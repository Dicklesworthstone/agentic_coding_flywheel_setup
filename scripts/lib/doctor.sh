#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Doctor - System Health Check
# Validates that ACFS installation is complete and working
#
# Uses gum for enhanced terminal UI when available
# ============================================================

ACFS_VERSION="${ACFS_VERSION:-0.1.0}"

_acfs_doctor_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

_acfs_doctor_existing_abs_nonroot_dir() {
    local path_value=""

    path_value="$(_acfs_doctor_sanitize_abs_nonroot_path "${1:-}" 2>/dev/null || true)"
    [[ -n "$path_value" ]] || return 1
    [[ -d "$path_value" ]] || return 1
    printf '%s\n' "$path_value"
}

_acfs_doctor_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1

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

_acfs_doctor_read_json_string_key() {
    local json_file="${1:-}"
    local key="${2:-}"
    local value=""
    local jq_bin=""
    local sed_bin=""

    [[ -f "$json_file" ]] || return 1
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1

    jq_bin="$(_acfs_doctor_system_binary_path jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        value="$("$jq_bin" -r --arg key "$key" 'select(.[$key] | type == "string") | .[$key]' "$json_file" 2>/dev/null || true)"
    fi

    if [[ -z "$value" ]]; then
        sed_bin="$(_acfs_doctor_system_binary_path sed 2>/dev/null || true)"
        if [[ -n "$sed_bin" ]]; then
            value="$("$sed_bin" -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$json_file" 2>/dev/null | head -n 1)"
        fi
    fi

    [[ -n "$value" ]] && [[ "$value" != "null" ]] || return 1
    printf '%s\n' "$value"
}

_acfs_doctor_normalize_mode() {
    local mode="${1:-}"

    case "$mode" in
        vibe|safe)
            printf '%s\n' "$mode"
            ;;
        *)
            return 1
            ;;
    esac
}

