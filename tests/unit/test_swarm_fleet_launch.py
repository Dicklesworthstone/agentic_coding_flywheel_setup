#!/usr/bin/env python3
"""Fleet execution contracts, real filesystem/child-process tests; no live VPSes."""
import copy
import importlib.util
import ipaddress
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "swarm-fleet-launch.py"
spec = importlib.util.spec_from_file_location("fleet_launch", SCRIPT)
fleet = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fleet)


def host(index=1):
    return {"id": f"worker-{index}", "host": f"worker-{index}.example.com", "user": "ubuntu", "port": 22,
            "request": {"repo": "/data/projects/myapp", "session": "wave-one",
                        "receipt": "/home/ubuntu/receipts/wave-one.json", "profile": "balanced",
                        "workload": "standard", "accept_warnings": False,
                        "agents": [{"agent_name": f"Agent{index}", "agent_type": "claude"}]}}


def specification(count=2):
    return {"schema": fleet.SPEC_SCHEMA, "hosts": [host(i) for i in range(1, count + 1)]}


def native_response(selected, mode, pane="%42"):
    req = selected["request"]
    result = {"schema": fleet.NATIVE_SCHEMA, "request": req, "starts_agents": mode == "launch",
              "work_dispatched": False, "authentication_verified": False, "agent_mail_registered": False,
              "review_sha256": fleet.native_hash(req)}
    if mode == "preview":
        result.update(status="preview", admission={"status": "pass", "recommendation": "launch",
                                                   "recommended_agents": 32, "safe_agents": 32})
    else:
        result.update(status="ready", reconciled_only=mode == "reconcile", targets=[{
            "slot": i, **agent, "pane": "%" + str(int(pane[1:]) + i - 1), "pane_pid": str(200 + i),
            "server_pid": "100", "session_id": "$3", "session_created": "1789000000",
        } for i, agent in enumerate(req["agents"], 1)])
    return result


class FixtureTransport:
    """An inert native-launch protocol peer; calls are recorded verbatim."""
    def __init__(self, transform=None):
        self.calls = []
        self.transform = transform

    def __call__(self, selected, mode):
        self.calls.append((selected["id"], mode))
        result = native_response(selected, mode)
        if self.transform:
            result = self.transform(selected, mode, result)
        if isinstance(result, Exception):
            raise result
        if isinstance(result, tuple):
            return result
        return 0, fleet.encoded(result)


