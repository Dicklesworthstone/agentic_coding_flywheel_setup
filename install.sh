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
ACFS_REPO="https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup"
ACFS_RAW="https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main"
# Note: ACFS_HOME is set after TARGET_HOME is determined
ACFS_LOG_DIR="/var/log/acfs"

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
PINK='\033[0;35m'
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
ACFS_ACCENT="#cba6f7"

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
        echo "$banner" | gum style --foreground "$ACFS_PRIMARY" --bold
    else
        echo -e "${BLUE}$banner${NC}"
    fi
}

# ============================================================
# Logging functions (with gum enhancement)
# ============================================================
log_step() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_PRIMARY" --bold "[$1]" | tr -d '\n'
        echo -n " "
        gum style "$2"
    else
        echo -e "${BLUE}[$1]${NC} $2" >&2
    fi
}

log_detail() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_MUTED" --margin "0 0 0 4" "→ $1"
    else
        echo -e "${GRAY}    → $1${NC}" >&2
    fi
}

log_success() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_SUCCESS" --bold "✓ $1"
    else
        echo -e "${GREEN}✓ $1${NC}" >&2
    fi
}

log_warn() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_WARNING" "⚠ $1"
    else
        echo -e "${YELLOW}⚠ $1${NC}" >&2
    fi
}

log_error() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_ERROR" --bold "✖ $1"
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

ensure_root() {
    if [[ $EUID -ne 0 ]]; then
        if command_exists sudo; then
            SUDO="sudo"
        else
            log_fatal "This script requires root privileges. Please run as root or install sudo."
        fi
    else
        SUDO=""
    fi
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
    log_step "0/8" "Checking base dependencies..."

    local missing=()
    for cmd in curl git jq; do
        if ! command_exists "$cmd"; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_detail "Installing missing packages: ${missing[*]}"
        $SUDO apt-get update -y
        $SUDO apt-get install -y curl git ca-certificates unzip tar xz-utils jq build-essential
    fi
}

