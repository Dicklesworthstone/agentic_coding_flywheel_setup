#!/usr/bin/env python3
"""Read-only nightly health regressions. Run directly with Python 3.

The status command is sourced intact; unrelated host/tool discovery is controlled.
No updater, package operation, real sleep, systemd mutation or network is run.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest import mock

import test_nightly_update as writer_fixture

ROOT = Path(__file__).resolve().parents[2]
WRAPPER = ROOT / "scripts/lib/nightly_update.sh"
STATUS = ROOT / "scripts/lib/status.sh"


class Fixture(unittest.TestCase):
    def setUp(self):
        # Retain fixture evidence. No cleanup touches an existing installation.
        self.home = Path(tempfile.mkdtemp(prefix="acfs-nightly-health-"))
        self.acfs = self.home / ".acfs"
        self.acfs.mkdir()
        self.state = self.acfs / "nightly-update.state"
        self.now = int(time.time())
        self.env = {"PATH": "/usr/bin:/bin", "HOME": str(self.home), "LC_ALL": "C",
                    "TZ": "UTC", "HEALTH_TEST_HOME": str(self.home)}

    def bash(self, source, *args, **env):
        return subprocess.run(["bash", "-c", source, "test", *map(str, args)],
                              env={**self.env, **env}, text=True, capture_output=True, timeout=8)

    def write(self, outcome="success", reason=None, skips=0, age=60, success_age=5,
              retry=None, **fields):
        reason = reason or {"success": "none", "running": "none", "skipped": "load",
                            "retrying": "load", "failed": "update", "interrupted": "interrupted"}[outcome]
        data = {"version": 1, "outcome": outcome, "reason": reason,
                "attempt_ts": self.now - age,
                "success_ts": 0 if success_age is None else self.now - success_age,
                "first_skip": self.now - 4 * 86400 if skips else 0,
                "skip_date": "2026-10-12" if skips else "-", "skips": skips,
                "attempt": 2 if outcome == "retrying" else 1,
                "retry": self.now + 600 if outcome == "retrying" and retry is None else retry or 0}
        data.update(fields)
        self.state.write_text("\t".join(map(str, data.values())) + "\n")
        return self.state.read_bytes()

    def report(self, now=None, path=None):
        result = self.bash('set -euo pipefail; source "$1"; acfs_nightly_health_report "$2" "$3"',
                           WRAPPER, path or self.state, self.now if now is None else now)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        level, message, encoded = result.stdout.rstrip("\n").split("\t")
        value = json.loads(encoded)
        self.assertEqual(value["health"], level)
        return level, message, value


class NightlyHealthTests(Fixture):
    def test_no_record_is_unknown_not_a_success_and_creates_nothing(self):
        before = sorted(self.home.rglob("*"))
        level, _, result = self.report()
        self.assertEqual((level, result["code"], result["state"]), ("skip", "not_recorded", None))
        self.assertEqual(sorted(self.home.rglob("*")), before)

    def test_recent_success_is_a_record_not_an_upstream_version_claim(self):
        original = self.write()
        level, message, result = self.report()
        self.assertEqual((level, result["code"]), ("pass", "success"))
        self.assertIn("recorded", message)
        self.assertIsNone(result["state"]["next_retry_epoch"])
        self.assertEqual(result["state"]["last_success_epoch"], self.now - 5)
        self.assertEqual(self.state.read_bytes(), original)

    def test_missed_nights_are_visible_for_each_blocking_resource(self):
        for reason in ("load", "disk", "metrics"):
            with self.subTest(reason=reason):
                original = self.write("skipped", reason=reason, skips=4, success_age=None)
                level, message, result = self.report()
                self.assertEqual((level, result["code"]), ("warn", "skipped"))
                self.assertIn("4 skipped night(s) since last full success", message)
                self.assertEqual(result["state"]["reason"], reason)
                self.assertIsNone(result["state"]["last_success_epoch"])
                self.assertEqual(self.state.read_bytes(), original)

    def test_retry_due_and_overdue_are_distinct_at_the_exact_boundary(self):
        self.write("retrying", skips=2, retry=self.now - 300, age=900)
        self.assertEqual(self.report()[2]["code"], "retrying")
        self.assertEqual(self.report(now=self.now + 1)[2]["code"], "retry_overdue")
        self.assertEqual(self.report()[2]["state"]["skipped_nights"], 2)

    def test_in_progress_does_not_erase_skips_or_claim_liveness(self):
        self.write("running", skips=3, age=7500, success_age=5 * 86400)
        level, message, result = self.report()
        self.assertEqual((level, result["code"]), ("warn", "running"))
        self.assertIn("3 skipped", message)
        self.assertEqual(self.report(now=self.now + 1)[2]["code"], "run_overdue")

    def test_partial_total_and_interrupted_failures_keep_the_previous_success(self):
        for outcome in ("failed", "interrupted"):
            with self.subTest(outcome=outcome):
                self.write(outcome, skips=4, success_age=7 * 86400)
                level, message, result = self.report()
                self.assertEqual((level, result["code"]), ("warn", outcome))
                self.assertIn("4 skipped", message)
                self.assertEqual(result["state"]["last_success_epoch"], self.now - 7 * 86400)

    def test_old_success_warning_boundary(self):
        self.write(age=259260, success_age=259200)
        self.assertEqual(self.report()[0], "pass")
        self.assertEqual(self.report(now=self.now + 1)[2]["code"], "stale_success")

    def test_clock_failures_do_not_make_success_fresh(self):
        self.write()
        for now in ("NaN", "0", "01", "-1", "999999999999999999999"):
            with self.subTest(now=now):
                self.assertEqual(self.report(now=now)[2]["code"], "clock_unavailable")
        self.write(success_ts=self.now + 301)
        self.assertEqual(self.report()[2]["code"], "clock_skew")

    def test_nul_suffix_cannot_hide_a_second_record(self):
        valid = self.write()
        for content in (valid + b"\0hidden", valid + b"\0", b"\0" + valid,
                        valid + valid, valid.rstrip(b"\n"), b"x" * 1024):
            with self.subTest(content=repr(content)[:60]):
                self.state.write_bytes(content)
                level, _, result = self.report()
                self.assertEqual((level, result["code"], result["state"]), ("warn", "invalid_state", None))
                self.assertEqual(self.state.read_bytes(), content)

    def test_rejects_raw_code_and_unknown_enums_without_echoing_or_executing(self):
        marker = self.home / "EXECUTED"
        for content in (f"$(touch {marker})\n", 'source /private/API_KEY\n',
                        '1\tsecret\tunknown\n', "1\tsuccess\tnone\t\t0\t0\t-\t0\t1\t0\n"):
            self.state.write_text(content)
            level, message, result = self.report()
            self.assertEqual((level, result["code"]), ("warn", "invalid_state"))
            self.assertNotIn("API_KEY", message)
            self.assertNotIn(str(marker), message)
            self.assertFalse(marker.exists())

    def test_special_and_symlinked_records_are_not_followed(self):
        valid = self.write()
        for name, kind in (("fifo", "fifo"), ("linked", "link"), ("dangling", "dangling"), ("directory", "dir")):
            path = self.home / name
            if kind == "fifo": os.mkfifo(path)
            elif kind == "link": path.symlink_to(self.state)
            elif kind == "dangling": path.symlink_to(self.home / "missing")
            else: path.mkdir()
            self.assertEqual(self.report(path=path)[2]["code"], "invalid_state")
        self.assertEqual(self.state.read_bytes(), valid)

    def test_same_shell_reads_do_not_leak_globals_or_change_options(self):
        self.write("skipped", skips=4)
        result = self.bash('set -euo pipefail; source "$1"; before=$-; old_home=$HOME; '
                           'ACFS_NIGHTLY_OUTCOME=sentinel; acfs_nightly_health_report "$2" "$3" >/dev/null; '
                           '[[ "$before" == "$-" && "$old_home" == "$HOME" && "$ACFS_NIGHTLY_OUTCOME" == sentinel ]]',
                           WRAPPER, self.state, self.now)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_existing_skip_count_is_not_cleared_by_observing_the_report(self):
        original = self.write("skipped", skips=4)
        for _ in range(3): self.report()
        self.assertEqual(self.state.read_bytes(), original)
        self.write()
        self.assertEqual(self.report()[0], "pass")


STATUS_SETUP = r'''
source "$1"
_status_prepare_context() { _ACFS_HOME="$HEALTH_TEST_HOME/.acfs"; }
_status_resolve_state_file() { printf '%s\n' "$HEALTH_TEST_HOME/.acfs/state.json"; }
_status_binary_exists() { return 0; }
_status_read_last_update_ts() { return 0; }
_status_read_last_completed_update_ts() { return 0; }
if [[ -n "${HEALTH_HELPER_DIR:-}" ]]; then _STATUS_SCRIPT_DIR="$HEALTH_HELPER_DIR"; fi
shift
status_main "$@"
'''


class StatusNightlyTests(Fixture):
    def setUp(self):
        super().setUp()
        (self.acfs / "state.json").write_text('{"schema_version":3}')

    def status(self, *args, **env):
        return self.bash(STATUS_SETUP, STATUS, *args, **env)

    def test_json_has_execution_health_and_missed_nights_without_network_flag(self):
        original = self.write("skipped", skips=4)
        result = self.status("--json")
        self.assertEqual(result.returncode, 1, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(value["status"], "warn")
        self.assertEqual(value["nightly_update"]["state"]["skipped_nights"], 4)
        self.assertIn("4 skipped", " ".join(value["warnings"]))
        self.assertEqual(self.state.read_bytes(), original)

    def test_short_and_human_outputs_warn_without_hiding_reason(self):
        self.write("skipped", skips=2, reason="disk")
        short = self.status("--short")
        self.assertEqual((short.returncode, short.stdout.strip()), (1, "WARN"))
        human = self.status()
        self.assertEqual(human.returncode, 1, human.stderr)
        self.assertIn("2 skipped", human.stdout)
        self.assertIn("disk", human.stdout)

    def test_success_and_absence_are_distinct_without_new_warnings(self):
        absent = self.status("--json")
        self.assertEqual(absent.returncode, 0, absent.stderr)
        self.assertEqual(json.loads(absent.stdout)["nightly_update"]["code"], "not_recorded")
        self.write()
        success = self.status("--json")
        self.assertEqual(success.returncode, 0, success.stderr)
        self.assertEqual(json.loads(success.stdout)["nightly_update"]["code"], "success")

    def test_failures_and_invalid_state_warn(self):
        for outcome in ("failed", "interrupted", "running"):
            self.write(outcome)
            result = self.status("--json")
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertEqual(json.loads(result.stdout)["nightly_update"]["code"], outcome)
        self.state.write_text("private state broken\n")
        result = self.status("--json")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertNotIn("private state broken", result.stdout)
        self.assertEqual(json.loads(result.stdout)["nightly_update"]["code"], "invalid_state")

    def test_existing_errors_still_take_priority_over_nightly_warning(self):
        self.write("skipped", skips=4)
        (self.acfs / "state.json").write_text("{broken")
        result = self.status("--json")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "error")

    def test_old_unguarded_wrapper_is_never_sourced(self):
        self.write("skipped", skips=4)
        library = self.home / "runtime/lib"
        library.mkdir(parents=True)
        marker = self.home / "UPDATER_RAN"
        (library / "nightly_update.sh").write_text(f'#!/bin/bash\ntouch "{marker}"\n')
        result = self.status("--json", HEALTH_HELPER_DIR=str(library))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(json.loads(result.stdout)["nightly_update"]["code"], "reader_unavailable")
        self.assertFalse(marker.exists())

    def test_deployed_hyphenated_wrapper_fallback(self):
        self.write("skipped", skips=2)
        library = self.home / "runtime/lib"
        library.mkdir(parents=True)
        (library.parent / "nightly-update.sh").write_bytes(WRAPPER.read_bytes())
        result = self.status("--json", HEALTH_HELPER_DIR=str(library))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(json.loads(result.stdout)["nightly_update"]["state"]["skipped_nights"], 2)

    def test_sourced_repeated_calls_do_not_retain_a_previous_warning(self):
        self.write("skipped", skips=4)
        setup = STATUS_SETUP.rsplit('status_main "$@"', 1)[0]
        code = setup + r'''
status_main --short || true
printf '1\tsuccess\tnone\t%s\t%s\t0\t-\t0\t1\t0\n' "$(date +%s)" "$(date +%s)" > "$HEALTH_TEST_HOME/.acfs/nightly-update.state"
status_main --short
'''
        result = self.bash(code, STATUS)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["WARN", "OK"])

    def test_editor_contract_inherits_nightly_warning_without_running_live_probes(self):
        (self.acfs / "state.json").write_text(
            '{"schema_version":3,"mode":"vibe","completed_phases":["finalize"]}')
        self.write("skipped", skips=4)
        result = self.status("--ide")
        self.assertEqual(result.returncode, 1, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(value["status"], "warn")
        self.assertEqual(value["collectors"]["sessions"], "not_requested")
        self.assertFalse(value["execute_automatically"])
        self.write()
        result = self.status("--ide")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "ok")

    def test_status_json_reports_nightly_failures_without_jq(self):
        self.write("failed", skips=3)
        setup = STATUS_SETUP.rsplit('status_main "$@"', 1)[0]
        code = setup + r'''
_status_system_binary_path() {
    [[ "$1" != jq ]] || return 1
    printf '/usr/bin/%s\n' "$1"
}
status_main --json
'''
        result = self.bash(code, STATUS)
        self.assertEqual(result.returncode, 1, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(value["nightly_update"]["code"], "failed")
        self.assertEqual(value["nightly_update"]["state"]["skipped_nights"], 3)

    def test_real_writer_to_status_preserves_skips_until_full_success(self):
        class RetainedDirectory:
            def __init__(self, **kwargs):
                self.name = tempfile.mkdtemp(**kwargs)

            def cleanup(self):
                pass

        # Reuse the existing writer's host-safe fixture. Only its disposable
        # directory cleanup is replaced; runtime, writer and parser are real.
        with mock.patch.object(writer_fixture.tempfile, "TemporaryDirectory", RetainedDirectory):
            writer = writer_fixture.NightlyUpdateTests()
            writer.setUp()
        self.addCleanup(writer.doCleanups)
        self.home, self.acfs, self.state = writer.home, writer.acfs, writer.state
        self.env.update(HOME=str(self.home), HEALTH_TEST_HOME=str(self.home))
        (self.acfs / "state.json").write_text('{"schema_version":3}')
        for day in range(4):
            writer.set_clock(self.now - (4 - day) * 86400)
            writer.metrics(load=("19.1",))
            writer.run_wrapper()
            original = self.state.read_bytes()
            result = self.status("--json")
            self.assertEqual(result.returncode, 1, result.stderr)
            value = json.loads(result.stdout)["nightly_update"]
            self.assertEqual(value["code"], "skipped")
            self.assertEqual(value["state"]["skipped_nights"], day + 1)
            self.assertEqual(self.state.read_bytes(), original)
            writer.assert_no_update()

        writer.set_clock(self.now)
        writer.metrics()
        writer.run_wrapper(rc=2, FIXTURE_UPDATE_RC="2")
        failed = json.loads(self.status("--json").stdout)["nightly_update"]
        self.assertEqual(failed["code"], "failed")
        self.assertEqual(failed["state"]["skipped_nights"], 4)
        self.assertIsNone(failed["state"]["last_success_epoch"])

        writer.metrics()
        writer.run_wrapper(ACFS_NIGHTLY_MAX_RETRIES="0")
        result = self.status("--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(result.stdout)["nightly_update"]
        self.assertEqual(value["code"], "success")
        self.assertEqual(value["state"]["skipped_nights"], 0)
        self.assertEqual(value["state"]["last_success_epoch"], self.now)
        self.assertEqual((self.home / "updates").read_text().splitlines(),
                         ["--yes --quiet --no-self-update"] * 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
