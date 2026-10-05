#!/usr/bin/env python3
"""Recovery exercises real durable state and process loss, with inert native peers."""
import fcntl
import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys
import tempfile
import time
import unittest

import test_swarm_fleet_launch as base

fleet, FixtureTransport, SCRIPT, host = base.fleet, base.FixtureTransport, base.SCRIPT, base.host


class RecoveryTests(unittest.TestCase):
    setUp = base.FleetTests.setUp
    run_fleet = base.FleetTests.run_fleet

    def lose_first_response(self):
        return self.run_fleet("launch", FixtureTransport(lambda h, m, r: (255, b"lost") if m == "launch" else r))

    def snapshot(self):
        return {p.name: p.read_bytes() for p in self.state.iterdir()}

    def test_receipt_only_reconciliation_never_launches_or_changes_files(self):
        self.run_fleet("launch")
        before = self.snapshot()
        peer = FixtureTransport()
        report, code = self.run_fleet("reconcile", peer)
        self.assertEqual((code, report["status"]), (0, "ready"))
        self.assertFalse(report["starts_agents"])
        self.assertEqual(peer.calls, [("worker-1", "reconcile"), ("worker-2", "reconcile")])
        self.assertEqual(before, self.snapshot())
        self.assertFalse(fleet.NEW_LAUNCH_ATTEMPTED)

    def test_read_only_recovery_of_lost_response_reports_partial_without_publishing(self):
        self.lose_first_response()
        before = self.snapshot()
        peer = FixtureTransport()
        report, code = self.run_fleet("reconcile", peer)
        self.assertEqual((code, report["status"]), (1, "partial"))
        self.assertEqual(report["hosts"][0]["status"], "ready")
        self.assertEqual(report["hosts"][1]["status"], "not_attempted")
        self.assertEqual(peer.calls, [("worker-1", "reconcile")])
        self.assertEqual(before, self.snapshot())

    def test_resume_recovers_lost_response_and_only_launches_untouched_host(self):
        self.lose_first_response()
        attempt = (self.state / "worker-1.attempt.json").read_bytes()
        peer = FixtureTransport()
        report, code = self.run_fleet("resume", peer)
        self.assertEqual((code, report["status"]), (0, "ready"))
        self.assertEqual(peer.calls, [("worker-1", "reconcile"), ("worker-2", "preview"), ("worker-2", "launch")])
        self.assertEqual((self.state / "worker-1.attempt.json").read_bytes(), attempt)
        self.assertTrue((self.state / "worker-1.result.json").exists())
        before = self.snapshot()
        again = FixtureTransport()
        report, code = self.run_fleet("resume", again)
        self.assertEqual(code, 0)
        self.assertFalse(report["starts_agents"])
        self.assertEqual(again.calls, [("worker-1", "reconcile"), ("worker-2", "reconcile")])
        self.assertEqual(self.snapshot(), before)

    def test_missing_remote_intent_is_unknown_not_permission_to_spawn_again(self):
        self.lose_first_response()
        before = self.snapshot()
        peer = FixtureTransport(lambda h, m, r: (2, fleet.encoded({"schema": fleet.NATIVE_SCHEMA, "status": "error"})))
        report, code = self.run_fleet("resume", peer)
        self.assertEqual((code, report["status"]), (1, "unconfirmed"))
        self.assertFalse(report["starts_agents"])
        self.assertEqual(peer.calls, [("worker-1", "reconcile")])
        self.assertEqual(before, self.snapshot())

    def test_original_target_change_or_adopted_session_blocks_continuation(self):
        for changed in ("pane", "adoption"):
            self.setUp()
            self.run_fleet("launch")
            before = self.snapshot()
            def mutate(h, m, r):
                if changed == "pane":
                    r["targets"][0]["pane"] = "%99"
                else:
                    r["original_launch_verified"] = False
                    r["recovery_provenance"] = {"schema": "acfs.swarm-launch-recovery.v1"}
                return r
            peer = FixtureTransport(mutate)
            report, code = self.run_fleet("resume", peer)
            self.assertEqual((code, report["status"]), (1, "unconfirmed"))
            self.assertTrue(all(m == "reconcile" for _, m in peer.calls))
            self.assertEqual(self.snapshot(), before)

    def test_later_existing_host_is_still_queried_when_first_is_unconfirmed(self):
        self.run_fleet("launch")
        peer = FixtureTransport(lambda h, m, r: (255, b"lost") if h["id"] == "worker-1" else r)
        report, code = self.run_fleet("reconcile", peer)
        self.assertEqual(code, 1)
        self.assertEqual(report["hosts"][1]["status"], "ready")
        self.assertEqual(peer.calls, [("worker-1", "reconcile"), ("worker-2", "reconcile")])

    def test_pending_host_readmission_failure_does_not_write_an_attempt(self):
        self.lose_first_response()
        peer = FixtureTransport(lambda h, m, r: (2, b"blocked") if m == "preview" else r)
        report, code = self.run_fleet("resume", peer)
        self.assertEqual((code, report["status"]), (1, "blocked"))
        self.assertTrue((self.state / "worker-1.result.json").exists())
        self.assertFalse((self.state / "worker-2.attempt.json").exists())
        self.assertNotIn(("worker-1", "launch"), peer.calls)
        self.assertNotIn(("worker-2", "launch"), peer.calls)

    def test_second_uncertain_launch_stays_query_only_on_next_resume(self):
        self.lose_first_response()
        second = FixtureTransport(lambda h, m, r: (255, b"lost") if m == "launch" else r)
        report, code = self.run_fleet("resume", second)
        self.assertEqual(code, 1)
        self.assertTrue((self.state / "worker-2.attempt.json").exists())
        third = FixtureTransport()
        report, code = self.run_fleet("resume", third)
        self.assertEqual(code, 0)
        self.assertEqual(third.calls, [("worker-1", "reconcile"), ("worker-2", "reconcile")])
        self.assertFalse(report["starts_agents"])

    def test_resume_requires_original_approval_before_connecting(self):
        self.lose_first_response()
        peer = FixtureTransport()
        with self.assertRaisesRegex(fleet.Refused, "approval_mismatch"):
            fleet.execute(self.plan, "resume", None, peer)
        self.assertEqual(peer.calls, [])

    def test_empty_durable_intent_can_resume_but_reconcile_does_not_contact_untouched_hosts(self):
        with fleet.new_state(self.plan):
            pass
        peer = FixtureTransport()
        report, code = self.run_fleet("reconcile", peer)
        self.assertEqual((code, report["status"]), (1, "partial"))
        self.assertEqual(peer.calls, [])
        report, code = self.run_fleet("resume", peer)
        self.assertEqual(code, 0)
        self.assertEqual(peer.calls, [("worker-1", "preview"), ("worker-2", "preview"),
                                     ("worker-1", "launch"), ("worker-2", "launch")])

    def test_unknown_or_partial_state_never_connects_or_adopts(self):
        for mutation in ("partial", "extra", "world_readable", "wrong_plan", "symlink", "result_without_attempt"):
            self.setUp()
            self.run_fleet("launch")
            if mutation == "partial":
                (self.state / "worker-1.result.json").write_bytes(b'{"schema":')
            elif mutation == "extra":
                (self.state / "foreign.json").write_bytes(b"{}")
            elif mutation == "world_readable":
                (self.state / "worker-1.result.json").chmod(0o644)
            elif mutation == "wrong_plan":
                data = json.loads((self.state / "intent.json").read_text())
                data["plan"]["spec"]["hosts"][0]["request"]["repo"] = "/other/project"
                (self.state / "intent.json").write_bytes(fleet.encoded(data))
            elif mutation == "symlink":
                original = self.state / "worker-1.result.json"
                moved = self.directory / "saved-result"
                original.rename(moved)
                original.symlink_to(moved)
            else:
                (self.state / "worker-1.attempt.json").rename(self.directory / "saved-attempt")
            peer = FixtureTransport()
            with self.subTest(mutation=mutation), self.assertRaises((fleet.Refused, OSError)):
                self.run_fleet("resume", peer)
            self.assertEqual(peer.calls, [])

    def test_deleting_an_earlier_record_cannot_make_it_pending_before_later_attempts(self):
        self.run_fleet("launch")
        for suffix in (".attempt.json", ".result.json"):
            (self.state / ("worker-1" + suffix)).rename(self.directory / ("retained" + suffix))
        peer = FixtureTransport()
        with self.assertRaisesRegex(fleet.Refused, "nonprefix_launch_history"):
            self.run_fleet("resume", peer)
        self.assertEqual(peer.calls, [])

    def test_changing_a_local_receipt_during_reconciliation_never_reenters_launch(self):
        self.lose_first_response()
        def move(h, m, r):
            (self.state / "worker-1.attempt.json").rename(self.directory / "retained-attempt")
            return r
        peer = FixtureTransport(move)
        with self.assertRaisesRegex(fleet.Refused, "state_changed"):
            self.run_fleet("resume", peer)
        self.assertEqual(peer.calls, [("worker-1", "reconcile")])
        self.assertFalse((self.state / "worker-2.attempt.json").exists())

    def test_replacing_state_directory_during_query_is_detected(self):
        self.lose_first_response()
        retained = self.directory / "retained-state"
        def replace(h, m, r):
            self.state.rename(retained)
            self.state.mkdir(mode=0o700)
            return r
        peer = FixtureTransport(replace)
        with self.assertRaisesRegex(fleet.Refused, "state_directory_changed"):
            self.run_fleet("resume", peer)
        self.assertTrue((retained / "worker-1.attempt.json").exists())
        self.assertEqual(peer.calls, [("worker-1", "reconcile")])

    def test_kernel_lock_excludes_concurrent_resume_and_read_only_reconciliation(self):
        self.run_fleet("launch")
        with fleet.directory_fd(self.state) as fd:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            for mode in ("resume", "reconcile"):
                peer = FixtureTransport()
                with self.assertRaisesRegex(fleet.Refused, "fleet_operation_in_progress"):
                    self.run_fleet(mode, peer)
                self.assertEqual(peer.calls, [])

    def test_duplicate_keys_or_boolean_numeric_request_substitutions_are_refused(self):
        selected = host()
        response = FixtureTransport(lambda h, m, r: {**r, "request": {**r["request"], "accept_warnings": 0}})
        self.assertEqual(fleet.remote_result(selected, "reconcile", response)["status"], "unconfirmed")
        self.lose_first_response()
        path = self.state / "intent.json"
        data = json.loads(path.read_text())
        data["plan"]["spec"]["hosts"][0]["request"]["accept_warnings"] = 0
        path.write_bytes(fleet.encoded(data))
        peer = FixtureTransport()
        with self.assertRaises(fleet.Refused):
            self.run_fleet("resume", peer)
        self.assertEqual(peer.calls, [])

    def test_new_launch_also_detects_receipt_changes_before_starting_later_hosts(self):
        def mutate(h, m, r):
            if m == "launch":
                (self.state / "intent.json").write_bytes(b'{}')
            return r
        peer = FixtureTransport(mutate)
        with self.assertRaisesRegex(fleet.Refused, "state_changed"):
            self.run_fleet("launch", peer)
        self.assertFalse((self.state / "worker-2.attempt.json").exists())
        self.assertNotIn(("worker-2", "launch"), peer.calls)

    def test_controller_sigkill_preserves_attempt_and_releases_lock_without_respawn(self):
        planfile = self.directory / "plan.json"
        planfile.write_bytes(fleet.encoded(self.plan))
        marker = self.directory / "reached-remote-launch"
        source = f'''
import importlib.util,json,time
from pathlib import Path
spec=importlib.util.spec_from_file_location('fleet',{str(SCRIPT)!r})
fleet=importlib.util.module_from_spec(spec); spec.loader.exec_module(fleet)
plan=json.loads(Path({str(planfile)!r}).read_text())
def peer(host,mode):
    if mode=='launch':
        Path({str(marker)!r}).write_text('reached')
        time.sleep(30)
    req=host['request']
    return 0,fleet.encoded({{'schema':fleet.NATIVE_SCHEMA,'request':req,'status':'preview','starts_agents':False,
      'work_dispatched':False,'authentication_verified':False,'agent_mail_registered':False,
      'review_sha256':fleet.native_hash(req),'admission':{{'status':'pass','recommendation':'launch','safe_agents':32,'recommended_agents':32}}}})
fleet.execute(plan,'launch',fleet.digest(fleet.encoded(plan)),peer)
'''
        child = subprocess.Popen([sys.executable, "-I", "-B", "-c", source], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 5
            while not marker.exists() and child.poll() is None and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertTrue(marker.exists())
            child.kill()
            child.wait(timeout=3)
            self.assertEqual(child.returncode, -signal.SIGKILL)
        finally:
            if child.poll() is None:
                child.kill()
            child.communicate(timeout=3)
        self.assertTrue((self.state / "worker-1.attempt.json").exists())
        self.assertFalse((self.state / "worker-1.result.json").exists())
        peer = FixtureTransport()
        report, code = self.run_fleet("resume", peer)
        self.assertEqual(code, 0)
        self.assertEqual(peer.calls, [("worker-1", "reconcile"), ("worker-2", "preview"), ("worker-2", "launch")])

    def test_cli_action_combinations_are_rejected_before_inputs_or_ssh(self):
        args = ["--spec", "unused", "--known-hosts", "unused", "--identity-file", "unused", "--state-dir", "unused"]
        for extra in (["--launch", "--resume"], ["--resume", "--reconcile"], ["--launch", "--reconcile"]):
            result = subprocess.run([sys.executable, "-I", "-B", str(SCRIPT), *args, *extra], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("not allowed", result.stderr)


class RemoteCommandTests(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="acfs-remote-command-test-"))
        self.home.chmod(0o755)
        lib = self.home / ".acfs" / "scripts" / "lib"
        lib.mkdir(parents=True, mode=0o755)
        self.script = lib / "swarm_launch.sh"
        self.script.write_text("#!/bin/bash\nexec " + shlex.quote(sys.executable) +
                               " -c 'import json,sys; print(json.dumps(sys.argv[1:]))' \"$@\"\n")
        self.script.chmod(0o755)
        self.identity = {"user": 65534, "group": 65534} if os.geteuid() == 0 else {}

    def invoke(self, command, identity=None):
        return subprocess.run(["/bin/sh", "-c", command], env={"HOME": str(self.home), "PATH": "/usr/bin:/bin"},
                              capture_output=True, text=True, timeout=5, **(self.identity if identity is None else identity))

    def test_real_unprivileged_remote_shell_preserves_exact_literal_arguments(self):
        selected = host()
        marker = self.home / "must-not-execute"
        selected["request"]["repo"] = "/data/quoted ' $(touch " + str(marker) + ")"
        command = fleet.ssh_argv(selected, "launch", 7, 8)[-1]
        result = self.invoke(command)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), fleet.native_argv(selected["request"], "launch"))
        self.assertFalse(marker.exists())
        result = self.invoke(fleet.ssh_argv(selected, "reconcile", 7, 8)[-1])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ["--reconcile", "--receipt", selected["request"]["receipt"]])

    def test_missing_or_symlinked_remote_launcher_never_falls_back(self):
        command = fleet.ssh_argv(host(), "launch", 7, 8)[-1]
        saved = self.script.with_suffix(".saved")
        self.script.rename(saved)
        result = self.invoke(command)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.script.symlink_to(saved)
        result = self.invoke(command)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    @unittest.skipUnless(os.geteuid() == 0, "root refusal exercised only when the test runner is root")
    def test_remote_root_is_refused_before_the_installed_launcher_executes(self):
        result = self.invoke(fleet.ssh_argv(host(), "launch", 7, 8)[-1], {})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
