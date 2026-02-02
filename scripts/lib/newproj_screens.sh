#!/usr/bin/env bash
# ============================================================
# ACFS newproj TUI Wizard - Screen Manager
# Loads all screens and provides routing functionality
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_NEWPROJ_SCREENS_SH_LOADED:-}" ]]; then
    return 0
fi
_ACFS_NEWPROJ_SCREENS_SH_LOADED=1

# Get the directory of this script
NEWPROJ_LIB_DIR="${NEWPROJ_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
NEWPROJ_SCREENS_DIR="$NEWPROJ_LIB_DIR/newproj_screens"

# ============================================================
# Dependencies
# ============================================================

# Source core modules
# shellcheck source=newproj_logging.sh
source "$NEWPROJ_LIB_DIR/newproj_logging.sh"
# shellcheck source=newproj_errors.sh
source "$NEWPROJ_LIB_DIR/newproj_errors.sh"
# shellcheck source=newproj_tui.sh
source "$NEWPROJ_LIB_DIR/newproj_tui.sh"
# shellcheck source=newproj_detect.sh
source "$NEWPROJ_LIB_DIR/newproj_detect.sh"
# shellcheck source=newproj_agents.sh
source "$NEWPROJ_LIB_DIR/newproj_agents.sh"

# ============================================================
# Screen Loading
# ============================================================

# Load all screen modules
load_screens() {
    local screens_dir="$NEWPROJ_SCREENS_DIR"

    if [[ ! -d "$screens_dir" ]]; then
        log_error "Screens directory not found: $screens_dir"
        return 1
    fi

    # Source each screen file
    for screen_file in "$screens_dir"/screen_*.sh; do
        if [[ -f "$screen_file" ]]; then
            log_debug "Loading screen: $screen_file"
            # shellcheck disable=SC1090  # dynamic screen loader
            source "$screen_file"
        fi
    done

    log_info "All screens loaded"
    return 0
}

# ============================================================
# Screen Registry
# ============================================================

# Map of screen IDs to their run functions
declare -gA SCREEN_RUNNERS=(
    ["welcome"]="run_welcome_screen"
    ["project_name"]="run_project_name_screen"
    ["directory"]="run_directory_screen"
    ["tech_stack"]="run_tech_stack_screen"
    ["features"]="run_features_screen"
    ["agents_preview"]="run_agents_preview_screen"
    ["confirmation"]="run_confirmation_screen"
    ["progress"]="run_progress_screen"
    ["success"]="run_success_screen"
)

# Screen flow order
declare -ga SCREEN_FLOW=(
    "welcome"
    "project_name"
    "directory"
    "tech_stack"
    "features"
    "agents_preview"
    "confirmation"
    "progress"
    "success"
)

# Get the run function for a screen
get_screen_runner() {
    local screen_id="$1"
    echo "${SCREEN_RUNNERS[$screen_id]:-}"
}

# Get the next screen in flow
get_next_screen() {
    local current="$1"
    local found=false

    for screen in "${SCREEN_FLOW[@]}"; do
        if [[ "$found" == "true" ]]; then
            echo "$screen"
            return 0
        fi
        if [[ "$screen" == "$current" ]]; then
            found=true
        fi
    done

    echo ""
    return 1
}

# Get the previous screen in flow
get_previous_screen() {
    local current="$1"
    local prev=""

    for screen in "${SCREEN_FLOW[@]}"; do
        if [[ "$screen" == "$current" ]]; then
            echo "$prev"
            return 0
        fi
        prev="$screen"
    done

    echo ""
    return 1
}

# ============================================================
# Screen Router
# ============================================================

