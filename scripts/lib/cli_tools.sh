#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Installer - CLI Tools Library
# Installs modern CLI replacements that acfs.zshrc depends on
# ============================================================

CLI_TOOLS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure we have logging functions available
if [[ -z "${ACFS_BLUE:-}" ]]; then
    # shellcheck source=logging.sh
    source "$CLI_TOOLS_SCRIPT_DIR/logging.sh"
fi

# ============================================================
# Configuration
# ============================================================

# APT packages (available in Ubuntu 24.04+)
APT_CLI_TOOLS=(
    ripgrep         # rg - fast grep
    fd-find         # fd - fast find
    fzf             # fuzzy finder
    tmux            # terminal multiplexer
    neovim          # better vim
    direnv          # directory-specific env vars
    jq              # JSON processor
    gh              # GitHub CLI (auth, issues, PRs)
    git-lfs         # Git LFS (large files)
    rsync           # fast file sync/copy
    lsof            # open files / ports debugging
    dnsutils        # dig/nslookup for DNS debugging
    netcat-openbsd  # nc for network debugging
    strace          # syscall tracing
    htop            # process viewer (fallback for btop)
    tree            # directory tree viewer
    ncdu            # interactive disk usage
    httpie          # better curl for APIs
    entr            # run commands when files change
    mtr             # better traceroute
    pv              # pipe viewer (progress bars)
)

# APT packages that may not be available on all Ubuntu versions
APT_CLI_TOOLS_OPTIONAL=(
    bat             # better cat (may be 'batcat' on older Ubuntu)
    lsd             # modern ls with icons
    eza             # modern ls alternative
    btop            # better top
    dust            # better du
    git-delta       # beautiful git diffs (provides 'delta' command)
)

# Cargo packages (for latest versions or missing apt packages)
# shellcheck disable=SC2034  # Used for documentation/reference
CARGO_CLI_TOOLS=(
    zoxide          # better cd (z command)
    ast-grep        # structural grep (sg command)
    tealdeer        # tldr - simplified man pages
)

# ============================================================
# Helper Functions
# ============================================================

# Check if a command exists
_cli_command_exists() {
    command -v "$1" &>/dev/null
}

# Get the sudo command if needed
_cli_get_sudo() {
    if [[ $EUID -eq 0 ]]; then
        echo ""
    else
        echo "sudo"
    fi
}

# Fetch latest version tag from GitHub
# Usage: _fetch_github_version "owner/repo" [strip_v]
_fetch_github_version() {
    local repo="$1"
    local strip_v="${2:-false}"
    local tag=""

    # Strategy 1: Try HTTP HEAD request to /releases/latest (redirects to /releases/tag/vX.Y.Z)
    # This avoids GitHub API rate limits (60 requests/hr for unauthenticated IP)
    local location_header
    if location_header=$(curl -sI --max-time 10 "https://github.com/$repo/releases/latest" | grep -i "^location:"); then
        # Extract tag from URL: https://github.com/owner/repo/releases/tag/v1.2.3
        # Remove trailing CR if present
        location_header="${location_header%$'\r'}"
        tag="${location_header##*/}"
    fi

    # Strategy 2: Fallback to GitHub API if HEAD failed or returned no tag
    if [[ -z "$tag" ]]; then
        local json
        if json=$(curl -s --max-time 10 "https://api.github.com/repos/$repo/releases/latest"); then
            if command -v jq &>/dev/null; then
                tag=$(echo "$json" | jq -r '.tag_name // empty')
            elif command -v python3 &>/dev/null; then
                tag=$(echo "$json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('tag_name', ''))" 2>/dev/null)
            else
                tag=$(echo "$json" | grep -o '"tag_name": *"[^"]*"' | head -n1 | cut -d'"' -f4)
            fi
        fi
    fi

    [[ -z "$tag" || "$tag" == "null" ]] && return 1

    if [[ "$strip_v" == "true" ]]; then
        echo "${tag#v}"
    else
        echo "$tag"
    fi
}

