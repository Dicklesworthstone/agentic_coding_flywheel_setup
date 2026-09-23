"""Exercise the actual inventory entrypoint with a bounded calculator fixture.

The fixture stands in for the installed sibling capacity.sh, not a production
injection option. The CI smoke additionally executes the real local calculator.
"""
import copy
import datetime as dt
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

SOURCE = Path(__file__).resolve().parents[2] / "scripts/lib/swarm_inventory.sh"


class InventoryProbeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="acfs-probe-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.script = self.root / "swarm_inventory.sh"
        shutil.copyfile(SOURCE, self.script)
        self.home = self.root / "home"
        self.home.mkdir()
        self.env = {**os.environ, "HOME": str(self.home)}
        self.report = {
            "schema_version": 1, "status": "pass", "generated_at": "1999-01-01T00:00:00Z",
            "host": {"cpu_count": 32, "mem_total_mib": 131072, "disk_available_mib": 262144},
            "tools": {"ntm": {"available": True}, "rch": {"available": True}},
            "assumptions": {"workload": "standard"},
            "capacity": {"recommended_agent_count": 20, "safe_agent_count": 30},
        }
        self.calculator()

    def calculator(self, payload=None, before="", after=""):
        text = json.dumps(self.report) if payload is None else payload
        (self.root / "capacity.sh").write_text(
            "#!/bin/bash\n"
            + "printf '%s\\n' \"$*\" > " + shlex.quote(str(self.root / "argv")) + "\n"
            + "/usr/bin/env > " + shlex.quote(str(self.root / "environment")) + "\n"
            + before + "\ncat <<'CAPACITY_JSON'\n" + text + "\nCAPACITY_JSON\n" + after + "\n")

    def run_cli(self, *args, code=0, env=None):
        result = subprocess.run(["/bin/bash", str(self.script), "--json", *map(str, args)],
                                capture_output=True, text=True, env=env or self.env, timeout=15)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result

    def probe(self, *args, code=0):
        result = self.run_cli("probe-local", "--host-id", "worker-a", *args, code=code)
        return json.loads(result.stdout)

    def base(self):
        data = self.probe()
        data["defaults"] = {"workload": "standard", "stale_after_hours": 24}
        host = data["hosts"][0]
        host["last_probe_at"] = "2000-01-01T00:00:00Z"
        host["display_name"] = "Operator chosen label"
        host["manual_tags"] = ["primary"]
        host["notes"] = "keep this note"
        host["capacity"]["custom_limit_reason"] = "operator managed"
        host["resources"]["disk_class"] = "fast"
        host["rch"] = {"controller": True, "workers_total": 4}
        host["ru"] = {"can_sync_repos": True}
        host["ntm"]["preferred_labels"] = ["work"]
        other = copy.deepcopy(host)
        other["id"] = "worker-b"
        data["hosts"].append(other)
        data["fleet_note"] = "preserve"
        path = self.root / "fleet.json"
        path.write_text(json.dumps(data))
        return path, data

    def test_measures_new_host_with_offline_default_and_fresh_timestamp(self):
        before = dt.datetime.now(dt.timezone.utc) - dt.timedelta(seconds=1)
        snapshot = self.probe()
        h = snapshot["hosts"][0]
        self.assertEqual(h["id"], "worker-a")
        self.assertEqual(h["resources"], self.report["host"])
        self.assertEqual(h["capacity"]["recommended_agents"], 20)
        self.assertEqual(h["capacity"]["safe_agents"], 30)
        self.assertEqual(h["role"], "swarm-worker")
        self.assertIs(h["ntm"]["can_launch"], False)
        self.assertFalse(h["local_observation"]["live_admission_checked"])
        self.assertGreaterEqual(dt.datetime.fromisoformat(h["last_probe_at"].replace("Z", "+00:00")), before)
        self.assertEqual(h["last_probe_at"], snapshot["updated_at"])
        self.assertEqual(list(self.home.iterdir()), [])
        self.assertEqual((self.root / "argv").read_text().strip(), "--json --workload standard")

    def test_explicit_new_host_launch_opt_in_flows_into_placement(self):
        snapshot = self.probe("--allow-launch", "--role", "swarm-controller")
        self.assertTrue(snapshot["hosts"][0]["ntm"]["can_launch"])
        path = self.root / "snapshot.json"
        path.write_text(json.dumps(snapshot))
        plan = json.loads(self.run_cli("plan", "--inventory", path, "--agents", "10").stdout)
        self.assertEqual(plan["assigned_agents"], 10)
        self.assertEqual(plan["allocations"][0]["host_id"], "worker-a")
        self.assertEqual(plan["unassigned_agents"], 0)

    def test_refresh_preserves_other_hosts_metadata_and_launch_veto(self):
        path, original = self.base()
        before = path.read_bytes()
        snapshot = self.probe("--inventory", path)
        h = snapshot["hosts"][0]
        self.assertEqual(snapshot["hosts"][1], original["hosts"][1])
        for field in ("display_name", "manual_tags", "notes", "rch", "ru", "role", "status"):
            self.assertEqual(h[field], original["hosts"][0][field])
        self.assertFalse(h["ntm"]["can_launch"])
        self.assertEqual(h["ntm"]["preferred_labels"], ["work"])
        self.assertEqual(h["resources"]["disk_class"], "fast")
        self.assertEqual(h["capacity"]["custom_limit_reason"], "operator managed")
        self.assertNotEqual(h["last_probe_at"], original["hosts"][0]["last_probe_at"])
        self.assertEqual(snapshot["fleet_note"], "preserve")
        self.assertEqual(path.read_bytes(), before)

    def test_policy_options_cannot_reclassify_existing_host(self):
        path, data = self.base()
        data["hosts"][0].update({"role": "rch-worker", "status": "disabled"})
        path.write_text(json.dumps(data))
        for args in (("--allow-launch",), ("--role", "swarm-worker")):
            self.probe("--inventory", path, *args, code=2)
        h = self.probe("--inventory", path)["hosts"][0]
        self.assertEqual((h["role"], h["status"]), ("rch-worker", "disabled"))
        self.assertFalse(h["ntm"]["can_launch"])

    def test_preserves_existing_workload_unless_explicitly_changed(self):
        path, data = self.base()
        data["hosts"][0]["capacity"]["workload"] = "heavy"
        path.write_text(json.dumps(data))
        self.report["assumptions"]["workload"] = "heavy"
        self.calculator()
        self.assertEqual(self.probe("--inventory", path)["hosts"][0]["capacity"]["workload"], "heavy")
        self.assertEqual((self.root / "argv").read_text().strip(), "--json --workload heavy")
        self.report["assumptions"]["workload"] = "light"
        self.calculator()
        self.assertEqual(self.probe("--inventory", path, "--workload", "light")["hosts"][0]["capacity"]["workload"], "light")

    def test_new_host_uses_explicit_inventory_workload_default(self):
        path, data = self.base()
        data["hosts"] = []
        data["defaults"]["workload"] = "heavy"
        path.write_text(json.dumps(data))
        self.report["assumptions"]["workload"] = "heavy"
        self.calculator()
        self.assertEqual(self.probe("--inventory", path)["hosts"][0]["capacity"]["workload"], "heavy")

    def test_missing_ntm_withdraws_capability_and_blocks_new_opt_in(self):
        path, data = self.base()
        data["hosts"][0]["ntm"]["can_launch"] = True
        path.write_text(json.dumps(data))
        self.report["tools"]["ntm"]["available"] = False
        self.calculator()
        self.assertFalse(self.probe("--inventory", path)["hosts"][0]["ntm"]["can_launch"])
        self.probe("--allow-launch", code=2)
        self.assertFalse(self.probe()["hosts"][0]["ntm"]["can_launch"])

    def test_build_only_and_disabled_new_roles_cannot_opt_in(self):
        for role in ("rch-worker", "disabled"):
            self.probe("--role", role, "--allow-launch", code=2)
            h = self.probe("--role", role)["hosts"][0]
            self.assertFalse(h["ntm"]["can_launch"])
            self.assertEqual(h["role"], role)

    def test_zero_capacity_and_warn_status_are_recorded_not_replaced(self):
        for status, count in (("warn", 20), ("fail", 0)):
            self.report["status"] = status
            self.report["capacity"] = {"recommended_agent_count": count, "safe_agent_count": count}
            self.calculator()
            h = self.probe()["hosts"][0]
            self.assertEqual(h["capacity"]["recommended_agents"], count)
            self.assertEqual(h["local_observation"]["capacity_status"], status)

    def test_child_receives_no_fixture_overrides_credentials_or_startup_settings(self):
        self.env.update({"ACFS_CAPACITY_CPU_COUNT": "99999", "ACFS_CAPACITY_MEM_TOTAL_KB": "99999",
                         "ACFS_CAPACITY_NTM_AVAILABLE": "true", "ACFS_CAPACITY_BIN_DIR": "/secret/tools",
                         "ACFS_CAPACITY_DISK_PATH": "/secret/mount", "HTTP_PROXY": "http://secret.invalid",
                         "AGENT_MAIL_TOKEN": "never-emit-this-secret", "PYTHONPATH": "/secret/modules"})
        self.probe()
        child = (self.root / "environment").read_text()
        for key in ("ACFS_CAPACITY_", "HTTP_PROXY", "AGENT_MAIL_TOKEN", "PYTHONPATH"):
            self.assertNotIn(key, child)
        self.assertIn("PATH=/usr/sbin:/usr/bin:/sbin:/bin", child)

    def test_raw_report_metadata_and_stderr_never_leak_into_snapshot(self):
        self.report["diagnostic"] = {"hostname": "private-host", "token": "never-emit-this-secret"}
        self.calculator(before="echo never-emit-this-secret >&2")
        result = self.run_cli("probe-local", "--host-id", "worker-a")
        self.assertNotIn("never-emit-this-secret", result.stdout + result.stderr)
        self.assertNotIn("private-host", result.stdout + result.stderr)
        self.assertNotIn(str(self.home), result.stdout)

    def test_explicit_disk_filesystem_is_selected_without_disclosing_its_path(self):
        disk = self.root / "project-volume"
        disk.mkdir()
        self.env["ACFS_CAPACITY_DISK_PATH"] = "/unrelated-volume"
        snapshot = self.probe("--disk-path", disk)
        self.assertIn("ACFS_CAPACITY_DISK_PATH=" + str(disk), (self.root / "environment").read_text())
        self.assertNotIn(str(disk), json.dumps(snapshot))

    def test_missing_disk_filesystem_is_rejected_before_measurement(self):
        self.probe("--disk-path", self.root / "missing-volume", code=2)
        self.assertFalse((self.root / "argv").exists())

    def test_bad_report_counts_schema_workload_and_flags_are_rejected(self):
        cases = [("capacity", "safe_agent_count", value) for value in (None, True, -1, 1.5, "30", 1000001)]
        cases += [("host", "mem_total_mib", 0), ("host", "cpu_count", False),
                  ("capacity", "recommended_agent_count", 31), ("assumptions", "workload", "heavy")]
        original = copy.deepcopy(self.report)
        for section, key, value in cases:
            with self.subTest(section=section, key=key, value=value):
                self.report = copy.deepcopy(original)
                self.report[section][key] = value
                self.calculator()
                self.probe(code=2)
        for change in ({"schema_version": True}, {"schema_version": 2}, {"status": "unknown"}, {"status": "fail"}):
            self.report = {**original, **change}
            self.calculator()
            self.probe(code=2)
        self.report = copy.deepcopy(original)
        self.report["tools"]["ntm"]["available"] = "true"
        self.calculator()
        self.probe(code=2)

    def test_bad_json_duplicate_keys_nonfinite_unicode_and_output_limit_fail(self):
        valid = json.dumps(self.report)
        for text in ("SECRET-not-json", valid[:-1], valid + valid,
                     valid[:-1] + ',"schema_version":1}',
                     valid[:-1] + ',"unused":NaN}', valid[:-1] + ',"unused":"\\ud800"}',
                     valid + " " * 65536, "[" * 40 + "0" + "]" * 40):
            self.calculator(payload=text)
            self.assertEqual(self.probe(code=2)["error_code"], "probe_failed")

    def test_nonzero_producer_cannot_publish_valid_prefix(self):
        target = self.root / "snapshot.json"
        self.calculator(after="exit 1")
        self.probe("--output", target, code=2)
        self.assertFalse(target.exists())

    def test_hung_producer_and_descendants_are_bounded(self):
        self.calculator(before="/bin/sleep 30 & wait")
        start = time.monotonic()
        self.probe(code=2)
        self.assertLess(time.monotonic() - start, 13)

    def test_missing_and_symlinked_calculators_are_rejected(self):
        source = self.root / "capacity.sh"
        moved = self.root / "calculator.saved"
        source.rename(moved)
        self.probe(code=2)
        source.symlink_to(moved)
        self.probe(code=2)

    def test_invalid_base_inventory_fails_before_measurement(self):
        path = self.root / "invalid.json"
        path.write_text('{"schema_version":1,"hosts":[],"token":"SECRET"}')
        result = self.run_cli("probe-local", "--host-id", "worker-a", "--inventory", path, code=2)
        self.assertNotIn("SECRET", result.stdout + result.stderr)
        self.assertFalse((self.root / "argv").exists())

    def test_output_is_private_complete_and_importable(self):
        path = self.root / "snapshot.json"
        result = self.probe("--allow-launch", "--output", path)
        self.assertEqual(result["output_file"], str(path))
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.run_cli("validate", "--inventory", path)
        installed = self.root / "installed.inventory.json"
        self.run_cli("import", "--input", path, "--output", installed)
        report = json.loads(self.run_cli("report", "--inventory", installed).stdout)
        self.assertEqual(report["summary"]["recommended_agents_total"], 20)
        self.assertEqual(list(self.root.glob(".swarm-probe-*")), [])

    def test_output_never_replaces_files_symlinks_directories_or_fifos(self):
        regular = self.root / "existing.json"
        regular.write_text("user work")
        link = self.root / "link.json"
        link.symlink_to(regular)
        dangling = self.root / "dangling.json"
        dangling.symlink_to(self.root / "absent")
        fifo = self.root / "pipe"
        os.mkfifo(fifo)
        for path in (regular, link, dangling, self.home, fifo):
            with self.subTest(path=path):
                self.probe("--output", path, code=2)
        self.assertEqual(regular.read_text(), "user work")
        self.assertTrue(link.is_symlink())
        self.assertEqual(list(self.home.iterdir()), [])

    def test_output_parent_links_and_missing_directories_are_rejected(self):
        link = self.root / "linked-home"
        link.symlink_to(self.home, target_is_directory=True)
        self.probe("--output", link / "new.json", code=2)
        self.probe("--output", self.root / "missing" / "new.json", code=2)
        self.assertEqual(list(self.home.iterdir()), [])
        self.assertFalse((self.root / "missing").exists())

    def test_destination_created_during_measurement_is_preserved(self):
        target = self.root / "concurrent.json"
        self.calculator(before="printf 'concurrent work' > " + shlex.quote(str(target)))
        self.probe("--output", target, code=2)
        self.assertEqual(target.read_text(), "concurrent work")

    def test_existing_inventory_cannot_be_overwritten_by_probe(self):
        path, _ = self.base()
        before = path.read_bytes()
        self.probe("--inventory", path, "--output", path, code=2)
        self.assertEqual(path.read_bytes(), before)

    def test_invalid_options_never_turn_probe_into_mutation(self):
        target = self.root / "unused.json"
        for args in (("probe-local",), ("probe-local", "--host-id", "bad/host"),
                     ("probe-local", "--host-id", "a", "--agents", "2"),
                     ("probe-local", "--host-id", "a", "--input", "source.json"),
                     ("probe-local", "--host-id", "a", "import", "--output", target),
                     ("report", "--host-id", "a"), ("plan", "--agents", "2", "--allow-launch"),
                     ("probe-local", "--host-id", "a", "--role", "root"),
                     ("probe-local", "--host-id", "a", "--artifact-dir", self.root / "error")):
            self.run_cli(*args, code=2)
        self.assertFalse((self.root / "argv").exists())
        self.assertFalse(target.exists())

    def test_environment_inventory_is_not_implicitly_loaded_or_modified(self):
        path = self.root / "ignored.json"
        path.write_text("not valid JSON")
        self.env["ACFS_SWARM_INVENTORY_FILE"] = str(path)
        self.assertEqual(len(self.probe()["hosts"]), 1)
        self.assertEqual(path.read_text(), "not valid JSON")


