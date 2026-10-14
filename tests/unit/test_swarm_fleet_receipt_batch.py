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

    def __call__(self, entry, mode):
        self.calls.append(mode)
        if mode == "read-receipt":
            item = entry["delivery"]
            value = native(item)
            if self.change_intent:
                self.change_intent(value)
            self.probes.append((item["request"]["operation_id"], "read"))
            return 0, fleet.encoded(value)
        if mode == "query-receipt":
            item = entry["delivery"]
            value = proof(item)
            if self.change_proof:
                self.change_proof(value)
            self.probes.append((item["request"]["operation_id"], "query"))
            return 0, fleet.encoded(value)
        assert mode == "batch-read-receipts", mode
        request = entry["receipt_batch"]
        by_id = {d["request"]["operation_id"]: d for d in entry["deliveries"]}
        rows = []
        for requested in request["items"]:
            item = by_id[requested["operation_id"]]
            value = native(item)
            if self.change_intent:
                self.change_intent(value)
            self.probes.append((requested["operation_id"], "read"))
            rows.append({"operation_id": requested["operation_id"], "status": "captured",
                         "stdout_base64": base64.b64encode(fleet.encoded(value)).decode()})
        value = {"schema": dispatch.BATCH_RECEIPT_SCHEMA,
                 "request_sha256": fleet.digest(fleet.encoded(request)), "rows": rows}
        if self.change_batch:
            self.change_batch(value)
        return 0, fleet.encoded(value)


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.entry = {"deliveries": deliveries()}
        self.peer = ProtocolPeer()

    def test_thirty_two_deliveries_cut_receipt_read_connections_in_half(self):
        self.entry["deliveries"] = deliveries(32)
        individual = ProtocolPeer()
        for item in self.entry["deliveries"]:
            dispatch.query_submission(self.entry, item, individual)
        result = dispatch.query_submissions_batched_reads(self.entry, self.peer)
        self.assertEqual(result, [None] * 32)
        self.assertEqual(len(individual.calls), 64)
        self.assertEqual(self.peer.calls[0], "batch-read-receipts")
        self.assertEqual(self.peer.calls[1:], ["query-receipt"] * 32)
        self.assertEqual(len(self.peer.calls), 33)

    def test_wrong_native_intent_never_enters_query_path(self):
        def wrong(value):
            if value["request"]["operation_id"] == "op-1":
                value["request"]["repo"] = "/wrong"
        self.peer.change_intent = wrong
        self.assertEqual(dispatch.query_submissions_batched_reads(self.entry, self.peer),
                         ["native_receipt_mismatch", None])
        self.assertNotIn(("op-1", "query"), self.peer.probes)
        self.assertIn(("op-2", "query"), self.peer.probes)

    def test_no_valid_intents_means_no_ntm_queries(self):
        self.peer.change_intent = lambda v: v.update(schema="wrong")
        self.assertEqual(dispatch.query_submissions_batched_reads(self.entry, self.peer),
                         ["native_receipt_mismatch"] * 2)
        self.assertEqual(self.peer.calls, ["batch-read-receipts"])

    def test_existing_ntm_identity_checks_remain_required(self):
        changes = [lambda v: v.update(success=False),
                   lambda v: v.update(session="other"),
                   lambda v: v["operation"].update(payload_sha256="0" * 64),
                   lambda v: v["operation"].update(status="pending"),
                   lambda v: v["operation"].update(admissions=[]),
                   lambda v: v["outcome"].update(success=False),
                   lambda v: v["outcome"].update(targets=["other"])]
        for change in changes:
            with self.subTest(change=change):
                self.peer = ProtocolPeer()
                self.peer.change_proof = change
                self.assertEqual(dispatch.query_submissions_batched_reads(self.entry, self.peer),
                                 ["submission_not_confirmed"] * 2)

    def test_reordered_or_mismatched_batch_envelope_is_refused(self):
        for change in (lambda v: v["rows"].reverse(),
                       lambda v: v.update(request_sha256="0" * 64),
                       lambda v: v.update(schema="wrong")):
            with self.subTest(change=change):
                self.peer = ProtocolPeer()
                self.peer.change_batch = change
                with self.assertRaises(fleet.Refused):
                    dispatch.query_submissions_batched_reads(self.entry, self.peer)
                self.assertEqual(self.peer.calls, ["batch-read-receipts"])

    def test_one_unavailable_receipt_does_not_hide_healthy_peer(self):
        def unavailable(value):
            value["rows"][0] = {"operation_id": "op-1", "status": "unavailable",
                                "code": "native_receipt_unavailable"}
        self.peer.change_batch = unavailable
        self.assertEqual(dispatch.query_submissions_batched_reads(self.entry, self.peer),
                         ["native_receipt_unavailable", None])
        self.assertEqual(self.peer.calls, ["batch-read-receipts", "query-receipt"])

    def test_malformed_item_is_local_and_not_queried(self):
        def malformed(value):
            value["rows"][0]["stdout_base64"] = base64.b64encode(b"not-json").decode()
        self.peer.change_batch = malformed
        self.assertEqual(dispatch.query_submissions_batched_reads(self.entry, self.peer),
                         ["invalid_json", None])
        self.assertEqual(self.peer.calls, ["batch-read-receipts", "query-receipt"])

    def test_batch_reader_is_strictly_read_only(self):
        self.assertNotIn("subprocess", dispatch.READ_RECEIPT_BATCH)
        self.assertNotIn("robot-send", dispatch.READ_RECEIPT_BATCH)

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
        self.assertEqual(self.calls, [("worker-0", "batch-read-receipts"),
                                      ("worker-0", "query-receipt"), ("worker-0", "query-receipt")])
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
        self.assertEqual(len(self.calls), 3)


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