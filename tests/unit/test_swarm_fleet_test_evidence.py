#!/usr/bin/env python3
"""Verify real runner evidence; retain fixtures and never manufacture a pass."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("test_runner_fixture", Path(__file__).with_name("test_swarm_fleet_test.py"))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
runner, Fixture, SCRIPT = base.runner, base.Fixture, base.SCRIPT


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.assertNotEqual(os.geteuid(), 0)

    def inspect(self, fx, result, **kw):
        args = dict(path=fx.output, repository=fx.repo, expected=result["plan_sha256"])
        args.update(kw)
        return runner.verify_test_run(**args)

    def rewrite(self, fx, change, row=None):
        path = fx.output / "result.json"
        value = json.loads(path.read_text())
        change(value)
        path.write_bytes(runner.encoded(value))
        if row is not None:
            (fx.output / (value["tests"][row]["id"] + ".result.json")).write_bytes(runner.encoded(value["tests"][row]))

    def test_pass_is_bound_to_full_plan_commit_tree_and_unchanged_evidence(self):
        fx = Fixture("import unittest\nclass T(unittest.TestCase):\n def test_real(self): self.assertEqual(2+2, 4)\nunittest.main()\n")
        result = fx.apply()
        before = fx.contents(fx.root)
        report = self.inspect(fx, result)
        self.assertEqual(report["status"], "passed")
        self.assertEqual(report["commit"], fx.commit)
        self.assertEqual(report["tree"], fx.tree)
        self.assertTrue(report["complete"])
        self.assertTrue(report["tracked_sources_unchanged"])
        self.assertFalse(report["test_provenance_verified"])
        self.assertFalse(report["tests_rerun"])
        self.assertEqual(self.inspect(fx, result), report)
        self.assertEqual(fx.contents(fx.root), before)

    def test_failed_tests_and_unattempted_suffix_are_preserved(self):
        fx = Fixture("raise SystemExit(23)\n")
        fx.spec["commands"].append({"id": "later", "argv": [base.PYTHON, "-c", "raise SystemExit(0)"], "timeout_seconds": 10})
        result = fx.apply()
        report = self.inspect(fx, result)
        self.assertEqual(report["status"], "failed")
        self.assertEqual([r["status"] for r in report["tests"]], ["failed", "not_attempted"])
        self.assertEqual(report["tests"][0]["exit_code"], 23)

    def test_timeout_and_output_exhaustion_remain_failed_evidence(self):
        for code in ("import time\ntime.sleep(10)\n", "import sys\nsys.stdout.buffer.write(b'x'*9000000)\n"):
            with self.subTest(code=code):
                fx = Fixture(code)
                fx.spec["commands"][0]["timeout_seconds"] = 1
                result = fx.apply()
                report = self.inspect(fx, result)
                self.assertEqual(report["status"], "failed")
                self.assertIn(report["tests"][0]["status"], ("timed_out", "output_limit"))

    def test_summary_alone_cannot_turn_failure_into_pass(self):
        fx = Fixture("raise SystemExit(1)\n")
        result = fx.apply()
        self.rewrite(fx, lambda v: v.update(status="passed"))
        with self.assertRaisesRegex(runner.fleet.Refused, "summary_mismatch"):
            self.inspect(fx, result)

    def test_exit_zero_boolean_and_missing_command_cannot_forge_pass(self):
        for edit, row in ((lambda v: v["tests"][0].update(exit_code=23), 0),
                          (lambda v: v["tests"][0].update(exit_code=False), 0),
                          (lambda v: v["tests"].clear(), None)):
            fx = Fixture()
            result = fx.apply()
            self.rewrite(fx, edit, row=row)
            with self.assertRaises(runner.fleet.Refused):
                self.inspect(fx, result)

    def test_command_attempt_and_final_row_must_match(self):
        fx = Fixture()
        result = fx.apply()
        attempt = fx.output / "unit.attempt.json"
        value = json.loads(attempt.read_text())
        value["command"]["argv"].append("unreviewed")
        attempt.write_bytes(runner.encoded(value))
        with self.assertRaisesRegex(runner.fleet.Refused, "record_mismatch"):
            self.inspect(fx, result)

    def test_log_tampering_and_retargeted_log_path_are_refused(self):
        fx = Fixture()
        result = fx.apply()
        (fx.output / "logs/unit.stdout").write_text("different output\n")
        with self.assertRaisesRegex(runner.fleet.Refused, "log_mismatch"):
            self.inspect(fx, result)
        other = Fixture()
        result = other.apply()
        self.rewrite(other, lambda v: v["tests"][0]["logs"]["stdout"].update(file="../secret"), row=0)
        with self.assertRaisesRegex(runner.fleet.Refused, "log_mismatch"):
            self.inspect(other, result)

    def test_current_workspace_mutation_revokes_qualification(self):
        fx = Fixture()
        result = fx.apply()
        (fx.output / "workspace/data.txt").write_text("edited after tests\n")
        report = self.inspect(fx, result)
        self.assertEqual(report["status"], "sources_changed")
        self.assertFalse(report["tracked_sources_unchanged"])
        self.assertEqual(report["tests"][0]["status"], "passed")

    def test_safe_links_are_verified_and_retargeting_is_not_accepted(self):
        fx = Fixture(files={"link": ("120000", b"data.txt")})
        result = fx.apply()
        self.assertEqual(self.inspect(fx, result)["status"], "passed")
        link = fx.output / "workspace/link"
        link.rename(fx.root / "retained-link")
        link.symlink_to("test.py")
        self.assertEqual(self.inspect(fx, result)["status"], "sources_changed")

    def test_generated_outputs_are_not_misclassified_as_source_mutations(self):
        fx = Fixture("from pathlib import Path\nPath('build').mkdir()\nPath('build/data').write_text('generated')\n")
        result = fx.apply()
        self.assertEqual(self.inspect(fx, result)["status"], "passed")

    def test_log_symlinks_hardlinks_and_nonprivate_files_are_refused(self):
        for kind in ("symlink", "hardlink", "permissions"):
            fx = Fixture()
            result = fx.apply()
            path = fx.output / "logs/unit.stdout"
            saved = fx.root / "retained-log"
            path.rename(saved)
            if kind == "symlink":
                path.symlink_to(saved)
            elif kind == "hardlink":
                os.link(saved, path)
            else:
                path.write_bytes(saved.read_bytes())
                path.chmod(0o644)
            with self.subTest(kind=kind), self.assertRaises((runner.fleet.Refused, OSError)):
                self.inspect(fx, result)

    def test_missing_final_result_is_incomplete_never_reconstructed(self):
        fx = Fixture()
        result = fx.apply()
        (fx.output / "result.json").rename(fx.root / "retained-result.json")
        before = fx.contents(fx.root)
        report = self.inspect(fx, result)
        self.assertEqual(report["status"], "incomplete")
        self.assertIsNone(report["evidence_sha256"])
        self.assertFalse(report["complete"])
        self.assertEqual(fx.contents(fx.root), before)

    def test_original_digest_and_repository_are_required(self):
        fx = Fixture()
        result = fx.apply()
        with self.assertRaisesRegex(runner.fleet.Refused, "plan_mismatch"):
            self.inspect(fx, result, expected="0" * 64)
        other = Fixture()
        with self.assertRaisesRegex(runner.fleet.Refused, "repository_mismatch"):
            self.inspect(fx, result, repository=other.repo)

    def test_historical_executable_is_not_run_or_required_to_still_exist(self):
        fx = Fixture()
        program = fx.root / "test-command"
        program.write_text("#!/bin/sh\nprintf 'historical result\\n'\n")
        program.chmod(0o700)
        fx.spec["commands"][0]["argv"] = [str(program)]
        result = fx.apply()
        program.rename(fx.root / "old-command")
        self.assertEqual(self.inspect(fx, result)["status"], "passed")

    def test_sha256_and_linked_repository_identity(self):
        fx = Fixture(fmt="sha256")
        linked = fx.root / "linked"
        fx.git("worktree", "add", "--detach", "--no-checkout", str(linked), fx.commit)
        result = fx.apply(repository=linked)
        self.assertEqual(self.inspect(fx, result, repository=linked)["status"], "passed")
        with self.assertRaisesRegex(runner.fleet.Refused, "repository_mismatch"):
            self.inspect(fx, result)

    def test_exclusive_lock_and_mid_read_mutation_are_detected(self):
        import fcntl
        fx = Fixture()
        result = fx.apply()
        with runner.fleet.directory_fd(fx.output, private=True) as fd:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(runner.fleet.Refused, "operation_in_progress"):
                self.inspect(fx, result)
        with self.assertRaisesRegex(runner.fleet.Refused, "evidence_changed"):
            with runner.test_evidence(fx.output, fx.repo, result["plan_sha256"]) as (_, _, _, guard):
                (fx.output / "logs/unit.stdout").write_text("changed during observation")
                guard()

    def test_extra_root_records_and_extra_logs_do_not_qualify(self):
        for name in ("unexpected.json", "logs/unexpected.stdout"):
            fx = Fixture()
            result = fx.apply()
            extra = fx.output / name
            extra.write_text("unrecorded")
            extra.chmod(0o600)
            with self.subTest(name=name), self.assertRaisesRegex(runner.fleet.Refused, "unexpected_test_evidence"):
                self.inspect(fx, result)

    def test_real_sigkill_leaves_unconfirmed_run_without_rerunning(self):
        fx = Fixture("pass\n")
        plan = fx.preview()
        # Crash the real runner immediately after the real command result was
        # durably written, before its completion marker. No sleeping child leaks.
        program = f'''import importlib.util, os, signal
spec = importlib.util.spec_from_file_location("r", {str(SCRIPT)!r})
r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
original = r.fleet.publish
def crash(fd, name, value):
    original(fd, name, value)
    if name == 'unit.result.json': os.kill(os.getpid(), signal.SIGKILL)
r.fleet.publish = crash
r.execute({str(fx.repo)!r}, {fx.commit!r}, {fx.spec!r}, {str(fx.output)!r}, 30, {plan['plan_sha256']!r})
'''
        result = subprocess.run([sys.executable, "-I", "-c", program], env=fx.env, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, -signal.SIGKILL, result.stderr)
        self.assertTrue((fx.output / "unit.result.json").is_file())
        before = fx.contents(fx.root)
        self.assertEqual(self.inspect(fx, plan)["status"], "incomplete")
        self.assertEqual(fx.contents(fx.root), before)

    def test_cli_reports_integrity_status_and_refuses_execution_flags(self):
        fx = Fixture()
        result = fx.apply()
        args = [sys.executable, "-I", str(SCRIPT), "--verify", str(fx.output),
                "--repository", str(fx.repo), "--expect-plan", result["plan_sha256"]]
        before = fx.contents(fx.root)
        verified = subprocess.run(args, env=fx.env, capture_output=True, text=True, timeout=20)
        self.assertEqual(verified.returncode, 0, verified.stdout + verified.stderr)
        self.assertEqual(json.loads(verified.stdout)["status"], "passed")
        for flags in (["--run"], ["--apply"], ["--spec", str(fx.specfile)]):
            refused = subprocess.run(args + flags, env=fx.env, capture_output=True, timeout=20)
            self.assertEqual(refused.returncode, 2)
        self.assertEqual(fx.contents(fx.root), before)
        (fx.output / "workspace/data.txt").write_text("changed")
        result = subprocess.run(args, env=fx.env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)


if __name__ == "__main__":
    if os.geteuid() == 0:
        os.setgroups([])
        os.setgid(65534)
        os.setuid(65534)
        os.execv(sys.executable, [sys.executable, "-B", __file__, *sys.argv[1:]])
    unittest.main()
