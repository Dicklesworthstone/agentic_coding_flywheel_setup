#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Installer - Post-Install Smoke Test
# Fast verification that runs at the end of install.sh
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

# Test result counters (reset in run_smoke_test)
CRITICAL_PASS=0
CRITICAL_FAIL=0
NONCRITICAL_PASS=0
WARNING_COUNT=0

# Target user (from install.sh or default)
TARGET_USER="${TARGET_USER:-ubuntu}"
TARGET_HOME="${TARGET_HOME:-/home/$TARGET_USER}"

# ============================================================
# Output Helpers
# ============================================================

_smoke_pass() {
    local label="$1"
    echo -e "  ${ACFS_GREEN:-\033[0;32m}✅${ACFS_NC:-\033[0m} $label"
    ((CRITICAL_PASS += 1))
}

_smoke_fail() {
    local label="$1"
    local fix="${2:-}"
    echo -e "  ${ACFS_RED:-\033[0;31m}❌${ACFS_NC:-\033[0m} $label"
    if [[ -n "$fix" ]]; then
        echo -e "     ${ACFS_GRAY:-\033[0;90m}Fix: $fix${ACFS_NC:-\033[0m}"
    fi
    ((CRITICAL_FAIL += 1))
}

_smoke_warn() {
    local label="$1"
    local note="${2:-}"
    echo -e "  ${ACFS_YELLOW:-\033[0;33m}⚠️${ACFS_NC:-\033[0m} $label"
    if [[ -n "$note" ]]; then
        echo -e "     ${ACFS_GRAY:-\033[0;90m}$note${ACFS_NC:-\033[0m}"
    fi
    ((WARNING_COUNT += 1))
}

# Non-critical pass (doesn't affect critical count)
_smoke_info() {
    local label="$1"
    echo -e "  ${ACFS_GREEN:-\033[0;32m}✅${ACFS_NC:-\033[0m} $label"
    ((NONCRITICAL_PASS += 1))
}

_smoke_header() {
    echo ""
    echo -e "${ACFS_BLUE:-\033[0;34m}[Smoke Test]${ACFS_NC:-\033[0m}"
    echo ""
}

# ============================================================
# Critical Checks (must pass)
# ============================================================

# Check 1: User is ubuntu
_check_user() {
    local current_user
    current_user=$(whoami)
    if [[ "$current_user" == "$TARGET_USER" ]]; then
        _smoke_pass "User: $TARGET_USER"
        return 0
    else
        _smoke_fail "User: expected $TARGET_USER, got $current_user" "ssh $TARGET_USER@YOUR_SERVER"
        return 1
    fi
}

# Check 2: Shell is zsh
_check_shell() {
    local shell
    shell=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f7)
    if [[ "$shell" == *"zsh"* ]]; then
        _smoke_pass "Shell: zsh"
        return 0
    else
        _smoke_fail "Shell: expected zsh, got $shell" "chsh -s \$(which zsh)"
        return 1
    fi
}

# Check 3: Passwordless sudo works
_check_sudo() {
    if sudo -n true 2>/dev/null; then
        _smoke_pass "Sudo: passwordless"
        return 0
    else
        _smoke_fail "Sudo: requires password" "Re-run installer with --mode vibe"
        return 1
    fi
}

# Check 4: /data/projects exists
_check_workspace() {
    if [[ -d "/data/projects" ]]; then
        _smoke_pass "Workspace: /data/projects exists"
        return 0
    else
        _smoke_fail "Workspace: /data/projects missing" "sudo mkdir -p /data/projects && sudo chown $TARGET_USER:$TARGET_USER /data/projects"
        return 1
    fi
}