# Run a command as target user
_cli_run_as_user() {
    local target_user="${TARGET_USER:-ubuntu}"
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
CLI_SECURITY_READY=false
_cli_require_security() {
    if [[ "${CLI_SECURITY_READY}" == "true" ]]; then
        return 0
    fi

    if [[ ! -f "$CLI_TOOLS_SCRIPT_DIR/security.sh" ]]; then
        log_warn "Security library not found ($CLI_TOOLS_SCRIPT_DIR/security.sh); refusing to run upstream installer scripts"
        return 1
    fi

    # shellcheck source=security.sh
    source "$CLI_TOOLS_SCRIPT_DIR/security.sh"
    if ! load_checksums; then
        log_warn "checksums.yaml not available; refusing to run upstream installer scripts"
        return 1
    fi

    CLI_SECURITY_READY=true
    return 0
}

# ============================================================
# APT-based CLI Tools
# ============================================================

# Install CLI tools available via apt
install_apt_cli_tools() {
    local sudo_cmd
    sudo_cmd=$(_cli_get_sudo)

    log_detail "Installing apt-based CLI tools..."

    # Update package list
    $sudo_cmd apt-get update -y >/dev/null 2>&1 || true

    # Install core packages (these should always be available)
    for pkg in "${APT_CLI_TOOLS[@]}"; do
        if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            log_detail "Installing $pkg..."
            $sudo_cmd apt-get install -y "$pkg" >/dev/null 2>&1 || log_warn "Could not install $pkg via apt"
        fi
    done

    # Install optional packages (may not be available on all versions)
    for pkg in "${APT_CLI_TOOLS_OPTIONAL[@]}"; do
        if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            log_detail "Installing $pkg (optional)..."
            $sudo_cmd apt-get install -y "$pkg" >/dev/null 2>&1 || true
        fi
    done

    # Handle bat/batcat naming issue (Ubuntu calls it batcat)
    if ! _cli_command_exists bat && _cli_command_exists batcat; then
        log_detail "Creating bat symlink for batcat..."
        $sudo_cmd ln -sf "$(which batcat)" /usr/local/bin/bat 2>/dev/null || true
    fi

    # Handle fd-find naming issue (Ubuntu calls it fdfind)
    if ! _cli_command_exists fd && _cli_command_exists fdfind; then
        log_detail "Creating fd symlink for fdfind..."
        $sudo_cmd ln -sf "$(which fdfind)" /usr/local/bin/fd 2>/dev/null || true
    fi

    log_success "APT CLI tools installed"
}

# ============================================================
# Cargo-based CLI Tools
# ============================================================

# Install CLI tools via cargo (for latest versions)
install_cargo_cli_tools() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local cargo_bin="$target_home/.cargo/bin/cargo"

    log_detail "Installing cargo-based CLI tools..."

    # Check if cargo is available
    if [[ ! -x "$cargo_bin" ]]; then
        log_warn "Cargo not found at $cargo_bin, skipping cargo CLI tools"
        return 0
    fi

    # Install zoxide if not already installed
    if ! _cli_command_exists zoxide; then
        log_detail "Installing zoxide via cargo..."
        _cli_run_as_user "$cargo_bin install zoxide --locked 2>/dev/null" || {
            # Fallback: try the official installer
            log_detail "Trying zoxide official installer..."
            if _cli_require_security; then
                local url="${KNOWN_INSTALLERS[zoxide]}"
                local expected_sha256
                expected_sha256="$(get_checksum zoxide)"
                if [[ -n "$expected_sha256" ]]; then
                    _cli_run_as_user "source '$CLI_TOOLS_SCRIPT_DIR/security.sh'; verify_checksum '$url' '$expected_sha256' 'zoxide' | sh" || true
                else
                    log_warn "No checksum recorded for zoxide; skipping unverified installer fallback"
                fi
            fi
        }
    fi

    # Install ast-grep (sg command)
    if ! _cli_command_exists sg; then
        log_detail "Installing ast-grep via cargo..."
        _cli_run_as_user "$cargo_bin install ast-grep --locked 2>/dev/null" || log_warn "Could not install ast-grep"
    fi

    # Install lsd via cargo if apt version not available
    if ! _cli_command_exists lsd && ! _cli_command_exists eza; then
        log_detail "Installing lsd via cargo..."
        _cli_run_as_user "$cargo_bin install lsd --locked 2>/dev/null" || log_warn "Could not install lsd"
    fi

    # Install dust via cargo if apt version not available
    if ! _cli_command_exists dust; then
        log_detail "Installing dust via cargo..."
        _cli_run_as_user "$cargo_bin install du-dust --locked 2>/dev/null" || log_warn "Could not install dust"
    fi

    # Install tealdeer (tldr - simplified man pages)
    if ! _cli_command_exists tldr; then
        log_detail "Installing tealdeer (tldr) via cargo..."
        _cli_run_as_user "$cargo_bin install tealdeer --locked 2>/dev/null" || log_warn "Could not install tealdeer"
        # Fetch tldr pages cache (use full path since ~/.cargo/bin may not be in PATH yet)
        local tldr_bin="$target_home/.cargo/bin/tldr"
        if [[ -x "$tldr_bin" ]]; then
            _cli_run_as_user "$tldr_bin --update 2>/dev/null" || true
        fi
    fi

    log_success "Cargo CLI tools installed"
}

