#!/usr/bin/env bash
# Host-safe regressions for the production upgrade-resume dispatcher.
# The exact dispatcher is run with fixture OS, package, state and systemd edges.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/scripts/lib/upgrade_resume.sh"
# This override is only a test fixture seam. Normal repository runs extract
# the release policy from the complete production upgrade library.
LIBRARY="${ACFS_TEST_UPGRADE_LIBRARY:-$ROOT/scripts/lib/ubuntu_upgrade.sh}"
STATE_LIBRARY="${ACFS_TEST_STATE_LIBRARY:-$ROOT/scripts/lib/state.sh}"
SUITE=$(mktemp -d "${TMPDIR:-/tmp}/acfs-resume-safety.XXXXXX")
PASS=0 FAIL=0

extract_function() {
    awk -v name="$1" '$0 == name "() {" { p=1 } p { print } p && /^}/ { exit }' "$SCRIPT"
}
for function_name in parse_resume_args compute_version_num ubuntu_is_at_or_beyond_target_version read_target_version_from_state validate_resume_target mark_state_complete load_continue_context launch_continue_script resume_recovery_file_safe retarget_resume_checkpoint; do
    extract_function "$function_name" >> "$SUITE/functions.sh"
done
awk '/^ubuntu_validate_upgrade_versions\(\) \{/ { p=1 } p { print } p && /^}/ { exit }' "$LIBRARY" > "$SUITE/policy.sh"
[[ -s "$SUITE/policy.sh" ]]
source "$SUITE/policy.sh"
for function_name in _state_update_with_jq state_update_with_args; do
    awk -v name="$function_name" '$0 == name "() {" { p=1 } p { print } p && /^}/ { exit }' "$STATE_LIBRARY" >> "$SUITE/state-write.sh"
