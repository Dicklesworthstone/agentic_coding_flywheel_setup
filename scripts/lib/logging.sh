#!/usr/bin/env bash
# ============================================================
# ACFS Installer - Logging Library
# Provides consistent, colored output for the installer
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_LOGGING_SH_LOADED:-}" ]]; then
    return 0
fi
_ACFS_LOGGING_SH_LOADED=1

# Colors
export ACFS_RED='\033[0;31m'
export ACFS_GREEN='\033[0;32m'
export ACFS_YELLOW='\033[0;33m'
export ACFS_BLUE='\033[0;34m'
export ACFS_GRAY='\033[0;90m'
export ACFS_NC='\033[0m' # No Color

# Log a major step (blue)
# Usage: log_step "1/8" "Installing packages..."
if ! declare -f log_step >/dev/null; then
    log_step() {
        if [[ $# -ge 2 ]]; then
            local step="$1"
            local message="$2"
            printf "${ACFS_BLUE}[%s]${ACFS_NC} %s\n" "$step" "$message" >&2
            return 0
        fi

        local message="${1:-}"
        printf "${ACFS_BLUE}[•]${ACFS_NC} %s\n" "$message" >&2
    }
fi

# Log a section header (blue)
# Usage: log_section "Phase: Shell setup"
if ! declare -f log_section >/dev/null; then
    log_section() {
        local title="$1"
        echo "" >&2
        printf "${ACFS_BLUE}%s${ACFS_NC}\n" "$title" >&2
    }
fi

# Log detail information (gray, indented)
# Usage: log_detail "Installing zsh..."
if ! declare -f log_detail >/dev/null; then
    log_detail() {
        printf "${ACFS_GRAY}    %s${ACFS_NC}\n" "$1" >&2
    }
fi

# Log informational message (alias for log_detail)
# Usage: log_info "Downloading..."
if ! declare -f log_info >/dev/null; then
    log_info() {
        log_detail "$1"
    }
fi

# Log success message (green with checkmark)
# Usage: log_success "Installation complete"
if ! declare -f log_success >/dev/null; then
    log_success() {
        printf "${ACFS_GREEN}%s${ACFS_NC}\n" "$1" >&2
    }
fi

# Log warning message (yellow with warning symbol)
# Usage: log_warn "This may take a while"
if ! declare -f log_warn >/dev/null; then
    log_warn() {
        printf "${ACFS_YELLOW}%s${ACFS_NC}\n" "$1" >&2
    }
fi

# Log error message (red with X)
# Usage: log_error "Failed to install package"
if ! declare -f log_error >/dev/null; then
    log_error() {
        printf "${ACFS_RED}%s${ACFS_NC}\n" "$1" >&2
    }
fi

# Log fatal error and exit
# Usage: log_fatal "Cannot continue without root"
if ! declare -f log_fatal >/dev/null; then
    log_fatal() {
        log_error "$1"
        exit 1
    }
fi

# Log to file (for persistent logging)
# Usage: log_to_file "message" "/path/to/log"
if ! declare -f log_to_file >/dev/null; then
    log_to_file() {
        local message="$1"
        local logfile="${2:-/var/log/acfs/install.log}"

        # Ensure log directory exists
        mkdir -p "$(dirname "$logfile")" 2>/dev/null || true

        # Write timestamped message
        printf "[%s] %s\n" "$(date -Iseconds)" "$message" >> "$logfile" 2>/dev/null || true
    }
fi

# Associative array for timer tracking (avoids eval)
declare -gA ACFS_TIMERS=()

# ============================================================
# Progress Display (for multi-phase installations)
# ============================================================

# Show installation progress header with visual progress bar
# Usage: show_progress_header $current_phase $total_phases $phase_name $start_time
if ! declare -f show_progress_header >/dev/null; then
    show_progress_header() {
        local current="$1"
        local total="$2"
        local name="$3"
        local start_time="${4:-0}"

        # Calculate percentage
        local percent=$((current * 100 / total))

        # Calculate elapsed time
        local elapsed=0
        if [[ "$start_time" -gt 0 ]]; then
            elapsed=$(($(date +%s) - start_time))
        fi
        local elapsed_min=$((elapsed / 60))
        local elapsed_sec=$((elapsed % 60))

        # Build progress bar (20 chars)
        local filled=$((percent / 5))
        local empty=$((20 - filled))
        local bar=""
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=0; i<empty; i++)); do bar+="░"; done

        # Truncate name if too long (max 50 chars to fit padding)
        local display_name="$name"
        if [[ ${#display_name} -gt 50 ]]; then
            display_name="${display_name:0:47}..."
        fi

        # Print progress header (box is 65 chars wide, content is 63 chars)
        echo "" >&2
        echo "╔═══════════════════════════════════════════════════════════════╗" >&2
        # Progress line: "  Progress: [bar] 100%  (9/9)                 "
        # We need to ensure the right padding adapts to the length of (current/total).
        # Fixed width for the progress text part: 20 (bar) + 6 (percent) + variable (counts)
        # Using printf * after the bar to pad the rest of the line.
        
        # Construct the progress detail string first: " 100%  (9/9)"
        local prog_detail
        printf -v prog_detail " %3d%%  (%d/%d)" "$percent" "$current" "$total"
        
        # Calculate padding needed to fill the rest of the 63-char content area minus "  Progress: [" and "]"
        # "  Progress: [" is 13 chars. "]" is 1 char. Total 14 chars.
        # Bar is 20 chars.
        # 63 - 14 - 20 = 29 chars remaining for prog_detail + padding.
        local detail_len=${#prog_detail}
        local pad_len=$((29 - detail_len))
        local padding=""
        if [[ $pad_len -gt 0 ]]; then
            padding=$(printf "%${pad_len}s" "")
        fi

        echo -e "║  Progress: [${bar}]${prog_detail}${padding} ║" >&2
        printf "║  Current:  %-50s ║\n" "$display_name" >&2
        printf "║  Elapsed:  %3dm %02ds                                           ║\n" \
               "$elapsed_min" "$elapsed_sec" >&2
        echo "╚═══════════════════════════════════════════════════════════════╝" >&2
        echo "" >&2
    }
fi

# Show installation completion message
# Usage: show_completion $total_phases $total_seconds
if ! declare -f show_completion >/dev/null; then
    show_completion() {
        local total="$1"
        local total_seconds="${2:-0}"
        local min=$((total_seconds / 60))
        local sec=$((total_seconds % 60))

        echo "" >&2
        echo "╔═══════════════════════════════════════════════════════════════╗" >&2
        echo "║              ✓ Installation Complete!                         ║" >&2
        echo "╠═══════════════════════════════════════════════════════════════╣" >&2
        printf "║  Total time: %3dm %02ds                                         ║\n" "$min" "$sec" >&2
        
        # Dynamic padding for "Phases completed: X/Y"
        # Label "  Phases completed: " is 20 chars.
        # Box width 63 chars. Remaining: 43 chars.
        local counts
        counts="$total/$total"
        local counts_len=${#counts}
        local pad_len=$((43 - counts_len))
        local padding=""
        if [[ $pad_len -gt 0 ]]; then
            padding=$(printf "%${pad_len}s" "")
        fi
        
        echo -e "║  Phases completed: ${counts}${padding}║" >&2
        echo "║                                                               ║" >&2
        echo "║  NEXT STEPS:                                                  ║" >&2
        echo "║  1. Type 'exit' to disconnect                                 ║" >&2
        local ssh_user="${TARGET_USER:-ubuntu}"
        local ssh_target="${ssh_user}@YOUR_IP"
        local reconnect_line="  2. Reconnect: ssh -i ~/.ssh/acfs_ed25519 ${ssh_target}"
        local reconnect_pad_len=$((63 - ${#reconnect_line}))
        local reconnect_padding=""
        if [[ $reconnect_pad_len -gt 0 ]]; then
            reconnect_padding=$(printf "%${reconnect_pad_len}s" "")
        fi
        echo -e "║${reconnect_line}${reconnect_padding}║" >&2
        echo "║  3. Start coding: type 'cc' for Claude Code                   ║" >&2
        echo "╚═══════════════════════════════════════════════════════════════╝" >&2
        echo "" >&2
    }
fi

# Start a timed operation (for performance tracking)
# Usage: timer_start "operation_name"
if ! declare -f timer_start >/dev/null; then
    timer_start() {
        local name="$1"
        ACFS_TIMERS["$name"]=$(date +%s)
    }
fi

# End a timed operation and log duration
# Usage: timer_end "operation_name"
if ! declare -f timer_end >/dev/null; then
    timer_end() {
        local name="$1"
        local start="${ACFS_TIMERS[$name]:-$(date +%s)}"
        local end
        end=$(date +%s)
        local duration=$((end - start))

        log_detail "Completed in ${duration}s"
    }
fi
