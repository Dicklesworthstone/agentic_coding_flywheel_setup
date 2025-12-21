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
#   --reset-state     Delete state file and exit (for debugging)
#   --interactive     Enable interactive prompts for resume decisions
#   --skip-preflight  Skip pre-flight system validation
#   --strict          Treat ALL tools as critical (any checksum mismatch aborts)
#   --list-modules    List available modules and exit
#   --print-plan      Print execution plan and exit (no installs)
# ============================================================

set -euo pipefail

# ============================================================
# Configuration
# ============================================================
ACFS_VERSION="0.1.0"
ACFS_REPO_OWNER="Dicklesworthstone"
ACFS_REPO_NAME="agentic_coding_flywheel_setup"
ACFS_REF="${ACFS_REF:-main}"
ACFS_RAW="https://raw.githubusercontent.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/${ACFS_REF}"
# Note: ACFS_HOME is set after TARGET_HOME is determined
ACFS_LOG_DIR="/var/log/acfs"
# SCRIPT_DIR is empty when running via curl|bash (BASH_SOURCE is unset)
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR=""
fi

# Default options
YES_MODE=false
DRY_RUN=false
PRINT_MODE=false
MODE="vibe"
SKIP_POSTGRES=false
SKIP_VAULT=false
SKIP_CLOUD=false

# Manifest-driven selection options (mjt.5.3)
LIST_MODULES=false
PRINT_PLAN_MODE=false

# Resume/reinstall options (used by state.sh confirm_resume)
export ACFS_FORCE_RESUME=false
export ACFS_FORCE_REINSTALL=false
export ACFS_INTERACTIVE=false
RESET_STATE_ONLY=false

# Preflight options
SKIP_PREFLIGHT=false

# Target user configuration
# When running as root, we install for ubuntu user, not root
TARGET_USER="ubuntu"
TARGET_HOME="/home/$TARGET_USER"

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
# Source context tracking library for try_step() wrapper
# ============================================================
_source_context_lib() {
    # Already loaded?
    if [[ -n "${ACFS_CONTEXT_LOADED:-}" ]]; then
        return 0
    fi

    # Try local file first (when running from repo)
    if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "$SCRIPT_DIR/scripts/lib/context.sh" ]]; then
        # shellcheck source=scripts/lib/context.sh
        source "$SCRIPT_DIR/scripts/lib/context.sh"
        return 0
    fi

    # Try relative path (when running from repo root)
    if [[ -f "./scripts/lib/context.sh" ]]; then
        source "./scripts/lib/context.sh"
        return 0
    fi

    # Download for curl|bash scenario (if curl available)
    if command -v curl &>/dev/null; then
        local tmp_context="/tmp/acfs-context-$$.sh"
        if curl -fsSL "$ACFS_RAW/scripts/lib/context.sh" -o "$tmp_context" 2>/dev/null; then
            source "$tmp_context"
            rm -f "$tmp_context"
            return 0
        fi
    fi

    # Fallback: define minimal no-op stubs so install.sh still works
    set_phase() { :; }
    try_step() { shift; "$@"; }
    try_step_eval() { shift; bash -c "$1"; }
    return 0
}
_source_context_lib

# ACFS Color scheme (Catppuccin Mocha inspired)
ACFS_PRIMARY="#89b4fa"
ACFS_SUCCESS="#a6e3a1"
ACFS_WARNING="#f9e2af"
ACFS_ERROR="#f38ba8"
ACFS_MUTED="#6c7086"

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

    # Quick apt update and gum install (silent unless it fails)
    echo -e "\033[0;90m    → Installing gum for enhanced UI...\033[0m" >&2

    # Add Charm apt repo
    $sudo_cmd mkdir -p /etc/apt/keyrings 2>/dev/null || true
    if curl "${ACFS_CURL_BASE_ARGS[@]}" https://repo.charm.sh/apt/gpg.key 2>/dev/null | \
        $sudo_cmd gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null; then
        echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | \
            $sudo_cmd tee /etc/apt/sources.list.d/charm.list > /dev/null 2>&1
        $sudo_cmd apt-get update -y >/dev/null 2>&1 || true
        if $sudo_cmd apt-get install -y gum >/dev/null 2>&1; then
            HAS_GUM=true
            echo -e "\033[0;32m    ✓ gum installed - enhanced UI enabled!\033[0m" >&2
        fi
    fi
}

# ============================================================
# ASCII Art Banner
# ============================================================
print_banner() {
    local banner='
    ╔═══════════════════════════════════════════════════════════════╗
    ║                                                               ║
    ║     █████╗  ██████╗███████╗███████╗                          ║
    ║    ██╔══██╗██╔════╝██╔════╝██╔════╝                          ║
    ║    ███████║██║     █████╗  ███████╗                          ║
    ║    ██╔══██║██║     ██╔══╝  ╚════██║                          ║
    ║    ██║  ██║╚██████╗██║     ███████║                          ║
    ║    ╚═╝  ╚═╝ ╚═════╝╚═╝     ╚══════╝                          ║
    ║                                                               ║
    ║         Agentic Coding Flywheel Setup v'"$ACFS_VERSION"'              ║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝
'

    if [[ "$HAS_GUM" == "true" ]]; then
        echo "$banner" | gum style --foreground "$ACFS_PRIMARY" --bold >&2
    else
        echo -e "${BLUE}$banner${NC}" >&2
    fi
}

