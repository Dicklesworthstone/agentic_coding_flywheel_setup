#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================

set -euo pipefail

# Ensure logging functions available
ACFS_GENERATED_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# When running a generated installer directly (not sourced by install.sh),
# set sane defaults and derive ACFS paths from the script location so
# contract validation passes and local assets are discoverable.
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    # Match install.sh defaults
    if [[ -z "${TARGET_USER:-}" ]]; then
        if [[ $EUID -eq 0 ]] && [[ -z "${SUDO_USER:-}" ]]; then
            _ACFS_DETECTED_USER="ubuntu"
        else
            _ACFS_DETECTED_USER="${SUDO_USER:-$(whoami)}"
        fi
        TARGET_USER="$_ACFS_DETECTED_USER"
    fi
    unset _ACFS_DETECTED_USER
    MODE="${MODE:-vibe}"

    if [[ -z "${TARGET_HOME:-}" ]]; then
        if [[ "${TARGET_USER}" == "root" ]]; then
            TARGET_HOME="/root"
        elif [[ "$(whoami 2>/dev/null || true)" == "${TARGET_USER}" ]]; then
            TARGET_HOME="${HOME}"
        else
            TARGET_HOME="/home/${TARGET_USER}"
        fi
    fi

    # Derive "bootstrap" paths from the repo layout (scripts/generated/.. -> repo root).
    if [[ -z "${ACFS_BOOTSTRAP_DIR:-}" ]]; then
        ACFS_BOOTSTRAP_DIR="$(cd "$ACFS_GENERATED_SCRIPT_DIR/../.." && pwd)"
    fi

    ACFS_LIB_DIR="${ACFS_LIB_DIR:-$ACFS_BOOTSTRAP_DIR/scripts/lib}"
    ACFS_GENERATED_DIR="${ACFS_GENERATED_DIR:-$ACFS_BOOTSTRAP_DIR/scripts/generated}"
    ACFS_ASSETS_DIR="${ACFS_ASSETS_DIR:-$ACFS_BOOTSTRAP_DIR/acfs}"
    ACFS_CHECKSUMS_YAML="${ACFS_CHECKSUMS_YAML:-$ACFS_BOOTSTRAP_DIR/checksums.yaml}"
    ACFS_MANIFEST_YAML="${ACFS_MANIFEST_YAML:-$ACFS_BOOTSTRAP_DIR/acfs.manifest.yaml}"

    export TARGET_USER TARGET_HOME MODE
    export ACFS_BOOTSTRAP_DIR ACFS_LIB_DIR ACFS_GENERATED_DIR ACFS_ASSETS_DIR ACFS_CHECKSUMS_YAML ACFS_MANIFEST_YAML
fi
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh"
else
    # Fallback logging functions if logging.sh not found
    # Progress/status output should go to stderr so stdout stays clean for piping.
    log_step() { echo "[*] $*" >&2; }
    log_section() { echo "" >&2; echo "=== $* ===" >&2; }
    log_success() { echo "[OK] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_info() { echo "    $*" >&2; }
fi

# Source install helpers (run_as_*_shell, selection helpers)
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh"
fi

# Source contract validation
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/contract.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/contract.sh"
fi

# Optional security verification for upstream installer scripts.
# Scripts that need it should call: acfs_security_init
ACFS_SECURITY_READY=false
acfs_security_init() {
    if [[ "${ACFS_SECURITY_READY}" = "true" ]]; then
        return 0
    fi

    local security_lib="$ACFS_GENERATED_SCRIPT_DIR/../lib/security.sh"
    if [[ ! -f "$security_lib" ]]; then
        log_error "Security library not found: $security_lib"
        return 1
    fi

    # Use ACFS_CHECKSUMS_YAML if set by install.sh bootstrap (overrides security.sh default)
    if [[ -n "${ACFS_CHECKSUMS_YAML:-}" ]]; then
        export CHECKSUMS_FILE="${ACFS_CHECKSUMS_YAML}"
    fi

    # shellcheck source=../lib/security.sh
    # shellcheck disable=SC1091  # runtime relative source
    source "$security_lib"
    load_checksums || { log_error "Failed to load checksums.yaml"; return 1; }
    ACFS_SECURITY_READY=true
    return 0
}

# Category: network
# Modules: 2

# Zero-config mesh VPN for secure remote VPS access
install_network_tailscale() {
    local module_id="network.tailscale"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing network.tailscale"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: case \"\$DISTRO_CODENAME\" in (root)"
    else
        if ! run_as_root_shell <<'INSTALL_NETWORK_TAILSCALE'
# Add Tailscale apt repository
DISTRO_CODENAME=$(lsb_release -cs 2>/dev/null || echo "jammy")
# Map newer Ubuntu codenames to supported ones
case "$DISTRO_CODENAME" in
  oracular|plucky|questing) DISTRO_CODENAME="noble" ;;
esac
CURL_ARGS=(-fsSL)
if curl --help all 2>/dev/null | grep -q -- '--proto'; then
  CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
fi
curl "${CURL_ARGS[@]}" "https://pkgs.tailscale.com/stable/ubuntu/${DISTRO_CODENAME}.noarmor.gpg" \
  | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu ${DISTRO_CODENAME} main" \
  | tee /etc/apt/sources.list.d/tailscale.list
apt-get update
apt-get install -y tailscale
systemctl enable tailscaled
INSTALL_NETWORK_TAILSCALE
        then
            log_error "network.tailscale: install command failed: case \"\$DISTRO_CODENAME\" in"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: tailscale version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_NETWORK_TAILSCALE'
tailscale version
INSTALL_NETWORK_TAILSCALE
        then
            log_error "network.tailscale: verify failed: tailscale version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: systemctl is-enabled tailscaled (root)"
    else
        if ! run_as_root_shell <<'INSTALL_NETWORK_TAILSCALE'
systemctl is-enabled tailscaled
INSTALL_NETWORK_TAILSCALE
        then
            log_error "network.tailscale: verify failed: systemctl is-enabled tailscaled"
            return 1
        fi
    fi

    # Post-install message
    log_info "Tailscale installed! To connect your VPS to your Tailscale network:"
    log_info "  sudo tailscale up"
    log_info "Then log in with your Google account at the URL shown."
    log_info "Once connected, you can access your VPS via its Tailscale IP or hostname."

    log_success "network.tailscale installed"
}

