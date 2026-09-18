#!/usr/bin/env python3
"""Exercise the complete resume entry point with host mutations redirected to fixtures.

Real Python/JSON, Bash, jq, file checks and flock run. Only OS identity, systemd,
package/reboot commands and the state-library callbacks are fixture services.
Temporary evidence is retained; this test never changes the real resume state.
"""
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(os.environ.get("ACFS_RESUME_TEST_SOURCE", ROOT / "scripts/lib/upgrade_resume.sh"))


def checkpoint(stage="awaiting_reboot", enabled=True):
    return {"schema_version": 3, "target_user": "ubuntu", "mode": "vibe",
            "ubuntu_upgrade": {"enabled": enabled, "current_stage": stage,
                               "target_version": "26.04", "completed_upgrades": []}}


class ResumeFixture:
    def __init__(self, data=None, release="26.04", mutate=None):
        self.root = Path(tempfile.mkdtemp(prefix="acfs-resume-checkpoint-"))
        self.resume = self.root / "recovery"
        self.lib = self.resume / "lib"
        self.lib.mkdir(parents=True, mode=0o700)
        self.resume.chmod(0o700)
        self.state = self.resume / "state.json"
        self.state.write_text(json.dumps(checkpoint() if data is None else data))
        self.state.chmod(0o600)
        self.trace = self.root / "trace"
        self.log = self.root / "logs" / "upgrade_resume.log"
        self.motd = self.root / "motd"
        self.os_release = self.root / "os-release"
        self.os_release.write_text(f'ID=ubuntu\nVERSION_ID="{release}"\n')
        self.mutation = self.root / "mutation.json"
        if mutate is not None:
            self.mutation.write_text(json.dumps(mutate))
        self.write("continue_context.env", "CONTINUE_HOME=/root\nCONTINUE_TARGET_USER=ubuntu\n"
                   "CONTINUE_TARGET_HOME=/home/ubuntu\nCONTINUE_ACFS_REF=" + "a" * 40 + "\n"
                   "CONTINUE_INSTALL_ARGS=(--yes --mode vibe --skip-ubuntu-upgrade)\n")
        self.write("continue_install.sh", "#!/bin/bash\nINSTALL_ARGS=(--yes --mode vibe --skip-ubuntu-upgrade)\nexit 0\n")
        self.write("lib/state.sh", r'''
printf 'source-state\n' >> "$TRACE"
state_upgrade_resumed() { printf 'state-resumed\n' >> "$TRACE"; }
state_upgrade_start() { printf 'state-start\n' >> "$TRACE"; }
state_upgrade_complete() { printf 'state-hop-complete\n' >> "$TRACE"; }
state_upgrade_needs_reboot() { printf 'state-reboot\n' >> "$TRACE"; }
state_upgrade_set_error() { printf 'state-error\n' >> "$TRACE"; }
state_update_with_args() { printf 'state-update\n' >> "$TRACE"; return 1; }
''')
        self.write("lib/ubuntu_upgrade.sh", r'''
printf 'source-upgrade\n' >> "$TRACE"
upgrade_acquire_lock() {
    exec {fixture_lock}>"${ACFS_RESUME_DIR}/upgrade.lock"
    flock -n "$fixture_lock" || return 1
    printf 'lock\n' >> "$TRACE"
    if [[ -f "$MUTATION" ]]; then
        cat "$MUTATION" > "$ACFS_STATE_FILE"
    fi
}
upgrade_release_lock() { printf 'unlock\n' >> "$TRACE"; flock -u "$fixture_lock"; }
ubuntu_validate_upgrade_versions() {
    case "$1:$2" in 2204:2604|2404:2604|2510:2604|2604:2604) return 0;; *) return 1;; esac
}
ubuntu_get_version_string() { printf '%s\n' "$FIXTURE_RELEASE"; }
ubuntu_calculate_upgrade_path() { printf '26.04\n'; }
ubuntu_check_apt_state() { return 0; }
ubuntu_check_reboot_required() { return 0; }
ubuntu_configure_release_prompt() { printf 'configure-release\n' >> "$TRACE"; }
ubuntu_preflight_checks() { printf 'preflight\n' >> "$TRACE"; return 1; }
ubuntu_do_upgrade() { printf 'UPGRADE\n' >> "$TRACE"; return 1; }
upgrade_update_motd() { printf 'motd-progress\n' >> "$TRACE"; }
dpkg() { printf 'audit\n' >> "$TRACE"; return 0; }
shutdown() { printf 'REBOOT\n' >> "$TRACE"; return 1; }
systemctl() {
    printf 'systemctl:%s\n' "$*" >> "$TRACE"
    case "$1" in is-active) return 3;; show) printf 'inactive\n';; esac
    return 0
}
systemd-run() { printf 'CONTINUE:%s\n' "$*" >> "$TRACE"; return 0; }
''')
        # Change only fixed host locations in this throwaway runner, not the
        # repository source or the implementation's command-search policy.
        text = SOURCE.read_text()
        replacements = {"/var/lib/acfs": str(self.resume),
                        "/var/log/acfs/upgrade_resume.log": str(self.log),
                        "/etc/os-release": str(self.os_release),
                        "/etc/update-motd.d/00-acfs-upgrade": str(self.motd)}
        for old, new in replacements.items():
            text = text.replace(old, new)
        self.runner = self.root / "upgrade_resume.sh"
        self.runner.write_text(text)
        self.runner.chmod(0o700)

    def write(self, name, text):
        target = self.resume / name
        target.write_text(text)
        target.chmod(0o600)

    def run(self, *args):
        return subprocess.run(["/bin/bash", "-p", str(self.runner), *args],
                              env={"PATH": "/usr/bin:/bin", "HOME": "/root",
                                   "TRACE": str(self.trace), "MUTATION": str(self.mutation),
                                   "FIXTURE_RELEASE": self.os_release.read_text().split('"')[1]},
                              text=True, capture_output=True, timeout=10)

    def events(self):
        return self.trace.read_text() if self.trace.exists() else ""


