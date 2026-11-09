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
printf 'Retaining checksum monitor test fixtures: %s\n' "$STATE_TMP" >&2

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

    # ---- public GitHub text --------------------------------------------
    [[ "$(HOME=/home/mon public_text 'clone not found at /home/mon/acfs-monitor; see /home/mon/.local/state/x')" \
        == 'clone not found at ~/acfs-monitor; see ~/.local/state/x' ]] || fail "public_text kept the home path"
    [[ "$(HOME=/home/mon public_text '/home/mon2/x /home/monitor')" == '/home/mon2/x /home/monitor' ]] \
        || fail "public_text rewrote a path outside the home directory"
    [[ "$(HOME=/ public_text '/usr/bin/x')" == '/usr/bin/x' ]] || fail "public_text rewrote paths for HOME=/"
    # Commit authors and issue text are public: the only $(hostname) use is the private push.
    [[ "$(grep -c '$(hostname' "$MONITOR")" == 1 ]] && grep -q 'local push_msg=.*$(hostname' "$MONITOR" \
        || fail "the monitor names its host outside the private push"

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
    accept_recovery() {
        printf '%s\n' "$1" > "$FAIL_STREAK_FILE"
        STATE=REMOTE_VERIFIED
        record_accepted_monitor_outcome "${2:-ok}"
    }
    _fail_alert_record "reason A" "$now"
    accept_recovery 2 || fail "accepted recovery below threshold must not fail"
    [[ -f "$FAIL_ALERT_FILE" ]] || fail "accepted recovery lost the alert record"
    [[ ! -s "$GH_CALLS" ]] || fail "recovery below the alert threshold must not talk to GitHub"
    accept_recovery 3 || fail "accepted recovery at threshold failed"
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
    accept_recovery 1008 || fail "accepted recovery with an open issue failed"
    [[ "$(grep -c '^gh issue comment 355 ' "$GH_CALLS")" == "1" ]] \
        || fail "expected exactly one recovery comment on the open issue"
    grep -q 'Previously recorded fail-closed streak: 1008' "$GH_CALLS" \
        || fail "recovery comment does not distinguish its historical streak"
    ! grep -q 'test-host' "$GH_CALLS" || fail "public recovery comment names the host"

    # The fail-closed alert path posts through the same runner: an alert that
    # is not due must not call gh at all; a due alert posts once and records.
    : > "$GH_CALLS"
    _fail_alert_record "reason A" "$now"
    # Bash functions see their caller's locals: _fail_alert_due has its own
    # empty `now`, so calculate the fixture clock before entering that scope.
    alert_test_epoch=$((now + 60))
    date() { printf '%s\n' "$alert_test_epoch"; }
    _alert_fail_closed_streak 4 "reason A"
    [[ ! -s "$GH_CALLS" ]] || fail "duplicate alert reached GitHub"
    _alert_fail_closed_streak 5 "reason B"
    [[ "$(grep -c '^gh issue comment 355 ' "$GH_CALLS")" == "1" ]] \
        || fail "changed reason did not produce exactly one alert comment"
    grep -qF "Run: $RUN_TS." "$GH_CALLS" || fail 'public alert has no exact run locator'
    saved_run_ts="$RUN_TS"
    RUN_TS=20261108T111700Z
    _alert_fail_closed_streak 6 "reason B"
    [[ "$(grep -c '^gh issue comment 355 ' "$GH_CALLS")" == "1" ]] \
        || fail 'a different run timestamp bypassed unchanged-reason deduplication'
    RUN_TS="$saved_run_ts"
    IFS=$'\t' read -r rec_epoch rec_reason < "$FAIL_ALERT_FILE"
    [[ "$rec_reason" == "reason B" ]] || fail "alert record not updated to the posted reason (got: $rec_reason)"
    unset -f date

    # ---- independent channel delivery and retries -----------------------
    # Both network entry points are intercepted before enabling a fake topic.
    # No unit test may send a real push or invoke the authenticated gh CLI.
    CURL_CALLS="$STATE_TMP/curl-calls"
    : > "$CURL_CALLS"
    : > "$GH_CALLS"
    : > "$FAIL_ALERT_FILE"
    push_record="$STATE_DIR/fail_closed_push_alert"
    fake_time=$((now + 120))
    CURL_RESULT=0
    GH_RESULT=1
    curl() {
        printf '%s\n' "$*" >> "$CURL_CALLS"
        return "$CURL_RESULT"
    }
    run_failure_bounded() {
        printf '%s\n' "$*" >> "$GH_CALLS"
        [[ "$GH_RESULT" == 0 ]] || return "$GH_RESULT"
        [[ "$*" == "gh issue list "* ]] && printf '355\n'
        return 0
    }
    date() { printf '%s\n' "$fake_time"; }
    export ACFS_NTFY_TOPIC=private-test-topic
    call_count() { grep -c '^-' "$CURL_CALLS" || true; }
    gh_count() { grep -c '^gh issue' "$GH_CALLS" || true; }

    HOME="$STATE_TMP" _alert_fail_closed_streak 3 "push-only reason"
    first_gh_count=$(gh_count)
    grep -q 'test-host' "$CURL_CALLS" || fail "private push does not name the host"
    grep -qF "Run: $RUN_TS." "$CURL_CALLS" || fail 'private push has no exact run locator'
    grep -qF "See $LOG_DIR." "$CURL_CALLS" || fail "private push does not give the log directory"
    grep -qF "Run: $RUN_TS." "$GH_CALLS" || fail 'public alert has no exact run locator'
    grep -qF 'See ~/state/logs on the monitor host.' "$GH_CALLS" || fail "GitHub alert lost the log directory"
    ! grep -qF "$STATE_TMP" "$GH_CALLS" || fail "public GitHub alert names the home directory"
    grep -q 'push-only reason' "$GH_CALLS" || fail "GitHub alert body missing the reason"
    ! grep -q 'test-host' "$GH_CALLS" || fail "public GitHub alert names the host"
    fake_time=$((fake_time + 60))
    _alert_fail_closed_streak 4 "push-only reason"
    [[ "$(call_count)" == 1 ]] || fail "successful push repeated while GitHub failed"
    (( $(gh_count) > first_gh_count )) || fail "push cooldown silenced failed GitHub retries"
    IFS=$'\t' read -r rec_epoch rec_reason < "$push_record"
    [[ "$rec_reason" == "push-only reason" ]] || fail "push success was not recorded"
    [[ ! -s "$FAIL_ALERT_FILE" ]] || fail "failed GitHub delivery was recorded as success"

    GH_RESULT=0
    _alert_fail_closed_streak 5 "push-only reason"
    [[ "$(call_count)" == 1 ]] || fail "GitHub recovery repeated a delivered push"
    IFS=$'\t' read -r rec_epoch rec_reason < "$FAIL_ALERT_FILE"
    [[ "$rec_reason" == "push-only reason" ]] || fail "successful GitHub retry was not recorded"
    delivered_gh_count=$(gh_count)
    _alert_fail_closed_streak 6 "push-only reason"
    [[ "$(gh_count)" == "$delivered_gh_count" && "$(call_count)" == 1 ]] \
        || fail "delivered channels were retried inside their cooldowns"

    _alert_fail_closed_streak 7 "changed reason"
    [[ "$(call_count)" == 2 ]] || fail "changed reason did not notify push channel"
    changed_gh_count=$(gh_count)
    fake_time=$((fake_time + 86399))
    _alert_fail_closed_streak 8 "changed reason"
    [[ "$(call_count)" == 2 && "$(gh_count)" == "$changed_gh_count" ]] \
        || fail "channel cooldown expired before 24h"
    fake_time=$((fake_time + 1))
    _alert_fail_closed_streak 9 "changed reason"
    [[ "$(call_count)" == 3 ]] || fail "push channel did not repeat at daily boundary"
    (( $(gh_count) > changed_gh_count )) || fail "GitHub channel did not repeat at daily boundary"

    CURL_RESULT=22
    GH_RESULT=1
    _alert_fail_closed_streak 10 "failed reason"
    failed_gh_count=$(gh_count)
    _alert_fail_closed_streak 11 "failed reason"
    [[ "$(call_count)" == 5 ]] || fail "failed pushes were not retried"
    (( $(gh_count) > failed_gh_count )) || fail "failed GitHub posts were not retried"
    IFS=$'\t' read -r rec_epoch rec_reason < "$push_record"
    [[ "$rec_reason" == "changed reason" ]] || fail "failed push advanced the cooldown"

    GH_RESULT=0
    _alert_fail_closed_streak 12 "GitHub-only reason"
    github_only_count=$(gh_count)
    _alert_fail_closed_streak 13 "GitHub-only reason"
    [[ "$(call_count)" == 7 ]] || fail "GitHub success silenced failed push retries"
    [[ "$(gh_count)" == "$github_only_count" ]] || fail "failed push repeated a delivered GitHub post"
    accept_recovery 13 || fail 'accepted recovery failed while resetting both channels'
    [[ -f "$push_record" && ! -s "$push_record" && ! -s "$FAIL_ALERT_FILE" ]] \
        || fail "recovery did not reset both channel cooldowns"
    CURL_RESULT=0
    GH_RESULT=1
    _alert_fail_closed_streak 3 "GitHub-only reason"
    [[ "$(call_count)" == 8 ]] || fail "new streak was suppressed by the previous push cooldown"
    unset ACFS_NTFY_TOPIC
    unset -f date

    # Preserve the landed deferral/deduplication regression cases.
    hx() { printf '%064d\n' "$1"; }
    report_with() {
        local out="$STATE_TMP/report-$1-$2.json"
        jq -cn --arg ta "$(hx "$1")" --arg ea "$(hx "$2")" --arg te "$(hx 1)" --arg ee "$(hx 2)" '{
          mismatches: [
            {name: "ext", url: "https://example.com/ext.sh", expected: $ee, actual: $ea},
            {name: "own", url: "https://raw.githubusercontent.com/Dicklesworthstone/own/main/install.sh", expected: $te, actual: $ta}
          ]}' > "$out"
        printf '%s\n' "$out"
    }
    d1="$(external_authorization_digest "$(report_with 3 4)" ext)"
    [[ "$d1" =~ ^[0-9a-f]{64}$ ]] || fail "external digest is not a sha256: $d1"
    [[ "$(external_authorization_digest "$(report_with 5 4)" ext)" == "$d1" ]] \
        || fail "a trusted repin changed the pending external authorization digest"
    [[ "$(external_authorization_digest "$(report_with 3 6)" ext)" != "$d1" ]] \
        || fail "different external bytes reused an authorization digest"

    policy() {
        printf '# checksums.yaml - Auto-generated %s\n# Run: ./scripts/lib/security.sh --update-checksums\n\ninstallers:\n' "$1" > "$1"
        printf '  ext:\n    url: "https://example.com/ext.sh"\n    sha256: "%s"\n\n' "$(hx "$2")" >> "$1"
        printf '  own:\n    url: "https://raw.githubusercontent.com/Dicklesworthstone/own/main/install.sh"\n    sha256: "%s"\n\n' "$(hx "$3")" >> "$1"
        printf '  stable:\n    url: "https://example.com/stable.sh"\n    sha256: "%s"\n' "$(hx "$4")" >> "$1"
    }
    cur="$STATE_TMP/cur.yaml"; raw="$STATE_TMP/raw.yaml"; want="$STATE_TMP/want.yaml"
    policy "$cur" 2 1 7
    policy "$raw" 4 3 8
    restrict_checksum_candidate "$cur" "$raw" own > "$STATE_TMP/got.yaml" \
        || fail "restrict_checksum_candidate failed"
    policy "$want" 2 3 7
    diff <(tail -n +2 "$STATE_TMP/got.yaml") <(tail -n +2 "$want") >/dev/null \
        || fail "restricted candidate did not keep unapplied installers at their current pins"
    [[ "$(head -1 "$STATE_TMP/got.yaml")" == "$(head -1 "$raw")" ]] \
        || fail "restricted candidate lost the generator header"
    restrict_checksum_candidate "$cur" "$raw" ext own > "$STATE_TMP/got-both.yaml"
    policy "$want" 4 3 7
    diff <(tail -n +2 "$STATE_TMP/got-both.yaml") <(tail -n +2 "$want") >/dev/null \
        || fail "authorized external change was not applied"

    run_bounded() {
        printf '%s\n' "$*" >> "$GH_CALLS"
        case "$*" in
            "45 gh issue list "*)
                printf '%s\n' "$ISSUE_CANDIDATES"
                return "${ISSUE_LOOKUP_EXIT:-0}"
                ;;
        esac
        return 0
    }
    EXTERNAL_CHANGED=(ext)
    BASE_HEAD=0000000000000000000000000000000000000000
    VERIFICATION_REPORT_SHA256="$(hx 9)"
    RUN_TS=unit
    authorization_mode=aggregate
    : > "$GH_CALLS"; ISSUE_CANDIDATES='[]'
    HOME="$STATE_TMP" record_external_review "$(report_with 3 4)" "$d1" required || fail "record_external_review failed"
    grep -q -- '--state all' "$GH_CALLS" || fail "authorization lookup ignores closed issues"
    grep -q -- '--json number,body' "$GH_CALLS" || fail 'authorization lookup cannot bind the primary digest and scope'
    review_body="$(grep -o -- '--body-file [^ ]*' "$GH_CALLS" | tail -n 1 | cut -d' ' -f2)"
    grep -qF 'place exactly this line in `~/state/authorized-checksum-change`' "$review_body" \
        || fail "authorization issue does not say where the authorization file goes"
    ! grep -qF "$STATE_TMP" "$review_body" || fail "public authorization issue names the home directory"
    [[ "$(grep -c ' gh issue create ' "$GH_CALLS")" == 1 ]] || fail "first pending request did not open one issue"
    legacy_review_body="$(printf -- '- Authorization digest: `%s`\n' "$d1")"
    ISSUE_CANDIDATES="$(jq -cn --arg body "$legacy_review_body" '[{number:446,body:$body}]')"
    : > "$GH_CALLS"
    record_external_review "$(report_with 3 4)" "$d1" required || fail "record_external_review failed"
    ! grep -qE ' gh issue (comment|create) ' "$GH_CALLS" || fail "a still-pending authorization was re-posted"
    record_external_review "$(report_with 3 4)" "$d1" authorized || fail "record_external_review failed"
    [[ "$(grep -c ' gh issue comment 446 ' "$GH_CALLS")" == 1 ]] || fail "authorized use was not recorded on the issue"

    # A subset issue may quote the aggregate digest as supporting evidence.
    # Search ordering and incidental references must not identify its scope.
    other_digest="$(hx 8)"
    incidental_body="$(printf -- '- Authorization digest: `%s`\n- Authorization scope: `subset`\n- Aggregate observation digest (separate review): `%s`\n' "$other_digest" "$d1")"
    wrong_scope_body="$(printf -- '- Authorization digest: `%s`\n- Authorization scope: `subset`\n' "$d1")"
    ISSUE_CANDIDATES="$(jq -cn --arg incidental "$incidental_body" --arg wrong "$wrong_scope_body" --arg exact "$legacy_review_body" \
        '[{number:500,body:$incidental},{number:501,body:$wrong},{number:446,body:$exact}]')"
    : > "$GH_CALLS"
    record_external_review "$(report_with 3 4)" "$d1" authorized || fail 'exact aggregate issue lookup failed'
    grep -q ' gh issue comment 446 ' "$GH_CALLS" || fail 'aggregate review was not matched by its exact primary digest'
    ! grep -qE ' gh issue comment (500|501) ' "$GH_CALLS" || fail 'incidental or differently scoped digest captured an authorization'

    for ambiguous_review in duplicate-digest duplicate-scope invalid-number; do
        case "$ambiguous_review" in
            duplicate-digest) ambiguous_body="$legacy_review_body"$'\n'"$legacy_review_body" ;;
            duplicate-scope) ambiguous_body="$legacy_review_body"$'\n- Authorization scope: `aggregate`\n- Authorization scope: `aggregate`' ;;
            invalid-number) ambiguous_body="$legacy_review_body" ;;
        esac
        ISSUE_CANDIDATES="$(jq -cn --arg body "$ambiguous_body" --arg kind "$ambiguous_review" \
            '[{number:(if $kind == "invalid-number" then 0 else 500 end),body:$body}]')"
        : > "$GH_CALLS"
        record_external_review "$(report_with 3 4)" "$d1" authorized || fail "$ambiguous_review prevented a fresh exact review"
        ! grep -q ' gh issue comment ' "$GH_CALLS" || fail "$ambiguous_review was accepted as an exact review"
        [[ "$(grep -c ' gh issue create ' "$GH_CALLS")" == 1 ]] || fail "$ambiguous_review did not open a fresh exact review"
    done
    for malformed_lookup in not-json '{}' $'[]\n[]'; do
        ISSUE_CANDIDATES="$malformed_lookup"
        : > "$GH_CALLS"
        ! record_external_review "$(report_with 3 4)" "$d1" authorized || fail 'malformed issue lookup was treated as an empty result'
        ! grep -qE ' gh issue (comment|create) ' "$GH_CALLS" || fail 'malformed lookup emitted an authorization message'
    done
    ISSUE_CANDIDATES='[]'; ISSUE_LOOKUP_EXIT=1; : > "$GH_CALLS"
    ! record_external_review "$(report_with 3 4)" "$d1" authorized || fail 'failed issue lookup was treated as an empty result'
    ! grep -qE ' gh issue (comment|create) ' "$GH_CALLS" || fail 'failed lookup emitted an authorization message'
    ISSUE_LOOKUP_EXIT=0

    authorization_mode=subset
    authorized_external_changed=ext
    deferred_changed=grok
    aggregate_authorization_digest="$other_digest"
    selected_authorization_record="authorize-subset:$d1:ext"
    ISSUE_CANDIDATES="$(jq -cn --arg aggregate "$legacy_review_body" --arg subset "$wrong_scope_body" \
        '[{number:446,body:$aggregate},{number:447,body:$subset}]')"
    : > "$GH_CALLS"
    record_external_review "$(report_with 3 4)" "$d1" authorized || fail 'exact subset issue lookup failed'
    grep -q ' gh issue comment 447 ' "$GH_CALLS" || fail 'subset review did not select the exact subset scope'
    ! grep -q ' gh issue comment 446 ' "$GH_CALLS" || fail 'subset review was recorded on the aggregate issue'
    review_body="$(grep -o -- '--body-file [^ ]*' "$GH_CALLS" | tail -n 1 | cut -d' ' -f2)"
    grep -qF -- '- Authorization scope: `subset`' "$review_body" || fail 'subset issue omitted its authorization scope'
    grep -qF -- '- Deferred external tools: `grok`' "$review_body" || fail 'subset issue concealed deferred tools'
    grep -qF "$selected_authorization_record" "$review_body" || fail 'subset issue omitted the exact selected record'
    : > "$GH_CALLS"
    record_external_review "$(report_with 3 4)" "$d1" required || fail 'pending subset issue lookup failed'
    ! grep -qE ' gh issue (comment|create) ' "$GH_CALLS" || fail 'pending subset review was re-posted'
    printf 'PASS: exact digest and scope review lookup, legacy deduplication and lookup failure guards\n'
) || exit 1

