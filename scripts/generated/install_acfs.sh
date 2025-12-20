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
fi

# Category: acfs
# Modules: 2

# Onboarding TUI tutorial
install_acfs_onboard() {
    log_step "Installing acfs.onboard"

    # Install onboard script to ~/.local/bin/onboard
    log_info "TODO: Install onboard script to ~/.local/bin/onboard"

    # Verify
    onboard --help || command -v onboard || { log_error "Verify failed: acfs.onboard"; return 1; }

    log_success "acfs.onboard installed"
}

# ACFS doctor command for health checks
install_acfs_doctor() {
    log_step "Installing acfs.doctor"

    # Install acfs script to ~/.local/bin/acfs
    log_info "TODO: Install acfs script to ~/.local/bin/acfs"

    # Verify
    acfs doctor --help || command -v acfs || { log_error "Verify failed: acfs.doctor"; return 1; }

    log_success "acfs.doctor installed"
}

# Install all acfs modules
install_acfs() {
    log_section "Installing acfs modules"
    install_acfs_onboard
    install_acfs_doctor
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_acfs
fi
