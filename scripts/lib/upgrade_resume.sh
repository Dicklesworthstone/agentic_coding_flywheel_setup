#!/usr/bin/env bash
# ============================================================
# ACFS Ubuntu Upgrade Resume Script
#
# This script is copied to /var/lib/acfs/ and executed after
# each reboot during the Ubuntu upgrade process.
#
# CRITICAL SAFETY: This script includes safeguards to prevent
# reboot loops. It checks actual system state, not just the
# state file, and disables itself when complete or on failure.
#
# Workflow:
# 1. FIRST: Check if already at target version (prevent loops)
# 2. Source libraries from /var/lib/acfs/lib/
# 3. Check if more upgrades needed
# 4. If complete: cleanup, disable service, launch continue_install.sh
# 5. If not complete: run next upgrade and trigger reboot
# 6. On failure: update MOTD with error, disable service, exit (NO reboot)
#
# This script is designed to be run by systemd on boot.
# ============================================================

set -euo pipefail

# Constants
ACFS_RESUME_DIR="/var/lib/acfs"
ACFS_LIB_DIR="${ACFS_RESUME_DIR}/lib"
ACFS_LOG="/var/log/acfs/upgrade_resume.log"
ACFS_STATE_FILE="${ACFS_RESUME_DIR}/state.json"
# Default target for ACFS. May be overridden by the state file (target_version)
# or by exporting UBUNTU_TARGET_VERSION before executing this script.
UBUNTU_TARGET_VERSION="${UBUNTU_TARGET_VERSION:-25.10}"
SERVICE_NAME="acfs-upgrade-resume"

# Ensure log directory exists
mkdir -p "$(dirname "$ACFS_LOG")"

# Read target version from state file if available.
read_target_version_from_state() {
    local state_file="$1"
    [[ -f "$state_file" ]] || return 1

    local target=""
    if command -v jq &>/dev/null; then
        target=$(jq -r '.ubuntu_upgrade.target_version // empty' "$state_file" 2>/dev/null || true)
    else
        target=$(sed -n 's/.*"target_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$state_file" | head -n 1)
    fi

    if [[ -n "$target" && "$target" != "null" ]]; then
        printf '%s' "$target"
        return 0
    fi

    return 1
}

compute_version_num() {
    local version="$1"
    local major="${version%%.*}"
    local minor="${version#*.}"
    printf "%d%02d" "$major" "$minor"
}

state_target_version="$(read_target_version_from_state "$ACFS_STATE_FILE" || true)"
if [[ -n "${state_target_version:-}" ]]; then
    UBUNTU_TARGET_VERSION="$state_target_version"
fi
export UBUNTU_TARGET_VERSION

if [[ -z "${UBUNTU_TARGET_VERSION_NUM:-}" ]]; then
    UBUNTU_TARGET_VERSION_NUM="$(compute_version_num "$UBUNTU_TARGET_VERSION")"
fi
export UBUNTU_TARGET_VERSION_NUM

# Logging function for this script
log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $*" | tee -a "$ACFS_LOG" || true
}

log_error() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $*" | tee -a "$ACFS_LOG" >&2 || true
}

# Cleanup function - disables the service to prevent loops
# NOTE: We do NOT call systemctl stop here because this script IS the running
# service. Calling stop would kill ourselves before completing cleanup.
# The service will exit naturally when the script finishes.
cleanup_service() {
    log "Disabling ${SERVICE_NAME} service to prevent reboot loops..."
    systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true
    # DO NOT call systemctl stop - that would kill this running script!
}

