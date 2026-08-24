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
