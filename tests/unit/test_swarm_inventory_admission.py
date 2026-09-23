"""Exercise fleet eligibility through the real Bash/jq inventory entrypoint."""
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(os.environ.get("ACFS_SWARM_INV_SCRIPT", ROOT / "scripts/lib/swarm_inventory.sh"))


def stamp(hours=0):
    return (datetime.now(timezone.utc) - timedelta(hours=hours, seconds=5)).strftime("%Y-%m-%dT%H:%M:%SZ")


def host(name="alpha", recommended=10, safe=16):
    return {"id": name, "role": "swarm-worker", "status": "active", "last_probe_at": stamp(),
            "resources": {}, "capacity": {"workload": "standard", "recommended_agents": recommended, "safe_agents": safe},
            "rch": {}, "ntm": {"can_launch": True}, "ru": {}}


class InventoryAdmissionTests(unittest.TestCase):
    def setUp(self):
        # Retain evidence; no repository or user files are removed by the suite.
        self.base = Path(tempfile.mkdtemp(prefix="acfs-inventory-admission-"))
        self.inventory = self.base / "inventory.json"
        self.data = {"schema_version": 1, "defaults": {"stale_after_hours": 24}, "hosts": [host()]}

    def call(self, operation="report", text=None, extra=(), code=None):
        self.inventory.write_text(json.dumps(self.data) if text is None else text)
        before = self.inventory.read_bytes()
        result = subprocess.run(["bash", str(SCRIPT), operation, "--inventory", str(self.inventory), "--json", *extra],
                                capture_output=True, text=True, timeout=8, cwd=self.base)
        self.assertEqual(self.inventory.read_bytes(), before)
        if code is not None:
            self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        return result, json.loads(result.stdout)

    def excluded(self, reason):
        _, result = self.call(code=1)
        self.assertEqual(result["recommended_launch_targets"], [])
        self.assertEqual(result["summary"]["recommended_agents_total"], 0)
        self.assertEqual(result["summary"]["safe_agents_total"], 0)
        self.assertIn(reason, result["hosts"][0]["exclusion_reasons"])
        self.assertFalse(result["hosts"][0]["eligible"])

    def test_fresh_explicit_host_retains_real_capacity(self):
        _, result = self.call(code=0)
        self.assertEqual(result["summary"]["recommended_agents_total"], 10)
        self.assertEqual(result["summary"]["safe_agents_total"], 16)
        self.assertTrue(result["hosts"][0]["eligible"])
        self.assertFalse(result["evidence"]["live_verified"])
        self.assertTrue(result["evidence"]["requires_live_admission"])

    def test_explicit_launch_veto_is_not_defaulted_to_true(self):
        self.data["hosts"][0]["ntm"]["can_launch"] = False
        self.excluded("launch_not_enabled")

    def test_missing_and_null_launch_flags_are_not_authorization(self):
        for value in ({}, {"can_launch": None}):
            with self.subTest(value=value):
                self.data["hosts"][0]["ntm"] = value
                self.excluded("launch_not_enabled")

    def test_missing_null_and_invalid_timestamps_exclude_host(self):
        for value in (None, "", "yesterday", "2026-02-30T01:00:00Z", "2026-05-08T24:00:00Z"):
            with self.subTest(value=value):
                self.data["hosts"][0]["last_probe_at"] = value
                self.excluded("probe_unknown")
        self.data["hosts"][0].pop("last_probe_at")
        self.excluded("probe_unknown")

    def test_future_timestamp_does_not_create_infinite_freshness(self):
        self.data["hosts"][0]["last_probe_at"] = stamp(-1)
        self.excluded("probe_future")

    def test_stale_timestamp_excludes_capacity(self):
        self.data["hosts"][0]["last_probe_at"] = stamp(25)
        self.excluded("probe_stale")

    def test_zero_safe_capacity_is_a_hard_cap(self):
        self.data["hosts"][0]["capacity"]["safe_agents"] = 0
        self.excluded("capacity_exhausted")

    def test_recommendation_never_exceeds_safe_capacity(self):
        self.data["hosts"][0]["capacity"] = {"recommended_agents": 50, "safe_agents": 6}
        _, result = self.call(code=0)
        self.assertEqual(result["recommended_launch_targets"][0]["recommended_agents"], 6)

    def test_unknown_capacity_cannot_admit_a_host(self):
        for field in ("safe_agents", "recommended_agents"):
            self.data["hosts"][0] = host()
            self.data["hosts"][0]["capacity"].pop(field)
            self.excluded("capacity_unknown")

    def test_invalid_counters_are_rejected_without_coercion(self):
        for field in ("safe_agents", "recommended_agents"):
            for value in (-1, 0.5, "20", True, {}, 1000001):
                with self.subTest(field=field, value=value):
                    self.data["hosts"][0] = host()
                    self.data["hosts"][0]["capacity"][field] = value
                    _, result = self.call(code=2)
                    self.assertEqual(result["error_code"], "invalid_capacity_counter")

    def test_invalid_launch_flag_is_rejected(self):
        for value in ("true", "false", 1, 0, [], {}):
            with self.subTest(value=value):
                self.data["hosts"][0]["ntm"]["can_launch"] = value
                _, result = self.call(code=2)
                self.assertEqual(result["error_code"], "invalid_launch_flag")

    def test_disabled_and_build_only_roles_do_not_contribute(self):
        self.data["hosts"] += [host("disabled"), host("build-only"), host("stale-status")]
        self.data["hosts"][1]["role"] = "disabled"
        self.data["hosts"][2]["role"] = "rch-worker"
        self.data["hosts"][3]["status"] = "stale"
        _, result = self.call(code=0)
        self.assertEqual([h["id"] for h in result["recommended_launch_targets"]], ["alpha"])
        self.assertEqual(result["summary"]["recommended_agents_total"], 10)

    def test_duplicate_decoded_keys_cannot_hide_launch_veto(self):
        text = json.dumps(self.data).replace('"can_launch": true', '"can_launch": false, "can_\\u006caunch": true')
        _, result = self.call(text=text, code=2)
        self.assertEqual(result["error_code"], "malformed_json")

    def test_ambiguous_nonfinite_and_deep_json_is_rejected(self):
        for text in (json.dumps(self.data) + " {}", '{"v": NaN}', '{"v": 1e999}', '[' * 40 + '0' + ']' * 40,
                     '{"v":"\\ud800"}', json.dumps(self.data) + '\0'):
            with self.subTest(text=text[:30]):
                _, result = self.call(text=text, code=2)
                self.assertEqual(result["error_code"], "malformed_json")

    def test_raw_input_limit_includes_trailing_whitespace(self):
        self.call(text=json.dumps(self.data) + " " * 1048576, code=2)

    def test_large_valid_inventory_does_not_exceed_argv_limit(self):
        self.data["fleet_note"] = "a" * 262144
        _, result = self.call(code=0)
        self.assertEqual(result["summary"]["recommended_agents_total"], 10)

    def test_secrets_are_still_rejected_not_echoed(self):
        self.data["hosts"][0]["password"] = "THIS_MUST_NOT_APPEAR"
        result, parsed = self.call(code=2)
        self.assertEqual(parsed["error_code"], "forbidden_sensitive_field")
        self.assertNotIn("THIS_MUST_NOT_APPEAR", result.stdout + result.stderr)

    def test_import_preserves_unknown_fields_and_validates_before_writing(self):
        self.data["fleet_note"] = "retain me"
        output = self.base / "imported.json"
        _, result = self.call("import", extra=("--input", str(self.inventory), "--output", str(output)), code=0)
        self.assertEqual(json.loads(output.read_text())["fleet_note"], "retain me")
        self.assertEqual(result["summary"]["imported_hosts"], 1)
        original = output.read_bytes()
        self.data["hosts"][0]["capacity"]["safe_agents"] = -1
        self.call("import", extra=("--input", str(self.inventory), "--output", str(output)), code=2)
        self.assertEqual(output.read_bytes(), original)

    def test_invalid_staleness_policy_cannot_disable_expiration(self):
        for value in (0, False, "24", 1e99, 8761):
            with self.subTest(value=value):
                self.data["defaults"]["stale_after_hours"] = value
                self.call(code=2)

    def test_workload_metadata_cannot_be_silently_defaulted(self):
        for container in (self.data["defaults"], self.data["hosts"][0]["capacity"]):
            for value in (None, False, 1, "unknown", [], {}):
                with self.subTest(value=value):
                    container["workload"] = value
                    _, result = self.call(code=2)
                    self.assertEqual(result["error_code"], "invalid_workload")
            container["workload"] = "standard"

    def test_invalid_unicode_in_keys_is_not_normalized_by_jq(self):
        _, result = self.call(text=json.dumps(self.data)[:-1] + ',"\\ud800":0}', code=2)
        self.assertEqual(result["error_code"], "malformed_json")

    def test_report_is_local_and_read_only(self):
        before = set(self.base.iterdir())
        _, report = self.call(code=0)
        self.assertEqual(set(self.base.iterdir()) - before, {self.inventory})
        self.assertFalse(any(report["mutations"].values()))
        self.assertTrue(report["advisory_only"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
