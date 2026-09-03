# Antigravity CLI (`agy`) — Canonical Migration Reference

> Deliverable of beads **bd-47kjh.1.2 (T0_2: schema)** + **bd-47kjh.1.3 (T0_3: CLI mapping)** + the model-pin contract for **bd-47kjh.1.7**.
> Every fact below is **verified against a live `agy` 1.0.7 install** (2026-06-11). This is the single source of truth the gmi→agy migration beads (epic `bd-47kjh`) implement against.

Google is retiring the Gemini CLI (`gmi`) on **2026-06-18**; `agy` (the Antigravity **CLI**, not the desktop app) replaces it. The migration is **additive**: keep reading old gmi history, make `agy` the forward path.

---

## 1. Install, auth, version

```bash
curl -fsSL https://antigravity.google/cli/install.sh | bash   # -> ~/.local/bin/agy
agy --version                                                 # -> 1.0.7
```
- **Auth** is Google OAuth via the system keyring; on headless/SSH it prints an auth URL + one-time code. A valid session is recorded at `~/.gemini/antigravity-cli/antigravity-oauth-token`. Authentication is a **human step** — agents cannot do it headlessly.
- `agy install` configures shell PATH/aliases. ⚠️ **GOTCHA:** it **purges shell-profile aliases** (`--skip-aliases` bypasses) and appends PATH (`--skip-path` bypasses) — it already wrote a PATH line to `~/.bashrc`. Our installer must use `agy install --skip-aliases --skip-path` (ACFS owns PATH) or skip `agy install` and place the binary itself, to avoid clobbering our `gmi`/`br` aliases or duplicating PATH.
- `agy update` self-updates the binary (relevant to the version-compat guard, bd-47kjh.2.5).

---

## 2. On-disk layout  (`~/.gemini/antigravity-cli/`)

| Path | What |
|---|---|
| `conversations/<uuid>.db` | **One stock-SQLite DB per conversation** (the `<uuid>` is the id used by `agy --conversation <uuid>`). Private protobuf schema (§4). |
| `brain/<uuid>/.system_generated/logs/transcript.jsonl` | ⭐ **Clean JSONL transcript of the conversation** — the recommended READ source (§3). Also `transcript_full.jsonl`. |
| `brain/<uuid>/.system_generated/messages/*.json` | Per-message JSON. |
| `brain/<uuid>/*.md` | Working docs (implementation_plan.md / task.md / walkthrough.md) — only for substantive conversations. |
| `settings.json` | ACFS pins `enableTelemetry: false`, `model: "Gemini 3.8 Flash (High)"`, `toolPermission: "always-proceed"`, `artifactReviewPolicy: "always-proceed"`, native-terminal rendering, sandbox off, and the other `agy-locked` defaults before every launch. |
| `cache/projects.json`, `cache/onboarding.json` | Workspace/onboarding metadata only (NOT history). |
| `antigravity-oauth-token`, `installation_id`, `keybindings.json`, `builtin/`, `implicit/`, `log/cli-*.log` | Auth, ids, config, logs. |
| `~/.gemini/config/mcp_config.json` | MCP server registration (empty by default; see §7). |

⚠️ **`~/.gemini/` is SHARED with gmi.** gmi history is `~/.gemini/tmp/<hash>/chats/session-*.json` (plain JSON). Detectors must distinguish by exact subtree + file type, never a blind `~/.gemini/**` glob (bead bd-47kjh.2.4).

---

## 3. ⭐ The transcript.jsonl — the recommended read/index source

`agy` writes a **plain JSONL** transcript per conversation. **Parse this, not the protobuf DB**, for indexing/resume previews — it turns T1_2 (bd-47kjh.2.2) from a protobuf reverse-engineering problem into a simple JSON parse (like the gmi reader). Record shape:

```json
{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"2026-06-11T20:14:42Z","content":"<USER_REQUEST>\n...\n</USER_REQUEST>\n<ADDITIONAL_METADATA>...</ADDITIONAL_METADATA>"}
{"step_index":3,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"...","content":"I am currently running as Gemini 3.8 Flash. ..."}
```
- `source`: `USER_EXPLICIT` | `MODEL` | `SYSTEM`.
- `type`: `USER_INPUT` | `PLANNER_RESPONSE` | `EPHEMERAL_MESSAGE` | `SYSTEM_MESSAGE` | `CONVERSATION_HISTORY` | … (tool steps appear for tool-using turns).
- The user's real prompt is wrapped in `<USER_REQUEST>…</USER_REQUEST>` with `<ADDITIONAL_METADATA>` (local time) and, on model change, `<USER_SETTINGS_CHANGE>` (records the model — useful for the guard). Reader must strip the wrapper tags.
- `content` is `null` for some system rows (tolerate it). Order by `step_index`.
- `transcript.jsonl` = condensed; `transcript_full.jsonl` = fuller — pick per need.

**Caveat:** the brain dir (and thus the transcript) is created when the conversation runs; a never-run conversation has none. The protobuf DB (§4) is the durable per-conversation store; the transcript is the easy parse. Prefer transcript; fall back to / cross-check the DB.

---

## 4. The conversation DB schema (secondary; protobuf)

`conversations/<uuid>.db` is stock SQLite ("SQLite format 3", user_version 1):

