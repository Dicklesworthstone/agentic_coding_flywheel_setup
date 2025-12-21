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

# Category: stack
# Modules: 8

# Named tmux manager (agent cockpit)
install_stack_ntm() {
    local module_id="stack.ntm"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.ntm"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verified installer: stack.ntm"
    else
        if ! {
            # Verified upstream installer script (checksums.yaml)
            if ! acfs_security_init; then
                log_error "Security verification unavailable for stack.ntm"
                false
            else
                local tool="ntm"
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
            log_error "stack.ntm: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: ntm --help"
    else
        if ! {
            ntm --help
        }; then
            log_error "stack.ntm: verify failed: ntm --help"
            return 1
        fi
    fi

    log_success "stack.ntm installed"
}

# Like gmail for coding agents; MCP HTTP server + token; installs beads tools
install_stack_mcp_agent_mail() {
    local module_id="stack.mcp_agent_mail"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.mcp_agent_mail"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verified installer: stack.mcp_agent_mail"
    else
        if ! {
            # Verified upstream installer script (checksums.yaml)
            if ! acfs_security_init; then
                log_error "Security verification unavailable for stack.mcp_agent_mail"
                false
            else
                local tool="mcp_agent_mail"
                local url="${KNOWN_INSTALLERS[$tool]:-}"
                local expected_sha256
                expected_sha256="$(get_checksum "$tool")"
                if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then
                    log_error "Missing checksum entry for $tool"
                    false
                else
                    verify_checksum "$url" "$expected_sha256" "$tool" | bash --yes
                fi
            fi
        }; then
            log_error "stack.mcp_agent_mail: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: command -v am"
    else
        if ! {
            command -v am
        }; then
            log_error "stack.mcp_agent_mail: verify failed: command -v am"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify (optional): curl -fsS http://127.0.0.1:8765/health"
    else
        if ! {
            curl -fsS http://127.0.0.1:8765/health
        }; then
            log_warn "Optional verify failed: stack.mcp_agent_mail"
        fi
    fi

    log_success "stack.mcp_agent_mail installed"
}

# UBS bug scanning (easy-mode)
install_stack_ultimate_bug_scanner() {
    local module_id="stack.ultimate_bug_scanner"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.ultimate_bug_scanner"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verified installer: stack.ultimate_bug_scanner"
    else
        if ! {
            # Verified upstream installer script (checksums.yaml)
            if ! acfs_security_init; then
                log_error "Security verification unavailable for stack.ultimate_bug_scanner"
                false
            else
                local tool="ubs"
                local url="${KNOWN_INSTALLERS[$tool]:-}"
                local expected_sha256
                expected_sha256="$(get_checksum "$tool")"
                if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then
                    log_error "Missing checksum entry for $tool"
                    false
                else
                    verify_checksum "$url" "$expected_sha256" "$tool" | bash --easy-mode
                fi
            fi
        }; then
            log_error "stack.ultimate_bug_scanner: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: ubs --help"
    else
        if ! {
            ubs --help
        }; then
            log_error "stack.ultimate_bug_scanner: verify failed: ubs --help"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify (optional): ubs doctor"
    else
        if ! {
            ubs doctor
        }; then
            log_warn "Optional verify failed: stack.ultimate_bug_scanner"
        fi
    fi

    log_success "stack.ultimate_bug_scanner installed"
}

# bv TUI for Beads tasks
install_stack_beads_viewer() {
    local module_id="stack.beads_viewer"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.beads_viewer"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verified installer: stack.beads_viewer"
    else
        if ! {
            # Verified upstream installer script (checksums.yaml)
            if ! acfs_security_init; then
                log_error "Security verification unavailable for stack.beads_viewer"
                false
            else
                local tool="bv"
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
            log_error "stack.beads_viewer: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: bv --help || bv --version"
    else
        if ! {
            bv --help || bv --version
        }; then
            log_error "stack.beads_viewer: verify failed: bv --help || bv --version"
            return 1
        fi
    fi

    log_success "stack.beads_viewer installed"
}

# Unified search across agent session history
install_stack_cass() {
    local module_id="stack.cass"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.cass"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verified installer: stack.cass"
    else
        if ! {
            # Verified upstream installer script (checksums.yaml)
            if ! acfs_security_init; then
                log_error "Security verification unavailable for stack.cass"
                false
            else
                local tool="cass"
                local url="${KNOWN_INSTALLERS[$tool]:-}"
                local expected_sha256
                expected_sha256="$(get_checksum "$tool")"
                if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then
                    log_error "Missing checksum entry for $tool"
                    false
                else
                    verify_checksum "$url" "$expected_sha256" "$tool" | bash --easy-mode --verify
                fi
            fi
        }; then
            log_error "stack.cass: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: cass --help || cass --version"
    else
        if ! {
            cass --help || cass --version
        }; then
            log_error "stack.cass: verify failed: cass --help || cass --version"
            return 1
        fi
    fi

    log_success "stack.cass installed"
}

# Procedural memory for agents (cass-memory)
install_stack_cm() {
    local module_id="stack.cm"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.cm"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verified installer: stack.cm"
    else
        if ! {
            # Verified upstream installer script (checksums.yaml)
            if ! acfs_security_init; then
                log_error "Security verification unavailable for stack.cm"
                false
            else
                local tool="cm"
                local url="${KNOWN_INSTALLERS[$tool]:-}"
                local expected_sha256
                expected_sha256="$(get_checksum "$tool")"
                if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then
                    log_error "Missing checksum entry for $tool"
                    false
                else
                    verify_checksum "$url" "$expected_sha256" "$tool" | bash --easy-mode --verify
                fi
            fi
        }; then
            log_error "stack.cm: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: cm --version"
    else
        if ! {
            cm --version
        }; then
            log_error "stack.cm: verify failed: cm --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify (optional): cm doctor --json"
    else
        if ! {
            cm doctor --json
        }; then
            log_warn "Optional verify failed: stack.cm"
        fi
    fi

    log_success "stack.cm installed"
}

# Instant auth switching for agent CLIs
install_stack_caam() {
    local module_id="stack.caam"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.caam"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verified installer: stack.caam"
    else
        if ! {
            # Verified upstream installer script (checksums.yaml)
            if ! acfs_security_init; then
                log_error "Security verification unavailable for stack.caam"
                false
            else
                local tool="caam"
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
            log_error "stack.caam: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: caam status || caam --help"
    else
        if ! {
            caam status || caam --help
        }; then
            log_error "stack.caam: verify failed: caam status || caam --help"
            return 1
        fi
    fi

    log_success "stack.caam installed"
}

# Two-person rule for dangerous commands (optional guardrails)
install_stack_slb() {
    local module_id="stack.slb"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.slb"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verified installer: stack.slb"
    else
        if ! {
            # Verified upstream installer script (checksums.yaml)
            if ! acfs_security_init; then
                log_error "Security verification unavailable for stack.slb"
                false
            else
                local tool="slb"
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
            log_warn "stack.slb: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.slb" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.slb"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: slb --help"
    else
        if ! {
            slb --help
        }; then
            log_warn "stack.slb: verify failed: slb --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.slb" "verify failed: slb --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.slb"
            fi
            return 0
        fi
    fi

    log_success "stack.slb installed"
}

# Install all stack modules
install_stack() {
    log_section "Installing stack modules"
    install_stack_ntm
    install_stack_mcp_agent_mail
    install_stack_ultimate_bug_scanner
    install_stack_beads_viewer
    install_stack_cass
    install_stack_cm
    install_stack_caam
    install_stack_slb
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_stack
fi
