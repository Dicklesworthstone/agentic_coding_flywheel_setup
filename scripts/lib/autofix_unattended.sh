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

readonly AUTOFIX_UNATTENDED_TIMEOUT="${AUTOFIX_UNATTENDED_TIMEOUT:-120}"
readonly AUTOFIX_UNATTENDED_POLL_INTERVAL=2

# Lock files that apt/dpkg can hold
readonly -a APT_LOCK_FILES=(
    "/var/lib/apt/lists/lock"
    "/var/lib/dpkg/lock"
    "/var/lib/dpkg/lock-frontend"
    "/var/cache/apt/archives/lock"
)

_autofix_unattended_binary_path() {
    autofix_system_binary_path "${1:-}"
}

_autofix_unattended_run_privileged() {
    local tool_path="${1:-}"
    local sudo_bin=""
    shift || return 1

    [[ -n "$tool_path" ]] || return 1
    if [[ $EUID -eq 0 ]]; then
        "$tool_path" "$@"
        return
    fi

    sudo_bin="$(_autofix_unattended_binary_path sudo 2>/dev/null || true)"
    if [[ -z "$sudo_bin" ]]; then
        log_error "[AUTO-FIX:unattended] sudo is required for package repair"
        return 1
    fi

    "$sudo_bin" "$tool_path" "$@"
}

# =============================================================================
# Detection Functions
# =============================================================================

