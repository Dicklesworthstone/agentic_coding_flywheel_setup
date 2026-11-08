"""Exercise real updater/verification functions with inert downloaded scripts.

Network acquisition and installed-tool discovery are fixtures. Pin-classification
tests stub binary snapshots; rollback tests use real snapshots and filesystem
restoration. SHA256 verification, metadata recovery, shell execution, background
status propagation, retry dispatch and final summaries run the repository code.
No system packages, real agent installations or external services are touched.
"""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]

COMMON = r'''
source "$UPDATE_TEST_LIBRARY"
source "$REPO_ROOT/scripts/lib/security.sh"
DRY_RUN=false
FORCE_MODE=false
VERBOSE="${TEST_VERBOSE:-false}"
QUIET="${TEST_QUIET:-true}"
ABORT_ON_FAILURE=false
UPDATE_LOG_FILE="$TEST_ROOT/update.log"
RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' NC=''
SUCCESS_COUNT=0 SKIP_COUNT=0 FAIL_COUNT=0
UPDATE_SECURITY_READY=true
ACFS_UPDATE_RETRY_SLEEP_SECONDS=0
ACFS_UPDATE_RETRY_MAX_ATTEMPTS=3
PIN="$TEST_PIN"
KNOWN_INSTALLERS[claude]="https://fixture.invalid/TLS/installer.sh"
update_require_security() { return 0; }
get_checksum() { printf '%s\n' "$PIN"; }
update_tool_hold_details() { return 1; }
update_tool_rollback_backoff_details() { return 1; }
update_is_linux_arm64() { return 1; }
update_snapshot_tool_binary() { printf 'snapshot\n' >> "$TEST_ROOT/events"; }
update_verify_tool_or_rollback() { printf 'smoke\n' >> "$TEST_ROOT/events"; }
update_create_target_readable_temp_file() { mktemp "$TEST_ROOT/stage.XXXXXX"; }
update_run_in_target_context() { shift; "$@"; }
# Preserve temporary fixture files for inspection after each run.
rm() { :; }
acfs_download_to_file() {
    printf 'download\n' >> "$TEST_ROOT/events"
    if [[ "${TEST_NETWORK_FAIL:-false}" == true ]]; then
        printf 'curl: (7) Connection refused\n' >&2
        return 7
    fi
    if [[ "$1" == *'/new.sh' ]]; then
        cat "$TEST_ROOT/new-installer.sh" > "$2"
    else
        cat "$TEST_ROOT/installer.sh" > "$2"
    fi
}
acfs_refresh_loaded_checksums_from_remote() {
    printf 'refresh\n' >> "$TEST_ROOT/events"
    case "${TEST_REFRESH:-same}" in
        same) return 0 ;;
        fail) return 1 ;;
        accept) PIN="$TEST_ACTUAL" ;;
        new-url) PIN="$TEST_NEW_ACTUAL"; KNOWN_INSTALLERS[claude]="https://fixture.invalid/new.sh" ;;
        wrong-new-pin) PIN=$(printf '%064d' 2) ;;
    esac
}
result() {
    printf 'COUNTS=%s,%s,%s,%s\n' "$SUCCESS_COUNT" "$SKIP_COUNT" "$FAIL_COUNT" "${#UPDATE_PIN_FAILURES[@]}"
}
'''


class PinFailureTests(unittest.TestCase):
    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="acfs-pin-test-"))
        self.script = b'#!/bin/bash\nprintf "execute\\n" >> "$TEST_ROOT/events"\nexit "${TEST_INSTALLER_EXIT:-0}"\n'
        self.new_script = self.script + b'# refreshed entrypoint\n'
        (self.base / "installer.sh").write_bytes(self.script)
        (self.base / "new-installer.sh").write_bytes(self.new_script)
        self.actual = hashlib.sha256(self.script).hexdigest()
        self.env = {
            "PATH": "/usr/bin:/bin", "HOME": str(self.base),
            "TARGET_HOME": str(self.base), "TEST_ROOT": str(self.base),
            "REPO_ROOT": str(ROOT), "TMPDIR": str(self.base),
            "UPDATE_TEST_LIBRARY": os.environ.get("ACFS_UPDATE_TEST_LIBRARY", str(ROOT / "scripts/lib/update.sh")),
            "NO_COLOR": "1", "ACFS_INTERACTIVE": "false",
            "TEST_ACTUAL": self.actual, "TEST_PIN": "1" * 64,
            "TEST_NEW_ACTUAL": hashlib.sha256(self.new_script).hexdigest(),
        }

    def shell(self, body, *, code=0, **env):
        result = subprocess.run(["/bin/bash", "--noprofile", "--norc", "-c", COMMON + body],
                                env=self.env | env, text=True, capture_output=True, timeout=25)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def events(self):
        path = self.base / "events"
        return path.read_text().splitlines() if path.exists() else []

    def test_valid_pin_returns_exact_downloaded_bytes(self):
        self.shell('verify_checksum "${KNOWN_INSTALLERS[claude]}" "$PIN" claude > "$TEST_ROOT/verified"',
                   TEST_PIN=self.actual)
        self.assertEqual((self.base / "verified").read_bytes(), self.script)
        self.assertEqual(self.events(), ["download"])

    def test_identical_refreshed_pin_is_not_downloaded_twice(self):
        output = self.shell('rc=0; verify_checksum "${KNOWN_INSTALLERS[claude]}" "$PIN" claude > "$TEST_ROOT/verified" || rc=$?; '
                            'printf "RC=%s REASON=%s\\n" "$rc" "$ACFS_LAST_MODULE_FAILURE_REASON"')
        self.assertIn("RC=1 REASON=checksum", output)
        self.assertEqual(self.events(), ["download", "refresh"])
        self.assertEqual((self.base / "verified").read_bytes(), b"")

    def test_new_pin_can_accept_original_bytes_without_a_second_download(self):
        self.shell('verify_checksum "${KNOWN_INSTALLERS[claude]}" "$PIN" claude > "$TEST_ROOT/verified"',
                   TEST_REFRESH="accept")
        self.assertEqual(self.events(), ["download", "refresh"])
        self.assertEqual((self.base / "verified").read_bytes(), self.script)

    def test_changed_url_uses_new_contract_and_verifies_exact_bytes(self):
        self.shell('verify_checksum "${KNOWN_INSTALLERS[claude]}" "$PIN" claude > "$TEST_ROOT/verified"',
                   TEST_REFRESH="new-url")
        self.assertEqual(self.events(), ["download", "refresh", "download"])
        self.assertEqual((self.base / "verified").read_bytes(), self.new_script)

    def test_changed_but_still_wrong_pin_remains_fail_closed(self):
        self.shell('verify_checksum "${KNOWN_INSTALLERS[claude]}" "$PIN" claude > "$TEST_ROOT/verified"',
                   code=1, TEST_REFRESH="wrong-new-pin")
        self.assertEqual(self.events(), ["download", "refresh", "download"])
        self.assertEqual((self.base / "verified").read_bytes(), b"")

    def test_failed_metadata_refresh_never_executes_or_retries(self):
        self.shell('update_run_verified_installer claude latest', code=95, TEST_REFRESH="fail")
        self.assertEqual(self.events(), ["download", "refresh"])

    def test_missing_and_invalid_pins_fail_before_download_or_snapshot(self):
        for pin in ("", "not-a-hash", "0" * 63, "f" * 65, " "+self.actual):
            with self.subTest(pin=pin):
                output = self.shell('update_run_verified_installer claude latest', code=95, TEST_PIN=pin)
                self.assertIn("checksums.yaml", output)
        self.assertEqual(self.events(), [])

    def test_verified_script_executes_then_runs_smoke_check(self):
        self.shell('update_run_verified_installer claude latest', TEST_PIN=self.actual)
        self.assertEqual(self.events(), ["download", "snapshot", "execute", "smoke"])

    def test_installer_exit_95_cannot_impersonate_a_pin_refusal(self):
        self.shell('update_run_verified_installer claude latest', code=1,
                   TEST_PIN=self.actual, TEST_INSTALLER_EXIT="95")
        self.assertEqual(self.events(), ["download", "snapshot", "execute"])

    def test_prior_checksum_reason_cannot_classify_a_network_failure(self):
        output = self.shell('ACFS_LAST_MODULE_FAILURE_REASON=checksum; rc=0; '
                            'update_run_verified_installer claude latest || rc=$?; '
                            'printf "RC=%s REASON=%s\\n" "$rc" "$ACFS_LAST_MODULE_FAILURE_REASON"',
                            TEST_NETWORK_FAIL="true")
        self.assertIn("RC=1 REASON=network", output)
        self.assertEqual(self.events(), ["download"])

    def test_run_cmd_tracks_pin_failure_across_console_and_pipeline_modes(self):
        for quiet, verbose in (("true", "true"), ("false", "true"), ("true", "false"), ("false", "false")):
            with self.subTest(quiet=quiet, verbose=verbose):
                output = self.shell('run_cmd "fixture tool" update_run_verified_installer claude latest; result; print_summary',
                                    TEST_QUIET=quiet, TEST_VERBOSE=verbose)
                self.assertIn("COUNTS=0,0,1,1", output)
                self.assertIn("CHECKSUM BLOCKED: 1 update(s)", output)
                self.assertNotIn("All updates completed successfully!", output)
        self.assertEqual(self.events().count("download"), 4)
        self.assertNotIn("snapshot", self.events())

    def test_unrelated_exit_95_is_an_ordinary_failure(self):
        output = self.shell('run_cmd "ordinary command" /bin/bash -c "exit 95"; result; print_summary')
        self.assertIn("COUNTS=0,0,1,0", output)
        self.assertNotIn("CHECKSUM BLOCKED", output)

    def test_capture_retry_does_not_treat_pin_url_as_transient(self):
        self.shell('update_run_command_capture_with_retry "fixture" update_run_verified_installer claude latest', code=95)
        self.assertEqual(self.events(), ["download", "refresh"])

    def test_capture_retry_still_recovers_real_transient_network_failure(self):
        output = self.shell(r'''
            failures=0
            acfs_download_to_file() {
                printf 'download\n' >> "$TEST_ROOT/events"
                failures=$((failures + 1))
                if [[ $failures -lt 3 ]]; then printf 'curl: (7) Connection refused\n' >&2; return 7; fi
                cat "$TEST_ROOT/installer.sh" > "$2"
            }
            update_run_command_capture_with_retry "fixture" update_run_verified_installer claude latest
        ''', TEST_PIN=self.actual)
        self.assertEqual(self.events(), ["download", "download", "download", "snapshot", "execute", "smoke"])

    def test_existing_binary_does_not_turn_pin_refusal_into_a_skip(self):
        output = self.shell(r'''
            update_binary_path() { printf '%s\n' /bin/true; }
            get_version() { printf '1.0.0\n'; }
            rc=0
            update_run_verified_installer_or_existing_on_transient fixture claude claude claude latest || rc=$?
            printf 'RC=%s\n' "$rc"
            result
        ''')
        self.assertIn("RC=95", output)
        self.assertIn("COUNTS=0,0,1,1", output)
        self.assertEqual(self.events(), ["download", "refresh"])

    def test_target_tmpdir_wrapper_preserves_pin_classification(self):
        output = self.shell(r'''
            update_prepare_target_installer_tmpdir() { printf '%s\n' "$TEST_ROOT"; }
            update_binary_path() { printf '%s\n' /bin/true; }
            get_version() { printf '1.0.0\n'; }
            rc=0
            update_run_verified_installer_with_target_tmpdir_or_existing_on_transient fixture claude claude claude latest || rc=$?
            printf 'RC=%s\n' "$rc"
            result
        ''')
        self.assertIn("RC=95", output)
        self.assertIn("COUNTS=0,0,1,1", output)
        self.assertEqual(self.events(), ["download", "refresh"])

    def agent_body(self):
        return r'''
            UPDATE_AGENTS=true
            update_binary_path() { [[ "$1" == claude ]] && printf '%s\n' /bin/true; }
            update_binary_exists() { return 1; }
            capture_version_before() { return 0; }
            capture_version_after() { return 1; }
            update_install_agy_locked_launchers() { return 0; }
            update_agents
            printf 'FAILURES=%s PINS=%s\n' "$FAIL_COUNT" "${#UPDATE_PIN_FAILURES[@]}"
            print_summary
        '''

    def test_real_claude_update_path_never_reinstalls_a_refused_pin(self):
        for quiet, verbose in (("true", "false"), ("false", "false"), ("true", "true"), ("false", "true")):
            with self.subTest(quiet=quiet, verbose=verbose):
                output = self.shell(self.agent_body(), TEST_QUIET=quiet, TEST_VERBOSE=verbose)
                self.assertIn("FAILURES=1 PINS=1", output)
                self.assertIn("CHECKSUM BLOCKED", output)
                self.assertNotIn("Claude Code (reinstall)", output)
        self.assertEqual(self.events().count("download"), 4)
        self.assertEqual(self.events().count("refresh"), 4)
        self.assertNotIn("execute", self.events())

    def test_non_pin_claude_error_retains_existing_reinstall_fallback(self):
        output = self.shell(self.agent_body(), TEST_PIN=self.actual, TEST_INSTALLER_EXIT="7")
        self.assertIn("FAILURES=1 PINS=0", output)
        self.assertEqual(self.events().count("execute"), 2)
        self.assertNotIn("CHECKSUM BLOCKED", output)

    def test_success_after_refreshed_metadata_is_not_counted_as_pin_failure(self):
        output = self.shell('run_cmd "fixture" update_run_verified_installer claude latest; result; print_summary',
                            TEST_REFRESH="accept")
        self.assertIn("COUNTS=1,0,0,0", output)
        self.assertNotIn("CHECKSUM BLOCKED", output)

    def test_dry_run_makes_no_downloads_or_pin_claims(self):
        output = self.shell('DRY_RUN=true; run_cmd "fixture" update_run_verified_installer claude latest; '
                            'run_cmd_claude_update; printf "PINS=%s\\n" "${#UPDATE_PIN_FAILURES[@]}"')
        self.assertIn("PINS=0", output)
        self.assertEqual(self.events(), [])

    def test_hold_and_backoff_short_circuit_before_metadata_or_network(self):
        for function, status in (("update_tool_hold_details", 93), ("update_tool_rollback_backoff_details", 94)):
            with self.subTest(function=function):
                self.shell(function + '() { return 0; }; update_run_verified_installer claude latest', code=status)
        self.assertEqual(self.events(), [])

    def test_summary_names_distinct_pin_failures_in_quiet_mode_and_log(self):
        output = self.shell('update_finish_cmd_pin_failure "Claude Code"; update_finish_cmd_pin_failure "Grok CLI"; '
                            'update_finish_cmd_pin_failure "Claude Code"; result; print_summary')
        self.assertIn("COUNTS=0,0,2,2", output)
        self.assertIn("CHECKSUM BLOCKED: 2 update(s)", output)
        self.assertIn("checksums.yaml", output)
        log = (self.base / "update.log").read_text()
        self.assertIn("CHECKSUM BLOCKED: Claude Code", log)
        self.assertIn("CHECKSUM BLOCKED: Grok CLI", log)

    def test_abort_on_failure_reports_pin_reason_before_exiting(self):
        output = self.shell('ABORT_ON_FAILURE=true; run_cmd fixture update_run_verified_installer claude latest; '
                            'printf "UNREACHABLE\\n"', code=1)
        self.assertIn("CHECKSUM BLOCKED", output)
        self.assertIn("checksums.yaml", output)
        self.assertNotIn("UNREACHABLE", output)
        self.assertNotIn("execute", self.events())

    def test_healthy_tool_does_not_clear_prior_pin_failures(self):
        output = self.shell('update_finish_cmd_pin_failure "Claude Code"; run_cmd healthy /bin/true; result; print_summary')
        self.assertIn("COUNTS=1,0,1,1", output)
        self.assertIn("CHECKSUM BLOCKED: 1 update(s)", output)
        self.assertIn("Partial failure", output)


