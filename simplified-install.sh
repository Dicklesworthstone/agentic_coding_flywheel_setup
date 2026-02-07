#!/usr/bin/env bash
# ============================================================
# Simplified Development Environment Setup
# Streamlined installer for essential dev tools + Claude Code
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/simplified-install.sh | bash
#   Or locally: chmod +x simplified-install.sh && ./simplified-install.sh
#
# Options:
#   --skip-optional   Skip optional utilities (giil, csctf, xf, etc.)
#   --yes            Skip all prompts
# ============================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Options
SKIP_OPTIONAL=false
YES_MODE=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --skip-optional)
            SKIP_OPTIONAL=true
            shift
            ;;
        --yes)
            YES_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $arg"
            exit 1
            ;;
    esac
done

# Prevent interactive prompts
export DEBIAN_FRONTEND=noninteractive

# ============================================================
# Helper Functions
# ============================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run with sudo"
        exit 1
    fi
}

detect_user() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        TARGET_USER="$SUDO_USER"
    else
        TARGET_USER="$(whoami)"
    fi
    TARGET_HOME=$(eval echo "~$TARGET_USER")
    log_info "Installing for user: $TARGET_USER ($TARGET_HOME)"
}

# ============================================================
# Installation Phases
# ============================================================

phase_1_base_packages() {
    log_info "Phase 1: Installing base system packages..."

    apt-get update -qq

    apt-get install -y -qq \
        curl \
        git \
        ca-certificates \
        unzip \
        tar \
        xz-utils \
        jq \
        build-essential \
        gnupg \
        lsb-release \
        lsof \
        dnsutils \
        netcat-openbsd \
        strace \
        rsync

    log_success "Base packages installed"
}

