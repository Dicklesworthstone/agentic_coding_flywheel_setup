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

# Category: db
# Modules: 1

# PostgreSQL 18
install_db_postgres18() {
    log_step "Installing db.postgres18"

    # Add PGDG apt repo
    log_info "TODO: Add PGDG apt repo"
    sudo apt-get install -y postgresql-18

    # Verify
    psql --version || { log_error "Verify failed: db.postgres18"; return 1; }
    systemctl status postgresql --no-pager || log_warn "Optional: db.postgres18 verify skipped"

    log_success "db.postgres18 installed"
}

# Install all db modules
install_db() {
    log_section "Installing db modules"
    install_db_postgres18
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_db
fi
