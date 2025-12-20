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

# Category: lang
# Modules: 4

# Bun runtime for JS tooling and global CLIs
install_lang_bun() {
    log_step "Installing lang.bun"

    curl -fsSL https://bun.sh/install | bash

    # Verify
    ~/.bun/bin/bun --version || { log_error "Verify failed: lang.bun"; return 1; }

    log_success "lang.bun installed"
}

# uv Python tooling (fast venvs)
install_lang_uv() {
    log_step "Installing lang.uv"

    curl -LsSf https://astral.sh/uv/install.sh | sh

    # Verify
    ~/.local/bin/uv --version || { log_error "Verify failed: lang.uv"; return 1; }

    log_success "lang.uv installed"
}

# Rust + cargo
install_lang_rust() {
    log_step "Installing lang.rust"

    curl https://sh.rustup.rs -sSf | sh -s -- -y

    # Verify
    ~/.cargo/bin/cargo --version || { log_error "Verify failed: lang.rust"; return 1; }

    log_success "lang.rust installed"
}

# Go toolchain
install_lang_go() {
    log_step "Installing lang.go"

    sudo apt-get install -y golang-go

    # Verify
    go version || { log_error "Verify failed: lang.go"; return 1; }

    log_success "lang.go installed"
}

# Install all lang modules
install_lang() {
    log_section "Installing lang modules"
    install_lang_bun
    install_lang_uv
    install_lang_rust
    install_lang_go
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_lang
fi
