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
CREATION_REQUEST=""
CREATION_PROJECT_DIR=""
CREATION_DIRECTORY_ID=""
CREATION_DIRECTORY_FD=""

# Inspect every component without following links. With --held, compare the
# path to the original directory handle, not merely an inode that could be
# recycled after the directory was removed.
creation_directory_identity() {
    command -v python3 >/dev/null 2>&1 || return 1
    python3 -I - "$1" "${2:-}" <<'ACFS_CREATION_IDENTITY_PY'
from contextlib import contextmanager, ExitStack
import os
import sys


@contextmanager
def opened(name, parent=None):
    with ExitStack() as owner:
        handle = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        owner.callback(os.close, handle)
        yield handle


try:
    path, mode = sys.argv[1:]
    if not path or mode not in ("", "--held"):
        raise ValueError("invalid directory inspection")
    with ExitStack() as handles:
        current = handles.enter_context(opened("/" if path.startswith("/") else "."))
        for part in path.split("/"):
            if part not in ("", "."):
                current = handles.enter_context(opened(part, current))
        info = os.fstat(current)
        if mode == "--held":
            held = os.fstat(3)
            if (held.st_dev, held.st_ino) != (info.st_dev, info.st_ino):
                raise ValueError("directory was replaced")
        print(str(info.st_dev) + ":" + str(info.st_ino))
except (OSError, ValueError):
    sys.exit(1)
ACFS_CREATION_IDENTITY_PY
}

creation_forget_directory() {
    if [[ "${CREATION_DIRECTORY_FD:-}" =~ ^[1-9][0-9]+$ ]]; then
        { exec {CREATION_DIRECTORY_FD}<&-; } 2>/dev/null || true
    fi
    CREATION_DIRECTORY_FD=""
    CREATION_DIRECTORY_ID=""
}

creation_verify_directory() {
    local current_identity=""
    if [[ "${CREATION_DIRECTORY_FD:-}" =~ ^[1-9][0-9]+$ && -n "$CREATION_DIRECTORY_ID" ]] \
        && current_identity=$(creation_directory_identity "$CREATION_PROJECT_DIR" --held 3<&"$CREATION_DIRECTORY_FD") \
        && [[ "$current_identity" == "$CREATION_DIRECTORY_ID" ]]; then
        return 0
    fi
    newproj_tty_printf '%s\n' 'The retained project directory is missing, replaced, or no longer safe.' \
        'Restore the original directory to retry, or choose a different directory. Nothing was removed.'
    return 1
}

# Bind retry to the settings that produced the retained files. This is an
# opaque comparison string, never shell source and never passed to eval.
creation_request() {
    local key value
    for key in project_dir project_name tech_stack agents_md_custom \
        enable_agents enable_br enable_claude enable_ubsignore; do
        value=$(state_get "$key") || return 1
        printf '%q=%q\n' "$key" "$value"
    done
}

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
        skipped)
            if [[ "$TERM_HAS_UNICODE" == "true" ]]; then
                icon="${TUI_WARNING}!${TUI_NC}"
            else
                icon="[${TUI_WARNING}-${TUI_NC}]"
            fi
            color="$TUI_WARNING"
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
        if [[ "${STEP_STATUS[$step]:-pending}" == "success" ]]; then
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
    # [[ -w /dev/tty ]] is true even without a controlling terminal (cron, CI,
    # nohup), where opening it fails with ENXIO and prints an error; probe by
    # actually opening it.
    if { : > /dev/tty; } 2>/dev/null; then
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
            local parent_dir
            parent_dir=$(dirname -- "$project_dir") || return 1
            if ! creation_directory_identity "$parent_dir" >/dev/null; then
                update_step "$step" "error"
                newproj_tty_printf '%s\n' 'Cannot safely inspect the project parent directory.'
                return 1
            fi
            if try_create_directory "$project_dir"; then
                creation_forget_directory
                # /.: require a directory during lookup, so a substituted
                # FIFO cannot block the shell while opening its reference.
                if ! { exec {CREATION_DIRECTORY_FD}<"$project_dir/."; } \
                    || ! CREATION_DIRECTORY_ID=$(creation_directory_identity "$project_dir" --held 3<&"$CREATION_DIRECTORY_FD"); then
                    creation_forget_directory
                    update_step "$step" "error"
                    newproj_tty_printf '%s\n' 'Cannot retain the project directory identity; no further steps were run.'
                    return 1
                fi
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

                AGENTS_ENABLE_BR=$(state_get "enable_br") || return 1
                export AGENTS_ENABLE_BR
                if ! agents_content=$(generate_agents_md "$project_name" "${tech_array[@]}"); then
                    update_step "$step" "error"
                    return 1
                fi
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
                    # Show a visible "skipped" state instead of quietly
                    # resetting to pending (GH #315): the user must be able
                    # to see that beads was requested but not initialized.
                    log_warn "br init skipped (not installed or failed)"
                    update_step "$step" "skipped"
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
  "permissions": {
    "allow": ["Read", "Edit", "Write", "Bash"]
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
            # Users may have added work while repairing a failed step. Never
            # stage or commit that work implicitly, and never hide git errors
            # behind a successful project-creation result.
            update_step "$step" "success"
            return 0
            ;;

        *)
            log_warn "Unknown step: $step"
            update_step "$step" "error"
            return 1
            ;;
    esac
}

