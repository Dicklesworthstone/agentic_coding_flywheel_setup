#!/usr/bin/env bash
# ============================================================
# ACFS newproj TUI Wizard - Progress Screen
# Shows progress during project creation
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_SCREEN_PROGRESS_LOADED:-}" ]]; then
    return 0
fi
_ACFS_SCREEN_PROGRESS_LOADED=1

# ============================================================
# Screen: Progress
# ============================================================

# Screen metadata
SCREEN_PROGRESS_ID="progress"
SCREEN_PROGRESS_TITLE="Creating Project"
SCREEN_PROGRESS_STEP=8
SCREEN_PROGRESS_NEXT="success"

# Step status tracking
declare -gA STEP_STATUS=()
declare -ga STEP_ORDER=()

# Initialize steps based on features
init_creation_steps() {
    STEP_STATUS=()
    STEP_ORDER=()

    # Always required steps
    STEP_ORDER+=("create_dir")
    STEP_STATUS["create_dir"]="pending"

    STEP_ORDER+=("init_git")
    STEP_STATUS["init_git"]="pending"

    STEP_ORDER+=("create_readme")
    STEP_STATUS["create_readme"]="pending"

    STEP_ORDER+=("create_gitignore")
    STEP_STATUS["create_gitignore"]="pending"

    # Feature-dependent steps
    if [[ "$(state_get "enable_agents")" == "true" ]]; then
        STEP_ORDER+=("create_agents")
        STEP_STATUS["create_agents"]="pending"
    fi

    if [[ "$(state_get "enable_br")" == "true" ]]; then
        STEP_ORDER+=("init_br")
        STEP_STATUS["init_br"]="pending"
    fi

    if [[ "$(state_get "enable_claude")" == "true" ]]; then
        STEP_ORDER+=("create_claude")
        STEP_STATUS["create_claude"]="pending"
    fi

    if [[ "$(state_get "enable_ubsignore")" == "true" ]]; then
        STEP_ORDER+=("create_ubsignore")
        STEP_STATUS["create_ubsignore"]="pending"
    fi

    # Final step
    STEP_ORDER+=("finalize")
    STEP_STATUS["finalize"]="pending"
}

# Get step display name
get_step_name() {
    local step="$1"
    case "$step" in
        create_dir) echo "Creating project directory" ;;
        init_git) echo "Initializing Git repository" ;;
        create_readme) echo "Creating README.md" ;;
        create_gitignore) echo "Creating .gitignore" ;;
        create_agents) echo "Generating AGENTS.md" ;;
        init_br) echo "Initializing Beads tracking" ;;
        create_claude) echo "Creating Claude Code settings" ;;
        create_ubsignore) echo "Creating .ubsignore" ;;
        finalize) echo "Finalizing project" ;;
        *) echo "$step" ;;
    esac
}

# Render step status
render_step() {
    local step="$1"
    local status="${STEP_STATUS[$step]:-pending}"
    local name
    name=$(get_step_name "$step")

    local icon color

    case "$status" in
        pending)
            if [[ "$TERM_HAS_UNICODE" == "true" ]]; then
                icon="○"
            else
                icon="[ ]"
            fi
            color="$TUI_GRAY"
            ;;
        running)
            if [[ "$TERM_HAS_UNICODE" == "true" ]]; then
                icon="◐"
            else
                icon="[*]"
            fi
            color="$TUI_PRIMARY"
            ;;
        success)
            if [[ "$TERM_HAS_UNICODE" == "true" ]]; then
                icon="${TUI_SUCCESS}${BOX_CHECK}${TUI_NC}"
            else
                icon="[${TUI_SUCCESS}x${TUI_NC}]"
            fi
            color=""
            ;;
        error)
            if [[ "$TERM_HAS_UNICODE" == "true" ]]; then
                icon="${TUI_ERROR}${BOX_CROSS}${TUI_NC}"
            else
                icon="[${TUI_ERROR}!${TUI_NC}]"
            fi
            color="$TUI_ERROR"
            ;;
    esac

    echo -e "  $icon ${color}$name${TUI_NC}"
}

