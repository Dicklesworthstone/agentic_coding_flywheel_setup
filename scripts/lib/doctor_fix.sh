#!/usr/bin/env bash
# ============================================================
# ACFS Doctor --fix Implementation
# Safe, deterministic fixers with logging and undo capability
#
# Implements bd-31ps.6.2 based on spec in doctor_fix_spec.md
# ============================================================

# Prevent multiple sourcing
[[ -n "${_ACFS_DOCTOR_FIX_LOADED:-}" ]] && return 0
_ACFS_DOCTOR_FIX_LOADED=1

doctor_fix_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

doctor_fix_systemd_unit_reject_line_breaks() {
    local value="${1:-}"
    [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]]
}

doctor_fix_systemd_unit_path_escape() {
    local value="${1:-}"
    local tab=$'\t'

    doctor_fix_systemd_unit_reject_line_breaks "$value" || return 1
    value="${value//\\/\\\\}"
    value="${value//%/%%}"
    value="${value// /\\s}"
    value="${value//$tab/\\t}"
    printf '%s\n' "$value"
}

doctor_fix_systemd_unit_quote() {
    local value="${1:-}"
    local escape_dollar="${2:-false}"

    doctor_fix_systemd_unit_reject_line_breaks "$value" || return 1
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//%/%%}"
    if [[ "$escape_dollar" == "true" ]]; then
        value="${value//\$/\$\$}"
    fi
    printf '"%s"\n' "$value"
}

doctor_fix_systemd_unit_exec_arg() {
    doctor_fix_systemd_unit_quote "${1:-}" true
}

doctor_fix_systemd_unit_exec_command() {
    doctor_fix_systemd_unit_quote "${1:-}" false
}

doctor_fix_systemd_unit_env_assignment() {
    local name="${1:-}"
    local value="${2:-}"

    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
    doctor_fix_systemd_unit_quote "${name}=${value}" false
}

doctor_fix_is_valid_username() {
    local username="${1:-}"
    [[ "$username" =~ ^[a-z_][a-z0-9._-]*$ ]]
}

doctor_fix_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1

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

doctor_fix_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(doctor_fix_system_binary_path getent 2>/dev/null || true)"
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

doctor_fix_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(doctor_fix_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(doctor_fix_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

doctor_fix_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    passwd_home="$(doctor_fix_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
    [[ -n "$passwd_home" ]] || return 1
    printf '%s\n' "$passwd_home"
}

doctor_fix_resolve_home_for_user() {
    local user="${1:-}"
    local home_candidate=""
    local passwd_entry=""

    doctor_fix_is_valid_username "$user" || [[ "$user" == "root" ]] || return 1

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    passwd_entry="$(doctor_fix_getent_passwd_entry "$user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        home_candidate="$(doctor_fix_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
        if [[ -n "$home_candidate" ]]; then
            printf '%s\n' "$home_candidate"
            return 0
        fi
    fi

    return 1
}

doctor_fix_validate_bin_dir_for_home() {
    local bin_dir="${1:-}"
    local base_home="${2:-}"
    local passwd_line=""
    local passwd_home=""
    local hinted_home=""

    bin_dir="$(doctor_fix_sanitize_abs_nonroot_path "$bin_dir" 2>/dev/null || true)"
    [[ -n "$bin_dir" ]] || return 1
    base_home="$(doctor_fix_sanitize_abs_nonroot_path "$base_home" 2>/dev/null || true)"

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
    hinted_home="$(doctor_fix_sanitize_abs_nonroot_path "$hinted_home" 2>/dev/null || true)"
    if [[ -n "$hinted_home" ]] && [[ -n "$base_home" ]] && [[ "$hinted_home" != "$base_home" ]]; then
        return 1
    fi

    while IFS= read -r passwd_line; do
        passwd_home="$(doctor_fix_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
        [[ -n "$passwd_home" ]] || continue
        [[ -n "$base_home" && "$passwd_home" == "$base_home" ]] && continue
        if [[ "$bin_dir" == "$passwd_home" || "$bin_dir" == "$passwd_home/"* ]]; then
            return 1
        fi
    done < <(doctor_fix_getent_passwd_entry 2>/dev/null || true)

    printf '%s\n' "$bin_dir"
}

doctor_fix_resolve_current_home() {
    local current_user=""
    local home_candidate=""
    local passwd_home=""

    home_candidate="$(doctor_fix_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"

    current_user="$(doctor_fix_current_user 2>/dev/null || true)"
    if [[ -n "$current_user" ]]; then
        passwd_home="$(doctor_fix_resolve_home_for_user "$current_user" 2>/dev/null || true)"
        if [[ -n "$passwd_home" ]]; then
            printf '%s\n' "$passwd_home"
            return 0
        fi
    fi

    [[ -n "$home_candidate" ]] || return 1
    printf '%s\n' "$home_candidate"
}

doctor_fix_runtime_home() {
    local target_user_raw="${TARGET_USER:-}"
    local current_user=""
    local explicit_home=""
    local resolved_home=""

    explicit_home="$(doctor_fix_sanitize_abs_nonroot_path "${TARGET_HOME:-}" 2>/dev/null || true)"

    if [[ -n "$target_user_raw" ]]; then
        doctor_fix_is_valid_username "$target_user_raw" || return 1

        resolved_home="$(doctor_fix_resolve_home_for_user "$target_user_raw" 2>/dev/null || true)"
        if [[ -n "$resolved_home" ]]; then
            printf '%s\n' "${resolved_home%/}"
            return 0
        fi

        current_user="$(doctor_fix_current_user 2>/dev/null || true)"
        if [[ -z "$current_user" ]] || [[ "$target_user_raw" != "$current_user" ]]; then
            return 1
        fi
    fi

    if [[ -n "$explicit_home" ]]; then
        printf '%s\n' "${explicit_home%/}"
        return 0
    fi

    resolved_home="$(doctor_fix_resolve_current_home 2>/dev/null || true)"
    [[ -n "$resolved_home" ]] || return 1
    printf '%s\n' "${resolved_home%/}"
}

doctor_fix_runtime_acfs_home() {
    local runtime_home=""
    local resolved_acfs_home=""

    runtime_home="$(doctor_fix_runtime_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 1
    resolved_acfs_home="$(doctor_fix_sanitize_abs_nonroot_path "${ACFS_HOME:-}" 2>/dev/null || true)"

    if [[ -n "${TARGET_HOME:-}" ]] || [[ -n "${TARGET_USER:-}" ]]; then
        printf '%s/.acfs\n' "$runtime_home"
        return 0
    fi

    if [[ "$resolved_acfs_home" == "$runtime_home/.acfs" ]]; then
        printf '%s\n' "$resolved_acfs_home"
        return 0
    fi

    if [[ -n "$resolved_acfs_home" ]]; then
        printf '%s\n' "$resolved_acfs_home"
        return 0
    fi

    printf '%s/.acfs\n' "$runtime_home"
}

doctor_fix_runtime_user() {
    local runtime_user=""

    if [[ -n "${TARGET_USER:-}" ]]; then
        printf '%s\n' "$TARGET_USER"
        return 0
    fi

    runtime_user="$(doctor_fix_current_user 2>/dev/null || true)"
    if [[ -n "$runtime_user" ]]; then
        printf '%s\n' "$runtime_user"
        return 0
    fi

    printf 'ubuntu\n'
}

doctor_fix_runtime_bin_dir() {
    local runtime_home=""
    local configured_bin=""

    runtime_home="$(doctor_fix_runtime_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 1

    configured_bin="$(doctor_fix_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$runtime_home" 2>/dev/null || true)"
    if [[ -n "$configured_bin" ]]; then
        printf '%s\n' "$configured_bin"
        return 0
    fi

    printf '%s/.local/bin\n' "$runtime_home"
}