ROLLBACK_COMMON = r'''
source "$UPDATE_TEST_LIBRARY"
source "$REPO_ROOT/scripts/lib/security.sh"
DRY_RUN=false FORCE_MODE=false VERBOSE=false QUIET=true ABORT_ON_FAILURE=false
UPDATE_LOG_FILE="$TEST_ROOT/update.log"
RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' NC=''
SUCCESS_COUNT=0 SKIP_COUNT=0 FAIL_COUNT=0
UPDATE_SECURITY_READY=true
UPDATE_SMOKE_TIMEOUT=2
ACFS_UPDATE_RETRY_SLEEP_SECONDS=0
ACFS_UPDATE_RETRY_MAX_ATTEMPTS=3
KNOWN_INSTALLERS["$TEST_TOOL"]='https://fixture.invalid/installer.sh'
update_require_security() { return 0; }
get_checksum() { printf '%s\n' "$TEST_PIN"; }
update_tool_hold_details() { return 1; }
update_tool_latest_release_tag() { printf '%s\n' 'v2.0.0'; }
update_tool_binary_path() {
    [[ -x "$TEST_ROOT/bin/fixturetool" && ! -d "$TEST_ROOT/bin/fixturetool" ]] || return 1
    printf '%s\n' "$TEST_ROOT/bin/fixturetool"
}
update_binary_path() { update_tool_binary_path "$@"; }
update_create_target_readable_temp_file() { mktemp "$TEST_ROOT/stage.XXXXXX"; }
update_private_installer_tmpdir() { return 0; }
update_run_in_target_context() { shift; "$@"; }
acfs_download_to_file() {
    printf 'download\n' >> "$TEST_ROOT/events"
    cat "$TEST_ROOT/installer.sh" > "$2"
}
acfs_refresh_loaded_checksums_from_remote() { return 1; }
# Keep the verified script and capture files; all binary fixture versions are
# also retained separately even when the real rollback replaces a broken file.
rm() { :; }
'''


class RollbackFailureTests(unittest.TestCase):
    def fixture(self, action="broken", installer_exit=17, *, initial=True,
                command="direct", expected=17, transient=False, pin=None, tool="fixturetool"):
        base = Path(tempfile.mkdtemp(prefix="acfs-rollback-test-"))
        (base / "bin").mkdir()
        (base / "originals").mkdir()
        versions = {
            "old": b'#!/bin/bash\nprintf "fixturetool 1.0.0\\n"\n',
            "healthy": b'#!/bin/bash\nprintf "fixturetool 2.0.0\\n"\n',
            "broken": b'#!/bin/bash\nprintf "missing runtime dependency\\n" >&2\nexit 1\n',
            "unsupported": b'#!/bin/bash\nprintf "Usage: fixturetool OTHER\\n" >&2\nexit 2\n',
        }
        for name, data in versions.items():
            path = base / "originals" / name
            path.write_bytes(data)
            path.chmod(0o755)
        active = base / "bin/fixturetool"
        if initial:
            active.write_bytes(versions["old"])
            active.chmod(0o755)
        original_inode = active.stat().st_ino if initial else None
        installer = br'''#!/bin/bash
set -eu
printf 'execute\n' >> "$TEST_ROOT/events"
case "$TEST_ACTION" in
    broken|healthy|unsupported)
        cp "$TEST_ROOT/originals/$TEST_ACTION" "$TEST_ROOT/bin/fixturetool" ;;
    nonexec)
        cp "$TEST_ROOT/originals/healthy" "$TEST_ROOT/bin/fixturetool"
        chmod 0644 "$TEST_ROOT/bin/fixturetool" ;;
    missing|directory)
        mv "$TEST_ROOT/bin/fixturetool" "$TEST_ROOT/installer-displaced"
        if [[ "$TEST_ACTION" == directory ]]; then mkdir "$TEST_ROOT/bin/fixturetool"; fi ;;
    unchanged) : ;;
    *) exit 99 ;;
esac
if [[ "$TEST_TRANSIENT" == true ]]; then printf 'curl: (7) Connection refused\n' >&2; fi
exit "$TEST_INSTALLER_EXIT"
'''
        (base / "installer.sh").write_bytes(installer)
        actual_pin = hashlib.sha256(installer).hexdigest()
        env = {
            "PATH": "/usr/bin:/bin", "HOME": str(base), "TARGET_HOME": str(base),
            "XDG_STATE_HOME": str(base / "state"), "TMPDIR": str(base),
            "REPO_ROOT": str(ROOT), "TEST_ROOT": str(base), "NO_COLOR": "1",
            "ACFS_INTERACTIVE": "false", "TEST_ACTION": action,
            "TEST_TOOL": tool,
            "TEST_INSTALLER_EXIT": str(installer_exit), "TEST_TRANSIENT": str(transient).lower(),
            "TEST_PIN": actual_pin if pin is None else pin,
            "UPDATE_TEST_LIBRARY": os.environ.get("ACFS_UPDATE_TEST_LIBRARY", str(ROOT / "scripts/lib/update.sh")),
        }
        commands = {
            "direct": 'update_run_verified_installer "$TEST_TOOL"',
            "captured": 'update_run_command_capture_with_retry fixture update_run_verified_installer "$TEST_TOOL"',
            "consumer": 'update_run_verified_installer_or_existing_on_transient fixture "$TEST_TOOL" fixturetool fixturetool',
        }
        body = ROLLBACK_COMMON + '\nrc=0\n' + commands[command] + r''' || rc=$?
printf 'COUNTS=%s,%s,%s\n' "$SUCCESS_COUNT" "$SKIP_COUNT" "$FAIL_COUNT"
exit "$rc"
'''
        result = subprocess.run(["/bin/bash", "--noprofile", "--norc", "-c", body],
                                env=env, text=True, capture_output=True, timeout=15)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, expected, output + "\nArtifacts: " + str(base))
        return base, active, versions, actual_pin, original_inode, output

    def assert_restored(self, fixture):
        base, active, versions, pin, _, output = fixture
        self.assertTrue(active.is_file(), output)
        self.assertEqual(active.read_bytes(), versions["old"], output)
        self.assertTrue(os.access(active, os.X_OK))
        probe = subprocess.run([str(active), "--version"], capture_output=True, text=True, timeout=2)
        self.assertEqual((probe.returncode, probe.stdout), (0, "fixturetool 1.0.0\n"))
        state = (base / "state/acfs/update-rollback.state").read_text().split()
        self.assertEqual(state[0:2], ["fixturetool", "1"])
        self.assertEqual(state[3:], [pin, "v2.0.0"])
        self.assertIn("ROLLED BACK", (base / "update.log").read_text())

    def test_nonzero_installer_recovers_each_damaged_binary_and_preserves_status(self):
        for action in ("broken", "nonexec", "missing"):
            with self.subTest(action=action):
                self.assert_restored(self.fixture(action))

    def test_zero_exit_installer_recovers_each_damaged_binary_and_fails(self):
        for action in ("broken", "nonexec", "missing"):
            with self.subTest(action=action):
                self.assert_restored(self.fixture(action, 0, expected=1))

    def test_nonzero_installer_keeps_healthy_binary_and_original_error(self):
        for action in ("unchanged", "healthy"):
            with self.subTest(action=action):
                base, active, versions, _, inode, output = self.fixture(action)
                self.assertEqual(active.read_bytes(), versions["old" if action == "unchanged" else "healthy"])
                self.assertEqual((base / "bin/fixturetool.prev").read_bytes(), versions["old"])
                self.assertFalse((base / "state/acfs/update-rollback.state").exists())
                self.assertNotIn("ROLLED BACK", output)
                if action == "unchanged": self.assertEqual(active.stat().st_ino, inode)

    def test_healthy_success_keeps_manual_rollback_copy(self):
        base, active, versions, _, _, _ = self.fixture("healthy", 0, expected=0)
        self.assertEqual(active.read_bytes(), versions["healthy"])
        self.assertEqual((base / "bin/fixturetool.prev").read_bytes(), versions["old"])
        self.assertFalse((base / "state/acfs/update-rollback.state").exists())

    def test_unsupported_smoke_probe_does_not_trigger_rollback_or_backoff(self):
        for status in (0, 17):
            with self.subTest(status=status):
                base, active, versions, _, _, output = self.fixture("unsupported", status, expected=status)
                self.assertEqual(active.read_bytes(), versions["unsupported"])
                self.assertEqual((base / "bin/fixturetool.prev").read_bytes(), versions["old"])
                self.assertFalse((base / "state/acfs/update-rollback.state").exists())
                if status == 0: self.assertIn("VERIFICATION UNAVAILABLE", output)

    def test_fresh_unverifiable_install_preserves_per_tool_delegation(self):
        for status in (0, 17):
            with self.subTest(status=status):
                base, active, _, _, _, _ = self.fixture("unchanged", status, initial=False, expected=status)
                self.assertFalse(active.exists())
                self.assertFalse((base / "bin/fixturetool.prev").exists())
                self.assertFalse((base / "state/acfs/update-rollback.state").exists())

    def test_shell_function_installer_retains_its_no_binary_exception(self):
        base, active, versions, _, inode, _ = self.fixture("unchanged", tool="nvm")
        self.assertEqual(active.read_bytes(), versions["old"])
        self.assertEqual(active.stat().st_ino, inode)
        self.assertFalse((base / "bin/fixturetool.prev").exists())
        self.assertFalse((base / "state/acfs/update-rollback.state").exists())

    def test_directory_at_restore_target_cannot_absorb_backup_or_report_success(self):
        for status in (0, 17):
            with self.subTest(status=status):
                base, active, versions, _, _, output = self.fixture("directory", status, expected=status or 1)
                self.assertTrue(active.is_dir())
                self.assertEqual(list(active.iterdir()), [])
                self.assertEqual((base / "bin/fixturetool.prev").read_bytes(), versions["old"])
                self.assertIn("ROLLBACK FAILED", output)
                self.assertNotIn("ROLLED BACK:", output)

    def test_upstream_checksum_exit_cannot_impersonate_refusal_after_damage(self):
        fixture = self.fixture("broken", 95, expected=1)
        self.assert_restored(fixture)
        self.assertNotIn("CHECKSUM BLOCKED", fixture[-1])

    def test_pin_refusal_never_snapshots_or_executes(self):
        base, active, versions, _, inode, _ = self.fixture(pin="1" * 64, expected=95)
        self.assertEqual(active.read_bytes(), versions["old"])
        self.assertEqual(active.stat().st_ino, inode)
        self.assertFalse((base / "bin/fixturetool.prev").exists())
        self.assertEqual((base / "events").read_text().splitlines(), ["download"])

    def test_transient_output_cannot_retry_failed_recovery_into_backoff_skip(self):
        for command, expected in (("captured", 17), ("consumer", 1)):
            with self.subTest(command=command):
                base, active, versions, _, _, output = self.fixture("directory", command=command,
                                                                  expected=expected, transient=True)
                self.assertTrue(active.is_dir())
                self.assertEqual((base / "bin/fixturetool.prev").read_bytes(), versions["old"])
                self.assertEqual((base / "events").read_text().splitlines(), ["download", "execute"])
                self.assertIn("ROLLBACK FAILED", (base / "update.log").read_text())
                self.assertNotIn("BACKOFF:", output)
                if command == "consumer": self.assertIn("COUNTS=0,0,1", output)


