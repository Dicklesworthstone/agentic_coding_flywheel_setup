#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================

set -euo pipefail

# Ensure logging functions available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../lib/logging.sh" ]]; then
    source "$SCRIPT_DIR/../lib/logging.sh"
else
    # Fallback logging functions if logging.sh not found
    log_step() { echo "[*] $*"; }
    log_section() { echo ""; echo "=== $* ==="; }
    log_success() { echo "[OK] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_info() { echo "    $*"; }
fi

# Source install helpers (run_as_*_shell, selection helpers)
if [[ -f "$SCRIPT_DIR/../lib/install_helpers.sh" ]]; then
    source "$SCRIPT_DIR/../lib/install_helpers.sh"
fi

# Optional security verification for upstream installer scripts.
# Scripts that need it should call: acfs_security_init
ACFS_SECURITY_READY=false
acfs_security_init() {
    if [[ "${ACFS_SECURITY_READY}" == "true" ]]; then
        return 0
    fi

    local security_lib="$SCRIPT_DIR/../lib/security.sh"
    if [[ ! -f "$security_lib" ]]; then
        log_error "Security library not found: $security_lib"
        return 1
    fi

    # shellcheck source=../lib/security.sh
    # shellcheck disable=SC1091  # runtime relative source
    source "$security_lib"
    load_checksums || { log_error "Failed to load checksums.yaml"; return 1; }
    ACFS_SECURITY_READY=true
    return 0
}

# Category: acfs
# Modules: 2

# Onboarding TUI tutorial
install_acfs_onboard() {
    local module_id="acfs.onboard"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing acfs.onboard"


    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: onboard --help || command -v onboard"
    else
        if ! {
            onboard --help || command -v onboard
        }; then
            log_error "acfs.onboard: verify failed: onboard --help || command -v onboard"
            return 1
        fi
    fi

    log_success "acfs.onboard installed"
}

# ACFS doctor command for health checks
install_acfs_doctor() {
    local module_id="acfs.doctor"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing acfs.doctor"


    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: acfs doctor --help || command -v acfs"
    else
        if ! {
            acfs doctor --help || command -v acfs
        }; then
            log_error "acfs.doctor: verify failed: acfs doctor --help || command -v acfs"
            return 1
        fi
    fi

    log_success "acfs.doctor installed"
}

# Install all acfs modules
install_acfs() {
    log_section "Installing acfs modules"
    install_acfs_onboard
    install_acfs_doctor
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_acfs
fi
