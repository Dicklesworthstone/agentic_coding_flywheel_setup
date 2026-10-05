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
