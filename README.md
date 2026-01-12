# Agentic Coding Flywheel Setup (ACFS)

![Version](https://img.shields.io/badge/Version-0.5.0-bd93f9?style=for-the-badge)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%2025.10-6272a4?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-50fa7b?style=for-the-badge)
![Shell](https://img.shields.io/badge/Shell-Bash-ff79c6?style=for-the-badge)

<p align="center">
  <strong>🌐 <a href="https://agent-flywheel.com">agent-flywheel.com</a></strong> — Interactive setup wizard for beginners
</p>

> **From zero to fully-configured agentic coding VPS in 30 minutes.**
> A complete bootstrapping system that transforms a fresh Ubuntu VPS into a professional AI-powered development environment.

<div align="center" style="margin: 1.2em 0;">
  <table>
    <tr>
      <td align="center" style="padding: 8px;">
        <strong>The Vision</strong><br/>
        <sub>Beginner with laptop → Wizard → VPS → Agents coding for you</sub>
      </td>
    </tr>
  </table>
</div>

### Quick Install

```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh?$(date +%s)" | bash -s -- --yes --mode vibe
```

The installer is **idempotent**—if interrupted, simply re-run it. It will automatically resume from the last completed phase without prompts.

> **Production environments:** For stable, reproducible installs, pin to a tagged release or specific commit:
> ```bash
> # Preferred: use a tagged release (e.g., v0.5.0)
> ACFS_REF=v0.5.0 curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/v0.5.0/install.sh" | bash -s -- --yes --mode vibe
>
> # Alternative: pin to a specific commit SHA
> ACFS_REF=abc1234 curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/abc1234/install.sh" | bash -s -- --yes --mode vibe
> ```
> Tagged releases are tested and stable. Setting `ACFS_REF` ensures all fetched scripts use the same version.

---

## TL;DR

**ACFS** is a complete system for bootstrapping agentic coding environments:

**Why you'd care:**
- **Zero to Hero:** Takes complete beginners from "I have a laptop" to "I have Claude/Codex/Gemini agents writing code for me on a VPS"
- **One-Liner Magic:** A single `curl | bash` command installs 30+ tools, configures everything, and sets up three AI coding agents
- **Vibe Mode:** Pre-configured for maximum velocity—passwordless sudo, dangerous agent flags enabled, optimized shell environment
- **Battle-Tested Stack:** Includes the complete Dicklesworthstone stack (10 tools + utilities) for agent orchestration, coordination, and safety

**What you get:**
- Modern shell (zsh + oh-my-zsh + powerlevel10k)
- All language runtimes (bun, uv/Python, Rust, Go)
- Three AI coding agents (Claude Code, Codex CLI, Gemini CLI)
- Agent coordination tools (NTM, MCP Agent Mail, SLB)
- Cloud CLIs (Vault, Wrangler, Supabase, Vercel)
- And 20+ more developer tools

---

## The ACFS Experience

```mermaid
graph LR
    %%{init: {'theme': 'base', 'themeVariables': { 'primaryColor': '#e8f5e9', 'lineColor': '#90a4ae'}}}%%

    subgraph user ["User's Machine"]
        LAPTOP["Laptop"]
        BROWSER["Browser"]
    end

    subgraph wizard ["Wizard Website"]
        STEPS["13-Step Guide"]
    end

    subgraph vps ["Fresh VPS"]
        UBUNTU["Ubuntu 25.10"]
        INSTALLER["install.sh"]
        CONFIGURED["Configured VPS"]
    end

    subgraph agents ["AI Agents"]
        CLAUDE["Claude Code"]
        CODEX["Codex CLI"]
        GEMINI["Gemini CLI"]
    end

    LAPTOP --> BROWSER
    BROWSER --> STEPS
    STEPS -->|SSH| UBUNTU
    UBUNTU --> INSTALLER
    INSTALLER --> CONFIGURED
    CONFIGURED --> CLAUDE
    CONFIGURED --> CODEX
    CONFIGURED --> GEMINI

    classDef user fill:#e3f2fd,stroke:#90caf9,stroke-width:2px
    classDef wizard fill:#fff8e1,stroke:#ffcc80,stroke-width:2px
    classDef vps fill:#f3e5f5,stroke:#ce93d8,stroke-width:2px
    classDef agent fill:#e8f5e9,stroke:#a5d6a7,stroke-width:2px

    class LAPTOP,BROWSER user
    class STEPS wizard
    class UBUNTU,INSTALLER,CONFIGURED vps
    class CLAUDE,CODEX,GEMINI agent
```

### For Beginners
ACFS includes a **step-by-step wizard website** at [agent-flywheel.com](https://agent-flywheel.com) that guides complete beginners through:
1. Installing a terminal on their local machine
2. Generating SSH keys (for secure access later)
3. Renting a VPS from providers like OVH or Contabo
4. Connecting via SSH with a password (initial setup)
5. Running the installer (which sets up key-based access)
6. Reconnecting securely with your SSH key
7. Starting to code with AI agents

### For Developers
ACFS is a **one-liner** that transforms any fresh Ubuntu VPS into a fully-configured development environment with modern tooling and three AI coding agents ready to go.

### For Teams
ACFS provides a **reproducible, idempotent** setup that ensures every team member's VPS environment is identical—eliminating "works on my machine" for agentic workflows.

---

## Architecture & Design

ACFS is built around a **single source of truth**: the manifest file. Everything else—the installer scripts, doctor checks, website content—derives from this central definition. This architecture ensures consistency and makes the system easy to extend.

### One-Page System Data Flow

```mermaid
flowchart TB
  %% User and website
  subgraph U["User (local machine)"]
    Browser["Browser"]
    Terminal["Terminal / SSH client"]
  end

  subgraph W["Wizard Website (Next.js 16) — apps/web"]
    Wizard["Wizard UI (/wizard/*)"]
    InstallRoute["GET /install (302 redirect to raw install.sh)"]
    WebState["State: URL params + localStorage"]
  end

  %% Repo sources
  subgraph R["Repo (source)"]
    Manifest["acfs.manifest.yaml<br/>Modules + install + verify + deps"]
    Generator["packages/manifest<br/>Parser (Zod) + generate.ts"]
    Generated["scripts/generated/* (reference)<br/>category installers + doctor_checks.sh"]
    Installer["install.sh (production one-liner)"]
    Lib["scripts/lib/*<br/>security / doctor / update / services-setup"]
    Configs["acfs/*<br/>zshrc + tmux.conf + onboard lessons"]
    Checksums["checksums.yaml<br/>sha256 for upstream installers"]
    Tests["tests/vm/test_install_ubuntu.sh<br/>Docker integration test"]
  end

  %% Target VPS
  subgraph V["Target VPS (Ubuntu 25.10, auto-upgraded)"]
    Run["Run install.sh"]
    Verify["Verified upstream installers<br/>(security.sh + checksums.yaml)"]
    AcfsHome["~/.acfs/<br/>configs + scripts + state.json"]
    Commands["Commands<br/>acfs doctor / acfs update / acfs services-setup / onboard"]
    Tools["Installed tools<br/>bun/uv/rust/go + tmux/rg/gh + vault + ..."]
    Agents["Agent CLIs<br/>claude / codex / gemini"]
    Stack["Stack tools<br/>ntm / mcp_agent_mail / ubs / bv / cass / cm / caam / slb / dcg / ru"]
  end

  %% Website guidance flow
  Browser --> Wizard
  Wizard --> WebState
  Wizard --> InstallRoute
  InstallRoute -->|redirects to| Installer

  %% How users fetch/run the installer
  Terminal -->|curl / bash| Installer
  Terminal -->|SSH| Run

  %% Manifest-driven generation (reference today)
  Manifest --> Generator --> Generated
  Generated -.->|planned: install.sh calls generated install_all.sh| Installer

  %% Installer composition
  Lib --> Installer
  Configs --> Installer
  Checksums --> Installer
  Tests -->|validates| Installer

  %% VPS install results
  Installer --> Run
  Run --> Verify
  Verify --> Tools
  Verify --> Agents
  Verify --> Stack
  Run --> AcfsHome --> Commands
```

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            SOURCE OF TRUTH                                   │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  acfs.manifest.yaml                                                  │    │
│  │  Tool Definitions • Install Commands • Verification Logic           │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    ▼                                   ▼
┌───────────────────────────────────┐   ┌───────────────────────────────────┐
│        CODE GENERATION            │   │        WIZARD WEBSITE             │
│  ┌─────────────────────────────┐  │   │  ┌─────────────────────────────┐  │
│  │ TypeScript Parser (Zod)     │  │   │  │ apps/web/ (Next.js 16)      │  │
│  │ generate.ts                 │  │   │  │ agent-flywheel.com          │  │
│  └─────────────────────────────┘  │   │  └─────────────────────────────┘  │
└───────────────────────────────────┘   └───────────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                     GENERATED OUTPUTS (REFERENCE)                          │
│  ┌────────────────────┐  ┌────────────────────┐  ┌────────────────────┐   │
│  │ scripts/generated/ │  │ doctor_checks.sh   │  │ install_all.sh     │   │
│  │ 11 Category Scripts│  │ Verification Logic │  │ Master Installer   │   │
│  └────────────────────┘  └────────────────────┘  └────────────────────┘   │
└───────────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                            INSTALLER                                       │
│  install.sh + scripts/lib/*.sh + checksums.yaml (SHA256 verification)     │
│  (scripts/generated/* are sourced; execution is feature-flagged)            │
└───────────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                           TARGET VPS                                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ 30+ Tools    │  │ zsh + p10k   │  │ AI Agents    │  │ ~/.acfs/     │   │
│  │ Installed    │  │ Shell Config │  │ Claude/Codex │  │ Configurations│  │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘   │
└───────────────────────────────────────────────────────────────────────────┘
```

### Why This Architecture?

**Single Source of Truth**: The manifest file (`acfs.manifest.yaml`) defines every tool—its name, description, install commands, and verification logic. When you add or edit a tool in the manifest, the generator automatically updates the generated scripts and manifest-derived checks. The production one-liner installer (`install.sh`) is still hand-written today, so behavior changes may also require updating `install.sh` until full migration.

**TypeScript + Zod Validation**: The manifest parser uses Zod schemas to validate the YAML at parse time. Typos, missing fields, and structural errors are caught immediately during generation—not at runtime on a user's VPS when the installer fails halfway through.

**Generated Scripts**: Rather than hand-maintaining 11 category installer scripts and keeping them synchronized, the generator produces them from the manifest. This means:
- A consistent, auditable view of manifest-defined install logic (some modules intentionally emit TODOs)
- Consistent error handling and logging across all modules
- A clear path toward future installer integration

### Components

| Component | Path | Technology | Purpose |
|-----------|------|------------|---------|
| **Manifest** | `acfs.manifest.yaml` | YAML | Single source of truth for all tools |
| **Generator** | `packages/manifest/src/generate.ts` | TypeScript/Bun | Produces installer scripts from manifest |
| **Website** | `apps/web/` | Next.js 16 + Tailwind 4 | Step-by-step wizard for beginners |
| **Installer** | `install.sh` | Bash | One-liner bootstrap script |
| **Lib Scripts** | `scripts/lib/` | Bash | Modular installer functions |
| **Generated Scripts** | `scripts/generated/` | Bash | Auto-generated category installers (sourced by `install.sh`; execution is feature-flagged) |
| **Configs** | `acfs/` | Shell/Tmux configs | Files deployed to `~/.acfs/` |
| **Onboarding** | `acfs/onboard/` | Bash + Markdown | Interactive tutorial system |
| **Checksums** | `checksums.yaml` | YAML | SHA256 hashes for upstream installers |

---

## The Manifest System

`acfs.manifest.yaml` is the **single source of truth** for all tools installed by ACFS. It defines what gets installed, how to install it, and how to verify the installation worked.

### Manifest Structure

```yaml
version: "1.0"
meta:
  name: "ACFS"
  description: "Agentic Coding Flywheel Setup"
  version: "0.1.0"

modules:
  base.system:
    description: "Base packages + sane defaults"
    category: base
    install:
      - sudo apt-get update -y
      - sudo apt-get install -y curl git ca-certificates unzip tar xz-utils jq build-essential
    verify:
      - curl --version
      - git --version
      - jq --version

  agents.claude:
    description: "Claude Code"
    category: agents
    install:
      - "Install claude code via official method"
    verify:
      - claude --version || claude --help
```

Each module specifies:
- **description**: Human-readable name
- **category**: Grouping for installer organization (base, shell, cli, lang, tools, db, cloud, agents, stack, acfs)
- **install**: Commands to run (or descriptions that become TODOs)
- **verify**: Commands that must succeed to confirm installation

### The Generator Pipeline

The TypeScript generator (`packages/manifest/src/generate.ts`) reads the manifest and produces:

1. **Category Scripts** (`scripts/generated/install_base.sh`, `install_agents.sh`, etc.)
   - One script per category with individual install functions
   - Consistent logging and error handling
   - Verification checks after each module

2. **Doctor Checks** (`scripts/generated/doctor_checks.sh`)
   - All verify commands extracted into a runnable health check
   - Tab-delimited format (to safely handle `||` in shell commands)
   - Reports pass/fail/skip for each module

3. **Master Installer** (`scripts/generated/install_all.sh`)
   - Sources all category scripts
   - Runs them in dependency order
   - Single entry point for running the generated installers

> Note: The production one-liner installer (`install.sh`) defaults to the legacy implementations; generated installers are sourced and can be enabled per-category via feature flags during migration.

To regenerate after manifest changes:

```bash
cd packages/manifest
bun run generate        # Generate scripts
bun run generate:dry    # Preview without writing
```

### Why TypeScript for Code Generation?

Shell can parse YAML with `yq`, but TypeScript + Zod offers:
- **Type safety**: The parser knows the exact shape of a manifest
- **Validation**: Zod catches malformed YAML with descriptive errors
- **Transformation**: Complex logic (sorting by dependencies, escaping) is natural in TypeScript
- **Consistency**: All generated code follows the same patterns

The generator itself is ~400 lines of TypeScript. The generated output is ~1000 lines of Bash across 13 files. The trade-off is clearly in favor of maintaining the generator.

---

## Security Verification

ACFS downloads and executes installer scripts from the internet. This is inherently risky—a compromised upstream could inject malicious code. The security verification system mitigates this risk.

### How It Works

The `checksums.yaml` file contains SHA256 hashes for all upstream installer scripts:

```yaml
# checksums.yaml
installers:
  bun:
    url: "https://bun.sh/install"
    sha256: "a1b2c3d4..."

  rust:
    url: "https://sh.rustup.rs"
    sha256: "e5f6a7b8..."
```

The security library (`scripts/lib/security.sh`) provides:

1. **HTTPS Enforcement**: All installer URLs must use HTTPS. Non-HTTPS URLs fail immediately.

2. **Checksum Verification**: Before executing a downloaded script, the system:
   - Downloads the content to memory
   - Calculates the SHA256 hash
   - Compares against the stored hash
   - Only executes if they match

3. **Verification Modes**:
   ```bash
   ./scripts/lib/security.sh --print              # List all upstream URLs
   ./scripts/lib/security.sh --verify             # Verify all against saved checksums
   ./scripts/lib/security.sh --update-checksums   # Generate new checksums.yaml
   ./scripts/lib/security.sh --checksum URL       # Calculate SHA256 of any URL
   ```

### When Checksums Fail

A checksum mismatch can mean:
1. **Normal update**: The upstream maintainer released a new version
2. **Potential compromise**: Someone modified the script maliciously

The verification report distinguishes these cases:
- If multiple checksums fail simultaneously, investigate before updating
- If a single checksum fails after a known release, update is likely safe

To update after verifying a legitimate upstream change:
```bash
./scripts/lib/security.sh --update-checksums > checksums.yaml
git diff checksums.yaml  # Review what changed
git commit -m "chore: update upstream checksums"
```

### Why This Approach?

The `curl | bash` pattern is controversial but practical. ACFS makes it safer by:
- Verifying content before execution (not just transport via HTTPS)
- Making checksums auditable in version control
- Providing tools to detect and investigate changes
- Failing closed (no execution on mismatch)

This is defense in depth—HTTPS protects transport, checksums protect content.

---

## The Installer

The installer is the heart of ACFS—a modular Bash script that transforms a fresh Ubuntu VPS into a fully-configured development environment.

### Usage

```bash
# Full vibe mode (recommended for throwaway VPS)
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh?$(date +%s)" | bash -s -- --yes --mode vibe

# Interactive mode (asks for confirmation)
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh" | bash

# Safe mode (no passwordless sudo, agent confirmations enabled)
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh" | bash -s -- --mode safe
```

### Installer Modes

| Mode | Passwordless Sudo | Agent Flags | Best For |
|------|-------------------|-------------|----------|
| **vibe** | Yes | `--dangerously-skip-permissions` | Throwaway VPS, maximum velocity |
| **safe** | No | Standard confirmations | Production-like environments |

### Installation Phases

```mermaid
graph TD
    %%{init: {'theme': 'base', 'themeVariables': { 'primaryColor': '#e8f5e9', 'lineColor': '#90a4ae'}}}%%

    A["Phase 1: User Normalization<br/><small>Create ubuntu user, migrate SSH keys</small>"]
    B["Phase 2: APT Packages<br/><small>Essential system packages</small>"]
    C["Phase 3: Shell Setup<br/><small>zsh, oh-my-zsh, powerlevel10k</small>"]
    D["Phase 4: CLI Tools<br/><small>ripgrep, fzf, lazygit, etc.</small>"]
    E["Phase 5: Language Runtimes<br/><small>bun, uv, rust, go</small>"]
    F["Phase 6: AI Agents<br/><small>claude, codex, gemini</small>"]
    G["Phase 7: Cloud Tools<br/><small>vault, wrangler, supabase, vercel</small>"]
    H["Phase 8: Dicklesworthstone Stack<br/><small>ntm, dcg, ru, ubs, mcp_agent_mail, etc.</small>"]
    I["Phase 9: Configuration<br/><small>Deploy acfs.zshrc, tmux.conf</small>"]
    J["Phase 10: Verification<br/><small>acfs doctor</small>"]

    A --> B --> C --> D --> E --> F --> G --> H --> I --> J

    classDef phase fill:#e8f5e9,stroke:#81c784,stroke-width:2px,color:#2e7d32
    class A,B,C,D,E,F,G,H,I,J phase
```

### Key Properties

| Property | Description |
|----------|-------------|
| **Idempotent** | Safe to re-run; skips already-installed tools |
| **Checkpointed** | Phases resume automatically from `~/.acfs/state.json` |
| **Pre-flight validated** | Run `scripts/preflight.sh` to catch issues before install |
| **Logged** | Colored output with progress indicators |
| **Modular** | Each category is a separate sourceable script |

### Resume Capability

The installer tracks progress in `~/.acfs/state.json`. If interrupted:
- Re-run the same command—it resumes from the last completed phase
- No prompts or confirmations needed (with `--yes`)
- Already-installed tools are detected and skipped

To force a fresh reinstall of all tools:
```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh" | bash -s -- --yes --mode vibe --force-reinstall
```

### Pre-Flight Check

Before running the full installer, validate your system:
```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/scripts/preflight.sh" | bash
```

This checks:
- OS compatibility (Ubuntu 22.04+; installer upgrades to 25.10)
- Architecture (x86_64 or ARM64)
- Memory and disk space
- Network connectivity to required URLs
- APT lock status
- Potential conflicts (nvm, pyenv, existing ACFS)

### Console Output

The installer uses semantic colors for progress visibility:

```bash
[1/8] Installing essential packages...     # Blue: progress steps
    Installing zsh, git, curl...           # Gray: details
⚠️  May take a few minutes                 # Yellow: warnings
✖ Failed to install package               # Red: errors
✔ Shell setup complete                    # Green: success
```

### Automatic Ubuntu Upgrade

ACFS automatically upgrades Ubuntu to version **25.10** before installation when running on older versions. This ensures compatibility with the latest packages and optimal performance.

**How it works:**
1. Detects your current Ubuntu version
2. Calculates the upgrade path (e.g., 24.04 → 25.04 → 25.10)
3. Performs sequential `do-release-upgrade` operations
4. Reboots after each upgrade (handled automatically)
5. Resumes via systemd service after reboot
6. Continues ACFS installation once at target version

**Expected timeline:**
- Each version hop takes 30-60 minutes
- Full chain from 24.04 → 25.10 takes 1.5-3 hours
- SSH sessions disconnect during reboots (reconnect to monitor)

**To skip automatic upgrade:**
```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh" | bash -s -- --yes --mode vibe --skip-ubuntu-upgrade
```

**To specify a different target version:**
```bash
# Upgrade only to 25.04 instead of 25.10
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh" | bash -s -- --yes --mode vibe --target-ubuntu=25.04
```

**Monitoring upgrade progress:**
```bash
# Check current status
/var/lib/acfs/check_status.sh

# View upgrade logs
journalctl -u acfs-upgrade-resume -f

# View detailed logs
tail -f /var/log/acfs/upgrade_resume.log
```

**Important notes:**
- Create a VM snapshot before upgrading (recommended but not required)
- Upgrades cannot be undone without restoring from snapshot
- The system will reboot multiple times automatically
- EOL interim releases (like 24.10) may be skipped automatically if they are no longer offered by `do-release-upgrade`
- Reconnect via SSH after each reboot to monitor progress

---

## The Update Command

After installation, keeping tools current is handled by `acfs-update`. It provides a unified interface for updating all installed components.

### Usage

```bash
acfs-update                  # Update apt, runtimes, shell, agents, and cloud CLIs
acfs-update --stack          # Include Dicklesworthstone stack tools
acfs-update --agents-only    # Only update coding agents
acfs-update --runtime-only   # Only update runtimes (bun, rust, uv, go)
acfs-update --dry-run        # Preview changes without making them
acfs-update --yes --quiet    # Automated/CI mode with minimal output
```

### What Gets Updated

| Category | Tools | Method |
|----------|-------|--------|
| **System** | apt packages | `apt update && apt upgrade` |
| **Shell** | OMZ, P10K, plugins | `git pull` on each repo |
| **Shell** | Atuin, Zoxide | Re-run upstream installers |
| **Runtime** | Bun | `bun upgrade` |
| **Runtime** | Rust | `rustup update stable` |
| **Runtime** | uv (Python) | `uv self update` |
| **Runtime** | Go | `apt upgrade` (if apt-managed) |
| **Agents** | Claude Code | `claude update` |
| **Agents** | Codex, Gemini | `bun install -g @latest` |
| **Cloud** | Wrangler, Vercel | `bun install -g @latest` |
| **Cloud** | Supabase | GitHub release tarball (sha256 checksums) |
| **Stack** | ntm, slb, ubs, dcg, ru, etc. | Re-run upstream installers |

### Options

**Category Selection:**
```bash
--apt-only       Only update system packages
--agents-only    Only update coding agents
--cloud-only     Only update cloud CLIs
--shell-only     Only update shell tools (OMZ, P10K, plugins, Atuin, Zoxide)
--runtime-only   Only update runtimes (bun, rust, uv, go)
--stack          Include Dicklesworthstone stack (disabled by default)
```

**Skip Categories:**
```bash
--no-apt         Skip apt updates
--no-agents      Skip agent updates
--no-cloud       Skip cloud CLI updates
--no-shell       Skip shell tool updates
--no-runtime     Skip runtime updates (bun, rust, uv, go)
```

**Behavior:**
```bash
--force            Install missing tools (not just update existing)
--dry-run          Preview changes without making them
--yes, -y          Non-interactive mode (skip prompts)
--quiet, -q        Minimal output (only errors and summary)
--verbose, -v      Show detailed command output
--abort-on-failure Stop on first failure (default: continue)
```

### Logs

Update logs are automatically saved to `~/.acfs/logs/updates/` with timestamps:
```bash
# View most recent log
cat ~/.acfs/logs/updates/$(ls -1t ~/.acfs/logs/updates | head -1)

# Follow a running update
tail -f ~/.acfs/logs/updates/$(ls -1t ~/.acfs/logs/updates | head -1)
```

### Why Separate from the Installer?

The installer transforms a fresh VPS. The update command maintains an existing installation. Separating them allows:
- **Focused updates**: Update just agents without touching system packages
- **Dry-run previews**: See what would change before committing
- **Skip flags**: Temporarily exclude categories that are working fine
- **Stack control**: The full stack reinstallation is opt-in (it's slow)
- **Automated updates**: Run via cron with `--yes --quiet`

---

## ACFS CLI Commands

After installation, the `acfs` command provides a unified interface for managing your environment. Each subcommand is designed to be fast, informative, and scriptable.

### Quick Reference

```bash
acfs info                    # Lightning-fast system overview
acfs cheatsheet              # Discover installed aliases
acfs dashboard generate      # Generate HTML status page
acfs doctor                  # Health checks
acfs newproj                 # Create a new project (TUI or CLI)
acfs update                  # Update all tools
acfs services-setup          # Configure agent credentials
acfs continue                # View upgrade progress after reboot
```

### `acfs newproj` — New Project Wizard

Create a new project directory with ACFS defaults (git init, optional bd, Claude settings, AGENTS.md).
The interactive wizard is recommended for beginners.

Interactive wizard (recommended):
```bash
acfs newproj --interactive
acfs newproj -i
acfs newproj -i myapp         # Prefill project name
```

The wizard guides you through:
- Project naming and location
- Tech stack detection/selection
- Feature selection (bd, Claude settings, AGENTS.md, UBS ignore)
- AGENTS.md customization preview

<details>
<summary><strong>TUI Wizard Screenshots</strong></summary>

**Welcome Screen:**
```
    ╔═══════════════════════════════════════════════════════╗
    ║                                                       ║
    ║      █████╗  ██████╗ ███████╗ ███████╗                ║
    ║     ██╔══██╗██╔════╝ ██╔════╝ ██╔════╝                ║
    ║     ███████║██║      █████╗   ███████╗                ║
    ║     ██╔══██║██║      ██╔══╝   ╚════██║                ║
    ║     ██║  ██║╚██████╗ ██║      ███████║                ║
    ║     ╚═╝  ╚═╝ ╚═════╝ ╚═╝      ╚══════╝                ║
    ║                                                       ║
    ║          Agentic Coding Flywheel Setup                ║
    ║                                                       ║
    ╚═══════════════════════════════════════════════════════╝

This wizard will help you set up a new project with:

  ✓ Project directory structure
  ✓ Git repository initialization
  ✓ AGENTS.md for AI coding assistants
  ✓ Beads issue tracking (optional)
  ✓ Claude Code settings (optional)
```

**Confirmation Screen:**
```
──────────────────── Review & Confirm ────────────────────
                                              Step 7 of 9

Please review your selections before creating the project.

Project Summary
──────────────────────────────────────────────────────────
  Name:       myapp
  Location:   /home/user/projects/myapp
  Tech:       Node.js, TypeScript

Features
──────────────────────────────────────────────────────────
  ✓ Beads tracking
  ✓ Claude Code settings
  ✓ AGENTS.md
  ✓ UBS ignore

Files to Create
──────────────────────────────────────────────────────────
myapp/
├── .git/
├── AGENTS.md
├── .beads/
│   └── beads.db
├── .claude/
│   └── settings.local.json
├── .ubsignore
├── README.md
└── .gitignore

Options:
  [Enter/c]   Create project
  [e]         Edit selections (go back)
  [q/Esc]     Cancel
```

</details>

CLI mode (automation):
```bash
acfs newproj myapp
acfs newproj myapp /custom/path
acfs newproj myapp --no-bd
```

Notes:
- The TUI uses gum when available (arrow keys, Space to toggle, Enter to confirm). Without gum, it falls back to numbered prompts.
- Minimum terminal size: 60x15.
- CLI mode skips existing AGENTS.md; the wizard overwrites it, so move it aside if you want to keep the old one.

### `acfs info` — System Overview

Displays installation status in under 1 second by reading cached state (no verification).

```bash
acfs info                # Terminal output (default)
acfs info --json         # JSON output for scripting
acfs info --html         # Self-contained HTML page
acfs info --minimal      # Just essentials (IP, key commands)
```

Example output:
```
╔══════════════════════════════════════════════════════════════╗
║                    ACFS System Info                           ║
╠══════════════════════════════════════════════════════════════╣
║  Host: vps-12345.contabo.net                                  ║
║  IP: 192.168.1.100                                            ║
║  User: ubuntu                                                 ║
║  Uptime: 3 days, 4 hours                                      ║
║                                                               ║
║  Quick Commands:                                              ║
║    cc    → Claude Code (dangerous mode)                       ║
║    cod   → Codex CLI (dangerous mode)                         ║
║    gmi   → Gemini CLI (yolo mode)                             ║
║    ntm   → Named Tmux Manager                                 ║
╚══════════════════════════════════════════════════════════════╝
```

**Design Philosophy:**
- **Speed**: Must complete in <1 second
- **Read-only**: Never verifies or tests (that's doctor's job)
- **Offline**: No network calls required
- **Fallback**: Graceful degradation if data missing

### `acfs cheatsheet` — Alias Discovery

Parses `~/.acfs/zsh/acfs.zshrc` to show all installed aliases and commands.

```bash
acfs cheatsheet              # List all aliases
acfs cheatsheet git          # Filter by category or search term
acfs cheatsheet --category Agents
acfs cheatsheet --search docker
acfs cheatsheet --json       # JSON output for tooling
```

Example output:
```
╔═══════════════════════════════════════════════════════════════╗
║  ACFS Cheatsheet                                               ║
╠═══════════════════════════════════════════════════════════════╣
║  Agents                                                        ║
║    cc   → claude --dangerously-skip-permissions                ║
║    cod  → codex --dangerously-bypass-approvals-and-sandbox     ║
║    gmi  → gemini --yolo                                        ║
║                                                                ║
║  Git                                                           ║
║    gs   → git status                                           ║
║    gp   → git push                                             ║
║    gl   → git pull                                             ║
║    gco  → git checkout                                         ║
║                                                                ║
║  Modern CLI                                                    ║
║    ls   → lsd --inode --long --all                             ║
║    cat  → bat                                                  ║
║    grep → rg                                                   ║
║    lg   → lazygit                                              ║
╚═══════════════════════════════════════════════════════════════╝
```

### `acfs dashboard` — HTML Status Page

Generates a self-contained HTML dashboard and optionally serves it.

```bash
acfs dashboard generate              # Generate ~/.acfs/dashboard/index.html
acfs dashboard generate --force      # Force regeneration
acfs dashboard serve                 # Serve on localhost:8080
acfs dashboard serve --port 3000     # Custom port
acfs dashboard serve --public        # Bind to 0.0.0.0
```

The dashboard provides:
- System health at a glance
- Tool versions and status
- Quick command reference
- Recent activity summary

### `acfs services-setup` — Credential Configuration

Interactive wizard for configuring AI agent credentials and cloud service logins.

```bash
acfs services-setup          # Run full setup wizard
```

Guides you through:
- **Claude Code**: API key configuration
- **Codex CLI**: ChatGPT account login
- **Gemini CLI**: Google account authentication
- **GitHub CLI**: `gh auth login`
- **Cloud CLIs**: Wrangler, Supabase, Vercel authentication

Also offers to install **DCG (Destructive Command Guard)**, a Claude Code hook that blocks destructive commands like `rm -rf /`.

### `acfs continue` — Upgrade Progress

After an Ubuntu upgrade reboot, view installation progress:

```bash
acfs continue                # Show current upgrade status
```

Displays:
- Original Ubuntu version
- Target version
- Current upgrade stage
- Next steps after completion

---

## Learning Hub (Web)

In addition to the terminal-based onboarding, ACFS provides a comprehensive web-based Learning Hub at [agent-flywheel.com/learn](https://agent-flywheel.com/learn).

### Web Lessons

The Learning Hub provides interactive lessons with progress tracking:

| # | Lesson | Duration | Topics |
|---|--------|----------|--------|
| 0 | Welcome & Overview | 5 min | What's installed, mental model |
| 1 | Linux Navigation | 8 min | Filesystem structure, essential commands |
| 2 | SSH & Persistence | 6 min | Secure connections, staying connected |
| 3 | tmux Basics | 7 min | Sessions, windows, panes, survival |
| 4 | Git Essentials | 10 min | Version control, dangerous operations |
| 5 | GitHub CLI | 8 min | Issues, PRs, releases via `gh` |
| 6 | Agent Commands | 10 min | Claude, Codex, Gemini usage |
| 7 | NTM Command Center | 8 min | Session orchestration |
| 8 | NTM Prompt Palette | 6 min | Quick command access |
| 9 | The Flywheel Loop | 8 min | How all 10 tools work together |

**Features:**
- Progress tracking in localStorage
- Code blocks with copy buttons
- Expandable deep-dive sections
- Practical exercises

### Command Reference

The [Command Reference](https://agent-flywheel.com/learn/commands) documents every installed tool:

| Category | Commands |
|----------|----------|
| **Agents** | `cc`, `cod`, `gmi` |
| **Search** | `rg`, `fd`, `sg`, `fzf` |
| **Git** | `lg`, `gh`, `git-lfs` |
| **System** | `z`, `bat`, `lsd`, `atuin`, `tmux` |
| **Stack** | `ntm`, `bv`, `am`, `cass`, `cm`, `ubs`, `slb`, `caam`, `dcg`, `ru` |
| **Languages** | `bun`, `uv`, `cargo`, `go` |
| **Cloud** | `wrangler`, `supabase`, `vercel`, `vault` |

### Technical Glossary

The [Glossary](https://agent-flywheel.com/glossary) defines 100+ technical terms with:

- **One-liner**: Quick tooltip definition
- **Full explanation**: Plain language description
- **Analogy**: "Think of it like..."
- **Why we use it**: Problem it solves
- **Related terms**: For context

Example entry:
```
RAM (Random Access Memory)
├── Short: Fast temporary storage your computer uses while working
├── Long: RAM is your computer's short-term memory...
├── Analogy: Like your desk space while working
├── Why: More RAM = run more programs simultaneously
└── Related: vCPU, VPS, NVMe
```

### Flywheel Visualization

The [Flywheel page](https://agent-flywheel.com/flywheel) visualizes tool interactions:

```
Plan (Beads) ──> Coordinate (Agent Mail) ──> Execute (NTM + Agents)
      ^                                              │
      │                                              v
      └──── Remember (CASS Memory) <──── Scan (UBS) ┘
```

**Workflow Scenarios:**

| Scenario | Description | Time |
|----------|-------------|------|
| Daily Parallel Progress | 3+ projects moving simultaneously | 3+ hours |
| Agents Reviewing Agents | Cross-review before merging | 30 min |
| Memory-Augmented Debugging | Past solutions for current bugs | 15 min |
| Coordinated Feature Dev | Multiple agents, one feature | 2+ hours |

### Interactive Website Components

The wizard website includes specialized components for guiding beginners:

**ConnectionCheck Component:**
A prominent visual that helps users verify they're connected to their VPS before running commands:
- Side-by-side comparison: "Wrong (laptop)" vs "Right (VPS)"
- Terminal prompt examples for Windows, Mac, and Linux
- Clear "STOP!" warning with color-coded styling

**CommandCard Component:**
CLI instruction cards with:
- Syntax-highlighted code blocks
- One-click copy button
- Platform-specific variations (bash/zsh/PowerShell)
- Expandable explanations

**Jargon Component (Responsive Technical Terms):**
A sophisticated tooltip system that adapts to device capabilities:

*Desktop behavior:*
- Hover reveals floating tooltip with term definition
- Radix UI Tooltip for accessible ARIA-compliant overlays
- Viewport-aware positioning (auto-flips when near edges)
- 200ms hover delay prevents tooltip spam

*Mobile behavior:*
- Tap opens bottom sheet drawer (Vaul library)
- Full definition visible without tiny tap targets
- Swipe-to-dismiss gesture support
- Snap points for partial/full expansion

*Visual features:*
- Gradient underline indicates tappable term
- Each term gets unique gradient based on slug hash
- Consistent color scheme with OKLCH tokens

*Content structure per term:*
```typescript
{
  term: "VPS",
  short: "Virtual Private Server - a remote computer you rent",
  long: "A VPS is your own slice of a powerful computer...",
  analogy: "Think of it like renting an apartment in a building",
  whyWeUseIt: "You get root access, dedicated resources...",
  relatedTerms: ["SSH", "Ubuntu", "RAM"]
}
```

**Confetti Celebration:**
On lesson completion:
- Burst of celebratory confetti particles
- Randomized encouraging messages
- Special celebration for completing all lessons
- Respects `prefers-reduced-motion` setting

**Stepper Component:**
Multi-step progress indicator:
- Visual step-by-step progress
- Clickable navigation
- Completion checkmarks
- Mobile-responsive design

### Expanded Lesson Library

The Learning Hub includes specialized lessons for each tool in the Dicklesworthstone stack:

| Lesson | Topics |
|--------|--------|
| **UBS (Bug Scanner)** | Scan workflow, severity levels, CI integration |
| **Agent Mail** | Registration, messaging, file reservations |
| **CASS (Session Search)** | Indexing, searching, cross-agent queries |
| **CASS Memory (cm)** | Rule extraction, playbook management |
| **Beads** | Issue tracking, graph metrics, priorities |
| **SLB (Safety)** | Two-person rule, dangerous command approval |
| **Prompt Engineering** | Effective prompts, context management |
| **Real-World Case Study** | End-to-end feature development walkthrough |

Each lesson includes:
- Conceptual introduction
- Practical commands with examples
- Interactive exercises
- Common pitfalls to avoid
- Links to tool documentation

---

## Interactive Onboarding (TUI)

After installation, users can learn the ACFS workflow through an interactive terminal-based tutorial. The onboarding TUI guides users through 11 lessons covering Linux basics through full agentic workflows.

### Running Onboarding

```bash
onboard                # Launch interactive menu
onboard --list         # List lessons with completion status
onboard 3              # Jump to lesson 3
onboard --reset        # Reset progress and start fresh
```

### Lessons

| # | Title | Duration | Topics |
|---|-------|----------|--------|
| 0 | Welcome & Overview | 2 min | What's installed, system overview |
| 1 | Linux Navigation | 5 min | Filesystem, basic commands |
| 2 | SSH & Persistence | 4 min | Keys, config, tunnels, screen/tmux |
| 3 | tmux Basics | 6 min | Sessions, windows, panes, navigation |
| 4 | Agent Commands | 5 min | `cc`, `cod`, `gmi` aliases |
| 5 | NTM Core | 7 min | Named Tmux Manager basics |
| 6 | NTM Prompt Palette | 5 min | Command palette features |
| 7 | Flywheel Loop | 8 min | Complete agentic workflow |
| 8 | Keeping Updated | 4 min | Using `acfs-update`, troubleshooting |
| 9 | RU: Multi-Repo Mastery | 6 min | Multi-repo sync, agent-sweep, parallel workflows |
| 10 | DCG: Destructive Command Guard | 5 min | Command safety, protection packs, allow-once workflow |

### Progress Tracking

Progress is saved in `~/.acfs/onboard_progress.json`:

```json
{
  "completed": [0, 1, 2],
  "current": 3,
  "started_at": "2024-12-20T10:30:00-05:00"
}
```

The TUI shows completion status for each lesson and suggests the next one to take. Users can jump to any lesson or re-take completed ones.

### Enhanced UX with Gum

If [Charmbracelet Gum](https://github.com/charmbracelet/gum) is installed, the onboarding system uses it for enhanced terminal UI—selection menus, styled prompts, and better formatting. Without Gum, it falls back to simple numbered menus that work everywhere.

---

## Tools Installed

ACFS installs a comprehensive suite of **30+ tools** organized into categories:

### Shell & Terminal UX

| Tool | Command | Description |
|------|---------|-------------|
| **zsh** | `zsh` | Modern shell |
| **oh-my-zsh** | - | zsh plugin framework |
| **powerlevel10k** | - | Fast, customizable prompt |
| **lsd** | `ls` (aliased) | Modern ls with icons |
| **atuin** | `Ctrl+R` | Shell history with search |
| **fzf** | `fzf` | Fuzzy finder |
| **zoxide** | `z` | Smarter cd |
| **direnv** | - | Directory-specific env vars |

### Languages & Package Managers

| Tool | Command | Description |
|------|---------|-------------|
| **bun** | `bun` | Fast JS/TS runtime + package manager |
| **uv** | `uv` | Fast Python package manager |
| **Rust** | `cargo` | Rust toolchain |
| **Go** | `go` | Go toolchain |

### Dev Tools

| Tool | Command | Description |
|------|---------|-------------|
| **tmux** | `tmux` | Terminal multiplexer |
| **ripgrep** | `rg` | Fast recursive grep |
| **ast-grep** | `sg` | Structural code search |
| **lazygit** | `lg` (aliased) | Git TUI |
| **GitHub CLI** | `gh` | GitHub auth, issues, PRs |
| **Git LFS** | `git-lfs` | Large file support for Git |
| **bat** | `cat` (aliased) | Cat with syntax highlighting |
| **neovim** | `nvim` | Modern vim |
| **jq** | `jq` | JSON processor |
| **rsync** | `rsync` | Fast file sync/copy |
| **lsof** | `lsof` | Debug open files/ports |
| **dnsutils** | `dig` | DNS debugging |
| **netcat** | `nc` | Network debugging |
| **strace** | `strace` | Syscall tracing |

### Networking

| Tool | Command | Description |
|------|---------|-------------|
| **Tailscale** | `tailscale` | Zero-config mesh VPN |

**Tailscale Integration:**

Tailscale provides secure, encrypted networking between your devices without complex firewall configuration:

```bash
# Authenticate and join your tailnet
tailscale up

# Check connection status
tailscale status

# Get your Tailscale IP
tailscale ip

# SSH over Tailscale (bypasses firewalls)
ssh ubuntu@your-vps.tailnet-name.ts.net
```

Benefits for agentic workflows:
- **Firewall-free access**: Connect even when behind NAT or restrictive firewalls
- **MagicDNS**: Access your VPS by hostname instead of IP
- **SSH keys over Tailscale**: Use `tailscale ssh` for key-free authentication
- **ACLs**: Fine-grained access control for team environments

### AI Coding Agents

| Agent | Command | Alias (Vibe Mode) |
|-------|---------|-------------------|
| **Claude Code** | `claude` | `cc` (dangerous mode) |
| **Codex CLI** | `codex` | `cod` (dangerous mode) |
| **Gemini CLI** | `gemini` | `gmi` (dangerous mode) |

**Vibe Mode Aliases:**
```bash
# Claude Code with max memory
alias cc='NODE_OPTIONS="--max-old-space-size=32768" claude --dangerously-skip-permissions'

# Codex with bypass and dangerous filesystem access
alias cod='codex --dangerously-bypass-approvals-and-sandbox'

# Gemini with yolo mode
alias gmi='gemini --yolo'
```

**Installation & Updates:**
Claude Code should be installed and updated using its native mechanisms:
- **Install:** ACFS uses the official native installer (`claude.ai/install.sh`), checksum-verified via `checksums.yaml` (installs to `~/.local/bin/claude`)
- **Update:** Use `claude update` (built-in) or run `acfs update --agents-only`

This ensures proper authentication handling and avoids issues with alternative package manager builds. For Codex and Gemini, ACFS uses standard bun global package updates.

### Cloud & Database

| Tool | Command | Description |
|------|---------|-------------|
| **PostgreSQL 18** | `psql` | Database |
| **HashiCorp Vault** | `vault` | Secrets management |
| **Wrangler** | `wrangler` | Cloudflare CLI |
| **Supabase CLI** | `supabase` | Supabase management |
| **Vercel CLI** | `vercel` | Vercel deployment |

Vault is installed by default (skip with `--skip-vault`). ACFS installs the Vault **CLI** so you have a real secrets tool available early; it does not automatically configure a Vault server for you.

Supabase networking note: some Supabase projects expose the **direct Postgres host over IPv6-only** (often on free tiers). If your VPS/network is **IPv4-only**, use the Supabase **pooler** connection string instead (or upgrade/configure networking for direct IPv4).

### Dicklesworthstone Stack (10 Tools)

The complete suite of tools for professional agentic workflows:

| # | Tool | Command | Description |
|---|------|---------|-------------|
| 1 | **Named Tmux Manager** | `ntm` | Agent cockpit—spawn, orchestrate, monitor tmux sessions |
| 2 | **MCP Agent Mail** | - | Agent coordination via mail-like messaging |
| 3 | **Ultimate Bug Scanner** | `ubs` | Bug scanning with guardrails |
| 4 | **Beads Viewer** | `bv` | Task management TUI with graph analysis |
| 5 | **Coding Agent Session Search** | `cass` | Unified agent history search |
| 6 | **CASS Memory System** | `cm` | Procedural memory for agents |
| 7 | **Coding Agent Account Manager** | `caam` | Agent auth switching |
| 8 | **Simultaneous Launch Button** | `slb` | Two-person rule for dangerous commands |
| 9 | **Destructive Command Guard** | `dcg` | Claude Code hook blocking dangerous git/fs commands |
| 10 | **Repo Updater** | `ru` | Multi-repo sync + AI-driven commit automation |

### Bundled Utilities

Additional productivity tools installed alongside the stack:

| Tool | Command | Description |
|------|---------|-------------|
| **Get Image from Internet Link** | `giil` | Download images from iCloud, Dropbox, Google Photos for visual debugging |
| **Chat Shared Conversation to File** | `csctf` | Convert AI share links (ChatGPT, Gemini, Claude) to Markdown/HTML |

---

## Doctor Command

`acfs doctor` performs comprehensive health checks on your installation:

```bash
$ acfs doctor

╔══════════════════════════════════════════════════════════════╗
║                    ACFS Health Check                          ║
╠══════════════════════════════════════════════════════════════╣
║ Identity                                                      ║
║   ✔ Running as ubuntu user                                    ║
║   ✔ Passwordless sudo enabled                                 ║
║                                                               ║
║ Workspace                                                     ║
║   ✔ /data/projects exists                                     ║
║                                                               ║
║ Shell                                                         ║
║   ✔ zsh installed                                             ║
║   ✔ oh-my-zsh installed                                       ║
║   ✔ powerlevel10k installed                                   ║
║   ✔ acfs.zshrc sourced                                        ║
║                                                               ║
║ Core Tools                                                    ║
║   ✔ bun 1.2.16                                                ║
║   ✔ uv 0.5.14                                                 ║
║   ✔ cargo 1.84.0                                              ║
║   ✔ go 1.23.4                                                 ║
║   ✔ ripgrep 14.1.0                                            ║
║   ✔ ast-grep 0.30.1                                           ║
║                                                               ║
║ Agents                                                        ║
║   ✔ claude 1.0.24                                             ║
║   ✔ codex 0.1.2504252326                                      ║
║   ✔ gemini 0.1.12                                             ║
║                                                               ║
║ Cloud                                                         ║
║   ✔ vault 1.18.3                                              ║
║   ✔ wrangler 4.16.0                                           ║
║   ✔ supabase 2.23.4                                           ║
║   ✔ vercel 41.7.6                                             ║
║                                                               ║
║ Dicklesworthstone Stack                                       ║
║   ✔ ntm 0.3.2                                                 ║
║   ✔ slb 0.2.1                                                 ║
║   ✔ ubs 0.1.8                                                 ║
║   ✔ bv 0.9.4                                                  ║
║   ✔ cass 0.4.2                                                ║
║   ✔ cm 0.1.3                                                  ║
║   ✔ caam 0.2.0                                                ║
║   ✔ dcg 0.1.0                                                 ║
║   ✔ ru 1.2.0                                                  ║
║   ⚠ mcp_agent_mail (not running)                              ║
║                                                               ║
║ Utilities                                                     ║
║   ✔ giil 3.0.0                                                ║
║   ✔ csctf 1.0.0                                               ║
╠══════════════════════════════════════════════════════════════╣
║ Overall: 35/36 checks passed                                  ║
╚══════════════════════════════════════════════════════════════╝
```

### Generated Doctor Checks

Doctor checks can be generated from the manifest (`scripts/generated/doctor_checks.sh`) to keep verification logic close to `acfs.manifest.yaml`. Today, the user-facing `acfs doctor` command is implemented in `scripts/lib/doctor.sh` and does not yet consume the generated `doctor_checks.sh` output.

### Options

```bash
acfs doctor          # Interactive colorful output
acfs doctor --json   # Machine-readable JSON output
acfs doctor --quiet  # Exit code only (0=healthy, 1=issues)
acfs doctor --deep   # Run functional tests (auth, connections)
```

### Deep Checks (`--deep`)

The `--deep` flag runs functional tests beyond binary existence:

| Category | Checks |
|----------|--------|
| **Agent Auth** | Claude config, Codex OAuth, Gemini credentials |
| **Database** | PostgreSQL connection, ubuntu role exists |
| **Cloud CLIs** | `gh auth status`, `wrangler whoami`, Supabase/Vercel tokens |
| **Vault** | `VAULT_ADDR` configured |

Deep checks use 5-second timeouts to avoid hanging on network issues. Results are cached for 5 minutes to speed up repeated runs.

Example output:
```
Deep Checks
  ✔ Claude auth configured
  ✔ PostgreSQL connection working
  ⚠ Codex not authenticated (run: codex login)
  ✔ GitHub CLI authenticated

8/9 functional tests passed in 3.2s
```

---

## The Wizard Website

The wizard guides beginners through a **13-step journey** from "I have a laptop" to "AI agents are coding for me":

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  ACFS Wizard                                                   [Step 3/13]  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  STEP 3: Generate SSH Key                                              │ │
│  │  ──────────────────────────────────────────────────────────────────    │ │
│  │                                                                        │ │
│  │  Run this command in your terminal:                                    │ │
│  │                                                                        │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │ │
│  │  │ ssh-keygen -t ed25519 -C "your-email@example.com"         [📋] │  │ │
│  │  └─────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  ☐ I ran this command                                                  │ │
│  │                                                                        │ │
│  │  [← Previous]                                        [Next Step →]     │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  Progress: ●●●○○○○○○○○○○                                                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Wizard Steps

| Step | Title | What Happens |
|------|-------|--------------|
| 1 | **Choose Your OS** | Select Mac, Windows, or Linux (auto-detected) |
| 2 | **Install Terminal** | Get a proper terminal application set up |
| 3 | **Generate SSH Key** | Create an ed25519 key for VPS access |
| 4 | **Rent a VPS** | Choose a VPS provider and plan |
| 5 | **Create VPS Instance** | Launch your VPS and confirm SSH access |
| 6 | **SSH Into Your VPS** | First connection with troubleshooting tips |
| 7 | **Set Up Accounts** | Create accounts for the services you'll use |
| 8 | **Pre-Flight Check** | Verify your VPS is ready before installing |
| 9 | **Run Installer** | The `curl \| bash` one-liner |
| 10 | **Reconnect as Ubuntu** | Post-install reconnection |
| 11 | **Verify Key Connection** | Reconnect using your SSH key and confirm it works |
| 12 | **Status Check** | Run `acfs doctor` to verify |
| 13 | **Launch Onboarding** | Start the interactive tutorial |

### Key Features

- **OS Detection:** Auto-detects Mac vs Windows for tailored instructions
- **Copy-to-Clipboard:** One-click copy for all commands
- **Progress Tracking:** localStorage persistence across browser sessions
- **Confirmation Checkboxes:** "I ran this command" acknowledgments
- **Troubleshooting:** Expandable help for common issues

### Technology Stack

```
Next.js 16 (App Router)
├── React 19
├── Tailwind CSS 4 (OKLCH colors)
├── shadcn/ui components
├── Radix UI primitives
└── Lucide icons
```

**No backend required.** All state is stored in:
- URL query parameters
- localStorage (`agent-flywheel-user-os`, `agent-flywheel-vps-ip`, `agent-flywheel-wizard-completed-steps`)

### Wizard State Management

The wizard uses **TanStack Query** for state management with optimistic updates and cross-tab synchronization:

**Architecture:**
```typescript
// Query-based state with localStorage persistence
const { data: steps } = useQuery({
  queryKey: ['wizardSteps', 'completed'],
  queryFn: getCompletedSteps,  // Reads from localStorage
  staleTime: 0,                // Always check for updates
  gcTime: Infinity,            // Never garbage collect
});
```

**Optimistic Updates with Rollback:**
```typescript
const mutation = useMutation({
  mutationFn: async (stepId) => {
    const newSteps = addCompletedStep(currentSteps, stepId);
    setCompletedSteps(newSteps);  // Persist to localStorage
    return newSteps;
  },
  onMutate: (stepId) => {
    // Optimistically update cache immediately
    const previousSteps = queryClient.getQueryData(queryKey);
    queryClient.setQueryData(queryKey, addCompletedStep(baseSteps, stepId));
    return { previousSteps };  // For rollback
  },
  onError: (_err, _stepId, context) => {
    // Rollback on failure
    queryClient.setQueryData(queryKey, context.previousSteps);
  },
});
```

**Cross-Tab Synchronization:**
The wizard maintains sync across browser tabs via two mechanisms:
1. **Custom DOM events** for same-tab coordination between components
2. **Storage events** for cross-tab updates when localStorage changes

```typescript
// Same-tab: custom event dispatch
window.dispatchEvent(new CustomEvent('acfs:wizard:completed-steps-changed', {
  detail: { steps }
}));

// Cross-tab: storage event listener
window.addEventListener('storage', (event) => {
  if (event.key === COMPLETED_STEPS_KEY) {
    queryClient.setQueryData(queryKey, getCompletedSteps());
  }
});
```

**Safe localStorage Utilities:**
All localStorage access is wrapped in safe utilities that handle SSR, private browsing, and quota exceeded errors:

```typescript
// Safe read (returns null on any error)
export function safeGetJSON<T>(key: string): T | null;

// Safe write (returns boolean success)
export function safeSetJSON(key: string, value: unknown): boolean;

// URL preservation for state fallback
export function withCurrentSearch(path: string): string;
```

This architecture ensures the wizard progress survives browser refreshes, works across tabs, and degrades gracefully when localStorage is unavailable.

---

## Configuration Files

ACFS deploys optimized configuration files to `~/.acfs/` on the target VPS.

### `~/.acfs/zsh/acfs.zshrc`

A comprehensive zsh configuration that's sourced by `~/.zshrc`:

**Oh-My-Zsh Plugins (14 total):**

| Plugin | Category | What It Provides |
|--------|----------|------------------|
| `git` | VCS | 150+ git aliases (gs, gp, gl, gco, gcm, etc.) |
| `sudo` | Shell | Double-tap Esc to prefix previous command with sudo |
| `colored-man-pages` | Shell | Colorized man pages for better readability |
| `command-not-found` | Shell | Suggests packages when command not found |
| `docker` | Containers | Docker command completion and aliases |
| `docker-compose` | Containers | docker-compose completion and aliases |
| `python` | Lang | Python aliases (pyfind, pyclean, pygrep) |
| `pip` | Lang | pip completion and cache management |
| `tmux` | Terminal | tmux aliases (ta, tad, ts, tl, tkss) |
| `tmuxinator` | Terminal | tmuxinator project completion |
| `systemd` | System | systemctl aliases (sc-status, sc-start, sc-stop) |
| `rsync` | Tools | rsync completion and common flag aliases |
| `zsh-autosuggestions` | UX | Fish-like autosuggestions from history |
| `zsh-syntax-highlighting` | UX | Real-time command syntax highlighting |

> **Note**: `zsh-autosuggestions` and `zsh-syntax-highlighting` are custom plugins installed from GitHub. They must be listed last for optimal performance.

**Path Configuration:**
```bash
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"
export PATH="$HOME/.atuin/bin:$PATH"
```

**Modern CLI Aliases:**
```bash
alias ls='lsd --inode --long --all'
alias ll='lsd -l'
alias tree='lsd --tree'
alias cat='bat'
alias grep='rg'
alias vim='nvim'
alias lg='lazygit'
```

**Tool Integrations:**
```bash
# Atuin (better shell history)
eval "$(atuin init zsh)"

# Zoxide (smarter cd)
eval "$(zoxide init zsh)"

# direnv (directory env vars)
eval "$(direnv hook zsh)"

# fzf (fuzzy finder)
source /usr/share/doc/fzf/examples/key-bindings.zsh
```

**Shell Keybindings (Quality of Life):**

| Keybind | Action | Notes |
|---------|--------|-------|
| `Ctrl+→` | Forward word | Navigate by word |
| `Ctrl+←` | Backward word | Navigate by word |
| `Alt+→` | Forward word | Alternative binding |
| `Alt+←` | Backward word | Alternative binding |
| `Ctrl+Backspace` | Delete word backward | Fast deletion |
| `Ctrl+Delete` | Delete word forward | Fast deletion |
| `Home` | Beginning of line | Works in all terminals |
| `End` | End of line | Works in all terminals |
| `Ctrl+R` | Atuin history search | Interactive fuzzy search |

**Atuin History Bindings:**
The config forces Atuin bindings to load last (after OMZ plugins) ensuring `Ctrl+R` triggers Atuin's fuzzy history search rather than zsh's default:

```bash
# Forced at end of zshrc
bindkey -e  # Emacs mode
bindkey -M emacs '^R' atuin-search
bindkey -M viins '^R' atuin-search-viins
bindkey -M vicmd '^R' atuin-search-vicmd
```

### `~/.acfs/tmux/tmux.conf`

A tmux configuration specifically optimized for NTM and multi-agent workflows:

**Key Bindings:**
```
Prefix: Ctrl+a (not Ctrl+b - more ergonomic)
Split horizontal: |  (preserves working directory)
Split vertical: -    (preserves working directory)
Navigate panes: h/j/k/l (vim-style)
Resize panes: H/J/K/L (repeatable with -r flag)
Reload config: r
New window: c (preserves working directory)
```

**Copy Mode (vim-style):**
```
Enter copy mode: prefix + [
Begin selection: v
Rectangle selection: r
Copy and exit: y
```

**Agent Workflow Optimizations:**

| Setting | Value | Purpose |
|---------|-------|---------|
| `history-limit` | 50,000 | Extended scrollback for long agent sessions |
| `escape-time` | 10ms | Faster key response (reduced from default 500ms) |
| `focus-events` | on | Enables vim/neovim autoread in agent windows |
| `detach-on-destroy` | off | NTM compatibility—don't detach when session ends |
| `monitor-activity` | on | Track agent window activity |
| `visual-activity` | off | Silent monitoring (no bell) |

**Catppuccin-Inspired Theme:**
```bash
# Status bar (top position, less intrusive)
status-style: bg=#1e1e2e, fg=#cdd6f4

# Session indicator (blue accent)
status-left: #[fg=#89b4fa,bold] #S

# Active window highlight (pink accent)
window-status-current-format: #[fg=#f5c2e7,bold] #I:#W

# Pane borders
pane-border-style: fg=#313244
pane-active-border-style: fg=#89b4fa  # Blue highlight
```

**Local Overrides:**
The config sources `~/.tmux.conf.local` if it exists, allowing personal customizations without modifying ACFS defaults.

---

## Library Modules

The installer is organized into modular Bash libraries in `scripts/lib/`:

### `logging.sh`

Colored console output utilities:

```bash
log_step "1/8" "Installing packages..."  # Blue step indicator
log_detail "Installing zsh..."           # Gray indented detail
log_success "Complete"                    # Green checkmark
log_warn "May take a while"              # Yellow warning
log_error "Failed"                        # Red error
log_fatal "Cannot continue"              # Red error + exit 1
```

### `security.sh`

HTTPS enforcement and checksum verification:

```bash
enforce_https "$url"                     # Fail if not HTTPS
verify_checksum "$url" "$sha256" "$name" # Verify before execute
fetch_and_run "$url" "$sha256" "$name"   # Verify + execute in one
```

### `os_detect.sh`

OS detection and validation:

```bash
detect_os()      # Sets OS_ID, OS_VERSION, OS_CODENAME
validate_os()    # Checks for Ubuntu 25.10 (or upgrade path)
is_fresh_vps()   # Heuristic detection of fresh VPS
get_arch()       # Returns amd64/arm64
is_wsl()         # Detects WSL
is_docker()      # Detects Docker container
```

### `user.sh`

User account normalization:

```bash
ensure_user()              # Creates ubuntu user if missing
enable_passwordless_sudo() # Adds NOPASSWD to sudoers
migrate_ssh_keys()         # Copies keys from root to ubuntu
normalize_user()           # Full normalization sequence
```

### `update.sh`

Component update logic with version tracking and logging:

```bash
update_apt()       # apt update/upgrade with lock detection
update_bun()       # bun upgrade with version tracking
update_agents()    # Claude, Codex, Gemini (version before/after)
update_cloud()     # Wrangler, Supabase, Vercel (Supabase uses verified release tarball)
update_rust()      # rustup update stable
update_uv()        # uv self update
update_go()        # Go toolchain update
update_shell()     # OMZ, P10K, plugins, Atuin, Zoxide
update_stack()     # Dicklesworthstone stack tools

# Features:
# - Automatic logging to ~/.acfs/logs/updates/
# - Version tracking (before/after for each tool)
# - APT lock detection and warning
# - Reboot-required detection for kernel updates
# - Dry-run mode with --dry-run flag
```

### `gum_ui.sh`

Enhanced terminal UI using Charmbracelet Gum:

```bash
print_banner()           # ASCII art ACFS banner
gum_step/gum_detail      # Styled output
gum_success/warn/error   # Colored messages
gum_spin                 # Spinner for long operations
gum_confirm              # Yes/No prompt
gum_choose               # Selection menu
```

Falls back to basic echo if Gum is not installed.

### `error_tracking.sh`

Sophisticated error collection and reporting:

```bash
track_error "phase" "step" "error_message"
track_warning "phase" "step" "warning_message"
get_error_report                    # Generate structured error report
get_error_count                     # Count of tracked errors
has_errors                          # Boolean check for any errors
```

Features:
- Collects errors without aborting execution
- Associates errors with phase and step context
- Generates end-of-run summary reports
- Distinguishes warnings from errors

### `state.sh`

State machine management for installation progress (v3 schema):

```bash
state_init                          # Initialize state file
state_get_phase                     # Current phase
state_set_phase "phase_name"        # Set current phase
state_mark_complete "phase_name"    # Mark phase complete
state_has_completed "phase_name"    # Check if phase done
state_save                          # Persist to disk (atomic)
state_load                          # Load from disk
```

The state file (`~/.acfs/state.json`) uses atomic writes to prevent corruption.

### `contract.sh`

Runtime contract validation for generated scripts:

```bash
acfs_require_contract "module_id"   # Assert environment is ready
acfs_check_contract                 # Non-fatal contract check
```

Validates that required environment variables and functions exist before execution:
- `TARGET_USER`, `TARGET_HOME`, `MODE`
- `ACFS_BOOTSTRAP_DIR`, `ACFS_LIB_DIR`
- Logging functions: `log_detail`, `log_success`, etc.

### `smoke_test.sh`

Post-install verification that runs automatically after installation:

```bash
run_smoke_test                      # Execute all smoke tests
```

**Critical Checks** (must pass):
- Running as ubuntu user
- Passwordless sudo enabled
- Zsh is default shell
- Core tools accessible (bun, uv, cargo)

**Non-Critical Checks** (warnings only):
- Agent authentication configured
- Cloud CLIs authenticated
- Optional tools installed

Example output:
```
[Smoke Test]
  ✅ Running as ubuntu user
  ✅ Passwordless sudo enabled
  ✅ Zsh is default shell
  ✅ bun --version works
  ⚠️  Codex not authenticated (run: codex login)
  ✅ 8/9 checks passed
```

### `session.sh`

Agent session export functionality for sharing and replay:

```bash
session_export "claude-code" "session_id" "/output/path"
session_list                        # List exportable sessions
session_validate "/export/file.json"
```

Implements the **Session Export Schema** for cross-agent sharing:

```typescript
interface SessionExport {
  schema_version: 1;
  exported_at: string;              // ISO8601
  session_id: string;
  agent: "claude-code" | "codex" | "gemini";
  model: string;
  summary: string;
  duration_minutes: number;
  stats: {
    turns: number;
    files_created: number;
    files_modified: number;
    commands_run: number;
  };
  outcomes: Array<{
    type: "file_created" | "file_modified" | "command_run";
    path?: string;
    description: string;
  }>;
  key_prompts: string[];            // Notable prompts for learning
  sanitized_transcript: Array<{
    role: "user" | "assistant";
    content: string;
    timestamp: string;
  }>;
}
```

### `tailscale.sh`

Zero-config VPN setup for secure remote access:

```bash
install_tailscale                   # Install via official APT repo
verify_tailscale                    # Check installation
tailscale_status                    # Get connection status
```

Tailscale provides:
- **Secure mesh networking** between your devices
- **SSH over Tailscale** for firewall-free access
- **MagicDNS** for hostname-based addressing
- **ACL-based access control**

After installation, run `tailscale up` to authenticate and join your tailnet.

### `ubuntu_upgrade.sh`

Multi-reboot Ubuntu version upgrade automation:

```bash
start_ubuntu_upgrade                # Begin upgrade chain
check_upgrade_status                # Current upgrade state
resume_upgrade_after_reboot         # Continue after reboot
```

Handles the complex multi-step Ubuntu upgrade process:
1. Detects current version
2. Calculates upgrade path (e.g., 24.04 → 25.04 → 25.10)
3. Performs sequential `do-release-upgrade` operations
4. Installs systemd service for post-reboot resume
5. Continues ACFS installation after reaching target

---

## MCP Agent Mail Integration

ACFS includes integration with **MCP Agent Mail** for multi-agent coordination:

### What Agent Mail Provides

- **Identities:** Each agent registers with a unique name
- **Inbox/Outbox:** Message-based communication between agents
- **File Reservations:** Advisory leases to prevent agents from clobbering each other's work
- **Searchable Threads:** Full-text search across all messages
- **Git Persistence:** All artifacts stored in git for human auditability

### Core Patterns

**1. Register Identity:**
```bash
# In your agent, call:
mcp.ensure_project(project_key="/data/projects/my-project")
mcp.register_agent(project_key=..., program="claude-code", model="opus-4.5")
```

**2. Reserve Files Before Editing:**
```bash
mcp.file_reservation_paths(
    project_key=...,
    agent_name="BlueLake",
    paths=["src/**"],
    ttl_seconds=3600,
    exclusive=true
)
```

**3. Communicate:**
```bash
mcp.send_message(
    project_key=...,
    sender_name="BlueLake",
    to=["GreenCastle"],
    subject="Review needed",
    body_md="Please review the auth changes..."
)
```

### Macros for Speed

When speed matters more than fine-grained control:

```bash
mcp.macro_start_session(...)      # Ensure project + register + fetch inbox
mcp.macro_prepare_thread(...)     # Align with existing thread
mcp.macro_file_reservation_cycle(...)  # Reserve + work + release
mcp.macro_contact_handshake(...)  # Request contact permissions
```

---

## Destructive Command Guard (dcg)

**dcg** is a high-performance Claude Code hook that blocks dangerous git and filesystem commands before they execute. Built in Rust for sub-millisecond latency, it provides mechanical enforcement of safety rules that instructions alone cannot guarantee.

### Why dcg Exists

On December 17, 2025, an AI agent ran `git checkout --` on files containing hours of uncommitted work from a parallel coding session. The files were recovered via `git fsck --lost-found`, but the incident made one thing clear: instructions in `AGENTS.md` don't prevent execution. **dcg provides mechanical enforcement**.

### What Gets Blocked

| Category | Commands |
|----------|----------|
| **Git Reset** | `git reset --hard`, `git reset --merge` |
| **File Discard** | `git checkout -- <files>`, `git restore <files>` |
| **Force Push** | `git push --force` / `-f` (allows `--force-with-lease`) |
| **Clean** | `git clean -f` (allows `-n` dry-run) |
| **Branch Delete** | `git branch -D` (allows `-d`) |
| **Stash Loss** | `git stash drop`, `git stash clear` |
| **Filesystem** | `rm -rf` (except temp directories) |

### What Gets Allowed

Safe variants are allowlisted:
- `git checkout -b <branch>` — Creates branch, doesn't touch files
- `git restore --staged` — Only unstages, doesn't discard
- `git clean -n` — Dry-run preview
- `rm -rf /tmp/...` — Temp directories are ephemeral

### Installation

```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/destructive_command_guard/main/install.sh?$(date +%s)" | bash
```

### Claude Code Configuration

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": "dcg"}]
      }
    ]
  }
}
```

### Modular Pack System

dcg uses a modular pack system for extensibility. Enable additional packs in `~/.config/dcg/config.toml`:

```toml
[packs]
enabled = [
    "database.postgresql",
    "containers.docker",
    "kubernetes",
]
```

Available packs: `database.*`, `containers.*`, `kubernetes.*`, `cloud.*`, `infrastructure.*`, `system.*`, `package_managers`.

---

## Repo Updater (ru)

**ru** is a production-grade CLI tool for synchronizing collections of GitHub repositories and automating commit workflows across dirty repos with AI assistance.

### Core Features

- **Multi-repo sync**: Clone missing repos, pull updates, detect conflicts
- **Agent sweep**: AI-driven commit automation across repositories with uncommitted changes
- **AI code review**: Orchestrate Claude Code review sessions for open issues/PRs
- **Work-stealing queue**: Parallel execution with load-balanced workers
- **NTM integration**: Session management via Named Tmux Manager

### Quick Start

```bash
# Install
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/repo_updater/main/install.sh?ru_cb=$(date +%s)" | bash

# Initialize configuration
ru init --example

# Sync all repositories
ru sync

# Check status without changes
ru status
```

### Agent Sweep Workflow

The `agent-sweep` command automates commits across dirty repositories:

```bash
# Preview repos to process
ru agent-sweep --dry-run

# Full automation with AI
ru agent-sweep --parallel 4

# Include release automation
ru agent-sweep --with-release
```

**Three-Phase Workflow:**
1. **Planning**: Claude Code analyzes changes, generates commit message
2. **Commit**: Validates plan, stages files, runs quality gates
3. **Release**: (Optional) Creates version tag and GitHub release

### Configuration

```bash
# ~/.config/ru/config
PROJECTS_DIR=/data/projects
LAYOUT=flat                   # flat|owner-repo|full
UPDATE_STRATEGY=ff-only       # ff-only|rebase|merge
PARALLEL=4
```

**Repo list format** (`~/.config/ru/repos.d/public.txt`):
```
owner/repo
owner/repo@develop            # Pin to branch
owner/repo as custom-name     # Custom directory name
```

---

## Get Image from Internet Link (giil)

**giil** downloads full-resolution images from cloud photo shares to your terminal. Essential for remote debugging workflows where you need to analyze screenshots in SSH sessions.

### Supported Platforms

| Platform | Method | Speed |
|----------|--------|-------|
| **iCloud** | 4-tier capture strategy | 5-15s |
| **Dropbox** | Direct curl download | 1-2s |
| **Google Photos** | Network interception | 5-15s |
| **Google Drive** | Multi-tier with auth detection | 5-15s |

### Usage

```bash
# Basic download
giil "https://share.icloud.com/photos/02cD9okNHvVd-uuDnPCH3ZEEA"
# Output: /current/dir/icloud_20240115_143245.jpg

# Download to specific directory
giil "..." --output ~/Downloads

# Get JSON metadata
giil "..." --json

# Download all photos from album
giil "..." --all --output ~/album
```

### Installation

```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/giil/main/install.sh?v=3.0.0" | bash
```

### Visual Debugging Workflow

1. Screenshot UI bug on iPhone
2. Wait for iCloud sync to Mac
3. Share via Photos.app → Copy iCloud Link
4. Paste link into remote terminal running Claude Code
5. `giil` fetches the image locally
6. AI assistant analyzes the screenshot

---

## Chat Shared Conversation to File (csctf)

**csctf** converts public AI conversation share links into clean, searchable Markdown and HTML transcripts. Perfect for archiving AI conversations, building knowledge bases, and sharing with teams.

### Supported Providers

| Provider | URL Pattern |
|----------|------------|
| **ChatGPT** | `chatgpt.com/share/*` |
| **Gemini** | `gemini.google.com/share/*` |
| **Grok** | `grok.com/share/*` |
| **Claude** | `claude.ai/share/*` |

### Usage

```bash
# Basic conversion
csctf https://chatgpt.com/share/69343092-91ac-800b-996c-7552461b9b70
# Creates: <slug>.md and <slug>.html

# Markdown only
csctf "..." --md-only

# Publish to GitHub Pages
csctf "..." --publish-to-gh-pages --yes

# JSON metadata output
csctf "..." --json
```

### Installation

```bash
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/chat_shared_conversation_to_file/main/install.sh | bash
```

### Output Features

- **Markdown**: Clean formatting with preserved code blocks and language hints
- **HTML**: Zero-JavaScript static page with syntax highlighting
- **Deterministic filenames**: `<slug>_YYYYMMDD.md` for reliable archival
- **Collision handling**: Auto-increments suffix to avoid overwrites

---

## CI/CD

ACFS uses GitHub Actions for continuous integration:

### Installer Testing (`installer.yml`)

```yaml
# Runs on every push and PR
jobs:
  shellcheck:
    - Lints all bash scripts with ShellCheck

  integration:
    - Matrix tests across Ubuntu 24.04, 25.04, 25.10
    - Runs full installation in Docker
    - Verifies all tools installed correctly
    - Runs acfs doctor to confirm health
```

This ensures the installer works on all supported Ubuntu versions and catches shell scripting issues early.

### Website Deployment (`website.yml`)

```yaml
# Builds and deploys the Next.js wizard
jobs:
  build:
    - Type-check TypeScript
    - Run ESLint
    - Build production bundle

  deploy:
    - Deploy to Vercel (production)
```

### Automated Checksum Updates (`checksum-monitor.yml`)

ACFS automatically monitors upstream installers for changes and updates checksums:

```yaml
# Runs every 2 hours + on upstream changes
schedule: "0 */2 * * *"
triggers:
  - Schedule (every 2 hours)
  - Webhook from upstream repos (repository_dispatch)
  - Changes to security.sh
```

**How It Works:**

1. **Verify Current Checksums**: Downloads all upstream installers, calculates SHA256
2. **Detect Changes**: Compares against `checksums.yaml`
3. **Categorize Tools**: Separates "trusted" tools (can auto-update) from others
4. **Auto-Update**: For trusted tools, commits updated checksums automatically
5. **Alert**: For non-trusted tools, creates GitHub issue for manual review

**Trusted Tools (Auto-Update Enabled):**
- Dicklesworthstone stack tools (ntm, cass, cm, ubs, slb, dcg, caam, bv, agent-mail, ru)
- These are maintained by the same author, so upstream changes are implicitly trusted

**Non-Trusted Tools (Manual Review Required):**
- Third-party installers (bun, uv, rust, oh-my-zsh, atuin, zoxide, nvm)
- Changes trigger a GitHub issue with diff details for human review

This ensures:
- **Security**: Third-party changes are reviewed before deployment
- **Velocity**: Internal tool updates are deployed automatically
- **Auditability**: All changes tracked via git commits

### Production Smoke Tests (`production-smoke.yml`)

Validates deployments on real environments:

```yaml
# Runs after deployment
jobs:
  smoke:
    - Fetches install.sh from production URL
    - Verifies checksum matches repository
    - Validates shell syntax
    - Confirms no uncommitted drift
```

### Playwright E2E Tests (`playwright.yml`)

Full browser testing of the wizard website:

```yaml
# Runs on PR to main
browsers:
  - Chromium
  - Firefox
  - WebKit
  - Mobile Chrome
  - Mobile Safari

tests:
  - Wizard flow completion
  - Step navigation
  - Copy button functionality
  - Responsive design
```

---

## VPS Providers

ACFS works on any Ubuntu VPS with SSH key login. Here are recommended providers optimized for multi-agent workloads.

> **Why 48-64GB RAM?** Each AI coding agent uses ~2GB RAM. To run 10-20+ agents simultaneously, you need 48GB+ RAM. Don't bottleneck a $400+/month AI investment to save $20 on hosting.

### Contabo (Best Value — Top Pick)

| Plan | RAM | vCPU | Storage | Price | Notes |
|------|-----|------|---------|-------|-------|
| **Cloud VPS 50** | 64GB | 16 | 400GB NVMe | ~$56/mo (US) | **Recommended** — Best for serious multi-agent work |
| Cloud VPS 40 | 48GB | 12 | 300GB NVMe | ~$36/mo (US) | Budget option, still comfortable |

- Best specs-to-price ratio on the market
- Month-to-month pricing, no commitment required
- US datacenter pricing includes ~$10/month premium

### OVH (Great Alternative)

| Plan | RAM | vCore | Storage | Price | Notes |
|------|-----|-------|---------|-------|-------|
| **VPS-5** | 64GB | 16 | 320GB NVMe | ~$40/mo | **Recommended** — Great EU and US datacenters |
| VPS-4 | 48GB | 12 | 240GB NVMe | ~$26/mo | Budget option |

- Anti-DDoS included
- Month-to-month, 5-15% discount for longer commitments
- Typically faster activation than Contabo

### Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| **OS** | Ubuntu 22.04+ (auto-upgraded) | Ubuntu 25.10 |
| **RAM** | 32GB (tight) | 48-64GB |
| **Storage** | 250GB NVMe SSD | 300GB+ NVMe SSD |
| **CPU** | 12 vCPU | 16 vCPU |
| **Price** | ~$26/mo | ~$40-56/mo |

### Other Providers

Any provider with Ubuntu VPS and SSH key login works. The wizard at [agent-flywheel.com](https://agent-flywheel.com) has step-by-step guides.

### Provider Setup Guides

ACFS includes detailed step-by-step guides for each supported provider in `scripts/providers/`:

| Provider | Guide | Key Sections |
|----------|-------|--------------|
| **Contabo** | `contabo.md` | Account creation, plan selection, data center choice, SSH key setup |
| **OVH** | `ovh.md` | Control panel navigation, instance configuration, networking |
| **Hetzner** | `hetzner.md` | Project setup, firewall rules, console access |

Each guide includes:
- **Screenshots** for every step (in `scripts/providers/screenshots/`)
- **Pricing breakdowns** with recommendations
- **Region selection** guidance (latency, privacy)
- **SSH key** configuration specific to that provider
- **Troubleshooting** for common provisioning issues

**Provider Comparison:**

| Aspect | Contabo | OVH | Hetzner |
|--------|---------|-----|---------|
| Best For | Maximum value | EU data residency | German engineering |
| Provisioning | 1-3 hours | 5-30 minutes | 2-10 minutes |
| Support | Email only | Phone + chat | 24/7 ticket system |
| Data Centers | EU, US, Asia | Global | EU only |
| Payment | Monthly | Hourly or monthly | Hourly or monthly |

**Recommendation Flow:**
1. **Budget**: Contabo (best specs per dollar)
2. **Speed**: Hetzner (instant provisioning)
3. **Support**: OVH (phone support available)
4. **Privacy**: Any EU provider (GDPR compliance)

---

## Project Structure

```
agentic_coding_flywheel_setup/
├── README.md                     # This file
├── AGENTS.md                     # Development guidelines
├── VERSION                       # Current version (0.2.0)
├── install.sh                    # Main installer entry point
├── acfs.manifest.yaml            # Canonical tool manifest (510 lines)
├── checksums.yaml                # SHA256 hashes for upstream scripts
├── package.json                  # Root monorepo config
│
├── apps/
│   └── web/                      # Next.js 16 wizard website
│       ├── app/                  # App Router pages
│       │   ├── layout.tsx        # Root layout
│       │   ├── page.tsx          # Landing page
│       │   └── wizard/           # Wizard step pages
│       ├── components/           # UI components
│       └── lib/                  # Utilities
│
├── packages/
│   ├── manifest/                 # Manifest parser + generator
│   │   └── src/
│   │       ├── parser.ts         # YAML parsing
│   │       ├── schema.ts         # Zod validation schemas
│   │       ├── types.ts          # TypeScript types
│   │       ├── utils.ts          # Helper functions
│   │       └── generate.ts       # Script generator
│   ├── installer/                # Installer helper scripts
│   └── onboard/                  # Onboard TUI source
│
├── acfs/                         # Files deployed to ~/.acfs/
│   ├── zsh/
│   │   └── acfs.zshrc            # Shell configuration
│   ├── tmux/
│   │   └── tmux.conf             # Tmux configuration
│   └── onboard/
│       ├── onboard.sh            # Onboarding TUI script
│       └── lessons/              # Tutorial markdown (11 files)
│
├── scripts/
│   ├── lib/                      # Installer bash libraries
│   │   ├── logging.sh            # Console output
│   │   ├── security.sh           # HTTPS + checksum verification
│   │   ├── os_detect.sh          # OS detection
│   │   ├── user.sh               # User management
│   │   ├── zsh.sh                # Shell setup
│   │   ├── update.sh             # Update command logic
│   │   ├── gum_ui.sh             # Enhanced UI
│   │   ├── cli_tools.sh          # Tool installation
│   │   └── doctor.sh             # Health checks
│   ├── generated/                # Auto-generated from manifest
│   │   ├── install_base.sh       # Base packages
│   │   ├── install_shell.sh      # Shell tools
│   │   ├── install_cli.sh        # CLI tools
│   │   ├── install_lang.sh       # Language runtimes
│   │   ├── install_agents.sh     # AI coding agents
│   │   ├── install_cloud.sh      # Cloud CLIs
│   │   ├── install_stack.sh      # Dicklesworthstone stack
│   │   ├── install_all.sh        # Master installer
│   │   └── doctor_checks.sh      # Verification checks
│   ├── providers/                # VPS provider guides
│   │   ├── ovh.md
│   │   ├── contabo.md
│   │   └── hetzner.md
│   └── sync/
│       └── sync_ntm_palette.sh   # Sync NTM command palette
│
├── .github/
│   └── workflows/
│       ├── installer.yml         # ShellCheck + Ubuntu matrix tests
│       └── website.yml           # Next.js build + deploy
│
└── tests/
    └── vm/
        └── test_install_ubuntu.sh # Docker integration test
```

---

## Development

### Website Development

```bash
cd apps/web
bun install           # Install dependencies
bun run dev           # Dev server at http://localhost:3000
bun run build         # Production build
bun run lint          # Lint check
bun run type-check    # TypeScript check
```

### Manifest Development

```bash
cd packages/manifest
bun install           # Install dependencies
bun run generate      # Generate installer scripts
bun run generate:dry  # Preview without writing files
```

### Installer Testing

```bash
# Local lint
shellcheck install.sh scripts/lib/*.sh

# Full installer integration test (Docker, same as CI)
./tests/vm/test_install_ubuntu.sh
```

### Security Verification

```bash
# Print all upstream URLs
./scripts/lib/security.sh --print

# Verify all checksums
./scripts/lib/security.sh --verify

# Update checksums after reviewing upstream changes
./scripts/lib/security.sh --update-checksums > checksums.yaml
```

### Manifest Validation

The manifest parser includes comprehensive validation beyond basic schema checking:

**Validation Error Codes:**

| Code | Description |
|------|-------------|
| `MISSING_DEPENDENCY` | Module references non-existent dependency |
| `DEPENDENCY_CYCLE` | Circular dependency detected (A→B→C→A) |
| `PHASE_VIOLATION` | Module runs before its dependencies |
| `FUNCTION_NAME_COLLISION` | Two modules generate same bash function |
| `RESERVED_NAME_COLLISION` | Module uses reserved identifier |
| `INVALID_VERIFIED_INSTALLER_RUNNER` | Runner not in allowlist (bash/sh only) |

**Running Validation:**
```bash
cd packages/manifest
bun run validate              # Full validation
bun run validate --verbose    # Show all checks
```

**Cycle Detection Algorithm:**
```
Tarjan's strongly connected components (SCC):
1. DFS with discovery/low-link tracking
2. Identify SCCs with size > 1 as cycles
3. Report cycle path for human debugging
```

### Test Harness

ACFS includes a comprehensive test harness (`tests/vm/lib/test_harness.sh`) for integration testing:

```bash
# Source the harness
source tests/vm/lib/test_harness.sh

# Initialize test suite
harness_init "ACFS Installation Tests"

# Create test sections
harness_section "Phase 1: Base Packages"

# Run commands with automatic logging
harness_run "Installing curl" apt install -y curl

# Assert results
harness_pass "curl installed successfully"
harness_fail "curl installation failed"
harness_skip "Skipping optional test"

# Generate summary
harness_summary  # Outputs: 15 passed, 0 failed, 2 skipped
```

**Test Files:**

| Test | Purpose |
|------|---------|
| `test_install_ubuntu.sh` | Full Docker-based installation |
| `test_acfs_update.sh` | Update mechanism validation |
| `bootstrap_offline_checks.sh` | Offline system readiness |
| `resume_checks.sh` | State resume validation |
| `selection_checks.sh` | Module selection unit tests |
| `selection_e2e.sh` | End-to-end selection flow |

**Running Tests:**
```bash
# Full Docker integration test
./tests/vm/test_install_ubuntu.sh

# Selection logic tests
./tests/vm/selection_checks.sh

# Web E2E tests
./tests/web/run_e2e.sh
```

### Sync Scripts

Sync scripts keep ACFS documentation aligned with upstream projects:

```bash
# Sync NTM command palette from upstream
./scripts/sync/sync_ntm_palette.sh

# Check if update available (without downloading)
./scripts/sync/sync_ntm_palette.sh --check
```

**Current Sync Sources:**

| Script | Source | Destination |
|--------|--------|-------------|
| `sync_ntm_palette.sh` | NTM repo `command_palette.md` | `acfs/onboard/docs/ntm/` |

All sync scripts use the security library for HTTPS enforcement and content hashing.

### Website Design System

The website uses a comprehensive design system (`apps/web/lib/design-tokens.ts`):

**Color Tokens (OKLCH Color Space):**
```typescript
// Perceptually uniform colors
colors: {
  cyan:    "oklch(0.75 0.18 195)",   // Primary accent
  pink:    "oklch(0.7 0.2 330)",     // Secondary accent
  purple:  "oklch(0.65 0.18 290)",   // Tertiary
  success: "oklch(0.72 0.19 145)",   // Green
  warning: "oklch(0.78 0.16 75)",    // Yellow
  error:   "oklch(0.65 0.22 25)",    // Red
}
```

**Shadow Tokens:**
```typescript
shadows: {
  cardHover: "0 20px 40px -12px oklch(0.75 0.18 195 / 0.15)",
  cardLifted: "0 25px 50px -12px oklch(0.75 0.18 195 / 0.2)",
  primaryGlow: "0 0 40px -8px oklch(0.75 0.18 195 / 0.3)",
}
```

**Animation Presets:**
```typescript
animations: {
  hover: { scale: 1.02, transition: { duration: 0.2 } },
  tap: { scale: 0.98 },
  fadeIn: { opacity: [0, 1], transition: { duration: 0.3 } },
}
```

**Accessibility:**
- Reduced motion support via `useReducedMotion` hook
- Semantic HTML structure
- ARIA labels on interactive elements
- Keyboard navigation support

### Requirements

- **Runtime:** Bun (not npm/yarn/pnpm)
- **Node:** Latest
- **Shell:** Bash 5+

---

## FAQ

### Why "Vibe Mode"?

Vibe mode is designed for **throwaway VPS environments** where velocity matters more than safety:
- Passwordless sudo eliminates friction
- Agent dangerous flags skip confirmation dialogs
- Pre-configured aliases for maximum speed

**Never use vibe mode on production or shared systems.**

### Can I use this on my local machine?

ACFS is designed for fresh Ubuntu VPS instances. While you *could* run it locally:
- It may conflict with existing configurations
- It assumes root/sudo access
- It's not designed for macOS or Windows

For local development, use the individual tools directly.

### What if the installer fails?

The installer is **checkpointed**. Simply re-run it:
```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh?$(date +%s)" | bash -s -- --yes --mode vibe
```

It will skip already-completed phases and resume where it left off.

### How do I update tools?

Use the built-in update command:
```bash
acfs update                  # Update all standard components
acfs update --stack          # Include Dicklesworthstone stack
acfs update --agents-only    # Just update AI agents
```

### How do I uninstall?

There's no uninstall script. To reset:
1. Delete the VPS instance
2. Create a new one
3. Run the installer fresh

This is intentional—ACFS is designed for ephemeral VPS environments.

### Can I customize which tools are installed?

Currently, ACFS installs the full suite. Future versions will support:
- Manifest-based tool selection
- Interactive mode for choosing components
- Modular installation scripts

---

## Why ACFS Exists

### The Problem: The Agentic Coding Barrier

The rise of AI coding agents (Claude Code, Codex CLI, Gemini CLI) has created a new paradigm in software development. These agents can write code, debug issues, and even architect solutions—but only if they have the right environment.

**The barrier isn't the agents themselves.** It's the **hours of setup** required to create an environment where agents can actually be productive:

```
┌────────────────────────────────────────────────────────────────────────────┐
│  TIME INVESTMENT WITHOUT ACFS                                               │
│                                                                              │
│  VPS Setup ..................... 30-60 min                                   │
│  Shell Configuration ........... 20-30 min                                   │
│  Language Runtimes ............. 30-45 min                                   │
│  Dev Tools ..................... 20-30 min                                   │
│  Agent Installation ............ 15-30 min                                   │
│  Agent Configuration ........... 20-40 min                                   │
│  Coordination Tools ............ 30-60 min                                   │
│  Troubleshooting ............... 30-120 min                                  │
│  ─────────────────────────────────────────                                   │
│  TOTAL: 3-7 hours (and that's if everything works)                          │
│                                                                              │
│  TIME INVESTMENT WITH ACFS                                                   │
│                                                                              │
│  Run one command ............... 25-30 min                                   │
│  ─────────────────────────────────────────                                   │
│  TOTAL: 30 minutes                                                           │
└────────────────────────────────────────────────────────────────────────────┘
```

**ACFS eliminates this barrier entirely.** One command, 30 minutes, fully configured.

### The Deeper Problem: Beginners Can't Start

For experienced developers, the setup is tedious but doable. For beginners—the people who would benefit *most* from AI coding assistance—it's an insurmountable wall:

- What's SSH? How do I generate keys?
- What's a VPS? How do I rent one?
- What's a terminal? Which one should I use?
- How do I connect to a remote server?
- What are all these tools and why do I need them?

The [wizard website at agent-flywheel.com](https://agent-flywheel.com) solves this by providing:

1. **Absolute beginner guidance** — Explains every concept in plain English
2. **OS-specific instructions** — Detects Mac vs Windows, shows the right commands
3. **Visual confirmations** — Checkboxes for each step, copy buttons for commands
4. **Troubleshooting help** — Expandable sections for common problems
5. **Progress persistence** — Resume where you left off across browser sessions

---

## The 10x Multiplier Effect

ACFS isn't just a collection of tools—it's a **carefully curated system** where each component amplifies the others. The value isn't additive; it's multiplicative.

### Tool Synergy Model

```
                              ┌─────────────────┐
                              │   PRODUCTIVITY  │
                              │   MULTIPLIER    │
                              └────────┬────────┘
                                       │
         ┌─────────────────────────────┼─────────────────────────────┐
         │                             │                             │
         ▼                             ▼                             ▼
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│  ENVIRONMENT    │         │    AGENTS       │         │  COORDINATION   │
│  LAYER          │         │    LAYER        │         │  LAYER          │
├─────────────────┤         ├─────────────────┤         ├─────────────────┤
│ • zsh + p10k    │────────▶│ • Claude Code   │────────▶│ • Agent Mail    │
│ • tmux          │         │ • Codex CLI     │         │ • NTM           │
│ • Modern CLI    │         │ • Gemini CLI    │         │ • SLB + DCG     │
│ • Language VMs  │         │                 │         │ • Beads Viewer  │
└─────────────────┘         └─────────────────┘         └─────────────────┘
         │                             │                             │
         │    Each layer enables       │    Agents become more      │
         │    the next layer           │    powerful together       │
         └─────────────────────────────┴─────────────────────────────┘
```

### Why These Specific Tools?

Every tool in ACFS earns its place through **concrete productivity gains**:

| Tool | Individual Value | Synergy Value |
|------|-----------------|---------------|
| **tmux** | Persistent sessions | Agents can work while you're disconnected |
| **NTM** | Organized sessions | One command spawns 10 agents in named windows |
| **Agent Mail** | Message passing | Agents coordinate without conflicts |
| **SLB** | Two-person rule | Dangerous operations require confirmation |
| **DCG** | Command guardrails | Blocks destructive commands before execution |
| **Beads Viewer** | Task tracking | Agents can see project state, avoid rework |
| **atuin** | Shell history | Search commands across sessions, share patterns |
| **zoxide** | Smart cd | `z proj` beats `cd ~/projects/my-long-name` |
| **ripgrep** | Fast search | Agents find code 100x faster than grep |
| **fzf** | Fuzzy finding | Interactive selection instead of typing paths |

### The Compounding Effect

A single agent with basic tooling is useful. Three agents with:
- A shared project structure
- Coordination via Agent Mail
- Orchestration via NTM
- Safety guardrails via SLB
- DCG guard hook (blocks destructive commands before execution)
- Task visibility via Beads

...can accomplish in one day what would take a solo developer a week.

Tip: run `acfs services-setup` to configure logins, and enable DCG for destructive-command protection.

**This is the flywheel effect in action.** Better tools → more capable agents → more code shipped → better understanding of what tools are needed → better tools.

---

## Design Algorithms & Decisions

ACFS implements several algorithmic patterns that ensure reliability and maintainability.

### Idempotency Algorithm

Every installation function follows the **check-before-install** pattern:

```bash
install_tool() {
    if command_exists "tool"; then
        log_success "tool already installed"
        return 0
    fi

    # ... installation logic ...

    if command_exists "tool"; then
        log_success "tool installed successfully"
        return 0
    else
        log_error "tool installation failed"
        return 1
    fi
}
```

This guarantees:
1. **Safe re-runs** — Running the installer twice doesn't break anything
2. **Resume capability** — Failures don't require starting over
3. **Declarative intent** — The end state is defined, not the transition

### Checksum Verification Algorithm

The security system uses **content-addressable verification**:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  VERIFICATION FLOW                                                       │
│                                                                          │
│  1. Download script to memory (not disk)                                 │
│  2. Calculate SHA256 of downloaded content                               │
│  3. Compare against stored hash in checksums.yaml                        │
│  4. If match → execute                                                   │
│  5. If mismatch → refuse execution, report discrepancy                   │
│                                                                          │
│  Key insight: We verify CONTENT, not just transport                      │
│  (HTTPS only protects the channel, not the content at source)            │
└─────────────────────────────────────────────────────────────────────────┘
```

### Manifest-Driven Generation

The generator uses a **template expansion** pattern:

1. **Parse** — Read YAML manifest, validate with Zod schemas
2. **Transform** — Convert manifest entries to installation functions
3. **Group** — Organize by category (base, shell, cli, lang, agents, etc.)
4. **Generate** — Emit Bash scripts with consistent structure
5. **Verify** — Generate doctor checks from verification commands

This ensures the manifest is the **single source of truth**—no drift between documentation, installer, and verification.

### Code Generator Architecture

The manifest generator (`packages/manifest/src/generate.ts`) is a sophisticated TypeScript program that transforms YAML into bash:

**Input Processing:**
```typescript
// 1. Parse YAML with validation
const manifest = parseManifestFile(MANIFEST_PATH);  // Zod-validated

// 2. Load checksums for verified installers
const checksums = parseYaml(readFileSync(CHECKSUMS_PATH));

// 3. Topological sort for dependency order
const sorted = sortModulesByInstallOrder(manifest.modules);
```

**Security-First Code Generation:**
```typescript
// Shell-safe quoting (prevents command injection)
function shellQuote(s: string): string {
  return `'${s.replace(/'/g, "'\\''")}'`;
}

// Allowlisted runners only (belt-and-suspenders)
const ALLOWED_RUNNERS = ['bash', 'sh'] as const;

// Verified installer pipe construction
function buildVerifiedInstallerPipe(module: Module, checksums: Checksums): string {
  // Generates: curl -fsSL "$URL" | verify_checksum "$SHA256" | bash
}
```

**Output Structure:**
```
scripts/generated/
├── install_base.sh        # Base system packages (apt)
├── install_users.sh       # User normalization (ubuntu user)
├── install_filesystem.sh  # Directory structure (/data/projects)
├── install_shell.sh       # zsh + oh-my-zsh + p10k
├── install_cli.sh         # ripgrep, tmux, fzf, lazygit, etc.
├── install_network.sh     # Tailscale
├── install_lang.sh        # bun, uv, rust, go
├── install_tools.sh       # ast-grep, atuin, zoxide
├── install_agents.sh      # claude, codex, gemini
├── install_db.sh          # PostgreSQL 18, Vault
├── install_cloud.sh       # wrangler, supabase, vercel
├── install_stack.sh       # Dicklesworthstone 10-tool stack + utilities
├── install_acfs.sh        # ACFS config deployment
├── install_all.sh         # Orchestration helper
├── doctor_checks.sh       # Health verification
└── manifest_index.sh      # Module metadata arrays
```

**Generated Script Structure:**
```bash
#!/usr/bin/env bash
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT

install_module_id() {
    acfs_require_contract "module.id"  # Validate environment

    if run_installed_check "module.id"; then
        log_step "module.id already installed"
        return 0
    fi

    set_phase "Installing module..."
    run_as_target_shell <<'HEREDOC'
        # Installation commands from manifest
    HEREDOC

    verify_module "module.id"  # Post-install checks
}
```

**Regeneration:**
```bash
cd packages/manifest
bun run generate           # Full regeneration
bun run generate:dry       # Preview without writing
```

### Generated Manifest Index

The generator produces `manifest_index.sh`, a comprehensive bash metadata file that provides programmatic access to manifest data at runtime:

**Associative Arrays:**
```bash
# Module metadata lookup
declare -A ACFS_MODULE_DESCRIPTION
ACFS_MODULE_DESCRIPTION["lang.bun"]="Bun JavaScript/TypeScript runtime..."
ACFS_MODULE_DESCRIPTION["agents.claude"]="Claude Code CLI agent..."

# Phase mapping (determines install order)
declare -A ACFS_MODULE_PHASE
ACFS_MODULE_PHASE["base.apt"]="1"
ACFS_MODULE_PHASE["lang.bun"]="3"
ACFS_MODULE_PHASE["agents.claude"]="5"

# Dependency relationships (space-separated)
declare -A ACFS_MODULE_DEPENDENCIES
ACFS_MODULE_DEPENDENCIES["agents.claude"]="lang.bun base.system"

# Generated function name mapping
declare -A ACFS_MODULE_FUNCTION
ACFS_MODULE_FUNCTION["lang.bun"]="install_lang_bun"

# Category grouping
declare -A ACFS_MODULE_CATEGORY
ACFS_MODULE_CATEGORY["lang.bun"]="lang"

# Default inclusion in install
declare -A ACFS_MODULE_DEFAULT
ACFS_MODULE_DEFAULT["lang.bun"]="true"
ACFS_MODULE_DEFAULT["db.postgres18"]="true"
```

**Runtime Query Functions:**
```bash
# Get all modules in a category
get_modules_by_category "agents"  # Returns: agents.claude agents.codex agents.gemini

# Check if module is default-installed
is_default_module "tools.vault"   # Returns: true

# Get installation phase
get_module_phase "stack.ntm"      # Returns: 6
```

**Use Cases:**
- `acfs doctor` queries module metadata for health checks
- `install.sh --list-modules` displays available modules
- `--skip <module>` validates module existence before skipping
- `--only-phase <n>` uses phase mapping for selective installs

The manifest index bridges the TypeScript generator with bash runtime, enabling sophisticated module selection logic while keeping the bash scripts simple.

### Progressive Disclosure in the Wizard

The wizard website implements **progressive disclosure** for complexity management:

```
Level 1: Core instructions (visible by default)
├── Copy this command
├── Paste in terminal
└── Press Enter

Level 2: Troubleshooting (expandable)
├── "Permission denied" → fix instructions
├── "Command not found" → prerequisites
└── "Connection refused" → diagnostics

Level 3: Deep explanations (collapsible "Beginner Guide")
├── What is SSH?
├── What is a VPS?
├── Why these specific steps?
└── What happens under the hood?
```

This allows beginners to get deep context when needed, while experts can skip straight to the commands.

---

## Multi-Agent Orchestration Model

ACFS is designed for **multi-agent workflows** where several AI coding agents work on the same project simultaneously.

### The Coordination Problem

Without coordination, multiple agents cause chaos:
- **File conflicts** — Two agents edit the same file
- **Duplicated work** — Agents solve the same problem independently
- **Communication gaps** — No visibility into what others are doing
- **Safety risks** — Dangerous operations without oversight

### The ACFS Solution Stack

```
┌───────────────────────────────────────────────────────────────────────────┐
│                         AGENT COORDINATION LAYER                           │
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│  │ Agent Mail  │  │    NTM      │  │  SLB + DCG  │  │   Beads     │       │
│  │ (Messaging) │  │ (Sessions)  │  │ (Safety)    │  │ (Tasks)     │       │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘       │
│         │                │                │                │               │
│         │   ┌────────────┴────────────────┴────────────────┘               │
│         │   │                                                              │
│         ▼   ▼                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │                      FILE RESERVATION SYSTEM                          │ │
│  │                                                                        │ │
│  │  Agent A reserves: src/auth/**                                         │ │
│  │  Agent B reserves: src/api/**                                          │ │
│  │  Agent C reserves: tests/**                                            │ │
│  │                                                                        │ │
│  │  → No conflicts, parallel progress                                     │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────┘
```

### Agent Communication Patterns

**1. Direct Messaging (Agent Mail)**
```
Agent A → Agent B: "I finished the auth module, ready for API integration"
Agent B → Agent A: "ACK, starting API integration with auth dependency"
```

**2. Broadcast Updates (Thread Summaries)**
```
Thread: "Sprint 23 Tasks"
├── Agent A: "Claimed user-registration feature"
├── Agent B: "Claimed api-endpoints feature"
├── Agent C: "Claimed test-coverage task"
└── All agents see project state
```

**3. File Reservations (Conflict Prevention)**
```
Agent A: reserve_paths(["src/auth/*"], exclusive=true, ttl=3600)
Agent B: reserve_paths(["src/auth/*"]) → CONFLICT: held by Agent A
Agent B: reserve_paths(["src/api/*"]) → GRANTED
```

### The NTM Orchestration Pattern

Named Tmux Manager (NTM) enables the **one-command swarm spawn**:

```bash
# Spawn 10 agents, each in a named tmux window
ntm spawn \
  --count 10 \
  --prefix "agent-" \
  --command "claude --dangerously-skip-permissions"
```

Result:
```
tmux session: acfs-swarm
├── agent-1: Claude working on auth
├── agent-2: Claude working on api
├── agent-3: Claude working on tests
├── agent-4: Codex reviewing PRs
├── agent-5: Gemini writing docs
└── ...
```

---

## Philosophy

### The Flywheel

The "Agentic Coding Flywheel" is a virtuous cycle:

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│    Better Environment → More Agent Productivity →               │
│    More Code Written → Better Understanding →                   │
│    Better Prompts → Better Environment                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

ACFS kicks off this flywheel by providing the **best possible starting environment** for agentic coding.

### Design Principles

1. **Beginner-Friendly, Expert-Fast:** The wizard guides beginners; the one-liner serves experts.

2. **Vibe-First:** Optimize for velocity in throwaway environments. Safety features exist in safe mode.

3. **Idempotent:** Re-run without fear. The installer handles already-installed tools gracefully.

4. **Single Source of Truth:** The manifest defines everything. Installer scripts are generated from it.

5. **Security by Default:** HTTPS enforcement, checksum verification, no blind `curl | bash`.

6. **Modern Defaults:** Latest versions, modern tools, optimal configurations out of the box.

---

## The Vibe Coding Manifesto

"Vibe coding" isn't just a catchy name—it's a philosophy about how humans and AI should collaborate on software development.

### What Is Vibe Coding?

Vibe coding is the practice of **directing AI agents to write code while you focus on intent, architecture, and quality**. Instead of typing every line yourself, you:

1. **Describe what you want** in natural language
2. **Review and guide** the agent's output
3. **Iterate rapidly** through multiple approaches
4. **Ship faster** while maintaining quality

The "vibe" comes from the flow state you enter when you're no longer fighting syntax, boilerplate, or implementation details—you're just vibing with your AI partner.

### The Three Laws of Vibe Coding

**1. Velocity Over Ceremony**

Traditional development is ceremony-heavy: create branch, write tests first, implement, refactor, write docs, create PR, wait for review, merge, deploy. Each step has friction.

Vibe coding inverts this: ship fast, iterate faster. The AI handles boilerplate while you focus on the 10% that requires human judgment.

```
Traditional: Think → Plan → Implement → Test → Document → Ship
Vibe:        Describe → Generate → Verify → Ship → Iterate
```

**2. Throwaway Environments Enable Boldness**

The magic of vibe coding happens on **ephemeral VPS instances**. When your environment is disposable:
- You can experiment without fear
- Catastrophic failures are just "rebuild the VPS"
- Agents can have dangerous permissions (they can't break what's disposable)
- You focus on output, not on protecting your setup

This is why ACFS's "vibe mode" enables passwordless sudo and dangerous agent flags—on a $5/month throwaway VPS, there's nothing worth protecting.

**3. Multi-Agent Is The Default**

One agent is useful. Three agents working in parallel are transformative.

Vibe coding assumes you'll run multiple agents simultaneously:
- Claude for complex reasoning and architecture
- Codex for rapid prototyping and refactoring
- Gemini for documentation and research

ACFS provides the coordination layer (Agent Mail, NTM, SLB) that makes this practical.

### The Anti-Patterns

Vibe coding is **NOT**:
- Blindly accepting agent output without review
- Abandoning tests and quality standards
- Ignoring security on production systems
- Treating agents as replacements for understanding

The goal is **augmented human judgment**, not abdicated human judgment.

### When NOT to Vibe Code

- Production systems with real users
- Security-critical infrastructure
- Anything involving credentials or secrets
- Long-running servers (use safe mode)
- Shared team environments (use coordination tools)

Vibe coding is for **greenfield development, prototyping, experimentation, and learning**. Use ACFS's safe mode for everything else.

---

## State Machine & Checkpoint System

ACFS implements a robust **checkpoint-based state machine** that enables reliable resume-from-failure. This section explains how it works under the hood.

### State File Format

Progress is tracked in `~/.acfs/state.json`:

```json
{
  "schema_version": 3,
  "started_at": "2024-12-21T10:30:00Z",
  "last_updated": "2024-12-21T10:45:23Z",
  "mode": "vibe",
  "completed_phases": ["user_setup", "filesystem", "shell_setup"],
  "current_phase": "cli_tools",
  "current_step": "Installing ripgrep",
  "failed_phase": null,
  "failed_step": null,
  "failed_error": null,
  "skipped_phases": [],
  "phase_timings": {
    "user_setup": 12,
    "filesystem": 8,
    "shell_setup": 145
  }
}
```

### Phase State Transitions

Each phase goes through a defined state machine:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE STATE MACHINE                                                         │
│                                                                              │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐                             │
│  │ PENDING  │────▶│ RUNNING  │────▶│ COMPLETE │                             │
│  └──────────┘     └────┬─────┘     └──────────┘                             │
│       │                │                                                     │
│       │                ▼                                                     │
│       │          ┌──────────┐     ┌──────────┐                              │
│       │          │  FAILED  │────▶│  RETRY   │──┐                           │
│       │          └──────────┘     └──────────┘  │                           │
│       │                                ▲        │                           │
│       │                                └────────┘                           │
│       │                                                                      │
│       └──────────────────────▶┌──────────┐                                  │
│          (--skip flag)        │ SKIPPED  │                                  │
│                               └──────────┘                                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Resume Logic

When the installer runs, it follows this decision tree:

```python
def should_run_phase(phase_id):
    state = load_state_file()

    if phase_id in state.completed_phases:
        return SKIP  # Already done

    if phase_id in state.skipped_phases:
        return SKIP  # User explicitly skipped

    if state.failed_phase == phase_id:
        if user_wants_retry():
            return RUN  # Retry failed phase
        else:
            return ABORT  # Don't continue past failure

    return RUN  # Normal execution
```

### Atomic State Updates

State file updates are **atomic** to prevent corruption from interrupted writes:

```bash
# Write to temp file first
echo "$new_state" > "$state_file.tmp.$$"

# Atomic rename (POSIX guarantees this is atomic on same filesystem)
mv "$state_file.tmp.$$" "$state_file"
```

This ensures the state file is never partially written, even if the process is killed mid-update.

### Recovery from Common Failures

| Failure Type | Detection | Recovery |
|--------------|-----------|----------|
| Network timeout | curl exit code 28 | Retry with exponential backoff |
| APT lock held | `/var/lib/dpkg/lock` exists | Wait and retry up to 60s |
| Disk full | df check before write | Abort with clear error |
| Out of memory | OOM killer | Resume picks up from last phase |
| SSH disconnect | N/A (session dies) | Resume on reconnect |
| Ctrl+C | Trap handler | Clean exit, state preserved |

### Phase Timings & Performance

The state file tracks how long each phase takes. This enables:
- Accurate progress estimation ("Phase 4/9, ~3 minutes remaining")
- Performance regression detection across ACFS versions
- Identifying slow phases that need optimization

---

## Error Handling & Recovery Patterns

ACFS is designed to **fail gracefully and recover automatically**. This section documents the error handling patterns used throughout the codebase.

### The Try-Step Pattern

Every installation step is wrapped in a `try_step` function that captures errors without aborting:

```bash
try_step "Installing ripgrep" install_ripgrep
```

This pattern provides:
- **Context tracking**: Errors include step name, not just exit code
- **Graceful continuation**: Non-critical failures don't abort the whole install
- **Structured reporting**: Failures are collected and reported at the end

### Network Resilience

Network operations implement **exponential backoff with jitter**:

```bash
retry_with_backoff() {
    local max_attempts=5
    local delay=1

    for attempt in $(seq 1 $max_attempts); do
        if "$@"; then
            return 0
        fi

        # Exponential backoff: 1s, 2s, 4s, 8s, 16s
        # With jitter: ±25% randomization
        local jitter=$(( (RANDOM % 50 - 25) * delay / 100 ))
        sleep $((delay + jitter))
        delay=$((delay * 2))
    done

    return 1
}
```

### APT Lock Handling

The most common installation failure is APT lock contention (another process using apt):

```bash
wait_for_apt_lock() {
    local max_wait=60
    local waited=0

    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        if [[ $waited -ge $max_wait ]]; then
            log_error "APT lock held for >60s, aborting"
            return 1
        fi
        log_detail "Waiting for apt lock... (${waited}s)"
        sleep 5
        waited=$((waited + 5))
    done

    return 0
}
```

### Graceful Degradation

When a non-critical tool fails to install, ACFS continues with a warning:

```
Category: Critical    → Failure aborts installation
          Standard    → Failure logged, installation continues
          Optional    → Failure noted, no warning

Examples:
  Critical: bun, zsh, git (can't proceed without these)
  Standard: ast-grep, lazygit (nice to have, not blocking)
  Optional: atuin, zoxide (pure enhancements)
```

### The Error Report

At the end of installation (or on abort), ACFS generates a structured error report:

```
═══════════════════════════════════════════════════════════════════════════════
  INSTALLATION REPORT
═══════════════════════════════════════════════════════════════════════════════

  Status: PARTIAL SUCCESS (8/9 phases completed)

  ✓ Completed Phases:
    • User Setup (12s)
    • Filesystem (8s)
    • Shell Setup (2m 25s)
    • CLI Tools (4m 12s)
    • Languages (3m 45s)
    • Agents (1m 30s)
    • Cloud (2m 10s)
    • Stack (5m 20s)

  ✗ Failed Phase: Finalize
    Step: Configuring tmux
    Error: tmux.conf syntax error on line 42

  Suggested Fix:
    Check ~/.acfs/tmux/tmux.conf for syntax errors
    Then run: curl ... | bash -s -- --yes --mode vibe --resume

═══════════════════════════════════════════════════════════════════════════════
```

---

## Troubleshooting Guide

This section covers common issues and their solutions. For quick debugging, start with `acfs doctor`.

### Installation Fails Immediately

**Symptom**: Installer exits within seconds of starting.

**Common Causes & Solutions**:

| Cause | Detection | Fix |
|-------|-----------|-----|
| Not running as root | "Permission denied" | `sudo bash` or use `sudo` in curl command |
| Not Ubuntu | "Unsupported OS" | ACFS only supports Ubuntu 22.04+ |
| No internet | "curl: (6) Could not resolve host" | Check DNS, try `ping google.com` |
| Old bash | Syntax errors | Upgrade to bash 4+ |

### APT Lock Errors

**Symptom**: `E: Could not get lock /var/lib/dpkg/lock-frontend`

**Solutions**:

1. **Wait for unattended-upgrades** (most common on fresh VPS):
   ```bash
   # Check what's holding the lock
   sudo lsof /var/lib/dpkg/lock-frontend

   # Wait for it to finish (usually 2-3 minutes on fresh VPS)
   # Then re-run installer
   ```

2. **Kill stuck process** (if waiting doesn't help):
   ```bash
   sudo killall apt apt-get dpkg
   sudo dpkg --configure -a
   sudo apt-get update
   ```

### Shell Not Changing to zsh

**Symptom**: Still seeing bash prompt after install.

**Solutions**:

1. **Log out and back in** (the change happens at next login)

2. **Manually set shell**:
   ```bash
   chsh -s $(which zsh)
   # Then log out and back in
   ```

3. **Check shell was installed**:
   ```bash
   which zsh  # Should show /usr/bin/zsh
   cat /etc/shells  # zsh should be listed
   ```

### Agent Authentication Issues

**Claude Code**:
```bash
# Check auth status
claude --version
ls -la ~/.claude/  # or ~/.config/claude/

# Re-authenticate
claude  # Follow prompts
```

**Codex CLI**:
```bash
# Check auth status
codex --version

# Re-authenticate (uses ChatGPT account, not API key)
codex login
```

**Gemini CLI**:
```bash
# Check auth status
gemini --version

# Re-authenticate
gemini  # Follow Google login flow
```

### "Command Not Found" After Install

**Symptom**: `claude: command not found` even though install succeeded.

**Solutions**:

1. **Reload shell config**:
   ```bash
   source ~/.zshrc
   # Or start a new shell
   exec zsh
   ```

2. **Check PATH**:
   ```bash
   echo $PATH | tr ':' '\n' | grep -E "(bun|local|cargo)"
   # Should include: ~/.bun/bin, ~/.local/bin, ~/.cargo/bin
   ```

3. **Manual path fix**:
   ```bash
   export PATH="$HOME/.bun/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
   ```

### Tmux Configuration Errors

**Symptom**: Tmux won't start or shows config errors.

**Solutions**:

1. **Check syntax**:
   ```bash
   tmux source-file ~/.tmux.conf
   # Will show line number of any errors
   ```

2. **Reset to ACFS defaults**:
   ```bash
   cp ~/.acfs/tmux/tmux.conf ~/.tmux.conf
   ```

3. **Version mismatch** (old tmux, new config):
   ```bash
   tmux -V  # Check version
   # ACFS config requires tmux 3.0+
   ```

### Stack Tools Not Working

**Symptom**: `ntm`, `slb`, `dcg`, etc. not found or erroring.

**Solutions**:

1. **Reinstall stack**:
   ```bash
   acfs update --stack --force
   ```

2. **Check cargo install worked**:
   ```bash
   ls ~/.cargo/bin/  # Should contain ntm, slb, ru, etc.
   ls ~/.local/bin/  # dcg often installs here
   ```

3. **Rust not in path**:
   ```bash
   source ~/.cargo/env
   ```

### DCG Hook Issues

**Symptom**: DCG isn't blocking commands or Claude reports hook errors.

**Solutions**:

1. **Run the built-in health check**:
   ```bash
   dcg doctor
   ```

2. **Re-register the hook**:
   ```bash
   dcg install --force
   ```

3. **Verify hook registration**:
   ```bash
   grep -n dcg ~/.claude/settings.json ~/.config/claude/settings.json
   ```

4. **Reinstall if binary is missing**:
   ```bash
   which dcg  # Should return a path
   # If missing, reinstall:
   curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/destructive_command_guard/main/install.sh" | bash
   dcg install  # Register hook after reinstall
   ```

### Complete Reset

When all else fails, the nuclear option:

```bash
# Save any important files first!

# Backup ACFS state (recommended)
ts="$(date +%Y%m%d_%H%M%S)"
[ -d ~/.acfs ] && mv ~/.acfs ~/.acfs.backup."$ts"

# Backup installed configs (optional)
for f in ~/.zshrc ~/.tmux.conf ~/.p10k.zsh; do
  [ -f "$f" ] && mv "$f" "$f".backup."$ts"
done

# Re-run installer fresh
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh?$(date +%s)" | bash -s -- --yes --mode vibe --force-reinstall
```

---

## Security Threat Model

ACFS takes security seriously while acknowledging the inherent risks of `curl | bash` installation. This section documents our threat model and mitigations.

### What We Protect Against

| Threat | Mitigation |
|--------|------------|
| **Man-in-the-middle (MITM)** | HTTPS enforcement for all downloads |
| **Compromised upstream scripts** | SHA256 checksum verification |
| **Malicious package injection** | Official package sources only (apt, cargo, bun) |
| **Credential exposure** | No credentials stored in scripts or configs |
| **Privilege escalation** | Minimal sudo usage, explicit permission grants |
| **Persistent backdoors** | Ephemeral VPS model; start fresh if concerned |

### What We Don't Protect Against

| Threat | Why Not | Mitigation |
|--------|---------|------------|
| **Compromised GitHub** | Would require GitHub-level breach | Use release tags, verify commits |
| **Compromised upstream maintainers** | Can't verify humans | Trust + checksum verification |
| **Zero-day in installed tools** | Beyond our control | Keep tools updated, follow CVEs |
| **Physical VPS access** | Provider responsibility | Choose reputable providers |
| **Vibe mode abuse** | By design for throwaway VPS | Use safe mode on important systems |

### The `curl | bash` Debate

The `curl | bash` pattern is controversial. Critics argue:
- You're executing arbitrary code from the internet
- The download could be swapped mid-stream
- You can't audit before executing

Our response:
1. **HTTPS** prevents mid-stream swapping
2. **Checksums** verify content matches known-good versions
3. **Ephemeral environments** limit blast radius
4. **Open source** allows pre-audit of install.sh

For maximum security, you can:
```bash
# Download first, audit, then execute
curl -fsSL "https://..." -o install.sh
less install.sh  # Review the code
bash install.sh --yes --mode vibe
```

### Checksum Verification Deep Dive

Every upstream installer we fetch is verified against known-good checksums:

```yaml
# checksums.yaml excerpt
installers:
  bun:
    url: "https://bun.sh/install"
    sha256: "a1b2c3d4e5f6..."
    last_verified: "2024-12-15"
    notes: "Official Bun installer"
```

The verification process:

```
1. Download script to memory (not disk)
2. Calculate SHA256 of downloaded bytes
3. Compare against stored checksum
4. If match: execute
5. If mismatch: abort with warning
```

A mismatch could mean:
- Upstream released a new version (common, usually safe)
- Upstream was compromised (rare, investigate before updating)

Our update process:
1. Monitor upstream releases
2. Review changes in new installer versions
3. Update checksums only after manual review
4. Commit with descriptive message explaining what changed

### Vibe Mode Security Implications

Vibe mode (`--mode vibe`) enables:
- Passwordless sudo for ubuntu user
- `--dangerously-skip-permissions` for Claude
- `--dangerously-bypass-approvals-and-sandbox` for Codex
- `--yolo` for Gemini

This is **intentionally insecure for velocity**. Use only on:
- Throwaway VPS you don't care about
- Non-production environments
- Personal experimentation

Never on:
- Production servers
- Shared team infrastructure
- Systems with sensitive data
- Long-running servers

---

## Comparison to Alternatives

How does ACFS compare to other ways of setting up a development environment?

### vs. Manual Setup

| Aspect | Manual | ACFS |
|--------|--------|------|
| Time | 3-7 hours | 30 minutes |
| Consistency | Varies | Identical every time |
| Documentation | Your memory | This README |
| Resume on failure | Start over | Automatic |
| Updates | Manual each tool | `acfs update` |

**When to use manual**: When you need to understand every detail, or have highly specific requirements.

### vs. Dotfiles Repos

| Aspect | Dotfiles | ACFS |
|--------|----------|------|
| Scope | Configs only | Full tool installation |
| Portability | Mac/Linux | Ubuntu-focused |
| Maintenance | DIY | Maintained project |
| Agent focus | None | Core feature |

**When to use dotfiles**: When you already have tools installed and just want configs.

### vs. Nix/NixOS

| Aspect | Nix | ACFS |
|--------|-----|------|
| Reproducibility | Perfect | Good |
| Learning curve | Steep | Gentle |
| Rollback | Native | Manual |
| Complexity | High | Low |
| Adoption | Growing | Easy |

**When to use Nix**: When you need perfect reproducibility and are willing to invest in learning Nix.

### vs. DevContainers

| Aspect | DevContainers | ACFS |
|--------|--------------|------|
| Isolation | Container | Full VPS |
| Resource overhead | Container runtime | None |
| IDE integration | VSCode-centric | Terminal-native |
| Agent experience | Limited | Native |

**When to use DevContainers**: When you want isolated project environments within an existing machine.

### vs. Ansible/Terraform

| Aspect | Ansible/TF | ACFS |
|--------|------------|------|
| Scope | Infrastructure | Development env |
| Complexity | High | Low |
| Audience | DevOps | Developers |
| Learning curve | Steep | Gentle |

**When to use Ansible/Terraform**: When you're managing fleets of servers, not individual dev environments.

### The ACFS Sweet Spot

ACFS is optimal when you need:
- **Fast setup** of a complete agentic coding environment
- **Fresh Ubuntu VPS** as your target
- **AI coding agents** as primary tools
- **Throwaway/ephemeral** infrastructure mindset
- **Minimal configuration** to get started

---

## The Dicklesworthstone Stack Philosophy

The 10-tool stack included in ACFS isn't random—each tool addresses a specific problem discovered through extensive multi-agent development experience.

### The Problems

Running multiple AI coding agents simultaneously surfaces problems that don't exist with single-agent or no-agent development:

1. **Session chaos**: Agents in random terminal windows, no organization
2. **File conflicts**: Two agents editing the same file simultaneously
3. **No communication**: Agents can't coordinate or share findings
4. **Dangerous commands**: Agents running `git reset --hard` or `rm -rf` without oversight
5. **Lost context**: No memory of what agents learned previously
6. **Auth switching**: Different projects need different credentials
7. **History fragmentation**: Agent conversations scattered across systems
8. **No task visibility**: Hard to see what agents are working on
9. **Repo sprawl**: Dozens of repos, hard to keep synced, uncommitted work everywhere
10. **Visual debugging gaps**: Screenshots on phone, can't view in SSH terminal

### The Solutions

Each tool in the stack addresses specific problems:

| # | Tool | Problem Solved | Philosophy |
|---|------|----------------|------------|
| 1 | **NTM** | Session chaos | Named sessions create order from chaos |
| 2 | **Agent Mail** | No communication + file conflicts | Message-passing + file reservations |
| 3 | **UBS** | Dangerous commands | Guardrails with intelligence |
| 4 | **Beads Viewer** | No task visibility | Graph-based task dependencies |
| 5 | **CASS** | History fragmentation | Unified search across all agents |
| 6 | **CM** | Lost context | Procedural memory for agents |
| 7 | **CAAM** | Auth switching | One command to switch identities |
| 8 | **SLB** | Dangerous commands | Two-person rule for nuclear options |
| 9 | **DCG** | Dangerous git/fs commands | Sub-millisecond Claude Code hook blocks destructive operations |
| 10 | **RU** | Repo sprawl | Sync repos + AI-driven commit automation across dirty repos |

**Bundled Utilities:**

| Tool | Problem Solved | Philosophy |
|------|----------------|------------|
| **giil** | Visual debugging gaps | Download cloud images (iCloud, Dropbox, Google Photos) to terminal |
| **csctf** | Knowledge capture | Convert AI chat shares to searchable Markdown/HTML archives |

### The Synergy Effect

These tools are designed to work together:

```
NTM spawns agents → Agents register with Agent Mail →
Agent Mail reserves files → DCG blocks dangerous commands →
UBS validates operations → Beads tracks tasks →
CASS searches history → CM provides memory →
CAAM manages auth → SLB gates nuclear operations →
RU syncs repos and automates commits
```

No single tool is transformative alone. Together, they enable workflows that would otherwise be impossible:

- **10 agents working in parallel** without stepping on each other
- **Continuous operation** across SSH disconnects
- **Audit trails** for every agent action
- **Coordination** without manual intervention
- **Safety** without sacrificing velocity

### Design Principles of the Stack

1. **Unix Philosophy**: Each tool does one thing well
2. **Composition**: Tools designed to pipe into each other
3. **Terminal-First**: TUI over GUI, speed over polish
4. **Agent-Native**: Built for AI, not adapted for AI
5. **Git-Friendly**: All state is auditable in version control

---

## Advanced Configuration

ACFS supports various configuration mechanisms for advanced users.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ACFS_HOME` | `~/.acfs` | Configuration directory |
| `ACFS_REF` | `main` | Git ref to install from (tag, branch, or commit SHA) |
| `ACFS_LOG_DIR` | `/var/log/acfs` | Log directory |
| `TARGET_USER` | `ubuntu` | User to configure |
| `TARGET_HOME` | `/home/$TARGET_USER` | User home directory |

**Examples:**
```bash
# Install from a tagged release (recommended for production)
ACFS_REF=v0.1.0 curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/v0.1.0/install.sh" | bash -s -- --yes --mode vibe

# Install from a specific branch (development/testing)
ACFS_REF=feature/new-tool curl -fsSL "..." | bash -s -- --yes --mode vibe

# Install from a specific commit (reproducibility)
ACFS_REF=abc1234 curl -fsSL "..." | bash -s -- --yes --mode vibe
```

> **Tip:** Always match the URL path with `ACFS_REF` so the initial script and all subsequently fetched scripts come from the same ref.

### Complete Installer CLI Options

The installer supports extensive command-line customization:

**Execution Control:**
```bash
--yes, -y              # Skip all prompts (non-interactive)
--dry-run              # Simulate without making changes
--print                # Print what would be installed
--mode vibe|safe       # Installation mode (default: vibe)
--interactive          # Force interactive mode with prompts
--strict               # Abort on any error (vs. continue with warnings)
```

**Resume & State:**
```bash
--resume               # Resume from last checkpoint
--force-reinstall      # Ignore state, reinstall everything
--reset-state          # Clear state.json and start fresh
```

**Ubuntu Upgrade:**
```bash
--skip-ubuntu-upgrade           # Don't upgrade Ubuntu version
--target-ubuntu=25.10           # Specify target Ubuntu version
--target-ubuntu 25.04           # Alternative syntax
```

**Skip Flags:**
```bash
--skip-postgres        # Skip PostgreSQL 18
--skip-vault           # Skip HashiCorp Vault
--skip-cloud           # Skip Wrangler, Supabase, Vercel CLIs
--skip-preflight       # Skip pre-flight validation
```

### Module Selection

Fine-grained control over what gets installed using manifest-driven selection:

```bash
--list-modules           # List available modules
--print-plan             # Show execution plan without running
--only <module>          # Only run specific module(s)
--only-phase <phase>     # Only run modules in a phase
--skip <module>          # Skip specific module(s)
--no-deps                # Don't auto-include dependencies (⚠️ advanced)
```

**Key behaviors:**
- **Dependency closure:** `--only` automatically includes required dependencies (safe by default)
- **Skip safety:** `--skip` fails early if it would break a required dependency chain
- **Deterministic:** `--print-plan` shows exactly what will run, in what order

**Examples:**
```bash
# Only install agents (plus their dependencies)
curl -fsSL "..." | bash -s -- --yes --only-phase agents

# Skip PostgreSQL and Vault
curl -fsSL "..." | bash -s -- --yes --skip db.postgres18 --skip tools.vault

# Preview what would run without executing
curl -fsSL "..." | bash -s -- --print-plan
```

> **Note:** Using `--no-deps` bypasses safety checks and may result in broken installs. Only use if you've already installed dependencies separately.

### Custom Post-Install Hooks

Add custom steps by placing scripts in `~/.acfs/hooks/`:

```bash
mkdir -p ~/.acfs/hooks
cat > ~/.acfs/hooks/post-install.sh << 'EOF'
#!/bin/bash
# Custom post-install steps
echo "Running custom configuration..."
# Your commands here
EOF
chmod +x ~/.acfs/hooks/post-install.sh
```

ACFS will execute `post-install.sh` after the main installation completes.

### Override Tool Versions

To pin specific tool versions, set environment variables:

```bash
export BUN_VERSION="1.1.0"
export UV_VERSION="0.5.0"
# Then run installer
```

Note: Not all tools support version pinning. Check individual tool documentation.

---

## Future Roadmap

ACFS is actively developed. Here's what's coming:

### Near-Term (Q1 2025)

- [ ] **Full manifest-driven execution**: install.sh consumes generated scripts
- [x] **Tailscale integration**: Zero-config VPN for secure remote access ✓
- [x] **Services setup wizard**: Guide users through service account setup (`acfs services-setup`) ✓
- [ ] **Interactive module selection**: Choose what to install via TUI

### Mid-Term (Q2 2025)

- [ ] **ARM64 optimization**: Native Apple Silicon and ARM VPS support
- [ ] **Offline mode**: Pre-downloaded package bundles
- [ ] **Team mode**: Shared configurations across team members
- [ ] **Plugin system**: Third-party tool integrations

### Long-Term (2025+)

- [ ] **ACFS Cloud**: Managed VPS provisioning + ACFS install in one click
- [ ] **IDE integrations**: VSCode/Cursor extensions for remote ACFS management
- [ ] **Agent marketplace**: Pre-configured agent personalities and workflows
- [ ] **Enterprise features**: SSO, audit logging, compliance

---

## Performance Benchmarks

Installation times vary by VPS provider and network conditions. Here are typical benchmarks:

### Installation Time by Phase

| Phase | Typical Duration | Notes |
|-------|-----------------|-------|
| User Setup | 10-15s | Fast, mostly checks |
| Filesystem | 5-10s | Creating directories |
| Shell Setup | 2-4 min | Oh-My-Zsh clone is slow |
| CLI Tools | 3-5 min | Many apt packages |
| Languages | 3-5 min | Rust compile takes longest |
| Agents | 1-2 min | Fast bun installs |
| Cloud | 1-2 min | Fast bun installs |
| Stack | 4-6 min | Cargo installs |
| Finalize | 30-60s | Config deployment |
| **Total** | **15-25 min** | **Typical full install** |

### Factors Affecting Speed

| Factor | Impact | Optimization |
|--------|--------|--------------|
| Network latency | High | Choose VPS close to package mirrors |
| Disk I/O | Medium | SSD/NVMe preferred |
| CPU cores | Medium | More cores = faster compilation |
| RAM | Low | 4GB is sufficient |
| Provider | Variable | OVH and Contabo offer excellent value |

### Resume Performance

Resuming from checkpoint is fast because completed phases are skipped:

```
Full install:     20 minutes
Resume from 50%:  10 minutes
Resume from 90%:  2 minutes
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

## Links

- **Website:** [agent-flywheel.com](https://agent-flywheel.com) — Interactive wizard for beginners
- **GitHub:** [Dicklesworthstone/agentic_coding_flywheel_setup](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup)
- **Related Projects:**
  - [ntm](https://github.com/Dicklesworthstone/ntm) - Named Tmux Manager
  - [beads_viewer](https://github.com/Dicklesworthstone/beads_viewer) - Task management TUI
  - [mcp_agent_mail](https://github.com/Dicklesworthstone/mcp_agent_mail) - Agent coordination
  - [cass](https://github.com/Dicklesworthstone/coding_agent_session_search) - Agent session search
  - [dcg](https://github.com/Dicklesworthstone/destructive_command_guard) - Destructive Command Guard
  - [ru](https://github.com/Dicklesworthstone/repo_updater) - Repo Updater

---

## About Contributions

Please don't take this the wrong way, but I do not accept outside contributions for any of my projects. I simply don't have the mental bandwidth to review anything, and it's my name on the thing, so I'm responsible for any problems it causes; thus, the risk-reward is highly asymmetric from my perspective. I'd also have to worry about other "stakeholders," which seems unwise for tools I mostly make for myself for free. Feel free to submit issues, and even PRs if you want to illustrate a proposed fix, but know I won't merge them directly. Instead, I'll have Claude or Codex review submissions via `gh` and independently decide whether and how to address them. Bug reports in particular are welcome. Sorry if this offends, but I want to avoid wasted time and hurt feelings. I understand this isn't in sync with the prevailing open-source ethos that seeks community contributions, but it's the only way I can move at this velocity and keep my sanity.

---

<div align="center">
  <sub>Created by <a href="https://x.com/doodlestein">Jeffrey Emanuel</a> (<a href="https://github.com/Dicklesworthstone">@Dicklesworthstone</a>) for the agentic coding community.</sub>
</div>
