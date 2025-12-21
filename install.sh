#!/usr/bin/env bash
# ============================================================
# ACFS - Agentic Coding Flywheel Setup
# Main installer script
#
# Usage:
#   curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh?$(date +%s)" | bash -s -- --yes --mode vibe
#
# Options:
#   --yes         Skip all prompts, use defaults
#   --mode vibe   Enable passwordless sudo, full agent permissions
#   --dry-run     Print what would be done without changing system
#   --print       Print upstream scripts/versions that will be run
#   --skip-postgres   Skip PostgreSQL 18 installation
#   --skip-vault      Skip HashiCorp Vault installation
#   --skip-cloud      Skip cloud CLIs (wrangler, supabase, vercel)
# ============================================================

set -euo pipefail

# ============================================================
# Configuration
# ============================================================
ACFS_VERSION="0.1.0"
ACFS_RAW="https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main"
# Note: ACFS_HOME is set after TARGET_HOME is determined
ACFS_LOG_DIR="/var/log/acfs"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default options
YES_MODE=false
DRY_RUN=false
PRINT_MODE=false
MODE="vibe"
SKIP_POSTGRES=false
SKIP_VAULT=false
SKIP_CLOUD=false

# Target user configuration
# When running as root, we install for ubuntu user, not root
TARGET_USER="ubuntu"
TARGET_HOME="/home/$TARGET_USER"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Check if gum is available for enhanced UI
HAS_GUM=false
if command -v gum &>/dev/null; then
    HAS_GUM=true
fi

# ACFS Color scheme (Catppuccin Mocha inspired)
ACFS_PRIMARY="#89b4fa"
ACFS_SUCCESS="#a6e3a1"
ACFS_WARNING="#f9e2af"
ACFS_ERROR="#f38ba8"
ACFS_MUTED="#6c7086"

# ============================================================
# Install gum FIRST for beautiful UI from the start
# ============================================================
install_gum_early() {
    # Already have gum? Great!
    if command -v gum &>/dev/null; then
        HAS_GUM=true
        return 0
    fi

    # Need curl to fetch gum - if curl isn't installed yet, skip early install
    # (gum will be installed later in install_cli_tools after ensure_base_deps)
    if ! command -v curl &>/dev/null; then
        return 0
    fi

    # Need gpg for apt key handling
    if ! command -v gpg &>/dev/null; then
        return 0
    fi

    # Need apt-get for installation
    if ! command -v apt-get &>/dev/null; then
        return 0
    fi

    # Need root/sudo for apt operations
    local sudo_cmd=""
    if [[ $EUID -ne 0 ]]; then
        if command -v sudo &>/dev/null; then
            sudo_cmd="sudo"
        else
            # Can't install gum without sudo, fall back to plain output
            return 0
        fi
    fi

    # Quick apt update and gum install (silent unless it fails)
    echo -e "\033[0;90m    → Installing gum for enhanced UI...\033[0m" >&2

    # Add Charm apt repo
    $sudo_cmd mkdir -p /etc/apt/keyrings 2>/dev/null || true
    if curl "${ACFS_CURL_BASE_ARGS[@]}" https://repo.charm.sh/apt/gpg.key 2>/dev/null | \
        $sudo_cmd gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null; then
        echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | \
            $sudo_cmd tee /etc/apt/sources.list.d/charm.list > /dev/null 2>&1
        $sudo_cmd apt-get update -y >/dev/null 2>&1 || true
        if $sudo_cmd apt-get install -y gum >/dev/null 2>&1; then
            HAS_GUM=true
            echo -e "\033[0;32m    ✓ gum installed - enhanced UI enabled!\033[0m" >&2
        fi
    fi
}

# ============================================================
# ASCII Art Banner
# ============================================================
print_banner() {
    local banner='
    ╔═══════════════════════════════════════════════════════════════╗
    ║                                                               ║
    ║     █████╗  ██████╗███████╗███████╗                          ║
    ║    ██╔══██╗██╔════╝██╔════╝██╔════╝                          ║
    ║    ███████║██║     █████╗  ███████╗                          ║
    ║    ██╔══██║██║     ██╔══╝  ╚════██║                          ║
    ║    ██║  ██║╚██████╗██║     ███████║                          ║
    ║    ╚═╝  ╚═╝ ╚═════╝╚═╝     ╚══════╝                          ║
    ║                                                               ║
    ║         Agentic Coding Flywheel Setup v'"$ACFS_VERSION"'              ║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝
'

    if [[ "$HAS_GUM" == "true" ]]; then
        echo "$banner" | gum style --foreground "$ACFS_PRIMARY" --bold >&2
    else
        echo -e "${BLUE}$banner${NC}" >&2
    fi
}

# ============================================================
# Logging functions (with gum enhancement)
# ============================================================
log_step() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_PRIMARY" --bold "[$1]" | tr -d '\n' >&2
        echo -n " " >&2
        gum style "$2" >&2
    else
        echo -e "${BLUE}[$1]${NC} $2" >&2
    fi
}

log_detail() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_MUTED" --margin "0 0 0 4" "→ $1" >&2
    else
        echo -e "${GRAY}    → $1${NC}" >&2
    fi
}

log_success() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_SUCCESS" --bold "✓ $1" >&2
    else
        echo -e "${GREEN}✓ $1${NC}" >&2
    fi
}

log_warn() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_WARNING" "⚠ $1" >&2
    else
        echo -e "${YELLOW}⚠ $1${NC}" >&2
    fi
}

log_error() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_ERROR" --bold "✖ $1" >&2
    else
        echo -e "${RED}✖ $1${NC}" >&2
    fi
}

log_fatal() {
    log_error "$1"
    exit 1
}

# ============================================================
# Error handling
# ============================================================
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error ""
        if [[ "${SMOKE_TEST_FAILED:-false}" == "true" ]]; then
            log_error "ACFS installation completed, but the post-install smoke test failed."
        else
            log_error "ACFS installation failed!"
        fi
        log_error ""
        log_error "To debug:"
        log_error "  1. Check the log: cat $ACFS_LOG_DIR/install.log"
        log_error "  2. Run: acfs doctor"
        log_error "  3. Re-run this installer (it's safe to run multiple times)"
        log_error ""
    fi
}
trap cleanup EXIT

