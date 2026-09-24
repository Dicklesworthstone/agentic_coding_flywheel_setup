#!/usr/bin/env python3
"""Actual collector logic and bounded subprocesses; SSH endpoints are explicit fixtures."""
import copy
import datetime as dt
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time
import types
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/lib/swarm_fleet_probe.sh"
source = SCRIPT.read_text().split("<<'PY'\n", 1)[1].rsplit("\nPY", 1)[0]
m = types.ModuleType("swarm_fleet_probe_test_module")
exec(compile(source, str(SCRIPT), "exec"), m.__dict__)


def inventory():
    return {"schema_version": 1, "updated_at": "2026-01-01T00:00:00Z",
            "defaults": {"workload": "standard", "stale_after_hours": 24},
            "hosts": [{"id": ident, "role": "swarm-worker", "status": "active",
                       "last_probe_at": "2026-01-01T00:00:00Z",
                       "resources": {"cpu_count": 8, "mem_total_mib": 16384, "disk_available_mib": 100000},
                       "capacity": {"workload": "standard", "recommended_agents": 5, "safe_agents": 8},
                       "rch": {"worker": False}, "ntm": {"can_launch": True}, "ru": {},
                       "notes": "operator policy"} for ident in ("alpha", "beta", "untouched")]}


def target(ident="alpha", host="alpha.example"):
    return {"id": ident, "host": host, "user": "runner", "port": 22}


def selected(values=None, base=None):
    return m.targets_from({"schema": "acfs.swarm-probe-targets.v1", "targets": values or [target()]}, base or inventory())


def response(ident="alpha", when=None):
    host = inventory()["hosts"][0]
    host["id"] = ident
    host["last_probe_at"] = when or dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    host["probe_source"] = "acfs swarm inventory probe-local"
    host["resources"]["cpu_count"] = 12
    host["capacity"].update(recommended_agents=6, safe_agents=9)
    host["local_observation"] = {"capacity_status": "pass", "ntm_available": True,
                                  "rch_available": False, "live_admission_checked": False}
    return {"schema_version": 1, "hosts": [host]}


