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
ACFS_CONTINUE_CONTEXT_FILE="${ACFS_RESUME_DIR}/continue_context.env"
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
    command -v jq &>/dev/null || return 1
    # The resume state is JSON, not arbitrary text containing a target_version
    # substring. Reject damaged/missing state instead of inventing a target.
    jq -er '.ubuntu_upgrade.target_version | strings | select(test("^[0-9]{2}\\.(04|10)$"))' \
        "$state_file" 2>/dev/null
}

compute_version_num() {
    local version="$1"
    if [[ ! "$version" =~ ^([0-9]{2})\.(04|10)(\.[0-9]+)?$ ]]; then
        return 1
    fi

    local major="${BASH_REMATCH[1]}"
    local minor="${BASH_REMATCH[2]}"

    # Force base-10 parsing for the zero-prefixed April release number.
    printf "%d%02d" "$((10#$major))" "$((10#$minor))"
}

ubuntu_is_at_or_beyond_target_version() {
    local current_version="$1"
    local current_version_num target_version_num
    current_version_num=$(compute_version_num "$current_version") || return 1
    target_version_num=$(compute_version_num "$UBUNTU_TARGET_VERSION") || return 1
    [[ "$current_version_num" -ge "$target_version_num" ]]
}

state_target_version="$(read_target_version_from_state "$ACFS_STATE_FILE" || true)"
if [[ -n "${state_target_version:-}" ]]; then
    UBUNTU_TARGET_VERSION="$state_target_version"
fi
export UBUNTU_TARGET_VERSION

# Always derive the number after reading the stored target. Never allow a
# caller's stale numeric value to disagree with the persisted release string.
UBUNTU_TARGET_VERSION_NUM="$(compute_version_num "$UBUNTU_TARGET_VERSION" || printf '')"
if [[ ! "${UBUNTU_TARGET_VERSION_NUM:-}" =~ ^[0-9]+$ ]]; then
    UBUNTU_TARGET_VERSION_NUM=""
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

load_continue_context() {
    [[ -f "$ACFS_CONTINUE_CONTEXT_FILE" ]] || return 1

    # shellcheck source=/dev/null
    source "$ACFS_CONTINUE_CONTEXT_FILE"
    return 0
}

