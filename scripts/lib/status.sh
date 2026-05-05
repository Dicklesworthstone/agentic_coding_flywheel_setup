#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Status - One-line health summary
# Quick check: runs in <100ms, no network calls by default
#
# Exit codes:
#   0 - Healthy (all core tools present, state valid)
#   1 - Warnings (some optional tools missing, outdated state)
#   2 - Errors (broken state, missing critical tools)
#
# Usage:
#   acfs status                # Human-readable one-liner
#   acfs status --json         # Machine-readable JSON
#   acfs status --short        # Minimal output for shell prompts
#   acfs status --check-updates  # Include network-based update check
# ============================================================

_STATUS_WAS_SOURCED=false
_STATUS_ORIGINAL_HOME=""
_STATUS_ORIGINAL_HOME_WAS_SET=false
if [[ -v HOME ]]; then
    _STATUS_ORIGINAL_HOME="$HOME"
    _STATUS_ORIGINAL_HOME_WAS_SET=true
fi
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    _STATUS_WAS_SOURCED=true
fi

# --- Defaults ---
_STATUS_JSON=false
_STATUS_SHORT=false
_STATUS_CHECK_UPDATES=false
_STATUS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_status_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

_status_existing_abs_home() {
    local path_value=""

    path_value="$(_status_sanitize_abs_nonroot_path "${1:-}" 2>/dev/null || true)"
    [[ -n "$path_value" ]] || return 1
    [[ -d "$path_value" ]] || return 1
    printf '%s\n' "$path_value"
}

_status_path_looks_like_user_home() {
    local path_value=""
    local marker=""

    path_value="$(_status_existing_abs_home "${1:-}" 2>/dev/null || true)"
    [[ -n "$path_value" ]] || return 1

    for marker in .local .config .ssh .bashrc .zshrc .profile .oh-my-zsh .bun .cargo .atuin go; do
        [[ -e "$path_value/$marker" ]] && return 0
    done

    return 1
}

