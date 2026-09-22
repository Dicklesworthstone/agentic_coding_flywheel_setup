#!/usr/bin/env python3
"""Selector command-replay and controlling-terminal regressions (stdlib only).

The resolver is stubbed at the I/O boundary; dependency behavior is covered by
other selector tests. No installer, network request, or system change is run.
"""

import errno
import fcntl
import os
from pathlib import Path
import pty
import shlex
import shutil
import subprocess
import termios
import unittest


ROOT = Path(__file__).resolve().parents[2]
SELECTOR = Path(os.environ.get(
    "ACFS_SELECTOR_UNDER_TEST", str(ROOT / "scripts/lib/module_selector.sh")
))
BASH = shutil.which("bash")
HEADER = r'''
set -euo pipefail
log_info() { :; }
log_error() { printf '%s\n' "$1" >&2; }
acfs_resolve_selection() { return 0; }
source "$1"
YES_MODE=false
CI=false
MODE=vibe
NO_DEPS=false
ACFS_SELECTED_PROFILE=''
ACFS_MANIFEST_INDEX_LOADED=true
ONLY_MODULES=()
ONLY_PHASES=()
SKIP_MODULES=()
SKIP_TAGS=()
SKIP_CATEGORIES=()
declare -a ACFS_MODULES_IN_ORDER=(base.core tools.extra cloud.deploy tools.other)
declare -A ACFS_MODULE_TAGS=(
    [base.core]=essential [tools.extra]=utility,optional
    [cloud.deploy]=optional [tools.other]=optional-extra
)
declare -A ACFS_MODULE_CATEGORY=(
    [base.core]=base [tools.extra]=tools [cloud.deploy]=cloud [tools.other]=tools
)
declare -A ACFS_PROFILE_ONLY_MODULES=([minimal]=base.core,tools.extra)
declare -A ACFS_PROFILE_ONLY_PHASES=([agents-only]=7)
'''


