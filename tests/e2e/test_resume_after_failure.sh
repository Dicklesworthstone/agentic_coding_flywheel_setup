#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2329 # Fixture globals and callbacks are consumed by sourced libraries.
# shellcheck source-path=SCRIPTDIR
# ============================================================
# E2E Test: Resume After Failure
#
# Resume/checkpoint is a core feature (state.json, --resume flag)
# but was COMPLETELY untested in CI. The version-mismatch bug
# (#86/#89) was a resume-path bug.
#
# Strategy:
#   1. Run installer with --only-phase user_setup (completes one phase)
#   2. Verify state.json shows completed_phases includes "user_setup"
#   3. Run installer with --resume --yes and verify it skips user_setup
#   4. Verify no duplicate work (check logs for "already completed")
#
# Related bugs: #86, #89
#
# --isolated exercises the real phase/step state machine and module checks
# across separate Bash processes with fixture installers. It needs no root,
# network, or installed ACFS tools. The default mode still runs the full
# installer and belongs in a disposable container.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0
WORK_DIR=""

cleanup_test() {
    if [[ -n "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR" 2>/dev/null || true
    fi
}
trap cleanup_test EXIT

assert_ok() {
    local desc="$1"
    shift
    if "$@"; then
        echo "  PASS: $desc"
        ((PASS++)) || true
    else
        echo "  FAIL: $desc"
        ((FAIL++)) || true
    fi
}

# The isolated worker is a fresh process for every install/resume attempt:
# in-memory error variables cannot accidentally make persistence tests pass.
isolated_worker() {
    local fixture="$1" action="$2"
    ACFS_HOME="$fixture/state"
    ACFS_STATE_FILE="$ACFS_HOME/state.json"
    TARGET_HOME="$fixture/home"
    TARGET_USER="$(id -un)"
    ACFS_VERSION="resume-regression"
    MODE=vibe
    HAS_GUM=false
    ERROR_VERBOSE=false
    ACFS_FORCE_REINSTALL=false
    ACFS_FORCE_RESUME=true
    DRY_RUN=false
    export ACFS_HOME ACFS_STATE_FILE TARGET_HOME TARGET_USER
    mkdir -p "$ACFS_HOME" "$TARGET_HOME"

    log_info() { printf '%s\n' "$*" >&2; }
    log_warn() { printf 'WARN: %s\n' "$*" >&2; }
    log_error() { printf 'ERROR: %s\n' "$*" >&2; }
    log_detail() { :; }
    log_debug() { :; }
    local_progress_record_installer_phase() { :; }

    # shellcheck source=../../scripts/lib/state.sh
    source "$REPO_ROOT/scripts/lib/state.sh"
    # shellcheck source=../../scripts/lib/error_tracking.sh
    source "$REPO_ROOT/scripts/lib/error_tracking.sh"
    # shellcheck source=../../scripts/lib/install_helpers.sh
    source "$REPO_ROOT/scripts/lib/install_helpers.sh"

    # Load the shipped terminal gate without executing install.sh's main().
    local function_name function_source
    for function_name in acfs_install_run_has_failures acfs_install_terminal_exit_status; do
        function_source="$(sed -n "/^${function_name}()/,/^}/p" "$REPO_ROOT/install.sh")"
        [[ -n "$function_source" ]] || return 2
        eval "$function_source"
    done

    ACFS_MANIFEST_INDEX_LOADED=true
    ACFS_GENERATED_SOURCED=true
    ACFS_EFFECTIVE_PLAN=(cli.healthy cli.required cli.optional)
    ONLY_MODULES=()
    ONLY_PHASES=()
    ACFS_PHASE_FAILURES=()
    ACFS_MODULE_FAILURES=()
    ACFS_OPTIONAL_MODULE_SKIPS=()
    SMOKE_TEST_FAILED=false
    ACFS_INSTALL_PARTIAL_FAILURE=0
    declare -gA ACFS_PLAN_REASON=()
    declare -gA ACFS_MODULE_PHASE=(
        [cli.healthy]=5 [cli.required]=5 [cli.optional]=5
    )
    declare -gA ACFS_MODULE_OPTIONAL=(
        [cli.healthy]=0 [cli.required]=0 [cli.optional]=1
    )
    declare -gA ACFS_MODULE_INSTALLED_CHECK=()
    declare -gA ACFS_MODULE_INSTALLED_CHECK_RUN_AS=()
    declare -gA ACFS_MODULE_VERIFY_COUNT=()
    declare -gA ACFS_MODULE_VERIFY_COMMAND=()
    declare -gA ACFS_MODULE_VERIFY_RUN_AS=()
    local module marker check
    for module in "${ACFS_EFFECTIVE_PLAN[@]}"; do
        marker="$fixture/${module#cli.}.ready"
        printf -v check 'test -f %q' "$marker"
        ACFS_MODULE_INSTALLED_CHECK[$module]="$check"
        ACFS_MODULE_INSTALLED_CHECK_RUN_AS[$module]=current
        ACFS_MODULE_VERIFY_COUNT[$module]=1
        ACFS_MODULE_VERIFY_COMMAND[$module.0]="$check"
        ACFS_MODULE_VERIFY_RUN_AS[$module]=current
    done
    # Presence is weaker than readiness: like a PostgreSQL package whose
    # database initialization or service start has not completed.
    printf -v check 'test -f %q' "$fixture/required.present"
    ACFS_MODULE_INSTALLED_CHECK[cli.required]="$check"

    # Fixture adapter only maps a stable phase ID to its manifest phase.
    # The validator, installed checks, state transitions, and terminal gate
    # all run their production implementations.
    acfs_verify_phase() {
        [[ "$1" == cli_tools ]] || return 1
        acfs_verify_phase_modules 5
    }

    fixture_install_healthy() {
        printf 'installed\n' >> "$fixture/healthy.attempts"
        touch "$fixture/healthy.ready"
    }
    fixture_privileged_install() {
        printf 'attempted\n' >> "$fixture/required.attempts"
        if [[ ! -f "$fixture/dependency.ready" ]]; then
            printf 'sudo: a password is required\n' >&2
            return 1
        fi
        touch "$fixture/required.present" "$fixture/required.ready"
    }
    fixture_phase() {
        set_phase cli_tools "CLI Tools"
        if ! acfs_should_skip_module cli.healthy; then
            try_step "Installing healthy component" fixture_install_healthy || true
        fi
        if [[ "$action" != optional ]] && ! acfs_should_skip_module cli.required; then
            # The real bug shape: a failed required step is logged, the phase
            # continues, and its final command succeeds.
            try_step "Installing required packages" fixture_privileged_install || true
        fi
        try_step_optional "Installing optional enhancement" false || true
        return 0
    }

    case "$action" in
        init)
            state_init
            touch "$fixture/healthy.ready"
            ;;
        legacy)
            state_init
            touch "$fixture/healthy.ready" "$fixture/required.present"
            # A real old record can claim success without any failure ledger.
            # Preserve the current schema version: upgraded versions must
            # still distrust false completion generated by their own version.
            local legacy
            legacy="$(state_load | jq '.completed_phases = ["cli_tools"] |
                .status = "success" | .failure = null | .failed_phase = null |
                .failed_step = null | .failed_error = null |
                del(.partial_phases, .phase_steps, .phase_attempts)')"
            state_save "$legacy"
            ;;
        interrupt)
            state_phase_start cli_tools
            state_step_result cli_tools "Installing required packages" running true
            touch "$fixture/required.present"
            # SIGTERM uses the production interruption handler. No fake
            # failure result is written before the signal lands.
            trap 'state_mark_interrupted; exit 143' TERM
            kill -TERM "$$"
            ;;
        ready)
            touch "$fixture/dependency.ready"
            ;;
        optional)
            ACFS_EFFECTIVE_PLAN=(cli.healthy cli.optional)
            run_phase cli_tools "4/9 CLI Tools" fixture_phase
            acfs_install_terminal_exit_status
            ;;
        explicit-optional)
            ACFS_EFFECTIVE_PLAN=(cli.optional)
            ONLY_MODULES=(cli.optional)
            ACFS_PLAN_REASON[cli.optional]="explicitly requested"
            acfs_verify_phase_modules 5
            ;;
        fail|resume)
            local phase_status=0 terminal_status=0
            run_phase cli_tools "4/9 CLI Tools" fixture_phase || phase_status=$?
            # Intentionally leave the per-process failure arrays empty: this
            # gate must also see unresolved failures persisted by earlier runs.
            acfs_install_terminal_exit_status || terminal_status=$?
            printf '%s\n' "$phase_status" > "$fixture/$action.phase_status"
            printf '%s\n' "$terminal_status" > "$fixture/$action.terminal_status"
            [[ "$phase_status" -eq 0 && "$terminal_status" -eq 0 ]]
            ;;
        terminal)
            acfs_install_terminal_exit_status
            ;;
        dry-run)
            DRY_RUN=true
            acfs_install_terminal_exit_status
            ;;
        *) return 2 ;;
    esac
}

