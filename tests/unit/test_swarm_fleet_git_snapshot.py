#!/usr/bin/env python3
"""Real Git-dependent candidate tests, independent snapshots and evidence gates.

Fixtures are private and intentionally retained, including failed runs. No SSH,
provider, network or source-repository write is performed by the test controller.
"""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zlib

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "scripts/swarm-fleet-test.py"
spec = importlib.util.spec_from_file_location("git_snapshot_runner", SOURCE)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

CHECK = '''import os, subprocess
from pathlib import Path

def git(*args, check=True):
    p = subprocess.run(["/usr/bin/git", *args], capture_output=True, text=True)
    if check: assert p.returncode == 0, (args, p.stderr)
    return p
assert git("rev-parse", "HEAD").stdout.strip() == os.environ["EXPECTED_COMMIT"]
assert git("rev-parse", "HEAD^{tree}").stdout.strip() == os.environ["EXPECTED_TREE"]
assert git("rev-parse", "--is-shallow-repository").stdout.strip() == "true"
assert git("rev-list", "--count", "HEAD").stdout.strip() == "1"
assert git("ls-files", "--error-unmatch", "nested/tracked.txt").returncode == 0
assert git("status", "--porcelain").stdout == ""
git("diff", "--exit-code")
assert git("remote").stdout == ""
assert git("tag", "--list").stdout == ""
assert git("cat-file", "-e", os.environ["PARENT_COMMIT"], check=False).returncode != 0
assert not Path(".git/hooks").exists()
assert not Path(".git/objects/info/alternates").exists()
assert Path("nested/tracked.txt").read_text() == "candidate\\n"
assert Path("link").is_symlink()
print("checked actual detached commit, index and independent objects")
'''


class GitSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="acfs-git-snapshot-test-"))
        self.root.chmod(0o700)
        self.home = self.root / "home"
        self.home.mkdir(mode=0o700)
        self.env = {"PATH": "/usr/bin:/bin", "HOME": str(self.home), "LANG": "C.UTF-8",
                    "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
                    "GIT_AUTHOR_NAME": "Snapshot test", "GIT_AUTHOR_EMAIL": "snapshot@localhost",
                    "GIT_COMMITTER_NAME": "Snapshot test", "GIT_COMMITTER_EMAIL": "snapshot@localhost"}
        self.make_repository("sha1")

    def git(self, *args):
        result = subprocess.run(["/usr/bin/git", "-C", str(self.repo), *args], env=self.env,
                                capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.decode().strip()

    def make_repository(self, fmt):
        self.repo = self.root / ("project-" + fmt)
        self.repo.mkdir(mode=0o700)
        self.git("init", "-q", "-b", "main", "--object-format=" + fmt)
        (self.repo / "nested").mkdir(mode=0o700)
        (self.repo / "nested/tracked.txt").write_text("base\n")
        (self.repo / "check.py").write_text(CHECK)
        (self.repo / "tool.sh").write_text("#!/bin/sh\nexit 0\n")
        (self.repo / "tool.sh").chmod(0o700)
        (self.repo / "link").symlink_to("nested/tracked.txt")
        self.git("add", ".")
        self.git("commit", "-q", "-m", "base")
        self.base = self.git("rev-parse", "HEAD")
        (self.repo / "nested/tracked.txt").write_text("candidate\n")
        self.git("commit", "-qam", "candidate")
        self.commit = self.git("rev-parse", "HEAD")
        self.tree = self.git("rev-parse", "HEAD^{tree}")
        self.output = self.root / ("test-run-" + fmt)
        self.specification = {"schema": runner.SPEC_SCHEMA, "commands": [
            {"id": "git-check", "argv": ["/usr/bin/python3", "check.py"], "timeout_seconds": 10}],
            "environment": {"EXPECTED_COMMIT": self.commit, "EXPECTED_TREE": self.tree, "PARENT_COMMIT": self.base}}

    def execute(self, approval=None, snapshot=True):
        return runner.execute(self.repo, self.commit, self.specification, self.output,
                              timeout=30, approval=approval, git_snapshot=snapshot)

    def run_test(self):
        preview = self.execute()
        result = self.execute(preview["plan_sha256"])
        self.assertEqual(result["status"], "passed", result)
        self.approval = preview["plan_sha256"]
        return result

    def verify(self):
        return runner.verify_test_run(self.output, self.repo, self.approval, 30)

    def files(self, root):
        return {str(p.relative_to(root)): ("link", os.readlink(p)) if p.is_symlink()
                else ("dir", p.stat().st_mode) if p.is_dir()
                else ("file", p.stat().st_mode, p.read_bytes()) for p in root.rglob("*")}

    def test_real_git_commands_pass_and_source_is_byte_for_byte_untouched(self):
        self.git("remote", "add", "origin", "ssh://private.invalid/sensitive.git")
        self.git("tag", "private-release")
        (self.repo / "untracked-secret").write_text("never copy me")
        (self.repo / "nested/tracked.txt").write_text("dirty source stays dirty\n")
        before = self.files(self.repo)
        result = self.run_test()
        self.assertEqual(self.files(self.repo), before)
        self.assertFalse((self.output / "workspace/untracked-secret").exists())
        self.assertFalse(result["plan"]["git_history_included"])
        self.assertEqual(result["plan"]["git_snapshot"], runner.GIT_SNAPSHOT_MODE)
        self.assertEqual(self.verify()["status"], "passed")
        self.assertEqual(self.files(self.repo), before)

    def test_preview_is_read_only_and_option_is_bound_to_approval(self):
        before = self.files(self.root)
        preview = self.execute()
        self.assertEqual(preview, self.execute())
        legacy = self.execute(snapshot=False)
        self.assertNotIn("git_snapshot", legacy["plan"])
        self.assertNotEqual(preview["plan_sha256"], legacy["plan_sha256"])
        for approval, selected in ((preview["plan_sha256"], False), (legacy["plan_sha256"], True)):
            with self.assertRaisesRegex(runner.fleet.Refused, "test_approval_mismatch"):
                self.execute(approval, selected)
        self.assertEqual(self.files(self.root), before)

    def test_without_opt_in_git_dependent_test_still_fails_without_git_metadata(self):
        preview = self.execute(snapshot=False)
        result = self.execute(preview["plan_sha256"], snapshot=False)
        self.assertEqual(result["status"], "failed")
        self.assertFalse((self.output / "workspace/.git").exists())
        self.approval = preview["plan_sha256"]
        self.assertEqual(self.verify()["status"], "failed")

    def test_legacy_non_git_test_evidence_remains_supported(self):
        self.specification["commands"][0]["argv"] = ["/usr/bin/python3", "-c", "print('legacy')"]
        preview = self.execute(snapshot=False)
        self.assertEqual(self.execute(preview["plan_sha256"], snapshot=False)["status"], "passed")
        self.approval = preview["plan_sha256"]
        self.assertEqual(self.verify()["status"], "passed")

    def test_sha256_repository_runs_real_git_and_verifies_evidence(self):
        self.make_repository("sha256")
        self.run_test()
        self.assertEqual(self.verify()["status"], "passed")

    def test_names_order_nested_trees_and_unicode_are_preserved(self):
        for name in ("nested.c", "nested-/a", "nested/z/leaf", "unicodé/quote' and\nnewline"):
            path = self.repo / name
            path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            path.write_text(name)
        self.git("add", ".")
        self.git("commit", "-qm", "unusual names")
        self.commit, self.tree = self.git("rev-parse", "HEAD"), self.git("rev-parse", "HEAD^{tree}")
        self.specification["environment"].update(EXPECTED_COMMIT=self.commit, EXPECTED_TREE=self.tree)
        self.run_test()
        self.assertEqual(self.verify()["status"], "passed")

    def test_stat_refresh_and_index_version_four_do_not_invalidate_evidence(self):
        self.run_test()
        work = self.output / "workspace"
        before = (work / ".git/index").read_bytes()
        result = subprocess.run(["/usr/bin/git", "-C", str(work), "update-index", "--index-version=4"],
                                capture_output=True, env=self.env, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotEqual((work / ".git/index").read_bytes(), before)
        unchanged = self.files(self.output)
        self.assertEqual(self.verify()["status"], "passed")
        self.assertEqual(self.files(self.output), unchanged)

    def test_changed_git_control_files_fail_without_executing_their_configuration(self):
        self.run_test()
        root = self.output / "workspace/.git"
        marker = self.root / "NEVER_EXECUTE"
        for name, value in (("HEAD", self.base + "\n"), ("shallow", ""),
                            ("config", "[core]\n fsmonitor = touch " + str(marker) + "\n")):
            with self.subTest(name=name):
                path = root / name
                old = path.read_bytes()
                path.write_text(value)
                before = self.files(self.output)
                self.assertEqual(self.verify()["status"], "sources_changed")
                self.assertEqual(self.files(self.output), before)
                self.assertFalse(marker.exists())
                path.write_bytes(old)
        self.assertEqual(self.verify()["status"], "passed")

    def test_changed_index_staging_is_not_a_successful_test_of_the_original_commit(self):
        self.run_test()
        work = self.output / "workspace"
        result = subprocess.run(["/usr/bin/git", "-C", str(work), "rm", "--cached", "nested/tracked.txt"],
                                capture_output=True, env=self.env, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((work / "nested/tracked.txt").read_text(), "candidate\n")
        self.assertEqual(self.verify()["status"], "sources_changed")

    def test_modified_git_stops_the_remaining_commands_even_after_exit_zero(self):
        self.specification["commands"] = [
            {"id": "mutate", "argv": ["/usr/bin/python3", "-c",
                "from pathlib import Path; Path('.git/HEAD').write_text('0'*40+'\\n')"], "timeout_seconds": 5},
            {"id": "never", "argv": ["/usr/bin/python3", "-c", "raise RuntimeError('must not run')"], "timeout_seconds": 5}]
        preview = self.execute()
        result = self.execute(preview["plan_sha256"])
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["tests"][0]["status"], "sources_changed")
        self.assertEqual(result["tests"][0]["exit_code"], 0)
        self.assertEqual(result["tests"][1]["status"], "not_attempted")
        self.approval = preview["plan_sha256"]
        self.assertEqual(self.verify()["status"], "sources_changed")

    def test_corrupt_trailing_and_expansion_bomb_objects_are_refused(self):
        self.run_test()
        root = self.output / "workspace/.git/objects"
        path = root / self.commit[:2] / self.commit[2:]
        old = path.read_bytes()
        for raw in (b"not zlib", old + b"trailing", zlib.compress(b"x" * 1000000),
                    zlib.compress(b"commit 0\0")):
            with self.subTest(size=len(raw)):
                path.write_bytes(raw)
                self.assertEqual(self.verify()["status"], "sources_changed")
        path.write_bytes(zlib.compress(zlib.decompress(old), level=0))
        self.assertEqual(self.verify()["status"], "passed")

    def test_extra_refs_hooks_and_alternates_are_refused(self):
        self.run_test()
        root = self.output / "workspace/.git"
        for directory in ("hooks", "objects/info"):
            path = root / directory
            path.mkdir(mode=0o700)
            (path / "untrusted").write_text("not a trusted snapshot member")
            self.assertEqual(self.verify()["status"], "sources_changed")
            path.rename(self.root / directory.replace("/", "-"))
        ref = root / "refs/heads/unreviewed"
        ref.write_text(self.commit + "\n")
        self.assertEqual(self.verify()["status"], "sources_changed")

    def test_git_directory_and_index_links_never_redirect_verification(self):
        self.run_test()
        root = self.output / "workspace/.git"
        index = root / "index"
        index.rename(self.root / "saved-index")
        index.symlink_to(self.root / "saved-index")
        self.assertEqual(self.verify()["status"], "sources_changed")
        index.rename(self.root / "saved-link")
        os.mkfifo(index, 0o600)
        self.assertEqual(self.verify()["status"], "sources_changed")
        root.rename(self.root / "retained-git")
        root.symlink_to(self.repo / ".git", target_is_directory=True)
        before = self.files(self.repo)
        self.assertEqual(self.verify()["status"], "sources_changed")
        self.assertEqual(self.files(self.repo), before)

    def test_exact_git_snapshot_evidence_can_promote_but_tampering_cannot(self):
        self.git("branch", "release", self.base)
        self.run_test()
        args = (self.output, self.repo, self.approval, "release", self.base)
        preview = runner.promote_candidate(*args)
        result = runner.promote_candidate(*args, approval=preview["plan_sha256"])
        self.assertEqual(result["status"], "promoted")
        self.assertEqual(self.git("rev-parse", "release"), self.commit)
        self.git("branch", "other-release", self.base)
        (self.output / "workspace/.git/HEAD").write_text(self.base + "\n")
        with self.assertRaisesRegex(runner.fleet.Refused, "passing_test_evidence_required"):
            runner.promote_candidate(self.output, self.repo, self.approval, "other-release", self.base)
        self.assertEqual(self.git("rev-parse", "other-release"), self.base)

    def test_unknown_snapshot_modes_and_unapproved_fields_are_refused(self):
        preview = self.execute()
        for change in (lambda p: p.update(git_snapshot=True), lambda p: p.update(git_snapshot="full-history"),
                       lambda p: p.update(git_history_included=True), lambda p: p.update(policy="unknown"),
                       lambda p: p.update(policy="exact-tree-explicit-unsandboxed-tests-v1")):
            plan = copy.deepcopy(preview["plan"])
            change(plan)
            with self.assertRaises(runner.fleet.Refused):
                runner.evidence_plan(plan, runner.digest(runner.encoded(plan)))

    def test_cli_opt_in_and_verification_use_the_same_controller(self):
        path = self.root / "spec.json"
        path.write_text(json.dumps(self.specification))
        path.chmod(0o600)
        args = [sys.executable, "-I", str(SOURCE), "--repository", str(self.repo), "--commit", self.commit,
                "--spec", str(path), "--output-dir", str(self.output), "--git-snapshot"]
        preview = subprocess.run(args, capture_output=True, text=True, env=self.env, timeout=20)
        self.assertEqual(preview.returncode, 0, preview.stdout + preview.stderr)
        self.approval = json.loads(preview.stdout)["plan_sha256"]
        run = subprocess.run([*args, "--run", "--accept-plan", self.approval],
                             capture_output=True, text=True, env=self.env, timeout=20)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertEqual(json.loads(run.stdout)["status"], "passed")
        self.assertEqual(self.verify()["status"], "passed")


if __name__ == "__main__":
    if os.geteuid() == 0:
        # Exercise production ownership checks as an actual unprivileged user.
        sys.exit(subprocess.run([sys.executable, "-B", str(Path(__file__).resolve()), *sys.argv[1:]],
                                user=65534, group=65534, extra_groups=[],
                                env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"}).returncode)
    unittest.main()
