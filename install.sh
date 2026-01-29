#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
# ============================================================
# ACFS - Agentic Coding Flywheel Setup
# Main installer script
#
# Usage:
#   curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh?$(date +%s)" | bash -s -- --yes --mode vibe
#
# Options:
#   --yes         Skip all prompts, use defaults
#   --mode vibe   Enable passwordless sudo, full agent permissions
#   --dry-run     Print what would be done without changing system
#   --print       Print upstream scripts/versions that will be run
#   --skip-postgres   Skip PostgreSQL 18 installation
#   --skip-vault      Skip HashiCorp Vault installation
#   --skip-cloud      Skip cloud CLIs (wrangler, supabase, vercel)
#   --resume          Resume from checkpoint (default when state exists)
#   --force-reinstall Start fresh, ignore existing state
#   --reset-state     Move state file aside and exit (for debugging)
#   --interactive     Enable interactive prompts for resume decisions
#   --skip-preflight  Skip pre-flight system validation
#   --auto-fix        Enable auto-fix for pre-flight issues (prompt mode, default)
#   --no-auto-fix     Disable auto-fix (only warn about issues)
#   --auto-fix-accept-all  Auto-fix all issues without prompting (for CI)
#   --auto-fix-dry-run     Show what auto-fix would do without executing
#   --skip-ubuntu-upgrade  Skip automatic Ubuntu version upgrade
#   --target-ubuntu=VER    Set target Ubuntu version (default: 25.10)
#   --strict          Treat ALL tools as critical (any checksum mismatch aborts)
#   --list-modules    List available modules and exit
#   --print-plan      Print execution plan and exit (no installs)
#   --only <module>       Only run a specific module (repeatable)
#   --only-phase <phase>  Only run modules in a specific phase (repeatable)
#   --skip <module>       Skip a specific module (repeatable)
#   --no-deps             Disable automatic dependency closure (expert/debug)
#   --checksums-ref <ref> Fetch checksums.yaml from this ref (default: main for pinned tags/SHAs)
# ============================================================

set -euo pipefail

# Prevent apt/dpkg from displaying interactive dialogs (kernel upgrade prompts,
# debconf questions, etc.) that corrupt the terminal with ncurses escape sequences
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a    # Automatically restart services without asking
export NEEDRESTART_SUSPEND=1 # Suppress needrestart prompts during installation
export DEBCONF_NONINTERACTIVE_SEEN=true

# ============================================================
# Configuration
# ============================================================
ACFS_VERSION="0.5.0"
# Allow fork installations by overriding these via environment variables
ACFS_REPO_OWNER="${ACFS_REPO_OWNER:-Dicklesworthstone}"
ACFS_REPO_NAME="${ACFS_REPO_NAME:-agentic_coding_flywheel_setup}"
ACFS_REF="${ACFS_REF:-main}"
# Preserve the original ref (branch/tag/sha) before resolving to a commit SHA.
ACFS_REF_INPUT="$ACFS_REF"
# Checksums ref defaults to ACFS_REF_INPUT, but pinned tags/SHAs fall back to main
# to avoid stale checksums for fast-moving upstream installers.
ACFS_CHECKSUMS_REF="${ACFS_CHECKSUMS_REF:-}"
if [[ -z "$ACFS_CHECKSUMS_REF" ]]; then
    if [[ "$ACFS_REF_INPUT" =~ ^v[0-9]+(\.[0-9]+){1,2}([.-][A-Za-z0-9]+)*$ ]] || [[ "$ACFS_REF_INPUT" =~ ^[0-9a-f]{7,40}$ ]]; then
        ACFS_CHECKSUMS_REF="main"
    else
        ACFS_CHECKSUMS_REF="$ACFS_REF_INPUT"
    fi
fi
ACFS_RAW="https://raw.githubusercontent.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/${ACFS_REF}"
ACFS_CHECKSUMS_RAW="https://raw.githubusercontent.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/${ACFS_CHECKSUMS_REF}"
export ACFS_RAW ACFS_CHECKSUMS_REF ACFS_CHECKSUMS_RAW ACFS_VERSION
export CHECKSUMS_FILE="${ACFS_CHECKSUMS_YAML:-}"
ACFS_COMMIT_SHA=""       # Short SHA for display (12 chars)
ACFS_COMMIT_SHA_FULL=""  # Full SHA for pinning resume scripts (40 chars)

# Early curl defaults: enforce HTTPS (including redirects) when supported.
# This is used before security.sh is available (bootstrap / early library sourcing).
ACFS_EARLY_CURL_ARGS=(-fsSL)
if command -v curl &>/dev/null && curl --help all 2>/dev/null | grep -q -- '--proto'; then
    ACFS_EARLY_CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
fi
# Note: ACFS_HOME is set after TARGET_HOME is determined
ACFS_LOG_DIR="/var/log/acfs"
# SCRIPT_DIR is empty when running via curl|bash (stdin; no file on disk)
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Early PATH setup: ensure ~/.local/bin is available for native installers (e.g., Claude Code)
# This is critical because the Claude native installer puts the binary at ~/.local/bin/claude
export PATH="$HOME/.local/bin:$PATH"

# Default options
YES_MODE=false
DRY_RUN=false
PRINT_MODE=false
PIN_REF_MODE=false
MODE="vibe"
SKIP_POSTGRES=false
SKIP_VAULT=false
SKIP_CLOUD=false

# Manifest-driven selection options (mjt.5.3)
LIST_MODULES=false
PRINT_PLAN_MODE=false
ONLY_MODULES=()
ONLY_PHASES=()
SKIP_MODULES=()
NO_DEPS=false

# Resume/reinstall options (used by state.sh confirm_resume)
export ACFS_FORCE_RESUME=false
export ACFS_FORCE_REINSTALL=false
# NOTE: When unset/empty, downstream libs default to interactive behavior when a TTY is available.
# install.sh forces non-interactive behavior in --yes mode.
export ACFS_INTERACTIVE="${ACFS_INTERACTIVE:-}"
RESET_STATE_ONLY=false

# Preflight options
SKIP_PREFLIGHT=false

# Auto-fix options (bd-19y9.3.4)
# Modes: "prompt" (default, interactive), "yes" (accept all), "no" (disable), "dry-run" (preview only)
AUTO_FIX_MODE="prompt"
export AUTO_FIX_MODE

# Ubuntu upgrade options (nb4: integrate upgrade phase)
SKIP_UBUNTU_UPGRADE=false
TARGET_UBUNTU_VERSION="25.10"

# Target user configuration
# Default: install for the "ubuntu" user (typical VPS images).
# Advanced: override with env vars (see README):
#   TARGET_USER=myuser TARGET_HOME=/home/myuser ...
TARGET_USER="${TARGET_USER:-ubuntu}"
# Leave TARGET_HOME unset by default; init_target_paths will derive it from:
# - $HOME when running as TARGET_USER
# - /home/$TARGET_USER otherwise
TARGET_HOME="${TARGET_HOME:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Check if gum is available for enhanced UI
HAS_GUM=false
if command -v gum &>/dev/null; then
    HAS_GUM=true
fi

# ============================================================
# Prevent logging.sh from overwriting our inline gum-enhanced functions
# ============================================================
export _ACFS_LOGGING_SH_LOADED=1

# ============================================================
# Minimal error-tracking fallbacks
# These are replaced once scripts/lib/error_tracking.sh is sourced (detect_environment()).
# ============================================================
type -t set_phase &>/dev/null || set_phase() { :; }
type -t try_step &>/dev/null || try_step() { shift; "$@"; }
type -t try_step_eval &>/dev/null || try_step_eval() { shift; bash -e -o pipefail -c "$1"; }

# ============================================================
# Installer libraries are sourced later in main() via detect_environment(), after
# bootstrapping the repo archive for curl|bash runs (prevents mixed refs).
# ============================================================

# ============================================================
# Source Ubuntu upgrade library for auto-upgrade functionality (nb4)
# ============================================================
_source_ubuntu_upgrade_lib() {
    # Already loaded?
    if [[ -n "${ACFS_UBUNTU_UPGRADE_LOADED:-}" ]]; then
        return 0
    fi

    # Prefer bootstrapped libs when available (curl|bash mode), to avoid mixed refs.
    if [[ -n "${ACFS_LIB_DIR:-}" ]] && [[ -f "$ACFS_LIB_DIR/ubuntu_upgrade.sh" ]]; then
        # shellcheck source=scripts/lib/ubuntu_upgrade.sh
        source "$ACFS_LIB_DIR/ubuntu_upgrade.sh"
        export ACFS_UBUNTU_UPGRADE_LOADED=1
        return 0
    fi

    # Try local file first (when running from repo)
    if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "$SCRIPT_DIR/scripts/lib/ubuntu_upgrade.sh" ]]; then
        # shellcheck source=scripts/lib/ubuntu_upgrade.sh
        source "$SCRIPT_DIR/scripts/lib/ubuntu_upgrade.sh"
        export ACFS_UBUNTU_UPGRADE_LOADED=1
        return 0
    fi

    # Try relative path (when running from repo root)
    if [[ -f "./scripts/lib/ubuntu_upgrade.sh" ]]; then
        source "./scripts/lib/ubuntu_upgrade.sh"
        export ACFS_UBUNTU_UPGRADE_LOADED=1
        return 0
    fi

    # Download for curl|bash scenario
    if command -v curl &>/dev/null; then
        local tmp_upgrade=""
        if command -v mktemp &>/dev/null; then
            tmp_upgrade="$(mktemp "${TMPDIR:-/tmp}/acfs-ubuntu-upgrade.XXXXXX" 2>/dev/null)" || tmp_upgrade=""
        fi
        if [[ -n "$tmp_upgrade" ]] && curl "${ACFS_EARLY_CURL_ARGS[@]}" "$ACFS_RAW/scripts/lib/ubuntu_upgrade.sh" -o "$tmp_upgrade" 2>/dev/null; then
            source "$tmp_upgrade"
            rm -f "$tmp_upgrade"
            export ACFS_UBUNTU_UPGRADE_LOADED=1
            return 0
        fi
    fi

    # If we can't load it, return failure (caller should handle)
    return 1
}

# ACFS Color scheme (Catppuccin Mocha inspired)
ACFS_PRIMARY="#89b4fa"
ACFS_SUCCESS="#a6e3a1"
ACFS_WARNING="#f9e2af"
ACFS_ERROR="#f38ba8"
ACFS_MUTED="#6c7086"

# ============================================================
# Fetch commit SHA and date from GitHub API
# This ensures we always know exactly which version is running
# ============================================================
export ACFS_COMMIT_DATE=""  # exported for child processes/debugging
ACFS_COMMIT_AGE=""

fetch_commit_sha() {
    # Already have it? Skip
    if [[ -n "$ACFS_COMMIT_SHA" && "$ACFS_COMMIT_SHA" != "(unknown)" ]]; then
        return 0
    fi

    # Need curl
    if ! command -v curl &>/dev/null; then
        ACFS_COMMIT_SHA="(curl not available)"
        return 0
    fi

    # Fetch from GitHub API - get the commit SHA for the ref
    local api_url="https://api.github.com/repos/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/commits/${ACFS_REF}"
    local response

    if response=$(curl -sf --max-time 5 "$api_url" 2>/dev/null); then
        # Try to use python3 for robust JSON parsing if available
        local sha=""
        local commit_date=""
        
        if command -v python3 &>/dev/null; then
            # Python parsing - robust against JSON formatting changes
            sha=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('sha', ''))" 2>/dev/null)
            commit_date=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('commit', {}).get('author', {}).get('date', ''))" 2>/dev/null)
        else
            # Fallback: Extract SHA from JSON using grep/sed (works without jq/python)
            # Use grep -o to handle minified JSON (puts matches on new lines)
            sha=$(echo "$response" | grep -o '"sha":[[:space:]]*"[^"]*"' | head -n 1 | sed 's/.*"\([a-f0-9]*\)".*/\1/')

            # Extract commit date (format: "2025-12-21T10:30:00Z")
            commit_date=$(echo "$response" | grep -o '"date":[[:space:]]*"[^"]*"' | head -n 1 | sed 's/.*"\([^"]*\)".*/\1/')
        fi

        if [[ -n "$sha" && ${#sha} -ge 7 ]]; then
            ACFS_COMMIT_SHA="${sha:0:12}"
            # shellcheck disable=SC2034  # Used by scripts/lib/ubuntu_upgrade.sh to pin resume scripts to a specific commit.
            [[ ${#sha} -ge 40 ]] && ACFS_COMMIT_SHA_FULL="$sha"
        fi

        if [[ -n "$commit_date" ]]; then
            ACFS_COMMIT_DATE="$commit_date"
            # Calculate age
            local now commit_ts age_seconds
            now=$(date +%s 2>/dev/null || echo 0)
            # Parse ISO 8601 date - handle both GNU and BSD date
            if date -d "$commit_date" +%s &>/dev/null; then
                # GNU date
                commit_ts=$(date -d "$commit_date" +%s 2>/dev/null || echo 0)
            else
                # BSD date - try simpler parsing
                commit_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$commit_date" +%s 2>/dev/null || echo 0)
            fi

            if [[ "$now" -gt 0 && "$commit_ts" -gt 0 ]]; then
                age_seconds=$((now - commit_ts))
                # Handle negative age (clock skew / future commit)
                if [[ $age_seconds -lt 0 ]]; then
                    ACFS_COMMIT_AGE="just now"
                elif [[ $age_seconds -lt 60 ]]; then
                    ACFS_COMMIT_AGE="${age_seconds}s ago"
                elif [[ $age_seconds -lt 3600 ]]; then
                    ACFS_COMMIT_AGE="$((age_seconds / 60))m ago"
                elif [[ $age_seconds -lt 86400 ]]; then
                    ACFS_COMMIT_AGE="$((age_seconds / 3600))h ago"
                else
                    ACFS_COMMIT_AGE="$((age_seconds / 86400))d ago"
                fi
            fi
        fi

        if [[ -n "$ACFS_COMMIT_SHA" ]]; then
            return 0
        fi
    fi

    # Fallback
    ACFS_COMMIT_SHA="(unknown)"
}

# ============================================================
# Install gum FIRST for beautiful UI from the start
# ============================================================
install_gum_early() {
    # Already have gum? Great!
    if command -v gum &>/dev/null; then
        HAS_GUM=true
        return 0
    fi

    # Respect dry-run / print-only modes: do not modify the system just to
    # improve UI.
    if [[ "${DRY_RUN:-false}" == "true" ]] || [[ "${PRINT_MODE:-false}" == "true" ]]; then
        return 0
    fi

    # Only attempt early gum install on supported Ubuntu systems.
    # Preflight/ensure_ubuntu will stop execution later, but this prevents
    # partial modifications (apt repo/key) on unsupported OS versions.
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        local version_id="${VERSION_ID:-}"
        local version_major="${version_id%%.*}"
        if [[ "${ID:-}" != "ubuntu" ]] || [[ -z "$version_id" ]] || [[ "$version_major" -lt 22 ]]; then
            return 0
        fi
    else
        return 0
    fi

    # Need curl to fetch gum - if curl isn't installed yet, skip early install
    # (gum will be installed later in install_cli_tools after ensure_base_deps)
    if ! command -v curl &>/dev/null; then
        return 0
    fi

    # Need gpg for apt key handling
    if ! command -v gpg &>/dev/null; then
        return 0
    fi

    # Need apt-get for installation
    if ! command -v apt-get &>/dev/null; then
        return 0
    fi

    # Need root/sudo for apt operations
    local sudo_cmd=""
    if [[ $EUID -ne 0 ]]; then
        if command -v sudo &>/dev/null; then
            sudo_cmd="sudo"
        else
            # Can't install gum without sudo, fall back to plain output
            return 0
        fi
    fi

    echo -e "\033[0;90m    → Installing gum for enhanced UI...\033[0m" >&2

    # Step 1: Fetch Charm GPG key (with timeout)
    echo -e "\033[0;90m      ↳ Fetching Charm repository key...\033[0m" >&2
    $sudo_cmd mkdir -p /etc/apt/keyrings 2>/dev/null || true
    if ! curl --connect-timeout 10 --max-time 30 -fsSL https://repo.charm.sh/apt/gpg.key 2>/dev/null | \
        $sudo_cmd gpg --batch --yes --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null; then
        echo -e "\033[0;33m      ⚠ Could not fetch Charm key (skipping gum, will retry later)\033[0m" >&2
        return 0
    fi

    # Step 2: Add apt repository (using DEB822 format to avoid .migrate warnings on upgrade)
    $sudo_cmd tee /etc/apt/sources.list.d/charm.sources > /dev/null 2>&1 << 'EOF'
Types: deb
URIs: https://repo.charm.sh/apt/
Suites: *
Components: *
Signed-By: /etc/apt/keyrings/charm.gpg
EOF

    # Step 3: Update apt (this can be slow on fresh systems)
    # Disable fancy progress to prevent terminal cursor issues
    echo -e "\033[0;90m      ↳ Updating package lists (may take 30-60s on fresh systems)...\033[0m" >&2
    if ! DEBIAN_FRONTEND=noninteractive timeout 120 $sudo_cmd apt-get update -y \
        -o Dpkg::Progress-Fancy="0" -o APT::Color="0" >/dev/null 2>&1; then
        # Reset terminal line position in case apt left cursor in bad state
        echo -e "\r\033[K\033[0;33m      ⚠ apt-get update slow/failed (skipping gum, will retry later)\033[0m" >&2
        return 0
    fi

    # Step 4: Install gum
    # Use DEBIAN_FRONTEND=noninteractive and disable fancy progress to prevent
    # terminal cursor position issues when apt-get fails or times out
    echo -e "\033[0;90m      ↳ Installing gum package...\033[0m" >&2
    local apt_output
    if apt_output=$(DEBIAN_FRONTEND=noninteractive timeout 60 $sudo_cmd apt-get install -y \
        -o Dpkg::Progress-Fancy="0" -o APT::Color="0" gum 2>&1); then
        HAS_GUM=true
        # Reset terminal line position and show success
        echo -e "\r\033[K\033[0;32m    ✓ gum installed - enhanced UI enabled!\033[0m" >&2
    else
        # Reset terminal line position in case apt left cursor in bad state
        echo -e "\r\033[K\033[0;33m      ⚠ gum install failed (continuing without enhanced UI)\033[0m" >&2
        # Show brief reason if available (e.g., "Unable to locate package", timeout, etc.)
        if echo "$apt_output" | grep -qi "unable to locate\|not found\|timeout"; then
            echo -e "\033[0;90m        (Charm repository may be unavailable or package not found)\033[0m" >&2
        fi
    fi
}

# ============================================================
# ASCII Art Banner
# ============================================================
print_banner() {
    # Ensure terminal is in a clean state before printing banner
    # (previous apt/dpkg operations may have left cursor in bad position)
    echo -e "\r\033[K" >&2

    # Build version line with proper padding (63 chars inner width)
    local version_text="Agentic Coding Flywheel Setup v${ACFS_VERSION}"
    local padding=$(( (63 - ${#version_text}) / 2 ))
    local version_line
    version_line=$(printf "║%*s%s%*s║" "$padding" "" "$version_text" "$((63 - padding - ${#version_text}))" "")

    # Build commit info line
    local commit_text=""
    if [[ -n "$ACFS_COMMIT_SHA" && "$ACFS_COMMIT_SHA" != "(unknown)" ]]; then
        commit_text="Commit: ${ACFS_COMMIT_SHA}"
        if [[ -n "$ACFS_COMMIT_AGE" ]]; then
            commit_text="${commit_text} (${ACFS_COMMIT_AGE})"
        fi
    fi
    local commit_padding=$(( (63 - ${#commit_text}) / 2 ))
    local commit_line
    if [[ -n "$commit_text" ]]; then
        commit_line=$(printf "║%*s%s%*s║" "$commit_padding" "" "$commit_text" "$((63 - commit_padding - ${#commit_text}))" "")
    else
        commit_line="║                                                               ║"
    fi

    local banner="
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     █████╗  ██████╗███████╗███████╗                           ║
║    ██╔══██╗██╔════╝██╔════╝██╔════╝                           ║
║    ███████║██║     █████╗  ███████╗                           ║
║    ██╔══██║██║     ██╔══╝  ╚════██║                           ║
║    ██║  ██║╚██████╗██║     ███████║                           ║
║    ╚═╝  ╚═╝ ╚═════╝╚═╝     ╚══════╝                           ║
║                                                               ║
${version_line}
${commit_line}
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
"

    if [[ "$HAS_GUM" == "true" ]]; then
        echo "$banner" | gum style --foreground "$ACFS_PRIMARY" --bold >&2
    else
        echo -e "${BLUE}$banner${NC}" >&2
    fi
}

# ============================================================
# Pinned Ref Output (bd-31ps.8.1)
# Prints resolved SHA and copy-pasteable pinned command
# ============================================================
print_pinned_ref() {
    local sha="${ACFS_COMMIT_SHA_FULL:-$ACFS_COMMIT_SHA}"

    if [[ -z "$sha" || "$sha" == "(unknown)" || "$sha" == "(curl not available)" ]]; then
        echo "Error: Could not resolve ref '$ACFS_REF' to SHA" >&2
        echo "" >&2
        echo "Possible causes:" >&2
        echo "  - Invalid ref (branch, tag, or SHA)" >&2
        echo "  - GitHub API rate limit or network issue" >&2
        echo "" >&2
        echo "Try:" >&2
        echo "  export ACFS_REF=main  # use main branch" >&2
        echo "  export ACFS_REF=v1.0  # use a tag" >&2
        exit 1
    fi

    local short_sha="${sha:0:12}"
    local install_url="https://raw.githubusercontent.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/${sha}/install.sh"

    echo ""
    echo "═════════════════════════════════════════════════════════════════"
    echo "                    ACFS Pinned Reference"
    echo "═════════════════════════════════════════════════════════════════"
    echo ""
    echo "  Requested ref:  ${ACFS_REF_INPUT:-$ACFS_REF}"
    echo "  Resolved SHA:   ${short_sha}"
    if [[ -n "${ACFS_COMMIT_SHA_FULL:-}" ]]; then
        echo "  Full SHA:       ${ACFS_COMMIT_SHA_FULL}"
    fi
    if [[ -n "${ACFS_COMMIT_DATE:-}" ]]; then
        echo "  Commit date:    ${ACFS_COMMIT_DATE}"
    fi
    if [[ -n "${ACFS_COMMIT_AGE:-}" ]]; then
        echo "  Commit age:     ${ACFS_COMMIT_AGE}"
    fi
    echo ""
    echo "─────────────────────────────────────────────────────────────────"
    echo "Copy-paste this command to install from this exact commit:"
    echo ""
    echo "  curl -fsSL \"${install_url}\" | ACFS_REF=\"${sha}\" bash -s -- --yes --mode vibe"
    echo ""
    echo "Or with environment variable:"
    echo ""
    echo "  export ACFS_REF=\"${sha}\""
    echo "  curl -fsSL \"https://agent-flywheel.com/install\" | bash -s -- --yes --mode vibe"
    echo ""
    echo "─────────────────────────────────────────────────────────────────"
    echo ""
    echo "Tip: Pinned refs ensure reproducible installs across machines."
    echo "     Use tags (e.g., v1.0.0) for stable releases."
    echo ""
}

# ============================================================
# Logging functions (with gum enhancement)
# ============================================================
log_step() {
    local step="${1:-}"
    local message="${2:-}"

    # Allow single-arg usage: treat the arg as the message
    if [[ -z "$message" ]]; then
        message="$step"
        step="*"
    fi

    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_PRIMARY" --bold "[$step]" | tr -d '\n' >&2
        echo -n " " >&2
        gum style "$message" >&2
    else
        echo -e "${BLUE}[$step]${NC} $message" >&2
    fi
}

log_detail() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_MUTED" --margin "0 0 0 4" "→ $1" >&2
    else
        echo -e "${GRAY}    → $1${NC}" >&2
    fi
}

log_info() {
    log_detail "$1"
}

log_success() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_SUCCESS" --bold "✓ $1" >&2
    else
        echo -e "${GREEN}✓ $1${NC}" >&2
    fi
}

log_warn() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_WARNING" "⚠ $1" >&2
    else
        echo -e "${YELLOW}⚠ $1${NC}" >&2
    fi
}

log_error() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_ERROR" --bold "✖ $1" >&2
    else
        echo -e "${RED}✖ $1${NC}" >&2
    fi
}

log_fatal() {
    log_error "$1"
    exit 1
}

log_section() {
    if [[ "$HAS_GUM" == "true" ]]; then
        echo "" >&2
        gum style --foreground "$ACFS_PRIMARY" --bold "═══ $1 ═══" >&2
    else
        echo "" >&2
        echo -e "${BLUE}═══ $1 ═══${NC}" >&2
    fi
}

# ============================================================
# Log file capture (tee stderr to file)
# ============================================================

# Initialize log file capture: tee stderr to a timestamped log file.
# After calling, all stderr output is captured to ACFS_LOG_FILE.
acfs_log_init() {
    local log_dir="${1:-${ACFS_HOME:+${ACFS_HOME}/logs}}"

    # Fallback if ACFS_HOME not set or empty
    if [[ -z "$log_dir" ]]; then
        log_dir="${ACFS_LOG_DIR:-/var/log/acfs}"
    fi

    # Create log directory
    mkdir -p "$log_dir" 2>/dev/null || return 1

    ACFS_LOG_FILE="${log_dir}/install-$(date +%Y%m%d_%H%M%S).log"
    export ACFS_LOG_FILE

    # Write log header
    {
        printf '=== ACFS Install Log ===\n'
        printf 'Started: %s\n' "$(date -Iseconds)"
        printf 'Version: %s\n' "${ACFS_VERSION:-unknown}"
        printf 'User: %s\n' "${TARGET_USER:-unknown}"
        printf 'Home: %s\n' "${TARGET_HOME:-unknown}"
        printf 'Mode: %s\n' "${MODE:-unknown}"
        printf '========================\n\n'
    } > "$ACFS_LOG_FILE" 2>/dev/null || return 1

    # Fix ownership so target user can read logs
    if [[ -n "${TARGET_USER:-}" ]] && [[ "$(id -u)" -eq 0 ]]; then
        chown "${TARGET_USER}:${TARGET_USER}" "$log_dir" "$ACFS_LOG_FILE" 2>/dev/null || true
    fi

    # Tee stderr: all stderr output goes to both terminal and log file.
    # fd 3 = original stderr (preserved for terminal output).
    exec 3>&2
    exec 2> >(tee -a "$ACFS_LOG_FILE" >&3)

    log_detail "Log file: $ACFS_LOG_FILE"
}

# Close log file capture and restore stderr.
# Strips ANSI color codes from the log for clean text output.
acfs_log_close() {
    # Restore original stderr if fd 3 is open
    if { true >&3; } 2>/dev/null; then
        exec 2>&3 3>&-
    fi

    if [[ -n "${ACFS_LOG_FILE:-}" ]] && [[ -f "$ACFS_LOG_FILE" ]]; then
        # Strip ANSI escape codes for clean log
        sed -i $'s/\033\[[0-9;]*m//g' "$ACFS_LOG_FILE" 2>/dev/null || true

        # Append footer
        {
            printf '\n========================\n'
            printf 'Finished: %s\n' "$(date -Iseconds)"
            printf '========================\n'
        } >> "$ACFS_LOG_FILE"

        # Fix ownership
        if [[ -n "${TARGET_USER:-}" ]] && [[ "$(id -u)" -eq 0 ]]; then
            chown "${TARGET_USER}:${TARGET_USER}" "$ACFS_LOG_FILE" 2>/dev/null || true
        fi
    fi
}

# ============================================================
# Install summary JSON (bd-31ps.3.2)
# ============================================================

# Emit a JSON summary of the install run for downstream tooling.
# Usage: acfs_summary_emit <status> [total_seconds]
#   status: "success" or "failure"
#   total_seconds: total wall-clock time (optional, default 0)
# Output: ~/.acfs/logs/install_summary_<timestamp>.json
acfs_summary_emit() {
    local status="$1"
    local total_seconds="${2:-0}"

    # Require jq (installed by ensure_base_deps before phases run)
    command -v jq &>/dev/null || return 1

    local summary_dir="${ACFS_HOME:-/home/${TARGET_USER:?}/.acfs}/logs"
    mkdir -p "$summary_dir" 2>/dev/null || return 1

    ACFS_SUMMARY_FILE="${summary_dir}/install_summary_$(date +%Y%m%d_%H%M%S).json"
    export ACFS_SUMMARY_FILE

    # Read phase data from state.json if available
    local phases_json="[]"
    local failure_json="null"
    if [[ -f "${ACFS_STATE_FILE:-}" ]] && command -v jq &>/dev/null; then
        # Build phases array: [{id, name, duration_seconds}] in completion order
        phases_json=$(jq -r '
            (.completed_phases // []) as $completed |
            (.phase_durations // {}) as $durations |
            [$completed[] | {id: ., duration_seconds: ($durations[.] // null)}]
        ' "$ACFS_STATE_FILE" 2>/dev/null) || phases_json="[]"

        # Build failure object if present with precise resume hint (bd-31ps.9.1)
        local failed_phase
        failed_phase=$(jq -r '.failed_phase // empty' "$ACFS_STATE_FILE" 2>/dev/null) || true
        if [[ -n "$failed_phase" ]]; then
            local resume_hint
            resume_hint=$(generate_resume_hint "$failed_phase" "")
            failure_json=$(jq -n \
                --arg phase "$failed_phase" \
                --arg step "$(jq -r '.failed_step // empty' "$ACFS_STATE_FILE" 2>/dev/null)" \
                --arg error "$(jq -r '.failed_error // empty' "$ACFS_STATE_FILE" 2>/dev/null)" \
                --arg resume_hint "$resume_hint" \
                '{phase: $phase, step: (if $step == "" then null else $step end), error: (if $error == "" then null else $error end), resume_hint: $resume_hint}')
        fi
    fi

    # Get Ubuntu version
    local ubuntu_version="unknown"
    if command -v lsb_release &>/dev/null; then
        ubuntu_version=$(lsb_release -rs 2>/dev/null) || ubuntu_version="unknown"
    fi

    # Construct the summary JSON
    jq -n \
        --argjson schema_version 1 \
        --arg status "$status" \
        --arg timestamp "$(date -Iseconds)" \
        --argjson total_seconds "$total_seconds" \
        --arg acfs_version "${ACFS_VERSION:-unknown}" \
        --arg mode "${MODE:-unknown}" \
        --arg ubuntu_version "$ubuntu_version" \
        --arg target_user "${TARGET_USER:-unknown}" \
        --arg target_home "${TARGET_HOME:-unknown}" \
        --argjson phases "$phases_json" \
        --argjson failure "$failure_json" \
        --arg log_file "${ACFS_LOG_FILE:-}" \
        '{
            schema_version: $schema_version,
            status: $status,
            timestamp: $timestamp,
            total_seconds: $total_seconds,
            environment: {
                acfs_version: $acfs_version,
                mode: $mode,
                ubuntu_version: $ubuntu_version,
                target_user: $target_user,
                target_home: $target_home
            },
            phases: $phases,
            failure: $failure,
            log_file: (if $log_file != "" then $log_file else null end)
        }' > "$ACFS_SUMMARY_FILE" 2>/dev/null || return 1

    # Fix ownership so target user can read
    if [[ -n "${TARGET_USER:-}" ]] && [[ "$(id -u)" -eq 0 ]]; then
        chown "${TARGET_USER}:${TARGET_USER}" "$ACFS_SUMMARY_FILE" 2>/dev/null || true
    fi

    log_detail "Summary: $ACFS_SUMMARY_FILE"
}

# ============================================================
# Resume Hint Generation (bd-31ps.9.1)
# ============================================================
# Generates a precise, copyable command to resume installation from failure.
# Includes all relevant flags to reproduce the original invocation.
generate_resume_hint() {
    local failed_phase="${1:-}"
    local failed_step="${2:-}"

    # Start with base command
    local cmd=""

    # Prefer curl|bash one-liner for curl invocations; local script for local runs
    if [[ -z "${SCRIPT_DIR:-}" ]]; then
        # curl|bash invocation - use one-liner format
        cmd="curl -sSL"
        if [[ -n "${ACFS_COMMIT_SHA_FULL:-}" ]]; then
            # Pin to exact commit SHA for reproducibility
            cmd="$cmd https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${ACFS_COMMIT_SHA_FULL}/install.sh"
        elif [[ -n "${ACFS_REF_INPUT:-}" && "${ACFS_REF_INPUT}" != "main" ]]; then
            cmd="$cmd https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${ACFS_REF_INPUT}/install.sh"
        else
            cmd="$cmd https://acfs.sh"
        fi
        cmd="$cmd | bash -s --"
    else
        # Local script invocation
        cmd="bash install.sh"
    fi

    # Always add --resume flag (skips completed phases via state.json)
    cmd="$cmd --resume"

    # Add mode if not default
    if [[ "${MODE:-vibe}" != "vibe" ]]; then
        cmd="$cmd --mode $MODE"
    fi

    # Add skip flags that were used
    [[ "${SKIP_POSTGRES:-false}" == "true" ]] && cmd="$cmd --skip-postgres"
    [[ "${SKIP_VAULT:-false}" == "true" ]] && cmd="$cmd --skip-vault"
    [[ "${SKIP_CLOUD:-false}" == "true" ]] && cmd="$cmd --skip-cloud"
    [[ "${SKIP_PREFLIGHT:-false}" == "true" ]] && cmd="$cmd --skip-preflight"
    [[ "${SKIP_UBUNTU_UPGRADE:-false}" == "true" ]] && cmd="$cmd --skip-ubuntu-upgrade"

    # Add --yes if original run was non-interactive
    [[ "${YES_MODE:-false}" == "true" ]] && cmd="$cmd --yes"

    # Add --strict if it was set
    [[ "${STRICT_MODE:-false}" == "true" ]] && cmd="$cmd --strict"

    echo "$cmd"
}

# Print the resume hint with explanation and copyable block
print_resume_hint() {
    local failed_phase="${1:-}"
    local failed_step="${2:-}"
    local resume_cmd
    resume_cmd=$(generate_resume_hint "$failed_phase" "$failed_step")

    log_info ""
    log_info "╔══════════════════════════════════════════════════════════════╗"
    log_info "║  To resume installation from this point:                     ║"
    log_info "╚══════════════════════════════════════════════════════════════╝"
    log_info ""
    log_info "  $resume_cmd"
    log_info ""

    if [[ -n "$failed_phase" ]]; then
        log_detail "Failed phase: $failed_phase"
    fi
    if [[ -n "$failed_step" ]]; then
        log_detail "Failed step: $failed_step"
    fi

    # Also update the summary JSON with the precise resume hint
    if [[ -f "${ACFS_STATE_FILE:-}" ]] && command -v jq &>/dev/null; then
        local tmp_state
        tmp_state=$(mktemp)
        if jq --arg hint "$resume_cmd" '.resume_hint = $hint' "$ACFS_STATE_FILE" > "$tmp_state" 2>/dev/null; then
            mv "$tmp_state" "$ACFS_STATE_FILE"
        else
            rm -f "$tmp_state"
        fi
    fi
}

# ============================================================
# Error handling
# ============================================================
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error ""
        if [[ "${SMOKE_TEST_FAILED:-false}" == "true" ]]; then
            log_error "ACFS installation completed, but the post-install smoke test failed."
        else
            log_error "ACFS installation failed!"
        fi
        log_error ""
        log_error "To debug:"
        if [[ -n "${ACFS_LOG_FILE:-}" ]] && [[ -f "${ACFS_LOG_FILE}" ]]; then
            log_error "  1. Check the log: cat $ACFS_LOG_FILE"
        elif [[ -d "$ACFS_LOG_DIR" ]]; then
            log_error "  1. Check the log: cat $ACFS_LOG_DIR/install.log"
        else
            log_error "  1. Re-run with increased verbosity for details"
        fi
        log_error "  2. If installed, run: acfs doctor (try as $TARGET_USER)"
        log_error "     (If you ran the installer as root: sudo -u $TARGET_USER -i bash -lc 'acfs doctor')"
        log_error ""
        # Print precise resume hint if available (bd-31ps.9.1)
        # Get failed phase from state if available
        local failed_phase=""
        local failed_step=""
        if [[ -f "${ACFS_STATE_FILE:-}" ]] && command -v jq &>/dev/null; then
            failed_phase=$(jq -r '.failed_phase // empty' "$ACFS_STATE_FILE" 2>/dev/null) || true
            failed_step=$(jq -r '.failed_step // empty' "$ACFS_STATE_FILE" 2>/dev/null) || true
        fi
        print_resume_hint "$failed_phase" "$failed_step"
        log_error ""
        # Emit failure summary (best-effort)
        acfs_summary_emit "failure" 0 2>/dev/null || true
    fi
    # Finalize log file (restore stderr, strip colors, add footer)
    acfs_log_close 2>/dev/null || true
}
trap cleanup EXIT

# ============================================================
# Parse arguments
# ============================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --yes|-y)
                YES_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --print)
                PRINT_MODE=true
                shift
                ;;
            --mode)
                if [[ -z "${2:-}" ]]; then
                    log_fatal "--mode requires a value (e.g., --mode vibe)"
                fi
                MODE="$2"
                case "$MODE" in
                    vibe|safe) ;;
                    *)
                        log_fatal "Invalid --mode '$MODE' (expected: vibe or safe)"
                        ;;
                esac
                shift 2
                ;;
            --skip-postgres)
                SKIP_POSTGRES=true
                shift
                ;;
            --skip-vault)
                SKIP_VAULT=true
                shift
                ;;
            --skip-cloud)
                SKIP_CLOUD=true
                shift
                ;;
            --resume)
                export ACFS_FORCE_RESUME=true
                shift
                ;;
            --force-reinstall)
                export ACFS_FORCE_REINSTALL=true
                shift
                ;;
            --reset-state)
                RESET_STATE_ONLY=true
                shift
                ;;
            --interactive)
                export ACFS_INTERACTIVE=true
                shift
                ;;
            --strict)
                # Treat all tools as critical - any checksum mismatch aborts
                # Related: bead 8mv, tools.sh ACFS_STRICT_MODE handling
                export ACFS_STRICT_MODE=true
                shift
                ;;
            --skip-preflight)
                SKIP_PREFLIGHT=true
                shift
                ;;
            --auto-fix)
                # Enable auto-fix with prompts (default for interactive)
                AUTO_FIX_MODE="prompt"
                shift
                ;;
            --no-auto-fix)
                # Disable auto-fix entirely - only show warnings
                AUTO_FIX_MODE="no"
                shift
                ;;
            --auto-fix-accept-all)
                # Non-interactive: fix all issues without prompting
                AUTO_FIX_MODE="yes"
                shift
                ;;
            --auto-fix-dry-run)
                # Show what auto-fix would do without executing
                AUTO_FIX_MODE="dry-run"
                shift
                ;;
            --checksums-ref|--checksums-ref=*)
                if [[ "$1" == "--checksums-ref" ]]; then
                    if [[ -z "${2:-}" ]]; then
                        log_fatal "--checksums-ref requires a ref (e.g., --checksums-ref main)"
                    fi
                    ACFS_CHECKSUMS_REF="$2"
                    shift 2
                else
                    ACFS_CHECKSUMS_REF="${1#*=}"
                    shift
                fi
                ACFS_CHECKSUMS_RAW="https://raw.githubusercontent.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/${ACFS_CHECKSUMS_REF}"
                export ACFS_CHECKSUMS_REF ACFS_CHECKSUMS_RAW
                ;;
            --pin-ref|--confirm-ref)
                # Print resolved SHA and pinned command, then exit
                PIN_REF_MODE=true
                shift
                ;;
            --skip-ubuntu-upgrade)
                # Skip automatic Ubuntu version upgrade (nb4)
                # shellcheck disable=SC2034  # used by run_ubuntu_upgrade_phase
                SKIP_UBUNTU_UPGRADE=true
                shift
                ;;
            --target-ubuntu|--target-ubuntu=*)
                # Set target Ubuntu version for auto-upgrade (nb4)
                if [[ "$1" == "--target-ubuntu" ]]; then
                    if [[ -z "${2:-}" ]]; then
                        log_fatal "--target-ubuntu requires a version (e.g., --target-ubuntu 25.10)"
                    fi
                    # shellcheck disable=SC2034  # used by run_ubuntu_upgrade_phase
                    TARGET_UBUNTU_VERSION="$2"
                    shift 2
                else
                    # Handle --target-ubuntu=25.10 format
                    # shellcheck disable=SC2034  # used by run_ubuntu_upgrade_phase
                    TARGET_UBUNTU_VERSION="${1#*=}"
                    shift
                fi
                ;;
            --list-modules)
                LIST_MODULES=true
                shift
                ;;
            --print-plan)
                PRINT_PLAN_MODE=true
                shift
                ;;
            --only)
                # Add module to ONLY_MODULES list (for manifest-driven selection)
                if [[ -z "${2:-}" ]]; then
                    log_fatal "--only requires a module ID"
                fi
                ONLY_MODULES+=("$2")
                shift 2
                ;;
            --only-phase)
                # Add phase to ONLY_PHASES list
                if [[ -z "${2:-}" ]]; then
                    log_fatal "--only-phase requires a phase number"
                fi
                ONLY_PHASES+=("$2")
                shift 2
                ;;
            --skip)
                # Add module to SKIP_MODULES list
                if [[ -z "${2:-}" ]]; then
                    log_fatal "--skip requires a module ID"
                fi
                SKIP_MODULES+=("$2")
                shift 2
                ;;
            --no-deps)
                # Disable automatic dependency resolution
                NO_DEPS=true
                shift
                ;;
            *)
                log_warn "Unknown option: $1"
                shift
                ;;
        esac
    done
}

