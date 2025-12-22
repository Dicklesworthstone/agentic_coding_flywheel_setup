#!/usr/bin/env bash
# ============================================================
# ACFS Ubuntu Upgrade Resume Script
#
# This script is copied to /var/lib/acfs/ and executed after
# each reboot during the Ubuntu upgrade process.
#
# Workflow:
# 1. Source libraries from /var/lib/acfs/lib/
# 2. Mark resume in state
# 3. Check if more upgrades needed
# 4. If complete: cleanup and launch continue_install.sh
# 5. If not complete: run next upgrade and trigger reboot
#
# This script is designed to be run by systemd on boot.
# ============================================================

set -euo pipefail

# Constants
ACFS_RESUME_DIR="/var/lib/acfs"
ACFS_LIB_DIR="${ACFS_RESUME_DIR}/lib"
ACFS_LOG="/var/log/acfs/upgrade_resume.log"

# Ensure log directory exists
mkdir -p "$(dirname "$ACFS_LOG")"

# Logging function for this script
log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $*" | tee -a "$ACFS_LOG"
}

log_error() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $*" | tee -a "$ACFS_LOG" >&2
}

# Main execution starts here
log "=== ACFS Upgrade Resume Starting ==="
log "Script: $0"
log "Current directory: $(pwd)"

# Check if libraries exist
if [[ ! -d "$ACFS_LIB_DIR" ]]; then
    log_error "Library directory not found: $ACFS_LIB_DIR"
    exit 1
fi

# Source required libraries
log "Sourcing libraries from $ACFS_LIB_DIR"

if [[ -f "$ACFS_LIB_DIR/logging.sh" ]]; then
    # shellcheck source=/dev/null
    source "$ACFS_LIB_DIR/logging.sh"
fi

if [[ -f "$ACFS_LIB_DIR/state.sh" ]]; then
    # shellcheck source=/dev/null
    source "$ACFS_LIB_DIR/state.sh"
else
    log_error "state.sh not found"
    exit 1
fi

if [[ -f "$ACFS_LIB_DIR/ubuntu_upgrade.sh" ]]; then
    # shellcheck source=/dev/null
    source "$ACFS_LIB_DIR/ubuntu_upgrade.sh"
else
    log_error "ubuntu_upgrade.sh not found"
    exit 1
fi

# Set state file location for resume context
export ACFS_STATE_FILE="${ACFS_RESUME_DIR}/state.json"

# Ensure non-LTS upgrades are permitted (LTS defaults to Prompt=lts).
ubuntu_enable_normal_releases || true

# Mark that we've successfully resumed after reboot
log "Marking upgrade as resumed"
state_upgrade_resumed

# Check current Ubuntu version after reboot
current_version=$(ubuntu_get_version_string) || {
    log_error "Failed to get current Ubuntu version"
    exit 1
}
log "Current Ubuntu version: $current_version"

# Check if upgrade is complete
if state_upgrade_is_complete; then
    log "All upgrades complete! Target version reached."

    # Mark upgrade as fully completed
    state_upgrade_mark_complete

    # Restore LTS-only upgrade settings if we changed them.
    ubuntu_restore_lts_only || true

    # Remove upgrade MOTD banner (so users aren't told upgrade is still running).
    upgrade_remove_motd || true

    # Cleanup systemd service and temporary files
    log "Cleaning up resume infrastructure..."
    ubuntu_cleanup_resume "acfs-upgrade-resume"

    # Check if continue script exists
    if [[ -f "${ACFS_RESUME_DIR}/continue_install.sh" ]]; then
        log "Launching continue_install.sh to resume ACFS installation"

        # Execute the continue script
        # Use nohup to survive this script exiting
        nohup bash "${ACFS_RESUME_DIR}/continue_install.sh" >> "$ACFS_LOG" 2>&1 &

        log "ACFS installation continuation launched (PID: $!)"
    else
        log "No continue_install.sh found - manual intervention may be needed"
    fi

    log "=== Upgrade Resume Complete ==="
    exit 0
fi

# More upgrades needed - get next version
next_version=$(state_upgrade_get_next_version)
if [[ -z "$next_version" ]]; then
    log_error "No next version found but upgrade not marked complete"
    state_upgrade_set_error "No next version found"
    exit 1
fi

log "Next upgrade target: $next_version"

# Update MOTD with progress
log "Updating MOTD with upgrade progress..."
upgrade_update_motd "Upgrading: $current_version → $next_version"

# Run preflight checks before continuing
log "Running preflight checks..."
if ! ubuntu_preflight_checks; then
    log_error "Preflight checks failed - cannot continue upgrade"
    state_upgrade_set_error "Preflight checks failed after reboot"
    upgrade_update_motd "UPGRADE PAUSED - preflight checks failed"
    exit 1
fi

# Start the next upgrade
log "Starting upgrade from $current_version to $next_version"
state_upgrade_start "$current_version" "$next_version"

# Perform the upgrade
if ! ubuntu_do_upgrade "$next_version"; then
    log_error "do-release-upgrade failed"
    state_upgrade_set_error "do-release-upgrade failed for $current_version → $next_version"
    upgrade_update_motd "UPGRADE FAILED - check logs"
    exit 1
fi

# Mark upgrade step complete
state_upgrade_complete "$next_version"
log "Upgrade to $next_version completed successfully"

# Mark that we need to reboot
state_upgrade_needs_reboot
log "System needs reboot to complete upgrade"

# Update MOTD before reboot
upgrade_update_motd "Rebooting to complete upgrade to $next_version..."

# Trigger reboot (1 minute delay for user to read messages)
log "Triggering reboot in 1 minute..."
ubuntu_trigger_reboot 1

log "=== Upgrade Resume Script Exiting (reboot pending) ==="
exit 0
