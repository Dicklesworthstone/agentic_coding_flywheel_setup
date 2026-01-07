#!/usr/bin/env bash
# ============================================================
# ACFS newproj TUI Wizard - Error Handling and Recovery
# Provides robust error handling, signal management, and cleanup
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_NEWPROJ_ERRORS_SH_LOADED:-}" ]]; then
    return 0
fi
_ACFS_NEWPROJ_ERRORS_SH_LOADED=1

# ============================================================
# Configuration
# ============================================================

# Colors for error messages
readonly NEWPROJ_RED='\033[0;31m'
readonly NEWPROJ_YELLOW='\033[0;33m'
readonly NEWPROJ_GREEN='\033[0;32m'
readonly NEWPROJ_NC='\033[0m'

# Minimum terminal size
readonly MIN_TERMINAL_COLS=60
readonly MIN_TERMINAL_LINES=15

# ============================================================
# State Management
# ============================================================

# Items to clean up on exit
declare -a WIZARD_CLEANUP_ITEMS=()

# Transaction state
WIZARD_TRANSACTION_ACTIVE=false
declare -a WIZARD_CREATED_FILES=()

# Saved terminal state
SAVED_STTY=""

# Current screen for redraw
WIZARD_CURRENT_SCREEN=""

# Redraw function (set by TUI framework)
WIZARD_REDRAW_FUNCTION=""

# ============================================================
# Cleanup Registration
# ============================================================

# Register an item for cleanup on exit
# Usage: register_cleanup "/path/to/file_or_dir"
register_cleanup() {
    local item="$1"
    WIZARD_CLEANUP_ITEMS+=("$item")
    log_debug "Registered for cleanup: $item" 2>/dev/null || true
}

# Remove an item from cleanup list (when successfully committed)
# Usage: unregister_cleanup "/path/to/file_or_dir"
unregister_cleanup() {
    local item="$1"
    local new_items=()
    for i in "${WIZARD_CLEANUP_ITEMS[@]}"; do
        if [[ "$i" != "$item" ]]; then
            new_items+=("$i")
        fi
    done
    WIZARD_CLEANUP_ITEMS=("${new_items[@]}")
    log_debug "Unregistered from cleanup: $item" 2>/dev/null || true
}

# ============================================================
# Signal Handlers
# ============================================================

# Main cleanup function called on exit
cleanup_on_exit() {
    local exit_code=$?

    log_debug "Running cleanup with exit code: $exit_code" 2>/dev/null || true

    # Clean up registered items if we're exiting with error
    if [[ "$exit_code" -ne 0 && "$WIZARD_TRANSACTION_ACTIVE" == "true" ]]; then
        for item in "${WIZARD_CLEANUP_ITEMS[@]}"; do
            log_debug "Cleaning up: $item" 2>/dev/null || true
            rm -rf "$item" 2>/dev/null || true
        done
    fi

    # Restore terminal state
    if [[ -n "${SAVED_STTY:-}" ]]; then
        stty "$SAVED_STTY" 2>/dev/null || true
    fi

    # Show cursor if hidden
    tput cnorm 2>/dev/null || true

    # Clear any line formatting
    echo -e "${NEWPROJ_NC}" 2>/dev/null || true

    # Finalize logging if available
    if declare -f finalize_logging &>/dev/null; then
        finalize_logging "$exit_code"
    fi

    return "$exit_code"
}

# Handle Ctrl+C interrupt
handle_interrupt() {
    local current_screen="${WIZARD_CURRENT_SCREEN:-unknown}"

    log_warn "Interrupt received on screen: $current_screen" 2>/dev/null || true

    # Show confirmation prompt
    echo ""
    echo -e "${NEWPROJ_YELLOW}Wizard interrupted.${NEWPROJ_NC}"

    # Read with timeout to prevent hanging
    local confirm=""
    read -r -t 30 -p "Cancel wizard? (y/N) " confirm || true

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "User confirmed cancellation" 2>/dev/null || true
        echo -e "${NEWPROJ_RED}Wizard cancelled.${NEWPROJ_NC}"
        exit 130  # 128 + SIGINT
    else
        log_info "User continued after interrupt" 2>/dev/null || true
        echo ""
        echo "Continuing..."
        # Redraw current screen if function is available
        redraw_current_screen
    fi
}