doctor_fix_binary_path() {
    local tool="$1"
    local runtime_home=""
    local primary_bin=""
    local candidate=""

    [[ -n "$tool" ]] || return 1

    runtime_home="$(doctor_fix_runtime_home)"
    [[ -n "$runtime_home" ]] || return 1

    primary_bin="$(doctor_fix_runtime_bin_dir)"
    for candidate in \
        "$primary_bin/$tool" \
        "$runtime_home/.local/bin/$tool" \
        "$runtime_home/.acfs/bin/$tool" \
        "$runtime_home/.cargo/bin/$tool" \
        "$runtime_home/.bun/bin/$tool" \
        "$runtime_home/.atuin/bin/$tool" \
        "$runtime_home/go/bin/$tool" \
        "$runtime_home/bin/$tool" \
        "/usr/local/go/bin/$tool" \
        "/usr/local/bin/$tool" \
        "/usr/bin/$tool" \
        "/bin/$tool" \
        "/usr/local/sbin/$tool" \
        "/usr/sbin/$tool" \
        "/sbin/$tool" \
        "/snap/bin/$tool"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

doctor_fix_runtime_path() {
    local runtime_home=""
    local primary_bin=""
    local current_path=""
    local system_path_prefix="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"

    runtime_home="$(doctor_fix_runtime_home)"
    [[ -n "$runtime_home" ]] || return 1

    primary_bin="$(doctor_fix_runtime_bin_dir)"
    current_path="${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"

    printf '%s\n' "$primary_bin:$runtime_home/.local/bin:$runtime_home/.acfs/bin:$runtime_home/.cargo/bin:$runtime_home/.bun/bin:$runtime_home/.atuin/bin:$runtime_home/go/bin:$runtime_home/google-cloud-sdk/bin:$system_path_prefix:$current_path"
}

doctor_fix_curl() {
    local curl_bin=""

    curl_bin="$(doctor_fix_binary_path curl 2>/dev/null || true)"
    [[ -n "$curl_bin" ]] || return 127

    "$curl_bin" "$@"
}

doctor_fix_stack_agent_mail_helpers_loaded() {
    declare -f _stack_agent_mail_cli_path >/dev/null 2>&1 \
        && declare -f _stack_repair_agent_mail_cli_symlink >/dev/null 2>&1 \
        && declare -f _stack_configure_agent_mail_service >/dev/null 2>&1 \
        && declare -f _stack_wait_for_agent_mail_health >/dev/null 2>&1
}

doctor_fix_clear_stack_agent_mail_helpers() {
    unset -f _stack_agent_mail_cli_path \
        _stack_repair_agent_mail_cli_symlink \
        _stack_configure_agent_mail_service \
        _stack_wait_for_agent_mail_health 2>/dev/null || true
}

doctor_fix_source_stack_lib() {
    local runtime_stack_lib=""
    local repo_stack_lib=""
    local candidate=""
    local -a candidates=()

    if doctor_fix_stack_agent_mail_helpers_loaded; then
        return 0
    fi

    candidates+=("$SCRIPT_DIR/stack.sh")

    runtime_stack_lib="$(doctor_fix_runtime_acfs_home)/scripts/lib/stack.sh"
    if [[ -n "${ACFS_REPO_ROOT:-}" ]]; then
        repo_stack_lib="${ACFS_REPO_ROOT%/}/scripts/lib/stack.sh"
    fi
    candidates+=(
        "$runtime_stack_lib"
        "$repo_stack_lib"
        "/data/projects/agentic_coding_flywheel_setup/scripts/lib/stack.sh"
        "/dp/agentic_coding_flywheel_setup/scripts/lib/stack.sh"
    )

    for candidate in "${candidates[@]}"; do
        [[ -n "$candidate" && -f "$candidate" ]] || continue
        doctor_fix_clear_stack_agent_mail_helpers
        # shellcheck source=stack.sh
        if source "$candidate" && doctor_fix_stack_agent_mail_helpers_loaded; then
            return 0
        fi
    done

    doctor_fix_clear_stack_agent_mail_helpers
    return 1
}

doctor_fix_log_file_path() {
    if [[ -n "${DOCTOR_FIX_LOG:-}" ]]; then
        printf '%s\n' "$DOCTOR_FIX_LOG"
        return 0
    fi

    printf '%s/.local/share/acfs/doctor.log\n' "$(doctor_fix_runtime_home)"
}

# Seed autofix state paths from the resolved ACFS home before sourcing
# autofix.sh so direct root-home-mismatch invocations do not record changes in
# the caller HOME by accident.
if [[ -z "${ACFS_STATE_DIR:-}" ]]; then
    ACFS_STATE_DIR="$(doctor_fix_runtime_acfs_home)/autofix"
fi
ACFS_CHANGES_FILE="${ACFS_CHANGES_FILE:-${ACFS_STATE_DIR}/changes.jsonl}"
ACFS_UNDOS_FILE="${ACFS_UNDOS_FILE:-${ACFS_STATE_DIR}/undos.jsonl}"
ACFS_BACKUPS_DIR="${ACFS_BACKUPS_DIR:-${ACFS_STATE_DIR}/backups}"
ACFS_LOCK_FILE="${ACFS_LOCK_FILE:-${ACFS_STATE_DIR}/.lock}"
ACFS_INTEGRITY_FILE="${ACFS_INTEGRITY_FILE:-${ACFS_STATE_DIR}/.integrity}"
export ACFS_STATE_DIR ACFS_CHANGES_FILE ACFS_UNDOS_FILE ACFS_BACKUPS_DIR ACFS_LOCK_FILE ACFS_INTEGRITY_FILE

# Source autofix library for change tracking
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [[ -f "$SCRIPT_DIR/autofix.sh" ]]; then
    # shellcheck source=autofix.sh
    source "$SCRIPT_DIR/autofix.sh"
elif [[ -f "$(doctor_fix_runtime_acfs_home)/scripts/lib/autofix.sh" ]]; then
    # shellcheck source=autofix.sh
    source "$(doctor_fix_runtime_acfs_home)/scripts/lib/autofix.sh"
fi

# ============================================================
# Configuration
# ============================================================

DOCTOR_FIX_LOG="${DOCTOR_FIX_LOG:-}"
DOCTOR_FIX_DRY_RUN=false
DOCTOR_FIX_YES=false
DOCTOR_FIX_PROMPT=false

# Counters for fix summary
declare -g FIX_APPLIED=0
declare -g FIX_SKIPPED=0
declare -g FIX_FAILED=0
declare -g FIX_MANUAL=0

# Arrays to track fixes for summary
declare -ga FIXES_APPLIED=()
declare -ga FIXES_DRY_RUN=()
declare -ga FIXES_MANUAL=()
declare -ga FIXES_PROMPTED=()

# ============================================================
# Logging Helpers
# ============================================================

doctor_fix_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    local log_file=""
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    log_file="$(doctor_fix_log_file_path)"

    # Ensure log directory exists
    mkdir -p "$(dirname "$log_file")"

    # Log to file
    echo "[$timestamp] [$level] $message" >> "$log_file"

    # Output to user
    case "$level" in
        INFO)  echo "  [fix] $message" ;;
        WARN)  echo "  [fix] WARNING: $message" >&2 ;;
        ERROR) echo "  [fix] ERROR: $message" >&2 ;;
        DRY)   echo "  [dry-run] Would: $message" ;;
    esac
}

# ============================================================
# Guard Helpers
# ============================================================

# Check if a file contains a specific line
file_contains_line() {
    local file="$1"
    local pattern="$2"

    [[ -f "$file" ]] && grep -qF "$pattern" "$file" 2>/dev/null
}

file_contains_exact_line() {
    local file="$1"
    local line="$2"

    [[ -f "$file" ]] && grep -Fxq "$line" "$file" 2>/dev/null
}

doctor_fix_sed_literal() {
    # This helper builds a basic-regex pattern for sed, not an extended regex.
    # Escaping literal parentheses would turn them into BRE capture groups and
    # make managed-marker removal miss lines like "(added by doctor --fix)".
    printf '%s' "$1" | sed 's/[][\\.^$*|]/\\&/g'
}

doctor_fix_remove_exact_line_and_next() {
    local file="$1"
    local line="$2"
    local escaped_line=""

    [[ -f "$file" ]] || return 1
    escaped_line="$(doctor_fix_sed_literal "$line")"
    sed -i "\\|^${escaped_line}$|,+1d" "$file"
}

doctor_fix_file_has_active_acfs_zshrc_source() {
    local file="${1:-}"

    [[ -f "$file" ]] || return 1
    awk '
        /^[[:space:]]*#/ { next }
        /(^|[[:space:];&|])(source|\.)[[:space:]]+.*\.acfs\/zsh\/acfs\.zshrc/ { found=1; exit }
        END { exit(found ? 0 : 1) }
    ' "$file" 2>/dev/null
}

# Check if directory is in PATH
dir_in_path() {
    local dir="$1"
    case ":$PATH:" in
        *":$dir:"*) return 0 ;;
        *) return 1 ;;
    esac
}

doctor_fix_nearest_existing_parent() {
    local path="${1:-}"
    path="$(dirname "$path")"

    while [[ "$path" != "/" && ! -d "$path" ]]; do
        path="$(dirname "$path")"
    done

    printf '%s\n' "$path"
}

doctor_fix_build_remove_path_rollback() {
    local target_path="${1:-}"
    local existing_parent="${2:-}"
    local target_parent=""
    local rollback_command=""

    target_parent="$(dirname "$target_path")"
    if [[ -z "$existing_parent" || "$existing_parent" == "$target_parent" ]]; then
        printf -v rollback_command 'rm -f %q' "$target_path"
        printf '%s\n' "$rollback_command"
        return 0
    fi

    printf -v rollback_command \
        'rm -f %q; cleanup_dir=%q; stop_dir=%q; while [[ "$cleanup_dir" != "$stop_dir" ]]; do rmdir "$cleanup_dir" 2>/dev/null || break; cleanup_dir=$(dirname "$cleanup_dir"); done' \
        "$target_path" "$target_parent" "$existing_parent"
    printf '%s\n' "$rollback_command"
}

doctor_fix_build_remove_tree_rollback() {
    local target_path="${1:-}"
    local existing_parent="${2:-}"
    local target_parent=""
    local rollback_command=""

    target_parent="$(dirname "$target_path")"
    if [[ -z "$existing_parent" || "$existing_parent" == "$target_parent" ]]; then
        printf -v rollback_command 'rm -rf %q' "$target_path"
        printf '%s\n' "$rollback_command"
        return 0
    fi

    printf -v rollback_command \
        'rm -rf %q; cleanup_dir=%q; stop_dir=%q; while [[ "$cleanup_dir" != "$stop_dir" ]]; do rmdir "$cleanup_dir" 2>/dev/null || break; cleanup_dir=$(dirname "$cleanup_dir"); done' \
        "$target_path" "$target_parent" "$existing_parent"
    printf '%s\n' "$rollback_command"
}

doctor_fix_build_remove_binary_rollback() {
    local target_path="${1:-}"
    local rollback_command=""

    [[ -n "$target_path" ]] || return 1
    printf -v rollback_command 'rm -f %q' "$target_path"
    printf '%s\n' "$rollback_command"
}

