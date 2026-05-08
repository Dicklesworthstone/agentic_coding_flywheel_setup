#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Support Bundle - Collect diagnostic data for troubleshooting
# Usage: acfs support-bundle [--verbose] [--output DIR]
# Output: ~/.acfs/support/<timestamp>/ + .tar.gz archive
# ============================================================
_SUPPORT_WAS_SOURCED=false
_SUPPORT_ORIGINAL_HOME=""
_SUPPORT_ORIGINAL_HOME_WAS_SET=false
_SUPPORT_RESTORE_ERREXIT=false
_SUPPORT_RESTORE_NOUNSET=false
_SUPPORT_RESTORE_PIPEFAIL=false
if [[ -v HOME ]]; then
    _SUPPORT_ORIGINAL_HOME="$HOME"
    _SUPPORT_ORIGINAL_HOME_WAS_SET=true
fi
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    _SUPPORT_WAS_SOURCED=true
    [[ $- == *e* ]] && _SUPPORT_RESTORE_ERREXIT=true
    [[ $- == *u* ]] && _SUPPORT_RESTORE_NOUNSET=true
    if shopt -qo pipefail 2>/dev/null; then
        _SUPPORT_RESTORE_PIPEFAIL=true
    fi
fi

set -euo pipefail

support_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

support_existing_abs_home() {
    local path_value=""

    path_value="$(support_sanitize_abs_nonroot_path "${1:-}" 2>/dev/null || true)"
    [[ -n "$path_value" ]] || return 1
    [[ -d "$path_value" ]] || return 1
    printf '%s\n' "$path_value"
}

