# ACFS Manifest Schema vNext Reference

Internal maintainer reference for the manifest-driven installer system.

**Version:** 2.0.0
**Bead:** mjt.3.6, bd-mitxy
**Last Updated:** 2026-05-08

## Overview

The ACFS manifest (`acfs.manifest.yaml`) is the single source of truth for all tools installed by the Agentic Coding Flywheel Setup. This document describes the schema vNext fields, validation rules, and maintainer workflows.

## Manifest Structure

```yaml
version: 2                # Schema version
name: agentic_coding_flywheel_setup
id: acfs                  # Short identifier (lowercase alphanumeric + underscores)

defaults:
  user: ubuntu            # Target user for installation
  workspace_root: /data/projects
  mode: vibe              # Installation mode (vibe|safe)

modules:
  - id: shell.zsh
    description: ...
    # ... module fields
```

## Module Fields Reference

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique namespace identifier matching `/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$/`. When `category` is omitted, the first segment must be a canonical category; explicit-category and plugin IDs may use another namespace. |
| `description` | string | Human-readable description (non-empty) |
| `verify` | string[] | Commands to verify installation succeeded (at least one required) |

### Execution Context Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `run_as` | enum | `target_user` | Execution context for install/verify. Options: `target_user`, `root`, `current` |
| `phase` | int | 1 | Execution phase (1-10). Lower phases run first |
| `category` | enum | ID prefix | Generated-layout authority. One of `base`, `users`, `filesystem`, `shell`, `cli`, `network`, `lang`, `tools`, `db`, `cloud`, `agents`, `stack`, `acfs`. When omitted, the canonical first ID segment is used. |

**run_as Values:**
- `target_user` - Run as the configured target user (defaults.user)
- `root` - Run with root privileges (sudo)
- `current` - Run as the current shell user

**Phase Guidelines:**
- Phase 1: Base apt packages
- Phase 2: User normalization
- Phase 3: Filesystem setup
- Phase 4: Shell configuration
- Phase 5: CLI tools
- Phase 6: Language runtimes + shell tools (atuin, zoxide, ast-grep)
- Phase 7: AI agents (Claude, Codex, Gemini)
- Phase 8: Cloud tools + databases (Vault, PostgreSQL, Wrangler, Supabase, Vercel)
- Phase 9: Stack tools (ntm, mcp_agent_mail, cass, etc.)
- Phase 10: ACFS utilities (onboard, doctor)

### Installation Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `install` | string[] | `[]` | Shell commands to run during installation |
| `verified_installer` | object | (none) | Reference to upstream installer with checksum verification |
| `installed_check` | object | (none) | Command to check if already installed (skip logic) |
| `generated` | bool | `true` | If false, no bash function is generated and validation requires a registered authored orchestration handler (currently only `users.ubuntu`); all other false values fail closed with `ORCHESTRATION_HANDLER_MISSING` |

**verified_installer Schema:**
```yaml
verified_installer:
  tool: bun              # Key in checksums.yaml
  runner: bash           # Executable (bash, sh)
  args: []               # Additional arguments
```

**installed_check Schema:**
```yaml
installed_check:
  run_as: target_user    # Context for the check
  command: "command -v zsh && test -f ~/.zshrc"
```

### Selection/Filtering Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `optional` | bool | `false` | If true, failures are warnings not errors |
| `enabled_by_default` | bool | `true` | If false, must be explicitly enabled |
| `dependencies` | string[] | `[]` | Module IDs this module depends on |
| `tags` | string[] | `[]` | Tags for higher-level selection (`--only agents`) |
| `aliases` | string[] | `[]` | Alternative names for this module |

