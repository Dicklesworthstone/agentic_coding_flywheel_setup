#!/usr/bin/env bash
# Focused, host-safe regression suite for the 26.04 upgrade path (bd-5ytb5).
# All release discovery, package and reboot operations are replaced by fixtures.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
LIB="$ROOT/scripts/lib/ubuntu_upgrade.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/acfs-lts-tests.XXXXXX")
PASS=0 FAIL=0

log_error() { printf '%s\n' "$*" >&2; }
log_warn() { printf '%s\n' "$*" >&2; }
log_detail() { :; }
log_step() { :; }
log_section() { :; }
log_success() { :; }
log_info() { :; }
unset UBUNTU_TARGET_VERSION UBUNTU_TARGET_VERSION_NUM
source "$LIB"

# The host OS is the boundary under test. A persistent file models changes
# made by a release-upgrader subprocess without touching /etc/os-release.
MOCK_CURRENT=2404
ubuntu_get_version_number() {
    if [[ -f "$WORK/installed" ]]; then cat "$WORK/installed"; else printf '%s\n' "$MOCK_CURRENT"; fi
}
ubuntu_version_gte() { [[ "$1" -ge "$2" ]]; }

assert_eq() { [[ "$1" == "$2" ]] || { printf 'expected <%s>, got <%s>\n' "$2" "$1" >&2; return 1; }; }
assert_failure() {
    if "$@" > "$WORK/refusal.out" 2> "$WORK/refusal.err"; then
        printf 'unexpected success: %s\n' "$*" >&2; return 1
    fi
    [[ ! -s "$WORK/refusal.out" ]] || { printf 'refusal emitted a partial plan\n' >&2; return 1; }
}
run() {
    local name="$1" result; shift
    set +e
    (set -e; "$@") > "$WORK/case.log" 2>&1
    result=$?
    set -e
    if [[ $result == 0 ]]; then
        PASS=$((PASS+1)); printf 'PASS %s\n' "$name"
    else
        FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$name"; cat "$WORK/case.log"
    fi
}
check_default() { assert_eq "$UBUNTU_TARGET_VERSION" 26.04; assert_eq "$UBUNTU_TARGET_VERSION_NUM" 2604; }
check_source_target() {
    local target="$1" expected="$2"
    local output
    output=$(UBUNTU_TARGET_VERSION="$target" UBUNTU_TARGET_VERSION_NUM=2510 bash -c \
        'source "$1" || exit; printf "%s" "$UBUNTU_TARGET_VERSION_NUM"' _ "$LIB")
    assert_eq "$output" "$expected"
}
check_bad_target() {
    assert_failure env UBUNTU_TARGET_VERSION="$1" bash -c 'source "$1"' _ "$LIB"
}
check_path() { MOCK_CURRENT="$1"; assert_eq "$(ubuntu_calculate_upgrade_path "$2")" "$3"; }
check_bad_path() { MOCK_CURRENT="$1"; assert_failure ubuntu_calculate_upgrade_path "$2"; }
check_bad_edge() {
    MOCK_CURRENT=2404
    ubuntu_get_next_version_hardcoded() { printf '%s\n' "$BAD_EDGE"; }
    BAD_EDGE="$1"
    assert_failure ubuntu_calculate_upgrade_path 2604
}
run 'default is 26.04 and numeric target is derived' check_default
run 'stale numeric target cannot override 26.04' check_source_target 26.04 2604
run 'explicit supported target 24.04 remains available' check_source_target 24.04 2404
for target in 20.04 24.10 25.04 25.10 26.10 28.04 99.99 26.04.1 '26.04;exit 0' 'a[0]'; do
    run "refuse target $target" check_bad_target "$target"
done
run '22.04 to 26.04 follows both LTS hops' check_path 2204 2604 $'24.04\n26.04'
run '24.04 upgrades directly to 26.04' check_path 2404 2604 26.04
run '25.10 recovery upgrades to 26.04' check_path 2510 2604 26.04
run 'explicit 24.04 target never overshoots' check_path 2204 2404 24.04
run '26.04 no-op has empty output' check_path 2604 2604 ''
run 'newer supported LTS is not downgraded' check_path 2604 2404 ''
for source in 2004 2410 2504 2610 2804 unknown 'a[0]'; do
    run "refuse unreviewed source $source" check_bad_path "$source" 2604