# ============================================================
# Other CLI Tools (via curl/installer scripts)
# ============================================================

# Install gum (Charmbracelet's glamorous shell tool)
install_gum_cli_tool() {
    local sudo_cmd
    sudo_cmd=$(_cli_get_sudo)

    if _cli_command_exists gum; then
        log_detail "gum already installed"
        return 0
    fi

    log_detail "Installing gum..."

    # Add Charm repository (DEB822 format for Ubuntu 24.04+)
    $sudo_cmd mkdir -p /etc/apt/keyrings
    curl --proto '=https' --proto-redir '=https' -fsSL https://repo.charm.sh/apt/gpg.key | $sudo_cmd gpg --batch --yes --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null || true
    printf 'Types: deb\nURIs: https://repo.charm.sh/apt/\nSuites: *\nComponents: *\nSigned-By: /etc/apt/keyrings/charm.gpg\n' | $sudo_cmd tee /etc/apt/sources.list.d/charm.sources > /dev/null
    $sudo_cmd apt-get update -y >/dev/null 2>&1 || true
    $sudo_cmd apt-get install -y gum >/dev/null 2>&1 || log_warn "Could not install gum"

    if _cli_command_exists gum; then
        log_success "gum installed"
    fi
}

# Install lazygit (Git TUI)
install_lazygit() {
    local sudo_cmd
    sudo_cmd=$(_cli_get_sudo)

    if _cli_command_exists lazygit; then
        log_detail "lazygit already installed"
        return 0
    fi

    log_detail "Installing lazygit..."

    # Try apt first (available in newer Ubuntu)
    if $sudo_cmd apt-get install -y lazygit >/dev/null 2>&1; then
        log_success "lazygit installed via apt"
        return 0
    fi

    # Fallback: install from GitHub releases
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch="x86_64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_warn "Unsupported architecture for lazygit: $arch"; return 1 ;;
    esac

    local version
    # Use helper for robust version fetching (strips 'v' prefix)
    version=$(_fetch_github_version "jesseduffield/lazygit" true) || version="0.44.1"

    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/acfs_lazygit.XXXXXX" 2>/dev/null)" || tmpdir=""
    if [[ -z "$tmpdir" ]] || [[ ! -d "$tmpdir" ]]; then
        log_warn "mktemp failed; cannot install lazygit"
        return 1
    fi
    curl --proto '=https' --proto-redir '=https' -fsSL -o "$tmpdir/lazygit.tar.gz" \
        "https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_Linux_${arch}.tar.gz" || {
        log_warn "Could not download lazygit"
        rm -rf -- "$tmpdir"
        return 1
    }

    tar -xzf "$tmpdir/lazygit.tar.gz" -C "$tmpdir"
    $sudo_cmd install "$tmpdir/lazygit" /usr/local/bin/lazygit
    rm -rf -- "$tmpdir"

    log_success "lazygit installed from GitHub"
}