support_system_binary_path() {
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

support_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(support_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(support_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

support_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(support_system_binary_path getent 2>/dev/null || true)"
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

support_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    passwd_home="$(support_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
    [[ -n "$passwd_home" ]] || return 1
    printf '%s\n' "$passwd_home"
}
support_is_valid_username() {
    local username="${1:-}"
    [[ "$username" =~ ^[a-z_][a-z0-9._-]*$ ]]
}

support_resolve_current_home() {
    local current_user=""
    local fallback_home=""
    local passwd_entry=""
    local passwd_home=""
    fallback_home="$(support_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
    if [[ "${_SUPPORT_WAS_SOURCED:-false}" == "true" ]]; then
        fallback_home="$(support_sanitize_abs_nonroot_path "${_SUPPORT_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
    fi
    current_user="$(support_resolve_current_user 2>/dev/null || true)"

    if [[ "$current_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    if [[ -n "$current_user" ]]; then
        passwd_entry="$(support_getent_passwd_entry "$current_user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            passwd_home="$(support_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
            if [[ -n "$passwd_home" ]]; then
                printf '%s\n' "$passwd_home"
                return 0
            fi
        fi
    fi

    [[ -n "$fallback_home" ]] || return 1
    printf '%s\n' "$fallback_home"
}
support_initial_current_home() {
    local cached_home=""
    local resolved_home=""

    if [[ "${_SUPPORT_WAS_SOURCED:-false}" == "true" ]] && [[ -z "${TARGET_HOME:-}${TARGET_USER:-}${ACFS_HOME:-}${ACFS_STATE_FILE:-}${ACFS_SYSTEM_STATE_FILE:-}" ]]; then
        cached_home="$(support_sanitize_abs_nonroot_path "${_SUPPORT_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
        if [[ -n "$cached_home" ]]; then
            printf '%s\n' "$cached_home"
            return 0
        fi
    fi

    resolved_home="$(support_resolve_current_home 2>/dev/null || true)"
    if [[ -n "$resolved_home" ]]; then
        printf '%s\n' "$resolved_home"
        return 0
    fi

    if [[ "${_SUPPORT_WAS_SOURCED:-false}" == "true" ]]; then
        cached_home="$(support_sanitize_abs_nonroot_path "${_SUPPORT_ORIGINAL_HOME:-${HOME:-}}" 2>/dev/null || true)"
        if [[ -n "$cached_home" ]]; then
            printf '%s\n' "$cached_home"
            return 0
        fi
    fi

    return 1
}
_SUPPORT_CURRENT_HOME="$(support_initial_current_home 2>/dev/null || true)"
if [[ -n "$_SUPPORT_CURRENT_HOME" ]]; then
    HOME="$_SUPPORT_CURRENT_HOME"
    export HOME
fi

_SUPPORT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SUPPORT_EXPLICIT_ACFS_HOME="$(support_sanitize_abs_nonroot_path "${ACFS_HOME:-}" 2>/dev/null || true)"
_SUPPORT_DEFAULT_ACFS_HOME=""
[[ -n "$_SUPPORT_CURRENT_HOME" ]] && _SUPPORT_DEFAULT_ACFS_HOME="${_SUPPORT_CURRENT_HOME}/.acfs"
_SUPPORT_ACFS_HOME="$_SUPPORT_EXPLICIT_ACFS_HOME"
_SUPPORT_ACFS_HOME_SOURCE=""
_SUPPORT_EXPLICIT_TARGET_HOME_RAW="${TARGET_HOME:-}"
_SUPPORT_EXPLICIT_TARGET_USER_RAW="${TARGET_USER:-}"
_SUPPORT_EXPLICIT_TARGET_HOME="$(support_existing_abs_home "${TARGET_HOME:-}" 2>/dev/null || true)"

# Source logging utilities
if [[ -f "$_SUPPORT_SCRIPT_DIR/logging.sh" ]]; then
    source "$_SUPPORT_SCRIPT_DIR/logging.sh"
fi

# Fallback log functions if logging.sh not available
if ! declare -f log_step >/dev/null 2>&1; then
    log_step()    { echo "[*] $*" >&2; }
    log_section() { echo "" >&2; echo "=== $* ===" >&2; }
    log_detail()  { echo "    $*" >&2; }
    log_success() { echo "[OK] $*" >&2; }
    log_warn()    { echo "[WARN] $*" >&2; }
    log_error()   { echo "[ERR] $*" >&2; }
fi

if [[ -f "$_SUPPORT_SCRIPT_DIR/progress.sh" ]]; then
    # shellcheck source=progress.sh
    source "$_SUPPORT_SCRIPT_DIR/progress.sh" 2>/dev/null || true
fi

# ============================================================
# Configuration
# ============================================================
VERBOSE=false
REDACT=true
OUTPUT_BASE=""
OUTPUT_BASE_EXPLICIT=false
REDACTION_COUNT=0
DOCTOR_TIMEOUT="${SUPPORT_BUNDLE_DOCTOR_TIMEOUT:-120}"
SWARM_STATUS_TIMEOUT="${SUPPORT_BUNDLE_SWARM_STATUS_TIMEOUT:-10}"
SWARM_TIMELINE_TIMEOUT="${SUPPORT_BUNDLE_SWARM_TIMELINE_TIMEOUT:-5}"
PROVENANCE_TIMEOUT="${SUPPORT_BUNDLE_PROVENANCE_TIMEOUT:-10}"
RESOURCE_PROFILE_TIMEOUT="${SUPPORT_BUNDLE_RESOURCE_PROFILE_TIMEOUT:-5}"
SWARM_INVENTORY_TIMEOUT="${SUPPORT_BUNDLE_SWARM_INVENTORY_TIMEOUT:-5}"
SUPPORT_SYSTEM_STATE_WAS_EXPLICIT=false
[[ -n "${ACFS_SYSTEM_STATE_FILE:-}" ]] && [[ "${ACFS_SYSTEM_STATE_FILE%/}" != "/var/lib/acfs/state.json" ]] && SUPPORT_SYSTEM_STATE_WAS_EXPLICIT=true
SUPPORT_SYSTEM_STATE_FILE="$(support_sanitize_abs_nonroot_path "${ACFS_SYSTEM_STATE_FILE:-/var/lib/acfs/state.json}" 2>/dev/null || true)"
if [[ -z "$SUPPORT_SYSTEM_STATE_FILE" ]]; then
    SUPPORT_SYSTEM_STATE_FILE="/var/lib/acfs/state.json"
fi
SUPPORT_TARGET_USER=""
SUPPORT_TARGET_HOME=""

# ============================================================
# Bundle collection functions
# ============================================================

support_print_help() {
    echo "Usage: acfs support-bundle [options]"
    echo ""
    echo "Collect diagnostic data into a tarball for troubleshooting."
    echo "Sensitive data (API keys, tokens, secrets) is redacted by default."
    echo ""
    echo "Options:"
    echo "  --verbose, -v    Show detailed output during collection"
    echo "  --output, -o DIR Output directory (default: ~/.acfs/support)"
    echo "  --no-redact      Disable secret redaction (WARNING: bundle may contain secrets)"
    echo "  --help, -h       Show this help"
    echo ""
    echo "Output:"
    echo "  ~/.acfs/support/<timestamp>/          Unpacked bundle directory"
    echo "  ~/.acfs/support/<timestamp>.tar.gz    Compressed archive"
    echo "  ~/.acfs/support/<timestamp>/manifest.json  Bundle manifest"
}

support_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --output|-o)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_error "--output requires a directory path"
                    return 1
                fi
                OUTPUT_BASE="$2"
                OUTPUT_BASE_EXPLICIT=true
                shift 2
                ;;
            --no-redact)
                REDACT=false
                shift
                ;;
            --help|-h)
                support_print_help
                return 2
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Try 'acfs support-bundle --help' for usage." >&2
                return 1
                ;;
        esac
    done

    return 0
}

support_home_for_user() {
    local user="$1"
    local passwd_entry=""
    local home_candidate=""
    local current_user=""

    [[ -n "$user" ]] || return 1

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    passwd_entry="$(support_getent_passwd_entry "$user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        home_candidate="$(support_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
        if [[ -n "$home_candidate" ]]; then
            printf '%s\n' "$home_candidate"
            return 0
        fi
    fi

    current_user="$(support_resolve_current_user 2>/dev/null || true)"
    if [[ "$user" == "$current_user" ]]; then
        home_candidate="${_SUPPORT_CURRENT_HOME:-}"
        if [[ -z "$home_candidate" ]]; then
            home_candidate="$(support_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
        fi
        if [[ -n "$home_candidate" ]]; then
            printf '%s\n' "$home_candidate"
            return 0
        fi
    fi

    return 1
}

support_resolve_explicit_target_home() {
    local target_home=""
    local resolved_home=""

    if [[ -n "$_SUPPORT_EXPLICIT_TARGET_USER_RAW" ]]; then
        support_is_valid_username "$_SUPPORT_EXPLICIT_TARGET_USER_RAW" || return 1
        resolved_home="$(support_existing_abs_home "$(support_home_for_user "$_SUPPORT_EXPLICIT_TARGET_USER_RAW" 2>/dev/null || true)" 2>/dev/null || true)"
        if [[ -n "$resolved_home" ]]; then
            printf '%s\n' "${resolved_home%/}"
            return 0
        fi
        target_home="$_SUPPORT_EXPLICIT_TARGET_HOME"
        if [[ -n "$target_home" ]] && [[ "$target_home" != "${_SUPPORT_CURRENT_HOME:-}" ]] && support_candidate_has_acfs_data "$target_home/.acfs"; then
            printf '%s\n' "${target_home%/}"
            return 0
        fi
        return 1
    fi

    target_home="$_SUPPORT_EXPLICIT_TARGET_HOME"
    if [[ -n "$target_home" ]]; then
        printf '%s\n' "${target_home%/}"
        return 0
    fi

    return 1
}

support_read_user_for_home() {
    local user_home="$1"
    local candidate_user=""
    local current_home=""
    local passwd_line=""
    local passwd_home=""
    local state_file=""

    user_home="$(support_sanitize_abs_nonroot_path "$user_home" 2>/dev/null || true)"
    [[ -n "$user_home" ]] || return 1

    while IFS= read -r passwd_line; do
        passwd_home="$(support_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
        [[ "$passwd_home" == "$user_home" ]] || continue
        candidate_user="${passwd_line%%:*}"
        if [[ "$candidate_user" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
    done < <(support_getent_passwd_entry 2>/dev/null || true)

    current_home="${_SUPPORT_CURRENT_HOME:-}"
    if [[ -n "$current_home" ]] && [[ "$user_home" == "$current_home" ]]; then
        candidate_user="$(support_resolve_current_user 2>/dev/null || true)"
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
    candidate_user="$(support_read_target_user_from_state "$state_file" 2>/dev/null || true)"
    if [[ -n "$candidate_user" ]]; then
        current_home="$(support_home_for_user "$candidate_user" 2>/dev/null || true)"
        if [[ -n "$current_home" ]] && [[ "$current_home" == "$user_home" ]]; then
            printf '%s\n' "$candidate_user"
            return 0
        fi
    fi

    return 1
}
support_candidate_has_acfs_data() {
    local candidate="$1"
    [[ -n "$candidate" ]] || return 1
    [[ -e "$candidate/state.json" || -e "$candidate/onboard_progress.json" || -d "$candidate/logs" || -d "$candidate/onboard" ]]
}

support_script_acfs_home() {
    local candidate=""
    candidate=$(cd "$_SUPPORT_SCRIPT_DIR/../.." 2>/dev/null && pwd) || return 1
    [[ "$(basename "$candidate")" == ".acfs" ]] || return 1
    printf '%s\n' "$candidate"
}

support_current_home_acfs_candidate() {
    local candidate="$_SUPPORT_DEFAULT_ACFS_HOME"
    local current_home="$_SUPPORT_CURRENT_HOME"
    local current_user=""
    local original_home=""
    local state_home=""
    local state_user=""
    local state_user_home=""

    [[ -n "$candidate" && -n "$current_home" ]] || return 1
    [[ "$current_home" != "/root" ]] || return 1
    support_candidate_has_acfs_data "$candidate" || return 1

    if [[ "${_SUPPORT_ORIGINAL_HOME_WAS_SET:-false}" == true ]]; then
        original_home="$(support_sanitize_abs_nonroot_path "$_SUPPORT_ORIGINAL_HOME" 2>/dev/null || true)"
        [[ -n "$original_home" && "$original_home" == "$current_home" ]] || return 1
    fi

    current_user="$(support_resolve_current_user 2>/dev/null || true)"
    [[ -n "$current_user" && "$current_user" != "root" ]] || return 1

    if [[ -f "$candidate/state.json" ]]; then
        state_home="$(support_read_target_home_from_state "$candidate/state.json" 2>/dev/null || true)"
        [[ -z "$state_home" || "$state_home" == "$current_home" ]] || return 1

        state_user="$(support_read_target_user_from_state "$candidate/state.json" 2>/dev/null || true)"
        if [[ -n "$state_user" && "$state_user" != "$current_user" ]]; then
            state_user_home="$(support_home_for_user "$state_user" 2>/dev/null || true)"
            [[ "$state_user_home" == "$current_home" ]] || return 1
        fi
    fi

    printf '%s\n' "$candidate"
}

support_read_target_user_from_state() {
    local state_file="${1:-$SUPPORT_SYSTEM_STATE_FILE}"
    support_read_state_string "$state_file" "target_user"
}

support_read_state_string() {
    local state_file="$1"
    local key="$2"
    local value=""
    local jq_bin=""
    local sed_bin=""
    local head_bin=""

    [[ -f "$state_file" ]] || return 1

    jq_bin="$(support_system_binary_path jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        value=$("$jq_bin" -r --arg key "$key" '.[$key] // empty' "$state_file" 2>/dev/null || true)
    else
        sed_bin="$(support_system_binary_path sed 2>/dev/null || true)"
        head_bin="$(support_system_binary_path head 2>/dev/null || true)"
        [[ -n "$sed_bin" && -n "$head_bin" ]] || return 1
        value=$("$sed_bin" -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$state_file" 2>/dev/null | "$head_bin" -n 1)
    fi

    [[ -n "$value" ]] && [[ "$value" != "null" ]] || return 1
    printf '%s\n' "$value"
}

support_read_target_home_from_state() {
    local state_file="${1:-$SUPPORT_SYSTEM_STATE_FILE}"
    local target_home=""

    target_home="$(support_read_state_string "$state_file" "target_home" 2>/dev/null || true)"
    [[ -n "$target_home" ]] || return 1
    [[ "$target_home" == /* ]] || return 1
    [[ "$target_home" != "/" ]] || return 1
    printf '%s\n' "${target_home%/}"
}

support_resolve_target_home() {
    local state_file="${1:-}"
    local state_home=""
    local system_home=""
    local explicit_target_home=""

    if [[ -n "$state_file" ]]; then
        state_home=$(support_read_target_home_from_state "$state_file" 2>/dev/null || true)
    fi
    system_home=$(support_read_target_home_from_state "$SUPPORT_SYSTEM_STATE_FILE" 2>/dev/null || true)
    explicit_target_home="$(support_resolve_explicit_target_home 2>/dev/null || true)"

    if [[ -n "$explicit_target_home" ]]; then
        printf '%s\n' "$explicit_target_home"
        return 0
    fi

    if [[ -n "$_SUPPORT_EXPLICIT_TARGET_HOME_RAW" ]] || [[ -n "$_SUPPORT_EXPLICIT_TARGET_USER_RAW" ]]; then
        return 1
    fi

    if [[ -n "$state_home" ]]; then
        if [[ "$state_file" == "$SUPPORT_SYSTEM_STATE_FILE" ]]; then
            printf '%s\n' "$state_home"
            return 0
        fi
        if [[ -n "$_SUPPORT_EXPLICIT_ACFS_HOME" ]] && [[ "$state_file" == "$_SUPPORT_EXPLICIT_ACFS_HOME/state.json" ]]; then
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

support_get_install_state_file() {
    local candidate=""

    if [[ -n "$_SUPPORT_ACFS_HOME" ]]; then
        candidate="${_SUPPORT_ACFS_HOME}/state.json"
    fi

    if [[ -n "$candidate" ]] && [[ -f "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    if [[ -f "$SUPPORT_SYSTEM_STATE_FILE" ]]; then
        printf '%s\n' "$SUPPORT_SYSTEM_STATE_FILE"
        return 0
    fi

    printf '%s\n' "$candidate"
}

support_resolve_acfs_home() {
    local target_home=""
    local candidate=""
    local target_user=""
    local explicit_target_home=""

    _SUPPORT_ACFS_HOME_SOURCE=""

    candidate=$(support_script_acfs_home 2>/dev/null || true)
    if support_candidate_has_acfs_data "$candidate"; then
        _SUPPORT_ACFS_HOME_SOURCE="script_acfs_home"
        printf '%s\n' "$candidate"
        return 0
    fi

    explicit_target_home="$(support_resolve_explicit_target_home 2>/dev/null || true)"
    if [[ -n "$explicit_target_home" ]]; then
        candidate="${explicit_target_home}/.acfs"
        if support_candidate_has_acfs_data "$candidate"; then
            _SUPPORT_ACFS_HOME_SOURCE="explicit_target_home"
            printf '%s\n' "$candidate"
            return 0
        fi
    fi

    if [[ ! -f "$SUPPORT_SYSTEM_STATE_FILE" ]] && [[ -n "$_SUPPORT_ACFS_HOME" ]] && support_candidate_has_acfs_data "$_SUPPORT_ACFS_HOME"; then
        _SUPPORT_ACFS_HOME_SOURCE="explicit_acfs_home"
        printf '%s\n' "$_SUPPORT_ACFS_HOME"
        return 0
    fi

    candidate="$(support_current_home_acfs_candidate 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        _SUPPORT_ACFS_HOME_SOURCE="current_home"
        printf '%s\n' "$candidate"
        return 0
    fi

    if [[ "$SUPPORT_SYSTEM_STATE_WAS_EXPLICIT" == true ]]; then
        target_home=$(support_read_target_home_from_state "$SUPPORT_SYSTEM_STATE_FILE" 2>/dev/null || true)
        if [[ -n "$target_home" ]]; then
            candidate="${target_home}/.acfs"
            if support_candidate_has_acfs_data "$candidate"; then
                _SUPPORT_ACFS_HOME_SOURCE="system_state_target_home"
                printf '%s\n' "$candidate"
                return 0
            fi
        fi

        target_user=$(support_read_target_user_from_state "$SUPPORT_SYSTEM_STATE_FILE" 2>/dev/null || true)
        if [[ -n "$target_user" ]]; then
            target_home=$(support_home_for_user "$target_user" 2>/dev/null || true)
            candidate="${target_home}/.acfs"
            if [[ -n "$target_home" ]] && support_candidate_has_acfs_data "$candidate"; then
                _SUPPORT_ACFS_HOME_SOURCE="system_state_target_user"
                printf '%s\n' "$candidate"
                return 0
            fi
        fi
    fi

    if [[ -n "$_SUPPORT_ACFS_HOME" ]] && support_candidate_has_acfs_data "$_SUPPORT_ACFS_HOME"; then
        _SUPPORT_ACFS_HOME_SOURCE="explicit_acfs_home"
        printf '%s\n' "$_SUPPORT_ACFS_HOME"
        return 0
    fi

    if [[ -n "$_SUPPORT_EXPLICIT_TARGET_HOME_RAW" ]] || [[ -n "$_SUPPORT_EXPLICIT_TARGET_USER_RAW" ]]; then
        return 1
    fi

    if [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
        target_home=$(support_home_for_user "$SUDO_USER" || true)
        candidate="${target_home}/.acfs"
        if [[ -n "$target_home" ]] && support_candidate_has_acfs_data "$candidate"; then
            _SUPPORT_ACFS_HOME_SOURCE="sudo_user_home"
            printf '%s\n' "$candidate"
            return 0
        fi
    fi

    target_home=$(support_read_target_home_from_state || true)
    if [[ -n "$target_home" ]]; then
        candidate="${target_home}/.acfs"
        if support_candidate_has_acfs_data "$candidate"; then
            _SUPPORT_ACFS_HOME_SOURCE="system_state_target_home"
            printf '%s\n' "$candidate"
            return 0
        fi
    fi

    target_user=$(support_read_target_user_from_state || true)
    if [[ -n "$target_user" ]]; then
        target_home=$(support_home_for_user "$target_user" || true)
        candidate="${target_home}/.acfs"
        if [[ -n "$target_home" ]] && support_candidate_has_acfs_data "$candidate"; then
            _SUPPORT_ACFS_HOME_SOURCE="system_state_target_user"
            printf '%s\n' "$candidate"
            return 0
        fi
    fi

    if [[ -n "$_SUPPORT_DEFAULT_ACFS_HOME" ]] && support_candidate_has_acfs_data "$_SUPPORT_DEFAULT_ACFS_HOME"; then
        _SUPPORT_ACFS_HOME_SOURCE="current_home"
        printf '%s\n' "$_SUPPORT_DEFAULT_ACFS_HOME"
        return 0
    fi

    _SUPPORT_ACFS_HOME_SOURCE="current_home"
    printf '%s\n' "${_SUPPORT_CURRENT_HOME:+${_SUPPORT_CURRENT_HOME}/.acfs}"
}

support_infer_target_home_from_acfs_home() {
    local acfs_home_candidate=""
    local inferred_home=""

    acfs_home_candidate="$(support_sanitize_abs_nonroot_path "${_SUPPORT_ACFS_HOME:-}" 2>/dev/null || true)"
    [[ -n "$acfs_home_candidate" ]] || return 1
    [[ "$(basename "$acfs_home_candidate")" == ".acfs" ]] || return 1
    [[ -e "$acfs_home_candidate/state.json" || -e "$acfs_home_candidate/onboard_progress.json" || -d "$acfs_home_candidate/logs" || -d "$acfs_home_candidate/onboard" ]] || return 1

    if [[ -n "$_SUPPORT_EXPLICIT_ACFS_HOME" ]] && [[ "$acfs_home_candidate" == "$_SUPPORT_EXPLICIT_ACFS_HOME" ]]; then
        :
    elif [[ -n "$_SUPPORT_DEFAULT_ACFS_HOME" ]] && [[ "$acfs_home_candidate" == "$_SUPPORT_DEFAULT_ACFS_HOME" ]]; then
        :
    elif [[ "${_SUPPORT_ACFS_HOME_SOURCE:-}" == "explicit_target_home" ]]; then
        :
    elif [[ "${_SUPPORT_ACFS_HOME_SOURCE:-}" == "script_acfs_home" ]]; then
        :
    elif [[ "${_SUPPORT_ACFS_HOME_SOURCE:-}" == "system_state_target_home" ]]; then
        :
    elif [[ "${_SUPPORT_ACFS_HOME_SOURCE:-}" == "system_state_target_user" ]]; then
        :
    else
        return 1
    fi

    inferred_home="${acfs_home_candidate%/.acfs}"
    inferred_home="$(support_sanitize_abs_nonroot_path "$inferred_home" 2>/dev/null || true)"
    [[ -n "$inferred_home" ]] || return 1
    printf '%s\n' "$inferred_home"
}
support_initialize_context() {
    local state_file=""
    local path_home=""
    local detected_user=""
    local state_target_user=""
    local resolved_target_home=""
    local explicit_target_home=""
    local target_home_source=""

    SUPPORT_TARGET_USER=""
    SUPPORT_TARGET_HOME=""
    _SUPPORT_ACFS_HOME=$(support_resolve_acfs_home 2>/dev/null || true)
    state_file=$(support_get_install_state_file)
    path_home="$(support_infer_target_home_from_acfs_home 2>/dev/null || true)"
    explicit_target_home="$(support_resolve_explicit_target_home 2>/dev/null || true)"
    if [[ "${_SUPPORT_ACFS_HOME_SOURCE:-}" == system_state_* ]]; then
        state_target_user="$(support_read_target_user_from_state "$SUPPORT_SYSTEM_STATE_FILE" 2>/dev/null || support_read_target_user_from_state "$state_file" 2>/dev/null || true)"
    elif [[ -n "$path_home" ]]; then
        state_target_user="$(support_read_target_user_from_state "$state_file" 2>/dev/null || true)"
    fi
    if [[ -z "$state_target_user" ]]; then
        state_target_user="$(support_read_target_user_from_state "$SUPPORT_SYSTEM_STATE_FILE" 2>/dev/null || support_read_target_user_from_state "$state_file" 2>/dev/null || true)"
    fi

    if [[ -n "$_SUPPORT_EXPLICIT_TARGET_HOME_RAW" ]] || [[ -n "$_SUPPORT_EXPLICIT_TARGET_USER_RAW" ]]; then
        if [[ -n "$explicit_target_home" ]]; then
            SUPPORT_TARGET_HOME="$explicit_target_home"
            target_home_source="explicit_target_home"
        else
            log_error "Explicit TARGET_HOME/TARGET_USER did not resolve to an installed home; refusing to fall back to current HOME"
            return 1
        fi
    fi

    if [[ -z "$SUPPORT_TARGET_HOME" ]] && [[ -n "$path_home" ]]; then
        SUPPORT_TARGET_HOME="$path_home"
        target_home_source="path_home"
    fi

    if [[ -z "$SUPPORT_TARGET_HOME" ]]; then
        resolved_target_home="$(support_resolve_target_home "$state_file" 2>/dev/null || true)"
        if [[ -n "$resolved_target_home" ]]; then
            SUPPORT_TARGET_HOME="$resolved_target_home"
            target_home_source="state_target_home"
        fi
    fi

    if [[ -z "$SUPPORT_TARGET_HOME" ]] && [[ -n "$state_target_user" ]]; then
        resolved_target_home="$(support_existing_abs_home "$(support_home_for_user "$state_target_user" 2>/dev/null || true)" 2>/dev/null || true)"
        if [[ -n "$resolved_target_home" ]]; then
            SUPPORT_TARGET_HOME="$resolved_target_home"
            target_home_source="state_target_user"
        fi
    fi

    if [[ -z "$SUPPORT_TARGET_HOME" ]] && [[ -n "$path_home" ]]; then
        SUPPORT_TARGET_HOME="$path_home"
        target_home_source="path_home"
    fi

    if [[ -z "$SUPPORT_TARGET_HOME" ]] && [[ "$_SUPPORT_ACFS_HOME" == */.acfs ]]; then
        resolved_target_home="$(support_existing_abs_home "${_SUPPORT_ACFS_HOME%/.acfs}" 2>/dev/null || true)"
        if [[ -n "$resolved_target_home" ]]; then
            SUPPORT_TARGET_HOME="$resolved_target_home"
            target_home_source="acfs_home_path"
        fi
    fi

    if [[ -z "$SUPPORT_TARGET_HOME" ]]; then
        resolved_target_home="$(support_existing_abs_home "${_SUPPORT_CURRENT_HOME:-}" 2>/dev/null || true)"
        if [[ -n "$resolved_target_home" ]]; then
            SUPPORT_TARGET_HOME="$resolved_target_home"
            target_home_source="current_home"
        fi
    fi

    if [[ -z "$SUPPORT_TARGET_USER" ]] && [[ -n "$state_target_user" ]] && support_is_valid_username "$state_target_user"; then
        resolved_target_home="$(support_existing_abs_home "$(support_home_for_user "$state_target_user" 2>/dev/null || true)" 2>/dev/null || true)"
        if [[ -z "$resolved_target_home" ]] || [[ "$resolved_target_home" == "$SUPPORT_TARGET_HOME" ]]; then
            SUPPORT_TARGET_USER="$state_target_user"
        fi
    fi

    if [[ -z "$SUPPORT_TARGET_USER" ]] && [[ -n "$SUPPORT_TARGET_HOME" ]]; then
        detected_user="$(support_read_user_for_home "$SUPPORT_TARGET_HOME" 2>/dev/null || true)"
        if [[ -n "$detected_user" ]]; then
            SUPPORT_TARGET_USER="$detected_user"
        fi
    fi

    if [[ -z "$SUPPORT_TARGET_USER" ]] && [[ "$target_home_source" != "explicit_target_home" ]] && [[ -n "$state_target_user" ]]; then
        SUPPORT_TARGET_USER="$state_target_user"
    fi

    if [[ -z "$SUPPORT_TARGET_USER" ]] && support_is_valid_username "$_SUPPORT_EXPLICIT_TARGET_USER_RAW"; then
        SUPPORT_TARGET_USER="$_SUPPORT_EXPLICIT_TARGET_USER_RAW"
    fi

    if [[ -z "$SUPPORT_TARGET_USER" ]] && [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
        SUPPORT_TARGET_USER="$SUDO_USER"
    fi

    if [[ -z "$SUPPORT_TARGET_USER" ]]; then
        SUPPORT_TARGET_USER="$(support_resolve_current_user 2>/dev/null || echo unknown)"
    fi

    if [[ "$OUTPUT_BASE_EXPLICIT" != "true" ]]; then
        if [[ -n "$_SUPPORT_ACFS_HOME" ]]; then
            OUTPUT_BASE="${_SUPPORT_ACFS_HOME}/support"
        else
            OUTPUT_BASE="${SUPPORT_TARGET_HOME:+${SUPPORT_TARGET_HOME}/.acfs/support}"
        fi
    fi
}

# Record a bundle-relative path in the manifest file list exactly once.
# Usage: record_bundle_file <relative_path>
record_bundle_file() {
    local relative_path="$1"
    local existing_path=""
    for existing_path in "${BUNDLE_FILES[@]:-}"; do
        if [[ "$existing_path" == "$relative_path" ]]; then
            return 0
        fi
    done
    BUNDLE_FILES+=("$relative_path")
}

support_manifest_diagnostic_json() {
    local bundle_dir="$1"
    local relative_path="$2"
    local label="$3"
    local categories_json="$4"
    local jq_bin="$5"
    local file_path="$bundle_dir/$relative_path"

    if [[ ! -f "$file_path" ]]; then
        "$jq_bin" -n \
            --arg source_file "$relative_path" \
            --arg label "$label" \
            --argjson categories "$categories_json" \
            '{
                proof_schema_version: 1,
                included: false,
                status: "skipped",
                source_file: $source_file,
                source_status: "missing",
                source_status_reason: "source file not collected",
                redaction_categories: $categories,
                paths_redacted: true,
                raw_hosts_collected: false,
                raw_paths_collected: false,
                records: {
                    raw_count: 0,
                    sanitized_count: 0,
                    raw_records_collected: false,
                    raw_values_collected: false
                },
                redaction: {
                    categories: $categories,
                    paths_redacted: true,
                    raw_values_collected: false,
                    secrets_collected: false,
                    raw_hosts_collected: false,
                    raw_paths_collected: false,
                    sanitized_records_only: true
                },
                summary: {
                    status: "skipped",
                    paths_redacted: true,
                    raw_paths_collected: false
                },
                source: {valid_json: false, malformed: false}
            }'
        return 0
    fi

    if ! "$jq_bin" . "$file_path" >/dev/null 2>&1; then
        "$jq_bin" -n \
            --arg source_file "$relative_path" \
            --arg label "$label" \
            --argjson categories "$categories_json" \
            '{
                proof_schema_version: 1,
                included: true,
                status: "fail",
                source_file: $source_file,
                source_status: "malformed",
                source_status_reason: "malformed JSON; raw content intentionally not summarized",
                redaction_categories: $categories,
                paths_redacted: true,
                raw_hosts_collected: false,
                raw_paths_collected: false,
                records: {
                    raw_count: 0,
                    sanitized_count: 0,
                    raw_records_collected: false,
                    raw_values_collected: false
                },
                redaction: {
                    categories: $categories,
                    paths_redacted: true,
                    raw_values_collected: false,
                    secrets_collected: false,
                    raw_hosts_collected: false,
                    raw_paths_collected: false,
                    sanitized_records_only: true
                },
                summary: {
                    status: "fail",
                    paths_redacted: true,
                    raw_paths_collected: false
                },
                source: {valid_json: false, malformed: true}
            }'
        return 0
    fi

    "$jq_bin" \
        --arg source_file "$relative_path" \
        --arg label "$label" \
        --argjson categories "$categories_json" \
        '
        def bool_or_false($v): if $v == true then true else false end;
        def status_value:
            (.status // .summary.status // .capture.status // "present")
            | if type == "string" and length > 0 then . else "present" end;
        def record_count:
            if type == "array" then length
            elif (.summary.hosts_total | type) == "number" then .summary.hosts_total
            elif (.managed_file_count | type) == "number" then .managed_file_count
            elif (.probes | type) == "array" then (.probes | length)
            elif (.probes | type) == "object" then (.probes | keys | length)
            elif (.checks | type) == "array" then (.checks | length)
            elif (.timeline | type) == "object" then (.timeline | keys | length)
            elif (.versions | type) == "object" then (.versions | keys | length)
            elif (.summary.total | type) == "number" then .summary.total
            elif type == "object" then ([paths(scalars)] | length)
            else 0
            end;
        def paths_redacted_value:
            if (.redaction.paths_redacted | type) == "boolean" then .redaction.paths_redacted
            elif $label == "versions" then false
            else true
            end;
        def raw_hosts_collected_value:
            bool_or_false(.redaction.raw_hosts_collected // .inventory.raw_hosts_collected // false);
        def raw_paths_collected_value:
            bool_or_false(.redaction.raw_paths_collected // false);
        def source_included($status):
            if $label == "swarm_inventory" and (.inventory.present == false) then false
            elif $status == "skipped" then false
            else true
            end;
        status_value as $source_status
        | record_count as $count
        | paths_redacted_value as $paths_redacted
        | raw_hosts_collected_value as $raw_hosts_collected
        | raw_paths_collected_value as $raw_paths_collected
        | {
            proof_schema_version: 1,
            included: source_included($source_status),
            status: $source_status,
            source_file: $source_file,
            source_status: $source_status,
            source_status_reason: (.capture.reason // .reason // null),
            redaction_categories: $categories,
            paths_redacted: $paths_redacted,
            raw_hosts_collected: $raw_hosts_collected,
            raw_paths_collected: $raw_paths_collected,
            records: {
                raw_count: $count,
                sanitized_count: $count,
                raw_records_collected: ($raw_hosts_collected or $raw_paths_collected),
                raw_values_collected: false
            },
            redaction: {
                categories: $categories,
                paths_redacted: $paths_redacted,
                raw_values_collected: false,
                secrets_collected: bool_or_false(.redaction.secrets_collected // false),
                raw_hosts_collected: $raw_hosts_collected,
                raw_paths_collected: $raw_paths_collected,
                sanitized_records_only: true
            },
            summary: {
                status: $source_status,
                mode: (.mode // null),
                paths_redacted: $paths_redacted,
                raw_paths_collected: $raw_paths_collected,
                managed_file_count: (.managed_file_count // null)
            },
            probes: (if (.probes | type) == "array" then [.probes[] | {id: (.id // null), status: (.status // "unknown"), reason: (.reason // null)}] else [] end),
            source: {valid_json: true, malformed: false}
        }
        ' "$file_path" 2>/dev/null || {
        "$jq_bin" -n \
            --arg source_file "$relative_path" \
            --arg label "$label" \
            --argjson categories "$categories_json" \
            '{
                proof_schema_version: 1,
                included: true,
                status: "warn",
                source_file: $source_file,
                source_status: "summary_failed",
                source_status_reason: "diagnostic proof rendering failed",
                redaction_categories: $categories,
                paths_redacted: true,
                raw_hosts_collected: false,
                raw_paths_collected: false,
                records: {
                    raw_count: 0,
                    sanitized_count: 0,
                    raw_records_collected: false,
                    raw_values_collected: false
                },
                redaction: {
                    categories: $categories,
                    paths_redacted: true,
                    raw_values_collected: false,
                    secrets_collected: false,
                    raw_hosts_collected: false,
                    raw_paths_collected: false,
                    sanitized_records_only: true
                },
                summary: {
                    status: "warn",
                    paths_redacted: true,
                    raw_paths_collected: false
                },
                source: {valid_json: false, malformed: false}
            }'
    }
}

# Generate a bundle name that stays unique even when multiple runs land
# in the same second or a prior bundle path already exists.
# Usage: next_bundle_name
next_bundle_name() {
    local timestamp base_name
    timestamp=$(date +%Y%m%d_%H%M%S)
    base_name="${timestamp}_$$"

    while [[ -e "${OUTPUT_BASE}/${base_name}" || -e "${OUTPUT_BASE}/${base_name}.tar.gz" ]]; do
        base_name="${timestamp}_$$_${RANDOM}"
    done

    printf '%s\n' "$base_name"
}

# Safely copy a file into the bundle, logging the result.
# Usage: collect_file <source_path> <bundle_dir> <bundle_relative_path> [display_name]
collect_file() {
    local src="$1"
    local bundle_dir="$2"
    local relative_path="$3"
    local display="${4:-$relative_path}"
    local dest_path="${bundle_dir}/${relative_path}"

    if [[ -L "$src" ]]; then
        [[ "$VERBOSE" == "true" ]] && log_detail "Skipping symlink: $display"
        return 1
    fi

    if [[ -f "$src" ]]; then
        mkdir -p -- "$(dirname "$dest_path")"
        cp -- "$src" "$dest_path" 2>/dev/null || {
            log_warn "Could not copy: $display"
            return 1
        }
        [[ "$VERBOSE" == "true" ]] && log_detail "Collected: $display"
        record_bundle_file "$relative_path"
        return 0
    else
        [[ "$VERBOSE" == "true" ]] && log_detail "Not found: $display"
        return 1
    fi
}

support_json_file_status() {
    local file_path="$1"
    local jq_bin="$2"

    [[ -f "$file_path" ]] || {
        printf 'missing\n'
        return 0
    }
    [[ -s "$file_path" ]] || {
        printf 'empty\n'
        return 0
    }
    "$jq_bin" . "$file_path" >/dev/null 2>&1 || {
        printf 'malformed\n'
        return 0
    }
    printf 'present\n'
}

support_local_progress_milestones_summary_json() {
    local jq_bin="$1"
    local progress_file="$2"
    local opt_out="$3"
    local file_status=""

    if [[ "$opt_out" == "true" ]]; then
        "$jq_bin" -n '{
            status: "skipped",
            source_status: "opt_out",
            reason: "local milestone recording is disabled by environment",
            event_count: 0,
            latest_event: null,
            sources: {},
            statuses: {}
        }'
        return 0
    fi

    file_status="$(support_json_file_status "$progress_file" "$jq_bin")"
    case "$file_status" in
        missing|empty)
            "$jq_bin" -n --arg source_status "$file_status" '{
                status: "empty",
                source_status: $source_status,
                event_count: 0,
                latest_event: null,
                sources: {},
                statuses: {}
            }'
            return 0
            ;;
        malformed)
            "$jq_bin" -n '{
                status: "warn",
                source_status: "malformed",
                reason: "local progress JSON is malformed; raw content intentionally not summarized",
                event_count: 0,
                latest_event: null,
                sources: {},
                statuses: {}
            }'
            return 0
            ;;
    esac

    "$jq_bin" '
      def safe_token:
        if type == "string" and test("^[A-Za-z0-9_.:-]{1,80}$") then . else "unknown" end;
      def safe_time:
        if type == "string" and test("^[0-9T:Z+_. -]{1,40}$") then . else null end;
      def detail_string($k):
        (.details[$k] // null) | if type == "string" and test("^[A-Za-z0-9_.:-]{1,80}$") then . else null end;
      def detail_number($k):
        (.details[$k] // null) | if type == "number" and . >= 0 then . else null end;
      def detail_bool($k):
        (.details[$k] // null) | if type == "boolean" then . else null end;
      def safe_details:
        {
          phase_id: detail_string("phase_id"),
          lesson_index: detail_number("lesson_index"),
          lesson_number: detail_number("lesson_number"),
          completed_count: detail_number("completed_count"),
          total_lessons: detail_number("total_lessons"),
          deep_mode: detail_bool("deep_mode"),
          fix_mode: detail_bool("fix_mode"),
          dry_run_mode: detail_bool("dry_run_mode"),
          json_mode: detail_bool("json_mode")
        } | with_entries(select(.value != null));
      def safe_event:
        {
          timestamp: (.timestamp | safe_time),
          source: (.source | safe_token),
          kind: (.kind | safe_token),
          status: (.status | safe_token),
          details: safe_details
        };
      ((.events // []) | map(select(type == "object"))) as $events
      | ($events | map(.source | safe_token) | sort | group_by(.) | map({key: .[0], value: length}) | from_entries) as $sources
      | ($events | map(.status | safe_token) | sort | group_by(.) | map({key: .[0], value: length}) | from_entries) as $statuses
      | {
          status: (if ($events | length) > 0 then "pass" else "empty" end),
          source_status: "present",
          event_count: ($events | length),
          first_event_at: (if ($events | length) > 0 then ($events[0].timestamp | safe_time) else null end),
          latest_event_at: (if ($events | length) > 0 then ($events[-1].timestamp | safe_time) else null end),
          latest_event: (if ($events | length) > 0 then ($events[-1] | safe_event) else null end),
          sources: $sources,
          statuses: $statuses
        }
    ' "$progress_file" 2>/dev/null || "$jq_bin" -n '{
        status: "warn",
        source_status: "summary_failed",
        event_count: 0,
        latest_event: null,
        sources: {},
        statuses: {}
    }'
}

support_onboard_progress_summary_json() {
    local jq_bin="$1"
    local progress_file="$2"
    local file_status=""

    file_status="$(support_json_file_status "$progress_file" "$jq_bin")"
    case "$file_status" in
        missing|empty)
            "$jq_bin" -n --arg source_status "$file_status" '{
                status: "empty",
                source_status: $source_status,
                completed_count: 0,
                current_lesson_index: null,
                started_at: null,
                last_accessed: null
            }'
            return 0
            ;;
        malformed)
            "$jq_bin" -n '{
                status: "warn",
                source_status: "malformed",
                reason: "onboard progress JSON is malformed; raw content intentionally not summarized",
                completed_count: 0,
                current_lesson_index: null,
                started_at: null,
                last_accessed: null
            }'
            return 0
            ;;
    esac

    "$jq_bin" '
      def safe_time:
        if type == "string" and test("^[0-9T:Z+_. -]{1,40}$") then . else null end;
      def safe_index:
        if type == "number" and . >= 0 and . == floor then . else null end;
      {
        status: "pass",
        source_status: "present",
        completed_count: ((.completed // []) | map(select(type == "number" and . >= 0 and . == floor)) | unique | length),
        current_lesson_index: (.current | safe_index),
        started_at: (.started_at | safe_time),
        last_accessed: (.last_accessed | safe_time)
      }
    ' "$progress_file" 2>/dev/null || "$jq_bin" -n '{
        status: "warn",
        source_status: "summary_failed",
        completed_count: 0,
        current_lesson_index: null,
        started_at: null,
        last_accessed: null
    }'
}

support_installer_progress_summary_json() {
    local jq_bin="$1"
    local state_file="$2"
    local file_status=""

    file_status="$(support_json_file_status "$state_file" "$jq_bin")"
    case "$file_status" in
        missing|empty)
            "$jq_bin" -n --arg source_status "$file_status" '{
                status: "empty",
                source_status: $source_status,
                completed_phase_count: 0,
                skipped_phase_count: 0,
                current_phase: null,
                failed_phase: null,
                failed_step_present: false,
                failed_error_present: false
            }'
            return 0
            ;;
        malformed)
            "$jq_bin" -n '{
                status: "warn",
                source_status: "malformed",
                reason: "installer state JSON is malformed; raw content intentionally not summarized",
                completed_phase_count: 0,
                skipped_phase_count: 0,
                current_phase: null,
                failed_phase: null,
                failed_step_present: false,
                failed_error_present: false
            }'
            return 0
            ;;
    esac

    "$jq_bin" '
      def safe_token:
        if type == "string" and test("^[A-Za-z0-9_.:-]{1,80}$") then . else null end;
      {
        status: "pass",
        source_status: "present",
        completed_phase_count: ((.completed_phases // []) | map(select(type == "string")) | length),
        skipped_phase_count: ((.skipped_phases // []) | map(select(type == "string")) | length),
        current_phase: (.current_phase | safe_token),
        failed_phase: (.failed_phase | safe_token),
        failed_step_present: ((.failed_step // null) != null),
        failed_error_present: ((.failed_error // null) != null)
      }
    ' "$state_file" 2>/dev/null || "$jq_bin" -n '{
        status: "warn",
        source_status: "summary_failed",
        completed_phase_count: 0,
        skipped_phase_count: 0,
        current_phase: null,
        failed_phase: null,
        failed_step_present: false,
        failed_error_present: false
    }'
}

support_checkpoint_summary_json() {
    local jq_bin="$1"
    local state_file="$2"
    local file_status=""
    local now_epoch="${ACFS_SUPPORT_NOW_EPOCH:-}"
    local now_epoch_json="null"
    local stale_seconds="${ACFS_CHECKPOINT_STALE_SECONDS:-3600}"
    local supported_schema_version=3

    [[ "$now_epoch" =~ ^[0-9]+$ ]] && now_epoch_json="$now_epoch"
    [[ "$stale_seconds" =~ ^[0-9]+$ ]] || stale_seconds=3600

    file_status="$(support_json_file_status "$state_file" "$jq_bin")"
    case "$file_status" in
        missing|empty)
            "$jq_bin" -n --arg source_status "$file_status" '{
                schema_version: 1,
                status: "empty",
                severity: "needs_state",
                install_status: "unknown",
                next_action: "acfs status --json",
                state: {
                    source_file: "state.json",
                    source_status: $source_status,
                    schema_version: null,
                    supported_schema_version: 3,
                    acfs_version: null,
                    mode: null
                },
                checkpoint: {
                    completed_phase_count: 0,
                    skipped_phase_count: 0,
                    last_completed_phase: null,
                    next_phase: null,
                    current_phase: null,
                    current_step_present: false,
                    failed_phase: null,
                    failed_step_present: false,
                    failed_error_present: false,
                    resume_hint_available: false,
                    updated_epoch: null,
                    age_seconds: null
                },
                redaction: {
                    raw_values_collected: false,
                    raw_paths_collected: false,
                    paths_redacted: true,
                    secrets_collected: false,
                    raw_errors_collected: false,
                    resume_command_collected: false,
                    sanitized_records_only: true
                }
            }'
            return 0
            ;;
        malformed)
            "$jq_bin" -n '{
                schema_version: 1,
                status: "warn",
                severity: "malformed_state",
                install_status: "unknown",
                next_action: "acfs support-bundle",
                reason: "installer state JSON is malformed; raw content intentionally not summarized",
                state: {
                    source_file: "state.json",
                    source_status: "malformed",
                    schema_version: null,
                    supported_schema_version: 3,
                    acfs_version: null,
                    mode: null
                },
                checkpoint: {
                    completed_phase_count: 0,
                    skipped_phase_count: 0,
                    last_completed_phase: null,
                    next_phase: null,
                    current_phase: null,
                    current_step_present: false,
                    failed_phase: null,
                    failed_step_present: false,
                    failed_error_present: false,
                    resume_hint_available: false,
                    updated_epoch: null,
                    age_seconds: null
                },
                redaction: {
                    raw_values_collected: false,
                    raw_paths_collected: false,
                    paths_redacted: true,
                    secrets_collected: false,
                    raw_errors_collected: false,
                    resume_command_collected: false,
                    sanitized_records_only: true
                }
            }'
            return 0
            ;;
    esac

    "$jq_bin" \
        --argjson supported_schema "$supported_schema_version" \
        --argjson now_epoch "$now_epoch_json" \
        --argjson stale_seconds "$stale_seconds" \
        '
          def safe_token:
            if type == "string" and test("^[A-Za-z0-9_.:-]{1,80}$") then . else null end;
          def safe_mode:
            if type == "string" and test("^[A-Za-z0-9_.:-]{1,40}$") then . else null end;
          def safe_version:
            if type == "string" and test("^[A-Za-z0-9_.:+-]{1,80}$") then . else null end;
          def numeric_epoch:
            if type == "number" and . >= 0 then floor
            elif type == "string" and test("^[0-9]+$") then tonumber
            else null end;
          def phase_after($phase):
            if $phase == null then "user_setup"
            elif $phase == "user_setup" then "filesystem"
            elif $phase == "filesystem" then "shell_setup"
            elif $phase == "shell_setup" then "cli_tools"
            elif $phase == "cli_tools" then "languages"
            elif $phase == "languages" then "agents"
            elif $phase == "agents" then "cloud_db"
            elif $phase == "cloud_db" then "stack"
            elif $phase == "stack" then "finalize"
            else null end;
          . as $state
          | (($state.completed_phases // []) | map(select(type == "string") | safe_token) | map(select(. != null))) as $completed
          | (($state.skipped_phases // []) | map(select(type == "string") | safe_token) | map(select(. != null))) as $skipped
          | ($state.schema_version // null) as $state_schema
          | ($completed[-1] // null) as $last_completed
          | (if ($state.current_phase | type) == "object" then ($state.current_phase.id // null) else $state.current_phase end | safe_token) as $current_phase
          | ($state.failed_phase | safe_token) as $failed_phase
          | ($state.last_updated // $state.updated_at // $state.last_update // null | numeric_epoch) as $updated_epoch
          | (if $now_epoch != null and $updated_epoch != null then ($now_epoch - $updated_epoch) else null end) as $age_seconds
          | (if ($state_schema | type) == "number" and $state_schema > $supported_schema then true else false end) as $future_schema
          | ($current_phase != null and $age_seconds != null and $age_seconds > $stale_seconds) as $stale
          | {
              schema_version: 1,
              status: (
                if $future_schema then "warn"
                elif $failed_phase != null then "fail"
                elif ($completed | index("finalize")) then "pass"
                elif $stale then "warn"
                elif $current_phase != null then "warn"
                elif ($completed | length) > 0 then "warn"
                else "empty" end
              ),
              severity: (
                if $future_schema then "future_state"
                elif $failed_phase != null then "blocked"
                elif ($completed | index("finalize")) then "healthy"
                elif $stale then "stale_checkpoint"
                elif $current_phase != null then "install_running"
                elif ($completed | length) > 0 then "interrupted"
                else "needs_state" end
              ),
              install_status: (
                if $failed_phase != null then "failed"
                elif ($completed | index("finalize")) then "healthy"
                elif $current_phase != null then "running"
                elif ($completed | length) > 0 then "partial"
                else "unknown" end
              ),
              next_action: (
                if $future_schema then "acfs support-bundle"
                elif $failed_phase != null then "acfs rescue --json"
                elif ($completed | index("finalize")) then "onboard"
                elif $stale then "acfs continue --status"
                elif $current_phase != null then "acfs continue"
                elif ($completed | length) > 0 then "acfs rescue --json"
                else "acfs status --json" end
              ),
              state: {
                source_file: "state.json",
                source_status: (if $future_schema then "future_version" else "present" end),
                schema_version: $state_schema,
                supported_schema_version: $supported_schema,
                acfs_version: ($state.version | safe_version),
                mode: ($state.mode | safe_mode)
              },
              checkpoint: {
                completed_phase_count: ($completed | length),
                skipped_phase_count: ($skipped | length),
                last_completed_phase: $last_completed,
                next_phase: (phase_after($last_completed)),
                current_phase: $current_phase,
                current_step_present: (($state.current_step // null) != null),
                failed_phase: $failed_phase,
                failed_step_present: (($state.failed_step // null) != null),
                failed_error_present: (($state.failed_error // null) != null),
                resume_hint_available: (($state.resume_hint // null) != null),
                updated_epoch: $updated_epoch,
                age_seconds: $age_seconds
              },
              redaction: {
                raw_values_collected: false,
                raw_paths_collected: false,
                paths_redacted: true,
                secrets_collected: false,
                raw_errors_collected: false,
                resume_command_collected: false,
                sanitized_records_only: true
              }
            }
        ' "$state_file" 2>/dev/null || "$jq_bin" -n '{
            schema_version: 1,
            status: "warn",
            severity: "summary_failed",
            install_status: "unknown",
            next_action: "acfs support-bundle",
            redaction: {
                raw_values_collected: false,
                raw_paths_collected: false,
                paths_redacted: true,
                secrets_collected: false,
                raw_errors_collected: false,
                resume_command_collected: false,
                sanitized_records_only: true
            }
        }'
}

# Capture a redacted checkpoint summary without copying raw state values.
# Usage: capture_checkpoint_summary_json <bundle_dir>
capture_checkpoint_summary_json() {
    local bundle_dir="$1"
    local jq_bin=""
    local output_file="$bundle_dir/checkpoint_summary.json"
    local state_file=""

    jq_bin="$(support_system_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        cat > "$output_file" <<'JSON'
{"schema_version":1,"status":"warn","severity":"blocked","reason":"jq is required to render checkpoint diagnostics","redaction":{"raw_values_collected":false,"raw_paths_collected":false,"paths_redacted":true}}
JSON
        record_bundle_file "checkpoint_summary.json"
        return 0
    fi

    state_file="${_SUPPORT_ACFS_HOME:+$_SUPPORT_ACFS_HOME/state.json}"
    support_checkpoint_summary_json "$jq_bin" "$state_file" > "$output_file" 2>/dev/null || {
        cat > "$output_file" <<'JSON'
{"schema_version":1,"status":"warn","severity":"summary_failed","reason":"checkpoint summary rendering failed","redaction":{"raw_values_collected":false,"raw_paths_collected":false,"paths_redacted":true}}
JSON
    }

    record_bundle_file "checkpoint_summary.json"
    return 0
}

# Capture a redacted local progress summary without copying raw milestone files.
# Usage: capture_local_progress_json <bundle_dir>
capture_local_progress_json() {
    local bundle_dir="$1"
    local jq_bin=""
    local output_file="$bundle_dir/local_progress.json"
    local progress_file=""
    local onboard_file=""
    local state_file=""
    local opt_out=false
    local milestones_json=""
    local onboard_json=""
    local installer_json=""

    jq_bin="$(support_system_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        cat > "$output_file" <<'JSON'
{"schema_version":1,"status":"warn","reason":"jq is required to render local progress diagnostics","redaction":{"raw_values_collected":false,"raw_paths_collected":false,"paths_redacted":true}}
JSON
        record_bundle_file "local_progress.json"
        return 0
    fi

    if type -t local_progress_is_disabled >/dev/null 2>&1 && local_progress_is_disabled; then
        opt_out=true
    fi

    progress_file="${ACFS_LOCAL_PROGRESS_FILE:-${_SUPPORT_ACFS_HOME:+$_SUPPORT_ACFS_HOME/local_progress.json}}"
    onboard_file="${_SUPPORT_ACFS_HOME:+$_SUPPORT_ACFS_HOME/onboard_progress.json}"
    state_file="${_SUPPORT_ACFS_HOME:+$_SUPPORT_ACFS_HOME/state.json}"

    milestones_json="$(support_local_progress_milestones_summary_json "$jq_bin" "$progress_file" "$opt_out")"
    onboard_json="$(support_onboard_progress_summary_json "$jq_bin" "$onboard_file")"
    installer_json="$(support_installer_progress_summary_json "$jq_bin" "$state_file")"

    "$jq_bin" -n \
        --argjson milestones "$milestones_json" \
        --argjson onboard "$onboard_json" \
        --argjson installer "$installer_json" \
        'def degraded($x): ($x.status == "warn");
         def emptyish($x): ($x.status == "empty");
         def skipped($x): ($x.status == "skipped");
         {
           schema_version: 1,
           status: (
             if degraded($milestones) or degraded($onboard) or degraded($installer) then "warn"
             elif skipped($milestones) then "skipped"
             elif emptyish($milestones) and emptyish($onboard) and emptyish($installer) then "empty"
             else "pass" end
           ),
           summary: {
             milestone_event_count: ($milestones.event_count // 0),
             onboard_completed_count: ($onboard.completed_count // 0),
             installer_completed_phase_count: ($installer.completed_phase_count // 0),
             latest_event_at: ($milestones.latest_event_at // null)
           },
           stuck_hint: (
             if ($installer.failed_phase // null) != null then
               {source: "installer", status: "failed", phase_id: $installer.failed_phase, next_action: "acfs rescue --json or acfs support-bundle"}
             elif ($milestones.latest_event // null) != null then
               {
                 source: $milestones.latest_event.source,
                 status: $milestones.latest_event.status,
                 kind: $milestones.latest_event.kind,
                 details: $milestones.latest_event.details,
                 next_action: "continue from the latest local milestone"
               }
             elif ($installer.current_phase // null) != null then
               {source: "installer", status: "in_progress", phase_id: $installer.current_phase, next_action: "acfs status --json"}
             elif ($onboard.current_lesson_index // null) != null then
               {source: "onboard", status: "in_progress", lesson_index: $onboard.current_lesson_index, next_action: "onboard status"}
             else
               {source: null, status: "empty", next_action: "acfs doctor --json"}
             end
           ),
           redaction: {
             raw_values_collected: false,
             raw_paths_collected: false,
             paths_redacted: true,
             secrets_collected: false,
             local_paths_collected: false,
             command_history_collected: false,
             keystrokes_collected: false,
             network_submission: false,
             sanitized_records_only: true
           },
           milestones: $milestones,
           onboard_progress: $onboard,
           installer_state: $installer
         }' > "$output_file" 2>/dev/null || {
        cat > "$output_file" <<'JSON'
{"schema_version":1,"status":"warn","reason":"local progress summary rendering failed","redaction":{"raw_values_collected":false,"raw_paths_collected":false,"paths_redacted":true}}
JSON
    }

    record_bundle_file "local_progress.json"
    return 0
}

# Capture doctor JSON output.
# Usage: capture_doctor_json <bundle_dir>
capture_doctor_json() {
    local bundle_dir="$1"

    local doctor_script=""
    if [[ -n "$_SUPPORT_ACFS_HOME" ]] && [[ -f "$_SUPPORT_ACFS_HOME/scripts/lib/doctor.sh" ]]; then
        doctor_script="$_SUPPORT_ACFS_HOME/scripts/lib/doctor.sh"
    elif [[ -f "$_SUPPORT_SCRIPT_DIR/doctor.sh" ]]; then
        doctor_script="$_SUPPORT_SCRIPT_DIR/doctor.sh"
    fi

    if [[ -n "$doctor_script" ]]; then
        log_detail "Running acfs doctor --json ..."
        if timeout "$DOCTOR_TIMEOUT" bash "$doctor_script" doctor --json > "$bundle_dir/doctor.json" 2>/dev/null; then
            record_bundle_file "doctor.json"
            return 0
        else
            log_warn "Doctor check timed out or failed"
            # Write partial output marker
            echo '{"error": "doctor check failed or timed out"}' > "$bundle_dir/doctor.json"
            record_bundle_file "doctor.json"
            return 1
        fi
    else
        log_warn "doctor.sh not found, skipping doctor output"
        return 1
    fi
}

# Capture local swarm status JSON output.
# Usage: capture_swarm_status_json <bundle_dir>
capture_swarm_status_json() {
    local bundle_dir="$1"

    local swarm_status_script=""
    if [[ -n "$_SUPPORT_ACFS_HOME" ]] && [[ -f "$_SUPPORT_ACFS_HOME/scripts/lib/swarm_status.sh" ]]; then
        swarm_status_script="$_SUPPORT_ACFS_HOME/scripts/lib/swarm_status.sh"
    elif [[ -f "$_SUPPORT_SCRIPT_DIR/swarm_status.sh" ]]; then
        swarm_status_script="$_SUPPORT_SCRIPT_DIR/swarm_status.sh"
    fi

    if [[ -z "$swarm_status_script" ]]; then
        log_warn "swarm_status.sh not found, skipping swarm status"
        return 1
    fi

    log_detail "Running acfs swarm status --json ..."
    local timeout_bin=""
    timeout_bin="$(support_system_binary_path timeout 2>/dev/null || command -v timeout 2>/dev/null || true)"
    if [[ -n "$timeout_bin" ]]; then
        if "$timeout_bin" "$SWARM_STATUS_TIMEOUT" bash "$swarm_status_script" --json > "$bundle_dir/swarm_status.json" 2>/dev/null; then
            record_bundle_file "swarm_status.json"
            return 0
        fi
    elif bash "$swarm_status_script" --json > "$bundle_dir/swarm_status.json" 2>/dev/null; then
        record_bundle_file "swarm_status.json"
        return 0
    fi

    log_warn "Swarm status check timed out or failed"
    echo '{"error": "swarm status check failed or timed out"}' > "$bundle_dir/swarm_status.json"
    record_bundle_file "swarm_status.json"
    return 1
}

# Capture installed-tool provenance ledger JSON.
# Usage: capture_provenance_json <bundle_dir>
capture_provenance_json() {
    local bundle_dir="$1"

    local provenance_script=""
    if [[ -n "$_SUPPORT_ACFS_HOME" ]] && [[ -f "$_SUPPORT_ACFS_HOME/scripts/lib/provenance.sh" ]]; then
        provenance_script="$_SUPPORT_ACFS_HOME/scripts/lib/provenance.sh"
    elif [[ -f "$_SUPPORT_SCRIPT_DIR/provenance.sh" ]]; then
        provenance_script="$_SUPPORT_SCRIPT_DIR/provenance.sh"
    fi

    if [[ -z "$provenance_script" ]]; then
        log_warn "provenance.sh not found, skipping tool provenance"
        return 1
    fi

    log_detail "Running acfs provenance --json ..."
    local timeout_bin=""
    timeout_bin="$(support_system_binary_path timeout 2>/dev/null || command -v timeout 2>/dev/null || true)"
    if [[ -n "$timeout_bin" ]]; then
        if "$timeout_bin" "$PROVENANCE_TIMEOUT" bash "$provenance_script" --json > "$bundle_dir/provenance.json" 2>/dev/null; then
            record_bundle_file "provenance.json"
            return 0
        fi
    elif bash "$provenance_script" --json > "$bundle_dir/provenance.json" 2>/dev/null; then
        record_bundle_file "provenance.json"
        return 0
    fi

    log_warn "Tool provenance capture timed out or failed"
    echo '{"error": "tool provenance capture failed or timed out"}' > "$bundle_dir/provenance.json"
    record_bundle_file "provenance.json"
    return 1
}

support_run_with_timeout() {
    local timeout_secs="$1"
    shift

    local timeout_bin=""
    timeout_bin="$(support_system_binary_path timeout 2>/dev/null || command -v timeout 2>/dev/null || true)"
    if [[ -n "$timeout_bin" ]]; then
        "$timeout_bin" "$timeout_secs" "$@" 2>/dev/null
    else
        "$@" 2>/dev/null
    fi
}

support_swarm_inventory_file() {
    local explicit_inventory=""

    explicit_inventory="$(support_sanitize_abs_nonroot_path "${ACFS_SWARM_INVENTORY_FILE:-}" 2>/dev/null || true)"
    if [[ -n "$explicit_inventory" ]]; then
        printf '%s\n' "$explicit_inventory"
        return 0
    fi

    if [[ -n "$_SUPPORT_ACFS_HOME" ]]; then
        printf '%s\n' "$_SUPPORT_ACFS_HOME/swarm/hosts.inventory.json"
        return 0
    fi

    if [[ -n "${SUPPORT_TARGET_HOME:-}" ]]; then
        printf '%s\n' "$SUPPORT_TARGET_HOME/.acfs/swarm/hosts.inventory.json"
        return 0
    fi

    return 1
}

# Capture a sanitized multi-host inventory summary. Raw host records, paths,
# hostnames, IPs, SSH details, provider identifiers, repo paths, and notes are
# intentionally excluded from support bundles.
# Usage: capture_swarm_inventory_json <bundle_dir>
capture_swarm_inventory_json() {
    local bundle_dir="$1"
    local inventory_file="$bundle_dir/swarm_inventory.json"
    local jq_bin=""
    local generated_at=""
    local source_inventory=""
    local swarm_inventory_script=""
    local report_output=""

    jq_bin="$(support_system_binary_path jq 2>/dev/null || true)"
    generated_at="$(date -Iseconds 2>/dev/null || date)"

    if [[ -z "$jq_bin" ]]; then
        printf '{"schema_version":1,"status":"skipped","capture":{"status":"skipped","reason":"jq not found"},"inventory":{"present":false,"raw_hosts_collected":false},"redaction":{"paths_redacted":true,"raw_hosts_collected":false,"secrets_collected":false}}\n' > "$inventory_file"
        record_bundle_file "swarm_inventory.json"
        return 1
    fi

    source_inventory="$(support_swarm_inventory_file 2>/dev/null || true)"
    if [[ -z "$source_inventory" || ! -f "$source_inventory" ]]; then
        "$jq_bin" -n \
            --arg generated_at "$generated_at" \
            '{
                schema_version: 1,
                generated_at: $generated_at,
                status: "skipped",
                capture: {status: "skipped", reason: "swarm inventory file not found"},
                inventory: {present: false, source: "canonical", path_collected: false, raw_hosts_collected: false},
                summary: {
                    hosts_total: 0,
                    active: 0,
                    stale: 0,
                    disabled: 0,
                    stale_probe_count: 0,
                    recommended_agents_total: 0,
                    safe_agents_total: 0,
                    rch_workers: 0,
                    unknown_field_count: 0
                },
                role_counts: {},
                status_counts: {},
                redaction: {
                    paths_redacted: true,
                    raw_hosts_collected: false,
                    raw_hostnames_collected: false,
                    raw_ip_addresses_collected: false,
                    ssh_users_collected: false,
                    ssh_key_paths_collected: false,
                    provider_ids_collected: false,
                    repo_paths_collected: false,
                    home_paths_collected: false,
                    token_like_notes_collected: false,
                    secrets_collected: false
                },
                diagnostics: {error_code: null, redacted_field_paths: []}
            }' > "$inventory_file" 2>/dev/null || printf '{"schema_version":1,"status":"skipped"}\n' > "$inventory_file"
        record_bundle_file "swarm_inventory.json"
        return 0
    fi

    if [[ -n "$_SUPPORT_ACFS_HOME" && -f "$_SUPPORT_ACFS_HOME/scripts/lib/swarm_inventory.sh" ]]; then
        swarm_inventory_script="$_SUPPORT_ACFS_HOME/scripts/lib/swarm_inventory.sh"
    elif [[ -f "$_SUPPORT_SCRIPT_DIR/swarm_inventory.sh" ]]; then
        swarm_inventory_script="$_SUPPORT_SCRIPT_DIR/swarm_inventory.sh"
    fi

    if [[ -z "$swarm_inventory_script" ]]; then
        "$jq_bin" -n \
            --arg generated_at "$generated_at" \
            '{
                schema_version: 1,
                generated_at: $generated_at,
                status: "warn",
                capture: {status: "warn", reason: "swarm_inventory.sh not found"},
                inventory: {present: true, source: "canonical", path_collected: false, raw_hosts_collected: false},
                summary: {
                    hosts_total: 0,
                    active: 0,
                    stale: 0,
                    disabled: 0,
                    stale_probe_count: 0,
                    recommended_agents_total: 0,
                    safe_agents_total: 0,
                    rch_workers: 0,
                    unknown_field_count: 0
                },
                role_counts: {},
                status_counts: {},
                redaction: {
                    paths_redacted: true,
                    raw_hosts_collected: false,
                    raw_hostnames_collected: false,
                    raw_ip_addresses_collected: false,
                    ssh_users_collected: false,
                    ssh_key_paths_collected: false,
                    provider_ids_collected: false,
                    repo_paths_collected: false,
                    home_paths_collected: false,
                    token_like_notes_collected: false,
                    secrets_collected: false
                },
                diagnostics: {error_code: "inventory_tool_missing", redacted_field_paths: []}
            }' > "$inventory_file" 2>/dev/null || printf '{"schema_version":1,"status":"warn"}\n' > "$inventory_file"
        record_bundle_file "swarm_inventory.json"
        return 1
    fi

    report_output="$(support_run_with_timeout "$SWARM_INVENTORY_TIMEOUT" bash "$swarm_inventory_script" --json report --inventory "$source_inventory" 2>/dev/null || true)"
    if ! printf '%s' "$report_output" | "$jq_bin" . >/dev/null 2>&1; then
        "$jq_bin" -n \
            --arg generated_at "$generated_at" \
            '{
                schema_version: 1,
                generated_at: $generated_at,
                status: "fail",
                capture: {status: "fail", reason: "swarm inventory report failed or timed out"},
                inventory: {present: true, source: "canonical", path_collected: false, raw_hosts_collected: false},
                summary: {
                    hosts_total: 0,
                    active: 0,
                    stale: 0,
                    disabled: 0,
                    stale_probe_count: 0,
                    recommended_agents_total: 0,
                    safe_agents_total: 0,
                    rch_workers: 0,
                    unknown_field_count: 0
                },
                role_counts: {},
                status_counts: {},
                redaction: {
                    paths_redacted: true,
                    raw_hosts_collected: false,
                    raw_hostnames_collected: false,
                    raw_ip_addresses_collected: false,
                    ssh_users_collected: false,
                    ssh_key_paths_collected: false,
                    provider_ids_collected: false,
                    repo_paths_collected: false,
                    home_paths_collected: false,
                    token_like_notes_collected: false,
                    secrets_collected: false
                },
                diagnostics: {error_code: "report_failed", redacted_field_paths: []}
            }' > "$inventory_file" 2>/dev/null || printf '{"schema_version":1,"status":"fail"}\n' > "$inventory_file"
        record_bundle_file "swarm_inventory.json"
        return 1
    fi

    printf '%s' "$report_output" | "$jq_bin" \
        --arg generated_at "$generated_at" \
        '
        def n($v): if ($v | type) == "number" then $v else 0 end;
        def summary_zero: {
            hosts_total: 0,
            active: 0,
            stale: 0,
            disabled: 0,
            stale_probe_count: 0,
            recommended_agents_total: 0,
            safe_agents_total: 0,
            rch_workers: 0,
            unknown_field_count: 0
        };
        (.summary // {}) as $summary
        | {
            schema_version: 1,
            generated_at: $generated_at,
            status: (.status // (if .error_code then "fail" else "unknown" end)),
            capture: {
                status: (if .error_code then "fail" else (.status // "unknown") end),
                reason: (if .error_code then "inventory validation failed or inventory JSON was malformed" else "swarm inventory summarized" end)
            },
            inventory: {present: true, source: "canonical", path_collected: false, raw_hosts_collected: false},
            summary: (summary_zero + {
                hosts_total: n($summary.hosts_total),
                active: n($summary.active),
                stale: n($summary.stale),
                disabled: n($summary.disabled),
                stale_probe_count: n($summary.stale_probe_count),
                recommended_agents_total: n($summary.recommended_agents_total),
                safe_agents_total: n($summary.safe_agents_total),
                rch_workers: n($summary.rch_workers),
                unknown_field_count: n($summary.unknown_field_count)
            }),
            role_counts: (.role_counts // {}),
            status_counts: (.status_counts // {}),
            redaction: {
                paths_redacted: true,
                raw_hosts_collected: false,
                raw_hostnames_collected: false,
                raw_ip_addresses_collected: false,
                ssh_users_collected: false,
                ssh_key_paths_collected: false,
                provider_ids_collected: false,
                repo_paths_collected: false,
                home_paths_collected: false,
                token_like_notes_collected: false,
                secrets_collected: false
            },
            diagnostics: {
                error_code: (.error_code // null),
                redacted_field_paths: (.redacted_field_paths // []),
                warnings: (.warnings // [])
            }
        }' > "$inventory_file" 2>/dev/null || {
        printf '{"schema_version":1,"status":"warn","capture":{"status":"warn","reason":"swarm inventory sanitization failed"},"inventory":{"present":true,"raw_hosts_collected":false},"redaction":{"paths_redacted":true,"raw_hosts_collected":false,"secrets_collected":false}}\n' > "$inventory_file"
        record_bundle_file "swarm_inventory.json"
        return 1
    }

    record_bundle_file "swarm_inventory.json"
    [[ "$("$jq_bin" -r '.status // "fail"' "$inventory_file" 2>/dev/null || printf 'fail')" != "fail" ]]
}

# Capture a sanitized ACFS resource-profile snapshot. Raw paths are intentionally
# omitted; support bundles only need status, safety metadata, and wrapper shape.
# Usage: capture_resource_profile_json <bundle_dir>
capture_resource_profile_json() {
    local bundle_dir="$1"
    local resource_file="$bundle_dir/resource_profile.json"
    local jq_bin=""
    local capacity_script=""
    local profile_home=""
    local capacity_output=""
    local capture_status="pass"
    local capture_reason="resource profile summarized"

    jq_bin="$(support_system_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        printf '{"schema_version":1,"status":"skipped","capture":{"status":"skipped","reason":"jq not found"},"redaction":{"paths_redacted":true,"raw_paths_collected":false,"secrets_collected":false}}\n' > "$resource_file"
        record_bundle_file "resource_profile.json"
        return 1
    fi

    if [[ -n "$_SUPPORT_ACFS_HOME" ]] && [[ -f "$_SUPPORT_ACFS_HOME/scripts/lib/capacity.sh" ]]; then
        capacity_script="$_SUPPORT_ACFS_HOME/scripts/lib/capacity.sh"
    elif [[ -f "$_SUPPORT_SCRIPT_DIR/capacity.sh" ]]; then
        capacity_script="$_SUPPORT_SCRIPT_DIR/capacity.sh"
    fi

    if [[ -z "$capacity_script" ]]; then
        printf '{"schema_version":1,"status":"skipped","capture":{"status":"skipped","reason":"capacity.sh not found"},"redaction":{"paths_redacted":true,"raw_paths_collected":false,"secrets_collected":false}}\n' > "$resource_file"
        record_bundle_file "resource_profile.json"
        return 1
    fi

    profile_home="${ACFS_RESOURCE_PROFILE_HOME:-}"
    if [[ -z "$profile_home" ]]; then
        profile_home="${SUPPORT_TARGET_HOME:-${_SUPPORT_CURRENT_HOME:-${HOME:-/tmp}}}/.acfs/resource-profile"
    fi

    log_detail "Capturing resource profile summary..."
    if ! capacity_output="$(ACFS_RESOURCE_PROFILE_HOME="$profile_home" support_run_with_timeout "$RESOURCE_PROFILE_TIMEOUT" bash "$capacity_script" --json --resource-profile)"; then
        capture_status="warn"
        capture_reason="capacity resource profile command failed or timed out"
    fi

    if ! printf '%s' "$capacity_output" | "$jq_bin" . >/dev/null 2>&1; then
        "$jq_bin" -n \
            --arg status "$capture_status" \
            --arg reason "$capture_reason" \
            '{
                schema_version: 1,
                status: "warn",
                capture: {status: $status, reason: $reason},
                redaction: {paths_redacted: true, raw_paths_collected: false, secrets_collected: false}
            }' > "$resource_file" 2>/dev/null || printf '{"schema_version":1,"status":"warn"}\n' > "$resource_file"
        record_bundle_file "resource_profile.json"
        return 1
    fi

    printf '%s' "$capacity_output" | "$jq_bin" \
        --arg capture_status "$capture_status" \
        --arg capture_reason "$capture_reason" \
        '{
            schema_version: 1,
            generated_at: (.generated_at // null),
            status: (if (.status // "pass") == "fail" then "fail" elif $capture_status == "warn" then "warn" else (.status // "pass") end),
            capture: {status: $capture_status, reason: $capture_reason},
            mode: (.mode // "unknown"),
            opt_in: (.opt_in // null),
            systemd: (.systemd // {}),
            safety: (.safety // {}),
            classes: [(.classes // [])[] | {name: (.name // null), slice: (.slice // null), properties: (.properties // [])}],
            wrappers: [(.wrappers // [])[] | {name: (.name // null), purpose: (.purpose // null), command_present: has("command")}],
            managed_file_count: ((.managed_files // []) | length),
            actions: (.actions // []),
            remediation: (.remediation // []),
            redaction: {
                paths_redacted: true,
                raw_paths_collected: false,
                secrets_collected: false
            }
        }' > "$resource_file" 2>/dev/null || {
        printf '{"schema_version":1,"status":"warn","capture":{"status":"warn","reason":"resource profile sanitization failed"},"redaction":{"paths_redacted":true,"raw_paths_collected":false,"secrets_collected":false}}\n' > "$resource_file"
        record_bundle_file "resource_profile.json"
        return 1
    }

    record_bundle_file "resource_profile.json"
    [[ "$capture_status" == "pass" ]]
}

support_binary_path_any() {
    local candidate=""
    local path_value=""

    for candidate in "$@"; do
        path_value="$(support_system_binary_path "$candidate" 2>/dev/null || command -v "$candidate" 2>/dev/null || true)"
        if [[ -n "$path_value" ]]; then
            printf '%s\n' "$path_value"
            return 0
        fi
    done

    return 1
}

support_json_count_items() {
    local json="$1"
    local jq_bin="$2"
    local count=""

    count="$(printf '%s' "$json" | "$jq_bin" -r '
        if type == "array" then length
        elif has("issues") and (.issues | type == "array") then .issues | length
        elif has("items") and (.items | type == "array") then .items | length
        elif has("jobs") and (.jobs | type == "array") then .jobs | length
        elif has("queue") and (.queue | type == "array") then .queue | length
        elif has("total") then .total
        else 0
        end
    ' 2>/dev/null || true)"
    [[ "$count" =~ ^[0-9]+$ ]] || count="0"
    printf '%s\n' "$count"
}

support_agent_mail_storage_root() {
    local candidate=""

    for candidate in \
        "${SUPPORT_TARGET_HOME:-}/.mcp_agent_mail_git_mailbox_repo" \
        "${_SUPPORT_CURRENT_HOME:-}/.mcp_agent_mail_git_mailbox_repo" \
        "${HOME:-}/.mcp_agent_mail_git_mailbox_repo"
    do
        [[ -n "$candidate" && -d "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

support_count_agent_mail_messages() {
    local storage_root="$1"

    [[ -n "$storage_root" && -d "$storage_root/messages" ]] || {
        printf '0\n'
        return 0
    }

    find "$storage_root/messages" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' '
}

capture_swarm_timeline_json() {
    local bundle_dir="$1"
    local timeline_file="$bundle_dir/swarm_timeline.json"
    local jq_bin=""
    local generated_at=""

    jq_bin="$(support_system_binary_path jq 2>/dev/null || true)"
    generated_at="$(date -Iseconds 2>/dev/null || date)"

    if [[ -z "$jq_bin" ]]; then
        printf '{"schema_version":1,"generated_at":"%s","status":"skipped","privacy":"Raw mail bodies, terminal history, and command output are not collected.","probes":[{"id":"jq","status":"skipped","reason":"jq not found"}]}\n' "$generated_at" > "$timeline_file"
        record_bundle_file "swarm_timeline.json"
        return 1
    fi

    local telemetry_json='{"status":"skipped","reason":"swarm_status.json unavailable"}'
    local telemetry_probe_status="skipped"
    local telemetry_probe_reason="swarm_status.json unavailable"
    if [[ -f "$bundle_dir/swarm_status.json" ]] && "$jq_bin" . "$bundle_dir/swarm_status.json" >/dev/null 2>&1; then
        telemetry_json="$("$jq_bin" -c '{
            status: (.status // "unknown"),
            generated_at: (.generated_at // null),
            warnings: (.warnings // []),
            host: (.host // {})
        }' "$bundle_dir/swarm_status.json" 2>/dev/null || printf '{"status":"warn","reason":"swarm_status.json summary failed"}')"
        telemetry_probe_status="pass"
        telemetry_probe_reason="summarized swarm_status.json"
    fi

    local br_bin=""
    local beads_json='{"status":"skipped","reason":"br not found in PATH"}'
    local beads_probe_status="skipped"
    local beads_probe_reason="br not found in PATH"
    br_bin="$(support_binary_path_any br 2>/dev/null || true)"
    if [[ -n "$br_bin" ]]; then
        local ready_json="" progress_json="" open_json="" cycles_json=""
        local ready_count=0 progress_count=0 open_count=0 cycle_count=0
        local beads_warning=""
        if ready_json="$(support_run_with_timeout "$SWARM_TIMELINE_TIMEOUT" "$br_bin" ready --json)"; then
            ready_count="$(support_json_count_items "$ready_json" "$jq_bin")"
        else
            beads_warning="br ready --json failed or timed out"
        fi
        if progress_json="$(support_run_with_timeout "$SWARM_TIMELINE_TIMEOUT" "$br_bin" list --status in_progress --json)"; then
            progress_count="$(support_json_count_items "$progress_json" "$jq_bin")"
        else
            beads_warning="${beads_warning:+$beads_warning; }br list --status in_progress --json failed or timed out"
        fi
        if open_json="$(support_run_with_timeout "$SWARM_TIMELINE_TIMEOUT" "$br_bin" list --status open --json)"; then
            open_count="$(support_json_count_items "$open_json" "$jq_bin")"
        else
            beads_warning="${beads_warning:+$beads_warning; }br list --status open --json failed or timed out"
        fi
        if cycles_json="$(support_run_with_timeout "$SWARM_TIMELINE_TIMEOUT" "$br_bin" dep cycles --json)"; then
            cycle_count="$(printf '%s' "$cycles_json" | "$jq_bin" -r '.count // 0' 2>/dev/null || echo 0)"
            [[ "$cycle_count" =~ ^[0-9]+$ ]] || cycle_count=0
        else
            beads_warning="${beads_warning:+$beads_warning; }br dep cycles --json failed or timed out"
        fi
        beads_probe_status="pass"
        beads_probe_reason="beads status snapshot collected"
        if [[ -n "$beads_warning" ]]; then
            beads_probe_status="warn"
            beads_probe_reason="$beads_warning"
        fi
        beads_json="$("$jq_bin" -n \
            --arg status "$beads_probe_status" \
            --arg reason "$beads_probe_reason" \
            --argjson ready "$ready_count" \
            --argjson in_progress "$progress_count" \
            --argjson open "$open_count" \
            --argjson dependency_cycles "$cycle_count" \
            '{status: $status, reason: $reason, ready_count: $ready, in_progress_count: $in_progress, open_count: $open, dependency_cycle_count: $dependency_cycles}')"
    fi

    local tmux_bin="" ntm_bin=""
    local ntm_json='{"status":"skipped","reason":"tmux and ntm not found in PATH"}'
    local ntm_probe_status="skipped"
    local ntm_probe_reason="tmux and ntm not found in PATH"
    tmux_bin="$(support_binary_path_any tmux 2>/dev/null || true)"
    ntm_bin="$(support_binary_path_any ntm 2>/dev/null || true)"
    if [[ -n "$tmux_bin" || -n "$ntm_bin" ]]; then
        local ntm_robot_ok=false
        local session_count=0
        local window_count=0
        local tmux_warning=""
        local ntm_output=""
        local tmux_output=""
        if [[ -n "$ntm_bin" ]] && ntm_output="$(support_run_with_timeout "$SWARM_TIMELINE_TIMEOUT" "$ntm_bin" --robot-status)"; then
            [[ -n "$ntm_output" ]] && ntm_robot_ok=true
        fi
        if [[ -n "$tmux_bin" ]]; then
            if tmux_output="$(support_run_with_timeout "$SWARM_TIMELINE_TIMEOUT" "$tmux_bin" list-sessions -F '#S	#{session_windows}')"; then
                session_count="$(printf '%s\n' "$tmux_output" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
                window_count="$(printf '%s\n' "$tmux_output" | awk '{sum += $2} END {print sum + 0}')"
            else
                tmux_warning="tmux has no listable sessions or timed out"
            fi
        fi
        ntm_probe_status="pass"
        ntm_probe_reason="NTM/tmux summary collected without session names"
        if [[ -n "$tmux_warning" && "$ntm_robot_ok" != true ]]; then
            ntm_probe_status="warn"
            ntm_probe_reason="$tmux_warning"
        fi
        ntm_json="$("$jq_bin" -n \
            --arg status "$ntm_probe_status" \
            --arg reason "$ntm_probe_reason" \
            --argjson ntm_available "$( [[ -n "$ntm_bin" ]] && echo true || echo false )" \
            --argjson ntm_robot_ok "$ntm_robot_ok" \
            --argjson tmux_available "$( [[ -n "$tmux_bin" ]] && echo true || echo false )" \
            --argjson sessions "$session_count" \
            --argjson windows "$window_count" \
            '{status: $status, reason: $reason, ntm_available: $ntm_available, ntm_robot_status_ok: $ntm_robot_ok, tmux_available: $tmux_available, tmux_session_count: $sessions, tmux_window_count: $windows}')"
    fi

    local rch_bin=""
    local rch_json='{"status":"skipped","reason":"rch not found in PATH"}'
    local rch_probe_status="skipped"
    local rch_probe_reason="rch not found in PATH"
    rch_bin="$(support_binary_path_any rch 2>/dev/null || true)"
    if [[ -n "$rch_bin" ]]; then
        local rch_status_output="" rch_queue_output=""
        local rch_status_ok=false rch_queue_ok=false
        local rch_queue_count=0
        if rch_status_output="$(support_run_with_timeout "$SWARM_TIMELINE_TIMEOUT" "$rch_bin" status --json)" \
            && printf '%s' "$rch_status_output" | "$jq_bin" . >/dev/null 2>&1; then
            rch_status_ok=true
        fi
        if rch_queue_output="$(support_run_with_timeout "$SWARM_TIMELINE_TIMEOUT" "$rch_bin" queue --json)" \
            && printf '%s' "$rch_queue_output" | "$jq_bin" . >/dev/null 2>&1; then
            rch_queue_ok=true
            rch_queue_count="$(support_json_count_items "$rch_queue_output" "$jq_bin")"
        fi
        rch_probe_status="pass"
        rch_probe_reason="RCH status and queue summarized"
        if [[ "$rch_status_ok" != true || "$rch_queue_ok" != true ]]; then
            rch_probe_status="warn"
            rch_probe_reason="RCH status or queue JSON failed or timed out"
        fi
        rch_json="$("$jq_bin" -n \
            --arg status "$rch_probe_status" \
            --arg reason "$rch_probe_reason" \
            --argjson status_json_ok "$rch_status_ok" \
            --argjson queue_json_ok "$rch_queue_ok" \
            --argjson queue_count "$rch_queue_count" \
            '{status: $status, reason: $reason, status_json_ok: $status_json_ok, queue_json_ok: $queue_json_ok, queue_count: $queue_count}')"
    fi

    local am_bin="" agent_mail_json='{"status":"skipped","reason":"Agent Mail CLI and archive not found"}'
    local agent_mail_probe_status="skipped"
    local agent_mail_probe_reason="Agent Mail CLI and archive not found"
    am_bin="$(support_binary_path_any am mcp-agent-mail agent-mail mcp_agent_mail 2>/dev/null || true)"
    local am_storage_root=""
    local am_message_count=0
    am_storage_root="$(support_agent_mail_storage_root 2>/dev/null || true)"
    if [[ -n "$am_bin" || -n "$am_storage_root" ]]; then
        am_message_count="$(support_count_agent_mail_messages "$am_storage_root")"
        agent_mail_probe_status="pass"
        agent_mail_probe_reason="Agent Mail pointer summary collected; raw bodies excluded"
        agent_mail_json="$("$jq_bin" -n \
            --arg status "$agent_mail_probe_status" \
            --arg reason "$agent_mail_probe_reason" \
            --argjson cli_available "$( [[ -n "$am_bin" ]] && echo true || echo false )" \
            --argjson archive_present "$( [[ -n "$am_storage_root" ]] && echo true || echo false )" \
            --argjson recent_message_file_count "$am_message_count" \
            '{status: $status, reason: $reason, cli_available: $cli_available, archive_present: $archive_present, recent_thread_pointers: {count: $recent_message_file_count, raw_bodies_collected: false}}')"
    fi

    local resource_json
    resource_json="$(printf '%s' "$telemetry_json" | "$jq_bin" -c '{
        status: (if (.host // {}) == {} then "skipped" else "pass" end),
        load_1m: (.host.load_1m // null),
        cpu_count: (.host.cpu_count // null),
        mem_total_kb: (.host.mem_total_kb // null),
        mem_available_kb: (.host.mem_available_kb // null),
        disk_available_kb: (.host.disk_available_kb // null),
        raw_process_command_lines_collected: false
    }' 2>/dev/null || printf '{"status":"skipped","raw_process_command_lines_collected":false}')"

    "$jq_bin" -n \
        --arg generated_at "$generated_at" \
        --arg privacy "Raw Agent Mail bodies, terminal history, tmux panes, and command output are intentionally excluded." \
        --argjson telemetry "$telemetry_json" \
        --arg telemetry_probe_status "$telemetry_probe_status" \
        --arg telemetry_probe_reason "$telemetry_probe_reason" \
        --argjson agent_mail "$agent_mail_json" \
        --arg agent_mail_probe_status "$agent_mail_probe_status" \
        --arg agent_mail_probe_reason "$agent_mail_probe_reason" \
        --argjson beads "$beads_json" \
        --arg beads_probe_status "$beads_probe_status" \
        --arg beads_probe_reason "$beads_probe_reason" \
        --argjson ntm "$ntm_json" \
        --arg ntm_probe_status "$ntm_probe_status" \
        --arg ntm_probe_reason "$ntm_probe_reason" \
        --argjson rch "$rch_json" \
        --arg rch_probe_status "$rch_probe_status" \
        --arg rch_probe_reason "$rch_probe_reason" \
        --argjson resource_pressure "$resource_json" \
        '{
            schema_version: 1,
            generated_at: $generated_at,
            status: ([$telemetry_probe_status, $agent_mail_probe_status, $beads_probe_status, $ntm_probe_status, $rch_probe_status] as $statuses | if (($statuses | index("warn")) or ($statuses | index("skipped"))) then "warn" else "pass" end),
            privacy: $privacy,
            probes: [
                {id: "telemetry", status: $telemetry_probe_status, reason: $telemetry_probe_reason},
                {id: "agent_mail", status: $agent_mail_probe_status, reason: $agent_mail_probe_reason},
                {id: "beads", status: $beads_probe_status, reason: $beads_probe_reason},
                {id: "ntm", status: $ntm_probe_status, reason: $ntm_probe_reason},
                {id: "rch", status: $rch_probe_status, reason: $rch_probe_reason},
                {id: "resource_pressure", status: ($resource_pressure.status // "skipped"), reason: "derived from redacted host metrics"}
            ],
            timeline: {
                telemetry: $telemetry,
                agent_mail: $agent_mail,
                beads: $beads,
                ntm: $ntm,
                rch: $rch,
                resource_pressure: $resource_pressure
            }
        }' > "$timeline_file" 2>/dev/null || {
        echo '{"schema_version":1,"status":"warn","probes":[{"id":"swarm_timeline","status":"warn","reason":"timeline render failed"}]}' > "$timeline_file"
        record_bundle_file "swarm_timeline.json"
        return 1
    }

    record_bundle_file "swarm_timeline.json"
    return 0
}

# Capture tool versions.
# Usage: capture_versions <bundle_dir>
capture_versions() {
    local bundle_dir="$1"
    local versions_file="$bundle_dir/versions.json"
    local jq_bin=""

    jq_bin="$(support_system_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        log_warn "jq not available, skipping versions capture"
        return 1
    fi

    local versions="{}"

    # Helper to safely get a version string
    _ver() {
        local cmd="$1"
        local args="${2:---version}"
        local cmd_path=""
        cmd_path="$(support_system_binary_path "$cmd" 2>/dev/null || command -v "$cmd" 2>/dev/null || true)"
        if [[ -n "$cmd_path" ]]; then
            timeout 5 "$cmd_path" $args 2>/dev/null | head -1 || echo "error"
        else
            echo "not installed"
        fi
    }

    versions=$("$jq_bin" -n \
        --arg bash_ver "${BASH_VERSION:-unknown}" \
        --arg zsh_ver "$(_ver zsh --version)" \
        --arg node_ver "$(_ver node -v)" \
        --arg bun_ver "$(_ver bun --version)" \
        --arg cargo_ver "$(_ver cargo --version)" \
        --arg go_ver "$(_ver go version)" \
        --arg python_ver "$(_ver python3 --version)" \
        --arg uv_ver "$(_ver uv --version)" \
        --arg git_ver "$(_ver git --version)" \
        --arg claude_ver "$(_ver claude --version)" \
        --arg gh_ver "$(_ver gh --version)" \
        --arg jq_ver "$(_ver jq --version)" \
        --arg tmux_ver "$(_ver tmux -V)" \
        --arg rg_ver "$(_ver rg --version)" \
        '{
            bash: $bash_ver,
            zsh: $zsh_ver,
            node: $node_ver,
            bun: $bun_ver,
            cargo: $cargo_ver,
            go: $go_ver,
            python3: $python_ver,
            uv: $uv_ver,
            git: $git_ver,
            claude: $claude_ver,
            gh: $gh_ver,
            jq: $jq_ver,
            tmux: $tmux_ver,
            ripgrep: $rg_ver
        }') || versions='{"error": "failed to collect versions"}'

    echo "$versions" > "$versions_file"
    record_bundle_file "versions.json"
}

# Capture environment summary.
# Usage: capture_env_summary <bundle_dir>
capture_env_summary() {
    local bundle_dir="$1"
    local env_file="$bundle_dir/environment.json"
    local support_home="${SUPPORT_TARGET_HOME:-${_SUPPORT_CURRENT_HOME:-}}"
    local support_user="${SUPPORT_TARGET_USER:-$(support_resolve_current_user 2>/dev/null || echo unknown)}"
    local jq_bin=""

    jq_bin="$(support_system_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        log_warn "jq not available, skipping environment capture"
        return 1
    fi

    local os_id="unknown"
    local os_version="unknown"
    local os_codename="unknown"
    if [[ -f /etc/os-release ]]; then
        os_id=$(. /etc/os-release && echo "${ID:-unknown}")
        os_version=$(. /etc/os-release && echo "${VERSION_ID:-unknown}")
        os_codename=$(. /etc/os-release && echo "${VERSION_CODENAME:-unknown}")
    fi

    local acfs_version="unknown"
    if [[ -n "$_SUPPORT_ACFS_HOME" ]] && [[ -f "$_SUPPORT_ACFS_HOME/VERSION" ]]; then
        acfs_version=$(cat "$_SUPPORT_ACFS_HOME/VERSION" 2>/dev/null) || acfs_version="unknown"
    fi

    "$jq_bin" -n \
        --arg hostname "$(hostname 2>/dev/null || echo unknown)" \
        --arg kernel "$(uname -r 2>/dev/null || echo unknown)" \
        --arg arch "$(uname -m 2>/dev/null || echo unknown)" \
        --arg os_id "$os_id" \
        --arg os_version "$os_version" \
        --arg os_codename "$os_codename" \
        --arg user "$support_user" \
        --arg home "$support_home" \
        --arg acfs_home "$_SUPPORT_ACFS_HOME" \
        --arg acfs_version "$acfs_version" \
        --arg shell "${SHELL:-unknown}" \
        --argjson uptime_seconds "$(cat /proc/uptime 2>/dev/null | awk '{printf "%d", $1}' || echo 0)" \
        --argjson mem_total_kb "$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)" \
        --argjson mem_available_kb "$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)" \
        --argjson disk_total_kb "$(df -k "$support_home" 2>/dev/null | tail -1 | awk '{print $2}' || echo 0)" \
        --argjson disk_available_kb "$(df -k "$support_home" 2>/dev/null | tail -1 | awk '{print $4}' || echo 0)" \
        '{
            hostname: $hostname,
            kernel: $kernel,
            arch: $arch,
            os: {id: $os_id, version: $os_version, codename: $os_codename},
            user: $user,
            home: $home,
            acfs_home: $acfs_home,
            acfs_version: $acfs_version,
            shell: $shell,
            uptime_seconds: $uptime_seconds,
            memory: {total_kb: $mem_total_kb, available_kb: $mem_available_kb},
            disk: {total_kb: $disk_total_kb, available_kb: $disk_available_kb}
        }' > "$env_file" 2>/dev/null || {
        log_warn "Failed to capture environment"
        return 1
    }

    record_bundle_file "environment.json"
}

# Write a manifest JSON describing the bundle contents.
# Usage: write_manifest <bundle_dir>
write_manifest() {
    local bundle_dir="$1"
    local manifest_file="$bundle_dir/manifest.json"
    local jq_bin=""

    jq_bin="$(support_system_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        # Fallback: write a simple text manifest
        record_bundle_file "manifest.txt"
        printf '%s\n' "${BUNDLE_FILES[@]}" > "$bundle_dir/manifest.txt"
        return 0
    fi

    record_bundle_file "manifest.json"

    local acfs_version="unknown"
    if [[ -n "$_SUPPORT_ACFS_HOME" ]] && [[ -f "$_SUPPORT_ACFS_HOME/VERSION" ]]; then
        acfs_version=$(cat "$_SUPPORT_ACFS_HOME/VERSION" 2>/dev/null) || acfs_version="unknown"
    fi

    # Build files array from BUNDLE_FILES
    local files_json
    files_json=$(printf '%s\n' "${BUNDLE_FILES[@]}" | "$jq_bin" -R . | "$jq_bin" -s .) || files_json="[]"
    local doctor_manifest=""
    local swarm_status_manifest=""
    local swarm_timeline_manifest=""
    local provenance_manifest=""
    local resource_profile_manifest=""
    local local_progress_manifest=""
    local checkpoint_summary_manifest=""
    local swarm_inventory_manifest=""
    local versions_manifest=""
    local environment_manifest=""
    doctor_manifest="$(support_manifest_diagnostic_json "$bundle_dir" "doctor.json" "doctor" '["secret_values","local_paths","command_output"]' "$jq_bin")"
    swarm_status_manifest="$(support_manifest_diagnostic_json "$bundle_dir" "swarm_status.json" "swarm_status" '["host_metrics","local_paths","command_output"]' "$jq_bin")"
    swarm_timeline_manifest="$(support_manifest_diagnostic_json "$bundle_dir" "swarm_timeline.json" "swarm_timeline" '["agent_mail_bodies","terminal_history","tmux_panes","command_output","local_paths"]' "$jq_bin")"
    provenance_manifest="$(support_manifest_diagnostic_json "$bundle_dir" "provenance.json" "provenance" '["tool_versions","install_sources","local_paths"]' "$jq_bin")"
    resource_profile_manifest="$(support_manifest_diagnostic_json "$bundle_dir" "resource_profile.json" "resource_profile" '["local_paths","wrapper_commands","secret_values"]' "$jq_bin")"
    local_progress_manifest="$(support_manifest_diagnostic_json "$bundle_dir" "local_progress.json" "local_progress" '["local_milestones","wizard_steps","installer_phase_ids","onboard_lesson_numbers"]' "$jq_bin")"
    checkpoint_summary_manifest="$(support_manifest_diagnostic_json "$bundle_dir" "checkpoint_summary.json" "checkpoint_summary" '["state_schema_version","installer_phase_ids","checkpoint_status"]' "$jq_bin")"
    swarm_inventory_manifest="$(support_manifest_diagnostic_json "$bundle_dir" "swarm_inventory.json" "swarm_inventory" '["hostnames","ip_addresses","ssh_users","ssh_key_paths","provider_ids","repo_paths","home_paths","token_like_notes"]' "$jq_bin")"
    versions_manifest="$(support_manifest_diagnostic_json "$bundle_dir" "versions.json" "versions" '["tool_versions"]' "$jq_bin")"
    environment_manifest="$(support_manifest_diagnostic_json "$bundle_dir" "environment.json" "environment" '["hostnames","home_paths","local_paths"]' "$jq_bin")"

    "$jq_bin" -n \
        --argjson schema_version 1 \
        --arg created_at "$(date -Iseconds)" \
        --arg created_by "acfs support-bundle" \
        --arg acfs_version "$acfs_version" \
        --arg bundle_dir "$(basename "$bundle_dir")" \
        --argjson files "$files_json" \
        --argjson file_count "${#BUNDLE_FILES[@]}" \
        --argjson redaction_enabled "$( [[ "$REDACT" == "true" ]] && echo true || echo false )" \
        --argjson redaction_files_modified "$REDACTION_COUNT" \
        --argjson doctor_manifest "$doctor_manifest" \
        --argjson swarm_status_manifest "$swarm_status_manifest" \
        --argjson swarm_timeline_manifest "$swarm_timeline_manifest" \
        --argjson provenance_manifest "$provenance_manifest" \
        --argjson resource_profile_manifest "$resource_profile_manifest" \
        --argjson local_progress_manifest "$local_progress_manifest" \
        --argjson checkpoint_summary_manifest "$checkpoint_summary_manifest" \
        --argjson swarm_inventory_manifest "$swarm_inventory_manifest" \
        --argjson versions_manifest "$versions_manifest" \
        --argjson environment_manifest "$environment_manifest" \
        '{
            schema_version: $schema_version,
            created_at: $created_at,
            created_by: $created_by,
            acfs_version: $acfs_version,
            bundle_id: $bundle_dir,
            file_count: $file_count,
            files: $files,
            redaction: {
                enabled: $redaction_enabled,
                files_modified: $redaction_files_modified,
                patterns: ["api_key", "aws_key", "github_token", "github_pat", "vault_token", "slack_token", "bearer", "jwt", "password", "private_key", "generic_secret", "message_snippet", "command_path"]
            },
            diagnostics: {
                doctor: $doctor_manifest,
                swarm_status: $swarm_status_manifest,
                swarm_timeline: $swarm_timeline_manifest,
                provenance: $provenance_manifest,
                resource_profile: $resource_profile_manifest,
                local_progress: $local_progress_manifest,
                checkpoint_summary: $checkpoint_summary_manifest,
                swarm_inventory: $swarm_inventory_manifest,
                versions: $versions_manifest,
                environment: $environment_manifest
            }
        }' > "$manifest_file" 2>/dev/null || return 1
}

support_report_markdown_link() {
    local bundle_dir="$1"
    local relative_path="$2"

    [[ -f "$bundle_dir/$relative_path" ]] || return 1
    printf '[%s](%s)' "$relative_path" "$relative_path"
}

support_report_json_status() {
    local bundle_dir="$1"
    local relative_path="$2"
    local jq_bin="$3"
    local file_path="$bundle_dir/$relative_path"

    [[ -f "$file_path" ]] || {
        printf 'missing\n'
        return 0
    }
    [[ -n "$jq_bin" ]] || {
        printf 'present\n'
        return 0
    }
    "$jq_bin" . "$file_path" >/dev/null 2>&1 || {
        printf 'malformed\n'
        return 0
    }
    "$jq_bin" -r '.status // .summary.status // .capture.status // "present"' "$file_path" 2>/dev/null || printf 'present\n'
}

support_report_sensitive_field_findings() {
    local bundle_dir="$1"
    local jq_bin="$2"
    local file_path=""
    local relative_path=""
    local findings=""
    local sensitive_keys=""

    [[ -n "$jq_bin" ]] || return 0

    while IFS= read -r file_path; do
        [[ -f "$file_path" ]] || continue
        "$jq_bin" . "$file_path" >/dev/null 2>&1 || continue
        relative_path="${file_path#"$bundle_dir"/}"
        sensitive_keys="$("$jq_bin" -r '
            paths as $p
            | select(($p | length) > 0)
            | ($p[-1] // empty)
            | select(type == "string")
            | select(test("(hostname|(^|_)ip($|_)|address|ssh_key|private_key|token|password|credential|provider_api_key|project_path|(^|_)home($|_))"; "i"))
        ' "$file_path" 2>/dev/null | sort -u | paste -sd, - || true)"
        [[ -n "$sensitive_keys" ]] || continue
        findings+="- ${relative_path}: sensitive-looking field names detected (${sensitive_keys}); values are not summarized."$'\n'
    done < <(find "$bundle_dir" -maxdepth 4 -type f \( -name '*.json' -o -name '*.yaml' -o -name '*.yml' \) 2>/dev/null | sort)

    printf '%s' "$findings"
}

support_report_write_link_line() {
    local bundle_dir="$1"
    local relative_path="$2"
    local label="$3"
    local status="$4"
    local report_file="$5"
    local link=""

    link="$(support_report_markdown_link "$bundle_dir" "$relative_path" 2>/dev/null || true)"
    [[ -n "$link" ]] || return 0
    printf '| %s | %s | %s |\n' "$label" "$link" "$status" >> "$report_file"
}

# Write a small redacted Markdown index for the support bundle.
# Usage: write_support_report_index <bundle_dir>
write_support_report_index() {
    local bundle_dir="$1"
    local report_file="$bundle_dir/support-report.md"
    local jq_bin=""
    local generated_at=""
    local redaction_enabled="true"
    local redaction_files_modified="$REDACTION_COUNT"
    local sensitive_findings=""
    local file=""
    local relative_path=""
    local status=""

    jq_bin="$(support_system_binary_path jq 2>/dev/null || true)"
    generated_at="$(date -Iseconds 2>/dev/null || date)"

    if [[ -n "$jq_bin" && -f "$bundle_dir/manifest.json" ]] && "$jq_bin" . "$bundle_dir/manifest.json" >/dev/null 2>&1; then
        redaction_enabled="$("$jq_bin" -r '.redaction.enabled // true' "$bundle_dir/manifest.json" 2>/dev/null || printf 'true')"
        redaction_files_modified="$("$jq_bin" -r '.redaction.files_modified // 0' "$bundle_dir/manifest.json" 2>/dev/null || printf '0')"
    fi

    sensitive_findings="$(support_report_sensitive_field_findings "$bundle_dir" "$jq_bin")"

    {
        printf '# ACFS Support Bundle Report\n\n'
        printf 'Generated: %s\n\n' "$generated_at"
        printf 'This report is a redacted index. It links only files present in this bundle and does not include raw command output, local paths, hostnames, message bodies, tokens, passwords, or private keys.\n\n'

        printf '## Start Here\n\n'
        printf '| Item | Link | Status |\n'
        printf '| --- | --- | --- |\n'
    } > "$report_file" || return 1

    status="$(support_report_json_status "$bundle_dir" "manifest.json" "$jq_bin")"
    support_report_write_link_line "$bundle_dir" "manifest.json" "Manifest" "$status" "$report_file"
    status="$(support_report_json_status "$bundle_dir" "doctor.json" "$jq_bin")"
    support_report_write_link_line "$bundle_dir" "doctor.json" "Doctor" "$status" "$report_file"
    status="$(support_report_json_status "$bundle_dir" "swarm_status.json" "$jq_bin")"
    support_report_write_link_line "$bundle_dir" "swarm_status.json" "Swarm status" "$status" "$report_file"
    status="$(support_report_json_status "$bundle_dir" "swarm_timeline.json" "$jq_bin")"
    support_report_write_link_line "$bundle_dir" "swarm_timeline.json" "Swarm timeline" "$status" "$report_file"
    status="$(support_report_json_status "$bundle_dir" "provenance.json" "$jq_bin")"
    support_report_write_link_line "$bundle_dir" "provenance.json" "Tool provenance" "$status" "$report_file"
    status="$(support_report_json_status "$bundle_dir" "resource_profile.json" "$jq_bin")"
    support_report_write_link_line "$bundle_dir" "resource_profile.json" "Resource profile" "$status" "$report_file"
    status="$(support_report_json_status "$bundle_dir" "local_progress.json" "$jq_bin")"
    support_report_write_link_line "$bundle_dir" "local_progress.json" "Local progress" "$status" "$report_file"
    status="$(support_report_json_status "$bundle_dir" "checkpoint_summary.json" "$jq_bin")"
    support_report_write_link_line "$bundle_dir" "checkpoint_summary.json" "Checkpoint summary" "$status" "$report_file"
    status="$(support_report_json_status "$bundle_dir" "swarm_inventory.json" "$jq_bin")"
    support_report_write_link_line "$bundle_dir" "swarm_inventory.json" "Swarm inventory" "$status" "$report_file"
    status="$(support_report_json_status "$bundle_dir" "versions.json" "$jq_bin")"
    support_report_write_link_line "$bundle_dir" "versions.json" "Versions" "$status" "$report_file"
    status="$(support_report_json_status "$bundle_dir" "environment.json" "$jq_bin")"
    support_report_write_link_line "$bundle_dir" "environment.json" "Environment" "$status" "$report_file"

    {
        printf '\n## Redaction\n\n'
        printf '%s\n' "- Redaction enabled: \`$redaction_enabled\`"
        printf '%s\n' "- Files modified by redaction: \`$redaction_files_modified\`"
        printf '%s\n\n' "- Raw Agent Mail bodies, terminal history, tmux panes, command output snippets, local project paths, and secret values are intentionally not summarized here."
    } >> "$report_file" || return 1

    if [[ -n "$sensitive_findings" ]]; then
        {
            printf '## Sensitive Field Review\n\n'
            printf 'Sensitive-looking field names were found. The report fails closed by listing field names only and not summarizing values from those files.\n\n'
            printf '%s\n' "$sensitive_findings"
        } >> "$report_file" || return 1
    fi

    {
        printf '## Simulation And Rehearsal Artifacts\n\n'
        printf '| Artifact | Link |\n'
        printf '| --- | --- |\n'
    } >> "$report_file" || return 1

    while IFS= read -r file; do
        relative_path="${file#"$bundle_dir"/}"
        case "$relative_path" in
            summary.json|scenario_*/summary.json|scenario_*/mock_rehearsal.json|scenario_*/plan.json|scenario_*/telemetry.json|scenario_*/capacity.json|scenario_*/resource.json)
                printf '| %s | [%s](%s) |\n' "$relative_path" "$relative_path" "$relative_path" >> "$report_file" || return 1
                ;;
        esac
    done < <(find "$bundle_dir" -maxdepth 3 -type f -name '*.json' 2>/dev/null | sort)

    {
        printf '\n## All Bundle Files\n\n'
        printf '| File |\n'
        printf '| --- |\n'
    } >> "$report_file" || return 1

    for relative_path in "${BUNDLE_FILES[@]:-}"; do
        [[ "$relative_path" == "support-report.md" ]] && continue
        [[ -f "$bundle_dir/$relative_path" ]] || continue
        printf '| [%s](%s) |\n' "$relative_path" "$relative_path" >> "$report_file" || return 1
    done

    record_bundle_file "support-report.md"
}

# ============================================================
# Redaction
# ============================================================

# Collapse PEM/OpenSSH/PGP-style private key blocks in-place. These are
# multiline secrets, so the single-line sed expressions below cannot catch them.
redact_private_key_blocks() {
    local file="$1"
    local tmp_file=""

    tmp_file=$(mktemp "${file}.redacted.XXXXXX") || return 0
    if awk '
        /^[[:space:]]*-----BEGIN [^-]*PRIVATE KEY[^-]*-----[[:space:]]*$/ {
            if (!in_private_key) {
                print "<REDACTED:private_key>"
            }
            in_private_key = 1
            next
        }
        in_private_key && /^[[:space:]]*-----END [^-]*PRIVATE KEY[^-]*-----[[:space:]]*$/ {
            in_private_key = 0
            next
        }
        in_private_key {
            next
        }
        {
            print
        }
    ' "$file" > "$tmp_file" 2>/dev/null; then
        if ! cmp -s "$file" "$tmp_file" 2>/dev/null; then
            mv "$tmp_file" "$file" 2>/dev/null || rm -f "$tmp_file"
        else
            rm -f "$tmp_file"
        fi
    else
        rm -f "$tmp_file"
    fi
}

# Redact sensitive values from a single text file in-place.
# Increments REDACTION_COUNT once when the file content changes.
# Usage: redact_file <file_path>
redact_file() {
    local file="$1"

    # Skip binary files (check first 512 bytes for null bytes)
    # -a forces grep to treat input as text (otherwise it silently skips binary data)
    if head -c 512 "$file" 2>/dev/null | grep -qaP '\x00'; then
        printf '<REDACTED:binary_file>\n' > "$file" 2>/dev/null || return 0
        REDACTION_COUNT=$((REDACTION_COUNT + 1))
        return 0
    fi

    # Count lines before redaction for diff
    local before_hash
    before_hash=$(md5sum "$file" 2>/dev/null | awk '{print $1}') || return 0

    redact_private_key_blocks "$file"

    # Apply redaction patterns using sed -E (extended regex)
    # Order: specific patterns first, then generic catch-alls
    sed -E -i \
        -e 's/sk-[a-zA-Z0-9_-]{20,}/<REDACTED:api_key>/g' \
        -e 's/AKIA[A-Z0-9]{16}/<REDACTED:aws_key>/g' \
        -e 's/gh[pousr]_[a-zA-Z0-9]{36,}/<REDACTED:github_token>/g' \
        -e 's/github_pat_[a-zA-Z0-9_]{22,}/<REDACTED:github_pat>/g' \
        -e 's/hvs\.[a-zA-Z0-9]{20,}/<REDACTED:vault_token>/g' \
        -e 's/xox[bpsar]-[a-zA-Z0-9-]{10,}/<REDACTED:slack_token>/g' \
        -e 's/Bearer [a-zA-Z0-9._\/-]{10,}/Bearer <REDACTED:bearer>/g' \
        -e 's/eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}/<REDACTED:jwt>/g' \
        -e 's#([A-Za-z][A-Za-z0-9+.-]*://)([^/@[:space:]]*):([^/@[:space:]]+)@#\1<REDACTED:credentials>@#g' \
        -e "s/(Generated password for '?[A-Za-z_][A-Za-z0-9._-]*'?[[:space:]]*:[[:space:]]*)[^[:space:]<>]{4,}/\1<REDACTED:password>/g" \
        "$file" 2>/dev/null || return 0

    # JSON-style secrets: "key_name": "value"
    sed -E -i \
        -e 's/"(api_key|API_KEY|ApiKey|api_secret|API_SECRET|secret_key|SECRET_KEY|access_token|ACCESS_TOKEN|refresh_token|REFRESH_TOKEN|auth_token|AUTH_TOKEN|client_secret|CLIENT_SECRET|private_key|PRIVATE_KEY)"[[:space:]]*:[[:space:]]*"([^"]{8,})"/"\1": "<REDACTED:\1>"/g' \
        -e 's/"(password|PASSWORD|passwd|PASSWD)"[[:space:]]*:[[:space:]]*"([^"]{4,})"/"\1": "<REDACTED:password>"/g' \
        -e 's/"([A-Za-z][A-Za-z0-9]*[_-]+[A-Za-z0-9_-]*(password|PASSWORD|passwd|PASSWD))"[[:space:]]*:[[:space:]]*"([^"<>]{4,})"/"\1": "<REDACTED:password>"/g' \
        -e 's/"([A-Za-z][A-Za-z0-9]*[_-]+[A-Za-z0-9_-]*(api[_-]?key|API[_-]?KEY|ApiKey|api[_-]?secret|API[_-]?SECRET|secret[_-]?key|SECRET[_-]?KEY|access[_-]?key|ACCESS[_-]?KEY|access[_-]?token|ACCESS[_-]?TOKEN|refresh[_-]?token|REFRESH[_-]?TOKEN|auth[_-]?token|AUTH[_-]?TOKEN|client[_-]?secret|CLIENT[_-]?SECRET|private[_-]?key|PRIVATE[_-]?KEY|secret|SECRET|token|TOKEN))"[[:space:]]*:[[:space:]]*"([^"<>]{8,})"/"\1": "<REDACTED:generic_secret>"/g' \
        -e 's/"([A-Za-z][A-Za-z0-9]*(Password|Passwd))"[[:space:]]*:[[:space:]]*"([^"<>]{4,})"/"\1": "<REDACTED:password>"/g' \
        -e 's/"([A-Za-z][A-Za-z0-9]*(ApiKey|APIKey|ApiSecret|SecretKey|AccessKey|AccessToken|RefreshToken|AuthToken|ClientSecret|PrivateKey|Secret|Token))"[[:space:]]*:[[:space:]]*"([^"<>]{8,})"/"\1": "<REDACTED:generic_secret>"/g' \
        -e 's/"(body_md|body_text|thread_snippet|message_snippet|mail_snippet|message_preview)"[[:space:]]*:[[:space:]]*"([^"]*)"/"\1": "<REDACTED:message_snippet>"/g' \
        -e 's#"(command|command_line|cmd|cwd|path|project_key|working_directory)"([[:space:]]*:[[:space:]]*")([^"]*)/(home|Users)/[A-Za-z0-9._-]+/[A-Za-z0-9._~+@%/=-]+([^"]*)"#"\1"\2\3/<REDACTED:path>\5"#g' \
        "$file" 2>/dev/null || return 0

    # Shell-style quoted secrets can contain spaces. Redact the full quoted
    # value before the unquoted catch-alls below see only the first word.
    sed -E -i \
        -e 's/(api_key|API_KEY|ApiKey|api_secret|API_SECRET|secret_key|SECRET_KEY|access_token|ACCESS_TOKEN|refresh_token|REFRESH_TOKEN|auth_token|AUTH_TOKEN|client_secret|CLIENT_SECRET|private_key|PRIVATE_KEY)([[:space:]]*[=:][[:space:]]*)"([^"<>]{8,})"/\1\2"<REDACTED:\1>"/g' \
        -e 's/(password|PASSWORD|passwd|PASSWD)([[:space:]]*[=:][[:space:]]*)"([^"<>]{4,})"/\1\2"<REDACTED:password>"/g' \
        -e 's/([A-Za-z][A-Za-z0-9]*[_-]+[A-Za-z0-9_-]*(password|PASSWORD|passwd|PASSWD))([[:space:]]*[=:][[:space:]]*)"([^"<>]{4,})"/\1\3"<REDACTED:password>"/g' \
        -e 's/([A-Za-z][A-Za-z0-9]*[_-]+[A-Za-z0-9_-]*(api[_-]?key|API[_-]?KEY|ApiKey|api[_-]?secret|API[_-]?SECRET|secret[_-]?key|SECRET[_-]?KEY|access[_-]?key|ACCESS[_-]?KEY|access[_-]?token|ACCESS[_-]?TOKEN|refresh[_-]?token|REFRESH[_-]?TOKEN|auth[_-]?token|AUTH[_-]?TOKEN|client[_-]?secret|CLIENT[_-]?SECRET|private[_-]?key|PRIVATE[_-]?KEY|secret|SECRET|token|TOKEN))([[:space:]]*[=:][[:space:]]*)"([^"<>]{8,})"/\1\3"<REDACTED:generic_secret>"/g' \
        -e 's/([A-Za-z][A-Za-z0-9]*(Password|Passwd))([[:space:]]*[=:][[:space:]]*)"([^"<>]{4,})"/\1\3"<REDACTED:password>"/g' \
        -e 's/([A-Za-z][A-Za-z0-9]*(ApiKey|APIKey|ApiSecret|SecretKey|AccessKey|AccessToken|RefreshToken|AuthToken|ClientSecret|PrivateKey|Secret|Token))([[:space:]]*[=:][[:space:]]*)"([^"<>]{8,})"/\1\3"<REDACTED:generic_secret>"/g' \
        "$file" 2>/dev/null || return 0

    sed -E -i \
        -e "s/(api_key|API_KEY|ApiKey|api_secret|API_SECRET|secret_key|SECRET_KEY|access_token|ACCESS_TOKEN|refresh_token|REFRESH_TOKEN|auth_token|AUTH_TOKEN|client_secret|CLIENT_SECRET|private_key|PRIVATE_KEY)([[:space:]]*[=:][[:space:]]*)'([^'<>]{8,})'/\1\2'<REDACTED:\1>'/g" \
        -e "s/(password|PASSWORD|passwd|PASSWD)([[:space:]]*[=:][[:space:]]*)'([^'<>]{4,})'/\1\2'<REDACTED:password>'/g" \
        -e "s/([A-Za-z][A-Za-z0-9]*[_-]+[A-Za-z0-9_-]*(password|PASSWORD|passwd|PASSWD))([[:space:]]*[=:][[:space:]]*)'([^'<>]{4,})'/\1\3'<REDACTED:password>'/g" \
        -e "s/([A-Za-z][A-Za-z0-9]*[_-]+[A-Za-z0-9_-]*(api[_-]?key|API[_-]?KEY|ApiKey|api[_-]?secret|API[_-]?SECRET|secret[_-]?key|SECRET[_-]?KEY|access[_-]?key|ACCESS[_-]?KEY|access[_-]?token|ACCESS[_-]?TOKEN|refresh[_-]?token|REFRESH[_-]?TOKEN|auth[_-]?token|AUTH[_-]?TOKEN|client[_-]?secret|CLIENT[_-]?SECRET|private[_-]?key|PRIVATE[_-]?KEY|secret|SECRET|token|TOKEN))([[:space:]]*[=:][[:space:]]*)'([^'<>]{8,})'/\1\3'<REDACTED:generic_secret>'/g" \
        -e "s/([A-Za-z][A-Za-z0-9]*(Password|Passwd))([[:space:]]*[=:][[:space:]]*)'([^'<>]{4,})'/\1\3'<REDACTED:password>'/g" \
        -e "s/([A-Za-z][A-Za-z0-9]*(ApiKey|APIKey|ApiSecret|SecretKey|AccessKey|AccessToken|RefreshToken|AuthToken|ClientSecret|PrivateKey|Secret|Token))([[:space:]]*[=:][[:space:]]*)'([^'<>]{8,})'/\1\3'<REDACTED:generic_secret>'/g" \
        "$file" 2>/dev/null || return 0

    # Generic key=value secrets (case-insensitive would need per-line processing;
    # instead match common casings)
    sed -E -i \
        -e 's/(api_key|API_KEY|ApiKey|api_secret|API_SECRET|secret_key|SECRET_KEY|access_token|ACCESS_TOKEN|refresh_token|REFRESH_TOKEN|auth_token|AUTH_TOKEN|client_secret|CLIENT_SECRET|private_key|PRIVATE_KEY)([[:space:]]*[=:][[:space:]]*["'"'"']?)([^ "'"'"'<>\n]{8,})/\1\2<REDACTED:\1>/g' \
        -e 's/(password|PASSWORD|passwd|PASSWD)([[:space:]]*[=:][[:space:]]*["'"'"']?)([^ "'"'"'<>\n]{4,})/\1\2<REDACTED:password>/g' \
        -e 's/([A-Za-z][A-Za-z0-9]*[_-]+[A-Za-z0-9_-]*(password|PASSWORD|passwd|PASSWD))([[:space:]]*[=:][[:space:]]*["'"'"']?)([^ "'"'"'<>\n]{4,})/\1\3<REDACTED:password>/g' \
        -e 's/([A-Za-z][A-Za-z0-9]*[_-]+[A-Za-z0-9_-]*(api[_-]?key|API[_-]?KEY|ApiKey|api[_-]?secret|API[_-]?SECRET|secret[_-]?key|SECRET[_-]?KEY|access[_-]?key|ACCESS[_-]?KEY|access[_-]?token|ACCESS[_-]?TOKEN|refresh[_-]?token|REFRESH[_-]?TOKEN|auth[_-]?token|AUTH[_-]?TOKEN|client[_-]?secret|CLIENT[_-]?SECRET|private[_-]?key|PRIVATE[_-]?KEY|secret|SECRET|token|TOKEN))([[:space:]]*[=:][[:space:]]*["'"'"']?)([^ "'"'"'<>\n]{8,})/\1\3<REDACTED:generic_secret>/g' \
        -e 's/([A-Za-z][A-Za-z0-9]*(Password|Passwd))([[:space:]]*[=:][[:space:]]*["'"'"']?)([^ "'"'"'<>\n]{4,})/\1\3<REDACTED:password>/g' \
        -e 's/([A-Za-z][A-Za-z0-9]*(ApiKey|APIKey|ApiSecret|SecretKey|AccessKey|AccessToken|RefreshToken|AuthToken|ClientSecret|PrivateKey|Secret|Token))([[:space:]]*[=:][[:space:]]*["'"'"']?)([^ "'"'"'<>\n]{8,})/\1\3<REDACTED:generic_secret>/g' \
        "$file" 2>/dev/null || return 0

    # Check if file changed
    local after_hash
    after_hash=$(md5sum "$file" 2>/dev/null | awk '{print $1}') || return 0
    if [[ "$before_hash" != "$after_hash" ]]; then
        REDACTION_COUNT=$((REDACTION_COUNT + 1))
    fi
}

# Walk all files in the bundle directory and apply redaction.
# Usage: redact_bundle <bundle_dir>
redact_bundle() {
    local bundle_dir="$1"

    if [[ "$REDACT" != "true" ]]; then
        log_warn "Redaction disabled (--no-redact). Bundle may contain secrets."
        return 0
    fi

    log_detail "Redacting sensitive data..."

    local file_count=0
    while IFS= read -r file; do
        redact_file "$file"
        file_count=$((file_count + 1))
    done < <(find "$bundle_dir" -type f \( \
        -name '*.json' -o -name '*.jsonl' -o -name '*.log' -o -name '*.txt' \
        -o -name '*.yaml' -o -name '*.yml' -o -name '*.sh' \
        -o -name '*.zshrc' -o -name '.zshrc' \
        -o -name 'os-release' -o -name 'VERSION' \
        \) 2>/dev/null)

    if [[ "$VERBOSE" == "true" ]]; then
        log_detail "Scanned $file_count files, redacted $REDACTION_COUNT"
    fi
}

# ============================================================
# Main bundle collection
# ============================================================
main() {
    local parse_status=0

    support_parse_args "$@" || parse_status=$?
    case "$parse_status" in
        0) ;;
        2) return 0 ;;
        *) return "$parse_status" ;;
    esac

    support_initialize_context

    local bundle_name
    bundle_name=$(next_bundle_name)

    local bundle_dir="${OUTPUT_BASE}/${bundle_name}"
    local archive_path="${OUTPUT_BASE}/${bundle_name}.tar.gz"

    # Track collected files for manifest
    BUNDLE_FILES=()

    log_section "ACFS Support Bundle"
    log_step "Collecting diagnostic data..."

    # Create bundle directory
    mkdir -p "$bundle_dir" || {
        log_error "Cannot create bundle directory: $bundle_dir"
        exit 1
    }

    # --- Collect ACFS state files ---
    log_detail "Collecting ACFS state files..."
    if [[ -n "$_SUPPORT_ACFS_HOME" ]]; then
        collect_file "$_SUPPORT_ACFS_HOME/state.json" "$bundle_dir" "state.json" || true
        collect_file "$_SUPPORT_ACFS_HOME/VERSION" "$bundle_dir" "VERSION" || true
        collect_file "$_SUPPORT_ACFS_HOME/checksums.yaml" "$bundle_dir" "checksums.yaml" || true
    fi

    # --- Collect install logs ---
    log_detail "Collecting install logs..."
    local logs_dir=""
    if [[ -n "$_SUPPORT_ACFS_HOME" ]]; then
        logs_dir="$_SUPPORT_ACFS_HOME/logs"
    fi
    if [[ -d "$logs_dir" ]]; then
        mkdir -p "$bundle_dir/logs"
        # Collect recent install logs
        local log_count=0
        while IFS= read -r logfile; do
            collect_file "$logfile" "$bundle_dir" "logs/$(basename "$logfile")" "$(basename "$logfile")" && {
                log_count=$((log_count + 1))
            }
        done < <(find "$logs_dir" -type f -name 'install-*.log' 2>/dev/null | sort -r | head -10)
        [[ "$VERBOSE" == "true" ]] && log_detail "Collected $log_count log files"
    fi

    # --- Collect install summary JSONs ---
    if [[ -d "$logs_dir" ]]; then
        while IFS= read -r summary; do
            collect_file "$summary" "$bundle_dir" "logs/$(basename "$summary")" "$(basename "$summary")" || true
        done < <(find "$logs_dir" -type f -name 'install_summary_*.json' 2>/dev/null | sort -r | head -5)
    fi

    # --- Collect performance budget JSONs ---
    if [[ -d "$logs_dir" ]]; then
        while IFS= read -r budget; do
            collect_file "$budget" "$bundle_dir" "logs/$(basename "$budget")" "$(basename "$budget")" || true
        done < <(find "$logs_dir" -type f -name 'performance_budget_*.json' 2>/dev/null | sort -r | head -5)
    fi

    # --- Capture doctor JSON ---
    log_detail "Running health checks..."
    capture_doctor_json "$bundle_dir" || true
    capture_checkpoint_summary_json "$bundle_dir" || true
    capture_local_progress_json "$bundle_dir" || true
    capture_swarm_status_json "$bundle_dir" || true
    capture_provenance_json "$bundle_dir" || true
    capture_resource_profile_json "$bundle_dir" || true
    capture_swarm_inventory_json "$bundle_dir" || true
    capture_swarm_timeline_json "$bundle_dir" || true

    # --- Capture versions ---
    log_detail "Collecting tool versions..."
    capture_versions "$bundle_dir" || true

    # --- Capture environment ---
    log_detail "Collecting environment info..."
    capture_env_summary "$bundle_dir" || true

    # --- Collect system info ---
    log_detail "Collecting system info..."
    if [[ -f /etc/os-release ]]; then
        collect_file "/etc/os-release" "$bundle_dir" "os-release" || true
    fi

    # Systemd journal (last 100 acfs-related lines)
    if command -v journalctl &>/dev/null; then
        local journal_tmp=""
        journal_tmp=$(mktemp "${bundle_dir}/journal-acfs.log.tmp.XXXXXX") || journal_tmp=""
        if [[ -n "$journal_tmp" ]] && journalctl --no-pager -n 100 -u 'acfs*' > "$journal_tmp" 2>/dev/null; then
            if mv "$journal_tmp" "$bundle_dir/journal-acfs.log"; then
                record_bundle_file "journal-acfs.log"
            else
                log_warn "Could not finalize journal capture"
                rm -f "$journal_tmp"
            fi
        else
            [[ -n "$journal_tmp" ]] && rm -f "$journal_tmp"
        fi
    fi

    # --- Collect configuration ---
    log_detail "Collecting configuration..."
    collect_file "${SUPPORT_TARGET_HOME}/.zshrc" "$bundle_dir" "config/.zshrc" ".zshrc" || true
    if [[ -n "$_SUPPORT_ACFS_HOME" ]]; then
        collect_file "$_SUPPORT_ACFS_HOME/acfs.manifest.yaml" "$bundle_dir" "config/acfs.manifest.yaml" "acfs.manifest.yaml" || true
    fi

    # --- Redact sensitive data ---
    redact_bundle "$bundle_dir"

    # --- Write manifest ---
    log_detail "Writing manifest..."
    write_manifest "$bundle_dir"
    log_detail "Writing support report..."
    write_support_report_index "$bundle_dir" || true
    write_manifest "$bundle_dir"

    # --- Create tar archive ---
    log_detail "Creating archive..."
    if tar -czf "$archive_path" -C "$OUTPUT_BASE" "$bundle_name" 2>/dev/null; then
        log_success "Bundle created: $archive_path"
        echo "$archive_path"
    else
        log_warn "Could not create tar archive, bundle available at: $bundle_dir"
        echo "$bundle_dir"
    fi
}

support_restore_shell_options_if_sourced() {
    [[ "$_SUPPORT_WAS_SOURCED" == "true" ]] || return 0

    if [[ "$_SUPPORT_ORIGINAL_HOME_WAS_SET" == "true" ]]; then
        HOME="$_SUPPORT_ORIGINAL_HOME"
        export HOME
    else
        unset HOME
    fi

    [[ "$_SUPPORT_RESTORE_ERREXIT" == "true" ]] || set +e
    [[ "$_SUPPORT_RESTORE_NOUNSET" == "true" ]] || set +u
    [[ "$_SUPPORT_RESTORE_PIPEFAIL" == "true" ]] || set +o pipefail
}

support_restore_shell_options_if_sourced

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
