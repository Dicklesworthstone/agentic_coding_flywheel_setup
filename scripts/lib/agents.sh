#!/usr/bin/env bash
# ============================================================
# ACFS Installer - Coding Agents Library
# Installs Claude Code, Codex CLI, and Gemini CLI
# ============================================================

# Ensure we have logging functions available
if [[ -z "${ACFS_BLUE:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=logging.sh
    source "$SCRIPT_DIR/logging.sh"
fi

# ============================================================
# Configuration
# ============================================================

# NPM package names for each agent
CLAUDE_PACKAGE="@anthropic-ai/claude-code@latest"
CODEX_PACKAGE="@openai/codex@latest"
GEMINI_PACKAGE="@google/gemini-cli@latest"

# Binary names after installation
CLAUDE_BIN="claude"
CODEX_BIN="codex"
GEMINI_BIN="gemini"

# ============================================================
# Helper Functions
# ============================================================

# Check if a command exists
_agent_command_exists() {
    command -v "$1" &>/dev/null
}

# Get the sudo command if needed
_agent_get_sudo() {
    if [[ $EUID -eq 0 ]]; then
        echo ""
    else
        echo "sudo"
    fi
}

# Run a command as target user
_agent_run_as_user() {
    local target_user="${TARGET_USER:-ubuntu}"
    local cmd="$1"

    if [[ "$(whoami)" == "$target_user" ]]; then
        bash -c "$cmd"
    else
        $(_agent_get_sudo) -u "$target_user" -H bash -c "$cmd"
    fi
}

# Get bun binary path for target user
_agent_get_bun_bin() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
    echo "$target_home/.bun/bin/bun"
}

# Check if bun is available
_agent_check_bun() {
    local bun_bin
    bun_bin=$(_agent_get_bun_bin)

    if [[ ! -x "$bun_bin" ]]; then
        log_warn "Bun not found at $bun_bin"
        log_warn "Install bun first: curl -fsSL https://bun.sh/install | bash"
        return 1
    fi
    return 0
}

# ============================================================
# Claude Code Installation
# ============================================================

# Install Claude Code CLI via bun
# The official package is @anthropic-ai/claude-code
install_claude_code() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local bun_bin
    bun_bin=$(_agent_get_bun_bin)
    local claude_bin="$target_home/.bun/bin/$CLAUDE_BIN"

    # Check if already installed
    if [[ -x "$claude_bin" ]]; then
        log_detail "Claude Code already installed at $claude_bin"
        return 0
    fi

    # Verify bun is available
    if ! _agent_check_bun; then
        return 1
    fi

    log_detail "Installing Claude Code for $target_user..."

    # Install via bun global
    if _agent_run_as_user "\"$bun_bin\" install -g $CLAUDE_PACKAGE"; then
        if [[ -x "$claude_bin" ]]; then
            log_success "Claude Code installed"
            log_detail "Note: Run 'claude' to complete login/setup"
            return 0
        fi
    fi

    log_warn "Claude Code installation may have failed"
    return 1
}

# Upgrade Claude Code to latest version
upgrade_claude_code() {
    local target_user="${TARGET_USER:-ubuntu}"
    local bun_bin
    bun_bin=$(_agent_get_bun_bin)

    if ! _agent_check_bun; then
        return 1
    fi

    log_detail "Upgrading Claude Code..."
    _agent_run_as_user "\"$bun_bin\" install -g $CLAUDE_PACKAGE" && log_success "Claude Code upgraded"
}

# ============================================================
# Codex CLI Installation (OpenAI)
# ============================================================

# Install Codex CLI via bun
# The official package is @openai/codex
install_codex_cli() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local bun_bin
    bun_bin=$(_agent_get_bun_bin)
    local codex_bin="$target_home/.bun/bin/$CODEX_BIN"

    # Check if already installed
    if [[ -x "$codex_bin" ]]; then
        log_detail "Codex CLI already installed at $codex_bin"
        return 0
    fi

    # Verify bun is available
    if ! _agent_check_bun; then
        return 1
    fi

    log_detail "Installing Codex CLI for $target_user..."

    # Install via bun global
    if _agent_run_as_user "\"$bun_bin\" install -g $CODEX_PACKAGE"; then
        if [[ -x "$codex_bin" ]]; then
            log_success "Codex CLI installed"
            log_detail "Note: Set OPENAI_API_KEY or run 'codex' to complete login"
            return 0
        fi
    fi

    log_warn "Codex CLI installation may have failed"
    return 1
}

# Upgrade Codex CLI to latest version
upgrade_codex_cli() {
    local target_user="${TARGET_USER:-ubuntu}"
    local bun_bin
    bun_bin=$(_agent_get_bun_bin)

    if ! _agent_check_bun; then
        return 1
    fi

    log_detail "Upgrading Codex CLI..."
    _agent_run_as_user "\"$bun_bin\" install -g $CODEX_PACKAGE" && log_success "Codex CLI upgraded"
}

# ============================================================
# Gemini CLI Installation (Google)
# ============================================================

# Install Gemini CLI via bun
# The official package is @google/gemini-cli
install_gemini_cli() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local bun_bin
    bun_bin=$(_agent_get_bun_bin)
    local gemini_bin="$target_home/.bun/bin/$GEMINI_BIN"

    # Check if already installed
    if [[ -x "$gemini_bin" ]]; then
        log_detail "Gemini CLI already installed at $gemini_bin"
        return 0
    fi

    # Verify bun is available
    if ! _agent_check_bun; then
        return 1
    fi

    log_detail "Installing Gemini CLI for $target_user..."

    # Install via bun global
    if _agent_run_as_user "\"$bun_bin\" install -g $GEMINI_PACKAGE"; then
        if [[ -x "$gemini_bin" ]]; then
            log_success "Gemini CLI installed"
            log_detail "Note: Run 'gemini' to complete Google login"
            return 0
        fi
    fi

    log_warn "Gemini CLI installation may have failed"
    return 1
}

