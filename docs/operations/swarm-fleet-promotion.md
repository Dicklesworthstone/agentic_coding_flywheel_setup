# Promote an exactly tested fleet candidate

The existing `acfs-fleet test` runner can verify its saved results without
executing tests again. After explicitly upgrading the installed fleet runtime,
use the original private run directory, repository and test approval digest:

```bash
acfs-fleet test --verify "$HOME/fleet-tests-wave1" \
  --repository /path/to/project --expect-plan ORIGINAL_TEST_PLAN_DIGEST
```

From a trusted complete checkout, replace `acfs-fleet test` with
`python3 -I scripts/swarm-fleet-test.py`. Keep the original digest separately
from the run directory. The verifier does not infer consent from a saved
`status: "passed"`, and it never invokes any executable named by the evidence.

## What must agree

The original intent, complete final summary, ordered command attempts, individual
results, exit codes, source-change flags and both private log streams must agree.
Log sizes and hashes are recomputed. All selected commands must have passed;
a failed command followed by fabricated additional attempts is refused. Symlinks,
hardlinked or nonprivate logs, unexpected records and missing completion evidence
cannot produce a verified pass.

The original repository identity, exact commit/tree, tracked-file list and every
Git blob are checked. The retained workspace's tracked bytes, executable flags
and symlinks must still match that tree. Generated untracked outputs are allowed.
A run that originally passed but whose tracked workspace was later edited reports
`sources_changed`. A missing final result reports `incomplete`; partial files
are neither reconstructed nor treated as authority to rerun tests. An incomplete
run can still have live children; this command does not inspect or stop them.

Exit **0** means the complete local evidence records a pass and the tracked
snapshot still matches. Exit **1** means failed, incomplete or changed-source
evidence. Exit **2** means invalid inputs, mismatched context, unsafe/corrupt
records, lock contention or a local execution error. JSON uses schema
`acfs.swarm-fleet-test-evidence.v1`. Complete records include an evidence digest
covering the exact metadata bytes and log fingerprints, alongside the original
test-plan digest and tested commit/tree. Raw log bodies are not printed.

This is a read-only operation on both the repository and run directory. It uses
local Git plumbing, no SSH or provider calls. `--timeout` bounds the aggregate
Git subprocess budget (default 90, range 1..3600 seconds), not local file hashing.
Existing snapshot/log size limits apply. Cooperating ACFS writers are locked out;
detected record or directory replacement invalidates the observation.

## Trust and retention

This is **local integrity evidence, not signed execution attestation**. Test code
runs as the same user who owns the records and can deliberately forge them. The
original specification and runner must be trusted. Neither command success nor
intact evidence proves coverage, correctness, provenance or task completion;
`test_provenance_verified` and `task_completion_verified` are false.

Historical executable fingerprints are validated as recorded data; the executable
need not still exist and is not rerun. This does not establish reproducibility
under today's libraries or toolchain. Retain the original workspace, logs and
metadata at their original location. Do not put unrelated files in the strict
run directory or change an old digest to make modified evidence pass.

## Review and approve one local fast-forward

After reviewing the code and test specification, select an existing local branch
and its full current commit ID. The branch must not be checked out in any
registered worktree. A release branch is shown below; no branch is inferred from
HEAD, a collection, a Bead or an integration name.

```bash
acfs-fleet test --promote "$HOME/fleet-tests-wave1" \
  --repository /path/to/project --expect-plan ORIGINAL_TEST_PLAN_DIGEST \
  --branch release --expect-old FULL_CURRENT_BRANCH_COMMIT
```

This preview checks the complete evidence described above, verifies that the old
commit is an ancestor of the exact tested candidate, and reports the branch and
old/new commit IDs. It writes no objects, refs, evidence or working files. Apply
only after reviewing that distinct promotion plan:

```text
--apply --accept-plan THE_PROMOTION_PLAN_DIGEST
```

Append those options to the same command. The test-plan digest identifies which
tests were approved; it is NOT permission to promote. The promotion digest binds
the exact evidence bytes, original repository identity, branch, expected old
commit, tested commit/tree, Git version, verifier implementation and timeout.
Changed evidence or context requires a new review. No tests are rerun.

Apply updates exactly `refs/heads/BRANCH`, and Git may append its existing branch
reflog with the identity `ACFS Fleet Promotion <acfs-fleet@localhost>`. It never
creates a missing branch, follows or overwrites a symbolic branch, discards
intervening commits, creates a new merge commit, pushes, or changes HEAD, another
branch, the index, Git objects or working files. The tested candidate is already
present from the prior integration/import workflow. SHA-1 and SHA-256 work.
An old commit already equal to the candidate returns `noop` without ref writes.

Git checks the expected old value while preparing a ref transaction. The
controller then checks for symbolic refs, changed evidence and occupied
worktrees again while Git holds that lock; only then does it commit. This matters
because `--no-deref` alone can overwrite a symbolic ref whose target has the
expected object ID. Competing ordinary Git ref writers cannot bypass the prepared
lock. Main, linked, locked and prunable worktree registrations are considered.

**Do not concurrently check out or attach this branch in another process.** The
worktree checks detect changes up to the final pre-commit check, but Git offers
no repository-wide checkout lock that this controller can hold. The ACFS common
directory lock coordinates ACFS operations, not unrelated Git commands. This is
not a sandbox against the repository owner writing ref files directly.

## Inspect a lost promotion response

Use the original arguments with `--check --accept-plan ORIGINAL_PROMOTION_DIGEST`
instead of `--apply`. This only validates evidence and observes the branch. It
does not update refs or logs, remove locks, repair evidence or retry a promotion.

The branch reports `matched`, `not_promoted`, `missing`, `different`, `symbolic`
or `unconfirmed`. Exit **0** (`matched`) means it directly points to the tested
candidate. Exit **1** (`attention`) means that condition is not established.
Exit **2** means invalid evidence, approval or execution context. A matching ref
does not prove which process moved it: `promotion_provenance_verified` is false.
Check mode may observe a branch now checked out elsewhere; it does not change it.

Successful apply returns `promoted` or `noop` with exit 0. Apply errors return 2;
signals return 128 plus the signal number. A timeout or lost response can happen
after Git commits the ref. `promotion_started` on an error means ref transaction
writes may have started, not that promotion succeeded. SIGKILL/power loss can also
leave lock files. Preserve them for inspection; no forced update, cleanup or
automatic retry exists. Keep approval output outside the strict test directory.

Promotion is local only. It does not replace human review, adequate test coverage,
branch-protection policy, or a separate authorized push/deployment workflow.
See Git's [update-ref](https://git-scm.com/docs/git-update-ref) and
[worktree](https://git-scm.com/docs/git-worktree) manuals for transaction and
worktree semantics. Historical test/runtime fingerprints are not publisher signatures.

```bash
python3 -B tests/unit/test_swarm_fleet_test_evidence.py -v
```

Tests run the real test runner and verifier with real Git repositories and
unprivileged subprocesses. They include an actual SIGKILL between durable command
results and final completion, tampering, filesystem safety, SHA-256/linked
worktrees and no-rerun/no-write assertions. No live provider acceptance is claimed.
Promotion tests exercise actual competing Git ref updates, a symbolic-ref race
after preflight, worktree attachment before commit, and real SIGKILL before/after
ref publication. A complete two-parent integration, real unittest run, evidence
verification, promotion and read-only check is exercised with production code.
