#!/usr/bin/env bash
# ============================================================
# ACFS Update - Update All Components
# Updates system packages, agents, cloud CLIs, and stack tools
# ============================================================

set -euo pipefail

ACFS_VERSION="${ACFS_VERSION:-0.1.0}"

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
UPDATE_STACK=false
FORCE_MODE=false
DRY_RUN=false
VERBOSE=false

# ============================================================
# Helper Functions
# ============================================================

log_section() {
    echo ""
    echo -e "${BOLD}${CYAN}$1${NC}"
    echo "------------------------------------------------------------"
}

log_item() {
    local status="$1"
    local msg="$2"
    local details="${3:-}"

    case "$status" in
        ok)
            echo -e "  ${GREEN}[ok]${NC} $msg"
            [[ -n "$details" && "$VERBOSE" == "true" ]] && echo -e "       ${DIM}$details${NC}"
            ((SUCCESS_COUNT++))
            ;;
        skip)
            echo -e "  ${DIM}[skip]${NC} $msg"
            [[ -n "$details" ]] && echo -e "       ${DIM}$details${NC}"
            ((SKIP_COUNT++))
            ;;
        fail)
            echo -e "  ${RED}[fail]${NC} $msg"
            [[ -n "$details" ]] && echo -e "       ${DIM}$details${NC}"
            ((FAIL_COUNT++))
            ;;
        run)
            echo -e "  ${YELLOW}[...]${NC} $msg"
            ;;
    esac
}

