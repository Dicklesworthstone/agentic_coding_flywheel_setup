#!/usr/bin/env python3
"""Paired replay, telemetry validation and large-input CLI regression tests."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from test_swarm_plan_admission import PLANNER, healthy_capacity, healthy_status


@unittest.skipUnless(shutil.which("bash") and shutil.which("jq"), "requires Bash and jq")
class SwarmSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="acfs-snapshot-")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.status = healthy_status()
        self.capacity = healthy_capacity()
        self.status_path = self.directory / "status.json"
        self.capacity_path = self.directory / "capacity.json"
        self.marker = self.directory / "probe-was-run"
        collector = self.directory / "forbidden-probe.sh"
        collector.write_text('printf called > "$ACFS_TEST_PROBE_MARKER"\nexit 90\n', encoding="utf-8")
        self.env = dict(os.environ, ACFS_SWARM_STATUS_SCRIPT=str(collector),
                        ACFS_SWARM_CAPACITY_SCRIPT=str(collector),
                        ACFS_TEST_PROBE_MARKER=str(self.marker))

    def run_plan(self, status_raw=None, capacity_raw=None, extra=(), human=False):
        self.status_path.write_text(json.dumps(self.status) if status_raw is None else status_raw,
                                    encoding="utf-8")
        self.capacity_path.write_text(json.dumps(self.capacity) if capacity_raw is None else capacity_raw,
                                      encoding="utf-8")
        result = subprocess.run(
            ["bash", str(PLANNER), "--agents", "10", "--status-file", str(self.status_path),
             "--capacity-file", str(self.capacity_path)] + ([] if human else ["--json"]) + list(extra),
            capture_output=True, text=True, env=self.env, timeout=15, check=False,
        )
        self.assertFalse(self.marker.exists(), "replay must not invoke either live collector")
        return result

    def assert_blocked(self, result):
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")
        report = json.loads(result.stdout)
        self.assertEqual(report["exit_code"], 2)
        self.assertEqual(report["recommendation"], "block")
        self.assertFalse(report["launch_profile"]["recommended"])
        self.assertIsNone(report["launch_profile"]["command"])
        self.assertEqual(report["quiesce_advisory"]["recommendation"], "wait")
        return report

    def assert_wait(self, result):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")
        report = json.loads(result.stdout)
        self.assertEqual(report["quiesce_advisory"]["recommendation"], "wait")
        self.assertFalse(report["launch_profile"]["recommended"])
        self.assertIsNone(report["launch_profile"]["command"])

    def test_replay_runs_no_live_probes_and_identifies_sources(self):
        result = self.run_plan()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["inputs"]["assessment_scope"], "snapshot_replay")
        self.assertTrue(report["inputs"]["replay_only"])
        self.assertFalse(report["inputs"]["snapshot_freshness_verified"])
        self.assertEqual(report["inputs"]["capacity_file"], str(self.capacity_path))
        self.assertEqual(report["inputs"]["swarm_status_file"], str(self.status_path))

    def test_replay_human_output_discloses_limitations(self):
        result = self.run_plan(human=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn("saved snapshot replay (no probes run", result.stdout)
        self.assertIn("freshness and host identity are not verified", result.stdout)

    def test_count_metadata_must_match(self):
        self.capacity["profile_check"]["requested_agents"] = 25
        self.assert_blocked(self.run_plan())

    def test_matching_producer_metadata_is_accepted(self):
        self.capacity["profile_check"].update(requested_agents=10, requested_profile="10-agents")
        self.capacity["assumptions"] = {"workload": "standard"}
        self.assertEqual(self.run_plan().returncode, 0)

    def test_workload_metadata_must_match(self):
        self.capacity["assumptions"] = {"workload": "heavy"}
        self.assert_blocked(self.run_plan())

    def test_missing_host_measurements_wait(self):
        for key in ("cpu_count", "load_1m", "mem_available_kb"):
            with self.subTest(key=key):
                self.status = healthy_status()
                del self.status["host"][key]
                self.assert_wait(self.run_plan())

    def test_null_host_measurements_wait(self):
        for key in ("cpu_count", "load_1m", "mem_available_kb"):
            with self.subTest(key=key):
                self.status = healthy_status()
                self.status["host"][key] = None
                self.assert_wait(self.run_plan())

    def test_missing_rch_counters_wait(self):
        for key in ("queue_depth", "active_build_count", "slots_available", "workers_total", "workers_healthy"):
            with self.subTest(key=key):
                self.status = healthy_status()
                del self.status["probes"]["rch"][key]
                result = self.run_plan()
                if key in ("workers_total", "workers_healthy"):
                    self.assert_blocked(result)
                else:
                    self.assert_wait(result)

    def test_unknown_rch_state_waits(self):
        self.status["probes"]["rch"]["status"] = "unknown"
        self.assert_wait(self.run_plan())

    def test_source_failure_cannot_be_masked_by_healthy_subprobes(self):
        for target in (self.status, self.status["host"], self.status["probes"]["rch"]):
            target["status"] = "fail"
            self.assert_blocked(self.run_plan())
            target["status"] = "pass"

    def test_duplicate_decoded_keys_are_rejected(self):
        source = json.dumps(self.status)
        for duplicate in ('"status":"fail",', '"\\u0073tatus":"fail",'):
            with self.subTest(duplicate=duplicate):
                self.assert_blocked(self.run_plan(status_raw="{" + duplicate + source[1:]))

    def test_duplicate_container_and_scalar_replacements_are_rejected(self):
        source = json.dumps(self.status)
        for duplicate in ('"host":0,', '"host":{},', '"host":{"cpu_count":0},'):
            with self.subTest(duplicate=duplicate):
                self.assert_blocked(self.run_plan(status_raw="{" + duplicate + source[1:]))

    def test_nested_duplicate_capacity_cannot_hide_zero(self):
        source = json.dumps(self.capacity).replace('"safe_agent_count": 64',
            '"safe_agent_count":0,"safe_agent_count":64')
        self.assert_blocked(self.run_plan(capacity_raw=source))

    def test_malformed_scalar_array_and_multiple_roots_are_blocked(self):
        for source in ("", "{", "null", "[]", "true", "{} {}", json.dumps(self.status) + "\n{}"):
            with self.subTest(source=source[:32]):
                self.assert_blocked(self.run_plan(status_raw=source))

    def test_unknown_schema_is_blocked(self):
        self.status["schema_version"] = 2
        self.assert_blocked(self.run_plan())

    def test_invalid_numeric_and_boolean_fields_are_blocked(self):
        for invalid in (True, -1, 1.5, "oops", 1e30, {}, []):
            with self.subTest(invalid=invalid):
                self.capacity["capacity"]["safe_agent_count"] = invalid
                self.assert_blocked(self.run_plan())
        self.capacity = healthy_capacity()
        self.status["probes"]["rch"]["queue_json_ok"] = "true"
        self.assert_blocked(self.run_plan())

    def test_negative_load_does_not_look_idle(self):
        self.status["host"]["load_1m"] = -0.1
        self.assert_blocked(self.run_plan())

    def test_decimal_count_input_is_normalized(self):
        result = self.run_plan(extra=("--agents", "00008"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)["requested_agents"], 8)

    def test_count_overflow_and_shell_expressions_are_rejected(self):
        for invalid in ("0", "000", "1000001", "9223372036854775809", "1e2", "1+1", "$(touch nope)"):
            with self.subTest(invalid=invalid):
                result = self.run_plan(extra=("--agents", invalid))
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")
                self.assertIn("--agents", result.stderr)

    def test_reports_larger_than_os_argument_limit_work(self):
        self.status["ignored_diagnostic"] = "x" * (256 * 1024)
        result = self.run_plan()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)["launch_profile"]["agent_count"], 10)

    def test_oversized_input_and_trailing_whitespace_are_rejected(self):
        source = json.dumps(self.status)
        for oversized in (source + " " * (1024 * 1024), source + "\n" * (1024 * 1024)):
            with self.subTest(trailing=repr(oversized[-1])):
                self.assert_blocked(self.run_plan(status_raw=oversized))

    def test_nul_cannot_be_silently_removed_to_turn_failure_into_pass(self):
        source = json.dumps(self.status).replace('"status": "pass"', '"status": "p\0ass"', 1)
        self.assert_blocked(self.run_plan(status_raw=source))

    def test_excessive_nesting_is_rejected(self):
        self.status["ignored_diagnostic"] = json.loads("[" * 40 + "0" + "]" * 40)
        self.assert_blocked(self.run_plan())

    def test_valid_arrays_and_escaped_strings_do_not_look_duplicated(self):
        self.status["ignored_diagnostic"] = [{"x": 1}, {"x": 2}, [], {}, "\"\\\n\u0000", [1, 2]]
        self.assertEqual(self.run_plan().returncode, 0)

    def test_capacity_file_requires_saved_status(self):
        result = subprocess.run(["bash", str(PLANNER), "--agents", "10", "--capacity-file", "missing"],
            capture_output=True, text=True, env=self.env, timeout=15, check=False)
        self.assertEqual(result.returncode, 2)
        self.assertIn("requires --status-file", result.stderr)
        self.assertFalse(self.marker.exists())

    def test_missing_file_returns_one_structured_failure(self):
        self.assert_blocked(self.run_plan(extra=("--capacity-file", str(self.directory / "missing"))))


if __name__ == "__main__":
    unittest.main()
