# Antigravity CLI (agy) Rollout & Cutover — gmi Retirement

> Bead `bd-47kjh.11`. Companion to [`AGY_MIGRATION_REFERENCE.md`](./AGY_MIGRATION_REFERENCE.md).
> Status as of the 2026-06-18 cutover; ecosystem E2E + stack-binary refresh + repo
> sweep closed out 2026-06-20.

## What happened

Google retired the **Gemini CLI (`gmi`)** on **2026-06-18** — it no longer serves
Pro/Ultra/free tiers. Its successor is the **Antigravity CLI (`agy`)**, a standalone
self-updating native binary. Every flywheel surface that spawns, detects, indexes,
resumes, configures, installs, guards, or documents a Gemini-family agent has been
migrated to `agy`, **additively**: `gmi` stays usable as a legacy reader of
already-existing `~/.gemini/tmp/<hash>/chats/*.json` history, but `agy` is the
forward path for all new work.

## Guiding principle (applied everywhere)

- **Operational** ("start a session" / spawn / recommend / default swarm) → `agy`
  through the ACFS `agy-locked` launcher.
- **Historical** (resume/read/discover an existing Gemini session) → keep `gmi`/`gemini`.
- **Model mandate**: every `agy` invocation is pinned to **`Gemini 3.8 Flash (High)`** —
  the only allowed model. Single source of truth: `scripts/lib/agy_model_guard.sh`
  (referenced by the bash, Go, and Rust ports).
- **Disambiguation**: the `~/.gemini/` parent is shared. `~/.gemini/tmp` = gmi;
  `~/.gemini/antigravity-cli/` = agy (conversations at `conversations/<uuid>.db`,
  auth at `antigravity-cli/antigravity-oauth-token`, MCP at `config/mcp_config.json`).

## Component status

