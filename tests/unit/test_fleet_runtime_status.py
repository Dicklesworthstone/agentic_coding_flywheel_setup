#!/usr/bin/env python3
"""Installed observation/collection/testing and retained runtime capabilities."""
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
        # Fixtures inherit the umask; a login user's 0002 makes them group-writable.
        self.addCleanup(os.umask, os.umask(0o022))
        # Reuse the actual installer fixture, without rerunning its inherited
        # test methods or duplicating filesystem/privilege setup.
        self.fx = base.RuntimeTests()
        self.fx.setUp()

    def legacy(self, active=True, schema="acfs.fleet-runtime.v1"):
        fx = self.fx
        names = LEGACY_FILES if schema == "acfs.fleet-runtime.v1" else (*LEGACY_FILES, "swarm-fleet-status.py")
        if schema in ("acfs.fleet-runtime.v3", "acfs.fleet-runtime.v4"):
            names = (*names, "swarm-fleet-collect.py")
        if schema == "acfs.fleet-runtime.v4":
            names = (*names, "swarm-fleet-test.py")
        files = {name: (LEGACY_FRONTEND if name == "acfs-fleet.py" else fx.peer).encode() for name in names}
        manifest = {"schema": schema, "files": {
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
        self.assertEqual(json.loads(version.stdout)["schema"], "acfs.fleet-runtime.v5")
        self.assertEqual(set(json.loads(version.stdout)["commands"]), {"launch", "prepare", "dispatch", "status", "collect", "test", "publish"})
        result = fx.run_cli(["runtimes"], installed=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = {r["runtime"]: r for r in json.loads(result.stdout)["runtimes"]}
        self.assertEqual(set(rows), {old_id, report["runtime"]})
        self.assertEqual(set(rows[old_id]["commands"]), {"launch", "prepare", "dispatch"})
        self.assertEqual(set(rows[report["runtime"]]["commands"]), {"launch", "prepare", "dispatch", "status", "collect", "test", "publish"})
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

    def test_v1_and_v2_upgrades_preserve_exact_capabilities_without_collection_fallback(self):
        fx = self.fx
        v1, root1 = self.legacy(active=False)
        v2, root2 = self.legacy(schema="acfs.fleet-runtime.v2")
        originals = [fx.members(root) for root in (root1, root2)]
        current = fx.install()
        result = fx.run_cli(["runtimes"], installed=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = {row["runtime"]: row for row in json.loads(result.stdout)["runtimes"]}
        self.assertEqual(set(rows), {v1, v2, current["runtime"]})
        self.assertEqual(rows[v1]["commands"], ["launch", "prepare", "dispatch"])
        self.assertEqual(rows[v2]["commands"], ["launch", "prepare", "dispatch", "status"])
        self.assertEqual(rows[current["runtime"]]["commands"], ["launch", "prepare", "dispatch", "status", "collect", "test", "publish"])
        for old in (v1, v2):
            result = fx.run_cli(["--runtime", old, "collect", "--help"], installed=True)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(result.stdout, "")
            self.assertEqual(json.loads(result.stderr)["code"], "runtime_command_unavailable")
        result = fx.run_cli(["--runtime", v2, "status", "--launch-state", "original journal"], installed=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"legacy_frontend": True,
                         "argv": ["status", "--launch-state", "original journal"]})
        self.assertEqual([fx.members(root) for root in (root1, root2)], originals)
        self.assertEqual(os.readlink(fx.bin_dir / "acfs-fleet"), current["pinned_launcher"])

    def test_each_runtime_schema_requires_its_exact_role_set(self):
        fx = self.fx
        expected = {
            "acfs.fleet-runtime.v1": set(LEGACY_FILES),
            "acfs.fleet-runtime.v2": set(LEGACY_FILES) | {"swarm-fleet-status.py"},
            "acfs.fleet-runtime.v3": set(LEGACY_FILES) | {"swarm-fleet-status.py", "swarm-fleet-collect.py"},
            "acfs.fleet-runtime.v4": set(LEGACY_FILES) | {"swarm-fleet-status.py", "swarm-fleet-collect.py", "swarm-fleet-test.py"},
            "acfs.fleet-runtime.v5": set(LEGACY_FILES) | {"swarm-fleet-status.py", "swarm-fleet-collect.py", "swarm-fleet-test.py", "swarm-fleet-publish.py"},
        }
        self.assertEqual(set(runtime.FILES_BY_SCHEMA), set(expected))
        for schema, names in expected.items():
            _, manifest, _ = runtime.snapshot(fx.checkout, schema=schema)
            self.assertEqual(set(runtime.manifest_layout(manifest)), names)
            for other in expected:
                if other != schema:
                    with self.subTest(schema=schema, other=other), self.assertRaisesRegex(runtime.Refused, "runtime_role_mismatch"):
                        runtime.manifest_layout({**manifest, "schema": other})

    def test_collector_change_or_absence_refuses_installation_before_publication(self):
        fx = self.fx
        preview = fx.preview()
        collector = fx.checkout / "swarm-fleet-collect.py"
        collector.write_text(fx.peer + "# reviewed bytes changed\n")
        result = fx.run_cli([*fx.options(), "--apply", "--accept-plan", preview["plan_sha256"]])
        self.assertEqual(result.returncode, 2)
        self.assertIn("installation_approval_mismatch", result.stderr)
        collector.rename(fx.checkout / "retained-collector")
        result = fx.run_cli(fx.options())
        self.assertEqual(result.returncode, 2)
        self.assertFalse((fx.prefix / "releases").exists())

    def test_damaged_collector_blocks_entire_runtime_without_executing_it(self):
        fx = self.fx
        result = fx.install()
        collector = Path(result["pinned_launcher"]).parent / "swarm-fleet-collect.py"
        collector.chmod(0o600)
        collector.write_text("raise SystemExit('MODIFIED-COLLECTOR')\n")
        collector.chmod(0o400)
        for command in ("launch", "status", "collect", "version"):
            rejected = fx.run_cli([command], installed=True)
            self.assertEqual(rejected.returncode, 2)
            self.assertIn("runtime_integrity_mismatch", rejected.stderr)
            self.assertNotIn("MODIFIED-COLLECTOR", rejected.stdout + rejected.stderr)

    def test_collect_forwards_exact_arguments_and_status_without_granting_approval(self):
        fx = self.fx
        installed = fx.install()
        args = ["--bases", "path with ' quotes", "--output-dir", "$(touch NEVER)",
                "--collect", "--accept-plan", "e" * 64, "--exit"]
        for prefix in ([], ["--runtime", installed["runtime"]]):
            result = fx.run_cli([*prefix, "collect", *args], installed=True)
            self.assertEqual(result.returncode, 23, result.stderr)
            self.assertEqual(json.loads(result.stdout)["argv"], args)
        self.assertFalse((fx.home / "NEVER").exists())

    def test_installed_collector_verifies_real_git_artifacts_without_checkout_or_ssh(self):
        fx = self.fx
        # Only collector and its one imported sibling execute in this case.
        # Other controller roles remain inert fixtures, not claimed acceptance.
        for name in ("swarm-fleet-collect.py", "swarm-fleet-launch.py"):
            (fx.checkout / name).write_bytes((ROOT / "scripts" / name).read_bytes())
        installed = fx.install()
        setup = f'''import importlib.util, json
spec = importlib.util.spec_from_file_location("collection_tests", {str(Path(__file__).with_name('test_swarm_fleet_collect.py'))!r})
tests = importlib.util.module_from_spec(spec); spec.loader.exec_module(tests)
fixture = tests.CollectionTests(); fixture.setUp()
result = fixture.collect()
print(json.dumps({{"directory": str(fixture.out), "plan_sha256": result["plan_sha256"]}}))
'''
        made = subprocess.run([sys.executable, "-I", "-c", setup], capture_output=True, text=True,
                              env=fx.env, timeout=15, **fx.credentials)
        self.assertEqual(made.returncode, 0, made.stderr)
        artifacts = json.loads(made.stdout)
        path = Path(artifacts["directory"])
        fx.checkout.rename(fx.root / "retained-source")
        before = fx.members(path)
        for prefix in ([], ["--runtime", installed["runtime"]]):
            result = fx.run_cli([*prefix, "collect", "--verify", str(path)], installed=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            self.assertEqual(report["schema"], "acfs.swarm-fleet-collection.v1")
            self.assertEqual(report["status"], "verified")
            self.assertEqual(report["plan_sha256"], artifacts["plan_sha256"])
            self.assertEqual(len(report["artifacts"]), 2)
            self.assertFalse(report["task_completion_verified"])
        self.assertEqual(fx.members(path), before)
        help_result = fx.run_cli(["collect", "--help"], installed=True)
        self.assertEqual(help_result.returncode, 0, help_result.stderr)
        self.assertIn("--bases", help_result.stdout)
        refused = fx.run_cli(["collect", "--verify", str(path), "--collect"], installed=True)
        self.assertEqual(refused.returncode, 2)
        self.assertEqual(json.loads(refused.stdout)["code"], "verify_requires_only_collection_directory")
        damaged = path / "alpha.bundle"
        with damaged.open("ab") as stream:
            stream.write(b"corrupt-transfer")
        refused = fx.run_cli(["collect", "--verify", str(path)], installed=True)
        self.assertEqual(refused.returncode, 2)
        self.assertEqual(json.loads(refused.stdout)["code"], "artifact_integrity_mismatch")

    def test_old_generations_do_not_acquire_test_capability_or_fall_back(self):
        fx = self.fx
        old = [self.legacy(active=False, schema="acfs.fleet-runtime.v" + str(n)) for n in (1, 2, 3)]
        before = [fx.members(root) for _, root in old]
        installed = fx.install()
        rows = json.loads(fx.run_cli(["runtimes"], installed=True).stdout)["runtimes"]
        self.assertEqual(len(rows), 4)
        for old_id, _ in old:
            self.assertNotIn("test", next(r["commands"] for r in rows if r["runtime"] == old_id))
            result = fx.run_cli(["--runtime", old_id, "test", "--run"], installed=True)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(result.stdout, "")
            self.assertIn("runtime_command_unavailable", result.stderr)
        self.assertEqual([fx.members(root) for _, root in old], before)
        self.assertEqual(os.readlink(fx.bin_dir / "acfs-fleet"), installed["pinned_launcher"])

    def test_v3_frontend_and_commands_remain_original_after_upgrade(self):
        fx = self.fx
        old_id, root = self.legacy(schema="acfs.fleet-runtime.v3")
        before = fx.members(root)
        fx.install()
        args = ["collect", "--integrate", "literal ' path", "--check", "--accept-plan", "f" * 64]
        result = fx.run_cli(["--runtime", old_id, *args], installed=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"legacy_frontend": True, "argv": args})
        self.assertEqual(fx.members(root), before)

    def test_test_controller_is_required_and_changes_invalidate_install_approval(self):
        fx = self.fx
        preview = fx.preview()
        source = fx.checkout / "swarm-fleet-test.py"
        source.write_text(fx.peer + "# changed test implementation\n")
        result = fx.run_cli([*fx.options(), "--apply", "--accept-plan", preview["plan_sha256"]])
        self.assertEqual(result.returncode, 2)
        self.assertIn("installation_approval_mismatch", result.stderr)
        source.rename(fx.checkout / "retained-test-controller")
        self.assertEqual(fx.run_cli(fx.options()).returncode, 2)
        self.assertFalse((fx.prefix / "releases").exists())

    def test_damaged_test_controller_blocks_execution_of_the_complete_cohort(self):
        fx = self.fx
        installed = fx.install()
        path = Path(installed["pinned_launcher"]).parent / "swarm-fleet-test.py"
        path.chmod(0o600)
        path.write_text("raise SystemExit('WRONG TEST CODE')\n")
        path.chmod(0o400)
        for command in ("test", "launch", "collect", "version"):
            result = fx.run_cli([command], installed=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("runtime_integrity_mismatch", result.stderr)
            self.assertNotIn("WRONG TEST CODE", result.stdout + result.stderr)

    def test_test_command_preserves_literal_arguments_exit_and_signal(self):
        fx = self.fx
        installed = fx.install()
        args = ["--run", "--accept-plan", "0" * 64, "$(touch NEVER)", "", "--exit"]
        for prefix in ([], ["--runtime", installed["runtime"]]):
            result = fx.run_cli([*prefix, "test", *args], installed=True)
            self.assertEqual(result.returncode, 23, result.stderr)
            self.assertEqual(json.loads(result.stdout)["argv"], args)
        result = fx.run_cli(["test", "--signal"], installed=True)
        self.assertEqual(result.returncode, -15)
        self.assertFalse((fx.home / "NEVER").exists())

    def test_actual_installed_runner_tests_commits_after_checkout_is_unavailable(self):
        fx = self.fx
        for name in ("swarm-fleet-test.py", "swarm-fleet-collect.py", "swarm-fleet-launch.py"):
            (fx.checkout / name).write_bytes((ROOT / "scripts" / name).read_bytes())
        installed = fx.install()
        setup = f'''import importlib.util, json
spec = importlib.util.spec_from_file_location("test_support", {str(Path(__file__).with_name('test_swarm_fleet_test.py'))!r})
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
fixture = module.Fixture()
print(json.dumps({{"repo": str(fixture.repo), "commit": fixture.commit,
                  "spec": str(fixture.specfile), "output": str(fixture.output)}}))
'''
        made = subprocess.run([sys.executable, "-I", "-c", setup], capture_output=True, text=True,
                              env=fx.env, timeout=15, **fx.credentials)
        self.assertEqual(made.returncode, 0, made.stderr)
        data = json.loads(made.stdout)
        fx.checkout.rename(fx.root / "retained-source")
        original = fx.members(Path(data["repo"]))
        for index, prefix in enumerate(([], ["--runtime", installed["runtime"]])):
            output = data["output"] + str(index)
            args = [*prefix, "test", "--repository", data["repo"], "--commit", data["commit"],
                    "--spec", data["spec"], "--output-dir", output]
            preview = fx.run_cli(args, installed=True)
            self.assertEqual(preview.returncode, 0, preview.stderr + preview.stdout)
            self.assertFalse(Path(output).exists())
            result = fx.run_cli([*args, "--run", "--accept-plan", json.loads(preview.stdout)["plan_sha256"]], installed=True)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            report = json.loads(result.stdout)
            self.assertEqual(report["status"], "passed")
            self.assertEqual(report["plan"]["commit"], data["commit"])
            self.assertEqual((Path(output) / "logs/unit.stdout").read_text(), "tested exact source\n")
            self.assertFalse(report["plan"]["sandboxed"])
        self.assertEqual(fx.members(Path(data["repo"])), original)

    def test_retained_v1_through_v4_never_acquire_publication(self):
        fx = self.fx
        old = [self.legacy(active=False, schema="acfs.fleet-runtime.v" + str(n)) for n in range(1, 5)]
        before = [fx.members(root) for _, root in old]
        installed = fx.install()
        result = fx.run_cli(["runtimes"], installed=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = {r["runtime"]: r for r in json.loads(result.stdout)["runtimes"]}
        self.assertEqual(len(rows), 5)
        self.assertIn("publish", rows[installed["runtime"]]["commands"])
        for old_id, _ in old:
            self.assertNotIn("publish", rows[old_id]["commands"])
            result = fx.run_cli(["--runtime", old_id, "publish", "--push"], installed=True)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(result.stdout, "")
            self.assertIn("runtime_command_unavailable", result.stderr)
        self.assertEqual([fx.members(root) for _, root in old], before)
        self.assertEqual(os.readlink(fx.bin_dir / "acfs-fleet"), installed["pinned_launcher"])

    def test_v4_test_frontend_keeps_original_recovery_arguments(self):
        fx = self.fx
        old_id, root = self.legacy(schema="acfs.fleet-runtime.v4")
        before = fx.members(root)
        fx.install()
        args = ["test", "--promote", "original ' run", "--check", "--accept-plan", "d" * 64]
        result = fx.run_cli(["--runtime", old_id, *args], installed=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"legacy_frontend": True, "argv": args})
        self.assertEqual(fx.members(root), before)

    def test_publication_code_is_required_and_bound_to_installation_approval(self):
        fx = self.fx
        preview = fx.preview()
        source = fx.checkout / "swarm-fleet-publish.py"
        source.write_text(fx.peer + "# changed publication authority\n")
        result = fx.run_cli([*fx.options(), "--apply", "--accept-plan", preview["plan_sha256"]])
        self.assertEqual(result.returncode, 2)
        self.assertIn("installation_approval_mismatch", result.stderr)
        source.rename(fx.checkout / "retained-publication-controller")
        self.assertEqual(fx.run_cli(fx.options()).returncode, 2)
        self.assertFalse((fx.prefix / "releases").exists())

    def test_damaged_publisher_blocks_whole_runtime(self):
        fx = self.fx
        installed = fx.install()
        path = Path(installed["pinned_launcher"]).parent / "swarm-fleet-publish.py"
        path.chmod(0o600)
        path.write_text("raise SystemExit('WRONG PUBLICATION CODE')\n")
        path.chmod(0o400)
        for command in ("publish", "test", "launch", "version"):
            result = fx.run_cli([command, "--help"], installed=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("runtime_integrity_mismatch", result.stderr)
            self.assertNotIn("WRONG PUBLICATION CODE", result.stdout + result.stderr)

    def test_publish_passes_literal_approval_arguments_stdin_and_exit_status(self):
        fx = self.fx
        installed = fx.install()
        args = ["--push", "--accept-plan", "a" * 64, "$(touch NEVER)", "", "--exit"]
        for prefix in ([], ["--runtime", installed["runtime"]]):
            result = fx.run_cli([*prefix, "publish", *args], installed=True)
            self.assertEqual(result.returncode, 23, result.stderr)
            self.assertEqual(json.loads(result.stdout)["argv"], args)
        result = fx.run_cli(["publish", "--echo-stdin"], installed=True, input="literal input\n")
        self.assertEqual(result.stdout, "literal input\n")
        self.assertEqual(fx.run_cli(["publish", "--signal"], installed=True).returncode, -15)
        self.assertFalse((fx.home / "NEVER").exists())

    def test_installed_publisher_uses_real_git_and_evidence_without_checkout(self):
        fx = self.fx
        # All four modules executed by this operation are production code.
        # Unrelated launch/prepare/status peers are not executed.
        for name in ("swarm-fleet-publish.py", "swarm-fleet-test.py",
                     "swarm-fleet-collect.py", "swarm-fleet-launch.py"):
            (fx.checkout / name).write_bytes((ROOT / "scripts" / name).read_bytes())
        installed = fx.install()
        setup = f'''import importlib.util, json
spec = importlib.util.spec_from_file_location("publication_fixture", {str(Path(__file__).with_name('test_swarm_fleet_publish.py'))!r})
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
fixture = module.Fixture(integrate=True)
print(json.dumps({{"argv": fixture.cli_args()[3:], "repo": str(fixture.repo),
                  "remote": str(fixture.remote), "candidate": fixture.candidate,
                  "state": str(fixture.state)}}))
'''
        made = subprocess.run([sys.executable, "-I", "-c", setup], capture_output=True, text=True,
                              env=fx.env, timeout=20, **fx.credentials)
        self.assertEqual(made.returncode, 0, made.stderr)
        data = json.loads(made.stdout)
        fx.checkout.rename(fx.root / "retained-source")
        original = fx.members(Path(data["repo"]))
        args = ["publish", *data["argv"]]
        preview = fx.run_cli(args, installed=True)
        self.assertEqual(preview.returncode, 0, preview.stdout + preview.stderr)
        self.assertFalse(Path(data["state"]).exists())
        digest = json.loads(preview.stdout)["plan_sha256"]
        published = fx.run_cli([*args, "--push", "--accept-plan", digest], installed=True)
        self.assertEqual(published.returncode, 0, published.stdout + published.stderr)
        self.assertEqual(json.loads(published.stdout)["status"], "published")
        saved = fx.members(Path(data["state"]))
        for prefix in ([], ["--runtime", installed["runtime"]]):
            checked = fx.run_cli([*prefix, *args, "--check", "--accept-plan", digest], installed=True)
            self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
            self.assertEqual(json.loads(checked.stdout)["remote_status"], "matched")
        self.assertEqual(fx.members(Path(data["repo"])), original)
        self.assertEqual(fx.members(Path(data["state"])), saved)
        observed = subprocess.run(["/usr/bin/git", "-C", data["remote"], "rev-parse", "refs/heads/main"],
                                  capture_output=True, text=True, env=fx.env, timeout=5, **fx.credentials)
        self.assertEqual(observed.returncode, 0, observed.stderr)
        self.assertEqual(observed.stdout.strip(), data["candidate"])


if __name__ == "__main__":
    unittest.main()
