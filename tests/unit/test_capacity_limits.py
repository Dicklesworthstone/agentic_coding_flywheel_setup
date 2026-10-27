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


class MemoryScopeFixture:
    """Synthetic kernel files; neither a live memory limit nor an OOM test."""

    def setUp(self):
        # Retain fixture files and command logs for diagnosing a failed guard.
        self.base = Path(tempfile.mkdtemp(prefix="acfs-memory-scope-"))
        self.proc = self.base / "proc"
        (self.proc / "self").mkdir(parents=True)
        self.cgroup = self.base / "cgroup with spaces"
        self.leaf = self.cgroup / "user.slice/run-acfs.scope"
        self.leaf.mkdir(parents=True)
        self.maximum = 8192 * 1024**2
        self.swap = 2048 * 1024**2
        self.write_membership()
        self.write_mounts()
        self.write_limits()

    @staticmethod
    def escape_mount(value):
        return str(value).replace("\\", "\\134").replace(" ", "\\040").replace("\t", "\\011")

    def write_membership(self, value="0::/user.slice/run-acfs.scope\n"):
        (self.proc / "self/cgroup").write_text(value)

    def write_mounts(self, root="/", point=None, kind="cgroup2"):
        mount = "40 20 0:30 %s %s rw - %s cgroup rw\n" % (
            self.escape_mount(root), self.escape_mount(point or self.cgroup), kind)
        (self.proc / "self/mountinfo").write_text(mount)

    def write_limits(self, memory=None, swap=None):
        (self.leaf / "memory.max").write_text(str(self.maximum if memory is None else memory) + "\n")
        (self.leaf / "memory.swap.max").write_text(str(self.swap if swap is None else swap) + "\n")

    def guard_module(self):
        marker = "ACFS_SCOPE_MEMORY_GUARD_PY"
        source = SOURCE.read_text()
        delimiter = "<<'" + marker + "'\n"
        self.assertIn(delimiter, source, "runtime has no bounded-launch kernel guard")
        code = source.split(delimiter, 1)[1].split("\n" + marker, 1)[0]
        module = {"__name__": "memory_scope_tested_runtime"}
        exec(compile(code, str(SOURCE) + "::scope_memory_guard", "exec"), module)
        return module