| Surface | Status | Notes |
|---|---|---|
| **ACFS install** | ✅ | `agents.antigravity` manifest module (verified_installer, checksum-gated); `uca` updates agy; `agy-locked` pins settings/model, installs the Antigravity dcg hook, and backs both `agy` and `gmi`. |
| **ACFS docs/onboarding** | ✅ | AGENTS.md, README, onboarding lessons, info/report/continue/cheatsheet, swarm-default mixes (`--agy=`). |
| **ACFS checksum monitor** | ✅ | `antigravity` in `KNOWN_INSTALLERS` + `checksums.yaml`; monitored like uv/rustup/bun. |
| **Shared e2e harness** | ✅ | `scripts/lib/agy_e2e_harness.sh` (structured logging, skip-if-unauth, model-guard, headless round-trip). |
| **franken_agent_detection (F1)** | ✅ | Antigravity connector (`src/connectors/antigravity.rs`) — shared detection/reader. |
| **cass (F2)** | ✅ | Indexes agy history; sync presets + disambiguation. |
| **ntm (F3)** | ✅ | `--agy=N` spawn flag + agy provider (ntm#185); agy session discovery/resume from `conversations/<uuid>.db`. Live-tmux spawn e2e (`4.3`) **verified** — `ntm spawn … --agy=1` launches an agy agent; `ntm deps` lists Antigravity CLI. |
| **useful_tmux_commands** | ✅ | Standalone swarm-fn library (sat/ant/sct/znt/bp/qps + TUI) — agy added as the forward 4th positional, gmi kept as targetable legacy (`utc-agy-swarm-fns-oa5`, bats+real-tmux e2e green, deployed to `~/.zshrc`). |
| **frankenterm** | ✅ | `AgentProvider::Antigravity` + session_resume (`~/.gemini/antigravity-cli/conversations` discovery, model-pin) + status-bar `agy:` segment + proptests — shipped in v0.8.0 (`ft-agy-provider-q8o4y`; doc/tape cleanup tracked there). |
| **repo sweep (`.10`)** | ✅ | Fleet-wide triage done: personal site + planning-doc spawn examples migrated; `ru`/iOS-app already agy; remaining `gmi` is legacy-read, model/vendor names, archived data, or false-positives (e.g. `gmi`=Gross-Margin-Index). |
| **skills (F7)** | ✅ | je_private_skills_repo migrated + deployed to `~/.claude`,`~/.codex`,`~/.gemini` skills on all 7 machines; clawd + clawdbot skill mirrors migrated. |
| **dcg (F5)** | ✅ `4e91659` | `dcg install --agy` writes a PreToolUse hook to `~/.gemini/config/hooks.json`; runtime detection of agy's `toolCall` envelope; emits the `{"decision":"block"}`+exit-0 form agy honors (envelope captured empirically). |
| **am (F6)** | ✅ `2972f9d5` | agy program identity (`KNOWN_PROGRAM_NAMES` + franken slug); MCP registration to `~/.gemini/config/mcp_config.json` (strace-confirmed agy reads it), token-safe (#148). |
| **casr (F9)** | ✅ `98ed5b1` | Antigravity provider — enumerate `conversations/<uuid>.db`, resume `agy --conversation <uuid> --model …`; read/resume-only (write deferred by design). |
| **caam (F10)** | ✅ | agy account detect/switch/backup/restore (token-file authoritative; no OS keyring on Linux). |
| **agent_flywheel_app** | ✅ | iOS orchestrator recognizes agy; spawns via `--agy=` (not folded into `--gmi`). |
| **brenner_bot** | ✅ | Default cockpit swarm spawns agy. |

## Fleet state (machine cutover)

`agy` is **installed and authenticated on all 7 dev machines** (this VPS + css, csd,
ts1, ts2, mac-mini-max, mac-mini-old). Auth was propagated by copying
`~/.gemini/antigravity-cli/antigravity-oauth-token` (the token alone authenticates;
it is not device-bound). Install one-liner (idempotent, SHA512-verified):

```bash
curl -fsSL https://antigravity.google/cli/install.sh | bash   # -> ~/.local/bin/agy
```

## Residual gmi (intentional, legacy-only)

These keep `gmi`/`gemini` **on purpose** — they read or resume *existing* Gemini
history and must not break:

- casr `src/providers/gemini.rs`, ntm/cass gemini discovery, dcg `Agent::GeminiCli`,
  caam legacy gemini account handling, franken gemini connector.
- ACFS `agents.gemini` manifest module is optional legacy; `gmi` now launches the
  same `agy-locked` forward path as `agy`.
- Doc tables that list `--gmi=N` as a legacy flag alongside `--agy=N`.

## Keep / remove decision (final) + user comms

- **Decision: keep the old Gemini history readable through history/indexing tools,
  but make the `gmi` command launch `agy-locked`.** Old
  `~/.gemini/tmp/<hash>/chats/*.json` data must stay readable/resumable by tools
  that understand it, but the shell command no longer starts the retired CLI.
- **Sequencing met the deadline**: the user-facing path — ACFS install, `ntm spawn`,
  cass index, casr resume, the skills, and the swarm helpers — all drive `agy`
  before the 2026-06-18 retirement; agy was installed+authed on all 7 machines first.
- **User comms**: aliases/docs present `agy` as the default third agent and call out
  `gmi` as "Gemini CLI — retired 2026-06-18, kept for old-session reads." No action
  is required of users beyond a one-time `agy` Google sign-in when they first use it.

## Closed out (was deferred)

- **Live-tmux spawn e2e** (ntm `4.3`): ✅ verified — `ntm spawn … --agy=1` launches an
  agy agent on the rebuilt ntm; the swarm-helper e2e (`utc-agy-swarm-fns-oa5.5`)
  spawns + targets an `__agy_` pane.
- **frankenterm**: ✅ the detached-HEAD/broken-submodule blocker resolved; the agy
  `AgentProvider` + session-resume + status-bar shipped in v0.8.0 (only doc/tape
  cleanup remains in that repo's release cycle).
- **Stack-binary refresh**: the installed `ntm`/`caam`/`casr` binaries were stale
  (predated their agy commits); rebuilt + reinstalled from agy-complete source so the
  live tools expose agy (`.pre-agy.bak` backups kept).

## Verification

- **Full ecosystem E2E** (`scripts/e2e/test_agy_ecosystem.sh`): ✅ 10/10 green on one
  real agy conversation pinned to `Gemini 3.8 Flash (High)` — agy round-trip + model
  guard, conversation persisted, cass index, casr resume, caam provider, dcg guard,
  am detection, ntm agy type, a deployed skill drives agy.
- `agy --model "Gemini 3.8 Flash (High)" --print "…"` returns a real completion on the
  pinned model (verified on the fleet).
- `bash scripts/lib/agy_model_guard.sh --self-test` and
  `bash scripts/lib/agy_e2e_harness.sh --self-test` pass.
- `bash tests/unit/test_agy_install.sh` — agy install contract (13 checks) passes;
  `bash scripts/e2e/test_agy_install.sh` — live round-trip passes (skips if unauth).