**Common Tags:**
- `critical` - Required for base functionality
- `recommended` - Should install unless explicitly skipped
- `optional` - Nice to have, not required
- `orchestration` - Descriptive/selection metadata only; it does not disable generation (that requires `generated: false` plus a registered authored handler)
- `runtime` - Language runtime (bun, uv, rust, go)
- `agent` - AI coding agent (Claude, Codex, Gemini)
- `shell-ux` - Affects shell experience
- `cli-modern` - Modern CLI tool replacements
- `cloud` - Cloud provider integrations
- `database` - Database tools

## Module Selection Resolver Contract

This contract defines the shared selection behavior that `install.sh`, generated manifest metadata, the website command builder, and the future onboarding TUI must converge on. There must be one resolver semantics model: UI profiles and repair commands map into the selectors below, then the resolver produces the effective plan. No UI surface should maintain a separate dependency graph or copy of module defaults.

### Contract Owners

| Surface | Responsibility |
|---------|----------------|
| `acfs.manifest.yaml` | Source of truth for module IDs, phases, categories, tags, defaults, dependencies, verification, and verified-installer usage |
| `packages/manifest/src/generate.ts` | Sorts modules deterministically and emits data-only Bash arrays in `scripts/generated/manifest_index.sh` |
| `scripts/generated/manifest_index.sh` | Runtime metadata bridge: `ACFS_MODULES_IN_ORDER`, `ACFS_CATEGORIES_IN_ORDER`, `ACFS_MODULE_PHASE`, `ACFS_MODULE_DEPS`, `ACFS_MODULE_FUNC` (generated modules only), `ACFS_MODULE_GENERATED`, `ACFS_MODULE_CATEGORY`, `ACFS_MODULE_TAGS`, `ACFS_MODULE_DEFAULT`, and installed-check arrays |
| `scripts/lib/install_helpers.sh` | Runtime resolver implementation: validates selectors, expands dependencies, applies skips, and populates `ACFS_EFFECTIVE_PLAN`, `ACFS_EFFECTIVE_RUN`, `ACFS_PLAN_REASON`, and `ACFS_PLAN_EXCLUDE_REASON` |
| `install.sh` | Parses CLI flags, maps legacy skip flags, calls the resolver before mutation, prints `--print-plan`, and executes only modules in the effective plan |
| `apps/web/lib/commandBuilder.ts` | Emits installer commands. Today this only passes mode, ref, and target user; future profile controls must serialize to the same public selectors |
| `packages/onboard/` | Future TUI selector UI. It must display profiles and modules from generated/shared metadata and submit the same selector payload |

### Selector Inputs

The resolver input model is additive and order-independent except where precedence is explicitly stated.

| Input | CLI today | Meaning |
|-------|-----------|---------|
| Install mode | `--mode safe`, `--mode vibe` | Controls installer behavior and copy. It does not change module selection by itself. |
| Explicit modules | Repeated `--only <module-id>` | Start from these module IDs. Unknown IDs are errors. |
| Explicit phases | Repeated `--only-phase <phase-or-alias>` | Start from all modules in those phases. Unknown phases are errors. |
| Explicit skips | Repeated `--skip <module-id>` | Exclude these module IDs. Unknown IDs are errors. |
| Legacy skips | `--skip-postgres`, `--skip-vault`, `--skip-cloud` | Compatibility wrappers that append concrete module IDs to `SKIP_MODULES`. New selectors should not add new legacy flags. |
| Skip tags | Internal `SKIP_TAGS` array | Exclude modules whose generated tag list contains the tag. Not currently exposed as a public CLI flag. |
| Skip categories | Internal `SKIP_CATEGORIES` array | Exclude modules whose generated category matches the category. Not currently exposed as a public CLI flag. |
| Dependency mode | `--no-deps` | Disables recursive dependency closure and dependency-skip errors, except direct `--only`/`--skip` contradictions still fail. |
| Plan mode | `--print-plan` | Resolves the plan and exits before generated installers are sourced or any install mutation runs. |

When both `--only` and `--only-phase` are supplied, the current resolver gives `--only` precedence and ignores phase starts. Future profile and TUI surfaces must avoid generating both. If a richer selector UI needs mixed module and phase starts, add an explicit resolver test before changing this rule.

