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

# Category: lang
# Modules: 4

# Bun runtime for JS tooling and global CLIs
install_lang_bun() {
    local module_id="lang.bun"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing lang.bun"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verified installer: lang.bun"
    else
        if ! {
            # Verified upstream installer script (checksums.yaml)
            if ! acfs_security_init; then
                log_error "Security verification unavailable for lang.bun"
                false
            else
                local tool="bun"
                local url="${KNOWN_INSTALLERS[$tool]:-}"
                local expected_sha256
                expected_sha256="$(get_checksum "$tool")"
                if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then
                    log_error "Missing checksum entry for $tool"
                    false
                else
                    verify_checksum "$url" "$expected_sha256" "$tool" | bash
                fi
            fi
        }; then
            log_error "lang.bun: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: ~/.bun/bin/bun --version"
    else
        if ! {
            ~/.bun/bin/bun --version
        }; then
            log_error "lang.bun: verify failed: ~/.bun/bin/bun --version"
            return 1
        fi
    fi

    log_success "lang.bun installed"
}

# uv Python tooling (fast venvs)
install_lang_uv() {
    local module_id="lang.uv"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing lang.uv"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verified installer: lang.uv"
    else
        if ! {
            # Verified upstream installer script (checksums.yaml)
            if ! acfs_security_init; then
                log_error "Security verification unavailable for lang.uv"
                false
            else
                local tool="uv"
                local url="${KNOWN_INSTALLERS[$tool]:-}"
                local expected_sha256
                expected_sha256="$(get_checksum "$tool")"
                if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then
                    log_error "Missing checksum entry for $tool"
                    false
                else
                    verify_checksum "$url" "$expected_sha256" "$tool" | sh
                fi
            fi
        }; then
            log_error "lang.uv: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: ~/.local/bin/uv --version"
    else
        if ! {
            ~/.local/bin/uv --version
        }; then
            log_error "lang.uv: verify failed: ~/.local/bin/uv --version"
            return 1
        fi
    fi

    log_success "lang.uv installed"
}

# Rust + cargo
install_lang_rust() {
    local module_id="lang.rust"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing lang.rust"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verified installer: lang.rust"
    else
        if ! {
            # Verified upstream installer script (checksums.yaml)
            if ! acfs_security_init; then
                log_error "Security verification unavailable for lang.rust"
                false
            else
                local tool="rust"
                local url="${KNOWN_INSTALLERS[$tool]:-}"
                local expected_sha256
                expected_sha256="$(get_checksum "$tool")"
                if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then
                    log_error "Missing checksum entry for $tool"
                    false
                else
                    verify_checksum "$url" "$expected_sha256" "$tool" | sh -s -- -y
                fi
            fi
        }; then
            log_error "lang.rust: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: ~/.cargo/bin/cargo --version"
    else
        if ! {
            ~/.cargo/bin/cargo --version
        }; then
            log_error "lang.rust: verify failed: ~/.cargo/bin/cargo --version"
            return 1
        fi
    fi

    log_success "lang.rust installed"
}

# Go toolchain
install_lang_go() {
    local module_id="lang.go"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing lang.go"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: apt-get install -y golang-go (root)"
    else
        if ! run_as_root_shell <<'INSTALL_LANG_GO'
apt-get install -y golang-go
INSTALL_LANG_GO
        then
            log_error "lang.go: install command failed: apt-get install -y golang-go"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: go version"
    else
        if ! {
            go version
        }; then
            log_error "lang.go: verify failed: go version"
            return 1
        fi
    fi

    log_success "lang.go installed"
}

# Install all lang modules
install_lang() {
    log_section "Installing lang modules"
    install_lang_bun
    install_lang_uv
    install_lang_rust
    install_lang_go
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_lang
fi
