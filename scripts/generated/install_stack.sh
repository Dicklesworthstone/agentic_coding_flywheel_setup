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

# Category: stack
# Modules: 25

# Named tmux manager (agent cockpit)
install_stack_ntm() {
    local module_id="stack.ntm"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.ntm"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.ntm"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="ntm"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.ntm: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--no-shell'; then
                            install_success=true
                        else
                            log_error "stack.ntm: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.ntm: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.ntm: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.ntm: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.ntm: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.ntm"
                false
            fi
        }; then
            log_error "stack.ntm: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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
            if acfs_security_init; then
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.mcp_agent_mail: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi
                else
                    log_error "stack.mcp_agent_mail: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.mcp_agent_mail: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            if [[ -z "$url" ]]; then
                log_error "stack.mcp_agent_mail: KNOWN_INSTALLERS[$tool] not found"
                false
            fi
            if [[ -z "$expected_sha256" ]]; then
                log_error "stack.mcp_agent_mail: checksum for '$tool' not found"
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
            if run_as_target tmux new-session -d -s "$tmux_session" 'bash' "$tmp_install" '--dir' "${TARGET_HOME:-/home/ubuntu}"'/mcp_agent_mail' '--yes'; then
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

# Local-first knowledge management with hybrid semantic search (ms)
install_stack_meta_skill() {
    local module_id="stack.meta_skill"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.meta_skill"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.meta_skill"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="ms"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.meta_skill: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--easy-mode'; then
                            install_success=true
                        else
                            log_error "stack.meta_skill: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.meta_skill: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.meta_skill: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.meta_skill: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.meta_skill: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.meta_skill"
                false
            fi
        }; then
            log_error "stack.meta_skill: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: ms --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_META_SKILL'
ms --version
INSTALL_STACK_META_SKILL
        then
            log_error "stack.meta_skill: verify failed: ms --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): ms doctor --json (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_META_SKILL'
ms doctor --json
INSTALL_STACK_META_SKILL
        then
            log_warn "Optional verify failed: stack.meta_skill"
        fi
    fi

    log_success "stack.meta_skill installed"
}

# Automated iterative spec refinement with extended AI reasoning (apr)
install_stack_automated_plan_reviser() {
    local module_id="stack.automated_plan_reviser"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.automated_plan_reviser"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.automated_plan_reviser"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="apr"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.automated_plan_reviser: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--easy-mode'; then
                            install_success=true
                        else
                            log_error "stack.automated_plan_reviser: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.automated_plan_reviser: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.automated_plan_reviser: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.automated_plan_reviser: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.automated_plan_reviser: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.automated_plan_reviser"
                false
            fi
        }; then
            log_warn "stack.automated_plan_reviser: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.automated_plan_reviser" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.automated_plan_reviser"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: apr --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_AUTOMATED_PLAN_REVISER'
apr --help
INSTALL_STACK_AUTOMATED_PLAN_REVISER
        then
            log_warn "stack.automated_plan_reviser: verify failed: apr --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.automated_plan_reviser" "verify failed: apr --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.automated_plan_reviser"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): apr --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_AUTOMATED_PLAN_REVISER'
apr --version
INSTALL_STACK_AUTOMATED_PLAN_REVISER
        then
            log_warn "Optional verify failed: stack.automated_plan_reviser"
        fi
    fi

    log_success "stack.automated_plan_reviser installed"
}

# Curated battle-tested prompts for AI agents - browse and install as skills (jfp)
install_stack_jeffreysprompts() {
    local module_id="stack.jeffreysprompts"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.jeffreysprompts"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.jeffreysprompts"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="jfp"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.jeffreysprompts: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "stack.jeffreysprompts: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.jeffreysprompts: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.jeffreysprompts: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.jeffreysprompts: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.jeffreysprompts: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.jeffreysprompts"
                false
            fi
        }; then
            log_warn "stack.jeffreysprompts: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.jeffreysprompts" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.jeffreysprompts"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: jfp --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_JEFFREYSPROMPTS'
