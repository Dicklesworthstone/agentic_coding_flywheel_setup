#!/usr/bin/env python3
"""Exercise admission through the real Bash/jq CLI; no agents or services run."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PLANNER = ROOT / "scripts/lib/swarm_plan.sh"


def healthy_status():
    return {
        "schema_version": 1, "status": "pass",
        "host": {"status": "pass", "cpu_count": 64, "load_1m": 8,
                 "mem_available_kb": 134217728, "warnings": []},
        "probes": {
            "agent_mail": {"status": "pass", "available": True, "healthy": True},
            "beads": {"status": "pass", "available": True, "ready_count": 12,
                      "in_progress_count": 0},
            "bv": {"status": "pass", "available": True, "robot_ok": True},
            "rch": {"status": "pass", "available": True, "status_json_ok": True,
                    "queue_json_ok": True, "queue_depth": 0, "active_build_count": 0,
                    "workers_total": 8, "workers_healthy": 8, "workers_busy": 0,
                    "workers_offline": 0, "slots_total": 32, "slots_available": 24,
                    "pressure_warning_count": 0, "stale_worker_count": 0},
            "ntm": {"status": "pass", "available": True, "robot_status_ok": True,
                    "tmux_available": True, "tmux_session_count": 2},
        },
    }


def healthy_capacity():
    return {
        "schema_version": 1, "status": "pass",
        "capacity": {"recommended_agent_count": 44, "safe_agent_count": 64,
                     "max_agent_count": 80},
        "profile_check": {"status": "pass"}, "recommendations": [],
    }


@unittest.skipUnless(shutil.which("bash") and shutil.which("jq"), "requires Bash and jq")
class SwarmAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="acfs-admission-")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.status = healthy_status()
        self.capacity = healthy_capacity()

    def run_plan(self, agents=10, human=False, profile="balanced"):
        status_file = self.directory / "status.json"
        status_file.write_text(json.dumps(self.status), encoding="utf-8")
        capacity_file = self.directory / "capacity.json"
        capacity_file.write_text(json.dumps(self.capacity), encoding="utf-8")
        collector = self.directory / "capacity.sh"
        collector.write_text('#!/bin/bash\ncat -- "$ACFS_TEST_CAPACITY_FILE"\n', encoding="utf-8")
        env = dict(os.environ, ACFS_SWARM_CAPACITY_SCRIPT=str(collector),
                   ACFS_TEST_CAPACITY_FILE=str(capacity_file))
        result = subprocess.run(
            ["bash", str(PLANNER), "--status-file", str(status_file), "--agents", str(agents),
             "--profile", profile] + ([] if human else ["--json"]),
            env=env, capture_output=True, text=True, timeout=15, check=False,
        )
        self.assertEqual(result.stderr, "", result.stderr)
        if human:
            return result.returncode, result.stdout
        report = json.loads(result.stdout)
        self.assertEqual(result.returncode, report["exit_code"])
        self.assertTrue(report["safety"]["read_only"])
        self.assertFalse(report["safety"]["launches_agents"])
        return result.returncode, report

    def assert_wait(self, report):
        self.assertEqual(report["quiesce_advisory"]["recommendation"], "wait")
        self.assertFalse(report["launch_profile"]["recommended"])
        for field in ("command", "agent_count", "label", "mix"):
            self.assertIsNone(report["launch_profile"][field], field)
        self.assertIsNone(report["recommended_agents"])
        self.assertIsNone(report["quiesce_advisory"]["recommended_agents"])
        self.assertIn(report["recommendation"], ("block", "defer_or_reduce"))
        self.assertTrue(report["quiesce_advisory"]["reasons"])
        for example in report["examples"]:
            self.assertNotIn(example["recommendation"], ("launch", "launch_with_review"))

    def test_healthy_launch_and_mix(self):
        for profile in ("balanced", "codex-heavy", "review-heavy", "docs-heavy"):
            with self.subTest(profile=profile):
                code, report = self.run_plan(profile=profile)
                self.assertEqual(code, 0)
                self.assertEqual(report["recommendation"], "launch")
                self.assertEqual(report["launch_profile"]["agent_count"], 10)
                self.assertEqual(sum(report["launch_profile"]["mix"].values()), 10)
                self.assertTrue(report["launch_profile"]["not_executed"])

    def test_high_load_waits_without_command(self):
        self.status["host"]["load_1m"] = 80
        code, report = self.run_plan()
        self.assertEqual(code, 1)
        self.assert_wait(report)

    def test_low_and_zero_memory_wait(self):
        for available in (2097152, 0):
            with self.subTest(available=available):
                self.status["host"]["mem_available_kb"] = available
                code, report = self.run_plan()
                self.assertEqual(code, 1)
                self.assert_wait(report)

    def test_stale_work_waits(self):
        self.status["probes"]["beads"]["stale_in_progress_count"] = 1
        code, report = self.run_plan()
        self.assertEqual(code, 1)
        self.assert_wait(report)

    def test_explicit_zero_safe_capacity_never_falls_back_to_maximum(self):
        self.capacity["capacity"]["safe_agent_count"] = 0
        code, report = self.run_plan()
        self.assertEqual(code, 2)
        self.assert_wait(report)

    def test_missing_safe_capacity_uses_legacy_maximum(self):
        del self.capacity["capacity"]["safe_agent_count"]
        code, report = self.run_plan()
        self.assertEqual(code, 0)
        self.assertEqual(report["safe_agents"], 80)

    def test_zero_recommended_capacity_waits(self):
        self.capacity["capacity"]["recommended_agent_count"] = 0
        code, report = self.run_plan()
        self.assertEqual(code, 1)
        self.assert_wait(report)

    def test_capacity_failure_cannot_be_overridden_by_profile_pass(self):
        self.capacity["status"] = "fail"
        code, report = self.run_plan()
        self.assertEqual(code, 2)
        self.assert_wait(report)

    def test_capacity_warning_survives_profile_pass(self):
        self.capacity["status"] = "warn"
        code, report = self.run_plan()
        self.assertEqual(code, 1)
        self.assertEqual(report["recommendation"], "launch_with_review")

    def test_busy_rch_scales_down_to_free_slots(self):
        self.status["probes"]["rch"].update(queue_depth=7, slots_available=4)
        code, report = self.run_plan()
        self.assertEqual(code, 1)
        self.assertEqual(report["launch_profile"]["agent_count"], 4)
        self.assertEqual(report["quiesce_advisory"]["recommendation"], "scale_down")

    def test_rch_slots_cannot_raise_host_recommendation(self):
        self.capacity["capacity"]["recommended_agent_count"] = 3
        self.status["probes"]["rch"].update(queue_depth=1, slots_available=8)
        code, report = self.run_plan()
        self.assertEqual(code, 1)
        self.assertEqual(report["recommended_agents"], 3)
        self.assertEqual(report["launch_profile"]["agent_count"], 3)

    def test_zero_slots_wait_even_without_reported_queue(self):
        for queued in (0, 3):
            with self.subTest(queued=queued):
                self.status["probes"]["rch"].update(queue_depth=queued, slots_available=0)
                code, report = self.run_plan()
                self.assertEqual(code, 1)
                self.assert_wait(report)

    def test_failed_queue_probe_waits(self):
        self.status["probes"]["rch"]["queue_json_ok"] = False
        code, report = self.run_plan()
        self.assertEqual(code, 1)
        self.assert_wait(report)

    def test_stale_worker_telemetry_waits(self):
        self.status["probes"]["rch"]["stale_worker_count"] = 1
        code, report = self.run_plan()
        self.assertEqual(code, 1)
        self.assert_wait(report)

    def test_hard_coordination_block(self):
        self.status["probes"]["agent_mail"]["available"] = False
        code, report = self.run_plan()
        self.assertEqual(code, 2)
        self.assert_wait(report)

    def test_waiting_human_output_has_no_spawn(self):
        self.status["host"]["load_1m"] = 100
        code, text = self.run_plan(human=True)
        self.assertEqual(code, 1)
        self.assertIn("Wait before launching", text)
        self.assertNotIn("ntm spawn", text)
        self.assertNotIn("Launch command", text)


if __name__ == "__main__":
    unittest.main()
