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
CLAUDE_PACKAGE="@anthropic-ai/claude-code@stable"
CODEX_PACKAGE="${CODEX_PACKAGE:-@openai/codex@latest}"
CODEX_FALLBACK_VERSION="${CODEX_FALLBACK_VERSION:-0.87.0}"
CODEX_FALLBACK_PACKAGE=""
if [[ -n "$CODEX_FALLBACK_VERSION" ]]; then
    CODEX_FALLBACK_PACKAGE="@openai/codex@${CODEX_FALLBACK_VERSION}"
fi
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
        log_warn "Install bun first: curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only-phase 5"
        return 1
    fi
    return 0
}

# Create a wrapper script that uses bun as the runtime instead of node.
# This avoids the "node not found" error when nvm hasn't added node to PATH yet.
# The wrapper is placed in ~/.local/bin which is early in PATH.
_agent_create_bun_wrapper() {
    local target_home="$1"
    local tool_name="$2"
    local wrapper_path="$target_home/.local/bin/$tool_name"
    local bun_tool_path="$target_home/.bun/bin/$tool_name"

    # Skip if wrapper already exists
    [[ -x "$wrapper_path" ]] && return 0

    # Skip if bun tool doesn't exist
    [[ -x "$bun_tool_path" ]] || return 0

    log_detail "Creating $tool_name bun wrapper at $wrapper_path"
    _agent_run_as_user "mkdir -p '$target_home/.local/bin'" || return 1
    # Use printf to avoid heredoc quoting issues with variable expansion
    _agent_run_as_user "printf '%s\\n' '#!/bin/bash' 'exec ~/.bun/bin/bun ~/.bun/bin/$tool_name \"\$@\"' > '$wrapper_path'" || return 1
    _agent_run_as_user "chmod +x '$wrapper_path'" || return 1
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
                if _agent_run_as_user "source '$AGENTS_SCRIPT_DIR/security.sh'; verify_checksum '$url' '$sha' 'claude' | bash -s -- stable"; then
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
        _agent_run_as_user "\"$bun_bin\" install -g --trust $CLAUDE_PACKAGE" && log_success "Claude Code upgraded"
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
    local codex_wrapper="$target_home/.local/bin/codex"

    # Check if already installed (wrapper takes precedence)
    if [[ -x "$codex_wrapper" ]]; then
        log_detail "Codex CLI already installed at $codex_wrapper"
        return 0
    fi
    if [[ -x "$codex_bin" ]]; then
        log_detail "Codex CLI already installed at $codex_bin"
        # Create wrapper if missing (fixes node PATH issues)
        _agent_create_bun_wrapper "$target_home" "codex"
        return 0
    fi

    # Verify bun is available
    if ! _agent_check_bun; then
        return 1
    fi

    log_detail "Installing Codex CLI for $target_user..."

    # Install via bun global (fallback to a pinned version if latest is broken)
    _agent_run_as_user "\"$bun_bin\" install -g --trust $CODEX_PACKAGE" || true
    if [[ ! -x "$codex_bin" ]] && [[ -n "$CODEX_FALLBACK_PACKAGE" ]]; then
        log_warn "Codex CLI latest install failed; retrying pinned fallback $CODEX_FALLBACK_VERSION"
        _agent_run_as_user "\"$bun_bin\" install -g --trust $CODEX_FALLBACK_PACKAGE" || true
    fi

    if [[ -x "$codex_bin" ]]; then
        # Create wrapper script that uses bun as runtime (avoids node PATH issues)
        _agent_create_bun_wrapper "$target_home" "codex"
        log_success "Codex CLI installed"
        log_detail "Note: Run 'codex login' to authenticate with your ChatGPT Pro account"
        return 0
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
    if _agent_run_as_user "\"$bun_bin\" install -g --trust $CODEX_PACKAGE"; then
        log_success "Codex CLI upgraded"
        return 0
    fi

    if [[ -n "$CODEX_FALLBACK_PACKAGE" ]]; then
        log_warn "Codex CLI latest upgrade failed; retrying pinned fallback $CODEX_FALLBACK_VERSION"
        if _agent_run_as_user "\"$bun_bin\" install -g --trust $CODEX_FALLBACK_PACKAGE"; then
            log_success "Codex CLI upgraded (fallback)"
            return 0
        fi
    fi

    log_warn "Codex CLI upgrade failed"
    return 1
}

# ============================================================
# Gemini CLI Installation (Google)
# ============================================================