# The subset record is a canonical private byte string, distinct from legacy
# aggregate authorization. Parsing alone never validates the selected digest.
(
    export ACFS_MONITOR_STATE="$STATE_TMP/subset-record-state"
    export ACFS_MONITOR_REPO="$STATE_TMP/does-not-exist"
    unset ACFS_NTFY_TOPIC
    ACFS_MONITOR_LIBRARY_ONLY=1
    # shellcheck source=../checksum-monitor-local.sh
    source "$MONITOR"
    subset_digest="$(printf '%064d' 1)"
    canonical_record="authorize-subset:$subset_digest:atuin,omp,uv"
    printf '%s\n' "$canonical_record" > "$AUTHORIZATION_FILE"
    chmod 600 "$AUTHORIZATION_FILE"
    [[ "$(read_subset_authorization_record)" == "$canonical_record" ]] || fail 'canonical subset record rejected'
    subset_authorization_is_valid "$canonical_record" 600 || fail 'exact subset record/mode rejected'
    ! authorization_is_valid "$subset_digest" || fail 'subset grant was reinterpreted as legacy aggregate approval'
    chmod 400 "$AUTHORIZATION_FILE"
    [[ "$(read_subset_authorization_record)" == "$canonical_record" ]] || fail 'read-only private record cannot be read'
    ! subset_authorization_is_valid "$canonical_record" 600 || fail 'owner-only mode replacement retained selected authority'
    for record_case in no-lf crlf extra-line trailing-space nul duplicate unsorted empty uppercase oversize public symlink hardlink legacy used; do
        AUTHORIZATION_FILE="$STATE_DIR/record-$record_case"
        if [[ "$record_case" == symlink || "$record_case" == hardlink ]]; then
            record_target="$STATE_DIR/target-$record_case"
            printf '%s\n' "$canonical_record" > "$record_target"
            chmod 600 "$record_target"
            if [[ "$record_case" == symlink ]]; then ln -s "$record_target" "$AUTHORIZATION_FILE"; else ln "$record_target" "$AUTHORIZATION_FILE"; fi
        else
            printf '%s\n' "$canonical_record" > "$AUTHORIZATION_FILE"
            chmod 600 "$AUTHORIZATION_FILE"
            case "$record_case" in
                no-lf) printf '%s' "$canonical_record" > "$AUTHORIZATION_FILE" ;;
                crlf) printf '%s\r\n' "$canonical_record" > "$AUTHORIZATION_FILE" ;;
                extra-line) printf '%s\nignored\n' "$canonical_record" > "$AUTHORIZATION_FILE" ;;
                trailing-space) printf '%s \n' "$canonical_record" > "$AUTHORIZATION_FILE" ;;
                nul) printf '%s\0\n' "$canonical_record" > "$AUTHORIZATION_FILE" ;;
                duplicate) printf 'authorize-subset:%s:atuin,omp,omp\n' "$subset_digest" > "$AUTHORIZATION_FILE" ;;
                unsorted) printf 'authorize-subset:%s:uv,atuin\n' "$subset_digest" > "$AUTHORIZATION_FILE" ;;
                empty) printf 'authorize-subset:%s:\n' "$subset_digest" > "$AUTHORIZATION_FILE" ;;
                uppercase) printf 'authorize-subset:%s:Atuin\n' "$subset_digest" > "$AUTHORIZATION_FILE" ;;
                oversize) { printf 'authorize-subset:%s:' "$subset_digest"; printf 'a%.0s' {1..4096}; printf '\n'; } > "$AUTHORIZATION_FILE" ;;
                public) chmod 644 "$AUTHORIZATION_FILE" ;;
                legacy) printf 'authorize:%s\n' "$subset_digest" > "$AUTHORIZATION_FILE" ;;
                used) printf 'used-subset:%s:atuin,omp,uv:%040d\n' "$subset_digest" 1 > "$AUTHORIZATION_FILE" ;;
            esac
        fi
        ! read_subset_authorization_record > "$STATE_DIR/$record_case-output" \
            || fail "noncanonical or unsafe subset record accepted: $record_case"
    done
    printf 'PASS: canonical private subset records, exact mode binding and aggregate separation\n'
) || exit 1

# Retained first-observation evidence is independently rehashed before it can
# support publication. Use inert binary fixtures, never execute their bodies.
(
    export ACFS_MONITOR_STATE="$STATE_TMP/download-evidence-state"
    export ACFS_MONITOR_REPO="$STATE_TMP/does-not-exist"
    unset ACFS_NTFY_TOPIC
    ACFS_MONITOR_LIBRARY_ONLY=1
    # shellcheck source=../checksum-monitor-local.sh
    source "$MONITOR"
    CURRENT_CHECKSUMS_SHA256="$(printf 'a%.0s' {1..64})"
    for evidence_case in valid body wire headers missing symlink hardlink file-mode directory-mode \
        wrong-name wrong-url extra-field traversal extra-tool late-body late-wire late-headers index-tamper index-mode; do
        run_dir="$(mktemp -d "$STATE_TMP/evidence-$evidence_case.XXXXXX")"
        evidence_root="$(mktemp -d "$run_dir/acfs-observations.XXXXXX")"
        observation="$evidence_root/fixture"
        mkdir -m 700 "$observation"
        (
            umask 077
            printf '#!/bin/sh\n# inert bytes\000with trailing newlines\n\n' > "$observation/body"
            cp "$observation/body" "$observation/body.wire"
            printf 'HTTP/2 200\r\nContent-Type: text/plain\r\nSet-Cookie: private-test-cookie\r\n\r\n' \
                > "$observation/body.headers"
            body_hash="$(sha256_file "$observation/body")"
            header_hash="$(sha256_file "$observation/body.headers")"
            jq -cn --arg actual "$body_hash" --arg headers "$header_hash" '{
                schema:"acfs.installer-download-evidence.v1",name:"fixture",url:"https://example.invalid/install.sh",
                expected:$actual,actual:$actual,status:"observed",bodySha256:$actual,wireSha256:$actual,headersSha256:$headers
            }' > "$observation/metadata.json"
            jq -cn --arg actual "$body_hash" '{matches:[{name:"fixture",url:"https://example.invalid/install.sh",checksum:$actual}],mismatches:[]}' \
                > "$run_dir/report.json"
        )
        report="$run_dir/report.json"
        VERIFICATION_REPORT_SHA256="$(sha256_file "$report")"
        DOWNLOAD_EVIDENCE_INDEX_FILE=""
        DOWNLOAD_EVIDENCE_INDEX_SHA256=""
        case "$evidence_case" in
            body) printf '\nchanged' >> "$observation/body" ;;
            wire) printf '\nchanged' >> "$observation/body.wire" ;;
            headers) printf '\r\nchanged' >> "$observation/body.headers" ;;
            missing) mv "$observation/body" "$observation/body.saved" ;;
            symlink)
                mv "$observation/body" "$observation/body.saved"
                ln -s "$observation/body.saved" "$observation/body"
                ;;
            hardlink) ln "$observation/body" "$run_dir/body-link" ;;
            file-mode) chmod 644 "$observation/body.headers" ;;
            directory-mode) chmod 755 "$observation" ;;
            wrong-name|wrong-url|extra-field)
                case "$evidence_case" in
                    wrong-name) filter='.name = "someone_else"' ;;
                    wrong-url) filter='.url = "https://example.invalid/other.sh"' ;;
                    extra-field) filter='.path = "../../outside"' ;;
                esac
                jq -c "$filter" "$observation/metadata.json" > "$run_dir/changed-metadata.json"
                cat "$run_dir/changed-metadata.json" > "$observation/metadata.json"
                ;;
            traversal)
                jq -c '.matches[0].name = "../../outside"' "$report" > "$run_dir/changed-report.json"
                report="$run_dir/changed-report.json"
                VERIFICATION_REPORT_SHA256="$(sha256_file "$report")"
                ;;
            extra-tool) mkdir -m 700 "$evidence_root/unreported" ;;
        esac
        if [[ "$evidence_case" == valid || "$evidence_case" == index-* || "$evidence_case" == late-* ]]; then
            validate_download_evidence "$report" "$run_dir" || fail "$evidence_case: valid evidence rejected"
            original_index="$DOWNLOAD_EVIDENCE_INDEX_SHA256"
            validate_download_evidence "$report" "$run_dir" "$original_index" || fail 'unchanged evidence recheck failed'
            if [[ "$evidence_case" == index-tamper ]]; then
                printf 'changed\n' > "$DOWNLOAD_EVIDENCE_INDEX_FILE"
            elif [[ "$evidence_case" == index-mode ]]; then
                chmod 644 "$DOWNLOAD_EVIDENCE_INDEX_FILE"
            elif [[ "$evidence_case" == late-body ]]; then
                printf '\nchanged' >> "$observation/body"
            elif [[ "$evidence_case" == late-wire ]]; then
                printf '\nchanged' >> "$observation/body.wire"
            elif [[ "$evidence_case" == late-headers ]]; then
                printf '\r\nchanged' >> "$observation/body.headers"
            else
                continue
            fi
            ! validate_download_evidence "$report" "$run_dir" "$original_index" \
                || fail "$evidence_case: original review index was not bound"
        else
            ! validate_download_evidence "$report" "$run_dir" \
                || fail "$evidence_case: unsafe evidence was accepted"
        fi
    done
    printf 'PASS: private download evidence binds body, raw response, headers, identity and original index\n'
) || exit 1

# Persisted numeric records must not abort fail_closed or silence delivery.
# Exercise each scenario independently so the incumbent's arithmetic failure
# cannot prevent the remaining regressions and positive controls from running.
numeric_case() (
    export ACFS_MONITOR_STATE="$STATE_TMP/numeric-$1"
    export ACFS_MONITOR_REPO="$STATE_TMP/no-live-repo"
    unset ACFS_NTFY_TOPIC
    ACFS_MONITOR_LIBRARY_ONLY=1
    # shellcheck source=../checksum-monitor-local.sh
    source "$MONITOR"
    calls="$STATE_DIR/calls"
    : > "$calls"
    run_failure_bounded() {
        printf '%s\n' "$*" >> "$calls"
        [[ "$*" == 'gh issue list '* ]] && printf '355\n'
        return 0
    }
    curl() { printf 'PUSH\n' >> "$calls"; }
    date() { printf '1000060\n'; }
    case "$1" in
        epoch-leading-zero)
            printf '0001000000\treason\n' > "$FAIL_ALERT_FILE"
            ! _fail_alert_due 4 reason 1000060 || fail 'decimal leading-zero epoch caused a duplicate alert'
            ;;
        epoch-eight)
            printf '08\treason\n' > "$FAIL_ALERT_FILE"
            _fail_alert_due 4 reason 1000060 || fail 'expired decimal epoch was silenced by octal parsing'
            ;;
        epoch-overflow)
            printf '18446744073710551616\treason\n' > "$FAIL_ALERT_FILE"
            _fail_alert_due 4 reason 1000060 || fail 'overflowed cooldown silenced alert'
            ;;
        epoch-future)
            printf '1000061\treason\n' > "$FAIL_ALERT_FILE"
            _fail_alert_due 4 reason 1000060 || fail 'future cooldown silenced alert'
            ;;
        epoch-normal)
            _fail_alert_record reason 1000000
            ! _fail_alert_due 2 other 9999999 || fail 'below-threshold alert became due'
            ! _fail_alert_due 4 reason 1086399 || fail 'cooldown expired before 24 hours'
            _fail_alert_due 4 reason 1086400 || fail '24-hour repeat was suppressed'
            ;;
        epoch-bad-clock)
            _fail_alert_record reason 1000000
            for bad_clock in 0 broken 18446744073710551616; do
                _fail_alert_due 4 reason "$bad_clock" || fail 'bad clock silenced alert'
                _fail_alert_record reason "$bad_clock"
                [[ "$(cat "$FAIL_ALERT_FILE")" == $'1000000\treason' ]] || fail 'bad clock poisoned the delivery record'
            done
            ;;
        counter-zero|counter-overflow|counter-long|counter-prefix|counter-binary|counter-limit|counter-normal|counter-invalid)
            case "$1" in
                counter-zero) raw=0008; expected=9 ;;
                counter-overflow) raw=9223372036854775807; expected=2147483647 ;;
                counter-long) printf -v raw '%0100d' 0; raw="${raw//0/9}"; expected=2147483647 ;;
                counter-prefix) printf -v raw '%0100d' 0; raw="${raw}8"; expected=2147483647 ;;
                counter-binary) raw=''; expected=1 ;;
                counter-limit) raw=2147483647; expected=2147483647 ;;
                counter-normal) raw=99; expected=100 ;;
                counter-invalid) raw=not-a-count; expected=1 ;;
            esac
            printf '%s\n' "$raw" > "$FAIL_STREAK_FILE"
            if [[ "$1" == counter-binary ]]; then
                printf '\0%.0s' {1..64} > "$FAIL_STREAK_FILE"
                printf '99\n' >> "$FAIL_STREAK_FILE"
            fi
            status=0
            ( fail_closed 'numeric regression' ) > "$STATE_DIR/failure.log" 2>&1 || status=$?
            [[ "$status" == 1 ]] || fail 'fail_closed lost its failure exit status'
            [[ "$(cat "$FAIL_STREAK_FILE")" == "$expected" ]] || fail "incorrect failure counter for $1"
            grep -q 'summary: result=fail_closed' "$STATE_DIR/failure.log" || fail 'fail_closed lost its summary'
            if (( expected >= 3 )); then
                grep -q '^gh issue comment 355 ' "$calls" || fail 'counted failure never reached alert delivery'
            else
                [[ ! -s "$calls" ]] || fail 'first failure bypassed the threshold'
            fi
            ;;
        recovery-leading-zero)
            printf '0008\n' > "$FAIL_STREAK_FILE"
            STATE=REMOTE_VERIFIED
            record_accepted_monitor_outcome ok || fail 'decimal recovery count failed'
            grep -q 'Previously recorded fail-closed streak: 8' "$calls" || fail 'recovery did not normalize decimal count'
            ;;
        future-channels)
            printf '1000061\treason\n' > "$FAIL_ALERT_FILE"
            printf '1000061\treason\n' > "$FAIL_PUSH_ALERT_FILE"
            export ACFS_NTFY_TOPIC=fixture-never-sent
            _alert_fail_closed_streak 4 reason
            _alert_fail_closed_streak 5 reason
            [[ "$(grep -c '^PUSH$' "$calls")" == 1 ]] || fail 'future push record was not repaired exactly once'
            [[ "$(grep -c '^gh issue comment 355 ' "$calls")" == 1 ]] || fail 'future GitHub record was not repaired exactly once'
            ;;
    esac
)
numeric_failures=0
for numeric_scenario in epoch-leading-zero epoch-eight epoch-overflow epoch-future epoch-normal epoch-bad-clock \
    counter-zero counter-overflow counter-long counter-prefix counter-binary counter-limit counter-normal counter-invalid \
    recovery-leading-zero future-channels; do
    if numeric_case "$numeric_scenario"; then
        printf 'PASS: numeric monitor state %s\n' "$numeric_scenario"
    else
        numeric_failures=$((numeric_failures + 1))
        printf 'FAIL: numeric monitor state %s\n' "$numeric_scenario" >&2
    fi
done

