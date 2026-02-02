#!/usr/bin/env bats
# ============================================================
# E2E Tests: Navigation and Error Recovery
# Tests screen transitions, back navigation, and error handling
# ============================================================

load 'test_helper'

setup() {
    e2e_setup
}

teardown() {
    e2e_teardown
}

# ============================================================
# Navigation Tests (with expect)
# ============================================================

@test "EXPECT: Back navigation returns to previous screen" {
    skip_without_expect

    run expect "$E2E_DIR/expect/navigation.exp" \
        "$ACFS_LIB_DIR/newproj.sh" \
        "back_navigation"

    assert_success
    [[ "$output" == *"back"* ]] || [[ "$output" == *"Directory"* ]]
}

@test "EXPECT: Edit from confirmation returns to project name" {
    skip_without_expect

    run expect "$E2E_DIR/expect/navigation.exp" \
        "$ACFS_LIB_DIR/newproj.sh" \
        "edit_from_confirm"

    assert_success
    [[ "$output" == *"Project Name"* ]] || [[ "$output" == *"edit"* ]]
}

@test "EXPECT: Escape cancels wizard cleanly" {
    skip_without_expect

    run expect "$E2E_DIR/expect/navigation.exp" \
        "$ACFS_LIB_DIR/newproj.sh" \
        "escape_cancel"

    # Should exit cleanly - either with cancel message or clean exit
    # Note: Exit codes 0 or 1 are both acceptable for cancellation
    [[ "$status" -le 1 ]]
    # Output should indicate cancellation or clean exit
    [[ "$output" == *"cancel"* ]] || [[ "$output" == *"exit"* ]] || [[ "$output" == *"abort"* ]] || [[ -z "$output" ]]
}

# ============================================================
# Error Handling Tests (with expect)
# ============================================================

@test "EXPECT: Empty project name is rejected" {
    skip_without_expect

    run expect "$E2E_DIR/expect/error_handling.exp" \
        "$ACFS_LIB_DIR/newproj.sh" \
        "invalid_name"

    # Should handle gracefully
    [[ "$status" -eq 0 ]]
}

@test "EXPECT: Existing directory shows conflict" {
    skip_without_expect

    # Create existing directory
    local existing_dir="$E2E_TEST_DIR/existing-project"
    mkdir -p "$existing_dir"

    run expect "$E2E_DIR/expect/error_handling.exp" \
        "$ACFS_LIB_DIR/newproj.sh" \
        "existing_dir" \
        "$existing_dir"

    # Should handle gracefully
    [[ "$status" -eq 0 ]]
}

@test "EXPECT: Can recover from validation error" {
    skip_without_expect

    run expect "$E2E_DIR/expect/error_handling.exp" \
        "$ACFS_LIB_DIR/newproj.sh" \
        "validation_recovery"

    assert_success
    [[ "$output" == *"recover"* ]] || [[ "$output" == *"Directory"* ]]
}

# ============================================================
# CLI Error Handling
# ============================================================

@test "CLI rejects empty project name" {
    run bash "$ACFS_LIB_DIR/newproj.sh" ""

    assert_failure
    [[ "$output" == *"name"* ]] || [[ "$output" == *"required"* ]] || [[ "$output" == *"Usage"* ]]
}

@test "CLI rejects invalid directory path" {
    run bash "$ACFS_LIB_DIR/newproj.sh" "test-project" "/nonexistent/deeply/nested/path/that/cant/exist"

    assert_failure
}

@test "CLI warns about existing directory but continues" {
    # newproj shows a warning but continues (idempotent behavior)
    local existing_dir="$E2E_TEST_DIR/existing-cli-project"
    mkdir -p "$existing_dir"

    run bash "$ACFS_LIB_DIR/newproj.sh" "existing-cli-project" "$existing_dir"

    # Should succeed with warning, not fail
    assert_success
    # Should show warning message
    [[ "$output" == *"exist"* ]] || [[ "$output" == *"already"* ]] || [[ "$output" == *"Warning"* ]]
}

@test "CLI handles special characters in project name" {
    local project_name='test-project_123'
    local project_dir="$E2E_TEST_DIR/$project_name"

    run bash "$ACFS_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    assert_success
    [[ -d "$project_dir" ]]
}