### Phase Aliases

`--only-phase` accepts either a phase number or one of the aliases below. Aliases are normalized before validation.

| Phase | Aliases |
|-------|---------|
| 1 | `base`, `base_deps`, `system` |
| 2 | `user_setup`, `user`, `users` |
| 3 | `filesystem`, `fs` |
| 4 | `shell_setup`, `shell` |
| 5 | `cli_tools`, `cli` |
| 6 | `languages`, `language`, `lang` |
| 7 | `agents`, `agent` |
| 8 | `cloud_db`, `cloud-db` |
| 9 | `stack` |
| 10 | `finalize`, `final` |

### Resolution Algorithm

Implementations must produce the same effective plan for the same manifest and selector payload:

1. Load `scripts/generated/manifest_index.sh`; fail if `ACFS_MANIFEST_INDEX_LOADED` is not true.
2. Normalize phase aliases.
3. Build `module_exists` and `phase_exists` from `ACFS_MODULES_IN_ORDER` and `ACFS_MODULE_PHASE`.
4. Choose the starting set:
   - if `ONLY_MODULES` is non-empty, validate each module and mark it `explicitly requested`;
   - else if `ONLY_PHASES` is non-empty, validate each phase and mark modules in those phases as `phase <n>`;
   - else include every module whose `ACFS_MODULE_DEFAULT` value is `1` or `true` and mark it `default`.
5. Validate each explicit skip module and build the skip set.
6. Add modules selected by internal `SKIP_TAGS` and `SKIP_CATEGORIES` to the skip set.
7. Fail if a module appears in both `ONLY_MODULES` and the skip set. The failure must name the module and the skip reason.
8. Remove skipped modules from the desired set and record `ACFS_PLAN_EXCLUDE_REASON`.
9. If `NO_DEPS` is false, walk dependencies from every desired module and fail if any dependency chain reaches a skipped module. The failure must include the chain.
10. If `NO_DEPS` is false, recursively add every dependency from `ACFS_MODULE_DEPS`, including dependencies that are disabled by default. Unknown dependencies are manifest errors.
11. If `NO_DEPS` is true, do not add dependencies and print a prominent warning.
12. Emit `ACFS_EFFECTIVE_PLAN` by iterating `ACFS_MODULES_IN_ORDER`; this preserves phase order and topological order from the generator.
13. Emit `ACFS_EFFECTIVE_RUN[module]=1` for every included module and exclusion reasons for everything not included.

### Required Core Modules

The resolver does not hard-code a separate required-module list. Requiredness is expressed through dependencies, `enabled_by_default`, and tags such as `critical`. A skip is allowed only when it does not break the selected dependency graph, or when `--no-deps` is explicitly set for debugging. User-facing profile UIs must explain any skipped `critical` module before generating a command, and the generated command should prefer `--print-plan` first.

### Profiles and Groups

Profiles are UI conveniences, not resolver modes. A profile must lower to explicit modules, phases, or skips before resolution.

| Profile or group | Selector payload | Notes |
|------------------|------------------|-------|
| `full` | no `--only` or `--only-phase`; no profile skips | Installs every `enabled_by_default` module plus any dependencies. |
| `safe` | `--mode safe`; no selection change | Same module set as `full` unless the user adds selectors. |
| `vibe` | `--mode vibe`; no selection change | Same module set as `full` unless the user adds selectors. |
| `minimal` | explicit allowlist below, then resolved with dependencies | Intended for the smallest supported beginner install. Until implemented, do not fake this in the web app with a handwritten list. |
| `agents-only` | `--only-phase agents` | Includes agent modules plus dependencies such as `lang.bun` and `lang.nvm`. |
| `cloud-only` | `--only cloud.wrangler --only cloud.supabase --only cloud.vercel` | Includes cloud CLIs plus dependencies. Use `--only-phase cloud-db` only when Vault and PostgreSQL should also be included. |
| `stack-only` | `--only-phase stack` | Includes stack and utility modules in phase 9 plus dependencies. |