doctor_fix_run_rollback_command() {
    local rollback_command="$1"
    local requires_root="${2:-false}"
    local -a sudo_cmd=()

    [[ -n "$rollback_command" ]] || return 1

    if [[ "$requires_root" == "true" ]]; then
        [[ $EUID -ne 0 ]] && command -v sudo &>/dev/null && sudo_cmd=(sudo -n)
        if [[ $EUID -ne 0 && ${#sudo_cmd[@]} -eq 0 ]]; then
            doctor_fix_log ERROR "Rollback requires root but sudo is unavailable"
            return 1
        fi
    fi

    if [[ ${#sudo_cmd[@]} -gt 0 ]]; then
        "${sudo_cmd[@]}" bash -c "$rollback_command"
    else
        bash -c "$rollback_command"
    fi
}

doctor_fix_record_change_or_rollback() {
    local rollback_command="$1"
    local rollback_requires_root="${2:-false}"
    shift 2

    local description="${2:-change}"

    if record_change "$@" >/dev/null; then
        return 0
    fi

    doctor_fix_log ERROR "Failed to record change: $description"
    if [[ -n "$rollback_command" ]]; then
        if ! doctor_fix_run_rollback_command "$rollback_command" "$rollback_requires_root"; then
            doctor_fix_log ERROR "Failed to roll back after journaling failure: $description"
        fi
    fi

    return 1
}

doctor_fix_files_json() {
    autofix_files_json "$@"
}

doctor_fix_require_security() {
    if [[ "${DOCTOR_FIX_SECURITY_READY:-false}" == "true" ]]; then
        return 0
    fi

    local security_script="$SCRIPT_DIR/security.sh"
    if [[ ! -r "$security_script" ]]; then
        security_script="$(doctor_fix_runtime_acfs_home)/scripts/lib/security.sh"
    fi

    if [[ ! -r "$security_script" ]]; then
        doctor_fix_log WARN "security.sh not available; cannot verify upstream installer scripts"
        return 1
    fi

    # shellcheck source=security.sh
    source "$security_script" || return 1
    if ! load_checksums >/dev/null 2>&1; then
        doctor_fix_log WARN "checksums.yaml not available; refusing to run unverified installer scripts"
        return 1
    fi

    DOCTOR_FIX_SECURITY_READY=true
    return 0
}

doctor_fix_run_verified_installer() {
    local tool="$1"
    shift
    local ms_arch=""
    ms_arch="$(uname -m 2>/dev/null || true)"

    if [[ "$tool" == "ms" ]] && [[ "$(uname -s 2>/dev/null)" == "Linux" ]] && [[ "$ms_arch" == "aarch64" || "$ms_arch" == "arm64" ]]; then
        local cargo_bin=""
        local runtime_home=""
        local runtime_path=""

        cargo_bin="$(doctor_fix_binary_path cargo 2>/dev/null || true)"
        runtime_home="$(doctor_fix_runtime_home)"
        runtime_path="$(doctor_fix_runtime_path 2>/dev/null || true)"
        if [[ -z "$cargo_bin" || -z "$runtime_home" || -z "$runtime_path" ]]; then
            doctor_fix_log WARN "meta_skill ARM64 Linux fallback requires cargo for the runtime home"
            return 1
        fi

        doctor_fix_log INFO "meta_skill: Linux ARM64 detected, rebuilding from source via cargo"
        env HOME="$runtime_home" PATH="$runtime_path" "$cargo_bin" install --git https://github.com/Dicklesworthstone/meta_skill --force
        return $?
    fi

    if ! doctor_fix_require_security; then
        return 1
    fi

    local url="${KNOWN_INSTALLERS[$tool]:-}"
    local expected_sha256=""
    expected_sha256="$(get_checksum "$tool")"

    if [[ -z "$url" || -z "$expected_sha256" ]]; then
        doctor_fix_log WARN "Missing verified installer metadata for $tool"
        return 1
    fi

    fetch_and_run "$url" "$expected_sha256" "$tool" "$@"
}

# ============================================================
# Fixer: PATH Ordering (fix.path.ordering)
# ============================================================

# Fix PATH ordering in shell config
# Ensures ~/.local/bin and other ACFS dirs are at front of PATH
fix_path_ordering() {
    local check_id="$1"
    local runtime_home=""
    runtime_home="$(doctor_fix_runtime_home)"
    local target_file="${runtime_home}/.zshrc"

    # Required directories in order
    local -a path_dirs=(
        '$HOME/.local/bin'
        '$HOME/.bun/bin'
        '$HOME/.cargo/bin'
        '$HOME/go/bin'
        '$HOME/.atuin/bin'
    )

    # Build the export line
    local path_string
    path_string=$(IFS=:; echo "${path_dirs[*]}")
    local export_line="export PATH=\"${path_string}:\$PATH\""
    local marker="# ACFS PATH ordering (added by doctor --fix)"
    local marker_present=false

    # Guard: the marker alone is not enough; older fixes may lack newer paths.
    if file_contains_exact_line "$target_file" "$marker" &&
       file_contains_exact_line "$target_file" "$export_line"; then
        doctor_fix_log INFO "PATH ordering already configured in $target_file"
        return 0
    fi
    if file_contains_exact_line "$target_file" "$marker"; then
        marker_present=true
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.path.ordering|Prepend PATH directories to $target_file|$target_file|$export_line")
        doctor_fix_log DRY "Prepend PATH directories to $target_file"
        return 0
    fi

    # Create backup
    local backup_json=""
    local restore_command=""
    if [[ -f "$target_file" ]]; then
        backup_json=$(create_backup "$target_file" "path-ordering")
        restore_command="$(autofix_backup_restore_command "$backup_json" 2>/dev/null || true)"
    else
        restore_command="if [[ -f '$target_file' ]]; then sed -i '/$marker/,+1d' '$target_file' && if ! grep -q '[^[:space:]]' '$target_file'; then rm -f '$target_file'; fi; fi"
    fi

    if [[ "$marker_present" == "true" ]]; then
        if ! doctor_fix_remove_exact_line_and_next "$target_file" "$marker"; then
            doctor_fix_log ERROR "Failed to remove stale PATH ordering block from $target_file"
            if [[ -n "$restore_command" ]]; then
                doctor_fix_run_rollback_command "$restore_command" false || true
            fi
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi
    fi

    # Apply fix
    if ! {
        echo ""
        echo "$marker"
        echo "$export_line"
    } >> "$target_file"; then
        doctor_fix_log ERROR "Failed to append PATH ordering to $target_file"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Record change
    if ! doctor_fix_record_change_or_rollback \
        "${restore_command:-if [[ -f '$target_file' ]]; then sed -i '/$marker/,+1d' '$target_file'; fi}" \
        false \
        "path" "Added PATH ordering to $target_file" \
        "${restore_command:-if [[ -f '$target_file' ]]; then sed -i '/$marker/,+1d' '$target_file'; fi}" \
        false "info" "$(doctor_fix_files_json "$target_file")" "$(echo "${backup_json:-[]}" | jq -c 'if type == \"object\" then [.] else . end' 2>/dev/null || echo '[]')" "[]"; then
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    doctor_fix_log INFO "Added PATH ordering to $target_file"
    FIXES_APPLIED+=("fix.path.ordering|Added PATH ordering to $target_file")
    FIX_APPLIED=$((FIX_APPLIED + 1))

    return 0
}

# ============================================================
# Fixer: Config Copy (fix.config.copy)
# ============================================================

# Copy missing ACFS config files
fix_config_copy() {
    local check_id="$1"
    local src="$2"
    local dest="$3"
    local dest_parent=""
    local existing_parent=""
    local rollback_command=""

    # Guard: Source must exist
    if [[ ! -f "$src" ]]; then
        doctor_fix_log WARN "Source config not found: $src"
        return 1
    fi

    # Guard: Dest must not exist
    if [[ -f "$dest" ]]; then
        doctor_fix_log INFO "Config already exists: $dest"
        return 0
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.config.copy|Copy $(basename "$src") to $dest|$dest|cp -p $src $dest")
        doctor_fix_log DRY "Copy $(basename "$src") to $dest"
        return 0
    fi

    dest_parent="$(dirname "$dest")"
    existing_parent="$(doctor_fix_nearest_existing_parent "$dest")"
    rollback_command="$(doctor_fix_build_remove_path_rollback "$dest" "$existing_parent")"

    # Ensure parent directory exists
    if ! mkdir -p "$dest_parent"; then
        doctor_fix_log ERROR "Failed to create config destination directory: $dest_parent"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Copy file
    if ! cp -p "$src" "$dest"; then
        if ! doctor_fix_run_rollback_command "$rollback_command" false; then
            doctor_fix_log ERROR "Failed to clean copied-config destination after copy failure: $dest"
        fi
        doctor_fix_log ERROR "Failed to copy $(basename "$src") to $dest"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Record change
    if ! doctor_fix_record_change_or_rollback \
        "$rollback_command" \
        false \
        "config" "Copied config: $(basename "$src")" \
        "$rollback_command" \
        false "info" "$(doctor_fix_files_json "$dest")" "[]" "[]"; then
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    doctor_fix_log INFO "Copied $(basename "$src") to $dest"
    FIXES_APPLIED+=("fix.config.copy|Copied $(basename "$src") to $dest")
    FIX_APPLIED=$((FIX_APPLIED + 1))

    return 0
}

# ============================================================
# Fixer: DCG Hook (fix.dcg.hook)
# ============================================================

dcg_hook_already_installed() {
    local doctor_json=""
    local dcg_bin=""
    local runtime_home=""
    local runtime_path=""

    dcg_bin="$(doctor_fix_binary_path dcg 2>/dev/null || true)"
    runtime_home="$(doctor_fix_runtime_home)"
    runtime_path="$(doctor_fix_runtime_path 2>/dev/null || true)"
    [[ -n "$dcg_bin" && -n "$runtime_home" && -n "$runtime_path" ]] || return 1

    doctor_json="$(env HOME="$runtime_home" PATH="$runtime_path" "$dcg_bin" doctor --format json 2>/dev/null)" || return 1
    [[ -n "$doctor_json" ]] || return 1

    if command -v jq &>/dev/null; then
        printf '%s' "$doctor_json" | jq -e '
            (.hook_installed == true) or
            any(.checks[]?; .id == "hook_wiring" and .status == "ok")
        ' >/dev/null 2>&1
        return $?
    fi

    printf '%s' "$doctor_json" | grep -q '"hook_installed"[[:space:]]*:[[:space:]]*true' && return 0
    printf '%s' "$doctor_json" | grep -Eq '"id"[[:space:]]*:[[:space:]]*"hook_wiring".*"status"[[:space:]]*:[[:space:]]*"ok"' && return 0
    return 1
}

# Install DCG pre-tool-use hook
fix_dcg_hook() {
    local check_id="$1"
    local dcg_bin=""
    local runtime_home=""
    local runtime_path=""
    local dcg_uninstall_cmd=""

    dcg_bin="$(doctor_fix_binary_path dcg 2>/dev/null || true)"
    runtime_home="$(doctor_fix_runtime_home)"
    runtime_path="$(doctor_fix_runtime_path 2>/dev/null || true)"

    # Guard: dcg command must exist
    if [[ -z "$dcg_bin" || -z "$runtime_home" || -z "$runtime_path" ]]; then
        doctor_fix_log WARN "DCG not installed for the runtime home, cannot fix hook"
        return 1
    fi

    dcg_uninstall_cmd="env HOME=$(printf '%q' "$runtime_home") PATH=$(printf '%q' "$runtime_path") $(printf '%q' "$dcg_bin") uninstall"

    # Guard: Check if already installed
    if dcg_hook_already_installed; then
        doctor_fix_log INFO "DCG hook already installed"
        return 0
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.dcg.hook|Install DCG pre-tool-use hook|~/.config/claude-code|dcg install")
        doctor_fix_log DRY "Install DCG pre-tool-use hook"
        return 0
    fi

    # Install hook
    if env HOME="$runtime_home" PATH="$runtime_path" "$dcg_bin" install 2>/dev/null; then
        if ! doctor_fix_record_change_or_rollback \
            "$dcg_uninstall_cmd" \
            false \
            "hook" "Installed DCG pre-tool-use hook" \
            "$dcg_uninstall_cmd" \
            false "info" "[]" "[]" "[]"; then
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi

        doctor_fix_log INFO "Installed DCG pre-tool-use hook"
        FIXES_APPLIED+=("fix.dcg.hook|Installed DCG pre-tool-use hook")
        FIX_APPLIED=$((FIX_APPLIED + 1))
        return 0
    else
        doctor_fix_log ERROR "Failed to install DCG hook"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
}

# ============================================================
# Fixer: Symlink Create (fix.symlink.create)
# ============================================================

# Create missing tool symlinks
fix_symlink_create() {
    local check_id="$1"
    local binary="$2"
    local symlink="$3"
    local symlink_parent=""
    local existing_parent=""
    local rollback_command=""

    # Guard: Binary must exist and be executable
    if [[ ! -x "$binary" ]]; then
        doctor_fix_log WARN "Binary not found or not executable: $binary"
        return 1
    fi

    # Guard: Symlink must not exist
    if [[ -e "$symlink" ]]; then
        doctor_fix_log INFO "Symlink already exists: $symlink"
        return 0
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.symlink.create|Create symlink $(basename "$symlink")|$symlink|ln -s $binary $symlink")
        doctor_fix_log DRY "Create symlink: $(basename "$symlink") -> $binary"
        return 0
    fi

    symlink_parent="$(dirname "$symlink")"
    existing_parent="$(doctor_fix_nearest_existing_parent "$symlink")"
    rollback_command="$(doctor_fix_build_remove_path_rollback "$symlink" "$existing_parent")"

    # Ensure symlink directory exists
    if ! mkdir -p "$symlink_parent"; then
        doctor_fix_log ERROR "Failed to create symlink directory: $symlink_parent"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Create symlink
    if ! ln -s "$binary" "$symlink"; then
        if ! doctor_fix_run_rollback_command "$rollback_command" false; then
            doctor_fix_log ERROR "Failed to clean symlink destination after symlink failure: $symlink"
        fi
        doctor_fix_log ERROR "Failed to create symlink: $symlink"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Record change
    if ! doctor_fix_record_change_or_rollback \
        "$rollback_command" \
        false \
        "symlink" "Created symlink: $(basename "$symlink")" \
        "$rollback_command" \
        false "info" "$(doctor_fix_files_json "$symlink")" "[]" "[]"; then
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    doctor_fix_log INFO "Created symlink: $(basename "$symlink") -> $binary"
    FIXES_APPLIED+=("fix.symlink.create|Created symlink $(basename "$symlink")")
    FIX_APPLIED=$((FIX_APPLIED + 1))

    return 0
}

# ============================================================
# Fixer: Plugin Clone (fix.plugin.clone)
# ============================================================

# Clone missing zsh plugins
fix_plugin_clone() {
    local check_id="$1"
    local plugin_name="$2"
    local repo_url="$3"
    local runtime_home=""
    local existing_parent=""
    local rollback_command=""
    runtime_home="$(doctor_fix_runtime_home)"

    local plugins_dir="${ZSH_CUSTOM:-$runtime_home/.oh-my-zsh/custom}/plugins"
    local target_dir="$plugins_dir/$plugin_name"

    # Guard: Must not already exist
    if [[ -d "$target_dir" ]]; then
        doctor_fix_log INFO "Plugin already installed: $plugin_name"
        return 0
    fi

    # Guard: Oh-my-zsh must be installed
    if [[ ! -d "$runtime_home/.oh-my-zsh" ]]; then
        doctor_fix_log WARN "Oh-my-zsh not installed, cannot install plugins"
        FIXES_MANUAL+=("fix.plugin.clone|Install Oh-my-zsh first|curl -fsSL https://install.ohmyz.sh/ | bash")
        FIX_MANUAL=$((FIX_MANUAL + 1))
        return 1
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.plugin.clone|Clone zsh plugin: $plugin_name|$target_dir|git clone --depth 1 $repo_url $target_dir")
        doctor_fix_log DRY "Clone zsh plugin: $plugin_name"
        return 0
    fi

    existing_parent="$(doctor_fix_nearest_existing_parent "$target_dir")"
    rollback_command="$(doctor_fix_build_remove_tree_rollback "$target_dir" "$existing_parent")"

    # Ensure plugins directory exists
    if ! mkdir -p "$plugins_dir"; then
        doctor_fix_log ERROR "Failed to create plugins directory: $plugins_dir"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Clone plugin
    if git clone --depth 1 "$repo_url" "$target_dir" 2>/dev/null; then
        if ! doctor_fix_record_change_or_rollback \
            "$rollback_command" \
            false \
            "plugin" "Cloned zsh plugin: $plugin_name" \
            "$rollback_command" \
            false "info" "$(doctor_fix_files_json "$target_dir")" "[]" "[]"; then
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi

        doctor_fix_log INFO "Cloned zsh plugin: $plugin_name"
        FIXES_APPLIED+=("fix.plugin.clone|Cloned zsh plugin: $plugin_name")
        FIX_APPLIED=$((FIX_APPLIED + 1))
        return 0
    else
        if [[ -d "$target_dir" ]]; then
            if ! doctor_fix_run_rollback_command "$rollback_command" false; then
                doctor_fix_log ERROR "Failed to clean partial plugin clone after clone failure: $plugin_name"
            fi
        fi
        doctor_fix_log ERROR "Failed to clone plugin: $plugin_name"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
}

# ============================================================
# Fixer: ACFS Sourcing (fix.acfs.sourcing)
# ============================================================

# Add ACFS config sourcing to .zshrc
fix_acfs_sourcing() {
    local check_id="$1"
    local runtime_home=""
    local runtime_acfs_home=""
    runtime_home="$(doctor_fix_runtime_home)"
    runtime_acfs_home="$(doctor_fix_runtime_acfs_home)"
    local zshrc="$runtime_home/.zshrc"
    local source_line='[[ -f ~/.acfs/zsh/acfs.zshrc ]] && source ~/.acfs/zsh/acfs.zshrc'
    local marker="# ACFS configuration (added by doctor --fix)"

    # Guard: comments mentioning acfs.zshrc do not mean the loader is active.
    if doctor_fix_file_has_active_acfs_zshrc_source "$zshrc"; then
        doctor_fix_log INFO "ACFS already sourced in .zshrc"
        return 0
    fi

    # Guard: Check if acfs.zshrc exists
    if [[ ! -f "$runtime_acfs_home/zsh/acfs.zshrc" ]]; then
        doctor_fix_log WARN "ACFS config not found at ~/.acfs/zsh/acfs.zshrc"
        return 1
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.acfs.sourcing|Add ACFS sourcing to .zshrc|$zshrc|$source_line")
        doctor_fix_log DRY "Add ACFS sourcing to .zshrc"
        return 0
    fi

    # Create backup
    local backup_json=""
    local restore_command=""
    if [[ -f "$zshrc" ]]; then
        backup_json=$(create_backup "$zshrc" "acfs-sourcing")
        restore_command="$(autofix_backup_restore_command "$backup_json" 2>/dev/null || true)"
    else
        restore_command="if [[ -f '$zshrc' ]]; then sed -i '/$marker/,+1d' '$zshrc' && if ! grep -q '[^[:space:]]' '$zshrc'; then rm -f '$zshrc'; fi; fi"
    fi

    # Append sourcing line
    if ! {
        echo ""
        echo "$marker"
        echo "$source_line"
    } >> "$zshrc"; then
        doctor_fix_log ERROR "Failed to append ACFS sourcing to $zshrc"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Record change
    if ! doctor_fix_record_change_or_rollback \
        "${restore_command:-if [[ -f '$zshrc' ]]; then sed -i '/$marker/,+1d' '$zshrc'; fi}" \
        false \
        "config" "Added ACFS sourcing to .zshrc" \
        "${restore_command:-if [[ -f '$zshrc' ]]; then sed -i '/$marker/,+1d' '$zshrc'; fi}" \
        false "info" "$(doctor_fix_files_json "$zshrc")" "$(echo "${backup_json:-[]}" | jq -c 'if type == \"object\" then [.] else . end' 2>/dev/null || echo '[]')" "[]"; then
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    doctor_fix_log INFO "Added ACFS sourcing to .zshrc"
    FIXES_APPLIED+=("fix.acfs.sourcing|Added ACFS sourcing to .zshrc")
    FIX_APPLIED=$((FIX_APPLIED + 1))

    return 0
}

# ============================================================
# Fix Dispatcher
# ============================================================

# Dispatch a fix based on check ID
# Returns 0 if fix was applied or not needed, 1 if fix failed
dispatch_fix() {
    local check_id="$1"
    local check_status="$2"
    local fix_hint="${3:-}"  # Optional hint from check (e.g., file path)

    # Only fix failed or warned checks
    case "$check_status" in
        pass) return 0 ;;
        skip) return 0 ;;
    esac

    case "$check_id" in
        # PATH fixes
        path.*)
            fix_path_ordering "$check_id"
            ;;

        # Config file copies
        config.acfs_zshrc)
            fix_config_copy "$check_id" \
                "$SCRIPT_DIR/../../acfs/zsh/acfs.zshrc" \
                "$(doctor_fix_runtime_acfs_home)/zsh/acfs.zshrc"
            ;;
        config.tmux)
            fix_config_copy "$check_id" \
                "$SCRIPT_DIR/../../acfs/tmux/tmux.conf" \
                "$(doctor_fix_runtime_acfs_home)/tmux/tmux.conf"
            ;;

        # DCG hook
        hook.dcg.*)
            fix_dcg_hook "$check_id"
            ;;

        # Stack tools (fixes #160 - meta_skill and other stack tools)
        stack.meta_skill*)
            fix_verified_install "$check_id" "ms" "ms" --easy-mode
            ;;
        stack.mcp_agent_mail*)
            fix_mcp_agent_mail "$check_id"
            ;;

        # Symlinks
        symlink.br)
            fix_symlink_create "$check_id" "$(doctor_fix_runtime_home)/.cargo/bin/br" "$(doctor_fix_runtime_home)/.local/bin/br"
            ;;
        symlink.bv)
            fix_symlink_create "$check_id" "$(doctor_fix_runtime_home)/.cargo/bin/bv" "$(doctor_fix_runtime_home)/.local/bin/bv"
            ;;
        symlink.am)
            fix_symlink_create "$check_id" "$(doctor_fix_runtime_home)/mcp_agent_mail/am" "$(doctor_fix_runtime_home)/.local/bin/am"
            ;;

        # Zsh plugins
        shell.plugins.zsh_autosuggestions)
            fix_plugin_clone "$check_id" "zsh-autosuggestions" \
                "https://github.com/zsh-users/zsh-autosuggestions"
            ;;
        shell.plugins.zsh_syntax_highlighting)
            fix_plugin_clone "$check_id" "zsh-syntax-highlighting" \
                "https://github.com/zsh-users/zsh-syntax-highlighting"
            ;;

        # ACFS sourcing
        shell.acfs_sourced)
            fix_acfs_sourcing "$check_id"
            ;;

        # SSH server (fixes #161/#162)
        network.ssh_server)
            fix_ssh_server "$check_id"
            ;;

        # SSH keepalive
        network.ssh_keepalive|network.ssh_keepalive.*)
            fix_ssh_keepalive "$check_id"
            ;;

        # Agent CLI tools (fixes #213)
        agent.claude)
            fix_verified_install "$check_id" "claude" "claude"
            ;;
        agent.codex)
            fix_stack_install "$check_id" "codex" \
                "bun install -g --trust @openai/codex@latest"
            ;;
        agent.gemini)
            fix_stack_install "$check_id" "gemini" \
                "bun install -g --trust @google/gemini-cli@latest"
            ;;

        # Agent aliases/functions (fixes #163)
        agent.alias.*)
            fix_acfs_sourcing "$check_id"
            ;;

        # Manual fixes (log suggestion only)
        shell.ohmyzsh|shell.p10k|*.apt_install|*.sudo_required)
            if [[ -n "$fix_hint" ]]; then
                FIXES_MANUAL+=("$check_id|Requires manual action|$fix_hint")
            fi
            FIX_MANUAL=$((FIX_MANUAL + 1))
            return 0
            ;;

        *)
            # Unknown check - skip silently
            FIX_SKIPPED=$((FIX_SKIPPED + 1))
            return 0
            ;;
    esac
}

