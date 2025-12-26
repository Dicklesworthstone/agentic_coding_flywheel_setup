#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Installer - Tailscale Library
# Installs and verifies Tailscale VPN for secure remote access
# ============================================================

TAILSCALE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure we have logging functions available
if [[ -z "${ACFS_BLUE:-}" ]]; then
    # shellcheck source=logging.sh
    source "$TAILSCALE_SCRIPT_DIR/logging.sh"
fi

# ============================================================
# Helper Functions
# ============================================================

# Get sudo command (empty if already root)
_tailscale_get_sudo() {
    if [[ $EUID -eq 0 ]]; then
        echo ""
    else
        echo "sudo"
    fi
}

# Check if systemd is available
_tailscale_has_systemd() {
    command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]
}

# Get Tailscale backend state (jq optional)
_tailscale_backend_state() {
    local output
    output=$(tailscale status --json 2>/dev/null || echo "")
    if [[ -z "$output" ]]; then
        echo "unknown"
        return 0
    fi

    if command -v jq &>/dev/null; then
        local state
        state=$(printf '%s' "$output" | jq -r '.BackendState // "unknown"' 2>/dev/null || echo "unknown")
        echo "$state"
        return 0
    fi

    local state
    state=$(printf '%s' "$output" | sed -n 's/.*"BackendState"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    if [[ -z "$state" ]]; then
        state="unknown"
    fi
    echo "$state"
}

# Get Ubuntu codename with fallback
_tailscale_get_codename() {
    local codename=""

    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        codename="${VERSION_CODENAME:-}"
    fi

    # Fallback to lsb_release if available
    if [[ -z "$codename" ]] && command -v lsb_release &>/dev/null; then
        codename=$(lsb_release -cs 2>/dev/null)
    fi

    # Map newer Ubuntu codenames to supported Tailscale repos
    case "$codename" in
        oracular|plucky|questing) codename="noble" ;;
    esac

    # Default to noble (24.04) if we can't determine
    echo "${codename:-noble}"
}

# ============================================================
# Installation Functions
# ============================================================

# Install Tailscale via official APT repository
# This is the recommended method for Ubuntu systems
install_tailscale() {
    local sudo_cmd
    sudo_cmd=$(_tailscale_get_sudo)

    # Check if already installed
    if command -v tailscale &>/dev/null; then
        log_detail "Tailscale already installed"
        local version
        version=$(tailscale version 2>/dev/null | head -1 || echo "unknown")
        log_detail "  Version: $version"
        return 0
    fi

    log_detail "Installing Tailscale..."

    # Get Ubuntu codename for APT repo
    local codename
    codename=$(_tailscale_get_codename)
    log_detail "  Ubuntu codename: $codename"

    # Add Tailscale signing key
    log_detail "  Adding Tailscale repository..."
    if ! (
        set -o pipefail
        curl --proto '=https' --proto-redir '=https' -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${codename}.noarmor.gpg" \
            | $sudo_cmd tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null 2>&1
    ); then
        log_warn "Failed to add Tailscale signing key"
        log_detail "  Trying fallback with generic key..."
        # Fallback: try without codename-specific key
        if ! (
            set -o pipefail
            curl --proto '=https' --proto-redir '=https' -fsSL "https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg" \
                | $sudo_cmd tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null 2>&1
        ); then
            log_error "Failed to add Tailscale repository key"
            return 1
        fi
    fi

    # Add APT repository
    echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu ${codename} main" \
        | $sudo_cmd tee /etc/apt/sources.list.d/tailscale.list >/dev/null

    # Update package list
    log_detail "  Updating package list..."
    if ! $sudo_cmd apt-get update -qq 2>/dev/null; then
        log_warn "apt-get update had issues, continuing anyway..."
    fi

    # Install tailscale package
    log_detail "  Installing tailscale package..."
    if ! $sudo_cmd apt-get install -y -qq tailscale 2>/dev/null; then
        log_error "Failed to install tailscale package"
        return 1
    fi

    # Enable and start the daemon (if systemd available)
    if _tailscale_has_systemd; then
        log_detail "  Enabling tailscaled service..."
        $sudo_cmd systemctl enable tailscaled >/dev/null 2>&1 || true
        $sudo_cmd systemctl start tailscaled >/dev/null 2>&1 || true
    else
        log_detail "  Skipping systemd service setup (no systemd)"
    fi

    # Verify installation
    if command -v tailscale &>/dev/null; then
        local version
        version=$(tailscale version 2>/dev/null | head -1 || echo "installed")
        log_success "Tailscale installed (v$version)"
        log_detail "  Run 'sudo tailscale up' to authenticate"
        return 0
    else
        log_error "Tailscale installation failed - binary not found"
        return 1
    fi
}

