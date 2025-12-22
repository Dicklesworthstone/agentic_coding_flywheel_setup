#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================

set -euo pipefail

# Ensure logging functions available
ACFS_GENERATED_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh"
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
    if [[ "${ACFS_SECURITY_READY}" == "true" ]]; then
        return 0
    fi

    local security_lib="$ACFS_GENERATED_SCRIPT_DIR/../lib/security.sh"
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
# Modules: 5

# Bun runtime for JS tooling and global CLIs
install_lang_bun() {
    local module_id="lang.bun"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing lang.bun"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verified installer: lang.bun"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init 2>/dev/null; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="bun"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    expected_sha256="$(get_checksum "$tool" 2>/dev/null)" || expected_sha256=""

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" 2>/dev/null | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        fi
                    fi
                fi
            fi

            # No unverified fallback: verified install is required
            if [[ "$install_success" != "true" ]]; then
                log_error "Verified install failed for lang.bun"
                false
            fi
        }; then
            log_error "lang.bun: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: ~/.bun/bin/bun --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_LANG_BUN'
~/.bun/bin/bun --version
INSTALL_LANG_BUN
        then
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
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init 2>/dev/null; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="uv"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    expected_sha256="$(get_checksum "$tool" 2>/dev/null)" || expected_sha256=""

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" 2>/dev/null | run_as_target_runner 'sh' '-s'; then
                            install_success=true
                        fi
                    fi
                fi
            fi

            # No unverified fallback: verified install is required
            if [[ "$install_success" != "true" ]]; then
                log_error "Verified install failed for lang.uv"
                false
            fi
        }; then
            log_error "lang.uv: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: ~/.local/bin/uv --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_LANG_UV'
~/.local/bin/uv --version
INSTALL_LANG_UV
        then
            log_error "lang.uv: verify failed: ~/.local/bin/uv --version"
            return 1
        fi
    fi

    log_success "lang.uv installed"
}

# Rust nightly + cargo
install_lang_rust() {
    local module_id="lang.rust"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing lang.rust"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verified installer: lang.rust"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init 2>/dev/null; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="rust"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    expected_sha256="$(get_checksum "$tool" 2>/dev/null)" || expected_sha256=""

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" 2>/dev/null | run_as_target_runner 'sh' '-s' '-s' '--' '-y' '--default-toolchain' 'nightly'; then
                            install_success=true
                        fi
                    fi
                fi
            fi

            # No unverified fallback: verified install is required
            if [[ "$install_success" != "true" ]]; then
                log_error "Verified install failed for lang.rust"
                false
            fi
        }; then
            log_error "lang.rust: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: ~/.cargo/bin/cargo --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_LANG_RUST'
~/.cargo/bin/cargo --version
INSTALL_LANG_RUST
        then
            log_error "lang.rust: verify failed: ~/.cargo/bin/cargo --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: ~/.cargo/bin/rustup show | grep -q nightly (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_LANG_RUST'
~/.cargo/bin/rustup show | grep -q nightly
INSTALL_LANG_RUST
        then
            log_error "lang.rust: verify failed: ~/.cargo/bin/rustup show | grep -q nightly"
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
        log_info "dry-run: verify: go version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_LANG_GO'
go version
INSTALL_LANG_GO
        then
            log_error "lang.go: verify failed: go version"
            return 1
        fi
    fi

    log_success "lang.go installed"
}

# nvm + latest Node.js
install_lang_nvm() {
    local module_id="lang.nvm"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing lang.nvm"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verified installer: lang.nvm"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init 2>/dev/null; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="nvm"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    expected_sha256="$(get_checksum "$tool" 2>/dev/null)" || expected_sha256=""

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" 2>/dev/null | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        fi
                    fi
                fi
            fi

            # No unverified fallback: verified install is required
            if [[ "$install_success" != "true" ]]; then
                log_error "Verified install failed for lang.nvm"
                false
            fi
        }; then
            log_error "lang.nvm: verified installer failed"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: export NVM_DIR=\"\$HOME/.nvm\" (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_LANG_NVM'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm install node
nvm alias default node
INSTALL_LANG_NVM
        then
            log_error "lang.nvm: install command failed: export NVM_DIR=\"\$HOME/.nvm\""
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: export NVM_DIR=\"\$HOME/.nvm\" (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_LANG_NVM'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
node --version
INSTALL_LANG_NVM
        then
            log_error "lang.nvm: verify failed: export NVM_DIR=\"\$HOME/.nvm\""
            return 1
        fi
    fi

    log_success "lang.nvm installed"
}

# Install all lang modules
install_lang() {
    log_section "Installing lang modules"
    install_lang_bun
    install_lang_uv
    install_lang_rust
    install_lang_go
    install_lang_nvm
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_lang
fi
