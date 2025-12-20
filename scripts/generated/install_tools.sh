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

# Category: tools
# Modules: 4

# Atuin shell history (Ctrl-R superpowers)
install_tools_atuin() {
    log_step "Installing tools.atuin"

    curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh

    # Verify
    ~/.atuin/bin/atuin --version || { log_error "Verify failed: tools.atuin"; return 1; }

    log_success "tools.atuin installed"
}

# Zoxide (better cd)
install_tools_zoxide() {
    log_step "Installing tools.zoxide"

    curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh

    # Verify
    command -v zoxide || { log_error "Verify failed: tools.zoxide"; return 1; }

    log_success "tools.zoxide installed"
}

# ast-grep (used by UBS for syntax-aware scanning)
install_tools_ast_grep() {
    log_step "Installing tools.ast_grep"

    ~/.cargo/bin/cargo install ast-grep

    # Verify
    sg --version || { log_error "Verify failed: tools.ast_grep"; return 1; }

    log_success "tools.ast_grep installed"
}

# HashiCorp Vault CLI
install_tools_vault() {
    log_step "Installing tools.vault"

    # Install Vault via official HashiCorp instructions (apt repo or binary)
    log_info "TODO: Install Vault via official HashiCorp instructions (apt repo or binary)"

    # Verify
    vault --version || { log_error "Verify failed: tools.vault"; return 1; }

    log_success "tools.vault installed"
}

# Install all tools modules
install_tools() {
    log_section "Installing tools modules"
    install_tools_atuin
    install_tools_zoxide
    install_tools_ast_grep
    install_tools_vault
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_tools
fi
