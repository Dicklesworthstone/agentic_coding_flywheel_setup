# AGENTS.md — Agentic Coding Flywheel Setup (ACFS)

> Guidelines for AI coding agents working in this multi-component Bash/TypeScript codebase.

---

## RULE 0 - THE FUNDAMENTAL OVERRIDE PREROGATIVE

If I tell you to do something, even if it goes against what follows below, YOU MUST LISTEN TO ME. I AM IN CHARGE, NOT YOU.

---

## RULE NUMBER 1: NO FILE DELETION

**YOU ARE NEVER ALLOWED TO DELETE A FILE WITHOUT EXPRESS PERMISSION.** Even a new file that you yourself created, such as a test code file. You have a horrible track record of deleting critically important files or otherwise throwing away tons of expensive work. As a result, you have permanently lost any and all rights to determine that a file or folder should be deleted.

**YOU MUST ALWAYS ASK AND RECEIVE CLEAR, WRITTEN PERMISSION BEFORE EVER DELETING A FILE OR FOLDER OF ANY KIND.**

---

## Irreversible Git & Filesystem Actions — DO NOT EVER BREAK GLASS

1. **Absolutely forbidden commands:** `git reset --hard`, `git clean -fd`, `rm -rf`, or any command that can delete or overwrite code/data must never be run unless the user explicitly provides the exact command and states, in the same message, that they understand and want the irreversible consequences.
2. **No guessing:** If there is any uncertainty about what a command might delete or overwrite, stop immediately and ask the user for specific approval. "I think it's safe" is never acceptable.
3. **Safer alternatives first:** When cleanup or rollbacks are needed, request permission to use non-destructive options (`git status`, `git diff`, `git stash`, copying to backups) before ever considering a destructive command.
4. **Mandatory explicit plan:** Even after explicit user authorization, restate the command verbatim, list exactly what will be affected, and wait for a confirmation that your understanding is correct. Only then may you execute it—if anything remains ambiguous, refuse and escalate.
5. **Document the confirmation:** When running any approved destructive command, record (in the session notes / final response) the exact user text that authorized it, the command actually run, and the execution time. If that record is absent, the operation did not happen.

---

## Git Branch: ONLY Use `main`, NEVER `master`

**The default branch is `main`. The `master` branch exists only for legacy URL compatibility.**

- **All work happens on `main`** — commits, PRs, feature branches all merge to `main`
- **Never reference `master` in code or docs** — if you see `master` anywhere, it's a bug that needs fixing
- **The `master` branch must stay synchronized with `main`** — after pushing to `main`, also push to `master`:
  ```bash
  git push origin main:master
  ```

**If you see `master` referenced anywhere:**
1. Update it to `main`
2. Ensure `master` is synchronized: `git push origin main:master`

---

## Toolchain: Bash & Bun

### Installer / Scripts: Bash

The installer and scripting layer uses **Bash** (POSIX-compatible where possible).

- **Linting:** `shellcheck` for all `.sh` files
- **Target OS:** Ubuntu 25.10 (installer auto-upgrades from 22.04+)
- **Idempotent:** Installer is safe to re-run; phases resume on failure
- **One-liner:** `curl -fsSL ... | bash -s -- --yes --mode vibe`

### Website: Bun & Next.js

Use **bun** for everything JS/TS. Never use `npm`, `yarn`, or `pnpm`.

- **Framework:** Next.js 16 App Router
- **Runtime:** Bun
- **Hosting:** Vercel + Cloudflare for cost optimization
- **Lockfiles:** Only `bun.lock`. Do not introduce any other lockfile.
- **Target:** Latest Node.js. No need to support old Node versions.
- **Note:** `bun install -g <pkg>` is valid syntax (alias for `bun add -g`). Do not "fix" it.

### Key Dependencies

| Component | Purpose |
|-----------|---------|
| `next` (16.x) | App Router framework for wizard website |
| `react` / `react-dom` (19.x) | UI rendering |
| `tailwindcss` (4.x) | Utility-first CSS |
| `@tanstack/react-form` | Form state management |
| `@tanstack/react-query` | Async state management |
| `framer-motion` | Animations |
| `@playwright/test` | E2E testing |
| `eslint` / `eslint-config-next` | Linting |
| `typescript` (5.x) | Type checking |

---

