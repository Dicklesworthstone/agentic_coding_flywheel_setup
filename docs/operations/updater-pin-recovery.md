# Updater installer-pin failures

A downloaded installer is executable only after its exact bytes match a trusted
entry in `checksums.yaml`. A mismatch can indicate a stale published pin or
unexpected upstream content; repeated downloads are not evidence of trust.

## Recovery behavior

The verifier can refresh checksum metadata once using its existing trusted
metadata path. If the refreshed pin matches the bytes already downloaded, those
same bytes are accepted without downloading them again. A different URL or pin
can justify one new download and verification. An unchanged URL/pin pair is not
retried after rejection. The updater does not run Claude's identical reinstall
fallback after a checksum refusal, even with `--force`.

The verified-installer boundary returns a distinct internal checksum result.
It is created only before executing the downloaded installer, using the
verifier's structured failure reason rather than searching human log messages.
An installer exiting with that reserved status is treated as an ordinary failed
installer, not as a pre-execution pin refusal. Missing or malformed pins also
block execution. Network errors remain eligible for the existing bounded retry
policy; active holds and rollback backoff still take precedence.

## Operator output

Pin-blocked updates remain included in the existing failed-tool count and
process exit convention (1 for total failure, 2 for partial failure). They are
also listed separately under `CHECKSUM BLOCKED`, including in `--quiet` output
and the update log. A working existing binary cannot turn a refused checksum
into a successful update or a transient-outage skip.

Read the verification diagnostics and review the published `checksums.yaml`.
Maintainers must independently review upstream changes before updating pins and
run the canonical manifest generator afterward. Never make the expected hash
match merely to silence a failure. End users can explicitly hold the affected
tool while its published metadata is investigated. No hold is created for them.

This is not a transaction for the entire update run: earlier tools may already
have been updated when another tool is blocked. The updater does not weaken
verification, change pins automatically outside its existing metadata refresh,
or launch a live update as part of the regression tests.

## Regression coverage

```sh
python3 -B tests/unit/test_update_pin_failures.py
```

These tests source the complete updater and security library. Network download
and installed-binary discovery are controlled fixtures; real hashing, exact-byte
verification, inert shell execution, background and pipeline exit propagation,
retry dispatch, and summaries use the production functions. They do not call
public installer endpoints or install packages. Live fleet acceptance and the
external automated setup checker are separate requirements.

## Verified release no-op updates (#505)

The updater can skip an unchanged Agent Mail or ASB installation without using
a self-reported version as proof. The two adapters have different release
contracts; the generic verified-installer wrapper does not skip other tools.

### Private installer staging (#508)

Hand-written stack installers, updates, doctor fixes, the installer's low-space
fallback, and generated installers allocate per-run directories through
`acfs_prepare_installer_tmpdir` in `scripts/lib/security.sh`. The helper runs as
the target account and creates `.cache`, `acfs`, `installer-tmp`, and the random
per-run directory with mode `0700` when they do not exist. Its private umask is
confined to a child process: a caller using `002` or `022` keeps that umask.
Agent Mail's archive, checksum manifest, and signature are created with a private
mask too, including after the target-user handoff. The evidence reader still
rejects group- or world-writable files; no authentication rule is relaxed.

The helper walks every component from `/` with no-follow directory descriptors.
It requires the home and cache tree to belong to the executing target account,
rejects writable ancestors, and compares each retained directory with its name
before returning a path. Only root-owned sticky `/tmp` and `/var/tmp` qualify
for system-temporary-directory protection when they are above a test or
temporary home. A private leaf beneath an unsafe parent is insufficient.

Legacy group-writable `~/.cache/acfs` and `installer-tmp` directories can be
tightened in place only after their ancestors pass validation. This migration
requires target-account ownership, its local user-private group, no other
listed primary or supplementary group members, no world write or special mode
bits, and no access/default POSIX ACL. It clears only group/other write using
`fchmod` on the checked descriptor and prints the exact path, UID, GID, and mode
transition. Other ACFS cache creators use a local creation mask so they cannot
introduce fresh `0775` ancestry before an installer runs. They do not modify
existing permissions.

ACFS does **not** automatically change the home, the general `.cache` directory,
a foreign-owned directory, or a directory configured for sharing. Refusals name
the exact component and its observed owner/mode, the expected contract, and a
recovery action. Inspect that component and its parent, including group and ACL
sharing, with concurrent installers stopped. Ask the owner to restore the
expected private ownership/permissions only when that matches the intended use;
otherwise use an account with a private home/cache. Do not recursively chmod or
chown the tree, follow symlinks during repair, or change the user's global umask.

This validation detects replacement during allocation and repair. The returned
pathname remains within the target account's trust boundary; it is not a
lifetime defense against an attacker who can rewrite that account's updater,
home, or files after allocation.