jfp --version
INSTALL_STACK_JEFFREYSPROMPTS
        then
            log_warn "stack.jeffreysprompts: verify failed: jfp --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.jeffreysprompts" "verify failed: jfp --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.jeffreysprompts"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): jfp doctor (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_JEFFREYSPROMPTS'
jfp doctor
INSTALL_STACK_JEFFREYSPROMPTS
        then
            log_warn "Optional verify failed: stack.jeffreysprompts"
        fi
    fi

    log_success "stack.jeffreysprompts installed"
}

# Find and terminate stuck/zombie processes with intelligent scoring (pt)
install_stack_process_triage() {
    local module_id="stack.process_triage"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.process_triage"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.process_triage"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="pt"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.process_triage: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "stack.process_triage: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.process_triage: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.process_triage: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.process_triage: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.process_triage: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.process_triage"
                false
            fi
        }; then
            log_warn "stack.process_triage: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.process_triage" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.process_triage"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: pt --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_PROCESS_TRIAGE'
pt --help
INSTALL_STACK_PROCESS_TRIAGE
        then
            log_warn "stack.process_triage: verify failed: pt --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.process_triage" "verify failed: pt --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.process_triage"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): pt --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_PROCESS_TRIAGE'
pt --version
INSTALL_STACK_PROCESS_TRIAGE
        then
            log_warn "Optional verify failed: stack.process_triage"
        fi
    fi

    log_success "stack.process_triage installed"
}

# UBS bug scanning (easy-mode)
install_stack_ultimate_bug_scanner() {
    local module_id="stack.ultimate_bug_scanner"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.ultimate_bug_scanner"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.ultimate_bug_scanner"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="ubs"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.ultimate_bug_scanner: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--easy-mode'; then
                            install_success=true
                        else
                            log_error "stack.ultimate_bug_scanner: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.ultimate_bug_scanner: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.ultimate_bug_scanner: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.ultimate_bug_scanner: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.ultimate_bug_scanner: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.ultimate_bug_scanner"
                false
            fi
        }; then
            log_error "stack.ultimate_bug_scanner: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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

# beads_rust (br) - Rust issue tracker with graph-aware dependencies
install_stack_beads_rust() {
    local module_id="stack.beads_rust"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.beads_rust"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.beads_rust"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="br"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.beads_rust: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "stack.beads_rust: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.beads_rust: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.beads_rust: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.beads_rust: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.beads_rust: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.beads_rust"
                false
            fi
        }; then
            log_error "stack.beads_rust: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: br --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_BEADS_RUST'
br --version
INSTALL_STACK_BEADS_RUST
        then
            log_error "stack.beads_rust: verify failed: br --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): br list --json 2>/dev/null (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_BEADS_RUST'
br list --json 2>/dev/null
INSTALL_STACK_BEADS_RUST
        then
            log_warn "Optional verify failed: stack.beads_rust"
        fi
    fi

    log_success "stack.beads_rust installed"
}

# bv TUI for Beads tasks
install_stack_beads_viewer() {
    local module_id="stack.beads_viewer"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.beads_viewer"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.beads_viewer"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="bv"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.beads_viewer: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "stack.beads_viewer: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.beads_viewer: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.beads_viewer: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.beads_viewer: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.beads_viewer: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.beads_viewer"
                false
            fi
        }; then
            log_error "stack.beads_viewer: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.cass"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="cass"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.cass: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--easy-mode' '--verify'; then
                            install_success=true
                        else
                            log_error "stack.cass: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.cass: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.cass: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.cass: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.cass: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.cass"
                false
            fi
        }; then
            log_error "stack.cass: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.cm"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="cm"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.cm: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--easy-mode' '--verify'; then
                            install_success=true
                        else
                            log_error "stack.cm: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.cm: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.cm: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.cm: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.cm: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.cm"
                false
            fi
        }; then
            log_error "stack.cm: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.caam"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="caam"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.caam: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "stack.caam: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.caam: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.caam: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.caam: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.caam: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.caam"
                false
            fi
        }; then
            log_error "stack.caam: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: mkdir -p ~/go/bin (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_SLB'
