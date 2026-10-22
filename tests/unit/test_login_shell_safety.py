"""Account-free regression tests for the shared login-shell transaction (#473)."""
import os
import pwd
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
LIBRARY = (ROOT / "scripts/lib/user.sh").read_text()
HELPERS = LIBRARY.split("# BEGIN ACFS LOGIN SHELL HELPERS", 1)[1].split(
    "# END ACFS LOGIN SHELL HELPERS", 1
)[0]


class LoginShellSafety(unittest.TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp(prefix="acfs-shell-test-"))
        self.home = self.directory / "home"
        self.home.mkdir()
        self.zsh = self.directory / "zsh"
        self.zsh.write_text("#!/bin/sh\nexit 0\n")
        self.zsh.chmod(0o755)
        self.shells = self.directory / "shells"
        self.shells.write_text(f"# Valid login shells\n/bin/bash\n{self.zsh}\n")
        self.passwd = self.directory / "passwd"
        self.passwd.write_text(f"alice:x:{os.getuid()}:0::/home/alice:/bin/bash\n")
        self.state = self.directory / "state"
        self.state.write_text("/bin/bash\n")
        self.calls = self.directory / "calls"
        self.backup = self.home / ".shell.pre-oh-my-zsh"

    def run_shell(self, script, *, change='printf "%s\\n" "$1" > "$STATE"'):
        env = dict(os.environ, STATE=str(self.state), CALLS=str(self.calls))
        prelude = HELPERS + f'''
real_change="$(declare -f acfs_login_shell_change)"
acfs_login_shell_entry() {{ printf 'alice:x:{os.getuid()}:0::/home/alice:%s\\n' "$(cat "$STATE")"; }}
acfs_login_shell_change() {{
    printf '%s\\n' "$1" >> "$CALLS"
    {change}
}}
configure() {{ acfs_configure_login_shell alice {shlex.quote(str(self.home))} {shlex.quote(str(self.shells))} {shlex.quote(str(self.passwd))}; }}
'''
        return subprocess.run(["bash", "-c", "set -euo pipefail\n" + prelude + script],
                              env=env, text=True, capture_output=True)

    def test_approved_path_applied_and_original_preserved(self):
        result = self.run_shell("configure")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state.read_text().strip(), str(self.zsh))
        self.assertEqual(self.backup.read_text(), "/bin/bash\n")
        self.assertEqual(self.backup.stat().st_mode & 0o777, 0o600)

    def test_repeated_install_does_not_change_shell_or_backup_again(self):
        result = self.run_shell("configure; configure")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)
        self.assertEqual(self.backup.read_text(), "/bin/bash\n")

    def test_existing_backup_is_preserved(self):
        self.backup.write_text("/bin/sh\n")
        self.assertEqual(self.run_shell("configure").returncode, 0)
        self.assertEqual(self.backup.read_text(), "/bin/sh\n")

    def test_usrmerge_alias_not_listed_is_replaced(self):
        self.state.write_text("/usr/sbin/zsh\n")
        result = self.run_shell("SHELL=/usr/sbin/zsh; configure")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state.read_text().strip(), str(self.zsh))

    def test_selection_ignores_path_order(self):
        for path in ("/usr/sbin:/usr/bin:/bin", "/bin:/usr/bin:/usr/sbin"):
            result = self.run_shell(f"PATH={shlex.quote(path)}; acfs_login_shell_select {shlex.quote(str(self.shells))}")
            self.assertEqual(result.stdout.strip(), str(self.zsh))

    def test_usr_bin_preferred_over_sbin_alias(self):
        # Model a usrmerged host without creating system binaries.
        result = self.run_shell('''
acfs_login_shell_approved() { [[ "$1" == /usr/bin/zsh || "$1" == /usr/sbin/zsh ]]; }
acfs_login_shell_select
''')
        self.assertEqual(result.stdout.strip(), "/usr/bin/zsh")

    def test_unusual_exact_entry_without_final_newline(self):
        self.shells.write_text(f"# comment\n{self.zsh}")
        self.assertEqual(self.run_shell("configure").returncode, 0)

    def test_missing_shells_refuses_without_chsh(self):
        self.shells = self.directory / "absent"
        self.assertNotEqual(self.run_shell("configure").returncode, 0)
        self.assertFalse(self.calls.exists())
        self.assertFalse(self.backup.exists())

    def test_empty_comment_and_nonliteral_entries_refuse(self):
        for contents in ("", "# /usr/bin/zsh\n", f" {self.zsh}\n", f"{self.zsh} # zsh\n", "/missing/zsh\n"):
            self.shells.write_text(contents)
            self.assertNotEqual(self.run_shell("configure").returncode, 0)
            self.assertFalse(self.calls.exists())

    def test_non_executable_shell_refuses(self):
        self.zsh.chmod(0o644)
        self.assertNotEqual(self.run_shell("configure").returncode, 0)
        self.assertFalse(self.calls.exists())

    def test_directory_named_zsh_refuses(self):
        directory = self.directory / "directory" / "zsh"
        directory.mkdir(parents=True)
        self.shells.write_text(f"{directory}\n")
        self.assertNotEqual(self.run_shell("configure").returncode, 0)

    def test_chsh_failure_is_error(self):
        result = self.run_shell("configure", change="return 1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state.read_text(), "/bin/bash\n")

    def test_chsh_success_without_account_update_is_error(self):
        self.assertNotEqual(self.run_shell("configure", change=":").returncode, 0)

    def test_chsh_partial_failure_restores_original(self):
        result = self.run_shell("configure", change='printf "%s\\n" "$1" > "$STATE"; return 1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state.read_text(), "/bin/bash\n")
        self.assertEqual(len(self.calls.read_text().splitlines()), 2)

    def test_wrong_applied_path_triggers_verified_recovery(self):
        result = self.run_shell("configure", change='if [[ "$1" == /bin/bash ]]; then printf "/bin/bash\\n" > "$STATE"; else printf "/usr/sbin/zsh\\n" > "$STATE"; fi')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state.read_text(), "/bin/bash\n")

    def test_failed_account_lookup_after_change_attempts_recovery(self):
        result = self.run_shell('''
acfs_login_shell_entry() {
    [[ "$(cat "$STATE")" == /bin/bash ]] || return 1
    printf 'alice:x:0:0::/home/alice:/bin/bash\\n'
}
configure
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state.read_text(), "/bin/bash\n")
        self.assertEqual(len(self.calls.read_text().splitlines()), 2)

    def test_failed_recovery_is_reported(self):
        result = self.run_shell("configure", change='printf "/usr/sbin/zsh\\n" > "$STATE"; return 1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Recovery failed", result.stderr)

    def test_external_account_never_calls_chsh(self):
        self.passwd.write_text("root:x:0:0::/root:/bin/bash\n")
        self.assertEqual(self.run_shell("configure").returncode, 2)
        self.assertFalse(self.calls.exists())

    def test_unreadable_account_source_is_not_treated_as_external(self):
        self.passwd = self.directory / "missing-passwd"
        self.assertEqual(self.run_shell("configure").returncode, 1)
        self.assertFalse(self.calls.exists())

    def test_symlink_recovery_file_refuses(self):
        self.backup.symlink_to(self.state)
        self.assertNotEqual(self.run_shell("configure").returncode, 0)
        self.assertFalse(self.calls.exists())

    @unittest.skipUnless(os.geteuid() == 0, "requires root to exercise the root branch")
    def test_root_chsh_receives_explicit_target(self):
        fake = self.directory / "chsh"
        fake.write_text('#!/bin/bash\nprintf "%s\\n" "$@" > "$CALLS"\n')
        fake.chmod(0o755)
        result = self.run_shell(f'''
eval "$real_change"
acfs_login_shell_tool() {{ printf '%s\\n' {shlex.quote(str(fake))}; }}
acfs_login_shell_change /usr/bin/zsh alice
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().splitlines(), ["-s", "/usr/bin/zsh", "alice"])

    def test_nonprivileged_without_sudo_or_tty_refuses(self):
        result = self.run_shell('''
eval "$real_change"
acfs_login_shell_is_root() { return 1; }
acfs_login_shell_tool() { [[ "$1" == chsh ]] && printf '/bin/false\\n'; }
acfs_login_shell_change /usr/bin/zsh alice
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("without privilege", result.stderr)

    def test_nonprivileged_sudo_failure_is_propagated(self):
        # Fake sudo accepts its noninteractive probe, then fails the change.
        self.directory.chmod(0o755)
        fake = self.directory / "sudo"
        fake.write_text('#!/bin/bash\n[[ "$*" == "-n true" ]]\n')
        fake.chmod(0o755)
        result = self.run_shell(f'''
eval "$real_change"
acfs_login_shell_is_root() {{ return 1; }}
acfs_login_shell_tool() {{
    case "$1" in chsh) printf '/bin/false\\n';; sudo) printf '%s\\n' {shlex.quote(str(fake))};; esac
}}
acfs_login_shell_change /usr/bin/zsh alice
''')
        self.assertNotEqual(result.returncode, 0)

    def test_nonprivileged_passwordless_sudo_uses_noninteractive_explicit_target(self):
        fake = self.directory / "sudo"
        fake.write_text('#!/bin/bash\n[[ "$*" == "-n true" ]] && exit 0\nprintf "%s\\n" "$@" > "$CALLS"\n')
        fake.chmod(0o755)
        result = self.run_shell(f'''
