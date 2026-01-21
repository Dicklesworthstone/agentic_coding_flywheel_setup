# AGENTS.md — Agentic Coding Flywheel Setup (ACFS)

## RULE 0 - THE FUNDAMENTAL OVERRIDE PEROGATIVE

If I tell you to do something, even if it goes against what follows below, YOU MUST LISTEN TO ME. I AM IN CHARGE, NOT YOU.

---

## RULE 1 – ABSOLUTE (DO NOT EVER VIOLATE THIS)

You may NOT delete any file or directory unless I explicitly give the exact command **in this session**.

- This includes files you just created (tests, tmp files, scripts, etc.).
- You do not get to decide that something is "safe" to remove.
- If you think something should be removed, stop and ask. You must receive clear written approval **before** any deletion command is even proposed.

Treat "never delete files without permission" as a hard invariant.

---

## IRREVERSIBLE GIT & FILESYSTEM ACTIONS

Absolutely forbidden unless I give the **exact command and explicit approval** in the same message:

- `git reset --hard`
- `git clean -fd`
- `rm -rf`
- Any command that can delete or overwrite code/data

Rules:

1. If you are not 100% sure what a command will delete, do not propose or run it. Ask first.
2. Prefer safe tools: `git status`, `git diff`, `git stash`, copying to backups, etc.
3. After approval, restate the command verbatim, list what it will affect, and wait for confirmation.
4. When a destructive command is run, record in your response:
   - The exact user text authorizing it
   - The command run
   - When you ran it

If that audit trail is missing, then you must act as if the operation never happened.

---

## Node / JS Toolchain

- Use **bun** for everything JS/TS.
- ❌ Never use `npm`, `yarn`, or `pnpm`.
- Lockfiles: only `bun.lock`. Do not introduce any other lockfile.
- Target **latest Node.js**. No need to support old Node versions.
- **Note:** `bun install -g <pkg>` is valid syntax (alias for `bun add -g`). Do not "fix" it.

---

## Project Architecture

ACFS is a **multi-component project** consisting of:

### A) Website Wizard (`apps/web/`)
- **Framework:** Next.js 16 App Router
- **Runtime:** Bun
- **Hosting:** Vercel + Cloudflare for cost optimization
- **Purpose:** Step-by-step wizard guiding beginners from "I have a laptop" to "fully configured VPS"
- **No backend required:** All state via URL params + localStorage

### B) Installer (`install.sh` + `scripts/`)
- **Language:** Bash (POSIX-compatible where possible)
- **Target:** Ubuntu 25.10 (auto-upgrades from 22.04+ via sequential do-release-upgrade)
- **Auto-Upgrade:** Older Ubuntu versions are automatically upgraded to 25.10 before ACFS install
  - Upgrade path: 22.04 → 24.04 → 25.04 → 25.10 (EOL interim releases like 24.10 may be skipped)
  - Takes 30-60 minutes per version hop; multiple reboots handled via systemd resume service
  - Skip with `--skip-ubuntu-upgrade` flag
- **One-liner:** `curl -fsSL ... | bash -s -- --yes --mode vibe`
- **Idempotent:** Safe to re-run
- **Checkpointed:** Phases resume on failure

### C) Onboarding TUI (`packages/onboard/`)
- **Command:** `onboard`
- **Purpose:** Interactive tutorial teaching Linux basics + agent workflow
- **Tech:** Shell script or simple Rust/Go binary (TBD)

### D) Module Manifest (`acfs.manifest.yaml`)
- **Purpose:** Single source of truth for all tools installed
- **Contains:** Tool definitions, install commands, verify commands
- **Generates:** Website content, installer modules, doctor checks

### E) ACFS Configs (`acfs/`)
- **Shell config:** `acfs/zsh/acfs.zshrc`
- **Tmux config:** `acfs/tmux/tmux.conf`
- **Onboard lessons:** `acfs/onboard/lessons/`
- **Installed to:** `~/.acfs/` on target VPS

---

## Repo Layout

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
│   └── providers/                # VPS provider guides
│
└── tests/
    └── vm/
        └── test_install_ubuntu.sh