# ============================================================
# Parse arguments
# ============================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --yes|-y)
                YES_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --print)
                PRINT_MODE=true
                shift
                ;;
            --mode)
                if [[ -z "${2:-}" ]]; then
                    log_fatal "--mode requires a value (e.g., --mode vibe)"
                fi
                MODE="$2"
                shift 2
                ;;
            --skip-postgres)
                SKIP_POSTGRES=true
                shift
                ;;
            --skip-vault)
                SKIP_VAULT=true
                shift
                ;;
            --skip-cloud)
                SKIP_CLOUD=true
                shift
                ;;
            *)
                log_warn "Unknown option: $1"
                shift
                ;;
        esac
    done
}

# ============================================================
# Utility functions
# ============================================================
command_exists() {
    command -v "$1" &>/dev/null
}

ACFS_CURL_BASE_ARGS=(-fsSL)
if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    ACFS_CURL_BASE_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
fi

acfs_curl() {
    curl "${ACFS_CURL_BASE_ARGS[@]}" "$@"
}

install_asset() {
    local rel_path="$1"
    local dest_path="$2"

    # Security: Validate rel_path doesn't contain path traversal
    if [[ "$rel_path" == *".."* ]]; then
        log_error "install_asset: Invalid path (contains '..'): $rel_path"
        return 1
    fi

    # Security: Validate dest_path is under expected directories
    local allowed_prefixes=("$ACFS_HOME" "$TARGET_HOME" "/data")
    local valid_dest=false
    for prefix in "${allowed_prefixes[@]}"; do
        if [[ "$dest_path" == "$prefix"* ]]; then
            valid_dest=true
            break
        fi
    done
    if [[ "$valid_dest" != "true" ]]; then
        log_error "install_asset: Destination outside allowed paths: $dest_path"
        return 1
    fi

    if [[ -f "$SCRIPT_DIR/$rel_path" ]]; then
        cp "$SCRIPT_DIR/$rel_path" "$dest_path"
    else
        acfs_curl -o "$dest_path" "$ACFS_RAW/$rel_path"
    fi
}

run_as_target() {
    local user="$TARGET_USER"

    # Already the target user
    if [[ "$(whoami)" == "$user" ]]; then
        "$@"
        return $?
    fi

    # Preferred: sudo
    if command_exists sudo; then
        sudo -u "$user" -H "$@"
        return $?
    fi

    # Fallbacks (root-only typically)
    if command_exists runuser; then
        runuser -u "$user" -- "$@"
        return $?
    fi

    su - "$user" -c "$(printf '%q ' "$@")"
}

# ============================================================
# Upstream installer verification (checksums.yaml)
# ============================================================

declare -A ACFS_UPSTREAM_URLS=()
declare -A ACFS_UPSTREAM_SHA256=()
ACFS_UPSTREAM_LOADED=false

acfs_calculate_sha256() {
    if command_exists sha256sum; then
        sha256sum | cut -d' ' -f1
        return 0
    fi

    if command_exists shasum; then
        shasum -a 256 | cut -d' ' -f1
        return 0
    fi

    log_error "No SHA256 tool available (need sha256sum or shasum)"
    return 1
}

acfs_fetch_url_content() {
    local url="$1"

    if [[ "$url" != https://* ]]; then
        log_error "Security error: upstream URL is not HTTPS: $url"
        return 1
    fi

    local sentinel="__ACFS_EOF_SENTINEL__"
    local content
    content="$(
        acfs_curl "$url" 2>/dev/null || exit 1
        printf '%s' "$sentinel"
    )" || {
        log_error "Failed to fetch upstream URL: $url"
        return 1
    }

    if [[ "$content" != *"$sentinel" ]]; then
        log_error "Failed to fetch upstream URL: $url"
        return 1
    fi
    printf '%s' "${content%"$sentinel"}"
}

acfs_load_upstream_checksums() {
    if [[ "$ACFS_UPSTREAM_LOADED" == "true" ]]; then
        return 0
    fi

    local content=""
    if [[ -r "$SCRIPT_DIR/checksums.yaml" ]]; then
        content="$(cat "$SCRIPT_DIR/checksums.yaml")"
    else
        content="$(acfs_curl "$ACFS_RAW/checksums.yaml" 2>/dev/null)" || {
            log_error "Failed to fetch checksums.yaml from $ACFS_RAW"
            return 1
        }
    fi

    local in_installers=false
    local current_tool=""

    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        if [[ "$line" =~ ^installers: ]]; then
            in_installers=true
            continue
        fi
        if [[ "$in_installers" != "true" ]]; then
            continue
        fi

        if [[ "$line" =~ ^[[:space:]]{2}([a-z_]+):[[:space:]]*$ ]]; then
            current_tool="${BASH_REMATCH[1]}"
            continue
        fi

        [[ -n "$current_tool" ]] || continue

        if [[ "$line" =~ url:[[:space:]]*\"([^\"]+)\" ]]; then
            ACFS_UPSTREAM_URLS["$current_tool"]="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$line" =~ sha256:[[:space:]]*\"([a-f0-9]{64})\" ]]; then
            ACFS_UPSTREAM_SHA256["$current_tool"]="${BASH_REMATCH[1]}"
            continue
        fi
    done <<< "$content"

    local required_tools=(
        atuin bun bv caam cass cm mcp_agent_mail ntm ohmyzsh rust slb ubs uv zoxide
    )
    local missing=false
    local tool
    for tool in "${required_tools[@]}"; do
        if [[ -z "${ACFS_UPSTREAM_URLS[$tool]:-}" ]] || [[ -z "${ACFS_UPSTREAM_SHA256[$tool]:-}" ]]; then
            log_error "checksums.yaml missing entry for '$tool'"
            missing=true
        fi
    done
    if [[ "$missing" == "true" ]]; then
        return 1
    fi

    ACFS_UPSTREAM_LOADED=true
    return 0
}

acfs_run_verified_upstream_script_as_target() {
    local tool="$1"
    local runner="$2"
    shift 2 || true

    acfs_load_upstream_checksums

    local url="${ACFS_UPSTREAM_URLS[$tool]:-}"
    local expected_sha256="${ACFS_UPSTREAM_SHA256[$tool]:-}"
    if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then
        log_error "No checksum recorded for upstream installer: $tool"
        return 1
    fi

    local content
    content="$(acfs_fetch_url_content "$url")" || return 1

    local actual_sha256
    actual_sha256="$(printf '%s' "$content" | acfs_calculate_sha256)" || return 1

    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        log_error "Security error: checksum mismatch for '$tool'"
        log_detail "URL: $url"
        log_detail "Expected: $expected_sha256"
        log_detail "Actual:   $actual_sha256"
        return 1
    fi

    printf '%s' "$content" | run_as_target "$runner" -s -- "$@"
}

ensure_root() {
    if [[ $EUID -ne 0 ]]; then
        if command_exists sudo; then
            SUDO="sudo"
        elif [[ "$DRY_RUN" == "true" ]]; then
            # Dry-run should be able to print actions even on systems without sudo.
            SUDO="sudo"
            log_warn "sudo not found (dry-run mode). No commands will be executed."
        else
            log_fatal "This script requires root privileges. Please run as root or install sudo."
        fi
    else
        SUDO=""
    fi
}

confirm_or_exit() {
    if [[ "$DRY_RUN" == "true" ]] || [[ "$YES_MODE" == "true" ]]; then
        return 0
    fi

    if [[ "$HAS_GUM" == "true" ]] && [[ -r /dev/tty ]]; then
        gum confirm "Proceed with ACFS install? (mode=$MODE)" < /dev/tty > /dev/tty || exit 1
        return 0
    fi

    local reply=""
    if [[ -t 0 ]]; then
        read -r -p "Proceed with ACFS install? (mode=$MODE) [y/N] " reply
    elif [[ -r /dev/tty ]]; then
        read -r -p "Proceed with ACFS install? (mode=$MODE) [y/N] " reply < /dev/tty
    else
        log_fatal "--yes is required when no TTY is available"
    fi
    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *) exit 1 ;;
    esac
}

# Set up target-specific paths
# Must be called after ensure_root
init_target_paths() {
    # If running as ubuntu, use ubuntu's home
    # If running as root, install for ubuntu user
    if [[ "$(whoami)" == "$TARGET_USER" ]]; then
        TARGET_HOME="$HOME"
    else
        TARGET_HOME="/home/$TARGET_USER"
    fi

    # ACFS directories for target user
    ACFS_HOME="$TARGET_HOME/.acfs"
    ACFS_STATE_FILE="$ACFS_HOME/state.json"

    log_detail "Target user: $TARGET_USER"
    log_detail "Target home: $TARGET_HOME"
}

ensure_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        log_fatal "Cannot detect OS. This script requires Ubuntu 24.04+ or 25.x"
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    if [[ "$ID" != "ubuntu" ]]; then
        log_warn "This script is designed for Ubuntu but detected: $ID"
        log_warn "Proceeding anyway, but some things may not work."
    fi

    VERSION_MAJOR="${VERSION_ID%%.*}"
    if [[ "$VERSION_MAJOR" -lt 24 ]]; then
        log_warn "Ubuntu $VERSION_ID detected. Recommended: Ubuntu 24.04+ or 25.x"
    fi

    log_detail "OS: Ubuntu $VERSION_ID"
}

