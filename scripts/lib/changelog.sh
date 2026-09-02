#!/usr/bin/env bash
# ============================================================
# ACFS Changelog - Show Recent Changes
#
# Displays changelog entries filtered by date, formatted for terminal.
# Parses CHANGELOG.md in Keep a Changelog format.
#
# Usage:
#   acfs changelog              # Since last update
#   acfs changelog --all        # Full history
#   acfs changelog --since 7d   # Last 7 days
#   acfs changelog --since 2w   # Last 2 weeks
#   acfs changelog --since 2026-01-01   # Since a calendar date
#   acfs changelog --json       # JSON output for scripting
#
# Design Philosophy:
#   - Speed: Parse CHANGELOG.md quickly using shell builtins
#   - Readable: Color-coded output with icons for change types
#   - Filterable: Support date-based filtering
#   - Scriptable: JSON output for automation
#
# Related beads:
#   - bd-2p56: acfs changelog: Show recent changes command
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_CHANGELOG_SH_LOADED:-}" ]]; then
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
    fi
    exit 0
fi
_ACFS_CHANGELOG_SH_LOADED=1

_CHANGELOG_WAS_SOURCED=false
_CHANGELOG_ORIGINAL_HOME=""
_CHANGELOG_ORIGINAL_HOME_WAS_SET=false
_CHANGELOG_RESTORE_ERREXIT=false
_CHANGELOG_RESTORE_NOUNSET=false
_CHANGELOG_RESTORE_PIPEFAIL=false
if [[ -v HOME ]]; then
    _CHANGELOG_ORIGINAL_HOME="$HOME"
    _CHANGELOG_ORIGINAL_HOME_WAS_SET=true
fi
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    _CHANGELOG_WAS_SOURCED=true
    [[ $- == *e* ]] && _CHANGELOG_RESTORE_ERREXIT=true
    [[ $- == *u* ]] && _CHANGELOG_RESTORE_NOUNSET=true
    if shopt -qo pipefail 2>/dev/null; then
        _CHANGELOG_RESTORE_PIPEFAIL=true
    fi
fi

set -euo pipefail

changelog_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

changelog_existing_abs_home() {
    local path_value=""

    path_value="$(changelog_sanitize_abs_nonroot_path "${1:-}" 2>/dev/null || true)"
    [[ -n "$path_value" ]] || return 1
    [[ -d "$path_value" ]] || return 1
    printf '%s\n' "$path_value"
}

