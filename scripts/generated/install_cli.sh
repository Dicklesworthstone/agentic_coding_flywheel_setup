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

# Category: cli
# Modules: 1

# Modern CLI tools referenced by the zshrc intent
install_cli_modern() {
    log_step "Installing cli.modern"

    sudo apt-get install -y ripgrep tmux fzf direnv
    sudo apt-get install -y lsd || true
    sudo apt-get install -y eza || true
    sudo apt-get install -y bat || sudo apt-get install -y batcat || true
    sudo apt-get install -y fd-find || true
    sudo apt-get install -y btop || true
    sudo apt-get install -y dust || true
    sudo apt-get install -y neovim || true
    sudo apt-get install -y docker.io docker-compose-plugin || true
    sudo apt-get install -y lazygit || true
    sudo apt-get install -y lazydocker || true

    # Verify
    rg --version || { log_error "Verify failed: cli.modern"; return 1; }
    tmux -V || { log_error "Verify failed: cli.modern"; return 1; }
    fzf --version || { log_error "Verify failed: cli.modern"; return 1; }
    command -v lsd || command -v eza || log_warn "Optional: cli.modern verify skipped"

    log_success "cli.modern installed"
}

# Install all cli modules
install_cli() {
    log_section "Installing cli modules"
    install_cli_modern
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_cli
fi
