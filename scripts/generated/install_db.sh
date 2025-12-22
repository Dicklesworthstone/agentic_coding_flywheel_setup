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

# Category: db
# Modules: 1

# PostgreSQL 18
install_db_postgres18() {
    local module_id="db.postgres18"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing db.postgres18"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: mkdir -p /etc/apt/keyrings (root)"
    else
        if ! run_as_root_shell <<'INSTALL_DB_POSTGRES18'
mkdir -p /etc/apt/keyrings
curl --proto '=https' --proto-redir '=https' -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --batch --yes --dearmor -o /etc/apt/keyrings/postgresql.gpg
CODENAME=$(lsb_release -cs 2>/dev/null || echo "noble")
case "$CODENAME" in
  oracular|plucky|questing) CODENAME="noble" ;;
esac
echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt ${CODENAME}-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list
INSTALL_DB_POSTGRES18
        then
            log_warn "db.postgres18: install command failed: mkdir -p /etc/apt/keyrings"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "db.postgres18" "install command failed: mkdir -p /etc/apt/keyrings"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "db.postgres18"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: apt-get update (root)"
    else
        if ! run_as_root_shell <<'INSTALL_DB_POSTGRES18'
apt-get update
INSTALL_DB_POSTGRES18
        then
            log_warn "db.postgres18: install command failed: apt-get update"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "db.postgres18" "install command failed: apt-get update"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "db.postgres18"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: apt-get install -y postgresql-18 (root)"
    else
        if ! run_as_root_shell <<'INSTALL_DB_POSTGRES18'
apt-get install -y postgresql-18
INSTALL_DB_POSTGRES18
        then
            log_warn "db.postgres18: install command failed: apt-get install -y postgresql-18"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "db.postgres18" "install command failed: apt-get install -y postgresql-18"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "db.postgres18"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify: psql --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_DB_POSTGRES18'
psql --version
INSTALL_DB_POSTGRES18
        then
            log_warn "db.postgres18: verify failed: psql --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "db.postgres18" "verify failed: psql --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "db.postgres18"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verify (optional): systemctl status postgresql --no-pager (root)"
    else
        if ! run_as_root_shell <<'INSTALL_DB_POSTGRES18'
systemctl status postgresql --no-pager
INSTALL_DB_POSTGRES18
        then
            log_warn "Optional verify failed: db.postgres18"
        fi
    fi

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
