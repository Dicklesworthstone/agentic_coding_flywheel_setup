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

# Category: stack
# Modules: 8

# Named tmux manager (agent cockpit)
install_stack_ntm() {
    log_step "Installing stack.ntm"

    curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh | bash

    # Verify
    ntm --help || { log_error "Verify failed: stack.ntm"; return 1; }

    log_success "stack.ntm installed"
}

# Like gmail for coding agents; MCP HTTP server + token; installs beads tools
install_stack_mcp_agent_mail() {
    log_step "Installing stack.mcp_agent_mail"

    curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail/main/scripts/install.sh?$(date +%s)" | bash -s -- --yes

    # Verify
    command -v am || { log_error "Verify failed: stack.mcp_agent_mail"; return 1; }
    curl -fsS http://127.0.0.1:8765/health || log_warn "Optional: stack.mcp_agent_mail verify skipped"

    log_success "stack.mcp_agent_mail installed"
}

# UBS bug scanning (easy-mode)
install_stack_ultimate_bug_scanner() {
    log_step "Installing stack.ultimate_bug_scanner"

    curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/master/install.sh?$(date +%s)" | bash -s -- --easy-mode

    # Verify
    ubs --help || { log_error "Verify failed: stack.ultimate_bug_scanner"; return 1; }
    ubs doctor || log_warn "Optional: stack.ultimate_bug_scanner verify skipped"

    log_success "stack.ultimate_bug_scanner installed"
}

# bv TUI for Beads tasks
install_stack_beads_viewer() {
    log_step "Installing stack.beads_viewer"

    curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh?$(date +%s)" | bash

    # Verify
    bv --help || bv --version || { log_error "Verify failed: stack.beads_viewer"; return 1; }

    log_success "stack.beads_viewer installed"
}

# Unified search across agent session history
install_stack_cass() {
    log_step "Installing stack.cass"

    curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh | bash -s -- --easy-mode --verify

    # Verify
    cass --help || cass --version || { log_error "Verify failed: stack.cass"; return 1; }

    log_success "stack.cass installed"
}

# Procedural memory for agents (cass-memory)
install_stack_cm() {
    log_step "Installing stack.cm"

    curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/cass_memory_system/main/install.sh | bash -s -- --easy-mode --verify

    # Verify
    cm --version || { log_error "Verify failed: stack.cm"; return 1; }
    cm doctor --json || log_warn "Optional: stack.cm verify skipped"

    log_success "stack.cm installed"
}

# Instant auth switching for agent CLIs
install_stack_caam() {
    log_step "Installing stack.caam"

    curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_account_manager/main/install.sh?$(date +%s)" | bash

    # Verify
    caam status || caam --help || { log_error "Verify failed: stack.caam"; return 1; }

    log_success "stack.caam installed"
}

# Two-person rule for dangerous commands (optional guardrails)
install_stack_slb() {
    log_step "Installing stack.slb"

    curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/simultaneous_launch_button/main/scripts/install.sh | bash

    # Verify
    slb --help || { log_error "Verify failed: stack.slb"; return 1; }

    log_success "stack.slb installed"
}

# Install all stack modules
install_stack() {
    log_section "Installing stack modules"
    install_stack_ntm
    install_stack_mcp_agent_mail
    install_stack_ultimate_bug_scanner
    install_stack_beads_viewer
    install_stack_cass
    install_stack_cm
    install_stack_caam
    install_stack_slb
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_stack
fi
