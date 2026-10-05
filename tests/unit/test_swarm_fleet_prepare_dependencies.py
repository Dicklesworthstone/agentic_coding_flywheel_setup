#!/usr/bin/env python3
"""Scheduling checks against the real current fleet preparation entrypoint."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/swarm-fleet-prepare.py"
loader = importlib.util.spec_from_file_location("current_fleet_prepare", SCRIPT)
prepare = importlib.util.module_from_spec(loader)
loader.loader.exec_module(prepare)
fleet = prepare.fleet


class Fixture:
    """Real private launch journals and native-format packet bundles, retained."""
    def __init__(self):
        self.root = Path(tempfile.mkdtemp(prefix="acfs-prepare-recovery-"))
        self.launch_dir = self.root / "launch"
        self.state = self.root / "preparation"
        hosts = []
        for i in range(3):
            hosts.append({"id": f"worker-{i}", "host": f"worker-{i}.example.com", "user": "ubuntu", "port": 22,
                "request": {"repo": "/projects/app", "session": "wave", "receipt": "/receipts/wave.json",
                    "profile": "balanced", "workload": "standard", "accept_warnings": False,
                    "agents": [{"agent_name": f"Agent{i}Idle", "agent_type": "claude"},
                               {"agent_name": f"Agent{i}Work", "agent_type": "codex"}]}})
        self.launch = fleet.build_plan({"schema": fleet.SPEC_SCHEMA, "hosts": hosts},
                                      b"known hosts", b"private identity", self.launch_dir, 360)
        self.launch_dir.mkdir(mode=0o700)
        with fleet.directory_fd(self.launch_dir, private=True) as fd:
            fleet.publish(fd, "intent.json", {"schema": fleet.STATE_SCHEMA, "plan": self.launch})
            for host in hosts:
                intent = fleet.host_intent(self.launch, host)
                targets = [{"slot": s, **a, "pane": "%" + str(s), "pane_pid": str(100 + s),
                    "server_pid": "500", "session_id": "$1", "session_created": "1700000000"}
                    for s, a in enumerate(host["request"]["agents"], 1)]
                fleet.publish(fd, host["id"] + ".attempt.json", intent)
                fleet.publish(fd, host["id"] + ".result.json", {**intent, "targets": targets})
        self.work = {"schema": prepare.WORK_SCHEMA, "hosts": [{"id": h["id"],
            "output": str(self.root / (h["id"] + "-bundle")),
            "identities": [{"slot": s, "name": a["agent_name"]}
                           for s, a in enumerate(h["request"]["agents"], 1)]} for h in hosts],
            "assignments": [{"host_id": h["id"], "slot": 2, "bead_id": f"bd-{i}",
                "role": "implementation", "write_scopes": [f"src/part-{i}/**"]} for i, h in enumerate(hosts)],
            "beads": [{"id": f"bd-{i}", "status": "open", "title": f"Task {i}",
                "issue_type": "task", "description": "private fixture task", "dependencies": []} for i in range(3)]}
        self.peer = {"fleet": fleet}
        exec(compile(prepare.PEER_CODE, "<fixed-peer>", "exec"), self.peer)
        self.calls = []

    def plan(self):
        with prepare.launch_context(self.launch_dir, b"known hosts", b"private identity") as (launch, history, records, _):
            return prepare.build_plan(self.work, launch, history, records, self.state, 5)

    def private(self, path, value):
        path.write_bytes(fleet.encoded(value))
        path.chmod(0o600)

    def bundle(self, entry):
        root = Path(entry["output"])
        root.mkdir(mode=0o700)
        bundle = root / "bundle"
        bundle.mkdir(mode=0o700)
        for name, value in (("request.json", entry), ("assignments.json", entry["assignments"]), ("beads.json", entry["beads"])):
            self.private(root / name, value)
        self.private(bundle / "assignments.json", entry["assignments"])
        deliveries = []
        for item in entry["assignments"]["assignments"]:
            name = f'packet-{item["slot"]:02d}'
            target = entry["targets"][item["slot"] - 1]
            req = entry["host"]["request"]
            text = "# ACFS Swarm Startup Packet\n" + item["bead_id"]
            packet = {"schema_version": 1, "status": "pass", "bead": {"id": item["bead_id"]},
                "repository": {"path": req["repo"]}, "output": {"truncated": False}, "packet_markdown": text,
                "preparation": {"slot": item["slot"], "assignment_sha256": fleet.digest(fleet.encoded(entry["assignments"])),
                    "declared_write_scopes": item["reservation_surfaces"], "reservations_acquired": False, "bead_source": "file"}}
            self.private(bundle / (name + ".json"), packet)
            (bundle / (name + ".md")).write_text(text)
            (bundle / (name + ".md")).chmod(0o600)
            deliveries.append({"packet": name + ".json", "receipt": name + ".receipt.json", "repo": req["repo"],
                "session": req["session"], "pane": target["pane"], "agent_type": target["agent_type"],
                "operation_id": "operation-" + item["bead_id"]})
        self.private(bundle / "batch.json", {"schema": "acfs.packet-delivery-batch.v1", "deliveries": deliveries})
        result = self.peer["bundle_snapshot"](entry)
        self.private(root / "complete.json", result)
        return result

    def invoke(self, entry, mode):
        self.calls.append((entry["host"]["id"], mode))
        if mode == "check":
            result = {"schema": prepare.PEER_SCHEMA, "status": "available", "entry_sha256": fleet.digest(fleet.encoded(entry)),
                      "starts_agents": False, "sends_prompt": False}
        elif mode == "prepare":
            result = self.bundle(entry)
        elif mode == "inspect":
            result = self.peer["inspect_preparation"](entry)
        else:
            raise AssertionError("unexpected operation " + mode)
        return 0, fleet.encoded(result)

    def cli_args(self):
        for name, value in (("work.json", self.work),):
            self.private(self.root / name, value)
        for name, raw in (("known", b"known hosts"), ("key", b"private identity")):
            (self.root / name).write_bytes(raw)
            (self.root / name).chmod(0o600)
        return [sys.executable, "-I", str(SCRIPT), "--launch-state", str(self.launch_dir), "--work", str(self.root / "work.json"),
            "--known-hosts", str(self.root / "known"), "--identity-file", str(self.root / "key"), "--state-dir", str(self.state),
            "--timeout", "5"]


class DependencyTests(unittest.TestCase):
    def setUp(self):
        self.f = Fixture()

    def edge(self, source, target):
        source["dependencies"] = [{"depends_on_id": target, "type": "blocks"}]

    def test_independent_tasks_and_original_idle_slot_holes_remain_valid(self):
        plan = self.f.plan()
        self.assertEqual([e["assignments"]["assignments"][0]["slot"] for e in plan["hosts"]], [2, 2, 2])
        self.assertEqual(len(plan["hosts"]), 3)

    def test_direct_cross_host_prerequisite_is_not_an_independent_wave(self):
        self.edge(self.f.work["beads"][0], "bd-1")
        with self.assertRaisesRegex(fleet.Refused, "unfinished_work_prerequisite"):
            self.f.plan()
        self.assertFalse(self.f.state.exists())

    def test_missing_dependency_is_not_implicitly_satisfied(self):
        self.edge(self.f.work["beads"][0], "bd-missing")
        with self.assertRaisesRegex(fleet.Refused, "incomplete_work_dependency_snapshot"):
            self.f.plan()

    def test_closed_blocking_closure_is_accepted(self):
        self.edge(self.f.work["beads"][0], "bd-base")
        self.f.work["beads"].append({"id": "bd-base", "status": "closed", "dependencies": []})
        self.f.plan()

    def test_transitive_unfinished_prerequisite_is_refused(self):
        self.edge(self.f.work["beads"][0], "bd-base")
        base = {"id": "bd-base", "status": "closed"}
        self.edge(base, "bd-1")
        self.f.work["beads"].append(base)
        with self.assertRaisesRegex(fleet.Refused, "unfinished_work_prerequisite"):
            self.f.plan()

    def test_cycle_among_closed_prerequisites_is_not_hidden(self):
        self.edge(self.f.work["beads"][0], "bd-base")
        base = {"id": "bd-base", "status": "closed"}
        self.edge(base, "bd-base")
        self.f.work["beads"].append(base)
        with self.assertRaisesRegex(fleet.Refused, "cyclic_work_dependencies"):
            self.f.plan()

    def test_nonblocking_relation_and_unrelated_metadata_do_not_block(self):
        self.f.work["beads"][0]["dependencies"] = [{"depends_on_id": "bd-not-in-snapshot", "type": "related"}]
        self.f.work["beads"].append({"id": "bd-other", "dependencies": "unrelated metadata"})
        self.f.plan()

    def test_malformed_dependency_types_are_not_ignored(self):
        for deps in (None, "bd-x", [{"type": "blocks"}], [{"type": True, "depends_on_id": "bd-x"}]):
            self.f.work["beads"][0]["dependencies"] = deps
            with self.assertRaises(fleet.Refused): self.f.plan()

    def test_real_cli_rejects_dependency_conflict_before_transport(self):
        self.edge(self.f.work["beads"][0], "bd-1")
        result = subprocess.run(self.f.cli_args(), capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertIn("unfinished_work_prerequisite", result.stdout)
        self.assertNotIn("private fixture task", result.stdout)
        self.assertFalse(self.f.state.exists())


if __name__ == "__main__": unittest.main()
