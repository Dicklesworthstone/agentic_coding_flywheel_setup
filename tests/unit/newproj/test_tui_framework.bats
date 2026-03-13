#!/usr/bin/env bats
# ============================================================
# Unit Tests for newproj_tui.sh - Core TUI Framework
# ============================================================

load '../test_helper'

setup() {
    common_setup

    # Create temp directory for testing
    TEST_DIR=$(create_temp_dir)
    export TEST_DIR

    # Set up logging
    export ACFS_LOG_DIR="$TEST_DIR"
    export ACFS_LOG_LEVEL=0

    # Source dependencies first
    source_lib "newproj_logging"
    init_logging

    # Source the TUI module
    source_lib "newproj_tui"
}

teardown() {
    common_teardown
}

# ============================================================
# Terminal Capability Tests
# ============================================================

@test "detect_terminal_capabilities sets TERM_COLS" {
    detect_terminal_capabilities

    [[ -n "$TERM_COLS" ]]
    [[ "$TERM_COLS" -gt 0 ]]
}

@test "detect_terminal_capabilities sets TERM_LINES" {
    detect_terminal_capabilities

    [[ -n "$TERM_LINES" ]]
    [[ "$TERM_LINES" -gt 0 ]]
}

@test "detect_terminal_capabilities checks GUM_AVAILABLE" {
    detect_terminal_capabilities

    # GUM_AVAILABLE should be set (true or false)
    [[ "$GUM_AVAILABLE" == "true" || "$GUM_AVAILABLE" == "false" ]]
}

@test "TERM=dumb disables color support" {
    export TERM=dumb
    detect_terminal_capabilities

    [[ "$TERM_HAS_COLOR" == "false" ]]
}

# ============================================================
# Color Setup Tests
# ============================================================

@test "setup_colors defines TUI_NC" {
    TERM_HAS_COLOR=true
    setup_colors

    [[ -n "$TUI_NC" ]]
}

@test "setup_colors sets empty strings when no color" {
    TERM_HAS_COLOR=false
    setup_colors

    [[ -z "$TUI_RED" ]]
    [[ -z "$TUI_GREEN" ]]
    [[ -z "$TUI_NC" ]]
}

# ============================================================
# Box Character Tests
# ============================================================

@test "setup_box_chars sets unicode chars when supported" {
    TERM_HAS_UNICODE=true
    setup_box_chars

    [[ "$BOX_TL" == "╭" ]]
    [[ "$BOX_CHECK" == "✓" ]]
}

@test "setup_box_chars sets ASCII chars when no unicode" {
    TERM_HAS_UNICODE=false
    setup_box_chars

    [[ "$BOX_TL" == "+" ]]
    [[ "$BOX_CHECK" == "*" ]]
}

# ============================================================
# State Management Tests
# ============================================================

@test "state_set updates WIZARD_STATE correctly" {
    state_set "project_name" "my-test-project"

    [[ "${WIZARD_STATE[project_name]}" == "my-test-project" ]]
}

@test "state_get returns correct value" {
    WIZARD_STATE[project_name]="test-value"

    local result
    result=$(state_get "project_name")

    [[ "$result" == "test-value" ]]
}

@test "state_get returns empty for missing key" {
    local result
    result=$(state_get "nonexistent_key")

    [[ -z "$result" ]]
}

@test "state_has returns true for set values" {
    state_set "project_name" "test"

    state_has "project_name"
}

@test "state_has returns false for empty values" {
    state_set "project_name" ""

    ! state_has "project_name"
}

@test "state_reset clears all state" {
    state_set "project_name" "test"
    state_set "project_dir" "/tmp/test"

    state_reset

    [[ -z "$(state_get 'project_name')" ]]
}

@test "state changes are logged" {
    state_set "project_name" "logged-value"

    grep -q "STATE" "$ACFS_SESSION_LOG"
    grep -q "project_name" "$ACFS_SESSION_LOG"
}

# ============================================================
# Navigation Tests
# ============================================================

@test "push_screen adds to history stack" {
    SCREEN_HISTORY=()
    CURRENT_SCREEN=""

    push_screen "welcome"
    push_screen "project_name"

    [[ "${#SCREEN_HISTORY[@]}" -eq 1 ]]
    [[ "${SCREEN_HISTORY[0]}" == "welcome" ]]
    [[ "$CURRENT_SCREEN" == "project_name" ]]
}

@test "pop_screen returns previous screen" {
    SCREEN_HISTORY=("welcome" "project_name")
    CURRENT_SCREEN="directory"

    # Note: pop_screen modifies CURRENT_SCREEN and returns the screen name
    # Since we run in subshell to capture output, we need to test separately
    local result
    result=$(pop_screen)

    # The returned value should be the popped screen
    [[ "$result" == "project_name" ]]

    # Test the state mutation separately
    SCREEN_HISTORY=("welcome" "project_name")
    CURRENT_SCREEN="directory"
    pop_screen >/dev/null

    [[ "$CURRENT_SCREEN" == "project_name" ]]
}

