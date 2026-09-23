# Prepare a scoped swarm handoff

`acfs swarm packet --prepare-batch` turns explicit scoped assignments into a
private directory of complete per-agent work packets and a delivery manifest.
It removes the manual packet/manifest assembly between `swarm assign` and
`swarm packet --deliver-batch`. It does not spawn agents or send prompts.

Generate an assignment report from the intended write scopes:

```bash
umask 077
set -o noclobber
acfs swarm assign --roles implementation,documentation \
  --scopes-file scopes.json --json > assignments.json
```

Read the assigned slots and bind each one to an existing native Claude or Codex
pane. Use the actual registered Agent Mail identities, not the example names:

```bash
acfs swarm packet --prepare-batch ./handoff \
  --assignments assignments.json --repo "$PWD" --session myproject \
  --target '1:RedFox:claude:%42' --target '2:BlueLake:codex:%43'
```

Each target is `SLOT:AGENT_NAME:AGENT_TYPE:STABLE_PANE_ID`. Provide exactly one
for every **assigned** slot, excluding idle slots. Argument order does not matter;
a slot is never reassigned to another pane merely because another slot is idle.
Panes, slots and agent identities must be distinct. Scope-aware assignments are
required; inferred paths and overlapping declared write sets are refused.

By default preparation reads each selected task with `br show ID --json` and
uses the existing packet generator's bounded CM/CASS context lookups. Supply
`--beads-file full-beads.json --no-live-context` for file-only preparation with
no br, CM or CASS calls. Beads input can be an object or array of full objects;
missing, duplicate, closed, blocked or undecomposed epic tasks prevent publication.
Saved assignments do not attest repository identity: `--repo` is an explicit
operator choice, and saved task data is not proof of current readiness.

The bundle includes `assignments.json`, `packet-NN.json`, `packet-NN.md`, and
`batch.json`. Prompts now include the task description, design and acceptance
criteria, together with the declared write scopes and an instruction not to
expand those scopes silently. Large or truncated task packets block preparation
rather than silently losing acceptance criteria. Ordinary single-packet generation
also includes task briefs and can select a specific ID from a multi-Bead file.

Review every Markdown prompt, then run the returned `preview_command`:

```bash
acfs swarm packet --deliver-batch ./handoff/batch.json
```

That separate preview returns the hash-bound send command. Submission may start
paid model work and project edits. Delivery performs its existing live pane and
ready-queue checks. See [delivery and recovery](swarm-packet-delivery.md).

## Publication and recovery

The directory must not already exist; its parent must already exist without
symlink components. Preparation validates all tasks and generated packets before
publishing. It creates a mode-0700 directory and mode-0600 files, writing
`batch.json` last. Existing files are not overwritten. An interrupted publication
can leave an incomplete directory; preserve and inspect it rather than deleting
user work. Without a completed manifest, no batch is ready for delivery.

Operation IDs are generated once into the manifest. After sending, keep that
same manifest, packets and receipts for reconciliation. Regenerating a bundle
creates new operations and is **not** a delivery retry.

Declared scope independence is not a reservation. Preparation does not inspect
live Agent Mail reservations, claim Beads, verify account authentication or
establish host capacity. Agents still need to coordinate before editing.

Packet JSON retains source task data and can contain private project information;
it is not a redacted support export. Markdown uses the existing best-effort
context sanitizer, not a guarantee that arbitrary secrets have been removed.
Do not publish handoff directories.

## Tests

```bash
python3 -B tests/unit/test_swarm_packet_preparation.py
```

Tests execute the actual Bash/Python preparation and packet generator, then the
actual batch delivery/reconciliation entrypoint against NTM/tmux/br contract
fixtures. No installed providers or paid model sessions are exercised.
