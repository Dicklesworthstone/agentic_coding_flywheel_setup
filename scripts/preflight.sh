#!/usr/bin/env bash
# ============================================================
# ACFS Pre-Flight Check
#
# Validates system prerequisites before installation to fail fast
# with clear, actionable error messages.
#
# Usage:
#   ./scripts/preflight.sh           # Full check with colored output
#   ./scripts/preflight.sh --quiet   # Exit code only
#   ./scripts/preflight.sh --json    # JSON output for automation
#
# Exit Codes:
#   0: All critical checks pass (warnings are OK)
#   1: Critical check failed (installation would fail)
#
# Related beads:
#   - agentic_coding_flywheel_setup-0iq: Create scripts/preflight.sh
#   - agentic_coding_flywheel_setup-0ok: EPIC: Pre-Flight Validation
# ============================================================

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
GRAY='\033[0;90m'
NC='\033[0m'

# Symbols
CHECK="${GREEN}[✓]${NC}"
WARN="${YELLOW}[!]${NC}"
FAIL="${RED}[✗]${NC}"

# Counters
ERRORS=0
WARNINGS=0

# Output mode
QUIET=false
JSON_OUTPUT=false

# Results for JSON output
declare -a RESULTS=()

# ============================================================
# Argument Parsing
# ============================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quiet|-q)
            QUIET=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--quiet] [--json]"
            echo ""
            echo "Options:"
            echo "  --quiet, -q  Suppress output, exit code only"
            echo "  --json       Output results as JSON"
            echo "  --help, -h   Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# ============================================================
# Output Functions
# ============================================================

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}" # escape backslashes
    s="${s//\"/\\\"}" # escape quotes
    s="${s//$'\n'/\\n}" # escape newlines
    s="${s//$'\r'/\\r}" # escape CR
    s="${s//$'\t'/\\t}" # escape tabs
    printf '%s' "$s"
}

log_check() {
    local status="$1"
    local message="$2"
    local detail="${3:-}"

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        # Escape quotes in message and detail for JSON
        message="$(json_escape "$message")"
        detail="$(json_escape "$detail")"
        RESULTS+=("{\"status\":\"$status\",\"message\":\"$message\",\"detail\":\"$detail\"}")
    elif [[ "$QUIET" != "true" ]]; then
        case "$status" in
            pass)
                echo -e "${CHECK} ${message}"
                [[ -n "$detail" ]] && echo -e "    ${GRAY}${detail}${NC}" || true
                ;;
            warn)
                echo -e "${WARN} ${YELLOW}${message}${NC}"
                [[ -n "$detail" ]] && echo -e "    ${GRAY}${detail}${NC}" || true
                ;;
            fail)
                echo -e "${FAIL} ${RED}${message}${NC}"
                [[ -n "$detail" ]] && echo -e "    ${GRAY}${detail}${NC}" || true
                ;;
        esac
    fi
}

pass() {
    log_check "pass" "$1" "${2:-}"
}

warn() {
    ((WARNINGS++)) || true
    log_check "warn" "$1" "${2:-}"
}

fail() {
    ((ERRORS++)) || true
    log_check "fail" "$1" "${2:-}"
}

# ============================================================
# System Checks
# ============================================================

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        fail "Not a Linux system" "ACFS requires Ubuntu Linux"
        return
    fi

    # shellcheck source=/dev/null
    source /etc/os-release

    if [[ "${ID:-}" != "ubuntu" ]]; then
        warn "Untested OS: ${ID:-unknown}" "ACFS is designed for Ubuntu, may work on ${ID}"
    else
        local version="${VERSION_ID:-0}"
        local major="${version%%.*}"
        if (( major >= 24 )); then
            pass "Operating System: Ubuntu ${VERSION_ID}"
        elif (( major >= 22 )); then
            pass "Operating System: Ubuntu ${VERSION_ID}" "22.04+ supported, 24.04+ recommended"
        else
            warn "Ubuntu ${VERSION_ID}" "Version 22.04+ recommended for best compatibility"
        fi
    fi
}

check_architecture() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64)
            pass "Architecture: x86_64 (AMD64)"
            ;;
        aarch64|arm64)
            pass "Architecture: ARM64"
            ;;
        *)
            fail "Unsupported architecture: $arch" "ACFS requires x86_64 or ARM64"
            ;;
    esac
}

check_memory() {
    if [[ ! -f /proc/meminfo ]]; then
        warn "Cannot check memory" "/proc/meminfo not available"
        return
    fi

    local mem_kb
    mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    local mem_gb=$((mem_kb / 1024 / 1024))

    if (( mem_gb >= 8 )); then
        pass "Memory: ${mem_gb}GB"
    elif (( mem_gb >= 4 )); then
        warn "Memory: ${mem_gb}GB" "8GB+ recommended for running multiple agents"
    else
        warn "Memory: ${mem_gb}GB" "Low memory may cause issues, 4GB minimum recommended"
    fi
}

