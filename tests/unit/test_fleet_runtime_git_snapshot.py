#!/usr/bin/env python3
"""Installed Git-aware tests through real promotion and local publication.

All executing controllers are production code. Three unused fleet roles are
inert sentinels; these tests neither launch agents nor claim live SSH acceptance.
Private test repositories, installed releases and journals are retained.
"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("snapshot_support", Path(__file__).with_name("test_swarm_fleet_git_snapshot.py"))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
EXECUTED = ("acfs-fleet.py", "swarm-fleet-test.py", "swarm-fleet-collect.py",
            "swarm-fleet-launch.py", "swarm-fleet-publish.py")


class InstalledGitSnapshotTests(unittest.TestCase):
    def setUp(self):
        # Fixtures inherit the umask; a login user's 0002 makes them group-writable.
        self.addCleanup(os.umask, os.umask(0o022))
        self.fx = base.GitSnapshotTests()
        self.fx.setUp()
        fx = self.fx
        self.source = fx.root / "controller-source"
        self.source.mkdir(mode=0o700)
        for name in EXECUTED:
            (self.source / name).write_bytes((ROOT / "scripts" / name).read_bytes())
        for role in ("prepare", "dispatch", "status"):
            (self.source / ("swarm-fleet-" + role + ".py")).write_text(
                "raise SystemExit('unused controller must never execute')\n")
        self.prefix, self.bin_dir = fx.root / "fleet", fx.root / "bin"
        self.prefix.mkdir(mode=0o700)
        self.bin_dir.mkdir(mode=0o700)
        self.specfile = fx.root / "tests.json"

    def cli(self, args, expected=0, command=None):
        command = command or [str(self.bin_dir / "acfs-fleet")]
        result = subprocess.run([*command, *args], env=self.fx.env, cwd=self.fx.root,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def install(self):
        args = ["install", "--prefix", str(self.prefix), "--bin-dir", str(self.bin_dir)]
        command = [sys.executable, "-I", str(self.source / "acfs-fleet.py")]
        preview = self.cli(args, command=command)
        self.assertEqual(preview["status"], "preview")
        self.assertFalse((self.prefix / "releases").exists())
        result = self.cli([*args, "--apply", "--accept-plan", preview["plan_sha256"]], command=command)
        self.assertEqual(result["status"], "installed")
        self.runtime = result["runtime"]
        self.launcher = result["pinned_launcher"]
        self.source.rename(self.fx.root / "retained-controller-source")

    def run_checks(self, pinned=False, snapshot=True, failure=False):
        fx = self.fx
        self.specfile.write_text(json.dumps(fx.specification))
        self.specfile.chmod(0o600)
        args = (["--runtime", self.runtime] if pinned else []) + [
            "test", "--repository", str(fx.repo), "--commit", fx.commit,
            "--spec", str(self.specfile), "--output-dir", str(fx.output)]
        if snapshot:
            args.append("--git-snapshot")
        preview = self.cli(args)
        self.assertEqual(preview["status"], "preview")
        self.assertFalse(fx.output.exists())
        self.test_plan = preview["plan_sha256"]
        result = self.cli([*args, "--run", "--accept-plan", self.test_plan], expected=int(failure))
        self.assertEqual(result["status"], "failed" if failure else "passed")
        return result

    def verify_args(self):
        return ["test", "--verify", str(self.fx.output), "--repository", str(self.fx.repo),
                "--expect-plan", self.test_plan]

    def promote(self):
        fx = self.fx
        args = ["test", "--promote", str(fx.output), "--repository", str(fx.repo),
                "--expect-plan", self.test_plan, "--branch", "release", "--expect-old", fx.base]
        preview = self.cli(args)
        result = self.cli([*args, "--apply", "--accept-plan", preview["plan_sha256"]])
        self.assertEqual(result["status"], "promoted")
        self.assertEqual(fx.git("rev-parse", "release"), fx.commit)

    def receiver(self):
        fx = self.fx
        fx.git("branch", "release", fx.base)
        self.remote = fx.root / "receiver.git"
        self.remote.mkdir(mode=0o700)
        result = subprocess.run(["/usr/bin/git", "init", "--bare", "--template=", "--initial-branch=main",
                                 "--object-format=" + fx.git("rev-parse", "--show-object-format"), str(self.remote)],
                                env=fx.env, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        fx.git("push", str(self.remote), fx.base + ":refs/heads/main")
        self.state = fx.root / "publication"

    def publication_args(self):
        fx = self.fx
        return ["publish", "--test-run", str(fx.output), "--repository", str(fx.repo),
                "--expect-test-plan", self.test_plan, "--branch", "release", "--remote-branch", "main",
                "--expect-old", fx.base, "--local-remote", str(self.remote), "--state-dir", str(self.state)]

    def pipeline(self, pinned=False):
        fx = self.fx
        self.receiver()
        # A real dirty source must stay dirty through testing and publication.
        (fx.repo / "nested/tracked.txt").write_text("local changes not tested or uploaded\n")
        before = fx.files(fx.repo)
        self.install()
        result = self.run_checks(pinned=pinned)
        self.assertEqual(result["plan"]["git_snapshot"], base.runner.GIT_SNAPSHOT_MODE)
        self.assertEqual(fx.files(fx.repo), before)
        self.assertEqual(self.cli(self.verify_args())["status"], "passed")
        self.promote()
        promoted = fx.files(fx.repo)
        args = self.publication_args()
        preview = self.cli(args)
        self.assertFalse(self.state.exists())
        self.assertEqual(preview["plan"]["candidate_commit"], fx.commit)
        result = self.cli([*args, "--push", "--accept-plan", preview["plan_sha256"]])
        self.assertEqual(result["status"], "published")
        self.assertEqual(fx.git("ls-remote", str(self.remote), "refs/heads/main").split()[0], fx.commit)
        journals = fx.files(self.state)
        evidence = fx.files(fx.output)
        receiver = fx.files(self.remote)
        checked = self.cli(["--runtime", self.runtime, *args, "--check", "--accept-plan", preview["plan_sha256"]])
        self.assertEqual(checked["status"], "matched")
        self.assertTrue(checked["read_only"])
        self.assertFalse(checked["tests_rerun"])
        self.assertFalse(checked["task_completion_verified"])
        self.assertEqual(fx.files(fx.repo), promoted)
        self.assertEqual(fx.files(self.state), journals)
        self.assertEqual(fx.files(fx.output), evidence)
        self.assertEqual(fx.files(self.remote), receiver)

    def test_installed_git_test_promote_publish_check_without_source_checkout(self):
        self.pipeline()

    def test_sha256_pipeline_through_explicit_pinned_runtime(self):
        self.fx.make_repository("sha256")
        self.pipeline(pinned=True)

    def test_real_merge_candidate_preserves_exact_commit_without_importing_parents(self):
        fx = self.fx
        first = fx.commit
        fx.git("checkout", "-qb", "other", fx.base)
        (fx.repo / "other-parent.txt").write_text("independent contribution\n")
        fx.git("add", "other-parent.txt")
        fx.git("commit", "-qm", "other parent")
        second = fx.git("rev-parse", "HEAD")
        fx.git("checkout", "main")
        fx.git("merge", "--no-ff", "-m", "combined candidate", "other")
        fx.commit, fx.tree = fx.git("rev-parse", "HEAD"), fx.git("rev-parse", "HEAD^{tree}")
        self.assertEqual(fx.git("show", "-s", "--format=%P", "HEAD").split(), [first, second])
        fx.specification["environment"].update(EXPECTED_COMMIT=fx.commit, EXPECTED_TREE=fx.tree)
        self.pipeline()

    def test_linked_source_worktree_does_not_become_a_borrowed_test_repository(self):
        fx = self.fx
        original = fx.repo
        linked = fx.root / "linked-project"
        fx.git("worktree", "add", "--detach", str(linked), fx.commit)
        fx.repo = linked
        before = fx.files(original)
        self.install()
        self.run_checks()
        self.assertEqual(self.cli(self.verify_args())["status"], "passed")
        self.assertTrue((fx.output / "workspace/.git").is_dir())
        self.assertFalse((fx.output / "workspace/.git/commondir").exists())
        self.assertEqual(fx.files(original), before)

    def test_metadata_tampering_revokes_previously_previewed_publication_without_writes(self):
        fx = self.fx
        self.receiver()
        self.install()
        self.run_checks()
        self.promote()
        args = self.publication_args()
        preview = self.cli(args)
        (fx.output / "workspace/.git/HEAD").write_text(fx.base + "\n")
        before = fx.files(fx.root)
        refused = self.cli([*args, "--push", "--accept-plan", preview["plan_sha256"]], expected=2)
        self.assertEqual(refused["code"], "passing_test_evidence_required")
        self.assertFalse(refused["push_started"])
        self.assertFalse(self.state.exists())
        self.assertEqual(fx.files(fx.root), before)

    def test_failing_git_aware_command_never_qualifies_for_promotion(self):
        fx = self.fx
        self.receiver()
        self.install()
        fx.specification["commands"].append({"id": "actual-failure", "argv": ["/usr/bin/git", "diff", "HEAD^"],
                                            "timeout_seconds": 5})
        result = self.run_checks(failure=True)
        self.assertEqual(result["tests"][0]["status"], "passed")
        self.assertEqual(result["tests"][1]["status"], "failed")
        self.assertEqual(self.cli(self.verify_args(), expected=1)["status"], "failed")
        promotion = self.cli(["test", "--promote", str(fx.output), "--repository", str(fx.repo),
                              "--expect-plan", self.test_plan, "--branch", "release",
                              "--expect-old", fx.base], expected=2)
        self.assertEqual(promotion["code"], "passing_test_evidence_required")
        refused = self.cli(self.publication_args(), expected=2)
        self.assertEqual(refused["code"], "passing_test_evidence_required")
        self.assertEqual(fx.git("rev-parse", "release"), fx.base)
        self.assertFalse(self.state.exists())

    def test_source_hooks_and_filters_are_not_inherited_by_installed_snapshot(self):
        fx = self.fx
        marker = fx.root / "UNEXPECTED-EXECUTION"
        # Commit raw export/filter attributes, then configure source-only hooks.
        (fx.repo / ".gitattributes").write_text("check.py export-ignore\nnested/tracked.txt filter=sentinel\n")
        fx.git("add", ".gitattributes")
        fx.git("commit", "-qm", "attributes are tracked data, not snapshot instructions")
        fx.commit, fx.tree = fx.git("rev-parse", "HEAD"), fx.git("rev-parse", "HEAD^{tree}")
        fx.specification["environment"].update(EXPECTED_COMMIT=fx.commit, EXPECTED_TREE=fx.tree)
        hook = fx.repo / ".git/hooks/post-checkout"
        hook.write_text("#!/bin/sh\nprintf executed > " + str(marker) + "\n")
        hook.chmod(0o700)
        fx.git("config", "filter.sentinel.smudge", "touch " + str(marker))
        fx.git("config", "filter.sentinel.clean", "touch " + str(marker))
        before = fx.files(fx.repo)
        self.install()
        self.run_checks()
        self.assertFalse(marker.exists())
        self.assertEqual(self.cli(self.verify_args())["status"], "passed")
        self.assertEqual(fx.files(fx.repo), before)


if __name__ == "__main__":
    if os.geteuid() == 0:
        sys.exit(subprocess.run([sys.executable, "-B", str(Path(__file__).resolve()), *sys.argv[1:]],
                                user=65534, group=65534, extra_groups=[],
                                env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"}).returncode)
    unittest.main()
