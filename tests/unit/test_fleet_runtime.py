#!/usr/bin/env python3
"""Exercise the real frontend and installer; controller peers never contact hosts."""
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[2] / "scripts/acfs-fleet.py"
spec = importlib.util.spec_from_file_location("fleet_runtime", SOURCE)
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        # Fixtures inherit the umask; a login user's 0002 makes them group-writable.
        self.addCleanup(os.umask, os.umask(0o022))
        # Fixtures intentionally retained. Never run cleanup against user data.
        self.root = Path(tempfile.mkdtemp(prefix="acfs-runtime-test-"))
        self.root.chmod(0o755)
        self.uid = 65534 if os.geteuid() == 0 else os.geteuid()
        self.gid = 65534 if os.geteuid() == 0 else os.getegid()
        self.credentials = {"user": self.uid, "group": self.gid} if os.geteuid() == 0 else {}
        self.home = self.root / "home"
        self.home.mkdir(mode=0o700)
        self.own(self.home)
        self.prefix, self.bin_dir = self.home / "fleet", self.home / "bin"
        for directory in (self.prefix, self.bin_dir):
            directory.mkdir(mode=0o700)
            self.own(directory)
        self.checkout = self.root / "checkout"
        self.checkout.mkdir(mode=0o755)
        (self.checkout / "acfs-fleet.py").write_bytes(SOURCE.read_bytes())
        self.peer = '''import json, os, signal, sys
if "--signal" in sys.argv: os.kill(os.getpid(), signal.SIGTERM)
if "--echo-stdin" in sys.argv: print(sys.stdin.read(), end="")
else: print(json.dumps({"argv":sys.argv[1:],"cwd":os.getcwd(),"uid":os.geteuid(),"isolated":sys.flags.isolated}))
if "--exit" in sys.argv: sys.exit(23)
'''
        for name in runtime.COMMANDS.values():
            (self.checkout / name).write_text(self.peer)
        self.env = {"HOME": str(self.home), "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"}
        self.command = [sys.executable, "-I", str(self.checkout / "acfs-fleet.py")]

    def own(self, path):
        if os.geteuid() == 0:
            os.chown(path, self.uid, self.gid)

    def run_cli(self, args, *, installed=False, input=None, env=None):
        command = [str(self.bin_dir / "acfs-fleet")] if installed else self.command
        return subprocess.run([*command, *args], input=input, encoding="utf-8", capture_output=True,
                              timeout=10, cwd=self.home, env=env or self.env, **self.credentials)

    def options(self):
        return ["install", "--prefix", str(self.prefix), "--bin-dir", str(self.bin_dir)]

    def preview(self):
        result = self.run_cli(self.options())
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def install(self):
        preview = self.preview()
        result = self.run_cli([*self.options(), "--apply", "--accept-plan", preview["plan_sha256"]])
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def members(self, root):
        return {str(p.relative_to(root)): ("link", os.readlink(p)) if p.is_symlink()
                else ("dir", p.stat().st_mode & 0o777) if p.is_dir()
                else ("file", p.stat().st_mode & 0o777, p.read_bytes()) for p in root.rglob("*")}

    def test_preview_is_repeatable_and_creates_nothing(self):
        before = self.members(self.home)
        first, second = self.preview(), self.preview()
        self.assertEqual(first, second)
        self.assertEqual(first["status"], "preview")
        self.assertEqual(set(first["plan"]["files"]), set(runtime.FILES))
        self.assertFalse(first["plan"]["network_access"])
        self.assertEqual(self.members(self.home), before)

    def test_complete_install_runs_every_controller_without_checkout(self):
        report = self.install()
        release = self.prefix / "releases" / report["runtime"]
        self.assertEqual(set(p.name for p in release.iterdir()), set(runtime.FILES) | {runtime.MANIFEST})
        self.assertEqual(release.stat().st_mode & 0o777, 0o500)
        self.assertEqual((release / "acfs-fleet.py").stat().st_mode & 0o777, 0o500)
        self.assertEqual((release / "runtime.json").stat().st_mode & 0o777, 0o400)
        # Make the checkout unavailable; installed commands cannot depend on it.
        self.checkout.rename(self.root / "retained-source")
        for command in runtime.COMMANDS:
            result = self.run_cli([command, "--help"], installed=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            parsed = json.loads(result.stdout)
            self.assertEqual(parsed["argv"], ["--help"])
            self.assertEqual(parsed["uid"], self.uid)
            self.assertEqual(parsed["isolated"], 1)
        version = self.run_cli(["version"], installed=True)
        self.assertEqual(json.loads(version.stdout)["runtime"], report["runtime"])

    def test_argv_stdin_cwd_and_nonzero_exit_are_preserved(self):
        self.install()
        args = ["--resume", "--accept-plan", "0" * 64, "$(touch SHOULD_NOT_EXIST)", "spaces here", "", "--exit"]
        result = self.run_cli(["prepare", *args], installed=True)
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual(json.loads(result.stdout)["argv"], args)
        self.assertEqual(json.loads(result.stdout)["cwd"], str(self.home))
        echo = self.run_cli(["dispatch", "--echo-stdin"], installed=True, input="not a shell\n")
        self.assertEqual(echo.stdout, "not a shell\n")
        self.assertFalse((self.home / "SHOULD_NOT_EXIST").exists())
        killed = self.run_cli(["launch", "--signal"], installed=True)
        self.assertEqual(killed.returncode, -signal.SIGTERM)

    def test_updated_install_retains_old_release_and_changes_launcher_atomically(self):
        first = self.install()
        old = self.prefix / "releases" / first["runtime"]
        before = self.members(old)
        (self.checkout / "swarm-fleet-launch.py").write_text(self.peer + "# new release\n")
        second = self.install()
        self.assertNotEqual(first["runtime"], second["runtime"])
        self.assertEqual(self.members(old), before)
        self.assertEqual(os.readlink(self.bin_dir / "acfs-fleet"), second["pinned_launcher"])
        self.assertEqual(len(list((self.prefix / "releases").iterdir())), 2)
        # The retained entrypoint stays independently usable for old journals.
        pinned = subprocess.run([first["pinned_launcher"], "version"], capture_output=True, text=True,
                                timeout=10, env=self.env, **self.credentials)
        self.assertEqual(pinned.returncode, 0, pinned.stderr)
        self.assertEqual(json.loads(pinned.stdout)["runtime"], first["runtime"])

    def test_reinstall_same_release_is_noop(self):
        self.install()
        before = self.members(self.home)
        self.install()
        self.assertEqual(self.members(self.home), before)

    def test_source_changes_invalidate_approval_without_writes(self):
        preview = self.preview()
        (self.checkout / "swarm-fleet-dispatch.py").write_text(self.peer + "# changed\n")
        result = self.run_cli([*self.options(), "--apply", "--accept-plan", preview["plan_sha256"]])
        self.assertEqual(result.returncode, 2)
        self.assertIn("installation_approval_mismatch", result.stderr)
        self.assertFalse((self.prefix / "releases").exists())

    def test_bin_directory_replacement_invalidates_approval(self):
        preview = self.preview()
        self.bin_dir.rename(self.home / "retained-bin")
        self.bin_dir.mkdir(mode=0o700)
        self.own(self.bin_dir)
        result = self.run_cli([*self.options(), "--apply", "--accept-plan", preview["plan_sha256"]])
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.prefix / "releases").exists())

    def test_unrelated_launchers_are_never_overwritten(self):
        path = self.bin_dir / "acfs-fleet"
        path.write_text("user command")
        self.own(path)
        result = self.run_cli(self.options())
        self.assertEqual(result.returncode, 2)
        self.assertEqual(path.read_text(), "user command")
        path.rename(self.home / "original-command")
        path.symlink_to(self.home / "original-command")
        self.own(path)
        result = self.run_cli(self.options())
        self.assertEqual(result.returncode, 2)
        self.assertEqual(os.readlink(path), str(self.home / "original-command"))

    def test_damaged_release_prevents_execution_and_reinstallation(self):
        report = self.install()
        target = Path(report["pinned_launcher"]).parent / "swarm-fleet-prepare.py"
        target.chmod(0o600)
        target.write_text("raise RuntimeError('must not run')\n")
        target.chmod(0o400)
        result = self.run_cli(["launch"], installed=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("runtime_integrity_mismatch", result.stderr)
        result = self.run_cli(self.options())
        self.assertEqual(result.returncode, 2)
        self.assertEqual(target.read_text(), "raise RuntimeError('must not run')\n")

    def test_missing_manifest_cannot_fall_back_to_checkout_mode(self):
        report = self.install()
        root = Path(report["pinned_launcher"]).parent
        root.chmod(0o700)
        (root / runtime.MANIFEST).rename(root / "retained-manifest.json")
        root.chmod(0o500)
        result = self.run_cli(["launch"], installed=True)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")

    def test_partial_release_is_retained_without_activation(self):
        preview = self.preview()
        releases = self.prefix / "releases"
        releases.mkdir(mode=0o700)
        self.own(releases)
        partial = releases / preview["plan"]["runtime"]
        partial.mkdir(mode=0o700)
        self.own(partial)
        marker = partial / "partial-evidence"
        marker.write_text("retain")
        self.own(marker)
        result = self.run_cli([*self.options(), "--apply", "--accept-plan", preview["plan_sha256"]])
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.bin_dir / "acfs-fleet").exists())
        self.assertEqual(marker.read_text(), "retain")

    def test_sibling_links_fifos_and_broken_python_are_refused(self):
        path = self.checkout / "swarm-fleet-prepare.py"
        original = self.checkout / "saved-controller"
        path.rename(original)
        path.symlink_to(original)
        self.assertEqual(self.run_cli(self.options()).returncode, 2)
        path.rename(self.checkout / "saved-link")
        os.mkfifo(path)
        self.assertEqual(self.run_cli(self.options()).returncode, 2)
        path.rename(self.checkout / "saved-fifo")
        path.write_text("not valid Python !\n")
        self.assertEqual(self.run_cli(self.options()).returncode, 2)
        self.assertFalse((self.prefix / "releases").exists())

    def test_unsafe_directories_and_nested_destination_are_refused(self):
        self.bin_dir.chmod(0o777)
        self.assertEqual(self.run_cli(self.options()).returncode, 2)
        self.bin_dir.chmod(0o700)
        alias = self.home / "alias"
        alias.symlink_to(self.prefix, target_is_directory=True)
        self.assertEqual(self.run_cli(["install", "--prefix", str(alias), "--bin-dir", str(self.bin_dir)]).returncode, 2)
        self.assertEqual(self.run_cli(["install", "--prefix", str(self.prefix), "--bin-dir", str(self.prefix)]).returncode, 2)

    def test_approval_flags_unknown_commands_and_sudo_are_refused(self):
        for args in ([*self.options(), "--apply"], [*self.options(), "--accept-plan", "0" * 64],
                     ["unknown"], ["version", "--apply"]):
            result = self.run_cli(args)
            self.assertEqual(result.returncode, 2, result.stdout)
        result = self.run_cli(self.options(), env={**self.env, "SUDO_USER": "test"})
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.prefix / "releases").exists())

    def test_python_startup_hooks_and_path_controllers_do_not_override_runtime(self):
        self.install()
        module = self.home / "sitecustomize.py"
        module.write_text("raise SystemExit('INJECTED')")
        result = self.run_cli(["launch", "--help"], installed=True,
                              env={**self.env, "PYTHONPATH": str(self.home), "PYTHONSTARTUP": str(module)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("INJECTED", result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)["isolated"], 1)

    def test_duplicate_manifest_keys_are_refused(self):
        report = self.install()
        path = Path(report["pinned_launcher"]).parent / runtime.MANIFEST
        path.chmod(0o600)
        path.write_text('{"schema":"x","schema":"y"}')
        path.chmod(0o400)
        result = self.run_cli(["version"], installed=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("duplicate_manifest_key", result.stderr)

    def test_select_old_runtime_preserves_current_pointer_and_uses_old_code(self):
        source = self.checkout / "swarm-fleet-prepare.py"
        source.write_text(self.peer + "print('original controller')\n")
        first = self.install()
        source.write_text(self.peer + "print('updated controller')\n")
        second = self.install()
        before = self.members(self.prefix)
        result = self.run_cli(["--runtime", first["runtime"], "prepare", "--resume",
                               "--accept-plan", "a" * 64], installed=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(lines[-1], "original controller")
        self.assertEqual(json.loads(lines[0])["argv"], ["--resume", "--accept-plan", "a" * 64])
        self.assertEqual(self.members(self.prefix), before)
        self.assertEqual(os.readlink(self.bin_dir / "acfs-fleet"), second["pinned_launcher"])

    def test_runtime_inventory_reports_all_retained_versions_without_writes(self):
        first = self.install()
        (self.checkout / "swarm-fleet-launch.py").write_text(self.peer + "# another cohort\n")
        second = self.install()
        before = self.members(self.home)
        result = self.run_cli(["runtimes"], installed=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = json.loads(result.stdout)["runtimes"]
        self.assertEqual({row["runtime"] for row in rows}, {first["runtime"], second["runtime"]})
        self.assertEqual([row["runtime"] for row in rows if row["current"]], [second["runtime"]])
        self.assertTrue(all(row["status"] == "verified" for row in rows))
        self.assertEqual(self.members(self.home), before)

    def test_unknown_or_unsafe_runtime_selection_never_falls_back(self):
        self.install()
        for args in (["--runtime", "0" * 64, "launch"], ["--runtime", "../../other", "launch"],
                     ["--runtime", "0" * 64], ["--runtime", "0" * 64, "install"]):
            result = self.run_cli(args, installed=True)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(result.stdout, "")
        self.assertEqual(self.run_cli(["runtimes"]).returncode, 2)

    def test_damaged_old_runtime_is_reported_and_never_executed(self):
        first = self.install()
        (self.checkout / "swarm-fleet-prepare.py").write_text(self.peer + "# new\n")
        self.install()
        source = Path(first["pinned_launcher"]).parent / "swarm-fleet-launch.py"
        source.chmod(0o600)
        source.write_text("raise SystemExit('WRONG CODE')\n")
        source.chmod(0o400)
        result = self.run_cli(["runtimes"], installed=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(next(r["status"] for r in json.loads(result.stdout)["runtimes"]
                              if r["runtime"] == first["runtime"]), "unavailable")
        result = self.run_cli(["--runtime", first["runtime"], "launch"], installed=True)
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("WRONG CODE", result.stdout + result.stderr)

    def test_exclusive_lock_prevents_competing_installation(self):
        preview = self.preview()
        fd = os.open(self.prefix, os.O_RDONLY | os.O_DIRECTORY)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_cli([*self.options(), "--apply", "--accept-plan", preview["plan_sha256"]])
            self.assertEqual(result.returncode, 2)
            self.assertIn("runtime_installation_in_progress", result.stderr)
            self.assertFalse((self.prefix / "releases").exists())
        finally:
            os.close(fd)

    def test_sigkill_mid_update_retains_old_active_runtime_and_partial_evidence(self):
        first = self.install()
        (self.checkout / "swarm-fleet-prepare.py").write_text(self.peer + "# update to interrupt\n")
        preview = self.preview()
        source = self.checkout / "acfs-fleet.py"
        program = f'''import importlib.util, os, signal
from pathlib import Path
spec = importlib.util.spec_from_file_location("r", {str(source)!r})
r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
original = r.publish
def crash(fd, name, raw, mode):
    original(fd, name, raw, mode)
    if name == "swarm-fleet-launch.py": os.kill(os.getpid(), signal.SIGKILL)
r.publish = crash
r.install(Path({str(self.prefix)!r}), Path({str(self.bin_dir)!r}), {preview['plan_sha256']!r})
'''
        killed = subprocess.run([sys.executable, "-I", "-c", program], capture_output=True, text=True,
                                timeout=10, env=self.env, **self.credentials)
        self.assertEqual(killed.returncode, -signal.SIGKILL, killed.stderr)
        self.assertEqual(os.readlink(self.bin_dir / "acfs-fleet"), first["pinned_launcher"])
        partial = self.prefix / "releases" / preview["plan"]["runtime"]
        self.assertTrue((partial / "swarm-fleet-launch.py").exists())
        self.assertFalse((partial / runtime.MANIFEST).exists())
        version = self.run_cli(["version"], installed=True)
        self.assertEqual(version.returncode, 0, version.stderr)
        self.assertEqual(json.loads(version.stdout)["runtime"], first["runtime"])
        before = self.members(self.home)
        retry = self.run_cli([*self.options(), "--apply", "--accept-plan", preview["plan_sha256"]])
        self.assertEqual(retry.returncode, 2)
        self.assertEqual(self.members(self.home), before)


if __name__ == "__main__":
    unittest.main()