@unittest.skipUnless(os.geteuid() == 0, "Root-owned recovery fixtures require root; no host writes occur")
class CheckpointAuthorityTests(unittest.TestCase):
    def assert_refused_before_code(self, data=None, raw=None):
        fixture = ResumeFixture(data)
        if raw is not None:
            fixture.state.write_bytes(raw)
        before = fixture.state.read_bytes()
        result = fixture.run()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(fixture.events(), "", "Recovery code ran before checkpoint validation")
        self.assertFalse(fixture.log.exists(), "Invalid checkpoint created a log")
        self.assertFalse(fixture.motd.exists(), "Invalid checkpoint changed MOTD")
        self.assertEqual(fixture.state.read_bytes(), before)
        return result

    def test_valid_enabled_checkpoint_reaches_guarded_continuation(self):
        fixture = ResumeFixture()
        result = fixture.run()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("CONTINUE:", fixture.events())
        self.assertIn("/bin/bash -p", fixture.events())
        self.assertEqual(json.loads(fixture.state.read_text())["ubuntu_upgrade"]["current_stage"], "completed")
        self.assertNotIn("UPGRADE", fixture.events())
        self.assertNotIn("REBOOT", fixture.events())

    def test_disabled_checkpoint_does_not_resume(self):
        self.assert_refused_before_code(checkpoint(enabled=False))

    def test_not_started_checkpoint_does_not_resume(self):
        self.assert_refused_before_code(checkpoint("not_started"))

    def test_unknown_stages_do_not_resume(self):
        for stage in ("complete", "unknown", "", None, 7, ["completed"]):
            with self.subTest(stage=stage):
                self.assert_refused_before_code(checkpoint(stage))

    def test_enabled_requires_a_boolean(self):
        for enabled in ("true", "false", 0, 1, None, [], {}):
            with self.subTest(enabled=enabled):
                self.assert_refused_before_code(checkpoint(enabled=enabled))

    def test_missing_authority_fields_fail_closed(self):
        for key in ("enabled", "current_stage", "target_version"):
            data = checkpoint()
            del data["ubuntu_upgrade"][key]
            with self.subTest(key=key):
                self.assert_refused_before_code(data)

    def test_schema_is_explicitly_versioned(self):
        for schema in (None, 2, 4, "3", 3.0, True):
            data = checkpoint()
            if schema is None:
                del data["schema_version"]
            else:
                data["schema_version"] = schema
            with self.subTest(schema=schema):
                self.assert_refused_before_code(data)

    def test_invalid_json_utf8_bom_and_multiple_documents(self):
        good = json.dumps(checkpoint()).encode()
        for raw in (b"", b"{broken", b"\xff", b"\xef\xbb\xbf" + good,
                    good + b"\n" + good, b"[]", b"null"):
            with self.subTest(raw=raw[:15]):
                self.assert_refused_before_code(raw=raw)

    def test_duplicate_authority_cannot_hide_disabled_or_failed_state(self):
        good = json.dumps(checkpoint())
        for raw in (good.replace('"enabled": true', '"enabled": false, "enabled": true'),
                    good.replace('"enabled": true', '"enabled": false, "\\u0065nabled": true'),
                    good.replace('"current_stage": "awaiting_reboot"',
                                 '"current_stage": "invalid", "current_stage": "awaiting_reboot"'),
                    good.replace('"schema_version": 3', '"schema_version": 99, "schema_version": 3')):
            with self.subTest(raw=raw[:90]):
                self.assert_refused_before_code(raw=raw.encode())

    def test_rejects_nonfinite_and_excessive_depth(self):
        for value in ("NaN", "Infinity", "1e999", "[" * 55 + "0" + "]" * 55):
            raw = json.dumps(checkpoint())[:-1] + ', "extra": ' + value + '}'
            with self.subTest(value=value[:12]):
                self.assert_refused_before_code(raw=raw.encode())

    def test_rejects_excessive_nodes_and_bytes(self):
        data = checkpoint()
        data["extra"] = [0] * 17000
        self.assert_refused_before_code(data)
        data["extra"] = "x" * 65536
        self.assert_refused_before_code(data)

    def test_errors_do_not_echo_checkpoint_contents(self):
        raw = json.dumps(checkpoint()).replace('"enabled": true', '"enabled": "PRIVATE_VALUE_DO_NOT_LOG"')
        result = self.assert_refused_before_code(raw=raw.encode())
        self.assertNotIn("PRIVATE_VALUE", result.stdout + result.stderr)

    def test_known_resume_stages_still_allow_live_target_check(self):
        for stage in ("initializing", "upgrading", "awaiting_reboot", "pre_upgrade_reboot",
                      "resumed", "step_complete", "error", "completed"):
            with self.subTest(stage=stage):
                fixture = ResumeFixture(checkpoint(stage))
                result = fixture.run()
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("CONTINUE:", fixture.events())

    def test_completed_checkpoint_cannot_replay_upgrade_below_target(self):
        fixture = ResumeFixture(checkpoint("completed"), release="24.04")
        before = fixture.state.read_bytes()
        result = fixture.run()
        self.assertNotEqual(result.returncode, 0)
        events = fixture.events()
        for forbidden in ("configure-release", "state-resumed", "state-start", "UPGRADE", "REBOOT", "CONTINUE:"):
            self.assertNotIn(forbidden, events)
        self.assertEqual(fixture.state.read_bytes(), before)
        self.assertFalse(fixture.motd.exists())

    def test_same_target_changes_are_rejected_under_lock(self):
        mutations = []
        for key, value in (("enabled", False), ("current_stage", "error"),
                           ("last_error", "another attempt failed"), ("completed_upgrades", ["24.04"])):
            data = checkpoint()
            data["ubuntu_upgrade"][key] = value
            mutations.append(data)
        changed_account = checkpoint()
        changed_account["target_user"] = "other"
        mutations.append(changed_account)
        for data in mutations:
            with self.subTest(data=data):
                fixture = ResumeFixture(mutate=data)
                result = fixture.run()
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("lock\n", fixture.events())
                self.assertIn("unlock\n", fixture.events())
                for forbidden in ("systemctl:", "CONTINUE:", "audit", "state-", "configure-release"):
                    # Sourced fixture names are not state writes.
                    self.assertNotIn(forbidden, fixture.events())
                self.assertEqual(json.loads(fixture.state.read_text()), data)
                self.assertFalse(fixture.motd.exists())

    def test_whitespace_and_object_order_do_not_create_false_checkpoint_changes(self):
        data = checkpoint()
        reordered = dict(reversed(list(data.items())))
        reordered["ubuntu_upgrade"] = dict(reversed(list(data["ubuntu_upgrade"].items())))
        fixture = ResumeFixture(mutate=reordered)
        result = fixture.run()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_corruption_while_acquiring_lock_is_not_treated_as_a_new_run(self):
        fixture = ResumeFixture()
        fixture.mutation.write_text("{broken")
        result = fixture.run()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(fixture.state.read_text(), "{broken")
        self.assertNotIn("systemctl:", fixture.events())
        self.assertNotIn("CONTINUE:", fixture.events())

    def test_existing_file_safety_guards_remain_active(self):
        for mutation in ("symlink", "hardlink", "world-writable"):
            fixture = ResumeFixture()
            original = fixture.state.read_bytes()
            if mutation == "symlink":
                saved = fixture.resume / "original.json"
                fixture.state.rename(saved)
                fixture.state.symlink_to(saved)
            elif mutation == "hardlink":
                os.link(fixture.state, fixture.resume / "extra-link.json")
            else:
                fixture.state.chmod(0o666)
            with self.subTest(mutation=mutation):
                result = fixture.run()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(fixture.events(), "")
                self.assertEqual(fixture.state.read_bytes(), original)

    def test_help_and_argument_errors_remain_inert(self):
        fixture = ResumeFixture()
        self.assertEqual(fixture.run("--help").returncode, 0)
        self.assertEqual(fixture.run("--unknown").returncode, 2)
        self.assertEqual(fixture.events(), "")
        self.assertFalse(fixture.log.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