changelog_system_binary_path() {
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

changelog_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(changelog_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(changelog_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

changelog_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(changelog_system_binary_path getent 2>/dev/null || true)"
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

changelog_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    passwd_home="$(changelog_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
    [[ -n "$passwd_home" ]] || return 1
    printf '%s\n' "$passwd_home"
}

changelog_is_valid_username() {
    local username="${1:-}"
    [[ "$username" =~ ^[a-z_][a-z0-9._-]*$ ]]
}

changelog_resolve_current_home() {
    local current_user=""
    local fallback_home=""
    local passwd_entry=""
    local passwd_home=""

    fallback_home="$(changelog_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
    if [[ "${_CHANGELOG_WAS_SOURCED:-false}" == "true" ]]; then
        fallback_home="$(changelog_sanitize_abs_nonroot_path "${_CHANGELOG_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
    fi

    current_user="$(changelog_resolve_current_user 2>/dev/null || true)"

    if [[ "$current_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    if [[ -n "$current_user" ]]; then
        passwd_entry="$(changelog_getent_passwd_entry "$current_user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            passwd_home="$(changelog_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
            if [[ -n "$passwd_home" ]]; then
                printf '%s\n' "$passwd_home"
                return 0
            fi
        fi
    fi

    [[ -n "$fallback_home" ]] || return 1
    printf '%s\n' "$fallback_home"
}
changelog_initial_current_home() {
    local cached_home=""
    local resolved_home=""

    if [[ "${_CHANGELOG_WAS_SOURCED:-false}" == "true" ]] && [[ -z "${TARGET_HOME:-}${TARGET_USER:-}${ACFS_HOME:-}${ACFS_STATE_FILE:-}${ACFS_SYSTEM_STATE_FILE:-}" ]]; then
        cached_home="$(changelog_sanitize_abs_nonroot_path "${_CHANGELOG_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
        if [[ -n "$cached_home" ]]; then
            printf '%s\n' "$cached_home"
            return 0
        fi
    fi

    resolved_home="$(changelog_resolve_current_home 2>/dev/null || true)"
    if [[ -n "$resolved_home" ]]; then
        printf '%s\n' "$resolved_home"
        return 0
    fi

    if [[ "${_CHANGELOG_WAS_SOURCED:-false}" == "true" ]]; then
        cached_home="$(changelog_sanitize_abs_nonroot_path "${_CHANGELOG_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
        if [[ -n "$cached_home" ]]; then
            printf '%s\n' "$cached_home"
            return 0
        fi
    fi

    return 1
}
_CHANGELOG_CURRENT_HOME="$(changelog_initial_current_home 2>/dev/null || true)"
if [[ -n "$_CHANGELOG_CURRENT_HOME" ]]; then
    HOME="$_CHANGELOG_CURRENT_HOME"
    export HOME
fi

# ============================================================
# Configuration
# ============================================================
_CHANGELOG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CHANGELOG_EXPLICIT_ACFS_HOME="$(changelog_sanitize_abs_nonroot_path "${ACFS_HOME:-}" 2>/dev/null || true)"
_CHANGELOG_DEFAULT_ACFS_HOME=""
[[ -n "$_CHANGELOG_CURRENT_HOME" ]] && _CHANGELOG_DEFAULT_ACFS_HOME="${_CHANGELOG_CURRENT_HOME}/.acfs"
_CHANGELOG_ACFS_HOME="${_CHANGELOG_EXPLICIT_ACFS_HOME:-$_CHANGELOG_DEFAULT_ACFS_HOME}"
_CHANGELOG_EXPLICIT_ACFS_REPO="$(changelog_sanitize_abs_nonroot_path "${ACFS_REPO:-}" 2>/dev/null || true)"
_CHANGELOG_ACFS_REPO="${_CHANGELOG_EXPLICIT_ACFS_REPO:-$_CHANGELOG_ACFS_HOME}"
_CHANGELOG_SYSTEM_STATE_WAS_EXPLICIT=false
[[ -n "${ACFS_SYSTEM_STATE_FILE:-}" ]] && [[ "${ACFS_SYSTEM_STATE_FILE%/}" != "/var/lib/acfs/state.json" ]] && _CHANGELOG_SYSTEM_STATE_WAS_EXPLICIT=true
_CHANGELOG_SYSTEM_STATE_FILE="$(changelog_sanitize_abs_nonroot_path "${ACFS_SYSTEM_STATE_FILE:-/var/lib/acfs/state.json}" 2>/dev/null || true)"
if [[ -z "$_CHANGELOG_SYSTEM_STATE_FILE" ]]; then
    _CHANGELOG_SYSTEM_STATE_FILE="/var/lib/acfs/state.json"
fi
_CHANGELOG_EXPLICIT_TARGET_HOME_RAW="${TARGET_HOME:-}"
_CHANGELOG_EXPLICIT_TARGET_USER_RAW="${TARGET_USER:-}"
_CHANGELOG_EXPLICIT_TARGET_HOME="$(changelog_existing_abs_home "${TARGET_HOME:-}" 2>/dev/null || true)"
_CHANGELOG_RESOLVED_ACFS_HOME=""
_CHANGELOG_FILE="${_CHANGELOG_ACFS_REPO:+${_CHANGELOG_ACFS_REPO}/CHANGELOG.md}"

# Find CHANGELOG.md - check multiple locations
find_changelog() {
    local locations=()
    local explicit_target_requested=false

    if [[ -n "$_CHANGELOG_EXPLICIT_TARGET_HOME_RAW" ]] || [[ -n "$_CHANGELOG_EXPLICIT_TARGET_USER_RAW" ]]; then
        explicit_target_requested=true
    fi

    [[ -n "$_CHANGELOG_FILE" ]] && locations+=("$_CHANGELOG_FILE")
    if [[ -n "$_CHANGELOG_ACFS_HOME" ]] && [[ "${_CHANGELOG_ACFS_HOME}/CHANGELOG.md" != "$_CHANGELOG_FILE" ]]; then
        locations+=("${_CHANGELOG_ACFS_HOME}/CHANGELOG.md")
    fi
    if [[ "$explicit_target_requested" != "true" ]]; then
        locations+=("/data/projects/agentic_coding_flywheel_setup/CHANGELOG.md")
        [[ -n "$_CHANGELOG_CURRENT_HOME" ]] && locations+=("${_CHANGELOG_CURRENT_HOME}/.acfs/CHANGELOG.md")
    fi

    for loc in "${locations[@]}"; do
        if [[ -f "$loc" ]]; then
            echo "$loc"
            return 0
        fi
    done

    return 1
}

# ============================================================
# Color Constants - respect NO_COLOR standard (https://no-color.org/)
# NO_COLOR with any value disables colors. Related: bd-39ye
# ============================================================
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    _CHANGELOG_C_RESET='\033[0m'
    _CHANGELOG_C_BOLD='\033[1m'
    _CHANGELOG_C_DIM='\033[2m'
    _CHANGELOG_C_GREEN='\033[0;32m'
    _CHANGELOG_C_CYAN='\033[0;36m'
    _CHANGELOG_C_YELLOW='\033[0;33m'
    _CHANGELOG_C_RED='\033[0;31m'
    _CHANGELOG_C_MAGENTA='\033[0;35m'
    _CHANGELOG_C_GRAY='\033[0;90m'
else
    _CHANGELOG_C_RESET=''
    _CHANGELOG_C_BOLD=''
    _CHANGELOG_C_DIM=''
    _CHANGELOG_C_GREEN=''
    _CHANGELOG_C_CYAN=''
    _CHANGELOG_C_YELLOW=''
    _CHANGELOG_C_RED=''
    _CHANGELOG_C_MAGENTA=''
    _CHANGELOG_C_GRAY=''
fi

# ============================================================
# Helper Functions
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

changelog_home_for_user() {
    local user="$1"
    local passwd_entry=""
    local home_candidate=""
    local current_user=""

    [[ -n "$user" ]] || return 1

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    current_user="$(changelog_resolve_current_user 2>/dev/null || true)"
    if [[ "$user" == "$current_user" ]] && [[ "${_CHANGELOG_WAS_SOURCED:-false}" == "true" ]]; then
        home_candidate="${_CHANGELOG_CURRENT_HOME:-}"
        if [[ -n "$home_candidate" ]]; then
            printf '%s\n' "$home_candidate"
            return 0
        fi
    fi

    passwd_entry="$(changelog_getent_passwd_entry "$user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        home_candidate="$(changelog_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
        if [[ -n "$home_candidate" ]]; then
            printf '%s\n' "$home_candidate"
            return 0
        fi
    fi

    if [[ "$user" == "$current_user" ]]; then
        home_candidate="${_CHANGELOG_CURRENT_HOME:-}"
        if [[ -z "$home_candidate" ]]; then
            home_candidate="$(changelog_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
        fi
        if [[ -n "$home_candidate" ]]; then
            printf '%s\n' "$home_candidate"
            return 0
        fi
    fi

    return 1
}

changelog_resolve_explicit_target_home() {
    local target_home=""
    local resolved_home=""

    if [[ -n "$_CHANGELOG_EXPLICIT_TARGET_USER_RAW" ]]; then
        changelog_is_valid_username "$_CHANGELOG_EXPLICIT_TARGET_USER_RAW" || return 1
        resolved_home="$(changelog_existing_abs_home "$(changelog_home_for_user "$_CHANGELOG_EXPLICIT_TARGET_USER_RAW" 2>/dev/null || true)" 2>/dev/null || true)"
        if [[ -n "$resolved_home" ]]; then
            printf '%s\n' "${resolved_home%/}"
            return 0
        fi
        target_home="$_CHANGELOG_EXPLICIT_TARGET_HOME"
        if [[ -n "$target_home" ]] && [[ "$target_home" != "${_CHANGELOG_CURRENT_HOME:-}" ]] && {
            [[ -f "$target_home/.acfs/state.json" ]] || [[ -f "$target_home/.acfs/VERSION" ]] || [[ -f "$target_home/.acfs/CHANGELOG.md" ]] || [[ -d "$target_home/.acfs/onboard" ]]
        }; then
            printf '%s\n' "${target_home%/}"
            return 0
        fi
        return 1
    fi

    target_home="$_CHANGELOG_EXPLICIT_TARGET_HOME"
    if [[ -n "$target_home" ]]; then
        printf '%s\n' "${target_home%/}"
        return 0
    fi

    return 1
}

changelog_read_target_user_from_state() {
    local state_file="$1"
    changelog_read_state_string "$state_file" "target_user"
}

changelog_read_state_string() {
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

changelog_read_target_home_from_state() {
    local state_file="$1"
    local target_home=""

    target_home="$(changelog_read_state_string "$state_file" "target_home" 2>/dev/null || true)"
    [[ -n "$target_home" ]] || return 1
    [[ "$target_home" == /* ]] || return 1
    [[ "$target_home" != "/" ]] || return 1
    printf '%s\n' "${target_home%/}"
}

changelog_script_acfs_home() {
    local candidate=""
    candidate=$(cd "$_CHANGELOG_SCRIPT_DIR/../.." 2>/dev/null && pwd) || return 1
    [[ "$(basename "$candidate")" == ".acfs" ]] || return 1
    printf '%s\n' "$candidate"
}

changelog_current_home_acfs_candidate() {
    local candidate="$_CHANGELOG_DEFAULT_ACFS_HOME"
    local current_home="$_CHANGELOG_CURRENT_HOME"
    local current_user=""
    local original_home=""
    local state_home=""
    local state_user=""
    local state_user_home=""

    [[ -n "$candidate" && -n "$current_home" ]] || return 1
    [[ "$current_home" != "/root" ]] || return 1
    [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -f "$candidate/CHANGELOG.md" ]] || return 1

    if [[ "${_CHANGELOG_ORIGINAL_HOME_WAS_SET:-false}" == true ]]; then
        original_home="$(changelog_sanitize_abs_nonroot_path "$_CHANGELOG_ORIGINAL_HOME" 2>/dev/null || true)"
        [[ -n "$original_home" && "$original_home" == "$current_home" ]] || return 1
    fi

    current_user="$(changelog_resolve_current_user 2>/dev/null || true)"
    [[ -n "$current_user" && "$current_user" != "root" ]] || return 1

    if [[ -f "$candidate/state.json" ]]; then
        state_home="$(changelog_read_target_home_from_state "$candidate/state.json" 2>/dev/null || true)"
        [[ -z "$state_home" || "$state_home" == "$current_home" ]] || return 1

        state_user="$(changelog_read_target_user_from_state "$candidate/state.json" 2>/dev/null || true)"
        if [[ -n "$state_user" && "$state_user" != "$current_user" ]]; then
            state_user_home="$(changelog_home_for_user "$state_user" 2>/dev/null || true)"
            [[ "$state_user_home" == "$current_home" ]] || return 1
        fi
    fi

    printf '%s\n' "$candidate"
}

resolve_changelog_acfs_home() {
    if [[ -n "$_CHANGELOG_RESOLVED_ACFS_HOME" ]]; then
        printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
        return 0
    fi

    local candidate=""
    local target_home=""
    local target_user=""
    local explicit_target_home=""

    candidate=$(changelog_script_acfs_home 2>/dev/null || true)
    if [[ -n "$candidate" ]] && [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -f "$candidate/CHANGELOG.md" ]]; then
        _CHANGELOG_RESOLVED_ACFS_HOME="$candidate"
        printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
        return 0
    fi

    explicit_target_home="$(changelog_resolve_explicit_target_home 2>/dev/null || true)"
    if [[ -n "$explicit_target_home" ]]; then
        candidate="${explicit_target_home}/.acfs"
        if [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -f "$candidate/CHANGELOG.md" ]]; then
            _CHANGELOG_RESOLVED_ACFS_HOME="$candidate"
            printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    if [[ ! -f "$_CHANGELOG_SYSTEM_STATE_FILE" ]] && [[ -n "$_CHANGELOG_EXPLICIT_ACFS_HOME" ]] && [[ -f "$_CHANGELOG_EXPLICIT_ACFS_HOME/state.json" || -f "$_CHANGELOG_EXPLICIT_ACFS_HOME/VERSION" || -f "$_CHANGELOG_EXPLICIT_ACFS_HOME/CHANGELOG.md" ]]; then
        _CHANGELOG_RESOLVED_ACFS_HOME="$_CHANGELOG_EXPLICIT_ACFS_HOME"
        printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
        return 0
    fi

    candidate="$(changelog_current_home_acfs_candidate 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        _CHANGELOG_RESOLVED_ACFS_HOME="$candidate"
        printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ "$_CHANGELOG_SYSTEM_STATE_WAS_EXPLICIT" == true ]]; then
        target_home=$(changelog_read_target_home_from_state "$_CHANGELOG_SYSTEM_STATE_FILE" 2>/dev/null || true)
        if [[ -n "$target_home" ]]; then
            candidate="${target_home}/.acfs"
            if [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -f "$candidate/CHANGELOG.md" ]]; then
                _CHANGELOG_RESOLVED_ACFS_HOME="$candidate"
                printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
                return 0
            fi
        fi

        target_user=$(changelog_read_target_user_from_state "$_CHANGELOG_SYSTEM_STATE_FILE" 2>/dev/null || true)
        if [[ -n "$target_user" ]]; then
            target_home=$(changelog_home_for_user "$target_user" 2>/dev/null || true)
            candidate="${target_home}/.acfs"
            if [[ -n "$target_home" ]] && [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -f "$candidate/CHANGELOG.md" ]]; then
                _CHANGELOG_RESOLVED_ACFS_HOME="$candidate"
                printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
                return 0
            fi
        fi
    fi

    if [[ -n "$_CHANGELOG_EXPLICIT_ACFS_HOME" ]] && [[ -f "$_CHANGELOG_EXPLICIT_ACFS_HOME/state.json" || -f "$_CHANGELOG_EXPLICIT_ACFS_HOME/VERSION" || -f "$_CHANGELOG_EXPLICIT_ACFS_HOME/CHANGELOG.md" ]]; then
        _CHANGELOG_RESOLVED_ACFS_HOME="$_CHANGELOG_EXPLICIT_ACFS_HOME"
        printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ -n "$_CHANGELOG_EXPLICIT_TARGET_HOME_RAW" ]] || [[ -n "$_CHANGELOG_EXPLICIT_TARGET_USER_RAW" ]]; then
        _CHANGELOG_RESOLVED_ACFS_HOME=""
        printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ -n "${SUDO_USER:-}" ]]; then
        target_home=$(changelog_home_for_user "$SUDO_USER" 2>/dev/null || true)
        candidate="${target_home}/.acfs"
        if [[ -n "$target_home" ]] && [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -f "$candidate/CHANGELOG.md" ]]; then
            _CHANGELOG_RESOLVED_ACFS_HOME="$candidate"
            printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    target_home=$(changelog_read_target_home_from_state "$_CHANGELOG_SYSTEM_STATE_FILE" 2>/dev/null || true)
    if [[ -n "$target_home" ]]; then
        candidate="${target_home}/.acfs"
        if [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -f "$candidate/CHANGELOG.md" ]]; then
            _CHANGELOG_RESOLVED_ACFS_HOME="$candidate"
            printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    target_user=$(changelog_read_target_user_from_state "$_CHANGELOG_SYSTEM_STATE_FILE" 2>/dev/null || true)
    if [[ -n "$target_user" ]]; then
        target_home=$(changelog_home_for_user "$target_user" 2>/dev/null || true)
        candidate="${target_home}/.acfs"
        if [[ -n "$target_home" ]] && [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -f "$candidate/CHANGELOG.md" ]]; then
            _CHANGELOG_RESOLVED_ACFS_HOME="$candidate"
            printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    if [[ -n "$_CHANGELOG_ACFS_HOME" ]] && [[ -f "$_CHANGELOG_ACFS_HOME/state.json" || -f "$_CHANGELOG_ACFS_HOME/VERSION" || -f "$_CHANGELOG_ACFS_HOME/CHANGELOG.md" ]]; then
        _CHANGELOG_RESOLVED_ACFS_HOME="$_CHANGELOG_ACFS_HOME"
        printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
        return 0
    fi

    _CHANGELOG_RESOLVED_ACFS_HOME="$_CHANGELOG_ACFS_HOME"
    printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
}

resolve_changelog_state_file() {
    local candidate=""

    if [[ -n "$_CHANGELOG_ACFS_HOME" ]]; then
        candidate="${_CHANGELOG_ACFS_HOME}/state.json"
    fi

    if [[ -n "$candidate" ]] && [[ -f "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    if [[ -f "$_CHANGELOG_SYSTEM_STATE_FILE" ]]; then
        printf '%s\n' "$_CHANGELOG_SYSTEM_STATE_FILE"
        return 0
    fi

    printf '%s\n' "$candidate"
}

refresh_changelog_paths() {
    _CHANGELOG_ACFS_HOME="$(resolve_changelog_acfs_home)"
    if [[ -n "$_CHANGELOG_EXPLICIT_ACFS_REPO" ]]; then
        _CHANGELOG_ACFS_REPO="$_CHANGELOG_EXPLICIT_ACFS_REPO"
    else
        _CHANGELOG_ACFS_REPO="$_CHANGELOG_ACFS_HOME"
    fi
    _CHANGELOG_FILE="${_CHANGELOG_ACFS_REPO:+${_CHANGELOG_ACFS_REPO}/CHANGELOG.md}"
}

read_state_timestamp() {
    local state_file="$1"
    local ts=""
    local key=""

    [[ -f "$state_file" ]] || return 1

    if command -v jq &>/dev/null; then
        ts=$(jq -r '
            .last_updated //
            .last_completed_phase_ts //
            .updated_at //
            .last_update //
            .started_at //
            .install_date //
            empty
        ' "$state_file" 2>/dev/null || true)
    fi

    if [[ -z "$ts" || "$ts" == "null" ]]; then
        for key in last_updated last_completed_phase_ts updated_at last_update started_at install_date; do
            ts=$(sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" \
                "$state_file" 2>/dev/null | head -n 1)
            if [[ -n "$ts" ]]; then
                break
            fi
        done
    fi

    [[ -n "$ts" ]] || return 1
    printf '%s\n' "$ts"
}

# Get last update timestamp from state.json
get_last_update_date() {
    local state_file=""
    state_file="$(resolve_changelog_state_file)"
    local ts=""

    if ts=$(read_state_timestamp "$state_file" 2>/dev/null || true); then
        if [[ -n "$ts" ]]; then
            date -d "$ts" '+%Y-%m-%d' 2>/dev/null || echo ""
            return 0
        fi
    fi

    # Fallback: 30 days ago
    date -d "30 days ago" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d'
}

# Parse a --since duration ("30d", "2w", "1m", or a bare number of days) to
# a whole number of days. The unit is case-insensitive; months are 30 days.
# Anything else returns 1 without touching bash arithmetic, so the caller can
# print a friendly error instead of "10#30d: value too great for base" (#376).
parse_duration() {
    local input="${1:-}"
    local num=""
    local unit=""

    [[ "$input" =~ ^([0-9]+)([dDwWmM]?)$ ]] || return 1
    num="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2],,}"

    case "$unit" in
        ""|d) echo "$((10#$num))" ;;
        w) echo "$((10#$num * 7))" ;;
        m) echo "$((10#$num * 30))" ;;
        *) return 1 ;;
    esac
}

# True when the --since value is an ISO calendar date (YYYY-MM-DD).
is_iso_date() {
    [[ "${1:-}" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]]
}

# Format change type icon and color
format_change_type() {
    local type="$1"
    case "$type" in
        Added|added)
            printf "%b\n" "${_CHANGELOG_C_GREEN}+"
            ;;
        Changed|changed)
            printf "%b\n" "${_CHANGELOG_C_YELLOW}~"
            ;;
        Deprecated|deprecated)
            printf "%b\n" "${_CHANGELOG_C_MAGENTA}!"
            ;;
        Removed|removed)
            printf "%b\n" "${_CHANGELOG_C_RED}-"
            ;;
        Fixed|fixed)
            printf "%b\n" "${_CHANGELOG_C_CYAN}*"
            ;;
        Security|security)
            printf "%b\n" "${_CHANGELOG_C_RED}!"
            ;;
        Migration|migration)
            printf "%b\n" "${_CHANGELOG_C_YELLOW}>"
            ;;
        *)
            printf "%b\n" "${_CHANGELOG_C_GRAY}*"
            ;;
    esac
}

# Get ACFS version from VERSION file
get_acfs_version() {
    local version_file="${_CHANGELOG_ACFS_HOME}/VERSION"
    if [[ -f "$version_file" ]]; then
        cat "$version_file"
    else
        echo "unknown"
    fi
}

refresh_changelog_paths

# ============================================================
# Changelog Parsing
# ============================================================

# Parse CHANGELOG.md and output structured data
# Output format: VERSION|DATE|TYPE|ENTRY
parse_changelog() {
    local changelog_path="$1"
    local current_version=""
    local current_date=""
    local current_type=""
    local in_entry=false
    local entry_text=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Version header: ## [X.Y.Z] - YYYY-MM-DD or ## [Unreleased]
        if [[ "$line" =~ ^##[[:space:]]*\[([^\]]+)\]([[:space:]]*-[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}))? ]]; then
            # Output previous entry if exists
            if [[ -n "$entry_text" ]]; then
                echo "${current_version}|${current_date}|${current_type}|${entry_text}"
                entry_text=""
            fi

            current_version="${BASH_REMATCH[1]}"
            current_date="${BASH_REMATCH[3]:-$(date '+%Y-%m-%d')}"
            current_type=""
            in_entry=false
            continue
        fi

        # Change type header: ### Added, ### Changed, etc.
        if [[ "$line" =~ ^###[[:space:]]*(.+)$ ]]; then
            # Output previous entry if exists
            if [[ -n "$entry_text" ]]; then
                echo "${current_version}|${current_date}|${current_type}|${entry_text}"
                entry_text=""
            fi

            current_type="${BASH_REMATCH[1]}"
            in_entry=false
            continue
        fi

        # Entry line: starts with - or *
        if [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]+(.+)$ ]]; then
            # Output previous entry if exists
            if [[ -n "$entry_text" ]]; then
                echo "${current_version}|${current_date}|${current_type}|${entry_text}"
            fi

            entry_text="${BASH_REMATCH[1]}"
            in_entry=true
            continue
        fi

        # Continuation line (indented, part of previous entry)
        if [[ "$in_entry" == "true" ]] && [[ "$line" =~ ^[[:space:]]{2,}(.+)$ ]]; then
            entry_text="${entry_text} ${BASH_REMATCH[1]}"
            continue
        fi

        # Empty line ends current entry
        if [[ -z "$line" ]] && [[ -n "$entry_text" ]]; then
            echo "${current_version}|${current_date}|${current_type}|${entry_text}"
            entry_text=""
            in_entry=false
        fi
    done < "$changelog_path"

    # Output final entry if exists
    if [[ -n "$entry_text" ]]; then
        echo "${current_version}|${current_date}|${current_type}|${entry_text}"
    fi
}

# Filter entries by date
filter_by_date() {
    local since_date="$1"
    local since_epoch
    since_epoch=$(date -d "$since_date" '+%s' 2>/dev/null || echo 0)

    while IFS='|' read -r version date type entry; do
        [[ -z "$date" ]] && continue
        local entry_epoch
        entry_epoch=$(date -d "$date" '+%s' 2>/dev/null || echo 0)

        if [[ "$entry_epoch" -ge "$since_epoch" ]]; then
            echo "${version}|${date}|${type}|${entry}"
        fi
    done
}

# ============================================================
# Output Formatters
# ============================================================

# Format as terminal output with colors
format_terminal() {
    local last_version=""
    local last_date=""
    local last_type=""
    local count=0

    while IFS='|' read -r version date type entry; do
        [[ -z "$entry" ]] && continue

        # New version header
        if [[ "$version" != "$last_version" ]] || [[ "$date" != "$last_date" ]]; then
            if [[ "$count" -gt 0 ]]; then
                echo ""  # Space between versions
            fi
            printf "%b\n" "${_CHANGELOG_C_BOLD}${_CHANGELOG_C_CYAN}## ${version}${_CHANGELOG_C_RESET}${_CHANGELOG_C_GRAY} - ${date}${_CHANGELOG_C_RESET}"
            last_version="$version"
            last_date="$date"
            last_type=""
        fi

        # New type header
        if [[ "$type" != "$last_type" ]] && [[ -n "$type" ]]; then
            printf "%b\n" "${_CHANGELOG_C_DIM}### ${type}${_CHANGELOG_C_RESET}"
            last_type="$type"
        fi

        # Entry with icon
        local icon
        icon=$(format_change_type "$type")
        printf "%b\n" "  ${icon} ${entry}${_CHANGELOG_C_RESET}"

        ((++count))
    done

    if [[ "$count" -eq 0 ]]; then
        printf "%b\n" "${_CHANGELOG_C_GREEN}You're up to date! No new changes since your last update.${_CHANGELOG_C_RESET}"
    else
        echo ""
        printf "%b\n" "${_CHANGELOG_C_DIM}${count} change(s) shown${_CHANGELOG_C_RESET}"
    fi
}

# Format as JSON
format_json() {
    local first=true

    echo "{"
    echo '  "changes": ['

    while IFS='|' read -r version date type entry; do
        [[ -z "$entry" ]] && continue

        if [[ "$first" != "true" ]]; then
            echo ","
        fi
        first=false

        printf '    {"version": "%s", "date": "%s", "type": "%s", "entry": "%s"}' \
            "$(json_escape "$version")" \
            "$(json_escape "$date")" \
            "$(json_escape "$type")" \
            "$(json_escape "$entry")"
    done

    echo ""
    echo "  ],"
    printf '  "acfs_version": "%s",\n' "$(json_escape "$(get_acfs_version)")"
    printf '  "generated_at": "%s"\n' "$(json_escape "$(date -Iseconds)")"
    echo "}"
}

# ============================================================
# Main Function
# ============================================================

show_usage() {
    cat << 'EOF'
ACFS Changelog - Show recent project changes

Usage: acfs changelog [OPTIONS]

Options:
  --all              Show full changelog history
  --since <PERIOD>   Show changes since a duration (7d, 2w, 1m, or whole days)
                     or since an ISO date (YYYY-MM-DD)
  --json             Output in JSON format
  --help, -h         Show this help message

Examples:
  acfs changelog              # Since last update
  acfs changelog --all        # Full history
  acfs changelog --since 7d   # Last 7 days
  acfs changelog --since 2w   # Last 2 weeks
  acfs changelog --since 2026-01-01   # Since a calendar date
  acfs changelog --json       # JSON output

Legend:
  + Added      New features
  ~ Changed    Changed behavior
  * Fixed      Bug fixes
  - Removed    Removed features
  ! Security   Security updates
  > Migration  Migration guides
EOF
}

main() {
    local show_all=false
    local since_period=""
    local json_output=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all|-a)
                show_all=true
                shift
                ;;
            --since|-s)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --since requires a duration (e.g., 7d, 2w, 1m) or a date (YYYY-MM-DD)" >&2
                    exit 1
                fi
                since_period="$2"
                shift 2
                ;;
            --json|-j)
                json_output=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_usage >&2
                exit 1
                ;;
        esac
    done

    # Find changelog file
    local changelog_path
    if ! changelog_path=$(find_changelog); then
        echo "Error: CHANGELOG.md not found" >&2
        echo "Looked in:" >&2
        echo "  - ${_CHANGELOG_FILE}" >&2
        echo "  - ${_CHANGELOG_ACFS_HOME}/CHANGELOG.md" >&2
        exit 1
    fi

    # Determine since date
    local since_date
    if [[ "$show_all" == "true" ]]; then
        since_date="1970-01-01"
    elif [[ -n "$since_period" ]]; then
        if is_iso_date "$since_period"; then
            since_date="$since_period"
        else
            local days
            if ! days=$(parse_duration "$since_period"); then
                echo "Error: invalid duration '$since_period' (expected 7d, 2w, 1m, whole days, or YYYY-MM-DD)" >&2
                exit 1
            fi
            since_date=$(date -d "${days} days ago" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
        fi
    else
        since_date=$(get_last_update_date)
    fi

    # Header for terminal output
    if [[ "$json_output" != "true" ]]; then
        printf "%b\n" "${_CHANGELOG_C_BOLD}ACFS Changelog${_CHANGELOG_C_RESET}"
        if [[ "$show_all" == "true" ]]; then
            printf "%b\n" "${_CHANGELOG_C_DIM}Showing all changes${_CHANGELOG_C_RESET}"
        else
            printf "%b\n" "${_CHANGELOG_C_DIM}Changes since: ${since_date}${_CHANGELOG_C_RESET}"
        fi
        echo ""
    fi

    # Parse and format
    if [[ "$json_output" == "true" ]]; then
        parse_changelog "$changelog_path" | filter_by_date "$since_date" | format_json
    else
        parse_changelog "$changelog_path" | filter_by_date "$since_date" | format_terminal
    fi
}

changelog_restore_shell_state_if_sourced() {
    [[ "$_CHANGELOG_WAS_SOURCED" == "true" ]] || return 0

    if [[ "$_CHANGELOG_ORIGINAL_HOME_WAS_SET" == "true" ]]; then
        HOME="$_CHANGELOG_ORIGINAL_HOME"
        export HOME
    else
        unset HOME
    fi

    [[ "$_CHANGELOG_RESTORE_ERREXIT" == "true" ]] || set +e
    [[ "$_CHANGELOG_RESTORE_NOUNSET" == "true" ]] || set +u
    [[ "$_CHANGELOG_RESTORE_PIPEFAIL" == "true" ]] || set +o pipefail
}

changelog_restore_shell_state_if_sourced

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
