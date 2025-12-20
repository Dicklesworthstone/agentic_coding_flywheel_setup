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

# Category: agents
# Modules: 3

# Claude Code
install_agents_claude() {
    log_step "Installing agents.claude"

    # Install claude code via official method
    log_info "TODO: Install claude code via official method"

    # Verify
    claude --version || claude --help || { log_error "Verify failed: agents.claude"; return 1; }

    log_success "agents.claude installed"
}

# OpenAI Codex CLI
install_agents_codex() {
    log_step "Installing agents.codex"

    ~/.bun/bin/bun install -g @openai/codex@latest

    # Verify
    codex --version || codex --help || { log_error "Verify failed: agents.codex"; return 1; }

    log_success "agents.codex installed"
}

# Google Gemini CLI
install_agents_gemini() {
    log_step "Installing agents.gemini"

    ~/.bun/bin/bun install -g @google/gemini-cli@latest

    # Verify
    gemini --version || gemini --help || { log_error "Verify failed: agents.gemini"; return 1; }

    log_success "agents.gemini installed"
}

# Install all agents modules
install_agents() {
    log_section "Installing agents modules"
    install_agents_claude
    install_agents_codex
    install_agents_gemini
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_agents
fi
