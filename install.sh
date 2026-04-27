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
#   --ref <ref>          Git ref to install (branch, tag, or SHA). Equivalent to
#                        ACFS_REF env var but works reliably in curl|bash pipelines.
#   --pin-ref            Print resolved SHA and pinned command, then exit
# ============================================================

set -euo pipefail

# Enable shell tracing when ACFS_DEBUG=true (matches the hint in our error messages)
[[ "${ACFS_DEBUG:-}" == "true" ]] && set -x

# Prevent apt/dpkg from displaying interactive dialogs (kernel upgrade prompts,
# debconf questions, etc.) that corrupt the terminal with ncurses escape sequences
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a    # Automatically restart services without asking
export NEEDRESTART_SUSPEND=1 # Suppress needrestart prompts during installation
export DEBCONF_NONINTERACTIVE_SEEN=true

# ============================================================
# Configuration
# ============================================================
ACFS_VERSION="0.7.0"
# Allow fork installations by overriding these via environment variables
ACFS_REPO_OWNER="${ACFS_REPO_OWNER:-Dicklesworthstone}"
ACFS_REPO_NAME="${ACFS_REPO_NAME:-agentic_coding_flywheel_setup}"
ACFS_REF="${ACFS_REF:-main}"
# Preserve the original ref (branch/tag/sha) before resolving to a commit SHA.
ACFS_REF_INPUT="$ACFS_REF"
# Checksums ref defaults to ACFS_REF_INPUT, but pinned tags/SHAs fall back to main
# to avoid stale checksums for fast-moving upstream installers.
_ACFS_CHECKSUMS_REF_FROM_ENV="${ACFS_CHECKSUMS_REF:-}"
ACFS_CHECKSUMS_REF_EXPLICIT=false
ACFS_CHECKSUMS_REF="$_ACFS_CHECKSUMS_REF_FROM_ENV"
if [[ -z "$ACFS_CHECKSUMS_REF" ]]; then
    if [[ "$ACFS_REF_INPUT" =~ ^v[0-9]+(\.[0-9]+){1,2}([.-][A-Za-z0-9]+)*$ ]] || [[ "$ACFS_REF_INPUT" =~ ^[0-9a-f]{7,40}$ ]]; then
        ACFS_CHECKSUMS_REF="main"
    else
        ACFS_CHECKSUMS_REF="$ACFS_REF_INPUT"
    fi
else
    ACFS_CHECKSUMS_REF_EXPLICIT=true
fi
unset _ACFS_CHECKSUMS_REF_FROM_ENV
ACFS_RAW="https://raw.githubusercontent.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/${ACFS_REF}"
ACFS_CHECKSUMS_RAW="https://raw.githubusercontent.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/${ACFS_CHECKSUMS_REF}"
export ACFS_RAW ACFS_CHECKSUMS_REF ACFS_CHECKSUMS_RAW ACFS_CHECKSUMS_REF_EXPLICIT ACFS_VERSION
export CHECKSUMS_FILE="${ACFS_CHECKSUMS_YAML:-${CHECKSUMS_FILE:-}}"
ACFS_COMMIT_SHA=""       # Short SHA for display (12 chars)
ACFS_COMMIT_SHA_FULL=""  # Full SHA for pinning resume scripts (40 chars)

# Early curl defaults: enforce HTTPS (including redirects) when supported.
# This is used before security.sh is available (bootstrap / early library sourcing).
ACFS_EARLY_CURL_ARGS=(--connect-timeout 30 --max-time 300 -fsSL)
# Note: ACFS_HOME is set after TARGET_HOME is determined
ACFS_LOG_DIR="/var/log/acfs"
_ACFS_BOOTSTRAP_DIR_OWNED=false
_ACFS_BOOTSTRAP_DIR_CREATED=""
_ACFS_BOOTSTRAP_DIR_TMP_ROOT=""
# SCRIPT_DIR is empty when running via curl|bash (stdin; no file on disk)
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Early PATH setup: ensure ~/.local/bin is available for native installers
# when HOME is present, without assuming stripped environments already set it.
_ACFS_EARLY_PATH="${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
if [[ -n "${HOME:-}" ]]; then
    export PATH="$HOME/.local/bin:$_ACFS_EARLY_PATH"
else
    export PATH="$_ACFS_EARLY_PATH"
fi
unset _ACFS_EARLY_PATH

acfs_early_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        *[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    for candidate in \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        echo "$candidate"
        return 0
    done

    return 1
}

acfs_early_sudo_binary_path() {
    if [[ -n "${SUDO:-}" && "$SUDO" == /* && -x "$SUDO" ]]; then
        printf '%s\n' "$SUDO"
        return 0
    fi

    acfs_early_system_binary_path sudo
}

_acfs_early_curl_bin="$(acfs_early_system_binary_path curl 2>/dev/null || true)"
_acfs_early_grep_bin="$(acfs_early_system_binary_path grep 2>/dev/null || true)"
if [[ -n "$_acfs_early_curl_bin" && -n "$_acfs_early_grep_bin" ]] && "$_acfs_early_curl_bin" --help all 2>/dev/null | "$_acfs_early_grep_bin" -q -- '--proto'; then
    ACFS_EARLY_CURL_ARGS=(--proto '=https' --proto-redir '=https' --connect-timeout 30 --max-time 300 -fsSL)
fi
unset _acfs_early_curl_bin _acfs_early_grep_bin

acfs_early_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(acfs_early_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(acfs_early_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    echo "$current_user"
}

acfs_early_getent_passwd_entry() {
    local user="${1:-}"
    local getent_bin=""
    local passwd_line=""
    local passwd_user=""

    getent_bin="$(acfs_early_system_binary_path getent 2>/dev/null || true)"
    if [[ -n "$getent_bin" ]]; then
        if [[ -n "$user" ]]; then
            "$getent_bin" passwd "$user" 2>/dev/null
        else
            "$getent_bin" passwd 2>/dev/null
        fi
        return $?
    fi

    [[ -r /etc/passwd ]] || return 1

    if [[ -n "$user" ]]; then
        while IFS= read -r passwd_line; do
            IFS=: read -r passwd_user _ <<< "$passwd_line"
            if [[ "$passwd_user" == "$user" ]]; then
                echo "$passwd_line"
                return 0
            fi
        done < /etc/passwd
        return 1
    fi

    while IFS= read -r passwd_line; do
        echo "$passwd_line"
    done < /etc/passwd
}
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
TARGET_UBUNTU_VERSION_EXPLICIT=false  # true when user passes --target-ubuntu

# Target user configuration
# Default: detect the current user (or SUDO_USER if running under sudo).
# Override with env var: TARGET_USER=myuser
# Note: Previously defaulted to "ubuntu" which broke non-ubuntu VPS installs.
if [[ -z "${TARGET_USER:-}" ]]; then
    if [[ $EUID -eq 0 ]] && [[ -z "${SUDO_USER:-}" ]]; then
        _ACFS_DETECTED_USER="ubuntu"
    else
        _ACFS_DETECTED_USER="${SUDO_USER:-}"
        if [[ -z "$_ACFS_DETECTED_USER" ]]; then
            _ACFS_DETECTED_USER="$(acfs_early_resolve_current_user 2>/dev/null || true)"
        fi
        if [[ -z "$_ACFS_DETECTED_USER" ]]; then
            printf 'ERROR: Unable to resolve the current user for TARGET_USER\n' >&2
            exit 1
        fi
    fi
    TARGET_USER="$_ACFS_DETECTED_USER"
fi
unset _ACFS_DETECTED_USER
# Export TARGET_USER early so subprocesses (e.g. preflight.sh) can use it
# to determine the correct installation partition for disk-space checks (#243).
export TARGET_USER
# Leave TARGET_HOME unset by default; init_target_paths derives it from the
# real passwd entry when possible and otherwise fails closed.
TARGET_HOME="${TARGET_HOME:-}"
export TARGET_HOME

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Check if gum is available for enhanced UI
HAS_GUM=false
if acfs_early_system_binary_path gum &>/dev/null; then
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
type -t try_step_eval &>/dev/null || try_step_eval() {
    local bash_bin=""
    bash_bin="$(acfs_early_system_binary_path bash 2>/dev/null || true)"
    [[ -n "$bash_bin" ]] || return 127
    shift
    "$bash_bin" -e -o pipefail -c "$1"
}

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
    local curl_bin=""
    curl_bin="$(acfs_early_system_binary_path curl 2>/dev/null || true)"
    if [[ -n "$curl_bin" ]]; then
        local tmp_upgrade=""
        local mktemp_bin=""
        mktemp_bin="$(acfs_early_system_binary_path mktemp 2>/dev/null || true)"
        if [[ -n "$mktemp_bin" ]]; then
            tmp_upgrade="$("$mktemp_bin" "${TMPDIR:-/tmp}/acfs-ubuntu-upgrade.XXXXXX" 2>/dev/null)" || tmp_upgrade=""
        fi
        if [[ -n "$tmp_upgrade" ]]; then
            if "$curl_bin" "${ACFS_EARLY_CURL_ARGS[@]}" "$ACFS_RAW/scripts/lib/ubuntu_upgrade.sh" -o "$tmp_upgrade" 2>/dev/null; then
                source "$tmp_upgrade"
                rm -f "$tmp_upgrade"
                export ACFS_UBUNTU_UPGRADE_LOADED=1
                return 0
            fi
            rm -f "$tmp_upgrade"
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
    local curl_bin=""
    curl_bin="$(acfs_early_system_binary_path curl 2>/dev/null || true)"
    if [[ -z "$curl_bin" ]]; then
        ACFS_COMMIT_SHA="(curl not available)"
        return 0
    fi

    # Fetch from GitHub API - get the commit SHA for the ref
    local api_url="https://api.github.com/repos/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/commits/${ACFS_REF}"
    local response

    if response=$("$curl_bin" -sf --max-time 5 "$api_url" 2>/dev/null); then
        # Try to use python3 for robust JSON parsing if available
        local sha=""
        local commit_date=""

        local python3_bin=""
        python3_bin="$(acfs_early_system_binary_path python3 2>/dev/null || true)"
        if [[ -n "$python3_bin" ]]; then
            # Python parsing - robust against JSON formatting changes
            sha=$(echo "$response" | "$python3_bin" -c "import sys, json; print(json.load(sys.stdin).get('sha', ''))" 2>/dev/null)
            commit_date=$(echo "$response" | "$python3_bin" -c "import sys, json; print(json.load(sys.stdin).get('commit', {}).get('author', {}).get('date', ''))" 2>/dev/null)
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
    if acfs_early_system_binary_path gum &>/dev/null; then
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

    local curl_bin=""
    local gpg_bin=""
    local apt_get_bin=""
    local timeout_bin=""
    local mkdir_bin=""
    local tee_bin=""

    # Need curl to fetch gum - if curl isn't installed yet, skip early install
    # (gum will be installed later in install_cli_tools after ensure_base_deps)
    curl_bin="$(acfs_early_system_binary_path curl 2>/dev/null || true)"
    if [[ -z "$curl_bin" ]]; then
        return 0
    fi

    # Need gpg for apt key handling
    gpg_bin="$(acfs_early_system_binary_path gpg 2>/dev/null || true)"
    if [[ -z "$gpg_bin" ]]; then
        return 0
    fi

    # Need apt-get for installation
    apt_get_bin="$(acfs_early_system_binary_path apt-get 2>/dev/null || true)"
    if [[ -z "$apt_get_bin" ]]; then
        return 0
    fi
    timeout_bin="$(acfs_early_system_binary_path timeout 2>/dev/null || true)"
    if [[ -z "$timeout_bin" ]]; then
        return 0
    fi
    mkdir_bin="$(acfs_early_system_binary_path mkdir 2>/dev/null || true)"
    tee_bin="$(acfs_early_system_binary_path tee 2>/dev/null || true)"
    if [[ -z "$mkdir_bin" || -z "$tee_bin" ]]; then
        return 0
    fi

    # Need root/sudo for apt operations
    local -a sudo_cmd=()
    local sudo_bin=""
    if [[ $EUID -ne 0 ]]; then
        sudo_bin="$(acfs_early_sudo_binary_path 2>/dev/null || true)"
        if [[ -n "$sudo_bin" ]]; then
            sudo_cmd=("$sudo_bin")
        else
            # Can't install gum without sudo, fall back to plain output
            return 0
        fi
    fi

    echo -e "\033[0;90m    → Installing gum for enhanced UI...\033[0m" >&2

    # Step 1: Fetch Charm GPG key (with timeout)
    echo -e "\033[0;90m      ↳ Fetching Charm repository key...\033[0m" >&2
    "${sudo_cmd[@]}" "$mkdir_bin" -p /etc/apt/keyrings 2>/dev/null || true
    if ! "$curl_bin" --connect-timeout 10 --max-time 30 -fsSL https://repo.charm.sh/apt/gpg.key 2>/dev/null | \
        "${sudo_cmd[@]}" "$gpg_bin" --batch --yes --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null; then
        echo -e "\033[0;33m      ⚠ Could not fetch Charm key (skipping gum, will retry later)\033[0m" >&2
        return 0
    fi

    # Step 2: Add apt repository (using DEB822 format to avoid .migrate warnings on upgrade)
    "${sudo_cmd[@]}" "$tee_bin" /etc/apt/sources.list.d/charm.sources > /dev/null 2>&1 << 'EOF'
Types: deb
URIs: https://repo.charm.sh/apt/
Suites: *
Components: *
Signed-By: /etc/apt/keyrings/charm.gpg
EOF

    # Step 3: Update apt (this can be slow on fresh systems)
    # Disable fancy progress to prevent terminal cursor issues
    echo -e "\033[0;90m      ↳ Updating package lists (may take 30-60s on fresh systems)...\033[0m" >&2
    if ! DEBIAN_FRONTEND=noninteractive "$timeout_bin" 120 "${sudo_cmd[@]}" "$apt_get_bin" update -y \
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
    if apt_output=$(DEBIAN_FRONTEND=noninteractive "$timeout_bin" 60 "${sudo_cmd[@]}" "$apt_get_bin" install -y \
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
    echo "  curl -fsSL \"${install_url}\" | bash -s -- --yes --mode vibe --ref \"${sha}\""
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
        printf 'Bash: %s\n' "${BASH_VERSION:-unknown}"
        printf '========================\n\n'
    } > "$ACFS_LOG_FILE" 2>/dev/null || return 1

    # Fix ownership so target user can read logs
    if [[ -n "${TARGET_USER:-}" ]] && [[ "$(id -u)" -eq 0 ]]; then
        chown "${TARGET_USER}:${TARGET_USER}" "$log_dir" "$ACFS_LOG_FILE" 2>/dev/null || true
    fi

    # Tee stderr: all stderr output goes to both terminal and log file.
    # fd 3 = original stderr (preserved for terminal output).
    #
    # NOTE: Process substitution >(tee ...) can fail on some systems
    # (especially Ubuntu 25.04 with bash 5.3+). We use a subshell guard
    # to prevent set -e from exiting the entire script on failure.
    # If tee logging fails, we fall back to simple file redirection.
    local tee_logging_ok=false
    if command -v tee >/dev/null 2>&1; then
        # Test if process substitution works before committing to it.
        # On bash 5.3+, bare `exec` under set -e can exit the script
        # before `if` catches the failure, so we test in a subshell.
        # shellcheck disable=SC2261
        if (exec 3>&1; echo test > >(cat >/dev/null)) 2>/dev/null; then
            # Process substitution works - set up tee logging
            # Save original stderr first
            exec 3>&2 || true
            # Now redirect stderr to tee (which sends to both log and original stderr)
            # shellcheck disable=SC2261
            # Use subshell test first to prevent exec from exiting under bash 5.3+
            if (set +e; exec 2> >(tee -a "$ACFS_LOG_FILE" >&3)) 2>/dev/null; then
                exec 2> >(tee -a "$ACFS_LOG_FILE" >&3) && tee_logging_ok=true
            fi
        fi
    fi

    if [[ "$tee_logging_ok" != "true" ]]; then
        # Fallback: redirect stderr to both terminal (via original fd) and log file
        # This is less elegant but works on all bash versions
        echo "Note: Tee logging unavailable on this system, using fallback" >&2 || true
        # Save original stderr, then append to log file for each command
        # We'll rely on explicit logging calls instead of automatic tee
        ACFS_LOG_FALLBACK=true
        export ACFS_LOG_FALLBACK
    fi

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

    local resolved_target_home=""
    local explicit_target_home=""
    if [[ -n "${TARGET_HOME:-}" ]] && [[ "${TARGET_HOME}" == /* ]] && [[ "${TARGET_HOME}" != "/" ]]; then
        explicit_target_home="${TARGET_HOME%/}"
    fi
    resolved_target_home="$(acfs_home_for_user "${TARGET_USER:-ubuntu}" "$explicit_target_home" 2>/dev/null || true)"
    resolved_target_home="${resolved_target_home%/}"
    if [[ -z "$resolved_target_home" ]] || [[ "$resolved_target_home" == "/" ]] || [[ "$resolved_target_home" != /* ]]; then
        return 1
    fi

    local summary_home="${ACFS_HOME:-}"
    if [[ -z "$summary_home" ]]; then
        summary_home="${resolved_target_home}/.acfs"
    fi

    local summary_dir="${summary_home}/logs"
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
        --arg target_home "${resolved_target_home:-unknown}" \
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
    local install_url=""
    local install_url_q=""
    local arg_q=""
    local resume_ref=""
    local resume_ref_pinned_from_commit=false
    local -a resume_args=(--resume)

    # Prefer curl|bash one-liner for curl invocations; local script for local runs
    if [[ -z "${SCRIPT_DIR:-}" ]]; then
        # curl|bash invocation - use one-liner format
        cmd="curl -sSL"
        if [[ -n "${ACFS_COMMIT_SHA_FULL:-}" ]]; then
            # Pin to exact commit SHA for reproducibility
            install_url="https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${ACFS_COMMIT_SHA_FULL}/install.sh"
        elif [[ -n "${ACFS_REF_INPUT:-}" && "${ACFS_REF_INPUT}" != "main" ]]; then
            install_url="https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${ACFS_REF_INPUT}/install.sh"
        else
            install_url="https://acfs.sh"
        fi
        printf -v install_url_q '%q' "$install_url"
        cmd="$cmd $install_url_q"
        cmd="$cmd | bash -s --"
    else
        # Local script invocation
        local local_install
        local_install="${SCRIPT_DIR%/}/install.sh"
        printf -v local_install '%q' "$local_install"
        cmd="bash $local_install"
    fi

    # Always add --resume flag (skips completed phases via state.json)

    # Add mode if not default
    if [[ "${MODE:-vibe}" != "vibe" ]]; then
        resume_args+=(--mode "$MODE")
    fi

    # Propagate --ref so the resume uses the same git ref (avoids the
    # curl|bash env-var pitfall where ACFS_REF only reaches curl, not bash)
    if [[ -z "${SCRIPT_DIR:-}" && -n "${ACFS_COMMIT_SHA_FULL:-}" ]]; then
        resume_ref="$ACFS_COMMIT_SHA_FULL"
        resume_ref_pinned_from_commit=true
    elif [[ -n "${ACFS_REF_INPUT:-}" && "${ACFS_REF_INPUT}" != "main" ]]; then
        resume_ref="$ACFS_REF_INPUT"
    fi
    if [[ -n "$resume_ref" ]]; then
        resume_args+=(--ref "$resume_ref")
    fi

    # Preserve checksum metadata that would otherwise be lost when replaying
    # the resume command with a different --ref than the original invocation.
    if [[ "${ACFS_CHECKSUMS_REF_EXPLICIT:-false}" == "true" && -n "${ACFS_CHECKSUMS_REF:-}" ]]; then
        resume_args+=(--checksums-ref "$ACFS_CHECKSUMS_REF")
    elif [[ "$resume_ref_pinned_from_commit" == "true" && -n "${ACFS_CHECKSUMS_REF:-}" && "$ACFS_CHECKSUMS_REF" != "main" ]]; then
        # Pinning --ref to an exact SHA would otherwise make parse_args derive
        # checksum metadata from main, not the symbolic branch used originally.
        resume_args+=(--checksums-ref "$ACFS_CHECKSUMS_REF")
    fi

    # Add skip flags that were used
    [[ "${SKIP_POSTGRES:-false}" == "true" ]] && resume_args+=(--skip-postgres)
    [[ "${SKIP_VAULT:-false}" == "true" ]] && resume_args+=(--skip-vault)
    [[ "${SKIP_CLOUD:-false}" == "true" ]] && resume_args+=(--skip-cloud)
    [[ "${SKIP_PREFLIGHT:-false}" == "true" ]] && resume_args+=(--skip-preflight)
    [[ "${SKIP_UBUNTU_UPGRADE:-false}" == "true" ]] && resume_args+=(--skip-ubuntu-upgrade)

    # Add --yes if original run was non-interactive
    [[ "${YES_MODE:-false}" == "true" ]] && resume_args+=(--yes)

    # Add --strict if it was set
    [[ "${STRICT_MODE:-false}" == "true" ]] && resume_args+=(--strict)

    for arg_q in "${resume_args[@]}"; do
        printf -v arg_q '%q' "$arg_q"
        cmd="$cmd $arg_q"
    done

    echo "$cmd"
}

# Print the resume hint with explanation and copyable block
print_resume_hint() {
    local failed_phase="${1:-}"
    local failed_step="${2:-}"
    local resume_cmd=""
    if ! resume_cmd=$(generate_resume_hint "${failed_phase:-}" "${failed_step:-}" 2>/dev/null); then
        if [[ -n "${SCRIPT_DIR:-}" ]]; then
            local local_install
            local_install="${SCRIPT_DIR%/}/install.sh"
            printf -v local_install '%q' "$local_install"
            resume_cmd="bash $local_install --resume --yes"
        else
            resume_cmd="curl -sSL https://acfs.sh | bash -s -- --resume --yes"
        fi
    fi

    log_info ""
    log_info "╔══════════════════════════════════════════════════════════════╗"
    log_info "║  To resume installation from this point:                     ║"
    log_info "╚══════════════════════════════════════════════════════════════╝"
    log_info ""
    log_info "  $resume_cmd"
    log_info ""

    if [[ -n "${failed_phase:-}" ]]; then
        log_detail "Failed phase: ${failed_phase:-}"
    fi
    if [[ -n "${failed_step:-}" ]]; then
        log_detail "Failed step: ${failed_step:-}"
    fi

    # Also persist the precise resume hint into state.json, but only through the
    # state library so we keep same-directory atomic writes and target-user ownership.
    if [[ -f "${ACFS_STATE_FILE:-}" ]] && type -t state_set_resume_hint &>/dev/null; then
        state_set_resume_hint "${resume_cmd:-}" 2>/dev/null || true
    fi
}

# ============================================================
# Error handling
# ============================================================
# Track whether cleanup was triggered by a signal (not a normal EXIT).
_ACFS_SIGNAL_RECEIVED=""

_acfs_signal_handler() {
    _ACFS_SIGNAL_RECEIVED="$1"
    # Exit with 128+signum (standard convention) to trigger the EXIT trap.
    case "$1" in
        TERM) exit 143 ;;
        INT)  exit 130 ;;
        HUP)  exit 129 ;;
        *)    exit 1   ;;
    esac
}

acfs_bootstrap_dir_is_owned_temp() {
    local dir="${1:-}"
    local tmp_root="${_ACFS_BOOTSTRAP_DIR_TMP_ROOT:-}"

    [[ "${_ACFS_BOOTSTRAP_DIR_OWNED:-false}" == "true" ]] || return 1
    [[ -n "$dir" ]] || return 1
    [[ -n "${_ACFS_BOOTSTRAP_DIR_CREATED:-}" ]] || return 1
    [[ "$dir" == "$_ACFS_BOOTSTRAP_DIR_CREATED" ]] || return 1

    dir="${dir%/}"
    [[ "$dir" == /* ]] || return 1
    [[ "$dir" != "/" ]] || return 1
    [[ "$tmp_root" == /* ]] || return 1
    [[ "$dir" == "$tmp_root"/acfs-bootstrap-* ]] || return 1
    [[ -d "$dir" ]] || return 1
}

cleanup() {
    # Capture exit code FIRST, before any other commands can overwrite $?
    local exit_code=$?

    # Cleanup must never abort — disable errexit for the entire function.
    set +e

    if acfs_bootstrap_dir_is_owned_temp "${ACFS_BOOTSTRAP_DIR:-}"; then
        rm -rf -- "$ACFS_BOOTSTRAP_DIR" 2>/dev/null || true
    fi

    if [[ -n "${ACFS_TMP_ARCHIVE:-}" ]] && [[ -f "$ACFS_TMP_ARCHIVE" ]]; then
        rm -f "$ACFS_TMP_ARCHIVE" 2>/dev/null || true
    fi

    if [[ -n "${ACFS_TMP_SLB:-}" ]] && [[ -d "$ACFS_TMP_SLB" ]]; then
        rm -rf "$ACFS_TMP_SLB" 2>/dev/null || true
    fi

    if [[ -n "${ACFS_TMP_INSTALL:-}" ]] && [[ -f "$ACFS_TMP_INSTALL" ]]; then
        rm -f "$ACFS_TMP_INSTALL" 2>/dev/null || true
    fi

    # If a signal triggered this cleanup, mark state as interrupted so
    # resume logic does not see a partially-started phase.
    if [[ -n "${_ACFS_SIGNAL_RECEIVED:-}" ]]; then
        if type -t state_mark_interrupted &>/dev/null; then
            state_mark_interrupted 2>/dev/null || true
        fi
    fi

    if [[ $exit_code -ne 0 ]]; then
        log_error ""
        if [[ "${SMOKE_TEST_FAILED:-false}" == "true" ]]; then
            log_error "ACFS installation completed, but the post-install smoke test failed."
        else
            log_error "ACFS installation failed!"
        fi
        log_error ""
        log_error "To debug:"
        if [[ -n "${ACFS_LOG_FILE:-}" ]] && [[ -f "${ACFS_LOG_FILE:-}" ]]; then
            log_error "  1. Check the log: cat ${ACFS_LOG_FILE:-}"
        elif [[ -n "${ACFS_LOG_DIR:-}" ]] && [[ -d "${ACFS_LOG_DIR:-}" ]]; then
            log_error "  1. Check the log: cat ${ACFS_LOG_DIR:-}/install.log"
        else
            log_error "  1. Re-run with ACFS_DEBUG=true for detailed output"
        fi
        log_error "  2. If installed, run: acfs doctor (try as ${TARGET_USER:-ubuntu})"
        log_error "     (If you ran the installer as root: sudo -u ${TARGET_USER:-ubuntu} -i bash -lc 'acfs doctor')"
        log_error ""
        # Print precise resume hint if available (bd-31ps.9.1)
        # Get failed phase from state if available
        local failed_phase=""
        local failed_step=""
        if [[ -f "${ACFS_STATE_FILE:-}" ]] && command -v jq &>/dev/null; then
            failed_phase=$(jq -r '.failed_phase // empty' "${ACFS_STATE_FILE:-}" 2>/dev/null) || true
            failed_step=$(jq -r '.failed_step // empty' "${ACFS_STATE_FILE:-}" 2>/dev/null) || true
        fi
        print_resume_hint "${failed_phase:-}" "${failed_step:-}"
        log_error ""
        # Emit failure summary (best-effort)
        acfs_summary_emit "failure" 0 2>/dev/null || true
        # Send webhook notification for failure (bd-2zqr)
        if type -t webhook_notify &>/dev/null; then
            webhook_notify "failure" "${ACFS_SUMMARY_FILE:-}" 2>/dev/null || true
        fi
        # Send ntfy.sh notification for failure (bd-2igt6)
        if type -t acfs_notify_install_failure &>/dev/null; then
            acfs_notify_install_failure 2>/dev/null || true
        fi
    fi
    # Finalize log file (restore stderr, strip colors, add footer)
    acfs_log_close 2>/dev/null || true
}
trap cleanup EXIT
trap '_acfs_signal_handler TERM' TERM
trap '_acfs_signal_handler INT'  INT
trap '_acfs_signal_handler HUP'  HUP

# ============================================================
# Parse arguments
# ============================================================
acfs_require_ref_arg_value() {
    local flag="$1"
    local value="${2:-}"
    local example="$3"

    if [[ -z "$value" || "$value" == -* ]]; then
        log_fatal "$flag requires a ref (e.g., $example)"
    fi
    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        log_fatal "$flag requires a single-line ref"
    fi
    if ((${#value} > 120)); then
        log_fatal "$flag ref is too long"
    fi
    if [[ ! "$value" =~ ^[A-Za-z0-9._/-]+$ ]]; then
        log_fatal "$flag contains unsafe ref characters; use letters, numbers, '.', '_', '-', and '/'"
    fi
    case "$value" in
        @|.|..|/*|*/|.*|*.|*//*|*/.*|*..*|*.lock)
            log_fatal "$flag has invalid git ref syntax"
            ;;
    esac
}

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
                if [[ -z "${2:-}" || "$2" == -* ]]; then
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
                    acfs_require_ref_arg_value "--checksums-ref" "${2:-}" "--checksums-ref main"
                    ACFS_CHECKSUMS_REF="$2"
                    shift 2
                else
                    ACFS_CHECKSUMS_REF="${1#*=}"
                    acfs_require_ref_arg_value "--checksums-ref" "$ACFS_CHECKSUMS_REF" "--checksums-ref=main"
                    shift
                fi
                ACFS_CHECKSUMS_REF_EXPLICIT=true
                ACFS_CHECKSUMS_RAW="https://raw.githubusercontent.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/${ACFS_CHECKSUMS_REF}"
                export ACFS_CHECKSUMS_REF ACFS_CHECKSUMS_RAW ACFS_CHECKSUMS_REF_EXPLICIT
                ;;
            --pin-ref|--confirm-ref)
                # Print resolved SHA and pinned command, then exit
                PIN_REF_MODE=true
                shift
                ;;
            --ref|--ref=*)
                # Set ACFS_REF from CLI (fixes curl|bash where env vars
                # bind to curl, not bash: ACFS_REF=v1 curl ... | bash
                # doesn't propagate to the bash process)
                if [[ "$1" == "--ref" ]]; then
                    acfs_require_ref_arg_value "--ref" "${2:-}" "--ref main"
                    ACFS_REF="$2"
                    shift 2
                else
                    ACFS_REF="${1#*=}"
                    acfs_require_ref_arg_value "--ref" "$ACFS_REF" "--ref=main"
                    shift
                fi
                ACFS_REF_INPUT="$ACFS_REF"
                ACFS_RAW="https://raw.githubusercontent.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/${ACFS_REF}"
                # Recalculate checksums ref for the new install ref unless the
                # user explicitly pinned checksum metadata with --checksums-ref
                # or ACFS_CHECKSUMS_REF.
                if [[ "${ACFS_CHECKSUMS_REF_EXPLICIT:-false}" != "true" ]]; then
                    if [[ "$ACFS_REF" =~ ^v[0-9]+(\.[0-9]+){1,2}([.-][A-Za-z0-9]+)*$ ]] || [[ "$ACFS_REF" =~ ^[0-9a-f]{7,40}$ ]]; then
                        ACFS_CHECKSUMS_REF="main"
                    else
                        ACFS_CHECKSUMS_REF="$ACFS_REF"
                    fi
                fi
                ACFS_CHECKSUMS_RAW="https://raw.githubusercontent.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/${ACFS_CHECKSUMS_REF}"
                export ACFS_REF ACFS_RAW ACFS_CHECKSUMS_REF ACFS_CHECKSUMS_RAW ACFS_CHECKSUMS_REF_EXPLICIT
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
                    if [[ -z "${2:-}" || "$2" == -* ]]; then
                        log_fatal "--target-ubuntu requires a version (e.g., --target-ubuntu 25.10)"
                    fi
                    # shellcheck disable=SC2034  # used by run_ubuntu_upgrade_phase
                    TARGET_UBUNTU_VERSION="$2"
                    TARGET_UBUNTU_VERSION_EXPLICIT=true
                    shift 2
                else
                    # Handle --target-ubuntu=25.10 format
                    # shellcheck disable=SC2034  # used by run_ubuntu_upgrade_phase
                    TARGET_UBUNTU_VERSION="${1#*=}"
                    TARGET_UBUNTU_VERSION_EXPLICIT=true
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
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_fatal "--only requires a module ID"
                fi
                ONLY_MODULES+=("$2")
                shift 2
                ;;
            --only-phase)
                # Add phase to ONLY_PHASES list
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_fatal "--only-phase requires a phase number"
                fi
                ONLY_PHASES+=("$2")
                shift 2
                ;;
            --skip)
                # Add module to SKIP_MODULES list
                if [[ -z "${2:-}" || "$2" == -* ]]; then
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
            --webhook|--webhook=*)
                # Webhook URL for install completion notification (bd-2zqr)
                if [[ "$1" == "--webhook" ]]; then
                    if [[ -z "${2:-}" ]]; then
                        log_fatal "--webhook requires a URL (e.g., --webhook https://hooks.slack.com/...)"
                    fi
                    export ACFS_WEBHOOK_URL="$2"
                    shift 2
                else
                    # Handle --webhook=https://... format
                    export ACFS_WEBHOOK_URL="${1#*=}"
                    shift
                fi
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
normalize_read_only_modes() {
    if [[ "${DRY_RUN:-false}" != "true" ]] && [[ "${PRINT_MODE:-false}" != "true" ]]; then
        return 0
    fi

    case "${AUTO_FIX_MODE:-prompt}" in
        no|dry-run)
            ;;
        *)
            AUTO_FIX_MODE="dry-run"
            ;;
    esac
}

