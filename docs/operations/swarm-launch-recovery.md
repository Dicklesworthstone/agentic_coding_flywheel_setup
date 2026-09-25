# Recover an unconfirmed native-agent launch without starting it again

A lost NTM response or an interruption after spawn can leave native agents
running while the ACFS launch intent has no `.result.json`. Retrying the normal
launch deliberately does not spawn again. Recovery provides an explicit way to
adopt the currently observed session and restore the result needed for work
packet preparation.

The checkout entrypoint is:

```bash
python3 -B scripts/lib/swarm_launch_recovery.py --receipt /absolute/path/launch.json
```

Inspect every proposed slot, agent type, pane ID, pane process, and session
identity. Names are assigned to the same native-agent types in numeric
window/pane order. They are intended packet identities, not evidence of Agent
Mail registration. The preview writes no files and invokes only tmux metadata
queries, never NTM, model commands, pane capture, or prompt delivery.

To adopt exactly those observed identities, repeat with the **recovery** digest:

```bash
python3 -B scripts/lib/swarm_launch_recovery.py --receipt /absolute/path/launch.json \
  --adopt --expect-sha256 RECOVERY_PREVIEW_DIGEST
```

This digest is different from the original launch approval. It binds the
original intent bytes, saved request, observed native pane identities and
recovery policy. Changing a process, pane, session, server, request, or policy
requires a new preview. The topology is rechecked before result publication and
again afterward. The same receipt-directory lock used by normal launch prevents
cooperating launch/recovery operations from racing.

## What adoption does and does not prove

Adoption confirms that the reviewed live panes match the saved repository,
agent count, native-agent mix and session. **It does not prove that the original
spawn created those panes.** The operator explicitly approves using this
current session. Both the report and the saved recovery provenance retain
`original_launch_verified: false`.

A successful adoption creates only the missing private result, in the existing
`acfs.swarm-launch.v1` format. Normal launch reconciliation and packet handoff
can consume that result. Keep the original intent. No agents are started,
stopped, interrupted, or given work; no Beads or Agent Mail state is changed.

Existing results (including malformed files, directories and dangling symlinks)
are never overwritten. Interrupted publication may leave a partial result that
must be preserved for inspection. Recovery does not erase evidence to enable
another attempt. A result that already exists should go through ordinary launch
reconciliation, not adoption.

Missing, extra, dead, shell-only, wrong-repository, duplicate or mixed-session
panes prevent recovery. Unsafe receipt paths and non-private, symlinked,
hardlinked or special-file intents are rejected. Input and observation sizes
are bounded to 1 MiB. `--timeout` bounds each observation to 1-30 seconds
(default 10); raw tmux errors are not copied into reports.

Exit 0 means a valid preview or successful adoption. Exit 1 means a result was
created but the final live recheck could not confirm it; retain that result and
use normal reconciliation. Exit 2 means recovery was refused or unavailable.
An interruption returns 130 and never authorizes a duplicate launch.

## Tests

```bash
python3 -B tests/unit/test_swarm_launch_recovery.py -v
```

The tests execute the real recovery CLI against a local tmux contract fixture.
They cover successful handoff-compatible results, identity-bound approval,
concurrent-directory locks, changing intents and panes, create-only result
races, partial-result preservation, invalid inputs, output limits and deadlines.
They do not start paid agents or certify a live provider session.
