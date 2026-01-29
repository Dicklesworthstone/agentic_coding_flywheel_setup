#!/bin/bash
# ACFS Auto-Fix: Unattended-Upgrades Conflict Resolution
# Handles apt lock conflicts caused by unattended-upgrades service
# Integrates with change recording system from autofix.sh

# Prevent multiple sourcing
[[ -n "${_ACFS_AUTOFIX_UNATTENDED_SOURCED:-}" ]] && return 0
_ACFS_AUTOFIX_UNATTENDED_SOURCED=1

# Source the core autofix module
_AUTOFIX_UNATTENDED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=autofix.sh
source "${_AUTOFIX_UNATTENDED_DIR}/autofix.sh"

# =============================================================================
# Constants
# =============================================================================

readonly AUTOFIX_UNATTENDED_TIMEOUT="${AUTOFIX_UNATTENDED_TIMEOUT:-30}"
readonly AUTOFIX_UNATTENDED_POLL_INTERVAL=2

# Lock files that apt/dpkg can hold
readonly -a APT_LOCK_FILES=(
    "/var/lib/apt/lists/lock"
    "/var/lib/dpkg/lock"
    "/var/lib/dpkg/lock-frontend"
    "/var/cache/apt/archives/lock"
)

# =============================================================================
# Detection Functions
# =============================================================================

