#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Installer - Post-Install Smoke Test
# Fast verification that runs at the end of install.sh
# ============================================================

_SMOKE_WAS_SOURCED=false
_SMOKE_ORIGINAL_HOME=""
_SMOKE_ORIGINAL_HOME_WAS_SET=false
if [[ -v HOME ]]; then
    _SMOKE_ORIGINAL_HOME="$HOME"
    _SMOKE_ORIGINAL_HOME_WAS_SET=true
fi
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    _SMOKE_WAS_SOURCED=true
fi

# Ensure we have logging functions available
if [[ -z "${ACFS_BLUE:-}" ]]; then
    case "${BASH_SOURCE[0]}" in
        */*)
            _SMOKE_SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
            ;;
        *)
            _SMOKE_SCRIPT_DIR="$(pwd)"
            ;;
    esac
    # shellcheck source=logging.sh
    source "$_SMOKE_SCRIPT_DIR/logging.sh"
fi

_smoke_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

_smoke_system_binary_path() {
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

_smoke_system_curl() {
    local curl_bin=""

    curl_bin="$(_smoke_system_binary_path curl 2>/dev/null || true)"
    [[ -n "$curl_bin" ]] || return 127

    "$curl_bin" "$@"
}

_smoke_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(_smoke_system_binary_path getent 2>/dev/null || true)"
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

_smoke_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(_smoke_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
        if [[ -n "$current_user" ]]; then
            printf '%s\n' "$current_user"
            return 0
        fi
    fi

    whoami_bin="$(_smoke_system_binary_path whoami 2>/dev/null || true)"
    if [[ -n "$whoami_bin" ]]; then
        current_user="$("$whoami_bin" 2>/dev/null || true)"
        if [[ -n "$current_user" ]]; then
            printf '%s\n' "$current_user"
            return 0
        fi
    fi

    current_user="${USER:-${LOGNAME:-}}"
    if [[ -n "$current_user" ]]; then
        printf '%s\n' "$current_user"
        return 0
    fi

    return 1
}

_smoke_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local _passwd_user=""
    local _passwd_pw=""
    local _passwd_uid=""
    local _passwd_gid=""
    local _passwd_gecos=""
    local passwd_home=""
    local _passwd_shell=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=':' read -r _passwd_user _passwd_pw _passwd_uid _passwd_gid _passwd_gecos passwd_home _passwd_shell <<< "$passwd_entry"
    [[ -n "$passwd_home" ]] || return 1
    printf '%s\n' "$passwd_home"
}

_smoke_passwd_shell_from_entry() {
    local passwd_entry="${1:-}"
    local _passwd_user=""
    local _passwd_pw=""
    local _passwd_uid=""
    local _passwd_gid=""
    local _passwd_gecos=""
    local _passwd_home=""
    local passwd_shell=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=':' read -r _passwd_user _passwd_pw _passwd_uid _passwd_gid _passwd_gecos _passwd_home passwd_shell <<< "$passwd_entry"
    [[ -n "$passwd_shell" ]] || return 1
    printf '%s\n' "$passwd_shell"
}

_smoke_resolve_current_home() {
    local current_user=""
    local fallback_home=""
    local passwd_entry=""
    local passwd_home=""

    fallback_home="$(_smoke_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
    if [[ "${_SMOKE_WAS_SOURCED:-false}" == "true" ]]; then
        fallback_home="$(_smoke_sanitize_abs_nonroot_path "${_SMOKE_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
    fi
    current_user="$(_smoke_resolve_current_user 2>/dev/null || true)"
    if [[ "$current_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    if [[ -n "$current_user" ]]; then
        passwd_entry="$(_smoke_getent_passwd_entry "$current_user" || true)"
        if [[ -n "$passwd_entry" ]]; then
            passwd_home="$(_smoke_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
            passwd_home="$(_smoke_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
            if [[ -n "$passwd_home" ]]; then
                printf '%s\n' "$passwd_home"
                return 0
            fi
        fi
    fi

    [[ -n "$fallback_home" ]] || return 1
    printf '%s\n' "$fallback_home"
}

_smoke_initial_current_home() {
    local cached_home=""
    local resolved_home=""

    if [[ "${_SMOKE_WAS_SOURCED:-false}" == "true" ]] && [[ -z "${TARGET_HOME:-}${TARGET_USER:-}${ACFS_HOME:-}${ACFS_STATE_FILE:-}${ACFS_SYSTEM_STATE_FILE:-}" ]]; then
        cached_home="$(_smoke_sanitize_abs_nonroot_path "${_SMOKE_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
        if [[ -n "$cached_home" ]]; then
            printf '%s\n' "$cached_home"
            return 0
        fi
    fi

    resolved_home="$(_smoke_resolve_current_home 2>/dev/null || true)"
    if [[ -n "$resolved_home" ]]; then
        printf '%s\n' "$resolved_home"
        return 0
    fi

    if [[ "${_SMOKE_WAS_SOURCED:-false}" == "true" ]]; then
        cached_home="$(_smoke_sanitize_abs_nonroot_path "${_SMOKE_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
        if [[ -n "$cached_home" ]]; then
            printf '%s\n' "$cached_home"
            return 0
        fi
    fi

    return 1
}

_SMOKE_CURRENT_USER="$(_smoke_resolve_current_user 2>/dev/null || true)"
_SMOKE_CURRENT_HOME="$(_smoke_initial_current_home 2>/dev/null || true)"
if [[ -n "$_SMOKE_CURRENT_HOME" ]]; then
    HOME="$_SMOKE_CURRENT_HOME"
    export HOME
fi
_SMOKE_EXPLICIT_ACFS_HOME="$(_smoke_sanitize_abs_nonroot_path "${ACFS_HOME:-}" 2>/dev/null || true)"
_SMOKE_DEFAULT_ACFS_HOME=""
[[ -n "$_SMOKE_CURRENT_HOME" ]] && _SMOKE_DEFAULT_ACFS_HOME="${_SMOKE_CURRENT_HOME}/.acfs"
_SMOKE_SYSTEM_STATE_FILE="$(_smoke_sanitize_abs_nonroot_path "${ACFS_SYSTEM_STATE_FILE:-/var/lib/acfs/state.json}" 2>/dev/null || true)"
if [[ -z "$_SMOKE_SYSTEM_STATE_FILE" ]]; then
    _SMOKE_SYSTEM_STATE_FILE="/var/lib/acfs/state.json"
fi
_SMOKE_SYSTEM_STATE_WAS_EXPLICIT=false
[[ -n "${ACFS_SYSTEM_STATE_FILE:-}" ]] && [[ "${ACFS_SYSTEM_STATE_FILE%/}" != "/var/lib/acfs/state.json" ]] && _SMOKE_SYSTEM_STATE_WAS_EXPLICIT=true

_smoke_script_acfs_home() {
    local candidate=""
    local script_dir=""

    case "${BASH_SOURCE[0]}" in
        */*)
            script_dir="${BASH_SOURCE[0]%/*}"
            ;;
        *)
            script_dir="."
            ;;
    esac

    candidate=$(cd "$script_dir/../.." 2>/dev/null && pwd) || return 1
    [[ "${candidate##*/}" == ".acfs" ]] || return 1
    printf '%s\n' "$candidate"
}