## Code Editing Discipline

### No Script-Based Changes

**NEVER** run a script that processes/changes code files in this repo. Brittle regex-based transformations create far more problems than they solve.

- **Always make code changes manually**, even when there are many instances
- For many simple changes: use parallel subagents
- For subtle/complex changes: do them methodically yourself

### No File Proliferation

If you want to change something or add a feature, **revise existing code files in place**.

**NEVER** create variations like:
- `install_v2.sh`
- `install_improved.sh`
- `install_enhanced.sh`

New files are reserved for **genuinely new functionality** that makes zero sense to include in any existing file. The bar for creating new files is **incredibly high**.

---

## Backwards Compatibility

We do not care about backwards compatibility—we're in early development with no users. We want to do things the **RIGHT** way with **NO TECH DEBT**.

- Never create "compatibility shims"
- Never create wrapper functions for deprecated APIs
- Just fix the code directly

---

## Compiler Checks (CRITICAL)

**After any substantive code changes, you MUST verify no errors were introduced:**

```bash
# Bash scripts: lint with shellcheck
shellcheck install.sh scripts/**/*.sh

# Website: type-check and lint
cd apps/web && bun run type-check && bun run lint

# Website: build verification
cd apps/web && bun run build
```

If you see errors, **carefully understand and resolve each issue**. Read sufficient context to fix them the RIGHT way.

## Verified Installer Checksum Discipline

ACFS treats `checksums.yaml` as a security boundary for any manifest module that uses `verified_installer`.

- **Whenever you change or release a tool whose ACFS manifest entry installs via `verified_installer`, you MUST run the canonical checksum refresh flow and review the diff.**
- **For `rch` specifically:** every new `remote_compilation_helper` release/version change must be followed by this checksum review in ACFS, even if you expect the installer script hash to stay the same.
- **Do not assume** a version bump is complete just because the upstream release exists; ACFS is still stale until the verified installer checksum is updated here.
- **Use the canonical updater, not a hand-edited checksum:** generate a candidate path such as `candidate="/tmp/acfs-checksums.$$.candidate.yaml"`, then compare it to `checksums.yaml`.
- **If unrelated installer entries changed too:** stop and investigate before replacing `checksums.yaml`, even if the target tool entry also changed.
- **If the diff is limited to the timestamp header plus the target tool entry:** replace `checksums.yaml` with the generated output.
- **If the only diff is the timestamp header:** leave `checksums.yaml` unchanged.
- Preferred targeted verification before or after regeneration:
  ```bash
  candidate="/tmp/acfs-checksums.$$.candidate.yaml"
  ./scripts/lib/security.sh --update-checksums > "$candidate"
  diff -u checksums.yaml "$candidate" || [[ $? -eq 1 ]]
  ./scripts/lib/security.sh --checksum https://raw.githubusercontent.com/Dicklesworthstone/remote_compilation_helper/main/install.sh
  awk '/^  rch:/{flag=1;print;next} flag && /^    /{print;next} flag{exit}' checksums.yaml
  awk '/^  rch:/{flag=1;print;next} flag && /^    /{print;next} flag{exit}' "$candidate"
  ```

---

## Testing

### Testing Policy

Scripts include integration tests. The website uses Playwright for E2E testing. Tests must cover:
- Happy path
- Edge cases (empty input, max values, boundary conditions)
- Error conditions

### Installer Tests

```bash
# Local lint
shellcheck install.sh scripts/lib/*.sh

# Full installer integration test (Docker, same as CI)
./tests/vm/test_install_ubuntu.sh
```

### Website Tests

```bash
cd apps/web
bun install                    # Install dependencies
bun run dev                    # Dev server
bun run build                  # Production build
bun run lint                   # ESLint check
bun run type-check             # TypeScript check
bun run test                   # Playwright E2E tests
```

### Test Structure

| Directory | Focus Areas |
|-----------|-------------|
| `tests/vm/` | Full installer integration tests (Docker-based, Ubuntu images) |
| `tests/e2e/` | End-to-end installer flow tests |
| `tests/unit/` | Unit tests for library functions |
| `tests/smoke/` | Quick smoke tests |
| `scripts/tests/` | Script-level tests (security, manifest drift, etc.) |
| `apps/web/e2e/` | Playwright production smoke tests |

---

## Third-Party Library Usage

