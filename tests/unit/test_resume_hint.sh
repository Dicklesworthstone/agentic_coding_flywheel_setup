#!/usr/bin/env bash
# shellcheck disable=SC2317,SC2034
# ============================================================
# Unit tests for resume hint generation (bd-31ps.9.2)
#
# Tests that generate_resume_hint() produces correct commands
# with various flag combinations.
#
# Run with: bash tests/unit/test_resume_hint.sh
# ============================================================

set -uo pipefail

# Get the absolute path to the repo root
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

# Log file
LOG_FILE="/tmp/acfs_resume_hint_test_$(date +%Y%m%d_%H%M%S).log"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================
# Test Helpers
# ============================================================

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

test_pass() {
    ((TESTS_PASSED++))
    log "PASS: $1"
}

test_fail() {
    ((TESTS_FAILED++))
    log "FAIL: $1"
    [[ -n "${2:-}" ]] && log "  Reason: $2"
}

run_test() {
    local test_name="$1"
    ((TESTS_RUN++))
    log ""
    log "Running: $test_name..."
    if "$test_name"; then
        test_pass "$test_name"
    else
        test_fail "$test_name"
    fi
}

# ============================================================
# Mock functions and setup
# ============================================================

# Stub log functions so sourcing install.sh doesn't fail
log_info() { :; }
log_warn() { :; }
log_error() { :; }
log_detail() { :; }

# Source just the generate_resume_hint function from install.sh
# We extract it rather than sourcing the full install.sh to avoid side effects
extract_resume_hint_function() {
    # Extract the generate_resume_hint function from install.sh
    sed -n '/^generate_resume_hint()/,/^}$/p' "$REPO_ROOT/install.sh"
}

extract_print_resume_hint_function() {
    sed -n '/^print_resume_hint()/,/^}$/p' "$REPO_ROOT/install.sh"
}

# Actually, let's just define our test environment and source install.sh functions
setup_test_env() {
    # Reset all variables to defaults
    SCRIPT_DIR=""
    ACFS_COMMIT_SHA_FULL=""
    ACFS_REF_INPUT=""
    MODE="vibe"
    SKIP_POSTGRES=false
    SKIP_VAULT=false
    SKIP_CLOUD=false
    SKIP_PREFLIGHT=false
    SKIP_UBUNTU_UPGRADE=false
    YES_MODE=false
    STRICT_MODE=false
}

# Source the generate_resume_hint function
# shellcheck disable=SC1090
eval "$(extract_resume_hint_function)"
# shellcheck disable=SC1090
eval "$(extract_print_resume_hint_function)"

STATE_SET_RESUME_HINT_CALLS=0
STATE_SET_RESUME_HINT_VALUE=""

state_set_resume_hint() {
    ((STATE_SET_RESUME_HINT_CALLS++))
    STATE_SET_RESUME_HINT_VALUE="$1"
    return 0
}

# ============================================================
# Tests
# ============================================================

# Test: Basic curl|bash invocation with defaults
test_basic_curl_invocation() {
    setup_test_env

    local result
    result=$(generate_resume_hint "" "")

    # Should contain curl and --resume
    if [[ "$result" != *"curl"* ]]; then
        log "  Expected curl in output, got: $result"
        return 1
    fi

    if [[ "$result" != *"--resume"* ]]; then
        log "  Expected --resume in output, got: $result"
        return 1
    fi

    # Should NOT contain mode flag (default is vibe)
    if [[ "$result" == *"--mode"* ]]; then
        log "  Should not contain --mode (default vibe), got: $result"
        return 1
    fi

    return 0
}

# Test: Local script invocation
test_local_script_invocation() {
    setup_test_env
    SCRIPT_DIR="/some/local/path"

    local result
    result=$(generate_resume_hint "" "")

    # Should use bash install.sh, not curl
    if [[ "$result" != "bash install.sh --resume"* ]]; then
        log "  Expected 'bash install.sh --resume', got: $result"
        return 1
    fi

    return 0
}

# Test: Pinned to specific commit SHA
test_pinned_commit_sha() {
    setup_test_env
    ACFS_COMMIT_SHA_FULL="abc123def456abc123def456abc123def456abc1"

    local result
    result=$(generate_resume_hint "" "")

    # Should include the full commit SHA in URL
    if [[ "$result" != *"$ACFS_COMMIT_SHA_FULL"* ]]; then
        log "  Expected commit SHA in output, got: $result"
        return 1
    fi

    return 0
}

# Test: Custom ACFS_REF (branch/tag)
test_custom_ref() {
    setup_test_env
    ACFS_REF_INPUT="v1.2.3"

    local result
    result=$(generate_resume_hint "" "")

    # Should include the ref in URL
    if [[ "$result" != *"v1.2.3"* ]]; then
        log "  Expected ref v1.2.3 in output, got: $result"
        return 1
    fi

    return 0
}

# Test: Safe mode
test_safe_mode() {
    setup_test_env
    MODE="safe"

    local result
    result=$(generate_resume_hint "" "")

    if [[ "$result" != *"--mode safe"* ]]; then
        log "  Expected --mode safe in output, got: $result"
        return 1
    fi

    return 0
}

# Test: Skip flags
test_skip_flags() {
    setup_test_env
    SKIP_POSTGRES=true
    SKIP_VAULT=true

    local result
    result=$(generate_resume_hint "" "")

    if [[ "$result" != *"--skip-postgres"* ]]; then
        log "  Expected --skip-postgres in output, got: $result"
        return 1
    fi

    if [[ "$result" != *"--skip-vault"* ]]; then
        log "  Expected --skip-vault in output, got: $result"
        return 1
    fi

    return 0
}

