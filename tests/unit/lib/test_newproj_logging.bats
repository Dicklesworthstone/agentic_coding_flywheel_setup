#!/usr/bin/env bats
# ============================================================
# Unit Tests for newproj_logging.sh
# Tests the logging infrastructure for the newproj TUI wizard
# ============================================================

load '../test_helper'

setup() {
    common_setup

    # Create temp directory for log files
    TEST_LOG_DIR=$(create_temp_dir)
    export ACFS_LOG_DIR="$TEST_LOG_DIR"
    # Set DEBUG level (0) before sourcing so it doesn't default to INFO
    export ACFS_LOG_LEVEL=0

    # Source the logging module
    source_lib "newproj_logging"
}

teardown() {
    common_teardown
}

# ============================================================
# Initialization Tests
# ============================================================

@test "init_logging creates log file" {
    init_logging

    # Verify log file was created
    [[ -f "$ACFS_SESSION_LOG" ]]
}

@test "init_logging writes session header" {
    init_logging

    # Check for expected header content
    grep -q "ACFS newproj TUI Wizard Session Log" "$ACFS_SESSION_LOG"
    grep -q "Started:" "$ACFS_SESSION_LOG"
    grep -q "User:" "$ACFS_SESSION_LOG"
    grep -q "Terminal:" "$ACFS_SESSION_LOG"
}

@test "init_logging with --verbose enables DEBUG level" {
    init_logging --verbose

    [[ "$ACFS_LOG_LEVEL" -eq "$ACFS_LOG_DEBUG" ]]
    grep -q "Verbose mode enabled" "$ACFS_SESSION_LOG"
}

@test "init_logging handles missing directory gracefully" {
    # A file cannot be used as a directory, even when tests run as root.
    # Keep the failure fixture inside this test's private scratch.
    local blocked="$TEST_LOG_DIR/blocked-directory"
    printf 'retained-file\n' > "$blocked"
    export ACFS_LOG_DIR="$blocked"

    # Should fall back to the temp dir and still create a log
    init_logging

    # The log dir should have been reset to ${TMPDIR:-/tmp}
    [[ "$ACFS_LOG_DIR" == "${TMPDIR:-/tmp}" ]]
    # And the log file should exist
    [[ -f "$ACFS_SESSION_LOG" ]]
    [[ "$(cat "$blocked")" == retained-file ]]
}

@test "standalone logging privacy and recovery regressions pass" {
    run bash "$PROJECT_ROOT/scripts/lib/test_newproj_logging.sh"
    assert_success
    assert_output --partial "Results: 32/32 passed"
}

@test "newproj_logging sources and initializes under set -u without HOME" {
    run env -i PATH="/usr/bin:/bin" TMPDIR="$TEST_LOG_DIR" bash -c '
        set -euo pipefail
        source "$1"
        printf "dir=%s\n" "$ACFS_LOG_DIR"
        init_logging
        grep -q "Home: <unset>" "$ACFS_SESSION_LOG"
        log_env_snapshot
    ' _ "$PROJECT_ROOT/scripts/lib/newproj_logging.sh"

    assert_success
    assert_output --partial "$TEST_LOG_DIR/acfs-state/acfs/logs"
    refute_output --partial "unbound variable"
}

# ============================================================
# Log Level Tests
# ============================================================

@test "log_debug writes DEBUG level messages" {
    init_logging

    log_debug "Test debug message"

    grep -q "\[DEBUG\]" "$ACFS_SESSION_LOG"
    grep -q "Test debug message" "$ACFS_SESSION_LOG"
}

@test "log_info writes INFO level messages" {
    init_logging

    log_info "Test info message"

    grep -q "\[INFO \]" "$ACFS_SESSION_LOG"
    grep -q "Test info message" "$ACFS_SESSION_LOG"
}

@test "log_warn writes WARN level messages" {
    init_logging

    log_warn "Test warning message"

    grep -q "\[WARN \]" "$ACFS_SESSION_LOG"
    grep -q "Test warning message" "$ACFS_SESSION_LOG"
}

