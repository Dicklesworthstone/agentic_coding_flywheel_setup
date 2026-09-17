# ACFS Plugin Verification and Target-User Installation

ACFS supports a deliberately narrow plugin installation path: a reviewed
archive, explicit module selection, an approved execution-plan fingerprint,
existing first-party prerequisites, and checksum-bound target-user installers.

`plugin:verify` remains read-only. `plugin:install` defaults to a read-only plan
and requires both `--yes` and `--accept-plan` to execute. Neither command changes
canonical generated artifacts. The generator still refuses loose `--plugin`,
`--plugins-dir`, `ACFS_PLUGIN_PATHS`, and `ACFS_PLUGINS_DIR` inputs. Profile/web
integration, elevated capabilities, other install kinds, and true offline
execution remain unsupported. See [plugin-manifest-contract.md](plugin-manifest-contract.md)
for the broader design contract; this guide describes the implemented subset.

## Verify, preview, then install

Run from a trusted checkout with the manifest package's Bun dependencies installed:

```bash
cd packages/manifest
bun run plugin:verify \
  --archive /path/to/example-tools.tar.gz \
  --review /trusted/reviews/example-tools.json \
  --target ubuntu/26.04/x86_64/glibc --json

bun run plugin:install \
  --archive /path/to/example-tools.tar.gz \
  --review /trusted/reviews/example-tools.json \
  --target ubuntu/26.04/x86_64/glibc \
  --only plugin.example_tools.cli --json
```

The second command prints `status: "planned"`, `mode: "dry-run"`, the dependency
closure, existing first-party prerequisites, exact installer hashes/arguments,
and `plan.planSha256`. It performs no installer downloads, subprocess checks,
or state writes. `--dry-run` makes this default explicit. There is no implicit
"install everything" selection. `--only` accepts comma-separated exact plugin
IDs. `--skip` may exclude other plugin IDs, but skipping a selected module or
any required dependency is an error, not permission to broaden or weaken a plan.

After reviewing the plan, repeat the same inputs **as the target Linux user,
not through sudo**, adding the fingerprint printed by the preview:

```bash
bun run plugin:install \
  --archive /path/to/example-tools.tar.gz \
  --review /trusted/reviews/example-tools.json \
  --target ubuntu/26.04/x86_64/glibc \
  --only plugin.example_tools.cli \
  --yes --accept-plan <planSha256-from-preview> --json
```

The CLI reloads the archive and external review and reruns canonical validation.
The plan fingerprint binds package/source/archive provenance, target, canonical
manifest and checksum bytes, selection, prerequisites, installer bytes, arguments,
and verification commands. Changed inputs require a new preview; a saved plan
file is never accepted as executable authority.

The example target does not migrate ACFS's root installer defaults or certify
Ubuntu 26.04 support throughout ACFS. Execution checks the actual Linux OS
version, architecture, and glibc against the explicit target. Previewing a plan
on a different host is allowed; executing it there is not.

## Execution and resume behavior

First-party dependencies must already be installed. Their canonical verification
commands run without privilege elevation; the plugin command never installs,
upgrades, or repairs them. A failed prerequisite stops before downloads. Install
missing prerequisites through the normal ACFS workflow and preview again.

Every pending installer is downloaded over verified HTTPS and checked against
`checksums.yaml` before **any** installer runs. Redirects cannot downgrade TLS or
add credentials. Downloads are bounded to 8 MiB per entrypoint, 32 MiB total
staging, five redirects, and a 60-second download deadline. Script snapshots
stay in memory and are passed to fixed `/bin/bash` or `/bin/sh` runners over stdin,
not a mutable staged pathname. This is an entrypoint check, not a claim that
upstream installers bundle or cryptographically pin all transitive downloads.

Installers execute noninteractively with literal arguments, an allowlisted
environment, system `timeout`, and `setpriv --no-new-privs`. This prevents
setuid/file-capability privilege gains through exec; it is **not** a filesystem
or network sandbox. Reviewed installers still have the target user's access to
files and network services. They must work without root privileges, interactive
input, inherited credentials, shell startup injection, or an on-disk `$0` script.
The runtime does not forward API keys, tokens, or arbitrary caller environment.
Raw installer output is discarded rather than persisted or exposed as diagnostics.

A kernel `flock` serializes plugin installs for that user. The parent keeps its
locked descriptor open and passes it to execution children. If the parent dies,
surviving descendants that retain the descriptor continue to exclude a retry.
Each plan stores an atomic, fsynced, private receipt at:

```text
~/.acfs/plugin-installs/<planSha256>.json
```

Receipts record per-module `pending`, `running`, `complete`, or `failed` state and
exit codes. Normal retries skip a completed module only after its declared
executables pass fresh checks. A missing executable invalidates its checkpoint.
Failed modules can be retried; already verified dependencies are retained. A
final verification sweep must pass before the command reports completion.

Malformed, mismatched, symlinked, hardlinked, or unsafe state is refused, not
silently replaced. A receipt left with a `running` action after abrupt process
loss is ambiguous: inspect the receipt, installer processes, and installed files
before recovery. The command does not steal a live lock, blindly replay an
interrupted installer, delete evidence, or roll back arbitrary user files.
Installers have a 15-minute runtime limit and bounded TERM/KILL cleanup for their
own process groups. An entrypoint that exits zero but leaves group members behind
is failed with exit code 125 rather than marked successful. SIGINT/SIGTERM
cancellation cannot produce a success result. Deliberately detached processes,
explicitly closed descriptors, or malicious same-user code are not contained by
this mechanism; reviewed installers must not daemonize or tamper with the lease.

## Inspect and recover an interrupted installation

Use the same archive, review, target, and selection as the original installation.
These modes still rebuild and validate the plan, require a valid external review,
and run as the matching target user on the matching host. They do not accept a
saved plan or arbitrary receipt pathname as authority.

```bash
bun run plugin:install \
  --archive /path/to/example-tools.tar.gz \
  --review /trusted/reviews/example-tools.json \
  --target ubuntu/26.04/x86_64/glibc \
  --only plugin.example_tools.cli --status --json
```

Status returns `status: "inspected"`, `mode: "status"`, and an `inspection`
containing the exact receipt digest, per-action state, and `recoveryEligible`.
It creates no directories or lock files, modifies no receipts, downloads nothing,
and executes no health or installer commands. It briefly takes the existing lock
for a stable snapshot. A busy lock returns `inspection.status: "busy"` with no
receipt fingerprint to approve. A recorded `complete` receipt is historical:
`healthChecked` is always false. An `incomplete` finalization without a running
action needs an ordinary approved retry, not interruption recovery.

After reviewing the interrupted actions and their possible partial effects,
set `PLAN_SHA256` to `inspection.planSha256` and `RECEIPT_SHA256` to the inspected
`inspection.receiptSha256`, then explicitly approve recovery:

```bash
bun run plugin:install \
  --archive /path/to/example-tools.tar.gz \
  --review /trusted/reviews/example-tools.json \
  --target ubuntu/26.04/x86_64/glibc \
  --only plugin.example_tools.cli \
  --recover --yes --accept-plan "$PLAN_SHA256" \
  --accept-receipt "$RECEIPT_SHA256" --json
```

Recovery acquires the existing exclusive lease and compares the exact receipt
bytes with the approved fingerprint. Changed receipts require a new inspection.
It durably preserves the original bytes in a private file named
`<planSha256>.interrupted-<receiptSha256>.json` before replacing active state.
Only `running` actions become `failed` with an unknown (`null`) exit code;
completed dependencies stay completed. The active receipt records `recoveredFrom`
so the preserved evidence is identifiable. Recovery never marks an interrupted
action successful and never downloads, verifies executables, or runs installers.
A separate normal `--yes --accept-plan` invocation is required to retry; it
rechecks completed dependencies and all existing trust boundaries as usual.

Legacy interrupted receipts without `executionProtocol: "inherited-lock-v1"`
remain inspectable but cannot use automatic recovery: an unlocked legacy lock
does not establish that an orphan installer has exited. Unknown protocols,
malformed or noncanonical machine receipts, mismatched plan/package identities,
unsafe files, and conflicting preserved evidence fail closed. Do not edit a
legacy receipt to manufacture protocol support or overwrite the evidence file.
An exact pre-existing backup is accepted after a crash between backup and state
replacement; a different backup is never overwritten.

Install command exits: `0` for a valid preview, verified installation, successful
status query (including busy/not-started), or completed recovery operation; `1`
for trust, planning, state, prerequisite, or execution refusal; `2` for invalid
arguments; `130`/`143` for interrupt/termination. JSON output distinguishes
`status: "planned"`, `"inspected"`, `"recovered"`, `"complete"`, and `"failed"`.
Recovery success means state is retryable, not that tools are installed.
`plugin:verify` retains its previous output and exit
contract, including `activation: "disabled"` because it never performs installs.

## External review record