# Upgrade Gemini CLI to latest version
upgrade_gemini_cli() {
    local target_user="${TARGET_USER:-ubuntu}"
    local bun_bin
    bun_bin=$(_agent_get_bun_bin)

    if ! _agent_check_bun; then
        return 1
    fi

    log_detail "Upgrading Gemini CLI..."
    _agent_run_as_user "\"$bun_bin\" install -g $GEMINI_PACKAGE" && log_success "Gemini CLI upgraded"
}

# ============================================================
# Verification Functions
# ============================================================

# Verify all coding agents are installed
verify_agents() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local bun_bin_dir="$target_home/.bun/bin"
    local all_pass=true

    log_detail "Verifying coding agents..."

    # Check Claude Code
    if [[ -x "$bun_bin_dir/$CLAUDE_BIN" ]]; then
        local version
        version=$(_agent_run_as_user "\"$bun_bin_dir/$CLAUDE_BIN\" --version" 2>/dev/null || echo "installed")
        log_detail "  claude: $version"
    else
        log_warn "  Missing: claude (Claude Code)"
        all_pass=false
    fi

    # Check Codex CLI
    if [[ -x "$bun_bin_dir/$CODEX_BIN" ]]; then
        local version
        version=$(_agent_run_as_user "\"$bun_bin_dir/$CODEX_BIN\" --version" 2>/dev/null || echo "installed")
        log_detail "  codex: $version"
    else
        log_warn "  Missing: codex (Codex CLI)"
        all_pass=false
    fi

    # Check Gemini CLI
    if [[ -x "$bun_bin_dir/$GEMINI_BIN" ]]; then
        local version
        version=$(_agent_run_as_user "\"$bun_bin_dir/$GEMINI_BIN\" --version" 2>/dev/null || echo "installed")
        log_detail "  gemini: $version"
    else
        log_warn "  Missing: gemini (Gemini CLI)"
        all_pass=false
    fi

    if [[ "$all_pass" == "true" ]]; then
        log_success "All coding agents verified"
        log_detail "Note: Each agent requires login before use"
        return 0
    else
        log_warn "Some coding agents are missing"
        return 1
    fi
}

# Check if agents are authenticated/logged in
check_agent_auth() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"

    log_detail "Checking agent authentication status..."

    # Claude: Check for config file
    if [[ -f "$target_home/.claude/config.json" ]] || [[ -f "$target_home/.config/claude/config.json" ]]; then
        log_detail "  Claude: configured"
    else
        log_warn "  Claude: not configured (run 'claude' to login)"
    fi

    # Codex: Check for API key or config
    if [[ -n "${OPENAI_API_KEY:-}" ]] || [[ -f "$target_home/.codex/config.json" ]]; then
        log_detail "  Codex: configured"
    else
        log_warn "  Codex: not configured (set OPENAI_API_KEY or run 'codex')"
    fi

    # Gemini: Check for credentials
    if [[ -f "$target_home/.config/gemini/credentials.json" ]] || [[ -n "${GOOGLE_API_KEY:-}" ]]; then
        log_detail "  Gemini: configured"
    else
        log_warn "  Gemini: not configured (run 'gemini' to login)"
    fi
}

# Get versions of installed agents (for doctor output)
get_agent_versions() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local bun_bin_dir="$target_home/.bun/bin"

    echo "Coding Agent Versions:"

    if [[ -x "$bun_bin_dir/$CLAUDE_BIN" ]]; then
        echo "  claude: $("$bun_bin_dir/$CLAUDE_BIN" --version 2>/dev/null || echo 'installed')"
    fi
    if [[ -x "$bun_bin_dir/$CODEX_BIN" ]]; then
        echo "  codex: $("$bun_bin_dir/$CODEX_BIN" --version 2>/dev/null || echo 'installed')"
    fi
    if [[ -x "$bun_bin_dir/$GEMINI_BIN" ]]; then
        echo "  gemini: $("$bun_bin_dir/$GEMINI_BIN" --version 2>/dev/null || echo 'installed')"
    fi
}

# ============================================================
# Upgrade All Agents
# ============================================================

# Upgrade all agents to latest versions
upgrade_all_agents() {
    log_detail "Upgrading all coding agents..."

    upgrade_claude_code
    upgrade_codex_cli
    upgrade_gemini_cli

    log_success "All coding agents upgraded"
}

# ============================================================
# Main Installation Function
# ============================================================

# Install all coding agents (called by install.sh)
install_all_agents() {
    log_step "6/8" "Installing coding agents..."

    # Verify bun is available first
    if ! _agent_check_bun; then
        log_warn "Skipping agent installation - bun not available"
        log_warn "Install bun first, then re-run this script"
        return 1
    fi

    # Install each agent
    install_claude_code
    install_codex_cli
    install_gemini_cli

    # Verify installation
    verify_agents

    # Note about authentication
    echo ""
    log_detail "Next steps: Login to each agent"
    log_detail "  • Claude: Run 'claude' and follow prompts"
    log_detail "  • Codex:  Set OPENAI_API_KEY or run 'codex'"
    log_detail "  • Gemini: Run 'gemini' and complete Google login"
    echo ""

    log_success "Coding agents installation complete"
}

# ============================================================
# Module can be sourced or run directly
# ============================================================

# If run directly (not sourced), execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_all_agents "$@"
fi
