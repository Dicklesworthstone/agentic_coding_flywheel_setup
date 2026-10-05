# Isolated agent profile rehearsal

Before starting a multi-account workspace, exercise each explicitly selected
CAAM **isolated profile** through a bounded startup rehearsal. The normal
agent-readiness audit remains unchanged. Rehearsal is an opt-in companion to it,
not an automatic login, account rotation, or swarm launch. Local checks are the
default; a separately selected live model check can establish that the isolated
CLI actually completes a fresh request.

From an ACFS checkout with Bun installed:

```bash
# Review the selection without running CAAM or any provider.
bash scripts/agent-readiness-audit.sh --rehearse \
  --profile claude:work --profile codex:review --json

# Run local checks as the target user, never through sudo.
bash scripts/agent-readiness-audit.sh --rehearse \
  --profile claude:work --profile codex:review --run --native-auth --json

# Equivalent package command:
cd packages/manifest
bun run agent:rehearse --profile claude:work --run
```

Select one to eight profiles, repeating `--profile PROVIDER:NAME`. Supported
providers for local checks are `claude`, `codex`, `gemini`, and `agy`. Names are
passed as single arguments, not evaluated as shell code. `--timeout SECONDS`
bounds each local command (default 10, range 1–30); output is limited to 64 KiB
across stdout and stderr.

## What runs locally

For each selection, the implementation runs `caam profile status PROVIDER NAME`.
If CAAM confirms local authentication material and an unlocked profile, it runs
`caam exec PROVIDER NAME -- --version`, retaining CAAM's normal profile lock.
With `--native-auth`, it additionally runs `claude auth status` or
`codex login status` through that same `caam exec` isolation before the final
status check. Native status can catch a provider rejecting credentials even
when CAAM reports that its local auth files exist. Claude JSON must contain a
boolean `loggedIn` consistent with the exit status. Duplicate/escaped duplicate
JSON keys, extra JSON documents, unknown native formats, and conflicting status
lines are not accepted. Codex's status is read from stderr; even its masked API
key fragments are discarded, not copied into reports.

It then checks the same isolated profile's status again. A busy profile is not
started or unlocked. Unknown, conflicting, or malformed status output is not
interpreted as success. Failed commands are not automatically retried.

The profile must appear in `caam profile ls PROVIDER`. The vault entries shown
by `caam ls PROVIDER` are a different store; a vault-only entry is not silently
activated or converted into an isolated profile. CAAM's status command currently
has a fixed text header rather than a JSON flag; changed output produces an
explicit unrecognized-status result.

Gemini and Antigravity do not have a verified native status protocol in this
rehearsal. Their native check is explicitly marked `unsupported`; no guessed
flags are sent. `--require-native-auth` implies `--native-auth` and requires a
recognized positive native result, so unsupported or inconclusive checks cannot
pass that stricter mode. Without either flag or a live model, the original
status/version/status sequence remains unchanged. A prerequisite failure marks
native auth `not_checked`, distinct from `not_requested`.

Missing authentication requires a separate human login. For Claude, open the
isolated session using `caam exec claude NAME` and use its built-in `/login`.
Other providers use their own login flow, such as `caam login codex NAME`.
The rehearsal never performs those actions on the user's behalf.

## Complete a live model request

An installed CLI and parseable credentials cannot establish that a model request
works. `--live-model PROVIDER:MODEL` adds that missing step. The model is explicit:
ACFS does not pick a cheaper fallback, inherit an unreviewed default, or rotate
to another account. All selected providers need one model selection, even when
several profiles use the same provider. Live support currently covers Claude.
Unsupported providers, duplicate mappings and malformed model IDs are refused
before any checks run.

```bash
# Preview only: no identity lookup, process, directory creation, or network call.
bash scripts/agent-readiness-audit.sh --rehearse \
  --profile claude:work --live-model claude:sonnet --json

# Explicitly permit the paid/quota-consuming check after reviewing the plan.
bash scripts/agent-readiness-audit.sh --rehearse \
  --profile claude:work --live-model claude:sonnet \
  --run --live-timeout 90 --json --output "$HOME/live-rehearsal.json"
```

A live attempt occurs only after the profile, recognizable version, and every
requested native-auth check pass. Each profile receives a new random challenge
in a new private temporary directory, not a repository. The prompt contains only
that challenge. Success requires the CLI to exit zero and return a single
successful JSON result with exactly one turn, no permission denials, and the
matching challenge as its result. A banner, mere exit zero, stale response,
malformed/duplicate JSON, conflicting result, or wrong challenge cannot pass.
The original profile is checked again after the attempt.

Claude is invoked through `caam exec` with `--safe-mode`, an explicit model,
`--tools ""`, all tools disallowed, empty strict MCP configuration, empty setting
sources, disabled ordinary hooks, a fixed system prompt, and no session
persistence. `--bare` is intentionally **not** used because it disables the
subscription OAuth credentials this workflow is meant to exercise. Use a recent
Claude CLI supporting these flags: an older CLI fails without a permissive
fallback. Helper-based API-key settings are not imported into the live request.

`--live-timeout` is separate from the local timeout (default 60 seconds, range
1–120). Claude receives a one-turn limit and a $0.25 CLI budget guard. These are
bounds on the invocation, not a guaranteed billing cap: client cost estimates
and provider billing can differ, and a timed-out request may already be billed.
ACFS makes at most one live CLI attempt per selected profile and does not retry;
a provider can still perform internal transport retries. An unconfirmed live
attempt stops later profiles rather than multiplying uncertain requests.
Cancellation stops the current process group and does not certify a reply that
raced with the signal. A live CLI that exits while leaving process-group members
behind is failed and those members are killed. Deliberately detached descendants
are outside that process-group boundary; this is not an OS sandbox.