ensure_base_deps() {
    log_step "0/9" "Checking base dependencies..."

    if [[ "$DRY_RUN" == "true" ]]; then
        local sudo_prefix=""
        if [[ -n "${SUDO:-}" ]]; then
            sudo_prefix="$SUDO "
        fi

        log_detail "dry-run: would run: ${sudo_prefix}apt-get update -y"
        log_detail "dry-run: would install: curl git ca-certificates unzip tar xz-utils jq build-essential sudo gnupg"
        return 0
    fi

    log_detail "Updating apt package index"
    $SUDO apt-get update -y

    log_detail "Installing base packages"
    $SUDO apt-get install -y curl git ca-certificates unzip tar xz-utils jq build-essential sudo gnupg
}

# ============================================================
# Phase 1: User normalization
# ============================================================
normalize_user() {
    log_step "1/9" "Normalizing user account..."

    # Create target user if it doesn't exist
    if ! id "$TARGET_USER" &>/dev/null; then
        log_detail "Creating user: $TARGET_USER"
        $SUDO useradd -m -s /bin/bash "$TARGET_USER" || true
        $SUDO usermod -aG sudo "$TARGET_USER"
    fi

    # Set up passwordless sudo in vibe mode
    if [[ "$MODE" == "vibe" ]]; then
        log_detail "Enabling passwordless sudo for $TARGET_USER"
        echo "$TARGET_USER ALL=(ALL) NOPASSWD:ALL" | $SUDO tee /etc/sudoers.d/90-ubuntu-acfs > /dev/null
        $SUDO chmod 440 /etc/sudoers.d/90-ubuntu-acfs
    fi

    # Copy SSH keys from root if running as root
    if [[ $EUID -eq 0 ]] && [[ -f /root/.ssh/authorized_keys ]]; then
        log_detail "Copying SSH keys to $TARGET_USER"
        $SUDO mkdir -p "$TARGET_HOME/.ssh"
        $SUDO cp /root/.ssh/authorized_keys "$TARGET_HOME/.ssh/"
        $SUDO chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.ssh"
        $SUDO chmod 700 "$TARGET_HOME/.ssh"
        $SUDO chmod 600 "$TARGET_HOME/.ssh/authorized_keys"
    fi

    # Add target user to docker group if docker is installed
    if getent group docker &>/dev/null; then
        $SUDO usermod -aG docker "$TARGET_USER" 2>/dev/null || true
    fi

    log_success "User normalization complete"
}

# ============================================================
# Phase 2: Filesystem setup
# ============================================================
setup_filesystem() {
    log_step "2/9" "Setting up filesystem..."

    # System directories
    local sys_dirs=("/data/projects" "/data/cache")
    for dir in "${sys_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_detail "Creating: $dir"
            $SUDO mkdir -p "$dir"
        fi
    done

    # Ensure /data is owned by target user
    $SUDO chown -R "$TARGET_USER:$TARGET_USER" /data 2>/dev/null || true

    # User directories (in TARGET_HOME, not $HOME)
    local user_dirs=("$TARGET_HOME/Development" "$TARGET_HOME/Projects" "$TARGET_HOME/dotfiles")
    for dir in "${user_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_detail "Creating: $dir"
            $SUDO mkdir -p "$dir"
        fi
    done

    # Create ACFS directories
    $SUDO mkdir -p "$ACFS_HOME"/{zsh,tmux,bin,docs,logs}
    $SUDO chown -R "$TARGET_USER:$TARGET_USER" "$ACFS_HOME"
    $SUDO mkdir -p "$ACFS_LOG_DIR"

    log_success "Filesystem setup complete"
}

