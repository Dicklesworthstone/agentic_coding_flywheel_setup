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

# Category: filesystem
# Modules: 1

# Create workspace and ACFS directories
install_base_filesystem() {
    local module_id="base.filesystem"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing base.filesystem"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: # Hardening: refuse to operate on symlinked workspace paths. (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_FILESYSTEM'
# Hardening: refuse to operate on symlinked workspace paths.
# Prevents symlink tricks like /data -> / or /data/projects -> /etc.
for p in /data /data/projects /data/cache; do
  if [[ -e "$p" && -L "$p" ]]; then
    echo "ERROR: Refusing to use symlinked path: $p" >&2
    exit 1
  fi
done

mkdir -p /data/projects /data/cache
chown -h "${TARGET_USER:-ubuntu}:${TARGET_USER:-ubuntu}" /data /data/projects /data/cache
INSTALL_BASE_FILESYSTEM
        then
            log_error "base.filesystem: install command failed: # Hardening: refuse to operate on symlinked workspace paths."
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: # Install AGENTS.md template to workspace root for agent guidance (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_FILESYSTEM'
# Install AGENTS.md template to workspace root for agent guidance
ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main}"
CURL_ARGS=(-fsSL)
if curl --help all 2>/dev/null | grep -q -- '--proto'; then
  CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
fi
curl "${CURL_ARGS[@]}" -o /data/projects/AGENTS.md "${ACFS_RAW}/acfs/AGENTS.md" || true
chown "${TARGET_USER:-ubuntu}:${TARGET_USER:-ubuntu}" /data/projects/AGENTS.md 2>/dev/null || true
INSTALL_BASE_FILESYSTEM
        then
            log_error "base.filesystem: install command failed: # Install AGENTS.md template to workspace root for agent guidance"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: target_home=\"\${TARGET_HOME:-/home/ubuntu}\" (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_FILESYSTEM'
target_home="${TARGET_HOME:-/home/ubuntu}"
if [[ -z "$target_home" || "$target_home" == "/" || "$target_home" != /* ]]; then
  echo "ERROR: Invalid TARGET_HOME: '${target_home:-<empty>}'" >&2
  exit 1
fi
if [[ -e "$target_home/.acfs" && -L "$target_home/.acfs" ]]; then
  echo "ERROR: Refusing to use symlinked ACFS dir: $target_home/.acfs" >&2
  exit 1
fi

mkdir -p "$target_home/.acfs"
chown -hR "${TARGET_USER:-ubuntu}:${TARGET_USER:-ubuntu}" "$target_home/.acfs"
INSTALL_BASE_FILESYSTEM
        then
            log_error "base.filesystem: install command failed: target_home=\"\${TARGET_HOME:-/home/ubuntu}\""
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test -d /data/projects (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_FILESYSTEM'
test -d /data/projects
INSTALL_BASE_FILESYSTEM
        then
            log_error "base.filesystem: verify failed: test -d /data/projects"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test -f /data/projects/AGENTS.md (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_FILESYSTEM'
test -f /data/projects/AGENTS.md
INSTALL_BASE_FILESYSTEM
        then
            log_error "base.filesystem: verify failed: test -f /data/projects/AGENTS.md"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test -d \"\${TARGET_HOME:-/home/ubuntu}/.acfs\" (root)"
    else
        if ! run_as_root_shell <<'INSTALL_BASE_FILESYSTEM'
test -d "${TARGET_HOME:-/home/ubuntu}/.acfs"
INSTALL_BASE_FILESYSTEM
        then
            log_error "base.filesystem: verify failed: test -d \"\${TARGET_HOME:-/home/ubuntu}/.acfs\""
            return 1
        fi
    fi

    log_success "base.filesystem installed"
}

# Install all filesystem modules
install_filesystem() {
    log_section "Installing filesystem modules"
    install_base_filesystem
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    install_filesystem
fi
