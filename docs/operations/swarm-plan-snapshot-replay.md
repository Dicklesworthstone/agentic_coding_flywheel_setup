# Replay swarm admission from saved evidence

`acfs swarm plan` remains an advisory, read-only command. It does not launch
agents, claim Beads, send Agent Mail, change reservations, or run builds.

## Capture and replay

On the host being assessed, collect both reports for the same requested count
and workload:

```bash
acfs swarm status --json > swarm_status.json
acfs capacity --json --profile 10-agents --workload standard --recommend-ntm > capacity.json
```

Replay the saved evidence, including on a different machine:

```bash
acfs swarm plan --agents 10 --workload standard \
  --status-file swarm_status.json --capacity-file capacity.json --json
```

Supplying both files bypasses **both** live collectors. The JSON report records
both paths, `inputs.assessment_scope: "snapshot_replay"`, and
`inputs.replay_only: true`. Human output also identifies saved replay. This
reconstructs advice from the supplied evidence; it does not verify snapshot age,
host identity, or current readiness. Refresh both reports on the target host
before using a proposed launch command.

The capacity report's requested count and workload must match the invocation
when those fields are present. Capture a new capacity report to change either.
Older schema-1 capacity reports without this optional metadata remain readable.

`--status-file` alone retains the existing saved-status/live-capacity behavior,
now labeled `mixed_snapshot_and_live`. Verify that the sources describe the same
host and time. `--capacity-file` without `--status-file` is rejected rather than
silently mixing saved capacity with a live status probe.

## Admission decisions

A `quiesce_advisory.recommendation` of `wait` suppresses the recommended launch
count, command, label, and agent mix. This includes exhausted capacity or build
slots, high host pressure, stale work, missing host pressure measurements, and
incomplete or stale RCH queue/worker telemetry. Hard failures also block advice.
Busy RCH slots can reduce, but never increase, the host's recommended count.

Exit codes are:

- `0`: the supplied evidence supports the proposed launch size.
- `1`: warnings require review. Inspect the quiesce decision: **this is not
  permission to launch when the decision is `wait`**.
- `2`: a hard blocker, invalid invocation, or unusable input prevents planning.

These decisions do not make saved evidence current. A replay can report a
historical `pass` even when the target host has changed since capture.

## Input handling

Each input is bounded to 1 MiB, 32 levels of nesting, and 50,000 completed JSON
nodes. Reports must contain exactly one schema-1 JSON object. Duplicate decoded
keys, including scalar/container replacements, are rejected before ordinary JSON
parsing can discard an earlier failure or zero-capacity limit. Invalid numeric
counters, incorrectly typed probe flags, and unsupported shapes are rejected.
Missing pressure measurements remain unknown rather than becoming idle/healthy.

The planner passes reports to jq through standard input, avoiding operating-system
argument-size failures on larger support reports. Evaluation failures emit one
structured blocking JSON report, not partial output. Agent counts are normalized
as decimal and bounded to 1 through 1,000,000; leading zeroes never select octal.

Run the regression suite without real services:

```bash
bash tests/unit/test_swarm_plan_admission.sh
```

The tests exercise the actual Bash/jq CLI with isolated fixtures and prove that
paired replay does not invoke either live collector. They are not a substitute
for acceptance on a configured VPS with real Agent Mail, Beads, RCH, and NTM.
