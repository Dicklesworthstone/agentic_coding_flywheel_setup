#!/usr/bin/env bash
# ============================================================
# ACFS Installer - Ubuntu Upgrade Library
# Automatically upgrades Ubuntu to target version (25.10)
#
# Requires: logging.sh, os_detect.sh to be sourced first
# ============================================================

# Target Ubuntu version for ACFS
export UBUNTU_TARGET_VERSION="25.10"
export UBUNTU_TARGET_VERSION_NUM=2510

# Minimum disk space required for upgrade (in MB)
export UBUNTU_UPGRADE_MIN_DISK_MB=5000

# Directory for resume infrastructure (created during upgrade)
export ACFS_RESUME_DIR="/var/lib/acfs"

# Lock file location
export ACFS_UPGRADE_LOCK="/var/run/acfs-upgrade.lock"

# Fallback logging if logging.sh not sourced
if ! declare -f log_fatal &>/dev/null; then
    log_fatal() { echo "FATAL: $1" >&2; exit 1; }
    log_detail() { echo "  $1" >&2; }
    log_warn() { echo "WARN: $1" >&2; }
    log_error() { echo "ERROR: $1" >&2; }
    log_success() { echo "OK: $1" >&2; }
    log_step() { echo "[*] $1" >&2; }
    log_section() { echo ""; echo "=== $1 ===" >&2; }
fi

# ============================================================
# Version Detection Functions
# ============================================================

# Get current Ubuntu version as comparable number
# e.g., 24.04 -> 2404, 25.10 -> 2510
# Returns: version number on stdout, or empty if not Ubuntu
ubuntu_get_version_number() {
    local version_str
    version_str=$(ubuntu_get_version_string)

    if [[ -z "$version_str" ]]; then
        return 1
    fi

    # Convert "24.04" to "2404"
    local major minor
    major="${version_str%%.*}"
    minor="${version_str#*.}"

    # Pad minor to 2 digits
    printf "%d%02d" "$major" "$minor"
}

# Get current Ubuntu version string
# e.g., "24.04", "25.10"
# Returns: version string on stdout, or empty if not Ubuntu
ubuntu_get_version_string() {
    if [[ ! -f /etc/os-release ]]; then
        return 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    if [[ "$ID" != "ubuntu" ]]; then
        return 1
    fi

    echo "$VERSION_ID"
}

# Compare two version numbers
# Returns: 0 if $1 >= $2, 1 otherwise
# Usage: ubuntu_version_gte 2404 2510  # returns 1 (24.04 < 25.10)
ubuntu_version_gte() {
    local v1="$1"
    local v2="$2"

    [[ "$v1" -ge "$v2" ]]
}

# Check if current Ubuntu needs upgrade
# Returns: 0 if upgrade needed, 1 if already at target or above
ubuntu_needs_upgrade() {
    local current_version
    current_version=$(ubuntu_get_version_number) || return 1

    if ubuntu_version_gte "$current_version" "$UBUNTU_TARGET_VERSION_NUM"; then
        return 1  # No upgrade needed
    fi

    return 0  # Upgrade needed
}

# ============================================================
# Upgrade Path Calculation Functions
# ============================================================

# Known Ubuntu version upgrade paths
# Ubuntu allows: sequential upgrades OR LTS-to-LTS jumps
# LTS versions: 22.04, 24.04 (next: 26.04)
# Non-LTS: 24.10, 25.04, 25.10

# Check if a version is LTS (Long Term Support)
# LTS versions are even years ending in .04 (22.04, 24.04, 26.04)
ubuntu_is_lts() {
    local version="${1:-}"

    if [[ -z "$version" ]]; then
        version=$(ubuntu_get_version_string) || return 1
    fi

    # Extract year
    local year="${version%%.*}"

    # LTS versions are even years + .04
    # 22.04, 24.04, 26.04, etc. (not 23.04, 25.04)
    [[ "$version" =~ ^[0-9]+\.04$ ]] && [[ $((year % 2)) -eq 0 ]]
}

# Get the next LTS version after the given version
ubuntu_get_next_lts() {
    local current="$1"
    local major="${current%%.*}"

    # LTS releases are every 2 years: 22.04, 24.04, 26.04, etc.
    if [[ "$current" =~ \.04$ ]]; then
        # Already on LTS, next LTS is current_year + 2
        echo "$((major + 2)).04"
    else
        # On non-LTS, find next LTS
        # 24.10 -> 26.04, 25.04 -> 26.04, etc.
        local next_lts_year=$(( (major / 2 + 1) * 2 ))
        echo "${next_lts_year}.04"
    fi
}

# Enable normal (non-LTS) release upgrades
# Required when upgrading from LTS to non-LTS releases
ubuntu_enable_normal_releases() {
    local config="/etc/update-manager/release-upgrades"

    if [[ ! -f "$config" ]]; then
        log_warn "Release upgrade config not found: $config"
        return 0
    fi

    # Check current setting
    if grep -q "^Prompt=lts" "$config"; then
        # Backup original
        cp "$config" "${config}.acfs-backup"

        # Change to normal releases
        sed -i 's/^Prompt=lts$/Prompt=normal/' "$config"

        log_detail "Enabled normal release upgrades (was LTS-only)"
    fi

    return 0
}

