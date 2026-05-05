#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Post-Install Services Setup
# Interactive wizard to configure AI agents and cloud services
# Run after main installer completes: acfs services-setup
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

services_setup_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

services_setup_system_binary_path() {
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

services_setup_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(services_setup_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(services_setup_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

services_setup_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(services_setup_system_binary_path getent 2>/dev/null || true)"
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

services_setup_passwd_home_from_entry() {
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
    passwd_home="$(services_setup_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
    [[ -n "$passwd_home" ]] || return 1
    printf '%s\n' "$passwd_home"
}

services_setup_resolve_current_home() {
    local current_user=""
    local home_candidate=""
    local passwd_entry=""
    local passwd_home=""

    home_candidate="$(services_setup_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
    current_user="$(services_setup_resolve_current_user 2>/dev/null || true)"
    if [[ "$current_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    if [[ -n "$current_user" ]]; then
        passwd_entry="$(services_setup_getent_passwd_entry "$current_user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            passwd_home="$(services_setup_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
            if [[ -n "$passwd_home" ]]; then
                printf '%s\n' "$passwd_home"
                return 0
            fi
        fi
    fi

    [[ -n "$home_candidate" ]] || return 1
    printf '%s\n' "$home_candidate"
}

_SERVICES_SETUP_ENV_HOME="$(services_setup_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
_SERVICES_SETUP_CURRENT_USER="$(services_setup_resolve_current_user 2>/dev/null || true)"
_SERVICES_SETUP_CURRENT_HOME="$(services_setup_resolve_current_home 2>/dev/null || true)"
if [[ -n "$_SERVICES_SETUP_CURRENT_HOME" ]]; then
    HOME="$_SERVICES_SETUP_CURRENT_HOME"
    export HOME
fi

ACFS_HOME="$(services_setup_sanitize_abs_nonroot_path "${ACFS_HOME:-}" 2>/dev/null || true)"
TARGET_HOME="$(services_setup_sanitize_abs_nonroot_path "${TARGET_HOME:-}" 2>/dev/null || true)"
ACFS_BIN_DIR="$(services_setup_sanitize_abs_nonroot_path "${ACFS_BIN_DIR:-}" 2>/dev/null || true)"
export ACFS_HOME TARGET_HOME ACFS_BIN_DIR

resolve_script_lib_dir() {
    local -a candidates=()
    local candidate=""

    candidates+=("$SCRIPT_DIR/lib")

    if [[ -n "${ACFS_HOME:-}" ]] && [[ "${ACFS_HOME}" == /* ]]; then
        candidates+=("${ACFS_HOME%/}/scripts/lib")
    fi

    if [[ -n "${TARGET_HOME:-}" ]] && [[ "${TARGET_HOME}" == /* ]]; then
        candidates+=("${TARGET_HOME%/}/.acfs/scripts/lib")
    fi

    if [[ -n "${_SERVICES_SETUP_CURRENT_HOME:-}" ]]; then
        candidates+=("${_SERVICES_SETUP_CURRENT_HOME}/.acfs/scripts/lib")
    fi

    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate/logging.sh" ]] && [[ -f "$candidate/gum_ui.sh" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

ACFS_LIB_DIR="$(resolve_script_lib_dir || true)"

# Source libraries from the script-adjacent install first, then explicit ACFS
# and target-home hints, and only finally the caller HOME fallback.
if [[ -n "$ACFS_LIB_DIR" ]]; then
    source "$ACFS_LIB_DIR/logging.sh"
    source "$ACFS_LIB_DIR/gum_ui.sh"
else
    echo "Error: Cannot find ACFS script libraries"
    echo "Expected at: $SCRIPT_DIR/lib/ or ${ACFS_HOME:-<acfs-home>}/scripts/lib/ or ${TARGET_HOME:-<target-home>}/.acfs/scripts/lib/ or ${_SERVICES_SETUP_CURRENT_HOME:-<home>}/.acfs/scripts/lib/"
    exit 1
fi

# ============================================================
# Configuration
# ============================================================

TARGET_USER="${TARGET_USER:-${SUDO_USER:-${_SERVICES_SETUP_CURRENT_USER:-}}}"
SERVICES_SETUP_ACTION="${SERVICES_SETUP_ACTION:-}"
SERVICES_SETUP_NONINTERACTIVE="${SERVICES_SETUP_NONINTERACTIVE:-false}"

services_setup_valid_target_user() {
    local user="${1:-}"
    [[ -n "$user" ]] || return 1
    [[ "$user" =~ ^[a-z_][a-z0-9._-]*$ ]]
}

services_setup_validate_target_user() {
    local user="${1:-${TARGET_USER:-}}"
    local display="${user:-<empty>}"

    if services_setup_valid_target_user "$user"; then
        return 0
    fi

    log_error "Invalid TARGET_USER '$display' (expected: lowercase user name like 'ubuntu')"
    return 1
}

resolve_home_dir() {
    local user="$1"
    local expected_home="${2:-}"
    local home=""
    local current_user=""
    local current_home=""
    local initial_env_home=""
    local passwd_entry=""

    expected_home="$(services_setup_sanitize_abs_nonroot_path "$expected_home" 2>/dev/null || true)"

    current_user="$(services_setup_resolve_current_user 2>/dev/null || true)"
    if [[ "$current_user" == "$user" ]] && [[ -n "$expected_home" ]]; then
        current_home="$(services_setup_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
        initial_env_home="$(services_setup_sanitize_abs_nonroot_path "${_SERVICES_SETUP_ENV_HOME:-}" 2>/dev/null || true)"
        if [[ "$current_home" != "$expected_home" ]] && [[ "$initial_env_home" != "$expected_home" ]] && {
            { declare -F services_setup_target_home_has_acfs_data >/dev/null 2>&1 && services_setup_target_home_has_acfs_data "$expected_home"; } \
                || [[ -n "${ACFS_BIN_DIR:-}" ]]
        }; then
            printf '%s' "$expected_home"
            return 0
        fi
    fi

    passwd_entry="$(services_setup_getent_passwd_entry "$user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        home="$(services_setup_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
    fi
    if [[ -n "$home" ]]; then
        printf '%s' "$home"
        return 0
    fi

    if [[ "$user" == "root" ]]; then
        printf '/root'
        return 0
    fi

    if [[ "$current_user" == "$user" ]]; then
        home="$(services_setup_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
        if [[ -n "$home" ]] && { [[ -z "$expected_home" ]] || [[ "$home" == "$expected_home" ]]; }; then
            printf '%s' "$home"
            return 0
        fi
    fi

    return 1
}

services_setup_validate_bin_dir_for_home() {
    local bin_dir="${1:-}"
    local base_home="${2:-}"
    local passwd_line=""
    local passwd_home=""
    local hinted_home=""

    bin_dir="$(services_setup_sanitize_abs_nonroot_path "$bin_dir" 2>/dev/null || true)"
    [[ -n "$bin_dir" ]] || return 1
    base_home="$(services_setup_sanitize_abs_nonroot_path "$base_home" 2>/dev/null || true)"

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
    hinted_home="$(services_setup_sanitize_abs_nonroot_path "$hinted_home" 2>/dev/null || true)"
    if [[ -n "$hinted_home" ]] && [[ -n "$base_home" ]] && [[ "$hinted_home" != "$base_home" ]]; then
        return 1
    fi

    while IFS= read -r passwd_line; do
        passwd_home="$(services_setup_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
        [[ -n "$passwd_home" ]] || continue
        [[ -n "$base_home" && "$passwd_home" == "$base_home" ]] && continue
        if [[ "$bin_dir" == "$passwd_home" || "$bin_dir" == "$passwd_home/"* ]]; then
            return 1
        fi
    done < <(services_setup_getent_passwd_entry 2>/dev/null || true)

    printf '%s\n' "$bin_dir"
}

services_setup_target_home_has_acfs_data() {
    local home_dir="${1:-}"

    home_dir="$(services_setup_sanitize_abs_nonroot_path "$home_dir" 2>/dev/null || true)"
    [[ -n "$home_dir" ]] || return 1

    [[ -f "$home_dir/.acfs/state.json" ]] \
        || [[ -f "$home_dir/.acfs/VERSION" ]] \
        || [[ -f "$home_dir/.acfs/version" ]] \
        || { [[ -f "$home_dir/.acfs/scripts/services-setup.sh" ]] && [[ -d "$home_dir/.acfs/scripts/lib" ]]; }
}

BUN_BIN="${BUN_BIN:-}"

init_target_context() {
    local bun_bin_dir=""
    local current_user=""
    local explicit_target_home=""
    local resolved_target_home=""

    services_setup_validate_target_user "$TARGET_USER" || return 1

    explicit_target_home="$(services_setup_sanitize_abs_nonroot_path "${TARGET_HOME:-}" 2>/dev/null || true)"
    resolved_target_home="$(resolve_home_dir "$TARGET_USER" "$explicit_target_home" 2>/dev/null || true)"
    if [[ -n "$resolved_target_home" ]]; then
        TARGET_HOME="$resolved_target_home"
    elif [[ -n "$explicit_target_home" ]]; then
        current_user="$(services_setup_resolve_current_user 2>/dev/null || true)"
        if [[ -z "$current_user" ]] || [[ "$TARGET_USER" != "$current_user" ]]; then
            log_error "Unable to determine home directory for user: $TARGET_USER"
            return 1
        fi
        TARGET_HOME="$explicit_target_home"
    fi
    if [[ -z "${TARGET_HOME:-}" ]]; then
        log_error "Unable to determine home directory for user: $TARGET_USER"
        return 1
    fi
    export TARGET_HOME

    ACFS_HOME="$(services_setup_sanitize_abs_nonroot_path "${ACFS_HOME:-}" 2>/dev/null || true)"
    if [[ -n "$explicit_target_home" ]] && [[ "$explicit_target_home" != "$TARGET_HOME" ]]; then
        case "$ACFS_HOME" in
            "$explicit_target_home"|"$explicit_target_home"/*)
                ACFS_HOME="$TARGET_HOME/.acfs"
                ;;
        esac
    fi
    export ACFS_HOME

    ACFS_BIN_DIR="$(services_setup_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$TARGET_HOME" 2>/dev/null || true)"
    export ACFS_BIN_DIR

    if [[ -n "${BUN_BIN:-}" && -x "${BUN_BIN:-}" ]]; then
        bun_bin_dir="$(services_setup_validate_bin_dir_for_home "${BUN_BIN%/*}" "$TARGET_HOME" 2>/dev/null || true)"
        [[ -n "$bun_bin_dir" ]] || BUN_BIN=""
    fi

    if [[ -z "${BUN_BIN:-}" || ! -x "${BUN_BIN:-}" ]]; then
        BUN_BIN="$(find_user_bin "bun" 2>/dev/null || true)"
    fi
}

# Service status tracking
declare -gA SERVICE_STATUS=()

# ============================================================
# Helper Functions
# ============================================================

# Run a command as target user
run_as_user() {
    local -a env_cmd=()
    local primary_bin_dir=""
    local env_bin=""
    local bash_bin=""
    local sh_bin=""
    local sudo_bin=""
    local runuser_bin=""
    local su_bin=""
    local target_home_for_cd=""
    local -a command_argv=()

    services_setup_validate_target_user "$TARGET_USER" || return 1

    env_bin="$(services_setup_system_binary_path env 2>/dev/null || true)"
    [[ -n "$env_bin" ]] || {
        log_error "Unable to locate env for target-user service setup command"
        return 1
    }
    bash_bin="$(services_setup_system_binary_path bash 2>/dev/null || true)"
    [[ -n "$bash_bin" ]] || {
        log_error "Unable to locate bash for target-user service setup command"
        return 1
    }
    sh_bin="$(services_setup_system_binary_path sh 2>/dev/null || true)"
    [[ -n "$sh_bin" ]] || {
        log_error "Unable to locate sh for target-user service setup command"
        return 1
    }

    primary_bin_dir="$(services_setup_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "${TARGET_HOME:-}" 2>/dev/null || true)"
    if [[ -z "$primary_bin_dir" ]] && [[ -n "${TARGET_HOME:-}" ]]; then
        primary_bin_dir="$TARGET_HOME/.local/bin"
    fi
    target_home_for_cd="$(services_setup_sanitize_abs_nonroot_path "${TARGET_HOME:-}" 2>/dev/null || true)"

    env_cmd=("$env_bin" "TARGET_USER=$TARGET_USER")
    [[ -n "${TARGET_HOME:-}" ]] && env_cmd+=("TARGET_HOME=$TARGET_HOME" "HOME=$TARGET_HOME")
    [[ -n "${ACFS_HOME:-}" ]] && env_cmd+=("ACFS_HOME=$ACFS_HOME")
    [[ -n "$primary_bin_dir" ]] && env_cmd+=("ACFS_BIN_DIR=$primary_bin_dir")

    command_argv=("$@")
    if [[ ${#command_argv[@]} -gt 0 ]]; then
        case "${command_argv[0]}" in
            env)
                command_argv[0]="$env_bin"
                local env_command_index=1
                while [[ "$env_command_index" -lt "${#command_argv[@]}" ]]; do
                    case "${command_argv[env_command_index]}" in
                        *=*) ((env_command_index += 1)) ;;
                        --) ((env_command_index += 1)); break ;;
                        -*) break ;;
                        *) break ;;
                    esac
                done
                if [[ "$env_command_index" -lt "${#command_argv[@]}" ]]; then
                    case "${command_argv[env_command_index]}" in
                        env) command_argv[env_command_index]="$env_bin" ;;
                        bash) command_argv[env_command_index]="$bash_bin" ;;
                        sh) command_argv[env_command_index]="$sh_bin" ;;
                    esac
                fi
                ;;
            bash) command_argv[0]="$bash_bin" ;;
            sh) command_argv[0]="$sh_bin" ;;
        esac
    fi

    if [[ "$(services_setup_resolve_current_user 2>/dev/null || true)" == "$TARGET_USER" ]]; then
        if [[ -n "$target_home_for_cd" ]]; then
            (
                if ! cd "$target_home_for_cd"; then
                    log_error "Unable to enter target home for '$TARGET_USER': $target_home_for_cd"
                    exit 1
                fi
                "${env_cmd[@]}" "${command_argv[@]}"
            )
        else
            "${env_cmd[@]}" "${command_argv[@]}"
        fi
        return $?
    fi

    sudo_bin="$(services_setup_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        if [[ -n "$target_home_for_cd" ]]; then
            # shellcheck disable=SC2016  # $HOME/$@ expand inside sh -c.
            "$sudo_bin" -u "$TARGET_USER" -H "${env_cmd[@]}" "$sh_bin" -c 'cd "$HOME" || exit 1; exec "$@"' _ "${command_argv[@]}"
        else
            "$sudo_bin" -u "$TARGET_USER" -H "${env_cmd[@]}" "${command_argv[@]}"
        fi
        return $?
    fi
    
    runuser_bin="$(services_setup_system_binary_path runuser 2>/dev/null || true)"
    if [[ -n "$runuser_bin" ]]; then
        if [[ -n "$target_home_for_cd" ]]; then
            # shellcheck disable=SC2016  # $HOME/$@ expand inside sh -c.
            "$runuser_bin" -u "$TARGET_USER" -- "${env_cmd[@]}" "$sh_bin" -c 'cd "$HOME" || exit 1; exec "$@"' _ "${command_argv[@]}"
        else
            "$runuser_bin" -u "$TARGET_USER" -- "${env_cmd[@]}" "${command_argv[@]}"
        fi
        return $?
    fi

    su_bin="$(services_setup_system_binary_path su 2>/dev/null || true)"
    [[ -n "$su_bin" ]] || {
        log_error "Unable to locate sudo, runuser, or su for target-user service setup command"
        return 1
    }

    local -a quoted_cmd=()
    local arg=""
    if [[ -n "$target_home_for_cd" ]]; then
        command_argv=("$sh_bin" -c 'cd "$HOME" || exit 1; exec "$@"' _ "${command_argv[@]}")
    fi
    for arg in "${env_cmd[@]}" "${command_argv[@]}"; do
        quoted_cmd+=("$(printf '%q' "$arg")")
    done
    "$su_bin" "$TARGET_USER" -c "${quoted_cmd[*]}"
}

# Run a shell string as target user (use for pipelines/redirections).
run_as_user_shell() {
    local cmd="${1:-}"
    local -a env_cmd=()
    local primary_bin_dir=""
    local env_bin=""
    local bash_bin=""
    local sudo_bin=""
    local runuser_bin=""
    local su_bin=""
    local target_home_for_cd=""

    services_setup_validate_target_user "$TARGET_USER" || return 1

    env_bin="$(services_setup_system_binary_path env 2>/dev/null || true)"
    bash_bin="$(services_setup_system_binary_path bash 2>/dev/null || true)"
    if [[ -z "$env_bin" || -z "$bash_bin" ]]; then
        log_error "Unable to locate env or bash for target-user service setup shell command"
        return 1
    fi

    primary_bin_dir="$(services_setup_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "${TARGET_HOME:-}" 2>/dev/null || true)"
    if [[ -z "$primary_bin_dir" ]] && [[ -n "${TARGET_HOME:-}" ]]; then
        primary_bin_dir="$TARGET_HOME/.local/bin"
    fi
    target_home_for_cd="$(services_setup_sanitize_abs_nonroot_path "${TARGET_HOME:-}" 2>/dev/null || true)"

    env_cmd=("$env_bin" "TARGET_USER=$TARGET_USER")
    [[ -n "${TARGET_HOME:-}" ]] && env_cmd+=("TARGET_HOME=$TARGET_HOME" "HOME=$TARGET_HOME")
    [[ -n "${ACFS_HOME:-}" ]] && env_cmd+=("ACFS_HOME=$ACFS_HOME")
    [[ -n "$primary_bin_dir" ]] && env_cmd+=("ACFS_BIN_DIR=$primary_bin_dir")

    if [[ "$(services_setup_resolve_current_user 2>/dev/null || true)" == "$TARGET_USER" ]]; then
        if [[ -n "$target_home_for_cd" ]]; then
            (
                if ! cd "$target_home_for_cd"; then
                    log_error "Unable to enter target home for '$TARGET_USER': $target_home_for_cd"
                    exit 1
                fi
                "${env_cmd[@]}" "$bash_bin" -c "$cmd"
            )
        else
            "${env_cmd[@]}" "$bash_bin" -c "$cmd"
        fi
    elif sudo_bin="$(services_setup_system_binary_path sudo 2>/dev/null || true)" && [[ -n "$sudo_bin" ]]; then
        if [[ -n "$target_home_for_cd" ]]; then
            # shellcheck disable=SC2016  # $HOME/$@ expand inside bash -c.
            "$sudo_bin" -u "$TARGET_USER" -H "${env_cmd[@]}" "$bash_bin" -c 'cd "$HOME" || exit 1; exec "$@"' _ "$bash_bin" -c "$cmd"
        else
            "$sudo_bin" -u "$TARGET_USER" -H "${env_cmd[@]}" "$bash_bin" -c "$cmd"
        fi
    elif runuser_bin="$(services_setup_system_binary_path runuser 2>/dev/null || true)" && [[ -n "$runuser_bin" ]]; then
        if [[ -n "$target_home_for_cd" ]]; then
            # shellcheck disable=SC2016  # $HOME/$@ expand inside bash -c.
            "$runuser_bin" -u "$TARGET_USER" -- "${env_cmd[@]}" "$bash_bin" -c 'cd "$HOME" || exit 1; exec "$@"' _ "$bash_bin" -c "$cmd"
        else
            "$runuser_bin" -u "$TARGET_USER" -- "${env_cmd[@]}" "$bash_bin" -c "$cmd"
        fi
    else
        su_bin="$(services_setup_system_binary_path su 2>/dev/null || true)"
        [[ -n "$su_bin" ]] || {
            log_error "Unable to locate sudo, runuser, or su for target-user service setup shell command"
            return 1
        }

        local -a quoted_cmd=()
        local arg=""
        local -a shell_argv=("$bash_bin" "-c" "$cmd")
        if [[ -n "$target_home_for_cd" ]]; then
            shell_argv=("$bash_bin" "-c" 'cd "$HOME" || exit 1; exec "$@"' _ "${shell_argv[@]}")
        fi
        for arg in "${env_cmd[@]}" "${shell_argv[@]}"; do
            quoted_cmd+=("$(printf '%q' "$arg")")
        done
        "$su_bin" "$TARGET_USER" -c "${quoted_cmd[*]}"
    fi
}

# Check if a command exists in target user's PATH
# More robust than checking binary paths directly - respects user's PATH
user_command_exists() {
    local cmd="$1"
    local primary_bin_dir="${ACFS_BIN_DIR:-$TARGET_HOME/.local/bin}"
    primary_bin_dir="$(services_setup_validate_bin_dir_for_home "$primary_bin_dir" "$TARGET_HOME" 2>/dev/null || true)"
    [[ -n "$primary_bin_dir" ]] || primary_bin_dir="$TARGET_HOME/.local/bin"
    local target_path_prefix="$primary_bin_dir:$TARGET_HOME/.local/bin:$TARGET_HOME/.acfs/bin:$TARGET_HOME/.cargo/bin:$TARGET_HOME/.bun/bin:$TARGET_HOME/.atuin/bin:$TARGET_HOME/go/bin"
    # Include common user install locations (bun/cargo/etc) even when running
    # via sudo, which may otherwise provide a restricted PATH.
    # shellcheck disable=SC2016  # $HOME/$PATH expand inside the target user's bash -c
    run_as_user env ACFS_TARGET_PATH_PREFIX="$target_path_prefix" bash -c \
        'export PATH="$ACFS_TARGET_PATH_PREFIX:$PATH"; command -v -- "$1" >/dev/null 2>&1' \
        _ "$cmd"
}

# Check if a file exists (from current user perspective)
# Used for checking config files in target user's home
user_file_exists() {
    local path="$1"
    [[ -f "$path" ]]
}

services_setup_normalize_config_value() {
    local value="${1-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ ${#value} -ge 2 ]]; then
        local first_char="${value:0:1}"
        local last_char="${value: -1}"
        if [[ ( "$first_char" == '"' && "$last_char" == '"' ) || ( "$first_char" == "'" && "$last_char" == "'" ) ]]; then
            value="${value:1:${#value}-2}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
        fi
    fi

    printf '%s\n' "$value"
}

services_setup_is_placeholder_secret() {
    local normalized=""
    normalized="$(services_setup_normalize_config_value "${1-}")"
    normalized="${normalized,,}"

    case "$normalized" in
        your-token-here|your_token_here|your-token|your_token|your_api_key|your-api-key|your_github_token|your_openai_api_key|your_claude_token|your_vercel_token|your_supabase_access_token|your_cloudflare_api_token|your_gemini_api_key|your_google_api_key|your_project_id|your_project_location|replace-me|change-me|changeme|"<token>"|"<api-key>"|"<secret>")
            return 0
            ;;
    esac

    return 1
}

services_setup_has_usable_secret() {
    local normalized=""
    normalized="$(services_setup_normalize_config_value "${1-}")"
    [[ -n "${normalized//[[:space:]]/}" ]] && ! services_setup_is_placeholder_secret "$normalized"
}

json_file_has_usable_jq_value() {
    local path="${1:-}"
    local jq_expr="${2:-}"
    local candidate=""

    [[ -s "$path" ]] || return 1
    [[ -n "$jq_expr" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    while IFS= read -r candidate; do
        if services_setup_has_usable_secret "$candidate"; then
            return 0
        fi
    done < <(jq -r "$jq_expr" "$path" 2>/dev/null || true)

    return 1
}

json_file_has_usable_string_key() {
    local path="${1:-}"
    shift || true

    [[ -s "$path" ]] || return 1

    local key=""
    local regex=""
    local line=""
    for key in "$@"; do
        [[ -n "$key" ]] || continue
        regex="\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]+)\""
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ $regex ]] && services_setup_has_usable_secret "${BASH_REMATCH[1]}"; then
                return 0
            fi
        done < "$path"
    done

    return 1
}

file_has_usable_secret() {
    local path="${1:-}"
    local value=""

    [[ -f "$path" ]] || return 1
    value="$(cat "$path" 2>/dev/null || true)"
    services_setup_has_usable_secret "$value"
}

claude_settings_has_command_hook() {
    local settings_file="${1:-}"
    local command_pattern="${2:-}"

    [[ -n "$settings_file" && -n "$command_pattern" ]] || return 1
    [[ -f "$settings_file" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    jq -e --arg pattern "$command_pattern" '
      def command_hook_matches:
        type == "object"
        and ((.type? // "command") == "command")
        and ((.command? // "") | strings | test($pattern));
      def event_entry_matches:
        if type == "object" and (.hooks? | type) == "array" then
          any(.hooks[]?; command_hook_matches)
        else
          command_hook_matches
        end;
      def hook_event_entries:
        if (.hooks? | type) == "object" then
          .hooks | to_entries[]? | .value | arrays | .[]?
        elif (.hooks? | type) == "array" then
          .hooks[]?
        else
          empty
        end;
      any(hook_event_entries; event_entry_matches)
    ' "$settings_file" >/dev/null 2>&1
}

# Check if a directory exists and is non-empty
user_dir_has_content() {
    local path="$1"
    [[ -d "$path" && -n "$(ls -A "$path" 2>/dev/null)" ]]
}

find_user_bin() {
    local name="${1:-}"
    local primary_bin_dir=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..) return 1 ;;
        *[!A-Za-z0-9._+-]*) return 1 ;;
    esac

    primary_bin_dir="${ACFS_BIN_DIR:-$TARGET_HOME/.local/bin}"
    primary_bin_dir="$(services_setup_validate_bin_dir_for_home "$primary_bin_dir" "$TARGET_HOME" 2>/dev/null || true)"
    [[ -n "$primary_bin_dir" ]] || primary_bin_dir="$TARGET_HOME/.local/bin"

    local candidates=(
        "$primary_bin_dir/$name"
        "$TARGET_HOME/.local/bin/$name"
        "$TARGET_HOME/.acfs/bin/$name"
        "$TARGET_HOME/.cargo/bin/$name"
        "$TARGET_HOME/.bun/bin/$name"
        "$TARGET_HOME/.atuin/bin/$name"
        "/usr/local/bin/$name"
        "/usr/local/sbin/$name"
        "/usr/bin/$name"
        "/bin/$name"
        "/snap/bin/$name"
    )

    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -x "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    return 1
}

dcg_hook_registered() {
    local settings_file="$TARGET_HOME/.claude/settings.json"
    local alt_settings_file="$TARGET_HOME/.config/claude/settings.json"
    local dcg_command_pattern='(^|[[:space:]/])dcg([[:space:]]|$)'

    if claude_settings_has_command_hook "$settings_file" "$dcg_command_pattern"; then
        return 0
    fi

    if claude_settings_has_command_hook "$alt_settings_file" "$dcg_command_pattern"; then
        return 0
    fi

    return 1
}

select_dcg_packs() {
    local -a options=(
        "database.postgresql (PostgreSQL guard pack)"
        "kubernetes (kubectl + cluster safety)"
        "cloud.aws (AWS CLI guard pack)"
    )

    local selected_lines=""

    if [[ "$HAS_GUM" == "true" ]]; then
        if [[ -r /dev/tty ]]; then
            selected_lines=$(gum choose --no-limit \
                --header "Select additional DCG packs (space to toggle, enter to confirm)" \
                --cursor.foreground "$ACFS_ACCENT" \
                --selected.foreground "$ACFS_SUCCESS" \
                "${options[@]}" < /dev/tty) || true
        elif [[ -t 0 ]]; then
            selected_lines=$(gum choose --no-limit \
                --header "Select additional DCG packs (space to toggle, enter to confirm)" \
                --cursor.foreground "$ACFS_ACCENT" \
                --selected.foreground "$ACFS_SUCCESS" \
                "${options[@]}") || true
        else
            echo "ERROR: --yes is required when no TTY is available" >&2
            return 1
        fi
    else
        echo "Select additional DCG packs (enter numbers separated by spaces, or 'all')"
        local input=""
        if [[ -t 0 ]]; then
            read -r -p "Select: " input
        elif [[ -r /dev/tty ]]; then
            read -r -p "Select: " input < /dev/tty
        else
            echo "ERROR: --yes is required when no TTY is available" >&2
            return 1
        fi

        if [[ "$input" == "all" ]]; then
            for opt in "${options[@]}"; do
                selected_lines+="${opt}"$'\n'
            done
        else
            local user_input=""
            for num in $input; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le "${#options[@]}" ]]; then
                    user_input+="$num "
                fi
            done
            selected_lines=""
            for num in $user_input; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le "${#options[@]}" ]]; then
                    selected_lines+="${options[$((10#$num - 1))]}"$'\n'
                fi
            done
        fi
    fi

    local -a packs=()
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        packs+=("${line%% *}")
    done <<< "$selected_lines"

    printf '%s' "${packs[*]}"
}

remove_dcg_hook_from_settings() {
    local settings_file="$1"

    if [[ -L "$settings_file" ]]; then
        gum_warn "Skipping DCG hook cleanup (symlink): $settings_file"
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        gum_warn "jq not available; cannot remove DCG hook automatically"
        gum_detail "Remove the dcg hook entry from: $settings_file"
        return 1
    fi

    local settings_dir
    settings_dir="$(dirname "$settings_file")"

    local tmp
    tmp="$(run_as_user mktemp "${settings_dir}/.acfs_dcg_cleanup.XXXXXX" 2>/dev/null || true)"
    if [[ -z "$tmp" ]]; then
        gum_warn "Could not update $settings_file (mktemp failed)"
        return 1
    fi

    local jq_program
    jq_program="$(cat <<'JQ'
def strip_dcg:
  if (type == "object" and has("hooks") and (.hooks | type) == "array") then
    .hooks |= [ .[]? | select(.type != "command" or ((.command // "") | test("dcg") | not)) ] |
    select((.hooks | length) > 0)
  else
    select(.type != "command" or ((.command // "") | test("dcg") | not))
  end;

.hooks = (.hooks // {}) |
if (.hooks.PreToolUse | type) != "array" then
  .hooks.PreToolUse = []
else
  .hooks.PreToolUse = [
    .hooks.PreToolUse[]?
    | strip_dcg
  ]
end
JQ
)"

    if run_as_user jq "$jq_program" "$settings_file" 2>/dev/null | run_as_user tee "$tmp" >/dev/null; then
        run_as_user mv -- "$tmp" "$settings_file" 2>/dev/null || {
            run_as_user rm -f -- "$tmp" 2>/dev/null || true
            gum_warn "Could not update $settings_file (mv failed)"
            return 1
        }
    else
        run_as_user rm -f -- "$tmp" 2>/dev/null || true
        gum_warn "Could not update $settings_file (invalid JSON?)"
        return 1
    fi

    return 0
}

cleanup_stale_dcg_hook() {
    if user_command_exists dcg; then
        return 0
    fi

    if ! dcg_hook_registered; then
        return 0
    fi

    gum_warn "DCG hook registered but dcg binary is missing"
    gum_detail "You can reinstall DCG or remove the hook registration."

    if [[ "$SERVICES_SETUP_NONINTERACTIVE" == "true" ]]; then
        gum_detail "Skipping cleanup (noninteractive)"
        return 0
    fi

    if ! gum_confirm "Remove stale DCG hook from Claude settings?"; then
        gum_warn "Skipped removing DCG hook"
        return 0
    fi

    local cleaned_any="false"
    local settings_file=""
    local settings_files=(
        "$TARGET_HOME/.claude/settings.json"
        "$TARGET_HOME/.config/claude/settings.json"
    )

    for settings_file in "${settings_files[@]}"; do
        if [[ -f "$settings_file" ]]; then
            if remove_dcg_hook_from_settings "$settings_file"; then
                cleaned_any="true"
                gum_success "Removed DCG hook from $settings_file"
            fi
        fi
    done

    if [[ "$cleaned_any" != "true" ]]; then
        gum_warn "No DCG hook entries removed"
    fi
}

# ============================================================
# Status Check Functions
# ============================================================

check_claude_status() {
    local claude_bin
    claude_bin="$(find_user_bin "claude" 2>/dev/null || true)"

    if [[ -z "$claude_bin" || ! -x "$claude_bin" ]]; then
        SERVICE_STATUS[claude]="not_installed"
        return
    fi

    if json_file_has_usable_jq_value \
        "$TARGET_HOME/.claude/.credentials.json" \
        '.claudeAiOauth.accessToken // empty | strings' || \
       { ! command -v jq >/dev/null 2>&1 && json_file_has_usable_string_key "$TARGET_HOME/.claude/.credentials.json" "accessToken"; }; then
        SERVICE_STATUS[claude]="configured"
    else
        SERVICE_STATUS[claude]="installed"
    fi
}

check_codex_status() {
    local codex_bin
    codex_bin="$(find_user_bin "codex" 2>/dev/null || true)"

    if [[ -z "$codex_bin" || ! -x "$codex_bin" ]]; then
        SERVICE_STATUS[codex]="not_installed"
        return
    fi

    if json_file_has_usable_jq_value \
        "$TARGET_HOME/.codex/auth.json" \
        '[.tokens.access_token, .access_token, .accessToken, .OPENAI_API_KEY] | .[]? | strings' || \
       { ! command -v jq >/dev/null 2>&1 && json_file_has_usable_string_key "$TARGET_HOME/.codex/auth.json" "access_token" "accessToken" "OPENAI_API_KEY"; }; then
        SERVICE_STATUS[codex]="configured"
    else
        SERVICE_STATUS[codex]="installed"
    fi
}

check_gemini_status() {
    local gemini_bin
    gemini_bin="$(find_user_bin "gemini" 2>/dev/null || true)"

    if [[ -z "$gemini_bin" || ! -x "$gemini_bin" ]]; then
        SERVICE_STATUS[gemini]="not_installed"
        return
    fi

    # Check for real Gemini OAuth state, not just a leftover or blank artifact.
    if json_file_has_usable_jq_value \
        "$TARGET_HOME/.gemini/google_accounts.json" \
        '.active // empty | strings' || \
       { ! command -v jq >/dev/null 2>&1 && json_file_has_usable_string_key "$TARGET_HOME/.gemini/google_accounts.json" "active"; } || \
       json_file_has_usable_jq_value \
        "$TARGET_HOME/.gemini/oauth_creds.json" \
        '[.access_token, .refresh_token] | .[]? | strings' || \
       { ! command -v jq >/dev/null 2>&1 && json_file_has_usable_string_key "$TARGET_HOME/.gemini/oauth_creds.json" "access_token" "refresh_token"; }; then
        SERVICE_STATUS[gemini]="configured"
    else
        SERVICE_STATUS[gemini]="installed"
    fi
}

check_vercel_status() {
    local vercel_bin
    vercel_bin="$(find_user_bin "vercel" 2>/dev/null || true)"

    if [[ -z "$vercel_bin" || ! -x "$vercel_bin" ]]; then
        SERVICE_STATUS[vercel]="not_installed"
        return
    fi

    # Check if logged in by looking for a usable auth token.
    if services_setup_has_usable_secret "${VERCEL_TOKEN:-}" || \
       json_file_has_usable_jq_value "$TARGET_HOME/.config/vercel/auth.json" '.token // empty | strings' || \
       json_file_has_usable_jq_value "$TARGET_HOME/.vercel/auth.json" '.token // empty | strings' || \
       { ! command -v jq >/dev/null 2>&1 && json_file_has_usable_string_key "$TARGET_HOME/.config/vercel/auth.json" "token"; } || \
       { ! command -v jq >/dev/null 2>&1 && json_file_has_usable_string_key "$TARGET_HOME/.vercel/auth.json" "token"; }; then
        SERVICE_STATUS[vercel]="configured"
    else
        SERVICE_STATUS[vercel]="installed"
    fi
}

check_supabase_status() {
    local supabase_bin
    supabase_bin="$(find_user_bin "supabase" 2>/dev/null || true)"

    if [[ -z "$supabase_bin" || ! -x "$supabase_bin" ]]; then
        SERVICE_STATUS[supabase]="not_installed"
        return
    fi

    # Check for access token
    if services_setup_has_usable_secret "${SUPABASE_ACCESS_TOKEN:-}"; then
        SERVICE_STATUS[supabase]="configured"
    elif file_has_usable_secret "$TARGET_HOME/.supabase/access-token" || \
         file_has_usable_secret "$TARGET_HOME/.config/supabase/access-token"; then
        SERVICE_STATUS[supabase]="configured"
    else
        SERVICE_STATUS[supabase]="installed"
    fi
}

check_wrangler_status() {
    local wrangler_bin
    wrangler_bin="$(find_user_bin "wrangler" 2>/dev/null || true)"

    if [[ -z "$wrangler_bin" || ! -x "$wrangler_bin" ]]; then
        SERVICE_STATUS[wrangler]="not_installed"
        return
    fi

    if run_as_user "$wrangler_bin" whoami >/dev/null 2>&1; then
        SERVICE_STATUS[wrangler]="configured"
    elif services_setup_has_usable_secret "${CLOUDFLARE_API_TOKEN:-}" && \
       run_as_user env CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" "$wrangler_bin" whoami >/dev/null 2>&1; then
        SERVICE_STATUS[wrangler]="configured"
    else
        SERVICE_STATUS[wrangler]="installed"
    fi
}

check_postgres_status() {
    # Check if psql is available to the target user
    if ! user_command_exists psql; then
        SERVICE_STATUS[postgres]="not_installed"
        return
    fi

    # Check if service is running and user can connect
    if run_as_user psql -c 'SELECT 1' &>/dev/null; then
        SERVICE_STATUS[postgres]="configured"
    elif systemctl is-active --quiet postgresql 2>/dev/null; then
        SERVICE_STATUS[postgres]="running"
    else
        SERVICE_STATUS[postgres]="installed"
    fi
}

check_dcg_status() {
    if ! user_command_exists dcg; then
        SERVICE_STATUS[dcg]="not_installed"
        return
    fi

    if ! user_command_exists claude; then
        SERVICE_STATUS[dcg]="installed"
        return
    fi

    if dcg_hook_registered; then
        SERVICE_STATUS[dcg]="configured"
    else
        SERVICE_STATUS[dcg]="installed"
    fi
}

check_all_status() {
    check_claude_status
    check_codex_status
    check_gemini_status
    check_vercel_status
    check_supabase_status
    check_wrangler_status
    check_postgres_status
    check_dcg_status
}

# ============================================================
# Status Display
# ============================================================

get_status_icon() {
    local status="$1"
    case "$status" in
        configured) echo "✓" ;;
        running)    echo "●" ;;
        installed)  echo "○" ;;
        *)          echo "✗" ;;
    esac
}

get_status_color() {
    local status="$1"
    case "$status" in
        configured) echo "$ACFS_SUCCESS" ;;
        running)    echo "$ACFS_WARNING" ;;
        installed)  echo "$ACFS_WARNING" ;;
        *)          echo "$ACFS_ERROR" ;;
    esac
}

print_status_table() {
    echo ""
    gum_section "Service Status"
    echo ""

    local services=("claude" "codex" "gemini" "vercel" "supabase" "wrangler" "postgres")
    local labels=("Claude Code" "Codex CLI" "Gemini CLI" "Vercel" "Supabase" "Cloudflare" "PostgreSQL")
    local categories=("AI Agent" "AI Agent" "AI Agent" "Cloud" "Cloud" "Cloud" "Database")

    if [[ "$HAS_GUM" == "true" ]]; then
        # Use gum table for beautiful display
        local table_data="Service,Category,Status,Action\n"
        for i in "${!services[@]}"; do
            local svc="${services[$i]}"
            local label="${labels[$i]}"
            local category="${categories[$i]}"
            local status="${SERVICE_STATUS[$svc]:-unknown}"
            local icon
            icon=$(get_status_icon "$status")
            local action=""
            case "$status" in
                configured) action="Ready" ;;
                running|installed) action="Needs setup" ;;
                not_installed) action="Install first" ;;
                *) action="Check" ;;
            esac
            table_data+="$icon $label,$category,$status,$action\n"
        done

        local dcg_status="${SERVICE_STATUS[dcg]:-unknown}"
        local dcg_icon
        dcg_icon=$(get_status_icon "$dcg_status")
        local dcg_action=""
        case "$dcg_status" in
            configured) dcg_action="Ready" ;;
            installed) dcg_action="Needs setup" ;;
            not_installed) dcg_action="Install first" ;;
            *) dcg_action="Check" ;;
        esac
        table_data+="$dcg_icon DCG (Destructive Command Guard),Safety,$dcg_status,$dcg_action\n"

        printf "%b\n" "$table_data" | gum table \
            --border.foreground "$ACFS_MUTED" \
            --header.foreground "$ACFS_PRIMARY"
    else
        # Fallback to simple display
        for i in "${!services[@]}"; do
            local svc="${services[$i]}"
            local label="${labels[$i]}"
            local status="${SERVICE_STATUS[$svc]:-unknown}"
            local icon
            icon=$(get_status_icon "$status")

            case "$status" in
                configured) printf "%b\n" "\033[32m  $icon $label: $status\033[0m" ;;
                running|installed) printf "%b\n" "\033[33m  $icon $label: $status\033[0m" ;;
                *) printf "%b\n" "\033[31m  $icon $label: $status\033[0m" ;;
            esac
        done

        local dcg_status="${SERVICE_STATUS[dcg]:-unknown}"
        local dcg_icon
        dcg_icon=$(get_status_icon "$dcg_status")
        case "$dcg_status" in
            configured) printf "%b\n" "\033[32m  $dcg_icon DCG (Destructive Command Guard): $dcg_status\033[0m" ;;
            running|installed) printf "%b\n" "\033[33m  $dcg_icon DCG (Destructive Command Guard): $dcg_status\033[0m" ;;
            *) printf "%b\n" "\033[31m  $dcg_icon DCG (Destructive Command Guard): $dcg_status\033[0m" ;;
        esac
    fi
    echo ""
}

# ============================================================
# Setup Functions
# ============================================================

setup_claude() {
    local claude_bin
    claude_bin="$(find_user_bin "claude" 2>/dev/null || true)"

    if [[ -z "$claude_bin" || ! -x "$claude_bin" ]]; then
        gum_error "Claude Code not installed. Run the main installer first."
        return 1
    fi

    if [[ "${SERVICE_STATUS[claude]:-unknown}" == "configured" ]]; then
        if ! gum_confirm "Claude Code appears to be configured. Reconfigure?"; then
            return 0
        fi
    fi

    gum_box "Claude Code Setup" "Claude Code uses OAuth to authenticate.
When you run 'claude', it will:
1. Open a browser window (or show a URL)
2. Ask you to log in with your Anthropic account
3. Authorize the CLI

Press Enter to launch Claude Code login..."

    read -r

    # Run claude interactively
    run_as_user "$claude_bin" || true

    # Re-check status
    check_claude_status
    if [[ "${SERVICE_STATUS[claude]:-unknown}" == "configured" ]]; then
        gum_success "Claude Code configured successfully!"
    else
        gum_warn "Claude Code may not be fully configured. Try running 'claude' again."
    fi
}

setup_codex() {
    local codex_bin
    codex_bin="$(find_user_bin "codex" 2>/dev/null || true)"

    if [[ -z "$codex_bin" || ! -x "$codex_bin" ]]; then
        gum_error "Codex CLI not installed. Run the main installer first."
        return 1
    fi

    if [[ "${SERVICE_STATUS[codex]:-unknown}" == "configured" ]]; then
        if ! gum_confirm "Codex CLI appears to be configured. Reconfigure?"; then
            return 0
        fi
    fi

    gum_box "Codex CLI Setup" "Codex works best on a headless VPS with device auth.
If you have device auth enabled in ChatGPT Settings → Security, we will launch
that flow now. If not, use the SSH tunnel fallback from the website wizard."

    gum_detail "Launching Codex device-auth login..."
    run_as_user "$codex_bin" login --device-auth || true

    check_codex_status
    if [[ "${SERVICE_STATUS[codex]:-unknown}" == "configured" ]]; then
        gum_success "Codex CLI configured successfully!"
    fi
}

configure_dcg() {
    cleanup_stale_dcg_hook

    local dcg_bin
    dcg_bin="$(find_user_bin "dcg" 2>/dev/null || true)"

    if [[ -z "$dcg_bin" || ! -x "$dcg_bin" ]]; then
        gum_error "DCG not installed. Run the main installer first."
        gum_detail "Then run: dcg install (or re-run acfs services-setup)"
        return 1
    fi

    if [[ "$SERVICES_SETUP_NONINTERACTIVE" != "true" ]]; then
        gum_box "DCG Safety Primer" "DCG (Destructive Command Guard) blocks dangerous commands before they run.

Examples it will block:
  • git reset --hard
  • rm -rf ./src
  • DROP TABLE users

When blocked, you'll see:
  • Why it matched
  • A safer alternative
  • An allow-once code for legit bypasses

Try it:
  dcg test 'git status'
  dcg test 'git reset --hard' --explain"
    fi

    if [[ "$SERVICES_SETUP_NONINTERACTIVE" != "true" ]]; then
        gum_box "DCG Setup" "DCG blocks destructive git/filesystem commands before they execute.
It also supports optional protection packs (database, Kubernetes, cloud)."
    fi

    if user_command_exists claude; then
        if dcg_hook_registered; then
            gum_success "DCG hook already registered with Claude Code"
        else
            if [[ "$SERVICES_SETUP_NONINTERACTIVE" == "true" ]]; then
                gum_detail "Registering DCG hook (noninteractive)"
                run_as_user "$dcg_bin" install --yes || gum_warn "DCG hook registration failed"
            else
                if gum_confirm "Register DCG hook for Claude Code?"; then
                    run_as_user "$dcg_bin" install || gum_warn "DCG hook registration failed"
                else
                    gum_warn "Skipped DCG hook registration"
                    gum_detail "You can enable later with: dcg install"
                fi
            fi
        fi
    else
        gum_warn "Claude Code not detected; skipping hook registration"
        gum_detail "Install Claude Code, then run: dcg install"
    fi

    if user_command_exists claude && ! run_as_user "$dcg_bin" doctor &>/dev/null; then
        gum_warn "DCG doctor reported issues"
        if [[ "$SERVICES_SETUP_NONINTERACTIVE" == "true" ]]; then
            gum_detail "Attempting DCG repair (noninteractive)"
            run_as_user "$dcg_bin" install --force --yes || gum_warn "DCG repair failed"
        else
            if gum_confirm "Attempt DCG repair by re-registering the hook?"; then
                run_as_user "$dcg_bin" install --force || gum_warn "DCG repair failed"
            else
                gum_warn "Skipped DCG repair"
            fi
        fi
    fi

    if [[ "$SERVICES_SETUP_NONINTERACTIVE" == "true" ]]; then
        gum_detail "Skipping pack selection (noninteractive)"
        return 0
    fi

    if ! gum_confirm "Enable additional DCG protection packs?"; then
        return 0
    fi

    local selected
    selected="$(select_dcg_packs)"
    if [[ -z "$selected" ]]; then
        gum_warn "No packs selected"
        return 0
    fi

    local config_dir="$TARGET_HOME/.config/dcg"
    local config_file="$config_dir/config.toml"

    if [[ -L "$config_dir" || -L "$config_file" ]]; then
        gum_error "Refusing to operate: $config_dir or $config_file is a symlink"
        return 1
    fi

    if [[ -f "$config_file" ]]; then
        if ! gum_confirm "Update existing DCG config at $config_file?"; then
            gum_warn "Skipped DCG config update"
            return 0
        fi
    fi

    run_as_user mkdir -p "$config_dir"

    {
        echo "[packs]"
        echo "enabled = ["
        for pack in $selected; do
            echo "    \"${pack}\","
        done
        echo "]"
    } | run_as_user tee "$config_file" >/dev/null

    gum_success "DCG config written to $config_file"
}


print_cli_help() {
    cat << 'EOF'
ACFS services-setup

Interactive:
  acfs services-setup

Options:
  --yes, -y    Non-interactive mode
  --install-claude-guard  Install DCG hook for Claude Code (non-interactive)
  --help, -h   Show this help
EOF
}

maybe_run_cli_action() {
    local arg

    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --yes|-y)
                SERVICES_SETUP_NONINTERACTIVE="true"
                ;;
            --install-claude-guard)
                SERVICES_SETUP_ACTION="install-claude-guard"
                SERVICES_SETUP_NONINTERACTIVE="true"
                ;;
            --help|-h)
                SERVICES_SETUP_ACTION="help"
                ;;
            *)
                ;;
        esac
        shift || true
    done

    return 0
}

run_cli_action() {
    case "${SERVICES_SETUP_ACTION:-}" in
        help)
            print_cli_help
            return 0
            ;;
        install-claude-guard)
            if ! init_target_context; then
                return 1
            fi
            configure_dcg
            return $?
            ;;
        *)
            return 1
            ;;
    esac
}

setup_gemini() {
    local gemini_bin
    gemini_bin="$(find_user_bin "gemini" 2>/dev/null || true)"

    if [[ -z "$gemini_bin" || ! -x "$gemini_bin" ]]; then
        gum_error "Gemini CLI not installed. Run the main installer first."
        return 1
    fi

    if [[ "${SERVICE_STATUS[gemini]:-unknown}" == "configured" ]]; then
        if ! gum_confirm "Gemini CLI appears to be configured. Reconfigure?"; then
            return 0
        fi
    fi

    gum_box "Gemini CLI Setup" "Gemini CLI uses Google OAuth to authenticate.
When you run 'gemini', it will:
1. Open a browser window (or show a URL)
2. Ask you to log in with your Google account
3. Authorize the CLI

Press Enter to launch Gemini login..."

    read -r

    run_as_user "$gemini_bin" || true

    check_gemini_status
    if [[ "${SERVICE_STATUS[gemini]:-unknown}" == "configured" ]]; then
        gum_success "Gemini CLI configured successfully!"
    fi
}

setup_vercel() {
    local vercel_bin
    vercel_bin="$(find_user_bin "vercel" 2>/dev/null || true)"

    if [[ -z "$vercel_bin" || ! -x "$vercel_bin" ]]; then
        gum_error "Vercel CLI not installed. Run the main installer first."
        return 1
    fi

    if [[ "${SERVICE_STATUS[vercel]:-unknown}" == "configured" ]]; then
        if ! gum_confirm "Vercel appears to be configured. Reconfigure?"; then
            return 0
        fi
    fi

    if [[ -n "${VERCEL_TOKEN:-}" ]]; then
        gum_box "Vercel Setup" "Using VERCEL_TOKEN from your environment to configure the CLI."
    else
        gum_box "Vercel Setup" "Vercel works best on a headless VPS with an access token.

If you already created one at https://vercel.com/account/tokens, export
VERCEL_TOKEN and rerun this step for a non-browser flow.

Press Enter to continue with Vercel login..."
    fi

    read -r

    if [[ -n "${VERCEL_TOKEN:-}" ]]; then
        run_as_user env VERCEL_TOKEN="$VERCEL_TOKEN" "$vercel_bin" login --token "$VERCEL_TOKEN" || true
    else
        run_as_user "$vercel_bin" login || true
    fi

    check_vercel_status
    if [[ "${SERVICE_STATUS[vercel]:-unknown}" == "configured" ]]; then
        gum_success "Vercel configured successfully!"
    fi
}

setup_supabase() {
    local supabase_bin
    supabase_bin="$(find_user_bin "supabase" 2>/dev/null || true)"

    if [[ -z "$supabase_bin" || ! -x "$supabase_bin" ]]; then
        gum_error "Supabase CLI not installed. Run the main installer first."
        return 1
    fi

    if [[ "${SERVICE_STATUS[supabase]:-unknown}" == "configured" ]]; then
        if ! gum_confirm "Supabase appears to be configured. Reconfigure?"; then
            return 0
        fi
    fi

    if [[ -n "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
        gum_box "Supabase Setup" "Using SUPABASE_ACCESS_TOKEN from your environment to configure the CLI."
    else
        gum_box "Supabase Setup" "Supabase CLI can use an access token on a headless VPS.

Note: some Supabase projects expose the direct Postgres host over IPv6-only.
If your VPS/network is IPv4-only, use the Supabase pooler connection string instead.

Press Enter to continue with Supabase login..."
    fi

    read -r

    if [[ -n "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
        run_as_user env SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" "$supabase_bin" login --token "$SUPABASE_ACCESS_TOKEN" || true
    else
        run_as_user "$supabase_bin" login --no-browser || true
    fi

    check_supabase_status
    if [[ "${SERVICE_STATUS[supabase]:-unknown}" == "configured" ]]; then
        gum_success "Supabase configured successfully!"
    fi
}

setup_wrangler() {
    local wrangler_bin
    wrangler_bin="$(find_user_bin "wrangler" 2>/dev/null || true)"

    if [[ -z "$wrangler_bin" || ! -x "$wrangler_bin" ]]; then
        gum_error "Wrangler (Cloudflare) CLI not installed. Run the main installer first."
        return 1
    fi

    if [[ "${SERVICE_STATUS[wrangler]:-unknown}" == "configured" ]]; then
        if ! gum_confirm "Cloudflare/Wrangler appears to be configured. Reconfigure?"; then
            return 0
        fi
    fi

    if [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
        gum_box "Cloudflare Wrangler Setup" "Using CLOUDFLARE_API_TOKEN from your environment.
If your workflows need it, also export CLOUDFLARE_ACCOUNT_ID."
    else
        gum_box "Cloudflare Wrangler Setup" "Wrangler browser login is awkward on a headless VPS.

Recommended flow:
1. Create an API token at https://dash.cloudflare.com/profile/api-tokens
2. Export CLOUDFLARE_API_TOKEN in your shell
3. Re-run this step (and add CLOUDFLARE_ACCOUNT_ID if your commands need it)

You can still try browser-based login if you have a browser-capable session or SSH tunnel."
    fi

    read -r

    if [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
        gum_detail "Using CLOUDFLARE_API_TOKEN from environment"
    elif gum_confirm "Try browser-based 'wrangler login' anyway?"; then
        run_as_user "$wrangler_bin" login || true
    else
        gum_warn "Skipping Wrangler OAuth. Export CLOUDFLARE_API_TOKEN and rerun this step when ready."
    fi

    check_wrangler_status
    if [[ "${SERVICE_STATUS[wrangler]:-unknown}" == "configured" ]]; then
        gum_success "Cloudflare/Wrangler configured successfully!"
    fi
}

setup_postgres() {
    if ! user_command_exists psql; then
        gum_error "PostgreSQL not installed. Run the main installer first."
        return 1
    fi

    gum_box "PostgreSQL Status" "Checking PostgreSQL configuration..."

    # Check service status
    local systemctl_bin=""
    systemctl_bin="$(services_setup_system_binary_path systemctl 2>/dev/null || true)"
    if [[ -n "$systemctl_bin" ]] && "$systemctl_bin" is-active --quiet postgresql 2>/dev/null; then
        gum_success "PostgreSQL service is running"
    else
        gum_warn "PostgreSQL service is not running"
        if gum_confirm "Start PostgreSQL service?"; then
            local -a sudo_cmd=()
            local sudo_bin=""
            if [[ $EUID -ne 0 ]]; then
                sudo_bin="$(services_setup_system_binary_path sudo 2>/dev/null || true)"
                if [[ -z "$sudo_bin" ]]; then
                    gum_error "sudo not found; cannot start PostgreSQL service"
                    return 1
                fi
                sudo_cmd=("$sudo_bin")
            fi
            if [[ -z "$systemctl_bin" ]]; then
                gum_error "systemctl not found; cannot start PostgreSQL service"
                return 1
            fi
            "${sudo_cmd[@]}" "$systemctl_bin" start postgresql
            "${sudo_cmd[@]}" "$systemctl_bin" enable postgresql
            gum_success "PostgreSQL service started and enabled"
        fi
    fi

    # Test connection
    if run_as_user psql -c 'SELECT version()' &>/dev/null; then
        gum_success "Database connection working"
        echo ""
        gum_detail "PostgreSQL version:"
        run_as_user psql -c 'SELECT version()' 2>/dev/null | head -3
    else
        gum_warn "Cannot connect to database as $TARGET_USER"
        gum_detail "This is normal if you haven't created a role yet"
        gum_detail "The installer should have created a role for you"
    fi

    check_postgres_status
}

# ============================================================
# Interactive Menu
# ============================================================

show_menu() {
    check_all_status
    print_status_table

    echo ""

    if [[ "$HAS_GUM" == "true" ]]; then
        # Build menu items with status indicators
        local -a items=()
        local services=("claude" "codex" "gemini" "dcg" "vercel" "supabase" "wrangler" "postgres")
        local labels=("Claude Code" "Codex CLI" "Gemini CLI" "DCG" "Vercel" "Supabase" "Cloudflare Wrangler" "PostgreSQL")
        local descs=("AI coding assistant" "OpenAI assistant" "Google AI assistant" "Destructive command guard" "Deployment platform" "Database platform" "Edge platform" "Local database")

        for i in "${!services[@]}"; do
            local svc="${services[$i]}"
            local label="${labels[$i]}"
            local desc="${descs[$i]}"
            local status="${SERVICE_STATUS[$svc]:-unknown}"
            local icon
            icon=$(get_status_icon "$status")
            items+=("$icon $label - $desc [$status]")
        done

        items+=("─────────────────────────────────────────")
        items+=("⚡ Configure ALL unconfigured services")
        items+=("🔄 Refresh status")
        items+=("👋 Exit")

        # Use gum filter for fuzzy search
        gum style --foreground "$ACFS_PRIMARY" --bold "What would you like to configure?"
        echo ""
        local choice
        choice=$(printf '%s\n' "${items[@]}" | gum filter \
            --indicator.foreground "$ACFS_ACCENT" \
            --match.foreground "$ACFS_SUCCESS" \
            --placeholder "Type to filter services..." \
            --height 12)

        case "$choice" in
            *"Claude"*)    setup_claude ;;
            *"Codex"*)     setup_codex ;;
            *"Gemini"*)    setup_gemini ;;
            *"DCG"*)       configure_dcg ;;
            *"Vercel"*)    setup_vercel ;;
            *"Supabase"*)  setup_supabase ;;
            *"Wrangler"*)  setup_wrangler ;;
            *"PostgreSQL"*) setup_postgres ;;
            *"ALL"*)       setup_all_unconfigured ;;
            *"Refresh"*)   return 0 ;;
            *"Exit"*)      exit 0 ;;
            *)             return 0 ;;
        esac
    else
        local choice
        choice=$(gum_choose "What would you like to configure?" \
            "1. Claude Code (AI coding assistant)" \
            "2. Codex CLI (OpenAI coding assistant)" \
            "3. Gemini CLI (Google AI assistant)" \
            "4. DCG (destructive command guard)" \
            "5. Vercel (deployment platform)" \
            "6. Supabase (database platform)" \
            "7. Cloudflare Wrangler (edge platform)" \
            "8. PostgreSQL (check database)" \
            "9. Configure ALL unconfigured services" \
            "10. Refresh status" \
            "0. Exit")

        case "$choice" in
            *"Claude"*)    setup_claude ;;
            *"Codex"*)     setup_codex ;;
            *"Gemini"*)    setup_gemini ;;
            *"DCG"*)       configure_dcg ;;
            *"Vercel"*)    setup_vercel ;;
            *"Supabase"*)  setup_supabase ;;
            *"Cloudflare"*) setup_wrangler ;;
            *"PostgreSQL"*) setup_postgres ;;
            *"ALL"*)       setup_all_unconfigured ;;
            *"Refresh"*)   return 0 ;;
            *"Exit"*)      exit 0 ;;
            *)             return 0 ;;
        esac
    fi
}

setup_all_unconfigured() {
    gum_section "Configuring All Unconfigured Services"

    local services=("claude" "codex" "gemini" "dcg" "vercel" "supabase" "wrangler")
    local labels=("Claude Code" "Codex CLI" "Gemini CLI" "DCG (Destructive Command Guard)" "Vercel" "Supabase" "Cloudflare Wrangler")
    local setup_funcs=("setup_claude" "setup_codex" "setup_gemini" "configure_dcg" "setup_vercel" "setup_supabase" "setup_wrangler")

    # Count services needing setup
    local needs_setup=0
    for i in "${!services[@]}"; do
        local status="${SERVICE_STATUS[${services[$i]}]:-unknown}"
        if [[ "$status" != "configured" && "$status" != "not_installed" ]]; then
            ((needs_setup += 1))
        fi
    done

    if [[ $needs_setup -eq 0 ]]; then
        if [[ "$HAS_GUM" == "true" ]]; then
            gum style \
                --foreground "$ACFS_SUCCESS" \
                --bold \
                "✓ All services are already configured!"
        else
            gum_success "All services are already configured!"
        fi
        return 0
    fi

    local current=0
    for i in "${!services[@]}"; do
        local svc="${services[$i]}"
        local label="${labels[$i]}"
        local func="${setup_funcs[$i]}"
        local status="${SERVICE_STATUS[$svc]:-unknown}"

        if [[ "$status" != "configured" && "$status" != "not_installed" ]]; then
            ((current += 1))
            echo ""

            if [[ "$HAS_GUM" == "true" ]]; then
                # Show wizard-style progress
                local dots=""
                for ((j = 1; j <= needs_setup; j++)); do
                    if [[ $j -lt $current ]]; then
                        dots+="$(gum style --foreground "$ACFS_SUCCESS" "●") "
                    elif [[ $j -eq $current ]]; then
                        dots+="$(gum style --foreground "$ACFS_PRIMARY" --bold "●") "
                    else
                        dots+="$(gum style --foreground "$ACFS_MUTED" "○") "
                    fi
                done

                gum style \
                    --border rounded \
                    --border-foreground "$ACFS_PRIMARY" \
                    --padding "0 2" \
                    --margin "0 0 1 0" \
                    "$(gum style --foreground "$ACFS_ACCENT" "Service $current of $needs_setup") $dots
$(gum style --foreground "$ACFS_PINK" --bold "Setting up $label...")"
            else
                gum_step "$current" "$needs_setup" "Setting up $label..."
            fi

            $func || true
        fi
    done

    # Always check postgres
    echo ""
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_MUTED" "Checking PostgreSQL status..."
    fi
    setup_postgres

    # Generate /AGENTS.md with current tool versions
    local agents_script="$SCRIPT_DIR/generate-root-agents-md.sh"
    if [[ -x "$agents_script" ]]; then
        "$agents_script" 2>/dev/null || true
    fi

    echo ""
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style \
            --border double \
            --border-foreground "$ACFS_SUCCESS" \
            --padding "1 2" \
            --margin "1 0" \
            --align center \
            "$(gum style --foreground "$ACFS_SUCCESS" --bold '✓ Setup Complete!')
$(gum style --foreground "$ACFS_TEAL" "All available services have been configured")"
    else
        gum_success "Setup complete!"
    fi
}

# ============================================================
# Main
# ============================================================

main() {
    if [[ "$HAS_GUM" == "true" ]]; then
        # Styled header
        echo ""
        gum style \
            --border double \
            --border-foreground "$ACFS_ACCENT" \
            --padding "1 3" \
            --margin "0 0 1 0" \
            "$(gum style --foreground "$ACFS_PINK" --bold '⚙️  ACFS Services Setup')
$(gum style --foreground "$ACFS_MUTED" "Configure AI agents and cloud services")"

        gum style --foreground "$ACFS_TEAL" "  User: $TARGET_USER"
    else
        print_compact_banner
        echo ""
        gum_detail "Post-install services configuration for user: $TARGET_USER"
    fi
    echo ""

    if ! init_target_context; then
        exit 1
    fi

    # Check if bun is available
    if [[ ! -x "$BUN_BIN" ]]; then
        if [[ "$HAS_GUM" == "true" ]]; then
            gum style \
                --foreground "$ACFS_ERROR" \
                --bold \
                "✖ Bun not found at $BUN_BIN"
            gum style --foreground "$ACFS_ERROR" "  Run the main ACFS installer first!"
        else
            gum_error "Bun not found at $BUN_BIN"
            gum_error "Run the main ACFS installer first!"
        fi
        exit 1
    fi

    # Main loop
    while true; do
        show_menu
        echo ""
        if [[ "$HAS_GUM" == "true" ]]; then
            if ! gum confirm \
                --prompt.foreground "$ACFS_PRIMARY" \
                --selected.foreground "$ACFS_SUCCESS" \
                "Configure more services?"; then
                break
            fi
        else
            if ! gum_confirm "Configure more services?"; then
                break
            fi
        fi
    done

    # Final status
    check_all_status
    print_status_table

    if [[ "$HAS_GUM" == "true" ]]; then
        gum style \
            --border double \
            --border-foreground "$ACFS_SUCCESS" \
            --padding "1 3" \
            --margin "1 0" \
            --align center \
            "$(gum style --foreground "$ACFS_SUCCESS" --bold '🎉 Services Setup Complete!')

$(gum style --foreground "$ACFS_TEAL" 'Your ACFS environment is configured!')

$(gum style --foreground "$ACFS_MUTED" 'Next steps:')
$(gum style --foreground "$ACFS_PRIMARY" '  • Start coding with:') $(gum style --foreground "$ACFS_ACCENT" 'cc') $(gum style --foreground "$ACFS_MUTED" '(Claude Code)')
$(gum style --foreground "$ACFS_PRIMARY" '  • Create a project:') $(gum style --foreground "$ACFS_ACCENT" 'ntm new myproject')
$(gum style --foreground "$ACFS_PRIMARY" '  • Run the onboarding:') $(gum style --foreground "$ACFS_ACCENT" 'onboard')

$(gum style --foreground "$ACFS_PINK" --bold '  Happy coding! 🚀')"
    else
        gum_completion "Services Setup Complete" "Your ACFS environment is configured!

Next steps:
  • Start coding with: cc (Claude Code)
  • Create a project session: ntm new myproject
  • Run the onboarding: onboard

Happy coding!"
    fi
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    maybe_run_cli_action "$@"
    if [[ -n "${SERVICES_SETUP_ACTION:-}" ]]; then
        run_cli_action
        exit $?
    fi
    main "$@"
fi
