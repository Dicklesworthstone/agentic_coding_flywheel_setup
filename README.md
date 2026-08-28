# Agentic Coding Flywheel Setup (ACFS)

<div align="center">
  <img src="docs/assets/acfs_illustration.webp" alt="Agentic Coding Flywheel Setup (ACFS) - From zero to fully-configured agentic coding VPS in 30 minutes">
</div>

![Version](https://img.shields.io/badge/Version-0.7.0-bd93f9?style=for-the-badge)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%2022.04%2B%20%7C%20Arch%2FOmarchy-6272a4?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT%2BOpenAI%2FAnthropic%20Rider-blue?style=for-the-badge)
![Shell](https://img.shields.io/badge/Shell-Bash-ff79c6?style=for-the-badge)

<p align="center">
  <strong>🌐 <a href="https://agent-flywheel.com">agent-flywheel.com</a></strong> — Interactive setup wizard for beginners
</p>

> **From zero to fully-configured agentic coding VPS in 30 minutes.**
> A complete bootstrapping system that transforms a fresh Ubuntu or Arch-based machine into a professional AI-powered development environment.

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
{ acfs_installer="$(curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh")" || acfs_installer="$(curl -fsSL "https://cdn.jsdelivr.net/gh/Dicklesworthstone/agentic_coding_flywheel_setup@main/install.sh")"; } && printf '%s\n' "$acfs_installer" | bash -s -- --yes --mode vibe
```

> [!NOTE]
> `raw.githubusercontent.com` is listed first deliberately. jsDelivr caches a *mutable* `@main`
> reference, so it can serve an installer that is hours or days behind the repository. When that
> happens the stale installer's bootstrap extraction list does not match the current checksum
> ledger and the install fails with `INTEGRITY: <file> missing` — a failure that looks like a
> repository defect but is purely a CDN cache artifact. Keeping the authoritative source primary
> and the CDN as fallback preserves the resilience without that failure mode. Please do not
> reorder these. Each download is buffered before execution so a failed request cannot concatenate
> a partial installer with the fallback response.

The installer is **idempotent**—if interrupted, simply re-run it. It will automatically resume from the last completed phase without prompts.

> **Production environments:** For stable, reproducible installs, pin to a tagged release or specific commit:
> ```bash
> # Preferred: use a tagged release (e.g., v0.9.0)
> curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/v0.9.0/install.sh" | bash -s -- --yes --mode vibe --ref v0.9.0
>
> # Alternative: pin to a specific commit SHA
> curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/abc1234/install.sh" | bash -s -- --yes --mode vibe --ref abc1234
> ```
> Tagged releases are tested and stable. Passing `--ref` ensures all fetched scripts use the same version.

---

## TL;DR

**ACFS** is a complete system for bootstrapping agentic coding environments:

**Why you'd care:**
- **Zero to Hero:** Takes complete beginners from "I have a laptop" to "I have Claude/Codex/Antigravity agents writing code for me on a VPS"
- **One-Liner Magic:** A single `curl | bash` command installs 30+ tools, configures everything, and sets up three AI coding agents
- **Vibe Mode:** Pre-configured for maximum velocity—passwordless sudo, dangerous agent flags enabled, optimized shell environment
- **Battle-Tested Stack:** Includes the complete Agent Flywheel stack (core tools + utilities) for agent orchestration, coordination, and safety

**What you get:**
- Modern shell (zsh + oh-my-zsh + powerlevel10k)
- All language runtimes (bun, uv/Python, Rust, Go)
- Three AI coding agents by default (Claude Code, Codex CLI, Antigravity CLI), plus optional OpenCode, oh-my-pi (omp), and Grok CLI
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
        AGY["Antigravity CLI"]
    end

    LAPTOP --> BROWSER
    BROWSER --> STEPS
    STEPS -->|SSH| UBUNTU
    UBUNTU --> INSTALLER
    INSTALLER --> CONFIGURED
    CONFIGURED --> CLAUDE
    CONFIGURED --> CODEX
    CONFIGURED --> AGY

    classDef user fill:#e3f2fd,stroke:#90caf9,stroke-width:2px
    classDef wizard fill:#fff8e1,stroke:#ffcc80,stroke-width:2px
    classDef vps fill:#f3e5f5,stroke:#ce93d8,stroke-width:2px
    classDef agent fill:#e8f5e9,stroke:#a5d6a7,stroke-width:2px

    class LAPTOP,BROWSER user
    class STEPS wizard
    class UBUNTU,INSTALLER,CONFIGURED vps
    class CLAUDE,CODEX,AGY agent
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
ACFS is a **one-liner** that transforms any fresh Ubuntu or Arch-based machine into a fully-configured development environment with modern tooling and three AI coding agents ready to go.

### For Teams
ACFS provides a **reproducible, idempotent** setup that ensures every team member's VPS environment is identical—eliminating "works on my machine" for agentic workflows.

---

## Architecture & Design

ACFS centers its tool inventory and generated module metadata on the manifest.
Generated installer libraries and doctor checks derive from it, while
`install.sh` and several orchestration libraries retain explicit authored
handoffs. Drift checks cover the seam between those two layers.

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
    Generated["scripts/generated/*<br/>source-only libraries/harness + doctor/index/checksum data"]
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
    Commands["Commands<br/>acfs doctor / acfs update / acfs services / acfs services-setup / onboard"]
    Tools["Installed tools<br/>bun/uv/rust/go + tmux/rg/gh + vault + ..."]
    Agents["Agent CLIs<br/>claude / codex / agy"]
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

  %% Manifest-driven generation
  Manifest --> Generator --> Generated
  Generated -->|install.sh sources category libraries<br/>and dispatches private module functions| Installer

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
│  scripts/generated/: 13 source-only category libraries + install_all      │
│  harness + doctor checks + manifest index + schema-1 checksum ledger      │
└───────────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                            INSTALLER                                       │
│  install.sh + scripts/lib/*.sh + checksums.yaml (SHA256 verification)     │
│  (category libraries are sourced; install.sh owns production dispatch)      │
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

**Generated Scripts**: Rather than hand-maintaining one installer script per manifest category and keeping them synchronized, the generator produces them from the manifest. This means:
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
| **Generated Scripts** | `scripts/generated/` | Bash/data | Source-only category libraries and harness, doctor checks, manifest metadata, and the schema-1 internal checksum ledger |
| **Configs** | `acfs/` | Shell/Tmux configs | Files deployed to `~/.acfs/` |
| **Onboarding** | `acfs/onboard/` | Bash + Markdown | Interactive tutorial system |
| **Checksums** | `checksums.yaml` | YAML | SHA256 hashes for upstream installers |

---

## The Manifest System

`acfs.manifest.yaml` is the canonical inventory for generated ACFS modules. It
defines their installation and verification metadata; authored orchestration
remains responsible for bootstrap, lifecycle, and registered non-generated
handoffs.

### Manifest Structure

```yaml
version: 2
name: agentic_coding_flywheel_setup
id: acfs
defaults:
  user: ubuntu
  workspace_root: /data/projects
  mode: vibe

modules:
  - id: base.system
    description: Base packages and sane defaults
    category: base
    run_as: root
    optional: false
    enabled_by_default: true
    generated: true
    phase: 1
    install:
      - apt-get update -y
      - apt-get install -y curl git ca-certificates unzip tar xz-utils jq build-essential
    verify:
      - curl --version
      - git --version
      - jq --version
```

Each module specifies:
- **description**: Human-readable name
- **category**: One of the canonical groups: base, users, filesystem, shell, cli, network, lang, tools, db, cloud, agents, stack, acfs
- **install**: Commands to run (or descriptions that become TODOs)
- **verify**: Commands that must succeed to confirm installation

### The Generator Pipeline

The TypeScript generator (`packages/manifest/src/generate.ts`) reads the manifest and produces:

1. **Category Libraries** (`scripts/generated/install_base.sh`, `install_agents.sh`, etc.)
   - One source-only file per category with private module functions
   - Consistent logging and error handling
   - Verification checks after each module
   - Direct execution fails closed because a single category cannot satisfy cross-category dependencies

2. **Doctor Checks** (`scripts/generated/doctor_checks.sh`)
   - All verify commands extracted into a runnable health check
   - Tab-delimited format (to safely handle `||` in shell commands)
   - Reports pass/fail/skip for each module

3. **Generated Harness** (`scripts/generated/install_all.sh`)
   - Sources all category libraries
   - Invokes private module functions in global dependency order
   - Sourceable generated-module harness; direct execution refuses because it omits orchestration-owned modules and production dispatcher semantics

4. **Runtime Data** (`scripts/generated/manifest_index.sh`, `internal_checksums.sh`)
   - Deterministic module/category/generated-ownership metadata
   - Closed-grammar schema-1 digests for checksum-controlled runtime scripts

> Note: Production `install.sh` is the only supported installation entry point. It sources the category libraries and dispatches their private functions through its phase runner; it does not call `install_all.sh`.

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

The generator centralizes the substantially larger Bash output in one reviewed TypeScript implementation. Exact line and file counts are intentionally derived from the current manifest rather than frozen in this document.

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
# Write to a candidate file first: redirecting straight onto checksums.yaml
# truncates it before the script runs, so a single fetch error would leave
# it empty and every verified installer would fail closed.
./scripts/lib/security.sh --update-checksums > /tmp/acfs-checksums.candidate.yaml
diff -u checksums.yaml /tmp/acfs-checksums.candidate.yaml   # Review what changed
cp /tmp/acfs-checksums.candidate.yaml checksums.yaml
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

## Omarchy (Arch) support

Omarchy (and Arch Linux generally) is supported by the **same one-liner** — no separate command required. The installer auto-detects your distribution and adapts:

- **pacman instead of apt**: system packages and CLI tools install via `pacman`.
- **Your existing starship config is preserved**: if you already have a customized `starship.toml`, ACFS leaves it alone rather than overwriting it.
- **No oh-my-zsh / powerlevel10k on Arch**: Arch users typically have an opinionated shell setup already, so the installer skips the oh-my-zsh + powerlevel10k phase instead of clobbering your prompt.

Everything else — language runtimes, AI agents, and the flywheel tool stack — installs identically to Ubuntu.

---

## The Installer
The installer is the heart of ACFS—a modular Bash script that transforms a fresh Ubuntu or Arch-based machine into a fully-configured development environment.

### Usage

Full vibe mode (recommended for throwaway VPS):

```bash
{ acfs_installer="$(curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh")" || acfs_installer="$(curl -fsSL "https://cdn.jsdelivr.net/gh/Dicklesworthstone/agentic_coding_flywheel_setup@main/install.sh")"; } && printf '%s\n' "$acfs_installer" | bash -s -- --yes --mode vibe
```

Interactive mode (asks for confirmation):

```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh" | bash
```

Safe mode (no passwordless sudo, agent confirmations enabled):

```bash
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

    A["Phase 1: User Setup<br/><small>Create ubuntu user, migrate SSH keys, sudo</small>"]
    B["Phase 2: Filesystem<br/><small>/data/projects, ~/.acfs layout</small>"]
    C["Phase 3: Shell Setup<br/><small>zsh, oh-my-zsh, powerlevel10k</small>"]
    D["Phase 4: CLI Tools<br/><small>ripgrep, fzf, lazygit, Tailscale, etc.</small>"]
    E["Phase 5: Language Runtimes<br/><small>bun, uv, rust, go, nvm</small>"]
    F["Phase 6: AI Agents<br/><small>claude, codex, agy</small>"]
    G["Phase 7: Cloud & Database<br/><small>PostgreSQL, vault, wrangler, supabase, vercel</small>"]
    H["Phase 8: Flywheel Stack<br/><small>ntm, agent mail, br, bv, ubs, dcg, ru, etc.</small>"]
    I["Phase 9: Finalize<br/><small>Deploy acfs.zshrc, tmux.conf, agent guide</small>"]
    J["Post-install smoke test<br/><small>critical checks; then run acfs doctor</small>"]

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

### Claude Code Settings Written at Install

The installer provisions a few keys in `~/.claude/settings.json`, always merging non-destructively (a value you have already set is never overridden):

| Key | Value | Mode | Why |
|-----|-------|------|-----|
| `cleanupPeriodDays` | `99999` | all modes | Claude Code silently deletes session transcripts older than this (default **30 days**) from `~/.claude/projects` — with no warning or log line. That default destroys history before cass can index it, so ACFS sets an explicit high value; lower it yourself if you actually want pruning. |
| `skipDangerousModePermissionPrompt` | `true` | vibe only | Avoids interactive workspace-trust prompts for coding agents. |

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
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/scripts/preflight.sh" | bash -s -- --json
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/scripts/preflight.sh" | bash -s -- --format toon
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/scripts/preflight.sh" | bash -s -- --network=skip
```

This checks:
- OS compatibility (Ubuntu 22.04+ or Arch-family: Arch, Omarchy; installer upgrades Ubuntu to 25.10)
- Architecture (x86_64 or ARM64)
- Memory and disk space (warns below 4GB RAM; fails below 20GB free disk)
- Network connectivity to required URLs
- Cached `checksums.yaml` availability for verified upstream installers
- APT lock status
- Potential conflicts (nvm, pyenv, existing ACFS)

**Network checks performed:**
| Check | What it verifies | Fix if failing |
|-------|------------------|----------------|
| DNS resolution | Can resolve github.com, raw.githubusercontent.com | Check provider DNS settings; inspect `resolvectl status` or `/etc/resolv.conf` |
| GitHub HTTPS | Can reach github.com:443 | Check firewall, proxy, or VPN settings |
| Verified installer URLs | Critical upstream installer endpoints from `checksums.yaml` plus ACFS raw content | May need to retry; transient failures OK; checksum verification still stays enabled |
| APT mirrors | Default Ubuntu mirror reachable | Check `/etc/apt/sources.list` or try different mirror |
| Offline/cache mode | `--network=skip` skips live URL checks while still reporting local checksum availability | Re-run with `--network=check` when online before a release or difficult install |

For checksum-refresh review, compare a generated candidate without changing `checksums.yaml`:
```bash
candidate="/tmp/acfs-checksums.$$.candidate.yaml"
./scripts/lib/security.sh --update-checksums > "$candidate"
./scripts/preflight.sh --checksum-candidate "$candidate"
```

**Common preflight failures:**

| Error | Cause | Solution |
|-------|-------|----------|
| "Cannot resolve github.com" | DNS misconfigured | Check provider DNS settings or reboot; do not overwrite managed resolver files |
| "Cannot reach github.com" | Firewall blocking HTTPS | Allow outbound port 443 |
| "timeout contacting github.com" | Network, proxy, or provider route is slow | Retry with `--network=check`; if it persists after install bootstrap, run `acfs support-bundle` |
| "APT mirror slow or unreachable" | Regional mirror down | Edit `/etc/apt/sources.list` to use `archive.ubuntu.com` |
| "checksum candidate differs" | Upstream verified installer content changed | Review the diff; do not install from unverified fallback sources |
| "APT is locked by another process" | Another apt process running (usually unattended-upgrades on a fresh VPS) | Wait for it to finish; reboot and resume if it remains stuck |
| "Need at least 20GB free" | Less than 20GB free disk (a hard failure; low RAM only warns) | Clean up with `sudo apt autoremove` or expand disk |

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
acfs-update                  # Update apt, runtimes, shell, agents, cloud CLIs, and stack tools
acfs-update --agents-only    # Only update coding agents
acfs-update --runtime-only   # Only update runtimes (bun, rust, uv, go)
acfs-update --dry-run        # Preview changes without making them
acfs-update --yes --quiet --no-self-update
                             # Automated mode that avoids changing the ACFS tree itself
acfs-update --bootstrap-self-update
                             # Explicitly convert a non-git or incomplete install into a git checkout
```

`--bootstrap-self-update` replaces ACFS repository files with `origin/main`. Copy local files elsewhere or commit local edits before opting in. Routine updates leave non-git and incomplete Git installs untouched.

**The control-plane boundary:** with `--no-self-update` (the shipped nightly
timer's default), automated runs update your stack tools but never ACFS itself --
neither the git checkout nor the deployed runtime copies under `~/.acfs`
(`bin/acfs`, `bin/acfs-update`, `scripts/lib/*.sh`). The control plane therefore
needs its own periodic refresh: run `acfs-update` without `--no-self-update` from
time to time, or `git pull --rebase` the checkout and then run
`acfs-update --shell-only` to redeploy the runtime copies. `acfs doctor` warns
(`updates.runtime_skew`) when the checkout and the deployed runtime disagree, so
a stack kept current by the nightly cannot silently outrun a stale dispatcher.

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
| **Agents** | Claude Code | `claude update --channel latest` |
| **Agents** | Codex | `bun install -g @latest` |
| **Agents** | Antigravity | `agy update` (or verified installer with `--force`) |
| **Agents** | oh-my-pi (omp) | `omp update` (or verified installer with `--force`) |
| **Agents** | Grok CLI | Re-run verified installer (`GROK_BIN_DIR` pinned to ACFS bin dir) |
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
--stack          Include Agent Flywheel stack tools (enabled by default)
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

### Per-Tool Version Holds

When a single tool ships a regression, hold just that tool instead of pausing
the whole nightly. Every hold records an owner, a reason, and an optional
expiry, so a hold is a visible decision rather than silent version drift:

```bash
acfs hold br --version 0.4.1 --reason "0.5.2 cannot read existing beads DBs" --expiry 2026-09-15
acfs holds        # list holds (also surfaced by `acfs doctor` and every update summary)
acfs unhold br    # release the hold
```

Held tools are skipped by every update run with the owner/reason/expiry named
in the log. Expired holds warn and are ignored. Holds live in
`~/.acfs/holds.yaml`.

### Post-Install Verification and Rollback

Before a verified installer replaces a tool binary, the previous binary is
retained at `<binary>.prev`. After the install, a smoke check probes the fresh
binary with a per-tool argument (`update_tool_smoke_probe` in
`scripts/lib/update.sh`: `fsfs version`, `mdwb --help`, `pfr --help`) or, for
tools without an entry, the chain `--version` → `--help` → `version`. Every
probe is headless-safe and runs with stdin detached under a 20 s ceiling.
Verdicts:

- **healthy** — a probe exited 0.
- **unsupported** — every probe was rejected as an unknown argument (usage
  error). The binary ran, so it is kept and logged as
  `POST-INSTALL VERIFICATION UNAVAILABLE`; no rollback, no backoff.
- **broken** — a probe timed out, could not execute, died by signal, or failed
  without a usage-style rejection (crash, traceback, missing runtime). The
  previous binary is restored atomically and the failure is recorded in
  `~/.local/state/acfs/update-rollback.state` so nightly runs back off instead
  of reinstalling the same broken release every night.

`acfs doctor` reports rolled back tools; `acfs-update --force` retries
immediately.

`acfs-update` exit codes distinguish partial from total failure: `0` all
succeeded, `1` total failure (nothing updated), `2` partial failure (some tools
updated, some failed).

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
- **Stack control**: Stack updates are included by default; skip with `--no-stack`
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
acfs agents update           # Regenerate the flywheel agent guide (ACFS-owned)
acfs agents install --help   # Explicitly deploy the guide (never overwrites)
acfs update                  # Update all tools
acfs holds                   # List per-tool version holds (acfs hold/unhold to manage)
acfs services status         # Check Agent Mail, CM, and CASS daemons
acfs services-setup          # Configure agent credentials
acfs continue                # View upgrade progress after reboot
acfs installer-cache build   # Cache checksum-pinned installer entrypoints
```

### `acfs installer-cache build` — Verified Installer Entrypoint Cache

Build a portable `acfs-installer-cache/` directory containing the
checksum-pinned upstream installer scripts selected from `acfs.manifest.yaml`.
On Ubuntu, pass either that directory or its parent to a later installation:

```bash
acfs installer-cache build --output /mnt/acfs-cache
./install.sh --yes --verified-installer-cache /mnt/acfs-cache
```

Explicit cache selection is fail-closed: if a required cached entrypoint is
missing, stale, malformed, for another Ubuntu/architecture target, or does not
match the current manifest and `checksums.yaml`, ACFS refuses it instead of
fetching that entrypoint live.

This is not a complete offline installer. The cached entrypoint scripts still
need network access for release archives, package registries, Git repositories,
APT packages, and other transitive payloads. The initial ACFS bootstrap is also
separate; use `--bootstrap-archive` for that layer. The roadmap below retains
full pre-downloaded package bundles as future work.

### `acfs newproj` — New Project Wizard

Create a new project directory with ACFS defaults (git init, optional br/beads, Claude settings, AGENTS.md).
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
- Feature selection (br/beads, Claude settings, AGENTS.md, UBS ignore)
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
acfs newproj myapp --no-br
```

Notes:
- The TUI uses gum when available (arrow keys, Space to toggle, Enter to confirm). Without gum, it falls back to numbered prompts.
- Minimum terminal size: 60x15.
- CLI mode skips existing AGENTS.md; the wizard overwrites it, so move it aside if you want to keep the old one.

### `acfs agents` — Flywheel Agent Guide

ACFS generates a machine-wide agent guide (installed tools with live versions, workflows, safety rules). The guide lives **only** in ACFS-owned storage, and ACFS refreshes it there on install/update:

```text
~/.acfs/docs/flywheel-agent-guide.md    # canonical, freely regenerated by ACFS
~/.acfs/docs/AGENTS.workspace.md        # workspace AGENTS.md template (canonical copy)
```

ACFS never automatically writes `/AGENTS.md`, `~/.codex/AGENTS.md`, or a project's `AGENTS.md` — those files can contain user-authored rules and belong to you. (`/data/projects/AGENTS.md` is seeded once on a fresh install only when absent, and is never overwritten afterward.) Deploying the guide into a real instruction surface is an explicit step:

```bash
acfs agents update                       # regenerate the canonical guide
acfs agents path                         # print the canonical path
acfs agents install --codex-global       # deploy to ~/.codex/AGENTS.md (Codex global scope)
acfs agents install --project DIR        # deploy to DIR/AGENTS.md (project scope)
acfs agents install --workspace          # deploy to /data/projects/AGENTS.md
acfs agents install --root               # deploy to /AGENTS.md (legacy; not auto-discovered)
acfs agents install --to PATH            # deploy anywhere else
```

Deployment creates the destination only when it is absent. If the destination already exists with different content, the deploy refuses, leaves your file untouched, and writes a merge candidate next to it (`<dest>.acfs-new`) so you can diff and merge manually. Redeploying identical content is an idempotent no-op.

Discovery scopes worth knowing: Codex reads global guidance from `~/.codex/AGENTS.md` and project guidance from the project root down to the working directory; filesystem-root `/AGENTS.md` is **not** automatically read by any major harness, which is exactly why ACFS no longer writes it.

Tool detection always runs in the target user's context (including under `sudo`, resolved via `SUDO_USER` with `~/.local/bin`, `~/go/bin`, etc. on PATH), so user-local tools are reported accurately.

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
║    agy   → Antigravity CLI (Gemini 3.8 Flash High)            ║
║    ntm   → Named Tmux Manager                                 ║
╚══════════════════════════════════════════════════════════════╝
```

**Design Philosophy:**
- **Speed**: Must complete in <1 second
- **Read-only**: Never verifies or tests (that's doctor's job). The one write it makes is benign: successful IP lookups are cached for an hour at `~/.acfs/cache/ip_address` so repeat runs stay fast
- **Offline**: No network calls; IP discovery reads local interfaces and routing tables only
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
║    agy  → agy --model 'Gemini 3.8 Flash (High)'                ║
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

### `acfs services` — Background Daemon Management

Start, stop, restart, inspect, or follow logs for the local coordination daemons:

```bash
acfs services start
acfs services status
acfs services logs agent-mail
acfs services restart cass     # restart one service; the others keep running
acfs services drift            # is the live process on the installed binary?
acfs services stop
```

Agent Mail keeps its ACFS-reserved `127.0.0.1:8765` endpoint and reuses the native
user service when one is already healthy. CM runs on `127.0.0.1:8766`, and CM plus
the CASS watch indexer run in the `acfs-svc` tmux session. `start` and `status`
return nonzero if any daemon fails its runtime readiness check.

**Lifecycle contract** (the tmux tradeoff chosen in #196, made explicit per #360):

- The installer does **not** start this service group; run `acfs services start`
  yourself after install (and after every reboot).
- `start` is a **one-shot launcher**, not a foreground supervisor: it brings the
  daemons up, reports readiness, and exits.
- Only **Agent Mail** is normally boot-persistent, via its native systemd user
  service. **CM and the CASS watch indexer live in the `acfs-svc` tmux session**,
  which does not survive a reboot and does not restart crashed processes -- after
  a reboot or crash, rerun `acfs services start`.
- CM's HTTP server is **optional** if you only use `cm context` / `cm reflect`
  from the CLI; those read the store directly.
- Leaving the CASS watcher off can be deliberate (for example while diagnosing
  indexing or resource problems); `acfs services status` reporting it "not
  running" is not necessarily a fault.

**Converging a partly-down group** (#383): when the `acfs-svc` session already
exists, `start` repairs it instead of reporting and exiting. It relaunches only
the services that are not running -- a pane whose process is alive is never
touched, which matters when the tmux server also hosts long-lived agent panes.
`acfs services repair` is the same operation under its own name.

**Preflight before teardown** (#382): `restart` resolves and validates every
binary it will need *before* it stops anything. Validation is the post-install
smoke check from #378 -- the binary must exist, be executable, and answer a
probe; a `broken` verdict (timeout, wrong architecture, missing loader, crash)
aborts the restart with no service-state change, while an `unsupported` verdict
(the CLI rejects `--version`/`--help`/`version` as unknown arguments) is
accepted. Managed binaries are resolved from the ACFS install directories as
well as `PATH`, so a noninteractive SSH shell without `~/.local/bin` on `PATH`
no longer takes the group down. `restart` also accepts service names
(`acfs services restart cass`) to restart one service without interrupting the
others.

**Running-binary drift** (#381): updating a tool replaces the file on disk, but
a service keeps executing the inode it started with -- `cass --version` then
reports the new release while the live watcher still runs the old code. ACFS
compares what each *service* executes (`/proc/<pid>/exe`, which is not the same
thing as what `PATH` resolves) against the installed binary, and warns with both
paths and hashes from `acfs services status`, `acfs doctor`, and the end of
`acfs update`. Nothing is restarted automatically: the warning names the exact
per-service restart command so you can pick a quiescent moment. `acfs services
drift` runs the check on demand (`--robot` for one `service|state|detail` line
per service). The comparison needs procfs, so it reports `unknown` on platforms
without one.

This lifecycle command is distinct from `acfs services-setup`, which configures
credentials and integrations rather than background processes.

### `acfs services-setup` — Credential Configuration

Interactive wizard for configuring AI agent credentials and cloud service logins.

```bash
acfs services-setup          # Run full setup wizard
```

Guides you through:
- **Claude Code**: API key configuration
- **Codex CLI**: ChatGPT account login
- **Antigravity CLI**: Google account authentication
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
| 6 | Agent Commands | 10 min | Claude, Codex, Antigravity usage |
| 7 | NTM Command Center | 8 min | Session orchestration |
| 8 | NTM Prompt Palette | 6 min | Quick command access |
| 9 | The Flywheel Loop | 10 min | How all 10 tools work together |

These are the core lessons; the hub ships 65 lessons in total (the core track plus per-tool deep dives such as UBS, Agent Mail, CASS, Beads, SLB, RCH and the case studies below), all defined in `apps/web/lib/lessons.ts`.

**Features:**
- Progress tracking in localStorage
- Code blocks with copy buttons
- Expandable deep-dive sections
- Practical exercises

### Command Reference

The [Command Reference](https://agent-flywheel.com/learn/commands) documents every installed tool:

| Category | Commands |
|----------|----------|
| **Agents** | `cc`, `cod`, `agy` |
| **Search** | `rg`, `fd`, `sg`, `fzf` |
| **Git** | `lg`, `gh`, `git-lfs` |
| **System** | `z`, `bat`, `lsd`, `atuin`, `tmux` |
| **Stack** | `ntm`, `am`, `br`, `bv`, `cass`, `cm`, `ubs`, `dcg`, `ru`, `rch`, `slb`, `caam` |
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

| Scenario | Description | Timeframe |
|----------|-------------|-----------|
| Daily Parallel Progress | Keep several projects moving at once, even without the mental bandwidth for all of them | 3+ hours of autonomous work |
| Agents Reviewing Agents | Agents review each other's work before it becomes a problem | Continuous improvement loop |
| 5,500 Lines to 347 Beads | Turn a massive planning document into a dependency-tracked task graph | ~1 day for a complex feature |
| Fresh Eyes Code Review | Agents re-investigate code from a fresh perspective to find what humans miss | Continuous |
| Multi-Repo Morning Sync | Start the day with every repo synced and agents spawned across the fleet | < 10 minutes to full productivity |
| Bulk AI Commit Automation | `ru agent-sweep` commits dirty repos with AI-written messages | 30 min – 2 hours depending on repo count |
| Resource-Protected Agent Swarm | Run heavy agents without the workstation freezing (SRPS keeps priorities in check) | Hours of unattended work |

The scenarios are defined in `apps/web/lib/flywheel.ts`; the page renders whatever that file contains.

### Tool Catalog (TL;DR page)

The [TL;DR page](https://agent-flywheel.com/tldr) is the searchable catalog of installed tools (the old `/tools` page was folded into it and now redirects there):

- **Search & Filter**: A search box (press `/` to focus) filters tools by name, CLI command, or description
- **Tool Details**: Each card shows the tool's tagline, its CLI command as a chip, and a copyable example invocation
- **Synergy Diagram**: An interactive diagram shows how the flywheel tools feed each other
- **Live Data**: Cards are generated from `acfs.manifest.yaml` — manifest tools without a hand-curated entry are auto-appended so the page can never silently omit a tool

This page helps users discover tools they may not know about and understand how each fits into the agentic coding workflow.

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
A tooltip system (`apps/web/components/jargon.tsx`) that adapts to the pointer type:

*Desktop behavior:*
- Hover or keyboard focus reveals a floating definition card, rendered through a portal so it escapes stacking contexts
- Viewport-aware positioning (auto-flips when near edges)
- A short close delay so the pointer can travel into the card

*Mobile behavior:*
- Tap opens a bottom sheet (`apps/web/components/ui/bottom-sheet.tsx`, framer-motion) with the full definition
- Swipe-to-dismiss from the handle, Escape and backdrop dismissal, focus returned to the term
- Body scroll locked while open and restored on close

*Visual features:*
- Dotted primary-colored underline marks a term as interactive
- Reduced-motion users get fades instead of slides
- Colors come from the OKLCH design tokens

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

The Learning Hub includes specialized lessons for each tool in the Agent Flywheel stack:

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

After installation, users can learn the ACFS workflow through an interactive terminal-based tutorial. The onboarding TUI discovers lesson markdown files dynamically from `acfs/onboard/lessons`, so the curriculum can grow as new tools and workflows are added without changing the launcher.

### Running Onboarding

```bash
onboard                # Launch interactive menu
onboard status         # Show completion status
onboard --list         # Alias for status
onboard 3              # Jump to lesson 3
onboard reset          # Reset progress and start fresh
onboard --reset        # Alias for reset
```

### Lessons

Run `onboard --help` to see the currently discovered lesson list. The curriculum currently spans Linux basics, SSH, tmux, agent login, NTM, the flywheel workflow, updating, Beads, RCH, and other ACFS tools. Because lessons are discovered by filename, adding a new `NN_name.md` file automatically extends the tutorial.

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
| **atuin** | `atuin search` | Searchable shell history database (its zsh hook is intentionally not enabled; `Ctrl+R` is the shell's own history search) |
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
| **minisign** | `minisign` | Release signature verification (required by the Agent Mail and CAAM installers) |

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
| **Antigravity CLI** | `agy` | `agy` (model-pinned, dangerous mode) |
| **Gemini CLI** (legacy) | `gemini` | `gmi` (retired 2026-06-18; routes to locked `agy`) |
| **OpenCode** (optional) | `opencode` | — |
| **oh-my-pi** (optional) | `omp` | — |
| **Grok CLI** (optional) | `grok` | — |

**Vibe Mode Aliases:**
```bash
# Claude Code with max memory (background tasks enabled by default)
alias cc='NODE_OPTIONS="--max-old-space-size=32768" claude --dangerously-skip-permissions'

# Codex with bypass and dangerous filesystem access
alias cod='codex --dangerously-bypass-approvals-and-sandbox --search -m gpt-5.6-sol -c model_reasoning_effort=xhigh -c model_reasoning_summary_format=experimental'

# Antigravity CLI, model/settings/DCG locked by the ACFS launcher
alias agy='$HOME/.local/bin/agy-locked'
alias gmi='$HOME/.local/bin/agy-locked'
```

**Installation & Updates:**
Claude Code should be installed and updated using its native mechanisms:
- **Install:** ACFS uses the official native installer (`claude.ai/install.sh`), checksum-verified via `checksums.yaml` (installs to `~/.local/bin/claude`)
- **Update:** Use `claude update --channel latest` (built-in) or run `acfs update --agents-only`

This ensures proper authentication handling and avoids issues with alternative package manager builds. ACFS updates Codex with Bun global package updates, Antigravity with its native `agy update` path, oh-my-pi with its native `omp update` path, and Grok CLI by re-running its checksum-verified installer.

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

### Agent Flywheel Stack (Core Tools)

The core suite of tools for professional agentic workflows:

| # | Tool | Command | Description |
|---|------|---------|-------------|
| 1 | **Named Tmux Manager** | `ntm` | Agent cockpit—spawn, orchestrate, monitor tmux sessions |
| 2 | **MCP Agent Mail** | `am` | Agent coordination via mail-like messaging (Rust rewrite) |
| 3 | **BeadsRust** | `br` | Dependency-aware issue tracker for agents (Rust implementation) |
| 4 | **Beads Viewer** | `bv` | Task management TUI with graph analysis |
| 5 | **Coding Agent Session Search** | `cass` | Unified agent history search (CASS) |
| 6 | **CASS Memory System** | `cm` | Procedural memory for agents |
| 7 | **Ultimate Bug Scanner** | `ubs` | Bug scanning with guardrails |
| 8 | **Destructive Command Guard** | `dcg` | Claude Code hook blocking dangerous git/fs commands |
| 9 | **Repo Updater** | `ru` | Multi-repo sync + AI-driven commit automation |
| 10 | **Remote Compilation Helper** | `rch` | Transparent build offloading to faster machines |
| 11 | **Coding Agent Account Manager** | `caam` | Agent auth switching |
| 12 | **Simultaneous Launch Button** | `slb` | Two-person rule for dangerous commands |

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
║   ✔ agy 1.0.12                                                ║
║                                                               ║
║ Cloud                                                         ║
║   ✔ vault 1.18.3                                              ║
║   ✔ wrangler 4.16.0                                           ║
║   ✔ supabase 2.23.4                                           ║
║   ✔ vercel 41.7.6                                             ║
║                                                               ║
║ Agent Flywheel Stack                                          ║
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

Doctor checks are generated from the manifest (`scripts/generated/doctor_checks.sh`) to keep verification logic close to `acfs.manifest.yaml`. The `acfs doctor` command automatically sources these generated checks to verify all manifest-defined tools.

**How it works:**
1. The manifest generator creates `doctor_checks.sh` with verify commands for each module
2. `acfs doctor` sources this file and runs each verification check
3. Failed checks display a **fix suggestion** with the exact command to reinstall

**Example output with fix suggestion:**
```
  ✗ tools.lazygit - Lazygit terminal UI not found
    Fix: curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --force-reinstall --only tools.lazygit
```

This architecture ensures doctor checks stay in sync with the installer—if a tool is in the manifest, it will be verified.

### Options

```bash
acfs doctor              # Interactive colorful output
acfs doctor --json       # Machine-readable JSON output
acfs doctor --quiet      # Exit code only (0=healthy, 1=issues)
acfs doctor --deep       # Run functional tests (auth, connections)
acfs doctor --fix        # Apply safe fixes for failed checks
acfs doctor --dry-run    # Preview fixes without applying
acfs doctor --no-cache   # Skip cache, run all checks fresh
```

### Deep Checks (`--deep`)

The `--deep` flag runs functional tests beyond binary existence:

| Category | Checks |
|----------|--------|
| **Agent Auth** | Claude config, Codex OAuth, Antigravity credentials |
| **Database** | PostgreSQL connection, ubuntu role exists |
| **Cloud CLIs** | `gh auth status`, `wrangler whoami`, Supabase/Vercel tokens |
| **Vault** | `VAULT_ADDR` configured |

Deep checks use 15-second timeouts to avoid hanging on network issues. Successful results are cached for 5 minutes to speed up repeated runs.

Example output:
```
Deep Checks
  ✔ Claude auth configured
  ✔ PostgreSQL connection working
  ⚠ Codex not authenticated (run: codex login)
  ✔ GitHub CLI authenticated

8/9 functional tests passed in 3.2s
```

### Auto-Fix Mode (`--fix`)

The `--fix` flag automatically applies safe, deterministic fixes for common issues:

```bash
acfs doctor --fix             # Apply safe fixes
acfs doctor --fix --dry-run   # Preview fixes without applying
```

#### Safe Auto-Fixers

These fixes are applied when `--fix` is used. Failed checks are fixed right away; warning-level checks (which most of these are) additionally need `--yes`, so the usual invocation is `acfs doctor --fix --yes`:

| Fix ID | Description | Undo Strategy |
|--------|-------------|---------------|
| `fix.path.ordering` | Prepend ACFS directories to PATH in .zshrc | Restore backup |
| `fix.config.copy` | Copy missing ~/.acfs config files | Remove copied file |
| `fix.dcg.hook` | Install DCG pre-tool-use hook | Run `dcg uninstall` |
| `fix.symlink.create` | Create missing tool symlinks | Remove symlink |
| `fix.plugin.clone` | Clone missing zsh plugins | Remove cloned directory |
| `fix.acfs.sourcing` | Add ACFS sourcing to .zshrc | Restore backup |

#### Safety Guarantees

- **Never deletes user files** — Only creates, modifies, or symlinks
- **Backups before modify** — SHA256-verified backups of all modified files
- **Idempotent** — Safe to run multiple times
- **Logged** — All changes recorded to `~/.local/share/acfs/doctor.log`
- **Reversible** — Configuration-level fixes (PATH, sourcing, config copies, symlinks, plugin clones) record an undo command; tool installs are not auto-reverted

#### Example Dry-Run Output

```
DRY-RUN: acfs doctor --fix

Would apply the following fixes:

  [fix.path.ordering]
    Action: Prepend PATH directories to ~/.zshrc
    File: ~/.zshrc
    Backup: Yes (SHA256 verified)

  [fix.acfs.sourcing]
    Action: Add ACFS sourcing to .zshrc
    File: ~/.zshrc
    Backup: Yes (SHA256 verified)

Fixes that require manual action:
  [shell.ohmyzsh]
    Status: FAIL
    Suggestion: curl -fsSL https://install.ohmyz.sh/ | bash

Summary: 2 auto-fixes, 0 prompted, 1 manual
```

#### Manual-Only Fixes

Some operations are never auto-fixed and instead provide suggestions:

- Package manager operations (`apt install ...`)
- Anything requiring sudo
- File deletions
- Complex shell configuration changes

#### Undoing Changes

All changes made by `--fix` can be undone:

```bash
acfs undo --list      # List all changes
acfs undo chg_0001    # Undo specific change
acfs undo --all       # Undo all changes from the most recent fix session
acfs undo --everything  # Undo every recorded change across all sessions
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
- **Handoff Runbook:** Downloadable JSON/Markdown artifact for the installer command and recovery steps
- **Progress Tracking:** localStorage persistence across browser sessions
- **Confirmation Checkboxes:** "I ran this command" acknowledgments
- **Troubleshooting:** Expandable help for common issues

### Wizard Handoff Runbook

Step 9 can download a local handoff runbook in JSON or Markdown. The runbook is meant for the user and support loop when an SSH session drops, an install is interrupted, or the user needs to remember the exact command they ran.

**Schema:** `acfs.handoff-runbook.v1`

| Field | Purpose |
|-------|---------|
| `wizardSelections` | Local OS, install mode, source ref, and normalized target user |
| `targetHost` | Redacted host kind and target-host assumptions |
| `ssh` | Expected SSH key paths and redacted reconnect command templates |
| `install` | Exact installer command generated from the shared command builder |
| `recoveryCommands` | Copy/paste-safe reconnect, retry, doctor, and support-bundle commands |
| `support` | Deterministic `acfs support-bundle` reference and review artifacts |
| `privacy` | Explicit redaction policy for host data and exact-command inclusion |

Host addresses are not written into the runbook. The installer command stays exact so a user can paste it back into the VPS session, and the artifact points to `support-report.md` and `manifest.json` for support-bundle review.

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
```

Atuin is still installed, but ACFS keeps it behind the guarded `~/.local/bin/atuin`
shim instead of putting `~/.atuin/bin` at the front of interactive shell `PATH`.

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
| `Ctrl+R` | Shell history search | Uses the active shell/editor binding |

**Atuin History Bindings:**
ACFS intentionally does not enable Atuin's zsh preexec/precmd integration by
default. Atuin's searchable CLI remains available as `atuin search`, but the
automatic shell hook can record every coding-agent command and grow the Atuin
database fast enough to make shells laggy.

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
update_agents()    # Claude, Codex, Antigravity, omp, Grok (version before/after)
update_cloud()     # Wrangler, Supabase, Vercel (Supabase uses verified release tarball)
update_rust()      # rustup update stable
update_uv()        # uv self update
update_go()        # Go toolchain update
update_shell()     # OMZ, P10K, plugins, Atuin, Zoxide
update_stack()     # Agent Flywheel stack tools

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
acfs_require_contract "module:${module_id}"  # Assert module environment is ready
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
  agent: "claude-code" | "codex" | "agy";
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

### Port 8765 is reserved for Agent Mail

ACFS runs Agent Mail as a user service bound to `127.0.0.1:8765` and health-checks it there.
`cm serve` (CASS Memory's MCP HTTP server) defaults to the same address, so on an ACFS machine
start it on another port (`cm serve --port 8766`, or `MCP_HTTP_PORT=8766 cm serve`); otherwise
whichever process starts second fails to bind and MCP clients can end up talking to the wrong
server. If Agent Mail cannot start, the installer reports which process is holding the port.

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
| **Git Reset** | `git reset --hard`, `git reset --merge` <!-- acfs-policy-lint: allow filesystem.no_destructive_cleanup --> |
| **File Discard** | `git checkout -- <files>`, `git restore <files>` <!-- acfs-policy-lint: allow filesystem.no_destructive_cleanup --> |
| **Force Push** | `git push --force` / `-f` (allows `--force-with-lease`) |
| **Clean** | `git clean -f` (allows `-n` dry-run) |
| **Branch Delete** | `git branch -D` (allows `-d`) |
| **Stash Loss** | `git stash drop`, `git stash clear` |
| **Filesystem** | `rm -rf` <!-- acfs-policy-lint: allow filesystem.no_destructive_cleanup --> |

### What Gets Allowed

Safe variants are allowlisted:
- `git checkout -b <branch>` — Creates branch, doesn't touch files
- `git restore --staged` — Only unstages, doesn't discard
- `git clean -n` — Dry-run preview
- Temp directory cleanup still requires explicit human approval when an agent would delete files

### Installation

```bash
acfs update --stack-only
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
{ curl -fsSL "https://cdn.jsdelivr.net/gh/Dicklesworthstone/repo_updater@main/install.sh" || curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/repo_updater/main/install.sh"; } | bash
```

Initialize configuration:

```bash
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

ACFS does not use GitHub Actions: every workflow under `.github/workflows/` is disabled, and the checks below run locally or on the maintainer's own machines (`scripts/release-doctor.sh`, `scripts/checksum-monitor-local.sh` on a systemd timer, the Docker and QEMU factory harnesses, and `dsr` for releases). The workflow descriptions that follow document what each disabled workflow used to do and what replaced it.

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

  factory-e2e:
    - Runs the literal public curl|bash installer on QEMU/KVM or a fresh real Ubuntu host
    - Requires systemd, SSH, and a disposable factory VM/VPS semantics
    - Verifies ubuntu user creation, SSH key merge, user services, tool health, and idempotency
```

Docker catches shell and package regressions early. The factory E2E is the authoritative release gate for the real beginner VPS path because it exercises systemd, SSH, login/user-service behavior, and provider image defaults that containers cannot model. A Docker pass is not sufficient release proof by itself.

### Local Release Doctor (`scripts/release-doctor.sh`)

Run the local release gate before tagging or publishing a release candidate:

```bash
bash scripts/release-doctor.sh --full --network=check
bash scripts/release-doctor.sh --json --full --network=check > release-doctor.json
```

For a fast local readiness check while developing:

```bash
bash scripts/release-doctor.sh --json
```

The release doctor composes the maintainer checks that are easy to forget:
- branch policy and clean worktree status
- `shellcheck install.sh scripts/**/*.sh`
- manifest/generated/checksum drift via `scripts/check-manifest-drift.sh --json --quiet`
- verified-installer checksum candidate review with `--network=check`
- website `type-check`, `lint`, and production build when `apps/web` changed or `--full` is set

The checksum candidate check uses the canonical updater output. If the generated body differs from `checksums.yaml`, review the diff before release; if only the timestamp header differs, leave `checksums.yaml` unchanged. The default `--network=skip` keeps routine runs offline, and `--web=auto` runs website checks only when web files changed unless `--full` or `--web=always` is provided.

### Stack Provenance Report (`scripts/stack-provenance-report.sh`)

Use the stack provenance report when reviewing Agent Flywheel stack tool freshness before release:

```bash
bash scripts/stack-provenance-report.sh --json
bash scripts/stack-provenance-report.sh --network=check --json
```

Offline mode reports local manifest/checksum consistency for stack tools. Network mode also checks GitHub latest release metadata and generates a checksum candidate without writing `checksums.yaml`. Changed stack installer hashes fail the report, unrelated checksum diffs are called out separately, and `rch` release changes are flagged as mandatory checksum-refresh review items.

### Agent Readiness Audit (`scripts/agent-readiness-audit.sh`)

Run the local agent readiness audit before launching a swarm on a freshly installed VPS:

```bash
bash scripts/agent-readiness-audit.sh
bash scripts/agent-readiness-audit.sh --json
```

The audit checks Claude Code, Codex CLI, Antigravity CLI, and `caam` without printing token values or auth file contents. It reports CLI presence, version availability, parseable auth/config files, CAAM default profile consistency, and stale CAAM defaults that point at missing profiles.

Useful options:

```bash
bash scripts/agent-readiness-audit.sh --no-version  # Skip CLI --version probes
bash scripts/agent-readiness-audit.sh --home /home/ubuntu --path "$PATH"
```

Treat failures as launch blockers. Warnings usually mean the CLI is installed but needs a user sign-in or CAAM default profile selection.

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

### Automated Checksum + Drift Repair (`scripts/checksum-monitor-local.sh`)

ACFS monitors upstream installers for changes and repairs generated-artifact checksum drift from a local systemd timer (every 15 minutes, in a dedicated clone on a maintainer box), not from GitHub Actions; the retired `checksum-monitor.yml` did the same job and is kept only for reference.

```text
scripts/checksum-monitor-local.sh      # the monitor
scripts/systemd/acfs-checksum-monitor.* # timer + service templates
```

**How It Works:**

1. **Verify Generated Artifact Drift**: Runs `scripts/check-manifest-drift.sh --json` to detect:
   - `ACFS_MANIFEST_SHA256` mismatches
   - internal script checksum drift (`scripts/generated/internal_checksums.sh`)
   - generated installer and web metadata drift via `bun run generate:diff`
   - semantic manifest contract drift across `scripts/generated/doctor_checks.sh`, `apps/web/lib/generated`, `acfs/onboard/lessons`, README snippets, and `checksums.yaml`

The internal ledger is inert data: exactly `ACFS_INTERNAL_CHECKSUMS_SCHEMA=1`,
one associative checksum map, and its exact entry count. The installer parses
that closed grammar without sourcing the ledger, enforces its checksum-controlled
membership, and verifies regular non-symlink files before sourcing them. This
is an internal consistency boundary, not an independent signature or archive
provenance claim.
2. **Auto-Repair Drift**: If drift is detected, runs `--fix` (regenerate + commit + push)
3. **Verify Current Upstream Checksums**: Downloads all upstream installers, calculates SHA256
4. **Detect Upstream Changes**: Compares against `checksums.yaml`
5. **Categorize Tools**: Separates "trusted" tools (can auto-update) from others
6. **Auto-Update Upstream Checksums**: Commits updated `checksums.yaml` when safe
7. **Alert**: For non-trusted tool changes, creates GitHub issue for manual review

The monitor **fails closed** when verification returns fetch errors or skipped entries; it will not emit partial/placeholder checksum updates.

**What gets auto-updated:** every changed installer hash — first-party and third-party alike — is regenerated with the canonical updater, committed, and pushed. The monitor fails closed (no partial update) if any fetch fails or any entry is skipped.

**What gets flagged for review:** when the changed set includes a third-party installer (anything whose URL is not under the Dicklesworthstone GitHub org: bun, uv, rustup, oh-my-zsh, atuin, zoxide, nvm, claude, antigravity, opencode, omp, grok), the monitor opens a GitHub issue with the diff after the update lands, so a human reviews the new upstream script post-hoc. First-party tool changes are committed without an issue.

This gives:
- **Velocity**: a fresh install is never broken by a stale hash for long
- **Auditability**: every hash change is a git commit, and third-party changes get an issue for review
- **Fail-closed behavior**: on fetch errors nothing is committed

**Upstream Repo Dispatch (Fast Path):**
- ACFS-owned tool repos emit a `repository_dispatch` event (`upstream-changed`) when their `install.sh` changes or a release is published.
- Requires a PAT secret named `ACFS_REPO_DISPATCH_TOKEN` in each tool repo (repo scope for this org/user).
- If dispatch fails, the 15-minute scheduled monitor still catches drift (but slower).

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

### Installer Canary (Docker) (`installer-canary.yml`)

Runs the installer inside fresh Ubuntu containers on a daily schedule. This is a fast regression canary, not the final proof of the factory VPS path.

```yaml
schedule: "30 7 * * *" # daily
jobs:
  canary:
    - Run tests/vm/test_install_ubuntu.sh (vibe mode)
    - Defaults to Ubuntu 25.10; --all covers 24.04, 25.04, and 25.10
    - Uses ACFS_CHECKSUMS_REF=main for freshest hashes
```

### Factory Installer E2E (`installer-factory-e2e.yml`)

Runs the literal public installer through the authoritative factory harness. The QEMU/KVM backend uses the official Ubuntu cloud image and requires a runner with `/dev/kvm`; set the repository variable `ACFS_FACTORY_RUNNER`, the manual `runner` input, or `client_payload.runner` to a KVM-capable larger/self-hosted runner. The real-host backend runs against a disposable Ubuntu VPS over SSH and is intended for provider-specific sentinel runs.

```yaml
schedule: "0 8 * * 0" # weekly QEMU/KVM factory canary when ACFS_FACTORY_RUNNER has /dev/kvm
workflow_dispatch:
  inputs:
    backend: qemu|real-host
    runner: "" # optional override; blank uses ACFS_FACTORY_RUNNER or ubuntu-latest
    ref: main
    mode: vibe
    expect_ubuntu: "25.10"
    expect_final_ubuntu: "25.10"
repository_dispatch:
  types: [acfs-factory-host-ready]
real-host secrets:
  ACFS_FACTORY_SSH_PRIVATE_KEY: private key for real-host backend
  ACFS_FACTORY_SSH_TARGET: optional fallback root@fresh-host for real-host backend
```

Standard GitHub-hosted runners do not provide a contractual nested-virtualization environment. If the QEMU backend runs without `/dev/kvm`, the workflow fails at the KVM preflight with an environment-specific error before invoking the installer.

Reusable workflow callers may use the QEMU backend without passing SSH secrets. The real-host backend still needs a private key plus either `client_payload.ssh_target` for dispatch runs or `ACFS_FACTORY_SSH_TARGET` as a fallback.

If `backend=real-host` is requested without those SSH credentials, the workflow fails during configuration resolution. It must never report a green canary when no disposable host was tested.

Workflow artifact directories and uploads include only the current GitHub run id and attempt. That keeps repeated scheduled/manual runs from reusing or uploading old QEMU overlay disks on KVM-capable self-hosted runners with persistent workspaces. The QEMU backend writes its generated private SSH key outside the repository checkout, so upload-artifact and future Git commits never package guest login credentials. Factory diagnostics are redacted before local upload, including installer logs and the remote diagnostic archive.

The target host must be freshly provisioned. By default the harness fails if the `ubuntu` user already exists before install, because the real beginner path must prove ACFS creates that user automatically. The harness also requires `acfs doctor --json` to report zero failures and zero warnings, then separately verifies Agent Mail liveness/systemd service state and the ACFS nightly user timer.

For the slower upgrade/resume gate, provision a fresh Ubuntu 24.04 host and run the same workflow or script with `--expect-ubuntu 24.04 --expect-final-ubuntu 25.10 --allow-install-reboot`.

For provider-specific real VPS sentinels, use an external provisioning job to create a disposable server, wait for root SSH, dispatch `acfs-factory-host-ready`, and destroy the server after artifact collection. The dispatch payload should include the fresh host address so the repository does not store a stale long-lived VPS as `ACFS_FACTORY_SSH_TARGET`:

```json
{
  "event_type": "acfs-factory-host-ready",
  "client_payload": {
    "backend": "real-host",
    "ssh_target": "root@203.0.113.10",
    "ref": "main",
    "mode": "vibe",
    "expect_ubuntu": "25.10",
    "expect_final_ubuntu": "25.10"
  }
}
```

### Local QEMU Factory E2E (`test_factory_install_qemu.sh`)

Runs the same factory-host harness inside a real local VM instead of a Docker container. The wrapper downloads and verifies the official Ubuntu cloud image, boots it with QEMU/KVM and cloud-init, exposes root SSH on a local forwarded port, then delegates to `tests/vm/test_factory_install_ubuntu.sh`. Generated private SSH keys are kept outside the repository checkout; use `--key-dir` with a path under `/tmp` or another non-repo directory when you need a specific local key location for debugging.

```bash
sudo apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils openssh-client
./tests/vm/test_factory_install_qemu.sh
```

Use this when Docker passes but you need local proof for systemd, sshd, cloud-init, kernel, filesystem, and login behavior before spending time on a disposable provider VPS.

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

ACFS works on any Ubuntu VPS with SSH access and either root password login or a provider console that lets you become root for the first install. Here are recommended providers optimized for multi-agent workloads.

> **Why 48-64GB RAM?** Each AI coding agent uses ~2GB RAM. To run 10-20+ agents simultaneously, you need 48GB+ RAM. Don't bottleneck a $400+/month AI investment to save $20 on hosting.

After installation, run `acfs capacity --profile 25-agents --recommend-ntm` on the VPS for a local RAM/CPU/disk sizing report with recommended agent counts and copyable NTM launch profiles.

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
| **OS** | Ubuntu 22.04+ (auto-upgraded) or Arch-family (Arch, Omarchy) | Ubuntu 25.10 |
| **RAM** | 32GB (tight) | 48-64GB |
| **Storage** | 250GB NVMe SSD | 300GB+ NVMe SSD |
| **CPU** | 12 vCPU | 16 vCPU |
| **Price** | ~$26/mo | ~$40-56/mo |

### Other Providers

Any provider with an Ubuntu VPS, SSH access, and a first-login root password or root console works. The wizard at [agent-flywheel.com](https://agent-flywheel.com) has step-by-step guides.

### Provider Setup Guides

ACFS includes detailed step-by-step guides for each supported provider in `scripts/providers/`:

| Provider | Guide | Key Sections |
|----------|-------|--------------|
| **Contabo** | `contabo.md` | Account creation, plan selection, data center choice, root password setup |
| **OVH** | `ovh.md` | Control panel navigation, password authentication, instance configuration, networking |
| **Hetzner** | `hetzner.md` | Project setup, firewall rules, console access |

Each guide includes:
- **Screenshots** for every step (in `scripts/providers/screenshots/`)
- **Pricing breakdowns** with recommendations
- **Region selection** guidance (latency, privacy)
- Password-first login guidance and post-install SSH key recovery specific to that provider
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
├── VERSION                       # Current version (0.7.0)
├── install.sh                    # Main installer entry point
├── acfs.manifest.yaml            # Canonical tool manifest
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
│   └── onboard/                  # Onboard TUI source
│
├── acfs/                         # Files deployed to ~/.acfs/
│   ├── zsh/
│   │   └── acfs.zshrc            # Shell configuration
│   ├── tmux/
│   │   └── tmux.conf             # Tmux configuration
│   └── onboard/
│       ├── onboard.sh            # Onboarding TUI script
│       └── lessons/              # Tutorial markdown
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
│   │   ├── install_<category>.sh # 13 source-only category libraries
│   │   ├── install_all.sh        # Sourceable generated-module harness
│   │   ├── manifest_index.sh     # Runtime module metadata
│   │   ├── doctor_checks.sh      # Verification checks
│   │   └── internal_checksums.sh # Schema-1 critical-script checksum data
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
        ├── test_install_ubuntu.sh # Docker integration test
        ├── test_factory_install_ubuntu.sh # Real VM/VPS factory install test
        └── test_factory_install_qemu.sh # Local QEMU/KVM factory install test
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

# Authoritative factory-host E2E (requires a disposable fresh Ubuntu 25.10 VM/VPS)
./tests/vm/test_factory_install_ubuntu.sh --ssh-target root@203.0.113.10

# Local authoritative VM E2E (QEMU/KVM + official Ubuntu cloud image)
./tests/vm/test_factory_install_qemu.sh

# Slow real-host upgrade/resume gate from Ubuntu 24.04 to 25.10
./tests/vm/test_factory_install_ubuntu.sh --ssh-target root@203.0.113.10 --expect-ubuntu 24.04 --expect-final-ubuntu 25.10 --allow-install-reboot
```

### Security Verification

```bash
# Print all upstream URLs
./scripts/lib/security.sh --print

# Verify all checksums
./scripts/lib/security.sh --verify

# Update checksums after reviewing upstream changes (candidate file first;
# never redirect onto checksums.yaml directly)
./scripts/lib/security.sh --update-checksums > /tmp/acfs-checksums.candidate.yaml
diff -u checksums.yaml /tmp/acfs-checksums.candidate.yaml || [[ $? -eq 1 ]]
# After reviewing and accepting the diff:
cp /tmp/acfs-checksums.candidate.yaml checksums.yaml
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
| `test_factory_install_ubuntu.sh` | Real systemd VM/VPS factory install from public curl\|bash |
| `test_factory_install_qemu.sh` | Local QEMU/KVM factory install using Ubuntu cloud images |
| `test_acfs_update.sh` | Update mechanism validation |
| `bootstrap_offline_checks.sh` | Offline system readiness |
| `resume_checks.sh` | State resume validation |
| `selection_checks.sh` | Module selection unit tests |
| `selection_e2e.sh` | End-to-end selection flow |

**Running Tests:**
```bash
# Full Docker integration test
./tests/vm/test_install_ubuntu.sh

# Full Docker integration matrix
./tests/vm/test_install_ubuntu.sh --all

# Real factory-host integration test
./tests/vm/test_factory_install_ubuntu.sh --ssh-target root@203.0.113.10

# Local QEMU/KVM factory-host integration test
./tests/vm/test_factory_install_qemu.sh

# Real upgrade/resume integration test
./tests/vm/test_factory_install_ubuntu.sh --ssh-target root@203.0.113.10 --expect-ubuntu 24.04 --expect-final-ubuntu 25.10 --allow-install-reboot

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
{ acfs_installer="$(curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh")" || acfs_installer="$(curl -fsSL "https://cdn.jsdelivr.net/gh/Dicklesworthstone/agentic_coding_flywheel_setup@main/install.sh")"; } && printf '%s\n' "$acfs_installer" | bash -s -- --yes --mode vibe
```

It will skip already-completed phases and resume where it left off.

### How do I update tools?

Use the built-in update command:
```bash
acfs update                  # Update all standard components
acfs update --stack          # Include Agent Flywheel stack
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

The rise of AI coding agents (Claude Code, Codex CLI, Antigravity CLI) has created a new paradigm in software development. These agents can write code, debug issues, and even architect solutions—but only if they have the right environment.

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
│ • Modern CLI    │         │ • Antigravity   │         │ • SLB + DCG     │
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

The manifest is the source of truth for generated modules and their verification
metadata. Explicitly authored orchestration handoffs remain in `install.sh` and
the installer libraries, so generator drift checks and integration tests are
still required across that boundary.

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

// Verified installer file-backed execution
function buildVerifiedInstallerFileCommand(module: Module): string {
  // Runs the interpreter only after the complete script is checksum-verified
  // and staged in a read-only file.
}
```

**Output Structure:**
```
scripts/generated/
├── install_base.sh        # Base system packages (apt)
├── install_users.sh       # Source-only library; users.ubuntu is orchestration-owned
├── install_filesystem.sh  # Directory structure (/data/projects)
├── install_shell.sh       # zsh + oh-my-zsh + p10k
├── install_cli.sh         # ripgrep, tmux, fzf, lazygit, etc.
├── install_network.sh     # Tailscale
├── install_lang.sh        # bun, uv, rust, go
├── install_tools.sh       # ast-grep, atuin, zoxide, Vault
├── install_agents.sh      # claude, codex, agy
├── install_db.sh          # PostgreSQL 18
├── install_cloud.sh       # wrangler, supabase, vercel
├── install_stack.sh       # Flywheel stack + utilities
├── install_acfs.sh        # ACFS config deployment
├── install_all.sh         # Sourceable generated-module harness
├── doctor_checks.sh       # Health verification
├── manifest_index.sh      # Module metadata arrays
└── internal_checksums.sh  # Schema-1 critical-script checksum data
```

**Generated Script Structure:**
```bash
#!/bin/bash -p
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT

acfs_generated_install_module_id() {
    local module_id="module.id"
    acfs_require_contract "module:${module_id}"  # Validate environment
    acfs_generated_ensure_selection
    should_run_module "$module_id" || return 0
    run_as_target_shell <<'HEREDOC'
        # Installation commands from manifest
    HEREDOC
}
```

Installed-check/idempotency and aggregate-failure behavior are owned by the
`install.sh` phase dispatcher. Generated files refuse direct execution; use
`install.sh` for a complete run.

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
declare -gA ACFS_MODULE_DESC
ACFS_MODULE_DESC["lang.bun"]="Bun JavaScript/TypeScript runtime"
ACFS_MODULE_DESC["agents.claude"]="Claude Code CLI agent"

# Phase mapping (determines install order)
declare -gA ACFS_MODULE_PHASE
ACFS_MODULE_PHASE["base.system"]="1"
ACFS_MODULE_PHASE["lang.bun"]="6"
ACFS_MODULE_PHASE["agents.claude"]="7"

# Dependency relationships (comma-separated)
declare -gA ACFS_MODULE_DEPS
ACFS_MODULE_DEPS["agents.codex"]="lang.bun"
ACFS_MODULE_DEPS["stack.mcp_agent_mail"]="lang.bun,lang.uv"

# Generated function name mapping
declare -gA ACFS_MODULE_FUNC
ACFS_MODULE_FUNC["lang.bun"]="acfs_generated_install_lang_bun"
# generated:false modules deliberately have no ACFS_MODULE_FUNC entry

# Canonical category order and per-module generation ownership
declare -a ACFS_CATEGORIES_IN_ORDER=(base users filesystem shell cli network lang tools db cloud agents stack acfs)
declare -gA ACFS_MODULE_GENERATED
ACFS_MODULE_GENERATED["lang.bun"]="1"
ACFS_MODULE_GENERATED["users.ubuntu"]="0"

# Category grouping
declare -gA ACFS_MODULE_CATEGORY
ACFS_MODULE_CATEGORY["lang.bun"]="lang"

# Default inclusion in install
declare -gA ACFS_MODULE_DEFAULT
ACFS_MODULE_DEFAULT["lang.bun"]="1"
ACFS_MODULE_DEFAULT["db.postgres18"]="1"
```

**Runtime Access Pattern:**
```bash
# Iterate modules in deterministic install order
for module in "${ACFS_MODULES_IN_ORDER[@]}"; do
  [[ "${ACFS_MODULE_CATEGORY[$module]}" == "agents" ]] || continue
  printf '%s\n' "$module"
done

# Check if module is default-installed
[[ "${ACFS_MODULE_DEFAULT[tools.vault]:-1}" == "1" ]]

# Get installation phase
printf '%s\n' "${ACFS_MODULE_PHASE[stack.ntm]}"  # 9
```

**Use Cases:**
- `acfs doctor` queries module metadata for health checks
- `install.sh --list-modules` displays available modules
- `--skip <module>` validates module existence before skipping
- `--only-phase <n|name>` uses phase mapping for selective installs

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
├── agent-5: Antigravity writing docs
└── ...
```

### Dry-Run Swarm Simulation

Before launching any real swarm, ask ACFS for a queue-aware plan:

```bash
acfs swarm plan --agents 25 --profile balanced --workload standard
```

The planner reads the local swarm status and capacity model, incorporates RCH
queue pressure, active tmux/NTM sessions, Beads in-progress counts, and host
resource headroom, then prints a pass/warn/fail recommendation. It is advisory
only: it does not launch agents, mutate Beads, send Agent Mail, force-release
reservations, or run build commands. JSON output is available with `--json`,
and fixture replay is available with `--status-file`.

For multi-host planning, keep a local redacted inventory at
`~/.acfs/swarm/hosts.inventory.json`:

```bash
acfs swarm inventory report
acfs swarm inventory validate --json
acfs swarm inventory export --format json --output inventory.redacted.json
acfs swarm inventory import --input inventory.redacted.json
```

The inventory commands are local and advisory. They read or write JSON files,
preserve unknown fields for future versions, reject sensitive field names such
as hostnames, IPs, keys, tokens, passwords, and home paths, and never SSH,
launch NTM, run RU, send Agent Mail, mutate Beads, or change RCH config.

For each agent you plan to launch, generate a bounded startup packet from the
selected Bead plus current repo instructions and bounded CM/CASS context:

```bash
acfs swarm packet --bead bd-1234 --agent-name BlueLake --role implementation
acfs swarm packet --json --bead bd-1234 --agent-name BlueLake
```

The packet is designed for NTM prompt injection. It prioritizes live AGENTS.md,
README.md, Beads, and Agent Mail state over memory-derived hints, includes drift
checks, and preserves exact `bv --robot-*`, `br`, Agent Mail MCP, `rch exec --`,
and UBS workflow guidance. It is read-only: it does not claim work, reserve
files, send messages, start agents, run builds, or edit generated files.

Before launching a large real swarm, ACFS can run an offline simulation of the control plane:

```bash
acfs swarm simulate
```

The default simulation runs 10, 25, and 50 logical-agent scenarios without launching tmux sessions, model CLIs, Beads mutations, Agent Mail writes, or local CPU-heavy builds. It writes artifacts for each scenario: generated launch plan, telemetry JSON, capacity/resource sample, timing, and pass/fail summary. Treat this as a local readiness harness, not a substitute for provider factory tests on real VPS hosts.

After one or more simulation runs, calibrate the static capacity assumptions
against those local artifacts:

```bash
acfs swarm calibration --artifact-dir ~/.acfs/logs/swarm-simulations
acfs swarm calibration --json --artifact-dir ./swarm-artifacts --rch-file ./rch-timing.json
```

The calibration report is read-only. It classifies the local evidence as
conservative, aligned, or too aggressive, handles missing or partial artifacts
with warnings, and never changes capacity defaults, RCH state, NTM sessions,
Beads, or Agent Mail.

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

4. **Single Source of Truth:** The manifest defines module metadata and generated module logic; hand-written `install.sh` owns production orchestration and dispatch.

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
- Antigravity for documentation and research

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
| Network timeout | curl exit code 28 | Retried on a fixed 0s/5s/15s schedule |
| APT lock held | `apt-get` waits via `DPkg::Lock::Timeout=120` | Waits up to 120s for unattended-upgrades; on timeout the step fails and a re-run resumes the install |
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

Downloads retry on a fixed schedule rather than exponential backoff: `retry_with_backoff` in `scripts/lib/error_tracking.sh` (and the installer's own `ACFS_CURL_RETRY_DELAYS`) retries three times with 0s, 5s, and 15s delays, and only for curl exit codes that indicate a transient network problem (DNS, connect, timeout, SSL handshake, empty reply). Permanent failures such as a 404 are not retried. The Ubuntu upgrade library is the one place with true exponential backoff (`ubuntu_retry_with_backoff`, 30s doubling) because `do-release-upgrade` mirrors are slow to recover.

### APT Lock Handling

The most common installation failure on a fresh VPS is APT lock contention: `unattended-upgrades` runs for a few minutes after first boot. To prevent transient lock errors, the installer passes `-o DPkg::Lock::Timeout=120` to `apt-get` calls so it waits up to 120 seconds for unattended-upgrades to finish. `acfs update` similarly waits (up to 120 seconds) before its apt operations, and `acfs doctor --fix` can disable stuck unattended-upgrades runs.

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
| Neither Ubuntu nor Arch-family | "Unsupported OS" | ACFS supports Ubuntu 22.04+, Arch, and Omarchy |
| No internet | "curl: (6) Could not resolve host" | Check DNS, try `ping google.com` |
| Old bash | Syntax errors | Upgrade to bash 4+ |

### Installation Failure Recovery

When the installer fails mid-way through, it provides an **auto-resume hint** with a precise command to continue from where it left off.

**What you'll see on failure:**

```
[ERROR] ACFS installation failed!

To debug:
  1. Check the log: cat /var/log/acfs/install.log
  2. If installed, run: acfs doctor (try as ubuntu)

╔══════════════════════════════════════════════════════════════╗
║  To resume installation from this point:                     ║
╚══════════════════════════════════════════════════════════════╝

  curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/.../install.sh | bash -s -- --resume --yes

  Failed phase: phase_9
  Failed step: install_stack
```

**Key features of the resume hint:**

| Feature | Description |
|---------|-------------|
| **Pinned commit** | Uses exact SHA from original run for reproducibility |
| **Preserved flags** | Includes all original flags (--skip-*, --mode, --strict) |
| **Automatic detection** | Reads failed phase/step from `~/.acfs/state.json` |
| **Copyable command** | Ready to paste and run immediately |

**Manual recovery steps:**

1. **Review the error**:
   ```bash
   # Check the full log
   cat /var/log/acfs/install.log | tail -50

   # Or search for ERROR
   grep -i error /var/log/acfs/install.log
   ```

2. **Run diagnostics**:
   ```bash
   # As the target user (ubuntu)
   acfs doctor

   # If running as root
   sudo -u ubuntu -i bash -lc 'acfs doctor'
   ```

3. **Resume installation**:
   ```bash
   # Use the exact command from the failure output
   # Or use the generic resume command:
   curl -fsSL https://acfs.sh | bash -s -- --resume --yes --mode vibe
   ```

4. **Check state file** (advanced):
   ```bash
   # View current installation state
   cat ~/.acfs/state.json | jq .

   # See the stored resume hint
   jq '.resume_hint' ~/.acfs/state.json
   ```

**Common failure scenarios:**

| Scenario | Typical Cause | Recovery |
|----------|---------------|----------|
| Network timeout | Transient connectivity | Wait, then resume |
| APT lock held | Unattended-upgrades | Wait 2-3 min, resume |
| Disk full | Insufficient space | Free space, resume |
| SSH disconnect | Session timeout | Reconnect, resume |
| Tool install failed | Upstream unavailable | Check status, resume |

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

2. **Inspect and recover if waiting doesn't help**:
   ```bash
   sudo fuser -v /var/lib/dpkg/lock-frontend || true
   sudo systemctl status unattended-upgrades --no-pager || true

   # If it still looks stuck after several minutes, reboot the VPS,
   # reconnect, then repair interrupted package configuration:
   sudo dpkg --configure -a
   sudo apt-get update
   ```

### Install Logs & Summary JSON

Every ACFS install run produces two artifacts for debugging and tooling:

**Log File Location:**
```
~/.acfs/logs/install-YYYYMMDD_HHMMSS.log
```

The log file captures all stderr output from the installer, with:
- Header containing version, date, and mode
- All progress messages and errors
- ANSI colors stripped after completion
- Footer with completion timestamp

**Summary JSON Location:**
```
~/.acfs/logs/install_summary_YYYYMMDD_HHMMSS.json
```

**Summary JSON Schema (v1):**
```json
{
  "schema_version": 1,
  "status": "success",           // "success" or "failure"
  "timestamp": "2026-01-27T...", // ISO 8601
  "total_seconds": 1200,         // Wall clock time
  "environment": {
    "acfs_version": "0.9.0",
    "mode": "vibe",
    "ubuntu_version": "25.04",
    "target_user": "ubuntu",
    "target_home": "/home/ubuntu"
  },
  "phases": [
    {"id": "phase_0", "duration_seconds": 5},
    {"id": "phase_1", "duration_seconds": 45},
    // ... completed phases in order
  ],
  "failure": null,               // null on success, or:
  // "failure": {
  //   "phase": "phase_9",
  //   "step": "install_stack",
  //   "error": "curl failed with exit code 7",
  //   "resume_hint": "curl -fsSL ... | bash -s -- --resume --yes"
  // }
  "log_file": "/home/ubuntu/.acfs/logs/install-20260127_120000.log"
}
```

**Accessing logs:**
```bash
# Find the latest log
ls -lt ~/.acfs/logs/install-*.log | head -1

# Find the latest summary
ls -lt ~/.acfs/logs/install_summary_*.json | head -1

# Parse summary JSON
jq . ~/.acfs/logs/install_summary_*.json | head -1

# Get failed phase (if any)
jq '.failure // "No failure"' ~/.acfs/logs/install_summary_*.json | tail -1

# Get phase timings
jq '.phases[] | "\(.id): \(.duration_seconds)s"' ~/.acfs/logs/install_summary_*.json | tail -1
```

**Sharing logs for support:**

```bash
# Create a support bundle (strips sensitive data)
acfs support-bundle > support-bundle.txt

# Or manually share (review for secrets first):
cat ~/.acfs/logs/install-*.log | tail -200  # Last 200 lines
cat ~/.acfs/logs/install_summary_*.json | tail -1  # Latest summary
```

### Support Bundle Command

The `acfs support-bundle` command collects all diagnostic data into a single archive for troubleshooting.

**Usage:**
```bash
acfs support-bundle [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--verbose, -v` | Show detailed output during collection |
| `--output, -o DIR` | Output directory (default: `~/.acfs/support`) |
| `--no-redact` | Disable secret redaction (WARNING: bundle may contain secrets) |
| `--help, -h` | Show help |

**Output files:**
```
~/.acfs/support/<timestamp>/          # Unpacked bundle directory
~/.acfs/support/<timestamp>.tar.gz    # Compressed archive (shareable)
~/.acfs/support/<timestamp>/manifest.json  # Bundle manifest
```

**What's collected:**

| File | Description |
|------|-------------|
| `state.json` | Installation state and checkpoints |
| `VERSION` | ACFS version |
| `checksums.yaml` | Upstream verification checksums |
| `logs/install-*.log` | Recent install logs (up to 10) |
| `logs/install_summary_*.json` | Recent install summaries |
| `doctor.json` | Health check results |
| `versions.json` | Installed tool versions |
| `environment.json` | OS, memory, disk, user info |
| `os-release` | Linux distribution info |
| `journal-acfs.log` | Systemd journal for ACFS services |
| `config/.zshrc` | Shell configuration |

**Security & Redaction:**

By default, sensitive data is automatically redacted:

| Pattern | Example | Redacted To |
|---------|---------|-------------|
| OpenAI API keys | `sk-abc123...` | `<REDACTED:api_key>` |
| AWS keys | `AKIAIOSFODNN...` | `<REDACTED:aws_key>` |
| GitHub tokens | `ghp_xxxx...` | `<REDACTED:github_token>` |
| Vault tokens | `hvs.xxxx...` | `<REDACTED:vault_token>` |
| Slack tokens | `xoxb-xxxx...` | `<REDACTED:slack_token>` |
| Bearer tokens | `Bearer xxx...` | `Bearer <REDACTED:bearer>` |
| JWTs | `eyJhbGc...` | `<REDACTED:jwt>` |
| Passwords | `"password": "..."` | `"password": "<REDACTED:password>"` |
| Private key blocks | `-----BEGIN ... PRIVATE KEY-----` | `<REDACTED:private_key>` |

Before launching a large agent swarm or sharing a support bundle, run a local credential preflight:

```bash
acfs credential-preflight --json
```

The preflight scans bounded ACFS state/log files plus shell config/history surfaces and reports only categories, counts, file labels, and remediation guidance. It never prints raw secret values or snippets.

**Example workflow:**

```bash
# Create support bundle
acfs support-bundle

# Output: ~/.acfs/support/20260127_120000.tar.gz

# Share the archive when filing an issue
# The archive is safe to share (secrets redacted)
```

**Disable redaction (use with caution):**
```bash
# WARNING: Bundle may contain API keys, tokens, and passwords
acfs support-bundle --no-redact
```

**When to use:**
- Installation failed and you need to share logs
- Filing a GitHub issue about ACFS
- Diagnosing tool installation problems
- Sharing system state with support

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

Start with the safe readiness report:

```bash
bash scripts/agent-readiness-audit.sh --json
```

**Claude Code**:
```bash
# Check auth status
claude --version
ls -la ~/.claude/  # or ~/.config/claude/

# Re-authenticate
claude  # Follow prompts, then use /login inside Claude Code to switch accounts
```

**Codex CLI**:
```bash
# Check auth status
codex --version

# Re-authenticate (uses ChatGPT account, not API key)
codex  # Follow first-run sign-in prompts
```

**Antigravity CLI**:
```bash
# Check auth status
agy --version

# Re-authenticate
agy  # Follow Google login flow
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

### Doctor Shows Missing Tools

**Symptom**: `acfs doctor` shows failed checks for tools you expected to be installed.

**Understanding doctor output:**

Doctor checks are generated directly from the manifest, so they verify the exact same tools the installer provides. When a check fails, doctor shows a copy-pasteable fix command:

```
  ✗ tools.lazygit - Lazygit terminal UI not found
    Fix: curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --force-reinstall --only tools.lazygit
```

**Solutions**:

1. **Re-run the specific module** (use the fix suggestion):
   ```bash
   curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --force-reinstall --only tools.lazygit
   curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --force-reinstall --only lang.go
   curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --force-reinstall --only stack.dcg
   ```

2. **Re-run an entire phase** (for multiple failures in one category):
   ```bash
   curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --force-reinstall --only-phase cli
   curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --force-reinstall --only-phase stack
   ```

3. **Run auto-fix mode** (applies safe, deterministic fixes):
   ```bash
   acfs doctor --fix
   acfs doctor --fix --dry-run  # Preview fixes first
   ```

**Note**: Doctor checks match the manifest verify commands exactly. If a tool was skipped during installation (e.g., using `--mode safe`), the check will fail. This is expected—run `acfs doctor` to see which tools are missing and decide which to install.

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
   # If missing, reinstall through the ACFS verified installer path:
   acfs update --stack-only
   dcg install --force  # Register hook after reinstall
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

{ acfs_installer="$(curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh")" || acfs_installer="$(curl -fsSL "https://cdn.jsdelivr.net/gh/Dicklesworthstone/agentic_coding_flywheel_setup@main/install.sh")"; } && printf '%s\n' "$acfs_installer" | bash -s -- --yes --mode vibe --force-reinstall
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
curl -fsSL "https://..." -o install.sh
less install.sh
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
1. Download into an installer-owned private temporary file
2. Calculate SHA256 from those staged bytes
3. Compare against the reviewed checksum metadata
4. If it matches, copy the verified bytes into a read-only staging file
5. Execute that exact staging file with a trusted Bash or sh binary
6. If any step fails or the hash differs, refuse execution
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
- Always-proceed tool permission for Antigravity (`agy`)

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

## The Agent Flywheel Stack Philosophy

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
| `ACFS_CHECKSUMS_REF` | `main` (when pinned) / `ACFS_REF` (when branch) | Ref used to fetch `checksums.yaml` |
| `ACFS_VERIFIED_INSTALLER_CACHE` | unset | `acfs-installer-cache/` directory, or its parent; when set, verified installer entrypoint acquisition is fail-closed to that cache |
| `ACFS_LOG_DIR` | `/var/log/acfs` | Log directory |
| `TARGET_USER` | `ubuntu` | User to configure |
| `TARGET_HOME` | Resolved from `TARGET_USER` | User home directory (or explicit override) |

**Examples:**
```bash
# Install from a tagged release (recommended for production)
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/v0.1.0/install.sh" | bash -s -- --yes --mode vibe --ref v0.1.0

# Install from a specific branch (development/testing)
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/feature/new-tool/install.sh" | bash -s -- --yes --mode vibe --ref feature/new-tool

# Install from a specific commit (reproducibility)
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/abc1234/install.sh" | bash -s -- --yes --mode vibe --ref abc1234

# Pin installer version but use latest checksums (avoid stale hash mismatches)
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/v0.9.0/install.sh" | bash -s -- --yes --mode vibe --ref v0.9.0 --checksums-ref main
```

> **Tip:** Always match the URL path with `--ref` so the initial script and all subsequently fetched scripts come from the same ref. If you use environment variables in a pipeline, attach them to `bash`, not `curl`: `curl ... | ACFS_REF=v0.9.0 bash -s -- --yes --mode vibe`.
> **Tip:** For pinned installs (tags/SHAs), checksums default to `main` to avoid stale installer hashes. Override with `ACFS_CHECKSUMS_REF` if you want checksums pinned to the same ref.

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
--ref <ref>            # Git ref to install from (branch, tag, or commit SHA)
--checksums-ref <ref>  # Fetch checksums.yaml from this ref (default: main for pinned tags/SHAs)
--verified-installer-cache <dir> # Require checksum-pinned installer entrypoints from this cache (Ubuntu only; transitive downloads still use the network)
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
Only install agents (plus their dependencies):

```bash
curl -fsSL "..." | bash -s -- --yes --only-phase agents
```

Skip PostgreSQL and Vault:

```bash
curl -fsSL "..." | bash -s -- --yes --skip db.postgres18 --skip tools.vault
```

Preview what would run without executing:

```bash
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

- [x] **Manifest-driven execution**: `install.sh` consumes generated module libraries while retaining explicit authored handoffs for registered `generated:false` modules ✓
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

MIT License (with OpenAI/Anthropic Rider). See [LICENSE](LICENSE) for details.

---

## Links

- **Website:** [agent-flywheel.com](https://agent-flywheel.com) — Interactive wizard for beginners
- **GitHub:** [Dicklesworthstone/agentic_coding_flywheel_setup](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup)
- **Related Projects:**
  - [ntm](https://github.com/Dicklesworthstone/ntm) - Named Tmux Manager
  - [beads_viewer](https://github.com/Dicklesworthstone/beads_viewer) - Task management TUI
  - [mcp_agent_mail_rust](https://github.com/Dicklesworthstone/mcp_agent_mail_rust) - Agent coordination
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