If you aren't 100% sure how to use a third-party library, **SEARCH ONLINE** to find the latest documentation and current best practices.

---

## ACFS — This Project

**This is the project you're working on.** ACFS (Agentic Coding Flywheel Setup) is a multi-component project that takes a beginner from "I have a laptop" to a fully configured VPS with coding agents, dev tools, and coordination infrastructure.

### What It Does

Provides a step-by-step wizard website, a one-liner installer, and an onboarding TUI to configure Ubuntu VPS instances with a complete agentic coding environment: shell setup, languages, dev tools, coding agents, and the Dicklesworthstone coordination stack.

### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| Website Wizard | `apps/web/` | Next.js 16 App Router wizard guiding beginners |
| Installer | `install.sh` + `scripts/` | Bash installer, idempotent, checkpointed |
| Onboarding TUI | `packages/onboard/` | Interactive tutorial for Linux basics + agent workflow |
| Module Manifest | `acfs.manifest.yaml` | Single source of truth for all tools installed |
| ACFS Configs | `acfs/` | Shell, tmux, onboard configs installed to `~/.acfs/` |
| Manifest Parser | `packages/manifest/` | YAML parser + code generators |

### Repo Layout

```
agentic_coding_flywheel_setup/
├── README.md
├── install.sh                    # One-liner entrypoint
├── VERSION
├── acfs.manifest.yaml            # Canonical tool manifest
│
├── apps/
│   └── web/                      # Next.js 16 wizard website
│       ├── app/                  # App Router pages
│       ├── components/           # Shared UI components
│       ├── lib/                  # Utilities + manifest types
│       └── package.json
│
├── packages/
│   ├── manifest/                 # Manifest YAML parser + generators
│   ├── installer/                # Installer helper scripts
│   └── onboard/                  # Onboard TUI source
│
├── acfs/                         # Files copied to ~/.acfs on VPS
│   ├── zsh/
│   │   └── acfs.zshrc
│   ├── tmux/
│   │   └── tmux.conf
│   └── onboard/
│       └── lessons/
│
├── scripts/
│   ├── lib/                      # Installer library functions
│   ├── generated/                # Auto-generated from manifest (NEVER edit)
│   ├── providers/                # VPS provider guides
│   ├── tests/                    # Script-level tests
│   └── e2e/                      # E2E test scripts
│
└── tests/
    ├── vm/                       # Docker-based installer integration
    ├── e2e/                      # End-to-end flow tests
    ├── unit/                     # Unit tests
    └── smoke/                    # Quick smoke tests
```

### Generated Files — NEVER Edit Manually

The following files are **auto-generated** from the manifest. Edits to these files will be **overwritten** on the next regeneration.

```
scripts/generated/          # ALL files in this directory
├── install_*.sh           # Category installer scripts
├── doctor_checks.sh       # Doctor verification checks
└── manifest_index.sh      # Bash arrays with module metadata
```

**How to modify generated code:**

1. **Identify the generator source**: `packages/manifest/src/generate.ts`
2. **Modify the generator**, not the output files
3. **Regenerate**: `cd packages/manifest && bun run generate`
4. **Verify**: `shellcheck scripts/generated/*.sh`

### Installer Architecture

- **Auto-Upgrade:** Older Ubuntu versions are automatically upgraded to 25.10 before ACFS install
  - Upgrade path: 22.04 -> 24.04 -> 25.04 -> 25.10 (EOL interim releases like 24.10 may be skipped)
  - Takes 30-60 minutes per version hop; multiple reboots handled via systemd resume service
  - Skip with `--skip-ubuntu-upgrade` flag
- **One-liner:** `curl -fsSL ... | bash -s -- --yes --mode vibe`
- **Idempotent:** Safe to re-run
- **Checkpointed:** Phases resume on failure

### Console Output (for installer scripts)

The installer uses colored output for progress visibility:

```bash
echo -e "\033[34m[1/8] Step description\033[0m"     # Blue progress steps
echo -e "\033[90m    Details...\033[0m"             # Gray indented details
echo -e "\033[33m    Warning message\033[0m"        # Yellow warnings
echo -e "\033[31m    Error message\033[0m"          # Red errors
echo -e "\033[32m    Success message\033[0m"        # Green success
```

