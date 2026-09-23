# Start native agents with admission and a durable launch intent

The explicit launcher fills the gap between the read-only swarm planner and
packet preparation, which needs existing stable agent panes. It supports 1–32
native Claude/Codex agents. It does not use NTM's automatic work assignment.

Preview first (the standalone entrypoint is also useful from a checkout):

```bash
bash scripts/lib/swarm_launch.sh --repo "$PWD" --session implementation \
  --agent RedFox:claude --agent BlueLake:codex \
  --receipt "$HOME/implementation-launch.json"
```

The installed command is `acfs swarm launch` once the runtime has been installed
or refreshed. Preview runs the existing live ACFS planner in the selected
repository and NTM's native spawn dry-run. It does not create a receipt or start
agents, although upstream tools can write their ordinary telemetry. Use the
returned `launch_command` to perform the separate hash-bound `--launch` operation.
Launching can start paid provider processes and NTM's normal session monitor;
NTM's configured commands, models and normal permission policy remain in effect.
No prompts, trust-dialog responses, Beads claims, reservations, interrupts,
existing-session reuse or destructive cleanup are requested.

Both ACFS and NTM must admit the requested agent count. Unknown or malformed
admission fails closed. ACFS `wait`, `scale_down`, `fail`, or a count above the
recommended/safe limits always blocks launch. `--accept-warnings` is explicit
permission for warning-level decisions that still recommend proceeding; it
never overrides pressure or hard blockers. `--profile` and `--workload` select
the existing planner policies, not provider/model overrides. No saved admission
snapshots are accepted as authority to start agents.

Every requested name is bound to its original slot, even when the request
interleaves Claude and Codex. After NTM reports ready agents, ACFS resolves each
returned window/pane index to a stable tmux pane ID and verifies the live native
command, project directory, and session/process identity. A stale title on a
shell is not sufficient. The result includes `preparation_targets`, such as:

```text
1:RedFox:claude:%42
2:BlueLake:codex:%43
```

Pass those values as repeated `--target` options to `acfs swarm packet
--prepare-batch`, then review the generated packets before dispatch. Names are
intended packet identities, not a claim that Agent Mail registration occurred.
Register/verify those identities through the normal Agent Mail workflow before
editing. Process readiness does not establish authentication or successful
model execution.

## Recovery: never blindly repeat a spawn

The owned receipt parent must already exist and must not be writable by other
users. Receipts use create-only mode-0600 files; path components and existing
files cannot be symlinks. An exclusive kernel lock on the receipt directory
serializes launches using that directory. This is not a machine-wide quota:
other users or NTM callers can still launch work independently.

The intent is fsynced **before** the real NTM spawn. Full verified success writes
a separate private `<receipt>.result.json`. Both files are immutable to this
command. Repeating the same request with an existing intent only verifies the
saved stable panes; it never invokes spawn or re-runs admission as authority to
spawn. Replaced sessions, shells and unavailable panes return `unconfirmed`.

A lost response, timeout, signal, partial startup or failed confirmation can
leave a working or partial session and an intent without a result. It remains
`unconfirmed`, and ACFS deliberately does not adopt arbitrary panes based only
on the session name. Inspect that session manually. Preserve receipts; changing
the receipt path or deleting an intent is a new launch request, not recovery.
No session is automatically killed, restarted or cleaned up after failure.

Exit codes: `0` for an admitted preview or fully verified ready agents, `1` for
an uncertain launch/reconciliation, `2` for validation, admission or preflight
failure. Preserve any intent even after an exit-2 interruption.

## Verification

```bash
bash -n scripts/lib/swarm_launch.sh
python3 -B tests/unit/test_swarm_launch.py
```

The regression suite executes the actual Bash/Python launcher against executable
planner/NTM/tmux contract fixtures. It covers both admissions, exact agent mix,
original-slot mapping, private receipts, directory exclusion, unready/native
process failures, response loss and no-relaunch recovery. It does not exercise
installed providers, live account authentication or a production VPS.