class FleetTests(unittest.TestCase):
    def setUp(self):
        # Retain fixtures on failure/success for inspection; no destructive cleanup.
        self.directory = Path(tempfile.mkdtemp(prefix="acfs-fleet-launch-test-"))
        self.state = self.directory / "launch"
        self.spec = specification()
        self.plan = fleet.build_plan(self.spec, b"reviewed host keys\n", b"private key\n", self.state, 360)
        self.approval = fleet.digest(fleet.encoded(self.plan))

    def run_fleet(self, mode="preview", invoke=None, approval=None):
        return fleet.execute(self.plan, mode, self.approval if approval is None else approval,
                             invoke or FixtureTransport())

    def test_preview_all_hosts_runs_admission_only_and_writes_nothing(self):
        peer = FixtureTransport()
        result, code = self.run_fleet(invoke=peer)
        self.assertEqual(code, 0)
        self.assertEqual(result["status"], "preview")
        self.assertFalse(result["starts_agents"])
        self.assertEqual(result["requested_new_agents"], 2)
        self.assertEqual(peer.calls, [("worker-1", "preview"), ("worker-2", "preview")])
        self.assertFalse(self.state.exists())

    def test_successful_fleet_launch_records_private_intents_before_each_remote_operation(self):
        def verify(selected, mode, result):
            if mode == "launch":
                intent = json.loads((self.state / "intent.json").read_text())
                attempt = json.loads((self.state / (selected["id"] + ".attempt.json")).read_text())
                self.assertEqual(intent["plan"], self.plan)
                self.assertEqual(attempt, fleet.host_intent(self.plan, selected))
                self.assertFalse((self.state / (selected["id"] + ".result.json")).exists())
            return result
        peer = FixtureTransport(verify)
        result, code = self.run_fleet("launch", peer)
        self.assertEqual(code, 0)
        self.assertEqual(result["status"], "ready")
        self.assertEqual(peer.calls, [("worker-1", "preview"), ("worker-2", "preview"),
                                     ("worker-1", "launch"), ("worker-2", "launch")])
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode), 0o700)
        for item in self.state.iterdir():
            self.assertEqual(stat.S_IMODE(item.stat().st_mode), 0o600)
        self.assertEqual(len(list(self.state.iterdir())), 5)

    def test_wrong_or_missing_approval_never_opens_a_remote_connection(self):
        for approval in (None, "0" * 64, True, ""):
            peer = FixtureTransport()
            with self.assertRaisesRegex(fleet.Refused, "approval_mismatch"):
                fleet.execute(self.plan, "launch", approval, peer)
            self.assertEqual(peer.calls, [])
            self.assertFalse(self.state.exists())

    def test_preview_failure_on_any_host_prevents_all_launches_and_all_state_writes(self):
        peer = FixtureTransport(lambda h, m, r: (2, b"private-token") if h["id"] == "worker-2" else r)
        report, code = self.run_fleet("launch", peer)
        self.assertEqual(code, 1)
        self.assertEqual(report["status"], "blocked")
        self.assertTrue(all(mode == "preview" for _, mode in peer.calls))
        self.assertFalse(self.state.exists())
        self.assertNotIn("private-token", json.dumps(report))

    def test_uncertain_first_launch_stops_later_hosts_and_retains_attempt(self):
        peer = FixtureTransport(lambda h, m, r: fleet.Refused("ssh_timeout") if m == "launch" else r)
        report, code = self.run_fleet("launch", peer)
        self.assertEqual(code, 1)
        self.assertEqual(report["status"], "unconfirmed")
        self.assertEqual(report["hosts"][1]["status"], "not_attempted")
        self.assertTrue((self.state / "worker-1.attempt.json").exists())
        self.assertFalse((self.state / "worker-2.attempt.json").exists())
        self.assertNotIn(("worker-2", "launch"), peer.calls)

    def test_partial_second_launch_retains_first_confirmed_session_without_rollback(self):
        peer = FixtureTransport(lambda h, m, r: (255, b"lost response") if h["id"] == "worker-2" and m == "launch" else r)
        report, code = self.run_fleet("launch", peer)
        self.assertEqual(code, 1)
        self.assertEqual(report["hosts"][0]["status"], "ready")
        self.assertTrue((self.state / "worker-1.result.json").exists())
        self.assertTrue((self.state / "worker-2.attempt.json").exists())
        self.assertFalse((self.state / "worker-2.result.json").exists())

    def test_existing_state_never_relaunches_or_previews(self):
        self.run_fleet("launch")
        before = {p.name: p.read_bytes() for p in self.state.iterdir()}
        for mode in ("preview", "launch"):
            peer = FixtureTransport()
            with self.assertRaisesRegex(fleet.Refused, "state_already_exists"):
                self.run_fleet(mode, peer)
            self.assertEqual(peer.calls, [])
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.state.iterdir()})

    def test_concurrent_state_creation_is_not_overwritten_after_admission(self):
        def collide(h, mode, result):
            if h["id"] == "worker-2":
                self.state.mkdir(mode=0o700)
                (self.state / "owner.txt").write_text("other operation")
            return result
        peer = FixtureTransport(collide)
        with self.assertRaises(FileExistsError):
            self.run_fleet("launch", peer)
        self.assertEqual((self.state / "owner.txt").read_text(), "other operation")
        self.assertFalse((self.state / "intent.json").exists())
        self.assertTrue(all(m == "preview" for _, m in peer.calls))

    def test_cancellation_after_intent_never_advertises_later_launch(self):
        peer = FixtureTransport(lambda h, m, r: fleet.Interrupted(signal.SIGINT) if m == "launch" else r)
        with self.assertRaises(fleet.Interrupted):
            self.run_fleet("launch", peer)
        self.assertTrue((self.state / "worker-1.attempt.json").exists())
        self.assertFalse((self.state / "worker-2.attempt.json").exists())

    def test_spec_and_host_key_identity_state_location_and_timeout_are_approval_bound(self):
        variants = []
        for key, value in (("known_hosts_sha256", "a" * 64), ("identity_sha256", "b" * 64),
                           ("state_directory", str(self.directory / "other")), ("timeout_seconds", 300)):
            candidate = copy.deepcopy(self.plan)
            candidate[key] = value
            variants.append(candidate)
        candidate = copy.deepcopy(self.plan)
        candidate["spec"]["hosts"][0]["request"]["agents"][0]["agent_type"] = "codex"
        variants.append(candidate)
        for variant in variants:
            with self.assertRaisesRegex(fleet.Refused, "approval_mismatch"):
                fleet.execute(variant, "launch", self.approval, FixtureTransport())
        self.assertFalse(self.state.exists())

    def test_plan_detaches_input_and_preserves_explicit_order(self):
        self.spec["hosts"][0]["request"]["agents"][0]["agent_name"] = "changed"
        self.assertEqual(self.plan["spec"]["hosts"][0]["request"]["agents"][0]["agent_name"], "Agent1")
        reversed_spec = specification()
        reversed_spec["hosts"].reverse()
        self.assertNotEqual(self.plan, fleet.build_plan(reversed_spec, b"reviewed host keys\n", b"private key\n", self.state, 360))

    def test_mixed_provider_original_slots_are_preserved(self):
        self.spec["hosts"][0]["request"]["agents"] = [
            {"agent_name": "Coder", "agent_type": "codex"}, {"agent_name": "Reviewer", "agent_type": "claude"}]
        self.plan = fleet.build_plan(self.spec, b"hosts", b"key", self.state, 360)
        self.approval = fleet.digest(fleet.encoded(self.plan))
        report, code = self.run_fleet("launch")
        self.assertEqual(code, 0)
        self.assertEqual([t["agent_name"] for t in report["hosts"][0]["targets"]], ["Coder", "Reviewer"])

    def test_reports_do_not_echo_endpoints_paths_ssh_keys_or_raw_diagnostics(self):
        def private(h, m, r):
            r["private"] = "SECRET-RAW-PAYLOAD"
            r["launch_command"] = "touch /tmp/SHOULD-NOT-EXECUTE"
            return r
        report, code = self.run_fleet("launch", FixtureTransport(private))
        self.assertEqual(code, 0)
        text = json.dumps(report)
        for forbidden in ("example.com", "/home/ubuntu", "/data/projects", "private key", "SECRET-RAW", "SHOULD-NOT"):
            self.assertNotIn(forbidden, text)