@unittest.skipUnless(BASH, "Bash is required")
class SelectorIOTests(unittest.TestCase):
    def run_shell(self, script, *, controlling_tty=False):
        """Keep stdio piped even when the child owns a real controlling TTY."""
        master = slave = None
        if controlling_tty:
            master, slave = pty.openpty()

        def attach_tty():
            # start_new_session runs setsid before this pre-exec callback.
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

        try:
            process = subprocess.run(
                [BASH, "--noprofile", "--norc", "-c", HEADER + script,
                 "selector-test", str(SELECTOR)],
                input=b"", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=10, start_new_session=True,
                pass_fds=(slave,) if controlling_tty else (),
                preexec_fn=attach_tty if controlling_tty else None,
                env={**os.environ, "BASH_ENV": "/dev/null"},
            )
            terminal_output = b""
            if controlling_tty:
                os.close(slave)
                slave = None
                os.set_blocking(master, False)
                while True:
                    try:
                        chunk = os.read(master, 65536)
                    except BlockingIOError:
                        break
                    except OSError as error:
                        if error.errno == errno.EIO:
                            break
                        raise
                    if not chunk:
                        break
                    terminal_output += chunk
            return process, terminal_output
        finally:
            if slave is not None:
                os.close(slave)
            if master is not None:
                os.close(master)

    def replay(self, setup=""):
        # Capture argv rather than running install.sh. Eval is intentional here:
        # it exercises precisely how the displayed command is parsed by Bash.
        process, _ = self.run_shell(setup + r'''
command_text="$(acfs_format_reproducible_cli_command)"
bash() { printf '%s\0' "$@"; }
eval "$command_text"
''')
        self.assertEqual(process.returncode, 0, process.stderr.decode())
        self.assertEqual(process.stderr, b"")
        return process.stdout.decode().split("\0")[:-1]

    def test_default_command(self):
        self.assertEqual(self.replay(), ["install.sh"])

    def test_explicit_selectors_and_expert_mode(self):
        self.assertEqual(self.replay('''
MODE=safe
ONLY_MODULES=(base.core tools.extra)
ONLY_PHASES=(6 7)
SKIP_MODULES=(cloud.deploy)
NO_DEPS=true
'''), ["install.sh", "--mode", "safe", "--only", "base.core", "--only",
       "tools.extra", "--only-phase", "6", "--only-phase", "7", "--skip",
       "cloud.deploy", "--no-deps"])

    def test_selector_profile_does_not_duplicate_only_flags(self):
        self.assertEqual(self.replay('''
ACFS_SELECTED_PROFILE=minimal
ONLY_MODULES=(base.core tools.extra)
'''), ["install.sh", "--profile", "minimal"])

    def test_phase_profile_does_not_duplicate_only_flags(self):
        self.assertEqual(self.replay('''
ACFS_SELECTED_PROFILE=agents-only
ONLY_PHASES=(7)
'''), ["install.sh", "--profile", "agents-only"])

    def test_mode_only_profile_preserves_explicit_selection(self):
        self.assertEqual(self.replay('''
ACFS_SELECTED_PROFILE=safe
MODE=safe
ONLY_MODULES=(base.core)
'''), ["install.sh", "--mode", "safe", "--only", "base.core"])

    def test_tag_exclusions_expand_to_supported_skip_arguments(self):
        self.assertEqual(self.replay("SKIP_TAGS=(optional)\n"),
                         ["install.sh", "--skip", "tools.extra", "--skip", "cloud.deploy"])

    def test_category_exclusions_expand_to_supported_skip_arguments(self):
        self.assertEqual(self.replay("SKIP_CATEGORIES=(cloud)\n"),
                         ["install.sh", "--skip", "cloud.deploy"])

    def test_overlapping_exclusions_are_deduplicated(self):
        self.assertEqual(self.replay('''
SKIP_MODULES=(cloud.deploy cloud.deploy)
SKIP_CATEGORIES=(cloud)
SKIP_TAGS=(optional optional)
'''), ["install.sh", "--skip", "cloud.deploy", "--skip", "tools.extra"])

    def test_unknown_or_empty_filters_do_not_expand_the_plan(self):
        self.assertEqual(self.replay('''
SKIP_CATEGORIES=('' unavailable)
SKIP_TAGS=('' option)
'''), ["install.sh"])

    def test_shell_metacharacters_remain_literal_arguments(self):
        value = "literal 'quote' ; printf INJECTED >&2; $(printf EXECUTED >&2) *\nnext"
        self.assertEqual(self.replay(f"ONLY_MODULES=({shlex.quote(value)})\n"),
                         ["install.sh", "--only", value])

    def test_formatting_does_not_mutate_selection(self):
        process, _ = self.run_shell(r'''
SKIP_MODULES=(cloud.deploy)
SKIP_TAGS=(optional)
SKIP_CATEGORIES=(tools)
before="$(declare -p ONLY_MODULES ONLY_PHASES SKIP_MODULES SKIP_TAGS SKIP_CATEGORIES)"
acfs_format_reproducible_cli_command >/dev/null
after="$(declare -p ONLY_MODULES ONLY_PHASES SKIP_MODULES SKIP_TAGS SKIP_CATEGORIES)"
[[ "$before" == "$after" ]]
''')
        self.assertEqual(process.returncode, 0, process.stderr.decode())

    def test_unset_optional_filter_arrays(self):
        self.assertEqual(self.replay("unset SKIP_TAGS SKIP_CATEGORIES\n"), ["install.sh"])

    def test_headless_probe_is_quiet_and_preserves_stderr(self):
        process, _ = self.run_shell(r'''
if acfs_is_interactive_terminal; then exit 42; fi
printf 'diagnostic-after-probe\n' >&2
''')
        self.assertEqual(process.returncode, 0, process.stderr.decode())
        self.assertEqual(process.stderr, b"diagnostic-after-probe\n")

    def test_explicit_interactive_without_tty_fails_with_visible_diagnostic(self):
        process, _ = self.run_shell(r'''
ACFS_INTERACTIVE=true
if acfs_interactive_module_selector; then exit 42; fi
printf 'diagnostic-after-selector\n' >&2
''')
        self.assertEqual(process.returncode, 0, process.stderr.decode())
        self.assertIn(b"no interactive TTY", process.stderr)
        self.assertTrue(process.stderr.endswith(b"diagnostic-after-selector\n"))
        self.assertNotIn(b"/dev/tty:", process.stderr)

    def test_tty_probe_preserves_stderr_and_closes_descriptors(self):
        process, _ = self.run_shell(r'''
ulimit -n 64
for ((i=0; i<100; i++)); do
    acfs_is_interactive_terminal || exit 42
done
printf 'diagnostic-after-probe\n' >&2
''', controlling_tty=True)
        self.assertEqual(process.returncode, 0, process.stderr.decode())
        self.assertEqual(process.stderr, b"diagnostic-after-probe\n")

    def test_selector_uses_tty_but_restores_streams_and_status(self):
        process, terminal_output = self.run_shell(r'''
_acfs_interactive_module_selector_on_tty() {
    [[ -t 0 && -t 1 ]] || return 42
    printf 'terminal-dialog\n'
    printf 'dialog-diagnostic\n' >&2
    return 17
}
status=0
acfs_interactive_module_selector || status=$?
[[ "$status" == 17 ]] || exit 42
printf 'stdout-after-selector\n'
printf 'stderr-after-selector\n' >&2
''', controlling_tty=True)
        self.assertEqual(process.returncode, 0, process.stderr.decode())
        self.assertEqual(process.stdout, b"stdout-after-selector\n")
        self.assertEqual(process.stderr, b"dialog-diagnostic\nstderr-after-selector\n")
        self.assertIn(b"terminal-dialog", terminal_output)
        self.assertNotIn(b"stdout-after-selector", terminal_output)

    def test_yes_and_ci_modes_do_not_open_tty(self):
        for setting in ("YES_MODE=true", "CI=true"):
            with self.subTest(setting=setting):
                process, _ = self.run_shell(setting + r'''
if acfs_is_interactive_terminal; then exit 42; fi
printf 'visible-diagnostic\n' >&2
''', controlling_tty=True)
                self.assertEqual(process.returncode, 0, process.stderr.decode())
                self.assertEqual(process.stderr, b"visible-diagnostic\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
