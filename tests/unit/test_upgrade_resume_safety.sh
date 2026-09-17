#!/usr/bin/env bash
# Host-safe regressions for the production upgrade-resume dispatcher.
# The exact dispatcher is run with fixture OS, package, state and systemd edges.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/scripts/lib/upgrade_resume.sh"
SUITE=$(mktemp -d "${TMPDIR:-/tmp}/acfs-resume-safety.XXXXXX")
PASS=0 FAIL=0

extract_function() {
    awk -v name="$1" '$0 == name "() {" { p=1 } p { print } p && /^}/ { exit }' "$SCRIPT"
}
for function_name in compute_version_num ubuntu_is_at_or_beyond_target_version read_target_version_from_state mark_state_complete; do
    extract_function "$function_name" >> "$SUITE/functions.sh"
done
awk '/^log "=== ACFS Upgrade Resume Starting ==="/ { p=1 } p' "$SCRIPT" > "$SUITE/main.sh"
[[ -s "$SUITE/main.sh" ]]
bash -n "$SCRIPT"
bash -n "$SUITE/functions.sh"
bash -n "$SUITE/main.sh"
source "$SUITE/functions.sh"

assert_eq() { [[ "$1" == "$2" ]] || { printf 'expected <%s>, got <%s>\n' "$2" "$1" >&2; return 1; }; }
run() {
    local name="$1" status; shift
    set +e
    (set -e; "$@") > "$SUITE/case.log" 2>&1
    status=$?
    set -e
    if [[ "$status" == 0 ]]; then
        PASS=$((PASS+1)); printf 'PASS %s\n' "$name"
    else
        FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$name"; cat "$SUITE/case.log"
    fi
}

check_target_read() {
    local value="$1" expected="$2" file
    file=$(mktemp "$SUITE/target.XXXXXX")
    printf '%s' "$value" > "$file"
    local actual='' status=0
    actual=$(read_target_version_from_state "$file") || status=$?
    if [[ "$expected" == refused ]]; then
        [[ "$status" != 0 && -z "$actual" ]]
    else
        assert_eq "$status" 0; assert_eq "$actual" "$expected"
    fi
}
run 'reads the persisted target' check_target_read '{"ubuntu_upgrade":{"target_version":"26.04"}}' 26.04
for value in '{}' 'null' '[]' '{broken "target_version":"26.04"}' \
    '{"ubuntu_upgrade":{"target_version":26.04}}' \
    '{"ubuntu_upgrade":{"target_version":"26.04;echo unsafe"}}' \
    '{"ubuntu_upgrade":{"target_version":"26.99"}}'; do
    run 'refuses malformed or missing target metadata' check_target_read "$value" refused
done
check_version() { assert_eq "$(compute_version_num "$1")" "$2"; }
run 'parses April using base ten' check_version 26.04 2604
run 'parses October' check_version 25.10 2510
run 'normalizes a live point release' check_version 26.04.1 2604
check_bad_version() { if compute_version_num "$1"; then return 1; fi; }
for value in '' 26 26.99 'a[0]' '999999999999999999999.04'; do
    run "rejects malformed numeric release: $value" check_bad_version "$value"
done
check_stale_number() {
    UBUNTU_TARGET_VERSION=26.04 UBUNTU_TARGET_VERSION_NUM=2204
    if ubuntu_is_at_or_beyond_target_version 24.04; then return 1; fi
    ubuntu_is_at_or_beyond_target_version 26.04
}
run 'inherited numeric target cannot make an older host complete' check_stale_number

check_mark_complete() {
    local WORK ACFS_STATE_FILE log_message
    WORK=$(mktemp -d "$SUITE/complete.XXXXXX")
    ACFS_STATE_FILE="$WORK/state.json"
    log() { :; }; log_error() { :; }
    printf '{"ubuntu_upgrade":{"target_version":"25.10","current_stage":"upgrading"}}' > "$ACFS_STATE_FILE"
    mark_state_complete
    jq -e '.ubuntu_upgrade.current_stage == "completed" and .ubuntu_upgrade.needs_reboot == false' "$ACFS_STATE_FILE" >/dev/null
}
run 'completion is persisted atomically' check_mark_complete
check_failed_write() {
    local scenario="$1" WORK ACFS_STATE_FILE before
    WORK=$(mktemp -d "$SUITE/write.XXXXXX")
    ACFS_STATE_FILE="$WORK/state.json"
    log() { :; }; log_error() { :; }
    printf '{"ubuntu_upgrade":{"target_version":"25.10"}}' > "$ACFS_STATE_FILE"
    before=$(cat "$ACFS_STATE_FILE")
    case "$scenario" in
        mktemp) mktemp() { return 1; } ;;
        rename) mv() { return 1; } ;;
        malformed) printf '{broken' > "$ACFS_STATE_FILE"; before='{broken' ;;
        missing) ACFS_STATE_FILE="$WORK/missing" ;;
    esac
    if mark_state_complete; then return 1; fi
    [[ "$scenario" == missing ]] || assert_eq "$(cat "$ACFS_STATE_FILE")" "$before"
}
for scenario in mktemp rename malformed missing; do
    run "completion write fails closed: $scenario" check_failed_write "$scenario"