@test "log_error writes ERROR level messages" {
    init_logging

    log_error "Test error message"

    grep -q "\[ERROR\]" "$ACFS_SESSION_LOG"
    grep -q "Test error message" "$ACFS_SESSION_LOG"
}

@test "log level filtering respects ACFS_LOG_LEVEL" {
    export ACFS_LOG_LEVEL=$ACFS_LOG_WARN
    init_logging

    log_debug "Should not appear"
    log_info "Should not appear either"
    log_warn "Should appear"
    log_error "Should also appear"

    run grep -q "Should not appear" "$ACFS_SESSION_LOG"
    assert_failure
    grep -q "Should appear" "$ACFS_SESSION_LOG"
    grep -q "Should also appear" "$ACFS_SESSION_LOG"
}

# ============================================================
# Specialized Logging Tests
# ============================================================

@test "log_state tracks state changes" {
    init_logging

    log_state "project_name" "" "my-project"

    grep -q "\[STATE\]" "$ACFS_SESSION_LOG"
    grep -q "project_name:" "$ACFS_SESSION_LOG"
    grep -q "'' -> 'my-project'" "$ACFS_SESSION_LOG"
}

@test "log_screen tracks screen transitions" {
    init_logging

    log_screen "ENTER" "welcome"
    log_screen "RENDER" "welcome"
    log_screen "EXIT" "welcome"

    [[ $(grep -c "\[SCRN \]" "$ACFS_SESSION_LOG") -eq 3 ]]
    grep -q "ENTER: welcome" "$ACFS_SESSION_LOG"
}

@test "log_input sanitizes long inputs" {
    init_logging

    # Create a string longer than 100 chars
    local long_input=$(printf 'x%.0s' {1..150})
    log_input "test_field" "$long_input"

    grep -q "\[INPUT\]" "$ACFS_SESSION_LOG"
    grep -q "truncated" "$ACFS_SESSION_LOG"
}

@test "log_input masks sensitive data" {
    init_logging

    log_input "api_key" "sk-1234567890abcdef"

    grep -q "sk-\*\*\*" "$ACFS_SESSION_LOG"
    run grep -q "1234567890abcdef" "$ACFS_SESSION_LOG"
    assert_failure
}

@test "log_key records key presses" {
    init_logging

    log_key "ENTER"
    log_key "ESC"
    log_key "a"

    [[ $(grep -c "\[KEY  \]" "$ACFS_SESSION_LOG") -eq 3 ]]
}

@test "log_validation tracks validation results" {
    init_logging

    log_validation "project_name" "good-name" "PASS"
    log_validation "project_name" "bad name!" "FAIL" "Contains spaces"

    grep -q "\[VALID\]" "$ACFS_SESSION_LOG"
    grep -q "PASS" "$ACFS_SESSION_LOG"
    grep -q "FAIL" "$ACFS_SESSION_LOG"
    grep -q "Contains spaces" "$ACFS_SESSION_LOG"
}

@test "log_file_op tracks file operations" {
    init_logging

    log_file_op "CREATE" "/tmp/test/project"
    log_file_op "MKDIR" "/tmp/test" "OK"
    log_file_op "WRITE" "/tmp/test/.gitignore" "FAIL"

    [[ $(grep -c "\[FILE \]" "$ACFS_SESSION_LOG") -eq 3 ]]
}

@test "log_cmd tracks command execution" {
    init_logging

    log_cmd "git init" 0
    log_cmd "invalid_command" 127

    [[ $(grep -c "\[CMD  \]" "$ACFS_SESSION_LOG") -eq 2 ]]
    grep -q "FAIL(exit=127)" "$ACFS_SESSION_LOG"
}

@test "log_tech_detect logs technology detection" {
    init_logging

    log_tech_detect "nodejs" "package.json" "high"
    log_tech_detect "typescript" "tsconfig.json" "high"

    [[ $(grep -c "\[TECH \]" "$ACFS_SESSION_LOG") -eq 2 ]]
    grep -q "Detected: nodejs" "$ACFS_SESSION_LOG"
}

@test "log_nav tracks navigation actions" {
    init_logging

    log_nav "NEXT" "welcome" "project_name"
    log_nav "BACK" "project_name" "welcome"
    log_nav "CANCEL"

    [[ $(grep -c "\[NAV  \]" "$ACFS_SESSION_LOG") -eq 3 ]]
}

