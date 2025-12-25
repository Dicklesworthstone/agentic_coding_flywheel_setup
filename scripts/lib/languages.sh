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
    command -v "$1" &>/dev/null
}

# Get the sudo command if needed
_lang_get_sudo() {
    if [[ $EUID -eq 0 ]]; then
        echo ""
    else
        echo "sudo"
    fi
}

# Run a command as target user
_lang_run_as_user() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local cmd="$1"
    local wrapped_cmd="set -o pipefail; $cmd"

    if [[ "$(whoami)" == "$target_user" ]]; then
        bash -c "$wrapped_cmd"
        return $?
    fi

    if command -v sudo &>/dev/null; then
        sudo -u "$target_user" -H bash -c "$wrapped_cmd"
        return $?
    fi

    if command -v runuser &>/dev/null; then
        runuser -u "$target_user" -- bash -c "$wrapped_cmd"
        return $?
    fi

    # Avoid login shells: profile files are not a stable API and can break non-interactive runs.
    su "$target_user" -c "bash -c $(printf %q "$wrapped_cmd")"
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
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local local_bin="$target_home/.local/bin"

    if [[ ! -d "$local_bin" ]]; then
        log_detail "Creating $local_bin"
        _lang_run_as_user "mkdir -p '$local_bin'"
    fi
}

# ============================================================
# Bun Installation
# ============================================================

# Install Bun JavaScript/TypeScript runtime
# Installs to ~/.bun/bin/bun
install_bun() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
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

    if ! _lang_run_as_user "source '$LANG_SCRIPT_DIR/security.sh'; verify_checksum '$url' '$expected_sha256' 'bun' | bash"; then
        log_warn "Bun installation failed"
        return 1
    fi

    # Verify installation
    if [[ -x "$bun_bin" ]]; then
        local version
        version=$(_lang_run_as_user "$bun_bin --version" 2>/dev/null || echo "unknown")
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
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local bun_bin="$target_home/.bun/bin/bun"

    if [[ ! -x "$bun_bin" ]]; then
        log_warn "Bun not installed, installing instead"
        install_bun
        return $?
    fi

    log_detail "Upgrading Bun..."
    _lang_run_as_user "$bun_bin upgrade" && log_success "Bun upgraded"
}

# ============================================================
# uv Installation (Python tooling)
# ============================================================

# Install uv - extremely fast Python package manager
# Installs to ~/.local/bin/uv
install_uv() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
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

    if ! _lang_run_as_user "source '$LANG_SCRIPT_DIR/security.sh'; verify_checksum '$url' '$expected_sha256' 'uv' | sh"; then
        log_warn "uv installation failed"
        return 1
    fi

    # Verify installation
    if [[ -x "$uv_bin" ]]; then
        local version
        version=$(_lang_run_as_user "$uv_bin --version" 2>/dev/null || echo "unknown")
        log_success "uv $version installed"
        return 0
    else
        log_warn "uv binary not found after installation"
        return 1
    fi
}

# Configure uv environment variables
configure_uv() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"

    # UV_LINK_MODE=copy is recommended for Docker/VPS environments
    # This will be set in acfs.zshrc, but log it for clarity
    log_detail "uv configured with UV_LINK_MODE=copy (set in acfs.zshrc)"
}

# Upgrade uv to latest version
upgrade_uv() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local uv_bin="$target_home/.local/bin/uv"

    if [[ ! -x "$uv_bin" ]]; then
        log_warn "uv not installed, installing instead"
        install_uv
        return $?
    fi

    log_detail "Upgrading uv..."
    _lang_run_as_user "$uv_bin self update" && log_success "uv upgraded"
}

# ============================================================
# Rust Installation
# ============================================================

# Install Rust via rustup
# Installs to ~/.cargo/bin/
install_rust() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
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

    if ! _lang_run_as_user "source '$LANG_SCRIPT_DIR/security.sh'; verify_checksum '$url' '$expected_sha256' 'rust' | sh -s -- -y"; then
        log_warn "Rust installation failed"
        return 1
    fi

    # Verify installation
    if [[ -x "$cargo_bin" ]]; then
        local version
        version=$(_lang_run_as_user "$cargo_bin --version" 2>/dev/null || echo "unknown")
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
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local rustup_bin="$target_home/.cargo/bin/rustup"

    if [[ ! -x "$rustup_bin" ]]; then
        log_warn "Rust not installed, installing instead"
        install_rust
        return $?
    fi

    log_detail "Upgrading Rust..."
    _lang_run_as_user "$rustup_bin update stable" && log_success "Rust upgraded"
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
    $sudo_cmd apt-get update -y >/dev/null 2>&1 || true

    if $sudo_cmd apt-get install -y golang-go >/dev/null 2>&1; then
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
    local version
    version=$(curl --proto '=https' --proto-redir '=https' -sL 'https://go.dev/VERSION?m=text' | head -1) || version="go1.23.4"

    # Download and install
    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/acfs_go.XXXXXX")
    local tarball="${version}.linux-${arch}.tar.gz"

    log_detail "Downloading $tarball..."
    if ! curl --proto '=https' --proto-redir '=https' -fsSL -o "$tmpdir/$tarball" "https://go.dev/dl/$tarball"; then
        log_warn "Failed to download Go"
        rm -rf "$tmpdir"
        return 1
    fi

    # Remove old installation and extract new one
    $sudo_cmd rm -rf /usr/local/go
    $sudo_cmd tar -C /usr/local -xzf "$tmpdir/$tarball"
    rm -rf "$tmpdir"

    # Create symlinks
    $sudo_cmd ln -sf /usr/local/go/bin/go /usr/local/bin/go
    $sudo_cmd ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

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
    local target_home="${TARGET_HOME:-/home/$target_user}"
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
    local target_home="${TARGET_HOME:-/home/$target_user}"

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

    # Configure uv (sets environment variables)
    configure_uv

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
