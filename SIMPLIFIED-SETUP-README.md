# Simplified Development Environment Setup

A streamlined, focused development environment with essential tools and Claude Code AI assistant.

## 🎯 What This Installs

This setup is based on the ACFS repository but significantly simplified by removing infrastructure, cloud tools, and most of the agent stack.

### Complete Tool List

#### **Base System Packages** (15 packages via apt)
- `curl` - HTTP client for downloading resources
- `git` - Version control system
- `ca-certificates` - Root certificate authorities
- `unzip` - Archive extraction
- `tar` - Archive utility
- `xz-utils` - XZ compression
- **`jq`** - JSON processor (explicitly included)
- `build-essential` - C/C++ compiler and build tools
- `gnupg` - GPG cryptography
- `lsb-release` - LSB version reporting
- `lsof` - List open files
- `dnsutils` - DNS utilities (dig, nslookup)
- `netcat-openbsd` - Network utility (nc)
- `strace` - System call tracer
- `rsync` - File synchronization

#### **Shell Environment**
- **Zsh** - Modern shell with extensive customization
- **Oh-My-Zsh** - Framework with plugin system
- **Powerlevel10k** - Modern prompt theme
- **zsh-autosuggestions** - Command history suggestions
- **zsh-syntax-highlighting** - Syntax highlighting for commands

#### **Modern CLI Tools** (20+ tools)
- **ripgrep (rg)** - Ultra-fast search tool
- **tmux** - Terminal multiplexer
- **fzf** - Fuzzy finder for command-line
- **direnv** - Load environment variables from .envrc
- **gh** - GitHub CLI
- **git-lfs** - Git Large File Storage
- **fd-find** - Better find alternative
- **bat** - Better cat with syntax highlighting
- **btop** - Modern system monitor
- **neovim** - Modern vim editor
- **docker.io** - Docker container runtime
- **docker-compose-plugin** - Docker Compose v2
- **lazygit** (v0.44.1) - Simple git TUI
- **lazydocker** (v0.23.3) - Simple Docker TUI

#### **Language Runtimes** (5 runtimes)
1. **Bun** - Fast JavaScript/TypeScript runtime & package manager
2. **uv** - Fast Python package manager & virtualenv creator
3. **Rust** (nightly) - Rust programming language
   - `cargo` - Rust package manager
   - `rustup` - Rust toolchain installer
4. **Go** - Go programming language
5. **Node.js** (via NVM) - JavaScript runtime
   - `nvm` - Node Version Manager

#### **Enhanced CLI Tools**
- **atuin** - Shell history search with sync
- **zoxide** - Smart directory navigation (learns your habits)
- **ast-grep (sg)** - Syntax-aware code search and manipulation

#### **AI Coding Agent**
- **Claude Code** - Anthropic's official CLI agent
- **OpenCode** - OpenAI code assistant (installation method TBD)

#### **Additional Utilities** (Optional, 10 tools)

These require manual installation or are marked optional in the script:

1. **giil** - Download images from cloud share links for debugging
2. **csctf** - Convert AI chat share links to Markdown/HTML
3. **xf** - Ultra-fast X/Twitter archive search with Tantivy
4. **tru** (toon_rust) - Token-optimized notation for LLM context efficiency
5. **rano** - Network observer for AI CLIs with request/response logging
6. **mdwb** - Markdown Web Browser for converting websites to Markdown
7. **s2p** - Source to Prompt TUI code-to-LLM-prompt generator
8. **aadc** - ASCII diagram corrector
9. **caut** - Coding Agent Usage Tracker for LLM provider usage
10. **rust_proxy** - Transparent proxy for network debugging

#### **Workspace Setup**
- `/data/projects` - Main project workspace directory
- `/data/cache` - Cache directory
- `/data/projects/my_first_project` - Starter project with git init

---

## 📊 Summary Statistics

- **Total System Packages**: 15 (via apt)
- **Language Runtimes**: 5 (Bun, Python/uv, Rust, Go, Node.js)
- **Modern CLI Tools**: 20+
- **AI Coding Agent**: 1 (Claude Code) + 1 (OpenCode)
- **Enhanced Tools**: 3 (atuin, zoxide, ast-grep)
- **Optional Utilities**: 10
- **Total Tools**: 50+ including optional utilities

---

## 🚀 Installation

### Quick Start

```bash
# Download and run (requires sudo)
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/simplified-install.sh | sudo bash

# Or clone and run locally
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO
chmod +x simplified-install.sh
sudo ./simplified-install.sh
```

### Installation Options

```bash
# Skip optional utilities
sudo ./simplified-install.sh --skip-optional

# Skip all prompts
sudo ./simplified-install.sh --yes

# Combine options
sudo ./simplified-install.sh --yes --skip-optional
```

---

## ⏱️ Installation Time

Estimated: **15-30 minutes** depending on:
- Network speed
- System specifications
- Whether optional utilities are installed

---

## 🔧 Post-Installation Setup

### 1. Restart Your Terminal

```bash
# Start zsh
zsh

# Or restart your terminal completely
```

### 2. Configure AI Tools

```bash
# Claude Code authentication
claude auth login

# GitHub CLI authentication
gh auth login
```

### 3. Verify Installation

```bash
# Check versions
claude --version
bun --version
cargo --version
go version
node --version

# Check CLI tools
rg --version
fzf --version
lazygit --version
atuin --version
zoxide --version
```

### 4. Start Your First Project

