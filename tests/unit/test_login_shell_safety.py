#!/usr/bin/env python3
"""Exercise login-shell policy against isolated passwd, shells, and command fixtures.

The production Bash functions run unchanged apart from fixed host paths being
redirected in memory to a retained temporary tree. Every chsh/sudo/getent command
in that tree is a test double; no test changes a real account or /etc file.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import pty
import re
import shlex
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(os.environ.get("ACFS_LOGIN_SHELL_TEST_SOURCE", ROOT / "scripts/lib/user.sh"))


COMMAND_STUB = r'''#!/usr/bin/python3
import json
import os
from pathlib import Path
import subprocess
import sys

tool = Path(sys.argv[0]).name
args = sys.argv[1:]
root = Path(os.environ["TEST_ROOT"])
passwd = root / "etc/passwd"
log = root / "calls.jsonl"
caller = os.environ.get("TEST_CALLER", "tester")

def record():
    with log.open("a") as stream:
        stream.write(json.dumps({"tool": tool, "args": args, "euid": os.geteuid()}) + "\n")

if tool == "getent":
    if not args or args[0] != "passwd":
        sys.exit(2)
    if os.environ.get("TEST_NSS_FAIL") == "1":
        sys.exit(2)
    if os.environ.get("TEST_NSS_FAIL_AFTER_CHANGE") == "1" and log.exists() and any(
        json.loads(line)["tool"] == "chsh" for line in log.read_text().splitlines()
    ):
        sys.exit(2)
    file = root / "nss-passwd" if (root / "nss-passwd").exists() else passwd
    lines = file.read_text().splitlines() if file.is_file() else []
    matches = [line for line in lines if len(args) == 1 or line.split(":")[0] == args[1]]
    if matches:
        print("\n".join(matches))
        sys.exit(0)
    sys.exit(2)
if tool in ("id", "whoami"):
    if tool == "whoami" or args == ["-un"]:
        print(caller)
        sys.exit(0)
    if args == ["-u"]:
        print(os.geteuid())
        sys.exit(0)
    if args[:1] == ["-u"]:
        print(os.environ.get("TEST_UID", str(os.geteuid())))
        sys.exit(0)
    sys.exit(2)
if tool == "chown":
    record()
    sys.exit(0)
if tool == "runuser":
    record()
    if len(args) < 4 or args[0] != "-u" or args[2] != "--":
        sys.exit(2)
    child_env = dict(os.environ, TEST_CALLER=args[1])
    uid = int(os.environ["TEST_UID"])
    sys.exit(subprocess.run(args[3:], env=child_env, user=uid, group=uid, extra_groups=[], check=False).returncode)
if tool == "sudo":
    record()
    if os.environ.get("TEST_SUDO", "allow") == "deny":
        print("sudo: a password is required", file=sys.stderr)
        sys.exit(1)
    if args[:1] == ["-n"]:
        args = args[1:]
    if args[:1] == ["--"]:
        args = args[1:]
    if args == ["true"]:
        sys.exit(0)
    if not args:
        sys.exit(2)
    sys.exit(subprocess.run(args, check=False).returncode)
if tool == "chsh":
    previous = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
    calls = sum(item["tool"] == "chsh" for item in previous)
    record()
    if args[:1] != ["-s"] or len(args) not in (2, 3):
        sys.exit(92)
    shell = args[1]
    target = args[2] if len(args) == 3 else caller
    mode = os.environ.get("TEST_CHSH", "apply")
    if mode == "fail" or (mode == "wrong_rollback_fail" and calls):
        print("chsh: simulated failure", file=sys.stderr)
        sys.exit(1)
    if mode == "noop":
        sys.exit(0)
    if mode in ("wrong", "wrong_rollback_fail") and not calls:
        shell = str(root / "usr/sbin/zsh")
    lines = passwd.read_text().splitlines()
    updated = []
    for line in lines:
        fields = line.split(":")
        if fields[0] == target:
            fields[6] = shell
        updated.append(":".join(fields))
    passwd.write_text("\n".join(updated) + "\n")
    if mode == "revoke" and not calls:
        shells = root / "etc/shells"
        old = shells.read_text()
        (root / "shells.before-revoke").write_text(old)
        shells.write_text("\n".join(line for line in old.splitlines() if line != shell) + "\n")
    if mode == "fail_after" and not calls:
        print("chsh: failed after writing", file=sys.stderr)
        sys.exit(1)
    sys.exit(0)
raise SystemExit("Unexpected fixture command: " + tool)
'''


class LoginShellTests(unittest.TestCase):
    def setUp(self):
        # Preserve test evidence, matching the repository's no-deletion policy.
        self.root = Path(tempfile.mkdtemp(prefix="acfs-login-shell-"))
        self.bin = self.root / "usr/bin"
        self.bin.mkdir(parents=True)
        (self.root / "usr/sbin").symlink_to("bin", target_is_directory=True)
        (self.root / "bin").symlink_to("usr/bin", target_is_directory=True)
        (self.root / "sbin").symlink_to("usr/bin", target_is_directory=True)
        (self.root / "usr/local/bin").mkdir(parents=True)
        (self.root / "usr/local/sbin").mkdir(parents=True)
        (self.root / "etc").mkdir()
        self.home = self.root / "home/tester"
        self.home.mkdir(parents=True)
        self.passwd = self.root / "etc/passwd"
        self.shells = self.root / "etc/shells"
        self.log = self.root / "calls.jsonl"
        self.zsh = self.bin / "zsh"
        self.original = self.bin / "bash"
        self.uid = os.geteuid()
        for name in ("getent", "id", "whoami", "chsh", "sudo", "chown", "runuser"):
            path = self.bin / name
            path.write_text(COMMAND_STUB)
            path.chmod(0o755)
        for name in ("awk", "cat", "chmod", "cmp", "cp", "date", "env", "flock", "grep", "head",
                     "install", "ln", "mkdir", "mktemp", "mv", "od", "readlink", "sed", "stat", "tail",
                     "tee", "test", "tr", "true"):
            real = Path("/usr/bin") / name
            if real.exists():
                (self.bin / name).symlink_to(real)
        self.original.symlink_to("/bin/bash")
        self.zsh.write_text("#!/bin/sh\nexit 0\n")
        self.zsh.chmod(0o755)
        self.account()
        self.approve(self.original, self.zsh)

    def account(self, shell=None, *, name="tester", uid=None, home=None):
        entry = f"{name}:x:{self.uid if uid is None else uid}:{self.uid}::{home or self.home}:{shell or self.original}\n"
        self.passwd.write_text(entry)
        return entry

    def approve(self, *paths, final_newline=True):
        self.shells.write_text("\n".join(map(str, paths)) + ("\n" if final_newline else ""))
        self.shells.chmod(0o644)

    def calls(self, tool="chsh"):
        records = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return [record["args"] for record in records if record["tool"] == tool]

    def current_shell(self):
        return self.passwd.read_text().rstrip("\n").split(":")[6]

    def redirect_paths(self, source):
        # Match once, so paths inserted for /usr/bin are not remapped as /bin.
        pattern = r"/(?:etc/(?:shells|passwd)|usr/(?:local/(?:bin|sbin)|bin|sbin)|bin|sbin)(?=/|[\s\"';)]|$)"
        return re.sub(pattern, lambda match: str(self.root) + match[0], source)

    def invoke(self, body='set_default_shell ""', *, code=0, env=None, uid=None, terminal=False):
        settings = {
            "PATH": f"{self.root}/usr/sbin:{self.bin}:{self.root}/bin:/usr/bin:/bin",
            "HOME": str(self.home), "TARGET_HOME": str(self.home), "TARGET_USER": "tester",
            "SHELL": str(self.original), "TEST_ROOT": str(self.root), "TEST_UID": str(self.uid),
            "ACFS_LIB_DIR": str(ROOT / "scripts/lib"),
            "LC_ALL": "C", "LANG": "C", "TEST_CALLER": "tester",
        }
        settings.update(env or {})
        source = self.redirect_paths(SOURCE.read_text())
        program = "set -euo pipefail\n" + source + "\n" + body + "\n"
        master = slave = None
        try:
            if terminal:
                master, slave = pty.openpty()
                argv, streams = ["/bin/bash", "-p", "-c", program], {"stdin": slave}
            else:
                argv, streams = ["/bin/bash", "-p", "-s"], {"input": program}
            result = subprocess.run(
                argv, **streams, capture_output=True, text=True,
                env=settings, timeout=30, user=uid, group=uid, extra_groups=[] if uid is not None else None,
            )
        finally:
            if master is not None:
                os.close(master)
                os.close(slave)
        self.assertNotIn("command not found", result.stderr, result.stderr)
        self.assertNotIn("unbound variable", result.stderr, result.stderr)
        if code == 0:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_arch_usrmerge_alias_is_replaced_with_literal_approved_path(self):
        alias = self.root / "usr/sbin/zsh"
        self.assertTrue(alias.samefile(self.zsh))
        self.invoke('set_default_shell "$(command -v zsh)"')
        self.assertEqual(self.current_shell(), str(self.zsh))
        self.assertEqual(self.calls(), [["-s", str(self.zsh), "tester"]])
        self.assertEqual((self.home / ".shell.pre-acfs").read_text(), f"{self.original}\n")
        self.assertEqual((self.home / ".shell.pre-acfs").stat().st_mode & 0o777, 0o600)

    def test_different_path_orderings_cannot_select_unapproved_alias(self):
        for leading in (self.root / "usr/sbin", self.bin, self.root / "bin", self.root / "sbin"):
            with self.subTest(leading=leading):
                result = self.invoke('user_select_login_shell "$(command -v zsh)"',
                                     env={"PATH": f"{leading}:{self.bin}:/usr/bin:/bin"})
                self.assertEqual(result.stdout.strip(), str(self.zsh))
        self.assertEqual(self.calls(), [])

    def test_only_approved_bin_alias_remains_literal_even_if_canonical_path_exists(self):
        approved_alias = self.root / "bin/zsh"
        self.approve(self.original, approved_alias)
        self.invoke()
        self.assertEqual(self.current_shell(), str(approved_alias))

    def test_usr_bin_is_preferred_when_sbin_alias_is_also_approved(self):
        alias = self.root / "usr/sbin/zsh"
        self.approve(self.original, alias, self.zsh)
        self.invoke()
        self.assertEqual(self.current_shell(), str(self.zsh))

    def test_custom_approved_zsh_path_can_be_selected(self):
        custom = self.root / "opt/vendor/bin/zsh"
        custom.parent.mkdir(parents=True)
        custom.symlink_to(self.zsh)
        self.approve(self.original, custom)
        self.invoke()
        self.assertEqual(self.current_shell(), str(custom))

    def test_shells_final_line_without_newline_is_supported(self):
        self.approve(self.original, self.zsh, final_newline=False)
        self.invoke()
        self.assertEqual(self.current_shell(), str(self.zsh))

    def test_comments_blank_lines_and_duplicates_do_not_change_selection(self):
        self.shells.write_text(f"# system login shells\n\n{self.original}\n{self.zsh}\n{self.zsh}\n")
        self.invoke()
        self.assertEqual(self.current_shell(), str(self.zsh))

    def test_initial_shell_selection_uses_literal_approved_bash_path(self):
        result = self.invoke('user_select_initial_login_shell bash')
        self.assertEqual(result.stdout.strip(), str(self.original))

    def test_initial_shell_selection_refuses_when_bash_is_not_approved(self):
        self.approve(self.zsh)
        self.invoke('user_select_initial_login_shell bash', code=1)

    def test_whitespace_crlf_inline_comments_and_partial_matches_are_not_approval(self):
        for entry in (f" {self.zsh}", f"{self.zsh} ", f"{self.zsh}\r", f"{self.zsh} # zsh",
                      f"#{self.zsh}", f"{self.zsh}.old", f"{self.zsh}/", "zsh"):
            with self.subTest(entry=entry):
                self.shells.write_bytes(f"{self.original}\n{entry}\n".encode())
                self.invoke(code=1)
                self.assertEqual(self.current_shell(), str(self.original))
                self.assertEqual(self.calls(), [])
        self.assertFalse((self.home / ".shell.pre-acfs").exists())

    def test_literal_membership_does_not_treat_shell_path_as_regular_expression(self):
        custom = self.root / "vendor.v1/zsh"
        custom.parent.mkdir()
        custom.symlink_to(self.zsh)
        self.shells.write_text(f"{self.original}\n{str(custom).replace('vendor.v1', 'vendorXv1')}\n")
        self.invoke(f'user_shell_is_approved {shlex.quote(str(custom))}', code=1)

    def test_missing_shells_file_refuses_before_mutation(self):
        self.shells.rename(self.root / "shells.saved")
        self.invoke(code=1)
        self.assertEqual(self.calls(), [])
        self.assertEqual(self.current_shell(), str(self.original))

    def test_empty_or_comment_only_shells_refuses_before_mutation(self):
        for contents in ("", "# No approved login shells\n\n"):
            with self.subTest(contents=contents):
                self.shells.write_text(contents)
                self.invoke(code=1)
                self.assertEqual(self.calls(), [])

    def test_world_writable_shells_file_refuses_before_mutation(self):
        self.shells.chmod(0o666)
        self.invoke(code=1)
        self.assertEqual(self.calls(), [])

    def test_directory_and_fifo_shells_files_are_rejected_without_blocking(self):
        self.shells.rename(self.root / "shells.saved")
        self.shells.mkdir()
        self.invoke(code=1)
        self.shells.rename(self.root / "shells.directory")
        os.mkfifo(self.shells)
        self.invoke(code=1)
        self.assertEqual(self.calls(), [])

    def test_missing_nonexecutable_or_directory_zsh_is_rejected(self):
        self.zsh.chmod(0o644)
        self.invoke(code=1)
        self.zsh.rename(self.bin / "zsh.saved")
        self.invoke(code=1)
        self.zsh.mkdir()
        self.invoke(code=1)
        self.assertEqual(self.calls(), [])

    def test_repeated_install_preserves_first_backup_and_skips_second_chsh(self):
        self.invoke('set_default_shell ""\nset_default_shell ""')
        self.assertEqual(self.calls(), [["-s", str(self.zsh), "tester"]])
        self.assertEqual((self.home / ".shell.pre-acfs").read_text(), f"{self.original}\n")

    def test_preexisting_backup_is_never_overwritten(self):
        backup = self.home / ".shell.pre-acfs"
        backup.write_text("/previously/saved/shell\n")
        backup.chmod(0o600)
        self.invoke()
        self.assertEqual(backup.read_text(), "/previously/saved/shell\n")

    def test_backup_symlink_is_rejected_without_changing_link_target(self):
        evidence = self.root / "important-file"
        evidence.write_text("preserve this evidence\n")
        (self.home / ".shell.pre-acfs").symlink_to(evidence)
        self.invoke(code=1)
        self.assertEqual(self.calls(), [])
        self.assertEqual(evidence.read_text(), "preserve this evidence\n")

    def test_backup_directory_is_rejected_before_chsh(self):
        (self.home / ".shell.pre-acfs").mkdir()
        self.invoke(code=1)
        self.assertEqual(self.calls(), [])

    def test_current_approved_shell_is_idempotent(self):
        self.account(self.zsh)
        self.invoke()
        self.assertEqual(self.calls(), [])
        self.invoke('user_login_shell_configured')

    def test_current_unlisted_zsh_alias_is_repaired_even_when_shell_environment_says_zsh(self):
        self.account(self.root / "usr/sbin/zsh")
        self.invoke('user_login_shell_configured', code=1, env={"SHELL": str(self.zsh)})
        self.invoke(env={"SHELL": str(self.zsh)})
        self.assertEqual(self.current_shell(), str(self.zsh))
        self.assertEqual(self.calls(), [["-s", str(self.zsh), "tester"]])

    def test_nonzero_chsh_reports_failure_and_retains_original(self):
        self.invoke(code=1, env={"TEST_CHSH": "fail"})
        self.assertEqual(self.current_shell(), str(self.original))
        self.assertEqual((self.home / ".shell.pre-acfs").read_text(), f"{self.original}\n")

    def test_zero_exit_chsh_that_does_not_change_account_is_failure(self):
        self.invoke(code=1, env={"TEST_CHSH": "noop"})
        self.assertEqual(self.current_shell(), str(self.original))

    def test_chsh_that_changes_to_unapproved_alias_is_detected_and_rolled_back(self):
        self.invoke(code=1, env={"TEST_CHSH": "wrong"})
        self.assertEqual(self.current_shell(), str(self.original))
        self.assertEqual(self.calls(), [["-s", str(self.zsh), "tester"],
                                       ["-s", str(self.original), "tester"]])

    def test_nonzero_chsh_after_mutation_is_rolled_back(self):
        self.invoke(code=1, env={"TEST_CHSH": "fail_after"})
        self.assertEqual(self.current_shell(), str(self.original))
        self.assertEqual(self.calls()[-1], ["-s", str(self.original), "tester"])

    def test_failed_change_never_restores_an_unapproved_original_alias(self):
        unsafe_original = self.root / "usr/sbin/zsh"
        self.account(unsafe_original)
        self.invoke(code=1, env={"TEST_CHSH": "fail_after"})
        self.assertEqual(self.current_shell(), str(self.zsh))
        self.assertEqual(self.calls(), [["-s", str(self.zsh), "tester"]])
        self.assertEqual((self.home / ".shell.pre-acfs").read_text(), f"{unsafe_original}\n")

    def test_recovery_failure_is_explicit_and_keeps_backup(self):
        result = self.invoke(code=1, env={"TEST_CHSH": "wrong_rollback_fail"})
        self.assertEqual((self.home / ".shell.pre-acfs").read_text(), f"{self.original}\n")
        self.assertRegex(result.stderr.lower(), r"recover|restor|rollback")
        self.assertIn(str(self.original), result.stderr)

    def test_shell_approval_revoked_during_chsh_is_detected_and_rolled_back(self):
        self.invoke(code=1, env={"TEST_CHSH": "revoke"})
        self.assertEqual(self.current_shell(), str(self.original))

    def test_external_bash_account_requires_provider_shell_change(self):
        entry = self.passwd.read_text()
        (self.root / "nss-passwd").write_text(entry)
        self.passwd.write_text("other:x:999:999::/other:/bin/bash\n")
        result = self.invoke(code=1)
        self.assertEqual(self.calls(), [])
        self.assertFalse((self.home / ".bashrc").exists())
        self.assertIn("identity provider", result.stderr.lower())
        self.invoke('user_login_shell_configured', code=1)

    def test_external_nonbash_account_is_not_reported_configured_by_bashrc(self):
        unknown = self.bin / "fish"
        unknown.symlink_to(self.zsh)
        self.approve(self.original, self.zsh, unknown)
        entry = self.account(unknown)
        (self.root / "nss-passwd").write_text(entry)
        self.passwd.write_text("other:x:999:999::/other:/bin/bash\n")
        self.invoke(code=1)
        self.assertEqual(self.calls(), [])
        self.invoke('user_login_shell_configured', code=1)

    def test_external_partial_handoff_is_refused_without_appending_duplicate(self):
        entry = self.passwd.read_text()
        (self.root / "nss-passwd").write_text(entry)
        self.passwd.write_text("other:x:999:999::/other:/bin/bash\n")
        partial = ('# ACFS externally-managed shell handoff\n'
                   'if [[ $- == *i* ]] && [[ -t 0 ]] && command -v zsh >/dev/null 2>&1 '
                   '&& [[ -z "${ACFS_ZSH_HANDOFF_ACTIVE:-}" ]]; then\n'
                   '    export ACFS_ZSH_HANDOFF_ACTIVE=1\nfi\n')
        (self.home / ".bashrc").write_text(partial)
        self.invoke(code=1)
        self.assertEqual((self.home / ".bashrc").read_text(), partial)
        self.assertEqual(self.calls(), [])

    def test_external_syntactically_invalid_bashrc_is_preserved_and_refused(self):
        entry = self.passwd.read_text()
        (self.root / "nss-passwd").write_text(entry)
        self.passwd.write_text("other:x:999:999::/other:/bin/bash\n")
        invalid = 'if [[ 1 == 1 ]]; then\n'
        (self.home / ".bashrc").write_text(invalid)
        self.invoke(code=1)
        self.assertEqual((self.home / ".bashrc").read_text(), invalid)
        self.assertEqual(self.calls(), [])

    def test_local_account_identity_accepts_matching_nss_and_expected_home(self):
        self.invoke('user_verify_local_account_identity "$TARGET_USER" "$TARGET_HOME"')

    def test_local_account_identity_rejects_unexpected_home_before_privilege_changes(self):
        wrong_home = self.root / "home/wrong"
        self.invoke(f'user_verify_local_account_identity "$TARGET_USER" {shlex.quote(str(wrong_home))}', code=1)

    def test_local_account_identity_rejects_nss_local_disagreement(self):
        fields = self.passwd.read_text().strip().split(":")
        fields[2] = str(int(fields[2]) + 1)
        (self.root / "nss-passwd").write_text(":".join(fields) + "\n")
        self.invoke('user_verify_local_account_identity "$TARGET_USER" "$TARGET_HOME"', code=1)

    def test_created_identity_can_require_exact_initial_shell(self):
        self.invoke(f'user_verify_local_account_identity "$TARGET_USER" "$TARGET_HOME" {shlex.quote(str(self.original))}')
        self.invoke(f'user_verify_local_account_identity "$TARGET_USER" "$TARGET_HOME" {shlex.quote(str(self.zsh))}', code=1)

    def test_nss_shadowed_local_account_is_rejected(self):
        for field, replacement in ((2, "42000"), (5, str(self.root / "different-home")),
                                   (6, str(self.root / "usr/sbin/zsh"))):
            with self.subTest(field=field):
                fields = self.passwd.read_text().strip().split(":")
                fields[field] = replacement
                (self.root / "nss-passwd").write_text(":".join(fields) + "\n")
                self.invoke(code=1)
                self.assertEqual(self.calls(), [])
                self.assertEqual(self.current_shell(), str(self.original))

    def test_nss_failure_does_not_fall_back_to_a_local_account(self):
        self.invoke(code=1, env={"TEST_NSS_FAIL": "1"})
        self.assertEqual(self.calls(), [])

    def test_nss_failure_after_mutation_refuses_blind_rollback(self):
        result = self.invoke(code=1, env={"TEST_NSS_FAIL_AFTER_CHANGE": "1"})
        # Preserve the evidence and refuse a second mutation while the
        # effective account's identity can no longer be verified through NSS.
        self.assertEqual(self.current_shell(), str(self.zsh))
        self.assertEqual(self.calls(), [["-s", str(self.zsh), "tester"]])
        self.assertEqual((self.home / ".shell.pre-acfs").read_text(), f"{self.original}\n")
        self.assertIn("recovery", result.stderr.lower())

    def test_missing_local_passwd_with_working_nss_is_not_treated_as_external(self):
        (self.root / "nss-passwd").write_text(self.passwd.read_text())
        self.passwd.rename(self.root / "passwd.saved")
        self.invoke(code=1)
        self.assertEqual(self.calls(), [])
        self.assertFalse((self.home / ".bashrc").exists())

    def test_passwd_home_wins_over_stale_target_home(self):
        stale = self.root / "stale-home"
        stale.mkdir()
        self.invoke(env={"TARGET_HOME": str(stale), "HOME": str(stale)})
        self.assertTrue((self.home / ".shell.pre-acfs").is_file())
        self.assertFalse((stale / ".shell.pre-acfs").exists())

    def test_generated_installed_check_cannot_skip_unsafe_existing_shell(self):
        (self.home / ".oh-my-zsh").mkdir()
        (self.home / ".oh-my-zsh/oh-my-zsh.sh").write_text("# fixture oh-my-zsh\n")
        (self.home / ".acfs/zsh").mkdir(parents=True)
        (self.home / ".acfs/zsh/acfs.zshrc").write_text("# fixture acfs config\n")
        (self.home / ".zshrc").write_text("# fixture zsh config\n")
        check = subprocess.check_output([
            "/bin/bash", "-p", "-euo", "pipefail", "-c",
            'source "$1"; printf "%s" "${ACFS_MODULE_INSTALLED_CHECK[shell.omz]}"',
            "_", str(ROOT / "scripts/generated/manifest_index.sh"),
        ], text=True, env={"PATH": "/usr/bin:/bin", "HOME": str(self.home)})
        self.account(self.root / "usr/sbin/zsh")
        self.invoke(check, code=1)
        self.account(self.zsh)
        self.invoke(check)

    def prepare_root_install_for_nonroot_target(self):
        if os.geteuid() != 0:
            self.skipTest("Root-to-target orchestration requires a root test runner")
        self.uid = 65534
        self.account(uid=self.uid)
        self.root.chmod(0o755)
        os.chown(self.home, self.uid, self.uid)

    def test_root_changes_target_account_but_writes_recovery_record_as_target(self):
        self.prepare_root_install_for_nonroot_target()
        self.invoke(env={"TEST_CALLER": "root", "TEST_SUDO": "deny"})
        self.assertEqual(self.current_shell(), str(self.zsh))
        self.assertEqual((self.home / ".shell.pre-acfs").stat().st_uid, self.uid)
        records = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual([item["euid"] for item in records if item["tool"] == "chsh"], [0])
        self.assertEqual(self.calls("sudo"), [])

    def test_root_refuses_shell_that_target_user_cannot_execute(self):
        self.prepare_root_install_for_nonroot_target()
        self.zsh.chmod(0o700)
        self.invoke(code=1, env={"TEST_CALLER": "root", "TEST_SUDO": "deny"})
        self.assertEqual(self.current_shell(), str(self.original))
        self.assertEqual(self.calls(), [])

    def generated_login_module_body(self):
        generated = (ROOT / "scripts/generated/install_shell.sh").read_text()
        module = re.search(r'^acfs_generated_install_shell_login\(\) \{\n.*?^\}', generated, re.M | re.S)
        self.assertIsNotNone(module, "Regenerate shell.login before running its integration test")
        fixture_lib = self.root / "lib"
        fixture_lib.mkdir()
        (fixture_lib / "user.sh").write_text(self.redirect_paths(SOURCE.read_text()))
        body = ('source ' + shlex.quote(str(ROOT / "scripts/lib/install_helpers.sh")) + '\n'
                'log_step() { :; }\n'
                'acfs_require_contract() { return 0; }\n'
                'acfs_generated_ensure_selection() { return 0; }\n'
                'should_run_module() { [[ "$1" == shell.login ]]; }\n'
                + module[0] + '\nacfs_generated_install_shell_login\n')
        return body, fixture_lib

    def test_generated_login_module_retains_root_authority_for_safe_mode_target(self):
        self.prepare_root_install_for_nonroot_target()
        body, fixture_lib = self.generated_login_module_body()
        self.invoke(body, env={"TEST_CALLER": "root", "TEST_SUDO": "deny",
                               "ACFS_LIB_DIR": str(fixture_lib), "DRY_RUN": "false", "MODE": "safe"})
        self.assertEqual(self.current_shell(), str(self.zsh))
        self.assertEqual((self.home / ".shell.pre-acfs").stat().st_uid, self.uid)
        records = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual([item["euid"] for item in records if item["tool"] == "chsh"], [0])
        self.assertEqual(self.calls("sudo"), [])

    def test_generated_login_module_propagates_failure_despite_stale_zsh_environment(self):
        self.prepare_root_install_for_nonroot_target()
        body, fixture_lib = self.generated_login_module_body()
        self.invoke(body, code=1, env={"TEST_CALLER": "root", "TEST_CHSH": "noop",
                                      "ACFS_LIB_DIR": str(fixture_lib), "SHELL": str(self.zsh)})
        self.assertEqual(self.current_shell(), str(self.original))
        self.assertEqual(self.calls(), [["-s", str(self.zsh), "tester"]])

    def test_generated_external_account_requires_provider_shell_change(self):
        self.prepare_root_install_for_nonroot_target()
        (self.root / "nss-passwd").write_text(self.passwd.read_text())
        self.passwd.write_text("other:x:999:999::/other:/bin/bash\n")
        body, fixture_lib = self.generated_login_module_body()
        result = self.invoke(body, code=1,
                             env={"TEST_CALLER": "root", "TEST_SUDO": "deny", "ACFS_LIB_DIR": str(fixture_lib)})
        self.assertEqual(self.calls(), [])
        self.assertFalse((self.home / ".bashrc").exists())
        self.assertIn("identity provider", result.stderr.lower())

    def make_nonroot_fixture(self):
        if os.geteuid() == 0:
            self.uid = 65534
            self.account(uid=self.uid)
            for directory, _, files in os.walk(self.root):
                os.chown(directory, self.uid, self.uid)
                for name in files:
                    path = Path(directory) / name
                    if not path.is_symlink():
                        os.chown(path, self.uid, self.uid)
            return self.uid
        return None

    def test_nonroot_without_passwordless_sudo_changes_only_own_account(self):
        uid = self.make_nonroot_fixture()
        self.invoke(uid=uid, terminal=True, env={"TEST_SUDO": "deny"})
        self.assertEqual(self.current_shell(), str(self.zsh))
        self.assertEqual(len(self.calls()), 1)
        self.assertEqual(self.calls()[0][:2], ["-s", str(self.zsh)])

    def test_noninteractive_nonroot_without_sudo_refuses_without_prompting(self):
        uid = self.make_nonroot_fixture()
        self.invoke(uid=uid, code=1, env={"TEST_SUDO": "deny"})
        self.assertEqual(self.current_shell(), str(self.original))
        self.assertEqual(self.calls(), [])

    def test_nonroot_passwordless_sudo_path_is_noninteractive(self):
        uid = self.make_nonroot_fixture()
        self.invoke(uid=uid)
        self.assertEqual(self.current_shell(), str(self.zsh))
        self.assertEqual(self.calls(), [["-s", str(self.zsh), "tester"]])
        self.assertIn(["-n", str(self.bin / "chsh"), "-s", str(self.zsh), "tester"], self.calls("sudo"))
        for args in self.calls("sudo"):
            self.assertIn("-n", args)

    def test_nonroot_sudo_probe_success_does_not_hide_failed_change(self):
        uid = self.make_nonroot_fixture()
        self.invoke(uid=uid, code=1, env={"TEST_CHSH": "fail"})
        self.assertEqual(self.current_shell(), str(self.original))
        self.assertEqual(self.calls(), [["-s", str(self.zsh), "tester"]])
        self.assertIn(["-n", str(self.bin / "chsh"), "-s", str(self.zsh), "tester"], self.calls("sudo"))

    def test_nonroot_cannot_change_another_account_without_sudo(self):
        uid = self.make_nonroot_fixture()
        self.invoke(uid=uid, code=1, env={"TEST_SUDO": "deny", "TEST_CALLER": "other"})
        self.assertEqual(self.calls(), [])
        self.assertEqual(self.current_shell(), str(self.original))

    def test_unreadable_shells_is_rejected_for_nonroot(self):
        uid = self.make_nonroot_fixture()
        self.shells.chmod(0o000)
        self.invoke(uid=uid, code=1)
        self.assertEqual(self.calls(), [])

    def test_nonroot_unwritable_home_refuses_before_changing_account(self):
        uid = self.make_nonroot_fixture()
        self.home.chmod(0o555)
        self.invoke(uid=uid, code=1)
        self.assertEqual(self.current_shell(), str(self.original))
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