# Run a specific screen
# Returns: 0 to continue, 1 to exit
run_screen() {
    local screen_id="$1"

    local runner
    runner=$(get_screen_runner "$screen_id")

    if [[ -z "$runner" ]]; then
        log_error "Unknown screen: $screen_id"
        return 1
    fi

    if ! declare -f "$runner" &>/dev/null; then
        log_error "Screen runner function not found: $runner"
        return 1
    fi

    # Track current screen for signal handlers (resize/interrupt)
    # shellcheck disable=SC2034  # used by newproj_errors.sh
    WIZARD_CURRENT_SCREEN="$screen_id"
    local redraw="render_${screen_id}_screen"
    if declare -f "$redraw" &>/dev/null; then
        # shellcheck disable=SC2034  # used by newproj_errors.sh
        WIZARD_REDRAW_FUNCTION="$redraw"
    else
        # shellcheck disable=SC2034  # used by newproj_errors.sh
        WIZARD_REDRAW_FUNCTION=""
    fi

    log_debug "Running screen: $screen_id via $runner"

    # Run the screen
    "$runner"
}

# Main wizard loop
# Runs screens until completion or cancellation
run_wizard() {
    log_info "Starting wizard loop"

    # Initialize TUI
    if ! tui_init; then
        log_error "Failed to initialize TUI"
        echo "Error: Unable to initialize terminal UI"
        echo "Make sure you're running in an interactive terminal"
        return 1
    fi

    # Load all screens
    if ! load_screens; then
        log_error "Failed to load screens"
        return 1
    fi

    # Start at welcome screen
    CURRENT_SCREEN="welcome"
    # shellcheck disable=SC2034  # used by newproj_tui.sh
    SCREEN_HISTORY=()

    # Main loop
    while true; do
        log_debug "Current screen: $CURRENT_SCREEN"

        if ! run_screen "$CURRENT_SCREEN"; then
            # Screen indicated exit or error
            log_info "Wizard exited from screen: $CURRENT_SCREEN"
            break
        fi

        # Check if we've completed the flow
        if [[ "$CURRENT_SCREEN" == "success" ]]; then
            log_info "Wizard completed successfully"
            break
        fi

        # Navigation is handled by individual screens via navigate_forward/navigate_back
        # which update CURRENT_SCREEN
    done

    # Cleanup
    tui_cleanup

    return 0
}

# ============================================================
# Quick Actions (for CLI integration)
# ============================================================

# Run wizard with preset values
# Usage: run_wizard_with_defaults "project_name" "/path/to/dir"
run_wizard_with_defaults() {
    local project_name="$1"
    local project_dir="$2"

    if [[ -n "$project_name" ]]; then
        state_set "project_name" "$project_name"
    fi

    if [[ -n "$project_dir" ]]; then
        state_set "project_dir" "$project_dir"
    fi

    run_wizard
}

# Skip to confirmation with all values set
# Usage: run_wizard_confirm_only "project_name" "/path/to/dir" "nodejs python" "true" "true" "true" "true"
run_wizard_confirm_only() {
    local project_name="$1"
    local project_dir="$2"
    local tech_stack="$3"
    local enable_br="${4:-true}"
    local enable_claude="${5:-true}"
    local enable_agents="${6:-true}"
    local enable_ubsignore="${7:-true}"

    state_set "project_name" "$project_name"
    state_set "project_dir" "$project_dir"
    state_set "tech_stack" "$tech_stack"
    state_set "enable_br" "$enable_br"
    state_set "enable_claude" "$enable_claude"
    state_set "enable_agents" "$enable_agents"
    state_set "enable_ubsignore" "$enable_ubsignore"

    # Start at confirmation
    CURRENT_SCREEN="confirmation"
    SCREEN_HISTORY=("welcome" "project_name" "directory" "tech_stack" "features" "agents_preview")

    # Initialize and run
    tui_init || return 1
    load_screens || return 1

    while true; do
        if ! run_screen "$CURRENT_SCREEN"; then
            break
        fi
        if [[ "$CURRENT_SCREEN" == "success" ]]; then
            break
        fi
    done

    tui_cleanup
    return 0
}