# ============================================================
# Configuration
# ============================================================

# Test result counters (reset in run_smoke_test)
_SMOKE_CRITICAL_PASS=0
_SMOKE_CRITICAL_FAIL=0
_SMOKE_NONCRITICAL_PASS=0
_SMOKE_WARNING_COUNT=0

_smoke_read_state_string() {
    local state_file="$1"
    local key="$2"
    local value=""
    local jq_bin=""
    local sed_bin=""

    [[ -f "$state_file" ]] || return 1

    jq_bin="$(_smoke_system_binary_path jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        value="$("$jq_bin" -r --arg key "$key" '.[$key] // empty' "$state_file" 2>/dev/null || true)"
    else
        sed_bin="$(_smoke_system_binary_path sed 2>/dev/null || true)"
        if [[ -n "$sed_bin" ]]; then
            while IFS= read -r value; do
                break
            done < <("$sed_bin" -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$state_file" 2>/dev/null || true)
        fi
    fi

    [[ -n "$value" ]] && [[ "$value" != "null" ]] || return 1
    printf '%s\n' "$value"
}

_smoke_resolve_bootstrap_state_file() {
    local candidate=""
    local explicit_state_file=""
    local env_state_file=""
    local system_target_home=""

    candidate="$(_smoke_script_acfs_home 2>/dev/null || true)"
    if [[ -n "$candidate" ]] && [[ -f "$candidate/state.json" ]]; then
        printf '%s\n' "$candidate/state.json"
        return 0
    fi

    candidate="$(_smoke_current_home_state_file 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    if [[ -f "$_SMOKE_SYSTEM_STATE_FILE" ]]; then
        system_target_home="$(_smoke_read_state_string "$_SMOKE_SYSTEM_STATE_FILE" "target_home" 2>/dev/null || true)"
        system_target_home="$(_smoke_sanitize_abs_nonroot_path "$system_target_home" 2>/dev/null || true)"
        if [[ -n "$system_target_home" ]] && {
            [[ -f "$system_target_home/.acfs/state.json" ]] || [[ -f "$system_target_home/.acfs/VERSION" ]] || [[ -d "$system_target_home/.acfs/onboard" ]]
        }; then
            printf '%s\n' "$_SMOKE_SYSTEM_STATE_FILE"
            return 0
        fi
    fi

    if [[ -n "$_SMOKE_EXPLICIT_ACFS_HOME" ]]; then
        explicit_state_file="$_SMOKE_EXPLICIT_ACFS_HOME/state.json"
        if [[ -f "$explicit_state_file" ]]; then
            printf '%s\n' "$explicit_state_file"
            return 0
        fi
    fi

    if [[ -f "$_SMOKE_SYSTEM_STATE_FILE" ]]; then
        printf '%s\n' "$_SMOKE_SYSTEM_STATE_FILE"
        return 0
    fi

    if [[ -n "$_SMOKE_DEFAULT_ACFS_HOME" ]]; then
        candidate="$_SMOKE_DEFAULT_ACFS_HOME/state.json"
        if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    fi

    env_state_file="$(_smoke_sanitize_abs_nonroot_path "${ACFS_STATE_FILE:-}" 2>/dev/null || true)"
    if [[ -n "$env_state_file" ]] && [[ -f "$env_state_file" ]]; then
        printf '%s\n' "$env_state_file"
        return 0
    fi

    candidate="${env_state_file:-${_SMOKE_DEFAULT_ACFS_HOME:+$_SMOKE_DEFAULT_ACFS_HOME/state.json}}"
    [[ -n "$candidate" ]] || candidate="$explicit_state_file"
    printf '%s\n' "$candidate"
}

_smoke_home_for_user() {
    local user="${1:-}"
    local passwd_entry=""
    local home_candidate=""

    [[ -n "$user" ]] || return 1

    passwd_entry="$(_smoke_getent_passwd_entry "$user" || true)"
    if [[ -n "$passwd_entry" ]]; then
        home_candidate="$(_smoke_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
        home_candidate="$(_smoke_sanitize_abs_nonroot_path "$home_candidate" 2>/dev/null || true)"
        if [[ -n "$home_candidate" ]]; then
            printf '%s\n' "$home_candidate"
            return 0
        fi
    fi

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    if [[ -n "${_SMOKE_CURRENT_USER:-}" ]] && [[ "$user" == "$_SMOKE_CURRENT_USER" ]] && [[ -n "${_SMOKE_CURRENT_HOME:-}" ]]; then
        printf '%s\n' "$_SMOKE_CURRENT_HOME"
        return 0
    fi

    return 1
}

_smoke_read_user_for_home() {
    local user_home="$1"
    local candidate_user=""
    local current_home=""
    local getent_bin=""
    local passwd_line=""
    local passwd_home=""
    local state_file=""

    user_home="$(_smoke_sanitize_abs_nonroot_path "$user_home" 2>/dev/null || true)"
    [[ -n "$user_home" ]] || return 1

    getent_bin="$(_smoke_system_binary_path getent 2>/dev/null || true)"
    if [[ -n "$getent_bin" ]]; then
        while IFS= read -r passwd_line; do
            passwd_home="$(_smoke_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
            passwd_home="$(_smoke_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
            [[ "$passwd_home" == "$user_home" ]] || continue
            candidate_user="${passwd_line%%:*}"
            if [[ "$candidate_user" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
                printf '%s\n' "$candidate_user"
                return 0
            fi
        done < <("$getent_bin" passwd 2>/dev/null || true)
    fi

    if [[ -r /etc/passwd ]]; then
        while IFS= read -r passwd_line; do
            passwd_home="$(_smoke_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
            passwd_home="$(_smoke_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
            [[ "$passwd_home" == "$user_home" ]] || continue
            candidate_user="${passwd_line%%:*}"
            if [[ "$candidate_user" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
                printf '%s\n' "$candidate_user"
                return 0
            fi
        done < /etc/passwd
    fi

    current_home="${_SMOKE_CURRENT_HOME:-}"
    if [[ -n "${_SMOKE_CURRENT_USER:-}" ]] && [[ -n "$current_home" ]] && [[ "$user_home" == "$current_home" ]]; then
        printf '%s\n' "$_SMOKE_CURRENT_USER"
        return 0
    fi

    if [[ "$user_home" == "/root" ]]; then
        printf 'root\n'
        return 0
    fi

    state_file="$user_home/.acfs/state.json"
    candidate_user="$(_smoke_read_state_string "$state_file" "target_user" 2>/dev/null || true)"
    if [[ -n "$candidate_user" ]]; then
        current_home="$(_smoke_home_for_user "$candidate_user" 2>/dev/null || true)"
        if [[ -n "$current_home" ]] && [[ "$current_home" == "$user_home" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
    fi

    return 1
}

_smoke_current_home_state_file() {
    local candidate=""
    local current_home="$_SMOKE_CURRENT_HOME"
    local current_user="${_SMOKE_CURRENT_USER:-}"
    local original_home=""
    local state_home=""
    local state_user=""
    local state_user_home=""

    [[ -n "$_SMOKE_DEFAULT_ACFS_HOME" && -n "$current_home" ]] || return 1
    [[ "$current_home" != "/root" ]] || return 1

    candidate="$_SMOKE_DEFAULT_ACFS_HOME/state.json"
    [[ -f "$candidate" ]] || return 1

    if [[ "${_SMOKE_ORIGINAL_HOME_WAS_SET:-false}" == true ]]; then
        original_home="$(_smoke_sanitize_abs_nonroot_path "$_SMOKE_ORIGINAL_HOME" 2>/dev/null || true)"
        [[ -n "$original_home" && "$original_home" == "$current_home" ]] || return 1
    fi

    if [[ -z "$current_user" ]]; then
        current_user="$(_smoke_resolve_current_user 2>/dev/null || true)"
    fi
    [[ -n "$current_user" && "$current_user" != "root" ]] || return 1

    state_home="$(_smoke_read_state_string "$candidate" "target_home" 2>/dev/null || true)"
    [[ -z "$state_home" || "$state_home" == "$current_home" ]] || return 1

    state_user="$(_smoke_read_state_string "$candidate" "target_user" 2>/dev/null || true)"
    if [[ -n "$state_user" && "$state_user" != "$current_user" ]]; then
        state_user_home="$(_smoke_home_for_user "$state_user" 2>/dev/null || true)"
        [[ "$state_user_home" == "$current_home" ]] || return 1
    fi

    printf '%s\n' "$candidate"
}

_SMOKE_BOOTSTRAP_STATE_FILE="$(_smoke_resolve_bootstrap_state_file 2>/dev/null || true)"
_SMOKE_TARGET_USER_DEFAULTED=false

# Target user (from install.sh, persisted state, home ownership, or default)
_SMOKE_TARGET_USER="${TARGET_USER:-}"
if [[ -z "${_SMOKE_TARGET_USER:-}" ]]; then
    _SMOKE_TARGET_USER="$(_smoke_read_state_string "$_SMOKE_BOOTSTRAP_STATE_FILE" "target_user" 2>/dev/null || true)"
fi
if [[ -z "${_SMOKE_TARGET_USER:-}" ]]; then
    _SMOKE_TARGET_USER="ubuntu"
    _SMOKE_TARGET_USER_DEFAULTED=true
fi

_SMOKE_TARGET_HOME=""
if [[ "$_SMOKE_TARGET_USER_DEFAULTED" == true ]] && [[ "$_SMOKE_SYSTEM_STATE_WAS_EXPLICIT" == true ]]; then
    _SMOKE_TARGET_HOME="$(_smoke_read_state_string "$_SMOKE_SYSTEM_STATE_FILE" "target_home" 2>/dev/null || true)"
    _SMOKE_TARGET_HOME="$(_smoke_sanitize_abs_nonroot_path "${_SMOKE_TARGET_HOME:-}" 2>/dev/null || true)"
fi
if [[ -z "${_SMOKE_TARGET_HOME:-}" ]]; then
    _smoke_target_passwd_entry="$(_smoke_getent_passwd_entry "$_SMOKE_TARGET_USER" || true)"
    if [[ -n "$_smoke_target_passwd_entry" ]]; then
        _SMOKE_TARGET_HOME="$(_smoke_sanitize_abs_nonroot_path "$(_smoke_passwd_home_from_entry "$_smoke_target_passwd_entry" 2>/dev/null || true)" 2>/dev/null || true)"
    elif [[ "${_SMOKE_TARGET_USER}" == "root" ]]; then
        _SMOKE_TARGET_HOME="/root"
    elif [[ -n "${_SMOKE_CURRENT_USER:-}" ]] && [[ "${_SMOKE_TARGET_USER}" == "${_SMOKE_CURRENT_USER}" ]] && [[ -n "${_SMOKE_CURRENT_HOME:-}" ]]; then
        _SMOKE_TARGET_HOME="$_SMOKE_CURRENT_HOME"
    fi
fi
unset _smoke_target_passwd_entry
if [[ -z "${_SMOKE_TARGET_HOME:-}" ]]; then
    _SMOKE_TARGET_HOME="$(_smoke_sanitize_abs_nonroot_path "${TARGET_HOME:-}" 2>/dev/null || true)"
fi
if [[ -z "${_SMOKE_TARGET_HOME:-}" ]]; then
    _SMOKE_TARGET_HOME="$(_smoke_read_state_string "$_SMOKE_BOOTSTRAP_STATE_FILE" "target_home" 2>/dev/null || true)"
    _SMOKE_TARGET_HOME="$(_smoke_sanitize_abs_nonroot_path "${_SMOKE_TARGET_HOME:-}" 2>/dev/null || true)"
fi
if [[ "${_SMOKE_TARGET_HOME:-}" != /* ]]; then
    if [[ "${_SMOKE_TARGET_USER}" == "root" ]]; then
        _SMOKE_TARGET_HOME="/root"
    elif [[ -n "${_SMOKE_CURRENT_USER:-}" ]] && [[ "${_SMOKE_TARGET_USER}" == "${_SMOKE_CURRENT_USER}" ]] && [[ -n "${_SMOKE_CURRENT_HOME:-}" ]]; then
        _SMOKE_TARGET_HOME="$_SMOKE_CURRENT_HOME"
    else
        _SMOKE_TARGET_HOME=""
    fi
fi
if [[ "$_SMOKE_TARGET_USER_DEFAULTED" == true ]] && [[ -n "${_SMOKE_TARGET_HOME:-}" ]]; then
    _smoke_inferred_target_user="$(_smoke_read_user_for_home "$_SMOKE_TARGET_HOME" 2>/dev/null || true)"
    if [[ -n "$_smoke_inferred_target_user" ]]; then
        _SMOKE_TARGET_USER="$_smoke_inferred_target_user"
        _SMOKE_TARGET_USER_DEFAULTED=false
    fi
    unset _smoke_inferred_target_user
fi
if [[ ! "$_SMOKE_TARGET_USER" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
    _SMOKE_TARGET_USER="ubuntu"
fi

_smoke_resolve_state_file() {
    local candidate=""
    local explicit_state_file=""
    local target_state_file=""
    local current_state_file=""
    local env_state_file=""

    candidate="$(_smoke_script_acfs_home 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        current_state_file="$candidate/state.json"
        if [[ -f "$current_state_file" ]]; then
            printf '%s\n' "$current_state_file"
            return 0
        fi
    fi

    if [[ -n "${_SMOKE_TARGET_HOME:-}" ]]; then
        target_state_file="${_SMOKE_TARGET_HOME}/.acfs/state.json"
        if [[ -f "$target_state_file" ]]; then
            printf '%s\n' "$target_state_file"
            return 0
        fi
    fi

    if [[ -n "$_SMOKE_EXPLICIT_ACFS_HOME" ]]; then
        explicit_state_file="$_SMOKE_EXPLICIT_ACFS_HOME/state.json"
        if [[ -f "$explicit_state_file" ]]; then
            printf '%s\n' "$explicit_state_file"
            return 0
        fi
    fi

    if [[ -f "$_SMOKE_SYSTEM_STATE_FILE" ]]; then
        printf '%s\n' "$_SMOKE_SYSTEM_STATE_FILE"
        return 0
    fi

    if [[ -n "$_SMOKE_DEFAULT_ACFS_HOME" ]]; then
        current_state_file="$_SMOKE_DEFAULT_ACFS_HOME/state.json"
        if [[ -f "$current_state_file" ]]; then
            printf '%s\n' "$current_state_file"
            return 0
        fi
    fi

    env_state_file="$(_smoke_sanitize_abs_nonroot_path "${ACFS_STATE_FILE:-}" 2>/dev/null || true)"
    if [[ -n "$env_state_file" ]] && [[ -f "$env_state_file" ]]; then
        printf '%s\n' "$env_state_file"
        return 0
    fi

    candidate="${env_state_file:-${current_state_file:-${target_state_file:-$explicit_state_file}}}"
    printf '%s\n' "$candidate"
}

_smoke_state_file_path_target_home() {
    local state_file="${1:-}"
    local data_home=""
    local path_home=""
    local state_home=""
    local candidate_user=""

    [[ "$state_file" == */.acfs/state.json ]] || return 1
    data_home="${state_file%/state.json}"
    data_home="$(_smoke_sanitize_abs_nonroot_path "$data_home" 2>/dev/null || true)"
    [[ -n "$data_home" ]] || return 1
    path_home="${data_home%/.acfs}"

    candidate_user="$(_smoke_read_user_for_home "$path_home" 2>/dev/null || true)"
    if [[ -n "$candidate_user" ]]; then
        printf '%s\n' "$path_home"
        return 0
    fi

    state_home="$(_smoke_read_state_string "$state_file" "target_home" 2>/dev/null || true)"
    state_home="$(_smoke_sanitize_abs_nonroot_path "$state_home" 2>/dev/null || true)"
    if [[ -n "$state_home" ]] && [[ "$state_home" == "$path_home" ]]; then
        printf '%s\n' "$path_home"
        return 0
    fi

    if [[ -n "$_SMOKE_EXPLICIT_ACFS_HOME" ]] && [[ "$state_file" == "$_SMOKE_EXPLICIT_ACFS_HOME/state.json" ]] && [[ -d "$path_home/.local/bin" ]]; then
        printf '%s\n' "$path_home"
        return 0
    fi

    return 1
}

_smoke_repair_target_context_from_resolved_state() {
    local state_file=""
    local default_state_file=""
    local candidate_user=""
    local candidate_home=""
    local resolved_home=""
    local path_home=""
    local state_candidate_user=""
    local state_home=""
    local system_home=""
    local system_user=""

    state_file="$(_smoke_resolve_state_file 2>/dev/null || true)"
    [[ -n "$state_file" ]] || return 0

    if [[ -n "$_SMOKE_DEFAULT_ACFS_HOME" ]]; then
        default_state_file="$_SMOKE_DEFAULT_ACFS_HOME/state.json"
    fi
    if [[ -n "$default_state_file" ]] && [[ "$state_file" == "$default_state_file" ]]         && [[ "$_SMOKE_TARGET_USER_DEFAULTED" != true ]]         && [[ -z "${TARGET_HOME:-}" ]]         && [[ -z "$_SMOKE_EXPLICIT_ACFS_HOME" ]]         && [[ ! -f "$_SMOKE_SYSTEM_STATE_FILE" ]]; then
        return 0
    fi

    state_home="$(_smoke_read_state_string "$state_file" "target_home" 2>/dev/null || true)"
    state_home="$(_smoke_sanitize_abs_nonroot_path "$state_home" 2>/dev/null || true)"
    path_home="$(_smoke_state_file_path_target_home "$state_file" 2>/dev/null || true)"
    system_home="$(_smoke_read_state_string "$_SMOKE_SYSTEM_STATE_FILE" "target_home" 2>/dev/null || true)"
    system_home="$(_smoke_sanitize_abs_nonroot_path "$system_home" 2>/dev/null || true)"
    system_user="$(_smoke_read_state_string "$_SMOKE_SYSTEM_STATE_FILE" "target_user" 2>/dev/null || true)"

    if [[ -n "$path_home" ]]; then
        candidate_user="$(_smoke_read_user_for_home "$path_home" 2>/dev/null || true)"
        if [[ -n "$candidate_user" ]]; then
            resolved_home="$path_home"
        fi
    fi

    if [[ -z "$candidate_user" ]] && [[ -n "$system_user" ]] && [[ -n "$system_home" ]] && { [[ -z "$path_home" ]] || [[ "$path_home" == "$system_home" ]]; }; then
        if [[ -n "$path_home" ]] || [[ -z "$state_home" ]] || [[ "$state_home" == "$system_home" ]] || [[ -z "$_SMOKE_EXPLICIT_ACFS_HOME" ]] || [[ "$state_file" != "$_SMOKE_EXPLICIT_ACFS_HOME/state.json" ]]; then
            candidate_user="$system_user"
            resolved_home="$system_home"
        fi
    fi

    if [[ -z "$candidate_user" ]] && [[ -n "$state_home" ]] && [[ -z "$path_home" || "$state_home" == "$path_home" ]]; then
        candidate_user="$(_smoke_read_user_for_home "$state_home" 2>/dev/null || true)"
        if [[ -n "$candidate_user" ]]; then
            resolved_home="$state_home"
        fi
    fi

    state_candidate_user="$(_smoke_read_state_string "$state_file" "target_user" 2>/dev/null || true)"
    if [[ -z "$candidate_user" ]] && [[ -n "$state_candidate_user" ]]; then
        if [[ -z "$state_home" ]]; then
            candidate_user="$state_candidate_user"
        else
            candidate_home="$(_smoke_home_for_user "$state_candidate_user" 2>/dev/null || true)"
            if [[ -n "$path_home" ]] && [[ "$candidate_home" == "$path_home" ]]; then
                candidate_user="$state_candidate_user"
                resolved_home="$path_home"
            elif [[ -n "$state_home" ]] && [[ -z "$path_home" || "$state_home" == "$path_home" ]] && [[ "$candidate_home" == "$state_home" ]]; then
                candidate_user="$state_candidate_user"
                resolved_home="$state_home"
            elif [[ -z "$path_home" ]] && [[ -n "$state_home" ]] && { [[ -z "$system_home" ]] || [[ "$state_home" == "$system_home" ]] || { [[ -n "$_SMOKE_EXPLICIT_ACFS_HOME" ]] && [[ "$state_file" == "$_SMOKE_EXPLICIT_ACFS_HOME/state.json" ]]; }; }; then
                candidate_user="$state_candidate_user"
                resolved_home="$state_home"
            elif [[ -n "$_SMOKE_EXPLICIT_ACFS_HOME" ]] && [[ "$state_file" == "$_SMOKE_EXPLICIT_ACFS_HOME/state.json" ]] && [[ -z "$path_home" ]]; then
                candidate_user="$state_candidate_user"
                if [[ -n "$state_home" ]]; then
                    resolved_home="$state_home"
                fi
            fi
        fi
    fi

    if [[ -z "$candidate_user" ]] && [[ -n "$system_user" ]] && [[ -z "$system_home" ]]; then
        candidate_user="$system_user"
    fi

    if [[ -z "$resolved_home" ]] && [[ -n "$path_home" ]]; then
        resolved_home="$path_home"
    fi
    if [[ -z "$resolved_home" ]] && [[ -n "$system_home" ]] && { [[ -z "$path_home" ]] || [[ "$path_home" == "$system_home" ]]; }; then
        if [[ -n "$path_home" ]] || [[ -z "$state_home" ]] || [[ "$state_home" == "$system_home" ]] || [[ -z "$_SMOKE_EXPLICIT_ACFS_HOME" ]] || [[ "$state_file" != "$_SMOKE_EXPLICIT_ACFS_HOME/state.json" ]]; then
            resolved_home="$system_home"
        fi
    fi
    if [[ -z "$resolved_home" ]] && [[ -n "$state_home" ]]; then
        resolved_home="$state_home"
    fi
    if [[ -z "$resolved_home" ]] && [[ -n "$candidate_user" ]]; then
        resolved_home="$(_smoke_home_for_user "$candidate_user" 2>/dev/null || true)"
    fi

    if [[ -n "$candidate_user" ]] && [[ "$candidate_user" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
        _SMOKE_TARGET_USER="$candidate_user"
        _SMOKE_TARGET_USER_DEFAULTED=false
    fi

    if [[ -n "$resolved_home" ]]; then
        _SMOKE_TARGET_HOME="$resolved_home"
    fi
}

_smoke_repair_target_context_from_resolved_state

_smoke_read_bin_dir_from_state() {
    local state_file="${1:-}"
    local bin_dir=""

    [[ -n "$state_file" ]] || return 1

    bin_dir="$(_smoke_read_state_string "$state_file" "bin_dir" 2>/dev/null || true)"
    bin_dir="$(_smoke_sanitize_abs_nonroot_path "$bin_dir" 2>/dev/null || true)"
    [[ -n "$bin_dir" ]] || return 1
    printf '%s\n' "$bin_dir"
}

_smoke_validate_bin_dir_for_home() {
    local bin_dir="${1:-}"
    local base_home="${2:-}"
    local passwd_line=""
    local passwd_home=""
    local hinted_home=""

    bin_dir="$(_smoke_sanitize_abs_nonroot_path "$bin_dir" 2>/dev/null || true)"
    [[ -n "$bin_dir" ]] || return 1
    base_home="$(_smoke_sanitize_abs_nonroot_path "$base_home" 2>/dev/null || true)"

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
    hinted_home=$(_smoke_sanitize_abs_nonroot_path "$hinted_home" 2>/dev/null || true)
    if [[ -n "$hinted_home" ]] && [[ -n "$base_home" ]] && [[ "$hinted_home" != "$base_home" ]]; then
        return 1
    fi

    while IFS= read -r passwd_line; do
        passwd_home="$(_smoke_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
        passwd_home="$(_smoke_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
        [[ -n "$passwd_home" ]] || continue
        [[ -n "$base_home" && "$passwd_home" == "$base_home" ]] && continue
        if [[ "$bin_dir" == "$passwd_home" || "$bin_dir" == "$passwd_home/"* ]]; then
            return 1
        fi
    done < <(_smoke_getent_passwd_entry 2>/dev/null || true)

    printf '%s\n' "$bin_dir"
}

_smoke_preferred_bin_dir() {
    local base_home="${1:-${_SMOKE_TARGET_HOME:-}}"
    local state_file=""
    local candidate=""

    state_file="$(_smoke_resolve_state_file 2>/dev/null || true)"

    candidate="$(_smoke_read_bin_dir_from_state "$state_file" 2>/dev/null || true)"
    candidate="$(_smoke_validate_bin_dir_for_home "$candidate" "$base_home" 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    candidate="$(_smoke_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$base_home" 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    [[ -n "$base_home" ]] || return 1
    printf '%s\n' "$base_home/.local/bin"
}

_smoke_prepend_user_paths() {
    local base_home="$1"
    local dir=""
    local primary_bin_dir=""
    local current_path="${PATH:-}"
    local seen_path=":${current_path}:"
    local -a to_prepend=()

    [[ -n "$base_home" ]] || return 0
    primary_bin_dir="$(_smoke_preferred_bin_dir "$base_home" 2>/dev/null || true)"
    [[ -n "$primary_bin_dir" ]] || primary_bin_dir="$base_home/.local/bin"

    for dir in \
        "$primary_bin_dir" \
        "$base_home/.local/bin" \
        "$base_home/.acfs/bin" \
        "$base_home/.bun/bin" \
        "$base_home/.cargo/bin" \
        "$base_home/.atuin/bin" \
        "$base_home/go/bin" \
        "$base_home/google-cloud-sdk/bin"; do
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

_smoke_binary_path() {
    local name="${1:-}"
    local base_home="${_SMOKE_TARGET_HOME:-}"
    local primary_bin_dir=""
    local candidate=""

    [[ -n "$name" ]] || return 1
    [[ -n "$base_home" ]] || return 1
    primary_bin_dir="$(_smoke_preferred_bin_dir "$base_home" 2>/dev/null || true)"
    [[ -n "$primary_bin_dir" ]] || primary_bin_dir="$base_home/.local/bin"

    for candidate in \
        "$primary_bin_dir/$name" \
        "$base_home/.local/bin/$name" \
        "$base_home/.acfs/bin/$name" \
        "$base_home/.bun/bin/$name" \
        "$base_home/.cargo/bin/$name" \
        "$base_home/.atuin/bin/$name" \
        "$base_home/go/bin/$name" \
        "$base_home/google-cloud-sdk/bin/$name" \
        "$base_home/bin/$name" \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/snap/bin/$name"; do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

_smoke_binary_exists() {
    local resolved=""
    resolved="$(_smoke_binary_path "$1" 2>/dev/null || true)"
    [[ -n "$resolved" ]]
}

_smoke_get_local_passwd_entry() {
    local user="${1:-}"
    local passwd_line=""

    [[ -n "$user" ]] || return 1
    [[ -r /etc/passwd ]] || return 1

    while IFS= read -r passwd_line; do
        [[ "${passwd_line%%:*}" == "$user" ]] || continue
        printf '%s\n' "$passwd_line"
        return 0
    done < /etc/passwd

    return 1
}

_smoke_is_externally_managed_user() {
    local user="${1:-}"
    local passwd_entry=""
    local local_entry=""

    [[ -n "$user" ]] || return 1
    passwd_entry="$(_smoke_getent_passwd_entry "$user" || true)"
    [[ -n "$passwd_entry" ]] || return 1

    local_entry="$(_smoke_get_local_passwd_entry "$user" || true)"
    [[ -z "$local_entry" ]]
}

_smoke_external_shell_handoff_configured() {
    local target_home="${1:-}"
    local bashrc_path=""

    [[ -n "$target_home" ]] || return 1
    bashrc_path="$target_home/.bashrc"
    [[ -f "$bashrc_path" ]] || return 1

    awk '
        $0 == "# ACFS externally-managed shell handoff" { marker=1; next }
        marker && $0 ~ /^[[:space:]]*#/ { next }
        marker && index($0, "command -v zsh") && index($0, "ACFS_ZSH_HANDOFF_ACTIVE") { found=1; exit }
        marker && $0 !~ /^[[:space:]]*$/ { marker=0 }
        END { exit(found ? 0 : 1) }
    ' "$bashrc_path" 2>/dev/null
}

# ============================================================
# Output Helpers
# ============================================================

# Use ${var-default} (not ${var:-default}) to preserve empty strings for NO_COLOR.
# Related: bd-39ye
_smoke_pass() {
    local label="$1"
    echo -e "  ${ACFS_GREEN-\033[0;32m}✅${ACFS_NC-\033[0m} $label"
    ((_SMOKE_CRITICAL_PASS += 1))
}

_smoke_fail() {
    local label="$1"
    local fix="${2:-}"
    echo -e "  ${ACFS_RED-\033[0;31m}❌${ACFS_NC-\033[0m} $label"
    if [[ -n "$fix" ]]; then
        echo -e "     ${ACFS_GRAY-\033[0;90m}Fix: $fix${ACFS_NC-\033[0m}"
    fi
    ((_SMOKE_CRITICAL_FAIL += 1))
}

_smoke_warn() {
    local label="$1"
    local note="${2:-}"
    echo -e "  ${ACFS_YELLOW-\033[0;33m}⚠️${ACFS_NC-\033[0m} $label"
    if [[ -n "$note" ]]; then
        echo -e "     ${ACFS_GRAY-\033[0;90m}$note${ACFS_NC-\033[0m}"
    fi
    ((_SMOKE_WARNING_COUNT += 1))
}

# Non-critical pass (doesn't affect critical count)
_smoke_info() {
    local label="$1"
    echo -e "  ${ACFS_GREEN-\033[0;32m}✅${ACFS_NC-\033[0m} $label"
    ((_SMOKE_NONCRITICAL_PASS += 1))
}

_smoke_header() {
    echo ""
    echo -e "${ACFS_BLUE-\033[0;34m}[Smoke Test]${ACFS_NC-\033[0m}"
    echo ""
}

# ============================================================
# Critical Checks (must pass)
# ============================================================

# Check 1: User is ubuntu
_check_user() {
    local current_user=""
    current_user="$(_smoke_resolve_current_user 2>/dev/null || true)"
    if [[ "$current_user" == "$_SMOKE_TARGET_USER" ]]; then
        _smoke_pass "User: $_SMOKE_TARGET_USER"
        return 0
    else
        _smoke_fail "User: expected $_SMOKE_TARGET_USER, got $current_user" "ssh $_SMOKE_TARGET_USER@YOUR_SERVER"
        return 1
    fi
}

# Check 2: Shell is zsh
_check_shell() {
    local shell=""
    local passwd_entry=""

    passwd_entry="$(_smoke_getent_passwd_entry "$_SMOKE_TARGET_USER" || true)"
    [[ -n "$passwd_entry" ]] && shell="$(_smoke_passwd_shell_from_entry "$passwd_entry" 2>/dev/null || true)"
    # Check if configured shell is zsh (the actual login shell, not just that zsh exists)
    if [[ "$shell" == *"zsh"* ]]; then
        _smoke_pass "Shell: zsh"
        return 0
    elif _smoke_is_externally_managed_user "$_SMOKE_TARGET_USER"; then
        if _smoke_external_shell_handoff_configured "$_SMOKE_TARGET_HOME"; then
            _smoke_pass "Shell: externally managed login hands off to zsh"
        else
            _smoke_warn "Shell: externally managed account reports ${shell:-unknown}" \
                "Local chsh is not valid here; configure the identity provider shell or add the ACFS bash-to-zsh handoff."
        fi
        return 0
    else
        _smoke_fail "Shell: expected zsh, got $shell" "chsh -s \$(which zsh)"
        return 1
    fi
}

# Check 3: Passwordless sudo works
_check_sudo() {
    if sudo -n true 2>/dev/null; then
        _smoke_pass "Sudo: passwordless"
        return 0
    else
        _smoke_fail "Sudo: requires password" "Re-run installer with --mode vibe"
        return 1
    fi
}

# Check 4: /data/projects exists
_check_workspace() {
    if [[ -d "/data/projects" ]]; then
        _smoke_pass "Workspace: /data/projects exists"
        return 0
    else
        _smoke_fail "Workspace: /data/projects missing" "sudo mkdir -p /data/projects && sudo chown $_SMOKE_TARGET_USER:$_SMOKE_TARGET_USER /data/projects"
        return 1
    fi
}

# Check 5: Language runtimes available
_check_languages() {
    local missing=()

    _smoke_binary_exists "bun" || missing+=("bun")
    _smoke_binary_exists "uv" || missing+=("uv")
    _smoke_binary_exists "cargo" || missing+=("cargo")
    _smoke_binary_exists "go" || missing+=("go")

    if [[ ${#missing[@]} -eq 0 ]]; then
        _smoke_pass "Languages: bun, uv, cargo, go"
        return 0
    else
        _smoke_fail "Languages: missing ${missing[*]}" "Re-run installer"
        return 1
    fi
}

# Check 6: Agent CLIs exist
_check_agents() {
    local found=()
    local missing=()

    # Check for each agent CLI
    if _smoke_binary_exists "claude"; then
        found+=("claude")
    else
        missing+=("claude")
    fi

    if _smoke_binary_exists "codex"; then
        found+=("codex")
    else
        missing+=("codex")
    fi

    if _smoke_binary_exists "gemini"; then
        found+=("gemini")
    else
        missing+=("gemini")
    fi

    if [[ ${#missing[@]} -eq 0 ]]; then
        _smoke_pass "Agents: ${found[*]}"
        return 0
    elif [[ ${#found[@]} -gt 0 ]]; then
        # At least one agent found
        _smoke_pass "Agents: ${found[*]}"
        _smoke_warn "Missing agents: ${missing[*]}" "May need manual installation"
        return 0
    else
        _smoke_fail "Agents: none found" "bun install -g --trust @openai/codex@latest @google/gemini-cli@latest"
        return 1
    fi
}

# Check 7: NTM command works
_check_ntm() {
    local ntm_bin=""
    ntm_bin="$(_smoke_binary_path "ntm" 2>/dev/null || true)"
    if [[ -n "$ntm_bin" ]] && "$ntm_bin" --help >/dev/null 2>&1; then
        _smoke_pass "NTM: installed"
        return 0
    else
        _smoke_fail "NTM: not found" "Re-run: curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --force-reinstall --only stack.ntm"
        return 1
    fi
}

# Check 8: Onboard command exists
_check_onboard() {
    if _smoke_binary_exists "onboard"; then
        _smoke_pass "Onboard: installed"
        return 0
    else
        _smoke_fail "Onboard: not found" "Check ~/.acfs/bin/onboard"
        return 1
    fi
}

# ============================================================
# Non-Critical Checks (warn only)
# ============================================================

# Check: Agent Mail can respond
_check_agent_mail() {
    if _smoke_system_curl -fsS --max-time 5 http://127.0.0.1:8765/health/liveness &>/dev/null; then
        _smoke_info "Agent Mail: running"
    else
        _smoke_warn "Agent Mail: not running" "re-run ACFS update/install to rewrite agent-mail.service, then run 'systemctl --user enable --now agent-mail.service'"
    fi
}

# Check: Stack tools respond to --help
_check_stack_tools() {
    local stack_tools=("slb" "ubs" "bv" "cass" "cm" "caam")
    local found=()
    local missing=()

    for tool in "${stack_tools[@]}"; do
        if _smoke_binary_exists "$tool"; then
            found+=("$tool")
        else
            missing+=("$tool")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        _smoke_info "Stack tools: all installed"
    else
        _smoke_warn "Stack tools missing: ${missing[*]}" "Some tools may need manual install"
    fi
}

# Check: PostgreSQL running
_check_postgres() {
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        _smoke_info "PostgreSQL: running"
    elif _smoke_binary_exists "psql"; then
        _smoke_warn "PostgreSQL: installed but not running" "sudo systemctl start postgresql"
    else
        _smoke_warn "PostgreSQL: not installed" "optional - install with apt"
    fi
}

# ============================================================
# Main Smoke Test Function
# ============================================================

run_smoke_test() {
    # Reset counters (important if run multiple times in same shell)
    _SMOKE_CRITICAL_PASS=0
    _SMOKE_CRITICAL_FAIL=0
    _SMOKE_NONCRITICAL_PASS=0
    _SMOKE_WARNING_COUNT=0

    local original_path="$PATH"

    _smoke_prepend_user_paths "$_SMOKE_TARGET_HOME"
    if [[ -n "${_SMOKE_CURRENT_HOME:-}" ]] && [[ "$_SMOKE_CURRENT_HOME" != "$_SMOKE_TARGET_HOME" ]]; then
        _smoke_prepend_user_paths "$_SMOKE_CURRENT_HOME"
    fi

    local start_time
    start_time=$(date +%s)

    _smoke_header

    echo "Critical Checks:"

    # Run all critical checks
    _check_user
    _check_shell
    _check_sudo
    _check_workspace
    _check_languages
    _check_agents
    _check_ntm
    _check_onboard

    echo ""
    echo "Non-Critical Checks:"

    # Run non-critical checks
    _check_agent_mail
    _check_stack_tools
    _check_postgres

    # Calculate duration
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Print summary
    echo ""
    local total_critical=$((_SMOKE_CRITICAL_PASS + _SMOKE_CRITICAL_FAIL))

    if [[ $_SMOKE_CRITICAL_FAIL -eq 0 ]]; then
        echo -e "${ACFS_GREEN-\033[0;32m}Smoke test: $_SMOKE_CRITICAL_PASS/$total_critical critical passed${ACFS_NC-\033[0m}"
    else
        echo -e "${ACFS_RED-\033[0;31m}Smoke test: $_SMOKE_CRITICAL_PASS/$total_critical critical passed, $_SMOKE_CRITICAL_FAIL failed${ACFS_NC-\033[0m}"
    fi

    if [[ $_SMOKE_WARNING_COUNT -gt 0 ]]; then
        echo -e "${ACFS_YELLOW-\033[0;33m}$_SMOKE_WARNING_COUNT warning(s)${ACFS_NC-\033[0m}"
    fi

    echo -e "${ACFS_GRAY-\033[0;90m}Completed in ${duration}s${ACFS_NC-\033[0m}"
    echo ""

    if [[ "$_SMOKE_WAS_SOURCED" == "true" ]]; then
        PATH="$original_path"
        export PATH
    fi

    # Return exit code based on critical failures
    if [[ $_SMOKE_CRITICAL_FAIL -gt 0 ]]; then
        echo -e "${ACFS_YELLOW-\033[0;33m}Some critical checks failed. Run 'acfs doctor' for detailed diagnostics.${ACFS_NC-\033[0m}"
        return 1
    fi

    echo -e "${ACFS_GREEN-\033[0;32m}Installation successful! Run 'onboard' to start the tutorial.${ACFS_NC-\033[0m}"
    return 0
}

_smoke_restore_home_if_sourced() {
    [[ "$_SMOKE_WAS_SOURCED" == "true" ]] || return 0

    if [[ "$_SMOKE_ORIGINAL_HOME_WAS_SET" == "true" ]]; then
        HOME="$_SMOKE_ORIGINAL_HOME"
        export HOME
    else
        unset HOME
    fi
}

_smoke_restore_home_if_sourced

# ============================================================
# Module can be sourced or run directly
# ============================================================

# If run directly (not sourced), execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_smoke_test "$@"
fi