_status_system_binary_path() {
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

_status_system_curl() {
    local curl_bin=""

    curl_bin="$(_status_system_binary_path curl 2>/dev/null || true)"
    [[ -n "$curl_bin" ]] || return 127

    "$curl_bin" "$@"
}

_status_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(_status_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(_status_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

_status_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(_status_system_binary_path getent 2>/dev/null || true)"
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

_status_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    passwd_home="$(_status_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
    [[ -n "$passwd_home" ]] || return 1
    printf '%s\n' "$passwd_home"
}
_status_is_valid_username() {
    local username="${1:-}"
    [[ "$username" =~ ^[a-z_][a-z0-9._-]*$ ]]
}

_status_resolve_current_home() {
    local current_user=""
    local fallback_home=""
    local passwd_entry=""
    local passwd_home=""
    fallback_home="$(_status_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
    if [[ "${_STATUS_WAS_SOURCED:-false}" == "true" ]]; then
        fallback_home="$(_status_sanitize_abs_nonroot_path "${_STATUS_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
    fi
    current_user="$(_status_resolve_current_user 2>/dev/null || true)"

    if [[ "$current_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    if [[ -n "$current_user" ]]; then
        passwd_entry="$(_status_getent_passwd_entry "$current_user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            passwd_home="$(_status_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
            if [[ -n "$passwd_home" ]]; then
                printf '%s\n' "$passwd_home"
                return 0
            fi
        fi
    fi

    [[ -n "$fallback_home" ]] || return 1
    printf '%s\n' "$fallback_home"
}
_status_initial_current_home() {
    local cached_home=""
    local resolved_home=""

    if [[ "${_STATUS_WAS_SOURCED:-false}" == "true" ]] && [[ -z "${TARGET_HOME:-}${TARGET_USER:-}${ACFS_HOME:-}${ACFS_STATE_FILE:-}${ACFS_SYSTEM_STATE_FILE:-}" ]]; then
        cached_home="$(_status_sanitize_abs_nonroot_path "${_STATUS_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
        if [[ -n "$cached_home" ]]; then
            printf '%s\n' "$cached_home"
            return 0
        fi
    fi

    resolved_home="$(_status_resolve_current_home 2>/dev/null || true)"
    if [[ -n "$resolved_home" ]]; then
        printf '%s\n' "$resolved_home"
        return 0
    fi

    if [[ "${_STATUS_WAS_SOURCED:-false}" == "true" ]]; then
        cached_home="$(_status_sanitize_abs_nonroot_path "${_STATUS_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
        if [[ -n "$cached_home" ]]; then
            printf '%s\n' "$cached_home"
            return 0
        fi
    fi

    return 1
}
_STATUS_CURRENT_HOME="$(_status_initial_current_home 2>/dev/null || true)"
if [[ -n "$_STATUS_CURRENT_HOME" ]]; then
    HOME="$_STATUS_CURRENT_HOME"
    export HOME
fi

_STATUS_EXPLICIT_ACFS_HOME="$(_status_sanitize_abs_nonroot_path "${ACFS_HOME:-}" 2>/dev/null || true)"
_STATUS_DEFAULT_ACFS_HOME=""
[[ -n "$_STATUS_CURRENT_HOME" ]] && _STATUS_DEFAULT_ACFS_HOME="${_STATUS_CURRENT_HOME}/.acfs"
_ACFS_HOME="${_STATUS_EXPLICIT_ACFS_HOME:-$_STATUS_DEFAULT_ACFS_HOME}"
_STATUS_SYSTEM_STATE_WAS_EXPLICIT=false
[[ -n "${ACFS_SYSTEM_STATE_FILE:-}" ]] && [[ "${ACFS_SYSTEM_STATE_FILE%/}" != "/var/lib/acfs/state.json" ]] && _STATUS_SYSTEM_STATE_WAS_EXPLICIT=true
_STATUS_SYSTEM_STATE_FILE="$(_status_sanitize_abs_nonroot_path "${ACFS_SYSTEM_STATE_FILE:-/var/lib/acfs/state.json}" 2>/dev/null || true)"
if [[ -z "$_STATUS_SYSTEM_STATE_FILE" ]]; then
    _STATUS_SYSTEM_STATE_FILE="/var/lib/acfs/state.json"
fi
_STATUS_EXPLICIT_TARGET_HOME_RAW="${TARGET_HOME:-}"
_STATUS_EXPLICIT_TARGET_USER_RAW="${TARGET_USER:-}"
_STATUS_EXPLICIT_TARGET_HOME="$(_status_existing_abs_home "${TARGET_HOME:-}" 2>/dev/null || true)"
_STATUS_RESOLVED_ACFS_HOME=""

_status_reset_options() {
    _STATUS_JSON=false
    _STATUS_SHORT=false
    _STATUS_CHECK_UPDATES=false
}

_status_print_help() {
    echo "Usage: acfs status [--json] [--short] [--check-updates]"
    echo ""
    echo "Quick one-line health summary."
    echo ""
    echo "Options:"
    echo "  --json            Machine-readable JSON output"
    echo "  --short           Minimal output for shell prompt integration"
    echo "  --check-updates   Include network-based update checks (slower)"
    echo ""
    echo "Exit codes:"
    echo "  0  Healthy"
    echo "  1  Warnings (outdated, minor issues)"
    echo "  2  Errors (broken state, missing critical tools)"
    echo ""
    echo "Examples:"
    echo "  acfs status                     # Quick health check"
    echo "  acfs status --json              # JSON for scripts"
    echo "  acfs status --short             # For shell prompts"
    echo "  acfs status --check-updates     # Check for ACFS updates"
    echo ""
    echo "Shell prompt integration:"
    echo "  PROMPT='\$(acfs status --short 2>/dev/null) \w \$ '"
}

_status_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)           _STATUS_JSON=true; shift ;;
            --short)          _STATUS_SHORT=true; shift ;;
            --check-updates)  _STATUS_CHECK_UPDATES=true; shift ;;
            --help|-h)
                _status_print_help
                return 2
                ;;
            *)
                echo "Error: Unknown option: $1" >&2
                echo "Try 'acfs status --help' for usage." >&2
                return 1
                ;;
        esac
    done

    return 0
}

_status_prepend_user_paths() {
    local base_home="$1"
    local dir=""
    local primary_bin_dir=""
    local current_path="${PATH:-}"
    local seen_path=":${current_path}:"
    local -a to_prepend=()

    [[ -n "$base_home" ]] || return 0
    primary_bin_dir="$(_status_preferred_bin_dir "$base_home" 2>/dev/null || true)"
    [[ -n "$primary_bin_dir" ]] || primary_bin_dir="$base_home/.local/bin"

    for dir in \
        "$primary_bin_dir" \
        "$base_home/.local/bin" \
        "$base_home/.acfs/bin" \
        "$base_home/.bun/bin" \
        "$base_home/.cargo/bin" \
        "$base_home/go/bin" \
        "$base_home/.atuin/bin" \
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

_status_ensure_path() {
    local current_user=""

    current_user="$(_status_resolve_current_user 2>/dev/null || true)"
    if [[ -n "$_STATUS_CURRENT_HOME" ]]; then
        if [[ -z "${TARGET_USER:-}" ]] || [[ -n "$current_user" && "${TARGET_USER:-}" == "$current_user" ]]; then
            _status_prepend_user_paths "$_STATUS_CURRENT_HOME"
        fi
    fi

    if [[ -n "${TARGET_HOME:-}" ]] && [[ "$TARGET_HOME" != "$_STATUS_CURRENT_HOME" ]]; then
        _status_prepend_user_paths "$TARGET_HOME"
    fi
}

_status_binary_path() {
    local name="${1:-}"
    local base_home=""
    local current_user=""
    local primary_bin_dir=""
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..) return 1 ;;
        *[!A-Za-z0-9._+-]*) return 1 ;;
    esac
    if [[ -n "${TARGET_HOME:-}" ]]; then
        base_home="${TARGET_HOME%/}"
    elif [[ -n "${TARGET_USER:-}" ]]; then
        current_user="$(_status_resolve_current_user 2>/dev/null || true)"
        if [[ -n "$current_user" ]] && [[ "${TARGET_USER:-}" == "$current_user" ]]; then
            base_home="${_STATUS_CURRENT_HOME:-}"
        fi
    else
        base_home="${_STATUS_CURRENT_HOME:-}"
    fi

    if [[ -n "$base_home" ]]; then
        primary_bin_dir="$(_status_preferred_bin_dir "$base_home" 2>/dev/null || true)"
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
            "$base_home/bin/$name"; do
            [[ -x "$candidate" ]] || continue
            printf '%s\n' "$candidate"
            return 0
        done
    fi

    for candidate in \
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

_status_binary_exists() {
    local resolved=""
    resolved="$(_status_binary_path "$1" 2>/dev/null || true)"
    [[ -n "$resolved" ]]
}

_status_home_for_user() {
    local user="$1"
    local passwd_entry=""
    local home_candidate=""
    local current_user=""

    [[ -n "$user" ]] || return 1

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    passwd_entry="$(_status_getent_passwd_entry "$user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        home_candidate="$(_status_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
        if [[ -n "$home_candidate" ]]; then
            printf '%s\n' "$home_candidate"
            return 0
        fi
    fi

    current_user="$(_status_resolve_current_user 2>/dev/null || true)"
    if [[ "$user" == "$current_user" ]]; then
        home_candidate="${_STATUS_CURRENT_HOME:-}"
        if [[ -z "$home_candidate" ]]; then
            home_candidate="$(_status_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
        fi
        if [[ -n "$home_candidate" ]]; then
            printf '%s\n' "$home_candidate"
            return 0
        fi
    fi

    return 1
}

_status_resolve_explicit_target_home() {
    local target_home=""
    local resolved_home=""

    if [[ -n "$_STATUS_EXPLICIT_TARGET_USER_RAW" ]]; then
        _status_is_valid_username "$_STATUS_EXPLICIT_TARGET_USER_RAW" || return 1
        resolved_home="$(_status_existing_abs_home "$(_status_home_for_user "$_STATUS_EXPLICIT_TARGET_USER_RAW" 2>/dev/null || true)" 2>/dev/null || true)"
        if [[ -n "$resolved_home" ]]; then
            printf '%s\n' "${resolved_home%/}"
            return 0
        fi
        target_home="$_STATUS_EXPLICIT_TARGET_HOME"
        if [[ -n "$target_home" ]] && [[ "$target_home" != "${_STATUS_CURRENT_HOME:-}" ]] && {
            [[ -f "$target_home/.acfs/state.json" ]] || [[ -f "$target_home/.acfs/VERSION" ]] || [[ -d "$target_home/.acfs/onboard" ]] || [[ -f "$target_home/.acfs/scripts/lib/status.sh" ]]
        }; then
            printf '%s\n' "${target_home%/}"
            return 0
        fi
        return 1
    fi

    target_home="$_STATUS_EXPLICIT_TARGET_HOME"
    if [[ -n "$target_home" ]]; then
        printf '%s\n' "${target_home%/}"
        return 0
    fi

    return 1
}

_status_read_state_string() {
    local state_file="$1"
    local key="$2"
    local value=""
    local jq_bin=""
    local sed_bin=""
    local head_bin=""

    [[ -f "$state_file" ]] || return 1

    jq_bin="$(_status_system_binary_path jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        value=$("$jq_bin" -r --arg key "$key" '.[$key] // empty' "$state_file" 2>/dev/null || true)
    else
        sed_bin="$(_status_system_binary_path sed 2>/dev/null || true)"
        head_bin="$(_status_system_binary_path head 2>/dev/null || true)"
        [[ -n "$sed_bin" && -n "$head_bin" ]] || return 1
        value=$("$sed_bin" -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$state_file" 2>/dev/null | "$head_bin" -n 1)
    fi

    [[ -n "$value" ]] && [[ "$value" != "null" ]] || return 1
    printf '%s\n' "$value"
}

_status_read_target_user_from_state() {
    local state_file="$1"
    _status_read_state_string "$state_file" "target_user"
}

_status_read_target_home_from_state() {
    local state_file="$1"
    local target_home=""

    target_home="$(_status_read_state_string "$state_file" "target_home" 2>/dev/null || true)"
    [[ -n "$target_home" ]] || return 1
    [[ "$target_home" == /* ]] || return 1
    [[ "$target_home" != "/" ]] || return 1
    printf '%s\n' "${target_home%/}"
}

_status_read_bin_dir_from_state() {
    local state_file="$1"
    local bin_dir=""

    [[ -n "$state_file" ]] || return 1

    bin_dir="$(_status_read_state_string "$state_file" "bin_dir" 2>/dev/null || true)"
    bin_dir="$(_status_sanitize_abs_nonroot_path "$bin_dir" 2>/dev/null || true)"
    [[ -n "$bin_dir" ]] || return 1
    printf '%s\n' "$bin_dir"
}

_status_validate_bin_dir_for_home() {
    local bin_dir="${1:-}"
    local base_home="${2:-}"
    local passwd_line=""
    local passwd_home=""
    local hinted_home=""

    bin_dir="$(_status_sanitize_abs_nonroot_path "$bin_dir" 2>/dev/null || true)"
    [[ -n "$bin_dir" ]] || return 1
    base_home="$(_status_sanitize_abs_nonroot_path "$base_home" 2>/dev/null || true)"

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
    hinted_home="$(_status_sanitize_abs_nonroot_path "$hinted_home" 2>/dev/null || true)"
    if [[ -n "$hinted_home" ]] && [[ -n "$base_home" ]] && [[ "$hinted_home" != "$base_home" ]]; then
        return 1
    fi

    while IFS= read -r passwd_line; do
        passwd_home="$(_status_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
        [[ -n "$passwd_home" ]] || continue
        [[ -n "$base_home" && "$passwd_home" == "$base_home" ]] && continue
        if [[ "$bin_dir" == "$passwd_home" || "$bin_dir" == "$passwd_home/"* ]]; then
            return 1
        fi
    done < <(_status_getent_passwd_entry 2>/dev/null || true)

    printf '%s\n' "$bin_dir"
}

_status_state_file_path_target_home() {
    local state_file="${1:-}"
    local data_home=""
    local path_home=""
    local state_home=""
    local candidate_user=""

    [[ "$state_file" == */.acfs/state.json ]] || return 1
    data_home="${state_file%/state.json}"
    data_home="$(_status_sanitize_abs_nonroot_path "$data_home" 2>/dev/null || true)"
    [[ -n "$data_home" ]] || return 1
    path_home="${data_home%/.acfs}"

    candidate_user="$(_status_read_user_for_home "$path_home" 2>/dev/null || true)"
    if [[ -n "$candidate_user" ]]; then
        printf '%s\n' "$path_home"
        return 0
    fi

    state_home="$(_status_read_target_home_from_state "$state_file" 2>/dev/null || true)"
    if [[ -n "$state_home" ]] && [[ "$state_home" == "$path_home" ]]; then
        printf '%s\n' "$path_home"
        return 0
    fi

    if [[ -n "$_STATUS_EXPLICIT_ACFS_HOME" ]] && [[ "$data_home" == "$_STATUS_EXPLICIT_ACFS_HOME" ]] && _status_path_looks_like_user_home "$path_home"; then
        printf '%s\n' "$path_home"
        return 0
    fi

    return 1
}

_status_read_user_for_home() {
    local user_home="${1:-}"
    local candidate_user=""
    local candidate_home=""
    local current_user=""
    local current_home=""
    local passwd_line=""
    local passwd_home=""
    local state_file=""

    user_home="$(_status_sanitize_abs_nonroot_path "$user_home" 2>/dev/null || true)"
    [[ -n "$user_home" ]] || return 1

    while IFS= read -r passwd_line; do
        passwd_home="$(_status_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
        [[ "$passwd_home" == "$user_home" ]] || continue
        candidate_user="${passwd_line%%:*}"
        if [[ "$candidate_user" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
    done < <(_status_getent_passwd_entry 2>/dev/null || true)

    current_user="$(_status_resolve_current_user 2>/dev/null || true)"
    current_home="${_STATUS_CURRENT_HOME:-}"
    if [[ -z "$current_home" ]]; then
        current_home="$(_status_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
    fi
    if [[ -n "$current_user" ]] && [[ -n "$current_home" ]] && [[ "$user_home" == "$current_home" ]]; then
        printf '%s\n' "$current_user"
        return 0
    fi

    if [[ "$user_home" == "/root" ]]; then
        printf 'root\n'
        return 0
    fi

    state_file="$user_home/.acfs/state.json"
    candidate_user="$(_status_read_target_user_from_state "$state_file" 2>/dev/null || true)"
    if [[ -n "$candidate_user" ]]; then
        candidate_home="$(_status_home_for_user "$candidate_user" 2>/dev/null || true)"
        if [[ -n "$candidate_home" ]] && [[ "$candidate_home" == "$user_home" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
    fi

    return 1
}

_status_resolve_target_user() {
    local state_file="${1:-}"
    local candidate_user=""
    local candidate_home=""
    local path_home=""
    local state_home=""
    local system_home=""
    local system_user=""

    state_home="$(_status_read_target_home_from_state "$state_file" 2>/dev/null || true)"
    path_home="$(_status_state_file_path_target_home "$state_file" 2>/dev/null || true)"
    system_home="$(_status_read_target_home_from_state "$_STATUS_SYSTEM_STATE_FILE" 2>/dev/null || true)"
    system_user="$(_status_read_target_user_from_state "$_STATUS_SYSTEM_STATE_FILE" 2>/dev/null || true)"

    if [[ -n "$path_home" ]]; then
        candidate_user="$(_status_read_user_for_home "$path_home" 2>/dev/null || true)"
        if [[ -n "$candidate_user" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
    fi

    if [[ -n "$system_user" ]] && [[ -n "$system_home" ]] && { [[ -z "$path_home" ]] || [[ "$path_home" == "$system_home" ]]; }; then
        if [[ -n "$path_home" ]] || [[ -z "$state_home" ]] || [[ "$state_home" == "$system_home" ]] || [[ -z "$_STATUS_EXPLICIT_ACFS_HOME" ]] || [[ "$state_file" != "$_STATUS_EXPLICIT_ACFS_HOME/state.json" ]]; then
            printf '%s\n' "$system_user"
            return 0
        fi
    fi

    if [[ -n "$state_home" ]] && [[ -z "$path_home" || "$state_home" == "$path_home" ]]; then
        candidate_user="$(_status_read_user_for_home "$state_home" 2>/dev/null || true)"
        if [[ -n "$candidate_user" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
    fi

    candidate_user="$(_status_read_target_user_from_state "$state_file" 2>/dev/null || true)"
    if [[ -n "$candidate_user" ]]; then
        if [[ -z "$state_home" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi

        if [[ -n "$path_home" ]] && [[ "$state_home" == "$path_home" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi

        candidate_home="$(_status_home_for_user "$candidate_user" 2>/dev/null || true)"
        if [[ -n "$path_home" ]] && [[ "$candidate_home" == "$path_home" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
        if [[ -n "$state_home" ]] && [[ -z "$path_home" || "$state_home" == "$path_home" ]] && [[ "$candidate_home" == "$state_home" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
        if [[ -z "$path_home" ]] && [[ -n "$state_home" ]] && { [[ -z "$system_home" ]] || [[ "$state_home" == "$system_home" ]] || { [[ -n "$_STATUS_EXPLICIT_ACFS_HOME" ]] && [[ "$state_file" == "$_STATUS_EXPLICIT_ACFS_HOME/state.json" ]]; }; }; then
            printf '%s\n' "$candidate_user"
            return 0
        fi

        if [[ -n "$_STATUS_EXPLICIT_ACFS_HOME" ]] && [[ "$state_file" == "$_STATUS_EXPLICIT_ACFS_HOME/state.json" ]] && [[ -z "$path_home" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
    fi

    if [[ -n "$system_user" ]] && [[ -z "$system_home" ]]; then
        printf '%s\n' "$system_user"
        return 0
    fi

    return 1
}

_status_resolve_target_home() {
    local state_file="${1:-}"
    local path_home=""
    local state_home=""
    local system_home=""
    local explicit_target_home=""

    path_home="$(_status_state_file_path_target_home "$state_file" 2>/dev/null || true)"
    state_home="$(_status_read_target_home_from_state "$state_file" 2>/dev/null || true)"
    system_home="$(_status_read_target_home_from_state "$_STATUS_SYSTEM_STATE_FILE" 2>/dev/null || true)"
    explicit_target_home="$(_status_resolve_explicit_target_home 2>/dev/null || true)"

    if [[ -n "$path_home" ]]; then
        printf '%s\n' "$path_home"
        return 0
    fi

    if [[ -n "$explicit_target_home" ]]; then
        printf '%s\n' "$explicit_target_home"
        return 0
    fi

    if [[ -n "$_STATUS_EXPLICIT_TARGET_HOME_RAW" ]] || [[ -n "$_STATUS_EXPLICIT_TARGET_USER_RAW" ]]; then
        return 1
    fi

    if [[ -n "$state_home" ]]; then
        if [[ "$state_file" == "$_STATUS_SYSTEM_STATE_FILE" ]]; then
            printf '%s\n' "$state_home"
            return 0
        fi
        if [[ -n "$_STATUS_EXPLICIT_ACFS_HOME" ]] && [[ "$state_file" == "$_STATUS_EXPLICIT_ACFS_HOME/state.json" ]]; then
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

_status_allow_target_home_fallback_from_user() {
    local state_file="${1:-}"
    local path_home=""
    local state_home=""
    local system_home=""

    path_home="$(_status_state_file_path_target_home "$state_file" 2>/dev/null || true)"
    if [[ -n "$path_home" ]]; then
        return 1
    fi

    state_home="$(_status_read_target_home_from_state "$state_file" 2>/dev/null || true)"
    system_home="$(_status_read_target_home_from_state "$_STATUS_SYSTEM_STATE_FILE" 2>/dev/null || true)"

    [[ "$state_file" == "$_STATUS_SYSTEM_STATE_FILE" ]] && return 0
    [[ -n "$state_home" ]] && { [[ -z "$system_home" ]] || [[ "$state_home" == "$system_home" ]]; } && return 0
    [[ -n "$_STATUS_EXPLICIT_ACFS_HOME" ]] && [[ "$state_file" == "$_STATUS_EXPLICIT_ACFS_HOME/state.json" ]] && [[ -z "$state_home" ]] && return 0

    return 1
}

_status_preferred_bin_dir() {
    local base_home="${1:-${TARGET_HOME:-${_STATUS_CURRENT_HOME:-}}}"
    local state_file=""
    local candidate=""

    state_file="$(_status_resolve_state_file 2>/dev/null || true)"

    candidate="$(_status_read_bin_dir_from_state "$state_file" 2>/dev/null || true)"
    candidate="$(_status_validate_bin_dir_for_home "$candidate" "$base_home" 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    candidate="$(_status_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$base_home" 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    [[ -n "$base_home" ]] || return 1
    printf '%s\n' "$base_home/.local/bin"
}

_status_script_acfs_home() {
    local candidate=""
    candidate=$(cd "$_STATUS_SCRIPT_DIR/../.." 2>/dev/null && pwd) || return 1
    [[ "$(basename "$candidate")" == ".acfs" ]] || return 1
    printf '%s\n' "$candidate"
}

_status_current_home_acfs_candidate() {
    local candidate="$_STATUS_DEFAULT_ACFS_HOME"
    local current_home="$_STATUS_CURRENT_HOME"
    local current_user=""
    local original_home=""
    local state_home=""
    local state_user=""
    local state_user_home=""

    [[ -n "$candidate" && -n "$current_home" ]] || return 1
    [[ "$current_home" != "/root" ]] || return 1
    [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]] || return 1

    if [[ "${_STATUS_ORIGINAL_HOME_WAS_SET:-false}" == true ]]; then
        original_home="$(_status_sanitize_abs_nonroot_path "$_STATUS_ORIGINAL_HOME" 2>/dev/null || true)"
        [[ -n "$original_home" && "$original_home" == "$current_home" ]] || return 1
    fi

    current_user="$(_status_resolve_current_user 2>/dev/null || true)"
    [[ -n "$current_user" && "$current_user" != "root" ]] || return 1

    if [[ -f "$candidate/state.json" ]]; then
        state_home="$(_status_read_target_home_from_state "$candidate/state.json" 2>/dev/null || true)"
        [[ -z "$state_home" || "$state_home" == "$current_home" ]] || return 1

        state_user="$(_status_read_target_user_from_state "$candidate/state.json" 2>/dev/null || true)"
        if [[ -n "$state_user" && "$state_user" != "$current_user" ]]; then
            state_user_home="$(_status_home_for_user "$state_user" 2>/dev/null || true)"
            [[ "$state_user_home" == "$current_home" ]] || return 1
        fi
    fi

    printf '%s\n' "$candidate"
}

_status_resolve_acfs_home() {
    if [[ -n "$_STATUS_RESOLVED_ACFS_HOME" ]]; then
        printf '%s\n' "$_STATUS_RESOLVED_ACFS_HOME"
        return 0
    fi

    local candidate=""
    local target_home=""
    local target_user=""
    local explicit_target_home=""

    candidate=$(_status_script_acfs_home 2>/dev/null || true)
    if [[ -n "$candidate" ]] && [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]]; then
        _STATUS_RESOLVED_ACFS_HOME="$candidate"
        printf '%s\n' "$_STATUS_RESOLVED_ACFS_HOME"
        return 0
    fi

    explicit_target_home="$(_status_resolve_explicit_target_home 2>/dev/null || true)"
    if [[ -n "$explicit_target_home" ]]; then
        candidate="${explicit_target_home}/.acfs"
        if [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]]; then
            _STATUS_RESOLVED_ACFS_HOME="$candidate"
            printf '%s\n' "$_STATUS_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    if [[ ! -f "$_STATUS_SYSTEM_STATE_FILE" ]] && [[ -n "$_STATUS_EXPLICIT_ACFS_HOME" ]] && [[ -f "$_STATUS_EXPLICIT_ACFS_HOME/state.json" || -f "$_STATUS_EXPLICIT_ACFS_HOME/VERSION" || -d "$_STATUS_EXPLICIT_ACFS_HOME/onboard" ]]; then
        _STATUS_RESOLVED_ACFS_HOME="$_STATUS_EXPLICIT_ACFS_HOME"
        printf '%s\n' "$_STATUS_RESOLVED_ACFS_HOME"
        return 0
    fi

    candidate="$(_status_current_home_acfs_candidate 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        _STATUS_RESOLVED_ACFS_HOME="$candidate"
        printf '%s\n' "$_STATUS_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ "$_STATUS_SYSTEM_STATE_WAS_EXPLICIT" == true ]]; then
        target_home=$(_status_read_target_home_from_state "$_STATUS_SYSTEM_STATE_FILE" 2>/dev/null || true)
        if [[ -n "$target_home" ]]; then
            candidate="${target_home}/.acfs"
            if [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]]; then
                _STATUS_RESOLVED_ACFS_HOME="$candidate"
                printf '%s\n' "$_STATUS_RESOLVED_ACFS_HOME"
                return 0
            fi
        fi

        target_user=$(_status_read_target_user_from_state "$_STATUS_SYSTEM_STATE_FILE" 2>/dev/null || true)
        if [[ -n "$target_user" ]]; then
            target_home=$(_status_home_for_user "$target_user" 2>/dev/null || true)
            candidate="${target_home}/.acfs"
            if [[ -n "$target_home" ]] && [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]]; then
                _STATUS_RESOLVED_ACFS_HOME="$candidate"
                printf '%s\n' "$_STATUS_RESOLVED_ACFS_HOME"
                return 0
            fi
        fi
    fi

    if [[ -n "$_STATUS_EXPLICIT_ACFS_HOME" ]] && [[ -f "$_STATUS_EXPLICIT_ACFS_HOME/state.json" || -f "$_STATUS_EXPLICIT_ACFS_HOME/VERSION" || -d "$_STATUS_EXPLICIT_ACFS_HOME/onboard" ]]; then
        _STATUS_RESOLVED_ACFS_HOME="$_STATUS_EXPLICIT_ACFS_HOME"
        printf '%s\n' "$_STATUS_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ -n "$_STATUS_EXPLICIT_TARGET_HOME_RAW" ]] || [[ -n "$_STATUS_EXPLICIT_TARGET_USER_RAW" ]]; then
        _STATUS_RESOLVED_ACFS_HOME=""
        printf '%s\n' "$_STATUS_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ -n "${SUDO_USER:-}" ]]; then
        target_home=$(_status_home_for_user "$SUDO_USER" 2>/dev/null || true)
        candidate="${target_home}/.acfs"
        if [[ -n "$target_home" ]] && [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]]; then
            _STATUS_RESOLVED_ACFS_HOME="$candidate"
            printf '%s\n' "$_STATUS_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    target_home=$(_status_read_target_home_from_state "$_STATUS_SYSTEM_STATE_FILE" 2>/dev/null || true)
    if [[ -n "$target_home" ]]; then
        candidate="${target_home}/.acfs"
        if [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]]; then
            _STATUS_RESOLVED_ACFS_HOME="$candidate"
            printf '%s\n' "$_STATUS_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    target_user=$(_status_read_target_user_from_state "$_STATUS_SYSTEM_STATE_FILE" 2>/dev/null || true)
    if [[ -n "$target_user" ]]; then
        target_home=$(_status_home_for_user "$target_user" 2>/dev/null || true)
        candidate="${target_home}/.acfs"
        if [[ -n "$target_home" ]] && [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]]; then
            _STATUS_RESOLVED_ACFS_HOME="$candidate"
            printf '%s\n' "$_STATUS_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    if [[ -n "$_STATUS_EXPLICIT_ACFS_HOME" ]] && [[ -f "$_STATUS_EXPLICIT_ACFS_HOME/state.json" || -f "$_STATUS_EXPLICIT_ACFS_HOME/VERSION" || -d "$_STATUS_EXPLICIT_ACFS_HOME/onboard" ]]; then
        _STATUS_RESOLVED_ACFS_HOME="$_STATUS_EXPLICIT_ACFS_HOME"
        printf '%s\n' "$_STATUS_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ -n "$_STATUS_DEFAULT_ACFS_HOME" ]] && [[ -f "$_STATUS_DEFAULT_ACFS_HOME/state.json" || -f "$_STATUS_DEFAULT_ACFS_HOME/VERSION" || -d "$_STATUS_DEFAULT_ACFS_HOME/onboard" ]]; then
        _STATUS_RESOLVED_ACFS_HOME="$_STATUS_DEFAULT_ACFS_HOME"
        printf '%s\n' "$_STATUS_RESOLVED_ACFS_HOME"
        return 0
    fi

    _STATUS_RESOLVED_ACFS_HOME="$_STATUS_DEFAULT_ACFS_HOME"
    printf '%s\n' "$_STATUS_RESOLVED_ACFS_HOME"
}

_status_resolve_state_file() {
    local candidate=""

    if [[ -n "$_ACFS_HOME" ]]; then
        candidate="$_ACFS_HOME/state.json"
    fi

    if [[ -n "$candidate" ]] && [[ -f "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    if [[ -f "$_STATUS_SYSTEM_STATE_FILE" ]]; then
        printf '%s\n' "$_STATUS_SYSTEM_STATE_FILE"
        return 0
    fi

    printf '%s\n' "$candidate"
}

_status_prepare_context() {
    local state_file=""
    local explicit_target_home=""
    local resolved_target_home=""

    _ACFS_HOME="$(_status_resolve_acfs_home 2>/dev/null || true)"
    state_file="$(_status_resolve_state_file)"
    explicit_target_home="$(_status_resolve_explicit_target_home 2>/dev/null || true)"

    if [[ -z "${TARGET_HOME:-}" ]] && [[ -n "$explicit_target_home" ]]; then
        TARGET_HOME="$explicit_target_home"
        export TARGET_HOME
    fi

    if [[ -z "${TARGET_USER:-}" ]]; then
        TARGET_USER=$(_status_resolve_target_user "$state_file" 2>/dev/null || true)
        [[ -n "${TARGET_USER:-}" ]] && export TARGET_USER
    fi

    if [[ -z "${TARGET_USER:-}" ]] && [[ -n "${TARGET_HOME:-}" ]]; then
        TARGET_USER="$(_status_read_user_for_home "$TARGET_HOME" 2>/dev/null || true)"
        [[ -n "${TARGET_USER:-}" ]] && export TARGET_USER
    fi

    if [[ -n "${TARGET_USER:-}" ]]; then
        resolved_target_home="$(_status_home_for_user "$TARGET_USER" 2>/dev/null || true)"
        if [[ -n "$resolved_target_home" ]]; then
            TARGET_HOME="$resolved_target_home"
            export TARGET_HOME
        fi
    fi

    if [[ -z "${TARGET_HOME:-}" ]]; then
        TARGET_HOME=$(_status_resolve_target_home "$state_file" 2>/dev/null || true)
    fi

    if [[ -z "${TARGET_HOME:-}" ]] && [[ -n "$explicit_target_home" ]]; then
        TARGET_HOME="$explicit_target_home"
        export TARGET_HOME
    fi

    if [[ -z "${TARGET_HOME:-}" ]] && [[ -n "${TARGET_USER:-}" ]]; then
        if [[ "${TARGET_USER:-}" == "$_STATUS_EXPLICIT_TARGET_USER_RAW" ]] || _status_allow_target_home_fallback_from_user "$state_file"; then
            TARGET_HOME=$(_status_home_for_user "$TARGET_USER" 2>/dev/null || true)
            [[ -n "${TARGET_HOME:-}" ]] && export TARGET_HOME
        fi
    fi

    [[ -n "${TARGET_HOME:-}" ]] && export TARGET_HOME

    _status_ensure_path
}

_status_read_last_update_ts() {
    local state_file="$1"
    local ts=""
    local key=""
    local jq_bin=""
    local sed_bin=""
    local head_bin=""

    [[ -f "$state_file" ]] || return 1

    jq_bin="$(_status_system_binary_path jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        ts=$("$jq_bin" -r '
            .last_updated //
            .last_completed_phase_ts //
            .updated_at //
            .last_update //
            .started_at //
            .install_date //
            empty
        ' "$state_file" 2>/dev/null) || true
    fi

    if [[ -z "$ts" || "$ts" == "null" ]]; then
        sed_bin="$(_status_system_binary_path sed 2>/dev/null || true)"
        head_bin="$(_status_system_binary_path head 2>/dev/null || true)"
        [[ -n "$sed_bin" && -n "$head_bin" ]] || return 1
        for key in last_updated last_completed_phase_ts updated_at last_update started_at install_date; do
            ts=$("$sed_bin" -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" \
                "$state_file" 2>/dev/null | "$head_bin" -n1)
            if [[ -n "$ts" ]]; then
                break
            fi
        done
    fi

    [[ -n "$ts" ]] || return 1
    printf '%s\n' "$ts"
}

# --- JSON escape helper (no jq dependency) ---
_json_escape() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
}


_status_print() {
    local color="$1"
    local message="$2"

    if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
        printf '%b%s\033[0m\n' "$color" "$message"
    else
        printf '%s\n' "$message"
    fi
}

status_main() {
    local parse_status=0
    local _state_file=""
    local -a _warnings=()
    local -a _errors=()
    local -a _CORE_TOOLS=(zsh git tmux bun cargo go rg claude)
    local -a _OPTIONAL_TOOLS=(codex gemini gh uv fzf zoxide atuin bat lsd ntm bv br cass cm slb ubs dcg)
    local _tool_count=0
    local _last_update_ts=""
    local _last_update_human=""
    local _update_available=""
    local _local_version=""
    local _remote_version=""
    local _last_epoch=0
    local _now_epoch=0
    local _age_secs=0
    local _exit_code=0
    local _status_word="OK"
    local _warn_items=""
    local _err_items=""
    local _last_update_json="null"
    local _update_json=""
    local _msg=""
    local _missing_count=0
    local _jq_bin=""
    local _date_bin=""
    local w=""
    local e=""
    local cmd=""

    _status_reset_options
    _status_parse_args "$@" || parse_status=$?
    case "$parse_status" in
        0) ;;
        2) return 0 ;;
        *) return "$parse_status" ;;
    esac

    _status_prepare_context
    _state_file="$(_status_resolve_state_file)"
    _jq_bin="$(_status_system_binary_path jq 2>/dev/null || true)"
    _date_bin="$(_status_system_binary_path date 2>/dev/null || true)"

    if [[ ! -d "$_ACFS_HOME" ]]; then
        _errors+=("ACFS_HOME missing")
    fi

    if [[ ! -f "$_state_file" ]]; then
        _errors+=("state file missing")
    elif [[ ! -s "$_state_file" ]]; then
        _errors+=("state file empty")
    elif [[ -n "$_jq_bin" ]] && ! "$_jq_bin" -e . "$_state_file" >/dev/null 2>&1; then
        _errors+=("state file invalid JSON")
    fi

    for cmd in "${_CORE_TOOLS[@]}"; do
        if _status_binary_exists "$cmd"; then
            ((_tool_count++)) || true
        else
            _warnings+=("missing: $cmd")
        fi
    done

    for cmd in "${_OPTIONAL_TOOLS[@]}"; do
        if _status_binary_exists "$cmd"; then
            ((_tool_count++)) || true
        fi
    done

    if [[ -f "$_state_file" ]]; then
        _last_update_ts="$(_status_read_last_update_ts "$_state_file" 2>/dev/null || true)"
    fi

    if [[ -n "$_last_update_ts" && -n "$_date_bin" ]]; then
        _last_epoch=$("$_date_bin" -d "$_last_update_ts" +%s 2>/dev/null) || _last_epoch=0
        _now_epoch=$("$_date_bin" +%s 2>/dev/null) || _now_epoch=0
        if [[ "$_last_epoch" -gt 0 ]]; then
            _age_secs=$((_now_epoch - _last_epoch))
            if [[ $_age_secs -lt 3600 ]]; then
                _last_update_human="$((_age_secs / 60))m ago"
            elif [[ $_age_secs -lt 86400 ]]; then
                _last_update_human="$((_age_secs / 3600))h ago"
            else
                _last_update_human="$((_age_secs / 86400))d ago"
            fi
        fi
    fi

    if [[ "$_STATUS_CHECK_UPDATES" == "true" ]]; then
        if [[ -n "$_ACFS_HOME" ]] && [[ -f "$_ACFS_HOME/VERSION" ]]; then
            _local_version=$(cat "$_ACFS_HOME/VERSION" 2>/dev/null) || _local_version=""
            _remote_version=$(_status_system_curl -fsSL --connect-timeout 2 --max-time 5 \
                "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/VERSION" \
                2>/dev/null) || _remote_version=""
            if [[ -n "$_remote_version" ]] && [[ -n "$_local_version" ]] \
               && [[ "$_remote_version" != "$_local_version" ]]; then
                _update_available="${_local_version} -> ${_remote_version}"
                _warnings+=("update available: $_update_available")
            fi
        fi
    fi

    if [[ ${#_errors[@]} -gt 0 ]]; then
        _exit_code=2
        _status_word="ERROR"
    elif [[ ${#_warnings[@]} -gt 0 ]]; then
        _exit_code=1
        _status_word="WARN"
    fi

    if [[ "$_STATUS_JSON" == "true" ]]; then
        for w in "${_warnings[@]+${_warnings[@]}}"; do
            [[ -z "$w" ]] && continue
            [[ -n "$_warn_items" ]] && _warn_items+=","
            _warn_items+="\"$(_json_escape "$w")\""
        done

        for e in "${_errors[@]+${_errors[@]}}"; do
            [[ -z "$e" ]] && continue
            [[ -n "$_err_items" ]] && _err_items+=","
            _err_items+="\"$(_json_escape "$e")\""
        done

        if [[ -n "$_last_update_ts" ]]; then
            _last_update_json="\"$(_json_escape "$_last_update_ts")\""
        fi

        if [[ -n "$_update_available" ]]; then
            _update_json=",\"update_available\":\"$(_json_escape "$_update_available")\""
        fi

        printf '{"status":"%s","tools":%d,"last_update":%s,"warnings":[%s],"errors":[%s]%s}\n' \
            "${_status_word,,}" "$_tool_count" "$_last_update_json" \
            "$_warn_items" "$_err_items" "$_update_json"
    elif [[ "$_STATUS_SHORT" == "true" ]]; then
        case $_exit_code in
            0) echo "OK" ;;
            1) echo "WARN" ;;
            2) echo "ERR" ;;
        esac
    else
        _msg="ACFS $_status_word: $_tool_count tools"
        [[ -n "$_last_update_human" ]] && _msg="$_msg, last update $_last_update_human"

        if [[ ${#_errors[@]} -gt 0 ]]; then
            _msg="$_msg, ${#_errors[@]} error(s)"
        fi

        if [[ ${#_warnings[@]} -gt 0 ]]; then
            for w in "${_warnings[@]}"; do
                [[ "$w" == missing:* ]] && ((_missing_count++)) || true
            done
            [[ $_missing_count -gt 0 ]] && _msg="$_msg, $_missing_count missing tool(s)"
            [[ -n "$_update_available" ]] && _msg="$_msg, update available"
        fi

        case $_exit_code in
            0) _status_print '\033[0;32m' "$_msg" ;;
            1) _status_print '\033[0;33m' "$_msg" ;;
            2) _status_print '\033[0;31m' "$_msg" ;;
        esac
    fi

    return "$_exit_code"
}

_status_restore_home_if_sourced() {
    [[ "$_STATUS_WAS_SOURCED" == "true" ]] || return 0

    if [[ "$_STATUS_ORIGINAL_HOME_WAS_SET" == "true" ]]; then
        HOME="$_STATUS_ORIGINAL_HOME"
        export HOME
    else
        unset HOME
    fi
}

_status_restore_home_if_sourced

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    status_main "$@"
    exit $?
fi
