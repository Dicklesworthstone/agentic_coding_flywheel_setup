#!/usr/bin/env python3
"""Real Git snapshots and unprivileged test subprocesses; fixtures are retained."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/swarm-fleet-test.py"
spec = importlib.util.spec_from_file_location("candidate_tests", SCRIPT)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
PYTHON = "/usr/bin/python3"


class Fixture:
    def __init__(self, program="print('tested exact source')\n", fmt="sha1", files=None):
        self.root = Path(tempfile.mkdtemp(prefix="acfs-candidate-tests-"))
        self.repo = self.root / "repo"
        self.repo.mkdir(mode=0o700)
        self.output = self.root / "results"
        self.specfile = self.root / "tests.json"
        self.env = {"PATH": "/usr/bin:/bin", "HOME": str(self.root), "LANG": "C", "LC_ALL": "C",
                    "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
                    "GIT_AUTHOR_NAME": "Test", "GIT_COMMITTER_NAME": "Test",
                    "GIT_AUTHOR_EMAIL": "test@example.invalid", "GIT_COMMITTER_EMAIL": "test@example.invalid"}
        self.git("init", "--template=", "--initial-branch=main", "--object-format=" + fmt)
        self.git("read-tree", "--empty")
        contents = {"test.py": ("100644", program.encode()), "data.txt": ("100644", b"committed\n")}
        contents.update(files or {})
        for path, (mode, content) in contents.items():
            oid = self.git("hash-object", "-w", "--stdin", data=content).decode().strip()
            self.git("update-index", "--add", "--cacheinfo", mode + "," + oid + "," + path)
        self.tree = self.git("write-tree").decode().strip()
        self.commit = self.git("commit-tree", self.tree, data=b"test candidate\n").decode().strip()
        self.git("update-ref", "refs/heads/main", self.commit)
        # Keep working files deliberately different from the selected commit.
        (self.repo / "data.txt").write_text("uncommitted\n")
        (self.repo / "test.py").write_text("raise RuntimeError('DO NOT RUN WORKING COPY')\n")
        self.spec = {"schema": runner.SPEC_SCHEMA, "environment": {}, "commands": [
            {"id": "unit", "argv": [PYTHON, "-B", "test.py"], "timeout_seconds": 10}]}
        self.save_spec()

    def git(self, *args, data=b"", repo=None):
        result = subprocess.run(["/usr/bin/git", "-C", str(repo or self.repo), *args], input=data,
                                env=self.env, capture_output=True, timeout=10)
        if result.returncode:
            raise AssertionError((args, result.stderr))
        return result.stdout

    def save_spec(self):
        self.specfile.write_bytes(runner.encoded(self.spec))
        self.specfile.chmod(0o600)

    def preview(self, **kw):
        args = dict(repository=self.repo, commit=self.commit, spec=self.spec, output=self.output, timeout=30)
        args.update(kw)
        return runner.execute(**args)

    def apply(self, **kw):
        preview = self.preview(**kw)
        return self.preview(approval=preview["plan_sha256"], **kw)

    def cli(self, *extra, env=None):
        self.save_spec()
        return subprocess.run([sys.executable, "-I", str(SCRIPT), "--repository", str(self.repo),
            "--commit", self.commit, "--spec", str(self.specfile), "--output-dir", str(self.output),
            "--deadline", "30", *extra], capture_output=True, text=True, env=env or self.env, timeout=20)

    @staticmethod
    def contents(root):
        return {str(p.relative_to(root)): ("link", os.readlink(p)) if p.is_symlink()
                else ("file", p.stat().st_mode & 0o777, p.read_bytes())
                for p in root.rglob("*") if not p.is_dir()}


class CandidateTestTests(unittest.TestCase):
    def setUp(self):
        # Fixtures inherit the umask; a login user's 0002 makes them group-writable.
        self.addCleanup(os.umask, os.umask(0o022))
        self.assertNotEqual(os.geteuid(), 0, "Run unprivileged")

    def test_preview_is_repeatable_and_executes_nothing(self):
        fx = Fixture()
        before = fx.contents(fx.root)
        first, second = fx.preview(), fx.preview()
        self.assertEqual(first, second)
        self.assertEqual(first["status"], "preview")
        self.assertFalse(first["run_started"])
        self.assertFalse(first["plan"]["sandboxed"])
        self.assertEqual(fx.contents(fx.root), before)

    def test_runs_committed_bytes_not_dirty_checkout_and_preserves_repository(self):
        fx = Fixture("from pathlib import Path\nassert Path('data.txt').read_text() == 'committed\\n'\nprint('PASS')\n")
        before = fx.contents(fx.repo)
        result = fx.apply()
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["tests"][0]["exit_code"], 0)
        self.assertEqual((fx.output / "logs/unit.stdout").read_text(), "PASS\n")
        self.assertEqual(fx.contents(fx.repo), before)
        self.assertEqual(result["plan"]["commit"], fx.commit)
        self.assertEqual(result["plan"]["tree"], fx.tree)
        self.assertEqual(fx.output.stat().st_mode & 0o777, 0o700)
        self.assertEqual((fx.output / "result.json").stat().st_mode & 0o777, 0o600)
        for stream in ("stdout", "stderr"):
            evidence = result["tests"][0]["logs"][stream]
            raw = (fx.output / evidence["file"]).read_bytes()
            self.assertEqual((len(raw), runner.digest(raw)), (evidence["bytes"], evidence["sha256"]))

    def test_real_unittest_success_and_failure_not_just_sentinel_processes(self):
        code = "import unittest\nclass T(unittest.TestCase):\n def test_value(self): self.assertEqual(2+2, 4)\nunittest.main()\n"
        good = Fixture(code)
        self.assertEqual(good.apply()["status"], "passed")
        bad = Fixture(code.replace("2+2, 4", "2+2, 5"))
        result = bad.apply()
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["tests"][0]["exit_code"], 1)
        self.assertIn("FAIL", (bad.output / "logs/unit.stderr").read_text())

    def test_failure_stops_later_commands_and_keeps_exact_status(self):
        fx = Fixture("import sys\nprint('failure evidence', file=sys.stderr)\nsys.exit(23)\n")
        fx.spec["commands"].append({"id": "never", "argv": [PYTHON, "-c", "raise RuntimeError()"], "timeout_seconds": 10})
        result = fx.apply()
        self.assertEqual([r["status"] for r in result["tests"]], ["failed", "not_attempted"])
        self.assertEqual(result["tests"][0]["exit_code"], 23)
        self.assertFalse((fx.output / "never.attempt.json").exists())

    def test_command_signal_is_not_a_pass(self):
        fx = Fixture("import os, signal\nos.kill(os.getpid(), signal.SIGTERM)\n")
        row = fx.apply()["tests"][0]
        self.assertEqual((row["status"], row["exit_code"]), ("failed", -signal.SIGTERM))

    def test_timeout_kills_process_group_and_retains_partial_logs(self):
        fx = Fixture("import time\nprint('started', flush=True)\ntime.sleep(10)\n")
        fx.spec["commands"][0]["timeout_seconds"] = 1
        result = fx.apply()
        row = result["tests"][0]
        self.assertEqual(row["status"], "timed_out")
        self.assertEqual(row["exit_code"], -signal.SIGKILL)
        self.assertLess(row["duration_ms"], 5000)
        self.assertEqual((fx.output / "logs/unit.stdout").read_text(), "started\n")

    def test_output_limits_apply_to_both_streams(self):
        for stream in ("stdout", "stderr"):
            with self.subTest(stream=stream):
                fx = Fixture("import sys\nsys.%s.buffer.write(b'x' * (9 * 1024 * 1024))\n" % stream)
                row = fx.apply()["tests"][0]
                self.assertEqual(row["status"], "output_limit")
                self.assertEqual(sum(v["bytes"] for v in row["logs"].values()), runner.MAX_LOG_BYTES)

    def test_environment_is_explicit_and_home_and_caches_are_private(self):
        fx = Fixture("import os\nfrom pathlib import Path\n"
                     "assert 'ACFS_TEST_SECRET' not in os.environ\n"
                     "assert 'PYTHONPATH' not in os.environ\n"
                     "assert os.environ['PUBLIC_OPTION'] == 'literal $HOME'\n"
                     "assert os.environ['CI'] == 'true'\n"
                     "Path(os.environ['HOME'], 'test-cache').write_text('local')\n")
        fx.spec["environment"] = {"PUBLIC_OPTION": "literal $HOME"}
        preview = json.loads(fx.cli().stdout)
        result = fx.cli("--run", "--accept-plan", preview["plan_sha256"],
                        env={**fx.env, "ACFS_TEST_SECRET": "private", "PYTHONPATH": "/not-allowed"})
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual((fx.output / "home/test-cache").read_text(), "local")
        self.assertNotIn("private", (fx.output / "result.json").read_text())

    def test_tracked_source_changes_cannot_qualify_even_with_zero_exit(self):
        fx = Fixture("from pathlib import Path\nPath('data.txt').write_text('changed')\n")
        row = fx.apply()["tests"][0]
        self.assertEqual(row["status"], "sources_changed")
        self.assertEqual(row["exit_code"], 0)
        self.assertFalse(row["tracked_sources_unchanged"])

    def test_generated_untracked_outputs_are_allowed(self):
        fx = Fixture("from pathlib import Path\nPath('build').mkdir()\nPath('build/output').write_text('artifact')\n")
        self.assertEqual(fx.apply()["status"], "passed")

    def test_exact_paths_binary_executable_and_safe_symlinks(self):
        fx = Fixture("from pathlib import Path\nimport os\n"
                     "assert Path('copy').read_bytes() == bytes(range(256))\n"
                     "assert os.access('executable', os.X_OK)\n"
                     "assert Path(\"file with ' quote\\nand newline\").read_text() == 'literal'\n",
                     files={"binary": ("100644", bytes(range(256))), "copy": ("120000", b"binary"),
                            "executable": ("100755", b"#!/bin/sh\nexit 0\n"),
                            "file with ' quote\nand newline": ("100644", b"literal")})
        self.assertEqual(fx.apply()["status"], "passed")

    def test_unsafe_symlinks_are_refused_before_tests_run(self):
        for target in (b"/etc/passwd", b"../../outside", b"loop"):
            with self.subTest(target=target):
                fx = Fixture(files={"loop": ("120000", target)})
                with self.assertRaises(runner.fleet.Refused):
                    fx.apply()
                self.assertFalse((fx.output / "unit.attempt.json").exists())
                self.assertFalse((fx.output / "result.json").exists())

    def test_git_export_attributes_do_not_hide_or_rewrite_test_sources(self):
        fx = Fixture("from pathlib import Path\nassert Path('data.txt').read_text() == 'committed\\n'\n"
                     "assert Path('literal').read_text() == '$Format:%H$'\n", files={
                     ".gitattributes": ("100644", b"data.txt export-ignore\nliteral export-subst\n"),
                     "literal": ("100644", b"$Format:%H$")})
        self.assertEqual(fx.apply()["status"], "passed")

    def test_sha256_commit_and_tree_snapshots(self):
        fx = Fixture(fmt="sha256")
        result = fx.apply()
        self.assertEqual(result["status"], "passed")
        self.assertEqual(len(result["plan"]["commit"]), 64)

    def test_changed_spec_or_executable_invalidates_approval(self):
        fx = Fixture()
        preview = fx.preview()
        fx.spec["commands"][0]["argv"].append("different")
        with self.assertRaisesRegex(runner.fleet.Refused, "approval_mismatch"):
            fx.preview(approval=preview["plan_sha256"])
        self.assertFalse(fx.output.exists())
        script = fx.root / "executable"
        script.write_text("#!/bin/sh\nexit 0\n")
        script.chmod(0o700)
        fx.spec["commands"][0]["argv"] = [str(script)]
        preview = fx.preview()
        script.write_text("#!/bin/sh\nexit 1\n")
        with self.assertRaisesRegex(runner.fleet.Refused, "approval_mismatch"):
            fx.preview(approval=preview["plan_sha256"])
        self.assertFalse(fx.output.exists())

    def test_empty_commands_ambiguous_ids_and_startup_hooks_are_rejected(self):
        for change in (lambda v: v.update(commands=[]),
                       lambda v: v["commands"].append(v["commands"][0].copy()),
                       lambda v: v["commands"][0].update(timeout_seconds=True),
                       lambda v: v["commands"][0].update(argv=["python3"]),
                       lambda v: v["environment"].update(BASH_ENV="evil"),
                       lambda v: v["environment"].update(LD_PRELOAD="evil"),
                       lambda v: v["environment"].update(GIT_DIR="evil"),
                       lambda v: v["environment"].update(HOME="/real-home")):
            fx = Fixture()
            change(fx.spec)
            with self.assertRaises(runner.fleet.Refused):
                fx.preview()
            self.assertFalse(fx.output.exists())

    def test_full_commit_and_exact_run_authority_are_required(self):
        fx = Fixture()
        before = fx.contents(fx.root)
        for commit in ("HEAD", fx.commit[:8], "--help"):
            with self.assertRaises(runner.fleet.Refused):
                fx.preview(commit=commit)
        for flags in (("--run",), ("--accept-plan", "a" * 64), ("--apply",), ("--ru",)):
            result = fx.cli(*flags)
            self.assertEqual(result.returncode, 2)
        self.assertEqual(fx.contents(fx.root), before)

    def test_existing_evidence_is_never_reused_or_overwritten(self):
        fx = Fixture()
        result = fx.apply()
        before = fx.contents(fx.output)
        with self.assertRaisesRegex(runner.fleet.Refused, "state_already_exists"):
            fx.preview(approval=result["plan_sha256"])
        self.assertEqual(fx.contents(fx.output), before)

    def test_output_inside_source_repository_is_refused(self):
        fx = Fixture()
        for path in (fx.repo, fx.repo / "results", fx.repo / ".git/results"):
            with self.assertRaises(runner.fleet.Refused):
                fx.preview(output=path)
        self.assertFalse((fx.repo / "results").exists())

    def test_lfs_pointer_never_becomes_fake_materialized_test_data(self):
        fx = Fixture(files={"asset": ("100644", b"version https://git-lfs.github.com/spec/v1\noid sha256:abc\nsize 3\n")})
        with self.assertRaisesRegex(runner.fleet.Refused, "lfs_materialization_required"):
            fx.apply()
        self.assertFalse(fx.output.exists())

    def test_argv_is_literal_and_stdin_is_closed(self):
        fx = Fixture("import sys\nassert sys.argv[1:] == ['$(touch BAD)', 'spaces here', '']\nassert sys.stdin.read() == ''\n")
        fx.spec["commands"][0]["argv"] += ["$(touch BAD)", "spaces here", ""]
        self.assertEqual(fx.apply()["status"], "passed")
        self.assertFalse((fx.output / "workspace/BAD").exists())

    def test_sigkill_preserves_intent_without_success_record(self):
        fx = Fixture("from pathlib import Path\nimport os, time\nPath('../started').write_text(str(os.getpid()))\ntime.sleep(30)\n")
        preview = fx.preview()
        fx.save_spec()
        args = [sys.executable, "-I", str(SCRIPT), "--repository", str(fx.repo), "--commit", fx.commit,
                "--spec", str(fx.specfile), "--output-dir", str(fx.output), "--deadline", "30",
                "--run", "--accept-plan", preview["plan_sha256"]]
        import time
        process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=fx.env)
        try:
            deadline = time.monotonic() + 10
            while not (fx.output / "started").exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue((fx.output / "unit.attempt.json").exists())
            os.kill(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
            self.assertFalse((fx.output / "result.json").exists())
            self.assertTrue((fx.output / "intent.json").exists())
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=5)
        # SIGKILL cannot run cleanup; terminate only the known fixture child.
        # The command timeout is not a remote supervisor after controller death.
        pid = int((fx.output / "started").read_text())
        try:
            self.assertEqual(Path('/proc/%s/cwd' % pid).resolve(), fx.output / 'workspace')
            os.killpg(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    def test_real_published_integration_candidate_is_the_tested_tree(self):
        support_spec = importlib.util.spec_from_file_location("integration_fixture",
                        Path(__file__).with_name("test_swarm_fleet_integrate.py"))
        support = importlib.util.module_from_spec(support_spec)
        support_spec.loader.exec_module(support)
        code = ("import unittest\nfrom pathlib import Path\nclass T(unittest.TestCase):\n"
                " def test_combined(self):\n"
                "  self.assertEqual(Path('left').read_text() + Path('right').read_text(), 'leftright')\n"
                "unittest.main()\n")
        fx = support.Fixture(files={"test.py": ("100644", code.encode())})
        for name in ("left", "right"):
            commit = fx.commit(name, [fx.base], {name: ("100644", name.encode())})
            fx.add_host(name, commit)
        fx.seal()
        preview = fx.preview()
        published = fx.preview(approval=preview["plan_sha256"])
        self.assertEqual(published["status"], "integrated")
        before = fx.contents(fx.repo)
        commit = published["plan"]["result"]["candidate_commit"]
        spec = {"schema": runner.SPEC_SCHEMA, "environment": {}, "commands": [
                {"id": "combined", "argv": [PYTHON, "-B", "test.py"], "timeout_seconds": 10}]}
        options = dict(repository=fx.repo, commit=commit, spec=spec, output=fx.root / "qualification")
        plan = runner.execute(**options)
        tested = runner.execute(**options, approval=plan["plan_sha256"])
        self.assertEqual(tested["status"], "passed")
        self.assertEqual(tested["plan"]["tree"], published["plan"]["result"]["candidate_tree"])
        self.assertEqual(fx.contents(fx.repo), before)

    def test_linked_worktree_does_not_redirect_output_into_common_git(self):
        fx = Fixture()
        linked = fx.root / "linked"
        fx.git("worktree", "add", "--detach", "--no-checkout", str(linked), fx.commit)
        before = fx.contents(fx.repo)
        with self.assertRaises(runner.fleet.Refused):
            fx.preview(repository=linked, output=fx.repo / ".git/results")
        self.assertEqual(fx.apply(repository=linked)["status"], "passed")
        self.assertEqual(fx.contents(fx.repo), before)

    def test_gitlinks_are_refused_instead_of_testing_incomplete_submodules(self):
        fx = Fixture()
        fx.git("update-index", "--add", "--cacheinfo", "160000," + fx.commit + ",submodule")
        tree = fx.git("write-tree").decode().strip()
        commit = fx.git("commit-tree", tree, data=b"with submodule").decode().strip()
        with self.assertRaisesRegex(runner.fleet.Refused, "submodule_or_special_tree_entry"):
            fx.preview(commit=commit)
        self.assertFalse(fx.output.exists())

    def test_corrupt_blob_is_rejected_before_output_or_tests(self):
        fx = Fixture()
        oid = fx.git("rev-parse", fx.commit + ":data.txt").decode().strip()
        path = fx.repo / ".git/objects" / oid[:2] / oid[2:]
        import zlib
        path.chmod(0o600)
        raw = b"malicious\n"
        path.write_bytes(zlib.compress(b"blob " + str(len(raw)).encode() + b"\0" + raw))
        with self.assertRaises(runner.fleet.Refused):
            fx.apply()
        self.assertFalse(fx.output.exists())

    def test_test_phase_deadline_stops_after_aggregate_budget(self):
        fx = Fixture("import time\ntime.sleep(0.65)\n")
        fx.spec["commands"] *= 2
        fx.spec["commands"][1] = {**fx.spec["commands"][1], "id": "second"}
        result = fx.apply(timeout=1)
        self.assertEqual([r["status"] for r in result["tests"]], ["passed", "timed_out"])


if __name__ == "__main__":
    if os.geteuid() == 0:
        os.setgroups([])
        os.setgid(65534)
        os.setuid(65534)
        os.execv(sys.executable, [sys.executable, "-B", __file__, *sys.argv[1:]])
    unittest.main()
