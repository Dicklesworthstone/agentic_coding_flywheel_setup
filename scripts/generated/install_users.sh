#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================

set -euo pipefail

# Ensure logging functions available
ACFS_GENERATED_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# When running a generated installer directly (not sourced by install.sh),
# set sane defaults and derive ACFS paths from the script location so
# contract validation passes and local assets are discoverable.
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    # Match install.sh defaults
    if [[ -z "${TARGET_USER:-}" ]]; then
        if [[ $EUID -eq 0 ]] && [[ -z "${SUDO_USER:-}" ]]; then
            _ACFS_DETECTED_USER="ubuntu"
        else
            _ACFS_DETECTED_USER="${SUDO_USER:-$(whoami)}"
        fi
        TARGET_USER="$_ACFS_DETECTED_USER"
    fi
    unset _ACFS_DETECTED_USER
    MODE="${MODE:-vibe}"

    if [[ -z "${TARGET_HOME:-}" ]]; then
        if [[ "${TARGET_USER}" == "root" ]]; then
            TARGET_HOME="/root"
        elif [[ "$(whoami 2>/dev/null || true)" == "${TARGET_USER}" ]]; then
            TARGET_HOME="${HOME}"
        else
            TARGET_HOME="/home/${TARGET_USER}"
        fi
    fi

    # Derive "bootstrap" paths from the repo layout (scripts/generated/.. -> repo root).
    if [[ -z "${ACFS_BOOTSTRAP_DIR:-}" ]]; then
        ACFS_BOOTSTRAP_DIR="$(cd "$ACFS_GENERATED_SCRIPT_DIR/../.." && pwd)"
    fi

    ACFS_LIB_DIR="${ACFS_LIB_DIR:-$ACFS_BOOTSTRAP_DIR/scripts/lib}"
    ACFS_GENERATED_DIR="${ACFS_GENERATED_DIR:-$ACFS_BOOTSTRAP_DIR/scripts/generated}"
    ACFS_ASSETS_DIR="${ACFS_ASSETS_DIR:-$ACFS_BOOTSTRAP_DIR/acfs}"
    ACFS_CHECKSUMS_YAML="${ACFS_CHECKSUMS_YAML:-$ACFS_BOOTSTRAP_DIR/checksums.yaml}"
    ACFS_MANIFEST_YAML="${ACFS_MANIFEST_YAML:-$ACFS_BOOTSTRAP_DIR/acfs.manifest.yaml}"

    export TARGET_USER TARGET_HOME MODE
    export ACFS_BOOTSTRAP_DIR ACFS_LIB_DIR ACFS_GENERATED_DIR ACFS_ASSETS_DIR ACFS_CHECKSUMS_YAML ACFS_MANIFEST_YAML
fi
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh"
else
    # Fallback logging functions if logging.sh not found
    # Progress/status output should go to stderr so stdout stays clean for piping.
    log_step() { echo "[*] $*" >&2; }
    log_section() { echo "" >&2; echo "=== $* ===" >&2; }
    log_success() { echo "[OK] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_info() { echo "    $*" >&2; }
fi

# Source install helpers (run_as_*_shell, selection helpers)
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh"
fi

# Source contract validation
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/contract.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/contract.sh"
fi

# Optional security verification for upstream installer scripts.
# Scripts that need it should call: acfs_security_init
ACFS_SECURITY_READY=false
acfs_security_init() {
    if [[ "${ACFS_SECURITY_READY}" = "true" ]]; then
        return 0
    fi

    local security_lib="$ACFS_GENERATED_SCRIPT_DIR/../lib/security.sh"
    if [[ ! -f "$security_lib" ]]; then
        log_error "Security library not found: $security_lib"
        return 1
    fi

    # Use ACFS_CHECKSUMS_YAML if set by install.sh bootstrap (overrides security.sh default)
    if [[ -n "${ACFS_CHECKSUMS_YAML:-}" ]]; then
        export CHECKSUMS_FILE="${ACFS_CHECKSUMS_YAML}"
    fi

    # shellcheck source=../lib/security.sh
    # shellcheck disable=SC1091  # runtime relative source
    source "$security_lib"
    load_checksums || { log_error "Failed to load checksums.yaml"; return 1; }
    ACFS_SECURITY_READY=true
    return 0
}

# Category: users
# Modules: 1

# Ensure target user + passwordless sudo + ssh keys
install_users_ubuntu() {
    local module_id="users.ubuntu"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing users.ubuntu"


    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: id \"\${TARGET_USER:-ubuntu}\" (root)"
    else
        if ! run_as_root_shell <<'INSTALL_USERS_UBUNTU'
id "${TARGET_USER:-ubuntu}"
INSTALL_USERS_UBUNTU
        then
            log_error "users.ubuntu: verify failed: id \"\${TARGET_USER:-ubuntu}\""
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: [[ \"\${MODE:-vibe}\" != \"vibe\" ]] || runuser -u \"\${TARGET_USER:-ubuntu}\" -- sudo -n true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_USERS_UBUNTU'
[[ "${MODE:-vibe}" != "vibe" ]] || runuser -u "${TARGET_USER:-ubuntu}" -- sudo -n true
INSTALL_USERS_UBUNTU
        then
            log_error "users.ubuntu: verify failed: [[ \"\${MODE:-vibe}\" != \"vibe\" ]] || runuser -u \"\${TARGET_USER:-ubuntu}\" -- sudo -n true"
            return 1
        fi
    fi

    log_success "users.ubuntu installed"
}

# Install all users modules
install_users() {
    log_section "Installing users modules"
    install_users_ubuntu
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    install_users
fi
