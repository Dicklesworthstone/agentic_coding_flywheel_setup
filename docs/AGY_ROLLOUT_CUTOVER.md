# Antigravity CLI (agy) Rollout & Cutover — gmi Retirement

> Bead `bd-47kjh.11`. Companion to [`AGY_MIGRATION_REFERENCE.md`](./AGY_MIGRATION_REFERENCE.md).
> Status as of the 2026-06-18 cutover.

## What happened

Google retired the **Gemini CLI (`gmi`)** on **2026-06-18** — it no longer serves
Pro/Ultra/free tiers. Its successor is the **Antigravity CLI (`agy`)**, a standalone
self-updating native binary. Every flywheel surface that spawns, detects, indexes,
resumes, configures, installs, guards, or documents a Gemini-family agent has been
migrated to `agy`, **additively**: `gmi` stays usable as a legacy reader of
already-existing `~/.gemini/tmp/<hash>/chats/*.json` history, but `agy` is the
forward path for all new work.

## Guiding principle (applied everywhere)

- **Operational** ("start a session" / spawn / recommend / default swarm) → `agy`.
- **Historical** (resume/read/discover an existing Gemini session) → keep `gmi`/`gemini`.
- **Model mandate**: every `agy` invocation is pinned to **`Gemini 3.1 Pro (High)`** —
  the only allowed model. Single source of truth: `scripts/lib/agy_model_guard.sh`
  (referenced by the bash, Go, and Rust ports).
- **Disambiguation**: the `~/.gemini/` parent is shared. `~/.gemini/tmp` = gmi;
  `~/.gemini/antigravity-cli/` = agy (conversations at `conversations/<uuid>.db`,
  auth at `antigravity-cli/antigravity-oauth-token`, MCP at `config/mcp_config.json`).

## Component status

| Surface | Status | Notes |
|---|---|---|
| **ACFS install** | ✅ | `agents.antigravity` manifest module (verified_installer, checksum-gated); `uca` updates agy; `agy()` model-pinned launcher in acfs.zshrc; `doctor` checks `agent.alias.agy`. |
| **ACFS docs/onboarding** | ✅ | AGENTS.md, README, onboarding lessons, info/report/continue/cheatsheet, swarm-default mixes (`--agy=`). |
| **ACFS checksum monitor** | ✅ | `antigravity` in `KNOWN_INSTALLERS` + `checksums.yaml`; monitored like uv/rustup/bun. |
| **Shared e2e harness** | ✅ | `scripts/lib/agy_e2e_harness.sh` (structured logging, skip-if-unauth, model-guard, headless round-trip). |
| **franken_agent_detection (F1)** | ✅ | Antigravity connector (`src/connectors/antigravity.rs`) — shared detection/reader. |
| **cass (F2)** | ✅ | Indexes agy history; sync presets + disambiguation. |
| **ntm (F3)** | ✅ | `--agy=N` spawn flag + agy provider (ntm#185); agy session discovery/resume from `conversations/<uuid>.db`. Live-tmux spawn e2e (`4.3`) belongs to the shared harness. |
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
- ACFS `agents.gemini` manifest module + `gmi()` zshrc launcher (relabelled legacy).
- Doc tables that list `--gmi=N` as a legacy flag alongside `--agy=N`.

## Deferred (needs a live interactive agy + TTY)

- **Live-tmux spawn/resume e2e** (ntm `4.3`, and the interactive halves of the
  per-component e2e): the provider/unit logic is covered; full live runs use the
  shared harness on a machine with an authenticated agy + real tmux.
- **frankenterm**: gmi → agy is cataloged but **not applied** — the working tree is
  on a detached HEAD with a broken submodule (defer to mac-mini-max). It needs an
  `Antigravity` variant in its `AgentProvider` enum (`session_resume.rs`,
  `status_bar.rs`) + `conversations/<uuid>.db` discovery, plus doc/tape updates.

## Verification

- `agy --model "Gemini 3.1 Pro (High)" --print "…"` returns a real completion on the
  pinned model (verified on the fleet).
- `bash scripts/lib/agy_model_guard.sh --self-test` and
  `bash scripts/lib/agy_e2e_harness.sh --self-test` pass.
- `bash tests/unit/test_agy_install.sh` — agy install contract (13 checks) passes;
  `bash scripts/e2e/test_agy_install.sh` — live round-trip passes (skips if unauth).
