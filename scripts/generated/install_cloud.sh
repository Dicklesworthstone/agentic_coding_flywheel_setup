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
fi

# Category: cloud
# Modules: 3

# Cloudflare Wrangler CLI
install_cloud_wrangler() {
    log_step "Installing cloud.wrangler"

    ~/.bun/bin/bun install -g wrangler

    # Verify
    wrangler --version || { log_error "Verify failed: cloud.wrangler"; return 1; }

    log_success "cloud.wrangler installed"
}

# Supabase CLI
install_cloud_supabase() {
    log_step "Installing cloud.supabase"

    ~/.bun/bin/bun install -g supabase

    # Verify
    supabase --version || { log_error "Verify failed: cloud.supabase"; return 1; }

    log_success "cloud.supabase installed"
}

# Vercel CLI
install_cloud_vercel() {
    log_step "Installing cloud.vercel"

    ~/.bun/bin/bun install -g vercel

    # Verify
    vercel --version || { log_error "Verify failed: cloud.vercel"; return 1; }

    log_success "cloud.vercel installed"
}

# Install all cloud modules
install_cloud() {
    log_section "Installing cloud modules"
    install_cloud_wrangler
    install_cloud_supabase
    install_cloud_vercel
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_cloud
fi
