"""Kernel-fixture tests plus the actual capacity model and CLI.

Fixtures replace proc/cgroup observations only. --live runs the unmodified
entrypoint against the current Linux process, without resource overrides.
"""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(os.environ.get("ACFS_CAPACITY_TEST_SOURCE", Path(__file__).resolve().parents[2] / "scripts/lib/capacity.sh"))
MARKER = "ACFS_PROCESS_LIMITS_PY"
CODE = SOURCE.read_text().split("<<'" + MARKER + "'\n", 1)[1].split("\n" + MARKER, 1)[0]
MODULE = {"__name__": "capacity_limits_tested_runtime"}
exec(compile(CODE, str(SOURCE) + "::process_limits", "exec"), MODULE)


class LimitsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="acfs-limit-test-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.proc = self.base / "proc"
        (self.proc / "self").mkdir(parents=True)
        self.cgroup = self.base / "cgroup"
        self.cgroup.mkdir()
        self.write_proc("0::/\n", self.mount("cgroup2"))

    def escaped(self, value):
        return str(value).replace("\\", "\\134").replace(" ", "\\040").replace("\t", "\\011").replace("\n", "\\012")

    def mount(self, kind, root="/", point=None, controllers="rw"):
        return "40 20 0:30 %s %s rw - %s cgroup %s\n" % (self.escaped(root), self.escaped(point or self.cgroup), kind, controllers)

    def write_proc(self, membership, mounts):
        (self.proc / "self/cgroup").write_text(membership)
        (self.proc / "self/mountinfo").write_text(mounts)

    def limits(self, directory=None, memory="max", cpu="max 100000"):
        directory = directory or self.cgroup
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "memory.max").write_text(memory + "\n")
        (directory / "cpu.max").write_text(cpu + "\n")

    def inspect(self, affinity=64):
        return MODULE["inspect_limits"](self.proc, affinity)

    def model(self, cpu="64", memory="268435456", cpu_override="", memory_override="", affinity=64):
        return MODULE["model_limits"](cpu, memory, cpu_override, memory_override, self.proc, affinity)

    def test_v2_limits_constrain_a_large_host(self):
        self.limits(memory=str(8 * 1024**3), cpu="150000 100000")
        cpu, memory, report = self.model()
        self.assertEqual((cpu, memory), (1500, 8 * 1024**2))
        self.assertEqual(report["status"], "known")
        self.assertEqual(report["cgroup_version"], "v2")

    def test_tighter_parent_beats_unlimited_leaf(self):
        leaf = self.cgroup / "slice/job"
        self.limits(memory=str(32 * 1024**3), cpu="800000 100000")
        self.limits(self.cgroup / "slice", memory=str(6 * 1024**3), cpu="175000 100000")
        self.limits(leaf)
        self.write_proc("0::/slice/job\n", self.mount("cgroup2"))
        cpu, memory, report = self.model()
        self.assertEqual((cpu, memory), (1750, 6 * 1024**2))
        self.assertEqual(report["ancestor_observations"], 3)

    def test_fractional_quota_is_floored_not_rounded_to_a_core(self):
        for quota, period, expected in [(50000, 100000, 500), (1, 100000, 0), (100000, 300000, 333)]:
            with self.subTest(quota=quota, period=period):
                self.limits(cpu=f"{quota} {period}")
                self.assertEqual(self.model()[0], expected)

    def test_unlimited_cgroup_cannot_raise_physical_resources(self):
        self.limits()
        self.assertEqual(self.model(cpu="4", memory="8388608")[:2], (4000, 8388608))
        self.limits(memory=str(2**63 - 4096), cpu="90000000 100000")
        self.assertEqual(self.model(cpu="4", memory="8388608")[:2], (4000, 8388608))

    def test_affinity_cpuset_caps_quota_and_visible_processors(self):
        self.limits(cpu="800000 100000")
        self.assertEqual(self.model(affinity=2)[0], 2000)

    def test_zero_memory_is_not_missing(self):
        self.limits(memory="0")
        self.assertEqual(self.model()[1], 0)

    def test_sub_kibibyte_memory_is_floored(self):
        self.limits(memory="1023")
        self.assertEqual(self.model()[1], 0)

    def test_subtree_mount_resolves_relative_membership(self):
        self.limits(memory=str(4 * 1024**3), cpu="200000 100000")
        self.limits(self.cgroup / "job")
        self.write_proc("0::/tenant/job\n", self.mount("cgroup2", root="/tenant"))
        cpu, memory, report = self.model()
        self.assertEqual((cpu, memory), (2000, 4 * 1024**2))
        self.assertTrue(report["subtree_mount"])
        self.assertEqual(report["ancestor_observations"], 2)

    def test_widest_mount_keeps_tighter_ancestor_visible(self):
        self.limits(cpu="50000 100000")
        self.limits(self.cgroup / "job")
        subtree = self.base / "bind"
        self.limits(subtree)
        self.write_proc("0::/job\n", self.mount("cgroup2", root="/job", point=subtree) + self.mount("cgroup2"))
        self.assertEqual(self.model()[0], 500)

    def test_namespace_root_is_measured_not_assumed_unlimited(self):
        self.limits(memory="1048576", cpu="25000 100000")
        self.assertEqual(self.model()[:2], (250, 1024))

    def test_mountinfo_escaped_paths_are_decoded_once(self):
        unusual = self.base / "space and\\backslash"
        self.limits(unusual, memory="8388608", cpu="120000 100000")
        self.write_proc("0::/\n", self.mount("cgroup2", point=unusual))
        self.assertEqual(self.model()[:2], (1200, 8192))

    def test_missing_membership_directory_fails_closed(self):
        self.write_proc("0::/missing\n", self.mount("cgroup2"))
        cpu, memory, report = self.model()
        self.assertEqual((cpu, memory), (0, 0))
        self.assertEqual(report["status"], "unavailable")
        self.assertNotIn(str(self.base), json.dumps(report))

    def test_membership_outside_visible_mount_fails_closed(self):
        self.write_proc("0::/another/job\n", self.mount("cgroup2", root="/tenant"))
        self.assertEqual(self.model()[:2], (0, 0))

    def test_no_mount_for_active_controller_fails_closed(self):
        self.write_proc("0::/\n", "20 10 0:20 / /proc rw - proc proc rw\n")
        self.assertEqual(self.inspect()["errors"], ["cgroup_mount_unavailable"])

    def test_missing_controller_files_on_real_root_are_unlimited(self):
        self.assertEqual(self.model()[:2], (64000, 268435456))

    def test_invalid_cpu_limits_cannot_create_positive_capacity(self):
        for value in ("", "50000", "0 100000", "-2 100000", "max 0", "max NaN", "1.5 100000", "1 2 3", "1e999 100000"):
            with self.subTest(value=value):
                self.limits(cpu=value)
                self.assertEqual(self.model()[:2], (0, 0))

    def test_invalid_memory_limits_cannot_create_positive_capacity(self):
        for value in ("", "-1", "1.5", "nan", "1e999", "max 1", str(2**64)):
            with self.subTest(value=value):
                self.limits(memory=value)
                self.assertEqual(self.model()[:2], (0, 0))

    def test_symlinked_limit_is_not_followed(self):
        secret = self.base / "secret"
        secret.write_text("SECRET-CONTENT")
        (self.cgroup / "memory.max").symlink_to(secret)
        report = self.inspect()
        self.assertEqual(report["status"], "unavailable")
        self.assertNotIn("SECRET", json.dumps(report))
        self.assertEqual(secret.read_text(), "SECRET-CONTENT")

    def test_symlinked_cgroup_directory_is_not_followed(self):
        outside = self.base / "outside"
        self.limits(outside)
        (self.cgroup / "job").symlink_to(outside, target_is_directory=True)
        self.write_proc("0::/job\n", self.mount("cgroup2"))
        self.assertEqual(self.inspect()["status"], "unavailable")

    def test_fifo_limit_fails_without_blocking(self):
        os.mkfifo(self.cgroup / "cpu.max")
        self.assertEqual(self.inspect()["status"], "unavailable")

    def test_v1_cpu_and_memory_limits_are_combined(self):
        cpu = self.base / "cpu"
        memory = self.base / "memory"
        cpu.mkdir()
        memory.mkdir()
        (cpu / "cpu.cfs_quota_us").write_text("150000\n")
        (cpu / "cpu.cfs_period_us").write_text("100000\n")
        (memory / "memory.limit_in_bytes").write_text(str(8 * 1024**3))
        self.write_proc("2:cpu,cpuacct:/\n3:memory:/\n", self.mount("cgroup", point=cpu, controllers="rw,cpu,cpuacct") + self.mount("cgroup", point=memory, controllers="rw,memory"))
        self.assertEqual(self.model()[:2], (1500, 8388608))
        self.assertEqual(self.inspect()["cgroup_version"], "v1")

    def test_v1_hierarchical_memory_limit_covers_hidden_ancestors(self):
        (self.cgroup / "memory.limit_in_bytes").write_text(str(2**63 - 4096))
        (self.cgroup / "memory.stat").write_text("cache 123\nhierarchical_memory_limit 8388608\nrss 50\n")
        self.write_proc("3:memory:/tenant\n", self.mount("cgroup", root="/tenant", controllers="rw,memory"))
        self.assertEqual(self.model()[1], 8192)

    def test_v1_unlimited_sentinel_cannot_overflow_host_bounds(self):
        (self.cgroup / "memory.limit_in_bytes").write_text(str(2**63 - 4096))
        (self.cgroup / "cpu.cfs_quota_us").write_text("-1")
        (self.cgroup / "cpu.cfs_period_us").write_text("100000")
        self.write_proc("2:cpu,memory:/\n", self.mount("cgroup", controllers="rw,cpu,memory"))
        self.assertEqual(self.model()[:2], (64000, 268435456))

    def test_v1_incomplete_quota_is_unknown(self):
        (self.cgroup / "cpu.cfs_quota_us").write_text("50000")
        self.write_proc("2:cpu:/\n", self.mount("cgroup", controllers="rw,cpu"))
        self.assertEqual(self.model()[:2], (0, 0))

    def test_hybrid_controllers_keep_both_limits(self):
        cpu = self.base / "cpu"
        cpu.mkdir()
        (cpu / "cpu.cfs_quota_us").write_text("50000")
        (cpu / "cpu.cfs_period_us").write_text("100000")
        self.limits(memory=str(4 * 1024**3))
        self.write_proc("0::/\n2:cpu:/\n", self.mount("cgroup2") + self.mount("cgroup", point=cpu, controllers="rw,cpu"))
        self.assertEqual(self.model()[:2], (500, 4194304))
        self.assertEqual(self.inspect()["cgroup_version"], "hybrid")

    def test_unrelated_v1_controllers_do_not_invent_constraints(self):
        self.write_proc("4:devices:/foo\n", self.mount("cgroup", controllers="rw,devices"))
        self.assertEqual(self.inspect()["cgroup_version"], "none")
        self.assertEqual(self.model(affinity=4)[:2], (4000, 268435456))

    def test_membership_change_during_observation_fails_closed(self):
        original = MODULE["text"]
        count = 0
        def reader(path, limit=262144):
            nonlocal count
            value = original(path, limit)
            if path.name == "cgroup":
                count += 1
                if count == 2:
                    return "0::/moved\n"
            return value
        with patch.dict(MODULE, text=reader):
            self.assertEqual(self.inspect()["errors"], ["cgroup_changed_during_observation"])

    def test_ambiguous_membership_and_path_traversal_fail_closed(self):
        for membership in ("0::/\n0::/other\n", "0::/../outside\n", "garbage\n", "1::/\n"):
            with self.subTest(membership=membership):
                self.write_proc(membership, self.mount("cgroup2"))
                self.assertEqual(self.model()[:2], (0, 0))

    def test_oversized_and_nonascii_limit_fails_closed(self):
        for value in ("1" * 5000, "\N{SNOWMAN}"):
            with self.subTest(value=value[:10]):
                self.limits(memory=value)
                self.assertEqual(self.model()[:2], (0, 0))

    def test_errors_are_redacted(self):
        def reader(*args):
            raise PermissionError("/private/path/TOKEN-SECRET")
        with patch.dict(MODULE, text=reader):
            report = self.inspect()
        self.assertEqual(report["errors"], ["kernel_limits_unreadable"])
        self.assertNotIn("SECRET", json.dumps(report))

    def test_explicit_legacy_resource_fixtures_are_labelled(self):
        self.limits(memory="0", cpu="1 100000")
        cpu, memory, report = self.model(cpu_override="64", memory_override="268435456")
        self.assertEqual((cpu, memory), (64000, 268435456))
        self.assertEqual(report["status"], "fixture")
        self.assertEqual(report["scope"], "explicit_test_overrides")

    def test_one_fixture_dimension_does_not_hide_other_real_limit(self):
        self.limits(memory="8388608", cpu="50000 100000")
        self.assertEqual(self.model(cpu_override="64")[:2], (64000, 8192))
        self.assertEqual(self.model(memory_override="268435456")[:2], (500, 268435456))

    def test_mismatching_or_invalid_override_is_not_accepted(self):
        self.limits(memory="8388608", cpu="50000 100000")
        for override in ("0", "32", "64;false", "1e9"):
            with self.subTest(override=override):
                self.assertEqual(self.model(cpu_override=override)[:2], (500, 8192))