# Recovery is a separate notification obligation from accepted publication.
# Each case has fresh state; all network entry points are intercepted before
# a helper is called. Keep the fixtures, including malformed/link records.
recovery_case() (
    export ACFS_MONITOR_STATE="$STATE_TMP/recovery-$1"
    export ACFS_MONITOR_REPO="$STATE_TMP/no-live-repo"
    unset ACFS_NTFY_TOPIC
    ACFS_MONITOR_LIBRARY_ONLY=1
    # shellcheck source=../checksum-monitor-local.sh
    source "$MONITOR"
    RUN_TS=20261108T120000Z
    calls="$STATE_DIR/calls"
    comments="$STATE_DIR/comment-attempts"
    deliveries="$STATE_DIR/comment-deliveries"
    : > "$calls"
    : > "$comments"
    : > "$deliveries"
    GH_LOOKUP_STATUS=0
    GH_POST_STATUS=0
    GH_ISSUE_NUMBER=457
    fixture_recovery_transport() {
        printf '%s\t%s\n' "$STATE" "$*" >> "$calls"
        case "$*" in
            'gh issue list '*)
                [[ "$GH_LOOKUP_STATUS" == 0 ]] || return "$GH_LOOKUP_STATUS"
                printf '%s\n' "$GH_ISSUE_NUMBER"
                ;;
            'gh issue comment '*)
                printf '%s\n' "$*" >> "$comments"
                [[ "$GH_POST_STATUS" == 0 ]] || return "$GH_POST_STATUS"
                printf '%s\n' "$*" >> "$deliveries"
                ;;
            *) fail 'recovery attempted an unexpected command' ;;
        esac
    }
    run_failure_bounded() { fixture_recovery_transport "$@"; }
    gh() { fail 'recovery bypassed the bounded notification runner'; }
    curl() { fail 'recovery attempted an unexpected live push'; }
    hostname() { printf 'private-monitor-host\n'; }
    date() { printf '1000060\n'; }
    accepted() {
        STATE=REMOTE_VERIFIED
        record_accepted_monitor_outcome "$1"
    }
    pending_count() { _read_recovery_pending_streak; }
    comment_count() { wc -l < "$comments"; }
    seed_pending() {
        ( umask 077; printf '%s\n' "$1" > "$RECOVERY_PENDING_FILE" )
    }
    printf '3\n' > "$FAIL_STREAK_FILE"
    _fail_alert_record 'same incident' 1000000
    _fail_alert_record 'same incident' 1000000 "$FAIL_PUSH_ALERT_FILE"
    printf 'private-authorization-sentinel\n' > "$AUTHORIZATION_FILE"
    mkdir -m 700 "$STATE_DIR/retained-evidence"
    printf 'private-original-response-sentinel\n' > "$STATE_DIR/retained-evidence/body"
    protected_before="$(sha256sum "$AUTHORIZATION_FILE" "$STATE_DIR/retained-evidence/body")"

    case "$1" in
        deferred)
            accepted deferred || fail 'accepted deferred recovery failed'
            [[ "$STATE" == DEFERRED && "$(cat "$FAIL_STREAK_FILE")" == 0 ]] \
                || fail 'deferred recovery changed the accepted outcome or retained the failure streak'
            [[ "$(comment_count)" == 1 && "$(pending_count)" == 0 ]] \
                || fail 'deferred recovery did not deliver and acknowledge one notice'
            grep -q 'current state: DEFERRED' "$comments" || fail 'deferred recovery was not identified'
            grep -q 'Unapproved external checksum changes remain pinned pending human authorization' "$comments" \
                || fail 'deferred recovery falsely claimed external checksum authorization'
            ! grep -q 'current state: HEALTHY' "$comments" || fail 'deferred recovery was reported healthy'
            [[ ! -s "$FAIL_ALERT_FILE" && ! -s "$FAIL_PUSH_ALERT_FILE" ]] \
                || fail 'deferred recovery did not reset both channel cooldowns'
            ;;
        post-retry|lookup-retry)
            if [[ "$1" == post-retry ]]; then GH_POST_STATUS=75; else GH_LOOKUP_STATUS=75; fi
            accepted deferred || fail 'notification failure changed the accepted outcome'
            [[ "$STATE" == DEFERRED && "$(cat "$FAIL_STREAK_FILE")" == 0 && "$(pending_count)" == 3 ]] \
                || fail 'failed recovery delivery lost pending state or changed accepted health'
            [[ "$(stat -c '%a:%h:%u' "$RECOVERY_PENDING_FILE")" == "600:1:$(id -u)" ]] \
                || fail 'recovery obligation is not private, owned and singly linked'
            [[ ! -s "$FAIL_ALERT_FILE" && ! -s "$FAIL_PUSH_ALERT_FILE" ]] \
                || fail 'failed recovery delivery kept an old failure cooldown'
            _fail_alert_due 3 'same incident' 1000060 "$FAIL_ALERT_FILE" \
                || fail 'old GitHub cooldown would suppress a new incident'
            _fail_alert_due 3 'same incident' 1000060 "$FAIL_PUSH_ALERT_FILE" \
                || fail 'old push cooldown would suppress a new incident'
            [[ ! -s "$deliveries" ]] || fail 'failed notification was counted as delivered'
            if [[ "$1" == lookup-retry ]]; then
                [[ ! -s "$comments" ]] || fail 'failed issue lookup attempted a comment'
            fi
            GH_LOOKUP_STATUS=0
            GH_POST_STATUS=0
            RUN_TS=20261108T121500Z
            # A fresh shell-source loses process-local state but must retain
            # the delivery obligation even though the failure counter is zero.
            source "$MONITOR"
            # Sourcing reinstalls the production transport, so replace it
            # before invoking any helper that can deliver a notification.
            run_failure_bounded() { fixture_recovery_transport "$@"; }
            RUN_TS=20261108T121500Z
            accepted ok || fail 'accepted run did not retry pending recovery'
            [[ "$STATE" == HEALTHY && "$(pending_count)" == 0 && "$(wc -l < "$deliveries")" == 1 ]] \
                || fail 'successful recovery retry was not acknowledged exactly once'
            grep -q 'Run: 20261108T121500Z.' "$deliveries" || fail 'retry reported a stale accepted run'
            delivered_calls="$(wc -l < "$calls")"
            accepted ok || fail 'no-op accepted run failed after recovery acknowledgement'
            [[ "$(wc -l < "$calls")" == "$delivered_calls" ]] || fail 'acknowledged recovery was delivered again'
            ;;
        no-open-issue)
            for GH_ISSUE_NUMBER in '' null; do
                printf '3\n' > "$FAIL_STREAK_FILE"
                accepted ok || fail 'successful empty issue lookup failed accepted recovery'
                [[ "$(pending_count)" == 0 && ! -s "$comments" ]] \
                    || fail 'empty issue lookup retained a notice or created a comment'
            done
            ! grep -q 'gh issue create ' "$calls" || fail 'recovery created a new issue'
            ;;
        invalid-issue)
            for GH_ISSUE_NUMBER in 0 -1 0457 '457 458' $'457\n458' '--repo=elsewhere' 'not-a-number'; do
                printf '3\n' > "$FAIL_STREAK_FILE"
                accepted ok || fail 'invalid issue response invalidated accepted health'
                [[ "$(pending_count)" == 3 && ! -s "$comments" ]] \
                    || fail 'invalid issue identity was used or discarded the retry'
            done
            ;;
        premature)
            seed_pending 3
            guarded_before="$(sha256sum "$FAIL_STREAK_FILE" "$RECOVERY_PENDING_FILE" "$FAIL_ALERT_FILE" "$FAIL_PUSH_ALERT_FILE")"
            for STATE in INIT LOCKED CLEAN_BASE OBSERVED CANDIDATE_VALIDATED AUTHORIZED GENERATED STAGED COMMITTED ATOMIC_PUBLISHED; do
                ! record_accepted_monitor_outcome ok || fail 'unaccepted state recorded recovery'
                ! _announce_recovery 3 ok || fail 'unaccepted state delivered a queued recovery'
            done
            STATE=REMOTE_VERIFIED
            ! record_accepted_monitor_outcome fail_closed || fail 'invalid accepted outcome was accepted'
            STATE=DEFERRED
            ! _announce_recovery 3 ok || fail 'deferred state emitted healthy recovery'
            STATE=HEALTHY
            ! _announce_recovery 3 deferred || fail 'healthy state emitted deferred recovery'
            [[ ! -s "$calls" ]] || fail 'unverified state reached notification transport'
            [[ "$(sha256sum "$FAIL_STREAK_FILE" "$RECOVERY_PENDING_FILE" "$FAIL_ALERT_FILE" "$FAIL_PUSH_ALERT_FILE")" == "$guarded_before" ]] \
                || fail 'rejected recovery changed state or cooldown evidence'
            ;;
        transition-failure)
            advance_state() { return 1; }
            ! accepted ok || fail 'failed state transition was reported as accepted recovery'
            [[ "$STATE" == REMOTE_VERIFIED && "$(pending_count)" == 3 && ! -s "$calls" ]] \
                || fail 'failed state transition delivered or discarded pending recovery'
            ;;
        intervening-failure)
            printf '8\n' > "$FAIL_STREAK_FILE"
            GH_POST_STATUS=75
            accepted ok || fail 'first accepted recovery failed'
            [[ "$(pending_count)" == 8 ]] || fail 'initial pending notice lost its historical streak'
            prior_attempts="$(comment_count)"
            STATE=CLEAN_BASE
            status=0
            ( fail_closed 'new brief failure' ) > "$STATE_DIR/new-failure.log" 2>&1 || status=$?
            [[ "$status" == 1 && "$(cat "$FAIL_STREAK_FILE")" == 1 ]] \
                || fail 'new failure did not remain fail closed'
            [[ "$(comment_count)" == "$prior_attempts" && "$(pending_count)" == 8 ]] \
                || fail 'new failure delivered or discarded stale recovery state'
            GH_POST_STATUS=0
            RUN_TS=20261108T123000Z
            accepted deferred || fail 'recovery after brief intervening failure failed'
            grep -q 'Previously recorded fail-closed streak: 8' "$deliveries" \
                || fail 'historical outage was not identified as historical'
            grep -q 'current state: DEFERRED' "$deliveries" || fail 'retry did not report the latest accepted outcome'
            ! grep -q 'after 8 consecutive' "$deliveries" || fail 'old pending streak was claimed as the latest streak'
            ;;
        newer-streak)
            seed_pending 8
            printf '5\n' > "$FAIL_STREAK_FILE"
            accepted ok || fail 'new qualifying outage did not recover'
            grep -q 'Previously recorded fail-closed streak: 5' "$deliveries" \
                || fail 'new qualifying outage did not supersede the pending historical streak'
            ;;
        queue-write-failure|ack-write-failure)
            notice_writer="$(declare -f _write_monitor_notice_record)"
            notice_writer="${notice_writer/#_write_monitor_notice_record /fixture_write_monitor_notice_record }"
            eval "$notice_writer"
            fault="$1"
            _write_monitor_notice_record() {
                if [[ "$1" == "$RECOVERY_PENDING_FILE" ]]; then
                    [[ "$fault" != queue-write-failure || -z "$2" ]] || return 1
                    [[ "$fault" != ack-write-failure || -n "$2" ]] || return 1
                fi
                fixture_write_monitor_notice_record "$@"
            }
            accepted ok || fail 'notification persistence failure changed accepted health'
            [[ "$STATE" == HEALTHY && "$(cat "$FAIL_STREAK_FILE")" == 0 && "$(wc -l < "$deliveries")" == 1 ]] \
                || fail 'persistence failure suppressed immediate delivery or accepted health'
            grep -q 'WARNING: recovery notification' "$LOG_FILE" || fail 'notification persistence failure was silent'
            if [[ "$fault" == ack-write-failure ]]; then
                [[ "$(pending_count)" == 3 ]] || fail 'failed acknowledgement discarded the pending record'
                fault=none
                accepted ok || fail 'acknowledgement failure was not retryable'
                [[ "$(wc -l < "$deliveries")" == 2 && "$(pending_count)" == 0 ]] \
                    || fail 'at-least-once acknowledgement retry was not persisted'
            fi
            ;;
        malformed-record)
            printf '0\n' > "$FAIL_STREAK_FILE"
            for bad_record in shell multiline oversized nul leading-zero extra-newline short negative overflow; do
                case "$bad_record" in
                    shell) printf '$(touch %q)\n' "$STATE_DIR/record-was-executed" > "$RECOVERY_PENDING_FILE" ;;
                    multiline) printf '3\n4\n' > "$RECOVERY_PENDING_FILE" ;;
                    oversized) printf '%0100d\n' 3 > "$RECOVERY_PENDING_FILE" ;;
                    nul) printf '3\0\n' > "$RECOVERY_PENDING_FILE" ;;
                    leading-zero) printf '003\n' > "$RECOVERY_PENDING_FILE" ;;
                    extra-newline) printf '3\n\n' > "$RECOVERY_PENDING_FILE" ;;
                    short) printf '2\n' > "$RECOVERY_PENDING_FILE" ;;
                    negative) printf -- '-3\n' > "$RECOVERY_PENDING_FILE" ;;
                    overflow) printf '2147483648\n' > "$RECOVERY_PENDING_FILE" ;;
                esac
                chmod 600 "$RECOVERY_PENDING_FILE"
                malformed_before="$(sha256sum "$RECOVERY_PENDING_FILE")"
                ! _read_recovery_pending_streak >/dev/null 2>&1 || fail "$bad_record recovery record was trusted"
                accepted ok || fail "$bad_record recovery record invalidated accepted health"
                [[ ! -s "$calls" && ! -e "$STATE_DIR/record-was-executed" ]] \
                    || fail "$bad_record recovery record reached execution or notification"
                [[ "$(sha256sum "$RECOVERY_PENDING_FILE")" == "$malformed_before" ]] \
                    || fail "$bad_record recovery record was silently rewritten"
            done
            ;;
        mode-400|mode-644|mode-660|symlink|hardlink|directory|fifo)
            printf '0\n' > "$FAIL_STREAK_FILE"
            printf '3\n' > "$STATE_DIR/notice-target"
            chmod 600 "$STATE_DIR/notice-target"
            target_before="$(sha256sum "$STATE_DIR/notice-target")"
            case "$1" in
                mode-*) seed_pending 3; chmod "${1#mode-}" "$RECOVERY_PENDING_FILE" ;;
                symlink) ln -s "$STATE_DIR/notice-target" "$RECOVERY_PENDING_FILE" ;;
                hardlink) ln "$STATE_DIR/notice-target" "$RECOVERY_PENDING_FILE" ;;
                directory) mkdir "$RECOVERY_PENDING_FILE" ;;
                fifo) mkfifo -m 600 "$RECOVERY_PENDING_FILE" ;;
            esac
            metadata_before="$(stat -c '%F:%a:%h:%i' "$RECOVERY_PENDING_FILE")"
            # Bound the FIFO regression in a separate shell so a reader bug
            # cannot hang this suite waiting for a writer.
            reader_status=0
            ACFS_MONITOR_LIBRARY_ONLY=1 timeout 3 bash -c \
                'source "$1"; _read_recovery_pending_streak' bash "$MONITOR" \
                > "$STATE_DIR/unsafe-read.log" 2>&1 || reader_status=$?
            [[ "$reader_status" == 1 ]] || fail "$1 recovery record was trusted or blocked (exit $reader_status)"
            ! _write_monitor_notice_record "$RECOVERY_PENDING_FILE" '' || fail "$1 recovery record was overwritten"
            accepted ok || fail "$1 pending record invalidated accepted health"
            [[ ! -s "$calls" ]] || fail "$1 pending record caused a recovery notification"
            [[ "$(stat -c '%F:%a:%h:%i' "$RECOVERY_PENDING_FILE")" == "$metadata_before" \
                && "$(sha256sum "$STATE_DIR/notice-target")" == "$target_before" ]] \
                || fail "$1 pending record or link target changed"
            ;;
        write-allowlist)
            ! _write_monitor_notice_record "$AUTHORIZATION_FILE" 'replacement' || fail 'notification writer modified authorization'
            ! _write_monitor_notice_record "$STATE_DIR/unrelated" '' || fail 'notification writer accepted an unrelated path'
            ! _write_monitor_notice_record "$FAIL_ALERT_FILE" $'1000000\tforged\nextra\n' \
                || fail 'notification writer accepted a malformed failure delivery record'
            ! _write_monitor_notice_record "$RECOVERY_PENDING_FILE" $'3\n4\n' \
                || fail 'notification writer accepted noncanonical recovery state'
            [[ ! -e "$STATE_DIR/unrelated" && ! -s "$calls" ]] || fail 'notification writer escaped its state paths'
            ;;
        *) fail "unknown recovery scenario $1" ;;
    esac
    [[ "$(sha256sum "$AUTHORIZATION_FILE" "$STATE_DIR/retained-evidence/body")" == "$protected_before" ]] \
        || fail 'notification lifecycle changed authorization or original evidence'
    ! grep -qF "$STATE_TMP" "$comments" || fail 'public recovery leaked a private path'
    ! grep -qE 'private-monitor-host|private-authorization-sentinel|private-original-response-sentinel' "$comments" \
        || fail 'public recovery leaked host identity or private evidence'
)
recovery_failures=0
for recovery_scenario in deferred post-retry lookup-retry no-open-issue invalid-issue premature transition-failure \
    intervening-failure newer-streak queue-write-failure ack-write-failure malformed-record \
    mode-400 mode-644 mode-660 symlink hardlink directory fifo write-allowlist; do
    if recovery_case "$recovery_scenario"; then
        printf 'PASS: recovery lifecycle %s\n' "$recovery_scenario"
    else
        recovery_failures=$((recovery_failures + 1))
        printf 'FAIL: recovery lifecycle %s\n' "$recovery_scenario" >&2
    fi
