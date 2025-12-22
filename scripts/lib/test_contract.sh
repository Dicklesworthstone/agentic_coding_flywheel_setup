#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2317,SC2329
# ============================================================
# Test script for contract.sh
# Run: bash scripts/lib/test_contract.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source required files
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/contract.sh"

TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    local name="$1"
    echo -e "\033[32m[PASS]\033[0m $name"
    ((++TESTS_PASSED))
}

test_fail() {
    local name="$1"
    local reason="${2:-}"
    echo -e "\033[31m[FAIL]\033[0m $name"
    [[ -n "$reason" ]] && echo "       Reason: $reason"
    ((++TESTS_FAILED))
}

# Reset environment for each test
reset_env() {
    unset TARGET_USER TARGET_HOME MODE
    unset SCRIPT_DIR ACFS_BOOTSTRAP_DIR ACFS_LIB_DIR
    unset ACFS_GENERATED_DIR ACFS_ASSETS_DIR ACFS_CHECKSUMS_YAML ACFS_MANIFEST_YAML
}

# Define stub functions for contract requirements
define_required_functions() {
    log_detail() { :; }
    run_as_target() { :; }
    run_as_target_shell() { :; }
    run_as_root_shell() { :; }
    run_as_current_shell() { :; }
    export -f log_detail run_as_target run_as_target_shell run_as_root_shell run_as_current_shell
}

# Undefine functions
undefine_required_functions() {
    unset -f run_as_target run_as_target_shell run_as_root_shell run_as_current_shell
}

# ============================================================
# Test Cases
# ============================================================

test_missing_target_user() {
    local name="Missing TARGET_USER fails contract"
    reset_env
    define_required_functions

    TARGET_HOME="/home/test"
    MODE="normal"
    SCRIPT_DIR="/some/path"

    if ! acfs_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail when TARGET_USER is missing"
    fi
}

test_missing_target_home() {
    local name="Missing TARGET_HOME fails contract"
    reset_env
    define_required_functions

    TARGET_USER="testuser"
    MODE="normal"
    SCRIPT_DIR="/some/path"

    if ! acfs_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail when TARGET_HOME is missing"
    fi
}

test_missing_mode() {
    local name="Missing MODE fails contract"
    reset_env
    define_required_functions

    TARGET_USER="testuser"
    TARGET_HOME="/home/test"
    SCRIPT_DIR="/some/path"

    if ! acfs_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail when MODE is missing"
    fi
}

test_all_basic_vars_present() {
    local name="All basic vars present passes contract"
    reset_env
    define_required_functions

    TARGET_USER="testuser"
    TARGET_HOME="/home/test"
    MODE="normal"
    SCRIPT_DIR="/some/path"

    if acfs_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should pass with all required vars"
    fi
}

test_bootstrap_mode_missing_vars() {
    local name="Bootstrap mode (empty SCRIPT_DIR) requires ACFS_BOOTSTRAP_DIR"
    reset_env
    define_required_functions

    TARGET_USER="testuser"
    TARGET_HOME="/home/test"
    MODE="normal"
    SCRIPT_DIR=""  # Empty triggers bootstrap check

    if ! acfs_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail when ACFS_BOOTSTRAP_DIR is missing in bootstrap mode"
    fi
}

test_bootstrap_mode_all_vars() {
    local name="Bootstrap mode with all vars passes"
    reset_env
    define_required_functions

    TARGET_USER="testuser"
    TARGET_HOME="/home/test"
    MODE="normal"
    SCRIPT_DIR=""  # Bootstrap mode
    ACFS_BOOTSTRAP_DIR="/tmp/acfs"
    ACFS_LIB_DIR="/tmp/acfs/lib"
    ACFS_GENERATED_DIR="/tmp/acfs/generated"
    ACFS_ASSETS_DIR="/tmp/acfs/assets"
    ACFS_CHECKSUMS_YAML="/tmp/acfs/checksums.yaml"
    ACFS_MANIFEST_YAML="/tmp/acfs/acfs.manifest.yaml"

    if acfs_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should pass with all bootstrap vars"
    fi
}

test_missing_run_as_target_function() {
    local name="Missing run_as_target function fails contract"
    reset_env
    define_required_functions
    unset -f run_as_target

    TARGET_USER="testuser"
    TARGET_HOME="/home/test"
    MODE="normal"
    SCRIPT_DIR="/some/path"

    if ! acfs_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail when run_as_target is missing"
    fi
}

test_missing_run_as_target_shell_function() {
    local name="Missing run_as_target_shell function fails contract"
    reset_env
    define_required_functions
    unset -f run_as_target_shell

    TARGET_USER="testuser"
    TARGET_HOME="/home/test"
    MODE="normal"
    SCRIPT_DIR="/some/path"

    if ! acfs_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail when run_as_target_shell is missing"
    fi
}

test_missing_run_as_root_shell_function() {
    local name="Missing run_as_root_shell function fails contract"
    reset_env
    define_required_functions
    unset -f run_as_root_shell

    TARGET_USER="testuser"
    TARGET_HOME="/home/test"
    MODE="normal"
    SCRIPT_DIR="/some/path"

    if ! acfs_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail when run_as_root_shell is missing"
    fi
}

test_missing_run_as_current_shell_function() {
    local name="Missing run_as_current_shell function fails contract"
    reset_env
    define_required_functions
    unset -f run_as_current_shell

    TARGET_USER="testuser"
    TARGET_HOME="/home/test"
    MODE="normal"
    SCRIPT_DIR="/some/path"

    if ! acfs_require_contract "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail when run_as_current_shell is missing"
    fi
}

# ============================================================
# Run Tests
# ============================================================

echo ""
echo "ACFS Contract Tests"
echo "==================="
echo ""

test_missing_target_user
test_missing_target_home
test_missing_mode
test_all_basic_vars_present
test_bootstrap_mode_missing_vars
test_bootstrap_mode_all_vars
test_missing_run_as_target_function
test_missing_run_as_target_shell_function
test_missing_run_as_root_shell_function
test_missing_run_as_current_shell_function

echo ""
echo "==================="
echo "Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"
echo ""

[[ $TESTS_FAILED -eq 0 ]]