Rules:
- Progress/status goes to `stderr` (so stdout remains clean for piping)
- `--quiet` flag suppresses progress but not errors
- All output functions should use the logging library (`scripts/lib/logging.sh`)

### Third-Party Tools Installed by ACFS

These are installed on target VPS (not development machine).

> **OS Requirement:** Ubuntu 25.10 (installer auto-upgrades from 22.04+)

**Shell & Terminal UX:**
- **zsh** + **oh-my-zsh** + **powerlevel10k**
- **lsd** (or eza fallback) — Modern ls
- **atuin** — Shell history with Ctrl-R
- **fzf** — Fuzzy finder
- **zoxide** — Better cd
- **direnv** — Directory-specific env vars

**Languages & Package Managers:**
- **bun** — JS/TS runtime + package manager
- **uv** — Fast Python tooling
- **rust/cargo** — Rust toolchain
- **go** — Go toolchain

**Dev Tools:**
- **tmux** — Terminal multiplexer
- **ripgrep** (`rg`) — Fast search
- **ast-grep** (`sg`) — Structural search/replace
- **lazygit** — Git TUI
- **bat** — Better cat

**Coding Agents:**
- **Claude Code** — Anthropic's coding agent
- **Codex CLI** — OpenAI's coding agent
- **Gemini CLI** — Google's coding agent

**Cloud & Database:**
- **PostgreSQL 18** — Database
- **HashiCorp Vault** — Secrets management
- **Wrangler** — Cloudflare CLI
- **Supabase CLI** — Supabase management
- **Vercel CLI** — Vercel deployment

**Dicklesworthstone Stack (10 tools + utilities):**
1. **ntm** — Named Tmux Manager (agent cockpit)
2. **mcp_agent_mail** — Agent coordination via mail-like messaging
3. **ultimate_bug_scanner** (`ubs`) — Bug scanning with guardrails
4. **beads_viewer** (`bv`) — Task management TUI
5. **coding_agent_session_search** (`cass`) — Unified agent history search
6. **cass_memory_system** (`cm`) — Procedural memory for agents
7. **coding_agent_account_manager** (`caam`) — Agent auth switching
8. **simultaneous_launch_button** (`slb`) — Two-person rule for dangerous commands
9. **destructive_command_guard** (`dcg`) — Claude Code hook blocking dangerous commands
10. **repo_updater** (`ru`) — Multi-repo sync + AI-driven commit automation

**Utilities:**
- **giil** — Download cloud images (iCloud, Dropbox, Google Photos) for visual debugging
- **csctf** — Convert AI chat share links to Markdown/HTML archives

### Website Development (apps/web)

```bash
cd apps/web
bun install           # Install dependencies
bun run dev           # Dev server
bun run build         # Production build
bun run lint          # Lint check
bun run type-check    # TypeScript check
```

Key patterns:
- App Router: all pages in `app/` directory
- UI components: shadcn/ui + Tailwind CSS
- State: URL query params + localStorage (no backend)
- Wizard step content: defined in `lib/wizardSteps.ts` or MDX

---

## MCP Agent Mail — Multi-Agent Coordination

A mail-like layer that lets coding agents coordinate asynchronously via MCP tools and resources. Provides identities, inbox/outbox, searchable threads, and advisory file reservations with human-auditable artifacts in Git.

### Why It's Useful

- **Prevents conflicts:** Explicit file reservations (leases) for files/globs
- **Token-efficient:** Messages stored in per-project archive, not in context
- **Quick reads:** `resource://inbox/...`, `resource://thread/...`

### Same Repository Workflow

1. **Register identity:**
   ```
   ensure_project(project_key=<abs-path>)
   register_agent(project_key, program, model)
   ```

2. **Reserve files before editing:**
   ```
   file_reservation_paths(project_key, agent_name, ["src/**"], ttl_seconds=3600, exclusive=true)
   ```

3. **Communicate with threads:**
   ```
   send_message(..., thread_id="FEAT-123")
   fetch_inbox(project_key, agent_name)
   acknowledge_message(project_key, agent_name, message_id)
   ```

4. **Quick reads:**
   ```
   resource://inbox/{Agent}?project=<abs-path>&limit=20
   resource://thread/{id}?project=<abs-path>&include_bodies=true
   ```

### Macros vs Granular Tools

