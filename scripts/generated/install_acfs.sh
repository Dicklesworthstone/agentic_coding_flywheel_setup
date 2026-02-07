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

# Category: acfs
# Modules: 5

# Agent workspace with tmux session and project folder
install_acfs_workspace() {
    local module_id="acfs.workspace"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing acfs.workspace"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: # Create project directory (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_WORKSPACE'
# Create project directory
mkdir -p /data/projects/my_first_project
cd /data/projects/my_first_project
git init 2>/dev/null || true
INSTALL_ACFS_WORKSPACE
        then
            log_error "acfs.workspace: install command failed: # Create project directory"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: # Create workspace instructions file (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_WORKSPACE'
# Create workspace instructions file
mkdir -p ~/.acfs
printf '%s\n' "" \
  "  ACFS AGENT WORKSPACE - QUICK REFERENCE" \
  "  --------------------------------------" \
  "" \
  "  RECONNECT AFTER SSH:" \
  "    tmux attach -t agents    OR just type:  agents" \
  "" \
  "  WINDOWS (Ctrl-b + number):" \
  "    0:welcome  - This instructions window" \
  "    1:claude   - Claude Code (Anthropic)" \
  "    2:codex    - Codex CLI (OpenAI)" \
  "    3:gemini   - Gemini CLI (Google)" \
  "" \
  "  TMUX BASICS:" \
  "    Ctrl-b d        - Detach (keep session running)" \
  "    Ctrl-b c        - Create new window" \
  "    Ctrl-b n/p      - Next/previous window" \
  "    Ctrl-b [0-9]    - Switch to window number" \
  "" \
  "  START AN AGENT:" \
  "    claude          - Start Claude Code" \
  "    codex           - Start Codex CLI" \
  "    gemini          - Start Gemini CLI" \
  "" \
  "  PROJECT: /data/projects/my_first_project" \
  "  (Rename with: mv /data/projects/my_first_project /data/projects/NEW_NAME)" \
  "" > ~/.acfs/workspace-instructions.txt
INSTALL_ACFS_WORKSPACE
        then
            log_error "acfs.workspace: install command failed: # Create workspace instructions file"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: # Create tmux session with agent panes (if not already running) (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_WORKSPACE'
# Create tmux session with agent panes (if not already running)
SESSION_NAME="agents"
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  # Create session with first window for instructions
  tmux new-session -d -s "$SESSION_NAME" -n "welcome" -c /data/projects/my_first_project

  # Add agent windows
  tmux new-window -t "$SESSION_NAME" -n "claude" -c /data/projects/my_first_project
  tmux new-window -t "$SESSION_NAME" -n "codex" -c /data/projects/my_first_project
  tmux new-window -t "$SESSION_NAME" -n "gemini" -c /data/projects/my_first_project

  # Send instructions to welcome window
  tmux send-keys -t "$SESSION_NAME:welcome" "cat ~/.acfs/workspace-instructions.txt" Enter

  # Select the welcome window
  tmux select-window -t "$SESSION_NAME:welcome"
fi
INSTALL_ACFS_WORKSPACE
        then
            log_error "acfs.workspace: install command failed: # Create tmux session with agent panes (if not already running)"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: # Add agents alias to zshrc.local if not already present (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_WORKSPACE'
# Add agents alias to zshrc.local if not already present
if [[ ! -f ~/.zshrc.local ]] || ! grep -q "alias agents=" ~/.zshrc.local; then
  touch ~/.zshrc.local 2>/dev/null || true
  echo '' >> ~/.zshrc.local
  echo '# ACFS agents workspace alias' >> ~/.zshrc.local
  echo 'alias agents="tmux attach -t agents 2>/dev/null || tmux new-session -s agents -c /data/projects"' >> ~/.zshrc.local
fi
INSTALL_ACFS_WORKSPACE
        then
            log_error "acfs.workspace: install command failed: # Add agents alias to zshrc.local if not already present"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test -d /data/projects/my_first_project (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_WORKSPACE'
test -d /data/projects/my_first_project
INSTALL_ACFS_WORKSPACE
        then
            log_error "acfs.workspace: verify failed: test -d /data/projects/my_first_project"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: grep -q \"alias agents=\" ~/.zshrc.local || grep -q \"alias agents=\" ~/.zshrc (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_WORKSPACE'
grep -q "alias agents=" ~/.zshrc.local || grep -q "alias agents=" ~/.zshrc
INSTALL_ACFS_WORKSPACE
        then
            log_error "acfs.workspace: verify failed: grep -q \"alias agents=\" ~/.zshrc.local || grep -q \"alias agents=\" ~/.zshrc"
            return 1
        fi
    fi

    log_success "acfs.workspace installed"
}

# Onboarding TUI tutorial
install_acfs_onboard() {
    local module_id="acfs.onboard"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing acfs.onboard"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: mkdir -p ~/.local/bin (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_ONBOARD'
mkdir -p ~/.local/bin
INSTALL_ACFS_ONBOARD
        then
            log_error "acfs.onboard: install command failed: mkdir -p ~/.local/bin"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: # Install onboard script (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_ONBOARD'
# Install onboard script
if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -f "${ACFS_BOOTSTRAP_DIR}/packages/onboard/onboard.sh" ]]; then
  cp "${ACFS_BOOTSTRAP_DIR}/packages/onboard/onboard.sh" ~/.local/bin/onboard