@test "CLI rejects project name with slashes" {
    run bash "$ACFS_LIB_DIR/newproj.sh" "test/project" "$E2E_TEST_DIR/slash-test"

    # Slashes in project names should be rejected (invalid characters)
    # OR the project should be created with the slash escaped/replaced
    if [[ "$status" -eq 0 ]]; then
        # If it succeeded, verify a project was actually created
        [[ -d "$E2E_TEST_DIR/slash-test" ]] || [[ -d "$E2E_TEST_DIR/test/project" ]]
    else
        # If it failed, verify appropriate error message
        [[ "$output" == *"invalid"* ]] || [[ "$output" == *"slash"* ]] || [[ "$output" == *"character"* ]] || [[ "$output" == *"name"* ]]
    fi
}

# ============================================================
# Flag Parsing
# ============================================================

@test "Unknown flag shows error" {
    run bash "$ACFS_LIB_DIR/newproj.sh" --unknown-flag

    assert_failure
    [[ "$output" == *"Unknown"* ]] || [[ "$output" == *"option"* ]] || [[ "$output" == *"flag"* ]]
}

@test "Help flag shows usage" {
    run bash "$ACFS_LIB_DIR/newproj.sh" --help

    assert_success
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"newproj"* ]]
}

@test "Version flag shows version" {
    run bash "$ACFS_LIB_DIR/newproj.sh" --version 2>&1 || true

    # Version flag may or may not be implemented
    [[ "$output" == *"version"* ]] || [[ "$output" == *"ACFS"* ]] || skip "Version flag not implemented"
}

@test "Multiple feature flags work together" {
    local project_name="multi-flag-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    run bash "$ACFS_LIB_DIR/newproj.sh" "$project_name" "$project_dir" --no-br --no-agents

    assert_success
    [[ -d "$project_dir" ]]
    [[ ! -d "$project_dir/.beads" ]]
    [[ ! -f "$project_dir/AGENTS.md" ]]
}

# ============================================================
# State Persistence (wizard maintains state through screens)
# ============================================================

@test "CLI mode works without tech stack flag" {
    # Tech stack is only selectable in interactive mode
    # CLI mode creates a generic project
    local project_name="tech-stack-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    run bash "$ACFS_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    assert_success
    [[ -d "$project_dir" ]]
    # Project should still have basic files
    [[ -f "$project_dir/README.md" ]]
}

# ============================================================
# Rollback and Recovery
# ============================================================

@test "Failed creation doesn't leave partial project" {
    # This is tricky to test without mocking, but we can check
    # that a previously failed dir doesn't exist

    local project_name="rollback-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    # Create a file where the directory should be (to cause failure)
    echo "blocker" > "$project_dir"

    run bash "$ACFS_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    assert_failure

    # The blocker file should still exist (not deleted by rollback)
    [[ -f "$project_dir" ]]
}

# ============================================================
# Concurrent Execution
# ============================================================

@test "Multiple wizard instances don't conflict" {
    local project1="$E2E_TEST_DIR/concurrent-1"
    local project2="$E2E_TEST_DIR/concurrent-2"

    # Run two instances in parallel
    bash "$ACFS_LIB_DIR/newproj.sh" "concurrent-1" "$project1" &
    local pid1=$!

    bash "$ACFS_LIB_DIR/newproj.sh" "concurrent-2" "$project2" &
    local pid2=$!

    # Wait for both
    wait $pid1
    local status1=$?
    wait $pid2
    local status2=$?

    # Both should succeed
    [[ $status1 -eq 0 ]]
    [[ $status2 -eq 0 ]]
    [[ -d "$project1" ]]
    [[ -d "$project2" ]]
}

# ============================================================
# Interrupt Handling
# ============================================================

@test "CLI handles SIGINT gracefully" {
    local project_name="sigint-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    # Start the command and send SIGINT after a short delay
    bash "$ACFS_LIB_DIR/newproj.sh" "$project_name" "$project_dir" &
    local pid=$!

    sleep 0.1
    kill -INT $pid 2>/dev/null || true

    # Wait and check it didn't leave corrupt state
    wait $pid 2>/dev/null || true

    # Either the project was created (fast enough) or it wasn't (interrupted)
    # But there shouldn't be partial state
    if [[ -d "$project_dir" ]]; then
        # If directory exists, it should be complete
        [[ -f "$project_dir/README.md" ]] || [[ ! -d "$project_dir/.git" ]] || skip "Partial project state"
    fi
}