# Configure SSH server keepalive to prevent VPN/NAT disconnects
install_network_ssh_keepalive() {
    local module_id="network.ssh_keepalive"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing network.ssh_keepalive"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ ! -f /etc/ssh/sshd_config.acfs.bak ]]; then (root)"
    else
        if ! run_as_root_shell <<'INSTALL_NETWORK_SSH_KEEPALIVE'
# Backup original sshd_config if not already backed up
if [[ ! -f /etc/ssh/sshd_config.acfs.bak ]]; then
  cp /etc/ssh/sshd_config /etc/ssh/sshd_config.acfs.bak
fi

# Configure SSH keepalive settings
# ClientAliveInterval: send keepalive every 60 seconds
# ClientAliveCountMax: disconnect after 3 missed (3 minutes of real disconnect)

# Remove any existing ClientAlive settings
sed -i '/^#*ClientAliveInterval/d' /etc/ssh/sshd_config
sed -i '/^#*ClientAliveCountMax/d' /etc/ssh/sshd_config

# Add new settings at the end
echo "" >> /etc/ssh/sshd_config
echo "# ACFS: SSH keepalive for VPN/NAT resilience" >> /etc/ssh/sshd_config
echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config
echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config

# Reload sshd (doesn't kill existing connections)
systemctl reload sshd || systemctl reload ssh || true
INSTALL_NETWORK_SSH_KEEPALIVE
        then
            log_warn "network.ssh_keepalive: install command failed: if [[ ! -f /etc/ssh/sshd_config.acfs.bak ]]; then"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "network.ssh_keepalive" "install command failed: if [[ ! -f /etc/ssh/sshd_config.acfs.bak ]]; then"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "network.ssh_keepalive"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: grep -E '^ClientAliveInterval[[:space:]]+60' /etc/ssh/sshd_config (root)"
    else
        if ! run_as_root_shell <<'INSTALL_NETWORK_SSH_KEEPALIVE'
grep -E '^ClientAliveInterval[[:space:]]+60' /etc/ssh/sshd_config
INSTALL_NETWORK_SSH_KEEPALIVE
        then
            log_warn "network.ssh_keepalive: verify failed: grep -E '^ClientAliveInterval[[:space:]]+60' /etc/ssh/sshd_config"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "network.ssh_keepalive" "verify failed: grep -E '^ClientAliveInterval[[:space:]]+60' /etc/ssh/sshd_config"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "network.ssh_keepalive"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: grep -E '^ClientAliveCountMax[[:space:]]+3' /etc/ssh/sshd_config (root)"
    else
        if ! run_as_root_shell <<'INSTALL_NETWORK_SSH_KEEPALIVE'
grep -E '^ClientAliveCountMax[[:space:]]+3' /etc/ssh/sshd_config
INSTALL_NETWORK_SSH_KEEPALIVE
        then
            log_warn "network.ssh_keepalive: verify failed: grep -E '^ClientAliveCountMax[[:space:]]+3' /etc/ssh/sshd_config"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "network.ssh_keepalive" "verify failed: grep -E '^ClientAliveCountMax[[:space:]]+3' /etc/ssh/sshd_config"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "network.ssh_keepalive"
            fi
            return 0
        fi
    fi

    # Post-install message
    log_info "SSH keepalive configured! Your connections will now survive VPN/NAT timeouts."
    log_info "Settings: ClientAliveInterval 60, ClientAliveCountMax 3"
    log_info "Original config backed up to /etc/ssh/sshd_config.acfs.bak"

    log_success "network.ssh_keepalive installed"
}

# Install all network modules
install_network() {
    log_section "Installing network modules"
    install_network_tailscale
    install_network_ssh_keepalive
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    install_network
fi
