#!/usr/bin/env bash
# ============================================================
# ACFS Dashboard - Static HTML Generation & Serving
#
# Generates a local HTML dashboard using `acfs info --html`
# and optionally serves it via a temporary HTTP server.
#
# Usage:
#   acfs dashboard generate [--force]
#   acfs dashboard serve [--port PORT]
# ============================================================

_DASHBOARD_WAS_SOURCED=false
_DASHBOARD_ORIGINAL_HOME=""
_DASHBOARD_ORIGINAL_HOME_WAS_SET=false
_DASHBOARD_RESTORE_ERREXIT=false
_DASHBOARD_RESTORE_NOUNSET=false
_DASHBOARD_RESTORE_PIPEFAIL=false
if [[ -v HOME ]]; then
    _DASHBOARD_ORIGINAL_HOME="$HOME"
    _DASHBOARD_ORIGINAL_HOME_WAS_SET=true
fi
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    _DASHBOARD_WAS_SOURCED=true
    [[ $- == *e* ]] && _DASHBOARD_RESTORE_ERREXIT=true
    [[ $- == *u* ]] && _DASHBOARD_RESTORE_NOUNSET=true
    if shopt -qo pipefail 2>/dev/null; then
        _DASHBOARD_RESTORE_PIPEFAIL=true
    fi
fi

set -euo pipefail

dashboard_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

dashboard_remove_temp_file() {
    local tmp_file="${1:-}"
    if [[ -n "$tmp_file" && -e "$tmp_file" ]]; then
        rm -f -- "$tmp_file" 2>/dev/null || true
    fi
}

dashboard_existing_abs_home() {
    local path_value=""

    path_value="$(dashboard_sanitize_abs_nonroot_path "${1:-}" 2>/dev/null || true)"
    [[ -n "$path_value" ]] || return 1
    [[ -d "$path_value" ]] || return 1
    printf '%s\n' "$path_value"
}

