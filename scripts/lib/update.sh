#!/usr/bin/env bash
# ============================================================
# ACFS Update - Update All Components
# Updates system packages, agents, cloud CLIs, and stack tools
# ============================================================

set -euo pipefail

# Prevent interactive prompts during apt operations
export DEBIAN_FRONTEND=noninteractive

ACFS_VERSION="${ACFS_VERSION:-0.1.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/../../VERSION" ]]; then
    ACFS_VERSION="$(cat "$SCRIPT_DIR/../../VERSION" 2>/dev/null || echo "$ACFS_VERSION")"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Counters
SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

# Flags
UPDATE_APT=true
UPDATE_AGENTS=true
UPDATE_CLOUD=true
UPDATE_RUNTIME=true
UPDATE_STACK=false
UPDATE_SHELL=true
FORCE_MODE=false
DRY_RUN=false
VERBOSE=false
QUIET=false
YES_MODE=false
ABORT_ON_FAILURE=false
REBOOT_REQUIRED=false

# Logging
UPDATE_LOG_DIR="${HOME}/.acfs/logs/updates"
UPDATE_LOG_FILE=""

# Version tracking
declare -gA VERSION_BEFORE=()
declare -gA VERSION_AFTER=()

# ============================================================
# Path Setup
# ============================================================

ensure_path() {
    local dir
    local to_add=()

    for dir in \
        "$HOME/.local/bin" \
        "$HOME/.bun/bin" \
        "$HOME/.cargo/bin" \
        "$HOME/go/bin" \
        "$HOME/.atuin/bin"; do
        [[ -d "$dir" ]] || continue
        case ":$PATH:" in
            *":$dir:"*) ;;
            *) to_add+=("$dir") ;;
        esac
    done

    if [[ ${#to_add[@]} -gt 0 ]]; then
        local prefix
        prefix=$(IFS=:; echo "${to_add[*]}")
        export PATH="${prefix}:$PATH"
    fi
}

# ============================================================
# Logging Infrastructure
# ============================================================

init_logging() {
    mkdir -p "$UPDATE_LOG_DIR"
    UPDATE_LOG_FILE="$UPDATE_LOG_DIR/$(date '+%Y-%m-%d-%H%M%S').log"

    # Write log header
    {
        echo "==============================================="
        echo "ACFS Update Log"
        echo "Started: $(date -Iseconds)"
        echo "User: $(whoami)"
        echo "Version: $ACFS_VERSION"
        echo "==============================================="
        echo ""
    } >> "$UPDATE_LOG_FILE"
}

log_to_file() {
    local msg="$1"
    if [[ -n "$UPDATE_LOG_FILE" ]]; then
        echo "[$(date '+%H:%M:%S')] $msg" >> "$UPDATE_LOG_FILE"
    fi
}

# ============================================================
# Version Detection
# ============================================================

get_version() {
    local tool="$1"
    local version=""

    case "$tool" in
        bun)
            version=$("$HOME/.bun/bin/bun" --version 2>/dev/null || echo "unknown")
            ;;
        rust)
            version=$("$HOME/.cargo/bin/rustc" --version 2>/dev/null | awk '{print $2}' || echo "unknown")
            ;;
        uv)
            version=$("$HOME/.local/bin/uv" --version 2>/dev/null | awk '{print $2}' || echo "unknown")
            ;;
        claude)
            version=$(claude --version 2>/dev/null | head -1 || echo "unknown")
            ;;
        codex)
            version=$(codex --version 2>/dev/null || echo "unknown")
            ;;
        gemini)
            version=$(gemini --version 2>/dev/null || echo "unknown")
            ;;
        wrangler)
            version=$(wrangler --version 2>/dev/null || echo "unknown")
            ;;
        supabase)
            version=$(supabase --version 2>/dev/null || echo "unknown")
            ;;
        convex)
            version=$(convex --version 2>/dev/null || echo "unknown")
            ;;
        vercel)
            version=$(vercel --version 2>/dev/null || echo "unknown")
            ;;
        ntm|ubs|bv|cass|cm|caam|slb)
            version=$("$tool" --version 2>/dev/null | head -1 || echo "unknown")
            ;;
        atuin)
            version=$(atuin --version 2>/dev/null | awk '{print $2}' || echo "unknown")
            ;;
        zoxide)
            version=$(zoxide --version 2>/dev/null | awk '{print $2}' || echo "unknown")
            ;;
        omz)
            # OMZ version from .oh-my-zsh git tag or commit
            local omz_dir="${ZSH:-$HOME/.oh-my-zsh}"
            if [[ -d "$omz_dir/.git" ]]; then
                version=$(git -C "$omz_dir" describe --tags --abbrev=0 2>/dev/null || \
                          git -C "$omz_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
            else
                version="unknown"
            fi
            ;;
        p10k)
            # P10K version from git tag or commit
            local p10k_dir="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/themes/powerlevel10k"
            if [[ -d "$p10k_dir/.git" ]]; then
                version=$(git -C "$p10k_dir" describe --tags --abbrev=0 2>/dev/null || \
                          git -C "$p10k_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
            else
                version="unknown"
            fi
            ;;
        *)
            version="unknown"
            ;;
    esac

    echo "$version"
}

capture_version_before() {
    local tool="$1"
    VERSION_BEFORE["$tool"]=$(get_version "$tool")
    log_to_file "Version before [$tool]: ${VERSION_BEFORE[$tool]}"
}

