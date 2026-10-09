# Seed fleet projects from an exact local commit

`scripts/swarm-fleet-provision.py` creates the project repositories needed by
fleet launch. One explicitly selected local commit and its reachable history are
transferred to the new repository paths in an existing fleet launch specification.
It requires configured Linux hosts, Python 3, Git and verified SSH access; it does
not provision VPS instances, install ACFS, authenticate providers or launch agents.
This is a checkout controller, not an installed `acfs-fleet provision` command.

## Preview and create

Use a complete trusted checkout on the Linux controller, as the source repository
owner without sudo. The original fleet launch specification supplies the hosts,
non-root accounts, ports and `request.repo` destinations. Every remote destination
must be absent under an existing user-owned parent. Existing directories, including
empty ones, are refused rather than adopted or overwritten.

```bash
python3 -I scripts/swarm-fleet-provision.py \
  --spec fleet-launch.json \
  --repository /path/to/project --commit FULL_COMMIT_ID \
  --known-hosts "$HOME/.ssh/known_hosts" \
  --identity-file "$HOME/.ssh/id_ed25519" \
  --state-dir "$HOME/fleet-projects-wave1"
```

Preview packs the exact committed history in temporary controller storage and
performs read-only SSH probes. It creates no named state or project directories.
It reports the commit/tree, full history and tree counts, transfer hash/size,
source identities and all remote parent identities/Git versions. Read the source
history too: the pack is **not redacted**, and includes intermediate commits,
messages and author metadata, including secrets removed by later commits.

Repeat the same command with `--provision --accept-plan THE_PREVIEW_DIGEST` only
after reviewing that plan. All hosts are re-probed before the first persistent
write. A changed selection, pack, trust file, destination identity or source
identity invalidates approval. Moving source HEAD alone does not change an exact
selected commit. Provisioning and fleet-launch approvals are separate.

Hosts are created sequentially. The receiver checks the full transfer hash,
initializes an empty Git repository without templates, strictly indexes the
self-contained pack, verifies the exact tree and history, and populates a new
`main` branch/index/working tree. It uses non-force `checkout-index`; it never
updates an existing project. Source Git configuration, remotes, other refs,
tags, credentials, hooks and uncommitted files are not copied. No project scripts,
install hooks, dependency installers or coding-agent commands are run.

The repository has complete reachable history, not a shallow snapshot and not a
borrowed object store. Ordinary and linked source worktrees and SHA-1/SHA-256
repositories are supported. The source's working files, index, refs and object
store are not modified. The same fleet launch spec can subsequently launch agents
in these repositories, under its normal independent admission checks.

## Records and uncertainty

The controller creates a private journal with `intent.json`, followed by each
host's durable `ID.attempt.json` before remote creation and `ID.result.json` only
after a validated completion response. The receiver writes a private
`.git/acfs-provision.json` completion receipt after successful checkout. Neither
journal contains the pack contents, but paths and source/host metadata are not
redacted. All retained evidence must be treated as private.

A failed or uncertain host stops later hosts. No directory, artifact, receipt or
project is automatically removed, repaired or regenerated. A lost SSH reply may
occur after the remote project exists; do not rerun creation into that destination.
A partial directory without a complete receipt is not a successful provisioning.
A cooperating controller uses exclusive local state publication; this does not
sandbox a hostile same-user process or promise power-loss-atomic Git/filesystem
operations. Preserve journals and remote outputs for inspection.

## Inspect interruption without recreating a project

Use the original controller snapshot, journal, SSH trust files and approval digest:

```bash
python3 -I scripts/swarm-fleet-provision.py \
  --check "$HOME/fleet-projects-wave1" \
  --known-hosts "$HOME/.ssh/known_hosts" \
  --identity-file "$HOME/.ssh/id_ed25519" \
  --accept-plan ORIGINAL_PROVISION_DIGEST
```

Check reads and locks the original journal and contacts only hosts with recorded
attempts. It verifies each receiver's original completion receipt, repository
identity, selected commit and history, branch, and Git cleanliness. A local
success is not sufficient: remote evidence must still match. All attempted hosts
are inspected even when an earlier one cannot be confirmed. The controller does
not need the source repository or regenerate its pack for this operation.

`--check` writes no controller records, remote project files or Git refs. A
receiver that completed after its SSH response was lost can report `provisioned`
with `local_result_recorded: false`; check does not create that missing local
record. Untouched hosts remain `not_attempted`. An unavailable host, absent or
invalid receipt, replaced repository, changed branch, or dirty project remains
`unconfirmed`, not evidence that no project was created or permission to retry.

This is a check of the original clean provisioning baseline, not a fleet work
status command. If agents have subsequently committed or edited the project,
the baseline check may be unconfirmed even though provisioning previously
succeeded. It does not reset their work. Git cleanliness is not hostile-code
attestation, and ignored/untracked-state semantics follow Git's normal rules.

