#!/usr/bin/env bats
# ============================================================
# Unit Tests for newproj_agents.sh - AGENTS.md Generator
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

    # Source dependencies
    source_lib "newproj_logging"
    init_logging

    # Source the agents module
    source_lib "newproj_agents"
}

teardown() {
    common_teardown
}

# ============================================================
# Section Registry Tests
# ============================================================

@test "AGENTS_SECTION_ORDER is defined and non-empty" {
    [[ ${#AGENTS_SECTION_ORDER[@]} -gt 0 ]]
}

@test "AGENTS_SECTION_ORDER contains header as first element" {
    [[ "${AGENTS_SECTION_ORDER[0]}" == "header" ]]
}

@test "AGENTS_SECTION_META contains entries for all ordered sections" {
    for section_id in "${AGENTS_SECTION_ORDER[@]}"; do
        [[ -n "${AGENTS_SECTION_META[$section_id]}" ]]
    done
}

@test "is_section_required returns true for header" {
    is_section_required "header"
}

@test "is_section_required returns true for rule_1_absolute" {
    is_section_required "rule_1_absolute"
}

@test "is_section_required returns false for nodejs_toolchain" {
    ! is_section_required "nodejs_toolchain"
}

@test "is_section_required returns false for unknown section" {
    ! is_section_required "nonexistent_section"
}

@test "get_section_title returns correct title for header" {
    local title
    title=$(get_section_title "header")

    [[ "$title" == "Header" ]]
}

@test "get_section_title returns empty for unknown section" {
    local title
    title=$(get_section_title "nonexistent")

    [[ -z "$title" ]]
}

@test "get_required_sections returns all required sections" {
    local required
    required=$(get_required_sections)

    [[ "$required" == *"header"* ]]
    [[ "$required" == *"rule_1_absolute"* ]]
    [[ "$required" == *"irreversible_actions"* ]]
    [[ "$required" == *"code_editing"* ]]
    [[ "$required" == *"landing_the_plane"* ]]
}

# ============================================================
# Section Content Tests
# ============================================================

@test "get_section_content returns content for header" {
    local content
    content=$(get_section_content "header" "test-project")

    [[ "$content" == *"AGENTS.md"* ]]
    [[ "$content" == *"test-project"* ]]
}

@test "get_section_content returns content for rule_1" {
    local content
    content=$(get_section_content "rule_1_absolute")

    [[ "$content" == *"RULE 1"* ]]
    [[ "$content" == *"ABSOLUTE"* ]]
    [[ "$content" == *"delete"* ]]
}

@test "get_section_content returns content for nodejs_toolchain" {
    local content
    content=$(get_section_content "nodejs_toolchain")

    [[ "$content" == *"Node"* ]]
    [[ "$content" == *"bun"* ]]
}

@test "get_section_content returns content for python_toolchain" {
    local content
    content=$(get_section_content "python_toolchain")

    [[ "$content" == *"Python"* ]]
    [[ "$content" == *"uv"* ]]
}

@test "get_section_content returns content for rust_toolchain" {
    local content
    content=$(get_section_content "rust_toolchain")

    [[ "$content" == *"Rust"* ]]
    [[ "$content" == *"cargo"* ]]
}

@test "get_section_content returns content for docker_workflow" {
    local content
    content=$(get_section_content "docker_workflow")

    [[ "$content" == *"Docker"* ]]
    [[ "$content" == *"docker-compose"* ]]
}

@test "get_section_content returns content for issue_tracking" {
    local content
    content=$(get_section_content "issue_tracking")

    [[ "$content" == *"br"* ]]
    [[ "$content" == *"beads"* ]]
}

@test "get_section_content returns empty for unknown section" {
    local content
    content=$(get_section_content "nonexistent")

    [[ -z "$content" ]]
}

# ============================================================
# Tech Stack Section Mapping Tests
# ============================================================

@test "get_sections_for_tech_stack includes required sections" {
    local sections
    sections=$(get_sections_for_tech_stack)

    [[ "$sections" == *"header"* ]]
    [[ "$sections" == *"rule_1_absolute"* ]]
    [[ "$sections" == *"code_editing"* ]]
}

@test "get_sections_for_tech_stack includes nodejs for nodejs stack" {
    local sections
    sections=$(get_sections_for_tech_stack "nodejs")

    [[ "$sections" == *"nodejs_toolchain"* ]]
}

@test "get_sections_for_tech_stack includes nodejs for typescript stack" {
    local sections
    sections=$(get_sections_for_tech_stack "typescript")

    [[ "$sections" == *"nodejs_toolchain"* ]]
}

@test "get_sections_for_tech_stack includes nodejs for nextjs stack" {
    local sections
    sections=$(get_sections_for_tech_stack "nextjs")

    [[ "$sections" == *"nodejs_toolchain"* ]]
}

@test "get_sections_for_tech_stack includes python for python stack" {
    local sections
    sections=$(get_sections_for_tech_stack "python")

    [[ "$sections" == *"python_toolchain"* ]]
}

@test "get_sections_for_tech_stack includes python for python-legacy stack" {
    local sections
    sections=$(get_sections_for_tech_stack "python-legacy")

    [[ "$sections" == *"python_toolchain"* ]]
}

@test "get_sections_for_tech_stack includes docker for docker stack" {
    local sections
    sections=$(get_sections_for_tech_stack "docker")

    [[ "$sections" == *"docker_workflow"* ]]
}

@test "get_sections_for_tech_stack includes docker for docker-compose stack" {
    local sections
    sections=$(get_sections_for_tech_stack "docker-compose")

    [[ "$sections" == *"docker_workflow"* ]]
}

@test "get_sections_for_tech_stack handles multiple techs" {
    local sections
    sections=$(get_sections_for_tech_stack "nodejs" "python" "docker")

    [[ "$sections" == *"nodejs_toolchain"* ]]
    [[ "$sections" == *"python_toolchain"* ]]
    [[ "$sections" == *"docker_workflow"* ]]
}

@test "get_sections_for_tech_stack deduplicates nodejs from multiple JS techs" {
    local sections
    sections=$(get_sections_for_tech_stack "nodejs" "typescript" "nextjs")

    # Count occurrences of nodejs_toolchain - should be 1
    local count
    count=$(echo "$sections" | grep -o "nodejs_toolchain" | wc -l)
    [[ "$count" -eq 1 ]]
}

# ============================================================
# Generator Tests
# ============================================================

@test "generate_agents_md produces valid content" {
    local content
    content=$(generate_agents_md "test-project")

    [[ -n "$content" ]]
    [[ "$content" == *"AGENTS.md"* ]]
    [[ "$content" == *"test-project"* ]]
}

@test "generate_agents_md includes required sections" {
    local content
    content=$(generate_agents_md "test-project")

    [[ "$content" == *"RULE 1"* ]]
    [[ "$content" == *"IRREVERSIBLE"* ]]
    [[ "$content" == *"Code Editing"* ]]
    [[ "$content" == *"Landing the Plane"* ]]
}

@test "generate_agents_md includes nodejs for nodejs stack" {
    local content
    content=$(generate_agents_md "test-project" "nodejs")

    [[ "$content" == *"Node / JS Toolchain"* ]]
    [[ "$content" == *"bun"* ]]
}

@test "generate_agents_md includes python for python stack" {
    local content
    content=$(generate_agents_md "test-project" "python")

    [[ "$content" == *"Python Toolchain"* ]]
    [[ "$content" == *"uv"* ]]
}

@test "generate_agents_md includes multiple toolchains" {
    local content
    content=$(generate_agents_md "test-project" "nodejs" "python" "docker")

    [[ "$content" == *"Node / JS Toolchain"* ]]
    [[ "$content" == *"Python Toolchain"* ]]
    [[ "$content" == *"Docker Workflow"* ]]
}

@test "generate_agents_md includes br section when enabled" {
    export AGENTS_ENABLE_BR=true
    local content
    content=$(generate_agents_md "test-project")

    [[ "$content" == *"Issue Tracking with br"* ]]
    [[ "$content" == *"beads"* ]]
}

@test "generate_agents_md excludes br section when disabled" {
    export AGENTS_ENABLE_BR=false
    local content
    content=$(generate_agents_md "test-project")

    [[ "$content" != *"Issue Tracking with br"* ]]
}

@test "generate_agents_md includes console section when enabled" {
    export AGENTS_ENABLE_CONSOLE=true
    local content
    content=$(generate_agents_md "test-project")

    [[ "$content" == *"Console Output"* ]]
}

# ============================================================
# File Generation Tests
# ============================================================

@test "generate_agents_md_file creates file" {
    local project_dir="$TEST_DIR/test-project"
    mkdir -p "$project_dir"

    run generate_agents_md_file "$project_dir" "test-project"
    assert_success

    [[ -f "$project_dir/AGENTS.md" ]]
}

@test "generate_agents_md_file includes correct content" {
    local project_dir="$TEST_DIR/test-project2"
    mkdir -p "$project_dir"

    generate_agents_md_file "$project_dir" "test-project2" "nodejs"

    local content
    content=$(cat "$project_dir/AGENTS.md")

    [[ "$content" == *"test-project2"* ]]
    [[ "$content" == *"Node / JS Toolchain"* ]]
}

# ============================================================
# Validation Tests
# ============================================================

@test "validate_agents_md passes for valid content" {
    local content
    content=$(generate_agents_md "test-project")

    run validate_agents_md "$content"
    assert_success
}

@test "validate_agents_md fails for empty content" {
    run validate_agents_md ""
    assert_failure

    [[ "$output" == *"Content too short"* ]]
}

@test "validate_agents_md fails for missing RULE 1" {
    run validate_agents_md "# AGENTS.md

Some content here without the safety rule.

## IRREVERSIBLE GIT & FILESYSTEM ACTIONS

Content about actions.

## Code Editing Discipline

More content about editing.

## Landing the Plane

Even more content here to make it long enough for validation purposes and to reach the minimum character count.

---

---

---
"
    assert_failure
    [[ "$output" == *"RULE 1"* ]]
}

@test "validate_agents_md fails for too few sections" {
    run validate_agents_md "# AGENTS.md

Short content.
"
    assert_failure
}

@test "validate_agents_md_file passes for generated file" {
    local project_dir="$TEST_DIR/validate-test"
    mkdir -p "$project_dir"
    generate_agents_md_file "$project_dir" "validate-test"

    run validate_agents_md_file "$project_dir/AGENTS.md"
    assert_success
}

@test "validate_agents_md_file fails for nonexistent file" {
    run validate_agents_md_file "$TEST_DIR/nonexistent/AGENTS.md"
    assert_failure

    [[ "$output" == *"not found"* ]]
}

# ============================================================
# Preview Tests
# ============================================================

@test "preview_agents_md shows project name" {
    local preview
    preview=$(preview_agents_md "my-project")

    [[ "$preview" == *"my-project"* ]]
}

@test "preview_agents_md shows tech stack" {
    local preview
    preview=$(preview_agents_md "my-project" "nodejs" "docker")

    [[ "$preview" == *"nodejs"* ]]
    [[ "$preview" == *"docker"* ]]
}

@test "preview_agents_md lists sections to include" {
    local preview
    preview=$(preview_agents_md "my-project" "python")

    [[ "$preview" == *"Python Toolchain"* ]]
    [[ "$preview" == *"Sections to include"* ]]
}

# ============================================================
# List Available Sections Test
# ============================================================

@test "list_available_sections shows all sections" {
    local output
    output=$(list_available_sections)

    [[ "$output" == *"header"* ]]
    [[ "$output" == *"nodejs_toolchain"* ]]
    [[ "$output" == *"python_toolchain"* ]]
    [[ "$output" == *"required"* ]]
    [[ "$output" == *"optional"* ]]
}

# ============================================================
# Edge Cases
# ============================================================

@test "generate_agents_md handles empty tech stack" {
    local content
    content=$(generate_agents_md "empty-project")

    # Should still have required sections
    [[ "$content" == *"RULE 1"* ]]
    [[ "$content" == *"IRREVERSIBLE"* ]]

    # Should not have optional toolchain sections
    [[ "$content" != *"Node / JS Toolchain"* ]]
    [[ "$content" != *"Python Toolchain"* ]]
}

@test "generate_agents_md handles unknown tech gracefully" {
    local content
    content=$(generate_agents_md "test-project" "unknown_tech_xyz")

    # Should still produce valid output with required sections
    [[ "$content" == *"RULE 1"* ]]
}

@test "generate_agents_md preserves section order" {
    local content
    content=$(generate_agents_md "test-project" "nodejs" "python")

    # header should come before rule_1
    local header_pos rule1_pos
    header_pos=$(echo "$content" | grep -n "AGENTS.md" | head -1 | cut -d: -f1)
    rule1_pos=$(echo "$content" | grep -n "RULE 1" | head -1 | cut -d: -f1)

    [[ "$header_pos" -lt "$rule1_pos" ]]
}