class SharedRollbackSafetyTests(unittest.TestCase):
    """Exercise shared recovery with ordinary tools, never upstream installers.

    Account transitions are explicitly a fixture on positive paths. The denial
    cases retain the real target runner, and must never fall back to the caller.
    """

    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="acfs-shared-rollback-"))
        (self.base / "bin").mkdir()
        self.active = self.base / "bin/fixturetool"
        self.backup = self.base / "bin/fixturetool.prev"
        self.old = b'#!/bin/bash\nprintf "fixturetool 1.0.0\\n"\n'
        self.broken = b'#!/bin/bash\nprintf "missing runtime dependency\\n" >&2\nexit 1\n'
        self.active.write_bytes(self.old)
        self.active.chmod(0o755)
        (self.base / "broken").write_bytes(self.broken)
        (self.base / "broken").chmod(0o755)
        self.victim = self.base / "unrelated file"
        self.victim.write_bytes(b"unrelated data must survive\n")
        self.victim_bytes = self.victim.read_bytes()
        self.installer = self.base / "installer.sh"
        self.write_installer("")
        self.env = {
            "PATH": "/usr/bin:/bin", "HOME": str(self.base),
            "TARGET_HOME": str(self.base), "TEST_ROOT": str(self.base),
            "XDG_STATE_HOME": str(self.base / "state"), "TMPDIR": str(self.base),
            "REPO_ROOT": str(ROOT), "NO_COLOR": "1", "ACFS_INTERACTIVE": "false",
            "TEST_TOOL": "fixturetool",
            "UPDATE_TEST_LIBRARY": os.environ.get("ACFS_UPDATE_TEST_LIBRARY", str(ROOT / "scripts/lib/update.sh")),
        }
        self.shell_count = 0

    def write_installer(self, body):
        self.installer.write_text('#!/bin/bash\nset -eu\nprintf "execute\\n" >> "$TEST_ROOT/events"\n'
                                  + body + "\n")

    def shell(self, body, *, code=0, timeout=15, **env):
        # Save the production runner before the existing acquisition/account
        # boundary fixture replaces it. Denial cases restore it explicitly.
        prefix = r'''
source "$UPDATE_TEST_LIBRARY"
real_target_runner="$(declare -f update_run_in_target_context)"
''' + ROLLBACK_COMMON
        self.shell_count += 1
        output_path = self.base / f"shell-{self.shell_count}.log"
        with output_path.open("w") as output_file:
            process = subprocess.Popen(
                ["/bin/bash", "--noprofile", "--norc", "-c", prefix + body],
                env=self.env | {"TEST_PIN": hashlib.sha256(self.installer.read_bytes()).hexdigest()} | env,
                stdout=output_file, stderr=subprocess.STDOUT, start_new_session=True,
            )
            try:
                process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                # The baseline lacks an installer deadline. Kill only this
                # fixture's session group, retaining all files and output.
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=3)
                self.fail(f"fixture exceeded {timeout}s; artifacts: {self.base}")
        output = output_path.read_text()
        self.assertEqual(process.returncode, code, output + f"\nArtifacts: {self.base}")
        return output

    def events(self):
        path = self.base / "events"
        return path.read_text().splitlines() if path.exists() else []

    def assert_no_successful_rollback(self, output):
        self.assertNotIn("ROLLED BACK", output)
        log = self.base / "update.log"
        if log.exists():
            self.assertNotIn("ROLLED BACK", log.read_text())

    def test_snapshot_refuses_symlink_backup_without_overwriting_its_target(self):
        self.backup.symlink_to(self.victim)
        output = self.shell('update_snapshot_tool_binary fixturetool\n'
                            'printf "PREV=%s\\n" "${UPDATE_ROLLBACK_PREV_PATH:-}"\n')
        self.assertEqual(self.victim.read_bytes(), self.victim_bytes)
        self.assertTrue(self.backup.is_symlink())
        self.assertIn("PREV=\n", output)
        self.assertEqual(self.active.read_bytes(), self.old)

    def test_snapshot_refuses_directory_backup_without_creating_a_child(self):
        self.backup.mkdir()
        output = self.shell('update_snapshot_tool_binary fixturetool\n'
                            'printf "PREV=%s\\n" "${UPDATE_ROLLBACK_PREV_PATH:-}"\n')
        self.assertEqual(list(self.backup.iterdir()), [])
        self.assertIn("PREV=\n", output)

    def test_snapshot_replaces_hardlinked_backup_without_changing_its_peer(self):
        os.link(self.victim, self.backup)
        self.shell('update_snapshot_tool_binary fixturetool\n'
                   '[[ -n "${UPDATE_ROLLBACK_PREV_PATH:-}" ]]\n')
        self.assertEqual(self.victim.read_bytes(), self.victim_bytes)
        self.assertEqual(self.backup.read_bytes(), self.old)
        self.assertNotEqual(self.backup.stat().st_ino, self.victim.stat().st_ino)

    def test_failed_staged_snapshot_preserves_the_previous_backup(self):
        retained = b"retained earlier backup\n"
        self.backup.write_bytes(retained)
        failing_cp = self.base / "failing-cp"
        failing_cp.write_text('#!/bin/bash\nprintf "incomplete copy\\n" > "${!#}"\nexit 23\n')
        failing_cp.chmod(0o755)
        output = self.shell(r'''
update_system_binary_path() {
    if [[ "$1" == cp ]]; then printf '%s\n' "$TEST_ROOT/failing-cp";
    elif [[ -x "/usr/bin/$1" ]]; then printf '/usr/bin/%s\n' "$1";
    else printf '/bin/%s\n' "$1"; fi
}
update_snapshot_tool_binary fixturetool
printf 'PREV=%s\n' "${UPDATE_ROLLBACK_PREV_PATH:-}"
''')
        self.assertEqual(self.backup.read_bytes(), retained)
        self.assertEqual(self.active.read_bytes(), self.old)
        self.assertIn("PREV=\n", output)

    def test_late_backup_symlink_is_neither_restored_nor_executed(self):
        decoy = self.base / "decoy"
        decoy.write_text('#!/bin/bash\nprintf "decoy\\n" >> "$TEST_ROOT/events"\nexit 0\n')
        decoy.chmod(0o755)
        output = self.shell(r'''
update_snapshot_tool_binary fixturetool
mv "$TEST_ROOT/bin/fixturetool.prev" "$TEST_ROOT/retained-original"
ln -s "$TEST_ROOT/decoy" "$TEST_ROOT/bin/fixturetool.prev"
cp "$TEST_ROOT/broken" "$TEST_ROOT/bin/fixturetool"
update_verify_tool_or_rollback fixturetool "$TEST_PIN"
''', code=1)
        self.assertTrue(self.backup.is_symlink())
        self.assertFalse(self.active.is_symlink())
        self.assertEqual(self.active.read_bytes(), self.broken)
        self.assertEqual((self.base / "retained-original").read_bytes(), self.old)
        self.assertNotIn("decoy", self.events())
        self.assertIn("ROLLBACK FAILED", output)
        self.assert_no_successful_rollback(output)

    def test_changed_backup_bytes_are_rejected_before_restoration_or_probe(self):
        output = self.shell(r'''
update_snapshot_tool_binary fixturetool
printf '#!/bin/bash\nprintf "decoy\\n" >> "$TEST_ROOT/events"\nexit 0\n' > "$TEST_ROOT/bin/fixturetool.prev"
cp "$TEST_ROOT/broken" "$TEST_ROOT/bin/fixturetool"
update_verify_tool_or_rollback fixturetool "$TEST_PIN"
''', code=1)
        self.assertEqual(self.active.read_bytes(), self.broken)
        self.assertNotIn("decoy", self.events())
        self.assertIn("ROLLBACK FAILED", output)
        self.assert_no_successful_rollback(output)

    def test_restore_refuses_substituted_destination_symlink_without_touching_peer(self):
        self.victim.write_bytes(self.broken)
        self.victim.chmod(0o755)
        output = self.shell(r'''
update_snapshot_tool_binary fixturetool
mv "$TEST_ROOT/bin/fixturetool" "$TEST_ROOT/displaced-original"
ln -s "$TEST_ROOT/unrelated file" "$TEST_ROOT/bin/fixturetool"
update_verify_tool_or_rollback fixturetool "$TEST_PIN"
''', code=1)
        self.assertTrue(self.active.is_symlink())
        self.assertEqual(self.victim.read_bytes(), self.broken)
        self.assertEqual(self.backup.read_bytes(), self.old)
        self.assertIn("ROLLBACK FAILED", output)
        self.assert_no_successful_rollback(output)

    def test_snapshot_and_restore_mutations_cross_the_target_runner_boundary(self):
        # Only system utility discovery and the account transition are fixtures.
        # The real snapshot/restore commands execute; wrappers record the env
        # supplied by the target boundary before delegating to the host utility.
        commands = self.base / "commands"
        commands.mkdir()
        for command in ("cp", "mv"):
            path = commands / command
            path.write_text('#!/bin/bash\n'
                            f'printf "{command}:%s\\n" "${{TEST_TARGET_CONTEXT:-caller}}" >> "$TEST_ROOT/mutations"\n'
                            f'exec /bin/{command} "$@"\n')
            path.chmod(0o755)
        self.shell(r'''
update_system_binary_path() {
    case "$1" in
        cp|mv) printf '%s/commands/%s\n' "$TEST_ROOT" "$1" ;;
        *) if [[ -x "/usr/bin/$1" ]]; then printf '/usr/bin/%s\n' "$1"; else printf '/bin/%s\n' "$1"; fi ;;
    esac
}
update_run_in_target_context() { shift; TEST_TARGET_CONTEXT=target "$@"; }
update_snapshot_tool_binary fixturetool
[[ -n "${UPDATE_ROLLBACK_PREV_PATH:-}" ]] || exit 98
printf 'snapshot-complete\n' >> "$TEST_ROOT/mutations"
cp "$TEST_ROOT/broken" "$TEST_ROOT/bin/fixturetool"
update_verify_tool_or_rollback fixturetool "$TEST_PIN"
''', code=1)
        records = (self.base / "mutations").read_text().splitlines() if (self.base / "mutations").exists() else []
        self.assertIn("cp:target", records)
        self.assertIn("mv:target", records)
        self.assertIn("snapshot-complete", records)
        self.assertIn("mv:target", records[records.index("snapshot-complete") + 1:])
        self.assertTrue(all(record.endswith(":target") for record in records if record != "snapshot-complete"), records)
        self.assertEqual(self.active.read_bytes(), self.old)

    def test_unavailable_real_target_account_does_not_snapshot_as_the_caller(self):
        output = self.shell(r'''
eval "$real_target_runner"
update_target_user() { printf '%s\n' acfs_fixture_unavailable_account; }
update_target_home() { printf '%s\n' "$TARGET_HOME"; }
update_snapshot_tool_binary fixturetool
printf 'PREV=%s\n' "${UPDATE_ROLLBACK_PREV_PATH:-}"
''')
        self.assertFalse(self.backup.exists())
        self.assertEqual(self.active.read_bytes(), self.old)
        self.assertIn("PREV=\n", output)

    def test_unavailable_real_target_account_does_not_restore_as_the_caller(self):
        output = self.shell(r'''
update_snapshot_tool_binary fixturetool
cp "$TEST_ROOT/broken" "$TEST_ROOT/bin/fixturetool"
eval "$real_target_runner"
update_target_user() { printf '%s\n' acfs_fixture_unavailable_account; }
update_target_home() { printf '%s\n' "$TARGET_HOME"; }
update_verify_tool_or_rollback fixturetool "$TEST_PIN"
''', code=1)
        self.assertEqual(self.active.read_bytes(), self.broken)
        self.assertEqual(self.backup.read_bytes(), self.old)
        self.assertIn("ROLLBACK FAILED", output)
        self.assert_no_successful_rollback(output)

    def test_relative_command_symlink_recovers_its_payload_and_keeps_the_link(self):
        payload_dir = self.base / "payload directory"
        payload_dir.mkdir()
        payload = payload_dir / "tool"
        self.active.rename(payload)
        self.active.symlink_to("../payload directory/tool")
        self.write_installer('cp "$TEST_ROOT/broken" "$TEST_ROOT/bin/fixturetool"\nexit 17')
        output = self.shell('update_run_verified_installer fixturetool\n', code=17)
        self.assertTrue(self.active.is_symlink())
        self.assertEqual(os.readlink(self.active), "../payload directory/tool")
        self.assertEqual(payload.read_bytes(), self.old)
        self.assertEqual(self.active.read_bytes(), self.old)
        self.assertFalse(self.backup.exists())
        self.assertIn("ROLLED BACK", output)

    def test_restored_wrapper_cannot_claim_recovery_while_its_payload_is_broken(self):
        payload = self.base / "wrapper-payload"
        payload.write_bytes(self.old)
        payload.chmod(0o755)
        wrapper = b'#!/bin/bash\nexec "$TEST_ROOT/wrapper-payload" "$@"\n'
        self.active.write_bytes(wrapper)
        self.write_installer('cp "$TEST_ROOT/broken" "$TEST_ROOT/wrapper-payload"\nexit 17')
        output = self.shell('update_run_verified_installer fixturetool\n', code=17)
        self.assertEqual(self.active.read_bytes(), wrapper)
        self.assertEqual(payload.read_bytes(), self.broken)
        self.assertIn("ROLLBACK FAILED", output)
        self.assert_no_successful_rollback(output)
        state = (self.base / "state/acfs/update-rollback.state").read_text().split()
        self.assertEqual(state[:2], ["fixturetool", "1"])

    def test_zero_and_invalid_deadlines_fail_before_acquisition_or_snapshot(self):
        for duration in ("0", "0.0s", "-1", "invalid", "1ms",
                         "0." + "0" * 400 + "1s", "9" * 400 + "d"):
            with self.subTest(duration=duration):
                self.shell('update_run_verified_installer fixturetool\n', code=1,
                           UPDATE_CMD_TIMEOUT=duration)
                self.assertEqual(self.events(), [])
                self.assertFalse(self.backup.exists())
                self.assertEqual(self.active.read_bytes(), self.old)

    def test_missing_timeout_or_bash_fails_before_acquisition_or_snapshot(self):
        for missing in ("timeout", "bash"):
            with self.subTest(missing=missing):
                self.shell(r'''
update_system_binary_path() {
    [[ "$1" != "$TEST_MISSING_SYSTEM_COMMAND" ]] || return 1
    if [[ -x "/usr/bin/$1" ]]; then printf '/usr/bin/%s\n' "$1"; else printf '/bin/%s\n' "$1"; fi
}
update_run_verified_installer fixturetool
''', code=1, TEST_MISSING_SYSTEM_COMMAND=missing)
                self.assertEqual(self.events(), [])
                self.assertFalse(self.backup.exists())

    def test_positive_fractional_deadline_bounds_the_actual_installer(self):
        self.write_installer('sleep 2\nprintf "finished\\n" >> "$TEST_ROOT/events"')
        self.shell('update_run_verified_installer fixturetool\n', code=137, UPDATE_CMD_TIMEOUT="0.2s")
        self.assertEqual(self.events(), ["download", "execute"])
        self.assertEqual(self.active.read_bytes(), self.old)

    def test_native_installer_exit_statuses_still_propagate(self):
        for native_status, expected in ((124, 124), (137, 137), (95, 1)):
            with self.subTest(native_status=native_status):
                self.write_installer(f"exit {native_status}")
                output = self.shell('update_run_verified_installer fixturetool\n', code=expected,
                                    UPDATE_CMD_TIMEOUT="2s")
                self.assertNotIn("CHECKSUM BLOCKED", output)
                self.assertEqual(self.active.read_bytes(), self.old)

    @staticmethod
    def process_is_running(pid):
        try:
            state = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[0]
        except FileNotFoundError:
            return False
        return state not in ("Z", "X")

    def assert_deadline_stops_descendants_before_recovery(self, parent_ignores_term):
        # The restored tool records whether the installer child is still alive
        # when recovery probes it. A zombie is finished and cannot mutate files.
        self.old = br'''#!/bin/bash
if [[ -r "$TEST_ROOT/child.pid" ]]; then
    read -r child_pid < "$TEST_ROOT/child.pid"
    if [[ -r "/proc/$child_pid/stat" ]]; then
        read -r child_stat < "/proc/$child_pid/stat"
        child_state="${child_stat##*) }"
        case "$child_state" in Z\ *|X\ *) ;; *) printf 'child-alive-at-restore\n' >> "$TEST_ROOT/events" ;; esac
    fi
fi
printf 'fixturetool 1.0.0\n'
'''
        self.active.write_bytes(self.old)
        child = self.base / "child.sh"
        child.write_text('#!/bin/bash\ntrap "" TERM\nprintf "%s\\n" "$BASHPID" > "$TEST_ROOT/child.pid"\n'
                         'sleep 2\nprintf "late-child-write\\n" >> "$TEST_ROOT/events"\n'
                         'cp "$TEST_ROOT/broken" "$TEST_ROOT/bin/fixturetool"\n')
        child.chmod(0o755)
        trap = "trap '' TERM" if parent_ignores_term else "trap 'exit 0' TERM"
        self.write_installer(trap + '\ncp "$TEST_ROOT/broken" "$TEST_ROOT/bin/fixturetool"\n'
                             '/bin/bash "$TEST_ROOT/child.sh" &\nwait\n')
        try:
            output = self.shell('update_run_verified_installer fixturetool\n', code=137,
                                timeout=10, UPDATE_CMD_TIMEOUT="1s")
            pid = int((self.base / "child.pid").read_text())
            self.assertFalse(self.process_is_running(pid), f"installer child {pid} survived recovery")
            # Observe past the child's scheduled write, including the case in
            # which a TERM-handling parent exited while its child survived.
            time.sleep(1.2)
            self.assertEqual(self.events(), ["download", "execute"])
            self.assertEqual(self.active.read_bytes(), self.old)
            self.assertIn("ROLLED BACK", output)
        finally:
            pid_file = self.base / "child.pid"
            if pid_file.exists():
                pid = int(pid_file.read_text())
                if self.process_is_running(pid):
                    os.kill(pid, signal.SIGKILL)

    def test_deadline_kills_term_resistant_parent_and_child_before_recovery(self):
        self.assert_deadline_stops_descendants_before_recovery(parent_ignores_term=True)

    def test_deadline_kills_child_even_when_parent_would_exit_on_term(self):
        self.assert_deadline_stops_descendants_before_recovery(parent_ignores_term=False)


