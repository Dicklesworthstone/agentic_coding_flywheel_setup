#!/usr/bin/env bats

load '../test_helper'

setup() {
    common_setup
    source_lib "logging"
    source_lib "error_tracking"
}

teardown() {
    common_teardown
}

@test "installation summary points to an implemented recovery command" {
    track_failed_tool "example-tool" "installer failed"

    run print_install_summary

    assert_success
    assert_output --partial "acfs doctor"
    assert_output --partial "manifest-bound Fix command"
    refute_output --partial "acfs install --retry-failed"
}

@test "failed-tools retry defaults fail clearly without HOME context" {
    run env -i PATH="/usr/bin:/bin" bash -c 'set -euo pipefail; source "$1"; source "$2"; save_failed_tools_for_retry' _ "$PROJECT_ROOT/scripts/lib/logging.sh" "$PROJECT_ROOT/scripts/lib/error_tracking.sh"
    assert_failure
    assert_output --partial "Unable to resolve failed-tools retry file"
    refute_output --partial "unbound variable"

    run env -i PATH="/usr/bin:/bin" bash -c 'set -euo pipefail; source "$1"; source "$2"; load_failed_tools_for_retry' _ "$PROJECT_ROOT/scripts/lib/logging.sh" "$PROJECT_ROOT/scripts/lib/error_tracking.sh"
    assert_failure
    assert_output --partial "Unable to resolve failed-tools retry file"
    refute_output --partial "unbound variable"
}

@test "failed-tools retry defaults use TARGET_HOME when HOME is absent" {
    local target_home
    target_home="$(create_temp_dir)"

    run env -i PATH="/usr/bin:/bin" TARGET_HOME="$target_home" bash -c 'set -euo pipefail; source "$1"; source "$2"; track_failed_tool atuin "hook missing"; save_failed_tools_for_retry; clear_install_tracking; load_failed_tools_for_retry; get_failed_tools_list' _ "$PROJECT_ROOT/scripts/lib/logging.sh" "$PROJECT_ROOT/scripts/lib/error_tracking.sh"
    assert_success
    assert_output --partial "atuin"
}

@test "try_step preserves caller errexit-off state" {
    run env -i PATH="/usr/bin:/bin" bash -c '
        set +e
        source "$1"
        before=$-
        try_step "successful command" true >/dev/null 2>&1
        after_success=$-
        status=0
        try_step "failing command" false >/dev/null 2>&1 || status=$?
        after_failure=$-
        [[ "$after_success" != *e* ]] || exit 2
        [[ "$after_failure" != *e* ]] || exit 3
        printf "status=%s\nbefore=%s\nafter_success=%s\nafter_failure=%s\n" \
            "$status" "$before" "$after_success" "$after_failure"
    ' _ "$PROJECT_ROOT/scripts/lib/error_tracking.sh"

    assert_success
    assert_output --partial "status=1"
    assert_output --partial "after_success="
    assert_output --partial "after_failure="
}

@test "try_step retains a required failure after later successful commands" {
    source_lib state
    export ACFS_HOME="$(create_temp_dir)"
    export ACFS_STATE_FILE="$ACFS_HOME/state.json"
    state_init
    set_phase cli_tools

    run try_step 'Installing required packages' bash -c 'printf "sudo: a password is required\n" >&2; exit 1'
    assert_failure
    try_step 'Writing informational log' true

    run clear_phase
    assert_failure
    run state_is_phase_completed cli_tools
    assert_failure
    run state_get '.failed_step'
    assert_output 'Installing required packages'
}

@test "optional wrapper keeps nested package failures optional" {
    source_lib state
    export ACFS_HOME="$(create_temp_dir)"
    export ACFS_STATE_FILE="$ACFS_HOME/state.json"
    state_init
    set_phase cli_tools
    nested_installer() { try_step 'Nested privileged command' false; }

    run try_step_optional 'Optional package' nested_installer
    assert_failure
    run state_get '.phase_steps.cli_tools["Nested privileged command"].required | tostring'
    assert_output false
    run state_get '.phase_steps.cli_tools["Optional package"].status'
    assert_output failed
    run clear_phase
    assert_success
}