class MemoryScopeGuardTests(MemoryScopeFixture, unittest.TestCase):
    def verify(self, swap=True):
        self.guard_module()["verify_limits"](self.maximum, self.swap if swap else None, self.proc)

    def assert_refused(self, swap=True):
        with self.assertRaises((OSError, ValueError)):
            self.verify(swap)

    def test_exact_and_tighter_kernel_limits_admit_the_payload(self):
        self.verify()
        self.write_limits(memory=self.maximum // 2, swap=0)
        self.verify()

    def test_unlimited_or_larger_memory_limit_is_refused(self):
        for value in ("max", self.maximum + 1):
            with self.subTest(value=value):
                self.write_limits(memory=value)
                self.assert_refused()

    def test_unlimited_or_larger_requested_swap_limit_is_refused(self):
        for value in ("max", self.swap + 1):
            with self.subTest(value=value):
                self.write_limits(swap=value)
                self.assert_refused()

    def test_unselected_swap_is_not_restricted(self):
        self.write_limits(swap="max")
        self.verify(swap=False)
        (self.leaf / "memory.swap.max").rename(self.leaf / "saved-swap.max")
        self.verify(swap=False)

    def test_missing_memory_controller_is_refused(self):
        (self.leaf / "memory.max").rename(self.leaf / "saved-memory.max")
        self.assert_refused()

    def test_missing_requested_swap_controller_is_refused(self):
        (self.leaf / "memory.swap.max").rename(self.leaf / "saved-swap.max")
        self.assert_refused()

    def test_malformed_kernel_limit_is_refused(self):
        for value in ("", "-1", "1.5", "1e3", "NaN", "12 34", "1" * 5000, "\N{SNOWMAN}"):
            with self.subTest(value=str(value)[:20]):
                self.write_limits(memory=value)
                self.assert_refused()

    def test_v1_or_missing_unified_membership_is_refused(self):
        for value in ("3:memory:/user.slice/run-acfs.scope\n", "", "garbage\n"):
            with self.subTest(value=value):
                self.write_membership(value)
                self.assert_refused()

    def test_ambiguous_or_escaping_membership_is_refused(self):
        for value in ("0::/user.slice/run-acfs.scope\n0::/elsewhere\n", "0::/../outside\n",
                      "1::/user.slice/run-acfs.scope\n", "0::relative/path\n"):
            with self.subTest(value=value):
                self.write_membership(value)
                self.assert_refused()

    def test_subtree_mount_maps_the_actual_current_scope(self):
        self.write_mounts(root="/user.slice", point=self.cgroup / "user.slice")
        self.verify()

    def test_membership_outside_visible_mount_is_refused(self):
        self.write_mounts(root="/another-user")
        self.assert_refused()

    def test_membership_change_during_verification_is_refused(self):
        module = self.guard_module()
        original = module["read_text"]
        observed = 0

        def reader(path, *arguments, **keywords):
            nonlocal observed
            value = original(path, *arguments, **keywords)
            if str(path).endswith("/self/cgroup"):
                observed += 1
                if observed == 2:
                    return "0::/moved-to-an-unlimited-scope\n"
            return value

        with patch.dict(module, read_text=reader):
            with self.assertRaises(ValueError):
                module["verify_limits"](self.maximum, self.swap, self.proc)

    def test_non_cgroup_mount_cannot_supply_forged_controller_files(self):
        self.write_mounts(kind="tmpfs")
        self.assert_refused()

    def test_symlinked_controller_file_is_refused_without_reading_target(self):
        target = self.base / "private"
        target.write_text("private-value\n")
        (self.leaf / "memory.max").rename(self.leaf / "saved-memory.max")
        (self.leaf / "memory.max").symlink_to(target)
        self.assert_refused()
        self.assertEqual(target.read_text(), "private-value\n")

    def test_symlinked_parent_is_refused(self):
        alias = self.base / "linked-cgroup"
        alias.symlink_to(self.cgroup, target_is_directory=True)
        self.write_mounts(point=alias)
        self.assert_refused()

    def test_fifo_controller_is_refused_without_blocking(self):
        (self.leaf / "memory.max").rename(self.leaf / "saved-memory.max")
        os.mkfifo(self.leaf / "memory.max")
        # Run in a subprocess so a regression is bounded even if open blocks.
        self.guard_module()
        result = subprocess.run(
            [sys.executable, "-I", "-c",
             "import runpy,sys; m=runpy.run_path(sys.argv[1]); "
             "m['MemoryScopeGuardTests']('test_fifo_controller_is_refused_without_blocking').guard_module()"
             "['verify_limits'](int(sys.argv[2]),None,m['Path'](sys.argv[3]))",
             str(Path(__file__).resolve()), str(self.maximum), str(self.proc)],
            capture_output=True, text=True, timeout=3,
            env={**os.environ, "ACFS_CAPACITY_TEST_SOURCE": str(SOURCE)})
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("private-value", result.stderr)


class MemoryScopeWrapperTests(MemoryScopeFixture, unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.root = self.base / "reviewed profile"
        self.bin = self.base / "fixture-bin"
        self.bin.mkdir()
        self.log = self.base / "systemd-run.jsonl"
        self.payload_log = self.base / "payload.jsonl"
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith(("ACFS_", "BASH_FUNC_")) and key not in ("BASH_ENV", "ENV")}
        self.env.update({"PATH": str(self.bin) + ":/usr/bin:/bin", "ACFS_RESOURCE_PROFILE_HOME": str(self.root),
                         "ACFS_CAPACITY_BIN_DIR": str(self.bin), "FIXTURE_PROC": str(self.proc),
                         "FIXTURE_SYSTEMD_LOG": str(self.log), "FIXTURE_PAYLOAD_LOG": str(self.payload_log),
                         "AUTH_LOCATION": str(self.base / "private auth"), "HOME": str(self.base)})
        (self.bin / "bash").symlink_to("/bin/bash")
        (self.bin / "cat").symlink_to("/bin/cat")
        (self.bin / "python3").symlink_to(sys.executable)
        self.write_executable("systemctl", """import os, sys
assert sys.argv[1:] == ['--user', 'show-environment'], sys.argv
sys.exit(int(os.environ.get('FIXTURE_USER_MANAGER_STATUS', '0')))
""")
        self.write_executable("systemd-run", """import json, os, pathlib, sys, types
arguments = sys.argv[1:]
split = next((i for i, argument in enumerate(arguments) if not argument.startswith('--')), len(arguments))
if '--' in arguments[:split]:
    split = arguments.index('--')
options, command = arguments[:split], arguments[split:]
if command and command[0] == '--':
    command = command[1:]
assert {'--user', '--scope', '--same-dir', '--collect'}.issubset(options), options
with open(os.environ['FIXTURE_SYSTEMD_LOG'], 'a') as stream:
    stream.write(json.dumps({'options': options, 'command': command[:3], 'arguments': command[4:]}) + '\\n')
if os.environ.get('FIXTURE_SCOPE_STATUS'):
    sys.exit(int(os.environ['FIXTURE_SCOPE_STATUS']))
assert len(command) >= 6 and command[1:3] == ['-I', '-c'], command[:3]
# Replace only the kernel observation root. Execute the generated Python guard
# and its real exec path; no production guard or payload result is mocked.
RealPath = pathlib.Path
def fixture_path(*parts):
    if parts == ('/proc',):
        parts = (os.environ['FIXTURE_PROC'],)
    return RealPath(*parts)
fixture_pathlib = types.ModuleType('pathlib')
fixture_pathlib.Path = fixture_path
sys.modules['pathlib'] = fixture_pathlib
sys.argv = ['-c', *command[4:]]
exec(compile(command[3], '<generated-acfs-memory-guard>', 'exec'), {'__name__': '__main__'})
""")
        payload = """import json, os, sys
record = {'argv': sys.argv[1:], 'cwd': os.getcwd(), 'auth': os.environ.get('AUTH_LOCATION'), 'stdin': sys.stdin.read()}
with open(os.environ['FIXTURE_PAYLOAD_LOG'], 'a') as stream:
    stream.write(json.dumps(record) + '\\n')
print('payload-stdout')
print('payload-stderr', file=sys.stderr)
sys.exit(int(os.environ.get('FIXTURE_PAYLOAD_STATUS', '0')))
"""
        for name in ("payload", "claude", "codex", "gemini"):
            self.write_executable(name, payload)

    def write_executable(self, name, code):
        path = self.bin / name
        path.write_text("#!" + sys.executable + "\n" + code)
        path.chmod(0o755)
        return path

    def cli(self, *arguments, ok=True):
        result = subprocess.run(["/bin/bash", str(SOURCE), "--json", *arguments],
                                env=self.env, cwd=self.base, capture_output=True, text=True, timeout=8)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def apply(self, swap=True):
        arguments = ["--resource-profile", "--memory-max-mib", "8192", "--apply-resource-profile"]
        if swap:
            arguments += ["--memory-swap-max-mib", "2048"]
        return self.cli(*arguments)

    def launch(self, name="acfs-scope", *arguments, status=0):
        result = subprocess.run([str(self.root / "bin" / name), *arguments],
                                env=self.env, cwd=self.base, input="terminal-input\n", text=True,
                                capture_output=True, timeout=8)
        self.assertEqual(result.returncode, status, result.stderr)
        return result

    def records(self, path):
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_review_reports_exact_limits_for_every_class_without_writes(self):
        report = self.cli("--resource-profile", "--memory-max-mib", "008192", "--memory-swap-max-mib", "0000")
        self.assertFalse(self.root.exists())
        expected = {
            "enabled": True, "memory_max_mib": 8192, "memory_swap_max_mib": 0,
            "on_unavailable": "refuse", "enforcement": "cgroup-v2-verified"}
        self.assertEqual({key: report["memory_bounds"][key] for key in expected}, expected)
        self.assertEqual({item["name"] for item in report["classes"]},
                         {"agent", "background", "local-build", "support", "rch"})
        for item in report["classes"]:
            self.assertIn("MemoryMax=" + str(self.maximum), item["properties"])
            self.assertIn("MemorySwapMax=0", item["properties"])

    def test_invalid_limits_and_conflicting_options_fail_before_writes(self):
        cases = [["--memory-max-mib", value] for value in
                 ("0", "-1", "1.5", "8G", "1048577", "12345678", "infinity", "2;true")]
        cases += [["--memory-max-mib", "8192", "--memory-swap-max-mib", value] for value in
                  ("-1", "1.5", "1048577", "12345678", "max")]
        cases += [["--memory-swap-max-mib", "0"],
                  ["--memory-max-mib", "8192", "--memory-max-mib", "4096"],
                  ["--memory-max-mib", "8192", "--memory-swap-max-mib", "0", "--memory-swap-max-mib", "1"],
                  ["--memory-max-mib", "8192", "--disable-resource-profile"]]
        for arguments in cases:
            with self.subTest(arguments=arguments):
                self.cli("--resource-profile", "--apply-resource-profile", *arguments, ok=False)
                self.assertFalse(self.root.exists())
        self.cli("--memory-max-mib", "8192", ok=False)
        self.assertFalse(self.root.exists())

    def test_all_classes_pass_exact_reviewed_properties_to_systemd(self):
        report = self.apply()
        saved = json.loads((self.root / "profile.json").read_text())
        self.assertEqual(report["memory_bounds"], saved["memory_bounds"])
        self.assertEqual(report["classes"], saved["classes"])
        for name in ("agent", "background", "local-build", "support", "rch"):
            self.launch("acfs-scope", name, "--", "payload", "--literal-option", "argument with spaces")
            entry = self.records(self.log)[-1]
            self.assertIn("--slice=acfs-" + name + ".slice", entry["options"])
            self.assertIn("--property=MemoryMax=" + str(self.maximum), entry["options"])
            self.assertIn("--property=MemorySwapMax=" + str(self.swap), entry["options"])
            self.assertFalse(any("OOMPolicy" in option for option in entry["options"]))
        self.assertEqual(len(self.records(self.payload_log)), 5)

    def test_agent_and_build_wrappers_preserve_arguments_stdin_environment_and_exit(self):
        self.apply()
        self.env["FIXTURE_PAYLOAD_STATUS"] = "37"
        for name, arguments in (("ccs", ["arg with spaces", "--flag", ""]),
                                ("cods", ["arg with spaces", "--flag", ""]),
                                ("gmis", ["arg with spaces", "--flag", ""]),
                                ("acfs-local-build", ["payload", "arg with spaces", "--flag", ""])):
            with self.subTest(wrapper=name):
                result = self.launch(name, *arguments, status=37)
                self.assertEqual(result.stdout, "payload-stdout\n")
                self.assertEqual(result.stderr, "payload-stderr\n")
                self.assertEqual(self.records(self.payload_log)[-1], {
                    "argv": ["arg with spaces", "--flag", ""], "cwd": str(self.base),
                    "auth": self.env["AUTH_LOCATION"], "stdin": "terminal-input\n"})
        self.assertEqual(len(self.records(self.payload_log)), 4, "a failed payload must never be retried")

    def test_named_wrappers_cannot_resolve_an_unbounded_scope_from_path(self):
        self.apply()
        decoy = self.write_executable("acfs-scope", "raise SystemExit('unbounded PATH scope executed')\n")
        self.launch("ccs", "reviewed")
        self.assertEqual(len(self.records(self.log)), 1)
        self.assertEqual(self.records(self.payload_log)[0]["argv"], ["reviewed"])
        self.assertTrue(decoy.exists())

    def test_unavailable_user_manager_prevents_payload_execution(self):
        self.apply()
        self.env["FIXTURE_USER_MANAGER_STATUS"] = "1"
        result = subprocess.run([str(self.root / "bin/acfs-scope"), "agent", "--", "payload"],
                                env=self.env, capture_output=True, text=True, timeout=8)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.records(self.log), [])
        self.assertEqual(self.records(self.payload_log), [])

    def test_missing_systemd_tools_prevent_bounded_payload_execution(self):
        self.apply()
        bare = self.base / "bare-bin"
        bare.mkdir()
        (bare / "bash").symlink_to("/bin/bash")
        (bare / "cat").symlink_to("/bin/cat")
        self.env["PATH"] = str(bare)
        result = subprocess.run([str(self.root / "bin/acfs-scope"), "agent", "--", str(self.bin / "payload")],
                                env=self.env, capture_output=True, text=True, timeout=8)
        self.assertEqual(result.returncode, 125, result.stderr)
        self.assertEqual(self.records(self.payload_log), [])

    def test_missing_python_prevents_bounded_payload_execution(self):
        self.apply()
        (self.bin / "python3").rename(self.bin / "saved-python3")
        self.env["PATH"] = str(self.bin)
        result = subprocess.run([str(self.root / "bin/acfs-scope"), "agent", "--", str(self.bin / "payload")],
                                env=self.env, capture_output=True, text=True, timeout=8)
        self.assertEqual(result.returncode, 125, result.stderr)
        self.assertEqual(self.records(self.log), [])
        self.assertEqual(self.records(self.payload_log), [])

    def test_environment_cannot_remove_the_reviewed_limits(self):
        self.apply()
        self.env.update({"CAPACITY_MEMORY_MAX_MIB": "", "CAPACITY_MEMORY_SWAP_MAX_MIB": "",
                         "memory_max_bytes": "", "memory_swap_max_bytes": ""})
        self.launch("acfs-scope", "agent", "--", "payload")
        entry = self.records(self.log)[0]
        self.assertIn("--property=MemoryMax=" + str(self.maximum), entry["options"])
        self.assertIn("--property=MemorySwapMax=" + str(self.swap), entry["options"])

    def test_rejected_systemd_scope_never_falls_back_or_retries(self):
        self.apply()
        self.env["FIXTURE_SCOPE_STATUS"] = "79"
        self.launch("acfs-scope", "agent", "--", "payload", status=79)
        self.assertEqual(len(self.records(self.log)), 1)
        self.assertEqual(self.records(self.payload_log), [])

    def test_successful_systemd_launch_with_unenforced_memory_never_runs_payload(self):
        self.apply()
        self.write_limits(memory="max")
        result = subprocess.run([str(self.root / "bin/acfs-scope"), "agent", "--", "payload"],
                                env=self.env, capture_output=True, text=True, timeout=8)
        self.assertEqual(result.returncode, 125, result.stderr)
        self.assertIn("command not started", result.stderr)
        self.assertEqual(len(self.records(self.log)), 1)
        self.assertEqual(self.records(self.payload_log), [])

    def test_successful_systemd_launch_with_unenforced_swap_never_runs_payload(self):
        self.apply()
        self.write_limits(swap="max")
        result = subprocess.run([str(self.root / "bin/acfs-scope"), "agent", "--", "payload"],
                                env=self.env, capture_output=True, text=True, timeout=8)
        self.assertEqual(result.returncode, 125, result.stderr)
        self.assertIn("command not started", result.stderr)
        self.assertEqual(len(self.records(self.log)), 1)
        self.assertEqual(self.records(self.payload_log), [])

    def test_omitting_swap_limit_preserves_the_existing_swap_policy(self):
        report = self.apply(swap=False)
        self.assertIsNone(report["memory_bounds"]["memory_swap_max_mib"])
        self.write_limits(swap="max")
        self.launch("acfs-scope", "agent", "--", "payload")
        self.assertFalse(any("MemorySwapMax" in arg for arg in self.records(self.log)[0]["options"]))
        self.assertEqual(len(self.records(self.payload_log)), 1)

    def test_default_profile_keeps_direct_fallback_and_no_memory_limit(self):
        report = self.cli("--resource-profile", "--apply-resource-profile")
        expected = {
            "enabled": False, "memory_max_mib": None, "memory_swap_max_mib": None,
            "on_unavailable": "direct-execution", "enforcement": "none"}
        self.assertEqual({key: report["memory_bounds"][key] for key in expected}, expected)
        self.assertFalse(any(property.startswith("MemoryMax=") for entry in report["classes"]
                             for property in entry["properties"]))
        self.env["FIXTURE_USER_MANAGER_STATUS"] = "1"
        self.env["FIXTURE_PAYLOAD_STATUS"] = "37"
        self.launch("acfs-scope", "agent", "--", "payload", status=37)
        self.assertEqual(self.records(self.log), [])
        self.assertEqual(len(self.records(self.payload_log)), 1)


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
