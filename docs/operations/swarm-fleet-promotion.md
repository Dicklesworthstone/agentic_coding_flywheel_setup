# Verify the test evidence for an exact fleet candidate

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

```bash
python3 -B tests/unit/test_swarm_fleet_test_evidence.py -v
```

Tests run the real test runner and verifier with real Git repositories and
unprivileged subprocesses. They include an actual SIGKILL between durable command
results and final completion, tampering, filesystem safety, SHA-256/linked
worktrees and no-rerun/no-write assertions. No live provider acceptance is claimed.