# ============================================================
# Utility functions
# ============================================================
command_exists() {
    command -v "$1" &>/dev/null
}

# Interactive yes/no confirmation prompt
# Returns 0 for yes, 1 for no
confirm() {
    local prompt="${1:-Continue?}"
    local response=""

    if [[ -t 0 ]]; then
        read -r -p "$prompt [y/N] " response < /dev/tty
    else
        # Non-interactive mode - default to no
        return 1
    fi

    [[ "$response" =~ ^[Yy]$ ]]
}

# ============================================================
# Auto-Fix Handler (bd-19y9.3.4)
# Dispatches auto-fix actions based on AUTO_FIX_MODE
# ============================================================
#
# Usage: handle_autofix <fix_name> <description> <fix_function>
#   fix_name     - Short identifier (e.g., "unattended_upgrades")
#   description  - Human-readable description of the issue
#   fix_function - Function to call for fixing (receives "fix" or "dry-run" as $1)
#
# Returns:
#   0 - Issue was fixed (or dry-run shown)
#   1 - User declined to fix or auto-fix is disabled
#   2 - Fix function failed
#
handle_autofix() {
    local fix_name="$1"
    local description="$2"
    local fix_function="$3"

    case "${AUTO_FIX_MODE:-prompt}" in
        "no")
            # Just warn, don't fix
            log_warn "[PRE-FLIGHT] $description"
            log_warn "[PRE-FLIGHT] Use --auto-fix to resolve automatically"
            return 1
            ;;
        "dry-run")
            # Show what would be done
            log_info "[DRY-RUN] Would auto-fix: $description"
            if type -t "$fix_function" &>/dev/null; then
                "$fix_function" "dry-run" || true
            fi
            return 0
            ;;
        "yes")
            # Fix automatically without prompting
            log_info "[AUTO-FIX] Fixing: $description"
            if type -t "$fix_function" &>/dev/null; then
                if "$fix_function" "fix"; then
                    log_success "[AUTO-FIX] Fixed: $fix_name"
                    return 0
                else
                    log_error "[AUTO-FIX] Failed to fix: $fix_name"
                    return 2
                fi
            else
                log_error "[AUTO-FIX] Fix function not found: $fix_function"
                return 2
            fi
            ;;
        "prompt"|*)
            # Interactive: ask user before fixing
            log_warn "[PRE-FLIGHT] $description"
            if [[ "${YES_MODE:-false}" == "true" ]]; then
                # In --yes mode, default to accepting auto-fix
                log_info "[AUTO-FIX] Fixing (--yes mode): $description"
                if type -t "$fix_function" &>/dev/null; then
                    if "$fix_function" "fix"; then
                        log_success "[AUTO-FIX] Fixed: $fix_name"
                        return 0
                    else
                        log_error "[AUTO-FIX] Failed to fix: $fix_name"
                        return 2
                    fi
                fi
            else
                # Interactive prompt
                local response=""
                printf "%b" "${ACFS_YELLOW:-}Would you like ACFS to fix this automatically? [Y/n] ${ACFS_NC:-}" >&2
                read -r response </dev/tty 2>/dev/null || response="y"
                case "${response:-y}" in
                    [Yy]|[Yy][Ee][Ss]|"")
                        log_info "[AUTO-FIX] Fixing: $description"
                        if type -t "$fix_function" &>/dev/null; then
                            if "$fix_function" "fix"; then
                                log_success "[AUTO-FIX] Fixed: $fix_name"
                                return 0
                            else
                                log_error "[AUTO-FIX] Failed to fix: $fix_name"
                                return 2
                            fi
                        fi
                        ;;
                    *)
                        log_info "[PRE-FLIGHT] Skipped auto-fix for: $fix_name"
                        return 1
                        ;;
                esac
            fi
            ;;
    esac
}

# Export for use in preflight and autofix scripts
export -f handle_autofix 2>/dev/null || true

# ============================================================
# Environment Detection (mjt.5.3)
# Sets up paths for libs and generated scripts BEFORE sourcing them.
# ============================================================
detect_environment() {
    # Set lib and generated script directories based on context
    if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]]; then
        # curl|bash mode: use bootstrap archive
        ACFS_LIB_DIR="$ACFS_BOOTSTRAP_DIR/scripts/lib"
        ACFS_GENERATED_DIR="$ACFS_BOOTSTRAP_DIR/scripts/generated"
        ACFS_ASSETS_DIR="${ACFS_ASSETS_DIR:-$ACFS_BOOTSTRAP_DIR/acfs}"
        ACFS_CHECKSUMS_YAML="${ACFS_CHECKSUMS_YAML:-$ACFS_BOOTSTRAP_DIR/checksums.yaml}"
        ACFS_MANIFEST_YAML="${ACFS_MANIFEST_YAML:-$ACFS_BOOTSTRAP_DIR/acfs.manifest.yaml}"
    elif [[ -n "${SCRIPT_DIR:-}" ]]; then
        # Local checkout mode
        ACFS_LIB_DIR="$SCRIPT_DIR/scripts/lib"
        ACFS_GENERATED_DIR="$SCRIPT_DIR/scripts/generated"
        ACFS_ASSETS_DIR="$SCRIPT_DIR/acfs"
        ACFS_CHECKSUMS_YAML="$SCRIPT_DIR/checksums.yaml"
        ACFS_MANIFEST_YAML="$SCRIPT_DIR/acfs.manifest.yaml"
    else
        # Fallback: current directory
        ACFS_LIB_DIR="./scripts/lib"
        ACFS_GENERATED_DIR="./scripts/generated"
        ACFS_ASSETS_DIR="./acfs"
        ACFS_CHECKSUMS_YAML="./checksums.yaml"
        ACFS_MANIFEST_YAML="./acfs.manifest.yaml"
    fi

    export ACFS_LIB_DIR ACFS_GENERATED_DIR ACFS_ASSETS_DIR ACFS_CHECKSUMS_YAML ACFS_MANIFEST_YAML

    # Source minimal libs in correct order (logging, then helpers)
    if [[ -f "$ACFS_LIB_DIR/logging.sh" ]]; then
        # shellcheck source=scripts/lib/logging.sh
        source "$ACFS_LIB_DIR/logging.sh"
    fi

    if [[ -f "$ACFS_LIB_DIR/security.sh" ]]; then
        # shellcheck source=scripts/lib/security.sh
        source "$ACFS_LIB_DIR/security.sh"
    fi

    if [[ -f "$ACFS_LIB_DIR/contract.sh" ]]; then
        # shellcheck source=scripts/lib/contract.sh
        source "$ACFS_LIB_DIR/contract.sh"
    fi

    if [[ -f "$ACFS_LIB_DIR/install_helpers.sh" ]]; then
        # shellcheck source=scripts/lib/install_helpers.sh
        source "$ACFS_LIB_DIR/install_helpers.sh"
    fi

    if [[ -f "$ACFS_LIB_DIR/user.sh" ]]; then
        # shellcheck source=scripts/lib/user.sh
        source "$ACFS_LIB_DIR/user.sh"
    fi

    # Source state management for resume/progress tracking (mjt.5.8)
    if [[ -f "$ACFS_LIB_DIR/state.sh" ]]; then
        # shellcheck source=scripts/lib/state.sh
        source "$ACFS_LIB_DIR/state.sh"
    fi

    # Source error pattern matcher (report.sh uses get_suggested_fix when available).
    if [[ -f "$ACFS_LIB_DIR/errors.sh" ]]; then
        # shellcheck source=scripts/lib/errors.sh
        source "$ACFS_LIB_DIR/errors.sh"
    fi

    # Source structured failure/success reporting (mjt.5.8).
    if [[ -f "$ACFS_LIB_DIR/report.sh" ]]; then
        # shellcheck source=scripts/lib/report.sh
        source "$ACFS_LIB_DIR/report.sh"
    fi

    # Source error tracking for try_step wrappers (mjt.5.8)
    if [[ -f "$ACFS_LIB_DIR/error_tracking.sh" ]]; then
        # shellcheck source=scripts/lib/error_tracking.sh
        source "$ACFS_LIB_DIR/error_tracking.sh"
    fi

    # Source Ubuntu upgrade library from the same lib dir when available (nb4).
    if [[ -f "$ACFS_LIB_DIR/ubuntu_upgrade.sh" ]]; then
        # shellcheck source=scripts/lib/ubuntu_upgrade.sh
        source "$ACFS_LIB_DIR/ubuntu_upgrade.sh"
        export ACFS_UBUNTU_UPGRADE_LOADED=1
    fi

    # Source tailscale installer (bt5)
    if [[ -f "$ACFS_LIB_DIR/tailscale.sh" ]]; then
        # shellcheck source=scripts/lib/tailscale.sh
        source "$ACFS_LIB_DIR/tailscale.sh"
    fi

    # Source auto-fix modules (bd-19y9.3.4)
    if [[ -f "$ACFS_LIB_DIR/autofix.sh" ]]; then
        # shellcheck source=scripts/lib/autofix.sh
        source "$ACFS_LIB_DIR/autofix.sh"
        export ACFS_AUTOFIX_LOADED=1
    fi
    if [[ -f "$ACFS_LIB_DIR/autofix_unattended.sh" ]]; then
        # shellcheck source=scripts/lib/autofix_unattended.sh
        source "$ACFS_LIB_DIR/autofix_unattended.sh"
    fi
    if [[ -f "$ACFS_LIB_DIR/autofix_existing.sh" ]]; then
        # shellcheck source=scripts/lib/autofix_existing.sh
        source "$ACFS_LIB_DIR/autofix_existing.sh"
    fi

    # Source manifest index (data-only, safe to source)
    if [[ -f "$ACFS_GENERATED_DIR/manifest_index.sh" ]]; then
        # shellcheck source=scripts/generated/manifest_index.sh
        source "$ACFS_GENERATED_DIR/manifest_index.sh"
        ACFS_MANIFEST_INDEX_LOADED=true
    else
        ACFS_MANIFEST_INDEX_LOADED=false
    fi

    export ACFS_MANIFEST_INDEX_LOADED
}

# ============================================================
# Source Generated Installers (mjt.5.6)
# Loads generated category scripts for module functions.
# ============================================================
source_generated_installers() {
    if [[ "${ACFS_GENERATED_SOURCED:-false}" == "true" ]]; then
        return 0
    fi

    if [[ -z "${ACFS_GENERATED_DIR:-}" ]]; then
        log_warn "ACFS_GENERATED_DIR not set; cannot source generated installers"
        return 0
    fi

    if [[ ! -d "$ACFS_GENERATED_DIR" ]]; then
        log_warn "Generated installers directory not found: $ACFS_GENERATED_DIR"
        return 0
    fi

    local script=""
    local scripts=(
        "install_users.sh"
        "install_base.sh"
        "install_filesystem.sh"
        "install_shell.sh"
        "install_cli.sh"
        "install_network.sh"
        "install_lang.sh"
        "install_tools.sh"
        "install_agents.sh"
        "install_db.sh"
        "install_cloud.sh"
        "install_stack.sh"
        "install_acfs.sh"
    )

    for script in "${scripts[@]}"; do
        if [[ -f "$ACFS_GENERATED_DIR/$script" ]]; then
            # shellcheck source=/dev/null
            source "$ACFS_GENERATED_DIR/$script"
        fi
    done

    ACFS_GENERATED_SOURCED=true
    export ACFS_GENERATED_SOURCED
}

# ============================================================
# List Modules (mjt.5.3)
# Prints available modules from manifest_index.sh
# ============================================================
list_modules() {
    if [[ "${ACFS_MANIFEST_INDEX_LOADED:-false}" != "true" ]]; then
        echo "Error: Manifest index not loaded. Cannot list modules." >&2
        return 1
    fi

    echo "Available ACFS Modules"
    echo "======================"
    echo ""

    local current_phase=""
    local module=""
    local phase=""
    local category=""
    local deps=""
    local enabled=""
    local key=""
    local enabled_marker=""
    for module in "${ACFS_MODULES_IN_ORDER[@]}"; do
        # Use key variable to prevent arithmetic evaluation with dots
        key="$module"
        phase="${ACFS_MODULE_PHASE[$key]:-?}"
        category="${ACFS_MODULE_CATEGORY[$key]:-?}"
        deps="${ACFS_MODULE_DEPS[$key]:-none}"
        enabled="${ACFS_MODULE_DEFAULT[$key]:-1}"

        if [[ "$phase" != "$current_phase" ]]; then
            echo ""
            echo "Phase $phase:"
            current_phase="$phase"
        fi

        enabled_marker="+"
        if [[ "$enabled" == "0" || "$enabled" == "false" ]]; then
            enabled_marker="-"
        fi

        echo "  [$enabled_marker] $module ($category)"
        if [[ -n "$deps" ]] && [[ "$deps" != "none" ]]; then
            echo "      deps: $deps"
        fi
    done

    echo ""
    echo "Legend: [+] enabled by default, [-] optional"
    echo "Total: ${#ACFS_MODULES_IN_ORDER[@]} modules"
}