class FleetTests(unittest.TestCase):
    def setUp(self):
        m.STOP.clear()
        self.directory = Path(tempfile.mkdtemp(prefix="acfs-fleet-test-"))

    def file(self, name, data, mode=0o600):
        path = self.directory / name
        path.write_bytes(data if isinstance(data, bytes) else data.encode())
        path.chmod(mode)
        return path

    def rejects(self, code, function, *args, **kwargs):
        with self.assertRaises(m.Refused) as error:
            function(*args, **kwargs)
        self.assertEqual(error.exception.code, code)

    def observe(self, value):
        now = time.time()
        return m.observation(m.encoded(value), selected()[0], now - 1, now)

    def test_unique_bounded_json(self):
        self.assertEqual(m.decode(b'{"x":[1,true]}'), {"x": [1, True]})
        for raw in (b'{"x":1,"x":2}', b'{"x":NaN}', b'{"x":1e999}', b'{"x":"\\ud800"}', b'{}{}', b'\xff'):
            with self.subTest(raw=raw), self.assertRaises(m.Refused):
                m.decode(raw)
        self.rejects("input_size_invalid", m.decode, b' ' * (m.LIMIT + 1))
        self.rejects("input_complexity_exceeded", m.decode, b'[' * 26 + b'0' + b']' * 26)

    def test_private_and_regular_file_snapshots(self):
        path = self.file("safe", "complete")
        self.assertEqual(m.read_snapshot(path, private=True), b"complete")
        path.chmod(0o644)
        self.rejects("unsafe_input_file", m.read_snapshot, path, private=True)
        path.chmod(0o666)
        self.rejects("unsafe_input_file", m.read_snapshot, path)
        link = self.directory / "link"
        link.symlink_to(path)
        with self.assertRaises(OSError):
            m.read_snapshot(link)
        path.chmod(0o600)
        os.link(path, self.directory / "hardlink")
        self.rejects("unsafe_input_file", m.read_snapshot, path)

    def test_fifo_is_not_opened_blockingly(self):
        path = self.directory / "fifo"
        os.mkfifo(path)
        self.rejects("unsafe_input_file", m.read_snapshot, path)

    def test_exact_known_target_selection_is_sorted_and_workload_bound(self):
        base = inventory()
        base["hosts"][1]["capacity"]["workload"] = "heavy"
        actual = selected([target("beta", "beta.example"), target()], base)
        self.assertEqual([(t["id"], t["workload"]) for t in actual], [("alpha", "standard"), ("beta", "heavy")])

    def test_null_defaults_use_standard(self):
        base = inventory()
        base["defaults"] = None
        base["hosts"][0]["capacity"].pop("workload")
        self.assertEqual(selected(base=base)[0]["workload"], "standard")

    def test_unknown_ids_cannot_invent_hosts(self):
        self.rejects("invalid_target", selected, [target("unknown")])

    def test_duplicate_machine_cannot_double_capacity(self):
        self.rejects("duplicate_or_noncanonical_endpoint", selected, [target(), target("beta")])
        self.rejects("invalid_target", selected, [target(), target()])

    def test_shell_options_and_noncanonical_endpoints_are_refused(self):
        for host in ("-oProxyCommand=touch", "a;touch", "a\nwhoami", "UPPER.example", "127.1", "12345", "host.", "x@y", "a_b"):
            with self.subTest(host=host), self.assertRaises(m.Refused):
                selected([target(host=host)])
        for field, value in (("user", "root;id"), ("id", "alpha;id"), ("port", True), ("port", 0), ("port", 65536)):
            item = target()
            item[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(m.Refused):
                selected([item])

    def test_canonical_ipv4_and_ipv6_work(self):
        self.assertEqual(selected([target(host="192.0.2.1")])[0]["host"], "192.0.2.1")
        self.assertEqual(selected([target(host="2001:db8::1")])[0]["host"], "2001:db8::1")
        self.rejects("duplicate_or_noncanonical_endpoint", selected, [target(host="2001:0db8::1")])

    def test_target_schema_is_closed_and_bounded(self):
        for value in ({}, {"schema": "acfs.swarm-probe-targets.v1", "targets": []},
                      {"schema": "acfs.swarm-probe-targets.v1", "targets": [target()] * 33}):
            self.rejects("invalid_targets", m.targets_from, value, inventory())
        item = target()
        item["command"] = "anything"
        self.rejects("invalid_target", selected, [item])

    def test_ssh_command_pins_host_keys_and_disables_implicit_actions(self):
        argv = m.ssh_argv(selected()[0], 7, "/private/key")
        self.assertEqual(argv[:7], ["/usr/bin/ssh", "-F", "/dev/null", "-T", "-n", "-o", "BatchMode=yes"])
        for option in ("StrictHostKeyChecking=yes", "UpdateHostKeys=no", "ForwardAgent=no", "ForwardX11=no",
                       "ClearAllForwardings=yes", "ControlMaster=no", "ControlPath=none", "PermitLocalCommand=no",
                       "ProxyCommand=none", "ProxyJump=none", "RemoteCommand=none", "SendEnv=-*"):
            self.assertIn(option, argv)
        self.assertIn(f"UserKnownHostsFile=/proc/{os.getpid()}/fd/7", argv)
        self.assertEqual(argv[-3], "--")
        self.assertEqual(argv[-2], "alpha.example")
        self.assertEqual(argv[-1], 'exec /bin/bash "$HOME/.acfs/scripts/lib/swarm_inventory.sh" probe-local --json --host-id alpha --workload standard')
        self.assertNotIn("--allow-launch", argv[-1])

    def test_real_subprocess_output_and_large_stdin_are_supported(self):
        payload = b"x" * 400000
        actual = m.capture([sys.executable, "-c", "import sys; sys.stdout.buffer.write(sys.stdin.buffer.read())"], 5, payload)
        self.assertEqual(actual, payload)

    def test_nonzero_exit_does_not_return_a_valid_looking_json(self):
        self.rejects("probe_command_failed", m.capture, [sys.executable, "-c", 'print("{}"); raise SystemExit(7)'], 5)

    def test_output_flood_is_bounded(self):
        self.rejects("probe_output_too_large", m.capture, [sys.executable, "-c", f'import sys; sys.stdout.buffer.write(b"x"*{m.LIMIT + 1})'], 5)

    def test_timeout_is_bounded_even_when_child_closes_stdout(self):
        began = time.monotonic()
        self.rejects("probe_timeout", m.capture, [sys.executable, "-c", "import os,time; os.close(1); time.sleep(30)"], 0.15)
        self.assertLess(time.monotonic() - began, 3)

    def test_cancellation_stops_real_subprocess(self):
        timer = threading.Timer(0.1, m.STOP.set)
        timer.start()
        try:
            self.rejects("cancelled", m.capture, [sys.executable, "-c", "import time; time.sleep(30)"], 5)
        finally:
            timer.join()
            m.STOP.clear()

    def test_lingering_pipe_writer_cannot_hold_collection_open(self):
        code = 'import os,time; pid=os.fork(); time.sleep(30) if pid==0 else None'
        self.rejects("probe_timeout", m.capture, [sys.executable, "-c", code], 0.15)

    def test_capture_discards_sensitive_stderr(self):
        self.assertEqual(m.capture([sys.executable, "-c", 'import sys; print("SECRET",file=sys.stderr); print("ok")'], 5), b"ok\n")

    def test_remote_policy_and_extra_sensitive_fields_are_not_copied(self):
        value = response()
        value["hosts"][0].update(role="swarm-controller", status="active", notes="PRIVATE ENDPOINT", token="SECRET")
        value["hosts"][0]["local_observation"]["password"] = "SECRET"
        actual = self.observe(value)
        self.assertEqual(actual["capacity"]["safe_agents"], 9)
        for field in ("role", "status", "notes", "token"):
            self.assertNotIn(field, actual)
        self.assertNotIn(b"SECRET", m.encoded(actual))
        self.assertNotIn(b"PRIVATE", m.encoded(actual))

    def test_identity_and_extra_host_responses_are_rejected(self):
        value = response("beta")
        self.rejects("probe_identity_mismatch", self.observe, value)
        value = response()
        value["hosts"].append(copy.deepcopy(value["hosts"][0]))
        self.rejects("probe_schema_invalid", self.observe, value)

    def test_stale_future_and_malformed_timestamp_are_not_refreshed(self):
        for when in ("2000-01-01T00:00:00Z", "2999-01-01T00:00:00Z", "2026-02-30T00:00:00Z", "2026-01-01", None):
            value = response()
            value["hosts"][0]["last_probe_at"] = when
            self.rejects("probe_timestamp_invalid", self.observe, value)

    def test_false_or_malformed_capacity_evidence_is_rejected(self):
        for field, bad in (("recommended_agents", True), ("recommended_agents", 10), ("safe_agents", -1), ("workload", "light")):
            value = response()
            value["hosts"][0]["capacity"][field] = bad
            with self.subTest(field=field), self.assertRaises(m.Refused):
                self.observe(value)
        for field, bad in (("capacity_status", "fail"), ("ntm_available", "true"), ("rch_available", 1), ("live_admission_checked", True)):
            value = response()
            value["hosts"][0]["local_observation"][field] = bad
            with self.subTest(field=field), self.assertRaises(m.Refused):
                self.observe(value)

    def test_zero_capacity_failure_is_an_observation_not_a_positive_admission(self):
        value = response()
        value["hosts"][0]["capacity"].update(recommended_agents=0, safe_agents=0)
        value["hosts"][0]["local_observation"]["capacity_status"] = "fail"
        self.assertEqual(self.observe(value)["capacity"]["safe_agents"], 0)

    def test_merge_preserves_disabled_status_role_veto_and_other_hosts(self):
        base = inventory()
        base["hosts"][0].update(role="rch-worker", status="disabled")
        base["hosts"][0]["ntm"]["can_launch"] = False
        before = copy.deepcopy(base)
        actual = m.merge(base, [{"id": "alpha", "status": "measured", "observation": self.observe(response())}])
        self.assertEqual(base, before)
        self.assertEqual(actual["hosts"][1:], before["hosts"][1:])
        host = actual["hosts"][0]
        self.assertEqual((host["role"], host["status"], host["ntm"]["can_launch"]), ("rch-worker", "disabled", False))
        self.assertEqual(host["notes"], "operator policy")
        self.assertEqual(host["resources"]["cpu_count"], 12)

    def test_missing_ntm_can_withdraw_but_not_grant_launch_permission(self):
        fresh = self.observe(response())
        fresh["local_observation"]["ntm_available"] = False
        actual = m.merge(inventory(), [{"id": "alpha", "status": "measured", "observation": fresh}])
        self.assertFalse(actual["hosts"][0]["ntm"]["can_launch"])

    def test_failed_probe_cannot_leave_stale_positive_recommendations(self):
        actual = m.merge(inventory(), [{"id": "alpha", "status": "failed", "code": "probe_timeout"}])
        host = actual["hosts"][0]
        self.assertEqual(host["capacity"]["recommended_agents"], 0)
        self.assertEqual(host["capacity"]["safe_agents"], 0)
        self.assertIsNone(host["last_probe_at"])
        self.assertTrue(host["ntm"]["can_launch"])
        self.assertEqual(actual["hosts"][1], inventory()["hosts"][1])

    def test_probe_executes_exact_command_against_executable_transport_fixture(self):
        transport = self.file("ssh-fixture", '#!' + sys.executable + '\nimport sys\nprint(' + repr(json.dumps(response())) + ')\n', 0o755)
        result = m.probe_one(selected()[0], 99, 5, ssh=str(transport))
        self.assertEqual(result["status"], "measured")
        self.assertEqual(result["observation"]["capacity"]["recommended_agents"], 6)

    def test_failed_transport_never_exposes_endpoint_or_output(self):
        transport = self.file("bad-ssh", '#!' + sys.executable + '\nimport sys\nprint("SECRET @ alpha.example"); sys.exit(255)\n', 0o755)
        result = m.probe_one(selected()[0], 99, 5, ssh=str(transport))
        self.assertEqual(result, {"id": "alpha", "status": "failed", "code": "probe_command_failed"})

    def test_create_only_private_durable_snapshot(self):
        path = self.directory / "result.json"
        fd, name = m.output_parent(path)
        try:
            m.publish(fd, name, b'{"complete":true}\n')
            with self.assertRaises(FileExistsError):
                m.publish(fd, name, b"clobber")
        finally:
            os.close(fd)
        self.assertEqual(path.read_bytes(), b'{"complete":true}\n')
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.rejects("output_exists", m.output_parent, path)

    def test_unsafe_output_paths_and_symlinked_ancestors_are_refused(self):
        link = self.directory / "link"
        link.symlink_to(self.directory, target_is_directory=True)
        with self.assertRaises(OSError):
            m.output_parent(link / "result")
        broken = self.directory / "broken"
        broken.symlink_to(self.directory / "absent")
        self.rejects("output_exists", m.output_parent, broken)
        self.directory.chmod(0o777)
        self.rejects("output_directory_unsafe", m.output_parent, self.directory / "result")

    def test_canonical_validator_and_preview_have_no_mutation(self):
        if not (ROOT / "scripts/lib/swarm_inventory.sh").exists():
            self.skipTest("Full checkout required for canonical inventory integration")
        base = self.file("inventory.json", m.encoded(inventory()))
        targets = self.file("targets.json", m.encoded({"schema": "acfs.swarm-probe-targets.v1", "targets": [target()]}))
        known = self.file("known_hosts", "operator-known-key\n")
        before = {p.name: p.read_bytes() for p in self.directory.iterdir()}
        report, code = m.main(["--inventory", str(base), "--targets", str(targets), "--known-hosts", str(known)], ROOT / "scripts/lib")
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "planned")
        self.assertNotIn(b"alpha.example", m.encoded(report))
        self.assertEqual({p.name: p.read_bytes() for p in self.directory.iterdir()}, before)
        bad = inventory()
        bad["hosts"][0]["notes"] = "IP is 192.0.2.3"
        self.rejects("inventory_validation_failed", m.validate_inventory, bad, ROOT / "scripts/lib")