- **Prefer macros for speed:** `macro_start_session`, `macro_prepare_thread`, `macro_file_reservation_cycle`, `macro_contact_handshake`
- **Use granular tools for control:** `register_agent`, `file_reservation_paths`, `send_message`, `fetch_inbox`, `acknowledge_message`

### Common Pitfalls

- `"from_agent not registered"`: Always `register_agent` in the correct `project_key` first
- `"FILE_RESERVATION_CONFLICT"`: Adjust patterns, wait for expiry, or use non-exclusive reservation
- **Auth errors:** If JWT+JWKS enabled, include bearer token with matching `kid`

---

## Beads (br) — Dependency-Aware Issue Tracking

Beads provides a lightweight, dependency-aware issue database and CLI (`br` - beads_rust) for selecting "ready work," setting priorities, and tracking status. It complements MCP Agent Mail's messaging and file reservations.

**Important:** `br` is non-invasive—it NEVER runs git commands automatically. You must manually commit changes after `br sync --flush-only`.

### Conventions

- **Single source of truth:** Beads for task status/priority/dependencies; Agent Mail for conversation and audit
- **Shared identifiers:** Use Beads issue ID (e.g., `br-123`) as Mail `thread_id` and prefix subjects with `[br-123]`
- **Reservations:** When starting a task, call `file_reservation_paths()` with the issue ID in `reason`

### Typical Agent Flow

1. **Pick ready work (Beads):**
   ```bash
   br ready --json  # Choose highest priority, no blockers
   ```

2. **Reserve edit surface (Mail):**
   ```
   file_reservation_paths(project_key, agent_name, ["src/**"], ttl_seconds=3600, exclusive=true, reason="br-123")
   ```

3. **Announce start (Mail):**
   ```
   send_message(..., thread_id="br-123", subject="[br-123] Start: <title>", ack_required=true)
   ```

4. **Work and update:** Reply in-thread with progress

5. **Complete and release:**
   ```bash
   br close 123 --reason "Completed"
   br sync --flush-only  # Export to JSONL (no git operations)
   ```
   ```
   release_file_reservations(project_key, agent_name, paths=["src/**"])
   ```
   Final Mail reply: `[br-123] Completed` with summary

### Mapping Cheat Sheet

| Concept | Value |
|---------|-------|
| Mail `thread_id` | `br-###` |
| Mail subject | `[br-###] ...` |
| File reservation `reason` | `br-###` |
| Commit messages | Include `br-###` for traceability |

---

## bv — Graph-Aware Triage Engine

bv is a graph-aware triage engine for Beads projects (`.beads/beads.jsonl`). It computes PageRank, betweenness, critical path, cycles, HITS, eigenvector, and k-core metrics deterministically.

**Scope boundary:** bv handles *what to work on* (triage, priority, planning). For agent-to-agent coordination (messaging, work claiming, file reservations), use MCP Agent Mail.

**CRITICAL: Use ONLY `--robot-*` flags. Bare `bv` launches an interactive TUI that blocks your session.**

### The Workflow: Start With Triage

**`bv --robot-triage` is your single entry point.** It returns:
- `quick_ref`: at-a-glance counts + top 3 picks
- `recommendations`: ranked actionable items with scores, reasons, unblock info
- `quick_wins`: low-effort high-impact items
- `blockers_to_clear`: items that unblock the most downstream work
- `project_health`: status/type/priority distributions, graph metrics
- `commands`: copy-paste shell commands for next steps

```bash
bv --robot-triage        # THE MEGA-COMMAND: start here
bv --robot-next          # Minimal: just the single top pick + claim command
```

### Command Reference

**Planning:**
| Command | Returns |
|---------|---------|
| `--robot-plan` | Parallel execution tracks with `unblocks` lists |
| `--robot-priority` | Priority misalignment detection with confidence |

**Graph Analysis:**
| Command | Returns |
|---------|---------|
| `--robot-insights` | Full metrics: PageRank, betweenness, HITS, eigenvector, critical path, cycles, k-core, articulation points, slack |
| `--robot-label-health` | Per-label health: `health_level`, `velocity_score`, `staleness`, `blocked_count` |
| `--robot-label-flow` | Cross-label dependency: `flow_matrix`, `dependencies`, `bottleneck_labels` |
| `--robot-label-attention [--attention-limit=N]` | Attention-ranked labels |

