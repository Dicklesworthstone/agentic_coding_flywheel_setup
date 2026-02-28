#!/usr/bin/env bash
# ============================================================
# ACFS newproj TUI Wizard - Project Name Screen
# Collects and validates the project name
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_SCREEN_PROJECT_NAME_LOADED:-}" ]]; then
    return 0
fi
_ACFS_SCREEN_PROJECT_NAME_LOADED=1

# ============================================================
# Screen: Project Name
# ============================================================

# Screen metadata
SCREEN_PROJECT_NAME_ID="project_name"
SCREEN_PROJECT_NAME_TITLE="Project Name"
SCREEN_PROJECT_NAME_STEP=2
SCREEN_PROJECT_NAME_NEXT="directory"
SCREEN_PROJECT_NAME_PREV="welcome"

# Render the project name screen
render_project_name_screen() {
    local current_value="${1:-}"

    render_screen_header "Choose a Project Name" "$SCREEN_PROJECT_NAME_STEP" 9

    echo "Enter a name for your new project."
    echo ""
    echo -e "${TUI_GRAY}Requirements:${TUI_NC}"

    if [[ "$TERM_HAS_UNICODE" == "true" ]]; then
        echo -e "  ${BOX_BULLET} Must start with a letter"
        echo -e "  ${BOX_BULLET} Only letters, numbers, hyphens, and underscores"
        echo -e "  ${BOX_BULLET} At least 2 characters"
        echo -e "  ${BOX_BULLET} Cannot be a reserved name (node_modules, .git, etc.)"
    else
        echo "  * Must start with a letter"
        echo "  * Only letters, numbers, hyphens, and underscores"
        echo "  * At least 2 characters"
        echo "  * Cannot be a reserved name (node_modules, .git, etc.)"
    fi

    echo ""

    # Show current value if editing
    if [[ -n "$current_value" ]]; then
        echo -e "Current: ${TUI_PRIMARY}$current_value${TUI_NC}"
        echo ""
    fi
}

# Get suggested project name from current directory
get_default_project_name() {
    local dirname
    dirname=$(basename "$(pwd)")

    # Validate it as a project name
    if validate_project_name "$dirname" &>/dev/null; then
        echo "$dirname"
    else
        echo "my-project"
    fi
}

# Handle input for project name screen
# Returns: next screen name, or empty to go back
handle_project_name_input() {
    local default_name
    default_name=$(get_default_project_name)

    local current_name
    current_name=$(state_get "project_name")
    [[ -z "$current_name" ]] && current_name="$default_name"

    local name=""
    local valid=false

    while [[ "$valid" != "true" ]]; do
        # Use TUI input
        if [[ "$GUM_AVAILABLE" == "true" && "$TERM_HAS_COLOR" == "true" ]]; then
            name=$(gum input \
                --value "$current_name" \
                --placeholder "my-project" \
                --prompt "Project name: " \
                --prompt.foreground "#89b4fa" \
                --cursor.foreground "#cba6f7" 2>/dev/null) || {
                # User cancelled (Ctrl+C in gum)
                echo ""
                return 1
            }
        else
            echo -n "Project name [$current_name]: "
            # Read from /dev/tty explicitly to avoid stdin conflicts
            # from signal handlers or subshell capture (issue #153)
            read -r name < /dev/tty || true
            [[ -z "$name" ]] && name="$current_name"
        fi

        log_input "project_name" "$name"

        # Handle escape/back
        if [[ -z "$name" ]]; then
            echo ""
            return 1
        fi

        # Validate
        local error
        error=$(validate_project_name "$name" 2>&1)
        if [[ $? -eq 0 ]]; then
            valid=true
            state_set "project_name" "$name"
            log_validation "project_name" "$name" "PASS"
        else
            echo -e "${TUI_ERROR}${BOX_CROSS} $error${TUI_NC}"
            echo ""
            log_validation "project_name" "$name" "FAIL" "$error"
            current_name="$name"
        fi
    done

    echo "$SCREEN_PROJECT_NAME_NEXT"
    return 0
}

# Run the project name screen
# Returns: 0 to continue, 1 to go back, 2 to exit
run_project_name_screen() {
    log_screen "ENTER" "project_name"

    local current_name
    current_name=$(state_get "project_name")

    render_project_name_screen "$current_name"

    local next
    next=$(handle_project_name_input)
    local result=$?

    if [[ $result -eq 0 ]] && [[ -n "$next" ]]; then
        navigate_forward "$next"
        return 0
    else
        # Go back
        if navigate_back; then
            return 0
        else
            log_screen "EXIT" "project_name" "no_back_history"
            return 1
        fi
    fi
}
