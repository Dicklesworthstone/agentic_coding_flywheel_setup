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

# Category: cloud
# Modules: 4

# Cloudflare Wrangler CLI
install_cloud_wrangler() {
    local module_id="cloud.wrangler"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing cloud.wrangler"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: ~/.bun/bin/bun install -g --trust wrangler (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_CLOUD_WRANGLER'
~/.bun/bin/bun install -g --trust wrangler
INSTALL_CLOUD_WRANGLER
        then
            log_warn "cloud.wrangler: install command failed: ~/.bun/bin/bun install -g --trust wrangler"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "cloud.wrangler" "install command failed: ~/.bun/bin/bun install -g --trust wrangler"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "cloud.wrangler"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: wrangler --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_CLOUD_WRANGLER'
wrangler --version
INSTALL_CLOUD_WRANGLER
        then
            log_warn "cloud.wrangler: verify failed: wrangler --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "cloud.wrangler" "verify failed: wrangler --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "cloud.wrangler"
            fi
            return 0
        fi
    fi

    log_success "cloud.wrangler installed"
}

# Supabase CLI
install_cloud_supabase() {
    local module_id="cloud.supabase"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing cloud.supabase"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: ~/.bun/bin/bun install -g --trust supabase (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_CLOUD_SUPABASE'
~/.bun/bin/bun install -g --trust supabase
INSTALL_CLOUD_SUPABASE
        then
            log_warn "cloud.supabase: install command failed: ~/.bun/bin/bun install -g --trust supabase"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "cloud.supabase" "install command failed: ~/.bun/bin/bun install -g --trust supabase"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "cloud.supabase"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: supabase --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_CLOUD_SUPABASE'
supabase --version
INSTALL_CLOUD_SUPABASE
        then
            log_warn "cloud.supabase: verify failed: supabase --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "cloud.supabase" "verify failed: supabase --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "cloud.supabase"
            fi
            return 0
        fi
    fi

    log_success "cloud.supabase installed"
}

# Convex CLI
install_cloud_convex() {
    local module_id="cloud.convex"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing cloud.convex"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: ~/.bun/bin/bun install -g --trust convex (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_CLOUD_CONVEX'
~/.bun/bin/bun install -g --trust convex
INSTALL_CLOUD_CONVEX
        then
            log_warn "cloud.convex: install command failed: ~/.bun/bin/bun install -g --trust convex"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "cloud.convex" "install command failed: ~/.bun/bin/bun install -g --trust convex"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "cloud.convex"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: convex --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_CLOUD_CONVEX'
convex --version
INSTALL_CLOUD_CONVEX
        then
            log_warn "cloud.convex: verify failed: convex --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "cloud.convex" "verify failed: convex --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "cloud.convex"
            fi
            return 0
        fi
    fi

    log_success "cloud.convex installed"
}

# Vercel CLI
install_cloud_vercel() {
    local module_id="cloud.vercel"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing cloud.vercel"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: ~/.bun/bin/bun install -g --trust vercel (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_CLOUD_VERCEL'
~/.bun/bin/bun install -g --trust vercel
INSTALL_CLOUD_VERCEL
        then
            log_warn "cloud.vercel: install command failed: ~/.bun/bin/bun install -g --trust vercel"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "cloud.vercel" "install command failed: ~/.bun/bin/bun install -g --trust vercel"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "cloud.vercel"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: vercel --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_CLOUD_VERCEL'
vercel --version
INSTALL_CLOUD_VERCEL
        then
            log_warn "cloud.vercel: verify failed: vercel --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "cloud.vercel" "verify failed: vercel --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "cloud.vercel"
            fi
            return 0
        fi
    fi

    log_success "cloud.vercel installed"
}

# Install all cloud modules
install_cloud() {
    log_section "Installing cloud modules"
    install_cloud_wrangler
    install_cloud_supabase
    install_cloud_convex
    install_cloud_vercel
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_cloud
fi
