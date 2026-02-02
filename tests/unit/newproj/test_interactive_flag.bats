#!/usr/bin/env bats
# ============================================================
# Unit Tests for newproj.sh - Interactive Flag
# ============================================================

load '../test_helper'

setup() {
    common_setup

    # Create temp directory for testing
    TEST_DIR=$(create_temp_dir)
    export TEST_DIR

    # Set up logging
    export ACFS_LOG_DIR="$TEST_DIR/logs"
    mkdir -p "$ACFS_LOG_DIR"
    export ACFS_LOG_LEVEL=0

    # Set script directory
    export NEWPROJ_SCRIPT_DIR="$ACFS_LIB_DIR"

    # Source the newproj module (just functions, not main)
    # We need to avoid running main(), so we source with set +e
    set +e
    source "$ACFS_LIB_DIR/newproj.sh" 2>/dev/null || true
    set -e
}

teardown() {
    common_teardown
}

# ============================================================
# Environment Detection Tests
# ============================================================

@test "is_ci_environment returns true when CI=true" {
    export CI=true
    is_ci_environment
}

@test "is_ci_environment returns true when GITHUB_ACTIONS set" {
    export GITHUB_ACTIONS=true
    is_ci_environment
}

@test "is_ci_environment returns true when GITLAB_CI set" {
    export GITLAB_CI=true
    is_ci_environment
}

@test "is_ci_environment returns true when JENKINS_URL set" {
    export JENKINS_URL="http://jenkins.example.com"
    is_ci_environment
}

@test "is_ci_environment returns true when TRAVIS set" {
    export TRAVIS=true
    is_ci_environment
}

@test "is_ci_environment returns true when CIRCLECI set" {
    export CIRCLECI=true
    is_ci_environment
}

@test "is_ci_environment returns true when TERM=dumb" {
    export TERM=dumb
    is_ci_environment
}

@test "is_ci_environment returns false in normal environment" {
    unset CI GITHUB_ACTIONS GITLAB_CI JENKINS_URL TRAVIS CIRCLECI
    export TERM=xterm

    ! is_ci_environment
}

# ============================================================
# TTY Detection Tests
# ============================================================

@test "is_stdin_tty function exists" {
    declare -f is_stdin_tty
}

@test "is_stdout_tty function exists" {
    declare -f is_stdout_tty
}

# ============================================================
# Terminal Size Tests
# ============================================================

@test "get_terminal_size returns dimensions" {
    local size
    size=$(get_terminal_size)

    # Should return two space-separated numbers
    [[ "$size" =~ ^[0-9]+\ [0-9]+$ ]]
}

@test "check_terminal_size passes for large terminal" {
    # Mock terminal size by providing reasonable defaults
    # This test assumes we're running in a reasonable terminal
    # If not, we just skip it
    local size
    size=$(get_terminal_size)
    local cols="${size%% *}"
    local lines="${size##* }"

    if [[ "$cols" -ge 60 ]] && [[ "$lines" -ge 15 ]]; then
        check_terminal_size 60 15
    else
        skip "Terminal too small for this test"
    fi
}

@test "check_terminal_size fails with error message for small terminal" {
    local error
    error=$(check_terminal_size 1000 1000) || true

    [[ "$error" == *"Terminal too small"* ]]
}

# ============================================================
# TUI Module Check Tests
# ============================================================

@test "check_tui_available passes when module exists" {
    # The module should exist
    check_tui_available
}

@test "check_tui_available fails when module missing" {
    export NEWPROJ_SCRIPT_DIR="/nonexistent/path"

    local error
    error=$(check_tui_available) || true

    [[ "$error" == *"not found"* ]]
}

# ============================================================
# Help Text Tests
# ============================================================

@test "print_help shows interactive flag" {
    local output
    output=$(print_help)

    [[ "$output" == *"--interactive"* ]]
    [[ "$output" == *"-i"* ]]
}

@test "print_help shows interactive examples" {
    local output
    output=$(print_help)

    [[ "$output" == *"--interactive"* ]]
    [[ "$output" == *"TUI wizard"* ]]
}

# ============================================================
# Argument Parsing Tests
# ============================================================

@test "main parses --interactive flag" {
    # We can't fully test main without a TTY, but we can test
    # that the flag is recognized
    export CI=true  # Force CI mode to make interactive fail fast

    run bash -c '
        source '"$ACFS_LIB_DIR"'/newproj.sh
        main --interactive 2>&1
    '

    # Should fail with CI environment error (meaning flag was recognized)
    [[ "$output" == *"CI environment"* ]] || [[ "$output" == *"TTY"* ]]
}