The operator selects a separately trusted review. A JSON review is not a
signature: a package author's self-issued file does not establish independent
trust. Do not generate approval automatically from an untrusted package.

```json
{
  "schema": "acfs.plugin-review.v1",
  "packageId": "example.tools",
  "version": "1.2.3",
  "sourceCommit": "0123456789abcdef0123456789abcdef01234567",
  "packageSha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "reviewer": "maintainer-identity",
  "reviewedAt": "2026-09-17T00:00:00Z",
  "expiresAt": "2026-10-17T00:00:00Z",
  "target": { "os": "ubuntu", "version": "26.04", "arch": "x86_64", "libc": "glibc" },
  "approvedCapabilities": ["verified_installer", "doctor_check", "web_metadata"]
}
```

The digest is illustrative, not an approval. Reviewers must inspect the exact
package, source revision, installer and requested capabilities. The loader checks
the compressed SHA-256 before decompression and reads the same byte snapshot.
Identity, version, commit and complete target tuple must match. All review fields
are required; unknown fields, duplicate keys, malformed times, future-dated or
expired reviews are refused. Expiration is exclusive. Every retry checks review
validity anew before planning or installation begins.

Only baseline `verified_installer`, `doctor_check`, and `web_metadata` capabilities
can be approved. Root/current-user modules, default-enabled plugins, cross-plugin
dependencies, arbitrary shell, services, and reserved `release_artifact`,
`copy_asset`, and `manual_step` executors remain refused. A review cannot replace
the canonical checksum database or waive these restrictions.

## Archive contract

The required regular files are `acfs-plugin-package/plugin.json`, `README.md`,
and `LICENSE` under that same single root. Produce a portable archive with:

```bash
tar --format=ustar -czf example-tools.tar.gz acfs-plugin-package
sha256sum example-tools.tar.gz
```

Plain GNU tar and POSIX ustar are accepted. Links, devices, FIFOs, extended/sparse
headers, privileged permission bits, traversal, duplicate paths, conflicting
file/directory paths, malformed headers/padding, truncated members and trailing
payloads are refused. Paths use portable ASCII segments beginning with a letter,
digit or underscore, followed by letters, digits, underscores, dots or hyphens.

The three core files are implicitly declared. Every additional regular file must
be under `assets/`, `docs/`, or `provenance/`, declared with exactly `path` and
`sha256` in `extensions.archiveFiles`, and match its content digest:

```json
{"extensions":{"archiveFiles":[{"path":"docs/guide.md","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}}
```

Limits: 16 MiB compressed, 64 MiB expanded, 1 MiB manifest, 8 MiB per other member,
1,024 entries, and 64 KiB external review. JSON must be bounded UTF-8 with no BOM,
duplicate decoded keys, non-finite numbers or excessive nesting/node counts.
Input files must be nonempty, single-link regular files. Archive members are
never extracted, displayed, installed, or interpreted as scripts by the loader.

## APIs and verification

`loadReviewedPluginPackage` binds a real archive and independent review to the
canonical schema, merged graph, phases, capability policy and checksum map.
`loadPluginInstallPlan` reads the canonical checkout's trust files and builds a
selection-specific plan; `buildPluginInstallPlan` is its pure planning core.
`inspectPluginInstallPlan` and `recoverPluginInstallPlan` expose the same receipt
operations for a freshly validated plan; neither executes that plan.
Low-level archive readers still return semantically untrusted `unknown` content.
Do not replace these boundaries with deserialized "valid" results or plan files.

```bash
cd packages/manifest
bun test src/plugin-archive.test.ts src/plugin-review.test.ts src/plugin-verify.test.ts
bun test src/plugin-plan.test.ts src/plugin-runtime.test.ts src/plugin-install.test.ts
bun test src/plugin-supervision.test.ts src/plugin-recovery.test.ts src/plugin-recovery-cli.test.ts
bun test src/plugin.test.ts
bun run type-check
bun run generate --validate
```

Runtime tests use real unprivileged Linux processes, kernel locks, receipt files,
and a local TLS server. Run as a non-root Linux user to exercise installation;
the root-refusal case is exercised separately under root. The canonical
archive-to-plan test additionally requires the repository and its YAML/Zod/Bun
dependencies. Local fixture execution is not a live third-party installer test.
Supervision/recovery tests kill a real parent, check the surviving lease, preserve
the ambiguous receipt, and retry without replaying completed dependencies. CLI
routing tests inject a plan loader; they do not substitute for canonical archive,
review, manifest, and checksum integration tests.