@test "optional nested steps preserve the required failure diagnosis" {
    source_lib state
    export ACFS_HOME="$(create_temp_dir)"
    export ACFS_STATE_FILE="$ACFS_HOME/state.json"
    state_init
    set_phase cli_tools
    try_step 'Required packages' false || true
    local required_error="$LAST_ERROR" required_code="$LAST_ERROR_CODE"
    optional_installer() { try_step 'Nested optional failure' false; }
    try_step_optional optional optional_installer || true
    [[ "$LAST_ERROR" == "$required_error" ]]
    [[ "$LAST_ERROR_CODE" == "$required_code" ]]
    run state_get '.failed_step'
    assert_output 'Required packages'
}

@test "retry wrapper resolves only the successful step result" {
    source_lib state
    export ACFS_HOME="$(create_temp_dir)"
    export ACFS_STATE_FILE="$ACFS_HOME/state.json"
    state_init
    set_phase languages

    try_step 'Separate failure' false || true
    try_step_retry 1 0 'Install runtime' false || true
    try_step_retry 1 0 'Install runtime' true

    run state_get '.phase_steps.languages["Install runtime"].status'
    assert_output success
    run state_phase_complete languages
    assert_failure
    try_step 'Separate failure' true
    run state_phase_complete languages
    assert_success
}

@test "run_phase opens one attempt when installer also calls set_phase" {
    source_lib state
    export ACFS_HOME="$(create_temp_dir)"
    export ACFS_STATE_FILE="$ACFS_HOME/state.json"
    state_init
    fixture_installer() {
        set_phase cli_tools
        try_step packages true
    }

    run run_phase cli_tools 'CLI Tools' fixture_installer
    assert_success
    run state_get '.phase_attempts.cli_tools'
    assert_output 1
}

# Exercise the actual authored language/tool functions, try_step and run_phase
# against inert installer/package commands. Ready markers stand in for the
# installed binaries, so retries use the same skip decisions as a real run.
setup_language_phase_fixture() {
    source_lib state
    export TARGET_HOME="$BATS_TEST_TMPDIR/language-home"
    export TARGET_USER="$(id -un)"
    export ACFS_HOME="$BATS_TEST_TMPDIR/language-state"
    export ACFS_STATE_FILE="$ACFS_HOME/state.json"
    export ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
    export LANGUAGE_ATTEMPTS="$BATS_TEST_TMPDIR/language-attempts"
    ACFS_DISTRO_FAMILY=debian
    ACFS_MODULE_FAILURES=()
    LANGUAGE_FAILURES=""
    LANGUAGE_APT_AVAILABLE=true
    SUDO=""
    mkdir -p "$TARGET_HOME/ready"
    : > "$LANGUAGE_ATTEMPTS"

    local missing=" ${1:-tools.atuin tools.zoxide} " module
    for module in lang.bun lang.rust lang.go lang.uv lang.nvm tools.ast_grep tools.atuin tools.zoxide; do
        [[ "$missing" == *" $module "* ]] || touch "$TARGET_HOME/ready/$module"
    done

    # The tools function contains a heredoc with column-zero closing braces;
    # extract the entire phase rather than stopping at the first such brace.
    eval "$(sed -n '/^install_languages_legacy_lang() {$/,/^install_agy_locked_launchers() {$/p' "$PROJECT_ROOT/install.sh" | sed '$d')"

    language_attempt() {
        local name="$1" module_id="$2"
        printf '%s\n' "$name" >> "$LANGUAGE_ATTEMPTS"
        ACFS_LAST_MODULE_FAILURE_REASON=""
        if [[ " $LANGUAGE_FAILURES " == *" $name "* ]]; then
            ACFS_LAST_MODULE_FAILURE_REASON=checksum
            printf 'checksum mismatch for %s\n' "$name" >&2
            return 65
        fi
        touch "$TARGET_HOME/ready/$module_id"
    }
    acfs_should_skip_module() { [[ -f "$TARGET_HOME/ready/$1" ]]; }
    acfs_use_generated_category() { return 1; }
    acfs_run_verified_upstream_script_as_target() {
        local category=lang
        [[ "$1" != zoxide ]] || category=tools
        language_attempt "$1" "$category.$1"
    }
    acfs_run_verified_upstream_script_as_target_with_env() {
        [[ "$1" == atuin && "$2" == sh && "$3" == ATUIN_NO_MODIFY_PATH=1 ]] || return 99
        language_attempt atuin tools.atuin
    }
    _ensure_target_nvm_node() {
        acfs_should_skip_module lang.nvm || language_attempt nvm lang.nvm
    }
    apt-cache() { [[ "$LANGUAGE_APT_AVAILABLE" == true ]]; }
    apt-get() {
        case "${!#}" in
            zoxide) language_attempt apt:zoxide tools.zoxide ;;
            golang-go) language_attempt apt:go lang.go ;;
            *) return 99 ;;
        esac
    }
    acfs_arch_pkg_install() { language_attempt "pacman:$1" "tools.$1"; }
    run_as_target() { "$@"; }
    acfs_verify_phase() {
        local module_id
        for module_id in lang.bun lang.rust lang.go lang.uv lang.nvm tools.ast_grep tools.atuin tools.zoxide; do
            acfs_should_skip_module "$module_id" || return 1
        done
    }
    run_language_phase_fixture() {
        local phase_status=0
        run_phase languages '5/9 Languages' install_languages || phase_status=$?
        printf '%s\n' "${ACFS_MODULE_FAILURES[@]}"
        return "$phase_status"
    }
    state_init
}

