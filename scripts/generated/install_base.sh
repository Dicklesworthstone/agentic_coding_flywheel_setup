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

# Category: base
# Modules: 1

# Base packages + sane defaults
install_base_system() {
    log_step "Installing base.system"

    sudo apt-get update -y
    sudo apt-get install -y curl git ca-certificates unzip tar xz-utils jq build-essential

    # Verify
    curl --version || { log_error "Verify failed: base.system"; return 1; }
    git --version || { log_error "Verify failed: base.system"; return 1; }
    jq --version || { log_error "Verify failed: base.system"; return 1; }

    log_success "base.system installed"
}

# Install all base modules
install_base() {
    log_section "Installing base modules"
    install_base_system
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_base
fi
