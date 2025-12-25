#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Installer - Coding Agents Library
# Installs Claude Code, Codex CLI, and Gemini CLI
# ============================================================

AGENTS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure we have logging functions available
if [[ -z "${ACFS_BLUE:-}" ]]; then
    # shellcheck source=logging.sh
    source "$AGENTS_SCRIPT_DIR/logging.sh"
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
    local wrapped_cmd="set -o pipefail; $cmd"

    if [[ "$(whoami)" == "$target_user" ]]; then
        bash -c "$wrapped_cmd"
        return $?
    fi

    if command -v sudo &>/dev/null; then
        sudo -u "$target_user" -H bash -c "$wrapped_cmd"
        return $?
    fi

    if command -v runuser &>/dev/null; then
        runuser -u "$target_user" -- bash -c "$wrapped_cmd"
        return $?
    fi

    # Avoid login shells: profile files are not a stable API and can break non-interactive runs.
    su "$target_user" -c "bash -c $(printf %q "$wrapped_cmd")"
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
        log_warn "Install bun first by re-running the ACFS installer (language runtimes phase)"
        return 1
    fi
    return 0
}

# ============================================================
# Claude Code Installation
# ============================================================

# Install Claude Code CLI (Native)
# Official installer from https://claude.ai/install.sh
install_claude_code() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local claude_bin="$target_home/.local/bin/claude"

    # Check if already installed
    if [[ -x "$claude_bin" ]]; then
        log_detail "Claude Code already installed at $claude_bin"
        return 0
    fi

    log_detail "Installing Claude Code (native) for $target_user..."

    # Try to use security.sh for verification
    if [[ -f "$AGENTS_SCRIPT_DIR/security.sh" ]]; then
        # shellcheck source=security.sh
        source "$AGENTS_SCRIPT_DIR/security.sh"
        if load_checksums; then
            local url="${KNOWN_INSTALLERS[claude]}"
            local sha="${LOADED_CHECKSUMS[claude]}"
            if [[ -n "$url" && -n "$sha" ]]; then
                if _agent_run_as_user "source '$AGENTS_SCRIPT_DIR/security.sh'; verify_checksum '$url' '$sha' 'claude' | bash"; then
                    log_success "Claude Code installed (verified)"
                    return 0
                fi
            fi
        fi
    fi

    # Fail closed: never execute unverified remote installer scripts.
    log_error "Security verification unavailable or failed for Claude Code"
    log_error "Refusing to execute unverified installer script"
    return 1
}

# Upgrade Claude Code to latest version
upgrade_claude_code() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local claude_bin="$target_home/.local/bin/claude"

    if [[ -x "$claude_bin" ]]; then
        log_detail "Upgrading Claude Code (native)..."
        if _agent_run_as_user "\"$claude_bin\" update"; then
            log_success "Claude Code upgraded"
            return 0
        fi

        log_warn "Claude Code native update failed, attempting reinstall..."
        install_claude_code
        return $?
    fi

    # Legacy fallback: bun-installed Claude Code
    local bun_bin
    bun_bin=$(_agent_get_bun_bin)
    if _agent_check_bun; then
        log_detail "Upgrading Claude Code (bun)..."
        _agent_run_as_user "\"$bun_bin\" install -g $CLAUDE_PACKAGE" && log_success "Claude Code upgraded"
        return 0
    fi

    log_warn "Claude Code not installed"
    return 1
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
            log_detail "Note: Run 'codex login' to authenticate with your ChatGPT Pro account"
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
    local claude_native_bin="$target_home/.local/bin/claude"
    if [[ -x "$claude_native_bin" ]]; then
        local version
        version=$(_agent_run_as_user "\"$claude_native_bin\" --version" 2>/dev/null || echo "installed")
        log_detail "  claude: $version"
    elif [[ -x "$bun_bin_dir/$CLAUDE_BIN" ]]; then
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

    # Codex: Check for OAuth auth.json (uses ChatGPT accounts, not API keys)
    local codex_home="${CODEX_HOME:-$target_home/.codex}"
    if [[ -f "$codex_home/auth.json" ]]; then
        log_detail "  Codex: configured"
    else
        log_warn "  Codex: not configured (run 'codex login' to authenticate)"
    fi

    # Gemini: Check for credentials (OAuth web login, like Claude Code and Codex CLI)
    if [[ -f "$target_home/.config/gemini/credentials.json" ]] || \
       [[ -d "$target_home/.config/gemini" && -n "$(ls -A "$target_home/.config/gemini" 2>/dev/null)" ]] || \
       [[ -f "$target_home/.gemini/config" ]]; then
        log_detail "  Gemini: configured"
    else
        log_warn "  Gemini: not configured (run 'gemini' to login via browser)"
    fi
}

# Get versions of installed agents (for doctor output)
get_agent_versions() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local bun_bin_dir="$target_home/.bun/bin"
    local claude_native_bin="$target_home/.local/bin/claude"

    echo "Coding Agent Versions:"

    # Check Claude Code (native install takes priority, then bun)
    if [[ -x "$claude_native_bin" ]]; then
        echo "  claude: $(_agent_run_as_user "\"$claude_native_bin\" --version" 2>/dev/null || echo 'installed')"
    elif [[ -x "$bun_bin_dir/$CLAUDE_BIN" ]]; then
        echo "  claude: $(_agent_run_as_user "\"$bun_bin_dir/$CLAUDE_BIN\" --version" 2>/dev/null || echo 'installed')"
    fi
    if [[ -x "$bun_bin_dir/$CODEX_BIN" ]]; then
        echo "  codex: $(_agent_run_as_user "\"$bun_bin_dir/$CODEX_BIN\" --version" 2>/dev/null || echo 'installed')"
    fi
    if [[ -x "$bun_bin_dir/$GEMINI_BIN" ]]; then
        echo "  gemini: $(_agent_run_as_user "\"$bun_bin_dir/$GEMINI_BIN\" --version" 2>/dev/null || echo 'installed')"
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
    log_detail "  • Codex:  Run 'codex login' (uses ChatGPT Pro account, not API key)"
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