@test "language phase: Atuin failure still installs Zoxide and retries only missing tools" {
    setup_language_phase_fixture
    LANGUAGE_FAILURES=atuin

    run run_language_phase_fixture
    assert_failure
    assert_output --partial 'tools.atuin (checksum)'
    [[ "$(cat "$LANGUAGE_ATTEMPTS")" == $'atuin\napt:zoxide' ]]
    jq -e '.phase_steps.languages["Installing Atuin"].status == "failed"
        and .phase_steps.languages["Installing Atuin"].required == true
        and .phase_steps.languages["Installing Zoxide (apt)"].status == "success"
        and (.completed_phases | index("languages")) == null
        and (.partial_phases | index("languages")) != null' "$ACFS_STATE_FILE"

    run run_language_phase_fixture
    assert_failure
    [[ "$(cat "$LANGUAGE_ATTEMPTS")" == $'atuin\napt:zoxide\natuin' ]]

    LANGUAGE_FAILURES=""
    run run_language_phase_fixture
    assert_success
    [[ "$(cat "$LANGUAGE_ATTEMPTS")" == $'atuin\napt:zoxide\natuin\natuin' ]]
    run state_is_phase_completed languages
    assert_success
    run state_has_required_failures
    assert_failure
}

@test "language phase: unavailable Zoxide package uses the verified upstream fallback" {
    setup_language_phase_fixture tools.zoxide
    LANGUAGE_APT_AVAILABLE=false

    run run_language_phase_fixture
    assert_success
    [[ "$(cat "$LANGUAGE_ATTEMPTS")" == zoxide ]]
    run state_is_phase_completed languages
    assert_success
}

@test "language phase: failed Zoxide package recovers through verified upstream without a required failure" {
    setup_language_phase_fixture tools.zoxide
    LANGUAGE_FAILURES=apt:zoxide

    run run_language_phase_fixture
    assert_success
    [[ "$(cat "$LANGUAGE_ATTEMPTS")" == $'apt:zoxide\nzoxide' ]]
    jq -e '.phase_steps.languages["Installing Zoxide (apt)"].status == "failed"
        and .phase_steps.languages["Installing Zoxide (apt)"].required == false
        and .phase_steps.languages["Installing Zoxide (upstream)"].status == "success"' "$ACFS_STATE_FILE"
    run state_has_required_failures
    assert_failure
}

@test "language phase: independent Atuin and Zoxide failures are both reported on Debian" {
    setup_language_phase_fixture
    LANGUAGE_FAILURES='atuin apt:zoxide zoxide'

    run run_language_phase_fixture
    assert_failure
    assert_output --partial 'tools.atuin (checksum)'
    assert_output --partial 'tools.zoxide (checksum)'
    [[ "$(cat "$LANGUAGE_ATTEMPTS")" == $'atuin\napt:zoxide\nzoxide' ]]
    run state_is_phase_completed languages
    assert_failure
}