# Run all creation steps
run_creation() {
    local project_dir request step
    project_dir=$(state_get "project_dir") || return 1
    request=$(creation_request) || return 1
    if [[ "$project_dir" == "$CREATION_PROJECT_DIR" && -n "$CREATION_REQUEST" ]]; then
        if [[ "$request" != "$CREATION_REQUEST" ]]; then
            newproj_tty_printf '%s\n' 'The retained project was created with different settings.' \
                'Restore the original settings to retry, or choose a different directory. Nothing was removed.'
            return 1
        fi
    else
        creation_forget_directory
        init_creation_steps || return 1
        CREATION_PROJECT_DIR="$project_dir"
        CREATION_REQUEST="$request"
        begin_project_creation "$project_dir" || return 1
    fi
    # A disconnect, signal, failed command, Retry, Back or Quit must never
    # authorize recursive deletion. Keep the old helper's EXIT trap inactive
    # before the first filesystem operation, not only after a reported error.
    suspend_project_creation_cleanup || return 1
    render_progress_screen_best_effort
    for step in "${STEP_ORDER[@]}"; do
        case "${STEP_STATUS[$step]:-pending}" in
            success|skipped) continue ;;
        esac
        if [[ "$step" != create_dir ]]; then
            creation_verify_directory || return 1
        fi
        if ! execute_step "$step"; then
            update_step "$step" "error"
            newproj_tty_printf '\nFailed at: %s\nProject preserved: %s\n' \
                "$(get_step_name "$step")" "$project_dir"
            newproj_tty_printf '%s\n' 'Fix the cause, then retry the unfinished steps. No files were removed.'
            return 1
        fi
    done
    creation_verify_directory || return 1
    commit_project_creation || return 1
    return 0
}

creation_read_key() {
    local tty_fd
    if { exec {tty_fd}</dev/tty; } 2>/dev/null; then
        local status=0
        IFS= read -rsn1 key <&"$tty_fd" || status=$?
        exec {tty_fd}<&-
        return "$status"
    fi
    IFS= read -rsn1 key
}

# Handle the progress screen
handle_progress_input() {
    if run_creation; then
        echo "$SCREEN_PROGRESS_NEXT"
        return 0
    else
        newproj_tty_printf '\n%s\n' 'Options:'
        newproj_tty_printf '%s\n' '  [r] Retry unfinished steps (preserve completed work)' \
            '  [b] Go back' '  [q] Quit and preserve the project'

        local key
        while true; do
            creation_read_key || return 2
            case "$key" in
                'r'|'R')
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
