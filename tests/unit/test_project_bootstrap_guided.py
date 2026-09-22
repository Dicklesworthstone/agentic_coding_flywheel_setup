"""Real pseudo-terminal coverage for the guided first-project workflow."""
import errno
import json
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import termios
import time
import unittest

import test_project_bootstrap as bootstrap


class Terminal:
    """Drive prompts, not piped answers; stdout remains a separate JSON stream."""

    def __init__(self, env, *arguments):
        self.master, slave = pty.openpty()
        attributes = termios.tcgetattr(slave)
        attributes[3] &= ~termios.ECHO
        termios.tcsetattr(slave, termios.TCSANOW, attributes)
        self.process = subprocess.Popen(
            [bootstrap.BASH, str(bootstrap.SCRIPT), "--guided", *arguments],
            stdin=slave, stderr=slave, stdout=subprocess.PIPE, env=env,
            start_new_session=True,
        )
        os.close(slave)
        self.pending = ""
        self.transcript = ""

    def expect(self, text):
        deadline = time.monotonic() + 10
        while text not in self.pending:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError("missing prompt: " + text + "\n" + self.transcript)
            if not select.select([self.master], [], [], remaining)[0]:
                continue
            try:
                data = os.read(self.master, 65536)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                data = b""
            if not data:
                raise AssertionError("terminal ended before: " + text + "\n" + self.transcript)
            decoded = data.decode("utf-8", errors="replace")
            self.pending += decoded
            self.transcript += decoded
        _, self.pending = self.pending.split(text, 1)

    def answer(self, prompt, value=""):
        self.expect(prompt)
        os.write(self.master, value.encode() + b"\n")

    def finish(self):
        output, _ = self.process.communicate(timeout=10)
        while select.select([self.master], [], [], 0)[0]:
            try:
                data = os.read(self.master, 65536)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                break
            if not data:
                break
            self.transcript += data.decode("utf-8", errors="replace")
        return self.process.returncode, output.decode()

    def close(self):
        if self.process.poll() is None:
            os.killpg(self.process.pid, signal.SIGKILL)
            self.process.communicate(timeout=5)
        if self.process.stdout:
            self.process.stdout.close()
        os.close(self.master)