done
[[ -s "$SUITE/state-write.sh" ]]
source "$SUITE/state-write.sh"
awk '/^log "=== ACFS Upgrade Resume Starting ==="/ { p=1 } p' "$SCRIPT" > "$SUITE/main.sh"
[[ -s "$SUITE/main.sh" ]]
bash -n "$SCRIPT"
bash -n "$SUITE/functions.sh"
bash -n "$SUITE/main.sh"
source "$SUITE/functions.sh"
RESUME_RETARGET_UBUNTU=false

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
    '{"ubuntu_upgrade":{"target_version":"26.99"}}' \
    '{"ubuntu_upgrade":{"target_version":"26.04"}} {"ubuntu_upgrade":{"target_version":"24.04"}}'; do
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
    printf '{"ubuntu_upgrade":{"target_version":"26.04","current_stage":"upgrading"}}' > "$ACFS_STATE_FILE"
    mark_state_complete
    jq -e '.ubuntu_upgrade.current_stage == "completed" and .ubuntu_upgrade.needs_reboot == false' "$ACFS_STATE_FILE" >/dev/null
}
run 'completion is persisted atomically' check_mark_complete
check_failed_write() {
    local scenario="$1" WORK ACFS_STATE_FILE before
    WORK=$(mktemp -d "$SUITE/write.XXXXXX")
    ACFS_STATE_FILE="$WORK/state.json"
    log() { :; }; log_error() { :; }
    printf '{"ubuntu_upgrade":{"target_version":"26.04"}}' > "$ACFS_STATE_FILE"
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
    local UBUNTU_TARGET_VERSION=26.04 UBUNTU_TARGET_VERSION_NUM=2604 state_target_version=26.04
    local BASE_VERSION=24.04 FAKE_ID=ubuntu STAGE=rebooting FAIL_AT='' PLAN=26.04
    local INSTALLED_VERSION=26.04 AUDIT='' EXPECTED_STATUS=0 EXPECTED_HOP=26.04
    local upgrade_lock_fd='' holder_fd=''
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
        if [[ "$1" == /etc/os-release ]]; then
            [[ -f "$WORK/locked" ]] || : > "$WORK/observed-without-lock"
            ID="$FAKE_ID"; VERSION_ID="$BASE_VERSION";
        else builtin source "$@"; fi
    }
    upgrade_acquire_lock() {
        [[ "$FAIL_AT" != lock ]] || return 1
        if [[ "$scenario" == real-lock-* ]]; then
            exec {upgrade_lock_fd}>"$WORK/shared.lock"
            flock -n "$upgrade_lock_fd" || return 1
        fi
        : > "$WORK/locked"
        case "$scenario" in
            changed-target)
                printf '{"ubuntu_upgrade":{"target_version":"26.04"}}' > "$ACFS_STATE_FILE"
                ;;
            corrupted-after-lock) printf '{broken' > "$ACFS_STATE_FILE" ;;
            obsolete-after-lock) printf '{"ubuntu_upgrade":{"target_version":"25.10"}}' > "$ACFS_STATE_FILE" ;;
        esac
        return 0
    }
    upgrade_release_lock() {
        if [[ -n "$upgrade_lock_fd" ]]; then
            flock -u "$upgrade_lock_fd"
            exec {upgrade_lock_fd}>&-
        fi
        : > "$WORK/released"
    }
    ubuntu_configure_release_prompt() { : > "$WORK/channel"; [[ "$FAIL_AT" != channel ]]; }
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
        [[ -f "$WORK/locked" ]] || : > "$WORK/observed-without-lock"
        printf '%s' "$AUDIT"
        if [[ "$FAIL_AT" == audit-status ]]; then return 1; fi
        if [[ "$FAIL_AT" == post-audit && -f "$WORK/upgraded" ]]; then printf 'unconfigured package\n'; fi
    }
    shutdown() { printf '%s\n' "$*" > "$WORK/reboot"; [[ "$FAIL_AT" != shutdown ]]; }
    ubuntu_trigger_reboot() { : > "$WORK/legacy-background-reboot"; return 0; }
    case "$scenario" in
        normal) ;;
        kernel-only) STAGE=pre_upgrade_reboot ;;
        stale-complete) STAGE=completed; BASE_VERSION=22.04; PLAN=$'24.04\n26.04'; INSTALLED_VERSION=24.04; EXPECTED_HOP=24.04 ;;
        at-target) BASE_VERSION=26.04 ;;
        beyond-target) BASE_VERSION=26.04; UBUNTU_TARGET_VERSION=24.04; UBUNTU_TARGET_VERSION_NUM=2404; state_target_version=24.04 ;;
        lock-at-target) BASE_VERSION=26.04; FAIL_AT=lock; EXPECTED_STATUS=1 ;;
        lock-beyond-target) BASE_VERSION=26.04; FAIL_AT=lock; EXPECTED_STATUS=1 ;;
        real-lock-free) BASE_VERSION=26.04 ;;
        real-lock-busy)
            BASE_VERSION=26.04; EXPECTED_STATUS=1
            exec {holder_fd}>"$WORK/shared.lock"
            flock -n "$holder_fd"
            ;;
        changed-target) UBUNTU_TARGET_VERSION=24.04; UBUNTU_TARGET_VERSION_NUM=2404; state_target_version=24.04 ;;
        corrupted-after-lock) EXPECTED_STATUS=1 ;;
        obsolete-after-lock) EXPECTED_STATUS=1 ;;
        library-at-target)
            BASE_VERSION=26.04; EXPECTED_STATUS=1
            printf 'return 1\n' > "$ACFS_LIB_DIR/ubuntu_upgrade.sh"
            ;;
        missing-libraries-at-target) BASE_VERSION=26.04; EXPECTED_STATUS=1; ACFS_LIB_DIR="$WORK/missing-lib" ;;
        bad-os) FAKE_ID=debian; EXPECTED_STATUS=1 ;;
        bad-target) UBUNTU_TARGET_VERSION_NUM=''; EXPECTED_STATUS=1 ;;
        missing-target) state_target_version=''; EXPECTED_STATUS=1 ;;
        backwards) PLAN=22.04; EXPECTED_STATUS=1 ;;
        overshoot) PLAN=28.04; EXPECTED_STATUS=1 ;;
        garbage-hop) PLAN='a[0]'; EXPECTED_STATUS=1 ;;
        no-op) INSTALLED_VERSION=24.04; EXPECTED_STATUS=1 ;;
        wrong-release) INSTALLED_VERSION=25.10; EXPECTED_STATUS=1 ;;
        point-release) INSTALLED_VERSION=26.04.1 ;;
        eol-recovery) BASE_VERSION=25.10 ;;
        eol-host-24) BASE_VERSION=24.10; EXPECTED_STATUS=1 ;;
        eol-host-25) BASE_VERSION=25.04; EXPECTED_STATUS=1 ;;
        future-host) BASE_VERSION=28.04; EXPECTED_STATUS=1 ;;
        future-target) UBUNTU_TARGET_VERSION=28.04; UBUNTU_TARGET_VERSION_NUM=2804; state_target_version=28.04; EXPECTED_STATUS=1 ;;
        obsolete-target) UBUNTU_TARGET_VERSION=25.10; UBUNTU_TARGET_VERSION_NUM=2510; state_target_version=25.10; EXPECTED_STATUS=1 ;;
        eol-above-target) BASE_VERSION=25.10; UBUNTU_TARGET_VERSION=24.04; UBUNTU_TARGET_VERSION_NUM=2404; state_target_version=24.04; EXPECTED_STATUS=1 ;;
        obsolete-library) unset -f ubuntu_validate_upgrade_versions; EXPECTED_STATUS=1 ;;
        audit-output) AUDIT='unconfigured package'; EXPECTED_STATUS=1 ;;
        target-audit) BASE_VERSION=26.04; AUDIT='unconfigured package'; EXPECTED_STATUS=1 ;;
        continuation|mark) BASE_VERSION=26.04; FAIL_AT="$scenario"; EXPECTED_STATUS=1 ;;
        library) printf 'return 1\n' > "$ACFS_LIB_DIR/ubuntu_upgrade.sh"; EXPECTED_STATUS=1 ;;
        state-library) printf 'return 1\n' > "$ACFS_LIB_DIR/state.sh"; EXPECTED_STATUS=1 ;;
        logging-library) printf 'return 1\n' > "$ACFS_LIB_DIR/logging.sh"; EXPECTED_STATUS=1 ;;
        *) FAIL_AT="$scenario"; EXPECTED_STATUS=1 ;;
    esac
    jq -n --arg target "$UBUNTU_TARGET_VERSION" --arg stage "$STAGE" \
        '{ubuntu_upgrade:{target_version:$target,current_stage:$stage,upgrade_path:["24.04","26.04"],completed_upgrades:[{},{}]}}' > "$ACFS_STATE_FILE"
    local result=0
    (set -e; builtin source "$SUITE/main.sh") > "$WORK/stdout" 2> "$WORK/stderr" || result=$?
    assert_eq "$result" "$EXPECTED_STATUS"
    [[ ! -f "$WORK/trusted-checkpoint" && ! -f "$WORK/trusted-path" && ! -f "$WORK/files-removed" ]]
    [[ ! -f "$WORK/legacy-background-reboot" ]]
    [[ ! -f "$WORK/observed-without-lock" ]]
    if [[ "$scenario" == at-target || "$scenario" == beyond-target || "$scenario" == real-lock-free ]]; then
        [[ -f "$WORK/continued" && -f "$WORK/marked" && -f "$WORK/disabled" && ! -f "$WORK/reboot" ]]
        [[ -f "$WORK/locked" && -f "$WORK/released" ]]
    elif [[ "$EXPECTED_STATUS" == 0 ]]; then
        assert_eq "$(cat "$WORK/upgraded")" "$EXPECTED_HOP"
        assert_eq "$(cat "$WORK/reboot")" '-r +1 ACFS: Ubuntu upgrade requires reboot'
        [[ ! -f "$WORK/continued" && ! -f "$WORK/disabled" && -f "$WORK/completed" && -f "$WORK/released" ]]
    else
        if [[ "$FAIL_AT" == lock || "$scenario" == real-lock-busy ]]; then
            [[ ! -f "$WORK/disabled" && ! -f "$WORK/marked" && ! -f "$WORK/locked" ]]
        else
            [[ -f "$WORK/disabled" && -f "$WORK/failure" ]]
        fi
        [[ "$scenario" == continuation || ! -f "$WORK/continued" ]]
        [[ "$scenario" == shutdown || ! -f "$WORK/reboot" ]]
        case "$scenario" in no-op|wrong-release|post-audit|executor) [[ ! -f "$WORK/completed" ]] ;; esac
        case "$scenario" in eol-host-*|future-*|obsolete-*|eol-above-target)
            [[ ! -f "$WORK/channel" && ! -f "$WORK/upgraded" && ! -f "$WORK/marked" ]]
            ;;
        esac
    fi
}
for scenario in normal kernel-only stale-complete at-target beyond-target bad-os bad-target missing-target \
    lock-at-target lock-beyond-target real-lock-free real-lock-busy changed-target corrupted-after-lock \
    library-at-target missing-libraries-at-target \
    obsolete-after-lock point-release eol-recovery eol-host-24 eol-host-25 future-host future-target obsolete-target eol-above-target obsolete-library \
    backwards overshoot garbage-hop no-op wrong-release audit-output target-audit audit-status post-audit \
    continuation mark library state-library logging-library lock channel resumed start plan preflight executor complete reboot-state shutdown; do
    run "resume dispatcher: $scenario" check_dispatch "$scenario"