# ============================================================
# Fixer: Stack Install (fix.stack.install)
# ============================================================

# Install missing stack tools via their upstream installer
fix_stack_install() {
    local check_id="$1"
    local binary_name="$2"
    local install_cmd="$3"
    local installed_path=""
    local rollback_command=""
    local runtime_home=""
    local runtime_path=""

    runtime_home="$(doctor_fix_runtime_home)"
    runtime_path="$(doctor_fix_runtime_path 2>/dev/null || true)"
    if [[ -z "$runtime_home" || -z "$runtime_path" ]]; then
        doctor_fix_log ERROR "Failed to resolve runtime environment for $binary_name install"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Guard: Check if already installed for the runtime home
    installed_path="$(doctor_fix_binary_path "$binary_name" 2>/dev/null || true)"
    if [[ -n "$installed_path" ]]; then
        doctor_fix_log INFO "$binary_name already installed"
        return 0
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.stack.$binary_name|Install $binary_name|~/.local/bin/$binary_name|$install_cmd")
        doctor_fix_log DRY "Install $binary_name"
        return 0
    fi

    # Run installer inside the runtime home so shell expansions, relative paths,
    # and PATH resolution match the target account instead of the caller shell.
    if (
        cd "$runtime_home" &&
        env HOME="$runtime_home" PATH="$runtime_path" bash -c "$install_cmd"
    ) 2>/dev/null; then
        hash -r
        installed_path="$(doctor_fix_binary_path "$binary_name" 2>/dev/null || true)"
        if [[ -z "$installed_path" ]]; then
            doctor_fix_log ERROR "Installer reported success but $binary_name is still unavailable"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi
        rollback_command="$(doctor_fix_build_remove_binary_rollback "$installed_path")"

        if ! doctor_fix_record_change_or_rollback \
            "$rollback_command" \
            false \
            "install" "Installed $binary_name" \
            "# Manual rollback required: remove $binary_name if undesired" \
            false "info" "$(doctor_fix_files_json "$installed_path")" "[]" "[]"; then
            hash -r
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi

        doctor_fix_log INFO "Installed $binary_name"
        FIXES_APPLIED+=("fix.stack.$binary_name|Installed $binary_name")
        FIX_APPLIED=$((FIX_APPLIED + 1))
        return 0
    fi

    doctor_fix_log ERROR "Failed to install $binary_name"
    FIX_FAILED=$((FIX_FAILED + 1))
    return 1
}