AGENT_MAIL_DEADLINE_COMMON = ROLLBACK_COMMON + r'''
UPDATE_STACK=true
ABORT_ON_FAILURE="${TEST_ABORT:-false}"
DRY_RUN="${TEST_DRY_RUN:-false}"
update_ensure_minisign() { return 0; }
update_target_user() { printf '%s\n' fixture; }
update_target_home() { printf '%s\n' "$HOME"; }
update_run_in_target_context() (
    local assignment="" assignments="$1"
    shift
    while IFS= read -r assignment; do
        [[ -z "$assignment" ]] || export "$assignment"
    done <<< "$assignments"
    TEST_TARGET_CONTEXT=target "$@"
)
update_private_installer_tmpdir() {
    printf 'private-tmp\n' >> "$TEST_ROOT/events"
    mktemp -d "$TEST_ROOT/private.XXXXXX"
}
update_remove_target_installer_tmpdir() {
    [[ "$1" == mcp_agent_mail ]] || return 97
    # The child and its sleep process retain this lock until they exit. Probe
    # the owned resource, not /proc/<pid>: /proc may expose a different PID
    # namespace from the one in which Bash reports BASHPID.
    if [[ -r "$TEST_ROOT/child.pid" ]] && ! flock -n "$TEST_ROOT/child.lock" true; then
        printf 'child-alive-at-cleanup\n' >> "$TEST_ROOT/events"
    fi
    printf 'tmp-cleanup\n' >> "$TEST_ROOT/events"
    # Retain the fixture contents while observing the real cleanup call/order.
    mv -- "$2" "$2.retained"
}
rm() {
    local path=""
    for path in "$@"; do
        if [[ "$path" == "$TEST_ROOT"/stage.* && -f "$path" ]]; then
            printf 'script-cleanup\n' >> "$TEST_ROOT/events"
            mv -- "$path" "$path.retained"
        fi
    done
}
update_source_stack_lib() { return 0; }
_stack_repair_agent_mail_cli_symlink() { printf 'repair\n' >> "$TEST_ROOT/events"; }
_stack_configure_agent_mail_service() { printf 'configure\n' >> "$TEST_ROOT/events"; }
_stack_wait_for_agent_mail_health() { printf 'health\n' >> "$TEST_ROOT/events"; }
# Agent Mail uses the real dispatch, verifier, logging, interpreter and timeout.
# Only APR retains run_cmd to mark continued execution; unrelated updates do
# not spend the fixture's watchdog budget logging dozens of inert commands.
fixture_run_cmd_definition="$(declare -f run_cmd)"
eval "${fixture_run_cmd_definition/run_cmd ()/agent_mail_fixture_run_cmd ()}"
run_cmd() {
    if [[ "$1" == APR ]]; then agent_mail_fixture_run_cmd "$@"; fi
    return 0
}
capture_version_before() { :; }
capture_version_after() { return 1; }
update_binary_exists() { return 1; }
update_run_verified_installer() {
    if [[ "$1" == apr ]]; then printf 'apr\n' >> "$TEST_ROOT/events"; fi
    return 0
}
update_run_verified_installer_with_env() { return 0; }
update_run_verified_installer_or_existing_on_transient() { return 0; }
update_run_verified_installer_with_target_tmpdir_or_existing_on_transient() { return 0; }
update_run_slb_verified_install() { return 0; }
update_run_fsfs_installer() { return 0; }
'''


