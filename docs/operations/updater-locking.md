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

`--help` and `-h` bypass admission, and sourcing `update.sh` does not acquire a
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