# ============================================================
# Verification Functions
# ============================================================

# Verify Tailscale installation and status
# Used by acfs doctor
verify_tailscale() {
    if ! command -v tailscale &>/dev/null; then
        log_warn "Tailscale not installed"
        return 1
    fi

    # Get version
    local version
    version=$(tailscale version 2>/dev/null | head -1 || echo "unknown")
    log_detail "  tailscale: $version"

    # Check daemon status (if systemd available)
    if _tailscale_has_systemd; then
        if systemctl is-active --quiet tailscaled 2>/dev/null; then
            log_detail "  tailscaled: running"
        else
            log_warn "  tailscaled: not running"
        fi
    fi

    # Check connection status
    local backend_state
    backend_state=$(_tailscale_backend_state)

    case "$backend_state" in
        "Running")
            log_detail "  Status: connected"
            local ip
            ip=$(tailscale ip -4 2>/dev/null || echo "")
            if [[ -n "$ip" ]]; then
                log_detail "  Tailscale IP: $ip"
            fi
            ;;
        "NeedsLogin")
            log_warn "  Status: needs authentication"
            log_detail "  Run: sudo tailscale up"
            ;;
        "Stopped")
            log_warn "  Status: stopped"
            log_detail "  Run: sudo systemctl start tailscaled"
            ;;
        *)
            log_detail "  Status: $backend_state"
            ;;
    esac

    return 0
}

# Check if Tailscale is authenticated
# Returns 0 if connected, 1 if needs auth
check_tailscale_auth() {
    if ! command -v tailscale &>/dev/null; then
        return 1
    fi

    local backend_state
    backend_state=$(_tailscale_backend_state)

    if [[ "$backend_state" == "Running" ]]; then
        return 0  # Authenticated and connected
    else
        return 1  # Needs auth or not running
    fi
}

# Get Tailscale connection info for display
get_tailscale_info() {
    if ! command -v tailscale &>/dev/null; then
        echo "not installed"
        return 1
    fi

    if check_tailscale_auth; then
        local ip hostname
        ip=$(tailscale ip -4 2>/dev/null || echo "unknown")
        hostname=$(tailscale status --json 2>/dev/null | jq -r '.Self.HostName // "unknown"' 2>/dev/null || echo "unknown")
        echo "connected: $hostname ($ip)"
        return 0
    else
        echo "not authenticated"
        return 1
    fi
}

# ============================================================
# Upgrade Function
# ============================================================

# Upgrade Tailscale to latest version
upgrade_tailscale() {
    local sudo_cmd
    sudo_cmd=$(_tailscale_get_sudo)

    if ! command -v tailscale &>/dev/null; then
        log_warn "Tailscale not installed, cannot upgrade"
        return 1
    fi

    log_detail "Upgrading Tailscale..."

    # Get current version
    local old_version
    old_version=$(tailscale version 2>/dev/null | head -1 || echo "unknown")

    # Update and upgrade via apt
    $sudo_cmd apt-get update -qq 2>/dev/null || true
    if $sudo_cmd apt-get install -y -qq tailscale 2>/dev/null; then
        local new_version
        new_version=$(tailscale version 2>/dev/null | head -1 || echo "unknown")
        if [[ "$old_version" != "$new_version" ]]; then
            log_success "Tailscale upgraded: $old_version -> $new_version"
        else
            log_detail "Tailscale already at latest version: $new_version"
        fi
        return 0
    else
        log_error "Failed to upgrade Tailscale"
        return 1
    fi
}

# ============================================================
# Module can be sourced or run directly
# ============================================================

# If run directly (not sourced), show usage
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        install)
            install_tailscale
            ;;
        verify)
            verify_tailscale
            ;;
        check-auth)
            if check_tailscale_auth; then
                echo "Tailscale is authenticated"
            else
                echo "Tailscale needs authentication"
                exit 1
            fi
            ;;
        info)
            get_tailscale_info
            ;;
        upgrade)
            upgrade_tailscale
            ;;
        *)
            echo "Usage: $0 {install|verify|check-auth|info|upgrade}"
            exit 1
            ;;
    esac
fi
