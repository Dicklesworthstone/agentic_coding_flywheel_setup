#!/usr/bin/env python3
"""Crash/recovery uses real journals and child processes, not a live fleet."""
import copy
import fcntl
import json
import os
from pathlib import Path
import select
import shlex
import signal
import subprocess
import sys
import unittest

import test_swarm_fleet_dispatch as fixtures

Peer, dispatch, fleet = fixtures.Peer, fixtures.dispatch, fixtures.fleet


class ReceiptPeer:
    def __init__(self, state):
        self.base = Peer(state)
        self.calls = self.base.calls
        self.mutate_query = None

    def __call__(self, entry, mode):
        if mode not in ("read-receipt", "query-receipt"):
            return self.base(entry, mode)
        ident = entry["host"]["id"]
        self.calls.append((ident, mode))
        delivery = entry["delivery"]
        original = self.base.intents.get(ident)
        if original is None:
            return 2, b"private missing receipt diagnostics"
        actual = next(d for d in original["deliveries"] if d["slot"] == delivery["slot"])
        request, target = actual["request"], str(actual["slot"])
        if mode == "read-receipt":
            value = {"schema": "acfs.packet-delivery.v1", "request": copy.deepcopy(request), "target": target}
        else:
            value = {"success": True, "session": request["session"], "operation": {
                "operation_id": request["operation_id"], "payload_sha256": request["payload_sha256"],
                "payload_bytes": request["payload_bytes"], "status": "completed",
                "admissions": [{"target": target, "state": "submitted"}]},
                "outcome": {"success": True, "targets": [target], "successful": [target], "failed": []}}
        if self.mutate_query:
            replacement = self.mutate_query(entry, mode, value)
            if replacement is not None:
                return replacement
        return 0, fleet.encoded(value)


