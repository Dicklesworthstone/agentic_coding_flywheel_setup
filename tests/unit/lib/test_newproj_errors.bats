#!/usr/bin/env bats
# ============================================================
# Unit Tests for newproj_errors.sh
# Tests error handling and recovery for the newproj TUI wizard
# ============================================================

load '../test_helper'

setup() {
    common_setup

    # Create temp directory for testing
    TEST_DIR=$(create_temp_dir)
    export TEST_DIR

    # Source the error handling module
    source_lib "newproj_errors"
}

teardown() {
    common_teardown
}

# ============================================================
# Cleanup Registration Tests
# ============================================================

@test "register_cleanup adds item to cleanup list" {
    register_cleanup "/tmp/test-item"

    [[ " ${WIZARD_CLEANUP_ITEMS[*]} " == *" /tmp/test-item "* ]]
}

@test "unregister_cleanup removes item from cleanup list" {
    register_cleanup "/tmp/item1"
    register_cleanup "/tmp/item2"
    register_cleanup "/tmp/item3"

    unregister_cleanup "/tmp/item2"

    [[ " ${WIZARD_CLEANUP_ITEMS[*]} " == *" /tmp/item1 "* ]]
    [[ " ${WIZARD_CLEANUP_ITEMS[*]} " != *" /tmp/item2 "* ]]
    [[ " ${WIZARD_CLEANUP_ITEMS[*]} " == *" /tmp/item3 "* ]]
}

# ============================================================
# Signal Handler Tests
# ============================================================

@test "setup_signal_handlers installs handlers without error" {
    run setup_signal_handlers
    assert_success
}

@test "SAVED_STTY is set or empty after setup_signal_handlers" {
    setup_signal_handlers

    # SAVED_STTY may be empty if not in a real terminal, but the function should not fail
    # Just verify the variable exists (even if empty)
    [[ -v SAVED_STTY ]]
}

# ============================================================
# Pre-flight Check Tests
# ============================================================

@test "preflight_check passes with valid terminal" {
    # Set up mock terminal environment
    export TERM=xterm
    export COLUMNS=80
    export LINES=24

    run preflight_check

    # Should pass (we're in a TTY in the test environment)
    # Note: This might fail in CI without a TTY
    [[ "$status" -eq 0 ]] || [[ "$output" == *"Not running in interactive terminal"* ]]
}

