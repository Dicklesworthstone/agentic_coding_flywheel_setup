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

    _alert_fail_closed_streak 3 "push-only reason"
    first_gh_count=$(gh_count)
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
    _announce_recovery 13
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
            "45 gh issue list "*) [[ -n "${OPEN_ISSUE:-}" ]] && printf '%s\n' "$OPEN_ISSUE" ;;
        esac
        return 0
    }
    EXTERNAL_CHANGED=(ext)
    BASE_HEAD=0000000000000000000000000000000000000000
    VERIFICATION_REPORT_SHA256="$(hx 9)"
    RUN_TS=unit
    : > "$GH_CALLS"; OPEN_ISSUE=""
    record_external_review "$(report_with 3 4)" "$d1" required || fail "record_external_review failed"
    grep -q -- '--state all' "$GH_CALLS" || fail "authorization lookup ignores closed issues"
    [[ "$(grep -c ' gh issue create ' "$GH_CALLS")" == 1 ]] || fail "first pending request did not open one issue"
    : > "$GH_CALLS"; OPEN_ISSUE=446
    record_external_review "$(report_with 3 4)" "$d1" required || fail "record_external_review failed"
    ! grep -qE ' gh issue (comment|create) ' "$GH_CALLS" || fail "a still-pending authorization was re-posted"
    record_external_review "$(report_with 3 4)" "$d1" authorized || fail "record_external_review failed"
    [[ "$(grep -c ' gh issue comment 446 ' "$GH_CALLS")" == 1 ]] || fail "authorized use was not recorded on the issue"
) || exit 1

# Opt-in full state-machine qualification uses an immutable source archive.
# Git's real SSH transport protocol is redirected to disposable bare fixtures;
# dependencies, cleanliness, strict validators, generation, atomic pushes and
# remote acceptance remain real. Upstream observations and issue delivery are
# deterministic fixtures, so this does not assert live GitHub acceptance.
if [[ -n "${ACFS_MONITOR_TEST_ARCHIVE:-}" ]]; then
    [[ -f "$ACFS_MONITOR_TEST_ARCHIVE" ]] || fail 'integration source archive missing'
    integration_root="$STATE_TMP/integration"
    mkdir -p "$integration_root/seed" "$integration_root/home/.bun/bin"
    command cp "$HOME/.bun/bin/bun" "$integration_root/home/.bun/bin/bun"
    chmod 755 "$integration_root/home/.bun/bin" "$integration_root/home/.bun/bin/bun"
    tar -xzf "$ACFS_MONITOR_TEST_ARCHIVE" -C "$integration_root/seed"
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
        "$HOME/.bun/bin/bun" install --cwd packages/manifest --frozen-lockfile --ignore-scripts --silent
        "$HOME/.bun/bin/bun" run packages/manifest/src/generate.ts > "$integration_root/seed-generation.log"
        git -c init.templateDir= init -q -b main
        git add -- .
        git -c core.hooksPath=/dev/null -c user.name='Monitor Test' -c user.email='monitor-test@example.invalid' \
            commit -qm 'Clean generated base'
        git branch master
    ) || fail 'could not prepare clean integration base'
    for integration_case in pending external-only approved review-unavailable approved-review-unavailable push-rejected fetch-error; do
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
            source "$MONITOR"
            # shellcheck source=../lib/security.sh
            source "$REPO_ROOT/scripts/lib/security.sh"
            export ACFS_SECURITY_RETAIN_TEMP_FILES=true
            declare -A integration_urls=() integration_hashes=()
            acfs_load_checksums_strict "$case_root/repo/checksums.yaml" integration_urls integration_hashes
            integration_base="$(git -C "$case_root/repo" rev-parse HEAD)"
            integration_policy_digest="$(sha256_file "$case_root/repo/checksums.yaml")"
            br_actual="$(printf 'a%.0s' {1..64})"
            omp_actual="$(printf 'b%.0s' {1..64})"
            for integration_tool in "${!integration_hashes[@]}"; do
                integration_actual="${integration_hashes[$integration_tool]}"
                if [[ "$integration_tool" == br && "$integration_case" != external-only ]]; then integration_actual="$br_actual"; fi
                if [[ "$integration_tool" == omp ]]; then integration_actual="$omp_actual"; fi
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
                approved|approved-review-unavailable|push-rejected)
                    printf 'authorize:%s\n' "$integration_digest" > "$AUTHORIZATION_FILE"
                    chmod 600 "$AUTHORIZATION_FILE"
                    ;;
            esac
            if [[ "$integration_case" == push-rejected ]]; then
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
                [[ "$integration_case" != review-unavailable && "$integration_case" != approved-review-unavailable ]]
            }
            _alert_fail_closed_streak() { return 0; }
            _announce_recovery() { return 0; }
            run_clean_bounded() {
                local budget="$1"
                shift
                if [[ "${1:-}" == bash && "${2:-}" == scripts/lib/security.sh ]]; then
                    if [[ "${3:-}" == --verify ]]; then
                        printf 'observation\n' >> "$case_root/state/network-calls"
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
                run_bounded "$budget" env -i HOME="$HOME" USER="${USER:-}" LOGNAME="${LOGNAME:-}" \
                    PATH="$MONITOR_EXEC_PATH:${BUN_BIN%/*}" LANG=C LC_ALL=C TZ=UTC CI=1 NO_COLOR=1 \
                    TMPDIR="$case_root/state/tmp" BASH_ENV="$integration_root/retain.sh" "$BUN_BIN" "$@"
            }
            # Run in a fresh strict shell: putting a function/subshell on the
            # left of || would disable errexit inside the tested state machine.
            export case_root integration_root integration_case integration_report
            export ACFS_MONITOR_LIBRARY_ONLY=1
            {
                printf '#!/usr/bin/env bash\nset -euo pipefail\nsource %q\n' "$MONITOR"
                declare -f record_external_review _alert_fail_closed_streak _announce_recovery \
                    run_clean_bounded run_bun_clean_bounded
                printf 'checksum_monitor_main\n'
            } > "$case_root/state/runner.sh"
            monitor_exit=0
            bash "$case_root/state/runner.sh" > "$case_root/state/full-run.log" 2>&1 || monitor_exit=$?
            remote_main="$(git --git-dir="$case_root/remote.git" rev-parse main)"
            remote_master="$(git --git-dir="$case_root/remote.git" rev-parse master)"
            [[ "$remote_main" == "$remote_master" ]] || fail "$integration_case published mixed refs"
            [[ "$(wc -l < "$case_root/state/network-calls")" -eq 1 ]] || fail "$integration_case did not observe exactly once"
            case "$integration_case" in
                approved-review-unavailable|push-rejected|fetch-error)
                    [[ "$monitor_exit" -ne 0 && "$remote_main" == "$integration_base" ]] \
                        || fail "$integration_case did not fail closed before remote acceptance"
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
