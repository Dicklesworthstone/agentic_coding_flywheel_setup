#!/usr/bin/env bash
# ============================================================
# ACFS newproj TUI Wizard - Directory Screen
# Collects and validates the project directory path
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_SCREEN_DIRECTORY_LOADED:-}" ]]; then
    return 0
fi
_ACFS_SCREEN_DIRECTORY_LOADED=1

# ============================================================
# Screen: Directory
# ============================================================

# Screen metadata
SCREEN_DIRECTORY_ID="directory"
SCREEN_DIRECTORY_TITLE="Project Directory"
SCREEN_DIRECTORY_STEP=3
SCREEN_DIRECTORY_NEXT="tech_stack"
SCREEN_DIRECTORY_PREV="project_name"

# Get the default projects directory
get_default_projects_dir() {
    # Configurable default: ACFS_PROJECTS_DIR env var, then check common locations
    # Priority: env var > /data/projects > ~/projects > ~/Projects > $HOME
    if [[ -n "${ACFS_PROJECTS_DIR:-}" ]] && [[ -d "$ACFS_PROJECTS_DIR" ]]; then
        echo "$ACFS_PROJECTS_DIR"
    elif [[ -d "/data/projects" ]]; then
        echo "/data/projects"
    elif [[ -d "$HOME/projects" ]]; then
        echo "$HOME/projects"
    elif [[ -d "$HOME/Projects" ]]; then
        echo "$HOME/Projects"
    else
        # Fall back to /data/projects (ACFS canonical default) even if it doesn't
        # exist yet -- the installer creates it. This unifies NTM, newproj, and docs.
        echo "/data/projects"
    fi
}

# Get the default directory path based on project name
get_default_directory() {
    local project_name
    project_name=$(state_get "project_name")

    if [[ -z "$project_name" ]]; then
        project_name="my-project"
    fi

    local base_dir
    base_dir=$(get_default_projects_dir)

    echo "$base_dir/$project_name"
}

