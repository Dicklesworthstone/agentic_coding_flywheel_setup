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
                self.assertTrue((folder / "backup-failed").exists())
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
