#!/usr/bin/env bash
# ============================================================
# ACFS Info Library
#
# Provides lightning-fast system and installation status display.
# Reads from state files only - NO verification checks (that's doctor's job).
#
# Usage:
#   acfs info            # Terminal output (default)
#   acfs info --json     # JSON output for scripting
#   acfs info --html     # Self-contained HTML page
#   acfs info --minimal  # Just essentials (IP, key commands)
#
# Design Philosophy:
#   - Speed: Must complete in <1 second
#   - Read-only: Never verify/test anything (doctor does that)
#   - Offline: No network calls required
#   - Fallback: Graceful degradation if data missing
#
# Related beads:
#   - agentic_coding_flywheel_setup-bags: FEATURE: acfs info Quick Reference Command
#   - agentic_coding_flywheel_setup-cxz3: TASK: Design acfs info output format
#   - agentic_coding_flywheel_setup-3dkg: TASK: Implement info.sh core data gathering
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_INFO_SH_LOADED:-}" ]]; then
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
    fi
    exit 0
fi
_ACFS_INFO_SH_LOADED=1

_INFO_WAS_SOURCED=false
_INFO_ORIGINAL_HOME=""
_INFO_ORIGINAL_HOME_WAS_SET=false
if [[ -v HOME ]]; then
    _INFO_ORIGINAL_HOME="$HOME"
    _INFO_ORIGINAL_HOME_WAS_SET=true
fi
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    _INFO_WAS_SOURCED=true
fi

info_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

info_existing_abs_home() {
    local path_value=""

    path_value="$(info_sanitize_abs_nonroot_path "${1:-}" 2>/dev/null || true)"
    [[ -n "$path_value" ]] || return 1
    [[ -d "$path_value" ]] || return 1
    printf '%s\n' "$path_value"
}

info_path_looks_like_user_home() {
    local path_value=""
    local marker=""

    path_value="$(info_existing_abs_home "${1:-}" 2>/dev/null || true)"
    [[ -n "$path_value" ]] || return 1

    for marker in .local .config .ssh .bashrc .zshrc .profile .oh-my-zsh .bun .cargo .atuin go; do
        [[ -e "$path_value/$marker" ]] && return 0
    done

    return 1
}

