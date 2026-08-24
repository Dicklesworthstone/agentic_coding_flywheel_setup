#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Installer - Language Runtimes Library
# Installs Bun, uv (Python), Rust, and Go
# ============================================================

LANG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure we have logging functions available
if [[ -z "${ACFS_BLUE:-}" ]]; then
    # shellcheck source=logging.sh
    source "$LANG_SCRIPT_DIR/logging.sh"
fi

# ============================================================
# Configuration
# ============================================================

# Version constraints (for documentation; installers fetch latest)
# shellcheck disable=SC2034  # Used for reference
declare -gA LANGUAGE_VERSIONS=(
    [bun]="latest"
    [uv]="latest"
    [rust]="stable"
    [go]="system"  # apt package
)

# ============================================================
# Helper Functions
# ============================================================

# Check if a command exists
_lang_command_exists() {
    local cmd="${1:-}"

    [[ -n "$cmd" ]] || return 1
    case "$cmd" in
        .|..) return 1 ;;
        *[!A-Za-z0-9._+-]*) return 1 ;;
    esac

    command -v "$cmd" &>/dev/null
}

_lang_remove_temp_dir() {
    local tmpdir="${1:-}"
    if [[ -n "$tmpdir" && -d "$tmpdir" ]]; then
        rm -rf -- "$tmpdir" 2>/dev/null || true
    fi
}

# Get the sudo command if needed
_lang_get_sudo() {
    if [[ $EUID -eq 0 ]]; then
        echo ""
    else
        echo "sudo"
    fi
}

