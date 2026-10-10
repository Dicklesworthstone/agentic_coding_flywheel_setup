#!/usr/bin/env bash
# shellcheck disable=SC2329  # stub functions below are invoked indirectly by the sourced monitor
# Unit checks for the pure helpers in scripts/checksum-monitor-local.sh:
# the Bun version floor and the fail-closed alert deduplication (#355).
# The monitor is sourced with ACFS_MONITOR_LIBRARY_ONLY=1, which defines its
# functions and state paths and returns before taking the lock.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MONITOR="$REPO_ROOT/scripts/checksum-monitor-local.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -f "$MONITOR" ]] || fail "missing checksum monitor script"

# The monitor binds coreutils at /usr/bin (its deployment target is the
# maintainer's Linux host); on other layouts the helpers cannot be sourced.
if [[ ! -x /usr/bin/date || ! -x /usr/bin/mkdir || ! -x /usr/bin/tee ]]; then
    printf 'SKIP: checksum monitor helpers require the Linux /usr/bin coreutils layout\n'
    exit 0
fi

STATE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/acfs-monitor-test.XXXXXX")"
trap 'rm -rf "$STATE_TMP"' EXIT

# Sourcing forces PATH to the monitor's system prefixes; run in a subshell so
# the assertions below keep this shell's environment.
(
    set -euo pipefail
    export ACFS_MONITOR_STATE="$STATE_TMP/state"
    export ACFS_MONITOR_REPO="$STATE_TMP/does-not-exist"
    # The alert path also pushes to ntfy when this is set; gh is stubbed below
    # but curl is not, so a maintainer shell that exports the topic must not
    # send a live notification from a unit test.
    unset ACFS_NTFY_TOPIC
    ACFS_MONITOR_LIBRARY_ONLY=1
    # shellcheck source=../checksum-monitor-local.sh
    source "$MONITOR"

    [[ "$(type -t bun_version_is_acceptable)" == "function" ]] \
        || fail "bun_version_is_acceptable not defined"
    [[ "$(type -t _fail_alert_due)" == "function" ]] \
        || fail "_fail_alert_due not defined"
    [[ "$STATE" == "INIT" ]] || fail "library-only sourcing advanced the state machine to $STATE"
    [[ ! -e "$ACFS_MONITOR_STATE/monitor.lock" ]] \
        || fail "library-only sourcing took the monitor lock"

    # ---- Bun floor -------------------------------------------------------
    [[ "$MINIMUM_BUN_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || fail "MINIMUM_BUN_VERSION is not X.Y.Z: $MINIMUM_BUN_VERSION"
    ! grep -q '^EXPECTED_BUN_VERSION=' "$MONITOR" \
        || fail "exact-version Bun pin is back (EXPECTED_BUN_VERSION); use the floor"

    accept() {
        bun_version_is_acceptable "$1" "$2" \
            || fail "expected bun $1 to satisfy floor $2"
    }
    reject() {
        ! bun_version_is_acceptable "$1" "$2" \
            || fail "expected bun $1 to be rejected against floor $2"
    }
    accept 1.4.0 1.4.0
    accept 1.4.1 1.4.0        # the auto-upgrade that failed the monitor closed
    accept 1.4.2 1.4.0
    accept 1.4.10 1.4.9       # numeric, not lexical
    accept 1.5.0 1.4.0
    accept 1.10.0 1.9.3
    reject 1.3.9 1.4.0        # downgrade
    reject 0.9.0 1.4.0        # older major
    reject 2.0.0 1.4.0        # newer major: lockfile/generator contract unproven
    reject 1.4.1-canary.3 1.4.0
    reject "1.4" 1.4.0
    reject "" 1.4.0
    reject "unavailable" 1.4.0
    reject "1.4.2 (34cbb9a40)" 1.4.0
    reject 1.4.2 "bogus"      # a corrupt floor never accepts anything

    # ---- pinned Bun binary metadata (#433: name the failing condition) -----
    [[ "$(type -t bun_binary_unsafe_reason)" == "function" ]] \
        || fail "bun_binary_unsafe_reason not defined"
    bun_case() {
        # bun_case NAME -> fresh dir/bun (0755, nlink 1) under the state tmp
        local root="$STATE_TMP/bun-$1"
        mkdir -p "$root/bin"
        chmod 0755 "$root" "$root/bin"
        printf '#!/bin/sh\n' > "$root/bin/bun"
        chmod 0755 "$root/bin/bun"
        printf '%s\n' "$root/bin/bun"
    }
    trusted() {
        local reason=""
        reason="$(bun_binary_unsafe_reason "$1")" || fail "expected trusted Bun at $1, got: $reason"
        [[ -z "$reason" ]] || fail "trusted Bun printed a reason: $reason"
    }
    untrusted() {
        local reason=""
        ! reason="$(bun_binary_unsafe_reason "$1")" || fail "expected untrusted Bun at $1"
        [[ "$reason" == *"$2"* ]] || fail "expected reason containing '$2', got: $reason"
    }

    b="$(bun_case plain)"; trusted "$b"
    b="$(bun_case bunx-hardlink)"; ln "$b" "${b%/*}/bunx"; trusted "$b"
    b="$(bun_case bunx-symlink)"; ln -s "$b" "${b%/*}/bunx"; trusted "$b"
    b="$(bun_case symlinked)"; mv "$b" "$b.real"; ln -s "$b.real" "$b"
    untrusted "$b" "missing or unsafe"
    b="$(bun_case missing)"; rm -f -- "$b"; untrusted "$b" "missing or unsafe"
    b="$(bun_case dir-writable)"; chmod 0775 "${b%/*}"
    untrusted "$b" "directory is group/world writable (mode 775)"
    b="$(bun_case bin-writable)"; chmod 0775 "$b"
    untrusted "$b" "binary is group/world writable (mode 775)"
    b="$(bun_case three-links)"; ln "$b" "${b%/*}/bunx"; ln "$b" "$STATE_TMP/bun-three-links/snapshot"
    untrusted "$b" "has 3 hard links"
    b="$(bun_case foreign-link)"; ln "$b" "$STATE_TMP/bun-foreign-link/elsewhere"
    untrusted "$b" "second hard link that is not the sibling bunx"
    untrusted "$b" "locate it with: sudo find / -xdev -inum $(stat -c '%i' -- "$b")"
    b="$(bun_case foreign-link-symlinked-bunx)"; ln -s "$b" "${b%/*}/bunx"
    ln "$b" "$STATE_TMP/bun-foreign-link-symlinked-bunx/elsewhere"
    untrusted "$b" "second hard link that is not the sibling bunx"
    # Owner checks need a second uid; covered by review, not fixtured here.
    grep -q 'bun_unsafe_reason="$(bun_binary_unsafe_reason "$BUN_BIN")"' "$MONITOR" \
        || fail "the monitor no longer gates on bun_binary_unsafe_reason"

    # ---- alert dedupe ----------------------------------------------------
    due() {
        _fail_alert_due "$@" || fail "expected alert to be due for: $*"
    }
    not_due() {
        ! _fail_alert_due "$@" || fail "expected alert NOT to be due for: $*"
    }
    now=1000000
    not_due 1 "reason A" "$now"
    not_due 2 "reason A" "$now"
    due 3 "reason A" "$now"                       # threshold, nothing posted yet
    _fail_alert_record "reason A" "$now"
    [[ -f "$FAIL_ALERT_FILE" ]] || fail "alert record not written"
    not_due 4 "reason A" "$((now + 60))"          # same reason, minutes later
    not_due 27 "reason A" "$((now + 6 * 3600))"   # the old every-24-runs cadence
    not_due 96 "reason A" "$((now + 86399))"      # just under a day
    due 97 "reason A" "$((now + 86400))"          # a day: one repeat
    due 5 "reason B" "$((now + 60))"              # the failure changed
    _fail_alert_record "reason B" "$((now + 60))"
    not_due 6 "reason B" "$((now + 120))"
    due 7 "reason A" "$((now + 180))"             # changed back: still news
    not_due 2 "reason C" "$((now + 200000))"      # below threshold regardless

    # A corrupt record never silences alerts.
    printf 'garbage\n' > "$FAIL_ALERT_FILE"
    due 3 "reason A" "$now"
    rm -f -- "$FAIL_ALERT_FILE"

    # ---- recovery note clears the alert record ---------------------------
    # gh is reached through run_failure_bounded (timeout + external gh), so a
    # shell-function stub for gh alone would NOT intercept it and the test
    # would post to the live issue. Stub the bounded runner itself and record
    # every gh invocation instead of executing it.
    GH_CALLS="$STATE_TMP/gh-calls"
    : > "$GH_CALLS"
    run_failure_bounded() {
        printf '%s\n' "$*" >> "$GH_CALLS"
        # `gh issue list` finds no open issue; everything else is a no-op.
        return 0
    }
    hostname() { printf 'test-host\n'; }
    LOG_FILE="$STATE_TMP/log"
    _fail_alert_record "reason A" "$now"
    _announce_recovery 2 || fail "_announce_recovery below threshold must not fail"
    [[ -f "$FAIL_ALERT_FILE" ]] || fail "recovery below the alert threshold must not touch the alert record"
    [[ ! -s "$GH_CALLS" ]] || fail "recovery below the alert threshold must not talk to GitHub"
    _announce_recovery 3 || fail "_announce_recovery at threshold failed"
    [[ -f "$FAIL_ALERT_FILE" && ! -s "$FAIL_ALERT_FILE" ]] || fail "recovery did not reset the alert record"
    due 3 "reason A" "$now"                       # next streak alerts again immediately
    grep -q '^gh issue list ' "$GH_CALLS" || fail "recovery did not look up the monitoring issue"
    ! grep -q '^gh issue comment ' "$GH_CALLS" || fail "recovery commented although no open issue was found"
    ! grep -q '^gh issue create ' "$GH_CALLS" || fail "recovery must never open an issue"

    # With an open monitoring issue, the recovery note is a single comment.
    : > "$GH_CALLS"
    run_failure_bounded() {
        printf '%s\n' "$*" >> "$GH_CALLS"
        case "$*" in
            "gh issue list "*) printf '355\n' ;;
        esac
        return 0
    }
    _announce_recovery 1008 || fail "_announce_recovery with an open issue failed"
    [[ "$(grep -c '^gh issue comment 355 ' "$GH_CALLS")" == "1" ]] \
        || fail "expected exactly one recovery comment on the open issue"
    grep -q 'recovered on test-host after 1008 consecutive fail-closed runs' "$GH_CALLS" \
        || fail "recovery comment text missing host/streak"

    # The fail-closed alert path posts through the same runner: an alert that
    # is not due must not call gh at all; a due alert posts once and records.
    : > "$GH_CALLS"
    _fail_alert_record "reason A" "$now"
    date() { printf '%s\n' "$((now + 60))"; }
    _alert_fail_closed_streak 4 "reason A"
    [[ ! -s "$GH_CALLS" ]] || fail "duplicate alert reached GitHub"
    _alert_fail_closed_streak 5 "reason B"
    [[ "$(grep -c '^gh issue comment 355 ' "$GH_CALLS")" == "1" ]] \
        || fail "changed reason did not produce exactly one alert comment"
    IFS=$'\t' read -r rec_epoch rec_reason < "$FAIL_ALERT_FILE"
    [[ "$rec_reason" == "reason B" ]] || fail "alert record not updated to the posted reason (got: $rec_reason)"
    unset -f date
) || exit 1

# The service unit still executes this script directly from the clone.
grep -q '^ExecStart=%h/acfs-monitor/scripts/checksum-monitor-local.sh$' \
    "$REPO_ROOT/scripts/templates/acfs-checksum-monitor.service" \
    || fail "service template no longer runs the monitor script"

printf 'PASS: checksum monitor accepts newer same-major Bun and deduplicates fail-closed alerts\n'