**History & Change Tracking:**
| Command | Returns |
|---------|---------|
| `--robot-history` | Bead-to-commit correlations |
| `--robot-diff --diff-since <ref>` | Changes since ref: new/closed/modified issues, cycles |

**Other:**
| Command | Returns |
|---------|---------|
| `--robot-burndown <sprint>` | Sprint burndown, scope changes, at-risk items |
| `--robot-forecast <id\|all>` | ETA predictions with dependency-aware scheduling |
| `--robot-alerts` | Stale issues, blocking cascades, priority mismatches |
| `--robot-suggest` | Hygiene: duplicates, missing deps, label suggestions |
| `--robot-graph [--graph-format=json\|dot\|mermaid]` | Dependency graph export |
| `--export-graph <file.html>` | Interactive HTML visualization |

### Scoping & Filtering

```bash
bv --robot-plan --label backend              # Scope to label's subgraph
bv --robot-insights --as-of HEAD~30          # Historical point-in-time
bv --recipe actionable --robot-plan          # Pre-filter: ready to work
bv --recipe high-impact --robot-triage       # Pre-filter: top PageRank
bv --robot-triage --robot-triage-by-track    # Group by parallel work streams
bv --robot-triage --robot-triage-by-label    # Group by domain
```

### Understanding Robot Output

**All robot JSON includes:**
- `data_hash` — Fingerprint of source beads.jsonl
- `status` — Per-metric state: `computed|approx|timeout|skipped` + elapsed ms
- `as_of` / `as_of_commit` — Present when using `--as-of`

**Two-phase analysis:**
- **Phase 1 (instant):** degree, topo sort, density
- **Phase 2 (async, 500ms timeout):** PageRank, betweenness, HITS, eigenvector, cycles

### jq Quick Reference

```bash
bv --robot-triage | jq '.quick_ref'                        # At-a-glance summary
bv --robot-triage | jq '.recommendations[0]'               # Top recommendation
bv --robot-plan | jq '.plan.summary.highest_impact'        # Best unblock target
bv --robot-insights | jq '.status'                         # Check metric readiness
bv --robot-insights | jq '.Cycles'                         # Circular deps (must fix!)
```

---

## UBS — Ultimate Bug Scanner

**Golden Rule:** `ubs <changed-files>` before every commit. Exit 0 = safe. Exit >0 = fix & re-run.

### Commands

```bash
ubs file.sh file2.ts                    # Specific files (< 1s) — USE THIS
ubs $(git diff --name-only --cached)    # Staged files — before commit
ubs --only=bash,js src/                 # Language filter (3-5x faster)
ubs --ci --fail-on-warning .            # CI mode — before PR
ubs .                                   # Whole project (ignores node_modules, .venv)
```

### Output Format

```
    Category (N errors)
    file.sh:42:5 - Issue description
    Suggested fix
Exit code: 1
```

Parse: `file:line:col` -> location | fix suggestion -> how to fix | Exit 0/1 -> pass/fail

### Fix Workflow

1. Read finding -> category + fix suggestion
2. Navigate `file:line:col` -> view context
3. Verify real issue (not false positive)
4. Fix root cause (not symptom)
5. Re-run `ubs <file>` -> exit 0
6. Commit

### Bug Severity

- **Critical (always fix):** Injection, unquoted variables, unsafe eval, command injection
- **Important (production):** Unhandled errors, resource leaks, missing error checks
- **Contextual (judgment):** TODO/FIXME, console logs, debugging output

---

## RCH — Remote Compilation Helper

RCH offloads `cargo build`, `cargo test`, `cargo clippy`, and other compilation commands to a fleet of 8 remote Contabo VPS workers instead of building locally. This prevents compilation storms from overwhelming csd when many agents run simultaneously.

**RCH is installed at `~/.local/bin/rch` and is hooked into Claude Code's PreToolUse automatically.** Most of the time you don't need to do anything if you are Claude Code — builds are intercepted and offloaded transparently.

To manually offload a build:
```bash
rch exec -- cargo build --release
rch exec -- cargo test
rch exec -- cargo clippy
```

Quick commands:
```bash
rch doctor                    # Health check
rch workers probe --all       # Test connectivity to all 8 workers
rch status                    # Overview of current state
rch queue                     # See active/waiting builds
```