check_disk() {
    local free_kb
    # Use -P for POSIX output (header + one line per FS), awk column 4 is usually Available
    # Tail -n 1 to get the data line (more portable than tail -1)
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS df -k -P
        free_kb=$(df -k -P / 2>/dev/null | tail -n 1 | awk '{print $4}')
    else
        # Linux df -P (often implies 1K blocks, but verify)
        # Using -k ensures 1K blocks
        free_kb=$(df -k -P / 2>/dev/null | tail -n 1 | awk '{print $4}')
    fi

    # Handle non-numeric or empty values
    if [[ -z "$free_kb" ]] || ! [[ "$free_kb" =~ ^[0-9]+$ ]]; then
        warn "Cannot determine disk space" "df command returned unexpected output"
        return
    fi

    local free_gb=$((free_kb / 1024 / 1024))

    if (( free_gb >= 40 )); then
        pass "Disk Space: ${free_gb}GB free"
    elif (( free_gb >= 20 )); then
        pass "Disk Space: ${free_gb}GB free" "40GB+ recommended for large projects"
    else
        fail "Disk Space: ${free_gb}GB free" "Need at least 20GB free (40GB+ recommended)"
    fi
}

# ============================================================
# Network Checks
# ============================================================

check_network_basic() {
    if ! command -v curl &>/dev/null; then
        warn "curl not installed" "Network checks skipped; curl will be installed"
        return
    fi

    # Test basic connectivity to GitHub (critical)
    if curl -sf --max-time 10 https://github.com > /dev/null 2>&1; then
        pass "Network: github.com reachable"
    else
        fail "Network: Cannot reach github.com" "Check network/firewall settings"
        return
    fi
}

check_network_installers() {
    if ! command -v curl &>/dev/null; then
        return
    fi

    # Test key installer URLs (warnings, not failures)
    # Use simple GET with HTTP status check - most reliable across VPS providers
    local urls=(
        "https://bun.sh/install:Bun installer"
        "https://astral.sh/uv/install.sh:UV/Python installer"
        "https://sh.rustup.rs:Rust installer"
        "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/README.md:GitHub raw content"
    )

    local all_ok=true
    local failed_urls=()

    for entry in "${urls[@]}"; do
        # Use single % to remove shortest match from end (preserves https://)
        local url="${entry%:*}"
        local name="${entry##*:}"

        # Simple check: follow redirects, get HTTP status, 15s timeout
        # We just need to verify the URL is reachable, not download the content
        local http_status
        http_status=$(curl -sL --max-time 15 --connect-timeout 10 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null) || http_status="000"

        # Ensure http_status is a valid number (default to 000 if empty or invalid)
        [[ "$http_status" =~ ^[0-9]+$ ]] || http_status="000"

        if [[ "$http_status" -ge 200 && "$http_status" -lt 400 ]]; then
            : # Success
        else
            all_ok=false
            failed_urls+=("$name")
        fi
    done

    if [[ "$all_ok" == "true" ]]; then
        pass "Network: All installer URLs reachable"
    else
        for name in "${failed_urls[@]}"; do
            warn "Network: Cannot reach $name" "May need to retry during install"
        done
    fi
}

# ============================================================
# APT Checks
# ============================================================

check_apt_lock() {
    # Only relevant on Debian/Ubuntu systems with apt
    if ! command -v apt-get &>/dev/null; then
        return
    fi

    # Check for dpkg lock
    if [[ -f /var/lib/dpkg/lock-frontend ]]; then
        if fuser /var/lib/dpkg/lock-frontend &>/dev/null 2>&1; then
            fail "APT is locked by another process" "Wait for other apt operations or run: sudo killall apt apt-get"
            return
        fi
    fi

    # Check for active apt processes
    # Use -f to match against full command line for safer detection
    if pgrep -f "(apt|apt-get|dpkg)" >/dev/null 2>&1; then
        warn "APT process running" "Another package operation in progress"
        return
    fi

    # Check for unattended-upgrades
    if pgrep -f "unattended-upgr" >/dev/null 2>&1; then
        warn "unattended-upgrades running" "May cause apt conflicts; consider: sudo systemctl stop unattended-upgrades"
        return
    fi

    pass "APT: No locks detected"
}

# ============================================================
# User Environment Checks
# ============================================================

check_user() {
    if [[ "$EUID" -eq 0 ]]; then
        warn "Running as root" "ACFS will create and install for 'ubuntu' user"
    else
        pass "User: $(whoami)"
    fi

    if [[ -z "${HOME:-}" ]]; then
        fail "HOME not set" "HOME environment variable is required"
        return
    fi

    if [[ ! -d "$HOME" ]]; then
        fail "HOME directory does not exist" "$HOME not found"
        return
    fi

    if [[ ! -w "$HOME" ]]; then
        fail "HOME not writable" "Cannot write to $HOME"
        return
    fi
}

