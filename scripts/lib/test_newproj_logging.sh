#!/usr/bin/env bash
# shellcheck disable=SC2317  # test helpers are invoked by this script
# ============================================================
# Unit Tests for newproj_logging.sh
# Run with: bash scripts/lib/test_newproj_logging.sh
# ============================================================

set -uo pipefail
# Note: Not using set -e because we want to continue running tests even if some fail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=newproj_logging.sh
source "$SCRIPT_DIR/newproj_logging.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Temporary directory for test logs
TEST_TMP_DIR=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Setup test environment
setup() {
    TEST_TMP_DIR=$(mktemp -d)
    export ACFS_LOG_DIR="$TEST_TMP_DIR"
    export ACFS_LOG_LEVEL=$ACFS_LOG_DEBUG
}

# Cleanup test environment
cleanup() {
    if [[ -n "$TEST_TMP_DIR" && -d "$TEST_TMP_DIR" ]]; then
        rm -rf "$TEST_TMP_DIR"
    fi
}

# Run a test
run_test() {
    local test_name="$1"
    local test_func="$2"

    ((TESTS_RUN++))

    if $test_func; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}PASS${NC}: $test_name"
    else
        ((TESTS_FAILED++))
        echo -e "${RED}FAIL${NC}: $test_name"
    fi
}

# ============================================================
# Test Cases
# ============================================================

test_init_logging() {
    init_logging
    [[ -f "$ACFS_SESSION_LOG" ]] || return 1
    grep -q "ACFS newproj TUI Wizard Session Log" "$ACFS_SESSION_LOG" || return 1
    return 0
}

test_log_levels() {
    init_logging

    log_debug "Debug message"
    log_info "Info message"
    log_warn "Warning message"
    log_error "Error message"

    grep -q "DEBUG" "$ACFS_SESSION_LOG" || return 1
    grep -q "INFO" "$ACFS_SESSION_LOG" || return 1
    grep -q "WARN" "$ACFS_SESSION_LOG" || return 1
    grep -q "ERROR" "$ACFS_SESSION_LOG" || return 1
    return 0
}

test_log_state() {
    init_logging

    log_state "project_name" "" "my-project"

    grep -q "STATE" "$ACFS_SESSION_LOG" || return 1
    grep -q "project_name" "$ACFS_SESSION_LOG" || return 1
    grep -q "my-project" "$ACFS_SESSION_LOG" || return 1
    return 0
}

test_log_screen() {
    init_logging

    log_screen "ENTER" "welcome"
    log_screen "RENDER" "welcome"
    log_screen "EXIT" "welcome"

    grep -c "SCRN" "$ACFS_SESSION_LOG" | grep -q "3" || return 1
    return 0
}

test_log_input_sanitization() {
    init_logging

    # Test truncation
    local long_input=$(printf 'x%.0s' {1..200})
    log_input "test_field" "$long_input"

    grep -q "truncated" "$ACFS_SESSION_LOG" || return 1

    # Test that sensitive patterns are masked
    log_input "api" "sk-1234567890abcdef"
    grep -q "sk-\*\*\*" "$ACFS_SESSION_LOG" || return 1

    return 0
}

test_log_validation() {
    init_logging

    log_validation "project_name" "my-project" "PASS"
    log_validation "project_name" "bad name!" "FAIL" "Contains invalid characters"

    grep -q "VALID" "$ACFS_SESSION_LOG" || return 1
    grep -q "PASS" "$ACFS_SESSION_LOG" || return 1
    grep -q "FAIL" "$ACFS_SESSION_LOG" || return 1
    return 0
}

test_log_file_op() {
    init_logging

    log_file_op "CREATE" "/tmp/test/project"
    log_file_op "MKDIR" "/tmp/test" "OK"
    log_file_op "WRITE" "/tmp/test/.gitignore" "OK"

    grep -c "FILE" "$ACFS_SESSION_LOG" | grep -q "3" || return 1
    return 0
}

test_log_cmd() {
    init_logging

    log_cmd "git init" 0
    log_cmd "invalid_command" 1

    grep -q "CMD" "$ACFS_SESSION_LOG" || return 1
    grep -q "FAIL" "$ACFS_SESSION_LOG" || return 1
    return 0
}

test_log_tech_detect() {
    init_logging

    log_tech_detect "nodejs" "package.json" "high"
    log_tech_detect "typescript" "tsconfig.json" "high"

    grep -c "TECH" "$ACFS_SESSION_LOG" | grep -q "2" || return 1
    return 0
}

test_log_nav() {
    init_logging

    log_nav "NEXT" "welcome" "project_name"
    log_nav "BACK" "project_name" "welcome"
    log_nav "CANCEL"

    grep -c "NAV" "$ACFS_SESSION_LOG" | grep -q "3" || return 1
    return 0
}

test_log_json() {
    init_logging

    log_json "wizard_state" '{"project_name": "test", "enabled": true}'

    grep -q "JSON" "$ACFS_SESSION_LOG" || return 1
    grep -q "project_name" "$ACFS_SESSION_LOG" || return 1
    return 0
}

