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

After an explicit [fleet runtime installation or upgrade](fleet-runtime.md), the
same command is available without retaining the checkout:

```bash
acfs-fleet status \
  --launch-state "$HOME/fleet-wave-1" \
  --dispatch-state "$HOME/fleet-work-wave-1" \
  --known-hosts "$HOME/.ssh/known_hosts" \
  --identity-file "$HOME/.ssh/id_ed25519"
```

Use `acfs-fleet runtimes` to see which retained versions provide `status`. Legacy
four-file runtimes remain available for their original recovery workflows but do
not provide this observer; selecting their `status` command never falls back to
new code.

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

The CLI observes up to four hosts concurrently by default. Set `--workers 1`
for serial observation or choose another limit from 1 through 16. All workers
share the same sample deadline; a stalled host does not serially consume the
budget before its concurrently scheduled peers can be inspected. A sufficiently
small budget can still leave queued hosts unconfirmed. Each host's receipt and
work queries remain ordered, and output always follows the original fleet order,
not response order. `observation_workers` reports the effective host limit.

Both journal locks remain held until all workers finish. Journal validation is
serialized around remote calls, and any detected local mutation invalidates the
whole sample even if another process subsequently restores the bytes. Signals
and invalidation cancel outstanding local SSH process groups and queued probes
before releasing those locks. Cancellation never kills remote agents, retries a
send, or turns an incomplete observation into a successful one.

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
excludes local journal validation and bounded child cleanup. Without `--watch`,
the command performs one sample and exits.

Local journals remain unchanged and are locked against cooperating launch/send/
resume controllers while observed. Concurrent journal replacement or mutation
invalidates the observation. Remote exports reject symlinks, special files,
multiple hard links, other-owner files, writable-by-others paths, malformed JSON,
duplicate keys/IDs, and changes detected while reading. Export limits are 16 MiB
total, 1 MiB per line, 100,000 lines, and bounded JSON depth. The trust model still
includes the SSH host and installed native tools; these checks are not a sandbox
against a malicious same-user process. Transient local SSH trust snapshots use
the existing fleet transport; no persistent status file is written automatically.

## Watch evidence changes over a bounded interval

Append `--watch 300 --interval 10` to the same command to observe for five minutes,
waiting ten seconds after each completed sample. `--watch` requires an explicit
duration from 1 through 86400 seconds. The interval defaults to five seconds and
accepts 1 through 3600. There are no overlapping samples or catch-up bursts, and
both journal locks are released before every delay so a cooperating controller
can make legitimate progress. Each sample retains its independent journal checks.

Watch output is **JSON Lines**, one complete, flushed status document per line.
Each includes `watch.sample`, `watch.attention_seen` and `watch.changes`. Changes
distinguish agent liveness, delivery evidence, export availability and individual
Bead states. The first sample has no changes. Ticking ages alone do not generate
changes; crossing the staleness threshold does. A stale or unavailable export
makes its current Bead states `unobserved` rather than carrying forward a cached
`closed` state. Every full report still includes its ordinary evidence counters.

All samples share one monotonic watch deadline. Their individual `--deadline`
and `--timeout` budgets are shortened to the remaining watch time. Local
validation and child cleanup can extend wall-clock completion; no new remote
budget is granted after the watch deadline. SSH trust bytes are retained from
the start, and each sample re-queries evidence instead of reusing a prior success.

Journal directories are pinned when watch starts, before the first lock attempt.
Their descriptors stay open without holding a lock, so even an initially busy
journal cannot be silently replaced before the first observation. Original plan
digests and intent bytes are bound on the first validated sample. Every observed
attempt/result file is also bound by its exact byte hash. Later samples permit
only validated additions: a removed receipt, rewritten result, or coherent
rollback to an earlier journal prefix stops observation before new remote calls.
Newly appended receipts become immutable for subsequent samples too.

Legitimate append-only launch or dispatch recovery can proceed between samples.
The watch does not resume anything itself, reconstruct receipts, approve another
operation, or resend work. Replacing a directory, changing the original plan,
malformed state, unsafe paths, and incompatible source evidence remain fatal.

### Watching while another controller holds a journal lock

In watch mode only, cooperative lock contention emits a `busy` JSON line with
`code: "fleet_operation_in_progress"`, `hosts: []`, and `summary: null`. This is
an **observation gap**, not a claim that the fleet has zero agents, that previous
submissions remain verified, or that recovery has succeeded. No remote probes
are started for that sample, no locked journal is read without its lock, and no
previous host states or counters are copied into the busy line.

The ordinary finite watch deadline and interval still apply. The next tick tries
the journal locks again; after acquisition, all source, append-only-history and
remote-evidence checks run anew. This also supports starting a watch while an
existing journal is already busy. A corrupt journal is not retried as contention.
Single-sample status retains its existing behavior: a busy journal returns a
local error rather than waiting.

`watch.observation_skipped` distinguishes a busy tick from an actual observation.
`watch.previous_observation_sample` identifies the last non-busy sample, and
`watch.skipped_samples_since_previous_observation` reports the intervening gap.
Busy lines have no changes. The next observed sample compares against the last
actual observation and explicitly reports how many ticks were skipped; it does
not imply continuous visibility or synthesize transitions during that gap.

Normal watch completion returns **1 if any sample needed attention or was busy**,
even when the final sample is healthy, and 0 otherwise. A watch that spends its
entire budget waiting on locks returns 1 with no observed host counters. Local errors return 2; signals keep
their 128-plus-signal exit codes. Errors after argument parsing use the same
single-line JSON format in watch mode. A closed downstream pipe stops output
without a traceback. A healthy watch still does not certify completed work or
authenticated model readiness, and it never changes the fleet.

## Validation

```bash
python3 -B tests/unit/test_swarm_fleet_status.py -v
python3 -B tests/unit/test_swarm_fleet_status_parallel.py -v
python3 -B tests/unit/test_swarm_fleet_status_watch.py -v
```

The suite constructs launch and dispatch journals through the existing production
controllers with protocol fixtures, then exercises the observer and its original
journal/receipt validators. The fixed remote export reader also runs as a real
unprivileged Python process through literal shell argument transport against real
files. Recovery-watch tests run the actual cooperating dispatch-resume controller
against those journals while a watch is active; only the remote protocol peer is
substituted. They verify that the resumed controller sends only to the untouched
host, the observer never sends, and removed or rewritten history cannot be adopted.
These tests do not replace live OpenSSH/VPS/NTM/provider acceptance.