@test "language phase: independent Atuin and Zoxide failures are both reported on Arch" {
    setup_language_phase_fixture
    ACFS_DISTRO_FAMILY=arch
    LANGUAGE_FAILURES='atuin pacman:zoxide zoxide'

    run run_language_phase_fixture
    assert_failure
    assert_output --partial 'tools.atuin (checksum)'
    assert_output --partial 'tools.zoxide (checksum)'
    [[ "$(cat "$LANGUAGE_ATTEMPTS")" == $'atuin\npacman:zoxide\nzoxide' ]]
    run state_is_phase_completed languages
    assert_failure
}

@test "language phase: missing Cargo does not prevent unrelated tools from installing" {
    setup_language_phase_fixture 'tools.ast_grep tools.atuin tools.zoxide'

    run run_language_phase_fixture
    assert_failure
    assert_output --partial 'tools.ast_grep (cargo unavailable)'
    [[ "$(cat "$LANGUAGE_ATTEMPTS")" == $'atuin\napt:zoxide' ]]
    run state_is_phase_completed languages
    assert_failure
}

@test "language phase: every independent runtime is attempted after preceding failures" {
    setup_language_phase_fixture 'lang.bun lang.rust lang.go lang.uv lang.nvm tools.atuin tools.zoxide'
    LANGUAGE_FAILURES='bun rust apt:go uv nvm'

    run run_language_phase_fixture
    assert_failure
    assert_output --partial 'lang.bun (checksum)'
    assert_output --partial 'lang.rust (checksum)'
    assert_output --partial 'lang.go (package installation failed)'
    assert_output --partial 'lang.uv (checksum)'
    assert_output --partial 'lang.nvm (checksum)'
    [[ "$(cat "$LANGUAGE_ATTEMPTS")" == $'bun\nrust\napt:go\nuv\nnvm\natuin\napt:zoxide' ]]
    run state_is_phase_completed languages
    assert_failure

    LANGUAGE_FAILURES=""
    run run_language_phase_fixture
    assert_success
    [[ "$(cat "$LANGUAGE_ATTEMPTS")" == $'bun\nrust\napt:go\nuv\nnvm\natuin\napt:zoxide\nbun\nrust\napt:go\nuv\nnvm' ]]
    run state_is_phase_completed languages
    assert_success
    run state_has_required_failures
    assert_failure
}

@test "language phase: optional Cargo package failures do not fail a healthy phase" {
    setup_language_phase_fixture
    mkdir -p "$TARGET_HOME/.cargo/bin"
    printf '#!/bin/sh\nexit 1\n' > "$TARGET_HOME/.cargo/bin/cargo"
    chmod +x "$TARGET_HOME/.cargo/bin/cargo"

    run run_language_phase_fixture
    assert_success
    jq -e '.phase_steps.languages["Batch installing cargo tools"].status == "failed"
        and .phase_steps.languages["Batch installing cargo tools"].required == false' "$ACFS_STATE_FILE"
    run state_has_required_failures
    assert_failure
}

@test "try_step_eval missing command string fails without unbound variable" {
    run env -i PATH="/usr/bin:/bin" /usr/bin/bash -c '
        set -euo pipefail
        source "$1"
        status=0
        try_step_eval "missing eval command" || status=$?
        printf "status=%s\n" "$status"
        printf "last_error=%s\n" "$LAST_ERROR"
        printf "last_error_code=%s\n" "$LAST_ERROR_CODE"
    ' _ "$PROJECT_ROOT/scripts/lib/error_tracking.sh"

    assert_success
    assert_output --partial "status=1"
    assert_output --partial "last_error=try_step_eval: missing command string for: missing eval command"
    assert_output --partial "last_error_code=1"
    refute_output --partial "unbound variable"
}