class GuidedBootstrapTests(unittest.TestCase):
    setUp = bootstrap.BootstrapTests.setUp
    run_cli = bootstrap.BootstrapTests.run_cli

    def terminal(self, *arguments):
        terminal = Terminal(self.env, *arguments)
        self.addCleanup(terminal.close)
        return terminal

    def select(self, terminal, *, stack="", beads="", mail=False, plan_path=""):
        terminal.answer("Project name: ", "demo")
        terminal.answer("Project directory (Enter uses the suggestion): ", str(self.target))
        terminal.answer("Starter language: python or typescript [python]: ", stack)
        terminal.answer("Initialize Beads task tracking? yes/no [no]: ", beads)
        terminal.answer("Connect an existing Agent Mail service? yes/no [no]: ", "yes" if mail else "")
        if mail:
            terminal.answer("Agent Mail URL: ", "https://mail.example/api/")
            terminal.answer("Token variable (or none for unauthenticated loopback) [AGENT_MAIL_TOKEN]: ", "GUIDED_TEST_TOKEN")
            terminal.answer("Clients: comma-separated claude,codex,gemini [claude,codex]: ", "claude,codex")
        terminal.answer("Plan file (Enter uses the suggestion): ", plan_path)

    def review(self, terminal, **kwargs):
        self.select(terminal, **kwargs)
        terminal.expect("Action: details / create / save / cancel [cancel]: ")

    def decide(self, terminal, action):
        os.write(terminal.master, action.encode() + b"\n")
        return terminal.finish()

    @property
    def plan_file(self):
        return self.base / ".demo-acfs-plan.json"

    def test_piped_input_is_never_consent(self):
        result = subprocess.run([bootstrap.BASH, str(bootstrap.SCRIPT), "--guided"],
                                input="demo\ncreate\n", capture_output=True, text=True,
                                env=self.env, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires terminal", result.stderr)
        self.assertEqual(list(self.base.iterdir()), [])

    def test_help_and_plan_overrides_do_not_create_anything(self):
        self.assertIn("--guided", self.run_cli("--guided", "--help").stdout)
        for arguments in (("--yes",), ("--stack", "python"), ("--beads",), ("--resume",),
                          ("--agent-mail-clients", "claude")):
            self.run_cli("--guided", *arguments, ok=False)
        self.assertEqual(list(self.base.iterdir()), [])

    def test_nothing_is_written_before_review_and_default_is_cancel(self):
        terminal = self.terminal()
        self.review(terminal)
        self.assertEqual(list(self.base.iterdir()), [])
        self.assertIn("REVIEW", terminal.transcript)
        self.assertIn("Network access: no", terminal.transcript)
        code, output = self.decide(terminal, "")
        self.assertEqual(code, 0, terminal.transcript)
        self.assertEqual(json.loads(output)["status"], "cancelled")
        self.assertEqual(list(self.base.iterdir()), [])

    def test_full_details_are_inspectable_without_writes(self):
        terminal = self.terminal()
        self.review(terminal)
        os.write(terminal.master, b"details\n")
        terminal.expect("Action: details / create / save / cancel [cancel]: ")
        self.assertIn('"content":', terminal.transcript)
        self.assertIn('"plan_id":', terminal.transcript)
        self.assertEqual(list(self.base.iterdir()), [])
        code, _ = self.decide(terminal, "cancel")
        self.assertEqual(code, 0)

    def test_save_only_produces_private_plan_usable_by_existing_cli(self):
        terminal = self.terminal()
        self.review(terminal)
        code, output = self.decide(terminal, "save")
        self.assertEqual(code, 0, terminal.transcript)
        result = json.loads(output)
        self.assertEqual(result["status"], "planned")
        self.assertFalse(self.target.exists())
        self.assertEqual(self.plan_file.stat().st_mode & 0o777, 0o600)
        self.assertEqual(list(self.base.iterdir()), [self.plan_file])
        self.run_cli("--apply", self.plan_file, "--yes")
        self.assertTrue((self.target / "src/app.py").is_file())

    def test_create_builds_working_python_project_and_retains_recovery_plan(self):
        terminal = self.terminal()
        self.review(terminal)
        code, output = self.decide(terminal, "create")
        self.assertEqual(code, 0, terminal.transcript)
        result = json.loads(output)
        self.assertEqual(result["status"], "created")
        self.assertEqual(result["plan_file"], str(self.plan_file))
        self.assertIn("sh scripts/check.sh", terminal.transcript)
        check = subprocess.run(["sh", "scripts/check.sh"], cwd=self.target,
                               capture_output=True, text=True, timeout=10)
        self.assertEqual(check.returncode, 0, check.stderr)
        self.assertIn("Ran 3 tests", check.stderr)
        self.assertEqual(self.plan_file.stat().st_mode & 0o777, 0o600)
        self.run_cli("--apply", self.plan_file, "--yes", "--resume")
        git = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=self.target,
                             capture_output=True, timeout=10)
        self.assertNotEqual(git.returncode, 0, "guide must not auto-commit")

    def test_typescript_choice_creates_only_typescript_starter(self):
        terminal = self.terminal()
        self.review(terminal, stack="typescript")
        code, _ = self.decide(terminal, "create")
        self.assertEqual(code, 0, terminal.transcript)
        self.assertTrue((self.target / "src/app.ts").exists())
        self.assertFalse((self.target / "src/app.py").exists())
        self.assertFalse((self.target / "node_modules").exists())
        self.assertEqual(json.loads(self.plan_file.read_text())["verification_commands"], [["bun", "test"]])

    def test_explicit_mail_selection_can_be_saved_offline_without_reading_token(self):
        self.env["GUIDED_TEST_TOKEN"] = "do-not-copy-me"
        terminal = self.terminal()
        self.review(terminal, mail=True)
        self.assertIn("ensure_project", terminal.transcript)
        self.assertIn("Network access: YES", terminal.transcript)
        code, output = self.decide(terminal, "save")
        self.assertEqual(code, 0, terminal.transcript)
        plan = json.loads(self.plan_file.read_text())
        self.assertEqual(plan["agent_mail_clients"], ["claude", "codex"])
        self.assertIn(".codex/config.toml", [entry["path"] for entry in plan["files"]])
        self.assertNotIn("do-not-copy-me", output + self.plan_file.read_text() + terminal.transcript)
        self.assertFalse(self.target.exists())

    def test_missing_mail_credential_blocks_create_before_plan_or_project(self):
        self.env.pop("GUIDED_TEST_TOKEN", None)
        terminal = self.terminal()
        self.review(terminal, mail=True)
        code, _ = self.decide(terminal, "create")
        self.assertNotEqual(code, 0)
        self.assertIn("token environment variable is missing", terminal.transcript)
        self.assertEqual(list(self.base.iterdir()), [])

    def test_existing_plan_is_not_overwritten(self):
        self.plan_file.write_text("existing plan")
        terminal = self.terminal()
        self.select(terminal)
        code, _ = terminal.finish()
        self.assertNotEqual(code, 0)
        self.assertEqual(self.plan_file.read_text(), "existing plan")
        self.assertFalse(self.target.exists())

    def test_guided_plan_matches_explicit_cli_plan_exactly(self):
        expected = json.loads(self.run_cli("--plan", "demo", self.target,
                                          "--preset", "first-project", "--stack", "python").stdout)
        terminal = self.terminal()
        self.review(terminal)
        code, _ = self.decide(terminal, "save")
        self.assertEqual(code, 0, terminal.transcript)
        self.assertEqual(json.loads(self.plan_file.read_text()), expected)

    def test_plan_directory_replacement_during_review_blocks_all_writes(self):
        plan_parent = self.base / "plans"
        plan_parent.mkdir()
        output = plan_parent / "review.json"
        terminal = self.terminal()
        self.review(terminal, plan_path=str(output))
        plan_parent.rename(self.base / "original-plans")
        plan_parent.mkdir()
        code, _ = self.decide(terminal, "create")
        self.assertNotEqual(code, 0)
        self.assertIn("plan directory changed", terminal.transcript)
        self.assertFalse(self.target.exists())
        self.assertEqual(list(plan_parent.iterdir()), [])
        self.assertEqual(list((self.base / "original-plans").iterdir()), [])

    def test_beads_is_selected_explicitly_and_disclosed_without_running_it(self):
        terminal = self.terminal()
        self.review(terminal, beads="yes")
        self.assertIn('"argv": ["br", "init"]', terminal.transcript)
        self.assertEqual(list(self.base.iterdir()), [])
        code, _ = self.decide(terminal, "save")
        self.assertEqual(code, 0, terminal.transcript)
        self.assertIn("beads", json.loads(self.plan_file.read_text())["features"])
        self.assertFalse(self.target.exists())

    def test_concurrent_plan_collision_blocks_create(self):
        terminal = self.terminal()
        self.review(terminal)
        self.plan_file.write_text("concurrent plan")
        code, _ = self.decide(terminal, "create")
        self.assertNotEqual(code, 0)
        self.assertEqual(self.plan_file.read_text(), "concurrent plan")
        self.assertFalse(self.target.exists())

    def test_concurrent_destination_change_blocks_even_plan_save(self):
        terminal = self.terminal()
        self.review(terminal)
        self.target.mkdir()
        (self.target / "human.txt").write_text("preserve")
        code, _ = self.decide(terminal, "create")
        self.assertNotEqual(code, 0)
        self.assertFalse(self.plan_file.exists())
        self.assertEqual((self.target / "human.txt").read_text(), "preserve")

    def test_plan_symlink_cannot_overwrite_another_file(self):
        outside = self.base / "outside"
        outside.write_text("preserve")
        self.plan_file.symlink_to(outside)
        terminal = self.terminal()
        self.select(terminal)
        code, _ = terminal.finish()
        self.assertNotEqual(code, 0)
        self.assertTrue(self.plan_file.is_symlink())
        self.assertEqual(outside.read_text(), "preserve")
        self.assertFalse(self.target.exists())

    def test_eof_and_interrupt_leave_no_files(self):
        terminal = self.terminal()
        terminal.expect("Project name: ")
        os.write(terminal.master, b"\x04")
        code, _ = terminal.finish()
        self.assertEqual(code, 130, terminal.transcript)
        self.assertEqual(list(self.base.iterdir()), [])
        interrupted = self.terminal()
        self.review(interrupted)
        os.killpg(interrupted.process.pid, signal.SIGINT)
        code, _ = interrupted.finish()
        self.assertIn(code, (130, -signal.SIGINT), interrupted.transcript)
        self.assertEqual(list(self.base.iterdir()), [])

    def test_failed_tool_keeps_plan_and_resumes_through_existing_cli(self):
        tools = self.base / "tools"
        tools.mkdir()
        bad_git = tools / "git"
        bad_git.write_text("#!/bin/sh\nexit 9\n")
        bad_git.chmod(0o755)
        original_path = self.env["PATH"]
        self.env["PATH"] = str(tools) + os.pathsep + original_path
        terminal = self.terminal()
        self.review(terminal)
        code, _ = self.decide(terminal, "create")
        self.assertNotEqual(code, 0)
        self.assertTrue(self.plan_file.exists())
        self.assertTrue((self.target / "src/app.py").exists())
        self.assertIn("--resume", terminal.transcript)
        self.env["PATH"] = original_path
        self.run_cli("--apply", self.plan_file, "--yes", "--resume")
        state = json.loads((self.target / ".acfs/bootstrap-state.json").read_text())
        self.assertEqual(state["status"], "complete")


if __name__ == "__main__":
    unittest.main(verbosity=2)
