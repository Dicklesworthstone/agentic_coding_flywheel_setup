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

## Prepare work directly from a verified launch

There is no need to copy pane IDs into the work preparer. Supply the original
launch intent and explicitly map each launched slot to its Agent Mail identity:

```bash
acfs swarm launch --prepare-batch ./handoff \
  --receipt "$HOME/implementation-launch.json" \
  --scopes-file scopes.json --roles implementation,documentation \
  --identity '1:RedFox' --identity '2:BlueLake'
```

This reads the private launch intent and result, rechecks the recorded native
process, stable pane, session creation time, tmux server PID, and repository
working directory, then delegates to the installed scope-aware packet preparer.
Repository, session, pane and provider choices come only from the saved launch;
there is no handoff override that can retarget another session. Provide one
identity for every launched slot, including slots that may be idle. Names are
explicit operator input, not verified Agent Mail registrations.

The original slot mapping is preserved even when NTM groups providers by type.
Only selected work produces packets. Use `--assignments assignments.json` instead
of `--scopes-file` to prepare saved assignments, including reports with idle-slot
holes. `--ready-file`, `--triage-file`, `--beads-file`, `--no-live-context` and the
role/profile options have the same meanings as in
[packet preparation](swarm-packet-preparation.md). Relative inputs resolve from
the invocation directory and their bytes are pinned before preparation.

The handoff does not spawn, send prompts, claim Beads or acquire reservations.
It rechecks the launch again after preparation. A changed agent causes failure
without advertising a usable handoff; any already-written bundle is retained for
inspection. Missing or unconfirmed launch receipts never trigger a replacement
launch or adoption of arbitrary same-named panes. Existing output is not replaced.
Review every generated packet and then use the returned `preview_command` for
the separate receipt-checked dispatch workflow below.

Handoff exit codes are `0` for prepared work, `1` for no independent ready work
(no bundle is created), and `2` for unusable launch evidence or preparation errors.
The result's `launch` object records the identity mapping and makes explicit that
no agents were started and no work was dispatched.

## Dispatch reviewed work to the original launched agents

Preparation from a launch now returns this preview command:

```bash
acfs swarm launch --dispatch-batch ./handoff/batch.json \
  --receipt "$HOME/implementation-launch.json"
```

The preview validates every packet using the installed packet-delivery module,
checks that each target belongs to the recorded launch, and verifies original
native process/session identity for each pending delivery. It does not send
prompts or create delivery receipts. Its `send_command` requires a hash binding
**the launch request and original targets plus the batch and every packet**.
A hash from the lower-level packet dispatcher does not authorize this command.

Use that returned command only after reviewing the packet Markdown and the
slot-to-pane mapping. Each new submission rechecks the original native target,
then uses the existing single-packet sender's live ready-queue check, NTM dry run,
private durable intent, exact payload hash and stdin transport. It does not create
sessions, register identities, claim Beads or acquire reservations.

Dispatch is sequential, not transactional. An uncertain submission or failed
identity check stops the batch, retains earlier submissions, and marks later
entries `not_attempted`. Keep the unchanged batch, packets, launch receipt/result,
and per-delivery receipts. Repeating the same approved command queries known
intents first and continues pending entries only after earlier submissions are
confirmed. A known intent never enters a send-capable path again during that
invocation, even if its file is moved after validation. Do not remove receipts
between invocations: an absent receipt cannot prove a previous send did not occur.

Historical submission receipts can be queried after the original agents exit;
new work still requires the original live identities. A missing upstream receipt,
wrong operation/payload/target, or malformed response stays `unconfirmed` and
never authorizes resending. `submitted` means matching NTM submission evidence,
not task execution or completion. `submission_may_have_occurred` flags uncertain
child execution even when no valid result was returned.

The native identity check and NTM send are separate operations, not an atomic
compare-and-send. Do not restart agents or replace panes during dispatch. This
path detects identity changes at its checks but cannot eliminate that final race.
The launch receipt directory lock excludes concurrent launch-aware dispatchers
using the same directory, not unrelated NTM callers or all users on the machine.

Dispatch exit codes are `0` for a valid preview or confirmed submissions, `1`
for an unconfirmed submission, and `2` for invalid evidence or a failed preflight.
After a stopped batch, inspect its per-delivery results before taking any action.
The lower-level `acfs swarm packet --deliver-batch` remains available for manually
managed agents; it does not add these original-launch identity checks.

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
python3 -B tests/unit/test_swarm_launch_handoff.py
```

The regression suites execute the actual Bash/Python launcher against executable
planner/NTM/tmux contract fixtures. They cover both admissions, exact agent mix,
original-slot mapping, private receipts, directory exclusion, unready/native
process failures, response loss and no-relaunch recovery. Handoff and dispatch
tests also exercise the actual allocator, preparer and packet sender from a
complete checkout, including receipt-only recovery after native agents exit.
They do not exercise installed providers, live authentication or a production VPS.