The executable staging regressions are in
`tests/unit/test_update_idempotency.py`, the generated CASS installer tests in
`packages/manifest/src/generate.test.ts`, and the installer/update TMPDIR tests
in `tests/unit/lib/test_update.bats`. They use isolated filesystems and controlled
transport rather than live installers. Replacement tests run the actual helper
with test-side syscall barriers and a separate process replacing paths. Kernel
ownership and ACL cases explicitly report skips when the host cannot support
them.

### Agent Mail

For the reviewed Linux release-archive installer, ACFS resolves the exact
requested release (or the current release), fetches `SHA256SUMS` and its detached
signature, and verifies minisign with the installer's pinned maintainer key.
The authenticated comment must name `mcp_agent_mail_rust` and the exact release
tag. The chosen archive must have one unambiguous checksum entry. A genuine
signature from another tag does not satisfy this check.

Installer approval and adapter review are separate trust decisions. The adapter
accepts only explicitly reviewed installer hashes; publishing a new checksum
does not automatically authorize receipt reuse or ACFS's local-archive route.
The reviewed revisions are
[`bc796a2d`](https://github.com/Dicklesworthstone/mcp_agent_mail_rust/commit/bc796a2da6e56164d2c26328de1f5934de28df13)
(`3de2d65d…`) and
[`baa88392`](https://github.com/Dicklesworthstone/mcp_agent_mail_rust/commit/baa88392d75dedd13c0761cf88eadfd218ef7ee0)
(`16c12f59…`). Their signature key, release metadata, archive checks, offline
arguments, destination lock, and binary transaction behavior are unchanged.
The latter revision delays Python launcher, environment, and client takeover
until database migration verifies. Installer failure still prevents ACFS from
writing a receipt. An unreviewed pin retains the independently verified upstream
installation path and is identified in the update log; it is never accepted by
matching whatever checksum happens to be published.

The release-contract regressions load the actual shipped checksum metadata and
authenticate retained release metadata with real Minisign. This catches a
checksum refresh that would otherwise silently disable the reviewed adapter.
When the upstream installer changes, review its exact bytes and relevant
behavior before adding an approved hash, then run these regressions. The
installer hash is part of the receipt contract, so receipts from another
approved installer revision still require a new verified installation.

ACFS then compares this release contract with evidence from its last successful
verified installation. That evidence binds:

- The reviewed installer URL and actual installer SHA-256.
- Release tag, platform, archive URL and SHA-256, signed manifest and signature
  hashes, verification key, and installation options.
- Both installed executables, `mcp_agent_mail/am` and
  `mcp_agent_mail/mcp-agent-mail`, including their absolute paths, modes, and
  SHA-256 digests.

Receipts live in the selected account's
`~/.local/state/acfs/verified-installs/mcp_agent_mail.json`. They are private JSON
data, never sourced as shell. Reads and writes run as that account using an
isolated system Python interpreter. The helper rejects unsafe ownership,
writable shared directories, symlinks, nonregular files, hard links, duplicate
JSON fields, oversized metadata, incomplete inventories, and payload changes
during hashing. Publication uses an atomic rename with file and directory
`fsync`. Missing Python or unusable evidence disables the optimization and
retains the normal verified installation path.

An installation that predates this evidence must complete one verified install;
ACFS never blesses its existing files from their version output. Before running
the installer, ACFS stages the exact selected archive and signed metadata in a
private directory owned by the target account. It checks all three files against
the authenticated contract and hashes the two executable archive members without
extracting or executing them. The bounded reader rejects duplicate, unexpected,
pathful, nonregular, sparse, or oversized members.

The installer receives the exact version and checksum with a local `file://`
archive URL and `--offline`. Its ordinary signature, archive-shape, and version
verification still runs against the staged release metadata. The archive is
downloaded once; the installer reads those same bytes locally. A concurrent
change to `latest` cannot bind a different release to a receipt.

Existing evidence is invalidated before executing an installer, and a failed
installer cannot publish replacement evidence. After successful installation,
ACFS requires the installed pair to match the hashes derived from the
authenticated archive before probing its version or publishing a receipt. A
different same-version installation that completes in the meantime is rejected.
The `agent-mail-minisign-v2` contract deliberately invalidates receipts from the
earlier post-install-snapshot adapter; those installations must be verified
again before reuse.
Once ACFS decides installation is necessary, it passes the upstream `--force`
option to suppress informational probes of the old, potentially corrupted
binaries. That upstream option does not disable release authentication.

A repeated update with the same authenticated release and intact files skips
the installer download and execution. It still fetches the small current release
metadata and reads the installed binaries; this is not an offline or zero-I/O
operation. A changed manifest, changed installer pin, missing or altered binary,
unsafe receipt, or pending upstream installation transaction prevents a no-op.

The receipt is evidence of a verified install followed by drift detection within
the target account's trust boundary. It is not a signature over arbitrary local
files and does not protect against an attacker who can rewrite that account's
updater and receipts. Independent authentication of an arbitrary existing
installation would require signed per-file digests or a separately protected
archive/attestation.

### Service reconciliation and operator intent

Agent Mail service reconciliation runs even when installation is a no-op.
`stack.sh` retains its existing conditional restart decision: an unchanged unit,
healthy and active service, and identical running/installed executable content
preserve the current process. An unhealthy service, changed managed unit, or
actual executable upgrade still reaches the existing repair/restart path.
ACFS passes `--no-service` to the upstream installer so service management stays
with this conditional mechanism.

For the reviewed no-op adapter, receipt checks and service reconciliation share
the upstream installer's owner-only destination-directory kernel lock. ACFS
releases its lock before invoking the installer, then reacquires it and checks
the authenticated payload before reconciling the service. An active competing
installer, changed lock authority, or unrecovered transaction prevents service
work. A target-account helper process owns the lock descriptor, so a background
server cannot inherit it and keep future installs locked out.

Both public commands, `am` and `mcp-agent-mail`, are reconciled in the configured
target bin directory and `~/.local/bin` even when the payload is unchanged.
Repairing a missing or incorrect command link does not restart a healthy
service. A link obstruction is reported before service reconciliation.

`--force` bypasses the no-op and explicitly requests reinstallation; it does not
bypass checksums or active tool holds. Tool holds suppress installation and
service actions. Persistent service masks, operator-disabled units,
`ACFS_SKIP_AGENT_MAIL`, and operator unit customizations retain their existing
semantics. A service-only opt-out does not imply a tool hold.

### ASB and the remaining installers

ASB publishes the installed script itself plus `asb-checksums.txt`. Its adapter
can therefore compare the installed script directly with the unique checksum
for the exact current release, without a receipt or an installed-script version
probe. It checks the default destination, selected command, regular-file type,
ownership, executable mode, and runtime prerequisites. Installation remains
pinned to the resolved `ASB_VERSION` when repair or upgrade is needed. Holds,
rollback backoff, `--force`, and checksum refusal keep their existing behavior.

Both adapters opt in only for a reviewed installer URL/pin. When a maintainer
updates that pin, review the new installer's complete payload, options, and
security contract before updating the adapter's reviewed pin. An unfamiliar
installer continues through the existing verified path. Custom destinations,
offline caches, alternate artifacts, and unsupported modes do not silently
inherit a default adapter's no-op decision.

FrankenSearch's managed Linux archive path now passes `--lite` explicitly, so
selecting a lite archive does not also request the upstream installer's default
semantic-model provisioning. Explicit source, artifact, checksum, offline,
version, and repository selectors are delegated unchanged to the verified
installer. `--verify` retains its independent archive-signature requirement.
This profile correction does not enable a FrankenSearch no-op receipt.

The other tools reported in #505 remain on their independent installer paths:

| Tool | Why a generic version or primary-binary skip is insufficient |
| --- | --- |
| APR | Defaults to mutable `main`; also manages Gum, Node, Oracle, and PATH. Release checksums are not mandatory in every mode. |
| RCH | Installs multiple binaries and reconciles hooks, skills, daemon/watchdog services, and remote workers; target fallbacks and optional signature verification need their own contract. |
| SRPS | Reconciles system settings, Ananicy, mutable rules, helpers, and services rather than one release payload. |
| FrankenSearch | Linux lite already has an exact archive/checksum contract, but lite/full profiles and optional archive signatures must be bound before enabling reuse. |
| SBH | The managed `scripts/install.sh` has archive, raw-file, and source paths, skills, distinct service binaries, and macOS signature requirements. |
| PFR | Defaults to a mutable source tree and installs scripts, libraries, docs, and skills; a complete immutable tree identity is needed to avoid its download safely. |

The reusable receipt helper is available to future reviewed adapters with a
complete immutable payload inventory. It does not change these installers'
security requirements or suppress their configuration and service work.

### Focused validation

```sh
python3 -B tests/unit/test_update_idempotency.py
python3 -B tests/unit/test_update_pin_failures.py
bash tests/unit/test_stack_agent_mail_mask.sh
bats --filter 'ASB current release' tests/unit/lib/test_update.bats
```

The signature fixtures use a real signed release manifest and real minisign.
Set `ACFS_TEST_MINISIGN` to a local minisign binary if it is not on PATH; those
cryptographic cases explicitly skip if the verifier is unavailable. The service
harness uses controlled systemd and `/proc` fixtures. Live user-systemd behavior,
stateful reservation-repair continuity, Docker installation, and the external
setup checker require the corresponding host environment.
