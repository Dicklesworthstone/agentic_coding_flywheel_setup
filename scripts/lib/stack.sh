#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Installer - Dicklesworthstone Stack Library
# Installs all 18 Dicklesworthstone tools + utilities
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
    [ru]="ru"
    [dcg]="dcg"
    [rch]="rch"
    [pt]="pt"
    [fsfs]="fsfs"
    [sbh]="sbh"
    [casr]="casr"
    [dsr]="dsr"
    [asb]="asb"
    [pcr]="claude-post-compact-reminder"
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
    [ru]="RU (Repo Updater)"
    [dcg]="DCG (Destructive Command Guard)"
    [rch]="RCH (Remote Compilation Helper)"
    [pt]="PT (Process Triage)"
    [fsfs]="Frankensearch"
    [sbh]="SBH (Storage Ballast Helper)"
    [casr]="CASR (Cross-Agent Session Resumer)"
    [dsr]="DSR (Doodlestein Self-Releaser)"
    [asb]="ASB (Agent Settings Backup)"
    [pcr]="PCR (Post-Compact Reminder)"
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

    [[ "${ACFS_INTERACTIVE:-true}" == "true" ]] || return 1

    if [[ -e /dev/tty ]] && (exec 3<>/dev/tty) 2>/dev/null; then
        return 0
    fi

    [[ -t 0 ]]
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
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local target_path_prefix="${ACFS_BIN_DIR:-$target_home/.local/bin}:$target_home/.cargo/bin:$target_home/.bun/bin:$target_home/.atuin/bin:$target_home/go/bin"
    local cmd="$1"
    local wrapped_cmd="export PATH=\"$target_path_prefix:\$PATH\"; set -o pipefail; $cmd"

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
# Some upstream installers use environment variables instead of CLI flags for
# non-interactive mode, so allow one optional inline env assignment like VAR=value.
_stack_run_verified_installer_with_env() {
    if [[ $# -lt 1 ]]; then
        log_warn "_stack_run_verified_installer_with_env requires at least a tool name"
        return 1
    fi

    local tool="$1"
    local bash_env_assignment="${2:-}"
    if [[ $# -ge 2 ]]; then
        shift 2
    else
        set --
    fi

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
    if [[ -n "$bash_env_assignment" ]] && [[ ! "$bash_env_assignment" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+$ ]]; then
        log_warn "Invalid inline env assignment for $tool installer: $bash_env_assignment"
        return 1
    fi

    local -a quoted_args=()
    local arg
    for arg in "$@"; do
        quoted_args+=("$(printf '%q' "$arg")")
    done

    local cmd="source '$STACK_SCRIPT_DIR/security.sh'; verify_checksum '$url' '$expected_sha256' '$tool' | "
    if [[ -n "$bash_env_assignment" ]]; then
        cmd+="$bash_env_assignment "
    fi
    cmd+="bash -s --"
    if [[ ${#quoted_args[@]} -gt 0 ]]; then
        cmd+=" ${quoted_args[*]}"
    fi

    _stack_run_as_user "$cmd"
}

_stack_run_verified_installer() {
    if [[ $# -lt 1 ]]; then
        log_warn "_stack_run_verified_installer requires a tool name"
        return 1
    fi

    local tool="$1"
    if [[ $# -ge 1 ]]; then
        shift
    else
        set --
    fi
    _stack_run_verified_installer_with_env "$tool" "" "$@"
}

_stack_run_installer() {
    if [[ $# -lt 1 ]]; then
        log_warn "_stack_run_installer requires a tool name"
        return 1
    fi

    local tool="$1"
    if [[ $# -ge 1 ]]; then
        shift
    else
        set --
    fi
    _stack_run_verified_installer "$tool" "$@"
}

# Check whether the local Agent Mail HTTP service is healthy.
_stack_agent_mail_healthy() {
    curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1
}

_stack_agent_mail_ready() {
    local check_cmd
    check_cmd="$(cat <<'EOF'
set -euo pipefail
command -v am >/dev/null 2>&1

if ! curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1; then
    exit 1
fi

runtime_dir="/run/user/$(id -u)"
if [[ -d "$runtime_dir" ]]; then
    export XDG_RUNTIME_DIR="$runtime_dir"
    if [[ -S "$runtime_dir/bus" ]]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
    fi
fi

if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user is-active --quiet agent-mail.service >/dev/null 2>&1
fi
EOF
)"

    _stack_run_as_user "$check_cmd"
}

# Write and enable the managed Agent Mail user service for the target user.
_stack_configure_agent_mail_service() {
    local service_cmd
    service_cmd="$(cat <<'EOF'
set -euo pipefail
command -v am >/dev/null 2>&1
storage_root="$HOME/.mcp_agent_mail_git_mailbox_repo"
unit_dir="$HOME/.config/systemd/user"
unit_file="$unit_dir/agent-mail.service"
am_bin="$(command -v am)"
db_url="sqlite+aiosqlite:///${storage_root}/storage.sqlite3"

# Detect MCP base path: Rust am uses /mcp/, Python mcp_agent_mail uses /api/
if "$am_bin" --version 2>/dev/null | grep -q '^am '; then
    am_mcp_path="/mcp/"
else
    am_mcp_path="/api/"
fi

mkdir -p "$storage_root" "$unit_dir"
cat > "$unit_file" <<UNIT_EOF
[Unit]
Description=MCP Agent Mail Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$storage_root
Environment=RUST_LOG=info
Environment=STORAGE_ROOT=$storage_root
Environment=DATABASE_URL=$db_url
Environment=HTTP_PATH=$am_mcp_path
ExecStart=$am_bin serve-http --host 127.0.0.1 --port 8765 --path $am_mcp_path --no-auth --no-tui
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=default.target
UNIT_EOF

runtime_dir="/run/user/$(id -u)"
if [[ -d "$runtime_dir" ]]; then
    export XDG_RUNTIME_DIR="$runtime_dir"
    if [[ -S "$runtime_dir/bus" ]]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
    fi
fi

fallback_pid_file="$storage_root/agent-mail.pid"
fallback_log_file="$storage_root/agent-mail.log"

stop_agent_mail_fallback() {
    if [[ -f "$fallback_pid_file" ]]; then
        existing_pid="$(cat "$fallback_pid_file" 2>/dev/null || true)"
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null && \
           ps -p "$existing_pid" -o args= 2>/dev/null | grep -Fq "$am_bin serve-http"; then
            kill "$existing_pid" >/dev/null 2>&1 || true
            for _ in {1..10}; do
                if ! kill -0 "$existing_pid" 2>/dev/null; then
                    break
                fi
                sleep 1
            done
            if kill -0 "$existing_pid" 2>/dev/null; then
                kill -9 "$existing_pid" >/dev/null 2>&1 || true
            fi
        fi
        rm -f "$fallback_pid_file"
    fi
}

launch_agent_mail_fallback() {
    if curl -fsS --max-time 5 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1; then
        return 0
    fi

    if [[ -f "$fallback_pid_file" ]]; then
        existing_pid="$(cat "$fallback_pid_file" 2>/dev/null || true)"
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null && \
           ps -p "$existing_pid" -o args= 2>/dev/null | grep -Fq "$am_bin serve-http"; then
            return 0
        fi
        rm -f "$fallback_pid_file"
    fi

    nohup env \
        RUST_LOG=info \
        STORAGE_ROOT="$storage_root" \
        DATABASE_URL="$db_url" \
        HTTP_PATH="$am_mcp_path" \
        "$am_bin" serve-http --host 127.0.0.1 --port 8765 --path "$am_mcp_path" --no-auth --no-tui \
        >>"$fallback_log_file" 2>&1 < /dev/null &
    echo $! > "$fallback_pid_file"
}

if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
    stop_agent_mail_fallback
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    if ! systemctl --user enable --now agent-mail.service >/dev/null 2>&1; then
        systemctl --user restart agent-mail.service >/dev/null 2>&1
    fi
    active_waited=0
    active_max_wait=10
    until systemctl --user is-active --quiet agent-mail.service >/dev/null 2>&1; do
        if [[ "$active_waited" -ge "$active_max_wait" ]]; then
            break
        fi
        sleep 1
        active_waited=$((active_waited + 1))
    done
    systemctl --user is-active --quiet agent-mail.service >/dev/null 2>&1
else
    echo "Agent Mail: systemctl --user unavailable, using background fallback" >&2
    launch_agent_mail_fallback
fi
EOF
)"

    _stack_run_as_user "$service_cmd"
}

# Wait for the managed Agent Mail service to become healthy.
_stack_wait_for_agent_mail_health() {
    local waited=0
    local max_wait=30

    until _stack_agent_mail_healthy; do
        if [[ "$waited" -ge "$max_wait" ]]; then
            return 1
        fi
        sleep 2
        waited=$((waited + 2))
    done

    return 0
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

# PCR is only fully installed once both the hook binary and Claude settings entry exist.
_stack_pcr_installed() {
    local target_home="${TARGET_HOME:-/home/${TARGET_USER:-ubuntu}}"
    local hook_script="$target_home/.local/bin/claude-post-compact-reminder"
    local settings_file="$target_home/.claude/settings.json"
    local alt_settings_file="$target_home/.config/claude/settings.json"

    [[ -x "$hook_script" ]] || return 1

    if [[ -f "$settings_file" ]] && grep -q "claude-post-compact-reminder" "$settings_file" 2>/dev/null; then
        return 0
    fi

    if [[ -f "$alt_settings_file" ]] && grep -q "claude-post-compact-reminder" "$alt_settings_file" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Some stack tools are only "ready" when their managed service or config is in place.
_stack_tool_ready() {
    local tool="$1"

    case "$tool" in
        mcp_agent_mail)
            _stack_is_installed "$tool" && _stack_agent_mail_ready
            ;;
        pcr)
            _stack_pcr_installed
            ;;
        *)
            _stack_is_installed "$tool"
            ;;
    esac
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
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local target_dir="$target_home/mcp_agent_mail"

    if _stack_tool_ready "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed and healthy"
        return 0
    fi

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed; ensuring managed service"
    else
        log_detail "Installing ${STACK_NAMES[$tool]}..."
        if ! _stack_run_installer "$tool" --dest "$target_dir" --yes --no-start; then
            log_warn "${STACK_NAMES[$tool]} installation may have failed"
            return 1
        fi
    fi

    if ! _stack_is_installed "$tool"; then
        log_warn "${STACK_NAMES[$tool]} CLI missing after install"
        return 1
    fi

    if ! _stack_configure_agent_mail_service; then
        log_warn "${STACK_NAMES[$tool]} installed but managed service setup failed"
        return 1
    fi

    if ! _stack_wait_for_agent_mail_health; then
        log_warn "${STACK_NAMES[$tool]} installed but service did not become healthy on http://127.0.0.1:8765"
        return 1
    fi

    log_success "${STACK_NAMES[$tool]} installed and running on http://127.0.0.1:8765"
    return 0
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
    local -a args=(--easy-mode)
    if ! _stack_is_interactive; then
        args+=(--yes)
    fi

    if _stack_run_installer "$tool" "${args[@]}"; then
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
    if _stack_run_installer "$tool" --easy-mode --verify; then
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
    if _stack_run_installer "$tool" --easy-mode --verify; then
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

# Install RU (Repo Updater)
# Multi-repo sync + AI automation
install_ru() {
    local tool="ru"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    # RU uses an environment variable, not CLI flags, for unattended install.
    if _stack_run_verified_installer_with_env "$tool" "RU_NON_INTERACTIVE=1"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install DCG (Destructive Command Guard)
# Blocks dangerous commands
install_dcg() {
    local tool="dcg"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    # DCG uses --easy-mode
    local -a args=(--easy-mode)
    if ! _stack_is_interactive; then
        args+=(--yes)
    fi

    if _stack_run_installer "$tool" "${args[@]}"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            
            # Register hook if Claude Code is present
            if _stack_command_exists claude; then
                log_detail "Registering DCG hook..."
                _stack_run_as_user "dcg install --force" || log_warn "Failed to register DCG hook"
            fi
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install RCH (Remote Compilation Helper)
# Build offloading daemon
install_rch() {
    local tool="rch"

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

# Install PT (Process Triage)
# Bayesian process cleanup
install_pt() {
    local tool="pt"

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

# Install Frankensearch (fsfs)
# Hybrid search engine
install_fsfs() {
    local tool="fsfs"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_verified_installer "$tool" --easy-mode; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install SBH (Storage Ballast Helper)
# Disk pressure defense daemon
install_sbh() {
    local tool="sbh"

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

# Install CASR (Cross-Agent Session Resumer)
# Cross-provider session handoff
install_casr() {
    local tool="casr"

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

# Install DSR (Doodlestein Self-Releaser)
# Fallback release infrastructure
install_dsr() {
    local tool="dsr"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_verified_installer "$tool" --easy-mode; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install ASB (Agent Settings Backup)
# Agent config backup tool
install_asb() {
    local tool="asb"

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

# Install PCR (Post-Compact Reminder)
# Claude Code hook for AGENTS.md re-read after compaction
install_pcr() {
    local tool="pcr"
    if _stack_pcr_installed; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    if ! _stack_command_exists claude; then
        log_detail "Skipping ${STACK_NAMES[$tool]} because Claude Code is not installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_installer "$tool" --yes; then
        if _stack_pcr_installed; then
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

    for tool in ntm mcp_agent_mail ubs bv cass cm caam slb ru dcg rch pt fsfs sbh casr dsr asb pcr; do
        local cmd="${STACK_COMMANDS[$tool]}"
        local name="${STACK_NAMES[$tool]}"

        if _stack_tool_ready "$tool"; then
            log_detail "  $cmd: installed"
            ((installed_count += 1))
        else
            log_warn "  Not ready: $cmd ($name)"
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

    for tool in ntm mcp_agent_mail ubs bv cass cm caam slb ru dcg rch pt fsfs sbh casr dsr asb pcr; do
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

    for tool in ntm mcp_agent_mail ubs bv cass cm caam slb ru dcg rch pt fsfs sbh casr dsr asb pcr; do
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

    # Install in recommended order (original 10 tools)
    install_ntm
    install_mcp_agent_mail
    install_ubs
    install_bv
    install_cass
    install_cm
    install_caam
    install_slb
    install_ru
    install_dcg

    # Additional tools (9 new integrations)
    install_rch
    install_pt
    install_fsfs
    install_sbh
    install_casr
    install_dsr
    install_asb
    install_pcr

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