If rch or its workers are unavailable, it fails open — builds run locally as normal.

**Note for Codex/GPT-5.2:** Codex does not have the automatic PreToolUse hook, but you can (and should) still manually offload compute-intensive compilation commands using `rch exec -- <command>`. This avoids local resource contention when multiple agents are building simultaneously.

---

## ast-grep vs ripgrep

**Use `ast-grep` when structure matters.** It parses code and matches AST nodes, ignoring comments/strings, and can **safely rewrite** code.

- Refactors/codemods: rename APIs, change import forms
- Policy checks: enforce patterns across a repo
- Editor/automation: LSP mode, `--json` output

**Use `ripgrep` when text is enough.** Fastest way to grep literals/regex.

- Recon: find strings, TODOs, log lines, config values
- Pre-filter: narrow candidate files before ast-grep

### Rule of Thumb

- Need correctness or **applying changes** -> `ast-grep`
- Need raw speed or **hunting text** -> `rg`
- Often combine: `rg` to shortlist files, then `ast-grep` to match/modify

### Examples

```bash
# Find structured code (ignores comments)
ast-grep run -l TypeScript -p 'function $NAME($$$ARGS) { $$$BODY }'

# Quick textual hunt
rg -n 'console.log' -t ts

# Combine speed + precision
rg -l -t ts 'useState' | xargs ast-grep run -l TypeScript -p 'useState($INIT)' --json
```

---

## Morph Warp Grep — AI-Powered Code Search

**Use `mcp__morph-mcp__warp_grep` for exploratory "how does X work?" questions.** An AI agent expands your query, greps the codebase, reads relevant files, and returns precise line ranges with full context.

**Use `ripgrep` for targeted searches.** When you know exactly what you're looking for.

**Use `ast-grep` for structural patterns.** When you need AST precision for matching/rewriting.

### When to Use What

| Scenario | Tool | Why |
|----------|------|-----|
| "How does the installer handle Ubuntu upgrades?" | `warp_grep` | Exploratory; don't know where to start |
| "Where is the checksum verification implemented?" | `warp_grep` | Need to understand architecture |
| "Find all uses of `logging.sh`" | `ripgrep` | Targeted literal search |
| "Find files with `echo -e`" | `ripgrep` | Simple pattern |
| "Replace `var` with `let` in TypeScript" | `ast-grep` | Structural refactor |

### warp_grep Usage

```
mcp__morph-mcp__warp_grep(
  repoPath: "/dp/agentic_coding_flywheel_setup",
  query: "How does the installer handle Ubuntu version upgrades?"
)
```

Returns structured results with file paths, line ranges, and extracted code snippets.

### Anti-Patterns

- **Don't** use `warp_grep` to find a specific function name -> use `ripgrep`
- **Don't** use `ripgrep` to understand "how does X work" -> wastes time with manual reads
- **Don't** use `ripgrep` for codemods -> risks collateral edits

<!-- bv-agent-instructions-v1 -->

---

## Beads Workflow Integration

