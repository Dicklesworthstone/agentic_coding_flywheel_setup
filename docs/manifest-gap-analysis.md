# Manifest Gap Analysis

> install.sh ↔ acfs.manifest.yaml mapping
>
> Created: 2025-12-21 | Bead: mjt.2.1

## Overview

This document maps the relationship between `install.sh` phases and `acfs.manifest.yaml` modules to:
1. Identify what the installer does that isn't in the manifest
2. Identify what the manifest specifies that the installer doesn't implement
3. Guide future manifest-driven installer integration

---

## Phase-to-Module Mapping

| install.sh Phase | Function | Manifest Module(s) | Status |
|------------------|----------|-------------------|--------|
| Phase 0 | `run_preflight_checks()` | — | Installer-only |
| Phase 1 | `ensure_base_deps()` | `base.system` | ✓ Aligned |
| Phase 2 | `normalize_user()` | `users.ubuntu` | ✓ Aligned |
| Phase 3 | `setup_filesystem()` | `base.filesystem` | ✓ Aligned |
| Phase 4 | `setup_shell()` | `shell.zsh` | ✓ Aligned |
| Phase 5 | `install_cli_tools()` | `cli.modern` | Partial (see gaps) |
| Phase 6 | `install_languages()` | `lang.*`, `tools.atuin`, `tools.zoxide`, `tools.ast_grep` | ✓ Aligned |
| Phase 7 | `install_agents()` | `agents.*` | ✓ Aligned |
| Phase 8 | `install_cloud_db()` | `db.postgres18`, `tools.vault`, `cloud.*` | ✓ Aligned |
| Phase 9 | `install_stack()` | `stack.*` | ✓ Aligned |
| Phase 10 | `finalize()` | `acfs.onboard`, `acfs.doctor` | Partial |
| Smoke Test | `run_smoke_test()` | — | Installer-only |

---

## Detailed Phase Analysis

### Phase 1: Base Dependencies (`ensure_base_deps`)

**Installer installs:** `curl git ca-certificates unzip tar xz-utils jq build-essential sudo gnupg`

**Manifest specifies (base.system):**
```yaml
install:
  - sudo apt-get update -y
  - sudo apt-get install -y curl git ca-certificates unzip tar xz-utils jq build-essential
verify:
  - curl --version
  - git --version
  - jq --version
```

**Gap:** Installer adds `sudo gnupg` which manifest doesn't specify.

---

### Phase 2: User Normalization (`normalize_user`)

**Installer does:**
- Creates ubuntu user if missing
- Adds to sudo group
- Configures passwordless sudo (`/etc/sudoers.d/90-ubuntu-acfs`)
- Copies SSH keys from root
- Adds user to docker group

**Manifest specifies (users.ubuntu):**
```yaml
install:
  - "Ensure user ubuntu exists with home /home/ubuntu"
  - "Write /etc/sudoers.d/90-ubuntu-acfs: ubuntu ALL=(ALL) NOPASSWD:ALL"
  - "Copy authorized_keys from invoking user to /home/ubuntu/.ssh/"
verify:
  - id ubuntu
  - sudo -n true
```

**Gap:** Manifest uses prose descriptions, not executable commands. Installer adds docker group membership.

---

### Phase 3: Filesystem Setup (`setup_filesystem`)

**Installer creates:**
- `/data/projects`, `/data/cache`
- `$TARGET_HOME/Development`, `$TARGET_HOME/Projects`, `$TARGET_HOME/dotfiles`
- `$ACFS_HOME/{zsh,tmux,bin,docs,logs}`
- `$ACFS_LOG_DIR` (/var/log/acfs)

**Manifest specifies (base.filesystem):**
```yaml
install:
  - "Create /data/projects and /data/cache directories"
  - "Create ~/.acfs/{zsh,tmux,bin,docs,logs} directories"
verify:
  - test -d /data/projects
  - test -d ~/.acfs
```

**Gap:** Installer creates more directories (Development, Projects, dotfiles, logs). Manifest uses prose.

---

### Phase 4: Shell Setup (`setup_shell`)

