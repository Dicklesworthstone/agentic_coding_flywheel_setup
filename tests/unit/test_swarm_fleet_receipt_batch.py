#!/usr/bin/env python3
"""Two-phase receipt verification: real private readers, processes and journals."""
import base64
import copy
from contextlib import redirect_stdout
import fcntl
import io
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
from unittest.mock import patch

import test_swarm_fleet_dispatch as fixtures

dispatch, fleet = fixtures.dispatch, fixtures.fleet


def native(delivery):
    return {"schema": "acfs.packet-delivery.v1", "request": copy.deepcopy(delivery["request"]),
            "target": "recorded:" + delivery["request"]["operation_id"]}


def proof(delivery):
    request, target = delivery["request"], native(delivery)["target"]
    return {"success": True, "session": request["session"], "operation": {
        "operation_id": request["operation_id"], "payload_sha256": request["payload_sha256"],
        "payload_bytes": request["payload_bytes"], "status": "completed",
        "admissions": [{"target": target, "state": "submitted"}]},
        "outcome": {"success": True, "targets": [target], "successful": [target], "failed": []}}


def deliveries(count=2):
    return [{"slot": i, "receipt": f"/home/ubuntu/receipts/op-{i}.json", "request": {
        "repo": "/data/projects/app", "session": "implementation", "pane": "%" + str(i),
        "agent_type": "claude", "operation_id": f"op-{i}", "bead_id": f"bd-{i}",
        "packet_sha256": "a" * 64, "payload_sha256": "b" * 64, "payload_bytes": 120}}
        for i in range(1, count + 1)]