# ============================================================
# Logging functions (with gum enhancement)
# ============================================================
log_step() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_PRIMARY" --bold "[$1]" | tr -d '\n' >&2
        echo -n " " >&2
        gum style "$2" >&2
    else
        echo -e "${BLUE}[$1]${NC} $2" >&2
    fi
}

log_detail() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_MUTED" --margin "0 0 0 4" "→ $1" >&2
    else
        echo -e "${GRAY}    → $1${NC}" >&2
    fi
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
        log_error "  1. Check the log: cat $ACFS_LOG_DIR/install.log"
        log_error "  2. Run: acfs doctor"
        log_error "  3. Re-run this installer (it's safe to run multiple times)"
        log_error ""
    fi
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
            --list-modules)
                LIST_MODULES=true
                shift
                ;;
            --print-plan)
                PRINT_PLAN_MODE=true
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
    echo "Effective modules: ${#ACFS_MODULES_IN_ORDER[@]}"
    echo ""
    echo "Execution order:"
    echo ""

    local idx=1
    local module phase func key
    for module in "${ACFS_MODULES_IN_ORDER[@]}"; do
        # Use key variable to prevent arithmetic evaluation with dots
        key="$module"
        phase="${ACFS_MODULE_PHASE[$key]:-?}"
        func="${ACFS_MODULE_FUNC[$key]:-?}"
        printf "  %2d. [Phase %s] %s -> %s()\n" "$idx" "$phase" "$module" "$func"
        ((idx++))
    done

    echo ""
    echo "Options:"
    echo "  --skip-postgres: $SKIP_POSTGRES"
    echo "  --skip-vault:    $SKIP_VAULT"
    echo "  --skip-cloud:    $SKIP_CLOUD"
    echo ""
    echo "This is a preview. Run without --print-plan to execute."
}

# ============================================================
# Pre-Flight Validation
# ============================================================
# Runs system validation checks before installation begins.
# Related beads: agentic_coding_flywheel_setup-545

run_preflight_checks() {
    log_step "0/10" "Running pre-flight validation..."

    local preflight_script=""

    # Try to find preflight script in different locations
    if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -f "$ACFS_BOOTSTRAP_DIR/scripts/preflight.sh" ]]; then
        preflight_script="$ACFS_BOOTSTRAP_DIR/scripts/preflight.sh"
    elif [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "$SCRIPT_DIR/scripts/preflight.sh" ]]; then
        preflight_script="$SCRIPT_DIR/scripts/preflight.sh"
    elif [[ -f "./scripts/preflight.sh" ]]; then
        preflight_script="./scripts/preflight.sh"
    elif [[ -f "/tmp/acfs-preflight.sh" ]]; then
        preflight_script="/tmp/acfs-preflight.sh"
    else
        # Download preflight script for curl | bash scenario
        log_detail "Downloading preflight script..."
        if acfs_curl "$ACFS_RAW/scripts/preflight.sh" -o /tmp/acfs-preflight.sh 2>/dev/null; then
            chmod +x /tmp/acfs-preflight.sh
            preflight_script="/tmp/acfs-preflight.sh"
        else
            log_warn "Could not download preflight script - skipping checks"
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

    log_success "[0/10] Pre-flight validation passed"
    echo ""
}

ACFS_CURL_BASE_ARGS=(-fsSL)
if curl --help all 2>/dev/null | grep -q -- '--proto'; then
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

bootstrap_repo_archive() {
    if [[ -n "${SCRIPT_DIR:-}" ]]; then
        return 0
    fi

    local ref="$ACFS_REF"
    local archive_url="https://github.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/archive/${ref}.tar.gz"
    local ref_safe="${ref//[^a-zA-Z0-9._-]/_}"
    local tmp_archive
    local tmp_dir

    if ! command_exists tar; then
        log_error "Bootstrap requires tar (install tar or run from a local checkout)"
        return 1
    fi

    tmp_archive="$(mktemp "/tmp/acfs-archive-${ref_safe}.XXXXXX.tar.gz" 2>/dev/null)" || {
        log_error "Failed to create temp file for bootstrap archive"
        return 1
    }

    tmp_dir="$(mktemp -d "/tmp/acfs-bootstrap-${ref_safe}.XXXXXX" 2>/dev/null)" || {
        log_error "Failed to create temp directory for bootstrap extract"
        return 1
    }

    log_step "Bootstrapping ACFS archive (${ref})"
    log_detail "Downloading ${archive_url}"

    if ! acfs_curl_with_retry "$archive_url" "$tmp_archive"; then
        log_error "Failed to download ACFS archive. Try again, or pin ACFS_REF to a tag/sha."
        return 1
    fi

    log_detail "Extracting runtime assets"
    if ! tar -xzf "$tmp_archive" -C "$tmp_dir" --strip-components=1 \
        --wildcards --wildcards-match-slash \
        "*/scripts/lib/**" \
        "*/scripts/generated/**" \
        "*/scripts/preflight.sh" \
        "*/acfs/**" \
        "*/checksums.yaml" \
        "*/acfs.manifest.yaml"; then
        log_error "Failed to extract ACFS bootstrap archive (tar error)"
        return 1
    fi

    if [[ ! -f "$tmp_dir/acfs.manifest.yaml" ]] || [[ ! -f "$tmp_dir/checksums.yaml" ]]; then
        log_error "Bootstrap archive missing required manifest/checksums files"
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
        log_error "Bootstrap validation failed. Retry or pin to a known-good tag/sha."
        return 1
    fi

    local manifest_sha expected_sha
    manifest_sha="$(acfs_calculate_file_sha256 "$tmp_dir/acfs.manifest.yaml")" || return 1
    expected_sha="$(grep -E '^ACFS_MANIFEST_SHA256=' "$tmp_dir/scripts/generated/manifest_index.sh" | head -n 1 | cut -d'=' -f2 | tr -d '\"')"

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
    local allowed_prefixes=("$ACFS_HOME" "$TARGET_HOME" "/data")
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

    if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -f "$ACFS_BOOTSTRAP_DIR/$rel_path" ]]; then
        cp "$ACFS_BOOTSTRAP_DIR/$rel_path" "$dest_path"
    elif [[ -f "$SCRIPT_DIR/$rel_path" ]]; then
        cp "$SCRIPT_DIR/$rel_path" "$dest_path"
    else
        acfs_curl -o "$dest_path" "$ACFS_RAW/$rel_path"
    fi
}

