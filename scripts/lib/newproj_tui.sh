#!/usr/bin/env bash
# shellcheck disable=SC2034  # variables are consumed by screen modules
# ============================================================
# ACFS newproj TUI Wizard - Core Framework
# Provides screen management, navigation, state, and styling
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_NEWPROJ_TUI_SH_LOADED:-}" ]]; then
    return 0
fi
_ACFS_NEWPROJ_TUI_SH_LOADED=1

# Get the directory of this script
NEWPROJ_LIB_DIR="${NEWPROJ_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Source dependencies
# shellcheck source=newproj_logging.sh
source "$NEWPROJ_LIB_DIR/newproj_logging.sh"
# shellcheck source=newproj_errors.sh
source "$NEWPROJ_LIB_DIR/newproj_errors.sh"

# ============================================================
# Terminal Capabilities
# ============================================================

# Capability flags
TERM_HAS_COLOR=false
TERM_HAS_256COLOR=false
TERM_HAS_UNICODE=false
GUM_AVAILABLE=false
GLOW_AVAILABLE=false

# Terminal dimensions
TERM_COLS=80
TERM_LINES=24

# Detect terminal capabilities
detect_terminal_capabilities() {
    log_debug "Detecting terminal capabilities..."

    # Get terminal size
    TERM_COLS=$(tput cols 2>/dev/null || echo 80)
    TERM_LINES=$(tput lines 2>/dev/null || echo 24)

    # Check color support
    if [[ -t 1 ]]; then
        local colors
        colors=$(tput colors 2>/dev/null || echo 0)
        if [[ "$colors" -ge 8 ]]; then
            TERM_HAS_COLOR=true
        fi
        if [[ "$colors" -ge 256 ]] || [[ "${TERM:-}" =~ 256color ]]; then
            TERM_HAS_256COLOR=true
        fi
    fi

    # Override: TERM=dumb means no color
    if [[ "${TERM:-}" == "dumb" ]]; then
        TERM_HAS_COLOR=false
        TERM_HAS_256COLOR=false
    fi

    # Check unicode support
    if locale charmap 2>/dev/null | grep -qi utf-8; then
        TERM_HAS_UNICODE=true
    fi

    # Check gum availability
    if command -v gum &>/dev/null; then
        GUM_AVAILABLE=true
    fi

    # Check glow availability
    if command -v glow &>/dev/null; then
        GLOW_AVAILABLE=true
    fi

    log_debug "Terminal: ${TERM_COLS}x${TERM_LINES} color=$TERM_HAS_COLOR 256=$TERM_HAS_256COLOR unicode=$TERM_HAS_UNICODE gum=$GUM_AVAILABLE"
}

# ============================================================
# Colors and Styling
# ============================================================

# Define colors (only set if color is supported)
setup_colors() {
    if [[ "$TERM_HAS_COLOR" == "true" ]]; then
        TUI_RED='\033[0;31m'
        TUI_GREEN='\033[0;32m'
        TUI_YELLOW='\033[0;33m'
        TUI_BLUE='\033[0;34m'
        TUI_MAGENTA='\033[0;35m'
        TUI_CYAN='\033[0;36m'
        TUI_WHITE='\033[0;37m'
        TUI_GRAY='\033[0;90m'
        TUI_BOLD='\033[1m'
        TUI_DIM='\033[2m'
        TUI_NC='\033[0m'

        # Catppuccin Mocha theme (for gum compatibility)
        if [[ "$TERM_HAS_256COLOR" == "true" ]]; then
            TUI_PRIMARY='\033[38;5;75m'    # Blue
            TUI_SUCCESS='\033[38;5;114m'   # Green
            TUI_WARNING='\033[38;5;221m'   # Yellow
            TUI_ERROR='\033[38;5;204m'     # Red/Pink
            TUI_ACCENT='\033[38;5;141m'    # Purple
        else
            TUI_PRIMARY="$TUI_BLUE"
            TUI_SUCCESS="$TUI_GREEN"
            TUI_WARNING="$TUI_YELLOW"
            TUI_ERROR="$TUI_RED"
            TUI_ACCENT="$TUI_MAGENTA"
        fi
    else
        # No colors
        TUI_RED=''
        TUI_GREEN=''
        TUI_YELLOW=''
        TUI_BLUE=''
        TUI_MAGENTA=''
        TUI_CYAN=''
        TUI_WHITE=''
        TUI_GRAY=''
        TUI_BOLD=''
        TUI_DIM=''
        TUI_NC=''
        TUI_PRIMARY=''
        TUI_SUCCESS=''
        TUI_WARNING=''
        TUI_ERROR=''
        TUI_ACCENT=''
    fi
}