If a profile needs a curated list rather than a phase, add the list to a shared generated metadata artifact and cover it with resolver fixture tests. Do not duplicate the list in `install.sh`, the web app, and the TUI.

The initial `minimal` allowlist is:

```text
shell.omz
cli.modern
lang.bun
lang.uv
agents.claude
agents.codex
agents.gemini
stack.ntm
stack.mcp_agent_mail
stack.ultimate_bug_scanner
stack.beads_rust
stack.beads_viewer
stack.cass
stack.cm
stack.dcg
stack.ru
stack.rch
acfs.workspace
acfs.onboard
acfs.update
acfs.doctor
```

Dependency closure adds required prerequisites such as `base.system`, `users.ubuntu`, `base.filesystem`, `shell.zsh`, `lang.rust`, `lang.go`, `lang.nvm`, and `tools.ast_grep` where the manifest graph requires them. The minimal profile intentionally excludes optional cloud/database modules, optional agents such as `agents.opencode`, broad utility extras, nightly auto-update, and non-essential shell/CLI niceties unless the user adds them explicitly.

### Examples

Default vibe install:

```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh" \
  | bash -s -- --yes --mode vibe --print-plan
```

Safe mode with the same default module set:

```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh" \
  | bash -s -- --yes --mode safe --print-plan
```

Minimal profile, once a shared profile artifact exists:

```bash
curl -fsSL "..." | bash -s -- --yes --profile minimal --print-plan
```

Until `--profile` exists, UIs must not emit that command. They should either hide the profile or lower it to tested `--only` selectors from shared metadata.

Cloud-only plan:

```bash
curl -fsSL "..." | bash -s -- --yes \
  --only cloud.wrangler \
  --only cloud.supabase \
  --only cloud.vercel \
  --print-plan
```

Stack-only plan:

```bash
curl -fsSL "..." | bash -s -- --yes --only-phase stack --print-plan
```

Invalid selector examples that must fail before mutation:

```bash
curl -fsSL "..." | bash -s -- --yes --only agents.not_real --print-plan
# Error: Unknown module id in --only: agents.not_real

curl -fsSL "..." | bash -s -- --yes --only agents.codex --skip lang.bun --print-plan
# Error: Selection error: agents.codex depends on skipped lang.bun
# Error: Dependency chain: agents.codex -> lang.bun

curl -fsSL "..." | bash -s -- --yes --only agents.codex --skip agents.codex --no-deps --print-plan
# Error: Selection error: agents.codex was requested with --only and excluded by explicitly skipped
```

### Fixture Requirements

Resolver tests should be writable from this contract without reading historical discussion. Every shared fixture should include:

- `name`: stable scenario name.
- `input`: mode, explicit modules, phases, skips, skip tags, skip categories, dependency mode, and profile if present.
- `expected_included`: ordered module IDs from `ACFS_EFFECTIVE_PLAN`.
- `expected_excluded`: module IDs with exclusion reasons when relevant.
- `expected_errors`: exact error fragments for invalid selectors.
- `expected_warnings`: warning fragments, especially for `--no-deps`.

The minimum fixture set must cover default `safe`, default `vibe`, `minimal` profile lowering, `cloud-only`, `stack-only`, unknown module, unknown phase, direct `--only`/`--skip` contradiction, skipped dependency with and without `--no-deps`, legacy skip mapping, and deterministic plan ordering.

### Metadata Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `notes` | string[] | `[]` | Maintainer notes (not executed) |
| `docs_url` | string | (none) | URL to external documentation |

### Web Metadata Fields (`web` block)

The `web` block drives website content generation. All fields are optional; the entire block is optional on a module. Modules without `web` (or with `web.visible: false`) are not displayed on the website.