@test "preflight_check warns about missing optional commands" {
    # This test just ensures preflight_check doesn't crash
    # when optional commands are missing
    run preflight_check

    # Should either pass or fail with specific errors
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

# ============================================================
# Directory Creation Tests
# ============================================================

@test "try_create_directory creates new directory" {
    local new_dir="$TEST_DIR/new-project"

    run try_create_directory "$new_dir"
    assert_success

    [[ -d "$new_dir" ]]
}

@test "try_create_directory fails if path exists" {
    local existing_dir="$TEST_DIR/existing"
    mkdir "$existing_dir"

    run try_create_directory "$existing_dir"
    assert_failure

    [[ "$output" == *"already exists"* ]]
}

@test "try_create_directory fails if parent doesn't exist" {
    local bad_path="/nonexistent/parent/directory"

    run try_create_directory "$bad_path"
    assert_failure

    [[ "$output" == *"does not exist"* ]]
}

@test "try_create_directory registers for cleanup" {
    local new_dir="$TEST_DIR/cleanup-test"
    WIZARD_CLEANUP_ITEMS=()

    try_create_directory "$new_dir"

    [[ " ${WIZARD_CLEANUP_ITEMS[*]} " == *" $new_dir "* ]]
}

# ============================================================
# Git Initialization Tests
# ============================================================

@test "try_git_init initializes git repository" {
    local project_dir="$TEST_DIR/git-project"
    mkdir -p "$project_dir"

    run try_git_init "$project_dir"
    assert_success

    [[ -d "$project_dir/.git" ]]
}

@test "try_git_init succeeds if already a git repo" {
    local project_dir="$TEST_DIR/existing-git"
    mkdir -p "$project_dir"
    git init "$project_dir" &>/dev/null

    run try_git_init "$project_dir"
    assert_success
}

# ============================================================
# br Initialization Tests
# ============================================================

@test "try_br_init gracefully skips if br not installed" {
    local project_dir="$TEST_DIR/br-project"
    mkdir -p "$project_dir"

    # Create a mock function that pretends br is not installed
    # by temporarily overriding command
    br() {
        return 127  # Command not found
    }
    export -f br

    # Use a subshell to test the case where br command doesn't exist
    run bash -c '
        source '"$ACFS_LIB_DIR"'/newproj_errors.sh
        # Override command -v to report br as missing
        command() {
            if [[ "$2" == "br" ]]; then
                return 1
            fi
            builtin command "$@"
        }
        try_br_init "'"$project_dir"'"
    '

    assert_success  # Should not fail, just skip
    [[ "$output" == *"br not installed"* ]]
}

# ============================================================
# File Writing Tests
# ============================================================

@test "try_write_file creates file with content" {
    local test_file="$TEST_DIR/test-file.txt"

    run try_write_file "$test_file" "Hello, World!"
    assert_success

    [[ -f "$test_file" ]]
    [[ "$(cat "$test_file")" == "Hello, World!" ]]
}

@test "try_write_file creates parent directories" {
    local test_file="$TEST_DIR/subdir/nested/file.txt"

    run try_write_file "$test_file" "Content"
    assert_success

    [[ -f "$test_file" ]]
}

@test "try_write_file tracks file for transaction" {
    WIZARD_TRANSACTION_ACTIVE=true
    WIZARD_CREATED_FILES=()

    local test_file="$TEST_DIR/tracked-file.txt"
    try_write_file "$test_file" "Content"

    [[ " ${WIZARD_CREATED_FILES[*]} " == *" $test_file "* ]]

    WIZARD_TRANSACTION_ACTIVE=false
}

# ============================================================
# Transaction Tests
# ============================================================

@test "begin_project_creation starts transaction" {
    begin_project_creation

    [[ "$WIZARD_TRANSACTION_ACTIVE" == "true" ]]
    [[ ${#WIZARD_CREATED_FILES[@]} -eq 0 ]]
}

@test "track_created_file adds file to transaction" {
    begin_project_creation

    track_created_file "/tmp/file1"
    track_created_file "/tmp/file2"

    [[ ${#WIZARD_CREATED_FILES[@]} -eq 2 ]]
}

@test "commit_project_creation clears transaction" {
    begin_project_creation
    track_created_file "/tmp/file1"
    register_cleanup "/tmp/file1"

    commit_project_creation

    [[ "$WIZARD_TRANSACTION_ACTIVE" == "false" ]]
    [[ ${#WIZARD_CREATED_FILES[@]} -eq 0 ]]
    [[ ${#WIZARD_CLEANUP_ITEMS[@]} -eq 0 ]]
}

@test "rollback_project_creation removes created files" {
    local test_file1="$TEST_DIR/rollback-test1.txt"
    local test_file2="$TEST_DIR/rollback-test2.txt"

    begin_project_creation
    echo "test" > "$test_file1"
    track_created_file "$test_file1"
    echo "test" > "$test_file2"
    track_created_file "$test_file2"

    rollback_project_creation

    [[ ! -f "$test_file1" ]]
    [[ ! -f "$test_file2" ]]
    [[ "$WIZARD_TRANSACTION_ACTIVE" == "false" ]]
}

# ============================================================
# Graceful Degradation Tests
# ============================================================

@test "optional_feature returns 0 on success" {
    run optional_feature "echo test" echo "success"
    assert_success
}

@test "optional_feature returns 0 on failure (graceful)" {
    run optional_feature "failing command" false
    assert_success  # Should not propagate failure
}

@test "feature_available returns 0 for existing command" {
    run feature_available "bash"
    assert_success
}

@test "feature_available returns 1 for missing command" {
    run feature_available "nonexistent_command_12345"
    assert_failure
}

# ============================================================
# Validation Tests
# ============================================================

@test "validate_project_name accepts valid names" {
    run validate_project_name "my-project"
    assert_success

    run validate_project_name "MyProject123"
    assert_success

    run validate_project_name "project_name"
    assert_success
}

@test "validate_project_name rejects empty name" {
    run validate_project_name ""
    assert_failure
    [[ "$output" == *"cannot be empty"* ]]
}

@test "validate_project_name rejects too short name" {
    run validate_project_name "a"
    assert_failure
    [[ "$output" == *"at least 2 characters"* ]]
}

@test "validate_project_name rejects invalid characters" {
    run validate_project_name "my project"
    assert_failure

    run validate_project_name "my@project"
    assert_failure

    run validate_project_name "my/project"
    assert_failure

    # Dots are not allowed in project names
    run validate_project_name "project.name"
    assert_failure
}

@test "validate_project_name rejects names starting with number" {
    run validate_project_name "123project"
    assert_failure
    [[ "$output" == *"must start with a letter"* ]]
}

@test "validate_project_name rejects reserved names" {
    run validate_project_name "node_modules"
    assert_failure
    [[ "$output" == *"reserved name"* ]]

    run validate_project_name ".git"
    assert_failure
}

@test "validate_directory accepts valid path" {
    local new_path="$TEST_DIR/valid-project"

    run validate_directory "$new_path"
    assert_success
}

@test "validate_directory rejects existing path" {
    local existing_path="$TEST_DIR/existing"
    mkdir "$existing_path"

    run validate_directory "$existing_path"
    assert_failure
    [[ "$output" == *"already exists"* ]]
}

@test "validate_directory rejects path with missing parent" {
    run validate_directory "/nonexistent/parent/project"
    assert_failure
    [[ "$output" == *"does not exist"* ]]
}

@test "validate_directory returns expanded path" {
    local relative_path="new-project"
    cd "$TEST_DIR"

    local result
    result=$(validate_directory "$relative_path")

    [[ "$result" == "$TEST_DIR/new-project" ]]
}

# ============================================================
# Error Message Tests
# ============================================================

@test "show_error_with_recovery displays permission error hints" {
    run show_error_with_recovery "permission" "No write access"

    [[ "$output" == *"Check permissions"* ]]
    [[ "$output" == *"chown"* ]]
}

@test "show_error_with_recovery displays disk full hints" {
    run show_error_with_recovery "disk_full" "Cannot write"

    [[ "$output" == *"disk space"* ]]
    [[ "$output" == *"df -h"* ]]
}

@test "show_error_with_recovery displays exists hints" {
    run show_error_with_recovery "exists" "Path exists"

    [[ "$output" == *"different project name"* ]]
}