@test "try_step_eval uses trusted bash instead of PATH bash" {
    local fake_bin
    local marker

    fake_bin="$(create_temp_dir)/bin"
    marker="$(create_temp_dir)/poisoned-bash"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/bash" <<'EOF'
#!/bin/sh
printf poisoned > "$ACFS_POISON_MARKER"
exit 43
EOF
    chmod +x "$fake_bin/bash"

    run env -i ACFS_POISON_MARKER="$marker" PATH="$fake_bin:/usr/bin:/bin" /usr/bin/bash -c '
        set -euo pipefail
        source "$1"
        try_step_eval "trusted bash probe" "true" >/dev/null 2>&1
        [[ ! -e "$2" ]] || exit 44
        printf "trusted bash used\n"
    ' _ "$PROJECT_ROOT/scripts/lib/error_tracking.sh" "$marker"

    assert_success
    assert_output "trusted bash used"
}

@test "errors: unmatched suggestions survive errexit" {
    run env -i PATH="/usr/bin:/bin" /usr/bin/bash -c '
        set -euo pipefail
        source "$1"
        get_suggested_fix "totally unmatched failure"
        printf "after\n"
    ' _ "$PROJECT_ROOT/scripts/lib/errors.sh"

    assert_success
    assert_output --partial "Unknown error. Troubleshooting steps:"
    assert_output --partial "Check internet connectivity"
    assert_output --partial "after"
}

@test "errors: formatted unmatched errors survive errexit" {
    run env -i PATH="/usr/bin:/bin" /usr/bin/bash -c '
        set -euo pipefail
        source "$1"
        format_error_with_fix "totally unmatched failure" "stack"
        printf "after\n"
    ' _ "$PROJECT_ROOT/scripts/lib/errors.sh"

    assert_success
    assert_output --partial "ERROR during phase: stack"
    assert_output --partial "Unknown error. Troubleshooting steps:"
    assert_output --partial "after"
}

@test "report_failure renders generic unknown fix once" {
    local report_log
    report_log="$BATS_TEST_TMPDIR/report.log"

    run env -i PATH="/usr/bin:/bin" ACFS_LOG_FILE="$report_log" /usr/bin/bash -c '
        set -euo pipefail
        source "$1"
        source "$2"
        CURRENT_PHASE="stack"
        CURRENT_PHASE_NAME="Agent Flywheel Stack"
        CURRENT_STEP="unknown step"
        LAST_ERROR="Unknown error"
        report_failure 8 9
    ' _ "$PROJECT_ROOT/scripts/lib/errors.sh" "$PROJECT_ROOT/scripts/lib/report.sh"

    assert_success
    assert_output --partial "Phase 8/9: Agent Flywheel Stack"
    assert_output --partial "Failed at:"

    local count
    count="$(grep -c "Check internet connectivity" <<< "$output" || true)"
    assert_equal "$count" "1"

    run jq -r '.failure.suggested_fix' "$report_log"
    assert_success
    count="$(grep -c "Check internet connectivity" <<< "$output" || true)"
    assert_equal "$count" "1"
}

@test "report_failure uses canonical resume hint when available" {
    local report_log
    report_log="$BATS_TEST_TMPDIR/report.log"

    run env -i PATH="/usr/bin:/bin" ACFS_LOG_FILE="$report_log" /usr/bin/bash -c '
        set -euo pipefail
        source "$1"
        generate_resume_hint() {
            printf "canonical-resume phase=%s step=%s\n" "$1" "$2"
        }
        CURRENT_PHASE="stack"
        CURRENT_PHASE_NAME="Agent Flywheel Stack"
        CURRENT_STEP="MCP Agent Mail"
        LAST_ERROR="checksum mismatch: expected old actual new"
        report_failure 8 9
    ' _ "$PROJECT_ROOT/scripts/lib/report.sh"

    assert_success
    assert_output --partial "canonical-resume phase=stack step=MCP Agent Mail"
}

@test "report log sudo fallback is noninteractive" {
    local fake_sudo
    local sudo_log
    fake_sudo="$BATS_TEST_TMPDIR/fake-sudo"
    sudo_log="$BATS_TEST_TMPDIR/sudo.log"

    cat > "$fake_sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_REPORT_SUDO_LOG"
[[ "${1:-}" == "-n" ]] || exit 77
exit 1
EOF
    chmod +x "$fake_sudo"

    run env -i PATH="/usr/bin:/bin" \
        ACFS_LOG_FILE="/proc/acfs-report-test/install.log" \
        TEST_REPORT_FAKE_SUDO="$fake_sudo" \
        TEST_REPORT_SUDO_LOG="$sudo_log" \
        /usr/bin/bash -c '
            set -euo pipefail
            source "$1"
            _acfs_report_sudo_binary_path() {
                printf "%s\n" "$TEST_REPORT_FAKE_SUDO"
            }
            _acfs_append_log_entry "{\"type\":\"test\"}"
        ' _ "$PROJECT_ROOT/scripts/lib/report.sh"

    assert_success

    run cat "$sudo_log"
    assert_success
    assert_output --partial "-n mkdir -p /proc/acfs-report-test"
}