done

check_context() {
    local scenario="$1" WORK ACFS_CONTINUE_CONTEXT_FILE
    WORK=$(mktemp -d "$SUITE/context.XXXXXX")
    ACFS_CONTINUE_CONTEXT_FILE="$WORK/context.env"
    case "$scenario" in
        missing) ;;
        syntax) printf 'if then\n' > "$ACFS_CONTINUE_CONTEXT_FILE" ;;
        error) printf 'return 1\n' > "$ACFS_CONTINUE_CONTEXT_FILE" ;;
        symlink)
            printf 'CONTINUE_HOME=/root\n' > "$WORK/other.env"
            ln -s "$WORK/other.env" "$ACFS_CONTINUE_CONTEXT_FILE"
            ;;
        valid) printf 'CONTINUE_HOME=/root\n' > "$ACFS_CONTINUE_CONTEXT_FILE" ;;
    esac
    local status=0
    load_continue_context || status=$?
    if [[ "$scenario" == valid ]]; then
        assert_eq "$status" 0
        assert_eq "$CONTINUE_HOME" /root
    else
        assert_eq "$status" 1
    fi
}
for scenario in valid missing syntax error symlink; do
    run "continuation context: $scenario" check_context "$scenario"
done

check_handoff() {
    local scenario="$1" WORK ACFS_RESUME_DIR ACFS_CONTINUE_CONTEXT_FILE ACFS_LOG
    WORK=$(mktemp -d "$SUITE/handoff.XXXXXX")
    ACFS_RESUME_DIR="$WORK/resume"
    ACFS_CONTINUE_CONTEXT_FILE="$WORK/context.env"
    ACFS_LOG="$WORK/log"
    mkdir -p "$ACFS_RESUME_DIR"
    printf '#!/bin/bash\nexit 0\n' > "$ACFS_RESUME_DIR/continue_install.sh"
    # These values deliberately contain spaces and shell punctuation. They
    # must remain single argv values, never evaluated or split by the caller.
    cat > "$ACFS_CONTINUE_CONTEXT_FILE" <<'CONTEXT'
CONTINUE_HOME=/root
CONTINUE_TARGET_USER=dev-user
CONTINUE_TARGET_HOME='/data/dev user'
CONTINUE_ACFS_HOME='/data/dev user/.acfs'
CONTINUE_ACFS_STATE_FILE='/data/dev user/.acfs/state.json'
CONTINUE_ACFS_REF='release/test-$literal;not-a-command'
CONTEXT
    log() { printf '%s\n' "$*" >> "$WORK/log"; [[ "$scenario" != log-failure ]]; }
    log_error() { printf '%s\n' "$*" >> "$WORK/errors"; }
    command() {
        if [[ "$*" == '-v systemd-run' && "$scenario" == missing-run ]]; then return 1; fi
        if [[ "$*" == '-v systemctl' && "$scenario" == missing-systemctl ]]; then return 1; fi
        builtin command "$@"
    }
    systemctl() {
        printf '%s\n' "$*" >> "$WORK/systemctl"
        if [[ "$1" == is-active ]]; then [[ "$scenario" == already-active ]]; else return 1; fi
    }
    systemd-run() {
        printf '%s\0' "$@" >> "$WORK/argv"
        printf 'systemd launch reply\n'
        [[ "$scenario" != rejected && "$scenario" != occupied-unit ]]
    }
    nohup() { : > "$WORK/unsupervised"; return 0; }
    case "$scenario" in
        missing-script) ACFS_RESUME_DIR="$WORK/missing" ;;
        bad-script) printf 'if then\n' > "$ACFS_RESUME_DIR/continue_install.sh" ;;
        linked-script)
            mkdir "$WORK/linked"
            ln -s "$ACFS_RESUME_DIR/continue_install.sh" "$WORK/linked/continue_install.sh"
            ACFS_RESUME_DIR="$WORK/linked"
            ;;
        missing-context) ACFS_CONTINUE_CONTEXT_FILE="$WORK/missing.env" ;;
        bad-context) printf 'return 1\n' > "$ACFS_CONTINUE_CONTEXT_FILE" ;;
    esac
    local status=0
    launch_continue_script || status=$?
    [[ ! -f "$WORK/unsupervised" ]]
    [[ -f "$WORK/resume/continue_install.sh" ]]
    case "$scenario" in
        success|log-failure)
            assert_eq "$status" 0
            local -a args=()
            mapfile -d '' -t args < "$WORK/argv"
            assert_eq "${#args[@]}" 17
            assert_eq "${args[0]}" --collect
            assert_eq "${args[1]}" --no-ask-password
            assert_eq "${args[2]}" --unit=acfs-continue-install
            assert_eq "${args[4]}" --property=Type=exec
            assert_eq "${args[5]}" --property=TimeoutStartSec=120
            assert_eq "${args[6]}" --property=RuntimeMaxSec=7200
            assert_eq "${args[7]}" --property=StandardOutput=journal
            assert_eq "${args[8]}" --property=StandardError=journal
            assert_eq "${args[9]}" --setenv=HOME=/root
            assert_eq "${args[10]}" --setenv=TARGET_USER=dev-user
            assert_eq "${args[11]}" '--setenv=TARGET_HOME=/data/dev user'
            assert_eq "${args[12]}" '--setenv=ACFS_HOME=/data/dev user/.acfs'
            assert_eq "${args[13]}" '--setenv=ACFS_STATE_FILE=/data/dev user/.acfs/state.json'
            assert_eq "${args[14]}" '--setenv=ACFS_REF=release/test-$literal;not-a-command'
            assert_eq "${args[15]}" /bin/bash
            assert_eq "${args[16]}" "$ACFS_RESUME_DIR/continue_install.sh"
            ;;
        already-active)
            assert_eq "$status" 0
            [[ ! -f "$WORK/argv" ]]
            ! grep -q reset-failed "$WORK/systemctl"
            ;;
        rejected|occupied-unit)
            assert_eq "$status" 1
            [[ -s "$WORK/argv" && -s "$WORK/errors" ]]
            ;;
        *) assert_eq "$status" 1; [[ ! -f "$WORK/argv" ]] ;;
    esac
}
for scenario in success log-failure already-active rejected occupied-unit missing-run missing-systemctl \
    missing-script bad-script linked-script missing-context bad-context; do
    run "supervised continuation handoff: $scenario" check_handoff "$scenario"
