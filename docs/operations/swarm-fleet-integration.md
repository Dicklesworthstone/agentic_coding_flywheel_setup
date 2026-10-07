# Combine collected histories without changing your checkout

The existing collector's offline `--integrate` mode computes a combined candidate
from a verified fleet collection. It uses Git's real three-way merge machinery,
not an overlapping-path heuristic or concatenated patches. No running agent,
remote connection, provider account or prior review-ref import is needed.

From a complete trusted checkout, as the owner of the destination repository:

```bash
python3 -I scripts/swarm-fleet-collect.py \
  --integrate "$HOME/fleet-results-wave-1" \
  --repository /path/to/project \
  --onto FULL_TARGET_COMMIT_ID \
  --name wave1
```

After explicitly upgrading the installed fleet runtime from that checkout, the
same options work with `acfs-fleet collect`. Existing retained runtimes are not
changed and do not acquire new options automatically.

## What is reviewed

Replace `FULL_TARGET_COMMIT_ID` with the complete SHA-1 or SHA-256 commit ID you
intend to integrate onto. Branch names, abbreviated IDs and revision expressions
are refused. A later movement of your current branch does not change this chosen
commit. Every selected collection baseline must already be an ancestor of this
target; unrelated histories are refused rather than force-combined.

By default the selection includes every collected host. Repeat `--host HOST_ID`
to select a subset; original collection order, not argument order, determines
merge order. Collection integrity and every bundle's prerequisites are checked
before staging. The destination can be an ordinary or linked worktree and can
have staged, unstaged and untracked work. Existing importer checks still reject
shallow, configured partial-clone and borrowed-object destinations.

The report binds the source collection, exact target, selected snapshots, local
Git version, destination identities and proposed new candidate ref. It reports
`unchanged`, `already_contained`, `fast_forward`, `merged`, `conflict` or
`not_attempted` for each host. Divergent clean histories produce deterministic
two-parent commits in scratch storage, preserving the original commits rather
than squashing or rewriting their authorship. The synthetic commits explicitly
use `ACFS Fleet Integration <acfs-fleet@localhost>` and parent-derived timestamps;
these dates describe deterministic construction, not the wall-clock merge time.

A clean result includes the candidate commit/tree, net changed paths and a plan
digest. A conflict returns exit 1, no candidate and no approval digest. Processing
stops at that host: later histories are not merged on top of conflict-marker
content. Git's exit status decides whether there is a conflict, even when its
conflicted-file list is empty. Conflict paths are JSON data, not shell commands.
Preview does not publish a candidate ref. It needs no previous `--import`
operation: the selected histories are read from the collection, not mutable
review refs or branch names.

To continue past a conflict, supply an explicit [reviewed resolution
specification](swarm-fleet-resolutions.md) using `--resolutions FILE`. Each
decision is bound to the actual parents and conflict tree. The controller
preserves both histories, continues later hosts, and requires a new complete
integration approval before publishing the resolved candidate.

## Publish the exact reviewed candidate

Repeat the original integration command with
`--apply --accept-plan THE_INTEGRATION_DIGEST`. The collection, destination,
selection, exact target and combined candidate are recomputed and must match the
reviewed plan. Collection and review-import digests do not approve integration.
A conflict cannot be approved; changed inputs require another preview.

Apply copies the selected histories and synthesized merge objects into the
destination, using strict Git pack/object checks. It then checks the candidate's
exact tree, reachable objects, input ancestry and net changed paths. Only after
these checks does one create-only Git transaction publish
`refs/acfs/integrations/NAME`. Direct or symbolic refs already at that name are
never adopted or overwritten, including refs created by a competing writer.

`HEAD`, existing branches/review refs, `FETCH_HEAD`, staged/unstaged files,
untracked files and the destination index remain untouched. No checkout, push,
project hooks, provider request or test execution is performed. An all-contained
selection whose candidate equals the chosen target is a true destination no-op:
no packs or candidate ref are written. The target is an exact commit, not a
promise that a moving development branch still points there.

Successful publication reports `status: "integrated"` and `candidate_published:
true`; the no-op reports `status: "noop"`. Neither outcome certifies correctness.
Review the new ref's complete history and tree before choosing a separate
worktree for tests or merging into a development branch.

Failure or interruption after indexing starts can leave objects and retained
`.keep` markers containing the integration digest, even if no ref was published.
`integration_writes_started` on an error means destination writes may have
happened, not that publication completed. A lost terminal response can occur
after publication; do not infer that it is safe to repeat the operation.
No automatic deletion, reset, repair or forced retry is performed. Ref creation
does not promise an all-or-nothing filesystem state across process death or power
loss. Preserve the original collection, target, runtime and integration digest
outside the collection's strict artifact directory.

## Check an interrupted publication without retrying

Use the same collection, target, name, selected hosts and timeout with the
original integration digest:

```bash
acfs-fleet collect --integrate "$HOME/fleet-results-wave-1" \
  --repository /path/to/project --onto FULL_TARGET_COMMIT_ID --name wave1 \
  --check --accept-plan ORIGINAL_INTEGRATION_DIGEST
```

Check mode recomputes the candidate in private scratch, then compares the exact
destination ref. It does not index destination packs or create, update or repair
refs. `--check` and `--apply` are mutually exclusive; a check digest identifies the
expected operation, not permission to write.

The `candidate.status` is `matched`, `missing`, `different`, `symbolic`,
`unchanged` or `unconfirmed`. The candidate commit's actual bytes must hash to its
reviewed object ID; trusting a loose object's pathname is insufficient. A
matching direct ref also needs the expected tree, complete reachable history,
input ancestry, commit/path counts and net changes. This is not a full repository
`fsck` of every pre-existing object.
An all-contained no-op is `unchanged` only while the candidate ref remains absent.
An unrelated ref at that name is not hidden by the no-op. A ref changed during
inspection makes the result unconfirmed. No status authorizes an automatic retry.

Exit **0** (`matched`) means the expected candidate or no-op is established;
exit **1** (`attention`) means it is not; exit **2** means invalid input, approval,
collection or execution context. `destination_read_only` is true on check
reports, but scratch is still written and retained as described below. The
collection, original Git version and destination identities must match the
reviewed plan. This is not a journal migration or a fallback to a different
runtime.

After interruption, Git objects may exist while the candidate ref is still
missing, or the ref may already be published. Both outcomes are inspectable
without re-importing. Matching objects/refs do not prove which process published
them or that a prior invocation finished every check;
`integration_provenance_verified` and `task_completion_verified` are false.
Cooperating ACFS operations hold the common Git-directory lock, but other Git
writers are not blocked, so observations are not an atomic repository snapshot.

## Isolation and limits

Preview writes a new private bare repository under `/tmp/acfs-fleet-integration-*`.
The path is reported as `scratch_directory` (or `integration_scratch` on an error).
It is retained for inspection, including after conflicts or interruption. Do not
share it blindly: it contains unredacted committed history and may contain
conflict-marker blobs. It borrows unchanged objects from the destination; it is
not a standalone backup and may become unreadable if that history is pruned.

**No destination objects, refs, HEAD, index or working-tree files are written by
preview.** The scratch index is used only for Git's attribute evaluation. Packs
are strictly validated in scratch, reachable objects and recorded commit/path
counts are checked, and source/destination identities are checked again before
reporting. Cooperating ACFS importers use the shared Git-directory lock; other Git
writers are not stopped, so this is not an atomic snapshot of every ref/file.

Merges use the built-in Git policy in a fresh configuration, not arbitrary project
or global merge commands. Attribute macros are evaluated by Git; merge attributes
requiring external drivers are refused. Built-in text, binary and union drivers
are supported. Hooks, filters, external diffs, user templates, inherited Git
environment, global/system configuration and system/global attributes are not
used. No project code or tests are executed. Git and the repository owner remain
trusted; this is not a sandbox against a malicious same-user process.

`--timeout` is the combined Git subprocess budget (default 90, range 1..600
seconds), excluding local artifact checks and bounded cleanup. Existing collection
limits apply; local Git output is bounded to 1 MiB normally and 16 MiB for attribute
inspection. Scratch disk usage and decompressed Git objects can exceed compressed
bundle sizes. Each copied source pack, the combined synthesized-object pack and
the candidate commit body read for hash verification is limited to 16 MiB;
an oversized generated pack refuses publication. Apply can
retain earlier indexed source packs in that case. Use a controller with adequate
scratch and destination space. Git must support
`merge-tree --write-tree` (Git 2.38 or newer); unsupported Git fails closed.

Exit 0 means a clean candidate was computed, not that tests passed or tasks were
completed; apply also returns 0 for publication or no-op. Exit 1 means a merge conflict; exit 2 means invalid inputs or a local
failure. A syntactically clean merge can still be semantically wrong. Review the
full history and run appropriate checks in a separately chosen worktree before
any merge into a development branch or push.

## Tests

```bash
python3 -B tests/unit/test_swarm_fleet_integrate.py -v
```

Tests use real Git objects, bundles, plumbing and unprivileged processes, covering
independent edits, same-file disjoint hunks, rename/edit, binary and modify/delete
conflicts, repeated histories, SHA-256, dirty linked worktrees, attribute macros,
collection tampering and occupied refs. Publication tests additionally exercise
dirty-checkout preservation, real competing direct/symbolic ref creation,
strict object transfer, collection changes during apply, and hook isolation.
Recovery tests send SIGKILL to actual child processes after real destination
pack indexing and after real ref publication, then verify both states without
destination writes. They also exercise SHA-256 checks, changed/symbolic refs,
approval mismatches, locks, and real ref changes during observation.
They reject a real corrupt loose candidate object even when its pathname, tree
and parent links still match the expected commit.
Fixtures are retained. These tests do not
claim live SSH, authenticated agents or full installer/VM acceptance.