# ============================================================
# Print Plan (mjt.5.3)
# Prints the effective execution plan without running installs.
# ============================================================
print_execution_plan() {
    if [[ "${ACFS_MANIFEST_INDEX_LOADED:-false}" != "true" ]]; then
        echo "Error: Manifest index not loaded. Cannot print plan." >&2
        return 1
    fi

    echo "ACFS Installation Plan"
    echo "======================"
    echo ""
    echo "Mode: $MODE"
    echo "Selected modules: ${#ACFS_EFFECTIVE_PLAN[@]} of ${#ACFS_MODULES_IN_ORDER[@]} available"
    echo ""

    # Show selection settings if non-default
    if [[ ${#ONLY_MODULES[@]} -gt 0 ]]; then
        echo "Selection: --only ${ONLY_MODULES[*]}"
    elif [[ ${#ONLY_PHASES[@]} -gt 0 ]]; then
        echo "Selection: --only-phase ${ONLY_PHASES[*]}"
    fi
    if [[ ${#SKIP_MODULES[@]} -gt 0 ]]; then
        echo "Skipped:   --skip ${SKIP_MODULES[*]}"
    fi
    if [[ "${NO_DEPS:-false}" == "true" ]]; then
        echo "⚠ --no-deps: dependencies NOT auto-installed"
    fi
    echo ""
    echo "Execution order:"
    echo ""

    local idx=1
    local module phase func key reason
    for module in "${ACFS_EFFECTIVE_PLAN[@]}"; do
        # Use key variable to prevent arithmetic evaluation with dots
        key="$module"
        phase="${ACFS_MODULE_PHASE[$key]:-?}"
        func="${ACFS_MODULE_FUNC[$key]:-?}"
        reason="${ACFS_PLAN_REASON[$key]:-}"
        if [[ -n "$reason" ]]; then
            printf "  %2d. [Phase %s] %s -> %s()  (%s)\n" "$idx" "$phase" "$module" "$func" "$reason"
        else
            printf "  %2d. [Phase %s] %s -> %s()\n" "$idx" "$phase" "$module" "$func"
        fi
        ((++idx))  # Use ++idx to avoid exit on zero under set -e
    done

    echo ""
    echo "Legacy options (will be migrated to --skip):"
    echo "  --skip-postgres: $SKIP_POSTGRES"
    echo "  --skip-vault:    $SKIP_VAULT"
    echo "  --skip-cloud:    $SKIP_CLOUD"
    echo ""
    echo "This is a preview. Run without --print-plan to execute."
}

# ============================================================
# Auto-Fix Functions (bd-19y9.3.4)
# ============================================================
# Handles automatic fixing of pre-flight issues based on AUTO_FIX_MODE

# Handle a single auto-fix item based on current mode
# Usage: handle_autofix <fix_name> <description>
handle_autofix() {
    local fix_name="$1"
    local description="$2"
    local fix_func="autofix_${fix_name}_fix"

    case "$AUTO_FIX_MODE" in
        "no")
            log_warn "[PRE-FLIGHT] $description"
            log_warn "[PRE-FLIGHT] Use --auto-fix to resolve automatically"
            ;;
        "dry-run")
            log_info "[DRY-RUN] Would auto-fix: $description"
            if type "$fix_func" &>/dev/null; then
                "$fix_func" dry-run 2>&1 | while IFS= read -r line; do
                    log_detail "  $line"
                done
            fi
            ;;
        "yes")
            log_info "[AUTO-FIX] Fixing: $description"
            if type "$fix_func" &>/dev/null; then
                "$fix_func" fix
            else
                log_warn "[AUTO-FIX] Fix function not available: $fix_func"
            fi
            ;;
        "prompt")
            log_warn "[PRE-FLIGHT] $description"
            # In --yes mode, auto-accept the fix without prompting
            if [[ "${YES_MODE:-false}" == "true" ]]; then
                log_info "[AUTO-FIX] Fixing (--yes mode): $description"
                if type "$fix_func" &>/dev/null; then
                    "$fix_func" fix
                else
                    log_warn "[AUTO-FIX] Fix function not available: $fix_func"
                fi
            elif confirm "Would you like ACFS to fix this automatically?"; then
                log_info "[AUTO-FIX] Fixing: $description"
                if type "$fix_func" &>/dev/null; then
                    "$fix_func" fix
                fi
            else
                log_warn "[PRE-FLIGHT] Skipped auto-fix for: $description"
            fi
            ;;
    esac
}

# Run auto-fix checks before main preflight validation
run_autofix_checks() {
    # Skip if auto-fix modules not loaded
    if [[ "${ACFS_AUTOFIX_LOADED:-0}" != "1" ]]; then
        log_debug "Auto-fix modules not loaded, skipping auto-fix checks"
        return 0
    fi

    # Skip if auto-fix disabled
    if [[ "$AUTO_FIX_MODE" == "no" ]]; then
        log_debug "Auto-fix disabled via --no-auto-fix"
        return 0
    fi

    log_info "Running auto-fix pre-flight checks..."

    # Check for existing ACFS installation
    if type autofix_existing_acfs_needs_handling &>/dev/null; then
        if autofix_existing_acfs_needs_handling 2>/dev/null; then
            local version
            version=$(get_installed_version 2>/dev/null || echo "unknown")
            handle_autofix "existing" "Existing ACFS installation detected (version: $version)"
        fi
    fi

    # Check for unattended-upgrades issues
    if type autofix_unattended_upgrades_needs_fix &>/dev/null; then
        if autofix_unattended_upgrades_needs_fix 2>/dev/null; then
            handle_autofix "unattended_upgrades" "unattended-upgrades service may cause apt lock conflicts"
        fi
    fi

    # Add more auto-fix checks here as they are implemented
    # e.g., nvm/pyenv conflicts from bd-19y9.3.2

    log_debug "Auto-fix pre-flight checks complete"
}

# ============================================================
# Pre-Flight Validation
# ============================================================
# Runs system validation checks before installation begins.
# Related beads: agentic_coding_flywheel_setup-545

run_preflight_checks() {
    log_step "0/9" "Running pre-flight validation..."

    local preflight_script=""
    local preflight_tmp=""

    # Try to find preflight script in different locations
    if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -f "$ACFS_BOOTSTRAP_DIR/scripts/preflight.sh" ]]; then
        preflight_script="$ACFS_BOOTSTRAP_DIR/scripts/preflight.sh"
    elif [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "$SCRIPT_DIR/scripts/preflight.sh" ]]; then
        preflight_script="$SCRIPT_DIR/scripts/preflight.sh"
    elif [[ -f "./scripts/preflight.sh" ]]; then
        preflight_script="./scripts/preflight.sh"
    else
        # Download preflight script for curl | bash scenario (if curl available)
        if command -v curl &>/dev/null; then
            log_detail "Downloading preflight script..."
            if command -v mktemp &>/dev/null; then
                preflight_tmp="$(mktemp "${TMPDIR:-/tmp}/acfs-preflight.XXXXXX" 2>/dev/null)" || preflight_tmp=""
            fi
            if [[ -n "$preflight_tmp" ]] && acfs_curl -o "$preflight_tmp" "$ACFS_RAW/scripts/preflight.sh" 2>/dev/null; then
                chmod +x "$preflight_tmp"
                preflight_script="$preflight_tmp"
            else
                log_warn "Could not download preflight script - skipping checks"
                return 0
            fi
        else
            log_warn "curl not available - skipping preflight checks"
            return 0
        fi
    fi

    # Run preflight checks and capture exit code correctly
    # (can't use "if ! cmd; then exit_code=$?" because $? would be 0 from the negation)
    local exit_code=0
    bash "$preflight_script" || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo "" >&2
        log_error "Pre-flight validation failed!"
        echo "" >&2
        log_info "Run preflight checks for details:"
        log_info "  bash $preflight_script"
        echo "" >&2
        log_info "Use --skip-preflight to bypass (not recommended)"
        echo "" >&2
        exit 1
    fi

    # Cleanup downloaded preflight script on success
    if [[ -n "$preflight_tmp" ]]; then
        rm -f "$preflight_tmp"
    fi

    log_success "[0/9] Pre-flight validation passed"
    echo ""
}

ACFS_CURL_BASE_ARGS=(-fsSL)
if command -v curl &>/dev/null && curl --help all 2>/dev/null | grep -q -- '--proto'; then
    ACFS_CURL_BASE_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
fi

acfs_curl() {
    curl "${ACFS_CURL_BASE_ARGS[@]}" "$@"
}

# Automatic retry for transient network errors (fast total budget).
ACFS_CURL_RETRY_DELAYS=(0 5 15)

acfs_is_retryable_curl_exit_code() {
    local exit_code="${1:-0}"
    case "$exit_code" in
        6|7|28|35|52|56) return 0 ;; # DNS/connect/timeout/SSL/empty reply/recv error
        *) return 1 ;;
    esac
}

acfs_curl_with_retry() {
    local url="$1"
    local output_path="$2"

    if [[ -z "$url" || -z "$output_path" ]]; then
        log_error "acfs_curl_with_retry: missing url or output path"
        return 1
    fi

    local attempt delay exit_code
    local max_attempts="${#ACFS_CURL_RETRY_DELAYS[@]}"
    if (( max_attempts == 0 )); then
        ACFS_CURL_RETRY_DELAYS=(0 5 15)
        max_attempts="${#ACFS_CURL_RETRY_DELAYS[@]}"
    fi

    for ((attempt=0; attempt<max_attempts; attempt++)); do
        delay="${ACFS_CURL_RETRY_DELAYS[$attempt]}"
        if (( attempt > 0 )); then
            log_detail "Retry ${attempt}/${max_attempts} (waiting ${delay}s)..."
            sleep "$delay"
        fi

        if acfs_curl -o "$output_path" "$url"; then
            return 0
        fi

        exit_code=$?
        if ! acfs_is_retryable_curl_exit_code "$exit_code"; then
            return "$exit_code"
        fi
    done

    return 1
}

acfs_calculate_file_sha256() {
    local file_path="$1"

    if command_exists sha256sum; then
        sha256sum "$file_path" | cut -d' ' -f1
        return 0
    fi

    if command_exists shasum; then
        shasum -a 256 "$file_path" | cut -d' ' -f1
        return 0
    fi

    log_error "No SHA256 tool available (need sha256sum or shasum)"
    return 1
}

