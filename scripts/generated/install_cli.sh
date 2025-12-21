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

# Category: cli
# Modules: 1

# Modern CLI tools referenced by the zshrc intent
install_cli_modern() {
    local module_id="cli.modern"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing cli.modern"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: apt-get install -y ripgrep tmux fzf direnv jq gh git-lfs lsof dnsutils netcat-openbsd strace rsync (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get install -y ripgrep tmux fzf direnv jq gh git-lfs lsof dnsutils netcat-openbsd strace rsync
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get install -y ripgrep tmux fzf direnv jq gh git-lfs lsof dnsutils netcat-openbsd strace rsync"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: apt-get install -y lsd || true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get install -y lsd || true
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get install -y lsd || true"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: apt-get install -y eza || true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get install -y eza || true
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get install -y eza || true"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: apt-get install -y bat || apt-get install -y batcat || true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get install -y bat || apt-get install -y batcat || true
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get install -y bat || apt-get install -y batcat || true"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: apt-get install -y fd-find || true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get install -y fd-find || true
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get install -y fd-find || true"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: apt-get install -y btop || true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get install -y btop || true
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get install -y btop || true"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: apt-get install -y dust || true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get install -y dust || true
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get install -y dust || true"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: apt-get install -y neovim || true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get install -y neovim || true
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get install -y neovim || true"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: apt-get install -y docker.io docker-compose-plugin || true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get install -y docker.io docker-compose-plugin || true
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get install -y docker.io docker-compose-plugin || true"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: apt-get install -y lazygit || true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get install -y lazygit || true
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get install -y lazygit || true"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: apt-get install -y lazydocker || true (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get install -y lazydocker || true
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get install -y lazydocker || true"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: rg --version"
    else
        if ! {
            rg --version
        }; then
            log_error "cli.modern: verify failed: rg --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: tmux -V"
    else
        if ! {
            tmux -V
        }; then
            log_error "cli.modern: verify failed: tmux -V"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: fzf --version"
    else
        if ! {
            fzf --version
        }; then
            log_error "cli.modern: verify failed: fzf --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: gh --version"
    else
        if ! {
            gh --version
        }; then
            log_error "cli.modern: verify failed: gh --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: git-lfs version"
    else
        if ! {
            git-lfs version
        }; then
            log_error "cli.modern: verify failed: git-lfs version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: rsync --version"
    else
        if ! {
            rsync --version
        }; then
            log_error "cli.modern: verify failed: rsync --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: strace --version"
    else
        if ! {
            strace --version
        }; then
            log_error "cli.modern: verify failed: strace --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: command -v lsof"
    else
        if ! {
            command -v lsof
        }; then
            log_error "cli.modern: verify failed: command -v lsof"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: command -v dig"
    else
        if ! {
            command -v dig
        }; then
            log_error "cli.modern: verify failed: command -v dig"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: command -v nc"
    else
        if ! {
            command -v nc
        }; then
            log_error "cli.modern: verify failed: command -v nc"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify (optional): command -v lsd || command -v eza"
    else
        if ! {
            command -v lsd || command -v eza
        }; then
            log_warn "Optional verify failed: cli.modern"
        fi
    fi

    log_success "cli.modern installed"
}

# Install all cli modules
install_cli() {
    log_section "Installing cli modules"
    install_cli_modern
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_cli
fi
