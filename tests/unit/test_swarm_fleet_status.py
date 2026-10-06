#!/usr/bin/env python3
"""Fleet observation through real journal validators and the fixed remote reader."""
from contextlib import redirect_stdout
import copy
import fcntl
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shlex
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("fleet_status", ROOT / "scripts/swarm-fleet-status.py")
status = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(status)
fleet, dispatch = status.fleet, status.dispatch


class FleetFixture:
    """Build journals using the actual launch and dispatch execution paths."""
    def __init__(self, root, *, launch=True, send=True, send_failure=None):
        self.root, self.calls = root, []
        self.known, self.key = b"PRIVATE-KNOWN-HOSTS-SENTINEL", b"PRIVATE-IDENTITY-SENTINEL"
        self.launch_path, self.work_path = root / "launch", root / "work"
        self.hosts = []
        for index, name in enumerate(("one", "two")):
            self.hosts.append({"id": name, "host": f"192.0.2.{index + 1}", "user": "ubuntu", "port": 22,
                "request": {"repo": "/home/ubuntu/project with ' quotes", "receipt": f"/home/ubuntu/{name}.launch.json",
                    "session": f"wave-{name}", "profile": "balanced", "workload": "standard", "accept_warnings": False,
                    "agents": [{"agent_name": name + "Fox", "agent_type": "claude"},
                               {"agent_name": name + "Lake", "agent_type": "codex"}]}})
        self.plan = fleet.build_plan({"schema": fleet.SPEC_SCHEMA, "hosts": self.hosts}, self.known,
                                     self.key, self.launch_path, 360)
        if launch:
            report, code = fleet.execute(self.plan, "launch", fleet.digest(fleet.encoded(self.plan)), self.native)
            assert code == 0, report
        else:
            with fleet.new_state(self.plan):
                pass
        self.work = None
        if send or send_failure:
            batches = {"schema": dispatch.SPEC_SCHEMA, "hosts": [
                {"id": h["id"], "batch": f"/home/ubuntu/{h['id']}/batch.json"} for h in self.hosts]}
            args = (str(self.launch_path), batches, self.known, self.key, str(self.work_path), 360)
            preview, code = dispatch.execute(*args, "preview", None, self.preview)
            assert code == 0, preview
            def sending(entry, mode):
                if mode == "send" and entry["host"]["id"] == send_failure:
                    raise fleet.Refused("fixture_transport_lost")
                return self.preview(entry, mode)
            report, code = dispatch.execute(*args, "send", preview["plan_sha256"], sending)
            assert code == (1 if send_failure else 0), report
            self.work = fleet.decode((self.work_path / "intent.json").read_bytes())["plan"]
        self.calls.clear()

    def targets(self, host):
        return [{"slot": slot, **agent, "pane": "%" + str(slot), "pane_pid": str(100 + slot),
                 "server_pid": "80", "session_id": "$1", "session_created": "1700000000"}
                for slot, agent in enumerate(host["request"]["agents"], 1)]

    def native(self, host, mode):
        value = {"schema": fleet.NATIVE_SCHEMA, "request": host["request"],
                 "work_dispatched": False, "authentication_verified": False, "agent_mail_registered": False,
                 "starts_agents": mode == "launch", "review_sha256": fleet.native_hash(host["request"])}
        if mode == "preview":
            value.update(status="preview", admission={"status": "pass", "recommendation": "launch",
                         "safe_agents": 10, "recommended_agents": 10})
        else:
            value.update(status="ready", targets=self.targets(host))
            if mode == "reconcile":
                value["reconciled_only"] = True
        return 0, fleet.encoded(value)

    def preview(self, entry, mode):
        if mode == "launch-status":
            return self.native(entry["host"], "reconcile")
        value = {"schema": dispatch.NATIVE_SCHEMA, "launch_receipt": entry["host"]["request"]["receipt"],
                 "batch": entry["batch"], "starts_agents": False, "agent_execution_verified": False,
                 "batch_review_sha256": "a" * 64}
        value["review_sha256"] = fleet.digest(fleet.encoded({"schema": dispatch.NATIVE_SCHEMA,
            "request": entry["host"]["request"], "targets": entry["targets"], "batch_sha256": "a" * 64}))
        if mode == "send":
            value.update(status="submitted", sends_prompt=True, deliveries=[
                {**d, "status": "submitted", "sends_prompt": True, "agent_execution_verified": False}
                for d in entry["deliveries"]])
        else:
            value.update(status="preview", sends_prompt=False, deliveries=[])
            for target in entry["targets"]:
                bead = f"bd-{entry['host']['id']}-{target['slot']}"
                request = {k: entry["host"]["request"][k] for k in ("repo", "session")}
                request.update(pane=target["pane"], agent_type=target["agent_type"], operation_id="op-" + bead,
                               bead_id=bead, packet_sha256="b" * 64, payload_sha256="c" * 64, payload_bytes=123)
                value["deliveries"].append({"slot": target["slot"], "request": request,
                    "receipt": "/home/ubuntu/" + bead + ".delivery.json", "action": "submit"})
        return 0, fleet.encoded(value)

    def observe(self, entry, mode):
        self.calls.append((entry["host"]["id"], mode))
        if mode == "launch-status":
            return self.native(entry["host"], "reconcile")
        if mode == "read-receipt":
            return 0, fleet.encoded({"schema": "acfs.packet-delivery.v1",
                "request": entry["delivery"]["request"], "target": "pane:recorded"})
        if mode == "query-receipt":
            request = entry["delivery"]["request"]
            return 0, fleet.encoded({"success": True, "session": request["session"],
                "operation": {"operation_id": request["operation_id"], "payload_sha256": request["payload_sha256"],
                    "payload_bytes": request["payload_bytes"], "status": "completed",
                    "admissions": [{"target": "pane:recorded", "state": "submitted"}]},
                "outcome": {"success": True, "targets": ["pane:recorded"], "successful": ["pane:recorded"], "failed": []}})
        if mode == "work-snapshot":
            request = entry["snapshot_request"]
            return 0, fleet.encoded({"schema": status.SNAPSHOT_SCHEMA, "request": request, "sha256": "d" * 64,
                "bytes": 500, "records": 4, "age_seconds": 5,
                "items": [{"bead_id": i, "status": "in_progress"} for i in request["bead_ids"]]})
        raise AssertionError("Observer crossed write boundary: " + mode)

    def collect(self, invoke=None, *, dispatch_state=True, max_age=300):
        return status.collect(str(self.launch_path), str(self.work_path) if dispatch_state else None,
                              self.known, self.key, invoke or self.observe, max_age)

    def snapshot(self):
        return {str(p.relative_to(self.root)): (p.read_bytes(), p.stat().st_mode, p.stat().st_mtime_ns)
                for p in self.root.rglob("*") if p.is_file()}


class StatusTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="acfs-status-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.fx = FleetFixture(self.root)

    def mutate(self, mode, change):
        def invoke(entry, action):
            code, raw = self.fx.observe(entry, action)
            if action == mode:
                value = fleet.decode(raw)
                change(value)
                raw = fleet.encoded(value)
            return code, raw
        return invoke

    def test_live_agents_submission_and_work_are_separate_and_read_only(self):
        before = self.fx.snapshot()
        report, code = self.fx.collect()
        self.assertEqual((code, report["status"]), (0, "observed"))
        self.assertEqual(report["summary"]["verified_live_agents"], 4)
        self.assertEqual(report["summary"]["confirmed_submissions"], 4)
        self.assertEqual(report["summary"]["recent_export_states"]["in_progress"], 4)
        self.assertTrue(report["read_only"])
        for field in ("starts_agents", "sends_prompts", "modifies_beads", "task_completion_verified"):
            self.assertIs(report[field], False)
        text = fleet.encoded(report).decode()
        self.assertNotIn("PRIVATE-", text)
        self.assertNotIn("/home/ubuntu/", text)
        self.assertEqual(before, self.fx.snapshot())
        self.assertEqual(set(m for _, m in self.fx.calls), {"launch-status", "read-receipt", "query-receipt", "work-snapshot"})

    def test_launch_only_does_not_query_work_or_receipts(self):
        report, code = self.fx.collect(dispatch_state=False)
        self.assertEqual(code, 0)
        self.assertIsNone(report["dispatch_plan_sha256"])
        self.assertEqual(self.fx.calls, [("one", "launch-status"), ("two", "launch-status")])

    def test_agent_loss_does_not_hide_historical_submission_or_closed_export(self):
        def invoke(entry, mode):
            if mode == "launch-status":
                self.fx.calls.append((entry["host"]["id"], mode))
                raise fleet.Refused("native_launch_unconfirmed")
            code, raw = self.fx.observe(entry, mode)
            if mode == "work-snapshot":
                data = fleet.decode(raw)
                for item in data["items"]:
                    item["status"] = "closed"
                raw = fleet.encoded(data)
            return code, raw
        report, code = self.fx.collect(invoke)
        self.assertEqual(code, 1)
        self.assertEqual(report["summary"]["verified_live_agents"], 0)
        self.assertEqual(report["summary"]["confirmed_submissions"], 4)
        self.assertEqual(report["summary"]["recent_export_states"]["closed"], 4)
        self.assertFalse(report["task_completion_verified"])

    def test_replaced_panes_cannot_become_original_agents(self):
        def change(value):
            value["targets"][0]["pane_pid"] = "999"
        report, code = self.fx.collect(self.mutate("launch-status", change))
        self.assertEqual(code, 1)
        self.assertEqual(report["hosts"][0]["agents"]["code"], "original_targets_changed")
        self.assertEqual(report["summary"]["confirmed_submissions"], 4)

    def test_adopted_native_sessions_are_not_original_launches(self):
        report, code = self.fx.collect(self.mutate("launch-status", lambda v: v.update(recovery_provenance={})))
        self.assertEqual(code, 1)
        self.assertEqual(report["hosts"][0]["agents"]["code"], "adopted_session_requires_manual_review")

    def test_forged_receipt_payload_is_unconfirmed_even_with_closed_work(self):
        def change(value):
            value["operation"]["payload_sha256"] = "0" * 64
        report, code = self.fx.collect(self.mutate("query-receipt", change))
        self.assertEqual(code, 1)
        self.assertEqual(report["summary"]["confirmed_submissions"], 0)
        self.assertEqual(report["hosts"][0]["deliveries"][0]["code"], "submission_not_confirmed")

    def test_native_intent_mismatch_prevents_ntm_receipt_query(self):
        def change(value):
            value["request"]["bead_id"] = "bd-other"
        report, code = self.fx.collect(self.mutate("read-receipt", change))
        self.assertEqual(code, 1)
        self.assertFalse(any(mode == "query-receipt" for _, mode in self.fx.calls))
        self.assertEqual(report["hosts"][0]["deliveries"][0]["code"], "native_receipt_mismatch")

    def test_stale_exports_never_contribute_recent_counts(self):
        report, code = self.fx.collect(self.mutate("work-snapshot", lambda v: v.update(age_seconds=301)))
        self.assertEqual(code, 1)
        self.assertEqual(report["summary"]["unobserved_work_items"], 4)
        self.assertEqual(sum(report["summary"]["recent_export_states"].values()), 0)
        self.assertEqual(report["hosts"][0]["work"]["status"], "stale")
        self.assertEqual(report["hosts"][0]["work"]["items"][0]["status"], "in_progress")

    def test_export_age_threshold_is_inclusive(self):
        report, code = self.fx.collect(self.mutate("work-snapshot", lambda v: v.update(age_seconds=300)))
        self.assertEqual(code, 0)
        self.assertEqual(report["hosts"][0]["work"]["status"], "recent")

    def test_unknown_missing_blocked_deferred_and_tombstone_need_attention(self):
        for state in ("unknown", "missing", "blocked", "deferred", "tombstone"):
            with self.subTest(state=state):
                def change(value):
                    value["items"][0]["status"] = state
                report, code = self.fx.collect(self.mutate("work-snapshot", change))
                self.assertEqual(code, 1)
                self.assertEqual(report["summary"]["recent_export_states"][state], 2)

    def test_snapshot_nonce_repo_item_ids_types_and_limits_are_bound(self):
        changes = [lambda v: v["request"].update(nonce="f" * 32),
                   lambda v: v["request"].update(repo="/other"),
                   lambda v: v["items"][0].update(bead_id="bd-other"),
                   lambda v: v["items"].reverse(),
                   lambda v: v.update(age_seconds=True), lambda v: v.update(age_seconds=-1),
                   lambda v: v.update(bytes=16777217), lambda v: v.update(records=100001),
                   lambda v: v.update(sha256="not-a-hash"), lambda v: v.update(items=[]),
                   lambda v: v["items"][0].update(status=["closed"]),
                   lambda v: v.update(secret="SHOULD-NOT-LEAK")]
        for change in changes:
            with self.subTest(change=changes.index(change)):
                report, code = self.fx.collect(self.mutate("work-snapshot", change))
                self.assertEqual(code, 1)
                self.assertEqual(report["hosts"][0]["work"]["status"], "unavailable")
                self.assertNotIn("SHOULD-NOT-LEAK", fleet.encoded(report).decode())

    def test_failed_host_does_not_prevent_other_host_observation(self):
        def invoke(entry, mode):
            if entry["host"]["id"] == "one":
                raise OSError("PRIVATE-REMOTE-DIAGNOSTIC")
            return self.fx.observe(entry, mode)
        report, code = self.fx.collect(invoke)
        self.assertEqual(code, 1)
        self.assertEqual(report["hosts"][1]["agents"]["status"], "live")
        self.assertEqual(report["summary"]["confirmed_submissions"], 2)
        self.assertNotIn("PRIVATE-REMOTE-DIAGNOSTIC", fleet.encoded(report).decode())

    def test_lost_dispatch_result_is_observed_without_repair_or_pending_send(self):
        parent = self.root / "interrupted"
        parent.mkdir()
        fx = FleetFixture(parent, send_failure="one")
        before = fx.snapshot()
        report, code = fx.collect()
        self.assertEqual(code, 1)
        self.assertFalse(report["hosts"][0]["local_dispatch_result_present"])
        self.assertEqual(report["summary"]["confirmed_submissions"], 2)
        self.assertEqual(report["hosts"][1]["work"]["status"], "not_attempted")
        self.assertEqual([mode for host, mode in fx.calls if host == "two"], ["launch-status"])
        self.assertEqual(before, fx.snapshot())

    def test_untouched_launches_never_contact_remote(self):
        parent = self.root / "untouched"
        parent.mkdir()
        fx = FleetFixture(parent, launch=False, send=False)
        before = fx.snapshot()
        report, code = fx.collect(dispatch_state=False)
        self.assertEqual(code, 1)
        self.assertEqual(fx.calls, [])
        self.assertTrue(all(r["agents"]["status"] == "not_attempted" for r in report["hosts"]))
        self.assertEqual(before, fx.snapshot())

    def test_missing_local_launch_result_can_be_inspected_without_adoption(self):
        parent = self.root / "launch-interrupted"
        parent.mkdir()
        fx = FleetFixture(parent, launch=False, send=False)
        with fleet.directory_fd(fx.launch_path, private=True) as fd:
            fleet.publish(fd, "one.attempt.json", fleet.host_intent(fx.plan, fx.hosts[0]))
        before = fx.snapshot()
        report, code = fx.collect(dispatch_state=False)
        self.assertEqual(code, 1)
        self.assertEqual(report["hosts"][0]["agents"]["status"], "live")
        self.assertFalse(report["hosts"][0]["agents"]["local_result_present"])
        self.assertEqual(fx.calls, [("one", "launch-status")])
        self.assertEqual(before, fx.snapshot())

    def test_changed_journal_during_remote_call_is_fatal(self):
        def invoke(entry, mode):
            result = self.fx.observe(entry, mode)
            (self.fx.work_path / "unexpected.json").write_bytes(b"{}")
            return result
        with self.assertRaisesRegex(fleet.Refused, "state_changed_during_operation"):
            self.fx.collect(invoke)
        self.assertEqual(len(self.fx.calls), 1)

    def test_corrupt_dispatch_or_other_fleet_fails_before_remote_calls(self):
        path = self.fx.work_path / "intent.json"
        original = path.read_bytes()
        for change in (lambda p: p.update(launch_plan_sha256="0" * 64),
                       lambda p: p["hosts"][0]["host"].update(host="192.0.2.88"),
                       lambda p: p["hosts"][0]["targets"][0].update(pane_pid="999"),
                       lambda p: p.update(timeout_seconds=True), lambda p: p.update(hosts=[None])):
            with self.subTest(change=change):
                value = fleet.decode(original)
                change(value["plan"])
                path.write_bytes(fleet.encoded(value))
                with self.assertRaises(fleet.Refused):
                    self.fx.collect()
                self.assertEqual(self.fx.calls, [])
        path.write_bytes(original)

    def test_foreign_trust_material_is_rejected_before_ssh(self):
        with self.assertRaisesRegex(fleet.Refused, "launch_transport_trust_mismatch"):
            status.collect(self.fx.launch_path, self.fx.work_path, b"different", self.fx.key, self.fx.observe)
        self.assertEqual(self.fx.calls, [])

    def test_busy_launch_or_dispatch_journal_is_not_observed(self):
        for path in (self.fx.launch_path, self.fx.work_path):
            with self.subTest(path=path), fleet.directory_fd(path, private=True) as fd:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with self.assertRaisesRegex(fleet.Refused, "fleet_operation_in_progress"):
                    self.fx.collect()
                self.assertEqual(self.fx.calls, [])

    def test_invalid_export_age_is_rejected_before_network(self):
        for age in (0, 86401, True):
            with self.subTest(age=age), self.assertRaisesRegex(fleet.Refused, "invalid_export_max_age"):
                self.fx.collect(max_age=age)
        self.assertEqual(self.fx.calls, [])

    def test_observer_transport_refuses_all_write_modes(self):
        for mode in ("send", "launch", "preview", "resume", "prepare", "reconcile"):
            with self.subTest(mode=mode), self.assertRaisesRegex(fleet.Refused, "status_operation_is_read_only"):
                status.remote_command({"host": self.fx.hosts[0]}, mode)

    def test_transport_retains_ssh_options_and_global_deadline(self):
        calls, now = [], [100.0]
        def runner(argv, timeout, env):
            calls.append((argv, timeout, env))
            now[0] += 9
            return 0, b"{}"
        with patch.object(status.time, "monotonic", side_effect=lambda: now[0]):
            invoke = status.transport(self.fx.known, self.fx.key, 10, 12, runner=runner, ssh="/usr/bin/true")
            invoke({"host": self.fx.hosts[0]}, "launch-status")
            invoke({"host": self.fx.hosts[1]}, "launch-status")
            with self.assertRaisesRegex(fleet.Refused, "status_deadline_exceeded"):
                invoke({"host": self.fx.hosts[0]}, "launch-status")
        self.assertEqual([call[1] for call in calls], [10, 3])
        args, _, env = calls[0]
        self.assertIn("StrictHostKeyChecking=yes", args)
        self.assertIn("ForwardAgent=no", args)
        self.assertIn("ProxyCommand=none", args)
        self.assertEqual(args[:5], ["/usr/bin/true", "-F", "/dev/null", "-T", "-n"])
        self.assertIn("--reconcile", args[-1])
        self.assertNotIn("--launch", args[-1])
        self.assertNotIn(self.fx.key.decode(), str(calls))
        self.assertNotIn("PYTHONPATH", env)

    def test_real_process_timeout_remains_bounded(self):
        start = time.monotonic()
        with self.assertRaisesRegex(fleet.Refused, "ssh_timeout"):
            fleet.capture([sys.executable, "-I", "-c", "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(30)"],
                          0.15, {"PATH": "/usr/bin:/bin"})
        self.assertLess(time.monotonic() - start, 3)

    def test_cli_rejects_write_flags_and_keeps_machine_readable_errors(self):
        result = subprocess.run([sys.executable, "-I", str(ROOT / "scripts/swarm-fleet-status.py"),
                                 "--launch-state", str(self.fx.launch_path), "--known-hosts", "/missing",
                                 "--identity-file", "/missing", "--send"], capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertIn(b"unrecognized arguments: --send", result.stderr)
        result = subprocess.run([sys.executable, "-I", str(ROOT / "scripts/swarm-fleet-status.py"),
                                 "--launch-state", str(self.fx.launch_path), "--known-hosts", "/missing",
                                 "--identity-file", "/missing"], capture_output=True, timeout=5)
        value = json.loads(result.stdout)
        self.assertEqual(result.returncode, 2)
        self.assertTrue(value["read_only"])
        self.assertFalse(value["sends_prompts"])
        self.assertNotIn(b"Traceback", result.stderr)


class RemoteExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="acfs-status-remote-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "project with ' quotes; $(false)"
        self.beads = self.repo / ".beads"
        self.beads.mkdir(parents=True)
        self.path = self.beads / "issues.jsonl"
        self.request = {"repo": str(self.repo), "bead_ids": ["bd-1", "bd-2", "bd-absent"], "nonce": "e" * 32}
        self.uid = 65534 if os.geteuid() == 0 else os.geteuid()
        self.gid = 65534 if os.geteuid() == 0 else os.getegid()
        for path in (self.root, self.repo, self.beads):
            path.chmod(0o700)
            if os.geteuid() == 0:
                os.chown(path, self.uid, self.gid)
        self.write(b'{"id":"bd-1","status":"closed","description":"PRIVATE-PROMPT-SENTINEL"}\n'
                   b'{"id":"bd-2","status":"in_progress"}\n{"id":"bd-unrelated","status":"open"}\n')

    def write(self, raw):
        self.path.write_bytes(raw)
        self.path.chmod(0o600)
        if os.geteuid() == 0:
            os.chown(self.path, self.uid, self.gid)

    def run_reader(self, request=None):
        options = {"user": self.uid, "group": self.gid, "extra_groups": []} if os.geteuid() == 0 else {}
        entry = {"snapshot_request": self.request if request is None else request}
        command = status.remote_command(entry, "work-snapshot")
        return subprocess.run(["/bin/bash", "--noprofile", "--norc", "-p", "-c", command],
                              env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"}, cwd="/", capture_output=True,
                              timeout=8, **options)

    def test_real_unprivileged_reader_and_literal_shell_transport(self):
        before = self.path.read_bytes()
        result = self.run_reader()
        self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(value["request"], self.request)
        self.assertEqual(value["sha256"], hashlib.sha256(before).hexdigest())
        self.assertEqual(value["records"], 3)
        self.assertEqual(value["items"], [{"bead_id": "bd-1", "status": "closed"},
            {"bead_id": "bd-2", "status": "in_progress"}, {"bead_id": "bd-absent", "status": "missing"}])
        self.assertNotIn(b"PRIVATE-PROMPT-SENTINEL", result.stdout + result.stderr)
        self.assertNotIn(b"bd-unrelated", result.stdout)
        self.assertEqual(before, self.path.read_bytes())
        self.assertEqual(sorted(p.name for p in self.beads.iterdir()), ["issues.jsonl"])

    def test_unknown_state_is_projected_not_trusted(self):
        self.write(b'{"id":"bd-1","status":{"secret":"PRIVATE-STATUS"}}\n')
        result = self.run_reader()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout)["items"][0]["status"], "unknown")
        self.assertNotIn(b"PRIVATE-STATUS", result.stdout)

    def test_duplicate_ids_keys_malformed_utf8_and_deep_records_are_refused(self):
        for raw in (b'{"id":"bd-1"}\n{"id":"bd-1"}\n', b'{"id":"bd-1","id":"bd-2"}\n',
                    b'{"id":"bd-other"}\nnot-json\n', b'{"id":"bd-1","title":"\xff"}\n',
                    b'{"id":"bd-1","value":NaN}\n',
                    b'{"id":"bd-1","value":' + b'[' * 40 + b'0' + b']' * 40 + b'}\n'):
            with self.subTest(raw=raw[:60]):
                self.write(raw)
                result = self.run_reader()
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout + result.stderr, b"")

    def test_bounded_file_and_record_sizes(self):
        for raw in (b" " * 1048577 + b"\n", b"\n" * 100001):
            with self.subTest(size=len(raw)):
                self.write(raw)
                result = self.run_reader()
                self.assertEqual(result.returncode, 2)
        self.write(b"")
        with self.path.open("wb") as stream:
            stream.truncate(16777217)
        self.assertEqual(self.run_reader().returncode, 2)

    def test_symlinked_export_is_refused(self):
        other = self.beads / "other.jsonl"
        self.path.rename(other)
        self.path.symlink_to(other)
        self.assertEqual(self.run_reader().returncode, 2)

    def test_symlinked_beads_directory_is_refused(self):
        other = self.repo / "other-beads"
        self.beads.rename(other)
        self.beads.symlink_to(other, target_is_directory=True)
        self.assertEqual(self.run_reader().returncode, 2)

    def test_fifo_is_refused_without_waiting_for_writer(self):
        self.path.rename(self.beads / "original.jsonl")
        os.mkfifo(self.path, 0o600)
        if os.geteuid() == 0:
            os.chown(self.path, self.uid, self.gid)
        start = time.monotonic()
        self.assertEqual(self.run_reader().returncode, 2)
        self.assertLess(time.monotonic() - start, 3)

    def test_group_writable_and_hardlinked_exports_are_refused(self):
        self.path.chmod(0o660)
        self.assertEqual(self.run_reader().returncode, 2)
        self.path.chmod(0o600)
        os.link(self.path, self.beads / "linked.jsonl")
        self.assertEqual(self.run_reader().returncode, 2)

    def test_future_clock_and_invalid_request_are_refused(self):
        future = time.time() + 60
        os.utime(self.path, (future, future))
        self.assertEqual(self.run_reader().returncode, 2)
        for change in (lambda v: v.update(repo=str(self.repo) + "/../other"),
                       lambda v: v.update(bead_ids=["bd-1", "bd-1"]), lambda v: v.update(nonce="x")):
            value = copy.deepcopy(self.request)
            change(value)
            self.assertEqual(self.run_reader(value).returncode, 2)

    def test_empty_export_explicitly_marks_every_requested_bead_missing(self):
        self.write(b"")
        result = self.run_reader()
        self.assertEqual(result.returncode, 0)
        value = json.loads(result.stdout)
        self.assertEqual(value["records"], 0)
        self.assertTrue(all(item["status"] == "missing" for item in value["items"]))


if __name__ == "__main__":
    unittest.main()