```bash
cd /data/projects/my_first_project

# Initialize your project
echo "# My First Project" > README.md
git add .
git commit -m "Initial commit"

# Start coding with Claude
claude code
```

---

## 📦 What's Removed from Original ACFS?

This simplified setup **removes** the following from the original repository:

### ❌ Removed Components

1. **ACFS Infrastructure**
   - `acfs-update` command
   - `acfs doctor` health checks
   - `onboard` interactive tutorial
   - Systemd nightly update timers
   - ACFS manifest system

2. **Cloud & Database Tools**
   - HashiCorp Vault (secrets management)
   - PostgreSQL 18
   - Wrangler (Cloudflare Workers CLI)
   - Supabase CLI
   - Vercel CLI

3. **Dicklesworthstone Agent Stack** (23+ tools)
   - `ntm` - Named tmux manager
   - `am` - MCP Agent Mail
   - `ms` - Meta Skill
   - `apr` - Automated Plan Reviser
   - `jfp` - JeffreysPrompts CLI
   - `pt` - Process Triage
   - `ubs` - Ultimate Bug Scanner
   - `br` - beads_rust (issue tracking)
   - `bv` - beads_viewer (task prioritization)
   - `cass` - Coding Agent Session Search
   - `cm` - CASS Memory System
   - `caam` - Coding Agent Account Manager
   - `slb` - Simultaneous Launch Button
   - `dcg` - Destructive Command Guard
   - `ru` - Repo Updater
   - `brenner` - Research session manager
   - `rch` - Remote Compilation Helper
   - `wa` - WezTerm Automata
   - `sysmoni` - System Resource Protection
   - And more...

4. **AI Agents**
   - ❌ Gemini CLI (removed)
   - ❌ Codex CLI (removed)
   - ✅ Claude Code (kept)

---

## 🆚 Comparison: ACFS vs Simplified Setup

| Category | ACFS Original | Simplified Setup |
|----------|---------------|------------------|
| **Total Tools** | 100+ | ~50 |
| **AI Agents** | 3 (Claude, Codex, Gemini) | 2 (Claude, OpenCode) |
| **Agent Stack** | 23+ specialized tools | 0 (removed) |
| **Cloud Tools** | 5 (Vault, PostgreSQL, etc.) | 0 (removed) |
| **Infrastructure** | ACFS system (updates, onboard) | 0 (removed) |
| **Install Time** | 30-60 minutes | 15-30 minutes |
| **Disk Space** | 5-10 GB | 2-4 GB |
| **Complexity** | High (multi-agent system) | Low (focused dev env) |
| **Use Case** | Advanced multi-agent coding | Simple AI-assisted development |

---

## 🛠️ Customization

### Adding More Tools

Edit `simplified-install.sh` and add to the appropriate phase:

```bash
phase_3_modern_cli_tools() {
    # Add your custom tool here
    apt-get install -y -qq your-tool
}
```

### Modifying Language Runtimes

```bash
phase_5_language_runtimes() {
    # Example: Install Python via apt instead of uv
    apt-get install -y python3 python3-pip
}
```

### Installing Optional Utilities

See `simplified-setup.yaml` for repository URLs and installation methods for each optional utility.

Example for installing from GitHub:

```bash
# Install giil
curl -fsSL https://install.giil.dev | sh

# Or build from source if it's a Rust project
git clone https://github.com/USER/giil
cd giil
cargo build --release
sudo cp target/release/giil /usr/local/bin/
```

---

## 📋 Installation Manifest

The complete installation plan is defined in `simplified-setup.yaml`:

```yaml
metadata:
  name: "Simplified Dev Environment"
  version: "1.0.0"

system_packages:
  apt: [curl, git, jq, ...]

shell:
  shell_type: zsh
  framework: oh-my-zsh
  theme: powerlevel10k

languages:
  bun: {...}
  uv: {...}
  rust: {...}
  go: {...}
  node: {...}

ai_agents:
  claude_code: {...}
  opencode: {...}
```

See the full file for detailed configuration.

---

## 🔍 Troubleshooting

### Permission Issues

```bash
# Make sure you're running with sudo
sudo ./simplified-install.sh
```

### Docker Permission Denied

```bash
# Log out and back in after installation
# Or manually add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

### Claude Code Not Found

```bash
# Add to PATH in ~/.zshrc
export PATH="$HOME/.local/bin:$PATH"

# Reload shell
source ~/.zshrc
```

### Rust/Cargo Commands Not Found

```bash
# Source cargo environment
source "$HOME/.cargo/env"

# Or add to ~/.zshrc (should be automatic)
export PATH="$HOME/.cargo/bin:$PATH"
```

---

## 🤝 Contributing

To suggest improvements:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## 📄 License

Same as the original ACFS repository.

---

## 🙏 Credits

Based on the excellent work from:
- [ACFS - Agentic Coding Flywheel Setup](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup)
- Created by Dicklesworthstone

This simplified version focuses on the core development tools while removing the advanced multi-agent infrastructure.

---

## 📚 Additional Resources

- **Claude Code Documentation**: https://docs.anthropic.com/claude/docs
- **GitHub CLI**: https://cli.github.com/
- **Oh-My-Zsh**: https://ohmyz.sh/
- **Rust**: https://www.rust-lang.org/
- **Bun**: https://bun.sh/

---

## 🆘 Support

For issues with:
- **This simplified setup**: Open an issue in this repository
- **Original ACFS**: See [original repo](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup)
- **Individual tools**: Consult their respective documentation

---

**Happy coding with Claude! 🚀**
