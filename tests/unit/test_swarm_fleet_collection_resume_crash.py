#!/usr/bin/env python3
"""Real process-death, competing writers and file boundaries for collection resume."""
import importlib.util
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
_spec = importlib.util.spec_from_file_location("resume_fixtures", Path(__file__).with_name("test_swarm_fleet_collection_resume.py"))
support = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(support)
collect, fleet, Fixture = support.collect, support.fleet, support.Fixture


class ResumeCrashTests(unittest.TestCase):
    def setUp(self):
        self.assertNotEqual(os.geteuid(), 0, "Exercise actual unprivileged production behavior")

    def kill_writer(self, fx, filename, resume_digest=None, *, torn=False):
        """Kill after a real fsynced publication, or a deliberately torn write."""
        program = f'''
import importlib.util, os, signal, subprocess
spec = importlib.util.spec_from_file_location("actual_collector", {str(Path(collect.__file__).resolve())!r})
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)
def invoke(host, base, mode, snapshot=None):
    result = subprocess.run(["/bin/bash", "--noprofile", "--norc", "-p", "-c",
                             c.remote_command(host, base, mode, snapshot, 10)],
                            capture_output=True, timeout=20)
    return result.returncode, result.stdout
def wrap(original):
    def write(fd, name, value):
        if name == {filename!r} and {torn!r}:
            raw = value if isinstance(value, bytes) else c.encoded(value)
            handle = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
            os.write(handle, raw[:17])
            os.fsync(handle)
            os.fsync(fd)
            os.kill(os.getpid(), signal.SIGKILL)
        result = original(fd, name, value)
        if name == {filename!r}:
            os.kill(os.getpid(), signal.SIGKILL)
        return result
    return write
c.publish_bundle = wrap(c.publish_bundle)
c.fleet.publish = wrap(c.fleet.publish)
args = dict(launch_path={str(fx.launch)!r}, selection={fx.selection!r}, known={fx.known!r}, identity={fx.key!r},
            output_dir={str(fx.out)!r}, timeout=90, approval={fx.approval!r}, invoke=invoke)
if {resume_digest is not None!r}:
    c.resume_collection(**args, resume_approval={resume_digest!r})
else:
    c.execute(**args)
raise SystemExit("test did not reach requested publication boundary")
'''
        killed = subprocess.run([sys.executable, "-I", "-B", "-c", program], env=fx.git.env,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(killed.returncode, -signal.SIGKILL, killed.stdout + killed.stderr)

    def finish(self, fx, expected_calls):
        preview, code = fx.resume()
        self.assertEqual(code, 0, preview)
        result, code = fx.resume(preview["resume_plan_sha256"])
        self.assertEqual((code, result["status"]), (0, "collected"))
        self.assertEqual(fx.calls, expected_calls)
        self.assertEqual(collect.verify(fx.out)["status"], "verified")
        return result

    def test_sigkill_after_initial_intent_resumes_without_restarting_agents(self):
        fx = Fixture()
        before = fx.git.contents(fx.launch)
        self.kill_writer(fx, "intent.json")
        self.assertEqual(set(os.listdir(fx.out)), {"intent.json"})
        self.finish(fx, [("alpha", "collect"), ("beta", "collect")])
        self.assertEqual(fx.git.contents(fx.launch), before)

    def test_sigkill_after_initial_bundle_reuses_it_without_remote_contact(self):
        fx = Fixture()
        self.kill_writer(fx, "alpha.bundle")
        path = fx.out / "alpha.bundle"
        raw, inode = path.read_bytes(), path.stat().st_ino
        self.finish(fx, [("beta", "collect")])
        self.assertEqual((path.read_bytes(), path.stat().st_ino), (raw, inode))

    def test_sigkill_after_resumed_last_bundle_needs_fresh_approval_and_only_manifest(self):
        for fmt in ("sha1", "sha256"):
            with self.subTest(fmt=fmt):
                fx = Fixture(fmt)
                fx.partial()
                preview, _ = fx.resume()
                self.kill_writer(fx, "beta.bundle", preview["resume_plan_sha256"])
                self.assertFalse((fx.out / "manifest.json").exists())
                before = fx.git.contents(fx.out)
                with patch.object(collect, "observe", side_effect=AssertionError("downloaded retained history")):
                    with self.assertRaisesRegex(fleet.Refused, "collection_resume_approval_mismatch"):
                        fx.resume(preview["resume_plan_sha256"])
                    fresh, _ = fx.resume()
                    self.assertNotEqual(fresh["resume_plan_sha256"], preview["resume_plan_sha256"])
                    self.assertEqual(fresh["resume_plan"]["pending_hosts"], [])
                    result = self.finish(fx, [])
                self.assertFalse(result["network_access"])
                for name, value in before.items():
                    self.assertEqual(fx.git.contents(fx.out)[name], value)

    def test_sigkill_after_final_manifest_is_verified_not_republished(self):
        fx = Fixture()
        fx.partial()
        preview, _ = fx.resume()
        self.kill_writer(fx, "manifest.json", preview["resume_plan_sha256"])
        before = fx.git.contents(fx.out)
        with patch.object(collect, "observe", side_effect=AssertionError("contacted a completed host")), \
             patch.object(fleet, "publish", side_effect=AssertionError("rewrote final evidence")):
            fresh, code = fx.resume()
            self.assertEqual((code, fresh["status"]), (0, "verified"))
            result, code = fx.resume(fresh["resume_plan_sha256"])
            self.assertEqual((code, result["status"]), (0, "verified"))
        self.assertFalse(result["collection_resume_writes_started"])
        self.assertEqual(fx.git.contents(fx.out), before)

    def test_sigkill_during_bundle_or_manifest_write_preserves_torn_evidence(self):
        for name in ("beta.bundle", "manifest.json"):
            with self.subTest(name=name):
                fx = Fixture()
                fx.partial()
                preview, _ = fx.resume()
                self.kill_writer(fx, name, preview["resume_plan_sha256"], torn=True)
                self.assertEqual((fx.out / name).stat().st_size, 17)
                before = fx.git.contents(fx.out)
                with patch.object(collect, "observe", side_effect=AssertionError("tried recapturing damaged evidence")):
                    with self.assertRaises(fleet.Refused):
                        fx.resume()
                self.assertEqual(fx.git.contents(fx.out), before)

    def test_progress_before_second_remote_failure_is_not_downloaded_again(self):
        fx = Fixture()
        fx.partial(fail="alpha")
        preview, _ = fx.resume()
        def fail_beta(host, base, mode, snapshot=None):
            return (255, b"") if host["id"] == "beta" else fx.invoke(host, base, mode, snapshot)
        report, code = fx.resume(preview["resume_plan_sha256"], invoke=fail_beta)
        self.assertEqual((code, report["status"]), (1, "partial"))
        self.assertTrue(report["collection_resume_writes_started"])
        self.assertEqual([a["id"] for a in report["artifacts"]], ["alpha"])
        self.assertFalse((fx.out / "manifest.json").exists())
        fx.calls.clear()
        with self.assertRaisesRegex(fleet.Refused, "collection_resume_approval_mismatch"):
            fx.resume(preview["resume_plan_sha256"])
        self.finish(fx, [("beta", "collect")])

    def test_competing_bundle_or_manifest_writer_is_not_overwritten(self):
        for name in ("beta.bundle", "manifest.json"):
            with self.subTest(name=name):
                fx = Fixture()
                fx.partial()
                preview, _ = fx.resume()
                saved = (fx.out / "alpha.bundle").read_bytes()
                target = collect if name.endswith(".bundle") else fleet
                method = "publish_bundle" if name.endswith(".bundle") else "publish"
                original = getattr(target, method)
                def competing(fd, filename, value):
                    if filename == name:
                        with os.fdopen(os.open(filename, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                              0o600, dir_fd=fd), "wb") as stream:
                            stream.write(b"competing writer owns this file\n")
                            stream.flush()
                            os.fsync(stream.fileno())
                    return original(fd, filename, value)
                with patch.object(target, method, competing), self.assertRaises(FileExistsError):
                    fx.resume(preview["resume_plan_sha256"])
                self.assertEqual((fx.out / name).read_bytes(), b"competing writer owns this file\n")
                self.assertEqual((fx.out / "alpha.bundle").read_bytes(), saved)
                self.assertTrue(collect.RESUME_WRITES_STARTED)
                with self.assertRaises(fleet.Refused):
                    fx.resume()

    def test_launch_and_collection_locks_refuse_real_competing_processes(self):
        fx = Fixture()
        fx.partial()
        before = fx.git.contents(fx.out)
        for directory in (fx.launch, fx.out):
            with self.subTest(directory=directory):
                program = f'''
import fcntl, os, sys
fd = os.open({str(directory)!r}, os.O_RDONLY | os.O_DIRECTORY)
fcntl.flock(fd, fcntl.LOCK_EX)
print("locked", flush=True)
sys.stdin.buffer.read(1)
'''
                with subprocess.Popen([sys.executable, "-I", "-B", "-c", program], env=fx.git.env,
                                      stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as holder:
                    try:
                        with selectors.DefaultSelector() as poll:
                            poll.register(holder.stdout, selectors.EVENT_READ)
                            self.assertTrue(poll.select(10), "lock child did not become ready")
                            self.assertEqual(os.read(holder.stdout.fileno(), 7), b"locked\n")
                        with self.assertRaisesRegex(fleet.Refused, "fleet_operation_in_progress"):
                            fx.resume()
                    finally:
                        if holder.poll() is None:
                            holder.communicate(input=b"x", timeout=10)
                self.assertEqual(fx.calls, [])
                self.assertEqual(fx.git.contents(fx.out), before)

    def test_replaced_directory_cannot_reuse_original_resume_approval(self):
        fx = Fixture()
        fx.partial()
        preview, _ = fx.resume()
        previous = fx.root / "retained-original-collection"
        fx.out.rename(previous)
        fx.out.mkdir(mode=0o700)
        for source in previous.iterdir():
            destination = fx.out / source.name
            destination.write_bytes(source.read_bytes())
            destination.chmod(0o600)
        before = fx.git.contents(fx.out)
        with self.assertRaisesRegex(fleet.Refused, "collection_resume_approval_mismatch"):
            fx.resume(preview["resume_plan_sha256"])
        self.assertEqual(fx.calls, [])
        self.assertEqual(fx.git.contents(fx.out), before)
        self.assertEqual(fx.git.contents(previous), before)

    def test_unsafe_retained_bundle_is_never_followed_or_replaced(self):
        for kind in ("symlink", "hardlink", "fifo", "public"):
            with self.subTest(kind=kind):
                fx = Fixture()
                fx.partial()
                path = fx.out / "alpha.bundle"
                retained = fx.root / "retained-original.bundle"
                raw = path.read_bytes()
                if kind == "public":
                    path.chmod(0o644)
                else:
                    path.rename(retained)
                    if kind == "symlink":
                        path.symlink_to(retained)
                    elif kind == "hardlink":
                        os.link(retained, path)
                    else:
                        os.mkfifo(path, 0o600)
                identity = path.lstat().st_ino
                with self.assertRaises((fleet.Refused, OSError)):
                    fx.resume()
                self.assertEqual(path.lstat().st_ino, identity)
                self.assertEqual((path if kind == "public" else retained).read_bytes(), raw)
                self.assertEqual(fx.calls, [])
                self.assertFalse((fx.out / "beta.bundle").exists())


if __name__ == "__main__":
    if os.geteuid() == 0:
        os.setgroups([])
        os.setgid(65534)
        os.setuid(65534)
        os.execv(sys.executable, [sys.executable, "-B", __file__, *sys.argv[1:]])
    unittest.main()
