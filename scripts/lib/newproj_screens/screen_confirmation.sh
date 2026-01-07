#!/usr/bin/env bash
# ============================================================
# ACFS newproj TUI Wizard - Confirmation Screen
# Shows summary and confirms before project creation
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_SCREEN_CONFIRMATION_LOADED:-}" ]]; then
    return 0
fi
_ACFS_SCREEN_CONFIRMATION_LOADED=1

# ============================================================
# Screen: Confirmation
# ============================================================

# Screen metadata
SCREEN_CONFIRMATION_ID="confirmation"
SCREEN_CONFIRMATION_TITLE="Confirmation"
SCREEN_CONFIRMATION_STEP=7
SCREEN_CONFIRMATION_NEXT="progress"
SCREEN_CONFIRMATION_PREV="agents_preview"

# Get list of files to be created
get_files_to_create() {
    local project_dir
    project_dir=$(state_get "project_dir")

    local files=()

    # Always created
    files+=("$project_dir/")
    files+=("$project_dir/.git/")

    # Based on features
    if [[ "$(state_get "enable_agents")" == "true" ]]; then
        files+=("$project_dir/AGENTS.md")
    fi

    if [[ "$(state_get "enable_bd")" == "true" ]]; then
        files+=("$project_dir/.beads/")
        files+=("$project_dir/.beads/beads.db")
    fi

    if [[ "$(state_get "enable_claude")" == "true" ]]; then
        files+=("$project_dir/.claude/")
        files+=("$project_dir/.claude/settings.local.json")
    fi

    if [[ "$(state_get "enable_ubsignore")" == "true" ]]; then
        files+=("$project_dir/.ubsignore")
    fi

    # Always create a basic README and .gitignore
    files+=("$project_dir/README.md")
    files+=("$project_dir/.gitignore")

    printf '%s\n' "${files[@]}"
}

# Render file tree
render_file_tree() {
    local project_dir
    project_dir=$(state_get "project_dir")
    local project_name
    project_name=$(basename "$project_dir")

    local files
    mapfile -t files < <(get_files_to_create)

    echo -e "${TUI_PRIMARY}$project_name/${TUI_NC}"

    for file in "${files[@]}"; do
        # Skip the project dir itself
        [[ "$file" == "$project_dir/" ]] && continue

        # Get relative path
        local rel="${file#$project_dir/}"

        # Calculate depth - strip trailing slash first so directories
        # don't appear deeper than their contents
        local clean_rel="${rel%/}"
        local depth=$(echo "$clean_rel" | tr -cd '/' | wc -c)

        # Build prefix - all items need at least "├── " for tree structure
        local prefix=""
        if [[ "$TERM_HAS_UNICODE" == "true" ]]; then
            # Add indentation for nested items
            for ((i = 0; i < depth; i++)); do
                prefix+="│   "
            done
            prefix+="├── "
        else
            for ((i = 0; i < depth; i++)); do
                prefix+="|   "
            done
            prefix+="|-- "
        fi

        # Get filename
        local name
        name=$(basename "$rel")
        [[ "$rel" == */ ]] && name="$name/"

        # Color directories differently
        if [[ "$rel" == */ ]]; then
            echo -e "${prefix}${TUI_PRIMARY}${name}${TUI_NC}"
        else
            echo -e "${prefix}${name}"
        fi
    done
}

# Render the confirmation screen
render_confirmation_screen() {
    render_screen_header "Review & Confirm" "$SCREEN_CONFIRMATION_STEP" 9

    echo "Please review your selections before creating the project."
    echo ""

    # Summary box
    local project_name
    project_name=$(state_get "project_name")
    local project_dir
    project_dir=$(state_get "project_dir")
    local tech_stack
    tech_stack=$(state_get "tech_stack")

    echo -e "${TUI_BOLD}Project Summary${TUI_NC}"
    draw_line 50

    echo -e "  Name:       ${TUI_PRIMARY}$project_name${TUI_NC}"
    echo -e "  Location:   ${TUI_PRIMARY}$project_dir${TUI_NC}"

    if [[ -n "$tech_stack" ]]; then
        # Get display names for tech
        local display_tech=""
        for tech in $tech_stack; do
            local name
            name=$(get_tech_option_display "$tech" 2>/dev/null || echo "$tech")
            display_tech+="$name, "
        done
        display_tech="${display_tech%, }"
        echo -e "  Tech:       ${TUI_CYAN}$display_tech${TUI_NC}"
    else
        echo -e "  Tech:       ${TUI_GRAY}None specified${TUI_NC}"
    fi

    echo ""

    # Features
    echo -e "${TUI_BOLD}Features${TUI_NC}"
    draw_line 50

    local features=("bd:Beads tracking" "claude:Claude Code settings" "agents:AGENTS.md" "ubsignore:UBS ignore")
    for feat in "${features[@]}"; do
        local id="${feat%%:*}"
        local name="${feat#*:}"
        local key="enable_$id"
        local enabled
        enabled=$(state_get "$key")

        if [[ "$enabled" == "true" ]]; then
            echo -e "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} $name"
        else
            echo -e "  ${TUI_GRAY}${BOX_CROSS} $name${TUI_NC}"
        fi
    done

    echo ""

    # File tree
    echo -e "${TUI_BOLD}Files to Create${TUI_NC}"
    draw_line 50
    render_file_tree

    echo ""
    draw_line 50

    echo ""
    echo "Options:"
    echo -e "  [Enter/c]   ${TUI_SUCCESS}Create project${TUI_NC}"
    echo "  [e]         Edit selections (go back)"
    echo "  [q/Esc]     Cancel"
}

# Handle input for confirmation screen
handle_confirmation_input() {
    while true; do
        render_confirmation_screen

        local key
        read -rsn1 key

        case "$key" in
            ''|'c'|'C'|'y'|'Y')
                # Confirm - proceed to creation
                log_input "confirmation" "create"
                echo "$SCREEN_CONFIRMATION_NEXT"
                return 0
                ;;
            'e'|'E')
                # Edit - go back to project name
                log_input "confirmation" "edit"
                # Clear history and go back to beginning
                SCREEN_HISTORY=("welcome")
                CURRENT_SCREEN="project_name"
                echo "project_name"
                return 0
                ;;
            'q'|'Q')
                # Quit
                log_input "confirmation" "quit"
                echo ""
                return 2  # Special code for exit
                ;;
            $'\e')
                # Escape
                read -rsn2 -t 0.1 escape_seq || true
                if [[ -z "$escape_seq" ]]; then
                    log_input "confirmation" "cancel"
                    echo ""
                    return 2
                fi
                ;;
            'b'|'B')
                # Back
                log_input "confirmation" "back"
                return 1
                ;;
        esac
    done
}

# Run the confirmation screen
run_confirmation_screen() {
    log_screen "ENTER" "confirmation"

    local next
    next=$(handle_confirmation_input)
    local result=$?

    case $result in
        0)
            if [[ -n "$next" ]]; then
                navigate_forward "$next"
                return 0
            fi
            ;;
        1)
            navigate_back
            return 0
            ;;
        2)
            # User wants to exit
            return 1
            ;;
    esac
}