# Restore LTS-only release setting after upgrade complete
ubuntu_restore_lts_only() {
    local config="/etc/update-manager/release-upgrades"
    local backup="${config}.acfs-backup"

    if [[ -f "$backup" ]]; then
        mv "$backup" "$config"
        log_detail "Restored LTS-only release setting"
    fi

    return 0
}

# Get next available upgrade version by querying do-release-upgrade
# Returns: next version string (e.g., "24.10") or empty if none
ubuntu_get_next_upgrade() {
    # Check if do-release-upgrade is available
    if ! command -v do-release-upgrade &>/dev/null; then
        log_error "do-release-upgrade not found. Installing ubuntu-release-upgrader-core..."
        apt-get install -y ubuntu-release-upgrader-core &>/dev/null || return 1
    fi

    # Query available upgrade (check mode, don't actually do it)
    local output
    output=$(do-release-upgrade -c 2>&1) || true

    # Parse output for version info
    # Output looks like: "New release '24.10' available."
    if echo "$output" | grep -qE "New release '[0-9]+\.[0-9]+' available"; then
        echo "$output" | grep -oE "[0-9]+\.[0-9]+" | head -1
        return 0
    fi

    # No upgrade available
    return 1
}

# Get next upgrade version from hardcoded path
# Fallback when do-release-upgrade -c doesn't work (e.g., network issues)
# This function knows the Ubuntu release schedule
ubuntu_get_next_version_hardcoded() {
    local current="$1"

    case "$current" in
        2204) echo "24.04" ;;  # LTS to LTS
        2404) echo "24.10" ;;  # LTS to next
        2410) echo "25.04" ;;
        2504) echo "25.10" ;;
        *) return 1 ;;  # Unknown version
    esac
}

# Calculate full upgrade path from current to target
# Returns: newline-separated list of versions to upgrade through
# Usage: ubuntu_calculate_upgrade_path 2510
# shellcheck disable=SC2120  # $1 is optional with default
ubuntu_calculate_upgrade_path() {
    local target="${1:-$UBUNTU_TARGET_VERSION_NUM}"
    local current
    current=$(ubuntu_get_version_number) || return 1

    if ubuntu_version_gte "$current" "$target"; then
        return 0  # Already at or above target
    fi

    local path=()
    local check_version="$current"

    while [[ "$check_version" -lt "$target" ]]; do
        local next
        next=$(ubuntu_get_next_version_hardcoded "$check_version")

        if [[ -z "$next" ]]; then
            log_error "Cannot determine upgrade path from $check_version"
            return 1
        fi

        path+=("$next")

        # Convert to number for comparison
        local major="${next%%.*}"
        local minor="${next#*.}"
        check_version=$(printf "%d%02d" "$major" "$minor")
    done

    printf '%s\n' "${path[@]}"
}

# Get number of upgrades needed to reach target
ubuntu_upgrades_remaining() {
    local path
    path=$(ubuntu_calculate_upgrade_path) || return 1

    if [[ -z "$path" ]]; then
        echo "0"
        return 0
    fi

    echo "$path" | wc -l | tr -d ' '
}

# ============================================================
# Pre-upgrade Check Functions
# ============================================================

# Run all pre-upgrade validations
# Returns: 0 if all checks pass, 1 with error details if not
ubuntu_preflight_checks() {
    local failed=0

    log_step "Running Ubuntu upgrade preflight checks..."

    # Check we're on Ubuntu
    if ! ubuntu_get_version_string &>/dev/null; then
        log_error "Not running Ubuntu - upgrade not supported"
        return 1
    fi

    # Check running as root
    if ! ubuntu_check_root; then
        ((failed++))
    fi

    # Check not in Docker
    if ! ubuntu_check_not_docker; then
        ((failed++))
    fi

    # Check not in WSL
    if ! ubuntu_check_not_wsl; then
        ((failed++))
    fi

    # Check disk space
    if ! ubuntu_check_disk_space; then
        ((failed++))
    fi

    # Check network connectivity
    if ! ubuntu_check_network; then
        ((failed++))
    fi

    # Check apt state
    if ! ubuntu_check_apt_state; then
        ((failed++))
    fi

    # Check for recent boot (warning only, no failure)
    ubuntu_check_recent_boot || true

    if [[ $failed -gt 0 ]]; then
        log_error "Preflight checks failed: $failed issue(s)"
        return 1
    fi

    log_success "All preflight checks passed"
    return 0
}

# Check sufficient disk space for upgrade
ubuntu_check_disk_space() {
    local available_mb
    available_mb=$(df -mP / | awk 'NR==2 {print $4}')

    if [[ "$available_mb" -lt "$UBUNTU_UPGRADE_MIN_DISK_MB" ]]; then
        log_error "Insufficient disk space: ${available_mb}MB available, need ${UBUNTU_UPGRADE_MIN_DISK_MB}MB"
        return 1
    fi

    log_detail "Disk space: ${available_mb}MB available (need ${UBUNTU_UPGRADE_MIN_DISK_MB}MB)"
    return 0
}

# Check network connectivity to Ubuntu repositories
ubuntu_check_network() {
    # Test connectivity to archive.ubuntu.com
    if ! timeout 10 curl -sfI https://archive.ubuntu.com &>/dev/null; then
        log_error "Cannot reach archive.ubuntu.com - check network connectivity"
        return 1
    fi

    log_detail "Network: can reach Ubuntu repositories"
    return 0
}

