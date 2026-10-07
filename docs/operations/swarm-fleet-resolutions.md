# Resolve conflicting fleet contributions without changing your checkout

An integration conflict no longer requires abandoning the collected histories or
manually merging them into the working branch. `acfs-fleet collect --integrate`
accepts an explicit, reviewed `--resolutions FILE` and continues the original
host sequence after constructing a two-parent resolution commit. The existing
preview, create-only candidate publication, exact-candidate testing, promotion
and publication workflow remains in force. No tests or provider requests run as
part of conflict resolution.

Use the updated trusted checkout, or explicitly upgrade the [installed fleet
runtime](fleet-runtime.md). Retained runtimes keep their original implementation;
selecting an old runtime does not fall back to this one.

## Inspect the actual conflict

Run the normal [integration preview](swarm-fleet-integration.md):

```bash
acfs-fleet collect --integrate "$HOME/fleet-results-wave-1" \
  --repository /path/to/project --onto FULL_TARGET_COMMIT_ID --name wave1
```

A conflict still returns exit 1, no candidate and no approval digest. Its step now
includes `conflict_tree` alongside `id`, `previous_commit`, `head_commit` and
`conflicted_paths`. The private `scratch_directory` contains the actual Git
objects. Use Git read-only inspection there to review the two parents, their
common history and the conflict tree. The tree can contain conflict-marker blobs;
it is **not** an accepted candidate. No running agent or mutable review ref is
used to supply a resolution.

## Supply explicit replacement bytes

Create a mode-0600 JSON file outside the immutable collection directory. Copy the
collection evidence digest and the conflicted step's exact object IDs from that
preview. For example, replacing `src/value.txt` with the bytes `resolved\n`:

```json
{
  "schema": "acfs.swarm-fleet-resolutions.v1",
  "collection_evidence_sha256": "COLLECTION_EVIDENCE_SHA256_FROM_PREVIEW",
  "steps": [
    {
      "id": "host2",
      "previous_commit": "EXACT_PREVIOUS_COMMIT",
      "head_commit": "EXACT_HOST_HEAD_COMMIT",
      "conflict_tree": "EXACT_CONFLICT_TREE",
      "changes": [
        {
          "path": "src/value.txt",
          "mode": "100644",
          "content_base64": "cmVzb2x2ZWQK"
        }
      ]
    }
  ]
}
```

These placeholders must be replaced with the full lowercase IDs from your
preview. Content uses canonical, padded, unwrapped base64: no shell expansion,
file discovery, source-file reread or executable merge driver is involved.
An empty file uses `"content_base64": ""`. Modes are `100644` for a regular file,
`100755` for an executable, or `120000` for a symlink whose target bytes are the
content. To remove a tracked entry, use only
`{"path": "src/obsolete.txt", "mode": "delete"}`. This edits a scratch Git index;
it does not delete a working-tree file.

Every reported conflicted path must have an explicit decision, including an
explicitly retained version. Additional path edits are allowed **only when
listed** in the reviewed specification; this permits rename, file/directory and
cross-file resolutions. All unlisted paths must retain the conflict tree's
entries. The final index must contain each exact requested mode/blob or deletion;
Git cannot silently drop one requested path while accepting another. Inspect
additional edits as carefully as the conflict itself.

The specification is bounded to 1 MiB of normalized JSON, at most one step per
selected host (16 hosts maximum), and 4,096 changes per step. Base64 and metadata
consume part of that budget. Duplicate keys, steps and paths, invalid Git modes,
traversal and `.git` path components, and noncanonical base64 are refused. No
submodule entry can be introduced. A resolution introducing an external merge
driver through `.gitattributes` is refused rather than executing that driver.

## Preview, approve, and continue

Repeat the original command with the private file:

```bash
acfs-fleet collect --integrate "$HOME/fleet-results-wave-1" \
  --repository /path/to/project --onto FULL_TARGET_COMMIT_ID --name wave1 \
  --resolutions "$HOME/fleet-resolutions-wave-1.json"
```

The controller reproduces each merge and requires that the collection evidence,
previous cumulative commit, host head, and conflict tree all match. A resolution
for an unselected, changed, already-contained, fast-forwarded or cleanly merged
host is refused, never silently ignored.

Resolved steps report `status: "resolved"`, their `resolved_tree`, a per-step
`resolution_sha256`, and every requested path/mode with blob ID, byte count and
SHA-256 where applicable. The full base64 content is not echoed into the plan.
The resolution file and resulting Git objects are **not redacted**; protect them
like source code. The plan separately binds the complete normalized specification
with `resolution_spec_sha256` and policy
`builtin-sequential-merge-tree-reviewed-resolutions-v2`.

If a later host also conflicts, processing stops there with no approval digest.
Keep earlier decisions and append the newly reported conflicted step. Earlier
resolution commits remain deterministic: they bind their own decision, not a
hash of future steps that would create a circular dependency. Host execution
order remains the original collection order, regardless of specification order.

Once the whole sequence produces a candidate, review it and repeat with
`--apply --accept-plan THE_NEW_INTEGRATION_DIGEST`. Apply transfers the resolved
objects with the source histories and creates only
`refs/acfs/integrations/NAME`. Existing candidate refs are not overwritten.
Changing any resolution bytes or decision invalidates that approval. A clean
integration approval without resolutions cannot approve the new mode.

Keep the exact resolution file alongside the original collection and digest.
After interruption, use the same arguments, including `--resolutions`, with
`--check --accept-plan ORIGINAL_INTEGRATION_DIGEST`. This recomputes and inspects
the expected candidate without updating destination refs, objects or checkout.
It does not repair or retry publication. Objects can remain after interrupted
apply; the original integration recovery rules still apply.

## What this does not establish

`resolved` means the supplied, reviewed bytes were applied to the reproduced
conflict and both parents were preserved. It does **not** establish that the
choice is semantically correct or that conflict markers were not intentionally
retained in supplied content. Neither automatic merges nor supplied resolutions
qualify as test results. `task_completion_verified` remains false.

Run [exact-candidate tests](swarm-fleet-testing.md) against the resulting full
candidate ID before promotion or publication. The runner's submodule/LFS/symlink
and unsandboxed-execution boundaries still apply. Preview writes only retained
private scratch; the destination checkout, index, existing branches, uncommitted
work and collection remain unchanged.

## Validation

```bash
python3 -B tests/unit/test_swarm_fleet_integrate.py -v
python3 -B tests/unit/test_swarm_fleet_resolutions.py -v
```

The resolution suite uses real Git merges, object transfer, create-only candidate
publication and read-only checking as an actual unprivileged user. It exercises
later-host continuation, incremental multiple conflicts, SHA-1/SHA-256, literal
binary content, modes, symlinks, modify/delete decisions, exact approval binding,
private CLI inputs and refusal paths. It does not establish live SSH/provider
acceptance or a full installer/VM run.