# Handle terminal resize
handle_resize() {
    local new_cols
    local new_lines
    new_cols=$(tput cols 2>/dev/null || echo 80)
    new_lines=$(tput lines 2>/dev/null || echo 24)

    log_debug "Terminal resized to ${new_cols}x${new_lines}" 2>/dev/null || true

    # Check minimum size
    if [[ "$new_cols" -lt "$MIN_TERMINAL_COLS" || "$new_lines" -lt "$MIN_TERMINAL_LINES" ]]; then
        log_warn "Terminal too small: ${new_cols}x${new_lines}" 2>/dev/null || true
        show_terminal_too_small_message "$new_cols" "$new_lines"
    else
        redraw_current_screen
    fi
}

# Redraw the current screen
redraw_current_screen() {
    if [[ -n "$WIZARD_REDRAW_FUNCTION" ]] && declare -f "$WIZARD_REDRAW_FUNCTION" &>/dev/null; then
        "$WIZARD_REDRAW_FUNCTION"
    fi
}

# Show message when terminal is too small
show_terminal_too_small_message() {
    local cols="${1:-0}"
    local lines="${2:-0}"

    clear
    echo ""
    echo -e "${NEWPROJ_YELLOW}Terminal too small!${NEWPROJ_NC}"
    echo ""
    echo "Current size: ${cols}x${lines}"
    echo "Minimum required: ${MIN_TERMINAL_COLS}x${MIN_TERMINAL_LINES}"
    echo ""
    echo "Please resize your terminal and the wizard will continue."
}

# Setup all signal handlers
# Usage: setup_signal_handlers
setup_signal_handlers() {
    # Save current terminal settings
    SAVED_STTY=$(stty -g 2>/dev/null || true)

    # Install handlers
    trap cleanup_on_exit EXIT
    trap handle_interrupt INT
    trap handle_resize WINCH

    log_debug "Signal handlers installed" 2>/dev/null || true
}

# ============================================================
# Pre-flight Checks
# ============================================================

# Run all pre-flight checks before starting wizard
# Returns: 0 if all checks pass, 1 if critical check fails
preflight_check() {
    local errors=()
    local warnings=()

    log_info "Running pre-flight checks..." 2>/dev/null || true

    # Check terminal is interactive
    if ! [[ -t 0 && -t 1 ]]; then
        errors+=("Not running in interactive terminal (stdin/stdout not TTY)")
    fi

    # Check terminal size
    local cols
    local lines
    cols=$(tput cols 2>/dev/null || echo 0)
    lines=$(tput lines 2>/dev/null || echo 0)

    if [[ "$cols" -lt "$MIN_TERMINAL_COLS" || "$lines" -lt "$MIN_TERMINAL_LINES" ]]; then
        errors+=("Terminal too small (${cols}x${lines}). Minimum: ${MIN_TERMINAL_COLS}x${MIN_TERMINAL_LINES}")
    fi

    # Check required commands
    local required_cmds=(git)
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            errors+=("Required command not found: $cmd")
        fi
    done

    # Check optional commands
    local optional_cmds=(bd gum glow)
    for cmd in "${optional_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            warnings+=("Optional command not found: $cmd (some features may be limited)")
        fi
    done

    # Check write permissions in common locations
    if [[ -n "${HOME:-}" ]] && [[ ! -w "$HOME" ]]; then
        warnings+=("No write permission to home directory")
    fi

    # Report warnings
    for warn in "${warnings[@]}"; do
        log_warn "$warn" 2>/dev/null || true
        echo -e "  ${NEWPROJ_YELLOW}!${NEWPROJ_NC} $warn"
    done

    # Report errors
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "" >&2
        echo -e "${NEWPROJ_RED}Pre-flight checks failed:${NEWPROJ_NC}" >&2
        for err in "${errors[@]}"; do
            log_error "$err" 2>/dev/null || true
            echo -e "  ${NEWPROJ_RED}✗${NEWPROJ_NC} $err" >&2
        done
        echo "" >&2
        return 1
    fi

    log_info "Pre-flight checks passed" 2>/dev/null || true
    return 0
}

