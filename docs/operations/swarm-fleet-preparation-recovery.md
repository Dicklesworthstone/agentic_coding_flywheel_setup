# Fleet preparation: dependency admission and recovery

Before packet preparation, selected tasks must form an independent work wave.
The controller now checks the `dependencies` edges in the supplied work spec,
not just its optimistic `status: "open"` and `blocked_by: []` fields. Include the
entire blocking dependency closure in the spec's `beads` array. Unrelated issues
can be omitted. Prerequisites can appear only as supporting records, not as
concurrent selected tasks, and must be closed.

Direct and transitive unfinished prerequisites, missing blocking nodes, cycles
and malformed dependency records stop planning before SSH or filesystem writes.
Non-blocking relations do not become scheduling dependencies. A closed prerequisite
with an unfinished transitive prerequisite remains contradictory evidence and is
refused. Existing duplicate-task, original-slot and cross-host scope gates remain.

This validates the supplied snapshot, not the live queue or a reservation. Missing
or deliberately omitted edge metadata cannot prove graph completeness. The
native dispatcher and working agents still own live task/lease checks.

```bash
python3 -B tests/unit/test_swarm_fleet_prepare_dependencies.py -v
```

## Inspect an interrupted preparation without changing it

Run the existing controller with the same original work spec, launch journal,
SSH trust, timeout and preparation state directory, replacing `--prepare` and
its approval with `--reconcile`:

```bash
python3 -I scripts/swarm-fleet-prepare.py \
  --launch-state "$HOME/fleet-wave-1" \
  --work fleet-work.json \
  --known-hosts "$HOME/.ssh/known_hosts" \
  --identity-file "$HOME/.ssh/id_ed25519" \
  --state-dir "$HOME/fleet-preparation-wave-1" \
  --reconcile
```

This opens SSH only to hosts with durable local attempts. It invokes the existing
fixed peer's **inspect** operation, never native preparation. That operation
checks the private request, assignments, selected briefs, completion marker,
packet JSON/Markdown pairs, scope/target bindings, operation identities and hashes.
The original agents need not remain alive. It is historical bundle verification,
not permission to dispatch to a dead or replaced agent.

Reconciliation writes no local or remote preparation files. It checks every
attempted host, even when another is unconfirmed. Untouched hosts are not
contacted. A previous local success cannot hide missing or changed remote
completion evidence. Existing local results must exactly match freshly inspected
remote results. Missing, malformed or contradictory evidence stays unconfirmed;
no inspection failure can turn into a preparation retry.

Exit 0 and `status: "prepared"` mean all selected bundles were confirmed. A
healthy partial wave returns `partial`/exit 1; unknown evidence returns
`unconfirmed`/exit 1. `mapping_published` separately reports whether the local
`batches.json` acceptance marker exists. Reconciliation does not publish that
marker when a prior process died before creating it.

## Continue only untouched hosts

After inspecting the result, use `--resume --accept-plan ORIGINAL_DIGEST` instead
of `--reconcile`. Resume requires the original plan approval, not a newly edited
or rehashed journal. It first inspects **all** attempted hosts. Only when each is
confirmed can it restore a missing local result from the exact remote completion
record. It never overwrites a result or regenerates a prior host's packet bundle.

Resume then runs fresh checks for **all untouched hosts** before preparing any
of them. Each new preparation still gets its own fsynced, create-only local
attempt first. A new uncertain result stops the wave; the next resume inspects
that attempt rather than repeating it. Once all hosts are confirmed, a missing
`batches.json` is published. An already-complete resume only inspects: no files
are changed and no native preparer runs.

A controller killed after remote publication but before receiving its reply can
therefore recover the original packet hashes and operation IDs, then continue
the untouched hosts. A remote folder without the original complete marker is
not sufficient. Even an absent remote directory cannot prove that an earlier
request never ran. Such attempts remain unconfirmed and require separate
inspection, never an automatic delete, adoption or retry.

The local journal must be a coherent prefix of the original host order. Truncated
JSON, unexpected files, results without attempts, missing earlier results before
later attempts, unsafe permissions and a prematurely published batch mapping are
refused **before SSH**. Both the original launch journal and preparation directory
remain locked and their identities/membership/bytes are checked around remote
calls. Moving a receipt cannot authorize regeneration.

`--prepare`, `--resume` and `--reconcile` are mutually exclusive. Preparation and
resume require `--accept-plan`; reconciliation rejects it. Usage, approval and
local state errors return 2. Signal handling retains the existing 128-plus-signal
exit and attempted-operation disclosure. No recovery operation launches agents,
sends work prompts, modifies Beads, acquires reservations or bypasses the later
reviewed fleet-dispatch step. Keep the same trusted checkout and unchanged inputs
for recovery; a changed policy or source journal is not silently adopted.

```bash
python3 -B tests/unit/test_swarm_fleet_prepare_resume.py -v
```

The recovery suite uses actual private launch/preparation journals and full
native-format packet bundles. It kills a controller child with SIGKILL after the
remote fixture has published its completion, then verifies inspection and
continuation without regeneration. The unchanged fixed peer also runs as an
unprivileged process against real bundle files with no installed native launcher
or live agents. Transport replies for new native generation remain protocol
fixtures; these tests do not establish real SSH/VPS/NTM/provider acceptance.