info_system_binary_path() {
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

info_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(info_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(info_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

info_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(info_system_binary_path getent 2>/dev/null || true)"
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

info_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    passwd_home="$(info_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
    [[ -n "$passwd_home" ]] || return 1
    printf '%s\n' "$passwd_home"
}
info_is_valid_username() {
    local username="${1:-}"
    [[ "$username" =~ ^[a-z_][a-z0-9._-]*$ ]]
}

info_resolve_current_home() {
    local current_user=""
    local fallback_home=""
    local passwd_entry=""
    local passwd_home=""
    fallback_home="$(info_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
    if [[ "${_INFO_WAS_SOURCED:-false}" == "true" ]]; then
        fallback_home="$(info_sanitize_abs_nonroot_path "${_INFO_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
    fi
    current_user="$(info_resolve_current_user 2>/dev/null || true)"

    if [[ "$current_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    if [[ -n "$current_user" ]]; then
        passwd_entry="$(info_getent_passwd_entry "$current_user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            passwd_home="$(info_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
            if [[ -n "$passwd_home" ]]; then
                printf '%s\n' "$passwd_home"
                return 0
            fi
        fi
    fi

    [[ -n "$fallback_home" ]] || return 1
    printf '%s\n' "$fallback_home"
}
info_initial_current_home() {
    local cached_home=""
    local resolved_home=""

    if [[ "${_INFO_WAS_SOURCED:-false}" == "true" ]] && [[ -z "${TARGET_HOME:-}${TARGET_USER:-}${ACFS_HOME:-}${ACFS_STATE_FILE:-}${ACFS_SYSTEM_STATE_FILE:-}" ]]; then
        cached_home="$(info_sanitize_abs_nonroot_path "${_INFO_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
        if [[ -n "$cached_home" ]]; then
            printf '%s\n' "$cached_home"
            return 0
        fi
    fi

    resolved_home="$(info_resolve_current_home 2>/dev/null || true)"
    if [[ -n "$resolved_home" ]]; then
        printf '%s\n' "$resolved_home"
        return 0
    fi

    if [[ "${_INFO_WAS_SOURCED:-false}" == "true" ]]; then
        cached_home="$(info_sanitize_abs_nonroot_path "${_INFO_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
        if [[ -n "$cached_home" ]]; then
            printf '%s\n' "$cached_home"
            return 0
        fi
    fi

    return 1
}
_INFO_CURRENT_HOME="$(info_initial_current_home 2>/dev/null || true)"
if [[ -n "$_INFO_CURRENT_HOME" ]]; then
    HOME="$_INFO_CURRENT_HOME"
    export HOME
fi

# ACFS home directory
_INFO_EXPLICIT_ACFS_HOME="$(info_sanitize_abs_nonroot_path "${ACFS_HOME:-}" 2>/dev/null || true)"
_INFO_DEFAULT_ACFS_HOME=""
[[ -n "$_INFO_CURRENT_HOME" ]] && _INFO_DEFAULT_ACFS_HOME="${_INFO_CURRENT_HOME}/.acfs"
_INFO_ACFS_HOME="${_INFO_EXPLICIT_ACFS_HOME:-$_INFO_DEFAULT_ACFS_HOME}"
_INFO_SYSTEM_STATE_WAS_EXPLICIT=false
[[ -n "${ACFS_SYSTEM_STATE_FILE:-}" ]] && [[ "${ACFS_SYSTEM_STATE_FILE%/}" != "/var/lib/acfs/state.json" ]] && _INFO_SYSTEM_STATE_WAS_EXPLICIT=true
_INFO_SYSTEM_STATE_FILE="$(info_sanitize_abs_nonroot_path "${ACFS_SYSTEM_STATE_FILE:-/var/lib/acfs/state.json}" 2>/dev/null || true)"
if [[ -z "$_INFO_SYSTEM_STATE_FILE" ]]; then
    _INFO_SYSTEM_STATE_FILE="/var/lib/acfs/state.json"
fi
_INFO_EXPLICIT_TARGET_HOME_RAW="${TARGET_HOME:-}"
_INFO_EXPLICIT_TARGET_USER_RAW="${TARGET_USER:-}"
_INFO_EXPLICIT_TARGET_HOME="$(info_existing_abs_home "${TARGET_HOME:-}" 2>/dev/null || true)"
_INFO_RESOLVED_ACFS_HOME=""

# Source output formatting library (for TOON support)
_INFO_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${_INFO_SCRIPT_DIR}/output.sh" ]]; then
    # shellcheck source=output.sh
    source "${_INFO_SCRIPT_DIR}/output.sh"
fi

# Global format options (set by argument parsing)
_INFO_OUTPUT_FORMAT=""
_INFO_SHOW_STATS=false

# ============================================================
# Color Constants (for terminal output)
# Respects NO_COLOR standard: https://no-color.org/
# Related: bd-39ye
# ============================================================
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_DIM='\033[2m'
    C_GREEN='\033[0;32m'
    C_CYAN='\033[0;36m'
    C_GRAY='\033[0;90m'
else
    C_RESET=''
    C_BOLD=''
    C_DIM=''
    C_GREEN=''
    C_CYAN=''
    C_GRAY=''
fi

# ============================================================
# Data Gathering Functions
# ============================================================
# Each function must:
#   - Complete in <100ms
#   - Never make network calls
#   - Return fallback value on error

# Get file modified time (unix epoch seconds)
info_get_file_mtime() {
    local path="$1"
    local mtime=""
    mtime="$(stat -c %Y "$path" 2>/dev/null || stat -f %m "$path" 2>/dev/null || echo "")"
    [[ "$mtime" =~ ^[0-9]+$ ]] || return 1
    echo "$mtime"
}

info_home_for_user() {
    local user="$1"
    local passwd_entry=""
    local home_candidate=""
    local current_user=""

    [[ -n "$user" ]] || return 1

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    passwd_entry="$(info_getent_passwd_entry "$user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        home_candidate="$(info_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
        if [[ -n "$home_candidate" ]]; then
            printf '%s\n' "$home_candidate"
            return 0
        fi
    fi

    current_user="$(info_resolve_current_user 2>/dev/null || true)"
    if [[ "$user" == "$current_user" ]]; then
        home_candidate="${_INFO_CURRENT_HOME:-}"
        if [[ -z "$home_candidate" ]]; then
            home_candidate="$(info_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
        fi
        if [[ -n "$home_candidate" ]]; then
            printf '%s\n' "$home_candidate"
            return 0
        fi
    fi

    return 1
}

info_resolve_explicit_target_home() {
    local target_home=""
    local resolved_home=""

    if [[ -n "$_INFO_EXPLICIT_TARGET_USER_RAW" ]]; then
        info_is_valid_username "$_INFO_EXPLICIT_TARGET_USER_RAW" || return 1
        resolved_home="$(info_existing_abs_home "$(info_home_for_user "$_INFO_EXPLICIT_TARGET_USER_RAW" 2>/dev/null || true)" 2>/dev/null || true)"
        if [[ -n "$resolved_home" ]]; then
            printf '%s\n' "${resolved_home%/}"
            return 0
        fi
        target_home="$_INFO_EXPLICIT_TARGET_HOME"
        if [[ -n "$target_home" ]] && [[ "$target_home" != "${_INFO_CURRENT_HOME:-}" ]] && info_candidate_has_acfs_data "$target_home/.acfs"; then
            printf '%s\n' "${target_home%/}"
            return 0
        fi
        return 1
    fi

    target_home="$_INFO_EXPLICIT_TARGET_HOME"
    if [[ -n "$target_home" ]]; then
        printf '%s\n' "${target_home%/}"
        return 0
    fi

    return 1
}

info_candidate_has_acfs_data() {
    local candidate="$1"
    [[ -n "$candidate" ]] || return 1
    [[ -e "$candidate/state.json" || -e "$candidate/onboard_progress.json" || -d "$candidate/onboard" || -e "$candidate/VERSION" || -e "$candidate/scripts/lib/info.sh" ]]
}

info_script_acfs_home() {
    local candidate=""
    candidate=$(cd "$_INFO_SCRIPT_DIR/../.." 2>/dev/null && pwd) || return 1
    [[ "$(basename "$candidate")" == ".acfs" ]] || return 1
    printf '%s\n' "$candidate"
}

info_current_home_acfs_candidate() {
    local candidate="$_INFO_DEFAULT_ACFS_HOME"
    local current_home="$_INFO_CURRENT_HOME"
    local current_user=""
    local original_home=""
    local state_home=""
    local state_user=""
    local state_user_home=""

    [[ -n "$candidate" && -n "$current_home" ]] || return 1
    [[ "$current_home" != "/root" ]] || return 1
    info_candidate_has_acfs_data "$candidate" || return 1

    if [[ "${_INFO_ORIGINAL_HOME_WAS_SET:-false}" == true ]]; then
        original_home="$(info_sanitize_abs_nonroot_path "$_INFO_ORIGINAL_HOME" 2>/dev/null || true)"
        [[ -n "$original_home" && "$original_home" == "$current_home" ]] || return 1
    fi

    current_user="$(info_resolve_current_user 2>/dev/null || true)"
    [[ -n "$current_user" && "$current_user" != "root" ]] || return 1

    if [[ -f "$candidate/state.json" ]]; then
        state_home="$(info_read_target_home_from_state "$candidate/state.json" 2>/dev/null || true)"
        [[ -z "$state_home" || "$state_home" == "$current_home" ]] || return 1

        state_user="$(info_read_target_user_from_state "$candidate/state.json" 2>/dev/null || true)"
        if [[ -n "$state_user" && "$state_user" != "$current_user" ]]; then
            state_user_home="$(info_home_for_user "$state_user" 2>/dev/null || true)"
            [[ "$state_user_home" == "$current_home" ]] || return 1
        fi
    fi

    printf '%s\n' "$candidate"
}

info_read_target_user_from_state() {
    local state_file="${1:-$_INFO_SYSTEM_STATE_FILE}"
    info_read_state_string "$state_file" "target_user"
}

info_read_state_string() {
    local state_file="$1"
    local key="$2"
    local value=""
    local jq_bin=""
    local sed_bin=""
    local head_bin=""

    [[ -f "$state_file" ]] || return 1

    jq_bin="$(info_system_binary_path jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        value=$("$jq_bin" -r --arg key "$key" '.[$key] // empty' "$state_file" 2>/dev/null || true)
    else
        sed_bin="$(info_system_binary_path sed 2>/dev/null || true)"
        head_bin="$(info_system_binary_path head 2>/dev/null || true)"
        [[ -n "$sed_bin" && -n "$head_bin" ]] || return 1
        value=$("$sed_bin" -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$state_file" 2>/dev/null | "$head_bin" -n 1)
    fi

    [[ -n "$value" ]] && [[ "$value" != "null" ]] || return 1
    echo "$value"
}

info_read_target_home_from_state() {
    local state_file="${1:-$_INFO_SYSTEM_STATE_FILE}"
    local target_home=""

    target_home="$(info_read_state_string "$state_file" "target_home" 2>/dev/null || true)"
    [[ -n "$target_home" ]] || return 1
    [[ "$target_home" == /* ]] || return 1
    [[ "$target_home" != "/" ]] || return 1
    printf '%s\n' "${target_home%/}"
}

info_read_bin_dir_from_state() {
    local state_file="${1:-}"
    local bin_dir=""

    [[ -n "$state_file" ]] || return 1

    bin_dir="$(info_read_state_string "$state_file" "bin_dir" 2>/dev/null || true)"
    bin_dir="$(info_sanitize_abs_nonroot_path "$bin_dir" 2>/dev/null || true)"
    [[ -n "$bin_dir" ]] || return 1
    printf '%s\n' "$bin_dir"
}

info_validate_bin_dir_for_home() {
    local bin_dir="${1:-}"
    local base_home="${2:-}"
    local passwd_line=""
    local passwd_home=""
    local hinted_home=""

    bin_dir="$(info_sanitize_abs_nonroot_path "$bin_dir" 2>/dev/null || true)"
    [[ -n "$bin_dir" ]] || return 1
    base_home="$(info_sanitize_abs_nonroot_path "$base_home" 2>/dev/null || true)"

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
    hinted_home="$(info_sanitize_abs_nonroot_path "$hinted_home" 2>/dev/null || true)"
    if [[ -n "$hinted_home" ]] && [[ -n "$base_home" ]] && [[ "$hinted_home" != "$base_home" ]]; then
        return 1
    fi

    while IFS= read -r passwd_line; do
        passwd_home="$(info_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
        [[ -n "$passwd_home" ]] || continue
        [[ -n "$base_home" && "$passwd_home" == "$base_home" ]] && continue
        if [[ "$bin_dir" == "$passwd_home" || "$bin_dir" == "$passwd_home/"* ]]; then
            return 1
        fi
    done < <(info_getent_passwd_entry 2>/dev/null || true)

    printf '%s\n' "$bin_dir"
}

info_state_file_path_target_home() {
    local state_file="${1:-}"
    local data_home=""
    local path_home=""
    local state_home=""
    local candidate_user=""

    [[ "$state_file" == */.acfs/state.json ]] || return 1
    data_home="${state_file%/state.json}"
    data_home="$(info_sanitize_abs_nonroot_path "$data_home" 2>/dev/null || true)"
    [[ -n "$data_home" ]] || return 1
    path_home="${data_home%/.acfs}"

    candidate_user="$(info_read_user_for_home "$path_home" 2>/dev/null || true)"
    if [[ -n "$candidate_user" ]]; then
        printf '%s\n' "$path_home"
        return 0
    fi

    state_home="$(info_read_target_home_from_state "$state_file" 2>/dev/null || true)"
    if [[ -n "$state_home" ]] && [[ "$state_home" == "$path_home" ]]; then
        printf '%s\n' "$path_home"
        return 0
    fi

    if [[ -n "$_INFO_EXPLICIT_ACFS_HOME" ]] && [[ "$data_home" == "$_INFO_EXPLICIT_ACFS_HOME" ]] && info_path_looks_like_user_home "$path_home"; then
        printf '%s\n' "$path_home"
        return 0
    fi

    return 1
}

info_read_user_for_home() {
    local user_home="${1:-}"
    local candidate_user=""
    local candidate_home=""
    local current_user=""
    local current_home=""
    local passwd_line=""
    local passwd_home=""
    local state_file=""

    user_home="$(info_sanitize_abs_nonroot_path "$user_home" 2>/dev/null || true)"
    [[ -n "$user_home" ]] || return 1

    while IFS= read -r passwd_line; do
        passwd_home="$(info_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
        [[ "$passwd_home" == "$user_home" ]] || continue
        candidate_user="${passwd_line%%:*}"
        if [[ "$candidate_user" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
    done < <(info_getent_passwd_entry 2>/dev/null || true)

    current_user="$(info_resolve_current_user 2>/dev/null || true)"
    current_home="${_INFO_CURRENT_HOME:-}"
    if [[ -z "$current_home" ]]; then
        current_home="$(info_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
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
    candidate_user="$(info_read_target_user_from_state "$state_file" 2>/dev/null || true)"
    if [[ -n "$candidate_user" ]]; then
        candidate_home="$(info_home_for_user "$candidate_user" 2>/dev/null || true)"
        if [[ -n "$candidate_home" ]] && [[ "$candidate_home" == "$user_home" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
    fi

    return 1
}

info_resolve_target_user() {
    local state_file="${1:-}"
    local candidate_user=""
    local candidate_home=""
    local path_home=""
    local state_home=""
    local system_home=""
    local system_user=""

    state_home="$(info_read_target_home_from_state "$state_file" 2>/dev/null || true)"
    path_home="$(info_state_file_path_target_home "$state_file" 2>/dev/null || true)"
    system_home="$(info_read_target_home_from_state "$_INFO_SYSTEM_STATE_FILE" 2>/dev/null || true)"
    system_user="$(info_read_target_user_from_state "$_INFO_SYSTEM_STATE_FILE" 2>/dev/null || true)"

    if [[ -n "$path_home" ]]; then
        candidate_user="$(info_read_user_for_home "$path_home" 2>/dev/null || true)"
        if [[ -n "$candidate_user" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
    fi

    if [[ -n "$system_user" ]] && [[ -n "$system_home" ]] && { [[ -z "$path_home" ]] || [[ "$path_home" == "$system_home" ]]; }; then
        if [[ -n "$path_home" ]] || [[ -z "$state_home" ]] || [[ "$state_home" == "$system_home" ]] || [[ -z "$_INFO_EXPLICIT_ACFS_HOME" ]] || [[ "$state_file" != "$_INFO_EXPLICIT_ACFS_HOME/state.json" ]]; then
            printf '%s\n' "$system_user"
            return 0
        fi
    fi

    if [[ -n "$state_home" ]] && [[ -z "$path_home" || "$state_home" == "$path_home" ]]; then
        candidate_user="$(info_read_user_for_home "$state_home" 2>/dev/null || true)"
        if [[ -n "$candidate_user" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
    fi

    candidate_user="$(info_read_target_user_from_state "$state_file" 2>/dev/null || true)"
    if [[ -n "$candidate_user" ]]; then
        if [[ -z "$state_home" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi

        if [[ -n "$path_home" ]] && [[ "$state_home" == "$path_home" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi

        candidate_home="$(info_home_for_user "$candidate_user" 2>/dev/null || true)"
        if [[ -n "$path_home" ]] && [[ "$candidate_home" == "$path_home" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
        if [[ -n "$state_home" ]] && [[ -z "$path_home" || "$state_home" == "$path_home" ]] && [[ "$candidate_home" == "$state_home" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
        if [[ -z "$path_home" ]] && [[ -n "$state_home" ]] && { [[ -z "$system_home" ]] || [[ "$state_home" == "$system_home" ]] || { [[ -n "$_INFO_EXPLICIT_ACFS_HOME" ]] && [[ "$state_file" == "$_INFO_EXPLICIT_ACFS_HOME/state.json" ]]; }; }; then
            printf '%s\n' "$candidate_user"
            return 0
        fi

        if [[ -n "$_INFO_EXPLICIT_ACFS_HOME" ]] && [[ "$state_file" == "$_INFO_EXPLICIT_ACFS_HOME/state.json" ]] && [[ -z "$path_home" ]]; then
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

info_resolve_target_home() {
    local state_file="${1:-}"
    local path_home=""
    local state_home=""
    local system_home=""
    local explicit_target_home=""

    path_home="$(info_state_file_path_target_home "$state_file" 2>/dev/null || true)"
    state_home="$(info_read_target_home_from_state "$state_file" 2>/dev/null || true)"
    system_home="$(info_read_target_home_from_state "$_INFO_SYSTEM_STATE_FILE" 2>/dev/null || true)"
    explicit_target_home="$(info_resolve_explicit_target_home 2>/dev/null || true)"

    if [[ -n "$path_home" ]]; then
        printf '%s\n' "$path_home"
        return 0
    fi

    if [[ -n "$explicit_target_home" ]]; then
        printf '%s\n' "$explicit_target_home"
        return 0
    fi

    if [[ -n "$_INFO_EXPLICIT_TARGET_HOME_RAW" ]] || [[ -n "$_INFO_EXPLICIT_TARGET_USER_RAW" ]]; then
        return 1
    fi

    if [[ -n "$state_home" ]]; then
        if [[ "$state_file" == "$_INFO_SYSTEM_STATE_FILE" ]]; then
            printf '%s\n' "$state_home"
            return 0
        fi
        if [[ -n "$_INFO_EXPLICIT_ACFS_HOME" ]] && [[ "$state_file" == "$_INFO_EXPLICIT_ACFS_HOME/state.json" ]]; then
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

info_preferred_bin_dir() {
    local base_home="${1:-${TARGET_HOME:-${_INFO_CURRENT_HOME:-}}}"
    local state_file=""
    local candidate=""

    state_file="$(info_get_install_state_file 2>/dev/null || true)"

    candidate="$(info_read_bin_dir_from_state "$state_file" 2>/dev/null || true)"
    candidate="$(info_validate_bin_dir_for_home "$candidate" "$base_home" 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    candidate="$(info_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$base_home" 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    [[ -n "$base_home" ]] || return 1
    printf '%s\n' "$base_home/.local/bin"
}

info_get_data_home() {
    if [[ -n "$_INFO_RESOLVED_ACFS_HOME" ]]; then
        echo "$_INFO_RESOLVED_ACFS_HOME"
        return 0
    fi

    local candidate=""
    local target_home=""
    local target_user=""
    local explicit_target_home=""

    candidate=$(info_script_acfs_home 2>/dev/null || true)
    if info_candidate_has_acfs_data "$candidate"; then
        _INFO_RESOLVED_ACFS_HOME="$candidate"
        echo "$_INFO_RESOLVED_ACFS_HOME"
        return 0
    fi

    explicit_target_home="$(info_resolve_explicit_target_home 2>/dev/null || true)"
    if [[ -n "$explicit_target_home" ]]; then
        candidate="${explicit_target_home}/.acfs"
        if info_candidate_has_acfs_data "$candidate"; then
            _INFO_RESOLVED_ACFS_HOME="$candidate"
            echo "$_INFO_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    if [[ ! -f "$_INFO_SYSTEM_STATE_FILE" ]] && [[ -n "$_INFO_EXPLICIT_ACFS_HOME" ]] && info_candidate_has_acfs_data "$_INFO_EXPLICIT_ACFS_HOME"; then
        _INFO_RESOLVED_ACFS_HOME="$_INFO_EXPLICIT_ACFS_HOME"
        echo "$_INFO_RESOLVED_ACFS_HOME"
        return 0
    fi

    candidate="$(info_current_home_acfs_candidate 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        _INFO_RESOLVED_ACFS_HOME="$candidate"
        echo "$_INFO_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ "$_INFO_SYSTEM_STATE_WAS_EXPLICIT" == true ]]; then
        target_home=$(info_read_target_home_from_state || true)
        if [[ -n "$target_home" ]]; then
            candidate="${target_home}/.acfs"
            if info_candidate_has_acfs_data "$candidate"; then
                _INFO_RESOLVED_ACFS_HOME="$candidate"
                echo "$_INFO_RESOLVED_ACFS_HOME"
                return 0
            fi
        fi

        target_user=$(info_read_target_user_from_state || true)
        if [[ -n "$target_user" ]]; then
            target_home=$(info_home_for_user "$target_user" || true)
            candidate="${target_home}/.acfs"
            if [[ -n "$target_home" ]] && info_candidate_has_acfs_data "$candidate"; then
                _INFO_RESOLVED_ACFS_HOME="$candidate"
                echo "$_INFO_RESOLVED_ACFS_HOME"
                return 0
            fi
        fi
    fi

    if [[ -n "$_INFO_EXPLICIT_ACFS_HOME" ]] && info_candidate_has_acfs_data "$_INFO_EXPLICIT_ACFS_HOME"; then
        _INFO_RESOLVED_ACFS_HOME="$_INFO_EXPLICIT_ACFS_HOME"
        echo "$_INFO_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ -n "$_INFO_EXPLICIT_TARGET_HOME_RAW" ]] || [[ -n "$_INFO_EXPLICIT_TARGET_USER_RAW" ]]; then
        _INFO_RESOLVED_ACFS_HOME=""
        echo ""
        return 0
    fi

    if [[ -n "${SUDO_USER:-}" ]]; then
        target_home=$(info_home_for_user "$SUDO_USER" || true)
        candidate="${target_home}/.acfs"
        if [[ -n "$target_home" ]] && info_candidate_has_acfs_data "$candidate"; then
            _INFO_RESOLVED_ACFS_HOME="$candidate"
            echo "$_INFO_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    target_home=$(info_read_target_home_from_state || true)
    if [[ -n "$target_home" ]]; then
        candidate="${target_home}/.acfs"
        if info_candidate_has_acfs_data "$candidate"; then
            _INFO_RESOLVED_ACFS_HOME="$candidate"
            echo "$_INFO_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    target_user=$(info_read_target_user_from_state || true)
    if [[ -n "$target_user" ]]; then
        target_home=$(info_home_for_user "$target_user" || true)
        candidate="${target_home}/.acfs"
        if [[ -n "$target_home" ]] && info_candidate_has_acfs_data "$candidate"; then
            _INFO_RESOLVED_ACFS_HOME="$candidate"
            echo "$_INFO_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    if [[ -n "$_INFO_DEFAULT_ACFS_HOME" ]] && info_candidate_has_acfs_data "$_INFO_DEFAULT_ACFS_HOME"; then
        _INFO_RESOLVED_ACFS_HOME="$_INFO_DEFAULT_ACFS_HOME"
        echo "$_INFO_RESOLVED_ACFS_HOME"
        return 0
    fi

    _INFO_RESOLVED_ACFS_HOME="$_INFO_DEFAULT_ACFS_HOME"
    echo "$_INFO_RESOLVED_ACFS_HOME"
}

info_get_install_state_file() {
    local data_home=""
    local candidate=""
    data_home=$(info_get_data_home)

    if [[ -n "$data_home" ]]; then
        candidate="$data_home/state.json"
    fi

    if [[ -n "$candidate" ]] && [[ -f "$candidate" ]]; then
        echo "$candidate"
        return 0
    fi

    if [[ -n "$_INFO_EXPLICIT_TARGET_HOME_RAW" ]] || [[ -n "$_INFO_EXPLICIT_TARGET_USER_RAW" ]]; then
        echo "$candidate"
        return 0
    fi

    if [[ -f "$_INFO_SYSTEM_STATE_FILE" ]]; then
        echo "$_INFO_SYSTEM_STATE_FILE"
        return 0
    fi

    echo "$candidate"
}

info_prepend_user_paths() {
    local base_home="$1"
    local dir=""
    local primary_bin_dir=""
    local current_path="${PATH:-}"
    local seen_path=":${current_path}:"
    local -a to_prepend=()

    [[ -n "$base_home" ]] || return 0
    primary_bin_dir="$(info_preferred_bin_dir "$base_home" 2>/dev/null || true)"
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

info_binary_path() {
    local name="${1:-}"
    local base_home="${TARGET_HOME:-${_INFO_CURRENT_HOME:-}}"
    local primary_bin_dir=""
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..) return 1 ;;
        *[!A-Za-z0-9._+-]*) return 1 ;;
    esac
    [[ -n "$base_home" ]] || return 1
    primary_bin_dir="$(info_preferred_bin_dir "$base_home" 2>/dev/null || true)"
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

info_binary_exists() {
    local resolved=""
    resolved="$(info_binary_path "$1" 2>/dev/null || true)"
    [[ -n "$resolved" ]]
}

info_prepare_context() {
    local data_home=""
    local state_file=""
    local target_home=""
    local resolved_target_home=""

    data_home=$(info_get_data_home)
    _INFO_RESOLVED_ACFS_HOME="$data_home"
    state_file=$(info_get_install_state_file)

    if [[ -z "${TARGET_USER:-}" ]]; then
        TARGET_USER=$(info_resolve_target_user "$state_file" 2>/dev/null || true)
        [[ -n "${TARGET_USER:-}" ]] && export TARGET_USER
    fi

    if [[ -n "${TARGET_USER:-}" ]]; then
        resolved_target_home="$(info_home_for_user "$TARGET_USER" 2>/dev/null || true)"
        if [[ -n "$resolved_target_home" ]]; then
            TARGET_HOME="$resolved_target_home"
            export TARGET_HOME
        fi
    fi

    if [[ -z "${TARGET_HOME:-}" ]]; then
        target_home=$(info_resolve_target_home "$state_file" 2>/dev/null || true)
        if [[ -n "${TARGET_USER:-}" ]]; then
            [[ -n "$target_home" ]] || target_home=$(info_home_for_user "$TARGET_USER" 2>/dev/null || true)
        fi
        if [[ -z "$target_home" ]] && [[ "$data_home" == */.acfs ]]; then
            target_home="${data_home%/.acfs}"
        fi
        if [[ -n "$target_home" ]]; then
            TARGET_HOME="$target_home"
            export TARGET_HOME
        fi
    fi

    info_prepend_user_paths "$_INFO_CURRENT_HOME"
    if [[ -n "${TARGET_HOME:-}" ]] && [[ "$TARGET_HOME" != "$_INFO_CURRENT_HOME" ]]; then
        info_prepend_user_paths "$TARGET_HOME"
    fi
}

# Get system hostname
info_get_hostname() {
    local hostname_value=""
    local hostname_bin=""

    if [[ -r /etc/hostname ]]; then
        IFS= read -r hostname_value < /etc/hostname || true
        if [[ -n "$hostname_value" ]]; then
            printf '%s\n' "$hostname_value"
            return 0
        fi
    fi

    hostname_bin="$(info_system_binary_path hostname 2>/dev/null || true)"
    if [[ -n "$hostname_bin" ]]; then
        hostname_value="$("$hostname_bin" 2>/dev/null || true)"
    fi

    if [[ -n "$hostname_value" ]]; then
        printf '%s\n' "$hostname_value"
    else
        echo "unknown"
    fi
}

# Get primary IP address (cached or live)
info_get_ip() {
    # Try cached value first
    local data_home=""
    local cache_file=""
    data_home=$(info_get_data_home)
    [[ -n "$data_home" ]] && cache_file="${data_home}/cache/ip_address"
    local now=""
    local date_bin=""
    local hostname_bin=""
    local ip_bin=""
    local mkdir_bin=""

    date_bin="$(info_system_binary_path date 2>/dev/null || true)"
    if [[ -n "$date_bin" ]]; then
        now="$("$date_bin" +%s 2>/dev/null || echo "")"
    fi

    if [[ -n "$cache_file" ]] && [[ -f "$cache_file" ]] && [[ "$now" =~ ^[0-9]+$ ]]; then
        local cache_mtime
        if cache_mtime="$(info_get_file_mtime "$cache_file")" && [[ $cache_mtime -gt $((now - 3600)) ]]; then
            local cached_ip=""
            IFS= read -r cached_ip < "$cache_file" || true
            cached_ip="${cached_ip//[[:space:]]/}"
            if [[ -n "$cached_ip" ]] && [[ "$cached_ip" != "unknown" ]]; then
                echo "$cached_ip"
                return 0
            fi
        fi
    fi

    # Get live value
    local ip=""
    local ip_line=""
    local route_word=""
    local expect_src=false

    hostname_bin="$(info_system_binary_path hostname 2>/dev/null || true)"
    if [[ -n "$hostname_bin" ]]; then
        ip_line="$("$hostname_bin" -I 2>/dev/null || true)"
        read -r ip _ <<< "$ip_line"
    fi

    if [[ -z "$ip" ]]; then
        ip_bin="$(info_system_binary_path ip 2>/dev/null || true)"
        if [[ -n "$ip_bin" ]]; then
            ip_line="$("$ip_bin" route get 1 2>/dev/null || true)"
            for route_word in $ip_line; do
                if [[ "$expect_src" == true ]]; then
                    ip="$route_word"
                    break
                fi
                [[ "$route_word" == "src" ]] && expect_src=true
            done
        fi
    fi

    if [[ -z "$ip" ]]; then
        ip="unknown"
    fi

    # Cache successful lookups, but do not pin transient failures for an hour.
    if [[ "$ip" != "unknown" ]] && [[ -n "$cache_file" ]]; then
        mkdir_bin="$(info_system_binary_path mkdir 2>/dev/null || true)"
        if [[ -n "$mkdir_bin" ]]; then
            "$mkdir_bin" -p "${data_home}/cache" 2>/dev/null
            echo "$ip" > "$cache_file" 2>/dev/null
        fi
    fi

    echo "$ip"
}

# Get human-readable uptime
info_get_uptime() {
    local uptime_bin=""
    local uptime_value=""

    uptime_bin="$(info_system_binary_path uptime 2>/dev/null || true)"
    if [[ -n "$uptime_bin" ]]; then
        uptime_value="$("$uptime_bin" -p 2>/dev/null || true)"
        uptime_value="${uptime_value#up }"
    fi

    if [[ -n "$uptime_value" ]]; then
        printf '%s\n' "$uptime_value"
    else
        echo "unknown"
    fi
}

# Get OS version info
info_get_os_version() {
    # Use subshell to avoid leaking os-release variables (ID, NAME, etc.)
    # shellcheck disable=SC1091
    (. /etc/os-release 2>/dev/null && echo "${VERSION_ID:-unknown}") || echo "unknown"
}

# Get OS codename
info_get_os_codename() {
    # shellcheck disable=SC1091
    (. /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME:-unknown}") || echo "unknown"
}

# Get installation state from state.json
info_get_install_state() {
    local state_file
    local jq_bin=""
    local cat_bin=""
    state_file="$(info_get_install_state_file)"
    [[ -f "$state_file" ]] || { echo '{}'; return 0; }

    jq_bin="$(info_system_binary_path jq 2>/dev/null || true)"
    cat_bin="$(info_system_binary_path cat 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        "$jq_bin" -c '.' "$state_file" 2>/dev/null || {
            if [[ -n "$cat_bin" ]]; then
                "$cat_bin" "$state_file" 2>/dev/null || echo '{}'
            else
                echo '{}'
            fi
        }
        return 0
    fi

    if [[ -n "$cat_bin" ]]; then
        "$cat_bin" "$state_file" 2>/dev/null || echo '{}'
    else
        echo '{}'
    fi
}

# Get completed phases count
info_get_completed_phases() {
    local state
    local jq_bin=""
    state=$(info_get_install_state)
    jq_bin="$(info_system_binary_path jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        "$jq_bin" -r '.completed_phases | length // 0' <<< "$state"
    else
        echo "0"
    fi
}

# Get total phases count
info_get_total_phases() {
    echo "9"  # Fixed in ACFS
}

# Get skipped tools
info_get_skipped_tools_json() {
    local state_file
    local jq_bin=""
    local python_bin=""
    local sed_bin=""
    local head_bin=""
    state_file="$(info_get_install_state_file)"
    [[ -f "$state_file" ]] || { echo '[]'; return 0; }

    jq_bin="$(info_system_binary_path jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        "$jq_bin" -c '.skipped_tools // []' "$state_file" 2>/dev/null || echo '[]'
        return 0
    fi

    python_bin="$(info_system_binary_path python3 2>/dev/null || true)"
    if [[ -n "$python_bin" ]]; then
        "$python_bin" - "$state_file" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
    skipped = data.get("skipped_tools", [])
    if isinstance(skipped, dict):
        skipped = list(skipped.keys())
    elif not isinstance(skipped, list):
        skipped = []
    print(json.dumps([str(item) for item in skipped if item is not None]))
except Exception:
    print("[]")
PY
        return 0
    fi

    local raw
    sed_bin="$(info_system_binary_path sed 2>/dev/null || true)"
    head_bin="$(info_system_binary_path head 2>/dev/null || true)"
    if [[ -n "$sed_bin" && -n "$head_bin" ]]; then
        raw=$("$sed_bin" -n 's/.*"skipped_tools"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$state_file" 2>/dev/null | "$head_bin" -n1)
    fi
    if [[ -z "$raw" ]]; then
        echo '[]'
    else
        printf '[%s]\n' "$raw"
    fi
}

info_get_skipped_tools() {
    local skipped_tools_json
    local jq_bin=""
    local python_bin=""
    local sed_bin=""
    skipped_tools_json="$(info_get_skipped_tools_json)"

    jq_bin="$(info_system_binary_path jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        "$jq_bin" -r 'join(", ")' <<< "$skipped_tools_json"
        return 0
    fi

    python_bin="$(info_system_binary_path python3 2>/dev/null || true)"
    if [[ -n "$python_bin" ]]; then
        "$python_bin" - "$skipped_tools_json" <<'PY'
import json
import sys

try:
    skipped = json.loads(sys.argv[1])
    if isinstance(skipped, dict):
        skipped = list(skipped.keys())
    elif not isinstance(skipped, list):
        skipped = []
    print(", ".join(str(item) for item in skipped if item is not None))
except Exception:
    print("")
PY
        return 0
    fi

    sed_bin="$(info_system_binary_path sed 2>/dev/null || true)"
    if [[ -n "$sed_bin" ]]; then
        printf '%s\n' "$skipped_tools_json" | "$sed_bin" -e 's/^\[//' -e 's/\]$//' -e 's/"//g' -e 's/, */, /g'
    else
        printf '%s\n' "$skipped_tools_json"
    fi
}

# Get installation date
info_get_install_date() {
    local state
    local jq_bin=""
    local date_bin=""
    state=$(info_get_install_state)
    jq_bin="$(info_system_binary_path jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        local date_str
        date_str=$("$jq_bin" -r '.started_at // empty' <<< "$state")
        if [[ -n "$date_str" ]]; then
            # Try to format nicely, fall back to raw
            date_bin="$(info_system_binary_path date 2>/dev/null || true)"
            if [[ -n "$date_bin" ]]; then
                "$date_bin" -d "$date_str" "+%Y-%m-%d" 2>/dev/null || echo "${date_str%%T*}"
            else
                echo "${date_str%%T*}"
            fi
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

# Get onboard progress
info_get_onboard_lessons_dir() {
    local data_home=""
    data_home=$(info_get_data_home)
    if [[ -n "${ACFS_LESSONS_DIR:-}" ]]; then
        echo "$ACFS_LESSONS_DIR"
    elif [[ -n "$data_home" ]]; then
        echo "${data_home}/onboard/lessons"
    else
        echo ""
    fi
}

info_get_onboard_progress_file() {
    local data_home=""
    data_home=$(info_get_data_home)
    if [[ -n "${ACFS_PROGRESS_FILE:-}" ]]; then
        echo "$ACFS_PROGRESS_FILE"
    elif [[ -n "$data_home" ]]; then
        echo "${data_home}/onboard_progress.json"
    else
        echo ""
    fi
}

info_get_lesson_file_by_index() {
    local index="${1:-}"
    local lessons_dir
    local find_bin=""
    local sort_bin=""
    local sed_bin=""
    lessons_dir=$(info_get_onboard_lessons_dir)

    if [[ ! "$index" =~ ^[0-9]+$ ]] || [[ ! -d "$lessons_dir" ]]; then
        return 1
    fi

    find_bin="$(info_system_binary_path find 2>/dev/null || true)"
    sort_bin="$(info_system_binary_path sort 2>/dev/null || true)"
    sed_bin="$(info_system_binary_path sed 2>/dev/null || true)"
    [[ -n "$find_bin" && -n "$sort_bin" && -n "$sed_bin" ]] || return 1

    "$find_bin" "$lessons_dir" -maxdepth 1 -type f -name '*.md' -print 2>/dev/null \
        | LC_ALL=C "$sort_bin" \
        | "$sed_bin" -n "$((index + 1))p"
}

info_get_onboard_progress() {
    local progress_file
    progress_file=$(info_get_onboard_progress_file)
    local total
    total=$(info_get_lessons_total)
    if [[ -f "$progress_file" ]]; then
        local cat_bin=""
        cat_bin="$(info_system_binary_path cat 2>/dev/null || true)"
        if [[ -n "$cat_bin" ]]; then
            "$cat_bin" "$progress_file"
        else
            printf '{"completed": [], "total": %s}\n' "$total"
        fi
    else
        printf '{"completed": [], "total": %s}\n' "$total"
    fi
}

info_get_onboard_progress_compact() {
    local progress_file
    local tr_bin=""
    progress_file=$(info_get_onboard_progress_file)

    [[ -f "$progress_file" ]] || return 1
    tr_bin="$(info_system_binary_path tr 2>/dev/null || true)"
    [[ -n "$tr_bin" ]] || return 1
    "$tr_bin" -d '[:space:]' < "$progress_file" 2>/dev/null
}

info_get_onboard_completed_csv() {
    local compact
    local sed_bin=""
    local head_bin=""
    compact="$(info_get_onboard_progress_compact || true)"
    sed_bin="$(info_system_binary_path sed 2>/dev/null || true)"
    head_bin="$(info_system_binary_path head 2>/dev/null || true)"
    [[ -n "$sed_bin" && -n "$head_bin" ]] || { echo ""; return 0; }
    printf '%s\n' "$compact" | "$sed_bin" -n 's/.*"completed":\[\([^]]*\)\].*/\1/p' | "$head_bin" -n 1
}

# Get onboard lessons completed count
info_get_lessons_completed() {
    local progress
    local jq_bin=""
    progress=$(info_get_onboard_progress)
    jq_bin="$(info_system_binary_path jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        "$jq_bin" -r '(.completed // []) | length' <<< "$progress"
    else
        local completed_raw
        local -a completed_items=()
        local completed_item=""
        local completed_count=0
        completed_raw="$(info_get_onboard_completed_csv || true)"
        if [[ -z "$completed_raw" ]]; then
            echo "0"
        else
            IFS=',' read -r -a completed_items <<< "$completed_raw"
            for completed_item in "${completed_items[@]}"; do
                completed_item="${completed_item//[[:space:]]/}"
                [[ -n "$completed_item" ]] || continue
                ((completed_count++)) || true
            done
            echo "$completed_count"
        fi
    fi
}

# Get total lessons
info_get_lessons_total() {
    local lessons_dir
    local find_bin=""
    local lesson_count=0
    local lesson_path=""
    lessons_dir=$(info_get_onboard_lessons_dir)

    if [[ ! -d "$lessons_dir" ]]; then
        echo "0"
        return 0
    fi

    find_bin="$(info_system_binary_path find 2>/dev/null || true)"
    if [[ -z "$find_bin" ]]; then
        echo "0"
        return 0
    fi

    while IFS= read -r lesson_path; do
        [[ -n "$lesson_path" ]] || continue
        ((lesson_count++)) || true
    done < <("$find_bin" "$lessons_dir" -maxdepth 1 -type f -name '*.md' -print 2>/dev/null)

    echo "$lesson_count"
}

# Map an onboard lesson index to its discovered title.
info_get_lesson_title() {
    local lesson_path
    local title
    local line=""

    lesson_path=$(info_get_lesson_file_by_index "${1:-}") || {
        echo "unknown"
        return 0
    }

    while IFS= read -r line; do
        case "$line" in
            "# "*)
                title="${line#"# "}"
                break
                ;;
        esac
    done < "$lesson_path"

    if [[ -n "$title" ]]; then
        echo "$title"
    else
        local filename="${lesson_path##*/}"
        echo "${filename%.md}"
    fi
}

# Get next lesson
info_get_next_lesson() {
    local progress
    local total
    local jq_bin=""
    progress=$(info_get_onboard_progress)
    total=$(info_get_lessons_total)

    if [[ ! "$total" =~ ^[0-9]+$ ]] || [[ "$total" -le 0 ]]; then
        echo "No lessons available"
        return 0
    fi

    jq_bin="$(info_system_binary_path jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        local completed_count
        completed_count=$("$jq_bin" -r '(.completed // []) | length' <<< "$progress" 2>/dev/null || echo "0")

        if [[ "$completed_count" -ge "$total" ]]; then
            echo "All complete!"
            return 0
        fi

        local next_idx
        next_idx=$("$jq_bin" -r --argjson total "$total" '(.completed // []) as $c | ([range(0;$total) as $i | select(($c | index($i)) == null) | $i] | first // 0)' <<< "$progress" 2>/dev/null || echo "0")
        [[ "$next_idx" =~ ^[0-9]+$ ]] || next_idx=0

        local title
        title=$(info_get_lesson_title "$next_idx")
        echo "Lesson $((next_idx + 1)) - $title"
    else
        local completed_count
        completed_count=$(info_get_lessons_completed)

        if [[ "$completed_count" =~ ^[0-9]+$ ]] && [[ "$completed_count" -ge "$total" ]]; then
            echo "All complete!"
            return 0
        fi

        local completed_csv
        completed_csv="$(info_get_onboard_completed_csv || true)"
        completed_csv="${completed_csv//[[:space:]]/}"

        local next_idx=0
        local idx
        for ((idx = 0; idx < total; idx++)); do
            if [[ ",${completed_csv}," != *",$idx,"* ]]; then
                next_idx="$idx"
                break
            fi
        done

        local title
        title=$(info_get_lesson_title "$next_idx")
        echo "Lesson $((next_idx + 1)) - $title"
    fi
}

# ============================================================
# Quick Commands Data
# ============================================================
# Top 8 most useful commands for quick reference

info_get_quick_commands() {
    cat <<'EOF'
cc|Launch Claude Code
cod|Launch Codex CLI
gmi|Launch Gemini CLI
ntm new X|Create tmux session
ntm attach X|Resume session
lazygit|Visual git interface
rg "term"|Search code
z folder|Jump to folder
EOF
}

# ============================================================
# Installed Tools Detection
# ============================================================

info_get_installed_tools_summary() {
    local shell_ok lang_ok agents_ok stack_ok
    local shell_home="${TARGET_HOME:-${_INFO_CURRENT_HOME:-}}"

    # Shell tools
    shell_ok="○"
    if info_binary_exists "zsh" && [[ -d "$shell_home/.oh-my-zsh" ]]; then
        shell_ok="✓"
    fi

    # Languages
    lang_ok="○"
    local lang_count=0
    info_binary_exists "bun" && lang_count=$((lang_count + 1))
    info_binary_exists "uv" && lang_count=$((lang_count + 1))
    info_binary_exists "rustc" && lang_count=$((lang_count + 1))
    info_binary_exists "go" && lang_count=$((lang_count + 1))
    [[ $lang_count -ge 3 ]] && lang_ok="✓"

    # Agents
    agents_ok="○"
    local agent_count=0
    info_binary_exists "claude" && agent_count=$((agent_count + 1))
    info_binary_exists "codex" && agent_count=$((agent_count + 1))
    info_binary_exists "gemini" && agent_count=$((agent_count + 1))
    [[ $agent_count -ge 2 ]] && agents_ok="✓"

    # Stack tools
    stack_ok="○"
    info_binary_exists "ntm" && stack_ok="✓"

    echo "shell:$shell_ok|lang:$lang_ok|agents:$agents_ok|stack:$stack_ok"
}

info_render_onboard_bar() {
    local completed="${1:-0}"
    local total="${2:-0}"
    local width="${3:-24}"
    local filled=0
    local empty="$width"

    [[ "$completed" =~ ^[0-9]+$ ]] || completed=0
    [[ "$total" =~ ^[0-9]+$ ]] || total=0
    [[ "$width" =~ ^[0-9]+$ ]] || width=24

    if (( total > 0 )); then
        (( completed < 0 )) && completed=0
        (( completed > total )) && completed="$total"
        filled=$((completed * width / total))
        if (( completed > 0 && filled == 0 )); then
            filled=1
        fi
        (( filled > width )) && filled="$width"
        empty=$((width - filled))
    fi

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    printf '%s' "$bar"
}

# ============================================================
# Terminal Output Renderer
# ============================================================

info_render_terminal() {
    local hostname ip uptime os_version os_codename
    hostname=$(info_get_hostname)
    ip=$(info_get_ip)
    uptime=$(info_get_uptime)
    os_version=$(info_get_os_version)
    os_codename=$(info_get_os_codename)

    local install_date skipped_tools
    install_date=$(info_get_install_date)
    skipped_tools=$(info_get_skipped_tools)

    local lessons_completed lessons_total next_lesson
    lessons_completed=$(info_get_lessons_completed)
    lessons_total=$(info_get_lessons_total)
    next_lesson=$(info_get_next_lesson)

    local tools_summary
    tools_summary=$(info_get_installed_tools_summary)

    # Header
    echo -e "${C_CYAN}╭─────────────────────────────────────────────────────────────╮${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET}  ${C_BOLD}ACFS Environment Info${C_RESET}                                      ${C_CYAN}│${C_RESET}"
    echo -e "${C_CYAN}╰─────────────────────────────────────────────────────────────╯${C_RESET}"
    echo ""

    # System section
    echo -e "${C_BOLD}System${C_RESET}"
    printf "  %-12s ${C_GREEN}%s${C_RESET}\n" "Hostname:" "$hostname"
    printf "  %-12s ${C_GREEN}%s${C_RESET}\n" "IP Address:" "$ip"
    printf "  %-12s %s\n" "Uptime:" "$uptime"
    printf "  %-12s Ubuntu %s (%s)\n" "OS:" "$os_version" "$os_codename"
    echo ""

    # Installed Tools section
    echo -e "${C_BOLD}Installed Tools${C_RESET}"

    # Parse tools summary
    local shell_status lang_status agents_status stack_status
    IFS='|' read -r shell_status lang_status agents_status stack_status <<< "$tools_summary"

    local shell_icon="${shell_status#*:}"
    local lang_icon="${lang_status#*:}"
    local agents_icon="${agents_status#*:}"
    local stack_icon="${stack_status#*:}"

    # Color the icons
    [[ "$shell_icon" == "✓" ]] && shell_icon="${C_GREEN}✓${C_RESET}" || shell_icon="${C_GRAY}○${C_RESET}"
    [[ "$lang_icon" == "✓" ]] && lang_icon="${C_GREEN}✓${C_RESET}" || lang_icon="${C_GRAY}○${C_RESET}"
    [[ "$agents_icon" == "✓" ]] && agents_icon="${C_GREEN}✓${C_RESET}" || agents_icon="${C_GRAY}○${C_RESET}"
    [[ "$stack_icon" == "✓" ]] && stack_icon="${C_GREEN}✓${C_RESET}" || stack_icon="${C_GRAY}○${C_RESET}"

    echo -e "  $shell_icon ${C_DIM}Shell:${C_RESET}     zsh + oh-my-zsh + powerlevel10k"
    echo -e "  $lang_icon ${C_DIM}Languages:${C_RESET} bun, uv, rust, go"
    echo -e "  $agents_icon ${C_DIM}Agents:${C_RESET}    claude, codex, gemini"
    echo -e "  $stack_icon ${C_DIM}Stack:${C_RESET}     ntm, bv, lazygit"

    if [[ -n "$skipped_tools" ]]; then
        echo -e "  ${C_GRAY}○ Skipped:   $skipped_tools${C_RESET}"
    fi
    echo ""

    # Quick Commands section
    echo -e "${C_BOLD}Quick Commands${C_RESET}"
    while IFS='|' read -r cmd desc; do
        printf "  ${C_CYAN}%-14s${C_RESET} %s\n" "$cmd" "$desc"
    done < <(info_get_quick_commands)
    echo ""

    # Onboard Progress section
    echo -e "${C_BOLD}Onboard Progress${C_RESET}"
    if [[ "$lessons_total" =~ ^[0-9]+$ ]] && (( lessons_total == 0 )); then
        echo -e "  No lessons available"
        echo -e "  ${C_DIM}Re-run the installer or set ACFS_LESSONS_DIR to a directory with onboarding lessons.${C_RESET}"
    else
        local percent=0
        local display_completed="$lessons_completed"
        if [[ "$lessons_completed" =~ ^[0-9]+$ ]] && [[ "$lessons_total" =~ ^[0-9]+$ ]] && (( lessons_total > 0 )); then
            if (( lessons_completed > lessons_total )); then
                display_completed="$lessons_total"
            fi
            percent=$((display_completed * 100 / lessons_total))
        fi
        local bar=""
        bar=$(info_render_onboard_bar "$display_completed" "$lessons_total" 24)

        echo -e "  ${C_GREEN}$bar${C_RESET} ${display_completed}/${lessons_total} lessons (${percent}%)"
        if [[ "$lessons_completed" -lt "$lessons_total" ]]; then
            echo -e "  ${C_DIM}Next:${C_RESET} $next_lesson"
        fi
    fi
    echo ""

    # Footer
    echo -e "${C_DIM}Run 'acfs doctor' for health verification${C_RESET}"
    if [[ "$lessons_total" =~ ^[0-9]+$ ]] && (( lessons_total > 0 )); then
        echo -e "${C_DIM}Run 'onboard' to continue learning${C_RESET}"
    fi
}

# ============================================================
# Minimal Output Renderer
# ============================================================

info_render_minimal() {
    local ip hostname
    ip=$(info_get_ip)
    hostname=$(info_get_hostname)

    echo "ACFS @ $hostname ($ip)"
    echo ""
    echo "Quick commands: cc (Claude), cod (Codex), ntm (sessions)"
    echo "Run 'acfs info' for full details"
}

# ============================================================
# JSON Output Renderer
# ============================================================

info_render_json() {
    local hostname ip uptime os_version os_codename
    hostname=$(info_get_hostname)
    ip=$(info_get_ip)
    uptime=$(info_get_uptime)
    os_version=$(info_get_os_version)
    os_codename=$(info_get_os_codename)

    local install_date
    install_date=$(info_get_install_date)
    local skipped_tools_json="[]"
    skipped_tools_json="$(info_get_skipped_tools_json)"

    local lessons_completed lessons_total next_lesson
    lessons_completed=$(info_get_lessons_completed)
    lessons_total=$(info_get_lessons_total)
    next_lesson=$(info_get_next_lesson)

    # Build JSON manually for compatibility (jq might not be available)
    # Ensure all string values are JSON-escaped so output is always valid JSON.
    _info_json_escape() {
        local s="$1"
        s="${s//\\/\\\\}"      # \ -> \\
        s="${s//\"/\\\"}"      # " -> \"
        s="${s//$'\n'/\\n}"    # newline -> \n
        s="${s//$'\r'/\\r}"    # carriage return -> \r
        s="${s//$'\t'/\\t}"    # tab -> \t
        printf '%s' "$s"
    }

    [[ "$lessons_completed" =~ ^[0-9]+$ ]] || lessons_completed=0
    [[ "$lessons_total" =~ ^[0-9]+$ ]] || lessons_total=0

    local hostname_json ip_json uptime_json os_version_json os_codename_json
    hostname_json="$(_info_json_escape "$hostname")"
    ip_json="$(_info_json_escape "$ip")"
    uptime_json="$(_info_json_escape "$uptime")"
    os_version_json="$(_info_json_escape "$os_version")"
    os_codename_json="$(_info_json_escape "$os_codename")"

    local install_date_json next_lesson_json
    install_date_json="$(_info_json_escape "$install_date")"
    next_lesson_json="$(_info_json_escape "$next_lesson")"

    local json_output
    json_output=$(cat <<EOF
{
  "system": {
    "hostname": "$hostname_json",
    "ip": "$ip_json",
    "uptime": "$uptime_json",
    "os": {
      "version": "$os_version_json",
      "codename": "$os_codename_json"
    }
  },
  "installation": {
    "date": "$install_date_json",
    "skipped_tools": $skipped_tools_json
  },
  "onboard": {
    "lessons_completed": $lessons_completed,
    "total_lessons": $lessons_total,
    "next_lesson": "$next_lesson_json"
  },
  "quick_commands": [
    {"cmd": "cc", "desc": "Launch Claude Code"},
    {"cmd": "cod", "desc": "Launch Codex CLI"},
    {"cmd": "gmi", "desc": "Launch Gemini CLI"},
    {"cmd": "ntm new X", "desc": "Create tmux session"},
    {"cmd": "ntm attach X", "desc": "Resume session"},
    {"cmd": "lazygit", "desc": "Visual git interface"},
    {"cmd": "rg term", "desc": "Search code"},
    {"cmd": "z folder", "desc": "Jump to folder"}
  ]
}
EOF
)

    # Use output formatting library if available
    if type -t acfs_format_output &>/dev/null; then
        local resolved_format
        resolved_format=$(acfs_resolve_format "$_INFO_OUTPUT_FORMAT")
        acfs_format_output "$json_output" "$resolved_format" "$_INFO_SHOW_STATS"
    else
        # Fallback: direct JSON output
        printf '%s\n' "$json_output"
    fi
}

# ============================================================
# HTML Output Renderer
# ============================================================

info_render_html() {
    local hostname ip uptime os_version os_codename
    local generated_at="unknown"
    local date_bin=""
    hostname=$(info_get_hostname)
    ip=$(info_get_ip)
    uptime=$(info_get_uptime)
    os_version=$(info_get_os_version)
    os_codename=$(info_get_os_codename)
    date_bin="$(info_system_binary_path date 2>/dev/null || true)"
    if [[ -n "$date_bin" ]]; then
        generated_at="$("$date_bin" -Iseconds 2>/dev/null || echo "unknown")"
    fi

    # Escape values for safe HTML rendering (prevent broken markup if hostname/etc contain
    # special characters). This output may be served via `acfs dashboard serve`.
    _info_html_escape() {
        local s="$1"
        s="${s//&/&amp;}"
        s="${s//</&lt;}"
        s="${s//>/&gt;}"
        s="${s//\"/&quot;}"
        s="${s//\'/&#39;}"
        printf '%s' "$s"
    }

    local hostname_html ip_html uptime_html os_version_html os_codename_html
    hostname_html="$(_info_html_escape "$hostname")"
    ip_html="$(_info_html_escape "$ip")"
    uptime_html="$(_info_html_escape "$uptime")"
    os_version_html="$(_info_html_escape "$os_version")"
    os_codename_html="$(_info_html_escape "$os_codename")"

    local lessons_completed lessons_total
    lessons_completed=$(info_get_lessons_completed)
    lessons_total=$(info_get_lessons_total)
    local percent=0
    local display_completed="$lessons_completed"
    if [[ "$lessons_completed" =~ ^[0-9]+$ ]] && [[ "$lessons_total" =~ ^[0-9]+$ ]] && (( lessons_total > 0 )); then
        if (( lessons_completed > lessons_total )); then
            display_completed="$lessons_total"
        fi
        percent=$((display_completed * 100 / lessons_total))
    fi

    local onboard_card
    if [[ "$lessons_total" =~ ^[0-9]+$ ]] && (( lessons_total == 0 )); then
        onboard_card=$(cat <<'EOF'
        <div class="card">
            <h2>Onboard Progress</h2>
            <p class="label">No lessons available.</p>
            <p class="label">Re-run the installer or set ACFS_LESSONS_DIR to a directory with onboarding lessons.</p>
        </div>
EOF
)
    else
        onboard_card=$(cat <<EOF
        <div class="card">
            <h2>Onboard Progress</h2>
            <div class="progress-bar">
                <div class="progress-fill">${display_completed}/${lessons_total}</div>
            </div>
        </div>
EOF
)
    fi

    cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ACFS Dashboard - $hostname_html</title>
    <style>
        :root {
            --bg: #1e1e2e;
            --surface: #313244;
            --text: #cdd6f4;
            --subtext: #a6adc8;
            --green: #a6e3a1;
            --cyan: #89dceb;
            --yellow: #f9e2af;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg);
            color: var(--text);
            padding: 2rem;
            line-height: 1.6;
        }
        .container { max-width: 800px; margin: 0 auto; }
        h1 { color: var(--cyan); margin-bottom: 1.5rem; }
        h2 { color: var(--text); font-size: 1.1rem; margin: 1.5rem 0 0.75rem; }
        .card {
            background: var(--surface);
            border-radius: 12px;
            padding: 1.5rem;
            margin-bottom: 1rem;
        }
        .grid { display: grid; grid-template-columns: 120px 1fr; gap: 0.5rem; }
        .label { color: var(--subtext); }
        .value { color: var(--green); }
        .cmd { font-family: monospace; color: var(--cyan); }
        .progress-bar {
            background: var(--bg);
            border-radius: 8px;
            height: 24px;
            overflow: hidden;
            margin: 0.5rem 0;
        }
        .progress-fill {
            background: linear-gradient(90deg, var(--green), var(--cyan));
            height: 100%;
            width: ${percent}%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 0.8rem;
            font-weight: bold;
        }
        .footer { margin-top: 2rem; color: var(--subtext); font-size: 0.9rem; }
    </style>
</head>
<body>
    <div class="container">
        <h1>ACFS Dashboard</h1>

        <div class="card">
            <h2>System</h2>
            <div class="grid">
                <span class="label">Hostname</span><span class="value">$hostname_html</span>
                <span class="label">IP Address</span><span class="value">$ip_html</span>
                <span class="label">Uptime</span><span>$uptime_html</span>
                <span class="label">OS</span><span>Ubuntu $os_version_html ($os_codename_html)</span>
            </div>
        </div>

        <div class="card">
            <h2>Quick Commands</h2>
            <div class="grid">
                <span class="cmd">cc</span><span>Launch Claude Code</span>
                <span class="cmd">cod</span><span>Launch Codex CLI</span>
                <span class="cmd">ntm new X</span><span>Create tmux session</span>
                <span class="cmd">lazygit</span><span>Visual git interface</span>
            </div>
        </div>

$onboard_card

        <div class="footer">
            Generated: $generated_at<br>
            Run <code>acfs doctor</code> for health verification
        </div>
    </div>
</body>
</html>
EOF
}

# ============================================================
# Main Entry Point
# ============================================================

info_main() {
    local output_mode="terminal"
    _INFO_OUTPUT_FORMAT=""
    _INFO_SHOW_STATS=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json|-j)
                output_mode="json"
                ;;
            --format|-f)
                shift
                if [[ -z "${1:-}" || "$1" == -* ]]; then
                    echo "Error: --format requires a value (json or toon)" >&2
                    return 1
                fi
                _INFO_OUTPUT_FORMAT="$1"
                if [[ "$_INFO_OUTPUT_FORMAT" != "json" && "$_INFO_OUTPUT_FORMAT" != "toon" ]]; then
                    echo "Error: invalid format '$_INFO_OUTPUT_FORMAT' (expected json or toon)" >&2
                    return 1
                fi
                output_mode="json"  # --format implies structured output
                ;;
            --format=*)
                _INFO_OUTPUT_FORMAT="${1#*=}"
                if [[ -z "$_INFO_OUTPUT_FORMAT" ]]; then
                    echo "Error: --format requires a value (json or toon)" >&2
                    return 1
                fi
                if [[ "$_INFO_OUTPUT_FORMAT" != "json" && "$_INFO_OUTPUT_FORMAT" != "toon" ]]; then
                    echo "Error: invalid format '$_INFO_OUTPUT_FORMAT' (expected json or toon)" >&2
                    return 1
                fi
                output_mode="json"
                ;;
            --toon|-t)
                _INFO_OUTPUT_FORMAT="toon"
                output_mode="json"
                ;;
            --stats)
                _INFO_SHOW_STATS=true
                ;;
            --html|-H)
                output_mode="html"
                ;;
            --minimal|-m)
                output_mode="minimal"
                ;;
            --help|-h)
                echo "Usage: acfs info [OPTIONS]"
                echo ""
                echo "Display ACFS environment information."
                echo ""
                echo "Options:"
                echo "  --json, -j         Output as JSON"
                echo "  --format <fmt>     Output format: json or toon (env: ACFS_OUTPUT_FORMAT, TOON_DEFAULT_FORMAT)"
                echo "  --toon, -t         Shorthand for --format toon"
                echo "  --stats            Show token savings statistics (JSON vs TOON bytes)"
                echo "  --html, -H         Output as self-contained HTML"
                echo "  --minimal, -m      Show only essentials"
                echo "  --help, -h         Show this help"
                return 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Run 'acfs info --help' for usage" >&2
                return 1
                ;;
        esac
        shift
    done

    info_prepare_context

    # Render based on output mode
    case "$output_mode" in
        json)
            info_render_json
            ;;
        html)
            info_render_html
            ;;
        minimal)
            info_render_minimal
            ;;
        terminal)
            info_render_terminal
            ;;
    esac
}

info_restore_home_if_sourced() {
    [[ "$_INFO_WAS_SOURCED" == "true" ]] || return 0

    if [[ "$_INFO_ORIGINAL_HOME_WAS_SET" == "true" ]]; then
        HOME="$_INFO_ORIGINAL_HOME"
        export HOME
    else
        unset HOME
    fi
}

info_restore_home_if_sourced

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    info_main "$@"
fi
