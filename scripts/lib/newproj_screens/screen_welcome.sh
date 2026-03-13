#!/usr/bin/env bash
# ============================================================
# ACFS newproj TUI Wizard - Welcome Screen
# First screen shown when wizard starts
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_SCREEN_WELCOME_LOADED:-}" ]]; then
    return 0
fi
_ACFS_SCREEN_WELCOME_LOADED=1

# ============================================================
# Screen: Welcome
# ============================================================

# Screen metadata
SCREEN_WELCOME_ID="welcome"
SCREEN_WELCOME_TITLE="Welcome"
SCREEN_WELCOME_STEP=1
SCREEN_WELCOME_NEXT="project_name"

# Render the welcome screen
render_welcome_screen() {
    render_screen_header "Welcome to ACFS Project Setup" "$SCREEN_WELCOME_STEP" 9

    # ASCII art banner (works without unicode)
    if [[ "$TERM_HAS_UNICODE" == "true" ]]; then
        cat << 'EOF'
    ╔═══════════════════════════════════════════════════════╗
    ║                                                       ║
    ║      █████╗  ██████╗ ███████╗ ███████╗                ║
    ║     ██╔══██╗██╔════╝ ██╔════╝ ██╔════╝                ║
    ║     ███████║██║      █████╗   ███████╗                ║
    ║     ██╔══██║██║      ██╔══╝   ╚════██║                ║
    ║     ██║  ██║╚██████╗ ██║      ███████║                ║
    ║     ╚═╝  ╚═╝ ╚═════╝ ╚═╝      ╚══════╝                ║
    ║                                                       ║
    ║          Agentic Coding Flywheel Setup                ║
    ║                                                       ║
    ╚═══════════════════════════════════════════════════════╝
EOF
    else
        cat << 'EOF'
    +-------------------------------------------------------+
    |                                                       |
    |     A   C   F   S                                    |
    |                                                       |
    |     Agentic Coding Flywheel Setup                    |
    |                                                       |
    +-------------------------------------------------------+
EOF
    fi

    echo ""
    echo "This wizard will help you set up a new project with:"
    echo ""

    if [[ "$TERM_HAS_UNICODE" == "true" ]]; then
        echo -e "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} Project directory structure"
        echo -e "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} Git repository initialization"
        echo -e "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} AGENTS.md for AI coding assistants"
        echo -e "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} Beads issue tracking (optional)"
        echo -e "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} Claude Code settings (optional)"
    else
        echo "  [*] Project directory structure"
        echo "  [*] Git repository initialization"
        echo "  [*] AGENTS.md for AI coding assistants"
        echo "  [*] Beads issue tracking (optional)"
        echo "  [*] Claude Code settings (optional)"
    fi

    echo ""
    echo -e "${TUI_GRAY}Press Enter to continue or Escape to exit.${TUI_NC}"

    render_screen_footer false true
}

# Handle input for welcome screen
# Returns: next screen name, or empty to exit
handle_welcome_input() {
    local key

    while true; do
        # Read single keypress
        read -rsn1 key

        case "$key" in
            '')
                # Enter key - continue
                log_input "welcome" "continue"
                echo "$SCREEN_WELCOME_NEXT"
                return 0
                ;;
            $'\e')
                # Escape key - check for escape sequence
                read -rsn2 -t 0.1 escape_seq || true
                if [[ -z "$escape_seq" ]]; then
                    # Plain escape - exit
                    log_input "welcome" "exit"
                    echo ""
                    return 1
                fi
                ;;
            'q'|'Q')
                # q to quit
                log_input "welcome" "quit"
                echo ""
                return 1
                ;;
        esac
    done
}

# Run the welcome screen
# Returns: 0 to continue, 1 to exit
run_welcome_screen() {
    log_screen "ENTER" "welcome"

    render_welcome_screen

    SCREEN_HANDLER_OUTPUT=""
    SCREEN_HANDLER_STATUS=0
    run_screen_handler_capture handle_welcome_input
    local result="$SCREEN_HANDLER_STATUS"
    local next="$SCREEN_HANDLER_OUTPUT"

    if [[ $result -eq 0 ]] && [[ -n "$next" ]]; then
        navigate_forward "$next"
        return 0
    else
        log_screen "EXIT" "welcome" "user_cancelled"
        return 1
    fi
}