fix_verified_install() {
    local check_id="$1"
    local binary_name="$2"
    local tool="$3"
    shift 3
    local args=("$@")
    local args_display="${args[*]:-}"
    local installed_path=""
    local rollback_command=""

    installed_path="$(doctor_fix_binary_path "$binary_name" 2>/dev/null || true)"
    if [[ -n "$installed_path" ]]; then
        doctor_fix_log INFO "$binary_name already installed"
        return 0
    fi

    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.stack.$binary_name|Install $binary_name via verified installer|~/.local/bin/$binary_name|verified:$tool ${args_display}")
        doctor_fix_log DRY "Install $binary_name via verified installer"
        return 0
    fi

    if doctor_fix_run_verified_installer "$tool" "${args[@]}" >/dev/null 2>&1; then
        hash -r
        installed_path="$(doctor_fix_binary_path "$binary_name" 2>/dev/null || true)"
        if [[ -n "$installed_path" ]]; then
            rollback_command="$(doctor_fix_build_remove_binary_rollback "$installed_path")"
            if ! doctor_fix_record_change_or_rollback \
                "$rollback_command" \
                false \
                "install" "Installed $binary_name via verified installer" \
                "# Manual rollback required: remove $binary_name if undesired" \
                false "info" "$(doctor_fix_files_json "$installed_path")" "[]" "[]"; then
                hash -r
                FIX_FAILED=$((FIX_FAILED + 1))
                return 1
            fi

            doctor_fix_log INFO "Installed $binary_name via verified installer"
            FIXES_APPLIED+=("fix.stack.$binary_name|Installed $binary_name via verified installer")
            FIX_APPLIED=$((FIX_APPLIED + 1))
            return 0
        fi
    fi

    doctor_fix_log ERROR "Failed to install $binary_name via verified installer"
    FIX_FAILED=$((FIX_FAILED + 1))
    return 1
}

# ============================================================
# Fixer: SSH Server (fix.ssh.server)
# ============================================================

# Install and enable SSH server
fix_ssh_server() {
    local check_id="$1"
    local sudo_cmd=""
    [[ $EUID -ne 0 ]] && command -v sudo &>/dev/null && sudo_cmd="sudo"

    # Guard: Check if already installed
    if command -v sshd &>/dev/null || [[ -f /etc/ssh/sshd_config ]]; then
        # Check if running
        if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
            if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
                doctor_fix_log INFO "SSH server already installed and running"
                return 0
            fi

            # Installed but not running - enable and start
            if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
                FIXES_DRY_RUN+=("fix.ssh.server|Enable and start SSH server|/etc/ssh/sshd_config|$sudo_cmd systemctl enable --now ssh")
                doctor_fix_log DRY "Enable and start SSH server"
                return 0
            fi

            if $sudo_cmd systemctl enable --now ssh 2>/dev/null || $sudo_cmd systemctl enable --now sshd 2>/dev/null; then
                if ! doctor_fix_record_change_or_rollback \
                    "$sudo_cmd systemctl disable --now ssh 2>/dev/null || $sudo_cmd systemctl disable --now sshd 2>/dev/null || true" \
                    true \
                    "service" "Enabled and started SSH server" \
                    "$sudo_cmd systemctl disable --now ssh 2>/dev/null || $sudo_cmd systemctl disable --now sshd 2>/dev/null || true" \
                    true "info" "[\"/etc/ssh/sshd_config\"]" "[]" "[]"; then
                    FIX_FAILED=$((FIX_FAILED + 1))
                    return 1
                fi

                doctor_fix_log INFO "Enabled and started SSH server"
                FIXES_APPLIED+=("fix.ssh.server|Enabled and started SSH server")
                FIX_APPLIED=$((FIX_APPLIED + 1))
                return 0
            fi

            doctor_fix_log ERROR "Failed to start SSH server"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi
        return 0
    fi

    # Not installed - install it
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.ssh.server|Install openssh-server|/etc/ssh/sshd_config|$sudo_cmd apt-get install -y openssh-server")
        doctor_fix_log DRY "Install openssh-server"
        return 0
    fi

    if $sudo_cmd apt-get install -y openssh-server 2>/dev/null; then
        if ! ($sudo_cmd systemctl enable --now ssh 2>/dev/null || $sudo_cmd systemctl enable --now sshd 2>/dev/null); then
            doctor_fix_log ERROR "Installed openssh-server but failed to enable/start SSH service"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi

        if ! doctor_fix_record_change_or_rollback \
            "" \
            false \
            "install" "Installed and enabled openssh-server" \
            "# Manual rollback required: remove openssh-server if undesired" \
            true "info" "[\"/etc/ssh/sshd_config\"]" "[]" "[]"; then
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi

        doctor_fix_log INFO "Installed and enabled openssh-server"
        FIXES_APPLIED+=("fix.ssh.server|Installed and enabled openssh-server")
        FIX_APPLIED=$((FIX_APPLIED + 1))
        return 0
    fi

    doctor_fix_log ERROR "Failed to install openssh-server"
    FIX_FAILED=$((FIX_FAILED + 1))
    return 1
}

