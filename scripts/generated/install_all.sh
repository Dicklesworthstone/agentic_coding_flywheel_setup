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

# Master installer - sources all category scripts

source "$ACFS_GENERATED_SCRIPT_DIR/install_base.sh"
source "$ACFS_GENERATED_SCRIPT_DIR/install_users.sh"
source "$ACFS_GENERATED_SCRIPT_DIR/install_filesystem.sh"
source "$ACFS_GENERATED_SCRIPT_DIR/install_shell.sh"
source "$ACFS_GENERATED_SCRIPT_DIR/install_cli.sh"
source "$ACFS_GENERATED_SCRIPT_DIR/install_tools.sh"
source "$ACFS_GENERATED_SCRIPT_DIR/install_network.sh"
source "$ACFS_GENERATED_SCRIPT_DIR/install_lang.sh"
source "$ACFS_GENERATED_SCRIPT_DIR/install_agents.sh"
source "$ACFS_GENERATED_SCRIPT_DIR/install_db.sh"
source "$ACFS_GENERATED_SCRIPT_DIR/install_cloud.sh"
source "$ACFS_GENERATED_SCRIPT_DIR/install_stack.sh"
source "$ACFS_GENERATED_SCRIPT_DIR/install_acfs.sh"

# Install all modules in global dependency order
install_all() {
    log_section "ACFS Full Installation"

    log_section "Category: base"
    install_base_system
    log_section "Category: users"
    install_users_ubuntu
    log_section "Category: filesystem"
    install_base_filesystem
    log_section "Category: shell"
    install_shell_zsh
    install_shell_omz
    log_section "Category: cli"
    install_cli_modern
    log_section "Category: tools"
    install_tools_lazygit
    install_tools_lazydocker
    log_section "Category: network"
    install_network_tailscale
    install_network_ssh_keepalive
    log_section "Category: lang"
    install_lang_bun
    install_lang_uv
    install_lang_rust
    install_lang_go
    install_lang_nvm
    log_section "Category: tools"
    install_tools_atuin
    install_tools_zoxide
    install_tools_ast_grep
    log_section "Category: agents"
    install_agents_claude
    install_agents_codex
    install_agents_gemini
    log_section "Category: tools"
    install_tools_vault
    log_section "Category: db"
    install_db_postgres18
    log_section "Category: cloud"
    install_cloud_wrangler
    install_cloud_supabase
    install_cloud_vercel
    log_section "Category: stack"
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
    log_section "Category: tools"
    install_utils_giil
    install_utils_csctf
    install_utils_xf
    install_utils_toon_rust
    install_utils_rano
    install_utils_mdwb
    install_utils_s2p
    install_utils_rust_proxy
    install_utils_aadc
    install_utils_caut
    log_section "Category: acfs"
    install_acfs_workspace
    install_acfs_onboard
    install_acfs_update
    install_acfs_nightly
    install_acfs_doctor

    log_success "All modules installed!"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    install_all
fi