done
[[ "$recovery_failures" == 0 ]] || exit 1

# Unexpected exits are exercised in separate Bash processes. Calling main in an
# `if`/`||` test here would disable its errexit semantics and hide the regression.
# Every injected exit happens at the first real state transition, before Git or
# upstream verification; only the acceptance boundary is advanced explicitly in
# the accepted-outcome cases. Network entry points are always intercepted.
lifecycle_runner="$STATE_TMP/lifecycle-runner.sh"
cat > "$lifecycle_runner" <<'LIFECYCLE_RUNNER'
#!/usr/bin/env bash
set -euo pipefail
monitor_source="$1"
lifecycle_root="$2"
lifecycle_scenario="$3"
export HOME="$lifecycle_root/home"
export ACFS_MONITOR_STATE="$HOME/state"
export ACFS_MONITOR_REPO="$lifecycle_root/no-repository"
export ACFS_MONITOR_LIBRARY_ONLY=1
unset ACFS_NTFY_TOPIC

if [[ "$lifecycle_scenario" == source-traps ]]; then
    trap 'printf "original trap\n" >> "$lifecycle_root/source-trap-fired"' EXIT
    trap ':' HUP INT TERM
    traps_before="$(trap -p EXIT HUP INT TERM)"
fi
# shellcheck source=../checksum-monitor-local.sh
source "$monitor_source"
if [[ "$lifecycle_scenario" == source-traps ]]; then
    [[ "$(trap -p EXIT HUP INT TERM)" == "$traps_before" ]]
    exit 0
fi

unexpected_transport() {
    printf '%s\n' "$*" >> "$lifecycle_root/unexpected-transport"
    return 97
}
git() { unexpected_transport git "$@"; }
gh() { unexpected_transport gh "$@"; }
run_bounded() { unexpected_transport run_bounded "$@"; }
run_clean_bounded() { unexpected_transport run_clean_bounded "$@"; }
run_bun_clean_bounded() { unexpected_transport run_bun_clean_bounded "$@"; }

if [[ "$lifecycle_scenario" == broken-log-transport-* ]]; then
    # Exercise the actual alert helper: a redirection failure used to prevent
    # even the mocked transport from being called when the log was unwritable.
    export ACFS_NTFY_TOPIC=fixture-topic
    curl() {
        printf 'push\n' >> "$lifecycle_root/transport-attempts"
        [[ "$lifecycle_scenario" != broken-log-transport-failure ]]
    }
    run_failure_bounded() {
        case "$*" in
            'gh issue list '*)
                printf 'lookup\n' >> "$lifecycle_root/transport-attempts"
                printf '457\n'
                ;;
            'gh issue comment '*)
                printf 'comment\n' >> "$lifecycle_root/transport-attempts"
                printf '%s\n' "$*" >> "$lifecycle_root/public-alerts"
                [[ "$lifecycle_scenario" != broken-log-transport-failure ]]
                ;;
            *) unexpected_transport "$@" ;;
        esac
    }
else
    _alert_fail_closed_streak() {
        printf '%s\t%s\n' "$1" "$2" >> "$lifecycle_root/alert-attempts"
        case "$lifecycle_scenario" in
            signal-during-failure-alert) kill -s TERM "$BASHPID" ;;
            log-and-alert-failure) return 75 ;;
        esac
        return 0
    }
fi

_announce_recovery() {
    printf '%s\t%s\n' "$1" "$2" >> "$lifecycle_root/recovery-attempts"
    case "$lifecycle_scenario" in
        accepted-term|accepted-deferred-term) kill -s TERM "$BASHPID" ;;
    esac
    return 0
}

case "$lifecycle_scenario" in
    mode-help) exec /usr/bin/bash "$monitor_source" --help ;;
    mode-diagnose) exec /usr/bin/bash "$monitor_source" --diagnose 20261108T110101Z ;;
    flock-contention) flock() { return 200; } ;;
    flock-error-one) flock() { return 1; } ;;
    flock-error-two) flock() { return 2; } ;;
    flock-error-usage) flock() { return 64; } ;;
    flock-unavailable) flock() { return 127; } ;;
    lock-open-failure) LOCK_FILE="$STATE_DIR/logs" ;;
esac

if [[ "$lifecycle_scenario" == broken-log || "$lifecycle_scenario" == log-and-alert-failure \
    || "$lifecycle_scenario" == broken-log-transport-* || "$lifecycle_scenario" == explicit-broken-log ]]; then
    LOG_FILE="$STATE_DIR/logs"
    if [[ "$lifecycle_scenario" == explicit-broken-log ]]; then
        fail_closed 'explicit fixture failure with unavailable log'
    fi
else
    injected=false
    LIFECYCLE_PRIVATE_COMMAND_SENTINEL() { return 73; }
    log() {
        if [[ "$*" == state=LOCKED && "$injected" == false ]]; then
            injected=true
            case "$lifecycle_scenario" in
                unexpected-nonzero) LIFECYCLE_PRIVATE_COMMAND_SENTINEL ;;
                unexpected-zero) exit 0 ;;
                nounset) printf '%s\n' "$LIFECYCLE_UNSET_VARIABLE" ;;
                signal-hup) kill -s HUP "$BASHPID" ;;
                signal-int) kill -s INT "$BASHPID" ;;
                signal-term) kill -s TERM "$BASHPID" ;;
                explicit-failure|signal-during-failure-alert) fail_closed 'explicit fixture failure' ;;
                subshell-nonzero) ( exit 73 ) ;;
                subshell-explicit) ( fail_closed 'child fixture failure' ) ;;
                substitution-explicit) discarded="$(fail_closed 'child fixture failure')" ;;
                subshell-signal) ( kill -s TERM "$BASHPID"; exit 96 ) ;;
                state-only-healthy) STATE=HEALTHY; exit 0 ;;
                ignored-child-accepted|accepted-ok|accepted-deferred|accepted-term|accepted-deferred-term|accepted-nonzero|acceptance-transition-failure)
                    if [[ "$lifecycle_scenario" == ignored-child-accepted ]]; then
                        ( fail_closed 'ignored child fixture failure' ) || true
                    fi
                    STATE=REMOTE_VERIFIED
                    outcome=ok
                    [[ "$lifecycle_scenario" != accepted-deferred* ]] || outcome=deferred
                    record_accepted_monitor_outcome "$outcome" || fail_closed 'accepted outcome recording failed'
                    [[ "$lifecycle_scenario" != accepted-nonzero ]] || exit 73
                    exit 0
                    ;;
                *) exit 96 ;;
            esac
            # Any injected signal unexpectedly ignored is a failed test rather
            # than permission to fall through to the production network path.
            exit 96
        fi
        if [[ "$lifecycle_scenario" == acceptance-transition-failure && "$*" == state=HEALTHY ]]; then
            return 74
        fi
        printf '[00:00:00] %s\n' "$*" >> "$LOG_FILE"
    }
fi

# This must remain a simple command, without a conditional-list wrapper.
checksum_monitor_main
LIFECYCLE_RUNNER

lifecycle_case() (
    lifecycle_scenario="$1"
    lifecycle_root="$(mktemp -d "$STATE_TMP/lifecycle-$lifecycle_scenario.XXXXXX")"
    mkdir -m 700 "$lifecycle_root/home" "$lifecycle_root/home/state"
    lifecycle_state="$lifecycle_root/home/state"
    printf '2\n' > "$lifecycle_state/fail_closed_streak"
    case "$lifecycle_scenario" in
        ignored-child-accepted|accepted-*|acceptance-transition-failure)
            printf '3\n' > "$lifecycle_state/fail_closed_streak"
            ;;
    esac
    printf 'private-authorization-sentinel\n' > "$lifecycle_state/authorized-checksum-change"
    printf 'private-original-observation-sentinel\n' > "$lifecycle_state/retained-observation"
    chmod 600 "$lifecycle_state/authorized-checksum-change" "$lifecycle_state/retained-observation"
    protected_before="$(sha256sum "$lifecycle_state/authorized-checksum-change" "$lifecycle_state/retained-observation")"
    held_lock=""
    if [[ "$lifecycle_scenario" == held-lock ]]; then
        exec {held_lock}>"$lifecycle_state/monitor.lock"
        flock -n "$held_lock" || fail 'could not prepare real contended lock'
    fi
    monitor_status=0
    timeout --signal=TERM --kill-after=2 8 bash "$lifecycle_runner" "$MONITOR" \
        "$lifecycle_root" "$lifecycle_scenario" > "$lifecycle_root/stdout" 2> "$lifecycle_root/stderr" \
        || monitor_status=$?
    if [[ -n "$held_lock" ]]; then
        exec {held_lock}>&-
    fi
    printf '%s\n' "$monitor_status" > "$lifecycle_root/exit-status"
    expected_status=1
    expected_streak=3
    expected_alerts=1
    expect_failure=true
    case "$lifecycle_scenario" in
        unexpected-nonzero|subshell-nonzero) expected_status=73 ;;
        signal-hup) expected_status=129 ;;
        signal-int) expected_status=130 ;;
        signal-term|subshell-signal) expected_status=143 ;;
        # The explicit failure has already claimed the terminal outcome. A
        # repeated signal during bounded delivery preserves that first cause
        # (exit 1); an initiating signal above still exits 128 + its number.
        signal-during-failure-alert) expected_status=1 ;;
        held-lock|flock-contention|source-traps|mode-help|mode-diagnose)
            expected_status=0; expected_streak=2; expected_alerts=0; expect_failure=false
            ;;
        accepted-ok|accepted-deferred|ignored-child-accepted)
            expected_status=0; expected_streak=0; expected_alerts=0; expect_failure=false
            ;;
        accepted-term|accepted-deferred-term)
            expected_status=143; expected_streak=0; expected_alerts=0; expect_failure=false
            ;;
        accepted-nonzero)
            expected_status=73; expected_streak=0; expected_alerts=0; expect_failure=false
            ;;
        acceptance-transition-failure) expected_streak=1 ;;
        broken-log-transport-*) expected_alerts=0 ;;
    esac
    [[ "$monitor_status" == "$expected_status" ]] \
        || fail "$lifecycle_scenario: expected exit $expected_status, found $monitor_status"
    [[ "$(cat "$lifecycle_state/fail_closed_streak")" == "$expected_streak" ]] \
        || fail "$lifecycle_scenario: failure was lost or counted more than once"
    alert_count=0
    [[ ! -f "$lifecycle_root/alert-attempts" ]] || alert_count="$(wc -l < "$lifecycle_root/alert-attempts")"
    [[ "$alert_count" == "$expected_alerts" ]] \
        || fail "$lifecycle_scenario: expected $expected_alerts alert attempts, found $alert_count"
    [[ ! -e "$lifecycle_root/unexpected-transport" ]] \
        || fail "$lifecycle_scenario reached a live verification/publication transport boundary"
    [[ "$(sha256sum "$lifecycle_state/authorized-checksum-change" "$lifecycle_state/retained-observation")" == "$protected_before" ]] \
        || fail "$lifecycle_scenario changed authorization or original observation evidence"
    if [[ -f "$lifecycle_root/alert-attempts" ]]; then
        ! grep -q 'LIFECYCLE_PRIVATE_COMMAND_SENTINEL' "$lifecycle_root/alert-attempts" \
            || fail 'unexpected-exit notification disclosed the failing command'
        ! grep -q 'child fixture failure' "$lifecycle_root/alert-attempts" \
            || fail 'parent unexpected-exit notification disclosed a child failure reason'
    fi
    shopt -s nullglob
    lifecycle_logs=("$lifecycle_state"/logs/run-*.log)
    log_summaries=0
    child_details=0
    for lifecycle_log in "${lifecycle_logs[@]}"; do
        found="$(grep -c 'summary: result=fail_closed' "$lifecycle_log" || true)"
        log_summaries=$((log_summaries + found))
        found="$(grep -c 'subprocess failed closed: .*child fixture failure' "$lifecycle_log" || true)"
        child_details=$((child_details + found))
    done
    stderr_summaries="$(grep -c 'summary: result=fail_closed' "$lifecycle_root/stderr" || true)"
    if [[ "$expect_failure" == true ]]; then
        [[ "$log_summaries" -le 1 && "$stderr_summaries" -le 1 \
            && ( "$log_summaries" == 1 || "$stderr_summaries" == 1 ) ]] \
            || fail "$lifecycle_scenario did not retain exactly one terminal failure summary per sink"
    else
        [[ "$log_summaries" == 0 && "$stderr_summaries" == 0 ]] \
            || fail "$lifecycle_scenario fabricated a terminal failure summary"
    fi
    case "$lifecycle_scenario" in
        subshell-explicit|substitution-explicit|ignored-child-accepted)
            [[ "$child_details" == 1 ]] || fail 'child failure reason was lost or duplicated in local evidence'
            ;;
    esac
    case "$lifecycle_scenario" in
        accepted-*|ignored-child-accepted)
            [[ "$(cat "$lifecycle_state/fail_closed_recovery_pending")" == 3 ]] \
                || fail "$lifecycle_scenario discarded or changed pending recovery during interruption"
            [[ "$(wc -l < "$lifecycle_root/recovery-attempts")" == 1 ]] \
                || fail "$lifecycle_scenario did not reach exactly one accepted recovery delivery"
            ;;
        acceptance-transition-failure)
            [[ ! -e "$lifecycle_root/recovery-attempts" ]] || fail 'failed acceptance delivered recovery'
            ;;
        source-traps)
            [[ "$(wc -l < "$lifecycle_root/source-trap-fired")" == 1 ]] \
                || fail 'library-only sourcing replaced the caller trap'
            ;;
        mode-help|mode-diagnose)
            [[ ! -e "$lifecycle_state/monitor.lock" ]] || fail 'diagnostic/help mode acquired the monitor lock'
            ;;
        broken-log-transport-*)
            [[ "$(grep -c '^push$' "$lifecycle_root/transport-attempts")" == 1 \
                && "$(grep -c '^lookup$' "$lifecycle_root/transport-attempts")" == 1 \
                && "$(grep -c '^comment$' "$lifecycle_root/transport-attempts")" == 1 ]] \
                || fail 'unavailable log suppressed or duplicated real alert transport attempts'
            if [[ "$lifecycle_scenario" == broken-log-transport-success ]]; then
                [[ -s "$lifecycle_state/fail_closed_alert" && -s "$lifecycle_state/fail_closed_push_alert" ]] \
                    || fail 'delivered alerts did not retain their independent cooldowns'
            else
                [[ ! -s "$lifecycle_state/fail_closed_alert" && ! -s "$lifecycle_state/fail_closed_push_alert" ]] \
                    || fail 'failed transports incorrectly suppressed the next alert retry'
            fi
            grep -q 'summary: result=fail_closed' "$lifecycle_root/stderr" \
                || fail 'unavailable log suppressed the terminal failure summary from stderr'
            ;;
    esac
)
lifecycle_failures=0
for lifecycle_scenario in unexpected-nonzero unexpected-zero nounset signal-hup signal-int signal-term \
    explicit-failure explicit-broken-log broken-log log-and-alert-failure signal-during-failure-alert \
    subshell-nonzero subshell-explicit substitution-explicit subshell-signal state-only-healthy \
    ignored-child-accepted accepted-ok accepted-deferred accepted-term accepted-deferred-term \
    accepted-nonzero acceptance-transition-failure held-lock flock-contention flock-error-one \
    flock-error-two flock-error-usage flock-unavailable lock-open-failure source-traps mode-help \
    mode-diagnose broken-log-transport-success broken-log-transport-failure; do
    if lifecycle_case "$lifecycle_scenario"; then
        printf 'PASS: monitor process lifecycle %s\n' "$lifecycle_scenario"
    else
        lifecycle_failures=$((lifecycle_failures + 1))
        printf 'FAIL: monitor process lifecycle %s\n' "$lifecycle_scenario" >&2
    fi
done
[[ "$lifecycle_failures" == 0 ]] || exit 1

# Mutable monitor records must never truncate an authorization/evidence alias.
# Run the actual lifecycle and delivery helpers in isolated, timed processes;
# every transport is intercepted and all rejected entries/temporary files stay
# in the fixtures. This block also runs unchanged against an incumbent monitor.
# BEGIN MONITOR_STATE_RECORD_REGRESSIONS
state_record_runner="$STATE_TMP/state-record-runner.sh"
cat > "$state_record_runner" <<'STATE_RECORD_RUNNER'
#!/usr/bin/env bash
set -euo pipefail
monitor="$1"
fixture_root="$2"
scenario="$3"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 97; }
export HOME="$fixture_root/home"
export ACFS_MONITOR_STATE="$HOME/state"
export ACFS_MONITOR_REPO="$fixture_root/no-live-repository"
mkdir -p "$HOME"
if [[ "$scenario" == parent-symlink ]]; then
    mkdir "$HOME/real-state"
    ln -s "$HOME/real-state" "$ACFS_MONITOR_STATE"
