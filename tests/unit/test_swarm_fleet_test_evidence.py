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

    def test_an_attempt_after_failure_cannot_be_accepted_as_an_ordered_run(self):
        fx = Fixture("raise SystemExit(1)\n")
        fx.spec["commands"].append({"id": "later", "argv": [base.PYTHON, "-c", "pass"], "timeout_seconds": 10})
        result = fx.apply()
        value = json.loads((fx.output / "result.json").read_text())
        row = {**value["tests"][0], "id": "later", "status": "passed", "exit_code": 0}
        value["tests"][1] = row
        (fx.output / "result.json").write_bytes(runner.encoded(value))
        with runner.fleet.directory_fd(fx.output, private=True) as fd:
            runner.fleet.publish(fd, "later.attempt.json", {"schema": runner.SCHEMA,
                "plan_sha256": result["plan_sha256"], "command": fx.spec["commands"][1]})
            runner.fleet.publish(fd, "later.result.json", row)
        with self.assertRaisesRegex(runner.fleet.Refused, "nonprefix_history"):
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


class PromotionTests(unittest.TestCase):
    def setUp(self):
        self.assertNotEqual(os.geteuid(), 0)

    def fixture(self, fmt="sha1", program="print('candidate passed')\n"):
        fx = Fixture(program, fmt=fmt)
        fx.old = fx.commit
        blob = fx.git("hash-object", "-w", "--stdin", data=b"new tested feature\n").decode().strip()
        fx.git("update-index", "--add", "--cacheinfo", "100644," + blob + ",feature.txt")
        fx.tree = fx.git("write-tree").decode().strip()
        fx.commit = fx.git("commit-tree", fx.tree, "-p", fx.old, data=b"candidate\n").decode().strip()
        fx.git("update-ref", "refs/acfs/integrations/wave", fx.commit)
        fx.git("update-ref", "refs/heads/release", fx.old)
        fx.test_result = fx.apply()
        return fx

    def promote(self, fx, **kw):
        options = dict(path=fx.output, repository=fx.repo, expected=fx.test_result["plan_sha256"],
                       branch="release", old=fx.old, timeout=30)
        options.update(kw)
        return runner.promote_candidate(**options)

    def applied(self, fx, **kw):
        preview = self.promote(fx, **kw)
        return self.promote(fx, approval=preview["plan_sha256"], **kw)

    def value(self, fx):
        return fx.git("rev-parse", "refs/heads/release").decode().strip()

    def test_preview_is_repeatable_and_does_not_change_any_files(self):
        fx = self.fixture()
        before = fx.contents(fx.root)
        report = self.promote(fx)
        self.assertEqual(report, self.promote(fx))
        self.assertEqual(report["status"], "preview")
        self.assertEqual(report["plan"]["candidate_commit"], fx.commit)
        self.assertEqual(report["plan"]["expected_old_commit"], fx.old)
        self.assertNotEqual(report["plan_sha256"], fx.test_result["plan_sha256"])
        self.assertEqual(fx.contents(fx.root), before)

    def test_only_approved_branch_and_its_reflog_change_not_checkout_or_objects(self):
        fx = self.fixture()
        before = fx.contents(fx.repo)
        evidence = fx.contents(fx.output)
        result = self.applied(fx)
        self.assertEqual(result["status"], "promoted")
        self.assertEqual(self.value(fx), fx.commit)
        self.assertEqual(fx.git("rev-parse", "HEAD").decode().strip(), fx.old)
        after = fx.contents(fx.repo)
        changed = {p for p in set(before) | set(after) if before.get(p) != after.get(p)}
        self.assertIn(".git/refs/heads/release", changed)
        self.assertLessEqual(changed, {".git/refs/heads/release", ".git/logs/refs/heads/release"})
        self.assertEqual(fx.contents(fx.output), evidence)
        with self.assertRaisesRegex(runner.fleet.Refused, "branch_changed"):
            self.promote(fx, approval=result["plan_sha256"])

    def test_test_approval_does_not_authorize_branch_promotion(self):
        fx = self.fixture()
        with self.assertRaisesRegex(runner.fleet.Refused, "promotion_approval_mismatch"):
            self.promote(fx, approval=fx.test_result["plan_sha256"])
        self.assertEqual(self.value(fx), fx.old)

    def test_failed_incomplete_and_edited_runs_cannot_promote(self):
        for kind in ("failed", "incomplete", "changed"):
            fx = self.fixture(program="raise SystemExit(1)\n" if kind == "failed" else "pass\n")
            if kind == "incomplete":
                (fx.output / "result.json").rename(fx.root / "retained-result.json")
            elif kind == "changed":
                (fx.output / "workspace/feature.txt").write_text("not tested")
            before = fx.contents(fx.repo)
            with self.subTest(kind=kind), self.assertRaisesRegex(runner.fleet.Refused, "passing_test_evidence_required"):
                self.promote(fx)
            self.assertEqual(fx.contents(fx.repo), before)

    def test_main_and_linked_checked_out_branches_are_refused(self):
        fx = self.fixture()
        with self.assertRaisesRegex(runner.fleet.Refused, "branch_is_checked_out"):
            self.promote(fx, branch="main")
        linked = fx.root / "linked with a newline\nquote'"
        fx.git("worktree", "add", "--no-checkout", str(linked), "release")
        before = fx.contents(fx.repo)
        with self.assertRaisesRegex(runner.fleet.Refused, "branch_is_checked_out"):
            self.promote(fx)
        self.assertEqual(fx.contents(fx.repo), before)

    def test_prunable_worktree_registration_still_blocks_promotion(self):
        fx = self.fixture()
        linked = fx.root / "linked"
        fx.git("worktree", "add", "--no-checkout", str(linked), "release")
        linked.rename(fx.root / "retained-linked")
        with self.assertRaisesRegex(runner.fleet.Refused, "branch_is_checked_out"):
            self.promote(fx)
        self.assertEqual(self.value(fx), fx.old)

    def test_checked_out_symbolic_alias_cannot_hide_target_branch(self):
        fx = self.fixture()
        fx.git("symbolic-ref", "refs/heads/main", "refs/heads/release")
        with self.assertRaisesRegex(runner.fleet.Refused, "branch_is_checked_out"):
            self.promote(fx)
        self.assertEqual(self.value(fx), fx.old)

    def test_wrong_old_commit_and_non_fast_forward_are_refused(self):
        fx = self.fixture()
        with self.assertRaisesRegex(runner.fleet.Refused, "branch_changed"):
            self.promote(fx, old=fx.commit)
        other = fx.git("commit-tree", fx.tree, data=b"unrelated\n").decode().strip()
        fx.git("update-ref", "refs/heads/release", other)
        with self.assertRaisesRegex(runner.fleet.Refused, "not_fast_forward"):
            self.promote(fx, old=other)
        self.assertEqual(self.value(fx), other)

    def test_missing_and_symbolic_targets_are_never_created_or_adopted(self):
        fx = self.fixture()
        with self.assertRaisesRegex(runner.fleet.Refused, "branch_changed"):
            self.promote(fx, branch="missing")
        fx.git("symbolic-ref", "refs/heads/release", "refs/heads/main")
        with self.assertRaisesRegex(runner.fleet.Refused, "branch_changed"):
            self.promote(fx)
        self.assertEqual(fx.git("symbolic-ref", "refs/heads/release").strip(), b"refs/heads/main")

    def test_noop_does_not_touch_refs_or_reflogs(self):
        fx = self.fixture()
        fx.git("update-ref", "refs/heads/release", fx.commit)
        before = fx.contents(fx.repo)
        report = self.applied(fx, old=fx.commit)
        self.assertEqual(report["status"], "noop")
        self.assertFalse(report["promotion_started"])
        self.assertEqual(fx.contents(fx.repo), before)

    def test_sha256_ref_publication_and_read_only_check(self):
        fx = self.fixture(fmt="sha256")
        result = self.applied(fx)
        before = fx.contents(fx.root)
        checked = self.promote(fx, approval=result["plan_sha256"], check=True)
        self.assertEqual(checked["status"], "matched")
        self.assertEqual(checked["branch_status"], "matched")
        self.assertTrue(checked["read_only"])
        self.assertFalse(checked["promotion_provenance_verified"])
        self.assertEqual(fx.contents(fx.root), before)

    def test_check_distinguishes_unpromoted_missing_symbolic_and_different(self):
        fx = self.fixture()
        preview = self.promote(fx)
        checked = self.promote(fx, approval=preview["plan_sha256"], check=True)
        self.assertEqual((checked["status"], checked["branch_status"]), ("attention", "not_promoted"))
        (fx.repo / ".git/refs/heads/release").rename(fx.root / "retained-ref")
        self.assertEqual(self.promote(fx, approval=preview["plan_sha256"], check=True)["branch_status"], "missing")
        fx.git("symbolic-ref", "refs/heads/release", "refs/heads/main")
        self.assertEqual(self.promote(fx, approval=preview["plan_sha256"], check=True)["branch_status"], "symbolic")
        other = fx.git("commit-tree", fx.tree, "-p", fx.old, data=b"competing\n").decode().strip()
        fx.git("update-ref", "--no-deref", "refs/heads/release", other)
        self.assertEqual(self.promote(fx, approval=preview["plan_sha256"], check=True)["branch_status"], "different")

    def test_changed_target_or_run_evidence_invalidates_original_promotion_plan(self):
        fx = self.fixture()
        preview = self.promote(fx)
        fx.git("update-ref", "refs/heads/other", fx.old)
        with self.assertRaisesRegex(runner.fleet.Refused, "approval_mismatch"):
            self.promote(fx, branch="other", approval=preview["plan_sha256"])
        # Even harmless serialization changes alter the exact evidence digest.
        path = fx.output / "result.json"
        path.write_text(path.read_text() + "\n")
        with self.assertRaisesRegex(runner.fleet.Refused, "approval_mismatch"):
            self.promote(fx, approval=preview["plan_sha256"])

    def test_real_competing_direct_ref_writer_wins_without_being_overwritten(self):
        fx = self.fixture()
        preview = self.promote(fx)
        other = fx.git("commit-tree", fx.tree, "-p", fx.old, data=b"competitor\n").decode().strip()
        original = runner.promote_ref
        def compete(git, reference, old, candidate, guard):
            fx.git("update-ref", reference, other, old)
            return original(git, reference, old, candidate, guard)
        runner.promote_ref = compete
        try:
            with self.assertRaisesRegex(runner.fleet.Refused, "transaction_refused"):
                self.promote(fx, approval=preview["plan_sha256"])
        finally:
            runner.promote_ref = original
        self.assertEqual(self.value(fx), other)
        self.assertFalse((fx.repo / ".git/refs/heads/release.lock").exists())

    def test_refusal_survives_git_exiting_before_cleanup_writes_abort(self):
        # Deterministic form of the competing-writer race: git refuses the
        # transaction and exits, but is not yet reaped when promote_ref's cleanup
        # runs, so the "abort" write meets a closed pipe. The refusal must still
        # surface as promotion_transaction_refused, never as BrokenPipeError, and
        # the competitor's ref must survive.
        fx = self.fixture()
        preview = self.promote(fx)
        other = fx.git("commit-tree", fx.tree, "-p", fx.old, data=b"competitor\n").decode().strip()
        original_ref, original_popen = runner.promote_ref, runner.subprocess.Popen
        def compete(git, reference, old, candidate, guard):
            fx.git("update-ref", reference, other, old)
            return original_ref(git, reference, old, candidate, guard)
        def late_reaped_popen(argv, *args, **kwargs):
            process = original_popen(argv, *args, **kwargs)
            if "update-ref" in argv and "--stdin" in argv:
                real_poll, real_wait, waited = process.poll, process.wait, []
                def poll():
                    if waited:
                        return real_poll()
                    real_wait(timeout=30)  # git refuses and exits on its own...
                    return None            # ...but is reported as not yet reaped
                def wait(timeout=None):
                    waited.append(True)
                    return real_wait(timeout=timeout)
                process.poll, process.wait = poll, wait
            return process
        runner.promote_ref, runner.subprocess.Popen = compete, late_reaped_popen
        try:
            with self.assertRaisesRegex(runner.fleet.Refused, "transaction_refused"):
                self.promote(fx, approval=preview["plan_sha256"])
        finally:
            runner.promote_ref, runner.subprocess.Popen = original_ref, original_popen
        self.assertEqual(self.value(fx), other)
        self.assertFalse((fx.repo / ".git/refs/heads/release.lock").exists())

    def test_real_symbolic_ref_race_is_refused_after_git_has_prepared_lock(self):
        fx = self.fixture()
        preview = self.promote(fx)
        original = runner.promote_ref
        def compete(git, reference, old, candidate, guard):
            fx.git("symbolic-ref", reference, "refs/heads/main")
            return original(git, reference, old, candidate, guard)
        runner.promote_ref = compete
        try:
            with self.assertRaisesRegex(runner.fleet.Refused, "branch_changed_or_symbolic"):
                self.promote(fx, approval=preview["plan_sha256"])
        finally:
            runner.promote_ref = original
        self.assertEqual(fx.git("symbolic-ref", "refs/heads/release").strip(), b"refs/heads/main")
        self.assertEqual(fx.git("rev-parse", "HEAD").decode().strip(), fx.old)
        self.assertFalse((fx.repo / ".git/refs/heads/release.lock").exists())

    def test_late_worktree_checkout_aborts_prepared_transaction(self):
        fx = self.fixture()
        preview = self.promote(fx)
        original = runner.promote_ref
        def checkout(git, reference, old, candidate, guard):
            fx.git("worktree", "add", "--no-checkout", str(fx.root / "late"), "release")
            return original(git, reference, old, candidate, guard)
        runner.promote_ref = checkout
        try:
            with self.assertRaisesRegex(runner.fleet.Refused, "branch_is_checked_out"):
                self.promote(fx, approval=preview["plan_sha256"])
        finally:
            runner.promote_ref = original
        self.assertEqual(self.value(fx), fx.old)
        self.assertFalse((fx.repo / ".git/refs/heads/release.lock").exists())

    def test_evidence_change_after_prepare_aborts_without_promoting(self):
        fx = self.fixture()
        preview = self.promote(fx)
        original = runner.promote_ref
        def mutate(git, reference, old, candidate, guard):
            def changed_guard():
                (fx.output / "logs/unit.stdout").write_text("late tamper")
                guard()
            return original(git, reference, old, candidate, changed_guard)
        runner.promote_ref = mutate
        try:
            with self.assertRaisesRegex(runner.fleet.Refused, "evidence_changed"):
                self.promote(fx, approval=preview["plan_sha256"])
        finally:
            runner.promote_ref = original
        self.assertEqual(self.value(fx), fx.old)
        self.assertFalse((fx.repo / ".git/refs/heads/release.lock").exists())

    def test_sigkill_before_and_after_ref_commit_is_inspectable_without_retry(self):
        import time
        for after in (False, True):
            fx = self.fixture()
            preview = self.promote(fx)
            program = f'''import importlib.util, os, signal
spec = importlib.util.spec_from_file_location("r", {str(SCRIPT)!r})
r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
original = r.promote_ref
def crash(git, ref, old, candidate, guard):
    def before():
        guard()
        os.kill(os.getpid(), signal.SIGKILL)
    original(git, ref, old, candidate, guard if {after!r} else before)
    os.kill(os.getpid(), signal.SIGKILL)
r.promote_ref = crash
r.promote_candidate({str(fx.output)!r}, {str(fx.repo)!r}, {fx.test_result['plan_sha256']!r},
                    'release', {fx.old!r}, 30, {preview['plan_sha256']!r})
'''
            killed = subprocess.run([sys.executable, "-I", "-c", program], env=fx.env, capture_output=True, timeout=20)
            self.assertEqual(killed.returncode, -signal.SIGKILL, killed.stderr)
            end = time.monotonic() + 5
            lock = fx.repo / ".git/refs/heads/release.lock"
            while lock.exists() and time.monotonic() < end:
                time.sleep(0.02)
            before = fx.contents(fx.root)
            result = self.promote(fx, approval=preview["plan_sha256"], check=True)
            self.assertEqual(result["branch_status"], "matched" if after else "not_promoted")
            self.assertEqual(fx.contents(fx.root), before)

    def test_cli_preview_apply_and_check_preserve_literal_branch_and_exit_codes(self):
        fx = self.fixture()
        args = [sys.executable, "-I", str(SCRIPT), "--promote", str(fx.output), "--repository", str(fx.repo),
                "--expect-plan", fx.test_result["plan_sha256"], "--branch", "release", "--expect-old", fx.old]
        def run(*more):
            return subprocess.run(args + list(more), env=fx.env, capture_output=True, text=True, timeout=20)
        preview = run()
        self.assertEqual(preview.returncode, 0, preview.stdout + preview.stderr)
        approval = json.loads(preview.stdout)["plan_sha256"]
        self.assertEqual(run("--check", "--accept-plan", approval).returncode, 1)
        for flags in (("--run",), ("--apply",), ("--check",), ("--verify", str(fx.output)),
                      ("--apply", "--check", "--accept-plan", approval)):
            self.assertEqual(run(*flags).returncode, 2)
        applied = run("--apply", "--accept-plan", approval)
        self.assertEqual(applied.returncode, 0, applied.stdout + applied.stderr)
        self.assertEqual(json.loads(applied.stdout)["status"], "promoted")
        self.assertEqual(run("--check", "--accept-plan", approval).returncode, 0)

    def test_real_two_parent_integration_test_verify_promotion_pipeline(self):
        support_spec = importlib.util.spec_from_file_location("pipeline_fixture",
                        Path(__file__).with_name("test_swarm_fleet_integrate.py"))
        support = importlib.util.module_from_spec(support_spec)
        support_spec.loader.exec_module(support)
        program = ("import unittest\nfrom pathlib import Path\nclass T(unittest.TestCase):\n"
                   " def test_both_changes(self):\n"
                   "  self.assertEqual(Path('left').read_text()+Path('right').read_text(), 'leftright')\n"
                   "unittest.main()\n")
        fx = support.Fixture(files={"test.py": ("100644", program.encode())})
        for side in ("left", "right"):
            commit = fx.commit(side, [fx.base], {side: ("100644", side.encode())})
            fx.add_host(side, commit)
        fx.seal()
        integration = fx.preview()
        published = fx.preview(approval=integration["plan_sha256"])
        candidate = published["plan"]["result"]["candidate_commit"]
        self.assertEqual(len(fx.text(fx.repo, "show", "-s", "--format=%P", candidate).split()), 2)
        fx.git(fx.repo, "update-ref", "refs/heads/release", fx.base)
        output = fx.root / "qualification"
        specification = {"schema": runner.SPEC_SCHEMA, "environment": {}, "commands": [
            {"id": "unit", "argv": [base.PYTHON, "-B", "test.py"], "timeout_seconds": 10}]}
        preview = runner.execute(fx.repo, candidate, specification, output)
        tests = runner.execute(fx.repo, candidate, specification, output, approval=preview["plan_sha256"])
        self.assertEqual(tests["status"], "passed")
        evidence = runner.verify_test_run(output, fx.repo, preview["plan_sha256"])
        self.assertEqual(evidence["commit"], candidate)
        options = (output, fx.repo, preview["plan_sha256"], "release", fx.base)
        promotion = runner.promote_candidate(*options)
        result = runner.promote_candidate(*options, approval=promotion["plan_sha256"])
        self.assertEqual(result["status"], "promoted")
        self.assertEqual(fx.text(fx.repo, "rev-parse", "refs/heads/release"), candidate)
        self.assertEqual(fx.text(fx.repo, "rev-parse", "HEAD"), fx.base)
        self.assertEqual(runner.promote_candidate(*options, approval=promotion["plan_sha256"], check=True)["status"], "matched")


if __name__ == "__main__":
    if os.geteuid() == 0:
        os.setgroups([])
        os.setgid(65534)
        os.setuid(65534)
        os.execv(sys.executable, [sys.executable, "-B", __file__, *sys.argv[1:]])
    unittest.main()
