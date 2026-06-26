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

# Category: cloud
# Modules: 3

# Cloudflare Wrangler CLI
install_cloud_wrangler() {
    local module_id="cloud.wrangler"
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping cloud.wrangler (not selected)"
        return 0
    fi
    log_step "Installing cloud.wrangler"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ ! -x \"\$HOME/.bun/bin/wrangler\" ]] || command -v node >/dev/null 2>&1; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_CLOUD_WRANGLER'
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

if [[ ! -x "$HOME/.bun/bin/wrangler" ]] || command -v node >/dev/null 2>&1; then
  exit 0
fi
wrapper_tmp="$(mktemp "${TMPDIR:-/tmp}/acfs-wrangler-wrapper.XXXXXX")"
trap 'rm -f "$wrapper_tmp"' EXIT
cat > "$wrapper_tmp" << 'WRANGLER_SHIM'
#!/usr/bin/env bash
exec "$HOME/.bun/bin/bun" x wrangler@latest "$@"
WRANGLER_SHIM
chmod 0755 "$wrapper_tmp"
acfs_install_executable_into_primary_bin "$wrapper_tmp" "wrangler"
INSTALL_CLOUD_WRANGLER
        then
            log_warn "cloud.wrangler: install command failed: if [[ ! -x \"\$HOME/.bun/bin/wrangler\" ]] || command -v node >/dev/null 2>&1; then"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "cloud.wrangler" "install command failed: if [[ ! -x \"\$HOME/.bun/bin/wrangler\" ]] || command -v node >/dev/null 2>&1; then"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "cloud.wrangler"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping cloud.supabase (not selected)"
        return 0
    fi
    log_step "Installing cloud.supabase"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: case \"\$(uname -m)\" in (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_CLOUD_SUPABASE'
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

# Install Supabase CLI from GitHub release (verified via sha256 checksums)
arch=""
case "$(uname -m)" in
  x86_64) arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  *)
    echo "Supabase CLI: unsupported architecture ($(uname -m))" >&2
    exit 1
    ;;
esac

CURL_ARGS=(-fsSL)
if command -v curl >/dev/null 2>&1 && curl --help all 2>/dev/null | grep -q -- '--proto'; then
  CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
fi

release_url="$(curl "${CURL_ARGS[@]}" -o /dev/null -w '%{url_effective}\n' "https://github.com/supabase/cli/releases/latest" 2>/dev/null | tail -n1)" || true
tag="${release_url##*/}"
if [[ -z "$tag" ]] || [[ "$tag" != v* ]]; then
  echo "Supabase CLI: failed to resolve latest release tag" >&2
  exit 1
fi

version="${tag#v}"
base_url="https://github.com/supabase/cli/releases/download/${tag}"
tarball="supabase_linux_${arch}.tar.gz"
# Supabase CLI v2.99.0 (2026-05-18) renamed the per-version asset to plain
# `checksums.txt`. Older releases still ship `supabase_${version}_checksums.txt`.
# Try the new name first, then fall back to the legacy one so both work. (#282)
checksums_new="checksums.txt"
checksums_legacy="supabase_${version}_checksums.txt"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/acfs-supabase.XXXXXX")"
tmp_tgz="$(mktemp "${TMPDIR:-/tmp}/acfs-supabase.tgz.XXXXXX")"
tmp_checksums="$(mktemp "${TMPDIR:-/tmp}/acfs-supabase.sha.XXXXXX")"

trap "rm -rf '$tmp_dir' '$tmp_tgz' '$tmp_checksums'" EXIT

if [[ -z "$tmp_dir" ]] || [[ -z "$tmp_tgz" ]] || [[ -z "$tmp_checksums" ]]; then
  echo "Supabase CLI: failed to create temp files" >&2
  exit 1
fi

curl "${CURL_ARGS[@]}" -o "$tmp_tgz" "${base_url}/${tarball}"
if ! curl "${CURL_ARGS[@]}" -o "$tmp_checksums" "${base_url}/${checksums_new}" 2>/dev/null \
   && ! curl "${CURL_ARGS[@]}" -o "$tmp_checksums" "${base_url}/${checksums_legacy}" 2>/dev/null; then
  echo "Supabase CLI: failed to download checksums (tried ${checksums_new} and ${checksums_legacy})" >&2
  exit 1
fi

expected_sha="$(awk -v tb="$tarball" '$2 == tb {print $1; exit}' "$tmp_checksums" 2>/dev/null)"
if [[ -z "$expected_sha" ]]; then
  echo "Supabase CLI: checksum entry not found for ${tarball}" >&2
  exit 1
fi

actual_sha=""
if command -v sha256sum >/dev/null 2>&1; then
  actual_sha="$(sha256sum "$tmp_tgz" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  actual_sha="$(shasum -a 256 "$tmp_tgz" | awk '{print $1}')"
else
  echo "Supabase CLI: no SHA256 tool available (need sha256sum or shasum)" >&2
  exit 1
fi

if [[ -z "$actual_sha" ]] || [[ "$actual_sha" != "$expected_sha" ]]; then
  echo "Supabase CLI: checksum mismatch" >&2
  echo "  Expected: $expected_sha" >&2
  echo "  Actual:   ${actual_sha:-<missing>}" >&2
  exit 1
fi

if ! tar -xzf "$tmp_tgz" -C "$tmp_dir" --no-same-owner --no-same-permissions supabase 2>/dev/null; then
  tar -xzf "$tmp_tgz" -C "$tmp_dir" --no-same-owner --no-same-permissions 2>/dev/null || {
    echo "Supabase CLI: failed to extract tarball" >&2
    exit 1
  }
fi

extracted_bin="$tmp_dir/supabase"
if [[ ! -f "$extracted_bin" ]]; then
  extracted_bin="$(find "$tmp_dir" -maxdepth 2 -type f -name supabase -print -quit 2>/dev/null || true)"
fi
if [[ -z "$extracted_bin" ]] || [[ ! -f "$extracted_bin" ]]; then
  echo "Supabase CLI: binary not found after extract" >&2
  exit 1
fi

target_bin="${ACFS_BIN_DIR:-$HOME/.local/bin}"
acfs_install_executable_into_primary_bin "$extracted_bin" "supabase"

if command -v timeout >/dev/null 2>&1; then
  timeout 5 "$target_bin/supabase" --version >/dev/null 2>&1 || {
    echo "Supabase CLI: installed but failed to run" >&2
    exit 1
  }
else
  "$target_bin/supabase" --version >/dev/null 2>&1 || {
    echo "Supabase CLI: installed but failed to run" >&2
    exit 1
  }
fi

# Best-effort cleanup
rm -f "$tmp_tgz" "$tmp_checksums" "$extracted_bin" 2>/dev/null || true
rmdir "$tmp_dir" 2>/dev/null || true
INSTALL_CLOUD_SUPABASE
        then
            log_warn "cloud.supabase: install command failed: case \"\$(uname -m)\" in"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "cloud.supabase" "install command failed: case \"\$(uname -m)\" in"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "cloud.supabase"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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

# Vercel CLI
install_cloud_vercel() {
    local module_id="cloud.vercel"
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping cloud.vercel (not selected)"
        return 0
    fi
    log_step "Installing cloud.vercel"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
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
    install_cloud_vercel
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    install_cloud
fi
