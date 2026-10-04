#!/usr/bin/env bash
# ============================================================
# ACFS Installer - OS Detection Library
# Detects and validates the operating system
#
# Requires: logging.sh to be sourced first for log_* functions
# ============================================================

# Fallback logging if logging.sh not sourced
if ! declare -f log_fatal &>/dev/null; then
    log_fatal() { echo "FATAL: $1" >&2; exit 1; }
    log_detail() { echo "  $1" >&2; }
    log_warn() { echo "WARN: $1" >&2; }
    log_success() { echo "OK: $1" >&2; }
fi

os_detect_system_binary_path() {
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

os_detect_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

os_detect_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(os_detect_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(os_detect_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

os_detect_getent_passwd_entry() {
    local user="${1:-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""

    [[ -n "$user" ]] || return 1

    getent_bin="$(os_detect_system_binary_path getent 2>/dev/null || true)"
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

os_detect_passwd_home_from_entry() {
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
    passwd_home="$(os_detect_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
    [[ -n "$passwd_home" ]] || return 1
    printf '%s\n' "$passwd_home"
}

detect_os() {
    local os_release_file="${ACFS_OS_RELEASE_PATH:-/etc/os-release}"

    if [[ ! -f "$os_release_file" ]]; then
        log_fatal "Cannot detect OS. $os_release_file not found."
    fi

    # shellcheck disable=SC1090
    source "$os_release_file"

    export OS_ID="$ID"
    export OS_VERSION="$VERSION_ID"
    export OS_VERSION_MAJOR="${VERSION_ID%%.*}"
    export OS_CODENAME="${VERSION_CODENAME:-unknown}"

    log_detail "Detected: $PRETTY_NAME"
}

# Validate that we're running on a supported OS
# Returns 0 if supported, 1 if not (but continues with warning)
validate_os() {
    detect_os

    if [[ "$OS_ID" != "ubuntu" ]]; then
        log_warn "ACFS is designed for Ubuntu but detected: $OS_ID"
        log_warn "Proceeding anyway, but some features may not work correctly."
        return 1
    fi

    if [[ "$OS_VERSION_MAJOR" -lt 24 ]]; then
        log_warn "Ubuntu $OS_VERSION detected. Recommended: Ubuntu 24.04 or 26.04 LTS"
        log_warn "Some packages may not be available in older versions."
        return 1
    fi

    log_success "OS validated: Ubuntu $OS_VERSION"
    return 0
}

# Check if running on a fresh VPS (heuristic)
# Returns 0 if likely fresh, 1 otherwise
is_fresh_vps() {
    local indicators=0

    # Check for minimal packages
    if ! command -v git &>/dev/null; then
        ((indicators += 1))
    fi

    # Check for default ubuntu user without customization
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    local explicit_target_home="${TARGET_HOME:-}"
    local resolved_target_home=""
    local current_home=""
    local current_user=""
    local passwd_entry=""
    if [[ -n "$explicit_target_home" ]]; then
        explicit_target_home="${explicit_target_home%/}"
    fi
    passwd_entry="$(os_detect_getent_passwd_entry "$target_user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        resolved_target_home="$(os_detect_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
    elif [[ "$target_user" == "root" ]]; then
        resolved_target_home="/root"
    else
        current_user="$(os_detect_resolve_current_user 2>/dev/null || true)"
    fi
    if [[ -z "$resolved_target_home" && "$target_user" == "$current_user" ]] && [[ -n "${HOME:-}" ]]; then
        current_home="${HOME%/}"
        if [[ "$current_home" == /* ]] && [[ "$current_home" != "/" ]] && { [[ -z "$explicit_target_home" ]] || [[ "$current_home" == "$explicit_target_home" ]]; }; then
            resolved_target_home="$current_home"
        fi
        if [[ -z "$resolved_target_home" ]] && [[ "$explicit_target_home" == /* ]] && [[ "$explicit_target_home" != "/" ]]; then
            resolved_target_home="$explicit_target_home"
        fi
    fi
    if [[ -n "$resolved_target_home" ]]; then
        if [[ "$resolved_target_home" == /* ]] && [[ "$resolved_target_home" != "/" ]]; then
            target_home="${resolved_target_home%/}"
        fi
    fi
    if [[ -z "$target_home" ]]; then
        return 1
    fi

    if [[ -f "$target_home/.bashrc" ]] && ! grep -q "ACFS" "$target_home/.bashrc" 2>/dev/null; then
        ((indicators += 1))
    fi

    # Check for minimal installed packages
    local pkg_count
    pkg_count=$(dpkg -l 2>/dev/null | wc -l)
    if [[ $pkg_count -lt 500 ]]; then
        ((indicators += 1))
    fi

    if [[ $indicators -ge 2 ]]; then
        log_detail "Detected fresh VPS environment"
        return 0
    fi

    log_detail "Detected existing system with customizations"
    return 1
}

# Get architecture
get_arch() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

# Check if running in WSL
is_wsl() {
    local version_file="${ACFS_PROC_VERSION:-/proc/version}"
    if grep -qi microsoft "$version_file" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Check if running in Docker
is_docker() {
    local dockerenv="${ACFS_DOCKERENV:-/.dockerenv}"
    local cgroup="${ACFS_CGROUP:-/proc/1/cgroup}"

    if [[ -f "$dockerenv" ]]; then
        return 0
    fi
    if grep -q docker "$cgroup" 2>/dev/null; then
        return 0
    fi
    return 1
}