# ============================================================
# Box Drawing Characters
# ============================================================

setup_box_chars() {
    if [[ "$TERM_HAS_UNICODE" == "true" ]]; then
        BOX_TL='╭'
        BOX_TR='╮'
        BOX_BL='╰'
        BOX_BR='╯'
        BOX_H='─'
        BOX_V='│'
        BOX_CHECK='✓'
        BOX_CROSS='✗'
        BOX_BULLET='•'
        BOX_ARROW='→'
        SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    else
        BOX_TL='+'
        BOX_TR='+'
        BOX_BL='+'
        BOX_BR='+'
        BOX_H='-'
        BOX_V='|'
        BOX_CHECK='*'
        BOX_CROSS='x'
        BOX_BULLET='*'
        BOX_ARROW='->'
        SPINNER_FRAMES=('|' '/' '-' "\\")
    fi
}

# ============================================================
# State Management
# ============================================================

# Wizard state (associative array)
declare -gA WIZARD_STATE=(
    [project_name]=""
    [project_dir]=""
    [tech_stack]=""
    [enable_br]="true"
    [enable_claude]="true"
    [enable_agents]="true"
    [enable_ubsignore]="true"
)

# Set a state value
# Usage: state_set "key" "value"
state_set() {
    local key="$1"
    local value="$2"
    local old_value="${WIZARD_STATE[$key]:-}"

    WIZARD_STATE[$key]="$value"

    # Log the state change
    log_state "$key" "$old_value" "$value"
}

# Get a state value
# Usage: state_get "key"
state_get() {
    local key="$1"
    echo "${WIZARD_STATE[$key]:-}"
}

# Check if a state value is set (non-empty)
# Usage: if state_has "key"; then ... fi
state_has() {
    local key="$1"
    [[ -n "${WIZARD_STATE[$key]:-}" ]]
}

# Reset all state to defaults
state_reset() {
    WIZARD_STATE=(
        [project_name]=""
        [project_dir]=""
        [tech_stack]=""
        [enable_br]="true"
        [enable_claude]="true"
        [enable_agents]="true"
        [enable_ubsignore]="true"
    )
    log_info "State reset to defaults"
}

# ============================================================
# Navigation
# ============================================================

# Screen history stack
declare -ga SCREEN_HISTORY=()

# Current screen
CURRENT_SCREEN=""

# Push a screen onto the history stack
# Usage: push_screen "screen_name"
push_screen() {
    local screen="$1"
    if [[ -n "$CURRENT_SCREEN" ]]; then
        SCREEN_HISTORY+=("$CURRENT_SCREEN")
    fi
    CURRENT_SCREEN="$screen"
    log_nav "PUSH" "" "$screen"
}