mkdir -p ~/go/bin
SLB_TMP="$(mktemp -d "${TMPDIR:-/tmp}/slb_build.XXXXXX")"
cd "$SLB_TMP"
git clone --depth 1 https://github.com/Dicklesworthstone/simultaneous_launch_button.git .
go build -o ~/go/bin/slb ./cmd/slb
cd ..
rm -rf "$SLB_TMP"
# Add ~/go/bin to PATH if not already present
if ! grep -q 'export PATH=.*\$HOME/go/bin' ~/.zshrc 2>/dev/null; then
  echo '' >> ~/.zshrc
  echo '# Go binaries' >> ~/.zshrc
  echo 'export PATH="$HOME/go/bin:$PATH"' >> ~/.zshrc
fi
INSTALL_STACK_SLB
        then
            log_warn "stack.slb: install command failed: mkdir -p ~/go/bin"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.slb" "install command failed: mkdir -p ~/go/bin"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.slb"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: export PATH=\"\$HOME/go/bin:\$PATH\" && slb >/dev/null 2>&1 || slb --help >/dev/null 2>&1 (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_SLB'
export PATH="$HOME/go/bin:$PATH" && slb >/dev/null 2>&1 || slb --help >/dev/null 2>&1
INSTALL_STACK_SLB
        then
            log_warn "stack.slb: verify failed: export PATH=\"\$HOME/go/bin:\$PATH\" && slb >/dev/null 2>&1 || slb --help >/dev/null 2>&1"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.slb" "verify failed: export PATH=\"\$HOME/go/bin:\$PATH\" && slb >/dev/null 2>&1 || slb --help >/dev/null 2>&1"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.slb"
            fi
            return 0
        fi
    fi

    log_success "stack.slb installed"
}

# Destructive Command Guard - Claude Code hook blocking dangerous git/fs commands
install_stack_dcg() {
    local module_id="stack.dcg"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.dcg"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.dcg"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="dcg"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.dcg: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--easy-mode'; then
                            install_success=true
                        else
                            log_error "stack.dcg: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.dcg: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.dcg: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.dcg: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.dcg: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.dcg"
                false
            fi
        }; then
            log_error "stack.dcg: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: dcg --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_DCG'
dcg --version
INSTALL_STACK_DCG
        then
            log_error "stack.dcg: verify failed: dcg --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: settings=\"\$HOME/.claude/settings.json\" (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_DCG'
settings="$HOME/.claude/settings.json"
alt_settings="$HOME/.config/claude/settings.json"
if [[ -f "$settings" ]]; then
  grep -q "dcg" "$settings"
elif [[ -f "$alt_settings" ]]; then
  grep -q "dcg" "$alt_settings"
else
  exit 1
fi
INSTALL_STACK_DCG
        then
            log_error "stack.dcg: verify failed: settings=\"\$HOME/.claude/settings.json\""
            return 1
        fi
    fi

    log_success "stack.dcg installed"
}

# Repo Updater - multi-repo sync + AI-driven commit automation
install_stack_ru() {
    local module_id="stack.ru"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.ru"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.ru"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="ru"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.ru: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--easy-mode'; then
                            install_success=true
                        else
                            log_error "stack.ru: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.ru: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.ru: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.ru: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.ru: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.ru"
                false
            fi
        }; then
            log_error "stack.ru: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: ru --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_RU'
ru --version
INSTALL_STACK_RU
        then
            log_error "stack.ru: verify failed: ru --version"
            return 1
        fi
    fi

    log_success "stack.ru installed"
}

# Brenner Bot - research session manager with hypothesis tracking
install_stack_brenner_bot() {
    local module_id="stack.brenner_bot"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.brenner_bot"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.brenner_bot"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="brenner_bot"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.brenner_bot: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--skip-cass'; then
                            install_success=true
                        else
                            log_error "stack.brenner_bot: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.brenner_bot: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.brenner_bot: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.brenner_bot: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.brenner_bot: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.brenner_bot"
                false
            fi
        }; then
            log_warn "stack.brenner_bot: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.brenner_bot" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.brenner_bot"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: brenner --version || brenner --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_BRENNER_BOT'
