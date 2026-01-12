# PLAN TO CREATE ACFS

## Agentic Coding Flywheel Setup - Comprehensive Implementation Plan

---

## Executive Summary

**ACFS** (Agentic Coding Flywheel Setup) is a "Rails installer" for agentic engineering - an end-to-end bootstrapper that transforms motivated beginners with zero Linux knowledge into fully-armed agentic engineers in approximately 10 minutes.

### Core Value Proposition

A beginner with a credit card and a laptop can:
1. Visit a beautiful wizard website
2. Follow step-by-step instructions to rent a VPS
3. Paste **one curl|bash command**
4. Type `onboard` and learn the workflow
5. Start vibe coding with AI agents immediately

### What Makes This a "Flywheel"

The installed toolstack creates a compounding loop:
1. **NTM** orchestrates multiple agents in parallel
2. **Agent Mail** provides coordination fabric (identities, inbox, leases)
3. **UBS** flags bugs early with minimal friction
4. **CASS** indexes all agent sessions for unified search
5. **CM** transforms sessions into procedural memory
6. **BV** provides task visibility via Beads
7. **CAAM** enables instant auth switching
8. **SLB** adds optional guardrails for dangerous commands

More agents → more sessions → better memory → better coordination → safer speed → better output → more sessions.

---

## Part 1: The User Journey (Golden Path)

### The 10-Minute Journey

This is the exact flow ACFS must nail:

| Step | User Action | ACFS Responsibility |
|------|-------------|---------------------|
| 1 | Choose laptop OS (Mac/Windows) | Show appropriate terminal/SSH instructions |
| 2 | Install a good terminal | Link to Ghostty/WezTerm (Mac) or Windows Terminal |
| 3 | Generate SSH key | Provide copy-paste command |
| 4 | Rent a VPS (~$40-56/mo) | Guide through OVH/Contabo (not Hetzner - new accounts have waiting period) |
| 5 | Choose Ubuntu 25.x image | Highlight exact selection |
| 6 | Paste SSH public key in provider UI | Screenshot guidance |
| 7 | SSH into server | Copy-paste command |
| 8 | Paste ACFS one-liner | The magic moment |
| 9 | Reconnect as ubuntu | If was root |
| 10 | Type `onboard` | Interactive tutorial begins |

---

## Part 2: Product Architecture

ACFS consists of **three products in one repo**:

### A) Website Wizard (apps/web/)

**Tech Stack:**
- **Framework:** Next.js 16 App Router
- **Runtime:** Bun
- **Hosting:** Vercel + Cloudflare (cost optimization)
- **State:** URL params + localStorage (no backend)

**Design Principles:**
- One action per screen
- Copy button on every command
- "I did it" checkbox gates "Next"
- Collapsible troubleshooting sections

### B) One-Liner Installer (install.sh)

**Contract:**
- Works when run as `root` (fresh VPS)
- Works when run as `ubuntu` with sudo
- Safe to run twice (idempotent)
- Handles connection drops + re-runs

**Phases:**
1. Preflight + confirm OS
2. Create/normalize `ubuntu` user + sudoers
3. Base packages (apt)
4. Shell (zsh + oh-my-zsh + p10k + plugins)
5. Dev toolchain (bun, uv, rust, go, tmux, rg, ast-grep, etc.)
6. Agent stack (claude/codex/gemini CLIs + aliases)
7. Flywheel stack (ntm, slb, ubs, cass, cm, bv, caam, mcp_agent_mail)
8. Post-install UX (onboard + doctor + summary)

**Checkpointing:**
- Progress written to `/var/log/acfs/install.log`
- State stored in `~/.acfs/state.json` with completed phases
- Re-runs skip completed phases

### C) Onboarding TUI (onboard)

**Purpose:** Interactive habit installation, not documentation.

**7 Missions:**
0. Welcome + what you now have
1. Linux navigation in 3 minutes
2. SSH and persistence (why tmux matters)
3. tmux basics (attach/detach/panes)
4. Your agent commands (cc/cod/gmi + login)
5. NTM as command center
6. Show NTM command palette prompts
7. The flywheel loop (the complete workflow)

---

## Part 3: Product Design Principles

### Non-Negotiables

1. **"No jargon until after success"**
   - Every step reads: "Do this" → "You should see this" → "If not, click here"

2. **Single action per screen**
   - One button or one command with Copy button