done

check_args() {
    local expected="$1"; shift
    local RESUME_RETARGET_UBUNTU=true RESUME_HELP=true status=0
    parse_resume_args "$@" || status=$?
    case "$expected" in
        ordinary) assert_eq "$status" 0; assert_eq "$RESUME_RETARGET_UBUNTU" false; assert_eq "$RESUME_HELP" false ;;
        help) assert_eq "$status" 0; assert_eq "$RESUME_HELP" true; assert_eq "$RESUME_RETARGET_UBUNTU" false ;;
        retarget) assert_eq "$status" 0; assert_eq "$RESUME_RETARGET_UBUNTU" true ;;
        rejected) assert_eq "$status" 2; assert_eq "$RESUME_RETARGET_UBUNTU" false ;;
    esac
}
run 'no arguments clear inherited retarget authority' check_args ordinary
run 'explicit retarget argument accepted' check_args retarget --retarget-ubuntu=26.04
run 'help is inert' check_args help --help
run 'unsupported retarget refused' check_args rejected --retarget-ubuntu=28.04
run 'unknown argument refused' check_args rejected --force
run 'duplicate arguments refused' check_args rejected --retarget-ubuntu=26.04 --retarget-ubuntu=26.04

check_retarget_dispatch() {
    local requested_status="$1" WORK RESUME_RETARGET_UBUNTU=true
    WORK=$(mktemp -d "$SUITE/retarget-dispatch.XXXXXX")
    log() { :; }
    retarget_resume_checkpoint() { : > "$WORK/called"; return "$requested_status"; }
    cleanup_service() { : > "$WORK/unwanted-normal-dispatch"; }
    local status=0
    (set -e; builtin source "$SUITE/main.sh") || status=$?
    assert_eq "$status" "$requested_status"
    [[ -f "$WORK/called" && ! -f "$WORK/unwanted-normal-dispatch" ]]
}
run 'retarget success exits before normal upgrade dispatch' check_retarget_dispatch 0
run 'retarget failure exits before normal upgrade dispatch' check_retarget_dispatch 1