class AgentMailDeadlineTests(unittest.TestCase):
    """Run Agent Mail's real update branch with a verified, inert installer.

    Account switching, private-directory removal and service operations are
    fixture boundaries. Interpreter lifetime, descendants, verification,
    argument/environment forwarding and failure accounting run as production.
    """

    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="acfs-agent-mail-deadline-"))
        self.installer = self.base / "installer.sh"
        self.env = {
            "PATH": "/usr/bin:/bin", "HOME": str(self.base),
            "TARGET_HOME": str(self.base), "TEST_ROOT": str(self.base),
            "REPO_ROOT": str(ROOT), "TMPDIR": str(self.base),
            "TEST_TOOL": "mcp_agent_mail", "NO_COLOR": "1",
            "ACFS_INTERACTIVE": "false", "UPDATE_CMD_TIMEOUT": "5s",
            "UPDATE_TEST_LIBRARY": os.environ.get("ACFS_UPDATE_TEST_LIBRARY", str(ROOT / "scripts/lib/update.sh")),
        }
        self.shell_count = 0
        self.write_installer("")

    def write_installer(self, body):
        self.installer.write_text(r'''#!/bin/bash
set -eu
printf 'execute\n' >> "$TEST_ROOT/events"
printf '%s\n' "$AM_INSTALL_SKIP_MCP_SETUP" "$AM_INSTALL_SKIP_REMOTE_HTTP_READINESS" \
    "$TMPDIR" "$TEST_TARGET_CONTEXT" "$(stat -c %a "$0")" "$@" > "$TEST_ROOT/context"
if IFS= read -r caller_input; then
    printf 'stdin-open\n' >> "$TEST_ROOT/events"
else
    printf 'stdin-closed\n' >> "$TEST_ROOT/events"
fi
''' + body + "\n")

    def shell(self, setup="", *, code=0, **env):
        self.shell_count += 1
        output_path = self.base / f"shell-{self.shell_count}.log"
        command = (AGENT_MAIL_DEADLINE_COMMON + setup + '\nupdate_stack\n'
                   'printf "FAILURES=%s\\n" "$FAIL_COUNT"\nprint_summary\n')
        with output_path.open("w") as output_file:
            process = subprocess.Popen(
                ["/bin/bash", "--noprofile", "--norc", "-c", command],
                env=self.env | {"TEST_PIN": hashlib.sha256(self.installer.read_bytes()).hexdigest()} | env,
                stdin=subprocess.PIPE, stdout=output_file, stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            try:
                process.communicate(input=b"caller input must not reach the installer\n", timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate(timeout=3)
                self.fail(f"Agent Mail fixture exceeded 15s; artifacts: {self.base}")
        output = output_path.read_text()
        self.assertEqual(process.returncode, code, output + f"\nArtifacts: {self.base}")
        return output

    def events(self):
        path = self.base / "events"
        return path.read_text().splitlines() if path.exists() else []

    def assert_failed_without_service_changes(self, output, *, aborted=False):
        events = self.events()
        self.assertIn("tmp-cleanup", events)
        self.assertIn("script-cleanup", events)
        self.assertNotIn("stdin-open", events)
        for operation in ("repair", "configure", "health"):
            self.assertNotIn(operation, events)
        self.assertIn("installer failed (exit 137)", output)
        self.assertNotIn("Success: MCP Agent Mail", (self.base / "update.log").read_text())
        if aborted:
            self.assertNotIn("apr", events)
            self.assertIn("Aborting due to failure (--abort-on-failure)", output)
        else:
            self.assertGreater(events.index("apr"), events.index("script-cleanup"))
            self.assertIn("FAILURES=1", output)
            self.assertIn("Partial failure", output)

    def test_success_preserves_target_environment_arguments_stdin_and_cleanup(self):
        output = self.shell()
        context = (self.base / "context").read_text().splitlines()
        self.assertEqual(context[:2], ["1", "1"])
        self.assertEqual(context[3:], ["target", "755", "--dest", str(self.base / "mcp_agent_mail"),
                                      "--yes", "--no-service", "--force"])
        self.assertFalse(Path(context[2]).exists())
        self.assertTrue(Path(context[2] + ".retained").is_dir())
        self.assertEqual(self.events(), ["download", "private-tmp", "execute", "stdin-closed",
                                         "script-cleanup", "tmp-cleanup", "repair", "configure", "health", "apr"])
        self.assertIn("FAILURES=0", output)

    def test_fractional_deadline_fails_without_service_changes_and_continues_stack(self):
        self.write_installer('sleep 2\nprintf "finished\\n" >> "$TEST_ROOT/events"')
        output = self.shell(UPDATE_CMD_TIMEOUT="0.2s")
        self.assert_failed_without_service_changes(output)
        self.assertNotIn("finished", self.events())

    def test_deadline_cleans_up_before_abort_on_failure(self):
        self.write_installer('sleep 2\nprintf "finished\\n" >> "$TEST_ROOT/events"')
        output = self.shell(code=1, UPDATE_CMD_TIMEOUT="0.2s", TEST_ABORT="true")
        self.assert_failed_without_service_changes(output, aborted=True)

    def test_invalid_deadlines_fail_before_download_or_temporary_directory(self):
        for duration in ("0", "0.0s", "-1", "invalid", "1ms",
                         "0." + "0" * 400 + "1s", "9" * 400 + "d"):
            with self.subTest(duration=duration):
                output = self.shell(UPDATE_CMD_TIMEOUT=duration)
                self.assertIn("cannot enforce verified installer deadline", output)
                self.assertIn("FAILURES=1", output)
                self.assertTrue(all(event == "apr" for event in self.events()), self.events())
                self.assertEqual(list(self.base.glob("stage.*")), [])

    def test_missing_trusted_timeout_or_bash_fails_before_download(self):
        for missing in ("timeout", "bash"):
            with self.subTest(missing=missing):
                output = self.shell(r'''
update_system_binary_path() {
    [[ "$1" != "$TEST_MISSING_SYSTEM_COMMAND" ]] || return 1
    if [[ -x "/usr/bin/$1" ]]; then printf '/usr/bin/%s\n' "$1"; else printf '/bin/%s\n' "$1"; fi
}
''', TEST_MISSING_SYSTEM_COMMAND=missing)
                self.assertIn("trusted timeout and bash are required", output)
                self.assertIn("FAILURES=1", output)
                self.assertTrue(all(event == "apr" for event in self.events()), self.events())

    def test_dry_run_does_not_require_or_execute_installer_deadline(self):
        output = self.shell(UPDATE_CMD_TIMEOUT="0", TEST_DRY_RUN="true")
        self.assertEqual(self.events(), [])
        self.assertIn("FAILURES=0", output)

    def assert_deadline_stops_descendants_before_cleanup(self, parent_ignores_term):
        child = self.base / "child.sh"
        child.write_text('#!/bin/bash\ntrap "" TERM\nexec 8> "$TEST_ROOT/child.lock"\nflock -x 8\n'
                         'printf "%s\\n" "$BASHPID" > "$TEST_ROOT/child.pid"\n'
                         'sleep 2\nprintf "late-child-write\\n" >> "$TEST_ROOT/events"\n')
        trap = "trap '' TERM" if parent_ignores_term else "trap 'exit 0' TERM"
        self.write_installer(trap + '\n/bin/bash "$TEST_ROOT/child.sh" &\nwait\n')
        try:
            output = self.shell(UPDATE_CMD_TIMEOUT="1s")
            self.assert_failed_without_service_changes(output)
            self.assertTrue((self.base / "child.pid").exists(), "child never reached its lifetime lock")
            with (self.base / "child.lock").open("r") as lifetime_lock:
                fcntl.flock(lifetime_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            time.sleep(1.2)
            self.assertNotIn("child-alive-at-cleanup", self.events())
            self.assertNotIn("late-child-write", self.events())
        finally:
            pid_file = self.base / "child.pid"
            if pid_file.exists():
                pid = int(pid_file.read_text())
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def test_deadline_kills_term_resistant_parent_and_child_before_cleanup(self):
        self.assert_deadline_stops_descendants_before_cleanup(parent_ignores_term=True)

    def test_deadline_kills_child_even_when_parent_would_exit_on_term(self):
        self.assert_deadline_stops_descendants_before_cleanup(parent_ignores_term=False)


GROK_UPDATE_CONTEXT = COMMON + r'''
KNOWN_INSTALLERS[grok]='https://fixture.invalid/grok-installer.sh'
update_target_user() { printf '%s\n' fixture; }
update_current_user() { printf '%s\n' "${TEST_CURRENT_USER:-fixture}"; }
update_target_home() { printf '%s\n' "$TARGET_HOME"; }
update_preferred_user_bin_dir() { printf '%s\n' "$ACFS_BIN_DIR"; }
update_private_installer_tmpdir() { return 0; }
update_tool_latest_release_tag() { return 1; }
# Host account switching is the boundary fixture. Commands, environment
# isolation, bounded execution, and ownership checks still run the real code.
update_run_in_target_context() {
    shift
    (
        cd "$TARGET_HOME" || exit 1
        export HOME="$TARGET_HOME"
        export PATH="$ACFS_BIN_DIR:$HOME/.grok/bin:/usr/bin:/bin"
        "$@"
    )
}
'''


GROK_MANIFEST_CONTEXT = r'''
source "$REPO_ROOT/scripts/generated/doctor_checks.sh"
source "$REPO_ROOT/scripts/generated/manifest_index.sh"
# Use a fixture account without creating or changing a real system user.
run_as_target() { "$@"; }
_acfs_resolve_target_home() { printf '%s\n' "$TARGET_HOME"; }
acfs_generated_resolve_current_user() { printf '%s\n' "$TARGET_USER"; }
export PATH="$ACFS_BIN_DIR:$HOME/.grok/bin:/usr/bin:/bin"
for operation in installed skip resume; do
    status=1
    case "$operation" in
        installed) if acfs_module_is_installed agents.grok; then status=0; fi ;;
        skip) if acfs_should_skip_module agents.grok; then status=0; fi ;;
        resume) if acfs_verify_module_commands agents.grok; then status=0; fi ;;
    esac
    printf '%s=%s\n' "$operation" "$status"
done
found=false
for entry in "${MANIFEST_CHECKS[@]}"; do
    IFS=$'\t' read -r id desc cmd req_flag run_as <<< "$entry"
    [[ "$id" == agents.grok ]] || continue
    found=true
    cmd="$(printf '%b' "$cmd")"
    status=0
    run_manifest_check_command "$run_as" "$cmd" || status=$?
    printf 'doctor=%s\n' "$status"
done
[[ "$found" == true ]]
'''


class GrokOwnershipTests(unittest.TestCase):
    """Command identity is a prerequisite to execution, not payload provenance.

    The executable fixtures deliberately print plausible versions. A decoy
    therefore passes the old version/help probe, but must never be invoked by
    the ownership guard or accepted as a working Grok installation.
    """

    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="acfs-grok-ownership-"))
        self.home = self.base / "target home"
        self.bin = self.home / ".local/bin"
        self.bin.mkdir(parents=True)
        machine = os.uname().machine
        arch = {"x86_64": "x86_64", "amd64": "x86_64",
                "aarch64": "aarch64", "arm64": "aarch64"}.get(machine)
        if os.uname().sysname != "Linux" or arch is None:
            self.skipTest("Grok ownership fixtures require a supported Linux architecture")
        self.payload = self.home / ".grok/downloads" / f"grok-linux-{arch}"
        self.decoy = self.base / "cursor-shim"
        self.program(self.decoy, "decoy")
        self.installer = self.base / "installer.sh"
        self.write_installer("")
        self.env = {
            "PATH": f"{self.bin}:/usr/bin:/bin", "HOME": str(self.home),
            "TARGET_HOME": str(self.home), "TARGET_USER": "fixture",
            "ACFS_BIN_DIR": str(self.bin), "TEST_ROOT": str(self.base),
            "REPO_ROOT": str(ROOT), "TMPDIR": str(self.base),
            "XDG_STATE_HOME": str(self.base / "state"),
            "UPDATE_TEST_LIBRARY": os.environ.get("ACFS_UPDATE_TEST_LIBRARY", str(ROOT / "scripts/lib/update.sh")),
            "NO_COLOR": "1", "ACFS_INTERACTIVE": "false",
            "TEST_PIN": hashlib.sha256(self.installer.read_bytes()).hexdigest(),
        }

    def program(self, path, event):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/bash\n"
                        f"printf '{event}:%s\\n' \"$*\" >> {shlex.quote(str(self.base / 'events'))}\n"
                        "printf 'grok fixture 1.0.0\\n'\n")
        path.chmod(0o755)

    def write_installer(self, commands):
        self.installer.write_text("#!/bin/bash\nset -eu\n"
                                  f"printf 'execute\\n' >> {shlex.quote(str(self.base / 'events'))}\n"
                                  + commands + "\n")

    def install_payload(self, *, bind=True, directory=None):
        self.program(self.payload, "payload")
        if bind:
            return self.bind(self.payload, directory=directory)
        return self.payload

    def bind(self, target, *, directory=None, name="grok", relative=False):
        directory = directory or self.bin
        directory.mkdir(parents=True, exist_ok=True)
        link = directory / name
        link.symlink_to(os.path.relpath(target, directory) if relative else target)
        return link

    def switch_record(self, state="active", *, directory=None):
        directory = directory or self.home / ".cursor"
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / "grok-switch.json"
        path.write_text(json.dumps({"schema": 1, "state": state}))
        return path

    def shell(self, body, *, code=0, context="security", real_recovery=False, **env):
        prefix = {
            "security": 'set -euo pipefail\nsource "$REPO_ROOT/scripts/lib/security.sh"\n',
            "update": GROK_UPDATE_CONTEXT,
            "manifest": 'set -euo pipefail\n',
        }[context]
        if real_recovery:
            # Retain the real recovery functions before COMMON installs its
            # acquisition-order event stubs. Only these tests exercise actual
            # snapshots and restoration; all host/network boundaries stay fake.
            prefix = r'''
source "$UPDATE_TEST_LIBRARY"
grok_recovery_source="$(declare -f update_snapshot_tool_binary update_verify_tool_or_rollback)"
''' + prefix + '\neval "$grok_recovery_source"\n'
        result = subprocess.run(["/bin/bash", "--noprofile", "--norc", "-c", prefix + body],
                                env=self.env | env, text=True, capture_output=True, timeout=25)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, code, output + "\nArtifacts: " + str(self.base))
        return output

    def events(self):
        path = self.base / "events"
        return path.read_text().splitlines() if path.exists() else []

    def test_fresh_preflight_allows_install_but_does_not_claim_readiness(self):
        self.shell("acfs_grok_check preflight")
        self.shell("acfs_grok_check ready", code=1)
        self.assertEqual(self.events(), [])

    def test_bound_payload_passes_without_running_a_version_probe(self):
        self.install_payload(bind=False)
        self.bind(self.payload, relative=True)
        self.switch_record("inactive")
        self.shell("acfs_grok_check preflight; acfs_grok_check ready")
        self.assertEqual(self.events(), [])

    def test_custom_primary_bin_and_home_with_spaces_are_supported(self):
        custom_bin = self.home / "custom tools/bin"
        self.install_payload(directory=custom_bin)
        self.shell("acfs_grok_check preflight; acfs_grok_check ready",
                   ACFS_BIN_DIR=str(custom_bin), PATH=f"{custom_bin}:/usr/bin:/bin")
        self.assertEqual(self.events(), [])

    def test_unrelated_grok_is_not_executed_or_replaced(self):
        self.install_payload(bind=False)
        link = self.bind(self.decoy)
        self.shell("acfs_grok_check preflight", code=1)
        self.shell("acfs_grok_check ready", code=1)
        self.assertEqual(link.readlink(), self.decoy)
        self.assertEqual(self.events(), [])

    def test_conflicting_agent_command_blocks_before_install(self):
        self.install_payload()
        link = self.bind(self.decoy, name="agent")
        self.shell("acfs_grok_check preflight", code=1)
        self.assertEqual(link.readlink(), self.decoy)
        self.assertEqual(self.events(), [])

    def test_dangling_grok_link_is_not_treated_as_an_empty_slot(self):
        link = self.bind(self.base / "missing-cursor-shim")
        self.shell("acfs_grok_check preflight", code=1)
        self.assertEqual(link.readlink(), self.base / "missing-cursor-shim")
        self.assertEqual(self.events(), [])

    def test_payload_symlink_cannot_establish_command_identity(self):
        self.payload.parent.mkdir(parents=True)
        self.payload.symlink_to(self.decoy)
        self.bind(self.payload)
        self.shell("acfs_grok_check ready", code=1)
        self.assertEqual(self.events(), [])

    def test_payload_without_command_binding_is_not_ready(self):
        self.install_payload(bind=False)
        self.shell("acfs_grok_check ready", code=1)
        self.assertEqual(self.events(), [])

    def test_pending_cursor_switch_blocks_even_with_correct_payload_link(self):
        self.install_payload()
        self.switch_record("pending")
        self.shell("acfs_grok_check preflight", code=1)
        self.shell("acfs_grok_check ready", code=1)
        self.assertEqual(self.events(), [])

    def test_ambiguous_cursor_record_blocks_without_touching_commands(self):
        self.install_payload()
        record = self.switch_record("active")
        record.write_text('{"schema":1,"state":')
        self.shell("acfs_grok_check preflight", code=1)
        self.assertEqual(record.read_text(), '{"schema":1,"state":')
        self.assertEqual(self.events(), [])

    def test_skip_resume_and_generated_doctor_accept_bound_payload(self):
        self.install_payload()
        output = self.shell(GROK_MANIFEST_CONTEXT, context="manifest")
        for operation in ("installed", "skip", "resume", "doctor"):
            self.assertIn(f"{operation}=0", output)
        self.assertEqual(self.events(), ["payload:--version"] * 3)

    def test_skip_resume_and_generated_doctor_reject_competing_command(self):
        self.install_payload(bind=False)
        self.bind(self.decoy)
        output = self.shell(GROK_MANIFEST_CONTEXT, context="manifest")
        for operation in ("installed", "skip", "resume", "doctor"):
            self.assertIn(f"{operation}=1", output)
        self.assertEqual(self.events(), [])

    def test_explicit_generated_install_rejects_conflict_before_acquisition(self):
        self.bind(self.decoy)
        self.shell(r'''
            source "$REPO_ROOT/scripts/generated/install_agents.sh"
            run_as_target() { "$@"; }
            acfs_require_contract() { return 0; }
            acfs_generated_ensure_selection() { return 0; }
            should_run_module() { return 0; }
            acfs_module_explicitly_selected() { return 0; }
            acfs_security_init() { printf 'acquisition\n' >> "$TEST_ROOT/events"; return 1; }
            acfs_generated_install_agents_grok
        ''', code=1, context="manifest")
        self.assertEqual(self.events(), [])

    def test_updater_rejects_conflict_before_download_snapshot_or_execution(self):
        self.install_payload(bind=False)
        self.bind(self.decoy)
        output = self.shell('run_cmd "Grok CLI" update_run_verified_installer grok; result', context="update")
        self.assertIn("COUNTS=0,0,1,0", output)
        self.assertEqual(self.events(), [])

    def test_updater_same_account_honors_configured_cursor_switch(self):
        custom = self.base / "custom cursor"
        self.switch_record(directory=custom)
        self.shell("update_run_verified_installer grok", code=1, context="update",
                   CURSOR_CONFIG_DIR=str(custom))
        self.assertEqual(self.events(), [])

    def test_updater_other_account_does_not_inherit_callers_cursor_switch(self):
        custom = self.base / "caller cursor"
        self.switch_record(directory=custom)
        self.install_payload()
        self.shell("update_run_verified_installer grok", context="update",
                   CURSOR_CONFIG_DIR=str(custom), TEST_CURRENT_USER="other")
        self.assertEqual(self.events(), ["download", "snapshot", "execute", "smoke"])

    def test_updater_successful_installer_cannot_claim_competing_command(self):
        self.install_payload()
        grok = self.bin / "grok"
        self.write_installer(f"mv -- {shlex.quote(str(grok))} {shlex.quote(str(self.base / 'previous-link'))}\n"
                             f"ln -s -- {shlex.quote(str(self.decoy))} {shlex.quote(str(grok))}")
        pin = hashlib.sha256(self.installer.read_bytes()).hexdigest()
        output = self.shell('run_cmd "Grok CLI" update_run_verified_installer grok; result',
                            context="update", real_recovery=True, TEST_PIN=pin)
        self.assertIn("COUNTS=0,0,1,0", output)
        self.assertEqual(self.events(), ["download", "execute"])
        self.assertEqual(grok.readlink(), self.decoy)
        self.assertTrue(Path(str(self.payload) + ".prev").is_file())
        self.assertNotIn("ROLLED BACK", (self.base / "update.log").read_text())

    def check_payload_recovery(self, damage):
        grok = self.install_payload()
        original = self.payload.read_bytes()
        self.write_installer(damage)
        pin = hashlib.sha256(self.installer.read_bytes()).hexdigest()
        output = self.shell('run_cmd "Grok CLI" update_run_verified_installer grok; result; '
                            'update_check_grok_command ready',
                            context="update", real_recovery=True, TEST_PIN=pin)
        self.assertIn("COUNTS=0,0,1,0", output)
        self.assertEqual(self.payload.read_bytes(), original)
        self.assertTrue(os.access(self.payload, os.X_OK))
        self.assertEqual(grok.readlink(), self.payload)
        self.assertIn("ROLLED BACK", (self.base / "update.log").read_text())
        self.assertEqual(self.events(), ["download", "execute", "payload:--version"])

    def test_updater_restores_genuine_payload_that_lost_executable_mode(self):
        self.check_payload_recovery(f"chmod 0644 -- {shlex.quote(str(self.payload))}")

    def test_updater_restores_missing_payload_without_replacing_command_link(self):
        self.check_payload_recovery(f"mv -- {shlex.quote(str(self.payload))} "
                                    f"{shlex.quote(str(self.base / 'displaced-payload'))}")

    def test_updater_snapshot_does_not_follow_existing_backup_symlink(self):
        self.install_payload()
        backup = Path(str(self.payload) + ".prev")
        backup.symlink_to(self.decoy)
        original_decoy = self.decoy.read_bytes()
        output = self.shell('update_snapshot_tool_binary grok; '
                            'printf "SNAPSHOT=%s\\n" "$UPDATE_ROLLBACK_PREV_PATH"',
                            context="update", real_recovery=True)
        self.assertIn("SNAPSHOT=\n", output)
        self.assertEqual(backup.readlink(), self.decoy)
        self.assertEqual(self.decoy.read_bytes(), original_decoy)
        self.assertEqual(self.events(), [])

    def test_updater_rejects_relative_config_from_newline_caller_directory(self):
        caller_dir = self.base / "caller\nworkspace"
        caller_dir.mkdir()
        for selector in ("CURSOR_CONFIG_DIR", "XDG_CONFIG_HOME"):
            with self.subTest(selector=selector):
                self.shell('cd -- "$TEST_CALLER_DIR"\n'
                           'update_grok_target_env > "$TEST_ROOT/grok-target-env"',
                           code=1, context="update", TEST_CALLER_DIR=str(caller_dir),
                           **{selector: "config"})
                self.assertEqual((self.base / "grok-target-env").read_bytes(), b"")
        self.assertEqual(self.events(), [])

    def test_updater_rejects_raw_config_selector_with_trailing_newline(self):
        for selector in ("CURSOR_CONFIG_DIR", "XDG_CONFIG_HOME"):
            with self.subTest(selector=selector):
                self.shell('update_grok_target_env > "$TEST_ROOT/grok-target-env"',
                           code=1, context="update", **{selector: str(self.base / "config") + "\n"})
                self.assertEqual((self.base / "grok-target-env").read_bytes(), b"")
        self.assertEqual(self.events(), [])

    def test_updater_version_probe_never_executes_competing_grok(self):
        self.install_payload(bind=False)
        self.bind(self.decoy)
        output = self.shell("get_version grok", context="update")
        self.assertIn("unknown", output)
        self.assertEqual(self.events(), [])

    def test_updater_checksum_refusal_remains_distinct_from_ownership_failure(self):
        self.install_payload()
        output = self.shell('run_cmd "Grok CLI" update_run_verified_installer grok; result',
                            context="update", TEST_PIN="1" * 64)
        self.assertIn("COUNTS=0,0,1,1", output)
        self.assertEqual(self.events(), ["download", "refresh"])


