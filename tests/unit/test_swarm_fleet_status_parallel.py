#!/usr/bin/env python3
"""Bounded host concurrency against real journals and cancellable local children."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import redirect_stdout
import copy
import fcntl
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import test_swarm_fleet_status as fixtures

status, fleet = fixtures.status, fixtures.fleet
ROOT = fixtures.ROOT


class ParallelStatusTests(unittest.TestCase):
    def setUp(self):
        self.addCleanup(os.umask, os.umask(0o022))
        self.temp = tempfile.TemporaryDirectory(prefix="acfs-status-parallel-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.fx = fixtures.FleetFixture(self.root)

    def collect(self, invoke=None, *, workers=2, cancel_event=None, work=True, launch_path=None):
        return status.collect(launch_path or self.fx.launch_path, self.fx.work_path if work else None,
                              self.fx.known, self.fx.key, invoke or self.fx.observe,
                              workers=workers, cancel_event=cancel_event)

    def large_fleet(self, count):
        hosts = []
        for i in range(count):
            host = copy.deepcopy(self.fx.hosts[0])
            host.update(id=f"host-{i}", host=f"192.0.2.{i + 10}")
            host["request"].update(session=f"wave-{i}", receipt=f"/home/ubuntu/launch-{i}.json")
            for j, agent in enumerate(host["request"]["agents"]):
                agent["agent_name"] = f"Host{i}Agent{j}"
            hosts.append(host)
        path = self.root / f"fleet-{count}"
        plan = fleet.build_plan({"schema": fleet.SPEC_SCHEMA, "hosts": hosts}, self.fx.known, self.fx.key, path, 360)
        report, code = fleet.execute(plan, "launch", fleet.digest(fleet.encoded(plan)), self.fx.native)
        self.assertEqual(code, 0, report)
        return path

    def test_hosts_overlap_but_report_and_each_host_protocol_stay_ordered(self):
        before = self.fx.snapshot()
        barrier = threading.Barrier(2)
        completion = []
        def invoke(entry, mode):
            if mode == "launch-status":
                barrier.wait(timeout=3)
                if entry["host"]["id"] == "one":
                    time.sleep(0.05)
                completion.append(entry["host"]["id"])
            return self.fx.observe(entry, mode)
        report, code = self.collect(invoke)
        self.assertEqual(code, 0)
        self.assertEqual(completion, ["two", "one"])
        self.assertEqual([h["id"] for h in report["hosts"]], ["one", "two"])
        self.assertEqual(report["observation_workers"], 2)
        for host in ("one", "two"):
            self.assertEqual([m for h, m in self.fx.calls if h == host], ["launch-status",
                "read-receipt", "query-receipt", "read-receipt", "query-receipt", "work-snapshot"])
        self.assertEqual(report["summary"]["confirmed_submissions"], 4)
        self.assertFalse(report["task_completion_verified"])
        self.assertEqual(before, self.fx.snapshot())

    def test_serial_and_parallel_agree_on_all_evidence_and_failure_fields(self):
        def invoke(entry, mode):
            if entry["host"]["id"] == "one" and mode == "query-receipt":
                return 1, b"PRIVATE-REMOTE-ERROR"
            return self.fx.observe(entry, mode)
        serial, serial_code = self.collect(invoke, workers=1)
        parallel, parallel_code = self.collect(invoke, workers=4)
        for report in (serial, parallel):
            for field in ("started_at", "finished_at", "observation_workers"):
                report.pop(field)
        self.assertEqual((serial_code, serial), (parallel_code, parallel))
        self.assertEqual(parallel_code, 1)
        self.assertNotIn("PRIVATE-", fleet.encoded(parallel).decode())

    def test_configured_worker_limit_bounds_six_host_concurrency(self):
        path = self.large_fleet(6)
        gate, active, peak = threading.Lock(), 0, 0
        barrier = threading.Barrier(2)
        def invoke(entry, mode):
            nonlocal active, peak
            self.assertEqual(mode, "launch-status")
            with gate:
                active += 1
                peak = max(active, peak)
            try:
                barrier.wait(timeout=3)
                return self.fx.observe(entry, mode)
            finally:
                with gate:
                    active -= 1
        report, code = self.collect(invoke, workers=2, work=False, launch_path=path)
        self.assertEqual((code, peak, active), (0, 2, 0))
        self.assertEqual([r["id"] for r in report["hosts"]], [f"host-{i}" for i in range(6)])

    def test_stalled_first_host_does_not_consume_healthy_peers_observation(self):
        def runner(argv, timeout, env):
            host = next(h for h in self.fx.hosts if h["host"] == argv[-2])
            if host["id"] == "one":
                return fleet.capture(["/usr/bin/python3", "-I", "-c", "import time; time.sleep(30)"], timeout, env)
            _, raw = self.fx.native(host, "reconcile")
            return fleet.capture(["/usr/bin/python3", "-I", "-c", "import sys; sys.stdout.write(sys.argv[1])",
                                  raw.decode()], timeout, env)
        invoke = status.transport(self.fx.known, self.fx.key, 1, 0.75, runner=runner, ssh="/usr/bin/true")
        start = time.monotonic()
        report, code = self.collect(invoke, work=False)
        self.assertEqual(code, 1)
        self.assertEqual(report["hosts"][0]["agents"]["code"], "ssh_timeout")
        self.assertEqual(report["hosts"][1]["agents"]["status"], "live")
        self.assertEqual(report["summary"]["verified_live_agents"], 2)
        self.assertLess(time.monotonic() - start, 3)

    def test_pre_cancelled_sample_performs_no_remote_calls(self):
        cancelled = threading.Event()
        cancelled.set()
        with self.assertRaisesRegex(fleet.Refused, "operation_cancelled"):
            self.collect(cancel_event=cancelled)
        self.assertEqual(self.fx.calls, [])

    def test_invalid_worker_counts_fail_before_journal_or_network_reads(self):
        for workers in (0, 17, True, 1.5, "2"):
            with self.subTest(workers=workers), self.assertRaisesRegex(fleet.Refused, "invalid_status_workers"):
                self.collect(workers=workers, launch_path="/missing")
        self.assertEqual(self.fx.calls, [])

    def test_locks_are_held_for_each_parallel_remote_call_and_released_afterwards(self):
        def invoke(entry, mode):
            for path in (self.fx.launch_path, self.fx.work_path):
                with fleet.directory_fd(path, private=True) as fd:
                    with self.assertRaises(BlockingIOError):
                        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return self.fx.observe(entry, mode)
        self.assertEqual(self.collect(invoke)[1], 0)
        for path in (self.fx.launch_path, self.fx.work_path):
            with fleet.directory_fd(path, private=True) as fd:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_journal_mutation_stays_fatal_when_another_worker_restores_bytes(self):
        cancelled, entered = threading.Event(), threading.Barrier(2)
        path = self.fx.work_path / "intent.json"
        original = path.read_bytes()
        restored = threading.Event()
        def invoke(entry, mode):
            self.assertEqual(mode, "launch-status")
            entered.wait(timeout=3)
            if entry["host"]["id"] == "one":
                path.write_bytes(original + b" ")
                return self.fx.observe(entry, mode)
            self.assertTrue(cancelled.wait(3))
            path.write_bytes(original)
            restored.set()
            return self.fx.observe(entry, mode)
        with self.assertRaisesRegex(fleet.Refused, "state_changed_during_operation"):
            self.collect(invoke, cancel_event=cancelled)
        self.assertTrue(restored.is_set())
        self.assertEqual(path.read_bytes(), original)
        self.assertFalse(any(t.name.startswith("acfs-status") for t in threading.enumerate()))

    def test_detected_corruption_cancels_queued_hosts_without_new_remote_calls(self):
        path = self.large_fleet(6)
        cancelled, barrier = threading.Event(), threading.Barrier(2)
        calls = []
        def invoke(entry, mode):
            calls.append(entry["host"]["id"])
            barrier.wait(timeout=3)
            if entry["host"]["id"] == "host-0":
                intent = path / "intent.json"
                intent.write_bytes(intent.read_bytes() + b" ")
            else:
                self.assertTrue(cancelled.wait(3))
            return self.fx.observe(entry, mode)
        with self.assertRaisesRegex(fleet.Refused, "state_changed_during_operation"):
            self.collect(invoke, launch_path=path, work=False, cancel_event=cancelled)
        self.assertCountEqual(calls, ["host-0", "host-1"])

    def test_parallel_guard_validation_never_uses_shared_descriptors_concurrently(self):
        original = fleet.state_unchanged
        gate, active = threading.Lock(), 0
        def inspect(*args):
            nonlocal active
            with gate:
                active += 1
                self.assertEqual(active, 1)
            try:
                time.sleep(0.001)
                return original(*args)
            finally:
                with gate:
                    active -= 1
        with patch.object(fleet, "state_unchanged", side_effect=inspect):
            self.assertEqual(self.collect(workers=4)[1], 0)

    def test_cli_selects_four_workers_and_can_explicitly_select_one(self):
        known, key = self.root / "known", self.root / "key"
        known.write_bytes(self.fx.known)
        key.write_bytes(self.fx.key)
        key.chmod(0o600)
        args = ["--launch-state", str(self.fx.launch_path), "--dispatch-state", str(self.fx.work_path),
                "--known-hosts", str(known), "--identity-file", str(key)]
        for options, expected in (([], 4), (["--workers", "1"], 1)):
            with self.subTest(options=options), patch.object(status, "transport", return_value=self.fx.observe), \
                 patch.object(status, "collect", wraps=status.collect) as collect, redirect_stdout(io.StringIO()) as out:
                self.assertEqual(status.main(args + options), 0)
                self.assertEqual(collect.call_args.kwargs["workers"], expected)
                self.assertEqual(json.loads(out.getvalue())["observation_workers"], min(expected, 2))

    def test_cancellation_is_shared_with_default_transport_capture(self):
        cancelled = threading.Event()
        with patch.object(fleet, "capture", return_value=(0, b"{}")) as capture:
            invoke = status.transport(self.fx.known, self.fx.key, 10, 12, ssh="/usr/bin/true", cancel_event=cancelled)
            invoke({"host": self.fx.hosts[0]}, "launch-status")
            self.assertIs(capture.call_args.kwargs["cancel_event"], cancelled)
            cancelled.set()
            with self.assertRaisesRegex(fleet.Refused, "operation_cancelled"):
                invoke({"host": self.fx.hosts[0]}, "launch-status")
            self.assertEqual(capture.call_count, 1)

    def test_signal_cancels_actual_parallel_children_and_releases_journal_locks(self):
        known, key = self.root / "known", self.root / "key"
        known.write_bytes(self.fx.known)
        key.write_bytes(self.fx.key)
        key.chmod(0o600)
        # Exercise the actual CLI's signal handler, pool shutdown and capture.
        # Substitute only the remote command with a local sleep; never use SSH.
        script = r'''
import importlib.util, os, pathlib, sys
spec = importlib.util.spec_from_file_location("status", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
original = mod.fleet.capture
root = pathlib.Path(sys.argv[2])
def local_capture(argv, timeout, env, **kwargs):
    child = "import os,pathlib,signal,sys,time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(30)"
    return original(["/usr/bin/python3", "-I", "-c", child, str(root / (argv[-2] + ".pid"))], timeout, env, **kwargs)
mod.fleet.capture = local_capture
original_transport = mod.transport
def local_transport(*args, **kwargs):
    return original_transport(*args, ssh="/usr/bin/true", **kwargs)
mod.transport = local_transport
sys.argv = [sys.argv[1], *sys.argv[3:]]
sys.exit(mod.cli())
'''
        process = subprocess.Popen([sys.executable, "-I", "-c", script, str(ROOT / "scripts/swarm-fleet-status.py"),
            str(self.root), "--launch-state", str(self.fx.launch_path), "--dispatch-state", str(self.fx.work_path),
            "--known-hosts", str(known), "--identity-file", str(key), "--timeout", "30", "--workers", "2"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            end = time.monotonic() + 5
            while len(list(self.root.glob("*.pid"))) != 2 and time.monotonic() < end and process.poll() is None:
                time.sleep(0.01)
            self.assertEqual(len(list(self.root.glob("*.pid"))), 2)
            started = time.monotonic()
            process.send_signal(signal.SIGTERM)
            out, err = process.communicate(timeout=3)
            self.assertLess(time.monotonic() - started, 3)
            self.assertEqual(process.returncode, 143, (out, err))
            report = json.loads(out)
            self.assertEqual(report["status"], "interrupted")
            self.assertTrue(report["read_only"])
            self.assertFalse(report["sends_prompts"])
            self.assertNotIn(b"Traceback", err)
            for marker in self.root.glob("*.pid"):
                with self.assertRaises(ProcessLookupError):
                    os.kill(int(marker.read_text()), 0)
            for path in (self.fx.launch_path, self.fx.work_path):
                with fleet.directory_fd(path, private=True) as fd:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=5)


class CaptureCancellationTests(unittest.TestCase):
    def test_pre_cancelled_capture_does_not_start_child(self):
        cancelled = threading.Event()
        cancelled.set()
        with patch.object(fleet.subprocess, "Popen") as popen, self.assertRaisesRegex(fleet.Refused, "operation_cancelled"):
            fleet.capture(["/usr/bin/true"], 30, {}, cancel_event=cancelled)
        popen.assert_not_called()

    def test_running_capture_cancels_without_waiting_for_thirty_second_timeout(self):
        cancelled = threading.Event()
        with tempfile.TemporaryDirectory(prefix="acfs-capture-cancel-") as tmp:
            marker = Path(tmp) / "pid"
            child = "import os,pathlib,signal,sys,time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(30)"
            with ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(fleet.capture, [sys.executable, "-I", "-c", child, str(marker)],
                                     30, {"PATH": "/usr/bin:/bin"}, cancel_event=cancelled)
                try:
                    end = time.monotonic() + 3
                    while not marker.exists() and time.monotonic() < end:
                        time.sleep(0.01)
                    self.assertTrue(marker.exists())
                finally:
                    cancelled.set()
                with self.assertRaisesRegex(fleet.Refused, "operation_cancelled"):
                    future.result(timeout=3)
            with self.assertRaises(ProcessLookupError):
                os.kill(int(marker.read_text()), 0)

    def test_cancellation_does_not_weaken_output_limit(self):
        cancelled = threading.Event()
        with self.assertRaisesRegex(fleet.Refused, "ssh_output_limit"):
            fleet.capture([sys.executable, "-I", "-c", "import sys; sys.stderr.write('x'*4097)"],
                          3, {"PATH": "/usr/bin:/bin"}, limit=4096, cancel_event=cancelled)


if __name__ == "__main__":
    unittest.main()