_acfs_doctor_normalize_ref() {
    local ref="${1:-}"

    [[ -n "$ref" ]] || return 1
    [[ "$ref" =~ ^[A-Za-z0-9._/-]+$ ]] || return 1
    [[ "$ref" != /* ]] || return 1
    [[ "$ref" != */ ]] || return 1
    [[ "$ref" != *..* ]] || return 1
    [[ "$ref" != *@\{* ]] || return 1
    printf '%s\n' "$ref"
}

_acfs_doctor_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(_acfs_doctor_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(_acfs_doctor_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

_acfs_doctor_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(_acfs_doctor_system_binary_path getent 2>/dev/null || true)"
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

_acfs_doctor_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    passwd_home="$(_acfs_doctor_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
    [[ -n "$passwd_home" ]] || return 1
    printf '%s\n' "$passwd_home"
}

_acfs_doctor_resolve_current_home() {
    local current_user=""
    local home_candidate=""
    local passwd_entry=""
    local passwd_home=""

    home_candidate="$(_acfs_doctor_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
    current_user="$(_acfs_doctor_resolve_current_user 2>/dev/null || true)"
    if [[ "$current_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    if [[ -n "$current_user" ]]; then
        passwd_entry="$(_acfs_doctor_getent_passwd_entry "$current_user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            passwd_home="$(_acfs_doctor_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
            if [[ -n "$passwd_home" ]]; then
                printf '%s\n' "$passwd_home"
                return 0
            fi
        fi
    fi

    [[ -n "$home_candidate" ]] || return 1
    printf '%s\n' "$home_candidate"
}

_acfs_doctor_current_home="$(_acfs_doctor_resolve_current_home 2>/dev/null || true)"
_acfs_doctor_original_home="$(_acfs_doctor_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
if [[ -n "$_acfs_doctor_original_home" ]]; then
    HOME="$_acfs_doctor_original_home"
    export HOME
elif [[ -n "$_acfs_doctor_current_home" ]]; then
    HOME="$_acfs_doctor_current_home"
    export HOME
fi
_ACFS_DOCTOR_ENV_TARGET_USER="${TARGET_USER:-}"
_ACFS_DOCTOR_ENV_TARGET_USER_WAS_SET=false
if [[ -n "$_ACFS_DOCTOR_ENV_TARGET_USER" ]]; then
    _ACFS_DOCTOR_ENV_TARGET_USER_WAS_SET=true
fi
_ACFS_DOCTOR_ENV_TARGET_HOME="$(_acfs_doctor_sanitize_abs_nonroot_path "${TARGET_HOME:-}" 2>/dev/null || true)"
TARGET_HOME="$_ACFS_DOCTOR_ENV_TARGET_HOME"
ACFS_HOME="$(_acfs_doctor_sanitize_abs_nonroot_path "${ACFS_HOME:-}" 2>/dev/null || true)"
ACFS_STATE_FILE="$(_acfs_doctor_sanitize_abs_nonroot_path "${ACFS_STATE_FILE:-}" 2>/dev/null || true)"
ACFS_SYSTEM_STATE_FILE="$(_acfs_doctor_sanitize_abs_nonroot_path "${ACFS_SYSTEM_STATE_FILE:-/var/lib/acfs/state.json}" 2>/dev/null || true)"
if [[ -z "$ACFS_SYSTEM_STATE_FILE" ]]; then
    ACFS_SYSTEM_STATE_FILE="/var/lib/acfs/state.json"
fi
_ACFS_DOCTOR_ENV_BIN_DIR="$(_acfs_doctor_sanitize_abs_nonroot_path "${ACFS_BIN_DIR:-}" 2>/dev/null || true)"
ACFS_BIN_DIR=""
export TARGET_HOME ACFS_HOME ACFS_STATE_FILE ACFS_SYSTEM_STATE_FILE ACFS_BIN_DIR

# Ensure the doctor is self-contained and doesn't depend on shell rc files
# for PATH setup (e.g., when run from a fresh SSH session or non-zsh shell).
ensure_path() {
    local dir
    local to_add=()
    local system_path_prefix="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
    local current_path="${PATH:-$system_path_prefix}"
    local seen_path=":$current_path:"
    local primary_home="${TARGET_HOME:-${_acfs_doctor_current_home:-/root}}"
    local primary_bin_dir="${ACFS_BIN_DIR:-$primary_home/.local/bin}"

    primary_bin_dir="$(_acfs_doctor_validate_bin_dir_for_home "$primary_bin_dir" "$primary_home" 2>/dev/null || true)"
    [[ -n "$primary_bin_dir" ]] || primary_bin_dir="$primary_home/.local/bin"

    # Priority order for ACFS tools
    local candidate_dirs=(
        "$primary_bin_dir"
        "$primary_home/.local/bin"
        "$primary_home/.acfs/bin"
        "$primary_home/.bun/bin"
        "$primary_home/.cargo/bin"
        "$primary_home/.atuin/bin"
        "$primary_home/go/bin"
        "$primary_home/google-cloud-sdk/bin"
        "/usr/local/sbin"
        "/usr/local/bin"
        "/usr/sbin"
        "/usr/bin"
        "/sbin"
        "/bin"
        "/snap/bin"
    )

    if [[ -n "${ACFS_HOME:-}" ]]; then
        candidate_dirs=("$ACFS_HOME/bin" "${candidate_dirs[@]}")
    fi

    if [[ -n "${_acfs_doctor_current_home:-}" ]] && [[ "$primary_home" != "$_acfs_doctor_current_home" ]]; then
        candidate_dirs+=(
            "$_acfs_doctor_current_home/.local/bin"
            "$_acfs_doctor_current_home/.acfs/bin"
            "$_acfs_doctor_current_home/.bun/bin"
            "$_acfs_doctor_current_home/.cargo/bin"
            "$_acfs_doctor_current_home/.atuin/bin"
            "$_acfs_doctor_current_home/go/bin"
            "$_acfs_doctor_current_home/google-cloud-sdk/bin"
        )
    fi

    for dir in "${candidate_dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        # Robust PATH check using exact matching to avoid partial substring hits.
        # Track pending additions too so duplicate candidate entries do not get
        # prepended twice when ACFS_BIN_DIR resolves to ~/.local/bin.
        if [[ "$seen_path" != *":$dir:"* ]]; then
            to_add+=("$dir")
            seen_path="${seen_path}${dir}:"
        fi
    done

    if [[ ${#to_add[@]} -gt 0 ]]; then
        local prefix
        prefix=$(IFS=:; echo "${to_add[*]}")
        export PATH="$prefix${current_path:+:$current_path}"
    fi
}
HAS_GUM=false

# Source gum_ui library if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_acfs_doctor_script_acfs_home=""
case "$SCRIPT_DIR" in
    */.acfs/bin)
        _acfs_doctor_script_acfs_home="${SCRIPT_DIR%/bin}"
        ;;
    */.acfs/scripts/lib)
        _acfs_doctor_script_acfs_home="${SCRIPT_DIR%/scripts/lib}"
        ;;
esac
_acfs_doctor_script_acfs_home="$(_acfs_doctor_sanitize_abs_nonroot_path "${_acfs_doctor_script_acfs_home:-}" 2>/dev/null || true)"

_acfs_doctor_acfs_home_for_home() {
    local base_home="${1:-}"

    base_home="$(_acfs_doctor_sanitize_abs_nonroot_path "$base_home" 2>/dev/null || true)"
    [[ -n "$base_home" ]] || return 1
    printf '%s\n' "$base_home/.acfs"
}

_acfs_doctor_acfs_home_matches_home() {
    local acfs_home="${1:-}"
    local base_home="${2:-}"
    local expected_acfs_home=""

    acfs_home="$(_acfs_doctor_sanitize_abs_nonroot_path "$acfs_home" 2>/dev/null || true)"
    [[ -n "$acfs_home" ]] || return 1
    expected_acfs_home="$(_acfs_doctor_acfs_home_for_home "$base_home" 2>/dev/null || true)"
    [[ -n "$expected_acfs_home" ]] || return 1
    [[ "$acfs_home" == "$expected_acfs_home" ]]
}

_acfs_doctor_trusted_lookup_acfs_home() {
    local acfs_home="${ACFS_HOME:-}"

    acfs_home="$(_acfs_doctor_sanitize_abs_nonroot_path "$acfs_home" 2>/dev/null || true)"
    [[ -n "$acfs_home" ]] || return 1

    if [[ -n "${_acfs_doctor_script_acfs_home:-}" ]]; then
        [[ "$acfs_home" == "$_acfs_doctor_script_acfs_home" ]] || return 1
        printf '%s\n' "$acfs_home"
        return 0
    fi

    if _acfs_doctor_acfs_home_matches_home "$acfs_home" "${_ACFS_DOCTOR_ENV_TARGET_HOME:-}" 2>/dev/null; then
        printf '%s\n' "$acfs_home"
        return 0
    fi

    if _acfs_doctor_acfs_home_matches_home "$acfs_home" "${_acfs_doctor_current_home:-}" 2>/dev/null; then
        printf '%s\n' "$acfs_home"
        return 0
    fi

    return 1
}

_acfs_doctor_trusted_runtime_acfs_home() {
    local acfs_home="${ACFS_HOME:-}"

    acfs_home="$(_acfs_doctor_sanitize_abs_nonroot_path "$acfs_home" 2>/dev/null || true)"
    [[ -n "$acfs_home" ]] || return 1

    if [[ -n "${_acfs_doctor_script_acfs_home:-}" ]]; then
        [[ "$acfs_home" == "$_acfs_doctor_script_acfs_home" ]] || return 1
        printf '%s\n' "$acfs_home"
        return 0
    fi

    if _acfs_doctor_acfs_home_matches_home "$acfs_home" "${TARGET_HOME:-}" 2>/dev/null; then
        printf '%s\n' "$acfs_home"
        return 0
    fi

    return 1
}

_acfs_doctor_find_project_path() {
    local rel_path="$1"
    local candidate=""
    local trusted_acfs_home=""

    trusted_acfs_home="$(_acfs_doctor_trusted_lookup_acfs_home 2>/dev/null || true)"

    for candidate in \
        "$SCRIPT_DIR/../$rel_path" \
        "$SCRIPT_DIR/../../$rel_path" \
        "${trusted_acfs_home:+$trusted_acfs_home/$rel_path}" \
        "${_acfs_doctor_current_home:+$_acfs_doctor_current_home/.acfs/$rel_path}"; do
        if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

_acfs_doctor_find_lib_script() {
    _acfs_doctor_find_project_path "scripts/lib/$1"
}

_acfs_doctor_find_scripts_script() {
    _acfs_doctor_find_project_path "scripts/$1"
}

_acfs_doctor_shell_has_active_assignment() {
    local file="${1:-}"
    local variable_name="${2:-}"
    [[ -n "$file" && -n "$variable_name" && -f "$file" ]] || return 1

    awk -v variable_name="$variable_name" '
        /^[[:space:]]*#/ { next }
        {
            line=$0
            sub(/^[[:space:]]*export[[:space:]]+/, "", line)
            if (line ~ "^[[:space:]]*" variable_name "[[:space:]]*=") {
                sub("^[[:space:]]*" variable_name "[[:space:]]*=", "", line)
                sub(/[[:space:]]+#.*$/, "", line)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
                empty_single_quotes=sprintf("%c%c", 39, 39)
                if (line != "" && line != "\"\"" && line != empty_single_quotes) {
                    found=1
                    exit
                }
            }
        }
        END { exit(found ? 0 : 1) }
    ' "$file" 2>/dev/null
}

_acfs_doctor_claude_settings_has_command_hook() {
    local settings_file="${1:-}"
    local command_pattern="${2:-}"

    [[ -n "$settings_file" && -n "$command_pattern" ]] || return 1
    [[ -f "$settings_file" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    jq -e --arg pattern "$command_pattern" '
      def command_hook_matches:
        type == "object"
        and ((.type? // "command") == "command")
        and ((.command? // "") | strings | test($pattern));
      def event_entry_matches:
        if type == "object" and (.hooks? | type) == "array" then
          any(.hooks[]?; command_hook_matches)
        else
          command_hook_matches
        end;
      def hook_event_entries:
        if (.hooks? | type) == "object" then
          .hooks | to_entries[]? | .value | arrays | .[]?
        elif (.hooks? | type) == "array" then
          .hooks[]?
        else
          empty
        end;
      any(hook_event_entries; event_entry_matches)
    ' "$settings_file" >/dev/null 2>&1
}

_acfs_doctor_source_first() {
    local rel_path="$1"
    local candidate=""
    candidate="$(_acfs_doctor_find_lib_script "$rel_path" 2>/dev/null || true)"
    [[ -n "$candidate" ]] || return 1

    # shellcheck source=/dev/null
    source "$candidate"
    return 0
}

# Source output formatting library (for TOON support)
_acfs_doctor_source_first "output.sh" || true

if ! type -t log_error >/dev/null 2>&1; then
    log_step() { echo "[*] $*" >&2; }
    log_section() { echo "" >&2; echo "=== $* ===" >&2; }
    log_success() { echo "[OK] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_info() { echo "    $*" >&2; }
fi

_acfs_doctor_validate_bin_dir_for_home() {
    local bin_dir="${1:-}"
    local base_home="${2:-}"
    local passwd_line=""
    local passwd_home=""
    local hinted_home=""

    bin_dir="$(_acfs_doctor_sanitize_abs_nonroot_path "$bin_dir" 2>/dev/null || true)"
    [[ -n "$bin_dir" ]] || return 1
    base_home="$(_acfs_doctor_sanitize_abs_nonroot_path "$base_home" 2>/dev/null || true)"

    if [[ -n "$base_home" ]] && [[ "$bin_dir" == "$base_home" || "$bin_dir" == "$base_home/"* ]]; then
        printf '%s\n' "$bin_dir"
        return 0
    fi

    case "$bin_dir" in
        */.local/bin) hinted_home="${bin_dir%/.local/bin}" ;;
        */.acfs/bin) hinted_home="${bin_dir%/.acfs/bin}" ;;
        */.bun/bin) hinted_home="${bin_dir%/.bun/bin}" ;;
        */.cargo/bin) hinted_home="${bin_dir%/.cargo/bin}" ;;
        */.atuin/bin) hinted_home="${bin_dir%/.atuin/bin}" ;;
        */go/bin) hinted_home="${bin_dir%/go/bin}" ;;
        */google-cloud-sdk/bin) hinted_home="${bin_dir%/google-cloud-sdk/bin}" ;;
    esac
    hinted_home="$(_acfs_doctor_sanitize_abs_nonroot_path "$hinted_home" 2>/dev/null || true)"
    if [[ -n "$hinted_home" ]] && [[ -n "$base_home" ]] && [[ "$hinted_home" != "$base_home" ]]; then
        return 1
    fi

    while IFS= read -r passwd_line; do
        passwd_home="$(_acfs_doctor_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
        [[ -n "$passwd_home" ]] || continue
        [[ -n "$base_home" && "$passwd_home" == "$base_home" ]] && continue
        if [[ "$bin_dir" == "$passwd_home" || "$bin_dir" == "$passwd_home/"* ]]; then
            return 1
        fi
    done < <(_acfs_doctor_getent_passwd_entry 2>/dev/null || true)

    printf '%s\n' "$bin_dir"
}

# Global format options (set by argument parsing)
_DOCTOR_OUTPUT_FORMAT=""
_DOCTOR_SHOW_STATS=false


# Prefer the installed VERSION file when available.
_acfs_doctor_version_file="$(_acfs_doctor_find_project_path "VERSION" 2>/dev/null || true)"
if [[ -n "$_acfs_doctor_version_file" ]]; then
    ACFS_VERSION="$(cat "$_acfs_doctor_version_file" 2>/dev/null || echo "$ACFS_VERSION")"
fi
unset _acfs_doctor_version_file

# Prefer the installed state file for mode (vibe/safe) when available.
ACFS_MODE="$(_acfs_doctor_normalize_mode "${ACFS_MODE:-}" 2>/dev/null || true)"
_acfs_doctor_installed_state="$(_acfs_doctor_find_project_path "state.json" 2>/dev/null || true)"
if [[ -z "${ACFS_MODE:-}" ]] && [[ -f "$_acfs_doctor_installed_state" ]]; then
    ACFS_MODE="$(_acfs_doctor_read_json_string_key "$_acfs_doctor_installed_state" "mode" 2>/dev/null || true)"
    ACFS_MODE="$(_acfs_doctor_normalize_mode "${ACFS_MODE:-}" 2>/dev/null || true)"
fi
ACFS_MODE="${ACFS_MODE:-vibe}"
export ACFS_MODE
unset _acfs_doctor_installed_state

# Prefer authoritative installed/system state before ambient $HOME/.acfs state.
_acfs_doctor_state_files=()
_acfs_doctor_ambient_state_files=()
_acfs_doctor_installed_state="$(_acfs_doctor_find_project_path "state.json" 2>/dev/null || true)"
if [[ -n "$_acfs_doctor_installed_state" ]]; then
    _acfs_doctor_state_files+=("$_acfs_doctor_installed_state")
fi
if [[ -n "${ACFS_SYSTEM_STATE_FILE:-}" ]]; then
    _acfs_doctor_state_files+=("$ACFS_SYSTEM_STATE_FILE")
fi
_acfs_doctor_trusted_acfs_home="$(_acfs_doctor_trusted_lookup_acfs_home 2>/dev/null || true)"
if [[ -n "$_acfs_doctor_trusted_acfs_home" ]]; then
    _acfs_doctor_state_files+=("$_acfs_doctor_trusted_acfs_home/state.json")
fi
if [[ -n "${ACFS_STATE_FILE:-}" ]]; then
    _acfs_doctor_state_files+=("$ACFS_STATE_FILE")
fi
if [[ -n "${_acfs_doctor_current_home:-}" ]]; then
    _acfs_doctor_ambient_state_files+=("$_acfs_doctor_current_home/.acfs/state.json")
fi

TARGET_USER=""
if [[ "$_ACFS_DOCTOR_ENV_TARGET_USER_WAS_SET" == true ]]; then
    TARGET_USER="$_ACFS_DOCTOR_ENV_TARGET_USER"
fi
if [[ -z "${TARGET_USER:-}" ]]; then
    for _acfs_doctor_state_file in "${_acfs_doctor_state_files[@]}"; do
        [[ -f "$_acfs_doctor_state_file" ]] || continue
        if command -v jq &>/dev/null; then
            TARGET_USER="$(jq -r '.target_user // empty' "$_acfs_doctor_state_file" 2>/dev/null || true)"
        fi
        if [[ -z "${TARGET_USER:-}" ]]; then
            TARGET_USER="$(sed -n 's/.*"target_user"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_acfs_doctor_state_file" | head -n 1)"
        fi
        [[ -n "${TARGET_USER:-}" ]] && break
    done
fi
if [[ -z "${TARGET_USER:-}" ]]; then
    for _acfs_doctor_state_file in "${_acfs_doctor_ambient_state_files[@]}"; do
        [[ -f "$_acfs_doctor_state_file" ]] || continue
        if command -v jq &>/dev/null; then
            TARGET_USER="$(jq -r '.target_user // empty' "$_acfs_doctor_state_file" 2>/dev/null || true)"
        fi
        if [[ -z "${TARGET_USER:-}" ]]; then
            TARGET_USER="$(sed -n 's/.*"target_user"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_acfs_doctor_state_file" | head -n 1)"
        fi
        [[ -n "${TARGET_USER:-}" ]] && break
    done
fi
if [[ -z "${TARGET_USER:-}" ]]; then
    _acfs_current_user="$(_acfs_doctor_resolve_current_user 2>/dev/null || true)"
    if [[ -n "$_acfs_current_user" ]] && [[ "$_acfs_current_user" != "root" ]]; then
        TARGET_USER="$_acfs_current_user"
    fi
    unset _acfs_current_user
fi
if [[ -z "${TARGET_USER:-}" ]] && [[ "$_ACFS_DOCTOR_ENV_TARGET_USER_WAS_SET" != true ]]; then
    TARGET_USER="ubuntu"
fi
if [[ ! "$TARGET_USER" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
    if [[ "$_ACFS_DOCTOR_ENV_TARGET_USER_WAS_SET" != true ]]; then
        TARGET_USER="ubuntu"
    fi
fi

TARGET_HOME=""
if [[ "$_ACFS_DOCTOR_ENV_TARGET_USER_WAS_SET" != true ]]; then
    for _acfs_doctor_state_file in "${_acfs_doctor_state_files[@]}"; do
        [[ -f "$_acfs_doctor_state_file" ]] || continue
        if command -v jq &>/dev/null; then
            TARGET_HOME="$(jq -r '.target_home // empty' "$_acfs_doctor_state_file" 2>/dev/null || true)"
        fi
        if [[ -z "${TARGET_HOME:-}" ]]; then
            TARGET_HOME="$(sed -n 's/.*"target_home"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_acfs_doctor_state_file" | head -n 1)"
        fi
        if [[ -n "${TARGET_HOME:-}" ]]; then
            TARGET_HOME="$(_acfs_doctor_existing_abs_nonroot_dir "${TARGET_HOME%/}" 2>/dev/null || true)"
        fi
        [[ -n "${TARGET_HOME:-}" ]] && break
    done
    if [[ -z "${TARGET_HOME:-}" ]]; then
        _acfs_doctor_ambient_target_user=""
        for _acfs_doctor_state_file in "${_acfs_doctor_ambient_state_files[@]}"; do
            [[ -f "$_acfs_doctor_state_file" ]] || continue
            if command -v jq &>/dev/null; then
                _acfs_doctor_ambient_target_user="$(jq -r '.target_user // empty' "$_acfs_doctor_state_file" 2>/dev/null || true)"
            fi
            if [[ -z "${_acfs_doctor_ambient_target_user:-}" ]]; then
                _acfs_doctor_ambient_target_user="$(sed -n 's/.*"target_user"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_acfs_doctor_state_file" | head -n 1)"
            fi
            [[ "${_acfs_doctor_ambient_target_user:-}" == "$TARGET_USER" ]] || continue
            if command -v jq &>/dev/null; then
                TARGET_HOME="$(jq -r '.target_home // empty' "$_acfs_doctor_state_file" 2>/dev/null || true)"
            fi
            if [[ -z "${TARGET_HOME:-}" ]]; then
                TARGET_HOME="$(sed -n 's/.*"target_home"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_acfs_doctor_state_file" | head -n 1)"
            fi
            if [[ -n "${TARGET_HOME:-}" ]]; then
                TARGET_HOME="$(_acfs_doctor_existing_abs_nonroot_dir "${TARGET_HOME%/}" 2>/dev/null || true)"
            fi
            [[ -n "${TARGET_HOME:-}" ]] && break
        done
        unset _acfs_doctor_ambient_target_user
    fi
fi
for _acfs_doctor_state_file in "${_acfs_doctor_state_files[@]}"; do
    [[ -f "$_acfs_doctor_state_file" ]] || continue
    if command -v jq &>/dev/null; then
        ACFS_BIN_DIR="$(jq -r '.bin_dir // empty' "$_acfs_doctor_state_file" 2>/dev/null || true)"
    fi
    if [[ -z "${ACFS_BIN_DIR:-}" ]]; then
        ACFS_BIN_DIR="$(sed -n 's/.*"bin_dir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_acfs_doctor_state_file" | head -n 1)"
    fi
    ACFS_BIN_DIR="$(_acfs_doctor_existing_abs_nonroot_dir "${ACFS_BIN_DIR:-}" 2>/dev/null || true)"
    ACFS_BIN_DIR="$(_acfs_doctor_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "${TARGET_HOME:-}" 2>/dev/null || true)"
    [[ -n "${ACFS_BIN_DIR:-}" ]] && break
done
if [[ -z "${ACFS_BIN_DIR:-}" ]]; then
    _acfs_doctor_ambient_target_user=""
    for _acfs_doctor_state_file in "${_acfs_doctor_ambient_state_files[@]}"; do
        [[ -f "$_acfs_doctor_state_file" ]] || continue
        if command -v jq &>/dev/null; then
            _acfs_doctor_ambient_target_user="$(jq -r '.target_user // empty' "$_acfs_doctor_state_file" 2>/dev/null || true)"
        fi
        if [[ -z "${_acfs_doctor_ambient_target_user:-}" ]]; then
            _acfs_doctor_ambient_target_user="$(sed -n 's/.*"target_user"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_acfs_doctor_state_file" | head -n 1)"
        fi
        [[ "${_acfs_doctor_ambient_target_user:-}" == "$TARGET_USER" ]] || continue
        if command -v jq &>/dev/null; then
            ACFS_BIN_DIR="$(jq -r '.bin_dir // empty' "$_acfs_doctor_state_file" 2>/dev/null || true)"
        fi
        if [[ -z "${ACFS_BIN_DIR:-}" ]]; then
            ACFS_BIN_DIR="$(sed -n 's/.*"bin_dir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_acfs_doctor_state_file" | head -n 1)"
        fi
        ACFS_BIN_DIR="$(_acfs_doctor_existing_abs_nonroot_dir "${ACFS_BIN_DIR:-}" 2>/dev/null || true)"
        ACFS_BIN_DIR="$(_acfs_doctor_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "${TARGET_HOME:-}" 2>/dev/null || true)"
        [[ -n "${ACFS_BIN_DIR:-}" ]] && break
    done
    unset _acfs_doctor_ambient_target_user
fi
if [[ -z "${ACFS_BIN_DIR:-}" ]]; then
    ACFS_BIN_DIR="$(_acfs_doctor_validate_bin_dir_for_home "$_ACFS_DOCTOR_ENV_BIN_DIR" "${TARGET_HOME:-}" 2>/dev/null || true)"
fi

_acfs_doctor_resolved_target_home=""
if [[ "$TARGET_USER" == "root" ]]; then
    _acfs_doctor_resolved_target_home="/root"
else
    _acfs_passwd_entry="$(_acfs_doctor_getent_passwd_entry "$TARGET_USER" 2>/dev/null || true)"
    if [[ -n "$_acfs_passwd_entry" ]]; then
        _acfs_doctor_resolved_target_home="$(_acfs_doctor_passwd_home_from_entry "$_acfs_passwd_entry" 2>/dev/null || true)"
    elif [[ "$TARGET_USER" == "$(_acfs_doctor_resolve_current_user 2>/dev/null || true)" ]] && [[ -n "${_acfs_doctor_current_home:-}" ]]; then
        _acfs_doctor_resolved_target_home="$_acfs_doctor_current_home"
    fi
    unset _acfs_passwd_entry
fi
if [[ -n "$_acfs_doctor_resolved_target_home" ]]; then
    TARGET_HOME="$_acfs_doctor_resolved_target_home"
fi
unset _acfs_doctor_resolved_target_home

if [[ -z "${TARGET_HOME:-}" ]] && [[ -n "${_ACFS_DOCTOR_ENV_TARGET_HOME:-}" ]] && [[ "$_ACFS_DOCTOR_ENV_TARGET_USER_WAS_SET" != true ]]; then
    TARGET_HOME="$_ACFS_DOCTOR_ENV_TARGET_HOME"
fi
if [[ -n "${TARGET_HOME:-}" ]] && { [[ "$TARGET_HOME" != /* ]] || [[ "$TARGET_HOME" == "/" ]]; }; then
    TARGET_HOME=""
fi
if [[ -z "${TARGET_HOME:-}" ]]; then
    if [[ "$TARGET_USER" == "root" ]]; then
        TARGET_HOME="/root"
    elif [[ -n "${_acfs_doctor_current_home:-}" ]] && [[ "$TARGET_USER" == "$(_acfs_doctor_resolve_current_user 2>/dev/null || true)" ]]; then
        TARGET_HOME="$_acfs_doctor_current_home"
    fi
fi

ACFS_BIN_DIR="$(_acfs_doctor_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "${TARGET_HOME:-}" 2>/dev/null || true)"

export TARGET_USER
export TARGET_HOME

if [[ -n "$_acfs_doctor_script_acfs_home" ]]; then
    ACFS_HOME="$_acfs_doctor_script_acfs_home"
else
    _acfs_doctor_trusted_acfs_home="$(_acfs_doctor_trusted_runtime_acfs_home 2>/dev/null || true)"
    if [[ -n "$_acfs_doctor_trusted_acfs_home" ]]; then
        ACFS_HOME="$_acfs_doctor_trusted_acfs_home"
    elif [[ -n "${TARGET_HOME:-}" ]]; then
        ACFS_HOME="$(_acfs_doctor_acfs_home_for_home "$TARGET_HOME" 2>/dev/null || true)"
    else
        ACFS_HOME=""
    fi
fi
export ACFS_HOME

unset _acfs_doctor_trusted_acfs_home
unset _acfs_doctor_script_acfs_home
unset _acfs_doctor_state_files
unset _acfs_doctor_state_file
unset _acfs_doctor_installed_state
unset _ACFS_DOCTOR_ENV_BIN_DIR
unset _ACFS_DOCTOR_ENV_TARGET_HOME
unset _ACFS_DOCTOR_ENV_TARGET_USER
unset _ACFS_DOCTOR_ENV_TARGET_USER_WAS_SET

ensure_path
if command -v gum &>/dev/null; then
    HAS_GUM=true
fi

_acfs_doctor_source_first "gum_ui.sh" || true

# Source doctor_fix after target-home resolution so its autofix state and
# helper lookups cannot be steered by a stale caller ACFS_HOME.
_acfs_doctor_source_first "doctor_fix.sh" || true

# ============================================================
# Fix Suggestion Builder (bd-31ps.5.2)
# ============================================================
# Builds copy-pasteable fix suggestions that respect the current
# install mode (vibe/safe) and pinned ref when known.
# ============================================================

# Build a fix suggestion command for a given module
# Usage: build_fix_suggestion <module_id> [--phase <phase_num>]
# Returns: A copy-pasteable install command
build_fix_suggestion() {
    local module_id="$1"
    shift
    local phase_value=""

    # Parse optional --phase argument
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --phase)
                [[ $# -ge 2 ]] || break
                phase_value="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Base URL
    local base_url="https://agent-flywheel.com/install"

    # Build flags based on current state
    local flags=""
    local -a flag_args=(--yes --force-reinstall)

    # Add mode flag (vibe is default, but explicit is clearer)
    local mode="${ACFS_MODE:-vibe}"
    mode="$(_acfs_doctor_normalize_mode "$mode" 2>/dev/null || true)"
    flag_args+=(--mode "${mode:-vibe}")

    # Add module/phase selector
    if [[ -n "$phase_value" ]]; then
        flag_args+=(--only-phase "$phase_value")
    elif [[ -n "$module_id" ]]; then
        flag_args+=(--only "$module_id")
    fi
    printf -v flags '%q ' "${flag_args[@]}"
    flags="${flags% }"

    # Build the command
    # Check if we have a pinned ref from state.json
    local ref_env=""
    local state_file=""
    state_file="$(_acfs_doctor_find_project_path "state.json" 2>/dev/null || true)"
    if [[ -f "$state_file" ]]; then
        local pinned_ref=""
        local pinned_ref_q=""
        pinned_ref="$(_acfs_doctor_read_json_string_key "$state_file" "pinned_ref" 2>/dev/null || true)"
        pinned_ref="$(_acfs_doctor_normalize_ref "$pinned_ref" 2>/dev/null || true)"
        if [[ -n "$pinned_ref" && "$pinned_ref" != "main" ]]; then
            printf -v pinned_ref_q '%q' "$pinned_ref"
            ref_env="ACFS_REF=$pinned_ref_q "
        fi
    fi

    echo "curl -fsSL $base_url | ${ref_env}bash -s -- $flags"
}

# Shorthand for common fix patterns
fix_for_module() {
    local module_id="$1"
    build_fix_suggestion "$module_id"
}

fix_for_phase() {
    local phase_num="$1"
    build_fix_suggestion "" --phase "$phase_num"
}

agent_mail_doctor_check_json() {
    local description="Agent Mail doctor check"
    local result=""
    local am_bin=""

    am_bin="$(doctor_agent_mail_cli_path 2>/dev/null || true)"
    [[ -n "$am_bin" ]] || return 1

    local exit_status=0
    if [[ $# -gt 0 ]]; then
        result="$(run_with_timeout "$DEEP_CHECK_TIMEOUT" "$description" "$am_bin" doctor check --json "$1")" || exit_status=$?
    else
        result="$(run_with_timeout "$DEEP_CHECK_TIMEOUT" "$description" "$am_bin" doctor check --json)" || exit_status=$?
    fi

    if [[ $exit_status -ne 0 ]] || [[ -z "$result" ]] || [[ "$result" == "TIMEOUT" ]]; then
        return 1
    fi

    printf '%s' "$result"
}

agent_mail_doctor_is_healthy() {
    local doctor_json="${1:-}"

    [[ -n "$doctor_json" ]] || return 1

    if command -v jq &>/dev/null; then
        [[ "$(printf '%s' "$doctor_json" | jq -r '.healthy // false' 2>/dev/null)" == "true" ]]
        return $?
    fi

    printf '%s' "$doctor_json" | grep -q '"healthy"[[:space:]]*:[[:space:]]*true'
}

agent_mail_doctor_summary() {
    local doctor_json="${1:-}"
    local summary=""

    [[ -n "$doctor_json" ]] || return 1

    if command -v jq &>/dev/null; then
        summary="$(printf '%s' "$doctor_json" | jq -r '
            [
                .checks[]?
                | select(.status == "fail")
                | "\(.check): \(.detail)"
            ] | join("; ")
        ' 2>/dev/null || true)"
        if [[ -n "$summary" ]]; then
            printf '%s' "$summary"
            return 0
        fi

        summary="$(printf '%s' "$doctor_json" | jq -r '
            [
                .checks[]?
                | select(.status == "warn")
                | "\(.check): \(.detail)"
            ] | join("; ")
        ' 2>/dev/null || true)"
        if [[ -n "$summary" ]]; then
            printf '%s' "$summary"
            return 0
        fi
    fi

    if printf '%s' "$doctor_json" | grep -q '"healthy"[[:space:]]*:[[:space:]]*false'; then
        printf '%s' "doctor check reported unhealthy state"
        return 0
    fi

    return 1
}

# ============================================================
# Manifest-Derived Checks (bd-31ps.5.1)
# ============================================================
# Source generated doctor_checks.sh to get MANIFEST_CHECKS array.
# This provides comprehensive manifest-driven verification for tools
# not already covered by the bespoke check functions below.
# ============================================================
MANIFEST_CHECKS_LOADED=false

# Source at top level (not inside a function) because doctor_checks.sh uses
# "declare -a MANIFEST_CHECKS=(...)" which bash scopes as local inside a
# function.  Top-level sourcing keeps the array globally visible.
_MANIFEST_CHECKS_FILE=""
_MANIFEST_CHECKS_FILE="$(_acfs_doctor_find_project_path "scripts/generated/doctor_checks.sh" 2>/dev/null || true)"

if [[ -n "$_MANIFEST_CHECKS_FILE" ]]; then
    # Save shell options before sourcing (doctor_checks.sh sets -euo pipefail)
    _MANIFEST_SAVED_OPTS=$(set +o)

    # shellcheck source=/dev/null
    if source "$_MANIFEST_CHECKS_FILE" 2>/dev/null; then
        MANIFEST_CHECKS_LOADED=true
    fi

    # Restore original shell options
    eval "$_MANIFEST_SAVED_OPTS" 2>/dev/null
    unset _MANIFEST_SAVED_OPTS
fi
unset _MANIFEST_CHECKS_FILE

# Colors (fallback if gum_ui not loaded)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Color scheme (Catppuccin Mocha)
ACFS_PRIMARY="${ACFS_PRIMARY:-#89b4fa}"
ACFS_SUCCESS="${ACFS_SUCCESS:-#a6e3a1}"
ACFS_WARNING="${ACFS_WARNING:-#f9e2af}"
ACFS_ERROR="${ACFS_ERROR:-#f38ba8}"
ACFS_MUTED="${ACFS_MUTED:-#6c7086}"
ACFS_ACCENT="${ACFS_ACCENT:-#cba6f7}"
ACFS_TEAL="${ACFS_TEAL:-#94e2d5}"

# Counters
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Skipped tools data (bead qup)
declare -ga SKIPPED_TOOLS_DATA=()

# Output modes
JSON_MODE=false
JSON_CHECKS=()

# Deep mode - run functional tests beyond binary existence
# Related: agentic_coding_flywheel_setup-01s
DEEP_MODE=false

# Fix mode - automatically apply safe fixes
# Related: bd-31ps.6.2
FIX_MODE=false
DRY_RUN_MODE=false

# Caching for deep checks - skip slow operations that recently passed
# Related: agentic_coding_flywheel_setup-lz1
NO_CACHE=false
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/acfs/doctor"
CACHE_TTL=300  # 5 minutes

# Per-check timeout (prevents indefinite hangs)
# Related: agentic_coding_flywheel_setup-lz1
DEEP_CHECK_TIMEOUT=15  # seconds
DOCTOR_VERSION_TIMEOUT="${DOCTOR_VERSION_TIMEOUT:-2}"

# Print `acfs` CLI help (only used when this script is installed as the `acfs` entrypoint).
print_acfs_help() {
    echo "ACFS - Agentic Coding Flywheel Setup"
    echo ""
    echo "Usage: acfs <command> [options]"
    echo ""
    echo "Commands:"
    echo "  doctor [options]    Check system health and tool status"
    echo "    --json            Output results as JSON"
    echo "    --deep            Run functional tests (auth, connections)"
    echo "  info [options]      Quick system overview (terminal/json/html)"
    echo "  status [options]    Quick one-line health summary"
    echo "  cheatsheet          Command reference (aliases, shortcuts)"
    echo "  changelog [options] Show recent project changes"
    echo "  export-config       Export config for backup/migration"
    echo "  continue [options]  View installation/upgrade progress"
    echo "  dashboard <command> Generate/view a static HTML dashboard"
    echo "  newproj <name>      Create new project with git, br, claude settings"
    echo "  update [options]    Update ACFS tools to latest versions"
    echo "  services-setup      Configure AI agents and cloud services"
    echo "  session <command>   Export/import/share agent sessions"
    echo "  support-bundle      Collect diagnostic data for troubleshooting"
    echo "  version             Show ACFS version"
    echo "  help                Show this help message"
}

_acfs_doctor_exec_bash_script() {
    local script_path="${1:-}"
    local bash_bin=""
    shift || true

    bash_bin="$(_acfs_doctor_system_binary_path bash 2>/dev/null || true)"
    if [[ -z "$bash_bin" ]]; then
        echo "Error: bash not found" >&2
        return 1
    fi

    exec "$bash_bin" "$script_path" "$@"
}

resolve_session_lib() {
    local session_script=""
    session_script="$(_acfs_doctor_find_lib_script "session.sh" 2>/dev/null || true)"
    if [[ -n "$session_script" ]]; then
        echo "$session_script"
        return 0
    fi
    return 1
}

print_session_help() {
    echo "Usage: acfs session <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list [--json] [--days N] [--agent NAME] [--limit N]"
    echo "  export <session_path> [--format json|markdown] [--no-sanitize] [--output FILE]"
    echo "  recent [--workspace PATH] [--format json|markdown]"
    echo "  import <file.json> [--dry-run]"
    echo "  convert <native_session_file> --from <claude-code|codex|gemini> --to <claude-code|codex|gemini> [--workspace PATH] [--session-id ID] [--dry-run]"
    echo "  show <id> [--format json|markdown|summary]"
    echo "  list-imported"
    echo ""
    echo "Examples:"
    echo "  acfs session list --days 7"
    echo "  acfs session export ~/.codex/sessions/.../abc.jsonl --output session.json"
    echo "  acfs session convert ~/.codex/sessions/.../abc.jsonl --from codex --to claude-code --workspace /data/projects/foo"
    echo "  acfs session recent --workspace /data/projects/foo"
    echo "  acfs session import session.json --dry-run"
}

acfs_session_recent() {
    local workspace
    workspace="$(pwd)"
    local format="json"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --workspace)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --workspace requires a path" >&2
                    return 1
                fi
                workspace="$2"
                shift 2
                ;;
            --format)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --format requires a value (json or markdown)" >&2
                    return 1
                fi
                format="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    export_recent_session "$workspace" "$format"
}

acfs_session_main() {
    local session_lib
    session_lib="$(resolve_session_lib)" || {
        echo "Error: session.sh not found. Re-run the ACFS installer." >&2
        return 1
    }

    # shellcheck source=/dev/null
    source "$session_lib"

    local subcmd="${1:-}"
    case "$subcmd" in
        help|-h|"")
            print_session_help
            return 0
            ;;
    esac

    if ! check_session_deps; then
        return 1
    fi

    case "$subcmd" in
        list)
            shift
            list_sessions "$@"
            ;;
        export)
            shift
            export_session "$@"
            ;;
        recent)
            shift
            acfs_session_recent "$@"
            ;;
        import)
            shift
            import_session "$@"
            ;;
        convert)
            shift
            convert_session_native "$@"
            ;;
        show)
            shift
            show_session "$@"
            ;;
        list-imported)
            shift
            list_imported_sessions "$@"
            ;;
        *)
            echo "Unknown session command: $subcmd" >&2
            print_session_help
            return 1
            ;;
    esac
}

# Print a section header only in human output mode.
section() {
    if [[ "$JSON_MODE" != "true" ]]; then
        if [[ "$HAS_GUM" == "true" ]]; then
            echo ""
            gum style \
                --foreground "$ACFS_PRIMARY" \
                --bold \
                --border-foreground "$ACFS_MUTED" \
                --border normal \
                --padding "0 2" \
                --margin "0 0 1 0" \
                "󰋊 $1"
        else
            echo ""
            printf "${CYAN}━━━ %s ━━━${NC}\n" "$1"
        fi
    fi
}

# Print a blank line only in human output mode.
blank_line() {
    if [[ "$JSON_MODE" != "true" ]]; then
        echo ""
    fi
}

# Escape a string for safe inclusion in JSON (without surrounding quotes).
json_escape() {
    local s="${1:-}"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

# ============================================================
# Timeout and Caching Helpers (bead lz1)
# ============================================================

# Run a command with timeout, returning special status for timeout
# Usage: run_with_timeout <timeout_seconds> <description> <command> [args...]
# Returns: 0=success, 124=timeout, other=command exit code
# Output: Command stdout (or "TIMEOUT" on timeout)
run_with_timeout() {
    local timeout_secs="$1"
    local description="$2"
    shift 2

    local result
    local status
    result=$(timeout "$timeout_secs" "$@" 2>&1)
    status=$?

    if ((status == 124)); then
        echo "TIMEOUT"
        if [[ "$JSON_MODE" != "true" ]]; then
            # Log timeout warning (non-fatal)
            if [[ "$HAS_GUM" == "true" ]]; then
                gum style --foreground "$ACFS_MUTED" "    ⏱ $description timed out after ${timeout_secs}s" >&2
            else
                echo -e "    ${YELLOW}⏱ $description timed out after ${timeout_secs}s${NC}" >&2
            fi
        fi
        return 124
    fi

    echo "$result"
    return $status
}

# Store a successful check result in cache
# Usage: cache_result <key> <value>
cache_result() {
    local key="$1"
    local value="$2"

    # Skip if caching disabled
    [[ "$NO_CACHE" == "true" ]] && return 0

    mkdir -p "$CACHE_DIR"
    echo "$value" > "$CACHE_DIR/$key"
}

# Get a cached result if it exists and is fresh
# Usage: get_cached_result <key>
# Returns: 0 if cache hit, 1 if miss/expired
# Output: Cached value on hit
get_cached_result() {
    local key="$1"
    local cache_file="$CACHE_DIR/$key"

    # Skip if caching disabled
    [[ "$NO_CACHE" == "true" ]] && return 1

    # Check if cache file exists
    [[ -f "$cache_file" ]] || return 1

    # Check cache age (compatible with both Linux and macOS)
    local file_mtime
    local current_time
    current_time=$(date +%s)

    # Try GNU stat first, fall back to BSD stat
    if file_mtime=$(stat -c %Y "$cache_file" 2>/dev/null); then
        : # GNU stat worked
    elif file_mtime=$(stat -f %m "$cache_file" 2>/dev/null); then
        : # BSD stat worked
    else
        return 1  # Can't determine age, cache miss
    fi

    local age=$((current_time - file_mtime))
    if ((age >= CACHE_TTL)); then
        return 1  # Cache expired
    fi

    cat "$cache_file"
    return 0
}

normalize_config_value() {
    local value="${1-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ ${#value} -ge 2 ]]; then
        local first_char="${value:0:1}"
        local last_char="${value: -1}"
        if [[ ( "$first_char" == '"' && "$last_char" == '"' ) || ( "$first_char" == "'" && "$last_char" == "'" ) ]]; then
            value="${value:1:${#value}-2}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
        fi
    fi

    printf '%s\n' "$value"
}

is_placeholder_secret() {
    local normalized
    normalized="$(normalize_config_value "${1-}")"
    normalized="${normalized,,}"

    case "$normalized" in
        your-token-here|your_token_here|your-token|your_token|your_api_key|your-api-key|your_github_token|your_openai_api_key|your_claude_token|your_vercel_token|your_supabase_access_token|your_cloudflare_api_token|your_gemini_api_key|your-gemini-api-key|your_google_api_key|your_project_id|your_project_location|replace-me|change-me|changeme|"<token>"|"<api-key>"|"<secret>")
            return 0
            ;;
    esac

    return 1
}

has_usable_secret() {
    local normalized
    normalized="$(normalize_config_value "${1-}")"
    [[ -n "${normalized//[[:space:]]/}" ]] && ! is_placeholder_secret "$normalized"
}

json_file_has_usable_jq_value() {
    local file_path="${1:-}"
    local jq_expr="${2:-}"
    local candidate=""

    [[ -s "$file_path" ]] || return 1
    [[ -n "$jq_expr" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    while IFS= read -r candidate; do
        if has_usable_secret "$candidate"; then
            return 0
        fi
    done < <(jq -r "$jq_expr" "$file_path" 2>/dev/null || true)

    return 1
}

json_file_has_usable_string_key() {
    local file_path="${1:-}"
    shift || true

    [[ -s "$file_path" ]] || return 1

    local key=""
    local regex=""
    local line=""
    for key in "$@"; do
        [[ -n "$key" ]] || continue
        regex="\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]+)\""
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ $regex ]] && has_usable_secret "${BASH_REMATCH[1]}"; then
                return 0
            fi
        done < "$file_path"
    done

    return 1
}

strip_shell_inline_comment() {
    local value="${1-}"
    local quote=""
    local char=""
    local prev=""
    local i

    for (( i = 0; i < ${#value}; i++ )); do
        char="${value:i:1}"

        if [[ -n "$quote" ]]; then
            if [[ "$char" == "\\" ]]; then
                (( i += 1 ))
                continue
            fi
            if [[ "$char" == "$quote" ]]; then
                quote=""
            fi
            continue
        fi

        if [[ "$char" == '"' || "$char" == "'" ]]; then
            quote="$char"
            continue
        fi

        if [[ "$char" == "#" ]]; then
            if (( i == 0 )); then
                printf '%s\n' "${value:0:i}"
                return 0
            fi
            prev="${value:i-1:1}"
            case "$prev" in
                [[:space:]])
                    printf '%s\n' "${value:0:i}"
                    return 0
                    ;;
            esac
        fi
    done

    printf '%s\n' "$value"
}

read_configured_var_from_file() {
    local var_name="$1"
    local file_path="$2"
    [[ -f "$file_path" ]] || return 1

    local line=""
    local regex="^[[:space:]]*(export[[:space:]]+)?${var_name}[[:space:]]*=(.*)$"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" =~ $regex ]]; then
            local value="${BASH_REMATCH[2]}"
            value="$(strip_shell_inline_comment "$value")"
            value="$(normalize_config_value "$value")"
            if [[ -n "${value//[[:space:]]/}" ]]; then
                printf '%s\n' "$value"
                return 0
            fi
        fi
    done < "$file_path"

    return 1
}

get_configured_value() {
    local var_name="$1"
    shift

    local env_value="${!var_name-}"
    if [[ -n "${env_value//[[:space:]]/}" ]] && ! is_placeholder_secret "$env_value"; then
        normalize_config_value "$env_value"
        return 0
    fi

    local file_path=""
    local configured_value=""
    for file_path in "$@"; do
        configured_value="$(read_configured_var_from_file "$var_name" "$file_path" || true)"
        if [[ -n "${configured_value//[[:space:]]/}" ]] && ! is_placeholder_secret "$configured_value"; then
            printf '%s\n' "$configured_value"
            return 0
        fi
    done

    return 1
}

get_configured_secret() {
    local var_name="$1"
    shift

    local env_value="${!var_name-}"
    if has_usable_secret "$env_value"; then
        normalize_config_value "$env_value"
        return 0
    fi

    local file_path=""
    local configured_value=""
    for file_path in "$@"; do
        configured_value="$(read_configured_var_from_file "$var_name" "$file_path" || true)"
        if has_usable_secret "$configured_value"; then
            printf '%s\n' "$configured_value"
            return 0
        fi
    done

    return 1
}

configured_truthy_value() {
    local var_name="$1"
    shift

    local configured_value=""
    configured_value="$(get_configured_value "$var_name" "$@" || true)"
    case "${configured_value,,}" in
        1|true|yes|on)
            return 0
            ;;
    esac

    return 1
}

doctor_runtime_home() {
    local resolved_home=""

    resolved_home="$(_acfs_doctor_sanitize_abs_nonroot_path "${TARGET_HOME:-}" 2>/dev/null || true)"
    if [[ -z "$resolved_home" ]]; then
        resolved_home="${_acfs_doctor_current_home:-}"
    fi

    if [[ -n "$resolved_home" ]] && [[ "$resolved_home" == /* ]] && [[ "$resolved_home" != "/" ]]; then
        printf '%s\n' "${resolved_home%/}"
    else
        printf '/root\n'
    fi
}

default_auth_config_files() {
    local auth_home=""
    auth_home="$(doctor_runtime_home)"
    printf '%s\n' \
        "$auth_home/.zshrc.local" \
        "$auth_home/.zshrc" \
        "$auth_home/.bashrc" \
        "$auth_home/.profile"
}

# Run a check with cache support
# Usage: check_with_cache <cache_key> <description> <command> [args...]
# Returns: Command exit status (0 = cache hit counts as success)
check_with_cache() {
    local cache_key="$1"
    local description="$2"
    shift 2

    # Try cache first
    local cached
    if cached=$(get_cached_result "$cache_key"); then
        echo "$cached (cached)"
        return 0
    fi

    # Run actual check with timeout
    local result
    local status
    result=$(run_with_timeout "$DEEP_CHECK_TIMEOUT" "$description" "$@")
    status=$?

    # Cache successful results
    if ((status == 0)); then
        cache_result "$cache_key" "$result"
    fi

    echo "$result"
    return $status
}

# Check with [?] (unknown) indicator for timeouts
# This variant of check() handles timeout status specially
# Usage: check_with_timeout_status <id> <label> <status> [details] [fix]
# status can be: pass, warn, fail, timeout
check_with_timeout_status() {
    local id="$1"
    local label="$2"
    local status="$3"
    local details="${4:-}"
    local fix="${5:-}"

    # Convert timeout to special handling
    if [[ "$status" == "timeout" ]]; then
        # Timeouts count as warnings for stats (unknown state, not failed)
        ((WARN_COUNT += 1))

        if [[ "$JSON_MODE" == "true" ]]; then
            local fix_json="null"
            if [[ -n "$fix" ]]; then
                fix_json="\"$(json_escape "$fix")\""
            fi
            JSON_CHECKS+=("{\"id\":\"$(json_escape "$id")\",\"label\":\"$(json_escape "$label")\",\"status\":\"timeout\",\"details\":\"$(json_escape "$details")\",\"fix\":$fix_json}")
            return 0
        fi

        # Display with [?] indicator
        if [[ "$HAS_GUM" == "true" ]]; then
            echo "  $(gum style --foreground "$ACFS_WARNING" --bold "? WAIT") $(gum style "$label")"
            if [[ -n "$fix" ]]; then
                echo "        $(gum style --foreground "$ACFS_MUTED" "Fix:") $(gum style --foreground "$ACFS_ACCENT" --italic "$fix")"
            fi
        else
            echo -e "  ${YELLOW}? WAIT${NC} $label"
            if [[ -n "$fix" ]]; then
                echo -e "        Fix: $fix"
            fi
        fi
        return 0
    fi

    # Delegate to standard check for other statuses
    check "$id" "$label" "$status" "$details" "$fix"
}

# Check result helper
check() {
    local id="$1"
    local label="$2"
    local status="$3"
    local details="${4:-}"
    local fix="${5:-}"

    case "$status" in
        pass) ((PASS_COUNT += 1)) ;;
        warn) ((WARN_COUNT += 1)) ;;
        fail) ((FAIL_COUNT += 1)) ;;
    esac

    if [[ "$JSON_MODE" == "true" ]]; then
        local fix_json="null"
        if [[ -n "$fix" ]]; then
            fix_json="\"$(json_escape "$fix")\""
        fi

        JSON_CHECKS+=("{\"id\":\"$(json_escape "$id")\",\"label\":\"$(json_escape "$label")\",\"status\":\"$(json_escape "$status")\",\"details\":\"$(json_escape "$details")\",\"fix\":$fix_json}")
        return 0
    fi

    if [[ "$HAS_GUM" == "true" ]]; then
        case "$status" in
            pass)
                echo "  $(gum style --foreground "$ACFS_SUCCESS" --bold "✓ PASS") $(gum style --foreground "$ACFS_TEAL" "$label")"
                ;;
            warn)
                echo "  $(gum style --foreground "$ACFS_WARNING" --bold "⚠ WARN") $(gum style "$label")"
                if [[ -n "$fix" ]]; then
                    echo "        $(gum style --foreground "$ACFS_MUTED" "Fix:") $(gum style --foreground "$ACFS_ACCENT" --italic "$fix")"
                fi
                ;;
            fail)
                echo "  $(gum style --foreground "$ACFS_ERROR" --bold "✖ FAIL") $(gum style "$label")"
                if [[ -n "$fix" ]]; then
                    echo "        $(gum style --foreground "$ACFS_MUTED" "Fix:") $(gum style --foreground "$ACFS_ACCENT" --italic "$fix")"
                fi
                ;;
        esac
    else
        case "$status" in
            pass)
                echo -e "  ${GREEN}✓ PASS${NC} $label"
                ;;
            warn)
                echo -e "  ${YELLOW}⚠ WARN${NC} $label"
                if [[ -n "$fix" ]]; then
                    echo -e "        Fix: $fix"
                fi
                ;;
            fail)
                echo -e "  ${RED}✖ FAIL${NC} $label"
                if [[ -n "$fix" ]]; then
                    echo -e "        Fix: $fix"
                fi
                ;;
        esac
    fi

    # Dispatch fix if --fix mode is enabled
    if [[ "$FIX_MODE" == "true" ]] && [[ "$status" != "pass" ]]; then
        if type -t dispatch_fix &>/dev/null; then
            dispatch_fix "$id" "$status" "$fix"
        fi
    fi
}

doctor_binary_path() {
    local name="${1:-}"
    local runtime_home=""
    local primary_bin_dir=""
    local candidate=""
    local path_dir=""
    local sanitized_dir=""
    local -a candidates=()
    local -a path_entries=()

    [[ -n "$name" ]] || return 1

    runtime_home="$(doctor_runtime_home)"
    [[ -n "$runtime_home" ]] || return 1

    primary_bin_dir="$(_acfs_doctor_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$runtime_home" 2>/dev/null || true)"
    [[ -n "$primary_bin_dir" ]] || primary_bin_dir="$runtime_home/.local/bin"
    if [[ -n "${ACFS_HOME:-}" ]]; then
        candidates+=("$ACFS_HOME/bin/$name")
    fi
    candidates+=(
        "$primary_bin_dir/$name"
        "$runtime_home/.local/bin/$name"
        "$runtime_home/.acfs/bin/$name"
        "$runtime_home/.bun/bin/$name"
        "$runtime_home/.cargo/bin/$name"
        "$runtime_home/.atuin/bin/$name"
        "$runtime_home/go/bin/$name"
        "$runtime_home/google-cloud-sdk/bin/$name"
        "$runtime_home/bin/$name"
        "/usr/local/bin/$name"
        "/usr/local/sbin/$name"
        "/usr/bin/$name"
        "/bin/$name"
        "/usr/sbin/$name"
        "/sbin/$name"
        "/snap/bin/$name"
    )

    for candidate in "${candidates[@]}"; do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    IFS=':' read -r -a path_entries <<< "${PATH:-}"
    for path_dir in "${path_entries[@]}"; do
        sanitized_dir="$(_acfs_doctor_sanitize_abs_nonroot_path "$path_dir" 2>/dev/null || true)"
        [[ -n "$sanitized_dir" ]] || continue
        case "$sanitized_dir" in
            "$runtime_home"|"$runtime_home"/*)
                candidate="$sanitized_dir/$name"
                [[ -x "$candidate" ]] || continue
                printf '%s\n' "$candidate"
                return 0
                ;;
        esac
    done

    return 1
}


doctor_runtime_path() {
    local runtime_home=""
    local primary_bin_dir=""
    local current_path="${PATH:-}"
    local dir=""
    local seen_path=":"
    local path_prefix=""
    local -a path_entries=()

    runtime_home="$(doctor_runtime_home)"
    [[ -n "$runtime_home" ]] || return 1

    primary_bin_dir="$(_acfs_doctor_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$runtime_home" 2>/dev/null || true)"
    [[ -n "$primary_bin_dir" ]] || primary_bin_dir="$runtime_home/.local/bin"

    if [[ -n "${ACFS_HOME:-}" ]]; then
        path_entries+=("$ACFS_HOME/bin")
        seen_path="${seen_path}${ACFS_HOME}/bin:"
    fi

    for dir in \
        "$primary_bin_dir" \
        "$runtime_home/.local/bin" \
        "$runtime_home/.acfs/bin" \
        "$runtime_home/.bun/bin" \
        "$runtime_home/.cargo/bin" \
        "$runtime_home/.atuin/bin" \
        "$runtime_home/go/bin" \
        "$runtime_home/google-cloud-sdk/bin" \
        "/usr/local/sbin" \
        "/usr/local/bin" \
        "/usr/sbin" \
        "/usr/bin" \
        "/sbin" \
        "/bin" \
        "/snap/bin"; do
        case "$seen_path" in
            *":$dir:"*) ;;
            *)
                path_entries+=("$dir")
                seen_path="${seen_path}${dir}:"
                ;;
        esac
    done

    path_prefix=$(IFS=:; echo "${path_entries[*]}")
    printf '%s\n' "$path_prefix${current_path:+:$current_path}"
}

doctor_binary_exists() {
    local resolved=""
    resolved="$(doctor_binary_path "$1" 2>/dev/null || true)"
    [[ -n "$resolved" ]]
}

doctor_agent_mail_cli_path() {
    doctor_binary_path "am"
}
# Try to retrieve a reasonably informative version line for a command without
# assuming it supports `--version`.
doctor_version_probe() {
    if (( $# < 4 )); then
        return 1
    fi

    local head_bin="/usr/bin/head"
    local timeout_bin="$1"
    local timeout_secs="$2"
    local stderr_mode="${3:-discard}"
    shift 3

    [[ -x "$head_bin" ]] || head_bin="/bin/head"
    [[ -x "$head_bin" ]] || return 1

    if [[ "$stderr_mode" == "merge" ]]; then
        if [[ -n "$timeout_bin" ]]; then
            "$timeout_bin" "$timeout_secs" "$@" 2>&1 | "$head_bin" -n 1
        else
            "$@" 2>&1 | "$head_bin" -n 1
        fi
    elif [[ -n "$timeout_bin" ]]; then
        "$timeout_bin" "$timeout_secs" "$@" 2>/dev/null | "$head_bin" -n 1
    else
        "$@" 2>/dev/null | "$head_bin" -n 1
    fi
}

get_version_line() {
    local cmd="$1"
    local exec_path="$cmd"

    if [[ "$cmd" != */* ]]; then
        exec_path="$(doctor_binary_path "$cmd" 2>/dev/null || true)"
        [[ -n "$exec_path" ]] || exec_path="$cmd"
    fi

    local version=""
    local timeout_bin=""
    timeout_bin="$(_acfs_doctor_system_binary_path timeout 2>/dev/null || true)"
    # UBS has a directory size check that can block --version; bypass it
    if [[ "$cmd" == "ubs" ]] || [[ "$exec_path" == */ubs ]]; then
        version=$(UBS_MAX_DIR_SIZE_MB=10000 doctor_version_probe "$timeout_bin" "$DOCTOR_VERSION_TIMEOUT" discard "$exec_path" --version) || true
    elif [[ "$cmd" == "lsof" ]] || [[ "$exec_path" == */lsof ]]; then
        version=$(doctor_version_probe "$timeout_bin" "$DOCTOR_VERSION_TIMEOUT" merge "$exec_path" -v) || true
    else
        version=$(doctor_version_probe "$timeout_bin" "$DOCTOR_VERSION_TIMEOUT" discard "$exec_path" --version) || true
    fi
    if [[ -z "$version" ]]; then
        version=$(doctor_version_probe "$timeout_bin" "$DOCTOR_VERSION_TIMEOUT" discard "$exec_path" -V) || true
    fi
    if [[ -z "$version" ]]; then
        version=$(doctor_version_probe "$timeout_bin" "$DOCTOR_VERSION_TIMEOUT" discard "$exec_path" version) || true
    fi

    if [[ -z "$version" ]]; then
        version="available"
    fi

    printf '%s' "$version"
}

# Check if command exists
check_command() {
    local id="$1"
    local label="$2"
    local cmd="$3"
    local fix="${4:-}"
    local cmd_path=""

    cmd_path="$(doctor_binary_path "$cmd" 2>/dev/null || true)"
    if [[ -n "$cmd_path" ]]; then
        local version
        version=$(get_version_line "$cmd_path")
        check "$id" "$label ($version)" "pass" "installed"
    else
        check "$id" "$label" "fail" "not found" "$fix"
    fi
}

# Check a command, but treat missing as WARN (optional dependency).
check_optional_command() {
    local id="$1"
    local label="$2"
    local cmd="$3"
    local fix="${4:-}"
    local cmd_path=""

    cmd_path="$(doctor_binary_path "$cmd" 2>/dev/null || true)"
    if [[ -n "$cmd_path" ]]; then
        local version
        version=$(get_version_line "$cmd_path")
        check "$id" "$label ($version)" "pass" "installed"
    else
        check "$id" "$label" "warn" "not found" "$fix"
    fi
}

# Check identity
check_identity() {
    section "Identity"

    # Check user
    local user
    local sudo_bin=""
    local id_bin=""
    local grep_bin=""
    user="$(_acfs_doctor_resolve_current_user 2>/dev/null || true)"
    if [[ "$user" == "$TARGET_USER" ]]; then
        check "identity.user_is_ubuntu" "Logged in as $TARGET_USER" "pass" "whoami=$user"
    else
        check "identity.user_is_ubuntu" "Logged in as $TARGET_USER (currently: $user)" "warn" "whoami=$user" "ssh ${TARGET_USER}@YOUR_SERVER"
    fi

    # Check sudo configuration (passwordless only required in vibe mode)
    sudo_bin="$(_acfs_doctor_system_binary_path sudo 2>/dev/null || true)"
    if [[ "${ACFS_MODE:-vibe}" == "vibe" ]]; then
        if [[ -n "$sudo_bin" ]] && "$sudo_bin" -n true 2>/dev/null; then
            check "identity.passwordless_sudo" "Passwordless sudo (vibe mode)" "pass"
        else
            check "identity.passwordless_sudo" "Passwordless sudo (vibe mode)" "fail" "requires password" "Re-run ACFS installer with --mode vibe"
        fi
    else
        id_bin="$(_acfs_doctor_system_binary_path id 2>/dev/null || true)"
        grep_bin="$(_acfs_doctor_system_binary_path grep 2>/dev/null || true)"
        if [[ -n "$sudo_bin" && -n "$id_bin" && -n "$grep_bin" ]] && "$id_bin" -nG 2>/dev/null | "$grep_bin" -qw sudo; then
            check "identity.sudo" "Sudo available (safe mode)" "pass"
        else
            check "identity.sudo" "Sudo available (safe mode)" "fail" "sudo unavailable" "Ensure ${TARGET_USER} is in the sudo group and sudo is installed"
        fi
    fi

    blank_line
}

# Check workspace
check_workspace() {
    section "Workspace"

    if [[ -d "/data/projects" ]] && [[ -w "/data/projects" ]]; then
        check "workspace.data_projects" "/data/projects exists and writable" "pass"
    else
        check "workspace.data_projects" "/data/projects" "fail" "missing or not writable" "sudo mkdir -p /data/projects && sudo chown ${TARGET_USER}:${TARGET_USER} /data/projects"
    fi

    blank_line
}

# Check shell
check_shell() {
    section "Shell"
    local runtime_home=""
    local zsh_custom=""

    runtime_home="$(doctor_runtime_home)"
    zsh_custom="${ZSH_CUSTOM:-$runtime_home/.oh-my-zsh/custom}"

    check_command "shell.zsh" "zsh" "zsh" "sudo apt install zsh"

    if [[ -d "$runtime_home/.oh-my-zsh" ]]; then
        check "shell.ohmyzsh" "Oh My Zsh" "pass"
    else
        check "shell.ohmyzsh" "Oh My Zsh" "fail" "not installed" "$(fix_for_module "shell.omz")"
    fi

    local p10k_dir="$zsh_custom/themes/powerlevel10k"
    if [[ -d "$p10k_dir" ]]; then
        check "shell.p10k" "Powerlevel10k" "pass"
    else
        check "shell.p10k" "Powerlevel10k" "warn" "not installed"
    fi

    # Check plugins
    local plugins_dir="$zsh_custom/plugins"
    if [[ -d "$plugins_dir/zsh-autosuggestions" ]]; then
        check "shell.plugins.zsh_autosuggestions" "zsh-autosuggestions" "pass"
    else
        check "shell.plugins.zsh_autosuggestions" "zsh-autosuggestions" "warn" "not installed" \
            "git clone https://github.com/zsh-users/zsh-autosuggestions \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    fi

    if [[ -d "$plugins_dir/zsh-syntax-highlighting" ]]; then
        check "shell.plugins.zsh_syntax_highlighting" "zsh-syntax-highlighting" "pass"
    else
        check "shell.plugins.zsh_syntax_highlighting" "zsh-syntax-highlighting" "warn" "not installed" \
            "git clone https://github.com/zsh-users/zsh-syntax-highlighting \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
    fi

    # Check modern CLI tools
    local lsd_bin=""
    local eza_bin=""
    lsd_bin="$(doctor_binary_path lsd 2>/dev/null || true)"
    eza_bin="$(doctor_binary_path eza 2>/dev/null || true)"
    if [[ -n "$lsd_bin" ]]; then
        check "shell.lsd_or_eza" "lsd" "pass"
    elif [[ -n "$eza_bin" ]]; then
        check "shell.lsd_or_eza" "eza (fallback)" "pass"
    else
        check "shell.lsd_or_eza" "lsd/eza" "warn" "neither installed" "sudo apt install lsd"
    fi

    check_command "shell.atuin" "Atuin" "atuin" "$(fix_for_module "shell.atuin")"
    check_command "shell.fzf" "fzf" "fzf" "sudo apt install fzf"
    check_command "shell.zoxide" "zoxide" "zoxide" \
        "Re-run: curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash"
    check_command "shell.direnv" "direnv" "direnv" "sudo apt install direnv"

    blank_line
}

# Check core tools
check_core_tools() {
    section "Core tools"

    check_command "tool.bun" "Bun" "bun" "$(fix_for_module "lang.bun")"
    check_command "tool.uv" "uv" "uv" "$(fix_for_module "lang.uv")"
    check_command "tool.cargo" "Cargo (Rust)" "cargo" "$(fix_for_module "lang.rust")"
    check_command "tool.go" "Go" "go" "sudo apt install golang-go"
    check_command "tool.tmux" "tmux" "tmux" "sudo apt install tmux"
    check_command "tool.rg" "ripgrep" "rg" "sudo apt install ripgrep"
    check_command "tool.gh" "GitHub CLI (gh)" "gh" "sudo apt-get install -y gh"
    check_command "tool.git_lfs" "Git LFS" "git-lfs" "sudo apt-get install -y git-lfs"
    check_command "tool.rsync" "rsync" "rsync" "sudo apt-get install -y rsync"
    check_command "tool.strace" "strace" "strace" "sudo apt-get install -y strace"
    check_command "tool.lsof" "lsof" "lsof" "sudo apt-get install -y lsof"
    check_command "tool.zstd" "zstd" "zstd" "sudo apt-get install -y zstd"
    check_optional_command "tool.cosign" "cosign" "cosign" \
        "COSIGN_VERSION=v2.4.1 && curl -fsSL https://github.com/sigstore/cosign/releases/download/\${COSIGN_VERSION}/cosign-linux-amd64 -o /tmp/cosign && sudo install /tmp/cosign /usr/local/bin/cosign"
    check_command "tool.dig" "dig (dnsutils)" "dig" "sudo apt-get install -y dnsutils"
    check_command "tool.nc" "nc (netcat-openbsd)" "nc" "sudo apt-get install -y netcat-openbsd"
    check_command "tool.sg" "ast-grep" "sg" "cargo install ast-grep --locked"

    blank_line
}

# Check coding agents
check_agents() {
    section "Agents"

    check_command "agent.claude" "Claude Code" "claude" "$(fix_for_module "agents.claude")"
    check_command "agent.codex" "Codex CLI" "codex" "$(fix_for_module "agents.codex")"
    check_command "agent.gemini" "Gemini CLI" "gemini" "$(fix_for_module "agents.gemini")"

    # Check aliases are defined in the zshrc
    local alias_fix
    local target_zshrc=""
    alias_fix="$(fix_for_module "shell.omz")"
    target_zshrc="$(_acfs_doctor_find_project_path "zsh/acfs.zshrc" 2>/dev/null || true)"
    if grep -q "^alias cc=" "$target_zshrc" 2>/dev/null; then
        check "agent.alias.cc" "cc alias" "pass"
    else
        check "agent.alias.cc" "cc alias" "warn" "not in zshrc" "$alias_fix"
    fi

    if grep -q "^alias cod=" "$target_zshrc" 2>/dev/null; then
        check "agent.alias.cod" "cod alias" "pass"
    else
        check "agent.alias.cod" "cod alias" "warn" "not in zshrc" "$alias_fix"
    fi

    # gmi is defined as a shell function (not an alias) in acfs.zshrc
    if grep -q "^gmi()" "$target_zshrc" 2>/dev/null || grep -q "^alias gmi=" "$target_zshrc" 2>/dev/null; then
        check "agent.alias.gmi" "gmi function" "pass"
    else
        check "agent.alias.gmi" "gmi function" "warn" "not in zshrc" "$alias_fix"
    fi

    # Check for PATH conflicts (bead hi7)
    # Claude Code native install should be in ~/.local/bin, not bun/npm
    check_agent_path_conflicts

    blank_line
}

# Check for agent PATH conflicts (bead hi7)
# Native installations should take precedence over package manager versions
check_agent_path_conflicts() {
    local doctor_ci="${ACFS_DOCTOR_CI:-false}"
    local expected_native_path=""
    expected_native_path="$(doctor_runtime_home)/.local/bin/claude"

    local claude_path
    claude_path="$(doctor_binary_path claude 2>/dev/null || true)"

    if [[ -z "$claude_path" ]]; then
        return 0  # Not installed, skip
    fi

    # Native install should be in ~/.local/bin
    if [[ "$claude_path" == "$expected_native_path" ]]; then
        check "agent.path.claude" "Claude Code path" "pass" "native ($claude_path)"
    elif [[ "$claude_path" == *".bun"* ]] || [[ "$claude_path" == *"node_modules"* ]]; then
        if [[ "$doctor_ci" == "true" ]]; then
            check "agent.path.claude" "Claude Code path" "pass" "using bun/npm version (expected in CI): $claude_path"
        else
            # Package manager version - warn about potential conflicts
            check "agent.path.claude" "Claude Code path" "warn" \
                "using bun/npm version ($claude_path)" \
                "Switch to native: acfs update --force --agents-only (removes bun version, installs native)"
        fi
    else
        # Some other path - just note it
        check "agent.path.claude" "Claude Code path" "pass" "$claude_path"
    fi
}

# Check DCG hook registration status
check_dcg_hook_status() {
    if ! doctor_binary_exists "dcg"; then
        check "stack.dcg" "DCG" "warn" "not installed" \
            "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/destructive_command_guard/main/install.sh | bash && dcg install"
        return
    fi

    local version
    version=$(get_version_line "dcg")

    if ! doctor_binary_exists "claude"; then
        check "stack.dcg" "DCG ($version)" "warn" "Claude Code not found for hook registration" \
            "Install Claude Code, then run: dcg install"
        return
    fi

    local settings_file=""
    local settings_home=""
    settings_home="$(doctor_runtime_home)"
    if [[ -f "$settings_home/.claude/settings.json" ]]; then
        settings_file="$settings_home/.claude/settings.json"
    elif [[ -f "$settings_home/.config/claude/settings.json" ]]; then
        settings_file="$settings_home/.config/claude/settings.json"
    elif [[ "$settings_home" != "$HOME" ]] && [[ -f "$HOME/.claude/settings.json" ]]; then
        settings_file="$HOME/.claude/settings.json"
    elif [[ "$settings_home" != "$HOME" ]] && [[ -f "$HOME/.config/claude/settings.json" ]]; then
        settings_file="$HOME/.config/claude/settings.json"
    fi

    if [[ -z "$settings_file" ]]; then
        check "stack.dcg" "DCG ($version)" "warn" "hook not registered (settings.json missing)" \
            "Run: dcg install"
        return
    fi

    if _acfs_doctor_claude_settings_has_command_hook "$settings_file" '(^|[[:space:]/])dcg([[:space:]]|$)'; then
        check "stack.dcg" "DCG ($version)" "pass" "installed + hook registered"
    else
        check "stack.dcg" "DCG ($version)" "warn" "binary installed but hook not registered" \
            "Run: dcg install"
    fi
}

# Check cloud tools
check_cloud() {
    section "Cloud/DB"

    local doctor_ci="${ACFS_DOCTOR_CI:-false}"

    check_optional_command "cloud.vault" "Vault" "vault"
    check_optional_command "cloud.postgres" "PostgreSQL" "psql"
    check_optional_command "cloud.wrangler" "Wrangler" "wrangler" "bun install -g --trust wrangler@latest"
    check_optional_command "cloud.supabase" "Supabase CLI" "supabase" "acfs update --cloud-only --force"
    check_optional_command "cloud.vercel" "Vercel CLI" "vercel" "bun install -g --trust vercel@latest"

    # Tailscale VPN (bt5)
    local tailscale_bin=""
    tailscale_bin="$(doctor_binary_path tailscale 2>/dev/null || true)"
    if [[ -n "$tailscale_bin" ]]; then
        local ts_status
        if command -v jq &>/dev/null; then
            ts_status=$("$tailscale_bin" status --json 2>/dev/null | jq -r '.BackendState // "unknown"' 2>/dev/null || echo "unknown")
        else
            ts_status=$("$tailscale_bin" status --json 2>/dev/null | sed -n 's/.*"BackendState"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
            ts_status="${ts_status:-unknown}"
        fi
        case "$ts_status" in
            "Running")
                check "network.tailscale" "Tailscale" "pass" "connected"
                ;;
            "NeedsLogin")
                if [[ "$doctor_ci" == "true" ]]; then
                    check "network.tailscale" "Tailscale (needs login)" "pass" "expected in CI"
                else
                    check "network.tailscale" "Tailscale" "warn" "needs login" "Run: sudo tailscale up"
                fi
                ;;
            *)
                if [[ "$doctor_ci" == "true" ]]; then
                    check "network.tailscale" "Tailscale ($ts_status)" "pass" "expected in CI"
                else
                    check "network.tailscale" "Tailscale" "warn" "$ts_status" "Run: sudo tailscale up"
                fi
                ;;
        esac
    else
        if [[ "$doctor_ci" == "true" ]]; then
            check "network.tailscale" "Tailscale (not installed)" "pass" "ok in CI"
        else
            check "network.tailscale" "Tailscale" "warn" "not installed (optional)" "Install: curl --proto '=https' --proto-redir '=https' -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only network.tailscale"
        fi
    fi

    # SSH server installed and running (fixes #161)
    # Fresh installs (WSL, VM, containers) may not have openssh-server
    local sshd_bin=""
    local systemctl_bin=""
    sshd_bin="$(_acfs_doctor_system_binary_path sshd 2>/dev/null || true)"
    systemctl_bin="$(_acfs_doctor_system_binary_path systemctl 2>/dev/null || true)"
    if [[ -n "$sshd_bin" ]] || [[ -f /etc/ssh/sshd_config ]]; then
        if [[ -n "$systemctl_bin" && -d /run/systemd/system ]]; then
            if "$systemctl_bin" is-active --quiet ssh 2>/dev/null || "$systemctl_bin" is-active --quiet sshd 2>/dev/null; then
                check "network.ssh_server" "SSH server" "pass" "installed and running"
            else
                check "network.ssh_server" "SSH server" "warn" "installed but not running" \
                    "sudo systemctl enable --now ssh"
            fi
        else
            check "network.ssh_server" "SSH server" "pass" "installed (no systemd)"
        fi
    else
        if [[ "$doctor_ci" == "true" ]]; then
            check "network.ssh_server" "SSH server (not installed)" "pass" "ok in CI"
        else
            check "network.ssh_server" "SSH server" "warn" "not installed" \
                "sudo apt-get install -y openssh-server && sudo systemctl enable --now ssh"
        fi
    fi

    # SSH keepalive configuration (prevents VPN/NAT disconnects)
    # Check both main config and sshd_config.d includes for ClientAliveInterval
    local keepalive_interval=""
    local keepalive_source=""

    # Check main sshd_config (allow leading whitespace, handle commented lines)
    if [[ -f /etc/ssh/sshd_config ]]; then
        keepalive_interval=$(grep -E '^[[:space:]]*ClientAliveInterval[[:space:]]+[0-9]+' /etc/ssh/sshd_config 2>/dev/null | { grep -v '^[[:space:]]*#' || true; } | tail -n1 | awk '{print $2}')
        [[ -n "$keepalive_interval" ]] && keepalive_source="sshd_config"
    fi

    # Check sshd_config.d includes (common on Ubuntu 22.04+)
    if [[ -z "$keepalive_interval" ]] && [[ -d /etc/ssh/sshd_config.d ]]; then
        for conf_file in /etc/ssh/sshd_config.d/*.conf; do
            [[ -f "$conf_file" ]] || continue
            local val
            val=$(grep -E '^[[:space:]]*ClientAliveInterval[[:space:]]+[0-9]+' "$conf_file" 2>/dev/null | { grep -v '^[[:space:]]*#' || true; } | tail -n1 | awk '{print $2}')
            if [[ -n "$val" ]]; then
                keepalive_interval="$val"
                keepalive_source="$(basename "$conf_file")"
                break
            fi
        done
    fi

    keepalive_interval="${keepalive_interval:-0}"
    if [[ "$keepalive_interval" -gt 0 ]] 2>/dev/null; then
        check "network.ssh_keepalive" "SSH keepalive" "pass" "ClientAliveInterval ${keepalive_interval}s (${keepalive_source})"
    else
        if [[ "$doctor_ci" == "true" ]]; then
            check "network.ssh_keepalive" "SSH keepalive (not configured)" "pass" "ok in CI"
        else
            check "network.ssh_keepalive" "SSH keepalive" "warn" "not configured (optional)" "$(fix_for_module "network.ssh_keepalive")"
        fi
    fi

    blank_line
}

# Check Dicklesworthstone stack
check_stack() {
    local ubs_bin=""
    local bv_path=""
    local am_bin=""
    local ru_bin=""

    section "Dicklesworthstone stack"

    check_command "stack.ntm" "NTM" "ntm" \
        "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh | bash"
    check_command "stack.slb" "SLB" "slb" \
        "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/simultaneous_launch_button/main/scripts/install.sh | bash"

    # UBS - custom check
    if ubs_bin="$(doctor_binary_path ubs 2>/dev/null || true)" && [[ -n "$ubs_bin" ]]; then
        local version
        version=$(get_version_line "$ubs_bin")
        check "stack.ubs" "UBS ($version)" "pass" "installed"
    else
        check "stack.ubs" "UBS" "fail" "not found" \
            "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/main/install.sh | bash"
    fi

    # Beads Viewer - custom check to detect gcloud 'bv' shadowing
    if bv_path="$(doctor_binary_path bv 2>/dev/null || true)" && [[ -n "$bv_path" ]]; then
        local version
        # Check if the resolved bv is gcloud's BigQuery Visualizer
        if [[ "$bv_path" == *"google-cloud-sdk"* ]]; then
            check "stack.bv" "Beads Viewer" "fail" "SHADOWED by gcloud bv at $bv_path" \
                "gcloud's 'bv' (BigQuery) is masking beads_viewer. Fix: Ensure ~/.local/bin is before gcloud in PATH, or re-run installer."
        else
            version=$(get_version_line "$bv_path")
            # Also warn if gcloud's bv exists anywhere in PATH
            local gcloud_bv
            gcloud_bv=$(type -ap bv 2>/dev/null | grep "google-cloud-sdk" | head -1 || true)
            if [[ -n "$gcloud_bv" ]]; then
                check "stack.bv" "Beads Viewer ($version)" "warn" "gcloud bv exists at $gcloud_bv (but correctly shadowed)" \
                    "beads_viewer is correctly prioritized, but gcloud's bv exists. ACFS zshrc handles this."
            else
                check "stack.bv" "Beads Viewer ($version)" "pass" "installed"
            fi
        fi
    else
        check "stack.bv" "Beads Viewer" "fail" "not found" \
            "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh | bash"
    fi

    # CASS - custom check
    if doctor_binary_exists "cass"; then
        local version
        version=$(get_version_line "$(doctor_binary_path cass 2>/dev/null || echo cass)")
        check "stack.cass" "CASS ($version)" "pass" "installed"
    else
        check "stack.cass" "CASS" "fail" "not found" \
            "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh | bash -s -- --easy-mode"
    fi

    check_command "stack.cm" "CASS Memory" "cm" \
        "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/cass_memory_system/main/install.sh | bash -s -- --easy-mode"
    check_command "stack.caam" "CAAM" "caam" \
        "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_account_manager/main/install.sh | bash"

    # Check MCP Agent Mail
    local am_install_fix am_repair_fix am_version am_label
    am_install_fix="Re-run: $(fix_for_module "stack.mcp_agent_mail")"
    am_repair_fix='Run: am doctor repair --yes && am doctor fix --yes'
    am_label="MCP Agent Mail"

    if am_bin="$(doctor_agent_mail_cli_path 2>/dev/null || true)" && [[ -n "$am_bin" ]]; then
        local am_global_doctor_json am_project_doctor_json am_project_path am_details
        local curl_bin=""
        local id_bin=""
        local systemctl_bin=""

        am_version=$(get_version_line "$am_bin")
        am_label="MCP Agent Mail ($am_version)"
        curl_bin="$(_acfs_doctor_system_binary_path curl 2>/dev/null || true)"

        if [[ -z "$curl_bin" ]] || ! "$curl_bin" -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1; then
            check "stack.mcp_agent_mail" "$am_label" "warn" "installed but service is not running" "$am_install_fix"
        elif {
            id_bin="$(_acfs_doctor_system_binary_path id 2>/dev/null || true)"
            systemctl_bin="$(_acfs_doctor_system_binary_path systemctl 2>/dev/null || true)"
            local am_uid=""
            local am_runtime_dir=""
            if [[ -n "$id_bin" ]]; then
                am_uid="$("$id_bin" -u 2>/dev/null || true)"
            fi
            [[ -n "$am_uid" ]] && am_runtime_dir="/run/user/$am_uid"
            if [[ -d "$am_runtime_dir" ]]; then
                export XDG_RUNTIME_DIR="$am_runtime_dir"
                if [[ -S "$am_runtime_dir/bus" ]]; then
                    export DBUS_SESSION_BUS_ADDRESS="unix:path=$am_runtime_dir/bus"
                fi
            fi
            [[ -n "$systemctl_bin" ]] && "$systemctl_bin" --user show-environment >/dev/null 2>&1 && \
                ! "$systemctl_bin" --user is-active --quiet agent-mail.service >/dev/null 2>&1
        }; then
            check "stack.mcp_agent_mail" "$am_label" "warn" \
                "HTTP endpoint is healthy but agent-mail.service is inactive; rerun install/update to migrate off the fallback launcher" \
                "$am_install_fix"
        else
            am_global_doctor_json="$(agent_mail_doctor_check_json || true)"
            if [[ -z "$am_global_doctor_json" ]]; then
                check "stack.mcp_agent_mail" "$am_label" "warn" \
                    "service healthy but doctor check timed out or returned invalid output" \
                    "$am_repair_fix"
            elif ! agent_mail_doctor_is_healthy "$am_global_doctor_json"; then
                am_details="$(agent_mail_doctor_summary "$am_global_doctor_json")"
                check "stack.mcp_agent_mail" "$am_label" "warn" \
                    "${am_details:-global doctor check reported unhealthy state}" \
                    "$am_repair_fix"
            else
                am_project_path="$(git rev-parse --show-toplevel 2>/dev/null || true)"
                if [[ -n "$am_project_path" ]]; then
                    am_project_doctor_json="$(agent_mail_doctor_check_json "$am_project_path" || true)"
                    if [[ -z "$am_project_doctor_json" ]]; then
                        check "stack.mcp_agent_mail" "$am_label" "warn" \
                            "service healthy but current-project doctor check timed out or returned invalid output" \
                            "$am_repair_fix"
                    elif ! agent_mail_doctor_is_healthy "$am_project_doctor_json"; then
                        am_details="$(agent_mail_doctor_summary "$am_project_doctor_json")"
                        check "stack.mcp_agent_mail" "$am_label" "warn" \
                            "current project unhealthy: ${am_details:-project doctor check reported unhealthy state}" \
                            "$am_repair_fix"
                    else
                        check "stack.mcp_agent_mail" "$am_label" "pass" "service healthy; doctor check OK"
                    fi
                else
                    check "stack.mcp_agent_mail" "$am_label" "pass" "service healthy; doctor check OK"
                fi
            fi
        fi
    elif [[ -d "$(doctor_runtime_home)/mcp_agent_mail" ]]; then
        local runtime_home=""
        runtime_home="$(doctor_runtime_home)"
        if [[ -x "$runtime_home/mcp_agent_mail/am" ]] && ! doctor_agent_mail_cli_path >/dev/null 2>&1; then
            check "symlink.am" "$am_label" "warn" \
                "binary exists at ~/mcp_agent_mail/am but symlink missing from ~/.local/bin/am" \
                "Fix: ln -sf ~/mcp_agent_mail/am ~/.local/bin/am (or run: acfs doctor --fix)"
        else
            check "stack.mcp_agent_mail" "$am_label" "warn" "install directory present but am CLI is missing" "$am_install_fix"
        fi
    else
        check "stack.mcp_agent_mail" "$am_label" "warn" "not installed" "$am_install_fix"
    fi

    # Check RU (Repo Updater)
    if ru_bin="$(doctor_binary_path ru 2>/dev/null || true)" && [[ -n "$ru_bin" ]]; then
        local version
        version=$(get_version_line "$ru_bin")
        check "stack.ru" "RU ($version)" "pass" "installed"
    else
        check "stack.ru" "RU (Repo Updater)" "warn" "not installed" \
            "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/repo_updater/main/install.sh | bash"
    fi

    # Check beads_rust (br) - local-first issue tracker.
    # Resolve against the target user's install first so a binary that exists
    # only in the invoking shell does not create a false pass.
    local _br_bin=""
    _br_bin="$(doctor_binary_path br 2>/dev/null || true)"
    if [[ -n "$_br_bin" ]]; then
        local version
        version=$(get_version_line "$_br_bin")
        check "stack.beads_rust" "beads_rust ($version)" "pass" "installed"
    else
        check "stack.beads_rust" "beads_rust (br)" "warn" "not installed" \
            "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh | bash"
    fi

    # Check meta_skill (ms)
    local ms_bin=""
    ms_bin="$(doctor_binary_path ms 2>/dev/null || true)"
    if [[ -n "$ms_bin" ]]; then
        local version
        version=$(get_version_line "$ms_bin")
        check "stack.meta_skill" "meta_skill ($version)" "pass" "installed"
    else
        # Detect architecture to give the right install advice
        local _ms_arch _ms_os _ms_fix
        _ms_arch="$(uname -m 2>/dev/null || echo unknown)"
        _ms_os="$(uname -s 2>/dev/null || echo unknown)"
        _ms_fix="Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/meta_skill/main/scripts/install.sh | bash"

        # Pre-built binaries exist for: x86_64-linux, aarch64-darwin, x86_64-darwin
        # ARM64 Linux (aarch64-Linux) does NOT have a pre-built binary yet:
        # https://github.com/Dicklesworthstone/meta_skill/issues/1
        case "${_ms_arch}-${_ms_os}" in
            aarch64-Linux|arm64-Linux)
                # ARM64 Linux binary is not yet published; the install script will 404
                check "stack.meta_skill" "meta_skill (ms)" "warn" \
                    "ARM64 Linux binary not yet available (see https://github.com/Dicklesworthstone/meta_skill/issues/1)" \
                    "Build from source: cargo install --git https://github.com/Dicklesworthstone/meta_skill --force"
                ;;
            x86_64-Linux|x86_64-Darwin|arm64-Darwin|aarch64-Darwin)
                # These platforms have pre-built binaries
                check "stack.meta_skill" "meta_skill (ms)" "warn" "not installed" \
                    "$_ms_fix"
                ;;
            *)
                _ms_fix="meta_skill has no pre-built binary for ${_ms_arch}-${_ms_os}. Build from source: cargo install --git https://github.com/Dicklesworthstone/meta_skill --force"
                check "stack.meta_skill" "meta_skill (ms)" "warn" "not installed" \
                    "$_ms_fix"
                ;;
        esac
    fi

    # Check rch (Remote Compilation Helper)
    # RCH can be installed in several locations: PATH, ~/.local/bin, ~/.cargo/bin, or ~/remote_compilation_helper
    local rch_bin=""
    local rch_version=""
    local runtime_home=""
    runtime_home="$(doctor_runtime_home)"

    rch_bin="$(doctor_binary_path rch 2>/dev/null || true)"
    if [[ -z "$rch_bin" && -x "$runtime_home/remote_compilation_helper/rch" ]]; then
        rch_bin="$runtime_home/remote_compilation_helper/rch"
    fi

    if [[ -n "$rch_bin" ]] && [[ -x "$rch_bin" ]]; then
        rch_version=$("$rch_bin" --version 2>/dev/null | head -n1) || rch_version="installed"
        check "stack.rch" "rch ($rch_version)" "pass" "installed"
    else
        # Also check if RCH config exists (indicates partial/previous install)
        if [[ -f "$runtime_home/.config/rch/config.toml" ]] || [[ -d "$runtime_home/remote_compilation_helper" ]]; then
            check "stack.rch" "rch (Remote Compilation Helper)" "warn" "config exists but binary not in PATH" \
                "Add rch to PATH or re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/remote_compilation_helper/main/install.sh | bash"
        else
            check "stack.rch" "rch (Remote Compilation Helper)" "warn" "not installed" \
                "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/remote_compilation_helper/main/install.sh | bash"
        fi
    fi

    # Check wa (WezTerm Automata) - optional
    local wa_bin=""
    wa_bin="$(doctor_binary_path wa 2>/dev/null || true)"
    if [[ -n "$wa_bin" ]]; then
        local version
        version=$(get_version_line "$wa_bin")
        check "stack.wezterm_automata" "wezterm_automata ($version)" "pass" "installed"
    else
        check "stack.wezterm_automata" "wezterm_automata (wa)" "skip" "not installed (optional)"
    fi

    # Check brenner (Brenner Bot) - optional
    local brenner_bin=""
    brenner_bin="$(doctor_binary_path brenner 2>/dev/null || true)"
    if [[ -n "$brenner_bin" ]]; then
        local version
        version=$(get_version_line "$brenner_bin")
        check "stack.brenner_bot" "brenner_bot ($version)" "pass" "installed"
    else
        check "stack.brenner_bot" "brenner_bot" "skip" "not installed (optional)"
    fi

    # Check DCG (Destructive Command Guard)
    check_dcg_hook_status

    # Check acfs-nightly-update timer (systemd user unit)
    # Gracefully handle missing systemd user session (curl|bash installs as
    # root don't have a D-Bus session, so systemctl --user always fails).
    local _nightly_status="unknown"
    local systemctl_bin=""
    systemctl_bin="$(_acfs_doctor_system_binary_path systemctl 2>/dev/null || true)"
    if [[ -n "$systemctl_bin" && -d /run/systemd/system ]]; then
        # Try to access the user session; if no D-Bus, fall back to checking
        # the unit file exists on disk instead.
        local _target_home=""
        _target_home="$(doctor_runtime_home)"
        local _nightly_unit_file="${_target_home}/.config/systemd/user/acfs-nightly-update.timer"
        if "$systemctl_bin" --user is-enabled acfs-nightly-update.timer &>/dev/null 2>&1; then
            _nightly_status="enabled"
        elif [[ -f "$_nightly_unit_file" ]]; then
            _nightly_status="unit_exists"
        else
            _nightly_status="missing"
        fi
    else
        _nightly_status="no_systemd"
    fi
    case "$_nightly_status" in
        enabled)
            check "acfs.nightly" "Nightly auto-update timer" "pass" "enabled"
            ;;
        unit_exists)
            check "acfs.nightly" "Nightly auto-update timer" "warn" \
                "unit file exists but timer not enabled (no D-Bus user session?)" \
                "loginctl enable-linger \$(whoami) && systemctl --user enable --now acfs-nightly-update.timer"
            ;;
        no_systemd)
            check "acfs.nightly" "Nightly auto-update timer" "skip" \
                "no systemd or no user session (expected for curl|bash root installs)"
            ;;
        *)
            check "acfs.nightly" "Nightly auto-update timer" "warn" \
                "not installed (optional)" \
                "$(fix_for_module "acfs.nightly")"
            ;;
    esac

    blank_line
}

# ============================================================
# Utility Tools Health Checks (bd-2gog)
# ============================================================
# Optional utility tools from the Dicklesworthstone ecosystem.
# These are non-fatal checks (skip status) since utilities are optional.
# ============================================================

check_utilities() {
    local util_bin=""

    section "Utility tools"

    # tru (Token-Optimized Notation)
    util_bin="$(doctor_binary_path tru 2>/dev/null || true)"
    if [[ -n "$util_bin" ]]; then
        local version
        version=$(get_version_line "$util_bin")
        check "util.tru" "tru ($version)" "pass" "installed"
    else
        check "util.tru" "tru (token notation)" "skip" "not installed (optional)"
    fi

    # rust_proxy (Transparent Proxy Routing)
    util_bin="$(doctor_binary_path rust_proxy 2>/dev/null || true)"
    if [[ -n "$util_bin" ]]; then
        local version
        version=$(get_version_line "$util_bin")
        check "util.rust_proxy" "rust_proxy ($version)" "pass" "installed"
    else
        check "util.rust_proxy" "rust_proxy (proxy routing)" "skip" "not installed (optional)"
    fi

    # rano (Network Observer for AI CLIs)
    util_bin="$(doctor_binary_path rano 2>/dev/null || true)"
    if [[ -n "$util_bin" ]]; then
        local version
        version=$(get_version_line "$util_bin")
        check "util.rano" "rano ($version)" "pass" "installed"
    else
        check "util.rano" "rano (network observer)" "skip" "not installed (optional)"
    fi

    # xf (X/Twitter Archive Search)
    util_bin="$(doctor_binary_path xf 2>/dev/null || true)"
    if [[ -n "$util_bin" ]]; then
        local version
        version=$(get_version_line "$util_bin")
        check "util.xf" "xf ($version)" "pass" "installed"
    else
        check "util.xf" "xf (X archive search)" "skip" "not installed (optional)"
    fi

    # mdwb (Markdown Web Browser)
    util_bin="$(doctor_binary_path mdwb 2>/dev/null || true)"
    if [[ -n "$util_bin" ]]; then
        local version
        version=$(get_version_line "$util_bin")
        check "util.mdwb" "mdwb ($version)" "pass" "installed"
    else
        check "util.mdwb" "mdwb (markdown browser)" "skip" "not installed (optional)"
    fi

    # pt (Process Triage)
    util_bin="$(doctor_binary_path pt 2>/dev/null || true)"
    if [[ -n "$util_bin" ]]; then
        local version
        version=$(get_version_line "$util_bin")
        check "util.pt" "pt ($version)" "pass" "installed"
    else
        check "util.pt" "pt (process triage)" "skip" "not installed (optional)"
    fi

    # aadc (ASCII Diagram Corrector)
    util_bin="$(doctor_binary_path aadc 2>/dev/null || true)"
    if [[ -n "$util_bin" ]]; then
        local version
        version=$(get_version_line "$util_bin")
        check "util.aadc" "aadc ($version)" "pass" "installed"
    else
        check "util.aadc" "aadc (ASCII diagram corrector)" "skip" "not installed (optional)"
    fi

    # s2p (Source to Prompt TUI)
    util_bin="$(doctor_binary_path s2p 2>/dev/null || true)"
    if [[ -n "$util_bin" ]]; then
        local version
        version=$(get_version_line "$util_bin")
        check "util.s2p" "s2p ($version)" "pass" "installed"
    else
        check "util.s2p" "s2p (source to prompt)" "skip" "not installed (optional)"
    fi

    # caut (Coding Agent Usage Tracker)
    util_bin="$(doctor_binary_path caut 2>/dev/null || true)"
    if [[ -n "$util_bin" ]]; then
        local version
        version=$(get_version_line "$util_bin")
        check "util.caut" "caut ($version)" "pass" "installed"
    else
        check "util.caut" "caut (usage tracker)" "skip" "not installed (optional)"
    fi

    blank_line
}

# ============================================================
# Manifest Supplemental Checks (bd-31ps.5.1)
# ============================================================
# Runs manifest-derived checks for tools NOT already covered by the bespoke
# check functions above.  This fills gaps (lazygit, nvm, apr, jfp, pt, srps,
# all utils.*, acfs.*, base.system.*) without duplicating bespoke output.
# ============================================================

# Returns 0 (true) if the given manifest ID is already verified by a bespoke
# check function; 1 (false) if it needs manifest supplemental coverage.
_is_bespoke_covered() {
    local id="$1"

    # Match against the raw check ID (e.g. "stack.beads_rust.1") rather than
    # the stripped module_id.  The previous approach stripped the trailing ".N"
    # via _manifest_module_id and then tested against patterns like
    # "stack.beads_rust.*" which requires a dot after the base — but the
    # stripped module_id ("stack.beads_rust") has no trailing dot so the pattern
    # never matched, causing duplicate/false-negative warnings (#241).

    case "$id" in
        # check_cloud covers the CLI presence check, but we still want the
        # manifest-derived PostgreSQL service health check (db.postgres18.2).
        db.postgres18.1) return 0 ;;
        # check_identity
        users.ubuntu|users.ubuntu.*) return 0 ;;
        # check_workspace
        base.filesystem.[12]) return 0 ;;
        acfs.workspace|acfs.workspace.*) return 0 ;;
        # check_shell
        shell|shell.*) return 0 ;;
        # check_core_tools  (cli.modern.* maps to rg, tmux, fzf, gh, etc.)
        cli.modern|cli.modern.*) return 0 ;;
        # check_core_tools  (languages)
        lang.bun|lang.uv|lang.rust|lang.rust.*|lang.go) return 0 ;;
        # check_shell / check_core_tools  (individual tools)
        tools.atuin|tools.zoxide|tools.ast_grep|tools.vault) return 0 ;;
        # check_agents
        agents|agents.*) return 0 ;;
        # check_cloud / check_ssh
        cloud.wrangler|cloud.supabase|cloud.vercel) return 0 ;;
        network.tailscale|network.tailscale.*|network.ssh_keepalive|network.ssh_keepalive.*) return 0 ;;
        # check_stack  (individual stack entries)
        stack.ntm|stack.slb|stack.mcp_agent_mail|stack.mcp_agent_mail.*) return 0 ;;
        stack.ultimate_bug_scanner|stack.ultimate_bug_scanner.*|stack.beads_viewer) return 0 ;;
        stack.beads_rust|stack.beads_rust.*|stack.cass|stack.cm|stack.cm.*|stack.caam) return 0 ;;
        stack.dcg|stack.dcg.*|stack.ru|stack.meta_skill|stack.meta_skill.*) return 0 ;;
        stack.brenner_bot|stack.rch|stack.wezterm_automata) return 0 ;;
        # check_stack  (acfs nightly timer — bespoke handles D-Bus gracefully)
        acfs.nightly) return 0 ;;
        # check_utilities (bd-2gog)
        util|util.*|utils|utils.*) return 0 ;;
    esac
    return 1
}

# Extract the manifest module ID from a check ID by stripping trailing ".N".
# e.g., "stack.automated_plan_reviser.1" → "stack.automated_plan_reviser"
# e.g., "tools.lazygit" → "tools.lazygit" (no change)
_manifest_module_id() {
    local id="$1"
    if [[ "$id" =~ ^(.+)\.[0-9]+$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "$id"
    fi
}

_doctor_run_manifest_check() {
    local run_as="$1"
    local cmd="$2"
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-}"
    local explicit_target_home=""
    local resolved_target_home=""
    local current_home=""
    local target_path=""
    local env_bin=""
    local bash_bin=""
    local sudo_bin=""
    local runuser_bin=""
    local su_bin=""

    explicit_target_home="$target_home"
    if [[ -n "$explicit_target_home" ]]; then
        explicit_target_home="${explicit_target_home%/}"
    fi

    if declare -f _acfs_validate_target_user >/dev/null 2>&1; then
        _acfs_validate_target_user "$target_user" "TARGET_USER" || return 1
    elif [[ -z "$target_user" ]] || [[ ! "$target_user" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
        log_error "Invalid TARGET_USER '${target_user:-<empty>}' (expected: lowercase user name like 'ubuntu')"
        return 1
    fi

    if [[ "$target_user" == "root" ]]; then
        resolved_target_home="/root"
    else
        local passwd_entry=""
        passwd_entry="$(_acfs_doctor_getent_passwd_entry "$target_user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            resolved_target_home="$(_acfs_doctor_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
        elif [[ "$target_user" == "$(_acfs_doctor_resolve_current_user 2>/dev/null || true)" ]]; then
            current_home="$(_acfs_doctor_sanitize_abs_nonroot_path "${_acfs_doctor_current_home:-}" 2>/dev/null || true)"
            if [[ -n "$current_home" ]] && { [[ -z "$explicit_target_home" ]] || [[ "$current_home" == "$explicit_target_home" ]]; }; then
                resolved_target_home="$current_home"
            fi
        fi
    fi
    if [[ -n "$resolved_target_home" ]]; then
        if [[ "$resolved_target_home" == /* ]] && [[ "$resolved_target_home" != "/" ]]; then
            target_home="${resolved_target_home%/}"
        else
            target_home=""
        fi
    fi

    env_bin="$(_acfs_doctor_system_binary_path env 2>/dev/null || true)"
    bash_bin="$(_acfs_doctor_system_binary_path bash 2>/dev/null || true)"
    if [[ -z "$env_bin" || -z "$bash_bin" ]]; then
        log_error "Unable to locate env/bash for manifest check"
        return 1
    fi

    local system_path_prefix="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"

    case "$run_as" in
        target_user)
            if [[ -z "$target_home" ]] || [[ "$target_home" != /* ]] || [[ "$target_home" == "/" ]]; then
                log_error "Invalid TARGET_HOME for '$target_user': ${target_home:-<empty>} (must be an absolute path and cannot be '/')"
                return 1
            fi
            local target_bin=""
            target_bin="$(_acfs_doctor_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$target_home" 2>/dev/null || true)"
            [[ -n "$target_bin" ]] || target_bin="$target_home/.local/bin"
            if [[ -z "$target_bin" ]] || [[ "$target_bin" != /* ]] || [[ "$target_bin" == "/" ]]; then
                log_error "ACFS_BIN_DIR must be an absolute path and cannot be '/' (got: ${target_bin:-<empty>})"
                return 1
            fi
            local dir=""
            local seen_path=":"
            local target_path_prefix=""
            local -a target_path_entries=()
            for dir in \
                "$target_bin" \
                "$target_home/.local/bin" \
                "$target_home/.acfs/bin" \
                "$target_home/.bun/bin" \
                "$target_home/.cargo/bin" \
                "$target_home/.atuin/bin" \
                "$target_home/go/bin" \
                "$target_home/google-cloud-sdk/bin" \
                "/usr/local/sbin" \
                "/usr/local/bin" \
                "/usr/sbin" \
                "/usr/bin" \
                "/sbin" \
                "/bin" \
                "/snap/bin"; do
                case "$seen_path" in
                    *":$dir:"*) ;;
                    *)
                        target_path_entries+=("$dir")
                        seen_path="${seen_path}${dir}:"
                        ;;
                esac
            done
            target_path_prefix=$(IFS=:; echo "${target_path_entries[*]}")
            target_path="$target_path_prefix${PATH:+:$PATH}"
            if [[ "$(_acfs_doctor_resolve_current_user 2>/dev/null || true)" == "$target_user" ]]; then
                "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" HOME="$target_home" PATH="$target_path" "$bash_bin" -o pipefail -c "$cmd"
                return $?
            fi
            runuser_bin="$(_acfs_doctor_system_binary_path runuser 2>/dev/null || true)"
            if [[ $EUID -eq 0 && -n "$runuser_bin" ]]; then
                "$runuser_bin" -u "$target_user" -- "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" HOME="$target_home" PATH="$target_path" "$bash_bin" -o pipefail -c "$cmd"
                return $?
            fi
            sudo_bin="$(_acfs_doctor_system_binary_path sudo 2>/dev/null || true)"
            if [[ -n "$sudo_bin" ]]; then
                "$sudo_bin" -n -u "$target_user" "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" HOME="$target_home" PATH="$target_path" "$bash_bin" -o pipefail -c "$cmd"
                return $?
            fi
            su_bin="$(_acfs_doctor_system_binary_path su 2>/dev/null || true)"
            if [[ $EUID -eq 0 && -n "$su_bin" ]]; then
                "$su_bin" "$target_user" -c "$(printf '%q' "$env_bin") TARGET_USER=$(printf '%q' "$target_user") TARGET_HOME=$(printf '%q' "$target_home") HOME=$(printf '%q' "$target_home") PATH=$(printf '%q' "$target_path") $(printf '%q' "$bash_bin") -o pipefail -c $(printf '%q' "$cmd")"
                return $?
            fi
            return 1
            ;;
        root)
            if [[ $EUID -eq 0 ]]; then
                if [[ -n "$target_home" ]] && [[ "$target_home" == /* ]] && [[ "$target_home" != "/" ]]; then
                    "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"
                else
                    "$env_bin" TARGET_USER="$target_user" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"
                fi
                return $?
            fi
            sudo_bin="$(_acfs_doctor_system_binary_path sudo 2>/dev/null || true)"
            if [[ -n "$sudo_bin" ]]; then
                if [[ -n "$target_home" ]] && [[ "$target_home" == /* ]] && [[ "$target_home" != "/" ]]; then
                    "$sudo_bin" -n "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"
                else
                    "$sudo_bin" -n "$env_bin" TARGET_USER="$target_user" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"
                fi
                return $?
            fi
            return 1
            ;;
        current|*)
            if [[ -n "$target_home" ]] && [[ "$target_home" == /* ]] && [[ "$target_home" != "/" ]]; then
                "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" "$bash_bin" -o pipefail -c "$cmd"
            else
                "$env_bin" TARGET_USER="$target_user" "$bash_bin" -o pipefail -c "$cmd"
            fi
            ;;
    esac
}

# Run manifest checks that are NOT already covered by bespoke functions.
# Integrates with the standard check() output (JSON/gum/plain) so the results
# are indistinguishable from hand-written checks.  Failed checks include a
# copy-pasteable fix suggestion using `acfs install --only <module>`.
check_manifest_supplemental() {
    [[ "$MANIFEST_CHECKS_LOADED" == "true" ]] || return 0
    [[ ${#MANIFEST_CHECKS[@]} -gt 0 ]] || return 0

    local printed_section=false

    for entry in "${MANIFEST_CHECKS[@]}"; do
        IFS=$'\t' read -r id desc cmd req_flag run_as <<< "$entry"

        # Skip checks already covered by bespoke functions
        _is_bespoke_covered "$id" && continue

        # Print section header on first supplemental check
        if [[ "$printed_section" == "false" ]]; then
            section "Additional Tools (manifest)"
            printed_section=true
        fi

        # Decode printf escapes (\n, \t, \\) embedded by the generator
        cmd="$(printf '%b' "$cmd")"
        run_as="${run_as:-current}"

        # Build a human-readable label from the check command.
        # For most entries the first word is the binary name (curl, lazygit, apr).
        # For shell builtins / operators we fall back to the ID's last segment.
        local tool_name
        tool_name="${cmd%% *}"
        case "$tool_name" in
            test|"["|grep|export|command|bash|sh|cd|systemctl|"[["*)
                tool_name="${id%.[0-9]*}"    # strip trailing .N
                tool_name="${tool_name##*.}" # keep last segment
                ;;
            */*)
                # Path like ~/.bun/bin/bun → basename
                tool_name="${tool_name##*/}"
                ;;
        esac

        # Build per-module fix suggestion for failed/warn checks (bd-31ps.5.2)
        local module_id
        module_id=$(_manifest_module_id "$id")
        local fix
        fix="$(fix_for_module "$module_id")"

        # Execute the check command in the same context the manifest expects.
        if _doctor_run_manifest_check "$run_as" "$cmd" &>/dev/null; then
            check "$id" "$tool_name" "pass" "$desc"
        elif [[ "$req_flag" == "optional" ]]; then
            # Optional tools use "warn" status (not critical failures)
            # Still provide fix suggestion so users know how to install if desired
            check "$id" "$tool_name" "warn" "$desc (optional)" "$fix"
        else
            check "$id" "$tool_name" "fail" "$desc" "$fix"
        fi
    done

    [[ "$printed_section" == "true" ]] && blank_line
}

