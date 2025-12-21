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

# Category: agents
# Modules: 3

# Claude Code
install_agents_claude() {
    local module_id="agents.claude"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing agents.claude"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verified installer: agents.claude"
    else
        if ! {
            # Verified upstream installer script (checksums.yaml)
            if ! acfs_security_init; then
                log_error "Security verification unavailable for agents.claude"
                false
            else
                local tool="claude"
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
            log_error "agents.claude: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: claude --version || claude --help"
    else
        if ! {
            claude --version || claude --help
        }; then
            log_error "agents.claude: verify failed: claude --version || claude --help"
            return 1
        fi
    fi

    log_success "agents.claude installed"
}

# OpenAI Codex CLI
install_agents_codex() {
    local module_id="agents.codex"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing agents.codex"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: ~/.bun/bin/bun install -g @openai/codex@latest (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_CODEX'
~/.bun/bin/bun install -g @openai/codex@latest
INSTALL_AGENTS_CODEX
        then
            log_error "agents.codex: install command failed: ~/.bun/bin/bun install -g @openai/codex@latest"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: codex --version || codex --help"
    else
        if ! {
            codex --version || codex --help
        }; then
            log_error "agents.codex: verify failed: codex --version || codex --help"
            return 1
        fi
    fi

    log_success "agents.codex installed"
}

# Google Gemini CLI
install_agents_gemini() {
    local module_id="agents.gemini"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing agents.gemini"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: ~/.bun/bin/bun install -g @google/gemini-cli@latest (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_GEMINI'
~/.bun/bin/bun install -g @google/gemini-cli@latest
INSTALL_AGENTS_GEMINI
        then
            log_error "agents.gemini: install command failed: ~/.bun/bin/bun install -g @google/gemini-cli@latest"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: gemini --version || gemini --help"
    else
        if ! {
            gemini --version || gemini --help
        }; then
            log_error "agents.gemini: verify failed: gemini --version || gemini --help"
            return 1
        fi
    fi

    log_success "agents.gemini installed"
}

# Install all agents modules
install_agents() {
    log_section "Installing agents modules"
    install_agents_claude
    install_agents_codex
    install_agents_gemini
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_agents
fi
