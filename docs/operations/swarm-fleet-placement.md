# Place a target swarm across recorded host capacity

```bash
acfs swarm inventory plan --agents 50 --workload standard --json \
  --inventory ~/.acfs/swarm/hosts.inventory.json
```

The planner distributes a **target total**, not an additional number of agents
to launch. It reads the existing v1 inventory; it never connects to hosts,
launches NTM, claims Beads, sends Agent Mail, or changes RCH/RU configuration.
A successful placement is not proof that a host is currently ready.

## Placement policy

Only active controller, swarm-worker, or explicitly launch-enabled support
hosts qualify. `ntm.can_launch` must be the boolean `true`. A missing flag,
null, or `false` is not permission. Both capacity counts must be known, positive
integers. The per-host limit is the smaller of `recommended_agents` and
`safe_agents`; zero remains zero. Recommendations above a safe maximum are
capped, not promoted to a larger limit.

Each host needs a valid UTC `last_probe_at` (`YYYY-MM-DDTHH:MM:SSZ`) that is not
in the future and is younger than `defaults.stale_after_hours` (24 by default,
1-8760 supported). Missing, malformed, future-dated, and expired records are
excluded. Updating the inventory's `updated_at` does not refresh any probe.

The selected workload must match the host's recorded workload. A host-specific
workload overrides the inventory default; absent values use the existing
standard-workload default. Present workload values must be one of `light`,
`standard`, or `heavy`; invalid values are never silently defaulted.
The planner never converts a light-workload count
into capacity for heavy work.

Eligible hosts are sorted by descending recorded recommendation, then by ID.
The planner fills the largest first, minimizing the number of hosts required
for the target. Input ordering does not change placement. A shortfall stays
unassigned rather than exceeding a limit or admitting an excluded host.

## Read the result

JSON includes `allocations`, `assigned_agents`, `unassigned_agents`,
`fully_placed`, `recorded_capacity_total`, and `excluded_hosts` with reason
codes. `allocation_semantics` is `target_totals_not_additional_agents`.

For example, with eligible recorded limits of 20 and 10, a target of 25 becomes
20 on the first host and 5 on the second. A target of 40 assigns only 30 and
reports 10 unassigned, returning exit status 1. A complete placement returns 0;
invalid arguments or inventory return 2. A complete placement can still include
warnings about excluded hosts; those hosts contributed no capacity.

Every allocation includes a `live_admission_command`, such as:

```bash
acfs swarm plan --agents 20 --workload standard --json
```

Run that command **on the allocated host**, inspect existing sessions, and
review its live admission result before deciding whether or how many agents
to launch with NTM. Do not run every host's command on the controller and do
not interpret target totals as additional agents. Recorded inventory is not
live capacity, a reservation, or an authorization token.

Human output is available by omitting `--json`. `--agents` and `--workload` are
plan-only flags. Plan rejects `--input`, `--output`, and `--artifact-dir` to keep
this operation read-only, including on error. Supplying a second operation,
such as `plan import`, is rejected before any writes.

## Inventory input boundary

All inventory commands require Python 3 and jq. Before jq sees the document,
the reader validates its original bytes. Inputs must be regular, non-symlink
files containing one UTF-8 JSON value, at most 1 MiB (including whitespace),
with depth at most 32 and at most 50,000 values. Duplicate decoded object keys,
non-finite numbers, and invalid Unicode surrogate values are rejected.

Capacity counts are integers from 0 to 1,000,000, or null for unknown. Numeric
strings, booleans, negative numbers, and fractions are not coerced. Reports
retain excluded hosts with zero eligible counts and explanatory reason codes.
Existing sensitive-field rejection remains active. Unknown non-sensitive
fields are preserved during import/export. Large documents travel through
stdin rather than process arguments.

## Regression tests