run_cmd() {
    local desc="$1"
    shift
    local cmd="$*"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_item "skip" "$desc" "dry-run: $cmd"
        return 0
    fi

    log_item "run" "$desc"

    if eval "$cmd" >/dev/null 2>&1; then
        # Move cursor up and overwrite
        echo -e "\033[1A\033[2K  ${GREEN}[ok]${NC} $desc"
        ((SUCCESS_COUNT++))
        return 0
    else
        echo -e "\033[1A\033[2K  ${RED}[fail]${NC} $desc"
        ((FAIL_COUNT++))
        return 1
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

# ============================================================
# Update Functions
# ============================================================

update_apt() {
    log_section "System Packages (apt)"

    if [[ "$UPDATE_APT" != "true" ]]; then
        log_item "skip" "apt update" "disabled via --no-apt"
        return 0
    fi

    local sudo_cmd
    sudo_cmd=$(get_sudo)

    run_cmd "apt update" "$sudo_cmd apt-get update -y"
    run_cmd "apt upgrade" "$sudo_cmd apt-get upgrade -y"
    run_cmd "apt autoremove" "$sudo_cmd apt-get autoremove -y"
}

update_bun() {
    log_section "Bun Runtime"

    local bun_bin="$HOME/.bun/bin/bun"

    if [[ ! -x "$bun_bin" ]]; then
        log_item "skip" "Bun" "not installed"
        return 0
    fi

    run_cmd "Bun self-upgrade" "$bun_bin upgrade"
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
        return 1
    fi

    # Claude Code has its own update command
    if cmd_exists claude; then
        run_cmd "Claude Code" "claude update"
    else
        log_item "skip" "Claude Code" "not installed"
    fi

    # Codex CLI via bun
    if cmd_exists codex || [[ "$FORCE_MODE" == "true" ]]; then
        run_cmd "Codex CLI" "$bun_bin install -g @openai/codex@latest"
    else
        log_item "skip" "Codex CLI" "not installed (use --force to install)"
    fi

    # Gemini CLI via bun
    if cmd_exists gemini || [[ "$FORCE_MODE" == "true" ]]; then
        run_cmd "Gemini CLI" "$bun_bin install -g @google/gemini-cli@latest"
    else
        log_item "skip" "Gemini CLI" "not installed (use --force to install)"
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
        return 1
    fi

    # Wrangler
    if cmd_exists wrangler || [[ "$FORCE_MODE" == "true" ]]; then
        run_cmd "Wrangler (Cloudflare)" "$bun_bin install -g wrangler@latest"
    else
        log_item "skip" "Wrangler" "not installed"
    fi

    # Supabase
    if cmd_exists supabase || [[ "$FORCE_MODE" == "true" ]]; then
        run_cmd "Supabase CLI" "$bun_bin install -g supabase@latest"
    else
        log_item "skip" "Supabase CLI" "not installed"
    fi

    # Vercel
    if cmd_exists vercel || [[ "$FORCE_MODE" == "true" ]]; then
        run_cmd "Vercel CLI" "$bun_bin install -g vercel@latest"
    else
        log_item "skip" "Vercel CLI" "not installed"
    fi
}

update_rust() {
    log_section "Rust Toolchain"

    local rustup_bin="$HOME/.cargo/bin/rustup"

    if [[ ! -x "$rustup_bin" ]]; then
        log_item "skip" "Rust" "not installed"
        return 0
    fi

    run_cmd "Rust stable" "$rustup_bin update stable"
}

update_uv() {
    log_section "Python Tools (uv)"

    local uv_bin="$HOME/.local/bin/uv"

    if [[ ! -x "$uv_bin" ]]; then
        log_item "skip" "uv" "not installed"
        return 0
    fi

    run_cmd "uv self-update" "$uv_bin self update"
}

update_stack() {
    log_section "Dicklesworthstone Stack"

    if [[ "$UPDATE_STACK" != "true" ]]; then
        log_item "skip" "stack update" "disabled (use --stack to enable)"
        return 0
    fi

    # NTM
    if cmd_exists ntm; then
        run_cmd "NTM" "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh | bash"
    fi

    # MCP Agent Mail
    if [[ -d "$HOME/mcp_agent_mail" ]] || cmd_exists am; then
        run_cmd "MCP Agent Mail" "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail/main/scripts/install.sh | bash -s -- --yes"
    fi

    # UBS
    if cmd_exists ubs; then
        run_cmd "Ultimate Bug Scanner" "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/master/install.sh | bash -s -- --easy-mode"
    fi

    # Beads Viewer
    if cmd_exists bv; then
        run_cmd "Beads Viewer" "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh | bash"
    fi

    # CASS
    if cmd_exists cass; then
        run_cmd "CASS" "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh | bash -s -- --easy-mode --verify"
    fi

    # CASS Memory
    if cmd_exists cm; then
        run_cmd "CASS Memory" "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/cass_memory_system/main/install.sh | bash -s -- --easy-mode --verify"
    fi

    # CAAM
    if cmd_exists caam; then
        run_cmd "CAAM" "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_account_manager/main/install.sh | bash"
    fi

    # SLB
    if cmd_exists slb; then
        run_cmd "SLB" "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/simultaneous_launch_button/main/scripts/install.sh | bash"
    fi
}

# ============================================================
# Summary
# ============================================================

print_summary() {
    echo ""
    echo "============================================================"
    echo -e "Summary: ${GREEN}$SUCCESS_COUNT updated${NC}, ${DIM}$SKIP_COUNT skipped${NC}, ${RED}$FAIL_COUNT failed${NC}"
    echo ""

    if [[ $FAIL_COUNT -eq 0 ]]; then
        echo -e "${GREEN}All updates completed successfully!${NC}"
    else
        echo -e "${YELLOW}Some updates failed. Check output above.${NC}"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        echo -e "${DIM}(dry-run mode - no changes were made)${NC}"
    fi
}

# ============================================================
# CLI
# ============================================================

usage() {
    cat << 'EOF'
acfs update - Update all ACFS components

Usage:
  acfs update [options]

Options:
  --apt-only       Only update system packages
  --agents-only    Only update coding agents
  --cloud-only     Only update cloud CLIs
  --stack          Include Dicklesworthstone stack updates
  --no-apt         Skip apt updates
  --no-agents      Skip agent updates
  --no-cloud       Skip cloud CLI updates
  --force          Install missing tools
  --dry-run        Show what would be updated without making changes
  --verbose        Show more details
  --help           Show this help

Examples:
  acfs update                  # Update apt, agents, and cloud CLIs
  acfs update --stack          # Include stack tools
  acfs update --agents-only    # Only update coding agents
  acfs update --dry-run        # Preview changes

What gets updated:
  - System packages (apt update/upgrade)
  - Bun runtime
  - Coding agents (Claude, Codex, Gemini)
  - Cloud CLIs (Wrangler, Supabase, Vercel)
  - Rust toolchain
  - uv (Python tools)
  - Dicklesworthstone stack (with --stack flag)
EOF
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --apt-only)
                UPDATE_APT=true
                UPDATE_AGENTS=false
                UPDATE_CLOUD=false
                UPDATE_STACK=false
                shift
                ;;
            --agents-only)
                UPDATE_APT=false
                UPDATE_AGENTS=true
                UPDATE_CLOUD=false
                UPDATE_STACK=false
                shift
                ;;
            --cloud-only)
                UPDATE_APT=false
                UPDATE_AGENTS=false
                UPDATE_CLOUD=true
                UPDATE_STACK=false
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

    # Header
    echo ""
    echo -e "${BOLD}ACFS Update v$ACFS_VERSION${NC}"
    echo -e "User: $(whoami)"
    echo -e "Date: $(date '+%Y-%m-%d %H:%M')"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}Mode: dry-run${NC}"
    fi

    # Run updates
    update_apt
    update_bun
    update_agents
    update_cloud
    update_rust
    update_uv
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
