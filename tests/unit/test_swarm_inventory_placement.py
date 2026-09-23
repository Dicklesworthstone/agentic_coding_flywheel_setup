"""Fleet placement operates on validated recorded headroom, never live launch."""
import json
import subprocess
import unittest

import test_swarm_inventory_admission as admission

SCRIPT = admission.SCRIPT
host = admission.host
stamp = admission.stamp


class InventoryPlacementTests(unittest.TestCase):
    setUp = admission.InventoryAdmissionTests.setUp
    call = admission.InventoryAdmissionTests.call

    def plan(self, count=25, workload="standard", code=0):
        result, plan = self.call("plan", extra=("--agents", str(count), "--workload", workload), code=code)
        self.assertEqual(plan["assigned_agents"] + plan["unassigned_agents"], count)
        self.assertEqual(sum(a["agents"] for a in plan["allocations"]), plan["assigned_agents"])
        self.assertEqual(len({a["host_id"] for a in plan["allocations"]}), len(plan["allocations"]))
        for allocation in plan["allocations"]:
            self.assertGreater(allocation["agents"], 0)
            self.assertLessEqual(allocation["agents"], allocation["recorded_recommendation"])
            self.assertLessEqual(allocation["agents"], allocation["safe_agents"])
        self.assertFalse(any(plan["mutations"].values()))
        self.assertNotIn("ntm spawn", result.stdout)
        return plan

    def test_allocates_target_across_hosts(self):
        self.data["hosts"] = [host("small", 10, 12), host("big", 20, 24)]
        result = self.plan()
        self.assertEqual([(a["host_id"], a["agents"]) for a in result["allocations"]], [("big", 20), ("small", 5)])
        self.assertTrue(result["fully_placed"])
        self.assertEqual(result["recorded_capacity_total"], 30)
        self.assertEqual(result["allocation_semantics"], "target_totals_not_additional_agents")

    def test_fills_largest_host_before_spreading_work(self):
        self.data["hosts"] = [host("small", 10, 12), host("big", 20, 24)]
        self.assertEqual([(a["host_id"], a["agents"]) for a in self.plan(8)["allocations"]], [("big", 8)])

    def test_ties_are_stable_under_permutation(self):
        self.data["hosts"] = [host("zeta", 20, 24), host("alpha", 20, 24)]
        first = self.plan()["allocations"]
        self.data["hosts"].reverse()
        second = self.plan()["allocations"]
        self.assertEqual(first, second)
        self.assertEqual(first[0]["host_id"], "alpha")

    def test_shortfall_is_not_hidden_by_safe_maximum(self):
        self.data["hosts"] = [host("a", 10, 80), host("b", 5, 80)]
        result = self.plan(25, code=1)
        self.assertEqual(result["assigned_agents"], 15)
        self.assertEqual(result["unassigned_agents"], 10)
        self.assertFalse(result["fully_placed"])

    def test_excluded_hosts_never_supply_capacity(self):
        self.data["hosts"] = [host("a", 20, 24), host("veto", 100, 120), host("old", 100, 120)]
        self.data["hosts"][1]["ntm"]["can_launch"] = False
        self.data["hosts"][2]["last_probe_at"] = stamp(48)
        result = self.plan(25, code=1)
        self.assertEqual(result["assigned_agents"], 20)
        self.assertEqual({h["id"] for h in result["excluded_hosts"]}, {"old", "veto"})

    def test_workload_counts_are_not_substituted_across_profiles(self):
        self.data["hosts"] = [host("standard", 20, 30), host("light", 40, 50)]
        self.data["hosts"][1]["capacity"]["workload"] = "light"
        result = self.plan(25, code=1)
        self.assertEqual(result["unassigned_agents"], 5)
        self.assertIn("workload_mismatch", result["excluded_hosts"][0]["reasons"])
        light = self.plan(25, workload="light")
        self.assertEqual(light["allocations"][0]["host_id"], "light")

    def test_capped_recommendation_drives_report_and_plan(self):
        self.data["hosts"] = [host("alpha", 20, 3)]
        result = self.plan(5, code=1)
        self.assertEqual(result["assigned_agents"], 3)

    def test_empty_inventory_returns_explicit_unassigned_target(self):
        self.data["hosts"] = []
        result = self.plan(50, code=1)
        self.assertEqual(result["allocations"], [])
        self.assertEqual(result["unassigned_agents"], 50)

    def test_maximum_supported_count_does_not_loop_per_agent(self):
        self.data["hosts"] = [host("alpha", 1000000, 1000000)]
        self.assertEqual(self.plan(1000000)["assigned_agents"], 1000000)

    def test_plan_outputs_safe_host_local_admission_commands(self):
        self.data["hosts"] = [host("alpha", 30, 40)]
        result = self.plan(25)
        self.assertEqual(result["allocations"][0]["live_admission_command"], "acfs swarm plan --agents 25 --workload standard --json")
        self.assertTrue(result["evidence"]["requires_live_admission"])
        self.assertFalse(result["evidence"]["live_verified"])

    def test_human_plan_clearly_separates_recorded_totals_from_launches(self):
        self.inventory.write_text(json.dumps(self.data))
        result = subprocess.run(["bash", str(SCRIPT), "plan", "--inventory", str(self.inventory), "--agents", "5"],
                                capture_output=True, text=True, timeout=8)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("NOT additional agents", result.stdout)
        self.assertIn("No agents launched", result.stdout)
        self.assertNotIn("ntm spawn", result.stdout)

    def test_invalid_plan_arguments_are_inert(self):
        cases = [[], ["--agents", "0"], ["--agents", "-1"], ["--agents", "01"], ["--agents", "1.5"],
                 ["--agents", "1000001"], ["--agents", "1;touch hacked"],
                 ["--agents", "5", "--agents", "6"], ["--agents", "5", "--workload", "unknown"],
                 ["--agents", "5", "--output", str(self.base / "unwanted.json")],
                 ["--agents", "5", "--artifact-dir", str(self.base / "unwanted")]]
        for args in cases:
            with self.subTest(args=args):
                result = subprocess.run(["bash", str(SCRIPT), "plan", *args], capture_output=True, text=True, timeout=5, cwd=self.base)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(list(self.base.iterdir()), [])

    def test_large_inventory_import_and_export_still_complete(self):
        self.data["fleet_note"] = "a" * 262144
        imported = self.base / "imported.json"
        self.call("import", extra=("--input", str(self.inventory), "--output", str(imported)), code=0)
        self.assertEqual(json.loads(imported.read_text())["fleet_note"], self.data["fleet_note"])
        exported = self.base / "exported.json"
        self.call("export", extra=("--output", str(exported)), code=0)
        self.assertEqual(json.loads(exported.read_text())["fleet_note"], self.data["fleet_note"])

    def test_plan_flags_cannot_accidentally_apply_to_import(self):
        result = subprocess.run(["bash", str(SCRIPT), "import", "--agents", "5"], capture_output=True, text=True, timeout=5, cwd=self.base)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(list(self.base.iterdir()), [])

    def test_second_operation_cannot_turn_a_plan_into_an_import(self):
        self.inventory.write_text(json.dumps(self.data))
        for operations in (["plan", "import"], ["--json", "plan", "import"], ["report", "import"]):
            with self.subTest(operations=operations):
                result = subprocess.run(["bash", str(SCRIPT), *operations, "--input", str(self.inventory),
                                         "--output", str(self.base / "unwanted.json")],
                                        capture_output=True, text=True, timeout=5, cwd=self.base)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(list(self.base.iterdir()), [self.inventory])


if __name__ == "__main__":
    unittest.main(verbosity=2)