class ValidationTests(unittest.TestCase):
    def test_no_inventory_target_totals_or_implicit_launch_selection(self):
        for value in ({"schema_version": 1, "allocations": []}, {"schema": fleet.SPEC_SCHEMA, "hosts": []},
                      {"schema": fleet.SPEC_SCHEMA, "hosts": [host()], "agents": 25}):
            with self.assertRaises(fleet.Refused):
                fleet.validate_spec(value)

    def test_endpoint_and_identity_validation(self):
        variants = [("host", "-oProxyCommand=touch"), ("host", "user@host"), ("host", "https://host"),
                    ("host", "LOCALHOST"), ("host", "bad\nhost"), ("host", "127.1"), ("host", "0.0.0.0"),
                    ("host", "fe80::1%eth0"), ("port", True), ("port", 0), ("port", 65536),
                    ("user", "root"), ("user", "ubuntu -o bad"), ("id", "../bad")]
        for key, value in variants:
            candidate = specification(1)
            candidate["hosts"][0][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(fleet.Refused):
                fleet.validate_spec(candidate)
        for address in ("localhost", "127.0.0.1", "::1", "192.0.2.1", "worker-a.example.com"):
            candidate = specification(1)
            candidate["hosts"][0]["host"] = address
            fleet.validate_spec(candidate)

    def test_duplicate_host_different_user_port_and_ipv4_mapped_alias_rejected(self):
        for addresses in (("worker.example.com", "worker.example.com"), ("127.0.0.1", str(ipaddress.ip_address("::ffff:7f00:1")))):
            candidate = specification()
            candidate["hosts"][0]["host"], candidate["hosts"][1]["host"] = addresses
            candidate["hosts"][1].update(user="other", port=2222)
            with self.assertRaisesRegex(fleet.Refused, "duplicate_endpoint"):
                fleet.validate_spec(candidate)

    def test_duplicate_agent_names_across_hosts_are_rejected_case_insensitively(self):
        candidate = specification()
        candidate["hosts"][1]["request"]["agents"][0]["agent_name"] = "agent1"
        with self.assertRaisesRegex(fleet.Refused, "duplicate_fleet_agent"):
            fleet.validate_spec(candidate)

    def test_strict_native_request_paths_names_providers_and_limits(self):
        for key, value in (("repo", "/"), ("repo", "relative"), ("receipt", "/home/../other"),
                           ("repo", "/double//slash"), ("receipt", "/tmp/file\x00"),
                           ("session", "--option"), ("session", "prefix--option"),
                           ("profile", "unknown"), ("workload", "unknown"), ("accept_warnings", "true"),
                           ("agents", []), ("agents", [{"agent_name": "A", "agent_type": "agy"}])):
            candidate = specification(1)
            candidate["hosts"][0]["request"][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(fleet.Refused):
                fleet.validate_spec(candidate)
        with self.assertRaises(fleet.Refused):
            fleet.validate_spec(specification(17))
        candidate = specification(16)
        for i, h in enumerate(candidate["hosts"]):
            h["request"]["agents"] = [{"agent_name": f"Agent{i}_{j}", "agent_type": "claude"} for j in range(32)]
        with self.assertRaisesRegex(fleet.Refused, "fleet_agent_limit"):
            fleet.validate_spec(candidate)

    def test_json_duplicate_decoded_keys_unicode_and_complexity_bounds(self):
        for raw in (b'{"a":1,"a":2}', b'{"a":1,"\\u0061":2}', b'{"a":NaN}', b'{"a":1e999}',
                    b'{"a":"\\ud800"}', b'{} {}', b'\xff', b'[' * 34 + b'0' + b']' * 34,
                    b' ' * (fleet.LIMIT + 1)):
            with self.subTest(raw=raw[:60]), self.assertRaises(fleet.Refused):
                fleet.decode(raw)
        self.assertEqual(fleet.decode(b'{"a":{"x":1},"b":{"x":2}}'), {"a": {"x": 1}, "b": {"x": 2}})

    def test_native_preview_cannot_hide_reused_receipts_or_missing_admission(self):
        for key, value in (("status", "ready"), ("reconciled_only", True), ("starts_agents", True),
                           ("review_sha256", "0" * 64), ("admission", {}), ("work_dispatched", True)):
            peer = FixtureTransport(lambda h, m, r: {**r, key: value})
            self.assertEqual(fleet.remote_result(host(), "preview", peer)["status"], "unconfirmed")

    def test_warning_and_capacity_limits_are_never_overridden_implicitly(self):
        for admission in ({"status": "warn", "recommendation": "launch_with_review", "recommended_agents": 2, "safe_agents": 2},
                          {"status": "pass", "recommendation": "wait", "recommended_agents": 2, "safe_agents": 2},
                          {"status": "pass", "recommendation": "launch", "recommended_agents": 0, "safe_agents": 2},
                          {"status": "pass", "recommendation": "launch", "recommended_agents": True, "safe_agents": 2}):
            peer = FixtureTransport(lambda h, m, r: {**r, "admission": admission})
            self.assertEqual(fleet.remote_result(host(), "preview", peer)["status"], "unconfirmed")
        selected = host()
        selected["request"]["accept_warnings"] = True
        peer = FixtureTransport(lambda h, m, r: {**r, "admission": {"status": "warn", "recommendation": "launch_with_review", "recommended_agents": 2, "safe_agents": 2}})
        self.assertEqual(fleet.remote_result(selected, "preview", peer)["status"], "admitted")

    def test_ready_requires_exact_request_original_native_targets_and_flags(self):
        variants = [("starts_agents", "true"), ("request", {}), ("work_dispatched", True),
                    ("original_launch_verified", False), ("recovery_provenance", {}), ("targets", []),
                    ("review_sha256", "f" * 64)]
        for key, value in variants:
            peer = FixtureTransport(lambda h, m, r: {**r, key: value})
            self.assertEqual(fleet.remote_result(host(), "launch", peer)["status"], "unconfirmed")
        for key, value in (("slot", True), ("agent_name", "Other"), ("agent_type", "codex"),
                           ("pane", "%x"), ("pane_pid", "-1"), ("session_id", "$bad")):
            def mutate(h, m, r):
                r["targets"][0][key] = value
                return r
            self.assertEqual(fleet.remote_result(host(), "launch", FixtureTransport(mutate))["status"], "unconfirmed")

    def test_duplicate_panes_and_changed_sessions_are_refused(self):
        selected = host()
        selected["request"]["agents"].append({"agent_name": "Other", "agent_type": "codex"})
        for key in ("pane", "session_id"):
            def change(h, m, r):
                r["targets"][1][key] = r["targets"][0][key] if key == "pane" else "$9"
                return r
            self.assertEqual(fleet.remote_result(selected, "launch", FixtureTransport(change))["status"], "unconfirmed")


class FilesAndProcessTests(unittest.TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp(prefix="acfs-fleet-io-test-"))

    def test_input_limits_no_follow_and_private_permissions(self):
        file = self.directory / "data"
        file.write_bytes(b"content")
        file.chmod(0o600)
        self.assertEqual(fleet.read_input(file), b"content")
        file.chmod(0o644)
        with self.assertRaises(fleet.Refused):
            fleet.read_input(file)
        self.assertEqual(fleet.read_input(file, private=False), b"content")
        link = self.directory / "link"
        link.symlink_to(file)
        with self.assertRaises(OSError):
            fleet.read_input(link, private=False)
        fifo = self.directory / "fifo"
        os.mkfifo(fifo)
        with self.assertRaises(fleet.Refused):
            fleet.read_input(fifo)
        file.chmod(0o600)
        file.write_bytes(b"x" * (fleet.LIMIT + 1))
        with self.assertRaises(fleet.Refused):
            fleet.read_input(file)
        file.write_bytes(b"content")
        os.link(file, self.directory / "hardlink")
        with self.assertRaises(fleet.Refused):
            fleet.read_input(file)

    def test_directory_paths_refuse_links_and_writable_parents(self):
        (self.directory / "alias").symlink_to(self.directory)
        for path in (self.directory / "alias",):
            with self.assertRaises(OSError):
                with fleet.directory_fd(path):
                    self.fail("symlink accepted")
        self.directory.chmod(0o777)
        with self.assertRaises(fleet.Refused):
            with fleet.directory_fd(self.directory):
                self.fail("writable parent accepted")

    def test_durable_publication_is_create_only_and_private(self):
        with fleet.directory_fd(self.directory) as fd:
            fleet.publish(fd, "evidence.json", {"ok": True})
            with self.assertRaises(FileExistsError):
                fleet.publish(fd, "evidence.json", {"ok": False})
        self.assertEqual(json.loads((self.directory / "evidence.json").read_text()), {"ok": True})
        self.assertEqual(stat.S_IMODE((self.directory / "evidence.json").stat().st_mode), 0o600)

    def test_ssh_argv_disables_ambient_configuration_and_quotes_all_remote_values(self):
        selected = host()
        selected["request"]["repo"] = "/data/space ' $(touch never)"
        args = fleet.ssh_argv(selected, "launch", 7, 8)
        self.assertEqual(args[:6], ["/usr/bin/ssh", "-F", "/dev/null", "-T", "-n", "-o"])
        for option in ("BatchMode=yes", "StrictHostKeyChecking=yes", "ForwardAgent=no", "ProxyCommand=none",
                       "ProxyJump=none", "ControlMaster=no", "PermitLocalCommand=no", "SendEnv=-*", "IdentitiesOnly=yes"):
            self.assertIn(option, args)
        self.assertEqual(args[-2], selected["host"])
        self.assertIn("--noprofile --norc -p", args[-1])
        self.assertIn("test ! -L", args[-1])
        import shlex
        tail = args[-1].split('"$HOME/.acfs/scripts/lib/swarm_launch.sh" ', 3)[-1]
        self.assertEqual(shlex.split(tail), fleet.native_argv(selected["request"], "launch"))
        self.assertNotIn("--launch", fleet.native_argv(selected["request"], "reconcile"))

    def test_transport_holds_private_snapshots_not_mutable_input_paths(self):
        def inspect(argv, timeout, env):
            key_path = argv[argv.index("-i") + 1]
            known_path = next(v.split("=", 1)[1] for v in argv if v.startswith("UserKnownHostsFile="))
            self.assertEqual(Path(key_path).read_bytes(), b"PRIVATE IDENTITY")
            self.assertEqual(Path(known_path).read_bytes(), b"KNOWN HOSTS")
            self.assertEqual(stat.S_IMODE(Path(key_path).stat().st_mode), 0o600)
            self.assertNotIn("BASH_ENV", env)
            self.assertNotIn("OPENAI_API_KEY", env)
            return 0, b"{}"
        with fleet.transport(b"KNOWN HOSTS", b"PRIVATE IDENTITY", 30, runner=inspect, ssh=sys.executable) as invoke:
            self.assertEqual(invoke(host(), "preview"), (0, b"{}"))

    def test_real_capture_collects_exit_and_stdout_but_never_exposes_stderr(self):
        code, output = fleet.capture([sys.executable, "-c", "import sys; print('response'); print('SECRET', file=sys.stderr); sys.exit(7)"], 3, {})
        self.assertEqual((code, output), (7, b"response\n"))

    def test_real_capture_closes_stdin_and_ignores_inherited_loader_hooks(self):
        code, output = fleet.capture([sys.executable, "-c", "import sys; print(len(sys.stdin.read()))"], 3, {})
        self.assertEqual((code, output), (0, b"0\n"))

    def test_real_capture_counts_both_streams_together(self):
        source = "import os,time; os.write(1,b'x'*600000); os.write(2,b'y'*600000); time.sleep(5)"
        with self.assertRaisesRegex(fleet.Refused, "ssh_output_limit"):
            fleet.capture([sys.executable, "-c", source], 3, {})

    def test_real_capture_timeout_kills_descendant_with_delayed_write(self):
        marker = self.directory / "must-not-be-created"
        child = "import time; from pathlib import Path; time.sleep(.8); Path(" + repr(str(marker)) + ").write_text('bad')"
        source = "import subprocess,sys; subprocess.Popen([sys.executable,'-c'," + repr(child) + "]); sys.exit(0)"
        started = time.monotonic()
        with self.assertRaisesRegex(fleet.Refused, "ssh_timeout"):
            fleet.capture([sys.executable, "-c", source], .15, {})
        self.assertLess(time.monotonic() - started, 2)
        time.sleep(.9)
        self.assertFalse(marker.exists())

    def test_cli_help_and_rejection_never_require_openssh_or_contact_hosts(self):
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), "--help"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn("live remote admission", result.stdout)
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), "--ssh", "/tmp/evil"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