class CapacityModelTests(unittest.TestCase):
    def run_model(self, budget, memory_kb, workload="standard", broken=False):
        metadata = {"status": "unavailable" if broken else "known", "scope": "current_process_visible_hierarchy",
                    "effective_cpu_millicores": budget, "effective_memory_kb": memory_kb}
        # Only the kernel-observation boundary is replaced. Arithmetic, model
        # status, JSON projection and command-line dispatch are production code.
        script = 'source "$1"\ncapacity_process_limits() { '
        script += 'return 1; }\n' if broken else 'printf "%s\\t%s\\t%s\\n" "$BUDGET" "$MEMORY" "$DETAILS"; }\n'
        script += 'capacity_main --json --recommend-ntm --workload "$2"'
        env = {"PATH": "/usr/bin:/bin", "HOME": os.environ.get("HOME", "/tmp"),
               "ACFS_CAPACITY_CPU_COUNT": "64", "ACFS_CAPACITY_MEM_TOTAL_KB": "268435456",
               "ACFS_CAPACITY_DISK_AVAILABLE_KB": "536870912", "ACFS_CAPACITY_RCH_AVAILABLE": "true",
               "ACFS_CAPACITY_NTM_AVAILABLE": "true", "BUDGET": str(budget), "MEMORY": str(memory_kb),
               "DETAILS": json.dumps(metadata)}
        result = subprocess.run(["/bin/bash", "-c", script, "model", str(SOURCE), workload],
                                env=env, text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_large_host_under_small_memory_limit_never_recommends_host_capacity(self):
        result = self.run_model(64000, 8 * 1024**2)
        self.assertEqual(result["host"]["physical_mem_total_mib"], 262144)
        self.assertEqual(result["host"]["mem_total_mib"], 8192)
        self.assertEqual(result["capacity"]["safe_agent_count"], 1)
        self.assertEqual(result["capacity"]["recommended_agent_count"], 1)

    def test_cpu_budget_affects_every_workload_without_rounding_up(self):
        for workload, maximum in (("light", 3), ("standard", 1), ("heavy", 0)):
            with self.subTest(workload=workload):
                result = self.run_model(1500, 268435456, workload)
                self.assertEqual(result["capacity"]["safe_agent_count"], maximum)
                self.assertEqual(result["host"]["effective_cpu_millicores"], 1500)

    def test_unobservable_context_blocks_all_positive_recommendations(self):
        result = self.run_model(0, 0, broken=True)
        self.assertEqual(result["status"], "fail")
        self.assertEqual(result["capacity"]["recommended_agent_count"], 0)
        self.assertEqual(result["resource_limits"]["status"], "unavailable")
        self.assertTrue(any("resource limits" in item for item in result["recommendations"]))

    def test_below_one_workload_unit_does_not_round_up(self):
        result = self.run_model(499, 268435456, "light")
        self.assertEqual(result["capacity"]["safe_agent_count"], 0)
        self.assertEqual(result["ntm"]["agent_count"], 0)


def live_smoke():
    env = {key: value for key, value in os.environ.items() if not key.startswith(("ACFS_CAPACITY_", "BASH_FUNC_"))}
    env.pop("BASH_ENV", None)
    env.pop("ENV", None)
    result = subprocess.run(["/bin/bash", str(SOURCE), "--json", "--workload", "light"],
                            env=env, text=True, capture_output=True, timeout=10)
    if result.returncode:
        raise AssertionError(result.stderr)
    report = json.loads(result.stdout)
    limits = report["resource_limits"]
    assert limits["status"] == "known", limits
    assert limits["cpu_source"] == limits["memory_source"] == "kernel"
    assert report["host"]["effective_cpu_millicores"] <= len(os.sched_getaffinity(0)) * 1000
    assert report["host"]["mem_total_mib"] <= report["host"]["physical_mem_total_mib"]
    assert report["capacity"]["safe_agent_count"] <= limits["effective_cpu_millicores"] // 500
    if limits["memory_limit_bytes"] is not None:
        assert report["host"]["mem_total_mib"] <= limits["memory_limit_bytes"] // 1024**2
    if os.environ.get("ACFS_LIMIT_TEST_RESTRICTED") == "1":
        assert limits["cpu_quota_millicores"] <= 500, limits
        assert limits["memory_limit_bytes"] <= 512 * 1024**2, limits
        assert report["capacity"]["safe_agent_count"] == 0
    print("LIVE_PROCESS_LIMITS_SMOKE=pass")


if __name__ == "__main__":
    if sys.argv[1:] == ["--live"]:
        live_smoke()
    else:
        unittest.main(verbosity=2)