# Configure Gemini CLI settings for tmux/agent compatibility and OAuth authentication
# Sets enableInteractiveShell: false to avoid node-pty issues in tmux panes
# Sets selectedType: "oauth-personal" for browser-based OAuth (not API key)
_configure_gemini_settings() {
    local target_home="$1"
    local settings_dir="$target_home/.gemini"
    local settings_file="$settings_dir/settings.json"

    # Create settings directory if needed
    _agent_run_as_user "mkdir -p '$settings_dir'" || return 1

    # If settings file doesn't exist, create it with tmux-compatible defaults and OAuth auth
    if [[ ! -f "$settings_file" ]]; then
        log_detail "Creating Gemini settings for tmux compatibility and OAuth auth..."
        # Write default settings - the JSON is simple enough to inline
        # Note: Using double quotes for variable expansion, escaping inner quotes
        _agent_run_as_user "cat > '$settings_file' << 'GEMINI_EOF'
{
  \"selectedType\": \"oauth-personal\",
  \"tools\": {
    \"shell\": {
      \"enableInteractiveShell\": false
    }
  }
}
GEMINI_EOF"
        return $?
    fi

    # Settings file exists - merge our settings if jq is available
    if command -v jq &>/dev/null; then
        local tmp_file="$settings_dir/.settings.tmp.$$"
        local needs_update=false

        # Check if enableInteractiveShell is already set correctly
        local shell_value
        shell_value=$(_agent_run_as_user "jq -r 'if .tools.shell | has(\"enableInteractiveShell\") then .tools.shell.enableInteractiveShell | tostring else \"unset\" end' '$settings_file'" 2>/dev/null || echo "error")

        if [[ "$shell_value" != "false" ]]; then
            needs_update=true
        fi

        # Check if selectedType is set to oauth-personal (fix gemini-api-key if found)
        local auth_value
        auth_value=$(_agent_run_as_user "jq -r '.selectedType // \"unset\"' '$settings_file'" 2>/dev/null || echo "error")

        if [[ "$auth_value" == "gemini-api-key" ]]; then
            log_detail "Fixing Gemini auth from API key to OAuth..."
            needs_update=true
        elif [[ "$auth_value" == "unset" || "$auth_value" == "error" ]]; then
            needs_update=true
        fi

        if [[ "$needs_update" == "true" ]]; then
            log_detail "Configuring Gemini settings for tmux compatibility and OAuth..."
            # Update both shell settings and auth type
            if _agent_run_as_user "jq '.selectedType = \"oauth-personal\" | .tools = (.tools // {}) | .tools.shell = (.tools.shell // {}) | .tools.shell.enableInteractiveShell = false' '$settings_file' > '$tmp_file' && mv '$tmp_file' '$settings_file'" 2>/dev/null; then
                log_detail "Gemini settings configured (OAuth + tmux compatibility)"
            else
                _agent_run_as_user "rm -f '$tmp_file'" 2>/dev/null
                log_warn "Could not update Gemini settings automatically"
            fi
        else
            log_detail "Gemini settings already configured correctly"
        fi
    else
        log_detail "jq not available; skipping Gemini settings merge"
    fi

    return 0
}

# Install Gemini CLI via bun
# The official package is @google/gemini-cli
install_gemini_cli() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local bun_bin
    bun_bin=$(_agent_get_bun_bin)
    local gemini_bin="$target_home/.bun/bin/$GEMINI_BIN"
    local gemini_wrapper="$target_home/.local/bin/gemini"

    # Check if already installed (wrapper takes precedence)
    if [[ -x "$gemini_wrapper" ]]; then
        log_detail "Gemini CLI already installed at $gemini_wrapper"
        # Ensure tmux-compatible settings are configured
        _configure_gemini_settings "$target_home"
        return 0
    fi
    if [[ -x "$gemini_bin" ]]; then
        log_detail "Gemini CLI already installed at $gemini_bin"
        # Create wrapper if missing (fixes node PATH issues)
        _agent_create_bun_wrapper "$target_home" "gemini"
        # Ensure tmux-compatible settings are configured
        _configure_gemini_settings "$target_home"
        return 0
    fi

    # Verify bun is available
    if ! _agent_check_bun; then
        return 1
    fi

    log_detail "Installing Gemini CLI for $target_user..."

    # Install via bun global
    if _agent_run_as_user "\"$bun_bin\" install -g --trust $GEMINI_PACKAGE"; then
        if [[ -x "$gemini_bin" ]]; then
            # Create wrapper script that uses bun as runtime (avoids node PATH issues)
            _agent_create_bun_wrapper "$target_home" "gemini"
            # Configure settings for tmux/agent compatibility
            _configure_gemini_settings "$target_home"
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
    if _agent_run_as_user "\"$bun_bin\" install -g --trust $GEMINI_PACKAGE"; then
        log_success "Gemini CLI upgraded"
        return 0
    else
        log_warn "Gemini CLI upgrade failed"
        return 1
    fi
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
# Returns: 0 if all succeeded, 1 if any failed
upgrade_all_agents() {
    log_detail "Upgrading all coding agents..."

    local failed=0

    if ! upgrade_claude_code; then
        ((failed++))
    fi
    if ! upgrade_codex_cli; then
        ((failed++))
    fi
    if ! upgrade_gemini_cli; then
        ((failed++))
    fi

    if ((failed == 0)); then
        log_success "All coding agents upgraded"
        return 0
    elif ((failed == 3)); then
        log_error "All agent upgrades failed"
        return 1
    else
        log_warn "Some agent upgrades failed ($failed of 3)"
        return 1
    fi
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
