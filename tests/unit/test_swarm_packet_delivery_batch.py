"""Multi-agent dispatch and cross-process recovery through the real entrypoint."""
import copy
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/lib/swarm_packet.sh"

FIXTURE = r'''#!/usr/bin/env python3
import hashlib, json, os, pathlib, sys
root = pathlib.Path(os.environ["BATCH_FIXTURE_ROOT"])
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
mode = os.environ.get("BATCH_FIXTURE_MODE", "ok")
with (root / "calls.jsonl").open("a") as f:
    f.write(json.dumps([name, args]) + "\n")
if name == "br":
    assert args == ["ready", "--json"], args
    print(json.dumps([{"id": "bd-" + str(i), "status": "open"} for i in (1, 2, 3)
                      if not (mode == "not-ready" and i == 2)]))
    sys.exit(0)
if name == "tmux":
    assert args[:3] == ["display-message", "-p", "-t"]
    number = int(args[3][1:]) - 40
    command = "codex" if number == 2 else "claude"
    if mode == "wrong-pane" and number == 2: command = "bash"
    print("project\t%" + str(40+number) + "\t" + str(root / "repo") + "\t0\t" + command)
    sys.exit(0)
assert name == "ntm"
if args[0].startswith("--robot-send-receipt="):
    op = args[0].split("=", 1)[1]
    store = root / (op + ".ntm.json")
    if not store.exists():
        print(json.dumps({"success": False, "error_code": "NOT_FOUND"}))
        sys.exit(1)
    recorded = json.loads(store.read_text())
    print(json.dumps({"success": True, "session": "project", "operation": recorded["operation"], "outcome": recorded}))
    sys.exit(0)
assert args[0] == "--robot-send=project", args
pane = next(a.split("=", 1)[1] for a in args if a.startswith("--panes="))
number = int(pane[1:]) - 40
assert "--type=" + ("codex" if number == 2 else "claude") in args, args
assert "--msg-file=-" in args and "--no-cass" in args and "--with-memory=false" in args, args
payload = sys.stdin.buffer.read()
expected = (root / ("expected-" + str(number))).read_bytes()
assert payload == expected
if "--dry-run" in args:
    print(json.dumps({"success": True, "session": "project", "dry_run": True, "blocked": False,
                      "successful": [], "failed": [], "would_send_to": [str(number)]}))
    sys.exit(0)
op = next(a.split("=", 1)[1] for a in args if a.startswith("--op-id="))
assert op == "batch-op-" + str(number)
recorded = {"success": True, "session": "project", "targets": [str(number)],
            "successful": [str(number)], "failed": [], "operation": {"operation_id": op, "status": "completed",
            "payload_sha256": hashlib.sha256(payload).hexdigest(), "payload_bytes": len(payload),
            "admissions": [{"target": str(number), "state": "submitted"}]}}
if mode != "missing" or number != 2:
    (root / (op + ".ntm.json")).write_text(json.dumps(recorded))
if mode in ("lost", "missing") and number == 2:
    print("private stderr must not leak", file=sys.stderr)
    sys.exit(1)
print(json.dumps(recorded))
'''


class BatchDeliveryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="acfs-batch-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        if Path("/usr/bin/python3").exists():
            (self.bin / "python3").symlink_to("/usr/bin/python3")
        for name in ("ntm", "br", "tmux"):
            path = self.bin / name
            path.write_text(FIXTURE)
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        BATCH_FIXTURE_ROOT=str(self.root))
        self.batch = self.root / "batch.json"
        self.spec = {"schema": "acfs.packet-delivery-batch.v1", "deliveries": []}
        for i in (1, 2, 3):
            prompt = "# ACFS Swarm Startup Packet\n\nTask bd-" + str(i) + "; private code context.\n"
            packet = {"schema_version": 1, "status": "pass", "repository": {"path": str(self.repo)},
                      "bead": {"id": "bd-" + str(i), "status": "open"},
                      "output": {"truncated": False}, "packet_markdown": prompt}
            (self.root / ("packet-" + str(i) + ".json")).write_text(json.dumps(packet))
            (self.root / ("expected-" + str(i))).write_bytes(prompt.encode())
            self.spec["deliveries"].append({"packet": "packet-" + str(i) + ".json", "repo": "repo",
                "session": "project", "pane": "%" + str(40 + i), "agent_type": "codex" if i == 2 else "claude",
                "operation_id": "batch-op-" + str(i), "receipt": "receipt-" + str(i) + ".json"})
        self.save()

    def save(self):
        self.batch.write_text(json.dumps(self.spec))

    def invoke(self, review_hash=None, send=False, mode="ok"):
        args = ["bash", str(SCRIPT), "--deliver-batch", str(self.batch)]
        if review_hash is not None:
            args += ["--expect-sha256", review_hash]
        if send:
            args.append("--send")
        result = subprocess.run(args, cwd="/", env=dict(self.env, BATCH_FIXTURE_MODE=mode),
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.stderr, "", result.stderr)
        report = json.loads(result.stdout)
        self.assertNotIn("private stderr", result.stdout)
        self.assertNotIn("private code context", result.stdout)
        return result.returncode, report

    def preview_hash(self):
        code, report = self.invoke()
        self.assertEqual(code, 0, report)
        return report["review_sha256"]

    def calls(self):
        path = self.root / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def sends(self):
        return [next(a for a in args if a.startswith("--op-id=")) for name, args in self.calls()
                if name == "ntm" and args[0] == "--robot-send=project" and "--dry-run" not in args]

    def test_preview_binds_every_payload_and_does_not_probe_or_write(self):
        code, report = self.invoke()
        self.assertEqual((code, report["status"]), (0, "preview"))
        self.assertEqual(report["delivery_count"], 3)
        self.assertEqual(self.calls(), [])
        self.assertEqual(list(self.root.glob("receipt*")), [])
        self.assertIn("--send", shlex.split(report["send_command"]))
        self.assertFalse(report["agent_execution_verified"])
        for item in report["deliveries"]:
            self.assertIn(str(self.root), item["receipt"])
            self.assertEqual(item["request"]["repo"], str(self.repo))

    def test_three_agents_receive_distinct_packets(self):
        code, report = self.invoke(self.preview_hash(), send=True)
        self.assertEqual((code, report["status"]), (0, "submitted"), report)
        self.assertEqual(report["summary"]["submitted"], 3)
        self.assertEqual(report["summary"]["not_attempted"], 0)
        self.assertEqual(self.sends(), ["--op-id=batch-op-1", "--op-id=batch-op-2", "--op-id=batch-op-3"])
        self.assertEqual(len(list(self.root.glob("receipt*"))), 3)

    def test_retry_queries_all_receipts_without_resubmitting(self):
        review = self.preview_hash()
        self.invoke(review, send=True)
        code, report = self.invoke(review, send=True)
        self.assertEqual((code, report["status"]), (0, "submitted"), report)
        self.assertEqual(report["summary"]["reconciled"], 3)
        self.assertFalse(report["sends_prompt"])
        self.assertEqual(len(self.sends()), 3)

    def test_lost_middle_response_stops_then_resumes_remaining_agent(self):
        review = self.preview_hash()
        code, report = self.invoke(review, send=True, mode="lost")
        self.assertEqual((code, report["status"]), (1, "stopped"), report)
        self.assertEqual([item["status"] for item in report["deliveries"]],
                         ["submitted", "unconfirmed", "not_attempted"])
        self.assertEqual(len(self.sends()), 2)
        self.assertFalse((self.root / "receipt-3.json").exists())
        code, report = self.invoke(review, send=True)
        self.assertEqual((code, report["status"]), (0, "submitted"), report)
        self.assertEqual(report["summary"]["reconciled"], 2)
        self.assertEqual(self.sends(), ["--op-id=batch-op-1", "--op-id=batch-op-2", "--op-id=batch-op-3"])

    def test_missing_middle_receipt_keeps_later_agents_unattempted(self):
        review = self.preview_hash()
        self.invoke(review, send=True, mode="missing")
        for _ in range(2):
            code, report = self.invoke(review, send=True)
            self.assertEqual((code, report["status"]), (1, "stopped"), report)
            self.assertEqual(report["summary"]["not_attempted"], 1)
        self.assertEqual(len(self.sends()), 2)

    def test_invalid_later_packet_blocks_entire_batch_before_tools(self):
        path = self.root / "packet-3.json"
        packet = json.loads(path.read_text())
        packet["output"]["truncated"] = True
        path.write_text(json.dumps(packet))
        code, _ = self.invoke(send=True, review_hash="0" * 64)
        self.assertEqual(code, 2)
        self.assertEqual(self.calls(), [])

    def test_changed_later_packet_requires_new_review(self):
        review = self.preview_hash()
        path = self.root / "packet-3.json"
        packet = json.loads(path.read_text())
        packet["packet_markdown"] += "New instruction.\n"
        path.write_text(json.dumps(packet))
        code, report = self.invoke(review, send=True)
        self.assertEqual(code, 2)
        self.assertIn("changed since review", report["error"])
        self.assertEqual(self.calls(), [])

    def test_changed_batch_requires_new_review(self):
        review = self.preview_hash()
        self.spec["deliveries"][2]["operation_id"] = "different-operation"
        self.save()
        code, _ = self.invoke(review, send=True)
        self.assertEqual(code, 2)
        self.assertEqual(self.calls(), [])

    def test_send_requires_combined_review_hash(self):
        code, report = self.invoke(send=True)
        self.assertEqual(code, 2)
        self.assertIn("Preview the batch", report["error"])
        self.assertEqual(self.calls(), [])

    def test_duplicate_targets_operations_and_receipts_are_rejected(self):
        original = copy.deepcopy(self.spec)
        for key in ("pane", "operation_id", "receipt"):
            with self.subTest(key=key):
                self.spec = copy.deepcopy(original)
                self.spec["deliveries"][1][key] = self.spec["deliveries"][0][key]
                self.save()
                code, _ = self.invoke()
                self.assertEqual(code, 2)
                self.assertEqual(self.calls(), [])

    def test_same_bead_cannot_be_dispatched_twice(self):
        path = self.root / "packet-2.json"
        packet = json.loads(path.read_text())
        packet["bead"]["id"] = "bd-1"
        path.write_text(json.dumps(packet))
        code, report = self.invoke()
        self.assertEqual(code, 2)
        self.assertIn("same repository Bead", report["error"])

    def test_receipt_cannot_alias_a_later_packet_or_batch(self):
        original = copy.deepcopy(self.spec)
        for target in ("packet-3.json", "batch.json"):
            with self.subTest(target=target):
                self.spec = copy.deepcopy(original)
                self.spec["deliveries"][0]["receipt"] = target
                self.save()
                code, _ = self.invoke()
                self.assertEqual(code, 2)
                self.assertEqual(self.calls(), [])

    def test_conflicting_later_receipt_prevents_any_new_sends(self):
        path = self.root / "receipt-3.json"
        path.write_text('{"schema":"unrelated"}')
        path.chmod(0o600)
        code, _ = self.invoke(send=True, review_hash="0" * 64)
        self.assertEqual(code, 2)
        self.assertEqual(path.read_text(), '{"schema":"unrelated"}')
        self.assertEqual(self.calls(), [])

    def test_live_middle_preflight_failure_preserves_first_submission(self):
        review = self.preview_hash()
        code, report = self.invoke(review, send=True, mode="not-ready")
        self.assertEqual((code, report["status"]), (2, "stopped"), report)
        self.assertEqual([item["status"] for item in report["deliveries"]],
                         ["submitted", "error", "not_attempted"])
        self.assertEqual(len(self.sends()), 1)
        code, report = self.invoke(review, send=True)
        self.assertEqual(code, 0, report)
        self.assertEqual(report["summary"]["reconciled"], 1)
        self.assertEqual(len(self.sends()), 3)

    def test_invalid_manifest_shapes_and_entry_types_are_rejected(self):
        original = copy.deepcopy(self.spec)
        bad_specs = [[], {}, {"schema": "other", "deliveries": []},
                     dict(original, deliveries=[]), dict(original, extra=True),
                     dict(original, deliveries=[None]), dict(original, deliveries=[{}]),
                     dict(original, deliveries=original["deliveries"] * 11)]
        for key in ("pane", "packet", "agent_type"):
            spec = copy.deepcopy(original)
            spec["deliveries"][1][key] = True
            bad_specs.append(spec)
        for spec in bad_specs:
            with self.subTest(spec=str(spec)[:90]):
                self.batch.write_text(json.dumps(spec))
                code, _ = self.invoke()
                self.assertEqual(code, 2)
        self.assertEqual(self.calls(), [])

    def test_duplicate_manifest_keys_are_rejected(self):
        self.batch.write_text('{"schema":"ignored",' + json.dumps(self.spec)[1:])
        code, _ = self.invoke()
        self.assertEqual(code, 2)
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