3. **Always include a "verify" micro-step**
   - After SSH keygen: `ls ~/.ssh` → confirm `id_ed25519.pub` exists

4. **Idempotent installer, resumable by default**
   - Handle: closed terminals, lost connections, paste twice, run as root accidentally

5. **Trust through visibility**
   - Show what you're doing
   - Log everything
   - Offer `--dry-run` mode

---

## Part 4: The VPS Target Environment

### Final State

| Aspect | Value |
|--------|-------|
| User | `ubuntu` |
| Home | `/home/ubuntu` |
| Shell | zsh |
| Sudo | Passwordless (vibe mode) |
| Workspace | `/data/projects` |

### Filesystem Layout

```
/home/ubuntu/
├── .acfs/                  # ACFS-managed configs
│   ├── zsh/
│   │   └── acfs.zshrc
│   ├── tmux/
│   │   └── tmux.conf
│   ├── bin/
│   │   ├── onboard
│   │   ├── acfs
│   │   └── acfs-doctor
│   ├── docs/
│   │   └── ntm/
│   │       └── command_palette.md
│   ├── logs/
│   │   └── install.<timestamp>.log
│   └── state.json
├── .zshrc                  # Tiny loader for acfs.zshrc
├── .zshrc.local            # User overrides
├── .p10k.zsh               # Powerlevel10k config
├── Development/
├── Projects/
└── mcp_agent_mail/         # Agent Mail installation

/data/
└── projects/               # Primary workspace
```

### Shell Aliases (Agent Shortcuts)

```bash
# Coding agents (dangerously enabled for vibe mode)
alias cc='NODE_OPTIONS="--max-old-space-size=32768" claude --dangerously-skip-permissions'
alias cod='codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.2-codex -c model_reasoning_effort="xhigh" -c model_reasoning_summary_format=experimental --enable web_search_request'
alias gmi='gemini --yolo --model gemini-3-pro-preview'

# Flywheel stack shortcuts
alias am='cd ~/mcp_agent_mail && scripts/run_server_with_token.sh'
alias update='sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y'
alias uca='claude update && bun install -g @openai/codex@latest && bun install -g @google/gemini-cli@latest'
```

---

## Part 5: Module Manifest

The manifest (`acfs.manifest.yaml`) is the **single source of truth** for all tools installed.

### Structure

```yaml
version: 1
name: agentic_coding_flywheel_setup
id: acfs

defaults:
  user: ubuntu
  workspace_root: /data/projects
  mode: vibe

modules:
  - id: base.system
    description: Base packages + sane defaults
    install: [...]
    verify: [...]

  - id: stack.ntm
    description: Named tmux manager (agent cockpit)
    install: [...]
    verify: [...]
```

### Module Categories

1. **base.** - System fundamentals (curl, git, build-essential)
2. **users.** - User account setup (ubuntu, sudoers, SSH)
3. **shell.** - Zsh, oh-my-zsh, p10k, plugins
4. **cli.** - Modern CLI tools (lsd, bat, fzf, etc.)
5. **lang.** - Language runtimes (bun, uv, rust, go)
6. **tools.** - Dev tools (atuin, ast-grep, tmux)
7. **db.** - Databases (postgres18)
8. **cloud.** - Cloud CLIs (vault, wrangler, supabase, vercel)
9. **agents.** - Coding agent CLIs (claude, codex, gemini)
10. **stack.** - Dicklesworthstone stack (all 8 tools)

---

## Part 6: The Dicklesworthstone Stack

### All 8 Tools

| Tool | Command | Purpose | Key Feature |
|------|---------|---------|-------------|
| **NTM** | `ntm` | Named Tmux Manager | Agent cockpit with spawn/send/broadcast |
| **MCP Agent Mail** | `am` | Agent coordination | Identities, inbox/outbox, file leases |
| **Ultimate Bug Scanner** | `ubs` | Bug scanning | 1000+ patterns, easy-mode guardrails |
| **Beads Viewer** | `bv` | Task management | Kanban, graph, insights TUI |
| **CASS** | `cass` | Session search | Unified agent history indexing |
| **CASS Memory** | `cm` | Procedural memory | Episodic → working → procedural |
| **CAAM** | `caam` | Auth switching | Sub-100ms account swap |
| **SLB** | `slb` | Guardrails | Two-person rule for dangerous commands |

### Installation Pattern

Each tool has:
1. Official one-liner installer
2. Easy-mode flag where applicable
3. Verify command(s)
4. Alias or PATH addition