| Field | Type | Max Length | Description |
|-------|------|------------|-------------|
| `display_name` | string | 100 | Full display name for UI (e.g., "MCP Agent Mail") |
| `short_name` | string | 30 | Abbreviated name (e.g., "MAM") |
| `tagline` | string | 200 | One-line marketing tagline |
| `short_desc` | string | 500 | 1-2 sentence description |
| `icon` | string | 50 | Lucide icon name, kebab-case (e.g., "terminal-square") |
| `color` | string | 7 | 6-digit hex color (e.g., "#3B82F6") |
| `category_label` | string | 50 | Category for UI grouping (e.g., "Stack Tools") |
| `href` | string | - | Internal path (e.g., "/learn/tools/agent-mail") or external URL |
| `features` | string[] | 20 items | Feature bullet points |
| `tech_stack` | string[] | 20 items | Technologies used (e.g., ["Rust", "SQLite"]) |
| `use_cases` | string[] | 20 items | When to use this tool |
| `language` | string | 30 | Primary programming language |
| `stars` | int | - | GitHub stars count |
| `cli_name` | string | 30 | CLI command name (e.g., "am") |
| `cli_aliases` | string[] | 10 items | Alternate CLI names |
| `command_example` | string | 200 | Example usage (e.g., "am --help") |
| `lesson_slug` | string | 100 | Lesson page slug (e.g., "agent-mail") |
| `tldr_snippet` | string | 500 | Quick summary for TL;DR page |
| `visible` | bool | true | Set false to hide from web |

**Security Constraints:**
- `icon` must be lowercase kebab-case (Lucide icons)
- `color` must be 6-digit hex to prevent CSS injection
- `href` must be absolute path (`/...`) or full URL (`https://...`)
- `cli_name` must be lowercase alphanumeric with hyphens/underscores

## Examples

### Standard Module (apt packages)

```yaml
- id: cli.modern
  description: Modern CLI tools
  category: cli
  phase: 5
  run_as: root
  optional: false
  enabled_by_default: true
  tags: [recommended, cli-modern]
  dependencies:
    - base.system
  installed_check:
    run_as: current
    command: "command -v rg && command -v fzf"
  install:
    - apt-get install -y ripgrep fzf tmux
  verify:
    - rg --version
    - fzf --version
```

### Verified Installer Module

```yaml
- id: lang.bun
  description: Bun JavaScript runtime
  category: lang
  phase: 6
  run_as: target_user
  optional: false
  enabled_by_default: true
  tags: [critical, runtime]
  dependencies:
    - base.system
  verified_installer:
    tool: bun
    runner: bash
    args: []
  installed_check:
    run_as: target_user
    command: "command -v bun"
  install: []  # Empty - handled by verified_installer
  verify:
    - bun --version
```

### Orchestration-Only Module

```yaml
- id: users.ubuntu
  description: Ensure ubuntu user exists with proper permissions
  category: users
  phase: 2
  run_as: root
  optional: false
  enabled_by_default: true
  generated: false  # No bash function generated
  tags: [orchestration, critical]
  notes:
    - "Ensure user ubuntu exists with home /home/ubuntu"
    - "Write /etc/sudoers.d/90-ubuntu-acfs for passwordless sudo"
  install: []
  verify:
    - id ubuntu
    - sudo -n true
```

### Module with Web Metadata

