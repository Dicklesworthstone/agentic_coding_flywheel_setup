#!/usr/bin/env python3
"""Host-safe recovery tests using the real CLI and a bounded tmux fixture."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/lib/swarm_launch_recovery.py"
FIXTURE = r'''#!/usr/bin/env python3
import json, os, pathlib, sys, time
root = pathlib.Path(os.environ["RECOVERY_FIXTURE"])
log = root / "commands.jsonl"
with log.open("a") as stream:
    stream.write(json.dumps(sys.argv[1:]) + "\n")
count = len(log.read_text().splitlines())
mode = os.environ.get("RECOVERY_MODE", "")
rows = json.loads((root / "panes.json").read_text())
if mode == "error":
    print("DO_NOT_LEAK_SECRET_STDERR", file=sys.stderr)
    sys.exit(17)
if mode == "large":
    print("x" * (1024 * 1024 + 1))
    sys.exit(0)
if mode == "invalid-utf8":
    sys.stdout.buffer.write(b"\xff\n")
    sys.exit(0)
if mode == "timeout":
    time.sleep(30)
if mode == "drift" and count == 2 or mode == "post-drift" and count == 3:
    rows[0][4] = "9876"
if mode == "replace-intent" and count == 2:
    intent = pathlib.Path(os.environ["RECOVERY_INTENT"])
    replacement = intent.with_name("replacement")
    replacement.write_bytes(intent.read_bytes())
    replacement.chmod(0o600)
    replacement.replace(intent)
if mode == "rewrite-intent" and count == 2:
    intent = pathlib.Path(os.environ["RECOVERY_INTENT"])
    intent.write_bytes(intent.read_bytes() + b" ")
if mode == "result-race" and count == 2:
    result = pathlib.Path(os.environ["RECOVERY_INTENT"] + ".result.json")
    result.write_text("retained competitor result")
    result.chmod(0o600)
for row in rows:
    print("\t".join(row))
'''


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="acfs-recovery-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repository with spaces"
        self.repo.mkdir()
        self.receipts = self.root / "receipts"
        self.receipts.mkdir(mode=0o700)
        self.intent = self.receipts / "launch.json"
        self.result = Path(str(self.intent) + ".result.json")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        tmux = self.bin / "tmux"
        tmux.write_text(FIXTURE)
        tmux.chmod(0o755)
        self.request = {"repo": str(self.repo), "session": "swarm-demo", "receipt": str(self.intent),
            "agents": [{"agent_name": "Reviewer", "agent_type": "codex"},
                       {"agent_name": "Builder", "agent_type": "claude"},
                       {"agent_name": "Tester", "agent_type": "codex"}],
            "profile": "balanced", "workload": "standard", "accept_warnings": False}
        self.save_intent()
        # Deliberately unsorted windows and panes: slot mapping must be stable.
        self.panes = [self.pane("%7", "1007", "codex", "2", "0"),
                      self.pane("%3", "1003", "claude", "0", "1"),
                      self.pane("%2", "1002", "codex", "0", "0")]
        self.save_panes()
        self.env = {**os.environ, "PATH": str(self.bin) + os.pathsep + os.environ.get("PATH", ""),
            "RECOVERY_FIXTURE": str(self.root), "RECOVERY_INTENT": str(self.intent)}

    def pane(self, pane, pid, kind, window, index):
        return ["swarm-demo", "$4", "1700000000", pane, pid, "990", str(self.repo), "0", kind, window, index]

    def save_intent(self):
        self.intent.write_text(json.dumps({"schema": "acfs.swarm-launch.v1", "request": self.request}))
        self.intent.chmod(0o600)

    def save_panes(self):
        (self.root / "panes.json").write_text(json.dumps(self.panes))

    def invoke(self, *args, code=0, mode=""):
        (self.root / "commands.jsonl").write_text("")
        process = subprocess.run([sys.executable, "-B", str(SCRIPT), "--receipt", str(self.intent), *args],
            env={**self.env, "RECOVERY_MODE": mode}, text=True, capture_output=True, timeout=8)
        self.assertEqual(process.returncode, code, process.stdout + process.stderr)
        self.assertNotIn("Traceback", process.stderr)
        report = json.loads(process.stdout)
        self.assertFalse(report["starts_agents"])
        self.assertFalse(report["work_dispatched"])
        calls = [json.loads(line) for line in (self.root / "commands.jsonl").read_text().splitlines()]
        for call in calls:
            self.assertEqual(call[:5], ["list-panes", "-s", "-t", "=swarm-demo", "-F"])
            self.assertEqual(len(call), 6)
        return report

    def preview(self):
        report = self.invoke()
        self.assertEqual(report["status"], "preview")
        self.assertFalse(report["result_created"])
        self.assertFalse(report["original_launch_verified"])
        self.assertFalse(self.result.exists())
        return report["review_sha256"]

    def adopt(self, review=None, **kwargs):
        if review is None:
            review = self.preview()
        return self.invoke("--adopt", "--expect-sha256", review, **kwargs)

    def test_preview_is_read_only_and_deterministic(self):
        before = self.intent.read_bytes()
        self.assertEqual(self.preview(), self.preview())
        self.assertEqual(self.intent.read_bytes(), before)
        self.assertEqual(list(self.receipts.iterdir()), [self.intent])

    def test_adoption_creates_private_compatible_result_and_preserves_intent(self):
        before = self.intent.read_bytes()
        report = self.adopt()
        self.assertEqual(report["status"], "ready")
        self.assertTrue(report["result_created"])
        self.assertEqual(self.intent.read_bytes(), before)
        self.assertEqual(self.result.stat().st_mode & 0o777, 0o600)
        saved = json.loads(self.result.read_text())
        self.assertEqual(saved["schema"], "acfs.swarm-launch.v1")
        self.assertEqual(saved["request"], self.request)
        self.assertEqual([(t["slot"], t["agent_name"], t["pane"]) for t in saved["targets"]],
                         [(1, "Reviewer", "%2"), (2, "Builder", "%3"), (3, "Tester", "%7")])
        self.assertFalse(saved["recovery"]["original_launch_verified"])
        self.assertEqual(saved["recovery"]["review_sha256"], report["review_sha256"])

    def test_pane_output_order_does_not_change_approval(self):
        review = self.preview()
        self.panes.reverse()
        self.save_panes()
        self.assertEqual(review, self.preview())
        self.adopt(review)

    def test_requires_distinct_recovery_approval_before_observation(self):
        self.invoke("--adopt", code=2)
        self.assertEqual((self.root / "commands.jsonl").read_text(), "")
        self.assertFalse(self.result.exists())

    def test_wrong_digest_does_not_publish(self):
        self.adopt("0" * 64, code=2)
        self.assertFalse(self.result.exists())

    def test_approval_binds_pane_process_session_and_server_identities(self):
        review = self.preview()
        for column, value in ((1, "$5"), (2, "1700000001"), (3, "%80"), (4, "1010"), (5, "991")):
            with self.subTest(column=column):
                old = [row.copy() for row in self.panes]
                if column in (1, 2, 5):
                    for row in self.panes:
                        row[column] = value
                else:
                    self.panes[0][column] = value
                self.save_panes()
                self.adopt(review, code=2)
                self.assertFalse(self.result.exists())
                self.panes = old
                self.save_panes()

    def test_approval_binds_original_intent_bytes(self):
        review = self.preview()
        self.intent.write_bytes(self.intent.read_bytes() + b" ")
        self.adopt(review, code=2)
        self.assertFalse(self.result.exists())

    def test_recheck_detects_topology_change_before_publish(self):
        self.adopt(mode="drift", code=2)
        self.assertFalse(self.result.exists())

    def test_intent_replacement_is_not_accepted(self):
        self.adopt(mode="replace-intent", code=2)
        self.assertFalse(self.result.exists())

    def test_intent_edit_during_recovery_is_not_accepted(self):
        self.adopt(mode="rewrite-intent", code=2)
        self.assertFalse(self.result.exists())

    def test_racing_result_is_preserved(self):
        self.adopt(mode="result-race", code=2)
        self.assertEqual(self.result.read_text(), "retained competitor result")

    def test_post_publication_drift_retains_result_and_returns_unconfirmed(self):
        report = self.adopt(mode="post-drift", code=1)
        self.assertEqual(report["status"], "unconfirmed")
        self.assertTrue(report["result_created"])
        self.assertTrue(self.result.is_file())
        before = self.result.read_bytes()
        self.invoke(code=2)
        self.assertEqual(self.result.read_bytes(), before)

    def test_existing_result_is_never_replaced(self):
        self.result.write_text("incomplete result to inspect")
        self.invoke(code=2)
        self.assertEqual(self.result.read_text(), "incomplete result to inspect")
        self.assertEqual((self.root / "commands.jsonl").read_text(), "")

    def test_existing_dangling_result_symlink_is_preserved(self):
        self.result.symlink_to(self.root / "missing")
        self.invoke(code=2)
        self.assertTrue(self.result.is_symlink())
        self.assertFalse((self.root / "missing").exists())

    def test_busy_launch_directory_is_refused(self):
        fd = os.open(self.receipts, os.O_RDONLY | os.O_DIRECTORY)
        self.addCleanup(os.close, fd)
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        self.invoke(code=2)
        self.assertFalse(self.result.exists())

    def test_unknown_or_extra_request_fields_are_rejected(self):
        self.request["force"] = True
        self.save_intent()
        self.invoke(code=2)

    def test_wrong_receipt_path_is_rejected(self):
        self.request["receipt"] = str(self.receipts / "other.json")
        self.save_intent()
        self.invoke(code=2)

    def test_duplicate_keys_and_nonfinite_json_are_rejected(self):
        for raw in ('{"schema":1,"schema":2}', '{"schema":NaN}', '{"schema":"\\ud800"}'):
            with self.subTest(raw=raw):
                self.intent.write_text(raw)
                self.invoke(code=2)

    def test_huge_intent_is_rejected_without_observation(self):
        self.intent.write_bytes(b" " * (1024 * 1024 + 1))
        self.invoke(code=2)
        self.assertEqual((self.root / "commands.jsonl").read_text(), "")

    def test_unprivate_intent_is_rejected(self):
        self.intent.chmod(0o644)
        self.invoke(code=2)

    def test_hardlinked_intent_is_rejected(self):
        os.link(self.intent, self.receipts / "intent-link")
        self.invoke(code=2)

    def test_symlinked_intent_is_rejected(self):
        real = self.receipts / "real-intent"
        self.intent.rename(real)
        self.intent.symlink_to(real)
        self.invoke(code=2)

    def test_nonregular_intent_does_not_block(self):
        self.intent.unlink()
        os.mkfifo(self.intent, 0o600)
        self.invoke(code=2)

    def test_writable_receipt_directory_is_rejected(self):
        self.receipts.chmod(0o777)
        self.invoke(code=2)

    def test_missing_dead_extra_or_shell_panes_are_rejected(self):
        original = [row.copy() for row in self.panes]
        cases = [original[:-1], original + [self.pane("%20", "1020", "codex", "9", "1")]]
        for column, value in ((7, "1"), (8, "bash"), (0, "swarm-other"), (4, "0")):
            changed = [row.copy() for row in original]
            changed[0][column] = value
            cases.append(changed)
        for rows in cases:
            with self.subTest(rows=rows):
                self.panes = rows
                self.save_panes()
                self.invoke(code=2)
                self.assertFalse(self.result.exists())

    def test_duplicate_pane_pid_or_position_is_rejected(self):
        for columns in ((3,), (4,), (9, 10)):
            with self.subTest(columns=columns):
                original = self.panes[0].copy()
                for column in columns:
                    self.panes[0][column] = self.panes[1][column]
                self.save_panes()
                self.invoke(code=2)
                self.panes[0] = original

    def test_native_agent_mix_must_match(self):
        self.panes[1][8] = "codex"
        self.save_panes()
        self.invoke(code=2)

    def test_outside_repo_pane_is_rejected(self):
        self.panes[0][6] = str(self.root)
        self.save_panes()
        self.invoke(code=2)

    def test_subdirectory_pane_is_accepted(self):
        child = self.repo / "src"
        child.mkdir()
        self.panes[0][6] = str(child)
        self.save_panes()
        self.adopt()

    def test_command_failure_is_redacted(self):
        report = self.invoke(mode="error", code=2)
        self.assertNotIn("DO_NOT_LEAK", json.dumps(report))

    def test_oversized_and_invalid_observations_are_rejected(self):
        self.invoke(mode="large", code=2)
        self.invoke(mode="invalid-utf8", code=2)
        self.assertFalse(self.result.exists())

    def test_observation_deadline_is_enforced(self):
        self.invoke("--timeout", "1", mode="timeout", code=2)
        self.assertFalse(self.result.exists())


if __name__ == "__main__":
    unittest.main()
