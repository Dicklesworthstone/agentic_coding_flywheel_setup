# Complete Tools List - Simplified Setup

Quick reference of all tools that will be installed.

## ✅ Always Installed (Core Tools)

### Base System (15 packages)
```
curl, git, ca-certificates, unzip, tar, xz-utils, jq,
build-essential, gnupg, lsb-release, lsof, dnsutils,
netcat-openbsd, strace, rsync
```

### Shell Environment (5 components)
```
1. zsh                      - Modern shell
2. oh-my-zsh                - Framework
3. powerlevel10k            - Theme
4. zsh-autosuggestions      - Plugin
5. zsh-syntax-highlighting  - Plugin
```

### Modern CLI Tools (14 tools)
```
1.  ripgrep (rg)           - Fast search
2.  tmux                   - Terminal multiplexer
3.  fzf                    - Fuzzy finder
4.  direnv                 - Environment loader
5.  gh                     - GitHub CLI
6.  git-lfs                - Git LFS
7.  fd-find                - Better find
8.  bat                    - Better cat
9.  btop                   - System monitor
10. neovim                 - Modern vim
11. docker.io              - Docker
12. docker-compose-plugin  - Docker Compose
13. lazygit (v0.44.1)      - Git TUI
14. lazydocker (v0.23.3)   - Docker TUI
```

### Language Runtimes (5 runtimes)
```
1. Bun        - JS/TS runtime & package manager
2. uv         - Python package manager
3. Rust       - Rust + cargo + rustup (nightly)
4. Go         - Go programming language
5. Node.js    - JavaScript runtime via NVM
```

### Enhanced CLI (3 tools)
```
1. atuin      - Shell history search
2. zoxide     - Smart cd
3. ast-grep   - Syntax-aware search
```

### AI Agents (2 agents)
```
1. Claude Code  - Anthropic's CLI agent
2. OpenCode     - OpenAI assistant (manual install)
```

### Workspace
```
/data/projects              - Project directory
/data/cache                 - Cache directory
/data/projects/my_first_project  - Starter project
```

**Total Core Tools: ~44 tools**

---

## 🔧 Optional Utilities (10 tools)

Install manually - see simplified-setup.yaml for URLs:

```
1.  giil         - Download images from cloud links
2.  csctf        - Convert AI chats to Markdown
3.  xf           - Twitter/X archive search
4.  tru          - Token-optimized notation
5.  rano         - Network observer for AI
6.  mdwb         - Markdown web browser
7.  s2p          - Source to prompt TUI
8.  aadc         - ASCII diagram corrector
9.  caut         - Agent usage tracker
10. rust_proxy   - Transparent proxy
```

---

## ❌ Not Included (Removed from ACFS)

### ACFS Infrastructure
```
❌ acfs-update
❌ acfs doctor
❌ onboard
❌ acfs-nightly-update timer
```

### Cloud & Database
```
❌ HashiCorp Vault
❌ PostgreSQL 18
❌ Wrangler (Cloudflare)
❌ Supabase CLI
❌ Vercel CLI
```

### Dicklesworthstone Agent Stack (23+ tools)
```
❌ ntm    - Named tmux manager
❌ am     - MCP Agent Mail
❌ ms     - Meta Skill
❌ apr    - Automated Plan Reviser
❌ jfp    - JeffreysPrompts
❌ pt     - Process Triage
❌ ubs    - Ultimate Bug Scanner
❌ br     - beads_rust issue tracker
❌ bv     - beads_viewer task prioritization
❌ cass   - Session Search
❌ cm     - CASS Memory
❌ caam   - Account Manager
❌ slb    - Simultaneous Launch Button
❌ dcg    - Destructive Command Guard
❌ ru     - Repo Updater
❌ brenner - Research manager
❌ rch    - Remote Compilation Helper
❌ wa     - WezTerm Automata
❌ sysmoni - System Resource Protection
... and more
```

### AI Agents Removed
```
❌ Gemini CLI
❌ Codex CLI
```

---

## 📊 At a Glance

| Category | Count |
|----------|-------|
| Base System Packages | 15 |
| Shell Components | 5 |
| Modern CLI Tools | 14 |
| Language Runtimes | 5 |
| Enhanced CLI Tools | 3 |
| AI Agents | 2 |
| Optional Utilities | 10 |
| **TOTAL** | **~54** |

---

## 🆚 vs Original ACFS

```
ACFS Original:      100+ tools
Simplified Setup:   ~54 tools

Reduction:          ~46% fewer tools
Install Time:       50% faster
Disk Space:         60% less
Complexity:         80% simpler
```

---

## 🚀 Quick Command Reference

After installation, you'll have access to:

```bash
# Version Control
git, gh, lazygit, git-lfs

# Search & Navigation
rg, fzf, fd, zoxide

# File Operations
bat, jq, rsync, unzip, tar

# Development
docker, lazydocker, tmux, neovim

# Languages
bun, cargo, go, node, npm, uv

# Shell Enhancement
zsh, atuin (history), direnv

# AI Assistant
claude, opencode

# Monitoring & Debug
btop, lsof, strace, netcat, dig

# Code Analysis
sg (ast-grep)
```

---

## 📦 Installation Size Estimate

```
Base system packages:    ~100 MB
Shell environment:       ~50 MB
Modern CLI tools:        ~200 MB
Language runtimes:       ~1.5 GB
  - Rust (nightly):      ~500 MB
  - Node.js:             ~300 MB
  - Bun:                 ~100 MB
  - Go:                  ~400 MB
  - Python/uv:           ~200 MB
Enhanced CLI:            ~50 MB
AI agents:               ~100 MB
Optional utilities:      ~100 MB (if all installed)

TOTAL:                   ~2-4 GB
```

Compare to ACFS original: 5-10 GB

---

## ⏱️ Installation Time Breakdown

```
Phase 1: Base packages           2-3 min
Phase 2: Shell environment       2-3 min
Phase 3: Modern CLI tools        3-5 min
Phase 4: SSH config              <1 min
Phase 5: Language runtimes       5-10 min
Phase 6: Enhanced CLI            2-3 min
Phase 7: AI agents               2-3 min
Phase 8: Optional utilities      Variable
Phase 9: Workspace setup         <1 min

TOTAL:                           15-30 min
```

Compare to ACFS original: 30-60 minutes

---

## 🎯 Use Cases

**Perfect for:**
- ✅ Individual developers
- ✅ Simple AI-assisted coding
- ✅ Learning Claude Code
- ✅ Lightweight development environments
- ✅ Quick VM/container setups

**Not suitable for:**
- ❌ Multi-agent orchestration
- ❌ Advanced agent workflows
- ❌ Production infrastructure
- ❌ Complex CI/CD pipelines
- ❌ Team collaboration features

For those use cases, use the full ACFS setup instead.

---

## 📚 Learn More

- Installation guide: `SIMPLIFIED-SETUP-README.md`
- Manifest file: `simplified-setup.yaml`
- Install script: `simplified-install.sh`