run_as_target() {
    local user="$TARGET_USER"

    # Already the target user
    if [[ "$(whoami)" == "$user" ]]; then
        "$@"
        return $?
    fi

    # Preferred: sudo
    if command_exists sudo; then
        sudo -u "$user" -H "$@"
        return $?
    fi

    # Fallbacks (root-only typically)
    if command_exists runuser; then
        runuser -u "$user" -- "$@"
        return $?
    fi

    su - "$user" -c "$(printf '%q ' "$@")"
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

        local content status
        content="$(
            acfs_curl "$url" 2>/dev/null
            status=$?
            if (( status != 0 )); then
                exit "$status"
            fi
            printf '%s' "$sentinel"
        )"
        status=$?

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

acfs_load_upstream_checksums() {
    if [[ "$ACFS_UPSTREAM_LOADED" == "true" ]]; then
        return 0
    fi

    local content=""
    if [[ -r "$SCRIPT_DIR/checksums.yaml" ]]; then
        content="$(cat "$SCRIPT_DIR/checksums.yaml")"
    else
        content="$(acfs_fetch_url_content "$ACFS_RAW/checksums.yaml")" || {
            log_error "Failed to fetch checksums.yaml from $ACFS_RAW"
            return 1
        }
    fi

    local in_installers=false
    local current_tool=""

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

        if [[ "$line" =~ url:[[:space:]]*\"([^\"]+)\" ]]; then
            ACFS_UPSTREAM_URLS["$current_tool"]="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$line" =~ sha256:[[:space:]]*\"([a-f0-9]{64})\" ]]; then
            ACFS_UPSTREAM_SHA256["$current_tool"]="${BASH_REMATCH[1]}"
            continue
        fi
    done <<< "$content"

    local required_tools=(
        atuin bun bv caam cass claude cm mcp_agent_mail ntm ohmyzsh rust slb ubs uv zoxide
    )
    local missing=false
    local tool
    for tool in "${required_tools[@]}"; do
        if [[ -z "${ACFS_UPSTREAM_URLS[$tool]:-}" ]] || [[ -z "${ACFS_UPSTREAM_SHA256[$tool]:-}" ]]; then
            log_error "checksums.yaml missing entry for '$tool'"
            missing=true
        fi
    done
    if [[ "$missing" == "true" ]]; then
        return 1
    fi

    ACFS_UPSTREAM_LOADED=true
    return 0
}

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

    local content
    content="$(acfs_fetch_url_content "$url")" || return 1

    local actual_sha256
    actual_sha256="$(printf '%s' "$content" | acfs_calculate_sha256)" || return 1

    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        log_error "Security error: checksum mismatch for '$tool'"
        log_detail "URL: $url"
        log_detail "Expected: $expected_sha256"
        log_detail "Actual:   $actual_sha256"
        return 1
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
        TARGET_HOME="$HOME"
    else
        TARGET_HOME="/home/$TARGET_USER"
    fi

    # ACFS directories for target user
    ACFS_HOME="$TARGET_HOME/.acfs"
    ACFS_STATE_FILE="$ACFS_HOME/state.json"

    log_detail "Target user: $TARGET_USER"
    log_detail "Target home: $TARGET_HOME"
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
        log_fatal "Cannot detect OS. This script requires Ubuntu 24.04+ or 25.x"
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    if [[ "$ID" != "ubuntu" ]]; then
        log_warn "This script is designed for Ubuntu but detected: $ID"
        log_warn "Proceeding anyway, but some things may not work."
    fi

    VERSION_MAJOR="${VERSION_ID%%.*}"
    if [[ "$VERSION_MAJOR" -lt 24 ]]; then
        log_warn "Ubuntu $VERSION_ID detected. Recommended: Ubuntu 24.04+ or 25.x"
    fi

    log_detail "OS: Ubuntu $VERSION_ID"
}

ensure_base_deps() {
    set_phase "base_deps" "Base Dependencies" 1
    log_step "1/10" "Checking base dependencies..."

    if [[ "$DRY_RUN" == "true" ]]; then
        local sudo_prefix=""
        if [[ -n "${SUDO:-}" ]]; then
            sudo_prefix="$SUDO "
        fi

        log_detail "dry-run: would run: ${sudo_prefix}apt-get update -y"
        log_detail "dry-run: would install: curl git ca-certificates unzip tar xz-utils jq build-essential sudo gnupg"
        return 0
    fi

    log_detail "Updating apt package index"
    try_step "Updating apt package index" $SUDO apt-get update -y || return 1

    log_detail "Installing base packages"
    try_step "Installing base packages" $SUDO apt-get install -y curl git ca-certificates unzip tar xz-utils jq build-essential sudo gnupg || return 1
}

# ============================================================
# Phase 1: User normalization
# ============================================================
normalize_user() {
    set_phase "normalize_user" "User Normalization" 2
    log_step "2/10" "Normalizing user account..."

    # Create target user if it doesn't exist
    if ! id "$TARGET_USER" &>/dev/null; then
        log_detail "Creating user: $TARGET_USER"
        try_step "Creating user $TARGET_USER" $SUDO useradd -m -s /bin/bash "$TARGET_USER" || true
        try_step "Adding $TARGET_USER to sudo group" $SUDO usermod -aG sudo "$TARGET_USER" || return 1
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

    # Copy SSH keys from root if running as root
    if [[ $EUID -eq 0 ]] && [[ -f /root/.ssh/authorized_keys ]]; then
        log_detail "Copying SSH keys to $TARGET_USER"
        try_step "Creating .ssh directory" $SUDO mkdir -p "$TARGET_HOME/.ssh" || return 1
        try_step "Copying SSH authorized_keys" $SUDO cp /root/.ssh/authorized_keys "$TARGET_HOME/.ssh/" || return 1
        try_step "Setting SSH directory ownership" $SUDO chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.ssh" || return 1
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
    set_phase "setup_filesystem" "Filesystem Setup" 3
    log_step "3/10" "Setting up filesystem..."

    # System directories
    local sys_dirs=("/data/projects" "/data/cache")
    for dir in "${sys_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_detail "Creating: $dir"
            try_step "Creating $dir" $SUDO mkdir -p "$dir" || return 1
        fi
    done

    # Ensure /data is owned by target user
    try_step "Setting /data ownership" $SUDO chown -R "$TARGET_USER:$TARGET_USER" /data || true

    # User directories (in TARGET_HOME, not $HOME)
    local user_dirs=("$TARGET_HOME/Development" "$TARGET_HOME/Projects" "$TARGET_HOME/dotfiles")
    for dir in "${user_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_detail "Creating: $dir"
            try_step "Creating $dir" $SUDO mkdir -p "$dir" || return 1
        fi
    done

    # Create ACFS directories
    try_step "Creating ACFS directories" $SUDO mkdir -p "$ACFS_HOME"/{zsh,tmux,bin,docs,logs} || return 1
    try_step "Setting ACFS directory ownership" $SUDO chown -R "$TARGET_USER:$TARGET_USER" "$ACFS_HOME" || return 1
    try_step "Creating ACFS log directory" $SUDO mkdir -p "$ACFS_LOG_DIR" || return 1

    log_success "Filesystem setup complete"
}

# ============================================================
# Phase 3: Shell setup (zsh + oh-my-zsh + p10k)
# ============================================================
setup_shell() {
    set_phase "setup_shell" "Shell Setup" 4
    log_step "4/10" "Setting up shell..."

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
        log_detail "Oh My Zsh found in /root, copying to $TARGET_USER"
        $SUDO cp -r /root/.oh-my-zsh "$omz_dir"
        $SUDO chown -R "$TARGET_USER:$TARGET_USER" "$omz_dir"
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

    # Create minimal .zshrc loader for target user (backup existing if needed)
    local user_zshrc="$TARGET_HOME/.zshrc"
    if [[ -f "$user_zshrc" ]] && ! grep -q "^# ACFS loader" "$user_zshrc" 2>/dev/null; then
        local backup
        backup="$user_zshrc.pre-acfs.$(date +%Y%m%d%H%M%S)"
        log_warn "Existing .zshrc found; backing up to $(basename "$backup")"
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

    # Set zsh as default shell for target user
    local current_shell
    current_shell=$(getent passwd "$TARGET_USER" | cut -d: -f7)
    if [[ "$current_shell" != *"zsh"* ]]; then
        log_detail "Setting zsh as default shell for $TARGET_USER"
        try_step "Setting zsh as default shell" $SUDO chsh -s "$(which zsh)" "$TARGET_USER" || true
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
    set_phase "install_cli_tools" "CLI Tools" 5
    log_step "5/10" "Installing CLI tools..."

    # Install gum if not already installed (install_gum_early may have skipped
    # if curl/gpg weren't available at that point)
    if command_exists gum; then
        log_detail "gum already installed"
    else
        log_detail "Installing gum for glamorous shell scripts"
        try_step "Creating apt keyrings directory" $SUDO mkdir -p /etc/apt/keyrings || true
        try_step_eval "Adding Charm apt key" "acfs_curl https://repo.charm.sh/apt/gpg.key | $SUDO gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null" || true
        try_step_eval "Adding Charm apt repo" "echo 'deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *' | $SUDO tee /etc/apt/sources.list.d/charm.list > /dev/null" || true
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

    log_detail "Installing optional apt packages"
    try_step "Installing optional apt packages" $SUDO apt-get install -y \
        lsd eza bat fd-find btop dust neovim \
        docker.io docker-compose-plugin || true

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
                if acfs_curl "$lg_url" -o /tmp/lazygit.tar.gz 2>/dev/null; then
                    $SUDO tar -xzf /tmp/lazygit.tar.gz -C /usr/local/bin lazygit
                    rm -f /tmp/lazygit.tar.gz
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
            if acfs_curl "$ld_url" -o /tmp/lazydocker.tar.gz 2>/dev/null; then
                $SUDO tar -xzf /tmp/lazydocker.tar.gz -C /usr/local/bin lazydocker
                rm -f /tmp/lazydocker.tar.gz
            fi
        fi
    fi

    # Add user to docker group
    try_step "Adding $TARGET_USER to docker group" $SUDO usermod -aG docker "$TARGET_USER" || true

    log_success "CLI tools installed"
}

# ============================================================
# Phase 5: Language runtimes
# ============================================================
install_languages() {
    set_phase "install_languages" "Language Runtimes" 6
    log_step "6/10" "Installing language runtimes..."

    # Bun (install as target user)
    local bun_bin="$TARGET_HOME/.bun/bin/bun"
    if [[ ! -x "$bun_bin" ]]; then
        log_detail "Installing Bun for $TARGET_USER"
        try_step "Installing Bun" acfs_run_verified_upstream_script_as_target "bun" "bash" || return 1
    fi

    # Rust (install as target user)
    local cargo_bin="$TARGET_HOME/.cargo/bin/cargo"
    if [[ ! -x "$cargo_bin" ]]; then
        log_detail "Installing Rust for $TARGET_USER"
        try_step "Installing Rust" acfs_run_verified_upstream_script_as_target "rust" "sh" -y || return 1
    fi

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

    log_success "Language runtimes installed"
}

# ============================================================
# Phase 6: Coding agents
# ============================================================
install_agents() {
    set_phase "install_agents" "Coding Agents" 7
    log_step "7/10" "Installing coding agents..."

    # Use target user's bun
    local bun_bin="$TARGET_HOME/.bun/bin/bun"

    if [[ ! -x "$bun_bin" ]]; then
        log_warn "Bun not found at $bun_bin, skipping agent CLI installation"
        return 0
    fi

    # Claude Code (install as target user)
    local claude_bin_local="$TARGET_HOME/.local/bin/claude"
    local claude_bin_bun="$TARGET_HOME/.bun/bin/claude"
    if [[ -x "$claude_bin_local" ]]; then
        log_detail "Claude Code already installed ($claude_bin_local)"
    elif [[ -x "$claude_bin_bun" ]]; then
        log_detail "Claude Code already installed ($claude_bin_bun)"
    else
        log_detail "Installing Claude Code (native) for $TARGET_USER"
        try_step "Installing Claude Code" acfs_run_verified_upstream_script_as_target "claude" "bash" stable || log_warn "Claude Code installation failed"
    fi

    # Codex CLI (install as target user)
    log_detail "Installing Codex CLI for $TARGET_USER"
    try_step "Installing Codex CLI" run_as_target "$bun_bin" install -g @openai/codex@latest || true

    # Gemini CLI (install as target user)
    log_detail "Installing Gemini CLI for $TARGET_USER"
    try_step "Installing Gemini CLI" run_as_target "$bun_bin" install -g @google/gemini-cli@latest || true

    log_success "Coding agents installed"
}

# ============================================================
# Phase 7: Cloud & database tools
# ============================================================
install_cloud_db() {
    set_phase "install_cloud_db" "Cloud & Database Tools" 8
    log_step "8/10" "Installing cloud & database tools..."

    local codename="noble"
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        codename="${VERSION_CODENAME:-noble}"
    fi

    # PostgreSQL 18 (via PGDG)
    if [[ "$SKIP_POSTGRES" == "true" ]]; then
        log_detail "Skipping PostgreSQL (--skip-postgres)"
    elif command_exists psql; then
        log_detail "PostgreSQL already installed ($(psql --version 2>/dev/null | head -1 || echo 'psql'))"
    else
        log_detail "Installing PostgreSQL 18 (PGDG repo, codename=$codename)"
        try_step "Creating apt keyrings for PostgreSQL" $SUDO mkdir -p /etc/apt/keyrings || true

        if ! try_step_eval "Adding PostgreSQL apt key" "acfs_curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | $SUDO gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg 2>/dev/null"; then
            log_warn "PostgreSQL: failed to install signing key (skipping)"
        else
            try_step_eval "Adding PostgreSQL apt repo" "echo 'deb [signed-by=/etc/apt/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt ${codename}-pgdg main' | $SUDO tee /etc/apt/sources.list.d/pgdg.list > /dev/null" || true

            try_step "Updating apt cache for PostgreSQL" $SUDO apt-get update -y || log_warn "PostgreSQL: apt-get update failed (continuing)"

            if try_step "Installing PostgreSQL 18" $SUDO apt-get install -y postgresql-18 postgresql-client-18; then
                log_success "PostgreSQL 18 installed"

                # Best-effort service start (containers may not have systemd)
                if command_exists systemctl; then
                    try_step "Enabling PostgreSQL service" $SUDO systemctl enable postgresql || true
                    try_step "Starting PostgreSQL service" $SUDO systemctl start postgresql || true
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

    # Vault (HashiCorp apt repo)
    if [[ "$SKIP_VAULT" == "true" ]]; then
        log_detail "Skipping Vault (--skip-vault)"
    elif command_exists vault; then
        log_detail "Vault already installed ($(vault --version 2>/dev/null | head -1 || echo 'vault'))"
    else
        log_detail "Installing Vault (HashiCorp repo, codename=$codename)"
        try_step "Creating apt keyrings for Vault" $SUDO mkdir -p /etc/apt/keyrings || true

        if ! try_step_eval "Adding HashiCorp apt key" "acfs_curl https://apt.releases.hashicorp.com/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg 2>/dev/null"; then
            log_warn "Vault: failed to install signing key (skipping)"
        else
            try_step_eval "Adding HashiCorp apt repo" "echo 'deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com ${codename} main' | $SUDO tee /etc/apt/sources.list.d/hashicorp.list > /dev/null" || true

            try_step "Updating apt cache for Vault" $SUDO apt-get update -y || log_warn "Vault: apt-get update failed (continuing)"
            if try_step "Installing Vault" $SUDO apt-get install -y vault; then
                log_success "Vault installed"
            else
                log_warn "Vault: installation failed (optional)"
            fi
        fi
    fi

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
                if [[ -x "$TARGET_HOME/.bun/bin/$cli" ]]; then
                    log_detail "$cli already installed"
                    continue
                fi

                log_detail "Installing $cli via bun"
                if try_step "Installing $cli via bun" run_as_target "$bun_bin" install -g "${cli}@latest"; then
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

install_stack() {
    set_phase "install_stack" "Dicklesworthstone Stack" 9
    log_step "9/10" "Installing Dicklesworthstone stack..."

    # NTM (Named Tmux Manager)
    if binary_installed "ntm"; then
        log_detail "NTM already installed"
    else
        log_detail "Installing NTM"
        try_step "Installing NTM" acfs_run_verified_upstream_script_as_target "ntm" "bash" || log_warn "NTM installation may have failed"
    fi

    # MCP Agent Mail (check for mcp-agent-mail stub or mcp_agent_mail directory)
    if binary_installed "mcp-agent-mail" || [[ -d "$TARGET_HOME/mcp_agent_mail" ]]; then
        log_detail "MCP Agent Mail already installed"
    else
        log_detail "Installing MCP Agent Mail"
        try_step "Installing MCP Agent Mail" acfs_run_verified_upstream_script_as_target "mcp_agent_mail" "bash" --yes || log_warn "MCP Agent Mail installation may have failed"
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

    log_success "Dicklesworthstone stack installed"
}

# ============================================================
# Phase 9: Final wiring
# ============================================================
finalize() {
    set_phase "finalize" "Final Wiring" 10
    log_step "10/10" "Finalizing installation..."

    # Copy tmux config
    log_detail "Installing tmux config"
    try_step "Installing tmux config" install_asset "acfs/tmux/tmux.conf" "$ACFS_HOME/tmux/tmux.conf" || return 1
    try_step "Setting tmux config ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/tmux/tmux.conf" || return 1

    # Link to target user's tmux.conf if it doesn't exist
    if [[ ! -f "$TARGET_HOME/.tmux.conf" ]]; then
        try_step "Linking tmux.conf" run_as_target ln -sf "$ACFS_HOME/tmux/tmux.conf" "$TARGET_HOME/.tmux.conf" || return 1
    fi

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
    )
    local lesson
    for lesson in "${lesson_files[@]}"; do
        install_asset "acfs/onboard/lessons/$lesson" "$ACFS_HOME/onboard/lessons/$lesson"
    done

    log_detail "Installing onboard command"
    try_step "Installing onboard script" install_asset "packages/onboard/onboard.sh" "$ACFS_HOME/onboard/onboard.sh" || return 1
    try_step "Setting onboard permissions" $SUDO chmod 755 "$ACFS_HOME/onboard/onboard.sh" || return 1
    try_step "Setting onboard ownership" $SUDO chown -R "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/onboard" || return 1

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

    # Install acfs-update wrapper command
    try_step "Installing acfs-update" install_asset "scripts/acfs-update" "$ACFS_HOME/bin/acfs-update" || return 1
    try_step "Setting acfs-update permissions" $SUDO chmod 755 "$ACFS_HOME/bin/acfs-update" || return 1
    try_step "Setting acfs-update ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/bin/acfs-update" || return 1
    try_step "Linking acfs-update command" run_as_target ln -sf "$ACFS_HOME/bin/acfs-update" "$TARGET_HOME/.local/bin/acfs-update" || return 1

    # Install services-setup wizard
    try_step "Installing services-setup.sh" install_asset "scripts/services-setup.sh" "$ACFS_HOME/scripts/services-setup.sh" || return 1
    try_step "Setting scripts permissions" $SUDO chmod 755 "$ACFS_HOME/scripts/services-setup.sh" || return 1
    try_step "Setting lib scripts permissions" $SUDO chmod 755 "$ACFS_HOME/scripts/lib/"*.sh || return 1
    try_step "Setting scripts ownership" $SUDO chown -R "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/scripts" || return 1

    # Install checksums + version metadata so `acfs update --stack` can verify upstream scripts.
    try_step "Installing checksums.yaml" install_asset "checksums.yaml" "$ACFS_HOME/checksums.yaml" || return 1
    try_step "Installing VERSION" install_asset "VERSION" "$ACFS_HOME/VERSION" || return 1
    try_step "Setting metadata ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/checksums.yaml" "$ACFS_HOME/VERSION" || true

    # Legacy: Install doctor as acfs binary (for backwards compat)
    try_step "Installing acfs CLI" install_asset "scripts/lib/doctor.sh" "$ACFS_HOME/bin/acfs" || return 1
    try_step "Setting acfs permissions" $SUDO chmod 755 "$ACFS_HOME/bin/acfs" || return 1
    try_step "Setting acfs ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/bin/acfs" || return 1
    try_step "Linking acfs command" run_as_target ln -sf "$ACFS_HOME/bin/acfs" "$TARGET_HOME/.local/bin/acfs" || return 1

    # Install Claude destructive-command guard hook automatically.
    #
    # This is especially important because ACFS config includes "dangerous mode"
    # aliases (e.g., `cc`) that can run commands without interactive approvals.
    log_detail "Installing Claude Git Safety Guard (PreToolUse hook)"
    try_step_eval "Installing Claude Git Safety Guard" \
        "TARGET_USER='$TARGET_USER' TARGET_HOME='$TARGET_HOME' '$ACFS_HOME/scripts/services-setup.sh' --install-claude-guard --yes" || \
        log_warn "Claude Git Safety Guard installation failed (optional)"

    # Create state file
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

    log_success "Installation complete!"
}

# ============================================================
# Post-install smoke test
# Runs quick, automatic verification at the end of install.sh
# ============================================================
_smoke_run_as_target() {
    local cmd="$1"

    if [[ "$(whoami)" == "$TARGET_USER" ]]; then
        bash -lc "$cmd"
        return $?
    fi

    if command_exists sudo; then
        sudo -u "$TARGET_USER" -H bash -lc "$cmd"
        return $?
    fi

    # Fallback: use su if sudo isn't available
    su - "$TARGET_USER" -c "bash -lc $(printf %q "$cmd")"
}

run_smoke_test() {
    local critical_total=8
    local critical_passed=0
    local critical_failed=0
    local warnings=0

    echo "" >&2
    echo "[Smoke Test]" >&2

    # 1) User is ubuntu
    if [[ "$TARGET_USER" == "ubuntu" ]] && id "$TARGET_USER" &>/dev/null; then
        echo "✅ User: ubuntu" >&2
        ((critical_passed += 1))
    else
        echo "✖ User: expected ubuntu (TARGET_USER=$TARGET_USER)" >&2
        echo "    Fix: set TARGET_USER=ubuntu and ensure the user exists" >&2
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
    [[ -x "$TARGET_HOME/.local/bin/uv" ]] || missing_lang+=("uv")
    [[ -x "$TARGET_HOME/.cargo/bin/cargo" ]] || missing_lang+=("cargo")
    command_exists go || missing_lang+=("go")
    if [[ ${#missing_lang[@]} -eq 0 ]]; then
        echo "✅ Languages: bun, uv, cargo, go available" >&2
        ((critical_passed += 1))
    else
        echo "✖ Languages: missing ${missing_lang[*]}" >&2
        echo "    Fix: re-run installer (phase 5) and check $ACFS_LOG_DIR/install.log" >&2
        ((critical_failed += 1))
    fi

    # 6) claude, codex, gemini commands exist
    local missing_agents=()
    [[ -x "$TARGET_HOME/.bun/bin/claude" ]] || missing_agents+=("claude")
    [[ -x "$TARGET_HOME/.bun/bin/codex" ]] || missing_agents+=("codex")
    [[ -x "$TARGET_HOME/.bun/bin/gemini" ]] || missing_agents+=("gemini")
    if [[ ${#missing_agents[@]} -eq 0 ]]; then
        echo "✅ Agents: claude, codex, gemini" >&2
        ((critical_passed += 1))
    else
        echo "✖ Agents: missing ${missing_agents[*]}" >&2
        echo "    Fix: re-run installer (phase 6) to install agent CLIs" >&2
        ((critical_failed += 1))
    fi

    # 7) ntm command works
    if _smoke_run_as_target "command -v ntm >/dev/null && ntm --help >/dev/null 2>&1"; then
        echo "✅ NTM: working" >&2
        ((critical_passed += 1))
    else
        echo "✖ NTM: not working" >&2
        echo "    Fix: re-run installer (phase 8) and check $ACFS_LOG_DIR/install.log" >&2
        ((critical_failed += 1))
    fi

    # 8) onboard command exists
    if [[ -x "$TARGET_HOME/.local/bin/onboard" ]]; then
        echo "✅ Onboard: installed" >&2
        ((critical_passed += 1))
    else
        echo "✖ Onboard: missing" >&2
        echo "    Fix: re-run installer (phase 9) or install onboard to $TARGET_HOME/.local/bin/onboard" >&2
        ((critical_failed += 1))
    fi

    # Non-critical: Agent Mail server can start
    if [[ -x "$TARGET_HOME/mcp_agent_mail/scripts/run_server_with_token.sh" ]]; then
        echo "✅ Agent Mail: installed (run 'am' to start)" >&2
    else
        echo "⚠️ Agent Mail: not installed (re-run installer phase 8)" >&2
        ((warnings += 1))
    fi

    # Non-critical: Stack tools respond to --help
    local stack_help_fail=()
    local stack_tools=(ntm ubs bv cass cm caam slb)
    for tool in "${stack_tools[@]}"; do
        if ! _smoke_run_as_target "command -v $tool >/dev/null && $tool --help >/dev/null 2>&1"; then
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
    elif command_exists systemctl && systemctl is-active --quiet postgresql 2>/dev/null; then
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
        [[ -x "$TARGET_HOME/.bun/bin/wrangler" ]] || missing_cloud+=("wrangler")
        [[ -x "$TARGET_HOME/.bun/bin/supabase" ]] || missing_cloud+=("supabase")
        [[ -x "$TARGET_HOME/.bun/bin/vercel" ]] || missing_cloud+=("vercel")

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

    local summary_content="Version: $ACFS_VERSION
Mode:    $MODE

Next steps:

  1. If you logged in as root, reconnect as ubuntu:
     exit
     ssh ubuntu@YOUR_SERVER_IP

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
            echo -e "${YELLOW}Next steps:${NC}"
            echo ""
            echo "  1. If you logged in as root, reconnect as ubuntu:"
            echo -e "     ${GRAY}exit${NC}"
            echo -e "     ${GRAY}ssh ubuntu@YOUR_SERVER_IP${NC}"
            echo ""
            echo "  2. Run the onboarding tutorial:"
            echo -e "     ${BLUE}onboard${NC}"
            echo ""
            echo "  3. Check everything is working:"
            echo -e "     ${BLUE}acfs doctor${NC}"
            echo ""
            echo "  4. Start your agent cockpit:"
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

    if [[ -z "${SCRIPT_DIR:-}" ]]; then
        bootstrap_repo_archive
    fi

    # Detect environment and source manifest index (mjt.5.3)
    # This must happen BEFORE any handlers that need module data
    detect_environment

    # Handle --list-modules: print available modules and exit (mjt.5.3)
    if [[ "$LIST_MODULES" == "true" ]]; then
        list_modules
        exit 0
    fi

    # Handle --print-plan: print execution plan and exit (mjt.5.3)
    if [[ "$PRINT_PLAN_MODE" == "true" ]]; then
        print_execution_plan
        exit 0
    fi

    # Handle --reset-state: just delete state file and exit
    if [[ "$RESET_STATE_ONLY" == "true" ]]; then
        echo "Resetting ACFS state..." >&2
        local state_file="${ACFS_HOME:-/home/${TARGET_USER}/.acfs}/state.json"
        if [[ -f "$state_file" ]]; then
            rm -f "$state_file"
            echo "State file deleted: $state_file" >&2
        else
            echo "No state file found at: $state_file" >&2
        fi
        exit 0
    fi

    # Install gum FIRST so the entire script looks amazing
    install_gum_early

    # Print beautiful ASCII banner (now with gum if available!)
    print_banner

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run mode - no changes will be made"
        echo ""
    fi

    # Run pre-flight validation (Phase 0)
    if [[ "$SKIP_PREFLIGHT" != "true" ]]; then
        run_preflight_checks
    fi

    if [[ "$PRINT_MODE" == "true" ]]; then
        echo "The following tools will be installed from upstream:"
        echo ""
        echo "  - Oh My Zsh: https://ohmyz.sh"
        echo "  - Powerlevel10k: https://github.com/romkatv/powerlevel10k"
        echo "  - Bun: https://bun.sh"
        echo "  - Rust: https://rustup.rs"
        echo "  - uv: https://astral.sh/uv"
        echo "  - Atuin: https://atuin.sh"
        echo "  - Zoxide: https://github.com/ajeetdsouza/zoxide"
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
    validate_target_user
    init_target_paths
    ensure_ubuntu
    confirm_or_exit
    ensure_base_deps

    if [[ "$DRY_RUN" != "true" ]]; then
        normalize_user
        setup_filesystem
        setup_shell
        install_cli_tools
        install_languages
        install_agents
        install_cloud_db
        install_stack
        finalize

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