# Check directory status and return warnings/errors
# Returns: 0=ok, 1=warning, 2=error
check_directory_status() {
    local dir="$1"
    local resolved

    # Use normalize_path from newproj_errors.sh for proper path resolution
    # This handles ~, relative paths, and symlink resolution safely
    if declare -f normalize_path &>/dev/null; then
        resolved=$(normalize_path "$dir")
        # If normalize_path fails or returns empty, fall back to basic expansion
        if [[ -z "$resolved" ]]; then
            resolved="$dir"
            # Basic tilde expansion
            if [[ "$resolved" == "~"* ]]; then
                resolved="${resolved/#\~/$HOME}"
            fi
            # Make absolute if relative
            if [[ "$resolved" != /* ]]; then
                resolved="$(pwd)/$resolved"
            fi
        fi
    else
        # Fallback if normalize_path not available
        resolved="$dir"
        # Basic tilde expansion
        if [[ "$resolved" == "~"* ]]; then
            resolved="${resolved/#\~/$HOME}"
        fi
        # Make absolute if relative
        if [[ "$resolved" != /* ]]; then
            resolved="$(pwd)/$resolved"
        fi
    fi

    # Check if exists
    if [[ -e "$resolved" ]]; then
        if [[ -d "$resolved" ]]; then
            if [[ -z "$(ls -A "$resolved" 2>/dev/null)" ]]; then
                echo "WARNING:Directory exists but is empty (will be used)"
                return 1
            else
                echo "ERROR:Directory already exists and is not empty"
                return 2
            fi
        else
            echo "ERROR:Path exists but is not a directory"
            return 2
        fi
    fi

    # Check parent exists
    local parent
    parent=$(dirname "$resolved")
    if [[ ! -d "$parent" ]]; then
        echo "ERROR:Parent directory does not exist: $parent"
        return 2
    fi

    # Check parent is writable
    if [[ ! -w "$parent" ]]; then
        echo "ERROR:Cannot write to parent directory: $parent"
        return 2
    fi

    echo "OK:$resolved"
    return 0
}

# Render the directory screen
render_directory_screen() {
    local current_value="${1:-}"

    render_screen_header "Choose Project Location" "$SCREEN_DIRECTORY_STEP" 9

    echo "Where should we create the project directory?"
    echo ""

    # Show current project name for context
    local project_name
    project_name=$(state_get "project_name")
    printf "%b\n" "Project: ${TUI_PRIMARY}$project_name${TUI_NC}"
    echo ""

    # Show default suggestion
    local default_dir
    default_dir=$(get_default_directory)
    printf "%b\n" "${TUI_GRAY}Default location: $default_dir${TUI_NC}"
    echo ""

    if [[ -n "$current_value" ]]; then
        printf "%b\n" "Current: ${TUI_PRIMARY}$current_value${TUI_NC}"

        # Check and show status
        local status
        status=$(check_directory_status "$current_value")
        local status_code=$?

        case $status_code in
            0)
                local resolved="${status#OK:}"
                if [[ "$resolved" != "$current_value" ]]; then
                    printf "%b\n" "${TUI_SUCCESS}${BOX_ARROW} Resolved: $resolved${TUI_NC}"
                fi
                ;;
            1)
                printf "%b\n" "${TUI_WARNING}${BOX_BULLET} ${status#WARNING:}${TUI_NC}"
                ;;
            2)
                printf "%b\n" "${TUI_ERROR}${BOX_CROSS} ${status#ERROR:}${TUI_NC}"
                ;;
        esac
        echo ""
    fi

    printf "%b\n" "${TUI_GRAY}Tip: You can use ~ for home directory${TUI_NC}"
}

# Handle input for directory screen
handle_directory_input() {
    local default_dir
    default_dir=$(get_default_directory)

    local current_dir
    current_dir=$(state_get "project_dir")
    [[ -z "$current_dir" ]] && current_dir="$default_dir"

    local dir=""
    local valid=false

    while [[ "$valid" != "true" ]]; do
        # Use TUI input
        if [[ "$GUM_AVAILABLE" == "true" && "$TERM_HAS_COLOR" == "true" ]]; then
            dir=$(gum input \
                --value "$current_dir" \
                --placeholder "$default_dir" \
                --prompt "Directory: " \
                --prompt.foreground "#89b4fa" \
                --cursor.foreground "#cba6f7" \
                --width 60 < /dev/tty 2>/dev/null) || {
                # User cancelled
                echo ""
                return 1
            }
        else
            newproj_tty_printf "%s [%s]: " "Directory" "$current_dir"
            # Read from /dev/tty explicitly to avoid stdin conflicts
            # from signal handlers or subshell capture (issue #153)
            read -r dir < /dev/tty || true
            [[ -z "$dir" ]] && dir="$current_dir"
        fi

        log_input "directory" "$dir"

        # Handle escape/back
        if [[ -z "$dir" ]]; then
            echo ""
            return 1
        fi

        # Expand tilde
        if [[ "$dir" == "~"* ]]; then
            dir="${dir/#\~/$HOME}"
        fi

        # Make absolute if relative
        if [[ "$dir" != /* ]]; then
            dir="$(pwd)/$dir"
        fi

        # Check status
        local status
        status=$(check_directory_status "$dir")
        local status_code=$?

        case $status_code in
            0)
                # OK - extract resolved path
                local resolved="${status#OK:}"
                state_set "project_dir" "$resolved"
                log_validation "directory" "$dir" "PASS"
                valid=true
                ;;
            1)
                # Warning - confirm with user
                newproj_tty_printf "%b\n" "${TUI_WARNING}${status#WARNING:}${TUI_NC}"
                if read_yes_no "Continue anyway?" "y"; then
                    state_set "project_dir" "$dir"
                    log_validation "directory" "$dir" "PASS" "warning_accepted"
                    valid=true
                else
                    current_dir="$dir"
                fi
                ;;
            2)
                # Error
                newproj_tty_printf "%b\n" "${TUI_ERROR}${BOX_CROSS} ${status#ERROR:}${TUI_NC}"
                newproj_tty_printf "%b\n" ""
                log_validation "directory" "$dir" "FAIL" "$status"
                current_dir="$dir"
                ;;
        esac
    done

    echo "$SCREEN_DIRECTORY_NEXT"
    return 0
}

# Run the directory screen
run_directory_screen() {
    log_screen "ENTER" "directory"

    local current_dir
    current_dir=$(state_get "project_dir")

    render_directory_screen "$current_dir"

    SCREEN_HANDLER_OUTPUT=""
    SCREEN_HANDLER_STATUS=0
    run_screen_handler_capture handle_directory_input
    local result="$SCREEN_HANDLER_STATUS"
    local next="$SCREEN_HANDLER_OUTPUT"

    if [[ $result -eq 0 ]] && [[ -n "$next" ]]; then
        navigate_forward "$next"
        return 0
    else
        navigate_back
        return 0
    fi
}
