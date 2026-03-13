#!/usr/bin/env bash
# ============================================================
# ACFS Continue - View Installation Progress
#
# This script allows users to monitor ongoing ACFS installation
# progress, especially after Ubuntu upgrades complete and the
# installer continues in the background.
#
# Usage:
#   acfs continue           # Show status and attach to logs
#   acfs continue --status  # Just show current status
#   acfs continue --help    # Show help
#
# Related bead: hun4
# ============================================================

set -euo pipefail

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACFS_LOG_DIR="/var/log/acfs"
ACFS_INSTALL_LOG="${ACFS_LOG_DIR}/install.log"
ACFS_UPGRADE_LOG="${ACFS_LOG_DIR}/upgrade_resume.log"
ACFS_SYSTEM_STATE_FILE="/var/lib/acfs/state.json"
_CONTINUE_EXPLICIT_ACFS_HOME="${ACFS_HOME:-}"
_CONTINUE_DEFAULT_ACFS_HOME="$HOME/.acfs"
SERVICE_NAME="acfs-upgrade-resume"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ============================================================
# Helper Functions
# ============================================================

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}ACFS Installation Progress${NC}                                 ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Check if the upgrade service is running
is_upgrade_service_running() {
    systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null
}

# Check if the installer process is running
is_installer_running() {
    # Only trust ACFS-specific continuation surfaces here. Generic install.sh
    # pgrep patterns can match unrelated installers and the probe process
    # itself, causing false "running" reports.
    is_continuation_running
}

is_continuation_running() {
    pgrep -f "bash.*/var/lib/acfs/continue_install.sh" &>/dev/null || \
    pgrep -f "acfs-continue-install" &>/dev/null
}