brenner --version || brenner --help
INSTALL_STACK_BRENNER_BOT
        then
            log_warn "stack.brenner_bot: verify failed: brenner --version || brenner --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.brenner_bot" "verify failed: brenner --version || brenner --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.brenner_bot"
            fi
            return 0
        fi
    fi

    log_success "stack.brenner_bot installed"
}

# Remote Compilation Helper - transparent build offloading for AI coding agents
install_stack_rch() {
    local module_id="stack.rch"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.rch"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.rch"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="rch"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.rch: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "stack.rch: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.rch: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.rch: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.rch: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.rch: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.rch"
                false
            fi
        }; then
            log_warn "stack.rch: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.rch" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.rch"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: rch --version || rch --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_RCH'
rch --version || rch --help
INSTALL_STACK_RCH
        then
            log_warn "stack.rch: verify failed: rch --version || rch --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.rch" "verify failed: rch --version || rch --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.rch"
            fi
            return 0
        fi
    fi

    log_success "stack.rch installed"
}

# WezTerm Automata (wa) - terminal automation and orchestration for AI agents
install_stack_wezterm_automata() {
    local module_id="stack.wezterm_automata"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.wezterm_automata"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: WA_TMP=\"\$(mktemp -d \"\${TMPDIR:-/tmp}/wa_build.XXXXXX\")\" (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_WEZTERM_AUTOMATA'
WA_TMP="$(mktemp -d "${TMPDIR:-/tmp}/wa_build.XXXXXX")"
cd "$WA_TMP"
git clone --depth 1 https://github.com/Dicklesworthstone/wezterm_automata.git .
cargo build --release -p wa
cp target/release/wa ~/.cargo/bin/
rm -rf "$WA_TMP"
INSTALL_STACK_WEZTERM_AUTOMATA
        then
            log_warn "stack.wezterm_automata: install command failed: WA_TMP=\"\$(mktemp -d \"\${TMPDIR:-/tmp}/wa_build.XXXXXX\")\""
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.wezterm_automata" "install command failed: WA_TMP=\"\$(mktemp -d \"\${TMPDIR:-/tmp}/wa_build.XXXXXX\")\""
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.wezterm_automata"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: wa --version || wa --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_WEZTERM_AUTOMATA'
wa --version || wa --help
INSTALL_STACK_WEZTERM_AUTOMATA
        then
            log_warn "stack.wezterm_automata: verify failed: wa --version || wa --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.wezterm_automata" "verify failed: wa --version || wa --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.wezterm_automata"
            fi
            return 0
        fi
    fi

    log_success "stack.wezterm_automata installed"
}

# System Resource Protection Script - ananicy-cpp rules + TUI monitor for responsive dev workstations
install_stack_srps() {
    local module_id="stack.srps"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.srps"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.srps"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="srps"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.srps: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--install'; then
                            install_success=true
                        else
                            log_error "stack.srps: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.srps: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.srps: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.srps: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.srps: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.srps"
                false
            fi
        }; then
            log_warn "stack.srps: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.srps" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.srps"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: sysmoni --version || sysmoni --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_SRPS'
sysmoni --version || sysmoni --help
INSTALL_STACK_SRPS
        then
            log_warn "stack.srps: verify failed: sysmoni --version || sysmoni --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.srps" "verify failed: sysmoni --version || sysmoni --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.srps"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: systemctl is-active ananicy-cpp (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_SRPS'
systemctl is-active ananicy-cpp
INSTALL_STACK_SRPS
        then
            log_warn "stack.srps: verify failed: systemctl is-active ananicy-cpp"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.srps" "verify failed: systemctl is-active ananicy-cpp"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.srps"
            fi
            return 0
        fi
    fi

    log_success "stack.srps installed"
}