# Check apt state - no broken packages
ubuntu_check_apt_state() {
    # Check for broken packages
    if ! dpkg --audit &>/dev/null; then
        log_error "dpkg audit failed - run 'sudo dpkg --configure -a'"
        return 1
    fi

    # Check for held packages that might block upgrade
    local held
    held=$(apt-mark showhold 2>/dev/null)
    if [[ -n "$held" ]]; then
        log_warn "Held packages detected (may block upgrade): $held"
        # Not a fatal error, just a warning
    fi

    log_detail "APT state: healthy"
    return 0
}

# Check we're not in a Docker container
ubuntu_check_not_docker() {
    if [[ -f /.dockerenv ]]; then
        log_error "Running in Docker - distribution upgrades not supported in containers"
        return 1
    fi

    if grep -q docker /proc/1/cgroup 2>/dev/null; then
        log_error "Running in Docker - distribution upgrades not supported in containers"
        return 1
    fi

    log_detail "Environment: not a container"
    return 0
}

# Check running as root
ubuntu_check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Must run as root for distribution upgrade"
        return 1
    fi

    log_detail "Permissions: running as root"
    return 0
}

# Check we're not in WSL (Windows Subsystem for Linux)
ubuntu_check_not_wsl() {
    if grep -qi microsoft /proc/version 2>/dev/null; then
        log_error "Running in WSL - Ubuntu upgrades not supported in WSL"
        return 1
    fi

    log_detail "Environment: not WSL"
    return 0
}

# Check for recent boot (system stability)
ubuntu_check_recent_boot() {
    local uptime_seconds
    uptime_seconds=$(cut -d. -f1 < /proc/uptime)

    if [[ "$uptime_seconds" -lt 60 ]]; then
        log_warn "System just booted. Waiting 30 seconds for services to stabilize..."
        sleep 30
    fi

    log_detail "System stability: uptime ${uptime_seconds}s"
    return 0
}

# ============================================================
# Upgrade Execution Functions
# ============================================================

# Prepare system before upgrade
# Runs apt update and dist-upgrade to ensure clean state
ubuntu_prepare_upgrade() {
    log_step "Preparing system for upgrade..."

    # Update package lists
    log_detail "Updating package lists..."
    if ! apt-get update -y; then
        log_error "apt-get update failed"
        return 1
    fi

    # Upgrade existing packages
    log_detail "Upgrading installed packages..."
    export DEBIAN_FRONTEND=noninteractive
    if ! apt-get dist-upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"; then
        log_error "apt-get dist-upgrade failed"
        return 1
    fi

    # Clean up
    apt-get autoremove -y &>/dev/null || true
    apt-get autoclean -y &>/dev/null || true

    log_success "System prepared for upgrade"
    return 0
}

# Perform single-version Ubuntu upgrade (non-interactive)
# Returns: 0 on success (reboot may be required), 1 on failure
ubuntu_do_upgrade() {
    local expected_next_version="${1:-}"

    local next_version=""
    next_version="$(ubuntu_get_next_upgrade || true)"

    if [[ -z "$next_version" ]]; then
        log_error "No upgrade available"
        return 1
    fi

    if [[ -n "$expected_next_version" ]] && [[ "$next_version" != "$expected_next_version" ]]; then
        log_error "Unexpected upgrade target detected"
        log_error "  Expected: $expected_next_version"
        log_error "  Detected:  $next_version"
        log_error "This is usually caused by LTS-only upgrade settings (Prompt=lts)."
        log_error "Fix: set Prompt=normal in /etc/update-manager/release-upgrades and retry."
        return 1
    fi

    log_section "Upgrading Ubuntu to $next_version"
    log_warn "This will take 30-60 minutes. System will reboot when complete."

    # Prepare the system first
    if ! ubuntu_prepare_upgrade; then
        return 1
    fi

    # Run do-release-upgrade in non-interactive mode
    log_step "Starting do-release-upgrade..."

    # The -f flag specifies the frontend
    # DistUpgradeViewNonInteractive is for fully automated upgrades
    export DEBIAN_FRONTEND=noninteractive

    if ! do-release-upgrade -f DistUpgradeViewNonInteractive; then
        log_error "do-release-upgrade failed"
        return 1
    fi

    log_success "Upgrade to $next_version complete"
    log_warn "System needs to reboot to complete the upgrade"

    return 0
}

# Setup resume mechanism for after reboot
# Creates systemd service that will run on next boot
ubuntu_setup_resume() {
    local resume_script="$1"  # Script to run after reboot
    local service_name="${2:-acfs-resume}"

    if [[ -z "$resume_script" ]]; then
        log_error "No resume script specified"
        return 1
    fi

    log_step "Setting up resume service for post-reboot..."

    # Create systemd service file
    cat > "/etc/systemd/system/${service_name}.service" << EOF
[Unit]
Description=ACFS Installation Resume (after Ubuntu upgrade)
After=network-online.target
Wants=network-online.target
ConditionPathExists=$resume_script

[Service]
Type=oneshot
ExecStart=$resume_script
RemainAfterExit=no
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF

    # Enable the service
    systemctl daemon-reload
    systemctl enable "${service_name}.service"

    log_success "Resume service created: ${service_name}.service"
    return 0
}

# Cleanup resume mechanism after completion
ubuntu_cleanup_resume() {
    local service_name="${1:-acfs-resume}"

    log_step "Cleaning up resume service..."

    # Disable and remove the service
    systemctl disable "${service_name}.service" 2>/dev/null || true
    rm -f "/etc/systemd/system/${service_name}.service"
    systemctl daemon-reload

    log_success "Resume service removed"
    return 0
}

