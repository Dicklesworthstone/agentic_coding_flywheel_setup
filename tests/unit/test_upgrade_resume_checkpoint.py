#!/usr/bin/env python3
"""Exercise the complete resume entry point with host mutations redirected to fixtures.

Real Python/JSON, Bash, jq, file checks and flock run. The interactive cases
also exercise the continuation generator, state library and a controlling PTY.
OS identity, systemd, the installer payload and package/reboot operations use
disposable fixtures. No test changes the real resume state.
"""
import copy
import fcntl
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import time
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

    def process(self, *args, tty=False):
        command = ["/bin/bash", "-p", str(self.runner), *args]
        if tty:
            command = ["script", "--quiet", "--return", "--command", shlex.join(command), "/dev/null"]
        return subprocess.Popen(command, env={
            "PATH": "/usr/bin:/bin", "HOME": "/root",
            "TRACE": str(self.trace), "MUTATION": str(self.mutation),
            "FIXTURE_RELEASE": self.os_release.read_text().split('"')[1],
        }, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            start_new_session=True, text=True)

    def run(self, *args, tty=False):
        with self.process(*args, tty=tty) as process:
            try:
                output, error = process.communicate(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()
                raise
            return subprocess.CompletedProcess(process.args, process.returncode, output, error)

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


@unittest.skipUnless(os.geteuid() == 0, "Root-owned recovery fixtures require root")
class InteractiveHandoffTests(unittest.TestCase):
    def setUp(self):
        self.fx = ResumeFixture()
        # Exercise real state writes and the actual continuation generator.
        self.fx.write("lib/state.sh", (ROOT / "scripts/lib/state.sh").read_text())
        self.source = self.fx.root / "source with spaces"
        libs = self.source / "scripts/lib"
        libs.mkdir(parents=True)
        (libs / "upgrade_resume.sh").write_text("#!/bin/bash\nexit 0\n")
        templates = self.source / "scripts/templates"
        templates.mkdir()
        (templates / "acfs-upgrade-resume.service").write_text("[Unit]\n")
        units = self.fx.root / "units"
        units.mkdir()
        self.producer = self.fx.root / "producer.sh"
        self.producer.write_text((ROOT / "scripts/lib/ubuntu_upgrade.sh").read_text()
                                 .replace("/etc/systemd/system", str(units))
                                 .replace("/var/log/acfs", str(self.fx.root / "logs")))
        # Use the production flock descriptor, lifetime and PID record. Replace
        # package, distro and reboot callbacks only; lock failure must be real.
        lock_functions = subprocess.check_output([
            "/bin/bash", "-p", "-c",
            'source "$1" && declare -f upgrade_acquire_lock upgrade_release_lock',
            "locks", str(self.producer),
        ], text=True)
        with (self.fx.lib / "ubuntu_upgrade.sh").open("a") as stream:
            stream.write('\nACFS_UPGRADE_LOCK="$ACFS_RESUME_DIR/upgrade.lock"\n' + lock_functions + "\n")
        self.payload("completed")

    def generate(self, *args):
        shell = r'''
set -eu
source "$1"
ACFS_RESUME_DIR="$2"
ACFS_STATE_FILE="$2/state.json"
ACFS_UPGRADE_INSTALL_STATE_FILE="$2/installation.json"
ACFS_HOME="$2/target-acfs"
ACFS_REF=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
TARGET_USER=root
systemctl() { :; }
source_dir="$3"; shift 3
upgrade_setup_infrastructure "$source_dir" "$@"
'''
        subprocess.run(["/bin/bash", "-p", "-c", shell, "generate", str(self.producer),
                        str(self.fx.resume), str(self.source), *args],
                       env={"PATH": "/usr/bin:/bin", "HOME": "/root"},
                       check=True, text=True, capture_output=True, timeout=15)

    def payload(self, receipt, *, status=0, crash=False, hold=False):
        # This replaces only install.sh. The real generated continuation still
        # replays its frozen arguments and account/checkpoint environment.
        lines = ["#!/bin/bash", "set -eu", "root=" + shlex.quote(str(self.fx.resume)),
                 '[[ -t 0 && -t 1 ]] && : < /dev/tty || exit 81',
                 'printf "%s\\n" "$ACFS_INSTALL_ATTEMPT" >> "$root/launches"',
                 'printf "%s\\n" "$@" > "$root/replayed-args"',
                 'printf "%s\\n" "$ACFS_STATE_FILE" > "$root/replayed-checkpoint"']
        if receipt is not None:
            lines.append("printf '%s\\n' " + shlex.quote(receipt) +
                         ' > "$root/$ACFS_INSTALL_ATTEMPT/outcome"')
        if crash:
            # The real dispatcher recorded its own PID in the fixture lock.
            # Never target a process discovered by name.
            lines += ["trap '' HUP", 'kill -KILL "$(cat "$root/upgrade.lock")"']
        if hold:
            lines += ['touch "$root/entered"', 'for ((i=0; i<150; i++)); do',
                      '    [[ ! -e "$root/release" ]] || break', '    sleep .1', 'done']
        (self.source / "install.sh").write_text("\n".join(lines + [f"exit {status}", ""]))

    def launches(self):
        path = self.fx.resume / "launches"
        return path.read_text().splitlines() if path.exists() else []

    def handoff(self):
        return json.loads(self.fx.state.read_text())["ubuntu_upgrade"].get("install_handoff", {})

    def arm(self, *args):
        self.generate(*(args or ("--mode", "safe", "--only", "agents.codex")))
        result = self.fx.run()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.handoff().get("status"), "awaiting", result.stdout + result.stderr)
        self.assertNotIn("CONTINUE:", self.fx.events())
        self.assertEqual(self.launches(), [])

    def manual(self):
        return self.fx.run("--continue-install", tty=True)

    def test_manual_command_before_the_final_hop_never_starts_a_release(self):
        self.generate("--mode", "safe")
        self.fx.os_release.write_text('ID=ubuntu\nVERSION_ID="24.04"\n')
        before = self.fx.state.read_bytes()
        self.assertNotEqual(self.manual().returncode, 0)
        self.assertEqual(self.fx.state.read_bytes(), before)
        self.assertEqual(self.launches(), [])
        for event in ("configure-release", "UPGRADE", "REBOOT", "systemctl:", "CONTINUE:"):
            self.assertNotIn(event, self.fx.events())

    def test_no_tty_cannot_consume_prompt_or_capture_attempt(self):
        self.arm()
        before = self.fx.state.read_bytes()
        self.assertNotEqual(self.fx.run("--continue-install").returncode, 0)
        self.assertEqual(self.fx.state.read_bytes(), before)
        self.assertEqual(self.launches(), [])
        self.fx.run()
        self.assertEqual(self.handoff()["status"], "awaiting")
        self.assertNotIn("CONTINUE:", self.fx.events())

    def test_saved_yes_uses_unit_and_manual_entry_cannot_take_it_over(self):
        self.generate("--yes", "--mode", "safe")
        self.assertEqual(self.fx.run().returncode, 0)
        self.assertEqual(self.fx.events().count("CONTINUE:"), 1)
        self.manual()
        self.assertEqual(self.launches(), [])
        self.assertEqual(self.fx.events().count("CONTINUE:"), 1)

    def test_conflicting_policy_cannot_claim_or_launch(self):
        self.generate("--yes", "--mode", "safe")
        context = self.fx.resume / "continue_context.env"
        with context.open("a") as stream:
            stream.write("CONTINUE_REQUIRES_TTY=true\n")
        result = self.fx.run()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.handoff(), {})
        self.assertEqual(self.launches(), [])
        self.assertNotIn("CONTINUE:", self.fx.events())

    def test_completed_upgrade_with_new_review_policy_recovers_missing_claim(self):
        self.generate("--mode", "safe")
        context = self.fx.resume / "continue_context.env"
        lines = [line for line in context.read_text().splitlines()
                 if not line.startswith("CONTINUE_REQUIRES_TTY=")]
        context.write_text("\n".join(lines + ["CONTINUE_REQUIRES_TTY=true", ""]))
        self.fx.state.write_text(json.dumps(checkpoint("completed")))
        result = self.manual()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.handoff()["status"], "completed")
        self.assertEqual(len(self.launches()), 1)
        self.manual()
        self.assertEqual(len(self.launches()), 1)

    def test_completed_legacy_checkpoint_does_not_replay_an_unknown_install(self):
        self.generate("--mode", "safe")
        context = self.fx.resume / "continue_context.env"
        lines = [line for line in context.read_text().splitlines()
                 if not line.startswith("CONTINUE_REQUIRES_TTY=")]
        context.write_text("\n".join(lines + [""]))
        self.fx.state.write_text(json.dumps(checkpoint("completed")))
        self.manual()
        self.fx.run()
        self.assertEqual(self.launches(), [])
        self.assertEqual(self.handoff(), {})
        self.assertNotIn("CONTINUE:", self.fx.events())

    def test_success_replays_exact_options_and_cannot_run_twice(self):
        self.arm("--mode", "safe", "--only", "agents.codex")
        result = self.manual()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.handoff()["status"], "completed")
        self.assertEqual((self.fx.resume / "replayed-args").read_text().splitlines(),
                         ["--mode", "safe", "--only", "agents.codex", "--skip-ubuntu-upgrade"])
        self.assertEqual((self.fx.resume / "replayed-checkpoint").read_text().strip(),
                         str(self.fx.resume / "installation.json"))
        ids = self.launches()
        self.assertEqual(len(ids), 1)
        self.assertRegex(ids[0], r"^install-attempt\.[a-zA-Z0-9]{10}$")
        self.manual()
        self.fx.run()
        self.assertEqual(self.launches(), ids)
        self.assertNotIn("CONTINUE:", self.fx.events())

    def test_decline_and_failure_retry_with_a_fresh_attempt(self):
        self.arm()
        for receipt, code, expected in (("declined", 0, "declined"), (None, 17, "failed"),
                                        ("completed", 0, "completed")):
            with self.subTest(expected=expected, code=code):
                self.payload(receipt, status=code)
                self.manual()
                self.assertEqual(self.handoff()["status"], expected)
                ids = self.launches()
                self.fx.run()
                self.assertEqual(self.launches(), ids)
        self.assertEqual(len(set(self.launches())), 3)
        self.assertNotIn("CONTINUE:", self.fx.events())

    def test_legacy_success_without_receipt_requires_operator_review(self):
        self.arm()
        self.payload(None)
        self.manual()
        self.assertEqual(self.handoff()["status"], "unconfirmed")
        self.manual()
        self.fx.run()
        self.assertEqual(self.handoff()["status"], "unconfirmed")
        self.assertEqual(len(self.launches()), 1)
        attempt = self.launches()[0]
        (self.fx.resume / attempt / "outcome").write_text("completed\n")
        self.manual()
        self.assertEqual(self.handoff()["status"], "completed")
        self.assertEqual(len(self.launches()), 1)

    def test_invalid_receipt_blocks_replay_even_if_the_wrapper_exited_zero(self):
        self.arm()
        self.payload("completed\nextra")
        self.assertNotEqual(self.manual().returncode, 0)
        self.assertNotEqual(self.manual().returncode, 0)
        self.assertNotEqual(self.handoff()["status"], "completed")
        self.assertEqual(len(self.launches()), 1)

    def test_durable_receipt_recovers_parent_death_without_reinstall(self):
        self.arm()
        self.payload("completed", crash=True)
        self.manual()
        self.assertEqual(self.handoff()["status"], "running")
        self.manual()
        self.assertEqual(self.handoff()["status"], "completed")
        self.assertEqual(len(self.launches()), 1)

    def test_legacy_parent_death_without_receipt_cannot_replay(self):
        self.generate("--mode", "safe")
        context = self.fx.resume / "continue_context.env"
        lines = [line for line in context.read_text().splitlines()
                 if not line.startswith("CONTINUE_REQUIRES_TTY=")]
        context.write_text("\n".join(lines + [""]))
        armed = self.fx.run()
        self.assertEqual(armed.returncode, 0, armed.stdout + armed.stderr)
        self.assertEqual(self.handoff()["status"], "awaiting")
        self.payload(None, crash=True)
        self.manual()
        self.assertEqual(self.handoff()["status"], "running")
        self.manual()
        self.assertEqual(self.handoff()["status"], "unconfirmed")
        self.manual()
        self.fx.run()
        self.assertEqual(len(self.launches()), 1)
        self.assertNotIn("CONTINUE:", self.fx.events())

    def test_orphan_holds_lock_and_recovery_without_receipt_needs_new_attempt(self):
        self.arm()
        self.payload(None, crash=True, hold=True)
        with self.fx.process("--continue-install", tty=True) as process:
            try:
                deadline = time.monotonic() + 10
                while not (self.fx.resume / "entered").exists():
                    if time.monotonic() >= deadline:
                        self.fail("Continuation did not reach its crash barrier")
                    time.sleep(.05)
                self.assertNotEqual(self.manual().returncode, 0)
                self.assertEqual(self.handoff()["status"], "running")
                self.assertEqual(len(self.launches()), 1)
            finally:
                (self.fx.resume / "release").touch()
                process.communicate(timeout=10)
        # The PTY owner and orphan may exit in either order. Wait for proof
        # that the orphan has dropped the shared upgrade lock.
        with (self.fx.resume / "upgrade.lock").open("r") as lock:
            deadline = time.monotonic() + 5
            while True:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if time.monotonic() >= deadline:
                        self.fail("Orphan retained the upgrade lock")
                    time.sleep(.05)
        self.payload("completed")
        self.manual()
        self.assertEqual(self.handoff()["status"], "interrupted")
        self.assertEqual(len(self.launches()), 1)
        self.assertEqual(self.manual().returncode, 0)
        self.assertEqual(self.handoff()["status"], "completed")
        self.assertEqual(len(set(self.launches())), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