# Install lazydocker (Docker TUI)
install_lazydocker() {
    local sudo_cmd
    sudo_cmd=$(_cli_get_sudo)

    if _cli_command_exists lazydocker; then
        log_detail "lazydocker already installed"
        return 0
    fi

    log_detail "Installing lazydocker..."

    # Install from GitHub releases
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch="x86_64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_warn "Unsupported architecture for lazydocker: $arch"; return 1 ;;
    esac

    local version
    # Use helper for robust version fetching (strips 'v' prefix)
    version=$(_fetch_github_version "jesseduffield/lazydocker" true) || version="0.23.3"

    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/acfs_lazydocker.XXXXXX" 2>/dev/null)" || tmpdir=""
    if [[ -z "$tmpdir" ]] || [[ ! -d "$tmpdir" ]]; then
        log_warn "mktemp failed; cannot install lazydocker"
        return 1
    fi
    curl --proto '=https' --proto-redir '=https' -fsSL -o "$tmpdir/lazydocker.tar.gz" \
        "https://github.com/jesseduffield/lazydocker/releases/download/v${version}/lazydocker_${version}_Linux_${arch}.tar.gz" || {
        log_warn "Could not download lazydocker"
        rm -rf -- "$tmpdir"
        return 1
    }

    tar -xzf "$tmpdir/lazydocker.tar.gz" -C "$tmpdir"
    $sudo_cmd install "$tmpdir/lazydocker" /usr/local/bin/lazydocker
    rm -rf -- "$tmpdir"

    log_success "lazydocker installed from GitHub"
}

# Install yq (YAML processor, like jq for YAML)
install_yq() {
    local sudo_cmd
    sudo_cmd=$(_cli_get_sudo)

    if _cli_command_exists yq; then
        log_detail "yq already installed"
        return 0
    fi

    log_detail "Installing yq..."

    # Install from GitHub releases (Mike Farah's yq)
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_warn "Unsupported architecture for yq: $arch"; return 1 ;;
    esac

    local version
    # Use helper for robust version fetching (keeps 'v' prefix)
    version=$(_fetch_github_version "mikefarah/yq" false) || version="v4.44.1"

    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/acfs_yq.XXXXXX" 2>/dev/null)" || tmpdir=""
    if [[ -z "$tmpdir" ]] || [[ ! -d "$tmpdir" ]]; then
        log_warn "mktemp failed; cannot install yq"
        return 1
    fi
    curl --proto '=https' --proto-redir '=https' -fsSL -o "$tmpdir/yq" \
        "https://github.com/mikefarah/yq/releases/download/${version}/yq_linux_${arch}" || {
        log_warn "Could not download yq"
        rm -rf -- "$tmpdir"
        return 1
    }

    chmod +x "$tmpdir/yq"
    $sudo_cmd install "$tmpdir/yq" /usr/local/bin/yq
    rm -rf -- "$tmpdir"

    log_success "yq installed from GitHub"
}

# Install atuin (shell history)
install_atuin() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"

    if [[ -d "$target_home/.atuin" ]] || _cli_command_exists atuin; then
        log_detail "atuin already installed"
        return 0
    fi

    log_detail "Installing atuin..."
    if ! _cli_require_security; then
        return 1
    fi

    local url="${KNOWN_INSTALLERS[atuin]}"
    local expected_sha256
    expected_sha256="$(get_checksum atuin)"
    if [[ -z "$expected_sha256" ]]; then
        log_warn "No checksum recorded for atuin; refusing to run unverified installer"
        return 1
    fi

    if ! _cli_run_as_user "source '$CLI_TOOLS_SCRIPT_DIR/security.sh'; verify_checksum '$url' '$expected_sha256' 'atuin' | sh"; then
        log_warn "Could not install atuin"
    fi

    if [[ -d "$target_home/.atuin" ]] || _cli_command_exists atuin; then
        log_success "atuin installed"
        return 0
    fi

    log_warn "atuin not installed"
    return 1
}

# ============================================================
# Docker Setup
# ============================================================

# Install and configure Docker
install_docker() {
    local sudo_cmd
    sudo_cmd=$(_cli_get_sudo)
    local target_user="${TARGET_USER:-ubuntu}"

    if _cli_command_exists docker; then
        log_detail "Docker already installed"
    else
        log_detail "Installing Docker..."
        $sudo_cmd apt-get install -y docker.io docker-compose-plugin >/dev/null 2>&1 || log_warn "Could not install Docker"
    fi

    # Add target user to docker group
    if getent group docker &>/dev/null; then
        log_detail "Adding $target_user to docker group..."
        $sudo_cmd usermod -aG docker "$target_user" 2>/dev/null || true
    fi

    log_success "Docker configured"
}