@test "pop_screen returns empty when stack empty" {
    SCREEN_HISTORY=()
    CURRENT_SCREEN="welcome"

    local result
    result=$(pop_screen)

    [[ -z "$result" ]]
}

@test "get_history_depth returns correct count" {
    SCREEN_HISTORY=("a" "b" "c")

    local depth
    depth=$(get_history_depth)

    [[ "$depth" -eq 3 ]]
}

@test "navigate_forward updates current screen" {
    SCREEN_HISTORY=()
    CURRENT_SCREEN="welcome"

    navigate_forward "project_name"

    [[ "$CURRENT_SCREEN" == "project_name" ]]
    [[ "${#SCREEN_HISTORY[@]}" -eq 1 ]]
}

@test "navigate_back returns to previous screen" {
    SCREEN_HISTORY=("welcome")
    CURRENT_SCREEN="project_name"

    navigate_back

    [[ "$CURRENT_SCREEN" == "welcome" ]]
    [[ "${#SCREEN_HISTORY[@]}" -eq 0 ]]
}

@test "navigate_back fails when no history" {
    SCREEN_HISTORY=()
    CURRENT_SCREEN="welcome"

    ! navigate_back
}

# ============================================================
# Drawing Utility Tests
# ============================================================

@test "draw_line renders correct width" {
    TERM_HAS_UNICODE=true
    setup_box_chars

    local line
    line=$(draw_line 10)

    [[ ${#line} -eq 10 ]]
}

@test "draw_line uses specified character" {
    local line
    line=$(draw_line 5 "=")

    [[ "$line" == "=====" ]]
}

@test "draw_box renders correct dimensions" {
    TERM_HAS_UNICODE=false
    setup_box_chars

    local box
    box=$(draw_box "" "test" 20)

    # Should have top, content, bottom lines
    local line_count
    line_count=$(echo "$box" | wc -l)
    [[ "$line_count" -eq 3 ]]
}

@test "draw_box handles minimum width" {
    TERM_HAS_UNICODE=false
    setup_box_chars

    local box
    box=$(draw_box "" "test" 5)  # Below minimum

    # Should still render (width forced to 20 minimum)
    [[ -n "$box" ]]
}

@test "render_progress shows correct percentage" {
    local progress
    progress=$(render_progress 5 10 10)

    [[ "$progress" == *"50%"* ]]
}

@test "render_progress handles 100%" {
    local progress
    progress=$(render_progress 10 10 10)

    [[ "$progress" == *"100%"* ]]
}

@test "render_progress handles 0%" {
    local progress
    progress=$(render_progress 0 10 10)

    [[ "$progress" == *"0%"* ]]
}

@test "run_screen_handler_capture preserves state mutations from handlers" {
    test_capture_handler() {
        state_set "project_name" "captured-project"
        echo "next_screen"
    }

    run_screen_handler_capture test_capture_handler

    [[ "$SCREEN_HANDLER_STATUS" -eq 0 ]]
    [[ "$SCREEN_HANDLER_OUTPUT" == "next_screen" ]]
    [[ "$(state_get "project_name")" == "captured-project" ]]
}

# ============================================================
# Input Handling Tests (limited without actual terminal)
# ============================================================

@test "read_yes_no function exists" {
    declare -f read_yes_no
}

@test "read_text_input function exists" {
    declare -f read_text_input
}

@test "read_selection function exists" {
    declare -f read_selection
}

@test "read_checkbox function exists" {
    declare -f read_checkbox
}

# ============================================================
# Screen Framework Tests
# ============================================================

@test "render_screen_header clears and shows title" {
    TERM_HAS_COLOR=false
    setup_colors

    local output
    output=$(render_screen_header "Test Title" 1 5 2>&1)

    [[ "$output" == *"Test Title"* ]]
    [[ "$output" == *"Wizard"* ]]
}

@test "render_screen_footer shows navigation hints" {
    TERM_HAS_COLOR=false
    setup_colors

    local output
    output=$(render_screen_footer true true)

    [[ "$output" == *"Cancel"* ]]
}

# ============================================================
# Initialization Tests
# ============================================================

@test "tui_init runs without error in test environment" {
    # This may fail pre-flight checks in non-TTY environment
    # but should not crash
    run tui_init

    # Should either pass or fail gracefully
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "tui_cleanup runs without error" {
    run tui_cleanup
    assert_success
}

# ============================================================
# Spinner Tests
# ============================================================

@test "spinner function exists" {
    declare -f spinner
}

@test "stop_spinner function exists" {
    declare -f stop_spinner
}

@test "SPINNER_FRAMES is defined" {
    TERM_HAS_UNICODE=true
    setup_box_chars

    [[ ${#SPINNER_FRAMES[@]} -gt 0 ]]
}