**Installer does:**
- Installs zsh via apt
- Installs Oh My Zsh (verified upstream script)
- Installs Powerlevel10k theme (git clone)
- Installs zsh-autosuggestions, zsh-syntax-highlighting plugins
- Copies `acfs/zsh/acfs.zshrc` to `~/.acfs/zsh/`
- Creates `.zshrc` loader that sources the ACFS config
- Sets zsh as default shell

**Manifest specifies (shell.zsh):** ✓ Matches conceptually.

---

### Phase 5: CLI Tools (`install_cli_tools`)

**Installer installs:**

| Tool | Source | In Manifest? |
|------|--------|--------------|
| gum | Charm apt repo | ❌ No |
| ripgrep | apt | ✓ Yes |
| tmux | apt | ✓ Yes |
| fzf | apt | ✓ Yes |
| direnv | apt | ✓ Yes |
| jq | apt | ✓ Yes (in base.system) |
| gh (GitHub CLI) | apt/official repo | ❌ No |
| git-lfs | apt | ❌ No |
| lsof, dnsutils, netcat, strace, rsync | apt | ❌ No |
| lsd, eza, bat, fd-find, btop, dust, neovim | apt | ✓ Yes (cli.modern) |
| docker.io, docker-compose-plugin | apt | ❌ No |
| lazygit | apt | ✓ Yes |
| lazydocker | apt | ❌ No |

**Manifest gap:** Missing: gum, gh, git-lfs, system utils, docker, lazydocker

---

### Phase 6: Language Runtimes (`install_languages`)

**Installer installs:**

| Tool | Method | Manifest Module |
|------|--------|-----------------|
| Bun | Verified upstream script | `lang.bun` ✓ |
| Rust/Cargo | Verified upstream script | `lang.rust` ✓ |
| ast-grep (sg) | cargo install | `tools.ast_grep` ✓ |
| Go | apt (golang-go) | `lang.go` ✓ |
| uv | Verified upstream script | `lang.uv` ✓ |
| Atuin | Verified upstream script | `tools.atuin` ✓ |
| Zoxide | Verified upstream script | `tools.zoxide` ✓ |

**Gap:** None - well aligned.

---

### Phase 7: Coding Agents (`install_agents`)

**Installer installs:**

| Agent | Method | Manifest Module |
|-------|--------|-----------------|
| Claude Code | Verified upstream script (native) | `agents.claude` ✓ |
| Codex CLI | bun install -g @openai/codex@latest | `agents.codex` ✓ |
| Gemini CLI | bun install -g @google/gemini-cli@latest | `agents.gemini` ✓ |

**Gap:** None - well aligned.

---

### Phase 8: Cloud & Database (`install_cloud_db`)

**Installer installs:**

| Tool | Method | Manifest Module | Skippable |
|------|--------|-----------------|-----------|
| PostgreSQL 18 | PGDG apt repo | `db.postgres18` ✓ | --skip-postgres |
| Vault | HashiCorp apt repo | `tools.vault` ✓ | --skip-vault |
| Wrangler | bun install -g | `cloud.wrangler` ✓ | --skip-cloud |
| Supabase | bun install -g | `cloud.supabase` ✓ | --skip-cloud |
| Convex | bun install -g | `cloud.convex` ✓ | --skip-cloud |
| Vercel | bun install -g | `cloud.vercel` ✓ | --skip-cloud |

**Gap:** Manifest doesn't specify skippability/tags. Installer creates postgres user/db.

---

### Phase 9: Dicklesworthstone Stack (`install_stack`)

**Installer installs:**

| Tool | Method | Manifest Module |
|------|--------|-----------------|
| NTM | Verified upstream script | `stack.ntm` ✓ |
| MCP Agent Mail | Verified upstream script | `stack.mcp_agent_mail` ✓ |
| UBS | Verified upstream script (--easy-mode) | `stack.ultimate_bug_scanner` ✓ |
| Beads Viewer (bv) | Verified upstream script | `stack.beads_viewer` ✓ |
| CASS | Verified upstream script (--easy-mode --verify) | `stack.cass` ✓ |
| CM | Verified upstream script (--easy-mode --verify) | `stack.cm` ✓ |
| CAAM | Verified upstream script | `stack.caam` ✓ |
| SLB | Verified upstream script | `stack.slb` ✓ |

**Gap:** Manifest doesn't capture install flags (--easy-mode, --verify, --yes).

---

### Phase 10: Finalize (`finalize`)

