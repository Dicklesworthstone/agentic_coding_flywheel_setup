# Updater single-instance admission

An update must hold an exclusive lock on its resolved target home before
repository discovery, self-update, logging, or component updates. The lock is
on the existing directory inode, opened read-only: no lock pathname is created,
truncated, stamped, or removed. A symlink alias to the same home identifies the
same lock. Root and an ordinary user updating that same home must contend with
each other; using different invoking UIDs is not permission to run concurrently.

## Outcomes

An already-running update causes a new invocation to exit **75** before any
update work. This is deliberately not a successful update or the component
summary's partial-failure status. The diagnostic explains that no update ran.
Set `ACFS_UPDATE_LOCK_WAIT=1` to wait instead; `0` is the default. Other values
are rejected. Missing system `flock`, an unresolved or unreadable home, kernel
locking errors, and a home replaced while waiting all stop the invocation.
There is no unlocked fallback and no automatic dependency installation.

`--help`, `-h`, and `--check-runtime` bypass admission, and sourcing `update.sh` does not acquire a
lock, exit its caller, or close its caller's descriptor. The existing target-home
resolver remains authoritative; an unknown target user does not fall back to
updating the invoking user's home.

## Self-update and subprocesses

Descriptor 9 carries the directory lock across `exec`. Re-execution by the same
process verifies both the inherited descriptor's directory identity and kernel
lock acquisition; `ACFS_SELF_UPDATE_DONE=true` alone never skips admission.
A normal child has a different process ID and must acquire its own lock rather
than starting a nested update with its parent's descriptor. An inherited process
marker without the matching descriptor fails closed.

The existing process-storm watchdog closes descriptor 9 in its child. Locks are
released when their last open descriptor closes; there is no stale lock file to
remove after a killed updater. Unrelated long-lived child programs must not keep
this descriptor alive. This is cooperative exclusion, not a sandbox against an
installed tool deliberately unlocking or closing descriptors.

## Dependency-complete self-update and recovery (#510)

The updater prepares a private runtime generation under
`~/.acfs/.update-runtime/` before advancing its checkout or replacing its
entrypoint. It reads raw Git objects from one immutable commit obtained from
the expected ACFS origin, checks the complete internal checksum inventory and
Bash syntax, then validates the saved installation policy in a fresh process.
The probe does not run tool installers or write the checkpoint.

A regular JSON `current` pointer activates the complete generation with one
atomic rename. The previous generation remains available if preparation is
interrupted or fails. Incomplete preparation directories remain private and
inactive. Do not edit or source their receipt files. A separate deployment's
canonical `scripts/lib/update.sh` entrypoint is published only after activation;
a Git-managed entrypoint is advanced through a clean fast-forward or retained
when it already supports generation admission. Locally modified tracked code
is never replaced by recovery.

The selected generation supplies the updater's libraries throughout the run.
Later deployment uses the same immutable source revision. Re-execution keeps
the original arguments, target identity and checkpoint path, process ID and
descriptor-9 lock. Preparation subprocesses close their inherited copy of
that descriptor, so an orphan cannot retain the updater's lock.

### Inspect a stranded installation

Use the updater from a current, reviewed ACFS checkout containing this fix:

```sh
bash /path/to/agentic_coding_flywheel_setup/scripts/lib/update.sh --check-runtime
```

This command is read-only and does not source the installed `state.sh`. It can
report a missing or outdated reader even while another update holds the lock.
An active generation is checked against its complete receipt and file hashes.
For an older unbundled installation, the command reports adjacent-library
availability without claiming an authenticated generation exists.

### Recover only the updater runtime

Run as the installation's account, using a current checkout with the expected
GitHub origin:

```sh
bash /path/to/agentic_coding_flywheel_setup/scripts/lib/update.sh --repair-runtime --yes
```

Recovery fetches and pins one revision, prepares its complete core runtime,
validates the existing checkpoint and activates the generation. It exits
without installing tools, deploying optional commands or configurations,
changing safe/vibe policy, or rewriting the checkpoint. An explicit
`ACFS_STATE_FILE` remains authoritative and must identify the resolved target.
Default legacy checkpoints may omit identity fields; conflicting identity,
malformed or unsupported state, unknown modules and unsafe paths still stop
recovery. There is no fallback to selecting every module after a validation
failure.

For a self-managed `~/.acfs` checkout whose old updater lacks generation
support, recovery requires a clean fast-forward to the selected revision.
If local tracked work blocks that transition, preserve and reconcile it first;
the command reports failure instead of overwriting it or claiming the public
updater was repaired. Preparation failure preserves the previous runtime.

After successful recovery, rerun the ordinary update command with the original
category options. That run uses the saved installation scope to finish normal
deployment and tool updates. `--repair-runtime --dry-run` previews recovery
without fetching, staging or publishing anything. It does not validate a new
candidate. No recovery mode disables installer checksum authentication.

## Scope and rollout

This changes lock identity from an invoking-UID file in `/tmp` to a target-home
directory. **Finish all older updater processes, including queued invocations,
before deploying the change.** Older versions do not acquire the new directory
lock. Do not mix the two locking protocols during a running update.

`ACFS_UPDATE_LOCK` is no longer a lock-path override; caller-supplied values
cannot split exclusion or redirect a write into another file. `TMPDIR` and
`XDG_RUNTIME_DIR` do not affect lock identity either.

Different target homes can proceed independently. Package managers retain their
own system-package locks. This guard does not serialize arbitrary shared external
Cargo/Rustup directories, shared Git checkouts, or third-party programs outside
this updater. Do not concurrently relocate the target home during an update.

The implementation requires Linux `/proc/self/fd` and working directory `flock`
support. On a filesystem without that support, admission fails rather than
pretending the update is protected. The underlying lock and exec semantics are
documented in [flock(1)](https://man7.org/linux/man-pages/man1/flock.1.html) and
[flock(2)](https://man7.org/linux/man-pages/man2/flock.2.html).

## Validation

```sh
python3 -B tests/unit/test_update_lock.py
bash -n scripts/lib/update.sh
shellcheck scripts/lib/update.sh
```

The regression suite extracts the actual startup section before repository
discovery, then appends a synchronized worker in place of the protected update.
It exercises real Bash processes, kernel locks, filesystem operations, waits and
exec, without calling package managers, networking, self-update downloads or
services. Cross-UID cases require root and an unprivileged `nobody` account. The
missing-executable case uses a private minimal filesystem with the real Bash
binary and its dynamic libraries, deliberately without `flock`. A writable
regular file stands in for that private filesystem's stderr sink `/dev/null`.
Fixtures are retained. These tests are not a live end-to-end update acceptance.
