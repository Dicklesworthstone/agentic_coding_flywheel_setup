# Collect reviewed commits while agents keep working

The collector supports an explicit historical tip for each selected host. This
removes the need to stop coding agents merely to keep their HEADs unchanged
through collection, or to abandon a partial collection because an unfinished
host has since committed more work. It does not select tasks or decide which
history is safe to collect.

Use an updated trusted checkout, or explicitly upgrade the installed
[fleet runtime](fleet-runtime.md). Retained older runtimes are not rewritten and
will not understand the new selection schema.

## Choose exact ranges

The existing `--bases` option accepts a private version-2 selection file:

```json
{
  "schema": "acfs.swarm-fleet-collection-spec.v2",
  "hosts": [
    {
      "id": "builder",
      "base_commit": "0123456789abcdef0123456789abcdef01234567",
      "head_commit": "89abcdef0123456789abcdef0123456789abcdef"
    }
  ]
}
```

Replace both example IDs with actual full lowercase commit IDs. For SHA-256
repositories use 64-character IDs for both. Branch names, `HEAD`, abbreviated
IDs, tag objects and revision expressions are not pins. Every selected host in
a version-2 file requires both fields; mixed implicit and explicit tips are
refused. Selection order does not change original fleet execution order.

The selected base must be an ancestor of the selected tip, not necessarily of
the host's current HEAD. The tip can belong to another branch or an earlier
work wave; it need not have a current named ref. The objects must still exist in
the original repository. Collection does not retain remote refs to protect
unreachable objects against independent garbage collection.

A version-1 selection still means **live HEAD**. Its unchanged-HEAD checks remain
in force. Merely adding a head field to version 1 is rejected; switching modes
requires a new preview and new approval, even when the two previews initially
observe the same commits.

## Preview and collect

```bash
acfs-fleet collect \
  --launch-state "$HOME/fleet-wave-1" \
  --bases "$HOME/fleet-ranges.json" \
  --known-hosts "$HOME/.ssh/known_hosts" \
  --identity-file "$HOME/.ssh/id_ed25519" \
  --output-dir "$HOME/fleet-results-wave-1"
```

This opens read-only connections and reports `revision_mode: "pinned"`, exact
ranges, counts and net changed paths. Review the complete history as well as
the summary. Repeat with `--collect --accept-plan THE_PREVIEW_DIGEST` to save the
collection. No agent is stopped, no prompt is sent and no source ref is created,
checked out or moved. Later commits, dirty indexes and uncommitted files are not
included in the selected historical range.

The controller rechecks the pinned snapshots and repository identities rather
than requiring a stationary HEAD. A changed selection, different repository,
missing object, non-ancestor base or different approval still fails closed.
There is no fallback to the current branch when a pin cannot be resolved.

## Resume the same historical collection

The existing recovery workflow works with the same version-2 file:

```bash
acfs-fleet collect \
  --launch-state "$HOME/fleet-wave-1" \
  --bases "$HOME/fleet-ranges.json" \
  --known-hosts "$HOME/.ssh/known_hosts" \
  --identity-file "$HOME/.ssh/id_ed25519" \
  --output-dir "$HOME/fleet-results-wave-1" \
  --resume --accept-plan ORIGINAL_COLLECTION_DIGEST
```

This preview is offline and read-only. Review it and repeat with
`--accept-resume THE_RESUME_PLAN_DIGEST` to download only missing ranges.
An unfinished host may have advanced its HEAD: the collector still requests the
original pinned tip. Previously saved hosts are not contacted. Changed pins or
a switch between live and pinned selection are refused before transport.

Recovery approval also binds the current executable policy, so an upgrade can
require a fresh offline preview even when saved artifacts have not changed.
Historical live-HEAD collections remain readable under their known policy; they
never acquire pinned authority. Their unchanged-HEAD requirement is preserved.
Corrupt/torn files, competing writes, and unknown members still fail closed;
there is no overwrite, cleanup, automatic retry or adoption of different work.

## Standard Git artifacts, not a different import pipeline

Pinned collection uses Git's `pack-objects --revs` for exactly the selected tip
minus the complete history reachable from the selected base. It adds a standard
version-3 bundle header advertising the selected commit as `HEAD` and requiring
the exact base history. This avoids creating a temporary source ref merely to
satisfy `git bundle create`'s named-ref requirement. `HEAD` in that transport
header is an advertisement, not a source ref update.

The existing 16 MiB limit covers the complete bundle, including its header.
Per-host deadlines, strict SSH trust, output limits and child-process cleanup
still apply. Git runs without inherited Git environment, hooks, external diffs,
lazy fetching, network protocols or automatic maintenance. Source repositories
and installed Git remain trusted; this is not a malicious-host sandbox.

The output retains the existing collection format and works with ordinary
`--verify`, strict `--import`, integration, exact-candidate testing and later
promotion. Git verifies prerequisites and performs strict indexing on import.
See [Git's bundle format](https://git-scm.com/docs/bundle-format) and
[pack-objects](https://git-scm.com/docs/git-pack-objects) for the wire semantics.

A successful collection is not proof of authorship, task attribution, safe
code or task completion. Review intermediate commits too: a secret later removed
from a selected range is still part of its history. LFS payloads, submodule
repositories and uncommitted work remain outside this collector.

## Validation

```bash
python3 -B tests/unit/test_swarm_fleet_pinned_collection.py -v
python3 -B tests/unit/test_swarm_fleet_integrate.py -v
```

The pinned suite uses real Git and the production remote program as an actual
unprivileged user. It covers moving and unborn HEADs, immutable approvals,
missing-only recovery after further commits, binary/mode/symlink/deletion
preservation, SHA-1/SHA-256 strict import and combined-candidate publication,
and merge graphs with several excluded boundary ancestors. Native launch
admission is a protocol fixture; these are not live SSH/provider or installer
acceptance results.
