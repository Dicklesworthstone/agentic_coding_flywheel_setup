#!/usr/bin/env bash
# ============================================================
# ACFS newproj TUI Wizard - Success Screen
# Shows success message and next steps
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_SCREEN_SUCCESS_LOADED:-}" ]]; then
    return 0
fi
_ACFS_SCREEN_SUCCESS_LOADED=1

# ============================================================
# Screen: Success
# ============================================================

# Screen metadata
SCREEN_SUCCESS_ID="success"
SCREEN_SUCCESS_TITLE="Success"
SCREEN_SUCCESS_STEP=9

# Render the success screen
render_success_screen() {
    render_screen_header "Project Created!" "$SCREEN_SUCCESS_STEP" 9

    local project_name
    project_name=$(state_get "project_name")
    local project_dir
    project_dir=$(state_get "project_dir")

    # Success banner
    if [[ "$TERM_HAS_UNICODE" == "true" ]]; then
        echo -e "${TUI_SUCCESS}"
        cat << 'EOF'
    ╔══════════════════════════════════════════════════════╗
    ║                                                      ║
    ║       ✓ ✓ ✓   PROJECT CREATED SUCCESSFULLY   ✓ ✓ ✓  ║
    ║                                                      ║
    ╚══════════════════════════════════════════════════════╝
EOF
        echo -e "${TUI_NC}"
    else
        echo ""
        echo -e "${TUI_SUCCESS}=== PROJECT CREATED SUCCESSFULLY ===${TUI_NC}"
        echo ""
    fi

    echo ""
    echo -e "Your new project ${TUI_PRIMARY}$project_name${TUI_NC} is ready!"
    echo ""

    # What was created
    echo -e "${TUI_BOLD}What was created:${TUI_NC}"
    draw_line 50

    echo -e "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} Project directory: $project_dir"
    echo -e "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} Git repository initialized"
    echo -e "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} README.md"
    echo -e "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} .gitignore"

    if [[ "$(state_get "enable_agents")" == "true" ]]; then
        echo -e "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} AGENTS.md for AI assistants"
    fi

    if [[ "$(state_get "enable_br")" == "true" ]]; then
        echo -e "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} Beads issue tracking (.beads/)"
    fi

    if [[ "$(state_get "enable_claude")" == "true" ]]; then
        echo -e "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} Claude Code settings (.claude/)"
    fi

    if [[ "$(state_get "enable_ubsignore")" == "true" ]]; then
        echo -e "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} UBS ignore patterns (.ubsignore)"
    fi

    echo ""

    # Next steps
    echo -e "${TUI_BOLD}Next steps:${TUI_NC}"
    draw_line 50
    echo ""

    echo "  1. Navigate to your project:"
    echo -e "     ${TUI_CYAN}cd $project_dir${TUI_NC}"
    echo ""

    echo "  2. Start coding with Claude Code:"
    echo -e "     ${TUI_CYAN}claude${TUI_NC}"
    echo ""

    if [[ "$(state_get "enable_br")" == "true" ]]; then
        echo "  3. Create your first task:"
        echo -e "     ${TUI_CYAN}br create \"First feature\" -t feature${TUI_NC}"
        echo ""
    fi

    echo "  For help, run:"
    echo -e "     ${TUI_CYAN}acfs help${TUI_NC}"
    echo ""

    draw_line 50
    echo ""
    echo "Options:"
    echo "  [Enter/o]   Open project in shell"
    echo "  [c]         Open in Claude Code"
    echo "  [q]         Exit wizard"
}

# Open project in new shell
open_in_shell() {
    local project_dir
    project_dir=$(state_get "project_dir")

    echo ""
    echo -e "${TUI_PRIMARY}Opening project directory...${TUI_NC}"
    echo ""
    echo -e "Run: ${TUI_CYAN}cd $project_dir${TUI_NC}"
    echo ""

    # If we're in an interactive shell, we can suggest the cd command
    # But we can't actually change the parent shell's directory
    return 0
}

# Open project in Claude Code
open_in_claude() {
    local project_dir
    project_dir=$(state_get "project_dir")

    if command -v claude &>/dev/null; then
        echo ""
        echo -e "${TUI_PRIMARY}Opening in Claude Code...${TUI_NC}"
        cd "$project_dir" && exec claude
    else
        echo ""
        echo -e "${TUI_WARNING}Claude Code not found in PATH${TUI_NC}"
        echo "Run manually:"
        echo -e "  ${TUI_CYAN}cd $project_dir && claude${TUI_NC}"
        return 1
    fi
}

# Handle input for success screen
handle_success_input() {
    while true; do
        render_success_screen

        local key
        read -rsn1 key

        case "$key" in
            ''|'o'|'O')
                # Open in shell
                log_input "success" "open_shell"
                open_in_shell
                return 0
                ;;
            'c'|'C')
                # Open in Claude Code
                log_input "success" "open_claude"
                open_in_claude
                return 0
                ;;
            'q'|'Q'|$'\e')
                # Quit
                log_input "success" "quit"
                return 0
                ;;
        esac
    done
}

# Run the success screen
run_success_screen() {
    log_screen "ENTER" "success"

    handle_success_input

    # Clean up
    tui_cleanup
    finalize_logging 2>/dev/null || true

    return 0
}