```

---

## Generated Files — NEVER Edit Manually

The following files are **auto-generated** from the manifest. Edits to these files will be **overwritten** on the next regeneration.

### Generated Locations

```
scripts/generated/          # ALL files in this directory
├── install_*.sh           # Category installer scripts
├── doctor_checks.sh       # Doctor verification checks
└── manifest_index.sh      # Bash arrays with module metadata
```

### How to Modify Generated Code

1. **Identify the generator source**: `packages/manifest/src/generate.ts`
2. **Modify the generator**, not the output files
3. **Regenerate**: `cd packages/manifest && bun run generate`
4. **Verify**: `shellcheck scripts/generated/*.sh`

### Key Generator Components

| File | Purpose |
|------|---------|
| `packages/manifest/src/generate.ts` | Main generator logic |
| `packages/manifest/src/schema.ts` | Zod schema for manifest validation |
| `packages/manifest/src/types.ts` | TypeScript interfaces |
| `acfs.manifest.yaml` | Source manifest (this IS hand-edited) |

### Why This Matters

If you manually edit a generated file:
- Your changes **will be lost** on next `bun run generate`
- Other developers won't know about your fix
- CI/CD may regenerate and overwrite your work

Always fix the generator, then regenerate.

---

## Code Editing Discipline

- Do **not** run scripts that bulk-modify code (codemods, invented one-off scripts, giant `sed`/regex refactors).
- Large mechanical changes: break into smaller, explicit edits and review diffs.
- Subtle/complex changes: edit by hand, file-by-file, with careful reasoning.

---

## Backwards Compatibility & File Sprawl

We optimize for a clean architecture now, not backwards compatibility.

- No "compat shims" or "v2" file clones.
- When changing behavior, migrate callers and remove old code.
- New files are only for genuinely new domains that don't fit existing modules.
- The bar for adding files is very high.

---

## Console Output (for installer scripts)

The installer uses colored output for progress visibility:

```bash
echo -e "\033[34m[1/8] Step description\033[0m"     # Blue progress steps
echo -e "\033[90m    Details...\033[0m"             # Gray indented details
echo -e "\033[33m⚠️  Warning message\033[0m"        # Yellow warnings
echo -e "\033[31m✖ Error message\033[0m"            # Red errors
echo -e "\033[32m✔ Success message\033[0m"          # Green success
```

Rules:
- Progress/status goes to `stderr` (so stdout remains clean for piping)
- `--quiet` flag suppresses progress but not errors
- All output functions should use the logging library (`scripts/lib/logging.sh`)

---

## Third-Party Tools Installed by ACFS

These are installed on target VPS (not development machine).

> **OS Requirement:** Ubuntu 25.10 (installer auto-upgrades from 22.04+; see Installer section above)

### Shell & Terminal UX
- **zsh** + **oh-my-zsh** + **powerlevel10k**
- **lsd** (or eza fallback) — Modern ls
- **atuin** — Shell history with Ctrl-R
- **fzf** — Fuzzy finder
- **zoxide** — Better cd
- **direnv** — Directory-specific env vars

### Languages & Package Managers
- **bun** — JS/TS runtime + package manager
- **uv** — Fast Python tooling
- **rust/cargo** — Rust toolchain
- **go** — Go toolchain

### Dev Tools
- **tmux** — Terminal multiplexer
- **ripgrep** (`rg`) — Fast search
- **ast-grep** (`sg`) — Structural search/replace
- **lazygit** — Git TUI
- **bat** — Better cat

### Coding Agents
- **Claude Code** — Anthropic's coding agent
- **Codex CLI** — OpenAI's coding agent
- **Gemini CLI** — Google's coding agent

### Cloud & Database
- **PostgreSQL 18** — Database
- **HashiCorp Vault** — Secrets management
- **Wrangler** — Cloudflare CLI
- **Supabase CLI** — Supabase management
- **Vercel CLI** — Vercel deployment

### Dicklesworthstone Stack (10 tools + utilities)
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

---

## MCP Agent Mail — Multi-Agent Coordination

Agent Mail is available as an MCP server for coordinating work across agents.

What Agent Mail gives:
- Identities, inbox/outbox, searchable threads.
- Advisory file reservations (leases) to avoid agents clobbering each other.
- Persistent artifacts in git (human-auditable).

Core patterns:

1. **Same repo**
   - Register identity:
     - `ensure_project` then `register_agent` with the repo's absolute path as `project_key`.
   - Reserve files before editing:
     - `file_reservation_paths(project_key, agent_name, ["src/**"], ttl_seconds=3600, exclusive=true)`.
   - Communicate:
     - `send_message(..., thread_id="FEAT-123")`.
     - `fetch_inbox`, then `acknowledge_message`.
   - Fast reads:
     - `resource://inbox/{Agent}?project=<abs-path>&limit=20`.
     - `resource://thread/{id}?project=<abs-path>&include_bodies=true`.

2. **Macros vs granular:**
   - Prefer macros when speed is more important than fine-grained control:
     - `macro_start_session`, `macro_prepare_thread`, `macro_file_reservation_cycle`, `macro_contact_handshake`.
   - Use granular tools when you need explicit behavior.

Common pitfalls:
- "from_agent not registered" → call `register_agent` with correct `project_key`.
- `FILE_RESERVATION_CONFLICT` → adjust patterns, wait for expiry, or use non-exclusive reservation.

---

## Website Development (apps/web)

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

## Installer Testing

```bash
# Local lint
shellcheck install.sh scripts/lib/*.sh

# Full installer integration test (Docker, same as CI)
./tests/vm/test_install_ubuntu.sh
```

---

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   br sync --flush-only
   git add .beads/
   git commit -m "Update beads"
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds


---

## Issue Tracking with br (Beads)

All issue tracking goes through **Beads**. No other TODO systems.

**Note:** `br` is a convenience alias (installed by `acfs/zsh/acfs.zshrc`) for the real Beads CLI: `bd`.
If `br` is unavailable (CI / non-interactive shells), use `bd` directly.

Key invariants:

- `.beads/` is authoritative state and **must always be committed** with code changes.
- Do not edit `.beads/*.jsonl` directly; only via `br` / `bd`.

### Basics

Check ready work:

```bash
br ready --json
```

Create issues:

```bash
br create "Issue title" -t bug|feature|task -p 0-4 --json
br create "Issue title" -p 1 --deps discovered-from:br-123 --json
```

Update:

```bash
br update br-42 --status in_progress --json
br update br-42 --priority 1 --json
```

Complete:

```bash
br close br-42 --reason "Completed" --json
```

Types:

- `bug`, `feature`, `task`, `epic`, `chore`

Priorities:

- `0` critical (security, data loss, broken builds)
- `1` high
- `2` medium (default)
- `3` low
- `4` backlog

Agent workflow:

1. `br ready` to find unblocked work.
2. Claim: `br update <id> --status in_progress`.
3. Implement + test.
4. If you discover new work, create a new bead with `discovered-from:<parent-id>`.
5. Close when done.
6. Commit `.beads/` in the same commit as code changes.

Sync:

- Run `br sync --flush-only` (or `bd sync --flush-only`) to export to `.beads/issues.jsonl` without git operations.
- Then run `git add .beads/ && git commit -m "Update beads"` to commit changes.

Never:

- Use markdown TODO lists.
- Use other trackers.
- Duplicate tracking.

---

### Using bv as an AI sidecar

bv is a graph-aware triage engine for Beads projects (.beads/beads.jsonl). Instead of parsing JSONL or hallucinating graph traversal, use robot flags for deterministic, dependency-aware outputs with precomputed metrics (PageRank, betweenness, critical path, cycles, HITS, eigenvector, k-core).

**Scope boundary:** bv handles *what to work on* (triage, priority, planning). For agent-to-agent coordination (messaging, work claiming, file reservations), use MCP Agent Mail, which should be available to you as an an MCP server (if it's not, then flag to the user; they might need to start Agent Mail using the `am` alias or by running `cd "<directory_where_they_installed_agent_mail>/mcp_agent_mail" && bash scripts/run_server_with_token.sh)' if the alias isn't available or isn't working.

**⚠️ CRITICAL: Use ONLY `--robot-*` flags. Bare `bv` launches an interactive TUI that blocks your session.**

#### The Workflow: Start With Triage

**`bv --robot-triage` is your single entry point.** It returns everything you need in one call:
- `quick_ref`: at-a-glance counts + top 3 picks
- `recommendations`: ranked actionable items with scores, reasons, unblock info
- `quick_wins`: low-effort high-impact items
- `blockers_to_clear`: items that unblock the most downstream work
- `project_health`: status/type/priority distributions, graph metrics
- `commands`: copy-paste shell commands for next steps

bv --robot-triage        # THE MEGA-COMMAND: start here
bv --robot-next          # Minimal: just the single top pick + claim command

#### Other bv Commands

**Planning:**
| Command | Returns |
|---------|---------|
| `--robot-plan` | Parallel execution tracks with `unblocks` lists |
| `--robot-priority` | Priority misalignment detection with confidence |

**Graph Analysis:**
| Command | Returns |
|---------|---------|
| `--robot-insights` | Full metrics: PageRank, betweenness, HITS (hubs/authorities), eigenvector, critical path, cycles, k-core, articulation points, slack |
| `--robot-label-health` | Per-label health: `health_level` (healthy\|warning\|critical), `velocity_score`, `staleness`, `blocked_count` |
| `--robot-label-flow` | Cross-label dependency: `flow_matrix`, `dependencies`, `bottleneck_labels` |
| `--robot-label-attention [--attention-limit=N]` | Attention-ranked labels by: (pagerank × staleness × block_impact) / velocity |

**History & Change Tracking:**
| Command | Returns |
|---------|---------|
| `--robot-history` | Bead-to-commit correlations: `stats`, `histories` (per-bead events/commits/milestones), `commit_index` |
| `--robot-diff --diff-since <ref>` | Changes since ref: new/closed/modified issues, cycles introduced/resolved |

**Other Commands:**
| Command | Returns |
|---------|---------|
| `--robot-burndown <sprint>` | Sprint burndown, scope changes, at-risk items |
| `--robot-forecast <id\|all>` | ETA predictions with dependency-aware scheduling |
| `--robot-alerts` | Stale issues, blocking cascades, priority mismatches |
| `--robot-suggest` | Hygiene: duplicates, missing deps, label suggestions, cycle breaks |
| `--robot-graph [--graph-format=json\|dot\|mermaid]` | Dependency graph export |
| `--export-graph <file.html>` | Self-contained interactive HTML visualization |

#### Scoping & Filtering

bv --robot-plan --label backend              # Scope to label's subgraph
bv --robot-insights --as-of HEAD~30          # Historical point-in-time
bv --recipe actionable --robot-plan          # Pre-filter: ready to work (no blockers)
bv --recipe high-impact --robot-triage       # Pre-filter: top PageRank scores
bv --robot-triage --robot-triage-by-track    # Group by parallel work streams
bv --robot-triage --robot-triage-by-label    # Group by domain

#### Understanding Robot Output

**All robot JSON includes:**
- `data_hash` — Fingerprint of source beads.jsonl (verify consistency across calls)
- `status` — Per-metric state: `computed|approx|timeout|skipped` + elapsed ms
- `as_of` / `as_of_commit` — Present when using `--as-of`; contains ref and resolved SHA

**Two-phase analysis:**
- **Phase 1 (instant):** degree, topo sort, density — always available immediately
- **Phase 2 (async, 500ms timeout):** PageRank, betweenness, HITS, eigenvector, cycles — check `status` flags

**For large graphs (>500 nodes):** Some metrics may be approximated or skipped. Always check `status`.

#### jq Quick Reference

bv --robot-triage | jq '.quick_ref'                        # At-a-glance summary
bv --robot-triage | jq '.recommendations[0]'               # Top recommendation
bv --robot-plan | jq '.plan.summary.highest_impact'        # Best unblock target
bv --robot-insights | jq '.status'                         # Check metric readiness
bv --robot-insights | jq '.Cycles'                         # Circular deps (must fix!)
bv --robot-label-health | jq '.results.labels[] | select(.health_level == "critical")'

**Performance:** Phase 1 instant, Phase 2 async (500ms timeout). Prefer `--robot-plan` over `--robot-insights` when speed matters. Results cached by data hash.

Use bv instead of parsing beads.jsonl—it computes PageRank, critical paths, cycles, and parallel tracks deterministically.

---

### Morph Warp Grep — AI-Powered Code Search

Use `mcp__morph-mcp__warp_grep` for “how does X work?” discovery across the codebase.

When to use:

- You don’t know where something lives.
- You want data flow across multiple files (API → service → schema → types).
- You want all touchpoints of a cross-cutting concern (e.g., moderation, billing).

Example:

```
mcp__morph-mcp__warp_grep(
  repoPath: "/data/projects/communitai",
  query: "How is the L3 Guardian appeals system implemented?"
)
```

Warp Grep:

- Expands a natural-language query to multiple search patterns.
- Runs targeted greps, reads code, follows imports, then returns concise snippets with line numbers.
- Reduces token usage by returning only relevant slices, not entire files.

When **not** to use Warp Grep:

- You already know the function/identifier name; use `rg`.
- You know the exact file; just open it.
- You only need a yes/no existence check.

Comparison:

| Scenario | Tool |
| ---------------------------------- | ---------- |
| “How is auth session validated?” | warp_grep |
| “Where is `handleSubmit` defined?” | `rg` |
| “Replace `var` with `let`” | `ast-grep` |

---

### cass — Cross-Agent Search

`cass` indexes prior agent conversations (Claude Code, Codex, Cursor, Gemini, ChatGPT, etc.) so we can reuse solved problems.

Rules:

- Never run bare `cass` (TUI). Always use `--robot` or `--json`.

Examples:

```bash
cass health
cass search "authentication error" --robot --limit 5
cass view /path/to/session.jsonl -n 42 --json
cass expand /path/to/session.jsonl -n 42 -C 3 --json
cass capabilities --json
cass robot-docs guide
```

Tips:

- Use `--fields minimal` for lean output.
- Filter by agent with `--agent`.
- Use `--days N` to limit to recent history.

stdout is data-only, stderr is diagnostics; exit code 0 means success.

Treat cass as a way to avoid re-solving problems other agents already handled.

---

## Memory System: cass-memory

The Cass Memory System (cm) is a tool for giving agents an effective memory based on the ability to quickly search across previous coding agent sessions across an array of different coding agent tools (e.g., Claude Code, Codex, Gemini-CLI, Cursor, etc) and projects (and even across multiple machines, optionally) and then reflect on what they find and learn in new sessions to draw out useful lessons and takeaways; these lessons are then stored and can be queried and retrieved later, much like how human memory works.

The `cm onboard` command guides you through analyzing historical sessions and extracting valuable rules.

### Quick Start

```bash
# 1. Check status and see recommendations
cm onboard status

# 2. Get sessions to analyze (filtered by gaps in your playbook)
cm onboard sample --fill-gaps

# 3. Read a session with rich context
cm onboard read /path/to/session.jsonl --template

# 4. Add extracted rules (one at a time or batch)
cm playbook add "Your rule content" --category "debugging"
# Or batch add:
cm playbook add --file rules.json

# 5. Mark session as processed
cm onboard mark-done /path/to/session.jsonl
```

Before starting complex tasks, retrieve relevant context:

```bash
cm context "<task description>" --json
```

This returns:
- **relevantBullets**: Rules that may help with your task
- **antiPatterns**: Pitfalls to avoid
- **historySnippets**: Past sessions that solved similar problems
- **suggestedCassQueries**: Searches for deeper investigation

### Protocol

1. **START**: Run `cm context "<task>" --json` before non-trivial work
2. **WORK**: Reference rule IDs when following them (e.g., "Following b-8f3a2c...")
3. **FEEDBACK**: Leave inline comments when rules help/hurt:
   - `// [cass: helpful b-xyz] - reason`
   - `// [cass: harmful b-xyz] - reason`
4. **END**: Just finish your work. Learning happens automatically.

### Key Flags

| Flag | Purpose |
|------|---------|
| `--json` | Machine-readable JSON output (required!) |
| `--limit N` | Cap number of rules returned |
| `--no-history` | Skip historical snippets for faster response |

stdout = data only, stderr = diagnostics. Exit 0 = success.

---

## UBS Quick Reference for AI Agents

UBS stands for "Ultimate Bug Scanner": **The AI Coding Agent's Secret Weapon: Flagging Likely Bugs for Fixing Early On**

**Golden Rule:** `ubs <changed-files>` before every commit. Exit 0 = safe. Exit >0 = fix & re-run.

**Commands:**
```bash
ubs file.ts file2.py                    # Specific files (< 1s) — USE THIS
ubs $(git diff --name-only --cached)    # Staged files — before commit
ubs --only=js,python src/               # Language filter (3-5x faster)
ubs --ci --fail-on-warning .            # CI mode — before PR
ubs --help                              # Full command reference
ubs sessions --entries 1                # Tail the latest install session log
ubs .                                   # Whole project (ignores things like .venv and node_modules automatically)
```

**Output Format:**
```
⚠️  Category (N errors)
    file.ts:42:5 – Issue description
    💡 Suggested fix
Exit code: 1
```
Parse: `file:line:col` → location | 💡 → how to fix | Exit 0/1 → pass/fail

**Fix Workflow:**
1. Read finding → category + fix suggestion
2. Navigate `file:line:col` → view context
3. Verify real issue (not false positive)
4. Fix root cause (not symptom)
5. Re-run `ubs <file>` → exit 0
6. Commit

**Speed Critical:** Scope to changed files. `ubs src/file.ts` (< 1s) vs `ubs .` (30s). Never full scan for small edits.

**Bug Severity:**
- **Critical** (always fix): Null safety, XSS/injection, async/await, memory leaks
- **Important** (production): Type narrowing, division-by-zero, resource leaks
- **Contextual** (judgment): TODO/FIXME, console logs

**Anti-Patterns:**
- ❌ Ignore findings → ✅ Investigate each
- ❌ Full scan per edit → ✅ Scope to file
- ❌ Fix symptom (`if (x) { x.y }`) → ✅ Root cause (`x?.y`)

---

## DCG Quick Reference for AI Agents

DCG (Destructive Command Guard) is a Claude Code hook that **blocks dangerous git and filesystem commands** before execution. Sub-millisecond latency, mechanical enforcement.

**Golden Rule:** DCG works automatically—you don't need to call it. When a dangerous command is blocked, use safer alternatives or ask the user to run it manually.

**Commands:**
```bash
dcg test "<cmd>" [--explain]          # Test if a command would be blocked
dcg packs [--enabled] [--verbose]     # List packs
dcg pack <pack-id> [--patterns]       # Pack details + match patterns
dcg allow-once <code>                 # One-time bypass code
dcg allow <rule-id> --reason "..."    # Add allowlist entry (project/user)
dcg doctor [--fix] [--format json]    # Health check + auto-fix
dcg install [--force]                 # Register Claude Code hook
dcg uninstall [--purge]               # Remove hook (and optionally binary/config)
```

**Auto-Blocked Commands:**
```bash
git reset --hard               # Destroys uncommitted changes
git checkout -- <files>        # Discards file changes permanently
git restore <files>            # Same as checkout -- (not --staged)
git push --force / -f          # Overwrites remote history
git clean -f                   # Deletes untracked files
git branch -D                  # Force-deletes without merge check
git stash drop / clear         # Permanently deletes stashes
rm -rf <non-temp>              # Recursive deletion
```

**Always Allowed:**
```bash
git checkout -b <branch>       # Creates branch, doesn't touch files
git restore --staged           # Only unstages, safe
git clean -n                   # Dry-run, preview only
rm -rf /tmp/...                # Temp directories are ephemeral
git push --force-with-lease    # Safe force push variant
```

**When Blocked:**
- You'll see a clear reason explaining why
- Ask the user to run the command manually if truly needed
- Consider safer alternatives (git stash, --force-with-lease)

**Configuration:**
- Config file: `~/.config/dcg/config.toml`
- View available packs: `dcg packs` (shows all), `dcg packs --enabled` (shows active)
- Pack examples: `git`, `filesystem`, `database.postgresql`, `containers.docker`, `kubernetes`
```toml
# ~/.config/dcg/config.toml
[packs]
enabled = ["git", "filesystem", "database.postgresql", "containers.docker"]
```
- Allowlist management: `dcg allow <rule-id> --reason "..." --project <path>` (or `--user`)

**Common Scenarios:**
- **Blocked command** → Read the reason, prefer the safer alternative, or use `dcg allow-once <code>`.
- **Hook missing after updates** → `dcg install --force`.
- **Need to disable** → `dcg uninstall` (or `dcg uninstall --purge` for full removal).

**Troubleshooting:**

| Issue | Solution |
|-------|----------|
| DCG blocks legitimate command | Ask user to run manually, or use allow-once code if provided |
| Hook not registered | Run `dcg install` |
| DCG not blocking anything | Run `dcg doctor` to verify hook is active |
| False positive | Check if command matches safe patterns; report to GitHub if bug |
| Config not being read | Verify `~/.config/dcg/config.toml` format is valid TOML |

**Agent Integration Tips:**
- DCG is automatic—no need to call `dcg test` before commands
- When blocked, explain to user why the command is dangerous
- Suggest safer alternatives (e.g., `--force-with-lease` instead of `--force`)
- Never try to bypass DCG—ask user to run dangerous commands manually
- DCG has sub-millisecond latency, designed to not slow down your workflow

---

## RU Quick Reference for AI Agents

RU (Repo Updater) is a multi-repo sync tool with **AI-driven commit automation**.

**Common Commands:**
```bash
ru sync                        # Clone missing + pull updates for all repos
ru sync --parallel 4           # Parallel sync (4 workers)
ru status                      # Check repo status without changes
ru status --fetch              # Fetch + show ahead/behind
ru list --paths                # List all repo paths
```

**Agent Sweep (commit automation):**
```bash
ru agent-sweep --dry-run       # Preview dirty repos to process
ru agent-sweep --parallel 4    # AI-driven commits in parallel
ru agent-sweep --with-release  # Include version tag + release
```

**Exit Codes:**
- `0` = Success
- `1` = Partial failure (some repos failed)
- `2` = Conflicts exist (manual resolution needed)
- `5` = Interrupted (use `--resume`)

**Best Practices:**
- Use `ru status` before `ru sync` to preview changes
- Use `ru agent-sweep --dry-run` before full automation
- Scope with `--repos=pattern` for targeted operations

---

## giil Quick Reference for AI Agents

giil (Get Image from Internet Link) downloads **cloud-hosted images** to the terminal for visual debugging.

**Usage:**
```bash
giil "https://share.icloud.com/..."       # Download iCloud photo
giil "https://www.dropbox.com/s/..."      # Download Dropbox image
giil "https://photos.google.com/..."      # Download Google Photos image
giil "..." --output ~/screenshots         # Custom output directory
giil "..." --json                         # JSON metadata output
giil "..." --all                          # Download all photos from album
```

**Supported Platforms:**
- iCloud (share.icloud.com)
- Dropbox (dropbox.com/s/, dl.dropbox.com)
- Google Photos (photos.google.com)
- Google Drive (drive.google.com)

**Exit Codes:**
- `0` = Success
- `10` = Network error
- `11` = Auth required (not publicly shared)
- `12` = Not found (expired link)
- `13` = Unsupported type (video, doc)

**Visual Debugging Workflow:**
1. User screenshots bug on phone
2. Shares iCloud/Dropbox link with agent
3. `giil "<url>"` downloads to working directory
4. Agent analyzes the image

---

## csctf Quick Reference for AI Agents

csctf (Chat Shared Conversation to File) converts **AI chat share links** to Markdown/HTML.

**Usage:**
```bash
csctf "https://chatgpt.com/share/..."      # ChatGPT conversation
csctf "https://gemini.google.com/share/..." # Gemini conversation
csctf "https://claude.ai/share/..."         # Claude conversation
csctf "..." --md-only                       # Markdown only (no HTML)
csctf "..." --json                          # JSON metadata output
csctf "..." --publish-to-gh-pages --yes     # Publish to GitHub Pages
```

**Output:**
- `<slug>.md` — Clean Markdown with code blocks
- `<slug>.html` — Static HTML with syntax highlighting

**Use Cases:**
- Archive important AI conversations for reference
- Build searchable knowledge base
- Share solutions with team members
- Document debugging sessions for future learning

---

## Note for Codex/GPT-5.2

You constantly bother me and stop working with concerned questions that look similar to this:

```
Unexpected changes (need guidance)

- Working tree still shows edits I did not make in Cargo.toml, Cargo.lock, src/main.rs, src/patterns.rs. Please advise whether to keep/commit/revert these before any further work. I did not touch them.

Next steps (pick one)

1. Decide how to handle the unrelated modified files above so we can resume cleanly.
```

NEVER EVER DO THAT AGAIN. The answer is literally ALWAYS the same: those are changes created by the potentially dozen of other agents working on the project at the same time. This is not only a common occurence, it happens multiple times PER MINUTE. The way to deal with it is simple: you NEVER, under ANY CIRCUMSTANCE, stash, revert, overwrite, or otherwise disturb in ANY way the work of other agents. Just treat those changes identically to changes that you yourself made. Just fool yourself into thinking YOU made the changes and simply don't recall it for some reason.

---

## Note on Built-in TODO Functionality

Also, if I ask you to explicitly use your built-in TODO functionality, don't complain about this and say you need to use beads. You can use built-in TODOs if I tell you specifically to do so. Always comply with such orders.