fi
unset ACFS_NTFY_TOPIC
ACFS_MONITOR_LIBRARY_ONLY=1
# shellcheck source=../checksum-monitor-local.sh
source "$monitor"
RUN_TS=20261108T120000Z
calls="$fixture_root/transport-attempts"
comments="$fixture_root/comment-attempts"
delivered="$fixture_root/comment-deliveries"
: > "$calls"
: > "$comments"
: > "$delivered"
GH_STATUS=0
PUSH_STATUS=0
run_failure_bounded() {
    printf '%s\n' "$*" >> "$calls"
    case "$*" in
        'gh issue list '*) printf '457\n' ;;
        'gh issue comment '*)
            printf '%s\n' "$*" >> "$comments"
            [[ "$GH_STATUS" == 0 ]] || return "$GH_STATUS"
            printf '%s\n' "$*" >> "$delivered"
            ;;
        *) fail 'mutable-state test reached an unexpected transport' ;;
    esac
}
curl() {
    printf 'PUSH\n' >> "$calls"
    [[ "$PUSH_STATUS" == 0 ]]
}
gh() { fail 'mutable-state test bypassed the bounded GitHub transport'; }
git() { fail 'mutable-state test reached repository publication'; }
hostname() { printf 'private-state-fixture-host\n'; }
date() { printf '1000060\n'; }
printf 'private-authorization-sentinel\n' > "$AUTHORIZATION_FILE"
printf 'private-original-evidence-sentinel\n' > "$fixture_root/original-evidence"
chmod 600 "$AUTHORIZATION_FILE" "$fixture_root/original-evidence"
protected_before="$(sha256sum "$AUTHORIZATION_FILE" "$fixture_root/original-evidence")"
protected_metadata="$(stat -c '%a:%u:%i' "$AUTHORIZATION_FILE" "$fixture_root/original-evidence")"

assert_protected() {
    [[ "$(sha256sum "$AUTHORIZATION_FILE" "$fixture_root/original-evidence")" == "$protected_before" \
        && "$(stat -c '%a:%u:%i' "$AUTHORIZATION_FILE" "$fixture_root/original-evidence")" == "$protected_metadata" ]] \
        || fail 'mutable monitor state changed authorization or original evidence'
    ! grep -qE 'private-authorization-sentinel|private-original-evidence-sentinel|private-state-fixture-host' "$comments" \
        || fail 'public failure alert disclosed retained evidence or host identity'
}
assert_unchanged() {
    [[ "$(stat -c '%F:%a:%h:%i' "$record")" == "$record_metadata" ]] \
        || fail 'unsafe record was silently replaced or its metadata changed'
    [[ "$(stat -c '%h' "$target")" == "$target_links" ]] \
        || fail 'unsafe alias target lost an evidence link'
    assert_protected
}
failed_run() {
    local status=0
    ( fail_closed 'state fixture failure' ) >> "$fixture_root/failure-output" 2>&1 || status=$?
    [[ "$status" == 1 ]] || fail "failed monitor lost its original exit status ($status)"
    grep -q 'FAIL-CLOSED: state fixture failure' "$fixture_root/failure-output" \
        || fail 'failure persistence error suppressed the original reason'
}
assert_unknown_count_alert() {
    grep -q 'consecutive failure count is unavailable' "$comments" \
        || fail 'unpersisted failure count stayed silent or lacked truthful diagnosis'
    ! grep -q 'times in a row' "$comments" || fail 'unpersisted count fabricated a consecutive streak'
    grep -q 'Checksum drift is NOT being monitored' "$comments" || fail 'failure alert claimed monitoring health'
}

case "$scenario" in
    failure-symlink|failure-hardlink|accepted-symlink|accepted-hardlink|github-symlink|github-hardlink|push-symlink|push-hardlink)
        operation="${scenario%-*}"
        case "$operation" in
            failure|accepted) record="$FAIL_STREAK_FILE"; target="$AUTHORIZATION_FILE" ;;
            github) record="$FAIL_ALERT_FILE"; target="$fixture_root/original-evidence" ;;
            push) record="$FAIL_PUSH_ALERT_FILE"; target="$fixture_root/original-evidence" ;;
        esac
        if [[ "$scenario" == *-symlink ]]; then ln -s "$target" "$record"; else ln "$target" "$record"; fi
        record_metadata="$(stat -c '%F:%a:%h:%i' "$record")"
        target_links="$(stat -c '%h' "$target")"
        case "$operation" in
            failure)
                failed_run
                assert_unchanged
                assert_unknown_count_alert
                ;;
            accepted)
                status=0
                (
                    STATE=REMOTE_VERIFIED
                    record_accepted_monitor_outcome ok
                    printf '%s\n' "$STATE" > "$fixture_root/accepted-state"
                ) > "$fixture_root/acceptance-output" 2>&1 || status=$?
                assert_unchanged
                [[ "$status" == 1 && ! -e "$fixture_root/accepted-state" ]] \
                    || fail 'unsafe failure-counter reset was declared healthy'
                ! grep -q 'completed an accepted run' "$comments" || fail 'rejected acceptance emitted recovery'
                grep -q 'failure-count state could not be safely read' "$fixture_root/acceptance-output" \
                    || fail 'rejected counter reset lost the failure reason'
                ;;
            github|push)
                _fail_alert_record 'state fixture failure' 1000060 "$record"
                assert_unchanged
                _fail_alert_due 4 'state fixture failure' 1000061 "$record" \
                    || fail 'unsafe cooldown suppressed the retry'
                ;;
        esac
        assert_unchanged
        ;;
    unsafe-mode|unsafe-directory|unsafe-fifo|unsafe-owner|parent-writable|parent-symlink)
        if [[ "$scenario" == parent-writable ]]; then chmod 0770 "$STATE_DIR"; fi
        for record in "$FAIL_STREAK_FILE" "$FAIL_ALERT_FILE" "$FAIL_PUSH_ALERT_FILE"; do
            if [[ "$record" == "$FAIL_STREAK_FILE" ]]; then content=$'8\n'; else content=$'1000060\tstate fixture failure\n'; fi
            case "$scenario" in
                unsafe-mode|unsafe-owner|parent-writable|parent-symlink)
                    printf '%s' "$content" > "$record"
                    if [[ "$scenario" == unsafe-mode ]]; then chmod 0666 "$record"; fi
                    if [[ "$scenario" == unsafe-owner ]]; then
                        other_uid=65534
                        [[ "$(id -u)" != "$other_uid" ]] || other_uid=65533
                        if ! chown "$other_uid" "$record" 2> "$fixture_root/chown-error"; then
                            printf 'SKIP: foreign-owner mutable-state fixture requires a mapped second uid\n'
                            exit 0
                        fi
                    fi
                    ;;
                unsafe-directory) mkdir "$record" ;;
                unsafe-fifo) mkfifo -m 600 "$record" ;;
            esac
            record_metadata="$(stat -c '%F:%a:%h:%i:%u' "$record")"
            record_before=""
            if [[ -f "$record" ]]; then record_before="$(sha256sum "$record")"; fi
            if [[ "$record" == "$FAIL_STREAK_FILE" ]]; then
                ! _read_failure_streak > "$fixture_root/unsafe-counter-output" \
                    || fail 'unsafe counter supplied a consecutive count'
                [[ ! -s "$fixture_root/unsafe-counter-output" ]] || fail 'unsafe counter was reported as an authoritative zero'
                ! _write_monitor_notice_record "$record" $'1\n' || fail 'unsafe counter was overwritten'
            else
                _fail_alert_due 4 'state fixture failure' 1000061 "$record" || fail 'unsafe cooldown silenced an alert'
                _fail_alert_record 'replacement' 1000061 "$record"
                ! _write_monitor_notice_record "$record" '' || fail 'unsafe cooldown reset was accepted'
            fi
            [[ "$(stat -c '%F:%a:%h:%i:%u' "$record")" == "$record_metadata" ]] \
                || fail 'unsafe state metadata was silently repaired'
            if [[ -n "$record_before" ]]; then
                [[ "$(sha256sum "$record")" == "$record_before" ]] || fail 'unsafe state bytes changed'
            fi
        done
        ;;
    legacy-failure|legacy-accepted|legacy-github|legacy-push)
        printf '2\n' > "$FAIL_STREAK_FILE"
        chmod 644 "$FAIL_STREAK_FILE"
        case "$scenario" in
            legacy-failure)
                failed_run
                [[ "$(cat "$FAIL_STREAK_FILE")" == 3 ]] || fail 'safe legacy count did not increment'
                grep -q 'failed closed 3 times in a row' "$comments" || fail 'known persisted count became unavailable'
                record="$FAIL_STREAK_FILE"
                ;;
            legacy-accepted)
                printf '3\n' > "$FAIL_STREAK_FILE"
                STATE=REMOTE_VERIFIED
                record_accepted_monitor_outcome ok
                [[ "$STATE" == HEALTHY && "$(cat "$FAIL_STREAK_FILE")" == 0 ]] || fail 'safe legacy recovery failed'
                grep -q 'Previously recorded fail-closed streak: 3' "$comments" || fail 'safe recovery lost its history'
                record="$FAIL_STREAK_FILE"
                ;;
            legacy-github|legacy-push)
                if [[ "$scenario" == legacy-github ]]; then record="$FAIL_ALERT_FILE"; else record="$FAIL_PUSH_ALERT_FILE"; fi
                printf '0001000000\told reason\n' > "$record"
                chmod 644 "$record"
                ! _fail_alert_due 4 'old reason' 1000060 "$record" || fail 'safe legacy cooldown was ignored'
                _fail_alert_record 'new reason' 1000060 "$record"
                ! _fail_alert_due 4 'new reason' 1000061 "$record" || fail 'delivered cooldown was not persisted'
                ;;
        esac
        [[ "$(stat -c '%a:%h:%u' "$record")" == "600:1:$(id -u)" ]] \
            || fail 'safe legacy record was not replaced with a private single-link record'
        ;;
    cooldown-nul|cooldown-extra-line|cooldown-extra-newline|cooldown-no-newline|cooldown-oversized|cooldown-tab|cooldown-control)
        for record in "$FAIL_ALERT_FILE" "$FAIL_PUSH_ALERT_FILE"; do
            case "$scenario" in
                cooldown-nul) printf '1000060\tstate\0 fixture failure\n' > "$record" ;;
                cooldown-extra-line) printf '1000060\tstate fixture failure\nuntrusted extra record\n' > "$record" ;;
                cooldown-extra-newline) printf '1000060\tstate fixture failure\n\n' > "$record" ;;
                cooldown-no-newline) printf '1000060\tstate fixture failure' > "$record" ;;
                cooldown-oversized)
                    printf '1000060\tstate fixture failure\n' > "$record"
                    printf '%0131072d' 0 >> "$record"
                    ;;
                cooldown-tab) printf '1000060\tstate fixture failure\t\n' > "$record" ;;
                cooldown-control) printf '1000060\tstate fixture failure\r\n' > "$record" ;;
            esac
            record_before="$(sha256sum "$record")"
            _fail_alert_due 4 'state fixture failure' 1000061 "$record" || fail 'malformed cooldown silenced an alert'
            [[ "$(sha256sum "$record")" == "$record_before" ]] || fail 'cooldown reader changed retained state'
        done
        ;;
    unsupported-reason|cooldown-byte-boundary|typed-write-grammar)
        _fail_alert_record 'old reason' 1000000
        record_before="$(sha256sum "$FAIL_ALERT_FILE")"
        case "$scenario" in
            unsupported-reason)
                printf -v oversized_reason '%05000d' 0
                for reason in $'embedded\nnewline' $'embedded\tseparator' $'embedded\rcarriage' $'embedded\001control' "$oversized_reason"; do
                    _fail_alert_record "$reason" 1000060
                    [[ "$(sha256sum "$FAIL_ALERT_FILE")" == "$record_before" ]] || fail 'unsupported reason was truncated or persisted'
                    _fail_alert_due 4 "$reason" 1000061 || fail 'unsupported reason suppressed its retry'
                done
                ;;
            cooldown-byte-boundary)
                printf -v reason '%04087d' 0
                _fail_alert_record "$reason" 1000060
                [[ "$(stat -c '%s' "$FAIL_ALERT_FILE")" == 4096 ]] || fail 'maximum valid cooldown was rejected'
                ! _fail_alert_due 4 "$reason" 1000061 || fail 'maximum valid cooldown did not deduplicate'
                record_before="$(sha256sum "$FAIL_ALERT_FILE")"
                reason="${reason}x"
                _fail_alert_record "$reason" 1000060
                [[ "$(sha256sum "$FAIL_ALERT_FILE")" == "$record_before" ]] || fail 'oversized cooldown replaced valid state'
                _fail_alert_due 4 "$reason" 1000061 || fail 'oversized reason was silently truncated into a duplicate'
                ;;
            typed-write-grammar)
                for content in $'01\n' $'-1\n' $'2147483648\n' $'1\n2\n' '1' ''; do
                    ! _write_monitor_notice_record "$FAIL_STREAK_FILE" "$content" || fail 'noncanonical failure count was written'
                done
                for content in $'0\treason\n' $'1000060\treason\nextra\n' $'1000060\treason\tother\n' $'1000060\treason' $'1000060\treason\r\n'; do
                    ! _write_monitor_notice_record "$FAIL_ALERT_FILE" "$content" || fail 'noncanonical delivered cooldown was written'
                done
                [[ "$(sha256sum "$FAIL_ALERT_FILE")" == "$record_before" ]] || fail 'rejected grammar modified previous cooldown'
                ! _write_monitor_notice_record "$AUTHORIZATION_FILE" $'1\n' || fail 'state writer accepted an authorization path'
                ;;
        esac
        ;;
    accepted-reset-failure)
        printf '3\n' > "$FAIL_STREAK_FILE"
        before="$(stat -c '%a:%h:%i' "$FAIL_STREAK_FILE"):$(sha256sum "$FAIL_STREAK_FILE")"
        mv() {
            [[ "${!#}" != "$FAIL_STREAK_FILE" ]] || return 75
            command mv "$@"
        }
        status=0
        (
            STATE=REMOTE_VERIFIED
            record_accepted_monitor_outcome ok
            printf '%s\n' "$STATE" > "$fixture_root/accepted-state"
        ) > "$fixture_root/acceptance-output" 2>&1 || status=$?
        [[ "$status" == 1 && ! -e "$fixture_root/accepted-state" ]] \
            || fail 'failed atomic counter reset was declared healthy'
        [[ "$(stat -c '%a:%h:%i' "$FAIL_STREAK_FILE"):$(sha256sum "$FAIL_STREAK_FILE")" == "$before" ]] \
            || fail 'failed accepted-run reset changed the previous counter'
        [[ "$(cat "$RECOVERY_PENDING_FILE")" == 3 ]] || fail 'failed accepted-run reset discarded pending recovery evidence'
        ! grep -q 'completed an accepted run' "$comments" || fail 'failed counter reset emitted recovery'
        grep -q 'healthy-state marker could not be written' "$fixture_root/acceptance-output" \
            || fail 'failed atomic reset lost its fail-closed reason'
        assert_unknown_count_alert
        ;;
    persist-mktemp-failure|persist-write-failure|persist-rename-failure)
        printf '2\n' > "$FAIL_STREAK_FILE"
        before="$(stat -c '%a:%h:%i' "$FAIL_STREAK_FILE"):$(sha256sum "$FAIL_STREAK_FILE")"
        case "$scenario" in
            persist-mktemp-failure) mktemp() { return 75; } ;;
            persist-write-failure)
                printf() {
                    if [[ "$#" == 2 && "$1" == '%s' && "$2" == $'3\n' ]]; then
                        builtin printf 'partial write'
                        return 75
                    fi
                    builtin printf "$@"
                }
                ;;
            persist-rename-failure) mv() { return 75; } ;;
        esac
        failed_run
        [[ "$(stat -c '%a:%h:%i' "$FAIL_STREAK_FILE"):$(sha256sum "$FAIL_STREAK_FILE")" == "$before" ]] \
            || fail 'failed replacement damaged the previous counter'
        assert_unknown_count_alert
        shopt -s nullglob
        staged=("$STATE_DIR"/notice-state.*)
        shopt -u nullglob
        if [[ "$scenario" == persist-mktemp-failure ]]; then
            [[ "${#staged[@]}" == 0 ]] || fail 'failed temporary creation claimed a retained stage'
        else
            [[ "${#staged[@]}" -ge 1 ]] || fail 'failed state replacement discarded temporary evidence'
            found=false
            for staged_record in "${staged[@]}"; do
                [[ "$(stat -c '%a' "$staged_record")" == 600 ]] || fail 'retained temporary record was public'
                case "$scenario:$(cat "$staged_record")" in
                    persist-write-failure:'partial write'|persist-rename-failure:3) found=true ;;
                esac
            done
            [[ "$found" == true ]] || fail 'failed staging bytes were not retained'
        fi
        ;;
    unavailable-dedup|unavailable-github-retry|unavailable-push-retry|unavailable-new-diagnosis)
        ln -s "$AUTHORIZATION_FILE" "$FAIL_STREAK_FILE"
        export ACFS_NTFY_TOPIC=fixture-never-sent
        case "$scenario" in
            unavailable-github-retry) GH_STATUS=75 ;;
            unavailable-push-retry) PUSH_STATUS=75 ;;
            unavailable-new-diagnosis)
                _fail_alert_record 'state fixture failure' 1000000
                _fail_alert_record 'state fixture failure' 1000000 "$FAIL_PUSH_ALERT_FILE"
                ;;
        esac
        failed_run
        failed_run
        if [[ "$scenario" == unavailable-github-retry || "$scenario" == unavailable-push-retry ]]; then
            GH_STATUS=0
            PUSH_STATUS=0
            failed_run
            failed_run
        fi
        assert_unknown_count_alert
        expected_comments=1
        expected_pushes=1
        [[ "$scenario" != unavailable-github-retry ]] || expected_comments=3
        [[ "$scenario" != unavailable-push-retry ]] || expected_pushes=3
        [[ "$(wc -l < "$comments")" == "$expected_comments" && "$(grep -c '^PUSH$' "$calls")" == "$expected_pushes" ]] \
            || fail 'unavailable-count alert lost independent delivered-channel cooldowns or retries'
        [[ "$(wc -l < "$delivered")" == 1 ]] || fail 'unavailable-count incident was not delivered exactly once in the fixture'
        ;;
    *) fail "unknown mutable-state scenario $scenario" ;;
