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

# Category: tools
# Modules: 4

# Atuin shell history (Ctrl-R superpowers)
install_tools_atuin() {
    local module_id="tools.atuin"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing tools.atuin"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verified installer: tools.atuin"
    else
        if ! {
            # Verified upstream installer script (checksums.yaml)
            if ! acfs_security_init; then
                log_error "Security verification unavailable for tools.atuin"
                false
            else
                local tool="atuin"
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
            log_error "tools.atuin: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: ~/.atuin/bin/atuin --version"
    else
        if ! {
            ~/.atuin/bin/atuin --version
        }; then
            log_error "tools.atuin: verify failed: ~/.atuin/bin/atuin --version"
            return 1
        fi
    fi

    log_success "tools.atuin installed"
}

# Zoxide (better cd)
install_tools_zoxide() {
    local module_id="tools.zoxide"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing tools.zoxide"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verified installer: tools.zoxide"
    else
        if ! {
            # Verified upstream installer script (checksums.yaml)
            if ! acfs_security_init; then
                log_error "Security verification unavailable for tools.zoxide"
                false
            else
                local tool="zoxide"
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
            log_error "tools.zoxide: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: command -v zoxide"
    else
        if ! {
            command -v zoxide
        }; then
            log_error "tools.zoxide: verify failed: command -v zoxide"
            return 1
        fi
    fi

    log_success "tools.zoxide installed"
}

# ast-grep (used by UBS for syntax-aware scanning)
install_tools_ast_grep() {
    local module_id="tools.ast_grep"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing tools.ast_grep"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: ~/.cargo/bin/cargo install ast-grep --locked (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_TOOLS_AST_GREP'
~/.cargo/bin/cargo install ast-grep --locked
INSTALL_TOOLS_AST_GREP
        then
            log_error "tools.ast_grep: install command failed: ~/.cargo/bin/cargo install ast-grep --locked"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: sg --version"
    else
        if ! {
            sg --version
        }; then
            log_error "tools.ast_grep: verify failed: sg --version"
            return 1
        fi
    fi

    log_success "tools.ast_grep installed"
}

# HashiCorp Vault CLI
install_tools_vault() {
    local module_id="tools.vault"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing tools.vault"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg (root)"
    else
        if ! run_as_root_shell <<'INSTALL_TOOLS_VAULT'
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
INSTALL_TOOLS_VAULT
        then
            log_warn "tools.vault: install command failed: curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "tools.vault" "install command failed: curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "tools.vault"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: echo \"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \$(lsb_release -cs) main\" > /etc/apt/sources.list.d/hashicorp.list (root)"
    else
        if ! run_as_root_shell <<'INSTALL_TOOLS_VAULT'
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list
INSTALL_TOOLS_VAULT
        then
            log_warn "tools.vault: install command failed: echo \"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \$(lsb_release -cs) main\" > /etc/apt/sources.list.d/hashicorp.list"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "tools.vault" "install command failed: echo \"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \$(lsb_release -cs) main\" > /etc/apt/sources.list.d/hashicorp.list"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "tools.vault"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: apt-get update && apt-get install -y vault (root)"
    else
        if ! run_as_root_shell <<'INSTALL_TOOLS_VAULT'
apt-get update && apt-get install -y vault
INSTALL_TOOLS_VAULT
        then
            log_warn "tools.vault: install command failed: apt-get update && apt-get install -y vault"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "tools.vault" "install command failed: apt-get update && apt-get install -y vault"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "tools.vault"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: vault --version"
    else
        if ! {
            vault --version
        }; then
            log_warn "tools.vault: verify failed: vault --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "tools.vault" "verify failed: vault --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "tools.vault"
            fi
            return 0
        fi
    fi

    log_success "tools.vault installed"
}

# Install all tools modules
install_tools() {
    log_section "Installing tools modules"
    install_tools_atuin
    install_tools_zoxide
    install_tools_ast_grep
    install_tools_vault
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_tools
fi
