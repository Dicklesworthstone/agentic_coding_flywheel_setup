# Observe a launched fleet without sending more work

`scripts/swarm-fleet-status.py` joins three separate observations for the original
fleet: native agent liveness, historical prompt submission, and the exported
state of the specific Beads assigned by a dispatch journal. It never launches,
sends, resumes, repairs receipts, closes Beads, or runs provider model requests.

From a trusted complete checkout on a Linux controller:

```bash
python3 -I scripts/swarm-fleet-status.py \
  --launch-state "$HOME/fleet-wave-1" \
  --dispatch-state "$HOME/fleet-work-wave-1" \
  --known-hosts "$HOME/.ssh/known_hosts" \
  --identity-file "$HOME/.ssh/id_ed25519"
```

Omit `--dispatch-state` to inspect only the original launched agents. The command
reads the original host selection from the launch journal; a new spec, batch
mapping, or arbitrary host override is not accepted. Use the original SSH trust
inputs and the runtime that understands those journals. Rotated keys require
operator review, not rewriting an old journal's approval or identity hashes.

## Read each kind of evidence separately

**Agents:** `live` means the native launch reconciler currently confirms the
original session/panes/process identities. Replaced targets or adopted sessions
cannot become the original launch. `unconfirmed` covers dead agents, unavailable
hosts, absent remote evidence, or failed validation; it does not prove the host
has no agents. `verified_live_agents: 0` is zero confirmed, not a process census.
Untouched launch hosts remain `not_attempted` and are not contacted.

**Deliveries:** `submitted` comes from querying each attempted delivery's exact
native intent and NTM operation receipt. A local success file is not used as a
substitute. Historical submission can still be confirmed after the original
agents have exited. An interrupted host batch is inspected delivery by delivery,
but missing receipts remain `unconfirmed`; no packet is resent. Untouched batches
remain `not_attempted` and their work exports are not queried.

**Work:** the fixed remote Python observer reads only `.beads/issues.jsonl` under
the recorded repository and projects only the assigned IDs and their status.
No task descriptions, titles, prompts, account data, or unrelated Beads are
returned. It does not open the live Beads database or run `br` (including its
possible auto-import/export behavior). A missing assigned ID is `missing`, never
implicitly closed. Unknown future status values become `unknown`.

An export is `recent` when its filesystem modification age is at most
`--export-max-age` seconds (default 300, allowed 1..86400); otherwise it is `stale`.
The age is measured on the remote host. **Recent mtime does not prove that the
export agrees with the live database**, and a quiet repository may have a stale
but otherwise accurate export. Both recent and stale reads include the export's
hash, byte/record count, and age. Stale states remain visible but do not contribute
to `recent_export_states`; their selected items count as `unobserved_work_items`.
Export clocks more than five seconds into the future are refused.

A Bead marked `closed` is a recorded workflow state, not an independently checked
implementation, test result, accepted artifact, or proof that this particular
agent completed it. `task_completion_verified` is always false. Neither successful
submission nor agent liveness makes it true. The observer performs no automatic
retry, reassignment, reservation, stop, or queue mutation.

## Output and failure handling

Output is one JSON document, schema `acfs.swarm-fleet-status.v1`, with per-host
agent, delivery, and work evidence, separate summary counters, and observation
start/finish timestamps. Hosts retain the original fleet order. It is a sequence
of observations, not an atomic fleet-wide snapshot.

Exit **0** (`observed`) means all original requested agents were confirmed live,
all selected deliveries were confirmed submitted, and all selected exports were
recent without missing/unknown/blocked/deferred/tombstoned assigned work. Open or
in-progress work can return 0: it means observation succeeded, not work completed.
Exit **1** (`attention`) means at least one of those conditions is not established,
including untouched hosts/batches. Other hosts are still inspected when possible.
Exit **2** is a local input, journal, lock, or execution error. Signals return
128 plus their signal number. No traceback or raw SSH error body is exported.

`--timeout` bounds each SSH call (default 10, allowed 1..600 seconds).
`--deadline` bounds the total remote-call budget for the sample (default 120,
allowed 1..3600 seconds), so many unavailable hosts cannot multiply the wait
without limit. Remaining observations after budget exhaustion are unconfirmed;
there is no second connection attempt or permissive SSH fallback. This budget
excludes local journal validation and bounded child cleanup. Polling/scheduling
is left to the operator; the command performs one sample and exits.

Local journals remain unchanged and are locked against cooperating launch/send/
resume controllers while observed. Concurrent journal replacement or mutation
invalidates the observation. Remote exports reject symlinks, special files,
multiple hard links, other-owner files, writable-by-others paths, malformed JSON,
duplicate keys/IDs, and changes detected while reading. Export limits are 16 MiB
total, 1 MiB per line, 100,000 lines, and bounded JSON depth. The trust model still
includes the SSH host and installed native tools; these checks are not a sandbox
against a malicious same-user process. Transient local SSH trust snapshots use
the existing fleet transport; no persistent status file is written automatically.

## Validation

```bash
python3 -B tests/unit/test_swarm_fleet_status.py -v
```

The suite constructs launch and dispatch journals through the existing production
controllers with protocol fixtures, then exercises the observer and its original
journal/receipt validators. The fixed remote export reader also runs as a real
unprivileged Python process through literal shell argument transport against real
files. These tests do not replace live OpenSSH/VPS/NTM/provider acceptance.