check_shell() {
    local shell
    shell=$(basename "${SHELL:-/bin/sh}")

    case "$shell" in
        bash|zsh)
            pass "Shell: $shell"
            ;;
        *)
            warn "Shell: $shell" "bash or zsh recommended (zsh will be installed)"
            ;;
    esac
}

check_sudo() {
    if ! command -v sudo &>/dev/null; then
        fail "sudo not installed" "sudo is required for system package installation"
        return
    fi

    # Check if user can sudo
    if [[ "$EUID" -eq 0 ]]; then
        pass "Privileges: Running as root"
    elif sudo -n true 2>/dev/null; then
        pass "Privileges: Passwordless sudo available"
    else
        pass "Privileges: sudo available" "Password may be required during install"
    fi
}

# ============================================================
# Conflict Detection
# ============================================================

check_conflicts() {
    local conflicts_found=false

    # Skip HOME-dependent checks if HOME is not set
    if [[ -z "${HOME:-}" ]]; then
        warn "Conflict checks skipped" "HOME not set, cannot check user directories"
        return
    fi

    # Check for nvm (may conflict with bun/mise)
    if [[ -d "${NVM_DIR:-$HOME/.nvm}" ]] || [[ -f "$HOME/.nvm/nvm.sh" ]]; then
        warn "nvm detected" "May conflict with bun; consider removing or deactivating"
        conflicts_found=true
    fi

    # Check for pyenv (may conflict with uv)
    if [[ -d "$HOME/.pyenv" ]] || command -v pyenv &>/dev/null; then
        warn "pyenv detected" "May conflict with uv; consider removing or deactivating"
        conflicts_found=true
    fi

    # Check for rbenv
    if [[ -d "$HOME/.rbenv" ]] || command -v rbenv &>/dev/null; then
        # Not a conflict, just FYI
        pass "rbenv detected" "Will coexist with ACFS tools"
    fi

    # Check for existing ACFS installation
    if [[ -d "$HOME/.acfs" ]]; then
        if [[ -f "$HOME/.acfs/state.json" ]]; then
            warn "Existing ACFS installation" "Previous install found; consider --resume or fresh start"
        else
            pass "ACFS directory exists" "Partial installation detected"
        fi
        conflicts_found=true
    fi

    # Check for existing tools that ACFS will install
    local existing_tools=()
    command -v bun &>/dev/null && existing_tools+=("bun")
    command -v uv &>/dev/null && existing_tools+=("uv")
    command -v claude &>/dev/null && existing_tools+=("claude")
    command -v codex &>/dev/null && existing_tools+=("codex")

    if [[ ${#existing_tools[@]} -gt 0 ]]; then
        pass "Existing tools: ${existing_tools[*]}" "Will be updated/skipped"
    fi

    if [[ "$conflicts_found" == "false" ]]; then
        pass "No conflicts detected"
    fi
}

# ============================================================
# Main
# ============================================================

main() {
    if [[ "$QUIET" != "true" && "$JSON_OUTPUT" != "true" ]]; then
        echo -e "${BOLD}ACFS Pre-Flight Check${NC}"
        echo "====================="
        echo ""
    fi

    # Run all checks
    check_os
    check_architecture
    check_memory
    check_disk

    [[ "$QUIET" != "true" && "$JSON_OUTPUT" != "true" ]] && echo ""

    check_network_basic
    check_network_installers

    [[ "$QUIET" != "true" && "$JSON_OUTPUT" != "true" ]] && echo ""

    check_apt_lock

    [[ "$QUIET" != "true" && "$JSON_OUTPUT" != "true" ]] && echo ""

    check_user
    check_shell
    check_sudo

    [[ "$QUIET" != "true" && "$JSON_OUTPUT" != "true" ]] && echo ""

    check_conflicts

    # Summary
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "{"
        echo "  \"errors\": $ERRORS,"
        echo "  \"warnings\": $WARNINGS,"
        echo "  \"checks\": ["
        local first=true
        for result in "${RESULTS[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            echo -n "    $result"
        done
        echo ""
        echo "  ]"
        echo "}"
    elif [[ "$QUIET" != "true" ]]; then
        echo ""
        echo "====================="
        if (( ERRORS > 0 )); then
            echo -e "${RED}${BOLD}Result: $ERRORS error(s), $WARNINGS warning(s)${NC}"
            echo ""
            echo -e "${RED}Critical issues must be resolved before installation.${NC}"
        elif (( WARNINGS > 0 )); then
            echo -e "${YELLOW}${BOLD}Result: $WARNINGS warning(s)${NC}"
            echo ""
            echo -e "${GREEN}Pre-flight checks passed. Warnings are informational.${NC}"
        else
            echo -e "${GREEN}${BOLD}Result: All checks passed!${NC}"
            echo ""
            echo -e "${GREEN}System is ready for ACFS installation.${NC}"
        fi
    fi

    # Exit with error if critical failures
    if (( ERRORS > 0 )); then
        exit 1
    fi

    exit 0
}

main "$@"