class ProtocolPeer:
    def __init__(self):
        self.calls, self.probes = [], []
        self.change_intent = self.change_proof = self.change_batch = None

    def one(self, delivery, kind):
        self.probes.append((delivery["request"]["operation_id"], kind))
        value = native(delivery) if kind == "read" else proof(delivery)
        change = self.change_intent if kind == "read" else self.change_proof
        if change:
            change(value)
        return fleet.encoded(value)

    def __call__(self, entry, mode):
        self.calls.append(mode)
        if mode in ("read-receipt", "query-receipt"):
            return 0, self.one(entry["delivery"], "read" if mode == "read-receipt" else "query")
        assert mode in ("batch-read-receipts", "batch-query-receipts"), mode
        request = entry["receipt_batch"]
        by_id = {d["request"]["operation_id"]: d for d in entry["deliveries"]}
        value = {"schema": dispatch.BATCH_RECEIPT_SCHEMA, "request_sha256": fleet.digest(fleet.encoded(request)),
                 "rows": [{"operation_id": item["operation_id"], "status": "captured",
                    "stdout_base64": base64.b64encode(self.one(by_id[item["operation_id"]], request["kind"])).decode()}
                    for item in request["items"]]}
        if self.change_batch:
            self.change_batch(value)
        return 0, fleet.encoded(value)


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.entry = {"deliveries": deliveries()}
        self.peer = ProtocolPeer()

    def test_thirty_two_deliveries_keep_same_proof_with_two_calls_not_sixty_four(self):
        self.entry["deliveries"] = deliveries(32)
        individual = ProtocolPeer()
        for delivery in self.entry["deliveries"]:
            dispatch.query_submission(self.entry, delivery, individual)
        result = dispatch.query_submissions(self.entry, self.peer)
        self.assertEqual(result, [None] * 32)
        self.assertEqual(len(individual.calls), 64)
        self.assertEqual(self.peer.calls, ["batch-read-receipts", "batch-query-receipts"])
        self.assertCountEqual(individual.probes, self.peer.probes)

    def test_wrong_native_intent_never_enters_query_batch(self):
        def wrong(value):
            if value["request"]["operation_id"] == "op-1":
                value["request"]["repo"] = "/wrong"
        self.peer.change_intent = wrong
        self.assertEqual(dispatch.query_submissions(self.entry, self.peer), ["native_receipt_mismatch", None])
        self.assertNotIn(("op-1", "query"), self.peer.probes)
        self.assertIn(("op-2", "query"), self.peer.probes)

    def test_no_valid_intents_means_no_ntm_batch(self):
        self.peer.change_intent = lambda v: v.update(schema="wrong")
        self.assertEqual(dispatch.query_submissions(self.entry, self.peer), ["native_receipt_mismatch"] * 2)
        self.assertEqual(self.peer.calls, ["batch-read-receipts"])

    def test_all_original_ntm_identity_checks_remain_required(self):
        changes = [lambda v: v.update(success=False), lambda v: v.update(session="other"),
            lambda v: v["operation"].update(operation_id="other"),
            lambda v: v["operation"].update(payload_sha256="0" * 64),
            lambda v: v["operation"].update(payload_bytes=True),
            lambda v: v["operation"].update(status="pending"),
            lambda v: v["operation"].update(admissions=[]),
            lambda v: v["outcome"].update(success=False),
            lambda v: v["outcome"].update(targets=["other"]),
            lambda v: v["outcome"].update(successful=[]),
            lambda v: v["outcome"].update(failed=["other"])]
        for change in changes:
            with self.subTest(change=change):
                self.peer.change_proof = change
                self.assertEqual(dispatch.query_submissions(self.entry, self.peer), ["submission_not_confirmed"] * 2)
                with self.assertRaisesRegex(fleet.Refused, "submission_not_confirmed"):
                    dispatch.query_submission(self.entry, self.entry["deliveries"][0], self.peer)

    def test_broken_frames_request_binding_and_row_order_are_not_trusted(self):
        changes = [lambda v: v.update(request_sha256="0" * 64), lambda v: v.update(schema="wrong"),
                   lambda v: v["rows"].reverse(), lambda v: v["rows"].pop(),
                   lambda v: v["rows"].append(v["rows"][0]), lambda v: v.update(secret="SECRET"),
                   lambda v: v["rows"][0].update(stdout_base64="%%%"),
                   lambda v: v["rows"][0].update(status="submitted"),
                   lambda v: v["rows"][0].update(stdout_base64=base64.b64encode(b"x" * 65537).decode())]
        for change in changes:
            with self.subTest(change=change):
                self.peer = ProtocolPeer()
                self.peer.change_batch = change
                with self.assertRaises(fleet.Refused):
                    dispatch.query_submissions(self.entry, self.peer)
                self.assertEqual(self.peer.calls, ["batch-read-receipts"])

    def test_unavailable_frame_only_marks_that_delivery_unconfirmed(self):
        def unavailable(value):
            for index, row in enumerate(value["rows"]):
                if row["operation_id"] == "op-1":
                    value["rows"][index] = {"operation_id": "op-1", "status": "unavailable", "code": "batch_output_limit"}
        self.peer.change_batch = unavailable
        self.assertEqual(dispatch.query_submissions(self.entry, self.peer), ["batch_output_limit", None])

    def test_malformed_per_item_json_does_not_erase_healthy_peer(self):
        def malformed(value):
            if len(value["rows"]) == 2:
                value["rows"][0]["stdout_base64"] = base64.b64encode(b"not-json SECRET").decode()
        self.peer.change_batch = malformed
        self.assertEqual(dispatch.query_submissions(self.entry, self.peer), ["invalid_json", None])
        self.assertNotIn(("op-1", "query"), self.peer.probes)

    def test_invalid_selection_and_budget_fail_before_transport(self):
        for entries in ([], deliveries(33), [deliveries()[0]] * 2):
            with self.subTest(entries=len(entries)), self.assertRaises(fleet.Refused):
                dispatch.query_submissions({"deliveries": entries}, self.peer)
        for timeout in (0, 601, True, "10"):
            with self.subTest(timeout=timeout), self.assertRaises(fleet.Refused):
                dispatch.query_submissions(self.entry, self.peer, timeout)
        self.assertEqual(self.peer.calls, [])

    def test_shell_metacharacters_are_literal_and_query_is_never_send(self):
        self.entry["deliveries"][0]["receipt"] = "/home/ubuntu/a 'quoted'; $(touch BAD)/intent.json"
        request = {"kind": "read", "nonce": "a" * 32, "timeout": 10,
                   "items": [{"operation_id": "op-1", "receipt": self.entry["deliveries"][0]["receipt"]}]}
        command = dispatch.receipt_batch_command(request, "read")
        argv = shlex.split(command)
        self.assertEqual(argv[:4], ["exec", "/usr/bin/python3", "-I", "-c"])
        self.assertEqual(json.loads(argv[-1]), request)
        request = {"kind": "query", "nonce": "a" * 32, "timeout": 10,
                   "items": [{"operation_id": "op-1 --robot-send=BAD"}]}
        with self.assertRaises(fleet.Refused):
            dispatch.receipt_batch_command(request, "query")

    def test_ssh_trust_policy_is_kept_for_batches(self):
        host = {"host": "192.0.2.1", "port": 22, "user": "ubuntu", "request": {"receipt": "/home/ubuntu/intent.json"}}
        request = {"kind": "query", "nonce": "a" * 32, "timeout": 7, "items": [{"operation_id": "op-1"}]}
        calls = []
        def runner(argv, deadline, env):
            calls.append(argv)
            self.assertEqual(deadline, 7)
            for option in ("StrictHostKeyChecking=yes", "ForwardAgent=no", "ProxyCommand=none", "SendEnv=-*"):
                self.assertIn(option, argv)
            self.assertNotIn("OPENAI_API_KEY", env)
            self.assertEqual(Path(argv[argv.index("-i") + 1]).read_bytes(), b"key")
            self.assertEqual(json.loads(shlex.split(argv[-1])[-1]), request)
            return 0, b"{}"
        invoke = dispatch.transport(b"known", b"key", 7, runner=runner, ssh=sys.executable)
        invoke({"host": host, "receipt_batch": request}, "batch-query-receipts")
        self.assertEqual(len(calls), 1)


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.addCleanup(os.umask, os.umask(0o022))
        self.fx = fixtures.DispatchTests()
        self.fx.setUp()
        self.approval = self.fx.approved()
        def lost(_entry, mode, _value):
            if mode == "send":
                raise fleet.Refused("ssh_timeout")
        self.fx.peer.mutate = lost
        self.assertEqual(self.fx.run_dispatch("send", self.approval)[1], 1)
        self.fx.peer.mutate = None
        self.peer, self.calls = ProtocolPeer(), []

    def invoke(self, entry, mode):
        self.calls.append((entry["host"]["id"], mode))
        for directory in (self.fx.launch_dir, self.fx.state):
            with fleet.directory_fd(directory, private=True) as fd:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if mode.startswith("batch-"):
            return self.peer(entry, mode)
        return self.fx.peer(entry, mode)

    def execute(self, mode="reconcile", approval=None):
        return dispatch.execute(self.fx.launch_dir, self.fx.batches, self.fx.known, self.fx.identity,
                                self.fx.state, 360, mode, approval, self.invoke, batch_receipts=True)

    def snapshot(self):
        return {str(p): (p.read_bytes(), p.stat().st_mode, p.stat().st_mtime_ns)
                for parent in (self.fx.launch_dir, self.fx.state) for p in parent.iterdir()}

    def test_partial_reconcile_queries_attempted_host_without_writes_or_launch_checks(self):
        before = self.snapshot()
        result, code = self.execute()
        self.assertEqual((code, result["status"]), (1, "partial"))
        self.assertEqual(self.calls, [("worker-0", "batch-read-receipts"), ("worker-0", "batch-query-receipts")])
        self.assertEqual(before, self.snapshot())
        self.assertFalse(result["send_attempted"])

    def test_resume_recovers_lost_result_and_only_sends_untouched_host(self):
        before = self.fx.snapshot()
        result, code = self.execute("resume", self.approval)
        self.assertEqual((code, result["status"]), (0, "submitted"))
        self.assertEqual([c for c in self.calls if c[1] == "send"], [("worker-1", "send")])
        self.assertEqual(before, self.fx.snapshot())
        self.assertTrue((self.fx.state / "worker-0.result.json").is_file())
        self.assertTrue((self.fx.state / "worker-1.result.json").is_file())

    def test_unknown_submission_blocks_every_pending_send_without_result_repair(self):
        self.peer.change_proof = lambda v: v["operation"].update(status="pending")
        before = self.snapshot()
        result, code = self.execute("resume", self.approval)
        self.assertEqual((code, result["status"]), (1, "unconfirmed"))
        self.assertEqual(before, self.snapshot())
        self.assertFalse(any(mode == "send" for _, mode in self.calls))

    def test_wrong_approval_is_rejected_before_any_batch_calls(self):
        with self.assertRaisesRegex(fleet.Refused, "approval_mismatch"):
            self.execute("resume", "0" * 64)
        self.assertEqual(self.calls, [])

    def test_journal_mutation_during_batch_stops_before_next_phase_or_resume(self):
        def change(_value):
            path = self.fx.state / "worker-0.attempt.json"
            path.write_bytes(path.read_bytes() + b" ")
        self.peer.change_batch = change
        with self.assertRaisesRegex(fleet.Refused, "state_changed"):
            self.execute("resume", self.approval)
        self.assertEqual(self.calls, [("worker-0", "batch-read-receipts")])

    def test_batch_flag_cannot_be_used_to_send_without_recovery(self):
        with self.assertRaisesRegex(fleet.Refused, "requires_reconciliation_or_resume"):
            self.execute("send", self.approval)
        self.assertEqual(self.calls, [])
        with patch.object(fleet, "read_input") as read, self.assertRaises(fleet.Refused):
            dispatch.main(["--launch-state", "/x", "--batches", "/x", "--known-hosts", "/x",
                           "--identity-file", "/x", "--state-dir", "/x", "--batch-receipts"])
        read.assert_not_called()

    def test_cli_reconcile_uses_batched_path(self):
        paths = []
        for name, raw in (("batches.json", fleet.encoded(self.fx.batches)), ("known", self.fx.known), ("key", self.fx.identity)):
            path = self.fx.root / name
            path.write_bytes(raw)
            path.chmod(0o600)
            paths.append(str(path))
        with patch.object(dispatch, "transport", return_value=self.invoke), redirect_stdout(io.StringIO()) as out:
            code = dispatch.main(["--launch-state", str(self.fx.launch_dir), "--batches", paths[0],
                "--known-hosts", paths[1], "--identity-file", paths[2], "--state-dir", str(self.fx.state),
                "--reconcile", "--batch-receipts"])
        self.assertEqual((code, json.loads(out.getvalue())["status"]), (1, "partial"))
        self.assertEqual(len(self.calls), 2)


class RemoteReadBatchTests(unittest.TestCase):
    def test_batch_reader_is_read_only_and_item_local(self):
        self.assertIn("native_receipt_unavailable", dispatch.READ_RECEIPT_BATCH)
        self.assertNotIn("robot-send", dispatch.READ_RECEIPT_BATCH)
        self.assertNotIn("subprocess", dispatch.READ_RECEIPT_BATCH)

    def test_batch_mode_keeps_existing_ntm_query_path(self):
        items = deliveries(2)
        peer = ProtocolPeer()
        failures = dispatch.query_submissions_batched_reads({"deliveries": items}, peer)
        self.assertEqual(failures, [None, None])
        self.assertEqual(peer.calls[0], "batch-read-receipts")
        self.assertEqual(peer.calls[1:], ["query-receipt", "query-receipt"])


if __name__ == "__main__":
    unittest.main()
\n# Offline audit coverage is added in the next revision.\n