# ============================================================
# Phase 3: Shell setup (zsh + oh-my-zsh + p10k)
# ============================================================
setup_shell() {
    log_step "3/9" "Setting up shell..."

    # Install zsh
    if ! command_exists zsh; then
        log_detail "Installing zsh"
        $SUDO apt-get install -y zsh
    fi

    # Install Oh My Zsh for target user
    local omz_dir="$TARGET_HOME/.oh-my-zsh"
    if [[ ! -d "$omz_dir" ]]; then
        log_detail "Installing Oh My Zsh for $TARGET_USER"
        # Run as target user to install in their home
        acfs_run_verified_upstream_script_as_target "ohmyzsh" "sh" --unattended
    fi

    # Install Powerlevel10k theme
    local p10k_dir="$omz_dir/custom/themes/powerlevel10k"
    if [[ ! -d "$p10k_dir" ]]; then
        log_detail "Installing Powerlevel10k theme"
        run_as_target git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"
    fi

    # Install zsh plugins
    local custom_plugins="$omz_dir/custom/plugins"

    if [[ ! -d "$custom_plugins/zsh-autosuggestions" ]]; then
        log_detail "Installing zsh-autosuggestions"
        run_as_target git clone https://github.com/zsh-users/zsh-autosuggestions "$custom_plugins/zsh-autosuggestions"
    fi

    if [[ ! -d "$custom_plugins/zsh-syntax-highlighting" ]]; then
        log_detail "Installing zsh-syntax-highlighting"
        run_as_target git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$custom_plugins/zsh-syntax-highlighting"
    fi

    # Copy ACFS zshrc
    log_detail "Installing ACFS zshrc"
    install_asset "acfs/zsh/acfs.zshrc" "$ACFS_HOME/zsh/acfs.zshrc"
    $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/zsh/acfs.zshrc"

    # Create minimal .zshrc loader for target user
    cat > "$TARGET_HOME/.zshrc" << 'EOF'
# ACFS loader
source "$HOME/.acfs/zsh/acfs.zshrc"

# User overrides live here forever
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
EOF
    $SUDO chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.zshrc"

    # Set zsh as default shell for target user
    local current_shell
    current_shell=$(getent passwd "$TARGET_USER" | cut -d: -f7)
    if [[ "$current_shell" != *"zsh"* ]]; then
        log_detail "Setting zsh as default shell for $TARGET_USER"
        $SUDO chsh -s "$(which zsh)" "$TARGET_USER" || true
    fi

    log_success "Shell setup complete"
}

