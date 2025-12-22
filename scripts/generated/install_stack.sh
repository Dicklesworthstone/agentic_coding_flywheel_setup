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
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init 2>/dev/null; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="ntm"
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
                log_error "Verified install failed for stack.ntm"
                false
            fi
        }; then
            log_error "stack.ntm: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: ntm --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_NTM'
ntm --help
INSTALL_STACK_NTM
        then
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
            # Run installer in detached tmux session (run_in_tmux: true)
            # This prevents blocking when the installer starts a long-running service
            local tmux_session="acfs-services"

            # Resolve verified installer URL + checksum (fail closed)
            local tool="mcp_agent_mail"
            local url=""
            local expected_sha256=""
            if acfs_security_init 2>/dev/null; then
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    expected_sha256="$(get_checksum "$tool" 2>/dev/null)" || expected_sha256=""
                fi
            fi

            if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then
                log_error "Missing verified installer URL/checksum for stack.mcp_agent_mail"
                false
            fi

            # Download verified installer to a temp file (so tmux can exec it without pipes)
            local tmp_install
            tmp_install="$(mktemp "${TMPDIR:-/tmp}/acfs-install-${tool}.XXXXXX" 2>/dev/null)" || tmp_install=""
            if [[ -z "$tmp_install" ]]; then
                log_error "Failed to create temp installer for stack.mcp_agent_mail"
                false
            fi

            if ! verify_checksum "$url" "$expected_sha256" "$tool" > "$tmp_install"; then
                rm -f "$tmp_install" 2>/dev/null || true
                log_error "stack.mcp_agent_mail: installer verification failed"
                false
            fi
            chmod 755 "$tmp_install" 2>/dev/null || true

            # Kill existing session if any (clean slate)
            run_as_target tmux kill-session -t "$tmux_session" 2>/dev/null || true

            # Create new detached tmux session and run the installer
            if run_as_target tmux new-session -d -s "$tmux_session" 'bash' "$tmp_install" '--dir' '/home/ubuntu/mcp_agent_mail' '--yes'; then
                    log_success "stack.mcp_agent_mail installing in tmux session '$tmux_session'"
                    log_info "Attach with: tmux attach -t $tmux_session"
                    # Give it a moment to start
                    sleep 3
                else
                    log_warn "stack.mcp_agent_mail tmux installation may have failed"
                fi
        }; then
            log_error "stack.mcp_agent_mail: verified installer failed"
            return 1
        fi
    fi

    # Verify skipped: run_in_tmux installs async in detached tmux session
    log_info "stack.mcp_agent_mail: installation running in background tmux session"
    log_info "Attach with: tmux attach -t acfs-services"

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
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init 2>/dev/null; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="ubs"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    expected_sha256="$(get_checksum "$tool" 2>/dev/null)" || expected_sha256=""

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" 2>/dev/null | run_as_target_runner 'bash' '-s' '--' '--easy-mode'; then
                            install_success=true
                        fi
                    fi
                fi
            fi

            # No unverified fallback: verified install is required
            if [[ "$install_success" != "true" ]]; then
                log_error "Verified install failed for stack.ultimate_bug_scanner"
                false
            fi
        }; then
            log_error "stack.ultimate_bug_scanner: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: ubs --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_ULTIMATE_BUG_SCANNER'
ubs --help
INSTALL_STACK_ULTIMATE_BUG_SCANNER
        then
            log_error "stack.ultimate_bug_scanner: verify failed: ubs --help"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify (optional): ubs doctor (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_ULTIMATE_BUG_SCANNER'
ubs doctor
INSTALL_STACK_ULTIMATE_BUG_SCANNER
        then
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
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init 2>/dev/null; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="bv"
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
                log_error "Verified install failed for stack.beads_viewer"
                false
            fi
        }; then
            log_error "stack.beads_viewer: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: bv --help || bv --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_BEADS_VIEWER'
bv --help || bv --version
INSTALL_STACK_BEADS_VIEWER
        then
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
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init 2>/dev/null; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="cass"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    expected_sha256="$(get_checksum "$tool" 2>/dev/null)" || expected_sha256=""

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" 2>/dev/null | run_as_target_runner 'bash' '-s' '--' '--easy-mode' '--verify'; then
                            install_success=true
                        fi
                    fi
                fi
            fi

            # No unverified fallback: verified install is required
            if [[ "$install_success" != "true" ]]; then
                log_error "Verified install failed for stack.cass"
                false
            fi
        }; then
            log_error "stack.cass: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: cass --help || cass --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_CASS'
cass --help || cass --version
INSTALL_STACK_CASS
        then
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
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init 2>/dev/null; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="cm"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    expected_sha256="$(get_checksum "$tool" 2>/dev/null)" || expected_sha256=""

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" 2>/dev/null | run_as_target_runner 'bash' '-s' '--' '--easy-mode' '--verify'; then
                            install_success=true
                        fi
                    fi
                fi
            fi

            # No unverified fallback: verified install is required
            if [[ "$install_success" != "true" ]]; then
                log_error "Verified install failed for stack.cm"
                false
            fi
        }; then
            log_error "stack.cm: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: cm --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_CM'
cm --version
INSTALL_STACK_CM
        then
            log_error "stack.cm: verify failed: cm --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify (optional): cm doctor --json (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_CM'
cm doctor --json
INSTALL_STACK_CM
        then
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
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init 2>/dev/null; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="caam"
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
                log_error "Verified install failed for stack.caam"
                false
            fi
        }; then
            log_error "stack.caam: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: caam status || caam --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_CAAM'
caam status || caam --help
INSTALL_STACK_CAAM
        then
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
        log_info "dry-run: install: go install github.com/Dicklesworthstone/slb@latest (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_SLB'
go install github.com/Dicklesworthstone/slb@latest
INSTALL_STACK_SLB
        then
            log_warn "stack.slb: install command failed: go install github.com/Dicklesworthstone/slb@latest"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.slb" "install command failed: go install github.com/Dicklesworthstone/slb@latest"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.slb"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: slb --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_SLB'
slb --help
INSTALL_STACK_SLB
        then
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
