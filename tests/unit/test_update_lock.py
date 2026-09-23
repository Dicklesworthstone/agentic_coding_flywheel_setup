"""Run the updater's actual startup in isolated processes, never its updates.

The source is cut immediately before repository discovery. A tiny worker then
stands in for the protected operation. Locking, home resolution and re-exec run
as written in update.sh, with real Bash, Linux flock and filesystem operations.
No package manager, network request or service is invoked. Fixtures are retained.
"""
import contextlib
import fcntl
import os
from pathlib import Path
import pwd
import re
import select
import shlex
import shutil
import signal
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "scripts/lib/update.sh"
BOUNDARY = "# Discover ACFS_REPO_ROOT: prefer a real git repo over the tarball install dir."
WORKER = r'''
case "${1:-}" in
    --exec)
        printf 'before-exec\n'
        IFS= read -r _ || exit 91
        export ACFS_SELF_UPDATE_DONE=true
        exec /bin/bash "$0" --hold
        ;;
    --child)
        if /bin/bash "$0" --quick; then result=0; else result=$?; fi
        printf 'child-result:%s\n' "$result"
        ;;
esac
printf 'entered\n'
printf 'stderr-survives\n' >&2
if [[ "${1:-}" == --hold ]]; then IFS= read -r _ || true; fi
'''


class UpdateLockTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.name != "posix" or not Path("/proc/self/fd").is_dir() or not shutil.which("flock"):
            raise unittest.SkipTest("requires Linux, Bash and util-linux flock")
        source = SOURCE.read_text()
        if source.count(BOUNDARY) != 1:
            raise AssertionError("updater startup boundary moved; review this harness")
        cls.startup = source.split(BOUNDARY, 1)[0]

    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="acfs-update-lock-test-"))
        self.base.chmod(0o755)
        self.home = self.base / "home"
        self.home.mkdir(mode=0o755)
        self.runner = self.base / "update-startup.sh"
        self.runner.write_text(self.startup + WORKER)
        self.runner.chmod(0o644)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(("ACFS_", "_ACFS_", "BASH_FUNC_"))}
        for key in ("TARGET_HOME", "TARGET_USER", "BASH_ENV", "ENV", "CDPATH"):
            self.env.pop(key, None)
        self.env.update(HOME=str(self.home), PATH="/usr/bin:/bin", NO_COLOR="1",
                        ACFS_UPDATE_LOCK=str(self.base / "legacy-lock"))
        self.processes = []
        self.addCleanup(self.stop_processes)

    def stop_processes(self):
        for process in self.processes:
            if process.poll() is None:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGKILL)
            process.communicate(timeout=5)

    def start(self, argument="--hold", *, env=None, before=None, uid=None):
        command = ["/bin/bash", str(self.runner), argument]
        if before is not None:
            command = ["/bin/bash", "-c", before + '; exec /bin/bash "$1" "$2"', "fixture", str(self.runner), argument]
        kwargs = {}
        if uid is not None:
            kwargs.update(user=uid, group=uid, extra_groups=[])
        process = subprocess.Popen(command, env=env or self.env, stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   start_new_session=True, **kwargs)
        self.processes.append(process)
        return process

    def line(self, process, stream="stdout"):
        pipe = getattr(process, stream)
        ready, _, _ = select.select([pipe], [], [], 5)
        self.assertTrue(ready, "worker did not produce the expected synchronization line")
        return pipe.readline().decode().strip()

    def quick(self, *, env=None, before=None, uid=None):
        process = self.start("--quick", env=env, before=before, uid=uid)
        out, err = process.communicate(timeout=5)
        return process.returncode, out.decode(), err.decode()

    def holder(self, **kwargs):
        process = self.start(**kwargs)
        self.assertEqual(self.line(process), "entered")
        return process

    def release(self, process):
        process.stdin.write(b"done\n")
        process.stdin.flush()
        process.wait(timeout=5)

    def test_success_is_read_only_and_keeps_stderr(self):
        code, out, err = self.quick()
        self.assertEqual((code, out), (0, "entered\n"))
        self.assertIn("stderr-survives", err)
        self.assertEqual(list(self.home.iterdir()), [])
        self.assertFalse((self.base / "legacy-lock").exists())

    def test_second_update_reports_busy_not_success(self):
        self.holder()
        code, out, err = self.quick()
        self.assertEqual(code, 75)
        self.assertEqual(out, "")
        self.assertIn("no update was performed", err)

    def test_self_update_environment_flag_cannot_bypass_lock(self):
        self.holder()
        code, out, _ = self.quick(env={**self.env, "ACFS_SELF_UPDATE_DONE": "true"})
        self.assertEqual(code, 75)
        self.assertEqual(out, "")

    def test_lock_path_environment_cannot_split_exclusion(self):
        self.holder()
        alternate = self.base / "another-lock"
        code, out, _ = self.quick(env={**self.env, "ACFS_UPDATE_LOCK": str(alternate)})
        self.assertEqual(code, 75)
        self.assertEqual(out, "")
        self.assertFalse(alternate.exists())

    def test_old_lock_path_cannot_truncate_a_symlink_target(self):
        victim = self.base / "do-not-touch"
        victim.write_bytes(b"original contents\n")
        path = self.base / "legacy-link"
        path.symlink_to(victim)
        code, _, _ = self.quick(env={**self.env, "ACFS_UPDATE_LOCK": str(path)})
        self.assertEqual(code, 0)
        self.assertEqual(victim.read_bytes(), b"original contents\n")
        self.assertTrue(path.is_symlink())

    def test_tmp_and_runtime_directories_do_not_change_lock_identity(self):
        self.holder()
        env = {**self.env, "TMPDIR": str(self.base / "absent"), "XDG_RUNTIME_DIR": "/run/user/0"}
        self.assertEqual(self.quick(env=env)[0], 75)

    def test_symlink_alias_to_home_contends_on_same_inode(self):
        self.holder()
        alias = self.base / "home-alias"
        alias.symlink_to(self.home, target_is_directory=True)
        self.assertEqual(self.quick(env={**self.env, "HOME": str(alias)})[0], 75)

    def test_explicit_target_home_is_locked_not_callers_home(self):
        self.holder()
        caller = self.base / "caller-home"
        caller.mkdir()
        env = {**self.env, "HOME": str(caller), "TARGET_HOME": str(self.home)}
        self.assertEqual(self.quick(env=env)[0], 75)
        self.assertEqual(list(caller.iterdir()), [])

    def test_independent_homes_can_update_in_parallel(self):
        self.holder()
        other = self.base / "other-home"
        other.mkdir()
        self.assertEqual(self.quick(env={**self.env, "HOME": str(other)})[0], 0)

    def test_wait_enters_only_after_previous_update_exits(self):
        holder = self.holder()
        waiter = self.start(env={**self.env, "ACFS_UPDATE_LOCK_WAIT": "1"})
        self.assertIn("waiting", self.line(waiter, "stderr"))
        self.assertEqual(select.select([waiter.stdout], [], [], 0.1)[0], [])
        self.release(holder)
        self.assertEqual(self.line(waiter), "entered")
        self.release(waiter)

    def test_wait_rejects_home_replacement_before_protected_operation(self):
        holder = self.holder()
        waiter = self.start(env={**self.env, "ACFS_UPDATE_LOCK_WAIT": "1"})
        self.assertIn("waiting", self.line(waiter, "stderr"))
        moved = self.base / "original-home"
        self.home.rename(moved)
        self.home.mkdir()
        self.release(holder)
        out, err = waiter.communicate(timeout=5)
        self.assertEqual(waiter.returncode, 1)
        self.assertEqual(out, b"")
        self.assertIn(b"target home changed", err)
        self.assertEqual(list(self.home.iterdir()), [])
        self.assertEqual(list(moved.iterdir()), [])

    def test_self_exec_preserves_exclusion_while_a_waiter_is_queued(self):
        holder = self.start("--exec")
        self.assertEqual(self.line(holder), "before-exec")
        waiter = self.start(env={**self.env, "ACFS_UPDATE_LOCK_WAIT": "1"})
        self.assertIn("waiting", self.line(waiter, "stderr"))
        holder.stdin.write(b"exec-now\n")
        holder.stdin.flush()
        self.assertEqual(self.line(holder), "entered")
        self.assertEqual(select.select([waiter.stdout], [], [], 0.1)[0], [])
        self.release(holder)
        self.assertEqual(self.line(waiter), "entered")
        self.release(waiter)

    def test_child_does_not_inherit_permission_to_start_nested_update(self):
        process = self.start("--child")
        out, _ = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0)
        self.assertEqual(out, b"child-result:75\nentered\n")

    def test_forged_process_marker_without_descriptor_fails_closed(self):
        code, out, err = self.quick(before='export _ACFS_UPDATE_LOCK_PID="$BASHPID"; exec 9<&-')
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertIn("inherited lock", err)

    def test_matching_descriptor_without_kernel_lock_still_contends(self):
        self.holder()
        code, out, _ = self.quick(before='exec 9<"$HOME/."; export _ACFS_UPDATE_LOCK_PID="$BASHPID"')
        self.assertEqual(code, 75)
        self.assertEqual(out, "")

    def test_inherited_descriptor_for_wrong_directory_fails_closed(self):
        code, out, _ = self.quick(before='exec 9</.; export _ACFS_UPDATE_LOCK_PID="$BASHPID"')
        self.assertEqual(code, 1)
        self.assertEqual(out, "")

    def test_independent_kernel_lock_blocks_updater(self):
        fd = os.open(self.home, os.O_RDONLY | os.O_DIRECTORY)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertEqual(self.quick()[0], 75)
        finally:
            os.close(fd)

    def test_killed_holder_does_not_leave_a_stale_lock_file(self):
        holder = self.holder()
        os.killpg(holder.pid, signal.SIGKILL)
        holder.wait(timeout=5)
        self.assertEqual(self.quick()[0], 0)
        self.assertFalse((self.base / "legacy-lock").exists())

    def test_help_does_not_acquire_or_require_a_lock(self):
        self.holder()
        helper = self.start("--help", env={**self.env, "TARGET_USER": "acfs_nonexistent_user_9381"})
        out, _ = helper.communicate(timeout=5)
        self.assertEqual(helper.returncode, 0)
        # The fixture body stands in for usage; it is never a real update.
        self.assertEqual(out, b"entered\n")

    def test_sourcing_does_not_lock_or_close_callers_descriptor(self):
        self.holder()
        command = f'exec 9<"$HOME/."; source {shlex.quote(str(self.runner))}; [[ "$HOME" -ef /proc/self/fd/9 ]]; printf "source-returned\\n"'
        result = subprocess.run(["/bin/bash", "-c", command], env=self.env,
                                capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertTrue(result.stdout.endswith(b"source-returned\n"))

    def test_unknown_target_user_cannot_fall_back_to_callers_home(self):
        code, out, err = self.quick(env={**self.env, "TARGET_USER": "acfs_nonexistent_user_9381"})
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertIn("resolve", err)
        self.assertFalse((self.base / "legacy-lock").exists())

    def test_invalid_wait_policy_is_rejected_before_operation(self):
        for value in ("yes", "2", "-1", "true", "$(touch unwanted)"):
            with self.subTest(value=value):
                code, out, _ = self.quick(env={**self.env, "ACFS_UPDATE_LOCK_WAIT": value})
                self.assertEqual(code, 1)
                self.assertEqual(out, "")

    def test_root_and_unprivileged_user_share_target_home_lock(self):
        if os.geteuid() != 0:
            self.skipTest("cross-UID acceptance needs root")
        account = pwd.getpwnam("nobody")
        holder = self.holder()
        env = {**self.env, "ACFS_UPDATE_LOCK": str(self.home / "other-uid-legacy-lock")}
        os.chown(self.home, account.pw_uid, account.pw_gid)
        self.assertEqual(self.quick(env=env, uid=account.pw_uid)[0], 75)
        self.release(holder)
        self.assertEqual(self.quick(env=env, uid=account.pw_uid)[0], 0)

    def test_unreadable_target_home_fails_closed(self):
        if os.geteuid() != 0:
            self.skipTest("unreadable-home acceptance needs a separate unprivileged UID")
        account = pwd.getpwnam("nobody")
        self.home.chmod(0o000)
        code, out, err = self.quick(uid=account.pw_uid)
        self.assertNotEqual(code, 0)
        self.assertEqual(out, "")
        self.assertIn("refusing", err)

    def test_exported_flock_function_cannot_fake_kernel_success(self):
        self.holder()
        code, out, _ = self.quick(before='flock() { return 0; }; export -f flock')
        self.assertEqual(code, 75)
        self.assertEqual(out, "")

    def test_fifo_replacement_while_waiting_cannot_hang_or_enter(self):
        holder = self.holder()
        waiter = self.start(env={**self.env, "ACFS_UPDATE_LOCK_WAIT": "1"})
        self.assertIn("waiting", self.line(waiter, "stderr"))
        self.home.rename(self.base / "original-home")
        os.mkfifo(self.home)
        self.release(holder)
        out, err = waiter.communicate(timeout=5)
        self.assertEqual(waiter.returncode, 1)
        self.assertEqual(out, b"")
        self.assertIn(b"target home changed", err)

    def test_missing_system_flock_fails_in_real_minimal_root(self):
        chroot = shutil.which("chroot")
        if os.geteuid() != 0 or chroot is None or shutil.which("ldd") is None:
            self.skipTest("minimal-root acceptance requires root, chroot and ldd")
        jail = self.base / "minimal-root"
        for name in ("bin", "scripts", "home", "dev"):
            (jail / name).mkdir(parents=True, exist_ok=True)
        shutil.copyfile("/bin/bash", jail / "bin/bash")
        (jail / "bin/bash").chmod(0o755)
        # Copy the actual dynamic loader/libraries, not fake executable probes.
        linked = subprocess.run([shutil.which("ldd"), "/bin/bash"], capture_output=True,
                                text=True, check=True, timeout=5).stdout
        for library in set(re.findall(r"(/[A-Za-z0-9_./+-]+)", linked)):
            destination = jail / library.lstrip("/")
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(library, destination)
            shutil.copymode(library, destination)
        # A writable sink is sufficient for startup's stderr redirections;
        # there is deliberately no flock anywhere in this private root.
        (jail / "dev/null").touch()
        (jail / "scripts/update-startup.sh").write_text(self.startup + WORKER)
        result = subprocess.run([chroot, str(jail), "/bin/bash", "/scripts/update-startup.sh", "--quick"],
                                env={**self.env, "HOME": "/home"}, capture_output=True, timeout=5)
        if result.stderr.startswith(b"chroot: cannot change root directory") and b"Operation not permitted" in result.stderr:
            self.skipTest("container lacks permission to enter a private root")
        self.assertEqual(result.returncode, 127, result.stderr.decode())
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"system flock is required", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