# ============================================================
# Fixer: SSH Keepalive (fix.ssh.keepalive)
# ============================================================

# Configure SSH keepalive settings
fix_ssh_keepalive() {
    local check_id="$1"
    local sshd_config="${DOCTOR_FIX_SSHD_CONFIG:-/etc/ssh/sshd_config}"
    local marker="# ACFS: SSH keepalive settings (added by doctor --fix)"
    local fallback_restore_command=""

    local sudo_cmd=""
    [[ $EUID -ne 0 ]] && command -v sudo &>/dev/null && sudo_cmd="sudo"

    # Guard: sshd_config must exist
    if [[ ! -f "$sshd_config" ]]; then
        doctor_fix_log WARN "sshd_config not found, install openssh-server first"
        FIXES_MANUAL+=("$check_id|Install openssh-server first|$sudo_cmd apt-get install -y openssh-server")
        FIX_MANUAL=$((FIX_MANUAL + 1))
        return 1
    fi

    # Guard: Check if already configured
    if grep -qE '^[[:space:]]*ClientAliveInterval[[:space:]]+[0-9]+' "$sshd_config" 2>/dev/null; then
        doctor_fix_log INFO "SSH keepalive already configured"
        return 0
    fi

    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.ssh.keepalive|Configure SSH keepalive|$sshd_config|echo 'ClientAliveInterval 60' >> $sshd_config")
        doctor_fix_log DRY "Configure SSH keepalive in $sshd_config"
        return 0
    fi

    # Create backup
    local backup_json=""
    local restore_command=""
    printf -v fallback_restore_command \
        "sed -i '/%s/,+2d' %q" \
        "$marker" "$sshd_config"
    if [[ -f "$sshd_config" ]]; then
        backup_json=$(create_backup "$sshd_config" "ssh-keepalive")
        restore_command="$(autofix_backup_restore_command "$backup_json" 2>/dev/null || true)"
    fi

    # Apply settings
    if ! {
        echo ""
        echo "$marker"
        echo "ClientAliveInterval 60"
        echo "ClientAliveCountMax 3"
    } | $sudo_cmd tee -a "$sshd_config" > /dev/null; then
        doctor_fix_log ERROR "Failed to append SSH keepalive settings to $sshd_config"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Restart sshd to apply
    $sudo_cmd systemctl reload ssh 2>/dev/null || $sudo_cmd systemctl reload sshd 2>/dev/null || true

    if ! doctor_fix_record_change_or_rollback \
        "${restore_command:-$fallback_restore_command}; $sudo_cmd systemctl reload ssh 2>/dev/null || $sudo_cmd systemctl reload sshd 2>/dev/null || true" \
        true \
        "config" "Configured SSH keepalive in $sshd_config" \
        "${restore_command:-$fallback_restore_command}; $sudo_cmd systemctl reload ssh 2>/dev/null || $sudo_cmd systemctl reload sshd 2>/dev/null || true" \
        true "info" "$(doctor_fix_files_json "$sshd_config")" "$(echo "${backup_json:-[]}" | jq -c 'if type == \"object\" then [.] else . end' 2>/dev/null || echo '[]')" "[]"; then
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    doctor_fix_log INFO "Configured SSH keepalive (ClientAliveInterval 60, ClientAliveCountMax 3)"
    FIXES_APPLIED+=("fix.ssh.keepalive|Configured SSH keepalive settings")
    FIX_APPLIED=$((FIX_APPLIED + 1))

    return 0
}

# ============================================================
# Fixer: MCP Agent Mail (fix.stack.mcp_agent_mail)
# ============================================================

doctor_fix_agent_mail_cli_path() {
    local runtime_home=""
    local primary_bin=""
    local candidate=""

    runtime_home="$(doctor_fix_runtime_home)"
    [[ -n "$runtime_home" ]] || return 1

    primary_bin="$(doctor_fix_runtime_bin_dir)"
    for candidate in \
        "$primary_bin/am" \
        "$runtime_home/.local/bin/am" \
        "$runtime_home/.acfs/bin/am" \
        "$runtime_home/.cargo/bin/am" \
        "$runtime_home/.bun/bin/am" \
        "$runtime_home/.atuin/bin/am" \
        "$runtime_home/go/bin/am"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

doctor_fix_resolve_path_target() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1

    if readlink -f "$path_value" >/dev/null 2>&1; then
        readlink -f "$path_value"
        return 0
    fi

    if realpath "$path_value" >/dev/null 2>&1; then
        realpath "$path_value"
        return 0
    fi

    printf '%s\n' "$path_value"
}