test_finalize_logging() {
    init_logging
    finalize_logging 0

    grep -q "Session completed" "$ACFS_SESSION_LOG" || return 1
    grep -q "Exit code: 0" "$ACFS_SESSION_LOG" || return 1
    return 0
}

test_log_checkpoint() {
    init_logging

    log_checkpoint "start_wizard"
    sleep 1
    log_checkpoint "end_wizard"

    grep -c "TIME" "$ACFS_SESSION_LOG" | grep -q "2" || return 1
    grep -q "Checkpoint: start_wizard" "$ACFS_SESSION_LOG" || return 1
    return 0
}

test_verbose_mode() {
    export ACFS_LOG_LEVEL=$ACFS_LOG_INFO
    init_logging

    # Info should not show DEBUG messages
    log_debug "This should not appear"

    if grep -q "This should not appear" "$ACFS_SESSION_LOG"; then
        return 1
    fi

    # Enable verbose mode
    enable_verbose
    log_debug "This should appear"

    grep -q "This should appear" "$ACFS_SESSION_LOG" || return 1
    return 0
}

test_show_log_location() {
    init_logging

    local output
    output=$(show_log_location)

    [[ "$output" == *"$TEST_TMP_DIR"* ]] || return 1
    return 0
}

test_get_log_path() {
    init_logging

    local path
    path=$(get_log_path)

    [[ -n "$path" ]] || return 1
    [[ -f "$path" ]] || return 1
    return 0
}

test_log_env_snapshot() {
    init_logging

    log_env_snapshot

    grep -q "ENV" "$ACFS_SESSION_LOG" || return 1
    grep -q "PATH=" "$ACFS_SESSION_LOG" || return 1
    grep -q "TERM=" "$ACFS_SESSION_LOG" || return 1
    return 0
}

test_log_level_filtering() {
    export ACFS_LOG_LEVEL=$ACFS_LOG_WARN
    init_logging

    log_debug "Debug should not appear"
    log_info "Info should not appear"
    log_warn "Warn should appear"
    log_error "Error should appear"

    if grep -q "Debug should not appear" "$ACFS_SESSION_LOG"; then
        return 1
    fi
    if grep -q "Info should not appear" "$ACFS_SESSION_LOG"; then
        return 1
    fi
    grep -q "Warn should appear" "$ACFS_SESSION_LOG" || return 1
    grep -q "Error should appear" "$ACFS_SESSION_LOG" || return 1
    return 0
}

test_multiple_sessions() {
    init_logging
    local first_log="$ACFS_SESSION_LOG"

    sleep 1  # Ensure different timestamp

    init_logging
    local second_log="$ACFS_SESSION_LOG"

    [[ "$first_log" != "$second_log" ]] || return 1
    [[ -f "$first_log" ]] || return 1
    [[ -f "$second_log" ]] || return 1
    return 0
}

test_log_dump_state() {
    init_logging

    declare -A TEST_STATE=(
        [project_name]="my-project"
        [tech_stack]="nodejs typescript"
        [enable_br]="true"
    )

    log_dump_state TEST_STATE

    grep -q "DUMP" "$ACFS_SESSION_LOG" || return 1
    grep -q "project_name" "$ACFS_SESSION_LOG" || return 1
    grep -q "my-project" "$ACFS_SESSION_LOG" || return 1
    return 0
}

# ============================================================
# Main Test Runner
# ============================================================

main() {
    echo "=========================================="
    echo "newproj_logging.sh Unit Tests"
    echo "=========================================="
    echo ""

    # Setup before all tests
    trap cleanup EXIT

    # Run tests (each gets a fresh environment)
    setup
    run_test "init_logging creates log file" test_init_logging

    setup
    run_test "log levels (DEBUG/INFO/WARN/ERROR)" test_log_levels

    setup
    run_test "log_state tracks state changes" test_log_state

    setup
    run_test "log_screen tracks screen transitions" test_log_screen

    setup
    run_test "log_input sanitizes sensitive data" test_log_input_sanitization

    setup
    run_test "log_validation tracks validation results" test_log_validation

    setup
    run_test "log_file_op tracks file operations" test_log_file_op

    setup
    run_test "log_cmd tracks command execution" test_log_cmd

    setup
    run_test "log_tech_detect tracks tech detection" test_log_tech_detect

    setup
    run_test "log_nav tracks navigation" test_log_nav

    setup
    run_test "log_json logs structured data" test_log_json

    setup
    run_test "finalize_logging writes session footer" test_finalize_logging

    setup
    run_test "log_checkpoint tracks timing" test_log_checkpoint

    setup
    run_test "verbose mode controls DEBUG level" test_verbose_mode

    setup
    run_test "show_log_location returns path" test_show_log_location

    setup
    run_test "get_log_path returns current log" test_get_log_path

    setup
    run_test "log_env_snapshot captures environment" test_log_env_snapshot

    setup
    run_test "log level filtering works" test_log_level_filtering

    setup
    run_test "multiple sessions create separate logs" test_multiple_sessions

    setup
    run_test "log_dump_state dumps associative array" test_log_dump_state

    # Summary
    echo ""
    echo "=========================================="
    echo "Results: $TESTS_PASSED/$TESTS_RUN passed"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}$TESTS_FAILED test(s) failed${NC}"
        exit 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

main "$@"