# Render the progress screen
render_progress_screen() {
    render_screen_header "Creating Project..." "$SCREEN_PROGRESS_STEP" 9

    local project_name
    project_name=$(state_get "project_name")

    echo -e "Setting up ${TUI_PRIMARY}$project_name${TUI_NC}"
    echo ""

    # Count progress
    local total=${#STEP_ORDER[@]}
    local completed=0
    for step in "${STEP_ORDER[@]}"; do
        if [[ "${STEP_STATUS[$step]}" == "success" ]]; then
            completed=$((completed + 1))
        fi
    done

    # Progress bar
    echo -n "Progress: "
    render_progress "$completed" "$total" 30
    echo ""

    # Step list
    for step in "${STEP_ORDER[@]}"; do
        render_step "$step"
    done

    echo ""
}

render_progress_screen_best_effort() {
    if [[ -w /dev/tty ]]; then
        render_progress_screen > /dev/tty 2>/dev/null || true
    else
        render_progress_screen >/dev/null 2>&1 || true
    fi
}

# Update step status and re-render
update_step() {
    local step="$1"
    local status="$2"

    STEP_STATUS[$step]="$status"
    # Re-render progress for interactive users, but never let redraw
    # failures break the underlying creation step.
    render_progress_screen_best_effort
}

# Execute a creation step
execute_step() {
    local step="$1"
    local project_dir
    project_dir=$(state_get "project_dir")
    local project_name
    project_name=$(state_get "project_name")

    log_info "Executing step: $step"
    update_step "$step" "running"

    case "$step" in
        create_dir)
            if try_create_directory "$project_dir"; then
                update_step "$step" "success"
                return 0
            else
                update_step "$step" "error"
                return 1
            fi
            ;;

        init_git)
            if try_git_init "$project_dir"; then
                update_step "$step" "success"
                return 0
            else
                update_step "$step" "error"
                return 1
            fi
            ;;

        create_readme)
            local readme_content="# $project_name

Created with ACFS newproj wizard.

## Getting Started

TODO: Add project documentation here.
"
            if try_write_file "$project_dir/README.md" "$readme_content"; then
                update_step "$step" "success"
                return 0
            else
                update_step "$step" "error"
                return 1
            fi
            ;;

        create_gitignore)
            local gitignore_content="# OS/Editor artifacts
.DS_Store
Thumbs.db
*~
*.swp
*.swo
.idea/
.vscode/
*.sublime-*

# Environment/secrets (never commit these)
.env
.env.*
!.env.example

# Logs
*.log
logs/
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Build artifacts (add project-specific patterns below)
dist/
build/
*.pyc
__pycache__/
node_modules/
.venv/
venv/

# Local AI agent settings
.claude/settings.local.json
"
            if try_write_file "$project_dir/.gitignore" "$gitignore_content"; then
                update_step "$step" "success"
                return 0
            else
                update_step "$step" "error"
                return 1
            fi
            ;;

        create_agents)
            local tech_stack
            tech_stack=$(state_get "tech_stack")

            # Check for custom content
            local custom_content
            custom_content=$(state_get "agents_md_custom")

            local agents_content
            if [[ -n "$custom_content" ]]; then
                agents_content="$custom_content"
            else
                # Convert tech_stack string to array
                local tech_array=()
                for tech in $tech_stack; do
                    case "$tech" in
                        nodejs) tech_array+=("nodejs") ;;
                        python) tech_array+=("python") ;;
                        rust) tech_array+=("rust") ;;
                        go) tech_array+=("go") ;;
                        ruby) tech_array+=("ruby") ;;
                        java) tech_array+=("java-maven") ;;
                        php) tech_array+=("php") ;;
                        elixir) tech_array+=("elixir") ;;
                        docker) tech_array+=("docker") ;;
                    esac
                done

                export AGENTS_ENABLE_BR=$(state_get "enable_br")
                agents_content=$(generate_agents_md "$project_name" "${tech_array[@]}")
            fi

            if try_write_file "$project_dir/AGENTS.md" "$agents_content"; then
                update_step "$step" "success"
                return 0
            else
                update_step "$step" "error"
                return 1
            fi
            ;;

        init_br)
            if try_br_init "$project_dir"; then
                update_step "$step" "success"
                return 0
            else
                local status=$?
                if [[ $status -eq 2 ]]; then
                    log_warn "br init skipped (not installed or failed)"
                    update_step "$step" "pending"
                    return 0
                fi
                update_step "$step" "error"
                return 1
            fi
            ;;

        create_claude)
            if newproj_has_existing_claude_settings "$project_dir"; then
                log_info "Claude settings already exist in $project_dir; skipping creation"
                update_step "$step" "success"
                return 0
            fi

            local claude_settings='{
  "model": "claude-sonnet-4-20250514",
  "permissions": {
    "allow_file_read": true,
    "allow_file_write": true,
    "allow_shell": true
  }
}'
            if try_write_file "$project_dir/.claude/settings.local.json" "$claude_settings"; then
                update_step "$step" "success"
                return 0
            else
                update_step "$step" "error"
                return 1
            fi
            ;;

        create_ubsignore)
            local ubsignore_content="# UBS ignore patterns for $project_name