# Trigger reboot with delay (in minutes)
# Allows SSH sessions to close gracefully
# Note: shutdown -r +N uses MINUTES, not seconds
ubuntu_trigger_reboot() {
    local delay_minutes="${1:-1}"

    log_warn "System will reboot in $delay_minutes minute(s)..."
    log_warn "Reconnect via SSH after reboot to continue."

    # Use shutdown for graceful reboot
    # Note: +N means N minutes from now
    shutdown -r +"$delay_minutes" "ACFS: Ubuntu upgrade requires reboot" &

    return 0
}

# ============================================================
# Status and Reporting Functions
# ============================================================

# Get current upgrade status summary
ubuntu_upgrade_status() {
    local current_version
    current_version=$(ubuntu_get_version_string) || {
        echo "Not Ubuntu"
        return 1
    }

    local current_num
    current_num=$(ubuntu_get_version_number)

    echo "Current: Ubuntu $current_version"
    echo "Target:  Ubuntu $UBUNTU_TARGET_VERSION"

    if ubuntu_version_gte "$current_num" "$UBUNTU_TARGET_VERSION_NUM"; then
        echo "Status:  At or above target version"
        return 0
    fi

    local remaining
    remaining=$(ubuntu_upgrades_remaining)
    echo "Upgrades needed: $remaining"

    echo "Upgrade path:"
    ubuntu_calculate_upgrade_path | while read -r version; do
        echo "  → $version"
    done

    return 0
}

# Print pre-upgrade warning message
ubuntu_print_upgrade_warning() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    UBUNTU UPGRADE REQUIRED                     ║"
    echo "╠════════════════════════════════════════════════════════════════╣"
    echo "║  Your Ubuntu version needs to be upgraded before installing   ║"
    echo "║  ACFS. This process is fully automatic but takes 30-60 min   ║"
    echo "║  per version and requires reboots.                            ║"
    echo "║                                                                ║"
    echo "║  IMPORTANT:                                                    ║"
    echo "║  • Create a VM snapshot/backup before proceeding              ║"
    echo "║  • SSH connections will drop during reboot                    ║"
    echo "║  • Reconnect after reboot - installation will auto-resume    ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    ubuntu_upgrade_status
    echo ""
}

# ============================================================
# MOTD and User Communication Functions
# ============================================================

