# Bring committed fleet work back for review

`scripts/swarm-fleet-collect.py` retrieves **incremental Git bundles** from the
repositories recorded in an original fleet launch journal. Unlike a status
report, these artifacts contain the actual commits, trees and file objects
needed to inspect and integrate the work on another machine. Merge topology,
binary files, executable bits and deletions are preserved by Git.

Collection does not launch agents, submit prompts, make commits, close Beads,
check out files, run project code/tests, merge branches or push. Remote reads use
the fleet's existing strict SSH transport and original trust inputs. Neither
provider access nor a still-running agent is required.

## Choose the original base commits

Create a private `fleet-bases.json` with the host IDs from the launch journal and
**full commit IDs for the starting revisions you intend to review**:

```json
{
  "schema": "acfs.swarm-fleet-collection-spec.v1",
  "hosts": [
    {"id": "builder", "base_commit": "0123456789abcdef0123456789abcdef01234567"},
    {"id": "reviewer", "base_commit": "89abcdef0123456789abcdef0123456789abcdef"}
  ]
}
```

The example hashes must be replaced with your actual base commits. The launcher
did not record a Git baseline, so collection **does not infer one** from a branch
name, timestamp or task closure. Each base must be an ancestor of that host's
current HEAD. The selection cannot override a repository, host, account or SSH
option. Only hosts with confirmed local launch results are selectable; reconcile
an interrupted launch separately before selecting it.

## Preview, then collect

After an explicit [fleet runtime installation or upgrade](fleet-runtime.md),
run on the Linux controller:

```bash
acfs-fleet collect \
  --launch-state "$HOME/fleet-wave-1" \
  --bases fleet-bases.json \
  --known-hosts "$HOME/.ssh/known_hosts" \
  --identity-file "$HOME/.ssh/id_ed25519" \
  --output-dir "$HOME/fleet-results-wave-1"
```

From a complete trusted checkout, `python3 -I scripts/swarm-fleet-collect.py`
accepts the same arguments. Older v1/v2 installed runtimes do not have `collect`;
use `acfs-fleet runtimes` to inspect capabilities rather than changing old files.

This contacts the selected hosts but creates nothing. It reports their exact
base/HEAD commits, object formats, commit counts and **net changed paths**. Paths
are JSON-escaped; they are data, not shell arguments to execute. The plan binds
those snapshots, original launch evidence, transport trust and output directory.

**Review the complete commit range, not just the net changed-path list.** A
bundle includes intermediate commits, commit messages and author metadata. A
secret committed and later removed still exists in that history. Bundles are not
redacted, signed or restricted to a Bead's declared file scope. Do not share them
without reviewing the included history.

Repeat the command with `--collect --accept-plan THE_RETURNED_DIGEST`. Every host
is re-previewed before any output is created. Changed HEADs, repository identities
or selections require new approval. The fixed remote program checks the snapshot
again before and after constructing the bundle, and the controller checks the
advertised HEAD and pack checksum. SHA-1 and SHA-256 repositories are supported.

The new private output directory contains `intent.json`, one `HOST_ID.bundle`
per nonempty commit range, and a final `manifest.json` with artifact hashes and
sizes. An unchanged range is recorded with `file: null`; it does not produce an
invalid empty bundle. No existing directory or artifact is overwritten.

**Only committed history is included.** Staged changes, unstaged changes,
untracked/ignored files, other branch tips, reflogs, repository configuration,
Git LFS object storage and submodule repositories are not exported. A committed
LFS pointer or submodule gitlink is preserved, not materialized. Shared-repository
commits may include work from other agents; collection is not task attribution
or independent completion verification.

## Verify and review locally

Integrity verification needs neither the original journal nor network access:

```bash
acfs-fleet collect --verify "$HOME/fleet-results-wave-1"
```

Keep the original collector runtime ID with these artifacts. To use that exact
retained verifier after an upgrade, put `--runtime ORIGINAL_RUNTIME_ID` before
`collect`. This selects code, not additional collection or merge authority.

This validates the complete manifest, exact member set, private file properties,
artifact hashes, bundle headers and pack checksums. It does **not** validate all
Git objects or establish that your destination has the required base history.
Use Git's own verifier in a trusted destination repository with the base commit:

```bash
git -C /path/to/project bundle verify "$HOME/fleet-results-wave-1/builder.bundle"
```

