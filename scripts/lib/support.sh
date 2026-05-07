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

# ============================================================
# Configuration
# ============================================================
VERBOSE=false
REDACT=true
OUTPUT_BASE=""
OUTPUT_BASE_EXPLICIT=false
REDACTION_COUNT=0
DOCTOR_TIMEOUT="${SUPPORT_BUNDLE_DOCTOR_TIMEOUT:-120}"
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
                patterns: ["api_key", "aws_key", "github_token", "github_pat", "vault_token", "slack_token", "bearer", "jwt", "password", "generic_secret"]
            }
        }' > "$manifest_file" 2>/dev/null || return 1
}

# ============================================================
# Redaction
# ============================================================

# Redact sensitive values from a single text file in-place.
# Increments REDACTION_COUNT once when the file content changes.
# Usage: redact_file <file_path>
redact_file() {
    local file="$1"

    # Skip binary files (check first 512 bytes for null bytes)
    # -a forces grep to treat input as text (otherwise it silently skips binary data)
    if head -c 512 "$file" 2>/dev/null | grep -qaP '\x00'; then
        return 0
    fi

    # Count lines before redaction for diff
    local before_hash
    before_hash=$(md5sum "$file" 2>/dev/null | awk '{print $1}') || return 0

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

    # --- Capture doctor JSON ---
    log_detail "Running health checks..."
    capture_doctor_json "$bundle_dir" || true

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
