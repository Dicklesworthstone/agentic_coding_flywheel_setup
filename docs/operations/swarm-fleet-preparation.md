# Prepare a fleet's work from one controller

`scripts/swarm-fleet-prepare.py` fills the gap between fleet launch and fleet
work dispatch. It transfers an explicitly reviewed, globally scoped assignment
set to the original hosts, invokes their existing launch-aware packet preparer,
and produces the exact batch mapping accepted by `swarm-fleet-dispatch.py`.
It never starts agents, sends prompts, claims Beads, registers identities,
acquires file reservations, switches accounts, or installs remote software.

Run it from a complete trusted ACFS checkout on a Linux controller. Remote hosts
must already have their project and native ACFS launcher/packet preparer. The
original private fleet launch journal supplies endpoints, repositories, sessions,
receipts, providers and original process identities. The work specification
cannot override those bindings. Claude and Codex are supported by the native
launcher. This is a checkout command, not a newly installed `acfs` subcommand.

## One reviewed assignment set for one logical project

Save a private mode-0600 `fleet-work.json` outside the launch journal. For example,
a two-host fleet with one original launch slot on each host can use:

```json
{
  "schema": "acfs.swarm-fleet-work.v1",
  "hosts": [
    {
      "id": "worker-a",
      "output": "/home/ubuntu/work-wave-1",
      "identities": [{"slot": 1, "name": "RedFox"}]
    },
    {
      "id": "worker-b",
      "output": "/home/ubuntu/work-wave-1",
      "identities": [{"slot": 1, "name": "BlueLake"}]
    }
  ],
  "assignments": [
    {
      "host_id": "worker-a",
      "slot": 1,
      "bead_id": "bd-api",
      "role": "implementation",
      "write_scopes": ["src/api/**"]
    },
    {
      "host_id": "worker-b",
      "slot": 1,
      "bead_id": "bd-docs",
      "role": "documentation",
      "write_scopes": ["docs/api/**"]
    }
  ],
  "beads": [
    {
      "id": "bd-api",
      "title": "Implement the agreed API change",
      "status": "open",
      "issue_type": "task",
      "description": "Replace this example with the actual reviewed task brief."
    },
    {
      "id": "bd-docs",
      "title": "Document the agreed API contract",
      "status": "open",
      "issue_type": "task",
      "description": "Replace this example with an independently ready task."
    }
  ]
}
```

Use actual full Beads objects from the project's existing workflow, not invented
IDs or status changes. This command does not schedule or rank work: assign each
reviewed task to an explicit existing host and slot. Task status is based on the
supplied snapshot; preparation is not a fresh `br ready` check. The existing
sender still checks readiness at submission time.

Each selected host needs a confirmed launch result and at least one task.
Supply an explicit Agent Mail name for **every original slot**, including idle
slots. Names must be unique across the selected fleet, ignoring case; they are
operator input, not proof that registration occurred. A task can occupy slot 2
while slot 1 is idle. No assignment is fabricated to fill idle slots. Preparation
runs in original fleet order and native slot order, not mapping-file order.

One invocation represents one logical project even when remote checkout paths
differ. Duplicate task IDs and slots are refused. Write scopes are checked
across **all** assignments and hosts: exact collisions, literal directory
ancestors, and possibly overlapping glob prefixes are rejected. For example,
`src/**` conflicts with `src/api.rs`, and `src` conflicts with `src/api.rs`.
`src/api/**` and `src/docs/**` can be independent. Glob checks are conservative;
a rejected complex pattern is not proof that its languages actually intersect.

Scopes are declarations, not acquired locks or proof of independent database,
network or runtime side effects. Symlink aliases and undeclared writes are not
resolved by this policy. Review task dependencies and acquire Agent Mail
reservations through the normal agent workflow before editing. Do not use
separate preparation runs to evade coordination for overlapping work.

## Preview locally, then explicitly prepare remotely

Use the same independently verified SSH trust files as the original fleet.
Choose a new preparation journal under an existing user-owned directory that
is not writable by others. It must be outside the launch journal:

```bash
python3 -I scripts/swarm-fleet-prepare.py \
  --launch-state "$HOME/fleet-wave-1" \
  --work fleet-work.json \
  --known-hosts "$HOME/.ssh/known_hosts" \
  --identity-file "$HOME/.ssh/id_ed25519" \
  --state-dir "$HOME/fleet-preparation-wave-1"
```

Unlike the launch/dispatch controllers' remote previews, this default preview
is entirely local: no SSH connection, remote file, native process or controller
state is created. It shows the host/slot/name mapping and write scopes, with a
`plan_sha256`. Read the complete private work file too: task text is not echoed
into the summary. The digest binds the selected task briefs, scopes, identities,
original launch journal, transport trust, output paths, timeout and exact
first-party remote-helper policy. It is not a signature or a trust attestation.

After review, repeat with:

```text
--prepare --accept-plan THE_PREVIEW_PLAN_SHA256
```

Preparation opens SSH connections and sends the selected task metadata to its
assigned hosts. All selected hosts must first verify their original native
agents and an available output destination before the first persistent write.
Then hosts prepare sequentially, each rechecking its launch before and after
packet generation. A replaced process, adopted session, unavailable preparer or
wrong original launch blocks that host. Admission is not an atomic fleet-wide
resource lock.

The controller transports only each host's assigned task briefs and native
assignment document. Task text goes over stdin, not shell interpolation or
command arguments. A fixed first-party Python bridge runs through strict
host-key-verified SSH, reusing the fleet controller's anonymous trust snapshots
and restrictions on forwarding, proxy commands, SSH config and multiplexing.
It needs Python 3 and a non-root remote user. It uses an allowlisted environment
and fixed Bash/native arguments; no input field supplies an executable.

The native preparer receives `--assignments`, `--beads-file`, all explicit
`--identity` values and `--no-live-context`. It still owns packet construction,
repository instruction discovery, native target validation and random delivery
operation IDs. CM/CASS probes are not requested, and no new task-selection engine
or template copy is introduced. The remote repository's current instructions
remain an input: review the resulting packets before authorizing dispatch.

## What is created

Each remote output must be absent and have an existing user-owned parent that
is not writable by others. Paths are walked without following symlinks. The
new private directory contains:

```text
work-wave-1/
  request.json
  assignments.json
  beads.json
  complete.json               # Written only after validation succeeds
  bundle/
    assignments.json
    packet-01.json
    packet-01.md
    ...
    batch.json
```

Files are mode 0600; the stage and native bundle are mode 0700. No existing
output is replaced. The helper verifies the exact assignment bytes, expected
members, original slots/panes/providers, task and scope bindings, complete
Markdown/JSON pairs, unique operation IDs and bounded sizes before recording
completion. It does not treat a mere exit-zero process as a prepared bundle.
A local result records the artifact hashes and sizes, not the task or packet
text. Local private intent does contain the original selected task briefs and
connection/path metadata; it is not a redacted support bundle.

A successful fleet creates `batches.json` in the local preparation journal:

```bash
python3 -I scripts/swarm-fleet-dispatch.py \
  --launch-state "$HOME/fleet-wave-1" \
  --batches "$HOME/fleet-preparation-wave-1/batches.json" \
  --known-hosts "$HOME/.ssh/known_hosts" \
  --identity-file "$HOME/.ssh/id_ed25519" \
  --state-dir "$HOME/fleet-work-wave-1"
```

First read every remote `bundle/packet-*.md`. The command above is a separate
**dispatch preview**, not a send. Preparation approval cannot authorize model
work. Changed packets will be reflected in that workflow's own review digest.
No packet bytes are downloaded to the controller by the preparation command.

## Failure and limits

The controller fsyncs its intent and per-host attempt before each remote
preparation. Any uncertain result stops later hosts. Existing bundles and all
journals are retained; no cleanup, rollback, adoption, regeneration or automatic
retry occurs. An absent reply does not imply the remote preparer stopped. Keep
the original launch journal and preparation state, and inspect remote outputs.
Do not change output paths or delete evidence to force another operation.

The remote `complete.json` acceptance marker is written last, after its bundle
is validated. A stage without that marker is not accepted as complete. A crash
can leave partial JSON or bundle files. Those are retained, never rehashed into
success or replaced. Previously generated operation IDs must not be regenerated
as a way to recover a lost response.

Limits: 16 selected hosts, at most 32 original slots per host and 256 assignments;
32 scopes per task; 64 KiB per selected task brief; 1 MiB input/plan/response
bounds; 16 MiB native bundle bound. The usual fleet JSON complexity limits apply.
`--timeout` defaults to 360 seconds, range 1–600, per host SSH operation. Remote
native calls share that host's remaining deadline. Timeout/cancellation kills
the local SSH process group; it cannot prove remote process termination after
connection loss. The remote program also bounds its native children. Trusted
remote tools/host policy remain part of the boundary; this is not an OS sandbox.

Exit 0 means a valid local preview or fully prepared fleet. Exit 1 means blocked
preflight or uncertain preparation. Exit 2 means invalid input, stale approval
or local state failure. Signals return 128 plus the signal number. Reports never
claim task execution, live authentication, file reservations or model completion.

## Verification

```bash
python3 -B tests/unit/test_swarm_fleet_prepare.py -v
```

The suite exercises actual controller state, filesystem locking, literal input
transport, bounded subprocesses and a real unprivileged remote helper against a
native-protocol fixture. It checks cross-host task/scope conflicts, original
identity binding, idle slots, all-host preflight, immutable outputs, changed
artifacts and failure stops. It is not a real SSH, VPS, native NTM or live model
acceptance run. Original fleet helper bytes used locally and transmitted to the
peer are the same trusted checkout snapshot.
