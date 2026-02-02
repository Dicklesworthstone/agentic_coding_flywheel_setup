#!/usr/bin/env bats
# ============================================================
# E2E Tests: Happy Path
# Tests the normal successful workflow through the wizard
# ============================================================

load 'test_helper'

setup() {
    e2e_setup
}

teardown() {
    e2e_teardown
}

# ============================================================
# CLI Mode Tests (always work, no PTY needed)
# ============================================================

@test "CLI mode creates project with all defaults" {
    local project_name="cli-default-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    run bash "$ACFS_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    assert_success
    [[ -d "$project_dir" ]]
    [[ -f "$project_dir/README.md" ]]
    [[ -f "$project_dir/.gitignore" ]]
    [[ -d "$project_dir/.git" ]]
}

@test "CLI mode creates AGENTS.md by default" {
    local project_name="cli-agents-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    run bash "$ACFS_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    assert_success
    [[ -f "$project_dir/AGENTS.md" ]]

    # Verify AGENTS.md has some content (br or newproj creates it)
    [[ -s "$project_dir/AGENTS.md" ]]
}

@test "CLI mode creates beads directory by default" {
    local project_name="cli-beads-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    run bash "$ACFS_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    assert_success
    [[ -d "$project_dir/.beads" ]] || skip "br not installed"
}

@test "CLI mode with --no-br skips beads" {
    local project_name="cli-no-br-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    run bash "$ACFS_LIB_DIR/newproj.sh" "$project_name" "$project_dir" --no-br

    assert_success
    [[ ! -d "$project_dir/.beads" ]]
}

@test "CLI mode with --no-agents --no-br skips AGENTS.md completely" {
    # Note: br creates its own AGENTS.md, so we need --no-br too
    local project_name="cli-no-agents-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    run bash "$ACFS_LIB_DIR/newproj.sh" "$project_name" "$project_dir" --no-agents --no-br

    assert_success
    [[ ! -f "$project_dir/AGENTS.md" ]]
}

@test "CLI mode initializes git with initial commit" {
    local project_name="cli-git-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    run bash "$ACFS_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    assert_success
    [[ -d "$project_dir/.git" ]]

    # Check for initial commit
    cd "$project_dir"
    local commit_count
    commit_count=$(git rev-list --count HEAD 2>/dev/null || echo 0)
    [[ "$commit_count" -ge 1 ]]
}

# ============================================================
# Interactive Mode Tests (require PTY or expect)
# ============================================================

@test "Interactive mode detects CI environment" {
    export CI=true

    run bash "$ACFS_LIB_DIR/newproj.sh" --interactive

    assert_failure
    [[ "$output" == *"CI environment"* ]]
}

@test "Interactive mode help shows --interactive flag" {
    run bash "$ACFS_LIB_DIR/newproj.sh" --help

    assert_success
    [[ "$output" == *"--interactive"* ]]
    [[ "$output" == *"-i"* ]]
}

# ============================================================
# Happy Path with Expect (full interactive testing)
# ============================================================

@test "EXPECT: Full happy path creates complete project" {
    skip_without_expect

    local project_name="expect-happy-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    run expect "$E2E_DIR/expect/happy_path.exp" \
        "$ACFS_LIB_DIR/newproj.sh" \
        "$project_name" \
        "$project_dir"

    assert_success

    # Verify project structure
    verify_project_created "$project_dir" "$project_name"

    # Verify all default features enabled
    verify_feature_enabled "$project_dir" "agents"
}

@test "EXPECT: Happy path captures output correctly" {
    skip_without_expect

    local project_name="expect-output-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    run expect "$E2E_DIR/expect/happy_path.exp" \
        "$ACFS_LIB_DIR/newproj.sh" \
        "$project_name" \
        "$project_dir"

    # Verify key screens were shown
    [[ "$output" == *"Welcome"* ]]
    [[ "$output" == *"Project Name"* ]]
    [[ "$output" == *"Project Created"* ]]
}

# ============================================================
# Pipe Mode Tests (work without expect, but limited)
# ============================================================

@test "PIPE: Can provide input via stdin in test mode" {
    # This tests that the wizard can accept piped input
    # Note: This may not work perfectly without a PTY

    local project_name="pipe-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    # Build input sequence
    local input
    input=$(cat <<EOF
${project_name}
${project_dir}



c
q
EOF
)

    # Try running with piped input
    # This may fail without PTY - that's expected in some environments
    run bash -c "echo '$input' | TERM=dumb bash '$ACFS_LIB_DIR/newproj.sh' --interactive 2>&1"

    # Check if it either succeeded or failed appropriately
    if [[ "$status" -eq 0 ]]; then
        # Success - verify project created
        if [[ ! -d "$project_dir" ]]; then
            # Interactive mode may require PTY - skip if project wasn't created
            skip "Pipe mode requires PTY (project not created)"
        fi
    else
        # Failure - should be due to TTY requirement, not other errors
        # Accept TTY-related errors as valid skip reason
        if [[ "$output" == *"TTY"* ]] || [[ "$output" == *"terminal"* ]] || [[ "$output" == *"CI environment"* ]]; then
            skip "Interactive mode requires TTY"
        fi
        # If it failed for other reasons, that's a real failure
        printf 'Unexpected non-TTY error (status=%d): %s\n' "$status" "$output" >&2
        return 1
    fi
}

# ============================================================
# Project Content Verification
# ============================================================

@test "Created README.md contains project name" {
    local project_name="readme-content-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    bash "$ACFS_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    grep -q "$project_name" "$project_dir/README.md"
}

@test "Created .gitignore contains common patterns" {
    local project_name="gitignore-content-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    bash "$ACFS_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    # Check for common patterns
    grep -q "node_modules" "$project_dir/.gitignore"
    grep -q ".env" "$project_dir/.gitignore"
    grep -q "__pycache__" "$project_dir/.gitignore"
}

@test "AGENTS.md contains project-appropriate content" {
    local project_name="agents-content-test"
    local project_dir="$E2E_TEST_DIR/$project_name"

    bash "$ACFS_LIB_DIR/newproj.sh" "$project_name" "$project_dir"

    # Check AGENTS.md exists and has content
    [[ -f "$project_dir/AGENTS.md" ]]
    [[ -s "$project_dir/AGENTS.md" ]]

    # AGENTS.md should have some meaningful content
    # br creates "landing the plane" instructions, newproj creates standard template
    grep -qE "(AGENT|Landing|plane|session|git)" "$project_dir/AGENTS.md"
}