```yaml
- id: stack.mcp_agent_mail
  description: MCP-based agent coordination via mail-like messaging
  category: stack
  phase: 9
  run_as: target_user
  optional: false
  enabled_by_default: true
  tags: [stack, recommended, agent-infra]
  dependencies:
    - lang.uv
    - stack.ntm
  verified_installer:
    tool: mcp_agent_mail
    runner: bash
    args: []
  installed_check:
    run_as: target_user
    command: "command -v am"
  install: []
  verify:
    - am --version
  docs_url: https://github.com/Dicklesworthstone/mcp_agent_mail
  web:
    display_name: "MCP Agent Mail"
    short_name: "MAM"
    tagline: "Agent-to-agent coordination via mail-like messaging"
    short_desc: "MCP-based messaging system for multi-agent coordination with file reservations, inboxes, and thread management."
    icon: "mail"
    color: "#8B5CF6"
    category_label: "Stack Tools"
    href: "/learn/tools/agent-mail"
    features:
      - "Agent identity registration"
      - "Threaded messaging with inboxes"
      - "Advisory file reservations"
      - "Git-backed persistence"
    tech_stack: ["Python", "SQLite", "MCP"]
    use_cases:
      - "Multi-agent coordination on shared codebases"
      - "Preventing agent edit conflicts"
      - "Asynchronous agent communication"
    language: "Python"
    stars: 450
    cli_name: "am"
    cli_aliases: []
    command_example: "am send BlueLake 'Review PR #42'"
    lesson_slug: "agent-mail"
    tldr_snippet: "Agent Mail provides messaging and file reservation for multi-agent workflows."
    visible: true
```

### Optional Cloud Tool (Legacy Pattern)

```yaml
- id: cloud.gcloud
  description: Google Cloud CLI
  category: cloud
  phase: 8
  run_as: root
  optional: true          # Failures are warnings
  enabled_by_default: false  # Must be explicitly requested
  tags: [cloud, optional]
  dependencies:
    - base.system
  installed_check:
    run_as: current
    command: "command -v gcloud"
  install:
    # NOTE: curl|bash is a legacy pattern. New modules should use
    # verified_installer with checksums.yaml for security.
    - curl https://sdk.cloud.google.com | bash
  verify:
    - gcloud --version
```

## Validation Rules

The manifest is validated at parse time. Validation runs in order:

### 1. Schema Validation (Zod)

- All required fields must be present
- Field types must match schema
- Module IDs must match pattern: `/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$/`
- Phase must be 1-10
- At least one verify command required

**Error Example:**
```
Module ID must be lowercase with dots (e.g., "shell.zsh", "lang.bun")
```

### 2. Dependency Existence

Every dependency must reference an existing module ID.

**Error Example:**
```
[MISSING_DEPENDENCY] Module "lang.bun" depends on "base.core" which does not exist
  → Check spelling or add the missing module
```

### 3. Cycle Detection

Dependencies must form a DAG (no cycles).

**Error Example:**
```
[DEPENDENCY_CYCLE] Dependency cycle detected: a → b → c → a
  → Remove one dependency to break the cycle
```

### 4. Phase Ordering

Dependencies must be in the same or earlier phase.

**Error Example:**
```
[PHASE_VIOLATION] Module "shell.zsh" (phase 4) depends on "agents.claude" (phase 7)
  → Move dependency to earlier phase or move module to later phase
```

### 5. Function Name Uniqueness

Generated module function names must be unique. IDs `lang.foo_bar` and
`lang.foo.bar` both generate `acfs_generated_install_lang_foo_bar`.

**Error Example:**
```
[FUNCTION_NAME_COLLISION] Module "lang.foo.bar" generates function "acfs_generated_install_lang_foo_bar"
which collides with "lang.foo_bar"
  → Rename one of the colliding modules to use a different ID
```

### 6. Private Generated Namespace

Every generated module installer uses the
`acfs_generated_install_<module_id_with_dots_as_underscores>` prefix. Category
files are source-only libraries; they intentionally expose no public
`install_<category>()` aggregate. `acfs_generated_install_all()` remains a
private sourceable generated-module harness, but generated files refuse direct execution because
only production `install.sh` owns installed checks, aggregate failures, and
authored orchestration handoffs. The private prefix prevents module IDs from
shadowing library or shell-builtin functions; collision validation rejects two
generated module IDs that normalize to the same private name.

