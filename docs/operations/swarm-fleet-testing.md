# Test the exact combined fleet result

`scripts/swarm-fleet-test.py` runs explicitly selected checks against a full
commit ID in a new private snapshot. Use the candidate commit returned by the
[integration workflow](swarm-fleet-integration.md), not a moving branch name or
the dirty working tree. This works independently of remote hosts, agents and
collection receipts once the commit exists in the local repository.

**Execution is not sandboxed.** The snapshot, private HOME and clean environment
prevent accidental reliance on your working copy and inherited credentials;
they do not contain hostile code. Tests run with your user privileges and can
access the network and other files accessible to you. Review the source and
commands, or run the entire workflow inside your own disposable VM/container.
The runner neither elevates privileges nor installs a sandbox or dependencies.

## Review a test specification

Save a private JSON file with one or more explicit commands. For example, for a
project using Python's standard-library tests:

```json
{
  "schema": "acfs.swarm-fleet-test-spec.v1",
  "commands": [
    {
      "id": "unit",
      "argv": ["/usr/bin/python3", "-B", "-m", "unittest", "discover", "-s", "tests", "-v"],
      "timeout_seconds": 120
    }
  ],
  "environment": {}
}
```

Select the correct installed executable for your machine. The first argument
must be an absolute executable path. Arguments are passed literally, without a
shell, interpolation, or wildcard expansion. An explicitly selected shell or
interpreter may execute its own arguments, so these must be reviewed too. There
is no automatic `package.json`, Makefile, Cargo, CI or script-command discovery.
Empty command sets and duplicate test IDs are refused.

Only the explicit `environment` entries supplement the defaults: system PATH,
UTF-8 locale, `CI=true`, a new HOME/TMPDIR, and private XDG paths. No login shell,
SSH agent socket, cloud token or parent process environment is inherited. Set
nonsecret runtime requirements, such as PATH or RUSTUP_HOME, explicitly when
needed. Startup injection and Git/home/XDG overrides are refused. **Do not put
secrets in this specification:** its literal arguments and environment are part
of the review plan and saved evidence, not redacted secret slots. The contents
of runtimes, libraries, explicit cache directories and the operating system are
not pinned; this is not a hermetic build environment.

## Preview, then execute

Run as the repository owner without sudo, from a complete trusted checkout:

```bash
python3 -I scripts/swarm-fleet-test.py \
  --repository /path/to/project \
  --commit FULL_CANDIDATE_COMMIT_ID \
  --spec /path/to/private-tests.json \
  --output-dir "$HOME/fleet-tests-wave1"
```

After an explicit [fleet runtime installation or upgrade](fleet-runtime.md),
use the same arguments with `acfs-fleet test`. A v4 runtime includes this runner
and its exact Git helper versions. Older v1/v2/v3 runtimes remain usable for
their original commands, but selecting `test` on them fails rather than falling
back to new code. `acfs-fleet --runtime RUNTIME_ID test ...` selects the complete
retained implementation without changing the active launcher.

Preview reads the exact commit/tree and test executable identities/hashes but
executes no project code and writes no files. Review the candidate, commands,
environment, output location, limits and explicit unsandboxed execution policy.
Repeat with `--run --accept-plan THE_TEST_PLAN_DIGEST` to execute. Collection,
import and integration approvals cannot approve tests. Changed test commands,
executables, candidate or destination identities invalidate this approval.
A branch advancing does not change the explicitly chosen full commit ID.

The runner copies raw tracked blobs in bounded Git batches. It preserves binary
contents, executable flags and safe internal relative symlinks without invoking
Git hooks, smudge filters, textconv, export-ignore or export-subst. Thus an export
attribute cannot hide a failing test or rewrite the tested bytes. Source object
hashes are checked. Absolute, escaping, dangling or cyclic symlinks, submodules,
and Git LFS pointers are refused instead of qualifying an incomplete snapshot.

**By default the snapshot has no `.git` directory or history.** Checks requiring history,
tags, submodules, LFS materialization or the original dirty working tree need a
separate explicitly configured environment. No checkout, ref, index, object or
configuration change is made in the source repository by the runner. This does
not restrict what intentionally executed test code can do with the same user's
permissions. Ordinary and linked worktrees and SHA-1/SHA-256 commits are supported.

### Git-dependent builds and tests

Add `--git-snapshot` to both preview and execution when checks need a real Git
repository, for example `git rev-parse HEAD`, `git ls-files`, `git status`, or
`git diff`. After upgrading the installed runtime from this source, this is:

```bash
acfs-fleet test \
  --repository /path/to/project --commit FULL_CANDIDATE_COMMIT_ID \
  --spec /path/to/private-tests.json \
  --output-dir "$HOME/fleet-git-tests-wave1" --git-snapshot
```

Review the new plan, then repeat with `--run --accept-plan THE_TEST_PLAN_DIGEST`.
The option is part of approval: a plain-snapshot approval cannot enable it, and
its approval cannot silently select a plain snapshot. Retained older runtimes
keep their original behavior and do not gain this option automatically.

