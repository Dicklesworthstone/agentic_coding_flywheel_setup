# ACFS Maintainer Guide

Internal reference for maintaining the ACFS installer and manifest.

## Manifest-Driven Architecture

ACFS uses a single source of truth pattern:

```
acfs.manifest.yaml
       ↓
packages/manifest/src/generate.ts
       ↓
scripts/generated/
       ↓
install.sh (orchestrator)
```

The manifest defines what gets installed. The generator produces bash functions. The installer orchestrates execution.

### Web Content Generation

The manifest also drives web content (tools, TL;DR, commands, lessons). Modules with a `web` block generate TypeScript data files consumed by the Next.js website.

```
acfs.manifest.yaml (web metadata)
       ↓
packages/manifest/src/generate.ts
       ↓
apps/web/lib/generated/
├── manifest-tools.ts      # Tool cards for flywheel/learn pages
├── manifest-tldr.ts       # TL;DR summaries
├── manifest-commands.ts   # CLI command reference
├── manifest-lessons-index.ts  # Lesson navigation index
└── manifest-web-index.ts  # Re-exports all above
```

**IMPORTANT:** Files in `apps/web/lib/generated/` are auto-generated. Never edit them directly.

## Adding a New Module

### 1. Add to acfs.manifest.yaml

```yaml
modules:
  - id: category.toolname
    name: Tool Name
    category: category  # base, shell, cli, lang, tools, agents, db, cloud, stack, acfs
    phase: 6            # Execution order (0-10)
    enabled_by_default: true  # Include in default install
    
    # Installation
    run_as: target_shell  # root, target, target_shell, current, current_shell
    install:
      - command1
      - command2
    
    # Verification (for acfs doctor)
    installed_check: command -v toolname
    verify:
      - toolname --version
    
    # Optional
    optional: false       # If true, failure doesn't kill install
    dependencies:         # Module IDs that must run first
      - lang.bun
    tags:
      - dev-tools
```

### 2. Add Checksums (for external scripts)

If the module downloads scripts from external URLs, add checksums to `checksums.yaml`:

```yaml
scripts:
  https://example.com/install.sh: sha256:abc123...
```

Generate checksums:
```bash
curl -fsSL "https://example.com/install.sh" | sha256sum
```

### 3. Regenerate

```bash
cd packages/manifest
bun run generate
```

Or with the pre-commit hook:
```bash
./scripts/hooks/install.sh  # One-time hook setup
git add acfs.manifest.yaml
git commit  # Hook auto-regenerates
```

### 4. Add Web Metadata (Optional)

If the tool should appear on the website (flywheel page, TL;DR, learn section), add a `web` block:

```yaml
modules:
  - id: stack.newtool
    # ... install/verify fields ...
    web:
      display_name: "New Tool"
      short_name: "NT"
      tagline: "One-line description of what it does"
      short_desc: "Slightly longer description (1-2 sentences)"
      icon: "terminal"           # Lucide icon name (kebab-case)
      color: "#3B82F6"           # Brand color (6-digit hex)
      category_label: "Stack Tools"
      href: "/learn/tools/newtool"   # Internal link or external URL
      features:
        - "Feature one"
        - "Feature two"
      tech_stack: ["Rust", "SQLite"]
      use_cases:
        - "When to use this tool"
      language: "Rust"
      cli_name: "nt"
      cli_aliases: ["newtool"]
      command_example: "nt status --json"
      lesson_slug: "newtool"     # Links to /learn/tools/newtool
      tldr_snippet: "Quick summary for TL;DR page"
      visible: true              # Set false to hide from web
```

See `docs/reference/MANIFEST_SCHEMA_VNEXT.md` for full field reference.

### 5. Validate

```bash
# Check for drift
cd packages/manifest && bun run generate --diff

# Syntax check all scripts
bash -n scripts/generated/*.sh

# Run selection tests
bash scripts/lib/test_selection.sh

# Full integration test
./tests/vm/test_install_ubuntu.sh
```

## run_as Modes

| Mode | Description | Use When |
|------|-------------|----------|
| `root` | Runs as root user | System packages, apt installs |
| `target` | Runs as target user | User config, no shell needed |
| `target_shell` | Target user with login shell | Most tools (needs PATH) |
| `current` | Current user context | Bootstrap scripts |
| `current_shell` | Current user with shell | Debugging |

## Verified Installers

For security, external install scripts must be:
1. HTTPS only
2. SHA256 checksummed in `checksums.yaml`
3. Listed in `KNOWN_INSTALLERS` (scripts/lib/security.sh)

The installer verifies checksums before execution.

## Testing Changes

### Local Testing

```bash
# Quick syntax check
bash -n install.sh scripts/lib/*.sh scripts/generated/*.sh

# Unit tests
bash scripts/lib/test_selection.sh
bash scripts/lib/test_contract.sh
bash scripts/lib/test_security.sh
bash scripts/lib/test_install_helpers.sh

# Bootstrap simulation
bash tests/vm/bootstrap_offline_checks.sh
```

### Docker Integration

```bash
# Single Ubuntu version
./tests/vm/test_install_ubuntu.sh

# All supported versions
./tests/vm/test_install_ubuntu.sh --all

# Specific version
./tests/vm/test_install_ubuntu.sh --ubuntu 25.04
```

### CI Checks

PR checks include:
- ShellCheck lint
- Manifest drift detection
- Selection/contract tests
- Full Docker integration matrix

## Common Tasks

### Updating a Tool Version

1. Edit `acfs.manifest.yaml` with new version
2. Update checksum if external script changed
3. Regenerate and test

### Adding a Skip Flag

Legacy skip flags are mapped in `scripts/lib/install_helpers.sh`:

```bash
if [[ "${SKIP_NEWTOOL:-false}" == "true" ]]; then
    SKIP_MODULES+=("category.newtool")
fi
```

### Debugging Selection

```bash
# Preview execution plan
./install.sh --print-plan

# List available modules
./install.sh --list-modules

# Test specific selection
./install.sh --only category.tool --print-plan
```

## Files Overview

| File | Purpose |
|------|---------|
| `acfs.manifest.yaml` | Module definitions (source of truth) |
| `checksums.yaml` | SHA256 hashes for external scripts |
| `packages/manifest/` | TypeScript generator |
| `scripts/generated/` | Generated bash functions (don't edit) |
| `scripts/lib/` | Installer libraries |
| `install.sh` | Orchestrator (thin wrapper) |