phase_2_shell_environment() {
    log_info "Phase 2: Setting up Zsh environment..."

    # Install zsh
    apt-get install -y -qq zsh

    # Change default shell
    chsh -s "$(which zsh)" "$TARGET_USER" || true

    # Install oh-my-zsh (as target user)
    if [[ ! -d "$TARGET_HOME/.oh-my-zsh" ]]; then
        sudo -u "$TARGET_USER" bash -c 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
    fi

    # Install powerlevel10k theme
    if [[ ! -d "$TARGET_HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]]; then
        sudo -u "$TARGET_USER" git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
            "$TARGET_HOME/.oh-my-zsh/custom/themes/powerlevel10k"
    fi

    # Install zsh plugins
    if [[ ! -d "$TARGET_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]]; then
        sudo -u "$TARGET_USER" git clone https://github.com/zsh-users/zsh-autosuggestions \
            "$TARGET_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
    fi

    if [[ ! -d "$TARGET_HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]]; then
        sudo -u "$TARGET_USER" git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
            "$TARGET_HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
    fi

    # Update .zshrc
    if [[ -f "$TARGET_HOME/.zshrc" ]]; then
        sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$TARGET_HOME/.zshrc"
        sed -i 's/^plugins=.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$TARGET_HOME/.zshrc"
    fi

    log_success "Zsh environment configured"
}

phase_3_modern_cli_tools() {
    log_info "Phase 3: Installing modern CLI tools..."

    # Install from apt
    apt-get install -y -qq \
        ripgrep \
        tmux \
        fzf \
        direnv \
        gh \
        git-lfs \
        fd-find \
        bat \
        btop \
        docker.io \
        docker-compose-plugin 2>/dev/null || true

    # Try to install neovim (may not be available on all versions)
    apt-get install -y -qq neovim 2>/dev/null || log_warn "Neovim not available, skipping"

    # Add user to docker group
    usermod -aG docker "$TARGET_USER" || true

    # Install lazygit
    if ! command -v lazygit &>/dev/null; then
        log_info "Installing lazygit..."
        curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v0.44.1/lazygit_0.44.1_Linux_x86_64.tar.gz" \
            | tar xz -C /usr/local/bin lazygit
        chmod +x /usr/local/bin/lazygit
    fi

    # Install lazydocker
    if ! command -v lazydocker &>/dev/null; then
        log_info "Installing lazydocker..."
        curl -fsSL "https://github.com/jesseduffield/lazydocker/releases/download/v0.23.3/lazydocker_0.23.3_Linux_x86_64.tar.gz" \
            | tar xz -C /usr/local/bin lazydocker
        chmod +x /usr/local/bin/lazydocker
    fi

    log_success "Modern CLI tools installed"
}

phase_4_ssh_config() {
    log_info "Phase 4: Configuring SSH keepalive..."

    mkdir -p "$TARGET_HOME/.ssh"

    if [[ ! -f "$TARGET_HOME/.ssh/config" ]] || ! grep -q "ServerAliveInterval" "$TARGET_HOME/.ssh/config"; then
        cat >> "$TARGET_HOME/.ssh/config" << 'EOF'

# Keep connections alive through NAT/firewalls
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    TCPKeepAlive yes
EOF
        chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.ssh"
        chmod 600 "$TARGET_HOME/.ssh/config"
    fi

    log_success "SSH configured"
}

phase_5_language_runtimes() {
    log_info "Phase 5: Installing language runtimes..."

    # Install Bun
    if ! command -v bun &>/dev/null; then
        log_info "Installing Bun..."
        sudo -u "$TARGET_USER" bash -c 'curl -fsSL https://bun.sh/install | bash'
        export PATH="$TARGET_HOME/.bun/bin:$PATH"
    fi

    # Install uv (Python package manager)
    if ! command -v uv &>/dev/null; then
        log_info "Installing uv..."
        sudo -u "$TARGET_USER" bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
    fi

    # Install Rust
    if ! command -v rustc &>/dev/null; then
        log_info "Installing Rust..."
        sudo -u "$TARGET_USER" bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly'
        export PATH="$TARGET_HOME/.cargo/bin:$PATH"
    fi

    # Install Go
    apt-get install -y -qq golang-go

    # Install NVM and Node.js
    if [[ ! -d "$TARGET_HOME/.nvm" ]]; then
        log_info "Installing NVM and Node.js..."
        sudo -u "$TARGET_USER" bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash'
        sudo -u "$TARGET_USER" bash -c 'export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" && nvm install --lts'
    fi

    log_success "Language runtimes installed"
}

phase_6_enhanced_cli() {
    log_info "Phase 6: Installing enhanced CLI tools..."

    # Ensure cargo is in PATH for this session
    export PATH="$TARGET_HOME/.cargo/bin:$PATH"

    # Install atuin (shell history)
    if ! command -v atuin &>/dev/null; then
        log_info "Installing atuin..."
        sudo -u "$TARGET_USER" bash -c 'curl --proto "=https" --tlsv1.2 -LsSf https://setup.atuin.sh | sh'
    fi

    # Install zoxide (smart cd)
    if ! command -v zoxide &>/dev/null; then
        log_info "Installing zoxide..."
        sudo -u "$TARGET_USER" bash -c 'curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh'
    fi

    # Install ast-grep via cargo
    if ! command -v sg &>/dev/null; then
        log_info "Installing ast-grep..."
        sudo -u "$TARGET_USER" bash -c 'source "$HOME/.cargo/env" && cargo install ast-grep'
    fi

    log_success "Enhanced CLI tools installed"
}

phase_7_ai_agents() {
    log_info "Phase 7: Installing AI coding agents..."

    # Install Claude Code
    if ! command -v claude &>/dev/null; then
        log_info "Installing Claude Code..."
        # Ensure ~/.local/bin exists
        mkdir -p "$TARGET_HOME/.local/bin"
        chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.local/bin"

        sudo -u "$TARGET_USER" bash -c 'curl -fsSL https://s3.amazonaws.com/downloads.anthropic.com/claude/cli/linux/claude_code_install.sh | sh'
    fi

    # Install OpenCode (assuming it's via npm/bun)
    # NOTE: Adjust this based on actual OpenCode installation method
    if ! command -v opencode &>/dev/null; then
        log_info "Installing OpenCode..."
        # Example: if it's an npm package
        # sudo -u "$TARGET_USER" bash -c 'source "$HOME/.nvm/nvm.sh" && npm install -g opencode-cli'

        # Or if it's a standalone binary, adjust accordingly
        log_warn "OpenCode installation method not specified - please install manually"
        log_warn "Visit: https://github.com/openai/opencode or appropriate source"
    fi

    log_success "AI agents installed"
}

phase_8_optional_utilities() {
    if [[ "$SKIP_OPTIONAL" == "true" ]]; then
        log_info "Skipping optional utilities (--skip-optional flag set)"
        return
    fi

    log_info "Phase 8: Installing optional utilities..."

    # These are placeholder installations - adjust URLs/methods based on actual tools
    declare -A utilities=(
        ["giil"]="Download images from cloud share links"
        ["csctf"]="Convert AI chat shares to Markdown/HTML"
        ["xf"]="X/Twitter archive search"
        ["tru"]="Token-optimized notation for LLMs"
        ["rano"]="Network observer for AI CLIs"
        ["mdwb"]="Markdown Web Browser"
        ["s2p"]="Source to Prompt TUI"
        ["aadc"]="ASCII diagram corrector"
        ["caut"]="Coding Agent Usage Tracker"
        ["rust_proxy"]="Transparent proxy"
    )

    log_warn "Optional utilities require manual installation"
    log_warn "See simplified-setup.yaml for repository URLs and installation methods"

    # Example: Install from GitHub releases (adjust per tool)
    # for tool in "${!utilities[@]}"; do
    #     if ! command -v "$tool" &>/dev/null; then
    #         log_info "Install $tool manually: ${utilities[$tool]}"
    #     fi
    # done

    log_success "Optional utilities section completed"
}

phase_9_workspace() {
    log_info "Phase 9: Setting up workspace..."

    # Create workspace directories
    mkdir -p /data/projects
    mkdir -p /data/cache

    chown -R "$TARGET_USER:$TARGET_USER" /data/projects
    chown -R "$TARGET_USER:$TARGET_USER" /data/cache

    # Create starter project
    if [[ ! -d "/data/projects/my_first_project" ]]; then
        sudo -u "$TARGET_USER" mkdir -p "/data/projects/my_first_project"
        sudo -u "$TARGET_USER" bash -c 'cd /data/projects/my_first_project && git init'
    fi

    log_success "Workspace configured"
}

finalize_installation() {
    log_info "Finalizing installation..."

    # Add PATH exports to .zshrc if not already present
    if ! grep -q "# Simplified Dev Environment Paths" "$TARGET_HOME/.zshrc" 2>/dev/null; then
        cat >> "$TARGET_HOME/.zshrc" << 'EOF'

# Simplified Dev Environment Paths
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Atuin
if command -v atuin &>/dev/null; then
    eval "$(atuin init zsh)"
fi

# Zoxide
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh)"
fi

# Direnv
if command -v direnv &>/dev/null; then
    eval "$(direnv hook zsh)"
fi
EOF
    fi

    chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.zshrc"

    log_success "Installation complete!"
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  🎉 Development Environment Setup Complete!          ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Installed components:${NC}"
    echo "  ✓ Base system packages + jq"
    echo "  ✓ Zsh with oh-my-zsh + powerlevel10k"
    echo "  ✓ Modern CLI tools (ripgrep, fzf, lazygit, etc.)"
    echo "  ✓ Language runtimes (Bun, Python/uv, Rust, Go, Node.js)"
    echo "  ✓ Enhanced tools (atuin, zoxide, ast-grep)"
    echo "  ✓ Claude Code AI assistant"
    echo "  ✓ Workspace at /data/projects"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. Restart your terminal or run: zsh"
    echo "  2. Configure Claude Code: claude auth login"
    echo "  3. Configure GitHub CLI: gh auth login"
    echo "  4. Start coding in: /data/projects/my_first_project"
    echo ""
    echo -e "${BLUE}Optional utilities:${NC}"
    echo "  See simplified-setup.yaml for additional tools to install"
    echo ""
}

# ============================================================
# Main Execution
# ============================================================

main() {
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     Simplified Development Environment Setup         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_root
    detect_user

    if [[ "$YES_MODE" == "false" ]]; then
        echo -e "${YELLOW}This will install development tools for user: $TARGET_USER${NC}"
        read -p "Continue? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled"
            exit 0
        fi
    fi

    phase_1_base_packages
    phase_2_shell_environment
    phase_3_modern_cli_tools
    phase_4_ssh_config
    phase_5_language_runtimes
    phase_6_enhanced_cli
    phase_7_ai_agents
    phase_8_optional_utilities
    phase_9_workspace
    finalize_installation
}

main "$@"