```bash
python3 -B -m unittest discover -s tests/unit -p 'test_swarm_inventory_*.py' -v
bash tests/unit/test_swarm_inventory.sh
bash -n scripts/lib/swarm_inventory.sh
shellcheck scripts/lib/swarm_inventory.sh
```

The Python tests execute the actual Bash/jq entrypoint with filesystem fixtures.
They cover eligibility, contradictory limits, duplicate keys, bad timestamps,
large import/export, workload matching, stable ordering, bounded allocations,
shortfalls, and inert invalid options. They do not perform live fleet or NTM
acceptance testing.

## Populate and refresh records from the local machine

Run the probe **on the host whose record you are creating**, using an
operator-chosen inventory ID, not its real hostname or IP address:

```bash
acfs swarm inventory probe-local --host-id worker-a --workload standard \
  --disk-path /data/projects --allow-launch --output worker-a.inventory.json
```

This invokes the installed sibling `capacity.sh` with its real local resource
readers and selected workload. It projects CPU, RAM, disk headroom, recommended
and safe counts into the existing inventory schema and records a UTC observation
time. The default filesystem is the current user's home; `--disk-path` selects
an existing project filesystem without including that local path in the output.
No commands run over SSH; no model, NTM session, RU operation, Beads write, Mail
request, or RCH service request is made. Executable availability is not service
health, authentication, or a live queue admission check.

New records default to role `swarm-worker`, status `active`, and
`ntm.can_launch: false`. `--role` selects another inventory role for a new record;
`--allow-launch` explicitly enables the new record's recommendation hint only
when NTM is installed and the role permits agent launches. It does **not** start
agents. Omit it for a record that should remain excluded until separately reviewed.

To refresh one local host in an existing fleet snapshot:

```bash
acfs swarm inventory probe-local --host-id worker-a \
  --inventory hosts.inventory.json --disk-path /data/projects \
  --output hosts.refreshed.json
acfs swarm inventory plan --inventory hosts.refreshed.json \
  --agents 50 --workload standard --json
```

An explicit `--inventory` is a merge base, never an implicit write destination.
Other hosts retain their exact records, including their original probe times.
Existing role, status, notes, tags, RCH/RU settings, and unrelated metadata are
preserved. Existing workload is retained unless `--workload` explicitly changes
it; new records use the inventory default. An old launch veto stays false.
Missing NTM withdraws an existing positive hint. `--role` and `--allow-launch`
are rejected for existing records: changing operator policy needs a separate
review, not a side effect of measurement. Refreshing a host never re-enables a
disabled host or repurposes a build-only worker.

With no `--output`, the result is JSON on stdout and no file is created. No
canonical inventory is read unless `--inventory` is explicit; the environment
variable `ACFS_SWARM_INVENTORY_FILE` does not silently select a merge base.
With `--output`, the parent must already exist and a complete private (0600)
snapshot is atomically created. Existing files, symlinks, directories, and even
a destination created during measurement are never replaced. Use a new filename,
review the diff against the original, then use the existing explicit `import`
command to adopt that complete snapshot. A snapshot is not an in-place fleet
transaction: concurrent edits to the original must be reconciled before import.

The producer has a ten-second deadline, a 64 KiB response limit, strict JSON and
capacity schema checks, and no inherited capacity test overrides, bearer tokens,
proxy variables, or shell startup configuration. A failed or malformed producer
never refreshes a timestamp or publishes a snapshot. Only approved numeric and
boolean observations are projected; raw diagnostics and local paths are omitted.
The final snapshot passes the same sensitive-field and size validation as other
inventory input. Import/export does not turn saved evidence into a fresh probe.

Focused probe coverage runs with:

```bash
python3 -B tests/unit/test_swarm_inventory_probe.py
```

Those tests execute the actual inventory shell with a sibling calculator
contract fixture. The regression workflow separately runs the actual installed
calculator on its Linux runner, validates and plans from its snapshot, and
checks that refreshing one record leaves an unrelated host unchanged. Neither
proves that a remote fleet is currently ready for an agent launch.
