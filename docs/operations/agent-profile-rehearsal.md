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
  --profile claude:work --profile codex:review --run --json

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
It then checks the same isolated profile's status again. A busy profile is not
started or unlocked. Unknown, conflicting, or malformed status output is not
interpreted as success. Failed commands are not automatically retried.

The profile must appear in `caam profile ls PROVIDER`. The vault entries shown
by `caam ls PROVIDER` are a different store; a vault-only entry is not silently
activated or converted into an isolated profile. CAAM's status command currently
has a fixed text header rather than a JSON flag; changed output produces an
explicit unrecognized-status result.

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
Unrecognized status/version output is a warning. Exit codes are 0 for a plan or
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

ACFS does not call `activate`, `backup`, `login`, `refresh`, `clear`, or `run` with
a model prompt. CAAM/provider commands can still update their own local metadata;
this is not a filesystem sandbox or a promise of zero upstream side effects.
Timeout and cancellation stop the process group created for that probe. A killed
CAAM process can leave its own stale lock; ACFS reports the failure rather than
removing a lock or restoring credentials automatically.

## Tests and remaining acceptance

`packages/manifest/src/agent-profile-rehearsal.test.ts` covers the actual process
runner as well as protocol fixtures: explicit selection, root/sudo refusal,
missing auth, locked/missing profiles, malformed responses, post-execution
changes, output limits, descendant termination, cancellation, and redaction.
A CLI integration case runs a fixture CAAM executable as an unprivileged user.
No test logs in to a live provider or consumes model quota. Live installed-CAAM
and authenticated-provider acceptance remains separate from these fixtures.