check_retarget() {
    local scenario="$1" WORK ACFS_RESUME_DIR ACFS_LIB_DIR ACFS_STATE_FILE ACFS_CONTINUE_CONTEXT_FILE
    WORK=$(mktemp -d "$SUITE/retarget.XXXXXX")
    ACFS_RESUME_DIR="$WORK/resume"
    ACFS_LIB_DIR="$WORK/lib"
    ACFS_STATE_FILE="$ACFS_RESUME_DIR/state.json"
    ACFS_CONTINUE_CONTEXT_FILE="$ACFS_RESUME_DIR/continue_context.env"
    local UBUNTU_TARGET_VERSION=25.10 UBUNTU_TARGET_VERSION_NUM=2510
    local LIVE_VERSION=24.04 OLD_TARGET=25.10 PLAN=26.04 EXPECTED_STATUS=1
    local STATE_LOCK_FD='' UPGRADE_LOCK_FD='' INITIAL_STATE='' STATE_CONTENDED=false
    mkdir -p "$ACFS_RESUME_DIR" "$ACFS_LIB_DIR"
    : > "$ACFS_LIB_DIR/state.sh"
    : > "$ACFS_LIB_DIR/ubuntu_upgrade.sh"
    log() { printf '%s\n' "$*" >> "$WORK/log"; }
    log_error() { log "$*"; }
    upgrade_acquire_lock() {
        [[ "$scenario" != busy-upgrader ]] || return 1
        exec {UPGRADE_LOCK_FD}>"$WORK/upgrade.lock"
        flock -n "$UPGRADE_LOCK_FD" || return 1
        : > "$WORK/locked"
        if [[ "$scenario" == changed-target ]]; then
            jq '.ubuntu_upgrade.target_version = "24.04"' "$ACFS_STATE_FILE" > "$WORK/changed.json"
            mv "$WORK/changed.json" "$ACFS_STATE_FILE"
        fi
    }
    upgrade_release_lock() {
        : > "$WORK/released"
        if [[ -n "$UPGRADE_LOCK_FD" ]]; then flock -u "$UPGRADE_LOCK_FD"; fi
    }
    _state_acquire_lock() {
        [[ "$scenario" != busy-state ]] || return 1
        exec {STATE_LOCK_FD}>"$WORK/state.lock"
        flock -n "$STATE_LOCK_FD" || return 1
        : > "$WORK/state-locked"
        if [[ "$scenario" == changed-state && "$STATE_CONTENDED" == false ]]; then
            STATE_CONTENDED=true
            jq '.ubuntu_upgrade.last_error = "concurrent update"' "$ACFS_STATE_FILE" > "$WORK/changed.json"
            mv "$WORK/changed.json" "$ACFS_STATE_FILE"
        fi
    }
    _state_release_lock() { : > "$WORK/state-released"; flock -u "$STATE_LOCK_FD"; }
    state_get_file() { printf '%s\n' "$ACFS_STATE_FILE"; }
    state_load() { cat "$ACFS_STATE_FILE"; }
    state_write_atomic() {
        [[ -f "$WORK/locked" && -f "$WORK/state-locked" ]] || return 1
        [[ "$scenario" != write-failure ]] || return 1
        local staged
        staged=$(mktemp "$ACFS_STATE_FILE.tmp.XXXXXX") || return 1
        printf '%s\n' "$2" > "$staged" || return 1
        mv "$staged" "$1" || return 1
        : > "$WORK/written"
    }
    ubuntu_get_version_string() { printf '%s\n' "$LIVE_VERSION"; }
    ubuntu_calculate_upgrade_path() {
        [[ "$scenario" != no-path ]] || return 1
        printf '%s' "$PLAN"
    }
    ubuntu_check_apt_state() { [[ "$scenario" != dirty-packages ]]; }
    ubuntu_check_reboot_required() { [[ "$scenario" != pending-reboot ]]; }
    systemctl() {
        if [[ "$*" != 'show --property=ActiveState --value acfs-continue-install.service' ]]; then
            : > "$WORK/service-mutation"; return 99
        fi
        case "$scenario" in
            active-continuation) printf 'active\n' ;;
            activating-continuation) printf 'activating\n' ;;
            systemd-unavailable) return 1 ;;
            unresolved-continuation) printf 'unknown\n' ;;
            *) printf 'inactive\n' ;;
        esac
    }
    ubuntu_do_upgrade() { : > "$WORK/unsafe-operation"; return 99; }
    ubuntu_prepare_eol_repositories() { : > "$WORK/unsafe-operation"; return 99; }
    ubuntu_configure_release_prompt() { : > "$WORK/unsafe-operation"; return 99; }
    shutdown() { : > "$WORK/unsafe-operation"; return 99; }
    launch_continue_script() { : > "$WORK/unsafe-operation"; return 99; }
    case "$scenario" in
        success|two-hops|eol-source|at-new-target|already-retargeted) EXPECTED_STATUS=0 ;;
    esac
    case "$scenario" in
        two-hops) LIVE_VERSION=22.04; PLAN=$'24.04\n26.04' ;;
        eol-source) LIVE_VERSION=25.10 ;;
        at-new-target) LIVE_VERSION=26.04; PLAN='' ;;
        already-retargeted) OLD_TARGET=26.04 ;;
        obsolete-source) LIVE_VERSION=25.04 ;;
        future-source) LIVE_VERSION=28.04 ;;
        future-target) OLD_TARGET=28.04 ;;
    esac
    jq -n --arg target "$OLD_TARGET" '{
        schema_version: 2, preserved_top_level: {value: "untouched"},
        ubuntu_upgrade: {enabled: true, target_version: $target, original_version: "22.04",
            upgrade_path: ["24.04","25.04","25.10"], completed_upgrades: [{from:"22.04",to:"24.04"}],
            current_stage: "error", last_error: "old failure", needs_reboot: true, resume_after_reboot: true,
            current_upgrade: {from:"24.04",to:"25.04"}, custom_field: "retained"}
    }' > "$ACFS_STATE_FILE"
    if [[ "$scenario" == malformed-history ]]; then
        jq '.ubuntu_upgrade.target_migrations = {}' "$ACFS_STATE_FILE" > "$WORK/malformed.json"
        mv "$WORK/malformed.json" "$ACFS_STATE_FILE"
    fi
    INITIAL_STATE=$(cat "$ACFS_STATE_FILE")
    printf 'CONTINUE_INSTALL_ARGS=(--yes --mode safe --only cloud.wrangler --skip-ubuntu-upgrade)\n' > "$ACFS_CONTINUE_CONTEXT_FILE"
    printf '#!/bin/bash\nINSTALL_ARGS=(--yes --mode safe --only cloud.wrangler --skip-ubuntu-upgrade)\nexit 0\n' > "$ACFS_RESUME_DIR/continue_install.sh"
    case "$scenario" in
        missing-skip) printf 'CONTINUE_INSTALL_ARGS=(--yes --mode safe)\n' > "$ACFS_CONTINUE_CONTEXT_FILE" ;;
        argv-mismatch) printf 'CONTINUE_INSTALL_ARGS=(--yes --mode vibe --skip-ubuntu-upgrade)\n' > "$ACFS_CONTINUE_CONTEXT_FILE" ;;
        duplicate-argv) printf 'INSTALL_ARGS=(--skip-ubuntu-upgrade)\n' >> "$ACFS_RESUME_DIR/continue_install.sh" ;;
        malformed-context) printf 'if then\n' > "$ACFS_CONTINUE_CONTEXT_FILE" ;;
        context-error) printf 'return 1\n' > "$ACFS_CONTINUE_CONTEXT_FILE" ;;
        malformed-script) printf 'if then\n' >> "$ACFS_RESUME_DIR/continue_install.sh" ;;
        missing-context) ACFS_CONTINUE_CONTEXT_FILE="$WORK/missing" ;;
        symlink-context)
            ln -s "$ACFS_CONTINUE_CONTEXT_FILE" "$ACFS_RESUME_DIR/linked.env"
            ACFS_CONTINUE_CONTEXT_FILE="$ACFS_RESUME_DIR/linked.env"
            ;;
        hardlink-context) ln "$ACFS_CONTINUE_CONTEXT_FILE" "$WORK/context-copy" ;;
        writable-context) chmod 666 "$ACFS_CONTINUE_CONTEXT_FILE" ;;
        writable-directory) chmod 777 "$ACFS_RESUME_DIR" ;;
        symlink-library)
            ln -s "$ACFS_LIB_DIR" "$WORK/linked-lib"
            ACFS_LIB_DIR="$WORK/linked-lib"
            ;;
        old-library) unset -f ubuntu_validate_upgrade_versions ;;
    esac
    local before_script before_context status=0
    before_script=$(sha256sum "$ACFS_RESUME_DIR/continue_install.sh")
    before_context=$(sha256sum "$ACFS_CONTINUE_CONTEXT_FILE" 2>/dev/null || true)
    retarget_resume_checkpoint || status=$?
    assert_eq "$status" "$EXPECTED_STATUS"
    assert_eq "$(sha256sum "$ACFS_RESUME_DIR/continue_install.sh")" "$before_script"
    assert_eq "$(sha256sum "$ACFS_CONTINUE_CONTEXT_FILE" 2>/dev/null || true)" "$before_context"
    [[ ! -f "$WORK/service-mutation" && ! -f "$WORK/unsafe-operation" ]]
    assert_eq "$UBUNTU_TARGET_VERSION" 25.10
    assert_eq "$UBUNTU_TARGET_VERSION_NUM" 2510
    if [[ "$EXPECTED_STATUS" == 0 && "$scenario" != already-retargeted ]]; then
        jq -e --argjson original "$INITIAL_STATE" --arg live "$LIVE_VERSION" --arg path "$PLAN" '
            .preserved_top_level == $original.preserved_top_level and
            .ubuntu_upgrade.target_version == "26.04" and
            .ubuntu_upgrade.custom_field == "retained" and
            .ubuntu_upgrade.original_version == "22.04" and
            .ubuntu_upgrade.upgrade_path == ($path | split("\n") | map(select(length > 0))) and
            .ubuntu_upgrade.completed_upgrades == [] and
            .ubuntu_upgrade.current_upgrade == null and
            .ubuntu_upgrade.needs_reboot == false and
            .ubuntu_upgrade.resume_after_reboot == false and
            .ubuntu_upgrade.current_stage == "initializing" and
            .ubuntu_upgrade.target_migrations[0].previous == $original.ubuntu_upgrade and
            .ubuntu_upgrade.target_migrations[0].live_version == $live
        ' "$ACFS_STATE_FILE" >/dev/null
        [[ -f "$WORK/written" && -f "$WORK/released" && -f "$WORK/state-released" ]]
        local first_write
        first_write=$(cat "$ACFS_STATE_FILE")
        retarget_resume_checkpoint
        assert_eq "$(cat "$ACFS_STATE_FILE")" "$first_write"
    else
        [[ ! -f "$WORK/written" ]]
        case "$scenario" in
            changed-target) jq -e '.ubuntu_upgrade.target_version == "24.04"' "$ACFS_STATE_FILE" >/dev/null ;;
            changed-state)
                jq -e '.ubuntu_upgrade.last_error == "concurrent update" and .ubuntu_upgrade.target_version == "25.10"' "$ACFS_STATE_FILE" >/dev/null
                [[ -f "$WORK/state-released" ]]
                ;;
            *) assert_eq "$(cat "$ACFS_STATE_FILE")" "$INITIAL_STATE" ;;
        esac
    fi
}
if [[ "$EUID" == 0 ]]; then
    # Ownership is part of the production recovery boundary. Exercise it with
    # real root-owned fixtures rather than replacing the root check in tests.
    for scenario in success two-hops eol-source at-new-target already-retargeted \
        obsolete-source future-source future-target busy-upgrader busy-state changed-target changed-state \
        dirty-packages pending-reboot active-continuation activating-continuation systemd-unavailable \
        unresolved-continuation no-path write-failure malformed-history missing-skip argv-mismatch \
        duplicate-argv malformed-context context-error malformed-script missing-context symlink-context \
        hardlink-context writable-context writable-directory symlink-library old-library; do
        run "explicit checkpoint recovery: $scenario" check_retarget "$scenario"
    done
else
    printf 'SKIP 34 checkpoint recovery filesystem cases: run as root to exercise ownership checks\n'
fi
printf '\n%s passed; %s failed. Fixtures retained at %s\n' "$PASS" "$FAIL" "$SUITE"
[[ "$FAIL" == 0 ]]
