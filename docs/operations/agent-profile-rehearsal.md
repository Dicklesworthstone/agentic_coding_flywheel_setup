# Isolated agent profile rehearsal

Before starting a multi-account workspace, exercise each explicitly selected
CAAM **isolated profile** through a bounded local startup rehearsal. The normal
agent-readiness audit remains unchanged. Rehearsal is an opt-in companion to it,
not an automatic login, account rotation, or swarm launch.

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
providers are `claude`, `codex`, `gemini`, and `agy`. Names are passed as single
arguments, not evaluated as shell code. `--timeout SECONDS` bounds each command
(default 10, range 1–30); output is limited to 64 KiB across stdout and stderr.

## What runs

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
pass that stricter mode. Without either flag, the original status/version/status
sequence remains unchanged. A prerequisite failure marks native auth
`not_checked`, distinct from `not_requested`.

Missing authentication requires a separate human login. For Claude, open the
isolated session using `caam exec claude NAME` and use its built-in `/login`.
Other providers use their own login flow, such as `caam login codex NAME`.
The rehearsal never performs those actions on the user's behalf.

## Meaning of a result

A `pass` proves only the stated scope, `isolated-cli-startup-and-local-auth`:
CAAM reported local auth, the selected isolated CLI returned a recognizable
version, and the final local status remained usable. It does **not** prove that
a server will accept a token, that it is unexpired, that quota is available, or
that a model can complete a request. Every report explicitly records
`liveAuthenticationVerified: false` and `modelPromptSent: false`.

Plan-only runs return status `planned`, not readiness success. Missing auth,
busy profiles, failed commands, and changed post-execution state are failures.
Unrecognized status/version output is a warning. A native report of missing
credentials is a failure even when CAAM's local-file check passed. Requiring
native auth promotes an unsupported/inconclusive native check to a failure.
Exit codes are 0 for a plan or
passing local rehearsal, 1 for a failing/inconclusive result, 2 for invalid input
or prerequisites, and 130 for cancellation.

## Privacy and side effects

JSON and human output identify selections as `profile-1`, `profile-2`, and so on,
in command-line argument order. They contain provider names, fixed result codes,
booleans, exit codes, and numeric versions, not account names, emails, paths,
provider output, or diagnostic snippets. Raw captures are bounded in memory and
are not written to a log. Shared reports do not include the original selectors;
keep their mapping locally when troubleshooting.

Children receive a restricted environment. Inherited API keys, provider-specific
home overrides, runtime injection hooks and proxies are removed, so those cannot
silently replace the selected isolated identity. CAAM/XDG store locations and
absolute PATH entries are retained for the target user's installed tools. No
shell is used, stdin is closed, and checks run outside a project directory.

ACFS does not call `activate`, `backup`, a login flow, `refresh`, `clear`, or send
a model prompt. `codex login status` is a status query, not the login flow.
CAAM/provider commands can still update their own local metadata;
this is not a filesystem sandbox or a promise of zero upstream side effects.
Timeout, SIGINT, SIGTERM, and SIGHUP stop the process group created for that
probe. A killed
CAAM process can leave its own stale lock; ACFS reports the failure rather than
removing a lock or restoring credentials automatically.

## Private evidence export

`--output FILE` saves the same redacted JSON to a new mode-0600 file. Choose an
existing, user-owned, non-group/world-writable directory; no directories are
created automatically. The path is checked before commands run and again when
publishing. Existing files, hard-linked existing targets, symlinks and unsafe
parent directories are refused. Export is explicit and also works for a
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

The `agent-profile-rehearsal.test.ts` and `agent-profile-native.test.ts` suites
cover the actual process
runner as well as protocol fixtures: explicit selection, root/sudo refusal,
missing auth, locked/missing profiles, malformed responses, post-execution
changes, output limits, descendant termination, cancellation, and redaction.
A CLI integration case runs a fixture CAAM executable as an unprivileged user.
No test logs in to a live provider or consumes model quota. Live installed-CAAM
and authenticated-provider acceptance remains separate from these fixtures.

## Protocol references

The native command contract is checked against the provider documentation and
source, not inferred from a successful `--version`:

- Claude Code CLI reference: <https://code.claude.com/docs/en/cli-reference>
- Codex CLI reference: <https://developers.openai.com/codex/cli/reference>
- Codex status implementation: <https://github.com/openai/codex/blob/44b857c00e5803adedbc5b2e94c4a33574a157fe/codex-rs/cli/src/login.rs>
- CAAM isolated profile/exec commands: <https://github.com/Dicklesworthstone/coding_agent_account_manager/blob/1e0e8e3019d306b34554715f3270ecae3218f653/cmd/caam/cmd/root.go>
