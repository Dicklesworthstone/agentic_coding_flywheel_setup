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

From a trusted checkout on the Linux controller:

```bash
python3 -I scripts/swarm-fleet-collect.py \
  --launch-state "$HOME/fleet-wave-1" \
  --bases fleet-bases.json \
  --known-hosts "$HOME/.ssh/known_hosts" \
  --identity-file "$HOME/.ssh/id_ed25519" \
  --output-dir "$HOME/fleet-results-wave-1"
```

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
python3 -I scripts/swarm-fleet-collect.py --verify "$HOME/fleet-results-wave-1"
```

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
`--verify`. Keep partial directories for inspection and use a **new output
directory with a new preview** for another collection. No launch/send operation
is retried, and neither local nor remote source history is rewritten.

## Validation

```bash
python3 -B tests/unit/test_swarm_fleet_collect.py -v
```

Tests use actual Git repositories and the unchanged fixed remote program running
through a real shell as an unprivileged process. They round-trip bundles into
separate repositories, including merges, binary files and SHA-256 history, and
exercise journal binding, changed snapshots, corrupt transfers, file integrity,
private publication and bounded capture. Launch admission is a protocol fixture;
these tests do not claim live SSH/VPS/NTM/provider acceptance.