home_for_user() {
    local user="$1"
    local passwd_entry=""

    [[ -n "$user" ]] || return 1

    if command -v getent &>/dev/null; then
        passwd_entry=$(getent passwd "$user" 2>/dev/null || true)
        if [[ -n "$passwd_entry" ]]; then
            printf '%s\n' "$(printf '%s\n' "$passwd_entry" | cut -d: -f6)"
            return 0
        fi
    fi

    if [[ "$user" == "root" ]]; then
        echo "/root"
        return 0
    fi

    if [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "/home/$user"
        return 0
    fi

    return 1
}

read_target_user_from_state() {
    local state_file="${1:-$ACFS_SYSTEM_STATE_FILE}"
    local target_user=""

    [[ -f "$state_file" ]] || return 1

    if command -v jq &>/dev/null; then
        target_user=$(jq -r '.target_user // empty' "$state_file" 2>/dev/null || true)
    else
        target_user=$(sed -n 's/.*"target_user"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$state_file" 2>/dev/null | head -n 1)
    fi

    [[ -n "$target_user" ]] && [[ "$target_user" != "null" ]] || return 1
    echo "$target_user"
}

script_acfs_home() {
    local candidate=""
    candidate=$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd) || return 1
    [[ "$(basename "$candidate")" == ".acfs" ]] || return 1
    printf '%s\n' "$candidate"
}

current_user_state_file() {
    printf '%s/state.json\n' "$_CONTINUE_DEFAULT_ACFS_HOME"
}

find_scanned_install_state_file() {
    local candidate=""
    local matches=()
    local newest=""
    local newest_mtime=-1
    local mtime=""

    shopt -s nullglob
    for candidate in /home/*/.acfs/state.json; do
        [[ -f "$candidate" ]] || continue
        matches+=("$candidate")
    done
    shopt -u nullglob

    if [[ ${#matches[@]} -eq 1 ]]; then
        echo "${matches[0]}"
        return 0
    fi

    for candidate in "${matches[@]}"; do
        mtime=$(stat -c %Y "$candidate" 2>/dev/null || stat -f %m "$candidate" 2>/dev/null || echo 0)
        if [[ "$mtime" =~ ^[0-9]+$ ]] && (( mtime > newest_mtime )); then
            newest="$candidate"
            newest_mtime="$mtime"
        fi
    done

    [[ -n "$newest" ]] || return 1
    echo "$newest"
}

get_install_state_file() {
    local candidate=""
    local target_user=""
    local target_home=""

    if [[ -n "${ACFS_STATE_FILE:-}" ]] && [[ -f "${ACFS_STATE_FILE}" ]] && [[ "${ACFS_STATE_FILE}" != "$ACFS_SYSTEM_STATE_FILE" ]]; then
        echo "$ACFS_STATE_FILE"
        return 0
    fi

    if [[ -n "$_CONTINUE_EXPLICIT_ACFS_HOME" ]] && [[ -f "$_CONTINUE_EXPLICIT_ACFS_HOME/state.json" ]]; then
        echo "$_CONTINUE_EXPLICIT_ACFS_HOME/state.json"
        return 0
    fi

    candidate=$(script_acfs_home 2>/dev/null || true)
    if [[ -n "$candidate" ]] && [[ -f "$candidate/state.json" ]]; then
        echo "$candidate/state.json"
        return 0
    fi

    candidate=$(current_user_state_file)
    if [[ -f "$candidate" ]]; then
        echo "$candidate"
        return 0
    fi

    if [[ -n "${SUDO_USER:-}" ]]; then
        target_home=$(home_for_user "$SUDO_USER" || true)
        candidate="${target_home}/.acfs/state.json"
        if [[ -n "$target_home" ]] && [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    fi

    target_user=$(read_target_user_from_state "$ACFS_SYSTEM_STATE_FILE" || true)
    if [[ -n "$target_user" ]]; then
        target_home=$(home_for_user "$target_user" || true)
        candidate="${target_home}/.acfs/state.json"
        if [[ -n "$target_home" ]] && [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    fi

    candidate=$(find_scanned_install_state_file || true)
    if [[ -n "$candidate" ]]; then
        echo "$candidate"
        return 0
    fi

    return 1
}

# Select the correct state file based on query key.
#
# Rationale:
# - Install progress is tracked in ~/.acfs/state.json (user state).
# - Ubuntu upgrade progress is tracked in /var/lib/acfs/state.json (system state).
# If both exist, we must avoid letting the system state mask install status.
select_state_file_for_key() {
    local key="$1"
    local install_state_file=""
    local candidate=""

    if [[ "$key" == *"ubuntu_upgrade"* ]]; then
        if [[ -f "$ACFS_SYSTEM_STATE_FILE" ]]; then
            echo "$ACFS_SYSTEM_STATE_FILE"
            return 0
        fi
        install_state_file=$(get_install_state_file || true)
        if [[ -n "$install_state_file" ]]; then
            echo "$install_state_file"
            return 0
        fi
    else
        install_state_file=$(get_install_state_file || true)
        if [[ -n "$install_state_file" ]]; then
            echo "$install_state_file"
            return 0
        fi
        if [[ -f "$ACFS_SYSTEM_STATE_FILE" ]]; then
            echo "$ACFS_SYSTEM_STATE_FILE"
            return 0
        fi
    fi

    candidate=$(current_user_state_file)
    if [[ -f "$candidate" ]]; then
        echo "$candidate"
        return 0
    fi

    return 1
}

# Get state from state.json
get_state_value() {
    local key="$1"
    local state_file=""

    # In set -e mode, failing command substitutions can abort the script.
    # Treat missing state/jq as "no value" so callers can fall back gracefully.
    state_file=$(select_state_file_for_key "$key") || { echo ""; return 0; }

    command -v jq &>/dev/null || { echo ""; return 0; }

    # Never crash on jq errors (schema drift / partial state files during boot).
    jq -r "$key" "$state_file" 2>/dev/null || true
}

# Get current phase info
get_current_phase() {
    local phase
    phase=$(get_state_value '.current_phase.id? // .current_phase // empty')
    if [[ -n "$phase" ]]; then
        echo "$phase"
    else
        echo "unknown"
    fi
}

# Get current step info
get_current_step() {
    local step
    step=$(get_state_value '.current_step // empty')
    if [[ -n "$step" ]]; then
        echo "$step"
    else
        echo ""
    fi
}

get_failed_phase() {
    local phase
    phase=$(get_state_value '.failed_phase // empty')
    if [[ -n "$phase" ]] && [[ "$phase" != "null" ]]; then
        echo "$phase"
    else
        echo ""
    fi
}

get_failed_step() {
    local step
    step=$(get_state_value '.failed_step // empty')
    if [[ -n "$step" ]] && [[ "$step" != "null" ]]; then
        echo "$step"
    else
        echo ""
    fi
}

# Get installation status
get_install_status() {
    local failed_phase current_phase finalize_completed
    failed_phase=$(get_state_value '.failed_phase // empty')
    if [[ -n "$failed_phase" ]] && [[ "$failed_phase" != "null" ]]; then
        echo "failed"
        return 0
    fi

    finalize_completed=$(get_state_value '(.completed_phases // []) | index("finalize") != null')
    if [[ "$finalize_completed" == "true" ]]; then
        echo "complete"
        return 0
    fi

    current_phase=$(get_state_value '.current_phase.id? // .current_phase // empty')
    if [[ -n "$current_phase" ]] && [[ "$current_phase" != "null" ]]; then
        echo "running"
        return 0
    fi

    echo "unknown"
}

# Get Ubuntu upgrade status
get_upgrade_status() {
    local stage
    stage=$(get_state_value '.ubuntu_upgrade.current_stage // empty')
    if [[ -n "$stage" ]]; then
        echo "$stage"
    else
        echo ""
    fi
}

get_latest_install_log() {
    local install_state_file=""
    local install_root=""
    local latest_log=""

    install_state_file=$(get_install_state_file || true)
    if [[ -n "$install_state_file" ]]; then
        install_root="$(dirname "$install_state_file")"
        latest_log=$(
            find "$install_root/logs" -maxdepth 1 -type f -name 'install-*.log' -printf '%T@ %p\n' 2>/dev/null \
                | sort -nr \
                | head -n 1 \
                | cut -d' ' -f2-
        )
        if [[ -n "$latest_log" ]] && [[ -f "$latest_log" ]]; then
            echo "$latest_log"
            return 0
        fi
    fi

    if [[ -f "$ACFS_INSTALL_LOG" ]]; then
        echo "$ACFS_INSTALL_LOG"
        return 0
    fi

    return 1
}

# Determine which log file to tail
get_active_log() {
    local upgrade_stage
    local install_log=""
    upgrade_stage=$(get_upgrade_status)
    install_log=$(get_latest_install_log || true)

    # If upgrade is in progress, or continuation is still running under the
    # upgrade wrapper, prefer the upgrade log.
    if [[ -n "$upgrade_stage" ]] && [[ -f "$ACFS_UPGRADE_LOG" ]] && \
       { [[ "$upgrade_stage" != "completed" ]] || is_upgrade_service_running || is_continuation_running; }; then
        if [[ -f "$ACFS_UPGRADE_LOG" ]]; then
            echo "$ACFS_UPGRADE_LOG"
            return 0
        fi
    fi

    if [[ -n "$install_log" ]]; then
        echo "$install_log"
        return 0
    fi

    # Check for any log file
    if [[ -f "$ACFS_UPGRADE_LOG" ]]; then
        echo "$ACFS_UPGRADE_LOG"
        return 0
    fi

    return 1
}

get_log_root_hint() {
    local install_state_file=""
    local install_root=""

    install_state_file=$(get_install_state_file || true)
    if [[ -n "$install_state_file" ]]; then
        install_root="$(dirname "$install_state_file")"
        if [[ -d "$install_root/logs" ]] || [[ "$install_root" != "/var/lib/acfs" ]]; then
            printf '%s/logs\n' "$install_root"
            return 0
        fi
    fi

    printf '%s\n' "$ACFS_LOG_DIR"
}

print_log_locations() {
    local install_log=""
    local have_logs=false

    install_log=$(get_latest_install_log || true)
    if [[ -n "$install_log" ]]; then
        have_logs=true
    fi
    if [[ -f "$ACFS_UPGRADE_LOG" ]]; then
        have_logs=true
    fi

    $have_logs || return 1

    echo -e "  ${DIM}Log files:${NC}"
    if [[ -n "$install_log" ]]; then
        echo -e "    ${DIM}Install:  $install_log${NC}"
    fi
    if [[ -f "$ACFS_UPGRADE_LOG" ]]; then
        echo -e "    ${DIM}Upgrade:  $ACFS_UPGRADE_LOG${NC}"
    fi
    echo ""
}

# ============================================================
# Status Display
# ============================================================

show_status() {
    print_header

    local is_running=false
    local status_msg=""
    local install_status
    install_status=$(get_install_status)

    # Persisted failure should win over loose runtime probes to avoid
    # contradictory output such as "in progress" with failure details below.
    if is_upgrade_service_running; then
        is_running=true
        status_msg="${YELLOW}Ubuntu upgrade in progress${NC}"
    elif [[ "$install_status" == "failed" ]]; then
        status_msg="${RED}Installation failed${NC}"
    elif is_installer_running; then
        is_running=true
        status_msg="${BLUE}Installation in progress${NC}"
    else
        case "$install_status" in
            running)
                is_running=true
                status_msg="${BLUE}Installation in progress${NC}"
                ;;
            failed)
                status_msg="${RED}Installation failed${NC}"
                ;;
            complete)
                status_msg="${GREEN}Installation complete${NC}"
                ;;
            *)
                status_msg="${GREEN}No active installation${NC}"
                ;;
        esac
    fi

    echo -e "  ${BOLD}Status:${NC} $status_msg"

    if [[ "$is_running" == "true" ]]; then
        # Show current phase only when installation is actually active.
        local phase
        phase=$(get_current_phase)
        if [[ "$phase" != "unknown" ]]; then
            echo -e "  ${BOLD}Phase:${NC}  $phase"
        fi

        # Show current step only when installation is actually active.
        local step
        step=$(get_current_step)
        if [[ -n "$step" ]]; then
            echo -e "  ${BOLD}Step:${NC}   $step"
        fi
    fi

    if [[ "$install_status" == "failed" ]]; then
        local failed_phase failed_step
        failed_phase=$(get_failed_phase)
        failed_step=$(get_failed_step)

        if [[ -n "$failed_phase" ]]; then
            echo -e "  ${BOLD}Failed:${NC} Phase: ${RED}$failed_phase${NC}"
        fi
        if [[ -n "$failed_step" ]]; then
            echo -e "  ${BOLD}Cause:${NC}  Step: ${RED}$failed_step${NC}"
        fi
    fi

    # Show upgrade status if relevant
    local upgrade_stage
    upgrade_stage=$(get_upgrade_status)
    if [[ -n "$upgrade_stage" ]] && [[ "$upgrade_stage" != "completed" ]]; then
        echo -e "  ${BOLD}Ubuntu:${NC} Upgrade stage: ${YELLOW}$upgrade_stage${NC}"
    fi

    echo ""

    print_log_locations || true

    # Return whether installation is running
    $is_running
}

# ============================================================
# Live Log Viewing
# ============================================================

show_live_log() {
    local log_file
    local log_root_hint=""
    log_file=$(get_active_log) || {
        log_root_hint=$(get_log_root_hint)
        echo -e "${YELLOW}No log files found yet.${NC}"
        echo -e "${DIM}Logs will appear at: $log_root_hint${NC}"
        return 1
    }

    echo -e "${BOLD}Showing live output from:${NC} $log_file"
    echo -e "${DIM}Press Ctrl+C to stop watching${NC}"
    echo ""
    echo "────────────────────────────────────────────────────────────────"

    # Use tail -f to show live output
    # Show last 20 lines first, then follow
    tail -n 20 -f "$log_file" 2>/dev/null || {
        echo -e "${RED}Unable to read log file${NC}"
        echo -e "${DIM}You may need to run with sudo: sudo acfs continue${NC}"
        return 1
    }
}

# ============================================================
# Help
# ============================================================

show_help() {
    echo "ACFS Continue - View Installation Progress"
    echo ""
    echo "Usage: acfs continue [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --status, -s    Show current status only (don't attach to logs)"
    echo "  --help, -h      Show this help message"
    echo ""
    echo "Description:"
    echo "  After Ubuntu upgrades complete, the ACFS installer continues"
    echo "  running in the background. This command lets you see what's"
    echo "  happening and attach to the live log output."
    echo ""
    echo "Examples:"
    echo "  acfs continue           # Show status and watch live logs"
    echo "  acfs continue --status  # Just show current status"
    echo "  sudo acfs continue      # If you get permission errors"
    echo ""
}

# ============================================================
# Main
# ============================================================

main() {
    local status_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status|-s)
                status_only=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                echo "Use 'acfs continue --help' for usage"
                exit 1
                ;;
        esac
    done

    # Show status
    if show_status; then
        # Installation is running
        if ! $status_only; then
            show_live_log
        fi
    else
        # Installation is not running - check if it was completed
        local status
        status=$(get_install_status)
        if [[ "$status" == "complete" ]]; then
            echo -e "${GREEN}${BOLD}Installation completed successfully!${NC}"
            echo ""
            echo "Next steps:"
            echo "  1. Log out and back in (or run: source ~/.zshrc)"
            echo "  2. Run: onboard"
            echo "  3. Start coding with: cc, cod, or gmi"
        elif [[ "$status" == "failed" ]]; then
            local failed_phase failed_step
            failed_phase=$(get_failed_phase)
            failed_step=$(get_failed_step)

            echo -e "${RED}${BOLD}Installation failed.${NC}"
            if [[ -n "$failed_phase" ]]; then
                echo "Failed phase: $failed_phase"
            fi
            if [[ -n "$failed_step" ]]; then
                echo "Failed step:  $failed_step"
            fi
            echo ""
            echo "Review the log files listed above, fix the underlying issue, then rerun the installer with --resume."
        else
            local install_log=""
            install_log=$(get_latest_install_log || true)

            # Only show log viewing instructions if logs exist
            if [[ -n "$install_log" ]] || [[ -f "$ACFS_UPGRADE_LOG" ]]; then
                echo "To view past logs:"
                if [[ -n "$install_log" ]]; then
                    echo "  cat $install_log"
                fi
                if [[ -f "$ACFS_UPGRADE_LOG" ]]; then
                    echo "  cat $ACFS_UPGRADE_LOG"
                fi
            else
                echo "No ACFS installation logs found."
                echo "Run the ACFS installer to get started."
            fi
        fi
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