**Installer does:**

| Action | In Manifest? |
|--------|--------------|
| Install tmux.conf | ❌ No (orchestration) |
| Link ~/.tmux.conf | ❌ No |
| Install onboard lessons (8 files) | `acfs.onboard` (partial) |
| Install onboard.sh script | `acfs.onboard` ✓ |
| Install scripts/lib/*.sh | ❌ No (orchestration) |
| Install acfs-update wrapper | ❌ No |
| Install services-setup.sh | ❌ No |
| Install checksums.yaml + VERSION | ❌ No |
| Install acfs CLI (doctor.sh) | `acfs.doctor` (partial) |
| Install Claude Git Safety Guard hook | ❌ No |
| Create state.json | ❌ No (orchestration) |

**Gap:** Most finalize actions are orchestration-level, not module-level.

---

## Summary: Installer-Only Functionality

These are things the installer does that the manifest doesn't specify:

1. **Pre-flight validation** (`run_preflight_checks`)
2. **Gum installation** (enhanced UI)
3. **GitHub CLI (gh)** installation
4. **git-lfs** installation and configuration
5. **System utilities**: lsof, dnsutils, netcat, strace, rsync
6. **Docker** installation and group membership
7. **lazydocker** installation
8. **PostgreSQL user/db creation** for target user
9. **Tmux configuration** linking
10. **ACFS scripts/lib/** installation
11. **acfs-update wrapper** installation
12. **Claude Git Safety Guard** hook installation
13. **State file** creation and management
14. **Smoke test** verification

---

## Summary: Manifest-Only Modules

These manifest modules don't have full installer implementation:

| Module | Issue |
|--------|-------|
| All modules | Use prose descriptions instead of executable commands |
| `users.ubuntu` | Missing docker group membership |
| `cli.modern` | Missing gum, gh, git-lfs, system utils |
| `acfs.onboard` | Verify command uses placeholder |
| `acfs.doctor` | Verify command uses placeholder |

---

## Recommendations for Manifest vNext

### 1. Add Missing Modules

```yaml
- id: cli.gum
  description: Gum terminal UI toolkit
  install:
    - "Add Charm apt repository"
    - sudo apt-get install -y gum
  verify:
    - gum --version
  tags: [optional, ui]

- id: cli.gh
  description: GitHub CLI
  install:
    - "Add GitHub CLI apt repository or install from distro"
    - sudo apt-get install -y gh
  verify:
    - gh --version
  tags: [recommended]

- id: cli.docker
  description: Docker container runtime
  install:
    - sudo apt-get install -y docker.io docker-compose-plugin
  verify:
    - docker --version
  tags: [optional, containers]
```

### 2. Add Tags/Categories for Skippability

```yaml
modules:
  - id: db.postgres18
    tags: [optional, database, skippable]
    skip_flag: --skip-postgres
```

### 3. Add Install Flags

```yaml
- id: stack.ubs
  install_args: ["--easy-mode"]
```

### 4. Separate Orchestration from Modules

Create a new section for orchestration-only actions:
```yaml
orchestration:
  - id: finalize.tmux_config
    description: Link tmux configuration
  - id: finalize.state_file
    description: Create installation state tracking
```

---

## CLI Flags Inventory (bead mjt.2.2)

> Added: 2025-12-21 | Maps legacy flags to manifest tags/modules

### install.sh CLI Flags

| Flag | Current Behavior | Proposed Tag/Module Mapping |
|------|------------------|----------------------------|
| `--yes` / `-y` | Skip all prompts | Orchestration (not module) |
| `--dry-run` | Print what would be done | Orchestration |
| `--print` | List upstream scripts | Orchestration |
| `--mode vibe` | Passwordless sudo, full agent permissions | `security.vibe_mode` or tag `vibe` |
| `--mode safe` | Standard sudo, confirmation prompts | Default (no tag) |
| `--skip-postgres` | Skip PostgreSQL 18 | `db.postgres18.enabled_by_default: false` or tag `skippable` |
| `--skip-vault` | Skip Vault | `tools.vault.enabled_by_default: false` or tag `skippable` |
| `--skip-cloud` | Skip wrangler/supabase/convex/vercel | Tag `cloud` + `enabled_by_default: false` |
| `--resume` | Resume from checkpoint | Orchestration (state.sh) |
| `--force-reinstall` | Start fresh | Orchestration |
| `--reset-state` | Delete state file | Orchestration |
| `--interactive` | Enable resume prompts | Orchestration |
| `--strict` | All tools critical (checksum abort) | Tag `critical` applied to all |
| `--skip-preflight` | Skip pre-flight checks | Orchestration |

### acfs update CLI Flags

| Flag | Behavior | Proposed Mapping |
|------|----------|------------------|
| `--apt-only` | Only apt packages | Category filter: `base`, `cli` |
| `--agents-only` | Only coding agents | Category filter: `agents` |
| `--cloud-only` | Only cloud CLIs | Category filter: `cloud` |
| `--stack` | Include Dicklesworthstone stack | Category filter: `stack` |
| `--no-apt` | Skip apt | Exclude category: `base`, `cli` |
| `--no-agents` | Skip agents | Exclude category: `agents` |
| `--no-cloud` | Skip cloud CLIs | Exclude category: `cloud` |
| `--force` | Install missing tools | Reinstall mode |
| `--dry-run` | Preview changes | Orchestration |
| `--verbose` | Show details | Orchestration |

### acfs doctor CLI Flags

| Flag | Behavior | Notes |
|------|----------|-------|
| `--json` | Machine-readable output | Output format |
| `--quiet` | Exit code only | Output format |
| `--deep` | Functional tests | Test depth |

---

## Wizard Mode Defaults (bead mjt.2.2)

The website wizard currently uses a **hardcoded command**:
```bash
curl -fsSL "..." | bash -s -- --yes --mode vibe
```

### Current Wizard Flow (11 steps)

1. Choose Your OS (local)
2. Install Terminal (local)
3. Generate SSH Key (local)
4. Rent a VPS (external)
5. Create VPS Instance (external)
6. SSH Into Your VPS
7. Pre-Flight Check
8. **Run Installer** ← hardcoded `--yes --mode vibe`
9. Reconnect as Ubuntu
10. Status Check (`acfs doctor`)
11. Launch Onboarding

### Proposed Mode Presets for Manifest

```yaml
presets:
  # Default for wizard (beginner-friendly, maximum automation)
  wizard_default:
    mode: vibe
    flags: [--yes]
    modules:
      enabled: [all]
      disabled: []
    tags:
      require: [critical, recommended]
      optional: [cloud, database]

  # Expert mode (minimal, interactive)
  minimal:
    mode: safe
    flags: []
    modules:
      enabled: [base.*, shell.*, lang.*, cli.modern, agents.*]
      disabled: [db.*, cloud.*, stack.*]
    tags:
      require: [critical]
      optional: [recommended]

  # Full stack (everything including optional)
  full:
    mode: vibe
    flags: [--yes]
    modules:
      enabled: [all]
      disabled: []
    tags:
      require: [critical, recommended, optional]
```

### Legacy Flag → Module Tag Mapping

| Legacy Flag | Manifest Equivalent |
|-------------|---------------------|
| `--skip-postgres` | `db.postgres18: { enabled_by_default: false }` |
| `--skip-vault` | `tools.vault: { enabled_by_default: false }` |
| `--skip-cloud` | All modules with tag `cloud`: `enabled_by_default: false` |
| `--mode vibe` | Apply tag `vibe_mode` to security-related modules |

### Category → Wizard Step Mapping

| Category | Wizard Relevance | Install Phase |
|----------|------------------|---------------|
| `base` | Silent (required) | Phase 1-3 |
| `shell` | Silent (required) | Phase 4 |
| `cli` | Silent (required) | Phase 5 |
| `lang` | Silent (required) | Phase 6 |
| `agents` | Core value prop | Phase 7 |
| `cloud` | Optional (skippable) | Phase 8 |
| `db` | Optional (skippable) | Phase 8 |
| `stack` | Core value prop | Phase 9 |
| `acfs` | Silent (orchestration) | Phase 10 |

---

## Runtime Assets Inventory (bead mjt.2.3)

> Added: 2025-12-21 | curl|bash bootstrap dependencies

### Bootstrap Mechanism

In curl|bash mode, `install.sh` fetches assets from GitHub via `install_asset()`:
```bash
acfs_curl -o "$dest_path" "$ACFS_RAW/$rel_path"
# $ACFS_RAW = https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main
```

### Required Runtime Assets

| Asset Path | Target Location | Purpose |
|------------|-----------------|---------|
| `acfs/zsh/acfs.zshrc` | `~/.acfs/zsh/acfs.zshrc` | Shell configuration |
| `acfs/tmux/tmux.conf` | `~/.acfs/tmux/tmux.conf` | Tmux configuration |
| `packages/onboard/onboard.sh` | `~/.acfs/onboard/onboard.sh` | Onboard TUI script |
| `scripts/lib/logging.sh` | `~/.acfs/scripts/lib/logging.sh` | Logging library |
| `scripts/lib/gum_ui.sh` | `~/.acfs/scripts/lib/gum_ui.sh` | Gum UI helpers |
| `scripts/lib/security.sh` | `~/.acfs/scripts/lib/security.sh` | Checksum verification |
| `scripts/lib/doctor.sh` | `~/.acfs/scripts/lib/doctor.sh` | Doctor health checks |
| `scripts/lib/update.sh` | `~/.acfs/scripts/lib/update.sh` | Update functionality |
| `scripts/acfs-update` | `~/.acfs/bin/acfs-update` | Update wrapper command |
| `scripts/services-setup.sh` | `~/.acfs/scripts/services-setup.sh` | Services wizard |
| `checksums.yaml` | `~/.acfs/checksums.yaml` | Upstream checksums |
| `VERSION` | `~/.acfs/VERSION` | Version metadata |

### Onboard Lessons (8 files)

| Lesson File | Purpose |
|-------------|---------|
| `acfs/onboard/lessons/00_welcome.md` | Welcome message |
| `acfs/onboard/lessons/01_linux_basics.md` | Linux fundamentals |
| `acfs/onboard/lessons/02_ssh_basics.md` | SSH tutorial |
| `acfs/onboard/lessons/03_tmux_basics.md` | Tmux primer |
| `acfs/onboard/lessons/04_agents_login.md` | Agent authentication |
| `acfs/onboard/lessons/05_ntm_core.md` | NTM basics |
| `acfs/onboard/lessons/06_ntm_command_palette.md` | NTM commands |
| `acfs/onboard/lessons/07_flywheel_loop.md` | Workflow loop |

### Scripts Not Downloaded (embedded/generated)

These are sourced via download at runtime or not used in finalize:

| Script | Status | Notes |
|--------|--------|-------|
| `scripts/lib/context.sh` | Downloaded early | Error context tracking |
| `scripts/lib/state.sh` | Not installed | Resume state management |
| `scripts/lib/tools.sh` | Not installed | Checksum tool definitions |
| `scripts/lib/errors.sh` | Not installed | Error pattern database |
| `scripts/generated/*.sh` | Not used | Generated by manifest package |
| `scripts/preflight.sh` | Not installed | Pre-flight checks |

### Bootstrap Order Dependencies

```
1. install.sh (downloaded via curl)
2. scripts/lib/context.sh (downloaded for try_step)
3. [checksums.yaml downloaded for verification]
4. [verified upstream scripts fetched and executed]
5. finalize() installs runtime assets
```

### Manifest Implications

For manifest-driven bootstrap, the following asset categories need specification:

```yaml
assets:
  # Core shell configuration
  shell_config:
    - src: acfs/zsh/acfs.zshrc
      dest: ~/.acfs/zsh/acfs.zshrc
      mode: 644

  # Runtime scripts (installed to ~/.acfs/)
  runtime_scripts:
    - src: scripts/lib/doctor.sh
      dest: ~/.acfs/scripts/lib/doctor.sh
      mode: 755
    # ... etc

  # Onboard lessons (pattern-based)
  lessons:
    pattern: acfs/onboard/lessons/*.md
    dest: ~/.acfs/onboard/lessons/
    mode: 644

  # Metadata
  metadata:
    - src: checksums.yaml
    - src: VERSION
```

---

## Next Steps

1. **mjt.1.1**: Define module taxonomy (categories/tags/defaults) using this gap analysis
2. **mjt.3.1**: Implement schema vNext fields based on identified gaps
3. Close parent epic **mjt.2** (all children now complete)