def live_ssh():
    """Real OpenSSH client/server, pinned keys and private identity FD on loopback."""
    import pwd
    import socket
    root = Path(tempfile.mkdtemp(prefix="acfs-fleet-openssh-"))
    user = pwd.getpwuid(os.getuid()).pw_name
    if os.getuid() == 0:
        raise RuntimeError("Run OpenSSH acceptance as the normal non-root runner")
    def write(name, value, mode=0o600):
        path = root / name
        path.write_bytes(value if isinstance(value, bytes) else value.encode())
        path.chmod(mode)
        return path
    for name in ("host", "client", "wrong"):
        subprocess.run(["/usr/bin/ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(root / name)], check=True)
    write("authorized_keys", (root / "client.pub").read_bytes())
    # This server is a transport contract fixture, not a fake authentication seam.
    # It admits only the collector's exact command and returns synthetic capacity.
    pattern = r'exec /bin/bash "\$HOME/\.acfs/scripts/lib/swarm_inventory\.sh" probe-local --json --host-id ([a-z0-9][a-z0-9._-]{0,62}) --workload (light|standard|heavy)'
    responder = write("responder", '#!' + sys.executable + '\n' +
        'import datetime,json,os,pathlib,re\n' +
        'match=re.fullmatch(' + repr(pattern) + ',os.environ.get("SSH_ORIGINAL_COMMAND",""))\n' +
        'assert match is not None\n' +
        'pathlib.Path(' + repr(str(root / "called")) + ').open("a").write("called\\n")\n' +
        'value=json.loads(' + repr(json.dumps(response())) + ')\n' +
        'host=value["hosts"][0]; host["id"]=match[1]; host["capacity"]["workload"]=match[2]\n' +
        'host["last_probe_at"]=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")\n' +
        'print(json.dumps(value))\n', 0o755)
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    config = write("sshd_config", f"""Port {port}
ListenAddress 127.0.0.1
HostKey {root / 'host'}
PidFile {root / 'sshd.pid'}
AuthorizedKeysFile {root / 'authorized_keys'}
ForceCommand {responder}
AllowUsers {user}
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
PubkeyAuthentication yes
UsePAM no
StrictModes yes
PermitTTY no
DisableForwarding yes
LoginGraceTime 5
LogLevel ERROR
""")
    subprocess.run(["sudo", "mkdir", "-p", "/run/sshd"], check=True)
    server = subprocess.Popen(["sudo", "/usr/sbin/sshd", "-D", "-e", "-f", str(config)],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        for _ in range(100):
            if server.poll() is not None:
                raise RuntimeError("Loopback sshd failed to start")
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                    break
            except OSError:
                time.sleep(0.05)
        else:
            raise RuntimeError("Loopback sshd did not become ready")
        base = write("inventory.json", m.encoded(inventory()))
        selected_target = {"id": "alpha", "host": "127.0.0.1", "user": user, "port": port}
        destinations = write("targets.json", m.encoded({"schema": "acfs.swarm-probe-targets.v1", "targets": [selected_target]}))
        known = write("known_hosts", f"[127.0.0.1]:{port} " + (root / "host.pub").read_text())
        args = ["--inventory", str(base), "--targets", str(destinations), "--known-hosts", str(known),
                "--identity-file", str(root / "client"), "--timeout", "5", "--json"]
        plan, code = m.main(args, ROOT / "scripts/lib")
        assert code == 0 and not (root / "called").exists(), "Preview performed SSH"
        path = root / "measured.json"
        report, code = m.main(args + ["--probe", "--accept-plan", plan["plan_sha256"], "--output", str(path)], ROOT / "scripts/lib")
        assert code == 0 and report["status"] == "measured", report
        measured = m.decode(path.read_bytes())
        assert measured["hosts"][0]["capacity"]["recommended_agents"] == 6
        assert measured["hosts"][0]["ntm"]["can_launch"] is True
        assert measured["hosts"][1:] == inventory()["hosts"][1:]
        assert base.read_bytes() == m.encoded(inventory()), "Input inventory changed"
        calls = (root / "called").read_bytes()
        # Output collision must stop before a second SSH command.
        try:
            m.main(args + ["--probe", "--accept-plan", plan["plan_sha256"], "--output", str(path)], ROOT / "scripts/lib")
            raise AssertionError("Existing output was overwritten")
        except m.Refused as error:
            assert error.code == "output_exists", error.code
        assert (root / "called").read_bytes() == calls
        known.write_text(f"[127.0.0.1]:{port} " + (root / "wrong.pub").read_text())
        try:
            m.main(args + ["--probe", "--accept-plan", plan["plan_sha256"], "--output", str(root / "stale.json")], ROOT / "scripts/lib")
            raise AssertionError("Changed trust accepted stale approval")
        except m.Refused as error:
            assert error.code == "plan_changed", error.code
        assert not (root / "stale.json").exists()
        wrong_plan, _ = m.main(args, ROOT / "scripts/lib")
        bad, code = m.main(args + ["--probe", "--accept-plan", wrong_plan["plan_sha256"], "--output", str(root / "wrong-key.json")], ROOT / "scripts/lib")
        assert code == 1 and bad["results"][0]["code"] == "probe_command_failed", bad
        assert (root / "called").read_bytes() == calls, "Host-key mismatch executed remote command"
        invalidated = m.decode((root / "wrong-key.json").read_bytes())["hosts"][0]
        assert invalidated["last_probe_at"] is None and invalidated["capacity"]["safe_agents"] == 0
        known.write_text(f"[127.0.0.1]:{port} " + (root / "host.pub").read_text())
        # One real healthy peer and one refused connection: publish a conservative
        # usable snapshot, not all-or-nothing data loss or stale success.
        destinations.write_bytes(m.encoded({"schema": "acfs.swarm-probe-targets.v1", "targets": [
            selected_target, {**selected_target, "id": "beta", "host": "127.0.0.2"}]}))
        partial_plan, _ = m.main(args, ROOT / "scripts/lib")
        partial, code = m.main(args + ["--probe", "--accept-plan", partial_plan["plan_sha256"], "--output", str(root / "partial.json")], ROOT / "scripts/lib")
        assert code == 1 and partial["status"] == "partial", partial
        snapshot = m.decode((root / "partial.json").read_bytes())
        assert snapshot["hosts"][0]["capacity"]["recommended_agents"] == 6
        assert snapshot["hosts"][1]["capacity"]["safe_agents"] == 0
        assert snapshot["hosts"][2] == inventory()["hosts"][2]
        for endpoint in (b"127.0.0.1", b"127.0.0.2", str(root).encode()):
            assert endpoint not in m.encoded(partial) and endpoint not in m.encoded(snapshot)
        print("PASS: actual OpenSSH authentication, pinned host/identity snapshots, strict key refusal, no-preview SSH, stale-approval refusal, create-only output and partial-fleet invalidation")
    finally:
        subprocess.run(["sudo", "kill", "-TERM", "--", "-" + str(server.pid)], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        server.wait(timeout=10)


if __name__ == "__main__":
    if sys.argv[1:] == ["--live-ssh"]:
        live_ssh()
    else:
        unittest.main(verbosity=2)
