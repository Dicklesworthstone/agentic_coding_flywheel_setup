#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Installer - Dicklesworthstone Stack Library
# Installs all 8 Dicklesworthstone tools
# ============================================================

STACK_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure we have logging functions available
if [[ -z "${ACFS_BLUE:-}" ]]; then
    # shellcheck source=logging.sh
    source "$STACK_SCRIPT_DIR/logging.sh"
fi

# ============================================================
# Configuration
# ============================================================

# Tool commands for verification
declare -gA STACK_COMMANDS=(
    [ntm]="ntm"
    [mcp_agent_mail]="am"
    [ubs]="ubs"
    [bv]="bv"
    [cass]="cass"
    [cm]="cm"
    [caam]="caam"
    [slb]="slb"
)

# Tool display names
declare -gA STACK_NAMES=(
    [ntm]="NTM (Named Tmux Manager)"
    [mcp_agent_mail]="MCP Agent Mail"
    [ubs]="Ultimate Bug Scanner"
    [bv]="Beads Viewer"
    [cass]="CASS (Coding Agent Session Search)"
    [cm]="CM (CASS Memory System)"
    [caam]="CAAM (Coding Agent Account Manager)"
    [slb]="SLB (Simultaneous Launch Button)"
)

# ============================================================
# Helper Functions
# ============================================================

# Check if a command exists
_stack_command_exists() {
    command -v "$1" &>/dev/null
}

# Check if we're in interactive mode (fallback if security.sh isn't loaded yet).
_stack_is_interactive() {
    if declare -f _acfs_is_interactive >/dev/null 2>&1; then
        _acfs_is_interactive
        return $?
    fi

    [[ "${ACFS_INTERACTIVE:-true}" == "true" ]] && [[ -t 0 ]]
}

# Get the sudo command if needed
_stack_get_sudo() {
    if [[ $EUID -eq 0 ]]; then
        echo ""
    else
        echo "sudo"
    fi
}

# Run a command as target user
_stack_run_as_user() {
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

    su - "$target_user" -c "bash -c $(printf %q "$wrapped_cmd")"
}

# Load security helpers + checksums.yaml (fail closed if unavailable).
STACK_SECURITY_READY=false
_stack_require_security() {
    if [[ "${STACK_SECURITY_READY}" == "true" ]]; then
        return 0
    fi

    if [[ ! -f "$STACK_SCRIPT_DIR/security.sh" ]]; then
        log_warn "Security library not found ($STACK_SCRIPT_DIR/security.sh); refusing to run upstream installer scripts"
        return 1
    fi

    # shellcheck source=security.sh
    source "$STACK_SCRIPT_DIR/security.sh"
    if ! load_checksums; then
        log_warn "checksums.yaml not available; refusing to run upstream installer scripts"
        return 1
    fi

    STACK_SECURITY_READY=true
    return 0
}

# Run an installer script as target user with checksum verification.
_stack_run_installer() {
    local tool="$1"
    shift || true
    local args="${*:-}"

    if ! _stack_require_security; then
        return 1
    fi

    local url="${KNOWN_INSTALLERS[$tool]:-}"
    local expected_sha256
    expected_sha256="$(get_checksum "$tool")"

    if [[ -z "$url" ]]; then
        log_warn "No installer URL configured for $tool (KNOWN_INSTALLERS)"
        return 1
    fi
    if [[ -z "$expected_sha256" ]]; then
        log_warn "No checksum recorded for $tool; refusing to run unverified installer"
        return 1
    fi

    _stack_run_as_user "source '$STACK_SCRIPT_DIR/security.sh'; verify_checksum '$url' '$expected_sha256' '$tool' | bash -s -- ${args:-}"
}

# Check if a stack tool is installed
_stack_is_installed() {
    local tool="$1"
    local cmd="${STACK_COMMANDS[$tool]}"

    if [[ -z "$cmd" ]]; then
        return 1
    fi

    # Check in common locations
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"

    # Check PATH
    if _stack_command_exists "$cmd"; then
        return 0
    fi

    # Check user's local bin
    if [[ -x "$target_home/.local/bin/$cmd" ]]; then
        return 0
    fi

    # Check user's bin
    if [[ -x "$target_home/bin/$cmd" ]]; then
        return 0
    fi

    return 1
}

# ============================================================
# Individual Tool Installers
# ============================================================