class ClaudeMigrationTests(unittest.TestCase):
    """The real agent dispatcher must retain Bun Claude until native readiness.

    Acquisition is file-backed and package operations are inert executables.
    Verification, the target HOME, command bindings and recovery are real. The
    target account is the current account with an isolated passwd-home fixture;
    these cases do not claim privileged account-switching coverage.
    """

    def fixture(self, *, binding="local", action="healthy", installer_exit=0,
                security=True, hold=False, backoff=False, dry_run=False, pin=None, cleanup_exit=0):
        base = Path(tempfile.mkdtemp(prefix="acfs-claude-migration-"))
        home, caller = base / "target", base / "caller"
        for folder in (home / ".local/bin", home / ".bun/bin", caller):
            folder.mkdir(parents=True, exist_ok=True)
        package = home / ".bun/install/global/node_modules/@anthropic-ai/claude-code"
        package.mkdir(parents=True)
        old = package / "cli.js"
        old.write_text('#!/bin/bash\nprintf "Claude Code 1.0.0 (Bun)\\n"\n')
        old.chmod(0o755)
        bun_command = home / ".bun/bin/claude"
        bun_command.symlink_to(old)
        native = home / ".local/bin/claude"
        active = bun_command
        if binding == "local":
            native.symlink_to(bun_command)
            active = native
        elif binding == "custom":
            active = home / "custom/bin/claude"
            active.parent.mkdir(parents=True)
            active.symlink_to(bun_command)
        bun = home / ".bun/bin/bun"
        bun.write_text(r'''#!/bin/bash
set -eu
if [[ "$*" == 'remove -g @anthropic-ai/claude-code' ]]; then
    printf 'remove:%s:%s\n' "$HOME" "${BUN_INSTALL:-unset}" >> "$TEST_ROOT/events"
    [[ "$TEST_CLEANUP_EXIT" == 0 ]] || exit "$TEST_CLEANUP_EXIT"
    mv "$HOME/.bun/install/global/node_modules/@anthropic-ai/claude-code" "$TEST_ROOT/retired-package"
elif [[ "${1:-}" == --version ]]; then
    printf '1.4.4\n'
fi
''')
        bun.chmod(0o755)
        payload = base / "native-payload"
        payload.write_text(r'''#!/bin/bash
printf 'native-probe:%s\n' "$HOME" >> "$TEST_ROOT/events"
if [[ "$TEST_ACTION" == broken ]]; then exit 17; fi
printf 'Claude Code 2.0.0 (native)\n'
''')
        payload.chmod(0o755)
        installer = base / "installer.sh"
        installer.write_text(r'''#!/bin/bash
set -eu
printf 'install:%s\n' "$HOME" >> "$TEST_ROOT/events"
if [[ "$TEST_ACTION" != unchanged ]]; then
    mkdir -p "$HOME/.local/share/claude/versions"
    cp "$TEST_ROOT/native-payload" "$HOME/.local/share/claude/versions/2.0.0"
    if [[ -e "$HOME/.local/bin/claude" || -L "$HOME/.local/bin/claude" ]]; then
        mv "$HOME/.local/bin/claude" "$TEST_ROOT/installer-displaced-command"
    fi
    ln -s "$HOME/.local/share/claude/versions/2.0.0" "$HOME/.local/bin/claude"
fi
exit "$TEST_INSTALLER_EXIT"
''')
        digest = hashlib.sha256(installer.read_bytes()).hexdigest()
        env = {
            "PATH": "/usr/bin:/bin", "HOME": str(caller), "TARGET_HOME": str(home),
            "TEST_HOME": str(home), "TEST_ROOT": str(base), "TMPDIR": str(base),
            "ACFS_HOME": str(home / ".acfs"), "ACFS_BIN_DIR": str(active.parent if binding == "custom" else native.parent),
            "REPO_ROOT": str(ROOT), "NO_COLOR": "1", "ACFS_INTERACTIVE": "false",
            "UPDATE_TEST_LIBRARY": os.environ.get("ACFS_UPDATE_TEST_LIBRARY", str(ROOT / "scripts/lib/update.sh")),
            "TEST_PIN": digest if pin is None else pin,
            "TEST_ACTION": action, "TEST_INSTALLER_EXIT": str(installer_exit),
            "TEST_SECURITY": str(security).lower(), "TEST_HOLD": str(hold).lower(),
            "TEST_BACKOFF": str(backoff).lower(),
            "TEST_DRY_RUN": str(dry_run).lower(), "TEST_CLEANUP_EXIT": str(cleanup_exit),
        }
        script = r'''
set -euo pipefail
source "$UPDATE_TEST_LIBRARY"
source "$REPO_ROOT/scripts/lib/security.sh"
UPDATE_AGENTS=true FORCE_MODE=true DRY_RUN="$TEST_DRY_RUN"
QUIET=true VERBOSE=false ABORT_ON_FAILURE=false
UPDATE_LOG_FILE="$TEST_ROOT/update.log"
UPDATE_CMD_TIMEOUT=5 UPDATE_SMOKE_TIMEOUT=2
update_target_home() { printf '%s\n' "$TEST_HOME"; }
update_require_security() { [[ "$TEST_SECURITY" == true ]]; }
get_checksum() { printf '%s\n' "$TEST_PIN"; }
KNOWN_INSTALLERS[claude]='https://fixture.invalid/installer.sh'
update_tool_hold_details() {
    [[ "$TEST_HOLD" == true ]] || return 1
    UPDATE_LAST_HOLD_TOOL=claude UPDATE_LAST_HOLD_DETAILS='fixture hold'
}
update_tool_rollback_backoff_details() {
    [[ "$TEST_BACKOFF" == true ]] || return 1
    UPDATE_LAST_BACKOFF_TOOL=claude UPDATE_LAST_BACKOFF_DETAILS='fixture backoff'
}
update_tool_latest_release_tag() { printf 'v2.0.0\n'; }
update_private_installer_tmpdir() { return 0; }
update_create_target_readable_temp_file() { mktemp "$TEST_ROOT/stage.XXXXXX"; }
acfs_download_to_file() { cat "$TEST_ROOT/installer.sh" > "$2"; }
acfs_refresh_loaded_checksums_from_remote() { return 1; }
# Retain captures and downloaded scripts. Package retirement is a fixture move.
rm() { :; }
# Exercise the actual Claude dispatch/run_cmd path without updating other agents.
original_run_cmd="$(declare -f run_cmd)"
eval "${original_run_cmd/run_cmd ()/migration_run_cmd ()}"
run_cmd() {
    if [[ "$1" == 'Claude Code'* ]]; then migration_run_cmd "$@"; fi
}
update_binary_exists() { return 1; }
update_install_agy_locked_launchers() { return 0; }
capture_version_before() { :; }
capture_version_after() { return 1; }
update_agents
printf 'COUNTS=%s,%s,%s\n' "$SUCCESS_COUNT" "$FAIL_COUNT" "${#UPDATE_PIN_FAILURES[@]}"
printf 'ACTIVE=%s\n' "$(update_binary_path claude 2>/dev/null || true)"
'''
        result = subprocess.run(["/bin/bash", "--noprofile", "--norc", "-c", script],
                                env=env, text=True, capture_output=True, timeout=30)
        output = result.stdout + result.stderr
        (base / "result.log").write_text(output)
        self.assertEqual(result.returncode, 0, output)
        return base, home, active, output

    def assert_original_works(self, home, active):
        result = subprocess.run([str(active), "--version"], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1.0.0 (Bun)", result.stdout)
        self.assertTrue((home / ".bun/install/global/node_modules/@anthropic-ai/claude-code/cli.js").exists())

    def test_checksum_refusal_preserves_package_and_active_binding(self):
        for binding in ("local", "bun", "custom"):
            with self.subTest(binding=binding):
                base, home, active, output = self.fixture(binding=binding, pin="1" * 64)
                self.assert_original_works(home, active)
                self.assertIn("CHECKSUM BLOCKED", output)
                self.assertFalse((base / "events").exists())

    def test_missing_security_preserves_existing_installation(self):
        base, home, active, _ = self.fixture(security=False)
        self.assert_original_works(home, active)
        self.assertFalse((base / "events").exists())

    def test_hold_preserves_existing_installation(self):
        base, home, active, _ = self.fixture(hold=True)
        self.assert_original_works(home, active)
        self.assertFalse((base / "events").exists())

    def test_backoff_preserves_existing_installation(self):
        base, home, active, _ = self.fixture(backoff=True)
        self.assert_original_works(home, active)
        self.assertFalse((base / "events").exists())
        self.assertIn("BACKOFF: fixture backoff", (base / "update.log").read_text())

    def test_executed_installer_cannot_impersonate_hold_or_backoff(self):
        for installer_exit in (93, 94):
            with self.subTest(installer_exit=installer_exit):
                base, home, active, output = self.fixture(action="broken", installer_exit=installer_exit)
                self.assert_original_works(home, active)
                self.assertNotIn("remove:", (base / "events").read_text())
                self.assertIn("[fail] Claude Code", output)
                self.assertNotIn("HELD:", output)
                self.assertNotIn("BACKOFF:", output)

    def test_failed_installer_restores_command_even_after_rebinding(self):
        for binding in ("local", "bun"):
            with self.subTest(binding=binding):
                base, home, active, output = self.fixture(binding=binding, installer_exit=17)
                self.assert_original_works(home, active)
                self.assertNotIn("remove:", (base / "events").read_text())
                self.assertIn("[fail] Claude Code", output)
                if binding == "bun":
                    self.assertFalse((home / ".local/bin/claude").exists())

    def test_broken_native_restores_working_bun_command(self):
        base, home, active, _ = self.fixture(action="broken")
        self.assert_original_works(home, active)
        self.assertNotIn("remove:", (base / "events").read_text())

    def test_noop_installer_cannot_remove_bun_or_claim_native_success(self):
        base, home, active, output = self.fixture(action="unchanged")
        self.assert_original_works(home, active)
        self.assertNotIn("remove:", (base / "events").read_text())
        self.assertIn("[fail] Claude Code", output)

    def test_success_verifies_native_before_target_context_cleanup(self):
        for binding in ("local", "bun", "custom"):
            with self.subTest(binding=binding):
                base, home, active, output = self.fixture(binding=binding)
                events = (base / "events").read_text().splitlines()
                removal = f"remove:{home}:{home}/.bun"
                self.assertIn(removal, events)
                self.assertLess(events.index(f"install:{home}"), events.index(removal))
                self.assertLess(events.index(f"native-probe:{home}"), events.index(removal))
                self.assertTrue((home / ".local/bin/claude").is_file())
                if binding == "custom":
                    self.assertEqual(active.resolve(), (home / ".local/bin/claude").resolve())
                self.assertNotIn("[fail] Claude Code", output)

    def test_cleanup_failure_keeps_native_and_old_package(self):
        base, home, _, output = self.fixture(cleanup_exit=17)
        self.assertTrue((home / ".local/bin/claude").is_file())
        self.assertTrue((home / ".bun/bin/claude").is_file())
        self.assertNotIn("[fail] Claude Code", output)
        self.assertIn("retained", (base / "update.log").read_text())

    def test_dry_run_does_not_install_remove_or_rebind(self):
        base, home, active, _ = self.fixture(dry_run=True)
        self.assert_original_works(home, active)
        self.assertFalse((base / "events").exists())
        self.assertEqual(list(home.glob(".acfs-claude-migration.*")), [])


class AgentMailReleaseContractTests(unittest.TestCase):
    """Verify actual release signatures with inert metadata transport.

    These immutable bytes came from the v0.3.40 GitHub release's SHA256SUMS
    and SHA256SUMS.minisig assets. No installer or release archive is fetched
    or executed. Crypto tests use the production public key and real Minisign;
    only the explicitly named manifest-syntax test bypasses signature checks.
    Set ACFS_TEST_MINISIGN to a local Minisign executable when it is not on PATH.
    """

    INSTALLER_URL = (
        "https://raw.githubusercontent.com/Dicklesworthstone/"
        "mcp_agent_mail_rust/refs/heads/main/install.sh"
    )
    INSTALLER_SHA = "3de2d65db5405432e56e28eddfd5046226fc8d2bedf53b7fb56a003aa9e88454"
    RELEASE_BASE = "https://github.com/Dicklesworthstone/mcp_agent_mail_rust/releases/download"
    PUBLIC_KEY = "RWTQGPeLsnm9G7VFdFWkkcRi3wJK/PqsYxWC+oLNN74W9IjBxRU1Xu70"
    MANIFEST = b"""4a2dfd568feffd235b7c2fe296138849e8c3c444561ec0d00f462b1a28fd6ef9  mcp-agent-mail-x86_64-pc-windows-msvc.zip
f07fec3c5cbf1664f8ee0bef0a4913c48e6ff1bd9a970c468ebd3653228ec6ee  mcp-agent-mail-x86_64-unknown-linux-gnu.tar.xz
f8381f01927805427b8f9f40b9033c7e4a2a68853b22bc258035a2b6392b9780  mcp-agent-mail-aarch64-unknown-linux-gnu.tar.xz
cd7784066ced9e53f52d20cd5785f5c785c05cd5a2d214a3165348eb67703c56  mcp-agent-mail-x86_64-unknown-linux-musl.tar.xz
9b410ac2ee38e25754efdf246cec69ea46ab9b88ea73aac01267ad38bf73a066  mcp-agent-mail-aarch64-apple-darwin.tar.xz
62a869ddde88adb51c7b65bb8185095a8a5bf01d097c66d30d0f327e0a8247dd  mcp-agent-mail-x86_64-apple-darwin.tar.xz
"""
    SIGNATURE = b"""untrusted comment: signature from minisign secret key
RUTQGPeLsnm9G40TN8B6XjKSQlqdAjqFXVp9Q7Rgi7POtAia3YyL9y230BuY37nh1sTqrarYVCMAkwwoVkBVp2wXK8UPYPrTCgU=
trusted comment: mcp_agent_mail_rust v0.3.40 SHA256SUMS
2o2SmHUoKOAoYJvU6w2yU7Arq7ltXAzBJIg7ReMbgAfH5Sn93HW3zVWHnOOfSSB8UbgUt82lLXLUPJ9a7AXKAA==
"""
    SHELL = r'''
source "$UPDATE_TEST_LIBRARY"
VERSION="$TEST_VERSION"
UPDATE_LOG_FILE="$TEST_ROOT/update.log"
update_system_binary_path() {
    case "$1" in
        minisign)
            [[ "$TEST_MINISIGN_AVAILABLE" == true ]] || return 1
            if [[ "$TEST_MANIFEST_SYNTAX_ONLY" == true ]]; then
                printf '%s\n' "$TEST_ROOT/syntax-verifier"
            else
                printf '%s\n' "$TEST_MINISIGN"
            fi
            ;;
        uname) printf '%s\n' "$TEST_ROOT/uname" ;;
        *) _update_early_system_binary_path "$@" ;;
    esac
}
update_create_target_readable_temp_file() {
    mktemp "$TEST_ROOT/$1.XXXXXX"
}
update_tool_latest_release_tag() {
    [[ "$1" == mcp_agent_mail ]] || return 1
    printf 'latest\n' >> "$TEST_EVENTS"
    printf '%s\n' "$TEST_LATEST"
}
update_curl() {
    local url="${!#}"
    printf '%s\n' "$url" >> "$TEST_EVENTS"
    case "$url" in
        https://github.com/Dicklesworthstone/mcp_agent_mail_rust/releases/download/*/SHA256SUMS)
            [[ "$TEST_NETWORK_FAIL" != manifest ]] || return 7
            cat -- "$TEST_MANIFEST"
            ;;
        https://github.com/Dicklesworthstone/mcp_agent_mail_rust/releases/download/*/SHA256SUMS.minisig)
            [[ "$TEST_NETWORK_FAIL" != signature ]] || return 7
            cat -- "$TEST_SIGNATURE"
            ;;
        *) return 64 ;;
    esac
}
# Keep staged evidence without replacing crypto, hashing, or manifest parsing.
rm() { :; }
release=(stale-contract stale-tag stale-url stale-hash)
rc=0
update_agent_mail_release_contract release "$TEST_INSTALLER_URL" "$TEST_INSTALLER_SHA" || rc=$?
printf 'RC=%s\nCOUNT=%s\n' "$rc" "${#release[@]}"
if (( ${#release[@]} )); then printf '%s\n' "${release[@]}"; fi
'''

    @classmethod
    def setUpClass(cls):
        minisign = os.environ.get("ACFS_TEST_MINISIGN") or shutil.which("minisign")
        if not minisign or not os.access(minisign, os.X_OK):
            raise unittest.SkipTest("real Minisign required; set ACFS_TEST_MINISIGN")
        cls.minisign = str(Path(minisign).resolve())

    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="acfs-agent-mail-contract-"))
        self.calls = 0
        (self.base / "SHA256SUMS").write_bytes(self.MANIFEST)
        (self.base / "SHA256SUMS.minisig").write_bytes(self.SIGNATURE)
        uname = self.base / "uname"
        uname.write_text('#!/bin/bash\ncase "$1" in\n'
                         '-s) printf "%s\\n" "$TEST_PLATFORM" ;;\n'
                         '-m) printf "%s\\n" "$TEST_ARCH" ;;\n'
                         '*) exit 1 ;;\nesac\n')
        uname.chmod(0o755)
        syntax_verifier = self.base / "syntax-verifier"
        syntax_verifier.write_text("#!/bin/bash\n# Syntax test boundary only.\nexit 0\n")
        syntax_verifier.chmod(0o755)
        self.env = {
            "PATH": "/usr/bin:/bin", "HOME": str(self.base),
            "TARGET_HOME": str(self.base), "TEST_ROOT": str(self.base),
            "UPDATE_TEST_LIBRARY": os.environ.get("ACFS_UPDATE_TEST_LIBRARY", str(ROOT / "scripts/lib/update.sh")),
            "NO_COLOR": "1", "ACFS_INTERACTIVE": "false",
            "TEST_INSTALLER_URL": self.INSTALLER_URL, "TEST_INSTALLER_SHA": self.INSTALLER_SHA,
            "TEST_MANIFEST": str(self.base / "SHA256SUMS"),
            "TEST_SIGNATURE": str(self.base / "SHA256SUMS.minisig"),
            "TEST_VERSION": "v0.3.40", "TEST_LATEST": "v0.3.40",
            "TEST_PLATFORM": "Linux", "TEST_ARCH": "x86_64",
            "TEST_NETWORK_FAIL": "", "TEST_MINISIGN": self.minisign,
            "TEST_MINISIGN_AVAILABLE": "true", "TEST_MANIFEST_SYNTAX_ONLY": "false",
        }

    def contract(self, **env):
        self.calls += 1
        events_path = self.base / f"events-{self.calls}"
        result = subprocess.run(
            ["/bin/bash", "--noprofile", "--norc", "-c", self.SHELL],
            env=self.env | {"TEST_EVENTS": str(events_path)} | env,
            text=True, capture_output=True, timeout=20,
        )
        (self.base / f"result-{self.calls}.log").write_text(result.stdout + result.stderr)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        lines = result.stdout.splitlines()
        self.assertGreaterEqual(len(lines), 2, result.stdout + result.stderr)
        self.assertTrue(lines[0].startswith("RC="), result.stdout)
        self.assertTrue(lines[1].startswith("COUNT="), result.stdout)
        status, count = int(lines[0][3:]), int(lines[1][6:])
        values = lines[2:]
        self.assertEqual(len(values), count, result.stdout)
        events = events_path.read_text().splitlines() if events_path.exists() else []
        if status:
            # A failed lookup must clear an earlier caller-owned contract.
            self.assertEqual(values, [], result.stdout)
        else:
            self.assertEqual(count, 4, result.stdout)
        return status, values, events

    def variant(self, name, content):
        path = self.base / name
        path.write_bytes(content)
        return str(path)

    def test_real_signed_release_binds_installer_platform_and_exact_metadata(self):
        self.assertEqual(hashlib.sha256(self.MANIFEST).hexdigest(),
                         "c9ee4661ed6618273d5e3eadb5e5c3f59bf206c0d4cdda7c3c7949452d6c738e")
        self.assertEqual(hashlib.sha256(self.SIGNATURE).hexdigest(),
                         "1b8b99469499d056caacaa4c9345e269041cc4089de4b8608f045d8c91ad68e3")
        for arch, target, digest in (
            ("x86_64", "x86_64-unknown-linux-musl", "cd7784066ced9e53f52d20cd5785f5c785c05cd5a2d214a3165348eb67703c56"),
            ("aarch64", "aarch64-unknown-linux-gnu", "f8381f01927805427b8f9f40b9033c7e4a2a68853b22bc258035a2b6392b9780"),
        ):
            with self.subTest(arch=arch):
                status, values, events = self.contract(TEST_ARCH=arch)
                self.assertEqual(status, 0)
                url = f"{self.RELEASE_BASE}/v0.3.40/mcp-agent-mail-{target}.tar.xz"
                self.assertEqual(values[1:], ["v0.3.40", url, digest])
                record = json.loads(values[0])
                self.assertEqual(record["adapter"], "agent-mail-minisign-v2")
                self.assertEqual(record["installer"], {"url": self.INSTALLER_URL, "sha256": self.INSTALLER_SHA})
                self.assertEqual(record["release"], {
                    "tag": "v0.3.40", "artifact": url, "sha256": digest,
                    "manifest": hashlib.sha256(self.MANIFEST).hexdigest(),
                    "signature": hashlib.sha256(self.SIGNATURE).hexdigest(), "key": self.PUBLIC_KEY,
                })
                self.assertEqual(record["platform"], f"Linux/{arch}")
                self.assertEqual(record["options"], ["--yes", "--no-service", "--force", "--offline", "AM_INSTALL_SKIP_MCP_SETUP=1",
                                                     "AM_INSTALL_SKIP_REMOTE_HTTP_READINESS=1"])
                self.assertEqual(events, [f"{self.RELEASE_BASE}/v0.3.40/SHA256SUMS",
                                          f"{self.RELEASE_BASE}/v0.3.40/SHA256SUMS.minisig"])

    def test_identical_signed_metadata_produces_identical_contract_on_repeated_runs(self):
        first = self.contract()
        second = self.contract()
        self.assertEqual(first[0], 0)
        self.assertEqual(second, first)

    def test_version_without_prefix_and_latest_resolution_select_the_signed_tag(self):
        for version in ("0.3.40", ""):
            with self.subTest(version=version):
                status, values, events = self.contract(TEST_VERSION=version)
                self.assertEqual(status, 0)
                self.assertEqual(values[1], "v0.3.40")
                self.assertEqual(events.count("latest"), 0 if version else 1)

    def test_real_verifier_rejects_changed_manifest_signature_and_trusted_comment(self):
        variants = (
            ("manifest", self.MANIFEST.replace(b"cd7784", b"ad7784", 1), "TEST_MANIFEST"),
            ("signature", self.SIGNATURE.replace(b"2o2SmH", b"3o2SmH", 1), "TEST_SIGNATURE"),
            ("truncated", b"\n".join(self.SIGNATURE.splitlines()[:3]) + b"\n", "TEST_SIGNATURE"),
            ("other-product", self.SIGNATURE.replace(b"mcp_agent_mail_rust", b"other_product"), "TEST_SIGNATURE"),
            ("changed-tag", self.SIGNATURE.replace(b"v0.3.40", b"v0.3.41"), "TEST_SIGNATURE"),
        )
        for name, content, selector in variants:
            with self.subTest(name=name):
                status, _, events = self.contract(**{selector: self.variant(name, content)})
                self.assertNotEqual(status, 0)
                self.assertEqual(len(events), 2)

    def test_authentic_signature_cannot_be_replayed_as_another_requested_release(self):
        for version in ("v0.3.41", "v0.4.0", "v0.3.40-rc.1"):
            with self.subTest(version=version):
                status, _, events = self.contract(TEST_VERSION=version)
                self.assertNotEqual(status, 0)
                self.assertEqual(events, [f"{self.RELEASE_BASE}/{version}/SHA256SUMS",
                                          f"{self.RELEASE_BASE}/{version}/SHA256SUMS.minisig"])

    def test_missing_empty_or_unavailable_metadata_never_returns_a_contract(self):
        empty = self.variant("empty", b"")
        for name, overrides, fetch_count in (
            ("manifest-network", {"TEST_NETWORK_FAIL": "manifest"}, 1),
            ("signature-network", {"TEST_NETWORK_FAIL": "signature"}, 2),
            ("manifest-missing", {"TEST_MANIFEST": str(self.base / "missing-manifest")}, 1),
            ("signature-missing", {"TEST_SIGNATURE": str(self.base / "missing-signature")}, 2),
            ("manifest-empty", {"TEST_MANIFEST": empty}, 2),
            ("signature-empty", {"TEST_SIGNATURE": empty}, 2),
        ):
            with self.subTest(name=name):
                status, _, events = self.contract(**overrides)
                self.assertNotEqual(status, 0)
                self.assertEqual(len(events), fetch_count)

    def test_unreviewed_pin_or_installer_url_declines_before_release_lookup(self):
        for overrides in (
            {"TEST_INSTALLER_SHA": ""}, {"TEST_INSTALLER_SHA": "f" * 64},
            {"TEST_INSTALLER_URL": self.INSTALLER_URL.replace("/refs/heads/main/", "/main/")},
            {"TEST_INSTALLER_URL": "https://example.invalid/installer.sh"},
        ):
            with self.subTest(overrides=overrides):
                status, _, events = self.contract(TEST_VERSION="", **overrides)
                self.assertNotEqual(status, 0)
                self.assertEqual(events, [])

    def test_offline_and_custom_installer_contracts_decline_before_metadata_fetch(self):
        overrides = {
            "OWNER": "other-owner", "REPO": "other-repository",
            "ARTIFACT_URL": "https://example.invalid/archive", "CHECKSUM": "a" * 64,
            "CHECKSUM_URL": "https://example.invalid/checksum",
            "SIGSTORE_BUNDLE_URL": "https://example.invalid/bundle", "DEST": "/custom/dest",
            "ACFS_VERIFIED_INSTALLER_CACHE": "/custom/cache", "AM_INSTALL_LOCK_FILE": "/custom/lock",
            "AM_LINK_DIR": "/custom/bin", "PYTHON_MIGRATION_MARKER": "/custom/migrated",
            "PYTHON_MIGRATION_SKIP_MARKER": "/custom/skipped", "AM_OFFLINE": "1",
        }
        for variable, value in overrides.items():
            with self.subTest(variable=variable):
                status, _, events = self.contract(TEST_VERSION="", **{variable: value})
                self.assertNotEqual(status, 0)
                self.assertEqual(events, [])

    def test_legacy_or_malformed_release_versions_keep_the_upstream_verification_path(self):
        for version in ("v0.3.30", "v0.2.99", "../../release", "v0.3.40/extra", "v0.3.40\n", "v1234567.1.1"):
            with self.subTest(version=version):
                status, _, events = self.contract(TEST_VERSION=version)
                self.assertNotEqual(status, 0)
                self.assertEqual(events, [])

    def test_missing_minisign_or_unsupported_platform_declines_without_metadata(self):
        for overrides in ({"TEST_MINISIGN_AVAILABLE": "false"},
                          {"TEST_PLATFORM": "Darwin"}, {"TEST_ARCH": "riscv64"}):
            with self.subTest(overrides=overrides):
                status, _, events = self.contract(**overrides)
                self.assertNotEqual(status, 0)
                self.assertEqual(events, [])

    def test_manifest_syntax_rejects_ambiguous_assets_with_explicit_verifier_stub(self):
        """Parser coverage only; mutated manifests are not claimed authentic."""
        asset = b"mcp-agent-mail-x86_64-unknown-linux-musl.tar.xz"
        line = next(line for line in self.MANIFEST.splitlines() if line.endswith(asset))
        malformed = (
            self.MANIFEST + line + b"\n",
            self.MANIFEST + line.replace(asset, b"./" + asset) + b"\n",
            self.MANIFEST + line.replace(asset, b"*" + asset) + b"\n",
            self.MANIFEST.replace(line, line + b" extra-field"),
            self.MANIFEST.replace(line, b"g" * 64 + b"  " + asset),
            self.MANIFEST.replace(line, b"a" * 63 + b"  " + asset),
            b"a" * 64 + b"  unrelated-archive.tar.xz\n",
        )
        for index, content in enumerate(malformed):
            with self.subTest(case=index):
                status, _, _ = self.contract(TEST_MANIFEST_SYNTAX_ONLY="true",
                                             TEST_MANIFEST=self.variant(f"syntax-{index}", content))
                self.assertNotEqual(status, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
