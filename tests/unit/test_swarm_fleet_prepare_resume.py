#!/usr/bin/env python3
"""Recover actual preparation journals and packet bundles without regeneration."""
import copy
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import unittest

import test_swarm_fleet_prepare_dependencies as base
prepare, fleet = base.prepare, base.fleet


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.f = base.Fixture()
        self.plan = self.f.plan()
        self.sha = fleet.digest(fleet.encoded(self.plan))

    def partial(self, failed=1, complete=True):
        def invoke(entry, mode):
            if mode == "prepare" and entry["host"]["id"] == f"worker-{failed}":
                if complete: self.f.invoke(entry, mode)
                else: self.f.calls.append((entry["host"]["id"], mode))
                return 1, b"response lost"
            return self.f.invoke(entry, mode)
        report, code = prepare.prepare(self.plan, self.sha, invoke, lambda: None)
        self.assertEqual(code, 1)
        self.assertEqual(report["status"], "unconfirmed")
        self.f.calls.clear()

    def run_recovery(self, mode="resume", invoke=None, approval=None, plan=None):
        with prepare.launch_context(self.f.launch_dir, b"known hosts", b"private identity") as (_, _, _, guard):
            return prepare.recover_preparation(plan or self.plan, mode, approval if approval is not None else self.sha,
                                               invoke or self.f.invoke, guard)

    def local_snapshot(self):
        return {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.f.state.iterdir()}

    def test_reconcile_partial_is_read_only_and_never_touches_pending_hosts(self):
        self.partial()
        before = self.local_snapshot()
        report, code = self.run_recovery("reconcile")
        self.assertEqual((report["status"], code), ("partial", 1))
        self.assertEqual(self.f.calls, [("worker-0", "inspect"), ("worker-1", "inspect")])
        self.assertFalse(report["mapping_published"])
        self.assertEqual(before, self.local_snapshot())

    def test_resume_inspects_attempts_and_prepares_only_untouched_hosts(self):
        self.partial()
        original = {i: (Path(self.plan["hosts"][i]["output"]) / "complete.json").read_bytes() for i in (0, 1)}
        report, code = self.run_recovery()
        self.assertEqual((report["status"], code), ("prepared", 0))
        self.assertEqual(self.f.calls, [("worker-0", "inspect"), ("worker-1", "inspect"),
                                      ("worker-2", "check"), ("worker-2", "prepare")])
        self.assertEqual(json.loads((self.f.state / "batches.json").read_text()), prepare.preparation_mapping(self.plan))
        self.assertTrue((self.f.state / "worker-1.result.json").exists())
        for i, raw in original.items():
            self.assertEqual((Path(self.plan["hosts"][i]["output"]) / "complete.json").read_bytes(), raw)
        self.assertFalse(report["sends_prompt"])
        self.assertFalse(report["starts_agents"])

    def test_unconfirmed_remote_never_falls_back_to_prepare_even_when_absent(self):
        self.partial(complete=False)
        before = self.local_snapshot()
        report, code = self.run_recovery()
        self.assertEqual((report["status"], code), ("unconfirmed", 1))
        self.assertEqual(self.f.calls, [("worker-0", "inspect"), ("worker-1", "inspect")])
        self.assertEqual(before, self.local_snapshot())
        self.assertFalse(Path(self.plan["hosts"][1]["output"]).exists())

    def test_changed_packet_prevents_resume_and_does_not_hide_other_attempts(self):
        self.partial()
        packet = Path(self.plan["hosts"][0]["output"]) / "bundle/packet-02.md"
        packet.write_text("edited packet")
        before = self.local_snapshot()
        report, code = self.run_recovery()
        self.assertEqual(code, 1)
        self.assertEqual(report["hosts"][0]["status"], "unconfirmed")
        self.assertEqual(report["hosts"][1]["status"], "prepared")
        self.assertEqual(before, self.local_snapshot())
        self.assertEqual(self.f.calls, [("worker-0", "inspect"), ("worker-1", "inspect")])

    def test_old_local_success_cannot_mask_missing_remote_completion(self):
        prepare.prepare(self.plan, self.sha, self.f.invoke, lambda: None)
        root = Path(self.plan["hosts"][0]["output"])
        (root / "complete.json").rename(root / "complete.retained")
        self.f.calls.clear()
        report, code = self.run_recovery("reconcile")
        self.assertEqual(code, 1)
        self.assertEqual(report["status"], "unconfirmed")
        self.assertEqual(len(self.f.calls), 3)
        self.assertTrue(all(mode == "inspect" for _, mode in self.f.calls))

    def test_complete_resume_is_inspection_only_without_local_writes(self):
        prepare.prepare(self.plan, self.sha, self.f.invoke, lambda: None)
        self.f.calls.clear()
        before = self.local_snapshot()
        report, code = self.run_recovery()
        self.assertEqual(code, 0)
        self.assertFalse(report["preparation_attempted"])
        self.assertEqual(before, self.local_snapshot())
        self.assertEqual(self.f.calls, [(f"worker-{i}", "inspect") for i in range(3)])

    def test_missing_final_mapping_is_published_only_by_explicit_resume(self):
        prepare.prepare(self.plan, self.sha, self.f.invoke, lambda: None)
        (self.f.state / "batches.json").rename(self.f.root / "batches.retained.json")
        report, code = self.run_recovery("reconcile")
        self.assertEqual(code, 0)
        self.assertFalse(report["mapping_published"])
        self.assertFalse((self.f.state / "batches.json").exists())
        self.f.calls.clear()
        report, code = self.run_recovery()
        self.assertEqual(code, 0)
        self.assertTrue(report["mapping_published"])
        self.assertTrue(all(mode == "inspect" for _, mode in self.f.calls))

    def test_fresh_barrier_checks_every_pending_host_before_new_preparation(self):
        self.partial(failed=0)
        def invoke(entry, mode):
            if entry["host"]["id"] == "worker-2" and mode == "check":
                self.f.calls.append(("worker-2", mode))
                return 1, b"not ready"
            return self.f.invoke(entry, mode)
        report, code = self.run_recovery(invoke=invoke)
        self.assertEqual((report["status"], code), ("blocked", 1))
        self.assertEqual(self.f.calls, [("worker-0", "inspect"), ("worker-1", "check"), ("worker-2", "check")])
        self.assertFalse((self.f.state / "worker-1.attempt.json").exists())

    def test_new_uncertain_attempt_is_inspected_on_next_resume(self):
        self.partial(failed=0)
        def invoke(entry, mode):
            result = self.f.invoke(entry, mode)
            if entry["host"]["id"] == "worker-1" and mode == "prepare": return 1, b"reply lost"
            return result
        report, code = self.run_recovery(invoke=invoke)
        self.assertEqual(code, 1)
        self.assertFalse((self.f.state / "worker-2.attempt.json").exists())
        self.f.calls.clear()
        report, code = self.run_recovery()
        self.assertEqual(code, 0)
        self.assertNotIn(("worker-1", "prepare"), self.f.calls)
        self.assertIn(("worker-1", "inspect"), self.f.calls)

    def test_wrong_approval_and_changed_plan_refused_before_inspection(self):
        self.partial()
        with self.assertRaisesRegex(fleet.Refused, "approval_mismatch"):
            self.run_recovery(approval="0" * 64)
        changed = copy.deepcopy(self.plan)
        changed["timeout_seconds"] += 1
        with self.assertRaisesRegex(fleet.Refused, "preparation_intent_mismatch"):
            self.run_recovery("reconcile", plan=changed)
        self.assertEqual(self.f.calls, [])

    def test_nonprefix_history_result_without_attempt_and_premature_mapping_refused(self):
        for corruption in ("nonprefix", "result_without_attempt", "premature_mapping"):
            self.setUp()
            self.partial(failed=0)
            if corruption == "nonprefix":
                self.f.private(self.f.state / "worker-2.attempt.json", prepare.attempt(self.plan, self.plan["hosts"][2]))
            elif corruption == "result_without_attempt":
                self.f.private(self.f.state / "worker-2.result.json", {})
            else:
                self.f.private(self.f.state / "batches.json", prepare.preparation_mapping(self.plan))
            with self.subTest(corruption=corruption), self.assertRaises(fleet.Refused):
                self.run_recovery()
            self.assertEqual(self.f.calls, [])

    def test_truncated_journal_unsafe_permissions_and_extra_members_refused(self):
        for corruption in ("truncated", "permissions", "extra"):
            self.setUp()
            self.partial()
            if corruption == "truncated": (self.f.state / "worker-1.attempt.json").write_text('{"schema":')
            elif corruption == "permissions": (self.f.state / "worker-1.attempt.json").chmod(0o644)
            else: (self.f.state / "unexpected").write_text("extra")
            with self.subTest(corruption=corruption), self.assertRaises(fleet.Refused): self.run_recovery()
            self.assertEqual(self.f.calls, [])

    def test_receipt_moved_during_inspection_cannot_trigger_repreparation(self):
        self.partial()
        def invoke(entry, mode):
            result = self.f.invoke(entry, mode)
            (self.f.state / "worker-1.attempt.json").rename(self.f.state / "attempt.retained")
            return result
        with self.assertRaises(fleet.Refused): self.run_recovery(invoke=invoke)
        self.assertEqual(self.f.calls, [("worker-0", "inspect")])

    def test_source_journal_change_stops_recovery(self):
        self.partial()
        def invoke(entry, mode):
            result = self.f.invoke(entry, mode)
            (self.f.launch_dir / "unexpected").write_text("extra")
            return result
        with self.assertRaises(fleet.Refused): self.run_recovery(invoke=invoke)
        self.assertEqual(self.f.calls, [("worker-0", "inspect")])

    def test_preparation_directory_lock_excludes_another_controller(self):
        self.partial()
        with fleet.directory_fd(self.f.state, private=True) as fd:
            prepare.lock(fd)
            with self.assertRaisesRegex(fleet.Refused, "fleet_operation_in_progress"):
                self.run_recovery()
        self.assertEqual(self.f.calls, [])

    def test_remote_valid_but_different_result_cannot_replace_local_evidence(self):
        self.partial()
        def invoke(entry, mode):
            code, raw = self.f.invoke(entry, mode)
            result = fleet.decode(raw)
            if entry["host"]["id"] == "worker-0": result["files"]["packet-02.md"]["sha256"] = "f" * 64
            return code, fleet.encoded(result)
        before = self.local_snapshot()
        report, code = self.run_recovery(invoke=invoke)
        self.assertEqual(code, 1)
        self.assertEqual(report["hosts"][0]["status"], "unconfirmed")
        self.assertEqual(before, self.local_snapshot())

    def test_sigkill_after_remote_completion_recovers_without_regeneration(self):
        plan_file = self.f.root / "plan.json"
        self.f.private(plan_file, self.plan)
        child = r'''
import json, os, signal, sys
from test_swarm_fleet_prepare_dependencies import prepare, fleet, Fixture
plan=json.load(open(sys.argv[1]))
f=Fixture.__new__(Fixture);f.calls=[];f.peer={'fleet':fleet}
exec(compile(prepare.PEER_CODE,'<fixed-peer>','exec'),f.peer)
def invoke(entry,mode):
    result=f.invoke(entry,mode)
    if mode=='prepare' and entry['host']['id']=='worker-1': os.kill(os.getpid(),signal.SIGKILL)
    return result
with prepare.launch_context(plan['launch_state'],b'known hosts',b'private identity') as (_,_,_,guard):
    prepare.prepare(plan,fleet.digest(fleet.encoded(plan)),invoke,guard)
'''
        result = subprocess.run([sys.executable, "-B", "-c", child, str(plan_file)],
            cwd=Path(__file__).parent, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, -signal.SIGKILL, result.stderr)
        self.assertTrue((self.f.state / "worker-1.attempt.json").exists())
        self.assertFalse((self.f.state / "worker-1.result.json").exists())
        report, code = self.run_recovery()
        self.assertEqual(code, 0)
        self.assertEqual(self.f.calls, [("worker-0", "inspect"), ("worker-1", "inspect"),
                                      ("worker-2", "check"), ("worker-2", "prepare")])

    def test_actual_unprivileged_peer_inspects_after_agents_are_gone(self):
        entry = self.plan["hosts"][0]
        expected = self.f.bundle(entry)
        self.f.root.chmod(0o755)
        uid = 65534 if os.geteuid() == 0 else os.geteuid()
        if os.geteuid() == 0:
            for parent, dirs, files in os.walk(entry["output"]):
                os.chown(parent, uid, uid)
                for name in files: os.chown(Path(parent) / name, uid, uid)
        # No native launcher, tmux or live agent exists here. Inspect cannot
        # silently fall back to one: this child sees only a completed bundle.
        result = subprocess.run([sys.executable, "-I", "-c", prepare.remote_program()],
            input=fleet.encoded({"mode": "inspect", "entry": entry, "timeout_seconds": 5}),
            env={"PATH": "/usr/bin:/bin"}, capture_output=True, timeout=10,
            **({"user": uid, "group": uid} if os.geteuid() == 0 else {}))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(fleet.decode(result.stdout), expected)
        self.assertNotIn(b"private fixture task", result.stdout)

    def test_cli_recovery_flags_reject_ambiguous_or_unapproved_operations(self):
        self.partial()
        for extra in (("--resume",), ("--prepare", "--reconcile"),
                      ("--reconcile", "--accept-plan", self.sha), ("--resume", "--accept-plan", "0" * 64)):
            result = subprocess.run(self.f.cli_args() + list(extra), capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 2, result.stdout)
            self.assertNotIn("private fixture task", result.stdout)

    def test_inspection_failure_never_publishes_recovered_results(self):
        self.partial()
        def invoke(entry, mode):
            if entry["host"]["id"] == "worker-0":
                self.f.calls.append(("worker-0", mode))
                raise OSError("private diagnostic")
            return self.f.invoke(entry, mode)
        report, code = self.run_recovery(invoke=invoke)
        self.assertEqual(code, 1)
        self.assertFalse((self.f.state / "worker-1.result.json").exists())
        self.assertNotIn("private diagnostic", json.dumps(report))


if __name__ == "__main__": unittest.main()