elif [[ -f "packages/onboard/onboard.sh" ]]; then
  cp "packages/onboard/onboard.sh" ~/.local/bin/onboard
else
  ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${ACFS_RAW}/packages/onboard/onboard.sh" -o ~/.local/bin/onboard
fi
chmod +x ~/.local/bin/onboard
INSTALL_ACFS_ONBOARD
        then
            log_error "acfs.onboard: install command failed: # Install onboard script"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: onboard --help || command -v onboard (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_ONBOARD'
onboard --help || command -v onboard
INSTALL_ACFS_ONBOARD
        then
            log_error "acfs.onboard: verify failed: onboard --help || command -v onboard"
            return 1
        fi
    fi

    log_success "acfs.onboard installed"
}

# ACFS update command wrapper
install_acfs_update() {
    local module_id="acfs.update"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing acfs.update"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: mkdir -p ~/.local/bin (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_UPDATE'
mkdir -p ~/.local/bin
INSTALL_ACFS_UPDATE
        then
            log_error "acfs.update: install command failed: mkdir -p ~/.local/bin"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: # Install acfs-update wrapper (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_UPDATE'
# Install acfs-update wrapper
if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -f "${ACFS_BOOTSTRAP_DIR}/scripts/acfs-update" ]]; then
  cp "${ACFS_BOOTSTRAP_DIR}/scripts/acfs-update" ~/.local/bin/acfs-update
elif [[ -f "scripts/acfs-update" ]]; then
  cp "scripts/acfs-update" ~/.local/bin/acfs-update
else
  ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${ACFS_RAW}/scripts/acfs-update" -o ~/.local/bin/acfs-update
fi
chmod +x ~/.local/bin/acfs-update
INSTALL_ACFS_UPDATE
        then
            log_error "acfs.update: install command failed: # Install acfs-update wrapper"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: command -v acfs-update (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_UPDATE'
command -v acfs-update
INSTALL_ACFS_UPDATE
        then
            log_error "acfs.update: verify failed: command -v acfs-update"
            return 1
        fi
    fi

    log_success "acfs.update installed"
}

# Nightly auto-update timer (systemd)
install_acfs_nightly() {
    local module_id="acfs.nightly"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing acfs.nightly"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: mkdir -p ~/.acfs/scripts ~/.config/systemd/user (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_NIGHTLY'
mkdir -p ~/.acfs/scripts ~/.config/systemd/user
INSTALL_ACFS_NIGHTLY
        then
            log_warn "acfs.nightly: install command failed: mkdir -p ~/.acfs/scripts ~/.config/systemd/user"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "acfs.nightly" "install command failed: mkdir -p ~/.acfs/scripts ~/.config/systemd/user"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "acfs.nightly"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: # Install nightly update wrapper script (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_NIGHTLY'
# Install nightly update wrapper script
if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -f "${ACFS_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh" ]]; then
  cp "${ACFS_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh" ~/.acfs/scripts/nightly-update.sh
elif [[ -f "scripts/lib/nightly_update.sh" ]]; then
  cp "scripts/lib/nightly_update.sh" ~/.acfs/scripts/nightly-update.sh
else
  ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${ACFS_RAW}/scripts/lib/nightly_update.sh" -o ~/.acfs/scripts/nightly-update.sh
fi
chmod +x ~/.acfs/scripts/nightly-update.sh
INSTALL_ACFS_NIGHTLY
        then
            log_warn "acfs.nightly: install command failed: # Install nightly update wrapper script"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "acfs.nightly" "install command failed: # Install nightly update wrapper script"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "acfs.nightly"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: # Install systemd timer unit (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_NIGHTLY'
