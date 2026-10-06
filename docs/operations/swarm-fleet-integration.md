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
This initial mode only previews; it does not publish a candidate ref.

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
bundle sizes. Use a controller with adequate scratch space. Git must support
`merge-tree --write-tree` (Git 2.38 or newer); unsupported Git fails closed.

Exit 0 means a clean candidate was computed, not that tests passed or tasks were
completed. Exit 1 means a merge conflict; exit 2 means invalid inputs or a local
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
collection tampering and occupied refs. Fixtures are retained. These tests do not
claim live SSH, authenticated agents or full installer/VM acceptance.