esac
assert_protected
STATE_RECORD_RUNNER

state_record_failures=0
for state_record_scenario in failure-symlink failure-hardlink accepted-symlink accepted-hardlink \
    github-symlink github-hardlink push-symlink push-hardlink \
    unsafe-mode unsafe-directory unsafe-fifo unsafe-owner parent-writable parent-symlink \
    legacy-failure legacy-accepted legacy-github legacy-push \
    cooldown-nul cooldown-extra-line cooldown-extra-newline cooldown-no-newline cooldown-oversized cooldown-tab cooldown-control \
    unsupported-reason cooldown-byte-boundary typed-write-grammar \
    accepted-reset-failure persist-mktemp-failure persist-write-failure persist-rename-failure \
    unavailable-dedup unavailable-github-retry unavailable-push-retry unavailable-new-diagnosis; do
    state_record_root="$(mktemp -d "$STATE_TMP/mutable-$state_record_scenario.XXXXXX")"
    state_record_status=0
    timeout --signal=TERM --kill-after=2 10 bash "$state_record_runner" "$MONITOR" \
        "$state_record_root" "$state_record_scenario" > "$state_record_root/stdout" 2> "$state_record_root/stderr" \
        || state_record_status=$?
    if [[ "$state_record_status" == 0 ]]; then
        if grep -q '^SKIP:' "$state_record_root/stdout"; then
            cat "$state_record_root/stdout"
        else
            printf 'PASS: mutable monitor state %s\n' "$state_record_scenario"
        fi
    else
        state_record_failures=$((state_record_failures + 1))
        printf 'FAIL: mutable monitor state %s (exit %s; %s)\n' \
            "$state_record_scenario" "$state_record_status" "$state_record_root" >&2
        cat "$state_record_root/stderr" >&2
    fi
done
[[ "$state_record_failures" == 0 ]] || exit 1
# END MONITOR_STATE_RECORD_REGRESSIONS

# Opt-in full state-machine qualification uses an immutable source archive.
# Git's real SSH transport protocol is redirected to disposable bare fixtures;
# dependencies, cleanliness, strict validators, generation, atomic pushes and
# remote acceptance remain real. Upstream observations and issue delivery are
# deterministic fixtures, so this does not assert live GitHub acceptance.
if [[ -n "${ACFS_MONITOR_TEST_ARCHIVE:-}" ]]; then
    [[ -f "$ACFS_MONITOR_TEST_ARCHIVE" ]] || fail 'integration source archive missing'
    integration_bun="${ACFS_MONITOR_TEST_BUN_BIN:-$(command -v bun || printf '%s' "$HOME/.bun/bin/bun")}"
    [[ -x "$integration_bun" ]] || fail 'integration Bun unavailable; set ACFS_MONITOR_TEST_BUN_BIN'
    integration_root="$STATE_TMP/integration"
    integration_bun_cache="${BUN_INSTALL_CACHE_DIR:-$integration_root/home/.bun/install/cache}"
    mkdir -p "$integration_root/seed" "$integration_root/home"
    tar -xzf "$ACFS_MONITOR_TEST_ARCHIVE" -C "$integration_root/seed"
    # Default to the immutable archive's implementation. A separately captured
    # incumbent can run against these same fixtures for regression proof.
    integration_monitor="${ACFS_MONITOR_TEST_IMPLEMENTATION:-$integration_root/seed/scripts/checksum-monitor-local.sh}"
    [[ -f "$integration_monitor" && ! -L "$integration_monitor" ]] \
        || fail 'integration monitor implementation is missing or unsafe'
    cat > "$integration_root/transport.sh" <<'TRANSPORT'
#!/usr/bin/env bash
set -euo pipefail
bare="$1"
shift
case "${!#}" in
    'git-upload-pack '*) exec git-upload-pack "$bare" ;;
    'git-receive-pack '*) exec git-receive-pack "$bare" ;;
    *) exit 1 ;;
esac
TRANSPORT
    cat > "$integration_root/retain.sh" <<'RETAIN'
