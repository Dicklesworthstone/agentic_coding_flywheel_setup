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

# Category: agents
# Modules: 5

# Claude Code
install_agents_claude() {
    local module_id="agents.claude"
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping agents.claude (not selected)"
        return 0
    fi
    log_step "Installing agents.claude"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: agents.claude"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="claude"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "agents.claude: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' 'latest'; then
                            install_success=true
                        else
                            log_error "agents.claude: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "agents.claude: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "agents.claude: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "agents.claude: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "agents.claude: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for agents.claude"
                false
            fi
        }; then
            log_error "agents.claude: verified installer failed"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: for candidate in \"\$HOME/.claude/bin/claude\" \"\$HOME/.claude/local/bin/claude\" \"\$HOME/.bun/bin/claude\"; do (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_CLAUDE'
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

claude_candidate=""
for candidate in "$HOME/.claude/bin/claude" "$HOME/.claude/local/bin/claude" "$HOME/.bun/bin/claude"; do
  if [[ -x "$candidate" ]]; then
    claude_candidate="$candidate"
    break
  fi
done
if [[ -z "$claude_candidate" ]] && [[ -d "$HOME/.claude" ]]; then
  claude_candidate="$(find "$HOME/.claude" -maxdepth 4 -type f -name claude -perm -111 -print -quit 2>/dev/null || true)"
fi
if [[ -z "$claude_candidate" ]] || [[ ! -x "$claude_candidate" ]]; then
  echo "Claude Code: installed but no runnable claude binary found" >&2
  exit 1
fi
acfs_link_primary_bin_command "$claude_candidate" "claude"
INSTALL_AGENTS_CLAUDE
        then
            log_error "agents.claude: install command failed: for candidate in \"\$HOME/.claude/bin/claude\" \"\$HOME/.claude/local/bin/claude\" \"\$HOME/.bun/bin/claude\"; do"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: \"\$target_bin/claude\" --version || \"\$target_bin/claude\" --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_CLAUDE'
target_bin="${ACFS_BIN_DIR:-$HOME/.local/bin}"
"$target_bin/claude" --version || "$target_bin/claude" --help
INSTALL_AGENTS_CLAUDE
        then
            log_error "agents.claude: verify failed: \"\$target_bin/claude\" --version || \"\$target_bin/claude\" --help"
            return 1
        fi
    fi

    log_success "agents.claude installed"
}

# OpenAI Codex CLI
install_agents_codex() {
    local module_id="agents.codex"
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping agents.codex (not selected)"
        return 0
    fi
    log_step "Installing agents.codex"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if ! ~/.bun/bin/bun install -g --trust @openai/codex@latest; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_CODEX'
if ! ~/.bun/bin/bun install -g --trust @openai/codex@latest; then
  echo "WARN: Codex CLI latest tag install failed; retrying @openai/codex" >&2
  ~/.bun/bin/bun install -g --trust @openai/codex
fi
INSTALL_AGENTS_CODEX
        then
            log_error "agents.codex: install command failed: if ! ~/.bun/bin/bun install -g --trust @openai/codex@latest; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: trap 'rm -f \"\$wrapper_tmp\"' EXIT (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_CODEX'
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

wrapper_tmp="$(mktemp "${TMPDIR:-/tmp}/acfs-codex-wrapper.XXXXXX")"
trap 'rm -f "$wrapper_tmp"' EXIT
cat > "$wrapper_tmp" << 'WRAPPER'
#!/bin/bash
exec "$HOME/.bun/bin/bun" "$HOME/.bun/bin/codex" "$@"
WRAPPER
chmod 0755 "$wrapper_tmp"
acfs_install_executable_into_primary_bin "$wrapper_tmp" "codex"
INSTALL_AGENTS_CODEX
        then
            log_error "agents.codex: install command failed: trap 'rm -f \"\$wrapper_tmp\"' EXIT"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: \"\$target_bin/codex\" --version || \"\$target_bin/codex\" --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_CODEX'
target_bin="${ACFS_BIN_DIR:-$HOME/.local/bin}"
"$target_bin/codex" --version || "$target_bin/codex" --help
INSTALL_AGENTS_CODEX
        then
            log_error "agents.codex: verify failed: \"\$target_bin/codex\" --version || \"\$target_bin/codex\" --help"
            return 1
        fi
    fi

    log_success "agents.codex installed"
}

