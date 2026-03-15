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

_agent_apply_verified_gemini_patch() {
    local patch_tool="gemini_patch"
    local patch_url="https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/fix-gemini-cli-ebadf-crash.sh"
    local patch_sha=""

    if [[ -f "$AGENTS_SCRIPT_DIR/security.sh" ]]; then
        # shellcheck source=security.sh
        source "$AGENTS_SCRIPT_DIR/security.sh"
        if load_checksums; then
            patch_url="${KNOWN_INSTALLERS[$patch_tool]:-$patch_url}"
            patch_sha="$(get_checksum "$patch_tool")"
        fi
    fi

    if [[ -z "$patch_sha" ]]; then
        log_warn "Gemini patch checksum unavailable; skipping patch for safety"
        return 1
    fi

    if _agent_run_as_user "source '$AGENTS_SCRIPT_DIR/security.sh'; verify_checksum '$patch_url' '$patch_sha' '$patch_tool' | bash -s --"; then
        return 0
    fi

    log_warn "Gemini patch verification failed; skipping patch"
    return 1
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
                if _agent_run_as_user "source '$AGENTS_SCRIPT_DIR/security.sh'; verify_checksum '$url' '$sha' 'claude' | bash -s -- latest"; then
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
        if _agent_run_as_user "\"$claude_bin\" update --channel latest"; then
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
        log_detail "Note: Run 'codex login --device-auth' to authenticate with your ChatGPT Pro account"
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

    # Detect MCP base path: Rust am uses /mcp/, Python mcp_agent_mail uses /api/
    local am_mcp_path="/mcp/"
    if command -v am &>/dev/null; then
        if ! am --version 2>/dev/null | grep -q '^am '; then
            am_mcp_path="/api/"
        fi
    fi
    local am_mcp_url="http://127.0.0.1:8765${am_mcp_path}"

    # Create settings directory if needed
    _agent_run_as_user "mkdir -p '$settings_dir'" || return 1

    # If settings file doesn't exist, create it with tmux-compatible defaults, OAuth auth,
    # and MCP Agent Mail server configuration (fixes #158)
    if [[ ! -f "$settings_file" ]]; then
        log_detail "Creating Gemini settings for tmux compatibility, OAuth auth, and MCP Agent Mail..."
        # Write default settings - the JSON is simple enough to inline
        # Note: Using double quotes for variable expansion, escaping inner quotes
        _agent_run_as_user "cat > '$settings_file' << 'GEMINI_EOF'
{
  \"selectedType\": \"oauth-personal\",
  \"tools\": {
    \"shell\": {
      \"enableInteractiveShell\": false
    }
  },
  \"mcpServers\": {
    \"mcp-agent-mail\": {
      \"httpUrl\": \"$am_mcp_url\"
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

        # Check if MCP Agent Mail server is configured (fixes #158)
        local mcp_value
        mcp_value=$(_agent_run_as_user "jq -r '.mcpServers.\"mcp-agent-mail\".httpUrl // \"unset\"' '$settings_file'" 2>/dev/null || echo "error")
        if [[ "$mcp_value" == "unset" || "$mcp_value" == "error" ]]; then
            needs_update=true
        fi

        if [[ "$needs_update" == "true" ]]; then
            log_detail "Configuring Gemini settings for tmux compatibility, OAuth, and MCP Agent Mail..."
            # Update shell settings, auth type, and MCP server config
            if _agent_run_as_user "jq '.selectedType = \"oauth-personal\" | .tools = (.tools // {}) | .tools.shell = (.tools.shell // {}) | .tools.shell.enableInteractiveShell = false | .mcpServers = (.mcpServers // {}) | .mcpServers.\"mcp-agent-mail\" = {\"httpUrl\": \"$am_mcp_url\"}' '$settings_file' > '$tmp_file' && mv '$tmp_file' '$settings_file'" 2>/dev/null; then
                log_detail "Gemini settings configured (OAuth + tmux + MCP Agent Mail)"
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
            # Apply patches (EBADF crash fix, rate-limit retry 3→1000, quota retry)
            log_detail "Applying Gemini CLI patches..."
            _agent_apply_verified_gemini_patch || true
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
        # Apply patches (EBADF crash fix, rate-limit retry 3→1000, quota retry)
        log_detail "Applying Gemini CLI patches..."
        _agent_apply_verified_gemini_patch || true
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

    # Claude: require a non-empty OAuth token, not just a config file.
    local claude_creds_file="$target_home/.claude/.credentials.json"
    local claude_configured=false
    if command -v jq &>/dev/null; then
        if [[ -f "$claude_creds_file" ]] && jq -e '((.claudeAiOauth.accessToken // "") | strings | length) > 0' "$claude_creds_file" >/dev/null 2>&1; then
            claude_configured=true
        fi
    elif [[ -f "$claude_creds_file" ]] && grep -Eq '"accessToken"[[:space:]]*:[[:space:]]*"[^"]+"' "$claude_creds_file" 2>/dev/null; then
        claude_configured=true
    fi

    if [[ "$claude_configured" == "true" ]]; then
        log_detail "  Claude: configured"
    else
        log_warn "  Claude: not configured (run 'claude' to login)"
    fi

    # Codex: require a non-empty OAuth/API token, not just auth.json presence.
    local codex_home="${CODEX_HOME:-$target_home/.codex}"
    local codex_auth_file="$codex_home/auth.json"
    local codex_configured=false
    if command -v jq &>/dev/null; then
        if [[ -f "$codex_auth_file" ]] && \
           jq -e '((.tokens.access_token // .access_token // .accessToken // .OPENAI_API_KEY // "") | strings | length) > 0' "$codex_auth_file" >/dev/null 2>&1; then
            codex_configured=true
        fi
    elif [[ -f "$codex_auth_file" ]] && grep -Eq '"(access(_token|Token)|OPENAI_API_KEY)"[[:space:]]*:[[:space:]]*"[^"]+"' "$codex_auth_file" 2>/dev/null; then
        codex_configured=true
    fi

    if [[ "$codex_configured" == "true" ]]; then
        log_detail "  Codex: configured"
    else
        log_warn "  Codex: not configured (run 'codex login --device-auth' to authenticate)"
    fi

    # Gemini: require a non-empty active account or token, not just file presence.
    local gemini_accounts_file="$target_home/.gemini/google_accounts.json"
    local gemini_oauth_file="$target_home/.gemini/oauth_creds.json"
    local gemini_configured=false

    if command -v jq &>/dev/null; then
        if [[ -f "$gemini_accounts_file" ]] && jq -e '((.active // "") | strings | length) > 0' "$gemini_accounts_file" >/dev/null 2>&1; then
            gemini_configured=true
        elif [[ -f "$gemini_oauth_file" ]] && \
             jq -e '((.access_token // "") | strings | length) > 0 or ((.refresh_token // "") | strings | length) > 0' "$gemini_oauth_file" >/dev/null 2>&1; then
            gemini_configured=true
        fi
    else
        if [[ -f "$gemini_accounts_file" ]] && grep -Eq '"active"[[:space:]]*:[[:space:]]*"[^"]+"' "$gemini_accounts_file" 2>/dev/null; then
            gemini_configured=true
        elif [[ -f "$gemini_oauth_file" ]] && grep -Eq '"(access_token|refresh_token)"[[:space:]]*:[[:space:]]*"[^"]+"' "$gemini_oauth_file" 2>/dev/null; then
            gemini_configured=true
        fi
    fi

    if [[ "$gemini_configured" == "true" ]]; then
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
        failed=$((failed + 1))
    fi
    if ! upgrade_codex_cli; then
        failed=$((failed + 1))
    fi
    if ! upgrade_gemini_cli; then
        failed=$((failed + 1))
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
    log_detail "  • Codex:  Run 'codex login --device-auth' (uses ChatGPT Pro account, not API key)"
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
