# Contention-aware swarm assignments

`acfs swarm assign` suggests work without claiming Beads, sending messages,
reserving files or launching agents. Role matching alone does not make tasks
independent. Use an explicit scope map to allocate a non-overlapping work set:

```sh
acfs swarm assign --roles implementation:2,review,testing \
  --scopes-file scopes.json --json
```

For offline replay, also supply `--ready-file ready.json` and
`--triage-file triage.json`; an empty `{}` triage file explicitly selects no
triage enrichment. Otherwise the only probes are `br ready --json` and, when
installed, `bv --robot-triage`.

## Declare the intended writes

A scope file has exactly this versioned shape:

```json
{
  "schema_version": 1,
  "scopes": {
    "bd-api": ["src/api/**", "tests/api/**"],
    "bd-client": ["src/client/**", "tests/client/**"],
    "bd-api-review": ["src/api/**"]
  }
}
```

Paths are relative to the same project root. List every intended write surface,
including generated outputs or shared metadata when the task will change them.
A literal denotes an exact file; use `directory/**` for a subtree. Do not use an
absolute path, `..`, empty path component, backslash, bracket/brace expansion,
or shell expression. The supported glob characters are `*`, `**`, and `?`.
Every listed scope is treated as exclusive, including review/testing roles:
those roles may edit code, and the planner does not assume they are read-only.

Beads without a declared scope are deferred with `missing-scope`, not assigned
using guessed paths. Epics are deferred with `decompose-first`; declare scopes
for their bounded child tasks instead. Already claimed, non-open and blocked
Beads are excluded. A dependency block reported by either ready input or triage
is respected.

## Allocation and explanations

The existing role fit, priority, triage score, estimate and ID tie-breaking
order is retained. For each slot, the allocator chooses the highest-ranked
candidate compatible with assignments already selected. It can therefore skip
a conflicting high-ranked task and assign a lower-ranked independent task. If
none fits, the slot is idle with `no-independent-ready-bead`. This is a greedy
advisor, not a maximum-cardinality or globally optimal scheduler.

`unassigned_ready_beads[].admission` explains `missing-scope`,
`decompose-first`, `scope-conflict`, or `eligible` (no slot remained). Conflicts
include `blocking_beads`. Both Markdown and JSON disclose the admission mode.

Glob intersections are conservative: incompatible literal prefixes prove
independence; compatible prefixes are treated as a possible collision. Thus
`src/a.py` and `src/b.py` are disjoint, but `src/*.py` and `src/*.ts` may be
serialized. Narrow a declaration only when that accurately describes the work.
Never shrink a scope merely to obtain more assignments.

Without `--scopes-file`, the original label-derived suggestions remain
available, marked `inferred-unchecked`; they are not parallel admission. With
explicit scopes, the planner only establishes non-overlap among **declared**
write sets. It neither verifies the agent's eventual writes nor checks live
Agent Mail reservations. Acquire actual reservations and recheck Beads before
editing. `scope_admission.launch_authorized` is always false.

A well-formed advisory report exits 0 even when slots remain idle; inspect
`scope_admission.status`, assignments and deferred reasons. Input failures exit
2 and publish no assignments. No commands are emitted for automated claiming.

## Input and execution bounds

Python 3 validates original JSON bytes before jq scheduling. Each input is
limited to 1 MiB, depth 32, 50,000 nodes and 2,048 issue/scope entries; each scope
has 1–32 unique paths of at most 256 characters. Inputs reject duplicate JSON
fields/issue IDs, non-finite numbers, invalid blocked flags and malformed
arrays rather than silently widening eligible work. Symlink and special-file
inputs are rejected. The planner supports 1–100 agents, including decimal
counts with leading zeroes. Live probes have 20-second deadlines and bounded
stdout. Explicit invalid triage is an error; an absent bv tool is optional.
Descriptions and raw parse/probe errors are not included in reports. Reports
still include ordinary task titles and labels; they are not redacted support
bundles and should be reviewed before sharing.

## Regression tests

```sh
python3 -B tests/unit/test_swarm_assign_scopes.py
bash tests/unit/test_swarm_assign.sh
bash -n scripts/lib/swarm_assign.sh
```

Tests run the actual Bash/jq allocator with file fixtures and executable probe
fixtures. They do not replace acceptance with live Beads, bv or Agent Mail.