After inspecting the plan and choosing a new review branch, an explicit local
import can preserve your current checkout:

```bash
git -C /path/to/project fetch "$HOME/fleet-results-wave-1/builder.bundle" \
  HEAD:refs/heads/fleet-review-builder
git -C /path/to/project log --oneline BASE_COMMIT..fleet-review-builder
git -C /path/to/project diff --stat BASE_COMMIT fleet-review-builder
```

Substitute the reviewed base commit. The fetch command writes local Git objects
and the named review ref; it is **not run by ACFS**. Choose an unused ref, inspect
the full diff, and run appropriate checks in an isolated worktree before any
merge. Never execute downloaded source merely because bundle checksums match.
See the [Git bundle manual](https://git-scm.com/docs/git-bundle) for prerequisite
and import semantics.

## Import a reviewed collection without changing the checkout

The separate offline `--import` mode handles several collected histories as one
review operation. Upgrade the explicit fleet runtime from this checkout before
using it; existing retained collector files are never modified in place.

```bash
acfs-fleet collect --import "$HOME/fleet-results-wave-1" \
  --repository /path/to/project --name wave1
```

This preview validates the entire collection and asks the destination's Git to
verify every selected bundle's prerequisite history. It creates no project files,
Git objects or refs. Run as the repository owner, without sudo, on Linux with
system Git. The destination must be an existing ordinary or linked worktree with
the corresponding base commits; bare, shallow, configured partial-clone and
borrowed-object repositories are refused. SHA-1 and SHA-256 formats must match.

By default all collected hosts are selected. Repeat `--host HOST_ID` to select
only histories belonging in this destination. Unknown or duplicate host IDs are
refused; original collection order is retained. No task attribution is inferred.
`--name` must start with a lowercase letter and contain at most 64 lowercase
letters, digits, underscores or hyphens. It creates a dedicated namespace:
`refs/acfs/fleet/NAME/HOST_ID`. These are review refs, not the current branch.
An unchanged range creates no ref; an entirely unchanged selection is a no-op.

Review the new import plan, including artifact hashes, commit ranges, destination
identities and exact new ref names. Repeat it with
`--apply --accept-plan THE_IMPORT_DIGEST`. Collection approval is not import
approval. Changed inputs or a replaced destination invalidate the import digest.
Existing refs, including dangling symbolic refs, are never adopted or overwritten.

All prerequisites are checked before any pack is indexed. Apply then runs Git's
strict pack/object checks, verifies each actual commit range and net changed-path
list against the recorded snapshot, and checks reachable-object connectivity.
Only after all selected histories pass does one create-only `git update-ref`
transaction publish the review refs. It does not update `HEAD`, existing refs,
`FETCH_HEAD`, the index, staged/unstaged files, or untracked files. It does not
checkout, merge, commit, push, execute hooks, run project code or invoke providers.
Inherited Git settings, lazy fetch, network protocols and automatic maintenance
are disabled. The destination and installed Git remain trusted, not sandboxed.

For example, inspect the imported range without switching branches:

```bash
git -C /path/to/project log --oneline BASE_COMMIT..refs/acfs/fleet/wave1/builder
git -C /path/to/project diff --stat BASE_COMMIT refs/acfs/fleet/wave1/builder
```

`--timeout` in import mode is the combined Git subprocess budget (default 90,
range 1..600 seconds), excluding local artifact reads and bounded child cleanup.
The JSON schema is `acfs.swarm-fleet-import.v1`; successful preview, import and
no-op return 0, errors return 2. Neither imported history nor a valid Git object
establishes task completion, code safety or test success.

Failures after indexing starts may leave Git objects even when no refs were
published. Packs receive retained `.keep` markers containing the import digest
so concurrent ordinary repacking does not discard them before publication. There
is no automatic cleanup, reset, forced retry or removal of Git data. The
create-only ref transaction does not promise an all-or-nothing filesystem state
under power loss or a process killed during publication. Inspect exact review
refs after interruption; do not infer failure from a lost terminal response.
A changed collection detected after publication can likewise produce an error
with the refs already present. `import_started` on an error means writes may
have happened, not that all refs were created. Keep the preview digest and output
outside the strict collection directory.

### Inspect an interrupted import without retrying it

Use the original import selection, destination, name and digest:

```bash
acfs-fleet collect --import "$HOME/fleet-results-wave-1" \
  --repository /path/to/project --name wave1 \
  --check --accept-plan ORIGINAL_IMPORT_DIGEST
```

This is read-only. The digest binds the expected operation; it does not authorize
writes in check mode. `--check` and `--apply` are mutually exclusive. Checks neither
index packs nor create, change or repair refs. They require the intact collection
and the same destination identity, but not remote hosts or running agents.

Each selected history reports `matched`, `missing`, `different`, `symbolic`,
`unchanged` (no commits to import), or `unconfirmed`. A matching direct ref must
point at the exact collected commit and pass the range/path/connectivity checks.
Symbolic refs cannot stand in for the original direct review refs. Ref changes
detected during observation make that result unconfirmed. Cooperating importers
are locked out; other Git writers can still modify refs, so the result is not an
atomic repository snapshot.

Exit **0** (`matched`) means all selected refs/history match, including unchanged
ranges. Exit **1** (`attention`) means some result is not established. Exit **2**
is an invalid input, changed approval context or local execution error. A match
does not prove which process created the refs, that a previous importer completed
its strict indexing checks, or that the work is correct; `import_provenance_verified`
and `task_completion_verified` remain false.

After a killed importer, some packs may exist without refs, or the ref transaction
may already have committed despite losing its terminal response. These are
different outcomes. Inspect the report before deciding on any further action;
missing/changed refs never become automatic permission to retry or overwrite.

## Resume an interrupted collection

The updated collector can finish a retained collection without downloading its
already-saved bundles again. This is separate from import/integration recovery:
it writes only missing collection artifacts, never project Git objects or refs.
Explicitly upgrade the installed fleet runtime from this checkout first; old
retained runtimes are not modified. Existing v1 collections remain readable and
eligible when their original policy and complete approval context still match.

Keep the original collection digest, launch journal, base selection, trust files,
output path and timeout. Start with an **offline, read-only resume preview**:

```bash
acfs-fleet collect \
  --launch-state "$HOME/fleet-wave-1" --bases fleet-bases.json \
  --known-hosts "$HOME/.ssh/known_hosts" \
  --identity-file "$HOME/.ssh/id_ed25519" \
  --output-dir "$HOME/fleet-results-wave-1" \
  --resume --accept-plan ORIGINAL_COLLECTION_DIGEST
```

This opens no SSH connection and changes no files. `status: "resume_preview"`
means the retained collection is incomplete but structurally recoverable. Its
`resume_plan` lists the exact recovered artifact hashes and `pending_hosts`;
`resume_plan_sha256` binds those bytes, the original intent, collection directory
identity, and any complete final manifest. A complete collection instead reports
`status: "verified"`, also without network or writes.

Review the retained artifacts and pending selection, then repeat the command
with **`--accept-resume THE_RESUME_PLAN_DIGEST`**. Both approvals are required:
the original digest identifies the exact approved histories; the fresh resume
digest authorizes continuing from the observed local state. It is not permission
to adopt different remote work or overwrite a damaged file. `--resume` and
`--collect` are mutually exclusive.

Only missing nonempty ranges are requested, in original host order. The unchanged
fixed remote collector checks each missing host against its original approved
base, HEAD, repository identity, object format, commit count and changed paths.
A missing host that has advanced or been replaced is refused. Successfully saved
hosts are **not contacted**, so they may continue working or be offline without
invalidating the historical bundle already retained locally. An approved empty
range needs no bundle or remote read; this does not assert that the remote HEAD
is still unchanged today.

Once all ranges are available, resume creates the original-format final manifest
and runs the existing verifier. The resulting collection works with the ordinary
strict import and integration commands; it does not need a special consumer.
Only missing files are created. Existing bundles, intent and manifest are never
replaced, removed or rewritten. The launch journal and collection are locked in
the same order as initial collection, and evidence/directory identities are
rechecked before and after remote reads and publication.

Missing completion evidence is not the same as corrupt evidence. A partial
bundle, malformed existing manifest, unrecognized member, unsafe file, or bundle
appearing after a missing earlier nonempty range fails closed. The controller
does not delete torn files or silently recapture them. Preserve such a directory
for inspection and use a new separately approved collection when it cannot be
resumed. Existing bundles are checked for framing, advertised HEAD and pack
checksum; before a final manifest exists this does not prove original transport
provenance or full Git object semantics. `collection_provenance_verified` remains
false. Review their hashes and use strict Git import checks before trusting work.

After any interrupted or partially successful resume, repeat the **offline
preview without `--accept-resume`**. Progress changes the resume digest; an old
digest cannot approve newly observed artifacts. A crash after all bundles are
saved but before the manifest can be completed without contacting any host.
A crash after the final manifest is published is recognized as already verified.
No lost response, missing ref, or failed SSH attempt triggers an automatic retry.

Resume reports retain the existing exit conventions: 0 for a successful preview,
verified no-op or completed collection; 1 for a remote refusal/partial result;
2 for input, approval, lock or filesystem errors. `collection_resume_writes_started`
on an error means artifact writes may have happened, not that the collection is
complete. Signals use the existing handler. Source histories, agent sessions,
prompts, Beads state and project working files remain untouched.

Existing per-host size/deadline limits apply. Recovery retains verified bundle
bytes in memory and rereads saved evidence around remote operations, so plan for
up to 16 bundles of 16 MiB plus validation overhead and local I/O. It is not an
atomic fleet snapshot, a sandbox against a malicious same-user process, proof of
task completion, or permission to execute collected code.

## Failure and resource limits

Exit 0 means preview, collection or local integrity verification succeeded.
Exit 1 reports a remote refusal or partial collection. Exit 2 is a local input,
lock, approval or filesystem error. Signals return 128 plus the signal number.
Failures expose fixed codes rather than raw Git/SSH stderr or source contents.

The collector accepts at most 16 selected hosts, 10,000 commits and 4,096 net
changed paths per host, a 1 MiB metadata limit, and a 16 MiB bundle limit. Each
remote operation has `--timeout` (default 90, range 1..600 seconds), with bounded
subprocess cleanup. Hosts are visited sequentially in original launch order;
this is not an atomic fleet snapshot or an overall wall-clock deadline.

Shallow and configured partial-clone repositories are refused. Network protocols,
lazy fetches, replace/graft objects, external diff/textconv helpers, fsmonitor and
Git maintenance are disabled for collection. Worktree and bare-repository paths
are not interchangeable; ordinary and linked worktrees are supported. The trust
boundary still includes the selected host and its installed Git/Python; this is
not a sandbox against a malicious same-user process or a dishonest host.

An interruption preserves the output already written and does not publish a
successful completion report. Missing or corrupted final evidence fails
`--verify`. An intact retained prefix can be explicitly resumed as described
above. Otherwise keep it for inspection and use a **new output directory with a
new preview**. No launch/send operation is retried, and neither local nor remote
source history is rewritten.

## Validation

```bash
python3 -B tests/unit/test_swarm_fleet_collect.py -v
python3 -B tests/unit/test_swarm_fleet_import.py -v
python3 -B tests/unit/test_swarm_fleet_collection_resume.py -v
```

Tests use actual Git repositories and the unchanged fixed remote program running
through a real shell as an unprivileged process. They round-trip bundles into
separate repositories, including merges, binary files and SHA-256 history, and
exercise journal binding, changed snapshots, corrupt transfers, file integrity,
private publication and bounded capture. Launch admission is a protocol fixture;
these tests do not claim live SSH/VPS/NTM/provider acceptance.

Import tests also construct real collections through the production collector
and fixed remote program, then exercise actual destination Git. They cover dirty
and linked worktrees, hooks, missing prerequisites, recomputed transport checksums
around corrupt pack objects, mismatched history metadata, occupied refs, namespace
selection, destination replacement and cooperating-controller locks.
Recovery tests kill actual importer children with SIGKILL after real pack indexing
and after a real ref transaction. They also introduce a competing Git ref write
after the importer's prechecks and verify that the create-only transaction refuses
the other creations. Read-only checks leave collection and repository bytes intact.

Collection resume tests run the real fixed remote program and Git as an actual
unprivileged user. They exercise offline previews, missing-only downloads,
immutable saved artifacts, both approvals, empty ranges, changed pending HEADs,
changed launch/trust context, corrupt/non-prefix evidence, and SHA-1/SHA-256
resume-to-strict-import-to-combined-candidate workflows. Native launch admission
is a protocol fixture; this does not establish live SSH/provider acceptance.
