# Root AGENTS.md Plan (Flywheel VPS)

## Goal
Define the structure and content outline for a root `/AGENTS.md` on the Flywheel VPS.
The doc should be short, skimmable, and focused on the core toolchain and workflows
agents use every day.

## Audience
- AI coding agents operating on the VPS (Codex, Claude Code, Gemini)
- Humans onboarding agents to the VPS

## Tools to Document (Core)
1. ru (Repo Updater) - multi-repo sync and agent-sweep automation
2. br (Beads Rust) - local issue tracking
3. bv (Beads Viewer) - triage and graph insights
4. ntm (Named Tmux Manager) - agent orchestration and robot APIs
5. Agent CLIs:
   - cc (Claude Code)
   - cod (Codex)
   - agy (Antigravity)

## Tools to Mention (Support)
- ubs (Ultimate Bug Scanner) - required before commits
- cass / cm - memory + context lookup
- slb / dcg - destructive command guardrails
- caam - account switching for agent CLIs
- mcp-agent-mail - multi-agent coordination

## Document Structure (Proposed)

```
# AGENTS.md — Flywheel VPS

## Quick Start (5-10 essential commands)
## Safety Rules (no delete / destructive command policy)
## Tools Reference
### ru - Multi-Repo Management
### br - Issue Tracking
### bv - Beads Visualization
### ntm - Agent Orchestration
### Agent CLIs (cc/cod/agy)
## Workflows
### Flywheel Loop (triage -> claim -> work -> sync -> push)
### Multi-Agent Sessions (ntm + agent-mail)
### Daily/Weekly Maintenance
## Troubleshooting
## Resources
```

## Content Outline by Section

### Quick Start
- ru:
  - `ru sync`
  - `ru status`
- br:
  - `br ready --json`
  - `br update <id> --status in_progress`
  - `br close <id> --reason "..."`
  - `br sync --flush-only`
- bv:
  - `bv --robot-triage`
  - `bv --robot-next`
- ntm:
  - `ntm activity`
  - `ntm health <session>`
  - `ntm --robot-bulk-assign=<session> --from-bv`
- support:
  - `cm context "<task>" --json`
  - `ubs <changed-files>`

### Safety Rules
- No deletion without explicit command from user.
- No destructive git commands without explicit approval.
- Use `git status` / `git diff` first.

### Tools Reference (per tool)
Each tool section should include:
- What it is for (1-2 sentences).
- 3-6 core commands.
- Config locations (if any).
- Gotchas (1-3 bullets).

#### ru
- Purpose: multi-repo sync, commit-sweep automation.
- Commands: `ru init --example`, `ru sync`, `ru status`, `ru commit-sweep` (dry run by default).
- Config: `~/.config/ru/config`, `~/.config/ru/repos.d/*.txt`.

#### br
- Purpose: local issue tracker (SQLite + JSONL).
- Commands: `br ready --json`, `br create`, `br update`, `br close`, `br sync --flush-only`.
- Gotchas: always use `--json` for agents, never run bare `bv`.

#### bv
- Purpose: triage and graph-based prioritization.
- Commands: `bv --robot-triage`, `bv --robot-next`, `bv --robot-plan`.
- Gotchas: never run bare `bv` (TUI blocks).

#### ntm
- Purpose: tmux-based agent orchestration.
- Commands: `ntm list`, `ntm activity`, `ntm health`, `ntm --robot-bulk-assign`.
- Gotchas: ensure pane titles include agent short forms.

#### Agent CLIs (cc/cod/agy)
- Purpose: run the underlying model UIs.
- Commands: canonical launch wrappers (from VPS setup).
- Gotchas: respect AGENTS.md rules; ensure prompts include AGENTS.md and README.

### Workflows
- Flywheel loop:
  1) bv triage
  2) br claim
  3) work + tests
  4) br close + br sync
  5) git commit/push
- Multi-agent:
  - ntm session + agent-mail registration
  - avoid conflicts via file reservations
- Maintenance:
  - ru sync daily
  - ubs before commits
  - cm context for non-trivial tasks

### Troubleshooting
- bv hangs -> use `--robot-*` flags
- br sync conflicts -> resolve JSONL, then `br sync --import-only`
- ntm stale health -> check tmux activity + pane titles

### Resources
- Links to ru/ntm/br/bv docs (README or official repos)
- MCP agent mail web UI and health check endpoint