acfs_download_file_and_verify_sha256() {
    local url="$1"
    local output_path="$2"
    local expected_sha256="$3"
    local label="${4:-download}"

    if [[ -z "$url" || -z "$output_path" || -z "$expected_sha256" ]]; then
        log_error "acfs_download_file_and_verify_sha256: missing url, output path, or expected sha256"
        return 1
    fi

    if [[ "$url" != https://* ]]; then
        log_error "Security error: upstream URL is not HTTPS: $url"
        return 1
    fi

    if ! acfs_curl_with_retry "$url" "$output_path"; then
        log_error "Failed to download $label"
        log_detail "URL: $url"
        return 1
    fi

    local actual_sha256=""
    actual_sha256="$(acfs_calculate_file_sha256 "$output_path")" || actual_sha256=""

    if [[ -z "$actual_sha256" ]] || [[ "$actual_sha256" != "$expected_sha256" ]]; then
        log_error "Security error: checksum mismatch for $label"
        log_detail "URL: $url"
        log_detail "Expected: $expected_sha256"
        log_detail "Actual:   ${actual_sha256:-<missing>}"
        return 1
    fi

    return 0
}

bootstrap_repo_archive() {
    if [[ -n "${SCRIPT_DIR:-}" ]]; then
        return 0
    fi

    local ref="$ACFS_REF"
    # Cache-bust GitHub's CDN to ensure we get the latest archive
    # GitHub caches archives for up to 5 minutes; this ensures fresh downloads
    local cache_buster
    cache_buster="$(date +%s)"
    local archive_url="https://github.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/archive/${ref}.tar.gz?cb=${cache_buster}"
    local ref_safe="${ref//[^a-zA-Z0-9._-]/_}"
    local tmp_archive
    local tmp_dir

    if ! command_exists tar; then
        log_error "Bootstrap requires tar (install tar or run from a local checkout)"
        return 1
    fi

    # mktemp portability: BSD mktemp requires Xs at end of template; tar doesn't need a .tar.gz suffix.
    tmp_archive="$(mktemp "${TMPDIR:-/tmp}/acfs-archive-${ref_safe}.XXXXXX" 2>/dev/null)" || {
        log_fatal "Failed to create temp file for archive"
    }

    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/acfs-bootstrap-${ref_safe}.XXXXXX" 2>/dev/null)" || {
        log_fatal "Failed to create temp dir for extraction"
    }
    # Make bootstrap dir world-readable so ubuntu user can access scripts
    chmod 755 "$tmp_dir"

    log_step "Bootstrapping ACFS archive (${ref})"
    log_detail "Downloading ${archive_url}"

    if ! acfs_curl_with_retry "$archive_url" "$tmp_archive"; then
        log_error "Failed to download ACFS archive. Try again, or pin ACFS_REF to a tag/sha."
        return 1
    fi

    log_detail "Extracting runtime assets"
    if ! tar -xzf "$tmp_archive" -C "$tmp_dir" --strip-components=1 \
        --wildcards --wildcards-match-slash \
        "*/scripts/**" \
        "*/acfs/**" \
        "*/checksums.yaml" \
        "*/acfs.manifest.yaml" \
        "*/VERSION"; then
        log_error "Failed to extract ACFS bootstrap archive (tar error)"
        return 1
    fi

    if [[ ! -f "$tmp_dir/acfs.manifest.yaml" ]] || [[ ! -f "$tmp_dir/checksums.yaml" ]] || [[ ! -f "$tmp_dir/VERSION" ]]; then
        log_error "Bootstrap archive missing required manifest/checksums/VERSION files"
        return 1
    fi

    if [[ ! -f "$tmp_dir/scripts/generated/manifest_index.sh" ]]; then
        log_error "Bootstrap archive missing scripts/generated/manifest_index.sh"
        return 1
    fi

    log_detail "Validating extracted shell scripts (bash -n)"
    local shellcheck_failed=false
    while IFS= read -r -d '' script_file; do
        if ! bash -n "$script_file" >/dev/null 2>&1; then
            log_error "Syntax error in extracted script: $script_file"
            shellcheck_failed=true
            break
        fi
    done < <(find "$tmp_dir" -type f -name "*.sh" -print0)

    if [[ "$shellcheck_failed" == "true" ]]; then
        log_error "Bootstrap validation failed. Retry or pin ACFS_REF to a known-good tag/sha."
        return 1
    fi

    local manifest_sha expected_sha
    manifest_sha="$(acfs_calculate_file_sha256 "$tmp_dir/acfs.manifest.yaml")" || return 1
    expected_sha="$(grep -E '^ACFS_MANIFEST_SHA256=' "$tmp_dir/scripts/generated/manifest_index.sh" | head -n 1 | cut -d'=' -f2 | tr -d '\"' || true)"

    if [[ -z "$expected_sha" ]]; then
        log_error "Bootstrap manifest index missing ACFS_MANIFEST_SHA256"
        return 1
    fi

    if [[ "$manifest_sha" != "$expected_sha" ]]; then
        log_error "Bootstrap mismatch: generated scripts do not match manifest."
        log_detail "Expected: $expected_sha"
        log_detail "Actual:   $manifest_sha"
        log_detail "Fix: retry or pin ACFS_REF to a tag/sha to avoid mixed refs."
        return 1
    fi

    ACFS_BOOTSTRAP_DIR="$tmp_dir"
    ACFS_LIB_DIR="$tmp_dir/scripts/lib"
    ACFS_GENERATED_DIR="$tmp_dir/scripts/generated"
    ACFS_ASSETS_DIR="$tmp_dir/acfs"
    ACFS_CHECKSUMS_YAML="$tmp_dir/checksums.yaml"
    ACFS_MANIFEST_YAML="$tmp_dir/acfs.manifest.yaml"

    export ACFS_BOOTSTRAP_DIR ACFS_LIB_DIR ACFS_GENERATED_DIR ACFS_ASSETS_DIR ACFS_CHECKSUMS_YAML ACFS_MANIFEST_YAML

    log_success "Bootstrap archive ready"
    return 0
}

_acfs_install_asset_has_symlink_component_under_prefix() {
    local prefix="$1"
    local dest_path="$2"

    case "$dest_path" in
        "$prefix" | "$prefix"/*) ;;
        *) return 1 ;; # Not under prefix; no signal
    esac

    local rel="${dest_path#"$prefix"}"
    rel="${rel#/}"

    local current="$prefix"
    if [[ -L "$current" ]]; then
        return 0
    fi

    if [[ -z "$rel" ]]; then
        return 1
    fi

    local -a parts=()
    IFS='/' read -r -a parts <<< "$rel"
    local part=""

    for part in "${parts[@]}"; do
        [[ -n "$part" ]] || continue
        current="$current/$part"
        if [[ -L "$current" ]]; then
            return 0
        fi
    done

    return 1
}

install_asset() {
    local rel_path="$1"
    local dest_path="$2"

    # Security: Validate rel_path doesn't contain path traversal
    if [[ "$rel_path" == *".."* ]]; then
        log_error "install_asset: Invalid path (contains '..'): $rel_path"
        return 1
    fi

    if [[ -z "${ACFS_HOME:-}" ]] || [[ -z "${TARGET_HOME:-}" ]]; then
        log_error "install_asset: ACFS_HOME/TARGET_HOME not set (call init_target_paths first)"
        return 1
    fi

    # Security: Validate dest_path is under expected directories
    local allowed_prefixes=("$ACFS_HOME" "$TARGET_HOME" "/data" "/usr/local/bin")
    local valid_dest=false
    for prefix in "${allowed_prefixes[@]}"; do
        [[ -n "$prefix" ]] || continue
        case "$dest_path" in
            "$prefix" | "$prefix"/*)
                valid_dest=true
                break
                ;;
        esac
    done
    if [[ "$valid_dest" != "true" ]]; then
        log_error "install_asset: Destination outside allowed paths: $dest_path"
        return 1
    fi

    # If running with elevated privileges, refuse to write through symlink path
    # components for sensitive destinations (prevents symlink clobber attacks).
    if [[ $EUID -eq 0 ]]; then
        if _acfs_install_asset_has_symlink_component_under_prefix "$ACFS_HOME" "$dest_path" || \
           _acfs_install_asset_has_symlink_component_under_prefix "$TARGET_HOME" "$dest_path" || \
           _acfs_install_asset_has_symlink_component_under_prefix "/usr/local/bin" "$dest_path"; then
            log_error "install_asset: Refusing to write through symlink path component: $dest_path"
            return 1
        fi
    fi

    local dest_dir
    dest_dir="$(dirname "$dest_path")"

    local sudo_cmd="${SUDO:-}"
    if [[ -z "$sudo_cmd" ]] && [[ $EUID -ne 0 ]] && command -v sudo &>/dev/null; then
        sudo_cmd="sudo"
    fi

    local need_sudo=false
    if [[ -e "$dest_path" ]]; then
        [[ -w "$dest_path" ]] || need_sudo=true
    else
        [[ -w "$dest_dir" ]] || need_sudo=true
    fi

    if [[ "$need_sudo" == "true" ]] && [[ -z "$sudo_cmd" ]]; then
        log_error "install_asset: Destination not writable and sudo not available: $dest_path"
        return 1
    fi

    if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -f "$ACFS_BOOTSTRAP_DIR/$rel_path" ]]; then
        if [[ "$need_sudo" == "true" ]]; then
            if ! $sudo_cmd cp "$ACFS_BOOTSTRAP_DIR/$rel_path" "$dest_path"; then
                log_error "install_asset: Failed to copy from bootstrap: $rel_path"
                return 1
            fi
        elif ! cp "$ACFS_BOOTSTRAP_DIR/$rel_path" "$dest_path"; then
            log_error "install_asset: Failed to copy from bootstrap: $rel_path"
            return 1
        fi
    elif [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "$SCRIPT_DIR/$rel_path" ]]; then
        if [[ "$need_sudo" == "true" ]]; then
            if ! $sudo_cmd cp "$SCRIPT_DIR/$rel_path" "$dest_path"; then
                log_error "install_asset: Failed to copy from script dir: $rel_path"
                return 1
            fi
        elif ! cp "$SCRIPT_DIR/$rel_path" "$dest_path"; then
            log_error "install_asset: Failed to copy from script dir: $rel_path"
            return 1
        fi
    else
        if [[ "$need_sudo" == "true" ]]; then
            if ! $sudo_cmd curl "${ACFS_CURL_BASE_ARGS[@]}" -o "$dest_path" "$ACFS_RAW/$rel_path"; then
                log_error "install_asset: Failed to download: $rel_path"
                return 1
            fi
        elif ! acfs_curl -o "$dest_path" "$ACFS_RAW/$rel_path"; then
            log_error "install_asset: Failed to download: $rel_path"
            return 1
        fi
    fi

    # Verify the file was actually created
    if [[ ! -f "$dest_path" ]]; then
        log_error "install_asset: File not created: $dest_path"
        return 1
    fi
}

install_checksums_yaml() {
    local dest_path="$1"

    if [[ -z "$dest_path" ]]; then
        log_error "install_checksums_yaml: Missing destination path"
        return 1
    fi

    # If checksums ref matches the install ref, use the standard asset path.
    if [[ -z "${ACFS_CHECKSUMS_REF:-}" || -z "${ACFS_REF_INPUT:-}" || "$ACFS_CHECKSUMS_REF" == "$ACFS_REF_INPUT" ]]; then
        install_asset "checksums.yaml" "$dest_path"
        return $?
    fi

    # Otherwise, fetch checksums from the dedicated checksums ref.
    local content=""
    content="$(acfs_fetch_fresh_checksums_via_api)" || {
        local cb
        cb="$(date +%s)"
        content="$(acfs_fetch_url_content "$ACFS_CHECKSUMS_RAW/checksums.yaml?cb=${cb}")" || {
            log_error "Failed to fetch checksums.yaml from ref '${ACFS_CHECKSUMS_REF}'"
            return 1
        }
    }

    local dest_dir
    dest_dir="$(dirname "$dest_path")"

    local sudo_cmd="${SUDO:-}"
    if [[ -z "$sudo_cmd" ]] && [[ $EUID -ne 0 ]] && command -v sudo &>/dev/null; then
        sudo_cmd="sudo"
    fi

    local need_sudo=false
    if [[ -e "$dest_path" ]]; then
        [[ -w "$dest_path" ]] || need_sudo=true
    else
        [[ -w "$dest_dir" ]] || need_sudo=true
    fi

    if [[ "$need_sudo" == "true" ]]; then
        printf '%s' "$content" | $sudo_cmd tee "$dest_path" >/dev/null
    else
        printf '%s' "$content" > "$dest_path"
    fi

    if [[ ! -f "$dest_path" ]]; then
        log_error "install_checksums_yaml: File not created: $dest_path"
        return 1
    fi
}

run_as_target() {
    local user="$TARGET_USER"
    local user_home="${TARGET_HOME:-/home/$user}"

    # Environment variables to set for target user commands
    # UV_NO_CONFIG prevents uv from looking for config in /root when running via sudo
    # HOME is set explicitly to ensure consistent home directory
    local -a env_args=("UV_NO_CONFIG=1" "HOME=$user_home")

    # Pass ACFS context variables to target user environment
    if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]]; then env_args+=("ACFS_BOOTSTRAP_DIR=$ACFS_BOOTSTRAP_DIR"); fi
    if [[ -n "${SCRIPT_DIR:-}" ]]; then env_args+=("SCRIPT_DIR=$SCRIPT_DIR"); fi
    if [[ -n "${ACFS_RAW:-}" ]]; then env_args+=("ACFS_RAW=$ACFS_RAW"); fi
    if [[ -n "${ACFS_VERSION:-}" ]]; then env_args+=("ACFS_VERSION=$ACFS_VERSION"); fi

    # Already the target user
    if [[ "$(whoami)" == "$user" ]]; then
        cd "$user_home" 2>/dev/null || true
        env "${env_args[@]}" "$@"
        return $?
    fi

    # IMPORTANT: Do NOT use sudo -i as it sources profile files (.profile, .bashrc)
    # which may be corrupted by third-party installers (e.g., uv adds lines that
    # reference non-existent files). Instead:
    # - Use sudo -u to switch user without sourcing profiles
    # - Set HOME explicitly in the environment
    # - Use sh -c to cd to home directory before executing
    #
    # The sh -c wrapper: 'cd "$HOME" && exec "$@"' _ "$@"
    # - First $@ expands inside sh -c to become positional params
    # - _ is $0 (script name placeholder)
    # - exec "$@" replaces sh with the target command, preserving stdin
    if command_exists sudo; then
        # shellcheck disable=SC2016  # $HOME/$@ expand inside sh -c
        sudo -u "$user" env "${env_args[@]}" sh -c 'cd "$HOME" 2>/dev/null; exec "$@"' _ "$@"
        return $?
    fi

    # Fallbacks (root-only typically)
    # Note: Avoid -l flag to prevent sourcing profiles
    if command_exists runuser; then
        # shellcheck disable=SC2016  # $HOME/$@ expand inside sh -c
        runuser -u "$user" -- env "${env_args[@]}" sh -c 'cd "$HOME" 2>/dev/null; exec "$@"' _ "$@"
        return $?
    fi

    # su without - to avoid sourcing login shell profiles
    local env_assignments=""
    local kv=""
    for kv in "${env_args[@]}"; do
        env_assignments+=" $(printf '%q' "$kv")"
    done
    env_assignments="${env_assignments# }"
    local user_home_q
    user_home_q=$(printf '%q' "$user_home")
    su "$user" -c "cd $user_home_q 2>/dev/null; env $env_assignments $(printf '%q ' "$@")"
}

# ============================================================
# Upstream installer verification (checksums.yaml)
# ============================================================

declare -A ACFS_UPSTREAM_URLS=()
declare -A ACFS_UPSTREAM_SHA256=()
ACFS_UPSTREAM_LOADED=false

acfs_calculate_sha256() {
    if command_exists sha256sum; then
        sha256sum | cut -d' ' -f1
        return 0
    fi

    if command_exists shasum; then
        shasum -a 256 | cut -d' ' -f1
        return 0
    fi

    log_error "No SHA256 tool available (need sha256sum or shasum)"
    return 1
}

acfs_fetch_url_content() {
    local url="$1"

    if [[ "$url" != https://* ]]; then
        log_error "Security error: upstream URL is not HTTPS: $url"
        return 1
    fi

    local sentinel="__ACFS_EOF_SENTINEL__"
    local max_attempts="${#ACFS_CURL_RETRY_DELAYS[@]}"
    local retries=$((max_attempts - 1))

    local attempt delay
    for ((attempt=0; attempt<max_attempts; attempt++)); do
        delay="${ACFS_CURL_RETRY_DELAYS[$attempt]}"
        if (( attempt > 0 )); then
            log_info "Retry ${attempt}/${retries} for fetching upstream URL (waiting ${delay}s)..."
            sleep "$delay"
        fi

        local content status=0
        # IMPORTANT: keep this `curl` call set -e-safe so transient failures
        # don't abort the installer before our retry loop can run.
        content="$(
            acfs_curl "$url" 2>/dev/null || exit $?
            printf '%s' "$sentinel"
        )" || status=$?

        if (( status == 0 )) && [[ "$content" == *"$sentinel" ]]; then
            (( attempt > 0 )) && log_info "Succeeded on retry ${attempt} for fetching upstream URL"
            printf '%s' "${content%"$sentinel"}"
            return 0
        fi

        if ! acfs_is_retryable_curl_exit_code "$status"; then
            log_error "Failed to fetch upstream URL: $url"
            return 1
        fi
    done

    log_error "Failed to fetch upstream URL after ${max_attempts} attempts: $url"
    return 1
}

# Fetch checksums.yaml directly via GitHub API (bypasses CDN caching entirely).
# This is used as a fallback when cached checksums don't match upstream.
# Uses ACFS_CHECKSUMS_REF to avoid stale checksums when ACFS_REF is pinned.
# Uses the raw content header to get the file directly without base64 encoding.
acfs_fetch_fresh_checksums_via_api() {
    local api_url="https://api.github.com/repos/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/contents/checksums.yaml?ref=${ACFS_CHECKSUMS_REF}"

    # Use application/vnd.github.raw to get raw file content directly (no base64)
    local content
    content="$(curl -fsSL \
        -H "Accept: application/vnd.github.raw" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$api_url" 2>/dev/null)" || {
        log_detail "GitHub API request failed for checksums.yaml"
        return 1
    }

    if [[ -z "$content" ]]; then
        log_detail "Empty content from GitHub API"
        return 1
    fi

    # Verify it looks like valid checksums.yaml (should start with a comment or "installers:")
    if [[ ! "$content" =~ ^[[:space:]]*(#|installers:) ]]; then
        log_detail "GitHub API returned unexpected content format"
        return 1
    fi

    printf '%s' "$content"
}

# Parse checksums.yaml content into associative arrays.
# Takes YAML content as argument, populates ACFS_UPSTREAM_URLS and ACFS_UPSTREAM_SHA256.
acfs_parse_checksums_content() {
    local content="$1"
    local in_installers=false
    local current_tool=""

    # Clear existing entries for fresh parse
    ACFS_UPSTREAM_URLS=()
    ACFS_UPSTREAM_SHA256=()

    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        if [[ "$line" =~ ^installers: ]]; then
            in_installers=true
            continue
        fi
        if [[ "$in_installers" != "true" ]]; then
            continue
        fi

        if [[ "$line" =~ ^[[:space:]]{2}([a-z_]+):[[:space:]]*$ ]]; then
            current_tool="${BASH_REMATCH[1]}"
            continue
        fi

        [[ -n "$current_tool" ]] || continue

        # Robust parsing: handle quoted or unquoted values, strip comments
        if [[ "$line" =~ ^[[:space:]]*url:[[:space:]]*(.*)$ ]]; then
            local val="${BASH_REMATCH[1]}"
            val="${val%%#*}"                    # Strip comments
            val="${val%"${val##*[![:space:]]}"}" # Trim trailing space
            val="${val#"${val%%[![:space:]]*}"}" # Trim leading space
            val="${val%\"}" val="${val#\"}"      # Strip double quotes
            val="${val%\'}" val="${val#\'}"      # Strip single quotes
            
            if [[ -n "$val" ]]; then
                ACFS_UPSTREAM_URLS["$current_tool"]="$val"
            fi
            continue
        fi

        if [[ "$line" =~ ^[[:space:]]*sha256:[[:space:]]*(.*)$ ]]; then
            local val="${BASH_REMATCH[1]}"
            val="${val%%#*}"
            val="${val%"${val##*[![:space:]]}"}"
            val="${val#"${val%%[![:space:]]*}"}"
            val="${val%\"}" val="${val#\"}"
            val="${val%\'}" val="${val#\'}"

            if [[ -n "$val" ]]; then
                ACFS_UPSTREAM_SHA256["$current_tool"]="$val"
            fi
            continue
        fi
    done <<< "$content"
}

acfs_load_upstream_checksums() {
    if [[ "$ACFS_UPSTREAM_LOADED" == "true" ]]; then
        return 0
    fi

    local content=""
    local checksums_file=""
    local checksums_source="unknown"
    local prefer_local_checksums=true

    # If checksums ref differs from the install ref, avoid using bootstrapped/local
    # checksums which may be stale for fast-moving upstream installers.
    if [[ -n "${ACFS_CHECKSUMS_REF:-}" && -n "${ACFS_REF_INPUT:-}" && "$ACFS_CHECKSUMS_REF" != "$ACFS_REF_INPUT" ]]; then
        prefer_local_checksums=false
        log_detail "Using checksums from ref '${ACFS_CHECKSUMS_REF}' (install ref: '${ACFS_REF_INPUT}')"
    fi

    if [[ "$prefer_local_checksums" == "true" && -n "${ACFS_CHECKSUMS_YAML:-}" ]] && [[ -r "$ACFS_CHECKSUMS_YAML" ]]; then
        checksums_file="$ACFS_CHECKSUMS_YAML"
        checksums_source="bootstrap"
    elif [[ "$prefer_local_checksums" == "true" && -n "${SCRIPT_DIR:-}" ]] && [[ -r "$SCRIPT_DIR/checksums.yaml" ]]; then
        checksums_file="$SCRIPT_DIR/checksums.yaml"
        checksums_source="local"
    elif [[ "$prefer_local_checksums" == "true" && -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -r "$ACFS_BOOTSTRAP_DIR/checksums.yaml" ]]; then
        checksums_file="$ACFS_BOOTSTRAP_DIR/checksums.yaml"
        checksums_source="bootstrap"
    fi

    if [[ -n "$checksums_file" ]]; then
        content="$(cat "$checksums_file")"
    else
        # Fetch via GitHub API (bypasses CDN caching entirely)
        content="$(acfs_fetch_fresh_checksums_via_api)" || {
            # Fallback to raw.githubusercontent.com with cache-bust
            local cb
            cb="$(date +%s)"
            content="$(acfs_fetch_url_content "$ACFS_CHECKSUMS_RAW/checksums.yaml?cb=${cb}")" || {
                log_error "Failed to fetch checksums.yaml from any source"
                return 1
            }
            checksums_source="raw-cdn"
        }
        # If we didn't fall back to raw-cdn, the API succeeded
        [[ "$checksums_source" == "unknown" ]] && checksums_source="github-api"
    fi

    acfs_parse_checksums_content "$content"

    local required_tools=(
        atuin bun bv caam cass claude cm dcg mcp_agent_mail ntm ohmyzsh rust slb ubs uv zoxide
    )
    local missing_required_tools=false
    local tool
    for tool in "${required_tools[@]}"; do
        if [[ -z "${ACFS_UPSTREAM_URLS[$tool]:-}" ]] || [[ -z "${ACFS_UPSTREAM_SHA256[$tool]:-}" ]]; then
            log_error "checksums.yaml missing entry for '$tool'"
            missing_required_tools=true
        fi
    done
    if [[ "$missing_required_tools" == "true" ]]; then
        return 1
    fi

    ACFS_UPSTREAM_LOADED=true
    return 0
}

#
# Upstream installers are pinned by checksums.yaml.
# On checksum mismatch, we attempt a fresh fetch via GitHub API to handle CDN caching.
# If still mismatched after fresh fetch, we fail closed (never execute unverified scripts).

acfs_run_verified_upstream_script_as_target() {
    local tool="$1"
    local runner="$2"
    shift 2 || true

    acfs_load_upstream_checksums

    local url="${ACFS_UPSTREAM_URLS[$tool]:-}"
    local expected_sha256="${ACFS_UPSTREAM_SHA256[$tool]:-}"
    if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then
        log_error "No checksum recorded for upstream installer: $tool"
        return 1
    fi

    # Preserve trailing newlines when capturing remote script content.
    # Bash command substitution trims trailing newlines, which would change the
    # checksum we compute vs the exact bytes we execute. Append an EOF sentinel
    # so the captured output never ends with a newline, then strip it.
    local sentinel="__ACFS_EOF_SENTINEL__"
    local content_with_sentinel
    content_with_sentinel="$(
        acfs_fetch_url_content "$url" || exit $?
        printf '%s' "$sentinel"
    )" || return 1

    if [[ "$content_with_sentinel" != *"$sentinel" ]]; then
        log_error "Failed to fetch upstream URL: $url"
        return 1
    fi

    local content="${content_with_sentinel%"$sentinel"}"

    local actual_sha256
    actual_sha256="$(printf '%s' "$content" | acfs_calculate_sha256)" || return 1

    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        # Checksum mismatch - but this might be due to CDN caching of our checksums.yaml.
        # Try fetching FRESH checksums directly via GitHub API (bypasses all CDN caching).
        log_detail "Checksum mismatch for '$tool' - fetching fresh checksums via GitHub API..."

        local fresh_content
        fresh_content="$(acfs_fetch_fresh_checksums_via_api)" || {
            log_detail "GitHub API fallback failed, cannot verify with fresh checksums"
            log_error "Security error: checksum mismatch for '$tool'"
            log_detail "URL: $url"
            log_detail "Expected: $expected_sha256"
            log_detail "Actual:   $actual_sha256"
            log_error "Refusing to execute unverified installer script."
            return 1
        }

        # Parse fresh checksums and get the updated expected hash
        acfs_parse_checksums_content "$fresh_content"
        local fresh_expected_sha256="${ACFS_UPSTREAM_SHA256[$tool]:-}"

        if [[ -z "$fresh_expected_sha256" ]]; then
            log_error "Fresh checksums.yaml missing entry for '$tool'"
            return 1
        fi

        # Re-verify with fresh checksum
        if [[ "$actual_sha256" == "$fresh_expected_sha256" ]]; then
            log_success "Verified '$tool' with fresh checksums from GitHub API"
            # Note: ACFS_UPSTREAM_SHA256 already updated by acfs_parse_checksums_content above
        else
            # Still doesn't match even with fresh checksums - this is a real problem
            log_error "Security error: checksum mismatch for '$tool' (verified with fresh checksums)"
            log_detail "URL: $url"
            log_detail "Expected (fresh): $fresh_expected_sha256"
            log_detail "Actual:           $actual_sha256"
            log_error "Refusing to execute unverified installer script."
            log_error "This could indicate:"
            log_error "  1. Upstream changed their installer very recently (wait and retry)"
            log_error "  2. Potential tampering (investigate before proceeding)"
            log_error "  3. Network issue corrupting downloads (retry on different network)"

            if [[ "${ACFS_STRICT_MODE:-false}" == "true" ]]; then
                log_fatal "Strict mode: aborting due to checksum mismatch for '$tool'"
            fi

            return 1
        fi
    fi

    printf '%s' "$content" | run_as_target "$runner" -s -- "$@"
}

ensure_root() {
    if [[ $EUID -ne 0 ]]; then
        if command_exists sudo; then
            SUDO="sudo"
        elif [[ "$DRY_RUN" == "true" ]]; then
            # Dry-run should be able to print actions even on systems without sudo.
            SUDO="sudo"
            log_warn "sudo not found (dry-run mode). No commands will be executed."
        else
            log_fatal "This script requires root privileges. Please run as root or install sudo."
        fi
    else
        SUDO=""
    fi
}

# Disable needrestart's apt hook to prevent installation hangs.
# On Ubuntu 22.04+, needrestart hooks into apt via /usr/lib/needrestart/apt-pinvoke
# and can wait for interactive input even with NEEDRESTART_SUSPEND=1, because sudo
# drops the environment variable. This function disables the hook proactively.
disable_needrestart_apt_hook() {
    local apt_hook="/usr/lib/needrestart/apt-pinvoke"
    local nr_conf_dir="/etc/needrestart/conf.d"

    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ -f "$apt_hook" ]]; then
            log_detail "dry-run: would disable needrestart apt hook at $apt_hook"
        fi
        return 0
    fi

    # Method 1: Disable the apt hook executable (prevents it from running)
    if [[ -f "$apt_hook" && -x "$apt_hook" ]]; then
        log_detail "Disabling needrestart apt hook to prevent installation hangs"
        $SUDO chmod -x "$apt_hook" 2>/dev/null || true
    fi

    # Method 2: Configure needrestart to auto-restart services without prompting
    if [[ -d "$nr_conf_dir" ]] || $SUDO mkdir -p "$nr_conf_dir" 2>/dev/null; then
        echo '$nrconf{restart} = '\''a'\'';' | $SUDO tee "$nr_conf_dir/50-acfs-noninteractive.conf" >/dev/null 2>&1 || true
    fi
}

acfs_chown_tree() {
    local owner_group="$1"
    local path="$2"

    if [[ -z "$owner_group" ]]; then
        log_error "acfs_chown_tree: owner/group is required"
        return 1
    fi
    if [[ -z "$path" ]]; then
        log_error "acfs_chown_tree: path is required"
        return 1
    fi
    if [[ "$path" == "/" ]]; then
        log_error "acfs_chown_tree: refusing to chown '/'"
        return 1
    fi

    # SECURITY: Prevent recursive chown from dereferencing symlinks under the tree.
    # For top-level symlinks (e.g., symlinked /data), resolve to the real path so
    # ownership is applied to the intended directory.
    local resolved="$path"
    if [[ -L "$path" ]]; then
        if ! command_exists readlink; then
            log_error "acfs_chown_tree: readlink is required to resolve symlink: $path"
            return 1
        fi
        resolved="$(readlink -f "$path" 2>/dev/null || true)"
        if [[ -z "$resolved" ]] || [[ "$resolved" == "/" ]]; then
            log_error "acfs_chown_tree: refusing to chown unresolved/unsafe symlink: $path"
            return 1
        fi
    fi

    # Guardrail: prevent catastrophic recursive chown if a caller misconfigures
    # TARGET_HOME (or other paths) to a system directory.
    #
    # If you *really* need to chown one of these paths, you can override with:
    #   ACFS_ALLOW_UNSAFE_CHOWN=1
    if [[ "${ACFS_ALLOW_UNSAFE_CHOWN:-0}" != "1" ]]; then
        local unsafe_prefix=""
        for unsafe_prefix in /etc /usr /bin /sbin /lib /lib64 /boot /proc /sys /dev /run /var /opt; do
            if [[ "$resolved" == "$unsafe_prefix" || "$resolved" == "$unsafe_prefix/"* ]]; then
                log_error "acfs_chown_tree: refusing to chown unsafe system path: $resolved"
                log_error "If you intended this (rare), re-run with ACFS_ALLOW_UNSAFE_CHOWN=1"
                return 1
            fi
        done
    fi

    # GNU coreutils: -h = do not dereference symlinks; -R = recursive.
    if ! $SUDO chown -hR "$owner_group" "$resolved"; then
        log_error "acfs_chown_tree: chown failed for $resolved"
        return 1
    fi
}

confirm_or_exit() {
    if [[ "$DRY_RUN" == "true" ]] || [[ "$YES_MODE" == "true" ]]; then
        return 0
    fi

    if [[ "$HAS_GUM" == "true" ]] && [[ -r /dev/tty ]]; then
        gum confirm "Proceed with ACFS install? (mode=$MODE)" < /dev/tty > /dev/tty || exit 1
        return 0
    fi

    local reply=""
    if [[ -t 0 ]]; then
        read -r -p "Proceed with ACFS install? (mode=$MODE) [y/N] " reply
    elif [[ -r /dev/tty ]]; then
        read -r -p "Proceed with ACFS install? (mode=$MODE) [y/N] " reply < /dev/tty
    else
        log_fatal "--yes is required when no TTY is available"
    fi
    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *) exit 1 ;;
    esac
}

# Set up target-specific paths
# Must be called after ensure_root
init_target_paths() {
    # If running as ubuntu, use ubuntu's home
    # If running as root, install for ubuntu user
    if [[ "$(whoami)" == "$TARGET_USER" ]]; then
        TARGET_HOME="${TARGET_HOME:-$HOME}"
    else
        # Respect an explicit TARGET_HOME env override (default is /home/$TARGET_USER).
        TARGET_HOME="${TARGET_HOME:-/home/$TARGET_USER}"
    fi

    if [[ -z "$TARGET_HOME" ]] || [[ "$TARGET_HOME" == "/" ]]; then
        log_fatal "Invalid TARGET_HOME: '${TARGET_HOME:-<empty>}'"
    fi
    if [[ "$TARGET_HOME" != /* ]]; then
        log_fatal "TARGET_HOME must be an absolute path (got: $TARGET_HOME)"
    fi

    # ACFS directories for target user
    ACFS_HOME="$TARGET_HOME/.acfs"
    ACFS_STATE_FILE="$ACFS_HOME/state.json"

    # Basic hardening: refuse to use a symlinked ACFS_HOME when running with
    # elevated privileges (prevents clobbering arbitrary paths via symlink tricks).
    if [[ -e "$ACFS_HOME" ]] && [[ -L "$ACFS_HOME" ]]; then
        log_fatal "Refusing to use ACFS_HOME because it is a symlink: $ACFS_HOME"
    fi

    log_detail "Target user: $TARGET_USER"
    log_detail "Target home: $TARGET_HOME"

    # Export for generated installers (run via subshells).
    export TARGET_USER TARGET_HOME ACFS_HOME ACFS_STATE_FILE

    # Add target user's bin directories to PATH early so that tools installed
    # later (like Claude Code) see the correct PATH and don't warn about it.
    export PATH="$TARGET_HOME/.local/bin:$TARGET_HOME/.cargo/bin:$TARGET_HOME/.bun/bin:$PATH"
}

validate_target_user() {
    if [[ -z "${TARGET_USER:-}" ]]; then
        log_fatal "TARGET_USER is empty"
    fi

    # Hard-stop on unsafe usernames (prevents injection into sudoers/paths).
    if [[ ! "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log_fatal "Invalid TARGET_USER '$TARGET_USER' (expected: lowercase user name like 'ubuntu')"
    fi
}

ensure_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        log_fatal "Cannot detect OS. ACFS supports Ubuntu 22.04+ only."
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    if [[ "${ID:-}" != "ubuntu" ]]; then
        log_fatal "Unsupported OS: ${PRETTY_NAME:-${ID:-unknown}}. ACFS supports Ubuntu 22.04+ only."
    fi

    local version_id="${VERSION_ID:-}"
    if [[ -z "$version_id" ]]; then
        log_fatal "Cannot detect Ubuntu version (VERSION_ID missing)"
    fi

    VERSION_MAJOR="${version_id%%.*}"
    if [[ "$VERSION_MAJOR" -lt 22 ]]; then
        log_fatal "Unsupported Ubuntu version: ${version_id}. ACFS supports Ubuntu 22.04+ only."
    fi

    if [[ "$VERSION_MAJOR" -lt 24 ]]; then
        log_warn "Ubuntu $version_id detected. Recommended: Ubuntu 24.04+ or 25.x"
    fi

    log_detail "OS: Ubuntu $version_id"
}

# ============================================================
# Ubuntu Auto-Upgrade Phase (nb4)
# Runs as "Phase -1" before all other installation phases.
# Handles multi-reboot upgrade sequences (e.g., 24.04 → 25.04 → 25.10; EOL releases like 24.10 may be skipped)
# ============================================================
run_ubuntu_upgrade_phase() {
    # Skip if user requested
    if [[ "$SKIP_UBUNTU_UPGRADE" == "true" ]]; then
        log_detail "Skipping Ubuntu upgrade (--skip-ubuntu-upgrade)"
        return 0
    fi

    # Only upgrade actual Ubuntu systems
    if [[ ! -f /etc/os-release ]]; then
        log_detail "Not an Ubuntu system, skipping upgrade"
        return 0
    fi
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        log_detail "Not Ubuntu (detected: $ID), skipping upgrade"
        return 0
    fi

    # CRITICAL: Ensure jq is installed for state tracking (state.sh depends on it).
    if ! command -v jq &>/dev/null; then
        log_detail "Installing jq for upgrade state tracking..."
        if [[ $EUID -eq 0 ]]; then
            apt-get update -qq && apt-get install -y jq >/dev/null 2>&1 || true
        elif command -v sudo &>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y jq >/dev/null 2>&1 || true
        fi
    fi

    # Source upgrade library
    if ! _source_ubuntu_upgrade_lib; then
        log_warn "Could not load ubuntu_upgrade.sh library"
        log_warn "Skipping Ubuntu auto-upgrade"
        return 0
    fi

    # Get current version (as number for comparison, as string for display)
    local current_version_num current_version_str
    current_version_str=$(ubuntu_get_version_string)
    current_version_num=$(ubuntu_get_version_number)
    log_detail "Current Ubuntu version: $current_version_str"

    # Upgrade tracking state must survive reboots and cannot depend on the
    # target user's home existing yet (user normalization runs later).
    # Use a root-owned, persistent state file under the resume directory.
    local upgrade_state_file="${ACFS_RESUME_DIR:-/var/lib/acfs}/state.json"
    export ACFS_STATE_FILE="$upgrade_state_file"

    # Convert target version string to number for comparison
    # TARGET_UBUNTU_VERSION is "25.10", need 2510
    local target_version_num
    local target_major target_minor
    target_major="${TARGET_UBUNTU_VERSION%%.*}"
    target_minor="${TARGET_UBUNTU_VERSION#*.}"
    target_version_num=$(printf "%d%02d" "$target_major" "$target_minor")

    # Ensure ubuntu_upgrade.sh uses the requested target (not just its defaults).
    export UBUNTU_TARGET_VERSION="$TARGET_UBUNTU_VERSION"
    export UBUNTU_TARGET_VERSION_NUM="$target_version_num"

    # Check if we're resuming an upgrade after reboot
    local upgrade_stage
    upgrade_stage=$(state_upgrade_get_stage 2>/dev/null || echo "not_started")

    case "$upgrade_stage" in
        initializing|upgrading|awaiting_reboot|resumed|step_complete)
            log_info "Detected Ubuntu upgrade in progress (stage: $upgrade_stage)"
            log_info "The systemd resume service should handle this automatically"
            log_info "Monitoring:"
            log_info "  - /var/lib/acfs/check_status.sh"
            log_info "  - journalctl -u acfs-upgrade-resume -f"
            log_info "  - tail -f /var/log/acfs/upgrade_resume.log"
            return 0
            ;;
        pre_upgrade_reboot)
            # We just rebooted to clear pending package updates
            log_success "Pre-upgrade reboot complete. Continuing with upgrade..."
            # Clear the stage so we proceed normally
            if type -t state_update &>/dev/null; then
                state_update ".ubuntu_upgrade.current_stage = \"not_started\" | .ubuntu_upgrade.enabled = false" || true
            fi
            # Set flag to skip redundant warning (user already confirmed before reboot)
            local skip_upgrade_warning=true
            # Fall through to continue with upgrade
            ;;
        error)
            log_error "Previous Ubuntu upgrade attempt failed (stage: error)"
            log_error "Check logs:"
            log_info "  journalctl -u acfs-upgrade-resume"
            log_info "  tail -100 /var/log/acfs/upgrade_resume.log"
            log_error "To reset and retry upgrade:"
            log_info "  sudo mv -- '${upgrade_state_file}' '${upgrade_state_file}.backup.\$(date +%Y%m%d_%H%M%S)'"
            log_error "To proceed without upgrading:"
            log_info "  Re-run with --skip-ubuntu-upgrade (not recommended)"
            return 1
            ;;
    esac

    # Check if upgrade is needed (using numeric comparison)
    if ubuntu_version_gte "$current_version_num" "$target_version_num"; then
        log_detail "Ubuntu $current_version_str meets target ($TARGET_UBUNTU_VERSION)"
        return 0
    fi

    # Ubuntu distribution upgrades require root (do-release-upgrade, systemd units,
    # /var/lib/acfs state). If the installer is being run as a sudo-capable user,
    # abort with clear guidance rather than failing mid-upgrade.
    if [[ $EUID -ne 0 ]]; then
        log_error "Ubuntu auto-upgrade requires running the installer as root"
        log_info "Re-run as root (e.g., run 'sudo -i' then run the install command again), or use --skip-ubuntu-upgrade."
        return 1
    fi

    # Calculate upgrade path (function takes target version NUMBER, determines current internally)
    # Returns newline-separated list of version strings to upgrade through
    local upgrade_path
    upgrade_path=$(ubuntu_calculate_upgrade_path "$target_version_num")

    if [[ -z "$upgrade_path" ]]; then
        log_detail "No upgrade path found from $current_version_str to $TARGET_UBUNTU_VERSION"
        return 0
    fi

    log_step "-1/9" "Ubuntu Auto-Upgrade"
    # Format path for display (e.g., "25.04 → 25.10")
    local upgrade_path_display
    upgrade_path_display=$(echo "$upgrade_path" | tr '\n' ' ' | sed 's/ $//; s/ / → /g')
    log_info "Upgrade path: $current_version_str → $upgrade_path_display"

    # Show warning and get confirmation (unless --yes mode or resuming from pre-reboot)
    if [[ "${skip_upgrade_warning:-}" != "true" ]]; then
        if type -t ubuntu_show_upgrade_warning &>/dev/null; then
            ubuntu_show_upgrade_warning
        fi

        if [[ "$YES_MODE" != "true" ]]; then
            log_warn "Ubuntu upgrade will take 30-60 minutes per version and require reboots."
            log_warn "Your SSH session will disconnect. Reconnect after each reboot."
            echo ""

            if [[ -t 0 ]]; then
                read -r -p "Proceed with Ubuntu upgrade? [y/N] " response
            elif [[ -r /dev/tty ]]; then
                echo -n "Proceed with Ubuntu upgrade? [y/N] " >&2
                read -r response < /dev/tty
            else
                log_fatal "--yes is required when no TTY is available"
            fi

            if [[ ! "$response" =~ ^[Yy] ]]; then
                log_info "Ubuntu upgrade skipped by user"
                log_info "Continuing with ACFS installation on Ubuntu $current_version_str"
                return 0
            fi
        fi
    fi

    # Check if system requires reboot before upgrade (package updates pending)
    # This must be handled before preflight checks, otherwise do-release-upgrade fails
    if [[ -f /var/run/reboot-required ]]; then
        log_warn "System requires reboot before upgrade can proceed"
        if [[ -f /var/run/reboot-required.pkgs ]]; then
            log_detail "Packages requiring reboot: $(tr '\n' ' ' < /var/run/reboot-required.pkgs | sed 's/ $//')"
        fi

        if [[ "$YES_MODE" == "true" ]]; then
            log_info "Automatically rebooting to clear pending updates..."

            # Initialize state file early for tracking
            mkdir -p "${ACFS_RESUME_DIR:-/var/lib/acfs}"
            if type -t state_ensure_valid &>/dev/null; then
                state_ensure_valid || true
            fi
            if type -t state_init &>/dev/null; then
                state_load >/dev/null 2>&1 || state_init || true
            fi

            # Set stage so we know to continue after reboot
            if type -t state_update &>/dev/null; then
                if ! state_update ".ubuntu_upgrade.enabled = true | .ubuntu_upgrade.current_stage = \"pre_upgrade_reboot\" | .ubuntu_upgrade.original_version = \"$current_version_str\" | .ubuntu_upgrade.target_version = \"$TARGET_UBUNTU_VERSION\""; then
                    log_error "Failed to record upgrade stage; cannot safely auto-reboot."
                    log_info "Please reboot manually and re-run the installer."
                    return 1
                fi
            else
                log_error "State tracking is unavailable; cannot safely auto-reboot."
                log_info "Please reboot manually and re-run the installer."
                return 1
            fi

            # Set up resume infrastructure
            local acfs_source_dir=""
            if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -d "$SCRIPT_DIR" ]]; then
                acfs_source_dir="$SCRIPT_DIR"
            elif [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -d "$ACFS_BOOTSTRAP_DIR" ]]; then
                acfs_source_dir="$ACFS_BOOTSTRAP_DIR"
            fi

            if [[ -n "$acfs_source_dir" ]] && type -t upgrade_setup_infrastructure &>/dev/null; then
                if ! upgrade_setup_infrastructure "$acfs_source_dir" "$@"; then
                    log_error "Failed to set up resume infrastructure. Cannot safely reboot."
                    log_info "Please reboot manually and re-run the installer."
                    return 1
                fi

                # upgrade_setup_infrastructure generates the correct continue_install.sh for both:
                # - pre-upgrade reboot (continue WITH upgrade)
                # - post-upgrade continuation (skip upgrade)
            else
                log_warn "Resume infrastructure not available. After reboot, re-run installer manually."
            fi

            # Update MOTD before reboot
            upgrade_update_motd "Rebooting for upgrade to ${UBUNTU_TARGET_VERSION:-Ubuntu}..."

            # Trigger reboot
            log_warn "Rebooting in 10 seconds..."
            echo ""
            log_info "After reconnecting via SSH, the upgrade continues automatically in the background."
            log_info "To monitor progress:"
            log_info "  journalctl -u acfs-upgrade-resume -f"
            log_info "  tail -f /var/log/acfs/upgrade_resume.log"
            echo ""
            sleep 10
            shutdown -r now "ACFS: Rebooting to apply pending updates before Ubuntu upgrade"
            exit 0
        else
            log_error "Manual action required: reboot the system first"
            log_info "Run: sudo reboot"
            log_info "Then re-run the ACFS installer"
            return 1
        fi
    fi

    # Run preflight checks
    if type -t ubuntu_preflight_checks &>/dev/null; then
        if ! ubuntu_preflight_checks; then
            log_error "Preflight checks failed. Cannot proceed with upgrade."
            log_info "Use --skip-ubuntu-upgrade to bypass (not recommended)"
            return 1
        fi
    fi

    # Ensure a state file exists so upgrade tracking can persist progress.
    # (The main install resume prompt/state init happens later, but upgrades
    # need state_update/state_upgrade_* to be able to write immediately.)
    if type -t state_ensure_valid &>/dev/null; then
        if ! state_ensure_valid; then
            log_error "State validation failed. Aborting Ubuntu upgrade."
            return 1
        fi
    fi
    if type -t state_load &>/dev/null && type -t state_init &>/dev/null; then
        if ! state_load >/dev/null 2>&1; then
            log_detail "Initializing state file for Ubuntu upgrade tracking..."
            if ! state_init; then
                log_error "Failed to initialize state file. Aborting Ubuntu upgrade."
                return 1
            fi
        fi
    fi

    # Start the upgrade sequence
    # This will trigger reboots and the resume service will continue
    log_info "Starting Ubuntu upgrade sequence..."

    if type -t ubuntu_start_upgrade_sequence &>/dev/null; then
        # Provide a source directory so we can copy upgrade-resume assets.
        # Local checkout: SCRIPT_DIR is set.
        # curl|bash: bootstrap_repo_archive prepared ACFS_BOOTSTRAP_DIR.
        local acfs_source_dir=""
        if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -d "$SCRIPT_DIR" ]]; then
            acfs_source_dir="$SCRIPT_DIR"
        elif [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -d "$ACFS_BOOTSTRAP_DIR" ]]; then
            acfs_source_dir="$ACFS_BOOTSTRAP_DIR"
        else
            acfs_source_dir="."
        fi

        if ! ubuntu_start_upgrade_sequence "$acfs_source_dir" "$@"; then
            log_error "Ubuntu upgrade failed to start"
            return 1
        fi

        # If we get here, the script is about to exit for reboot
        # The resume service will take over after reboot
        log_info "Upgrade initiated. System will reboot shortly."
        log_info "Reconnect via SSH after reboot - upgrade will continue automatically."
        exit 0
    else
        log_warn "ubuntu_start_upgrade_sequence not available"
        log_warn "Continuing with ACFS installation on current Ubuntu version"
        return 0
    fi
}

ensure_base_deps() {
    set_phase "base_deps" "Base Dependencies" 1
    log_step "0/9" "Checking base dependencies..."

    if acfs_use_generated_category "base"; then
        log_detail "Using generated installers for base (phase 1)"
        acfs_run_generated_category_phase "base" "1" || return 1
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        local sudo_prefix=""
        if [[ -n "${SUDO:-}" ]]; then
            sudo_prefix="$SUDO "
        fi

        log_detail "dry-run: would run: ${sudo_prefix}apt-get update -y"
        log_detail "dry-run: would install: curl git ca-certificates unzip tar xz-utils jq build-essential sudo gnupg libssl-dev pkg-config"
        return 0
    fi

    log_detail "Updating apt package index"
    try_step "Updating apt package index" $SUDO apt-get update -y || return 1

    log_detail "Installing base packages"
    try_step "Installing base packages" $SUDO apt-get install -y curl git ca-certificates unzip tar xz-utils jq build-essential sudo gnupg libssl-dev pkg-config || return 1
}

# ============================================================
# Phase 1: User normalization
# ============================================================
normalize_user() {
    set_phase "user_setup" "User Normalization"
    log_step "1/9" "Normalizing user account..."

    if [[ $EUID -eq 0 ]] && type -t prompt_ssh_key &>/dev/null; then
        if ! prompt_ssh_key; then
            log_warn "SSH key prompt failed or was skipped; continuing"
        fi
    fi

    if acfs_use_generated_category "users"; then
        log_detail "Using generated installers for users (phase 2)"
        acfs_run_generated_category_phase "users" "2" || return 1
        log_success "User normalization complete"
        return 0
    fi

    # Create target user if it doesn't exist
    if ! id "$TARGET_USER" &>/dev/null; then
        log_detail "Creating user: $TARGET_USER"

        # Generate random password (user will use SSH key, but password is needed for sudo in safe mode)
        # Use openssl/python/urandom for robustness
        local user_password=""
        if command -v openssl &>/dev/null; then
            user_password=$(openssl rand -base64 32)
        elif command -v python3 &>/dev/null; then
            user_password=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
        else
            user_password=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
        fi

        # We intentionally do NOT use try_step here because user creation can be
        # a recoverable race (e.g., another process creates the user between the
        # id check and useradd). Using try_step would record state_phase_fail and
        # poison resume state even if we recover.
        local useradd_exit=0
        local useradd_output=""
        
        # Create user with home directory and bash shell
        useradd_output="$($SUDO useradd -m -s /bin/bash "$TARGET_USER" 2>&1)" || useradd_exit=$?
        
        if [[ $useradd_exit -ne 0 ]]; then
            if id "$TARGET_USER" &>/dev/null; then
                log_warn "useradd exited ${useradd_exit}, but user '$TARGET_USER' exists; continuing"
            else
                log_error "Failed to create user '$TARGET_USER' (useradd exit ${useradd_exit})."
                if [[ -n "$useradd_output" ]]; then
                    local first_line=""
                    first_line="$(printf '%s\n' "$useradd_output" | head -n 1)"
                    [[ -n "$first_line" ]] && log_detail "useradd: $first_line"
                fi
                return 1
            fi
        else
            # Set password if user creation succeeded
            if [[ -n "$user_password" ]]; then
                echo "$TARGET_USER:$user_password" | $SUDO chpasswd
                
                # Print password for the operator (important for safe mode)
                echo "" >&2
                log_warn "Generated password for '$TARGET_USER': $user_password"
                log_warn "Save this password! You may need it for sudo access (safe mode)."
                echo "" >&2
            else
                log_warn "Failed to generate password for $TARGET_USER"
            fi
        fi
    fi
    # Ensure the target user has sudo-group membership even on reruns.
    # If user creation succeeded but the first `usermod` attempt failed,
    # reruns should still apply the group change (idempotent).
    try_step "Ensuring $TARGET_USER is in sudo group" $SUDO usermod -aG sudo "$TARGET_USER" || return 1

    # Ensure home directory has correct ownership
    # CRITICAL: useradd -m does NOT change ownership of existing directories (common on VPS)
    # Cloud images often pre-create /home/ubuntu owned by root:root
    if [[ -d "$TARGET_HOME" ]]; then
        try_step "Setting home directory ownership" acfs_chown_tree "$TARGET_USER:$TARGET_USER" "$TARGET_HOME" || return 1
    fi

    # Set up passwordless sudo in vibe mode
    if [[ "$MODE" == "vibe" ]]; then
        log_detail "Enabling passwordless sudo for $TARGET_USER"
        try_step_eval "Configuring passwordless sudo" \
            "echo '$TARGET_USER ALL=(ALL) NOPASSWD:ALL' | $SUDO tee /etc/sudoers.d/90-ubuntu-acfs > /dev/null" || return 1
        try_step "Setting sudoers file permissions" $SUDO chmod 440 /etc/sudoers.d/90-ubuntu-acfs || return 1
        if command_exists visudo && ! $SUDO visudo -c -f /etc/sudoers.d/90-ubuntu-acfs >/dev/null 2>&1; then
            log_fatal "Invalid sudoers file generated at /etc/sudoers.d/90-ubuntu-acfs"
        fi
    fi

    # Ensure root's SSH keys are present for the target user (do not overwrite existing keys)
    if [[ $EUID -eq 0 ]] && [[ -f /root/.ssh/authorized_keys ]]; then
        log_detail "Syncing SSH keys to $TARGET_USER"
        try_step "Creating .ssh directory" $SUDO mkdir -p "$TARGET_HOME/.ssh" || return 1

        # Basic hardening: refuse to follow symlinks as root.
        if [[ -L "$TARGET_HOME/.ssh" ]]; then
            log_error "Refusing to manage SSH keys: $TARGET_HOME/.ssh is a symlink"
            return 1
        fi
        if [[ -L "$TARGET_HOME/.ssh/authorized_keys" ]]; then
            log_error "Refusing to manage SSH keys: $TARGET_HOME/.ssh/authorized_keys is a symlink"
            return 1
        fi

        try_step "Ensuring authorized_keys exists" $SUDO touch "$TARGET_HOME/.ssh/authorized_keys" || return 1
        # shellcheck disable=SC2016  # Variables expand inside the bash -c script, not here.
        try_step "Merging SSH authorized_keys" bash -c '
            set -euo pipefail
            src="/root/.ssh/authorized_keys"
            dst="$1"
            while IFS= read -r line || [[ -n "$line" ]]; do
                [[ -n "$line" ]] || continue
                if grep -Fxq "$line" "$dst" 2>/dev/null; then
                    continue
                fi
                # Ensure destination file ends with newline before appending
                if [[ -s "$dst" ]] && [[ -n "$(tail -c 1 "$dst")" ]]; then
                    echo "" >> "$dst"
                fi
                printf "%s\n" "$line" >> "$dst"
            done < "$src"
        ' -- "$TARGET_HOME/.ssh/authorized_keys" || return 1
        try_step "Setting SSH directory ownership" acfs_chown_tree "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.ssh" || return 1
        try_step "Setting SSH directory permissions" $SUDO chmod 700 "$TARGET_HOME/.ssh" || return 1
        try_step "Setting authorized_keys permissions" $SUDO chmod 600 "$TARGET_HOME/.ssh/authorized_keys" || return 1
    fi

    # Add target user to docker group if docker is installed
    if getent group docker &>/dev/null; then
        try_step "Adding $TARGET_USER to docker group" $SUDO usermod -aG docker "$TARGET_USER" || true
    fi

    log_success "User normalization complete"
}

# ============================================================
# Phase 2: Filesystem setup
# ============================================================
setup_filesystem() {
    set_phase "filesystem" "Filesystem Setup"
    log_step "2/9" "Setting up filesystem..."

    if acfs_use_generated_category "filesystem"; then
        log_detail "Using generated installers for filesystem (phase 3)"
        acfs_run_generated_category_phase "filesystem" "3" || return 1
        log_success "Filesystem setup complete"
        return 0
    fi

    # Basic hardening: refuse to follow symlinks as root.
    # Prevents symlink tricks like /data -> / or /data/projects -> /etc.
    local fs_path=""
    for fs_path in /data /data/projects /data/cache; do
        if [[ -e "$fs_path" && -L "$fs_path" ]]; then
            log_error "Refusing to set up filesystem: $fs_path is a symlink"
            return 1
        fi
    done

    # System directories
    local sys_dirs=("/data/projects" "/data/cache")
    for dir in "${sys_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_detail "Creating: $dir"
            try_step "Creating $dir" $SUDO mkdir -p "$dir" || return 1
        fi
    done

    # Ensure workspace directories are owned by target user (avoid over-broad recursive chown).
    try_step "Setting /data ownership" $SUDO chown -h "$TARGET_USER:$TARGET_USER" /data /data/projects /data/cache || true

    # Install AGENTS.md template to /data/projects for agent guidance
    log_detail "Installing AGENTS.md template"
    try_step "Installing AGENTS.md" install_asset "acfs/AGENTS.md" "/data/projects/AGENTS.md" || true
    try_step "Setting AGENTS.md ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "/data/projects/AGENTS.md" || true

    # CRITICAL: Fix home directory ownership FIRST, before any run_as_target calls
    # Some cloud images (e.g., Hetzner) have /home/ubuntu owned by root after user creation
    # If we don't fix this first, all run_as_target mkdir calls below will fail
    try_step "Fixing home directory ownership" acfs_chown_tree "$TARGET_USER:$TARGET_USER" "$TARGET_HOME" || true

    # User directories (in TARGET_HOME, not $HOME)
    # CRITICAL: Create these as target user to ensure correct ownership
    local user_dirs=("Development" "Projects" "dotfiles")
    for dir in "${user_dirs[@]}"; do
        local full_path="$TARGET_HOME/$dir"
        if [[ ! -d "$full_path" ]]; then
            log_detail "Creating: $full_path"
            try_step "Creating $full_path" run_as_target mkdir -p "$full_path" || return 1
        fi
    done

    # Create ACFS directories (as root, then chown)
    try_step "Creating ACFS directories" $SUDO mkdir -p "$ACFS_HOME"/{zsh,tmux,bin,docs,logs,scripts/lib} || return 1
    try_step "Setting ACFS directory ownership" acfs_chown_tree "$TARGET_USER:$TARGET_USER" "$ACFS_HOME" || return 1
    try_step "Creating ACFS log directory" $SUDO mkdir -p "$ACFS_LOG_DIR" || return 1

    # Install essential ACFS scripts early so `acfs doctor` works even after early failures.
    # This is critical for debugging failed installs - users need `acfs doctor` to work
    # even if the install failed in Phase 3 (languages) before finalization.
    log_detail "Installing essential ACFS scripts for early debugging"
    try_step "Installing logging.sh (early)" install_asset "scripts/lib/logging.sh" "$ACFS_HOME/scripts/lib/logging.sh" || true
    try_step "Installing gum_ui.sh (early)" install_asset "scripts/lib/gum_ui.sh" "$ACFS_HOME/scripts/lib/gum_ui.sh" || true
    try_step "Installing doctor.sh (early)" install_asset "scripts/lib/doctor.sh" "$ACFS_HOME/scripts/lib/doctor.sh" || true
    # Set permissions and ownership so target user can run doctor
    $SUDO chmod 755 "$ACFS_HOME/scripts/lib/"*.sh 2>/dev/null || true
    acfs_chown_tree "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/scripts" 2>/dev/null || true

    # Create user's .local/bin and .bun directories early - many installers need them
    # This prevents NTM, UBS, CASS, Bun, etc. from creating them as root via sudo
    try_step "Creating .local/bin directory" run_as_target mkdir -p "$TARGET_HOME/.local/bin" || return 1
    try_step "Creating .bun directory" run_as_target mkdir -p "$TARGET_HOME/.bun" || return 1

    log_success "Filesystem setup complete"
}

# ============================================================
# Phase 3: Shell setup (zsh + oh-my-zsh + p10k)
# ============================================================
setup_shell() {
    set_phase "shell_setup" "Shell Setup"
    log_step "3/9" "Setting up shell..."

    if acfs_use_generated_category "shell"; then
        log_detail "Using generated installers for shell (phase 4)"
        acfs_run_generated_category_phase "shell" "4" || return 1
        log_success "Shell setup complete"
        return 0
    fi

    # Install zsh
    if ! command_exists zsh; then
        log_detail "Installing zsh"
        try_step "Installing zsh" $SUDO apt-get install -y zsh || return 1
    fi

    # Install Oh My Zsh for target user
    # Check multiple possible locations for existing installation
    local omz_dir="$TARGET_HOME/.oh-my-zsh"
    local omz_installed=false

    if [[ -d "$omz_dir" ]]; then
        omz_installed=true
        log_detail "Oh My Zsh already installed at $omz_dir"
    elif [[ -d "/root/.oh-my-zsh" ]] && [[ "$(whoami)" == "root" ]]; then
        # If running as root and oh-my-zsh exists in /root, copy it to target
        # Use -rL to dereference symlinks (avoids broken symlinks pointing to /root/)
        log_detail "Oh My Zsh found in /root, copying to $TARGET_USER"
        $SUDO cp -rL /root/.oh-my-zsh "$omz_dir"
        acfs_chown_tree "$TARGET_USER:$TARGET_USER" "$omz_dir"
        omz_installed=true
    elif [[ -f "$TARGET_HOME/.zshrc" ]] && grep -q "oh-my-zsh" "$TARGET_HOME/.zshrc" 2>/dev/null; then
        # oh-my-zsh referenced in .zshrc but directory missing - unusual state
        log_warn "Oh My Zsh referenced in .zshrc but directory not found; reinstalling"
    fi

    if [[ "$omz_installed" != "true" ]]; then
        log_detail "Installing Oh My Zsh for $TARGET_USER"
        # Run as target user to install in their home
        try_step "Installing Oh My Zsh" acfs_run_verified_upstream_script_as_target "ohmyzsh" "sh" --unattended || return 1
    fi

    # Install Powerlevel10k theme
    local p10k_dir="$omz_dir/custom/themes/powerlevel10k"
    if [[ ! -d "$p10k_dir" ]]; then
        log_detail "Installing Powerlevel10k theme"
        try_step "Installing Powerlevel10k theme" run_as_target git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir" || return 1
    fi

    # Install zsh plugins
    local custom_plugins="$omz_dir/custom/plugins"

    if [[ ! -d "$custom_plugins/zsh-autosuggestions" ]]; then
        log_detail "Installing zsh-autosuggestions"
        try_step "Installing zsh-autosuggestions" run_as_target git clone https://github.com/zsh-users/zsh-autosuggestions "$custom_plugins/zsh-autosuggestions" || return 1
    fi

    if [[ ! -d "$custom_plugins/zsh-syntax-highlighting" ]]; then
        log_detail "Installing zsh-syntax-highlighting"
        try_step "Installing zsh-syntax-highlighting" run_as_target git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$custom_plugins/zsh-syntax-highlighting" || return 1
    fi

    # Copy ACFS zshrc
    log_detail "Installing ACFS zshrc"
    try_step "Installing ACFS zshrc" install_asset "acfs/zsh/acfs.zshrc" "$ACFS_HOME/zsh/acfs.zshrc" || return 1
    try_step "Setting zshrc ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/zsh/acfs.zshrc" || return 1

    # Install pre-configured Powerlevel10k theme settings
    # This prevents the p10k configuration wizard from launching on first login
    log_detail "Installing Powerlevel10k configuration"
    try_step "Installing p10k config" install_asset "acfs/zsh/p10k.zsh" "$TARGET_HOME/.p10k.zsh" || return 1
    try_step "Setting p10k config ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.p10k.zsh" || return 1

    # Create minimal .zshrc loader for target user (backup existing if needed)
    local user_zshrc="$TARGET_HOME/.zshrc"
    if [[ -f "$user_zshrc" ]] && ! grep -q "^# ACFS loader" "$user_zshrc" 2>/dev/null; then
        local backup
        backup="$user_zshrc.pre-acfs.$(date +%Y%m%d%H%M%S)"
        if [[ "${ACFS_CI:-false}" == "true" ]]; then
            log_detail "Existing .zshrc found; backing up to $(basename "$backup")"
        else
            log_warn "Existing .zshrc found; backing up to $(basename "$backup")"
        fi
        $SUDO cp "$user_zshrc" "$backup"
        $SUDO chown "$TARGET_USER:$TARGET_USER" "$backup" 2>/dev/null || true
    fi

    cat > "$user_zshrc" << 'EOF'
# ACFS loader
source "$HOME/.acfs/zsh/acfs.zshrc"

# User overrides live here forever
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
EOF
    try_step "Setting .zshrc ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$user_zshrc" || return 1

    # Ensure ~/.local/bin is in PATH for bash login shells (used by installers)
    # This prevents warnings from tools like Claude's installer that check PATH
    local user_profile="$TARGET_HOME/.profile"
    # shellcheck disable=SC2016  # We want $HOME/$PATH to expand when .profile is sourced, not during install.
    local profile_path_line='export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"'
    if [[ ! -f "$user_profile" ]]; then
        # Create new .profile
        {
            echo "# ~/.profile: executed by bash for login shells"
            echo ""
            echo "# User binary paths"
            echo "$profile_path_line"
        } > "$user_profile"
        $SUDO chown "$TARGET_USER:$TARGET_USER" "$user_profile"
    elif ! grep -q '\.local/bin' "$user_profile" 2>/dev/null; then
        # Append to existing .profile
        {
            echo ""
            echo "# Added by ACFS - user binary paths"
            echo "$profile_path_line"
        } >> "$user_profile"
    fi
    # Ensure correct ownership (handles edge case where file was created by root)
    [[ -f "$user_profile" ]] && $SUDO chown "$TARGET_USER:$TARGET_USER" "$user_profile" 2>/dev/null || true

    # Set zsh as default shell for target user
    local current_shell
    current_shell=$(getent passwd "$TARGET_USER" | cut -d: -f7)
    if [[ "$current_shell" != *"zsh"* ]]; then
        log_detail "Setting zsh as default shell for $TARGET_USER"
        try_step "Setting zsh as default shell" $SUDO chsh -s "$(command -v zsh)" "$TARGET_USER" || true
    fi

    log_success "Shell setup complete"
}

# ============================================================
# Phase 4: CLI tools
# ============================================================
install_github_cli() {
    # GitHub CLI (gh) is a core tool for ACFS workflows (PRs, auth, issues).
    # Prefer distro apt; fall back to the official GitHub CLI apt repo if needed.

    if command_exists gh; then
        return 0
    fi

    log_detail "Installing GitHub CLI (gh)"

    # First try default apt repos (often available on Ubuntu 24.04+/25.x).
    if $SUDO apt-get install -y gh >/dev/null 2>&1; then
        return 0
    fi

    # Fallback: add official GitHub CLI apt repo and retry.
    log_detail "gh not available in default apt repos; adding GitHub CLI apt repo"

    if ! $SUDO mkdir -p /etc/apt/keyrings; then
        return 1
    fi
    if ! acfs_curl https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
        $SUDO dd of=/etc/apt/keyrings/githubcli-archive-keyring.gpg status=none 2>/dev/null; then
        return 1
    fi
    $SUDO chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg 2>/dev/null || true

    local arch
    arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
    if ! echo "deb [arch=$arch signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
        $SUDO tee /etc/apt/sources.list.d/github-cli.list > /dev/null; then
        return 1
    fi

    $SUDO apt-get update -y >/dev/null 2>&1 || true
    if ! $SUDO apt-get install -y gh >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

install_cli_tools() {
    set_phase "cli_tools" "CLI Tools"
    log_step "4/9" "Installing CLI tools..."

    local used_generated_cli=false
    local used_generated_network=false

    if acfs_use_generated_category "cli"; then
        log_detail "Using generated installers for cli (phase 5)"
        acfs_run_generated_category_phase "cli" "5" || return 1
        used_generated_cli=true
    fi

    if acfs_use_generated_category "network"; then
        log_detail "Using generated installers for network (phase 5)"
        acfs_run_generated_category_phase "network" "5" || return 1
        used_generated_network=true
    fi

    if [[ "$used_generated_cli" == "true" ]]; then
        if [[ "$used_generated_network" != "true" ]]; then
            # Preserve legacy Tailscale install when network isn't generated yet.
            if command -v tailscale &>/dev/null; then
                log_detail "Tailscale already installed"
            else
                log_detail "Installing Tailscale..."
                if try_step "Installing Tailscale" install_tailscale; then
                    log_success "Tailscale installed"
                else
                    log_warn "Tailscale installation failed (optional, continuing)"
                fi
            fi
        fi
        log_success "CLI tools installed"
        return 0
    fi

    # Install gum if not already installed (install_gum_early may have skipped
    # if curl/gpg weren't available at that point)
    if command_exists gum; then
        log_detail "gum already installed"
    else
        log_detail "Installing gum for glamorous shell scripts"
        try_step "Creating apt keyrings directory" $SUDO mkdir -p /etc/apt/keyrings || true
        try_step_eval "Adding Charm apt key" "set -o pipefail; if curl --help all 2>/dev/null | grep -q -- '--proto'; then curl --proto '=https' --proto-redir '=https' -fsSL https://repo.charm.sh/apt/gpg.key; else curl -fsSL https://repo.charm.sh/apt/gpg.key; fi | $SUDO gpg --batch --yes --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null" || true
        try_step_eval "Adding Charm apt repo" "printf 'Types: deb\nURIs: https://repo.charm.sh/apt/\nSuites: *\nComponents: *\nSigned-By: /etc/apt/keyrings/charm.gpg\n' | $SUDO tee /etc/apt/sources.list.d/charm.sources > /dev/null" || true
        try_step "Updating apt cache" $SUDO apt-get update -y || true
        if try_step "Installing gum" $SUDO apt-get install -y gum 2>/dev/null; then
            HAS_GUM=true
            log_success "gum installed - enhanced UI now available"
        else
            log_detail "gum installation failed (optional, continuing)"
        fi
    fi

    log_detail "Installing required apt packages"
    try_step "Installing required apt packages" $SUDO apt-get install -y ripgrep tmux fzf direnv jq git-lfs lsof dnsutils netcat-openbsd strace rsync || return 1

    # GitHub CLI (gh)
    if command_exists gh; then
        log_detail "gh already installed ($(gh --version 2>/dev/null | head -1 || echo 'gh'))"
    else
        if try_step "Installing GitHub CLI" install_github_cli; then
            log_success "gh installed"
        else
            log_fatal "Failed to install GitHub CLI (gh)"
        fi
    fi

    # Git LFS setup (best-effort: installs hooks config for the target user)
    if command_exists git-lfs; then
        log_detail "Configuring git-lfs for $TARGET_USER"
        try_step "Configuring git-lfs" run_as_target git lfs install --skip-repo || true
    fi

    # Install optional apt packages individually to prevent one failure from blocking others
    log_detail "Installing optional apt packages"
    local optional_pkgs=(lsd eza bat fd-find btop dust neovim htop tree ncdu httpie entr mtr pv docker.io docker-compose-plugin)
    for pkg in "${optional_pkgs[@]}"; do
        $SUDO apt-get install -y "$pkg" >/dev/null 2>&1 || log_detail "$pkg not available (optional)"
    done

    # Robust lazygit install (apt or binary fallback)
    if ! command_exists lazygit; then
        log_detail "Installing lazygit..."
        if ! $SUDO apt-get install -y lazygit >/dev/null 2>&1; then
            local arch=""
            case "$(uname -m)" in
                x86_64) arch="x86_64" ;;
                aarch64|arm64) arch="arm64" ;;
            esac
            if [[ -n "$arch" ]]; then
                local lg_ver="0.44.1"
                local lg_url="https://github.com/jesseduffield/lazygit/releases/download/v${lg_ver}/lazygit_${lg_ver}_Linux_${arch}.tar.gz"
                local lg_sha256=""
                case "$arch" in
                    x86_64) lg_sha256="84682f4ad5a449d0a3ffbc8332200fe8651aee9dd91dcd8d87197ba6c2450dbc" ;;
                    arm64) lg_sha256="26a435f47b691325c086dad2f84daa6556df5af8efc52b6ed624fa657605c976" ;;
                esac
                local lg_tmp=""
                if command -v mktemp &>/dev/null; then
                    lg_tmp="$(mktemp "${TMPDIR:-/tmp}/acfs-lazygit.XXXXXX" 2>/dev/null)" || lg_tmp=""
                fi
                if [[ -n "$lg_tmp" ]]; then
                    if acfs_download_file_and_verify_sha256 "$lg_url" "$lg_tmp" "$lg_sha256" "lazygit ${lg_ver} (${arch})"; then
                        if $SUDO tar -xzf "$lg_tmp" -C /usr/local/bin --no-same-owner --no-same-permissions lazygit 2>/dev/null; then
                            $SUDO chmod 0755 /usr/local/bin/lazygit 2>/dev/null || true
                            if command_exists lazygit; then
                                log_detail "lazygit installed from GitHub release"
                            else
                                log_warn "lazygit: extracted but binary not found in PATH (skipping)"
                            fi
                        else
                            log_warn "lazygit: failed to extract tarball (skipping)"
                        fi
                    fi
                    rm -f "$lg_tmp" 2>/dev/null || true
                fi
            fi
        fi
    fi

    # Robust lazydocker install (binary fallback)
    if ! command_exists lazydocker; then
        log_detail "Installing lazydocker..."
        local arch=""
        case "$(uname -m)" in
            x86_64) arch="x86_64" ;;
            aarch64|arm64) arch="arm64" ;;
        esac
        if [[ -n "$arch" ]]; then
            local ld_ver="0.23.3"
            local ld_url="https://github.com/jesseduffield/lazydocker/releases/download/v${ld_ver}/lazydocker_${ld_ver}_Linux_${arch}.tar.gz"
            local ld_sha256=""
            case "$arch" in
                x86_64) ld_sha256="1f3c7037326973b85cb85447b2574595103185f8ed067b605dd43cc201bc8786" ;;
                arm64) ld_sha256="ae7bed0309289396d396b8502b2d78d153a4f8ce8add042f655332241e7eac31" ;;
            esac
            local ld_tmp=""
            if command -v mktemp &>/dev/null; then
                ld_tmp="$(mktemp "${TMPDIR:-/tmp}/acfs-lazydocker.XXXXXX" 2>/dev/null)" || ld_tmp=""
            fi
            if [[ -n "$ld_tmp" ]]; then
                if acfs_download_file_and_verify_sha256 "$ld_url" "$ld_tmp" "$ld_sha256" "lazydocker ${ld_ver} (${arch})"; then
                    if $SUDO tar -xzf "$ld_tmp" -C /usr/local/bin --no-same-owner --no-same-permissions lazydocker 2>/dev/null; then
                        $SUDO chmod 0755 /usr/local/bin/lazydocker 2>/dev/null || true
                        if command_exists lazydocker; then
                            log_detail "lazydocker installed from GitHub release"
                        else
                            log_warn "lazydocker: extracted but binary not found in PATH (skipping)"
                        fi
                    else
                        log_warn "lazydocker: failed to extract tarball (skipping)"
                    fi
                fi
                rm -f "$ld_tmp" 2>/dev/null || true
            fi
        fi
    fi

    # Add user to docker group (only if docker group exists)
    if getent group docker &>/dev/null; then
        try_step "Adding $TARGET_USER to docker group" $SUDO usermod -aG docker "$TARGET_USER" || true
    else
        log_detail "Docker group not found, skipping group membership"
    fi

    # Tailscale VPN for secure remote access (bt5)
    if [[ "$used_generated_network" == "true" ]]; then
        log_detail "Tailscale handled by generated network installers"
    elif command -v tailscale &>/dev/null; then
        log_detail "Tailscale already installed"
    else
        log_detail "Installing Tailscale..."
        if try_step "Installing Tailscale" install_tailscale; then
            log_success "Tailscale installed"
        else
            log_warn "Tailscale installation failed (optional, continuing)"
        fi
    fi

    log_success "CLI tools installed"
}

# ============================================================
# Phase 5: Language runtimes
# ============================================================
install_languages_legacy_lang() {
    # Bun (install as target user)
    local bun_bin="$TARGET_HOME/.bun/bin/bun"
    if [[ ! -x "$bun_bin" ]]; then
        log_detail "Installing Bun for $TARGET_USER"
        try_step "Installing Bun" acfs_run_verified_upstream_script_as_target "bun" "bash" || return 1
    fi

    # Create node symlink to bun for Node.js compatibility
    # Many tools (codex, gemini, etc.) have #!/usr/bin/env node shebangs
    local node_link="$TARGET_HOME/.bun/bin/node"
    if [[ -x "$bun_bin" ]]; then
        # Idempotency: handle an existing broken symlink and avoid clobbering a real node binary.
        if [[ -L "$node_link" ]]; then
            local current_node_target=""
            if command -v readlink &>/dev/null; then
                current_node_target="$(readlink "$node_link" 2>/dev/null || true)"
            fi
            if [[ "$current_node_target" != "$bun_bin" ]]; then
                log_detail "Updating node symlink for Bun compatibility"
                try_step "Updating node symlink" run_as_target ln -sf "$bun_bin" "$node_link" || log_warn "Failed to update node symlink"
            fi
        elif [[ ! -e "$node_link" ]]; then
            log_detail "Creating node symlink for Bun compatibility"
            try_step "Creating node symlink" run_as_target ln -s "$bun_bin" "$node_link" || log_warn "Failed to create node symlink"
        else
            log_detail "node already exists in $TARGET_HOME/.bun/bin (leaving as-is)"
        fi
    fi

    # Rust nightly (install as target user)
    # We use nightly for latest features and to install tools like dust/lsd
    local cargo_bin="$TARGET_HOME/.cargo/bin/cargo"
    if [[ ! -x "$cargo_bin" ]]; then
        log_detail "Installing Rust nightly for $TARGET_USER"
        try_step "Installing Rust nightly" acfs_run_verified_upstream_script_as_target "rust" "sh" -y --default-toolchain nightly || return 1
    fi

    # Go (system-wide)
    if ! command_exists go; then
        log_detail "Installing Go"
        try_step "Installing Go" $SUDO apt-get install -y golang-go || return 1
    fi

    # uv (install as target user)
    if [[ -x "$TARGET_HOME/.local/bin/uv" ]] || [[ -x "$TARGET_HOME/.cargo/bin/uv" ]] || command -v uv &>/dev/null; then
        log_detail "uv already installed"
    else
        log_detail "Installing uv for $TARGET_USER"
        try_step "Installing uv" acfs_run_verified_upstream_script_as_target "uv" "sh" || return 1
    fi
}

install_languages_legacy_tools() {
    local cargo_bin="$TARGET_HOME/.cargo/bin/cargo"

    # Helper to install cargo tools with fallback
    _cargo_install() {
        local tool="$1"
        local bin_name="${2:-$1}"
        if [[ ! -x "$TARGET_HOME/.cargo/bin/$bin_name" ]]; then
            if [[ -x "$cargo_bin" ]]; then
                log_detail "Installing $tool via cargo"
                if try_step "Installing $tool via cargo" run_as_target "$cargo_bin" install "$tool" --locked 2>/dev/null || \
                   try_step "Installing $tool via cargo (no --locked)" run_as_target "$cargo_bin" install "$tool"; then
                    log_success "$tool installed"
                else
                    log_warn "Failed to install $tool (optional)"
                fi
            fi
        fi
    }

    # ast-grep (sg) - required by UBS for syntax-aware scanning
    if [[ ! -x "$TARGET_HOME/.cargo/bin/sg" ]]; then
        if [[ -x "$cargo_bin" ]]; then
            log_detail "Installing ast-grep (sg) via cargo"
            if try_step "Installing ast-grep via cargo" run_as_target "$cargo_bin" install ast-grep --locked; then
                log_success "ast-grep installed"
            else
                log_fatal "Failed to install ast-grep (sg)"
            fi
        else
            log_fatal "Cargo not found at $cargo_bin (cannot install ast-grep)"
        fi
    fi

    # Install additional cargo tools (dust, lsd, etc.)
    # These are better than apt versions and always up-to-date
    # Optimization: batch install all needed tools in one cargo command
    # This downloads the index once and allows parallel compilation
    local cargo_tools_needed=()
    local -A cargo_bin_map=(
        ["du-dust"]="dust"
        ["lsd"]="lsd"
        ["bat"]="bat"
        ["fd-find"]="fd"
        ["ripgrep"]="rg"
    )

    # Collect tools that need to be installed
    for tool in du-dust lsd bat fd-find ripgrep; do
        local bin_name="${cargo_bin_map[$tool]}"
        if [[ ! -x "$TARGET_HOME/.cargo/bin/$bin_name" ]]; then
            cargo_tools_needed+=("$tool")
        fi
    done

    # Batch install if there are tools to install
    if [[ ${#cargo_tools_needed[@]} -gt 0 ]] && [[ -x "$cargo_bin" ]]; then
        log_detail "Batch installing ${#cargo_tools_needed[@]} cargo tools: ${cargo_tools_needed[*]}"
        if try_step "Batch installing cargo tools" run_as_target "$cargo_bin" install "${cargo_tools_needed[@]}" --locked 2>/dev/null || \
           try_step "Batch installing cargo tools (no --locked)" run_as_target "$cargo_bin" install "${cargo_tools_needed[@]}"; then
            log_success "Cargo tools batch installed: ${cargo_tools_needed[*]}"
        else
            # Fallback: install individually if batch fails
            log_warn "Batch install failed, falling back to individual installs"
            _cargo_install "du-dust" "dust"
            _cargo_install "lsd"
            _cargo_install "bat" "bat"
            _cargo_install "fd-find" "fd"
            _cargo_install "ripgrep" "rg"
        fi
    fi

    # Atuin (install as target user)
    # Check both the data directory and the binary location
    if [[ -d "$TARGET_HOME/.atuin" ]] || [[ -x "$TARGET_HOME/.atuin/bin/atuin" ]] || command -v atuin &>/dev/null; then
        log_detail "Atuin already installed"
    else
        log_detail "Installing Atuin for $TARGET_USER"
        try_step "Installing Atuin" acfs_run_verified_upstream_script_as_target "atuin" "sh" || return 1
    fi

    # Zoxide (install as target user)
    # Check multiple possible locations
    if [[ -x "$TARGET_HOME/.local/bin/zoxide" ]] || [[ -x "/usr/local/bin/zoxide" ]] || command -v zoxide &>/dev/null; then
        log_detail "Zoxide already installed"
    else
        log_detail "Installing Zoxide for $TARGET_USER"
        try_step "Installing Zoxide" acfs_run_verified_upstream_script_as_target "zoxide" "sh" || return 1
    fi
}

install_languages() {
    set_phase "languages" "Language Runtimes"
    log_step "5/9" "Installing language runtimes..."

    local ran_any=false

    if acfs_use_generated_category "lang"; then
        log_detail "Using generated installers for lang (phase 6)"
        acfs_run_generated_category_phase "lang" "6" || return 1
        ran_any=true
    else
        install_languages_legacy_lang || return 1
        ran_any=true
    fi

    if acfs_use_generated_category "tools"; then
        log_detail "Using generated installers for tools (phase 6)"
        acfs_run_generated_category_phase "tools" "6" || return 1
        ran_any=true
    else
        install_languages_legacy_tools || return 1
        ran_any=true
    fi

    if [[ "$ran_any" != "true" ]]; then
        log_warn "No language/tool modules selected"
    fi

    log_success "Language runtimes installed"
}

# ============================================================
# Phase 6: Coding agents
# ============================================================
install_agents_phase() {
    set_phase "agents" "Coding Agents"
    log_step "6/9" "Installing coding agents..."

    if acfs_use_generated_category "agents"; then
        log_detail "Using generated installers for agents (phase 7)"
        acfs_run_generated_category_phase "agents" "7" || return 1

        # CI/doctor expectations: ensure `claude` resolves to ~/.local/bin/claude.
        # The native installer can choose non-standard paths, and bun installs land in ~/.bun/bin.
        local claude_bin_local="$TARGET_HOME/.local/bin/claude"
        if [[ ! -x "$claude_bin_local" ]]; then
            run_as_target mkdir -p "$TARGET_HOME/.local/bin" 2>/dev/null || true

            local claude_candidate=""
            local candidates=(
                "$TARGET_HOME/.claude/bin/claude"
                "$TARGET_HOME/.claude/local/bin/claude"
                "$TARGET_HOME/.bun/bin/claude"
            )
            for claude_candidate in "${candidates[@]}"; do
                if [[ -x "$claude_candidate" ]]; then
                    break
                fi
                claude_candidate=""
            done

            if [[ -z "$claude_candidate" ]] && [[ -d "$TARGET_HOME/.claude" ]]; then
                claude_candidate="$(run_as_target find "$TARGET_HOME/.claude" -maxdepth 4 -type f -name claude -perm -111 -print -quit 2>/dev/null || true)"
            fi

            if [[ -n "$claude_candidate" ]] && [[ -x "$claude_candidate" ]]; then
                try_step "Linking Claude Code into ~/.local/bin" run_as_target ln -sf "$claude_candidate" "$claude_bin_local" || true
            fi
        fi

        log_success "Coding agents installed"
        return 0
    fi

    # Use target user's bun
    local bun_bin="$TARGET_HOME/.bun/bin/bun"

    if [[ ! -x "$bun_bin" ]]; then
        log_warn "Bun not found at $bun_bin, skipping agent CLI installation"
        return 0
    fi

    # Claude Code (install as target user)
    # NOTE: The native installer may choose a non-standard install path; CI smoke
    # checks require claude to exist at ~/.local/bin/claude or ~/.bun/bin/claude.
    local claude_bin_local="$TARGET_HOME/.local/bin/claude"
    local claude_bin_bun="$TARGET_HOME/.bun/bin/claude"
    if [[ -x "$claude_bin_local" ]]; then
        log_detail "Claude Code already installed ($claude_bin_local)"
    elif [[ -x "$claude_bin_bun" ]]; then
        log_detail "Claude Code already installed ($claude_bin_bun)"
    else
        run_as_target mkdir -p "$TARGET_HOME/.local/bin" 2>/dev/null || true

        log_detail "Installing Claude Code (native) for $TARGET_USER"
        try_step "Installing Claude Code (native)" acfs_run_verified_upstream_script_as_target "claude" "bash" stable || true

        if [[ ! -x "$claude_bin_local" && ! -x "$claude_bin_bun" ]]; then
            log_detail "Claude Code not found in standard paths; attempting bun install"
            try_step "Installing Claude Code (bun)" run_as_target "$bun_bin" install -g --trust @anthropic-ai/claude-code@stable || true
        fi

        # Best-effort: if claude landed in ~/.claude/*, link it into ~/.local/bin.
        if [[ ! -x "$claude_bin_local" && ! -x "$claude_bin_bun" ]]; then
            local claude_candidate=""
            local candidates=(
                "$TARGET_HOME/.claude/bin/claude"
                "$TARGET_HOME/.claude/local/bin/claude"
            )
            for claude_candidate in "${candidates[@]}"; do
                if [[ -x "$claude_candidate" ]]; then
                    break
                fi
                claude_candidate=""
            done

            if [[ -z "$claude_candidate" ]] && [[ -d "$TARGET_HOME/.claude" ]]; then
                claude_candidate="$(run_as_target find "$TARGET_HOME/.claude" -maxdepth 4 -type f -name claude -perm -111 -print -quit 2>/dev/null || true)"
            fi

            if [[ -n "$claude_candidate" ]] && [[ -x "$claude_candidate" ]]; then
                try_step "Linking Claude Code into ~/.local/bin" run_as_target ln -sf "$claude_candidate" "$claude_bin_local" || true
            fi
        fi

        if [[ -x "$claude_bin_local" || -x "$claude_bin_bun" ]]; then
            log_success "Claude Code installed"
        else
            log_warn "Claude Code installation may have failed (claude not found in standard paths)"
        fi
    fi

    # Prefer ~/.local/bin for Claude to avoid PATH conflict warnings in acfs doctor.
    # (If Claude was installed via bun, link it into ~/.local/bin which is earlier in PATH.)
    if [[ ! -x "$claude_bin_local" && -x "$claude_bin_bun" ]]; then
        run_as_target mkdir -p "$TARGET_HOME/.local/bin" 2>/dev/null || true
        try_step "Linking Claude Code into ~/.local/bin" run_as_target ln -sf "$claude_bin_bun" "$claude_bin_local" || true
    fi

    # Codex CLI (install as target user)
    # Uses fallback chain: @latest -> unversioned -> pinned 0.87.0
    # npm can 404 briefly after publishing; pinned version is reliable fallback
    log_detail "Installing Codex CLI for $TARGET_USER"
    try_step "Installing Codex CLI" run_as_target bash -c '
        set -euo pipefail
        bun_bin="$1"
        CODEX_FALLBACK_VERSION="0.87.0"
        if "$bun_bin" install -g --trust @openai/codex@latest 2>/dev/null; then
            exit 0
        fi
        echo "WARN: Codex CLI @latest failed; retrying unversioned" >&2
        if "$bun_bin" install -g --trust @openai/codex 2>/dev/null; then
            exit 0
        fi
        echo "WARN: Codex CLI unversioned failed; retrying pinned $CODEX_FALLBACK_VERSION" >&2
        "$bun_bin" install -g --trust "@openai/codex@$CODEX_FALLBACK_VERSION"
    ' _ "$bun_bin" || true

    # Create wrapper script that uses bun as runtime (avoids node PATH issues)
    local codex_bin_local="$TARGET_HOME/.local/bin/codex"
    if [[ -x "$TARGET_HOME/.bun/bin/codex" ]] && [[ ! -x "$codex_bin_local" ]]; then
        run_as_target mkdir -p "$TARGET_HOME/.local/bin" 2>/dev/null || true
        # shellcheck disable=SC2016  # Variables expand inside the bash -c script, not here.
        try_step "Creating Codex bun wrapper" run_as_target bash -c '
            set -euo pipefail
            wrapper_path="$1"
            printf "%s\n" "#!/bin/bash" "exec ~/.bun/bin/bun ~/.bun/bin/codex \"\$@\"" > "$wrapper_path"
            chmod +x "$wrapper_path"
        ' _ "$codex_bin_local" || true
    fi

    # Gemini CLI (install as target user)
    log_detail "Installing Gemini CLI for $TARGET_USER"
    try_step "Installing Gemini CLI" run_as_target "$bun_bin" install -g --trust @google/gemini-cli@latest || true

    # Create wrapper script that uses bun as runtime (avoids node PATH issues)
    local gemini_bin_local="$TARGET_HOME/.local/bin/gemini"
    if [[ -x "$TARGET_HOME/.bun/bin/gemini" ]] && [[ ! -x "$gemini_bin_local" ]]; then
        run_as_target mkdir -p "$TARGET_HOME/.local/bin" 2>/dev/null || true
        # shellcheck disable=SC2016  # Variables expand inside the bash -c script, not here.
        try_step "Creating Gemini bun wrapper" run_as_target bash -c '
            set -euo pipefail
            wrapper_path="$1"
            printf "%s\n" "#!/bin/bash" "exec ~/.bun/bin/bun ~/.bun/bin/gemini \"\$@\"" > "$wrapper_path"
            chmod +x "$wrapper_path"
        ' _ "$gemini_bin_local" || true
    fi

    log_success "Coding agents installed"
}

# ============================================================
# Phase 7: Cloud & database tools
# ============================================================
install_cloud_db_legacy_db() {
    local codename="$1"

    # PostgreSQL 18 (via PGDG)
    if [[ "$SKIP_POSTGRES" == "true" ]]; then
        log_detail "Skipping PostgreSQL (--skip-postgres)"
    elif command_exists psql; then
        log_detail "PostgreSQL already installed ($(psql --version 2>/dev/null | head -1 || echo 'psql'))"
    else
        # PGDG may lag behind new Ubuntu codenames (e.g. 25.10) - fall back to noble (24.04 LTS) when needed.
        local pgdg_codename="$codename"
        if command_exists curl && ! curl -sfI "https://apt.postgresql.org/pub/repos/apt/dists/${codename}-pgdg/Release" >/dev/null 2>&1; then
            pgdg_codename="noble"
            log_detail "PGDG repo unavailable for $codename, using $pgdg_codename"
        fi

        log_detail "Installing PostgreSQL 18 (PGDG repo, codename=$pgdg_codename)"
        try_step "Creating apt keyrings for PostgreSQL" $SUDO mkdir -p /etc/apt/keyrings || true

        if ! try_step_eval "Adding PostgreSQL apt key" "set -o pipefail; if curl --help all 2>/dev/null | grep -q -- '--proto'; then curl --proto '=https' --proto-redir '=https' -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc; else curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc; fi | $SUDO gpg --batch --yes --dearmor -o /etc/apt/keyrings/postgresql.gpg 2>/dev/null"; then
            log_warn "PostgreSQL: failed to install signing key (skipping)"
        else
            try_step_eval "Adding PostgreSQL apt repo" "echo 'deb [signed-by=/etc/apt/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt ${pgdg_codename}-pgdg main' | $SUDO tee /etc/apt/sources.list.d/pgdg.list > /dev/null" || true

            try_step "Updating apt cache for PostgreSQL" $SUDO apt-get update -y || log_warn "PostgreSQL: apt-get update failed (continuing)"

            if try_step "Installing PostgreSQL 18" $SUDO apt-get install -y postgresql-18 postgresql-client-18; then
                log_success "PostgreSQL 18 installed"

                # Best-effort service start (GitHub Actions containers may not have systemd)
                if command_exists systemctl && [[ -d /run/systemd/system ]]; then
                    try_step "Enabling PostgreSQL service" $SUDO systemctl enable postgresql || true
                    try_step "Starting PostgreSQL service" $SUDO systemctl start postgresql || true
                elif command_exists pg_ctlcluster; then
                    # Start directly without systemd to avoid noisy `systemctl` errors in containers.
                    try_step "Starting PostgreSQL cluster" $SUDO pg_ctlcluster 18 main start || true
                elif command_exists service; then
                    try_step "Starting PostgreSQL service (service)" $SUDO service postgresql start || true
                fi

                # Best-effort role + db for target user
                if command_exists runuser; then
                    $SUDO runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$TARGET_USER'" | grep -q 1 || \
                        $SUDO runuser -u postgres -- createuser -s "$TARGET_USER" 2>/dev/null || true
                    $SUDO runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='$TARGET_USER'" | grep -q 1 || \
                        $SUDO runuser -u postgres -- createdb "$TARGET_USER" 2>/dev/null || true
                elif command_exists sudo; then
                    sudo -u postgres -H psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$TARGET_USER'" | grep -q 1 || \
                        sudo -u postgres -H createuser -s "$TARGET_USER" 2>/dev/null || true
                    sudo -u postgres -H psql -tAc "SELECT 1 FROM pg_database WHERE datname='$TARGET_USER'" | grep -q 1 || \
                        sudo -u postgres -H createdb "$TARGET_USER" 2>/dev/null || true
                fi
            else
                log_warn "PostgreSQL: installation failed (optional)"
            fi
        fi
    fi
}

install_cloud_db_legacy_tools() {
    local codename="$1"

    # Vault (HashiCorp apt repo)
    if [[ "$SKIP_VAULT" == "true" ]]; then
        log_detail "Skipping Vault (--skip-vault)"
    elif command_exists vault; then
        log_detail "Vault already installed ($(vault --version 2>/dev/null | head -1 || echo 'vault'))"
    else
        # HashiCorp doesn't always have packages for newest Ubuntu versions.
        # Check if the current codename is supported, otherwise fall back to noble (24.04 LTS).
        local vault_codename="$codename"
        if ! curl -sfI "https://apt.releases.hashicorp.com/dists/${codename}/main/binary-amd64/Packages" >/dev/null 2>&1; then
            vault_codename="noble"
            log_detail "HashiCorp repo unavailable for $codename, using $vault_codename"
        fi

        log_detail "Installing Vault (HashiCorp repo, codename=$vault_codename)"
        try_step "Creating apt keyrings for Vault" $SUDO mkdir -p /etc/apt/keyrings || true

        if ! try_step_eval "Adding HashiCorp apt key" "set -o pipefail; if curl --help all 2>/dev/null | grep -q -- '--proto'; then curl --proto '=https' --proto-redir '=https' -fsSL https://apt.releases.hashicorp.com/gpg; else curl -fsSL https://apt.releases.hashicorp.com/gpg; fi | $SUDO gpg --batch --yes --dearmor -o /etc/apt/keyrings/hashicorp.gpg 2>/dev/null"; then
            log_warn "Vault: failed to install signing key (skipping)"
        else
            try_step_eval "Adding HashiCorp apt repo" "echo 'deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com ${vault_codename} main' | $SUDO tee /etc/apt/sources.list.d/hashicorp.list > /dev/null" || true

            try_step "Updating apt cache for Vault" $SUDO apt-get update -y || log_warn "Vault: apt-get update failed (continuing)"
            if try_step "Installing Vault" $SUDO apt-get install -y vault; then
                log_success "Vault installed"
            else
                log_warn "Vault: installation failed (optional)"
            fi
        fi
    fi
}

install_supabase_cli_release() {
    local arch=""
    case "$(uname -m)" in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)
            log_error "Supabase CLI: unsupported architecture ($(uname -m))"
            return 1
            ;;
    esac

    local release_url=""
    release_url="$(acfs_curl -o /dev/null -w '%{url_effective}\n' "https://github.com/supabase/cli/releases/latest" 2>/dev/null | tail -n1)" || true
    local tag="${release_url##*/}"
    if [[ -z "$tag" ]] || [[ "$tag" != v* ]]; then
        log_error "Supabase CLI: failed to resolve latest release tag"
        return 1
    fi

    local version="${tag#v}"
    local base_url="https://github.com/supabase/cli/releases/download/${tag}"
    local tarball="supabase_linux_${arch}.tar.gz"
    local checksums="supabase_${version}_checksums.txt"

    local tmp_dir=""
    local tmp_tgz=""
    local tmp_checksums=""
    if command -v mktemp &>/dev/null; then
        tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/acfs-supabase.XXXXXX" 2>/dev/null)" || tmp_dir=""
        tmp_tgz="$(mktemp "${TMPDIR:-/tmp}/acfs-supabase.tgz.XXXXXX" 2>/dev/null)" || tmp_tgz=""
        tmp_checksums="$(mktemp "${TMPDIR:-/tmp}/acfs-supabase.sha.XXXXXX" 2>/dev/null)" || tmp_checksums=""
    fi

    if [[ -z "$tmp_dir" ]] || [[ -z "$tmp_tgz" ]] || [[ -z "$tmp_checksums" ]]; then
        log_error "Supabase CLI: failed to create temp files"
        return 1
    fi

    if ! acfs_curl -o "$tmp_tgz" "${base_url}/${tarball}" 2>/dev/null; then
        log_error "Supabase CLI: failed to download ${tarball}"
        return 1
    fi
    if ! acfs_curl -o "$tmp_checksums" "${base_url}/${checksums}" 2>/dev/null; then
        log_error "Supabase CLI: failed to download checksums"
        return 1
    fi

    local expected_sha=""
    expected_sha="$(grep -E " ${tarball}\$" "$tmp_checksums" 2>/dev/null | awk '{print $1}' | head -n1)" || true
    if [[ -z "$expected_sha" ]]; then
        log_error "Supabase CLI: checksum entry not found for ${tarball}"
        return 1
    fi

    local actual_sha=""
    actual_sha="$(acfs_calculate_file_sha256 "$tmp_tgz" 2>/dev/null)" || actual_sha=""
    if [[ -z "$actual_sha" ]] || [[ "$actual_sha" != "$expected_sha" ]]; then
        log_error "Supabase CLI: checksum mismatch"
        log_error "  Expected: $expected_sha"
        log_error "  Actual:   ${actual_sha:-<missing>}"
        return 1
    fi

    # Extract only the binary if possible (keeps tmp dir clean).
    if ! tar -xzf "$tmp_tgz" -C "$tmp_dir" supabase 2>/dev/null; then
        tar -xzf "$tmp_tgz" -C "$tmp_dir" 2>/dev/null || {
            log_error "Supabase CLI: failed to extract tarball"
            return 1
        }
    fi

    local extracted_bin="$tmp_dir/supabase"
    if [[ ! -f "$extracted_bin" ]]; then
        extracted_bin="$(find "$tmp_dir" -maxdepth 2 -type f -name supabase -print -quit 2>/dev/null || true)"
    fi
    if [[ -z "$extracted_bin" ]] || [[ ! -f "$extracted_bin" ]]; then
        log_error "Supabase CLI: binary not found after extract"
        return 1
    fi

    chmod 755 "$tmp_dir" 2>/dev/null || true
    chmod 755 "$extracted_bin" 2>/dev/null || true

    run_as_target mkdir -p "$TARGET_HOME/.local/bin" 2>/dev/null || true
    if ! run_as_target install -m 0755 "$extracted_bin" "$TARGET_HOME/.local/bin/supabase"; then
        log_error "Supabase CLI: failed to install into ~/.local/bin"
        return 1
    fi
    if ! run_as_target "$TARGET_HOME/.local/bin/supabase" --version >/dev/null 2>&1; then
        log_error "Supabase CLI: installed but failed to run"
        return 1
    fi

    # Best-effort cleanup
    rm -f "$tmp_tgz" "$tmp_checksums" "$extracted_bin" 2>/dev/null || true
    rmdir "$tmp_dir" 2>/dev/null || true

    return 0
}

install_cloud_db_legacy_cloud() {
    # Cloud CLIs (bun global installs)
    if [[ "$SKIP_CLOUD" == "true" ]]; then
        log_detail "Skipping cloud CLIs (--skip-cloud)"
    else
        local bun_bin="$TARGET_HOME/.bun/bin/bun"
        if [[ ! -x "$bun_bin" ]]; then
            log_warn "Cloud CLIs: bun not found at $bun_bin (skipping)"
        else
            local cli
            for cli in wrangler supabase vercel; do
                if [[ "$cli" == "supabase" ]]; then
                    if [[ -x "$TARGET_HOME/.local/bin/supabase" ]] || [[ -x "$TARGET_HOME/.bun/bin/supabase" ]]; then
                        log_detail "supabase already installed"
                        continue
                    fi

                    log_detail "Installing supabase (direct binary)"
                    if try_step "Installing supabase" install_supabase_cli_release; then
                        log_success "supabase installed"
                    else
                        log_warn "supabase installation failed (optional)"
                    fi
                    continue
                fi

                if [[ -x "$TARGET_HOME/.bun/bin/$cli" ]]; then
                    log_detail "$cli already installed"
                    continue
                fi

                log_detail "Installing $cli via bun"
                if try_step "Installing $cli via bun" run_as_target "$bun_bin" install -g --trust "${cli}@latest"; then
                    if [[ -x "$TARGET_HOME/.bun/bin/$cli" ]]; then
                        log_success "$cli installed"
                    else
                        log_warn "$cli: install finished but binary not found"
                    fi
                else
                    log_warn "$cli installation failed (optional)"
                fi
            done
        fi
    fi
}

install_cloud_db_legacy() {
    # Cloud CLIs (bun global installs)
    if [[ "$SKIP_CLOUD" == "true" ]]; then
        log_detail "Skipping cloud CLIs (--skip-cloud)"
    else
        local bun_bin="$TARGET_HOME/.bun/bin/bun"
        if [[ ! -x "$bun_bin" ]]; then
            log_warn "Cloud CLIs: bun not found at $bun_bin (skipping)"
        else
            local cli
            for cli in wrangler supabase vercel; do
                if [[ "$cli" == "supabase" ]]; then
                    if [[ -x "$TARGET_HOME/.local/bin/supabase" ]] || [[ -x "$TARGET_HOME/.bun/bin/supabase" ]]; then
                        log_detail "supabase already installed"
                        continue
                    fi

                    log_detail "Installing supabase (direct binary)"
                    if try_step "Installing supabase" install_supabase_cli_release; then
                        log_success "supabase installed"
                    else
                        log_warn "supabase installation failed (optional)"
                    fi
                    continue
                fi

                if [[ -x "$TARGET_HOME/.bun/bin/$cli" ]]; then
                    log_detail "$cli already installed"
                    continue
                fi

                log_detail "Installing $cli via bun"
                if try_step "Installing $cli via bun" run_as_target "$bun_bin" install -g --trust "${cli}@latest"; then
                    if [[ -x "$TARGET_HOME/.bun/bin/$cli" ]]; then
                        log_success "$cli installed"
                    else
                        log_warn "$cli: install finished but binary not found"
                    fi
                else
                    log_warn "$cli installation failed (optional)"
                fi
            done
        fi
    fi
}

install_cloud_db() {
    set_phase "cloud_db" "Cloud & Database Tools"
    log_step "7/9" "Installing cloud & database tools..."

    local codename="noble"
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        codename="${VERSION_CODENAME:-noble}"
    fi

    local ran_any=false

    if acfs_use_generated_category "db"; then
        log_detail "Using generated installers for db (phase 8)"
        acfs_run_generated_category_phase "db" "8" || return 1
        ran_any=true
    else
        install_cloud_db_legacy_db "$codename" || return 1
        ran_any=true
    fi

    if acfs_use_generated_category "tools"; then
        log_detail "Using generated installers for tools (phase 8)"
        acfs_run_generated_category_phase "tools" "8" || return 1
        ran_any=true
    else
        install_cloud_db_legacy_tools "$codename" || return 1
        ran_any=true
    fi

    if acfs_use_generated_category "cloud"; then
        log_detail "Using generated installers for cloud (phase 8)"
        acfs_run_generated_category_phase "cloud" "8" || return 1
        ran_any=true
    else
        install_cloud_db_legacy_cloud || return 1
        ran_any=true
    fi

    if [[ "$ran_any" != "true" ]]; then
        log_warn "No cloud/db/tools modules selected"
    fi

    log_success "Cloud & database tools phase complete"
}

# ============================================================
# Phase 8: Dicklesworthstone stack
# ============================================================

# Helper: check if a binary exists in common install locations
binary_installed() {
    local name="$1"
    [[ -x "$TARGET_HOME/.local/bin/$name" ]] || \
    [[ -x "/usr/local/bin/$name" ]] || \
    [[ -x "$TARGET_HOME/.bun/bin/$name" ]] || \
    [[ -x "$TARGET_HOME/.cargo/bin/$name" ]]
}

install_stack_phase() {
    set_phase "stack" "Dicklesworthstone Stack"
    log_step "8/9" "Installing Dicklesworthstone stack..."

    if acfs_use_generated_category "stack"; then
        log_detail "Using generated installers for stack (phase 9)"
        acfs_run_generated_category_phase "stack" "9" || return 1
        log_success "Dicklesworthstone stack installed"
        return 0
    fi

    # NTM (Named Tmux Manager)
    if binary_installed "ntm"; then
        log_detail "NTM already installed"
    else
        log_detail "Installing NTM"
        # The upstream installer can exit non-zero in non-interactive CI while still
        # successfully installing. Run it best-effort, then verify the binary.
        local ntm_exit=0
        acfs_run_verified_upstream_script_as_target "ntm" "bash" --no-shell || ntm_exit=$?

        if _smoke_run_as_target "command -v ntm >/dev/null && ntm --help >/dev/null 2>&1"; then
            log_success "NTM installed"
        else
            log_warn "NTM installation failed (installer exit ${ntm_exit}; ntm not working)"
        fi
    fi

    # Configure NTM with current model defaults (issue #39)
    # NTM ships with outdated defaults; create config with current recommended models
    local ntm_config_dir="$TARGET_HOME/.config/ntm"
    local ntm_config_file="$ntm_config_dir/config.toml"
    if binary_installed "ntm"; then
        if [[ ! -f "$ntm_config_file" ]]; then
            log_detail "Creating NTM config with current model defaults"
            run_as_target mkdir -p "$ntm_config_dir" || true
            if run_as_target cat > "$ntm_config_file" << 'NTM_CONFIG_EOF'
# NTM Configuration - created by ACFS
# Updated model defaults for ChatGPT Pro and Gemini accounts

# Codex model - gpt-5.2-codex with xhigh reasoning (works with ChatGPT Pro)
default_codex = "gpt-5.2-codex"
codex_reasoning_effort = "xhigh"

# Gemini model - gemini-3 pro preview
default_gemini = "gemini-3-pro-preview"

# Claude model - Opus 4.5 (most capable)
default_claude = "claude-opus-4-5"
NTM_CONFIG_EOF
            then
                log_success "NTM config created with current model defaults"
            else
                log_warn "Failed to create NTM config"
            fi
        else
            log_detail "NTM config already exists, skipping"
        fi
    fi

    # MCP Agent Mail (check for mcp-agent-mail stub or mcp_agent_mail directory)
    # NOTE: We run this in tmux because the installer starts the server which blocks
    if binary_installed "mcp-agent-mail" || [[ -d "$TARGET_HOME/mcp_agent_mail" ]]; then
        log_detail "MCP Agent Mail already installed"
    else
        log_detail "Installing MCP Agent Mail (in tmux session)"
        # Create or use acfs-services tmux session, run installer in first pane.
        # The installer will start the server, which runs persistently in tmux.
        local tmux_session="acfs-services"
        local tool="mcp_agent_mail"
        local target_dir="$TARGET_HOME/mcp_agent_mail"

        # Fetch + verify the installer script, then run it in tmux to avoid blocking.
        if acfs_load_upstream_checksums; then
            local url="${ACFS_UPSTREAM_URLS[$tool]:-}"
            local expected_sha256="${ACFS_UPSTREAM_SHA256[$tool]:-}"

            if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then
                log_warn "MCP Agent Mail: missing installer URL/checksum"
            else
                local tmp_install
                tmp_install="$(mktemp "${TMPDIR:-/tmp}/acfs-install-${tool}.XXXXXX" 2>/dev/null)" || tmp_install=""

                if [[ -n "$tmp_install" ]] && verify_checksum "$url" "$expected_sha256" "$tool" > "$tmp_install"; then
                    chmod 755 "$tmp_install" 2>/dev/null || true

                    # Kill existing session if any (clean slate)
                    run_as_target tmux kill-session -t "$tmux_session" 2>/dev/null || true

                    # Create new detached session and run the installer
                    if try_step "Installing MCP Agent Mail in tmux" run_as_target tmux new-session -d -s "$tmux_session" "$tmp_install" --dir "$target_dir" --yes; then
                        log_success "MCP Agent Mail installing in tmux session '$tmux_session'"
                        log_info "Attach with: tmux attach -t $tmux_session"
                        # Give it a moment to start
                        sleep 5
                    else
                        log_warn "MCP Agent Mail tmux installation may have failed"
                    fi
                else
                    rm -f "$tmp_install" 2>/dev/null || true
                    log_warn "MCP Agent Mail: installer verification failed"
                fi
            fi
        else
            log_warn "MCP Agent Mail: unable to load upstream checksums; refusing to run unverified installer"
        fi
    fi

    # Ultimate Bug Scanner
    if binary_installed "ubs"; then
        log_detail "Ultimate Bug Scanner already installed"
    else
        log_detail "Installing Ultimate Bug Scanner"
        try_step "Installing UBS" acfs_run_verified_upstream_script_as_target "ubs" "bash" --easy-mode || log_warn "UBS installation may have failed"
    fi

    # Beads Viewer
    if binary_installed "bv"; then
        log_detail "Beads Viewer already installed"
    else
        log_detail "Installing Beads Viewer"
        try_step "Installing Beads Viewer" acfs_run_verified_upstream_script_as_target "bv" "bash" || log_warn "Beads Viewer installation may have failed"
    fi

    # CASS (Coding Agent Session Search)
    if binary_installed "cass"; then
        log_detail "CASS already installed"
    else
        log_detail "Installing CASS"
        try_step "Installing CASS" acfs_run_verified_upstream_script_as_target "cass" "bash" --easy-mode --verify || log_warn "CASS installation may have failed"
    fi

    # CASS Memory System
    if binary_installed "cm"; then
        log_detail "CASS Memory System already installed"
    else
        log_detail "Installing CASS Memory System"
        try_step "Installing CM" acfs_run_verified_upstream_script_as_target "cm" "bash" --easy-mode --verify || log_warn "CM installation may have failed"
    fi

    # CAAM (Coding Agent Account Manager)
    if binary_installed "caam"; then
        log_detail "CAAM already installed"
    else
        log_detail "Installing CAAM"
        try_step "Installing CAAM" acfs_run_verified_upstream_script_as_target "caam" "bash" || log_warn "CAAM installation may have failed"
    fi

    # SLB (Simultaneous Launch Button)
    if binary_installed "slb"; then
        log_detail "SLB already installed"
    else
        log_detail "Installing SLB"
        try_step "Installing SLB" acfs_run_verified_upstream_script_as_target "slb" "bash" || log_warn "SLB installation may have failed"
    fi

    # RU (Repo Updater)
    if binary_installed "ru"; then
        log_detail "RU already installed"
    else
        log_detail "Installing RU"
        try_step "Installing RU" acfs_run_verified_upstream_script_as_target "ru" "bash" || log_warn "RU installation may have failed"
    fi

    # DCG (Destructive Command Guard)
    if binary_installed "dcg"; then
        log_detail "DCG already installed"
    else
        log_info "Installing DCG (Destructive Command Guard)..."
        log_detail "DCG blocks destructive git/fs commands before they run"
        if try_step "Installing DCG" acfs_run_verified_upstream_script_as_target "dcg" "bash"; then
            log_success "DCG installed. Run 'dcg doctor' to verify."
        else
            log_warn "DCG installation may have failed"
            log_detail "Recovery: re-run the installer or run the DCG installer manually, then run: dcg install"
        fi
    fi

    # Best-effort hook registration (Claude Code)
    local dcg_bin=""
    if [[ -x "$TARGET_HOME/.local/bin/dcg" ]]; then
        dcg_bin="$TARGET_HOME/.local/bin/dcg"
    elif [[ -x "$TARGET_HOME/.cargo/bin/dcg" ]]; then
        dcg_bin="$TARGET_HOME/.cargo/bin/dcg"
    elif [[ -x "/usr/local/bin/dcg" ]]; then
        dcg_bin="/usr/local/bin/dcg"
    fi

    if [[ -n "$dcg_bin" ]]; then
        if try_step "Registering DCG hook" run_as_target "$dcg_bin" install; then
            log_success "DCG hook registered with Claude Code"
        else
            log_warn "DCG hook registration failed"
            log_detail "Next steps: run: dcg install and check with: dcg doctor"
        fi
    else
        log_warn "DCG hook not registered (dcg binary not found in standard paths)"
        log_detail "Install DCG first, then run: dcg install"
    fi

    log_success "Dicklesworthstone stack installed"
}

# ============================================================
# Phase 9: Final wiring
# ============================================================
finalize() {
    set_phase "finalize" "Final Wiring"
    log_step "9/9" "Finalizing installation..."

    if acfs_use_generated_category "acfs"; then
        log_detail "Using generated installers for acfs (phase 10)"
        acfs_run_generated_category_phase "acfs" "10" || return 1
        log_success "Final wiring complete"
        return 0
    fi

    # Copy tmux config
    log_detail "Installing tmux config"
    try_step "Installing tmux config" install_asset "acfs/tmux/tmux.conf" "$ACFS_HOME/tmux/tmux.conf" || return 1
    try_step "Setting tmux config ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/tmux/tmux.conf" || return 1

    # Link to target user's tmux.conf if it doesn't exist
    if [[ ! -f "$TARGET_HOME/.tmux.conf" ]]; then
        try_step "Linking tmux.conf" run_as_target ln -sf "$ACFS_HOME/tmux/tmux.conf" "$TARGET_HOME/.tmux.conf" || return 1
    fi

    # Reload tmux config if server is running (fixes #66: prefix key works immediately)
    # This handles the case where tmux started in an earlier phase before config was deployed
    # Note: Use $TARGET_HOME, not ~, since ~ expands to the installer's user (often root)
    run_as_target tmux source-file "$TARGET_HOME/.tmux.conf" 2>/dev/null || true

    # Install onboard lessons + command
    log_detail "Installing onboard lessons"
    try_step "Creating onboard lessons directory" $SUDO mkdir -p "$ACFS_HOME/onboard/lessons" || return 1
    local lesson_files=(
        "00_welcome.md"
        "01_linux_basics.md"
        "02_ssh_basics.md"
        "03_tmux_basics.md"
        "04_agents_login.md"
        "05_ntm_core.md"
        "06_ntm_command_palette.md"
        "07_flywheel_loop.md"
        "08_keeping_updated.md"
        "09_ru.md"
        "10_dcg.md"
    )
    local lesson
    for lesson in "${lesson_files[@]}"; do
        try_step "Installing onboard lesson: $lesson" install_asset "acfs/onboard/lessons/$lesson" "$ACFS_HOME/onboard/lessons/$lesson" || return 1
    done

    log_detail "Installing onboard command"
    try_step "Installing onboard script" install_asset "packages/onboard/onboard.sh" "$ACFS_HOME/onboard/onboard.sh" || return 1
    try_step "Setting onboard permissions" $SUDO chmod 755 "$ACFS_HOME/onboard/onboard.sh" || return 1
    try_step "Setting onboard ownership" acfs_chown_tree "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/onboard" || return 1

    try_step "Creating .local/bin directory" run_as_target mkdir -p "$TARGET_HOME/.local/bin" || return 1
    try_step "Linking onboard command" run_as_target ln -sf "$ACFS_HOME/onboard/onboard.sh" "$TARGET_HOME/.local/bin/onboard" || return 1

    # Install acfs scripts (for acfs CLI subcommands)
    log_detail "Installing acfs scripts"
    try_step "Creating ACFS scripts directory" $SUDO mkdir -p "$ACFS_HOME/scripts/lib" || return 1
    
    # Install script libraries
    try_step "Installing logging.sh" install_asset "scripts/lib/logging.sh" "$ACFS_HOME/scripts/lib/logging.sh" || return 1
    try_step "Installing gum_ui.sh" install_asset "scripts/lib/gum_ui.sh" "$ACFS_HOME/scripts/lib/gum_ui.sh" || return 1
    try_step "Installing security.sh" install_asset "scripts/lib/security.sh" "$ACFS_HOME/scripts/lib/security.sh" || return 1
    try_step "Installing doctor.sh" install_asset "scripts/lib/doctor.sh" "$ACFS_HOME/scripts/lib/doctor.sh" || return 1
    try_step "Installing update.sh" install_asset "scripts/lib/update.sh" "$ACFS_HOME/scripts/lib/update.sh" || return 1
    try_step "Installing session.sh" install_asset "scripts/lib/session.sh" "$ACFS_HOME/scripts/lib/session.sh" || return 1
    try_step "Installing continue.sh" install_asset "scripts/lib/continue.sh" "$ACFS_HOME/scripts/lib/continue.sh" || return 1
    try_step "Installing info.sh" install_asset "scripts/lib/info.sh" "$ACFS_HOME/scripts/lib/info.sh" || return 1
    try_step "Installing cheatsheet.sh" install_asset "scripts/lib/cheatsheet.sh" "$ACFS_HOME/scripts/lib/cheatsheet.sh" || return 1
    try_step "Installing dashboard.sh" install_asset "scripts/lib/dashboard.sh" "$ACFS_HOME/scripts/lib/dashboard.sh" || return 1

    # Install acfs-update wrapper command
    try_step "Installing acfs-update" install_asset "scripts/acfs-update" "$ACFS_HOME/bin/acfs-update" || return 1
    try_step "Setting acfs-update permissions" $SUDO chmod 755 "$ACFS_HOME/bin/acfs-update" || return 1
    try_step "Setting acfs-update ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/bin/acfs-update" || return 1
    try_step "Linking acfs-update command" run_as_target ln -sf "$ACFS_HOME/bin/acfs-update" "$TARGET_HOME/.local/bin/acfs-update" || return 1

    # Install services-setup wizard
    try_step "Installing services-setup.sh" install_asset "scripts/services-setup.sh" "$ACFS_HOME/scripts/services-setup.sh" || return 1
    try_step "Setting scripts permissions" $SUDO chmod 755 "$ACFS_HOME/scripts/services-setup.sh" || return 1
    try_step "Setting lib scripts permissions" $SUDO chmod 755 "$ACFS_HOME/scripts/lib/"*.sh || return 1
    try_step "Setting scripts ownership" acfs_chown_tree "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/scripts" || return 1

    # Install newproj command scripts (used by acfs newproj CLI and TUI wizard)
    log_detail "Installing newproj scripts"
    try_step "Installing newproj.sh" install_asset "scripts/lib/newproj.sh" "$ACFS_HOME/scripts/lib/newproj.sh" || return 1
    try_step "Installing newproj_agents.sh" install_asset "scripts/lib/newproj_agents.sh" "$ACFS_HOME/scripts/lib/newproj_agents.sh" || return 1
    try_step "Installing newproj_detect.sh" install_asset "scripts/lib/newproj_detect.sh" "$ACFS_HOME/scripts/lib/newproj_detect.sh" || return 1
    try_step "Installing newproj_errors.sh" install_asset "scripts/lib/newproj_errors.sh" "$ACFS_HOME/scripts/lib/newproj_errors.sh" || return 1
    try_step "Installing newproj_logging.sh" install_asset "scripts/lib/newproj_logging.sh" "$ACFS_HOME/scripts/lib/newproj_logging.sh" || return 1
    try_step "Installing newproj_screens.sh" install_asset "scripts/lib/newproj_screens.sh" "$ACFS_HOME/scripts/lib/newproj_screens.sh" || return 1
    try_step "Installing newproj_tui.sh" install_asset "scripts/lib/newproj_tui.sh" "$ACFS_HOME/scripts/lib/newproj_tui.sh" || return 1

    try_step "Creating newproj_screens directory" $SUDO mkdir -p "$ACFS_HOME/scripts/lib/newproj_screens" || return 1
    
    local screens=(
        "screen_agents_preview.sh"
        "screen_confirmation.sh"
        "screen_directory.sh"
        "screen_features.sh"
        "screen_progress.sh"
        "screen_project_name.sh"
        "screen_success.sh"
        "screen_tech_stack.sh"
        "screen_welcome.sh"
    )
    for screen in "${screens[@]}"; do
        try_step "Installing $screen" install_asset "scripts/lib/newproj_screens/$screen" "$ACFS_HOME/scripts/lib/newproj_screens/$screen" || return 1
    done
    try_step "Setting newproj permissions" $SUDO chmod 755 "$ACFS_HOME/scripts/lib/"newproj*.sh "$ACFS_HOME/scripts/lib/newproj_screens/"*.sh || return 1
    try_step "Setting newproj ownership" acfs_chown_tree "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/scripts/lib" || return 1

    # Install checksums + version metadata so `acfs update --stack` can verify upstream scripts.
    try_step "Installing checksums.yaml" install_checksums_yaml "$ACFS_HOME/checksums.yaml" || return 1
    try_step "Installing VERSION" install_asset "VERSION" "$ACFS_HOME/VERSION" || return 1
    try_step "Setting metadata ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/checksums.yaml" "$ACFS_HOME/VERSION" || true

    # Legacy: Install doctor as acfs binary (for backwards compat)
    try_step "Installing acfs CLI" install_asset "scripts/lib/doctor.sh" "$ACFS_HOME/bin/acfs" || return 1
    try_step "Setting acfs permissions" $SUDO chmod 755 "$ACFS_HOME/bin/acfs" || return 1
    try_step "Setting acfs ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/bin/acfs" || return 1
    try_step "Linking acfs command" run_as_target ln -sf "$ACFS_HOME/bin/acfs" "$TARGET_HOME/.local/bin/acfs" || return 1

    # Install global acfs wrapper (works for root and all users)
    # This wrapper finds the target user from state and runs acfs as that user
    try_step "Installing global acfs wrapper" install_asset "scripts/acfs-global" "/usr/local/bin/acfs" || return 1
    try_step "Setting global acfs permissions" $SUDO chmod 755 "/usr/local/bin/acfs" || return 1

    # Install DCG (Destructive Command Guard) hook automatically.
    #
    # This is especially important because ACFS config includes "dangerous mode"
    # aliases (e.g., `cc`) that can run commands without interactive approvals.
    log_detail "Installing DCG (Destructive Command Guard) PreToolUse hook"
    try_step_eval "Installing DCG hook" \
        "TARGET_USER='$TARGET_USER' TARGET_HOME='$TARGET_HOME' '$ACFS_HOME/scripts/services-setup.sh' --install-claude-guard --yes" || \
        log_warn "DCG hook installation failed (optional)"

    # Legacy state file (only if state.sh is unavailable)
    if type -t state_load &>/dev/null; then
        if [[ -f "$ACFS_STATE_FILE" ]]; then
            $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_STATE_FILE" || true
        fi
    else
        cat > "$ACFS_STATE_FILE" << EOF
{
  "version": "$ACFS_VERSION",
  "installed_at": "$(date -Iseconds)",
  "mode": "$MODE",
  "target_user": "$TARGET_USER",
  "yes_mode": $YES_MODE,
  "skip_postgres": $SKIP_POSTGRES,
  "skip_vault": $SKIP_VAULT,
  "skip_cloud": $SKIP_CLOUD,
  "completed_phases": [1, 2, 3, 4, 5, 6, 7, 8, 9]
}
EOF
        $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_STATE_FILE"
    fi

    log_success "Installation complete!"
}

# ============================================================
# Post-install smoke test
# Runs quick, automatic verification at the end of install.sh
# ============================================================
_smoke_run_as_target() {
    local cmd="$1"
    if type -t run_as_target_shell &>/dev/null; then
        run_as_target_shell "$cmd"
        return $?
    fi
    run_as_target bash -c "$cmd"
}

run_smoke_test() {
    local critical_total=8
    local critical_passed=0
    local critical_failed=0
    local warnings=0

    echo "" >&2
    echo "[Smoke Test]" >&2

    # 1) Target user exists
    if id "$TARGET_USER" &>/dev/null; then
        echo "✅ User: $TARGET_USER" >&2
        ((critical_passed += 1))
    else
        echo "✖ User: missing (TARGET_USER=$TARGET_USER)" >&2
        echo "    Fix: set TARGET_USER=<user> and ensure the user exists" >&2
        ((critical_failed += 1))
    fi

    # 2) Shell is zsh
    local target_shell=""
    target_shell=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f7 || true)
    if [[ "$target_shell" == *"zsh"* ]]; then
        echo "✅ Shell: zsh" >&2
        ((critical_passed += 1))
    else
        echo "✖ Shell: zsh (found: ${target_shell:-unknown})" >&2
        echo "    Fix: sudo chsh -s \"\$(command -v zsh)\" \"$TARGET_USER\"" >&2
        ((critical_failed += 1))
    fi

    # 3) Sudo configuration
    # - vibe mode: passwordless sudo is required
    # - safe mode: sudo must exist, but may require a password
    if [[ "$MODE" == "vibe" ]]; then
        if _smoke_run_as_target "sudo -n true" &>/dev/null; then
            echo "✅ Sudo: passwordless (vibe mode)" >&2
            ((critical_passed += 1))
        else
            echo "✖ Sudo: passwordless (vibe mode)" >&2
            echo "    Fix: re-run installer with --mode vibe (or configure NOPASSWD for $TARGET_USER)" >&2
            ((critical_failed += 1))
        fi
    else
        if _smoke_run_as_target "command -v sudo >/dev/null" &>/dev/null && \
            _smoke_run_as_target "id -nG | grep -qw sudo" &>/dev/null; then
            echo "✅ Sudo: available (safe mode)" >&2
            ((critical_passed += 1))
        else
            echo "✖ Sudo: available (safe mode)" >&2
            echo "    Fix: ensure sudo is installed and $TARGET_USER is in the sudo group" >&2
            ((critical_failed += 1))
        fi
    fi

    # 4) /data/projects exists
    if _smoke_run_as_target "[[ -d /data/projects && -w /data/projects ]]" &>/dev/null; then
        echo "✅ Workspace: /data/projects exists" >&2
        ((critical_passed += 1))
    else
        echo "✖ Workspace: /data/projects exists" >&2
        echo "    Fix: sudo mkdir -p /data/projects && sudo chown -R \"$TARGET_USER:$TARGET_USER\" /data/projects" >&2
        ((critical_failed += 1))
    fi

    # 5) bun, uv, cargo, go available
    local missing_lang=()
    [[ -x "$TARGET_HOME/.bun/bin/bun" ]] || missing_lang+=("bun")
    [[ -x "$TARGET_HOME/.local/bin/uv" || -x "$TARGET_HOME/.cargo/bin/uv" ]] || missing_lang+=("uv")
    [[ -x "$TARGET_HOME/.cargo/bin/cargo" ]] || missing_lang+=("cargo")
    command_exists go || missing_lang+=("go")
    if [[ ${#missing_lang[@]} -eq 0 ]]; then
        echo "✅ Languages: bun, uv, cargo, go available" >&2
        ((critical_passed += 1))
    else
        echo "✖ Languages: missing ${missing_lang[*]}" >&2
        echo "    Fix: curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only-phase 5" >&2
        ((critical_failed += 1))
    fi

    # 6) claude, codex, gemini commands exist
    local missing_agents=()
    [[ -x "$TARGET_HOME/.local/bin/claude" || -x "$TARGET_HOME/.bun/bin/claude" ]] || missing_agents+=("claude")
    [[ -x "$TARGET_HOME/.bun/bin/codex" || -x "$TARGET_HOME/.local/bin/codex" ]] || missing_agents+=("codex")
    [[ -x "$TARGET_HOME/.bun/bin/gemini" || -x "$TARGET_HOME/.local/bin/gemini" ]] || missing_agents+=("gemini")
    if [[ ${#missing_agents[@]} -eq 0 ]]; then
        echo "✅ Agents: claude, codex, gemini" >&2
        ((critical_passed += 1))
    else
        echo "✖ Agents: missing ${missing_agents[*]}" >&2
        echo "    Fix: curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only-phase 6" >&2
        ((critical_failed += 1))
    fi

    # 7) ntm command works
    if _smoke_run_as_target "command -v ntm >/dev/null && ntm --help >/dev/null 2>&1"; then
        echo "✅ NTM: working" >&2
        ((critical_passed += 1))
    else
        echo "✖ NTM: not working" >&2
        echo "    Fix: curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only-phase 8" >&2
        ((critical_failed += 1))
    fi

    # 8) onboard command exists
    if [[ -x "$TARGET_HOME/.local/bin/onboard" ]]; then
        echo "✅ Onboard: installed" >&2
        ((critical_passed += 1))
    else
        echo "✖ Onboard: missing" >&2
        echo "    Fix: curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only-phase 9" >&2
        ((critical_failed += 1))
    fi

    # Non-critical: Agent Mail server can start
    if [[ -x "$TARGET_HOME/mcp_agent_mail/scripts/run_server_with_token.sh" ]]; then
        echo "✅ Agent Mail: installed (run 'am' to start)" >&2
    else
        echo "⚠️ Agent Mail: not installed (re-run: curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only-phase 8)" >&2
        ((warnings += 1))
    fi

    # Non-critical: Stack tools respond to --help
    local stack_help_fail=()
    local stack_tools=(ntm ubs bv cass cm caam slb)
    for tool in "${stack_tools[@]}"; do
        # SLB may have issues with --help exit code, try bare command first
        if [[ "$tool" == "slb" ]]; then
            if ! _smoke_run_as_target "command -v slb >/dev/null && (slb >/dev/null 2>&1 || slb --help >/dev/null 2>&1)"; then
                stack_help_fail+=("$tool")
            fi
        elif ! _smoke_run_as_target "command -v $tool >/dev/null && $tool --help >/dev/null 2>&1"; then
            stack_help_fail+=("$tool")
        fi
    done
    if [[ ${#stack_help_fail[@]} -gt 0 ]]; then
        echo "⚠️ Stack tools: --help failed for ${stack_help_fail[*]}" >&2
        ((warnings += 1))
    fi

    # Non-critical: PostgreSQL service running
    if [[ "$SKIP_POSTGRES" == "true" ]]; then
        echo "⚠️ PostgreSQL: skipped (optional)" >&2
        ((warnings += 1))
    elif command_exists systemctl && [[ -d /run/systemd/system ]] && systemctl is-active --quiet postgresql 2>/dev/null; then
        echo "✅ PostgreSQL: running" >&2
    elif command_exists pg_isready && pg_isready -q 2>/dev/null; then
        echo "✅ PostgreSQL: running" >&2
    else
        echo "⚠️ PostgreSQL: not running (optional)" >&2
        ((warnings += 1))
    fi

    # Non-critical: Vault installed
    if [[ "$SKIP_VAULT" == "true" ]]; then
        echo "⚠️ Vault: skipped (optional)" >&2
        ((warnings += 1))
    elif command_exists vault; then
        echo "✅ Vault: installed" >&2
    else
        echo "⚠️ Vault: not installed (optional)" >&2
        ((warnings += 1))
    fi

    # Non-critical: Cloud CLIs installed
    if [[ "$SKIP_CLOUD" == "true" ]]; then
        echo "⚠️ Cloud CLIs: skipped (optional)" >&2
        ((warnings += 1))
    else
        local missing_cloud=()
        binary_installed "wrangler" || missing_cloud+=("wrangler")
        binary_installed "supabase" || missing_cloud+=("supabase")
        binary_installed "vercel" || missing_cloud+=("vercel")

        if [[ ${#missing_cloud[@]} -eq 0 ]]; then
            echo "✅ Cloud CLIs: wrangler, supabase, vercel" >&2
        else
            echo "⚠️ Cloud CLIs: missing ${missing_cloud[*]} (optional)" >&2
            ((warnings += 1))
        fi
    fi

    echo "" >&2
    if [[ $critical_failed -eq 0 ]]; then
        echo "Smoke test: ${critical_passed}/${critical_total} critical passed, ${warnings} warnings" >&2
        return 0
    fi

    echo "Smoke test: ${critical_passed}/${critical_total} critical passed, ${critical_failed} critical failed, ${warnings} warnings" >&2
    return 1
}

# ============================================================
# Print summary
# ============================================================
print_summary() {
    if [[ "$DRY_RUN" == "true" ]]; then
        {
            if [[ "$HAS_GUM" == "true" ]]; then
                echo ""
                gum style \
                    --border double \
                    --border-foreground "$ACFS_WARNING" \
                    --padding "1 3" \
                    --margin "1 0" \
                    --align left \
                    "$(gum style --foreground "$ACFS_WARNING" --bold '🧪 ACFS Dry Run Complete (no changes made)')

Version: $ACFS_VERSION
Mode:    $MODE

No commands were executed. To actually install, re-run without --dry-run.
Tip: use --print to see upstream install scripts that will be fetched."
            else
                echo ""
                echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${YELLOW}║          🧪 ACFS Dry Run Complete (no changes made)        ║${NC}"
                echo -e "${YELLOW}╠════════════════════════════════════════════════════════════╣${NC}"
                echo ""
                echo -e "Version: ${BLUE}$ACFS_VERSION${NC}"
                echo -e "Mode:    ${BLUE}$MODE${NC}"
                echo ""
                echo -e "${GRAY}No commands were executed. Re-run without --dry-run to install.${NC}"
                echo -e "${GRAY}Tip: use --print to see upstream install scripts.${NC}"
                echo ""
                echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
                echo ""
            fi
        } >&2
        return 0
    fi

    # Build dynamic Tailscale status
    local tailscale_section=""
    if command -v tailscale &>/dev/null; then
        if check_tailscale_auth 2>/dev/null; then
            local ts_ip
            ts_ip=$(tailscale ip -4 2>/dev/null || echo "connected")
            tailscale_section="  ✓ Tailscale: connected ($ts_ip)"
        else
            tailscale_section="  🔐 Tailscale (Secure Remote Access):
     sudo tailscale up
     → Log in with your Google account
     → Then access this VPS from anywhere!"
        fi
    fi

    local summary_content="Version: $ACFS_VERSION
Mode:    $MODE

${tailscale_section:+Service Authentication:

$tailscale_section

}Next steps:

  1. If you logged in as root, reconnect as $TARGET_USER:
     exit
     ssh $TARGET_USER@YOUR_SERVER_IP

  2. Run the onboarding tutorial:
     onboard

  3. Check everything is working:
     acfs doctor

  4. Start your agent cockpit:
     ntm"

    {
        if [[ "$HAS_GUM" == "true" ]]; then
            echo ""
            gum style \
                --border double \
                --border-foreground "$ACFS_SUCCESS" \
                --padding "1 3" \
                --margin "1 0" \
                --align left \
                "$(gum style --foreground "$ACFS_SUCCESS" --bold '🎉 ACFS Installation Complete!')

$summary_content"
        else
            echo ""
            echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║            🎉 ACFS Installation Complete!                   ║${NC}"
            echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
            echo ""
            echo -e "Version: ${BLUE}$ACFS_VERSION${NC}"
            echo -e "Mode:    ${BLUE}$MODE${NC}"
            echo ""
            # Show Tailscale auth section if applicable
            if [[ -n "$tailscale_section" ]]; then
                echo -e "${YELLOW}Service Authentication:${NC}"
                echo ""
                if command -v tailscale &>/dev/null && check_tailscale_auth 2>/dev/null; then
                    local ts_ip_display
                    ts_ip_display=$(tailscale ip -4 2>/dev/null || echo "connected")
                    echo -e "  ${GREEN}✓${NC} Tailscale: connected (${BLUE}$ts_ip_display${NC})"
                else
                    echo -e "  ${YELLOW}🔐${NC} Tailscale (Secure Remote Access):"
                    echo -e "     ${BLUE}sudo tailscale up${NC}"
                    echo -e "     ${GRAY}→ Log in with your Google account${NC}"
                    echo -e "     ${GRAY}→ Then access this VPS from anywhere!${NC}"
                fi
                echo ""
            fi
            # Show SSH key warning if password-only connection was detected
            if [[ "${ACFS_SSH_KEY_WARNING:-false}" == "true" ]]; then
                echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
                echo -e "${RED}  ⚠  SSH KEY SETUP REQUIRED FOR TARGET USER${NC}"
                echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
                echo ""
                echo -e "  You connected with a password, so no SSH key was copied"
                echo -e "  to the $TARGET_USER user. You won't be able to SSH as $TARGET_USER"
                echo -e "  until you set up SSH key access."
                echo ""
                echo -e "  ${YELLOW}FROM YOUR LOCAL MACHINE, run:${NC}"
                echo ""
                echo -e "    ${BLUE}ssh-copy-id ${TARGET_USER}@YOUR_SERVER_IP${NC}"
                echo ""
                echo -e "  Or see the instructions printed earlier for manual setup."
                echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
                echo ""
            fi
            echo -e "${YELLOW}Next steps:${NC}"
            echo ""
            if [[ "${ACFS_SSH_KEY_WARNING:-false}" == "true" ]]; then
                echo "  1. Set up SSH key for $TARGET_USER user (see warning above)"
                echo ""
                echo "  2. Then reconnect as $TARGET_USER:"
            else
                echo "  1. If you logged in as root, reconnect as $TARGET_USER:"
            fi
            echo -e "     ${GRAY}exit${NC}"
            echo -e "     ${GRAY}ssh ${TARGET_USER}@YOUR_SERVER_IP${NC}"
            echo ""
            local step_num=2
            if [[ "${ACFS_SSH_KEY_WARNING:-false}" == "true" ]]; then
                step_num=3
            fi
            echo "  $step_num. Run the onboarding tutorial:"
            echo -e "     ${BLUE}onboard${NC}"
            echo ""
            ((step_num++))
            echo "  $step_num. Check everything is working:"
            echo -e "     ${BLUE}acfs doctor${NC}"
            echo ""
            ((step_num++))
            echo "  $step_num. Start your agent cockpit:"
            echo -e "     ${BLUE}ntm${NC}"
            echo ""
            echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
            echo ""
        fi
    } >&2
}

# ============================================================
# Main
# ============================================================
main() {
    parse_args "$@"

    # --yes should always behave non-interactively (skip prompts), regardless of flag order.
    if [[ "$YES_MODE" == "true" ]]; then
        export ACFS_INTERACTIVE=false
    fi

    # Handle --pin-ref early (before any heavy setup) - just resolve SHA and exit
    if [[ "$PIN_REF_MODE" == "true" ]]; then
        fetch_commit_sha
        print_pinned_ref
        exit 0
    fi

    if [[ -z "${SCRIPT_DIR:-}" ]]; then
        # Resolve ACFS_REF to a specific commit SHA early to prevent mixed-ref installs.
        # Without this, we could download a tarball for one commit and later fetch commit metadata
        # (or resume scripts) from a newer commit if the branch/tag moves mid-install.
        fetch_commit_sha
        if [[ -n "${ACFS_COMMIT_SHA_FULL:-}" ]]; then
            ACFS_REF="$ACFS_COMMIT_SHA_FULL"
            ACFS_RAW="https://raw.githubusercontent.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/${ACFS_REF}"
            export ACFS_REF ACFS_RAW
        fi
        bootstrap_repo_archive
    fi

    # Detect environment and source manifest index (mjt.5.3)
    # This must happen BEFORE any handlers that need module data
    detect_environment

    # Source generated installers for manifest-driven execution (mjt.5.6)
    # Skip when we're only listing/printing plan or running dry-run/print-only modes.
    if [[ "$LIST_MODULES" != "true" ]] && [[ "$PRINT_PLAN_MODE" != "true" ]] && [[ "$DRY_RUN" != "true" ]] && [[ "$PRINT_MODE" != "true" ]]; then
        source_generated_installers
    fi

    # Map legacy --skip-* flags to SKIP_MODULES (mjt.5.5)
    # This allows --skip-postgres, --skip-vault, --skip-cloud to work
    # through the manifest-driven selection engine
    acfs_apply_legacy_skips

    # Resolve module selection (mjt.5.4)
    # Computes ACFS_EFFECTIVE_PLAN and ACFS_EFFECTIVE_RUN based on:
    # - CLI flags (--only, --skip, --no-deps, --only-phase)
    # - Legacy flags mapped above
    # - Manifest defaults and dependency graph
    if ! acfs_resolve_selection; then
        exit 1
    fi

    # Handle --list-modules: print available modules and exit (mjt.5.3)
    if [[ "$LIST_MODULES" == "true" ]]; then
        list_modules
        exit 0
    fi

    # Handle --print-plan: print execution plan and exit (mjt.5.3/5.4)
    if [[ "$PRINT_PLAN_MODE" == "true" ]]; then
        print_execution_plan
        exit 0
    fi

    # Handle --reset-state: move state file aside and exit
    if [[ "$RESET_STATE_ONLY" == "true" ]]; then
        echo "Resetting ACFS state..." >&2
        local state_file=""
        if [[ -n "${ACFS_HOME:-}" ]]; then
            state_file="${ACFS_HOME}/state.json"
        else
            local base_home=""
            if [[ -n "${TARGET_HOME:-}" ]]; then
                base_home="$TARGET_HOME"
            elif [[ "${TARGET_USER:-}" == "root" ]]; then
                base_home="/root"
            else
                base_home="/home/${TARGET_USER}"
            fi

            if [[ -z "$base_home" ]] || [[ "$base_home" == "/" ]]; then
                echo "ERROR: Invalid TARGET_HOME: '${base_home:-<empty>}'" >&2
                exit 1
            fi
            if [[ "$base_home" != /* ]]; then
                echo "ERROR: TARGET_HOME must be an absolute path (got: $base_home)" >&2
                exit 1
            fi

            state_file="${base_home}/.acfs/state.json"
        fi
        if [[ -f "$state_file" ]]; then
            if type -t state_backup_and_remove &>/dev/null; then
                local state_dir
                state_dir="$(dirname "$state_file")"
                if ! ACFS_HOME="$state_dir" ACFS_STATE_FILE="$state_file" state_backup_and_remove; then
                    echo "ERROR: Failed to move state file out of the way: $state_file" >&2
                    exit 1
                fi
            else
                local backup_file
                backup_file="${state_file}.backup.$(date +%Y%m%d_%H%M%S)"
                if mv "$state_file" "$backup_file" 2>/dev/null; then
                    echo "Moved state file aside: $backup_file" >&2
                else
                    echo "ERROR: Failed to move state file out of the way: $state_file" >&2
                    exit 1
                fi
            fi
        else
            echo "No state file found at: $state_file" >&2
        fi
        exit 0
    fi

    # Install gum FIRST so the entire script looks amazing
    install_gum_early

    # Fetch commit SHA for version display
    fetch_commit_sha

    # Print beautiful ASCII banner (now with gum if available!)
    print_banner

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run mode - no changes will be made"
        echo ""
    fi

    # Run auto-fix checks before preflight (bd-19y9.3.4)
    if [[ "$SKIP_PREFLIGHT" != "true" ]]; then
        run_autofix_checks
    fi

    # Run pre-flight validation (Phase 0)
    if [[ "$SKIP_PREFLIGHT" != "true" ]]; then
        run_preflight_checks
    fi

    # Dry-run mode should be truly non-destructive. Print the plan/summary and exit
    # before any system-modifying steps (apt/user/upgrade) can run.
    if [[ "$DRY_RUN" == "true" ]]; then
        print_execution_plan || true
        print_summary
        exit 0
    fi

    if [[ "$PRINT_MODE" == "true" ]]; then
        echo "The following tools will be installed from upstream:"
        echo ""
        echo "  - Oh My Zsh: https://ohmyz.sh"
        echo "  - Powerlevel10k: https://github.com/romkatv/powerlevel10k"
        echo "  - Bun: https://bun.sh"
        echo "  - Rust: https://rustup.rs"
        echo "  - uv: https://astral.sh/uv"
        echo "  - Claude Code (native): https://claude.ai/install.sh"
        echo "  - NTM: https://github.com/Dicklesworthstone/ntm"
        echo "  - MCP Agent Mail: https://github.com/Dicklesworthstone/mcp_agent_mail"
        echo "  - UBS: https://github.com/Dicklesworthstone/ultimate_bug_scanner"
        echo "  - Beads Viewer: https://github.com/Dicklesworthstone/beads_viewer"
        echo "  - CASS: https://github.com/Dicklesworthstone/coding_agent_session_search"
        echo "  - CM: https://github.com/Dicklesworthstone/cass_memory_system"
        echo "  - CAAM: https://github.com/Dicklesworthstone/coding_agent_account_manager"
        echo "  - SLB: https://github.com/Dicklesworthstone/simultaneous_launch_button"
        echo ""
        exit 0
    fi

    ensure_root
    disable_needrestart_apt_hook  # Prevent apt hangs on Ubuntu 22.04+ (issue #70)
    validate_target_user
    init_target_paths
    acfs_log_init   # Start capturing stderr to log file (uses ACFS_HOME/logs)
    ensure_ubuntu

    # Ensure base dependencies (like jq) are installed before upgrade logic
    # This is safe to run on old Ubuntu versions and ensures jq is available
    # for state management during the upgrade process.
    ensure_base_deps

    # ============================================================
    # Ubuntu Auto-Upgrade Phase (nb4)
    # ============================================================
    # Run as "Phase -1" before all other phases.
    # This may trigger a reboot and exit. After final reboot,
    # the resume service will call install.sh again to continue.
    run_ubuntu_upgrade_phase "$@"

    # ============================================================
    # State Management and Resume Logic (mjt.5.8)
    # ============================================================
    # Initialize state file location (uses TARGET_USER's home)
    ACFS_HOME="${ACFS_HOME:-/home/${TARGET_USER}/.acfs}"
    ACFS_STATE_FILE="$ACFS_HOME/state.json"
    export ACFS_HOME ACFS_STATE_FILE

    # Validate and handle existing state file
    if type -t state_ensure_valid &>/dev/null; then
        if ! state_ensure_valid; then
            log_error "State validation failed. Aborting."
            exit 1
        fi
    fi

    # Check for resume scenario (if state functions available)
    if type -t confirm_resume &>/dev/null; then
        # Use || to capture non-zero exit codes without triggering set -e
        # confirm_resume returns: 0=resume, 1=fresh install, 2=abort
        local resume_result=0
        confirm_resume || resume_result=$?
        case $resume_result in
            0) # Resume - state functions will skip completed phases
                log_info "Resuming installation from last checkpoint..."
                ;;
            1) # Fresh install - confirm before proceeding, then initialize state
                confirm_or_exit
                if type -t state_init &>/dev/null; then
                    state_init
                fi
                ;;
            2) # Abort
                log_info "Installation aborted by user."
                exit 0
                ;;
        esac
    else
        # Fallback: use original confirm_or_exit
        confirm_or_exit
    fi

    if [[ "$DRY_RUN" != "true" ]]; then
        # Execute phases with state tracking (mjt.5.8)
        # Each run_phase call checks if phase is already completed and skips if so

        # Track installation timing for report_success
        local installation_start_time
        installation_start_time=$(date +%s)

        # Helper: Run phase with structured error reporting (mjt.5.8)
        _run_phase_with_report() {
            local phase_id="$1"
            local phase_display="$2"
            local phase_func="$3"
            local phase_num="${phase_display%%/*}"
            # Extract name after the leading "X/Y " prefix (robust to multi-digit totals).
            local phase_name="${phase_display#* }"

            # Show progress header before running phase
            if type -t show_progress_header &>/dev/null; then
                show_progress_header "$phase_num" 9 "$phase_name" "$installation_start_time"
            fi

            if type -t run_phase &>/dev/null; then
                if ! run_phase "$phase_id" "$phase_display" "$phase_func"; then
                    # Use structured error reporting
                    if type -t report_failure &>/dev/null; then
                        report_failure "$phase_num" 9
                    else
                        log_error "Phase $phase_display failed"
                    fi
                    # Print precise resume hint (bd-31ps.9.1)
                    print_resume_hint "$phase_id" ""
                    exit 1
                fi
            else
                # Fallback: direct call with basic error handling
                if ! "$phase_func"; then
                    log_error "Phase $phase_display failed"
                    print_resume_hint "$phase_id" ""
                    exit 1
                fi
            fi
        }

        _run_phase_with_report "user_setup" "1/9 User Setup" normalize_user
        _run_phase_with_report "filesystem" "2/9 Filesystem" setup_filesystem
        _run_phase_with_report "shell_setup" "3/9 Shell Setup" setup_shell
        _run_phase_with_report "cli_tools" "4/9 CLI Tools" install_cli_tools
        _run_phase_with_report "languages" "5/9 Languages" install_languages
        _run_phase_with_report "agents" "6/9 Coding Agents" install_agents_phase
        _run_phase_with_report "cloud_db" "7/9 Cloud & DB" install_cloud_db
        _run_phase_with_report "stack" "8/9 Stack" install_stack_phase
        _run_phase_with_report "finalize" "9/9 Finalize" finalize

        # Always update checksums.yaml and VERSION after all phases complete
        # This ensures resume installs get fresh metadata even if finalize was previously completed
        # Related: PR #44 - fix checksums.yaml becoming stale on resume installs
        if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -d "$ACFS_BOOTSTRAP_DIR" ]]; then
            if [[ -f "$ACFS_BOOTSTRAP_DIR/checksums.yaml" ]]; then
                if [[ -n "${ACFS_CHECKSUMS_REF:-}" && -n "${ACFS_REF_INPUT:-}" && "$ACFS_CHECKSUMS_REF" != "$ACFS_REF_INPUT" ]]; then
                    log_detail "Refreshing checksums.yaml from ref '${ACFS_CHECKSUMS_REF}'"
                    install_checksums_yaml "$ACFS_HOME/checksums.yaml" || true
                    $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/checksums.yaml" 2>/dev/null || true
                else
                    log_detail "Ensuring checksums.yaml is up to date"
                    $SUDO cp -f "$ACFS_BOOTSTRAP_DIR/checksums.yaml" "$ACFS_HOME/checksums.yaml" 2>/dev/null || true
                    $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/checksums.yaml" 2>/dev/null || true
                fi
            fi
            if [[ -f "$ACFS_BOOTSTRAP_DIR/VERSION" ]]; then
                log_detail "Ensuring VERSION is up to date"
                $SUDO cp -f "$ACFS_BOOTSTRAP_DIR/VERSION" "$ACFS_HOME/VERSION" 2>/dev/null || true
                $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/VERSION" 2>/dev/null || true
            fi
        fi

        # Calculate installation time for success report
        local installation_end_time total_seconds
        installation_end_time=$(date +%s)
        total_seconds=$((installation_end_time - installation_start_time))

        # Show completion message with progress display
        if type -t show_completion &>/dev/null; then
            show_completion 9 "$total_seconds"
        fi

        # Report success with timing (mjt.5.8)
        if type -t report_success &>/dev/null; then
            report_success 9 "$total_seconds"
        fi

        # Emit install summary JSON (bd-31ps.3.2)
        acfs_summary_emit "success" "$total_seconds" 2>/dev/null || true

        SMOKE_TEST_FAILED=false
        if ! run_smoke_test; then
            SMOKE_TEST_FAILED=true
        fi
    fi

    print_summary

    if [[ "${SMOKE_TEST_FAILED:-false}" == "true" ]]; then
        exit 1
    fi
}

main "$@"
