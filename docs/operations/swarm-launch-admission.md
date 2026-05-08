# Swarm Launch Admission Model

This note records the `bd-h8c2m` contract for a future queue-aware
`acfs swarm plan` advisor. It is design guidance only; ACFS does not
currently launch agents from this model.

## Purpose

Large ACFS hosts can run many agents, but launch decisions should still account
for local capacity, RCH queue pressure, existing NTM/tmux activity, active
Beads work, Agent Mail reservation pressure, and stale coordination state. The
admission model answers one question:

> Is it reasonable to start the requested number of agents now, and if not,
> what should the operator inspect before launching?

The model must be deterministic, read-only, and safe to run before every swarm.
It can return `pass`, `warn`, or `fail`, but it must never spawn agents, mutate
Beads, send Agent Mail, force-release reservations, or clean files.

## Source Of Truth

Current repository instructions remain authoritative:

- Read the repo-local `AGENTS.md` and `README.md` first.
- Treat current Beads, Agent Mail reservations, and the live working tree as
  fresher than old memories or old session summaries.
- If memory, CASS, or CM guidance conflicts with current repo docs or task
  instructions, the current docs and user instructions win.

The admission output can include advisory links to memory or CASS refresh
commands, but stale memories must never be used to override current repo rules.

## Inputs

The future planner should accept:

| Input | Required | Source |
| --- | --- | --- |
| `requested_agents` | yes | CLI flag such as `--agents 25` or profile name such as `25-agents` |
| `workload` | yes | `light`, `standard`, or `heavy`; same vocabulary as `capacity.sh` |
| `swarm_status` | yes | `acfs swarm status --json` or `scripts/lib/swarm_status.sh --json` |
| `capacity` | yes | `acfs capacity --json --profile <N> --recommend-ntm` |
| `simulation` | recommended | `acfs swarm simulate --json --counts 10,25,50` or selected counts |
| `agent_mail_pressure` | optional | future reservation summary, degraded to warning when unavailable |
| `repo_policy` | advisory | local `AGENTS.md` and README presence/read freshness |

All tool probes must use existing timeout wrappers or bounded fixture input.
No local CPU-heavy cargo examples should appear in examples; use RCH policy
language for build/test work.

## Admission Status

The top-level status is the maximum severity of all checks:

- `pass`: requested launch is within the recommended envelope and required
  coordination probes are healthy.
- `warn`: launch may be reasonable, but the operator should review pressure or
  degraded probes first.
- `fail`: requested launch exceeds hard safety limits or required coordination
  data is unavailable.

Recommended exit codes:

| Status | Exit Code | Meaning |
| --- | ---: | --- |
| `pass` | 0 | Launch is reasonable. |
| `warn` | 1 | Review warnings before launching. |
| `fail` | 2 | Do not launch at this size. |

## JSON Contract

The planner should emit one JSON object:

```json
{
  "schema_version": 1,
  "generated_at": "2026-05-08T00:00:00Z",
  "status": "warn",
  "exit_code": 1,
  "requested_agents": 25,
  "recommended_agents": 18,
  "safe_agents": 32,
  "workload": "standard",
  "recommendation": "defer_or_reduce",
  "recommended_action": "Reduce to 18 agents or wait for RCH pressure to clear",
  "inputs": {
    "swarm_status_file": null,
    "capacity_file": null,
    "simulation_file": null
  },
  "checks": [],
  "examples": []
}
```

Required top-level fields:

| Field | Type | Notes |
| --- | --- | --- |
| `schema_version` | number | Start at `1`; bump on breaking schema changes. |
| `generated_at` | string | UTC ISO-8601 timestamp. |
| `status` | string | `pass`, `warn`, or `fail`. |
| `exit_code` | number | `0`, `1`, or `2`. |
| `requested_agents` | number | Operator-requested launch size. |
| `recommended_agents` | number or null | Conservative count after all checks. |
| `safe_agents` | number or null | Hard upper bound from capacity and pressure. |
| `workload` | string | `light`, `standard`, or `heavy`. |
| `recommendation` | string | `launch`, `launch_with_review`, `defer_or_reduce`, or `block`. |
| `recommended_action` | string | Human-readable next step. |
| `checks` | array | Deterministic check objects, documented below. |
| `examples` | array | Plans for 10, 25, and 50 agents. |

## Check Objects

Each check object should use this shape:

```json
{
  "id": "rch_pressure",
  "status": "warn",
  "summary": "RCH has queue or worker pressure",
  "details": {
    "queue_depth": 4,
    "active_build_count": 2,
    "workers_total": 7,
    "workers_healthy": 7,
    "workers_busy": 2,
    "workers_offline": 0,
    "slots_total": 82,
    "slots_available": 64,
    "pressure_warning_count": 2,
    "stale_worker_count": 0
  },
  "next_commands": ["acfs swarm status --json", "rch status --json", "rch queue --json"]
}
```

Required checks:

| Check | Pass | Warn | Fail |
| --- | --- | --- | --- |
| `host_capacity` | Requested count is at or below capacity recommendation. | Requested count is above recommendation but at or below safe count. | Requested count is above safe count or safe count is zero. |
| `rch_pressure` | RCH unavailable only when workload is light, or queue/worker pressure is clear. | RCH has a queue, busy workers, stale telemetry, or pressure warnings but enough slots remain. | RCH is required for the workload and unavailable, invalid, or has no available slots. |
| `coordination_health` | Agent Mail, Beads, and bv probes are healthy. | Optional coordination probes degrade but Beads and bv remain usable. | Beads or bv JSON commands are unavailable for swarm planning. |
| `active_work` | No in-progress Beads and no stale reservations reported. | In-progress Beads exist or stale reservations are suspected. | A requested launch would overlap active exclusive reservations without operator review. |
| `ntm_tmux` | NTM robot status is healthy and tmux has expected capacity. | NTM is degraded but tmux is usable. | NTM and tmux are unavailable for the intended launch path. |
| `policy_freshness` | Local `AGENTS.md`/README have been read in the current session. | Freshness is unknown. | Never fail solely on this check; emit a warning instead. |

## Thresholds

The first implementation should use conservative thresholds:

- `safe_agents` starts from `capacity.capacity.safe_agent_count`.
- `recommended_agents` starts from `capacity.capacity.recommended_agent_count`.
- If `probes.rch.queue_depth > 0`, cap `recommended_agents` to the smaller of
  the capacity recommendation and available RCH slots.
- If `probes.rch.pressure_warning_count > 0`, return at least `warn`.
- If `probes.rch.stale_worker_count > 0`, return at least `warn`.
- If `probes.rch.slots_available == 0` and workload is `standard` or `heavy`,
  return `fail`.
- If `probes.beads.in_progress_count > 0`, return at least `warn` and include
  `br list --status in_progress --json` as a next command.
- If Agent Mail reservation pressure is unavailable, return `warn`, not `fail`,
  unless Beads or bv are also unavailable.
- If requested agents exceed `safe_agents`, return `fail`.
- If requested agents exceed `recommended_agents` but not `safe_agents`, return
  `warn`.

The model should prefer aggregate counts over raw worker names, hostnames, file
paths, or command strings. Support-bundle output should redact any optional
detail fields that could expose secrets, private hosts, or local project paths.

## Human Output

Human output should fit in one terminal screen:

```text
ACFS Swarm Plan
Status: warn
Requested: 25 agents (standard)
Recommended: 18 agents
Safe maximum: 32 agents
RCH: queue=4 active=2 workers=7/7 busy=2 slots=64/82 pressure=2 stale=0
Beads: ready=12 in_progress=1
NTM/tmux: sessions=2 windows=8
Recommendation: Reduce to 18 agents or wait for RCH pressure to clear

Warnings:
  - RCH has queued work and elevated worker pressure.
  - There is active in-progress Beads work; inspect before launching more agents.

Next commands:
  br list --status in_progress --json
  acfs swarm status --json
  acfs swarm simulate --counts 10,25,50
```

## Example Plans

These examples assume `standard` workload, 32 safe agents from capacity, 18
recommended agents after RCH pressure, healthy Beads/bv, and one active Bead.

| Requested | Status | Recommendation | Reason |
| ---: | --- | --- | --- |
| 10 | `warn` | `launch_with_review` | Count is below recommendation, but active work exists. |
| 25 | `warn` | `defer_or_reduce` | Count exceeds pressure-adjusted recommendation but remains below safe maximum. |
| 50 | `fail` | `block` | Count exceeds safe maximum. |

The JSON `examples` array should include the same scenarios:

```json
[
  {"requested_agents": 10, "status": "warn", "recommendation": "launch_with_review"},
  {"requested_agents": 25, "status": "warn", "recommendation": "defer_or_reduce"},
  {"requested_agents": 50, "status": "fail", "recommendation": "block"}
]
```

## Non-Goals

- No automatic agent spawning.
- No Beads claiming, closing, or priority changes.
- No Agent Mail sends or force-release operations.
- No destructive cleanup, reset, checkout, or generated-file edits.
- No local CPU-heavy cargo examples. Build/test examples should preserve the
  RCH policy, for example `rch exec -- cargo test`.
- No memory-derived override of local `AGENTS.md`, README, Beads, or user
  instructions.

## Test Plan

The implementation Bead should add fixture-driven tests before exposing the
advisor in normal workflows:

- Fixture status files for healthy, warned, failed, missing RCH, malformed RCH,
  stale worker telemetry, active Beads, and missing Agent Mail data.
- Golden JSON outputs for 10, 25, and 50 requested agents.
- Golden human output for `pass`, `warn`, and `fail`.
- Tests proving the command is read-only: no Beads mutation, no Agent Mail send,
  no file deletion, no agent launch, no RCH build execution.
- Tests proving timeout or malformed optional probes degrade to warnings unless
  a required planning dependency is unavailable.
- Redaction tests proving hostnames, command strings, file paths, and secrets do
  not appear in support-bundle or human output unless explicitly requested.

## Implementation Notes

Start with a pure planner that accepts explicit JSON fixture paths. Wire live
collection only after the fixture path is stable. The planner should be easy to
call from `acfs swarm doctor`, `acfs swarm simulate`, and support bundles, but
those integrations should remain separate follow-up Beads.
