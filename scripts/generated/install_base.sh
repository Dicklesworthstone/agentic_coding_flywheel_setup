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

# Category: base
# Modules: 2

# Base packages + sane defaults
install_base_system() {
    local module_id="base.system"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing base.system"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: apt-get update -y (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_SYSTEM'
apt-get update -y
INSTALL_BASE_SYSTEM
        then
            log_error "base.system: install command failed: apt-get update -y"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: apt-get install -y curl git ca-certificates unzip tar xz-utils jq build-essential (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_SYSTEM'
apt-get install -y curl git ca-certificates unzip tar xz-utils jq build-essential
INSTALL_BASE_SYSTEM
        then
            log_error "base.system: install command failed: apt-get install -y curl git ca-certificates unzip tar xz-utils jq build-essential"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: curl --version"
    else
        if ! {
            curl --version
        }; then
            log_error "base.system: verify failed: curl --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: git --version"
    else
        if ! {
            git --version
        }; then
            log_error "base.system: verify failed: git --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: jq --version"
    else
        if ! {
            jq --version
        }; then
            log_error "base.system: verify failed: jq --version"
            return 1
        fi
    fi

    log_success "base.system installed"
}

# Create workspace and ACFS directories
install_base_filesystem() {
    local module_id="base.filesystem"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing base.filesystem"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: mkdir -p /data/projects /data/cache (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_FILESYSTEM'
mkdir -p /data/projects /data/cache
INSTALL_BASE_FILESYSTEM
        then
            log_error "base.filesystem: install command failed: mkdir -p /data/projects /data/cache"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: chown -R ubuntu:ubuntu /data (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_FILESYSTEM'
chown -R ubuntu:ubuntu /data
INSTALL_BASE_FILESYSTEM
        then
            log_error "base.filesystem: install command failed: chown -R ubuntu:ubuntu /data"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: test -d /data/projects"
    else
        if ! {
            test -d /data/projects
        }; then
            log_error "base.filesystem: verify failed: test -d /data/projects"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: test -d ~/.acfs"
    else
        if ! {
            test -d ~/.acfs
        }; then
            log_error "base.filesystem: verify failed: test -d ~/.acfs"
            return 1
        fi
    fi

    log_success "base.filesystem installed"
}

# Install all base modules
install_base() {
    log_section "Installing base modules"
    install_base_system
    install_base_filesystem
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_base
fi