# Legacy Google Gemini CLI (retired; not installed by default)
install_agents_gemini() {
    local module_id="agents.gemini"
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping agents.gemini (not selected)"
        return 0
    fi
    log_step "Installing agents.gemini"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: ~/.bun/bin/bun install -g --trust @google/gemini-cli@latest (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_GEMINI'
~/.bun/bin/bun install -g --trust @google/gemini-cli@latest
INSTALL_AGENTS_GEMINI
        then
            log_warn "agents.gemini: install command failed: ~/.bun/bin/bun install -g --trust @google/gemini-cli@latest"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "agents.gemini" "install command failed: ~/.bun/bin/bun install -g --trust @google/gemini-cli@latest"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "agents.gemini"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: trap 'rm -f \"\$wrapper_tmp\"' EXIT (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_GEMINI'
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

wrapper_tmp="$(mktemp "${TMPDIR:-/tmp}/acfs-gemini-wrapper.XXXXXX")"
trap 'rm -f "$wrapper_tmp"' EXIT
cat > "$wrapper_tmp" << 'WRAPPER'
#!/bin/bash
exec "$HOME/.bun/bin/bun" "$HOME/.bun/bin/gemini" "$@"
WRAPPER
chmod 0755 "$wrapper_tmp"
acfs_install_executable_into_primary_bin "$wrapper_tmp" "gemini"
INSTALL_AGENTS_GEMINI
        then
            log_warn "agents.gemini: install command failed: trap 'rm -f \"\$wrapper_tmp\"' EXIT"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "agents.gemini" "install command failed: trap 'rm -f \"\$wrapper_tmp\"' EXIT"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "agents.gemini"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ ! -f \"\$security_lib\" ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_GEMINI'
security_lib="${ACFS_LIB_DIR:-$HOME/.acfs/scripts/lib}/security.sh"
if [[ ! -f "$security_lib" ]]; then
  echo "agents.gemini: security library not found at $security_lib; skipping Gemini patch" >&2
  exit 0
fi
if [[ -n "${ACFS_CHECKSUMS_YAML:-}" ]]; then
  export CHECKSUMS_FILE="$ACFS_CHECKSUMS_YAML"
fi
# shellcheck disable=SC1090,SC1091
source "$security_lib"
if ! load_checksums; then
  echo "agents.gemini: checksum metadata unavailable; skipping Gemini patch" >&2
  exit 0
fi
find_nvm_node() {
  local node_path=""
  while IFS= read -r node_path; do
    if [[ -x "$node_path" ]]; then
      printf '%s\n' "$node_path"
      return 0
    fi
  done < <(compgen -G "$HOME/.nvm/versions/node/*/bin/node" | sort -Vr)
  return 1
}
if ! nvm_node="$(find_nvm_node)"; then
  nvm_url="${KNOWN_INSTALLERS[nvm]:-}"
  nvm_sha256="$(get_checksum nvm)"
  if [[ -z "$nvm_url" || -z "$nvm_sha256" ]]; then
    echo "agents.gemini: missing verified installer metadata for nvm; skipping Gemini patch" >&2
    exit 0
  fi
  if ! verify_checksum "$nvm_url" "$nvm_sha256" "nvm" | bash; then
    echo "agents.gemini: nvm installer verification failed; skipping Gemini patch" >&2
    exit 0
  fi
  export NVM_DIR="$HOME/.nvm"
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    echo "agents.gemini: nvm.sh not found at $NVM_DIR/nvm.sh; skipping Gemini patch" >&2
    exit 0
  fi
  . "$NVM_DIR/nvm.sh"
  if ! nvm install node || ! nvm alias default node; then
    echo "agents.gemini: failed to install Node.js via nvm; skipping Gemini patch" >&2
    exit 0
  fi
fi
if ! nvm_node="$(find_nvm_node)"; then
  echo "agents.gemini: nvm Node.js binary not found after install; skipping Gemini patch" >&2
  exit 0
fi
nvm_node_bin="${nvm_node%/node}"
if [[ -z "$nvm_node_bin" ]]; then
  echo "agents.gemini: nvm Node.js bin not found after install; skipping Gemini patch" >&2
  exit 0
fi
export PATH="$nvm_node_bin:$PATH"
patch_url="${KNOWN_INSTALLERS[gemini_patch]:-}"
patch_sha256="$(get_checksum gemini_patch)"
if [[ -z "$patch_url" || -z "$patch_sha256" ]]; then
  echo "agents.gemini: missing verified installer metadata for gemini_patch; skipping Gemini patch" >&2
  exit 0
fi
if ! verify_checksum "$patch_url" "$patch_sha256" "gemini_patch" | bash; then
  echo "agents.gemini: Gemini patch verification failed; skipping patch" >&2
  exit 0
fi
INSTALL_AGENTS_GEMINI
        then
            log_warn "agents.gemini: install command failed: if [[ ! -f \"\$security_lib\" ]]; then"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "agents.gemini" "install command failed: if [[ ! -f \"\$security_lib\" ]]; then"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "agents.gemini"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: \"\$target_bin/gemini\" --version || \"\$target_bin/gemini\" --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_GEMINI'
target_bin="${ACFS_BIN_DIR:-$HOME/.local/bin}"
"$target_bin/gemini" --version || "$target_bin/gemini" --help
INSTALL_AGENTS_GEMINI
        then
            log_warn "agents.gemini: verify failed: \"\$target_bin/gemini\" --version || \"\$target_bin/gemini\" --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "agents.gemini" "verify failed: \"\$target_bin/gemini\" --version || \"\$target_bin/gemini\" --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "agents.gemini"
            fi
            return 0
        fi
    fi

    log_success "agents.gemini installed"
}

# Antigravity CLI (agy) — Google, successor to the retired Gemini CLI
install_agents_antigravity() {
    local module_id="agents.antigravity"
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping agents.antigravity (not selected)"
        return 0
    fi
    log_step "Installing agents.antigravity"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: agents.antigravity"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="antigravity"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "agents.antigravity: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "agents.antigravity: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "agents.antigravity: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "agents.antigravity: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "agents.antigravity: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "agents.antigravity: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for agents.antigravity"
                false
            fi
        }; then
            log_error "agents.antigravity: verified installer failed"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: install agy-locked launchers and prime settings (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_ANTIGRAVITY'
# acfs-summary: install agy-locked launchers and prime settings
target_bin="${ACFS_BIN_DIR:-$HOME/.local/bin}"
source_file=""
for candidate in \
  "${ACFS_LIB_DIR:-$HOME/.acfs/scripts/lib}/agy_locked.py" \
  "$HOME/.acfs/scripts/lib/agy_locked.py"; do
  if [[ -f "$candidate" ]]; then
    source_file="$candidate"
    break
  fi
done

if [[ -z "$source_file" ]]; then
  echo "agents.antigravity: agy locked launcher asset not found" >&2
  exit 1
fi

mkdir -p "$target_bin"
install -m 0755 "$source_file" "$target_bin/agy-locked"
install -m 0755 "$source_file" "$target_bin/gmi"

if "$target_bin/agy-locked" --acfs-prime-settings; then
  echo "agents.antigravity: agy locked settings and dcg hook primed" >&2
else
  echo "agents.antigravity: warning: settings will be primed on first agy launch" >&2
fi
INSTALL_AGENTS_ANTIGRAVITY
        then
            log_error "agents.antigravity: install command failed: install agy-locked launchers and prime settings"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: verify agy-locked launchers and pinned settings (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_ANTIGRAVITY'
# acfs-summary: verify agy-locked launchers and pinned settings
target_bin="${ACFS_BIN_DIR:-$HOME/.local/bin}"
test -x "$target_bin/agy"
test -x "$target_bin/agy-locked"
test -x "$target_bin/gmi"
python3 - <<'PY'
import json
import pathlib
import sys

settings_path = pathlib.Path.home() / ".gemini" / "antigravity-cli" / "settings.json"
hook_path = pathlib.Path.home() / ".gemini" / "config" / "hooks" / "dcg-antigravity-hook.py"
try:
    settings = json.loads(settings_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"invalid or missing Antigravity settings: {settings_path}: {exc}", file=sys.stderr)
    raise SystemExit(1)

expected = {
    "model": "Gemini 3.1 Pro (High)",
    "toolPermission": "always-proceed",
    "artifactReviewPolicy": "always-proceed",
    "enableTelemetry": False,
    "enableTerminalSandbox": False,
    "allowNonWorkspaceAccess": True,
    "notifications": False,
    "showTips": False,
    "showFeedbackSurvey": False,
    "useG1Credits": False,
    "verbosity": "high",
    "runningLightSpeed": "medium",
    "colorScheme": "terminal",
    "editor": "auto",
    "altScreenMode": "never",
}
for key, value in expected.items():
    if settings.get(key) != value:
        print(f"Antigravity setting {key} is {settings.get(key)!r}, expected {value!r}", file=sys.stderr)
        raise SystemExit(1)
if not hook_path.is_file():
    print(f"Antigravity dcg hook is missing: {hook_path}", file=sys.stderr)
    raise SystemExit(1)
PY
INSTALL_AGENTS_ANTIGRAVITY
        then
            log_error "agents.antigravity: verify failed: verify agy-locked launchers and pinned settings"
            return 1
        fi
    fi

    log_success "agents.antigravity installed"
}

# OpenCode (multi-provider agent harness)
install_agents_opencode() {
    local module_id="agents.opencode"
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping agents.opencode (not selected)"
        return 0
    fi
    log_step "Installing agents.opencode"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: agents.opencode"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="opencode"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "agents.opencode: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "agents.opencode: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "agents.opencode: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "agents.opencode: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "agents.opencode: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "agents.opencode: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for agents.opencode"
                false
            fi
        }; then
            log_warn "agents.opencode: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "agents.opencode" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "agents.opencode"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: opencode --version || opencode --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_OPENCODE'
opencode --version || opencode --help
INSTALL_AGENTS_OPENCODE
        then
            log_warn "agents.opencode: verify failed: opencode --version || opencode --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "agents.opencode" "verify failed: opencode --version || opencode --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "agents.opencode"
            fi
            return 0
        fi
    fi

    log_success "agents.opencode installed"
}

# Install all agents modules
install_agents() {
    log_section "Installing agents modules"
    install_agents_claude
    install_agents_codex
    install_agents_gemini
    install_agents_antigravity
    install_agents_opencode
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    install_agents
fi
