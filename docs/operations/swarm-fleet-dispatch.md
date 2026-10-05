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
```

Tests execute the actual controller with real private launch/dispatch journals,
locks, file changes and protocol peers. They check all-host barriers, exact
binding, argument quoting, transport restrictions, immutable results, and failure
stops. These tests are not real SSH/VPS/NTM or authenticated-provider acceptance.
The command requires Linux and system OpenSSH on the controller, a complete
trusted ACFS checkout, and already installed native launchers on remote hosts.
It is not a new installed `acfs` subcommand.
