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


class RemoteBatchTests(unittest.TestCase):
    def setUp(self):
        self.addCleanup(os.umask, os.umask(0o022))
        self.root = Path(tempfile.mkdtemp(prefix="acfs-real-batch-"))
        self.uid = 65534 if os.geteuid() == 0 else os.geteuid()
        self.gid = 65534 if os.geteuid() == 0 else os.getegid()
        self.options = {"user": self.uid, "group": self.gid, "extra_groups": []} if os.geteuid() == 0 else {}
        self.owned(self.root)
        self.bin = self.root / "bin"
        self.bin.mkdir(mode=0o700)
        self.owned(self.bin)
        self.stub = self.bin / "ntm"
        self.stub.write_text('''#!/usr/bin/python3
import json, os, pathlib, signal, sys, time
root = pathlib.Path(os.environ['HOME'])
assert len(sys.argv) == 3 and sys.argv[1].startswith('--robot-send-receipt=') and sys.argv[2] == '--robot-format=json'
op = sys.argv[1].split('=', 1)[1]
with (root / 'queries.log').open('a') as stream:
    stream.write(op + '\\n')
if op == 'hang':
    (root / 'pid').write_text(str(os.getpid()))
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    time.sleep(30)
elif op == 'noisy':
    sys.stderr.write('SECRET' * 20000)
elif op == 'large':
    sys.stdout.write('x' * 65537)
elif op == 'fail':
    sys.stderr.write('SECRET')
    sys.exit(1)
else:
    sys.stdout.buffer.write((root / (op + '.proof')).read_bytes())
''')
        self.stub.chmod(0o700)
        self.owned(self.stub)
        self.entry = {"deliveries": deliveries()}
        for delivery in self.entry["deliveries"]:
            op = delivery["request"]["operation_id"]
            path = self.root / (op + " 'literal'; $(touch BAD).json")
            self.write(path, fleet.encoded(native(delivery)))
            delivery["receipt"] = str(path)
            self.write(self.root / (op + ".proof"), fleet.encoded(proof(delivery)))
        self.calls = []

    def owned(self, path):
        if os.geteuid() == 0:
            os.chown(path, self.uid, self.gid)

    def write(self, path, raw):
        path.write_bytes(raw)
        path.chmod(0o600)
        self.owned(path)

    def invoke(self, entry, mode):
        self.calls.append(mode)
        command = dispatch.remote_command(entry, mode)
        result = subprocess.run(["/bin/bash", "--noprofile", "--norc", "-p", "-c", command], cwd="/",
            env={"PATH": str(self.bin) + ":/usr/bin:/bin", "HOME": str(self.root), "LANG": "C.UTF-8"},
            capture_output=True, timeout=15, **self.options)
        self.assertEqual(result.stderr, b"")
        return result.returncode, result.stdout

    def request(self, operations, timeout=10):
        return {"kind": "query", "nonce": "a" * 32, "timeout": timeout,
                "items": [{"operation_id": op} for op in operations]}

    def test_real_two_phase_reader_and_ntm_processes_validate_both_deliveries(self):
        before = {str(p): (p.read_bytes(), p.stat().st_mtime_ns) for p in self.root.iterdir() if p.is_file()}
        self.assertEqual(dispatch.query_submissions(self.entry, self.invoke), [None, None])
        self.assertEqual(self.calls, ["batch-read-receipts", "batch-query-receipts"])
        self.assertEqual((self.root / "queries.log").read_text().splitlines(), ["op-1", "op-2"])
        self.assertFalse((self.root / "BAD").exists())
        for path, expected in before.items():
            self.assertEqual((Path(path).read_bytes(), Path(path).stat().st_mtime_ns), expected)

    def test_real_invalid_intent_is_not_queried_but_other_item_is(self):
        self.write(Path(self.entry["deliveries"][0]["receipt"]), b'{"schema":"bad"}')
        self.assertEqual(dispatch.query_submissions(self.entry, self.invoke), ["native_receipt_mismatch", None])
        self.assertEqual((self.root / "queries.log").read_text().splitlines(), ["op-2"])

    def test_special_and_unsafe_receipts_are_refused_without_blocking_healthy_item(self):
        first = self.entry["deliveries"][0]
        original = Path(first["receipt"])
        candidates = []
        symlink = self.root / "link"; symlink.symlink_to(original); candidates.append(symlink)
        fifo = self.root / "fifo"; os.mkfifo(fifo, 0o600); self.owned(fifo); candidates.append(fifo)
        writable = self.root / "writable"; self.write(writable, original.read_bytes()); writable.chmod(0o660); candidates.append(writable)
        target = self.root / "linked-source"; self.write(target, original.read_bytes())
        hardlink = self.root / "hardlink"; os.link(target, hardlink); candidates.append(hardlink)
        candidates.append(self.root / "missing")
        for path in candidates:
            with self.subTest(path=path.name):
                first["receipt"] = str(path)
                result = dispatch.query_submissions(self.entry, self.invoke)
                self.assertEqual(result, ["batch_child_failed", None])
        self.assertEqual((self.root / "queries.log").read_text().splitlines(), ["op-2"] * len(candidates))

    def test_real_output_limits_cover_stderr_and_preserve_other_item(self):
        request = self.request(["noisy", "large", "op-2", "fail"])
        code, raw = self.invoke({"receipt_batch": request}, "batch-query-receipts")
        self.assertEqual(code, 0)
        rows = json.loads(raw)["rows"]
        self.assertEqual([r["status"] for r in rows], ["unavailable", "unavailable", "captured", "unavailable"])
        self.assertEqual([rows[i]["code"] for i in (0, 1, 3)], ["batch_output_limit", "batch_output_limit", "batch_child_failed"])
        self.assertNotIn(b"SECRET", raw)

    def test_remote_deadline_is_shared_and_reaps_child_without_querying_later_items(self):
        request = self.request(["hang", "op-2"], timeout=1)
        start = time.monotonic()
        code, raw = self.invoke({"receipt_batch": request}, "batch-query-receipts")
        self.assertEqual(code, 0)
        self.assertLess(time.monotonic() - start, 4)
        self.assertTrue(all(row["code"] == "batch_deadline_exceeded" for row in json.loads(raw)["rows"]))
        self.assertEqual((self.root / "queries.log").read_text().splitlines(), ["hang"])
        with self.assertRaises(ProcessLookupError):
            os.kill(int((self.root / "pid").read_text()), 0)

    def test_remote_validates_entire_request_before_starting_any_child(self):
        valid = self.request(["op-1"])
        command = dispatch.receipt_batch_command(valid, "query")
        argv = shlex.split(command)[1:]
        invalids = [{**valid, "items": [{"operation_id": "op-1"}, {"operation_id": "--robot-send=BAD"}]},
                    {**valid, "items": valid["items"] * 2}, {**valid, "timeout": True},
                    {**valid, "command": "BAD"}, {**valid, "nonce": "bad"}]
        for value in invalids:
            with self.subTest(value=value):
                result = subprocess.run([*argv[:-1], json.dumps(value)], capture_output=True, timeout=5,
                    env={"PATH": str(self.bin) + ":/usr/bin:/bin", "HOME": str(self.root)}, **self.options)
                self.assertEqual((result.returncode, result.stdout, result.stderr), (2, b"", b""))
        self.assertFalse((self.root / "queries.log").exists())

    def test_remote_signal_cancels_and_reaps_only_its_query_process(self):
        request = self.request(["hang", "op-2"], timeout=30)
        argv = shlex.split(dispatch.receipt_batch_command(request, "query"))[1:]
        process = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env={"PATH": str(self.bin) + ":/usr/bin:/bin", "HOME": str(self.root)}, **self.options)
        try:
            end = time.monotonic() + 3
            while not (self.root / "pid").exists() and time.monotonic() < end:
                time.sleep(0.01)
            self.assertTrue((self.root / "pid").exists())
            process.send_signal(signal.SIGTERM)
            out, err = process.communicate(timeout=3)
            self.assertEqual((process.returncode, out, err), (143, b"", b""))
            with self.assertRaises(ProcessLookupError):
                os.kill(int((self.root / "pid").read_text()), 0)
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=5)


if __name__ == "__main__":
    unittest.main()
