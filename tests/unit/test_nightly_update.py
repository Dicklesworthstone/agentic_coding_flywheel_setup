#!/usr/bin/env python3
"""Offline regressions for the real nightly wrapper (issue #448) and for direct
`acfs update --yes` runs recording into the same health record (issue #483).

Run: python3 -m unittest discover -s tests/unit -p test_nightly_update.py -v
The real updater entrypoint uses stubbed components and disposable runtime
files. No package operations, host cleanup, real sleeps, network, or systemd
changes are performed.
"""
import datetime
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
WRAPPER = ROOT / "scripts/lib/nightly_update.sh"
FIELDS = ("version", "outcome", "reason", "last_attempt", "last_success",
          "first_skip", "skip_date", "skipped_nights", "attempt", "next_retry")
START = int(datetime.datetime(2026, 10, 9, 4, tzinfo=datetime.timezone.utc).timestamp())

MOCKS = r'''
fixture_metric() {
    local name="$1" count=0 value
    local -a values=()
    if [[ -f "$FIXTURE/$name.count" ]]; then read -r count < "$FIXTURE/$name.count"; fi
    mapfile -t values < "$FIXTURE/$name"
    value="${values[count]:-${values[${#values[@]}-1]}}"
    printf '%s\n' "$((count + 1))" > "$FIXTURE/$name.count"
    [[ "$value" != ERROR ]] || return 1
    [[ "$value" != EMPTY ]] || return 0
    printf '%s\n' "$value"
}
nproc() { fixture_metric cpu; }
awk() {
    if [[ "${2:-}" == /proc/loadavg ]]; then fixture_metric load
    else command awk "$@"; fi
}
df() { printf 'Avail\n'; fixture_metric disk; }
date() {
    local now
    read -r now < "$FIXTURE/clock"
    command date -u -d "@$now" "$@"
}
sleep() {
    local now
    printf '%s\n' "$1" >> "$FIXTURE/sleeps"
    read -r now < "$FIXTURE/clock"
    printf '%s\n' "$((now + $1))" > "$FIXTURE/clock"
}
# The tested process must never clean up anything on the test runner.
find() { return 0; }
rm() { printf 'unexpected cleanup\n' >&2; return 99; }
'''


class NightlyUpdateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="acfs-nightly-test-")
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.acfs = self.home / ".acfs"
        self.bin = self.acfs / "bin"
        self.bin.mkdir(parents=True)
        self.state = self.acfs / "nightly-update.state"
        self.mocks = self.home / "mocks.sh"
        self.mocks.write_text(MOCKS)
        updater = self.bin / "acfs-update"
        updater.write_text('''#!/usr/bin/env bash
if [[ "${1:-}" == --help ]]; then echo --no-self-update; exit 0; fi
printf '%s\\n' "$*" >> "$FIXTURE/updates"
exit "${FIXTURE_UPDATE_RC:-0}"
''')
        updater.chmod(0o755)
        self.env = {**os.environ, "HOME": str(self.home), "TARGET_HOME": str(self.home),
                    "ACFS_HOME": str(self.acfs), "ACFS_STATE_FILE": str(self.acfs / "state.json"),
                    "ACFS_SYSTEM_STATE_FILE": str(self.home / "no-system-state.json"),
                    "ACFS_BIN_DIR": str(self.bin), "BASH_ENV": str(self.mocks),
                    "FIXTURE": str(self.home), "ACFS_NIGHTLY_MAX_RETRIES": "2",
                    "ACFS_NIGHTLY_RETRY_DELAY_SECONDS": "1800",
                    "ACFS_NIGHTLY_SELF_UPDATE": "false"}
        self.set_clock(START)
        self.metrics()

    def set_clock(self, value):
        (self.home / "clock").write_text(f"{value}\n")

    def metrics(self, cpu=("8",), load=("0.5",), disk=("8388608",)):
        for name, values in (("cpu", cpu), ("load", load), ("disk", disk)):
            (self.home / name).write_text("\n".join(values) + "\n")
            (self.home / f"{name}.count").write_text("0\n")

    def run_wrapper(self, rc=0, **env):
        result = subprocess.run(["bash", str(WRAPPER)], env={**self.env, **env},
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, rc, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def read_state(self):
        values = self.state.read_text().rstrip("\n").split("\t")
        self.assertEqual(len(values), len(FIELDS))
        return dict(zip(FIELDS, values))

    def assert_probes(self, count):
        for name in ("cpu", "load", "disk"):
            self.assertEqual(int((self.home / f"{name}.count").read_text()), count, name)

    def assert_no_update(self):
        self.assertFalse((self.home / "updates").exists())

    def test_repeated_skips_count_nights_not_attempts_or_same_day_reruns(self):
        for day in range(4):
            self.set_clock(START + day * 86400)
            self.metrics(load=("19.1",))
            output = self.run_wrapper()
            state = self.read_state()
            self.assertEqual(state["outcome"], "skipped")
            self.assertEqual(state["skipped_nights"], str(day + 1))
            self.assertEqual(state["last_success"], "0")
            self.assertEqual(state["first_skip"], str(START))
            self.assertEqual(state["attempt"], "3")
            self.assertEqual(state["next_retry"], "0")
            self.assertIn("retry budget exhausted", output)
            self.assert_probes(3)
        self.run_wrapper()
        self.assertEqual(self.read_state()["skipped_nights"], "4")
        self.assertEqual((self.home / "sleeps").read_text().splitlines(), ["1800"] * 10)
        self.assert_no_update()
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o600)

    def test_each_retry_rechecks_disk_even_when_load_recovers(self):
        self.metrics(load=("10", "0.5", "0.5"), disk=("8388608", "1024", "8388608"))
        output = self.run_wrapper()
        self.assertIn("System overloaded", output)
        self.assertIn("Critically low", output)
        self.assert_probes(3)
        self.assertEqual((self.home / "updates").read_text().splitlines(),
                         ["--yes --quiet --no-self-update"])
        state = self.read_state()
        self.assertEqual(state["outcome"], "success")
        self.assertEqual(state["last_success"], str(START + 3600))
        self.assertEqual(state["skipped_nights"], "0")
        self.assertEqual(state["first_skip"], "0")
        self.assertEqual(state["skip_date"], "-")
        self.assertEqual(state["next_retry"], "0")

    def test_successful_manual_retry_resets_persisted_history(self):
        self.metrics(load=("8.0",))
        self.run_wrapper()
        self.set_clock(START + 86400)
        self.metrics()
        self.run_wrapper(ACFS_NIGHTLY_MAX_RETRIES="0")
        self.assert_probes(1)
        state = self.read_state()
        self.assertEqual(state["outcome"], "success")
        self.assertEqual(state["skipped_nights"], "0")
        self.assertEqual(state["last_success"], str(START + 86400))

    def test_missing_and_malformed_metrics_fail_closed_with_bounded_retries(self):
        for name, value in (("cpu", "ERROR"), ("cpu", "0"), ("cpu", "08"),
                            ("load", "ERROR"), ("load", "EMPTY"), ("load", "NaN"),
                            ("load", "x[$(touch bad)]"), ("disk", "ERROR"),
                            ("disk", "EMPTY"), ("disk", "-1"), ("disk", "999999999999999999999")):
            with self.subTest(metric=name, value=value):
                self.metrics(**{name: (value,)})
                self.run_wrapper()
                state = self.read_state()
                self.assertEqual(state["outcome"], "skipped")
                self.assertEqual(state["reason"], "metrics")
                self.assert_probes(3)
                self.assert_no_update()

    def test_partial_and_total_failure_do_not_claim_recovery(self):
        self.run_wrapper()
        self.set_clock(START + 86400)
        self.metrics(load=("18",))
        self.run_wrapper()
        for rc in (2, 1):
            self.metrics()
            self.run_wrapper(rc=rc, FIXTURE_UPDATE_RC=str(rc))
            state = self.read_state()
            self.assertEqual(state["outcome"], "failed")
            self.assertEqual(state["last_success"], str(START))
            self.assertEqual(state["skipped_nights"], "1")
            self.assert_probes(1)  # Never retry an updater that actually ran.

    def test_retry_window_crossing_midnight_is_one_night(self):
        midnight = int(datetime.datetime(2026, 10, 9, 23, 50,
                                        tzinfo=datetime.timezone.utc).timestamp())
        self.set_clock(midnight)
        self.metrics(load=("8.0",))
        self.run_wrapper()
        self.assertEqual(self.read_state()["skipped_nights"], "1")
        self.assertEqual(self.read_state()["skip_date"], "2026-10-09")

    def test_config_cannot_create_unbounded_or_arithmetic_injected_retries(self):
        for name, value in (("ACFS_NIGHTLY_MAX_RETRIES", "3"),
                            ("ACFS_NIGHTLY_MAX_RETRIES", "-1"),
                            ("ACFS_NIGHTLY_RETRY_DELAY_SECONDS", "0"),
                            ("ACFS_NIGHTLY_RETRY_DELAY_SECONDS", "1801"),
                            ("ACFS_NIGHTLY_RETRY_DELAY_SECONDS", "x[$(touch bad)]")):
            with self.subTest(name=name, value=value):
                self.run_wrapper(rc=1, **{name: value})
                self.assert_no_update()
                self.assert_probes(0)

    def test_corrupt_state_is_not_executed_or_overwritten(self):
        malicious = f"$(touch {self.home}/bad)\n"
        self.state.write_text(malicious)
        self.run_wrapper(rc=1)
        self.assertEqual(self.state.read_text(), malicious)
        self.assertFalse((self.home / "bad").exists())
        self.assert_no_update()

    def test_reader_is_safe_to_source_without_side_effects(self):
        result = subprocess.run(["bash", "-c", 'before=$-; old_home=$HOME; source "$1"; '
                                 '[[ "$before" == "$-" && "$old_home" == "$HOME" ]]; '
                                 'declare -F acfs_nightly_state_read', "test", str(WRAPPER)],
                                env=self.env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "acfs_nightly_state_read")
        self.assertFalse(self.state.exists())
        self.assert_no_update()