# ============================================================
# Error Recovery Functions
# ============================================================

# Try to create a directory with error handling
# Usage: try_create_directory "/path/to/dir"
# Returns: 0 on success, 1 on failure
try_create_directory() {
    local dir="$1"

    log_debug "Creating directory: $dir" 2>/dev/null || true

    # Check if path already exists
    if [[ -e "$dir" ]]; then
        log_error "Path already exists: $dir" 2>/dev/null || true
        show_error_with_recovery "exists" "Path already exists: $dir"
        return 1
    fi

    # Check parent directory exists and is writable
    local parent_dir
    parent_dir=$(dirname "$dir")
    if [[ ! -d "$parent_dir" ]]; then
        log_error "Parent directory does not exist: $parent_dir" 2>/dev/null || true
        show_error_with_recovery "no_parent" "Parent directory does not exist: $parent_dir"
        return 1
    fi

    if [[ ! -w "$parent_dir" ]]; then
        log_error "No write permission to parent directory: $parent_dir" 2>/dev/null || true
        show_error_with_recovery "permission" "No write permission to: $parent_dir"
        return 1
    fi

    # Try to create the directory
    if ! mkdir -p "$dir" 2>/dev/null; then
        local errno=$?
        log_error "Failed to create directory: $dir (errno: $errno)" 2>/dev/null || true

        # Try to diagnose the error
        if ! df "$(dirname "$dir")" &>/dev/null; then
            show_error_with_recovery "disk_full" "Failed to create directory (disk may be full)"
        else
            show_error_with_recovery "unknown" "Failed to create directory: $dir"
        fi
        return $errno
    fi

    # Register for cleanup and track for transaction
    register_cleanup "$dir"
    track_created_file "$dir"

    log_file_op "MKDIR" "$dir" "OK" 2>/dev/null || true
    return 0
}

# Try to initialize git repository
# Usage: try_git_init "/path/to/dir"
try_git_init() {
    local dir="$1"

    log_debug "Initializing git in: $dir" 2>/dev/null || true

    # Check if already a git repo
    if [[ -d "$dir/.git" ]]; then
        log_info "Already a git repository: $dir" 2>/dev/null || true
        return 0
    fi

    if ! git -C "$dir" init 2>/dev/null; then
        local errno=$?
        log_error "git init failed in $dir (errno: $errno)" 2>/dev/null || true
        show_error_with_recovery "git_init" "Failed to initialize git repository"
        return $errno
    fi

    track_created_file "$dir/.git"
    log_cmd "git init" 0 2>/dev/null || true
    return 0
}

# Try to initialize beads (bd)
# Usage: try_bd_init "/path/to/dir"
try_bd_init() {
    local dir="$1"

    log_debug "Initializing bd in: $dir" 2>/dev/null || true

    # Check if bd is available
    if ! command -v bd &>/dev/null; then
        log_warn "bd not found - skipping beads initialization" 2>/dev/null || true
        echo -e "${NEWPROJ_YELLOW}Note: bd not installed. Skipping beads setup.${NEWPROJ_NC}"
        return 0  # Graceful degradation
    fi

    # Check if already initialized
    if [[ -d "$dir/.beads" ]]; then
        log_info "Beads already initialized: $dir" 2>/dev/null || true
        return 0
    fi

    if ! (cd "$dir" && bd init 2>/dev/null); then
        local errno=$?
        log_warn "bd init failed in $dir (errno: $errno)" 2>/dev/null || true
        echo -e "${NEWPROJ_YELLOW}Warning: Failed to initialize beads. You can run 'bd init' later.${NEWPROJ_NC}"
        return 0  # Graceful degradation - not fatal
    fi

    track_created_file "$dir/.beads"
    log_cmd "bd init" 0 2>/dev/null || true
    return 0
}

