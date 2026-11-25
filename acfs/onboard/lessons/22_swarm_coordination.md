# Swarm Coordination: From Claim to Handoff

**Goal:** Run one realistic multi-agent task loop without stale commands, local build storms, or file conflicts.

---

## The Shape of a Safe Swarm Session

A good swarm session is boring in the best way:

1. Pick ready work from Beads.
2. Pull bounded history with CASS and CM.
3. Register with Agent Mail.
4. Reserve the exact files you will edit.
5. Announce the start in the Beads thread.
6. Work in a narrow slice.
7. Run quality gates with the right offload wrapper.
8. Scan changed files with UBS.
9. Close and sync the Bead.
10. Release reservations and hand off the result.

The commands below use `br` for issue state and `bv --robot-*` for graph-aware recommendations. Agents should not launch the interactive Beads viewer during automated work.

---

## 1. Pick the Next Ready Task

Start from robot output so an agent can parse it deterministically:

```bash
bv --robot-next
bv --robot-triage
br ready --json
```

Pick one unblocked Bead, then inspect it:

```bash
br show bd-1234 --json
br update bd-1234 --status in_progress
```

Use the Bead ID everywhere else in the session: Agent Mail thread ID, reservation reason, commit message, and closeout note.

---

## 2. Pull Bounded CASS and CM Context

Before editing, recover only the history that can change the plan:

```bash
cm context "bd-1234 checkout validation in /data/projects/my-app" --workspace /data/projects/my-app --limit 5 --history 3 --json
cass search "checkout validation command shape" --workspace /data/projects/my-app --limit 5 --fields summary --json --max-tokens 1200
cass search "bd-1234 checkout validation" --workspace /data/projects/my-app --limit 3 --fields summary --json --max-tokens 900
```

Use the results as hints, not law. Durable memories can tell you which command shapes and prior traps matter, but current `AGENTS.md`, README files, Beads output, and the live code still win when anything disagrees.

A good memory preflight ends with a short note:

```text
Context preflight:
- Current source of truth: AGENTS.md, README.md, br show bd-1234.
- Useful memory: prior checkout work used server-side validation plus focused tests.
- Drift-prone fact to recheck: current route names in src/checkout/session.ts.
```

For a launched swarm, generate the copyable per-agent startup packet before
spawning or pasting prompts:

```bash
acfs swarm packet --bead bd-1234 --agent-name BlueLake --role implementation
acfs swarm packet --json --bead bd-1234 --agent-name BlueLake
```

The packet is read-only. It packages current AGENTS.md/README guidance, the live
Bead, bounded CM and CASS hints, Agent Mail reservation commands, RCH gate
examples, UBS scanning, and explicit drift checks into a prompt-sized handoff.
Live repo files and Beads always override packet hints.

---

## 3. Register With Agent Mail

Agent Mail is exposed to agents as MCP tools. Register a unique identity in the project before reserving files or sending messages:

```text
ensure_project(human_key="/data/projects/my-app")

register_agent(
  project_key="/data/projects/my-app",
  program="codex-cli",
  model="gpt-6.2-sol",
  task_description="bd-1234 checkout validation"
)
```

Agent names are generated adjective+noun identifiers such as `BlueLake` or `GreenCastle`. Use the actual registered name in every later Agent Mail call.

---

## 4. Reserve the Edit Surface

Reserve only the files or tight globs you expect to touch:

```text
file_reservation_paths(
  project_key="/data/projects/my-app",
  agent_name="BlueLake",
  paths=[
    "src/checkout/session.ts",
    "tests/checkout/session.test.ts"
  ],
  ttl_seconds=3600,
  exclusive=true,
  reason="bd-1234: checkout validation"
)
```

If the reservation conflicts, choose a different ready Bead or narrow the path set. Do not edit files held by another active agent.

---

## 5. Announce the Start

Use the Bead ID as the Agent Mail thread ID:

```text
send_message(
  project_key="/data/projects/my-app",
  sender_name="BlueLake",
  to=["GreenCastle"],
  thread_id="bd-1234",
  subject="[bd-1234] Start: checkout validation",
  body_md="Claimed bd-1234. Reserved src/checkout/session.ts and tests/checkout/session.test.ts. Plan: add server-side validation and focused tests."
)
```

For solo work, a self-addressed start note is still useful because it leaves an auditable trail.

---

## 6. Work in One Narrow Slice

Keep the slice small enough that another agent can understand it from the Bead, the reservation, and the final diff.

Good swarm slices:

- One failing test plus the production fix.
- One docs page plus its static lint.
- One installer phase hardening change plus a fixture.

Risky swarm slices:

- Broad refactors across unrelated modules.
- Generated files edited by hand.
- Cleanups mixed into feature work.

---

## 7. Run Quality Gates Without Local Build Storms

For Rust-heavy checks, use RCH so swarms do not overload the local machine:

```bash
rch exec -- cargo test
rch exec -- cargo clippy
```

For Bash and web work, use the repo's local gates:

```bash
shellcheck install.sh scripts/**/*.sh

cd apps/web
bun run type-check
bun run lint
bun run build
```

Run the smallest useful gate first, then widen when the change touches shared behavior.

---

## 8. Scan Changed Files With UBS

UBS is the last bug-focused check before commit:

```bash
ubs src/checkout/session.ts tests/checkout/session.test.ts
```

If UBS reports a real issue, fix the cause and rerun it on the changed files.

---

## 9. Close and Sync the Bead

Close the Bead only after the change is implemented and verified:

```bash
br close bd-1234 --reason "Implemented checkout validation and focused tests"
br sync --flush-only
```

`br sync --flush-only` only exports Beads data. You still stage and commit the `.beads/` changes yourself.

---

## 10. Commit, Push, Release, and Handoff

Keep the commit focused and include the Bead ID:

```bash
git status
git add src/checkout/session.ts tests/checkout/session.test.ts .beads/
git commit -m "fix(checkout): validate checkout sessions"
git push origin main
```

Then release reservations and post the final note:

```text
release_file_reservations(
  project_key="/data/projects/my-app",
  agent_name="BlueLake"
)

send_message(
  project_key="/data/projects/my-app",
  sender_name="BlueLake",
  to=["GreenCastle"],
  thread_id="bd-1234",
  subject="[bd-1234] Completed: checkout validation",
  body_md="Landed commit abc123. Gates: type-check, lint, build, UBS. Reservations released."
)
```

Your final handoff should say what changed, which gates ran, what was not run, and whether any follow-up Beads remain.

---

## Quick Reference

| Step | Command or Tool |
|------|-----------------|
| Find work | `bv --robot-next`, `bv --robot-triage`, `br ready --json` |
| Claim | `br update bd-1234 --status in_progress` |
| Context | `cm context ... --workspace ... --limit 5 --history 3 --json` |
| Search history | `cass search ... --workspace ... --limit 5 --fields summary --json` |
| Packet | `acfs swarm packet --bead bd-1234 --agent-name BlueLake` |
| Reserve | `file_reservation_paths(...)` |
| Announce | `send_message(..., thread_id="bd-1234")` |
| Rust gates | `rch exec -- cargo test` |
| Scan | `ubs <changed-files>` |
| Close | `br close bd-1234 --reason "..."` |
| Sync | `br sync --flush-only` |
| Release | `release_file_reservations(...)` |

---

## Next

Learn how ACFS keeps the machine responsive under heavy agent load:

```bash
onboard 23
```