done

check_dispatch() {
    local scenario="$1" WORK ACFS_RESUME_DIR ACFS_LIB_DIR ACFS_LOG ACFS_STATE_FILE
    WORK=$(mktemp -d "$SUITE/dispatch.XXXXXX")
    ACFS_RESUME_DIR="$WORK/resume" ACFS_LIB_DIR="$WORK/lib" ACFS_LOG="$WORK/run.log"
    ACFS_STATE_FILE="$ACFS_RESUME_DIR/state.json"
    local UBUNTU_TARGET_VERSION=25.10 UBUNTU_TARGET_VERSION_NUM=2510 state_target_version=25.10
    local BASE_VERSION=25.04 FAKE_ID=ubuntu STAGE=rebooting FAIL_AT='' PLAN=25.10
    local INSTALLED_VERSION=25.10 AUDIT='' EXPECTED_STATUS=0 EXPECTED_HOP=25.10
    mkdir -p "$ACFS_RESUME_DIR" "$ACFS_LIB_DIR"
    : > "$ACFS_LIB_DIR/logging.sh"
    : > "$ACFS_LIB_DIR/state.sh"
    : > "$ACFS_LIB_DIR/ubuntu_upgrade.sh"
    log() { printf '%s\n' "$*" >> "$WORK/log"; }
    log_error() { log "$*"; }
    cleanup_service() { : > "$WORK/disabled"; }
    update_motd_failure() { printf '%s\n' "$*" > "$WORK/failure"; }
    remove_motd() { : > "$WORK/motd-removed"; }
    cleanup_resume_files() { : > "$WORK/files-removed"; }
    launch_continue_script() { : > "$WORK/continued"; [[ "$FAIL_AT" != continuation ]]; }
    mark_state_complete() { : > "$WORK/marked"; [[ "$FAIL_AT" != mark ]]; }
    source() {
        if [[ "$1" == /etc/os-release ]]; then ID="$FAKE_ID"; VERSION_ID="$BASE_VERSION";
        else builtin source "$@"; fi
    }
    upgrade_acquire_lock() { [[ "$FAIL_AT" != lock ]]; }
    upgrade_release_lock() { : > "$WORK/released"; }
    ubuntu_enable_normal_releases() { [[ "$FAIL_AT" != channel ]]; }
    state_upgrade_resumed() { [[ "$FAIL_AT" != resumed ]]; }
    state_upgrade_is_complete() { : > "$WORK/trusted-checkpoint"; return 0; }
    state_upgrade_get_next_version() { : > "$WORK/trusted-path"; printf '99.10\n'; }
    state_upgrade_start() { printf '%s\n' "$*" > "$WORK/started"; [[ "$FAIL_AT" != start ]]; }
    state_upgrade_set_error() { : > "$WORK/error-recorded"; return 1; }
    state_upgrade_complete() { : > "$WORK/completed"; [[ "$FAIL_AT" != complete ]]; }
    state_upgrade_needs_reboot() { [[ "$FAIL_AT" != reboot-state ]]; }
    ubuntu_calculate_upgrade_path() { printf '%s\n' "$PLAN"; [[ "$FAIL_AT" != plan ]]; }
    ubuntu_preflight_checks() { [[ "$FAIL_AT" != preflight ]]; }
    ubuntu_do_upgrade() { printf '%s\n' "$1" > "$WORK/upgraded"; [[ "$FAIL_AT" != executor ]]; }
    ubuntu_get_version_string() { printf '%s\n' "$INSTALLED_VERSION"; }
    upgrade_update_motd() { :; }
    dpkg() {
        [[ "$*" == --audit ]] || return 99
        printf '%s' "$AUDIT"
        if [[ "$FAIL_AT" == audit-status ]]; then return 1; fi
        if [[ "$FAIL_AT" == post-audit && -f "$WORK/upgraded" ]]; then printf 'unconfigured package\n'; fi
    }
    shutdown() { printf '%s\n' "$*" > "$WORK/reboot"; [[ "$FAIL_AT" != shutdown ]]; }
    ubuntu_trigger_reboot() { : > "$WORK/legacy-background-reboot"; return 0; }
    case "$scenario" in
        normal) ;;
        kernel-only) STAGE=pre_upgrade_reboot ;;
        stale-complete) STAGE=completed; BASE_VERSION=24.04; PLAN=$'25.04\n25.10'; INSTALLED_VERSION=25.04; EXPECTED_HOP=25.04 ;;
        at-target) BASE_VERSION=25.10 ;;
        beyond-target) BASE_VERSION=26.04 ;;
        bad-os) FAKE_ID=debian; EXPECTED_STATUS=1 ;;
        bad-target) UBUNTU_TARGET_VERSION_NUM=''; EXPECTED_STATUS=1 ;;
        missing-target) state_target_version=''; EXPECTED_STATUS=1 ;;
        backwards) PLAN=24.04; EXPECTED_STATUS=1 ;;
        overshoot) PLAN=26.04; EXPECTED_STATUS=1 ;;
        garbage-hop) PLAN='a[0]'; EXPECTED_STATUS=1 ;;
        no-op) INSTALLED_VERSION=25.04; EXPECTED_STATUS=1 ;;
        wrong-release) INSTALLED_VERSION=26.04; EXPECTED_STATUS=1 ;;
        audit-output) AUDIT='unconfigured package'; EXPECTED_STATUS=1 ;;
        target-audit) BASE_VERSION=25.10; AUDIT='unconfigured package'; EXPECTED_STATUS=1 ;;
        continuation|mark) BASE_VERSION=25.10; FAIL_AT="$scenario"; EXPECTED_STATUS=1 ;;
        library) printf 'return 1\n' > "$ACFS_LIB_DIR/ubuntu_upgrade.sh"; EXPECTED_STATUS=1 ;;
        state-library) printf 'return 1\n' > "$ACFS_LIB_DIR/state.sh"; EXPECTED_STATUS=1 ;;
        logging-library) printf 'return 1\n' > "$ACFS_LIB_DIR/logging.sh"; EXPECTED_STATUS=1 ;;
        *) FAIL_AT="$scenario"; EXPECTED_STATUS=1 ;;
    esac
    jq -n --arg target "$UBUNTU_TARGET_VERSION" --arg stage "$STAGE" \
        '{ubuntu_upgrade:{target_version:$target,current_stage:$stage,upgrade_path:["25.04","25.10"],completed_upgrades:[{},{}]}}' > "$ACFS_STATE_FILE"
    local result=0
    (set -e; builtin source "$SUITE/main.sh") > "$WORK/stdout" 2> "$WORK/stderr" || result=$?
    assert_eq "$result" "$EXPECTED_STATUS"
    [[ ! -f "$WORK/trusted-checkpoint" && ! -f "$WORK/trusted-path" && ! -f "$WORK/files-removed" ]]
    [[ ! -f "$WORK/legacy-background-reboot" ]]
    if [[ "$scenario" == at-target || "$scenario" == beyond-target ]]; then
        [[ -f "$WORK/continued" && -f "$WORK/marked" && -f "$WORK/disabled" && ! -f "$WORK/reboot" ]]
    elif [[ "$EXPECTED_STATUS" == 0 ]]; then
        assert_eq "$(cat "$WORK/upgraded")" "$EXPECTED_HOP"
        assert_eq "$(cat "$WORK/reboot")" '-r +1 ACFS: Ubuntu upgrade requires reboot'
        [[ ! -f "$WORK/continued" && ! -f "$WORK/disabled" && -f "$WORK/completed" && -f "$WORK/released" ]]
    else
        if [[ "$scenario" != lock ]]; then [[ -f "$WORK/disabled" && -f "$WORK/failure" ]]; fi
        [[ "$scenario" == continuation || ! -f "$WORK/continued" ]]
        [[ "$scenario" == shutdown || ! -f "$WORK/reboot" ]]
        case "$scenario" in no-op|wrong-release|post-audit|executor) [[ ! -f "$WORK/completed" ]] ;; esac
    fi
}
for scenario in normal kernel-only stale-complete at-target beyond-target bad-os bad-target missing-target \
    backwards overshoot garbage-hop no-op wrong-release audit-output target-audit audit-status post-audit \
    continuation mark library state-library logging-library lock channel resumed start plan preflight executor complete reboot-state shutdown; do
    run "resume dispatcher: $scenario" check_dispatch "$scenario"
done
printf '\n%s passed; %s failed. Fixtures retained at %s\n' "$PASS" "$FAIL" "$SUITE"
[[ "$FAIL" == 0 ]]
