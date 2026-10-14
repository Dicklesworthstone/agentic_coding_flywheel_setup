#!/usr/bin/env python3
"""Installed provisioning, retained capabilities, and real unprivileged Git I/O."""
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest

import test_fleet_runtime as fixtures

runtime = fixtures.runtime
PROVISION = fixtures.SOURCE.with_name("swarm-fleet-provision.py")


class ProvisionRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.f = fixtures.RuntimeTests(methodName="runTest")
        self.f.setUp()
        self.addCleanup(self.f.doCleanups)

    def test_historical_layouts_keep_exact_original_roles(self):
        roles = ["launch", "prepare", "dispatch"]
        for generation, added in enumerate((None, "status", "collect", "test", "publish", "provision"), 1):
            if added:
                roles.append(added)
            schema = f"acfs.fleet-runtime.v{generation}"
            expected = {"acfs-fleet.py", *(f"swarm-fleet-{role}.py" for role in roles)}
            with self.subTest(schema=schema):
                self.assertEqual(set(runtime.FILES_BY_SCHEMA[schema]), expected)
                manifest = {"schema": schema, "files": {name: {"bytes": 1, "sha256": "a" * 64}
                                                       for name in expected}}
                self.assertEqual(set(runtime.manifest_layout(manifest)), expected)
                self.assertEqual(set(runtime.runtime_commands(manifest)), set(roles))
                if generation < 6:
                    manifest["files"]["swarm-fleet-provision.py"] = {"bytes": 1, "sha256": "b" * 64}
                    with self.assertRaisesRegex(runtime.Refused, "runtime_role_mismatch"):
                        runtime.manifest_layout(manifest)
        self.assertEqual(runtime.SCHEMA, "acfs.fleet-runtime.v6")

    def retained_release(self, generation):
        f = self.f
        schema = f"acfs.fleet-runtime.v{generation}"
        files = {name: f.peer.encode() for name in runtime.FILES_BY_SCHEMA[schema]}
        manifest = {"schema": schema, "files": {name: {"bytes": len(data), "sha256": runtime.sha(data)}
                                                for name, data in files.items()}}
        release = f.prefix / "releases" / runtime.sha(runtime.encode(manifest))
        release.mkdir(mode=0o700)
        f.own(release)
        for name, data in {**files, "runtime.json": runtime.encode(manifest)}.items():
            target = release / name
            target.write_bytes(data)
            f.own(target)
            target.chmod(0o500 if name == "acfs-fleet.py" else 0o400)
        release.chmod(0o500)
        return release

    def test_all_legacy_versions_stay_selectable_but_cannot_provision(self):
        f = self.f
        installed = f.install()
        for generation in range(1, 6):
            release = self.retained_release(generation)
            before = f.members(release)
            with self.subTest(generation=generation):
                refused = f.run_cli(["--runtime", release.name, "provision", "--resume", "original-journal"], installed=True)
                self.assertEqual(refused.returncode, 2, refused.stdout + refused.stderr)
                self.assertIn("runtime_command_unavailable", refused.stderr)
                self.assertEqual(refused.stdout, "")
                allowed = f.run_cli(["--runtime", release.name, "launch", "--reconcile", "original-receipt"], installed=True)
                self.assertEqual(allowed.returncode, 0, allowed.stderr)
                self.assertEqual(json.loads(allowed.stdout)["argv"], ["launch", "--reconcile", "original-receipt"])
                self.assertEqual(f.members(release), before)
        inventory = f.run_cli(["runtimes"], installed=True)
        self.assertEqual(inventory.returncode, 0, inventory.stderr)
        rows = json.loads(inventory.stdout)["runtimes"]
        self.assertEqual(len(rows), 6)
        self.assertEqual([r["runtime"] for r in rows if "provision" in r["commands"]], [installed["runtime"]])
        self.assertEqual(os.readlink(f.bin_dir / "acfs-fleet"), installed["pinned_launcher"])

    def test_provision_passes_recovery_authority_and_stdin_literally(self):
        f = self.f
        f.install()
        args = ["--resume", "journal with spaces", "--accept-plan", "f" * 64,
                "$(touch DO_NOT_EXECUTE)", "", "--exit"]
        result = f.run_cli(["provision", *args], installed=True)
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual(json.loads(result.stdout)["argv"], args)
        self.assertFalse((f.home / "DO_NOT_EXECUTE").exists())
        echoed = f.run_cli(["provision", "--echo-stdin"], installed=True, input="literal receiver input\n")
        self.assertEqual(echoed.stdout, "literal receiver input\n")

    def test_missing_provision_source_prevents_partial_install(self):
        f = self.f
        source = f.checkout / "swarm-fleet-provision.py"
        source.rename(f.checkout / "retained-provision.py")
        result = f.run_cli(f.options())
        self.assertEqual(result.returncode, 2)
        self.assertFalse((f.prefix / "releases").exists())

    def test_changed_provisioner_invalidates_install_approval(self):
        f = self.f
        preview = f.preview()
        (f.checkout / "swarm-fleet-provision.py").write_text(f.peer + "# changed receiver policy\n")
        result = f.run_cli([*f.options(), "--apply", "--accept-plan", preview["plan_sha256"]])
        self.assertEqual(result.returncode, 2)
        self.assertIn("installation_approval_mismatch", result.stderr)
        self.assertFalse((f.prefix / "releases").exists())

    def test_damaged_provisioner_blocks_the_entire_cohort(self):
        f = self.f
        installed = f.install()
        source = Path(installed["pinned_launcher"]).with_name("swarm-fleet-provision.py")
        source.chmod(0o600)
        source.write_text("raise SystemExit('UNREVIEWED CODE')\n")
        source.chmod(0o400)
        for command in ("provision", "launch", "publish", "version"):
            with self.subTest(command=command):
                result = f.run_cli([command], installed=True)
                self.assertEqual(result.returncode, 2)
                self.assertIn("runtime_integrity_mismatch", result.stderr)
                self.assertNotIn("UNREVIEWED CODE", result.stdout + result.stderr)

    def test_installed_real_receiver_creates_and_checks_sha1_and_sha256_without_checkout(self):
        f = self.f
        (f.checkout / "swarm-fleet-provision.py").write_bytes(PROVISION.read_bytes())
        installed = f.install()
        provision_path = Path(installed["pinned_launcher"]).with_name("swarm-fleet-provision.py")
        f.checkout.rename(f.root / "retained-source")
        policy = hashlib.sha256(provision_path.read_bytes()).hexdigest()

        def run(args, *, data=None):
            result = subprocess.run(args, input=data, capture_output=True, timeout=30,
                                    cwd=f.home, env=f.env, **f.credentials)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return result.stdout

        for fmt in ("sha1", "sha256"):
            with self.subTest(object_format=fmt):
                source = f.home / ("project-" + fmt)
                source.mkdir(mode=0o700)
                f.own(source)
                run(["/usr/bin/git", "-C", str(source), "init", "--template=", "--initial-branch=main", "--object-format=" + fmt])
                tracked = source / "tracked.txt"
                tracked.write_text("committed history\n")
                f.own(tracked)
                run(["/usr/bin/git", "-C", str(source), "add", "tracked.txt"])
                run(["/usr/bin/git", "-C", str(source), "-c", "user.name=Fixture", "-c", "user.email=fixture@localhost",
                     "commit", "-m", "Exact committed project"])
                commit = run(["/usr/bin/git", "-C", str(source), "rev-parse", "HEAD"]).decode().strip()
                tracked.write_text("uncommitted work remains private\n")
                before = f.members(source)
                program = '''import base64, importlib.util, json, sys
s=importlib.util.spec_from_file_location("provision", sys.argv[1])
p=importlib.util.module_from_spec(s); s.loader.exec_module(p)
source, artifact, pack=p.source_artifact(sys.argv[2], sys.argv[3], 20)
print(json.dumps({"artifact":artifact,"pack":base64.b64encode(pack).decode()}))
'''
                artifact = json.loads(run([sys.executable, "-I", "-c", program, str(provision_path), str(source), commit]))
                destination = f.home / ("receiver-" + fmt)
                request = {"schema": "acfs.swarm-fleet-provision.v1", "mode": "preview", "repo": str(destination),
                           "artifact": artifact["artifact"], "context": None, "plan_sha256": None,
                           "host_id": "receiver", "policy": policy}
                command = [str(f.bin_dir / "acfs-fleet"), "provision", "--receiver", "20"]
                preview = json.loads(run(command, data=json.dumps(request).encode() + b"\n"))
                self.assertEqual(preview["status"], "available")
                self.assertFalse(destination.exists())
                request.update(mode="create", context=preview["context"], plan_sha256="a" * 64)
                response = json.loads(run(command, data=json.dumps(request).encode() + b"\n" + base64.b64decode(artifact["pack"])))
                self.assertEqual(response["status"], "provisioned")
                self.assertEqual((destination / "tracked.txt").read_text(), "committed history\n")
                self.assertEqual(f.members(source), before)
                receipt = (destination / ".git/acfs-provision.json").read_bytes()
                source.rename(f.home / ("unavailable-project-" + fmt))
                request["mode"] = "check"
                checked = json.loads(run(command, data=json.dumps(request).encode() + b"\n"))
                self.assertEqual(checked, response)
                self.assertEqual((destination / ".git/acfs-provision.json").read_bytes(), receipt)
                request["mode"] = "create"
                duplicate = subprocess.run(command, input=json.dumps(request).encode() + b"\n" + base64.b64decode(artifact["pack"]),
                                           capture_output=True, timeout=30, env=f.env, **f.credentials)
                self.assertEqual(duplicate.returncode, 2)
                self.assertEqual(json.loads(duplicate.stdout)["code"], "destination_already_exists")
                self.assertEqual((destination / ".git/acfs-provision.json").read_bytes(), receipt)


if __name__ == "__main__":
    unittest.main()