done
run 'EOL host cannot masquerade as already above older target' check_bad_path 2510 2404
for target in 2510 2610 2804 'a[0]'; do
    run "refuse unreviewed numeric target $target" check_bad_path 2404 "$target"
done
for edge in 24.04 25.10 26.10 garbage '26.04;echo unsafe'; do
    run "reject nonprogressing/unknown graph edge $edge" check_bad_edge "$edge"
done

check_prompt() {
    local source="$1" initial="$2" expected="$3"
    local dir config
    dir=$(mktemp -d "$WORK/channel.XXXXXX"); config="$dir/release-upgrades"
    printf '# preserved comment\n[DEFAULT]\nPrompt=%s\nOther=value\n' "$initial" > "$config"
    chmod 640 "$config"
    MOCK_CURRENT="$source"
    ubuntu_configure_release_prompt "$config"
    grep -qx "Prompt=$expected" "$config"
    grep -qx 'Other=value' "$config"
    assert_eq "$(stat -c %a "$config")" 640
    if [[ "$initial" == "$expected" ]]; then
        [[ ! -e "$config.disabled" ]]
    else
        grep -qx "Prompt=$initial" "$config.disabled"
        ubuntu_configure_release_prompt "$config"
        grep -qx "Prompt=$initial" "$config.disabled"
    fi
}
check_invalid_prompt() {
    local content="$1" dir config original
    dir=$(mktemp -d "$WORK/channel.XXXXXX"); config="$dir/release-upgrades"
    printf '%s\n' "$content" > "$config"; original=$(cat "$config")
    assert_failure ubuntu_configure_release_prompt "$config"
    assert_eq "$(cat "$config")" "$original"
    [[ ! -e "$config.disabled" ]]
}
check_symlink_prompt() {
    local dir
    dir=$(mktemp -d "$WORK/symlink.XXXXXX")
    mkdir "$dir/real"
    printf '[DEFAULT]\nPrompt=normal\n' > "$dir/real/config"
    ln -s "$dir/real" "$dir/link"
    assert_failure ubuntu_configure_release_prompt "$dir/link/config"
    grep -qx 'Prompt=normal' "$dir/real/config"
    [[ ! -e "$dir/real/config.disabled" ]]
}
check_hardlink_prompt() {
    local dir
    dir=$(mktemp -d "$WORK/hardlink.XXXXXX")
    printf '[DEFAULT]\nPrompt=normal\n' > "$dir/config"
    ln "$dir/config" "$dir/alias"
    assert_failure ubuntu_configure_release_prompt "$dir/config"
    grep -qx 'Prompt=normal' "$dir/alias"
}
for source in 2204 2404; do
    for initial in normal never lts; do
        run "channel $source/$initial becomes lts idempotently" check_prompt "$source" "$initial" lts
    done
done
run '25.10 recovery uses normal channel' check_prompt 2510 lts normal
run 'duplicate prompt config refused without mutation' check_invalid_prompt $'[DEFAULT]\nPrompt=lts\nPrompt=normal'
run 'missing prompt refused without mutation' check_invalid_prompt '[DEFAULT]'
run 'wrong section refused without mutation' check_invalid_prompt $'[OTHER]\nPrompt=normal'
run 'malformed prompt refused without mutation' check_invalid_prompt $'[DEFAULT]\nPrompt=garbage'
run 'symlinked parent refused before writing backup' check_symlink_prompt
run 'hardlinked config refused before replacement' check_hardlink_prompt

check_discovery() {
    local MOCK_RELEASE_OUTPUT="$1" MOCK_RELEASE_STATUS="$2" expected="$3"
    ubuntu_configure_release_prompt() { :; }
    do-release-upgrade() {
        [[ "$*" == '-c' ]] || return 99
        [[ "$LC_ALL" == C && "$LANG" == C ]] || return 98
        printf '%s\n' "$MOCK_RELEASE_OUTPUT"; return "$MOCK_RELEASE_STATUS"
    }
    if [[ "$expected" == REFUSE ]]; then
        assert_failure ubuntu_get_next_upgrade
    else
        assert_eq "$(ubuntu_get_next_upgrade)" "$expected"
    fi
}
run 'parse stable release announcement' check_discovery "New release '26.04' available." 0 26.04
run 'parse LTS point release announcement' check_discovery "New release '26.04.1 LTS' available." 0 26.04
run 'parse CRLF announcement and informational lines' check_discovery $'Checking for a new Ubuntu release\r\nNew release \'26.04 LTS\' available.\r' 0 26.04
run 'nonzero discovery cannot authorize an upgrade' check_discovery "New release '26.04' available." 1 REFUSE
run 'closed rollout gate fails closed' check_discovery 'No new release found.' 0 REFUSE
run 'ambiguous announcements fail closed' check_discovery $'New release \'24.04\' available.\nNew release \'26.04\' available.' 0 REFUSE
run 'version inside arbitrary text is not an offer' check_discovery "Warning: New release '26.04' available. Retry later." 0 REFUSE
run 'malformed release is not an offer' check_discovery "New release '26.04.invalid' available." 0 REFUSE

