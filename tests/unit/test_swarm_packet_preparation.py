"""Exercise preparation, full task prompts and dispatch through the real CLI."""
import copy
import hashlib
import json
import os
from pathlib import Path
import shlex
import stat
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/lib/swarm_packet.sh"

TOOLS = r'''#!/usr/bin/env python3
import hashlib, json, os, pathlib, sys
root = pathlib.Path(os.environ["PREPARATION_TEST_ROOT"])
args = sys.argv[1:]
name = pathlib.Path(sys.argv[0]).name
with (root / "calls.jsonl").open("a") as stream:
    stream.write(json.dumps([name, args]) + "\n")
beads = json.loads((root / "beads.json").read_text())
if name == "br":
    if args == ["ready", "--json"]:
        print(json.dumps(beads))
    else:
        assert args[0] == "show" and args[2:] == ["--json"], args
        print(json.dumps([b for b in beads if b["id"] == args[1]]))
    sys.exit(0)
if name == "tmux":
    assert args[:3] == ["display-message", "-p", "-t"], args
    pane = args[3]
    assert pane in ("%42", "%43"), pane
    print("project\t" + pane + "\t" + str(root / "repo") + "\t0\t" + ("claude" if pane == "%42" else "codex"))
    sys.exit(0)
assert name == "ntm", name
if args[0].startswith("--robot-send-receipt="):
    op = args[0].split("=", 1)[1]
    data = json.loads((root / (op + ".json")).read_text())
    print(json.dumps({"success": True, "session": "project", "operation": data["operation"], "outcome": data}))
    sys.exit(0)
assert "--robot-send=project" in args and "--msg-file=-" in args, args
pane = next(a.split("=", 1)[1] for a in args if a.startswith("--panes="))
assert "--type=" + ("claude" if pane == "%42" else "codex") in args, args
payload = sys.stdin.buffer.read()
assert b"Acceptance criteria" in payload and b"Declared Write Scope" in payload
assert (b"bd-api" if pane == "%42" else b"bd-doc") in payload
if "--dry-run" in args:
    print(json.dumps({"success": True, "session": "project", "dry_run": True, "blocked": False,
                      "successful": [], "failed": [], "would_send_to": [pane]}))
    sys.exit(0)
op = next(a.split("=", 1)[1] for a in args if a.startswith("--op-id="))
data = {"success": True, "session": "project", "targets": [pane], "successful": [pane], "failed": [],
        "operation": {"operation_id": op, "status": "completed", "payload_sha256": hashlib.sha256(payload).hexdigest(),
                      "payload_bytes": len(payload), "admissions": [{"target": pane, "state": "submitted"}]}}
(root / (op + ".json")).write_text(json.dumps(data))
(root / (pane[1:] + ".prompt")).write_bytes(payload)
print(json.dumps(data))
'''


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="acfs-prepare-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        (self.repo / "AGENTS.md").write_text("Read current code. Protect user work.\n")
        (self.repo / "README.md").write_text("The project.\n")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("br", "tmux", "ntm", "cm", "cass"):
            path = self.bin / name
            path.write_text(TOOLS)
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        PREPARATION_TEST_ROOT=str(self.root))
        self.output = self.root / "prepared work"
        self.assignments = {"schema_version": 1, "status": "pass", "advisory_only": True,
            "scope_admission": {"mode": "explicit-scopes", "status": "pass"},
            "assignments": [
                {"slot": 1, "agent": "agent-1", "role": "implementation", "bead_id": "bd-api",
                 "title": "Old API title", "scope_source": "explicit", "issue_type": "feature",
                 "reservation_surfaces": ["src/api/**", "tests/api/**"], "dependency_position": {"blocked_by": []}},
                {"slot": 3, "agent": "agent-3", "role": "documentation", "bead_id": "bd-doc",
                 "title": "Documentation", "scope_source": "explicit", "issue_type": "task",
                 "reservation_surfaces": ["docs/**"], "dependency_position": {"blocked_by": []}}],
            "idle_agents": [{"slot": 2, "reason": "no-independent-ready-bead"}]}
        self.beads = [{"id": "bd-api", "title": "Implement endpoint", "status": "open", "priority": 1,
                       "description": "Implement a useful API. Literal $(touch should-not-exist).",
                       "design": "Use the current router.", "acceptance_criteria": "GET returns status 200.", "labels": ["api"]},
                      {"id": "bd-doc", "title": "Document endpoint", "status": "open", "priority": 2,
                       "description": "Explain the endpoint.", "design": "Add working examples.",
                       "acceptance_criteria": "The example matches the public API.", "labels": ["docs"]}]
        self.assignment_path = self.root / "assignments.json"
        self.bead_path = self.root / "beads.json"
        self.write_inputs()

    def write_inputs(self):
        self.assignment_path.write_text(json.dumps(self.assignments))
        self.bead_path.write_text(json.dumps(self.beads))

    def calls(self):
        path = self.root / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def invoke(self, offline=True, targets=None, extra=()):
        args = ["bash", str(SCRIPT), "--prepare-batch", str(self.output), "--repo", str(self.repo),
                "--session", "project", "--assignments", str(self.assignment_path), "--no-live-context"]
        for target in targets or ["3:BlueLake:codex:%43", "1:RedFox:claude:%42"]:
            args += ["--target", target]
        if offline:
            args += ["--beads-file", str(self.bead_path)]
        result = subprocess.run(args + list(extra), env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.stderr, "", result.stderr)
        return result.returncode, json.loads(result.stdout)

    def packet(self, slot):
        return json.loads((self.output / f"packet-{slot:02}.json").read_text())

    def test_offline_prepares_complete_private_packets_without_tools(self):
        code, report = self.invoke()
        self.assertEqual(code, 0, report)
        self.assertEqual(report["status"], "prepared")
        self.assertEqual(report["delivery_count"], 2)
        self.assertEqual(report["idle_agents"], self.assignments["idle_agents"])
        self.assertEqual(self.calls(), [])
        self.assertFalse(report["sends_prompt"])
        self.assertNotIn("send_command", report)
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o700)
        for path in self.output.iterdir():
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertFalse(list(self.output.glob("*.receipt.json")))
        for slot, bead in zip((1, 3), self.beads):
            packet = self.packet(slot)
            prompt = packet["packet_markdown"]
            for key in ("description", "design", "acceptance_criteria"):
                self.assertIn(bead[key], prompt)
            self.assertEqual(packet["output"]["char_count"], len(prompt))
            self.assertFalse(packet["output"]["truncated"])
            self.assertIn("stop and renegotiate", prompt)
            self.assertEqual((self.output / f"packet-{slot:02}.md").read_text(), prompt)
            self.assertEqual(packet["bead"]["source"], bead)
        self.assertFalse((self.repo / "should-not-exist").exists())

    def test_slots_map_exactly_despite_reversed_targets_and_idle_hole(self):
        code, report = self.invoke()
        self.assertEqual(code, 0, report)
        batch = json.loads((self.output / "batch.json").read_text())
        self.assertEqual([d["pane"] for d in batch["deliveries"]], ["%42", "%43"])
        self.assertEqual([d["agent_type"] for d in batch["deliveries"]], ["claude", "codex"])
        self.assertEqual([self.packet(s)["agent"]["name"] for s in (1, 3)], ["RedFox", "BlueLake"])
        self.assertEqual([d["packet"] for d in batch["deliveries"]], ["packet-01.json", "packet-03.json"])

    def test_live_reads_selected_beads_and_does_not_send(self):
        code, report = self.invoke(offline=False)
        self.assertEqual(code, 0, report)
        self.assertEqual(self.calls(), [["br", ["show", "bd-api", "--json"]], ["br", ["show", "bd-doc", "--json"]]])
        self.assertEqual(self.packet(1)["bead"]["title"], "Implement endpoint")

    def test_prepared_batch_dispatches_and_reconciles_without_resends(self):
        code, report = self.invoke()
        self.assertEqual(code, 0, report)
        command = shlex.split(report["preview_command"])
        preview = subprocess.run(["bash", str(SCRIPT), *command[3:]], env=self.env,
                                 capture_output=True, text=True, timeout=30)
        self.assertEqual(preview.returncode, 0, preview.stderr + preview.stdout)
        self.assertEqual(self.calls(), [])
        args = shlex.split(json.loads(preview.stdout)["send_command"])
        for attempt in (0, 1):
            sent = subprocess.run(["bash", str(SCRIPT), *args[3:]], env=self.env,
                                  capture_output=True, text=True, timeout=30)
            self.assertEqual(sent.returncode, 0, sent.stderr + sent.stdout)
            result = json.loads(sent.stdout)
            self.assertEqual(result["summary"]["submitted"], 2)
            self.assertEqual(result["summary"]["reconciled"], attempt * 2)
        sends = [args for name, args in self.calls()
                 if name == "ntm" and "--robot-send=project" in args and "--dry-run" not in args]
        self.assertEqual(len(sends), 2)
        for slot, pane in ((1, "42"), (3, "43")):
            self.assertEqual((self.root / (pane + ".prompt")).read_text(), self.packet(slot)["packet_markdown"])

    def test_overlapping_or_inferred_scopes_are_not_trusted(self):
        self.assignments["assignments"][1]["reservation_surfaces"] = ["src/api/routes.py"]
        self.write_inputs()
        code, report = self.invoke()
        self.assertEqual(code, 2)
        self.assertIn("overlap", report["error"])
        self.assertFalse(self.output.exists())
        self.assignments["scope_admission"]["mode"] = "inferred-unchecked"
        self.write_inputs()
        self.assertEqual(self.invoke()[0], 2)
        self.assertEqual(self.calls(), [])

    def test_unusable_targets_do_not_create_bundle(self):
        cases = [["1:RedFox:claude:%42"], ["1:RedFox:claude:%42", "3:BlueLake:codex:%42"],
                 ["1:RedFox:claude:%42", "3:RedFox:codex:%43"],
                 ["1:RedFox:bash:%42", "3:BlueLake:codex:%43"],
                 ["1:RedFox:claude:1", "3:BlueLake:codex:%43"]]
        for targets in cases:
            with self.subTest(targets=targets):
                self.assertEqual(self.invoke(targets=targets)[0], 2)
                self.assertFalse(self.output.exists())
        self.assertEqual(self.calls(), [])

    def test_missing_or_changed_later_bead_prevents_all_publication(self):
        original = copy.deepcopy(self.beads)
        for mutation in ({"id": "bd-other"}, {"status": "closed"}, {"blocked": True},
                         {"blocked_by": ["bd-first"]}, {"issue_type": "epic"}, {"description": []}):
            with self.subTest(mutation=mutation):
                self.beads = copy.deepcopy(original)
                self.beads[1].update(mutation)
                self.write_inputs()
                self.assertEqual(self.invoke()[0], 2)
                self.assertFalse(self.output.exists())

    def test_large_brief_blocks_instead_of_truncating_requirements(self):
        self.beads[1]["description"] = "x" * 65000
        self.write_inputs()
        code, report = self.invoke()
        self.assertEqual(code, 2, report)
        self.assertFalse(self.output.exists())

    def test_existing_directory_and_files_are_preserved(self):
        self.output.mkdir()
        keep = self.output / "batch.json"
        keep.write_text("important work")
        self.assertEqual(self.invoke()[0], 2)
        self.assertEqual(keep.read_text(), "important work")
        self.assertEqual(self.calls(), [])

    def test_symlink_input_or_output_parent_is_refused(self):
        linked = self.root / "linked"
        linked.symlink_to(self.repo, target_is_directory=True)
        self.output = linked / "bundle"
        self.assertEqual(self.invoke()[0], 2)
        self.assertFalse((self.repo / "bundle").exists())
        self.output = self.root / "new-output"
        self.assertEqual(self.invoke(extra=("--assignments", str(linked / "AGENTS.md")))[0], 2)

    def test_duplicate_json_keys_and_duplicate_beads_are_refused(self):
        self.assignment_path.write_text('{"schema_version":0,' + json.dumps(self.assignments)[1:])
        self.assertEqual(self.invoke()[0], 2)
        self.write_inputs()
        self.beads.append(self.beads[0])
        self.write_inputs()
        self.assertEqual(self.invoke()[0], 2)
        self.assertFalse(self.output.exists())

    def test_task_can_be_selected_from_full_beads_list(self):
        result = subprocess.run(["bash", str(SCRIPT), "--bead", "bd-doc", "--bead-file", str(self.bead_path),
            "--repo", str(self.repo), "--no-live-context", "--json"], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        packet = json.loads(result.stdout)
        self.assertEqual(packet["bead"]["id"], "bd-doc")
        self.assertIn("The example matches", packet["packet_markdown"])
        self.assertNotIn("GET returns", packet["packet_markdown"])

    def test_unselected_multibead_file_is_not_silently_first(self):
        result = subprocess.run(["bash", str(SCRIPT), "--bead-file", str(self.bead_path),
            "--repo", str(self.repo), "--no-live-context", "--json"], capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_secret_shaped_brief_text_is_sanitized_in_prompt(self):
        self.beads[0]["description"] += "\nAuthorization: Bearer top-secret\n"
        self.write_inputs()
        code, report = self.invoke()
        self.assertEqual(code, 0, report)
        self.assertNotIn("top-secret", self.packet(1)["packet_markdown"])
        self.assertIn("credential redacted", self.packet(1)["packet_markdown"])


if __name__ == "__main__":
    unittest.main()
