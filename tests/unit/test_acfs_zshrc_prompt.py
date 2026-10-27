#!/usr/bin/env python3
"""Run the canonical zshrc in real shells with isolated prompt dependencies.

PTY-backed interactive shells are the positive control. Command-mode and
non-terminal shells must keep ACFS helpers without starting prompt engines.
Test trees are retained to preserve evidence.
"""
from __future__ import annotations

import os
from pathlib import Path
import pty
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(os.environ.get("ACFS_PROMPT_TEST_SOURCE", ROOT / "acfs/zsh/acfs.zshrc"))
ZSH = shutil.which("zsh")

OMZ = r'''
print -r -- "omz:$ZSH_THEME:$GITSTATUS_NUM_THREADS" >> "$ACFS_PROMPT_LOG"
if [[ -n "$ZSH_THEME" ]]; then
  print -r -- theme-start >> "$ACFS_PROMPT_LOG"
fi
'''

STARSHIP = r'''
starship() {
  print -r -- "starship:$*" >> "$ACFS_PROMPT_LOG"
  print -r -- 'starship_precmd() { :; }'
}
'''

RECORD = r'''
print -r -- "threads:$GITSTATUS_NUM_THREADS" >> "$ACFS_PROMPT_LOG"
print -r -- "theme:$ZSH_THEME" >> "$ACFS_PROMPT_LOG"
print -r -- "prompt:$PROMPT" >> "$ACFS_PROMPT_LOG"
whence -w acfs >> "$ACFS_PROMPT_LOG"
alias gs >> "$ACFS_PROMPT_LOG"
print -r -- "path:$PATH" >> "$ACFS_PROMPT_LOG"
'''


class PromptStartupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if ZSH is None:
            raise RuntimeError("zsh is required for prompt startup regressions")
        if not SOURCE.is_file():
            raise RuntimeError(f"Canonical zshrc is missing: {SOURCE}")

    def invoke(self, *, command=None, interactive=True, login=False,
               stdin_tty=True, stdout_tty=True, env=None, omz=True,
               starship=False, prelude=""):
        root = Path(tempfile.mkdtemp(prefix="acfs-prompt-"))
        home = root / "home"
        home.mkdir()
        bin_dir = root / "bin"
        bin_dir.mkdir()
        # Keep host tool integrations out of the test. zsh's standard fpath
        # still supplies its real completion and hook functions.
        for name in ("zsh", "infocmp", "mkdir", "mv"):
            executable = shutil.which(name)
            if executable:
                (bin_dir / name).symlink_to(executable)
        log = root / "prompt.log"
        recorder = root / "record.zsh"
        recorder.write_text(RECORD)
        # End non-command fixtures after startup, without adding -c (which
        # would change the very mode being tested). A shell can otherwise
        # choose its terminal for input even when fd 0 is a pipe.
        finish = "exit 0\n" if interactive and command is None else ""
        (home / ".zshrc").write_text(
            prelude + (STARSHIP if starship else "")
            + '\nsource "$ACFS_PROMPT_SOURCE"\nsource "$ACFS_PROMPT_RECORD"\n' + finish
        )
        (home / ".p10k.zsh").write_text(
            'print -r -- p10k-config >> "$ACFS_PROMPT_LOG"\n'
        )
        if omz:
            (home / ".oh-my-zsh").mkdir()
            (home / ".oh-my-zsh/oh-my-zsh.sh").write_text(OMZ)
        settings = {
            "HOME": str(home), "ZDOTDIR": str(home), "PATH": str(bin_dir),
            "TERM": "xterm-256color", "LC_ALL": "C",
            "ACFS_PROMPT_SOURCE": str(SOURCE),
            "ACFS_PROMPT_RECORD": str(recorder),
            "ACFS_PROMPT_LOG": str(log),
        }
        settings.update(env or {})
        argv = [ZSH, "-d"]
        if login:
            argv.append("-l")
        if interactive:
            argv.append("-i")
        if command is not None:
            argv.extend(["-c", command])
        elif not interactive:
            argv.extend(["-c", 'source "$HOME/.zshrc"'])
        master = slave = None
        proc = None
        try:
            if stdin_tty or stdout_tty:
                master, slave = pty.openpty()
            proc = subprocess.Popen(
                argv, cwd=home, env=settings,
                stdin=slave if stdin_tty else subprocess.PIPE,
                stdout=slave if stdout_tty else subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            stdout, stderr = proc.communicate(timeout=15)
            self.assertEqual(
                proc.returncode, 0,
                f"fixture={root}\nstdout={stdout!r}\nstderr={stderr!r}",
            )
            self.assertNotIn(b"parse error", stderr)
            self.assertNotIn(b"command not found", stderr)
        finally:
            if proc is not None and proc.poll() is None:
                proc.kill()
                proc.wait()
            if master is not None:
                os.close(master)
                os.close(slave)
        self.assertTrue(log.is_file(), f"Startup did not reach recorder: {root}")
        lines = log.read_text().splitlines()
        # Exercise the complete config, not an extracted condition. Suppressing
        # a theme must leave the command environment available.
        self.assertIn("acfs: function", lines)
        self.assertIn("gs='git status'", lines)
        path_line = next(line for line in lines if line.startswith("path:"))
        self.assertIn(str(home / ".local/bin"), path_line.split(":", 1)[1].split(":"))
        return lines

    def assert_no_prompt(self, lines):
        self.assertNotIn("theme-start", lines)
        self.assertNotIn("p10k-config", lines)
        self.assertFalse(any(line.startswith("starship:") for line in lines))
        self.assertIn("theme:", lines)

    def test_terminal_interactive_shell_starts_prompt(self):
        lines = self.invoke()
        self.assertIn("theme-start", lines)
        self.assertIn("p10k-config", lines)
        self.assertIn("omz:powerlevel10k/powerlevel10k:2", lines)

    def test_login_terminal_shell_still_starts_prompt(self):
        lines = self.invoke(login=True)
        self.assertIn("theme-start", lines)
        self.assertIn("p10k-config", lines)

    def test_explicit_worker_count_is_visible_before_theme_load(self):
        lines = self.invoke(prelude="GITSTATUS_NUM_THREADS=4")
        self.assertIn("omz:powerlevel10k/powerlevel10k:4", lines)
        self.assertIn("threads:4", lines)

    def test_exported_worker_count_is_preserved(self):
        lines = self.invoke(env={"GITSTATUS_NUM_THREADS": "3"})
        self.assertIn("omz:powerlevel10k/powerlevel10k:3", lines)

    def test_empty_worker_count_uses_small_default(self):
        lines = self.invoke(env={"GITSTATUS_NUM_THREADS": ""})
        self.assertIn("omz:powerlevel10k/powerlevel10k:2", lines)

    def test_command_shell_with_pty_skips_prompt_and_executes_payload(self):
        lines = self.invoke(
            login=True, command='print -r -- payload >> "$ACFS_PROMPT_LOG"'
        )
        self.assert_no_prompt(lines)
        self.assertIn("payload", lines)

    def test_command_shell_without_tty_skips_prompt(self):
        lines = self.invoke(login=True, command=":", stdin_tty=False, stdout_tty=False)
        self.assert_no_prompt(lines)

    def test_empty_command_with_pty_still_skips_prompt(self):
        self.assert_no_prompt(self.invoke(login=True, command=""))

    def test_input_tty_alone_does_not_enable_prompt(self):
        self.assert_no_prompt(self.invoke(stdout_tty=False))

    def test_output_tty_alone_does_not_enable_prompt(self):
        self.assert_no_prompt(self.invoke(stdin_tty=False))

    def test_piped_interactive_shell_skips_prompt(self):
        self.assert_no_prompt(self.invoke(stdin_tty=False, stdout_tty=False))

    def test_noninteractive_manual_source_skips_prompt(self):
        self.assert_no_prompt(self.invoke(interactive=False))

    def test_agent_markers_disable_terminal_prompt(self):
        for marker in ("CODEX_REMOTE_PAYLOAD", "SIFS_AGENT", "AGENT_ENV"):
            with self.subTest(marker=marker):
                self.assert_no_prompt(self.invoke(env={marker: "1"}))

    def test_empty_agent_markers_do_not_disable_human_prompt(self):
        lines = self.invoke(env={
            "CODEX_REMOTE_PAYLOAD": "", "SIFS_AGENT": "", "AGENT_ENV": "",
        })
        self.assertIn("theme-start", lines)
        self.assertIn("p10k-config", lines)

    def test_vscode_uses_plain_prompt_without_starting_theme(self):
        lines = self.invoke(env={"TERM_PROGRAM": "vscode"})
        self.assert_no_prompt(lines)
        self.assertIn("prompt:%n@%m:%~%# ", lines)

    def test_no_omz_human_terminal_starts_starship(self):
        lines = self.invoke(omz=False, starship=True)
        self.assertIn("starship:init zsh", lines)

    def test_no_omz_command_shell_skips_starship(self):
        lines = self.invoke(omz=False, starship=True, login=True, command=":")
        self.assert_no_prompt(lines)

    def test_no_omz_agent_terminal_skips_starship(self):
        lines = self.invoke(omz=False, starship=True, env={"AGENT_ENV": "1"})
        self.assert_no_prompt(lines)


if __name__ == "__main__":
    unittest.main(verbosity=2)
