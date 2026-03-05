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
    TARGET_USER="${TARGET_USER:-ubuntu}"
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

# Category: cli
# Modules: 1

# Modern CLI tools referenced by the zshrc intent
install_cli_modern() {
    local module_id="cli.modern"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing cli.modern"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: apt-get install -y ripgrep tmux fzf direnv jq gh git-lfs lsof dnsutils netcat-openbsd strace rsync zstd cosign (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
apt-get install -y ripgrep tmux fzf direnv jq gh git-lfs lsof dnsutils netcat-openbsd strace rsync zstd cosign
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: install command failed: apt-get install -y ripgrep tmux fzf direnv jq gh git-lfs lsof dnsutils netcat-openbsd strace rsync zstd cosign"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: rg --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
rg --version
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: rg --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: tmux -V (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
tmux -V
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: tmux -V"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: fzf --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
fzf --version
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: fzf --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: gh --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
gh --version
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: gh --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: git-lfs version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
git-lfs version
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: git-lfs version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: rsync --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
rsync --version
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: rsync --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: strace --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
strace --version
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: strace --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: command -v lsof (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
command -v lsof
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: command -v lsof"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: command -v dig (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
command -v dig
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: command -v dig"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: command -v nc (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
command -v nc
INSTALL_CLI_MODERN
        then
            log_error "cli.modern: verify failed: command -v nc"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): command -v lsd || command -v eza (root)"
    else
        if ! run_as_root_shell <<'INSTALL_CLI_MODERN'
command -v lsd || command -v eza
INSTALL_CLI_MODERN
        then
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
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    install_cli
fi