UPDATE = ROOT / "scripts/lib/update.sh"
# Every step main() runs is a no-op except update_apt, which sets the counters
# that decide main's exit status. Logging and the exit-status logic are real.
UPDATE_MAIN_STUBS = r'''
for fn in ensure_path update_ensure_writable_tmpdir update_acfs_self \
    update_procwatch_start update_procwatch_stop update_ensure_jq_available \
    cleanup_legacy_git_safety_guard cleanup_legacy_br_alias cleanup_legacy_bv_alias \
    cleanup_unmanaged_atuin_init update_bun update_agents update_cloud update_rust \
    update_cargo_tools update_uv update_go update_shell update_stack \
    update_root_agents_md update_report_service_binary_drift print_summary; do
    eval "$fn() { :; }"
done
update_apt() { SUCCESS_COUNT="$FIXTURE_SUCCESSES"; FAIL_COUNT="$FIXTURE_FAILURES"; }
'''

# Observe finalization while retaining the real health recorder and writer.
UPDATE_FINALIZATION_AUDIT = r'''
_fixture_record_definition="$(declare -f update_record_nightly_outcome)"
eval "${_fixture_record_definition/update_record_nightly_outcome/_fixture_record_nightly_outcome}"
unset _fixture_record_definition
update_record_nightly_outcome() {
    printf '%s\n' "$1" >> "$HOME/recorded-outcomes"
    _fixture_record_nightly_outcome "$@"
}
update_procwatch_stop() { printf 'stopped\n' >> "$HOME/watchdog-stops"; }
'''