# ============================================================
# Phase 4: CLI tools
# ============================================================
install_github_cli() {
    # GitHub CLI (gh) is a core tool for ACFS workflows (PRs, auth, issues).
    # Prefer distro apt; fall back to the official GitHub CLI apt repo if needed.

    if command_exists gh; then
        return 0
    fi

    log_detail "Installing GitHub CLI (gh)"

    # First try default apt repos (often available on Ubuntu 24.04+/25.x).
    if $SUDO apt-get install -y gh >/dev/null 2>&1; then
        return 0
    fi

    # Fallback: add official GitHub CLI apt repo and retry.
    log_detail "gh not available in default apt repos; adding GitHub CLI apt repo"

    if ! $SUDO mkdir -p /etc/apt/keyrings; then
        return 1
    fi
    if ! acfs_curl https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
        $SUDO dd of=/etc/apt/keyrings/githubcli-archive-keyring.gpg status=none 2>/dev/null; then
        return 1
    fi
    $SUDO chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg 2>/dev/null || true

    local arch
    arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
    if ! echo "deb [arch=$arch signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
        $SUDO tee /etc/apt/sources.list.d/github-cli.list > /dev/null; then
        return 1
    fi

    $SUDO apt-get update -y >/dev/null 2>&1 || true
    if ! $SUDO apt-get install -y gh >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

install_cli_tools() {
    log_step "4/9" "Installing CLI tools..."

    # Install gum if not already installed (install_gum_early may have skipped
    # if curl/gpg weren't available at that point)
    if command_exists gum; then
        log_detail "gum already installed"
    else
        log_detail "Installing gum for glamorous shell scripts"
        $SUDO mkdir -p /etc/apt/keyrings
        acfs_curl https://repo.charm.sh/apt/gpg.key | $SUDO gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null || true
        echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | $SUDO tee /etc/apt/sources.list.d/charm.list > /dev/null
        $SUDO apt-get update -y >/dev/null 2>&1 || true
        if $SUDO apt-get install -y gum 2>/dev/null; then
            HAS_GUM=true
            log_success "gum installed - enhanced UI now available"
        else
            log_detail "gum installation failed (optional, continuing)"
        fi
    fi

    log_detail "Installing required apt packages"
    $SUDO apt-get install -y ripgrep tmux fzf direnv jq git-lfs lsof dnsutils netcat-openbsd strace rsync

    # GitHub CLI (gh)
    if command_exists gh; then
        log_detail "gh already installed ($(gh --version 2>/dev/null | head -1 || echo 'gh'))"
    else
        if install_github_cli; then
            log_success "gh installed"
        else
            log_fatal "Failed to install GitHub CLI (gh)"
        fi
    fi

    # Git LFS setup (best-effort: installs hooks config for the target user)
    if command_exists git-lfs; then
        log_detail "Configuring git-lfs for $TARGET_USER"
        run_as_target git lfs install --skip-repo >/dev/null 2>&1 || true
    fi

    log_detail "Installing optional apt packages"
    $SUDO apt-get install -y \
        lsd eza bat fd-find btop dust neovim \
        docker.io docker-compose-plugin \
        lazygit 2>/dev/null || true

    # Add user to docker group
    $SUDO usermod -aG docker "$TARGET_USER" 2>/dev/null || true

    log_success "CLI tools installed"
}

# ============================================================
# Phase 5: Language runtimes
# ============================================================
install_languages() {
    log_step "5/9" "Installing language runtimes..."

    # Bun (install as target user)
    local bun_bin="$TARGET_HOME/.bun/bin/bun"
    if [[ ! -x "$bun_bin" ]]; then
        log_detail "Installing Bun for $TARGET_USER"
        acfs_run_verified_upstream_script_as_target "bun" "bash"
    fi

    # Rust (install as target user)
    local cargo_bin="$TARGET_HOME/.cargo/bin/cargo"
    if [[ ! -x "$cargo_bin" ]]; then
        log_detail "Installing Rust for $TARGET_USER"
        acfs_run_verified_upstream_script_as_target "rust" "sh" -y
    fi

    # ast-grep (sg) - required by UBS for syntax-aware scanning
    if [[ ! -x "$TARGET_HOME/.cargo/bin/sg" ]]; then
        if [[ -x "$cargo_bin" ]]; then
            log_detail "Installing ast-grep (sg) via cargo"
            if run_as_target "$cargo_bin" install ast-grep --locked; then
                log_success "ast-grep installed"
            else
                log_fatal "Failed to install ast-grep (sg)"
            fi
        else
            log_fatal "Cargo not found at $cargo_bin (cannot install ast-grep)"
        fi
    fi

    # Go (system-wide)
    if ! command_exists go; then
        log_detail "Installing Go"
        $SUDO apt-get install -y golang-go
    fi

    # uv (install as target user)
    if [[ ! -f "$TARGET_HOME/.local/bin/uv" ]]; then
        log_detail "Installing uv for $TARGET_USER"
        acfs_run_verified_upstream_script_as_target "uv" "sh"
    fi

    # Atuin (install as target user)
    if [[ ! -d "$TARGET_HOME/.atuin" ]]; then
        log_detail "Installing Atuin for $TARGET_USER"
        acfs_run_verified_upstream_script_as_target "atuin" "sh"
    fi

    # Zoxide (install as target user)
    if [[ ! -f "$TARGET_HOME/.local/bin/zoxide" ]]; then
        log_detail "Installing Zoxide for $TARGET_USER"
        acfs_run_verified_upstream_script_as_target "zoxide" "sh"
    fi

    log_success "Language runtimes installed"
}

# ============================================================
# Phase 6: Coding agents
# ============================================================
install_agents() {
    log_step "6/9" "Installing coding agents..."

    # Use target user's bun
    local bun_bin="$TARGET_HOME/.bun/bin/bun"

    if [[ ! -x "$bun_bin" ]]; then
        log_warn "Bun not found at $bun_bin, skipping agent CLI installation"
        return 0
    fi

    # Claude Code (install as target user)
    log_detail "Installing Claude Code for $TARGET_USER"
    run_as_target "$bun_bin" install -g @anthropic-ai/claude-code@latest 2>/dev/null || true

    # Codex CLI (install as target user)
    log_detail "Installing Codex CLI for $TARGET_USER"
    run_as_target "$bun_bin" install -g @openai/codex@latest 2>/dev/null || true

    # Gemini CLI (install as target user)
    log_detail "Installing Gemini CLI for $TARGET_USER"
    run_as_target "$bun_bin" install -g @google/gemini-cli@latest 2>/dev/null || true

    log_success "Coding agents installed"
}

# ============================================================
# Phase 7: Cloud & database tools
# ============================================================
install_cloud_db() {
    log_step "7/9" "Installing cloud & database tools..."

    local codename="noble"
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        codename="${VERSION_CODENAME:-noble}"
    fi

    # PostgreSQL 18 (via PGDG)
    if [[ "$SKIP_POSTGRES" == "true" ]]; then
        log_detail "Skipping PostgreSQL (--skip-postgres)"
    elif command_exists psql; then
        log_detail "PostgreSQL already installed ($(psql --version 2>/dev/null | head -1 || echo 'psql'))"
    else
        log_detail "Installing PostgreSQL 18 (PGDG repo, codename=$codename)"
        $SUDO mkdir -p /etc/apt/keyrings

        if ! acfs_curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
            $SUDO gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg 2>/dev/null; then
            log_warn "PostgreSQL: failed to install signing key (skipping)"
        else
            echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt ${codename}-pgdg main" | \
                $SUDO tee /etc/apt/sources.list.d/pgdg.list > /dev/null

            $SUDO apt-get update -y >/dev/null 2>&1 || log_warn "PostgreSQL: apt-get update failed (continuing)"

            if $SUDO apt-get install -y postgresql-18 postgresql-client-18 >/dev/null 2>&1; then
                log_success "PostgreSQL 18 installed"

                # Best-effort service start (containers may not have systemd)
                if command_exists systemctl; then
                    $SUDO systemctl enable postgresql >/dev/null 2>&1 || true
                    $SUDO systemctl start postgresql >/dev/null 2>&1 || true
                fi

                # Best-effort role + db for target user
                if command_exists runuser; then
                    $SUDO runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$TARGET_USER'" | grep -q 1 || \
                        $SUDO runuser -u postgres -- createuser -s "$TARGET_USER" 2>/dev/null || true
                    $SUDO runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='$TARGET_USER'" | grep -q 1 || \
                        $SUDO runuser -u postgres -- createdb "$TARGET_USER" 2>/dev/null || true
                elif command_exists sudo; then
                    sudo -u postgres -H psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$TARGET_USER'" | grep -q 1 || \
                        sudo -u postgres -H createuser -s "$TARGET_USER" 2>/dev/null || true
                    sudo -u postgres -H psql -tAc "SELECT 1 FROM pg_database WHERE datname='$TARGET_USER'" | grep -q 1 || \
                        sudo -u postgres -H createdb "$TARGET_USER" 2>/dev/null || true
                fi
            else
                log_warn "PostgreSQL: installation failed (optional)"
            fi
        fi
    fi

    # Vault (HashiCorp apt repo)
    if [[ "$SKIP_VAULT" == "true" ]]; then
        log_detail "Skipping Vault (--skip-vault)"
    elif command_exists vault; then
        log_detail "Vault already installed ($(vault --version 2>/dev/null | head -1 || echo 'vault'))"
    else
        log_detail "Installing Vault (HashiCorp repo, codename=$codename)"
        $SUDO mkdir -p /etc/apt/keyrings

        if ! acfs_curl https://apt.releases.hashicorp.com/gpg | \
            $SUDO gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg 2>/dev/null; then
            log_warn "Vault: failed to install signing key (skipping)"
        else
            echo "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com ${codename} main" | \
                $SUDO tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

            $SUDO apt-get update -y >/dev/null 2>&1 || log_warn "Vault: apt-get update failed (continuing)"
            if $SUDO apt-get install -y vault >/dev/null 2>&1; then
                log_success "Vault installed"
            else
                log_warn "Vault: installation failed (optional)"
            fi
        fi
    fi

    # Cloud CLIs (bun global installs)
    if [[ "$SKIP_CLOUD" == "true" ]]; then
        log_detail "Skipping cloud CLIs (--skip-cloud)"
    else
        local bun_bin="$TARGET_HOME/.bun/bin/bun"
        if [[ ! -x "$bun_bin" ]]; then
            log_warn "Cloud CLIs: bun not found at $bun_bin (skipping)"
        else
            local cli
            for cli in wrangler supabase vercel; do
                if [[ -x "$TARGET_HOME/.bun/bin/$cli" ]]; then
                    log_detail "$cli already installed"
                    continue
                fi

                log_detail "Installing $cli via bun"
                if run_as_target "$bun_bin" install -g "${cli}@latest"; then
                    if [[ -x "$TARGET_HOME/.bun/bin/$cli" ]]; then
                        log_success "$cli installed"
                    else
                        log_warn "$cli: install finished but binary not found"
                    fi
                else
                    log_warn "$cli installation failed (optional)"
                fi
            done
        fi
    fi

    log_success "Cloud & database tools phase complete"
}

# ============================================================
# Phase 8: Dicklesworthstone stack
# ============================================================
install_stack() {
    log_step "8/9" "Installing Dicklesworthstone stack..."

    # NTM (Named Tmux Manager)
    log_detail "Installing NTM"
    acfs_run_verified_upstream_script_as_target "ntm" "bash" || log_warn "NTM installation may have failed"

    # MCP Agent Mail
    log_detail "Installing MCP Agent Mail"
    acfs_run_verified_upstream_script_as_target "mcp_agent_mail" "bash" --yes || log_warn "MCP Agent Mail installation may have failed"

    # Ultimate Bug Scanner
    log_detail "Installing Ultimate Bug Scanner"
    acfs_run_verified_upstream_script_as_target "ubs" "bash" --easy-mode || log_warn "UBS installation may have failed"

    # Beads Viewer
    log_detail "Installing Beads Viewer"
    acfs_run_verified_upstream_script_as_target "bv" "bash" || log_warn "Beads Viewer installation may have failed"

    # CASS (Coding Agent Session Search)
    log_detail "Installing CASS"
    acfs_run_verified_upstream_script_as_target "cass" "bash" --easy-mode --verify || log_warn "CASS installation may have failed"

    # CASS Memory System
    log_detail "Installing CASS Memory System"
    acfs_run_verified_upstream_script_as_target "cm" "bash" --easy-mode --verify || log_warn "CM installation may have failed"

    # CAAM (Coding Agent Account Manager)
    log_detail "Installing CAAM"
    acfs_run_verified_upstream_script_as_target "caam" "bash" || log_warn "CAAM installation may have failed"

    # SLB (Simultaneous Launch Button)
    log_detail "Installing SLB"
    acfs_run_verified_upstream_script_as_target "slb" "bash" || log_warn "SLB installation may have failed"

    log_success "Dicklesworthstone stack installed"
}

# ============================================================
# Phase 9: Final wiring
# ============================================================
finalize() {
    log_step "9/9" "Finalizing installation..."

    # Copy tmux config
    log_detail "Installing tmux config"
    install_asset "acfs/tmux/tmux.conf" "$ACFS_HOME/tmux/tmux.conf"
    $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/tmux/tmux.conf"

    # Link to target user's tmux.conf if it doesn't exist
    if [[ ! -f "$TARGET_HOME/.tmux.conf" ]]; then
        run_as_target ln -sf "$ACFS_HOME/tmux/tmux.conf" "$TARGET_HOME/.tmux.conf"
    fi

    # Install onboard lessons + command
    log_detail "Installing onboard lessons"
    $SUDO mkdir -p "$ACFS_HOME/onboard/lessons"
    local lesson_files=(
        "00_welcome.md"
        "01_linux_basics.md"
        "02_ssh_basics.md"
        "03_tmux_basics.md"
        "04_agents_login.md"
        "05_ntm_core.md"
        "06_ntm_command_palette.md"
        "07_flywheel_loop.md"
    )
    local lesson
    for lesson in "${lesson_files[@]}"; do
        install_asset "acfs/onboard/lessons/$lesson" "$ACFS_HOME/onboard/lessons/$lesson"
    done

    log_detail "Installing onboard command"
    install_asset "packages/onboard/onboard.sh" "$ACFS_HOME/onboard/onboard.sh"
    $SUDO chmod 755 "$ACFS_HOME/onboard/onboard.sh"
    $SUDO chown -R "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/onboard"

    run_as_target mkdir -p "$TARGET_HOME/.local/bin"
    run_as_target ln -sf "$ACFS_HOME/onboard/onboard.sh" "$TARGET_HOME/.local/bin/onboard"

    # Install acfs scripts (for acfs CLI subcommands)
    log_detail "Installing acfs scripts"
    $SUDO mkdir -p "$ACFS_HOME/scripts/lib"

    # Install script libraries
    install_asset "scripts/lib/logging.sh" "$ACFS_HOME/scripts/lib/logging.sh"
    install_asset "scripts/lib/gum_ui.sh" "$ACFS_HOME/scripts/lib/gum_ui.sh"
    install_asset "scripts/lib/doctor.sh" "$ACFS_HOME/scripts/lib/doctor.sh"
    install_asset "scripts/lib/update.sh" "$ACFS_HOME/scripts/lib/update.sh"

    # Install services-setup wizard
    install_asset "scripts/services-setup.sh" "$ACFS_HOME/scripts/services-setup.sh"
    $SUDO chmod 755 "$ACFS_HOME/scripts/services-setup.sh"
    $SUDO chmod 755 "$ACFS_HOME/scripts/lib/"*.sh
    $SUDO chown -R "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/scripts"

    # Legacy: Install doctor as acfs binary (for backwards compat)
    install_asset "scripts/lib/doctor.sh" "$ACFS_HOME/bin/acfs"
    $SUDO chmod 755 "$ACFS_HOME/bin/acfs"
    $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/bin/acfs"
    run_as_target ln -sf "$ACFS_HOME/bin/acfs" "$TARGET_HOME/.local/bin/acfs"

    # Create state file
    cat > "$ACFS_STATE_FILE" << EOF
{
  "version": "$ACFS_VERSION",
  "installed_at": "$(date -Iseconds)",
  "mode": "$MODE",
  "target_user": "$TARGET_USER",
  "yes_mode": $YES_MODE,
  "skip_postgres": $SKIP_POSTGRES,
  "skip_vault": $SKIP_VAULT,
  "skip_cloud": $SKIP_CLOUD,
  "completed_phases": [1, 2, 3, 4, 5, 6, 7, 8, 9]
}
EOF
    $SUDO chown "$TARGET_USER:$TARGET_USER" "$ACFS_STATE_FILE"

    log_success "Installation complete!"
}

# ============================================================
# Post-install smoke test
# Runs quick, automatic verification at the end of install.sh
# ============================================================
_smoke_run_as_target() {
    local cmd="$1"

    if [[ "$(whoami)" == "$TARGET_USER" ]]; then
        bash -lc "$cmd"
        return $?
    fi

    if command_exists sudo; then
        sudo -u "$TARGET_USER" -H bash -lc "$cmd"
        return $?
    fi

    # Fallback: use su if sudo isn't available
    su - "$TARGET_USER" -c "bash -lc $(printf %q "$cmd")"
}

run_smoke_test() {
    local critical_total=8
    local critical_passed=0
    local critical_failed=0
    local warnings=0

    echo "" >&2
    echo "[Smoke Test]" >&2

    # 1) User is ubuntu
    if [[ "$TARGET_USER" == "ubuntu" ]] && id "$TARGET_USER" &>/dev/null; then
        echo "✅ User: ubuntu" >&2
        ((critical_passed += 1))
    else
        echo "✖ User: expected ubuntu (TARGET_USER=$TARGET_USER)" >&2
        echo "    Fix: set TARGET_USER=ubuntu and ensure the user exists" >&2
        ((critical_failed += 1))
    fi

    # 2) Shell is zsh
    local target_shell=""
    target_shell=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f7 || true)
    if [[ "$target_shell" == *"zsh"* ]]; then
        echo "✅ Shell: zsh" >&2
        ((critical_passed += 1))
    else
        echo "✖ Shell: zsh (found: ${target_shell:-unknown})" >&2
        echo "    Fix: sudo chsh -s \"\$(command -v zsh)\" \"$TARGET_USER\"" >&2
        ((critical_failed += 1))
    fi

    # 3) Passwordless sudo works
    if _smoke_run_as_target "sudo -n true" &>/dev/null; then
        echo "✅ Sudo: passwordless" >&2
        ((critical_passed += 1))
    else
        echo "✖ Sudo: passwordless" >&2
        echo "    Fix: re-run installer with --mode vibe (or configure NOPASSWD for $TARGET_USER)" >&2
        ((critical_failed += 1))
    fi

    # 4) /data/projects exists
    if _smoke_run_as_target "[[ -d /data/projects && -w /data/projects ]]" &>/dev/null; then
        echo "✅ Workspace: /data/projects exists" >&2
        ((critical_passed += 1))
    else
        echo "✖ Workspace: /data/projects exists" >&2
        echo "    Fix: sudo mkdir -p /data/projects && sudo chown -R \"$TARGET_USER:$TARGET_USER\" /data/projects" >&2
        ((critical_failed += 1))
    fi

    # 5) bun, uv, cargo, go available
    local missing_lang=()
    [[ -x "$TARGET_HOME/.bun/bin/bun" ]] || missing_lang+=("bun")
    [[ -x "$TARGET_HOME/.local/bin/uv" ]] || missing_lang+=("uv")
    [[ -x "$TARGET_HOME/.cargo/bin/cargo" ]] || missing_lang+=("cargo")
    command_exists go || missing_lang+=("go")
    if [[ ${#missing_lang[@]} -eq 0 ]]; then
        echo "✅ Languages: bun, uv, cargo, go available" >&2
        ((critical_passed += 1))
    else
        echo "✖ Languages: missing ${missing_lang[*]}" >&2
        echo "    Fix: re-run installer (phase 5) and check $ACFS_LOG_DIR/install.log" >&2
        ((critical_failed += 1))
    fi

    # 6) claude, codex, gemini commands exist
    local missing_agents=()
    [[ -x "$TARGET_HOME/.bun/bin/claude" ]] || missing_agents+=("claude")
    [[ -x "$TARGET_HOME/.bun/bin/codex" ]] || missing_agents+=("codex")
    [[ -x "$TARGET_HOME/.bun/bin/gemini" ]] || missing_agents+=("gemini")
    if [[ ${#missing_agents[@]} -eq 0 ]]; then
        echo "✅ Agents: claude, codex, gemini" >&2
        ((critical_passed += 1))
    else
        echo "✖ Agents: missing ${missing_agents[*]}" >&2
        echo "    Fix: re-run installer (phase 6) to install agent CLIs" >&2
        ((critical_failed += 1))
    fi

    # 7) ntm command works
    if _smoke_run_as_target "command -v ntm >/dev/null && ntm --help >/dev/null 2>&1"; then
        echo "✅ NTM: working" >&2
        ((critical_passed += 1))
    else
        echo "✖ NTM: not working" >&2
        echo "    Fix: re-run installer (phase 8) and check $ACFS_LOG_DIR/install.log" >&2
        ((critical_failed += 1))
    fi

    # 8) onboard command exists
    if [[ -x "$TARGET_HOME/.local/bin/onboard" ]]; then
        echo "✅ Onboard: installed" >&2
        ((critical_passed += 1))
    else
        echo "✖ Onboard: missing" >&2
        echo "    Fix: re-run installer (phase 9) or install onboard to $TARGET_HOME/.local/bin/onboard" >&2
        ((critical_failed += 1))
    fi

    # Non-critical: Agent Mail server can start
    if [[ -x "$TARGET_HOME/mcp_agent_mail/scripts/run_server_with_token.sh" ]]; then
        echo "✅ Agent Mail: installed (run 'am' to start)" >&2
    else
        echo "⚠️ Agent Mail: not installed (re-run installer phase 8)" >&2
        ((warnings += 1))
    fi

    # Non-critical: Stack tools respond to --help
    local stack_help_fail=()
    local stack_tools=(ntm ubs bv cass cm caam slb)
    for tool in "${stack_tools[@]}"; do
        if ! _smoke_run_as_target "command -v $tool >/dev/null && $tool --help >/dev/null 2>&1"; then
            stack_help_fail+=("$tool")
        fi
    done
    if [[ ${#stack_help_fail[@]} -gt 0 ]]; then
        echo "⚠️ Stack tools: --help failed for ${stack_help_fail[*]}" >&2
        ((warnings += 1))
    fi

    # Non-critical: PostgreSQL service running
    if [[ "$SKIP_POSTGRES" == "true" ]]; then
        echo "⚠️ PostgreSQL: skipped (optional)" >&2
        ((warnings += 1))
    elif command_exists systemctl && systemctl is-active --quiet postgresql 2>/dev/null; then
        echo "✅ PostgreSQL: running" >&2
    else
        echo "⚠️ PostgreSQL: not running (optional)" >&2
        ((warnings += 1))
    fi

    # Non-critical: Vault installed
    if [[ "$SKIP_VAULT" == "true" ]]; then
        echo "⚠️ Vault: skipped (optional)" >&2
        ((warnings += 1))
    elif command_exists vault; then
        echo "✅ Vault: installed" >&2
    else
        echo "⚠️ Vault: not installed (optional)" >&2
        ((warnings += 1))
    fi

    # Non-critical: Cloud CLIs installed
    if [[ "$SKIP_CLOUD" == "true" ]]; then
        echo "⚠️ Cloud CLIs: skipped (optional)" >&2
        ((warnings += 1))
    else
        local missing_cloud=()
        [[ -x "$TARGET_HOME/.bun/bin/wrangler" ]] || missing_cloud+=("wrangler")
        [[ -x "$TARGET_HOME/.bun/bin/supabase" ]] || missing_cloud+=("supabase")
        [[ -x "$TARGET_HOME/.bun/bin/vercel" ]] || missing_cloud+=("vercel")

        if [[ ${#missing_cloud[@]} -eq 0 ]]; then
            echo "✅ Cloud CLIs: wrangler, supabase, vercel" >&2
        else
            echo "⚠️ Cloud CLIs: missing ${missing_cloud[*]} (optional)" >&2
            ((warnings += 1))
        fi
    fi

    echo "" >&2
    if [[ $critical_failed -eq 0 ]]; then
        echo "Smoke test: ${critical_passed}/${critical_total} critical passed, ${warnings} warnings" >&2
        return 0
    fi

    echo "Smoke test: ${critical_passed}/${critical_total} critical passed, ${critical_failed} critical failed, ${warnings} warnings" >&2
    return 1
}

# ============================================================
# Print summary
# ============================================================
print_summary() {
    if [[ "$DRY_RUN" == "true" ]]; then
        {
            if [[ "$HAS_GUM" == "true" ]]; then
                echo ""
                gum style \
                    --border double \
                    --border-foreground "$ACFS_WARNING" \
                    --padding "1 3" \
                    --margin "1 0" \
                    --align left \
                    "$(gum style --foreground "$ACFS_WARNING" --bold '🧪 ACFS Dry Run Complete (no changes made)')

Version: $ACFS_VERSION
Mode:    $MODE

No commands were executed. To actually install, re-run without --dry-run.
Tip: use --print to see upstream install scripts that will be fetched."
            else
                echo ""
                echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${YELLOW}║          🧪 ACFS Dry Run Complete (no changes made)        ║${NC}"
                echo -e "${YELLOW}╠════════════════════════════════════════════════════════════╣${NC}"
                echo ""
                echo -e "Version: ${BLUE}$ACFS_VERSION${NC}"
                echo -e "Mode:    ${BLUE}$MODE${NC}"
                echo ""
                echo -e "${GRAY}No commands were executed. Re-run without --dry-run to install.${NC}"
                echo -e "${GRAY}Tip: use --print to see upstream install scripts.${NC}"
                echo ""
                echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
                echo ""
            fi
        } >&2
        return 0
    fi

    local summary_content="Version: $ACFS_VERSION
Mode:    $MODE

Next steps:

  1. If you logged in as root, reconnect as ubuntu:
     exit
     ssh ubuntu@YOUR_SERVER_IP

  2. Run the onboarding tutorial:
     onboard

  3. Check everything is working:
     acfs doctor

  4. Start your agent cockpit:
     ntm"

    {
        if [[ "$HAS_GUM" == "true" ]]; then
            echo ""
            gum style \
                --border double \
                --border-foreground "$ACFS_SUCCESS" \
                --padding "1 3" \
                --margin "1 0" \
                --align left \
                "$(gum style --foreground "$ACFS_SUCCESS" --bold '🎉 ACFS Installation Complete!')

$summary_content"
        else
            echo ""
            echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║            🎉 ACFS Installation Complete!                   ║${NC}"
            echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
            echo ""
            echo -e "Version: ${BLUE}$ACFS_VERSION${NC}"
            echo -e "Mode:    ${BLUE}$MODE${NC}"
            echo ""
            echo -e "${YELLOW}Next steps:${NC}"
            echo ""
            echo "  1. If you logged in as root, reconnect as ubuntu:"
            echo -e "     ${GRAY}exit${NC}"
            echo -e "     ${GRAY}ssh ubuntu@YOUR_SERVER_IP${NC}"
            echo ""
            echo "  2. Run the onboarding tutorial:"
            echo -e "     ${BLUE}onboard${NC}"
            echo ""
            echo "  3. Check everything is working:"
            echo -e "     ${BLUE}acfs doctor${NC}"
            echo ""
            echo "  4. Start your agent cockpit:"
            echo -e "     ${BLUE}ntm${NC}"
            echo ""
            echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
            echo ""
        fi
    } >&2
}

# ============================================================
# Main
# ============================================================
main() {
    parse_args "$@"

    # Install gum FIRST so the entire script looks amazing
    install_gum_early

    # Print beautiful ASCII banner (now with gum if available!)
    print_banner

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run mode - no changes will be made"
        echo ""
    fi

    if [[ "$PRINT_MODE" == "true" ]]; then
        echo "The following tools will be installed from upstream:"
        echo ""
        echo "  - Oh My Zsh: https://ohmyz.sh"
        echo "  - Powerlevel10k: https://github.com/romkatv/powerlevel10k"
        echo "  - Bun: https://bun.sh"
        echo "  - Rust: https://rustup.rs"
        echo "  - uv: https://astral.sh/uv"
        echo "  - Atuin: https://atuin.sh"
        echo "  - Zoxide: https://github.com/ajeetdsouza/zoxide"
        echo "  - NTM: https://github.com/Dicklesworthstone/ntm"
        echo "  - MCP Agent Mail: https://github.com/Dicklesworthstone/mcp_agent_mail"
        echo "  - UBS: https://github.com/Dicklesworthstone/ultimate_bug_scanner"
        echo "  - Beads Viewer: https://github.com/Dicklesworthstone/beads_viewer"
        echo "  - CASS: https://github.com/Dicklesworthstone/coding_agent_session_search"
        echo "  - CM: https://github.com/Dicklesworthstone/cass_memory_system"
        echo "  - CAAM: https://github.com/Dicklesworthstone/coding_agent_account_manager"
        echo "  - SLB: https://github.com/Dicklesworthstone/simultaneous_launch_button"
        echo ""
        exit 0
    fi

    ensure_root
    init_target_paths
    ensure_ubuntu
    confirm_or_exit
    ensure_base_deps

    if [[ "$DRY_RUN" != "true" ]]; then
        normalize_user
        setup_filesystem
        setup_shell
        install_cli_tools
        install_languages
        install_agents
        install_cloud_db
        install_stack
        finalize

        SMOKE_TEST_FAILED=false
        if ! run_smoke_test; then
            SMOKE_TEST_FAILED=true
        fi
    fi

    print_summary

    if [[ "${SMOKE_TEST_FAILED:-false}" == "true" ]]; then
        exit 1
    fi
}

main "$@"