# Test: All skip flags
test_all_skip_flags() {
    setup_test_env
    SKIP_POSTGRES=true
    SKIP_VAULT=true
    SKIP_CLOUD=true
    SKIP_PREFLIGHT=true
    SKIP_UBUNTU_UPGRADE=true

    local result
    result=$(generate_resume_hint "" "")

    for flag in --skip-postgres --skip-vault --skip-cloud --skip-preflight --skip-ubuntu-upgrade; do
        if [[ "$result" != *"$flag"* ]]; then
            log "  Expected $flag in output, got: $result"
            return 1
        fi
    done

    return 0
}

# Test: YES_MODE flag
test_yes_mode() {
    setup_test_env
    YES_MODE=true

    local result
    result=$(generate_resume_hint "" "")

    if [[ "$result" != *"--yes"* ]]; then
        log "  Expected --yes in output, got: $result"
        return 1
    fi

    return 0
}

# Test: STRICT_MODE flag
test_strict_mode() {
    setup_test_env
    STRICT_MODE=true

    local result
    result=$(generate_resume_hint "" "")

    if [[ "$result" != *"--strict"* ]]; then
        log "  Expected --strict in output, got: $result"
        return 1
    fi

    return 0
}

# Test: Complex combination
test_complex_combination() {
    setup_test_env
    MODE="safe"
    SKIP_POSTGRES=true
    SKIP_CLOUD=true
    YES_MODE=true
    ACFS_REF_INPUT="develop"

    local result
    result=$(generate_resume_hint "languages" "install_rust")

    # Check all expected flags
    if [[ "$result" != *"--resume"* ]]; then
        log "  Expected --resume, got: $result"
        return 1
    fi

    if [[ "$result" != *"--mode safe"* ]]; then
        log "  Expected --mode safe, got: $result"
        return 1
    fi

    if [[ "$result" != *"--skip-postgres"* ]]; then
        log "  Expected --skip-postgres, got: $result"
        return 1
    fi

    if [[ "$result" != *"--skip-cloud"* ]]; then
        log "  Expected --skip-cloud, got: $result"
        return 1
    fi

    if [[ "$result" != *"--yes"* ]]; then
        log "  Expected --yes, got: $result"
        return 1
    fi

    if [[ "$result" != *"develop"* ]]; then
        log "  Expected 'develop' ref, got: $result"
        return 1
    fi

    return 0
}

# Test: Main branch uses acfs.sh shorthand
test_main_branch_shorthand() {
    setup_test_env
    ACFS_REF_INPUT="main"

    local result
    result=$(generate_resume_hint "" "")

    # Should use acfs.sh shorthand for main branch
    if [[ "$result" != *"acfs.sh"* ]]; then
        log "  Expected acfs.sh shorthand for main branch, got: $result"
        return 1
    fi

    return 0
}

# Test: Empty ACFS_REF uses acfs.sh shorthand
test_empty_ref_shorthand() {
    setup_test_env
    ACFS_REF_INPUT=""

    local result
    result=$(generate_resume_hint "" "")

    # Should use acfs.sh shorthand
    if [[ "$result" != *"acfs.sh"* ]]; then
        log "  Expected acfs.sh shorthand, got: $result"
        return 1
    fi

    return 0
}

# Test: print_resume_hint uses the state helper instead of rewriting state directly
test_print_resume_hint_uses_state_helper() {
    setup_test_env
    YES_MODE=true
    ACFS_STATE_FILE="$(mktemp)"
    printf '{}\n' > "$ACFS_STATE_FILE"
    STATE_SET_RESUME_HINT_CALLS=0
    STATE_SET_RESUME_HINT_VALUE=""

    print_resume_hint "languages" "install_rust"

    if [[ "$STATE_SET_RESUME_HINT_CALLS" -ne 1 ]]; then
        log "  Expected state_set_resume_hint to be called once, got: $STATE_SET_RESUME_HINT_CALLS"
        rm -f "$ACFS_STATE_FILE"
        return 1
    fi

    if [[ "$STATE_SET_RESUME_HINT_VALUE" != *"--resume"* ]]; then
        log "  Expected generated resume hint to include --resume, got: $STATE_SET_RESUME_HINT_VALUE"
        rm -f "$ACFS_STATE_FILE"
        return 1
    fi

    if [[ "$STATE_SET_RESUME_HINT_VALUE" != *"--yes"* ]]; then
        log "  Expected generated resume hint to include --yes, got: $STATE_SET_RESUME_HINT_VALUE"
        rm -f "$ACFS_STATE_FILE"
        return 1
    fi

    rm -f "$ACFS_STATE_FILE"
    return 0
}

# ============================================================
# Main
# ============================================================

main() {
    log "============================================================"
    log "ACFS Resume Hint Unit Tests"
    log "============================================================"
    log "Log file: $LOG_FILE"
    log ""

    # Run all tests
    run_test test_basic_curl_invocation
    run_test test_local_script_invocation
    run_test test_pinned_commit_sha
    run_test test_custom_ref
    run_test test_safe_mode
    run_test test_skip_flags
    run_test test_all_skip_flags
    run_test test_yes_mode
    run_test test_strict_mode
    run_test test_complex_combination
    run_test test_main_branch_shorthand
    run_test test_empty_ref_shorthand
    run_test test_print_resume_hint_uses_state_helper

    # Summary
    log ""
    log "============================================================"
    log "Results: $TESTS_PASSED passed, $TESTS_FAILED failed (of $TESTS_RUN)"
    log "Log file: $LOG_FILE"
    log "============================================================"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi

    exit 0
}

main "$@"