# Update MOTD with failure message and instructions
update_motd_failure() {
    local error_msg="$1"
    local motd_file="/etc/update-motd.d/00-acfs-upgrade"

    # Truncate error message to fit box
    # Box content: "║  Error: " (10) + message + " ║" (2) = 64, so max = 52
    local max_len=52
    if [[ ${#error_msg} -gt $max_len ]]; then
        error_msg="${error_msg:0:49}..."
    fi
    local padded_err
    padded_err=$(printf "%-${max_len}s" "$error_msg")

    cat > "$motd_file" << 'MOTD_SCRIPT'
#!/bin/bash
C='\033[0;31m'    # Red
Y='\033[1;33m'    # Yellow
B='\033[1m'       # Bold
N='\033[0m'       # Reset

echo ""
echo -e "${C}╔══════════════════════════════════════════════════════════════╗${N}"
echo -e "${C}║${N}           ${C}${B}*** ACFS UBUNTU UPGRADE FAILED ***${N}                ${C}║${N}"
echo -e "${C}╠══════════════════════════════════════════════════════════════╣${N}"
echo -e "${C}║${N}                                                              ${C}║${N}"
MOTD_SCRIPT

    # Add the error message with proper padding
    cat >> "$motd_file" << MOTD_ERROR
echo -e "\${C}║\${N}  \${Y}Error:\${N} ${padded_err}\${C}║\${N}"
MOTD_ERROR

    cat >> "$motd_file" << 'MOTD_FOOTER'
echo -e "${C}║${N}                                                              ${C}║${N}"
echo -e "${C}║${N}  ${B}TO RETRY (AFTER FIXING):${N}                                   ${C}║${N}"
echo -e "${C}║${N}    sudo systemctl enable --now acfs-upgrade-resume           ${C}║${N}"
echo -e "${C}║${N}                                                              ${C}║${N}"
echo -e "${C}║${N}  ${B}TO CHECK STATUS:${N}                                           ${C}║${N}"
echo -e "${C}║${N}    /var/lib/acfs/check_status.sh                             ${C}║${N}"
echo -e "${C}║${N}                                                              ${C}║${N}"
echo -e "${C}║${N}  ${B}TO VIEW LOGS:${N}                                              ${C}║${N}"
echo -e "${C}║${N}    journalctl -u acfs-upgrade-resume -f                      ${C}║${N}"
echo -e "${C}║${N}    cat /var/log/acfs/upgrade_resume.log                      ${C}║${N}"
echo -e "${C}║${N}                                                              ${C}║${N}"
echo -e "${C}╚══════════════════════════════════════════════════════════════╝${N}"
echo ""
MOTD_FOOTER

    chmod +x "$motd_file"
}

# Remove MOTD
remove_motd() {
    rm -f /etc/update-motd.d/00-acfs-upgrade 2>/dev/null || true
}

# Update state to mark upgrade as complete
mark_state_complete() {
    if [[ -f "$ACFS_STATE_FILE" ]] && command -v jq &>/dev/null; then
        local tmp_file=""
        tmp_file="$(mktemp "${ACFS_STATE_FILE}.tmp.XXXXXX" 2>/dev/null)" || tmp_file=""

        if [[ -z "$tmp_file" ]]; then
            log_error "mktemp failed; skipping state update"
            return 0
        fi

        if jq '.ubuntu_upgrade.current_stage = "completed" | .ubuntu_upgrade.needs_reboot = false' "$ACFS_STATE_FILE" > "$tmp_file" 2>/dev/null; then
            if mv "$tmp_file" "$ACFS_STATE_FILE" 2>/dev/null; then
                log "State updated to 'completed'"
            else
                rm -f "$tmp_file" 2>/dev/null || true
                log_error "Failed to write updated state file"
            fi
        else
            rm -f "$tmp_file" 2>/dev/null || true
            log_error "Failed to update state file"
        fi
    fi
}

# Launch continue script using systemd-run for reliability
# nohup+background is unreliable when parent service exits
launch_continue_script() {
    local script="${ACFS_RESUME_DIR}/continue_install.sh"

    if [[ ! -f "$script" ]]; then
        log "No continue_install.sh found - manual installation needed"
        log "Run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh | bash -s -- --yes --mode vibe"
        return 1
    fi

    log "Launching continue_install.sh to resume ACFS installation"

    # Use systemd-run to spawn a proper transient service that survives this script's exit
    # --collect: auto-cleanup unit after it finishes (avoids "unit already exists" errors)
    # --no-block: don't wait for service to complete (we want to exit immediately)
    # --setenv: ensure HOME is set (required by preflight checks and installer)
    # Service output goes to journal (check with: journalctl -u acfs-continue-install)
	    if command -v systemd-run &>/dev/null; then
	        # Remove any stale unit from previous failed attempts
	        systemctl reset-failed acfs-continue-install 2>/dev/null || true
	
	        if (
	            set -o pipefail
	            systemd-run --collect --no-block \
	            --unit=acfs-continue-install \
	            --description="ACFS Installation Continuation" \
	            --property=Type=oneshot \
	            --property=TimeoutStartSec=7200 \
	            --setenv=HOME=/root \
	            /bin/bash "$script" 2>&1 | tee -a "$ACFS_LOG"
	        ); then
	            log "ACFS continuation launched via systemd-run"
	            log "Monitor with: journalctl -u acfs-continue-install -f"
	        else
	            log "systemd-run failed, falling back to nohup"
	            nohup bash "$script" >> "$ACFS_LOG" 2>&1 &
            log "ACFS continuation launched via nohup (PID: $!)"
        fi
    else
        # Fallback to nohup if systemd-run unavailable (shouldn't happen on Ubuntu)
        nohup bash "$script" >> "$ACFS_LOG" 2>&1 &
        log "ACFS continuation launched via nohup (PID: $!)"
    fi

    return 0
}

# ============================================================
# MAIN EXECUTION STARTS HERE
# ============================================================

log "=== ACFS Upgrade Resume Starting ==="
log "Script: $0"
log "Current directory: $(pwd)"

# ============================================================
# CRITICAL SAFETY CHECK #1: Are we already at target version?
# This prevents reboot loops if the state file is stale/wrong.
# ============================================================

# Get current Ubuntu version directly from the system (not state file)
if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    CURRENT_UBUNTU_VERSION="${VERSION_ID:-unknown}"
else
    log_error "Cannot read /etc/os-release"
    CURRENT_UBUNTU_VERSION="unknown"
fi

log "Current Ubuntu version (from system): $CURRENT_UBUNTU_VERSION"
log "Target Ubuntu version: $UBUNTU_TARGET_VERSION"

# If we're already at target, we're DONE - clean up and exit
if [[ "$CURRENT_UBUNTU_VERSION" == "$UBUNTU_TARGET_VERSION" ]]; then
    log "SUCCESS: Already at target version $UBUNTU_TARGET_VERSION!"
    log "Cleaning up upgrade infrastructure..."

    # Disable service FIRST to prevent any possibility of loop
    cleanup_service

    # Update state to mark as complete (before removing files)
    export ACFS_STATE_FILE="${ACFS_RESUME_DIR}/state.json"
    mark_state_complete

    # Remove MOTD
    remove_motd

    # Launch continue script BEFORE removing files (it may need them)
    launch_continue_script || log "Note: Manual installation may be needed"

    # Clean up resume files (after launching continue script)
    rm -f "${ACFS_RESUME_DIR}/upgrade_resume.sh" 2>/dev/null || true
    rm -rf "${ACFS_LIB_DIR}" 2>/dev/null || true

    log "=== Upgrade Resume Complete (target reached) ==="
    exit 0
fi

# ============================================================
# Check if libraries exist
# ============================================================

if [[ ! -d "$ACFS_LIB_DIR" ]]; then
    log_error "Library directory not found: $ACFS_LIB_DIR"
    cleanup_service
    update_motd_failure "Library files missing"
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
    cleanup_service
    update_motd_failure "state.sh missing"
    exit 1
fi

if [[ -f "$ACFS_LIB_DIR/ubuntu_upgrade.sh" ]]; then
    # shellcheck source=/dev/null
    source "$ACFS_LIB_DIR/ubuntu_upgrade.sh"
else
    log_error "ubuntu_upgrade.sh not found"
    cleanup_service
    update_motd_failure "ubuntu_upgrade.sh missing"
    exit 1
fi

# Set state file location for resume context
export ACFS_STATE_FILE="${ACFS_STATE_FILE}"

# ============================================================
# Check current stage in state
# ============================================================

current_stage=""
if [[ -f "$ACFS_STATE_FILE" ]] && command -v jq &>/dev/null; then
    current_stage=$(jq -r '.ubuntu_upgrade.current_stage // "unknown"' "$ACFS_STATE_FILE" 2>/dev/null) || current_stage="unknown"
fi
log "Current stage from state file: $current_stage"

# Pre-upgrade reboot: system rebooted to apply pending updates before the first do-release-upgrade.
# At this point, we should disable the resume service and re-run install.sh (continue_install.sh)
# which will proceed with the Ubuntu upgrade normally.
if [[ "$current_stage" == "pre_upgrade_reboot" ]]; then
    log "Detected pre-upgrade reboot marker. Continuing ACFS installer after reboot..."
    cleanup_service
    launch_continue_script || log "Note: Manual installation may be needed"
    log "=== Upgrade Resume Complete (pre-upgrade reboot) ==="
    exit 0
fi

# Ensure non-LTS upgrades are permitted
ubuntu_enable_normal_releases || true

# Mark that we've successfully resumed after reboot
log "Marking upgrade as resumed"
state_upgrade_resumed

# ============================================================
# Check if upgrade is complete (using state file)
# ============================================================

if state_upgrade_is_complete; then
    log "All upgrades complete per state file!"

    state_upgrade_mark_complete
    ubuntu_restore_lts_only || true
    remove_motd
    cleanup_service

    # Launch continue script BEFORE cleaning up files (it may need them)
    launch_continue_script || log "Note: Manual installation may be needed"

    # Clean up resume files (after launching continue script)
    rm -f "${ACFS_RESUME_DIR}/upgrade_resume.sh" 2>/dev/null || true
    rm -rf "${ACFS_LIB_DIR}" 2>/dev/null || true

    log "=== Upgrade Resume Complete ==="
    exit 0
fi

# ============================================================
# More upgrades needed - get next version
# ============================================================

next_version=$(state_upgrade_get_next_version)
if [[ -z "$next_version" ]]; then
    log_error "No next version found but upgrade not marked complete"
    log "This may indicate a corrupted state file. Current version: $CURRENT_UBUNTU_VERSION"

    # Safety check: if we're at target, just clean up
    if [[ "$CURRENT_UBUNTU_VERSION" == "$UBUNTU_TARGET_VERSION" ]]; then
        log "Actually at target version - cleaning up anyway"
        cleanup_service
        remove_motd
        launch_continue_script || true
        exit 0
    fi

    cleanup_service
    update_motd_failure "State file corrupted - rerun installer"
    exit 1
fi

log "Next upgrade target: $next_version"

# Update MOTD with progress
log "Updating MOTD with upgrade progress..."
upgrade_update_motd "Upgrading: $CURRENT_UBUNTU_VERSION → $next_version"

# Run preflight checks before continuing
log "Running preflight checks..."
if ! ubuntu_preflight_checks; then
    log_error "Preflight checks failed - cannot continue upgrade"
    state_upgrade_set_error "Preflight checks failed after reboot"
    cleanup_service
    update_motd_failure "Preflight checks failed"
    exit 1
fi

# ============================================================
# Perform the upgrade
# ============================================================

log "Starting upgrade from $CURRENT_UBUNTU_VERSION to $next_version"
state_upgrade_start "$CURRENT_UBUNTU_VERSION" "$next_version"

if ! ubuntu_do_upgrade "$next_version"; then
    log_error "do-release-upgrade failed"
    state_upgrade_set_error "do-release-upgrade failed for $CURRENT_UBUNTU_VERSION → $next_version"

    # CRITICAL: Disable service to prevent reboot loop on failure
    cleanup_service
    update_motd_failure "do-release-upgrade failed"

    log "=== Upgrade Failed - Service Disabled ==="
    # DO NOT REBOOT - just exit
    exit 1
fi

# ============================================================
# Upgrade succeeded - prepare for reboot
# ============================================================

state_upgrade_complete "$next_version"
log "Upgrade to $next_version completed successfully"

state_upgrade_needs_reboot
log "System needs reboot to complete upgrade"

# Update MOTD before reboot
upgrade_update_motd "Rebooting to complete upgrade to $next_version..."

# Trigger reboot (1 minute delay for user to read messages)
log "Triggering reboot in 1 minute..."
ubuntu_trigger_reboot 1

log "=== Upgrade Resume Script Exiting (reboot pending) ==="
exit 0
