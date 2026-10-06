#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Export Config - Export current configuration
# Exports tool versions, settings, and module list for backup/migration
# ============================================================

_EXPORT_WAS_SOURCED=false
_EXPORT_ORIGINAL_HOME=""
_EXPORT_ORIGINAL_HOME_WAS_SET=false
_EXPORT_RESTORE_ERREXIT=false
_EXPORT_RESTORE_NOUNSET=false
_EXPORT_RESTORE_PIPEFAIL=false
if [[ -v HOME ]]; then
    _EXPORT_ORIGINAL_HOME="$HOME"
    _EXPORT_ORIGINAL_HOME_WAS_SET=true
fi
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    _EXPORT_WAS_SOURCED=true
    [[ $- == *e* ]] && _EXPORT_RESTORE_ERREXIT=true
    [[ $- == *u* ]] && _EXPORT_RESTORE_NOUNSET=true
    if shopt -qo pipefail 2>/dev/null; then
        _EXPORT_RESTORE_PIPEFAIL=true
    fi
fi

set -euo pipefail

export_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

export_existing_abs_home() {
    local path_value=""

    path_value="$(export_sanitize_abs_nonroot_path "${1:-}" 2>/dev/null || true)"
    [[ -n "$path_value" ]] || return 1
    [[ -d "$path_value" ]] || return 1
    printf '%s\n' "$path_value"
}