# Add patterns to exclude from bug scanning

# Common exclusions
node_modules/
.git/
*.min.js
*.bundle.js
dist/
build/
coverage/
.venv/
__pycache__/
"
            if try_write_file "$project_dir/.ubsignore" "$ubsignore_content"; then
                update_step "$step" "success"
                return 0
            else
                update_step "$step" "error"
                return 1
            fi
            ;;

        finalize)
            # Make initial commit if git was initialized
            if [[ -d "$project_dir/.git" ]]; then
                (
                    cd "$project_dir" || exit 1
                    git add -A 2>/dev/null
                    git commit -m "Initial commit

Created with ACFS newproj wizard.

🤖 Generated with [Claude Code](https://claude.com/claude-code)" 2>/dev/null
                ) || true
            fi

            update_step "$step" "success"
            return 0
            ;;

        *)
            log_warn "Unknown step: $step"
            update_step "$step" "success"
            return 0
            ;;
    esac
}

# Run all creation steps
run_creation() {
    init_creation_steps
    render_progress_screen_best_effort

    # Begin transaction
    local project_dir
    project_dir=$(state_get "project_dir")
    begin_project_creation "$project_dir"

    local failed=false
    local failed_step=""

    for step in "${STEP_ORDER[@]}"; do
        if ! execute_step "$step"; then
            failed=true
            failed_step="$step"
            break
        fi
        sleep 0.2  # Small delay for visual effect
    done

    if [[ "$failed" == "true" ]]; then
        # Rollback — display to /dev/tty (issue #214)
        echo "" > /dev/tty
        echo -e "${TUI_ERROR}${BOX_CROSS} Failed at: $(get_step_name "$failed_step")${TUI_NC}" > /dev/tty
        echo "" > /dev/tty

        if read_yes_no "Rollback changes?" "y"; then
            rollback_project_creation
            echo -e "${TUI_WARNING}Changes rolled back${TUI_NC}" > /dev/tty
        else
            suspend_project_creation_cleanup
        fi

        return 1
    else
        # Commit transaction
        commit_project_creation
        return 0
    fi
}

# Handle the progress screen
handle_progress_input() {
    if run_creation; then
        echo "$SCREEN_PROGRESS_NEXT"
        return 0
    else
        # Failed - offer retry or exit (display to /dev/tty, issue #214)
        echo "" > /dev/tty
        echo "Options:" > /dev/tty
        echo "  [r] Retry" > /dev/tty
        echo "  [b] Go back to edit" > /dev/tty
        echo "  [q] Quit" > /dev/tty

        while true; do
            read -rsn1 key < /dev/tty
            case "$key" in
                'r'|'R')
                    rollback_project_creation >/dev/null 2>&1 || true
                    return 0  # Will re-run when screen is called again
                    ;;
                'b'|'B')
                    return 1
                    ;;
                'q'|'Q'|$'\e')
                    return 2
                    ;;
            esac
        done
    fi
}

# Run the progress screen
run_progress_screen() {
    log_screen "ENTER" "progress"

    SCREEN_HANDLER_OUTPUT=""
    SCREEN_HANDLER_STATUS=0
    run_screen_handler_capture handle_progress_input
    local result="$SCREEN_HANDLER_STATUS"
    local next="$SCREEN_HANDLER_OUTPUT"

    case $result in
        0)
            if [[ -n "$next" ]]; then
                navigate_forward "$next"
                return 0
            fi
            return 0
            ;;
        1)
            navigate_back
            return 0
            ;;
        2)
            return 1
            ;;
    esac
}