# Try to write a file
# Usage: try_write_file "/path/to/file" "content"
try_write_file() {
    local file="$1"
    local content="$2"

    log_debug "Writing file: $file" 2>/dev/null || true

    # Check parent directory
    local parent_dir
    parent_dir=$(dirname "$file")
    if [[ ! -d "$parent_dir" ]]; then
        if ! mkdir -p "$parent_dir" 2>/dev/null; then
            log_error "Failed to create parent directory: $parent_dir" 2>/dev/null || true
            return 1
        fi
    fi

    # Write the file
    if ! echo "$content" > "$file" 2>/dev/null; then
        local errno=$?
        log_error "Failed to write file: $file (errno: $errno)" 2>/dev/null || true
        show_error_with_recovery "write" "Failed to write file: $file"
        return $errno
    fi

    track_created_file "$file"
    log_file_op "WRITE" "$file" "OK" 2>/dev/null || true
    return 0
}

# ============================================================
# Transaction Management
# ============================================================

# Begin a transaction for project creation
# All files created after this will be tracked for rollback
begin_project_creation() {
    WIZARD_TRANSACTION_ACTIVE=true
    WIZARD_CREATED_FILES=()
    log_info "Beginning project creation transaction" 2>/dev/null || true
}

# Track a created file within the current transaction
track_created_file() {
    if [[ "$WIZARD_TRANSACTION_ACTIVE" == "true" ]]; then
        WIZARD_CREATED_FILES+=("$1")
    fi
}

# Commit the transaction (files will not be cleaned up)
commit_project_creation() {
    WIZARD_TRANSACTION_ACTIVE=false

    # Remove all created files from cleanup list
    for file in "${WIZARD_CREATED_FILES[@]}"; do
        unregister_cleanup "$file"
    done

    WIZARD_CLEANUP_ITEMS=()
    WIZARD_CREATED_FILES=()

    log_info "Project creation committed successfully" 2>/dev/null || true
}

# Rollback the transaction (remove all created files)
rollback_project_creation() {
    log_error "Rolling back project creation..." 2>/dev/null || true

    # Remove files in reverse order (deepest first)
    local i
    for ((i=${#WIZARD_CREATED_FILES[@]}-1; i>=0; i--)); do
        local file="${WIZARD_CREATED_FILES[i]}"
        log_debug "Removing: $file" 2>/dev/null || true
        rm -rf "$file" 2>/dev/null || true
    done

    WIZARD_CREATED_FILES=()
    WIZARD_TRANSACTION_ACTIVE=false

    echo -e "${NEWPROJ_YELLOW}Project creation rolled back.${NEWPROJ_NC}"
}

# ============================================================
# Graceful Degradation
# ============================================================

# Try an optional feature, skip gracefully if it fails
# Usage: optional_feature "feature_name" command_to_run
# Returns: 0 always (feature is optional)
optional_feature() {
    local feature_name="$1"
    shift
    local command="$*"

    log_debug "Attempting optional feature: $feature_name" 2>/dev/null || true

    if eval "$command" 2>/dev/null; then
        log_info "Optional feature succeeded: $feature_name" 2>/dev/null || true
        return 0
    else
        log_warn "Optional feature skipped: $feature_name" 2>/dev/null || true
        return 0  # Don't fail the wizard
    fi
}

# Check if a feature is available
# Usage: if feature_available "gum"; then ... fi
feature_available() {
    local feature="$1"
    command -v "$feature" &>/dev/null
}

# ============================================================
# User-Friendly Error Messages
# ============================================================

# Show an error with recovery hints
# Usage: show_error_with_recovery "error_type" "message"
show_error_with_recovery() {
    local error_type="$1"
    local message="$2"

    echo ""
    echo -e "${NEWPROJ_RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NEWPROJ_NC}"
    echo -e "${NEWPROJ_RED}  Error: $message${NEWPROJ_NC}"
    echo -e "${NEWPROJ_RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NEWPROJ_NC}"
    echo ""

    case "$error_type" in
        permission)
            echo "How to fix:"
            echo "  1. Check permissions: ls -la <parent_directory>"
            echo "  2. Fix ownership: sudo chown -R \$(whoami) <directory>"
            ;;
        disk_full)
            echo "How to fix:"
            echo "  1. Check disk space: df -h"
            echo "  2. Free up space and try again"
            ;;
        exists)
            echo "How to fix:"
            echo "  1. Choose a different project name"
            echo "  2. Or remove the existing directory first"
            ;;
        no_parent)
            echo "How to fix:"
            echo "  1. Create the parent directory first"
            echo "  2. Or choose a different location"
            ;;
        git_not_installed)
            echo "How to fix:"
            echo "  1. Install git: sudo apt install git"
            echo "  2. Run wizard again"
            ;;
        git_init)
            echo "How to fix:"
            echo "  1. Check if git is installed: git --version"
            echo "  2. Check directory permissions"
            ;;
        write)
            echo "How to fix:"
            echo "  1. Check write permissions to the directory"
            echo "  2. Check available disk space"
            ;;
        *)
            echo "For more details, check the log file."
            ;;
    esac

    # Show log location if available
    if [[ -n "${ACFS_SESSION_LOG:-}" && -f "${ACFS_SESSION_LOG:-}" ]]; then
        echo ""
        echo "Debug log: $ACFS_SESSION_LOG"
    fi
    echo ""
}

