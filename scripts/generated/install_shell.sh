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

# Category: shell
# Modules: 1

# Zsh + Oh My Zsh + Powerlevel10k + plugins + canonical ACFS zshrc
install_shell_zsh() {
    local module_id="shell.zsh"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing shell.zsh"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: sudo apt-get install -y zsh (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_ZSH'
sudo apt-get install -y zsh
INSTALL_SHELL_ZSH
        then
            log_error "shell.zsh: install command failed: sudo apt-get install -y zsh"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: zsh --version"
    else
        if ! {
            zsh --version
        }; then
            log_error "shell.zsh: verify failed: zsh --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: test -f ~/.acfs/zsh/acfs.zshrc"
    else
        if ! {
            test -f ~/.acfs/zsh/acfs.zshrc
        }; then
            log_error "shell.zsh: verify failed: test -f ~/.acfs/zsh/acfs.zshrc"
            return 1
        fi
    fi

    log_success "shell.zsh installed"
}

# Install all shell modules
install_shell() {
    log_section "Installing shell modules"
    install_shell_zsh
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_shell
fi