def live_capacity_smoke():
    """Read the real Linux runner without fixtures, services, or agent calls."""
    capacity = SOURCE.with_name("capacity.sh")
    if not capacity.is_file():
        raise SystemExit("The real capacity calculator is required for --live")
    with tempfile.TemporaryDirectory(prefix="acfs-real-probe-") as directory:
        root = Path(directory)
        output = root / "measured.json"
        env = {**os.environ, "ACFS_CAPACITY_CPU_COUNT": "999999",
               "ACFS_CAPACITY_DISK_AVAILABLE_KB": "999999999999",
               "ACFS_CAPACITY_MEM_TOTAL_KB": "999999999999"}

        def run(*args, code=0):
            result = subprocess.run(["/bin/bash", str(SOURCE), *map(str, args)],
                                    env=env, capture_output=True, text=True, timeout=15)
            assert result.returncode == code, result.stdout + result.stderr
            return json.loads(result.stdout)

        run("probe-local", "--host-id", "local-a", "--workload", "heavy", "--disk-path", root, "--output", output)
        measured = json.loads(output.read_text())
        clean_env = {"HOME": os.path.realpath(os.environ["HOME"]), "PATH": "/usr/sbin:/usr/bin:/sbin:/bin",
                     "LC_ALL": "C", "LANG": "C", "TERM": "dumb", "ACFS_CAPACITY_DISK_PATH": str(root)}
        direct = subprocess.run(["/bin/bash", str(capacity), "--json", "--workload", "heavy"],
                                env=clean_env, capture_output=True, text=True, timeout=15, check=True)
        direct = json.loads(direct.stdout)
        local = measured["hosts"][0]
        for key in ("cpu_count", "mem_total_mib"):
            assert local["resources"][key] == direct["host"][key]
        assert local["resources"]["cpu_count"] != 999999
        assert local["capacity"]["workload"] == "heavy"
        assert 0 <= local["capacity"]["recommended_agents"] <= local["capacity"]["safe_agents"]
        assert not local["ntm"]["can_launch"]
        run("validate", "--inventory", output, "--json")
        other = {**copy.deepcopy(local), "id": "other-b", "last_probe_at": "2000-01-01T00:00:00Z"}
        measured["hosts"].append(other)
        output.write_text(json.dumps(measured))
        before = output.read_bytes()
        refreshed = root / "refreshed.json"
        run("probe-local", "--host-id", "local-a", "--inventory", output, "--disk-path", root, "--output", refreshed)
        assert output.read_bytes() == before
        assert json.loads(refreshed.read_text())["hosts"][1] == other
        plan = run("plan", "--inventory", refreshed, "--agents", "1", "--workload", "heavy", "--json", code=1)
        assert plan["assigned_agents"] == 0 and plan["unassigned_agents"] == 1
    print("LIVE_CAPACITY_SMOKE=pass")


if __name__ == "__main__":
    if sys.argv[1:] == ["--live"]:
        live_capacity_smoke()
    else:
        unittest.main(verbosity=2)