This mode creates an **independent, shallow, single-commit repository** inside
`workspace/.git`. HEAD is detached at the actual reviewed commit, not a synthetic
replacement. The index records its exact tracked paths, modes and object IDs.
Verified blobs and reconstructed, root-hash-checked trees are copied into a new
loose object store; nothing is hard-linked or borrowed from the source. This is
not a linked worktree or a clone of the source's configuration. The runner copies
no source remotes, hooks, tags, branches, alternates, credentials or dirty files.
It performs no fetch, checkout or source-repository update. System/global Git
configuration is disabled in the test environment for this mode.

**No parent history or tags are included.** `git log`/`rev-list` see one commit,
so history counts, tag-based version derivation and parent diffs still need a
 different explicitly configured environment. Submodules and LFS remain refused.
The selected commit object includes its original author, committer and message;
review the workspace before sharing it. Tests remain unsandboxed and can execute
arbitrary Git operations, network calls or same-user filesystem access themselves.

After each command and when verifying saved evidence, the runner checks the
Git control files, exact directory members, object contents and semantic index
against the original commit. Normal index stat refreshes are accepted. Changing
HEAD, staged entries, configuration, refs or objects makes the run
`sources_changed`, even after exit 0, and stops later commands. Altered saved Git
metadata also prevents promotion/publication through the existing evidence gate.
Verification never repairs the snapshot or reruns tests, and it rejects unsafe
metadata before allowing read-only Git index inspection. As with tracked files,
checks do not detect changes a trusted test makes and restores between observations.

The opt-in uses test policy `exact-tree-explicit-unsandboxed-tests-v2` and
`git_snapshot: shallow-single-commit-v1`; ordinary v1 evidence remains supported.
The existing `git_history_included` field remains false: copying one commit is
not copying its history. Canonical reconstructed trees are required; noncanonical
tree encodings are refused rather than rewritten to a different commit.
Additional limits are 10,000 tree directories, 8 MiB combined tree/commit
metadata, 8 MiB index data, and a separate 10-second bound on each snapshot
index plumbing call. Copied Git objects consume additional disk space.

## Results and failure handling

Each command runs from the snapshot root with closed stdin. Commands are ordered
and stop at the first nonzero exit, signal, output limit, timeout, or tracked-source
change. Later commands remain `not_attempted`. A zero exit cannot pass after the
command changed a tracked file, executable flag or link. Generated untracked
build outputs are allowed; source checks occur after each command, not throughout
its execution. They do not detect a modification that a trusted test restores.

The new mode-0700 output directory contains the original `intent.json`, per-test
attempt/result records, the snapshot in `workspace/`, private HOME/temp locations,
bounded `logs/ID.stdout` and `.stderr`, and a final `result.json`. Log metadata
records hashes and sizes. The JSON summary does not echo raw command output;
logs themselves are **not redacted** and may contain secrets printed by tests.
Do not share logs or workspaces without reviewing them.

Exit 0 means preview succeeded or every selected test passed with unchanged
tracked sources. Exit 1 means a completed test run failed; exit 2 means invalid
input, approval or an execution/setup error. Handled signals return 128 plus
the signal number. A passed command is not coverage, correctness or task-completion
certification; `task_completion_verified` remains false.

Normal cancellation, timeout and output-limit handling kill the test process
group and retain available output. A forcibly killed controller cannot run
cleanup, so its child tests may remain running. Test code that deliberately
escapes the group is also outside this supervisor. Inspect those processes before
further action. An interrupted run never writes a successful completion record.
Existing result directories are never overwritten or resumed; preserve them and
use a new location and newly reviewed plan for another run. No cleanup is automatic.

## Resource limits

There are at most 32 commands and 10,000 tracked files, 8 MiB per tracked blob,
256 MiB total tree data, and 1 MiB Git metadata/plan limits. Each test's combined
stdout/stderr is limited to 8 MiB; exceeding it fails the test, rather than accepting
a truncated success. `timeout_seconds` bounds each command. `--deadline` bounds
the combined test phase (default 600, range 1..3600 seconds); Git inspection and
staging have their own same-sized budget. Local hashing, file materialization,
source verification, log writes and bounded child cleanup are not strict wall-clock
limits. Tests can allocate disk or memory beyond their captured output; run in a
resource-limited environment when appropriate.

## Validation

```bash
python3 -B tests/unit/test_swarm_fleet_test.py -v
python3 -B tests/unit/test_swarm_fleet_git_snapshot.py -v
```

The suite uses real Git objects and actual unprivileged subprocesses, including
real passing/failing unittest runs and a candidate produced and published by the
production integration controller. It covers dirty/linked worktrees, SHA-256,
raw export attributes, binary/executable/link handling, aggregate and per-test
deadlines, output limits, source mutation, executable/spec changes and interruption.
It does not claim a sandbox, live provider acceptance or full installer validation.
The Git-snapshot suite runs real Git commands as an unprivileged user, verifies
dirty-source preservation, SHA-256 and unusual paths, and exercises altered
metadata, objects, unsafe files, approval separation and actual local promotion.