# Check 5: Language runtimes available
_check_languages() {
    local missing=()

    # Check bun
    if [[ -x "$TARGET_HOME/.bun/bin/bun" ]] || command -v bun &>/dev/null; then
        :
    else
        missing+=("bun")
    fi

    # Check uv
    if [[ -x "$TARGET_HOME/.local/bin/uv" ]] || command -v uv &>/dev/null; then
        :
    else
        missing+=("uv")
    fi

    # Check cargo
    if [[ -x "$TARGET_HOME/.cargo/bin/cargo" ]] || command -v cargo &>/dev/null; then
        :
    else
        missing+=("cargo")
    fi

    # Check go
    if command -v go &>/dev/null; then
        :
    else
        missing+=("go")
    fi

    if [[ ${#missing[@]} -eq 0 ]]; then
        _smoke_pass "Languages: bun, uv, cargo, go"
        return 0
    else
        _smoke_fail "Languages: missing ${missing[*]}" "Re-run installer"
        return 1
    fi
}

# Check 6: Agent CLIs exist
_check_agents() {
    local found=()
    local missing=()

    # Check for each agent CLI
    if command -v claude &>/dev/null; then
        found+=("claude")
    else
        missing+=("claude")
    fi

    if command -v codex &>/dev/null || [[ -x "$TARGET_HOME/.bun/bin/codex" ]]; then
        found+=("codex")
    else
        missing+=("codex")
    fi

    if command -v gemini &>/dev/null || [[ -x "$TARGET_HOME/.bun/bin/gemini" ]]; then
        found+=("gemini")
    else
        missing+=("gemini")
    fi

    if [[ ${#missing[@]} -eq 0 ]]; then
        _smoke_pass "Agents: ${found[*]}"
        return 0
    elif [[ ${#found[@]} -gt 0 ]]; then
        # At least one agent found
        _smoke_pass "Agents: ${found[*]}"
        _smoke_warn "Missing agents: ${missing[*]}" "May need manual installation"
        return 0
    else
        _smoke_fail "Agents: none found" "bun install -g @openai/codex @google/gemini-cli"
        return 1
    fi
}

# Check 7: NTM command works
_check_ntm() {
    if command -v ntm &>/dev/null; then
        _smoke_pass "NTM: installed"
        return 0
    else
        _smoke_fail "NTM: not found" "Re-run the ACFS installer (stack phase)"
        return 1
    fi
}

# Check 8: Onboard command exists
_check_onboard() {
    if command -v onboard &>/dev/null || [[ -x "$TARGET_HOME/.local/bin/onboard" ]] || [[ -x "$TARGET_HOME/.acfs/bin/onboard" ]]; then
        _smoke_pass "Onboard: installed"
        return 0
    else
        _smoke_fail "Onboard: not found" "Check ~/.acfs/bin/onboard"
        return 1
    fi
}

# ============================================================
# Non-Critical Checks (warn only)
# ============================================================

# Check: Agent Mail can respond
_check_agent_mail() {
    if curl -fsS --max-time 5 http://127.0.0.1:8765/health &>/dev/null; then
        _smoke_info "Agent Mail: running"
    else
        _smoke_warn "Agent Mail: not started" "run 'am' to start"
    fi
}

# Check: Stack tools respond to --help
_check_stack_tools() {
    local stack_tools=("slb" "ubs" "bv" "cass" "cm" "caam")
    local found=()
    local missing=()

    for tool in "${stack_tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            found+=("$tool")
        else
            missing+=("$tool")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        _smoke_info "Stack tools: all installed"
    else
        _smoke_warn "Stack tools missing: ${missing[*]}" "Some tools may need manual install"
    fi
}

# Check: PostgreSQL running
_check_postgres() {
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        _smoke_info "PostgreSQL: running"
    elif command -v psql &>/dev/null; then
        _smoke_warn "PostgreSQL: installed but not running" "sudo systemctl start postgresql"
    else
        _smoke_warn "PostgreSQL: not installed" "optional - install with apt"
    fi
}

# ============================================================
# Main Smoke Test Function
# ============================================================

run_smoke_test() {
    # Reset counters (important if run multiple times in same shell)
    CRITICAL_PASS=0
    CRITICAL_FAIL=0
    NONCRITICAL_PASS=0
    WARNING_COUNT=0

    local start_time
    start_time=$(date +%s)

    _smoke_header

    echo "Critical Checks:"

    # Run all critical checks
    _check_user
    _check_shell
    _check_sudo
    _check_workspace
    _check_languages
    _check_agents
    _check_ntm
    _check_onboard

    echo ""
    echo "Non-Critical Checks:"

    # Run non-critical checks
    _check_agent_mail
    _check_stack_tools
    _check_postgres

    # Calculate duration
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Print summary
    echo ""
    local total_critical=$((CRITICAL_PASS + CRITICAL_FAIL))

    if [[ $CRITICAL_FAIL -eq 0 ]]; then
        echo -e "${ACFS_GREEN:-\033[0;32m}Smoke test: $CRITICAL_PASS/$total_critical critical passed${ACFS_NC:-\033[0m}"
    else
        echo -e "${ACFS_RED:-\033[0;31m}Smoke test: $CRITICAL_PASS/$total_critical critical passed, $CRITICAL_FAIL failed${ACFS_NC:-\033[0m}"
    fi

    if [[ $WARNING_COUNT -gt 0 ]]; then
        echo -e "${ACFS_YELLOW:-\033[0;33m}$WARNING_COUNT warning(s)${ACFS_NC:-\033[0m}"
    fi

    echo -e "${ACFS_GRAY:-\033[0;90m}Completed in ${duration}s${ACFS_NC:-\033[0m}"
    echo ""

    # Return exit code based on critical failures
    if [[ $CRITICAL_FAIL -gt 0 ]]; then
        echo -e "${ACFS_YELLOW:-\033[0;33m}Some critical checks failed. Run 'acfs doctor' for detailed diagnostics.${ACFS_NC:-\033[0m}"
        return 1
    fi

    echo -e "${ACFS_GREEN:-\033[0;32m}Installation successful! Run 'onboard' to start the tutorial.${ACFS_NC:-\033[0m}"
    return 0
}

# ============================================================
# Module can be sourced or run directly
# ============================================================

# If run directly (not sourced), execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_smoke_test "$@"
fi