capture_version_after() {
    local tool="$1"
    VERSION_AFTER["$tool"]=$(get_version "$tool")
    log_to_file "Version after [$tool]: ${VERSION_AFTER[$tool]}"

    local before="${VERSION_BEFORE[$tool]:-unknown}"
    local after="${VERSION_AFTER[$tool]}"

    if [[ "$before" != "$after" ]]; then
        log_to_file "Updated [$tool]: $before -> $after"
        return 0
    fi
    return 1
}

# ============================================================
# Helper Functions
# ============================================================

log_section() {
    log_to_file "=== $1 ==="
    if [[ "$QUIET" != "true" ]]; then
        echo ""
        echo -e "${BOLD}${CYAN}$1${NC}"
        echo "------------------------------------------------------------"
    fi
}

log_item() {
    local status="$1"
    local msg="$2"
    local details="${3:-}"

    log_to_file "[$status] $msg${details:+ - $details}"

    case "$status" in
        ok)
            [[ "$QUIET" != "true" ]] && echo -e "  ${GREEN}[ok]${NC} $msg"
            [[ -n "$details" && "$VERBOSE" == "true" && "$QUIET" != "true" ]] && echo -e "       ${DIM}$details${NC}"
            ((SUCCESS_COUNT += 1))
            ;;
        skip)
            [[ "$QUIET" != "true" ]] && echo -e "  ${DIM}[skip]${NC} $msg"
            [[ -n "$details" && "$QUIET" != "true" ]] && echo -e "       ${DIM}$details${NC}"
            ((SKIP_COUNT += 1))
            ;;
        fail)
            # Always show failures even in quiet mode
            echo -e "  ${RED}[fail]${NC} $msg"
            [[ -n "$details" ]] && echo -e "       ${DIM}$details${NC}"
            ((FAIL_COUNT += 1))
            ;;
        run)
            [[ "$QUIET" != "true" ]] && echo -e "  ${YELLOW}[...]${NC} $msg"
            ;;
        warn)
            [[ "$QUIET" != "true" ]] && echo -e "  ${YELLOW}[warn]${NC} $msg"
            [[ -n "$details" && "$QUIET" != "true" ]] && echo -e "       ${DIM}$details${NC}"
            ;;
    esac
}