rm() { return 0; }
export -f rm
RETAIN
    (
        cd "$integration_root/seed" || exit 1
        # Actual fixture bytes back every policy pin. Invented digests cannot
        # qualify the independent first-observation evidence validator.
        fixture_hash="$(printf '#!/bin/sh\n# monitor match fixture\n' | sha256sum | awk '{print $1}')"
        awk -v hash="$fixture_hash" '
            /^    sha256: / { print "    sha256: \"" hash "\""; next }
            { print }
        ' checksums.yaml > "$integration_root/fixture-checksums.yaml"
        command cp "$integration_root/fixture-checksums.yaml" checksums.yaml
        BUN_INSTALL_CACHE_DIR="$integration_bun_cache" "$integration_bun" install \
            --cwd packages/manifest --frozen-lockfile --ignore-scripts --backend=hardlink --silent
        "$integration_bun" run packages/manifest/src/generate.ts > "$integration_root/seed-generation.log"
        git -c init.templateDir= init -q -b main
        git add -- .
        git -c core.hooksPath=/dev/null -c user.name='Monitor Test' -c user.email='monitor-test@example.invalid' \
            commit -qm 'Clean generated base'
        git branch master
    ) || fail 'could not prepare clean integration base'
    integration_cases=(pending external-only approved review-unavailable approved-review-unavailable push-rejected fetch-error
        authorization-revoked-before-commit authorization-revoked-before-push evidence-changed-before-push evidence-changed-after-push
        subset-approved subset-review-unavailable subset-stale subset-malformed subset-push-rejected
        subset-grant-replaced-before-push subset-mode-changed-before-push subset-grant-replaced-before-consumption)
    if [[ -n "${ACFS_MONITOR_TEST_CASE:-}" ]]; then
        integration_case_found=false
        for integration_case in "${integration_cases[@]}"; do
            if [[ "$integration_case" == "$ACFS_MONITOR_TEST_CASE" ]]; then integration_case_found=true; fi
        done
        [[ "$integration_case_found" == true ]] || fail 'unknown integration case requested'
        integration_cases=("$ACFS_MONITOR_TEST_CASE")
    fi
    for integration_case in "${integration_cases[@]}"; do
        (
            case_root="$integration_root/$integration_case"
            mkdir -p "$case_root/state/tmp"
            git clone --quiet --bare --no-hardlinks "$integration_root/seed" "$case_root/remote.git"
            git clone --quiet --no-hardlinks "$case_root/remote.git" "$case_root/repo"
            git -C "$case_root/repo" remote set-url origin git@github.com:Dicklesworthstone/agentic_coding_flywheel_setup.git
            git -C "$case_root/repo" config core.sshCommand "bash '$integration_root/transport.sh' '$case_root/remote.git'"
            git -C "$case_root/repo" config ssh.variant ssh
            export ACFS_MONITOR_REPO="$case_root/repo" ACFS_MONITOR_STATE="$case_root/state"
            HOME="$integration_root/home"
            export HOME
            unset ACFS_NTFY_TOPIC
            ACFS_MONITOR_LIBRARY_ONLY=1
            # shellcheck source=../checksum-monitor-local.sh
            source "$integration_monitor"
            # Reuse the selected real runtime even when fixture TMPDIR is on
            # a separate or noexec filesystem. Its production ownership/mode/
            # link/version checks still run inside checksum_monitor_main.
            BUN_BIN="$integration_bun"
            # shellcheck source=../lib/security.sh
            source "$REPO_ROOT/scripts/lib/security.sh"
            export ACFS_SECURITY_RETAIN_TEMP_FILES=true
            declare -A integration_urls=() integration_hashes=()
            acfs_load_checksums_strict "$case_root/repo/checksums.yaml" integration_urls integration_hashes
            integration_base="$(git -C "$case_root/repo" rev-parse HEAD)"
            integration_policy_digest="$(sha256_file "$case_root/repo/checksums.yaml")"
            integration_match_hash="$(printf '#!/bin/sh\n# monitor match fixture\n' | sha256sum | awk '{print $1}')"
            br_actual="$(printf '#!/bin/sh\n# monitor trusted fixture\n' | sha256sum | awk '{print $1}')"
            omp_actual="$(printf '#!/bin/sh\n# monitor external fixture\n' | sha256sum | awk '{print $1}')"
            atuin_actual="$(printf '#!/bin/sh\n# monitor Atuin fixture\n' | sha256sum | awk '{print $1}')"
            grok_actual="$(printf '#!/bin/sh\n# monitor Grok fixture\n' | sha256sum | awk '{print $1}')"
            uv_actual="$(printf '#!/bin/sh\n# monitor uv fixture\n' | sha256sum | awk '{print $1}')"
            for integration_tool in "${!integration_hashes[@]}"; do
                integration_actual="${integration_hashes[$integration_tool]}"
                if [[ "$integration_tool" == br && "$integration_case" != external-only ]]; then integration_actual="$br_actual"; fi
                if [[ "$integration_tool" == omp && "$integration_case" != evidence-changed-after-push ]]; then integration_actual="$omp_actual"; fi
                if [[ "$integration_case" == subset-* ]]; then
                    case "$integration_tool" in
                        atuin) integration_actual="$atuin_actual" ;;
                        grok) integration_actual="$grok_actual" ;;
                        uv) integration_actual="$uv_actual" ;;
                    esac
                fi
                jq -cn --arg name "$integration_tool" --arg url "${integration_urls[$integration_tool]}" \
                    --arg expected "${integration_hashes[$integration_tool]}" --arg actual "$integration_actual" \
                    '{name:$name,url:$url,expected:$expected,actual:$actual}'
            done > "$case_root/state/observations.jsonl"
            integration_report="$case_root/state/report.json"
            jq -cs --arg digest "$integration_policy_digest" '{
                schema:"acfs.installer-checksum-verification.v1", schemaVersion:1,
                timestamp:"2026-10-12T00:00:00Z", checksumsYamlSha256:$digest, total:length,
                matches:[.[] | select(.actual == .expected) | {name,url,checksum:.expected}],
                mismatches:[.[] | select(.actual != .expected)], errors:[], skipped:[]
            }' "$case_root/state/observations.jsonl" > "$integration_report"
            integration_digest="$(external_authorization_digest "$integration_report" omp)"
            case "$integration_case" in
                approved|approved-review-unavailable|push-rejected|authorization-revoked-before-commit|authorization-revoked-before-push)
                    printf 'authorize:%s\n' "$integration_digest" > "$AUTHORIZATION_FILE"
                    chmod 600 "$AUTHORIZATION_FILE"
                    ;;
            esac
            if [[ "$integration_case" == subset-* ]]; then
                bash "$REPO_ROOT/scripts/lib/security.sh" --review-checksum-subset \
                    "$case_root/repo/checksums.yaml" "$integration_report" atuin omp uv --retain-temp-files \
                    > "$case_root/state/subset-proposal.json" || fail 'could not produce the real subset review fixture'
                integration_subset_record="$(jq -er '.authorization_line' "$case_root/state/subset-proposal.json")" \
                    || fail 'subset review fixture has no authorization record'
                integration_digest="$(jq -er '.authorization_digest' "$case_root/state/subset-proposal.json")"
                printf '%s\n' "$integration_subset_record" > "$AUTHORIZATION_FILE"
                case "$integration_case" in
                    subset-stale) printf 'authorize-subset:%064d:atuin,omp,uv\n' 0 > "$AUTHORIZATION_FILE" ;;
                    subset-malformed) printf 'authorize-subset:%s:uv,omp,atuin\n' "$integration_digest" > "$AUTHORIZATION_FILE" ;;
                    subset-grant-replaced-before-push|subset-grant-replaced-before-consumption)
                        bash "$REPO_ROOT/scripts/lib/security.sh" --review-checksum-subset \
                            "$case_root/repo/checksums.yaml" "$integration_report" atuin omp --retain-temp-files \
                            > "$case_root/state/replacement-proposal.json" || fail 'could not produce a distinct valid grant'
                        jq -er '.authorization_line' "$case_root/state/replacement-proposal.json" \
                            > "$case_root/state/replacement-authorization" || fail 'replacement review fixture is invalid'
                        ;;
                esac
                chmod 600 "$AUTHORIZATION_FILE"
                cp "$AUTHORIZATION_FILE" "$case_root/state/initial-authorization"
            fi
            if [[ "$integration_case" == push-rejected || "$integration_case" == subset-push-rejected ]]; then
                printf '#!/usr/bin/env bash\nexit 1\n' > "$case_root/remote.git/hooks/pre-receive"
                chmod 755 "$case_root/remote.git/hooks/pre-receive"
            fi
            if [[ "$integration_case" == fetch-error ]]; then
                jq -c '.errors = [{name:.matches[0].name,url:.matches[0].url,error:"network failure"}] |
                    .matches |= .[1:]' "$integration_report" > "$case_root/state/error-report.json"
                integration_report="$case_root/state/error-report.json"
            fi
            record_external_review() {
                printf '%s\t%s\n' "$2" "$3" >> "$case_root/state/reviews.tsv"
                [[ "$integration_case" != review-unavailable && "$integration_case" != approved-review-unavailable \
                    && "$integration_case" != subset-review-unavailable ]]
            }
            _alert_fail_closed_streak() { return 0; }
            # A prior alerted outage makes every accepted run exercise the
            # real recovery lifecycle. Failed publication paths must never
            # reach this mocked transport, even after a remote push succeeded.
            printf '3\n' > "$FAIL_STREAK_FILE"
            run_failure_bounded() {
                printf '%s\t%s\n' "$STATE" "$*" >> "$case_root/state/recovery-calls"
                [[ "$STATE" == HEALTHY || "$STATE" == DEFERRED ]] \
                    || fail 'publication attempted recovery before accepted health'
                case "$*" in
                    'gh issue list '*) printf '457\n' ;;
                    'gh issue comment 457 '*) return 0 ;;
                    *) fail 'publication recovery attempted an unexpected command' ;;
                esac
            }
            # Delegate to the real remote reader before changing private state.
            # These deterministic interleavings occur after the last staging
            # check and are invisible to Git worktree/ref cleanliness checks.
            integration_remote_reader="$(declare -f read_remote_heads)"
            integration_remote_reader="${integration_remote_reader/#read_remote_heads /fixture_read_remote_heads }"
            [[ "$integration_remote_reader" == 'fixture_read_remote_heads ()'* ]] \
                || fail 'could not capture the actual remote reader'
            read_remote_heads() {
                fixture_read_remote_heads || return 1
                [[ ! -e "$case_root/state/boundary-mutation" ]] || return 0
                case "$integration_case:$STATE" in
                    authorization-revoked-before-commit:STAGED|authorization-revoked-before-push:COMMITTED)
                        printf 'revoked\n' > "$AUTHORIZATION_FILE" || return 1
                        ;;
                    subset-grant-replaced-before-push:COMMITTED)
                        cat "$case_root/state/replacement-authorization" > "$AUTHORIZATION_FILE" || return 1
                        ;;
                    subset-mode-changed-before-push:COMMITTED)
                        chmod 400 "$AUTHORIZATION_FILE" || return 1
                        ;;
                    evidence-changed-before-push:COMMITTED|evidence-changed-after-push:ATOMIC_PUBLISHED)
                        [[ -n "$DOWNLOAD_EVIDENCE_ROOT" && -f "$DOWNLOAD_EVIDENCE_ROOT/omp/body" ]] \
                            || fail 'missing retained body at the publication boundary'
                        printf '\n# changed after staging\n' >> "$DOWNLOAD_EVIDENCE_ROOT/omp/body" || return 1
                        ;;
                    *) return 0 ;;
                esac
                printf '%s\t%s\n' "$integration_case" "$STATE" > "$case_root/state/boundary-mutation"
            }
            integration_state_advancer="$(declare -f advance_state)"
            integration_state_advancer="${integration_state_advancer/#advance_state /fixture_advance_state }"
            [[ "$integration_state_advancer" == 'fixture_advance_state ()'* ]] \
                || fail 'could not capture the actual state transition helper'
            advance_state() {
                fixture_advance_state "$@" || return 1
                if [[ "$integration_case:$STATE" == subset-grant-replaced-before-consumption:REMOTE_VERIFIED ]]; then
                    cat "$case_root/state/replacement-authorization" > "$AUTHORIZATION_FILE" || return 1
                    printf '%s\t%s\n' "$integration_case" "$STATE" > "$case_root/state/boundary-mutation"
                fi
            }
            write_fixture_download_evidence() {
                local temp_root="$1" root="" name="" url="" expected="" actual="" dir="" header_hash=""
                root="$(mktemp -d "$temp_root/acfs-observations.XXXXXX")" || return 1
                while IFS=$'\t' read -r name url expected actual; do
                    dir="$root/$name"
                    mkdir -m 700 "$dir" || return 1
                    (
                        umask 077
                        case "$actual" in
                            "$integration_match_hash") printf '#!/bin/sh\n# monitor match fixture\n' ;;
                            "$br_actual") printf '#!/bin/sh\n# monitor trusted fixture\n' ;;
                            "$omp_actual") printf '#!/bin/sh\n# monitor external fixture\n' ;;
                            "$atuin_actual") printf '#!/bin/sh\n# monitor Atuin fixture\n' ;;
                            "$grok_actual") printf '#!/bin/sh\n# monitor Grok fixture\n' ;;
                            "$uv_actual") printf '#!/bin/sh\n# monitor uv fixture\n' ;;
                            *) exit 1 ;;
                        esac > "$dir/body" || exit 1
                        cp "$dir/body" "$dir/body.wire"
                        printf 'HTTP/2 200\r\nContent-Type: text/plain\r\n\r\n' > "$dir/body.headers"
                        header_hash="$(sha256_file "$dir/body.headers")"
                        jq -cn --arg name "$name" --arg url "$url" --arg expected "$expected" --arg actual "$actual" \
                            --arg headers "$header_hash" '{schema:"acfs.installer-download-evidence.v1",name:$name,url:$url,
                            expected:$expected,actual:$actual,status:"observed",bodySha256:$actual,wireSha256:$actual,headersSha256:$headers}' \
                            > "$dir/metadata.json"
                    ) || return 1
                done < <(jq -r '([.matches[] | {name,url,expected:.checksum,actual:.checksum}] + .mismatches)[] |
                    [.name,.url,.expected,.actual] | @tsv' "$integration_report")
            }
            run_clean_bounded() {
                local budget="$1" observation_tmp=""
                shift
                if [[ "${1:-}" == env && "${2:-}" == TMPDIR=* ]]; then
                    observation_tmp="${2#TMPDIR=}"
                    shift 2
                    [[ "${1:-}" == bash && "${2:-}" == scripts/lib/security.sh && "${3:-}" == --verify ]] \
                        || fail 'unexpected environment-wrapped command in monitor fixture'
                fi
                if [[ "${1:-}" == bash && "${2:-}" == scripts/lib/security.sh ]]; then
                    if [[ "${3:-}" == --verify ]]; then
                        [[ -n "$observation_tmp" && "${!#}" == --retain-temp-files ]] \
                            || fail 'monitor observation did not request private retained evidence'
                        printf 'observation\n' >> "$case_root/state/network-calls"
                        write_fixture_download_evidence "$observation_tmp" || fail 'could not create observation fixture'
                        cat "$integration_report"
                        return 1
                    fi
                    [[ "${3:-}" != --update-checksums ]] || fail 'monitor fetched a second installer snapshot'
                    set -- "$@" --retain-temp-files
                fi
                run_bounded "$budget" env -i HOME="$HOME" USER="${USER:-}" LOGNAME="${LOGNAME:-}" \
                    PATH="$MONITOR_EXEC_PATH:${BUN_BIN%/*}" LANG=C LC_ALL=C TZ=UTC CI=1 NO_COLOR=1 \
                    TMPDIR="$case_root/state/tmp" BASH_ENV="$integration_root/retain.sh" \
                    ACFS_SECURITY_RETAIN_TEMP_FILES=true "$@"
            }
            run_bun_clean_bounded() {
                local budget="$1"
                shift
                # Reuse the cache populated by the same frozen seed install.
                # This is fixture dependency preparation, not a substitute for
                # the real frozen/lifecycle-disabled install below.
                if [[ "${1:-}" == install ]]; then set -- "$@" --backend=hardlink; fi
                run_bounded "$budget" env -i HOME="$HOME" USER="${USER:-}" LOGNAME="${LOGNAME:-}" \
                    PATH="$MONITOR_EXEC_PATH:${BUN_BIN%/*}" LANG=C LC_ALL=C TZ=UTC CI=1 NO_COLOR=1 \
                    TMPDIR="$case_root/state/tmp" BASH_ENV="$integration_root/retain.sh" \
                    BUN_INSTALL_CACHE_DIR="$integration_bun_cache" "$BUN_BIN" "$@"
            }
            # Run in a fresh strict shell: putting a function/subshell on the
            # left of || would disable errexit inside the tested state machine.
            export case_root integration_root integration_case integration_report integration_match_hash br_actual omp_actual integration_bun_cache
            export atuin_actual grok_actual uv_actual
            export ACFS_MONITOR_LIBRARY_ONLY=1
            {
                printf '#!/usr/bin/env bash\nset -euo pipefail\nsource %q\n' "$integration_monitor"
                printf 'BUN_BIN=%q\n' "$integration_bun"
                printf '%s\n' "$integration_remote_reader"
                printf '%s\n' "$integration_state_advancer"
                declare -f fail record_external_review _alert_fail_closed_streak run_failure_bounded \
                    read_remote_heads advance_state write_fixture_download_evidence run_clean_bounded run_bun_clean_bounded
                printf 'checksum_monitor_main\n'
            } > "$case_root/state/runner.sh"
            monitor_exit=0
            bash "$case_root/state/runner.sh" > "$case_root/state/full-run.log" 2>&1 || monitor_exit=$?
            remote_main="$(git --git-dir="$case_root/remote.git" rev-parse main)"
            remote_master="$(git --git-dir="$case_root/remote.git" rev-parse master)"
            [[ "$remote_main" == "$remote_master" ]] || fail "$integration_case published mixed refs"
            if [[ ! -f "$case_root/state/network-calls" ]]; then
                tail -15 "$case_root/state/full-run.log" >&2
                fail "$integration_case stopped before the fixture observation (monitor exit $monitor_exit)"
            fi
            [[ "$(wc -l < "$case_root/state/network-calls")" -eq 1 ]] || fail "$integration_case did not observe exactly once"
            if [[ "$monitor_exit" -eq 0 ]]; then
                expected_health=DEFERRED
                if [[ "$integration_case" == approved ]]; then expected_health=HEALTHY; fi
                [[ "$(cat "$FAIL_STREAK_FILE")" == 0 && -f "$RECOVERY_PENDING_FILE" && ! -s "$RECOVERY_PENDING_FILE" ]] \
                    || fail "$integration_case did not clear the accepted outage and acknowledge recovery"
                [[ "$(grep -c 'gh issue comment 457 ' "$case_root/state/recovery-calls")" == 1 ]] \
                    || fail "$integration_case did not deliver exactly one accepted recovery"
                grep -q "current state: $expected_health" "$case_root/state/recovery-calls" \
                    || fail "$integration_case reported an incorrect recovery outcome"
                if [[ "$expected_health" == DEFERRED ]]; then
                    grep -q 'Unapproved external checksum changes remain pinned pending human authorization' \
                        "$case_root/state/recovery-calls" || fail 'deferred publication falsely claimed full authorization'
                fi
            else
                [[ ! -e "$case_root/state/recovery-calls" ]] || fail "$integration_case announced recovery before acceptance"
            fi
            case "$integration_case" in
                subset-approved|subset-stale|subset-malformed|subset-grant-replaced-before-consumption)
                    local_head="$(git -C "$case_root/repo" rev-parse HEAD)"
                    printf 'Subset evidence: case=%s exit=%s base=%s remote-main=%s remote-mirror=%s local=%s\n' \
                        "$integration_case" "$monitor_exit" "$integration_base" "$remote_main" "$remote_master" "$local_head"
                    [[ "$remote_main" != "$integration_base" && "$local_head" == "$remote_main" ]] \
                        || fail "$integration_case did not publish its valid candidate"
                    git --git-dir="$case_root/remote.git" show "$remote_main:checksums.yaml" > "$case_root/state/published.yaml"
                    declare -A subset_urls=() subset_hashes=()
                    acfs_load_checksums_strict "$case_root/state/published.yaml" subset_urls subset_hashes
                    for integration_tool in "${!integration_hashes[@]}"; do
                        expected_pin="${integration_hashes[$integration_tool]}"
                        if [[ "$integration_tool" == br ]]; then expected_pin="$br_actual"; fi
                        if [[ "$integration_case" != subset-stale && "$integration_case" != subset-malformed ]]; then
                            case "$integration_tool" in
                                atuin) expected_pin="$atuin_actual" ;;
                                omp) expected_pin="$omp_actual" ;;
                                uv) expected_pin="$uv_actual" ;;
                            esac
                        fi
                        [[ "${subset_hashes[$integration_tool]}" == "$expected_pin" ]] \
                            || fail "$integration_case changed an unselected pin or missed a selected pin: $integration_tool"
                    done
                    if [[ "$integration_case" == subset-grant-replaced-before-consumption ]]; then
                        [[ "$monitor_exit" -ne 0 \
                            && "$(cat "$case_root/state/boundary-mutation")" == "$integration_case"$'\tREMOTE_VERIFIED' ]] \
                            || fail 'replacement grant was not rejected at the receipt boundary'
                        cmp -s "$AUTHORIZATION_FILE" "$case_root/state/replacement-authorization" \
                            || fail 'replacement subset grant was overwritten or consumed'
                        ! grep -qE 'state=(HEALTHY|DEFERRED)' "$case_root/state/full-run.log" \
                            || fail 'replacement at the receipt boundary was falsely accepted'
                    else
                        [[ "$monitor_exit" -eq 0 ]] || fail "$integration_case failed"
                        grep -q 'result=deferred state=DEFERRED' "$case_root/state/full-run.log" \
                            || fail 'unselected external mismatches were falsely reported healthy'
                        if [[ "$integration_case" == subset-approved ]]; then
                            [[ "$(cat "$AUTHORIZATION_FILE")" == "used-subset:$integration_digest:atuin,omp,uv:$remote_main" ]] \
                                || fail 'subset receipt did not bind the exact selected set and accepted commit'
                            grep -q 'deferred=grok' "$case_root/state/full-run.log" || fail 'Grok did not remain deferred'
                            grep -qF "$integration_digest"$'\tauthorized' "$case_root/state/reviews.tsv" \
                                || fail 'selected subset authorization was not recorded'
                        else
                            cmp -s "$AUTHORIZATION_FILE" "$case_root/state/initial-authorization" \
                                || fail 'invalid subset record was reinterpreted or consumed'
                        fi
                    fi
                    [[ -z "$(git -C "$case_root/repo" status --porcelain --untracked-files=all)" ]] \
                        || fail "$integration_case left a dirty publication clone"
                    ;;
                subset-review-unavailable|subset-push-rejected|subset-grant-replaced-before-push|subset-mode-changed-before-push)
                    local_head="$(git -C "$case_root/repo" rev-parse HEAD)"
                    printf 'Subset evidence: case=%s exit=%s base=%s remote-main=%s remote-mirror=%s local=%s\n' \
                        "$integration_case" "$monitor_exit" "$integration_base" "$remote_main" "$remote_master" "$local_head"
                    [[ "$monitor_exit" -ne 0 && "$remote_main" == "$integration_base" ]] \
                        || fail "$integration_case published an unaccepted subset"
                    if [[ "$integration_case" == subset-grant-replaced-before-push ]]; then
                        cmp -s "$AUTHORIZATION_FILE" "$case_root/state/replacement-authorization" \
                            || fail 'different valid subset grant was overwritten or consumed'
                    else
                        cmp -s "$AUTHORIZATION_FILE" "$case_root/state/initial-authorization" \
                            || fail "$integration_case consumed an unaccepted subset grant"
                    fi
                    if [[ "$integration_case" == subset-mode-changed-before-push ]]; then
                        [[ "$(stat -c '%a' "$AUTHORIZATION_FILE")" == 400 ]] || fail 'replacement authorization mode was overwritten'
                    fi
                    if [[ "$integration_case" == subset-grant-replaced-before-push || "$integration_case" == subset-mode-changed-before-push ]]; then
                        [[ "$local_head" != "$integration_base" \
                            && "$(cat "$case_root/state/boundary-mutation")" == "$integration_case"$'\tCOMMITTED' ]] \
                            || fail 'subset replacement did not follow the real local commit'
                        grep -qF 'selected external subset authorization changed before acceptance' "$case_root/state/full-run.log" \
                            || fail 'pre-push guard did not reject the changed subset grant'
                    fi
                    ;;
                evidence-changed-after-push)
                    local_head="$(git -C "$case_root/repo" rev-parse HEAD)"
                    printf 'Boundary evidence: case=%s exit=%s base=%s remote-main=%s remote-mirror=%s local=%s\n' \
                        "$integration_case" "$monitor_exit" "$integration_base" "$remote_main" "$remote_master" "$local_head"
                    [[ "$(cat "$case_root/state/boundary-mutation")" == "$integration_case"$'\tATOMIC_PUBLISHED' ]] \
                        || fail 'post-publication evidence mutation did not follow the real push'
                    [[ "$remote_main" != "$integration_base" && "$local_head" == "$remote_main" ]] \
                        || fail 'post-publication case did not publish its valid trusted candidate'
                    git --git-dir="$case_root/remote.git" show "$remote_main:checksums.yaml" > "$case_root/state/published.yaml"
                    declare -A accepted_urls=() accepted_hashes=()
                    acfs_load_checksums_strict "$case_root/state/published.yaml" accepted_urls accepted_hashes
                    [[ "${accepted_hashes[br]}" == "$br_actual" && "${accepted_hashes[omp]}" == "${integration_hashes[omp]}" ]] \
                        || fail 'post-publication case changed pins outside its trusted candidate'
                    [[ "$monitor_exit" -ne 0 && ! -e "$AUTHORIZATION_FILE" ]] \
                        || fail 'changed post-publication evidence was falsely accepted'
                    grep -qF 'first-observation download evidence is missing, unsafe, or changed' "$case_root/state/full-run.log" \
                        || fail 'final acceptance did not reject changed retained evidence'
                    ! grep -qE 'state=(REMOTE_VERIFIED|HEALTHY|DEFERRED)' "$case_root/state/full-run.log" \
                        || fail 'changed evidence reached a verified or healthy acceptance state'
                    ;;
                authorization-revoked-before-commit|authorization-revoked-before-push|evidence-changed-before-push)
                    local_head="$(git -C "$case_root/repo" rev-parse HEAD)"
                    printf 'Boundary evidence: case=%s exit=%s base=%s remote-main=%s remote-mirror=%s local=%s\n' \
                        "$integration_case" "$monitor_exit" "$integration_base" "$remote_main" "$remote_master" "$local_head"
                    [[ -s "$case_root/state/boundary-mutation" ]] || fail "$integration_case did not reach its mutation boundary"
                    [[ "$monitor_exit" -ne 0 && "$remote_main" == "$integration_base" ]] \
                        || fail "$integration_case published after its authority/evidence changed"
                    if [[ "$integration_case" == evidence-changed-before-push ]]; then
                        [[ ! -e "$AUTHORIZATION_FILE" ]] || fail 'trusted-only evidence failure created an authorization'
                        grep -qF 'first-observation download evidence is missing, unsafe, or changed' "$case_root/state/full-run.log" \
                            || fail 'trusted publication did not reject changed retained evidence'
                    else
                        [[ "$(cat "$AUTHORIZATION_FILE")" == revoked ]] || fail 'revoked authorization was overwritten or consumed'
                        grep -qF 'selected external authorization changed before acceptance' "$case_root/state/full-run.log" \
                            || fail 'publication did not reject revoked external authorization'
                    fi
                    if [[ "$integration_case" == authorization-revoked-before-commit ]]; then
                        [[ "$local_head" == "$integration_base" ]] || fail 'revoked authorization created a local commit'
                    else
                        [[ "$local_head" != "$integration_base" ]] || fail 'pre-push mutation did not follow the real local commit'
                    fi
                    ;;
                approved-review-unavailable|push-rejected|fetch-error)
                    [[ "$monitor_exit" -ne 0 && "$remote_main" == "$integration_base" ]] \
                        || fail "$integration_case did not fail closed before remote acceptance"
                    if [[ "$integration_case" == fetch-error ]]; then
                        retained_reports=("$case_root/state"/verify-*.json)
                        retained_downloads=("$case_root/state"/downloads-*)
                        [[ ${#retained_reports[@]} == 1 && -f "${retained_reports[0]}" \
                            && ${#retained_downloads[@]} == 1 && -d "${retained_downloads[0]}" ]] \
                            || fail 'failed verification lost its original diagnostic artifacts'
                        grep -qF "exit=1 report=${retained_reports[0]} downloads=${retained_downloads[0]}" \
                            "$case_root/state/full-run.log" || fail 'failed verification lost its exit status or evidence locators'
                        grep -qF "verification binding: policy_sha256=$integration_policy_digest report_sha256=$(sha256_file "${retained_reports[0]}")" \
                            "$case_root/state/full-run.log" || fail 'failed verification lost its policy/report digest binding'
                        grep -qF 'verification returned 1 error(s) / 0 skip(s); refusing to auto-update checksums.yaml' \
                            "$case_root/state/full-run.log" || fail 'diagnostic logging changed the fail-closed reason'
                        [[ "$(git -C "$case_root/repo" rev-parse HEAD)" == "$integration_base" ]] \
                            || fail 'verification error created a publication commit'
                    fi
                    if [[ -f "$AUTHORIZATION_FILE" ]]; then
                        [[ "$(cat "$AUTHORIZATION_FILE")" == "authorize:$integration_digest" ]] \
                            || fail "$integration_case consumed an unaccepted authorization"
                    fi
                    ;;
                *)
                    [[ "$monitor_exit" -eq 0 ]] || { tail -15 "$case_root/state/full-run.log" >&2; fail "$integration_case failed"; }
                    git --git-dir="$case_root/remote.git" show "$remote_main:checksums.yaml" > "$case_root/state/published.yaml"
                    declare -A published_urls=() published_hashes=()
                    acfs_load_checksums_strict "$case_root/state/published.yaml" published_urls published_hashes
                    if [[ "$integration_case" == external-only ]]; then
                        [[ "$remote_main" == "$integration_base" && "${published_hashes[br]}" == "${integration_hashes[br]}" ]] \
                            || fail 'external-only pending review created a commit'
                    else
                        [[ "$remote_main" != "$integration_base" && "${published_hashes[br]}" == "$br_actual" ]] \
                            || fail "$integration_case did not publish the trusted observation"
                        [[ "$(git --git-dir="$case_root/remote.git" log -1 --format='%an|%cn' "$remote_main")" \
                            == 'acfs-checksum-monitor|acfs-checksum-monitor' ]] \
                            || fail "$integration_case published under a name other than acfs-checksum-monitor"
                    fi
                    if [[ "$integration_case" == approved ]]; then
                        [[ "${published_hashes[omp]}" == "$omp_actual" \
                            && "$(cat "$AUTHORIZATION_FILE")" == "used:$integration_digest:$remote_main" ]] \
                            || fail 'approved external publication was not accepted and consumed exactly once'
                        grep -q 'result=ok state=HEALTHY' "$case_root/state/full-run.log" || fail 'approved run not healthy'
                    else
                        [[ "${published_hashes[omp]}" == "${integration_hashes[omp]}" ]] || fail 'unapproved external pin changed'
                        grep -q 'result=deferred state=DEFERRED' "$case_root/state/full-run.log" || fail 'pending review falsely reported healthy'
                    fi
                    [[ -z "$(git -C "$case_root/repo" status --porcelain --untracked-files=all)" ]] \
                        || fail "$integration_case accepted a dirty clone"
                    ;;
            esac
            printf 'PASS: full publication state machine: %s\n' "$integration_case"
        ) || exit 1
    done
else
    printf 'SKIP: full publication qualification requires ACFS_MONITOR_TEST_ARCHIVE\n'
fi

# The service unit still executes this script directly from the clone.
grep -q '^ExecStart=%h/acfs-monitor/scripts/checksum-monitor-local.sh$' \
    "$REPO_ROOT/scripts/templates/acfs-checksum-monitor.service" \
    || fail "service template no longer runs the monitor script"

printf 'PASS: checksum monitor accepts newer same-major Bun and deduplicates fail-closed alerts\n'

# Real policy/report validation, candidate selection and Git cleanliness. Only
# delivery to GitHub is replaced here; no external messages may leave this test.
(
    export ACFS_MONITOR_REPO="$STATE_TMP/selection-repo"
    export ACFS_MONITOR_STATE="$STATE_TMP/selection-state"
    unset ACFS_NTFY_TOPIC
    ACFS_MONITOR_LIBRARY_ONLY=1
    # shellcheck source=../checksum-monitor-local.sh
    source "$MONITOR"
    mkdir -p "$MONITOR_REPO/scripts/lib"
    command cp "$REPO_ROOT/scripts/lib/security.sh" "$MONITOR_REPO/scripts/lib/security.sh"
    command cp "$REPO_ROOT/checksums.yaml" "$MONITOR_REPO/checksums.yaml"
    cd "$MONITOR_REPO" || exit 1
    git -c init.templateDir= init -q
    git add -- checksums.yaml scripts/lib/security.sh
    git -c core.hooksPath=/dev/null -c user.name='Monitor Test' -c user.email='monitor-test@example.invalid' \
        commit -qm 'Initial policy fixture'
    BASE_HEAD="$(git rev-parse HEAD)"
    CURRENT_CHECKSUMS_SHA256="$(sha256_file checksums.yaml)"
    # shellcheck source=../lib/security.sh
    source "$REPO_ROOT/scripts/lib/security.sh"
    export ACFS_SECURITY_RETAIN_TEMP_FILES=true
    declare -A test_urls=() test_hashes=()
    acfs_load_checksums_strict checksums.yaml test_urls test_hashes
    test_br_actual="$(printf 'a%.0s' {1..64})"
    test_omp_actual="$(printf 'b%.0s' {1..64})"
    for test_tool in "${!test_hashes[@]}"; do
        test_actual="${test_hashes[$test_tool]}"
        if [[ "$test_tool" == br ]]; then test_actual="$test_br_actual"; fi
        if [[ "$test_tool" == omp ]]; then test_actual="$test_omp_actual"; fi
        jq -cn --arg name "$test_tool" --arg url "${test_urls[$test_tool]}" \
            --arg expected "${test_hashes[$test_tool]}" --arg actual "$test_actual" \
            '{name:$name,url:$url,expected:$expected,actual:$actual}'
    done > "$STATE_DIR/observations.jsonl"
    report="$STATE_DIR/report.json"
    jq -cs --arg digest "$CURRENT_CHECKSUMS_SHA256" '{
        schema:"acfs.installer-checksum-verification.v1", schemaVersion:1,
        timestamp:"2026-10-12T00:00:00Z", checksumsYamlSha256:$digest, total:length,
        matches:[.[] | select(.actual == .expected) | {name,url,checksum:.expected}],
        mismatches:[.[] | select(.actual != .expected)], errors:[], skipped:[]
    }' "$STATE_DIR/observations.jsonl" > "$report"
    VERIFICATION_REPORT_SHA256="$(sha256_file "$report")"
    mismatches=2
    external_deferred=false
    authorization_consumed=false
    changed_tools=""
    review_exit=0
    record_external_review() {
        printf '%s\t%s\n' "$2" "$3" >> "$STATE_DIR/reviews.tsv"
        return "$review_exit"
    }
    _alert_fail_closed_streak() { return 0; }
    run_clean_bounded() {
        shift
        # Execute the real security CLI, retaining its temporary snapshots.
        "$@" --retain-temp-files
    }
    validate_verification_report "$report" "$CURRENT_CHECKSUMS_SHA256" \
        || fail 'complete report did not validate'
    first_digest="$(external_authorization_digest "$report" omp)"
    jq -c '.mismatches |= map(if .name == "br" then .actual = ("c" * 64) else . end)' \
        "$report" > "$STATE_DIR/trusted-changed.json"
    [[ "$(external_authorization_digest "$STATE_DIR/trusted-changed.json" omp)" == "$first_digest" ]] \
        || fail 'trusted changes invalidate external authorization'
    BASE_HEAD="$(printf 'd%.0s' {1..40})"
    [[ "$(external_authorization_digest "$report" omp)" == "$first_digest" ]] \
        || fail 'unrelated base changes invalidate external authorization'
    jq -c '.mismatches |= map(if .name == "omp" then .actual = ("e" * 64) else . end)' \
        "$report" > "$STATE_DIR/external-changed.json"
    [[ "$(external_authorization_digest "$STATE_DIR/external-changed.json" omp)" != "$first_digest" ]] \
        || fail 'changed external bytes reuse an approval'
    ! is_trusted_installer_url 'https://raw.githubusercontent.com/DicklesworthstoneEvil/tool/main/install.sh' \
        || fail 'owner-prefix impersonation is trusted'

    STATE=OBSERVED
    prepare_checksum_candidate "$report"
    [[ "$STATE" == AUTHORIZED && "$applicable_changed" == br && "$external_deferred" == true \
        && "$authorization_consumed" == false ]] || fail 'pending external review blocked trusted selection'
    declare -A selected_urls=() selected_hashes=()
    acfs_load_checksums_strict "$validated_candidate" selected_urls selected_hashes
    [[ "${selected_hashes[br]}" == "$test_br_actual" && "${selected_hashes[omp]}" == "${test_hashes[omp]}" ]] \
        || fail 'trusted-only candidate changed the wrong pins'
    require_clean_tree || fail 'candidate preparation mutated the repository'

    review_exit=1
    STATE=OBSERVED
    prepare_checksum_candidate "$report"
    [[ "$applicable_changed" == br && "$external_deferred" == true ]] \
        || fail 'failed review delivery prevented trusted selection'
    grep -q 'WARNING: external review issue could not be recorded' "$LOG_FILE" \
        || fail 'failed review delivery was hidden'
    review_exit=0
    jq -c '.matches += [.mismatches[] | select(.name == "br") | {name,url,checksum:.expected}] |
        .mismatches |= map(select(.name != "br"))' "$report" > "$STATE_DIR/external-only.json"
    (
        mismatches=1
        VERIFICATION_REPORT_SHA256="$(sha256_file "$STATE_DIR/external-only.json")"
        STATE=OBSERVED
        prepare_checksum_candidate "$STATE_DIR/external-only.json"
        [[ -z "$applicable_changed" && -z "$validated_candidate" && "$external_deferred" == true \
            && "$authorization_consumed" == false ]] || fail 'external-only review mutated a candidate'
    ) || fail 'external-only pending review failed'

    printf 'authorize:%s\n' "$first_digest" > "$AUTHORIZATION_FILE"
    chmod 600 "$AUTHORIZATION_FILE"
    authorization_is_valid "$first_digest" || fail 'exact owner-only authorization rejected'
    STATE=OBSERVED
    prepare_checksum_candidate "$report"
    [[ "$external_deferred" == false && "$authorization_consumed" == true \
        && "$applicable_changed" == "$changed_tools" ]] || fail 'approved external observation was not selected'
    acfs_load_checksums_strict "$validated_candidate" selected_urls selected_hashes
    [[ "${selected_hashes[omp]}" == "$test_omp_actual" ]] || fail 'approved external pin did not advance'
    [[ "$(cat "$AUTHORIZATION_FILE")" == "authorize:$first_digest" ]] \
        || fail 'authorization consumed before publication'
    review_exit=1
    if ( STATE=OBSERVED; prepare_checksum_candidate "$report" ) > "$STATE_DIR/approved-review-failure.log" 2>&1; then
        fail 'authorized external publication ignored failed evidence recording'
    fi
    chmod 644 "$AUTHORIZATION_FILE"
    ! authorization_is_valid "$first_digest" || fail 'non-owner-only authorization accepted'
    chmod 600 "$AUTHORIZATION_FILE"
    ! authorization_is_valid "$(printf 'f%.0s' {1..64})" || fail 'wrong authorization digest accepted'
    ln -s "$AUTHORIZATION_FILE" "$STATE_DIR/authorization-symlink"
    (
        AUTHORIZATION_FILE="$STATE_DIR/authorization-symlink"
        ! authorization_is_valid "$first_digest" || fail 'authorization symlink accepted'
    ) || fail 'symlink authorization check failed'

    # The offline helper's selected digest is intentionally independent of
    # unrelated observations, but its response must still bind this run's
    # exact policy and report snapshots before it grants any authority.
    unit_subset_proposal="$STATE_DIR/unit-subset-proposal.json"
    bash "$REPO_ROOT/scripts/lib/security.sh" --review-checksum-subset checksums.yaml "$report" omp --retain-temp-files \
        > "$unit_subset_proposal" || fail 'real offline subset proposal failed'
    unit_subset_record="$(jq -er '.authorization_line' "$unit_subset_proposal")"
    printf '%s\n' "$unit_subset_record" > "$AUTHORIZATION_FILE"
    chmod 600 "$AUTHORIZATION_FILE"
    cp "$AUTHORIZATION_FILE" "$STATE_DIR/unit-subset-original-authorization"
    authorization_mode=none
    authorization_consumed=false
    SELECTED_EXTERNAL_CHANGED=()
    select_external_subset_authorization "$report" || fail 'valid exact helper proposal was rejected'
    [[ "$authorization_mode" == subset && "${SELECTED_EXTERNAL_CHANGED[*]}" == omp \
        && "$selected_authorization_record" == "$unit_subset_record" && "$selected_authorization_file_mode" == 600 \
        && "$authorization_consumed" == false ]] || fail 'valid helper selection did not retain exact record and mode'
    for proposal_fault in checksums_yaml_sha256 verification_report_sha256 authorization_digest selected schema scope authorization_line; do
        bad_proposal="$STATE_DIR/proposal-bad-$proposal_fault.json"
        case "$proposal_fault" in
            selected) jq '.selected = ["atuin"]' "$unit_subset_proposal" > "$bad_proposal" ;;
            schema) jq '.schema = "unbound-review"' "$unit_subset_proposal" > "$bad_proposal" ;;
            scope) jq '.scope = "aggregate"' "$unit_subset_proposal" > "$bad_proposal" ;;
            authorization_line) jq '.authorization_line += ",uv"' "$unit_subset_proposal" > "$bad_proposal" ;;
            *) jq --arg field "$proposal_fault" '.[$field] = ("0" * 64)' "$unit_subset_proposal" > "$bad_proposal" ;;
        esac
        (
            authorization_mode=none
            authorization_digest=""
            selected_authorization_record=""
            selected_authorization_file_mode=""
            authorized_external_changed=""
            SELECTED_EXTERNAL_CHANGED=()
            run_clean_bounded() {
                shift
                [[ "${1:-}" == bash && "${2:-}" == scripts/lib/security.sh && "${3:-}" == --review-checksum-subset ]] \
                    || fail 'unexpected command in subset proposal fault fixture'
                cat "$bad_proposal"
            }
            ! select_external_subset_authorization "$report" || fail "unbound helper proposal was accepted: $proposal_fault"
            [[ "$authorization_mode" == none && ${#SELECTED_EXTERNAL_CHANGED[@]} == 0 \
                && -z "$selected_authorization_record" ]] || fail "$proposal_fault left selected external authority"
            cmp -s "$AUTHORIZATION_FILE" "$STATE_DIR/unit-subset-original-authorization" \
                || fail "$proposal_fault modified the human record"
        ) || fail 'subset helper response binding failed'
    done
    printf 'PASS: subset proposal binds exact policy/report snapshots, selected set, digest, scope and record\n'
    require_clean_tree || fail 'selection tests mutated the repository'
    printf 'PASS: bound offline candidates, independent external approval, pending review and authority guards\n'
    if [[ -n "${ACFS_MONITOR_TEST_INCUMBENT:-}" ]]; then
        acfs_build_checksum_candidate checksums.yaml "$report" > "$STATE_DIR/first-full.yaml"
        # Runtime fixture data only: simulate an applied installer changing
        # between first observation and the incumbent's second download.
        awk '/^  br:$/ { in_br=1; print; next }
             /^  [a-z0-9_]+:$/ { in_br=0 }
             in_br && /^    sha256:/ { print "    sha256: \"" sprintf("%064d", 3) "\""; next }
             { print }' "$STATE_DIR/first-full.yaml" > "$STATE_DIR/flapping-second.yaml"
        (
            legacy_state="$STATE_DIR"
            legacy_report="$report"
            ACFS_MONITOR_LIBRARY_ONLY=1
            source "$ACFS_MONITOR_TEST_INCUMBENT/scripts/checksum-monitor-local.sh"
            source "$ACFS_MONITOR_TEST_INCUMBENT/scripts/lib/security.sh"
            export ACFS_SECURITY_RETAIN_TEMP_FILES=true
            restrict_checksum_candidate checksums.yaml "$legacy_state/flapping-second.yaml" br \
                > "$legacy_state/incumbent-restricted.yaml"
            if acfs_validate_checksum_candidate checksums.yaml "$legacy_state/incumbent-restricted.yaml" \
                "$legacy_report" omp > "$legacy_state/incumbent-rejected.yaml"; then
                fail 'incumbent unexpectedly accepted a second-fetch applied variant'
            fi
        ) || fail 'incumbent counterfactual failed'
        acfs_build_checksum_candidate checksums.yaml "$report" omp > "$STATE_DIR/stable-first.yaml"
        acfs_validate_checksum_candidate checksums.yaml "$STATE_DIR/stable-first.yaml" "$report" omp \
            > "$STATE_DIR/stable-first-validated.yaml" || fail 'first-report candidate rejected'
        printf 'PASS: same-fixture incumbent rejects second-fetch variant; offline candidate accepts first observation\n'
    fi
) || exit 1
[[ "$numeric_failures" == 0 ]] || exit 1