class RecoveryTests(unittest.TestCase):
    setUp = fixtures.DispatchTests.setUp
    run_dispatch = fixtures.DispatchTests.run_dispatch
    approved = fixtures.DispatchTests.approved

    def begin(self, partial=True):
        self.peer = ReceiptPeer(self.state)
        approval = self.approved()
        if partial:
            def lost(_entry, mode, _value):
                if mode == "send":
                    raise fleet.Refused("ssh_timeout")
            self.peer.base.mutate = lost
        result, code = self.run_dispatch("send", approval)
        self.assertEqual(code, 1 if partial else 0, result)
        self.peer.base.mutate = None
        self.peer.calls.clear()
        return approval

    def state_bytes(self):
        return {p.name: p.read_bytes() for p in self.state.iterdir()}

    def test_reconcile_queries_attempted_host_only_and_writes_nothing(self):
        self.begin()
        before = self.state_bytes()
        report, code = self.run_dispatch("reconcile")
        self.assertEqual(code, 1)
        self.assertEqual(report["status"], "partial")
        self.assertFalse(report["send_attempted"])
        self.assertEqual([h["status"] for h in report["hosts"]], ["submitted", "not_attempted"])
        self.assertEqual(self.peer.calls, [("worker-0", m) for _ in range(2) for m in ("read-receipt", "query-receipt")])
        self.assertEqual(before, self.state_bytes())

    def test_resume_confirms_lost_response_and_sends_only_untouched_host(self):
        approval = self.begin()
        old_intent = (self.state / "worker-0.attempt.json").read_bytes()
        report, code = self.run_dispatch("resume", approval)
        self.assertEqual(code, 0, report)
        self.assertEqual(report["status"], "submitted")
        self.assertEqual([m for h, m in self.peer.calls if h == "worker-0"], ["read-receipt", "query-receipt"] * 2)
        self.assertEqual([m for h, m in self.peer.calls if h == "worker-1"], ["launch-status", "preview", "send"])
        self.assertTrue((self.state / "worker-0.result.json").exists())
        self.assertEqual(old_intent, (self.state / "worker-0.attempt.json").read_bytes())
        self.peer.calls.clear()
        before = self.state_bytes()
        report, code = self.run_dispatch("resume", approval)
        self.assertEqual(code, 0, report)
        self.assertFalse(report["send_attempted"])
        self.assertTrue(all(m in ("read-receipt", "query-receipt") for _, m in self.peer.calls))
        self.assertEqual(before, self.state_bytes())

    def test_receipt_recovery_works_without_live_agents_or_packet_files(self):
        self.begin(False)
        def no_native(_entry, mode, _value):
            raise AssertionError("A historical submission must not run a live check or dispatch: " + mode)
        self.peer.base.mutate = no_native
        report, code = self.run_dispatch("reconcile")
        self.assertEqual(code, 0, report)
        self.assertEqual(report["status"], "submitted")

    def test_missing_remote_receipt_never_authorizes_resend(self):
        approval = self.begin()
        self.peer.base.intents.clear()
        before = self.state_bytes()
        report, code = self.run_dispatch("resume", approval)
        self.assertEqual(code, 1)
        self.assertEqual(report["status"], "unconfirmed")
        self.assertTrue(all(m == "read-receipt" for _, m in self.peer.calls))
        self.assertEqual(before, self.state_bytes())
        self.assertNotIn("private missing", json.dumps(report))

    def test_missing_one_delivery_blocks_rest_of_host_and_fleet_continuation(self):
        approval = self.begin()
        def missing(entry, mode, _value):
            if entry["delivery"]["slot"] == 2 and mode == "read-receipt":
                return 2, b""
        self.peer.mutate_query = missing
        report, code = self.run_dispatch("resume", approval)
        self.assertEqual(code, 1)
        self.assertEqual([d["status"] for d in report["hosts"][0]["deliveries"]], ["submitted", "unconfirmed"])
        self.assertTrue(all(h == "worker-0" and m != "send" for h, m in self.peer.calls))
        self.assertFalse((self.state / "worker-0.result.json").exists())

    def test_ntm_proof_rejects_wrong_digest_target_size_operation_and_incomplete_admission(self):
        approval = self.begin()
        mutations = [lambda v: v["operation"].update(payload_sha256="0" * 64),
                     lambda v: v["operation"].update(payload_bytes=True),
                     lambda v: v["operation"].update(operation_id="wrong"),
                     lambda v: v["operation"].update(status="pending"),
                     lambda v: v["operation"].update(admissions=[]),
                     lambda v: v["outcome"].update(targets=["999"]),
                     lambda v: v["outcome"].update(successful=[]),
                     lambda v: v["outcome"].update(failed=["1"]),
                     lambda v: v.update(session="another-session"), lambda v: v.update(success="true")]
        for mutation in mutations:
            def bad(_entry, mode, value):
                if mode == "query-receipt":
                    mutation(value)
            self.peer.mutate_query = bad
            with self.subTest(mutation=mutation):
                self.assertEqual(self.run_dispatch("resume", approval)[1], 1)
        self.assertFalse((self.state / "worker-0.result.json").exists())
        self.assertTrue(all(m in ("read-receipt", "query-receipt") for _, m in self.peer.calls))

    def test_native_receipt_mismatch_prevents_ntm_query(self):
        self.begin()
        def bad(_entry, mode, value):
            if mode == "read-receipt":
                value["request"]["pane"] = "%999"
        self.peer.mutate_query = bad
        self.assertEqual(self.run_dispatch("reconcile")[1], 1)
        self.assertTrue(all(m == "read-receipt" for _, m in self.peer.calls))

    def test_duplicate_json_keys_and_raw_diagnostics_never_become_success(self):
        self.begin()
        self.peer.mutate_query = lambda *_: (0, b'{"secret":"sk-private-test","secret":"other"}')
        report, code = self.run_dispatch("reconcile")
        self.assertEqual(code, 1)
        self.assertNotIn("sk-private", json.dumps(report))

    def test_wrong_resume_approval_fails_before_receipt_queries(self):
        self.begin()
        with self.assertRaisesRegex(fleet.Refused, "approval_mismatch"):
            self.run_dispatch("resume", "0" * 64)
        self.assertEqual(self.peer.calls, [])

    def test_changed_selection_cannot_retarget_recovery(self):
        approval = self.begin()
        self.batches["hosts"][0]["batch"] = "/different/batch.json"
        with self.assertRaisesRegex(fleet.Refused, "dispatch_host_changed"):
            self.run_dispatch("resume", approval)
        self.assertEqual(self.peer.calls, [])

    def test_changed_pending_packet_blocks_resume_without_sending(self):
        approval = self.begin()
        def changed(_entry, mode, value):
            if mode == "preview":
                value["deliveries"][0]["request"]["packet_sha256"] = "c" * 64
        self.peer.base.mutate = changed
        report, code = self.run_dispatch("resume", approval)
        self.assertEqual(code, 1)
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["hosts"][1]["code"], "pending_batch_changed")
        self.assertNotIn(("worker-1", "send"), self.peer.calls)
        self.assertFalse((self.state / "worker-1.attempt.json").exists())

    def test_completed_local_result_is_not_substitute_for_matching_remote_proof(self):
        self.begin(False)
        self.peer.base.intents.clear()
        report, code = self.run_dispatch("reconcile")
        self.assertEqual(code, 1)
        self.assertEqual([h["status"] for h in report["hosts"]], ["unconfirmed", "unconfirmed"])
        self.assertEqual(len(self.peer.calls), 4)

    def test_invalid_nonprefix_journal_is_refused_before_ssh(self):
        self.begin()
        intent = json.loads((self.state / "intent.json").read_bytes())
        plan = intent["plan"]
        with fleet.directory_fd(self.state, private=True) as fd:
            fleet.publish(fd, "worker-1.attempt.json", dispatch.attempted(plan, plan["hosts"][1]))
        with self.assertRaisesRegex(fleet.Refused, "nonprefix_dispatch_history"):
            self.run_dispatch("reconcile")
        self.assertEqual(self.peer.calls, [])

    def test_unexpected_symlinked_or_truncated_state_is_not_adopted(self):
        self.begin()
        (self.state / "unexpected").symlink_to(self.root / "does-not-exist")
        with self.assertRaises(fleet.Refused):
            self.run_dispatch("reconcile")
        self.assertEqual(self.peer.calls, [])
        (self.state / "unexpected").rename(self.root / "retained-link")
        (self.state / "worker-0.attempt.json").write_bytes(b'{"schema":')
        with self.assertRaisesRegex(fleet.Refused, "invalid_json"):
            self.run_dispatch("reconcile")
        self.assertEqual(self.peer.calls, [])

    def test_local_receipt_moved_during_query_cannot_trigger_a_send(self):
        approval = self.begin()
        moved = False
        def change(_entry, mode, _value):
            nonlocal moved
            if mode == "read-receipt" and not moved:
                (self.state / "worker-0.attempt.json").rename(self.root / "preserved-attempt.json")
                moved = True
        self.peer.mutate_query = change
        with self.assertRaisesRegex(fleet.Refused, "state_changed"):
            self.run_dispatch("resume", approval)
        self.assertTrue(all(m == "read-receipt" for _, m in self.peer.calls))

    def test_recovery_holds_exclusive_dispatch_directory_lock(self):
        self.begin()
        def locked(_entry, _mode, _value):
            with fleet.directory_fd(self.state, private=True) as fd:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        self.peer.mutate_query = locked
        self.assertEqual(self.run_dispatch("reconcile")[1], 1)

    def test_actual_sigkill_after_submission_is_recovered_without_replaying_batch(self):
        self.peer = ReceiptPeer(self.state)
        approval = self.approved()
        ready_read, ready_write = os.pipe()
        evidence = self.root / "simulated-remote-submission.json"
        inputs = self.root / "crash-inputs.json"
        inputs.write_bytes(fleet.encoded({"launch": str(self.launch_dir), "state": str(self.state),
            "batches": self.batches, "known": self.known.decode(), "identity": self.identity.decode(),
            "approval": approval, "evidence": str(evidence)}))
        child_code = '''import json, os, sys, time
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from test_swarm_fleet_dispatch_recovery import ReceiptPeer, dispatch, fleet
args = json.loads(Path(sys.argv[2]).read_bytes())
peer = ReceiptPeer(Path(args['state']))
def pause(entry, mode, value):
    if mode == 'send':
        Path(args['evidence']).write_bytes(fleet.encoded(value))
        os.write(int(sys.argv[3]), b'ready')
        while True:
            time.sleep(10)
peer.base.mutate = pause
dispatch.execute(args['launch'], args['batches'], args['known'].encode(), args['identity'].encode(),
                 args['state'], 360, 'send', args['approval'], peer)
sys.exit(99)
'''
        child = subprocess.Popen([sys.executable, "-I", "-c", child_code, str(Path(__file__).parent),
                                  str(inputs), str(ready_write)], pass_fds=(ready_write,),
                                 stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        os.close(ready_write)
        try:
            self.assertTrue(select.select([ready_read], [], [], 10)[0], "child never reached durable attempted send")
            self.assertEqual(os.read(ready_read, 5), b"ready")
        finally:
            child.kill()
            _, stderr = child.communicate(timeout=5)
            os.close(ready_read)
        self.assertEqual(child.returncode, -signal.SIGKILL, stderr)
        self.assertTrue((self.state / "worker-0.attempt.json").exists())
        self.assertFalse((self.state / "worker-0.result.json").exists())
        self.peer.base.intents["worker-0"] = json.loads(evidence.read_bytes())
        self.peer.calls.clear()
        report, code = self.run_dispatch("resume", approval)
        self.assertEqual(code, 0, report)
        self.assertNotIn(("worker-0", "send"), self.peer.calls)
        self.assertEqual(self.peer.calls.count(("worker-1", "send")), 1)

    def remote_fixture(self):
        self.root.chmod(0o755)
        root = self.root / "remote"
        root.mkdir(mode=0o700)
        uid = 65534 if os.geteuid() == 0 else os.geteuid()
        identity = {"user": uid, "group": 65534} if os.geteuid() == 0 else {}
        if identity:
            os.chown(root, uid, 65534)
        path = root / "a 'quote'; $(touch BAD).receipt"
        path.write_bytes(b'{"schema":"fixture","value":"inert private evidence"}')
        path.chmod(0o600)
        if identity:
            os.chown(path, uid, 65534)
        return root, path, identity

    def test_fixed_remote_reader_runs_as_unprivileged_user_with_literal_path(self):
        root, path, identity = self.remote_fixture()
        command = dispatch.remote_command({"delivery": {"receipt": str(path)}}, "read-receipt")
        # Use the interpreter visible in this environment through a private PATH
        # shim named python3; no production command/identity override is added.
        bin_dir = root / "bin"
        bin_dir.mkdir(mode=0o755)
        (bin_dir / "python3").symlink_to(sys.executable)
        result = subprocess.run(["/bin/bash", "--noprofile", "--norc", "-p", "-c", command],
                                env={"PATH": f"{bin_dir}:/usr/bin:/bin"}, capture_output=True, timeout=5, **identity)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, path.read_bytes())
        self.assertFalse((Path.cwd() / "BAD").exists())
        self.assertEqual(set(root.iterdir()), {path, bin_dir})

    def test_remote_reader_refuses_links_fifos_permissions_and_oversized_files(self):
        root, path, identity = self.remote_fixture()
        paths = []
        link = root / "link"; link.symlink_to(path); paths.append(link)
        fifo = root / "fifo"; os.mkfifo(fifo, 0o600); paths.append(fifo)
        public = root / "public"; public.write_bytes(b"private"); public.chmod(0o644); paths.append(public)
        large = root / "large"; large.write_bytes(b"x" * (fleet.LIMIT + 1)); large.chmod(0o600); paths.append(large)
        hard = root / "hardlink"; os.link(path, hard); paths.extend([path, hard])
        alias = root / "alias"; alias.symlink_to(root); paths.append(alias / public.name)
        if identity:
            for item in (fifo, public, large):
                os.chown(item, identity["user"], identity["group"])
        for candidate in paths:
            with self.subTest(path=candidate):
                result = subprocess.run([sys.executable, "-I", "-c", dispatch.READ_RECEIPT, str(candidate)],
                                        capture_output=True, timeout=5, **identity)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertEqual(result.stdout, b"")
        self.assertEqual(public.read_bytes(), b"private")

    def test_query_transport_cannot_accept_send_commands_or_inject_operation(self):
        entry = {"delivery": {"request": {"operation_id": "op.review-1"}}}
        command = dispatch.remote_command(entry, "query-receipt")
        self.assertIn("--robot-send-receipt=op.review-1", command)
        self.assertNotIn("--robot-send=", command)
        self.assertNotIn("--send", command)
        self.assertNotIn("--launch", command)
        entry["delivery"]["request"]["operation_id"] = "op; touch BAD"
        with self.assertRaises(fleet.Refused):
            dispatch.remote_command(entry, "query-receipt")

    def test_real_unprivileged_shell_transports_exact_native_and_query_arguments(self):
        root, _, identity = self.remote_fixture()
        native = root / ".acfs/scripts/lib/swarm_launch.sh"
        native.parent.mkdir(parents=True)
        body = ("#!/bin/bash\nexec " + shlex.quote(sys.executable) + " -I -c "
                + shlex.quote("import json,sys;print(json.dumps(sys.argv[1:]))") + ' "$@"\n')
        native.write_text(body)
        native.chmod(0o755)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        ntm = bin_dir / "ntm"
        ntm.write_text(body)
        ntm.chmod(0o755)
        entry = {"host": self.launch["spec"]["hosts"][0],
                 "batch": str(root / "batch 'quoted' $(touch BAD).json"), "review_sha256": "f" * 64,
                 "delivery": {"request": {"operation_id": "exact-op.1"}}}
        expected = {
            "launch-status": ["--reconcile", "--receipt", entry["host"]["request"]["receipt"]],
            "preview": ["--dispatch-batch", entry["batch"], "--receipt", entry["host"]["request"]["receipt"]],
            "send": ["--dispatch-batch", entry["batch"], "--receipt", entry["host"]["request"]["receipt"],
                     "--expect-sha256", "f" * 64, "--send"],
            "query-receipt": ["--robot-send-receipt=exact-op.1", "--robot-format=json"],
        }
        for mode, argv in expected.items():
            with self.subTest(mode=mode):
                result = subprocess.run(["/bin/bash", "--noprofile", "--norc", "-p", "-c", dispatch.remote_command(entry, mode)],
                    cwd=root, env={"HOME": str(root), "PATH": f"{bin_dir}:/usr/bin:/bin"},
                    capture_output=True, timeout=5, **identity)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), argv)
        self.assertFalse((root / "BAD").exists())

    def test_recovery_actions_are_mutually_exclusive_in_cli(self):
        script = Path(dispatch.__file__)
        result = subprocess.run([sys.executable, "-I", str(script), "--send", "--resume"], capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