check_execution() {
    local scenario="$1" root="$WORK" WORK
    WORK=$(mktemp -d "$root/execution.XXXXXX")
    local MOCK_CURRENT=2404 OFFER=26.04 REFRESH=26.04 RESULT_OS=2604
    local QUERY_STATUS=0 PREP_STATUS=0 EXEC_STATUS=0 AUDIT_STATUS=0 AUDIT_TEXT=''
    local KERNEL_REBOOT=0 STATE_STATUS=0 SETUP_STATUS=0 SHUTDOWN_STATUS=0
    local expected=0 caller=26.04 phase=executed
    local ACFS_RESUME_DIR="$WORK/resume" SCRIPT_DIR="$WORK/source" ACFS_BOOTSTRAP_DIR=''
    mkdir -p "$SCRIPT_DIR" "$ACFS_RESUME_DIR"
    # The actual upgrader runs in a subshell; model observed OS changes in a file.
    ubuntu_get_next_upgrade() {
        local count=0
        [[ ! -f "$WORK/queries" ]] || count=$(cat "$WORK/queries")
        printf '%s\n' "$((count+1))" > "$WORK/queries"
        [[ "$QUERY_STATUS" == 0 ]] || return "$QUERY_STATUS"
        if [[ "$count" == 0 ]]; then printf '%s\n' "$OFFER"; else printf '%s\n' "$REFRESH"; fi
    }
    ubuntu_prepare_upgrade() { : > "$WORK/prepared"; return "$PREP_STATUS"; }
    ubuntu_check_reboot_required() { [[ "$KERNEL_REBOOT" == 0 ]]; }
    do-release-upgrade() {
        printf '%s\n' "$*" > "$WORK/executed"
        [[ "$LC_ALL" == C && "$LANG" == C ]] || return 97
        assert_eq "$*" '-f DistUpgradeViewNonInteractive' || return 98
        printf '%s\n' "$RESULT_OS" > "$WORK/installed"
        return "$EXEC_STATUS"
    }
    dpkg() { assert_eq "$*" '--audit'; printf '%s' "$AUDIT_TEXT"; return "$AUDIT_STATUS"; }
    apt-mark() { assert_eq "$*" showhold; }
    state_update() { printf '%s\n' "$*" > "$WORK/state-write"; return "$STATE_STATUS"; }
    upgrade_setup_infrastructure() { printf '%s\n' "$@" > "$WORK/setup"; return "$SETUP_STATUS"; }
    upgrade_update_motd() { :; }
    systemctl() { :; }
    sleep() { :; }
    shutdown() { printf '%s\n' "$*" > "$WORK/reboot"; return "$SHUTDOWN_STATUS"; }
    local ACFS_UPGRADE_ORIGINAL_ARGS=(--yes --mode safe --skip-cloud --target-ubuntu 26.04)

    case "$scenario" in
        success) ;;
        first-lts-hop) MOCK_CURRENT=2204; caller=24.04; OFFER=24.04; REFRESH=24.04; RESULT_OS=2404 ;;
        eol-recovery-hop) MOCK_CURRENT=2510 ;;
        stale-caller) caller=25.10; expected=1; phase=none ;;
        unsupported-source) MOCK_CURRENT=2504; expected=1; phase=none ;;
        no-upgrade-needed) MOCK_CURRENT=2604; expected=1; phase=none ;;
        higher-offer) OFFER=26.10; expected=1; phase=queried ;;
        lower-offer) OFFER=25.10; expected=1; phase=queried ;;
        same-version-offer) OFFER=24.04; expected=1; phase=queried ;;
        closed-rollout) QUERY_STATUS=1; expected=1; phase=queried ;;
        prepare-failed) PREP_STATUS=1; expected=1; phase=prepared ;;
        changed-offer) REFRESH=26.10; expected=1; phase=prepared ;;
        lost-offer) REFRESH=''; expected=1; phase=prepared ;;
        upgrader-failed) EXEC_STATUS=1; expected=1 ;;
        exit-zero-no-upgrade) RESULT_OS=2404; expected=1 ;;
        wrong-installed-release) RESULT_OS=2610; expected=1 ;;
        audit-error) AUDIT_STATUS=1; expected=1 ;;
        audit-diagnostics-with-exit-zero) AUDIT_TEXT='Unconfigured packages remain'; expected=1 ;;
        audit-whitespace) AUDIT_TEXT=$' \n\t' ;;
        kernel-reboot) KERNEL_REBOOT=1; phase=reboot ;;
        kernel-state-write-failed) KERNEL_REBOOT=1; STATE_STATUS=1; expected=1; phase=prepared ;;
        kernel-resume-setup-failed) KERNEL_REBOOT=1; SETUP_STATUS=1; expected=1; phase=prepared ;;
        kernel-shutdown-failed) KERNEL_REBOOT=1; SHUTDOWN_STATUS=1; expected=1; phase=reboot ;;
        reused-kernel-reboot|reused-kernel-state-write-failed|reused-kernel-shutdown-failed)
            KERNEL_REBOOT=1; SCRIPT_DIR=''; phase=reboot
            printf '#!/bin/bash\n' > "$ACFS_RESUME_DIR/upgrade_resume.sh"
            chmod +x "$ACFS_RESUME_DIR/upgrade_resume.sh"
            : > "$ACFS_RESUME_DIR/continue_context.env"
            if [[ "$scenario" == reused-kernel-state-write-failed ]]; then STATE_STATUS=1; expected=1; phase=prepared; fi
            if [[ "$scenario" == reused-kernel-shutdown-failed ]]; then SHUTDOWN_STATUS=1; expected=1; fi
            ;;
        *) printf 'unknown scenario\n' >&2; return 1 ;;
    esac
    local result=0
    # Successful kernel-reboot paths intentionally exit, so isolate the call.
    (ubuntu_do_upgrade "$caller") > "$WORK/stdout" 2> "$WORK/stderr" || result=$?
    assert_eq "$result" "$expected"
    case "$phase" in
        none) [[ ! -e "$WORK/queries" && ! -e "$WORK/prepared" && ! -e "$WORK/executed" ]] ;;
        queried) [[ -e "$WORK/queries" && ! -e "$WORK/prepared" && ! -e "$WORK/executed" ]] ;;
        prepared) [[ -e "$WORK/prepared" && ! -e "$WORK/executed" && ! -e "$WORK/reboot" ]] ;;
        executed) [[ -e "$WORK/executed" && ! -e "$WORK/reboot" ]]; assert_eq "$(cat "$WORK/queries")" 2 ;;
        reboot) [[ -e "$WORK/reboot" && ! -e "$WORK/executed" && -e "$WORK/state-write" ]] ;;
    esac
    if [[ "$scenario" == kernel-reboot ]]; then
        assert_eq "$(tail -n +2 "$WORK/setup")" $'--yes\n--mode\nsafe\n--skip-cloud\n--target-ubuntu\n26.04'
    fi
}
for scenario in success first-lts-hop eol-recovery-hop stale-caller unsupported-source no-upgrade-needed \
    higher-offer lower-offer same-version-offer closed-rollout prepare-failed changed-offer lost-offer \
    upgrader-failed exit-zero-no-upgrade wrong-installed-release audit-error audit-diagnostics-with-exit-zero \
    audit-whitespace kernel-reboot kernel-state-write-failed kernel-resume-setup-failed kernel-shutdown-failed \
    reused-kernel-reboot reused-kernel-state-write-failed reused-kernel-shutdown-failed; do
    run "executor: $scenario" check_execution "$scenario"