# Two-tier hybrid local search — lexical (BM25) + semantic retrieval with progressive delivery (fsfs)
install_stack_frankensearch() {
    local module_id="stack.frankensearch"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.frankensearch"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.frankensearch"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="fsfs"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.frankensearch: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--easy-mode'; then
                            install_success=true
                        else
                            log_error "stack.frankensearch: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.frankensearch: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.frankensearch: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.frankensearch: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.frankensearch: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.frankensearch"
                false
            fi
        }; then
            log_warn "stack.frankensearch: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.frankensearch" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.frankensearch"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: fsfs version || fsfs --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_FRANKENSEARCH'
fsfs version || fsfs --help
INSTALL_STACK_FRANKENSEARCH
        then
            log_warn "stack.frankensearch: verify failed: fsfs version || fsfs --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.frankensearch" "verify failed: fsfs version || fsfs --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.frankensearch"
            fi
            return 0
        fi
    fi

    log_success "stack.frankensearch installed"
}

# Cross-platform disk-pressure defense for AI coding workloads (sbh)
install_stack_storage_ballast_helper() {
    local module_id="stack.storage_ballast_helper"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.storage_ballast_helper"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.storage_ballast_helper"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="sbh"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.storage_ballast_helper: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "stack.storage_ballast_helper: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.storage_ballast_helper: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.storage_ballast_helper: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.storage_ballast_helper: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.storage_ballast_helper: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.storage_ballast_helper"
                false
            fi
        }; then
            log_warn "stack.storage_ballast_helper: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.storage_ballast_helper" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.storage_ballast_helper"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: sbh status || sbh --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_STORAGE_BALLAST_HELPER'
sbh status || sbh --help
INSTALL_STACK_STORAGE_BALLAST_HELPER
        then
            log_warn "stack.storage_ballast_helper: verify failed: sbh status || sbh --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.storage_ballast_helper" "verify failed: sbh status || sbh --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.storage_ballast_helper"
            fi
            return 0
        fi
    fi

    log_success "stack.storage_ballast_helper installed"
}

# Cross-provider AI coding session resumption — convert and resume sessions across providers (casr)
install_stack_cross_agent_session_resumer() {
    local module_id="stack.cross_agent_session_resumer"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.cross_agent_session_resumer"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.cross_agent_session_resumer"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="casr"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.cross_agent_session_resumer: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "stack.cross_agent_session_resumer: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.cross_agent_session_resumer: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.cross_agent_session_resumer: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.cross_agent_session_resumer: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.cross_agent_session_resumer: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.cross_agent_session_resumer"
                false
            fi
        }; then
            log_warn "stack.cross_agent_session_resumer: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.cross_agent_session_resumer" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.cross_agent_session_resumer"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: casr providers || casr --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_CROSS_AGENT_SESSION_RESUMER'
casr providers || casr --help
INSTALL_STACK_CROSS_AGENT_SESSION_RESUMER
        then
            log_warn "stack.cross_agent_session_resumer: verify failed: casr providers || casr --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.cross_agent_session_resumer" "verify failed: casr providers || casr --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.cross_agent_session_resumer"
            fi
            return 0
        fi
    fi

    log_success "stack.cross_agent_session_resumer installed"
}

# Fallback release infrastructure — local builds via act when GitHub Actions is throttled (dsr)
install_stack_doodlestein_self_releaser() {
    local module_id="stack.doodlestein_self_releaser"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.doodlestein_self_releaser"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: DSR_TMP=\"\$(mktemp -d \"\${TMPDIR:-/tmp}/dsr_install.XXXXXX\")\" (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_DOODLESTEIN_SELF_RELEASER'
DSR_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dsr_install.XXXXXX")"
cd "$DSR_TMP"
git clone --depth 1 https://github.com/Dicklesworthstone/doodlestein_self_releaser.git .
cp dsr ~/.local/bin/dsr
chmod 755 ~/.local/bin/dsr
cd ..
rm -rf "$DSR_TMP"
INSTALL_STACK_DOODLESTEIN_SELF_RELEASER
        then
            log_warn "stack.doodlestein_self_releaser: install command failed: DSR_TMP=\"\$(mktemp -d \"\${TMPDIR:-/tmp}/dsr_install.XXXXXX\")\""
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.doodlestein_self_releaser" "install command failed: DSR_TMP=\"\$(mktemp -d \"\${TMPDIR:-/tmp}/dsr_install.XXXXXX\")\""
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.doodlestein_self_releaser"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: dsr doctor || dsr --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_DOODLESTEIN_SELF_RELEASER'
dsr doctor || dsr --help
INSTALL_STACK_DOODLESTEIN_SELF_RELEASER
        then
            log_warn "stack.doodlestein_self_releaser: verify failed: dsr doctor || dsr --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.doodlestein_self_releaser" "verify failed: dsr doctor || dsr --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.doodlestein_self_releaser"
            fi
            return 0
        fi
    fi

    log_success "stack.doodlestein_self_releaser installed"
}