# Install NTM (Named Tmux Manager)
# Agent orchestration cockpit
install_ntm() {
    local tool="ntm"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_installer "$tool"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install MCP Agent Mail
# Agent coordination server
install_mcp_agent_mail() {
    local tool="mcp_agent_mail"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    # MCP Agent Mail uses --yes for non-interactive install
    local args=""
    if ! _stack_is_interactive; then
        args="--yes"
    fi

    if _stack_run_installer "$tool" "$args"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install Ultimate Bug Scanner (UBS)
# Bug scanning with guardrails
install_ubs() {
    local tool="ubs"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    # UBS uses --easy-mode for simplified setup
    # Also add --yes for non-interactive installs if needed by UBS installer
    local args="--easy-mode"
    if ! _stack_is_interactive; then
        args="$args --yes"
    fi

    if _stack_run_installer "$tool" "$args"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install Beads Viewer (BV)
# Task management TUI
install_bv() {
    local tool="bv"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_installer "$tool"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install CASS (Coding Agent Session Search)
# Unified session search
install_cass() {
    local tool="cass"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    # CASS uses --easy-mode --verify for simplified setup with verification
    if _stack_run_installer "$tool" "--easy-mode --verify"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install CM (CASS Memory System)
# Procedural memory for agents
install_cm() {
    local tool="cm"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    # CM uses --easy-mode --verify for simplified setup with verification
    if _stack_run_installer "$tool" "--easy-mode --verify"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install CAAM (Coding Agent Account Manager)
# Auth switching
install_caam() {
    local tool="caam"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_installer "$tool"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install SLB (Simultaneous Launch Button)
# Two-person rule for dangerous commands
install_slb() {
    local tool="slb"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_installer "$tool"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# ============================================================
# Verification Functions
# ============================================================

# Verify all stack tools are installed
verify_stack() {
    local all_pass=true
    local installed_count=0
    local total_count=${#STACK_COMMANDS[@]}

    log_detail "Verifying Dicklesworthstone stack..."

    for tool in ntm mcp_agent_mail ubs bv cass cm caam slb; do
        local cmd="${STACK_COMMANDS[$tool]}"
        local name="${STACK_NAMES[$tool]}"

        if _stack_is_installed "$tool"; then
            log_detail "  $cmd: installed"
            ((installed_count += 1))
        else
            log_warn "  Missing: $cmd ($name)"
            all_pass=false
        fi
    done

    if [[ "$all_pass" == "true" ]]; then
        log_success "All $total_count stack tools verified"
        return 0
    else
        log_warn "Stack: $installed_count/$total_count tools installed"
        return 1
    fi
}

# Check if stack tools respond to --help
verify_stack_help() {
    local failures=()

    log_detail "Testing stack tools --help..."

    for tool in ntm mcp_agent_mail ubs bv cass cm caam slb; do
        local cmd="${STACK_COMMANDS[$tool]}"

        if _stack_is_installed "$tool"; then
            if ! _stack_run_as_user "$cmd --help >/dev/null 2>&1"; then
                failures+=("$cmd")
            fi
        fi
    done

    if [[ ${#failures[@]} -gt 0 ]]; then
        log_warn "Stack tools --help failed: ${failures[*]}"
        return 1
    fi

    log_success "All stack tools respond to --help"
    return 0
}

# Get versions of installed stack tools (for doctor output)
get_stack_versions() {
    echo "Dicklesworthstone Stack Versions:"

    for tool in ntm mcp_agent_mail ubs bv cass cm caam slb; do
        local cmd="${STACK_COMMANDS[$tool]}"
        local name="${STACK_NAMES[$tool]}"

        if _stack_is_installed "$tool"; then
            local version
            version=$(_stack_run_as_user "$cmd --version 2>/dev/null" || echo "installed")
            echo "  $cmd: $version"
        fi
    done
}

# ============================================================
# Main Installation Function
# ============================================================

# Install all stack tools (called by install.sh)
install_all_stack() {
    log_step "7/8" "Installing Dicklesworthstone stack..."

    # Install in recommended order
    install_ntm
    install_mcp_agent_mail
    install_ubs
    install_bv
    install_cass
    install_cm
    install_caam
    install_slb

    # Verify installation
    verify_stack

    log_success "Dicklesworthstone stack installation complete"
}

# ============================================================
# Module can be sourced or run directly
# ============================================================

# If run directly (not sourced), execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_all_stack "$@"
fi