# ============================================================
# Verification Functions
# ============================================================

# Verify all CLI tools are installed
verify_cli_tools() {
    local all_pass=true

    log_detail "Verifying CLI tools..."

    # Core tools (must have)
    local core_tools=("rg" "fzf" "tmux" "jq")
    for tool in "${core_tools[@]}"; do
        if _cli_command_exists "$tool"; then
            log_detail "  $tool"
        else
            log_warn "  Missing: $tool"
            all_pass=false
        fi
    done

    # Preferred tools (one of alternatives)
    if _cli_command_exists lsd || _cli_command_exists eza; then
        log_detail "  ls replacement: $(command -v lsd || command -v eza)"
    else
        log_warn "  Missing: lsd or eza"
    fi

    if _cli_command_exists bat || _cli_command_exists batcat; then
        log_detail "  cat replacement: $(command -v bat || command -v batcat)"
    else
        log_warn "  Missing: bat"
    fi

    if _cli_command_exists fd || _cli_command_exists fdfind; then
        log_detail "  find replacement: $(command -v fd || command -v fdfind)"
    else
        log_warn "  Missing: fd"
    fi

    # Optional tools (nice to have)
    local optional_tools=("zoxide" "direnv" "nvim" "lazygit" "gum" "atuin" "yq" "tldr" "delta" "tree" "ncdu" "http")
    for tool in "${optional_tools[@]}"; do
        if _cli_command_exists "$tool"; then
            log_detail "  $tool"
        fi
    done

    if [[ "$all_pass" == "true" ]]; then
        log_success "All core CLI tools verified"
        return 0
    else
        log_warn "Some CLI tools are missing"
        return 1
    fi
}

# Get versions of installed tools (for doctor output)
get_cli_tool_versions() {
    echo "CLI Tool Versions:"

    _cli_command_exists rg && echo "  ripgrep: $(rg --version | head -1)"
    _cli_command_exists fzf && echo "  fzf: $(fzf --version)"
    _cli_command_exists tmux && echo "  tmux: $(tmux -V)"
    _cli_command_exists nvim && echo "  neovim: $(nvim --version | head -1)"
    _cli_command_exists lsd && echo "  lsd: $(lsd --version)"
    _cli_command_exists eza && echo "  eza: $(eza --version | head -1)"
    _cli_command_exists bat && echo "  bat: $(bat --version)"
    _cli_command_exists fd && echo "  fd: $(fd --version)"
    _cli_command_exists zoxide && echo "  zoxide: $(zoxide --version)"
    _cli_command_exists lazygit && echo "  lazygit: $(lazygit --version | head -1)"
    _cli_command_exists gum && echo "  gum: $(gum --version)"
    _cli_command_exists atuin && echo "  atuin: $(atuin --version)"
    _cli_command_exists docker && echo "  docker: $(docker --version)"
    _cli_command_exists yq && echo "  yq: $(yq --version)"
    _cli_command_exists tldr && echo "  tldr: $(tldr --version 2>/dev/null || echo 'installed')"
    _cli_command_exists delta && echo "  delta: $(delta --version)"
    _cli_command_exists tree && echo "  tree: $(tree --version | head -1)"
    _cli_command_exists ncdu && echo "  ncdu: $(ncdu --version 2>/dev/null | head -1 || echo 'installed')"
    _cli_command_exists http && echo "  httpie: $(http --version)"
}

# ============================================================
# Main Installation Function
# ============================================================

# Install all CLI tools (called by install.sh)
install_all_cli_tools() {
    log_step "4/8" "Installing CLI tools..."

    # Install gum first for enhanced UI
    install_gum_cli_tool

    # APT-based tools
    install_apt_cli_tools

    # Cargo-based tools (requires rust to be installed first)
    install_cargo_cli_tools

    # Other installers
    install_lazygit
    install_lazydocker
    install_yq
    install_atuin

    # Docker
    install_docker

    # Verify installation
    verify_cli_tools

    log_success "CLI tools installation complete"
}

# ============================================================
# Module can be sourced or run directly
# ============================================================

# If run directly (not sourced), execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_all_cli_tools "$@"
fi
