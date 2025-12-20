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

# Master installer - sources all category scripts

source "$SCRIPT_DIR/install_base.sh"
source "$SCRIPT_DIR/install_users.sh"
source "$SCRIPT_DIR/install_shell.sh"
source "$SCRIPT_DIR/install_cli.sh"
source "$SCRIPT_DIR/install_lang.sh"
source "$SCRIPT_DIR/install_tools.sh"
source "$SCRIPT_DIR/install_db.sh"
source "$SCRIPT_DIR/install_cloud.sh"
source "$SCRIPT_DIR/install_agents.sh"
source "$SCRIPT_DIR/install_stack.sh"
source "$SCRIPT_DIR/install_acfs.sh"

# Install all modules in order
install_all() {
    log_section "ACFS Full Installation"

    install_base
    install_users
    install_shell
    install_cli
    install_lang
    install_tools
    install_db
    install_cloud
    install_agents
    install_stack
    install_acfs

    log_success "All modules installed!"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_all
fi
