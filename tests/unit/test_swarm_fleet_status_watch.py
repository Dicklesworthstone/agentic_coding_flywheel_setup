#!/usr/bin/env python3
"""Finite watch scheduling, evidence transitions, and pinned journals without SSH."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import redirect_stdout
import fcntl
import io
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import sys
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import test_swarm_fleet_status as fixtures

status, fleet, dispatch = fixtures.status, fixtures.fleet, fixtures.dispatch


class Clock:
    def __init__(self, on_wait=lambda: None):
        self.now = 100.0
        self.delays = []
        self.event = threading.Event()
        self.on_wait = on_wait

    def monotonic(self):
        return self.now

    def is_set(self):
        return self.event.is_set()

    def set(self):
        self.event.set()

    def wait(self, delay):
        self.on_wait()
        self.delays.append(delay)
        self.now += delay
        return self.is_set()


class Output(io.StringIO):
    def __init__(self):
        super().__init__()
        self.flushes = 0

    def flush(self):
        self.flushes += 1
        super().flush()


class WatchTests(unittest.TestCase):
    def setUp(self):
        self.addCleanup(os.umask, os.umask(0o022))
        self.temp = tempfile.TemporaryDirectory(prefix="acfs-status-watch-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.fx = fixtures.FleetFixture(self.root)
        self.args = SimpleNamespace(launch_state=str(self.fx.launch_path), dispatch_state=str(self.fx.work_path),
                                   watch=5, interval=2, timeout=10, deadline=30, export_max_age=300, workers=2)

    def run_watch(self, *, clock=None, factory=None):
        clock = clock or Clock()
        output = Output()
        factory = factory or (lambda *args, **kwargs: self.fx.observe)
        with patch.object(status.time, "monotonic", clock.monotonic), \
             patch.object(status, "transport", side_effect=factory) as transport, redirect_stdout(output):
            code = status.watch(self.args, self.fx.known, self.fx.key, clock)
        reports = [json.loads(line) for line in output.getvalue().splitlines()]
        return reports, code, clock, output, transport

    def test_finite_watch_emits_flushed_json_lines_instead_of_overlapping_samples(self):
        before = self.fx.snapshot()
        reports, code, clock, output, transport = self.run_watch()
        self.assertEqual(code, 0)
        self.assertEqual([r["watch"]["sample"] for r in reports], [1, 2, 3])
        self.assertEqual(clock.delays, [2, 2, 1])
        self.assertEqual(clock.now, 105)
        self.assertEqual(output.flushes, 3)
        self.assertTrue(all(r["watch"]["changes"] == [] for r in reports))
        self.assertTrue(all(r["schema"] == status.SCHEMA and r["read_only"] for r in reports))
        self.assertTrue(all(not r["task_completion_verified"] and not r["sends_prompts"] for r in reports))
        self.assertEqual([c.kwargs["stop_at"] for c in transport.call_args_list], [105, 105, 105])
        self.assertEqual(before, self.fx.snapshot())

    def test_default_interval_is_clipped_to_remaining_watch_duration(self):
        self.args.watch, self.args.interval = 2, None
        reports, code, clock, _, _ = self.run_watch()
        self.assertEqual(code, 0)
        self.assertEqual(len(reports), 1)
        self.assertEqual(reports[0]["watch"]["interval_seconds"], 5)
        self.assertEqual(clock.delays, [2])
        self.assertEqual(clock.now, 102)

    def test_journal_locks_are_released_between_samples(self):
        checks = []
        def idle():
            for path in (self.fx.launch_path, self.fx.work_path):
                with fleet.directory_fd(path, private=True) as fd:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertFalse(any(t.name.startswith("acfs-status") for t in threading.enumerate()))
            checks.append(True)
        reports, code, _, _, _ = self.run_watch(clock=Clock(idle))
        self.assertEqual(code, 0)
        self.assertEqual(len(checks), len(reports))

    def test_attention_is_sticky_and_stale_closed_work_is_not_carried_forward(self):
        sample = 0
        def factory(*args, **kwargs):
            nonlocal sample
            sample += 1
            def invoke(entry, mode):
                if sample == 2 and entry["host"]["id"] == "one" and mode == "launch-status":
                    raise fleet.Refused("native_launch_unconfirmed")
                code, raw = self.fx.observe(entry, mode)
                if mode == "work-snapshot":
                    value = fleet.decode(raw)
                    for item in value["items"]:
                        item["status"] = "closed"
                    if sample == 2:
                        value["age_seconds"] = 301
                    raw = fleet.encoded(value)
                return code, raw
            return invoke
        reports, code, _, _, _ = self.run_watch(factory=factory)
        self.assertEqual(code, 1)
        self.assertEqual([r["status"] for r in reports], ["observed", "attention", "observed"])
        self.assertEqual([r["watch"]["attention_seen"] for r in reports], [False, True, True])
        self.assertEqual(reports[1]["summary"]["recent_export_states"]["closed"], 0)
        self.assertEqual(reports[1]["summary"]["unobserved_work_items"], 4)
        stale = [c for c in reports[1]["watch"]["changes"] if c["kind"] == "bead"]
        self.assertEqual(len(stale), 4)
        self.assertTrue(all(c["before"] == "closed" and c["after"] == "unobserved" for c in stale))
        restored = [c for c in reports[2]["watch"]["changes"] if c["kind"] == "bead"]
        self.assertTrue(all(c["before"] == "unobserved" and c["after"] == "closed" for c in restored))
        self.assertTrue(all(r["task_completion_verified"] is False for r in reports))

    def test_new_observation_does_not_reuse_a_prior_confirmed_submission(self):
        sample = 0
        def factory(*args, **kwargs):
            nonlocal sample
            sample += 1
            def invoke(entry, mode):
                if sample >= 2 and mode == "read-receipt":
                    return 2, b"SECRET-RAW-FAILURE"
                return self.fx.observe(entry, mode)
            return invoke
        reports, code, _, _, _ = self.run_watch(factory=factory)
        self.assertEqual(code, 1)
        self.assertEqual([r["summary"]["confirmed_submissions"] for r in reports], [4, 0, 0])
        changes = [c for c in reports[1]["watch"]["changes"] if c["kind"] == "delivery"]
        self.assertEqual(len(changes), 4)
        self.assertTrue(all(c["before"]["status"] == "submitted" and c["after"]["status"] == "unconfirmed" for c in changes))
        self.assertNotIn("SECRET", json.dumps(reports))

    def test_intent_byte_changes_between_samples_fail_before_any_new_remote_calls(self):
        path = self.fx.work_path / "intent.json"
        def changed():
            path.write_bytes(path.read_bytes() + b" ")
        with self.assertRaisesRegex(fleet.Refused, "watch_source_changed"):
            self.run_watch(clock=Clock(changed))
        # One complete two-host sample; even semantically equal new JSON cannot
        # become a new watch authority on the next sample.
        self.assertEqual(len(self.fx.calls), 12)

    def test_identical_replacement_directory_is_not_silently_adopted(self):
        path = self.fx.launch_path
        def replaced():
            saved = self.root / "retained-original-launch"
            path.rename(saved)
            shutil.copytree(saved, path)
        with self.assertRaisesRegex(fleet.Refused, "watch_source_changed"):
            self.run_watch(clock=Clock(replaced))
        self.assertEqual(len(self.fx.calls), 12)

    def test_dispatch_directory_replacement_is_detected_too(self):
        path = self.fx.work_path
        def replaced():
            saved = self.root / "retained-original-work"
            path.rename(saved)
            shutil.copytree(saved, path)
        with self.assertRaisesRegex(fleet.Refused, "watch_source_changed"):
            self.run_watch(clock=Clock(replaced))
        self.assertEqual(len(self.fx.calls), 12)

    def test_legitimate_dispatch_progress_between_samples_can_be_observed(self):
        parent = self.root / "partial"
        parent.mkdir()
        self.fx = fixtures.FleetFixture(parent, send_failure="one")
        self.args.launch_state, self.args.dispatch_state = str(self.fx.launch_path), str(self.fx.work_path)
        progressed = False
        def resume_between_samples():
            nonlocal progressed
            if progressed:
                return
            spec = {"schema": dispatch.SPEC_SCHEMA, "hosts": [
                {"id": e["host"]["id"], "batch": e["batch"]} for e in self.fx.work["hosts"]]}
            def invoke(entry, mode):
                if mode in ("read-receipt", "query-receipt"):
                    return self.fx.observe(entry, mode)
                return self.fx.preview(entry, mode)
            result, code = dispatch.execute(str(self.fx.launch_path), spec, self.fx.known, self.fx.key,
                str(self.fx.work_path), 360, "resume", fleet.digest(fleet.encoded(self.fx.work)), invoke)
            self.assertEqual((code, result["status"]), (0, "submitted"))
            progressed = True
        reports, code, _, _, _ = self.run_watch(clock=Clock(resume_between_samples))
        self.assertTrue(progressed)
        self.assertEqual(code, 1)  # The first partial observation is not erased.
        self.assertEqual([r["summary"]["confirmed_submissions"] for r in reports], [2, 4, 4])
        self.assertEqual(len({r["dispatch_plan_sha256"] for r in reports}), 1)
        self.assertTrue(any(c["kind"] == "delivery" and c["host"] == "two" for c in reports[1]["watch"]["changes"]))

    def test_cancellation_during_interval_stops_before_a_second_sample(self):
        clock = Clock()
        clock.on_wait = clock.set
        with self.assertRaisesRegex(fleet.Refused, "operation_cancelled"):
            self.run_watch(clock=clock)
        self.assertEqual(len(self.fx.calls), 12)
        for path in (self.fx.launch_path, self.fx.work_path):
            with fleet.directory_fd(path, private=True) as fd:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_overall_watch_deadline_shrinks_later_sample_transport_budget(self):
        clock, budgets = Clock(), []
        self.args.workers, self.args.interval = 1, 1
        self.args.dispatch_state = None
        real_transport = status.transport
        def factory(known, identity, timeout, deadline, **kwargs):
            def runner(argv, remaining, env):
                budgets.append(remaining)
                host = next(h for h in self.fx.hosts if h["host"] == argv[-2])
                clock.now += 1
                return self.fx.native(host, "reconcile")
            return real_transport(known, identity, timeout, deadline, runner=runner, ssh="/usr/bin/true", **kwargs)
        reports, code, _, _, _ = self.run_watch(clock=clock, factory=factory)
        self.assertEqual((code, len(reports)), (0, 2))
        self.assertEqual(budgets, [5, 4, 2, 1])
        self.assertEqual(clock.delays, [1])
        self.assertEqual(clock.now, 105)

    def test_local_errors_are_not_retried_or_converted_into_watch_success(self):
        def corrupt():
            (self.fx.work_path / "one.result.json").write_bytes(b"invalid-json")
        with self.assertRaises(fleet.Refused):
            self.run_watch(clock=Clock(corrupt))
        self.assertEqual(len(self.fx.calls), 12)

    def test_invalid_watch_options_are_refused_before_trust_or_ssh_reads(self):
        base = ["--launch-state", "/missing", "--known-hosts", "/missing", "--identity-file", "/missing"]
        for options in (["--watch", "0"], ["--watch", "86401"], ["--interval", "1"],
                        ["--watch", "5", "--interval", "0"], ["--watch", "5", "--interval", "3601"]):
            with self.subTest(options=options), patch.object(fleet, "read_input") as read, \
                 patch.object(status, "transport") as transport, self.assertRaises(fleet.Refused):
                status.main(base + options)
            read.assert_not_called()
            transport.assert_not_called()

    def test_main_routes_watch_without_a_bonus_single_sample(self):
        known, key = self.root / "known", self.root / "key"
        known.write_bytes(self.fx.known)
        key.write_bytes(self.fx.key)
        key.chmod(0o600)
        args = ["--launch-state", str(self.fx.launch_path), "--known-hosts", str(known),
                "--identity-file", str(key), "--watch", "5", "--interval", "2"]
        with patch.object(status, "watch", return_value=1) as watch, \
             patch.object(status, "collect") as collect, redirect_stdout(io.StringIO()) as out:
            self.assertEqual(status.main(args), 1)
            self.assertEqual(watch.call_args.args[0].workers, 4)
            self.assertEqual(watch.call_args.args[1:3], (self.fx.known, self.fx.key))
        collect.assert_not_called()
        self.assertEqual(out.getvalue(), "")

    def test_watch_errors_after_samples_are_also_single_line_json(self):
        def fail_after_sample():
            status.emit({"schema": status.SCHEMA, "status": "observed"}, jsonl=True)
            raise fleet.Refused("watch_source_changed")
        for argv in (["status", "--watch", "5"], ["status", "--watch=5"]):
            with self.subTest(argv=argv), patch.object(sys, "argv", argv), \
                 patch.object(status.signal, "signal"), patch.object(status, "main", side_effect=fail_after_sample), \
                 redirect_stdout(io.StringIO()) as out:
                self.assertEqual(status.cli(), 2)
            lines = out.getvalue().splitlines()
            self.assertEqual(len(lines), 2)
            report = json.loads(lines[1])
            self.assertEqual(report["code"], "watch_source_changed")
            self.assertTrue(report["read_only"])
            self.assertFalse(report["task_completion_verified"])

    def test_signal_report_in_watch_mode_is_json_lines(self):
        with patch.object(sys, "argv", ["status", "--watch", "5"]), \
             patch.object(status.signal, "signal"), patch.object(status, "main", side_effect=fleet.Interrupted(15)), \
             redirect_stdout(io.StringIO()) as out:
            self.assertEqual(status.cli(), 143)
        self.assertEqual(len(out.getvalue().splitlines()), 1)
        self.assertEqual(json.loads(out.getvalue())["status"], "interrupted")

    def test_broken_output_stops_cleanly_without_a_second_write(self):
        class BrokenOutput:
            closed = False
            writes = 0
            def write(self, _text):
                self.writes += 1
                raise BrokenPipeError()
            def close(self):
                self.closed = True
        output = BrokenOutput()
        with patch.object(status.signal, "signal"), \
             patch.object(status, "main", side_effect=lambda: status.emit({}, jsonl=True)), \
             patch.object(sys, "stdout", output):
            self.assertEqual(status.cli(), 1)
        self.assertTrue(output.closed)
        self.assertEqual(output.writes, 1)

    def test_broken_output_during_error_reporting_preserves_failure_exit(self):
        with patch.object(status.signal, "signal"), \
             patch.object(status, "main", side_effect=fleet.Refused("watch_source_changed")), \
             patch.object(status, "emit", side_effect=BrokenPipeError()) as emit, \
             patch.object(status, "close_output") as close:
            self.assertEqual(status.cli(), 2)
        self.assertEqual(emit.call_count, 1)
        close.assert_called_once_with()

    def test_starting_during_recovery_emits_busy_then_observes_without_ssh_while_locked(self):
        for journal in (self.fx.launch_path, self.fx.work_path):
            with self.subTest(journal=journal), fleet.directory_fd(journal, private=True) as fd:
                self.fx.calls.clear()
                before = self.fx.snapshot()
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                def release():
                    if not self.fx.calls:
                        self.assertEqual(before, self.fx.snapshot())
                    fcntl.flock(fd, fcntl.LOCK_UN)
                reports, code, _, _, _ = self.run_watch(clock=Clock(release))
            self.assertEqual(code, 1)
            self.assertEqual([r["status"] for r in reports], ["busy", "observed", "observed"])
            busy = reports[0]
            self.assertEqual(busy["code"], "fleet_operation_in_progress")
            self.assertEqual(busy["hosts"], [])
            self.assertIsNone(busy["summary"])
            self.assertTrue(busy["watch"]["observation_skipped"])
            self.assertEqual(reports[1]["watch"]["skipped_samples_since_previous_observation"], 1)
            self.assertEqual(len(self.fx.calls), 24)
            self.assertEqual(before, self.fx.snapshot())

    def test_lock_held_for_whole_watch_is_bounded_and_never_reported_healthy(self):
        with fleet.directory_fd(self.fx.launch_path, private=True) as fd:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            reports, code, clock, output, _ = self.run_watch()
        self.assertEqual((code, clock.now, output.flushes), (1, 105, 3))
        self.assertTrue(all(r["status"] == "busy" and r["summary"] is None for r in reports))
        self.assertTrue(all(r["watch"]["attention_seen"] for r in reports))
        self.assertEqual(self.fx.calls, [])

    def test_lock_gap_keeps_changes_relative_to_last_actual_observation(self):
        waits = 0
        with fleet.directory_fd(self.fx.work_path, private=True) as fd:
            def switch_lock():
                nonlocal waits
                waits += 1
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB if waits == 1 else fcntl.LOCK_UN)
            reports, code, _, _, _ = self.run_watch(clock=Clock(switch_lock))
        self.assertEqual(code, 1)
        self.assertEqual([r["status"] for r in reports], ["observed", "busy", "observed"])
        self.assertIsNone(reports[1]["summary"])
        self.assertEqual(reports[1]["watch"]["changes"], [])
        self.assertEqual(reports[2]["watch"]["previous_observation_sample"], 1)
        self.assertEqual(reports[2]["watch"]["skipped_samples_since_previous_observation"], 1)
        self.assertEqual(reports[2]["watch"]["changes"], [])
        self.assertEqual(len(self.fx.calls), 24)

    def test_receipt_rewriting_between_samples_is_not_append_only(self):
        for journal in (self.fx.launch_path, self.fx.work_path):
            for name in ("one.attempt.json", "one.result.json"):
                with self.subTest(journal=journal, name=name):
                    binding = {}
                    path = journal / name
                    original = path.read_bytes()
                    work_path = None if journal == self.fx.launch_path else self.fx.work_path
                    try:
                        status.collect(self.fx.launch_path, work_path, self.fx.known, self.fx.key,
                                       self.fx.observe, watch_binding=binding)
                        self.fx.calls.clear()
                        path.write_bytes(original + b" ")
                        with self.assertRaisesRegex(fleet.Refused, "watch_history_changed"):
                            status.collect(self.fx.launch_path, work_path, self.fx.known, self.fx.key,
                                           self.fx.observe, watch_binding=binding)
                        self.assertEqual(self.fx.calls, [])
                    finally:
                        path.write_bytes(original)

    def test_changed_launch_target_cannot_be_rebound_as_original_on_next_sample(self):
        binding = {}
        status.collect(self.fx.launch_path, None, self.fx.known, self.fx.key,
                       self.fx.observe, watch_binding=binding)
        self.fx.calls.clear()
        path = self.fx.launch_path / "two.result.json"
        value = fleet.decode(path.read_bytes())
        value["targets"][0]["pane_pid"] = "999"
        path.write_bytes(fleet.encoded(value))
        with self.assertRaisesRegex(fleet.Refused, "watch_history_changed"):
            status.collect(self.fx.launch_path, None, self.fx.known, self.fx.key,
                           self.fx.observe, watch_binding=binding)
        self.assertEqual(self.fx.calls, [])

    def test_coherent_history_rollback_is_refused_before_remote_observation(self):
        for suffix in ("result", "attempt"):
            with self.subTest(suffix=suffix):
                parent = self.root / suffix
                parent.mkdir()
                fx = fixtures.FleetFixture(parent, send=False)
                binding = {}
                status.collect(fx.launch_path, None, fx.known, fx.key, fx.observe, watch_binding=binding)
                fx.calls.clear()
                (fx.launch_path / "two.result.json").rename(parent / "retained-result.json")
                if suffix == "attempt":
                    (fx.launch_path / "two.attempt.json").rename(parent / "retained-attempt.json")
                with self.assertRaisesRegex(fleet.Refused, "watch_history_changed"):
                    status.collect(fx.launch_path, None, fx.known, fx.key, fx.observe, watch_binding=binding)
                self.assertEqual(fx.calls, [])

    def test_dispatch_rollback_is_not_mistaken_for_unattempted_work(self):
        binding = {}
        status.collect(self.fx.launch_path, self.fx.work_path, self.fx.known, self.fx.key,
                       self.fx.observe, watch_binding=binding)
        self.fx.calls.clear()
        for suffix in ("attempt", "result"):
            (self.fx.work_path / ("two." + suffix + ".json")).rename(self.root / ("retained-" + suffix + ".json"))
        with self.assertRaisesRegex(fleet.Refused, "watch_history_changed"):
            status.collect(self.fx.launch_path, self.fx.work_path, self.fx.known, self.fx.key,
                           self.fx.observe, watch_binding=binding)
        self.assertEqual(self.fx.calls, [])

    def test_initial_busy_directory_cannot_be_replaced_before_first_observation(self):
        for name in ("launch", "work"):
            with self.subTest(name=name):
                parent = self.root / ("busy-" + name)
                parent.mkdir()
                fx = fixtures.FleetFixture(parent)
                self.args.launch_state, self.args.dispatch_state = str(fx.launch_path), str(fx.work_path)
                path = parent / name
                with fleet.directory_fd(path, private=True) as fd:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    def replace():
                        retained = parent / "retained-original"
                        path.rename(retained)
                        shutil.copytree(retained, path)
                        fcntl.flock(fd, fcntl.LOCK_UN)
                    with self.assertRaisesRegex(fleet.Refused, "watch_source_changed"):
                        self.run_watch(clock=Clock(replace), factory=lambda *a, **kw: fx.observe)
                self.assertEqual(fx.calls, [])

    def test_source_guard_is_checked_inside_first_sample_before_remote_calls(self):
        def replace_between_guard_and_collect(*args, **kwargs):
            path = self.fx.launch_path
            retained = self.root / "retained-first-source"
            path.rename(retained)
            shutil.copytree(retained, path)
            return self.fx.observe
        with self.assertRaisesRegex(fleet.Refused, "watch_source_changed"):
            self.run_watch(factory=replace_between_guard_and_collect)
        self.assertEqual(self.fx.calls, [])

    def test_new_results_become_immutable_after_legitimate_launch_resume(self):
        parent = self.root / "resume-launch"
        parent.mkdir()
        fx = fixtures.FleetFixture(parent, launch=False, send=False)
        with fleet.directory_fd(fx.launch_path, private=True) as fd:
            fleet.publish(fd, "one.attempt.json", fleet.host_intent(fx.plan, fx.hosts[0]))
        binding = {}
        def sample():
            return status.collect(fx.launch_path, None, fx.known, fx.key, fx.observe, watch_binding=binding)
        self.assertEqual(sample()[1], 1)
        result, code = fleet.execute(fx.plan, "resume", fleet.digest(fleet.encoded(fx.plan)), fx.native)
        self.assertEqual((code, result["status"]), (0, "ready"))
        report, code = sample()
        self.assertEqual((code, report["summary"]["verified_live_agents"]), (0, 4))
        self.assertFalse(report["starts_agents"])
        fx.calls.clear()
        (fx.launch_path / "two.result.json").rename(parent / "retained-new-result.json")
        with self.assertRaisesRegex(fleet.Refused, "watch_history_changed"):
            sample()
        self.assertEqual(fx.calls, [])

    def test_watch_survives_actual_cooperating_dispatch_resume(self):
        parent = self.root / "resume-dispatch"
        parent.mkdir()
        fx = fixtures.FleetFixture(parent, send_failure="one")
        self.args.launch_state, self.args.dispatch_state = str(fx.launch_path), str(fx.work_path)
        spec = {"schema": dispatch.SPEC_SCHEMA, "hosts": [
            {"id": e["host"]["id"], "batch": e["batch"]} for e in fx.work["hosts"]]}
        entered, release = threading.Event(), threading.Event()
        recovery_calls, observer_calls, futures, waits = [], [], [], []
        def recover_peer(entry, mode):
            recovery_calls.append((entry["host"]["id"], mode))
            if not entered.is_set():
                entered.set()  # Actual resume already holds both journal locks.
                self.assertTrue(release.wait(3))
            if mode in ("read-receipt", "query-receipt"):
                return fx.observe(entry, mode)
            return fx.preview(entry, mode)
        def observer(entry, mode):
            self.assertFalse(entered.is_set() and not release.is_set())
            observer_calls.append((entry["host"]["id"], mode))
            return fx.observe(entry, mode)
        with ThreadPoolExecutor(max_workers=1) as pool:
            def interval():
                waits.append(len(observer_calls))
                if len(waits) == 1:
                    futures.append(pool.submit(dispatch.execute, str(fx.launch_path), spec, fx.known, fx.key,
                        str(fx.work_path), 360, "resume", fleet.digest(fleet.encoded(fx.work)), recover_peer))
                    self.assertTrue(entered.wait(3))
                elif len(waits) == 2:
                    self.assertEqual(waits[0], waits[1])  # Busy sample did not probe.
                    release.set()
                    result, code = futures[0].result(timeout=3)
                    self.assertEqual((code, result["status"]), (0, "submitted"))
            try:
                reports, code, _, _, _ = self.run_watch(clock=Clock(interval), factory=lambda *a, **kw: observer)
            finally:
                release.set()
        self.assertEqual(code, 1)
        self.assertEqual([r["status"] for r in reports], ["attention", "busy", "observed"])
        self.assertEqual(reports[0]["summary"]["confirmed_submissions"], 2)
        self.assertIsNone(reports[1]["summary"])
        self.assertEqual(reports[2]["summary"]["confirmed_submissions"], 4)
        self.assertEqual(reports[2]["watch"]["previous_observation_sample"], 1)
        self.assertEqual(reports[2]["watch"]["skipped_samples_since_previous_observation"], 1)
        self.assertEqual([(h, m) for h, m in recovery_calls if m == "send"], [("two", "send")])
        self.assertFalse(any(m in ("send", "preview") for _, m in observer_calls))
        self.assertTrue(all(not r["sends_prompts"] and not r["starts_agents"] for r in reports))

    def test_initial_busy_journal_corruption_is_fatal_after_lock_release(self):
        path = self.fx.work_path / "intent.json"
        with fleet.directory_fd(self.fx.work_path, private=True) as fd:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            def corrupt_and_release():
                path.write_bytes(b"not-json")
                fcntl.flock(fd, fcntl.LOCK_UN)
            with self.assertRaisesRegex(fleet.Refused, "invalid_json"):
                self.run_watch(clock=Clock(corrupt_and_release))
        self.assertEqual(self.fx.calls, [])

    def test_cancellation_during_busy_interval_releases_directory_handles(self):
        clock = Clock()
        clock.on_wait = clock.set
        before = len(os.listdir("/proc/self/fd"))
        with fleet.directory_fd(self.fx.launch_path, private=True) as fd:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(fleet.Refused, "operation_cancelled"):
                self.run_watch(clock=clock)
        self.assertEqual(self.fx.calls, [])
        self.assertEqual(len(os.listdir("/proc/self/fd")), before)

    def test_invalid_dispatch_path_is_not_masked_by_busy_launch(self):
        for nested in (False, True):
            path = self.fx.launch_path / "nested" if nested else self.fx.launch_path
            if nested:
                path.mkdir(mode=0o700)
            self.args.dispatch_state = str(path)
            with self.subTest(nested=nested), fleet.directory_fd(self.fx.launch_path, private=True) as fd:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with self.assertRaisesRegex(fleet.Refused, "dispatch_state_must_be_outside_launch_journal"):
                    self.run_watch()
        self.assertEqual(self.fx.calls, [])

    def test_real_cli_flushes_before_exit_and_stops_at_finite_watch_duration(self):
        known, key = self.root / "known", self.root / "key"
        known.write_bytes(self.fx.known)
        key.write_bytes(self.fx.key)
        key.chmod(0o600)
        # Only replace the protocol peer. Exercise actual CLI parsing, watch
        # scheduling, journal pinning, worker lifetime, output flushing and exit.
        harness = r'''
import importlib.util, sys
spec = importlib.util.spec_from_file_location("fixtures", sys.argv[1])
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)
peer = fixtures.FleetFixture.__new__(fixtures.FleetFixture)
peer.calls = []
mod = fixtures.status
mod.transport = lambda *args, **kwargs: peer.observe
sys.argv = ["fleet-status", *sys.argv[2:]]
sys.exit(mod.cli())
'''
        process = subprocess.Popen(["/usr/bin/python3", "-I", "-c", harness,
            str(fixtures.ROOT / "tests/unit/test_swarm_fleet_status.py"),
            "--launch-state", str(self.fx.launch_path), "--dispatch-state", str(self.fx.work_path),
            "--known-hosts", str(known), "--identity-file", str(key), "--watch", "2", "--interval", "1"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                self.assertTrue(selector.select(timeout=1.5), "First sample was not flushed")
                first = json.loads(process.stdout.readline())
            self.assertIsNone(process.poll(), "Output appeared only after process exit")
            self.assertEqual(first["watch"]["sample"], 1)
            rest, error = process.communicate(timeout=4)
            self.assertEqual((process.returncode, error), (0, b""))
            reports = [first, *[json.loads(line) for line in rest.splitlines()]]
            self.assertEqual([r["watch"]["sample"] for r in reports], [1, 2])
            self.assertTrue(all(r["summary"]["confirmed_submissions"] == 4 for r in reports))
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=5)


if __name__ == "__main__":
    unittest.main()