dashboard_system_binary_path() {
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

dashboard_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(dashboard_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(dashboard_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

dashboard_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(dashboard_system_binary_path getent 2>/dev/null || true)"
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

dashboard_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    passwd_home="$(dashboard_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
    [[ -n "$passwd_home" ]] || return 1
    printf '%s\n' "$passwd_home"
}
dashboard_is_valid_username() {
    local username="${1:-}"
    [[ "$username" =~ ^[a-z_][a-z0-9._-]*$ ]]
}

dashboard_resolve_current_home() {
    local current_user=""
    local fallback_home=""
    local passwd_entry=""
    local passwd_home=""
    fallback_home="$(dashboard_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
    if [[ "${_DASHBOARD_WAS_SOURCED:-false}" == "true" ]]; then
        fallback_home="$(dashboard_sanitize_abs_nonroot_path "${_DASHBOARD_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
    fi
    current_user="$(dashboard_resolve_current_user 2>/dev/null || true)"

    if [[ "$current_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    if [[ -n "$current_user" ]]; then
        passwd_entry="$(dashboard_getent_passwd_entry "$current_user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            passwd_home="$(dashboard_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
            if [[ -n "$passwd_home" ]]; then
                printf '%s\n' "$passwd_home"
                return 0
            fi
        fi
    fi

    [[ -n "$fallback_home" ]] || return 1
    printf '%s\n' "$fallback_home"
}
dashboard_initial_current_home() {
    local cached_home=""
    local resolved_home=""

    if [[ "${_DASHBOARD_WAS_SOURCED:-false}" == "true" ]] && [[ -z "${TARGET_HOME:-}${TARGET_USER:-}${ACFS_HOME:-}${ACFS_STATE_FILE:-}${ACFS_SYSTEM_STATE_FILE:-}" ]]; then
        cached_home="$(dashboard_sanitize_abs_nonroot_path "${_DASHBOARD_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
        if [[ -n "$cached_home" ]]; then
            printf '%s\n' "$cached_home"
            return 0
        fi
    fi

    resolved_home="$(dashboard_resolve_current_home 2>/dev/null || true)"
    if [[ -n "$resolved_home" ]]; then
        printf '%s\n' "$resolved_home"
        return 0
    fi

    if [[ "${_DASHBOARD_WAS_SOURCED:-false}" == "true" ]]; then
        cached_home="$(dashboard_sanitize_abs_nonroot_path "${_DASHBOARD_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
        if [[ -n "$cached_home" ]]; then
            printf '%s\n' "$cached_home"
            return 0
        fi
    fi

    return 1
}
_DASHBOARD_CURRENT_HOME="$(dashboard_initial_current_home 2>/dev/null || true)"
if [[ -n "$_DASHBOARD_CURRENT_HOME" ]]; then
    HOME="$_DASHBOARD_CURRENT_HOME"
    export HOME
fi

_DASHBOARD_EXPLICIT_ACFS_HOME="$(dashboard_sanitize_abs_nonroot_path "${ACFS_HOME:-}" 2>/dev/null || true)"
_DASHBOARD_DEFAULT_ACFS_HOME=""
[[ -n "$_DASHBOARD_CURRENT_HOME" ]] && _DASHBOARD_DEFAULT_ACFS_HOME="${_DASHBOARD_CURRENT_HOME}/.acfs"
_DASHBOARD_ACFS_HOME="${_DASHBOARD_EXPLICIT_ACFS_HOME:-$_DASHBOARD_DEFAULT_ACFS_HOME}"
_DASHBOARD_SYSTEM_STATE_WAS_EXPLICIT=false
[[ -n "${ACFS_SYSTEM_STATE_FILE:-}" ]] && [[ "${ACFS_SYSTEM_STATE_FILE%/}" != "/var/lib/acfs/state.json" ]] && _DASHBOARD_SYSTEM_STATE_WAS_EXPLICIT=true
_DASHBOARD_SYSTEM_STATE_FILE="$(dashboard_sanitize_abs_nonroot_path "${ACFS_SYSTEM_STATE_FILE:-/var/lib/acfs/state.json}" 2>/dev/null || true)"
if [[ -z "$_DASHBOARD_SYSTEM_STATE_FILE" ]]; then
    _DASHBOARD_SYSTEM_STATE_FILE="/var/lib/acfs/state.json"
fi
_DASHBOARD_EXPLICIT_TARGET_HOME_RAW="${TARGET_HOME:-}"
_DASHBOARD_EXPLICIT_TARGET_USER_RAW="${TARGET_USER:-}"
_DASHBOARD_EXPLICIT_TARGET_HOME="$(dashboard_existing_abs_home "${TARGET_HOME:-}" 2>/dev/null || true)"
_DASHBOARD_RESOLVED_ACFS_HOME=""
_DASHBOARD_RESOLVED_ACFS_HOME_SOURCE=""
_DASHBOARD_RESOLVED_TARGET_USER=""
_DASHBOARD_RESOLVED_TARGET_HOME=""

dashboard_usage() {
    echo "Usage: acfs dashboard <command>"
    echo ""
    echo "Commands:"
    echo "  generate [--force]   Generate ~/.acfs/dashboard/index.html"
    echo "  serve [--port PORT] [--host HOST] [--public]  Start a temporary HTTP server for the dashboard"
    echo "  help                 Show this help"
}

dashboard_home_for_user() {
    local user="$1"
    local passwd_entry=""
    local home_candidate=""
    local current_user=""

    [[ -n "$user" ]] || return 1

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    passwd_entry="$(dashboard_getent_passwd_entry "$user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        home_candidate="$(dashboard_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
        if [[ -n "$home_candidate" ]]; then
            printf '%s\n' "$home_candidate"
            return 0
        fi
    fi

    current_user="$(dashboard_resolve_current_user 2>/dev/null || true)"
    if [[ "$user" == "$current_user" ]]; then
        home_candidate="${_DASHBOARD_CURRENT_HOME:-}"
        if [[ -z "$home_candidate" ]]; then
            home_candidate="$(dashboard_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
        fi
        if [[ -n "$home_candidate" ]]; then
            printf '%s\n' "$home_candidate"
            return 0
        fi
    fi

    return 1
}
dashboard_resolve_explicit_target_home() {
    local target_home=""
    local resolved_home=""

    if [[ -n "$_DASHBOARD_EXPLICIT_TARGET_USER_RAW" ]]; then
        dashboard_is_valid_username "$_DASHBOARD_EXPLICIT_TARGET_USER_RAW" || return 1
        resolved_home="$(dashboard_existing_abs_home "$(dashboard_home_for_user "$_DASHBOARD_EXPLICIT_TARGET_USER_RAW" 2>/dev/null || true)" 2>/dev/null || true)"
        if [[ -n "$resolved_home" ]]; then
            printf '%s\n' "${resolved_home%/}"
            return 0
        fi
        target_home="$_DASHBOARD_EXPLICIT_TARGET_HOME"
        if [[ -n "$target_home" ]] && [[ "$target_home" != "${_DASHBOARD_CURRENT_HOME:-}" ]] && dashboard_candidate_has_acfs_data "$target_home/.acfs"; then
            printf '%s\n' "${target_home%/}"
            return 0
        fi
        return 1
    fi

    target_home="$_DASHBOARD_EXPLICIT_TARGET_HOME"
    if [[ -n "$target_home" ]]; then
        printf '%s\n' "${target_home%/}"
        return 0
    fi

    return 1
}

dashboard_read_user_for_home() {
    local user_home="$1"
    local candidate_user=""
    local current_home=""
    local passwd_line=""
    local passwd_home=""
    local state_file=""

    user_home="$(dashboard_sanitize_abs_nonroot_path "$user_home" 2>/dev/null || true)"
    [[ -n "$user_home" ]] || return 1

    while IFS= read -r passwd_line; do
        passwd_home="$(dashboard_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
        [[ "$passwd_home" == "$user_home" ]] || continue
        candidate_user="${passwd_line%%:*}"
        if [[ "$candidate_user" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
    done < <(dashboard_getent_passwd_entry 2>/dev/null || true)

    current_home="${_DASHBOARD_CURRENT_HOME:-}"
    if [[ -n "$current_home" ]] && [[ "$user_home" == "$current_home" ]]; then
        candidate_user="$(dashboard_resolve_current_user 2>/dev/null || true)"
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
    candidate_user="$(dashboard_read_state_string "$state_file" "target_user" 2>/dev/null || true)"
    if [[ -n "$candidate_user" ]]; then
        current_home="$(dashboard_home_for_user "$candidate_user" 2>/dev/null || true)"
        if [[ -n "$current_home" ]] && [[ "$current_home" == "$user_home" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
    fi

    return 1
}
dashboard_read_state_string() {
    local state_file="$1"
    local key="$2"
    local value=""

    [[ -f "$state_file" ]] || return 1

    if command -v jq &>/dev/null; then
        value=$(jq -r --arg key "$key" '.[$key] // empty' "$state_file" 2>/dev/null || true)
    else
        value=$(sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$state_file" 2>/dev/null | head -n 1)
    fi

    [[ -n "$value" ]] && [[ "$value" != "null" ]] || return 1
    printf '%s\n' "$value"
}

dashboard_read_target_home_from_state() {
    local state_file="$1"
    local target_home=""

    target_home="$(dashboard_read_state_string "$state_file" "target_home" 2>/dev/null || true)"
    [[ -n "$target_home" ]] || return 1
    [[ "$target_home" == /* ]] || return 1
    [[ "$target_home" != "/" ]] || return 1
    printf '%s\n' "${target_home%/}"
}

dashboard_candidate_has_acfs_data() {
    local candidate="$1"
    [[ -n "$candidate" ]] || return 1
    [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/dashboard" || -d "$candidate/onboard" || -f "$candidate/scripts/lib/info.sh" ]]
}

dashboard_script_acfs_home() {
    local candidate=""
    candidate=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd) || return 1
    [[ "$(basename "$candidate")" == ".acfs" ]] || return 1
    printf '%s\n' "$candidate"
}

dashboard_current_home_acfs_candidate() {
    local candidate="$_DASHBOARD_DEFAULT_ACFS_HOME"
    local current_home="$_DASHBOARD_CURRENT_HOME"
    local current_user=""
    local original_home=""
    local state_home=""
    local state_user=""
    local state_user_home=""

    [[ -n "$candidate" && -n "$current_home" ]] || return 1
    [[ "$current_home" != "/root" ]] || return 1
    dashboard_candidate_has_acfs_data "$candidate" || return 1

    if [[ "${_DASHBOARD_ORIGINAL_HOME_WAS_SET:-false}" == true ]]; then
        original_home="$(dashboard_sanitize_abs_nonroot_path "$_DASHBOARD_ORIGINAL_HOME" 2>/dev/null || true)"
        [[ -n "$original_home" && "$original_home" == "$current_home" ]] || return 1
    fi

    current_user="$(dashboard_resolve_current_user 2>/dev/null || true)"
    [[ -n "$current_user" && "$current_user" != "root" ]] || return 1

    if [[ -f "$candidate/state.json" ]]; then
        state_home="$(dashboard_read_target_home_from_state "$candidate/state.json" 2>/dev/null || true)"
        [[ -z "$state_home" || "$state_home" == "$current_home" ]] || return 1

        state_user="$(dashboard_read_state_string "$candidate/state.json" "target_user" 2>/dev/null || true)"
        if [[ -n "$state_user" && "$state_user" != "$current_user" ]]; then
            state_user_home="$(dashboard_home_for_user "$state_user" 2>/dev/null || true)"
            [[ "$state_user_home" == "$current_home" ]] || return 1
        fi
    fi

    printf '%s\n' "$candidate"
}

dashboard_resolve_acfs_home() {
    if [[ -n "$_DASHBOARD_RESOLVED_ACFS_HOME" ]]; then
        printf '%s\n' "$_DASHBOARD_RESOLVED_ACFS_HOME"
        return 0
    fi

    local candidate=""
    local target_home=""
    local target_user=""
    local explicit_target_home=""

    _DASHBOARD_RESOLVED_ACFS_HOME_SOURCE=""

    candidate=$(dashboard_script_acfs_home 2>/dev/null || true)
    if dashboard_candidate_has_acfs_data "$candidate"; then
        _DASHBOARD_RESOLVED_ACFS_HOME="$candidate"
        _DASHBOARD_RESOLVED_ACFS_HOME_SOURCE="script_acfs_home"
        printf '%s\n' "$_DASHBOARD_RESOLVED_ACFS_HOME"
        return 0
    fi

    explicit_target_home="$(dashboard_resolve_explicit_target_home 2>/dev/null || true)"
    if [[ -n "$explicit_target_home" ]]; then
        candidate="${explicit_target_home}/.acfs"
        if dashboard_candidate_has_acfs_data "$candidate"; then
            _DASHBOARD_RESOLVED_ACFS_HOME="$candidate"
            _DASHBOARD_RESOLVED_ACFS_HOME_SOURCE="explicit_target_home"
            printf '%s\n' "$_DASHBOARD_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    if [[ ! -f "$_DASHBOARD_SYSTEM_STATE_FILE" ]] && [[ -n "$_DASHBOARD_EXPLICIT_ACFS_HOME" ]] && dashboard_candidate_has_acfs_data "$_DASHBOARD_EXPLICIT_ACFS_HOME"; then
        _DASHBOARD_RESOLVED_ACFS_HOME="$_DASHBOARD_EXPLICIT_ACFS_HOME"
        _DASHBOARD_RESOLVED_ACFS_HOME_SOURCE="explicit_acfs_home"
        printf '%s\n' "$_DASHBOARD_RESOLVED_ACFS_HOME"
        return 0
    fi

    candidate="$(dashboard_current_home_acfs_candidate 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        _DASHBOARD_RESOLVED_ACFS_HOME="$candidate"
        _DASHBOARD_RESOLVED_ACFS_HOME_SOURCE="current_home"
        printf '%s\n' "$_DASHBOARD_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ "$_DASHBOARD_SYSTEM_STATE_WAS_EXPLICIT" == true ]]; then
        target_home=$(dashboard_read_target_home_from_state "$_DASHBOARD_SYSTEM_STATE_FILE" 2>/dev/null || true)
        candidate="${target_home}/.acfs"
        if [[ -n "$target_home" ]] && dashboard_candidate_has_acfs_data "$candidate"; then
            _DASHBOARD_RESOLVED_ACFS_HOME="$candidate"
            _DASHBOARD_RESOLVED_ACFS_HOME_SOURCE="system_state_target_home"
            printf '%s\n' "$_DASHBOARD_RESOLVED_ACFS_HOME"
            return 0
        fi

        target_user=$(dashboard_read_state_string "$_DASHBOARD_SYSTEM_STATE_FILE" "target_user" 2>/dev/null || true)
        if [[ -n "$target_user" ]]; then
            target_home=$(dashboard_home_for_user "$target_user" 2>/dev/null || true)
            candidate="${target_home}/.acfs"
            if [[ -n "$target_home" ]] && dashboard_candidate_has_acfs_data "$candidate"; then
                _DASHBOARD_RESOLVED_ACFS_HOME="$candidate"
                _DASHBOARD_RESOLVED_ACFS_HOME_SOURCE="system_state_target_user"
                printf '%s\n' "$_DASHBOARD_RESOLVED_ACFS_HOME"
                return 0
            fi
        fi
    fi

    if [[ -n "$_DASHBOARD_EXPLICIT_ACFS_HOME" ]] && dashboard_candidate_has_acfs_data "$_DASHBOARD_EXPLICIT_ACFS_HOME"; then
        _DASHBOARD_RESOLVED_ACFS_HOME="$_DASHBOARD_EXPLICIT_ACFS_HOME"
        _DASHBOARD_RESOLVED_ACFS_HOME_SOURCE="explicit_acfs_home"
        printf '%s\n' "$_DASHBOARD_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ -n "$_DASHBOARD_EXPLICIT_TARGET_HOME_RAW" ]] || [[ -n "$_DASHBOARD_EXPLICIT_TARGET_USER_RAW" ]]; then
        return 1
    fi

    if [[ -n "${SUDO_USER:-}" ]]; then
        target_home=$(dashboard_home_for_user "$SUDO_USER" 2>/dev/null || true)
        candidate="${target_home}/.acfs"
        if [[ -n "$target_home" ]] && dashboard_candidate_has_acfs_data "$candidate"; then
            _DASHBOARD_RESOLVED_ACFS_HOME="$candidate"
            _DASHBOARD_RESOLVED_ACFS_HOME_SOURCE="sudo_user_home"
            printf '%s\n' "$_DASHBOARD_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    target_home=$(dashboard_read_target_home_from_state "$_DASHBOARD_SYSTEM_STATE_FILE" 2>/dev/null || true)
    candidate="${target_home}/.acfs"
    if [[ -n "$target_home" ]] && dashboard_candidate_has_acfs_data "$candidate"; then
        _DASHBOARD_RESOLVED_ACFS_HOME="$candidate"
        _DASHBOARD_RESOLVED_ACFS_HOME_SOURCE="system_state_target_home"
        printf '%s\n' "$_DASHBOARD_RESOLVED_ACFS_HOME"
        return 0
    fi

    target_user=$(dashboard_read_state_string "$_DASHBOARD_SYSTEM_STATE_FILE" "target_user" 2>/dev/null || true)
    if [[ -n "$target_user" ]]; then
        if [[ -z "$target_home" ]]; then
            target_home=$(dashboard_home_for_user "$target_user" 2>/dev/null || true)
        fi
        candidate="${target_home}/.acfs"
        if [[ -n "$target_home" ]] && dashboard_candidate_has_acfs_data "$candidate"; then
            _DASHBOARD_RESOLVED_ACFS_HOME="$candidate"
            _DASHBOARD_RESOLVED_ACFS_HOME_SOURCE="system_state_target_user"
            printf '%s\n' "$_DASHBOARD_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    _DASHBOARD_RESOLVED_ACFS_HOME="$_DASHBOARD_DEFAULT_ACFS_HOME"
    _DASHBOARD_RESOLVED_ACFS_HOME_SOURCE="current_home"
    printf '%s\n' "$_DASHBOARD_RESOLVED_ACFS_HOME"
}

dashboard_resolve_state_file() {
    local candidate=""

    if [[ -n "$_DASHBOARD_ACFS_HOME" ]]; then
        candidate="${_DASHBOARD_ACFS_HOME}/state.json"
    fi

    if [[ -n "$candidate" ]] && [[ -f "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    if [[ -f "$_DASHBOARD_SYSTEM_STATE_FILE" ]]; then
        printf '%s\n' "$_DASHBOARD_SYSTEM_STATE_FILE"
        return 0
    fi

    printf '%s\n' "$candidate"
}

dashboard_infer_target_home_from_acfs_home() {
    local acfs_home_candidate=""
    local inferred_home=""

    acfs_home_candidate="$(dashboard_sanitize_abs_nonroot_path "${_DASHBOARD_ACFS_HOME:-}" 2>/dev/null || true)"
    [[ -n "$acfs_home_candidate" ]] || return 1
    [[ "$(basename "$acfs_home_candidate")" == ".acfs" ]] || return 1
    [[ -f "$acfs_home_candidate/state.json" || -f "$acfs_home_candidate/VERSION" || -d "$acfs_home_candidate/dashboard" || -d "$acfs_home_candidate/onboard" || -f "$acfs_home_candidate/scripts/lib/info.sh" ]] || return 1

    if [[ -n "$_DASHBOARD_EXPLICIT_ACFS_HOME" ]] && [[ "$acfs_home_candidate" == "$_DASHBOARD_EXPLICIT_ACFS_HOME" ]]; then
        :
    elif [[ -n "$_DASHBOARD_DEFAULT_ACFS_HOME" ]] && [[ "$acfs_home_candidate" == "$_DASHBOARD_DEFAULT_ACFS_HOME" ]]; then
        :
    elif [[ "${_DASHBOARD_RESOLVED_ACFS_HOME_SOURCE:-}" == "explicit_target_home" ]]; then
        :
    else
        return 1
    fi

    inferred_home="${acfs_home_candidate%/.acfs}"
    inferred_home="$(dashboard_sanitize_abs_nonroot_path "$inferred_home" 2>/dev/null || true)"
    [[ -n "$inferred_home" ]] || return 1
    printf '%s\n' "$inferred_home"
}
dashboard_prepare_context() {
    local state_file=""
    local path_home=""
    local detected_user=""
    local state_target_user=""
    local resolved_target_home=""
    local explicit_target_home=""
    local target_home_source=""

    _DASHBOARD_RESOLVED_TARGET_USER=""
    _DASHBOARD_RESOLVED_TARGET_HOME=""
    _DASHBOARD_ACFS_HOME="$(dashboard_resolve_acfs_home 2>/dev/null || true)"
    state_file="$(dashboard_resolve_state_file)"
    path_home="$(dashboard_infer_target_home_from_acfs_home 2>/dev/null || true)"
    explicit_target_home="$(dashboard_resolve_explicit_target_home 2>/dev/null || true)"
    if [[ -n "$path_home" ]]; then
        state_target_user="$(dashboard_read_state_string "$state_file" "target_user" 2>/dev/null || true)"
    fi
    if [[ -z "$state_target_user" ]]; then
        state_target_user="$(dashboard_read_state_string "$_DASHBOARD_SYSTEM_STATE_FILE" "target_user" 2>/dev/null ||         dashboard_read_state_string "$state_file" "target_user" 2>/dev/null || true)"
    fi

    if [[ -n "$_DASHBOARD_EXPLICIT_TARGET_HOME_RAW" ]] || [[ -n "$_DASHBOARD_EXPLICIT_TARGET_USER_RAW" ]]; then
        if [[ -n "$explicit_target_home" ]]; then
            _DASHBOARD_RESOLVED_TARGET_HOME="$explicit_target_home"
            target_home_source="explicit_target_home"
        else
            echo "Error: explicit TARGET_HOME/TARGET_USER did not resolve to an installed home; refusing to fall back to current HOME" >&2
            return 1
        fi
    fi

    if [[ -z "$_DASHBOARD_RESOLVED_TARGET_HOME" ]] && [[ -n "$path_home" ]]; then
        _DASHBOARD_RESOLVED_TARGET_HOME="$path_home"
        target_home_source="path_home"
    fi

    if [[ -z "$_DASHBOARD_RESOLVED_TARGET_HOME" ]]; then
        resolved_target_home="$(dashboard_read_target_home_from_state "$_DASHBOARD_SYSTEM_STATE_FILE" 2>/dev/null ||             dashboard_read_target_home_from_state "$state_file" 2>/dev/null || true)"
        if [[ -n "$resolved_target_home" ]]; then
            _DASHBOARD_RESOLVED_TARGET_HOME="$resolved_target_home"
            target_home_source="state_target_home"
        fi
    fi

    if [[ -z "$_DASHBOARD_RESOLVED_TARGET_HOME" ]] && [[ -n "$state_target_user" ]]; then
        resolved_target_home="$(dashboard_existing_abs_home "$(dashboard_home_for_user "$state_target_user" 2>/dev/null || true)" 2>/dev/null || true)"
        if [[ -n "$resolved_target_home" ]]; then
            _DASHBOARD_RESOLVED_TARGET_HOME="$resolved_target_home"
            target_home_source="state_target_user"
        fi
    fi

    if [[ -z "$_DASHBOARD_RESOLVED_TARGET_HOME" ]] && [[ -n "$path_home" ]]; then
        _DASHBOARD_RESOLVED_TARGET_HOME="$path_home"
        target_home_source="path_home"
    fi

    if [[ -z "$_DASHBOARD_RESOLVED_TARGET_HOME" ]] && [[ "$_DASHBOARD_ACFS_HOME" == */.acfs ]]; then
        resolved_target_home="$(dashboard_existing_abs_home "${_DASHBOARD_ACFS_HOME%/.acfs}" 2>/dev/null || true)"
        if [[ -n "$resolved_target_home" ]]; then
            _DASHBOARD_RESOLVED_TARGET_HOME="$resolved_target_home"
            target_home_source="acfs_home_path"
        fi
    fi

    if [[ -z "$_DASHBOARD_RESOLVED_TARGET_HOME" ]]; then
        resolved_target_home="$(dashboard_existing_abs_home "${_DASHBOARD_CURRENT_HOME:-}" 2>/dev/null || true)"
        if [[ -n "$resolved_target_home" ]]; then
            _DASHBOARD_RESOLVED_TARGET_HOME="$resolved_target_home"
            target_home_source="current_home"
        fi
    fi

    if [[ -z "$_DASHBOARD_RESOLVED_TARGET_USER" ]] && [[ -n "$_DASHBOARD_RESOLVED_TARGET_HOME" ]]; then
        detected_user="$(dashboard_read_user_for_home "$_DASHBOARD_RESOLVED_TARGET_HOME" 2>/dev/null || true)"
        if [[ -n "$detected_user" ]]; then
            _DASHBOARD_RESOLVED_TARGET_USER="$detected_user"
        fi
    fi

    if [[ -z "$_DASHBOARD_RESOLVED_TARGET_USER" ]] && [[ "$target_home_source" != "explicit_target_home" ]] && [[ -n "$state_target_user" ]]; then
        _DASHBOARD_RESOLVED_TARGET_USER="$state_target_user"
    fi

    if [[ -z "$_DASHBOARD_RESOLVED_TARGET_USER" ]] && dashboard_is_valid_username "$_DASHBOARD_EXPLICIT_TARGET_USER_RAW"; then
        _DASHBOARD_RESOLVED_TARGET_USER="$_DASHBOARD_EXPLICIT_TARGET_USER_RAW"
    fi

    if [[ -z "$_DASHBOARD_RESOLVED_TARGET_USER" ]] && [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
        _DASHBOARD_RESOLVED_TARGET_USER="$SUDO_USER"
    fi
}

find_info_script() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Prefer the repo-local helper when running from a checkout so dashboard
    # generation follows the code under test, not a stale installed copy.
    if [[ -f "$script_dir/info.sh" ]]; then
        echo "$script_dir/info.sh"
        return 0
    fi

    if [[ -n "$_DASHBOARD_ACFS_HOME" ]] && [[ -f "$_DASHBOARD_ACFS_HOME/scripts/lib/info.sh" ]]; then
        echo "$_DASHBOARD_ACFS_HOME/scripts/lib/info.sh"
        return 0
    fi

    return 1
}

validate_port() {
    local port="${1:-}"
    local port_num=0

    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    while [[ "${#port}" -gt 1 && "$port" == 0* ]]; do
        port="${port#0}"
    done
    [[ "${#port}" -le 5 ]] || return 1

    port_num=$((10#$port))
    (( port_num >= 1 && port_num <= 65535 ))
}

dashboard_generate() {
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force=true
                ;;
            --help|-h)
                dashboard_usage
                return 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                return 1
                ;;
        esac
        shift
    done

    dashboard_prepare_context

    if [[ -z "$_DASHBOARD_ACFS_HOME" ]]; then
        echo "Error: ACFS home not found" >&2
        echo "Provide ACFS_SYSTEM_STATE_FILE with target_home, or re-run the installer." >&2
        return 1
    fi

    local dashboard_dir="${_DASHBOARD_ACFS_HOME}/dashboard"
    local html_file="${dashboard_dir}/index.html"
    local timestamp_file="${dashboard_dir}/.last_generated"

    mkdir -p "$dashboard_dir"

    if [[ "$force" != "true" && -f "$html_file" ]]; then
        local last_gen now age
        last_gen="$(cat "$timestamp_file" 2>/dev/null || echo 0)"
        if [[ ! "$last_gen" =~ ^[0-9]+$ ]]; then
            last_gen=0
        fi
        now="$(date +%s)"
        age=$((now - last_gen))

        if [[ $age -ge 0 && $age -lt 3600 ]]; then
            echo "Dashboard is recent ($((age / 60)) minutes old). Use --force to regenerate."
            echo "Dashboard path: $html_file"
            return 0
        fi
    fi

    local info_script
    if ! info_script="$(find_info_script)"; then
        echo "Error: info.sh not found" >&2
        echo "Re-run the ACFS installer to get the latest scripts." >&2
        return 1
    fi

    echo "Generating dashboard..."
    local tmp_file=""
    tmp_file=$(mktemp "${dashboard_dir}/index.html.tmp.XXXXXX") || {
        echo "Error: could not create temporary dashboard file" >&2
        return 1
    }

    if ! bash "$info_script" --html > "$tmp_file"; then
        echo "Error: dashboard generation failed" >&2
        dashboard_remove_temp_file "$tmp_file"
        return 1
    fi

    if ! mv -- "$tmp_file" "$html_file"; then
        echo "Error: could not replace dashboard file" >&2
        dashboard_remove_temp_file "$tmp_file"
        return 1
    fi

    if ! date +%s > "$timestamp_file"; then
        echo "Error: could not update dashboard timestamp" >&2
        return 1
    fi

    echo "Dashboard generated: $html_file"
    echo "Open with: open \"$html_file\" (macOS) or xdg-open \"$html_file\" (Linux)"
}

dashboard_serve() {
    local port=8080
    local host="127.0.0.1"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --port)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --port requires a port number" >&2
                    return 1
                fi
                if ! validate_port "$2"; then
                    echo "Error: port must be an integer between 1 and 65535" >&2
                    return 1
                fi
                port="$2"
                shift 2
                continue
                ;;
            --host)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --host requires a host/address (e.g. 127.0.0.1 or 0.0.0.0)" >&2
                    return 1
                fi
                host="$2"
                shift 2
                continue
                ;;
            --public)
                host="0.0.0.0"
                ;;
            --help|-h)
                echo "Usage: acfs dashboard serve [--port PORT] [--host HOST] [--public]"
                echo ""
                echo "Starts a temporary HTTP server to view the dashboard."
                echo "Default port: 8080"
                echo "Default host: 127.0.0.1 (local only)"
                echo ""
                echo "Notes:"
                echo "  - Local-only is safer on VPS (prevents accidental internet exposure)."
                echo "  - Use --public to bind 0.0.0.0 (all interfaces)."
                return 0
                ;;
            *)
                # Allow port as positional argument
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    if ! validate_port "$1"; then
                        echo "Error: port must be an integer between 1 and 65535" >&2
                        return 1
                    fi
                    port="$1"
                else
                    echo "Unknown option: $1" >&2
                    return 1
                fi
                ;;
        esac
        shift
    done

    if ! validate_port "$port"; then
        echo "Error: port must be an integer between 1 and 65535" >&2
        return 1
    fi

    dashboard_prepare_context

    if [[ -z "$_DASHBOARD_ACFS_HOME" ]]; then
        echo "Error: ACFS home not found" >&2
        echo "Provide ACFS_SYSTEM_STATE_FILE with target_home, or re-run the installer." >&2
        return 1
    fi

    local dashboard_dir="${_DASHBOARD_ACFS_HOME}/dashboard"
    local html_file="${dashboard_dir}/index.html"

    # Auto-generate dashboard if missing
    if [[ ! -f "$html_file" ]]; then
        echo "Dashboard not found. Generating..."
        dashboard_generate --force
    fi

    # Get IP for display
    local ip="<your-server-ip>"
    local hostname_bin=""
    local hostname_ips=""
    hostname_bin="$(dashboard_system_binary_path hostname 2>/dev/null || true)"
    if [[ -n "$hostname_bin" ]]; then
        hostname_ips="$("$hostname_bin" -I 2>/dev/null || true)"
        read -r ip _ <<< "$hostname_ips"
    fi
    # Fallback if hostname -I returned empty
    [[ -z "$ip" ]] && ip="<your-server-ip>"

    # Prefer the invoking user for SSH tunnel instructions (handles `sudo acfs ...`).
    local ssh_user=""
    if [[ -n "$_DASHBOARD_RESOLVED_TARGET_USER" ]]; then
        ssh_user="$_DASHBOARD_RESOLVED_TARGET_USER"
    elif [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
        ssh_user="$SUDO_USER"
    else
        ssh_user="$(dashboard_resolve_current_user 2>/dev/null || echo "ubuntu")"
    fi

    # Check if port is in use
    local lsof_bin=""
    lsof_bin="$(dashboard_system_binary_path lsof 2>/dev/null || true)"
    if [[ -n "$lsof_bin" ]] && "$lsof_bin" -i :"$port" &>/dev/null; then
        echo "Warning: Port $port appears to be in use." >&2
        echo "Try a different port: acfs dashboard serve --port 8081" >&2
        return 1
    fi

    # Show banner
    if [[ "$host" == "127.0.0.1" || "$host" == "localhost" ]]; then
        cat <<EOF

╭─────────────────────────────────────────────────────────────╮
│  📊 ACFS Dashboard Server                                   │
├─────────────────────────────────────────────────────────────┤
│  Local URL:   http://localhost:${port} (server-side only)      │
│                                                             │
│  Press Ctrl+C to stop                                       │
│                                                             │
│  ⚠️  This is a temporary server.                            │
│  It stops when you close this terminal.                     │
│                                                             │
│  To view from your laptop (recommended):                     │
│    ssh -L ${port}:localhost:${port} ${ssh_user}@${ip}                │
│    then open: http://localhost:${port}                         │
╰─────────────────────────────────────────────────────────────╯

EOF
    else
        cat <<EOF

╭─────────────────────────────────────────────────────────────╮
│  📊 ACFS Dashboard Server                                   │
├─────────────────────────────────────────────────────────────┤
│  Local URL:   http://localhost:${port}                         │
│  Network URL: http://${ip}:${port}
│                                                             │
│  Press Ctrl+C to stop                                       │
│                                                             │
│  ⚠️  This is a temporary server.                            │
│  It stops when you close this terminal.                     │
╰─────────────────────────────────────────────────────────────╯

EOF
    fi

    # Start server
    cd "$dashboard_dir" || {
        echo "Error: Cannot cd to $dashboard_dir" >&2
        return 1
    }

    local python_bin=""
    python_bin="$(dashboard_system_binary_path python3 2>/dev/null || dashboard_system_binary_path python 2>/dev/null || true)"
    if [[ -n "$python_bin" ]]; then
        "$python_bin" -m http.server --bind "$host" "$port"
    else
        echo "Error: Python not found. Cannot start HTTP server." >&2
        echo "Install Python or open the dashboard directly: $html_file" >&2
        return 1
    fi
}

dashboard_main() {
    local cmd="${1:-help}"
    shift 1 2>/dev/null || true

    case "$cmd" in
        generate)
            dashboard_generate "$@"
            ;;
        serve)
            dashboard_serve "$@"
            ;;
        help|-h|--help)
            dashboard_usage
            ;;
        *)
            echo "Unknown command: $cmd" >&2
            dashboard_usage >&2
            return 1
            ;;
    esac
}

dashboard_restore_shell_options_if_sourced() {
    [[ "$_DASHBOARD_WAS_SOURCED" == "true" ]] || return 0

    if [[ "$_DASHBOARD_ORIGINAL_HOME_WAS_SET" == "true" ]]; then
        HOME="$_DASHBOARD_ORIGINAL_HOME"
        export HOME
    else
        unset HOME
    fi

    [[ "$_DASHBOARD_RESTORE_ERREXIT" == "true" ]] || set +e
    [[ "$_DASHBOARD_RESTORE_NOUNSET" == "true" ]] || set +u
    [[ "$_DASHBOARD_RESTORE_PIPEFAIL" == "true" ]] || set +o pipefail
}

dashboard_restore_shell_options_if_sourced

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    dashboard_main "$@"
fi