@test "report_failure fallback preserves pinned ref and install flags" {
    local report_log
    local pinned_ref
    report_log="$BATS_TEST_TMPDIR/report.log"
    pinned_ref="2463b6a6e4338d74502c7bb34cb02ab8ca8e2ad4"

    run env -i PATH="/usr/bin:/bin" \
        ACFS_LOG_FILE="$report_log" \
        ACFS_COMMIT_SHA_FULL="$pinned_ref" \
        ACFS_REF="$pinned_ref" \
        ACFS_REF_INPUT="main" \
        ACFS_RAW="https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/$pinned_ref" \
        ACFS_CHECKSUMS_REF_EXPLICIT=true \
        ACFS_CHECKSUMS_REF="release-checksums" \
        MODE="safe" \
        YES_MODE=true \
        ACFS_STRICT_MODE=true \
        SKIP_CLOUD=true \
        /usr/bin/bash -c '
            set -euo pipefail
            source "$1"
            ONLY_MODULES=("stack.ntm" "stack.mcp_agent_mail")
            ONLY_PHASES=("9")
            SKIP_MODULES=("stack.cass")
            NO_DEPS=true
            CURRENT_PHASE="stack"
            CURRENT_PHASE_NAME="Agent Flywheel Stack"
            CURRENT_STEP="MCP Agent Mail"
            LAST_ERROR="checksum mismatch: expected old actual new"
            report_failure 8 9
        ' _ "$PROJECT_ROOT/scripts/lib/report.sh"

    assert_success
    assert_output --partial "raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/$pinned_ref/install.sh"
    assert_output --partial "--resume"
    assert_output --partial "--mode safe"
    assert_output --partial "--yes"
    assert_output --partial "--strict"
    assert_output --partial "--skip-cloud"
    assert_output --partial "--ref $pinned_ref"
    assert_output --partial "--checksums-ref release-checksums"
    assert_output --partial "--only stack.ntm"
    assert_output --partial "--only stack.mcp_agent_mail"
    assert_output --partial "--only-phase 9"
    assert_output --partial "--skip stack.cass"
    assert_output --partial "--no-deps"
}

@test "report_failure fills missing context from state file" {
    local state_dir
    local state_file
    local report_log
    state_dir="$(create_temp_dir)"
    state_file="$state_dir/state.json"
    report_log="$state_dir/report.log"
    cat > "$state_file" <<'EOF_STATE'
{
  "failed_phase": "stack",
  "failed_step": "MCP Agent Mail",
  "failed_error": "checksum mismatch: expected old actual new"
}
EOF_STATE

    run env -i PATH="/usr/bin:/bin" ACFS_STATE_FILE="$state_file" ACFS_LOG_FILE="$report_log" /usr/bin/bash -c '
        set -euo pipefail
        source "$1"
        source "$2"
        source "$3"
        report_failure 8 9
    ' _ "$PROJECT_ROOT/scripts/lib/state.sh" "$PROJECT_ROOT/scripts/lib/errors.sh" "$PROJECT_ROOT/scripts/lib/report.sh"

    assert_success
    assert_output --partial "Phase 8/9: Agent Flywheel Stack"
    assert_output --partial "Failed at:"
    assert_output --partial "MCP Agent Mail"
    assert_output --partial "checksum mismatch: expected old actual new"
    refute_output --partial "unknown step"

    run jq -e '
        .phase.name == "Agent Flywheel Stack"
        and .failure.step == "MCP Agent Mail"
        and .failure.error == "checksum mismatch: expected old actual new"
        and (.failure.suggested_fix | contains("Upstream installer script has changed"))
    ' "$report_log"
    assert_success
}
