# Send reviewed work to an existing fleet

The fleet launcher starts native agents but does not assign work. The checkout
controller `scripts/swarm-fleet-dispatch.py` connects that fleet's original
launch evidence to the installed per-host `acfs swarm launch --dispatch-batch`
workflow. It never spawns an agent, installs remote software, changes accounts,
claims Beads, or acquires reservations. Sending a work packet can start paid
model execution and editing; preview is separate from that authorization.

## Prepare and review work on each host

Use the original launch receipt with `acfs swarm launch --prepare-batch` on each
host, as described in [native launch](swarm-launch.md). Review the generated
Markdown, task, write scopes and agent identity mapping before dispatch. The
batch and packets stay on the remote host: this controller does not upload them
or reconstruct packet contents from a summary. Cross-host file-scope coordination
remains the operator's responsibility. Duplicate Bead IDs in one fleet dispatch
are refused rather than assigning the same task twice.

The local fleet launch journal must contain a confirmed result for every selected
host. Partial fleets are allowed only when each selected host has that evidence.
Endpoint, remote user, session, repository, receipt and original native process
identities come exclusively from that journal; they cannot be overridden by a
batch selection. Native support is Claude and Codex, as in the fleet launcher.

Create a private, mode-0600 file containing only explicit existing host IDs and
absolute paths to their reviewed remote batches:

```json
{
  "schema": "acfs.swarm-fleet-batches.v1",
  "hosts": [
    {"id": "worker-a", "batch": "/home/ubuntu/work-wave-1/batch.json"},
    {"id": "worker-b", "batch": "/home/ubuntu/work-wave-1/batch.json"}
  ]
}
```

Select any nonempty subset of the original fleet. Dispatch follows original
fleet order, not the order of this mapping. Each host has one batch with 1–32
unique original slots; unused slots are permitted. Empty, duplicate or unknown
hosts, relative/traversing paths, executable fields and existing delivery intents
are rejected for a new dispatch. The controller never adopts an old receipt as
permission to send a new packet.

## Preview, approve, send

Use the original fleet's independently verified host keys and explicit SSH
identity. Choose a new dispatch journal directory outside the launch journal,
under an existing user-owned directory not writable by others:

```bash
python3 -I scripts/swarm-fleet-dispatch.py \
  --launch-state "$HOME/fleet-wave-1" \
  --batches fleet-batches.json \
  --known-hosts "$HOME/.ssh/known_hosts" \
  --identity-file "$HOME/.ssh/id_ed25519" \
  --state-dir "$HOME/fleet-work-wave-1"
```

Default preview opens SSH connections but creates no dispatch files and sends
no work. Each selected host must confirm the original live native identities and
produce a valid launch-aware batch preview. The controller binds its original
launch targets to the native combined digest, and checks every returned slot,
provider, operation ID, task ID, receipt and payload digest. It never executes
command strings returned by a remote preview.

Inspect the per-host tasks and packet hashes in the JSON result and the original
packet Markdown. Repeat the same command with the returned digest:

```text
--send --accept-plan THE_DISPATCH_PLAN_SHA256
```

A launch digest cannot authorize work. Approval binds the entire selected fleet,
original launch evidence, SSH trust, remote batch paths, native review digests,
individual packet/payload identities, timeout and new local state directory.
Changed work or targets require another preview. A digest detects changes; it
is not a signature, model/account attestation, or substitute for human review.

Send rechecks every selected host before the first batch invocation. If any
preview fails, no local dispatch journal is created and nothing is sent. Hosts
then dispatch sequentially. Each native sender retains its live ready-queue,
pane-identity, exact-payload and durable-receipt checks. Capacity is not reserved
fleet-wide, and identity checks are not atomic with the eventual NTM send.
Do not restart agents or change packets/receipts during dispatch.

## Durable intent and partial failure

The controller fsyncs a new mode-0700 journal and mode-0600 intent, then writes
an immutable per-host attempt before invoking that host's batch sender. A
matching, fully submitted response creates a separate result:

```text
fleet-work-wave-1/
  intent.json
  worker-a.attempt.json
  worker-a.result.json
  worker-b.attempt.json
```

A lost response, timeout, malformed result or interruption is unconfirmed, not
proof of no delivery. Later hosts remain `not_attempted`; earlier submissions,
remote sessions, packets and all receipts are retained. Repeating a new send
against an existing state directory is refused before SSH. Never delete or move
receipts, choose new operation IDs, or change the state path to force a retry.
Inspect the native launch-aware dispatch on the affected host before recovery.
No destructive cleanup, rollback or automatic retry occurs.

## Reconcile and continue after interruption

Use the same launch journal, batch mapping, SSH trust, timeout and dispatch state
directory. Replace `--send --accept-plan ...` with `--reconcile` to query the
recorded attempts without writing controller state or sending work:

```bash
python3 -I scripts/swarm-fleet-dispatch.py \
  --launch-state "$HOME/fleet-wave-1" \
  --batches fleet-batches.json \
  --known-hosts "$HOME/.ssh/known_hosts" \
  --identity-file "$HOME/.ssh/id_ed25519" \
  --state-dir "$HOME/fleet-work-wave-1" --reconcile
```

For each attempted host, a fixed read-only Python program snapshots the original
private per-delivery intent over SSH. It checks ownership, permissions, regular
file type, hardlinks, symlink-free directories and a 1 MiB bound; it creates no
remote files. The controller validates that intent against the approved packet
request, then calls only `ntm --robot-send-receipt=OPERATION --robot-format=json`.
Successful proof must match the exact operation, payload hash and byte count,
session, recorded native target and completed submission admission. Raw receipt
and NTM diagnostics are never copied into reports.

This historical query does not need live panes or the original batch/packet
files on the remote. It does need both the original native delivery intent and
NTM's operation receipt. A missing, malformed, conflicting, partial or unavailable
receipt remains `unconfirmed` even when a local result previously said submitted.
No queried host can enter a preview or send path in this invocation. All
attempted hosts are checked, so one failed query does not hide its peers.

After reviewing the result, use `--resume --accept-plan ORIGINAL_DISPATCH_DIGEST`
instead. Resume first confirms every delivery on every attempted host. Only
then can it reconstruct a missing local result from the remote evidence, preview
all untouched hosts again, require byte-identical approved work/targets, and send
to those untouched hosts. A fully submitted fleet's resume only queries receipts;
it neither writes files nor starts model work. Earlier local results are never
replaced, and an attempted host is never sent its batch again by this controller.

**Continuation is host-granular.** If only part of a host's batch was submitted,
the missing per-delivery intents cannot prove those sends were never attempted.
The fleet controller leaves that host unconfirmed and does not continue its
batch. Inspect and, when justified, use the native launch-aware dispatcher on
that host with the original unchanged packets and receipts. Once all its
submissions have matching evidence, fleet reconciliation can confirm the host
and resume can continue untouched hosts. Never remove a receipt to force replay.

Malformed, truncated, non-prefix or mismatched local journals fail before SSH.
Recovery locks both journals, checks their captured bytes and directory identity
around remote operations, and refuses changed evidence. It does not adopt a
replacement directory. A receipt removed during a query cannot become permission
to send. These rules protect cooperative operations, not a malicious same-user process
rewriting every source of evidence. Preserve the launch journal as well as the
dispatch journal: its source evidence is part of the original approval.

Reconciliation returns exit 0 only when every selected host is confirmed
submitted. A healthy partial fleet returns `partial`/exit 1 with untouched hosts
marked `not_attempted`; any unknown submission returns `unconfirmed`/exit 1.
Resume requires the original digest; changing the batch or source evidence is
not a recovery override. Local state errors return 2, without a send fallback.

A native `submitted` result means matching NTM submission evidence, not task
execution, task completion, or Agent Mail registration. Reports contain reviewed
IDs and digests, never packet text or raw remote diagnostics. The private local
journal does contain endpoints, paths and operation metadata; it is not a
redacted support bundle.

The controller reuses the fleet launcher's strict SSH policy, anonymous snapshots
of host-key/identity bytes, closed stdin, bounded output and process-group
termination. Default timeout is 360 seconds per SSH operation, configurable from
1 to 600. A timed-out SSH client cannot guarantee that the remote batch stopped;
retain evidence and inspect the remote. The original launch journal is locked
and checked for mutation throughout. This excludes cooperating controllers,
not unrelated users or malicious same-user edits.

Exit 0 means a valid preview or fully confirmed submissions. Exit 1 means blocked
preview or uncertain submission. Exit 2 means invalid inputs, stale approval or
local state failure. Signal exits are 128 plus the signal number. Error reports
retain whether a send-capable invocation was attempted; that does not prove
whether its remote request arrived.

## Tests and acceptance boundary

```bash
python3 -B tests/unit/test_swarm_fleet_dispatch.py -v
python3 -B tests/unit/test_swarm_fleet_dispatch_recovery.py -v
```

Tests execute the actual controller with real private launch/dispatch journals,
locks, file changes and protocol peers. They check all-host barriers, exact
binding, argument quoting, transport restrictions, immutable results, and failure
stops. Recovery tests kill an actual controller child after its durable attempt,
then assert that its batch is queried rather than resent. The fixed remote
receipt reader is exercised as an unprivileged user with real private files,
symlinks, hardlinks, FIFOs, oversized input and literal shell arguments.
These tests are not real SSH/VPS/NTM or authenticated-provider acceptance.
The command requires Linux and system OpenSSH on the controller, a complete
trusted ACFS checkout, and already installed native launchers on remote hosts.
It is not a new installed `acfs` subcommand.