# ============================================================
# Validation Helpers
# ============================================================

# Validate project name
# Usage: validate_project_name "name"
# Returns: 0 if valid, 1 if invalid
validate_project_name() {
    local name="$1"
    local error_msg=""

    # Check if empty
    if [[ -z "$name" ]]; then
        error_msg="Project name cannot be empty"
    # Check length
    elif [[ ${#name} -lt 2 ]]; then
        error_msg="Project name must be at least 2 characters"
    elif [[ ${#name} -gt 100 ]]; then
        error_msg="Project name must be less than 100 characters"
    # Check for valid characters (alphanumeric, dash, underscore)
    elif [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        error_msg="Project name must start with a letter and contain only letters, numbers, dashes, and underscores"
    # Check for reserved names
    elif [[ "$name" =~ ^(node_modules|\.git|\.beads|__pycache__|\.venv|venv)$ ]]; then
        error_msg="'$name' is a reserved name"
    fi

    if [[ -n "$error_msg" ]]; then
        log_validation "project_name" "$name" "FAIL" "$error_msg" 2>/dev/null || true
        echo "$error_msg"
        return 1
    fi

    log_validation "project_name" "$name" "PASS" 2>/dev/null || true
    return 0
}

# Validate directory path
# Usage: validate_directory "/path/to/dir"
# Returns: 0 if valid, 1 if invalid
validate_directory() {
    local dir="$1"
    local error_msg=""

    # Expand path
    local expanded_dir
    expanded_dir=$(eval echo "$dir" 2>/dev/null) || expanded_dir="$dir"

    # Check if path is absolute or can be made absolute
    if [[ "$expanded_dir" != /* ]]; then
        expanded_dir="$(pwd)/$expanded_dir"
    fi

    # Check parent directory exists
    local parent_dir
    parent_dir=$(dirname "$expanded_dir")
    if [[ ! -d "$parent_dir" ]]; then
        error_msg="Parent directory does not exist: $parent_dir"
    # Check parent is writable
    elif [[ ! -w "$parent_dir" ]]; then
        error_msg="No write permission to: $parent_dir"
    # Check if target already exists
    elif [[ -e "$expanded_dir" ]]; then
        error_msg="Path already exists: $expanded_dir"
    fi

    if [[ -n "$error_msg" ]]; then
        log_validation "directory" "$dir" "FAIL" "$error_msg" 2>/dev/null || true
        echo "$error_msg"
        return 1
    fi

    log_validation "directory" "$dir" "PASS" 2>/dev/null || true
    echo "$expanded_dir"  # Return expanded path
    return 0
}
