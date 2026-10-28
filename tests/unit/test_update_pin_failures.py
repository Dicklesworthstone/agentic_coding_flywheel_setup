"""Exercise real updater/verification functions with inert downloaded scripts.

Network acquisition and installed-tool discovery are fixtures. Pin-classification
tests stub binary snapshots; rollback tests use real snapshots and filesystem
restoration. SHA256 verification, metadata recovery, shell execution, background
status propagation, retry dispatch and final summaries run the repository code.
No system packages, real agent installations or external services are touched.
"""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