doctor_fix_agent_mail_bin() {
    local runtime_user=""
    local runtime_home=""
    local primary_bin=""
    local candidate=""
    local resolved=""

    runtime_user="$(doctor_fix_runtime_user)"
    runtime_home="$(doctor_fix_runtime_home)"
    [[ -n "$runtime_home" ]] || return 1

    if [[ -x "$runtime_home/mcp_agent_mail/am" ]]; then
        printf '%s\n' "$runtime_home/mcp_agent_mail/am"
        return 0
    fi

    resolved="$(doctor_fix_agent_mail_cli_path 2>/dev/null || true)"
    if [[ -n "$resolved" ]]; then
        printf '%s\n' "$resolved"
        return 0
    fi

    if doctor_fix_source_stack_lib >/dev/null 2>&1; then
        resolved="$(ACFS_STACK_TRUST_TARGET_HOME=true TARGET_USER="$runtime_user" TARGET_HOME="$runtime_home" _stack_agent_mail_cli_path 2>/dev/null || true)"
        if [[ -n "$resolved" ]]; then
            printf '%s\n' "$resolved"
            return 0
        fi
    fi

    primary_bin="$(doctor_fix_runtime_bin_dir)"
    for candidate in \
        "$runtime_home/mcp_agent_mail/am" \
        "$primary_bin/am" \
        "$runtime_home/.local/bin/am" \
        "$runtime_home/.acfs/bin/am" \
        "$runtime_home/.cargo/bin/am" \
        "$runtime_home/.bun/bin/am" \
        "$runtime_home/.atuin/bin/am" \
        "$runtime_home/go/bin/am"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

doctor_fix_agent_mail_mcp_path() {
    local am_bin="${1:-}"

    if [[ -z "$am_bin" ]]; then
        am_bin="$(doctor_fix_agent_mail_bin 2>/dev/null || true)"
    fi
    [[ -n "$am_bin" ]] || return 1

    if "$am_bin" --version 2>/dev/null | grep -q '^am '; then
        printf '/mcp/\n'
    else
        printf '/api/\n'
    fi
}
agent_mail_fix_doctor_healthy() {
    local doctor_json=""
    local am_bin=""
    local -a cmd=()

    am_bin="$(doctor_fix_agent_mail_bin 2>/dev/null || true)"
    [[ -n "$am_bin" ]] || return 1
    cmd=("$am_bin" doctor check --json)

    if [[ $# -gt 0 ]]; then
        cmd+=("$1")
    fi

    if command -v timeout &>/dev/null; then
        doctor_json="$(timeout 15s "${cmd[@]}" 2>/dev/null)" || return 1
    else
        doctor_json="$("${cmd[@]}" 2>/dev/null)" || return 1
    fi

    [[ -n "$doctor_json" ]] || return 1

    if command -v jq &>/dev/null; then
        [[ "$(printf '%s' "$doctor_json" | jq -r '.healthy // false' 2>/dev/null)" == "true" ]]
        return $?
    fi

    printf '%s' "$doctor_json" | grep -q '"healthy"[[:space:]]*:[[:space:]]*true'
}

agent_mail_fix_wait_for_health() {
    doctor_fix_source_stack_lib || return 1
    ACFS_STACK_TRUST_TARGET_HOME=true TARGET_USER="$(doctor_fix_runtime_user)" TARGET_HOME="$(doctor_fix_runtime_home)" _stack_wait_for_agent_mail_health
}

agent_mail_fix_write_unit() {
    local runtime_home=""
    runtime_home="$(doctor_fix_runtime_home)"
    local storage_root="$runtime_home/.mcp_agent_mail_git_mailbox_repo"
    local unit_dir="$runtime_home/.config/systemd/user"
    local unit_file="$unit_dir/agent-mail.service"
    local am_bin=""
    local db_url=""
    local storage_root_unit=""
    local rust_log_env=""
    local storage_root_env=""
    local database_url_env=""
    local http_path_env=""
    local am_bin_exec=""
    local am_mcp_path_exec=""

    am_bin="$(doctor_fix_agent_mail_bin 2>/dev/null || true)"
    [[ -n "$am_bin" ]] || return 1

    db_url="sqlite+aiosqlite:///${storage_root}/storage.sqlite3"

    local am_mcp_path=""
    am_mcp_path="$(doctor_fix_agent_mail_mcp_path "$am_bin" 2>/dev/null || true)"
    [[ -n "$am_mcp_path" ]] || return 1

    mkdir -p "$storage_root" "$unit_dir" || return 1
    storage_root_unit="$(doctor_fix_systemd_unit_path_escape "$storage_root")" || return 1
    rust_log_env="$(doctor_fix_systemd_unit_env_assignment RUST_LOG info)" || return 1
    storage_root_env="$(doctor_fix_systemd_unit_env_assignment STORAGE_ROOT "$storage_root")" || return 1
    database_url_env="$(doctor_fix_systemd_unit_env_assignment DATABASE_URL "$db_url")" || return 1
    http_path_env="$(doctor_fix_systemd_unit_env_assignment HTTP_PATH "$am_mcp_path")" || return 1
    am_bin_exec="$(doctor_fix_systemd_unit_exec_command "$am_bin")" || return 1
    am_mcp_path_exec="$(doctor_fix_systemd_unit_exec_arg "$am_mcp_path")" || return 1
    cat > "$unit_file" <<UNIT_EOF
[Unit]
Description=MCP Agent Mail Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$storage_root_unit
Environment=$rust_log_env
Environment=$storage_root_env
Environment=$database_url_env
Environment=$http_path_env
ExecStart=${am_bin_exec} serve-http --host 127.0.0.1 --port 8765 --path ${am_mcp_path_exec} --no-auth --no-tui
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=default.target
UNIT_EOF
}

agent_mail_fix_launch_fallback() {
    local storage_root="$(doctor_fix_runtime_home)/.mcp_agent_mail_git_mailbox_repo"
    local fallback_pid_file="$storage_root/agent-mail.pid"
    local fallback_log_file="$storage_root/agent-mail.log"
    local am_bin=""
    local db_url=""
    local existing_pid=""

    am_bin="$(doctor_fix_agent_mail_bin 2>/dev/null || true)"
    [[ -n "$am_bin" ]] || return 1

    db_url="sqlite+aiosqlite:///${storage_root}/storage.sqlite3"

    local am_mcp_path=""
    am_mcp_path="$(doctor_fix_agent_mail_mcp_path "$am_bin" 2>/dev/null || true)"
    [[ -n "$am_mcp_path" ]] || return 1

    if doctor_fix_curl -fsS --max-time 5 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1; then
        return 0
    fi

    if [[ -f "$fallback_pid_file" ]]; then
        existing_pid="$(cat "$fallback_pid_file" 2>/dev/null || true)"
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null && \
           ps -p "$existing_pid" -o args= 2>/dev/null | grep -Fq "$am_bin serve-http"; then
            return 0
        fi
        rm -f "$fallback_pid_file"
    fi

    nohup env \
        RUST_LOG=info \
        STORAGE_ROOT="$storage_root" \
        DATABASE_URL="$db_url" \
        HTTP_PATH="$am_mcp_path" \
        "$am_bin" serve-http --host 127.0.0.1 --port 8765 --path "$am_mcp_path" --no-auth --no-tui \
        >>"$fallback_log_file" 2>&1 < /dev/null &
    echo $! > "$fallback_pid_file"
}

agent_mail_fix_stop_fallback() {
    local storage_root="$(doctor_fix_runtime_home)/.mcp_agent_mail_git_mailbox_repo"
    local fallback_pid_file="$storage_root/agent-mail.pid"
    local am_bin=""
    local existing_pid=""

    am_bin="$(doctor_fix_agent_mail_bin 2>/dev/null || true)"
    [[ -n "$am_bin" ]] || return 1

    if [[ -f "$fallback_pid_file" ]]; then
        existing_pid="$(cat "$fallback_pid_file" 2>/dev/null || true)"
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null && \
           ps -p "$existing_pid" -o args= 2>/dev/null | grep -Fq "$am_bin serve-http"; then
            kill "$existing_pid" >/dev/null 2>&1 || true
            for _ in {1..10}; do
                if ! kill -0 "$existing_pid" 2>/dev/null; then
                    break
                fi
                sleep 1
            done
            if kill -0 "$existing_pid" 2>/dev/null; then
                kill -9 "$existing_pid" >/dev/null 2>&1 || true
            fi
        fi
        rm -f "$fallback_pid_file"
    fi
}

fix_mcp_agent_mail() {
    local check_id="$1"
    local fixed_any=false
    local service_healthy=false
    local doctor_healthy=false
    local runtime_home=""
    local runtime_user=""
    local am_src=""
    local am_dst=""
    local storage_root=""
    local unit_file=""
    runtime_home="$(doctor_fix_runtime_home)"
    runtime_user="$(doctor_fix_runtime_user)"
    am_src="$runtime_home/mcp_agent_mail/am"
    am_dst="$runtime_home/.local/bin/am"
    storage_root="$runtime_home/.mcp_agent_mail_git_mailbox_repo"
    unit_file="$runtime_home/.config/systemd/user/agent-mail.service"

    doctor_fix_source_stack_lib || {
        doctor_fix_log ERROR "Unable to load stack helper library for MCP Agent Mail repair"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    }

    if [[ -x "$am_src" ]]; then
        local resolved_am_cli=""
        local resolved_am_target=""
        local am_src_target=""
        resolved_am_cli="$(doctor_fix_agent_mail_cli_path 2>/dev/null || true)"
        resolved_am_target="$(doctor_fix_resolve_path_target "$resolved_am_cli" 2>/dev/null || true)"
        am_src_target="$(doctor_fix_resolve_path_target "$am_src" 2>/dev/null || true)"
        if [[ -z "$resolved_am_target" || "$resolved_am_target" != "$am_src_target" ]]; then
            local symlink_backup_json='[]'
            local symlink_restore_command="rm -f '$am_dst'"
            if [[ -e "$am_dst" || -L "$am_dst" ]]; then
                symlink_backup_json="$(create_backup "$am_dst" "doctor-fix-agent-mail-symlink" 2>/dev/null || echo '[]')"
                symlink_restore_command="$(autofix_backup_restore_command "$symlink_backup_json" 2>/dev/null || true)"
                if [[ -z "$symlink_restore_command" || "$symlink_backup_json" == '[]' ]]; then
                    doctor_fix_log ERROR "Failed to back up existing am entry before repairing CLI symlink"
                    FIX_FAILED=$((FIX_FAILED + 1))
                    return 1
                fi
            fi

            if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
                FIXES_DRY_RUN+=("fix.stack.mcp_agent_mail.symlink|Ensure am symlink points at installed Rust CLI|$am_dst|ln -sf $am_src $am_dst")
                doctor_fix_log DRY "Ensure am symlink points at $am_src"
            elif ACFS_STACK_TRUST_TARGET_HOME=true TARGET_USER="$runtime_user" TARGET_HOME="$runtime_home" _stack_repair_agent_mail_cli_symlink; then
                hash -r
                resolved_am_cli="$(doctor_fix_agent_mail_cli_path 2>/dev/null || true)"
                resolved_am_target="$(doctor_fix_resolve_path_target "$resolved_am_cli" 2>/dev/null || true)"
                if [[ -z "$resolved_am_target" || "$resolved_am_target" != "$am_src_target" ]]; then
                    doctor_fix_log ERROR "Agent Mail CLI symlink repair completed but am still resolves away from $am_src"
                    FIX_FAILED=$((FIX_FAILED + 1))
                    return 1
                fi

                if ! doctor_fix_record_change_or_rollback \
                    "$symlink_restore_command" \
                    false \
                    "symlink" "Ensured am resolves to installed Rust CLI" \
                    "$symlink_restore_command" \
                    false "info" "$(doctor_fix_files_json "$am_dst")" "$symlink_backup_json" "[]"; then
                    FIX_FAILED=$((FIX_FAILED + 1))
                    return 1
                fi

                hash -r
                doctor_fix_log INFO "Ensured am resolves to the installed Rust CLI"
                FIXES_APPLIED+=("fix.stack.mcp_agent_mail.symlink|Ensured am resolves to installed Rust CLI")
                FIX_APPLIED=$((FIX_APPLIED + 1))
                fixed_any=true
            else
                doctor_fix_log ERROR "Failed to repair Agent Mail CLI symlink"
                FIX_FAILED=$((FIX_FAILED + 1))
                return 1
            fi
        fi
    fi

    local am_bin=""
    am_bin="$(doctor_fix_agent_mail_bin 2>/dev/null || true)"

    if [[ -z "$am_bin" ]]; then
        if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
            FIXES_DRY_RUN+=("fix.stack.mcp_agent_mail|Install MCP Agent Mail via verified installer, then repair service state|$runtime_home/mcp_agent_mail|verified:mcp_agent_mail --dest $runtime_home/mcp_agent_mail --yes")
            doctor_fix_log DRY "Install MCP Agent Mail via verified installer, then repair service state"
            return 0
        fi

        if doctor_fix_run_verified_installer "mcp_agent_mail" --dest "$runtime_home/mcp_agent_mail" --yes >/dev/null 2>&1; then
            local installed_cli=""
            local installed_cli_target=""
            local am_src_target=""
            hash -r
            if ACFS_STACK_TRUST_TARGET_HOME=true TARGET_USER="$runtime_user" TARGET_HOME="$runtime_home" _stack_repair_agent_mail_cli_symlink; then
                hash -r
            fi
            installed_cli="$(doctor_fix_agent_mail_cli_path 2>/dev/null || true)"
            installed_cli_target="$(doctor_fix_resolve_path_target "$installed_cli" 2>/dev/null || true)"
            am_src_target="$(doctor_fix_resolve_path_target "$am_src" 2>/dev/null || true)"
            if [[ -z "$installed_cli_target" || "$installed_cli_target" != "$am_src_target" ]]; then
                doctor_fix_log ERROR "Installed MCP Agent Mail CLI but failed to repair am symlink"
                FIX_FAILED=$((FIX_FAILED + 1))
                return 1
            fi
            am_bin="$(doctor_fix_agent_mail_bin 2>/dev/null || true)"
            if [[ -n "$am_bin" ]]; then
                if ! doctor_fix_record_change_or_rollback \
                    "" \
                    false \
                    "install" "Installed MCP Agent Mail CLI via verified installer" \
                    "# Manual rollback required: remove $runtime_home/mcp_agent_mail if undesired" \
                    false "info" "$(doctor_fix_files_json "$runtime_home/mcp_agent_mail")" "[]" "[]"; then
                    FIX_FAILED=$((FIX_FAILED + 1))
                    return 1
                fi

                doctor_fix_log INFO "Installed MCP Agent Mail CLI via verified installer"
                FIXES_APPLIED+=("fix.stack.mcp_agent_mail.install|Installed MCP Agent Mail CLI via verified installer")
                FIX_APPLIED=$((FIX_APPLIED + 1))
                fixed_any=true
            else
                doctor_fix_log ERROR "Verified MCP Agent Mail install completed but am does not resolve to $am_src"
                FIX_FAILED=$((FIX_FAILED + 1))
                return 1
            fi
        else
            doctor_fix_log ERROR "Failed to install MCP Agent Mail via verified installer"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi
    elif [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.stack.mcp_agent_mail|Repair MCP Agent Mail and apply upstream doctor fixes|$runtime_home/.mcp_agent_mail_git_mailbox_repo|am doctor repair --yes && am doctor fix --yes")
        doctor_fix_log DRY "Repair MCP Agent Mail database, apply upstream doctor fixes, and restart the service"
        return 0
    fi

    am_bin="$(doctor_fix_agent_mail_bin 2>/dev/null || true)"
    [[ -n "$am_bin" ]] || {
        doctor_fix_log ERROR "MCP Agent Mail CLI is missing after repair attempt"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    }

    if "$am_bin" doctor repair --yes >/dev/null 2>&1; then
        if ! doctor_fix_record_change_or_rollback \
            "" \
            false \
            "repair" "Ran MCP Agent Mail database repair" \
            "# Manual rollback required: restore Agent Mail storage from backup if needed" \
            false "info" "$(doctor_fix_files_json "$storage_root")" "[]" "[]"; then
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi

        doctor_fix_log INFO "Ran MCP Agent Mail database repair"
        FIXES_APPLIED+=("fix.stack.mcp_agent_mail.repair|Ran MCP Agent Mail database repair")
        FIX_APPLIED=$((FIX_APPLIED + 1))
        fixed_any=true
    else
        doctor_fix_log WARN "MCP Agent Mail database repair did not complete cleanly"
    fi

    if "$am_bin" doctor fix --yes >/dev/null 2>&1; then
        if ! doctor_fix_record_change_or_rollback \
            "" \
            false \
            "repair" "Applied MCP Agent Mail doctor fixes" \
            "# Manual rollback required: restore Agent Mail storage/config from backup if needed" \
            false "info" "$(doctor_fix_files_json "$storage_root")" "[]" "[]"; then
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi

        doctor_fix_log INFO "Applied MCP Agent Mail doctor fixes"
        FIXES_APPLIED+=("fix.stack.mcp_agent_mail.fix|Applied MCP Agent Mail doctor fixes")
        FIX_APPLIED=$((FIX_APPLIED + 1))
        fixed_any=true
    else
        doctor_fix_log WARN "MCP Agent Mail doctor fix did not complete cleanly"
    fi

    if doctor_fix_curl -fsS --max-time 5 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1 && \
       doctor_fix_curl -fsS --max-time 5 http://127.0.0.1:8765/health >/dev/null 2>&1; then
        service_healthy=true
    fi

    if ACFS_STACK_TRUST_TARGET_HOME=true TARGET_USER="$runtime_user" TARGET_HOME="$runtime_home" _stack_configure_agent_mail_service; then
        if ! doctor_fix_record_change_or_rollback \
            "" \
            false \
            "service" "Repaired MCP Agent Mail managed service" \
            "# Manual rollback required: restore Agent Mail user service files if needed" \
            true "info" "$(doctor_fix_files_json "$unit_file")" "[]" "[]"; then
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi

        doctor_fix_log INFO "Repaired MCP Agent Mail managed service"
        FIXES_APPLIED+=("fix.stack.mcp_agent_mail.service|Repaired MCP Agent Mail managed service")
        FIX_APPLIED=$((FIX_APPLIED + 1))
        fixed_any=true

        if agent_mail_fix_wait_for_health; then
            doctor_fix_log INFO "Agent Mail service is healthy after restart"
            service_healthy=true
        else
            doctor_fix_log WARN "Agent Mail service did not reach readiness after repair"
        fi
    elif [[ "$service_healthy" != "true" ]]; then
        doctor_fix_log WARN "Failed to rewrite MCP Agent Mail user service unit"
    fi

    if [[ "$service_healthy" == "true" ]] && agent_mail_fix_doctor_healthy; then
        project_path="$(git rev-parse --show-toplevel 2>/dev/null || true)"
        if [[ -n "$project_path" ]]; then
            if agent_mail_fix_doctor_healthy "$project_path"; then
                doctor_healthy=true
            fi
        else
            doctor_healthy=true
        fi
    fi

    if [[ "$doctor_healthy" == "true" ]]; then
        if [[ "$fixed_any" == "true" ]]; then
            doctor_fix_log INFO "MCP Agent Mail is healthy after repair"
        else
            doctor_fix_log INFO "MCP Agent Mail is already healthy"
        fi
        return 0
    fi

    doctor_fix_log ERROR "Failed to repair MCP Agent Mail to a healthy state"
    FIX_FAILED=$((FIX_FAILED + 1))
    return 1
}

# ============================================================
# Summary Output
# ============================================================

# Print fix summary
print_fix_summary() {
    echo ""
    echo "========================================================================"
    echo "  Doctor --fix Summary"
    echo "========================================================================"

    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        echo "  Mode: DRY-RUN (no changes made)"
        echo ""

        if [[ ${#FIXES_DRY_RUN[@]} -gt 0 ]]; then
            echo "  Would apply the following fixes:"
            for fix in "${FIXES_DRY_RUN[@]}"; do
                IFS='|' read -r id desc file cmd <<< "$fix"
                echo ""
                echo "    [$id]"
                echo "      Action: $desc"
                echo "      File: $file"
                echo "      Command: $cmd"
            done
        else
            echo "  No fixes needed."
        fi
    else
        echo "  Applied: $FIX_APPLIED"
        echo "  Skipped: $FIX_SKIPPED"
        echo "  Failed:  $FIX_FAILED"
        echo "  Manual:  $FIX_MANUAL"

        if [[ ${#FIXES_APPLIED[@]} -gt 0 ]]; then
            echo ""
            echo "  Applied fixes:"
            for fix in "${FIXES_APPLIED[@]}"; do
                IFS='|' read -r id desc <<< "$fix"
                echo "    [$id] $desc"
            done
        fi
    fi

    if [[ ${#FIXES_MANUAL[@]} -gt 0 ]]; then
        echo ""
        echo "  Manual fixes needed:"
        for fix in "${FIXES_MANUAL[@]}"; do
            IFS='|' read -r id desc cmd <<< "$fix"
            echo "    [$id] $desc"
            echo "      Run: $cmd"
        done
    fi

    echo ""
    echo "========================================================================"

    # Show undo hint if changes were made
    if [[ "$DOCTOR_FIX_DRY_RUN" != "true" ]] && [[ $FIX_APPLIED -gt 0 ]]; then
        echo ""
        echo "  To undo changes: acfs undo --list"
        echo ""
    fi
}

# ============================================================
# Main Entry Point
# ============================================================

# Run doctor --fix
# Usage: run_doctor_fix [--dry-run] [--yes] [--only <categories>]
run_doctor_fix() {
    local only_categories=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DOCTOR_FIX_DRY_RUN=true; shift ;;
            --yes) DOCTOR_FIX_YES=true; shift ;;
            --prompt) DOCTOR_FIX_PROMPT=true; shift ;;
            --only)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --only requires a category value" >&2
                    return 1
                fi
                only_categories="$2"
                shift 2
                ;;
            *) shift ;;
        esac
    done

    # Initialize autofix session (unless dry-run)
    if [[ "$DOCTOR_FIX_DRY_RUN" != "true" ]]; then
        start_autofix_session || {
            echo "ERROR: Failed to start autofix session" >&2
            return 1
        }
    fi

    # Reset counters
    FIX_APPLIED=0
    FIX_SKIPPED=0
    FIX_FAILED=0
    FIX_MANUAL=0
    FIXES_APPLIED=()
    FIXES_DRY_RUN=()
    FIXES_MANUAL=()
    FIXES_PROMPTED=()

    echo ""
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: acfs doctor --fix"
        echo "Scanning for fixable issues..."
    else
        echo "Running: acfs doctor --fix"
        echo "Applying safe fixes..."
    fi
    echo ""

    # The actual fixes are dispatched by the caller (doctor.sh)
    # based on check results. This function sets up the environment.

    return 0
}

# Finalize doctor --fix
finalize_doctor_fix() {
    # Print summary
    print_fix_summary

    # End autofix session (unless dry-run)
    if [[ "$DOCTOR_FIX_DRY_RUN" != "true" ]]; then
        if ! end_autofix_session; then
            echo "ERROR: Failed to finalize autofix session" >&2
            return 1
        fi

        # Print undo summary if changes were made
        if [[ $FIX_APPLIED -gt 0 ]]; then
            print_undo_summary
        fi
    fi

    # Return failure if any fixes failed
    if [[ $FIX_FAILED -gt 0 ]]; then
        return 1
    fi

    return 0
}
