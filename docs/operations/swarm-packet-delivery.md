# Deliver a reviewed work packet to an existing agent

The packet generator can now hand its prompt to one explicitly selected NTM
pane. Ordinary `acfs swarm packet --bead …` generation remains read-only.
Delivery is a separate `--deliver` mode, previews by default, and requires
`--send` plus the previewed packet hash to submit anything.

This starts work in an **existing native Claude or Codex agent**. It does not
spawn agents, authenticate accounts, clear input, interrupt a session, change
trust settings, claim Beads, or reserve files. Submission can trigger paid model
calls and project edits by the receiving agent. Review the prompt first.

## Generate, review, then deliver

Run in the target repository. Protect saved context and avoid overwriting an
existing packet:

```bash
umask 077
set -o noclobber
acfs swarm packet --bead bd-example --repo "$PWD" \
  --agent-name YOUR_AGENT_NAME --max-chars 16000 --json > work-packet.json
jq -r .packet_markdown work-packet.json
```

Use an already registered Agent Mail identity where the packet names one. The
receiving agent must still inspect its inbox, current Beads, and reservations.
A packet is not a work claim or evidence that its instructions are current.

Find the stable pane ID, not a layout index:

```bash
tmux list-panes -a -F '#{session_name} #{pane_id} #{pane_current_command} #{pane_current_path}'
```

Preview the handoff (no tools are called and no receipt is written):

```bash
acfs swarm packet --deliver work-packet.json --repo "$PWD" \
  --session myproject --pane '%42' --agent-type claude \
  --operation-id myproject-bd-example-1 --receipt work-packet.receipt.json
```

The JSON output includes `send_command`, a copyable invocation with `--send` and
`--expect-sha256` already filled in. Execute that command only after reviewing
the prompt, pane, repository, and potential model costs.

Before sending, ACFS checks the live `br ready --json` queue, verifies the pane
belongs to the named session and repository, requires its foreground command to
be the requested native agent, and asks NTM for a dry run. NTM must select
exactly one agent. A shell with an old agent title is not accepted. Node-hosted
legacy agent wrappers and other provider types are not yet supported here.

Requires an NTM version supporting `--robot-send`, `--msg-file=-`, `--panes`,
`--type`, `--dry-run`, `--op-id`, and `--robot-send-receipt`. The prompt is sent
through stdin, never shell-evaluated or placed in process arguments. NTM context
injection is refused when reported enabled: this packet already contains its
reviewed context. ACFS does not edit the NTM configuration to turn it off.

## Interruptions and uncertain outcomes

Immediately before submission, ACFS writes a create-only, mode-0600 intent
receipt. It records the packet hash, target, and operation ID, not the prompt.
**Keep both the packet and receipt.**

Repeat the identical delivery command after a dropped connection or uncertain
result. When the receipt exists, ACFS only queries NTM's durable receipt. It does
not resend, even when the upstream receipt is missing or still in progress.
This intentionally avoids NTM's stale-operation takeover becoming a blind retry.
It also means an intent written just before a crash may require manual inspection
when no send actually reached NTM. Do not remove receipts merely to retry.

`submitted` means a matching NTM durable operation reports one successful pane
submission with the expected payload digest and byte count. It does **not**
prove model comprehension, task execution, or task completion. Changed or
transformed payloads, missing operations, and incomplete admissions remain
`unconfirmed`. Review NTM and the actual pane before deliberately creating a new
operation/receipt for another attempt.

Exit codes: `0` for a preview or confirmed submission, `1` for an unconfirmed
outcome, and `2` for invalid inputs, failed preflight, or interruption. Never
interpret a nonzero exit as proof that nothing was typed; retain the receipt.
No raw NTM output, model prompt, or service error body is echoed in delivery
reports. Saved packet JSON can contain private project context; do not publish it.

## Tests

```bash
bash tests/unit/test_swarm_packet_delivery.sh
```

The suite drives the real Bash/Python command, real packet generation, and
executable NTM/tmux/Beads contract fixtures. Live provider/NTM acceptance must be
run separately on a configured VPS; these tests make no model calls.
