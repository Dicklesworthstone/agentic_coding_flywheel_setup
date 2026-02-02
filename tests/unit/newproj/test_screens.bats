#!/usr/bin/env bats
# ============================================================
# Unit Tests for newproj_screens - Wizard Screen Modules
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

    # Create screens directory structure for testing
    export NEWPROJ_LIB_DIR="$ACFS_LIB_DIR"

    # Source dependencies
    source_lib "newproj_logging"
    init_logging

    # Mock terminal capabilities for testing
    export TERM_HAS_COLOR=false
    export TERM_HAS_UNICODE=false
    export GUM_AVAILABLE=false
    export TERM_COLS=80
    export TERM_LINES=24
}

teardown() {
    common_teardown
}

# ============================================================
# Screen Manager Tests
# ============================================================

@test "newproj_screens.sh sources without error" {
    run source_lib "newproj_screens"
    assert_success
}

@test "load_screens loads all screen files" {
    source_lib "newproj_screens"

    run load_screens
    assert_success
}

@test "SCREEN_FLOW contains all screens" {
    source_lib "newproj_screens"

    [[ ${#SCREEN_FLOW[@]} -eq 9 ]]
    [[ "${SCREEN_FLOW[0]}" == "welcome" ]]
    [[ "${SCREEN_FLOW[8]}" == "success" ]]
}

@test "SCREEN_RUNNERS maps to valid functions" {
    source_lib "newproj_screens"
    load_screens

    for screen_id in "${!SCREEN_RUNNERS[@]}"; do
        local runner="${SCREEN_RUNNERS[$screen_id]}"
        declare -f "$runner" &>/dev/null
    done
}

@test "get_screen_runner returns correct function" {
    source_lib "newproj_screens"

    local runner
    runner=$(get_screen_runner "welcome")
    [[ "$runner" == "run_welcome_screen" ]]

    runner=$(get_screen_runner "project_name")
    [[ "$runner" == "run_project_name_screen" ]]
}

@test "get_next_screen returns correct screen" {
    source_lib "newproj_screens"

    local next
    next=$(get_next_screen "welcome")
    [[ "$next" == "project_name" ]]

    next=$(get_next_screen "project_name")
    [[ "$next" == "directory" ]]

    next=$(get_next_screen "progress")
    [[ "$next" == "success" ]]
}

@test "get_previous_screen returns correct screen" {
    source_lib "newproj_screens"

    local prev
    prev=$(get_previous_screen "project_name")
    [[ "$prev" == "welcome" ]]

    prev=$(get_previous_screen "success")
    [[ "$prev" == "progress" ]]
}

@test "get_next_screen returns empty for last screen" {
    source_lib "newproj_screens"

    local next
    next=$(get_next_screen "success") || true
    [[ -z "$next" ]]
}

# ============================================================
# Welcome Screen Tests
# ============================================================

@test "welcome screen module loads" {
    source_lib "newproj_tui"
    source_lib "newproj_errors"
    setup_colors
    setup_box_chars

    source "$ACFS_LIB_DIR/newproj_screens/screen_welcome.sh"

    [[ "$SCREEN_WELCOME_ID" == "welcome" ]]
    [[ "$SCREEN_WELCOME_NEXT" == "project_name" ]]
}

@test "welcome screen metadata is correct" {
    source_lib "newproj_screens"
    load_screens

    [[ "$SCREEN_WELCOME_STEP" -eq 1 ]]
    [[ "$SCREEN_WELCOME_TITLE" == "Welcome" ]]
}

@test "render_welcome_screen produces output" {
    source_lib "newproj_screens"
    load_screens

    local output
    output=$(render_welcome_screen 2>&1 | head -20)

    [[ "$output" == *"ACFS"* ]]
    [[ "$output" == *"Welcome"* ]]
}

# ============================================================
# Project Name Screen Tests
# ============================================================

@test "project name screen module loads" {
    source_lib "newproj_screens"
    load_screens

    [[ "$SCREEN_PROJECT_NAME_ID" == "project_name" ]]
    [[ "$SCREEN_PROJECT_NAME_NEXT" == "directory" ]]
}

@test "get_default_project_name returns valid name" {
    source_lib "newproj_screens"
    load_screens

    local default_name
    default_name=$(get_default_project_name)

    # Should return something
    [[ -n "$default_name" ]]
}

@test "render_project_name_screen produces output" {
    source_lib "newproj_screens"
    load_screens

    local output
    output=$(render_project_name_screen "my-project" 2>&1 | head -20)

    [[ "$output" == *"Project Name"* ]]
    [[ "$output" == *"my-project"* ]]
}

# ============================================================
# Directory Screen Tests
# ============================================================

@test "directory screen module loads" {
    source_lib "newproj_screens"
    load_screens

    [[ "$SCREEN_DIRECTORY_ID" == "directory" ]]
    [[ "$SCREEN_DIRECTORY_NEXT" == "tech_stack" ]]
}

@test "get_default_projects_dir returns valid path" {
    source_lib "newproj_screens"
    load_screens

    local default_dir
    default_dir=$(get_default_projects_dir)

    # Should return a valid directory
    [[ -d "$default_dir" ]] || [[ "$default_dir" == "$HOME" ]]
}

@test "check_directory_status returns OK for new path" {
    source_lib "newproj_screens"
    load_screens

    local new_path="$TEST_DIR/new-project-$(date +%s)"

    local status
    status=$(check_directory_status "$new_path")

    [[ "$status" == "OK:"* ]]
}

@test "check_directory_status returns ERROR for existing non-empty dir" {
    source_lib "newproj_screens"
    load_screens

    local existing_dir="$TEST_DIR/existing"
    mkdir -p "$existing_dir"
    echo "test" > "$existing_dir/file.txt"

    local status
    status=$(check_directory_status "$existing_dir") || true

    [[ "$status" == "ERROR:"* ]]
}

@test "check_directory_status returns WARNING for empty dir" {
    source_lib "newproj_screens"
    load_screens

    local empty_dir="$TEST_DIR/empty"
    mkdir -p "$empty_dir"

    local status
    status=$(check_directory_status "$empty_dir") || true

    [[ "$status" == "WARNING:"* ]]
}

@test "check_directory_status expands tilde" {
    source_lib "newproj_screens"
    load_screens

    local status
    status=$(check_directory_status "~/nonexistent-project-test-123")

    # Should have resolved the tilde
    [[ "$status" != *"~"* ]] || [[ "$status" == "ERROR:"* ]]
}

# ============================================================
# Tech Stack Screen Tests
# ============================================================

@test "tech stack screen module loads" {
    source_lib "newproj_screens"
    load_screens

    [[ "$SCREEN_TECH_STACK_ID" == "tech_stack" ]]
    [[ ${#TECH_STACK_OPTIONS[@]} -gt 0 ]]
}

@test "TECH_STACK_OPTIONS contains expected options" {
    source_lib "newproj_screens"
    load_screens

    local found_nodejs=false
    local found_python=false

    for opt in "${TECH_STACK_OPTIONS[@]}"; do
        [[ "$opt" == "nodejs:"* ]] && found_nodejs=true
        [[ "$opt" == "python:"* ]] && found_python=true
    done

    [[ "$found_nodejs" == "true" ]]
    [[ "$found_python" == "true" ]]
}

@test "get_tech_option_display returns correct name" {
    source_lib "newproj_screens"
    load_screens

    local display
    display=$(get_tech_option_display "nodejs")
    [[ "$display" == *"Node.js"* ]]

    display=$(get_tech_option_display "python")
    [[ "$display" == *"Python"* ]]
}

@test "toggle_option adds new option" {
    source_lib "newproj_screens"
    load_screens

    local result
    result=$(toggle_option "python" "nodejs")
    [[ "$result" == *"python"* ]]
    [[ "$result" == *"nodejs"* ]]
}

@test "toggle_option removes existing option" {
    source_lib "newproj_screens"
    load_screens

    local result
    result=$(toggle_option "nodejs" "nodejs python")
    [[ "$result" != *"nodejs"* ]]
    [[ "$result" == *"python"* ]]
}

# ============================================================
# Features Screen Tests
# ============================================================

@test "features screen module loads" {
    source_lib "newproj_screens"
    load_screens

    [[ "$SCREEN_FEATURES_ID" == "features" ]]
    [[ ${#FEATURE_OPTIONS[@]} -gt 0 ]]
}

@test "FEATURE_OPTIONS contains expected features" {
    source_lib "newproj_screens"
    load_screens

    local found_br=false
    local found_agents=false

    for opt in "${FEATURE_OPTIONS[@]}"; do
        [[ "$opt" == "br:"* ]] && found_br=true
        [[ "$opt" == "agents:"* ]] && found_agents=true
    done

    [[ "$found_br" == "true" ]]
    [[ "$found_agents" == "true" ]]
}

@test "get_feature_key returns correct key" {
    source_lib "newproj_screens"
    load_screens

    local key
    key=$(get_feature_key "br")
    [[ "$key" == "enable_br" ]]

    key=$(get_feature_key "agents")
    [[ "$key" == "enable_agents" ]]
}

@test "toggle_feature changes state" {
    source_lib "newproj_screens"
    load_screens

    state_set "enable_br" "true"
    toggle_feature "br"
    [[ "$(state_get "enable_br")" == "false" ]]

    toggle_feature "br"
    [[ "$(state_get "enable_br")" == "true" ]]
}

# ============================================================
# Agents Preview Screen Tests
# ============================================================

@test "agents preview screen module loads" {
    source_lib "newproj_screens"
    load_screens

    [[ "$SCREEN_AGENTS_PREVIEW_ID" == "agents_preview" ]]
}

@test "generate_preview_content produces content" {
    source_lib "newproj_screens"
    load_screens

    state_set "project_name" "test-project"
    state_set "tech_stack" "nodejs"

    local content
    content=$(generate_preview_content)

    [[ -n "$content" ]]
    [[ "$content" == *"AGENTS.md"* ]]
}

@test "get_preview_summary shows sections" {
    source_lib "newproj_screens"
    load_screens

    state_set "project_name" "test-project"
    state_set "tech_stack" "nodejs python"

    local summary
    summary=$(get_preview_summary)

    [[ "$summary" == *"Sections"* ]]
}

# ============================================================
# Confirmation Screen Tests
# ============================================================

@test "confirmation screen module loads" {
    source_lib "newproj_screens"
    load_screens

    [[ "$SCREEN_CONFIRMATION_ID" == "confirmation" ]]
}

@test "get_files_to_create returns file list" {
    source_lib "newproj_screens"
    load_screens

    state_set "project_dir" "/tmp/test-project"
    state_set "enable_agents" "true"
    state_set "enable_br" "true"

    local files
    files=$(get_files_to_create)

    [[ "$files" == *"AGENTS.md"* ]]
    [[ "$files" == *".beads"* ]]
}

@test "get_files_to_create respects disabled features" {
    source_lib "newproj_screens"
    load_screens

    state_set "project_dir" "/tmp/test-project"
    state_set "enable_agents" "false"
    state_set "enable_br" "false"

    local files
    files=$(get_files_to_create)

    [[ "$files" != *"AGENTS.md"* ]]
    [[ "$files" != *".beads"* ]]
}

# ============================================================
# Progress Screen Tests
# ============================================================

@test "progress screen module loads" {
    source_lib "newproj_screens"
    load_screens

    [[ "$SCREEN_PROGRESS_ID" == "progress" ]]
}

@test "init_creation_steps creates step list" {
    source_lib "newproj_screens"
    load_screens

    state_set "enable_agents" "true"
    state_set "enable_br" "false"

    init_creation_steps

    [[ ${#STEP_ORDER[@]} -gt 0 ]]
    [[ " ${STEP_ORDER[*]} " =~ " create_dir " ]]
    [[ " ${STEP_ORDER[*]} " =~ " init_git " ]]
    [[ " ${STEP_ORDER[*]} " =~ " create_agents " ]]
    [[ ! " ${STEP_ORDER[*]} " =~ " init_br " ]]
}

@test "get_step_name returns readable names" {
    source_lib "newproj_screens"
    load_screens

    local name
    name=$(get_step_name "create_dir")
    [[ "$name" == *"directory"* ]]

    name=$(get_step_name "init_git")
    [[ "$name" == *"Git"* ]]
}

# ============================================================
# Success Screen Tests
# ============================================================

@test "success screen module loads" {
    source_lib "newproj_screens"
    load_screens

    [[ "$SCREEN_SUCCESS_ID" == "success" ]]
    [[ "$SCREEN_SUCCESS_STEP" -eq 9 ]]
}

@test "render_success_screen produces output" {
    source_lib "newproj_screens"
    load_screens

    state_set "project_name" "test-project"
    state_set "project_dir" "/tmp/test-project"

    local output
    output=$(render_success_screen 2>&1 | head -30)

    [[ "$output" == *"SUCCESS"* ]] || [[ "$output" == *"Created"* ]]
}

# ============================================================
# State Management Integration Tests
# ============================================================

@test "screen navigation updates state correctly" {
    source_lib "newproj_screens"
    load_screens

    CURRENT_SCREEN=""
    SCREEN_HISTORY=()

    push_screen "welcome"
    [[ "$CURRENT_SCREEN" == "welcome" ]]

    navigate_forward "project_name"
    [[ "$CURRENT_SCREEN" == "project_name" ]]
    [[ ${#SCREEN_HISTORY[@]} -eq 1 ]]

    navigate_back
    [[ "$CURRENT_SCREEN" == "welcome" ]]
    [[ ${#SCREEN_HISTORY[@]} -eq 0 ]]
}

@test "state persists across screen changes" {
    source_lib "newproj_screens"
    load_screens

    state_set "project_name" "my-test"
    navigate_forward "directory"

    [[ "$(state_get "project_name")" == "my-test" ]]
}

# ============================================================
# Edge Cases
# ============================================================

@test "screens handle empty state gracefully" {
    source_lib "newproj_screens"
    load_screens

    state_reset

    # This should not crash
    local output
    output=$(render_project_name_screen "" 2>&1 | head -5)
    [[ -n "$output" ]]
}

@test "get_screen_runner returns empty for unknown screen" {
    source_lib "newproj_screens"

    local runner
    runner=$(get_screen_runner "nonexistent_screen")
    [[ -z "$runner" ]]
}