### 7. Authored Orchestration Ownership

`generated: false` is a closed allowlist, not a general escape hatch. The
validator requires a registered production handler for each such module and
currently accepts only `users.ubuntu`. Any other ID fails with
`ORCHESTRATION_HANDLER_MISSING`, preventing a manifest entry from silently
disappearing from generated execution.

## Web Content Generation

The manifest generates TypeScript data files for the Next.js website. This keeps website content in sync with what gets installed.

### Generated Files

| File | Purpose |
|------|---------|
| `apps/web/lib/generated/manifest-tools.ts` | Tool cards for flywheel page and learn section |
| `apps/web/lib/generated/manifest-tldr.ts` | TL;DR page tool summaries |
| `apps/web/lib/generated/manifest-commands.ts` | CLI command reference |
| `apps/web/lib/generated/manifest-lessons-index.ts` | Lesson navigation index |
| `apps/web/lib/generated/manifest-web-index.ts` | Re-exports all generated modules |

**IMPORTANT:** Never edit files in `apps/web/lib/generated/`. They are overwritten on every generation.

### Web Generation Workflow

1. **Add web metadata** to the module's `web` block in `acfs.manifest.yaml`
2. **Regenerate**: `cd packages/manifest && bun run generate`
3. **Verify no drift**: `bun run generate:diff` (should exit 0)
4. **Build website** to verify: `cd apps/web && bun run build`
5. **Commit** both `acfs.manifest.yaml` and `apps/web/lib/generated/*`

### Migration Checklist (Adding New Tool to Website)

```bash
# 1. Edit manifest - add web block to module
vim acfs.manifest.yaml

# 2. Regenerate web data
cd packages/manifest && bun run generate

# 3. Verify generated files are in sync
bun run generate:diff

# 4. Type-check and build website
cd apps/web
bun run type-check
bun run build

# 5. Commit everything together
git add acfs.manifest.yaml apps/web/lib/generated/
git commit -m "feat(manifest): add web metadata for <tool-name>"
```

### CI Integration

The GitHub Actions workflows (`playwright.yml`, `website.yml`) include a `verify-generated` job that runs `bun run generate:diff` before building. This ensures:
- Generated files match the manifest
- No manual edits to generated files sneak through
- Website builds use current manifest data

## Maintainer Workflows

### Adding a New Module

1. **Choose ID and category**: Use `category.name` (for example, `tools.lazygit`) when the namespace begins with a canonical category. Plugin or alternate namespaces must set the canonical `category` explicitly.
2. **Set Phase**: Match dependency phase requirements
3. **Define Dependencies**: List module IDs this depends on
4. **Add installed_check**: For idempotent skip-if-present logic
5. **Add install Commands**: Or use verified_installer for upstream scripts
6. **Add verify Commands**: At least one required
7. **Validate**: Run the generator in dry-run mode to check for errors
8. **Regenerate**: Run the generator to update bash scripts

```bash
# Validate manifest (dry-run shows errors without writing files)
cd packages/manifest && bun run generate:dry

# Generate bash scripts
cd packages/manifest && bun run generate
```

### Checksums, Drift Checks, and Bootstrap Validation

When adding or modifying modules—especially ones that run upstream installers—follow this checklist to avoid manifest/installer drift and broken curl|bash installs:

1. **Checksums (verified installers only)**
   - Add the installer URL + SHA256 in `checksums.yaml`.
   - Use the security helper for updates:
     ```bash
     # Generate a candidate, then review before replacing the canonical file
     candidate="/tmp/acfs-checksums.$$.candidate.yaml"
     ./scripts/lib/security.sh --update-checksums > "$candidate"
     diff -u checksums.yaml "$candidate" || [[ $? -eq 1 ]]

     # Verify all checksums against upstream
     ./scripts/lib/security.sh --verify
     ```
   - Replace `checksums.yaml` only after the reviewed diff is limited to its
     timestamp header plus the intended tool entry. If only the timestamp
     changes, leave the canonical file unchanged; investigate any unrelated
     entry before replacement.

