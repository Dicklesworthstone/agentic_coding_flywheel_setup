#!/usr/bin/env python3
"""Host-safe tests of upgrade_resume.sh, not a live OS upgrade.

Execute the real startup prefix and extracted production functions. Only fixed
production paths in startup are redirected into root-owned temporary fixtures;
Bash, filesystem permissions, symlinks, hardlinks and process environments are
real. Fixtures are retained, not deleted, for diagnostics.
"""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
SOURCE = Path(os.environ.get("ACFS_RESUME_TEST_SOURCE", REPO / "scripts/lib/upgrade_resume.sh"))
TEXT = SOURCE.read_text()


def function(name):
    found = re.search(r"^" + re.escape(name) + r"\(\) \{\n.*?^\}", TEXT, re.M | re.S)
    if not found:
        raise AssertionError(f"Production function is missing: {name}")
    return found[0] + "\n"


def run(script, *args, env=None):
    return subprocess.run(["/bin/bash", "--noprofile", "--norc", "-c", script, "resume-test", *map(str, args)],
                          text=True, capture_output=True, timeout=10, env=env)


class ResumeTrustTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="acfs-resume-trust-"))
        self.state_dir = self.root / "resume"
        self.lib = self.state_dir / "lib"
        self.lib.mkdir(parents=True)
        self.log_parent = self.root / "logs"
        self.log_parent.mkdir()
        self.log = self.log_parent / "acfs" / "upgrade_resume.log"
        self.state = self.state_dir / "state.json"
        self.state.write_text('{"ubuntu_upgrade":{"target_version":"26.04"}}\n')
        self.context = self.state_dir / "continue_context.env"
        self.context.write_text('CONTINUE_HOME=/root\nCONTINUE_INSTALL_ARGS=(--yes --skip-ubuntu-upgrade)\n')
        for path in [self.lib / "state.sh", self.lib / "ubuntu_upgrade.sh", self.state_dir / "continue_install.sh"]:
            path.write_text('#!/bin/bash\ntrue\n')
            path.chmod(0o644)

    def checked(self, result, expected=0):
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)

    def functions(self, *names):
        return 'set -euo pipefail\n' + ''.join(function(n) for n in names)

    def file_check(self, path):
        script = self.functions("resume_recovery_directory_safe", "resume_recovery_file_safe")
        return run(script + '\nresume_recovery_file_safe "$1"\n', path)

    def startup(self, env=None):
        # Execute all startup statements up to the first state read, including
        # the production root/input/log gates. Nothing reaches systemd or dpkg.
        code = TEXT.split('# Read target version from state file if available.')[0]
        code = code.replace('ACFS_RESUME_DIR="/var/lib/acfs"', f'ACFS_RESUME_DIR="{self.state_dir}"', 1)
        code = code.replace('ACFS_LOG="/var/log/acfs/upgrade_resume.log"', f'ACFS_LOG="{self.log}"', 1)
        return run(code + '\nprintf "STARTUP_OK\\n"\n', env=env)

    def context_read(self):
        code = self.functions("resume_recovery_directory_safe", "resume_recovery_file_safe", "load_continue_context")
        return run(code + '''
ACFS_CONTINUE_CONTEXT_FILE="$1"
CONTINUE_TARGET_USER=wrong_user
CONTINUE_ACFS_REF=wrong_ref
CONTINUE_INSTALL_ARGS=(wrong_arg)
load_continue_context
printf '%s|%s|%s|%s\n' "$CONTINUE_HOME" "$CONTINUE_TARGET_USER" "$CONTINUE_ACFS_REF" "${CONTINUE_INSTALL_ARGS[*]}"
''', self.context)

    def test_help_is_inert_with_hostile_environment(self):
        marker = self.root / "poison"
        shims = self.root / "bin"
        shims.mkdir()
        for name in ["mkdir", "dirname", "jq", "date", "tee", "stat", "systemctl"]:
            path = shims / name
            path.write_text(f'#!/bin/sh\nprintf poison >> "{marker}"\nexit 71\n')
            path.chmod(0o755)
        env = dict(os.environ, PATH=str(shims), ACFS_UPGRADE_LOCK_FD="77", _ACFS_STATE_SH_LOADED="1")
        result = subprocess.run(['/bin/bash', str(SOURCE), '--help'], env=env, text=True,
                                capture_output=True, timeout=5)
        self.checked(result)
        self.assertIn("Usage:", result.stdout)
        self.assertFalse(marker.exists())

    def test_startup_discards_exported_functions_and_shell_hooks(self):
        marker = self.root / "poison"
        startup_hook = self.root / "bashenv"
        startup_hook.write_text(f'''mkdir() {{ printf poison >> "{marker}"; }}
stat() {{ printf poison >> "{marker}"; }}
source() {{ printf poison >> "{marker}"; }}
export -f mkdir stat source
''')
        env = dict(os.environ, BASH_ENV=str(startup_hook), ENV=str(startup_hook))
        # The hook only defines functions. Executed pre-startup side effects are
        # beyond a script's control; subsequent executable hooks must be gone.
        result = self.startup(env)
        self.checked(result)
        self.assertFalse(marker.exists())

    def test_trusted_path_and_lock_authority_are_reset_before_loading(self):
        prefix = TEXT.split('# Recovery is an explicit CLI operation')[0]
        env = dict(os.environ, PATH='/tmp/untrusted', ACFS_UPGRADE_LOCK_FD='200',
                   _ACFS_UPGRADE_LOCK_FILE='/tmp/lock', ACFS_LOCK_FD='200', _ACFS_STATE_LOCKED='true',
                   _ACFS_STATE_LOCK_FILE='/tmp/state.lock', _ACFS_STATE_LOCK_DEPTH='99', _ACFS_STATE_SH_LOADED='1')
        result = run(prefix + '''
[[ "$PATH" == /usr/sbin:/usr/bin:/sbin:/bin ]]
for name in ACFS_UPGRADE_LOCK_FD _ACFS_UPGRADE_LOCK_FILE ACFS_LOCK_FD _ACFS_STATE_LOCKED _ACFS_STATE_LOCK_FILE _ACFS_STATE_LOCK_DEPTH _ACFS_STATE_SH_LOADED; do
  [[ ! -v "$name" ]] || exit 12
done
''', env=env)
        self.checked(result)

    def test_invalid_arguments_exit_before_mutation(self):
        result = subprocess.run(['/bin/bash', str(SOURCE), '--retarget-ubuntu=25.10'], text=True,
                                capture_output=True, timeout=5)
        self.checked(result, 2)

    @unittest.skipUnless(os.geteuid() == 0, "root-owned recovery boundary requires root fixtures")
    def test_root_startup_accepts_safe_inputs_and_creates_private_log(self):
        self.checked(self.startup())
        self.assertEqual(self.log.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.log.parent.stat().st_mode & 0o777, 0o700)
        self.checked(self.startup())
        self.assertEqual(self.log.read_bytes(), b'')

    @unittest.skipUnless(os.geteuid() == 0, "requires switching to an unprivileged identity")
    def test_normal_resume_refuses_nonroot_before_recovery_io(self):
        result = subprocess.run(['/usr/bin/setpriv', '--reuid=65534', '--regid=65534', '--clear-groups',
                                 '/bin/bash', str(SOURCE)], text=True, capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('must run directly as root', result.stderr)

    @unittest.skipUnless(os.geteuid() == 0, "root-owned recovery boundary requires root fixtures")
    def test_input_checks_precede_log_creation(self):
        self.lib.joinpath('state.sh').chmod(0o666)
        self.checked(self.startup(), 1)
        self.assertFalse(self.log.parent.exists())

    @unittest.skipUnless(os.geteuid() == 0, "root-owned recovery boundary requires root fixtures")
    def test_redirected_state_lock_is_refused_before_any_write(self):
        target = self.root / 'unrelated'
        target.write_text('KEEP')
        Path(str(self.state) + '.lock').symlink_to(target)
        self.checked(self.startup(), 1)
        self.assertFalse(self.log.parent.exists())
        self.assertEqual(target.read_text(), 'KEEP')

    @unittest.skipUnless(os.geteuid() == 0, "root-owned recovery boundary requires root fixtures")
    def test_rejects_untrusted_and_malformed_optional_libraries(self):
        for name, content in [('logging.sh', 'if then'), ('progress.sh', 'true')]:
            with self.subTest(name=name):
                path = self.lib / name
                path.write_text(content)
                path.chmod(0o666 if name == 'progress.sh' else 0o644)
                self.checked(self.startup(), 1)
                self.assertFalse(self.log.parent.exists())
                path.rename(path.with_suffix('.evidence'))

    @unittest.skipUnless(os.geteuid() == 0, "root-owned recovery boundary requires root fixtures")
    def test_rejects_symlinked_library_before_executing_contents(self):
        original = self.lib / 'state.sh'
        original.rename(self.lib / 'original.evidence')
        payload = self.root / 'payload'
        payload.write_text('touch "$HOME/SHOULD_NOT_RUN"\n')
        original.symlink_to(payload)
        self.checked(self.startup(), 1)
        self.assertFalse(self.log.parent.exists())

    @unittest.skipUnless(os.geteuid() == 0, "root-owned recovery boundary requires root fixtures")
    def test_regular_root_files_accept_private_or_readable_modes(self):
        for mode in [0o600, 0o640, 0o644, 0o700, 0o755]:
            self.state.chmod(mode)
            self.checked(self.file_check(self.state))

    @unittest.skipUnless(os.geteuid() == 0, "root-owned recovery boundary requires root fixtures")
    def test_refuses_file_links_and_special_files(self):
        symlink = self.root / 'symlink'
        symlink.symlink_to(self.state)
        hardlink = self.root / 'hardlink'
        os.link(self.state, hardlink)
        fifo = self.root / 'fifo'
        os.mkfifo(fifo)
        for path in [symlink, hardlink, self.state, fifo, self.root, self.root / 'missing']:
            with self.subTest(path=path.name):
                self.checked(self.file_check(path), 1)

    @unittest.skipUnless(os.geteuid() == 0, "root-owned recovery boundary requires root fixtures")
    def test_refuses_wrong_owner_or_writable_file(self):
        for mode in [0o620, 0o602, 0o666]:
            self.state.chmod(mode)
            self.checked(self.file_check(self.state), 1)
        self.state.chmod(0o600)
        os.chown(self.state, 65534, 65534)
        self.checked(self.file_check(self.state), 1)

    @unittest.skipUnless(os.geteuid() == 0, "root-owned recovery boundary requires root fixtures")
    def test_refuses_unsafe_ancestors_and_noncanonical_paths(self):
        alias = self.root / 'alias'
        alias.symlink_to(self.state_dir, target_is_directory=True)
        for path in [alias / 'state.json', str(self.state_dir) + '/../resume/state.json',
                     str(self.state_dir) + '/./state.json', str(self.state_dir) + '//state.json', 'relative/state.json']:
            with self.subTest(path=str(path)):
                self.checked(self.file_check(path), 1)
        self.state_dir.chmod(0o1777)
        self.checked(self.file_check(self.state), 1)
        self.state_dir.chmod(0o755)
        os.chown(self.state_dir, 65534, 65534)
        self.checked(self.file_check(self.state), 1)

    @unittest.skipUnless(os.geteuid() == 0, "root-owned recovery boundary requires root fixtures")
    def test_symlinked_log_parent_and_log_do_not_change_target(self):
        other = self.root / 'other'
        other.mkdir()
        self.log.parent.symlink_to(other, target_is_directory=True)
        self.checked(self.startup(), 1)
        self.assertFalse((other / self.log.name).exists())
        self.log.parent.rename(self.log_parent / 'old-link.evidence')
        self.log.parent.mkdir()
        target = self.root / 'target'
        target.write_text('KEEP')
        self.log.symlink_to(target)
        self.checked(self.startup(), 1)
        self.assertEqual(target.read_text(), 'KEEP')

    @unittest.skipUnless(os.geteuid() == 0, "root-owned recovery boundary requires root fixtures")
    def test_context_resets_omitted_inherited_values(self):
        result = self.context_read()
        self.checked(result)
        self.assertEqual(result.stdout.strip(), '/root|||--yes --skip-ubuntu-upgrade')

    @unittest.skipUnless(os.geteuid() == 0, "root-owned recovery boundary requires root fixtures")
    def test_context_preserves_callers_array_scope_not_shadowed_globals(self):
        code = self.functions("resume_recovery_directory_safe", "resume_recovery_file_safe", "load_continue_context")
        result = run(code + '''
ACFS_CONTINUE_CONTEXT_FILE="$1"
CONTINUE_INSTALL_ARGS=(global_old)
f() {
 local -a CONTINUE_INSTALL_ARGS=(local_old)
 load_continue_context
 [[ "${CONTINUE_INSTALL_ARGS[*]}" == '--yes --skip-ubuntu-upgrade' ]]
}
f
[[ "${CONTINUE_INSTALL_ARGS[*]}" == global_old ]]
''', self.context)
        self.checked(result)

    @unittest.skipUnless(os.geteuid() == 0, "root-owned recovery boundary requires root fixtures")
    def test_untrusted_context_does_not_execute(self):
        marker = self.root / 'executed'
        self.context.write_text(f'touch "{marker}"\n')
        self.context.chmod(0o666)
        self.checked(self.context_read(), 1)
        self.assertFalse(marker.exists())

    def test_continuation_uses_privileged_shell_mode(self):
        self.assertIn('/bin/bash -p "$script"', function('launch_continue_script'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