Temporary directories under `/tmp/acfs-live-rehearsal-*` (or the OS-resolved
`/tmp` path) are retained, including after failure. They start empty and private;
ACFS does not recursively remove files a provider may have created. Trusted CAAM
and provider binaries, their isolation behavior, and mandatory managed host
policy remain part of the trust boundary. CLI flags are restrictions requested
of those tools, not independent proof of zero side effects.

## Meaning of a result

A local-only `pass` covers `isolated-cli-startup-and-local-auth`: CAAM reported
local auth, the isolated CLI returned a recognizable version, and the final
local status remained usable. It does **not** establish server token validity,
quota, or model execution. Local-only reports retain `modelPromptSent: false`.

A live report has scope `isolated-cli-and-live-model`, per-profile `liveModel`
status and attempt count, and `liveModelPolicy`. Its `responseVerified` is true
only when every selected profile completed its unique challenge and passed the
final status check. `modelPromptSent` is false if no live attempt was made, null
if delivery is uncertain, or true if at least one response confirms delivery.
A true aggregate delivery flag does not mean every profile succeeded: inspect
per-profile results. The requested model is recorded, not a claim of an
independently attested backend model or account. `liveAuthenticationVerified`
remains false: no account-identity attestation is performed. One completed
request is not proof of future quota, model availability, or swarm capacity.

Plan-only runs return status `planned`, not readiness success. Missing auth,
busy profiles, failed commands, and changed post-execution state are failures.
Unrecognized status/version output is a warning in local mode and prevents live
execution. A native report of missing credentials is a failure even when CAAM's
local-file check passed. Requiring native auth promotes an unsupported or
inconclusive native check to failure. Exit codes are 0 for a plan or passing
rehearsal, 1 for a failing/inconclusive result, 2 for invalid input or
prerequisites, and 130 for cancellation.

## Privacy and side effects

JSON and human output identify selections as `profile-1`, `profile-2`, and so on,
in command-line argument order. They contain provider names, explicitly selected
model IDs, fixed result codes, booleans, exit codes, and numeric versions, not
account names, emails, paths, challenge/response text, provider metadata, or
diagnostic snippets. Raw captures are bounded in memory and are not written to
a log. Shared reports do not include the original selectors; keep their mapping
locally when troubleshooting.

Children receive a restricted environment. Inherited API keys, provider-specific
home overrides, runtime injection hooks and proxies are removed, so those cannot
silently replace the selected isolated identity. CAAM/XDG store locations and
absolute PATH entries are retained for the target user's installed tools. No
shell is used, stdin is closed, and checks run outside a project directory.
Proxy-only networks may therefore not work with the live check.

ACFS does not call `activate`, `backup`, a login flow, `refresh`, or `clear`.
Without `--live-model`, no model prompt is sent. `codex login status` is a status
query, not the login flow. CAAM/provider commands can update their own local
metadata; this is not a promise of zero upstream side effects. Timeout, SIGINT,
SIGTERM, and SIGHUP stop the process group created for that probe. A killed CAAM
process can leave its own stale lock; ACFS reports failure rather than removing
a lock or restoring credentials automatically.

## Private evidence export

`--output FILE` saves the same redacted JSON to a new mode-0600 file. Choose an
existing, user-owned, non-group/world-writable directory; no evidence directories
are created automatically. The path is checked before commands run and again
when publishing. Existing files, hard-linked existing targets, symlinks and
unsafe parent directories are refused. Export is explicit and also works for a
plan-only run:

```bash
bash scripts/agent-readiness-audit.sh --rehearse \
  --profile claude:work --profile codex:review \
  --run --require-native-auth --json --output "$HOME/rehearsal.json"
```

A concurrent file creation is never overwritten. If publication fails after
checks complete, JSON error output includes the redacted completed report, so
users can inspect the evidence without rerunning account checks. A crash during
file writing can leave incomplete JSON; it is not an atomic receipt or authority
to launch work. No partial file is deleted automatically. Choose a fresh output
name for another run. The report can be included manually with support evidence;
this command does not upload it or automatically ingest it into support bundles.

## Tests and remaining acceptance

The `agent-profile-rehearsal.test.ts`, `agent-profile-native.test.ts`, and
`agent-profile-live.test.ts` suites cover the actual process runner as well as
protocol fixtures: explicit selection, root/sudo refusal, missing auth,
locked/missing profiles, malformed responses, post-execution changes, output
limits, descendant termination, cancellation, and redaction. Live tests also
cover unique challenges, exact restrictive argv, cost opt-in, fail-fast behavior,
and uncertain delivery. CLI integration cases run fixture CAAM executables as
an unprivileged user. No test logs in to a live provider or consumes model quota.
Live installed-CAAM and authenticated-provider acceptance remains separate from
these fixtures.

## Protocol references

The command contract is checked against provider documentation and source,
not inferred from a successful `--version`:

- Claude Code CLI reference: <https://code.claude.com/docs/en/cli-reference>
- Claude print-mode results and bare-mode authentication: <https://code.claude.com/docs/en/headless>
- Codex CLI reference: <https://developers.openai.com/codex/cli/reference>
- Codex status implementation: <https://github.com/openai/codex/blob/44b857c00e5803adedbc5b2e94c4a33574a157fe/codex-rs/cli/src/login.rs>
- CAAM isolated profile/exec commands: <https://github.com/Dicklesworthstone/coding_agent_account_manager/blob/1e0e8e3019d306b34554715f3270ecae3218f653/cmd/caam/cmd/root.go>
