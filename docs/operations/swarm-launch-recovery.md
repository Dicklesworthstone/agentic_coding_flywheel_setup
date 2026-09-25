# Recover an unconfirmed native-agent launch without starting it again

A lost NTM response or an interruption after spawn can leave native agents
running while the ACFS launch intent has no `.result.json`. Retrying the normal
launch deliberately does not spawn again. Recovery provides an explicit way to
adopt the currently observed session and restore the result needed for work
packet preparation.

The installed entrypoint is:

```bash
acfs swarm launch --recover --receipt /absolute/path/launch.json
```

Inspect every proposed slot, agent type, pane ID, pane process, and session
identity. Names are assigned to the same native-agent types in numeric
window/pane order. They are intended packet identities, not evidence of Agent
Mail registration. The preview writes no files and invokes only tmux metadata
queries, never NTM, model commands, pane capture, or prompt delivery.

To adopt exactly those observed identities, repeat with the **recovery** digest:

```bash
acfs swarm launch --recover --receipt /absolute/path/launch.json \
  --adopt --expect-sha256 RECOVERY_PREVIEW_DIGEST
```

This digest is different from the original launch approval. It binds the
original intent bytes, saved request, observed native pane identities and
recovery policy. Changing a process, pane, session, server, request, or policy
requires a new preview. The topology is rechecked before result publication and
again afterward. The same receipt-directory lock used by normal launch prevents
cooperating launch/recovery operations from racing.

## Reconcile a saved launch using only its receipt

```bash
acfs swarm launch --reconcile --receipt /absolute/path/launch.json
```

This reads the original saved repository, session, agent identities and options,
then verifies the recorded native panes. It does not need the original launch
arguments and never calls admission, NTM spawn, or prompt delivery. An adopted
result retains its explicit recovery provenance in this report. A missing result
returns an unconfirmed status and a recovery preview command; reconciliation does
not adopt anything automatically. Changed or invalid results remain preserved.

After a ready result, prepare work using the existing scoped handoff:

```bash
acfs swarm launch --prepare-batch ./work-bundle \
  --receipt /absolute/path/launch.json --scopes-file ./scopes.json \
  --identity 1:BlueLake --identity 2:RedFox
```

Supply the actual Agent Mail identity for every recorded launch slot. Preparing
packets does not send them; review the returned dispatch preview separately.
The launch/adoption names alone are not proof of Agent Mail registration.

Fresh installs and runtime updates distribute the recovery helper beside the
native launcher under the canonical internal-checksum contract. A missing or
symlinked helper fails closed; the launcher never searches PATH for a substitute.
For checkout use, invoke `bash scripts/lib/swarm_launch.sh --recover` or the
standalone `python3 -B scripts/lib/swarm_launch_recovery.py` with the same flags.

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
python3 -B -m unittest discover -s tests/unit -p 'test_swarm_launch_recovery*.py' -v
```

The tests execute the real recovery CLI against a local tmux contract fixture.
They cover successful handoff-compatible results, identity-bound approval,
concurrent-directory locks, changing intents and panes, create-only result
races, partial-result preservation, invalid inputs, output limits and deadlines.
They do not start paid agents or certify a live provider session.

Integration tests additionally reproduce a lost NTM spawn response through the
actual launcher, recover its saved session, reconcile using only the receipt, and
produce real scoped startup packets without a second spawn or any prompt send.