# ============================================================
# Skipped Tools Display (bead qup)
# ============================================================
# Shows tools the user intentionally skipped during installation.
# These are not failures - they are deliberate choices.

# Load skipped tools from state.json
# Populates SKIPPED_TOOLS_DATA array with "tool:reason" entries
load_skipped_tools() {
    SKIPPED_TOOLS_DATA=()
    local state_file=""
    state_file="$(_acfs_doctor_find_project_path "state.json" 2>/dev/null || true)"

    [[ -f "$state_file" ]] || return 0

    # Use jq if available for reliable parsing
    if command -v jq &>/dev/null; then
        local skipped_json
        skipped_json=$(jq -r '.skipped_tools // empty' "$state_file" 2>/dev/null) || return 0

        # Handle both array format ["tool1","tool2"] and object format {"tool1":"reason"}
        if [[ "$skipped_json" == "["* ]]; then
            # Array format - no reasons stored
            while IFS= read -r tool; do
                [[ -n "$tool" && "$tool" != "null" ]] && SKIPPED_TOOLS_DATA+=("$tool:user choice")
            done < <(jq -r '.skipped_tools[]? // empty' "$state_file" 2>/dev/null)
        elif [[ "$skipped_json" == "{"* ]]; then
            # Object format with reasons
            while IFS= read -r line; do
                [[ -n "$line" ]] && SKIPPED_TOOLS_DATA+=("$line")
            done < <(jq -r '.skipped_tools | to_entries[]? | "\(.key):\(.value)"' "$state_file" 2>/dev/null)
        fi
    else
        # Fallback: basic sed for array format (POSIX-compatible, works on macOS/BSD)
        local skipped
        skipped=$(sed -n 's/.*"skipped_tools"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$state_file" 2>/dev/null | tr -d '", ')
        for tool in $skipped; do
            [[ -n "$tool" ]] && SKIPPED_TOOLS_DATA+=("$tool:user choice")
        done
    fi
}

# Display a skipped tool with [○] indicator
# Usage: check_skipped <id> <label> [reason]
check_skipped() {
    local id="$1"
    local label="$2"
    local reason="${3:-user choice}"

    ((SKIP_COUNT += 1))

    if [[ "$JSON_MODE" == "true" ]]; then
        JSON_CHECKS+=("{\"id\":\"$(json_escape "$id")\",\"label\":\"$(json_escape "$label")\",\"status\":\"skipped\",\"details\":\"$(json_escape "$reason")\",\"fix\":null}")
        return 0
    fi

    if [[ "$HAS_GUM" == "true" ]]; then
        echo "  $(gum style --foreground "$ACFS_MUTED" --bold "○ SKIP") $(gum style --foreground "$ACFS_MUTED" "$label")"
        echo "        $(gum style --foreground "$ACFS_MUTED" --italic "Reason: $reason")"
    else
        echo -e "  ${CYAN}○ SKIP${NC} $label"
        echo -e "        Reason: $reason"
    fi
}

# Show intentionally skipped tools section
show_skipped_tools() {
    load_skipped_tools

    # Skip section if nothing was skipped
    [[ ${#SKIPPED_TOOLS_DATA[@]} -eq 0 ]] && return 0

    section "Intentionally Skipped"

    if [[ "$JSON_MODE" != "true" ]]; then
        if [[ "$HAS_GUM" == "true" ]]; then
            gum style --foreground "$ACFS_MUTED" "  These tools were skipped during installation (not errors)"
        else
            echo -e "  ${CYAN}These tools were skipped during installation (not errors)${NC}"
        fi
        echo ""
    fi

    for entry in "${SKIPPED_TOOLS_DATA[@]}"; do
        local tool="${entry%%:*}"
        local reason="${entry#*:}"
        check_skipped "skipped.$tool" "$tool" "$reason"
    done

    blank_line
}

# ============================================================
# Deep Checks - Functional Tests (bead 01s)
# ============================================================
# These tests go beyond "is the binary installed" to verify
# actual functionality: authentication, connectivity, etc.
#
# Only runs when --deep flag is provided.
# ============================================================

# Deep check counters (separate from main counters for summary)
DEEP_PASS_COUNT=0
DEEP_WARN_COUNT=0
DEEP_FAIL_COUNT=0

# Run all deep/functional checks with formatted output
# Enhanced per bead aqs: Adds counters and summary
# Enhanced per bead lz1: Adds timing
# Usage: run_deep_checks
deep_check_optional_probe() {
    local id="$1"
    local label="$2"
    local binary="$3"
    local fix="$4"
    shift 4
    local runtime_home=""
    local binary_path=""
    local runtime_path=""
    runtime_home="$(doctor_runtime_home)"
    binary_path="$(doctor_binary_path "$binary" 2>/dev/null || true)"
    runtime_path="$(doctor_runtime_path 2>/dev/null || true)"

    if [[ -z "$binary_path" || -z "$runtime_path" ]]; then
        check "$id" "$label" "warn" "not installed" "$fix"
        return 0
    fi

    local cache_key="${id//./_}"
    local cached_result=""
    if cached_result=$(get_cached_result "$cache_key"); then
        check "$id" "$label" "pass" "$cached_result (cached)"
        return 0
    fi

    local cmd=""
    local output=""
    local status=0
    local summary=""
    local detail=""
    local last_timeout=false
    local env_bin=""
    local bash_bin=""

    env_bin="$(_acfs_doctor_system_binary_path env 2>/dev/null || true)"
    bash_bin="$(_acfs_doctor_system_binary_path bash 2>/dev/null || true)"
    if [[ -z "$env_bin" || -z "$bash_bin" ]]; then
        check "$id" "$label" "warn" "env/bash unavailable" "$fix"
        return 0
    fi

    for cmd in "$@"; do
        output=$(run_with_timeout "$DEEP_CHECK_TIMEOUT" "$label via $cmd" "$env_bin" HOME="$runtime_home" PATH="$runtime_path" "$bash_bin" -o pipefail -c "$cmd")
        status=$?

        if ((status == 0)); then
            detail="$(printf '%s\n' "$output" | head -n 1)"
            if [[ -n "$detail" ]]; then
                summary="$cmd: ${detail:0:120}"
            else
                summary="$cmd"
            fi
            cache_result "$cache_key" "$summary"
            check "$id" "$label" "pass" "$summary"
            return 0
        fi

        if ((status == 124)); then
            last_timeout=true
            detail="timed out running: $cmd"
            continue
        fi

        if [[ -z "$detail" ]]; then
            detail="$(printf '%s\n' "$output" | head -n 1)"
            [[ -n "$detail" ]] || detail="command failed: $cmd"
        fi
    done

    if [[ "$last_timeout" == "true" ]]; then
        check_with_timeout_status "$id" "$label" "timeout" "$detail" "$fix"
    else
        check "$id" "$label" "warn" "$detail" "$fix"
    fi
}

deep_check_stack_tools() {
    deep_check_optional_probe \
        "deep.stack.rch" \
        "RCH operational probe" \
        "rch" \
        "Run: rch doctor --fix" \
        "rch doctor" \
        "rch status"

    deep_check_optional_probe \
        "deep.stack.pt" \
        "Process Triage operational probe" \
        "pt" \
        "Run: pt check" \
        "pt check" \
        "pt doctor" \
        "pt --help"

    deep_check_optional_probe \
        "deep.stack.fsfs" \
        "FrankenSearch operational probe" \
        "fsfs" \
        "timed out running: fsfs status" \
        "fsfs status" \
        "fsfs version" \
        "fsfs --help"

    deep_check_optional_probe \
        "deep.stack.sbh" \
        "Storage Ballast Helper operational probe" \
        "sbh" \
        "Run: sbh check" \
        "sbh check" \
        "sbh status" \
        "sbh --help"

    deep_check_optional_probe \
        "deep.stack.casr" \
        "CASR provider probe" \
        "casr" \
        "Run: casr providers" \
        "casr providers" \
        "casr list" \
        "casr --help"

    deep_check_optional_probe \
        "deep.stack.dsr" \
        "DSR operational probe" \
        "dsr" \
        "Run: dsr check --all" \
        "dsr doctor" \
        "dsr check --all" \
        "dsr --help"

    deep_check_optional_probe \
        "deep.stack.ru" \
        "Repo Updater operational probe" \
        "ru" \
        "Run: ru doctor" \
        "ru doctor" \
        "ru list" \
        "ru --help"

    deep_check_optional_probe \
        "deep.stack.asb" \
        "Agent Settings Backup operational probe" \
        "asb" \
        "test -d \"$HOME/.asb\" && asb list" \
        "asb list" \
        "asb help"

    deep_check_optional_probe \
        "deep.stack.pcr" \
        "Post-Compact Reminder operational probe" \
        "claude-post-compact-reminder" \
        "Reinstall PCR or verify Claude settings registration" \
        "printf '{\"session_id\":\"doctor\",\"source\":\"compact\"}\n' | claude-post-compact-reminder"
}

run_deep_checks() {
    section "Deep Checks (Functional Tests)"

    # Track total deep check time (bead lz1)
    local start_time
    start_time=$(date +%s)

    if [[ "$JSON_MODE" != "true" ]]; then
        # Log cache status (bead lz1)
        local cache_status=""
        if [[ "$NO_CACHE" == "true" ]]; then
            cache_status=" (cache disabled)"
        fi
        if [[ "$HAS_GUM" == "true" ]]; then
            gum style --foreground "$ACFS_MUTED" "  Running functional tests...$cache_status"
        else
            echo -e "  ${CYAN}Running functional tests...$cache_status${NC}"
        fi
        echo ""
    fi

    # Capture counts before deep checks to calculate deep-only stats
    local pre_pass=$PASS_COUNT
    local pre_warn=$WARN_COUNT
    local pre_fail=$FAIL_COUNT

    # Agent authentication checks
    deep_check_agent_auth

    # Database connectivity checks
    deep_check_database

    # Cloud CLI checks
    deep_check_cloud

    # tmux responsiveness checks (GitHub issue #20: NTM timeouts / slow tmux)
    deep_check_tmux_performance

    # Network health checks (bead bd-31ps.7.2)
    deep_check_network

    # Notification (ntfy.sh) connectivity check (GitHub issue #131)
    deep_check_notifications

    # Stack tool functional probes for newly integrated tools
    deep_check_stack_tools

    # Calculate deep check specific counts
    DEEP_PASS_COUNT=$((PASS_COUNT - pre_pass))
    DEEP_WARN_COUNT=$((WARN_COUNT - pre_warn))
    DEEP_FAIL_COUNT=$((FAIL_COUNT - pre_fail))
    local deep_total=$((DEEP_PASS_COUNT + DEEP_WARN_COUNT + DEEP_FAIL_COUNT))

    # Calculate elapsed time (bead lz1)
    local end_time elapsed_time
    end_time=$(date +%s)
    elapsed_time=$((end_time - start_time))
    DEEP_CHECK_ELAPSED=$elapsed_time  # Export for JSON output

    # Print deep checks summary
    if [[ "$JSON_MODE" != "true" ]]; then
        echo ""
        if [[ "$HAS_GUM" == "true" ]]; then
            local summary_text=""
            if [[ $DEEP_FAIL_COUNT -eq 0 ]]; then
                summary_text="$(gum style --foreground "$ACFS_SUCCESS" --bold "$DEEP_PASS_COUNT/$deep_total") functional tests passed"
                [[ $DEEP_WARN_COUNT -gt 0 ]] && summary_text="$summary_text $(gum style --foreground "$ACFS_WARNING" "($DEEP_WARN_COUNT warnings)")"
            else
                summary_text="$(gum style --foreground "$ACFS_ERROR" --bold "$DEEP_PASS_COUNT/$deep_total") functional tests passed"
                summary_text="$summary_text $(gum style --foreground "$ACFS_ERROR" "($DEEP_FAIL_COUNT failed)")"
            fi
            echo "  $summary_text $(gum style --foreground "$ACFS_MUTED" "in ${elapsed_time}s")"
        else
            if [[ $DEEP_FAIL_COUNT -eq 0 ]]; then
                echo -e "  ${GREEN}$DEEP_PASS_COUNT/$deep_total${NC} functional tests passed in ${elapsed_time}s"
            else
                echo -e "  ${RED}$DEEP_PASS_COUNT/$deep_total${NC} functional tests passed (${RED}$DEEP_FAIL_COUNT failed${NC}) in ${elapsed_time}s"
            fi
        fi
    fi

    blank_line
}

# Deep check: Agent authentication
# Enhanced per bead 325: Check config files, API keys, and low-cost API checks
deep_check_agent_auth() {
    check_claude_auth
    check_codex_auth
    check_gemini_auth
}

# check_claude_auth - Thorough Claude Code authentication check
# Returns via check(): pass (auth OK), warn (partial/skipped), fail (auth broken)
# Related: bead 325
# Fixed: Check correct credentials file (.credentials.json, not config.json)
# Fixed: Removed non-existent --print-system-info flag
check_claude_auth() {
    local auth_home=""
    auth_home="$(doctor_runtime_home)"

    local claude_bin=""
    claude_bin="$(doctor_binary_path claude 2>/dev/null || true)"
    if [[ -z "$claude_bin" ]]; then
        check "deep.agent.claude_auth" "Claude Code" "warn" "not installed" "acfs update --force --agents-only"
        return
    fi

    # Check if binary works
    if ! "$claude_bin" --version &>/dev/null; then
        check "deep.agent.claude_auth" "Claude Code auth" "fail" "binary error" "Reinstall: acfs update --force --agents-only"
        return
    fi

    # Check for credentials file (indicates previous auth)
    # Claude Code stores OAuth credentials in ~/.claude/.credentials.json (note leading dot)
    local creds_file="$auth_home/.claude/.credentials.json"
    if [[ ! -f "$creds_file" ]]; then
        check "deep.agent.claude_auth" "Claude Code auth" "warn" "not authenticated" "Run: claude to authenticate"
        return
    fi

    # Verify OAuth token exists in credentials file
    local has_token=false
    if command -v jq &>/dev/null; then
        # Use jq for reliable JSON parsing
        if json_file_has_usable_jq_value "$creds_file" '.claudeAiOauth.accessToken // empty | strings'; then
            has_token=true
        fi
    else
        # Fallback: require a non-empty string token, not just key presence.
        if json_file_has_usable_string_key "$creds_file" "accessToken"; then
            has_token=true
        fi
    fi

    if [[ "$has_token" == "true" ]]; then
        check "deep.agent.claude_auth" "Claude Code auth" "pass" "OAuth authenticated"
    else
        check "deep.agent.claude_auth" "Claude Code auth" "warn" "credentials file exists but no valid token" "Run: claude to re-authenticate"
    fi
}

# check_codex_auth - Thorough Codex CLI authentication check
# Codex CLI uses OAuth (ChatGPT accounts), NOT OPENAI_API_KEY environment variable.
# Token location: ~/.codex/auth.json (or $CODEX_HOME/auth.json)
# Returns via check(): pass (auth OK), warn (partial/skipped), fail (auth broken)
# Related: bead 325, ua5 (Codex auth documentation fix)
check_codex_auth() {
    local auth_home=""
    auth_home="$(doctor_runtime_home)"

    local codex_bin=""
    codex_bin="$(doctor_binary_path codex 2>/dev/null || true)"
    if [[ -z "$codex_bin" ]]; then
        check "deep.agent.codex_auth" "Codex CLI" "warn" "not installed" "bun install -g --trust @openai/codex@latest"
        return
    fi

    # Check if binary works
    if ! "$codex_bin" --version &>/dev/null; then
        check "deep.agent.codex_auth" "Codex CLI auth" "fail" "binary error" "Reinstall: bun install -g --trust @openai/codex@latest"
        return
    fi

    # Determine auth.json location (respects CODEX_HOME if set)
    local auth_file="${CODEX_HOME:-$auth_home/.codex}/auth.json"

    # Check if auth.json exists
    if [[ ! -f "$auth_file" ]]; then
        check "deep.agent.codex_auth" "Codex CLI auth" "warn" "not authenticated" "Run: codex login --device-auth"
        return
    fi

    # Check for OAuth tokens (primary auth method)
    # auth.json structure: { "tokens": { "access_token": "..." }, "OPENAI_API_KEY": null|"..." }
    local has_oauth=false
    local has_api_key=false

    # Check for OAuth tokens.access_token (preferred)
    if command -v jq &>/dev/null; then
        # Use jq if available for reliable JSON parsing
        if json_file_has_usable_jq_value "$auth_file" '[.tokens.access_token, .access_token, .accessToken] | .[]? | strings'; then
            has_oauth=true
        fi
        # Check for legacy API key in auth.json
        if json_file_has_usable_jq_value "$auth_file" '.OPENAI_API_KEY // empty | strings'; then
            has_api_key=true
        fi
    else
        # Fallback: require non-empty strings, not just key presence.
        if json_file_has_usable_string_key "$auth_file" "access_token" "accessToken"; then
            has_oauth=true
        fi
        if json_file_has_usable_string_key "$auth_file" "OPENAI_API_KEY"; then
            has_api_key=true
        fi
    fi

    if [[ "$has_oauth" == "true" ]]; then
        check "deep.agent.codex_auth" "Codex CLI auth" "pass" "OAuth authenticated (ChatGPT account)"
    elif [[ "$has_api_key" == "true" ]]; then
        check "deep.agent.codex_auth" "Codex CLI auth" "pass" "API key authenticated (pay-as-you-go)"
    else
        check "deep.agent.codex_auth" "Codex CLI auth" "warn" "not authenticated" "Run: codex login --device-auth"
    fi
}

# check_gemini_auth - Thorough Gemini CLI authentication check
# Returns via check(): pass (auth OK), warn (partial/skipped), fail (auth broken)
# Related: bead 325
# Fixed: Check actual Gemini CLI credential files (oauth_creds.json, google_accounts.json)
check_gemini_auth() {
    local auth_home=""
    auth_home="$(doctor_runtime_home)"

    local gemini_bin=""
    gemini_bin="$(doctor_binary_path gemini 2>/dev/null || true)"
    if [[ -z "$gemini_bin" ]]; then
        check "deep.agent.gemini_auth" "Gemini CLI" "warn" "not installed" "bun install -g --trust @google/gemini-cli@latest"
        return
    fi

    # Check if binary works
    if ! "$gemini_bin" --version &>/dev/null; then
        check "deep.agent.gemini_auth" "Gemini CLI auth" "fail" "binary error" "Reinstall: bun install -g --trust @google/gemini-cli@latest"
        return
    fi

    local gemini_home="${GEMINI_CLI_HOME:-$auth_home}"
    local shell_config_files=()
    mapfile -t shell_config_files < <(default_auth_config_files)
    local gemini_config_files=(
        "$gemini_home/.gemini/.env"
        "${shell_config_files[@]}"
    )
    if get_configured_secret "GEMINI_API_KEY" "${gemini_config_files[@]}" >/dev/null; then
        check "deep.agent.gemini_auth" "Gemini CLI auth" "pass" "via GEMINI_API_KEY"
        return
    fi
    if configured_truthy_value "GOOGLE_GENAI_USE_VERTEXAI" "${gemini_config_files[@]}"; then
        if get_configured_secret "GOOGLE_API_KEY" "${gemini_config_files[@]}" >/dev/null; then
            check "deep.agent.gemini_auth" "Gemini CLI auth" "pass" "via GOOGLE_API_KEY (Vertex AI)"
            return
        fi

        local vertex_project=""
        local vertex_location=""
        local service_account_path=""
        local gcloud_bin=""
        vertex_project="$(get_configured_value "GOOGLE_CLOUD_PROJECT" "${gemini_config_files[@]}" || get_configured_value "GOOGLE_CLOUD_PROJECT_ID" "${gemini_config_files[@]}" || true)"
        vertex_location="$(get_configured_value "GOOGLE_CLOUD_LOCATION" "${gemini_config_files[@]}" || true)"
        service_account_path="$(get_configured_value "GOOGLE_APPLICATION_CREDENTIALS" "${gemini_config_files[@]}" || true)"
        gcloud_bin="$(doctor_binary_path gcloud 2>/dev/null || true)"

        if [[ -n "$vertex_project" && -n "$vertex_location" ]]; then
            if [[ -n "$service_account_path" && -f "$service_account_path" ]]; then
                check "deep.agent.gemini_auth" "Gemini CLI auth" "pass" "via GOOGLE_APPLICATION_CREDENTIALS (Vertex AI)"
                return
            fi
            if [[ -n "$gcloud_bin" ]] && timeout 5 "$gcloud_bin" auth application-default print-access-token >/dev/null 2>&1; then
                check "deep.agent.gemini_auth" "Gemini CLI auth" "pass" "via gcloud ADC (Vertex AI)"
                return
            fi
        fi
    fi

    # Gemini CLI also stores browser-login state under ~/.gemini/ (or $GEMINI_CLI_HOME/.gemini).
    local google_accounts_file="$gemini_home/.gemini/google_accounts.json"
    local oauth_creds_file="$gemini_home/.gemini/oauth_creds.json"
    local found_auth=false

    if command -v jq &>/dev/null; then
        local gemini_active=""
        local gemini_access_token=""
        local gemini_refresh_token=""

        if [[ -f "$google_accounts_file" ]]; then
            gemini_active="$(jq -r '.active // empty' "$google_accounts_file" 2>/dev/null || true)"
        fi
        if [[ -f "$oauth_creds_file" ]]; then
            gemini_access_token="$(jq -r '.access_token // empty' "$oauth_creds_file" 2>/dev/null || true)"
            gemini_refresh_token="$(jq -r '.refresh_token // empty' "$oauth_creds_file" 2>/dev/null || true)"
        fi

        if has_usable_secret "$gemini_active" || has_usable_secret "$gemini_access_token" || has_usable_secret "$gemini_refresh_token"; then
            found_auth=true
        fi
    else
        if json_file_has_usable_string_key "$google_accounts_file" "active"; then
            found_auth=true
        fi
        if [[ "$found_auth" == "false" ]] && json_file_has_usable_string_key "$oauth_creds_file" "access_token" "refresh_token"; then
            found_auth=true
        fi
    fi

    if [[ "$found_auth" == "true" ]]; then
        check "deep.agent.gemini_auth" "Gemini CLI auth" "pass" "authenticated"
    else
        check "deep.agent.gemini_auth" "Gemini CLI auth" "warn" "not authenticated" "Set GEMINI_API_KEY (or Vertex AI env vars), then run gemini"
    fi
}

# Deep check: Database connectivity
# Enhanced per bead azw: PostgreSQL connection and role checks
deep_check_database() {
    check_postgres_connection
    check_postgres_role
}

# check_postgres_connection - Test PostgreSQL connectivity
# Related: bead azw
check_postgres_connection() {
    local psql_bin=""

    # Skip if not installed
    if ! psql_bin="$(doctor_binary_path psql 2>/dev/null || true)" || [[ -z "$psql_bin" ]]; then
        check "deep.db.postgres_connect" "PostgreSQL connection" "warn" "psql not installed" "sudo apt install postgresql-client"
        return
    fi

    # Try to connect to local postgres (5 second timeout, no password prompt)
    # Use -w to avoid password prompts (would hang)
    if timeout 5 "$psql_bin" -w -h localhost -U postgres -c 'SELECT 1' &>/dev/null; then
        check "deep.db.postgres_connect" "PostgreSQL connection" "pass" "localhost:5432"
    elif timeout 5 "$psql_bin" -w -h /var/run/postgresql -U postgres -c 'SELECT 1' &>/dev/null; then
        check "deep.db.postgres_connect" "PostgreSQL connection" "pass" "unix socket"
    else
        # Try connecting as current user
        if timeout 5 "$psql_bin" -w -c 'SELECT 1' &>/dev/null; then
            check "deep.db.postgres_connect" "PostgreSQL connection" "pass" "current user"
        else
            check "deep.db.postgres_connect" "PostgreSQL connection" "warn" "connection failed" "sudo systemctl status postgresql"
        fi
    fi
}

# check_postgres_role - Verify target user role exists in PostgreSQL
# Related: bead azw
# Fixed: Try current user first before postgres user (pg_roles is readable by any authenticated user)
# Fixed: Provide actionable fix message (createuser, not systemctl status)
# Fixed: Use bash variable substitution with validated input (:'var' syntax is unreliable across psql versions)
check_postgres_role() {
    local psql_bin=""
    psql_bin="$(doctor_binary_path psql 2>/dev/null || true)"
    if [[ -z "$psql_bin" ]]; then
        return  # Already reported in connection check
    fi

    # Validate target user - PostgreSQL identifiers must match this pattern
    # SECURITY: Prevents SQL injection by validating input before use
    local target_user="${TARGET_USER:-}"
    if [[ -z "$target_user" ]]; then
        check "deep.db.postgres_role" "PostgreSQL role check" "warn" "TARGET_USER not set"
        return
    fi
    if [[ ! "$target_user" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        check "deep.db.postgres_role" "PostgreSQL role check" "fail" "invalid username format"
        return
    fi

    # Try to check if target user role exists
    # pg_roles view is readable by any authenticated user - no superuser required
    # SECURITY: target_user is validated above with regex, safe for bash substitution
    local role_check
    local connect_success=false
    local sql_query="SELECT 1 FROM pg_roles WHERE rolname='$target_user'"

    # Try connecting as current user first (mirrors check_postgres_connection behavior)
    # This works when pg_hba.conf allows peer auth for local users
    if role_check=$(timeout 5 "$psql_bin" -w -tAc "$sql_query" 2>/dev/null) && [[ "$role_check" == "1" ]]; then
        connect_success=true
    # Try localhost with postgres user as fallback
    elif role_check=$(timeout 5 "$psql_bin" -w -h localhost -U postgres -tAc "$sql_query" 2>/dev/null) && [[ "$role_check" == "1" ]]; then
        connect_success=true
    # Try unix socket with postgres user as last resort
    elif role_check=$(timeout 5 "$psql_bin" -w -h /var/run/postgresql -U postgres -tAc "$sql_query" 2>/dev/null) && [[ "$role_check" == "1" ]]; then
        connect_success=true
    fi

    if [[ "$connect_success" == "true" ]]; then
        check "deep.db.postgres_role" "PostgreSQL $target_user role" "pass" "role exists"
    else
        # Connection failed or role missing - provide actionable fix
        check "deep.db.postgres_role" "PostgreSQL $target_user role" "warn" "role missing or connection failed" "sudo -u postgres createuser -s $target_user"
    fi
}

# Deep check: Cloud CLI authentication
# Enhanced per bead azw: Thorough cloud CLI auth checks with proper status handling
# All checks use 10 second timeout to prevent hanging on network issues
deep_check_cloud() {
    check_vault_configured
    check_gh_auth
    check_wrangler_auth
    check_supabase_auth
    check_vercel_auth
}

# Deep check: tmux responsiveness
# Related: GitHub issue #20 (NTM: "context deadline exceeded")
deep_check_tmux_performance() {
    local tmux_bin=""

    if ! tmux_bin="$(doctor_binary_path tmux 2>/dev/null || true)" || [[ -z "$tmux_bin" ]]; then
        check "deep.tmux.present" "tmux responsiveness" "warn" "tmux not installed" "sudo apt install tmux"
        return
    fi

    local timeout_secs=5
    local warn_threshold_ms=1000
    local hint="If NTM shows 'context deadline exceeded', tmux may be slow. Try running NTM outside of tmux (fresh SSH session). Diagnose with: time tmux list-sessions; time tmux list-panes -a; ls -la /tmp/tmux-*."
    if [[ -n "${TMUX:-}" ]]; then
        hint="You are currently inside tmux. If NTM is timing out, try running it outside tmux (new SSH session). Diagnose with: time tmux list-sessions; time tmux list-panes -a; ls -la /tmp/tmux-*."
    fi

    _deep_check_tmux_cmd() {
        local id="$1"
        local label="$2"
        shift 2

        local start_ns end_ns elapsed_ms
        start_ns=$(date +%s%N 2>/dev/null || echo "")

        local output status
        output=$(run_with_timeout "$timeout_secs" "$label" "$@")
        status=$?

        end_ns=$(date +%s%N 2>/dev/null || echo "")
        if [[ "$start_ns" =~ ^[0-9]+$ ]] && [[ "$end_ns" =~ ^[0-9]+$ ]]; then
            elapsed_ms=$(((end_ns - start_ns) / 1000000))
        else
            elapsed_ms=-1
        fi

        if ((status == 124)); then
            check_with_timeout_status "$id" "$label" "timeout" "timed out after ${timeout_secs}s" "$hint"
            return 0
        fi

        if ((status != 0)); then
            if echo "$output" | grep -qiE "no server running|failed to connect to server"; then
                check "$id" "$label (no server)" "pass" "no tmux server running"
                return 0
            fi

            local first_line=""
            first_line="$(printf '%s\n' "$output" | head -n 1)"
            [[ -z "$first_line" ]] && first_line="tmux command failed"
            check "$id" "$label" "warn" "$first_line" "$hint"
            return 0
        fi

        local label_with_timing="$label"
        if ((elapsed_ms >= 0)); then
            label_with_timing="$label (${elapsed_ms}ms)"
        fi

        if ((elapsed_ms >= 0)) && ((elapsed_ms >= warn_threshold_ms)); then
            check "$id" "$label_with_timing" "warn" "slow tmux" "$hint"
        else
            check "$id" "$label_with_timing" "pass" "ok"
        fi
        return 0
    }

    _deep_check_tmux_cmd "deep.tmux.list_sessions" "tmux list-sessions responsiveness" "$tmux_bin" list-sessions
    _deep_check_tmux_cmd "deep.tmux.list_panes" "tmux list-panes -a responsiveness" "$tmux_bin" list-panes -a -F '#{pane_id}'
}

# Deep check: Network health
# Related: bead bd-31ps.7.2
# Exposes preflight-style network checks via doctor --deep for ongoing verification.
# Results are WARN (non-fatal) since network issues may be transient.
deep_check_network() {
    check_network_dns
    check_network_github
    check_network_apt_mirror
}

# check_network_dns - DNS resolution check for critical hosts
# Related: bead bd-31ps.7.2
# Tests DNS resolution for hosts required by the installer
check_network_dns() {
    local hosts=(
        "github.com"
        "raw.githubusercontent.com"
    )
    local dns_failures=()
    local dns_ok=true

    for host in "${hosts[@]}"; do
        # Try multiple resolution methods (dig, host, getent)
        local resolved=false
        local dig_bin=""
        local host_bin=""
        local getent_bin=""
        local timeout_bin=""
        local grep_bin=""
        dig_bin="$(_acfs_doctor_system_binary_path dig 2>/dev/null || true)"
        host_bin="$(_acfs_doctor_system_binary_path host 2>/dev/null || true)"
        getent_bin="$(_acfs_doctor_system_binary_path getent 2>/dev/null || true)"
        timeout_bin="$(_acfs_doctor_system_binary_path timeout 2>/dev/null || true)"
        grep_bin="$(_acfs_doctor_system_binary_path grep 2>/dev/null || true)"
        if [[ -n "$dig_bin" && -n "$grep_bin" ]]; then
            if "$dig_bin" +short +time=5 +tries=1 "$host" 2>/dev/null | "$grep_bin" -qE '^[0-9]'; then
                resolved=true
            fi
        fi
        if [[ "$resolved" == "false" && -n "$host_bin" && -n "$timeout_bin" ]]; then
            if "$timeout_bin" 5 "$host_bin" "$host" &>/dev/null; then
                resolved=true
            fi
        fi
        if [[ "$resolved" == "false" && -n "$getent_bin" && -n "$timeout_bin" ]]; then
            if "$timeout_bin" 5 "$getent_bin" hosts "$host" &>/dev/null; then
                resolved=true
            fi
        fi

        if [[ "$resolved" == "false" ]]; then
            dns_failures+=("$host")
            dns_ok=false
        fi
    done

    if [[ "$dns_ok" == "true" ]]; then
        check "deep.network.dns" "DNS resolution" "pass" "all hosts resolved"
    else
        local failed_list
        failed_list=$(IFS=", "; echo "${dns_failures[*]}")
        check "deep.network.dns" "DNS resolution" "warn" "failed: $failed_list" "Check /etc/resolv.conf or network settings"
    fi
}

# check_network_github - GitHub connectivity check
# Related: bead bd-31ps.7.2
# Tests HTTP(S) connectivity to GitHub (critical for installer downloads)
check_network_github() {
    local curl_bin=""
    curl_bin="$(_acfs_doctor_system_binary_path curl 2>/dev/null || true)"
    if [[ -z "$curl_bin" ]]; then
        check "deep.network.github" "GitHub connectivity" "warn" "curl not installed"
        return
    fi

    # Test basic HTTPS connectivity to GitHub
    local http_status
    http_status=$("$curl_bin" -sL --max-time 10 --connect-timeout 5 -o /dev/null -w "%{http_code}" "https://github.com" 2>/dev/null) || http_status="000"

    if [[ "$http_status" == "200" ]] || [[ "$http_status" == "301" ]] || [[ "$http_status" == "302" ]]; then
        check "deep.network.github" "GitHub connectivity" "pass" "github.com reachable (HTTP $http_status)"
    elif [[ "$http_status" == "000" ]]; then
        check "deep.network.github" "GitHub connectivity" "warn" "connection failed" "Check network/firewall settings"
    else
        check "deep.network.github" "GitHub connectivity" "warn" "HTTP $http_status" "Unexpected response; check proxy settings"
    fi

    # Also test raw.githubusercontent.com (used for script downloads)
    http_status=$("$curl_bin" -sL --max-time 10 --connect-timeout 5 -o /dev/null -w "%{http_code}" "https://raw.githubusercontent.com" 2>/dev/null) || http_status="000"

    if [[ "$http_status" == "200" ]] || [[ "$http_status" == "400" ]]; then
        # Note: raw.githubusercontent.com returns 400 on bare request, which is expected
        check "deep.network.github_raw" "GitHub raw content" "pass" "raw.githubusercontent.com reachable"
    elif [[ "$http_status" == "000" ]]; then
        check "deep.network.github_raw" "GitHub raw content" "warn" "connection failed" "Check network/firewall settings"
    else
        check "deep.network.github_raw" "GitHub raw content" "warn" "HTTP $http_status" "Unexpected response"
    fi
}

# check_network_apt_mirror - APT mirror reachability check
# Related: bead bd-31ps.7.2
# Tests connectivity to the configured APT mirror
check_network_apt_mirror() {
    local curl_bin=""
    curl_bin="$(_acfs_doctor_system_binary_path curl 2>/dev/null || true)"
    if [[ -z "$curl_bin" ]]; then
        return  # Already warned in github check
    fi

    # Detect the primary APT mirror from sources.list
    local mirror_url=""
    if [[ -f /etc/apt/sources.list ]]; then
        mirror_url=$(grep -m1 "^deb http" /etc/apt/sources.list 2>/dev/null | awk '{print $2}' | sed 's|/ubuntu.*||') || true
    fi
    if [[ -z "$mirror_url" ]] && [[ -d /etc/apt/sources.list.d ]]; then
        mirror_url=$(grep -rh "^deb http" /etc/apt/sources.list.d/ 2>/dev/null | head -1 | awk '{print $2}' | sed 's|/ubuntu.*||') || true
    fi

    if [[ -z "$mirror_url" ]]; then
        check "deep.network.apt_mirror" "APT mirror" "warn" "could not detect mirror URL"
        return
    fi

    # Test mirror reachability
    local http_status
    http_status=$("$curl_bin" -sL --max-time 10 --connect-timeout 5 -o /dev/null -w "%{http_code}" "${mirror_url}/dists/" 2>/dev/null) || http_status="000"

    local mirror_host="${mirror_url#http*://}"
    mirror_host="${mirror_host%%/*}"

    if [[ "$http_status" == "200" ]] || [[ "$http_status" == "301" ]]; then
        check "deep.network.apt_mirror" "APT mirror" "pass" "$mirror_host reachable"
    elif [[ "$http_status" == "000" ]]; then
        check "deep.network.apt_mirror" "APT mirror" "warn" "$mirror_host unreachable" "Check /etc/apt/sources.list or network"
    else
        check "deep.network.apt_mirror" "APT mirror" "warn" "HTTP $http_status from $mirror_host" "May need to switch mirrors"
    fi
}

# deep_check_notifications - Verify ntfy.sh notification configuration and connectivity
# Related: GitHub issue #131
deep_check_notifications() {
    local runtime_home=""
    runtime_home="$(doctor_runtime_home)"
    local config_file="${runtime_home}/.config/acfs/config.yaml"
    local enabled="" topic="" server=""

    # Read config (same logic as notify.sh)
    if [[ -f "$config_file" ]]; then
        enabled=$(grep -E '^\s*ntfy_enabled\s*:' "$config_file" 2>/dev/null | head -1 | \
                  sed -E 's/^\s*ntfy_enabled\s*:\s*//; s/^["'"'"']//; s/["'"'"']$//' | \
                  sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true)
        topic=$(grep -E '^\s*ntfy_topic\s*:' "$config_file" 2>/dev/null | head -1 | \
                sed -E 's/^\s*ntfy_topic\s*:\s*//; s/^["'"'"']//; s/["'"'"']$//' | \
                sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true)
        server=$(grep -E '^\s*ntfy_server\s*:' "$config_file" 2>/dev/null | head -1 | \
                 sed -E 's/^\s*ntfy_server\s*:\s*//; s/^["'"'"']//; s/["'"'"']$//' | \
                 sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true)
    fi

    # Allow env overrides
    enabled="${ACFS_NTFY_ENABLED:-$enabled}"
    topic="${ACFS_NTFY_TOPIC:-$topic}"
    server="${ACFS_NTFY_SERVER:-$server}"
    server="${server:-https://ntfy.sh}"

    # Check configuration state
    if [[ "$enabled" != "true" ]]; then
        check "deep.notifications.ntfy" "ntfy.sh notifications" "warn" "not enabled" "acfs notifications enable"
        return
    fi

    if [[ -z "$topic" ]]; then
        check "deep.notifications.ntfy" "ntfy.sh notifications" "warn" "enabled but no topic set" "acfs notifications enable"
        return
    fi

    # Topic and enabled are set -- test server connectivity
    local curl_bin=""
    curl_bin="$(_acfs_doctor_system_binary_path curl 2>/dev/null || true)"
    if [[ -z "$curl_bin" ]]; then
        check "deep.notifications.ntfy" "ntfy.sh notifications" "warn" "curl not available" "apt install curl"
        return
    fi

    # HEAD request against the server health endpoint (lightweight)
    local http_code
    http_code=$("$curl_bin" -sL --max-time 5 --connect-timeout 3 -o /dev/null -w "%{http_code}" "${server}/v1/health" 2>/dev/null) || http_code="000"

    if [[ "$http_code" =~ ^2 ]]; then
        check "deep.notifications.ntfy" "ntfy.sh notifications" "pass" "enabled, server reachable (${server})"
    elif [[ "$http_code" == "000" ]]; then
        check "deep.notifications.ntfy" "ntfy.sh notifications" "warn" "server unreachable (${server})" "Check network or acfs notifications set-server <url>"
    else
        check "deep.notifications.ntfy" "ntfy.sh notifications" "warn" "server returned HTTP ${http_code}" "Check server URL: ${server}"
    fi
}

# check_vault_configured - Check if Vault is configured and reachable
# Related: bead azw
check_vault_configured() {
    local auth_home=""
    local vault_bin=""
    auth_home="$(doctor_runtime_home)"

    # Skip if not installed
    if ! vault_bin="$(doctor_binary_path vault 2>/dev/null || true)" || [[ -z "$vault_bin" ]]; then
        check "deep.cloud.vault_status" "Vault" "warn" "not installed" "Install from https://www.vaultproject.io/"
        return
    fi

    # Check if VAULT_ADDR is set (required for vault to work)
    if [[ -z "${VAULT_ADDR:-}" ]]; then
        # Check common config locations
        if _acfs_doctor_shell_has_active_assignment "$auth_home/.zshrc.local" "VAULT_ADDR"; then
            check "deep.cloud.vault_config" "Vault config" "pass" "VAULT_ADDR in ~/.zshrc.local"
        else
            check "deep.cloud.vault_config" "Vault config" "warn" "VAULT_ADDR not set" "export VAULT_ADDR=https://your-vault-server:8200"
        fi
        return
    fi

    # VAULT_ADDR is set, try to connect
    if timeout 10 "$vault_bin" status &>/dev/null; then
        check "deep.cloud.vault_status" "Vault status" "pass" "connected to $VAULT_ADDR"
    else
        check "deep.cloud.vault_status" "Vault status" "warn" "not reachable" "Check VAULT_ADDR and network"
    fi
}

# check_gh_auth - GitHub CLI authentication check
# Related: bead azw
# Enhanced: Caching support (bead lz1)
check_gh_auth() {
    local gh_bin=""

    if ! gh_bin="$(doctor_binary_path gh 2>/dev/null || true)" || [[ -z "$gh_bin" ]]; then
        check "deep.cloud.gh_auth" "GitHub CLI" "warn" "not installed" "sudo apt install gh"
        return
    fi

    # Try cache first for auth status (bead lz1)
    local cached_result
    if cached_result=$(get_cached_result "gh_auth"); then
        check "deep.cloud.gh_auth" "GitHub CLI auth" "pass" "$cached_result (cached)"
        return
    fi

    # Run with timeout
    local result
    result=$(run_with_timeout "$DEEP_CHECK_TIMEOUT" "GitHub CLI auth" "$gh_bin" auth status 2>&1)
    local status=$?

    if ((status == 124)); then
        check_with_timeout_status "deep.cloud.gh_auth" "GitHub CLI auth" "timeout" "check timed out" "Check network, then: gh auth login"
    elif ((status == 0)); then
        # Get the authenticated user for more detail
        local gh_user
        gh_user=$(timeout 5 "$gh_bin" api user --jq '.login' 2>/dev/null) || gh_user="authenticated"
        cache_result "gh_auth" "$gh_user"
        check "deep.cloud.gh_auth" "GitHub CLI auth" "pass" "$gh_user"
    else
        check "deep.cloud.gh_auth" "GitHub CLI auth" "warn" "not authenticated" "gh auth login"
    fi
}

# check_wrangler_auth - Cloudflare Wrangler authentication check
# Related: bead azw
# Enhanced: Caching and timeout support (bead lz1)
check_wrangler_auth() {
    local auth_home=""
    local wrangler_bin=""
    auth_home="$(doctor_runtime_home)"

    if ! wrangler_bin="$(doctor_binary_path wrangler 2>/dev/null || true)" || [[ -z "$wrangler_bin" ]]; then
        check "deep.cloud.wrangler_auth" "Wrangler (Cloudflare)" "warn" "not installed" "bun install -g --trust wrangler@latest"
        return
    fi

    # Try cache first (bead lz1)
    local cached_result
    if cached_result=$(get_cached_result "wrangler_auth"); then
        check "deep.cloud.wrangler_auth" "Wrangler (Cloudflare) auth" "pass" "$cached_result (cached)"
        return
    fi

    local shell_config_files=()
    mapfile -t shell_config_files < <(default_auth_config_files)
    if get_configured_secret "CLOUDFLARE_API_TOKEN" "${shell_config_files[@]}" >/dev/null; then
        cache_result "wrangler_auth" "CLOUDFLARE_API_TOKEN"
        check "deep.cloud.wrangler_auth" "Wrangler (Cloudflare) auth" "pass" "CLOUDFLARE_API_TOKEN set"
        return
    fi

    # Run with timeout
    local result
    result=$(run_with_timeout "$DEEP_CHECK_TIMEOUT" "Wrangler auth" "$wrangler_bin" whoami 2>&1)
    local status=$?

    if ((status == 124)); then
        check_with_timeout_status "deep.cloud.wrangler_auth" "Wrangler (Cloudflare) auth" "timeout" "check timed out" "Check network, then set CLOUDFLARE_API_TOKEN or run wrangler login from a browser-capable session"
    elif ((status == 0)); then
        # Extract account info from wrangler whoami output
        local wrangler_account="authenticated"
        if echo "$result" | grep -q "Account ID"; then
            wrangler_account="authenticated"
        fi
        cache_result "wrangler_auth" "$wrangler_account"
        check "deep.cloud.wrangler_auth" "Wrangler (Cloudflare) auth" "pass" "$wrangler_account"
    else
        # A wrangler config file alone does not prove the user is still
        # authenticated, so do not treat it as a pass if `whoami` failed.
        if [[ -f "$auth_home/.wrangler/config/default.toml" ]]; then
            check "deep.cloud.wrangler_auth" "Wrangler (Cloudflare) auth" "warn" "config file present but auth could not be verified" "Set CLOUDFLARE_API_TOKEN or rerun wrangler login from a browser-capable session"
        else
            check "deep.cloud.wrangler_auth" "Wrangler (Cloudflare) auth" "warn" "not authenticated" "Set CLOUDFLARE_API_TOKEN or run wrangler login from a browser-capable session"
        fi
    fi
}

# check_supabase_auth - Supabase CLI authentication check
# Related: bead azw
check_supabase_auth() {
    local auth_home=""
    local supabase_bin=""
    auth_home="$(doctor_runtime_home)"

    if ! supabase_bin="$(doctor_binary_path supabase 2>/dev/null || true)" || [[ -z "$supabase_bin" ]]; then
        check "deep.cloud.supabase_auth" "Supabase CLI" "warn" "not installed" "acfs update --cloud-only --force"
        return
    fi

    # Try cache first (bead lz1)
    local cached_result
    if cached_result=$(get_cached_result "supabase_auth"); then
        check "deep.cloud.supabase_auth" "Supabase CLI auth" "pass" "$cached_result (cached)"
        return
    fi

    # Check for SUPABASE_ACCESS_TOKEN (headless auth)
    local shell_config_files=()
    mapfile -t shell_config_files < <(default_auth_config_files)
    if get_configured_secret "SUPABASE_ACCESS_TOKEN" "${shell_config_files[@]}" >/dev/null; then
        cache_result "supabase_auth" "SUPABASE_ACCESS_TOKEN"
        check "deep.cloud.supabase_auth" "Supabase CLI auth" "pass" "SUPABASE_ACCESS_TOKEN set"
        return
    fi

    local token_file=""
    local token_files=(
        "$auth_home/.supabase/access-token"
        "$auth_home/.config/supabase/access-token"
    )
    for token_file in "${token_files[@]}"; do
        if [[ -f "$token_file" ]]; then
            local token_value=""
            token_value="$(cat "$token_file" 2>/dev/null || true)"
            if has_usable_secret "$token_value"; then
                cache_result "supabase_auth" "access-token file"
                check "deep.cloud.supabase_auth" "Supabase CLI auth" "pass" "access-token file present"
                return
            fi
        fi
    done

    check "deep.cloud.supabase_auth" "Supabase CLI auth" "warn" "not authenticated" "supabase login --token <token> (or set SUPABASE_ACCESS_TOKEN)"
}

# check_vercel_auth - Vercel CLI authentication check
# Related: bead azw
check_vercel_auth() {
    local auth_home=""
    local vercel_bin=""
    auth_home="$(doctor_runtime_home)"

    if ! vercel_bin="$(doctor_binary_path vercel 2>/dev/null || true)" || [[ -z "$vercel_bin" ]]; then
        check "deep.cloud.vercel_auth" "Vercel CLI" "warn" "not installed" "bun install -g --trust vercel@latest"
        return
    fi

    # Try cache first (bead lz1)
    local cached_result
    if cached_result=$(get_cached_result "vercel_auth"); then
        check "deep.cloud.vercel_auth" "Vercel CLI auth" "pass" "$cached_result (cached)"
        return
    fi

    local shell_config_files=()
    mapfile -t shell_config_files < <(default_auth_config_files)
    if get_configured_secret "VERCEL_TOKEN" "${shell_config_files[@]}" >/dev/null; then
        cache_result "vercel_auth" "VERCEL_TOKEN"
        check "deep.cloud.vercel_auth" "Vercel CLI auth" "pass" "VERCEL_TOKEN set"
        return
    fi

    # Run with timeout
    local result
    result=$(run_with_timeout "$DEEP_CHECK_TIMEOUT" "Vercel auth" "$vercel_bin" whoami 2>&1)
    local status=$?

    if ((status == 124)); then
        check_with_timeout_status "deep.cloud.vercel_auth" "Vercel CLI auth" "timeout" "check timed out" "Check network, then run vercel login or set VERCEL_TOKEN"
    elif ((status == 0)); then
        local vercel_user
        vercel_user=$(echo "$result" | head -n1 | tr -d ' ')
        [[ -z "$vercel_user" ]] && vercel_user="authenticated"
        cache_result "vercel_auth" "$vercel_user"
        check "deep.cloud.vercel_auth" "Vercel CLI auth" "pass" "$vercel_user"
    else
        local auth_file=""
        local auth_files=(
            "$auth_home/.config/vercel/auth.json"
            "$auth_home/.vercel/auth.json"
        )
        for auth_file in "${auth_files[@]}"; do
            [[ -f "$auth_file" ]] || continue
            if command -v jq &>/dev/null; then
                if json_file_has_usable_jq_value "$auth_file" '.token // empty | strings'; then
                    cache_result "vercel_auth" "auth file present"
                    check "deep.cloud.vercel_auth" "Vercel CLI auth" "pass" "auth file present"
                    return
                fi
            elif json_file_has_usable_string_key "$auth_file" "token"; then
                cache_result "vercel_auth" "auth file present"
                check "deep.cloud.vercel_auth" "Vercel CLI auth" "pass" "auth file present"
                return
            fi
        done

        check "deep.cloud.vercel_auth" "Vercel CLI auth" "warn" "not authenticated" "vercel login (or set VERCEL_TOKEN)"
    fi
}

# Print summary
print_summary() {
    echo ""

    # Print legend (bead qup)
    local doctor_ci="${ACFS_DOCTOR_CI:-false}"
    if [[ "$doctor_ci" != "true" ]]; then
        if [[ "$HAS_GUM" == "true" ]]; then
            gum style --foreground "$ACFS_MUTED" "  Legend: $(gum style --foreground "$ACFS_SUCCESS" "✓") installed  $(gum style --foreground "$ACFS_MUTED" "○") skipped  $(gum style --foreground "$ACFS_ERROR" "✖") missing  $(gum style --foreground "$ACFS_WARNING" "⚠") warning  $(gum style --foreground "$ACFS_WARNING" "?") timeout"
        else
            echo -e "  Legend: ${GREEN}✓${NC} installed  ${CYAN}○${NC} skipped  ${RED}✖${NC} missing  ${YELLOW}⚠${NC} warning  ${YELLOW}?${NC} timeout"
        fi
    fi
}

# Print JSON output
# Enhanced per bead aqs: Includes deep check summary when --deep is used
print_json() {
    local checks_json
    checks_json=$(printf '%s,' "${JSON_CHECKS[@]}" | sed 's/,$//')

    local os_id="unknown"
    local os_version="unknown"
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        os_id="${ID:-unknown}"
        os_version="${VERSION_ID:-unknown}"
    fi

    # Build deep summary JSON if deep mode was used
    local deep_summary_json=""
    if [[ "$DEEP_MODE" == "true" ]]; then
        local deep_total=$((DEEP_PASS_COUNT + DEEP_WARN_COUNT + DEEP_FAIL_COUNT))
        deep_summary_json=",
  \"deep_summary\": {\"pass\": $DEEP_PASS_COUNT, \"warn\": $DEEP_WARN_COUNT, \"fail\": $DEEP_FAIL_COUNT, \"total\": $deep_total, \"elapsed_seconds\": ${DEEP_CHECK_ELAPSED:-0}}"
    fi

    local json_output
    json_output=$(cat << EOF
{
  "acfs_version": "$(json_escape "$ACFS_VERSION")",
  "timestamp": "$(json_escape "$(date -Iseconds)")",
  "mode": "$(json_escape "${ACFS_MODE:-vibe}")",
  "deep_mode": $DEEP_MODE,
  "user": "$(json_escape "$(_acfs_doctor_resolve_current_user 2>/dev/null || true)")",
  "os": {"id": "$(json_escape "$os_id")", "version": "$(json_escape "$os_version")"},
  "checks": [$checks_json],
  "summary": {"pass": $PASS_COUNT, "skip": $SKIP_COUNT, "warn": $WARN_COUNT, "fail": $FAIL_COUNT}$deep_summary_json
}
EOF
)

    # Use output formatting library if available
    if type -t acfs_format_output &>/dev/null; then
        local resolved_format
        resolved_format=$(acfs_resolve_format "$_DOCTOR_OUTPUT_FORMAT")
        acfs_format_output "$json_output" "$resolved_format" "$_DOCTOR_SHOW_STATS"
    else
        # Fallback: direct JSON output
        printf '%s\n' "$json_output"
    fi
}

# Main
main() {
    local invoked_as
    invoked_as="$(basename "${0:-acfs}")"

    # If installed as `acfs`, support subcommands (doctor/update/services-setup/version).
    local subcmd="${1:-}"
    case "$subcmd" in
        doctor|check)
            shift
            ;;
        info|i)
            shift
            local info_script=""
            info_script="$(_acfs_doctor_find_lib_script "info.sh" 2>/dev/null || true)"

            if [[ -n "$info_script" ]]; then
                _acfs_doctor_exec_bash_script "$info_script" "$@"
            fi

            echo "Error: info.sh not found" >&2
            return 1
            ;;
        status)
            shift
            local status_script=""
            status_script="$(_acfs_doctor_find_lib_script "status.sh" 2>/dev/null || true)"

            if [[ -n "$status_script" ]]; then
                _acfs_doctor_exec_bash_script "$status_script" "$@"
            fi

            echo "Error: status.sh not found" >&2
            return 1
            ;;
        dashboard)
            shift
            local dashboard_script=""
            dashboard_script="$(_acfs_doctor_find_lib_script "dashboard.sh" 2>/dev/null || true)"

            if [[ -n "$dashboard_script" ]]; then
                _acfs_doctor_exec_bash_script "$dashboard_script" "$@"
            fi

            echo "Error: dashboard.sh not found" >&2
            return 1
            ;;
        continue|progress)
            shift
            local continue_script=""
            continue_script="$(_acfs_doctor_find_lib_script "continue.sh" 2>/dev/null || true)"

            if [[ -n "$continue_script" ]]; then
                _acfs_doctor_exec_bash_script "$continue_script" "$@"
            fi

            echo "Error: continue.sh not found" >&2
            return 1
            ;;
        changelog|changes|log)
            shift
            local changelog_script=""
            changelog_script="$(_acfs_doctor_find_lib_script "changelog.sh" 2>/dev/null || true)"

            if [[ -n "$changelog_script" ]]; then
                _acfs_doctor_exec_bash_script "$changelog_script" "$@"
            fi

            echo "Error: changelog.sh not found" >&2
            return 1
            ;;
        export-config|export)
            shift
            local export_config_script=""
            export_config_script="$(_acfs_doctor_find_lib_script "export-config.sh" 2>/dev/null || true)"

            if [[ -n "$export_config_script" ]]; then
                _acfs_doctor_exec_bash_script "$export_config_script" "$@"
            fi

            echo "Error: export-config.sh not found" >&2
            return 1
            ;;
        cheatsheet|cs)
            shift
            local cheatsheet_script=""
            cheatsheet_script="$(_acfs_doctor_find_lib_script "cheatsheet.sh" 2>/dev/null || true)"

            if [[ -n "$cheatsheet_script" ]]; then
                _acfs_doctor_exec_bash_script "$cheatsheet_script" "$@"
            fi

            echo "Error: cheatsheet.sh not found" >&2
            return 1
            ;;
        session|sessions)
            shift
            acfs_session_main "$@"
            return $?
            ;;
        update)
            shift
            local update_script=""
            update_script="$(_acfs_doctor_find_lib_script "update.sh" 2>/dev/null || true)"

            if [[ -n "$update_script" ]]; then
                _acfs_doctor_exec_bash_script "$update_script" "$@"
            fi

            echo "Error: update.sh not found" >&2
            return 1
            ;;
        newproj|new-project|new)
            shift
            local newproj_script=""
            newproj_script="$(_acfs_doctor_find_lib_script "newproj.sh" 2>/dev/null || true)"

            if [[ -n "$newproj_script" ]]; then
                _acfs_doctor_exec_bash_script "$newproj_script" "$@"
            fi

            echo "Error: newproj.sh not found" >&2
            return 1
            ;;
        services-setup|services|setup)
            shift
            local services_script=""
            services_script="$(_acfs_doctor_find_scripts_script "services-setup.sh" 2>/dev/null || true)"

            if [[ -n "$services_script" ]]; then
                _acfs_doctor_exec_bash_script "$services_script" "$@"
            fi

            echo "Error: services-setup.sh not found" >&2
            return 1
            ;;
        support-bundle|bundle)
            shift
            local support_script=""
            support_script="$(_acfs_doctor_find_lib_script "support.sh" 2>/dev/null || true)"

            if [[ -n "$support_script" ]]; then
                _acfs_doctor_exec_bash_script "$support_script" "$@"
            fi

            echo "Error: support.sh not found" >&2
            return 1
            ;;
        version|-v|--version)
            local version_file=""
            version_file="$(_acfs_doctor_find_project_path "VERSION" 2>/dev/null || true)"

            if [[ -n "$version_file" ]]; then
                cat "$version_file"
            else
                echo "${ACFS_VERSION:-unknown}"
            fi
            return 0
            ;;
        help|-h)
            print_acfs_help
            return 0
            ;;
        "")
            if [[ "$invoked_as" == "acfs" ]]; then
                print_acfs_help
                return 0
            fi
            ;;
    esac

    # Parse args
    while [[ $# -gt 0 ]]; do
        case $1 in
            --json)
                JSON_MODE=true
                shift
                ;;
            --format|-f)
                shift
                if [[ -z "${1:-}" || "$1" == -* ]]; then
                    echo "Error: --format requires a value (json or toon)" >&2
                    return 1
                fi
                _DOCTOR_OUTPUT_FORMAT="$1"
                JSON_MODE=true
                shift
                ;;
            --format=*)
                _DOCTOR_OUTPUT_FORMAT="${1#*=}"
                if [[ -z "$_DOCTOR_OUTPUT_FORMAT" ]]; then
                    echo "Error: --format requires a value (json or toon)" >&2
                    return 1
                fi
                JSON_MODE=true
                shift
                ;;
            --toon|-t)
                _DOCTOR_OUTPUT_FORMAT="toon"
                JSON_MODE=true
                shift
                ;;
            --stats)
                _DOCTOR_SHOW_STATS=true
                shift
                ;;
            --deep)
                DEEP_MODE=true
                shift
                ;;
            --no-cache)
                NO_CACHE=true
                shift
                ;;
            --fix)
                FIX_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN_MODE=true
                shift
                ;;
            --help|-h)
                echo "Usage: acfs doctor [--json] [--format <fmt>] [--stats] [--deep] [--no-cache] [--fix] [--dry-run]"
                echo ""
                echo "Options:"
                echo "  --json           Output results as JSON"
                echo "  --format <fmt>   Output format: json or toon (env: ACFS_OUTPUT_FORMAT, TOON_DEFAULT_FORMAT)"
                echo "  --toon, -t       Shorthand for --format toon"
                echo "  --stats          Show token savings statistics (JSON vs TOON bytes)"
                echo "  --deep      Run functional tests (auth, connections)"
                echo "  --no-cache  Skip cache, run all checks fresh"
                echo "  --fix       Automatically apply safe fixes for failed checks"
                echo "  --dry-run   Preview fixes without applying (use with --fix)"
                echo ""
                echo "By default, doctor runs quick existence checks only."
                echo "Use --deep for thorough validation including:"
                echo "  - Agent authentication (claude, codex, gemini)"
                echo "  - Database connectivity (PostgreSQL)"
                echo "  - Cloud CLI authentication (vault, wrangler, etc.)"
                echo ""
                echo "Deep checks are cached for 5 minutes by default."
                echo "Use --no-cache to force fresh deep checks."
                echo ""
                echo "Fix mode applies safe, reversible fixes for common issues:"
                echo "  - PATH ordering in shell config"
                echo "  - Missing ACFS config files"
                echo "  - Missing symlinks for tools"
                echo "  - Missing zsh plugins"
                echo "Use --dry-run to preview fixes before applying."
                echo ""
                echo "Examples:"
                echo "  acfs doctor                   # Quick health check"
                echo "  acfs doctor --deep            # Full functional tests"
                echo "  acfs doctor --deep --no-cache # Force fresh deep checks"
                echo "  acfs doctor --json            # JSON output for tooling"
                echo "  acfs doctor --fix             # Apply safe fixes"
                echo "  acfs doctor --fix --dry-run   # Preview fixes"
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ "$JSON_MODE" != "true" ]]; then
        local os_pretty="unknown"
        if [[ -f /etc/os-release ]]; then
            # shellcheck disable=SC1091
            . /etc/os-release
            os_pretty="${PRETTY_NAME:-${ID:-unknown} ${VERSION_ID:-unknown}}"
        fi

        if [[ "$HAS_GUM" == "true" ]]; then
            echo ""
            gum style \
                --border rounded \
                --border-foreground "$ACFS_PRIMARY" \
                --padding "1 2" \
                --margin "0 0 1 0" \
                "$(gum style --foreground "$ACFS_ACCENT" --bold '🩺 ACFS Doctor') $(gum style --foreground "$ACFS_MUTED" "v$ACFS_VERSION")

