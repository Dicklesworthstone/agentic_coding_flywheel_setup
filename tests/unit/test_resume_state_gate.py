#!/usr/bin/env python3
"""Resume checkpoint preparation with real locks and controlling terminals.

Source the production state library and compose the existing actual-main
fixture harness. Package and service edges are inert. State I/O failures use
controlled fixtures; fixture directories and evidence are retained.
ACFS_STATE_LIB_SOURCE optionally selects a saved library for baseline checks.
The main harness also accepts ACFS_INSTALLER_MAIN_TEST_SOURCE for a saved main.
"""
from __future__ import annotations

import errno
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import pty
import select
import shlex
import shutil
import signal
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
STATE = Path(os.environ.get("ACFS_STATE_LIB_SOURCE", ROOT / "scripts/lib/state.sh"))
RESUME_PATHS = ("forced", "default", "tty-read", "tty-gum")
SOURCE_A = "a" * 64
SOURCE_B = "b" * 64

# Import the harness module, not its TestCase: unittest must discover only this
# file's cases rather than silently rerunning all imported upgrade tests.
_main_spec = importlib.util.spec_from_file_location(
    "acfs_resume_main_fixture", ROOT / "tests/unit/test_ubuntu_upgrade_main.py")
_main_fixture = importlib.util.module_from_spec(_main_spec)
_main_spec.loader.exec_module(_main_fixture)


def checkpoint_bytes():
    return (json.dumps({
        "schema_version": 3,
        "version": "old-version",
        "mode": "safe",
        "completed_phases": ["user_setup", "finalize"],
        "partial_phases": [],
        "phase_steps": {},
        "phase_attempts": {},
        "phase_durations": {},
        "sentinel": "original evidence",
    }, indent=2) + "\n").encode()


def source_checkpoint(source=SOURCE_A):
    state = json.loads(checkpoint_bytes())
    state["source_ledger_sha256"] = source
    return (json.dumps(state, indent=2) + "\n").encode()


def clean_environment(home):
    return {"PATH": "/usr/bin:/bin", "HOME": str(home),
            "TMPDIR": os.environ.get("TMPDIR", "/tmp"), "TERM": "dumb"}


# Fail just one atomic-write attempt, so a later writable state directory
# cannot mask a lost version transition. No host filesystem is made unwritable.
WRITE_FAILURE = r'''
mktemp() {
    if [[ "${1:-}" == "$ACFS_HOME/.state."* && ! -e "$ACFS_HOME/write-failed" ]]; then
        : > "$ACFS_HOME/write-failed"
        return 73
    fi
    command mktemp "$@"
}
'''

# Model the optional bootstrap binary being absent without changing system
# packages. Python, the real fallback parser, remains available.
WITHOUT_JQ = r'''
command() {
    if [[ "${1:-}" == -v && "${2:-}" == jq ]]; then return 1; fi
    builtin command "$@"
}
jq() { trace unexpected_jq; return 127; }
'''


class ResumeCheckpointGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for executable in ("bash", "flock", "jq"):
            if shutil.which(executable) is None:
                raise unittest.SkipTest(f"{executable} is required")

    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="acfs-resume-state-gate-"))
        self.fixture_count = 0

    def fixture(self, label, *, content=None):
        self.fixture_count += 1
        folder = self.root / f"{self.fixture_count}-{label}"
        folder.mkdir()
        (folder / "state.json").write_bytes(
            checkpoint_bytes() if content is None else content)
        return folder

    def run_resume(self, folder, path="forced", *, choice="resume", write_failure=False,
                   backup_failure=False, force_reinstall=False, version="new-version",
                   source=None, extra="", on_prompt=None):
        tty = path.startswith("tty-")
        gum = path == "tty-gum"
        script = "\n".join([
            "set -euo pipefail",
            f"builtin source {shlex.quote(str(STATE))}",
            f"state_bind_installer_source {shlex.quote(source)}" if source is not None else "",
            f"export ACFS_HOME={shlex.quote(str(folder))}",
            'export ACFS_STATE_FILE="$ACFS_HOME/state.json"',
            "export ACFS_STATE_LOCK_TIMEOUT=1",
            f"ACFS_VERSION={shlex.quote(version)}",
            f"ACFS_FORCE_RESUME={'true' if path == 'forced' else 'false'}",
            f"ACFS_FORCE_REINSTALL={'true' if force_reinstall else 'false'}",
            f"ACFS_INTERACTIVE={'true' if tty else 'false'}",
            f"HAS_GUM={'true' if gum else 'false'}",
            'log_error() { printf "ERROR:%s\\n" "$*" >&2; }',
            r'''
gum() {
    if [[ "${1:-}" == choose ]]; then
        printf 'GUM_CHOICE_READY\n' >&2
        local selection
        IFS= read -r selection < /dev/tty || return 1
        printf '%s\n' "$selection"
    else
        printf '%s\n' "${@: -1}"
    fi
}
''' if gum else "",
            WRITE_FAILURE if write_failure else "",
            r'''
mv() {
    if [[ "${1:-}" == "$ACFS_STATE_FILE" ]]; then
        : > "$ACFS_HOME/backup-failed"
        return 74
    fi
    command mv "$@"
}
''' if backup_failure else "",
            extra,
            "status=0",
            # main() also calls this with ||; tests must preserve Bash's
            # conditional-call errexit semantics that exposed the defect.
            "confirm_resume || status=$?",
            'printf "%s\\n" "$status" > "$ACFS_HOME/resume-status"',
            'exit "$status"',
        ])
        (folder / "fixture.sh").write_text(script + "\n")
        if tty:
            response = {
                "resume": "Resume" if gum else "r",
                "abort": "Abort" if gum else "a",
                "fresh": "Fresh install" if gum else "f",
                "eof": "\x04",
            }[choice]
            prompt = b"GUM_CHOICE_READY" if gum else b"Choice [R/f/a]:"
            status, output = self.run_terminal(folder, script, prompt, response, on_prompt)
        else:
            result = subprocess.run(
                ["/bin/bash", "-p", "-c", script], stdin=subprocess.DEVNULL,
                text=True, capture_output=True, env=clean_environment(folder),
                start_new_session=True, timeout=8)
            status, output = result.returncode, result.stdout + result.stderr
        (folder / "output.log").write_text(output)
        return status, output

    def run_terminal(self, folder, script, prompt, response, on_prompt):
        pid, terminal = pty.fork()
        if pid == 0:
            try:
                os.chdir(folder)
                os.execve("/bin/bash", ["bash", "-p", "-c", script], clean_environment(folder))
            except BaseException:
                # An exec failure must not return the fork into unittest.
                os._exit(127)
        output = bytearray()
        answered = False
        reaped = False
        deadline = time.monotonic() + 8
        try:
            while time.monotonic() < deadline:
                ready, _, _ = select.select([terminal], [], [], 0.05)
                if ready:
                    try:
                        chunk = os.read(terminal, 65536)
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        chunk = b""
                    output.extend(chunk)
                if not answered and prompt in output:
                    if on_prompt is not None:
                        on_prompt()
                    os.write(terminal, (response + "\n").encode())
                    answered = True
                observed, status = os.waitpid(pid, os.WNOHANG)
                if observed:
                    reaped = True
                    self.assertTrue(answered, output.decode(errors="replace"))
                    return os.waitstatus_to_exitcode(status), output.decode(errors="replace")
            self.fail("Resume prompt did not finish:\n" + output.decode(errors="replace"))
        finally:
            if not reaped:
                try:
                    os.killpg(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                os.waitpid(pid, 0)
            os.close(terminal)

    def assert_version_committed(self, folder):
        state = json.loads((folder / "state.json").read_text())
        self.assertEqual(state["version"], "new-version")
        self.assertEqual(state["completed_phases"], ["user_setup"])
        self.assertEqual(state["sentinel"], "original evidence")

    def test_reviewed_reboot_arguments_keep_all_checkpoint_choices(self):
        parser = _main_fixture.definition(_main_fixture.MAIN.read_text(), "parse_args")
        replay = parser + "\nACFS_INTERACTIVE=false\nparse_args --interactive-resume --mode safe"
        for choice, expected_status in (("resume", 0), ("fresh", 1), ("abort", 2)):
            with self.subTest(choice=choice):
                original = checkpoint_bytes()
                folder = self.fixture(choice, content=original)
                status, output = self.run_resume(
                    folder, "tty-read", choice=choice, extra=replay, version="old-version")
                self.assertEqual(status, expected_status, output)
                if choice == "fresh":
                    self.assertFalse((folder / "state.json").exists())
                    [backup] = folder.glob("state.json.backup.*")
                    self.assertEqual(backup.read_bytes(), original)
                else:
                    self.assertEqual((folder / "state.json").read_bytes(), original)

    def test_default_resume_preserves_work_before_first_completed_phase(self):
        # Use the real state writers. SIGKILL leaves the active cursor, while
        # SIGTERM between steps clears the cursor without setting failed_phase.
        for interrupted in (False, True):
            with self.subTest(interrupted=interrupted):
                state = json.loads(checkpoint_bytes())
                state["completed_phases"] = []
                folder = self.fixture("first-phase", content=json.dumps(state).encode())
                setup = 'state_phase_start user_setup\n'
                if interrupted:
                    setup += 'state_mark_interrupted\n'
                setup += 'cp "$ACFS_STATE_FILE" "$ACFS_HOME/before-resume.json"'
                status, output = self.run_resume(
                    folder, "default", version="old-version", extra=setup)
                self.assertEqual(status, 0, output)
                before = (folder / "before-resume.json").read_bytes()
                self.assertEqual((folder / "state.json").read_bytes(), before)
                self.assertIsNone(json.loads(before).get("failed_phase"))
                self.assertIn("user_setup", json.loads(before)["partial_phases"])

    def test_pristine_checkpoint_still_requires_fresh_confirmation(self):
        state = json.loads(checkpoint_bytes())
        state["completed_phases"] = []
        folder = self.fixture("pristine", content=json.dumps(state).encode())
        status, output = self.run_resume(folder, "default", version="old-version")
        self.assertEqual(status, 1, output)

    def test_same_version_source_change_invalidates_finalize_in_all_resume_paths(self):
        for path in RESUME_PATHS:
            with self.subTest(path=path):
                folder = self.fixture(path, content=source_checkpoint())
                status, output = self.run_resume(
                    folder, path, version="old-version", source=SOURCE_B)
                self.assertEqual(status, 0, output)
                state = json.loads((folder / "state.json").read_text())
                self.assertEqual(state["completed_phases"], ["user_setup"])
                self.assertEqual(state["version"], "old-version")
                self.assertEqual(state["source_ledger_sha256"], SOURCE_A)
                self.assertEqual(state["sentinel"], "original evidence")

    def test_legacy_source_identity_requires_finalization_refresh(self):
        for content in (checkpoint_bytes(), source_checkpoint(None)):
            for path in RESUME_PATHS:
                with self.subTest(path=path, content=content):
                    folder = self.fixture(path, content=content)
                    status, output = self.run_resume(
                        folder, path, version="old-version", source=SOURCE_B)
                    self.assertEqual(status, 0, output)
                    state = json.loads((folder / "state.json").read_text())
                    self.assertEqual(state["completed_phases"], ["user_setup"])
                    self.assertIsNone(state.get("source_ledger_sha256"))

    def test_interrupted_prompt_cannot_authorize_resume(self):
        for path in ("tty-read", "tty-gum"):
            with self.subTest(path=path):
                folder = self.fixture(path)
                before = (folder / "state.json").read_bytes()
                status, output = self.run_resume(folder, path, choice="eof")
                self.assertEqual(status, 3, output)
                self.assertEqual((folder / "state.json").read_bytes(), before)

    def test_matching_source_identity_needs_no_state_write(self):
        for path in RESUME_PATHS:
            with self.subTest(path=path):
                before = source_checkpoint()
                folder = self.fixture(path, content=before)
                with (folder / "state.json.lock").open("w") as holder:
                    fcntl.flock(holder, fcntl.LOCK_EX)
                    status, output = self.run_resume(
                        folder, path, version="old-version", source=SOURCE_A,
                        write_failure=True)
                self.assertEqual(status, 0, output)
                self.assertFalse((folder / "write-failed").exists())
                self.assertEqual((folder / "state.json").read_bytes(), before)

    def test_source_invalidation_write_failure_refuses_resume(self):
        for path in RESUME_PATHS:
            with self.subTest(path=path):
                before = source_checkpoint()
                folder = self.fixture(path, content=before)
                status, output = self.run_resume(
                    folder, path, version="old-version", source=SOURCE_B,
                    write_failure=True)
                self.assertEqual(status, 3, output)
                self.assertTrue((folder / "write-failed").exists())
                self.assertEqual((folder / "state.json").read_bytes(), before)

    def test_source_change_abort_and_fresh_preserve_original_checkpoint(self):
        for path in ("tty-read", "tty-gum"):
            for choice in ("abort", "fresh"):
                with self.subTest(path=path, choice=choice):
                    before = source_checkpoint()
                    folder = self.fixture(path, content=before)
                    status, output = self.run_resume(
                        folder, path, version="old-version", source=SOURCE_B,
                        choice=choice, write_failure=True)
                    self.assertEqual(status, 2 if choice == "abort" else 1, output)
                    self.assertFalse((folder / "write-failed").exists())
                    if choice == "abort":
                        self.assertEqual((folder / "state.json").read_bytes(), before)
                    else:
                        backups = list(folder.glob("state.json.backup.*"))
                        self.assertEqual(len(backups), 1)
                        self.assertEqual(backups[0].read_bytes(), before)

    def test_malformed_checkpoint_identity_is_not_treated_as_current(self):
        for source in ("", "main", "a" * 40, "A" * 64, [], {"sha": SOURCE_A}, 7):
            with self.subTest(source=source):
                before = source_checkpoint(source)
                folder = self.fixture("malformed-source", content=before)
                status, output = self.run_resume(
                    folder, version="old-version", source=SOURCE_B)
                self.assertEqual(status, 3, output)
                self.assertEqual((folder / "state.json").read_bytes(), before)

    def test_source_transition_preserves_updates_while_prompt_is_open(self):
        for path in ("tty-read", "tty-gum"):
            with self.subTest(path=path):
                folder = self.fixture(path, content=source_checkpoint())

                def update_checkpoint():
                    script = "\n".join([
                        "set -euo pipefail",
                        f"builtin source {shlex.quote(str(STATE))}",
                        f"export ACFS_STATE_FILE={shlex.quote(str(folder / 'state.json'))}",
                        "state_update_with_args '.sentinel = \"saved while prompting\" | "
                        ".phase_durations.agents = 17 | .failed_phase = \"agents\" | "
                        ".failed_step = \"dependency\" | .failed_error = \"preserve evidence\"'",
                    ])
                    writer = subprocess.run(
                        ["/bin/bash", "-p", "-c", script], text=True, capture_output=True,
                        env=clean_environment(folder), start_new_session=True, timeout=4)
                    self.assertEqual(writer.returncode, 0, writer.stdout + writer.stderr)

                status, output = self.run_resume(
                    folder, path, version="old-version", source=SOURCE_B,
                    on_prompt=update_checkpoint)
                self.assertEqual(status, 0, output)
                state = json.loads((folder / "state.json").read_text())
                self.assertEqual(state["completed_phases"], ["user_setup"])
                self.assertEqual(state["source_ledger_sha256"], SOURCE_A)
                self.assertEqual(state["sentinel"], "saved while prompting")
                self.assertEqual(state["phase_durations"]["agents"], 17)
                self.assertEqual(state["failed_phase"], "agents")
                self.assertEqual(state["failed_step"], "dependency")
                self.assertEqual(state["failed_error"], "preserve evidence")

    def test_all_resume_paths_reject_failed_version_write(self):
        for path in RESUME_PATHS:
            with self.subTest(path=path):
                folder = self.fixture(path)
                before = (folder / "state.json").read_bytes()
                status, output = self.run_resume(folder, path, write_failure=True)
                self.assertEqual(status, 3, output)
                self.assertTrue((folder / "write-failed").exists())
                self.assertEqual((folder / "state.json").read_bytes(), before)

    def test_all_resume_paths_commit_version_before_accepting(self):
        for path in RESUME_PATHS:
            with self.subTest(path=path):
                folder = self.fixture(path)
                status, output = self.run_resume(folder, path)
                self.assertEqual(status, 0, output)
                self.assert_version_committed(folder)

    def test_unchanged_version_needs_no_write_even_when_state_lock_is_held(self):
        for path in RESUME_PATHS:
            with self.subTest(path=path):
                folder = self.fixture(path)
                before = (folder / "state.json").read_bytes()
                with (folder / "state.json.lock").open("w") as holder:
                    fcntl.flock(holder, fcntl.LOCK_EX)
                    status, output = self.run_resume(
                        folder, path, version="old-version", write_failure=True)
                self.assertEqual(status, 0, output)
                self.assertFalse((folder / "write-failed").exists())
                self.assertEqual((folder / "state.json").read_bytes(), before)

    def test_lock_contention_refuses_resume_without_releasing_other_owner(self):
        for path in ("forced", "default"):
            with self.subTest(path=path):
                folder = self.fixture(path)
                before = (folder / "state.json").read_bytes()
                with (folder / "state.json.lock").open("w") as holder:
                    fcntl.flock(holder, fcntl.LOCK_EX)
                    status, output = self.run_resume(folder, path)
                    with (folder / "state.json.lock").open("r+") as contender:
                        with self.assertRaises(BlockingIOError):
                            fcntl.flock(contender, fcntl.LOCK_EX | fcntl.LOCK_NB)
                self.assertEqual(status, 3, output)
                self.assertEqual((folder / "state.json").read_bytes(), before)

    def test_updates_written_while_prompt_is_open_survive_version_commit(self):
        for path in ("tty-read", "tty-gum"):
            with self.subTest(path=path):
                folder = self.fixture(path)

                def update_checkpoint():
                    # This writer starts only after the original checkpoint
                    # has been displayed. Use the public transaction API.
                    update = r'''
state_update_with_args '
    .sentinel = "saved while prompting" |
    .phase_durations.agents = 17 |
    .partial_phases = ["agents"] |
    .failed_phase = "agents" |
    .failed_step = "dependency" |
    .failed_error = "keep recovery evidence"
'
'''
                    script = "\n".join([
                        "set -euo pipefail",
                        f"builtin source {shlex.quote(str(STATE))}",
                        f"export ACFS_STATE_FILE={shlex.quote(str(folder / 'state.json'))}",
                        update,
                    ])
                    (folder / "concurrent-writer.sh").write_text(script)
                    writer = subprocess.run(
                        ["/bin/bash", "-p", "-c", script], text=True, capture_output=True,
                        env=clean_environment(folder), start_new_session=True, timeout=4)
                    self.assertEqual(writer.returncode, 0, writer.stdout + writer.stderr)

                status, output = self.run_resume(folder, path, on_prompt=update_checkpoint)
                self.assertEqual(status, 0, output)
                state = json.loads((folder / "state.json").read_text())
                self.assertEqual(state["version"], "new-version")
                self.assertEqual(state["completed_phases"], ["user_setup"])
                self.assertEqual(state["sentinel"], "saved while prompting")
                self.assertEqual(state["phase_durations"]["agents"], 17)
                self.assertEqual(state["partial_phases"], ["agents"])
                self.assertEqual(state["failed_phase"], "agents")
                self.assertEqual(state["failed_step"], "dependency")
                self.assertEqual(state["failed_error"], "keep recovery evidence")

    def test_user_abort_preserves_checkpoint_without_version_write(self):
        for path in ("tty-read", "tty-gum"):
            with self.subTest(path=path):
                folder = self.fixture(path)
                before = (folder / "state.json").read_bytes()
                status, output = self.run_resume(
                    folder, path, choice="abort", write_failure=True)
                self.assertEqual(status, 2, output)
                self.assertEqual((folder / "state.json").read_bytes(), before)
                self.assertFalse((folder / "write-failed").exists())

    def test_fresh_choices_archive_original_checkpoint_without_version_write(self):
        for path, forced in (("tty-read", False), ("tty-gum", False), ("default", True)):
            with self.subTest(path=path, forced=forced):
                folder = self.fixture(path)
                before = (folder / "state.json").read_bytes()
                status, output = self.run_resume(
                    folder, path, choice="fresh", force_reinstall=forced, write_failure=True)
                self.assertEqual(status, 1, output)
                self.assertFalse((folder / "state.json").exists())
                backups = list(folder.glob("state.json.backup.*"))
                self.assertEqual(len(backups), 1)
                self.assertEqual(backups[0].read_bytes(), before)
                self.assertFalse((folder / "write-failed").exists())

    def test_backup_failures_are_technical_errors_and_preserve_checkpoint(self):
        scenarios = (("tty-read", False, None), ("tty-gum", False, None),
                     ("default", True, None), ("default", False, b"invalid-json\n"))
        for path, forced, content in scenarios:
            with self.subTest(path=path, forced=forced, malformed=content is not None):
                folder = self.fixture(path, content=content)
                before = (folder / "state.json").read_bytes()
                status, output = self.run_resume(
                    folder, path, choice="fresh", force_reinstall=forced, backup_failure=True)
                self.assertEqual(status, 3, output)
                if content is None:
                    self.assertTrue((folder / "backup-failed").exists())
                else:
                    # Unparseable state could contain managed selection intent.
                    # It must now be refused before even attempting a backup.
                    self.assertFalse((folder / "backup-failed").exists())
                    self.assertIn("Refusing to reset or resume", output)
                self.assertEqual((folder / "state.json").read_bytes(), before)
                self.assertEqual(list(folder.glob("state.json.backup.*")), [])

    def test_checkpoint_path_resolution_failure_is_technical_error(self):
        folder = self.fixture("unresolved-path")
        status, output = self.run_resume(
            folder, extra="state_get_file() { return 17; }")
        self.assertEqual(status, 3, output)
        self.assertEqual((folder / "state.json").read_bytes(), checkpoint_bytes())

    def test_unreadable_metadata_is_technical_error_without_checkpoint_mutation(self):
        state = json.loads(checkpoint_bytes())
        state["completed_phases"] = {"invalid": "shape"}
        before = (json.dumps(state) + "\n").encode()
        folder = self.fixture("invalid-metadata", content=before)
        status, output = self.run_resume(folder)
        self.assertEqual(status, 3, output)
        self.assertEqual((folder / "state.json").read_bytes(), before)


class ResumeSourceDeploymentTests(unittest.TestCase):
    # Reuse fixture helpers without inheriting (and rerunning) their tests.
    setUp = ResumeCheckpointGateTests.setUp
    fixture = ResumeCheckpointGateTests.fixture

    @classmethod
    def setUpClass(cls):
        ResumeCheckpointGateTests.setUpClass()

    def run_steps(self, folder, body, *, inherited=None):
        script = "\n".join([
            "set -euo pipefail",
            f"builtin source {shlex.quote(str(STATE))}",
            f"export ACFS_HOME={shlex.quote(str(folder))}",
            'export ACFS_STATE_FILE="$ACFS_HOME/state.json"',
            "ACFS_VERSION=old-version",
            "ACFS_FORCE_RESUME=true",
            "ACFS_INTERACTIVE=false",
            f"state_bind_installer_source {SOURCE_B}",
            "acfs_verify_phase() { return 0; }",
            'untouched_phase() { printf "unexpected phase\\n" >> "$ACFS_HOME/events"; }',
            'deploy_runtime() { printf "deployed\\n" >> "$ACFS_HOME/events"; '
            f'printf "%s\\n" {SOURCE_B} > "$ACFS_HOME/runtime"; }}',
            body,
        ])
        environment = clean_environment(folder)
        environment.update(inherited or {})
        result = subprocess.run(
            ["/bin/bash", "-p", "-c", script], text=True, capture_output=True,
            env=environment, start_new_session=True, timeout=10)
        (folder / "deployment-output.log").write_text(result.stdout + result.stderr)
        return result

    def test_targeted_resume_defers_refresh_then_full_resume_deploys_once(self):
        folder = self.fixture("targeted-then-full", content=source_checkpoint())
        (folder / "runtime").write_text(SOURCE_A + "\n")
        targeted = self.run_steps(folder, r'''
declare -a ONLY_MODULES=(agents.claude) ONLY_PHASES=() ACFS_EFFECTIVE_PLAN=(agents.claude)
declare -A ACFS_MODULE_PHASE=([agents.claude]=7)
confirm_resume
run_phase user_setup "User setup" untouched_phase
run_phase finalize "Finalize" deploy_runtime
''')
        self.assertEqual(targeted.returncode, 0, targeted.stdout + targeted.stderr)
        state = json.loads((folder / "state.json").read_text())
        self.assertEqual(state["completed_phases"], ["user_setup"])
        self.assertEqual(state["source_ledger_sha256"], SOURCE_A)
        self.assertEqual((folder / "runtime").read_text(), SOURCE_A + "\n")
        self.assertFalse((folder / "events").exists())

        full = self.run_steps(folder, r'''
confirm_resume
run_phase user_setup "User setup" untouched_phase
run_phase finalize "Finalize" deploy_runtime
''')
        self.assertEqual(full.returncode, 0, full.stdout + full.stderr)
        state = json.loads((folder / "state.json").read_text())
        self.assertEqual(state["completed_phases"], ["user_setup", "finalize"])
        self.assertEqual(state["source_ledger_sha256"], SOURCE_B)
        self.assertEqual((folder / "runtime").read_text(), SOURCE_B + "\n")
        self.assertEqual((folder / "events").read_text(), "deployed\n")

        repeat = self.run_steps(folder, r'''
confirm_resume
run_phase finalize "Finalize" deploy_runtime
''')
        self.assertEqual(repeat.returncode, 0, repeat.stdout + repeat.stderr)
        self.assertEqual((folder / "events").read_text(), "deployed\n")

    def test_failed_finalization_keeps_old_identity_and_retries(self):
        folder = self.fixture("failed-refresh", content=source_checkpoint())
        failed = self.run_steps(folder, r'''
confirm_resume
failed_deployment() { return 7; }
run_phase finalize "Finalize" failed_deployment
''')
        self.assertNotEqual(failed.returncode, 0, failed.stdout + failed.stderr)
        state = json.loads((folder / "state.json").read_text())
        self.assertNotIn("finalize", state["completed_phases"])
        self.assertEqual(state["source_ledger_sha256"], SOURCE_A)
        recovered = self.run_steps(folder, r'''
confirm_resume
run_phase finalize "Finalize" deploy_runtime
''')
        self.assertEqual(recovered.returncode, 0, recovered.stdout + recovered.stderr)
        state = json.loads((folder / "state.json").read_text())
        self.assertIn("finalize", state["completed_phases"])
        self.assertEqual(state["source_ledger_sha256"], SOURCE_B)

    def test_failed_completion_write_cannot_publish_new_identity(self):
        folder = self.fixture("completion-write-fails", content=source_checkpoint())
        failed = self.run_steps(folder, "\n".join([
            "confirm_resume", "state_phase_start finalize", WRITE_FAILURE,
            "state_phase_complete finalize",
        ]))
        self.assertNotEqual(failed.returncode, 0, failed.stdout + failed.stderr)
        state = json.loads((folder / "state.json").read_text())
        self.assertNotIn("finalize", state["completed_phases"])
        self.assertEqual(state["source_ledger_sha256"], SOURCE_A)
        self.assertTrue((folder / "write-failed").exists())

    def test_source_binding_rejects_malformed_digests(self):
        folder = self.fixture("invalid-binding", content=source_checkpoint())
        for digest in ("", "main", "A" * 64, "a" * 40, "b" * 65, "x" * 64):
            with self.subTest(digest=digest):
                result = self.run_steps(folder, f"state_bind_installer_source {shlex.quote(digest)}")
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((folder / "state.json").read_bytes(), source_checkpoint())

    def test_inherited_identity_cannot_replace_verified_binding(self):
        folder = self.fixture("inherited-source", content=source_checkpoint())
        script = "\n".join([
            "set -euo pipefail",
            f"builtin source {shlex.quote(str(STATE))}",
            '[[ -z "$_ACFS_STATE_SOURCE_LEDGER_SHA256" ]]',
        ])
        environment = clean_environment(folder)
        environment.update({"_ACFS_STATE_SOURCE_LEDGER_SHA256": SOURCE_A,
                            "ACFS_TRUSTED_INTERNAL_LEDGER_SHA256": SOURCE_A})
        result = subprocess.run(
            ["/bin/bash", "-p", "-c", script], text=True, capture_output=True,
            env=environment, start_new_session=True, timeout=4)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        rebound = self.run_steps(folder, "confirm_resume", inherited=environment)
        self.assertEqual(rebound.returncode, 0, rebound.stdout + rebound.stderr)
        self.assertEqual(json.loads((folder / "state.json").read_text())["completed_phases"],
                         ["user_setup"])


class ResumeMainGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        _main_fixture.MainUpgradeOrderTests.setUpClass()
        cls.harness = _main_fixture.MainUpgradeOrderTests(methodName="runTest")

    def run_main(self, extra):
        return self.harness.run_main(
            overrides={"TEST_MISSING_TOOLS": "false"}, extra=extra)

    def test_resume_error_and_unknown_status_stop_before_base_dependencies(self):
        for status in (3, 17):
            with self.subTest(status=status):
                result, events, _ = self.run_main(
                    f"confirm_resume() {{ trace resume_gate; return {status}; }}\n"
                    "confirm_or_exit() { trace unexpected_fresh; }\n"
                    "state_init() { trace unexpected_state_init; }\n"
                    "ensure_base_deps() { trace mut:base; exit 0; }")
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("resume_gate", events)
                self.assertNotIn("mut:base", events)
                self.assertNotIn("unexpected_fresh", events)
                self.assertNotIn("unexpected_state_init", events)

    def test_user_abort_exits_successfully_before_base_dependencies(self):
        result, events, _ = self.run_main(
            "confirm_resume() { trace user_abort; return 2; }\n"
            "ensure_base_deps() { trace mut:base; exit 19; }")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("user_abort", events)
        self.assertNotIn("mut:base", events)

    def test_resume_and_fresh_success_reach_base_dependencies(self):
        for status in (0, 1):
            with self.subTest(status=status):
                result, events, _ = self.run_main(
                    f"confirm_resume() {{ trace resume_gate; return {status}; }}\n"
                    "confirm_or_exit() { trace fresh_confirmed; }\n"
                    "state_init() { trace state_initialized; }\n"
                    "ensure_base_deps() { trace mut:base; exit 0; }")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("mut:base", events)
                self.assertLess(events.index("resume_gate"), events.index("mut:base"))
                self.assertEqual("fresh_confirmed" in events, status == 1)
                self.assertEqual("state_initialized" in events, status == 1)

    def real_state_setup(self):
        return "\n".join([
            f"builtin source {shlex.quote(str(STATE))}",
            'mkdir -p "$ACFS_HOME"',
            'export ACFS_STATE_FILE="$ACFS_HOME/state.json"',
            "ACFS_VERSION=new-version",
            "ACFS_FORCE_RESUME=true",
            "ACFS_FORCE_REINSTALL=false",
            "ACFS_INTERACTIVE=false",
            "HAS_GUM=false",
            f"printf '%s' {shlex.quote(checkpoint_bytes().decode())} > \"$ACFS_STATE_FILE\"",
        ])

    def test_real_failed_version_transition_stops_main(self):
        result, events, folder = self.run_main("\n".join([
            self.real_state_setup(), WRITE_FAILURE,
            "ensure_base_deps() { trace mut:base; exit 0; }",
        ]))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("mut:base", events)
        state_dir = folder / "home/.acfs"
        self.assertTrue((state_dir / "write-failed").exists())
        self.assertEqual((state_dir / "state.json").read_bytes(), checkpoint_bytes())

    def test_real_version_transition_is_committed_before_base_dependencies(self):
        result, events, folder = self.run_main("\n".join([
            self.real_state_setup(),
            r'''
ensure_base_deps() {
    jq -e '.version == "new-version" and (.completed_phases | index("finalize") == null)' \
        "$ACFS_STATE_FILE" >/dev/null || exit 31
    trace mut:base
    exit 0
}
''',
        ]))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("mut:base", events)
        state = json.loads((folder / "home/.acfs/state.json").read_text())
        self.assertEqual(state["version"], "new-version")
        self.assertEqual(state["completed_phases"], ["user_setup"])

    def test_same_version_source_transition_is_required_before_main_continues(self):
        for write_failure in (False, True):
            with self.subTest(write_failure=write_failure):
                result, events, folder = self.run_main("\n".join([
                    self.real_state_setup(),
                    "ACFS_VERSION=old-version",
                    f"state_bind_installer_source {SOURCE_B}",
                    f"printf '%s' {shlex.quote(source_checkpoint().decode())} > \"$ACFS_STATE_FILE\"",
                    WRITE_FAILURE if write_failure else "",
                    r'''
ensure_base_deps() {
    jq -e '.version == "old-version" and (.completed_phases | index("finalize") == null)' \
        "$ACFS_STATE_FILE" >/dev/null || exit 31
    trace mut:base
    exit 0
}
''',
                ]))
                state_dir = folder / "home/.acfs"
                if write_failure:
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertNotIn("mut:base", events)
                    self.assertTrue((state_dir / "write-failed").exists())
                    self.assertEqual((state_dir / "state.json").read_bytes(), source_checkpoint())
                else:
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("mut:base", events)
                    state = json.loads((state_dir / "state.json").read_text())
                    self.assertEqual(state["completed_phases"], ["user_setup"])
                    self.assertEqual(state["source_ledger_sha256"], SOURCE_A)



class OptionalModuleResumeTests(unittest.TestCase):
    """Exercise actual phase skipping, bounded probes and persisted attempts.

    Package installation is a fixture that makes a local executable healthy;
    the checkpoint and verifier decide whether that fixture may run.
    """

    @classmethod
    def setUpClass(cls):
        for executable in ("bash", "flock", "jq", "timeout"):
            if shutil.which(executable) is None:
                raise unittest.SkipTest(f"{executable} is required")
        installer = Path(os.environ.get("ACFS_INSTALLER_MAIN_TEST_SOURCE", ROOT / "install.sh"))
        cls.verify_phase = _main_fixture.definition(installer.read_text(), "acfs_verify_phase")

    def run_phase_resume(self, *, repair=True, saved=True, requested=False,
                         selected=True, applicable=True, healthy=False, soft_only=False):
        folder = Path(tempfile.mkdtemp(prefix="acfs-optional-resume-"))
        home = folder / "home"
        home.mkdir()
        probe = folder / "probe"
        probe.write_text(
            "#!/bin/bash\n"
            f"printf 'probe\\n' >> {shlex.quote(str(folder / 'trace'))}\n"
            f"test -f {shlex.quote(str(folder / 'ready'))}\n")
        probe.chmod(0o755)
        if healthy:
            (folder / "ready").touch()
        helpers = Path(os.environ.get(
            "ACFS_INSTALL_HELPERS_TEST_SOURCE", ROOT / "scripts/lib/install_helpers.sh"))
        script = "\n".join([
            "set -euo pipefail",
            f"source {shlex.quote(str(helpers))}",
            f"source {shlex.quote(str(STATE))}",
            f"source {shlex.quote(str(ROOT / 'scripts/generated/manifest_index.sh'))}",
            self.verify_phase,
            f"export TEST_ROOT={shlex.quote(str(folder))}",
            'export TARGET_HOME="$HOME" ACFS_HOME="$HOME/.acfs"',
            'export TARGET_USER="$(id -un)" ACFS_STATE_FILE="$ACFS_HOME/state.json"',
            "ACFS_VERSION=fixture; MODE=safe; HAS_GUM=false; ACFS_DISTRO_FAMILY=ubuntu",
            "state_getent_passwd_entry() { printf '%s:x:1000:1000::%s:/bin/bash\\n' \"$TARGET_USER\" \"$TARGET_HOME\"; }",
            "ONLY_MODULES=(); ONLY_PHASES=(); ACFS_PLAN_REASON=()",
            "ACFS_EFFECTIVE_PLAN=(agents.claude" + (" agents.opencode" if selected else "") + ")",
            f"ACFS_SAVED_SELECTION_ACTIVE={'true' if saved else 'false'}",
            "ACFS_PLAN_REASON[agents.opencode]='explicitly requested'" if requested else "",
            "ACFS_MODULE_VERIFY_COUNT[agents.claude]=1",
            "ACFS_MODULE_VERIFY_COMMAND[agents.claude.0]=true",
            "ACFS_MODULE_VERIFY_RUN_AS[agents.claude]=current",
            f"ACFS_MODULE_VERIFY_COUNT[agents.opencode]={0 if soft_only else 1}",
            f"ACFS_MODULE_VERIFY_COMMAND[agents.opencode.0]={shlex.quote(shlex.quote(str(probe)))}",
            "ACFS_MODULE_VERIFY_RUN_AS[agents.opencode]=current",
            "ACFS_MODULE_FAMILIES[agents.opencode]=arch" if not applicable else "",
            "state_init",
            "state_phase_complete agents",
            'cp "$ACFS_STATE_FILE" "$TEST_ROOT/before.json"',
            "fixture_install() {",
            '    printf "install\\n" >> "$TEST_ROOT/trace"',
            '    : > "$TEST_ROOT/ready"' if repair else "    :",
            "}",
            "for attempt in 1 2; do",
            "    status=0",
            "    run_phase agents 'Coding Agents' fixture_install || status=$?",
            '    printf "%s\\n" "$status" >> "$TEST_ROOT/statuses"',
            "done",
        ])
        (folder / "fixture.sh").write_text(script + "\n")
        result = subprocess.run(
            ["/bin/bash", "-p", "-c", script], text=True, capture_output=True,
            stdin=subprocess.DEVNULL, env=clean_environment(home), timeout=10)
        (folder / "output.log").write_text(result.stdout + result.stderr)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        trace = (folder / "trace").read_text().splitlines() if (folder / "trace").exists() else []
        statuses = list(map(int, (folder / "statuses").read_text().splitlines()))
        state = json.loads((home / ".acfs/state.json").read_text())
        before = json.loads((folder / "before.json").read_text())
        self.assertEqual(state["module_selection"], before["module_selection"])
        return trace, statuses, state

    def test_failed_optional_selection_is_retried_once_then_live_verified(self):
        for saved in (False, True):
            with self.subTest(saved_scope=saved):
                trace, statuses, state = self.run_phase_resume(saved=saved)
                self.assertEqual(trace, ["probe", "install", "probe"])
                self.assertEqual(statuses, [0, 0])
                self.assertEqual(state["phase_attempts"]["agents"], 1)

    def test_optional_retry_failure_stays_nonfatal_and_retryable(self):
        trace, statuses, state = self.run_phase_resume(repair=False)
        self.assertEqual(trace, ["probe", "install", "probe", "install"])
        self.assertEqual(statuses, [0, 0])
        self.assertIn("agents", state["completed_phases"])
        self.assertEqual(state["phase_attempts"]["agents"], 2)
        self.assertIsNone(state["failed_phase"])

    def test_explicit_optional_request_still_fails_if_repair_does_not_work(self):
        trace, statuses, state = self.run_phase_resume(repair=False, requested=True)
        self.assertEqual(trace.count("install"), 2)
        self.assertEqual(statuses, [1, 1])
        self.assertNotIn("agents", state["completed_phases"])
        self.assertEqual(state["failed_phase"], "agents")

    def test_healthy_optional_selection_does_not_reinstall(self):
        trace, statuses, _ = self.run_phase_resume(healthy=True)
        self.assertEqual(trace, ["probe", "probe"])
        self.assertEqual(statuses, [0, 0])

    def test_excluded_inapplicable_and_soft_only_modules_do_not_force_reinstalls(self):
        for options in ({"selected": False}, {"applicable": False}, {"soft_only": True}):
            with self.subTest(options=options):
                trace, statuses, _ = self.run_phase_resume(**options)
                self.assertEqual(trace, [])
                self.assertEqual(statuses, [0, 0])


class TargetedPhaseRecoveryTests(unittest.TestCase):
    """A narrow repair must not certify a different failed selected module."""

    @classmethod
    def setUpClass(cls):
        for executable in ("bash", "flock", "jq", "timeout"):
            if shutil.which(executable) is None:
                raise unittest.SkipTest(f"{executable} is required")
        installer = Path(os.environ.get("ACFS_INSTALLER_MAIN_TEST_SOURCE", ROOT / "install.sh"))
        cls.verify_phase = _main_fixture.definition(installer.read_text(), "acfs_verify_phase")

    def run_repair(self, *, previous="agents.codex", healthy=False, requested=False,
                   legacy=False, selector="only", current_failure=False, alter=""):
        folder = Path(tempfile.mkdtemp(prefix="acfs-targeted-phase-recovery-"))
        home = folder / "home"
        home.mkdir()
        for module in ("agents.claude", previous):
            probe = folder / module
            probe.write_text(
                "#!/bin/bash\n"
                f"printf '%s\\n' {shlex.quote('probe:' + module)} >> {shlex.quote(str(folder / 'trace'))}\n"
                + ("exit 0\n" if module == "agents.claude" else
                   f"test -f {shlex.quote(str(folder / 'previous-ready'))}\n"))
            probe.chmod(0o755)
        if healthy:
            (folder / "previous-ready").touch()
        helpers = Path(os.environ.get(
            "ACFS_INSTALL_HELPERS_TEST_SOURCE", ROOT / "scripts/lib/install_helpers.sh"))
        script = [
            "set -euo pipefail",
            f"source {shlex.quote(str(helpers))}",
            f"source {shlex.quote(str(STATE))}",
            f"source {shlex.quote(str(ROOT / 'scripts/generated/manifest_index.sh'))}",
            self.verify_phase,
            f"export TEST_ROOT={shlex.quote(str(folder))}",
            'export TARGET_HOME="$HOME" ACFS_HOME="$HOME/.acfs"',
            'export TARGET_USER="$(id -un)" ACFS_STATE_FILE="$ACFS_HOME/state.json"',
            "ACFS_VERSION=fixture; MODE=safe; HAS_GUM=false; ACFS_DISTRO_FAMILY=ubuntu",
            "state_getent_passwd_entry() { printf '%s:x:1000:1000::%s:/bin/bash\\n' \"$TARGET_USER\" \"$TARGET_HOME\"; }",
            f"ACFS_EFFECTIVE_PLAN=(agents.claude {previous})",
            "ACFS_PLAN_REASON=()",
            f"ACFS_PLAN_REASON[{previous}]='explicitly requested'" if requested else "",
        ]
        for module in ("agents.claude", previous):
            script.extend([
                f"ACFS_MODULE_VERIFY_COUNT[{module}]=1",
                f"ACFS_MODULE_VERIFY_COMMAND[{module}.0]={shlex.quote(shlex.quote(str(folder / module)))}",
                f"ACFS_MODULE_VERIFY_RUN_AS[{module}]=current",
            ])
        script.extend([
            "state_init",
            "state_update 'del(.module_selection)'" if legacy else "",
            "state_phase_start agents",
            "state_step_result agents 'Prior install failure' failed true 'previous required payload is missing'",
            alter,
            'cp "$ACFS_STATE_FILE" "$TEST_ROOT/before.json"',
            "ACFS_PLAN_REASON=([agents.claude]='explicitly requested')",
            "ACFS_EFFECTIVE_PLAN=(agents.claude)" if selector not in ("full", "full-profile") else
            f"ACFS_EFFECTIVE_PLAN=(agents.claude {previous})",
            "ONLY_MODULES=(agents.claude)" if selector in ("only", "profile") else "ONLY_MODULES=()",
            f"SKIP_MODULES=({previous})" if selector == "skip" else "SKIP_MODULES=()",
            "SKIP_TAGS=(fixture-previous)" if selector == "skip-tag" else "SKIP_TAGS=()",
            "SKIP_CATEGORIES=(fixture-previous)" if selector == "skip-category" else "SKIP_CATEGORIES=()",
            f"ACFS_MODULE_TAGS[{previous}]=fixture-previous" if selector == "skip-tag" else "",
            f"ACFS_MODULE_CATEGORY[{previous}]=fixture-previous" if selector == "skip-category" else "",
            "ACFS_CLI_PROFILE=minimal" if selector == "profile" else
            "ACFS_CLI_PROFILE=full" if selector == "full-profile" else "ACFS_CLI_PROFILE=''",
            'declare -p ACFS_EFFECTIVE_PLAN ACFS_PLAN_REASON > "$TEST_ROOT/selection-before"',
            "fixture_install() {",
            '    printf "install:agents.claude\\n" >> "$TEST_ROOT/trace"',
            "    state_step_result agents 'Current install failure' failed true 'current attempt failed'"
            if current_failure else "    :",
            "}",
            "status=0",
            "run_phase agents 'Coding Agents' fixture_install || status=$?",
            'printf "%s\\n" "$status" > "$TEST_ROOT/status"',
            'declare -p ACFS_EFFECTIVE_PLAN ACFS_PLAN_REASON > "$TEST_ROOT/selection-after"',
        ])
        source = "\n".join(script) + "\n"
        (folder / "fixture.sh").write_text(source)
        result = subprocess.run(
            ["/bin/bash", "-p", "-c", source], text=True, capture_output=True,
            stdin=subprocess.DEVNULL, env=clean_environment(home), timeout=10)
        (folder / "output.log").write_text(result.stdout + result.stderr)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((folder / "selection-after").read_bytes(),
                         (folder / "selection-before").read_bytes())
        state = json.loads((home / ".acfs/state.json").read_text())
        before = json.loads((folder / "before.json").read_text())
        self.assertEqual(state.get("module_selection"), before.get("module_selection"))
        trace = (folder / "trace").read_text().splitlines()
        self.assertEqual([event for event in trace if event.startswith("install:")],
                         ["install:agents.claude"])
        return int((folder / "status").read_text()), trace, state

    def assert_failure_preserved(self, status, state):
        self.assertEqual(status, 1)
        self.assertNotIn("agents", state["completed_phases"])
        self.assertIn("agents", state["partial_phases"])
        prior = state["phase_steps"]["agents"]["Prior install failure"]
        self.assertEqual(prior["status"], "failed")
        self.assertEqual(prior["error"], "previous required payload is missing")
        self.assertNotIn("verified_at", prior)

    def test_narrow_repair_cannot_clear_another_selected_required_failure(self):
        status, trace, state = self.run_repair()
        self.assert_failure_preserved(status, state)
        self.assertIn("probe:agents.codex", trace)

    def test_cumulative_live_verification_can_resolve_an_earlier_failure(self):
        status, trace, state = self.run_repair(healthy=True)
        self.assertEqual(status, 0)
        self.assertIn("probe:agents.codex", trace)
        self.assertIn("agents", state["completed_phases"])
        self.assertIsNone(state["failed_phase"])
        prior = state["phase_steps"]["agents"]["Prior install failure"]
        self.assertEqual(prior["status"], "verified")
        self.assertEqual(prior["error"], "previous required payload is missing")

    def test_saved_explicit_optional_failure_is_still_required(self):
        status, trace, state = self.run_repair(previous="agents.opencode", requested=True)
        self.assert_failure_preserved(status, state)
        self.assertIn("probe:agents.opencode", trace)

    def test_current_attempt_failure_is_never_reconciled_by_other_live_probes(self):
        status, trace, state = self.run_repair(healthy=True, current_failure=True)
        self.assert_failure_preserved(status, state)
        self.assertEqual(state["phase_steps"]["agents"]["Current install failure"]["status"], "failed")
        self.assertFalse(any(event.startswith("probe:") for event in trace), trace)

    def test_legacy_narrow_repairs_retain_unproven_earlier_failures(self):
        for selector in ("only", "skip", "skip-tag", "skip-category", "profile"):
            with self.subTest(selector=selector):
                status, trace, state = self.run_repair(legacy=True, selector=selector)
                self.assert_failure_preserved(status, state)
                self.assertNotIn("probe:agents.codex", trace)

    def test_legacy_full_phase_verification_can_still_recover(self):
        for selector in ("full", "full-profile"):
            with self.subTest(selector=selector):
                status, trace, state = self.run_repair(legacy=True, selector=selector, healthy=True)
                self.assertEqual(status, 0)
                self.assertIn("probe:agents.codex", trace)
                self.assertEqual(state["phase_steps"]["agents"]["Prior install failure"]["status"], "verified")

    def test_inapplicable_required_module_cannot_certify_an_earlier_failure(self):
        status, trace, state = self.run_repair(
            healthy=True, alter="ACFS_MODULE_FAMILIES[agents.codex]=arch")
        self.assert_failure_preserved(status, state)
        self.assertNotIn("probe:agents.codex", trace)

    def test_incomplete_manifest_metadata_cannot_certify_an_earlier_failure(self):
        for mapping in ("ACFS_MODULE_PHASE", "ACFS_MODULE_OPTIONAL"):
            with self.subTest(mapping=mapping):
                status, trace, state = self.run_repair(
                    healthy=True, alter=f"unset '{mapping}[agents.codex]'")
                self.assert_failure_preserved(status, state)
                self.assertNotIn("probe:agents.codex", trace)

    def test_invalid_cumulative_selection_never_certifies_previous_failures(self):
        for expression in (
                '.module_selection.selected_modules += ["retired.tool"]',
                '.module_selection.schema_version = 2',
                '.module_selection.requested_modules = ["agents.opencode"]'):
            with self.subTest(expression=expression):
                status, trace, state = self.run_repair(
                    healthy=True, alter="state_update " + shlex.quote(expression))
                self.assert_failure_preserved(status, state)
                self.assertNotIn("probe:agents.codex", trace)


class ScopedInstallerResumeTests(unittest.TestCase):
    BASE_SCOPE = ("base.system", "users.ubuntu", "lang.bun")

    @classmethod
    def setUpClass(cls):
        _main_fixture.MainUpgradeOrderTests.setUpClass()
        cls.harness = _main_fixture.MainUpgradeOrderTests(methodName="runTest")

    def run_scoped(self, arguments=(), *, modules=None, requested=("lang.bun",),
                   alter="", custom=False, completed=True, options=None, execution="", with_cleanup=False):
        modules = self.BASE_SCOPE if modules is None else modules
        installer = (ROOT / "install.sh").read_text()
        setup = [
            f"builtin source {shlex.quote(str(ROOT / 'scripts/lib/install_helpers.sh'))}",
            f"builtin source {shlex.quote(str(STATE))}",
            f"builtin source {shlex.quote(str(ROOT / 'scripts/generated/manifest_index.sh'))}",
            _main_fixture.definitions(installer, [
                "parse_args", "append_comma_or_space_separated"]),
            "ACFS_VERSION=fixture; MODE=safe; HAS_GUM=false",
            "ACFS_FORCE_RESUME=false; ACFS_FORCE_REINSTALL=false; ACFS_INTERACTIVE=false",
            "SKIP_POSTGRES=false; SKIP_VAULT=false; SKIP_CLOUD=false",
            "ACFS_CLI_PROFILE=''; ACFS_SELECTED_PROFILE=''; NO_DEPS=false",
            "declare -a ONLY_MODULES=() ONLY_PHASES=() SKIP_MODULES=()",
            "ACFS_SAVED_SELECTION_ACTIVE=false",
            "declare -a ACFS_SAVED_SELECTION_MODULES=() ACFS_SAVED_REQUESTED_MODULES=()",
            'export ACFS_STATE_FILE="$ACFS_HOME/state.json"',
            # Isolate NSS at the fixture account boundary; checkpoint parsing,
            # selector closure, initialization, locks and persistence are real.
            r'''state_getent_passwd_entry() { printf 'ubuntu:x:1000:1000::%s:/bin/bash\n' "$TARGET_HOME"; }''',
            "ACFS_EFFECTIVE_PLAN=(" + " ".join(map(shlex.quote, modules)) + ")",
            "ACFS_PLAN_REASON=()",
        ]
        setup += [f"ACFS_PLAN_REASON[{shlex.quote(module)}]='explicitly requested'"
                  for module in requested]
        setup += [
            "state_init",
            "state_phase_complete languages" if completed else "",
            # A new installer process starts with its own default mode.
            "MODE=vibe; ACFS_MODE_EXPLICIT=false",
            "ACFS_EFFECTIVE_PLAN=(); ACFS_PLAN_REASON=()",
            'cp "$ACFS_STATE_FILE" "$TEST_ROOT/custom-state.json"\n'
            'ACFS_STATE_FILE="$TEST_ROOT/custom-state.json"' if custom else "",
            alter,
            'cp "$ACFS_STATE_FILE" "$TEST_ROOT/checkpoint-before.json"',
            r'''
confirm_or_exit() { trace approved; }
ensure_base_deps() { trace mut:base; }
record_scope() {
    trace "mode:$MODE"
    local module
    local -a required=()
    for module in "${ACFS_EFFECTIVE_PLAN[@]}"; do
        if acfs_module_explicitly_selected "$module"; then required+=("$module"); fi
    done
    trace "resolved:$(jq -cn --args '$ARGS.positional' "${ACFS_EFFECTIVE_PLAN[@]}")"
    trace "required:$(jq -cn --args '$ARGS.positional' "${required[@]}")"
}
print_execution_plan() { record_scope; }
acfs_verify_phase() { record_scope; exit 0; }
''',
            execution,
        ]
        if with_cleanup:
            # Exercise the production EXIT handler and its real checkpoint
            # writes. Keep network and notification destinations inside the fixture.
            setup += [_main_fixture.definitions(installer, ["cleanup", "print_resume_hint"]), r'''
BOOTSTRAP_ARCHIVE_FD=""
acfs_bootstrap_dir_is_owned_temp() { return 1; }
acfs_file_is_owned_temp() { return 1; }
generate_resume_hint() { echo "fixture resume"; }
acfs_summary_emit() { trace failure_summary; }
webhook_notify() { trace failure_webhook; }
acfs_notify_install_failure() { trace failure_notification; }
acfs_release_install_lock() { trace released_lock; }
acfs_log_close() { :; }
trap cleanup EXIT
''']
        return self.harness.run_main(
            overrides={"TEST_MISSING_TOOLS": "false", **(options or {})},
            arguments=arguments, extra="\n".join(setup))

    def scope_event(self, events, name):
        values = [event[len(name) + 1:] for event in events if event.startswith(name + ":")]
        self.assertEqual(len(values), 1, events)
        return json.loads(values[0])

    def assert_unchanged(self, folder, *, custom=False):
        checkpoint = folder / "custom-state.json" if custom else folder / "home/.acfs/state.json"
        self.assertEqual(checkpoint.read_bytes(), (folder / "checkpoint-before.json").read_bytes())

    def test_no_selector_retry_and_force_preserve_scope_even_before_first_completed_phase(self):
        for completed in (False, True):
            for arguments in ((), ("--resume",), ("--force-reinstall",)):
                with self.subTest(completed=completed, arguments=arguments):
                    result, events, folder = self.run_scoped(arguments, completed=completed)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(self.scope_event(events, "resolved"), list(self.BASE_SCOPE))
                    self.assertEqual(self.scope_event(events, "required"), ["lang.bun"])
                    selection = json.loads((folder / "home/.acfs/state.json").read_text())["module_selection"]
                    self.assertEqual(selection["selected_modules"], list(self.BASE_SCOPE))
                    self.assertEqual(selection["requested_modules"], ["lang.bun"])

    def test_saved_no_deps_scope_survives_retry_force_and_readonly_preview(self):
        for arguments in ((), ("--resume",), ("--force-reinstall",),
                          ("--print-plan",), ("--dry-run",)):
            with self.subTest(arguments=arguments):
                # This is the persisted result of --only agents.codex --no-deps.
                # The next invocation has its normal NO_DEPS=false default.
                result, events, folder = self.run_scoped(
                    arguments, modules=("agents.codex",),
                    requested=("agents.codex",), completed=False)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.scope_event(events, "resolved"), ["agents.codex"])
                self.assertEqual(self.scope_event(events, "required"), ["agents.codex"])
                selection = json.loads((folder / "home/.acfs/state.json").read_text())["module_selection"]
                self.assertEqual(selection["selected_modules"], ["agents.codex"])
                self.assertEqual(selection["requested_modules"], ["agents.codex"])
                self.assertIn("outside the saved installation", result.stderr)
                self.assertIn("agents.codex -> lang.bun", result.stderr)
                if arguments in (("--print-plan",), ("--dry-run",)):
                    self.assert_unchanged(folder)
                    self.assertFalse(any(event.startswith("mut:") for event in events), events)

    def test_saved_scope_does_not_silently_add_new_manifest_dependencies(self):
        for arguments in (("--resume",), ("--force-reinstall",)):
            with self.subTest(arguments=arguments):
                result, events, folder = self.run_scoped(
                    arguments, alter="ACFS_MODULE_DEPS[lang.bun]+=,lang.go")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.scope_event(events, "resolved"), list(self.BASE_SCOPE))
                self.assertIn("lang.bun -> lang.go", result.stderr)
                selection = json.loads((folder / "home/.acfs/state.json").read_text())["module_selection"]
                self.assertEqual(selection["selected_modules"], list(self.BASE_SCOPE))

    def test_print_reports_selected_installer_sources_and_preserves_checkpoint(self):
        installer = (ROOT / "install.sh").read_text()
        preview = _main_fixture.definitions(installer, [
            "print_installer_sources", "acfs_load_upstream_checksums",
            "acfs_parse_checksums_content", "acfs_validate_upstream_checksums",
            "acfs_required_upstream_tools"])
        preview += "\nACFS_UPSTREAM_LOADED=false; declare -A ACFS_UPSTREAM_URLS=() ACFS_UPSTREAM_SHA256=()"
        policy = ROOT / "checksums.yaml"
        preview += "\nACFS_CHECKSUMS_YAML=" + shlex.quote(str(policy))
        for args, selected, omitted in (
            (("--print",), "bun", "uv"),
            (("--print", "--only", "lang.uv"), "uv", "bun"),
        ):
            with self.subTest(args=args):
                result, events, folder = self.run_scoped(args, execution=preview)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("mode: safe", result.stdout)
                self.assertIn("base.system — ", result.stdout)
                self.assertIn(f"lang.{selected} — ", result.stdout)
                self.assertNotIn(f"lang.{omitted} — ", result.stdout)
                entry = policy.read_text().split(f"  {selected}:\n", 1)[1].splitlines()
                url, pin = [line.split('"')[1] for line in entry[:2]]
                self.assertIn(f"Installer: {url}\n  SHA-256: {pin}", result.stdout)
                self.assertNotIn("preflight", events)
                self.assert_unchanged(folder)

    def test_explicit_choices_can_expand_a_saved_no_deps_installation(self):
        cases = (
            ("--only", "agents.codex"),
            ("--only-phase", "agents"),
            ("--profile", "full"),
        )
        for arguments in cases:
            with self.subTest(arguments=arguments):
                result, events, folder = self.run_scoped(
                    arguments, modules=("agents.codex",), requested=("agents.codex",))
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                scope = self.scope_event(events, "resolved")
                for module in (*self.BASE_SCOPE, "agents.codex"):
                    self.assertIn(module, scope)
                self.assertNotIn("outside the saved installation", result.stderr)
                selection = json.loads((folder / "home/.acfs/state.json").read_text())["module_selection"]
                self.assertEqual(set(selection["selected_modules"]), set(scope))
                self.assertIn("agents.codex", selection["requested_modules"])

    def test_saved_scope_still_refuses_explicit_dependency_skips(self):
        result, events, folder = self.run_scoped(
            ("--resume", "--skip", "lang.bun"),
            modules=("agents.codex",), requested=("agents.codex",))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("agents.codex depends on skipped lang.bun", result.stderr)
        self.assertFalse(any(event.startswith("mut:") for event in events), events)
        self.assert_unchanged(folder)

    def test_saved_scope_does_not_hide_unknown_dependency_metadata(self):
        result, events, folder = self.run_scoped(
            ("--resume",), alter="ACFS_MODULE_DEPS[lang.bun]=lang.missing")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("lang.bun depends on unknown module lang.missing", result.stderr)
        self.assertFalse(any(event.startswith("mut:") for event in events), events)
        self.assert_unchanged(folder)

    def test_explicit_module_phase_and_profile_requests_can_expand_the_installation(self):
        cases = (
            (("--only", "agents.grok"), "agents.grok", ["agents.grok"]),
            (("--only-phase", "agents"), "agents.codex", []),
            (("--profile", "full"), "stack.ntm", []),
        )
        for arguments, included, required in cases:
            with self.subTest(arguments=arguments):
                result, events, folder = self.run_scoped(arguments)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(included, self.scope_event(events, "resolved"))
                self.assertEqual(self.scope_event(events, "required"), required)
                selection = json.loads((folder / "home/.acfs/state.json").read_text())["module_selection"]
                self.assertIn("lang.bun", selection["selected_modules"])
                self.assertIn(included, selection["selected_modules"])

    def test_saved_optional_roots_stay_required_but_unrecorded_requirements_are_not_invented(self):
        modules = (*self.BASE_SCOPE, "agents.grok")
        for arguments in (("--resume",), ("--force-reinstall",)):
            result, events, _ = self.run_scoped(arguments, modules=modules, requested=("agents.grok",))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(self.scope_event(events, "required"), ["agents.grok"])
        result, events, _ = self.run_scoped(
            ("--resume",), modules=modules, requested=(),
            alter="state_update 'del(.module_selection.requested_modules)'")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("agents.grok", self.scope_event(events, "resolved"))
        self.assertEqual(self.scope_event(events, "required"), [])

    def test_skip_filters_saved_scope_without_expanding_or_erasing_cumulative_intent(self):
        for flag in ("--resume", "--force-reinstall"):
            result, events, folder = self.run_scoped(
                (flag, "--skip", "agents.grok"), modules=(*self.BASE_SCOPE, "agents.grok"),
                requested=("agents.grok",))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(self.scope_event(events, "resolved"), list(self.BASE_SCOPE))
            self.assertEqual(self.scope_event(events, "required"), [])
            selection = json.loads((folder / "home/.acfs/state.json").read_text())["module_selection"]
            self.assertIn("agents.grok", selection["selected_modules"])
            self.assertEqual(selection["requested_modules"], ["agents.grok"])

    def test_invalid_or_foreign_checkpoints_stop_before_upgrade_packages_or_state_changes(self):
        cases = (
            ("empty", "state_update '.module_selection.selected_modules = []'", False),
            ("unknown", 'state_update \'.module_selection.selected_modules += ["stack.unknown"]\'', False),
            ("orphan-request", 'state_update \'.module_selection.requested_modules = ["agents.grok"]\'', False),
            ("broken", r'''printf '{"module_selection":' > "$ACFS_STATE_FILE"''', False),
            ("foreign-default", 'state_update \'.target_home = "/another/home"\'', False),
            ("foreign-custom", 'state_update \'.target_user = "someone_else"\'', True),
            ("null-identity", "state_update '.target_user = null'", False),
            ("invalid-mode", "state_update '.mode = null'", False),
        )
        for name, alter, custom in cases:
            for flag in ("--resume", "--force-reinstall"):
                with self.subTest(case=name, flag=flag):
                    result, events, folder = self.run_scoped(
                        (flag,), alter=alter, custom=custom, with_cleanup=True,
                        options={"TARGET_UBUNTU_VERSION_EXPLICIT": "true"})
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertFalse(any(event.startswith("mut:") for event in events), events)
                    self.assertNotIn("upgrade", events)
                    self.assertNotIn("install_lock", events)
                    self.assertFalse(any(event.startswith("failure_") for event in events), events)
                    self.assert_unchanged(folder, custom=custom)

    def test_second_installer_cannot_report_failure_or_interrupt_the_active_run(self):
        for signal_name in ("", "INT"):
            with self.subTest(signal_name=signal_name):
                result, events, folder = self.run_scoped(
                    ("--resume",), with_cleanup=True, execution=r'''
printf 'active run\n' > "$ACFS_HOME/.install.lock"
exec 195>>"$ACFS_HOME/.install.lock"
flock -xn 195
acfs_attach_to_running_install() { trace watching; return 1; }
''' + f"_ACFS_SIGNAL_RECEIVED={shlex.quote(signal_name)}")
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("watching", events)
                self.assertNotIn("install_lock", events)
                self.assertFalse(any(event.startswith("failure_") for event in events), events)
                self.assert_unchanged(folder)
                self.assertEqual((folder / "home/.acfs/.install.lock").read_text(), "active run\n")

    def test_installer_uses_the_scope_present_at_lock_acquisition(self):
        result, events, _ = self.run_scoped(("--resume",), execution=r'''
acfs_remember_install_lock() {
    trace install_lock
    state_update '.module_selection.selected_modules += ["agents.codex"]'
}
''')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("agents.codex", self.scope_event(events, "resolved"))

    def test_valid_custom_checkpoint_and_legacy_full_install_remain_supported(self):
        result, events, _ = self.run_scoped(("--resume",), custom=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.scope_event(events, "resolved"), list(self.BASE_SCOPE))
        result, events, folder = self.run_scoped(
            ("--resume",), alter="state_update 'del(.module_selection, .target_home, .target_user)'")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("stack.ntm", self.scope_event(events, "resolved"))
        self.assertNotIn("module_selection", json.loads((folder / "home/.acfs/state.json").read_text()))

    def test_reset_moves_only_the_requested_custom_checkpoint(self):
        result, _, folder = self.run_scoped(("--reset-state",), custom=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_unchanged(folder)
        self.assertFalse((folder / "custom-state.json").exists())
        backups = list(folder.glob("custom-state.json.backup.*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), (folder / "checkpoint-before.json").read_bytes())

    def test_reset_rejects_foreign_custom_checkpoint(self):
        result, events, folder = self.run_scoped(("--reset-state",), custom=True, with_cleanup=True,
                                            alter="""state_update '.target_user = "other"'""")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("released_lock", events)
        self.assertFalse(any(event.startswith("failure_") for event in events), events)
        self.assert_unchanged(folder, custom=True)
        self.assertTrue((folder / "home/.acfs/state.json").is_file())
        self.assertEqual(list(folder.rglob("*.backup.*")), [])

    def test_reset_recovers_damaged_default_without_replacing_an_earlier_backup(self):
        result, _, folder = self.run_scoped(
            ("--reset-state",), alter=r'''
printf 'truncated checkpoint' > "$ACFS_STATE_FILE"
printf 'prior recovery' > "$ACFS_STATE_FILE.backup.20261124_000000"
date() { if [[ "$1" == +%Y%m%d_%H%M%S ]]; then echo 20261124_000000; else command date "$@"; fi; }
''')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        checkpoint = folder / "home/.acfs/state.json"
        self.assertFalse(checkpoint.exists())
        backups = checkpoint.parent.glob("state.json.backup.*")
        self.assertCountEqual([file.read_bytes() for file in backups],
                              [b"prior recovery", b"truncated checkpoint"])

    def test_reset_respects_the_custom_checkpoint_writer_lock(self):
        result, events, folder = self.run_scoped(
            ("--reset-state",), custom=True, with_cleanup=True, execution=r'''
exec 195>>"$ACFS_STATE_FILE.lock"
flock -xn 195
ACFS_STATE_LOCK_TIMEOUT=1
_ACFS_SIGNAL_RECEIVED=TERM
''')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("released_lock", events)
        self.assertFalse(any(event.startswith("failure_") for event in events), events)
        self.assert_unchanged(folder, custom=True)
        self.assertEqual(list(folder.rglob("*.backup.*")), [])

    def test_readonly_flags_cannot_move_a_checkpoint_in_either_argument_order(self):
        for flag in ("--dry-run", "--print"):
            for arguments in (("--reset-state", flag), (flag, "--reset-state")):
                with self.subTest(arguments=arguments):
                    result, events, folder = self.run_scoped(arguments, with_cleanup=True)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("--reset-state", result.stderr)
                    self.assertNotIn("install_lock", events)
                    self.assertIn("released_lock", events)
                    self.assertFalse(any(event.startswith("failure_") for event in events), events)
                    self.assert_unchanged(folder)
                    self.assertEqual(list(folder.rglob("*.backup.*")), [])

    def test_install_failure_still_saves_the_resume_hint_and_notifies(self):
        result, events, folder = self.run_scoped(
            ("--resume",), with_cleanup=True, execution="ensure_base_deps() { return 37; }")
        self.assertEqual(result.returncode, 37, result.stdout + result.stderr)
        checkpoint = json.loads((folder / "home/.acfs/state.json").read_text())
        self.assertEqual(checkpoint["resume_hint"], "fixture resume")
        for event in ("failure_summary", "failure_webhook", "failure_notification", "released_lock"):
            self.assertIn(event, events)

    def test_saved_scope_previews_match_execution_without_privileges_or_checkpoint_writes(self):
        for flag in ("--print-plan", "--dry-run"):
            result, events, folder = self.run_scoped((flag,))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(self.scope_event(events, "resolved"), list(self.BASE_SCOPE))
            self.assertEqual(self.scope_event(events, "required"), ["lang.bun"])
            self.assertFalse(any(event.startswith("mut:") for event in events), events)
            for event in ("root", "user", "paths", "install_lock", "upgrade"):
                self.assertNotIn(event, events)
            self.assert_unchanged(folder)

    def test_damaged_or_unresolvable_preview_warns_and_keeps_readonly_inspection_available(self):
        for alter in ("state_update '.module_selection.selected_modules = []'",
                      "TARGET_USER='invalid user'"):
            for flag in ("--print-plan", "--dry-run"):
                with self.subTest(alter=alter, flag=flag):
                    result, events, folder = self.run_scoped((flag,), alter=alter)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("fallback manifest plan", result.stderr)
                    self.assertIn("stack.ntm", self.scope_event(events, "resolved"))
                    self.assertFalse(any(event.startswith("mut:") for event in events), events)
                    self.assertNotIn("root", events)
                    self.assert_unchanged(folder)


    def test_saved_safe_mode_survives_retry_force_and_explicit_selection(self):
        for arguments in ((), ("--resume",), ("--force-reinstall",),
                          ("--only", "agents.grok"), ("--only-phase", "agents"),
                          ("--profile", "full")):
            with self.subTest(arguments=arguments):
                result, events, folder = self.run_scoped(arguments)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("mode:safe", events)
                checkpoint = json.loads((folder / "home/.acfs/state.json").read_text())
                self.assertEqual(checkpoint["mode"], "safe")

    def test_explicit_cli_and_profile_modes_override_saved_policy_and_are_recorded(self):
        cases = (
            (("--resume", "--mode", "vibe"), "", "vibe"),
            (("--resume", "--mode", "safe"), 'state_update \'.mode = "vibe"\'', "safe"),
            (("--profile", "vibe"), "", "vibe"),
            (("--profile", "safe"), 'state_update \'.mode = "vibe"\'', "safe"),
        )
        for arguments, alter, expected in cases:
            with self.subTest(arguments=arguments):
                result, events, folder = self.run_scoped(arguments, alter=alter)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(f"mode:{expected}", events)
                checkpoint = json.loads((folder / "home/.acfs/state.json").read_text())
                self.assertEqual(checkpoint["mode"], expected)

    def test_legacy_safe_policy_is_restored_and_absent_policy_uses_default(self):
        for alter, expected in (
                ("state_update 'del(.module_selection)'", "safe"),
                ("state_update 'del(.mode)'", "vibe")):
            with self.subTest(alter=alter):
                result, events, folder = self.run_scoped(("--resume",), alter=alter)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(f"mode:{expected}", events)
                checkpoint = json.loads((folder / "home/.acfs/state.json").read_text())
                self.assertEqual(checkpoint["mode"], expected)
                if expected == "safe":
                    self.assertNotIn("module_selection", checkpoint)

    def test_reviewed_default_plan_is_not_replaced_by_the_previous_scoped_checkpoint(self):
        result, events, _ = self.run_scoped(("--print-plan", "--profile", "full"))
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = self.scope_event(events, "resolved")
        self.assertIn("stack.ntm", expected)
        for additional in ((), ("--yes",)):
            with self.subTest(additional=additional):
                result, events, folder = self.run_scoped(
                    ("--interactive-resume", "--mode", "safe", "--print-plan", *additional),
                    options={"YES_MODE": "false"})
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.scope_event(events, "resolved"), expected)
                self.assertNotIn("interactive", events)
                self.assert_unchanged(folder)

    def test_saved_and_explicit_modes_match_targeted_previews_without_state_writes(self):
        cases = (
            ((), "safe", "lang.bun"),
            (("--only", "agents.grok"), "safe", "agents.grok"),
            (("--profile", "full"), "safe", "stack.ntm"),
            (("--mode", "vibe"), "vibe", "lang.bun"),
            (("--profile", "vibe"), "vibe", "stack.ntm"),
        )
        for flag in ("--print-plan", "--dry-run"):
            for selectors, expected, included in cases:
                with self.subTest(flag=flag, selectors=selectors):
                    result, events, folder = self.run_scoped((flag, *selectors))
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn(f"mode:{expected}", events)
                    self.assertIn(included, self.scope_event(events, "resolved"))
                    self.assertFalse(any(event.startswith("mut:") for event in events), events)
                    for event in ("root", "user", "paths", "install_lock", "upgrade"):
                        self.assertNotIn(event, events)
                    self.assert_unchanged(folder)

    def test_mode_override_is_not_saved_when_resume_is_declined(self):
        # The approval boundary is inert; actual state reads and main ordering
        # still run, so an early mode write would alter the checkpoint.
        result, events, folder = self.run_scoped(
            ("--mode", "vibe"),
            alter='confirm_resume() { trace "declined-mode:$MODE"; return 2; }')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("declined-mode:vibe", events)
        self.assertNotIn("mut:base", events)
        self.assert_unchanged(folder)

    def test_expanded_selection_and_mode_survive_base_dependency_failure(self):
        for resume in ((), ("--resume",), ("--force-reinstall",)):
            with self.subTest(resume=resume):
                result, events, folder = self.run_scoped(
                    ("--yes", *resume, "--only", "agents.grok", "--mode", "vibe"),
                    execution="ensure_base_deps() { trace mut:base; exit 42; }")
                self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
                self.assertIn("mut:base", events)
                checkpoint = json.loads((folder / "home/.acfs/state.json").read_text())
                selection = checkpoint["module_selection"]
                self.assertTrue(set(self.BASE_SCOPE).issubset(selection["selected_modules"]))
                self.assertIn("agents.grok", selection["selected_modules"])
                self.assertEqual(set(selection["requested_modules"]),
                                 {"lang.bun", "agents.grok"})
                self.assertEqual(checkpoint["mode"], "vibe")

    def test_failed_selection_write_stops_before_base_dependencies(self):
        result, events, folder = self.run_scoped(
            ("--resume", "--only", "agents.grok"), execution=WRITE_FAILURE)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((folder / "home/.acfs/write-failed").exists())
        self.assertIn("Could not record the selected modules", result.stderr)
        self.assertNotIn("mut:base", events)
        self.assert_unchanged(folder)

    def test_declined_expansion_never_updates_saved_selection(self):
        result, events, folder = self.run_scoped(
            ("--only", "agents.grok", "--mode", "vibe"),
            execution='confirm_resume() { trace declined_expansion; return 2; }')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("declined_expansion", events)
        self.assertNotIn("mut:base", events)
        self.assert_unchanged(folder)

    def test_legacy_selection_remains_legacy_after_base_failure(self):
        result, events, folder = self.run_scoped(
            ("--resume", "--only", "agents.grok", "--mode", "vibe"),
            alter="state_update 'del(.module_selection)'",
            execution="ensure_base_deps() { trace mut:base; exit 42; }")
        self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
        self.assertIn("mut:base", events)
        checkpoint = json.loads((folder / "home/.acfs/state.json").read_text())
        self.assertNotIn("module_selection", checkpoint)
        self.assertEqual(checkpoint["mode"], "vibe")

    def test_fresh_selection_without_jq_can_reach_base_dependency_repair(self):
        result, events, folder = self.run_scoped(
            ("--yes", "--only", "agents.grok", "--mode", "safe"),
            options={"TEST_MISSING_TOOLS": "true"},
            execution='mv -- "$ACFS_STATE_FILE" "$TEST_ROOT/fixture-checkpoint.json"\n'
            + WITHOUT_JQ + '\nensure_base_deps() { trace mut:base; exit 42; }')
        self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
        self.assertIn("mut:base", events)
        self.assertNotIn("unexpected_jq", events)
        checkpoint = json.loads((folder / "home/.acfs/state.json").read_text())
        self.assertIn("agents.grok", checkpoint["module_selection"]["selected_modules"])
        self.assertEqual(checkpoint["module_selection"]["requested_modules"], ["agents.grok"])
        self.assertEqual(checkpoint["mode"], "safe")

    def test_approved_no_jq_recovery_preserves_scope_before_base_dependencies(self):
        result, events, folder = self.run_scoped(
            ("--yes", "--only", "agents.grok", "--mode", "vibe"),
            options={"TEST_MISSING_TOOLS": "true"},
            execution=WITHOUT_JQ + '\nensure_base_deps() { trace mut:base; exit 42; }')
        self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
        self.assertIn("mut:base", events)
        self.assertNotIn("unexpected_jq", events)
        checkpoint = json.loads((folder / "home/.acfs/state.json").read_text())
        selection = checkpoint["module_selection"]
        self.assertTrue(set(self.BASE_SCOPE).issubset(selection["selected_modules"]))
        self.assertIn("agents.grok", selection["selected_modules"])
        self.assertEqual(set(selection["requested_modules"]), {"lang.bun", "agents.grok"})
        self.assertEqual(checkpoint["mode"], "vibe")
        backups = list((folder / "home/.acfs").glob("state.json.backup.*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), (folder / "checkpoint-before.json").read_bytes())

    def test_no_jq_checkpoint_recovery_requires_readable_confirmation(self):
        result, events, folder = self.run_scoped(
            ("--resume", "--only", "agents.grok"),
            options={"YES_MODE": "false", "TEST_MISSING_TOOLS": "true"},
            execution=WITHOUT_JQ)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Cannot validate state safely without jq", result.stderr)
        self.assertNotIn("mut:base", events)
        self.assertNotIn("unexpected_jq", events)
        self.assert_unchanged(folder)

    def test_invalid_checkpoint_recovery_never_treats_missing_tty_as_consent(self):
        for damage in ("del(.version)", ".schema_version = 99", ".schema_version = 1"):
            with self.subTest(damage=damage):
                result, events, folder = self.run_scoped(
                    ("--resume",), options={"YES_MODE": "false"},
                    alter="state_update " + shlex.quote(damage))
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("State validation failed", result.stderr)
                self.assertNotIn("mut:base", events)
                self.assert_unchanged(folder)


class BaseDependencySelectionTests(unittest.TestCase):
    """Authored base installers must honor the same scope as generated ones."""

    BASE_SCOPE = ScopedInstallerResumeTests.BASE_SCOPE

    @classmethod
    def setUpClass(cls):
        ScopedInstallerResumeTests.setUpClass()
        cls.harness = ScopedInstallerResumeTests.harness
        cls.base_install = _main_fixture.definitions(
            _main_fixture.MAIN.read_text(), ["ensure_base_deps", "acfs_legacy_module_selected"])

    run_scoped = ScopedInstallerResumeTests.run_scoped
    scope_event = ScopedInstallerResumeTests.scope_event

    def run_base_install(self, family, arguments=(), *, modules=None,
                         alter="", packages_present=False, install_status=0):
        # Run the real main, checkpoint policy, selector and authored base
        # installer. Only host privileges, package queries and package writes
        # are replaced, so this never invokes the machine's package manager.
        execution = self.base_install + r'''
ACFS_USE_GENERATED_BASE=0
set_phase() { trace "phase:$1"; }
log_step() { :; }
try_step() { shift; "$@"; }
acfs_early_sudo_binary_path() { printf 'fixture_sudo\n'; }
fixture_sudo() { "$@"; }
fixture_pacman() {
    trace "query:pacman:$*"
    [[ "$FIXTURE_PACKAGES_PRESENT" == true ]]
}
fixture_apt() {
    trace "mut:apt:$*"
    return "$FIXTURE_INSTALL_STATUS"
}
acfs_arch_pkg_install() {
    trace "mut:pacman:$*"
    return "$FIXTURE_INSTALL_STATUS"
}
'''
        execution += f"\nFIXTURE_PACKAGES_PRESENT={'true' if packages_present else 'false'}"
        execution += f"\nFIXTURE_INSTALL_STATUS={install_status}"
        return self.run_scoped(
            arguments, modules=modules, requested=(), alter=alter,
            options={"ACFS_DISTRO_FAMILY": family}, execution=execution)

    def test_explicit_no_deps_selection_does_not_install_base_packages(self):
        for family in ("arch", "ubuntu"):
            for arguments in (("--only", "lang.bun", "--no-deps"),
                              ("--only", "lang.bun", "--skip", "base.system", "--no-deps")):
                with self.subTest(family=family, arguments=arguments):
                    result, events, _ = self.run_base_install(family, arguments)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(self.scope_event(events, "resolved"), ["lang.bun"])
                    self.assertFalse(any(event.startswith(("mut:apt:", "mut:pacman:", "query:pacman:"))
                                         for event in events), events)

    def test_saved_scope_omitting_base_packages_survives_retry_and_force(self):
        for family in ("arch", "ubuntu"):
            for arguments in ((), ("--resume",), ("--force-reinstall",)):
                with self.subTest(family=family, arguments=arguments):
                    result, events, _ = self.run_base_install(
                        family, arguments, modules=("agents.codex",))
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(self.scope_event(events, "resolved"), ["agents.codex"])
                    self.assertFalse(any(event.startswith(("mut:apt:", "mut:pacman:", "query:pacman:"))
                                         for event in events), events)

    def test_selected_dependency_and_legacy_full_install_still_install_base_packages(self):
        for family in ("arch", "ubuntu"):
            for arguments, alter in ((("--only", "lang.bun"), ""),
                                     ((), "state_update 'del(.module_selection)'")):
                with self.subTest(family=family, arguments=arguments):
                    result, events, _ = self.run_base_install(family, arguments, alter=alter)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("base.system", self.scope_event(events, "resolved"))
                    prefix = "mut:pacman:" if family == "arch" else "mut:apt:"
                    self.assertTrue(any(event.startswith(prefix) for event in events), events)

    def test_selected_base_install_failure_still_stops_the_installer(self):
        for family in ("arch", "ubuntu"):
            with self.subTest(family=family):
                result, events, _ = self.run_base_install(
                    family, ("--only", "lang.bun"), install_status=42)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                prefix = "mut:pacman:" if family == "arch" else "mut:apt:"
                self.assertTrue(any(event.startswith(prefix) for event in events), events)
                self.assertFalse(any(event.startswith("resolved:") for event in events), events)

    def test_existing_arch_base_packages_do_not_trigger_an_upgrade(self):
        result, events, _ = self.run_base_install(
            "arch", ("--only", "lang.bun"), packages_present=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(any(event.startswith("query:pacman:") for event in events), events)
        self.assertFalse(any(event.startswith("mut:pacman:") for event in events), events)


class SudoPolicyResumeTests(unittest.TestCase):
    """Run user-phase resume and atomic policy writes in a private /etc fixture."""

    @classmethod
    def setUpClass(cls):
        ResumeCheckpointGateTests.setUpClass()
        index = Path(os.environ.get("ACFS_USER_MANIFEST_INDEX_TEST_SOURCE",
                                    ROOT / "scripts/generated/manifest_index.sh"))
        probes = subprocess.check_output([
            "/bin/bash", "-p", "-euo", "pipefail", "-c",
            'source "$1"; for ((i=0; i<ACFS_MODULE_VERIFY_COUNT[users.ubuntu]; i++)); do '
            'printf "%s\\0" "${ACFS_MODULE_VERIFY_COMMAND[users.ubuntu.$i]}"; done',
            "_", str(index),
        ], env={"PATH": "/usr/bin:/bin"}, timeout=10)
        cls.checks = [probe.decode() for probe in probes.split(b"\0")[:-1]]
        installer = _main_fixture.MAIN.read_text()
        cls.installer = _main_fixture.definitions(installer, [
            "normalize_user", "acfs_install_sudoers_dropin", "acfs_verify_phase"],
            ["acfs_configure_sudo_policy"])

    def run_policy(self, mode, *, family="ubuntu", content=None, completed=False,
                   fail_validation=False, custom_kind=None, target_user="ubuntu",
                   stub_ubuntu_uid=True):
        folder = Path(tempfile.mkdtemp(prefix="acfs-sudo-policy-"))
        policy_dir = folder / "etc/sudoers.d"
        policy_dir.mkdir(parents=True)
        policy = policy_dir / ("90-acfs" if family == "arch" else "90-ubuntu-acfs")
        unrelated = policy_dir / "70-administrator"
        unrelated.write_text("operator ALL=(ALL) NOPASSWD:/usr/bin/id\n")
        (policy_dir / "90-acfs-wheel").write_text("%wheel ALL=(ALL:ALL) ALL\n")
        if content is not None:
            policy.write_text(content)
            policy.chmod(0o440)
        if custom_kind == "symlink":
            policy.symlink_to(unrelated)
        if custom_kind == "hardlink":
            os.link(unrelated, policy)
        if custom_kind == "directory":
            policy.mkdir()
        (folder / "bin").mkdir()
        # Privilege/account boundaries are inert. The actual file contents,
        # atomic writer, candidate validation ordering, selectors, checkpoint
        # and phase/resume verifiers run unchanged in the retained fixture.
        (folder / "bin/stat").write_text(
            "#!/bin/bash\nresult=$(/usr/bin/stat \"$@\") || exit $?\n"
            "printf '%s:%s\\n' \"${TEST_OWNER:-0}\" \"${result#*:}\"\n")
        (folder / "bin/visudo").write_text(
            "#!/bin/bash\nprintf 'validate\\n' >> \"$TEST_ROOT/events\"\n"
            "[[ \"${TEST_VISUDO_FAIL:-false}\" != true ]]\n")
        (folder / "bin/id").write_text(
            "#!/bin/bash\nif [[ \"$*\" == '-u ubuntu' ]]; then printf '42424\\n'; "
            "else /usr/bin/id \"$@\"; fi\n"
            if stub_ubuntu_uid else "#!/bin/bash\nexec /usr/bin/id \"$@\"\n")
        for path in (folder / "bin").iterdir():
            path.chmod(0o755)
        fixture_source = self.installer.replace("/etc/sudoers", str(folder / "etc/sudoers"))
        commands = [check.replace("/etc/sudoers", str(folder / "etc/sudoers")) for check in self.checks]
        script = "\n".join([
            "set -euo pipefail",
            f"export TEST_ROOT={shlex.quote(str(folder))}",
            f"export TARGET_HOME={shlex.quote(str(folder / 'home'))} TARGET_USER={shlex.quote(target_user)}",
            'mkdir -p "$TARGET_HOME"; export HOME="$TARGET_HOME" ACFS_HOME="$TARGET_HOME/.acfs"',
            'export ACFS_STATE_FILE="$ACFS_HOME/state.json"',
            f"source {shlex.quote(str(ROOT / 'scripts/lib/install_helpers.sh'))}",
            f"source {shlex.quote(str(STATE))}",
            "MODE=vibe; ACFS_VERSION=fixture; HAS_GUM=false; SUDO=''; DRY_RUN=false",
            f"ACFS_DISTRO_FAMILY={shlex.quote(family)}",
            "ACFS_MANIFEST_INDEX_LOADED=true; ACFS_GENERATED_SELECTION_READY=true",
            "declare -a ACFS_EFFECTIVE_PLAN=(users.ubuntu) ONLY_MODULES=() ONLY_PHASES=() SKIP_MODULES=()",
            "declare -A ACFS_EFFECTIVE_RUN=([users.ubuntu]=1) ACFS_PLAN_REASON=()",
            "declare -a ACFS_MODULES_IN_ORDER=(users.ubuntu)",
            "declare -A ACFS_MODULE_PHASE=([users.ubuntu]=2) ACFS_MODULE_OPTIONAL=([users.ubuntu]=0)",
            "declare -A ACFS_MODULE_FAMILIES=([users.ubuntu]='')",
            r'''state_getent_passwd_entry() { printf '%s:x:1000:1000::%s:/bin/bash\n' "$TARGET_USER" "$TARGET_HOME"; }''',
            "state_init",
            "state_phase_complete user_setup" if completed else "",
            fixture_source,
            f"MODE={shlex.quote(mode)}; state_record_module_selection users.ubuntu",
            f"declare -A ACFS_MODULE_VERIFY_COUNT=([users.ubuntu]={len(commands)})",
            "declare -A ACFS_MODULE_VERIFY_RUN_AS=([users.ubuntu]=root) ACFS_MODULE_VERIFY_COMMAND=()",
            *[f"ACFS_MODULE_VERIFY_COMMAND[users.ubuntu.{i}]={shlex.quote(check)}"
              for i, check in enumerate(commands)],
            r'''
set_phase() { :; }; log_step() { :; }; log_detail() { :; }; log_success() { :; }
try_step() { shift; "$@"; }
try_step_optional() { shift; "$@"; }
user_require_valid_target_user() { [[ "$1" =~ ^[a-z_][a-z0-9._-]*$ ]]; }
user_verify_local_account_identity() { return 0; }
acfs_chown_target_home() { return 0; }
acfs_use_generated_category() { return 1; }
acfs_early_system_binary_path() {
    case "$1" in
        stat|visudo|id) printf '%s/bin/%s\n' "$TEST_ROOT" "$1" ;;
        *) printf '/usr/bin/%s\n' "$1" ;;
    esac
}
id() { [[ "${1:-}" != -u ]]; }
getent() { return 2; }
usermod() { printf 'user_setup\n' >> "$TEST_ROOT/events"; }
command_exists() { return 1; }
runuser() {
    [[ "$*" == "-u $TARGET_USER -- sudo -n true" ]] || return 91
    [[ "$(cat -- "$TEST_POLICY")" == "$TARGET_USER ALL=(ALL) NOPASSWD:ALL" ]]
}
acfs_run_verification_shell() { ( eval "$2"; ); }
stat() { "$TEST_ROOT/bin/stat" "$@"; }
''',
            f"export TEST_POLICY={shlex.quote(str(policy))}",
            f"export TEST_VISUDO_FAIL={'true' if fail_validation else 'false'}",
            f"export TEST_OWNER={'1234' if custom_kind == 'foreign-owner' else '0'}",
            'run_phase user_setup "User setup" normalize_user',
        ])
        (folder / "fixture.sh").write_text(script + "\n")
        result = subprocess.run(["/bin/bash", "-p", "-c", script], text=True, capture_output=True,
                                env={"PATH": "/usr/bin:/bin", "HOME": str(folder)}, timeout=15)
        self.assertNotIn("command not found", result.stderr, result.stderr)
        self.assertNotIn("unbound variable", result.stderr, result.stderr)
        self.assertEqual(unrelated.read_text(), "operator ALL=(ALL) NOPASSWD:/usr/bin/id\n")
        self.assertEqual((policy_dir / "90-acfs-wheel").read_text(), "%wheel ALL=(ALL:ALL) ALL\n")
        state = json.loads((folder / "home/.acfs/state.json").read_text())
        events = (folder / "events").read_text().splitlines() if (folder / "events").exists() else []
        return result, policy, state, events

    def test_completed_vibe_install_reconciles_safe_policy_on_both_families(self):
        for family in ("ubuntu", "arch"):
            with self.subTest(family=family):
                result, policy, state, events = self.run_policy(
                    "safe", family=family, content="ubuntu ALL=(ALL) NOPASSWD:ALL\n", completed=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(policy.read_text(), "ubuntu ALL=(ALL) PASSWD:ALL\n")
                self.assertEqual(policy.stat().st_mode & 0o777, 0o440)
                self.assertEqual(events, ["user_setup", "validate"])
                self.assertEqual(state["mode"], "safe")
                self.assertIn("user_setup", state["completed_phases"])

    def test_vibe_reenables_managed_policy_and_safe_rerun_is_idempotent(self):
        for mode, before, after, expected_events in (
            ("vibe", "PASSWD", "NOPASSWD", ["user_setup", "validate"]),
            ("safe", "PASSWD", "PASSWD", []),
        ):
            with self.subTest(mode=mode):
                result, policy, state, events = self.run_policy(
                    mode, content=f"ubuntu ALL=(ALL) {before}:ALL\n", completed=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(policy.read_text(), f"ubuntu ALL=(ALL) {after}:ALL\n")
                self.assertEqual(events, expected_events)
                self.assertEqual(state["mode"], mode)

    def test_safe_policy_validation_failure_remains_retryable(self):
        original = "ubuntu ALL=(ALL) NOPASSWD:ALL\n"
        result, policy, state, events = self.run_policy(
            "safe", content=original, completed=True, fail_validation=True)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(policy.read_text(), original)
        self.assertEqual(events, ["user_setup", "validate"])
        self.assertNotIn("user_setup", state["completed_phases"])
        self.assertEqual(state["failed_phase"], "user_setup")

    def test_custom_foreign_or_linked_managed_files_are_preserved(self):
        cases = (
            (None, "ubuntu ALL=(ALL) NOPASSWD:ALL\noperator ALL=(ALL) ALL\n"),
            (None, "anotheruser ALL=(ALL) NOPASSWD:ALL\n"),
            ("foreign-owner", "ubuntu ALL=(ALL) NOPASSWD:ALL\n"),
            ("symlink", None), ("hardlink", None), ("directory", None),
        )
        for kind, content in cases:
            with self.subTest(kind=kind, content=content):
                result, policy, state, events = self.run_policy(
                    "safe", content=content, custom_kind=kind, completed=True)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                if content is not None:
                    self.assertEqual(policy.read_text(), content)
                if kind == "symlink":
                    self.assertTrue(policy.is_symlink())
                if kind == "hardlink":
                    self.assertEqual(policy.stat().st_nlink, 2)
                if kind == "directory":
                    self.assertTrue(policy.is_dir())
                self.assertNotIn("validate", events)
                self.assertNotIn("user_setup", state["completed_phases"])

    def test_fresh_safe_install_does_not_create_a_passwordless_grant(self):
        for family in ("ubuntu", "arch"):
            with self.subTest(family=family):
                result, policy, state, events = self.run_policy("safe", family=family)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse(policy.exists())
                self.assertEqual(events, ["user_setup"])
                self.assertIn("user_setup", state["completed_phases"])

    def test_nonroot_caller_cannot_revoke_its_own_active_sudo_grant(self):
        if os.geteuid() == 0:
            self.skipTest("This refusal requires a non-root test process")
        user = subprocess.check_output(["/usr/bin/id", "-un"], text=True, timeout=10).strip()
        original = f"{user} ALL=(ALL) NOPASSWD:ALL\n"
        result, policy, state, events = self.run_policy(
            "safe", target_user=user, content=original, completed=True,
            stub_ubuntu_uid=False)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("requires a root installer process", result.stderr)
        self.assertEqual(policy.read_text(), original)
        self.assertNotIn("validate", events)
        self.assertNotIn("user_setup", state["completed_phases"])


class BaseDependencyRecoveryTests(unittest.TestCase):
    """The early base phase must preserve the same recovery scope as run_phase."""

    BASE_SCOPE = ScopedInstallerResumeTests.BASE_SCOPE

    @classmethod
    def setUpClass(cls):
        ResumeCheckpointGateTests.setUpClass()
        ScopedInstallerResumeTests.setUpClass()
        cls.harness = ScopedInstallerResumeTests.harness
        cls.verify_phase = _main_fixture.definition(
            _main_fixture.MAIN.read_text(), "acfs_verify_phase")

    run_scoped = ScopedInstallerResumeTests.run_scoped
    scope_event = ScopedInstallerResumeTests.scope_event

    def run_base_repair(self, *, healthy=False, legacy=False, current_failure=False,
                        previous_failure=True, full=False):
        setup = [
            "state_phase_start base_deps",
            "state_step_result base_deps 'Prior base failure' failed true 'base.system is missing'"
            if previous_failure else "",
            "state_update 'del(.module_selection)'" if legacy else "",
            'touch "$TEST_ROOT/base-ready"' if healthy else "",
        ]
        execution = self.verify_phase + r'''
# The package boundary is inert; phase attempts, selectors, checkpoint I/O,
# authored verification and main's recovery decision execute production code.
ensure_base_deps() {
    trace mut:base
    state_phase_start base_deps
'''
        if current_failure:
            execution += "    state_step_result base_deps 'Current base failure' failed true 'current attempt failed'\n"
        execution += r'''
}
ACFS_MODULE_VERIFY_COUNT[base.system]=1
printf -v base_probe 'printf "EVENT:probe:base.system\\n" >&3; test -f %q' "$TEST_ROOT/base-ready"
ACFS_MODULE_VERIFY_COMMAND[base.system.0]="$base_probe"
ACFS_MODULE_VERIFY_RUN_AS[base.system]=current
run_phase() { trace checkpointed_phases_reached; record_scope; exit 0; }
'''
        arguments = ("--profile", "full") if full else ("--only", "lang.bun", "--no-deps")
        result, events, folder = self.run_scoped(
            arguments, alter="\n".join(setup), execution=execution)
        state = json.loads((folder / "home/.acfs/state.json").read_text())
        before = json.loads((folder / "checkpoint-before.json").read_text())
        if not full:
            self.assertEqual(state.get("module_selection"), before.get("module_selection"))
        return result, events, state

    def assert_prior_failure_retained(self, result, events, state):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertNotIn("checkpointed_phases_reached", events)
        prior = state["phase_steps"]["base_deps"]["Prior base failure"]
        self.assertEqual(prior["status"], "failed")
        self.assertEqual(prior["error"], "base.system is missing")
        self.assertNotIn("verified_at", prior)
        self.assertEqual(state["failed_phase"], "base_deps")

    def test_narrow_repair_cannot_certify_an_unhealthy_prior_base_dependency(self):
        result, events, state = self.run_base_repair()
        self.assert_prior_failure_retained(result, events, state)
        self.assertIn("probe:base.system", events)

    def test_live_base_recovery_preserves_the_narrow_execution_plan(self):
        result, events, state = self.run_base_repair(healthy=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("probe:base.system", events)
        self.assertIn("checkpointed_phases_reached", events)
        self.assertEqual(self.scope_event(events, "resolved"), ["lang.bun"])
        self.assertEqual(state["phase_steps"]["base_deps"]["Prior base failure"]["status"], "verified")
        self.assertIsNone(state["failed_phase"])

    def test_legacy_filtered_repair_preserves_unproven_base_failures(self):
        result, events, state = self.run_base_repair(healthy=True, legacy=True)
        self.assert_prior_failure_retained(result, events, state)
        self.assertNotIn("probe:base.system", events)

    def test_legacy_full_repair_can_still_reconcile_healthy_base_dependencies(self):
        result, events, state = self.run_base_repair(healthy=True, legacy=True, full=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("probe:base.system", events)
        self.assertIn("checkpointed_phases_reached", events)
        self.assertEqual(state["phase_steps"]["base_deps"]["Prior base failure"]["status"], "verified")
        self.assertIsNone(state["failed_phase"])

    def test_current_base_failure_is_not_forgiven_by_a_healthy_saved_scope(self):
        result, events, state = self.run_base_repair(healthy=True, current_failure=True)
        self.assert_prior_failure_retained(result, events, state)
        self.assertEqual(state["phase_steps"]["base_deps"]["Current base failure"]["status"], "failed")
        self.assertNotIn("probe:base.system", events)

    def test_clean_narrow_repair_does_not_probe_unselected_base_dependencies(self):
        result, events, _ = self.run_base_repair(previous_failure=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("checkpointed_phases_reached", events)
        self.assertEqual(self.scope_event(events, "resolved"), ["lang.bun"])
        self.assertNotIn("probe:base.system", events)


if __name__ == "__main__":
    unittest.main(verbosity=2)