```
trajectory_meta(trajectory_id, cascade_id, trajectory_type, source)
steps(idx, step_type INT, status INT, has_subtrajectory, metadata BLOB, error_details BLOB,
      permissions BLOB, task_details BLOB, render_info BLOB, step_payload BLOB, step_format)
gen_metadata, executor_metadata, parent_references, trajectory_metadata_blob, battle_mode_infos
```
- Content is **protobuf** in the `*_payload`/`*_blob` columns (bytes begin with protobuf tags `0A..`). `strings` extracts the text; full structure needs protobuf decode.
- Observed `step_type` mapping (from a real conversation): **90** = system prompt (the "CRITICAL INSTRUCTION" tool rules), **15** = MODEL thinking + response, **23** = file/transcript reference, 14/98/101 = user/metadata steps. `status` 3 = DONE.
- ⚠️ This schema is **undocumented + private** and can change on `agy update`. The reader must **fail loud** on unknown schema/decode failure (never silently drop history) and track tested agy versions (bead bd-47kjh.2.5).

---

## 5. CLI surface (`agy --help`, verified)

| Need | Invocation |
|---|---|
| One-shot, non-interactive (scripts/spawn/skills) | `agy --print "<prompt>"` (also `--prompt`, `-p`). **The prompt is the VALUE of `--print`** — Go flag parsing. Put it LAST or use `--print="<prompt>"`. ⚠️ `agy --print --model …` makes `--print` swallow `--model` as the prompt. |
| Pick model (REQUIRED, §6) | `--model "Gemini 3.8 Flash (High)"` |
| Autonomous (no permission prompts) | `--dangerously-skip-permissions` |
| Workspace dir(s) | `--add-dir <dir>` (repeatable) |
| Resume most recent | `--continue` / `-c` |
| Resume by id (casr) | `--conversation <uuid>` (the `conversations/<uuid>.db` filename) |
| Sandbox | `--sandbox` |
| Timeout for `--print` | `--print-timeout` (default 5m) |
| Initial prompt then stay interactive | `--prompt-interactive` / `-i` |
| List models | `agy models` |
| Other subcommands | `agy install` (§1), `agy plugin`/`plugins`, `agy update`, `agy changelog` |

**Verified working headless task execution:**
```bash
agy --model "Gemini 3.8 Flash (High)" --add-dir /work --dangerously-skip-permissions \
    --print "Read notes.txt and reply with only the secret word."   # -> e.g. "FLYWHEEL 42"
```
Each `agy --print` starts a **new** conversation (new `conversations/<uuid>.db`). The model self-reports its name in early turns ("I am currently running as Gemini 3.8 Flash").

---

## 6. 🔴 MODEL-PIN GUARD (mandatory — bead bd-47kjh.1.7)

**Every** `agy` invocation in **every** tool/skill MUST run on **`Gemini 3.8 Flash (High)`** and never anything else. `agy models` lists:

| Allowed | Forbidden |
|---|---|
| `Gemini 3.8 Flash (High)` | `Gemini 3.8 Flash (Medium/Low)`, `Gemini 3.7 Flash (High/Medium/Low)`, `Gemini 3.6 Flash (High/Medium/Low)`, `Gemini 3.5 Flash (High/Medium/Low)`, `Gemini 3.1 Pro (High/Low)`, `Claude Sonnet 4.6 (Thinking)`, `Claude Opus 4.6 (Thinking)`, `GPT-OSS 120B (Medium)` |

**Enforcement contract:**
1. **Pin**: always pass `--model "Gemini 3.8 Flash (High)"` explicitly on every spawn/`--print`/`--continue`/`--conversation` call. Do NOT rely on the `settings.json` default.
2. **Verify** (any of, fail-closed): read `~/.gemini/antigravity-cli/settings.json → "model"`; and/or parse the transcript `<USER_SETTINGS_CHANGE>` / the model's self-report. If the effective model is not exactly `Gemini 3.8 Flash (High)`, **refuse/abort with a clear error** — never silently run on a worse model.
3. **One definition**: keep the allowed-model string in a single shared constant/helper per tool (Go helper in ntm, etc.) — no copy-paste drift.
4. Every e2e test asserts the model (§9).

---

## 7. MCP server registration (bead bd-47kjh.7.2)

agy reads MCP servers from `~/.gemini/config/mcp_config.json` — **empty by default**. To let agy agents use Agent Mail (`am`) + our other MCP servers, register them there (or via `agy plugin`, whichever agy actually consumes — verify the exact schema first by registering one through agy and capturing what it writes). Never write a bearer token into a tracked/committable file (cf. mcp_agent_mail_rust#148).

---

## 8. gmi → agy quick map

| gmi (legacy) | agy |
|---|---|
| `gmi` (interactive) | `agy-locked` (same forward path as `agy`) |
| scripted prompt | `agy --print "<prompt>" --model "Gemini 3.8 Flash (High)"` |
| history `~/.gemini/tmp/<hash>/chats/session-*.json` (JSON) | `~/.gemini/antigravity-cli/conversations/<uuid>.db` + `brain/<uuid>/…/transcript.jsonl` |
| resume | `agy --continue` / `agy --conversation <uuid>` |
| model select | `--model "<name>"` (PIN to Gemini 3.8 Flash (High)) |
| MCP servers | `~/.gemini/config/mcp_config.json` |
| account switch (caam) | OAuth keyring + `antigravity-oauth-token` |

---

## 9. Testing baseline (harness bead bd-47kjh.12)

Every per-component e2e script must: structured timestamped logging + artifact capture (the exact `agy` command incl `--model`, stdout/stderr, the resulting `conversations/<uuid>.db` + `brain/<uuid>/…/transcript.jsonl`, the effective model); assert the model is `Gemini 3.8 Flash (High)`; skip cleanly if agy is unauthenticated; clean up its temp conversations. Reuse the verified smoke prompt (read a fixture file → assert the answer) as a known-good agy task.