Example:
```yaml
- id: stack.mcp_agent_mail
  description: Like gmail for coding agents
  install:
    - |
      curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail/main/scripts/install.sh?$(date +%s)" | bash -s -- --yes
  verify:
    - command -v am
    - curl -fsS http://127.0.0.1:8765/health || true
```

---

## Part 7: Website Implementation

### Route Structure

```
apps/web/
├── app/
│   ├── layout.tsx
│   ├── page.tsx                    # Landing/Welcome
│   └── wizard/
│       ├── layout.tsx              # Stepper wrapper
│       ├── os/page.tsx             # Step 1: Mac/Windows
│       ├── terminal/page.tsx       # Step 2: Install terminal
│       ├── ssh-key/page.tsx        # Step 3: Generate SSH key
│       ├── vps/page.tsx            # Step 4: Rent VPS
│       ├── create-vps/page.tsx     # Step 5: Create + attach key
│       ├── connect/page.tsx        # Step 6: SSH in
│       ├── install/page.tsx        # Step 7: Paste one-liner
│       ├── reconnect/page.tsx      # Step 8: Reconnect as ubuntu
│       ├── status/page.tsx         # Step 9: ACFS Status Check
│       └── onboard/page.tsx        # Step 10: Run onboard
├── components/
│   ├── Stepper.tsx
│   ├── CommandCard.tsx             # OS-aware command with copy
│   ├── ProviderChooser.tsx         # VPS provider cards
│   ├── Checklist.tsx               # Status check display
│   └── PasteDoctorJson.tsx         # Optional auto-check
└── lib/
    ├── wizardSteps.ts              # Step definitions
    ├── doctorChecks.ts             # Check IDs for status page
    └── manifest.ts                 # Manifest types
```

### Key Components

**CommandCard:**
- OS-aware command rendering
- Copy button
- "I ran this" checkbox

**ProviderChooser:**
- Cards for OVH, Contabo, Other
- Expandable guidance per provider

**Stepper:**
- Left sidebar showing all steps
- Current step highlighted
- Completed steps checkmarked

---

## Part 8: acfs doctor Specification

### Purpose
Single command to verify installation is complete and working.

### Output Format

```
ACFS Doctor v0.1.0
User: ubuntu ✅
Mode: vibe (passwordless sudo: enabled) ✅
OS: Ubuntu 25.x ✅
Workspace: /data/projects ✅

Shell
  PASS ✅ zsh installed (zsh 5.x)
  PASS ✅ oh-my-zsh installed
  PASS ✅ powerlevel10k installed
  ...

Core tools
  PASS ✅ bun (x.y.z)
  PASS ✅ uv (x.y.z)
  ...

Agents
  PASS ✅ claude (available)
  PASS ✅ codex (available)
  PASS ✅ gemini (available)
  PASS ✅ aliases: cc cod gmi

Cloud/DB
  PASS ✅ vault (x.y.z)
  PASS ✅ postgres (psql 18.x)
  ...

Dicklesworthstone stack
  PASS ✅ ntm (available)
  PASS ✅ slb (available)
  ...

Next: run `onboard`
```

### Exit Codes
- `0` = all PASS (warnings allowed)
- `1` = one or more FAIL
- `2` = doctor itself crashed

### JSON Mode

`acfs doctor --json` outputs structured data:

```json
{
  "acfs_version": "0.1.0",
  "timestamp": "2025-12-19T12:34:56Z",
  "mode": "vibe",
  "user": "ubuntu",
  "checks": [
    {
      "id": "identity.user_is_ubuntu",
      "label": "Logged in as ubuntu",
      "status": "pass",
      "details": "whoami=ubuntu",
      "fix": null
    }
  ],
  "summary": { "pass": 34, "warn": 1, "fail": 0 }
}
```

### Check IDs

Stable IDs for mapping to website checklist:
- `identity.user_is_ubuntu`
- `identity.passwordless_sudo`
- `workspace.data_projects`
- `shell.zsh`, `shell.ohmyzsh`, `shell.p10k`
- `shell.plugins.*`
- `tool.bun`, `tool.uv`, `tool.cargo`, `tool.go`, `tool.tmux`, `tool.rg`, `tool.sg`
- `agent.claude`, `agent.codex`, `agent.gemini`
- `agent.alias.cc`, `agent.alias.cod`, `agent.alias.gmi`
- `cloud.vault`, `cloud.postgres18`, `cloud.wrangler`, `cloud.supabase`, `cloud.vercel`
- `stack.ntm`, `stack.slb`, `stack.ubs`, `stack.bv`, `stack.cass`, `stack.cm`, `stack.caam`, `stack.mcp_agent_mail`