export_system_binary_path() {
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
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

export_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(export_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(export_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

export_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(export_system_binary_path getent 2>/dev/null || true)"
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

export_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    passwd_home="$(export_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
    [[ -n "$passwd_home" ]] || return 1
    printf '%s\n' "$passwd_home"
}
export_is_valid_username() {
    local username="${1:-}"
    [[ "$username" =~ ^[a-z_][a-z0-9._-]*$ ]]
}

export_resolve_current_home() {
    local current_user=""
    local fallback_home=""
    local passwd_entry=""
    local passwd_home=""
    fallback_home="$(export_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
    if [[ "${_EXPORT_WAS_SOURCED:-false}" == "true" ]]; then
        fallback_home="$(export_sanitize_abs_nonroot_path "${_EXPORT_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
    fi
    current_user="$(export_resolve_current_user 2>/dev/null || true)"

    if [[ "$current_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    if [[ -n "$current_user" ]]; then
        passwd_entry="$(export_getent_passwd_entry "$current_user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            passwd_home="$(export_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
            if [[ -n "$passwd_home" ]]; then
                printf '%s\n' "$passwd_home"
                return 0
            fi
        fi
    fi

    [[ -n "$fallback_home" ]] || return 1
    printf '%s\n' "$fallback_home"
}
export_initial_current_home() {
    local cached_home=""
    local resolved_home=""

    if [[ "${_EXPORT_WAS_SOURCED:-false}" == "true" ]] && [[ -z "${TARGET_HOME:-}${TARGET_USER:-}${ACFS_HOME:-}${ACFS_STATE_FILE:-}${ACFS_SYSTEM_STATE_FILE:-}" ]]; then
        cached_home="$(export_sanitize_abs_nonroot_path "${_EXPORT_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
        if [[ -n "$cached_home" ]]; then
            printf '%s\n' "$cached_home"
            return 0
        fi
    fi

    resolved_home="$(export_resolve_current_home 2>/dev/null || true)"
    if [[ -n "$resolved_home" ]]; then
        printf '%s\n' "$resolved_home"
        return 0
    fi

    if [[ "${_EXPORT_WAS_SOURCED:-false}" == "true" ]]; then
        cached_home="$(export_sanitize_abs_nonroot_path "${_EXPORT_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
        if [[ -n "$cached_home" ]]; then
            printf '%s\n' "$cached_home"
            return 0
        fi
    fi

    return 1
}
_EXPORT_CURRENT_HOME="$(export_initial_current_home 2>/dev/null || true)"
if [[ -n "$_EXPORT_CURRENT_HOME" ]]; then
    HOME="$_EXPORT_CURRENT_HOME"
    export HOME
fi

# Script directory
_EXPORT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_EXPORT_EXPLICIT_ACFS_HOME="$(export_sanitize_abs_nonroot_path "${ACFS_HOME:-}" 2>/dev/null || true)"
_EXPORT_DEFAULT_ACFS_HOME=""
[[ -n "$_EXPORT_CURRENT_HOME" ]] && _EXPORT_DEFAULT_ACFS_HOME="${_EXPORT_CURRENT_HOME}/.acfs"
_EXPORT_ACFS_HOME="${_EXPORT_EXPLICIT_ACFS_HOME:-$_EXPORT_DEFAULT_ACFS_HOME}"
_EXPORT_SYSTEM_STATE_WAS_EXPLICIT=false
[[ -n "${ACFS_SYSTEM_STATE_FILE:-}" ]] && [[ "${ACFS_SYSTEM_STATE_FILE%/}" != "/var/lib/acfs/state.json" ]] && _EXPORT_SYSTEM_STATE_WAS_EXPLICIT=true
_EXPORT_SYSTEM_STATE_FILE="$(export_sanitize_abs_nonroot_path "${ACFS_SYSTEM_STATE_FILE:-/var/lib/acfs/state.json}" 2>/dev/null || true)"
if [[ -z "$_EXPORT_SYSTEM_STATE_FILE" ]]; then
    _EXPORT_SYSTEM_STATE_FILE="/var/lib/acfs/state.json"
fi
_EXPORT_EXPLICIT_TARGET_HOME_RAW="${TARGET_HOME:-}"
_EXPORT_EXPLICIT_TARGET_USER_RAW="${TARGET_USER:-}"
_EXPORT_EXPLICIT_TARGET_HOME="$(export_existing_abs_home "${TARGET_HOME:-}" 2>/dev/null || true)"
_EXPORT_RESOLVED_ACFS_HOME=""

# Source logging if available
if [[ -f "$_EXPORT_SCRIPT_DIR/logging.sh" ]]; then
    source "$_EXPORT_SCRIPT_DIR/logging.sh"
else
    log_error() { echo "[ERROR] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
fi

# ============================================================
# Configuration
# ============================================================
_EXPORT_OUTPUT_FORMAT="yaml"  # yaml, json, or minimal
_EXPORT_STATE_FILE=""
_EXPORT_VERSION_FILE=""
_EXPORT_INSTALL_HELPERS_FILE="${ACFS_INSTALL_HELPERS_SH:-$_EXPORT_SCRIPT_DIR/install_helpers.sh}"
_EXPORT_MANIFEST_INDEX_FILE="${ACFS_MANIFEST_INDEX_SH:-$_EXPORT_SCRIPT_DIR/../generated/manifest_index.sh}"

# ============================================================
# Parse Arguments
# ============================================================
show_help() {
    cat << 'EOF'
ACFS Export Config - Export current configuration

USAGE:
  acfs export-config [OPTIONS]

OPTIONS:
  --json          Output in JSON format (default: YAML)
  --minimal       Output only module list (one per line)
  --output FILE   Write to file instead of stdout
  -h, --help      Show this help message

EXAMPLES:
  acfs export-config                    # Print YAML to stdout
  acfs export-config > backup.yaml      # Save to file
  acfs export-config --json             # JSON output
  acfs export-config --minimal          # Just module list

SENSITIVE DATA:
  This command NEVER exports:
  - SSH keys, API tokens, passwords
  - Full paths containing usernames (sanitized to ~/)
  - Environment-specific secrets

RESTORE ON ANOTHER HOST:
  From a trusted ACFS checkout on the destination (any of the formats above):
    python3 scripts/import-config.py backup.yaml           # preview the plan
    python3 scripts/import-config.py backup.yaml --apply   # install it
  Details: docs/operations/config-restore.md

EOF
}

_EXPORT_OUTPUT_FILE=""

export_config_reset_options() {
    _EXPORT_OUTPUT_FORMAT="yaml"
    _EXPORT_OUTPUT_FILE=""
}

export_config_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                _EXPORT_OUTPUT_FORMAT="json"
                shift
                ;;
            --minimal)
                _EXPORT_OUTPUT_FORMAT="minimal"
                shift
                ;;
            --output)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_error "--output requires a file path"
                    return 1
                fi
                _EXPORT_OUTPUT_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                return 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                return 1
                ;;
        esac
    done

    return 0
}

# ============================================================
# Utility Functions
# ============================================================

json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

yaml_escape() {
    local value="$1"
    value=${value//\'/\'\'}
    printf '%s' "$value"
}

read_state_string_from_file() {
    local state_file="$1"
    local key="$2"
    local value=""
    local jq_bin=""
    local python_bin=""
    local sed_bin=""
    local head_bin=""

    [[ -f "$state_file" ]] || return 1

    jq_bin="$(export_system_binary_path jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        value=$("$jq_bin" -r --arg key "$key" '.[$key] // empty' "$state_file" 2>/dev/null || true)
    else
        python_bin="$(export_system_binary_path python3 2>/dev/null || true)"
    fi

    if [[ -z "$value" && -n "$python_bin" ]]; then
        value=$("$python_bin" - "$state_file" "$key" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
    value = data.get(sys.argv[2], "")
    if isinstance(value, str):
        print(value)
except Exception:
    pass
PY
        )
    fi

    if [[ -z "$value" ]]; then
        sed_bin="$(export_system_binary_path sed 2>/dev/null || true)"
        head_bin="$(export_system_binary_path head 2>/dev/null || true)"
        [[ -n "$sed_bin" && -n "$head_bin" ]] || return 1
        value=$("$sed_bin" -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$state_file" 2>/dev/null | "$head_bin" -n 1 || true)
    fi

    [[ -n "$value" ]] || return 1
    printf '%s\n' "$value"
}

get_state_string() {
    local key="$1"
    read_state_string_from_file "$_EXPORT_STATE_FILE" "$key"
}

read_target_user_from_state() {
    local state_file="$1"
    read_state_string_from_file "$state_file" "target_user"
}

read_target_home_from_state() {
    local state_file="$1"
    local target_home=""

    target_home="$(read_state_string_from_file "$state_file" "target_home" 2>/dev/null || true)"
    [[ -n "$target_home" ]] || return 1
    [[ "$target_home" == /* ]] || return 1
    [[ "$target_home" != "/" ]] || return 1
    printf '%s\n' "${target_home%/}"
}

resolve_target_home() {
    local state_file="${1:-}"
    local state_home=""
    local system_home=""
    local explicit_target_home=""

    if [[ -n "$state_file" ]]; then
        state_home=$(read_target_home_from_state "$state_file" 2>/dev/null || true)
    fi
    system_home=$(read_target_home_from_state "$_EXPORT_SYSTEM_STATE_FILE" 2>/dev/null || true)
    explicit_target_home="$(resolve_explicit_target_home 2>/dev/null || true)"

    if [[ -n "$explicit_target_home" ]]; then
        printf '%s\n' "$explicit_target_home"
        return 0
    fi

    if [[ -n "$_EXPORT_EXPLICIT_TARGET_HOME_RAW" ]] || [[ -n "$_EXPORT_EXPLICIT_TARGET_USER_RAW" ]]; then
        return 1
    fi

    if [[ -n "$state_home" ]]; then
        if [[ "$state_file" == "$_EXPORT_SYSTEM_STATE_FILE" ]]; then
            printf '%s\n' "$state_home"
            return 0
        fi
        if [[ -n "$_EXPORT_EXPLICIT_ACFS_HOME" ]] && [[ "$state_file" == "$_EXPORT_EXPLICIT_ACFS_HOME/state.json" ]]; then
            printf '%s\n' "$state_home"
            return 0
        fi
    fi

    if [[ -n "$system_home" ]]; then
        printf '%s\n' "$system_home"
        return 0
    fi

    if [[ -n "$state_home" ]]; then
        printf '%s\n' "$state_home"
        return 0
    fi

    return 1
}

script_acfs_home() {
    local candidate=""
    candidate=$(cd "$_EXPORT_SCRIPT_DIR/../.." 2>/dev/null && pwd) || return 1
    [[ "$(basename "$candidate")" == ".acfs" ]] || return 1
    printf '%s\n' "$candidate"
}

export_current_home_acfs_candidate() {
    local candidate="$_EXPORT_DEFAULT_ACFS_HOME"
    local current_home="$_EXPORT_CURRENT_HOME"
    local current_user=""
    local original_home=""
    local state_home=""
    local state_user=""
    local state_user_home=""

    [[ -n "$candidate" && -n "$current_home" ]] || return 1
    [[ "$current_home" != "/root" ]] || return 1
    [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]] || return 1

    if [[ "${_EXPORT_ORIGINAL_HOME_WAS_SET:-false}" == true ]]; then
        original_home="$(export_sanitize_abs_nonroot_path "$_EXPORT_ORIGINAL_HOME" 2>/dev/null || true)"
        [[ -n "$original_home" && "$original_home" == "$current_home" ]] || return 1
    fi

    current_user="$(export_resolve_current_user 2>/dev/null || true)"
    [[ -n "$current_user" && "$current_user" != "root" ]] || return 1

    if [[ -f "$candidate/state.json" ]]; then
        state_home="$(read_target_home_from_state "$candidate/state.json" 2>/dev/null || true)"
        [[ -z "$state_home" || "$state_home" == "$current_home" ]] || return 1

        state_user="$(read_target_user_from_state "$candidate/state.json" 2>/dev/null || true)"
        if [[ -n "$state_user" && "$state_user" != "$current_user" ]]; then
            state_user_home="$(home_for_user "$state_user" 2>/dev/null || true)"
            [[ "$state_user_home" == "$current_home" ]] || return 1
        fi
    fi

    printf '%s\n' "$candidate"
}

resolve_acfs_home() {
    if [[ -n "$_EXPORT_RESOLVED_ACFS_HOME" ]]; then
        printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
        return 0
    fi

    local candidate=""
    local detected_home=""
    local detected_user=""
    local explicit_target_home=""

    candidate=$(script_acfs_home 2>/dev/null || true)
    if [[ -n "$candidate" ]] && [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]]; then
        _EXPORT_RESOLVED_ACFS_HOME="$candidate"
        printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
        return 0
    fi

    explicit_target_home="$(resolve_explicit_target_home 2>/dev/null || true)"
    if [[ -n "$explicit_target_home" ]]; then
        candidate="${explicit_target_home}/.acfs"
        if [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]]; then
            _EXPORT_RESOLVED_ACFS_HOME="$candidate"
            printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    if [[ ! -f "$_EXPORT_SYSTEM_STATE_FILE" ]] && [[ -n "$_EXPORT_EXPLICIT_ACFS_HOME" ]] && [[ -f "$_EXPORT_EXPLICIT_ACFS_HOME/state.json" || -f "$_EXPORT_EXPLICIT_ACFS_HOME/VERSION" || -d "$_EXPORT_EXPLICIT_ACFS_HOME/onboard" ]]; then
        _EXPORT_RESOLVED_ACFS_HOME="$_EXPORT_EXPLICIT_ACFS_HOME"
        printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
        return 0
    fi

    candidate="$(export_current_home_acfs_candidate 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        _EXPORT_RESOLVED_ACFS_HOME="$candidate"
        printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ "$_EXPORT_SYSTEM_STATE_WAS_EXPLICIT" == true ]]; then
        detected_home=$(read_target_home_from_state "$_EXPORT_SYSTEM_STATE_FILE" 2>/dev/null || true)
        if [[ -n "$detected_home" ]]; then
            candidate="${detected_home}/.acfs"
            if [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]]; then
                _EXPORT_RESOLVED_ACFS_HOME="$candidate"
                printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
                return 0
            fi
        fi

        detected_user=$(read_target_user_from_state "$_EXPORT_SYSTEM_STATE_FILE" 2>/dev/null || true)
        if [[ -n "$detected_user" ]]; then
            detected_home=$(home_for_user "$detected_user" 2>/dev/null || true)
            candidate="${detected_home}/.acfs"
            if [[ -n "$detected_home" ]] && [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]]; then
                _EXPORT_RESOLVED_ACFS_HOME="$candidate"
                printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
                return 0
            fi
        fi
    fi

    if [[ -n "$_EXPORT_EXPLICIT_ACFS_HOME" ]] && [[ -f "$_EXPORT_EXPLICIT_ACFS_HOME/state.json" || -f "$_EXPORT_EXPLICIT_ACFS_HOME/VERSION" || -d "$_EXPORT_EXPLICIT_ACFS_HOME/onboard" ]]; then
        _EXPORT_RESOLVED_ACFS_HOME="$_EXPORT_EXPLICIT_ACFS_HOME"
        printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ -n "$_EXPORT_EXPLICIT_TARGET_HOME_RAW" ]] || [[ -n "$_EXPORT_EXPLICIT_TARGET_USER_RAW" ]]; then
        _EXPORT_RESOLVED_ACFS_HOME=""
        printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ -n "${SUDO_USER:-}" ]]; then
        detected_home=$(home_for_user "$SUDO_USER" 2>/dev/null || true)
        candidate="${detected_home}/.acfs"
        if [[ -n "$detected_home" ]] && [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]]; then
            _EXPORT_RESOLVED_ACFS_HOME="$candidate"
            printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    detected_home=$(read_target_home_from_state "$_EXPORT_SYSTEM_STATE_FILE" 2>/dev/null || true)
    if [[ -n "$detected_home" ]]; then
        candidate="${detected_home}/.acfs"
        if [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]]; then
            _EXPORT_RESOLVED_ACFS_HOME="$candidate"
            printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    detected_user=$(read_target_user_from_state "$_EXPORT_SYSTEM_STATE_FILE" 2>/dev/null || true)
    if [[ -n "$detected_user" ]]; then
        detected_home=$(home_for_user "$detected_user" 2>/dev/null || true)
        candidate="${detected_home}/.acfs"
        if [[ -n "$detected_home" ]] && [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]]; then
            _EXPORT_RESOLVED_ACFS_HOME="$candidate"
            printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    if [[ -n "$_EXPORT_EXPLICIT_ACFS_HOME" ]] && [[ -f "$_EXPORT_EXPLICIT_ACFS_HOME/state.json" || -f "$_EXPORT_EXPLICIT_ACFS_HOME/VERSION" || -d "$_EXPORT_EXPLICIT_ACFS_HOME/onboard" ]]; then
        _EXPORT_RESOLVED_ACFS_HOME="$_EXPORT_EXPLICIT_ACFS_HOME"
        printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ -n "$_EXPORT_DEFAULT_ACFS_HOME" ]] && [[ -f "$_EXPORT_DEFAULT_ACFS_HOME/state.json" || -f "$_EXPORT_DEFAULT_ACFS_HOME/VERSION" || -d "$_EXPORT_DEFAULT_ACFS_HOME/onboard" ]]; then
        _EXPORT_RESOLVED_ACFS_HOME="$_EXPORT_DEFAULT_ACFS_HOME"
        printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
        return 0
    fi

    _EXPORT_RESOLVED_ACFS_HOME="$_EXPORT_DEFAULT_ACFS_HOME"
    printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
}

resolve_state_file() {
    local candidate=""

    if [[ -n "$_EXPORT_ACFS_HOME" ]]; then
        candidate="${_EXPORT_ACFS_HOME}/state.json"
    fi

    if [[ -n "$candidate" ]] && [[ -f "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    if [[ -f "$_EXPORT_SYSTEM_STATE_FILE" ]]; then
        printf '%s\n' "$_EXPORT_SYSTEM_STATE_FILE"
        return 0
    fi

    printf '%s\n' "$candidate"
}

refresh_acfs_paths() {
    _EXPORT_ACFS_HOME="$(resolve_acfs_home)"
    _EXPORT_STATE_FILE="$(resolve_state_file)"
    _EXPORT_VERSION_FILE="${_EXPORT_ACFS_HOME:+$_EXPORT_ACFS_HOME/VERSION}"
}

get_target_user() {
    if [[ -n "${TARGET_USER:-}" ]]; then
        printf '%s\n' "$TARGET_USER"
        return 0
    fi

    read_target_user_from_state "$_EXPORT_SYSTEM_STATE_FILE" 2>/dev/null || \
        read_target_user_from_state "$_EXPORT_STATE_FILE" 2>/dev/null
}

home_for_user() {
    local user="$1"
    local passwd_entry=""
    local home_candidate=""
    local current_user=""

    [[ -n "$user" ]] || return 1

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    passwd_entry="$(export_getent_passwd_entry "$user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        home_candidate="$(export_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
        if [[ -n "$home_candidate" ]]; then
            printf '%s\n' "$home_candidate"
            return 0
        fi
    fi

    current_user="$(export_resolve_current_user 2>/dev/null || true)"
    if [[ "$user" == "$current_user" ]]; then
        home_candidate="${_EXPORT_CURRENT_HOME:-}"
        if [[ -z "$home_candidate" ]]; then
            home_candidate="$(export_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
        fi
        if [[ -n "$home_candidate" ]]; then
            printf '%s\n' "$home_candidate"
            return 0
        fi
    fi

    return 1
}

resolve_explicit_target_home() {
    local target_home=""
    local resolved_home=""

    if [[ -n "$_EXPORT_EXPLICIT_TARGET_USER_RAW" ]]; then
        export_is_valid_username "$_EXPORT_EXPLICIT_TARGET_USER_RAW" || return 1
        resolved_home="$(export_existing_abs_home "$(home_for_user "$_EXPORT_EXPLICIT_TARGET_USER_RAW" 2>/dev/null || true)" 2>/dev/null || true)"
        if [[ -n "$resolved_home" ]]; then
            printf '%s\n' "${resolved_home%/}"
            return 0
        fi
        target_home="$_EXPORT_EXPLICIT_TARGET_HOME"
        if [[ -n "$target_home" ]] && [[ "$target_home" != "${_EXPORT_CURRENT_HOME:-}" ]] && {
            [[ -f "$target_home/.acfs/state.json" ]] || [[ -f "$target_home/.acfs/VERSION" ]] || [[ -d "$target_home/.acfs/onboard" ]]
        }; then
            printf '%s\n' "${target_home%/}"
            return 0
        fi
        return 1
    fi

    target_home="$_EXPORT_EXPLICIT_TARGET_HOME"
    if [[ -n "$target_home" ]]; then
        printf '%s\n' "${target_home%/}"
        return 0
    fi

    return 1
}

read_user_for_home() {
    local user_home="$1"
    local candidate_user=""
    local current_home=""
    local passwd_line=""
    local passwd_home=""
    local state_file=""

    user_home="$(export_sanitize_abs_nonroot_path "$user_home" 2>/dev/null || true)"
    [[ -n "$user_home" ]] || return 1

    while IFS= read -r passwd_line; do
        passwd_home="$(export_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
        [[ "$passwd_home" == "$user_home" ]] || continue
        candidate_user="${passwd_line%%:*}"
        if [[ "$candidate_user" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
    done < <(export_getent_passwd_entry 2>/dev/null || true)

    current_home="${_EXPORT_CURRENT_HOME:-}"
    if [[ -n "$current_home" ]] && [[ "$user_home" == "$current_home" ]]; then
        candidate_user="$(export_resolve_current_user 2>/dev/null || true)"
        if [[ "$candidate_user" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
    fi

    if [[ "$user_home" == "/root" ]]; then
        printf 'root\n'
        return 0
    fi

    state_file="$user_home/.acfs/state.json"
    candidate_user="$(read_target_user_from_state "$state_file" 2>/dev/null || true)"
    if [[ -n "$candidate_user" ]]; then
        current_home="$(home_for_user "$candidate_user" 2>/dev/null || true)"
        if [[ -n "$current_home" ]] && [[ "$current_home" == "$user_home" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
    fi

    return 1
}

infer_target_home_from_acfs_home() {
    local acfs_home_candidate=""
    local inferred_home=""

    acfs_home_candidate="$(export_sanitize_abs_nonroot_path "${_EXPORT_ACFS_HOME:-}" 2>/dev/null || true)"
    [[ -n "$acfs_home_candidate" ]] || return 1
    [[ "$(basename "$acfs_home_candidate")" == ".acfs" ]] || return 1
    [[ -f "$acfs_home_candidate/state.json" || -f "$acfs_home_candidate/VERSION" || -d "$acfs_home_candidate/onboard" ]] || return 1

    if [[ -n "$_EXPORT_EXPLICIT_ACFS_HOME" ]] && [[ "$acfs_home_candidate" == "$_EXPORT_EXPLICIT_ACFS_HOME" ]]; then
        :
    elif [[ -n "$_EXPORT_DEFAULT_ACFS_HOME" ]] && [[ "$acfs_home_candidate" == "$_EXPORT_DEFAULT_ACFS_HOME" ]]; then
        :
    else
        return 1
    fi

    inferred_home="${acfs_home_candidate%/.acfs}"
    inferred_home="$(export_sanitize_abs_nonroot_path "$inferred_home" 2>/dev/null || true)"
    [[ -n "$inferred_home" ]] || return 1

    printf '%s\n' "$inferred_home"
}
prepare_target_context() {
    local detected_user=""
    local detected_home=""
    local path_home=""
    local state_user=""
    local state_user_home=""
    local resolved_target_home=""

    refresh_acfs_paths
    path_home="$(infer_target_home_from_acfs_home 2>/dev/null || true)"

    if [[ -z "${TARGET_HOME:-}" ]] && [[ -n "$path_home" ]]; then
        export TARGET_HOME="$path_home"
    fi

    state_user="$(read_target_user_from_state "$_EXPORT_STATE_FILE" 2>/dev/null || true)"
    if [[ -z "${TARGET_USER:-}" ]] \
        && [[ -n "$path_home" ]] \
        && [[ -n "${TARGET_HOME:-}" ]] \
        && [[ "$TARGET_HOME" == "$path_home" ]] \
        && [[ -n "$state_user" ]] \
        && [[ -n "$_EXPORT_EXPLICIT_ACFS_HOME" ]] \
        && [[ "$_EXPORT_STATE_FILE" == "$_EXPORT_EXPLICIT_ACFS_HOME/state.json" ]]; then
        state_user_home="$(home_for_user "$state_user" 2>/dev/null || true)"
        if [[ -z "$state_user_home" || "$state_user_home" == "$path_home" ]]; then
            export TARGET_USER="$state_user"
        fi
    fi

    if [[ -z "${TARGET_USER:-}" ]] && [[ -n "${TARGET_HOME:-}" ]]; then
        detected_user="$(read_user_for_home "$TARGET_HOME" 2>/dev/null || true)"
        if [[ -n "$detected_user" ]]; then
            export TARGET_USER="$detected_user"
        fi
    fi

    if [[ -z "${TARGET_USER:-}" ]] && [[ -n "$path_home" ]] && [[ -n "${_EXPORT_STATE_FILE:-}" ]]; then
        if [[ -n "$state_user" ]]; then
            export TARGET_USER="$state_user"
        fi
    fi

    if [[ -z "${TARGET_USER:-}" ]]; then
        if detected_user=$(get_target_user 2>/dev/null || true); then
            if [[ -n "$detected_user" ]]; then
                export TARGET_USER="$detected_user"
            fi
        fi
    fi

    if [[ -n "${TARGET_USER:-}" ]]; then
        resolved_target_home="$(home_for_user "$TARGET_USER" 2>/dev/null || true)"
        if [[ -n "$resolved_target_home" ]]; then
            export TARGET_HOME="$resolved_target_home"
        fi
    fi

    if [[ -z "${TARGET_HOME:-}" ]]; then
        detected_home="$(resolve_target_home "$_EXPORT_STATE_FILE" 2>/dev/null || true)"
        if [[ -n "$detected_home" ]]; then
            export TARGET_HOME="$detected_home"
        fi
    fi

    if [[ -z "${TARGET_HOME:-}" ]] && [[ -n "${TARGET_USER:-}" ]]; then
        detected_home="$(home_for_user "$TARGET_USER" 2>/dev/null || true)"
        if [[ -n "$detected_home" ]]; then
            export TARGET_HOME="$detected_home"
        fi
    fi

    if [[ -z "${TARGET_HOME:-}" ]] && [[ -n "$path_home" ]]; then
        export TARGET_HOME="$path_home"
    fi
}

export_validate_bin_dir_for_home() {
    local bin_dir="${1:-}"
    local base_home="${2:-}"
    local passwd_line=""
    local passwd_home=""
    local hinted_home=""

    bin_dir="$(export_sanitize_abs_nonroot_path "$bin_dir" 2>/dev/null || true)"
    [[ -n "$bin_dir" ]] || return 1
    base_home="$(export_sanitize_abs_nonroot_path "$base_home" 2>/dev/null || true)"

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
    hinted_home="$(export_sanitize_abs_nonroot_path "$hinted_home" 2>/dev/null || true)"
    if [[ -n "$hinted_home" ]] && [[ -n "$base_home" ]] && [[ "$hinted_home" != "$base_home" ]]; then
        return 1
    fi

    while IFS= read -r passwd_line; do
        passwd_home="$(export_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
        [[ -n "$passwd_home" ]] || continue
        [[ -n "$base_home" && "$passwd_home" == "$base_home" ]] && continue
        if [[ "$bin_dir" == "$passwd_home" || "$bin_dir" == "$passwd_home/"* ]]; then
            return 1
        fi
    done < <(export_getent_passwd_entry 2>/dev/null || true)

    printf '%s\n' "$bin_dir"
}

augment_path_for_target_user() {
    local dir=""
    local target_home="${TARGET_HOME:-}"
    local primary_bin_dir="${ACFS_BIN_DIR:-$target_home/.local/bin}"
    local current_path="${PATH:-}"
    if declare -f export_validate_bin_dir_for_home >/dev/null 2>&1; then
        primary_bin_dir="$(export_validate_bin_dir_for_home "$primary_bin_dir" "$target_home" 2>/dev/null || true)"
    fi
    [[ -n "$primary_bin_dir" ]] || primary_bin_dir="$target_home/.local/bin"
    local seen_path=":${current_path}:"
    local -a to_prepend=()

    [[ -n "$target_home" ]] || return 0

    for dir in \
        "$primary_bin_dir" \
        "$target_home/.local/bin" \
        "$target_home/.acfs/bin" \
        "$target_home/.bun/bin" \
        "$target_home/.cargo/bin" \
        "$target_home/go/bin" \
        "$target_home/.atuin/bin" \
        "$target_home/google-cloud-sdk/bin"; do
        [[ -d "$dir" ]] || continue
        case "$seen_path" in
            *":$dir:"*) ;;
            *)
                to_prepend+=("$dir")
                seen_path="${seen_path}${dir}:"
                ;;
        esac
    done

    if [[ ${#to_prepend[@]} -gt 0 ]]; then
        local prefix=""
        prefix="$(IFS=:; printf '%s' "${to_prepend[*]}")"
        export PATH="$prefix${current_path:+:$current_path}"
    fi
}

load_module_detection_support() {
    if [[ "${_ACFS_EXPORT_MODULE_SUPPORT_LOADED:-false}" == "true" ]]; then
        return 0
    fi

    if [[ ! -f "$_EXPORT_INSTALL_HELPERS_FILE" ]] || [[ ! -f "$_EXPORT_MANIFEST_INDEX_FILE" ]]; then
        return 1
    fi

    prepare_target_context
    augment_path_for_target_user

    # shellcheck source=/dev/null
    source "$_EXPORT_INSTALL_HELPERS_FILE"
    # shellcheck source=/dev/null
    source "$_EXPORT_MANIFEST_INDEX_FILE"
    _ACFS_EXPORT_MODULE_SUPPORT_LOADED=true
}

# Get ACFS version
get_acfs_version() {
    if [[ -f "$_EXPORT_VERSION_FILE" ]]; then
        cat "$_EXPORT_VERSION_FILE"
    else
        echo "unknown"
    fi
}

# Get tool version (returns empty string if not found)
get_tool_version() {
    local tool="$1"
    local version=""

    case "$tool" in
        rust|cargo)
            version=$(cargo --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        bun)
            version=$(bun --version 2>/dev/null || true)
            ;;
        uv)
            version=$(uv --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        go)
            version=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//' || true)
            ;;
        zsh)
            version=$(zsh --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        tmux)
            version=$(tmux -V 2>/dev/null | awk '{print $2}' || true)
            ;;
        nvim|neovim)
            version=$(nvim --version 2>/dev/null | head -1 | awk '{print $2}' | sed 's/v//' || true)
            ;;
        claude|claude-code)
            version=$(claude --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
            ;;
        codex)
            version=$(codex --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
            ;;
        gemini)
            version=$(gemini --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
            ;;
        zoxide)
            version=$(zoxide --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        atuin)
            version=$(atuin --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        fzf)
            version=$(fzf --version 2>/dev/null | awk '{print $1}' || true)
            ;;
        ripgrep|rg)
            version=$(rg --version 2>/dev/null | head -1 | awk '{print $2}' || true)
            ;;
        gh)
            version=$(gh --version 2>/dev/null | head -1 | awk '{print $3}' || true)
            ;;
        docker)
            version=$(docker --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
            ;;
        postgresql|psql)
            version=$(psql --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+' | head -1 || true)
            ;;
        ntm)
            # ntm uses "ntm version" not --version
            version=$(ntm version 2>/dev/null | awk '{print $3}' || true)
            ;;
        cass)
            version=$(cass --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        cm)
            version=$(cm --version 2>/dev/null | head -1 | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
            ;;
        bv)
            version=$(bv --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        br)
            version=$(br --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        dcg)
            # dcg doesn't have --version, check if binary exists
            if command -v dcg &>/dev/null; then
                version="installed"
            fi
            ;;
        slb)
            # slb uses "slb version" not --version, first line only
            version=$(slb version 2>/dev/null | head -1 | awk '{print $2}' || true)
            ;;
        caam)
            # caam uses "caam version" not --version
            version=$(caam version 2>/dev/null | awk '{print $2}' || true)
            ;;
        ubs)
            # ubs doesn't have typical version output, check if binary exists
            if command -v ubs &>/dev/null; then
                version="installed"
            fi
            ;;
        rch)
            version=$(rch --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        ms)
            version=$(ms --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        ru)
            version=$(ru --version 2>/dev/null | awk '{print $3}' || true)
            ;;
        *)
            # Generic version check
            version=$($tool --version 2>/dev/null | head -1 | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)
            ;;
    esac

    echo "${version:-}"
}

# Get mode from state.json
get_mode() {
    local jq_bin=""
    local python_bin=""
    local sed_bin=""
    local head_bin=""

    if [[ -f "$_EXPORT_STATE_FILE" ]]; then
        jq_bin="$(export_system_binary_path jq 2>/dev/null || true)"
        if [[ -n "$jq_bin" ]]; then
            "$jq_bin" -r '.mode // "unknown"' "$_EXPORT_STATE_FILE" 2>/dev/null || echo "unknown"
        else
            python_bin="$(export_system_binary_path python3 2>/dev/null || true)"
        fi

        if [[ -z "$jq_bin" && -n "$python_bin" ]]; then
            "$python_bin" - "$_EXPORT_STATE_FILE" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
    value = data.get("mode", "unknown")
    print(value if value else "unknown")
except Exception:
    print("unknown")
PY
        elif [[ -z "$jq_bin" ]]; then
            # Use sed instead of grep -oP for portability (works on macOS/BSD)
            sed_bin="$(export_system_binary_path sed 2>/dev/null || true)"
            head_bin="$(export_system_binary_path head 2>/dev/null || true)"
            if [[ -n "$sed_bin" && -n "$head_bin" ]]; then
                "$sed_bin" -n 's/.*"mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_EXPORT_STATE_FILE" 2>/dev/null | "$head_bin" -n 1 || echo "unknown"
            else
                echo "unknown"
            fi
        fi
    else
        echo "unknown"
    fi
}

# Get installed modules from state.json
get_modules_from_state_file() {
    local jq_bin=""
    local python_bin=""

    if [[ -f "$_EXPORT_STATE_FILE" ]]; then
        jq_bin="$(export_system_binary_path jq 2>/dev/null || true)"
        if [[ -n "$jq_bin" ]]; then
            "$jq_bin" -r '.installed_modules // [] | .[]' "$_EXPORT_STATE_FILE" 2>/dev/null || true
        else
            python_bin="$(export_system_binary_path python3 2>/dev/null || true)"
        fi

        if [[ -z "$jq_bin" && -n "$python_bin" ]]; then
            "$python_bin" - "$_EXPORT_STATE_FILE" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
    modules = data.get("installed_modules", [])
    if isinstance(modules, list):
        for module in modules:
            if module is not None:
                print(module)
except Exception:
    pass
PY
        fi
    fi
}

get_modules() {
    local module=""

    if load_module_detection_support; then
        for module in "${ACFS_MODULES_IN_ORDER[@]}"; do
            if acfs_module_is_installed "$module"; then
                printf '%s\n' "$module"
            fi
        done
        return 0
    fi

    get_modules_from_state_file
}

# ============================================================
# Output Generation
# ============================================================

generate_minimal() {
    # Just output module list, one per line
    get_modules
}

generate_yaml() {
    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
    local timestamp
    timestamp=$(date -Iseconds 2>/dev/null || date)
    local acfs_version
    acfs_version=$(get_acfs_version)
    local mode
    mode=$(get_mode)

    cat << EOF
# ACFS Configuration Export
# Generated: $timestamp
# Hostname: $hostname
# ACFS Version: $acfs_version

settings:
  mode: '$(yaml_escape "$mode")'
  shell: '$(yaml_escape "${SHELL##*/}")'

modules:
EOF

    # List modules
    while IFS= read -r module; do
        [[ -n "$module" ]] && printf "  - '%s'\n" "$(yaml_escape "$module")"
    done < <(get_modules)

    echo ""
    echo "tools:"

    # Core tools
    local tools=(
        "rust" "bun" "uv" "go" "zsh" "tmux" "nvim"
        "zoxide" "atuin" "fzf" "ripgrep" "gh" "docker" "postgresql"
    )

    for tool in "${tools[@]}"; do
        local version
        version=$(get_tool_version "$tool")
        if [[ -n "$version" ]]; then
            printf "  %s:\n" "$tool"
            printf "    version: '%s'\n" "$(yaml_escape "$version")"
            echo "    installed: true"
        fi
    done

    echo ""
    echo "agents:"

    # AI agents
    local agents=("claude" "codex" "gemini")
    for agent in "${agents[@]}"; do
        local version
        version=$(get_tool_version "$agent")
        if [[ -n "$version" ]]; then
            printf "  %s:\n" "$agent"
            printf "    version: '%s'\n" "$(yaml_escape "$version")"
            echo "    installed: true"
        fi
    done

    echo ""
    echo "flywheel_stack:"

    # Flywheel tools
    local stack_tools=("ntm" "cass" "cm" "bv" "br" "dcg" "slb" "caam" "ubs" "rch" "ms" "ru")
    for tool in "${stack_tools[@]}"; do
        local version
        version=$(get_tool_version "$tool")
        if [[ -n "$version" ]]; then
            printf "  %s:\n" "$tool"
            printf "    version: '%s'\n" "$(yaml_escape "$version")"
            echo "    installed: true"
        fi
    done
}

generate_json() {
    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
    local timestamp
    timestamp=$(date -Iseconds 2>/dev/null || date)
    local acfs_version
    acfs_version=$(get_acfs_version)
    local mode
    mode=$(get_mode)

    # Build JSON manually to avoid jq dependency for output
    cat << EOF
{
  "metadata": {
    "generated_at": "$(json_escape "$timestamp")",
    "hostname": "$(json_escape "$hostname")",
    "acfs_version": "$(json_escape "$acfs_version")"
  },
  "settings": {
    "mode": "$(json_escape "$mode")",
    "shell": "$(json_escape "${SHELL##*/}")"
  },
  "modules": [
EOF

    # Collect modules into array
    local modules=()
    while IFS= read -r module; do
        [[ -n "$module" ]] && modules+=("$module")
    done < <(get_modules)

    # Output modules as JSON array
    local first=true
    for module in "${modules[@]}"; do
        if [[ "$first" == "true" ]]; then
            printf '    "%s"\n' "$(json_escape "$module")"
            first=false
        else
            printf '    ,"%s"\n' "$(json_escape "$module")"
        fi
    done

    cat << 'EOF'
  ],
  "tools": {
EOF

    # Core tools
    local tools=("rust" "bun" "uv" "go" "zsh" "tmux" "nvim" "zoxide" "atuin" "fzf" "ripgrep" "gh" "docker" "postgresql")
    first=true
    for tool in "${tools[@]}"; do
        local version
        version=$(get_tool_version "$tool")
        if [[ -n "$version" ]]; then
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            printf '    "%s": { "version": "%s", "installed": true }' \
                "$(json_escape "$tool")" \
                "$(json_escape "$version")"
        fi
    done

    cat << 'EOF'

  },
  "agents": {
EOF

    # AI agents
    local agents=("claude" "codex" "gemini")
    first=true
    for agent in "${agents[@]}"; do
        local version
        version=$(get_tool_version "$agent")
        if [[ -n "$version" ]]; then
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            printf '    "%s": { "version": "%s", "installed": true }' \
                "$(json_escape "$agent")" \
                "$(json_escape "$version")"
        fi
    done

    cat << 'EOF'

  },
  "flywheel_stack": {
EOF

    # Flywheel tools
    local stack_tools=("ntm" "cass" "cm" "bv" "br" "dcg" "slb" "caam" "ubs" "rch" "ms" "ru")
    first=true
    for tool in "${stack_tools[@]}"; do
        local version
        version=$(get_tool_version "$tool")
        if [[ -n "$version" ]]; then
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            printf '    "%s": { "version": "%s", "installed": true }' \
                "$(json_escape "$tool")" \
                "$(json_escape "$version")"
        fi
    done

    cat << 'EOF'

  }
}
EOF
}

# ============================================================
# Main
# ============================================================

export_config_main() {
    local output
    local parse_status=0

    export_config_reset_options
    export_config_parse_args "$@" || parse_status=$?
    case "$parse_status" in
        0) ;;
        2) return 0 ;;
        *) return "$parse_status" ;;
    esac

    prepare_target_context
    augment_path_for_target_user

    case "$_EXPORT_OUTPUT_FORMAT" in
        minimal)
            output=$(generate_minimal)
            ;;
        json)
            output=$(generate_json)
            ;;
        yaml|*)
            output=$(generate_yaml)
            ;;
    esac

    if [[ -n "$_EXPORT_OUTPUT_FILE" ]]; then
        echo "$output" > "$_EXPORT_OUTPUT_FILE"
        echo "Configuration exported to: $_EXPORT_OUTPUT_FILE" >&2
    else
        echo "$output"
    fi
}

export_config_restore_shell_options_if_sourced() {
    [[ "$_EXPORT_WAS_SOURCED" == "true" ]] || return 0

    if [[ "$_EXPORT_ORIGINAL_HOME_WAS_SET" == "true" ]]; then
        HOME="$_EXPORT_ORIGINAL_HOME"
        export HOME
    else
        unset HOME
    fi

    [[ "$_EXPORT_RESTORE_ERREXIT" == "true" ]] || set +e
    [[ "$_EXPORT_RESTORE_NOUNSET" == "true" ]] || set +u
    [[ "$_EXPORT_RESTORE_PIPEFAIL" == "true" ]] || set +o pipefail
}

export_config_restore_shell_options_if_sourced

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    export_config_main "$@"
    exit $?
fi
