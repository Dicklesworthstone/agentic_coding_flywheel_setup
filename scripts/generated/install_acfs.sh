#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================

set -euo pipefail

# Resolve relative helper paths first.
ACFS_GENERATED_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure logging functions available
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

acfs_generated_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..)
            return 1
            ;;
        *[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    for candidate in \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

acfs_generated_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(acfs_generated_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(acfs_generated_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

acfs_generated_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(acfs_generated_system_binary_path getent 2>/dev/null || true)"
    if [[ -z "$user" ]]; then
        if [[ -n "$getent_bin" ]]; then
            while IFS= read -r passwd_line; do
                printf '%s\n' "$passwd_line"
                printed_any=true
            done < <("$getent_bin" passwd 2>/dev/null || true)
            if [[ "$printed_any" == true ]]; then
                return 0
            fi
        fi

        [[ -r /etc/passwd ]] || return 1
        while IFS= read -r passwd_line; do
            printf '%s\n' "$passwd_line"
        done < /etc/passwd
        return 0
    fi

    if [[ -n "$getent_bin" ]]; then
        passwd_entry="$("$getent_bin" passwd "$user" 2>/dev/null || true)"
    fi

    if [[ -z "$passwd_entry" ]] && [[ -r /etc/passwd ]]; then
        while IFS= read -r passwd_line; do
            [[ "${passwd_line%%:*}" == "$user" ]] || continue
            passwd_entry="$passwd_line"
            break
        done < /etc/passwd
    fi

    [[ -n "$passwd_entry" ]] || return 1
    printf '%s\n' "$passwd_entry"
}

acfs_generated_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    if [[ -n "$passwd_home" ]] && [[ "$passwd_home" == /* ]] && [[ "$passwd_home" != "/" ]]; then
        printf '%s\n' "${passwd_home%/}"
        return 0
    fi

    return 1
}

acfs_generated_target_user_exists() {
    local user="${1:-}"
    local id_bin=""

    [[ -n "$user" ]] || return 1
    id_bin="$(acfs_generated_system_binary_path id 2>/dev/null || true)"
    [[ -n "$id_bin" ]] || return 1
    "$id_bin" "$user" >/dev/null 2>&1
}

acfs_generated_default_home_for_new_user() {
    local user="${1:-}"

    [[ -n "$user" ]] || return 1
    [[ "$user" =~ ^[a-z_][a-z0-9._-]*$ ]] || return 1

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    printf '/home/%s\n' "$user"
}

# When running a generated installer directly (not sourced by install.sh),
# set sane defaults and derive ACFS paths from the script location so
# contract validation passes and local assets are discoverable.
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    # Match install.sh defaults
    if [[ -z "${TARGET_USER:-}" ]]; then
        if [[ $EUID -eq 0 ]] && [[ -z "${SUDO_USER:-}" ]]; then
            _ACFS_DETECTED_USER="ubuntu"
        else
            _ACFS_DETECTED_USER="${SUDO_USER:-}"
            if [[ -z "$_ACFS_DETECTED_USER" ]]; then
                _ACFS_DETECTED_USER="$(acfs_generated_resolve_current_user 2>/dev/null || true)"
            fi
            if [[ -z "$_ACFS_DETECTED_USER" ]]; then
                log_error "Unable to resolve the current user for TARGET_USER"
                exit 1
            fi
        fi
        TARGET_USER="$_ACFS_DETECTED_USER"
    fi
    unset _ACFS_DETECTED_USER

    if declare -f _acfs_validate_target_user >/dev/null 2>&1; then
        _acfs_validate_target_user "${TARGET_USER}" "TARGET_USER" || exit 1
    elif [[ -z "${TARGET_USER:-}" ]] || [[ ! "${TARGET_USER}" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
        log_error "Invalid TARGET_USER '${TARGET_USER:-<empty>}' (expected: lowercase user name like 'ubuntu')"
        exit 1
    fi

    MODE="${MODE:-vibe}"

    _ACFS_EXPLICIT_TARGET_HOME="${TARGET_HOME:-}"
    if [[ -n "$_ACFS_EXPLICIT_TARGET_HOME" ]]; then
        _ACFS_EXPLICIT_TARGET_HOME="${_ACFS_EXPLICIT_TARGET_HOME%/}"
    fi
    _ACFS_RESOLVED_TARGET_HOME=""
    if declare -f _acfs_resolve_target_home >/dev/null 2>&1; then
        _ACFS_RESOLVED_TARGET_HOME="$(_acfs_resolve_target_home "${TARGET_USER}" "$_ACFS_EXPLICIT_TARGET_HOME" || true)"
    else
        if [[ "${TARGET_USER}" == "root" ]]; then
            _ACFS_RESOLVED_TARGET_HOME="/root"
        else
            _acfs_passwd_entry="$(acfs_generated_getent_passwd_entry "${TARGET_USER}" 2>/dev/null || true)"
            if [[ -n "$_acfs_passwd_entry" ]]; then
                _ACFS_RESOLVED_TARGET_HOME="$(acfs_generated_passwd_home_from_entry "$_acfs_passwd_entry" 2>/dev/null || true)"
            else
                _acfs_current_user="$(acfs_generated_resolve_current_user 2>/dev/null || true)"
                _acfs_current_home="${HOME:-}"
                if [[ -n "$_acfs_current_home" ]]; then
                    _acfs_current_home="${_acfs_current_home%/}"
                fi
                if [[ "${_acfs_current_user:-}" == "${TARGET_USER}" ]] && [[ -n "$_acfs_current_home" ]] && [[ "$_acfs_current_home" == /* ]] && [[ "$_acfs_current_home" != "/" ]] && { [[ -z "$_ACFS_EXPLICIT_TARGET_HOME" ]] || [[ "$_acfs_current_home" == "$_ACFS_EXPLICIT_TARGET_HOME" ]]; }; then
                    _ACFS_RESOLVED_TARGET_HOME="$_acfs_current_home"
                fi
                unset _acfs_current_user _acfs_current_home
            fi
            unset _acfs_passwd_entry
        fi
    fi
    if [[ -z "$_ACFS_RESOLVED_TARGET_HOME" ]] && [[ $EUID -eq 0 ]] && ! acfs_generated_target_user_exists "${TARGET_USER}"; then
        if [[ -n "$_ACFS_EXPLICIT_TARGET_HOME" ]] && [[ "$_ACFS_EXPLICIT_TARGET_HOME" == /* ]] && [[ "$_ACFS_EXPLICIT_TARGET_HOME" != "/" ]]; then
            _ACFS_RESOLVED_TARGET_HOME="$_ACFS_EXPLICIT_TARGET_HOME"
        else
            _ACFS_RESOLVED_TARGET_HOME="$(acfs_generated_default_home_for_new_user "${TARGET_USER}" 2>/dev/null || true)"
        fi
    fi
    if [[ -n "$_ACFS_RESOLVED_TARGET_HOME" ]]; then
        TARGET_HOME="${_ACFS_RESOLVED_TARGET_HOME%/}"
    fi
    unset _ACFS_EXPLICIT_TARGET_HOME _ACFS_RESOLVED_TARGET_HOME

    if [[ -z "${TARGET_HOME:-}" ]] || [[ "${TARGET_HOME}" == "/" ]] || [[ "${TARGET_HOME}" != /* ]]; then
        log_error "Invalid TARGET_HOME for '${TARGET_USER}': ${TARGET_HOME:-<empty>} (must be an absolute path and cannot be '/')"
        exit 1
    fi

    # Derive "bootstrap" paths from the repo layout (scripts/generated/.. -> repo root).
    if [[ -z "${ACFS_BOOTSTRAP_DIR:-}" ]]; then
        ACFS_BOOTSTRAP_DIR="$(cd "$ACFS_GENERATED_SCRIPT_DIR/../.." && pwd)"
    fi

    ACFS_BIN_DIR="${ACFS_BIN_DIR:-$TARGET_HOME/.local/bin}"
    if [[ -z "${ACFS_BIN_DIR:-}" ]] || [[ "${ACFS_BIN_DIR}" == "/" ]] || [[ "${ACFS_BIN_DIR}" != /* ]]; then
        log_error "ACFS_BIN_DIR must be an absolute path and cannot be '/' (got: ${ACFS_BIN_DIR:-<empty>})"
        exit 1
    fi
    ACFS_LIB_DIR="${ACFS_LIB_DIR:-$ACFS_BOOTSTRAP_DIR/scripts/lib}"
    ACFS_GENERATED_DIR="${ACFS_GENERATED_DIR:-$ACFS_BOOTSTRAP_DIR/scripts/generated}"
    ACFS_ASSETS_DIR="${ACFS_ASSETS_DIR:-$ACFS_BOOTSTRAP_DIR/acfs}"
    ACFS_CHECKSUMS_YAML="${ACFS_CHECKSUMS_YAML:-$ACFS_BOOTSTRAP_DIR/checksums.yaml}"
    ACFS_MANIFEST_YAML="${ACFS_MANIFEST_YAML:-$ACFS_BOOTSTRAP_DIR/acfs.manifest.yaml}"

    export TARGET_USER TARGET_HOME MODE ACFS_BIN_DIR
    export ACFS_BOOTSTRAP_DIR ACFS_LIB_DIR ACFS_GENERATED_DIR ACFS_ASSETS_DIR ACFS_CHECKSUMS_YAML ACFS_MANIFEST_YAML

    # Defensive ownership repair (#306): when running as root, make sure the
    # target user owns their XDG bin dir before the user-space language
    # installers (uv/rust/bun) write into it. uv installs via an atomic
    # mktemp+rename inside ~/.local/bin, so a root-owned ~/.local/bin makes its
    # mktemp fail with "Permission denied (os error 13)" once the installer is
    # re-exec'd as the (non-root) target user. The chown is NON-recursive on
    # purpose — only the two directories themselves, never their contents (never
    # chown -R ~/.local, which would clobber ownership of unrelated state).
    if [[ $EUID -eq 0 ]] && [[ -n "${TARGET_USER:-}" ]] && [[ "${TARGET_USER}" != "root" ]]; then
        _acfs_repair_mkdir="$(_acfs_system_binary_path mkdir 2>/dev/null || true)"
        _acfs_repair_chown="$(_acfs_system_binary_path chown 2>/dev/null || true)"
        if [[ -n "$_acfs_repair_mkdir" ]] && [[ -n "$_acfs_repair_chown" ]]; then
            if "$_acfs_repair_mkdir" -p "$TARGET_HOME/.local/bin" 2>/dev/null; then
                "$_acfs_repair_chown" "${TARGET_USER}" "$TARGET_HOME/.local" "$TARGET_HOME/.local/bin" 2>/dev/null || true
            fi
        fi
        unset _acfs_repair_mkdir _acfs_repair_chown
    fi
fi

acfs_generated_ensure_selection() {
    if [[ "${ACFS_MANIFEST_INDEX_LOADED:-false}" != "true" ]]; then
        local manifest_index="${ACFS_GENERATED_DIR:-$ACFS_GENERATED_SCRIPT_DIR}/manifest_index.sh"
        if [[ ! -f "$manifest_index" ]]; then
            log_error "Manifest index not found: $manifest_index"
            return 1
        fi
        source "$manifest_index"
        ACFS_MANIFEST_INDEX_LOADED=true
        export ACFS_MANIFEST_INDEX_LOADED
    fi

    if [[ "${ACFS_GENERATED_SELECTION_READY:-false}" != "true" ]]; then
        if ! declare -f acfs_resolve_selection >/dev/null 2>&1; then
            log_error "Install selection helper not loaded"
            return 1
        fi
        acfs_resolve_selection || return 1
        ACFS_GENERATED_SELECTION_READY=true
        export ACFS_GENERATED_SELECTION_READY
    fi

    return 0
}

acfs_generated_should_run_module() {
    local module_id="${1:-}"
    [[ -n "$module_id" ]] || return 1
    acfs_generated_ensure_selection || return 1
    should_run_module "$module_id"
}

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
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping acfs.workspace (not selected)"
        return 0
    fi
    log_step "Installing acfs.workspace"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: mkdir -p /data/projects/my_first_project (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_WORKSPACE'
# Create project directory
mkdir -p /data/projects/my_first_project
cd /data/projects/my_first_project
git init 2>/dev/null || true
INSTALL_ACFS_WORKSPACE
        then
            log_warn "acfs.workspace: install command failed: mkdir -p /data/projects/my_first_project"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "acfs.workspace" "install command failed: mkdir -p /data/projects/my_first_project"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "acfs.workspace"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: mkdir -p ~/.acfs (target_user)"
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
  "    3:agy      - Antigravity CLI (Google)" \
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
  "    agy             - Start Antigravity CLI" \
  "" \
  "  PROJECT: /data/projects/my_first_project" \
  "  (Rename with: mv /data/projects/my_first_project /data/projects/NEW_NAME)" \
  "" > ~/.acfs/workspace-instructions.txt
INSTALL_ACFS_WORKSPACE
        then
            log_warn "acfs.workspace: install command failed: mkdir -p ~/.acfs"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "acfs.workspace" "install command failed: mkdir -p ~/.acfs"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "acfs.workspace"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if ! tmux has-session -t \"\$SESSION_NAME\" 2>/dev/null; then (target_user)"
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
  tmux new-window -t "$SESSION_NAME" -n "agy" -c /data/projects/my_first_project

  # Send instructions to welcome window
  tmux send-keys -t "$SESSION_NAME:welcome" "cat ~/.acfs/workspace-instructions.txt" Enter

  # Select the welcome window
  tmux select-window -t "$SESSION_NAME:welcome"
fi
INSTALL_ACFS_WORKSPACE
        then
            log_warn "acfs.workspace: install command failed: if ! tmux has-session -t \"\$SESSION_NAME\" 2>/dev/null; then"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "acfs.workspace" "install command failed: if ! tmux has-session -t \"\$SESSION_NAME\" 2>/dev/null; then"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "acfs.workspace"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if ! acfs_has_active_agents_alias ~/.zshrc.local; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_WORKSPACE'
# Add agents alias to zshrc.local if not already present
acfs_has_active_agents_alias() {
  local file="${1:-}"
  [[ -f "$file" ]] || return 1

  awk '
      /^[[:space:]]*#/ { next }
      /^[[:space:]]*alias[[:space:]]+agents=/ { found=1; exit }
      END { exit(found ? 0 : 1) }
  ' "$file" 2>/dev/null
}

if ! acfs_has_active_agents_alias ~/.zshrc.local; then
  touch ~/.zshrc.local 2>/dev/null || true
  echo '' >> ~/.zshrc.local
  echo '# ACFS agents workspace alias' >> ~/.zshrc.local
  echo 'alias agents="tmux attach -t agents 2>/dev/null || tmux new-session -s agents -c /data/projects"' >> ~/.zshrc.local
fi
INSTALL_ACFS_WORKSPACE
        then
            log_warn "acfs.workspace: install command failed: if ! acfs_has_active_agents_alias ~/.zshrc.local; then"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "acfs.workspace" "install command failed: if ! acfs_has_active_agents_alias ~/.zshrc.local; then"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "acfs.workspace"
            fi
            return 0
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
            log_warn "acfs.workspace: verify failed: test -d /data/projects/my_first_project"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "acfs.workspace" "verify failed: test -d /data/projects/my_first_project"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "acfs.workspace"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: acfs_has_active_agents_alias ~/.zshrc.local || acfs_has_active_agents_alias ~/.zshrc (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_WORKSPACE'
acfs_has_active_agents_alias() {
  local file="${1:-}"
  [[ -f "$file" ]] || return 1

  awk '
      /^[[:space:]]*#/ { next }
      /^[[:space:]]*alias[[:space:]]+agents=/ { found=1; exit }
      END { exit(found ? 0 : 1) }
  ' "$file" 2>/dev/null
}

acfs_has_active_agents_alias ~/.zshrc.local || acfs_has_active_agents_alias ~/.zshrc
INSTALL_ACFS_WORKSPACE
        then
            log_warn "acfs.workspace: verify failed: acfs_has_active_agents_alias ~/.zshrc.local || acfs_has_active_agents_alias ~/.zshrc"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "acfs.workspace" "verify failed: acfs_has_active_agents_alias ~/.zshrc.local || acfs_has_active_agents_alias ~/.zshrc"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "acfs.workspace"
            fi
            return 0
        fi
    fi

    log_success "acfs.workspace installed"
}

# Onboarding TUI tutorial
install_acfs_onboard() {
    local module_id="acfs.onboard"
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping acfs.onboard (not selected)"
        return 0
    fi
    log_step "Installing acfs.onboard"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: trap 'rm -f \"\$onboard_tmp\"' EXIT (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_ONBOARD'
# Generated helper functions used by this child shell.
acfs_generated_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..)
            return 1
            ;;
        *[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    for candidate in \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

# Primary-bin helper functions used by this child shell.
acfs_child_log_error() {
    if declare -f log_error >/dev/null 2>&1; then
        log_error "$@"
    else
        echo "[ERROR] $*" >&2
    fi
}

acfs_child_primary_bin_dir() {
    local primary_bin_dir="${ACFS_BIN_DIR:-}"
    local fallback_home="${HOME:-}"

    if [[ -z "$primary_bin_dir" ]]; then
        if [[ -z "$fallback_home" ]] || [[ "$fallback_home" == "/" ]] || [[ "$fallback_home" != /* ]]; then
            acfs_child_log_error "ACFS_BIN_DIR is unset and HOME is not a usable absolute path"
            return 1
        fi
        primary_bin_dir="$fallback_home/.local/bin"
    fi

    if [[ -z "$primary_bin_dir" ]] || [[ "$primary_bin_dir" == "/" ]] || [[ "$primary_bin_dir" != /* ]]; then
        acfs_child_log_error "ACFS_BIN_DIR must be an absolute path and cannot be '/' (got: ${primary_bin_dir:-<empty>})"
        return 1
    fi

    printf '%s\n' "$primary_bin_dir"
}

acfs_child_primary_bin_requires_root() {
    local primary_bin_dir="$1"
    local target_home="${TARGET_HOME:-${HOME:-}}"

    [[ -n "$target_home" && "$target_home" == /* && "$target_home" != "/" ]] || return 0
    case "$primary_bin_dir" in
        "$target_home"|"$target_home"/*) return 1 ;;
        *) return 0 ;;
    esac
}

acfs_child_run_root_bin_command() {
    if [[ -z "${1:-}" || "${1:-}" != /* ]]; then
        acfs_child_log_error "Root primary bin command must be an absolute trusted path (got: ${1:-<empty>})"
        return 1
    fi

    if [[ $EUID -eq 0 ]]; then
        "$@"
        return $?
    fi

    local sudo_bin=""
    sudo_bin="$(acfs_generated_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        "$sudo_bin" -n "$@"
        return $?
    fi

    acfs_child_log_error "Primary bin dir requires root, but sudo is unavailable: ${ACFS_BIN_DIR:-<unset>}"
    return 1
}

acfs_child_primary_bin_tool_path() {
    local name="${1:-}"
    local tool_path=""

    tool_path="$(acfs_generated_system_binary_path "$name" 2>/dev/null || true)"
    if [[ -z "$tool_path" ]]; then
        acfs_child_log_error "Unable to locate trusted $name for primary bin operation"
        return 1
    fi

    printf '%s\n' "$tool_path"
}

acfs_child_ensure_primary_bin_dir() {
    local primary_bin_dir="$1"
    local mkdir_bin=""

    mkdir_bin="$(acfs_child_primary_bin_tool_path mkdir)" || return 1

    if acfs_child_primary_bin_requires_root "$primary_bin_dir"; then
        acfs_child_run_root_bin_command "$mkdir_bin" -p "$primary_bin_dir"
        return $?
    fi

    "$mkdir_bin" -p "$primary_bin_dir"
}

acfs_link_primary_bin_command() {
    local source_path="$1"
    local command_name="$2"
    local primary_bin_dir=""
    local dest_path=""
    local ln_bin=""

    primary_bin_dir="$(acfs_child_primary_bin_dir)" || return 1
    dest_path="$primary_bin_dir/$command_name"
    acfs_child_ensure_primary_bin_dir "$primary_bin_dir" || return 1
    ln_bin="$(acfs_child_primary_bin_tool_path ln)" || return 1

    if acfs_child_primary_bin_requires_root "$primary_bin_dir"; then
        acfs_child_run_root_bin_command "$ln_bin" -sf "$source_path" "$dest_path"
        return $?
    fi

    "$ln_bin" -sf "$source_path" "$dest_path"
}

acfs_install_executable_into_primary_bin() {
    local src_path="$1"
    local command_name="$2"
    local primary_bin_dir=""
    local dest_path=""
    local install_bin=""

    primary_bin_dir="$(acfs_child_primary_bin_dir)" || return 1
    dest_path="$primary_bin_dir/$command_name"
    acfs_child_ensure_primary_bin_dir "$primary_bin_dir" || return 1
    install_bin="$(acfs_child_primary_bin_tool_path install)" || return 1

    if acfs_child_primary_bin_requires_root "$primary_bin_dir"; then
        acfs_child_run_root_bin_command "$install_bin" -m 0755 "$src_path" "$dest_path"
        return $?
    fi

    "$install_bin" -m 0755 "$src_path" "$dest_path"
}

onboard_tmp="$(mktemp "${TMPDIR:-/tmp}/acfs-onboard.XXXXXX")"
trap 'rm -f "$onboard_tmp"' EXIT
# Install onboard script
if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -f "${ACFS_BOOTSTRAP_DIR}/packages/onboard/onboard.sh" ]]; then
  cp "${ACFS_BOOTSTRAP_DIR}/packages/onboard/onboard.sh" "$onboard_tmp"
elif [[ -f "packages/onboard/onboard.sh" ]]; then
  cp "packages/onboard/onboard.sh" "$onboard_tmp"
else
  ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${ACFS_REF:-main}}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${ACFS_RAW}/packages/onboard/onboard.sh" -o "$onboard_tmp"
fi
acfs_install_executable_into_primary_bin "$onboard_tmp" "onboard"
if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1 && { [[ ! -e /usr/local/bin/onboard ]] || [[ -L /usr/local/bin/onboard ]]; }; then
  sudo -n ln -sf "$HOME/.acfs/onboard/onboard.sh" /usr/local/bin/onboard
fi
INSTALL_ACFS_ONBOARD
        then
            log_error "acfs.onboard: install command failed: trap 'rm -f \"\$onboard_tmp\"' EXIT"
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
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping acfs.update (not selected)"
        return 0
    fi
    log_step "Installing acfs.update"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: mkdir -p ~/.acfs/scripts (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_UPDATE'
mkdir -p ~/.acfs/scripts
INSTALL_ACFS_UPDATE
        then
            log_error "acfs.update: install command failed: mkdir -p ~/.acfs/scripts"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ -n \"\${ACFS_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${ACFS_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh\" ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_UPDATE'
# Install acfs-update wrapper
if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -f "${ACFS_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh" ]]; then
  cp "${ACFS_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh" ~/.acfs/scripts/nightly-update.sh
elif [[ -f "scripts/lib/nightly_update.sh" ]]; then
  cp "scripts/lib/nightly_update.sh" ~/.acfs/scripts/nightly-update.sh
else
  ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${ACFS_REF:-main}}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${ACFS_RAW}/scripts/lib/nightly_update.sh" -o ~/.acfs/scripts/nightly-update.sh
fi
chmod +x ~/.acfs/scripts/nightly-update.sh
INSTALL_ACFS_UPDATE
        then
            log_error "acfs.update: install command failed: if [[ -n \"\${ACFS_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${ACFS_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh\" ]]; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: trap 'rm -f \"\$update_tmp\"' EXIT (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_UPDATE'
# Generated helper functions used by this child shell.
acfs_generated_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..)
            return 1
            ;;
        *[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    for candidate in \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

# Primary-bin helper functions used by this child shell.
acfs_child_log_error() {
    if declare -f log_error >/dev/null 2>&1; then
        log_error "$@"
    else
        echo "[ERROR] $*" >&2
    fi
}

acfs_child_primary_bin_dir() {
    local primary_bin_dir="${ACFS_BIN_DIR:-}"
    local fallback_home="${HOME:-}"

    if [[ -z "$primary_bin_dir" ]]; then
        if [[ -z "$fallback_home" ]] || [[ "$fallback_home" == "/" ]] || [[ "$fallback_home" != /* ]]; then
            acfs_child_log_error "ACFS_BIN_DIR is unset and HOME is not a usable absolute path"
            return 1
        fi
        primary_bin_dir="$fallback_home/.local/bin"
    fi

    if [[ -z "$primary_bin_dir" ]] || [[ "$primary_bin_dir" == "/" ]] || [[ "$primary_bin_dir" != /* ]]; then
        acfs_child_log_error "ACFS_BIN_DIR must be an absolute path and cannot be '/' (got: ${primary_bin_dir:-<empty>})"
        return 1
    fi

    printf '%s\n' "$primary_bin_dir"
}

acfs_child_primary_bin_requires_root() {
    local primary_bin_dir="$1"
    local target_home="${TARGET_HOME:-${HOME:-}}"

    [[ -n "$target_home" && "$target_home" == /* && "$target_home" != "/" ]] || return 0
    case "$primary_bin_dir" in
        "$target_home"|"$target_home"/*) return 1 ;;
        *) return 0 ;;
    esac
}

acfs_child_run_root_bin_command() {
    if [[ -z "${1:-}" || "${1:-}" != /* ]]; then
        acfs_child_log_error "Root primary bin command must be an absolute trusted path (got: ${1:-<empty>})"
        return 1
    fi

    if [[ $EUID -eq 0 ]]; then
        "$@"
        return $?
    fi

    local sudo_bin=""
    sudo_bin="$(acfs_generated_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        "$sudo_bin" -n "$@"
        return $?
    fi

    acfs_child_log_error "Primary bin dir requires root, but sudo is unavailable: ${ACFS_BIN_DIR:-<unset>}"
    return 1
}

acfs_child_primary_bin_tool_path() {
    local name="${1:-}"
    local tool_path=""

    tool_path="$(acfs_generated_system_binary_path "$name" 2>/dev/null || true)"
    if [[ -z "$tool_path" ]]; then
        acfs_child_log_error "Unable to locate trusted $name for primary bin operation"
        return 1
    fi

    printf '%s\n' "$tool_path"
}

acfs_child_ensure_primary_bin_dir() {
    local primary_bin_dir="$1"
    local mkdir_bin=""

    mkdir_bin="$(acfs_child_primary_bin_tool_path mkdir)" || return 1

    if acfs_child_primary_bin_requires_root "$primary_bin_dir"; then
        acfs_child_run_root_bin_command "$mkdir_bin" -p "$primary_bin_dir"
        return $?
    fi

    "$mkdir_bin" -p "$primary_bin_dir"
}

acfs_link_primary_bin_command() {
    local source_path="$1"
    local command_name="$2"
    local primary_bin_dir=""
    local dest_path=""
    local ln_bin=""

    primary_bin_dir="$(acfs_child_primary_bin_dir)" || return 1
    dest_path="$primary_bin_dir/$command_name"
    acfs_child_ensure_primary_bin_dir "$primary_bin_dir" || return 1
    ln_bin="$(acfs_child_primary_bin_tool_path ln)" || return 1

    if acfs_child_primary_bin_requires_root "$primary_bin_dir"; then
        acfs_child_run_root_bin_command "$ln_bin" -sf "$source_path" "$dest_path"
        return $?
    fi

    "$ln_bin" -sf "$source_path" "$dest_path"
}

acfs_install_executable_into_primary_bin() {
    local src_path="$1"
    local command_name="$2"
    local primary_bin_dir=""
    local dest_path=""
    local install_bin=""

    primary_bin_dir="$(acfs_child_primary_bin_dir)" || return 1
    dest_path="$primary_bin_dir/$command_name"
    acfs_child_ensure_primary_bin_dir "$primary_bin_dir" || return 1
    install_bin="$(acfs_child_primary_bin_tool_path install)" || return 1

    if acfs_child_primary_bin_requires_root "$primary_bin_dir"; then
        acfs_child_run_root_bin_command "$install_bin" -m 0755 "$src_path" "$dest_path"
        return $?
    fi

    "$install_bin" -m 0755 "$src_path" "$dest_path"
}

update_tmp="$(mktemp "${TMPDIR:-/tmp}/acfs-update-wrapper.XXXXXX")"
trap 'rm -f "$update_tmp"' EXIT
if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -f "${ACFS_BOOTSTRAP_DIR}/scripts/acfs-update" ]]; then
  cp "${ACFS_BOOTSTRAP_DIR}/scripts/acfs-update" "$update_tmp"
elif [[ -f "scripts/acfs-update" ]]; then
  cp "scripts/acfs-update" "$update_tmp"
else
  ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${ACFS_REF:-main}}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${ACFS_RAW}/scripts/acfs-update" -o "$update_tmp"
fi
acfs_install_executable_into_primary_bin "$update_tmp" "acfs-update"
if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1 && { [[ ! -e /usr/local/bin/acfs-update ]] || [[ -L /usr/local/bin/acfs-update ]]; }; then
  sudo -n ln -sf "$HOME/.acfs/bin/acfs-update" /usr/local/bin/acfs-update
fi
INSTALL_ACFS_UPDATE
        then
            log_error "acfs.update: install command failed: trap 'rm -f \"\$update_tmp\"' EXIT"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: acfs-update --help || command -v acfs-update (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_UPDATE'
acfs-update --help || command -v acfs-update
INSTALL_ACFS_UPDATE
        then
            log_error "acfs.update: verify failed: acfs-update --help || command -v acfs-update"
            return 1
        fi
    fi

    log_success "acfs.update installed"
}

# Nightly auto-update timer (systemd)
install_acfs_nightly() {
    local module_id="acfs.nightly"
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping acfs.nightly (not selected)"
        return 0
    fi
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
        log_info "dry-run: install: if [[ -n \"\${ACFS_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${ACFS_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh\" ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_NIGHTLY'
# Install nightly update wrapper script
if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -f "${ACFS_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh" ]]; then
  cp "${ACFS_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh" ~/.acfs/scripts/nightly-update.sh
elif [[ -f "scripts/lib/nightly_update.sh" ]]; then
  cp "scripts/lib/nightly_update.sh" ~/.acfs/scripts/nightly-update.sh
else
  ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${ACFS_REF:-main}}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${ACFS_RAW}/scripts/lib/nightly_update.sh" -o ~/.acfs/scripts/nightly-update.sh
fi
chmod +x ~/.acfs/scripts/nightly-update.sh
INSTALL_ACFS_NIGHTLY
        then
            log_warn "acfs.nightly: install command failed: if [[ -n \"\${ACFS_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${ACFS_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh\" ]]; then"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "acfs.nightly" "install command failed: if [[ -n \"\${ACFS_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${ACFS_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh\" ]]; then"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "acfs.nightly"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ -n \"\${ACFS_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${ACFS_BOOTSTRAP_DIR}/scripts/templates/acfs-nightly-update.timer\" ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_NIGHTLY'
# Install systemd timer unit
if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -f "${ACFS_BOOTSTRAP_DIR}/scripts/templates/acfs-nightly-update.timer" ]]; then
  cp "${ACFS_BOOTSTRAP_DIR}/scripts/templates/acfs-nightly-update.timer" ~/.config/systemd/user/acfs-nightly-update.timer
elif [[ -f "scripts/templates/acfs-nightly-update.timer" ]]; then
  cp "scripts/templates/acfs-nightly-update.timer" ~/.config/systemd/user/acfs-nightly-update.timer
else
  ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${ACFS_REF:-main}}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${ACFS_RAW}/scripts/templates/acfs-nightly-update.timer" -o ~/.config/systemd/user/acfs-nightly-update.timer
fi
INSTALL_ACFS_NIGHTLY
        then
            log_warn "acfs.nightly: install command failed: if [[ -n \"\${ACFS_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${ACFS_BOOTSTRAP_DIR}/scripts/templates/acfs-nightly-update.timer\" ]]; then"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "acfs.nightly" "install command failed: if [[ -n \"\${ACFS_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${ACFS_BOOTSTRAP_DIR}/scripts/templates/acfs-nightly-update.timer\" ]]; then"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "acfs.nightly"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ -n \"\${ACFS_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${ACFS_BOOTSTRAP_DIR}/scripts/templates/acfs-nightly-update.service\" ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_NIGHTLY'
# Install systemd service unit
if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -f "${ACFS_BOOTSTRAP_DIR}/scripts/templates/acfs-nightly-update.service" ]]; then
  cp "${ACFS_BOOTSTRAP_DIR}/scripts/templates/acfs-nightly-update.service" ~/.config/systemd/user/acfs-nightly-update.service
elif [[ -f "scripts/templates/acfs-nightly-update.service" ]]; then
  cp "scripts/templates/acfs-nightly-update.service" ~/.config/systemd/user/acfs-nightly-update.service
else
  ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${ACFS_REF:-main}}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${ACFS_RAW}/scripts/templates/acfs-nightly-update.service" -o ~/.config/systemd/user/acfs-nightly-update.service
fi
INSTALL_ACFS_NIGHTLY
        then
            log_warn "acfs.nightly: install command failed: if [[ -n \"\${ACFS_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${ACFS_BOOTSTRAP_DIR}/scripts/templates/acfs-nightly-update.service\" ]]; then"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "acfs.nightly" "install command failed: if [[ -n \"\${ACFS_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${ACFS_BOOTSTRAP_DIR}/scripts/templates/acfs-nightly-update.service\" ]]; then"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "acfs.nightly"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: systemctl --user daemon-reload (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_NIGHTLY'
# Reload systemd and enable the timer
systemctl --user daemon-reload
systemctl --user enable --now acfs-nightly-update.timer
INSTALL_ACFS_NIGHTLY
        then
            log_warn "acfs.nightly: install command failed: systemctl --user daemon-reload"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "acfs.nightly" "install command failed: systemctl --user daemon-reload"
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
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping acfs.doctor (not selected)"
        return 0
    fi
    log_step "Installing acfs.doctor"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: trap 'rm -f \"\$doctor_tmp\"' EXIT (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_ACFS_DOCTOR'
# Generated helper functions used by this child shell.
acfs_generated_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..)
            return 1
            ;;
        *[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    for candidate in \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

# Primary-bin helper functions used by this child shell.
acfs_child_log_error() {
    if declare -f log_error >/dev/null 2>&1; then
        log_error "$@"
    else
        echo "[ERROR] $*" >&2
    fi
}

acfs_child_primary_bin_dir() {
    local primary_bin_dir="${ACFS_BIN_DIR:-}"
    local fallback_home="${HOME:-}"

    if [[ -z "$primary_bin_dir" ]]; then
        if [[ -z "$fallback_home" ]] || [[ "$fallback_home" == "/" ]] || [[ "$fallback_home" != /* ]]; then
            acfs_child_log_error "ACFS_BIN_DIR is unset and HOME is not a usable absolute path"
            return 1
        fi
        primary_bin_dir="$fallback_home/.local/bin"
    fi

    if [[ -z "$primary_bin_dir" ]] || [[ "$primary_bin_dir" == "/" ]] || [[ "$primary_bin_dir" != /* ]]; then
        acfs_child_log_error "ACFS_BIN_DIR must be an absolute path and cannot be '/' (got: ${primary_bin_dir:-<empty>})"
        return 1
    fi

    printf '%s\n' "$primary_bin_dir"
}

acfs_child_primary_bin_requires_root() {
    local primary_bin_dir="$1"
    local target_home="${TARGET_HOME:-${HOME:-}}"

    [[ -n "$target_home" && "$target_home" == /* && "$target_home" != "/" ]] || return 0
    case "$primary_bin_dir" in
        "$target_home"|"$target_home"/*) return 1 ;;
        *) return 0 ;;
    esac
}

acfs_child_run_root_bin_command() {
    if [[ -z "${1:-}" || "${1:-}" != /* ]]; then
        acfs_child_log_error "Root primary bin command must be an absolute trusted path (got: ${1:-<empty>})"
        return 1
    fi

    if [[ $EUID -eq 0 ]]; then
        "$@"
        return $?
    fi

    local sudo_bin=""
    sudo_bin="$(acfs_generated_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        "$sudo_bin" -n "$@"
        return $?
    fi

    acfs_child_log_error "Primary bin dir requires root, but sudo is unavailable: ${ACFS_BIN_DIR:-<unset>}"
    return 1
}

acfs_child_primary_bin_tool_path() {
    local name="${1:-}"
    local tool_path=""

    tool_path="$(acfs_generated_system_binary_path "$name" 2>/dev/null || true)"
    if [[ -z "$tool_path" ]]; then
        acfs_child_log_error "Unable to locate trusted $name for primary bin operation"
        return 1
    fi

    printf '%s\n' "$tool_path"
}

acfs_child_ensure_primary_bin_dir() {
    local primary_bin_dir="$1"
    local mkdir_bin=""

    mkdir_bin="$(acfs_child_primary_bin_tool_path mkdir)" || return 1

    if acfs_child_primary_bin_requires_root "$primary_bin_dir"; then
        acfs_child_run_root_bin_command "$mkdir_bin" -p "$primary_bin_dir"
        return $?
    fi

    "$mkdir_bin" -p "$primary_bin_dir"
}

acfs_link_primary_bin_command() {
    local source_path="$1"
    local command_name="$2"
    local primary_bin_dir=""
    local dest_path=""
    local ln_bin=""

    primary_bin_dir="$(acfs_child_primary_bin_dir)" || return 1
    dest_path="$primary_bin_dir/$command_name"
    acfs_child_ensure_primary_bin_dir "$primary_bin_dir" || return 1
    ln_bin="$(acfs_child_primary_bin_tool_path ln)" || return 1

    if acfs_child_primary_bin_requires_root "$primary_bin_dir"; then
        acfs_child_run_root_bin_command "$ln_bin" -sf "$source_path" "$dest_path"
        return $?
    fi

    "$ln_bin" -sf "$source_path" "$dest_path"
}

acfs_install_executable_into_primary_bin() {
    local src_path="$1"
    local command_name="$2"
    local primary_bin_dir=""
    local dest_path=""
    local install_bin=""

    primary_bin_dir="$(acfs_child_primary_bin_dir)" || return 1
    dest_path="$primary_bin_dir/$command_name"
    acfs_child_ensure_primary_bin_dir "$primary_bin_dir" || return 1
    install_bin="$(acfs_child_primary_bin_tool_path install)" || return 1

    if acfs_child_primary_bin_requires_root "$primary_bin_dir"; then
        acfs_child_run_root_bin_command "$install_bin" -m 0755 "$src_path" "$dest_path"
        return $?
    fi

    "$install_bin" -m 0755 "$src_path" "$dest_path"
}

doctor_tmp="$(mktemp "${TMPDIR:-/tmp}/acfs-doctor.XXXXXX")"
trap 'rm -f "$doctor_tmp"' EXIT
# Install acfs CLI (doctor.sh entrypoint)
if [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && [[ -f "${ACFS_BOOTSTRAP_DIR}/scripts/lib/doctor.sh" ]]; then
  cp "${ACFS_BOOTSTRAP_DIR}/scripts/lib/doctor.sh" "$doctor_tmp"
elif [[ -f "scripts/lib/doctor.sh" ]]; then
  cp "scripts/lib/doctor.sh" "$doctor_tmp"
else
  ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${ACFS_REF:-main}}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${ACFS_RAW}/scripts/lib/doctor.sh" -o "$doctor_tmp"
fi
acfs_install_executable_into_primary_bin "$doctor_tmp" "acfs"
INSTALL_ACFS_DOCTOR
        then
            log_error "acfs.doctor: install command failed: trap 'rm -f \"\$doctor_tmp\"' EXIT"
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
