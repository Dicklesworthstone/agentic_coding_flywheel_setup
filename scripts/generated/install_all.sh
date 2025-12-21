#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================

set -euo pipefail

# Ensure logging functions available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../lib/logging.sh" ]]; then
    source "$SCRIPT_DIR/../lib/logging.sh"
else
    # Fallback logging functions if logging.sh not found
    log_step() { echo "[*] $*"; }
    log_section() { echo ""; echo "=== $* ==="; }
    log_success() { echo "[OK] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_info() { echo "    $*"; }
fi

# Source install helpers (run_as_*_shell, selection helpers)
if [[ -f "$SCRIPT_DIR/../lib/install_helpers.sh" ]]; then
    source "$SCRIPT_DIR/../lib/install_helpers.sh"
fi

# Optional security verification for upstream installer scripts.
# Scripts that need it should call: acfs_security_init
ACFS_SECURITY_READY=false
acfs_security_init() {
    if [[ "${ACFS_SECURITY_READY}" == "true" ]]; then
        return 0
    fi

    local security_lib="$SCRIPT_DIR/../lib/security.sh"
    if [[ ! -f "$security_lib" ]]; then
        log_error "Security library not found: $security_lib"
        return 1
    fi

    # shellcheck source=../lib/security.sh
    # shellcheck disable=SC1091  # runtime relative source
    source "$security_lib"
    load_checksums || { log_error "Failed to load checksums.yaml"; return 1; }
    ACFS_SECURITY_READY=true
    return 0
}

# Master installer - sources all category scripts

source "$SCRIPT_DIR/install_base.sh"
source "$SCRIPT_DIR/install_users.sh"
source "$SCRIPT_DIR/install_shell.sh"
source "$SCRIPT_DIR/install_cli.sh"
source "$SCRIPT_DIR/install_lang.sh"
source "$SCRIPT_DIR/install_tools.sh"
source "$SCRIPT_DIR/install_agents.sh"
source "$SCRIPT_DIR/install_db.sh"
source "$SCRIPT_DIR/install_cloud.sh"
source "$SCRIPT_DIR/install_stack.sh"
source "$SCRIPT_DIR/install_acfs.sh"

# Install all modules in order
install_all() {
    log_section "ACFS Full Installation"

    install_base
    install_users
    install_shell
    install_cli
    install_lang
    install_tools
    install_agents
    install_db
    install_cloud
    install_stack
    install_acfs

    log_success "All modules installed!"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_all
fi
