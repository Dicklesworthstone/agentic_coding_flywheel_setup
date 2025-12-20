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

# Category: users
# Modules: 1

# Ensure ubuntu user + passwordless sudo + ssh keys
install_users_ubuntu() {
    log_step "Installing users.ubuntu"

    # Ensure user ubuntu exists with home /home/ubuntu
    log_info "TODO: Ensure user ubuntu exists with home /home/ubuntu"
    # Write /etc/sudoers.d/90-ubuntu-acfs: ubuntu ALL=(ALL) NOPASSWD:ALL
    log_info "TODO: Write /etc/sudoers.d/90-ubuntu-acfs: ubuntu ALL=(ALL) NOPASSWD:ALL"
    # Copy authorized_keys from invoking user to /home/ubuntu/.ssh/
    log_info "TODO: Copy authorized_keys from invoking user to /home/ubuntu/.ssh/"

    # Verify
    id ubuntu || { log_error "Verify failed: users.ubuntu"; return 1; }
    sudo -n true || { log_error "Verify failed: users.ubuntu"; return 1; }

    log_success "users.ubuntu installed"
}

# Install all users modules
install_users() {
    log_section "Installing users modules"
    install_users_ubuntu
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_users
fi