# Clean up the resume infrastructure on success.
# This uses strict path checks because it runs as root on boot; a bad rm -rf would be catastrophic.
cleanup_resume_files() {
    local expected_resume_dir="/var/lib/acfs"
    if [[ "${ACFS_RESUME_DIR:-}" != "$expected_resume_dir" ]]; then
        log_error "Refusing to clean up unexpected ACFS_RESUME_DIR: ${ACFS_RESUME_DIR:-<unset>} (expected: $expected_resume_dir)"
        return 1
    fi

    local script_path="${ACFS_RESUME_DIR}/upgrade_resume.sh"
    local lib_dir="${ACFS_RESUME_DIR}/lib"

    if [[ "$script_path" != "$expected_resume_dir/upgrade_resume.sh" ]]; then
        log_error "Refusing to remove unexpected resume script path: $script_path"
        return 1
    fi
    if [[ "$lib_dir" != "$expected_resume_dir/lib" ]]; then
        log_error "Refusing to remove unexpected lib dir path: $lib_dir"
        return 1
    fi

    rm -f -- "$script_path" 2>/dev/null || true
    rm -rf -- "$lib_dir" 2>/dev/null || true
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

    # Security: This message will be embedded into a shell script. Prevent any
    # possibility of shell injection by normalizing to a single line and
    # using shell-escaped assignment when writing the MOTD script.
    error_msg="${error_msg//$'\r'/ }"
    error_msg="${error_msg//$'\n'/ }"
    error_msg="${error_msg//$'\t'/ }"

    # Truncate error message to fit box
    # Box content: "║  Error: " (10) + message + " ║" (2) = 64, so max = 52
    local max_len=52
    if [[ ${#error_msg} -gt $max_len ]]; then
        error_msg="${error_msg:0:49}..."
    fi
    local padded_err
    padded_err=$(printf "%-${max_len}s" "$error_msg")
    local padded_err_q
    padded_err_q=$(printf '%q' "$padded_err")

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
ERROR_MSG=${padded_err_q}
echo -e "\${C}║\${N}  \${Y}Error:\${N} \${ERROR_MSG}\${C}║\${N}"
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
        local completed_at=""
        tmp_file="$(mktemp "${ACFS_STATE_FILE}.tmp.XXXXXX" 2>/dev/null)" || tmp_file=""

        if [[ -z "$tmp_file" ]]; then
            log_error "mktemp failed; cannot persist completion"
            return 1
        fi

        completed_at="$(date -Iseconds)"
        if jq --arg now "$completed_at" '
            .ubuntu_upgrade.current_stage = "completed" |
            .ubuntu_upgrade.completed_at = $now |
            .ubuntu_upgrade.needs_reboot = false |
            .ubuntu_upgrade.resume_after_reboot = false |
            .ubuntu_upgrade.current_upgrade = null
        ' "$ACFS_STATE_FILE" > "$tmp_file" 2>/dev/null; then
            if mv "$tmp_file" "$ACFS_STATE_FILE" 2>/dev/null; then
                log "State updated to 'completed'"
            else
                rm -f "$tmp_file" 2>/dev/null || true
                log_error "Failed to write updated state file"
                return 1
            fi
        else
            rm -f "$tmp_file" 2>/dev/null || true
            log_error "Failed to update state file"
            return 1
        fi
    else
        log_error "Missing state file or jq; cannot persist completion"
        return 1
    fi
    return 0
}

# Launch continue script using systemd-run for reliability
# nohup+background is unreliable when parent service exits
launch_continue_script() {
    local script="${ACFS_RESUME_DIR}/continue_install.sh"
    load_continue_context || true

    if [[ ! -f "$script" ]]; then
        log "No continue_install.sh found - manual installation needed"
        local curl_cmd="curl -fsSL"
        if command -v curl &>/dev/null && curl --help all 2>/dev/null | grep -q -- '--proto'; then
            curl_cmd="curl --proto '=https' --proto-redir '=https' -fsSL"
        fi

        local install_url="${CONTINUE_INSTALL_URL:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh}"
        local continue_ref="${CONTINUE_ACFS_REF:-main}"
        local continue_home="${CONTINUE_HOME:-/root}"
        local -a continue_args=()
        local rendered_args=""
        local arg=""
        local env_prefix=""

        if declare -p CONTINUE_INSTALL_ARGS >/dev/null 2>&1; then
            continue_args=("${CONTINUE_INSTALL_ARGS[@]}")
        else
            continue_args=(--yes --mode vibe)
        fi

        for arg in "${continue_args[@]}"; do
            rendered_args+=" $(printf '%q' "$arg")"
        done
        rendered_args="${rendered_args# }"

        [[ -n "${CONTINUE_TARGET_USER:-}" ]] && env_prefix+="TARGET_USER=$(printf '%q' "$CONTINUE_TARGET_USER") "
        [[ -n "${CONTINUE_TARGET_HOME:-}" ]] && env_prefix+="TARGET_HOME=$(printf '%q' "$CONTINUE_TARGET_HOME") "
        [[ -n "${CONTINUE_ACFS_HOME:-}" ]] && env_prefix+="ACFS_HOME=$(printf '%q' "$CONTINUE_ACFS_HOME") "
        [[ -n "${CONTINUE_ACFS_STATE_FILE:-}" ]] && env_prefix+="ACFS_STATE_FILE=$(printf '%q' "$CONTINUE_ACFS_STATE_FILE") "
        env_prefix+="HOME=$(printf '%q' "$continue_home") "
        if [[ -n "$continue_ref" ]] && [[ "$continue_ref" != "main" ]]; then
            env_prefix+="ACFS_REF=$(printf '%q' "$continue_ref") "
        fi

        log "Run: ${env_prefix}${curl_cmd} $(printf '%q' "$install_url") | bash -s -- ${rendered_args}"
        return 1
    fi

    log "Launching continue_install.sh to resume ACFS installation"
    local continue_home="${CONTINUE_HOME:-/root}"
    local -a continue_env_args=("--setenv=HOME=${continue_home}")
    local -a continue_nohup_env=("HOME=${continue_home}")

    if [[ -n "${CONTINUE_TARGET_USER:-}" ]]; then
        continue_env_args+=("--setenv=TARGET_USER=${CONTINUE_TARGET_USER}")
        continue_nohup_env+=("TARGET_USER=${CONTINUE_TARGET_USER}")
    fi
    if [[ -n "${CONTINUE_TARGET_HOME:-}" ]]; then
        continue_env_args+=("--setenv=TARGET_HOME=${CONTINUE_TARGET_HOME}")
        continue_nohup_env+=("TARGET_HOME=${CONTINUE_TARGET_HOME}")
    fi
    if [[ -n "${CONTINUE_ACFS_HOME:-}" ]]; then
        continue_env_args+=("--setenv=ACFS_HOME=${CONTINUE_ACFS_HOME}")
        continue_nohup_env+=("ACFS_HOME=${CONTINUE_ACFS_HOME}")
    fi
    if [[ -n "${CONTINUE_ACFS_STATE_FILE:-}" ]]; then
        continue_env_args+=("--setenv=ACFS_STATE_FILE=${CONTINUE_ACFS_STATE_FILE}")
        continue_nohup_env+=("ACFS_STATE_FILE=${CONTINUE_ACFS_STATE_FILE}")
    fi
    if [[ -n "${CONTINUE_ACFS_REF:-}" ]]; then
        continue_env_args+=("--setenv=ACFS_REF=${CONTINUE_ACFS_REF}")
        continue_nohup_env+=("ACFS_REF=${CONTINUE_ACFS_REF}")
    fi

    # Use systemd-run to spawn a proper transient service that survives this script's exit
    # --collect: auto-cleanup unit after it finishes (avoids "unit already exists" errors)
    # --no-block: don't wait for service to complete (we want to exit immediately)
    # --setenv: restore the original target-user context before install.sh resumes
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
                "${continue_env_args[@]}" \
                /bin/bash "$script" 2>&1 | tee -a "$ACFS_LOG"
            exit "${PIPESTATUS[0]:-1}"
        ); then
            log "ACFS continuation launched via systemd-run"
            log "Monitor with: journalctl -u acfs-continue-install -f"
        else
            log "systemd-run failed, falling back to nohup"
            env "${continue_nohup_env[@]}" nohup bash "$script" >> "$ACFS_LOG" 2>&1 &
            log "ACFS continuation launched via nohup (PID: $!)"
        fi
    else
        # Fallback to nohup if systemd-run unavailable (shouldn't happen on Ubuntu)
        env "${continue_nohup_env[@]}" nohup bash "$script" >> "$ACFS_LOG" 2>&1 &
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

# Keep the current installer's target policy here until its full release graph
# is migrated. An invalid target must never be interpreted as completion.
if [[ -z "$state_target_version" || -z "$UBUNTU_TARGET_VERSION_NUM" ]]; then
    cleanup_service
    update_motd_failure "Invalid upgrade target - review state"
    exit 1
fi

# ============================================================
# CRITICAL SAFETY CHECK #1: Are we already at target version?
# This prevents reboot loops if the state file is stale/wrong.
# ============================================================

# Get current Ubuntu version directly from the system (not state file)
if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" != ubuntu ]]; then
        log_error "Upgrade resume is only supported on Ubuntu"
        cleanup_service
        update_motd_failure "Host is not Ubuntu"
        exit 1
    fi
    CURRENT_UBUNTU_VERSION="${VERSION_ID:-unknown}"
else
    log_error "Cannot read /etc/os-release"
    CURRENT_UBUNTU_VERSION="unknown"
fi

log "Current Ubuntu version (from system): $CURRENT_UBUNTU_VERSION"
log "Target Ubuntu version: $UBUNTU_TARGET_VERSION"

# If we're already at target, we're DONE - clean up and exit
if ubuntu_is_at_or_beyond_target_version "$CURRENT_UBUNTU_VERSION"; then
    # os-release can change before package configuration finishes. Do not
    # launch the installer on a partially upgraded machine merely because
    # its release number now matches the target.
    package_audit=""
    if ! package_audit=$(dpkg --audit 2>&1) || [[ -n "${package_audit//[[:space:]]/}" ]]; then
        log_error "Target version reached but dpkg still requires recovery; refusing installer continuation"
        cleanup_service
        update_motd_failure "Package recovery required - run dpkg --audit"
        exit 1
    fi
    log "SUCCESS: Already at or beyond target version (current: $CURRENT_UBUNTU_VERSION, target: $UBUNTU_TARGET_VERSION)!"
    log "Cleaning up upgrade infrastructure..."

    # Disable service FIRST to prevent any possibility of loop
    cleanup_service

    # Update state to mark as complete (before removing files)
    export ACFS_STATE_FILE="${ACFS_RESUME_DIR}/state.json"
    if ! mark_state_complete; then
        update_motd_failure "Cannot persist completed upgrade state"
        exit 1
    fi

    # Remove MOTD
    remove_motd

    # Launch continue script BEFORE removing files (it may need them)
    if ! launch_continue_script; then
        update_motd_failure "Installer continuation failed - retry manually"
        log_error "Keeping resume files for recovery; installer continuation did not launch"
        exit 1
    fi

    # The continuation is a detached service and may still source these
    # libraries. Do not remove its inputs or recovery evidence underneath it.
    log "Retaining resume files until the installer continuation finishes"

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
    if ! source "$ACFS_LIB_DIR/logging.sh"; then
        cleanup_service
        update_motd_failure "Logging library initialization failed"
        exit 1
    fi
fi

if [[ -f "$ACFS_LIB_DIR/state.sh" ]]; then
    # shellcheck source=/dev/null
    if ! source "$ACFS_LIB_DIR/state.sh"; then
        cleanup_service
        update_motd_failure "State library initialization failed"
        exit 1
    fi
else
    log_error "state.sh not found"
    cleanup_service
    update_motd_failure "state.sh missing"
    exit 1
fi

if [[ -f "$ACFS_LIB_DIR/ubuntu_upgrade.sh" ]]; then
    # shellcheck source=/dev/null
    if ! source "$ACFS_LIB_DIR/ubuntu_upgrade.sh"; then
        cleanup_service
        update_motd_failure "Upgrade library initialization failed"
        exit 1
    fi
else
    log_error "ubuntu_upgrade.sh not found"
    cleanup_service
    update_motd_failure "ubuntu_upgrade.sh missing"
    exit 1
fi

if ! upgrade_acquire_lock; then
    log_error "Another Ubuntu upgrade process is already running"
    exit 1
fi
trap 'upgrade_release_lock' EXIT

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

# A kernel-only reboot did not finish a release hop. Continue in this service
# using the live OS. The existing continuation may contain --skip-ubuntu-upgrade
# from an earlier hop; launching it here would bypass the remaining upgrades.
if [[ "$current_stage" == "pre_upgrade_reboot" ]]; then
    log "Kernel reboot completed; recomputing the pending release hop from the live OS"
fi

# Preserve the existing channel policy; do not continue after a failed change.
if ! ubuntu_enable_normal_releases; then
    cleanup_service
    update_motd_failure "Cannot configure release upgrade channel"
    exit 1
fi

# Mark that we've successfully resumed after reboot
log "Marking upgrade as resumed"
if ! state_upgrade_resumed; then
    cleanup_service
    update_motd_failure "Cannot persist resumed upgrade state"
    exit 1
fi

# ============================================================
# More upgrades needed - get next version from the LIVE host
# ============================================================

# Completion was checked against os-release above. The persisted path and
# completed-hop count are progress metadata, not authority to skip a release.
if ! remaining_path=$(ubuntu_calculate_upgrade_path "$UBUNTU_TARGET_VERSION_NUM") || [[ -z "$remaining_path" ]]; then
    log_error "No reviewed remaining upgrade path from $CURRENT_UBUNTU_VERSION to $UBUNTU_TARGET_VERSION"
    state_upgrade_set_error "No reviewed live-host upgrade path" || true
    cleanup_service
    update_motd_failure "No supported path - review recovery"
    exit 1
fi
next_version="${remaining_path%%$'\n'*}"
if ! next_version_num=$(compute_version_num "$next_version") \
    || ! current_version_num=$(compute_version_num "$CURRENT_UBUNTU_VERSION") \
    || [[ "$next_version_num" -le "$current_version_num" || "$next_version_num" -gt "$UBUNTU_TARGET_VERSION_NUM" ]]; then
    cleanup_service
    update_motd_failure "Non-advancing upgrade path - review state"
    exit 1
fi

log "Next upgrade target: $next_version"

# Update MOTD with progress
log "Updating MOTD with upgrade progress..."
upgrade_update_motd "Upgrading: $CURRENT_UBUNTU_VERSION → $next_version"

# Run preflight checks before continuing
log "Running preflight checks..."
package_audit=""
if ! package_audit=$(dpkg --audit 2>&1) || [[ -n "${package_audit//[[:space:]]/}" ]] || ! ubuntu_preflight_checks; then
    log_error "Preflight checks failed - cannot continue upgrade"
    state_upgrade_set_error "Preflight checks failed after reboot" || true
    cleanup_service
    update_motd_failure "Preflight checks failed"
    exit 1
fi

# ============================================================
# Perform the upgrade
# ============================================================

log "Starting upgrade from $CURRENT_UBUNTU_VERSION to $next_version"
if ! state_upgrade_start "$CURRENT_UBUNTU_VERSION" "$next_version"; then
    cleanup_service
    update_motd_failure "Cannot persist the next upgrade hop"
    exit 1
fi

if ! ubuntu_do_upgrade "$next_version"; then
    log_error "do-release-upgrade failed"
    state_upgrade_set_error "do-release-upgrade failed for $CURRENT_UBUNTU_VERSION → $next_version" || true

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

# A successful command exit is not proof that the requested release was
# installed. Never write a completed-hop checkpoint for a no-op or wrong hop.
installed_version="$(ubuntu_get_version_string)" || installed_version=""
package_audit=""
if [[ "$installed_version" != "$next_version" ]] \
    || ! package_audit=$(dpkg --audit 2>&1) || [[ -n "${package_audit//[[:space:]]/}" ]]; then
    state_upgrade_set_error "Release upgrade did not finish the requested hop cleanly" || true
    cleanup_service
    update_motd_failure "Upgrade incomplete - inspect OS and dpkg"
    exit 1
fi

if ! state_upgrade_complete "$next_version"; then
    cleanup_service
    update_motd_failure "Cannot persist completed release hop"
    exit 1
fi
log "Upgrade to $next_version completed successfully"

if ! state_upgrade_needs_reboot; then
    cleanup_service
    update_motd_failure "Cannot persist reboot state"
    exit 1
fi
log "System needs reboot to complete upgrade"

# Update MOTD before reboot
upgrade_update_motd "Rebooting to complete upgrade to $next_version..."

# Trigger reboot (1 minute delay for user to read messages)
log "Triggering reboot in 1 minute..."
# Schedule synchronously: the legacy helper backgrounds shutdown and hides
# errors, which can strand a host with a checkpoint claiming a reboot is due.
if ! shutdown -r +1 "ACFS: Ubuntu upgrade requires reboot"; then
    state_upgrade_set_error "reboot_scheduling_failed" || true
    cleanup_service
    update_motd_failure "Reboot scheduling failed - review logs"
    exit 1
fi

log "=== Upgrade Resume Script Exiting (reboot pending) ==="
exit 0
