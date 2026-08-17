#!/usr/bin/env bash
# ============================================================
# ACFS Installer - Logging Library
# Provides consistent, colored output for the installer
# ============================================================

# ============================================================
# Log file capture (always defined, even when basic log funcs
# are skipped via _ACFS_LOGGING_SH_LOADED guard)
# ============================================================

# Initialize log file capture: tee stderr to a timestamped log file.
# Usage: acfs_log_init [log_directory]
# After calling, all stderr output is captured to ACFS_LOG_FILE.
# Call acfs_log_close to restore stderr and finalize the log.
if ! declare -f acfs_log_init >/dev/null 2>&1; then
    acfs_log_init() {
        local log_dir="${1:-${ACFS_HOME:+${ACFS_HOME}/logs}}"
        local saved_stderr_fd=""

        # Fallback if ACFS_HOME not set or empty
        if [[ -z "$log_dir" ]]; then
            log_dir="${ACFS_LOG_DIR:-/var/log/acfs}"
        fi

        ACFS_LOG_INITIALIZED=false
        ACFS_LOG_STDERR_CAPTURED=false
        ACFS_LOG_ORIGINAL_STDERR_FD=""

        # Create log directory
        mkdir -p "$log_dir" 2>/dev/null || return 1

        ACFS_LOG_FILE="${log_dir}/install-$(date +%Y%m%d_%H%M%S).log"
        export ACFS_LOG_FILE

        # Write log header
        {
            printf '=== ACFS Install Log ===\n'
            printf 'Started: %s\n' "$(date -Iseconds)"
            printf 'Version: %s\n' "${ACFS_VERSION:-unknown}"
            printf 'User: %s\n' "${TARGET_USER:-unknown}"
            printf 'Home: %s\n' "${TARGET_HOME:-unknown}"
            printf '========================\n\n'
        } > "$ACFS_LOG_FILE" 2>/dev/null || return 1
        ACFS_LOG_INITIALIZED=true

        # Fix ownership so target user can read logs
        if [[ -n "${TARGET_USER:-}" ]] && [[ "$(id -u)" -eq 0 ]]; then
            chown "${TARGET_USER}:${TARGET_USER}" "$log_dir" "$ACFS_LOG_FILE" 2>/dev/null || true
        fi

        # Tee stderr: all stderr output goes to both terminal and log file.
        # fd 3 = original stderr (preserved for terminal output).
        #
        # NOTE: Process substitution >(tee ...) can fail on some systems
        # (especially Ubuntu 25.04 with bash 5.3+). We test first and
        # fall back to simple file logging if it fails.
        local tee_logging_ok=false
        if command -v tee >/dev/null 2>&1; then
            # Test if process substitution works before committing to it.
            # On bash 5.3+, bare `exec` under set -e can exit the script
            # before `if` catches the failure, so we test in a subshell.
            if (exec 3>&1; echo test > >(cat >/dev/null)) 2>/dev/null; then
                # Save original stderr first. Use an ACFS-owned dynamic fd instead
                # of fd 3, because BATS and other callers may already own fd 3.
                if exec {saved_stderr_fd}>&2; then
                    ACFS_LOG_ORIGINAL_STDERR_FD="$saved_stderr_fd"
                fi
                # shellcheck disable=SC2261
                # Use set +e locally to prevent exec from exiting under bash 5.3+
                if [[ -n "$saved_stderr_fd" ]] && (set +e; exec 2> >(tee -a "$ACFS_LOG_FILE" >&"$saved_stderr_fd")) 2>/dev/null; then
                    if exec 2> >(tee -a "$ACFS_LOG_FILE" >&"$saved_stderr_fd"); then
                        tee_logging_ok=true
                        ACFS_LOG_STDERR_CAPTURED=true
                    fi
                fi
            fi
        fi

        if [[ "$tee_logging_ok" != "true" ]]; then
            if [[ -n "${ACFS_LOG_ORIGINAL_STDERR_FD:-}" ]]; then
                { exec {ACFS_LOG_ORIGINAL_STDERR_FD}>&-; } 2>/dev/null || true
                ACFS_LOG_ORIGINAL_STDERR_FD=""
            fi
            # Fallback: rely on explicit logging calls instead of automatic tee
            ACFS_LOG_FALLBACK=true
            export ACFS_LOG_FALLBACK
        fi
    }