_lang_existing_abs_home() {
    local home_candidate="${1:-}"

    [[ -n "$home_candidate" ]] || return 1
    home_candidate="${home_candidate%/}"
    [[ -n "$home_candidate" ]] || return 1
    [[ "$home_candidate" == /* ]] || return 1
    [[ "$home_candidate" != "/" ]] || return 1
    [[ -d "$home_candidate" ]] || return 1
    printf '%s\n' "$home_candidate"
}

_lang_system_binary_path() {
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

_lang_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(_lang_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(_lang_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

_lang_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(_lang_system_binary_path getent 2>/dev/null || true)"
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

_lang_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    passwd_home="$(_lang_existing_abs_home "$passwd_home" 2>/dev/null || true)"
    [[ -n "$passwd_home" ]] || return 1
    printf '%s\n' "$passwd_home"
}

_lang_target_home() {
    local target_user="${1:-${TARGET_USER:-ubuntu}}"
    local explicit_home=""
    local passwd_entry=""
    local current_user=""
    local current_home=""

    explicit_home="$(_lang_existing_abs_home "${TARGET_HOME:-}" 2>/dev/null || true)"
    current_user="$(_lang_resolve_current_user 2>/dev/null || true)"
    if [[ "$target_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi
    if [[ -n "$explicit_home" && -z "${TARGET_USER:-}" && "$target_user" == "$current_user" ]]; then
        printf '%s\n' "$explicit_home"
        return 0
    fi

    passwd_entry="$(_lang_getent_passwd_entry "$target_user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        passwd_entry="$(_lang_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            printf '%s\n' "${passwd_entry%/}"
            return 0
        fi
    fi

    if [[ "$current_user" == "$target_user" ]]; then
        current_home="$(_lang_existing_abs_home "${HOME:-}" 2>/dev/null || true)"
        if [[ -n "$current_home" ]] && { [[ -z "$explicit_home" ]] || [[ "$current_home" == "$explicit_home" ]]; }; then
            printf '%s\n' "$current_home"
            return 0
        fi
    fi

    if [[ -n "$explicit_home" ]]; then
        printf '%s\n' "$explicit_home"
        return 0
    fi

    return 1
}

_lang_validate_bin_dir_for_home() {
    local bin_dir="${1:-}"
    local base_home="${2:-}"
    local passwd_line=""
    local passwd_home=""
    local hinted_home=""

    bin_dir="${bin_dir%/}"
    [[ -n "$bin_dir" ]] || return 1
    [[ "$bin_dir" == /* ]] || return 1
    [[ "$bin_dir" != "/" ]] || return 1
    base_home="$(_lang_existing_abs_home "$base_home" 2>/dev/null || true)"

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
    hinted_home="${hinted_home%/}"
    if [[ "$hinted_home" != /* ]] || [[ "$hinted_home" == "/" ]]; then
        hinted_home=""
    fi
    if [[ -n "$hinted_home" ]] && [[ -n "$base_home" ]] && [[ "$hinted_home" != "$base_home" ]]; then
        return 1
    fi

    while IFS= read -r passwd_line; do
        passwd_home="$(_lang_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
        [[ -n "$passwd_home" ]] || continue
        [[ -n "$base_home" && "$passwd_home" == "$base_home" ]] && continue
        if [[ "$bin_dir" == "$passwd_home" || "$bin_dir" == "$passwd_home/"* ]]; then
            return 1
        fi
    done < <(_lang_getent_passwd_entry 2>/dev/null || true)

    printf '%s\n' "$bin_dir"
}

_lang_preferred_bin_dir() {
    local target_home="${1:-}"
    local candidate=""

    [[ -n "$target_home" ]] || return 1

    candidate="$(_lang_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$target_home" 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    printf '%s\n' "$target_home/.local/bin"
}

_lang_validate_target_user() {
    local username="${1:-${TARGET_USER:-}}"
    local display="${username:-<empty>}"

    if [[ "$username" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
        return 0
    fi

    log_error "Invalid TARGET_USER '$display' (expected: lowercase user name like 'ubuntu')"
    return 1
}

# Run a command as target user
_lang_run_as_user() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    local target_path_prefix=""
    local preferred_bin_dir=""
    local cmd="$1"
    local target_user_q=""
    local target_home_q=""
    local target_path_prefix_q=""
    local acfs_home_q=""
    local acfs_bin_dir_q=""
    local wrapped_cmd=""
    local bash_bin=""
    local sudo_bin=""
    local runuser_bin=""
    local su_bin=""

    _lang_validate_target_user "$target_user" || return 1
    bash_bin="$(_lang_system_binary_path bash 2>/dev/null || true)"
    [[ -n "$bash_bin" ]] || {
        log_error "Unable to locate bash for target-user language command"
        return 1
    }

    target_home="$(_lang_target_home "$target_user" 2>/dev/null || true)"
    if [[ -z "$target_home" ]] || [[ "$target_home" == "/" ]] || [[ "$target_home" != /* ]]; then
        log_error "Invalid TARGET_HOME for '$target_user': ${target_home:-<empty>} (must be an absolute path and cannot be '/')"
        return 1
    fi

    if [[ -n "${ACFS_BIN_DIR:-}" ]] && { [[ "${ACFS_BIN_DIR}" == "/" ]] || [[ "${ACFS_BIN_DIR}" != /* ]]; }; then
        log_error "ACFS_BIN_DIR must be an absolute path and cannot be '/' (got: ${ACFS_BIN_DIR:-<empty>})"
        return 1
    fi

    preferred_bin_dir="$(_lang_preferred_bin_dir "$target_home" 2>/dev/null || true)"
    [[ -n "$preferred_bin_dir" ]] || preferred_bin_dir="$target_home/.local/bin"
    target_path_prefix="$preferred_bin_dir:$target_home/.local/bin:$target_home/.acfs/bin:$target_home/.cargo/bin:$target_home/.bun/bin:$target_home/.atuin/bin:$target_home/go/bin"

    printf -v target_user_q '%q' "$target_user"
    printf -v target_home_q '%q' "$target_home"
    printf -v target_path_prefix_q '%q' "$target_path_prefix"
    if [[ -n "${ACFS_HOME:-}" ]]; then
        printf -v acfs_home_q '%q' "$ACFS_HOME"
    fi
    printf -v acfs_bin_dir_q '%q' "$preferred_bin_dir"

    wrapped_cmd="export TARGET_USER=$target_user_q TARGET_HOME=$target_home_q HOME=$target_home_q;"
    if [[ -n "$acfs_home_q" ]]; then
        wrapped_cmd+=" export ACFS_HOME=$acfs_home_q;"
    fi
    wrapped_cmd+=" export ACFS_BIN_DIR=$acfs_bin_dir_q;"
    wrapped_cmd+=" export PATH=$target_path_prefix_q:\$PATH; set -o pipefail; cd \"\$HOME\" || exit 1; $cmd"

    if [[ "$(_lang_resolve_current_user 2>/dev/null || true)" == "$target_user" ]]; then
        "$bash_bin" -c "$wrapped_cmd"
        return $?
    fi

    sudo_bin="$(_lang_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        "$sudo_bin" -n -u "$target_user" -H "$bash_bin" -c "$wrapped_cmd"
        return $?
    fi

    runuser_bin="$(_lang_system_binary_path runuser 2>/dev/null || true)"
    if [[ -n "$runuser_bin" ]]; then
        "$runuser_bin" -u "$target_user" -- "$bash_bin" -c "$wrapped_cmd"
        return $?
    fi

    su_bin="$(_lang_system_binary_path su 2>/dev/null || true)"
    [[ -n "$su_bin" ]] || {
        log_error "Unable to locate sudo, runuser, or su for target-user language command"
        return 1
    }

    # Avoid login shells: profile files are not a stable API and can break non-interactive runs.
    "$su_bin" "$target_user" -c "$(printf '%q' "$bash_bin") -c $(printf %q "$wrapped_cmd")"
}

# Load security helpers + checksums.yaml (fail closed if unavailable).
LANG_SECURITY_READY=false
_lang_require_security() {
    if [[ "${LANG_SECURITY_READY}" == "true" ]]; then
        return 0
    fi

    if [[ ! -f "$LANG_SCRIPT_DIR/security.sh" ]]; then
        log_warn "Security library not found ($LANG_SCRIPT_DIR/security.sh); refusing to run upstream installer scripts"
        return 1
    fi

    # shellcheck source=security.sh
    source "$LANG_SCRIPT_DIR/security.sh"
    if ! load_checksums; then
        log_warn "checksums.yaml not available; refusing to run upstream installer scripts"
        return 1
    fi

    LANG_SECURITY_READY=true
    return 0
}

# Ensure ~/.local/bin exists for target user
_lang_ensure_local_bin() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_lang_target_home "$target_user")"
    local local_bin="$target_home/.local/bin"

    if [[ ! -d "$local_bin" ]]; then
        local local_bin_q=""
        printf -v local_bin_q '%q' "$local_bin"
        log_detail "Creating $local_bin"
        _lang_run_as_user "mkdir -p $local_bin_q"
    fi
}

# ============================================================
# Bun Installation
# ============================================================

# Install Bun JavaScript/TypeScript runtime
# Installs to ~/.bun/bin/bun
install_bun() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_lang_target_home "$target_user")"
    local bun_dir="$target_home/.bun"
    local bun_bin="$bun_dir/bin/bun"

    # Check if already installed
    if [[ -x "$bun_bin" ]]; then
        log_detail "Bun already installed at $bun_bin"
        return 0
    fi

    log_detail "Installing Bun for $target_user..."

    # Run Bun installer as target user
    if ! _lang_require_security; then
        return 1
    fi

    local url="${KNOWN_INSTALLERS[bun]}"
    local expected_sha256
    expected_sha256="$(get_checksum bun)"
    if [[ -z "$expected_sha256" ]]; then
        log_warn "No checksum recorded for bun; refusing to run unverified installer"
        return 1
    fi

    local security_lib_q=""
    local url_q=""
    local expected_sha256_q=""
    printf -v security_lib_q '%q' "$LANG_SCRIPT_DIR/security.sh"
    printf -v url_q '%q' "$url"
    printf -v expected_sha256_q '%q' "$expected_sha256"
    if ! _lang_run_as_user "source $security_lib_q; fetch_and_run_with_runner bash $url_q $expected_sha256_q bun"; then
        log_warn "Bun installation failed"
        return 1
    fi

    # Verify installation
    if [[ -x "$bun_bin" ]]; then
        local version
        local bun_bin_q=""
        printf -v bun_bin_q '%q' "$bun_bin"
        version=$(_lang_run_as_user "$bun_bin_q --version" 2>/dev/null || echo "unknown")
        log_success "Bun $version installed"
        return 0
    else
        log_warn "Bun binary not found after installation"
        return 1
    fi
}

# Upgrade Bun to latest version
upgrade_bun() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_lang_target_home "$target_user")"
    local bun_bin="$target_home/.bun/bin/bun"

    if [[ ! -x "$bun_bin" ]]; then
        log_warn "Bun not installed, installing instead"
        install_bun
        return $?
    fi

    log_detail "Upgrading Bun..."
    local bun_bin_q=""
    printf -v bun_bin_q '%q' "$bun_bin"
    _lang_run_as_user "$bun_bin_q upgrade" && log_success "Bun upgraded"
}

# ============================================================
# uv Installation (Python tooling)
# ============================================================

# Install uv - extremely fast Python package manager
# Installs to ~/.local/bin/uv
install_uv() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_lang_target_home "$target_user")"
    local uv_bin="$target_home/.local/bin/uv"

    # Check if already installed
    if [[ -x "$uv_bin" ]]; then
        log_detail "uv already installed at $uv_bin"
        return 0
    fi

    log_detail "Installing uv for $target_user..."

    # Ensure ~/.local/bin exists
    _lang_ensure_local_bin

    # Run uv installer as target user
    if ! _lang_require_security; then
        return 1
    fi

    local url="${KNOWN_INSTALLERS[uv]}"
    local expected_sha256
    expected_sha256="$(get_checksum uv)"
    if [[ -z "$expected_sha256" ]]; then
        log_warn "No checksum recorded for uv; refusing to run unverified installer"
        return 1
    fi

    local security_lib_q=""
    local url_q=""
    local expected_sha256_q=""
    printf -v security_lib_q '%q' "$LANG_SCRIPT_DIR/security.sh"
    printf -v url_q '%q' "$url"
    printf -v expected_sha256_q '%q' "$expected_sha256"
    if ! _lang_run_as_user "source $security_lib_q; fetch_and_run_with_runner sh $url_q $expected_sha256_q uv"; then
        log_warn "uv installation failed"
        return 1
    fi

    # Verify installation
    if [[ -x "$uv_bin" ]]; then
        local version
        local uv_bin_q=""
        printf -v uv_bin_q '%q' "$uv_bin"
        version=$(_lang_run_as_user "$uv_bin_q --version" 2>/dev/null || echo "unknown")
        log_success "uv $version installed"
        return 0
    else
        log_warn "uv binary not found after installation"
        return 1
    fi
}

# Note: uv environment configuration (UV_LINK_MODE=copy) is handled
# by acfs/zsh/acfs.zshrc, not at install time.

# Upgrade uv to latest version
upgrade_uv() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_lang_target_home "$target_user")"
    local uv_bin="$target_home/.local/bin/uv"

    if [[ ! -x "$uv_bin" ]]; then
        log_warn "uv not installed, installing instead"
        install_uv
        return $?
    fi

    log_detail "Upgrading uv..."
    local uv_bin_q=""
    printf -v uv_bin_q '%q' "$uv_bin"
    _lang_run_as_user "$uv_bin_q self update" && log_success "uv upgraded"
}

# ============================================================
# Rust Installation
# ============================================================

# Install Rust via rustup
# Installs to ~/.cargo/bin/
install_rust() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_lang_target_home "$target_user")"
    local cargo_bin="$target_home/.cargo/bin/cargo"

    # Check if already installed
    if [[ -x "$cargo_bin" ]]; then
        log_detail "Rust already installed at $cargo_bin"
        return 0
    fi

    log_detail "Installing Rust for $target_user..."

    # Run rustup installer as target user (-y for non-interactive)
    if ! _lang_require_security; then
        return 1
    fi

    local url="${KNOWN_INSTALLERS[rust]}"
    local expected_sha256
    expected_sha256="$(get_checksum rust)"
    if [[ -z "$expected_sha256" ]]; then
        log_warn "No checksum recorded for rust; refusing to run unverified installer"
        return 1
    fi

    local security_lib_q=""
    local url_q=""
    local expected_sha256_q=""
    printf -v security_lib_q '%q' "$LANG_SCRIPT_DIR/security.sh"
    printf -v url_q '%q' "$url"
    printf -v expected_sha256_q '%q' "$expected_sha256"
    if ! _lang_run_as_user "source $security_lib_q; fetch_and_run_with_runner sh $url_q $expected_sha256_q rust -y"; then
        log_warn "Rust installation failed"
        return 1
    fi

    # Verify installation
    if [[ -x "$cargo_bin" ]]; then
        local version
        local cargo_bin_q=""
        printf -v cargo_bin_q '%q' "$cargo_bin"
        version=$(_lang_run_as_user "$cargo_bin_q --version" 2>/dev/null || echo "unknown")
        log_success "Rust $version installed"
        return 0
    else
        log_warn "Cargo binary not found after installation"
        return 1
    fi
}

# Upgrade Rust to latest stable
upgrade_rust() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_lang_target_home "$target_user")"
    local rustup_bin="$target_home/.cargo/bin/rustup"

    if [[ ! -x "$rustup_bin" ]]; then
        log_warn "Rust not installed, installing instead"
        install_rust
        return $?
    fi

    log_detail "Upgrading Rust..."
    local rustup_bin_q=""
    printf -v rustup_bin_q '%q' "$rustup_bin"
    _lang_run_as_user "$rustup_bin_q update stable" && log_success "Rust upgraded"
}

# ============================================================
# Go Installation
# ============================================================

# Install Go via apt (system package)
# For latest version, use install_go_latest
install_go() {
    local sudo_cmd
    sudo_cmd=$(_lang_get_sudo)

    # Check if already installed
    if _lang_command_exists go; then
        log_detail "Go already installed"
        return 0
    fi

    log_detail "Installing Go via apt..."

    # Update package list and install
    $sudo_cmd apt-get -o DPkg::Lock::Timeout=120 update -y >/dev/null 2>&1 || true

    if $sudo_cmd apt-get -o DPkg::Lock::Timeout=120 install -y golang-go >/dev/null 2>&1; then
        local version
        version=$(go version 2>/dev/null | cut -d' ' -f3 || echo "unknown")
        log_success "Go $version installed"
        return 0
    else
        log_warn "Go installation via apt failed"
        return 1
    fi
}

# Install latest Go from go.dev (alternative to apt)
install_go_latest() {
    local sudo_cmd
    sudo_cmd=$(_lang_get_sudo)

    log_detail "Installing latest Go from go.dev..."

    # Detect architecture
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)
            log_warn "Unsupported architecture for Go: $arch"
            return 1
            ;;
    esac

    # Get latest version
    local version="go1.23.4"
    local version_response=""
    version_response="$(curl --proto '=https' --proto-redir '=https' -fsSL --max-time 10 'https://go.dev/VERSION?m=text' 2>/dev/null)" || version_response=""
    local fetched_version="${version_response%%$'\n'*}"
    fetched_version="${fetched_version%%$'\r'}"
    if [[ "$fetched_version" =~ ^go[0-9]+(\.[0-9]+)*$ ]]; then
        version="$fetched_version"
    fi

    # Download and install
    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/acfs_go.XXXXXX" 2>/dev/null)" || tmpdir=""
    if [[ -z "$tmpdir" ]] || [[ ! -d "$tmpdir" ]]; then
        log_warn "mktemp failed; cannot install Go"
        return 1
    fi
    local tarball="${version}.linux-${arch}.tar.gz"

    log_detail "Downloading $tarball..."
    if ! curl --proto '=https' --proto-redir '=https' -fsSL -o "$tmpdir/$tarball" "https://go.dev/dl/$tarball"; then
        log_warn "Failed to download Go"
        _lang_remove_temp_dir "$tmpdir"
        return 1
    fi

    # Remove old installation and extract new one
    if ! $sudo_cmd rm -rf -- /usr/local/go; then
        log_warn "Failed to remove existing Go installation"
        _lang_remove_temp_dir "$tmpdir"
        return 1
    fi
    if ! $sudo_cmd tar -C /usr/local -xzf "$tmpdir/$tarball"; then
        log_warn "Failed to extract Go"
        _lang_remove_temp_dir "$tmpdir"
        return 1
    fi
    _lang_remove_temp_dir "$tmpdir"

    # Create symlinks
    if ! $sudo_cmd ln -sf /usr/local/go/bin/go /usr/local/bin/go; then
        log_warn "Failed to link go binary"
        return 1
    fi
    if ! $sudo_cmd ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt; then
        log_warn "Failed to link gofmt binary"
        return 1
    fi

    local installed_version
    installed_version=$(/usr/local/go/bin/go version 2>/dev/null | cut -d' ' -f3 || echo "unknown")
    log_success "Go $installed_version installed"
}

# ============================================================
# Verification Functions
# ============================================================

# Verify all language runtimes are installed
verify_languages() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_lang_target_home "$target_user")"
    local all_pass=true

    log_detail "Verifying language runtimes..."

    # Check Bun
    if [[ -x "$target_home/.bun/bin/bun" ]]; then
        log_detail "  bun: $("$target_home"/.bun/bin/bun --version 2>/dev/null || echo 'installed')"
    else
        log_warn "  Missing: bun"
        all_pass=false
    fi

    # Check uv
    if [[ -x "$target_home/.local/bin/uv" ]]; then
        log_detail "  uv: $("$target_home"/.local/bin/uv --version 2>/dev/null | head -1 || echo 'installed')"
    else
        log_warn "  Missing: uv"
        all_pass=false
    fi

    # Check Rust/Cargo
    if [[ -x "$target_home/.cargo/bin/cargo" ]]; then
        log_detail "  cargo: $("$target_home"/.cargo/bin/cargo --version 2>/dev/null || echo 'installed')"
    else
        log_warn "  Missing: cargo (rust)"
        all_pass=false
    fi

    # Check Go
    if _lang_command_exists go; then
        log_detail "  go: $(go version 2>/dev/null | cut -d' ' -f3 || echo 'installed')"
    else
        log_warn "  Missing: go"
        all_pass=false
    fi

    if [[ "$all_pass" == "true" ]]; then
        log_success "All language runtimes verified"
        return 0
    else
        log_warn "Some language runtimes are missing"
        return 1
    fi
}

# Get versions of installed languages (for doctor output)
get_language_versions() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_lang_target_home "$target_user")"

    echo "Language Runtime Versions:"

    [[ -x "$target_home/.bun/bin/bun" ]] && echo "  bun: $("$target_home"/.bun/bin/bun --version 2>/dev/null)"
    [[ -x "$target_home/.local/bin/uv" ]] && echo "  uv: $("$target_home"/.local/bin/uv --version 2>/dev/null | head -1)"
    [[ -x "$target_home/.cargo/bin/cargo" ]] && echo "  cargo: $("$target_home"/.cargo/bin/cargo --version 2>/dev/null)"
    [[ -x "$target_home/.cargo/bin/rustc" ]] && echo "  rustc: $("$target_home"/.cargo/bin/rustc --version 2>/dev/null)"
    _lang_command_exists go && echo "  go: $(go version 2>/dev/null | cut -d' ' -f3)"
}

# ============================================================
# Main Installation Function
# ============================================================

# Install all language runtimes (called by install.sh)
install_all_languages() {
    log_step "5/8" "Installing language runtimes..."

    # Install each language runtime
    install_bun
    install_uv
    install_rust
    install_go

    # Verify installation
    verify_languages

    log_success "Language runtimes installation complete"
}

# ============================================================
# Module can be sourced or run directly
# ============================================================

# If run directly (not sourced), execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_all_languages "$@"
fi