# ============================================================
# Phase 1: User normalization
# ============================================================
normalize_user() {
    log_step "1/8" "Normalizing user account..."

    local current_user
    current_user=$(whoami)

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
    log_step "2/8" "Setting up filesystem..."

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
    log_step "3/8" "Setting up shell..."

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
        run_as_target sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
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
    curl -fsSL "$ACFS_RAW/acfs/zsh/acfs.zshrc" -o "$ACFS_HOME/zsh/acfs.zshrc"
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
install_cli_tools() {
    log_step "4/8" "Installing CLI tools..."

    # Install gum first for enhanced UI
    if ! command_exists gum; then
        log_detail "Installing gum for glamorous shell scripts"
        $SUDO mkdir -p /etc/apt/keyrings
        curl -fsSL https://repo.charm.sh/apt/gpg.key | $SUDO gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null || true
        echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | $SUDO tee /etc/apt/sources.list.d/charm.list > /dev/null
        $SUDO apt-get update -y
        $SUDO apt-get install -y gum 2>/dev/null || true

        # Update HAS_GUM if install succeeded
        if command -v gum &>/dev/null; then
            HAS_GUM=true
            log_success "gum installed - enhanced UI enabled"
        fi
    else
        log_detail "gum already installed"
    fi

    # Install apt packages
    log_detail "Installing apt packages"
    $SUDO apt-get install -y \
        ripgrep tmux fzf direnv \
        lsd eza bat fd-find btop dust neovim \
        docker.io docker-compose-plugin \
        lazygit 2>/dev/null || true

    # Add user to docker group
    $SUDO usermod -aG docker "$(whoami)" 2>/dev/null || true

    log_success "CLI tools installed"
}

# ============================================================
# Phase 5: Language runtimes
# ============================================================
install_languages() {
    log_step "5/8" "Installing language runtimes..."

    # Bun (install as target user)
    if [[ ! -d "$TARGET_HOME/.bun" ]]; then
        log_detail "Installing Bun for $TARGET_USER"
        run_as_target bash -c 'curl -fsSL https://bun.sh/install | bash'
    fi

    # Rust (install as target user)
    if [[ ! -d "$TARGET_HOME/.cargo" ]]; then
        log_detail "Installing Rust for $TARGET_USER"
        run_as_target bash -c 'curl https://sh.rustup.rs -sSf | sh -s -- -y'
    fi

    # Go (system-wide)
    if ! command_exists go; then
        log_detail "Installing Go"
        $SUDO apt-get install -y golang-go
    fi

    # uv (install as target user)
    if [[ ! -f "$TARGET_HOME/.local/bin/uv" ]]; then
        log_detail "Installing uv for $TARGET_USER"
        run_as_target bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
    fi

    # Atuin (install as target user)
    if [[ ! -d "$TARGET_HOME/.atuin" ]]; then
        log_detail "Installing Atuin for $TARGET_USER"
        run_as_target bash -c 'curl --proto "=https" --tlsv1.2 -LsSf https://setup.atuin.sh | sh'
    fi

    # Zoxide (install as target user)
    if [[ ! -f "$TARGET_HOME/.local/bin/zoxide" ]]; then
        log_detail "Installing Zoxide for $TARGET_USER"
        run_as_target bash -c 'curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh'
    fi

    log_success "Language runtimes installed"
}

# ============================================================
# Phase 6: Coding agents
# ============================================================
install_agents() {
    log_step "6/8" "Installing coding agents..."

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
# Phase 7: Dicklesworthstone stack
# ============================================================
install_stack() {
    log_step "7/8" "Installing Dicklesworthstone stack..."

    # Helper to run install scripts as target user
    run_install_as_target() {
        local url="$1"
        local args="${2:-}"
        run_as_target bash -c "curl -fsSL '$url' 2>/dev/null | bash -s -- $args" || return 1
    }

    # NTM (Named Tmux Manager)
    log_detail "Installing NTM"
    run_install_as_target "https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh" || log_warn "NTM installation may have failed"

    # MCP Agent Mail
    log_detail "Installing MCP Agent Mail"
    run_install_as_target "https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail/main/scripts/install.sh?$(date +%s)" "--yes" || log_warn "MCP Agent Mail installation may have failed"

    # Ultimate Bug Scanner
    log_detail "Installing Ultimate Bug Scanner"
    run_install_as_target "https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/master/install.sh?$(date +%s)" "--easy-mode" || log_warn "UBS installation may have failed"

    # Beads Viewer
    log_detail "Installing Beads Viewer"
    run_install_as_target "https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh?$(date +%s)" || log_warn "Beads Viewer installation may have failed"

    # CASS (Coding Agent Session Search)
    log_detail "Installing CASS"
    run_install_as_target "https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh" "--easy-mode --verify" || log_warn "CASS installation may have failed"

    # CASS Memory System
    log_detail "Installing CASS Memory System"
    run_install_as_target "https://raw.githubusercontent.com/Dicklesworthstone/cass_memory_system/main/install.sh" "--easy-mode --verify" || log_warn "CM installation may have failed"

    # CAAM (Coding Agent Account Manager)
    log_detail "Installing CAAM"
    run_install_as_target "https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_account_manager/main/install.sh?$(date +%s)" || log_warn "CAAM installation may have failed"

    # SLB (Simultaneous Launch Button)
    log_detail "Installing SLB"
    run_install_as_target "https://raw.githubusercontent.com/Dicklesworthstone/simultaneous_launch_button/main/scripts/install.sh" || log_warn "SLB installation may have failed"

    log_success "Dicklesworthstone stack installed"
}

# ============================================================
# Phase 8: Final wiring
# ============================================================
finalize() {
    log_step "8/8" "Finalizing installation..."

    # Copy tmux config
    log_detail "Installing tmux config"
    curl -fsSL "$ACFS_RAW/acfs/tmux/tmux.conf" -o "$ACFS_HOME/tmux/tmux.conf"
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
        curl -fsSL "$ACFS_RAW/acfs/onboard/lessons/$lesson" -o "$ACFS_HOME/onboard/lessons/$lesson"
    done

    log_detail "Installing onboard command"
    curl -fsSL "$ACFS_RAW/acfs/onboard/onboard.sh" -o "$ACFS_HOME/onboard/onboard.sh"
    $SUDO chmod 755 "$ACFS_HOME/onboard/onboard.sh"
    $SUDO chown -R "$TARGET_USER:$TARGET_USER" "$ACFS_HOME/onboard"

    run_as_target mkdir -p "$TARGET_HOME/.local/bin"
    run_as_target ln -sf "$ACFS_HOME/onboard/onboard.sh" "$TARGET_HOME/.local/bin/onboard"

    # Create state file
    cat > "$ACFS_STATE_FILE" << EOF
{
  "version": "$ACFS_VERSION",
  "installed_at": "$(date -Iseconds)",
  "mode": "$MODE",
  "target_user": "$TARGET_USER",
  "completed_phases": [1, 2, 3, 4, 5, 6, 7, 8]
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
        bash -c "$cmd"
        return $?
    fi

    if command_exists sudo; then
        sudo -u "$TARGET_USER" -H bash -c "$cmd"
        return $?
    fi

    # Fallback: use su if sudo isn't available
    su - "$TARGET_USER" -c "bash -c $(printf %q "$cmd")"
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
        ((critical_passed++))
    else
        echo "✖ User: expected ubuntu (TARGET_USER=$TARGET_USER)" >&2
        echo "    Fix: set TARGET_USER=ubuntu and ensure the user exists" >&2
        ((critical_failed++))
    fi

    # 2) Shell is zsh
    local target_shell=""
    target_shell=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f7 || true)
    if [[ "$target_shell" == *"zsh"* ]]; then
        echo "✅ Shell: zsh" >&2
        ((critical_passed++))
    else
        echo "✖ Shell: zsh (found: ${target_shell:-unknown})" >&2
        echo "    Fix: sudo chsh -s \"\$(command -v zsh)\" \"$TARGET_USER\"" >&2
        ((critical_failed++))
    fi

    # 3) Passwordless sudo works
    if _smoke_run_as_target "sudo -n true" &>/dev/null; then
        echo "✅ Sudo: passwordless" >&2
        ((critical_passed++))
    else
        echo "✖ Sudo: passwordless" >&2
        echo "    Fix: re-run installer with --mode vibe (or configure NOPASSWD for $TARGET_USER)" >&2
        ((critical_failed++))
    fi

    # 4) /data/projects exists
    if _smoke_run_as_target "[[ -d /data/projects && -w /data/projects ]]" &>/dev/null; then
        echo "✅ Workspace: /data/projects exists" >&2
        ((critical_passed++))
    else
        echo "✖ Workspace: /data/projects exists" >&2
        echo "    Fix: sudo mkdir -p /data/projects && sudo chown -R \"$TARGET_USER:$TARGET_USER\" /data" >&2
        ((critical_failed++))
    fi

    # 5) bun, uv, cargo, go available
    local missing_lang=()
    [[ -x "$TARGET_HOME/.bun/bin/bun" ]] || missing_lang+=("bun")
    [[ -x "$TARGET_HOME/.local/bin/uv" ]] || missing_lang+=("uv")
    [[ -x "$TARGET_HOME/.cargo/bin/cargo" ]] || missing_lang+=("cargo")
    command_exists go || missing_lang+=("go")
    if [[ ${#missing_lang[@]} -eq 0 ]]; then
        echo "✅ Languages: bun, uv, cargo, go available" >&2
        ((critical_passed++))
    else
        echo "✖ Languages: missing ${missing_lang[*]}" >&2
        echo "    Fix: re-run installer (phase 5) and check $ACFS_LOG_DIR/install.log" >&2
        ((critical_failed++))
    fi

    # 6) claude, codex, gemini commands exist
    local missing_agents=()
    [[ -x "$TARGET_HOME/.bun/bin/claude" ]] || missing_agents+=("claude")
    [[ -x "$TARGET_HOME/.bun/bin/codex" ]] || missing_agents+=("codex")
    [[ -x "$TARGET_HOME/.bun/bin/gemini" ]] || missing_agents+=("gemini")
    if [[ ${#missing_agents[@]} -eq 0 ]]; then
        echo "✅ Agents: claude, codex, gemini" >&2
        ((critical_passed++))
    else
        echo "✖ Agents: missing ${missing_agents[*]}" >&2
        echo "    Fix: re-run installer (phase 6) to install agent CLIs" >&2
        ((critical_failed++))
    fi

    # 7) ntm command works
    if _smoke_run_as_target "command -v ntm >/dev/null && ntm --help >/dev/null 2>&1"; then
        echo "✅ NTM: working" >&2
        ((critical_passed++))
    else
        echo "✖ NTM: not working" >&2
        echo "    Fix: re-run installer (phase 7) or run NTM installer: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh | bash" >&2
        ((critical_failed++))
    fi

    # 8) onboard command exists
    if [[ -x "$TARGET_HOME/.local/bin/onboard" ]]; then
        echo "✅ Onboard: installed" >&2
        ((critical_passed++))
    else
        echo "✖ Onboard: missing" >&2
        echo "    Fix: re-run installer (phase 8) or install onboard to $TARGET_HOME/.local/bin/onboard" >&2
        ((critical_failed++))
    fi

    # Non-critical: Agent Mail server can start
    if [[ -x "$TARGET_HOME/mcp_agent_mail/scripts/run_server_with_token.sh" ]]; then
        echo "✅ Agent Mail: installed (run 'am' to start)" >&2
    else
        echo "⚠️ Agent Mail: not installed (re-run installer phase 7)" >&2
        ((warnings++))
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
        ((warnings++))
    fi

    # Non-critical: PostgreSQL service running
    if [[ "$SKIP_POSTGRES" == "true" ]]; then
        echo "⚠️ PostgreSQL: skipped (optional)" >&2
        ((warnings++))
    elif command_exists systemctl && systemctl is-active --quiet postgresql 2>/dev/null; then
        echo "✅ PostgreSQL: running" >&2
    else
        echo "⚠️ PostgreSQL: not running (optional)" >&2
        ((warnings++))
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
}

# ============================================================
# Main
# ============================================================
main() {
    parse_args "$@"

    # Print beautiful ASCII banner
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
    ensure_base_deps

    if [[ "$DRY_RUN" != "true" ]]; then
        normalize_user
        setup_filesystem
        setup_shell
        install_cli_tools
        install_languages
        install_agents
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