# Check if unattended-upgrades is causing issues
# Returns JSON with status and details
autofix_unattended_upgrades_check() {
    local status="none"
    local details=""
    local -a held_locks=()
    local apt_pids=""

    # Check if service is active
    if systemctl is-active unattended-upgrades &>/dev/null; then
        status="active"
        details="Service is running"
    fi

    # Check for lock files being held
    for lock in "${APT_LOCK_FILES[@]}"; do
        if [[ -f "$lock" ]] && fuser "$lock" &>/dev/null 2>&1; then
            held_locks+=("$lock")
        fi
    done

    if [[ ${#held_locks[@]} -gt 0 ]]; then
        status="locks_held"
        details="Locks held: ${held_locks[*]}"
    fi

    # Check for running apt/dpkg processes
    apt_pids=$(pgrep -x "apt|apt-get|dpkg|aptitude" 2>/dev/null | tr '\n' ' ' | xargs)
    if [[ -n "$apt_pids" ]]; then
        status="processes_running"
        details="Running PIDs: $apt_pids"
    fi

    # Output JSON for structured handling
    local locks_json
    if [[ ${#held_locks[@]} -gt 0 ]]; then
        locks_json=$(printf '%s\n' "${held_locks[@]}" | jq -R . | jq -s .)
    else
        locks_json="[]"
    fi

    jq -n \
        --arg status "$status" \
        --arg details "$details" \
        --argjson locks "$locks_json" \
        --arg pids "$apt_pids" \
        '{status: $status, details: $details, held_locks: $locks, apt_pids: $pids}'
}

# Quick check - returns 0 if there are issues to fix, 1 if clean
autofix_unattended_upgrades_needs_fix() {
    local check_result
    check_result=$(autofix_unattended_upgrades_check)
    local status
    status=$(echo "$check_result" | jq -r '.status')

    [[ "$status" != "none" ]]
}

# =============================================================================
# Fix Functions
# =============================================================================

# Main fix function
# Arguments:
#   $1 - mode: "fix" (default) or "dry-run"
# Returns:
#   0 - success
#   1 - partial fix (some issues remain)
#   2 - failed
autofix_unattended_upgrades_fix() {
    local mode="${1:-fix}"
    local errors=0

    log_info "[AUTO-FIX:unattended] Starting unattended-upgrades fix (mode=$mode)"

    # Get current state
    local check_result
    check_result=$(autofix_unattended_upgrades_check)
    local status
    status=$(echo "$check_result" | jq -r '.status')

    if [[ "$status" == "none" ]]; then
        log_info "[AUTO-FIX:unattended] No issues detected"
        return 0
    fi

    log_info "[AUTO-FIX:unattended] Detected status: $status"
    log_info "[AUTO-FIX:unattended] Details: $(echo "$check_result" | jq -r '.details')"

    if [[ "$mode" == "dry-run" ]]; then
        log_info "[DRY-RUN] Would stop unattended-upgrades service"
        log_info "[DRY-RUN] Would wait up to ${AUTOFIX_UNATTENDED_TIMEOUT}s for apt/dpkg to finish"
        log_info "[DRY-RUN] Would kill stuck apt/dpkg processes if timeout exceeded"
        log_info "[DRY-RUN] Would remove stale lock files"
        log_info "[DRY-RUN] Would run dpkg --configure -a"
        log_info "[DRY-RUN] Would run apt-get update"
        return 0
    fi

    # STEP 1: Stop unattended-upgrades service
    if ! _autofix_stop_unattended_service; then
        ((errors++))
    fi

    # STEP 2: Wait for running processes to finish (with timeout)
    if ! _autofix_wait_for_apt_processes; then
        # STEP 3: Kill stuck processes if still running after timeout
        if ! _autofix_kill_stuck_processes; then
            ((errors++))
        fi
    fi

    # STEP 4: Remove stale lock files
    if ! _autofix_remove_stale_locks; then
        ((errors++))
    fi

    # STEP 5: Reconfigure dpkg in case it was interrupted
    if ! _autofix_reconfigure_dpkg; then
        ((errors++))
    fi

    # STEP 6: Update apt lists
    if ! _autofix_update_apt; then
        ((errors++))
    fi

    if [[ $errors -eq 0 ]]; then
        log_info "[AUTO-FIX:unattended] Fix completed successfully"
        return 0
    elif [[ $errors -lt 3 ]]; then
        log_warn "[AUTO-FIX:unattended] Fix completed with $errors warnings"
        return 1
    else
        log_error "[AUTO-FIX:unattended] Fix failed with $errors errors"
        return 2
    fi
}

# Stop unattended-upgrades service
_autofix_stop_unattended_service() {
    if ! systemctl is-active unattended-upgrades &>/dev/null; then
        log_debug "[AUTO-FIX:unattended] Service not active, skipping stop"
        return 0
    fi

    # Check if service was enabled (for potential restore)
    local was_enabled="false"
    if systemctl is-enabled unattended-upgrades &>/dev/null; then
        was_enabled="true"
    fi

    # Record the change
    record_change \
        "unattended" \
        "Stopped unattended-upgrades service (was_enabled=$was_enabled)" \
        "sudo systemctl start unattended-upgrades" \
        true \
        "warning" \
        '[]' \
        '[]' \
        '[]'

    if sudo systemctl stop unattended-upgrades 2>&1; then
        log_info "[AUTO-FIX:unattended] Stopped unattended-upgrades service"
        return 0
    else
        log_error "[AUTO-FIX:unattended] Failed to stop unattended-upgrades service"
        return 1
    fi
}

# Wait for apt/dpkg processes to finish naturally
_autofix_wait_for_apt_processes() {
    local waited=0

    while pgrep -x "apt\|apt-get\|dpkg" &>/dev/null && [[ $waited -lt $AUTOFIX_UNATTENDED_TIMEOUT ]]; do
        log_info "[AUTO-FIX:unattended] Waiting for apt/dpkg to finish... (${waited}s/${AUTOFIX_UNATTENDED_TIMEOUT}s)"
        sleep "$AUTOFIX_UNATTENDED_POLL_INTERVAL"
        ((waited += AUTOFIX_UNATTENDED_POLL_INTERVAL))
    done

    # Return 0 if processes finished, 1 if still running (need to kill)
    if pgrep -x "apt\|apt-get\|dpkg" &>/dev/null; then
        log_warn "[AUTO-FIX:unattended] Timeout reached, processes still running"
        return 1
    fi

    log_debug "[AUTO-FIX:unattended] All apt/dpkg processes finished naturally"
    return 0
}

# Kill stuck apt/dpkg processes
_autofix_kill_stuck_processes() {
    local stuck_pids
    stuck_pids=$(pgrep -x "apt\|apt-get\|dpkg" 2>/dev/null | tr '\n' ' ' | xargs)

    if [[ -z "$stuck_pids" ]]; then
        return 0
    fi

    log_warn "[AUTO-FIX:unattended] Killing stuck processes: $stuck_pids"

    # Record the change (no undo needed - processes were stuck)
    record_change \
        "unattended" \
        "Killed stuck apt/dpkg processes (PIDs: $stuck_pids)" \
        "# No undo needed - processes were stuck" \
        true \
        "warning" \
        '[]' \
        '[]' \
        '[]'

    # Kill each process type
    sudo pkill -9 -x "apt" 2>/dev/null || true
    sudo pkill -9 -x "apt-get" 2>/dev/null || true
    sudo pkill -9 -x "dpkg" 2>/dev/null || true

    # Brief wait for processes to die
    sleep 2

    # Verify processes are gone
    if pgrep -x "apt\|apt-get\|dpkg" &>/dev/null; then
        log_error "[AUTO-FIX:unattended] Some processes still running after kill"
        return 1
    fi

    log_info "[AUTO-FIX:unattended] Successfully killed stuck processes"
    return 0
}

# Remove stale lock files (only if not actively held)
_autofix_remove_stale_locks() {
    local removed=0
    local failed=0

    for lock in "${APT_LOCK_FILES[@]}"; do
        if [[ ! -f "$lock" ]]; then
            continue
        fi

        # Check if lock is actively held
        if fuser "$lock" &>/dev/null 2>&1; then
            log_debug "[AUTO-FIX:unattended] Lock still held, skipping: $lock"
            continue
        fi

        # Record the change
        record_change \
            "unattended" \
            "Removed stale lock file: $lock" \
            "# Lock files are recreated automatically by apt" \
            true \
            "info" \
            "[\"$lock\"]" \
            '[]' \
            '[]'

        if sudo rm -f "$lock" 2>&1; then
            log_info "[AUTO-FIX:unattended] Removed stale lock: $lock"
            ((removed++))
        else
            log_error "[AUTO-FIX:unattended] Failed to remove lock: $lock"
            ((failed++))
        fi
    done

    if [[ $removed -gt 0 ]]; then
        log_info "[AUTO-FIX:unattended] Removed $removed stale lock file(s)"
    fi

    [[ $failed -eq 0 ]]
}

# Reconfigure dpkg in case it was interrupted
_autofix_reconfigure_dpkg() {
    log_info "[AUTO-FIX:unattended] Running dpkg --configure -a"

    local output
    if output=$(sudo dpkg --configure -a 2>&1); then
        if [[ -n "$output" ]]; then
            while IFS= read -r line; do
                log_debug "[dpkg:configure] $line"
            done <<< "$output"
        fi
        return 0
    else
        log_error "[AUTO-FIX:unattended] dpkg --configure -a failed"
        log_error "$output"
        return 1
    fi
}

# Update apt package lists
_autofix_update_apt() {
    log_info "[AUTO-FIX:unattended] Running apt-get update"

    local output
    if output=$(sudo apt-get update 2>&1); then
        if [[ -n "$output" ]]; then
            while IFS= read -r line; do
                log_debug "[apt:update] $line"
            done <<< "$output"
        fi
        return 0
    else
        log_warn "[AUTO-FIX:unattended] apt-get update had issues (may be non-fatal)"
        log_debug "$output"
        # Return success even on minor apt-get update issues
        return 0
    fi
}

# =============================================================================
# Restore Functions
# =============================================================================

# Re-enable unattended-upgrades after installation completes
# Called at end of ACFS installation to restore normal operation
autofix_unattended_upgrades_restore() {
    # Check if we stopped unattended-upgrades during this session
    if [[ ! -f "$ACFS_CHANGES_FILE" ]]; then
        log_debug "[POST-INSTALL] No changes file, nothing to restore"
        return 0
    fi

    local session_changes
    session_changes=$(grep '"category":"unattended"' "$ACFS_CHANGES_FILE" 2>/dev/null | \
                      grep -v '"auto_restored"' || true)

    if [[ -z "$session_changes" ]]; then
        log_debug "[POST-INSTALL] No unattended-upgrades changes to restore"
        return 0
    fi

    log_info "[POST-INSTALL] Re-enabling unattended-upgrades service"

    if sudo systemctl start unattended-upgrades 2>&1; then
        # Mark as auto-restored in undos file
        local restore_record
        restore_record=$(jq -cn \
            --arg ts "$(date -Iseconds)" \
            '{auto_restored: "unattended-upgrades", timestamp: $ts}')

        append_atomic "$ACFS_UNDOS_FILE" "$restore_record"
        log_info "[POST-INSTALL] Successfully re-enabled unattended-upgrades"
        return 0
    else
        log_warn "[POST-INSTALL] Could not re-enable unattended-upgrades (may need manual intervention)"
        return 1
    fi
}

# =============================================================================
# CLI Interface
# =============================================================================

# Run when script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-check}" in
        check)
            autofix_unattended_upgrades_check
            ;;
        needs-fix)
            if autofix_unattended_upgrades_needs_fix; then
                echo "true"
                exit 0
            else
                echo "false"
                exit 1
            fi
            ;;
        fix)
            autofix_unattended_upgrades_fix "fix"
            ;;
        dry-run)
            autofix_unattended_upgrades_fix "dry-run"
            ;;
        restore)
            autofix_unattended_upgrades_restore
            ;;
        *)
            echo "Usage: $0 {check|needs-fix|fix|dry-run|restore}"
            echo ""
            echo "Commands:"
            echo "  check     Output JSON status of unattended-upgrades issues"
            echo "  needs-fix Exit 0 if fixes needed, 1 if clean"
            echo "  fix       Apply fixes to resolve conflicts"
            echo "  dry-run   Show what would be done without making changes"
            echo "  restore   Re-enable service after installation"
            exit 1
            ;;
    esac
fi