eval "$real_change"
acfs_login_shell_is_root() {{ return 1; }}
acfs_login_shell_tool() {{
    case "$1" in chsh) printf '/usr/bin/chsh\\n';; sudo) printf '%s\\n' {shlex.quote(str(fake))};; esac
}}
acfs_login_shell_change /usr/bin/zsh alice
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().splitlines(), ["-n", "/usr/bin/chsh", "-s", "/usr/bin/zsh", "alice"])

    def generated_shell_step(self):
        generated = (ROOT / "scripts/generated/install_shell.sh").read_text()
        return "# Set default shell\n" + generated.split("# Set default shell\n", 1)[1].split("\nINSTALL_SHELL_OMZ", 1)[0]

    def test_generated_external_handoff_is_idempotent_and_never_calls_chsh(self):
        script = '''
acfs_generated_resolve_current_user() { echo acfs_test_external; }
acfs_generated_getent_passwd_entry() { echo 'acfs_test_external:x:12345:12345::/home/external:/bin/bash'; }
acfs_configure_login_shell() { echo 'unexpected local change' >&2; return 1; }
'''
        env = dict(os.environ, HOME=str(self.home), SHELL="/bin/bash")
        for _ in range(2):
            result = subprocess.run(["bash", "-euc", script + self.generated_shell_step()], env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        bashrc = (self.home / ".bashrc").read_text()
        self.assertEqual(bashrc.count("# ACFS externally-managed shell handoff"), 1)

    def test_generated_local_failure_propagates_even_with_stale_zsh_environment(self):
        name = pwd.getpwuid(os.getuid()).pw_name
        script = f'''
acfs_generated_resolve_current_user() {{ echo {shlex.quote(name)}; }}
acfs_generated_getent_passwd_entry() {{ getent passwd {shlex.quote(name)}; }}
acfs_configure_login_shell() {{ echo 'refused unsafe shell' >&2; return 1; }}
'''
        result = subprocess.run(["bash", "-euc", script + self.generated_shell_step()],
                                env=dict(os.environ, HOME=str(self.home), SHELL="/usr/sbin/zsh"), text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refused unsafe shell", result.stderr)

    def test_generated_helper_is_identical_to_legacy_helper(self):
        generated = (ROOT / "scripts/generated/install_shell.sh").read_text()
        self.assertIn(HELPERS.strip(), generated)


if __name__ == "__main__":
    unittest.main()