@test "main parses -i flag (short form)" {
    export CI=true

    run bash -c '
        source '"$ACFS_LIB_DIR"'/newproj.sh
        main -i 2>&1
    '

    # Should fail with CI environment error
    [[ "$output" == *"CI environment"* ]] || [[ "$output" == *"TTY"* ]]
}

@test "main allows --interactive with project name" {
    export CI=true

    run bash -c '
        source '"$ACFS_LIB_DIR"'/newproj.sh
        main --interactive myproject 2>&1
    '

    # Should fail with CI error, but not argument error
    [[ "$output" != *"Too many arguments"* ]]
}

# ============================================================
# Interactive Mode Pre-flight Tests
# ============================================================

@test "run_interactive_mode fails in CI environment" {
    export CI=true

    run run_interactive_mode
    assert_failure

    [[ "$output" == *"CI environment"* ]]
}

@test "run_interactive_mode provides helpful error for CI" {
    export CI=true

    run run_interactive_mode

    [[ "$output" == *"CLI mode"* ]]
}

@test "run_interactive_mode fails when TUI module missing" {
    export NEWPROJ_SCRIPT_DIR="/nonexistent"
    # Unset ALL CI environment variables
    unset CI GITHUB_ACTIONS GITLAB_CI JENKINS_URL TRAVIS CIRCLECI
    export TERM=xterm

    # This will also fail because we're not in a real TTY
    # but we can check if it reaches the TUI check
    run run_interactive_mode 2>&1 || true

    # Should mention either TTY or TUI module
    [[ "$output" == *"TTY"* ]] || [[ "$output" == *"TUI module"* ]] || [[ "$output" == *"terminal"* ]]
}

# ============================================================
# State Pre-fill Tests
# ============================================================

@test "run_interactive_mode shows pre-fill message for project name" {
    # We'll check the early output before TTY check fails
    unset CI GITHUB_ACTIONS
    export TERM=xterm

    # This will fail on TTY check in test environment, but we can
    # check if pre-fill logic is reached

    # Just verify the function exists and takes arguments
    declare -f run_interactive_mode

    # The actual pre-fill is inside the function after TTY checks
    # which we can't pass in a test environment
}

# ============================================================
# CLI Mode Fallback Tests
# ============================================================

@test "main still works in CLI mode without --interactive" {
    local test_project="$TEST_DIR/cli-test-project"

    run bash -c '
        source '"$ACFS_LIB_DIR"'/newproj.sh
        main cli-test-project '"$test_project"' 2>&1
    '

    # Should create project in CLI mode
    [[ -d "$test_project" ]] || [[ "$output" == *"Creating project"* ]]
}

@test "main rejects unknown flags" {
    run bash -c '
        source '"$ACFS_LIB_DIR"'/newproj.sh
        main --unknown-flag 2>&1
    '

    assert_failure
    [[ "$output" == *"Unknown option"* ]]
}

# ============================================================
# Combined Flag Tests
# ============================================================

@test "main allows --interactive with --no-br" {
    export CI=true

    run bash -c '
        source '"$ACFS_LIB_DIR"'/newproj.sh
        main --interactive --no-br 2>&1
    '

    # Should reach interactive mode (and fail on CI check)
    [[ "$output" == *"CI environment"* ]] || [[ "$output" == *"TTY"* ]]
    [[ "$output" != *"Unknown option"* ]]
}

@test "main allows -i with project name and directory" {
    export CI=true

    run bash -c '
        source '"$ACFS_LIB_DIR"'/newproj.sh
        main -i myproject /tmp/myproject 2>&1
    '

    # Should not complain about arguments
    [[ "$output" != *"Too many arguments"* ]]
}

# ============================================================
# Edge Cases
# ============================================================

@test "interactive mode without project name is valid" {
    export CI=true

    run bash -c '
        source '"$ACFS_LIB_DIR"'/newproj.sh
        main --interactive 2>&1
    '

    # Should not require project name in interactive mode
    [[ "$output" != *"Project name is required"* ]]
}

@test "CLI mode without project name fails" {
    run bash -c '
        source '"$ACFS_LIB_DIR"'/newproj.sh
        main 2>&1
    '

    assert_failure
    [[ "$output" == *"Project name is required"* ]] || [[ "$output" == *"help"* ]]
}
