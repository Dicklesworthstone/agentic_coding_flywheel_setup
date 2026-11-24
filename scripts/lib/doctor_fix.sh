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

# Arch-family hosts repair packages with pacman, not apt. doctor.sh owns the
# detection (installer verdict, then /etc/os-release); when this file is sourced
# on its own, only the installer's exported verdict is consulted.
doctor_fix_is_arch_family() {
    if declare -F _acfs_doctor_is_arch_family >/dev/null 2>&1; then
        _acfs_doctor_is_arch_family
        return
    fi
    [[ "${ACFS_DISTRO_FAMILY:-}" == "arch" ]]
}

# Display form of the SSH server install command for dry-run and manual hints.
doctor_fix_ssh_server_install_display() {
    local root_display="$1"
    if doctor_fix_is_arch_family; then
        printf '%spacman -S --needed --noconfirm openssh' "$root_display"
    else
        printf '%sapt-get -o DPkg::Lock::Timeout=120 install -y openssh-server' "$root_display"
    fi
}

doctor_fix_system_binary_path() {
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
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

# Lifecycle helpers normally run as the target user and may legitimately use
# that user's installed tools. When doctor --fix itself has root authority,
# however, never resolve support commands through the user-augmented doctor
# PATH: an executable in ~/.local/bin must not inherit root merely because a
# fallback Agent Mail process needs to be inspected or started.
doctor_fix_lifecycle_binary_path() {
    local name="${1:-}"
    local resolved=""

    if [[ $EUID -eq 0 ]]; then
        doctor_fix_system_binary_path "$name"
        return
    fi

    resolved="$(command -v -- "$name" 2>/dev/null || true)"
    [[ -n "$resolved" ]] || return 1
    printf '%s\n' "$resolved"
}

doctor_fix_root_prefix() {
    local ref_name="${1:-}"

    [[ -n "$ref_name" ]] || return 1

    local -n _root_prefix_ref="$ref_name"
    _root_prefix_ref=()

    if [[ $EUID -eq 0 ]]; then
        return 0
    fi

    local sudo_bin=""
    sudo_bin="$(doctor_fix_system_binary_path sudo 2>/dev/null || true)"
    [[ -n "$sudo_bin" ]] || return 1
    _root_prefix_ref=("$sudo_bin" -n)
}

doctor_fix_root_display_prefix() {
    local sudo_bin=""
    local display_prefix=""

    if [[ $EUID -eq 0 ]]; then
        printf '%s' ""
        return 0
    fi

    sudo_bin="$(doctor_fix_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        printf -v display_prefix '%q -n ' "$sudo_bin"
    else
        display_prefix="sudo -n "
    fi
    printf '%s' "$display_prefix"
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

doctor_fix_system_curl() {
    local curl_bin=""

    curl_bin="$(doctor_fix_system_binary_path curl 2>/dev/null || true)"
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
DOCTOR_FIX_FINALIZED=false

# Counters for fix summary
declare -g FIX_APPLIED=0
declare -g FIX_SKIPPED=0
declare -g FIX_FAILED=0
declare -g FIX_MANUAL=0
declare -g FIX_FILTERED=0

# A bare category selects that category's checks; dotted selectors name one
# exact check. doctor.sh validates these against the completed diagnostic
# results before dispatching any scoped repairs.
declare -ga DOCTOR_FIX_ONLY_SELECTORS=()

# A failed launch is different from a missing command or a broken service/hook.
# Keep that diagnostic fact until scoped repairs are dispatched. Existing
# installers cannot transactionally replace a package and restore its full
# prior state, so these findings require an explicit manual repair instead.
declare -ga DOCTOR_FIX_FAILED_COMMAND_IDS=()

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

    # Output to user. Under --json stdout must stay a single JSON document,
    # so informational fix chatter goes to stderr there.
    local fix_out=1
    if [[ "${JSON_MODE:-false}" == "true" ]]; then
        fix_out=2
    fi
    case "$level" in
        INFO)  echo "  [fix] $message" >&"$fix_out" ;;
        WARN)  echo "  [fix] WARNING: $message" >&2 ;;
        ERROR) echo "  [fix] ERROR: $message" >&2 ;;
        DRY)   echo "  [dry-run] Would: $message" >&"$fix_out" ;;
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
    # sed -i rewrites via a temp file + rename, which replaces the target
    # inode: on a symlinked ~/.zshrc (common with dotfile managers) that
    # silently swaps the symlink for a detached plain file. Resolve the
    # symlink and edit the real target instead.
    local real_file=""
    real_file="$(readlink -f -- "$file" 2>/dev/null || true)"
    [[ -n "$real_file" && -f "$real_file" ]] || real_file="$file"
    escaped_line="$(doctor_fix_sed_literal "$line")"
    sed -i "\\|^${escaped_line}$|,+1d" "$real_file"
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
    local bash_bin=""
    local env_bin=""
    local sudo_bin=""
    local rollback_path="/usr/sbin:/usr/bin:/sbin:/bin"
    local -a rollback_env_args=()
    local -a sudo_cmd=()

    [[ -n "$rollback_command" ]] || return 1

    bash_bin="$(doctor_fix_system_binary_path bash 2>/dev/null || true)"
    if [[ -z "$bash_bin" ]]; then
        doctor_fix_log ERROR "Rollback requires system bash but bash is unavailable"
        return 1
    fi

    env_bin="$(doctor_fix_system_binary_path env 2>/dev/null || true)"
    if [[ -z "$env_bin" ]]; then
        doctor_fix_log ERROR "Rollback requires system env but env is unavailable"
        return 1
    fi

    if [[ "$requires_root" == "true" ]]; then
        if [[ $EUID -ne 0 ]]; then
            sudo_bin="$(doctor_fix_system_binary_path sudo 2>/dev/null || true)"
            [[ -n "$sudo_bin" ]] && sudo_cmd=("$sudo_bin" -n)
        fi
        if [[ $EUID -ne 0 && ${#sudo_cmd[@]} -eq 0 ]]; then
            doctor_fix_log ERROR "Rollback requires root but sudo is unavailable"
            return 1
        fi
    fi

    rollback_env_args=(
        -i
        PATH="$rollback_path"
        "$bash_bin"
        --noprofile
        --norc
        -p
        -c "$rollback_command"
    )

    if [[ ${#sudo_cmd[@]} -gt 0 ]]; then
        "${sudo_cmd[@]}" "$env_bin" "${rollback_env_args[@]}"
    else
        "$env_bin" "${rollback_env_args[@]}"
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

doctor_fix_backups_json_array() {
    local backup_json="${1:-[]}"
    local jq_bin=""

    jq_bin="$(doctor_fix_system_binary_path jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        printf '%s\n' "${backup_json:-[]}" | "$jq_bin" -c 'if type == "object" then [.] else . end' 2>/dev/null && return 0
    fi

    printf '[]\n'
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

doctor_fix_parse_env_assignment() {
    local assignment="${1:-}"
    local -n _name_ref="$2"
    local -n _value_ref="$3"

    _name_ref=""
    _value_ref=""
    [[ -n "$assignment" ]] || return 0

    if [[ "$assignment" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        _name_ref="${BASH_REMATCH[1]}"
        _value_ref="${BASH_REMATCH[2]}"
        return 0
    fi

    doctor_fix_log WARN "Invalid installer environment assignment: $assignment"
    return 1
}

doctor_fix_build_runtime_env_args() {
    local -n _env_args_ref="$1"
    local extra_env_assignment="${2:-}"
    local env_name=""
    local env_value=""
    local runtime_home=""
    local runtime_path=""
    local runtime_user=""
    local tmpdir_leaf=""
    local tmpdir_prefix=""

    _env_args_ref=()
    runtime_home="$(doctor_fix_runtime_home 2>/dev/null || true)"
    runtime_path="$(doctor_fix_runtime_path 2>/dev/null || true)"
    runtime_user="$(doctor_fix_runtime_user 2>/dev/null || true)"
    if [[ -z "$runtime_home" || -z "$runtime_path" || -z "$runtime_user" ]]; then
        doctor_fix_log WARN "Unable to resolve runtime environment for verified installer"
        return 1
    fi
    doctor_fix_is_valid_username "$runtime_user" || [[ "$runtime_user" == "root" ]] || {
        doctor_fix_log WARN "Invalid runtime user for verified installer: $runtime_user"
        return 1
    }

    # BUN_INSTALL keeps `bun install -g` fixers on ~/.bun/bin (#388).
    _env_args_ref=(
        "TARGET_USER=$runtime_user" \
        "TARGET_HOME=$runtime_home" \
        "HOME=$runtime_home" \
        "PATH=$runtime_path" \
        "BUN_INSTALL=$runtime_home/.bun" \
        "USER=$runtime_user" \
        "LOGNAME=$runtime_user" \
        "LANG=C.UTF-8"
    )
    if [[ -n "$extra_env_assignment" ]]; then
        local env_assignment=""
        while IFS= read -r env_assignment || [[ -n "$env_assignment" ]]; do
            [[ -n "$env_assignment" ]] || continue
            doctor_fix_parse_env_assignment "$env_assignment" env_name env_value || return $?
            if [[ -n "$env_name" ]]; then
                case "$env_name" in
                    TMPDIR)
                        tmpdir_prefix="$runtime_home/.cache/acfs/installer-tmp/"
                        tmpdir_leaf="${env_value#"$tmpdir_prefix"}"
                        if [[ "$env_value" != "$tmpdir_prefix"* ]] \
                            || [[ -z "$tmpdir_leaf" || "$tmpdir_leaf" == */* ]] \
                            || [[ "$tmpdir_leaf" == "." || "$tmpdir_leaf" == ".." ]] \
                            || [[ "$tmpdir_leaf" == *[!A-Za-z0-9._-]* ]]; then
                            doctor_fix_log WARN "Refusing installer TMPDIR outside the ACFS runtime cache"
                            return 1
                        fi
                        ;;
                    RU_NON_INTERACTIVE|AM_INSTALL_SKIP_MCP_SETUP|AM_INSTALL_SKIP_REMOTE_HTTP_READINESS)
                        if [[ "$env_value" != "1" ]]; then
                            doctor_fix_log WARN "Refusing invalid installer environment value for $env_name"
                            return 1
                        fi
                        ;;
                    CLAUDE_CONFIG_DIR)
                        if [[ "$env_value" != /* || "$env_value" == / || "$env_value" == *$'\n'* || "$env_value" == *$'\r'* ]]; then
                            doctor_fix_log WARN "Refusing an invalid Claude configuration directory"
                            return 1
                        fi
                        ;;
                    *)
                        doctor_fix_log WARN "Refusing unsupported installer environment variable: $env_name"
                        return 1
                        ;;
                esac
                _env_args_ref+=("$env_name=$env_value")
            fi
        done <<< "$extra_env_assignment"
    fi
}

doctor_fix_build_runtime_command() {
    local -n _runtime_command_ref="$1"
    shift
    local extra_env_assignment="${1:-}"
    shift
    local env_bin=""
    local runuser_bin=""
    local runtime_user=""
    local sudo_bin=""
    local current_user=""
    local -a env_args=()

    _runtime_command_ref=()
    [[ $# -gt 0 ]] || {
        doctor_fix_log WARN "doctor_fix_run_in_runtime_context requires a command"
        return 1
    }

    env_bin="$(doctor_fix_system_binary_path env 2>/dev/null || true)"
    [[ -n "$env_bin" ]] || {
        doctor_fix_log WARN "Unable to locate env for target-user command"
        return 1
    }

    doctor_fix_build_runtime_env_args env_args "$extra_env_assignment" || return $?

    runtime_user="${env_args[0]#TARGET_USER=}"
    current_user="$(doctor_fix_current_user 2>/dev/null || true)"
    if [[ "$current_user" == "$runtime_user" ]]; then
        _runtime_command_ref=("$env_bin" -i "${env_args[@]}" "$@")
        return 0
    fi

    runuser_bin="$(doctor_fix_system_binary_path runuser 2>/dev/null || true)"
    if [[ $EUID -eq 0 && -n "$runuser_bin" ]]; then
        _runtime_command_ref=("$runuser_bin" -u "$runtime_user" -- "$env_bin" -i "${env_args[@]}" "$@")
        return 0
    fi

    sudo_bin="$(doctor_fix_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        _runtime_command_ref=("$sudo_bin" -n -u "$runtime_user" "$env_bin" -i "${env_args[@]}" "$@")
        return 0
    fi

    doctor_fix_log WARN "Unable to run command as $runtime_user without passwordless sudo or root runuser"
    return 1
}

doctor_fix_run_in_runtime_context() {
    local -a runtime_command=()
    doctor_fix_build_runtime_command runtime_command "$@" || return $?
    "${runtime_command[@]}"
}

doctor_fix_run_verified_installer_with_env() {
    if [[ $# -lt 1 ]]; then
        doctor_fix_log WARN "doctor_fix_run_verified_installer_with_env requires a tool name"
        return 1
    fi

    local tool="$1"
    local installer_env_assignment=""
    shift
    if [[ $# -gt 0 ]]; then
        installer_env_assignment="$1"
        shift
    fi
    local bash_bin=""
    local verified_installer_file=""
    local status=0

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

    bash_bin="$(acfs_security_required_binary_path bash)" || return $?
    acfs_stage_verified_installer verified_installer_file "$url" "$expected_sha256" "$tool" || return $?

    if doctor_fix_run_in_runtime_context "$installer_env_assignment" "$bash_bin" "$verified_installer_file" "$@"; then
        status=0
    else
        status=$?
    fi

    _acfs_remove_temp_files "$verified_installer_file"
    return "$status"
}

doctor_fix_run_verified_installer() {
    if [[ $# -lt 1 ]]; then
        doctor_fix_log WARN "doctor_fix_run_verified_installer requires a tool name"
        return 1
    fi

    local tool="$1"
    shift

    doctor_fix_run_verified_installer_with_env "$tool" "" "$@"
}

doctor_fix_prepare_target_installer_tmpdir() {
    local tool="${1:-}"
    local runtime_home=""

    [[ -n "$tool" ]] || {
        doctor_fix_log WARN "doctor_fix_prepare_target_installer_tmpdir requires a tool name"
        return 1
    }
    case "$tool" in
        .|..|*[!A-Za-z0-9._+-]*)
            doctor_fix_log WARN "Invalid tool name for installer TMPDIR: $tool"
            return 1
            ;;
    esac

    runtime_home="$(doctor_fix_runtime_home 2>/dev/null || true)"
    if [[ -z "$runtime_home" || "$runtime_home" != /* || "$runtime_home" == "/" ]]; then
        doctor_fix_log WARN "Cannot prepare installer TMPDIR without a valid runtime home"
        return 1
    fi

    doctor_fix_require_security || return 1
    acfs_prepare_installer_tmpdir "$runtime_home" "$tool" \
        doctor_fix_run_in_runtime_context ""
}

# Remove one per-run TMPDIR made by doctor_fix_prepare_target_installer_tmpdir.
# Only "<runtime home>/.cache/acfs/installer-tmp/<tool>.<mktemp suffix>"
# qualifies; anything else is left in place. Removal runs in the runtime
# (target-user) context.
doctor_fix_remove_target_installer_tmpdir() {
    local tool="${1:-}"
    local tmpdir="${2:-}"
    local runtime_home=""
    local tmpdir_parent=""
    local tmpdir_suffix=""
    local rm_bin=""

    case "$tool" in
        ""|.|..|*[!A-Za-z0-9._+-]*)
            doctor_fix_log WARN "Invalid tool name for installer TMPDIR cleanup: $tool"
            return 1
            ;;
    esac

    runtime_home="$(doctor_fix_runtime_home 2>/dev/null || true)"
    if [[ -z "$runtime_home" || "$runtime_home" != /* || "$runtime_home" == "/" ]]; then
        doctor_fix_log WARN "Cannot clean installer TMPDIR without a valid runtime home: $tmpdir"
        return 1
    fi

    tmpdir_parent="$runtime_home/.cache/acfs/installer-tmp"
    tmpdir_suffix="${tmpdir#"$tmpdir_parent/$tool."}"
    if [[ "$tmpdir" != "$tmpdir_parent/$tool."* || -z "$tmpdir_suffix" \
        || "$tmpdir_suffix" == *[!A-Za-z0-9]* || -L "$tmpdir_parent" || -L "$tmpdir" ]]; then
        doctor_fix_log WARN "Leaving installer TMPDIR that does not match its template: $tmpdir"
        return 1
    fi

    rm_bin="$(doctor_fix_system_binary_path rm 2>/dev/null || true)"
    if [[ -z "$rm_bin" ]]; then
        doctor_fix_log WARN "Trusted rm not found; leaving installer TMPDIR: $tmpdir"
        return 1
    fi
    if ! doctor_fix_run_in_runtime_context "" "$rm_bin" -rf --one-file-system -- "$tmpdir"; then
        doctor_fix_log WARN "Failed to remove installer TMPDIR: $tmpdir"
        return 1
    fi
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
        if ! backup_json=$(create_backup "$target_file" "path-ordering"); then
            doctor_fix_log ERROR "Failed to back up $target_file before changing PATH ordering"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi
        restore_command="$(autofix_backup_restore_command "$backup_json" 2>/dev/null || true)"
        if [[ -z "$restore_command" ]]; then
            doctor_fix_log ERROR "Failed to build a restore command for $target_file"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi
    else
        restore_command="$(doctor_fix_build_remove_path_rollback \
            "$target_file" \
            "$(doctor_fix_nearest_existing_parent "$target_file")")" || {
            doctor_fix_log ERROR "Failed to build rollback command for new file $target_file"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        }
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
        if ! doctor_fix_run_rollback_command "$restore_command" false; then
            doctor_fix_log ERROR "Failed to restore $target_file after the append failure"
        fi
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Record change
    if ! doctor_fix_record_change_or_rollback \
        "$restore_command" \
        false \
        "path" "Added PATH ordering to $target_file" \
        "$restore_command" \
        false "info" "$(doctor_fix_files_json "$target_file")" "$(doctor_fix_backups_json_array "${backup_json:-[]}")" "[]"; then
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

# Build a reusable target-account command so probe, repair and serialized undo
# all carry the same privilege and configuration boundary. Only a same-account
# caller can intentionally select a custom Claude configuration directory.
doctor_fix_build_dcg_hook_command() {
    local result_name="$1" duration="$2"
    shift 2
    local dcg_bin="" runtime_home="" runtime_user="" current_user=""
    local config_dir="" extra_env="" timeout_bin=""
    local -a bounded=()
    dcg_bin="$(doctor_fix_binary_path dcg 2>/dev/null || true)"
    runtime_home="$(doctor_fix_runtime_home 2>/dev/null || true)"
    runtime_user="$(doctor_fix_runtime_user 2>/dev/null || true)"
    current_user="$(doctor_fix_current_user 2>/dev/null || true)"
    [[ -n "$dcg_bin" && -n "$runtime_home" && -n "$runtime_user" ]] || return 1
    if [[ "$runtime_user" == "$current_user" && -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
        case "$CLAUDE_CONFIG_DIR" in
            '~') config_dir="$runtime_home" ;;
            \~/*) config_dir="$runtime_home/${CLAUDE_CONFIG_DIR#\~/}" ;;
            /*) config_dir="$CLAUDE_CONFIG_DIR" ;;
            *) config_dir="$PWD/$CLAUDE_CONFIG_DIR" ;;
        esac
        # The shared environment API accepts multiple newline-separated
        # assignments. A literal path must remain one value before entering it.
        [[ "$config_dir" != *$'\n'* && "$config_dir" != *$'\r'* ]] || return 1
        extra_env="CLAUDE_CONFIG_DIR=$config_dir"
    fi
    timeout_bin="$(doctor_fix_system_binary_path timeout 2>/dev/null || true)"
    [[ -z "$timeout_bin" ]] || bounded=("$timeout_bin" --kill-after=5s "$duration")
    doctor_fix_build_runtime_command "$result_name" "$extra_env" "${bounded[@]}" "$dcg_bin" "$@"
}

dcg_hook_already_installed() {
    local doctor_json="" jq_bin=""
    local -a probe_command=()
    doctor_fix_build_dcg_hook_command probe_command 15s doctor --format json || return 1
    doctor_json="$("${probe_command[@]}" 2>/dev/null)" || return 1
    [[ -n "$doctor_json" ]] || return 1

    jq_bin="$(doctor_fix_system_binary_path jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        printf '%s' "$doctor_json" | "$jq_bin" -e '
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
    local dcg_uninstall_cmd=""
    local rollback_requires_root=false
    local current_user="" runtime_user="" id_bin="" undo_guard=""
    local -a install_command=() uninstall_command=()

    # Prepare both operations before any target binary executes. Missing
    # account transport must never fall through to running it as the caller.
    if ! doctor_fix_build_dcg_hook_command install_command 60s install \
        || ! doctor_fix_build_dcg_hook_command uninstall_command 60s uninstall; then
        doctor_fix_log ERROR "Cannot run the DCG hook repair in the target account"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
    printf -v dcg_uninstall_cmd '%q ' "${uninstall_command[@]}"
    current_user="$(doctor_fix_current_user)"
    runtime_user="$(doctor_fix_runtime_user)"
    if [[ "$current_user" == "$runtime_user" ]]; then
        # A same-account repair needs no transport at install time. Its saved
        # undo may later be replayed under sudo, so HOME/USER alone cannot grant
        # permission to execute the user-owned binary. Refuse a changed actor;
        # the original account can still undo without elevated privileges.
        id_bin="$(doctor_fix_system_binary_path id 2>/dev/null || true)"
        if [[ -z "$id_bin" ]]; then
            doctor_fix_log ERROR "Cannot verify the account for DCG hook undo"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi
        printf -v undo_guard '[ "$(%q -un)" = %q ] || { printf %q >&2; exit 1; }; ' \
            "$id_bin" "$runtime_user" "Refusing DCG undo as a different account; run acfs undo as $runtime_user without sudo."$'\n'
        dcg_uninstall_cmd="$undo_guard$dcg_uninstall_cmd"
    elif [[ $EUID -eq 0 ]]; then
        rollback_requires_root=true
    fi

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
    if "${install_command[@]}" 2>/dev/null; then
        if ! doctor_fix_record_change_or_rollback \
            "$dcg_uninstall_cmd" \
            "$rollback_requires_root" \
            "hook" "Installed DCG pre-tool-use hook" \
            "$dcg_uninstall_cmd" \
            "$rollback_requires_root" "info" "[]" "[]" "[]"; then
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

    # Guard: nothing must exist at the target path. Test -L as well as -e so a
    # pre-existing *broken* user symlink (which -e reports as absent) is left
    # untouched: otherwise `ln -s` below fails with "File exists" and its
    # failure rollback would `rm -f` a symlink this fixer never created,
    # violating the "never deletes user files" guarantee with no backup.
    if [[ -e "$symlink" || -L "$symlink" ]]; then
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
        if ! backup_json=$(create_backup "$zshrc" "acfs-sourcing"); then
            doctor_fix_log ERROR "Failed to back up $zshrc before adding ACFS sourcing"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi
        restore_command="$(autofix_backup_restore_command "$backup_json" 2>/dev/null || true)"
        if [[ -z "$restore_command" ]]; then
            doctor_fix_log ERROR "Failed to build a restore command for $zshrc"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi
    else
        restore_command="$(doctor_fix_build_remove_path_rollback \
            "$zshrc" \
            "$(doctor_fix_nearest_existing_parent "$zshrc")")" || {
            doctor_fix_log ERROR "Failed to build rollback command for new file $zshrc"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        }
    fi

    # Append sourcing line
    if ! {
        echo ""
        echo "$marker"
        echo "$source_line"
    } >> "$zshrc"; then
        doctor_fix_log ERROR "Failed to append ACFS sourcing to $zshrc"
        if ! doctor_fix_run_rollback_command "$restore_command" false; then
            doctor_fix_log ERROR "Failed to restore $zshrc after the append failure"
        fi
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Record change
    if ! doctor_fix_record_change_or_rollback \
        "$restore_command" \
        false \
        "config" "Added ACFS sourcing to .zshrc" \
        "$restore_command" \
        false "info" "$(doctor_fix_files_json "$zshrc")" "$(doctor_fix_backups_json_array "${backup_json:-[]}")" "[]"; then
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

# Pure selection helpers: neither validation nor membership may start an undo
# session, write logs, or run a fixer. Keep matching literal so a selector can
# never widen into a shell glob or accidentally select a similarly named tool.
doctor_fix_check_selected() {
    local check_id="${1:-}"
    local selector=""

    [[ ${#DOCTOR_FIX_ONLY_SELECTORS[@]} -gt 0 ]] || return 0
    for selector in "${DOCTOR_FIX_ONLY_SELECTORS[@]}"; do
        if [[ "$selector" == *.* ]]; then
            [[ "$check_id" == "$selector" ]] && return 0
        elif [[ "$check_id" == "$selector".* ]]; then
            return 0
        fi
    done
    return 1
}

# Validate against every observed check, including healthy and skipped checks.
# No match is a typo or a check unavailable in this diagnostic mode, not
# permission to fall back to repairing the entire installation.
doctor_fix_validate_selection() {
    local selector=""
    local check_id=""
    local matched=false
    local validation_status=0

    for selector in "${DOCTOR_FIX_ONLY_SELECTORS[@]}"; do
        matched=false
        for check_id in "$@"; do
            if [[ "$selector" == *.* ]]; then
                [[ "$check_id" == "$selector" ]] || continue
            else
                [[ "$check_id" == "$selector".* ]] || continue
            fi
            matched=true
            break
        done
        if [[ "$matched" != true ]]; then
            printf 'Error: --only selector %s did not match any doctor check; use an exact check ID or category from this run (deep checks require --deep).\n' "$selector" >&2
            validation_status=2
        fi
    done
    return "$validation_status"
}

# Called by Doctor only after an installed command failed its bounded probe.
# This records policy, not a repair: selection and warning opt-in still apply
# later in dispatch_fix, after the complete diagnostic pass is validated.
doctor_fix_mark_failed_command() {
    local check_id="$1"
    local existing_id=""
    for existing_id in "${DOCTOR_FIX_FAILED_COMMAND_IDS[@]}"; do
        [[ "$existing_id" == "$check_id" ]] && return 0
    done
    DOCTOR_FIX_FAILED_COMMAND_IDS+=("$check_id")
}

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

    if ! doctor_fix_check_selected "$check_id"; then
        FIX_FILTERED=$((FIX_FILTERED + 1))
        return 0
    fi

    # A WARN is advisory ("optional tool not installed", "service not
    # running", "ssh keepalive not set"). Several of the fixers behind those
    # ids run curl|bash installers, repair the Agent Mail database, or edit
    # sshd_config with sudo — far more than the config-level fixes the docs
    # promise for a bare --fix. Apply them only when the caller opted in.
    if [[ "$check_status" == "warn" ]] && [[ "${DOCTOR_FIX_YES:-false}" != "true" ]]; then
        local warning_retry="acfs doctor --fix --yes"
        local warning_selector=""
        for warning_selector in "${DOCTOR_FIX_ONLY_SELECTORS[@]}"; do
            warning_retry+=" --only $warning_selector"
        done
        doctor_fix_log INFO "$check_id: warning left as-is (run '$warning_retry' to apply warning-level fixes)"
        return 0
    fi

    local failed_command_id=""
    for failed_command_id in "${DOCTOR_FIX_FAILED_COMMAND_IDS[@]}"; do
        [[ "$failed_command_id" == "$check_id" ]] || continue
        FIXES_MANUAL+=("$check_id|Installed command failed verification; inspect or reinstall it before retrying Doctor|$fix_hint")
        FIX_MANUAL=$((FIX_MANUAL + 1))
        doctor_fix_log WARN "$check_id: installed command failed verification; manual repair required"
        return 0
    done

    case "$check_id" in
        # PATH fixes
        path.*)
            fix_path_ordering "$check_id"
            ;;

        # Config file copies. SCRIPT_DIR/../../acfs/* only exists in a repo
        # checkout; an installed tree (~/.acfs/scripts/lib) has no sibling
        # asset directory — there the missing file IS the asset, so route to
        # `acfs update` instead of failing a copy from a bogus path.
        config.acfs_zshrc|config.tmux)
            local cfg_rel="zsh/acfs.zshrc"
            [[ "$check_id" == "config.tmux" ]] && cfg_rel="tmux/tmux.conf"
            local cfg_src="${SCRIPT_DIR:-}/../../acfs/$cfg_rel"
            if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "$cfg_src" ]]; then
                fix_config_copy "$check_id" "$cfg_src" \
                    "$(doctor_fix_runtime_acfs_home)/$cfg_rel"
            else
                FIXES_MANUAL+=("$check_id|Source asset not available from this install|Run: acfs update")
                FIX_MANUAL=$((FIX_MANUAL + 1))
            fi
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
        stack.ntm)
            fix_verified_install "$check_id" "ntm" "ntm"
            ;;
        stack.ubs|stack.ultimate_bug_scanner|stack.ultimate_bug_scanner.*)
            fix_verified_install "$check_id" "ubs" "ubs" --easy-mode
            ;;
        stack.beads_viewer|stack.bv)
            fix_verified_install "$check_id" "bv" "bv"
            ;;
        stack.beads_rust|stack.beads_rust.*)
            fix_verified_install "$check_id" "br" "br"
            ;;
        stack.cass)
            fix_verified_install_with_target_tmpdir "$check_id" "cass" "cass" --easy-mode --verify
            ;;
        stack.cm|stack.cm.*)
            fix_verified_install "$check_id" "cm" "cm" --easy-mode --verify
            ;;
        stack.caam)
            fix_verified_install "$check_id" "caam" "caam"
            ;;
        stack.ru)
            fix_verified_install_with_env "$check_id" "ru" "ru" "RU_NON_INTERACTIVE=1"
            ;;
        stack.rch)
            fix_verified_install "$check_id" "rch" "rch" --easy-mode
            ;;
        stack.dcg|stack.dcg.*)
            local claude_fix_hint="Install Claude Code first, then re-run acfs doctor --fix"
            if ! doctor_fix_binary_path dcg >/dev/null 2>&1; then
                fix_verified_install "$check_id" "dcg" "dcg" --easy-mode || return $?
            fi
            if doctor_fix_binary_path claude >/dev/null 2>&1; then
                fix_dcg_hook "$check_id"
            else
                if declare -f fix_for_module >/dev/null 2>&1; then
                    claude_fix_hint="$(fix_for_module "agents.claude")"
                fi
                FIXES_MANUAL+=("$check_id|Install Claude Code before registering the DCG hook|$claude_fix_hint")
                FIX_MANUAL=$((FIX_MANUAL + 1))
                return 0
            fi
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

        # Atuin daemon socket: pin socket_path and (re)start the daemon (#358, #404)
        shell.atuin_daemon)
            fix_atuin_daemon_socket "$check_id"
            ;;

        # bun global installs stranded in the XDG cache fallback dir (#388)
        bun.global_bin_dir)
            fix_bun_global_bin_dir "$check_id"
            ;;

        # Agent CLI tools (fixes #213)
        agent.claude)
            fix_verified_install "$check_id" "claude" "claude"
            ;;
        agent.codex)
            fix_stack_install "$check_id" "codex" \
                "bun install -g --trust @openai/codex@latest"
            ;;
        agent.antigravity)
            fix_verified_install "$check_id" "agy" "antigravity"
            ;;
        agent.gemini)
            fix_stack_install "$check_id" "gemini" \
                "bun install -g --trust @google/gemini-cli@latest"
            ;;

        # Agent aliases/functions (fixes #163). The agent.alias.* checks grep
        # the shipped ~/.acfs/zsh/acfs.zshrc for the alias definition itself;
        # fix_acfs_sourcing only ensures ~/.zshrc sources that file and cannot
        # add a missing alias to it — only refreshing ~/.acfs (acfs update)
        # can. Report the hint as a manual fix instead of running an
        # irrelevant fixer and counting the warn as repaired.
        agent.alias.*)
            if [[ -n "$fix_hint" ]]; then
                FIXES_MANUAL+=("$check_id|Requires manual action|$fix_hint")
            fi
            FIX_MANUAL=$((FIX_MANUAL + 1))
            return 0
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
    local bash_bin=""

    runtime_home="$(doctor_fix_runtime_home)"
    if [[ -z "$runtime_home" ]]; then
        doctor_fix_log ERROR "Failed to resolve runtime environment for $binary_name install"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
    bash_bin="$(doctor_fix_system_binary_path bash 2>/dev/null || true)"
    if [[ -z "$bash_bin" ]]; then
        doctor_fix_log ERROR "Failed to resolve trusted Bash for $binary_name install"
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
        doctor_fix_run_in_runtime_context "" \
            "$bash_bin" --noprofile --norc -p -c "$install_cmd"
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

# ============================================================
# Fixer: bun global installs stranded off PATH (fix.bun.global_bin_dir, #388)
# ============================================================

# Reinstall, with BUN_INSTALL pinned to ~/.bun, every package whose binaries
# a `bun install -g` left in bun's XDG cache fallback dir (~/.cache/.bun/bin)
# instead of the ~/.bun/bin ACFS puts on PATH. The stranded copies are never
# moved or deleted: the reinstall is what makes the tool reachable, and the
# leftovers are inert.
fix_bun_global_bin_dir() {
    local check_id="$1"
    local runtime_home=""
    local bash_bin=""
    local bun_bin=""
    local expected_dir=""
    local stranded=""
    local path=""
    local package=""
    local name=""
    local -a packages=()
    local -a names=()
    local -a installed_paths=()
    local failed=0

    if ! declare -f doctor_bun_stranded_global_binaries >/dev/null 2>&1; then
        doctor_fix_log WARN "$check_id: stranded-binary scan unavailable (doctor.sh not loaded)"
        FIX_SKIPPED=$((FIX_SKIPPED + 1))
        return 0
    fi

    runtime_home="$(doctor_fix_runtime_home)"
    bash_bin="$(doctor_fix_system_binary_path bash 2>/dev/null || true)"
    bun_bin="$(doctor_fix_binary_path bun 2>/dev/null || true)"
    if [[ -z "$runtime_home" || -z "$bash_bin" || -z "$bun_bin" ]]; then
        doctor_fix_log ERROR "$check_id: cannot resolve runtime home, bash, or bun for the reinstall"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
    expected_dir="$runtime_home/.bun/bin"

    stranded="$(doctor_bun_stranded_global_binaries 2>/dev/null || true)"
    while IFS=$'\t' read -r path package; do
        [[ -n "$path" && -n "$package" ]] || continue
        # Only a well-formed npm name is ever passed to bun.
        [[ "$package" =~ ^(@[A-Za-z0-9][A-Za-z0-9._-]*/)?[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || continue
        names+=("${path##*/}")
        case " ${packages[*]:-} " in
            *" $package "*) ;;
            *) packages+=("$package") ;;
        esac
    done <<< "$stranded"

    if [[ ${#packages[@]} -eq 0 ]]; then
        doctor_fix_log INFO "$check_id: no stranded bun global installs found"
        return 0
    fi

    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.bun.global_bin_dir|Reinstall ${packages[*]} into $expected_dir|$expected_dir|BUN_INSTALL=\"\$HOME/.bun\" bun install -g --trust ${packages[*]}")
        doctor_fix_log DRY "Reinstall ${packages[*]} with BUN_INSTALL=$runtime_home/.bun"
        return 0
    fi

    # doctor_fix_run_in_runtime_context exports BUN_INSTALL=<home>/.bun, so
    # bun resolves its global bin dir to $expected_dir regardless of the
    # caller's XDG_CACHE_HOME.
    for package in "${packages[@]}"; do
        if (
            cd "$runtime_home" &&
            doctor_fix_run_in_runtime_context "" \
                "$bash_bin" --noprofile --norc -c '"$1" install -g --trust "$2"' _ "$bun_bin" "$package"
        ) >/dev/null 2>&1; then
            doctor_fix_log INFO "$check_id: reinstalled $package into $expected_dir"
        else
            doctor_fix_log ERROR "$check_id: bun install -g $package failed"
            failed=$((failed + 1))
        fi
    done

    hash -r
    for name in "${names[@]}"; do
        if [[ -x "$expected_dir/$name" ]]; then
            installed_paths+=("$expected_dir/$name")
        else
            doctor_fix_log ERROR "$check_id: $name is still missing from $expected_dir after the reinstall"
            failed=$((failed + 1))
        fi
    done

    if [[ ${#installed_paths[@]} -gt 0 ]]; then
        if ! doctor_fix_record_change_or_rollback \
            "" \
            false \
            "install" "Reinstalled bun global packages into $expected_dir: ${packages[*]}" \
            "# Manual rollback: remove the reinstalled binaries from $expected_dir if undesired" \
            false "info" "$(doctor_fix_files_json "${installed_paths[@]}")" "[]" "[]"; then
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi
    fi

    if [[ "$failed" -gt 0 ]]; then
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
    FIXES_APPLIED+=("fix.bun.global_bin_dir|Reinstalled ${packages[*]} into $expected_dir")
    FIX_APPLIED=$((FIX_APPLIED + 1))
    return 0
}

fix_verified_install_with_env() {
    local check_id="$1"
    local binary_name="$2"
    local tool="$3"
    local installer_env_assignment="$4"
    shift 4
    local args=("$@")
    local args_display="${args[*]:-}"
    local dry_run_env_display=""
    local installed_path=""
    local rollback_command=""

    installed_path="$(doctor_fix_binary_path "$binary_name" 2>/dev/null || true)"
    if [[ -n "$installed_path" ]]; then
        if [[ "$binary_name" == "bv" && "$installed_path" == *"/google-cloud-sdk/"* ]]; then
            installed_path=""
        else
            doctor_fix_log INFO "$binary_name already installed"
            return 0
        fi
    fi

    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        [[ -n "$installer_env_assignment" ]] && dry_run_env_display="${installer_env_assignment} "
        FIXES_DRY_RUN+=("fix.stack.$binary_name|Install $binary_name via verified installer|~/.local/bin/$binary_name|verified:$tool ${dry_run_env_display}${args_display}")
        doctor_fix_log DRY "Install $binary_name via verified installer"
        return 0
    fi

    if doctor_fix_run_verified_installer_with_env "$tool" "$installer_env_assignment" "${args[@]}" >/dev/null 2>&1; then
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

fix_verified_install_with_target_tmpdir() {
    local check_id="$1"
    local binary_name="$2"
    local tool="$3"
    shift 3
    local installer_tmpdir=""
    local fix_status=0

    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        installer_tmpdir="$(doctor_fix_runtime_home)/.cache/acfs/installer-tmp/${tool}.XXXXXX"
        fix_verified_install_with_env "$check_id" "$binary_name" "$tool" "TMPDIR=$installer_tmpdir" "$@"
        return $?
    fi

    installer_tmpdir="$(doctor_fix_prepare_target_installer_tmpdir "$tool")" || {
        doctor_fix_log ERROR "Failed to prepare installer TMPDIR for $binary_name"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    }

    fix_verified_install_with_env "$check_id" "$binary_name" "$tool" "TMPDIR=$installer_tmpdir" "$@" || fix_status=$?
    doctor_fix_remove_target_installer_tmpdir "$tool" "$installer_tmpdir" || true
    return "$fix_status"
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
        if [[ "$binary_name" == "bv" && "$installed_path" == *"/google-cloud-sdk/"* ]]; then
            installed_path=""
        else
            doctor_fix_log INFO "$binary_name already installed"
            return 0
        fi
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

# True when the host booted with systemd as init (sd_booted semantics).
doctor_fix_systemd_booted() {
    [[ -d /run/systemd/system ]]
}

# Install and enable SSH server
fix_ssh_server() {
    local check_id="$1"
    local apt_get_bin=""
    local env_bin=""
    local root_display=""
    local sshd_bin=""
    local systemctl_bin=""
    local sshd_config="${DOCTOR_FIX_SSHD_CONFIG:-/etc/ssh/sshd_config}"
    local -a root_cmd=()

    root_display="$(doctor_fix_root_display_prefix)"
    sshd_bin="$(doctor_fix_system_binary_path sshd 2>/dev/null || true)"
    systemctl_bin="$(doctor_fix_system_binary_path systemctl 2>/dev/null || true)"

    # Guard: Check if already installed
    if [[ -n "$sshd_bin" ]] || [[ -f "$sshd_config" ]]; then
        # Check if running
        if [[ -n "$systemctl_bin" ]] && doctor_fix_systemd_booted; then
            if "$systemctl_bin" is-active --quiet ssh 2>/dev/null || "$systemctl_bin" is-active --quiet sshd 2>/dev/null; then
                doctor_fix_log INFO "SSH server already installed and running"
                return 0
            fi

            # Installed but not running - enable and start
            if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
                FIXES_DRY_RUN+=("fix.ssh.server|Enable and start SSH server|/etc/ssh/sshd_config|${root_display}systemctl enable --now ssh")
                doctor_fix_log DRY "Enable and start SSH server"
                return 0
            fi

            if ! doctor_fix_root_prefix root_cmd; then
                doctor_fix_log ERROR "Cannot start SSH server without root or passwordless sudo"
                FIX_FAILED=$((FIX_FAILED + 1))
                return 1
            fi

            if "${root_cmd[@]}" "$systemctl_bin" enable --now ssh 2>/dev/null || "${root_cmd[@]}" "$systemctl_bin" enable --now sshd 2>/dev/null; then
                if ! doctor_fix_record_change_or_rollback \
                    "$(printf '%q disable --now ssh 2>/dev/null || %q disable --now sshd 2>/dev/null || true' "$systemctl_bin" "$systemctl_bin")" \
                    true \
                    "service" "Enabled and started SSH server" \
                    "$(printf '%q disable --now ssh 2>/dev/null || %q disable --now sshd 2>/dev/null || true' "$systemctl_bin" "$systemctl_bin")" \
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
        FIXES_DRY_RUN+=("fix.ssh.server|Install openssh-server|/etc/ssh/sshd_config|$(doctor_fix_ssh_server_install_display "$root_display")")
        doctor_fix_log DRY "Install openssh-server"
        return 0
    fi

    local package_manager_bin=""
    local ssh_package="openssh-server"
    local -a install_argv=()
    env_bin="$(doctor_fix_system_binary_path env 2>/dev/null || true)"
    if doctor_fix_is_arch_family; then
        ssh_package="openssh"
        package_manager_bin="$(doctor_fix_system_binary_path pacman 2>/dev/null || true)"
        install_argv=("$package_manager_bin" -S --needed --noconfirm "$ssh_package")
    else
        apt_get_bin="$(doctor_fix_system_binary_path apt-get 2>/dev/null || true)"
        package_manager_bin="$apt_get_bin"
        install_argv=("$apt_get_bin" -o DPkg::Lock::Timeout=120 install -y "$ssh_package")
    fi
    if [[ -z "$package_manager_bin" ]]; then
        doctor_fix_log ERROR "No supported package manager (apt-get/pacman) found; cannot install the SSH server"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
    if [[ -z "$systemctl_bin" ]]; then
        doctor_fix_log ERROR "systemctl not found; cannot enable SSH server"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
    if [[ -z "$env_bin" ]]; then
        doctor_fix_log ERROR "env not found; cannot set the noninteractive package environment"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
    if ! doctor_fix_root_prefix root_cmd; then
        doctor_fix_log ERROR "Cannot install $ssh_package without root or passwordless sudo"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    if "${root_cmd[@]}" "$env_bin" DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 "${install_argv[@]}" 2>/dev/null; then
        if ! ("${root_cmd[@]}" "$systemctl_bin" enable --now ssh 2>/dev/null || "${root_cmd[@]}" "$systemctl_bin" enable --now sshd 2>/dev/null); then
            doctor_fix_log ERROR "Installed $ssh_package but failed to enable/start SSH service"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi

        if ! doctor_fix_record_change_or_rollback \
            "" \
            false \
            "install" "Installed and enabled $ssh_package" \
            "# Manual rollback required: remove $ssh_package if undesired" \
            true "info" "[\"/etc/ssh/sshd_config\"]" "[]" "[]"; then
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi

        doctor_fix_log INFO "Installed and enabled $ssh_package"
        FIXES_APPLIED+=("fix.ssh.server|Installed and enabled $ssh_package")
        FIX_APPLIED=$((FIX_APPLIED + 1))
        return 0
    fi

    doctor_fix_log ERROR "Failed to install $ssh_package"
    FIX_FAILED=$((FIX_FAILED + 1))
    return 1
}

# ============================================================
# Fixer: Atuin daemon socket (fix.atuin.daemon_socket)
# ============================================================

# Read daemon.socket_path from an atuin config.toml (empty when not pinned).
doctor_fix_atuin_configured_socket() {
    local config_file="$1"
    [[ -r "$config_file" ]] || return 0
    awk -F'=' '
        /^\[daemon\]/ { in_daemon = 1; next }
        /^\[/ { in_daemon = 0 }
        in_daemon && $1 ~ /^[[:space:]]*socket_path[[:space:]]*$/ {
            v = $2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
            gsub(/^"|"$/, "", v)
            print v
        }
    ' "$config_file" 2>/dev/null | tail -n1
}

# Resolve a configured daemon.socket_path the way atuin >= 18.9 does
# (shellexpand::full: a leading ~, $VAR, ${VAR}), with ~ and HOME as the
# runtime user's home (#460). rc 1 when it names any other variable, whose
# value depends on the environment of whoever reads the config.
# Mirrors doctor_atuin_resolve_socket_path in doctor.sh.
doctor_fix_atuin_resolve_socket_path() {
    local value="${1:-}"
    local home="${2:-}"
    [[ -n "$value" && "$home" == /* ]] || return 1

    # shellcheck disable=SC2088 # matching a literal ~ from the config text
    case "$value" in
        "~") value="$home" ;;
        "~/"*) value="$home/${value:2}" ;;
    esac
    value="${value//'${HOME}'/"$home"}"
    value="${value//'$HOME/'/"$home/"}"
    [[ "$value" != *'$HOME' ]] || value="${value%'$HOME'}$home"
    [[ "$value" != *'$'* ]] || return 1
    printf '%s\n' "$value"
}

# Stop any running atuin daemon. Split out so tests can replace it: the real
# thing signals processes system-wide. The bracketed pattern cannot match the
# command line of a shell that is running this very hint (#404).
doctor_fix_atuin_stop_daemon() {
    local pkill_bin=""
    pkill_bin="$(doctor_fix_system_binary_path pkill 2>/dev/null || true)"
    [[ -n "$pkill_bin" ]] || return 0
    "$pkill_bin" -f '[a]tuin daemon' 2>/dev/null || true
    return 0
}

# Start the atuin daemon detached and wait (up to ~3s) for it to bind the
# expected socket. rc 0 when the socket appears, 1 otherwise.
doctor_fix_atuin_start_daemon() {
    local atuin_bin="$1"
    local socket_path="$2"
    local setsid_bin=""
    setsid_bin="$(doctor_fix_system_binary_path setsid 2>/dev/null || true)"

    # A stale socket file makes the daemon fail to bind; the check already
    # established nothing is listening on it before dispatching here.
    if [[ -S "$socket_path" ]]; then
        rm -f "$socket_path" 2>/dev/null || true
    fi

    if [[ -n "$setsid_bin" ]]; then
        (cd / && "$setsid_bin" "$atuin_bin" daemon >/dev/null 2>&1 < /dev/null &)
    else
        (cd / && "$atuin_bin" daemon >/dev/null 2>&1 < /dev/null &)
    fi

    local attempt=0
    while [[ $attempt -lt 30 ]]; do
        [[ -S "$socket_path" ]] && return 0
        sleep 0.1
        attempt=$((attempt + 1))
    done
    return 1
}

# Pin atuin's daemon socket_path to a TMPDIR-independent path and (re)start the
# daemon so shell and daemon agree on one socket (#358). Same edit the
# installer's _cli_pin_atuin_daemon_socket makes, but journaled for `acfs undo`
# and reachable from `acfs doctor --fix --yes` (#404).
fix_atuin_daemon_socket() {
    local check_id="$1"
    local runtime_home=""
    runtime_home="$(doctor_fix_runtime_home)"
    local config_dir="$runtime_home/.config/atuin"
    local config_file="$config_dir/config.toml"
    local default_socket="$runtime_home/.local/share/atuin/atuin-daemon.sock"
    local atuin_bin=""
    atuin_bin="$(doctor_fix_binary_path atuin 2>/dev/null || true)"

    # Guard: the check only fires with atuin installed and a readable config
    # that enables the daemon; anything else is not ours to repair.
    if [[ -z "$atuin_bin" ]]; then
        doctor_fix_log WARN "atuin not found; cannot repair its daemon socket"
        FIXES_MANUAL+=("$check_id|Install atuin first|acfs update")
        FIX_MANUAL=$((FIX_MANUAL + 1))
        return 1
    fi
    if [[ ! -f "$config_file" ]]; then
        doctor_fix_log INFO "atuin config not found at $config_file; nothing to pin"
        return 0
    fi
    if [[ -L "$config_file" || -L "$config_dir" ]]; then
        doctor_fix_log WARN "Refusing to edit atuin config through a symlink: $config_file"
        FIXES_MANUAL+=("$check_id|Pin daemon.socket_path by hand|set socket_path = \"$default_socket\" under [daemon] in $config_file")
        FIX_MANUAL=$((FIX_MANUAL + 1))
        return 1
    fi

    local configured_socket=""
    configured_socket="$(doctor_fix_atuin_configured_socket "$config_file")"
    local need_pin=false
    [[ -n "$configured_socket" ]] || need_pin=true
    local target_socket="$default_socket"
    # Wait for the path atuin will bind, not the literal config text: a
    # "~/..." value never exists as a file under that name (#460).
    if [[ "$need_pin" != "true" ]] \
        && ! target_socket="$(doctor_fix_atuin_resolve_socket_path "$configured_socket" "$runtime_home")"; then
        doctor_fix_log WARN "atuin daemon.socket_path ($configured_socket) depends on environment variables; not restarting the daemon on a path doctor cannot resolve"
        FIXES_MANUAL+=("$check_id|Pin daemon.socket_path to an absolute path by hand|set socket_path = \"$default_socket\" under [daemon] in $config_file")
        FIX_MANUAL=$((FIX_MANUAL + 1))
        return 1
    fi

    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        if [[ "$need_pin" == "true" ]]; then
            FIXES_DRY_RUN+=("fix.atuin.daemon_socket|Pin atuin daemon socket_path and restart the daemon|$config_file|socket_path = \"$default_socket\"")
            doctor_fix_log DRY "Pin atuin daemon.socket_path to $default_socket in $config_file and restart the daemon"
        else
            FIXES_DRY_RUN+=("fix.atuin.daemon_socket|Restart the atuin daemon on its configured socket|$target_socket|$atuin_bin daemon")
            doctor_fix_log DRY "Restart the atuin daemon so it binds $target_socket"
        fi
        return 0
    fi

    if [[ "$need_pin" == "true" ]]; then
        local backup_json=""
        local restore_command=""
        if ! backup_json=$(create_backup "$config_file" "atuin-daemon-socket"); then
            doctor_fix_log ERROR "Failed to back up $config_file before pinning socket_path"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi
        restore_command="$(autofix_backup_restore_command "$backup_json" 2>/dev/null || true)"
        if [[ -z "$restore_command" ]]; then
            doctor_fix_log ERROR "Failed to build a restore command for $config_file"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi

        # Insert under an existing [daemon] table, else append one. Write an
        # absolute path: atuin expands ~ and $VARS here only from 18.9 on,
        # and an absolute path means the same socket to every version.
        local tmp_config="$config_file.acfs-tmp.$$"
        local wrote=false
        if grep -Eq '^\[daemon\]' "$config_file"; then
            if awk -v sock="$default_socket" '
                { print }
                /^\[daemon\]/ && !done { printf "socket_path = \"%s\"\n", sock; done = 1 }
            ' "$config_file" > "$tmp_config" 2>/dev/null; then
                wrote=true
            fi
        else
            if {
                cat "$config_file"
                printf '\n# Managed by ACFS: pin the daemon socket to a TMPDIR-independent path (#358)\n'
                printf '[daemon]\n'
                printf 'socket_path = "%s"\n' "$default_socket"
            } > "$tmp_config" 2>/dev/null; then
                wrote=true
            fi
        fi
        if [[ "$wrote" != "true" ]] || ! mv -f "$tmp_config" "$config_file" 2>/dev/null; then
            rm -f "$tmp_config" 2>/dev/null || true
            doctor_fix_log ERROR "Failed to write socket_path into $config_file"
            if ! doctor_fix_run_rollback_command "$restore_command" false; then
                doctor_fix_log ERROR "Failed to restore $config_file after the write failure"
            fi
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi

        if ! doctor_fix_record_change_or_rollback \
            "$restore_command" \
            false \
            "config" "Pinned atuin daemon.socket_path to $default_socket" \
            "$restore_command" \
            false "info" "$(doctor_fix_files_json "$config_file")" "$(doctor_fix_backups_json_array "${backup_json:-[]}")" "[]"; then
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi

        doctor_fix_log INFO "Pinned atuin daemon.socket_path to $default_socket"
        FIXES_APPLIED+=("fix.atuin.daemon_socket|Pinned atuin daemon.socket_path to $default_socket")
        FIX_APPLIED=$((FIX_APPLIED + 1))
        target_socket="$default_socket"
    fi

    # Restart so the daemon binds the configured path. Starting a user daemon
    # is not journaled: undoing the config edit and re-running the daemon is
    # the reverse, and there is nothing durable to roll back.
    doctor_fix_atuin_stop_daemon
    if doctor_fix_atuin_start_daemon "$atuin_bin" "$target_socket"; then
        doctor_fix_log INFO "atuin daemon restarted on $target_socket"
        if [[ "$need_pin" != "true" ]]; then
            FIXES_APPLIED+=("fix.atuin.daemon_socket|Restarted the atuin daemon on $target_socket")
            FIX_APPLIED=$((FIX_APPLIED + 1))
        fi
        return 0
    fi

    doctor_fix_log ERROR "atuin daemon did not bind $target_socket within 3s after restart"
    FIXES_MANUAL+=("$check_id|Start the atuin daemon by hand and check its output|$atuin_bin daemon")
    FIX_MANUAL=$((FIX_MANUAL + 1))
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
    # Prefer a drop-in under sshd_config.d: appending to sshd_config lands
    # after any trailing Match block, silently scoping the directives to that
    # Match, and a drop-in is cleanly reversible (rm) instead of needing a
    # whole-file backup restore.
    local sshd_dropin=""
    if [[ -d "${sshd_config%/*}/sshd_config.d" ]] && \
       grep -qE '^[[:space:]]*Include[[:space:]]+.*sshd_config\.d' "$sshd_config" 2>/dev/null; then
        sshd_dropin="${sshd_config%/*}/sshd_config.d/60-acfs-keepalive.conf"
    fi
    local root_display=""
    local systemctl_bin=""
    local tee_bin=""
    local -a root_cmd=()

    root_display="$(doctor_fix_root_display_prefix)"
    systemctl_bin="$(doctor_fix_system_binary_path systemctl 2>/dev/null || true)"
    tee_bin="$(doctor_fix_system_binary_path tee 2>/dev/null || true)"

    # Guard: sshd_config must exist
    if [[ ! -f "$sshd_config" ]]; then
        doctor_fix_log WARN "sshd_config not found, install openssh-server first"
        FIXES_MANUAL+=("$check_id|Install openssh-server first|$(doctor_fix_ssh_server_install_display "$root_display")")
        FIX_MANUAL=$((FIX_MANUAL + 1))
        return 1
    fi

    # Guard: Check if already configured
    if grep -qsE '^[[:space:]]*ClientAliveInterval[[:space:]]+[0-9]+' "$sshd_config" "${sshd_config%/*}/sshd_config.d/"*.conf 2>/dev/null; then
        doctor_fix_log INFO "SSH keepalive already configured"
        return 0
    fi

    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.ssh.keepalive|Configure SSH keepalive|${sshd_dropin:-$sshd_config}|${root_display}tee ${sshd_dropin:-"-a $sshd_config"}")
        doctor_fix_log DRY "Configure SSH keepalive in ${sshd_dropin:-$sshd_config}"
        return 0
    fi

    if [[ -z "$tee_bin" ]]; then
        doctor_fix_log ERROR "tee not found; cannot append SSH keepalive settings"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
    if ! doctor_fix_root_prefix root_cmd; then
        doctor_fix_log ERROR "Cannot configure SSH keepalive without root or passwordless sudo"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Create backup (append path only: a drop-in is a brand-new file whose
    # rollback is simply removing it, no whole-file backup needed)
    local backup_json=""
    local restore_command=""
    if [[ -n "$sshd_dropin" ]]; then
        restore_command="rm -f $(printf '%q' "$sshd_dropin")"
    elif [[ -f "$sshd_config" ]]; then
        if ! backup_json=$(create_backup "$sshd_config" "ssh-keepalive"); then
            doctor_fix_log ERROR "Failed to back up $sshd_config before adding SSH keepalive settings"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi
        restore_command="$(autofix_backup_restore_command "$backup_json" 2>/dev/null || true)"
        if [[ -z "$restore_command" ]]; then
            doctor_fix_log ERROR "Failed to build a restore command for $sshd_config"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi
    fi

    # Apply settings
    local keepalive_target="${sshd_dropin:-$sshd_config}"
    local -a tee_args=(-a "$sshd_config")
    if [[ -n "$sshd_dropin" ]]; then
        tee_args=("$sshd_dropin")
    fi
    if ! {
        echo "$marker"
        echo "ClientAliveInterval 60"
        echo "ClientAliveCountMax 3"
    } | "${root_cmd[@]}" "$tee_bin" "${tee_args[@]}" > /dev/null; then
        doctor_fix_log ERROR "Failed to write SSH keepalive settings to $keepalive_target"
        if ! doctor_fix_run_rollback_command "$restore_command" true; then
            doctor_fix_log ERROR "Failed to restore $keepalive_target after the write failure"
        fi
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Restart sshd to apply
    if [[ -n "$systemctl_bin" ]]; then
        "${root_cmd[@]}" "$systemctl_bin" reload ssh 2>/dev/null || "${root_cmd[@]}" "$systemctl_bin" reload sshd 2>/dev/null || true
    fi

    local reload_rollback=""
    if [[ -n "$systemctl_bin" ]]; then
        reload_rollback="$(printf '%q reload ssh 2>/dev/null || %q reload sshd 2>/dev/null || true' "$systemctl_bin" "$systemctl_bin")"
    else
        reload_rollback="true"
    fi

    if ! doctor_fix_record_change_or_rollback \
        "$restore_command; $reload_rollback" \
        true \
        "config" "Configured SSH keepalive in $keepalive_target" \
        "$restore_command; $reload_rollback" \
        true "info" "$(doctor_fix_files_json "$keepalive_target")" "$(doctor_fix_backups_json_array "${backup_json:-[]}")" "[]"; then
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

doctor_fix_agent_mail_command_path() {
    local command_name="${1:-am}"
    local runtime_home=""
    local primary_bin=""
    local candidate=""

    runtime_home="$(doctor_fix_runtime_home)"
    [[ -n "$runtime_home" ]] || return 1

    primary_bin="$(doctor_fix_runtime_bin_dir)"
    for candidate in \
        "$primary_bin/$command_name" \
        "$runtime_home/.local/bin/$command_name" \
        "$runtime_home/.acfs/bin/$command_name" \
        "$runtime_home/.cargo/bin/$command_name" \
        "$runtime_home/.bun/bin/$command_name" \
        "$runtime_home/.atuin/bin/$command_name" \
        "$runtime_home/go/bin/$command_name"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

doctor_fix_agent_mail_cli_path() {
    doctor_fix_agent_mail_command_path "am"
}

doctor_fix_agent_mail_server_cli_path() {
    doctor_fix_agent_mail_command_path "mcp-agent-mail"
}

doctor_fix_resolve_path_target() {
    local path_value="${1:-}"
    local readlink_bin=""
    local realpath_bin=""

    [[ -n "$path_value" ]] || return 1

    readlink_bin="$(doctor_fix_system_binary_path readlink 2>/dev/null || true)"
    if [[ -n "$readlink_bin" ]] && "$readlink_bin" -f "$path_value" >/dev/null 2>&1; then
        "$readlink_bin" -f "$path_value"
        return 0
    fi

    realpath_bin="$(doctor_fix_system_binary_path realpath 2>/dev/null || true)"
    if [[ -n "$realpath_bin" ]] && "$realpath_bin" "$path_value" >/dev/null 2>&1; then
        "$realpath_bin" "$path_value"
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

# Build every Agent Mail probe and database mutation in the same account and
# configuration context. A drain of the caller's mailbox cannot authorize a
# repair of the installation selected by TARGET_USER/TARGET_HOME.
doctor_fix_build_agent_mail_command() {
    local result_name="$1"
    local am_bin="$2"
    local deadline="$3"
    shift 3
    local runtime_home=""
    local runtime_user=""
    local current_user=""
    local working_dir=""
    local env_bin=""
    local bash_bin=""
    local timeout_bin=""
    local selector=""
    local selector_value=""
    local -a mailbox_env=()

    runtime_home="$(doctor_fix_runtime_home 2>/dev/null || true)"
    runtime_user="$(doctor_fix_runtime_user 2>/dev/null || true)"
    current_user="$(doctor_fix_current_user 2>/dev/null || true)"
    [[ -n "$runtime_home" && -n "$runtime_user" && -n "$current_user" && -n "$am_bin" ]] || return 1
    [[ "$deadline" =~ ^[1-9][0-9]*s$ ]] || return 1

    working_dir="$runtime_home"
    if [[ "$current_user" == "$runtime_user" ]]; then
        # An operator repairing their own mailbox may deliberately select a
        # custom database, archive or XDG directory. Keep relative paths tied
        # to their original directory, without evaluating any shell syntax.
        # With no explicit selectors, always use target HOME: a public account
        # handoff has already changed identity and cleared foreign selectors,
        # but can still retain the caller's inaccessible/project-local CWD.
        for selector in DATABASE_URL STORAGE_ROOT XDG_CONFIG_HOME XDG_DATA_HOME; do
            [[ -v "$selector" ]] || continue
            working_dir="$PWD"
            selector_value="${!selector}"
            if [[ "$selector_value" == *$'\n'* || "$selector_value" == *$'\r'* ]]; then
                doctor_fix_log WARN "Refusing a multiline Agent Mail configuration value for $selector"
                return 1
            fi
            mailbox_env+=("$selector=$selector_value")
        done
    fi

    env_bin="$(doctor_fix_system_binary_path env 2>/dev/null || true)"
    bash_bin="$(doctor_fix_system_binary_path bash 2>/dev/null || true)"
    timeout_bin="$(doctor_fix_system_binary_path timeout 2>/dev/null || true)"
    if [[ -z "$env_bin" || -z "$bash_bin" || -z "$timeout_bin" ]]; then
        doctor_fix_log WARN "Agent Mail repair requires system env, bash and timeout commands"
        return 1
    fi

    # The outer builder drops ambient startup hooks and switches accounts
    # before executing this bounded command. Never inherit a foreign CWD's
    # .env configuration; user-global config is discovered under target HOME.
    doctor_fix_build_runtime_command "$result_name" "" \
        "$timeout_bin" --kill-after=5s "$deadline" \
        "$bash_bin" --noprofile --norc -p -c \
        'cd -- "$1" || exit 1; shift; exec "$@"' -- "$working_dir" \
        "$env_bin" -- "${mailbox_env[@]}" "$am_bin" "$@"
}

doctor_fix_run_agent_mail_command() {
    local -a agent_mail_command=()
    doctor_fix_build_agent_mail_command agent_mail_command "$@" || return $?
    "${agent_mail_command[@]}"
}

doctor_fix_agent_mail_mcp_path() {
    local am_bin="${1:-}"

    if [[ -z "$am_bin" ]]; then
        am_bin="$(doctor_fix_agent_mail_bin 2>/dev/null || true)"
    fi
    [[ -n "$am_bin" ]] || return 1

    local version_output=""
    version_output="$(doctor_fix_run_agent_mail_command "$am_bin" 15s --version 2>/dev/null)" || return 1
    if [[ "$version_output" == am\ * ]]; then
        printf '/mcp/\n'
    else
        printf '/api/\n'
    fi
}
agent_mail_fix_doctor_healthy() {
    local doctor_json=""
    local am_bin=""
    local jq_bin=""
    local -a cmd=()

    am_bin="$(doctor_fix_agent_mail_bin 2>/dev/null || true)"
    [[ -n "$am_bin" ]] || return 1
    cmd=(doctor check --json)

    if [[ $# -gt 0 ]]; then
        cmd+=("$1")
    fi

    doctor_json="$(doctor_fix_run_agent_mail_command "$am_bin" 15s "${cmd[@]}" 2>/dev/null)" || return 1

    [[ -n "$doctor_json" ]] || return 1

    jq_bin="$(doctor_fix_system_binary_path jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        [[ "$(printf '%s' "$doctor_json" | "$jq_bin" -r '.healthy // false' 2>/dev/null)" == "true" ]]
        return $?
    fi

    printf '%s' "$doctor_json" | grep -q '"healthy"[[:space:]]*:[[:space:]]*true'
}

agent_mail_fix_wait_for_health() {
    doctor_fix_source_stack_lib || return 1
    ACFS_STACK_TRUST_TARGET_HOME=true TARGET_USER="$(doctor_fix_runtime_user)" TARGET_HOME="$(doctor_fix_runtime_home)" _stack_wait_for_agent_mail_health
}

agent_mail_fix_readiness_ready() {
    local max_attempts="${1:-4}"
    local attempt=0
    local readiness_body=""
    local readiness_url=""

    while (( attempt < max_attempts )); do
        attempt=$((attempt + 1))
        for readiness_url in \
            http://127.0.0.1:8765/health/readiness \
            http://127.0.0.1:8765/health
        do
            readiness_body="$(doctor_fix_system_curl -fsS --max-time 5 "$readiness_url" 2>/dev/null)" || continue
            if printf '%s\n' "$readiness_body" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ready"([[:space:]]*[,}])'; then
                return 0
            fi
        done
        if (( attempt < max_attempts )); then
            sleep 1
        fi
    done

    return 1
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
    local http_allow_env=""
    local am_bin_exec=""
    local am_mcp_path_exec=""

    am_bin="$(doctor_fix_agent_mail_bin 2>/dev/null || true)"
    [[ -n "$am_bin" ]] || return 1

    db_url="sqlite:///${storage_root}/storage.sqlite3"

    local am_mcp_path=""
    am_mcp_path="$(doctor_fix_agent_mail_mcp_path "$am_bin" 2>/dev/null || true)"
    [[ -n "$am_mcp_path" ]] || return 1

    mkdir -p "$storage_root" "$unit_dir" || return 1
    storage_root_unit="$(doctor_fix_systemd_unit_path_escape "$storage_root")" || return 1
    rust_log_env="$(doctor_fix_systemd_unit_env_assignment RUST_LOG info)" || return 1
    storage_root_env="$(doctor_fix_systemd_unit_env_assignment STORAGE_ROOT "$storage_root")" || return 1
    database_url_env="$(doctor_fix_systemd_unit_env_assignment DATABASE_URL "$db_url")" || return 1
    http_allow_env="$(doctor_fix_systemd_unit_env_assignment HTTP_ALLOW_LOCALHOST_UNAUTHENTICATED true)" || return 1
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
Environment=$http_allow_env
ExecStart=${am_bin_exec} serve-http --no-tui --host 127.0.0.1 --port 8765 --path ${am_mcp_path_exec}
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
    local env_bin=""
    local nohup_bin=""
    local setsid_bin=""

    am_bin="$(doctor_fix_agent_mail_bin 2>/dev/null || true)"
    [[ -n "$am_bin" ]] || return 1

    db_url="sqlite:///${storage_root}/storage.sqlite3"

    local am_mcp_path=""
    am_mcp_path="$(doctor_fix_agent_mail_mcp_path "$am_bin" 2>/dev/null || true)"
    [[ -n "$am_mcp_path" ]] || return 1

    env_bin="$(doctor_fix_lifecycle_binary_path env 2>/dev/null || true)"
    nohup_bin="$(doctor_fix_lifecycle_binary_path nohup 2>/dev/null || true)"
    setsid_bin="$(doctor_fix_system_binary_path setsid 2>/dev/null || true)"
    if [[ -z "$env_bin" || -z "$nohup_bin" ]]; then
        doctor_fix_log ERROR "Cannot launch the Agent Mail fallback because env or nohup is unavailable"
        return 1
    fi

    if doctor_fix_system_curl -fsS --max-time 5 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1 && \
       agent_mail_fix_readiness_ready; then
        return 0
    fi

    if [[ -f "$fallback_pid_file" ]]; then
        agent_mail_fix_stop_fallback || return 1
    fi

    if [[ -n "$setsid_bin" ]]; then
        "$setsid_bin" "$nohup_bin" "$env_bin" \
            RUST_LOG=info \
            STORAGE_ROOT="$storage_root" \
            DATABASE_URL="$db_url" \
            HTTP_ALLOW_LOCALHOST_UNAUTHENTICATED=true \
            "$am_bin" serve-http --no-tui --host 127.0.0.1 --port 8765 --path "$am_mcp_path" \
            >>"$fallback_log_file" 2>&1 < /dev/null &
    else
        "$nohup_bin" "$env_bin" \
            RUST_LOG=info \
            STORAGE_ROOT="$storage_root" \
            DATABASE_URL="$db_url" \
            HTTP_ALLOW_LOCALHOST_UNAUTHENTICATED=true \
            "$am_bin" serve-http --no-tui --host 127.0.0.1 --port 8765 --path "$am_mcp_path" \
            >>"$fallback_log_file" 2>&1 < /dev/null &
    fi
    echo $! > "$fallback_pid_file"
}

agent_mail_fix_stop_fallback() {
    local storage_root="$(doctor_fix_runtime_home)/.mcp_agent_mail_git_mailbox_repo"
    local fallback_pid_file="$storage_root/agent-mail.pid"
    local am_bin=""
    local existing_pid=""
    local managed_pid=""
    local victim_args=""
    local victim_exe=""
    local am_real=""
    local owner_matches=false
    local ps_bin=""
    local readlink_bin=""
    local rm_bin=""
    local sleep_bin=""
    local systemctl_bin=""

    am_bin="$(doctor_fix_agent_mail_bin 2>/dev/null || true)"
    [[ -n "$am_bin" ]] || return 1

    ps_bin="$(doctor_fix_lifecycle_binary_path ps 2>/dev/null || true)"
    readlink_bin="$(doctor_fix_lifecycle_binary_path readlink 2>/dev/null || true)"
    rm_bin="$(doctor_fix_lifecycle_binary_path rm 2>/dev/null || true)"
    sleep_bin="$(doctor_fix_lifecycle_binary_path sleep 2>/dev/null || true)"
    systemctl_bin="$(doctor_fix_lifecycle_binary_path systemctl 2>/dev/null || true)"
    if [[ -z "$ps_bin" || -z "$readlink_bin" || -z "$rm_bin" || -z "$sleep_bin" ]]; then
        doctor_fix_log ERROR "Cannot inspect the Agent Mail fallback because required system tools are unavailable"
        return 1
    fi

    if [[ -f "$fallback_pid_file" ]]; then
        IFS= read -r existing_pid < "$fallback_pid_file" || existing_pid=""
        if [[ -n "$systemctl_bin" ]] && "$systemctl_bin" --user show-environment >/dev/null 2>&1; then
            managed_pid="$("$systemctl_bin" --user show agent-mail.service -p MainPID --value 2>/dev/null || true)"
        fi
        if [[ "$managed_pid" =~ ^[1-9][0-9]*$ ]] && [[ "$existing_pid" == "$managed_pid" ]]; then
            doctor_fix_log INFO "Agent Mail PID $existing_pid belongs to agent-mail.service; leaving it to the supervisor"
            "$rm_bin" -f -- "$fallback_pid_file"
            return 0
        fi
        if [[ "$existing_pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
            victim_args="$("$ps_bin" -p "$existing_pid" -o args= 2>/dev/null || true)"
            victim_exe="$("$readlink_bin" -f "/proc/$existing_pid/exe" 2>/dev/null || true)"
            am_real="$("$readlink_bin" -f "$am_bin" 2>/dev/null || printf '%s' "$am_bin")"
            if [[ ! "$victim_args" =~ (^|[[:space:]])serve-http([[:space:]]|$) ]] ||
               [[ ! "$victim_args" =~ (^|[[:space:]])--port(=|[[:space:]]+)8765([[:space:]]|$) ]]; then
                owner_matches=false
            elif [[ -n "$victim_exe" ]]; then
                [[ "$victim_exe" == "$am_real" ]] && owner_matches=true
            elif [[ "$victim_args" =~ (^|/)am([[:space:]]|$) ]]; then
                owner_matches=true
            fi
        fi
        if [[ "$owner_matches" == "true" ]]; then
            kill "$existing_pid" >/dev/null 2>&1 || true
            for _ in {1..10}; do
                if ! kill -0 "$existing_pid" 2>/dev/null; then
                    break
                fi
                "$sleep_bin" 1
            done
            if kill -0 "$existing_pid" 2>/dev/null; then
                doctor_fix_log ERROR "Agent Mail fallback PID $existing_pid did not stop after SIGTERM; refusing a hard kill"
                return 1
            fi
        fi
        "$rm_bin" -f -- "$fallback_pid_file"
    fi
}

agent_mail_fix_safe_to_mutate() {
    local am_bin="$1"
    local drain_json=""
    local jq_bin=""

    drain_json="$(doctor_fix_run_agent_mail_command "$am_bin" 15s doctor drain --json 2>/dev/null)" || return 2
    jq_bin="$(doctor_fix_system_binary_path jq 2>/dev/null || true)"
    [[ -n "$jq_bin" ]] || return 2
    if ! printf '%s\n' "$drain_json" | "$jq_bin" -e \
        'type == "object" and (.safe_to_mutate | type == "boolean")' >/dev/null 2>&1; then
        return 2
    fi
    if printf '%s\n' "$drain_json" | "$jq_bin" -e \
        '.safe_to_mutate == true' >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

fix_mcp_agent_mail() {
    local check_id="$1"
    local fixed_any=false
    local service_healthy=false
    local doctor_healthy=false
    local mutation_failed=false
    local repair_succeeded=false
    local drain_rc=0
    local am_configure_rc=0
    local project_path=""
    local runtime_home=""
    local runtime_user=""
    local am_src=""
    local am_dst=""
    local mcp_server_src=""
    local mcp_server_dst=""
    local storage_root=""
    local unit_file=""
    local runtime_probe_bin=""
    runtime_home="$(doctor_fix_runtime_home)"
    runtime_user="$(doctor_fix_runtime_user)"
    am_src="$runtime_home/mcp_agent_mail/am"
    am_dst="$runtime_home/.local/bin/am"
    mcp_server_src="$runtime_home/mcp_agent_mail/mcp-agent-mail"
    mcp_server_dst="$runtime_home/.local/bin/mcp-agent-mail"
    storage_root="$runtime_home/.mcp_agent_mail_git_mailbox_repo"
    unit_file="$runtime_home/.config/systemd/user/agent-mail.service"

    # Resolve and exercise the account transport before changing symlinks,
    # installing a CLI or reconciling service state. A missing/denied switch
    # must not fall through to caller-owned execution or a misleading success.
    if [[ "$DOCTOR_FIX_DRY_RUN" != "true" ]]; then
        runtime_probe_bin="$(doctor_fix_system_binary_path true 2>/dev/null || true)"
        if [[ -z "$runtime_probe_bin" ]] || ! doctor_fix_run_agent_mail_command "$runtime_probe_bin" 15s; then
            doctor_fix_log ERROR "Unable to enter the target account and configuration for MCP Agent Mail repair"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi
    fi

    doctor_fix_source_stack_lib || {
        doctor_fix_log ERROR "Unable to load stack helper library for MCP Agent Mail repair"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    }

    if [[ -x "$am_src" ]]; then
        local resolved_am_cli=""
        local resolved_am_target=""
        local am_src_target=""
        local resolved_server_cli=""
        local resolved_server_target=""
        local mcp_server_src_target=""
        local need_am_link=false
        local need_server_link=false

        resolved_am_cli="$(doctor_fix_agent_mail_cli_path 2>/dev/null || true)"
        resolved_am_target="$(doctor_fix_resolve_path_target "$resolved_am_cli" 2>/dev/null || true)"
        am_src_target="$(doctor_fix_resolve_path_target "$am_src" 2>/dev/null || true)"
        if [[ -z "$resolved_am_target" || "$resolved_am_target" != "$am_src_target" ]]; then
            need_am_link=true
        fi

        if [[ -x "$mcp_server_src" ]]; then
            resolved_server_cli="$(doctor_fix_agent_mail_server_cli_path 2>/dev/null || true)"
            resolved_server_target="$(doctor_fix_resolve_path_target "$resolved_server_cli" 2>/dev/null || true)"
            mcp_server_src_target="$(doctor_fix_resolve_path_target "$mcp_server_src" 2>/dev/null || true)"
            if [[ -z "$resolved_server_target" || "$resolved_server_target" != "$mcp_server_src_target" ]]; then
                need_server_link=true
            fi
        fi

        if [[ "$need_am_link" == "true" || "$need_server_link" == "true" ]]; then
            if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
                if [[ "$need_am_link" == "true" ]]; then
                    FIXES_DRY_RUN+=("fix.stack.mcp_agent_mail.symlink|Ensure am symlink points at installed Rust CLI|$am_dst|ln -sf $am_src $am_dst")
                    doctor_fix_log DRY "Ensure am symlink points at $am_src"
                fi
                if [[ "$need_server_link" == "true" ]]; then
                    FIXES_DRY_RUN+=("fix.stack.mcp_agent_mail.symlink|Ensure mcp-agent-mail symlink points at installed Rust server CLI|$mcp_server_dst|ln -sf $mcp_server_src $mcp_server_dst")
                    doctor_fix_log DRY "Ensure mcp-agent-mail symlink points at $mcp_server_src"
                fi
            else
                local symlink_backup_json='[]'
                local am_backup_json='[]'
                local server_backup_json='[]'
                local am_restore_command=""
                local server_restore_command=""
                local symlink_restore_command=""
                local symlink_files_json=""
                local jq_bin=""

                if [[ -e "$am_dst" || -L "$am_dst" ]]; then
                    am_backup_json="$(create_backup "$am_dst" "doctor-fix-agent-mail-symlink" 2>/dev/null || echo '[]')"
                    am_restore_command="$(autofix_backup_restore_command "$am_backup_json" 2>/dev/null || true)"
                    if [[ -z "$am_restore_command" || "$am_backup_json" == '[]' ]]; then
                        doctor_fix_log ERROR "Failed to back up existing am entry before repairing CLI symlink"
                        FIX_FAILED=$((FIX_FAILED + 1))
                        return 1
                    fi
                else
                    am_restore_command="$(doctor_fix_build_remove_path_rollback \
                        "$am_dst" \
                        "$(doctor_fix_nearest_existing_parent "$am_dst")")" || {
                        doctor_fix_log ERROR "Failed to build rollback command for new Agent Mail CLI symlink"
                        FIX_FAILED=$((FIX_FAILED + 1))
                        return 1
                    }
                fi

                symlink_restore_command="$am_restore_command"
                symlink_backup_json="$am_backup_json"
                symlink_files_json="$(doctor_fix_files_json "$am_dst")"

                if [[ -x "$mcp_server_src" ]]; then
                    if [[ -e "$mcp_server_dst" || -L "$mcp_server_dst" ]]; then
                        server_backup_json="$(create_backup "$mcp_server_dst" "doctor-fix-agent-mail-server-symlink" 2>/dev/null || echo '[]')"
                        server_restore_command="$(autofix_backup_restore_command "$server_backup_json" 2>/dev/null || true)"
                        if [[ -z "$server_restore_command" || "$server_backup_json" == '[]' ]]; then
                            doctor_fix_log ERROR "Failed to back up existing mcp-agent-mail entry before repairing CLI symlink"
                            FIX_FAILED=$((FIX_FAILED + 1))
                            return 1
                        fi
                    else
                        server_restore_command="$(doctor_fix_build_remove_path_rollback \
                            "$mcp_server_dst" \
                            "$(doctor_fix_nearest_existing_parent "$mcp_server_dst")")" || {
                            doctor_fix_log ERROR "Failed to build rollback command for new mcp-agent-mail CLI symlink"
                            FIX_FAILED=$((FIX_FAILED + 1))
                            return 1
                        }
                    fi

                    symlink_restore_command="( acfs_restore_rc=0; { $am_restore_command; } || acfs_restore_rc=\$?; { $server_restore_command; } || acfs_restore_rc=\$?; exit \$acfs_restore_rc )"
                    symlink_files_json="$(doctor_fix_files_json "$am_dst" "$mcp_server_dst")"
                    if [[ "$am_backup_json" == '[]' && "$server_backup_json" == '[]' ]]; then
                        symlink_backup_json='[]'
                    elif [[ "$am_backup_json" == '[]' ]]; then
                        symlink_backup_json="$server_backup_json"
                    elif [[ "$server_backup_json" == '[]' ]]; then
                        symlink_backup_json="$am_backup_json"
                    else
                        jq_bin="$(doctor_fix_system_binary_path jq 2>/dev/null || true)"
                        if [[ -z "$jq_bin" ]] || ! symlink_backup_json="$("$jq_bin" -cn \
                            --argjson am_b "$am_backup_json" \
                            --argjson srv_b "$server_backup_json" \
                            '[$am_b, $srv_b]' 2>/dev/null)" || [[ -z "$symlink_backup_json" ]]; then
                            doctor_fix_log ERROR "Failed to combine Agent Mail CLI symlink backup metadata"
                            FIX_FAILED=$((FIX_FAILED + 1))
                            return 1
                        fi
                    fi
                fi

                if ! ACFS_STACK_TRUST_TARGET_HOME=true TARGET_USER="$runtime_user" TARGET_HOME="$runtime_home" _stack_repair_agent_mail_cli_symlink; then
                    doctor_fix_log ERROR "Failed to repair Agent Mail CLI symlink"
                    if ! doctor_fix_run_rollback_command "$am_restore_command" false; then
                        doctor_fix_log ERROR "Failed to restore the prior Agent Mail CLI entry"
                    fi
                    if [[ -n "$server_restore_command" ]] && ! doctor_fix_run_rollback_command "$server_restore_command" false; then
                        doctor_fix_log ERROR "Failed to restore the prior mcp-agent-mail CLI entry"
                    fi
                    FIX_FAILED=$((FIX_FAILED + 1))
                    return 1
                fi

                hash -r
                resolved_am_cli="$(doctor_fix_agent_mail_cli_path 2>/dev/null || true)"
                resolved_am_target="$(doctor_fix_resolve_path_target "$resolved_am_cli" 2>/dev/null || true)"
                local server_verify_failed=false
                if [[ -x "$mcp_server_src" ]]; then
                    resolved_server_cli="$(doctor_fix_agent_mail_server_cli_path 2>/dev/null || true)"
                    resolved_server_target="$(doctor_fix_resolve_path_target "$resolved_server_cli" 2>/dev/null || true)"
                    if [[ -z "$resolved_server_target" || "$resolved_server_target" != "$mcp_server_src_target" ]]; then
                        server_verify_failed=true
                    fi
                fi
                if [[ -z "$resolved_am_target" || "$resolved_am_target" != "$am_src_target" || "$server_verify_failed" == "true" ]]; then
                    doctor_fix_log ERROR "Agent Mail CLI symlink repair completed but commands still resolve away from $runtime_home/mcp_agent_mail"
                    if ! doctor_fix_run_rollback_command "$am_restore_command" false; then
                        doctor_fix_log ERROR "Failed to restore the prior Agent Mail CLI entry"
                    fi
                    if [[ -n "$server_restore_command" ]] && ! doctor_fix_run_rollback_command "$server_restore_command" false; then
                        doctor_fix_log ERROR "Failed to restore the prior mcp-agent-mail CLI entry"
                    fi
                    FIX_FAILED=$((FIX_FAILED + 1))
                    return 1
                fi

                local symlink_fix_desc="Ensured am resolves to installed Rust CLI"
                if [[ "$need_am_link" == "true" && "$need_server_link" == "true" ]]; then
                    symlink_fix_desc="Ensured am and mcp-agent-mail resolve to installed Rust CLIs"
                elif [[ "$need_am_link" != "true" && "$need_server_link" == "true" ]]; then
                    symlink_fix_desc="Ensured mcp-agent-mail resolves to installed Rust server CLI"
                fi

                if ! doctor_fix_record_change_or_rollback \
                    "$symlink_restore_command" \
                    false \
                    "symlink" "$symlink_fix_desc" \
                    "$symlink_restore_command" \
                    false "info" "$symlink_files_json" "$symlink_backup_json" "[]"; then
                    FIX_FAILED=$((FIX_FAILED + 1))
                    return 1
                fi

                hash -r
                doctor_fix_log INFO "$symlink_fix_desc"
                FIXES_APPLIED+=("fix.stack.mcp_agent_mail.symlink|$symlink_fix_desc")
                FIX_APPLIED=$((FIX_APPLIED + 1))
                fixed_any=true
            fi
        fi
    fi

    local am_bin=""
    am_bin="$(doctor_fix_agent_mail_bin 2>/dev/null || true)"

    if [[ -z "$am_bin" ]]; then
        if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
            FIXES_DRY_RUN+=("fix.stack.mcp_agent_mail|Install MCP Agent Mail via verified installer, then repair service state|$runtime_home/mcp_agent_mail|verified:mcp_agent_mail AM_INSTALL_SKIP_MCP_SETUP=1 AM_INSTALL_SKIP_REMOTE_HTTP_READINESS=1 --dest $runtime_home/mcp_agent_mail --yes")
            doctor_fix_log DRY "Install MCP Agent Mail via verified installer, then repair service state"
            return 0
        fi

        if doctor_fix_run_verified_installer_with_env "mcp_agent_mail" $'AM_INSTALL_SKIP_MCP_SETUP=1\nAM_INSTALL_SKIP_REMOTE_HTTP_READINESS=1' --dest "$runtime_home/mcp_agent_mail" --yes >/dev/null 2>&1; then
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
            if [[ -x "$mcp_server_src" ]]; then
                local installed_server_cli=""
                local installed_server_target=""
                local installed_server_src_target=""
                installed_server_cli="$(doctor_fix_agent_mail_server_cli_path 2>/dev/null || true)"
                installed_server_target="$(doctor_fix_resolve_path_target "$installed_server_cli" 2>/dev/null || true)"
                installed_server_src_target="$(doctor_fix_resolve_path_target "$mcp_server_src" 2>/dev/null || true)"
                if [[ -z "$installed_server_target" || "$installed_server_target" != "$installed_server_src_target" ]]; then
                    doctor_fix_log ERROR "Installed MCP Agent Mail CLI but failed to repair mcp-agent-mail symlink"
                    FIX_FAILED=$((FIX_FAILED + 1))
                    return 1
                fi
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
        FIXES_DRY_RUN+=("fix.stack.mcp_agent_mail|Inspect MCP Agent Mail drain state, repair only when safe_to_mutate=true, then reconcile the user service|$runtime_home/.mcp_agent_mail_git_mailbox_repo|am doctor drain --json; if safe: am doctor repair --yes; am doctor fix --yes")
        doctor_fix_log DRY "Inspect MCP Agent Mail drain state, repair only when safe to mutate, and reconcile the user service"
        return 0
    fi

    am_bin="$(doctor_fix_agent_mail_bin 2>/dev/null || true)"
    [[ -n "$am_bin" ]] || {
        doctor_fix_log ERROR "MCP Agent Mail CLI is missing after repair attempt"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    }

    agent_mail_fix_safe_to_mutate "$am_bin" || drain_rc=$?
    if [[ "$drain_rc" -eq 0 ]]; then
        if doctor_fix_run_agent_mail_command "$am_bin" 60s doctor repair --yes >/dev/null 2>&1; then
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
            repair_succeeded=true
        else
            doctor_fix_log WARN "MCP Agent Mail database repair did not complete cleanly"
            mutation_failed=true
        fi

        if [[ "$repair_succeeded" == "true" ]]; then
            drain_rc=0
            agent_mail_fix_safe_to_mutate "$am_bin" || drain_rc=$?
            if [[ "$drain_rc" -eq 0 ]]; then
                if doctor_fix_run_agent_mail_command "$am_bin" 60s doctor fix --yes >/dev/null 2>&1; then
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
                    mutation_failed=true
                fi
            elif [[ "$drain_rc" -eq 1 ]]; then
                doctor_fix_log INFO "MCP Agent Mail acquired a live owner after repair; skipping doctor fix until a new supervised drain is safe"
            else
                doctor_fix_log WARN "Could not renew the MCP Agent Mail drain attestation after repair; skipping doctor fix"
            fi
        fi
    elif [[ "$drain_rc" -eq 1 ]]; then
        doctor_fix_log INFO "MCP Agent Mail has a live mailbox owner; skipping mutating doctor repair until a supervised drain reports safe_to_mutate=true"
    else
        doctor_fix_log WARN "Could not obtain a trustworthy MCP Agent Mail drain attestation; skipping mutating doctor repair"
    fi

    if doctor_fix_system_curl -fsS --max-time 5 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1 && \
       agent_mail_fix_readiness_ready; then
        service_healthy=true
    fi

    ACFS_STACK_TRUST_TARGET_HOME=true TARGET_USER="$runtime_user" TARGET_HOME="$runtime_home" _stack_configure_agent_mail_service || am_configure_rc=$?
    if [[ "$am_configure_rc" -eq 75 ]]; then
        # Local opt-out (masked/disabled unit or ACFS_SKIP_AGENT_MAIL=1):
        # intentionally skipped, never a repair failure (#327).
        doctor_fix_log INFO "MCP Agent Mail service management skipped by local opt-out"
    elif [[ "$am_configure_rc" -eq 0 ]]; then
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

        # The unit was restarted, so the pre-restart probe is stale. Require a
        # fresh readiness result before allowing the overall repair to pass.
        service_healthy=false
        if agent_mail_fix_wait_for_health; then
            doctor_fix_log INFO "Agent Mail service is healthy after restart"
            service_healthy=true
        else
            doctor_fix_log WARN "Agent Mail service did not reach readiness after repair"
        fi
    else
        # A still-responsive old process does not prove that the requested unit
        # rewrite/restart succeeded. Preserve this as a repair failure so stale
        # or broken service configuration cannot be reported as fixed.
        doctor_fix_log WARN "Failed to rewrite or restart the MCP Agent Mail user service unit"
        mutation_failed=true
    fi

    if [[ "$mutation_failed" != "true" && "$service_healthy" == "true" ]] && agent_mail_fix_doctor_healthy; then
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
        elif [[ ${#FIXES_MANUAL[@]} -gt 0 ]]; then
            echo "  No automatic fixes available for the reported manual repairs."
        elif [[ ${#DOCTOR_FIX_ONLY_SELECTORS[@]} -gt 0 ]]; then
            echo "  No automatic fixes planned for this selection."
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

    if [[ ${#DOCTOR_FIX_ONLY_SELECTORS[@]} -gt 0 ]]; then
        echo ""
        printf '  Selected: %s\n' "${DOCTOR_FIX_ONLY_SELECTORS[*]}"
        echo "  Outside selection: $FIX_FILTERED (findings remain unchanged)"
    fi

    if [[ ${#FIXES_MANUAL[@]} -gt 0 ]]; then
        echo ""
        echo "  Manual fixes needed:"
        for fix in "${FIXES_MANUAL[@]}"; do
            IFS='|' read -r id desc cmd <<< "$fix"
            echo "    [$id] $desc"
            if [[ -n "$cmd" ]]; then
                echo "      Run: $cmd"
            fi
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
# Usage: run_doctor_fix [--dry-run] [--yes] [--only <category|check-id>[,...]]
run_doctor_fix() {
    local dry_run=false
    local yes_mode=false
    local selection_value=""
    local selector=""
    local existing_selector=""
    local duplicate=false
    local -a selection_values=()
    local -a parsed_selectors=()
    local -a value_selectors=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=true; shift ;;
            --yes|-y) yes_mode=true; shift ;;
            --only)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --only requires a category or exact check ID" >&2
                    return 2
                fi
                selection_values+=("$2")
                shift 2
                ;;
            --only=*) selection_values+=("${1#*=}"); shift ;;
            --prompt)
                echo "Error: --prompt is not supported; use --dry-run to preview fixes first" >&2
                return 2
                ;;
            *)
                printf "Error: unknown doctor fix option '%s'\n" "$1" >&2
                return 2
                ;;
        esac
    done

    # Validate the complete request before logging or starting the undo session.
    # Repeated --only options form a union; duplicates do not repeat repairs.
    for selection_value in "${selection_values[@]}"; do
        if [[ ! "$selection_value" =~ ^[A-Za-z0-9_.,+-]+$ || "$selection_value" == ,* || "$selection_value" == *, || "$selection_value" == *,,* ]]; then
            echo "Error: --only requires a nonempty comma-separated list of categories or exact check IDs" >&2
            return 2
        fi
        IFS=',' read -r -a value_selectors <<< "$selection_value"
        for selector in "${value_selectors[@]}"; do
            # Dynamic hold/rollback IDs include validated tool names, which
            # may contain uppercase letters, plus signs, hyphens and dots.
            # Treat the dotted tail literally; observed-ID validation below
            # the diagnostic pass establishes whether the complete ID exists.
            if [[ ! "$selector" =~ ^[a-z][a-z0-9_]*(\.[A-Za-z0-9_+-][A-Za-z0-9._+-]*)?$ ]]; then
                printf 'Error: invalid --only selector %q; use a category or exact check ID without spaces or wildcards\n' "$selector" >&2
                return 2
            fi
            duplicate=false
            for existing_selector in "${parsed_selectors[@]}"; do
                if [[ "$existing_selector" == "$selector" ]]; then
                    duplicate=true
                    break
                fi
            done
            [[ "$duplicate" == true ]] || parsed_selectors+=("$selector")
        done
    done
    DOCTOR_FIX_DRY_RUN="$dry_run"
    DOCTOR_FIX_YES="$yes_mode"
    DOCTOR_FIX_PROMPT=false
    DOCTOR_FIX_FINALIZED=false
    DOCTOR_FIX_ONLY_SELECTORS=("${parsed_selectors[@]}")

    # Say which tier of fixes this run may apply, so a `--fix --yes` that did
    # not reach here is visible in the log instead of indistinguishable from
    # a run with nothing to fix (#401).
    if [[ "$DOCTOR_FIX_YES" == "true" ]]; then
        doctor_fix_log INFO "warning-level fixes enabled (--yes)"
    else
        doctor_fix_log INFO "warning-level fixes disabled (pass --yes to apply them)"
    fi

    # Fixers write ~/.zshrc, ~/.claude/settings.json, plugin clones, and
    # bun/global installs as the *invoking* uid. Running them as root for a
    # non-root target leaves root-owned files in the user's home (and
    # oh-my-zsh then complains about insecure directories). The global
    # /usr/local/bin/acfs wrapper already drops privileges; refuse the direct
    # root path instead of silently corrupting ownership.
    local fix_runtime_user=""
    fix_runtime_user="$(doctor_fix_runtime_user 2>/dev/null || true)"
    if [[ $EUID -eq 0 ]] && [[ -n "$fix_runtime_user" ]] && [[ "$fix_runtime_user" != "root" ]] \
        && [[ "${DOCTOR_FIX_ALLOW_ROOT:-false}" != "true" ]] && [[ "$DOCTOR_FIX_DRY_RUN" != "true" ]]; then
        echo "ERROR: acfs doctor --fix must run as $fix_runtime_user, not root (fixes would leave root-owned files in that user's home)." >&2
        echo "       Use '/usr/local/bin/acfs doctor --fix' (drops privileges) or 'sudo -u $fix_runtime_user -i acfs doctor --fix'." >&2
        return 1
    fi

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
    FIX_FILTERED=0
    FIXES_APPLIED=()
    FIXES_DRY_RUN=()
    FIXES_MANUAL=()
    FIXES_PROMPTED=()
    DOCTOR_FIX_FAILED_COMMAND_IDS=()

    # Under --json stdout must remain a single JSON document.
    local banner_fd=1
    if [[ "${JSON_MODE:-false}" == "true" ]]; then
        banner_fd=2
    fi
    echo "" >&"$banner_fd"
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: acfs doctor --fix" >&"$banner_fd"
        echo "Scanning for fixable issues..." >&"$banner_fd"
    else
        echo "Running: acfs doctor --fix" >&"$banner_fd"
        echo "Applying safe fixes..." >&"$banner_fd"
    fi
    echo "" >&"$banner_fd"

    # The actual fixes are dispatched by the caller (doctor.sh)
    # based on check results. This function sets up the environment.

    return 0
}

# Finalize doctor --fix
finalize_doctor_fix() {
    DOCTOR_FIX_FINALIZED=false
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

    # Session closure is independent of repair success. A failed repair can
    # still leave a completely finalized undo journal that callers can trust.
    DOCTOR_FIX_FINALIZED=true

    # Return failure if any fixes failed
    if [[ $FIX_FAILED -gt 0 ]]; then
        return 1
    fi

    return 0
}