fi

# Close log file capture and restore stderr.
# Strips ANSI color codes from the log for clean text output.
if ! declare -f acfs_log_close >/dev/null 2>&1; then
    acfs_log_close() {
        # Restore only an fd that acfs_log_init opened. Callers and test harnesses
        # often use fd 3 themselves; inheriting it must not make us redirect/close it.
        if [[ "${ACFS_LOG_STDERR_CAPTURED:-false}" == "true" && -n "${ACFS_LOG_ORIGINAL_STDERR_FD:-}" ]]; then
            exec 2>&"${ACFS_LOG_ORIGINAL_STDERR_FD}" || true
            { exec {ACFS_LOG_ORIGINAL_STDERR_FD}>&-; } 2>/dev/null || true
            ACFS_LOG_ORIGINAL_STDERR_FD=""
            ACFS_LOG_STDERR_CAPTURED=false
        fi

        if [[ "${ACFS_LOG_INITIALIZED:-false}" == "true" && -n "${ACFS_LOG_FILE:-}" && -f "$ACFS_LOG_FILE" ]]; then
            # Strip ANSI escape codes for clean log
            # Use -i.bak for portability (works on both GNU sed and BSD sed)
            sed -i.bak $'s/\033\[[0-9;]*m//g' "$ACFS_LOG_FILE" 2>/dev/null && rm -f "${ACFS_LOG_FILE}.bak" || true

            # Append footer
            {
                printf '\n========================\n'
                printf 'Finished: %s\n' "$(date -Iseconds)"
                printf '========================\n'
            } >> "$ACFS_LOG_FILE"

            # Fix ownership
            if [[ -n "${TARGET_USER:-}" ]] && [[ "$(id -u)" -eq 0 ]]; then
                chown "${TARGET_USER}:${TARGET_USER}" "$ACFS_LOG_FILE" 2>/dev/null || true
            fi
        fi
        ACFS_LOG_INITIALIZED=false
    }
fi

# Prevent multiple sourcing of basic log functions
if [[ -n "${_ACFS_LOGGING_SH_LOADED:-}" ]]; then
    return 0
fi
_ACFS_LOGGING_SH_LOADED=1

# ============================================================
# Color Support with NO_COLOR Standard (https://no-color.org/)
# ============================================================
#
# Respects:
# - NO_COLOR env var (any value = disable colors)
# - Non-TTY output (pipes, redirects)
#
# Related: bd-39ye

# Initialize colors based on environment
_acfs_init_colors() {
    # Disable colors if NO_COLOR is set (any value) or output is not a TTY
    if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 2 ]]; then
        # No colors - empty strings
        export ACFS_RED=''
        export ACFS_GREEN=''
        export ACFS_YELLOW=''
        export ACFS_BLUE=''
        export ACFS_GRAY=''
        export ACFS_NC=''
        export ACFS_COLORS_ENABLED=false
    else
        # Colors enabled
        export ACFS_RED='\033[0;31m'
        export ACFS_GREEN='\033[0;32m'
        export ACFS_YELLOW='\033[0;33m'
        export ACFS_BLUE='\033[0;34m'
        export ACFS_GRAY='\033[0;90m'
        export ACFS_NC='\033[0m'
        export ACFS_COLORS_ENABLED=true
    fi
}

# Initialize colors on first load
_acfs_init_colors

# Check if colors are enabled
# Usage: if acfs_colors_enabled; then echo "colors!"; fi
acfs_colors_enabled() {
    [[ "${ACFS_COLORS_ENABLED:-true}" == "true" ]]
}

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
        printf "${ACFS_GREEN}✓ %s${ACFS_NC}\n" "$1" >&2
    }
fi