This project uses [beads_rust](https://github.com/Dicklesworthstone/beads_rust) (`br`) for issue tracking. Issues are stored in `.beads/` and tracked in git.

**Important:** `br` is non-invasive—it NEVER executes git commands. After `br sync --flush-only`, you must manually run `git add .beads/ && git commit`.

### Essential Commands

```bash
# View issues (launches TUI - avoid in automated sessions)
bv

# CLI commands for agents (use these instead)
br ready              # Show issues ready to work (no blockers)
br list --status=open # All open issues
br show <id>          # Full issue details with dependencies
br create --title="..." --type=task --priority=2
br update <id> --status=in_progress
br close <id> --reason "Completed"
br close <id1> <id2>  # Close multiple issues at once
br sync --flush-only  # Export to JSONL (NO git operations)
```

### Workflow Pattern

1. **Start**: Run `br ready` to find actionable work
2. **Claim**: Use `br update <id> --status=in_progress`
3. **Work**: Implement the task
4. **Complete**: Use `br close <id>`
5. **Sync**: Run `br sync --flush-only` then manually commit

### Key Concepts

- **Dependencies**: Issues can block other issues. `br ready` shows only unblocked work.
- **Priority**: P0=critical, P1=high, P2=medium, P3=low, P4=backlog (use numbers, not words)
- **Types**: task, bug, feature, epic, chore
- **Blocking**: `br dep add <issue> <depends-on>` to add dependencies

### Session Protocol

**Before ending any session, run this checklist:**

```bash
git status              # Check what changed
git add <files>         # Stage code changes
br sync --flush-only    # Export beads to JSONL
git add .beads/         # Stage beads changes
git commit -m "..."     # Commit everything together
git push                # Push to remote
```

### Best Practices

- Check `br ready` at session start to find available work
- Update status as you work (in_progress -> closed)
- Create new issues with `br create` when you discover tasks
- Use descriptive titles and set appropriate priority/type
- Always `br sync --flush-only && git add .beads/` before ending session

<!-- end-bv-agent-instructions -->

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Sync beads** - `br sync --flush-only` to export to JSONL
5. **Hand off** - Provide context for next session

---

## Auxiliary Tools

### DCG — Destructive Command Guard

DCG is a Claude Code hook that **blocks dangerous git and filesystem commands** before execution. Sub-millisecond latency, mechanical enforcement.

**Golden Rule:** DCG works automatically. When a dangerous command is blocked, use safer alternatives or ask the user to run it manually.

```bash
dcg test "<cmd>" [--explain]          # Test if a command would be blocked
dcg packs [--enabled] [--verbose]     # List packs
dcg allow-once <code>                 # One-time bypass code
dcg doctor [--fix] [--format json]    # Health check + auto-fix
dcg install [--force]                 # Register Claude Code hook
```

### RU — Repo Updater

Multi-repo sync tool with AI-driven commit automation.

```bash
ru sync                        # Clone missing + pull updates for all repos
ru sync --parallel 4           # Parallel sync (4 workers)
ru status                      # Check repo status without changes
ru agent-sweep --dry-run       # Preview dirty repos to process
ru agent-sweep --parallel 4    # AI-driven commits in parallel
```

### giil — Cloud Image Downloader

Downloads cloud-hosted images to the terminal for visual debugging.

```bash
giil "https://share.icloud.com/..."       # Download iCloud photo
giil "https://www.dropbox.com/s/..."      # Download Dropbox image
giil "https://photos.google.com/..."      # Download Google Photos image
```

Supports: iCloud, Dropbox, Google Photos, Google Drive.

### csctf — Chat Share to File

Converts AI chat share links to Markdown/HTML archives.

```bash
csctf "https://chatgpt.com/share/..."      # ChatGPT conversation
csctf "https://claude.ai/share/..."        # Claude conversation
csctf "..." --md-only                       # Markdown only (no HTML)
```

### cass — Cross-Agent Search

Indexes prior agent conversations so solved problems can be reused.

```bash
cass search "authentication error" --robot --limit 5
cass view /path/to/session.jsonl -n 42 --json
cass capabilities --json
```

**Never run bare `cass` (TUI). Always use `--robot` or `--json`.**

### cm — Cass Memory System

Procedural memory for agents based on cross-session analysis.

```bash
cm onboard status                          # Check status
cm onboard sample --fill-gaps              # Get sessions to analyze
cm context "<task description>" --json     # Retrieve relevant context before work
```

---

Note for Codex/GPT-5.2:

You constantly bother me and stop working with concerned questions that look similar to this:

```
Unexpected changes (need guidance)

- Working tree still shows edits I did not make in Cargo.toml, Cargo.lock, src/main.rs, src/patterns.rs. Please advise whether to keep/commit/revert these before any further work. I did not touch them.

Next steps (pick one)

1. Decide how to handle the unrelated modified files above so we can resume cleanly.
```

NEVER EVER DO THAT AGAIN. The answer is literally ALWAYS the same: those are changes created by the potentially dozen of other agents working on the project at the same time. This is not only a common occurrence, it happens multiple times PER MINUTE. The way to deal with it is simple: you NEVER, under ANY CIRCUMSTANCE, stash, revert, overwrite, or otherwise disturb in ANY way the work of other agents. Just treat those changes identically to changes that you yourself made. Just fool yourself into thinking YOU made the changes and simply don't recall it for some reason.

---

## Note on Built-in TODO Functionality

Also, if I ask you to explicitly use your built-in TODO functionality, don't complain about this and say you need to use beads. You can use built-in TODOs if I tell you specifically to do so. Always comply with such orders.