Exit 0 means all original targets are currently confirmed. Exit 1 means there
are untouched or unconfirmed hosts; invalid evidence, approval or execution
context returns 2. Neither a confirmed receipt nor a matching Git state proves
which process performed the operation; `provenance_verified` remains false.

## Resume only the untouched hosts

After reviewing the check, replace `--check` with `--resume` in the command above.
This is explicit write authority under the original plan, not an automatic
reaction to a timeout. Resume first checks every attempted host. **An attempted
host can never enter the creation path again**, even if its directory is absent.
An unconfirmed attempt blocks all continuation; no partial remote project is
repaired or recreated.

When attempted hosts are all confirmed, the controller rebuilds the original
source pack only if untouched hosts remain. The source directory identities and
exact pack/artifact bytes must still match the approved plan. The chosen commit
can remain valid after source HEAD advances, but a missing source, removed
history, replacement checkout or different pack encoding prevents continuation.
No current branch or fresh source is substituted. A completed operation can be
checked or resumed as a no-op after the source becomes unavailable.

Every untouched host must then pass a fresh absent-destination and original-
parent-context preflight **before any missing local confirmation is recovered
or any further remote project is created**. Only after that barrier can resume
publish a missing result for a receipt-confirmed attempt, then provision untouched
hosts in the original order. It records a durable attempt before each new remote
creation and stops at the first uncertain result. Existing local results and all
remote completion receipts remain unchanged.

Journal parsing rejects non-prefix attempt histories, results without attempts,
contradictory records, unexpected members, unsafe files and changed directory
identities. The controller holds the same exclusive journal-directory lock and
rechecks exact records around remote calls and writes. A racing writer cannot
make an existing receipt eligible for replacement. Lost responses after final
publication are inspectable; a completed resume does not recreate the projects.

Keep the exact controller file used for approval. The plan binds its source hash;
updating the implementation does not silently migrate an old journal. Recovery
accepts no new repository, spec, target, commit or timeout overrides. It is not
an alternative path for adopting existing projects or bypassing initial approval.

## Limits and trust boundary

Up to 16 hosts use the same selected project. The complete compressed history is
limited to 16 MiB, at most 10,000 reachable commits, and a current tracked tree of
10,000 files/256 MiB total with 8 MiB per file. Submodule entries, shallow and
configured partial-clone sources, borrowed object stores and malformed Git
objects are refused. Git LFS **payloads are not fetched**: committed pointers
remain ordinary tracked files. Dependencies, ignored files and build caches are
not transferred. Symlinks retain Git's ordinary link semantics; this is not an
isolated execution environment for future agents or tests.

`--timeout` bounds each remote operation and the source Git phase (default 90,
range 1–600 seconds), not the complete multi-host invocation. Remote input and
both subprocess output streams are bounded. Compressed packs can expand to much
larger historical object storage; provision adequate disk/memory or use an
operator-supplied resource-limited environment. No resource limits are installed.
The source, selected remote host, Git and Python remain trusted.

Strict SSH host verification, explicit identities and the existing restrictions
on forwarding, config, proxies and multiplexing remain in place. Pack data goes
over stdin, not command-line arguments. No Git hosting credentials are required
on receivers because they do not fetch from a remote Git service.

Exit 0 means successful preview or completed provisioning; 1 means blocked or
partial host results; 2 means invalid input, approval or local execution failure.
Handled SIGINT/SIGTERM/SIGHUP return 128 plus the signal number and an interrupted
report, not success. Local child process groups are terminated on handled
interruption; a killed controller or lost SSH connection cannot prove that a
remote process stopped. Preserve evidence and inspect it before further action.
`writes_attempted` means local recovery records or remote creation may have been
written, not that every host is ready. A successful repository setup is not proof
of agent authentication, task execution, test success or code safety.

## Tests

```bash
python3 -B tests/unit/test_swarm_fleet_provision.py -v
```

Tests execute the real transmitted receiver and Git as an unprivileged user,
including two-host SHA-1/SHA-256 setup, dirty-source preservation, two-parent
history independent of its source, strict transfer/refusal cases and bounded
process execution. The SSH argv test injects a capture function and an existing
sentinel executable when OpenSSH is unavailable; it is not a live SSH test.
No hosted VPS, real agent or installer acceptance is claimed by this suite.

Recovery tests kill actual controller processes after a durable attempt, remote
completion and final local result publication. They distinguish unconfirmed
attempts from recoverable lost responses and complete no-ops, verify that only
untouched hosts enter creation, preserve changed project files, and exercise
real CLI input/approval errors and handled receiver termination. No crash test
turns absent completion evidence into a retry or modifies the original tests'
acceptance conditions.