# Install systemd timer unit
if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -f "${ACFS_BOOTSTRAP_DIR}/scripts/templates/acfs-nightly-update.timer" ]]; then
  cp "${ACFS_BOOTSTRAP_DIR}/scripts/templates/acfs-nightly-update.timer" ~/.config/systemd/user/acfs-nightly-update.timer
elif [[ -f "scripts/templates/acfs-nightly-update.timer" ]]; then
  cp "scripts/templates/acfs-nightly-update.timer" ~/.config/systemd/user/acfs-nightly-update.timer
else
  ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${ACFS_RAW}/scripts/templates/acfs-nightly-update.timer" -o ~/.config/systemd/user/acfs-nightly-update.timer
fi
INSTALL_ACFS_NIGHTLY
        then
            log_warn "acfs.nightly: install command failed: # Install systemd timer unit"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "acfs.nightly" "install command failed: # Install systemd timer unit"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "acfs.nightly"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: # Install systemd service unit (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_NIGHTLY'
# Install systemd service unit
if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -f "${ACFS_BOOTSTRAP_DIR}/scripts/templates/acfs-nightly-update.service" ]]; then
  cp "${ACFS_BOOTSTRAP_DIR}/scripts/templates/acfs-nightly-update.service" ~/.config/systemd/user/acfs-nightly-update.service
elif [[ -f "scripts/templates/acfs-nightly-update.service" ]]; then
  cp "scripts/templates/acfs-nightly-update.service" ~/.config/systemd/user/acfs-nightly-update.service
else
  ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${ACFS_RAW}/scripts/templates/acfs-nightly-update.service" -o ~/.config/systemd/user/acfs-nightly-update.service
fi
INSTALL_ACFS_NIGHTLY
        then
            log_warn "acfs.nightly: install command failed: # Install systemd service unit"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "acfs.nightly" "install command failed: # Install systemd service unit"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "acfs.nightly"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: # Reload systemd and enable the timer (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_NIGHTLY'
# Reload systemd and enable the timer
systemctl --user daemon-reload
systemctl --user enable --now acfs-nightly-update.timer
INSTALL_ACFS_NIGHTLY
        then
            log_warn "acfs.nightly: install command failed: # Reload systemd and enable the timer"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "acfs.nightly" "install command failed: # Reload systemd and enable the timer"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "acfs.nightly"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: systemctl --user is-enabled acfs-nightly-update.timer (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_NIGHTLY'
systemctl --user is-enabled acfs-nightly-update.timer
INSTALL_ACFS_NIGHTLY
        then
            log_warn "acfs.nightly: verify failed: systemctl --user is-enabled acfs-nightly-update.timer"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "acfs.nightly" "verify failed: systemctl --user is-enabled acfs-nightly-update.timer"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "acfs.nightly"
            fi
            return 0
        fi
    fi

    log_success "acfs.nightly installed"
}

# ACFS doctor command for health checks
install_acfs_doctor() {
    local module_id="acfs.doctor"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing acfs.doctor"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: mkdir -p ~/.local/bin (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_DOCTOR'
mkdir -p ~/.local/bin
INSTALL_ACFS_DOCTOR
        then
            log_error "acfs.doctor: install command failed: mkdir -p ~/.local/bin"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: # Install acfs CLI (doctor.sh entrypoint) (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_DOCTOR'
# Install acfs CLI (doctor.sh entrypoint)
if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -f "${ACFS_BOOTSTRAP_DIR}/scripts/lib/doctor.sh" ]]; then
  cp "${ACFS_BOOTSTRAP_DIR}/scripts/lib/doctor.sh" ~/.local/bin/acfs
elif [[ -f "scripts/lib/doctor.sh" ]]; then
  cp "scripts/lib/doctor.sh" ~/.local/bin/acfs
else
  ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${ACFS_RAW}/scripts/lib/doctor.sh" -o ~/.local/bin/acfs
fi
chmod +x ~/.local/bin/acfs
INSTALL_ACFS_DOCTOR
        then
            log_error "acfs.doctor: install command failed: # Install acfs CLI (doctor.sh entrypoint)"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: acfs doctor --help || command -v acfs (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_DOCTOR'
acfs doctor --help || command -v acfs
INSTALL_ACFS_DOCTOR
        then
            log_error "acfs.doctor: verify failed: acfs doctor --help || command -v acfs"
            return 1
        fi
    fi

    log_success "acfs.doctor installed"
}

# Install all acfs modules
install_acfs() {
    log_section "Installing acfs modules"
    install_acfs_workspace
    install_acfs_onboard
    install_acfs_update
    install_acfs_nightly
    install_acfs_doctor
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    install_acfs
fi