# Log warning message (yellow with warning symbol)
# Usage: log_warn "This may take a while"
if ! declare -f log_warn >/dev/null; then
    log_warn() {
        printf "${ACFS_YELLOW}⚠ %s${ACFS_NC}\n" "$1" >&2
    }
fi

# Log sensitive warning message (tries to bypass log tee to avoid storing secrets)
# Usage: log_sensitive "Generated password for user: ..."
if ! declare -f log_sensitive >/dev/null; then
    log_sensitive() {
        local message="$1"

        # If stderr is being tee'd, write to the ACFS-owned saved stderr fd so
        # secrets still reach the operator without entering the install log.
        if [[ "${ACFS_LOG_STDERR_CAPTURED:-false}" == "true" ]] &&
            [[ "${ACFS_LOG_ORIGINAL_STDERR_FD:-}" =~ ^[0-9]+$ ]] &&
            { true >&"${ACFS_LOG_ORIGINAL_STDERR_FD}"; } 2>/dev/null; then
            printf "${ACFS_YELLOW}⚠ %s${ACFS_NC}\n" "$message" >&"${ACFS_LOG_ORIGINAL_STDERR_FD}"
            return 0
        fi

        # Fall back to /dev/tty when available to avoid log capture.
        if [[ -w /dev/tty ]] && printf "${ACFS_YELLOW}⚠ %s${ACFS_NC}\n" "$message" > /dev/tty 2>/dev/null; then
            return 0
        fi

        # Last resort: stderr (may be logged).
        printf "${ACFS_YELLOW}⚠ %s${ACFS_NC}\n" "$message" >&2
    }
fi

# Log error message (red with X)
# Usage: log_error "Failed to install package"
if ! declare -f log_error >/dev/null; then
    log_error() {
        printf "${ACFS_RED}✖ %s${ACFS_NC}\n" "$1" >&2
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
# Usage: show_progress_header $current_phase $total_phases $phase_name $start_time [$phase_id]
if ! declare -f show_progress_header >/dev/null; then
    show_progress_header() {
        local current="$1"
        local total="$2"
        local name="$3"
        local start_time="${4:-0}"
        local phase_id="${5:-}"

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
        
        # Construct the progress detail string: " 100%  (9/9)"
        local prog_detail
        printf -v prog_detail " %3d%%  (%d/%d)" "$percent" "$current" "$total"
        
        # Final progress line: "  Progress: [bar] 100%  (9/9)                 "
        # "  Progress: [" (13) + bar (20) + "]" (1) + prog_detail + padding + " ║"
        local visible_len=$((14 + 20 + ${#prog_detail}))
        local padding=""
        if [[ $visible_len -lt 62 ]]; then
            padding=$(printf '%*s' $((62 - visible_len)) "")
        fi
        printf "║  Progress: [%s]%s%s ║\n" "${bar}" "${prog_detail}" "${padding}" >&2

        # Completed phases line
        local counts="${current}/${total}"
        padding=""
        visible_len=$((21 + ${#counts}))
        if [[ $visible_len -lt 62 ]]; then
            padding=$(printf '%*s' $((62 - visible_len)) "")
        fi
        printf "║  Phases completed: %s%s║\n" "${counts}" "${padding}" >&2

        # Optional reconnection hint if we just finished a reboot-heavy phase
        if [[ "$name" == *"User Setup"* ]] || [[ "$name" == *"Reboot"* ]]; then
            local reconnect_line="  Tip: if SSH disconnected, just re-run install.sh"
            padding=""
            if [[ ${#reconnect_line} -lt 60 ]]; then
                padding=$(printf '%*s' $((60 - ${#reconnect_line})) "")
            fi
            printf "║%s%s║\n" "${reconnect_line}" "${padding}" >&2
        fi
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
        local start="${ACFS_TIMERS[$name]:-}"

        # If timer was never started, warn and skip duration logging
        if [[ -z "$start" ]]; then
            log_detail "Completed (no timing data)"
            return 0
        fi

        local end
        end=$(date +%s)
        local duration=$((end - start))

        log_detail "Completed in ${duration}s"
    }
fi