done

check_reboot_schedule() {
    local delay="$1" shutdown_result="$2" expected="$3" result=0
    local marker
    marker=$(mktemp "$WORK/reboot.XXXXXX")
    shutdown() { printf '%s\n' "$*" > "$marker"; return "$shutdown_result"; }
    ubuntu_trigger_reboot "$delay" > /dev/null || result=$?
    assert_eq "$result" "$expected"
    if [[ "$delay" =~ ^[0-9]{1,3}$ ]]; then
        assert_eq "$(cat "$marker")" "-r +$delay ACFS: Ubuntu upgrade requires reboot"
    else
        [[ ! -s "$marker" ]]
    fi
}
run 'synchronous scheduling reports shutdown success' check_reboot_schedule 1 0 0
run 'synchronous scheduling reports shutdown failure' check_reboot_schedule 1 1 1
run 'invalid reboot delay never invokes shutdown' check_reboot_schedule '-now' 0 1

check_sequence() {
    local scenario="$1" root="$WORK" WORK
    WORK=$(mktemp -d "$root/sequence.XXXXXX")
    local ACFS_RESUME_DIR="$WORK/resume" MOCK_CURRENT=2204 FAILURE='' expected=0
    mkdir -p "$ACFS_RESUME_DIR"
    printf '{"ubuntu_upgrade":{}}\n' > "$ACFS_RESUME_DIR/state.json"
    local ACFS_UPGRADE_ORIGINAL_ARGS=()
    ubuntu_get_version_string() { printf '22.04\n'; }
    upgrade_acquire_lock() { [[ "$FAILURE" != lock ]]; }
    upgrade_release_lock() { : > "$WORK/released"; }
    state_upgrade_init() {
        assert_eq "$1" 22.04 || return 99
        assert_eq "$2" 26.04 || return 99
        assert_eq "$(jq -c . <<< "$3")" '["24.04","26.04"]' || return 99
        [[ "$FAILURE" != init ]]
    }
    upgrade_setup_infrastructure() { printf '%s\n' "$@" > "$WORK/args"; [[ "$FAILURE" != infrastructure ]]; }
    upgrade_update_motd() { :; }
    state_upgrade_start() { [[ "$FAILURE" != start ]]; }
    ubuntu_do_upgrade() { assert_eq "$1" 24.04; : > "$WORK/executed"; [[ "$FAILURE" != executor ]]; }
    state_upgrade_set_error() { : > "$WORK/error"; }
    state_upgrade_complete() { : > "$WORK/completion"; [[ "$FAILURE" != complete ]]; }
    state_upgrade_needs_reboot() { : > "$WORK/reboot-state"; [[ "$FAILURE" != reboot-state ]]; }
    state_get_file() {
        [[ "$FAILURE" != state-missing ]] || return 1
        printf '%s\n' "$ACFS_RESUME_DIR/state.json"
    }
    ubuntu_trigger_reboot() { : > "$WORK/reboot"; [[ "$FAILURE" != shutdown ]]; }
    case "$scenario" in
        success) ;;
        unsupported-source) MOCK_CURRENT=2504; expected=1 ;;
        *) FAILURE="$scenario"; expected=1 ;;
    esac
    local result=0
    ubuntu_start_upgrade_sequence "$WORK" --yes --mode safe --skip-cloud > /dev/null || result=$?
    assert_eq "$result" "$expected"
    if [[ "$expected" == 0 ]]; then
        assert_eq "${ACFS_UPGRADE_ORIGINAL_ARGS[*]}" '--yes --mode safe --skip-cloud'
        assert_eq "$(tail -n +2 "$WORK/args")" $'--yes\n--mode\nsafe\n--skip-cloud'
        [[ -f "$WORK/reboot" && -f "$WORK/completion" && -f "$WORK/reboot-state" ]]
    elif [[ "$scenario" == shutdown ]]; then
        [[ -f "$WORK/error" && -f "$WORK/released" ]]
    else
        [[ ! -f "$WORK/reboot" ]]
    fi
    case "$scenario" in
        start|infrastructure|init|lock|unsupported-source) [[ ! -f "$WORK/executed" ]] ;;
        executor) [[ ! -f "$WORK/completion" ]] ;;
    esac
}
for scenario in success unsupported-source lock init infrastructure start executor complete reboot-state state-missing shutdown; do
    run "orchestration: $scenario" check_sequence "$scenario"
done

printf '\n%s passed; %s failed. Fixture artifacts: %s\n' "$PASS" "$FAIL" "$WORK"
[[ "$FAIL" == 0 ]]