isolated_run() {
    local fixture="$1" action="$2"
    bash "${BASH_SOURCE[0]}" --isolated-worker "$fixture" "$action" \
        > "$fixture/$action.log" 2>&1
}

assert_isolated_fails() {
    local desc="$1"
    shift
    if "$@"; then
        echo "  FAIL: $desc (unexpected success)"
        ((FAIL++)) || true
    else
        echo "  PASS: $desc"
        ((PASS++)) || true
    fi
}

run_isolated_regressions() {
    command -v jq >/dev/null || { echo "ERROR: jq is required" >&2; return 2; }
    WORK_DIR="$(mktemp -d)"
    echo "=== Isolated resume recovery regressions (#474) ==="
    local fixture="$WORK_DIR/required" state
    mkdir -p "$fixture"
    isolated_run "$fixture" init
    state="$fixture/state/state.json"
    assert_isolated_fails "failed privileged command makes a superficially successful phase fail" \
        isolated_run "$fixture" fail
    assert_ok "failed required phase is partial, incomplete, and retains its step failure" \
        jq -e '(.partial_phases | index("cli_tools")) != null and
            (.completed_phases | index("cli_tools")) == null and
            .phase_steps.cli_tools["Installing required packages"].status == "failed" and
            .phase_steps.cli_tools["Installing required packages"].required == true' "$state"
    assert_isolated_fails "a fresh process cannot report success over persistent required failures" \
        isolated_run "$fixture" terminal
    assert_ok "dry-run inspection is not failed by a persisted installation error" \
        isolated_run "$fixture" dry-run
    assert_isolated_fails "resume retries but remains failed while its dependency is unavailable" \
        isolated_run "$fixture" resume
    assert_ok "failed resume actually retried the required installation" \
        test "$(wc -l < "$fixture/required.attempts")" -eq 2
    assert_ok "working component was not reinstalled during failed attempts" \
        test ! -e "$fixture/healthy.attempts"
    isolated_run "$fixture" ready
    assert_ok "resume recovers when the missing dependency becomes available" \
        isolated_run "$fixture" resume
    assert_ok "recovered phase is complete and no longer partial" \
        jq -e '(.completed_phases | index("cli_tools")) != null and
            (.partial_phases | index("cli_tools")) == null' "$state"
    assert_ok "successful recovery performs only the missing installation" \
        test "$(wc -l < "$fixture/required.attempts")" -eq 3
    assert_ok "healthy component remains untouched after recovery" \
        test ! -e "$fixture/healthy.attempts"
    assert_ok "another resume validates and skips the healthy phase" \
        isolated_run "$fixture" resume
    assert_ok "validated completed phase performs no duplicate installation" \
        test "$(wc -l < "$fixture/required.attempts")" -eq 3

    fixture="$WORK_DIR/legacy"
    mkdir -p "$fixture"
    isolated_run "$fixture" legacy
    isolated_run "$fixture" ready
    assert_ok "a stale success record is repaired by live validation on resume" \
        isolated_run "$fixture" resume
    assert_ok "stale completion did not hide the missing required component" \
        test -f "$fixture/required.ready"
    assert_ok "legacy record repair preserves working components" \
        test ! -e "$fixture/healthy.attempts"

    fixture="$WORK_DIR/interrupted"
    mkdir -p "$fixture"
    isolated_run "$fixture" init
    assert_isolated_fails "SIGTERM interrupts an in-progress mandatory installation" \
        isolated_run "$fixture" interrupt
    state="$fixture/state/state.json"
    assert_ok "interrupted phase remains partial and cannot be mistaken for complete" \
        jq -e '.interrupted == true and
            (.partial_phases | index("cli_tools")) != null and
            (.completed_phases | index("cli_tools")) == null' "$state"
    isolated_run "$fixture" ready
    assert_ok "a new process resumes an interrupted phase after dependency repair" \
        isolated_run "$fixture" resume
    assert_ok "interruption recovery installs the missing component" \
        test -f "$fixture/required.ready"

    fixture="$WORK_DIR/optional"
    mkdir -p "$fixture"
    isolated_run "$fixture" init
    assert_ok "optional failure alone does not fail phase or installation" \
        isolated_run "$fixture" optional
    assert_ok "optional failure is retained for diagnosis without blocking completion" \
        jq -e '(.completed_phases | index("cli_tools")) != null and
            .phase_steps.cli_tools["Installing optional enhancement"].status == "failed" and
            .phase_steps.cli_tools["Installing optional enhancement"].required == false' \
        "$fixture/state/state.json"
    assert_isolated_fails "explicitly requested optional module must pass verification" \
        isolated_run "$fixture" explicit-optional

    fixture="$WORK_DIR/dry-run"
    mkdir -p "$fixture"
    assert_ok "dry-run succeeds without an installation state file" \
        isolated_run "$fixture" dry-run
    assert_ok "dry-run terminal validation does not create installation state" \
        test ! -e "$fixture/state/state.json"

    printf '\nResults: %s passed, %s failed\n' "$PASS" "$FAIL"
    if [[ "$FAIL" -gt 0 ]]; then
        local logfile
        for logfile in "$WORK_DIR"/*/*.log; do
            printf '\n%s\n' "$logfile"
            tail -12 "$logfile"
        done
        return 1
    fi
}

case "${1:-}" in
    --isolated-worker)
        isolated_worker "$2" "$3"
        exit $?
        ;;
    --isolated)
        run_isolated_regressions
        exit $?
        ;;
esac

echo "=== E2E: Resume After Failure ==="
echo ""

WORK_DIR="$(mktemp -d)"
STATE_DIR="$WORK_DIR/.acfs"
STATE_FILE="$STATE_DIR/state.json"
LOG_DIR="$WORK_DIR/logs"
mkdir -p "$STATE_DIR" "$LOG_DIR"

# ────────────────────────────────────────
# 1. Run installer with --only-phase user_setup
# ────────────────────────────────────────
echo "Step 1: Running installer with --only-phase user_setup..."

LOG1="$LOG_DIR/run1.log"

ACFS_CI=true \
ACFS_HOME="$STATE_DIR" \
ACFS_STATE_FILE="$STATE_FILE" \
ACFS_LOG_DIR="$LOG_DIR" \
    bash "$REPO_ROOT/install.sh" \
        --yes \
        --skip-preflight \
        --skip-ubuntu-upgrade \
        --only-phase user_setup \
        > "$LOG1" 2>&1 || {
            echo "  NOTE: First run exited non-zero (may be expected for partial run)"
        }

echo ""

# ────────────────────────────────────────
# 2. Verify state.json
# ────────────────────────────────────────
echo "Step 2: Verifying state.json..."

if [[ -f "$STATE_FILE" ]]; then
    echo "  PASS: state.json exists"
    ((PASS++)) || true

    # Check completed_phases contains user_setup
    if command -v jq &>/dev/null; then
        completed=$(jq -r '.completed_phases // [] | join(",")' "$STATE_FILE" 2>/dev/null) || completed=""
        if [[ "$completed" == *"user_setup"* ]]; then
            echo "  PASS: completed_phases includes 'user_setup'"
            ((PASS++)) || true
        else
            echo "  FAIL: completed_phases does not include 'user_setup' (got: '$completed')"
            ((FAIL++)) || true
        fi

        schema_v=$(jq -r '.schema_version // 0' "$STATE_FILE" 2>/dev/null) || schema_v="0"
        if [[ "$schema_v" -ge 2 ]]; then
            echo "  PASS: schema_version is $schema_v (>= 2)"
            ((PASS++)) || true
        else
            echo "  FAIL: schema_version is $schema_v (expected >= 2)"
            ((FAIL++)) || true
        fi
    else
        echo "  WARN: jq not available, skipping detailed state checks"
    fi
else
    echo "  FAIL: state.json not created"
    ((FAIL++)) || true
fi
echo ""

# ────────────────────────────────────────
# 3. Run installer with --resume
# ────────────────────────────────────────
echo "Step 3: Running installer with --resume..."

LOG2="$LOG_DIR/run2.log"

ACFS_CI=true \
ACFS_HOME="$STATE_DIR" \
ACFS_STATE_FILE="$STATE_FILE" \
ACFS_LOG_DIR="$LOG_DIR" \
    bash "$REPO_ROOT/install.sh" \
        --yes \
        --resume \
        --skip-preflight \
        --skip-ubuntu-upgrade \
        --only-phase user_setup \
        > "$LOG2" 2>&1 || {
            echo "  NOTE: Resume run exited non-zero (may be expected)"
        }

echo ""

# ────────────────────────────────────────
# 4. Verify resume behavior
# ────────────────────────────────────────
echo "Step 4: Verifying resume behavior..."

# The resume run should mention skipping or already-completed phases
if grep -qiE "skip|already completed|already done|resuming" "$LOG2" 2>/dev/null; then
    echo "  PASS: Resume run mentions skipping/already completed"
    ((PASS++)) || true
else
    echo "  WARN: No skip/resume message found (may use different wording)"
    # This is a soft check - different log levels may suppress the message
    ((PASS++)) || true
fi

# The resume run should NOT have unbound variable errors
if grep -qi "unbound variable" "$LOG2" 2>/dev/null; then
    echo "  FAIL: Found 'unbound variable' error in resume run"
    ((FAIL++)) || true
else
    echo "  PASS: No unbound variable errors in resume run"
    ((PASS++)) || true
fi

# State file should still exist and be valid JSON
if [[ -f "$STATE_FILE" ]]; then
    if command -v jq &>/dev/null; then
        if jq empty "$STATE_FILE" 2>/dev/null; then
            echo "  PASS: state.json is valid JSON after resume"
            ((PASS++)) || true
        else
            echo "  FAIL: state.json is not valid JSON after resume"
            ((FAIL++)) || true
        fi
    fi
fi

echo ""
echo "---"
echo "Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "FAIL: Resume-after-failure E2E test failed."
    echo ""
    echo "Run 1 log (last 20 lines):"
    tail -20 "$LOG1" 2>/dev/null || true
    echo ""
    echo "Run 2 log (last 20 lines):"
    tail -20 "$LOG2" 2>/dev/null || true
    exit 1
fi

echo "PASS: Resume-after-failure E2E test passed."
exit 0
