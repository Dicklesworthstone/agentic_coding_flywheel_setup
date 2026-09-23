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