# Pop a screen from the history stack
# Usage: screen=$(pop_screen)
pop_screen() {
    if [[ ${#SCREEN_HISTORY[@]} -gt 0 ]]; then
        local prev_screen="${SCREEN_HISTORY[-1]}"
        unset 'SCREEN_HISTORY[-1]'
        CURRENT_SCREEN="$prev_screen"
        log_nav "POP" "" "$prev_screen"
        echo "$prev_screen"
    else
        echo ""
    fi
}

# Get history depth
# Usage: depth=$(get_history_depth)
get_history_depth() {
    echo "${#SCREEN_HISTORY[@]}"
}

# Navigate forward to a new screen
# Usage: navigate_forward "screen_name"
navigate_forward() {
    local next_screen="$1"
    local current="$CURRENT_SCREEN"

    log_screen "EXIT" "$current"
    push_screen "$next_screen"
    log_screen "ENTER" "$next_screen"
}

# Navigate back to the previous screen
# Usage: if navigate_back; then ... fi
navigate_back() {
    if [[ ${#SCREEN_HISTORY[@]} -gt 0 ]]; then
        local current="$CURRENT_SCREEN"
        log_screen "EXIT" "$current"
        pop_screen >/dev/null
        log_screen "ENTER" "$CURRENT_SCREEN"
        return 0
    else
        return 1
    fi
}

# ============================================================
# Drawing Utilities
# ============================================================

# Draw a horizontal line
# Usage: draw_line [width] [char]
draw_line() {
    local width="${1:-$TERM_COLS}"
    local char="${2:-$BOX_H}"
    printf '%*s' "$width" '' | tr ' ' "$char"
}

# Draw a box around text
# Usage: draw_box "title" "content" [width]
draw_box() {
    local title="${1:-}"
    local content="${2:-}"
    local width="${3:-60}"

    # Ensure minimum width
    [[ "$width" -lt 20 ]] && width=20

    # Top border with title
    local title_len=${#title}
    local inner_width=$((width - 4))

    echo -n "$BOX_TL"
    if [[ -n "$title" ]]; then
        echo -n "$BOX_H $title "
        local remaining=$((inner_width - title_len - 2))
        draw_line "$remaining" "$BOX_H"
    else
        draw_line "$((width - 2))" "$BOX_H"
    fi
    echo "$BOX_TR"

    # Content lines
    while IFS= read -r line; do
        local line_len=${#line}
        local padding=$((inner_width - line_len))
        # Clamp padding to avoid negative values for lines longer than box width
        [[ $padding -lt 0 ]] && padding=0
        echo "$BOX_V $line$(printf '%*s' "$padding" '') $BOX_V"
    done <<< "$content"

    # Bottom border
    echo -n "$BOX_BL"
    draw_line "$((width - 2))" "$BOX_H"
    echo "$BOX_BR"
}

# Draw a progress bar
# Usage: render_progress current total [width]
render_progress() {
    local current="$1"
    local total="$2"
    local width="${3:-20}"

    # Guard against division by zero
    [[ "$total" -le 0 ]] && total=1

    local percent=$((current * 100 / total))
    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    local bar=""
    if [[ "$TERM_HAS_UNICODE" == "true" ]]; then
        for ((i = 0; i < filled; i++)); do bar+="█"; done
        for ((i = 0; i < empty; i++)); do bar+="░"; done
    else
        for ((i = 0; i < filled; i++)); do bar+="#"; done
        for ((i = 0; i < empty; i++)); do bar+="-"; done
    fi

    echo "[$bar] $percent%"
}

# Show a spinner for a background operation
# Usage: spinner "message" & pid=$!; do_work; kill $pid
spinner() {
    local message="${1:-Working...}"
    local i=0
    local frame_count=${#SPINNER_FRAMES[@]}

    # Hide cursor
    tput civis 2>/dev/null || true

    while true; do
        local frame="${SPINNER_FRAMES[$((i % frame_count))]}"
        printf "\r%s %s" "$frame" "$message"
        sleep 0.1
        ((i++))
    done
}

# Stop spinner and show result
# Usage: stop_spinner $pid "Success message"
stop_spinner() {
    local pid="$1"
    local message="${2:-Done}"
    local success="${3:-true}"

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true

    # Show cursor
    tput cnorm 2>/dev/null || true

    if [[ "$success" == "true" ]]; then
        printf "\r${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} %s\n" "$message"
    else
        printf "\r${TUI_ERROR}${BOX_CROSS}${TUI_NC} %s\n" "$message"
    fi
}

# ============================================================
# Input Handling
# ============================================================

# Read text input with optional validation
# Usage: result=$(read_text_input "prompt" "default" "validator_function")
read_text_input() {
    local prompt="${1:-Enter value}"
    local default="${2:-}"
    local validator="${3:-}"

    local input=""
    local valid=false

    while [[ "$valid" != "true" ]]; do
        if [[ "$GUM_AVAILABLE" == "true" && "$TERM_HAS_COLOR" == "true" ]]; then
            # Use gum for pretty input
            input=$(gum input \
                --placeholder "${default:-Type here...}" \
                --prompt "$prompt: " \
                --prompt.foreground "#89b4fa" \
                --cursor.foreground "#cba6f7" 2>/dev/null) || true
        else
            # Fallback to read from /dev/tty to avoid stdin conflicts
            # from signal handlers or subshell capture (issue #153)
            if [[ -n "$default" ]]; then
                echo -n "$prompt [$default]: "
                read -r input < /dev/tty || true
                [[ -z "$input" ]] && input="$default"
            else
                echo -n "$prompt: "
                read -r input < /dev/tty || true
            fi
        fi

        log_input "$prompt" "$input"

        # Validate if validator provided
        if [[ -n "$validator" ]]; then
            local error
            if error=$("$validator" "$input" 2>&1); then
                valid=true
            else
                echo -e "${TUI_ERROR}${error}${TUI_NC}"
                log_validation "$prompt" "$input" "FAIL" "$error"
            fi
        else
            valid=true
        fi
    done

    echo "$input"
}

# Read yes/no confirmation
# Usage: if read_yes_no "Are you sure?" "y"; then ... fi
read_yes_no() {
    local prompt="${1:-Continue?}"
    local default="${2:-y}"  # y or n

    local result=""

    if [[ "$GUM_AVAILABLE" == "true" && "$TERM_HAS_COLOR" == "true" ]]; then
        if gum confirm "$prompt" 2>/dev/null; then
            result="y"
        else
            result="n"
        fi
    else
        local hint
        if [[ "$default" == "y" ]]; then
            hint="[Y/n]"
        else
            hint="[y/N]"
        fi

        read -r -p "$prompt $hint " response
        response="${response:-$default}"

        if [[ "$response" =~ ^[Yy]$ ]]; then
            result="y"
        else
            result="n"
        fi
    fi

    log_input "$prompt" "$result"

    [[ "$result" == "y" ]]
}

# Read selection from list
# Usage: selected=$(read_selection "Choose one" "opt1" "opt2" "opt3")
read_selection() {
    local prompt="$1"
    shift
    local options=("$@")

    local selected=""

    if [[ "$GUM_AVAILABLE" == "true" && "$TERM_HAS_COLOR" == "true" ]]; then
        selected=$(gum choose \
            --cursor.foreground "#cba6f7" \
            --selected.foreground "#a6e3a1" \
            "${options[@]}" 2>/dev/null) || true
    else
        echo "$prompt"
        local i=1
        for opt in "${options[@]}"; do
            echo "  $i) $opt"
            ((i++))
        done

        read -r -p "Enter number [1-${#options[@]}]: " num
        if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le ${#options[@]} ]]; then
            selected="${options[$((num - 1))]}"
        fi
    fi

    log_input "$prompt" "$selected"
    echo "$selected"
}

# Read multiple selections (checkboxes)
# Usage: selected=$(read_checkbox "Select options" "opt1" "opt2" "opt3")
read_checkbox() {
    local prompt="$1"
    shift
    local options=("$@")

    local selected=""

    if [[ "$GUM_AVAILABLE" == "true" && "$TERM_HAS_COLOR" == "true" ]]; then
        selected=$(gum choose --no-limit \
            --cursor.foreground "#cba6f7" \
            --selected.foreground "#a6e3a1" \
            "${options[@]}" 2>/dev/null | tr '\n' ' ') || true
    else
        echo "$prompt (enter numbers separated by spaces, or 'all')"
        local i=1
        for opt in "${options[@]}"; do
            echo "  $i) $opt"
            ((i++))
        done

        read -r -p "Select: " input

        if [[ "$input" == "all" ]]; then
            selected="${options[*]}"
        else
            for num in $input; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le ${#options[@]} ]]; then
                    selected+="${options[$((num - 1))]} "
                fi
            done
        fi
    fi

    log_input "$prompt" "$selected"
    echo "$selected"
}

# ============================================================
# Screen Framework
# ============================================================

# Current screen's redraw function (for resize handling)
SCREEN_REDRAW_FUNCTION=""

# Screen header with progress
# Usage: render_screen_header "Screen Title" current_step total_steps
render_screen_header() {
    local title="$1"
    local current="${2:-1}"
    local total="${3:-9}"

    clear

    # Progress bar
    local progress
    progress=$(render_progress "$current" "$total")

    echo -e "${TUI_PRIMARY}${TUI_BOLD}ACFS newproj Wizard${TUI_NC}"
    echo -e "${TUI_GRAY}$progress${TUI_NC}"
    echo ""
    echo -e "${TUI_BOLD}$title${TUI_NC}"
    draw_line "$((TERM_COLS < 60 ? TERM_COLS : 60))"
    echo ""
}

# Screen footer with navigation hints
# Usage: render_screen_footer [has_back] [has_next]
render_screen_footer() {
    local has_back="${1:-true}"
    local has_next="${2:-true}"

    echo ""
    draw_line "$((TERM_COLS < 60 ? TERM_COLS : 60))"

    local hints=""
    if [[ "$has_back" == "true" ]] && [[ ${#SCREEN_HISTORY[@]} -gt 0 ]]; then
        hints+="[Esc] Back  "
    fi
    if [[ "$has_next" == "true" ]]; then
        hints+="[Enter] Continue  "
    fi
    hints+="[Ctrl+C] Cancel"

    echo -e "${TUI_GRAY}$hints${TUI_NC}"
}

# ============================================================
# Initialization
# ============================================================

# Initialize the TUI framework
# Call this before any TUI operations
tui_init() {
    log_info "Initializing TUI framework..."

    # Detect capabilities
    detect_terminal_capabilities

    # Setup styling
    setup_colors
    setup_box_chars

    # Setup signal handlers
    setup_signal_handlers

    # Run pre-flight checks
    if ! preflight_check; then
        log_error "Pre-flight checks failed"
        return 1
    fi

    log_info "TUI framework initialized"
    return 0
}

# Cleanup TUI (restore terminal state)
tui_cleanup() {
    log_info "Cleaning up TUI framework..."

    # Show cursor
    tput cnorm 2>/dev/null || true

    # Clear any styling
    echo -e "${TUI_NC}" 2>/dev/null || true
}