# Smart backup tool for AI coding agent configuration folders (asb)
install_stack_agent_settings_backup() {
    local module_id="stack.agent_settings_backup"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.agent_settings_backup"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.agent_settings_backup"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="asb"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.agent_settings_backup: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "stack.agent_settings_backup: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.agent_settings_backup: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.agent_settings_backup: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.agent_settings_backup: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.agent_settings_backup: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.agent_settings_backup"
                false
            fi
        }; then
            log_warn "stack.agent_settings_backup: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.agent_settings_backup" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.agent_settings_backup"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: asb version || asb help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_AGENT_SETTINGS_BACKUP'
asb version || asb help
INSTALL_STACK_AGENT_SETTINGS_BACKUP
        then
            log_warn "stack.agent_settings_backup: verify failed: asb version || asb help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.agent_settings_backup" "verify failed: asb version || asb help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.agent_settings_backup"
            fi
            return 0
        fi
    fi

    log_success "stack.agent_settings_backup installed"
}

# Post-compaction reminder hook for Claude Code that forces an AGENTS.md re-read
install_stack_pcr() {
    local module_id="stack.pcr"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.pcr"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.pcr"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="pcr"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.pcr: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--yes'; then
                            install_success=true
                        else
                            log_error "stack.pcr: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.pcr: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.pcr: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.pcr: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.pcr: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.pcr"
                false
            fi
        }; then
            log_warn "stack.pcr: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.pcr" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.pcr"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: target_home=\"\${TARGET_HOME:-\$HOME}\" (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_PCR'
target_home="${TARGET_HOME:-$HOME}"
hook_script="$target_home/.local/bin/claude-post-compact-reminder"
settings="$target_home/.claude/settings.json"
alt_settings="$target_home/.config/claude/settings.json"

test -x "$hook_script" || exit 1

if [[ -f "$settings" ]]; then
  grep -q "claude-post-compact-reminder" "$settings"
elif [[ -f "$alt_settings" ]]; then
  grep -q "claude-post-compact-reminder" "$alt_settings"
else
  exit 1
fi
INSTALL_STACK_PCR
        then
            log_warn "stack.pcr: verify failed: target_home=\"\${TARGET_HOME:-\$HOME}\""
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.pcr" "verify failed: target_home=\"\${TARGET_HOME:-\$HOME}\""
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.pcr"
            fi
            return 0
        fi
    fi

    log_success "stack.pcr installed"
}

# Install all stack modules
install_stack() {
    log_section "Installing stack modules"
    install_stack_ntm
    install_stack_mcp_agent_mail
    install_stack_meta_skill
    install_stack_automated_plan_reviser
    install_stack_jeffreysprompts
    install_stack_process_triage
    install_stack_ultimate_bug_scanner
    install_stack_beads_rust
    install_stack_beads_viewer
    install_stack_cass
    install_stack_cm
    install_stack_caam
    install_stack_slb
    install_stack_dcg
    install_stack_ru
    install_stack_brenner_bot
    install_stack_rch
    install_stack_wezterm_automata
    install_stack_srps
    install_stack_frankensearch
    install_stack_storage_ballast_helper
    install_stack_cross_agent_session_resumer
    install_stack_doodlestein_self_releaser
    install_stack_agent_settings_backup
    install_stack_pcr
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    install_stack
fi