class DirectUpdateRecordTests(unittest.TestCase):
    """A direct `acfs update --yes` refreshes the nightly record (issue #483)."""

    NOW = START + 10 * 86400

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="acfs-nightly-direct-")
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.acfs = self.home / ".acfs"
        self.acfs.mkdir()
        self.state = self.acfs / "nightly-update.state"
        self.env = {"PATH": os.environ["PATH"], "HOME": str(self.home), "LC_ALL": "C",
                    "TZ": "UTC", "NO_COLOR": "1"}

    def write(self, *fields):
        self.state.write_text("\t".join(map(str, ("1",) + fields)) + "\n")
        return self.state.read_bytes()

    def write_interrupted(self):
        # Shaped like the record in the report: an interrupted wrapper run with
        # one skipped night, after which every night ran update --yes directly.
        return self.write("interrupted", "interrupted", START, START - 86400,
                          START - 3600, "2026-10-08", 1, 1, 0)

    def read_state(self):
        values = self.state.read_text().rstrip("\n").split("\t")
        self.assertEqual(len(values), len(FIELDS))
        return dict(zip(FIELDS, values))

    RECORD = 'source "$1"; acfs_nightly_record_direct_update "$2" "$3" "$4"'
    # The wrapper holds nightly-update.lock for its whole retry window.
    RECORD_UNDER_WRAPPER_LOCK = ('exec 9>>"$(dirname "$2")/nightly-update.lock"; flock -n 9; '
                                 'source "$1"; acfs_nightly_record_direct_update "$2" "$3" "$4"')

    def record(self, rc, script=RECORD):
        return subprocess.run(
            ["bash", "-c", script, "test", str(WRAPPER), str(self.state), str(rc), str(self.NOW)],
            env=self.env, capture_output=True, text=True, timeout=10)

    def health(self, now=None):
        result = subprocess.run(
            ["bash", "-c", 'source "$1"; acfs_nightly_health_report "$2" "$3"',
             "test", str(WRAPPER), str(self.state), str(now or self.NOW + 60)],
            env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        level, _, encoded = result.stdout.rstrip("\n").split("\t")
        return level, json.loads(encoded)["code"]

    def run_update_main(self, *args, successes=5, failures=0, overrides="", extra_env=None):
        result = subprocess.run(
            ["bash", "-c", 'source "$1"; eval "$STUBS"; shift; main "$@"',
             "test", str(UPDATE), *args],
            env={**self.env, "STUBS": UPDATE_MAIN_STUBS + overrides,
                 "FIXTURE_SUCCESSES": str(successes), "FIXTURE_FAILURES": str(failures),
                 **(extra_env or {})},
            capture_output=True, text=True, timeout=30)
        return result

    def assert_failure_recorded(self, previous):
        state = self.read_state()
        self.assertEqual((state["outcome"], state["reason"]), ("failed", "update"))
        for field in ("last_success", "first_skip", "skip_date", "skipped_nights"):
            self.assertEqual(state[field], previous[field], field)
        self.assertNotEqual(state["last_attempt"], previous["last_attempt"])
        self.assertEqual((state["attempt"], state["next_retry"]), ("1", "0"))
        self.assertEqual(self.health(now=int(time.time()) + 60), ("warn", "failed"))

    def test_successful_direct_update_clears_the_stale_warning(self):
        self.write_interrupted()
        self.assertEqual(self.health(), ("warn", "interrupted"))
        result = self.record(0)
        self.assertEqual(result.returncode, 0, result.stderr)
        state = self.read_state()
        self.assertEqual(state["outcome"], "success")
        self.assertEqual(state["reason"], "none")
        self.assertEqual(state["last_attempt"], str(self.NOW))
        self.assertEqual(state["last_success"], str(self.NOW))
        self.assertEqual((state["skipped_nights"], state["first_skip"], state["skip_date"]),
                         ("0", "0", "-"))
        self.assertEqual(self.health(), ("pass", "success"))
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o600)

    def test_failed_direct_update_is_recorded_without_claiming_recovery(self):
        self.write("skipped", "load", START, START - 86400, START - 3600, "2026-10-09", 2, 3, 0)
        for rc in (2, 1):
            with self.subTest(rc=rc):
                result = self.record(rc)
                self.assertEqual(result.returncode, 0, result.stderr)
                state = self.read_state()
                self.assertEqual((state["outcome"], state["reason"]), ("failed", "update"))
                self.assertEqual(state["last_attempt"], str(self.NOW))
                self.assertEqual(state["last_success"], str(START - 86400))
                self.assertEqual(state["skipped_nights"], "2")
                self.assertEqual(self.health(), ("warn", "failed"))

    def test_only_an_existing_valid_record_is_refreshed(self):
        result = self.record(0)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertFalse(self.state.exists())
        self.state.write_text("not a record\n")
        result = self.record(0)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(self.state.read_text(), "not a record\n")
        self.write_interrupted()
        result = self.record(0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read_state()["outcome"], "success")

    def test_a_running_wrapper_keeps_ownership_of_the_record(self):
        original = self.write_interrupted()
        result = self.record(0, script=self.RECORD_UNDER_WRAPPER_LOCK)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(self.state.read_bytes(), original)
        result = self.record(0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read_state()["outcome"], "success")

    def test_update_main_records_a_full_noninteractive_run(self):
        self.write_interrupted()
        result = self.run_update_main("--yes", "--quiet")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        success = self.read_state()
        self.assertEqual(success["outcome"], "success")
        logs = "".join(log.read_text() for log in (self.acfs / "logs/updates").glob("*.log"))
        self.assertIn("Recorded this update (exit 0) in the nightly execution record", logs)
        # main records with the real clock.
        self.assertEqual(self.health(now=int(time.time()) + 60), ("pass", "success"))

        result = self.run_update_main("--yes", "--quiet", "--no-self-update",
                                      successes=3, failures=1)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        state = self.read_state()
        self.assertEqual((state["outcome"], state["reason"]), ("failed", "update"))
        self.assertEqual(state["last_success"], success["last_success"])

    def test_update_main_records_only_full_noninteractive_runs(self):
        original = self.write_interrupted()
        for args in (("--quiet",), ("--yes", "--quiet", "--agents-only"),
                     ("--yes", "--quiet", "--no-apt"), ("--yes", "--quiet", "--dry-run")):
            with self.subTest(args=args):
                result = self.run_update_main(*args)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.state.read_bytes(), original)
        result = self.run_update_main("--yes", "--quiet")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.read_state()["outcome"], "success")

    def test_update_main_never_creates_a_record(self):
        result = self.run_update_main("--yes", "--quiet")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.state.exists())
        self.write_interrupted()
        result = self.run_update_main("--yes", "--quiet")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.read_state()["outcome"], "success")

    def test_update_main_records_early_failures_and_stops_watchdog(self):
        cases = (("update_ensure_writable_tmpdir", 41), ("update_acfs_self", 42),
                 ("init_logging", 43), ("update_shell", 44))
        expected = []
        for step, rc in cases:
            with self.subTest(step=step):
                now = int(time.time())
                self.write("success", "none", now - 65, now - 60, 0, "-", 0, 1, 0)
                previous = self.read_state()
                result = self.run_update_main(
                    "--yes", "--quiet", overrides=UPDATE_FINALIZATION_AUDIT +
                    f"\n{step}() {{ return {rc}; }}\n")
                self.assertEqual(result.returncode, rc, result.stdout + result.stderr)
                self.assert_failure_recorded(previous)
                expected.append(str(rc))
                self.assertEqual((self.home / "recorded-outcomes").read_text().splitlines(), expected)
                self.assertEqual((self.home / "watchdog-stops").read_text().splitlines(),
                                 ["stopped"] * len(expected))

    def test_update_main_abort_on_failure_records_failed_attempt(self):
        self.write_interrupted()
        previous = self.read_state()
        result = self.run_update_main(
            "--yes", "--quiet", "--abort-on-failure",
            overrides=UPDATE_FINALIZATION_AUDIT + r'''
update_apt() { update_finish_cmd_fail "fixture component" "controlled failure"; }
''')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Aborting due to failure", result.stdout)
        self.assert_failure_recorded(previous)
        self.assertEqual((self.home / "recorded-outcomes").read_text(), "1\n")
        self.assertEqual((self.home / "watchdog-stops").read_text(), "stopped\n")

    def test_update_main_records_failed_runtime_publication(self):
        self.write_interrupted()
        previous = self.read_state()
        source = self.home / "new-wrapper"
        target = self.home / "old-wrapper"
        source.write_text("#!/bin/bash\nprintf 'new wrapper\\n'\n")
        target.write_text("#!/bin/bash\nprintf 'old wrapper\\n'\n")
        target.chmod(0o755)
        original = (target.read_bytes(), target.stat().st_ino, target.stat().st_mode)
        result = self.run_update_main("--yes", "--quiet", overrides=UPDATE_FINALIZATION_AUDIT + r'''
cp() { printf 'partial copy\n' > "${@: -1}"; return 73; }
update_shell() { update_atomic_deploy_file "$HOME/new-wrapper" "$HOME/old-wrapper" 755; }
''')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual((target.read_bytes(), target.stat().st_ino, target.stat().st_mode), original)
        self.assertEqual(list(self.home.glob(".acfs-deploy.*")), [])
        self.assert_failure_recorded(previous)
        self.assertEqual((self.home / "recorded-outcomes").read_text(), "1\n")

    def test_update_main_finalizes_once_for_complete_outcomes(self):
        for index, (successes, failures, rc) in enumerate(((5, 0, 0), (3, 1, 2), (0, 1, 1)), 1):
            with self.subTest(rc=rc):
                self.write_interrupted()
                previous = self.read_state()
                result = self.run_update_main(
                    "--yes", "--quiet", successes=successes, failures=failures,
                    overrides=UPDATE_FINALIZATION_AUDIT)
                self.assertEqual(result.returncode, rc, result.stdout + result.stderr)
                if rc:
                    self.assert_failure_recorded(previous)
                else:
                    self.assertEqual(self.read_state()["outcome"], "success")
                    self.assertEqual(self.health(now=int(time.time()) + 60), ("pass", "success"))
                self.assertEqual((self.home / "recorded-outcomes").read_text().splitlines(),
                                 ["0", "2", "1"][:index])
                self.assertEqual((self.home / "watchdog-stops").read_text().splitlines(),
                                 ["stopped"] * index)

    def test_update_main_finalization_failures_preserve_original_status(self):
        self.write_interrupted()
        previous = self.read_state()
        result = self.run_update_main("--yes", "--quiet", overrides=UPDATE_FINALIZATION_AUDIT + r'''
update_acfs_self() { return 42; }
update_procwatch_stop() { printf 'stopped\n' >> "$HOME/watchdog-stops"; return 71; }
''')
        self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
        self.assert_failure_recorded(previous)
        self.assertEqual((self.home / "recorded-outcomes").read_text(), "42\n")

        original = self.write_interrupted()
        result = self.run_update_main("--yes", "--quiet", overrides=UPDATE_FINALIZATION_AUDIT + r'''
update_acfs_self() { return 43; }
update_record_nightly_outcome() {
    printf '%s\n' "$1" >> "$HOME/recorded-outcomes"
    return 72
}
''')
        self.assertEqual(result.returncode, 43, result.stdout + result.stderr)
        self.assertEqual(self.state.read_bytes(), original)
        self.assertEqual((self.home / "recorded-outcomes").read_text(), "42\n43\n")
        self.assertEqual((self.home / "watchdog-stops").read_text().splitlines(),
                         ["stopped", "stopped"])

    def test_update_main_early_failures_respect_record_filters(self):
        original = self.write_interrupted()
        for args in (("--quiet",), ("--yes", "--quiet", "--dry-run"),
                     ("--yes", "--quiet", "--shell-only"), ("--yes", "--quiet", "--no-apt")):
            with self.subTest(args=args):
                result = self.run_update_main(*args, overrides=UPDATE_FINALIZATION_AUDIT +
                                              "\nupdate_acfs_self() { return 42; }\n")
                self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
                self.assertEqual(self.state.read_bytes(), original)

    def test_update_main_does_not_record_help_or_argument_errors(self):
        original = self.write_interrupted()
        for args, rc in ((("--yes", "--help"), 0), (("--yes", "--invalid-fixture-option"), 1)):
            with self.subTest(args=args):
                result = self.run_update_main(*args, overrides=UPDATE_FINALIZATION_AUDIT)
                self.assertEqual(result.returncode, rc, result.stdout + result.stderr)
                self.assertEqual(self.state.read_bytes(), original)
                self.assertFalse((self.home / "recorded-outcomes").exists())
                self.assertFalse((self.home / "watchdog-stops").exists())

    def test_update_main_early_failure_defers_to_running_wrapper(self):
        original = self.write_interrupted()
        result = self.run_update_main("--yes", "--quiet", overrides=UPDATE_FINALIZATION_AUDIT + r'''
exec 8>>"$HOME/.acfs/nightly-update.lock"
flock -n 8
update_acfs_self() { return 42; }
''')
        self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
        self.assertEqual(self.state.read_bytes(), original)
        self.assertEqual((self.home / "recorded-outcomes").read_text(), "42\n")
        self.assertEqual((self.home / "watchdog-stops").read_text(), "stopped\n")

    def test_update_main_reexec_records_only_replacement_run(self):
        original = self.write_interrupted().decode().rstrip("\n")
        result = self.run_update_main(
            "--yes", "--quiet", overrides=UPDATE_FINALIZATION_AUDIT + r'''
update_acfs_self() {
    if [[ "${FIXTURE_REEXEC:-false}" != true ]]; then
        export FIXTURE_REEXEC=true
        exec bash -c 'source "$1"; eval "$STUBS"; shift; main "$@"' \
            test "$FIXTURE_UPDATE_SOURCE" "$@"
    fi
    [[ "$(< "$HOME/.acfs/nightly-update.state")" == "$FIXTURE_INITIAL_STATE" ]]
}
''', extra_env={"FIXTURE_UPDATE_SOURCE": str(UPDATE), "FIXTURE_INITIAL_STATE": original})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.read_state()["outcome"], "success")
        self.assertEqual((self.home / "recorded-outcomes").read_text(), "0\n")
        self.assertEqual((self.home / "watchdog-stops").read_text(), "stopped\n")

    def test_update_main_signals_record_failure_and_preserve_status(self):
        expected = []
        for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=sig):
                self.write_interrupted()
                previous = self.read_state()
                stubs = UPDATE_MAIN_STUBS + UPDATE_FINALIZATION_AUDIT + r'''
update_shell() { printf 'fixture-ready\n'; IFS= read -r _fixture_release; }
'''
                with subprocess.Popen(
                    ["bash", "-c", 'source "$1"; eval "$STUBS"; shift; main "$@"',
                     "test", str(UPDATE), "--yes", "--quiet"],
                    env={**self.env, "STUBS": stubs, "FIXTURE_SUCCESSES": "5", "FIXTURE_FAILURES": "0"},
                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    start_new_session=True,
                ) as process:
                    try:
                        output = b""
                        deadline = time.monotonic() + 10
                        while b"fixture-ready\n" not in output:
                            remaining = deadline - time.monotonic()
                            self.assertGreater(remaining, 0, output)
                            ready, _, _ = select.select([process.stdout], [], [], remaining)
                            self.assertTrue(ready, output)
                            chunk = os.read(process.stdout.fileno(), 4096)
                            self.assertTrue(chunk, output)
                            output += chunk
                        os.kill(process.pid, sig)
                        process.wait(timeout=10)
                        stdout, stderr = process.communicate(timeout=10)
                        self.assertEqual(process.returncode, 128 + sig, output + stdout + stderr)
                    finally:
                        if process.poll() is None:
                            os.killpg(process.pid, signal.SIGKILL)
                            process.communicate(timeout=10)
                self.assert_failure_recorded(previous)
                expected.append(str(128 + sig))
                self.assertEqual((self.home / "recorded-outcomes").read_text().splitlines(), expected)
                self.assertEqual((self.home / "watchdog-stops").read_text().splitlines(),
                                 ["stopped"] * len(expected))


if __name__ == "__main__":
    unittest.main()