2. **Drift Check (CI parity)**
   ```bash
   cd packages/manifest
   bun run generate:diff   # ensures scripts/generated matches manifest
   bun run generate        # writes scripts/generated/**
   ```

3. **Bootstrap Validation (curl|bash path)**
   - Validate the archive bootstrap on the exact ref you intend to ship:
     ```bash
     # Run against a tag/sha or branch ref
     curl -fsSL \
       "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/<ref>/install.sh" \
       | bash -s -- --print-plan --ref <ref>
     ```
   - The bootstrap flow validates script syntax and ensures `scripts/generated/manifest_index.sh`
     matches `acfs.manifest.yaml`. It also parses the schema-1 internal checksum
     ledger as data (never sources it), enforces its closed checksum-controlled membership,
     and verifies tracked regular non-symlink files before sourcing them. This
     proves internal consistency; it is not an independent archive signature.

4. **Smoke Sanity (optional but recommended)**
   ```bash
   bash scripts/lib/test_install_helpers.sh
   bash scripts/lib/test_contract.sh
   ```

### Modifying an Existing Module

1. **Check Dependents**: Find modules that depend on this one
2. **Update Carefully**: Changes affect generation output
3. **Validate**: Ensure no phase/dependency violations introduced
4. **Regenerate**: Update generated scripts

```bash
# Find modules that depend on a specific module (e.g., lang.bun)
grep -B15 -- "- lang.bun" acfs.manifest.yaml | grep "^  - id:"
```

### Debugging Validation Errors

```bash
cd packages/manifest

# Dry-run: validates manifest and shows what would be generated (no file writes)
bun run generate:dry

# Full generation: validates and writes files to scripts/generated/
bun run generate
```

## Generated Output

The generator produces:
- `scripts/generated/install_<category>.sh` - Source-only category function libraries (for example, `install_lang.sh`, `install_cli.sh`)
- `scripts/generated/install_all.sh` - Sourceable harness that loads those libraries and calls generated module functions in global dependency order; it is not a supported direct installer
- `scripts/generated/manifest_index.sh` - Module metadata for runtime queries
- `scripts/generated/doctor_checks.sh` - Health check functions
- `scripts/generated/internal_checksums.sh` - Schema-1 data-only runtime checksum map with an exact entry count

### Function Naming

Module ID `lang.bun` generates:
- Function: `acfs_generated_install_lang_bun()`
- Location: Inside `scripts/generated/install_lang.sh` (grouped by category)

### Execution Model

```bash
# Generated orchestrator pseudocode
acfs_generated_install_all() {
  # Phase 1
  acfs_generated_install_base_system || handle_error

  # generated:false modules such as users.ubuntu are deliberately omitted;
  # production install.sh owns their authored orchestration handlers.

  # ... continues by phase
}
```

## File Locations

| Path | Description |
|------|-------------|
| `acfs.manifest.yaml` | Source of truth manifest |
| `packages/manifest/src/schema.ts` | Zod schema definitions |
| `packages/manifest/src/types.ts` | TypeScript type definitions |
| `packages/manifest/src/validate.ts` | Validation logic |
| `packages/manifest/src/generate.ts` | Bash script generator |
| `scripts/generated/` | Generated bash scripts (committed to git) |
| `checksums.yaml` | Verified installer checksums |

## Related Beads

- `mjt.3.1` - Implement schema vNext fields (Zod + TS types)
- `mjt.3.2` - Add manifest validation (deps, cycles, phases)
- `mjt.3.3` - Add generated function-name collision validation
- `mjt.3.4` - Migrate acfs.manifest.yaml to schema vNext
- `mjt.3.5` - Migrate remote installers to verified_installer
- `mjt.3.6` - Document schema vNext (this document)