---

## Part 9: Implementation Milestones

### Milestone 1: MVP ("It works for real people")

**Deliverables:**
- Website wizard skeleton (Mac + Windows, one provider)
- `install.sh` that:
  - Creates `ubuntu` user
  - Installs zsh + shell config via `~/.acfs`
  - Installs tmux + ntm
  - Installs cc/cod/gmi dependencies
  - Installs basic `onboard`

**Acceptance:**
- A nontechnical user can get from VPS purchase → `onboard` without help

### Milestone 2: Full Flywheel Stack

**Deliverables:**
- All 8 Dicklesworthstone tools installed and configured
- `acfs doctor` shows green across the board

### Milestone 3: Polished Onboarding TUI

**Deliverables:**
- Interactive missions
- "Send this prompt to all agents" integration
- Vendored NTM command palette viewer

**Acceptance:**
- A beginner can successfully spawn agents and run first multi-agent workflow

### Milestone 4: Provider Expansion + "I'm Stuck" Excellence

**Deliverables:**
- Provider-specific screenshot guides (OVH/Contabo/etc)
- Error-driven help (SSH permission denied, host key, firewall)
- "Already have a VPS" and "Local-only" branches

**Acceptance:**
- Support burden drops because wizard answers top 20 failure modes

### Milestone 5: CI You Can Trust

**Deliverables:**
- GitHub Actions that:
  - Spins Ubuntu VM
  - Runs ACFS installer
  - Verifies every module
  - Runs shellcheck on scripts
- `--dry-run` mode

### Milestone 6: Production Polish

**Deliverables:**
- Cloudflare caching rules
- Analytics
- SEO optimization
- Performance optimization

---

## Part 10: Hosting Strategy (Cheap but Good)

### Vercel Side
- Deploy Next.js site to Vercel
- Use Bun runtime support
- Free tier should suffice initially

### Cloudflare Side (Cost Control)
- Cloudflare DNS (free)
- Aggressive caching for static wizard pages
- Cloudflare Analytics (free)
- Optional: Cloudflare Turnstile for forms (no CAPTCHA cost)

---

## Part 11: Supply Chain & Trust

Even for curl|bash, design responsibly:

### Website Transparency
- Show "What this script changes"
- Show "Where logs go"
- Show "How to uninstall/revert"

### Installer Flags
- `--dry-run` - prints plan without changing anything
- `--print` - prints exact scripts/versions it will fetch
- Optional checksum verification for tool installers

---

## Part 12: The Clean Canonical zshrc

Located at `~/.acfs/zsh/acfs.zshrc`

Key features:
- No duplicate PATH blocks
- No duplicate aliases
- Safe `chpwd` hook instead of overriding `cd()`
- Proper init ordering (atuin path before init)
- All tools only aliased if present
- Local overrides via `~/.zshrc.local`

The main `~/.zshrc` becomes a tiny loader:
```zsh
# ACFS loader
source "$HOME/.acfs/zsh/acfs.zshrc"

# user overrides live here forever
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
```

---

## Part 13: Post-Install Magic

### "Start a project for me"

After `onboard`, offer:
```bash
ntm spawn myproject --cc=2 --cod=1 --gmi=1
```

This makes the user feel: "I just became an agentic engineer."

### Quick Health Check

Type `acfs doctor` anytime to verify everything is working.

### Update All

```bash
acfs update
```
- Updates apt packages
- Updates bun globals
- Optionally re-runs tool installers

---

## Summary: Why This Works

1. **Beginner-obsessed UX** - Every decision optimized for "I have no idea what I'm doing"
2. **One-liner magic** - The entire complexity hidden behind a single paste
3. **Genuine flywheel** - Tools reinforce each other, not just a random toolbox
4. **Trust through visibility** - Even in "vibe mode", users can see what's happening
5. **Resumable by default** - Handle real-world failure modes gracefully
6. **Manifest-driven** - Single source of truth makes updates tractable

The goal is to make agentic engineering accessible to anyone motivated enough to rent a VPS and follow instructions. ACFS is the bridge from "I want to try this AI coding thing" to "I'm running multiple agents coordinating on my project."