# Update MOTD to show upgrade status
# This helps users understand what's happening when they reconnect via SSH
upgrade_update_motd() {
    local message="${1:-Ubuntu upgrade in progress}"
    local motd_file="/etc/update-motd.d/00-acfs-upgrade"

    # Truncate message to fit in 60-char content area (leaving space for "║  " and " ║")
    local max_len=60
    if [[ ${#message} -gt $max_len ]]; then
        message="${message:0:$((max_len - 3))}..."
    fi
    # Pad message to fill the box width
    local padded_msg
    padded_msg=$(printf "%-${max_len}s" "$message")

    # Create MOTD script
    cat > "$motd_file" << 'MOTD_HEADER'
#!/bin/bash
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    ACFS UPGRADE IN PROGRESS                    ║"
echo "╠════════════════════════════════════════════════════════════════╣"
MOTD_HEADER

    # Add the dynamic message (properly padded)
    cat >> "$motd_file" << MOTD_MESSAGE
echo "║  ${padded_msg} ║"
MOTD_MESSAGE

    cat >> "$motd_file" << 'MOTD_FOOTER'
echo "║                                                                ║"
echo "║  The system will reboot automatically when each upgrade       ║"
echo "║  step completes. Do not interrupt this process.               ║"
echo "║                                                                ║"
echo "║  View logs: journalctl -u acfs-upgrade-resume -f              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
MOTD_FOOTER

    chmod +x "$motd_file"
}

# Remove MOTD upgrade notice
upgrade_remove_motd() {
    rm -f /etc/update-motd.d/00-acfs-upgrade
}

# ============================================================
# Lock File and Progress Functions
# ============================================================

# Acquire upgrade lock to prevent concurrent runs
# Returns: 0 if lock acquired, 1 if already locked
upgrade_acquire_lock() {
    if [[ -f "$ACFS_UPGRADE_LOCK" ]]; then
        local pid
        pid=$(cat "$ACFS_UPGRADE_LOCK" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_error "Another upgrade is in progress (PID: $pid)"
            return 1
        fi
        # Stale lock file - remove it
        rm -f "$ACFS_UPGRADE_LOCK"
    fi

    echo $$ > "$ACFS_UPGRADE_LOCK"
    return 0
}

# Release upgrade lock
upgrade_release_lock() {
    rm -f "$ACFS_UPGRADE_LOCK"
}

# Show progress and time estimation
# Usage: upgrade_show_progress <current_hop> <total_hops>
upgrade_show_progress() {
    local current_hop="${1:-1}"
    local total_hops="${2:-1}"
    local minutes_per_hop=45

    local remaining_hops=$((total_hops - current_hop + 1))
    local remaining_minutes=$((remaining_hops * minutes_per_hop))

    log_step "Progress: Upgrade $current_hop of $total_hops"
    log_detail "Estimated time remaining: ~${remaining_minutes} minutes"
}

# Display pre-reboot warning with countdown
# Usage: upgrade_warn_reboot [delay_seconds]
upgrade_warn_reboot() {
    local delay="${1:-30}"

    echo ""
    log_warn "╔══════════════════════════════════════════════════════════╗"
    log_warn "║  System will reboot in $delay seconds for Ubuntu upgrade     ║"
    log_warn "║                                                          ║"
    log_warn "║  Your SSH session will disconnect.                       ║"
    log_warn "║  Wait 2-3 minutes, then reconnect.                       ║"
    log_warn "║  The upgrade will continue automatically.                ║"
    log_warn "╚══════════════════════════════════════════════════════════╝"
    echo ""

    # Countdown display
    for i in $(seq "$delay" -1 1); do
        echo -ne "\rRebooting in $i seconds... "
        sleep 1
    done
    echo ""
}

# Create status check script for users
upgrade_create_status_script() {
    cat > "${ACFS_RESUME_DIR}/check_status.sh" << 'STATUS_SCRIPT'
#!/usr/bin/env bash
# ACFS Upgrade Status Checker

STATE_FILE="/var/lib/acfs/state.json"

if [[ ! -f "$STATE_FILE" ]]; then
    echo "No upgrade in progress"
    exit 0
fi

if ! command -v jq &>/dev/null; then
    echo "jq not installed - showing raw state:"
    cat "$STATE_FILE"
    exit 0
fi

echo "═══════════════════════════════════════════════════"
echo "  ACFS Ubuntu Upgrade Status"
echo "═══════════════════════════════════════════════════"

jq -r '
    "  Original version: " + (.ubuntu_upgrade.original_version // "N/A"),
    "  Target version:   " + (.ubuntu_upgrade.target_version // "N/A"),
    "  Current stage:    " + (.ubuntu_upgrade.current_stage // "N/A"),
    "  Upgrades done:    " + ((.ubuntu_upgrade.completed_upgrades // []) | length | tostring) + "/" + ((.ubuntu_upgrade.upgrade_path // []) | length | tostring),
    ""
' "$STATE_FILE"

# Show completed upgrades
completed=$(jq -r '.ubuntu_upgrade.completed_upgrades // []' "$STATE_FILE")
if [[ "$completed" != "[]" ]]; then
    echo "  Completed upgrades:"
    jq -r '.ubuntu_upgrade.completed_upgrades[] | "    ✓ " + .from + " → " + .to' "$STATE_FILE"
fi

echo "═══════════════════════════════════════════════════"
echo "  Logs: /var/log/acfs/upgrade_resume.log"
echo "═══════════════════════════════════════════════════"
STATUS_SCRIPT

    chmod +x "${ACFS_RESUME_DIR}/check_status.sh"
}

# ============================================================
# Upgrade Infrastructure Setup/Teardown
# ============================================================

# Setup complete resume infrastructure
# This copies all necessary files and sets up systemd service
# Usage: upgrade_setup_infrastructure <acfs_source_dir> [original_install_args...]
upgrade_setup_infrastructure() {
    local source_dir="$1"
    shift
    local install_args=("$@")
    local service_template="${source_dir}/scripts/templates/acfs-upgrade-resume.service"

    log_step "Setting up upgrade resume infrastructure..."

    # Create directory structure
    mkdir -p "${ACFS_RESUME_DIR}/lib"
    mkdir -p /var/log/acfs

    # Copy required library files
    log_detail "Copying library files..."
    local libs=(logging.sh state.sh ubuntu_upgrade.sh os_detect.sh)
    for lib in "${libs[@]}"; do
        if [[ -f "${source_dir}/scripts/lib/${lib}" ]]; then
            cp "${source_dir}/scripts/lib/${lib}" "${ACFS_RESUME_DIR}/lib/"
        else
            log_warn "Library not found: ${lib}"
        fi
    done

    # Copy upgrade resume script
    log_detail "Copying resume script..."
    if [[ ! -f "${source_dir}/scripts/lib/upgrade_resume.sh" ]]; then
        log_error "Upgrade resume script not found: ${source_dir}/scripts/lib/upgrade_resume.sh"
        return 1
    fi
    cp "${source_dir}/scripts/lib/upgrade_resume.sh" "${ACFS_RESUME_DIR}/"
    chmod +x "${ACFS_RESUME_DIR}/upgrade_resume.sh"

    # Create a user-facing status helper (referenced by README).
    upgrade_create_status_script

    # Copy current state file if exists
    local state_file
    state_file="$(state_get_file 2>/dev/null || echo "${HOME}/.acfs/state.json")"
    local dest_state_file="${ACFS_RESUME_DIR}/state.json"
    if [[ -f "$state_file" ]] && [[ "$state_file" != "$dest_state_file" ]]; then
        cp "$state_file" "$dest_state_file"
    fi

    # Create continue_install.sh script
    # This runs after all upgrades complete to resume ACFS installation
    log_detail "Creating continuation script..."
    local repo_owner repo_name repo_ref
    repo_owner="${ACFS_REPO_OWNER:-Dicklesworthstone}"
    repo_name="${ACFS_REPO_NAME:-agentic_coding_flywheel_setup}"
    repo_ref="${ACFS_REF:-main}"
    local source_dir_q repo_ref_q install_url install_url_q
    source_dir_q=$(printf '%q' "$source_dir")
    repo_ref_q=$(printf '%q' "$repo_ref")
    install_url="https://raw.githubusercontent.com/${repo_owner}/${repo_name}/${repo_ref}/install.sh"
    install_url_q=$(printf '%q' "$install_url")

    local -a continue_args=("${install_args[@]}" "--skip-ubuntu-upgrade")
    local rendered_args=""
    local arg=""
    for arg in "${continue_args[@]}"; do
        rendered_args+=" $(printf '%q' "$arg")"
    done
    rendered_args="${rendered_args# }"

    cat > "${ACFS_RESUME_DIR}/continue_install.sh" << CONTINUE_SCRIPT
#!/usr/bin/env bash
# Auto-generated script to continue ACFS installation after Ubuntu upgrades
set -euo pipefail

echo "Ubuntu upgrade complete. Resuming ACFS installation..."

# Prefer local source dir (only if it still exists), else fetch from GitHub.
SOURCE_DIR=${source_dir_q}
export ACFS_REF=${repo_ref_q}
INSTALL_URL=${install_url_q}

INSTALL_ARGS=(${rendered_args})

if [[ -f "\${SOURCE_DIR}/install.sh" ]]; then
    echo "Using local installer: \${SOURCE_DIR}/install.sh"
    (cd "\${SOURCE_DIR}" && bash ./install.sh "\${INSTALL_ARGS[@]}")
else
    echo "Fetching installer: \${INSTALL_URL}"
    curl -fsSL "\${INSTALL_URL}" | bash -s -- "\${INSTALL_ARGS[@]}"
fi

echo "ACFS installation complete!"
CONTINUE_SCRIPT
    chmod +x "${ACFS_RESUME_DIR}/continue_install.sh"

    # Install systemd service
    log_detail "Installing systemd service..."
    if [[ -f "$service_template" ]]; then
        cp "$service_template" /etc/systemd/system/acfs-upgrade-resume.service
    else
        # Generate service file inline if template not found
        cat > /etc/systemd/system/acfs-upgrade-resume.service << 'SERVICE'
[Unit]
Description=ACFS Ubuntu Upgrade Resume Service
After=network-online.target
Wants=network-online.target
ConditionPathExists=/var/lib/acfs/upgrade_resume.sh

[Service]
Type=oneshot
ExecStart=/bin/bash /var/lib/acfs/upgrade_resume.sh
TimeoutStartSec=7200
Restart=no
RemainAfterExit=no
StandardOutput=journal+console
StandardError=journal+console
User=root
Group=root

[Install]
WantedBy=multi-user.target
SERVICE
    fi

    # Enable the service
    systemctl daemon-reload
    systemctl enable acfs-upgrade-resume.service

    log_success "Upgrade infrastructure setup complete"
    return 0
}

# Teardown upgrade infrastructure
# Removes all temporary files and systemd service
upgrade_teardown_infrastructure() {
    log_step "Tearing down upgrade infrastructure..."

    # Disable and remove systemd service
    systemctl disable acfs-upgrade-resume.service 2>/dev/null || true
    rm -f /etc/systemd/system/acfs-upgrade-resume.service
    systemctl daemon-reload

    # Remove MOTD notice
    upgrade_remove_motd

    # Remove temporary files (keep logs)
    rm -rf "${ACFS_RESUME_DIR:?}/lib"
    rm -f "${ACFS_RESUME_DIR:?}/upgrade_resume.sh"
    rm -f "${ACFS_RESUME_DIR:?}/continue_install.sh"
    rm -f "${ACFS_RESUME_DIR:?}/state.json"

    # Keep the directory for logs reference
    # rm -rf "${ACFS_RESUME_DIR}"

    log_success "Upgrade infrastructure removed"
    return 0
}

# ============================================================
# Main Upgrade Orchestration
# ============================================================

# Start the complete upgrade process
# This is the main entry point for initiating upgrades
# Usage: ubuntu_start_upgrade_sequence <source_dir> [install_args...]
ubuntu_start_upgrade_sequence() {
    local source_dir="$1"
    shift
    local install_args=("$@")

    # Get current and target versions
    local current_version
    current_version=$(ubuntu_get_version_string) || {
        log_error "Failed to get current Ubuntu version"
        return 1
    }

    local current_num
    current_num=$(ubuntu_get_version_number)

    # Check if upgrade is needed
    if ubuntu_version_gte "$current_num" "$UBUNTU_TARGET_VERSION_NUM"; then
        log_success "Ubuntu $current_version is at or above target version"
        return 0
    fi

    log_section "Starting Ubuntu Upgrade Sequence"
    log_step "Current: Ubuntu $current_version"
    log_step "Target:  Ubuntu $UBUNTU_TARGET_VERSION"

    # Ensure non-LTS upgrades are permitted (LTS defaults to Prompt=lts).
    # ACFS targets interim releases (e.g. 24.10, 25.04, 25.10) on the path to 25.10.
    ubuntu_enable_normal_releases || true

    # Calculate upgrade path
    local upgrade_path
    upgrade_path=$(ubuntu_calculate_upgrade_path)

    if [[ -z "$upgrade_path" ]]; then
        log_error "Cannot determine upgrade path"
        return 1
    fi

    local upgrade_count
    upgrade_count=$(echo "$upgrade_path" | wc -l | tr -d ' ')
    log_step "Upgrades needed: $upgrade_count"

    # Convert upgrade path to JSON array for state
    local path_json
    path_json=$(echo "$upgrade_path" | jq -R . | jq -s .)

    # Initialize state tracking
    state_upgrade_init "$current_version" "$UBUNTU_TARGET_VERSION" "$path_json"

    # Setup infrastructure for resume after reboot
    upgrade_setup_infrastructure "$source_dir" "${install_args[@]}"

    # Update MOTD
    upgrade_update_motd "Starting upgrade: $current_version → $UBUNTU_TARGET_VERSION"

    # Start first upgrade
    local first_target
    first_target=$(echo "$upgrade_path" | head -1)

    state_upgrade_start "$current_version" "$first_target"

    if ! ubuntu_do_upgrade "$first_target"; then
        log_error "First upgrade failed"
        state_upgrade_set_error "do-release-upgrade failed"
        return 1
    fi

    # Mark first upgrade complete
    state_upgrade_complete "$first_target"

    # Mark needs reboot
    state_upgrade_needs_reboot

    # Copy updated state to resume location
    local state_file
    state_file="$(state_get_file)"
    if [[ -f "$state_file" ]] && [[ "$state_file" != "${ACFS_RESUME_DIR}/state.json" ]]; then
        cp "$state_file" "${ACFS_RESUME_DIR}/state.json"
    fi

    # Update MOTD before reboot
    upgrade_update_motd "Rebooting for upgrade to $first_target..."

    # Trigger reboot (1 minute delay for user to read messages)
    log_warn "Upgrade step complete. Rebooting in 1 minute..."
    log_warn "Reconnect via SSH after reboot. Upgrade will continue automatically."
    ubuntu_trigger_reboot 1

    return 0
}

# ============================================================
# Snapshot Recommendation and Safety Warnings
# ============================================================

# Show comprehensive upgrade warning with snapshot recommendation
ubuntu_show_upgrade_warning() {
    local current
    current=$(ubuntu_get_version_string)
    local target="$UBUNTU_TARGET_VERSION"
    local path
    path=$(ubuntu_calculate_upgrade_path)
    local hops
    hops=$(echo "$path" | wc -l | tr -d ' ')
    local estimated_time=$((hops * 45))

    cat << EOF

╔══════════════════════════════════════════════════════════════════╗
║           ACFS Ubuntu Upgrade - READ CAREFULLY                   ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  Current version:  Ubuntu $current
║  Target version:   Ubuntu $target
║  Upgrade path:     $(echo "$path" | tr '\n' ' ')
║  Estimated time:   ~${estimated_time} minutes
║                                                                  ║
╠══════════════════════════════════════════════════════════════════╣
║  WARNING:                                                        ║
║                                                                  ║
║  • OS upgrades CANNOT be undone                                  ║
║  • System will reboot $hops time(s)
║  • SSH sessions will disconnect during reboots                   ║
║  • Reconnect after each reboot to monitor progress               ║
║                                                                  ║
╠══════════════════════════════════════════════════════════════════╣
║  RECOMMENDED: Take a snapshot BEFORE proceeding                  ║
║                                                                  ║
║  Most cloud providers support snapshots:                         ║
║  • Hetzner:  Cloud Console > Snapshots                           ║
║  • OVH:      Control Panel > VPS > Snapshot                      ║
║  • Contabo:  Customer Panel > Snapshots                          ║
║  • AWS:      EC2 > Snapshots > Create Snapshot                   ║
║  • DigitalOcean: Droplets > Snapshots                            ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

EOF
}

# Confirm upgrade with user (for interactive mode)
ubuntu_confirm_upgrade() {
    # In --yes mode, show warning but proceed
    if [[ "${YES_MODE:-false}" == "true" ]]; then
        ubuntu_show_upgrade_warning
        log_warn "Proceeding automatically (--yes mode)"
        log_warn "Press Ctrl+C within 10 seconds to abort..."
        sleep 10
        return 0
    fi

    ubuntu_show_upgrade_warning

    echo ""
    echo "Have you taken a snapshot? (Recommended but not required)"
    echo ""

    read -r -p "Proceed with Ubuntu upgrade? [y/N] " response
    if [[ ! "$response" =~ ^[Yy] ]]; then
        log_warn "Upgrade cancelled by user"
        return 1
    fi

    return 0
}

# ============================================================
# Error Recovery and Graceful Degradation
# ============================================================

# Retry a command with exponential backoff
# Usage: ubuntu_retry_with_backoff <command> [max_retries] [initial_delay]
ubuntu_retry_with_backoff() {
    local cmd="$1"
    local max_retries="${2:-5}"
    local delay="${3:-30}"

    for i in $(seq 1 "$max_retries"); do
        if eval "$cmd"; then
            return 0
        fi

        log_warn "Attempt $i failed, retrying in ${delay}s..."
        sleep "$delay"
        delay=$((delay * 2))  # Exponential backoff
    done

    log_error "Command failed after $max_retries attempts"
    return 1
}

# Emergency disk cleanup when running low on space
ubuntu_emergency_cleanup() {
    log_warn "Attempting emergency disk cleanup..."

    # Clear apt cache
    apt-get clean 2>/dev/null || true

    # Remove old kernels (keep current)
    apt-get autoremove -y 2>/dev/null || true

    # Clear old journal logs
    journalctl --vacuum-size=100M 2>/dev/null || true

    # Report remaining space
    local available
    available=$(df -hP / | awk 'NR==2 {print $4}')
    log_detail "Available space after cleanup: $available"
}

# Internal helper: Check if dpkg is locked
# Uses fuser if available, falls back to lsof, then simple file check
_dpkg_is_locked() {
    local lock_file="/var/lib/dpkg/lock-frontend"

    # Try fuser first (most reliable)
    if command -v fuser &>/dev/null; then
        fuser "$lock_file" >/dev/null 2>&1
        return $?
    fi

    # Fallback to lsof
    if command -v lsof &>/dev/null; then
        lsof "$lock_file" >/dev/null 2>&1
        return $?
    fi

    # Last resort: check if lock file exists and any apt/dpkg process is running
    # This is less reliable but better than nothing
    if [[ -f "$lock_file" ]]; then
        # Check for common package manager process names
        # Use pgrep -x for exact process name matching to avoid false positives
        # (e.g., matching "cat /var/log/apt/history.log")
        pgrep -x "apt" >/dev/null 2>&1 && return 0
        pgrep -x "apt-get" >/dev/null 2>&1 && return 0
        pgrep -x "dpkg" >/dev/null 2>&1 && return 0
        pgrep -x "aptitude" >/dev/null 2>&1 && return 0
        pgrep -x "unattended-upgr" >/dev/null 2>&1 && return 0
        # No matching process found
        return 1
    fi

    return 1  # Not locked
}

# Fix interrupted dpkg operations
ubuntu_fix_dpkg() {
    log_warn "Fixing interrupted dpkg operations..."

    # Wait for any running apt/dpkg
    local max_wait=300  # 5 minutes
    local waited=0

    # Check for dpkg lock - use fuser if available, fallback to lsof or file check
    while _dpkg_is_locked; do
        if [[ $waited -ge $max_wait ]]; then
            log_error "Timeout waiting for dpkg lock"
            return 1
        fi
        sleep 5
        waited=$((waited + 5))
    done

    # Configure any unpacked packages
    dpkg --configure -a 2>/dev/null || true

    # Fix broken dependencies
    apt-get -f install -y 2>/dev/null || true

    log_success "dpkg state fixed"
    return 0
}

# Attempt to recover from failed upgrade
ubuntu_recover_failed_upgrade() {
    log_warn "Attempting to recover from failed upgrade..."

    # Try fixing dpkg first
    ubuntu_fix_dpkg

    # Check disk space
    local available_mb
    available_mb=$(df -mP / | awk 'NR==2 {print $4}')
    if [[ "$available_mb" -lt 1000 ]]; then
        ubuntu_emergency_cleanup
    fi

    # Try dist-upgrade to complete any partial upgrade
    export DEBIAN_FRONTEND=noninteractive
    if apt-get dist-upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" 2>/dev/null; then
        log_success "Recovery dist-upgrade succeeded"
        return 0
    fi

    log_error "Recovery failed - manual intervention may be required"
    return 1
}

# Create diagnostic dump on failure
ubuntu_create_diagnostic_dump() {
    local dump_file
    dump_file="/var/log/acfs/upgrade_diagnostic_$(date +%Y%m%d_%H%M%S).txt"

    mkdir -p /var/log/acfs

    {
        echo "=== ACFS Upgrade Diagnostic Dump ==="
        echo "Timestamp: $(date)"
        echo ""
        echo "=== Ubuntu Version ==="
        cat /etc/os-release 2>/dev/null || echo "Cannot read /etc/os-release"
        echo ""
        echo "=== Disk Space ==="
        df -h
        echo ""
        echo "=== Memory ==="
        free -h
        echo ""
        echo "=== dpkg Status ==="
        dpkg --audit 2>/dev/null || echo "dpkg audit failed"
        echo ""
        echo "=== Held Packages ==="
        apt-mark showhold 2>/dev/null || echo "Cannot list held packages"
        echo ""
        echo "=== APT History (last 50 lines) ==="
        tail -50 /var/log/apt/history.log 2>/dev/null || echo "No apt history"
        echo ""
        echo "=== ACFS Upgrade State ==="
        cat "${ACFS_RESUME_DIR}/state.json" 2>/dev/null || echo "No state file"
        echo ""
        echo "=== Last 100 lines of upgrade log ==="
        tail -100 /var/log/acfs/upgrade_resume.log 2>/dev/null || echo "No upgrade log"
    } > "$dump_file"

    log_warn "Diagnostic dump saved to: $dump_file"
    echo "$dump_file"
}

# Graceful degradation - continue ACFS on current version if upgrade fails
ubuntu_upgrade_with_fallback() {
    if ubuntu_do_upgrade; then
        return 0
    fi

    log_error "Ubuntu upgrade failed"

    # Attempt recovery
    if ubuntu_recover_failed_upgrade; then
        log_success "Recovery successful - retrying upgrade"
        if ubuntu_do_upgrade; then
            return 0
        fi
    fi

    # Create diagnostic dump
    ubuntu_create_diagnostic_dump

    # Check if system is still functional
    if apt-get update &>/dev/null; then
        log_warn "System is functional. Continuing ACFS on current Ubuntu version."
        log_warn "Some features may not work optimally on older Ubuntu."

        # Mark upgrade as skipped, not failed
        state_upgrade_set_error "upgrade_failed_graceful_degradation"

        # Return success to allow ACFS to continue
        return 0
    else
        log_error "System may be in inconsistent state. Manual recovery needed."
        log_error "Check diagnostic dump and /var/log/acfs/upgrade_resume.log"
        return 1
    fi
}