# Check if unattended-upgrades is causing issues
# Returns JSON with status and details
autofix_unattended_upgrades_check() {
    local status="none"
    local details=""
    local -a held_locks=()
    local -a unavailable_tools=()
    local apt_pids=""
    local fuser_bin=""
    local jq_bin=""
    local lock=""
    local pgrep_bin=""
    local systemctl_bin=""

    systemctl_bin="$(_autofix_unattended_binary_path systemctl 2>/dev/null || true)"
    fuser_bin="$(_autofix_unattended_binary_path fuser 2>/dev/null || true)"
    jq_bin="$(_autofix_unattended_binary_path jq 2>/dev/null || true)"
    pgrep_bin="$(_autofix_unattended_binary_path pgrep 2>/dev/null || true)"

    [[ -n "$systemctl_bin" ]] || unavailable_tools+=("systemctl")
    [[ -n "$fuser_bin" ]] || unavailable_tools+=("fuser")
    [[ -n "$pgrep_bin" ]] || unavailable_tools+=("pgrep")
    if [[ -z "$jq_bin" ]]; then
        log_error "[AUTO-FIX:unattended] Cannot inspect package ownership because jq is unavailable"
        return 1
    fi

    # Check if service is active
    if [[ -n "$systemctl_bin" ]] && "$systemctl_bin" is-active unattended-upgrades &>/dev/null; then
        status="active"
        details="Service is running"
    fi

    # Check for lock files being held
    for lock in "${APT_LOCK_FILES[@]}"; do
        if [[ -n "$fuser_bin" ]] && [[ -f "$lock" ]] && "$fuser_bin" "$lock" >/dev/null 2>&1; then
            held_locks+=("$lock")
        fi
    done

    if [[ ${#held_locks[@]} -gt 0 ]]; then
        status="locks_held"
        details="Locks held: ${held_locks[*]}"
    fi

    # Check for running apt/dpkg processes
    if [[ -n "$pgrep_bin" ]]; then
        apt_pids=$("$pgrep_bin" -x "apt|apt-get|dpkg|aptitude|unattended-upgr|unattended-upgrade" 2>/dev/null || true)
        apt_pids="${apt_pids//$'\n'/ }"
    fi
    if [[ -n "$apt_pids" ]]; then
        status="processes_running"
        details="Running PIDs: $apt_pids"
    fi

    if [[ ${#unavailable_tools[@]} -gt 0 ]]; then
        status="inspection_unavailable"
        details="Cannot safely inspect package ownership; unavailable tools: ${unavailable_tools[*]}"
    fi

    # Output JSON for structured handling
    local locks_json
    if [[ ${#held_locks[@]} -gt 0 ]]; then
        if ! locks_json=$(printf '%s\n' "${held_locks[@]}" | "$jq_bin" -R . | "$jq_bin" -s .); then
            log_error "[AUTO-FIX:unattended] Failed to encode held-lock inspection data"
            return 1
        fi
    else
        locks_json="[]"
    fi

    "$jq_bin" -n \
        --arg status "$status" \
        --arg details "$details" \
        --argjson locks "$locks_json" \
        --arg pids "$apt_pids" \
        '{status: $status, details: $details, held_locks: $locks, apt_pids: $pids}'
}

# Quick check - returns 0 if there are issues to fix, 1 if clean
autofix_unattended_upgrades_needs_fix() {
    local check_result
    local jq_bin=""
    if ! check_result=$(autofix_unattended_upgrades_check); then
        return 0
    fi
    jq_bin="$(_autofix_unattended_binary_path jq 2>/dev/null || true)"
    [[ -n "$jq_bin" ]] || return 0
    local status
    if ! status=$(printf '%s\n' "$check_result" | "$jq_bin" -er '.status | strings' 2>/dev/null); then
        return 0
    fi

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
    local session_owned=false
    local result=0
    local jq_bin=""

    log_info "[AUTO-FIX:unattended] Starting unattended-upgrades fix (mode=$mode)"

    # Get current state
    local check_result
    if ! check_result=$(autofix_unattended_upgrades_check); then
        log_error "[AUTO-FIX:unattended] Could not establish package-manager ownership state"
        return 2
    fi
    jq_bin="$(_autofix_unattended_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        log_error "[AUTO-FIX:unattended] Cannot parse ownership state because jq is unavailable"
        return 2
    fi
    local status
    if ! status=$(printf '%s\n' "$check_result" | "$jq_bin" -er '.status | strings' 2>/dev/null); then
        log_error "[AUTO-FIX:unattended] Ownership inspection returned malformed status data"
        return 2
    fi

    if [[ "$status" == "none" ]]; then
        log_info "[AUTO-FIX:unattended] No issues detected"
        return 0
    fi

    log_info "[AUTO-FIX:unattended] Detected status: $status"
    log_info "[AUTO-FIX:unattended] Details: $(printf '%s\n' "$check_result" | "$jq_bin" -r '.details')"

    if [[ "$mode" == "dry-run" ]]; then
        log_info "[DRY-RUN] Would stop unattended-upgrades service"
        log_info "[DRY-RUN] Would wait up to ${AUTOFIX_UNATTENDED_TIMEOUT}s for apt/dpkg to finish"
        log_info "[DRY-RUN] Would refuse further mutation if an apt/dpkg owner remains live"
        log_info "[DRY-RUN] Would run dpkg --configure -a"
        log_info "[DRY-RUN] Would run apt-get update"
        return 0
    fi

    if [[ "$status" == "inspection_unavailable" ]]; then
        log_error "[AUTO-FIX:unattended] Refusing package repair without authoritative ownership probes"
        return 2
    fi

    if ! autofix_ensure_session session_owned; then
        log_error "[AUTO-FIX:unattended] Failed to start autofix session"
        return 2
    fi

    # STEP 1: Stop unattended-upgrades service
    if ! _autofix_stop_unattended_service; then
        log_error "[AUTO-FIX:unattended] Refusing package mutation because unattended-upgrades could not be stopped safely"
        if ! autofix_finalize_managed_session "$session_owned"; then
            log_error "[AUTO-FIX:unattended] Failed to finalize autofix session after service-stop failure"
        fi
        return 2
    fi

    # STEP 2: Wait for running processes to finish (with timeout). A process
    # that remains live is still the lock owner; never SIGKILL it or unlink its
    # lock files. Both actions can interrupt a transaction or create two lock
    # domains backed by different inodes.
    if ! _autofix_wait_for_apt_processes; then
        log_error "[AUTO-FIX:unattended] Refusing to mutate package state while apt/dpkg is still running"
        ((errors++)) || true
        if ! autofix_unattended_upgrades_restore; then
            ((errors++)) || true
        fi
    else
        # STEP 3: Reconfigure dpkg only after every prior owner has exited.
        if ! _autofix_reconfigure_dpkg; then
            ((errors++)) || true
        fi

        # STEP 4: Update apt lists with cooperative lock waiting.
        if ! _autofix_update_apt; then
            ((errors++)) || true
        fi
    fi

    if [[ $errors -eq 0 ]]; then
        log_info "[AUTO-FIX:unattended] Fix completed successfully"
        result=0
    elif [[ $errors -lt 3 ]]; then
        log_warn "[AUTO-FIX:unattended] Fix completed with $errors warnings"
        result=1
    else
        log_error "[AUTO-FIX:unattended] Fix failed with $errors errors"
        result=2
    fi

    if ! autofix_finalize_managed_session "$session_owned"; then
        log_error "[AUTO-FIX:unattended] Failed to finalize autofix session"
        return 2
    fi

    return "$result"
}

# Stop unattended-upgrades service
_autofix_stop_unattended_service() {
    local systemctl_bin=""
    local undo_command=""

    systemctl_bin="$(_autofix_unattended_binary_path systemctl 2>/dev/null || true)"
    if [[ -z "$systemctl_bin" ]]; then
        log_error "[AUTO-FIX:unattended] systemctl is unavailable"
        return 1
    fi

    if ! "$systemctl_bin" is-active unattended-upgrades &>/dev/null; then
        log_debug "[AUTO-FIX:unattended] Service not active, skipping stop"
        return 0
    fi

    # Check if service was enabled (for potential restore)
    local was_enabled="false"
    if "$systemctl_bin" is-enabled unattended-upgrades &>/dev/null; then
        was_enabled="true"
    fi

    printf -v undo_command '%q start unattended-upgrades' "$systemctl_bin"
    if [[ $EUID -ne 0 ]]; then
        local sudo_bin=""
        sudo_bin="$(_autofix_unattended_binary_path sudo 2>/dev/null || true)"
        if [[ -z "$sudo_bin" ]]; then
            log_error "[AUTO-FIX:unattended] sudo is required to stop unattended-upgrades"
            return 1
        fi
    fi

    if _autofix_unattended_run_privileged "$systemctl_bin" stop unattended-upgrades 2>&1; then
        if ! record_change \
            "unattended" \
            "Stopped unattended-upgrades service (was_enabled=$was_enabled)" \
            "$undo_command" \
            true \
            "warning" \
            '[]' \
            '[]' \
            '[]' >/dev/null; then
            log_error "[AUTO-FIX:unattended] Failed to record service stop after mutating state"
            if ! _autofix_unattended_run_privileged "$systemctl_bin" start unattended-upgrades 2>&1; then
                log_error "[AUTO-FIX:unattended] Failed to roll back unattended-upgrades service after journaling failure"
            fi
            return 1
        fi
        log_info "[AUTO-FIX:unattended] Stopped unattended-upgrades service"
        return 0
    else
        log_error "[AUTO-FIX:unattended] Failed to stop unattended-upgrades service"
        return 1
    fi
}

_autofix_package_owner_running() {
    local fuser_bin=""
    local lock=""
    local pgrep_bin=""

    pgrep_bin="$(_autofix_unattended_binary_path pgrep 2>/dev/null || true)"
    fuser_bin="$(_autofix_unattended_binary_path fuser 2>/dev/null || true)"
    if [[ -z "$pgrep_bin" || -z "$fuser_bin" ]]; then
        log_warn "[AUTO-FIX:unattended] Cannot prove package state is idle because pgrep or fuser is unavailable"
        return 0
    fi

    if "$pgrep_bin" -x "apt|apt-get|dpkg|aptitude|unattended-upgr|unattended-upgrade" &>/dev/null; then
        return 0
    fi

    # Process names are not authoritative: helpers and future package-manager
    # versions may use a different comm value. A held lock is ownership evidence.
    for lock in "${APT_LOCK_FILES[@]}"; do
        if "$fuser_bin" "$lock" >/dev/null 2>&1; then
            return 0
        fi
    done

    return 1
}

# Wait for package-manager owners to finish naturally
_autofix_wait_for_apt_processes() {
    local sleep_bin=""
    local waited=0

    sleep_bin="$(_autofix_unattended_binary_path sleep 2>/dev/null || true)"
    if [[ -z "$sleep_bin" ]]; then
        log_error "[AUTO-FIX:unattended] Cannot wait safely because sleep is unavailable"
        return 1
    fi

    while _autofix_package_owner_running && [[ $waited -lt $AUTOFIX_UNATTENDED_TIMEOUT ]]; do
        log_info "[AUTO-FIX:unattended] Waiting for apt/dpkg to finish... (${waited}s/${AUTOFIX_UNATTENDED_TIMEOUT}s)"
        "$sleep_bin" "$AUTOFIX_UNATTENDED_POLL_INTERVAL"
        ((waited += AUTOFIX_UNATTENDED_POLL_INTERVAL))
    done

    # Return 0 if processes finished, 1 if a live owner remains.
    if _autofix_package_owner_running; then
        log_warn "[AUTO-FIX:unattended] Timeout reached, a package-manager process or lock owner is still present"
        return 1
    fi

    log_debug "[AUTO-FIX:unattended] All apt/dpkg processes finished naturally"
    return 0
}

# Reconfigure dpkg in case it was interrupted
_autofix_reconfigure_dpkg() {
    log_info "[AUTO-FIX:unattended] Running dpkg --configure -a"

    local dpkg_bin=""
    local output
    dpkg_bin="$(_autofix_unattended_binary_path dpkg 2>/dev/null || true)"
    if [[ -z "$dpkg_bin" ]]; then
        log_error "[AUTO-FIX:unattended] dpkg is unavailable"
        return 1
    fi

    if output=$(_autofix_unattended_run_privileged "$dpkg_bin" --configure -a 2>&1); then
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

    local apt_get_bin=""
    local output
    apt_get_bin="$(_autofix_unattended_binary_path apt-get 2>/dev/null || true)"
    if [[ -z "$apt_get_bin" ]]; then
        log_error "[AUTO-FIX:unattended] apt-get is unavailable"
        return 1
    fi

    if output=$(_autofix_unattended_run_privileged "$apt_get_bin" -o DPkg::Lock::Timeout=120 update 2>&1); then
        if [[ -n "$output" ]]; then
            while IFS= read -r line; do
                log_debug "[apt:update] $line"
            done <<< "$output"
        fi
        return 0
    else
        log_warn "[AUTO-FIX:unattended] apt-get update had issues (may be non-fatal)"
        log_debug "$output"
        return 1
    fi
}

# =============================================================================
# Restore Functions
# =============================================================================

# Re-enable unattended-upgrades after installation completes
# Called at end of ACFS installation to restore normal operation
autofix_unattended_upgrades_restore() {
    local date_bin=""
    local jq_rc=0
    local jq_bin=""
    local latest_change_id=""
    local session_owned=false
    local systemctl_bin=""

    # Check if we stopped unattended-upgrades during this session
    if [[ ! -f "$ACFS_CHANGES_FILE" ]]; then
        log_debug "[POST-INSTALL] No changes file, nothing to restore"
        return 0
    fi

    # This function may run inside an active autofix session, before the final
    # integrity checkpoint is written. Validate both journals directly so a
    # malformed or unchecksummed marker cannot suppress the required restore.
    if ! autofix_journals_are_trusted >/dev/null 2>&1; then
        log_error "[POST-INSTALL] Cannot trust malformed autofix change or undo history"
        return 1
    fi

    jq_bin="$(_autofix_unattended_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        log_error "[POST-INSTALL] Cannot inspect unattended-upgrades changes because jq is unavailable"
        return 1
    fi

    if latest_change_id=$("$jq_bin" -r -s \
        '[.[] | select(.category == "unattended")][-1].id // ""' \
        "$ACFS_CHANGES_FILE" 2>/dev/null); then
        :
    else
        log_error "[POST-INSTALL] Cannot trust malformed unattended-upgrades change history"
        return 1
    fi
    if [[ -z "$latest_change_id" ]]; then
        log_debug "[POST-INSTALL] No unattended-upgrades changes to restore"
        return 0
    fi

    if [[ -f "$ACFS_UNDOS_FILE" ]]; then
        if "$jq_bin" -e -s --arg id "$latest_change_id" \
            'any(.[]; .undone == $id and .status == "applied")' \
            "$ACFS_UNDOS_FILE" >/dev/null 2>&1; then
            if autofix_path_exists "$ACFS_STATE_DIR/.session" && ! autofix_session_active; then
                log_error "[POST-INSTALL] Found unattended-upgrades auto-restore marker with unresolved autofix session"
                log_error "[POST-INSTALL] Resolve the previous autofix session before treating unattended-upgrades as restored"
                return 1
            fi
            log_debug "[POST-INSTALL] Unattended-upgrades already auto-restored"
            return 0
        else
            jq_rc=$?
            if [[ $jq_rc -ne 1 ]]; then
                log_error "[POST-INSTALL] Cannot trust malformed unattended-upgrades undo history"
                return 1
            fi
        fi
    fi

    date_bin="$(_autofix_unattended_binary_path date 2>/dev/null || true)"
    systemctl_bin="$(_autofix_unattended_binary_path systemctl 2>/dev/null || true)"
    if [[ -z "$date_bin" || -z "$systemctl_bin" ]]; then
        log_error "[POST-INSTALL] Cannot restore unattended-upgrades because date or systemctl is unavailable"
        return 1
    fi

    log_info "[POST-INSTALL] Re-enabling unattended-upgrades service"

    if ! autofix_ensure_session session_owned; then
        log_error "[POST-INSTALL] Failed to start autofix session for restore"
        return 1
    fi

    if _autofix_unattended_run_privileged "$systemctl_bin" start unattended-upgrades 2>&1; then
        # Mark as auto-restored in undos file
        local restore_record
        if ! restore_record=$("$jq_bin" -cn \
            --arg id "$latest_change_id" \
            --arg ts "$("$date_bin" -Iseconds)" \
            '{
              undone: $id,
              auto_restored: "unattended-upgrades",
              timestamp: $ts,
              exit_code: 0,
              status: "applied"
            }'); then
            log_error "[POST-INSTALL] Failed to build unattended-upgrades restore marker"
            if ! autofix_finalize_managed_session "$session_owned"; then
                log_error "[POST-INSTALL] Failed to finalize autofix session after restore record failure"
            fi
            return 1
        fi
        if ! restore_record="$(autofix_add_record_checksum "$restore_record")"; then
            log_error "[POST-INSTALL] Failed to checksum unattended-upgrades restore marker"
            if ! autofix_finalize_managed_session "$session_owned"; then
                log_error "[POST-INSTALL] Failed to finalize autofix session after restore checksum failure"
            fi
            return 1
        fi

        if ! append_atomic "$ACFS_UNDOS_FILE" "$restore_record"; then
            log_error "[POST-INSTALL] Failed to persist unattended-upgrades auto-restore marker"
            if ! autofix_finalize_managed_session "$session_owned"; then
                log_error "[POST-INSTALL] Failed to finalize autofix session after restore journaling failure"
            fi
            return 1
        fi
        if ! autofix_finalize_managed_session "$session_owned"; then
            log_error "[POST-INSTALL] Failed to finalize autofix session after restore"
            return 1
        fi
        log_info "[POST-INSTALL] Successfully re-enabled unattended-upgrades"
        return 0
    else
        if ! autofix_finalize_managed_session "$session_owned"; then
            log_error "[POST-INSTALL] Failed to finalize autofix session after restore failure"
        fi
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