@test "log_json logs structured data" {
    init_logging

    log_json "wizard_state" '{"project_name": "test", "enabled": true}'

    grep -q "\[JSON \]" "$ACFS_SESSION_LOG"
    grep -q "wizard_state:" "$ACFS_SESSION_LOG"
    grep -q "project_name" "$ACFS_SESSION_LOG"
}

# ============================================================
# Session Management Tests
# ============================================================

@test "finalize_logging writes session footer" {
    init_logging
    finalize_logging 0

    grep -q "Session completed:" "$ACFS_SESSION_LOG"
    grep -q "Exit code: 0" "$ACFS_SESSION_LOG"
}

@test "finalize_logging shows log location on error" {
    init_logging

    run finalize_logging 1

    # Should output message about log location to stderr
    [[ "$output" == *"Session log saved to"* ]]
}

@test "show_log_location returns current log path" {
    init_logging

    run show_log_location
    assert_success

    [[ "$output" == *"$TEST_LOG_DIR"* ]]
}

@test "get_log_path returns session log path" {
    init_logging

    local path
    path=$(get_log_path)

    [[ -n "$path" ]]
    [[ -f "$path" ]]
}

# ============================================================
# Debug Helper Tests
# ============================================================

@test "log_env_snapshot captures environment" {
    init_logging

    log_env_snapshot

    grep -q "\[ENV  \]" "$ACFS_SESSION_LOG"
    grep -q "PATH=" "$ACFS_SESSION_LOG"
    grep -q "TERM=" "$ACFS_SESSION_LOG"
}

@test "log_checkpoint tracks timing" {
    init_logging

    log_checkpoint "start"
    sleep 1
    log_checkpoint "end"

    [[ $(grep -c "\[TIME \]" "$ACFS_SESSION_LOG") -eq 2 ]]
    grep -q "Checkpoint: start" "$ACFS_SESSION_LOG"
}

@test "log_dump_state dumps associative array" {
    init_logging

    declare -A TEST_STATE=(
        [project_name]="my-project"
        [tech_stack]="nodejs typescript"
    )

    log_dump_state TEST_STATE

    grep -q "\[DUMP \]" "$ACFS_SESSION_LOG"
    grep -q "project_name" "$ACFS_SESSION_LOG"
}

# ============================================================
# Verbose Mode Tests
# ============================================================

@test "enable_verbose sets DEBUG level" {
    export ACFS_LOG_LEVEL=$ACFS_LOG_INFO
    init_logging

    enable_verbose

    [[ "$ACFS_LOG_LEVEL" -eq "$ACFS_LOG_DEBUG" ]]
}

@test "is_verbose returns true when DEBUG level" {
    export ACFS_LOG_LEVEL=$ACFS_LOG_DEBUG
    init_logging

    is_verbose
}

@test "is_verbose returns false when not DEBUG level" {
    export ACFS_LOG_LEVEL=$ACFS_LOG_INFO
    init_logging

    run is_verbose
    assert_failure
}

# ============================================================
# Edge Cases
# ============================================================

@test "multiple sessions create separate log files" {
    init_logging
    local first_log="$ACFS_SESSION_LOG"

    sleep 1  # Ensure different timestamp

    init_logging
    local second_log="$ACFS_SESSION_LOG"

    [[ "$first_log" != "$second_log" ]]
    [[ -f "$first_log" ]]
    [[ -f "$second_log" ]]
}

@test "logging works without session log initialized" {
    # Don't call init_logging
    ACFS_SESSION_LOG=""

    # These should not error
    run log_debug "No log file"
    run log_info "No log file"
    run log_state "key" "old" "new"

    # All should succeed silently
    assert_success
}

@test "log format includes timestamp and caller info" {
    init_logging

    log_info "Test message"

    # Check format: [HH:MM:SS.mmm] [LEVEL] [caller:line] message
    grep -E "^\[[0-9]{2}:[0-9]{2}:[0-9]{2}" "$ACFS_SESSION_LOG"
    grep -E "\[INFO \]" "$ACFS_SESSION_LOG"
}