run_cmd() {
    local desc="$1"
    shift
    local cmd_display=""
    cmd_display=$(printf '%q ' "$@")

    log_to_file "Running: $cmd_display"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_item "skip" "$desc" "dry-run: $cmd_display"
        return 0
    fi

    log_item "run" "$desc"

    local output=""
    local exit_code=0
    output=$("$@" 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        # Move cursor up and overwrite (only if not in quiet mode)
        if [[ "$QUIET" != "true" ]]; then
            echo -e "\033[1A\033[2K  ${GREEN}[ok]${NC} $desc"
        fi
        log_to_file "Success: $desc"
        [[ -n "$output" ]] && log_to_file "Output: $output"
        ((SUCCESS_COUNT += 1))
        return 0
    else
        if [[ "$QUIET" != "true" ]]; then
            echo -e "\033[1A\033[2K  ${RED}[fail]${NC} $desc"
        else
            echo -e "  ${RED}[fail]${NC} $desc"
        fi
        log_to_file "Failed: $desc (exit code: $exit_code)"
        [[ -n "$output" ]] && log_to_file "Output: $output"
        ((FAIL_COUNT += 1))

        # Handle abort-on-failure
        if [[ "$ABORT_ON_FAILURE" == "true" ]]; then
            echo -e "${RED}Aborting due to failure (--abort-on-failure)${NC}"
            log_to_file "ABORT: Stopping due to --abort-on-failure"
            exit 1
        fi
        return 0
    fi
}

# Check if command exists
cmd_exists() {
    command -v "$1" &>/dev/null
}

# Get sudo (empty if already root)
get_sudo() {
    if [[ $EUID -eq 0 ]]; then
        echo ""
    else
        echo "sudo"
    fi
}

run_cmd_sudo() {
    local desc="$1"
    shift

    local sudo_cmd
    sudo_cmd=$(get_sudo)
    if [[ -n "$sudo_cmd" ]]; then
        run_cmd "$desc" "$sudo_cmd" "$@"
        return 0
    fi
    run_cmd "$desc" "$@"
}

# ============================================================
# Upstream installer verification (checksums.yaml)
# ============================================================

UPDATE_SECURITY_READY=false
update_require_security() {
    if [[ "${UPDATE_SECURITY_READY}" == "true" ]]; then
        return 0
    fi

    if [[ ! -f "$SCRIPT_DIR/security.sh" ]]; then
        return 1
    fi

    # shellcheck source=security.sh
    # shellcheck disable=SC1091  # runtime relative source
    source "$SCRIPT_DIR/security.sh"
    load_checksums || return 1

    UPDATE_SECURITY_READY=true
    return 0
}

# shellcheck disable=SC2317,SC2329  # invoked indirectly via run_cmd()
update_run_verified_installer() {
    local tool="$1"
    shift || true

    if ! update_require_security; then
        echo "Security verification unavailable (missing $SCRIPT_DIR/security.sh or checksums.yaml)" >&2
        return 1
    fi

    local url="${KNOWN_INSTALLERS[$tool]:-}"
    local expected_sha256
    expected_sha256="$(get_checksum "$tool")"

    if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then
        echo "Missing checksum entry for $tool" >&2
        return 1
    fi

    verify_checksum "$url" "$expected_sha256" "$tool" | bash -s -- "$@"
}

# ============================================================
# Update Functions
# ============================================================

update_apt() {
    log_section "System Packages (apt)"

    if [[ "$UPDATE_APT" != "true" ]]; then
        log_item "skip" "apt update" "disabled via --no-apt"
        return 0
    fi

    # Check if apt/dpkg is available (Linux only)
    if ! command -v apt-get &>/dev/null; then
        log_item "skip" "apt" "not available (non-Debian system)"
        return 0
    fi

    # Check for apt lock
    if ! check_apt_lock; then
        return 0
    fi

    # Run apt update
    run_cmd_sudo "apt update" apt-get update -y

    # Get list of upgradable packages before upgrade
    local upgradable_list=""
    local upgrade_count=0
    if upgradable_list=$(apt list --upgradable 2>/dev/null | grep -v "^Listing"); then
        upgrade_count=$(echo "$upgradable_list" | grep -c . || echo 0)
        if [[ $upgrade_count -gt 0 ]]; then
            log_to_file "Upgradable packages ($upgrade_count):"
            log_to_file "$upgradable_list"
        fi
    fi

    if [[ $upgrade_count -eq 0 ]]; then
        log_item "ok" "apt upgrade" "all packages up to date"
    else
        log_to_file "Upgrading $upgrade_count packages..."
        run_cmd_sudo "apt upgrade ($upgrade_count packages)" apt-get upgrade -y
    fi

    run_cmd_sudo "apt autoremove" apt-get autoremove -y

    # Check if reboot is required (kernel updates, etc.)
    check_reboot_required
}

# Check if apt is locked by another process
check_apt_lock() {
    # Check for dpkg lock
    if [[ -f /var/lib/dpkg/lock-frontend ]]; then
        if fuser /var/lib/dpkg/lock-frontend &>/dev/null 2>&1; then
            log_item "fail" "apt locked" "dpkg lock held by another process"
            log_to_file "APT lock detected: /var/lib/dpkg/lock-frontend in use"
            if [[ "$ABORT_ON_FAILURE" == "true" ]]; then
                echo -e "${RED}Aborting: apt is locked by another process${NC}"
                echo "Try: sudo killall apt apt-get dpkg  (use with caution)"
                exit 1
            fi
            return 1
        fi
    fi

    # Check for apt/apt-get processes
    if pgrep -x 'apt' &>/dev/null || pgrep -x 'apt-get' &>/dev/null || pgrep -x 'dpkg' &>/dev/null; then
        log_item "fail" "apt locked" "apt/dpkg process running"
        log_to_file "APT lock detected: apt/dpkg process already running"
        if [[ "$ABORT_ON_FAILURE" == "true" ]]; then
            echo -e "${RED}Aborting: another apt process is running${NC}"
            exit 1
        fi
        return 1
    fi

    # Check for unattended-upgrades
    if pgrep -x "unattended-upgr" &>/dev/null; then
        log_item "skip" "apt" "unattended-upgrades running, will retry later"
        log_to_file "Skipping apt: unattended-upgrades in progress"
        return 1
    fi

    return 0
}

# Check if system reboot is required after updates
check_reboot_required() {
    if [[ -f /var/run/reboot-required ]]; then
        log_item "warn" "Reboot required" "kernel or critical package updated"
        log_to_file "REBOOT REQUIRED: /var/run/reboot-required exists"

        if [[ -f /var/run/reboot-required.pkgs ]]; then
            local pkgs
            pkgs=$(cat /var/run/reboot-required.pkgs 2>/dev/null || echo "unknown")
            log_to_file "Packages requiring reboot: $pkgs"
            if [[ "$QUIET" != "true" ]]; then
                echo -e "       ${DIM}Packages: $pkgs${NC}"
            fi
        fi

        # Set a global flag for summary
        REBOOT_REQUIRED=true
    fi
}

update_bun() {
    log_section "Bun Runtime"

    if [[ "$UPDATE_RUNTIME" != "true" ]]; then
        log_item "skip" "Bun" "disabled via --no-runtime / category selection"
        return 0
    fi

    local bun_bin="$HOME/.bun/bin/bun"

    if [[ ! -x "$bun_bin" ]]; then
        log_item "skip" "Bun" "not installed"
        return 0
    fi

    # Capture version before update
    capture_version_before "bun"

    run_cmd "Bun self-upgrade" "$bun_bin" upgrade

    # Capture version after and log if changed (don't use log_item "ok" to avoid double-counting)
    if capture_version_after "bun"; then
        [[ "$QUIET" != "true" ]] && echo -e "       ${DIM}${VERSION_BEFORE[bun]} → ${VERSION_AFTER[bun]}${NC}"
    fi
}

update_agents() {
    log_section "Coding Agents"

    if [[ "$UPDATE_AGENTS" != "true" ]]; then
        log_item "skip" "agents update" "disabled via --no-agents"
        return 0
    fi

    local bun_bin="$HOME/.bun/bin/bun"

    if [[ ! -x "$bun_bin" ]]; then
        log_item "fail" "Bun not installed" "required for agent updates"
        return 0
    fi

    # Claude Code - has native update with fallback to reinstall
    if cmd_exists claude; then
        capture_version_before "claude"

        # Try native update first
        if ! run_cmd_claude_update; then
            log_to_file "Claude update failed, attempting reinstall via official installer"
            if update_require_security; then
                run_cmd "Claude Code (reinstall)" update_run_verified_installer claude
            else
                log_item "fail" "Claude Code" "update failed and reinstall unavailable (missing security.sh)"
            fi
        fi

        # Show version change without double-counting (run_cmd already incremented SUCCESS_COUNT)
        if capture_version_after "claude"; then
            [[ "$QUIET" != "true" ]] && echo -e "       ${DIM}${VERSION_BEFORE[claude]} → ${VERSION_AFTER[claude]}${NC}"
        fi
    else
        log_item "skip" "Claude Code" "not installed"
    fi

    # Codex CLI via bun (--trust allows postinstall scripts)
    if cmd_exists codex || [[ "$FORCE_MODE" == "true" ]]; then
        capture_version_before "codex"
        run_cmd "Codex CLI" "$bun_bin" install -g --trust @openai/codex@latest
        # Show version change without double-counting
        if capture_version_after "codex"; then
            [[ "$QUIET" != "true" ]] && echo -e "       ${DIM}${VERSION_BEFORE[codex]} → ${VERSION_AFTER[codex]}${NC}"
        fi
    else
        log_item "skip" "Codex CLI" "not installed (use --force to install)"
    fi

    # Gemini CLI via bun (--trust allows postinstall scripts)
    if cmd_exists gemini || [[ "$FORCE_MODE" == "true" ]]; then
        capture_version_before "gemini"
        run_cmd "Gemini CLI" "$bun_bin" install -g --trust @google/gemini-cli@latest
        # Show version change without double-counting
        if capture_version_after "gemini"; then
            [[ "$QUIET" != "true" ]] && echo -e "       ${DIM}${VERSION_BEFORE[gemini]} → ${VERSION_AFTER[gemini]}${NC}"
        fi
    else
        log_item "skip" "Gemini CLI" "not installed (use --force to install)"
    fi
}

# Helper for Claude update with proper error handling
run_cmd_claude_update() {
    local desc="Claude Code (native update)"
    local cmd_display="claude update"

    log_to_file "Running: $cmd_display"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_item "skip" "$desc" "dry-run: $cmd_display"
        return 0
    fi

    log_item "run" "$desc"

    local output=""
    local exit_code=0
    output=$(claude update 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        if [[ "$QUIET" != "true" ]]; then
            echo -e "\033[1A\033[2K  ${GREEN}[ok]${NC} $desc"
        fi
        log_to_file "Success: $desc"
        [[ -n "$output" ]] && log_to_file "Output: $output"
        ((SUCCESS_COUNT += 1))
        return 0
    else
        if [[ "$QUIET" != "true" ]]; then
            echo -e "\033[1A\033[2K  ${YELLOW}[retry]${NC} $desc"
        fi
        log_to_file "Failed: $desc (exit code: $exit_code), will try reinstall"
        [[ -n "$output" ]] && log_to_file "Output: $output"
        return 1
    fi
}

update_cloud() {
    log_section "Cloud CLIs"

    if [[ "$UPDATE_CLOUD" != "true" ]]; then
        log_item "skip" "cloud CLIs update" "disabled via --no-cloud"
        return 0
    fi

    local bun_bin="$HOME/.bun/bin/bun"

    if [[ ! -x "$bun_bin" ]]; then
        log_item "fail" "Bun not installed" "required for cloud CLI updates"
        return 0
    fi

    # Wrangler (--trust allows postinstall scripts for native binaries)
    if cmd_exists wrangler || [[ "$FORCE_MODE" == "true" ]]; then
        run_cmd "Wrangler (Cloudflare)" "$bun_bin" install -g --trust wrangler@latest
    else
        log_item "skip" "Wrangler" "not installed"
    fi

    # Supabase (--trust allows postinstall scripts for native binaries)
    if cmd_exists supabase || [[ "$FORCE_MODE" == "true" ]]; then
        run_cmd "Supabase CLI" "$bun_bin" install -g --trust supabase@latest
    else
        log_item "skip" "Supabase CLI" "not installed"
    fi

    # Convex
    if cmd_exists convex || [[ "$FORCE_MODE" == "true" ]]; then
        run_cmd "Convex CLI" "$bun_bin" install -g --trust convex@latest
    else
        log_item "skip" "Convex CLI" "not installed"
    fi

    # Vercel (--trust allows postinstall scripts for native binaries)
    if cmd_exists vercel || [[ "$FORCE_MODE" == "true" ]]; then
        run_cmd "Vercel CLI" "$bun_bin" install -g --trust vercel@latest
    else
        log_item "skip" "Vercel CLI" "not installed"
    fi
}

update_rust() {
    log_section "Rust Toolchain"

    if [[ "$UPDATE_RUNTIME" != "true" ]]; then
        log_item "skip" "Rust" "disabled via --no-runtime / category selection"
        return 0
    fi

    local rustup_bin="$HOME/.cargo/bin/rustup"

    if [[ ! -x "$rustup_bin" ]]; then
        log_item "skip" "Rust" "not installed"
        return 0
    fi

    # Capture version before update
    capture_version_before "rust"

    # Update stable toolchain
    run_cmd "Rust stable" "$rustup_bin" update stable

    # Check if nightly is installed and update it too
    if "$rustup_bin" toolchain list 2>/dev/null | grep -q "^nightly"; then
        run_cmd "Rust nightly" "$rustup_bin" update nightly
    fi

    # Update rustup itself
    run_cmd "rustup self-update" "$rustup_bin" self update

    # Show version change without double-counting
    if capture_version_after "rust"; then
        [[ "$QUIET" != "true" ]] && echo -e "       ${DIM}${VERSION_BEFORE[rust]} → ${VERSION_AFTER[rust]}${NC}"
    fi

    # Log installed toolchains
    local toolchains
    toolchains=$("$rustup_bin" toolchain list 2>/dev/null | tr '\n' ', ' | sed 's/, $//')
    log_to_file "Installed toolchains: $toolchains"
}

update_uv() {
    log_section "Python Tools (uv)"

    if [[ "$UPDATE_RUNTIME" != "true" ]]; then
        log_item "skip" "uv" "disabled via --no-runtime / category selection"
        return 0
    fi

    local uv_bin="$HOME/.local/bin/uv"

    if [[ ! -x "$uv_bin" ]]; then
        log_item "skip" "uv" "not installed"
        return 0
    fi

    # Capture version before update
    capture_version_before "uv"

    run_cmd "uv self-update" "$uv_bin" self update

    # Show version change without double-counting
    if capture_version_after "uv"; then
        [[ "$QUIET" != "true" ]] && echo -e "       ${DIM}${VERSION_BEFORE[uv]} → ${VERSION_AFTER[uv]}${NC}"
    fi
}

update_go() {
    log_section "Go Runtime"

    if [[ "$UPDATE_RUNTIME" != "true" ]]; then
        log_item "skip" "Go" "disabled via --no-runtime / category selection"
        return 0
    fi

    # Check if go is installed
    if ! command -v go &>/dev/null; then
        log_item "skip" "Go" "not installed"
        return 0
    fi

    # Determine how Go was installed
    local go_path
    go_path=$(command -v go 2>/dev/null || true)

    # Check if it's apt-managed (system install)
    if [[ "$go_path" == "/usr/bin/go" ]] || [[ "$go_path" == "/usr/local/go/bin/go" ]]; then
        # System install - apt handles it, or manual install
        if dpkg -l golang-go &>/dev/null 2>&1; then
            log_item "ok" "Go" "apt-managed (updated via apt upgrade)"
            log_to_file "Go is managed by apt, skipping dedicated update"
        else
            log_item "skip" "Go" "manual install, update manually from golang.org"
            log_to_file "Go appears to be manually installed at $go_path"
        fi
        return 0
    fi

    # Check for goenv or similar version managers
    if [[ -d "$HOME/.goenv" ]]; then
        log_item "skip" "Go" "managed by goenv, use goenv to update"
        return 0
    fi

    # For other installations, just log the version
    local go_version
    go_version=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//')
    log_item "ok" "Go $go_version" "no auto-update available"
    log_to_file "Go version: $go_version (path: $go_path)"
}

update_stack() {
    log_section "Dicklesworthstone Stack"

    if [[ "$UPDATE_STACK" != "true" ]]; then
        log_item "skip" "stack update" "disabled (use --stack to enable)"
        return 0
    fi

    if ! update_require_security; then
        log_item "fail" "stack updates" "security verification unavailable (missing security.sh/checksums.yaml)"
        return 0
    fi

    # NTM
    if cmd_exists ntm; then
        run_cmd "NTM" update_run_verified_installer ntm
    fi

    # MCP Agent Mail - Special handling for tmux (server blocks)
    # Note: Version tracking not possible for async tmux updates
    if cmd_exists "am" || [[ -d "$HOME/mcp_agent_mail" ]]; then
        if cmd_exists tmux; then
            local tool="mcp_agent_mail"
            local url="${KNOWN_INSTALLERS[$tool]:-}"
            local expected_sha256
            expected_sha256="$(get_checksum "$tool")"

            if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                # Fetch and verify content first
                local tmp_install
                tmp_install=$(mktemp "${TMPDIR:-/tmp}/acfs-install-am.XXXXXX")

                if verify_checksum "$url" "$expected_sha256" "$tool" > "$tmp_install"; then
                    chmod +x "$tmp_install"

                    local tmux_session="acfs-services"
                    # Kill old session if exists
                    tmux kill-session -t "$tmux_session" 2>/dev/null || true

                    # Launch in tmux (tmux does not split a single string into argv)
                    if run_cmd "MCP Agent Mail (tmux)" tmux new-session -d -s "$tmux_session" "$tmp_install" --dir "$HOME/mcp_agent_mail" --yes; then
                        log_to_file "Started MCP Agent Mail update in tmux session: $tmux_session"
                        [[ "$QUIET" != "true" ]] && echo -e "       ${DIM}Update running in tmux session '$tmux_session'${NC}"
                    fi

                    # Cleanup happens when system tmp is cleaned
                else
                    rm -f "$tmp_install"
                    log_item "fail" "MCP Agent Mail" "verification failed"
                fi
            else
                log_item "fail" "MCP Agent Mail" "unknown installer URL/checksum"
            fi
        else
            log_item "skip" "MCP Agent Mail" "tmux not found (required for update)"
        fi
    fi

    # UBS
    if cmd_exists ubs; then
        run_cmd "Ultimate Bug Scanner" update_run_verified_installer ubs --easy-mode
    fi

    # Beads Viewer
    if cmd_exists bv; then
        run_cmd "Beads Viewer" update_run_verified_installer bv
    fi

    # CASS
    if cmd_exists cass; then
        run_cmd "CASS" update_run_verified_installer cass --easy-mode --verify
    fi

    # CASS Memory
    if cmd_exists cm; then
        run_cmd "CASS Memory" update_run_verified_installer cm --easy-mode --verify
    fi

    # CAAM
    if cmd_exists caam; then
        run_cmd "CAAM" update_run_verified_installer caam
    fi

    # SLB
    if cmd_exists slb; then
        run_cmd "SLB" update_run_verified_installer slb
    fi
}

# ============================================================
# Shell Tool Updates
# Related: bead db0
# ============================================================

# Update Oh-My-Zsh via its built-in upgrade script
update_omz() {
    local omz_dir="${ZSH:-$HOME/.oh-my-zsh}"

    if [[ ! -d "$omz_dir" ]]; then
        log_item "skip" "Oh-My-Zsh" "not installed"
        return 0
    fi

    capture_version_before "omz"

    # OMZ has its own upgrade script that handles everything
    # Set DISABLE_UPDATE_PROMPT to avoid interactive prompts
    local upgrade_script="$omz_dir/tools/upgrade.sh"
    if [[ -x "$upgrade_script" ]]; then
        run_cmd "Oh-My-Zsh upgrade" env DISABLE_UPDATE_PROMPT=true ZSH="$omz_dir" "$upgrade_script"
    elif [[ -f "$upgrade_script" ]]; then
        run_cmd "Oh-My-Zsh upgrade" env DISABLE_UPDATE_PROMPT=true ZSH="$omz_dir" bash "$upgrade_script"
    else
        # Fallback to git pull
        if [[ -d "$omz_dir/.git" ]]; then
            run_cmd "Oh-My-Zsh (git pull)" git -C "$omz_dir" pull --ff-only
        else
            log_item "skip" "Oh-My-Zsh" "no upgrade mechanism found"
            return 0
        fi
    fi

    # Show version change without double-counting
    if capture_version_after "omz"; then
        [[ "$QUIET" != "true" ]] && echo -e "       ${DIM}${VERSION_BEFORE[omz]} → ${VERSION_AFTER[omz]}${NC}"
    fi
}

# Update Powerlevel10k theme via git
update_p10k() {
    local p10k_dir="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/themes/powerlevel10k"

    if [[ ! -d "$p10k_dir" ]]; then
        log_item "skip" "Powerlevel10k" "not installed"
        return 0
    fi

    if [[ ! -d "$p10k_dir/.git" ]]; then
        log_item "skip" "Powerlevel10k" "not a git repo"
        return 0
    fi

    capture_version_before "p10k"

    # Use --ff-only to avoid merge conflicts
    local output=""
    local exit_code=0
    output=$(git -C "$p10k_dir" pull --ff-only 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        if capture_version_after "p10k"; then
            log_item "ok" "Powerlevel10k updated" "${VERSION_BEFORE[p10k]} → ${VERSION_AFTER[p10k]}"
        else
            log_item "ok" "Powerlevel10k" "already up to date"
        fi
    else
        # Check if it's a ff-only failure (local changes)
        if echo "$output" | grep -q "fatal.*not possible to fast-forward"; then
            log_item "skip" "Powerlevel10k" "local changes detected, manual merge required"
            log_to_file "P10K update failed: $output"
        else
            log_item "fail" "Powerlevel10k" "git pull failed"
            log_to_file "P10K update failed: $output"
            # Note: log_item "fail" already increments FAIL_COUNT
        fi
    fi
}

# Update zsh plugins via git
update_zsh_plugins() {
    local zsh_custom="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}"
    local plugins_dir="$zsh_custom/plugins"

    # Known plugins to update
    local -a plugins=(
        "zsh-autosuggestions"
        "zsh-syntax-highlighting"
        "zsh-completions"
        "zsh-history-substring-search"
    )

    local updated=0
    local skipped=0

    for plugin in "${plugins[@]}"; do
        local plugin_dir="$plugins_dir/$plugin"

        if [[ ! -d "$plugin_dir" ]]; then
            continue
        fi

        if [[ ! -d "$plugin_dir/.git" ]]; then
            log_item "warn" "$plugin" "not a git repo (skipped)"
            log_to_file "Plugin $plugin exists but is not a git repo"
            continue
        fi

        local output=""
        local exit_code=0
        output=$(git -C "$plugin_dir" pull --ff-only 2>&1) || exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            if ! echo "$output" | grep -q "Already up to date"; then
                log_item "ok" "$plugin" "updated"
                ((updated += 1))
            else
                ((skipped += 1))
            fi
        else
            if echo "$output" | grep -q "fatal.*not possible to fast-forward"; then
                log_item "skip" "$plugin" "local changes"
            else
                log_item "fail" "$plugin" "git pull failed"
                log_to_file "$plugin update failed: $output"
            fi
        fi
    done

    if [[ $updated -eq 0 && $skipped -gt 0 ]]; then
        log_item "ok" "zsh plugins" "$skipped plugins already up to date"
    elif [[ $updated -eq 0 && $skipped -eq 0 ]]; then
        log_item "skip" "zsh plugins" "no plugins installed"
    fi
}

# Update Atuin - try self-update first, fallback to installer
update_atuin() {
    if ! cmd_exists atuin; then
        log_item "skip" "Atuin" "not installed"
        return 0
    fi

    capture_version_before "atuin"

    # Try atuin self-update first (available in newer versions)
    if atuin --help 2>&1 | grep -q "self-update"; then
        run_cmd "Atuin self-update" atuin self-update
    else
        # Fallback to reinstall via official installer with checksum verification
        if update_require_security; then
            run_cmd "Atuin (reinstall)" update_run_verified_installer atuin
        else
            # Last resort: no checksum verification available
            if [[ "$YES_MODE" == "true" ]]; then
                log_item "skip" "Atuin" "checksum verification unavailable, use --force to bypass"
            else
                log_item "skip" "Atuin" "no self-update command, manual update recommended"
                log_to_file "Atuin update: install newer version with: curl -fsSL https://setup.atuin.sh | bash"
            fi
            return 0
        fi
    fi

    # Show version change without double-counting
    if capture_version_after "atuin"; then
        [[ "$QUIET" != "true" ]] && echo -e "       ${DIM}${VERSION_BEFORE[atuin]} → ${VERSION_AFTER[atuin]}${NC}"
    fi
}

# Update Zoxide via reinstall (checksum verified)
update_zoxide() {
    if ! cmd_exists zoxide; then
        log_item "skip" "Zoxide" "not installed"
        return 0
    fi

    capture_version_before "zoxide"

    # Zoxide doesn't have self-update, reinstall via official installer
    if update_require_security; then
        run_cmd "Zoxide (reinstall)" update_run_verified_installer zoxide
    else
        log_item "skip" "Zoxide" "checksum verification unavailable"
        log_to_file "Zoxide update: install newer version with: curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash"
        return 0
    fi

    # Show version change without double-counting
    if capture_version_after "zoxide"; then
        [[ "$QUIET" != "true" ]] && echo -e "       ${DIM}${VERSION_BEFORE[zoxide]} → ${VERSION_AFTER[zoxide]}${NC}"
    fi
}

# Main shell update dispatcher
update_shell() {
    log_section "Shell Tools"

    if [[ "$UPDATE_SHELL" != "true" ]]; then
        log_item "skip" "shell tools update" "disabled via --no-shell"
        return 0
    fi

    # Git-based updates (OMZ, P10K, plugins)
    update_omz
    update_p10k
    update_zsh_plugins

    # Installer-based updates (Atuin, Zoxide)
    update_atuin
    update_zoxide
}

# ============================================================
# Summary
# ============================================================

print_summary() {
    # Log footer to file
    if [[ -n "$UPDATE_LOG_FILE" ]]; then
        {
            echo ""
            echo "==============================================="
            echo "Summary"
            echo "==============================================="
            echo "Updated: $SUCCESS_COUNT"
            echo "Skipped: $SKIP_COUNT"
            echo "Failed:  $FAIL_COUNT"
            if [[ "$REBOOT_REQUIRED" == "true" ]]; then
                echo "Reboot:  REQUIRED"
            fi
            echo ""
            echo "Completed: $(date -Iseconds)"
            echo "==============================================="
        } >> "$UPDATE_LOG_FILE"
    fi

    # Console output (respects quiet mode for success, always shows failures)
    if [[ "$QUIET" != "true" ]]; then
        echo ""
        echo "============================================================"
        echo -e "Summary: ${GREEN}$SUCCESS_COUNT updated${NC}, ${DIM}$SKIP_COUNT skipped${NC}, ${RED}$FAIL_COUNT failed${NC}"
        echo ""

        if [[ $FAIL_COUNT -eq 0 ]]; then
            echo -e "${GREEN}All updates completed successfully!${NC}"
        else
            echo -e "${YELLOW}Some updates failed. Check output above.${NC}"
        fi

        # Reboot warning
        if [[ "$REBOOT_REQUIRED" == "true" ]]; then
            echo ""
            echo -e "${YELLOW}${BOLD}⚠ System reboot required${NC}"
            echo -e "${DIM}Run: sudo reboot${NC}"
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            echo ""
            echo -e "${DIM}(dry-run mode - no changes were made)${NC}"
        fi

        # Show log location
        if [[ -n "$UPDATE_LOG_FILE" ]]; then
            echo ""
            echo -e "${DIM}Log: $UPDATE_LOG_FILE${NC}"
        fi
    elif [[ $FAIL_COUNT -gt 0 ]]; then
        # In quiet mode, still report failures
        echo ""
        echo -e "${RED}Update failed: $FAIL_COUNT error(s)${NC}"
        if [[ -n "$UPDATE_LOG_FILE" ]]; then
            echo -e "${DIM}See: $UPDATE_LOG_FILE${NC}"
        fi
    fi
}

# ============================================================
# CLI
# ============================================================

usage() {
    cat << 'EOF'
acfs update - Update all ACFS components

USAGE:
  acfs-update [options]
  acfs update [options]    (if acfs wrapper is installed)

CATEGORY OPTIONS (select what to update):
  --apt-only         Only update system packages (apt)
  --agents-only      Only update coding agents (Claude, Codex, Gemini)
  --cloud-only       Only update cloud CLIs (Wrangler, Supabase, Convex, Vercel)
  --shell-only       Only update shell tools (OMZ, P10K, plugins, Atuin, Zoxide)
  --runtime-only     Only update runtimes (Bun, Rust, uv, Go)
  --stack            Include Dicklesworthstone stack tools (default: disabled)

SKIP OPTIONS (exclude categories from update):
  --no-apt           Skip apt update/upgrade
  --no-agents        Skip coding agent updates
  --no-cloud         Skip cloud CLI updates
  --no-shell         Skip shell tool updates
  --no-runtime       Skip runtime updates (Bun, Rust, uv, Go)

BEHAVIOR OPTIONS:
  --force            Install tools that are missing (not just update existing)
  --dry-run          Preview changes without making them
  --yes, -y          Non-interactive mode, skip all prompts
  --quiet, -q        Minimal output, only show errors and summary
  --verbose, -v      Show detailed output including command details
  --abort-on-failure Stop immediately on first failure
  --continue         Continue after failures (default)
  --help, -h         Show this help message

EXAMPLES:
  # Standard update (apt, runtimes, shell, agents, cloud)
  acfs-update

  # Include Dicklesworthstone stack
  acfs-update --stack

  # Only update agents
  acfs-update --agents-only

  # Only update runtimes
  acfs-update --runtime-only

  # Update everything except apt (faster)
  acfs-update --no-apt

  # Preview what would be updated
  acfs-update --dry-run

  # Automated CI/cron mode
  acfs-update --yes --quiet

  # Strict mode: stop on first error
  acfs-update --abort-on-failure --stack

WHAT EACH CATEGORY UPDATES:
  apt:      System packages via apt update && apt upgrade
  shell:    Oh-My-Zsh, Powerlevel10k, zsh plugins (git pull)
            Atuin, Zoxide (reinstall from upstream)
  agents:   Claude Code (claude update)
            Codex CLI (bun install -g @openai/codex@latest)
            Gemini CLI (bun install -g @google/gemini-cli@latest)
  cloud:    Wrangler, Supabase CLI, Convex CLI, Vercel CLI (bun install -g @latest)
  runtime:  Bun (bun upgrade), Rust (rustup update), uv (uv self update), Go (apt-managed)
  stack:    NTM, UBS, BV, CASS, CM, CAAM, SLB (re-run upstream installers)

LOGS:
  Update logs are saved to: ~/.acfs/logs/updates/
  Log files are timestamped: YYYY-MM-DD-HHMMSS.log

  Example: tail -f ~/.acfs/logs/updates/$(ls -1t ~/.acfs/logs/updates | head -1)

ENVIRONMENT VARIABLES:
  ACFS_HOME          Base directory for ACFS (default: ~/.acfs)
  ACFS_VERSION       Override version string in logs

TROUBLESHOOTING:
  - If apt is locked: wait for other package operations or run:
    sudo rm /var/lib/dpkg/lock-frontend && sudo dpkg --configure -a

  - If an agent update fails: try running the update command directly:
    claude update
    bun install -g @openai/codex@latest

  - If shell tools fail to update: check git remote access:
    git -C ~/.oh-my-zsh remote -v

  - View recent logs:
    ls -lt ~/.acfs/logs/updates/ | head -5
    cat ~/.acfs/logs/updates/LATEST_LOG_FILE

  - Force reinstall a specific tool:
    acfs-update --force --agents-only
EOF
}

main() {
    # Guard against running as root (unless ACFS is actually installed in /root)
    if [[ $EUID -eq 0 ]] && [[ "${HOME}" != "/root" ]]; then
        echo -e "${YELLOW}Warning: Running as root but HOME is $HOME.${NC}"
        echo "ACFS update should typically be run as the target user (e.g. ubuntu)."
        if [[ "$YES_MODE" != "true" ]]; then
            read -r -p "Continue anyway? [y/N] " response
            if [[ ! "$response" =~ ^[Yy] ]]; then
                exit 1
            fi
        fi
    fi

    # Ensure PATH includes user tool directories
    ensure_path

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --apt-only)
                UPDATE_APT=true
                UPDATE_AGENTS=false
                UPDATE_CLOUD=false
                UPDATE_RUNTIME=false
                UPDATE_STACK=false
                UPDATE_SHELL=false
                shift
                ;;
            --agents-only)
                UPDATE_APT=false
                UPDATE_AGENTS=true
                UPDATE_CLOUD=false
                UPDATE_RUNTIME=false
                UPDATE_STACK=false
                UPDATE_SHELL=false
                shift
                ;;
            --cloud-only)
                UPDATE_APT=false
                UPDATE_AGENTS=false
                UPDATE_CLOUD=true
                UPDATE_RUNTIME=false
                UPDATE_STACK=false
                UPDATE_SHELL=false
                shift
                ;;
            --shell-only)
                UPDATE_APT=false
                UPDATE_AGENTS=false
                UPDATE_CLOUD=false
                UPDATE_RUNTIME=false
                UPDATE_STACK=false
                UPDATE_SHELL=true
                shift
                ;;
            --runtime-only)
                UPDATE_APT=false
                UPDATE_AGENTS=false
                UPDATE_CLOUD=false
                UPDATE_RUNTIME=true
                UPDATE_STACK=false
                UPDATE_SHELL=false
                shift
                ;;
            --stack)
                UPDATE_STACK=true
                shift
                ;;
            --no-apt)
                UPDATE_APT=false
                shift
                ;;
            --no-agents)
                UPDATE_AGENTS=false
                shift
                ;;
            --no-cloud)
                UPDATE_CLOUD=false
                shift
                ;;
            --no-shell)
                UPDATE_SHELL=false
                shift
                ;;
            --no-runtime)
                UPDATE_RUNTIME=false
                shift
                ;;
            --force)
                FORCE_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --quiet|-q)
                QUIET=true
                shift
                ;;
            --yes|-y)
                YES_MODE=true
                shift
                ;;
            --abort-on-failure)
                ABORT_ON_FAILURE=true
                shift
                ;;
            --continue)
                ABORT_ON_FAILURE=false
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Try: acfs update --help" >&2
                exit 1
                ;;
        esac
    done

    # Initialize logging
    init_logging

    # Header
    if [[ "$QUIET" != "true" ]]; then
        echo ""
        echo -e "${BOLD}ACFS Update v$ACFS_VERSION${NC}"
        echo -e "User: $(whoami)"
        echo -e "Date: $(date '+%Y-%m-%d %H:%M')"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "${YELLOW}Mode: dry-run${NC}"
        fi
    fi

    # Set non-interactive mode if --yes was passed
    if [[ "$YES_MODE" == "true" ]]; then
        export ACFS_INTERACTIVE=false
    fi

    # Run updates
    update_apt
    update_bun
    update_agents
    update_cloud
    update_rust
    update_uv
    update_go
    update_shell
    update_stack

    # Summary
    print_summary

    # Exit code
    if [[ $FAIL_COUNT -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
