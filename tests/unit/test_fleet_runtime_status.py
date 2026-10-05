#!/usr/bin/env python3
"""Observer-enabled runtime installation and retained four-file compatibility."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("runtime_test_support", Path(__file__).with_name("test_fleet_runtime.py"))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
runtime = base.runtime
LEGACY_FILES = ("acfs-fleet.py", "swarm-fleet-dispatch.py", "swarm-fleet-launch.py", "swarm-fleet-prepare.py")
LEGACY_FRONTEND = '''#!/usr/bin/python3 -I
import json, sys
print(json.dumps({"legacy_frontend": True, "argv": sys.argv[1:]}))
'''


class RuntimeStatusTests(unittest.TestCase):
    def setUp(self):
        # Reuse the actual installer fixture, without rerunning its inherited
        # test methods or duplicating filesystem/privilege setup.
        self.fx = base.RuntimeTests()
        self.fx.setUp()

    def legacy(self, active=True):
        fx = self.fx
        files = {name: (LEGACY_FRONTEND if name == "acfs-fleet.py" else fx.peer).encode() for name in LEGACY_FILES}
        manifest = {"schema": "acfs.fleet-runtime.v1", "files": {
            name: {"sha256": runtime.sha(raw), "bytes": len(raw)} for name, raw in files.items()}}
        release_id = runtime.sha(runtime.encode(manifest))
        releases = fx.prefix / "releases"
        releases.mkdir(mode=0o700, exist_ok=True)
        fx.own(releases)
        root = releases / release_id
        root.mkdir(mode=0o700)
        fx.own(root)
        for name, raw in {**files, "runtime.json": runtime.encode(manifest)}.items():
            path = root / name
            path.write_bytes(raw)
            path.chmod(0o500 if name == "acfs-fleet.py" else 0o400)
            fx.own(path)
        root.chmod(0o500)
        if active:
            link = fx.bin_dir / "acfs-fleet"
            link.symlink_to(root / "acfs-fleet.py")
            if os.geteuid() == 0:
                os.lchown(link, fx.uid, fx.gid)
        return release_id, root

    def test_upgrade_preserves_legacy_release_and_advertises_only_available_commands(self):
        fx = self.fx
        old_id, old = self.legacy()
        before = fx.members(old)
        report = fx.install()
        version = fx.run_cli(["version"], installed=True)
        self.assertEqual(version.returncode, 0, version.stderr)
        self.assertEqual(json.loads(version.stdout)["schema"], "acfs.fleet-runtime.v2")
        self.assertEqual(set(json.loads(version.stdout)["commands"]), {"launch", "prepare", "dispatch", "status"})
        result = fx.run_cli(["runtimes"], installed=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = {r["runtime"]: r for r in json.loads(result.stdout)["runtimes"]}
        self.assertEqual(set(rows), {old_id, report["runtime"]})
        self.assertEqual(set(rows[old_id]["commands"]), {"launch", "prepare", "dispatch"})
        self.assertEqual(set(rows[report["runtime"]]["commands"]), {"launch", "prepare", "dispatch", "status"})
        self.assertTrue(rows[report["runtime"]]["current"])
        self.assertEqual(fx.members(old), before)

    def test_legacy_selection_executes_original_frontend_without_changing_active_version(self):
        fx = self.fx
        old_id, _ = self.legacy()
        installed = fx.install()
        before = fx.members(fx.home)
        args = ["prepare", "--resume", "--accept-plan", "d" * 64, "path with ' quotes"]
        result = fx.run_cli(["--runtime", old_id, *args], installed=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"legacy_frontend": True, "argv": args})
        self.assertEqual(os.readlink(fx.bin_dir / "acfs-fleet"), installed["pinned_launcher"])
        self.assertEqual(fx.members(fx.home), before)

    def test_status_on_legacy_runtime_is_refused_without_frontend_execution_or_fallback(self):
        fx = self.fx
        old_id, _ = self.legacy()
        fx.install()
        before = fx.members(fx.home)
        result = fx.run_cli(["--runtime", old_id, "status", "--help"], installed=True)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertEqual(json.loads(result.stderr)["code"], "runtime_command_unavailable")
        self.assertEqual(fx.members(fx.home), before)

    def test_damaged_legacy_release_has_no_advertised_commands_and_cannot_be_selected(self):
        fx = self.fx
        old_id, root = self.legacy()
        fx.install()
        path = root / "swarm-fleet-launch.py"
        path.chmod(0o600)
        path.write_text("raise SystemExit('PRIVATE-DAMAGED-CODE')\n")
        path.chmod(0o400)
        result = fx.run_cli(["runtimes"], installed=True)
        self.assertEqual(result.returncode, 1)
        row = next(r for r in json.loads(result.stdout)["runtimes"] if r["runtime"] == old_id)
        self.assertEqual((row["status"], row["commands"]), ("unavailable", []))
        result = fx.run_cli(["--runtime", old_id, "version"], installed=True)
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("PRIVATE-DAMAGED-CODE", result.stdout + result.stderr)

    def test_new_cohort_requires_observer_and_its_change_invalidates_install_approval(self):
        fx = self.fx
        plan = fx.preview()
        observer = fx.checkout / "swarm-fleet-status.py"
        observer.write_text(fx.peer + "# different observer\n")
        result = fx.run_cli([*fx.options(), "--apply", "--accept-plan", plan["plan_sha256"]])
        self.assertEqual(result.returncode, 2)
        self.assertIn("installation_approval_mismatch", result.stderr)
        observer.rename(fx.checkout / "retained-status.py")
        result = fx.run_cli(fx.options())
        self.assertEqual(result.returncode, 2)
        self.assertFalse((fx.prefix / "releases").exists())

    def test_damaged_observer_blocks_other_commands_in_the_same_cohort(self):
        fx = self.fx
        report = fx.install()
        path = Path(report["pinned_launcher"]).parent / "swarm-fleet-status.py"
        path.chmod(0o600)
        path.write_text("raise SystemExit('WRONG-OBSERVER')\n")
        path.chmod(0o400)
        for command in ("launch", "status"):
            result = fx.run_cli([command, "--help"], installed=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("runtime_integrity_mismatch", result.stderr)
            self.assertNotIn("WRONG-OBSERVER", result.stdout + result.stderr)

    def test_known_schemas_require_exact_fixed_roles_and_strict_metadata(self):
        fx = self.fx
        _, manifest, _ = runtime.snapshot(fx.checkout)
        self.assertEqual(set(runtime.manifest_layout(manifest)), set(runtime.FILES))
        changes = [lambda v: v.update(schema=[]), lambda v: v.update(schema="future-runtime"),
                   lambda v: v.update(files={}), lambda v: v["files"].pop("swarm-fleet-status.py"),
                   lambda v: v["files"].update({"../../other.py": {"sha256": "a" * 64, "bytes": 1}}),
                   lambda v: v.update(schema="acfs.fleet-runtime.v1"),
                   lambda v: v["files"]["acfs-fleet.py"].update(bytes=True),
                   lambda v: v["files"]["acfs-fleet.py"].update(bytes=1.0),
                   lambda v: v["files"]["acfs-fleet.py"].update(bytes=runtime.LIMIT + 1),
                   lambda v: v["files"]["acfs-fleet.py"].update(sha256="unknown"),
                   lambda v: v["files"]["acfs-fleet.py"].update(optional=True)]
        for index, change in enumerate(changes):
            value = copy.deepcopy(manifest)
            change(value)
            with self.subTest(index=index), self.assertRaises(runtime.Refused):
                runtime.manifest_layout(value)

    def test_status_is_a_real_installed_command_with_original_exit_codes_and_no_checkout(self):
        fx = self.fx
        # The observer and both imported controllers are production code, not
        # forwarding fixtures. Preparation is not executed by this test.
        for name in ("swarm-fleet-status.py", "swarm-fleet-launch.py", "swarm-fleet-dispatch.py"):
            (fx.checkout / name).write_bytes((ROOT / "scripts" / name).read_bytes())
        report = fx.install()
        setup = f'''import importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location("fixtures", {str(Path(__file__).with_name('test_swarm_fleet_status.py'))!r})
fixtures = importlib.util.module_from_spec(spec); spec.loader.exec_module(fixtures)
root = Path({str(fx.home / 'operation')!r})
root.mkdir(mode=0o700)
fixture = fixtures.FleetFixture(root, launch=False, send=False)
for name, raw in (("known", fixture.known), ("identity", fixture.key)):
    path = root / name
    path.write_bytes(raw)
    path.chmod(0o600)
'''
        made = subprocess.run([sys.executable, "-I", "-c", setup], capture_output=True, text=True,
                              cwd=fx.home, env=fx.env, timeout=10, **fx.credentials)
        self.assertEqual(made.returncode, 0, made.stderr)
        fx.checkout.rename(fx.root / "retained-source")
        before = fx.members(fx.home)
        args = ["status", "--launch-state", str(fx.home / "operation/launch"),
                "--known-hosts", str(fx.home / "operation/known"), "--identity-file", str(fx.home / "operation/identity")]
        for prefix in ([], ["--runtime", report["runtime"]]):
            result = fx.run_cli([*prefix, *args], installed=True)
            self.assertEqual(result.returncode, 1, result.stderr)
            value = json.loads(result.stdout)
            self.assertEqual(value["schema"], "acfs.swarm-fleet-status.v1")
            self.assertEqual(value["status"], "attention")
            self.assertTrue(value["read_only"])
            self.assertEqual(value["summary"]["requested_agents"], 4)
            self.assertTrue(all(r["agents"]["status"] == "not_attempted" for r in value["hosts"]))
            self.assertFalse(value["sends_prompts"])
        rejected = fx.run_cli([*args, "--send"], installed=True)
        self.assertEqual(rejected.returncode, 2)
        self.assertIn("unrecognized arguments: --send", rejected.stderr)
        self.assertEqual(fx.members(fx.home), before)


if __name__ == "__main__":
    unittest.main()