command_exists() {
    command -v "$1" &>/dev/null
}

# Interactive yes/no confirmation prompt
# Returns 0 for yes, 1 for no
confirm() {
    local prompt="${1:-Continue?}"
    local response=""

    # In --yes mode, auto-accept all prompts (fixes non-TTY curl|bash failure)
    if [[ "${YES_MODE:-false}" == "true" ]]; then
        return 0
    fi

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
        # Fallback: current directory (only valid for testing from repo root)
        # This should NOT be reached in curl-pipe mode since bootstrap_repo_archive
        # sets ACFS_BOOTSTRAP_DIR. If we reach here without SCRIPT_DIR, something is wrong.
        ACFS_LIB_DIR="./scripts/lib"
        ACFS_GENERATED_DIR="./scripts/generated"
        ACFS_ASSETS_DIR="./acfs"
        ACFS_CHECKSUMS_YAML="./checksums.yaml"
        ACFS_MANIFEST_YAML="./acfs.manifest.yaml"
    fi

    export ACFS_LIB_DIR ACFS_GENERATED_DIR ACFS_ASSETS_DIR ACFS_CHECKSUMS_YAML ACFS_MANIFEST_YAML

    # Validate that library directory exists - if not, fail early with a clear message
    if [[ ! -d "$ACFS_LIB_DIR" ]]; then
        local abs_lib_dir="$ACFS_LIB_DIR"
        # Try to show absolute path for better debugging
        if [[ "$ACFS_LIB_DIR" == ./* ]]; then
            abs_lib_dir="$(pwd)/${ACFS_LIB_DIR#./}"
        fi
        echo "ERROR: Library directory not found: $abs_lib_dir" >&2
        echo "This typically means bootstrap failed or the script is being run from an unexpected location." >&2
        echo "For curl|bash installation, ensure network connectivity to GitHub." >&2
        echo "For local installation, run from the repository root directory." >&2
        exit 1
    fi

    # Source minimal libs in correct order (logging, then helpers)
    if [[ -f "$ACFS_LIB_DIR/logging.sh" ]]; then
        # shellcheck source=scripts/lib/logging.sh
        source "$ACFS_LIB_DIR/logging.sh"
    fi

    # Verify internal script integrity before sourcing (bd-3tpl.5)
    # Fail-closed: abort if any tracked script has been modified.
    # Gracefully skips if checksums file is missing (pre-migration compat).
    if [[ -f "$ACFS_GENERATED_DIR/internal_checksums.sh" ]]; then
        # shellcheck source=scripts/generated/internal_checksums.sh
        source "$ACFS_GENERATED_DIR/internal_checksums.sh"
        if declare -p ACFS_INTERNAL_CHECKSUMS &>/dev/null; then
            local _ics_base
            if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]]; then
                _ics_base="$ACFS_BOOTSTRAP_DIR"
            elif [[ -n "${SCRIPT_DIR:-}" ]]; then
                _ics_base="$SCRIPT_DIR"
            else
                _ics_base="."
            fi
            local _ics_fail=0
            for _ics_path in "${!ACFS_INTERNAL_CHECKSUMS[@]}"; do
                local _ics_expected="${ACFS_INTERNAL_CHECKSUMS[$_ics_path]}"
                local _ics_file="$_ics_base/$_ics_path"
                if [[ -f "$_ics_file" ]]; then
                    local _ics_actual
                    _ics_actual="$(acfs_calculate_file_sha256 "$_ics_file" 2>/dev/null || true)"
                    if [[ -z "$_ics_actual" ]]; then
                        _ics_fail=$((_ics_fail + 1))
                        if declare -f log_error &>/dev/null; then
                            log_error "INTEGRITY: failed to checksum $_ics_path"
                        else
                            echo "ERROR: INTEGRITY: failed to checksum $_ics_path" >&2
                        fi
                        continue
                    fi
                    if [[ "$_ics_actual" != "$_ics_expected" ]]; then
                        _ics_fail=$((_ics_fail + 1))
                        if declare -f log_error &>/dev/null; then
                            log_error "INTEGRITY: $_ics_path checksum mismatch (expected ${_ics_expected:0:12}… got ${_ics_actual:0:12}…)"
                        else
                            echo "ERROR: INTEGRITY: $_ics_path checksum mismatch" >&2
                        fi
                    fi
                else
                    _ics_fail=$((_ics_fail + 1))
                    if declare -f log_error &>/dev/null; then
                        log_error "INTEGRITY: $_ics_path missing (expected checksum ${_ics_expected:0:12}…)"
                    else
                        echo "ERROR: INTEGRITY: $_ics_path missing" >&2
                    fi
                fi
            done
            if [[ "$_ics_fail" -gt 0 ]]; then
                local _msg="Internal script integrity check failed: $_ics_fail file(s) modified. Run 'bun run generate' to regenerate checksums."
                if declare -f log_error &>/dev/null; then
                    log_error "$_msg"
                else
                    echo "ERROR: $_msg" >&2
                fi
                exit 1
            fi
            if [[ "$_ics_fail" -eq 0 ]] && declare -f log_success &>/dev/null; then
                log_success "Internal script integrity verified (${ACFS_INTERNAL_CHECKSUMS_COUNT:-?} scripts)"
            fi
        fi
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

    # Source webhook notification library (bd-2zqr)
    if [[ -f "$ACFS_LIB_DIR/webhook.sh" ]]; then
        # shellcheck source=scripts/lib/webhook.sh
        source "$ACFS_LIB_DIR/webhook.sh"
    fi
    # Source ntfy.sh notification library (bd-2igt6)
    if [[ -f "$ACFS_LIB_DIR/notify.sh" ]]; then
        # shellcheck source=scripts/lib/notify.sh
        source "$ACFS_LIB_DIR/notify.sh"
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
            # In --yes mode or non-TTY (curl|bash), auto-accept the fix
            if [[ "${YES_MODE:-false}" == "true" ]] || [[ ! -t 0 ]]; then
                log_info "[AUTO-FIX] Fixing (non-interactive): $description"
                if type "$fix_func" &>/dev/null; then
                    "$fix_func" fix
                else
                    log_warn "[AUTO-FIX] Fix function not available: $fix_func"
                fi
            elif confirm "Would you like ACFS to fix this automatically?"; then
                log_info "[AUTO-FIX] Fixing: $description"
                if type "$fix_func" &>/dev/null; then
                    "$fix_func" fix
                else
                    log_warn "[AUTO-FIX] Fix function not available: $fix_func"
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
        return 0
    fi

    # Skip if auto-fix disabled
    if [[ "$AUTO_FIX_MODE" == "no" ]]; then
        log_debug "Auto-fix disabled via --no-auto-fix" 2>/dev/null || true
        return 0
    fi

    log_info "Running auto-fix pre-flight checks..."

    # Check for existing ACFS installation
    # Skip this check when --only or --only-phase is specified, since the user
    # is targeting a specific module on an already-installed system
    if [[ ${#ONLY_MODULES[@]} -eq 0 ]] && [[ ${#ONLY_PHASES[@]} -eq 0 ]]; then
        if type autofix_existing_acfs_needs_handling &>/dev/null; then
            if autofix_existing_acfs_needs_handling 2>/dev/null; then
                local version
                version=$(get_installed_version 2>/dev/null || echo "unknown")
                handle_autofix "existing" "Existing ACFS installation detected (version: $version)"
            fi
        fi
    else
        log_debug "Skipping existing-installation check (--only/--only-phase mode)"
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
        local curl_bin=""
        curl_bin="$(acfs_early_system_binary_path curl 2>/dev/null || true)"
        if [[ -n "$curl_bin" ]]; then
            log_detail "Downloading preflight script..."
            local mktemp_bin=""
            mktemp_bin="$(acfs_early_system_binary_path mktemp 2>/dev/null || true)"
            if [[ -n "$mktemp_bin" ]]; then
                preflight_tmp="$("$mktemp_bin" "${TMPDIR:-/tmp}/acfs-preflight.XXXXXX" 2>/dev/null)" || preflight_tmp=""
            fi
            if [[ -n "$preflight_tmp" ]] && acfs_curl -o "$preflight_tmp" "$ACFS_RAW/scripts/preflight.sh" 2>/dev/null; then
                local chmod_bin=""
                chmod_bin="$(acfs_early_system_binary_path chmod 2>/dev/null || true)"
                if [[ -n "$chmod_bin" ]]; then
                    "$chmod_bin" +x "$preflight_tmp"
                fi
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
    local bash_bin=""
    bash_bin="$(acfs_early_system_binary_path bash 2>/dev/null || true)"
    if [[ -z "$bash_bin" ]]; then
        log_warn "bash not available - skipping preflight checks"
        return 0
    fi
    "$bash_bin" "$preflight_script" || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo "" >&2
        log_error "Pre-flight validation failed!"
        echo "" >&2
        log_info "Run preflight checks for details:"
        log_info "  bash $preflight_script"
        echo "" >&2
        log_info "Use --skip-preflight to bypass (not recommended)"
        echo "" >&2
        if [[ -n "$preflight_tmp" ]]; then
            rm -f "$preflight_tmp"
        fi
        exit 1
    fi

    # Cleanup downloaded preflight script on success
    if [[ -n "$preflight_tmp" ]]; then
        rm -f "$preflight_tmp"
    fi

    log_success "[0/9] Pre-flight validation passed"
    echo ""
}

ACFS_CURL_BASE_ARGS=(--connect-timeout 30 --max-time 300 -fsSL)
_acfs_early_curl_bin="$(acfs_early_system_binary_path curl 2>/dev/null || true)"
_acfs_early_grep_bin="$(acfs_early_system_binary_path grep 2>/dev/null || true)"
if [[ -n "$_acfs_early_curl_bin" && -n "$_acfs_early_grep_bin" ]] && "$_acfs_early_curl_bin" --help all 2>/dev/null | "$_acfs_early_grep_bin" -q -- '--proto'; then
    ACFS_CURL_BASE_ARGS=(--proto '=https' --proto-redir '=https' --connect-timeout 30 --max-time 300 -fsSL)
fi
unset _acfs_early_curl_bin _acfs_early_grep_bin

acfs_curl() {
    local curl_bin=""
    curl_bin="$(acfs_early_system_binary_path curl 2>/dev/null || true)"
    if [[ -z "$curl_bin" ]]; then
        log_error "Unable to locate curl"
        return 1
    fi

    "$curl_bin" "${ACFS_CURL_BASE_ARGS[@]}" "$@"
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
        else
            exit_code=$?
        fi
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
    local tmp_dir
    local mktemp_bin=""
    local chmod_bin=""
    local tar_bin=""
    local rm_bin=""
    local find_bin=""
    local bash_bin=""
    local grep_bin=""
    local head_bin=""
    local cut_bin=""
    local tr_bin=""

    tar_bin="$(acfs_early_system_binary_path tar 2>/dev/null || true)"
    if [[ -z "$tar_bin" ]]; then
        log_error "Bootstrap requires tar (install tar or run from a local checkout)"
        return 1
    fi
    mktemp_bin="$(acfs_early_system_binary_path mktemp 2>/dev/null || true)"
    chmod_bin="$(acfs_early_system_binary_path chmod 2>/dev/null || true)"
    rm_bin="$(acfs_early_system_binary_path rm 2>/dev/null || true)"
    find_bin="$(acfs_early_system_binary_path find 2>/dev/null || true)"
    bash_bin="$(acfs_early_system_binary_path bash 2>/dev/null || true)"
    grep_bin="$(acfs_early_system_binary_path grep 2>/dev/null || true)"
    head_bin="$(acfs_early_system_binary_path head 2>/dev/null || true)"
    cut_bin="$(acfs_early_system_binary_path cut 2>/dev/null || true)"
    tr_bin="$(acfs_early_system_binary_path tr 2>/dev/null || true)"
    if [[ -z "$mktemp_bin" || -z "$chmod_bin" || -z "$rm_bin" || -z "$find_bin" || -z "$bash_bin" || -z "$grep_bin" || -z "$head_bin" || -z "$cut_bin" || -z "$tr_bin" ]]; then
        log_error "Bootstrap requires core system utilities (mktemp, chmod, rm, find, bash, grep, head, cut, tr)"
        return 1
    fi

    # mktemp portability: BSD mktemp requires Xs at end of template; tar doesn't need a .tar.gz suffix.
    ACFS_TMP_ARCHIVE="$("$mktemp_bin" "${TMPDIR:-/tmp}/acfs-archive-${ref_safe}.XXXXXX" 2>/dev/null)" || {
        log_fatal "Failed to create temp file for archive"
    }

    tmp_dir="$("$mktemp_bin" -d "${TMPDIR:-/tmp}/acfs-bootstrap-${ref_safe}.XXXXXX" 2>/dev/null)" || {
        log_fatal "Failed to create temp dir for extraction"
    }
    ACFS_BOOTSTRAP_DIR="$tmp_dir"
    _ACFS_BOOTSTRAP_DIR_CREATED="$tmp_dir"
    _ACFS_BOOTSTRAP_DIR_TMP_ROOT="${TMPDIR:-/tmp}"
    _ACFS_BOOTSTRAP_DIR_TMP_ROOT="${_ACFS_BOOTSTRAP_DIR_TMP_ROOT%/}"
    _ACFS_BOOTSTRAP_DIR_OWNED=true
    # Make bootstrap dir world-readable so ubuntu user can access scripts
    "$chmod_bin" 755 "$tmp_dir"

    log_step "Bootstrapping ACFS archive (${ref})"

    # Test-mode hook: offline bootstrap checks cannot use PATH-based curl
    # stubs because acfs_curl resolves curl via absolute paths only (intentional
    # hardening, commit 958e2ee2). The hook lets tests point the bootstrap at
    # a locally-staged archive and skip the network entirely. Gated on an
    # explicit ACFS_TEST_MODE=1 so accidentally setting ACFS_TEST_ARCHIVE in
    # production cannot bypass the network path.
    if [[ "${ACFS_TEST_MODE:-}" == "1" && -n "${ACFS_TEST_ARCHIVE:-}" ]]; then
        local cp_bin
        cp_bin="$(acfs_early_system_binary_path cp 2>/dev/null || true)"
        if [[ -z "$cp_bin" ]]; then
            log_error "Test-mode bootstrap requires cp"
            "$rm_bin" -rf "$tmp_dir"
            return 1
        fi
        if [[ ! -f "$ACFS_TEST_ARCHIVE" ]]; then
            log_error "ACFS_TEST_MODE=1 but ACFS_TEST_ARCHIVE is not a regular file: $ACFS_TEST_ARCHIVE"
            "$rm_bin" -f "$ACFS_TMP_ARCHIVE"
            "$rm_bin" -rf "$tmp_dir"
            return 1
        fi
        log_detail "Test mode: using local archive $ACFS_TEST_ARCHIVE"
        if ! "$cp_bin" "$ACFS_TEST_ARCHIVE" "$ACFS_TMP_ARCHIVE"; then
            log_error "Failed to stage local archive for bootstrap"
            "$rm_bin" -f "$ACFS_TMP_ARCHIVE"
            "$rm_bin" -rf "$tmp_dir"
            return 1
        fi
    else
        log_detail "Downloading ${archive_url}"
        if ! acfs_curl_with_retry "$archive_url" "$ACFS_TMP_ARCHIVE"; then
            log_error "Failed to download ACFS archive. Try again, or pin ACFS_REF to a tag/sha."
            "$rm_bin" -f "$ACFS_TMP_ARCHIVE"
            "$rm_bin" -rf "$tmp_dir"
            return 1
        fi
    fi

    log_detail "Extracting runtime assets"
    if ! "$tar_bin" -xzf "$ACFS_TMP_ARCHIVE" -C "$tmp_dir" --strip-components=1 \
        --wildcards --wildcards-match-slash \
        "*/scripts/**" \
        "*/acfs/**" \
        "*/checksums.yaml" \
        "*/acfs.manifest.yaml" \
        "*/VERSION"; then
        log_error "Failed to extract ACFS bootstrap archive (tar error)"
        "$rm_bin" -f "$ACFS_TMP_ARCHIVE"
        return 1
    fi
    "$rm_bin" -f "$ACFS_TMP_ARCHIVE"

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
        if ! "$bash_bin" -n "$script_file" >/dev/null 2>&1; then
            log_error "Syntax error in extracted script: $script_file"
            shellcheck_failed=true
            break
        fi
    done < <("$find_bin" "$tmp_dir" -type f -name "*.sh" -print0)

    if [[ "$shellcheck_failed" == "true" ]]; then
        log_error "Bootstrap validation failed. Retry or pin ACFS_REF to a known-good tag/sha."
        return 1
    fi

    local manifest_sha expected_sha
    manifest_sha="$(acfs_calculate_file_sha256 "$tmp_dir/acfs.manifest.yaml")" || return 1
    expected_sha="$("$grep_bin" -E '^ACFS_MANIFEST_SHA256=' "$tmp_dir/scripts/generated/manifest_index.sh" | "$head_bin" -n 1 | "$cut_bin" -d'=' -f2 | "$tr_bin" -d '"[:space:]\r' || true)"

    if [[ -z "$expected_sha" ]]; then
        log_error "Bootstrap manifest index missing ACFS_MANIFEST_SHA256"
        return 1
    fi

    if [[ "$manifest_sha" != "$expected_sha" ]]; then
        log_error "Bootstrap mismatch: generated scripts do not match manifest."
        log_detail "Expected: $expected_sha"
        log_detail "Actual:   $manifest_sha"
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

    local -a sudo_cmd=()
    local sudo_bin=""
    if [[ $EUID -ne 0 ]]; then
        sudo_bin="$(acfs_early_sudo_binary_path 2>/dev/null || true)"
        if [[ -n "$sudo_bin" ]]; then
            sudo_cmd=("$sudo_bin")
        fi
    fi

    local mkdir_bin=""
    local cp_bin=""
    mkdir_bin="$(acfs_early_system_binary_path mkdir 2>/dev/null || true)"
    if [[ -z "$mkdir_bin" ]]; then
        log_error "install_asset: Unable to locate mkdir"
        return 1
    fi
    cp_bin="$(acfs_early_system_binary_path cp 2>/dev/null || true)"
    if [[ -z "$cp_bin" ]]; then
        log_error "install_asset: Unable to locate cp"
        return 1
    fi

    # Security: Validate dest_path is under expected directories
    local allowed_prefixes=("$ACFS_HOME" "$TARGET_HOME" "/data" "/usr/local/bin")
    if [[ -n "${ACFS_BIN_DIR:-}" ]] && [[ "$ACFS_BIN_DIR" == /* ]] && [[ "$ACFS_BIN_DIR" != "/" ]]; then
        allowed_prefixes+=("$ACFS_BIN_DIR")
    fi
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

    # Ensure destination directory exists (matches install_asset_from_path behavior)
    local _ia_dest_dir
    _ia_dest_dir="$(dirname "$dest_path")"
    if [[ ! -d "$_ia_dest_dir" ]]; then
        if [[ -w "$(dirname "$_ia_dest_dir" 2>/dev/null)" ]] || [[ $EUID -eq 0 ]]; then
            "$mkdir_bin" -p "$_ia_dest_dir" 2>/dev/null || true
        elif [[ ${#sudo_cmd[@]} -gt 0 ]]; then
            "${sudo_cmd[@]}" "$mkdir_bin" -p "$_ia_dest_dir" 2>/dev/null || true
        fi
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
        if [[ -n "${ACFS_BIN_DIR:-}" ]] && [[ "$ACFS_BIN_DIR" == /* ]] && [[ "$ACFS_BIN_DIR" != "/" ]] && \
           [[ "$ACFS_BIN_DIR" != "/usr/local/bin" ]] && \
           _acfs_install_asset_has_symlink_component_under_prefix "$ACFS_BIN_DIR" "$dest_path"; then
            log_error "install_asset: Refusing to write through symlink path component: $dest_path"
            return 1
        fi
    fi

    local dest_dir
    dest_dir="$(dirname "$dest_path")"

    local need_sudo=false
    if [[ -e "$dest_path" ]]; then
        [[ -w "$dest_path" ]] || need_sudo=true
    else
        [[ -w "$dest_dir" ]] || need_sudo=true
    fi

    if [[ "$need_sudo" == "true" ]] && [[ ${#sudo_cmd[@]} -eq 0 ]]; then
        log_error "install_asset: Destination not writable and sudo not available: $dest_path"
        return 1
    fi

    if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -f "$ACFS_BOOTSTRAP_DIR/$rel_path" ]]; then
        if [[ "$need_sudo" == "true" ]]; then
            if ! "${sudo_cmd[@]}" "$cp_bin" "$ACFS_BOOTSTRAP_DIR/$rel_path" "$dest_path"; then
                log_error "install_asset: Failed to copy from bootstrap: $rel_path"
                return 1
            fi
        elif ! "$cp_bin" "$ACFS_BOOTSTRAP_DIR/$rel_path" "$dest_path"; then
            log_error "install_asset: Failed to copy from bootstrap: $rel_path"
            return 1
        fi
    elif [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "$SCRIPT_DIR/$rel_path" ]]; then
        if [[ "$need_sudo" == "true" ]]; then
            if ! "${sudo_cmd[@]}" "$cp_bin" "$SCRIPT_DIR/$rel_path" "$dest_path"; then
                log_error "install_asset: Failed to copy from script dir: $rel_path"
                return 1
            fi
        elif ! "$cp_bin" "$SCRIPT_DIR/$rel_path" "$dest_path"; then
            log_error "install_asset: Failed to copy from script dir: $rel_path"
            return 1
        fi
    else
        if [[ "$need_sudo" == "true" ]]; then
            local curl_bin=""
            curl_bin="$(acfs_early_system_binary_path curl 2>/dev/null || true)"
            if [[ -z "$curl_bin" ]]; then
                log_error "install_asset: Unable to locate curl"
                return 1
            fi
            if ! "${sudo_cmd[@]}" "$curl_bin" "${ACFS_CURL_BASE_ARGS[@]}" -o "$dest_path" "$ACFS_RAW/$rel_path"; then
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

install_asset_from_path() {
    local src_path="$1"
    local dest_path="$2"

    if [[ -z "$src_path" || -z "$dest_path" ]]; then
        log_error "install_asset_from_path: Missing source or destination path"
        return 1
    fi

    if [[ ! -f "$src_path" ]]; then
        log_error "install_asset_from_path: Source file not found: $src_path"
        return 1
    fi

    local dest_dir
    dest_dir="$(dirname "$dest_path")"

    local -a sudo_cmd=()
    local sudo_bin=""
    if [[ $EUID -ne 0 ]]; then
        sudo_bin="$(acfs_early_sudo_binary_path 2>/dev/null || true)"
        if [[ -n "$sudo_bin" ]]; then
            sudo_cmd=("$sudo_bin")
        fi
    fi

    local mkdir_bin=""
    local cp_bin=""
    mkdir_bin="$(acfs_early_system_binary_path mkdir 2>/dev/null || true)"
    if [[ -z "$mkdir_bin" ]]; then
        log_error "install_asset_from_path: Unable to locate mkdir"
        return 1
    fi
    cp_bin="$(acfs_early_system_binary_path cp 2>/dev/null || true)"
    if [[ -z "$cp_bin" ]]; then
        log_error "install_asset_from_path: Unable to locate cp"
        return 1
    fi

    local need_sudo=false
    if [[ -e "$dest_path" ]]; then
        [[ -w "$dest_path" ]] || need_sudo=true
    else
        [[ -w "$dest_dir" ]] || need_sudo=true
    fi

    if [[ "$need_sudo" == "true" ]] && [[ ${#sudo_cmd[@]} -eq 0 ]]; then
        log_error "install_asset_from_path: Destination not writable and sudo not available: $dest_path"
        return 1
    fi

    if [[ "$need_sudo" == "true" ]]; then
        if ! "${sudo_cmd[@]}" "$mkdir_bin" -p "$dest_dir"; then
            log_error "install_asset_from_path: Failed to create destination directory: $dest_dir"
            return 1
        fi
        if ! "${sudo_cmd[@]}" "$cp_bin" "$src_path" "$dest_path"; then
            log_error "install_asset_from_path: Failed to copy $src_path to $dest_path"
            return 1
        fi
    else
        if ! "$mkdir_bin" -p "$dest_dir"; then
            log_error "install_asset_from_path: Failed to create destination directory: $dest_dir"
            return 1
        fi
        if ! "$cp_bin" "$src_path" "$dest_path"; then
            log_error "install_asset_from_path: Failed to copy $src_path to $dest_path"
            return 1
        fi
    fi

    if [[ ! -f "$dest_path" ]]; then
        log_error "install_asset_from_path: File not created: $dest_path"
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

    local -a sudo_cmd=()
    local sudo_bin=""
    if [[ $EUID -ne 0 ]]; then
        sudo_bin="$(acfs_early_sudo_binary_path 2>/dev/null || true)"
        if [[ -n "$sudo_bin" ]]; then
            sudo_cmd=("$sudo_bin")
        fi
    fi

    local mkdir_bin=""
    local tee_bin=""
    mkdir_bin="$(acfs_early_system_binary_path mkdir 2>/dev/null || true)"
    if [[ -z "$mkdir_bin" ]]; then
        log_error "install_checksums_yaml: Unable to locate mkdir"
        return 1
    fi
    tee_bin="$(acfs_early_system_binary_path tee 2>/dev/null || true)"
    if [[ -z "$tee_bin" ]]; then
        log_error "install_checksums_yaml: Unable to locate tee"
        return 1
    fi

    if [[ ! -d "$dest_dir" ]]; then
        if [[ -w "$(dirname "$dest_dir" 2>/dev/null)" ]] || [[ $EUID -eq 0 ]]; then
            "$mkdir_bin" -p "$dest_dir" 2>/dev/null || true
        elif [[ ${#sudo_cmd[@]} -gt 0 ]]; then
            "${sudo_cmd[@]}" "$mkdir_bin" -p "$dest_dir" 2>/dev/null || true
        fi
    fi

    local need_sudo=false
    if [[ -e "$dest_path" ]]; then
        [[ -w "$dest_path" ]] || need_sudo=true
    else
        [[ -w "$dest_dir" ]] || need_sudo=true
    fi

    if [[ "$need_sudo" == "true" ]] && [[ ${#sudo_cmd[@]} -eq 0 ]]; then
        log_error "install_checksums_yaml: Destination not writable and sudo not available: $dest_path"
        return 1
    fi

    if [[ "$need_sudo" == "true" ]]; then
        if ! printf '%s' "$content" | "${sudo_cmd[@]}" "$tee_bin" "$dest_path" >/dev/null; then
            log_error "install_checksums_yaml: Failed to write $dest_path"
            return 1
        fi
    else
        if ! printf '%s' "$content" > "$dest_path"; then
            log_error "install_checksums_yaml: Failed to write $dest_path"
            return 1
        fi
    fi

    if [[ ! -f "$dest_path" ]]; then
        log_error "install_checksums_yaml: File not created: $dest_path"
        return 1
    fi
}

run_as_target() {
    local user="$TARGET_USER"
    local explicit_user_home="${TARGET_HOME:-}"
    local explicit_user_home_for_repair=""
    local user_home=""
    local passwd_entry=""
    local passwd_home=""
    local primary_bin_dir=""
    local acfs_home_for_target=""
    local env_bin=""
    local bash_bin=""
    local sh_bin=""
    local sudo_bin=""
    local runuser_bin=""
    local su_bin=""
    local -a command_argv=()

    if [[ -z "$user" ]] || [[ ! "$user" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
        log_error "Invalid TARGET_USER '${user:-<empty>}' (expected: lowercase user name like 'ubuntu')"
        return 1
    fi
    env_bin="$(acfs_early_system_binary_path env 2>/dev/null || true)"
    if [[ -z "$env_bin" ]]; then
        log_error "Unable to locate env for target-user command"
        return 1
    fi
    bash_bin="$(acfs_early_system_binary_path bash 2>/dev/null || true)"
    if [[ -z "$bash_bin" ]]; then
        log_error "Unable to locate bash for target-user command"
        return 1
    fi
    sh_bin="$(acfs_early_system_binary_path sh 2>/dev/null || true)"
    if [[ -z "$sh_bin" ]]; then
        log_error "Unable to locate sh for target-user command"
        return 1
    fi

    if [[ "$user" == "root" ]]; then
        user_home="/root"
    else
        passwd_entry="$(acfs_early_getent_passwd_entry "$user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
            if [[ -n "$passwd_home" ]] && [[ "$passwd_home" == /* ]] && [[ "$passwd_home" != "/" ]]; then
                user_home="${passwd_home%/}"
            fi
        fi
    fi

    if [[ "$explicit_user_home" == /* ]] && [[ "$explicit_user_home" != "/" ]]; then
        explicit_user_home_for_repair="${explicit_user_home%/}"
        [[ "$explicit_user_home_for_repair" != "/" ]] || explicit_user_home_for_repair=""
    fi

    if [[ -z "$user_home" ]]; then
        user_home="$(acfs_home_for_user "$user" || true)"
    fi
    if [[ -z "$user_home" ]] || [[ "$user_home" == "/" ]] || [[ "$user_home" != /* ]]; then
        log_error "Invalid TARGET_HOME for '$user': ${user_home:-<empty>} (must be an absolute path and cannot be '/')"
        return 1
    fi

    primary_bin_dir="${ACFS_BIN_DIR:-$user_home/.local/bin}"
    if [[ -n "$explicit_user_home_for_repair" ]] && [[ "$explicit_user_home_for_repair" != "$user_home" ]]; then
        case "$primary_bin_dir" in
            "$explicit_user_home_for_repair"|"$explicit_user_home_for_repair"/*)
                primary_bin_dir="$user_home/.local/bin"
                ;;
        esac
    fi
    acfs_home_for_target="${ACFS_HOME:-}"
    if [[ -n "$explicit_user_home_for_repair" ]] && [[ "$explicit_user_home_for_repair" != "$user_home" ]]; then
        case "$acfs_home_for_target" in
            "$explicit_user_home_for_repair"|"$explicit_user_home_for_repair"/*)
                acfs_home_for_target="$user_home/.acfs"
                ;;
        esac
    fi

    local target_path_prefix="$primary_bin_dir:$user_home/.local/bin:$user_home/.acfs/bin:$user_home/.cargo/bin:$user_home/.bun/bin:$user_home/.atuin/bin:$user_home/go/bin"
    local current_path="${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"

    # Environment variables to set for target user commands
    # UV_NO_CONFIG prevents uv from looking for config in /root when running via sudo
    # HOME is set explicitly to ensure consistent home directory.
    # PATH must include the target user's tool bins because we intentionally
    # avoid login shells and therefore cannot rely on profile files.
    # XDG_RUNTIME_DIR / DBUS_SESSION_BUS_ADDRESS let user services work even when
    # install.sh is running as root and switching to TARGET_USER non-interactively.
    local -a env_args=("UV_NO_CONFIG=1" "HOME=$user_home" "PATH=$target_path_prefix:$current_path" "TARGET_USER=$user" "TARGET_HOME=$user_home")
    local target_uid=""
    local target_runtime_dir=""
    local id_bin=""
    local current_user=""
    id_bin="$(acfs_early_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]] && target_uid="$($id_bin -u "$user" 2>/dev/null)"; then
        target_runtime_dir="/run/user/$target_uid"
        if [[ -d "$target_runtime_dir" ]]; then
            env_args+=("XDG_RUNTIME_DIR=$target_runtime_dir")
            if [[ -S "$target_runtime_dir/bus" ]]; then
                env_args+=("DBUS_SESSION_BUS_ADDRESS=unix:path=$target_runtime_dir/bus")
            fi
        fi
    fi

    # Pass ACFS context variables to target user environment
    if [[ -n "$acfs_home_for_target" ]]; then env_args+=("ACFS_HOME=$acfs_home_for_target"); fi
    if [[ -n "${ACFS_BIN_DIR:-}" ]]; then env_args+=("ACFS_BIN_DIR=$primary_bin_dir"); fi
    if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]]; then env_args+=("ACFS_BOOTSTRAP_DIR=$ACFS_BOOTSTRAP_DIR"); fi
    if [[ -n "${ACFS_LIB_DIR:-}" ]]; then env_args+=("ACFS_LIB_DIR=$ACFS_LIB_DIR"); fi
    if [[ -n "${ACFS_GENERATED_DIR:-}" ]]; then env_args+=("ACFS_GENERATED_DIR=$ACFS_GENERATED_DIR"); fi
    if [[ -n "${ACFS_ASSETS_DIR:-}" ]]; then env_args+=("ACFS_ASSETS_DIR=$ACFS_ASSETS_DIR"); fi
    if [[ -n "${ACFS_CHECKSUMS_YAML:-}" ]]; then env_args+=("ACFS_CHECKSUMS_YAML=$ACFS_CHECKSUMS_YAML"); fi
    if [[ -n "${ACFS_MANIFEST_YAML:-}" ]]; then env_args+=("ACFS_MANIFEST_YAML=$ACFS_MANIFEST_YAML"); fi
    if [[ -n "${CHECKSUMS_FILE:-}" ]]; then env_args+=("CHECKSUMS_FILE=$CHECKSUMS_FILE"); fi
    if [[ -n "${SCRIPT_DIR:-}" ]]; then env_args+=("SCRIPT_DIR=$SCRIPT_DIR"); fi
    if [[ -n "${ACFS_RAW:-}" ]]; then env_args+=("ACFS_RAW=$ACFS_RAW"); fi
    if [[ -n "${ACFS_VERSION:-}" ]]; then env_args+=("ACFS_VERSION=$ACFS_VERSION"); fi
    if [[ -n "${ACFS_REF:-}" ]]; then env_args+=("ACFS_REF=$ACFS_REF"); fi

    command_argv=("$@")
    if [[ ${#command_argv[@]} -gt 0 ]]; then
        case "${command_argv[0]}" in
            env)
                command_argv[0]="$env_bin"
                local env_command_index=1
                while [[ "$env_command_index" -lt "${#command_argv[@]}" ]]; do
                    case "${command_argv[env_command_index]}" in
                        *=*) ((env_command_index += 1)) ;;
                        --) ((env_command_index += 1)); break ;;
                        -*) break ;;
                        *) break ;;
                    esac
                done
                if [[ "$env_command_index" -lt "${#command_argv[@]}" ]]; then
                    case "${command_argv[env_command_index]}" in
                        env) command_argv[env_command_index]="$env_bin" ;;
                        bash) command_argv[env_command_index]="$bash_bin" ;;
                        sh) command_argv[env_command_index]="$sh_bin" ;;
                    esac
                fi
                ;;
            bash) command_argv[0]="$bash_bin" ;;
            sh) command_argv[0]="$sh_bin" ;;
        esac
    fi

    # Already the target user
    current_user="$(acfs_early_resolve_current_user 2>/dev/null || true)"
    if [[ "${current_user:-}" == "$user" ]]; then
        (
            if ! cd "$user_home"; then
                log_error "Unable to enter target home for '$user': $user_home"
                exit 1
            fi
            "$env_bin" "${env_args[@]}" "${command_argv[@]}"
        )
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
    sudo_bin="$(acfs_early_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        # shellcheck disable=SC2016  # $HOME/$@ expand inside sh -c
        "$sudo_bin" -u "$user" "$env_bin" "${env_args[@]}" "$sh_bin" -c 'cd "$HOME" || exit 1; exec "$@"' _ "${command_argv[@]}"
        return $?
    fi

    # Fallbacks (root-only typically)
    # Note: Avoid -l flag to prevent sourcing profiles
    runuser_bin="$(acfs_early_system_binary_path runuser 2>/dev/null || true)"
    if [[ -n "$runuser_bin" ]]; then
        # shellcheck disable=SC2016  # $HOME/$@ expand inside sh -c
        "$runuser_bin" -u "$user" -- "$env_bin" "${env_args[@]}" "$sh_bin" -c 'cd "$HOME" || exit 1; exec "$@"' _ "${command_argv[@]}"
        return $?
    fi

    su_bin="$(acfs_early_system_binary_path su 2>/dev/null || true)"
    if [[ -z "$su_bin" ]]; then
        log_error "Unable to locate sudo, runuser, or su for target-user command"
        return 1
    fi

    # su without - to avoid sourcing login shell profiles
    local env_assignments=""
    local kv=""
    for kv in "${env_args[@]}"; do
        env_assignments+=" $(printf '%q' "$kv")"
    done
    env_assignments="${env_assignments# }"
    local user_home_q
    local env_bin_q
    user_home_q=$(printf '%q' "$user_home")
    env_bin_q=$(printf '%q' "$env_bin")
    "$su_bin" "$user" -c "cd $user_home_q || exit 1; $env_bin_q $env_assignments $(printf '%q ' "${command_argv[@]}")"
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
    local curl_bin=""

    # Use application/vnd.github.raw to get raw file content directly (no base64)
    local content
    curl_bin="$(acfs_early_system_binary_path curl 2>/dev/null || true)"
    if [[ -z "$curl_bin" ]]; then
        log_detail "curl unavailable for GitHub API request"
        return 1
    fi
    content="$("$curl_bin" --connect-timeout 30 --max-time 300 -fsSL \
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

        if [[ "$line" =~ ^[[:space:]]{2}([[:alnum:]_-]+):[[:space:]]*$ ]]; then
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
        atuin bun bv caam cass claude cm dcg gemini_patch mcp_agent_mail ntm ohmyzsh ru rust slb ubs uv zoxide
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

acfs_run_verified_upstream_script_as_target_with_env() {
    if [[ $# -lt 2 ]]; then
        log_error "acfs_run_verified_upstream_script_as_target_with_env requires a tool and runner"
        return 1
    fi

    local tool="$1"
    local runner="$2"
    local runner_env_assignment="${3:-}"
    if [[ $# -ge 3 ]]; then
        shift 3
    else
        set --
    fi

    acfs_load_upstream_checksums

    local url="${ACFS_UPSTREAM_URLS[$tool]:-}"
    local expected_sha256="${ACFS_UPSTREAM_SHA256[$tool]:-}"
    if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then
        log_error "No checksum recorded for upstream installer: $tool"
        return 1
    fi
    if [[ -n "$runner_env_assignment" ]] && [[ ! "$runner_env_assignment" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+$ ]]; then
        log_error "Invalid inline env assignment for upstream installer '$tool': $runner_env_assignment"
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

    if [[ -n "$runner_env_assignment" ]]; then
        printf '%s' "$content" | run_as_target env "$runner_env_assignment" "$runner" -s -- "$@"
    else
        printf '%s' "$content" | run_as_target "$runner" -s -- "$@"
    fi
}

acfs_run_verified_upstream_script_as_target() {
    if [[ $# -lt 2 ]]; then
        log_error "acfs_run_verified_upstream_script_as_target requires a tool and runner"
        return 1
    fi

    local tool="$1"
    local runner="$2"
    if [[ $# -ge 2 ]]; then
        shift 2
    else
        set --
    fi
    acfs_run_verified_upstream_script_as_target_with_env "$tool" "$runner" "" "$@"
}

ensure_root() {
    if [[ $EUID -ne 0 ]]; then
        local sudo_bin=""
        sudo_bin="$(acfs_early_sudo_binary_path 2>/dev/null || true)"
        if [[ -n "$sudo_bin" ]]; then
            SUDO="$sudo_bin"
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
    local chmod_bin=""
    local mkdir_bin=""
    local tee_bin=""
    local -a sudo_cmd=()

    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ -f "$apt_hook" ]]; then
            log_detail "dry-run: would disable needrestart apt hook at $apt_hook"
        fi
        return 0
    fi

    chmod_bin="$(acfs_early_system_binary_path chmod 2>/dev/null || true)"
    mkdir_bin="$(acfs_early_system_binary_path mkdir 2>/dev/null || true)"
    tee_bin="$(acfs_early_system_binary_path tee 2>/dev/null || true)"
    if [[ -z "$chmod_bin" || -z "$mkdir_bin" || -z "$tee_bin" ]]; then
        log_warn "Skipping needrestart apt hook hardening: required coreutils unavailable"
        return 0
    fi
    if [[ $EUID -ne 0 ]]; then
        local sudo_bin=""
        sudo_bin="$(acfs_early_sudo_binary_path 2>/dev/null || true)"
        [[ -n "$sudo_bin" ]] || return 0
        sudo_cmd=("$sudo_bin")
    fi

    # Method 1: Disable the apt hook executable (prevents it from running)
    if [[ -f "$apt_hook" && -x "$apt_hook" ]]; then
        log_detail "Disabling needrestart apt hook to prevent installation hangs"
        "${sudo_cmd[@]}" "$chmod_bin" -x "$apt_hook" 2>/dev/null || true
    fi

    # Method 2: Configure needrestart to auto-restart services without prompting
    if [[ -d "$nr_conf_dir" ]] || "${sudo_cmd[@]}" "$mkdir_bin" -p "$nr_conf_dir" 2>/dev/null; then
        echo '$nrconf{restart} = '\''a'\'';' | "${sudo_cmd[@]}" "$tee_bin" "$nr_conf_dir/50-acfs-noninteractive.conf" >/dev/null 2>&1 || true
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
    # Transient files (SSH control sockets, etc.) may vanish during the
    # recursive walk of a live home directory.  Only fail on non-transient errors.
    local _chown_err=""
    _chown_err=$($SUDO chown -hR "$owner_group" "$resolved" 2>&1) || {
        local _real_err
        _real_err=$(printf '%s\n' "$_chown_err" | grep -v "No such file or directory" || true)
        if [[ -n "$_real_err" ]]; then
            log_error "acfs_chown_tree: chown failed for $resolved"
            return 1
        fi
        log_detail "acfs_chown_tree: transient file warnings during chown (safe to ignore)"
    }
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

# Resolve a user's home directory from NSS when possible.
acfs_home_for_user() {
    local user="${1:-}"
    local expected_home="${2:-}"
    local passwd_entry=""
    local current_user=""
    local current_home=""
    local passwd_home=""

    [[ -n "$user" ]] || return 1
    if [[ -n "$expected_home" ]] && [[ "$expected_home" == /* ]] && [[ "$expected_home" != "/" ]]; then
        expected_home="${expected_home%/}"
    else
        expected_home=""
    fi

    if [[ "$user" == "root" ]]; then
        echo /root
        return 0
    fi

    passwd_entry="$(acfs_early_getent_passwd_entry "$user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
        if [[ -n "$passwd_home" ]] && [[ "$passwd_home" == /* ]] && [[ "$passwd_home" != "/" ]]; then
            echo "${passwd_home%/}"
            return 0
        fi
    fi

    current_user="$(acfs_early_resolve_current_user 2>/dev/null || true)"
    if [[ "$current_user" == "$user" ]] && [[ -n "${HOME:-}" ]] && [[ "${HOME}" == /* ]] && [[ "${HOME}" != "/" ]]; then
        current_home="${HOME%/}"
        if [[ -z "$expected_home" ]] || [[ "$current_home" == "$expected_home" ]]; then
            echo "$current_home"
            return 0
        fi
    fi

    return 1
}
# Set up target-specific paths
# Must be called after ensure_root
init_target_paths() {
    validate_target_user

    # Resolve the target user's actual home directory through NSS/getent first.
    # Inherited TARGET_HOME is a hint only; if it cannot be validated against
    # passwd/root/current-HOME, fail closed instead of operating in a stale home.
    local explicit_target_home_raw="${TARGET_HOME:-}"
    local current_user=""
    local explicit_target_home=""
    local resolved_target_home=""
    if [[ "$explicit_target_home_raw" == /* ]] && [[ "$explicit_target_home_raw" != "/" ]]; then
        explicit_target_home="${explicit_target_home_raw%/}"
        [[ "$explicit_target_home" != "/" ]] || explicit_target_home=""
    fi
    resolved_target_home="$(acfs_home_for_user "$TARGET_USER" "$explicit_target_home" 2>/dev/null || true)"
    if [[ -n "$resolved_target_home" ]]; then
        TARGET_HOME="$resolved_target_home"
    elif [[ -n "$explicit_target_home" ]]; then
        current_user="$(acfs_early_resolve_current_user 2>/dev/null || true)"
        if [[ -n "$current_user" && "$TARGET_USER" == "$current_user" ]]; then
            TARGET_HOME="$explicit_target_home"
        else
            TARGET_HOME=""
        fi
    else
        TARGET_HOME=""
    fi

    if [[ -z "$TARGET_HOME" ]]; then
        log_fatal "Unable to resolve TARGET_HOME for '$TARGET_USER'; export TARGET_HOME explicitly"
    fi

    if [[ -z "$TARGET_HOME" ]] || [[ "$TARGET_HOME" == "/" ]]; then
        log_fatal "Invalid TARGET_HOME: '${TARGET_HOME:-<empty>}'"
    fi
    if [[ "$TARGET_HOME" != /* ]]; then
        log_fatal "TARGET_HOME must be an absolute path (got: $TARGET_HOME)"
    fi

    # Configurable binary install directory (fixes #211).
    # Override via ACFS_BIN_DIR for shared/multi-user machines:
    #   ACFS_BIN_DIR=/usr/local/bin ./install.sh
    ACFS_BIN_DIR="${ACFS_BIN_DIR:-$TARGET_HOME/.local/bin}"
    if [[ -n "$explicit_target_home" ]] && [[ "$explicit_target_home" != "$TARGET_HOME" ]]; then
        case "$ACFS_BIN_DIR" in
            "$explicit_target_home"|"$explicit_target_home"/*)
                ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
                ;;
        esac
    fi
    if [[ -z "$ACFS_BIN_DIR" ]] || [[ "$ACFS_BIN_DIR" == "/" ]] || [[ "$ACFS_BIN_DIR" != /* ]]; then
        log_fatal "ACFS_BIN_DIR must be an absolute path and cannot be '/' (got: ${ACFS_BIN_DIR:-<empty>})"
    fi

    # ACFS directories for target user
    ACFS_HOME="${ACFS_HOME:-$TARGET_HOME/.acfs}"
    if [[ -n "$explicit_target_home" ]] && [[ "$explicit_target_home" != "$TARGET_HOME" ]]; then
        case "$ACFS_HOME" in
            "$explicit_target_home"|"$explicit_target_home"/*)
                ACFS_HOME="$TARGET_HOME/.acfs"
                ;;
        esac
    fi
    ACFS_STATE_FILE="${ACFS_STATE_FILE:-$ACFS_HOME/state.json}"
    if [[ -n "$explicit_target_home" ]] && [[ "$explicit_target_home" != "$TARGET_HOME" ]]; then
        case "$ACFS_STATE_FILE" in
            "$explicit_target_home"|"$explicit_target_home"/*)
                ACFS_STATE_FILE="$ACFS_HOME/state.json"
                ;;
        esac
    fi

    # Basic hardening: refuse to use a symlinked ACFS_HOME when running with
    # elevated privileges (prevents clobbering arbitrary paths via symlink tricks).
    if [[ -e "$ACFS_HOME" ]] && [[ -L "$ACFS_HOME" ]]; then
        log_fatal "Refusing to use ACFS_HOME because it is a symlink: $ACFS_HOME"
    fi

    log_detail "Target user: $TARGET_USER"
    log_detail "Target home: $TARGET_HOME"

    # Export for generated installers (run via subshells).
    export TARGET_USER TARGET_HOME ACFS_HOME ACFS_STATE_FILE ACFS_BIN_DIR

    # Add target user's bin directories to PATH early so that tools installed
    # later (like Claude Code) see the correct PATH and don't warn about it.
    export PATH="$ACFS_BIN_DIR:$TARGET_HOME/.local/bin:$TARGET_HOME/.acfs/bin:$TARGET_HOME/.cargo/bin:$TARGET_HOME/.bun/bin:$TARGET_HOME/.atuin/bin:$TARGET_HOME/go/bin:$PATH"
}

acfs_primary_bin_dir_uses_root() {
    [[ -n "${ACFS_BIN_DIR:-}" ]] || return 1
    [[ -n "${TARGET_HOME:-}" ]] || return 1

    case "$ACFS_BIN_DIR" in
        "$TARGET_HOME"|"$TARGET_HOME"/*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

acfs_ensure_primary_bin_dir() {
    if acfs_primary_bin_dir_uses_root; then
        "$SUDO" mkdir -p "$ACFS_BIN_DIR"
        return $?
    fi

    run_as_target mkdir -p "$ACFS_BIN_DIR"
}

acfs_link_primary_bin_command() {
    local source_path="$1"
    local command_name="$2"
    local dest_path="$ACFS_BIN_DIR/$command_name"

    acfs_ensure_primary_bin_dir || return 1

    if acfs_primary_bin_dir_uses_root; then
        "$SUDO" ln -sf "$source_path" "$dest_path"
        return $?
    fi

    run_as_target ln -sf "$source_path" "$dest_path"
}

acfs_install_executable_into_primary_bin() {
    local src_path="$1"
    local command_name="$2"
    local dest_path="$ACFS_BIN_DIR/$command_name"

    acfs_ensure_primary_bin_dir || return 1

    if acfs_primary_bin_dir_uses_root; then
        "$SUDO" install -m 0755 "$src_path" "$dest_path"
        return $?
    fi

    if [[ $EUID -eq 0 ]]; then
        "$SUDO" install -m 0755 "$src_path" "$dest_path" || return 1
        "$SUDO" chown "$TARGET_USER:$TARGET_USER" "$dest_path"
        return $?
    fi

    run_as_target install -m 0755 "$src_path" "$dest_path"
}

validate_target_user() {
    if [[ -z "${TARGET_USER:-}" ]]; then
        log_fatal "TARGET_USER is empty"
    fi

    # Hard-stop on unsafe usernames (prevents injection into sudoers/paths).
    if [[ ! "$TARGET_USER" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
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

    local VERSION_MAJOR="${version_id%%.*}"
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

    # If the user did NOT explicitly pass --target-ubuntu, check whether this
    # is a fully-patched LTS release.  LTS users (e.g., 24.04) should not be
    # forced to upgrade to a non-LTS target just because the default
    # TARGET_UBUNTU_VERSION is ahead of them.
    if [[ "$TARGET_UBUNTU_VERSION_EXPLICIT" != "true" ]]; then
        local _current_ver="${VERSION_ID:-}"
        # Ubuntu LTS releases have .04 minor versions (e.g., 22.04, 24.04)
        if [[ "$_current_ver" == *.04 ]]; then
            # Check whether all packages are up to date (0 upgradable)
            local _upgradable=0
            if command -v apt-get &>/dev/null; then
                # apt-get update may need root; try non-destructively first
                _upgradable=$(apt list --upgradable 2>/dev/null | grep -c '\[upgradable' || true)
            fi
            if [[ "$_upgradable" -eq 0 ]]; then
                log_detail "Ubuntu $_current_ver LTS is fully patched (0 packages upgradable); skipping auto-upgrade"
                log_detail "  (pass --target-ubuntu=<VER> to force an upgrade)"
                return 0
            fi
        fi
    fi

    # CRITICAL: Ensure jq is installed for state tracking (state.sh depends on it).
    if ! acfs_early_system_binary_path jq &>/dev/null; then
        log_detail "Installing jq for upgrade state tracking..."
        local apt_get_bin=""
        apt_get_bin="$(acfs_early_system_binary_path apt-get 2>/dev/null || true)"
        if [[ -z "$apt_get_bin" ]]; then
            log_warn "apt-get not found; cannot install jq for upgrade state tracking"
        elif [[ $EUID -eq 0 ]]; then
            "$apt_get_bin" update -qq && "$apt_get_bin" install -y jq >/dev/null 2>&1 || true
        else
            local sudo_bin=""
            sudo_bin="$(acfs_early_sudo_binary_path 2>/dev/null || true)"
            if [[ -n "$sudo_bin" ]]; then
                "$sudo_bin" "$apt_get_bin" update -qq && "$sudo_bin" "$apt_get_bin" install -y jq >/dev/null 2>&1 || true
            fi
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
    local had_state_file=false
    local previous_state_file="${ACFS_STATE_FILE:-}"
    if [[ "${ACFS_STATE_FILE+x}" == "x" ]]; then
        had_state_file=true
    fi
    export ACFS_STATE_FILE="$upgrade_state_file"

    # Convert target version string to number for comparison
    # TARGET_UBUNTU_VERSION is "25.10", need 2510
    local target_version_num
    local target_major target_minor
    target_major="${TARGET_UBUNTU_VERSION%%.*}"
    target_minor="${TARGET_UBUNTU_VERSION#*.}"
    target_version_num=$(printf "%d%02d" "$((10#$target_major))" "$((10#$target_minor))")

    # Ensure ubuntu_upgrade.sh uses the requested target (not just its defaults).
    export UBUNTU_TARGET_VERSION="$TARGET_UBUNTU_VERSION"
    export UBUNTU_TARGET_VERSION_NUM="$target_version_num"

    # Check if we're resuming an upgrade after reboot
    local upgrade_stage
    upgrade_stage=$(state_upgrade_get_stage 2>/dev/null || echo "not_started")

    case "$upgrade_stage" in
        initializing|upgrading|awaiting_reboot|resumed|step_complete)
            log_error "Detected Ubuntu upgrade in progress (stage: $upgrade_stage)"
            log_error "Refusing to continue normal installation during an active upgrade."
            log_info "Monitoring:"
            log_info "  - /var/lib/acfs/check_status.sh"
            log_info "  - journalctl -u acfs-upgrade-resume -f"
            log_info "  - tail -f /var/log/acfs/upgrade_resume.log"
            restore_previous_acfs_state_file "$had_state_file" "$previous_state_file"
            return 1
            ;;
        pre_upgrade_reboot)
            # We just rebooted to clear pending package updates
            log_success "Pre-upgrade reboot complete. Continuing with upgrade..."
            # Clear the stage so we proceed normally
            if type -t state_update &>/dev/null; then
                if ! state_update ".ubuntu_upgrade.current_stage = \"not_started\" | .ubuntu_upgrade.enabled = false"; then
                    log_error "Failed to clear pre_upgrade_reboot stage; aborting to prevent stale state."
                    restore_previous_acfs_state_file "$had_state_file" "$previous_state_file"
                    return 1
                fi
            else
                log_error "State tracking is unavailable; cannot continue upgrade safely."
                restore_previous_acfs_state_file "$had_state_file" "$previous_state_file"
                return 1
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
            restore_previous_acfs_state_file "$had_state_file" "$previous_state_file"
            return 1
            ;;
    esac

    # Check if upgrade is needed (using numeric comparison)
    if ubuntu_version_gte "$current_version_num" "$target_version_num"; then
        log_detail "Ubuntu $current_version_str meets target ($TARGET_UBUNTU_VERSION)"
        restore_previous_acfs_state_file "$had_state_file" "$previous_state_file"
        return 0
    fi

    # Ubuntu distribution upgrades require root (do-release-upgrade, systemd units,
    # /var/lib/acfs state). If the installer is being run as a sudo-capable user,
    # abort with clear guidance rather than failing mid-upgrade.
    if [[ $EUID -ne 0 ]]; then
        log_error "Ubuntu auto-upgrade requires running the installer as root"
        log_info "Re-run as root (e.g., run 'sudo -i' then run the install command again), or use --skip-ubuntu-upgrade."
        restore_previous_acfs_state_file "$had_state_file" "$previous_state_file"
        return 1
    fi

    # Calculate upgrade path (function takes target version NUMBER, determines current internally)
    # Returns newline-separated list of version strings to upgrade through
    local upgrade_path
    upgrade_path=$(ubuntu_calculate_upgrade_path "$target_version_num")

    if [[ -z "$upgrade_path" ]]; then
        log_detail "No upgrade path found from $current_version_str to $TARGET_UBUNTU_VERSION"
        restore_previous_acfs_state_file "$had_state_file" "$previous_state_file"
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
                restore_previous_acfs_state_file "$had_state_file" "$previous_state_file"
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
            # Try without sudo first, fall back to sudo for system directories
            local mkdir_bin=""
            mkdir_bin="$(acfs_early_system_binary_path mkdir 2>/dev/null || true)"
            if [[ -n "$mkdir_bin" ]] && ! "$mkdir_bin" -p "${ACFS_RESUME_DIR:-/var/lib/acfs}" 2>/dev/null; then
                local sudo_bin=""
                local chown_bin=""
                local id_bin=""
                sudo_bin="$(acfs_early_sudo_binary_path 2>/dev/null || true)"
                chown_bin="$(acfs_early_system_binary_path chown 2>/dev/null || true)"
                id_bin="$(acfs_early_system_binary_path id 2>/dev/null || true)"
                if [[ $EUID -ne 0 && -n "$sudo_bin" ]]; then
                    "$sudo_bin" "$mkdir_bin" -p "${ACFS_RESUME_DIR:-/var/lib/acfs}"
                    if [[ -n "$chown_bin" && -n "$id_bin" ]]; then
                        "$sudo_bin" "$chown_bin" "$("$id_bin" -u):$("$id_bin" -g)" "${ACFS_RESUME_DIR:-/var/lib/acfs}" 2>/dev/null || true
                    fi
                fi
            fi
            if type -t state_ensure_valid &>/dev/null; then
                state_ensure_valid || true
            fi
            if type -t state_init &>/dev/null; then
                state_load >/dev/null 2>&1 || state_init || true
            fi

            # Set stage so we know to continue after reboot
            if type -t state_update_with_args &>/dev/null; then
                if ! state_update_with_args '
                    .ubuntu_upgrade.enabled = true |
                    .ubuntu_upgrade.current_stage = "pre_upgrade_reboot" |
                    .ubuntu_upgrade.original_version = $current_version |
                    .ubuntu_upgrade.target_version = $target_version
                ' --arg current_version "$current_version_str" --arg target_version "$TARGET_UBUNTU_VERSION"; then
                    log_error "Failed to record upgrade stage; cannot safely auto-reboot."
                    log_info "Please reboot manually and re-run the installer."
                    restore_previous_acfs_state_file "$had_state_file" "$previous_state_file"
                    return 1
                fi
            else
                log_error "State tracking is unavailable; cannot safely auto-reboot."
                log_info "Please reboot manually and re-run the installer."
                restore_previous_acfs_state_file "$had_state_file" "$previous_state_file"
                return 1
            fi

            # Set up resume infrastructure
            local acfs_source_dir=""
            if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -d "$SCRIPT_DIR" ]]; then
                acfs_source_dir="$SCRIPT_DIR"
            elif [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -d "$ACFS_BOOTSTRAP_DIR" ]]; then
                acfs_source_dir="$ACFS_BOOTSTRAP_DIR"
            fi

            if [[ -z "$acfs_source_dir" ]] || ! type -t upgrade_setup_infrastructure &>/dev/null; then
                log_error "Resume infrastructure is unavailable. Cannot safely auto-reboot."
                log_info "Please reboot manually and re-run the installer."
                restore_previous_acfs_state_file "$had_state_file" "$previous_state_file"
                return 1
            fi
            if ! upgrade_setup_infrastructure "$acfs_source_dir" "$@"; then
                log_error "Failed to set up resume infrastructure. Cannot safely reboot."
                log_info "Please reboot manually and re-run the installer."
                restore_previous_acfs_state_file "$had_state_file" "$previous_state_file"
                return 1
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
            restore_previous_acfs_state_file "$had_state_file" "$previous_state_file"
            return 1
        fi
    fi

    # Run preflight checks
    if type -t ubuntu_preflight_checks &>/dev/null; then
        if ! ubuntu_preflight_checks; then
            log_error "Preflight checks failed. Cannot proceed with upgrade."
            log_info "Use --skip-ubuntu-upgrade to bypass (not recommended)"
            restore_previous_acfs_state_file "$had_state_file" "$previous_state_file"
            return 1
        fi
    fi

    # Ensure a state file exists so upgrade tracking can persist progress.
    # (The main install resume prompt/state init happens later, but upgrades
    # need state_update/state_upgrade_* to be able to write immediately.)
    if type -t state_ensure_valid &>/dev/null; then
        if ! state_ensure_valid; then
            log_error "State validation failed. Aborting Ubuntu upgrade."
            restore_previous_acfs_state_file "$had_state_file" "$previous_state_file"
            return 1
        fi
    fi
    if type -t state_load &>/dev/null && type -t state_init &>/dev/null; then
        if ! state_load >/dev/null 2>&1; then
            log_detail "Initializing state file for Ubuntu upgrade tracking..."
            if ! state_init; then
                log_error "Failed to initialize state file. Aborting Ubuntu upgrade."
                restore_previous_acfs_state_file "$had_state_file" "$previous_state_file"
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
            restore_previous_acfs_state_file "$had_state_file" "$previous_state_file"
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
        restore_previous_acfs_state_file "$had_state_file" "$previous_state_file"
        return 0
    fi
}

restore_previous_acfs_state_file() {
    local had_state_file=${1:-false}
    local previous_state_file=${2-}

    if [[ "$had_state_file" == "true" ]]; then
        export ACFS_STATE_FILE="$previous_state_file"
    else
        unset ACFS_STATE_FILE
    fi
}

ensure_base_deps() {
    set_phase "base_deps" "Base Dependencies" 1
    log_step "0/9" "Checking base dependencies..."
    local apt_get_bin=""
    local -a sudo_cmd=()

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

    apt_get_bin="$(acfs_early_system_binary_path apt-get 2>/dev/null || true)"
    if [[ -z "$apt_get_bin" ]]; then
        log_error "apt-get not found; cannot install base dependencies"
        return 1
    fi
    if [[ $EUID -ne 0 ]]; then
        local sudo_bin=""
        sudo_bin="$(acfs_early_sudo_binary_path 2>/dev/null || true)"
        if [[ -z "$sudo_bin" ]]; then
            log_error "sudo not found; cannot install base dependencies"
            return 1
        fi
        sudo_cmd=("$sudo_bin")
    fi

    log_detail "Updating apt package index"
    try_step "Updating apt package index" "${sudo_cmd[@]}" "$apt_get_bin" update -y || return 1

    log_detail "Installing base packages"
    try_step "Installing base packages" "${sudo_cmd[@]}" "$apt_get_bin" install -y curl git ca-certificates unzip tar xz-utils jq build-essential sudo gnupg libssl-dev pkg-config || return 1
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
                if declare -f log_sensitive >/dev/null; then
                    log_sensitive "Generated password for '$TARGET_USER': $user_password"
                    log_sensitive "Save this password! You may need it for sudo access (safe mode)."
                else
                    log_warn "Generated password for '$TARGET_USER': $user_password"
                    log_warn "Save this password! You may need it for sudo access (safe mode)."
                fi
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
                if [[ -s "$dst" ]]; then
                    local last_char
                    last_char=$(tail -c 1 "$dst" | od -An -t u1 | tr -d ' ' 2>/dev/null || true)
                    if [[ "$last_char" != "10" ]]; then
                        echo "" >> "$dst"
                    fi
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

    # Enable lingering user sessions so systemctl --user works on fresh VPS installs
    # where the target user has never had an interactive login (no /run/user/<uid>).
    # This must happen BEFORE the stack phase (Phase 8) attempts systemctl --user.
    if command_exists loginctl; then
        log_detail "Enabling loginctl linger for $TARGET_USER"
        $SUDO loginctl enable-linger "$TARGET_USER" 2>/dev/null || true
    fi
    local target_uid=""
    if target_uid="$(id -u "$TARGET_USER" 2>/dev/null)"; then
        local runtime_dir="/run/user/$target_uid"
        if [[ ! -d "$runtime_dir" ]]; then
            log_detail "Creating XDG_RUNTIME_DIR: $runtime_dir"
            $SUDO mkdir -p "$runtime_dir"
            $SUDO chown "$TARGET_USER:$TARGET_USER" "$runtime_dir"
            $SUDO chmod 700 "$runtime_dir"
        fi
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

    # Create user's bin and .bun directories early - many installers need them
    # This prevents NTM, UBS, CASS, Bun, etc. from creating them as root via sudo
    try_step "Creating bin directory ($ACFS_BIN_DIR)" acfs_ensure_primary_bin_dir || return 1
    try_step "Creating .bun directory" run_as_target mkdir -p "$TARGET_HOME/.bun" || return 1

    log_success "Filesystem setup complete"
}

# ============================================================
# Phase 3: Shell setup (zsh + oh-my-zsh + p10k)
# ============================================================
acfs_get_local_passwd_entry() {
    local user="${1:-}"
    local passwd_line=""
    local passwd_user=""

    [[ -n "$user" ]] || return 1
    [[ -r /etc/passwd ]] || return 1

    while IFS= read -r passwd_line; do
        IFS=: read -r passwd_user _ <<< "$passwd_line"
        if [[ "$passwd_user" == "$user" ]]; then
            echo "$passwd_line"
            return 0
        fi
    done < /etc/passwd

    return 1
}
acfs_is_externally_managed_user() {
    local user="${1:-}"
    local passwd_entry=""
    local local_entry=""

    [[ -n "$user" ]] || return 1
    passwd_entry="$(acfs_early_getent_passwd_entry "$user" 2>/dev/null || true)"
    [[ -n "$passwd_entry" ]] || return 1

    local_entry="$(acfs_get_local_passwd_entry "$user" || true)"
    [[ -z "$local_entry" ]]
}

acfs_external_shell_handoff_configured() {
    local target_home="${1:-}"
    local bashrc_path=""

    [[ -n "$target_home" ]] || return 1
    bashrc_path="$target_home/.bashrc"
    [[ -f "$bashrc_path" ]] || return 1

    awk '
        $0 == "# ACFS externally-managed shell handoff" { marker=1; next }
        marker && $0 ~ /^[[:space:]]*#/ { next }
        marker && index($0, "command -v zsh") && index($0, "ACFS_ZSH_HANDOFF_ACTIVE") { found=1; exit }
        marker && $0 !~ /^[[:space:]]*$/ { marker=0 }
        END { exit(found ? 0 : 1) }
    ' "$bashrc_path" 2>/dev/null
}

acfs_append_external_shell_handoff() {
    local bashrc_path="${1:-}"
    [[ -n "$bashrc_path" ]] || return 1

    if [[ -f "$bashrc_path" ]] && [[ -s "$bashrc_path" ]]; then
        local last_char=""
        last_char=$(tail -c 1 "$bashrc_path" | od -An -t u1 | tr -d ' ' 2>/dev/null || true)
        if [[ "$last_char" != "10" ]]; then
            printf '\n' >> "$bashrc_path"
        fi
    fi

    cat >> "$bashrc_path" << 'EOF'
# ACFS externally-managed shell handoff
if [[ $- == *i* ]] && [[ -t 0 ]] && command -v zsh >/dev/null 2>&1 && [[ -z "${ACFS_ZSH_HANDOFF_ACTIVE:-}" ]]; then
    export ACFS_ZSH_HANDOFF_ACTIVE=1
    exec "$(command -v zsh)" -l
fi
EOF
}

acfs_configure_external_shell_handoff() {
    local target_home="${1:-}"
    local target_user="${2:-}"

    [[ -n "$target_home" ]] || return 1
    [[ -n "$target_user" ]] || return 1

    if acfs_external_shell_handoff_configured "$target_home"; then
        return 0
    fi

    acfs_append_external_shell_handoff "$target_home/.bashrc" || return 1

    $SUDO chown "$target_user:$target_user" "$target_home/.bashrc" 2>/dev/null || true
    return 0
}

profile_path_has_fragment() {
    local file="${1:-}"
    local fragment="${2:-}"

    [[ -n "$file" && -n "$fragment" && -f "$file" ]] || return 1
    awk -v fragment="$fragment" '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*(export[[:space:]]+)?PATH[[:space:]]*=/ && index($0, fragment) { found=1; exit }
        END { exit(found ? 0 : 1) }
    ' "$file" 2>/dev/null
}

profile_path_sed_literal() {
    # This is used in sed's default BRE mode with | as the delimiter.
    # Do not escape literal parentheses: \(...\) is a BRE capture group.
    printf '%s' "$1" | sed 's/[][\\.^$*|]/\\&/g'
}

acfs_zshrc_is_managed_loader() {
    local file="${1:-}"

    [[ -f "$file" ]] || return 1
    awk '
        /^[[:space:]]*$/ { next }
        { lines[++line_count]=$0 }
        END {
            if (line_count == 2 &&
                lines[1] ~ /^# ACFS loader/ &&
                lines[2] == "source \"$HOME/.acfs/zsh/acfs.zshrc\"") {
                exit 0
            }
            exit 1
        }
    ' "$file" 2>/dev/null
}

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
    if ! binary_installed "zsh"; then
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
    elif [[ -d "/root/.oh-my-zsh" ]] && [[ "$EUID" -eq 0 ]]; then
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
    if [[ -f "$user_zshrc" ]] && ! acfs_zshrc_is_managed_loader "$user_zshrc"; then
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
EOF
    try_step "Setting .zshrc ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$user_zshrc" || return 1

    # Ensure core user-installed tool paths are present for login shells.
    # This prevents warnings from tools like Claude's installer that check PATH
    local user_profile="$TARGET_HOME/.profile"
    local user_zprofile="$TARGET_HOME/.zprofile"
    local legacy_profile_path_line='export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"'
    # shellcheck disable=SC2016  # We want $HOME/$PATH to expand when .profile is sourced, not during install.
    local profile_path_line='export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"'
    if [[ ! -f "$user_profile" ]]; then
        # Create new .profile
        {
            echo "# ~/.profile: executed by bash for login shells"
            echo ""
            echo "# User binary paths"
            echo "$profile_path_line"
        } > "$user_profile"
        $SUDO chown "$TARGET_USER:$TARGET_USER" "$user_profile"
    elif grep -Fxq "$legacy_profile_path_line" "$user_profile" 2>/dev/null; then
        sed -i "s|^$(profile_path_sed_literal "$legacy_profile_path_line")$|$profile_path_line|" "$user_profile"
    elif ! profile_path_has_fragment "$user_profile" '.local/bin' || \
         ! profile_path_has_fragment "$user_profile" '.atuin/bin'; then
        # Append to existing .profile
        {
            echo ""
            echo "# Added by ACFS - user binary paths"
            echo "$profile_path_line"
        } >> "$user_profile"
    fi
    # Ensure correct ownership (handles edge case where file was created by root)
    [[ -f "$user_profile" ]] && $SUDO chown "$TARGET_USER:$TARGET_USER" "$user_profile" 2>/dev/null || true

    # zsh login shells do not read ~/.profile, so mirror the login PATH there.
    if [[ ! -f "$user_zprofile" ]]; then
        {
            echo "# ~/.zprofile: executed by zsh for login shells"
            echo ""
            echo "# User binary paths"
            echo "$profile_path_line"
        } > "$user_zprofile"
        $SUDO chown "$TARGET_USER:$TARGET_USER" "$user_zprofile"
    elif grep -Fxq "$legacy_profile_path_line" "$user_zprofile" 2>/dev/null; then
        sed -i "s|^$(profile_path_sed_literal "$legacy_profile_path_line")$|$profile_path_line|" "$user_zprofile"
    elif ! profile_path_has_fragment "$user_zprofile" '.local/bin' || \
         ! profile_path_has_fragment "$user_zprofile" '.atuin/bin'; then
        {
            echo ""
            echo "# Added by ACFS - user binary paths"
            echo "$profile_path_line"
        } >> "$user_zprofile"
    fi
    [[ -f "$user_zprofile" ]] && $SUDO chown "$TARGET_USER:$TARGET_USER" "$user_zprofile" 2>/dev/null || true

    # Set zsh as default shell for target user. Some environments expose user
    # entries via NSS but do not allow local chsh updates, so fall back to an
    # interactive bash-to-zsh handoff there.
    local current_shell
    local current_shell_entry=""
    local zsh_path
    local chsh_path=""
    current_shell_entry="$(acfs_early_getent_passwd_entry "$TARGET_USER" 2>/dev/null || true)"
    current_shell=""
    if [[ -n "$current_shell_entry" ]]; then
        IFS=: read -r _ _ _ _ _ _ current_shell <<< "$current_shell_entry"
    fi
    zsh_path="$(acfs_early_system_binary_path zsh 2>/dev/null || true)"
    chsh_path="$(acfs_early_system_binary_path chsh 2>/dev/null || true)"
    if [[ -n "$zsh_path" ]] && [[ "$current_shell" != *"zsh"* ]]; then
        if acfs_is_externally_managed_user "$TARGET_USER"; then
            log_warn "Shell for $TARGET_USER is managed outside /etc/passwd; installing a bash-to-zsh handoff instead of using chsh"
            try_step "Configuring bash-to-zsh handoff" acfs_configure_external_shell_handoff "$TARGET_HOME" "$TARGET_USER" || return 1
        elif [[ -n "$chsh_path" ]]; then
            log_detail "Setting zsh as default shell for $TARGET_USER"
            try_step "Setting zsh as default shell" $SUDO "$chsh_path" -s "$zsh_path" "$TARGET_USER" || true
        else
            log_warn "Could not locate chsh; leaving the default shell unchanged for $TARGET_USER"
        fi
    fi

    log_success "Shell setup complete"
}

# ============================================================
# Phase 4: CLI tools
# ============================================================
install_github_cli() {
    # GitHub CLI (gh) is a core tool for ACFS workflows (PRs, auth, issues).
    # Prefer distro apt; fall back to the official GitHub CLI apt repo if needed.

    if binary_installed "gh"; then
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

    # tools phase 5: lazygit, lazydocker — bug #146 audit follow-up
    if acfs_use_generated_category "tools"; then
        log_detail "Using generated installers for tools (phase 5)"
        acfs_run_generated_category_phase "tools" "5" || return 1
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
    if binary_installed "gum"; then
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
    try_step "Installing required apt packages" $SUDO apt-get install -y ripgrep tmux fzf direnv jq git-lfs lsof dnsutils netcat-openbsd strace rsync zstd || return 1

    # GitHub CLI (gh)
    local gh_bin=""
    gh_bin="$(binary_path gh 2>/dev/null || true)"
    if [[ -n "$gh_bin" ]]; then
        log_detail "gh already installed ($("$gh_bin" --version 2>/dev/null | head -1 || echo 'gh'))"
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

    # Install optional apt packages - batch install for speed (14→1 apt-get calls)
    log_detail "Installing optional apt packages"
    local optional_pkgs=(lsd eza bat fd-find btop dust neovim htop tree ncdu httpie entr mtr pv docker.io docker-compose-plugin cosign)
    # First attempt: batch install all at once (fastest path)
    if ! $SUDO apt-get install -y "${optional_pkgs[@]}" >/dev/null 2>&1; then
        # Fallback: some packages failed, install individually to get what we can
        log_detail "Batch install failed, trying packages individually"
        for pkg in "${optional_pkgs[@]}"; do
            $SUDO apt-get install -y "$pkg" >/dev/null 2>&1 || log_detail "$pkg not available (optional)"
        done
    fi

    # Robust lazygit install (apt or binary fallback)
    if ! binary_installed "lazygit"; then
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
                local mktemp_bin=""
                mktemp_bin="$(acfs_early_system_binary_path mktemp 2>/dev/null || true)"
                if [[ -n "$mktemp_bin" ]]; then
                    lg_tmp="$("$mktemp_bin" "${TMPDIR:-/tmp}/acfs-lazygit.XXXXXX" 2>/dev/null)" || lg_tmp=""
                fi
                if [[ -n "$lg_tmp" ]]; then
                    if acfs_download_file_and_verify_sha256 "$lg_url" "$lg_tmp" "$lg_sha256" "lazygit ${lg_ver} (${arch})"; then
                        if $SUDO tar -xzf "$lg_tmp" -C /usr/local/bin --no-same-owner --no-same-permissions lazygit 2>/dev/null; then
                            $SUDO chmod 0755 /usr/local/bin/lazygit 2>/dev/null || true
                            if binary_installed "lazygit"; then
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
    if ! binary_installed "lazydocker"; then
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
            local mktemp_bin=""
            mktemp_bin="$(acfs_early_system_binary_path mktemp 2>/dev/null || true)"
            if [[ -n "$mktemp_bin" ]]; then
                ld_tmp="$("$mktemp_bin" "${TMPDIR:-/tmp}/acfs-lazydocker.XXXXXX" 2>/dev/null)" || ld_tmp=""
            fi
            if [[ -n "$ld_tmp" ]]; then
                if acfs_download_file_and_verify_sha256 "$ld_url" "$ld_tmp" "$ld_sha256" "lazydocker ${ld_ver} (${arch})"; then
                    if $SUDO tar -xzf "$ld_tmp" -C /usr/local/bin --no-same-owner --no-same-permissions lazydocker 2>/dev/null; then
                        $SUDO chmod 0755 /usr/local/bin/lazydocker 2>/dev/null || true
                        if binary_installed "lazydocker"; then
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
_target_has_nvm_node() {
    local node_path=""

    while IFS= read -r node_path; do
        [[ -x "$node_path" ]] && return 0
    done < <(compgen -G "$TARGET_HOME/.nvm/versions/node/*/bin/node")

    return 1
}

_target_latest_nvm_node_bin() {
    local node_path=""

    while IFS= read -r node_path; do
        if [[ -x "$node_path" ]]; then
            printf '%s\n' "${node_path%/node}"
            return 0
        fi
    done < <(compgen -G "$TARGET_HOME/.nvm/versions/node/*/bin/node" | sort -Vr)

    return 1
}

_ensure_target_nvm_node() {
    if _target_has_nvm_node; then
        log_detail "nvm + Node.js already installed"
        return 0
    fi

    log_detail "Installing nvm + latest Node.js for $TARGET_USER"
    try_step "Installing nvm" acfs_run_verified_upstream_script_as_target "nvm" "bash" || return 1
    try_step "Installing Node.js via nvm" run_as_target bash -c '
        set -euo pipefail
        export NVM_DIR="$HOME/.nvm"
        if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
            echo "nvm.sh not found at $NVM_DIR/nvm.sh" >&2
            exit 1
        fi
        . "$NVM_DIR/nvm.sh"
        nvm install node
        nvm alias default node
    ' || return 1

    _target_has_nvm_node
}

install_languages_legacy_lang() {
    # Bun (install as target user)
    local bun_bin="$TARGET_HOME/.bun/bin/bun"
    if [[ ! -x "$bun_bin" ]]; then
        log_detail "Installing Bun for $TARGET_USER"
        try_step "Installing Bun" acfs_run_verified_upstream_script_as_target "bun" "bash" || return 1
    fi

    # NOTE: node→bun symlink REMOVED (bug #145). The symlink shadowed real Node.js
    # from nvm and broke TypeScript builds. Bun already handles #!/usr/bin/env node
    # shebangs natively when running .js files via bun, so the symlink was unnecessary.

    # Rust nightly (install as target user)
    # We use nightly for latest features and to install tools like dust/lsd
    local cargo_bin="$TARGET_HOME/.cargo/bin/cargo"
    if [[ ! -x "$cargo_bin" ]]; then
        log_detail "Installing Rust nightly for $TARGET_USER"
        try_step "Installing Rust nightly" acfs_run_verified_upstream_script_as_target "rust" "sh" -y --default-toolchain nightly || return 1
    fi

    # Go (system-wide)
    if ! binary_installed "go"; then
        log_detail "Installing Go"
        try_step "Installing Go" $SUDO apt-get install -y golang-go || return 1
    fi

    # uv (install as target user)
    if binary_installed "uv"; then
        log_detail "uv already installed"
    else
        log_detail "Installing uv for $TARGET_USER"
        try_step "Installing uv" acfs_run_verified_upstream_script_as_target "uv" "sh" || return 1
    fi

    _ensure_target_nvm_node || return 1
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
    if [[ -d "$TARGET_HOME/.atuin" ]] || binary_installed "atuin"; then
        log_detail "Atuin already installed"
    else
        log_detail "Installing Atuin for $TARGET_USER"
        try_step "Installing Atuin" acfs_run_verified_upstream_script_as_target "atuin" "sh" "--non-interactive" || return 1
    fi

    if [[ -x "$TARGET_HOME/.atuin/bin/atuin" ]]; then
        if run_as_target bash -c '
            set -euo pipefail
            preferred_src="$HOME/.atuin/bin/atuin"
            primary_dir="'"$ACFS_BIN_DIR"'"
            fallback_dir="$HOME/.local/bin"
            mkdir -p "$primary_dir"
            ln -sf "$preferred_src" "$primary_dir/atuin"
            if [[ "$fallback_dir" != "$primary_dir" ]]; then
                mkdir -p "$fallback_dir"
                ln -sf "$preferred_src" "$fallback_dir/atuin"
            fi
        ' >/dev/null 2>&1; then
            log_detail "Atuin shim normalized in $ACFS_BIN_DIR and ~/.local/bin"
        else
            log_detail "Skipping Atuin shim normalization for $ACFS_BIN_DIR"
        fi
    fi

    # Zoxide - prefer apt to avoid GitHub API rate limits in CI
    # Check multiple possible locations
    if binary_installed "zoxide"; then
        log_detail "Zoxide already installed"
    else
        log_detail "Installing Zoxide for $TARGET_USER"
        # Prefer apt (avoids GitHub API rate limits), fall back to upstream script
        if apt-cache show zoxide &>/dev/null; then
            try_step "Installing Zoxide (apt)" $SUDO apt-get install -y zoxide || {
                log_detail "apt install failed, falling back to upstream script"
                try_step "Installing Zoxide (upstream)" acfs_run_verified_upstream_script_as_target "zoxide" "sh" || return 1
            }
        else
            try_step "Installing Zoxide" acfs_run_verified_upstream_script_as_target "zoxide" "sh" || return 1
        fi
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
        local claude_bin_local="$ACFS_BIN_DIR/claude"
        if [[ ! -x "$claude_bin_local" ]]; then
            acfs_ensure_primary_bin_dir 2>/dev/null || true

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
                try_step "Linking Claude Code into $ACFS_BIN_DIR" acfs_link_primary_bin_command "$claude_candidate" "claude" || true
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
    local claude_bin_local="$ACFS_BIN_DIR/claude"
    local claude_bin_bun="$TARGET_HOME/.bun/bin/claude"
    if [[ -x "$claude_bin_local" ]]; then
        log_detail "Claude Code already installed ($claude_bin_local)"
    elif [[ -x "$claude_bin_bun" ]]; then
        log_detail "Claude Code already installed ($claude_bin_bun)"
    else
        acfs_ensure_primary_bin_dir 2>/dev/null || true

        log_detail "Installing Claude Code (native) for $TARGET_USER"
        try_step "Installing Claude Code (native)" acfs_run_verified_upstream_script_as_target "claude" "bash" latest || true

        if [[ ! -x "$claude_bin_local" && ! -x "$claude_bin_bun" ]]; then
            log_detail "Claude Code not found in standard paths; attempting bun install"
            try_step "Installing Claude Code (bun)" run_as_target "$bun_bin" install -g --trust @anthropic-ai/claude-code@latest || true
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
                try_step "Linking Claude Code into $ACFS_BIN_DIR" acfs_link_primary_bin_command "$claude_candidate" "claude" || true
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
        acfs_ensure_primary_bin_dir 2>/dev/null || true
        try_step "Linking Claude Code into $ACFS_BIN_DIR" acfs_link_primary_bin_command "$claude_bin_bun" "claude" || true
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
    local codex_bin_local="$ACFS_BIN_DIR/codex"
    if [[ -x "$TARGET_HOME/.bun/bin/codex" ]] && [[ ! -x "$codex_bin_local" ]]; then
        local codex_wrapper_tmp=""
        codex_wrapper_tmp="$(mktemp "${TMPDIR:-/tmp}/acfs-codex-wrapper.XXXXXX")" || true
        if [[ -n "$codex_wrapper_tmp" ]]; then
            printf '%s\n' '#!/bin/bash' "exec \"$TARGET_HOME/.bun/bin/bun\" \"$TARGET_HOME/.bun/bin/codex\" \"\$@\"" > "$codex_wrapper_tmp"
            try_step "Creating Codex bun wrapper" acfs_install_executable_into_primary_bin "$codex_wrapper_tmp" "codex" || true
            rm -f "$codex_wrapper_tmp" 2>/dev/null || true
        fi
    fi

    # Gemini CLI (install as target user)
    log_detail "Installing Gemini CLI for $TARGET_USER"
    try_step "Installing Gemini CLI" run_as_target "$bun_bin" install -g --trust @google/gemini-cli@latest || true

    # Create wrapper script that uses bun as runtime (avoids node PATH issues)
    local gemini_bin_local="$ACFS_BIN_DIR/gemini"
    if [[ -x "$TARGET_HOME/.bun/bin/gemini" ]] && [[ ! -x "$gemini_bin_local" ]]; then
        local gemini_wrapper_tmp=""
        gemini_wrapper_tmp="$(mktemp "${TMPDIR:-/tmp}/acfs-gemini-wrapper.XXXXXX")" || true
        if [[ -n "$gemini_wrapper_tmp" ]]; then
            printf '%s\n' '#!/bin/bash' "exec \"$TARGET_HOME/.bun/bin/bun\" \"$TARGET_HOME/.bun/bin/gemini\" \"\$@\"" > "$gemini_wrapper_tmp"
            try_step "Creating Gemini bun wrapper" acfs_install_executable_into_primary_bin "$gemini_wrapper_tmp" "gemini" || true
            rm -f "$gemini_wrapper_tmp" 2>/dev/null || true
        fi
    fi

    # Apply Gemini CLI patches (EBADF crash fix, rate-limit retry, quota retry)
    if [[ -x "$TARGET_HOME/.bun/bin/gemini" ]]; then
        log_detail "Applying Gemini CLI patches (EBADF, retry, quota)"
        if _ensure_target_nvm_node; then
            local gemini_nvm_bin=""
            if gemini_nvm_bin="$(_target_latest_nvm_node_bin)"; then
                try_step "Patching Gemini CLI" \
                    acfs_run_verified_upstream_script_as_target_with_env \
                    "gemini_patch" "bash" "PATH=$gemini_nvm_bin:$PATH" || \
                    log_warn "Gemini CLI patches were not applied (continuing)"
            else
                log_warn "Skipping Gemini CLI patch because no nvm Node.js bin was found after install"
            fi
        else
            log_warn "Skipping Gemini CLI patch because Node.js via nvm could not be prepared"
            log_warn "Re-run phase 5 or install nvm manually, then re-run the Gemini patch"
        fi
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
    elif psql_bin="$(binary_path psql 2>/dev/null || true)" && [[ -n "$psql_bin" ]]; then
        log_detail "PostgreSQL already installed ($("$psql_bin" --version 2>/dev/null | head -1 || echo 'psql'))"
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
                local runuser_bin=""
                local postgres_sudo_bin=""
                local psql_bin=""
                local createuser_bin=""
                local createdb_bin=""
                local grep_bin=""
                local -a postgres_runner=()
                runuser_bin="$(acfs_early_system_binary_path runuser 2>/dev/null || true)"
                postgres_sudo_bin="$(acfs_early_sudo_binary_path 2>/dev/null || true)"
                psql_bin="$(acfs_early_system_binary_path psql 2>/dev/null || true)"
                createuser_bin="$(acfs_early_system_binary_path createuser 2>/dev/null || true)"
                createdb_bin="$(acfs_early_system_binary_path createdb 2>/dev/null || true)"
                grep_bin="$(acfs_early_system_binary_path grep 2>/dev/null || true)"
                if [[ $EUID -eq 0 && -n "$runuser_bin" ]]; then
                    postgres_runner=("$runuser_bin" -u postgres --)
                elif [[ -n "$postgres_sudo_bin" ]]; then
                    postgres_runner=("$postgres_sudo_bin" -u postgres -H)
                fi
                if [[ ${#postgres_runner[@]} -gt 0 && -n "$psql_bin" && -n "$createuser_bin" && -n "$createdb_bin" && -n "$grep_bin" ]]; then
                    "${postgres_runner[@]}" "$psql_bin" -tAc "SELECT 1 FROM pg_roles WHERE rolname='$TARGET_USER'" | "$grep_bin" -q 1 || \
                        "${postgres_runner[@]}" "$createuser_bin" -s "$TARGET_USER" 2>/dev/null || true
                    "${postgres_runner[@]}" "$psql_bin" -tAc "SELECT 1 FROM pg_database WHERE datname='$TARGET_USER'" | "$grep_bin" -q 1 || \
                        "${postgres_runner[@]}" "$createdb_bin" "$TARGET_USER" 2>/dev/null || true
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
    elif vault_bin="$(binary_path vault 2>/dev/null || true)" && [[ -n "$vault_bin" ]]; then
        log_detail "Vault already installed ($("$vault_bin" --version 2>/dev/null | head -1 || echo 'vault'))"
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

cleanup_supabase_cli_release_temp() {
    local tmp_dir="${1:-}"
    local tmp_tgz="${2:-}"
    local tmp_checksums="${3:-}"

    [[ -n "$tmp_tgz" ]] && rm -f -- "$tmp_tgz" 2>/dev/null || true
    [[ -n "$tmp_checksums" ]] && rm -f -- "$tmp_checksums" 2>/dev/null || true

    if [[ -n "$tmp_dir" && -d "$tmp_dir" ]]; then
        case "$tmp_dir" in
            "${TMPDIR:-/tmp}"/acfs-supabase.*) rm -rf -- "$tmp_dir" 2>/dev/null || true ;;
            *) log_warn "Supabase CLI: refusing to clean unexpected temp dir: $tmp_dir" ;;
        esac
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
    local mktemp_bin=""
    mktemp_bin="$(acfs_early_system_binary_path mktemp 2>/dev/null || true)"
    if [[ -n "$mktemp_bin" ]]; then
        tmp_dir="$("$mktemp_bin" -d "${TMPDIR:-/tmp}/acfs-supabase.XXXXXX" 2>/dev/null)" || tmp_dir=""
        tmp_tgz="$("$mktemp_bin" "${TMPDIR:-/tmp}/acfs-supabase.tgz.XXXXXX" 2>/dev/null)" || tmp_tgz=""
        tmp_checksums="$("$mktemp_bin" "${TMPDIR:-/tmp}/acfs-supabase.sha.XXXXXX" 2>/dev/null)" || tmp_checksums=""
    fi

    if [[ -z "$tmp_dir" ]] || [[ -z "$tmp_tgz" ]] || [[ -z "$tmp_checksums" ]]; then
        log_error "Supabase CLI: failed to create temp files"
        cleanup_supabase_cli_release_temp "$tmp_dir" "$tmp_tgz" "$tmp_checksums"
        return 1
    fi

    if ! acfs_curl -o "$tmp_tgz" "${base_url}/${tarball}" 2>/dev/null; then
        log_error "Supabase CLI: failed to download ${tarball}"
        cleanup_supabase_cli_release_temp "$tmp_dir" "$tmp_tgz" "$tmp_checksums"
        return 1
    fi
    if ! acfs_curl -o "$tmp_checksums" "${base_url}/${checksums}" 2>/dev/null; then
        log_error "Supabase CLI: failed to download checksums"
        cleanup_supabase_cli_release_temp "$tmp_dir" "$tmp_tgz" "$tmp_checksums"
        return 1
    fi

    local expected_sha=""
    expected_sha="$(grep -E " ${tarball}\$" "$tmp_checksums" 2>/dev/null | awk '{print $1}' | head -n1)" || true
    if [[ -z "$expected_sha" ]]; then
        log_error "Supabase CLI: checksum entry not found for ${tarball}"
        cleanup_supabase_cli_release_temp "$tmp_dir" "$tmp_tgz" "$tmp_checksums"
        return 1
    fi

    local actual_sha=""
    actual_sha="$(acfs_calculate_file_sha256 "$tmp_tgz" 2>/dev/null)" || actual_sha=""
    if [[ -z "$actual_sha" ]] || [[ "$actual_sha" != "$expected_sha" ]]; then
        log_error "Supabase CLI: checksum mismatch"
        log_error "  Expected: $expected_sha"
        log_error "  Actual:   ${actual_sha:-<missing>}"
        cleanup_supabase_cli_release_temp "$tmp_dir" "$tmp_tgz" "$tmp_checksums"
        return 1
    fi

    # Extract only the binary if possible (keeps tmp dir clean).
    if ! tar -xzf "$tmp_tgz" -C "$tmp_dir" supabase 2>/dev/null; then
        tar -xzf "$tmp_tgz" -C "$tmp_dir" 2>/dev/null || {
            log_error "Supabase CLI: failed to extract tarball"
            cleanup_supabase_cli_release_temp "$tmp_dir" "$tmp_tgz" "$tmp_checksums"
            return 1
        }
    fi

    local extracted_bin="$tmp_dir/supabase"
    if [[ ! -f "$extracted_bin" ]]; then
        extracted_bin="$(find "$tmp_dir" -maxdepth 2 -type f -name supabase -print -quit 2>/dev/null || true)"
    fi
    if [[ -z "$extracted_bin" ]] || [[ ! -f "$extracted_bin" ]]; then
        log_error "Supabase CLI: binary not found after extract"
        cleanup_supabase_cli_release_temp "$tmp_dir" "$tmp_tgz" "$tmp_checksums"
        return 1
    fi

    chmod 755 "$tmp_dir" 2>/dev/null || true
    chmod 755 "$extracted_bin" 2>/dev/null || true

    acfs_ensure_primary_bin_dir 2>/dev/null || true
    if ! acfs_install_executable_into_primary_bin "$extracted_bin" "supabase"; then
        log_error "Supabase CLI: failed to install into $ACFS_BIN_DIR"
        cleanup_supabase_cli_release_temp "$tmp_dir" "$tmp_tgz" "$tmp_checksums"
        return 1
    fi
    if ! run_as_target "$ACFS_BIN_DIR/supabase" --version >/dev/null 2>&1; then
        log_error "Supabase CLI: installed but failed to run"
        cleanup_supabase_cli_release_temp "$tmp_dir" "$tmp_tgz" "$tmp_checksums"
        return 1
    fi

    cleanup_supabase_cli_release_temp "$tmp_dir" "$tmp_tgz" "$tmp_checksums"

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
                    if [[ -x "$ACFS_BIN_DIR/supabase" ]] || [[ -x "$TARGET_HOME/.bun/bin/supabase" ]]; then
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
                        # Create a bun-based shim in ACFS_BIN_DIR for wrangler (issue #152).
                        # wrangler installed via bun may fail at runtime if node is missing.
                        # The shim uses `bun x` to run wrangler, avoiding the node dependency.
                        if [[ "$cli" == "wrangler" ]] && ! command -v node &>/dev/null; then
                            local shim_dir="$ACFS_BIN_DIR"
                            local wrangler_wrapper_tmp=""
                            acfs_ensure_primary_bin_dir 2>/dev/null || true
                            if [[ ! -f "$shim_dir/wrangler" ]] || grep -q 'bun x wrangler' "$shim_dir/wrangler" 2>/dev/null; then
                                wrangler_wrapper_tmp="$(mktemp "${TMPDIR:-/tmp}/acfs-wrangler-wrapper.XXXXXX")" || true
                                if [[ -n "$wrangler_wrapper_tmp" ]]; then
                                    cat > "$wrangler_wrapper_tmp" <<WRANGLER_SHIM
#!/usr/bin/env bash
# Wrangler shim: uses bun to run wrangler when node is not available.
# Created by ACFS installer (issue #152).
exec "$TARGET_HOME/.bun/bin/bun" x wrangler@latest "\$@"
WRANGLER_SHIM
                                    if acfs_install_executable_into_primary_bin "$wrangler_wrapper_tmp" "wrangler"; then
                                        log_detail "Created bun-based wrangler shim at $shim_dir/wrangler (node not found)"
                                    fi
                                    rm -f "$wrangler_wrapper_tmp" 2>/dev/null || true
                                fi
                            fi
                        fi
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
                    if [[ -x "$ACFS_BIN_DIR/supabase" ]] || [[ -x "$TARGET_HOME/.bun/bin/supabase" ]]; then
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

# Resolve binaries only from target-owned or stable system locations.
# Do not trust arbitrary inherited PATH entries here: they can point at tools from
# the caller's shell instead of the target installation we are managing.
binary_path() {
    local name="$1"
    local primary_bin="${ACFS_BIN_DIR:-$TARGET_HOME/.local/bin}"
    local candidate=""

    for candidate in \
        "$primary_bin/$name" \
        "$TARGET_HOME/.local/bin/$name" \
        "$TARGET_HOME/.acfs/bin/$name" \
        "$TARGET_HOME/.cargo/bin/$name" \
        "$TARGET_HOME/.bun/bin/$name" \
        "$TARGET_HOME/.atuin/bin/$name" \
        "$TARGET_HOME/go/bin/$name" \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/snap/bin/$name"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

binary_installed() {
    local path=""
    path="$(binary_path "$1" 2>/dev/null || true)"
    [[ -n "$path" ]]
}

install_stack_phase() {
    set_phase "stack" "Dicklesworthstone Stack"
    log_step "8/9" "Installing Dicklesworthstone stack..."

    # Install utils.* modules (category: tools, phase: 9) — bug #146 fix
    if acfs_use_generated_category "tools"; then
        log_detail "Using generated installers for tools (phase 9)"
        acfs_run_generated_category_phase "tools" "9" || return 1
    fi

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
            # Write config via tee to ensure proper target user ownership (bd-2od5.2.4)
            # Using tee avoids redirect-as-root issue with heredoc + run_as_target
            # Config format fixed for proper [models] section (bd-2od5.2.5)
            if run_as_target tee "$ntm_config_file" > /dev/null << 'NTM_CONFIG_EOF'
# NTM Configuration - created by ACFS
# Updated model defaults for ChatGPT Pro and Gemini accounts

# Base directory for projects (matches ACFS workspace_root)
projects_base = "/data/projects"

[models]
# Default models when no specifier given
default_claude = "claude-opus-4-7"
default_codex = "gpt-5.5-codex"
default_gemini = "gemini-3-pro-preview"

[agents]
# Override gemini command to set TERM=xterm-256color (issue #178).
# When TERM=tmux-256color (the tmux default-terminal), a node-pty bug
# in gemini-cli causes SIGHUP on all shell tool invocations.
# Scoping the override here keeps tmux and other panes on tmux-256color.
gemini = "TERM=xterm-256color gemini{{if .Model}} --model {{shellQuote .Model}}{{end}} --yolo"
NTM_CONFIG_EOF
            then
                log_success "NTM config created with current model defaults"
            else
                log_warn "Failed to create NTM config"
            fi
        else
            log_detail "NTM config already exists, skipping"
        fi

        # Install NTM command palette (bd-2od5.2.2)
        # Provides useful prompts for ntm palette command
        local ntm_palette_dst="$ntm_config_dir/command_palette.md"
        if [[ ! -f "$ntm_palette_dst" ]]; then
            log_detail "Installing NTM command palette"
            # Ensure config dir exists (install_asset doesn't create parent dirs)
            run_as_target mkdir -p "$ntm_config_dir" 2>/dev/null || true
            # Use install_asset for consistency with other assets (works with curl|bash bootstrap)
            if install_asset "acfs/onboard/docs/ntm/command_palette.md" "$ntm_palette_dst"; then
                # Fix ownership for target user
                if [[ -n "${TARGET_USER:-}" ]] && [[ "$(id -u)" -eq 0 ]]; then
                    chown "${TARGET_USER}:${TARGET_USER}" "$ntm_palette_dst" 2>/dev/null || true
                fi
                log_success "NTM command palette installed"
            else
                log_warn "Failed to install NTM command palette (asset not found)"
            fi
        else
            log_detail "NTM command palette already exists, skipping"
        fi
    fi

    # MCP Agent Mail
    local am_cli_path="$TARGET_HOME/.local/bin/am"
    if binary_installed "mcp-agent-mail" || [[ -x "$am_cli_path" ]] || [[ -d "$TARGET_HOME/mcp_agent_mail" ]]; then
        log_detail "MCP Agent Mail already installed; ensuring managed service"
    else
        log_detail "Installing MCP Agent Mail"
    fi
    local tool="mcp_agent_mail"
    local target_dir="$TARGET_HOME/mcp_agent_mail"
    local am_service_ready=false
    if run_as_target bash -c 'set -euo pipefail
        export PATH="${ACFS_BIN_DIR:-$HOME/.local/bin}:$HOME/.local/bin:$HOME/.acfs/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$HOME/go/bin:/usr/local/bin:/usr/bin:/bin:/snap/bin"
        resolve_target_am() {
            local primary_am="${ACFS_BIN_DIR:-$HOME/.local/bin}/am"
            local candidate=""

            for candidate in \
                "$HOME/mcp_agent_mail/am" \
                "$primary_am" \
                "$HOME/.local/bin/am" \
                "$HOME/.acfs/bin/am" \
                "$HOME/.cargo/bin/am" \
                "$HOME/.bun/bin/am" \
                "$HOME/.atuin/bin/am" \
                "$HOME/go/bin/am"; do
                if [[ -x "$candidate" ]]; then
                    printf "%s\n" "$candidate"
                    return 0
                fi
            done

            return 1
        }
        am_bin="$(resolve_target_am 2>/dev/null || true)"
        [[ -n "$am_bin" ]] || exit 1
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
        curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1
        readiness_body="$(curl -fsS --max-time 10 http://127.0.0.1:8765/health 2>/dev/null)"
        printf "%s\n" "$readiness_body" | grep -Eq "\"status\"[[:space:]]*:[[:space:]]*\"ready\""
    '; then
        log_success "MCP Agent Mail service already running on http://127.0.0.1:8765"
        am_service_ready=true
    fi

    if [[ "$am_service_ready" != "true" ]] && acfs_load_upstream_checksums; then
        local url="${ACFS_UPSTREAM_URLS[$tool]:-}"
        local expected_sha256="${ACFS_UPSTREAM_SHA256[$tool]:-}"

        if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then
            log_error "MCP Agent Mail: missing installer URL/checksum"
        else
            ACFS_TMP_INSTALL="$(mktemp "${TMPDIR:-/tmp}/acfs-install-${tool}.XXXXXX" 2>/dev/null)" || ACFS_TMP_INSTALL=""

            if [[ -n "$ACFS_TMP_INSTALL" ]] && verify_checksum "$url" "$expected_sha256" "$tool" > "$ACFS_TMP_INSTALL"; then
                chmod 755 "$ACFS_TMP_INSTALL" 2>/dev/null || true

                if try_step "Installing MCP Agent Mail" run_as_target bash "$ACFS_TMP_INSTALL" --dest "$target_dir" --yes; then
                    # Symlink repair/normalization: prefer the freshly installed
                    # Rust CLI even if an older am is already on PATH.
                    run_as_target env "ACFS_AGENT_MAIL_TARGET_DIR=$target_dir" bash -c '
                        export PATH="${ACFS_BIN_DIR:-$HOME/.local/bin}:$HOME/.local/bin:$HOME/.acfs/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$HOME/go/bin:/usr/local/bin:/usr/bin:/bin:/snap/bin"
                        am_src="$ACFS_AGENT_MAIL_TARGET_DIR/am"
                        am_dst="$HOME/.local/bin/am"
                        primary_am="${ACFS_BIN_DIR:-$HOME/.local/bin}/am"
                        resolved_am=""
                        for candidate in \
                            "$am_src" \
                            "$primary_am" \
                            "$HOME/.local/bin/am" \
                            "$HOME/.acfs/bin/am" \
                            "$HOME/.cargo/bin/am" \
                            "$HOME/.bun/bin/am" \
                            "$HOME/.atuin/bin/am" \
                            "$HOME/go/bin/am"; do
                            if [[ -x "$candidate" ]]; then
                                resolved_am="$candidate"
                                break
                            fi
                        done
                        if [[ -x "$am_src" ]]; then
                            mkdir -p "$HOME/.local/bin"
                            if [[ "$resolved_am" != "$am_src" ]]; then
                                ln -sf "$am_src" "$am_dst"
                                echo "ACFS: ensured am symlink points at installed binary: $am_dst -> $am_src" >&2
                            fi
                        fi
                    ' || true
                    if run_as_target bash -c 'set -euo pipefail
                        export PATH="${ACFS_BIN_DIR:-$HOME/.local/bin}:$HOME/.local/bin:$HOME/.acfs/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$HOME/go/bin:/usr/local/bin:/usr/bin:/bin:/snap/bin"
                        sqlite_user_table_count() {
                            local db_path="$1"
                            [[ -f "$db_path" ]] || {
                                printf "0\n"
                                return 0
                            }
                            if command -v python3 >/dev/null 2>&1; then
                                python3 - "$db_path" <<'"'"'PY'"'"'
import sqlite3
import sys

db_path = sys.argv[1]
try:
    conn = sqlite3.connect(db_path)
    cur = conn.execute("SELECT count(*) FROM sqlite_master WHERE type='\''table'\'' AND name NOT LIKE '\''sqlite_%'\''")
    row = cur.fetchone()
    print(int(row[0]) if row and row[0] is not None else 0)
except Exception:
    print(0)
PY
                                return 0
                            fi
                            if command -v sqlite3 >/dev/null 2>&1; then
                                sqlite3 "$db_path" "SELECT count(*) FROM sqlite_master WHERE type='\''table'\'' AND name NOT LIKE '\''sqlite_%'\'';" 2>/dev/null || printf "0\n"
                                return 0
                            fi
                            printf "0\n"
                        }

                        storage_root="$HOME/.mcp_agent_mail_git_mailbox_repo"
                        install_storage_root="$HOME/mcp_agent_mail"
                        install_db="$install_storage_root/storage.sqlite3"
                        legacy_db="$storage_root/storage.sqlite3"
                        unit_dir="$HOME/.config/systemd/user"
                        unit_file="$unit_dir/agent-mail.service"
                        preferred_am="$HOME/mcp_agent_mail/am"
                        primary_am="${ACFS_BIN_DIR:-$HOME/.local/bin}/am"
                        am_bin=""
                        for candidate in \
                            "$preferred_am" \
                            "$primary_am" \
                            "$HOME/.local/bin/am" \
                            "$HOME/.acfs/bin/am" \
                            "$HOME/.cargo/bin/am" \
                            "$HOME/.bun/bin/am" \
                            "$HOME/.atuin/bin/am" \
                            "$HOME/go/bin/am"; do
                            if [[ -x "$candidate" ]]; then
                                am_bin="$candidate"
                                break
                            fi
                        done
                        [[ -n "$am_bin" ]] || exit 1
                        if [[ -f "$install_db" ]]; then
                            install_tables="$(sqlite_user_table_count "$install_db")"
                            legacy_tables="$(sqlite_user_table_count "$legacy_db")"
                            if [[ "$install_tables" -gt 0 && "$legacy_tables" -eq 0 ]]; then
                                storage_root="$install_storage_root"
                            fi
                        fi
                        db_url="sqlite:///${storage_root}/storage.sqlite3"
                        # Detect MCP base path: Rust am uses /mcp/, Python mcp_agent_mail uses /api/
                        if "$am_bin" --version 2>/dev/null | grep -q "^am "; then
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
Environment=HTTP_ALLOW_LOCALHOST_UNAUTHENTICATED=true
ExecStartPre=$am_bin migrate
ExecStart=$am_bin serve-http --no-tui --host 127.0.0.1 --port 8765 --path $am_mcp_path
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
                            existing_pid=""
                            if curl -fsS --max-time 5 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1 && \
                               curl -fsS --max-time 5 http://127.0.0.1:8765/health 2>/dev/null | grep -Eq "\"status\"[[:space:]]*:[[:space:]]*\"ready\""; then
                                :
                            elif [[ -f "$fallback_pid_file" ]]; then
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
                                    rm -f "$fallback_pid_file"
                                else
                                    rm -f "$fallback_pid_file"
                                fi
                            fi
                            if env \
                                RUST_LOG=info \
                                STORAGE_ROOT="$storage_root" \
                                DATABASE_URL="$db_url" \
                                HTTP_ALLOW_LOCALHOST_UNAUTHENTICATED=true \
                                "$am_bin" migrate >>"$fallback_log_file" 2>&1; then
                                nohup env \
                                    RUST_LOG=info \
                                    STORAGE_ROOT="$storage_root" \
                                    DATABASE_URL="$db_url" \
                                    HTTP_ALLOW_LOCALHOST_UNAUTHENTICATED=true \
                                    "$am_bin" serve-http --no-tui --host 127.0.0.1 --port 8765 --path "$am_mcp_path" \
                                    >>"$fallback_log_file" 2>&1 < /dev/null &
                                echo $! > "$fallback_pid_file"
                            fi
                        fi
                    '; then
                        local am_waited=0
                        local am_max_wait=30
                        until curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1 && \
                              curl -fsS --max-time 10 http://127.0.0.1:8765/health 2>/dev/null | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ready"'; do
                            if [[ "$am_waited" -ge "$am_max_wait" ]]; then
                                log_error "MCP Agent Mail service did not become ready on http://127.0.0.1:8765 after ${am_max_wait}s"
                                break
                            fi
                            sleep 2
                            am_waited=$((am_waited + 2))
                        done
                        if curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1 && \
                           curl -fsS --max-time 10 http://127.0.0.1:8765/health 2>/dev/null | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ready"'; then
                            log_success "MCP Agent Mail service running on http://127.0.0.1:8765"
                            am_service_ready=true
                        else
                            log_error "MCP Agent Mail installed but service did not become ready"
                        fi
                    else
                        log_error "MCP Agent Mail installed but managed service setup failed"
                    fi
                else
                    log_error "MCP Agent Mail installation may have failed"
                fi
                rm -f "$ACFS_TMP_INSTALL" 2>/dev/null || true
                ACFS_TMP_INSTALL=""
            else
                rm -f "$ACFS_TMP_INSTALL" 2>/dev/null || true
                ACFS_TMP_INSTALL=""
                log_error "MCP Agent Mail: installer verification failed"
            fi
        fi
    elif [[ "$am_service_ready" != "true" ]]; then
        log_error "MCP Agent Mail: unable to load upstream checksums; refusing to run unverified installer"
    fi

    if [[ "$am_service_ready" != "true" ]]; then
        return 1
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
    # The upstream install script calls GitHub API for latest version, which hits rate limits in CI.
    # We install via .deb package directly to avoid this.
    if binary_installed "slb"; then
        log_detail "SLB already installed"
    else
        log_detail "Installing SLB"
        local slb_version="0.2.0"
        local slb_arch="amd64"
        [[ "$(uname -m)" == "aarch64" ]] && slb_arch="arm64"
        local slb_deb="slb_${slb_version}_linux_${slb_arch}.deb"
        local slb_url="https://github.com/Dicklesworthstone/slb/releases/download/v${slb_version}/${slb_deb}"
        ACFS_TMP_SLB="$(mktemp -d "${TMPDIR:-/tmp}/acfs-slb.XXXXXX" 2>/dev/null)" || ACFS_TMP_SLB=""
        if [[ -n "$ACFS_TMP_SLB" ]] && [[ -d "$ACFS_TMP_SLB" ]]; then
            if acfs_curl -o "${ACFS_TMP_SLB}/${slb_deb}" "$slb_url" && \
               $SUDO dpkg -i "${ACFS_TMP_SLB}/${slb_deb}"; then
                log_success "SLB installed via .deb"
            else
                log_warn "SLB .deb install failed, trying upstream script"
                try_step "Installing SLB (upstream)" acfs_run_verified_upstream_script_as_target "slb" "bash" || log_warn "SLB installation may have failed"
            fi
            rm -rf "$ACFS_TMP_SLB" 2>/dev/null || true
            ACFS_TMP_SLB=""
        else
            log_warn "Failed to create temp directory for SLB, trying upstream script"
            try_step "Installing SLB (upstream)" acfs_run_verified_upstream_script_as_target "slb" "bash" || log_warn "SLB installation may have failed"
        fi
    fi

    # RU (Repo Updater)
    if binary_installed "ru"; then
        log_detail "RU already installed"
    else
        log_detail "Installing RU"
        try_step "Installing RU" acfs_run_verified_upstream_script_as_target_with_env "ru" "bash" "RU_NON_INTERACTIVE=1" || log_warn "RU installation may have failed"
    fi

    # RCH (Remote Compilation Helper)
    if binary_installed "rch"; then
        log_detail "RCH already installed"
    else
        log_detail "Installing RCH"
        try_step "Installing RCH" acfs_run_verified_upstream_script_as_target "rch" "bash" || log_warn "RCH installation may have failed"
    fi

    # FrankenSearch (fsfs)
    if binary_installed "fsfs"; then
        log_detail "FrankenSearch already installed"
    else
        log_detail "Installing FrankenSearch"
        try_step "Installing FrankenSearch" acfs_run_verified_upstream_script_as_target "fsfs" "bash" --easy-mode || log_warn "FrankenSearch installation may have failed"
    fi

    # Process Triage (pt)
    if binary_installed "pt"; then
        log_detail "Process Triage already installed"
    else
        log_detail "Installing Process Triage"
        try_step "Installing Process Triage" acfs_run_verified_upstream_script_as_target "pt" "bash" || log_warn "Process Triage installation may have failed"
    fi

    # Storage Ballast Helper (sbh)
    if binary_installed "sbh"; then
        log_detail "Storage Ballast Helper already installed"
    else
        log_detail "Installing Storage Ballast Helper"
        try_step "Installing SBH" acfs_run_verified_upstream_script_as_target "sbh" "bash" || log_warn "SBH installation may have failed"
    fi

    # Cross-Agent Session Resumer (casr)
    if binary_installed "casr"; then
        log_detail "CASR already installed"
    else
        log_detail "Installing CASR"
        try_step "Installing CASR" acfs_run_verified_upstream_script_as_target "casr" "bash" || log_warn "CASR installation may have failed"
    fi

    # Doodlestein Self-Releaser (dsr) — modular bash project with verified installer
    if binary_installed "dsr"; then
        log_detail "DSR already installed"
    else
        log_detail "Installing DSR"
        try_step "Installing DSR" acfs_run_verified_upstream_script_as_target "dsr" "bash" --easy-mode || log_warn "DSR installation may have failed"
    fi

    # Agent Settings Backup (asb)
    if binary_installed "asb"; then
        log_detail "ASB already installed"
    else
        log_detail "Installing ASB"
        try_step "Installing ASB" acfs_run_verified_upstream_script_as_target "asb" "bash" || log_warn "ASB installation may have failed"
    fi

    # Post-Compact Reminder (pcr hook)
    local pcr_installed=false
    local pcr_hook_script="$TARGET_HOME/.local/bin/claude-post-compact-reminder"
    local settings_file="$TARGET_HOME/.claude/settings.json"
    local alt_settings_file="$TARGET_HOME/.config/claude/settings.json"
    if [[ -x "$pcr_hook_script" ]]; then
        if [[ -f "$settings_file" ]] && grep -q "claude-post-compact-reminder" "$settings_file" 2>/dev/null; then
            pcr_installed=true
        elif [[ -f "$alt_settings_file" ]] && grep -q "claude-post-compact-reminder" "$alt_settings_file" 2>/dev/null; then
            pcr_installed=true
        fi
    fi

    if [[ "$pcr_installed" == "true" ]]; then
        log_detail "Post-Compact Reminder already installed"
    elif ! binary_installed "claude"; then
        log_detail "Skipping Post-Compact Reminder because Claude Code is not installed"
    else
        log_detail "Installing Post-Compact Reminder"
        try_step "Installing PCR" acfs_run_verified_upstream_script_as_target "pcr" "bash" --yes || log_warn "PCR installation may have failed"
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
    if [[ -x "$ACFS_BIN_DIR/dcg" ]]; then
        dcg_bin="$ACFS_BIN_DIR/dcg"
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

    # Token-Optimized Notation (tru)
    if binary_installed "tru"; then
        log_detail "TRU already installed"
    else
        log_detail "Installing TRU"
        try_step "Installing TRU" acfs_run_verified_upstream_script_as_target "tru" "bash" || log_warn "TRU installation may have failed"
    fi

    # Automated Plan Reviser (apr)
    if binary_installed "apr"; then
        log_detail "APR already installed"
    else
        log_detail "Installing APR"
        try_step "Installing APR" acfs_run_verified_upstream_script_as_target "apr" "bash" --easy-mode || log_warn "APR installation may have failed"
    fi

    # Chat Shared Conversation to File (csctf)
    if binary_installed "csctf"; then
        log_detail "CSCTF already installed"
    else
        log_detail "Installing CSCTF"
        try_step "Installing CSCTF" acfs_run_verified_upstream_script_as_target "csctf" "bash" || log_warn "CSCTF installation may have failed"
    fi

    # Get Image from Internet Link (giil)
    if binary_installed "giil"; then
        log_detail "GIIL already installed"
    else
        log_detail "Installing GIIL"
        try_step "Installing GIIL" acfs_run_verified_upstream_script_as_target "giil" "bash" || log_warn "GIIL installation may have failed"
    fi

    # JeffreysPrompts CLI (jfp)
    if binary_installed "jfp"; then
        log_detail "JFP already installed"
    else
        log_detail "Installing JFP"
        try_step "Installing JFP" acfs_run_verified_upstream_script_as_target "jfp" "bash" || log_warn "JFP installation may have failed"
    fi

    # Markdown Web Browser (mdwb)
    if binary_installed "mdwb"; then
        log_detail "MDWB already installed"
    else
        log_detail "Installing MDWB"
        try_step "Installing MDWB" acfs_run_verified_upstream_script_as_target "mdwb" "bash" || log_warn "MDWB installation may have failed"
    fi

    # Meta Skill (ms)
    if binary_installed "ms"; then
        log_detail "Meta Skill already installed"
    else
        log_detail "Installing Meta Skill"
        try_step "Installing Meta Skill" acfs_run_verified_upstream_script_as_target "ms" "bash" --easy-mode || log_warn "Meta Skill installation may have failed"
    fi

    # OpenCode
    if binary_installed "opencode"; then
        log_detail "OpenCode already installed"
    else
        log_detail "Installing OpenCode"
        try_step "Installing OpenCode" acfs_run_verified_upstream_script_as_target "opencode" "bash" || log_warn "OpenCode installation may have failed"
    fi

    # Network Observer (rano)
    if binary_installed "rano"; then
        log_detail "RANO already installed"
    else
        log_detail "Installing RANO"
        try_step "Installing RANO" acfs_run_verified_upstream_script_as_target "rano" "bash" || log_warn "RANO installation may have failed"
    fi

    # Source to Prompt TUI (s2p)
    if binary_installed "s2p"; then
        log_detail "S2P already installed"
    else
        log_detail "Installing S2P"
        try_step "Installing S2P" acfs_run_verified_upstream_script_as_target "s2p" "bash" --skip-cass || log_warn "S2P installation may have failed"
    fi

    # System Resource Protection Script (srps)
    if binary_installed "sysmoni"; then
        log_detail "SRPS already installed"
    else
        log_detail "Installing SRPS"
        try_step "Installing SRPS" acfs_run_verified_upstream_script_as_target "srps" "bash" --install || log_warn "SRPS installation may have failed"
    fi

    # X Archive Search (xf)
    if binary_installed "xf"; then
        log_detail "XF already installed"
    else
        log_detail "Installing XF"
        try_step "Installing XF" acfs_run_verified_upstream_script_as_target "xf" "bash" --easy-mode || log_warn "XF installation may have failed"
    fi

    # Brenner Bot
    if binary_installed "brenner"; then
        log_detail "Brenner Bot already installed"
    else
        log_detail "Installing Brenner Bot"
        try_step "Installing Brenner Bot" acfs_run_verified_upstream_script_as_target "brenner_bot" "bash" --skip-cass || log_warn "Brenner Bot installation may have failed"
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
        log_detail "Generated acfs modules are supplemental; continuing legacy finalize for full runtime deployment parity"
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
    local lesson_path
    local lesson_name
    local nullglob_was_set=0
    if shopt -q nullglob; then
        nullglob_was_set=1
    fi
    shopt -s nullglob
    local lesson_files=("${ACFS_ASSETS_DIR}/onboard/lessons/"*.md)
    if (( ! nullglob_was_set )); then
        shopt -u nullglob
    fi
    if [[ ${#lesson_files[@]} -eq 0 ]]; then
        log_error "No onboard lessons found in ${ACFS_ASSETS_DIR}/onboard/lessons"
        return 1
    fi
    for lesson_path in "${lesson_files[@]}"; do
        lesson_name=$(basename "$lesson_path")
        try_step "Installing onboard lesson: $lesson_name" install_asset "acfs/onboard/lessons/$lesson_name" "$ACFS_HOME/onboard/lessons/$lesson_name" || return 1
    done

    log_detail "Installing onboard command"
    try_step "Installing onboard script" install_asset "packages/onboard/onboard.sh" "$ACFS_HOME/onboard/onboard.sh" || return 1
    try_step "Setting onboard permissions" $SUDO chmod 755 "$ACFS_HOME/onboard/onboard.sh" || return 1
    try_step "Setting onboard ownership" acfs_chown_tree "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/onboard" || return 1

    try_step "Creating bin directory ($ACFS_BIN_DIR)" acfs_ensure_primary_bin_dir || return 1
    try_step "Linking onboard command" acfs_link_primary_bin_command "$ACFS_HOME/onboard/onboard.sh" "onboard" || return 1

    # Install acfs scripts (for acfs CLI subcommands)
    log_detail "Installing acfs scripts"
    try_step "Creating ACFS scripts directory" $SUDO mkdir -p "$ACFS_HOME/scripts/lib" || return 1
    try_step "Creating ACFS generated scripts directory" $SUDO mkdir -p "$ACFS_HOME/scripts/generated" || return 1
    try_step "Creating ACFS templates directory" $SUDO mkdir -p "$ACFS_HOME/scripts/templates" || return 1
    
    # Install script libraries
    try_step "Installing logging.sh" install_asset "scripts/lib/logging.sh" "$ACFS_HOME/scripts/lib/logging.sh" || return 1
    try_step "Installing output.sh" install_asset "scripts/lib/output.sh" "$ACFS_HOME/scripts/lib/output.sh" || return 1
    try_step "Installing gum_ui.sh" install_asset "scripts/lib/gum_ui.sh" "$ACFS_HOME/scripts/lib/gum_ui.sh" || return 1
    try_step "Installing contract.sh" install_asset "scripts/lib/contract.sh" "$ACFS_HOME/scripts/lib/contract.sh" || return 1
    try_step "Installing security.sh" install_asset "scripts/lib/security.sh" "$ACFS_HOME/scripts/lib/security.sh" || return 1
    try_step "Installing autofix.sh" install_asset "scripts/lib/autofix.sh" "$ACFS_HOME/scripts/lib/autofix.sh" || return 1
    try_step "Installing doctor_fix.sh" install_asset "scripts/lib/doctor_fix.sh" "$ACFS_HOME/scripts/lib/doctor_fix.sh" || return 1
    try_step "Installing doctor.sh" install_asset "scripts/lib/doctor.sh" "$ACFS_HOME/scripts/lib/doctor.sh" || return 1
    try_step "Installing nightly_update.sh (source)" install_asset "scripts/lib/nightly_update.sh" "$ACFS_HOME/scripts/lib/nightly_update.sh" || return 1
    try_step "Installing nightly-update.sh (runtime wrapper)" install_asset "scripts/lib/nightly_update.sh" "$ACFS_HOME/scripts/nightly-update.sh" || return 1
    try_step "Installing update.sh" install_asset "scripts/lib/update.sh" "$ACFS_HOME/scripts/lib/update.sh" || return 1
    try_step "Installing session.sh" install_asset "scripts/lib/session.sh" "$ACFS_HOME/scripts/lib/session.sh" || return 1
    try_step "Installing continue.sh" install_asset "scripts/lib/continue.sh" "$ACFS_HOME/scripts/lib/continue.sh" || return 1
    try_step "Installing info.sh" install_asset "scripts/lib/info.sh" "$ACFS_HOME/scripts/lib/info.sh" || return 1
    try_step "Installing status.sh" install_asset "scripts/lib/status.sh" "$ACFS_HOME/scripts/lib/status.sh" || return 1
    try_step "Installing changelog.sh" install_asset "scripts/lib/changelog.sh" "$ACFS_HOME/scripts/lib/changelog.sh" || return 1
    try_step "Installing export-config.sh" install_asset "scripts/lib/export-config.sh" "$ACFS_HOME/scripts/lib/export-config.sh" || return 1
    try_step "Installing cheatsheet.sh" install_asset "scripts/lib/cheatsheet.sh" "$ACFS_HOME/scripts/lib/cheatsheet.sh" || return 1
    try_step "Installing webhook.sh" install_asset "scripts/lib/webhook.sh" "$ACFS_HOME/scripts/lib/webhook.sh" || return 1
    try_step "Installing notify.sh" install_asset "scripts/lib/notify.sh" "$ACFS_HOME/scripts/lib/notify.sh" || return 1
    try_step "Installing notifications.sh" install_asset "scripts/lib/notifications.sh" "$ACFS_HOME/scripts/lib/notifications.sh" || return 1
    try_step "Installing dashboard.sh" install_asset "scripts/lib/dashboard.sh" "$ACFS_HOME/scripts/lib/dashboard.sh" || return 1
    try_step "Installing support.sh" install_asset "scripts/lib/support.sh" "$ACFS_HOME/scripts/lib/support.sh" || return 1
    try_step "Installing acfs-nightly-update.service template" install_asset "scripts/templates/acfs-nightly-update.service" "$ACFS_HOME/scripts/templates/acfs-nightly-update.service" || return 1
    try_step "Installing acfs-nightly-update.timer template" install_asset "scripts/templates/acfs-nightly-update.timer" "$ACFS_HOME/scripts/templates/acfs-nightly-update.timer" || return 1

    local generated_script=""
    local generated_basename=""
    local generated_count=0
    for generated_script in "$ACFS_GENERATED_DIR"/*.sh; do
        [[ -f "$generated_script" ]] || continue
        generated_basename="$(basename "$generated_script")"
        try_step "Installing generated script: $generated_basename" install_asset_from_path "$generated_script" "$ACFS_HOME/scripts/generated/$generated_basename" || return 1
        generated_count=$((generated_count + 1))
    done
    if [[ $generated_count -eq 0 ]]; then
        log_error "No generated ACFS scripts found to install from $ACFS_GENERATED_DIR"
        return 1
    fi

    # Install acfs-update wrapper command
    try_step "Installing acfs-update" install_asset "scripts/acfs-update" "$ACFS_HOME/bin/acfs-update" || return 1
    try_step "Setting acfs-update permissions" $SUDO chmod 755 "$ACFS_HOME/bin/acfs-update" || return 1
    try_step "Setting acfs-update ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/bin/acfs-update" || return 1
    try_step "Linking acfs-update command" acfs_link_primary_bin_command "$ACFS_HOME/bin/acfs-update" "acfs-update" || return 1

    # Install root AGENTS.md generator (if available) and generate /AGENTS.md once
    if try_step "Installing flywheel-update-agents-md" install_asset "scripts/generate-root-agents-md.sh" "$ACFS_HOME/bin/flywheel-update-agents-md"; then
        try_step "Setting flywheel-update-agents-md permissions" $SUDO chmod 755 "$ACFS_HOME/bin/flywheel-update-agents-md" || return 1
        try_step "Setting flywheel-update-agents-md ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/bin/flywheel-update-agents-md" || return 1
        try_step "Linking flywheel-update-agents-md command" $SUDO ln -sf "$ACFS_HOME/bin/flywheel-update-agents-md" "/usr/local/bin/flywheel-update-agents-md" || return 1
        try_step "Generating /AGENTS.md" $SUDO /usr/local/bin/flywheel-update-agents-md || true
    else
        log_warn "Root AGENTS.md generator not found; skipping /AGENTS.md generation"
    fi

    # Install services-setup wizard
    try_step "Installing services-setup.sh" install_asset "scripts/services-setup.sh" "$ACFS_HOME/scripts/services-setup.sh" || return 1
    try_step "Setting scripts permissions" $SUDO chmod 755 "$ACFS_HOME/scripts/services-setup.sh" || return 1
    try_step "Setting lib scripts permissions" $SUDO chmod 755 "$ACFS_HOME/scripts/lib/"*.sh "$ACFS_HOME/scripts/nightly-update.sh" || return 1
    try_step "Setting generated scripts permissions" $SUDO find "$ACFS_HOME/scripts/generated" -maxdepth 1 -type f -name '*.sh' -exec chmod 755 {} + || return 1
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
    try_step "Linking acfs command" acfs_link_primary_bin_command "$ACFS_HOME/bin/acfs" "acfs" || return 1

    # Install global acfs wrapper (works for root and all users)
    # This wrapper finds the target user from state and runs acfs as that user
    try_step "Installing global acfs wrapper" install_asset "scripts/acfs-global" "/usr/local/bin/acfs" || return 1
    try_step "Setting global acfs permissions" $SUDO chmod 755 "/usr/local/bin/acfs" || return 1

    # Install DCG (Destructive Command Guard) hook automatically.
    #
    # This is especially important because ACFS config includes "dangerous mode"
    # aliases (e.g., `cc`) that can run commands without interactive approvals.
    log_detail "Installing DCG (Destructive Command Guard) PreToolUse hook"
    try_step "Installing DCG hook" \
        env "TARGET_USER=$TARGET_USER" "TARGET_HOME=$TARGET_HOME" \
        "$ACFS_HOME/scripts/services-setup.sh" --install-claude-guard --yes || \
        log_warn "DCG hook installation failed (optional)"

    # Configure workspace trust for coding agents (fixes #159)
    # In vibe/yolo mode, Claude Code requires explicit workspace trust to avoid
    # interactive prompts. Set skipDangerousModePermissionPrompt and trust /data/projects + $HOME.
    if [[ "$MODE" == "vibe" ]]; then
        log_detail "Configuring workspace trust for coding agents..."
        local claude_settings_file="$TARGET_HOME/.claude/settings.json"
        if [[ -f "$claude_settings_file" ]] && command -v jq &>/dev/null; then
            # Use run_as_target for the entire jq+mv pipeline so the temp file
            # is created with target user ownership (not root). Previously the
            # shell redirect "> $tmp_settings" ran as root, leaving a root-owned
            # settings file that the target user couldn't modify later.
            local tmp_settings="${claude_settings_file}.tmp.$$"
            if run_as_target bash -c "jq '.skipDangerousModePermissionPrompt = true' \"\$1\" > \"\$2\" && mv \"\$2\" \"\$1\"" \
                    _ "$claude_settings_file" "$tmp_settings" 2>/dev/null; then
                log_detail "Claude workspace trust configured"
            else
                run_as_target rm -f "$tmp_settings" 2>/dev/null || true
            fi
        elif [[ ! -f "$claude_settings_file" ]]; then
            # Create minimal settings with trust enabled
            run_as_target mkdir -p "$TARGET_HOME/.claude" 2>/dev/null || true
            run_as_target tee "$claude_settings_file" > /dev/null << 'CLAUDE_TRUST_EOF'
{
  "skipDangerousModePermissionPrompt": true
}
CLAUDE_TRUST_EOF
            log_detail "Claude settings created with workspace trust"
        fi

        # Gemini CLI trust pre-configuration (fixes #159 follow-up)
        # Gemini CLI prompts for folder trust on first run. Pre-configure trusted
        # folders so agents can start without interactive approval.
        local gemini_settings_file="$TARGET_HOME/.gemini/settings.json"
        if [[ -f "$gemini_settings_file" ]] && command -v jq &>/dev/null; then
            local tmp_gemini="${gemini_settings_file}.tmp.$$"
            # Enable folder trust and set yolo-equivalent sandbox bypass
            if run_as_target bash -c "jq '
                .security = (.security // {})
                | .security.folderTrust = (.security.folderTrust // {})
                | .security.folderTrust.enabled = true
            ' \"\$1\" > \"\$2\" && mv \"\$2\" \"\$1\"" \
                    _ "$gemini_settings_file" "$tmp_gemini" 2>/dev/null; then
                log_detail "Gemini workspace trust configured"
            else
                run_as_target rm -f "$tmp_gemini" 2>/dev/null || true
            fi
        elif [[ ! -f "$gemini_settings_file" ]]; then
            run_as_target mkdir -p "$TARGET_HOME/.gemini" 2>/dev/null || true
            run_as_target tee "$gemini_settings_file" > /dev/null << 'GEMINI_TRUST_EOF'
{
  "security": {
    "folderTrust": {
      "enabled": true
    }
  }
}
GEMINI_TRUST_EOF
            log_detail "Gemini settings created with workspace trust"
        fi

        # Pre-populate Gemini trusted folders list so agents skip the
        # interactive "Trust this folder?" prompt entirely.
        # Gemini CLI 0.33.0+ expects trustedFolders.json as a JSON object
        # mapping folder paths to "TRUST_FOLDER", not a JSON array.
        local gemini_trusted_folders="$TARGET_HOME/.gemini/trustedFolders.json"
        if [[ ! -f "$gemini_trusted_folders" ]]; then
            local tmp_folders="${gemini_trusted_folders}.tmp.$$"
            if run_as_target bash -c '
                jq -n --arg home "$1" '"'"'{"/data/projects": "TRUST_FOLDER", ($home): "TRUST_FOLDER"}'"'"' > "$2" &&
                mv "$2" "$3"
            ' _ "$TARGET_HOME" "$tmp_folders" "$gemini_trusted_folders" 2>/dev/null; then
                log_detail "Gemini trusted folders pre-configured"
            else
                run_as_target rm -f "$tmp_folders" 2>/dev/null || true
                log_warn "Gemini trusted folders pre-configuration failed"
            fi
        elif command -v jq &>/dev/null; then
            # Merge paths into existing file, handling both legacy array format
            # and current object format (fixes #213).
            local tmp_folders="${gemini_trusted_folders}.tmp.$$"
            if run_as_target bash -c '
                content=$(cat "$1" 2>/dev/null) || content="{}"
                is_array=$(echo "$content" | jq -e "type == \"array\"" 2>/dev/null) || is_array="false"
                if [ "$is_array" = "true" ]; then
                    # Migrate legacy array format to object format
                    migrated=$(echo "$content" | jq "reduce .[] as \$p ({}; . + {(\$p): \"TRUST_FOLDER\"})")
                    content="$migrated"
                fi
                # Merge required paths into object
                updated=$(echo "$content" | jq \
                    --arg p1 "/data/projects" \
                    --arg p2 "$2" \
                    ". + {(\$p1): \"TRUST_FOLDER\", (\$p2): \"TRUST_FOLDER\"}")
                if [ "$updated" != "$content" ]; then
                    echo "$updated" > "$3" && mv "$3" "$1"
                fi
            ' _ "$gemini_trusted_folders" "$TARGET_HOME" "$tmp_folders" 2>/dev/null; then
                log_detail "Gemini trusted folders updated"
            else
                run_as_target rm -f "$tmp_folders" 2>/dev/null || true
            fi
        fi
    fi

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
  "target_home": "$TARGET_HOME",
  "bin_dir": "$ACFS_BIN_DIR",
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
_smoke_target_path() {
    local user_home="${TARGET_HOME:-}"
    if [[ -z "$user_home" ]]; then
        user_home="$(acfs_home_for_user "$TARGET_USER" || true)"
    fi
    if [[ -z "$user_home" ]] || [[ "$user_home" != /* ]]; then
        return 1
    fi

    printf '%s\n' "${ACFS_BIN_DIR:-$user_home/.local/bin}:$user_home/.local/bin:$user_home/.acfs/bin:$user_home/.cargo/bin:$user_home/.bun/bin:$user_home/.atuin/bin:$user_home/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
}


_smoke_run_as_target() {
    local cmd="$1"
    local smoke_path=""

    smoke_path="$(_smoke_target_path)" || return 1
    run_as_target env "PATH=$smoke_path" bash -c "set -euo pipefail; $cmd"
}

run_smoke_test() {
    local critical_total=8
    local critical_passed=0
    local critical_failed=0
    local warnings=0

    echo "" >&2
    echo "[Smoke Test]" >&2

    # 1) Target user exists
    local smoke_id_bin=""
    local target_shell=""
    local target_shell_entry=""
    smoke_id_bin="$(acfs_early_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$smoke_id_bin" ]] && "$smoke_id_bin" "$TARGET_USER" &>/dev/null; then
        echo "✅ User: $TARGET_USER" >&2
        ((critical_passed += 1))
    else
        echo "✖ User: missing (TARGET_USER=$TARGET_USER)" >&2
        echo "    Fix: set TARGET_USER=<user> and ensure the user exists" >&2
        ((critical_failed += 1))
    fi

    # 2) Shell is zsh
    target_shell_entry="$(acfs_early_getent_passwd_entry "$TARGET_USER" 2>/dev/null || true)"
    if [[ -n "$target_shell_entry" ]]; then
        IFS=: read -r _ _ _ _ _ _ target_shell <<< "$target_shell_entry"
    fi
    if [[ "$target_shell" == *"zsh"* ]]; then
        echo "✅ Shell: zsh" >&2
        ((critical_passed += 1))
    elif acfs_is_externally_managed_user "$TARGET_USER"; then
        if acfs_external_shell_handoff_configured "$TARGET_HOME"; then
            echo "✅ Shell: externally managed login hands off to zsh" >&2
            ((critical_passed += 1))
        else
            echo "⚠ Shell: externally managed account reports ${target_shell:-unknown}" >&2
            echo "    Note: local chsh is not valid here; configure the identity provider shell or add the ACFS bash-to-zsh handoff." >&2
            ((warnings += 1))
        fi
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
    [[ -x "$ACFS_BIN_DIR/uv" || -x "$TARGET_HOME/.cargo/bin/uv" ]] || missing_lang+=("uv")
    [[ -x "$TARGET_HOME/.cargo/bin/cargo" ]] || missing_lang+=("cargo")
    binary_installed "go" || missing_lang+=("go")
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
    [[ -x "$ACFS_BIN_DIR/claude" || -x "$TARGET_HOME/.bun/bin/claude" ]] || missing_agents+=("claude")
    [[ -x "$TARGET_HOME/.bun/bin/codex" || -x "$ACFS_BIN_DIR/codex" ]] || missing_agents+=("codex")
    [[ -x "$TARGET_HOME/.bun/bin/gemini" || -x "$ACFS_BIN_DIR/gemini" ]] || missing_agents+=("gemini")
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
    if [[ -x "$ACFS_BIN_DIR/onboard" ]]; then
        echo "✅ Onboard: installed" >&2
        ((critical_passed += 1))
    else
        echo "✖ Onboard: missing" >&2
        echo "    Fix: curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only-phase 9" >&2
        ((critical_failed += 1))
    fi

    # Non-critical: Agent Mail service status
    if run_as_target bash -c 'set -euo pipefail
        export PATH="${ACFS_BIN_DIR:-$HOME/.local/bin}:$HOME/.local/bin:$HOME/.acfs/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$HOME/go/bin:/usr/local/bin:/usr/bin:/bin:/snap/bin"
        primary_am="${ACFS_BIN_DIR:-$HOME/.local/bin}/am"
        [[ -x "$HOME/mcp_agent_mail/am" || -x "$primary_am" || -x "$HOME/.local/bin/am" || -x "$HOME/.acfs/bin/am" || -x "$HOME/.cargo/bin/am" || -x "$HOME/.bun/bin/am" || -x "$HOME/.atuin/bin/am" || -x "$HOME/go/bin/am" ]]
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
        curl -fsS --max-time 5 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1
    ' &>/dev/null; then
        echo "✅ Agent Mail: running on http://127.0.0.1:8765" >&2
    elif [[ -x "$TARGET_HOME/.local/bin/am" ]] || [[ -x "$TARGET_HOME/mcp_agent_mail/scripts/run_server_with_token.sh" ]]; then
        echo "⚠️ Agent Mail: installed but service is not running" >&2
        echo "    Fix: rerun ACFS update/install to rewrite agent-mail.service, then systemctl --user enable --now agent-mail.service" >&2
        ((warnings += 1))
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
    elif binary_installed "vault"; then
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
    acfs_require_ref_arg_value "ACFS_REF" "${ACFS_REF:-}" "main"
    acfs_require_ref_arg_value "ACFS_CHECKSUMS_REF" "${ACFS_CHECKSUMS_REF:-}" "main"
    normalize_read_only_modes

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
        # Download and extract the repo archive for curl-pipe mode.
        # This sets ACFS_BOOTSTRAP_DIR and related paths. If it fails, we cannot continue
        # because the library files (install_helpers.sh, etc.) won't be available.
        if ! bootstrap_repo_archive; then
            log_error "Bootstrap failed. Cannot continue without library files."
            log_error "Try again, or run from a local checkout instead of curl|bash."
            exit 1
        fi
        # Verify bootstrap succeeded - ACFS_BOOTSTRAP_DIR must be set for curl-pipe mode
        if [[ -z "${ACFS_BOOTSTRAP_DIR:-}" ]]; then
            log_error "Bootstrap did not set ACFS_BOOTSTRAP_DIR. This is a bug."
            exit 1
        fi
    fi

    # Detect environment and source manifest index (mjt.5.3)
    # This must happen BEFORE any handlers that need module data
    detect_environment

    # Acquire install-wide flock to prevent concurrent install.sh processes.
    # Uses FD 199 (autofix.sh already uses FD 200 for its own lock).
    # Read-only modes (--list-modules, --print-plan, --dry-run, --print) skip locking.
    if [[ "$LIST_MODULES" != "true" ]] && [[ "$PRINT_PLAN_MODE" != "true" ]] \
       && [[ "$DRY_RUN" != "true" ]] && [[ "$PRINT_MODE" != "true" ]]; then
        local _acfs_lock_home="${TARGET_HOME:-}"
        if [[ -z "$_acfs_lock_home" ]]; then
            _acfs_lock_home="$(acfs_home_for_user "${TARGET_USER:-ubuntu}" || true)"
        fi
        if [[ -z "$_acfs_lock_home" ]] || [[ "$_acfs_lock_home" != /* ]]; then
            log_error "Unable to resolve TARGET_HOME for '${TARGET_USER:-ubuntu}'; export TARGET_HOME explicitly"
            exit 1
        fi
        local _acfs_lock_dir="${ACFS_HOME:-${_acfs_lock_home}/.acfs}"
        mkdir -p "$_acfs_lock_dir" 2>/dev/null || true
        local _acfs_lock_file="$_acfs_lock_dir/.install.lock"
        # NOTE: On bash 5.3+, `exec N>file` under set -e exits the script
        # before `if` can catch the failure. We test in a subshell first,
        # then only exec in the main shell if the subshell succeeded.
        local _acfs_lock_fd=""
        if (exec 199>"$_acfs_lock_file") 2>/dev/null; then
            exec 199>"$_acfs_lock_file"
            _acfs_lock_fd=199
        elif (exec 198>"$_acfs_lock_file") 2>/dev/null; then
            exec 198>"$_acfs_lock_file"
            _acfs_lock_fd=198
        fi
        if [[ -n "$_acfs_lock_fd" ]]; then
            if ! flock -n "$_acfs_lock_fd"; then
                log_error "Another ACFS installer is already running."
                log_error "If you are sure no other installer is running, remove: $_acfs_lock_file"
                exit 1
            fi
        else
            log_warn "Could not acquire install lock (continuing anyway)"
        fi
    fi

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
            else
                base_home="$(acfs_home_for_user "${TARGET_USER:-ubuntu}" || true)"
            fi

            if [[ -z "$base_home" ]]; then
                echo "ERROR: Unable to resolve TARGET_HOME for '${TARGET_USER:-ubuntu}'; export TARGET_HOME explicitly" >&2
                exit 1
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

    # Early dependency bootstrap (issue #152, #180): on a truly fresh Ubuntu,
    # jq and curl may be missing. Install them before anything else so that
    # later phases (state management, JSON parsing, gum install) don't fail.
    # Also covers the case where sudo is available but $SUDO isn't set yet.
    if [[ $EUID -eq 0 ]] || [[ -n "${SUDO:-}" ]] || acfs_early_sudo_binary_path &>/dev/null; then
        local _need_early_apt=false
        acfs_early_system_binary_path curl &>/dev/null || _need_early_apt=true
        acfs_early_system_binary_path jq &>/dev/null   || _need_early_apt=true
        acfs_early_system_binary_path git &>/dev/null   || _need_early_apt=true
        if [[ "$_need_early_apt" == "true" ]]; then
            echo -e "${YELLOW}Installing minimal bootstrap dependencies (curl, jq, git)...${NC}" >&2
            local -a _sudo_cmd=()
            local apt_get_bin=""
            apt_get_bin="$(acfs_early_system_binary_path apt-get 2>/dev/null || true)"
            if [[ -z "$apt_get_bin" ]]; then
                log_warn "apt-get not found; cannot install bootstrap dependencies"
            else
                if [[ $EUID -ne 0 ]]; then
                    local sudo_bin=""
                    sudo_bin="$(acfs_early_sudo_binary_path 2>/dev/null || true)"
                    [[ -n "$sudo_bin" ]] && _sudo_cmd=("$sudo_bin")
                fi
                if [[ $EUID -eq 0 || ${#_sudo_cmd[@]} -gt 0 ]]; then
                    "${_sudo_cmd[@]}" "$apt_get_bin" update -qq 2>/dev/null || true
                    "${_sudo_cmd[@]}" "$apt_get_bin" install -y -qq curl jq git 2>/dev/null || true
                fi
            fi
        fi
    fi

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
    # Skip when --only or --only-phase is specified, since the user
    # is targeting a specific module on an already-installed system.
    if [[ ${#ONLY_MODULES[@]} -eq 0 ]] && [[ ${#ONLY_PHASES[@]} -eq 0 ]]; then
        run_ubuntu_upgrade_phase "$@"
    else
        log_debug "Skipping Ubuntu auto-upgrade (--only/--only-phase mode)"
    fi

    # ============================================================
    # State Management and Resume Logic (mjt.5.8)
    # ============================================================
    # Initialize state file location (uses TARGET_USER's home)
    ACFS_HOME="${ACFS_HOME:-$TARGET_HOME/.acfs}"
    ACFS_STATE_FILE="${ACFS_STATE_FILE:-$ACFS_HOME/state.json}"
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
                show_progress_header "$phase_num" 9 "$phase_name" "$installation_start_time" "$phase_id"
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

        # Send webhook notification if configured (bd-2zqr)
        if type -t webhook_notify &>/dev/null; then
            webhook_notify "success" "${ACFS_SUMMARY_FILE:-}" 2>/dev/null || true
        fi
        # Send ntfy.sh notification if configured (bd-2igt6)
        if type -t acfs_notify_install_success &>/dev/null; then
            acfs_notify_install_success 2>/dev/null || true
        fi

        # Skip the post-install smoke test when --only / --only-phase was
        # used: the user asked for a targeted subset, so the full-stack
        # checks (agents, ntm, onboard, languages, …) will fail by design.
        # They can still run `acfs doctor` if they want a broader health check.
        SMOKE_TEST_FAILED=false
        if [[ ${#ONLY_MODULES[@]} -eq 0 ]] && [[ ${#ONLY_PHASES[@]} -eq 0 ]]; then
            if ! run_smoke_test; then
                SMOKE_TEST_FAILED=true
            fi
        else
            log_debug "Skipping post-install smoke test (--only/--only-phase mode)"
        fi
    fi

    print_summary

    if [[ "${SMOKE_TEST_FAILED:-false}" == "true" ]]; then
        exit 1
    fi
}

main "$@"
