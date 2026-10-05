#!/usr/bin/env python3
"""Real controller journals and transport; native peers are protocol fixtures."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("dispatch", ROOT / "scripts/swarm-fleet-dispatch.py")
dispatch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dispatch)
fleet = dispatch.fleet


class Peer:
    def __init__(self, state):
        self.state, self.calls, self.mutate = state, [], None
        self.intents = {}

    def __call__(self, entry, mode):
        entry = copy.deepcopy(entry)
        self.calls.append((entry["host"]["id"], mode))
        host, targets = entry["host"], entry["targets"]
        request, ident = host["request"], host["id"]
        if mode == "launch-status":
            value = {"schema": fleet.NATIVE_SCHEMA, "request": request, "status": "ready", "targets": targets,
                     "starts_agents": False, "work_dispatched": False, "authentication_verified": False,
                     "agent_mail_registered": False, "reconciled_only": True}
        else:
            deliveries = []
            for target in targets:
                slot = target["slot"]
                delivery = {"repo": request["repo"], "session": request["session"], "pane": target["pane"],
                            "agent_type": target["agent_type"], "operation_id": f"op-{ident}-{slot}",
                            "bead_id": f"bd-{ident}-{slot}", "packet_sha256": "a" * 64,
                            "payload_sha256": "b" * 64, "payload_bytes": 120}
                deliveries.append({"slot": slot, "request": delivery, "receipt": f"/home/ubuntu/packets/{ident}-{slot}.receipt",
                                   "action": "submit"})
            batch_digest = fleet.digest(fleet.encoded(deliveries))
            value = {"schema": dispatch.NATIVE_SCHEMA, "status": "preview", "batch": entry["batch"],
                     "launch_receipt": request["receipt"], "batch_review_sha256": batch_digest,
                     "review_sha256": fleet.digest(fleet.encoded({"schema": dispatch.NATIVE_SCHEMA,
                         "request": request, "targets": targets, "batch_sha256": batch_digest})),
                     "starts_agents": False, "sends_prompt": False, "agent_execution_verified": False,
                     "deliveries": deliveries, "send_command": "touch /NEVER-EXECUTE-REMOTE-COMMAND"}
            if mode == "send":
                assert (self.state / f"{ident}.attempt.json").is_file(), "send preceded durable local attempt"
                assert value["review_sha256"] == entry["review_sha256"]
                value.update(status="submitted", sends_prompt=True)
                for detail in deliveries:
                    detail.pop("action")
                    detail.update(status="submitted", sends_prompt=True, agent_execution_verified=False)
                self.intents[ident] = copy.deepcopy(value)
        code = 0
        if self.mutate:
            replacement = self.mutate(entry, mode, value)
            if replacement is not None:
                return replacement
        return code, fleet.encoded(value)


class DispatchTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="acfs-fleet-dispatch-test-"))
        self.launch_dir, self.state = self.root / "launch", self.root / "dispatch"
        self.known, self.identity = b"fixture independently verified host keys", b"fixture private identity"
        hosts = []
        for number in range(2):
            ident = f"worker-{number}"
            request = {"repo": "/data/projects/app", "session": "implementation", "receipt": f"/home/ubuntu/{ident}.launch.json",
                       "profile": "balanced", "workload": "standard", "accept_warnings": False,
                       "agents": [{"agent_name": f"Agent{number}a", "agent_type": "claude"},
                                  {"agent_name": f"Agent{number}b", "agent_type": "codex"}]}
            hosts.append({"id": ident, "host": f"worker{number}.example.com", "user": "ubuntu", "port": 22, "request": request})
        self.launch = fleet.build_plan({"schema": fleet.SPEC_SCHEMA, "hosts": hosts}, self.known, self.identity, self.launch_dir, 360)
        self.targets = {}
        with fleet.new_state(self.launch) as fd:
            for index, host in enumerate(hosts):
                targets = [{"slot": i, **agent, "pane": f"%{20+i}", "pane_pid": str(100+i), "server_pid": "99",
                            "session_id": "$2", "session_created": "123456"} for i, agent in enumerate(host["request"]["agents"], 1)]
                self.targets[host["id"]] = targets
                attempt = fleet.host_intent(self.launch, host)
                fleet.publish(fd, host["id"] + ".attempt.json", attempt)
                fleet.publish(fd, host["id"] + ".result.json", {**attempt, "targets": targets})
        self.batches = {"schema": dispatch.SPEC_SCHEMA, "hosts": [{"id": h["id"], "batch": f"/home/ubuntu/packets/{h['id']}/batch.json"} for h in hosts]}
        self.peer = Peer(self.state)

    def run_dispatch(self, mode="preview", approval=None):
        return dispatch.execute(self.launch_dir, self.batches, self.known, self.identity, self.state, 360, mode, approval, self.peer)

    def approved(self):
        result, code = self.run_dispatch()
        self.assertEqual(code, 0, result)
        self.peer.calls.clear()
        return result["plan_sha256"]

    def snapshot(self):
        return {p.name: p.read_bytes() for p in self.launch_dir.iterdir()}

    def test_preview_checks_every_host_without_creating_dispatch_state(self):
        before = self.snapshot()
        result, code = self.run_dispatch()
        self.assertEqual(code, 0, result)
        self.assertEqual(result["status"], "preview")
        self.assertFalse(result["send_attempted"])
        self.assertFalse(result["starts_agents"])
        self.assertEqual(self.peer.calls, [(f"worker-{i}", m) for i in range(2) for m in ("launch-status", "preview")])
        self.assertFalse(self.state.exists())
        self.assertEqual(before, self.snapshot())
        self.assertEqual(len(result["hosts"][0]["deliveries"]), 2)
        output = json.dumps(result)
        for private in ("example.com", "/home/ubuntu", "NEVER-EXECUTE", "fixture private identity"):
            self.assertNotIn(private, output)

    def test_send_has_all_host_barrier_private_intents_and_matching_results(self):
        approval = self.approved()
        before = self.snapshot()
        result, code = self.run_dispatch("send", approval)
        self.assertEqual(code, 0, result)
        self.assertEqual(result["status"], "submitted")
        self.assertEqual(self.peer.calls[-2:], [("worker-0", "send"), ("worker-1", "send")])
        self.assertTrue(all(m != "send" for _, m in self.peer.calls[:-2]))
        self.assertEqual({p.name for p in self.state.iterdir()}, {"intent.json", "worker-0.attempt.json", "worker-0.result.json", "worker-1.attempt.json", "worker-1.result.json"})
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o700)
        self.assertTrue(all(p.stat().st_mode & 0o777 == 0o600 for p in self.state.iterdir()))
        self.assertEqual(before, self.snapshot())

    def test_subset_dispatch_uses_launch_order_not_map_order(self):
        self.batches["hosts"].reverse()
        result, _ = self.run_dispatch()
        self.assertEqual([h["id"] for h in result["hosts"]], ["worker-0", "worker-1"])
        self.peer.calls.clear()
        self.batches["hosts"] = self.batches["hosts"][:1]
        result, _ = self.run_dispatch()
        self.assertEqual([h["id"] for h in result["hosts"]], ["worker-1"])
        self.assertTrue(all(ident == "worker-1" for ident, _ in self.peer.calls))

    def test_invalid_selection_is_inert(self):
        original = copy.deepcopy(self.batches)
        for hosts in ([], [{"id": "missing", "batch": "/tmp/batch.json"}],
                      [original["hosts"][0]] * 2, [{**original["hosts"][0], "command": "touch BAD"}],
                      [{"id": "worker-0", "batch": "relative"}], [{"id": "worker-0", "batch": "/tmp/../batch"}]):
            with self.subTest(hosts=hosts):
                self.batches = {"schema": dispatch.SPEC_SCHEMA, "hosts": hosts}
                with self.assertRaises(fleet.Refused):
                    self.run_dispatch()
                self.assertFalse(self.state.exists())
                self.assertEqual(self.peer.calls, [])

    def test_rotated_ssh_trust_requires_launch_context_review(self):
        self.known += b"changed"
        with self.assertRaisesRegex(fleet.Refused, "trust_mismatch"):
            self.run_dispatch()
        self.assertEqual(self.peer.calls, [])

    def test_incomplete_selected_launch_never_reaches_ssh(self):
        # Retain rather than delete the saved result; the journal refuses extras.
        (self.launch_dir / "worker-1.result.json").rename(self.root / "retained-result.json")
        with self.assertRaisesRegex(fleet.Refused, "selected_launch_not_confirmed"):
            self.run_dispatch()
        self.assertEqual(self.peer.calls, [])

    def test_existing_dispatch_state_is_never_reused_as_new(self):
        self.state.mkdir(mode=0o700)
        with self.assertRaisesRegex(fleet.Refused, "state_already_exists"):
            self.run_dispatch("send", "0" * 64)
        self.assertEqual(self.peer.calls, [])

    def test_dispatch_journal_cannot_live_inside_source_journal(self):
        self.state = self.launch_dir / "dispatch"
        with self.assertRaisesRegex(fleet.Refused, "outside_launch_journal"):
            self.run_dispatch()
        self.assertEqual(self.peer.calls, [])

    def test_wrong_approval_never_sends_or_creates_state(self):
        with self.assertRaisesRegex(fleet.Refused, "approval_mismatch"):
            self.run_dispatch("send", "0" * 64)
        self.assertFalse(self.state.exists())
        self.assertTrue(all(mode != "send" for _, mode in self.peer.calls))

    def test_launch_approval_does_not_authorize_work(self):
        with self.assertRaisesRegex(fleet.Refused, "approval_mismatch"):
            self.run_dispatch("send", fleet.digest(fleet.encoded(self.launch)))
        self.assertFalse(self.state.exists())

    def test_changed_remote_packet_requires_new_review(self):
        approval = self.approved()
        def changed(_entry, mode, value):
            if mode == "preview":
                value["deliveries"][0]["request"]["packet_sha256"] = "d" * 64
        self.peer.mutate = changed
        with self.assertRaisesRegex(fleet.Refused, "approval_mismatch"):
            self.run_dispatch("send", approval)
        self.assertFalse(self.state.exists())
        self.assertTrue(all(mode != "send" for _, mode in self.peer.calls))

    def test_native_preview_refusals_stop_entire_fleet_before_any_send(self):
        approval = self.approved()
        def blocked(entry, mode, _value):
            if entry["host"]["id"] == "worker-1" and mode == "preview":
                return 2, b'"SECRET: sensitive remote failure"'
        self.peer.mutate = blocked
        result, code = self.run_dispatch("send", approval)
        self.assertEqual(code, 1)
        self.assertEqual(result["status"], "blocked")
        self.assertNotIn("SECRET", json.dumps(result))
        self.assertFalse(self.state.exists())
        self.assertTrue(all(mode != "send" for _, mode in self.peer.calls))

    def test_replaced_native_process_blocks_dispatch(self):
        def changed(_entry, mode, value):
            if mode == "launch-status":
                value["targets"][0]["pane_pid"] = "999"
        self.peer.mutate = changed
        result, code = self.run_dispatch()
        self.assertEqual(code, 1)
        self.assertEqual(result["errors"][0]["code"], "original_agents_not_live")
        self.assertTrue(all(mode == "launch-status" for _, mode in self.peer.calls))

    def test_adopted_native_session_is_not_original_launch_evidence(self):
        def changed(_entry, mode, value):
            if mode == "launch-status":
                value["original_launch_verified"] = False
        self.peer.mutate = changed
        self.assertEqual(self.run_dispatch()[1], 1)

    def test_native_dispatch_hash_must_bind_our_original_targets(self):
        def changed(_entry, mode, value):
            if mode == "preview":
                value["review_sha256"] = "0" * 64
        self.peer.mutate = changed
        result, code = self.run_dispatch()
        self.assertEqual(code, 1)
        self.assertEqual(result["errors"][0]["code"], "original_launch_or_batch_mismatch")

    def test_delivery_contract_rejects_wrong_target_type_boolean_slot_and_duplicates(self):
        mutations = [lambda d: d.update(slot=True), lambda d: d["request"].update(pane="%999"),
                     lambda d: d["request"].update(agent_type="agy"), lambda d: d.update(action="reconcile_only"),
                     lambda d: d["request"].update(payload_bytes=True), lambda d: d["request"].update(payload_sha256="bad"),
                     lambda d: d.update(receipt="/tmp/../escape"), lambda d: d["request"].update(command="BAD")]
        for mutate in mutations:
            def changed(_entry, mode, value):
                if mode == "preview":
                    mutate(value["deliveries"][0])
            self.peer.mutate = changed
            with self.subTest(mutate=mutate):
                self.assertEqual(self.run_dispatch()[1], 1)
                self.assertFalse(self.state.exists())

    def test_duplicate_task_across_hosts_is_rejected(self):
        def changed(_entry, mode, value):
            if mode == "preview":
                value["deliveries"][0]["request"]["bead_id"] = "bd-duplicate"
        self.peer.mutate = changed
        with self.assertRaisesRegex(fleet.Refused, "duplicate_fleet_bead"):
            self.run_dispatch()

    def test_unconfirmed_send_retains_intent_and_stops_later_hosts(self):
        approval = self.approved()
        def lost(_entry, mode, _value):
            if mode == "send":
                raise fleet.Refused("ssh_timeout")
        self.peer.mutate = lost
        result, code = self.run_dispatch("send", approval)
        self.assertEqual(code, 1)
        self.assertTrue(result["send_attempted"])
        self.assertEqual([h["status"] for h in result["hosts"]], ["unconfirmed", "not_attempted"])
        self.assertEqual({p.name for p in self.state.iterdir()}, {"intent.json", "worker-0.attempt.json"})
        self.assertNotIn(("worker-1", "send"), self.peer.calls)

    def test_mismatching_success_response_is_unconfirmed(self):
        approval = self.approved()
        def changed(_entry, mode, value):
            if mode == "send":
                value["deliveries"][0]["request"]["payload_sha256"] = "f" * 64
        self.peer.mutate = changed
        result, code = self.run_dispatch("send", approval)
        self.assertEqual(code, 1)
        self.assertEqual(result["hosts"][0]["status"], "unconfirmed")
        self.assertFalse((self.state / "worker-0.result.json").exists())

    def test_launch_journal_changed_during_preview_stops_before_send(self):
        approval = self.approved()
        def changed(_entry, mode, _value):
            if mode == "preview":
                path = self.launch_dir / "worker-0.result.json"
                path.write_bytes(path.read_bytes() + b" ")
        self.peer.mutate = changed
        with self.assertRaisesRegex(fleet.Refused, "state_changed"):
            self.run_dispatch("send", approval)
        self.assertFalse(self.state.exists())

    def test_source_journal_is_locked_through_remote_operations(self):
        import fcntl
        def check(_entry, _mode, _value):
            with fleet.directory_fd(self.launch_dir, private=True) as fd:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        self.peer.mutate = check
        self.assertEqual(self.run_dispatch()[1], 0)

    def test_ssh_transport_preserves_trust_snapshots_and_fixed_remote_argv(self):
        seen = []
        def runner(argv, timeout, env):
            seen.append(argv)
            self.assertEqual(timeout, 17)
            self.assertEqual(argv[:5], [sys.executable, "-F", "/dev/null", "-T", "-n"])
            self.assertIn("StrictHostKeyChecking=yes", argv)
            self.assertIn("ForwardAgent=no", argv)
            self.assertIn("ProxyCommand=none", argv)
            self.assertIn("SendEnv=-*", argv)
            self.assertNotIn("BASH_ENV", env)
            self.assertNotIn("OPENAI_API_KEY", env)
            key = Path(argv[argv.index("-i") + 1])
            known_path = Path(next(a.split("=", 1)[1] for a in argv if a.startswith("UserKnownHostsFile=")))
            self.assertEqual(key.read_bytes(), self.identity)
            self.assertEqual(known_path.read_bytes(), self.known)
            return 0, b"{}"
        entry = {"host": self.launch["spec"]["hosts"][0], "batch": "/home/ubuntu/a 'quote'; $(touch BAD)/batch.json", "review_sha256": "a" * 64}
        invoke = dispatch.transport(self.known, self.identity, 17, runner=runner, ssh=sys.executable)
        for mode in ("launch-status", "preview", "send"):
            invoke(entry, mode)
            command = seen[-1][-1]
            self.assertNotIn("--launch", command)
            parsed = shlex.split(command.split(" -p ", 1)[1])
            self.assertEqual(parsed[0], "$HOME/.acfs/scripts/lib/swarm_launch.sh")
            if mode != "launch-status":
                self.assertEqual(parsed[2], entry["batch"])
            self.assertEqual("--send" in parsed, mode == "send")

    def test_cli_help_and_invalid_arguments_are_available_without_network(self):
        path = ROOT / "scripts/swarm-fleet-dispatch.py"
        result = subprocess.run([sys.executable, "-I", str(path), "--help"], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertIn("--launch-state", result.stdout)
        result = subprocess.run([sys.executable, "-I", str(path), "--launch"], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