$(gum style --foreground "$ACFS_MUTED" "User:") $(gum style --foreground "$ACFS_TEAL" "$(_acfs_doctor_resolve_current_user 2>/dev/null || true)")  $(gum style --foreground "$ACFS_MUTED" "Mode:") $(gum style --foreground "$ACFS_TEAL" "${ACFS_MODE:-vibe}")
$(gum style --foreground "$ACFS_MUTED" "OS:") $(gum style --foreground "$ACFS_TEAL" "$os_pretty")"
        else
            echo ""
            echo "ACFS Doctor v$ACFS_VERSION"
            echo "User: $(_acfs_doctor_resolve_current_user 2>/dev/null || true)"
            echo "Mode: ${ACFS_MODE:-vibe}"
            echo "OS: $os_pretty"
            echo ""
        fi
    fi

    # Initialize fix mode if enabled
    if [[ "$FIX_MODE" == "true" ]]; then
        if type -t run_doctor_fix &>/dev/null; then
            if [[ "$DRY_RUN_MODE" == "true" ]]; then
                run_doctor_fix --dry-run
            else
                run_doctor_fix
            fi
        else
            echo "Warning: doctor_fix.sh not loaded, --fix unavailable" >&2
            FIX_MODE=false
        fi
    fi

    check_identity
    check_workspace
    check_shell
    check_core_tools
    check_agents
    check_cloud
    check_stack
    check_utilities
    check_manifest_supplemental
    show_skipped_tools

    # Run deep checks if --deep flag was provided
    if [[ "$DEEP_MODE" == "true" ]]; then
        run_deep_checks
    fi

    if [[ "$JSON_MODE" == "true" ]]; then
        print_json
    else
        print_summary
    fi

    # Finalize fix mode if enabled
    if [[ "$FIX_MODE" == "true" ]]; then
        if type -t finalize_doctor_fix &>/dev/null; then
            finalize_doctor_fix
        fi
    fi

    # Exit with appropriate code
    if [[ $FAIL_COUNT -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
