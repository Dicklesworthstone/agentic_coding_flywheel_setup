#!/usr/bin/env python3
"""Offline integration regressions for atomic runtime deployment (issue #488).

Run: python3 -B -m unittest discover -s tests/unit -p test_update_deployment.py -v
The real runtime, early security, and managed-shell deployment paths run against
disposable source/runtime trees. No updater main(), package manager, network
request, or service is invoked.
"""
import contextlib
import os
from pathlib import Path
import select
import signal
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
COMMON = r'''
source "$REPO_ROOT/scripts/lib/update.sh"
ACFS_REPO_ROOT="$TEST_SOURCE"
UPDATE_LOG_FILE="$TEST_ROOT/update.log"
DRY_RUN="${TEST_DRY_RUN:-false}"
update_runtime_acfs_home() { printf '%s\n' "$TEST_DEPLOYED"; }
update_runtime_shell_home() { printf '%s\n' "$TEST_ROOT"; }
'''
SYNC = r'''
# Calling through a conditional must not hide copy/chmod/rename errors merely
# because Bash suppresses errexit throughout functions in this context.
if sync_acfs_deployed "${TEST_SOURCE_REF:-}"; then
    exit 0
else
    exit "$?"
fi
'''
PHASE_SETUP = r'''
UPDATE_SELF=true
UPDATE_SHELL=true
ACFS_SELF_UPDATE_DONE=false
BOOTSTRAP_SELF_UPDATE=false
QUIET=true
is_expected_acfs_origin_url() { return 0; }
update_runtime_shell_home() { printf '%s\n' "$TEST_ROOT"; }
# Keep the real deployment functions; isolate unrelated tool and profile work.
update_omz() { :; }
update_p10k() { :; }
update_zsh_plugins() { :; }
update_atuin() { :; }
update_zoxide() { :; }
sync_acfs_profile_paths() { :; }
sync_acfs_zprofile_paths() { :; }
sync_acfs_zsh_loader() { :; }
cleanup_unmanaged_atuin_init() { :; }
sync_acfs_global_command_links() { :; }
# Redirect only the global wrapper's destination, retaining its real source
# selection and publication behavior without touching /usr/local/bin.
_test_wrapper_definition="$(declare -f sync_acfs_global_wrapper)"
eval "${_test_wrapper_definition/sync_acfs_global_wrapper/_test_sync_global_wrapper}"
unset _test_wrapper_definition
sync_acfs_global_wrapper() {
    _test_sync_global_wrapper "${1:-}" "$TEST_ROOT/global-acfs"
}
'''


class AtomicDeploymentTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="acfs-deploy-test-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.repo = self.base / "source"
        self.acfs = self.base / ".acfs"
        self.stage = self.base / "temporary"
        for path in (self.repo, self.acfs, self.stage):
            path.mkdir()
        self.log = self.base / "update.log"
        self.env = {
            "PATH": "/usr/bin:/bin", "HOME": str(self.base),
            "TARGET_HOME": str(self.base), "TMPDIR": str(self.stage),
            "REPO_ROOT": str(ROOT), "TEST_ROOT": str(self.base),
            "TEST_SOURCE": str(self.repo), "TEST_DEPLOYED": str(self.acfs),
            "NO_COLOR": "1", "ACFS_INTERACTIVE": "false",
        }
        self.processes = []
        self.addCleanup(self.stop_processes)

    def stop_processes(self):
        for process in self.processes:
            if process.poll() is None:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGKILL)
            process.communicate(timeout=5)

    def write(self, root, relative, content, mode=0o644):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        path.chmod(mode)
        return path

    def commit_source(self):
        for args in (("init", "--quiet", "--initial-branch=main"), ("add", "."),
                     ("-c", "user.name=ACFS Test", "-c", "user.email=acfs-test@example.invalid",
                      "commit", "--quiet", "-m", "fixture")):
            subprocess.run(["git", "-C", str(self.repo), *args], env=self.env, check=True,
                           capture_output=True, timeout=5)

    def git(self, repo, *args):
        result = subprocess.run(["git", "-C", str(repo), *args], env=self.env, check=True,
                                capture_output=True, timeout=5)
        return result.stdout.decode().strip()

    def commit_tree(self, repo, message):
        self.git(repo, "add", ".")
        self.git(repo, "-c", "user.name=ACFS Test", "-c",
                 "user.email=acfs-test@example.invalid", "commit", "--quiet", "-m", message)

    def phase_tree(self, name):
        root = self.base / name
        source = root / "source"
        runtime = root / ".acfs"
        source.mkdir(parents=True)
        runtime.mkdir()
        env = {"HOME": str(root), "TARGET_HOME": str(root), "TEST_ROOT": str(root),
               "TEST_SOURCE": str(source), "TEST_DEPLOYED": str(runtime)}
        return root, source, runtime, env

    def start(self, command, **env):
        process = subprocess.Popen(command, env=self.env | env, stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   start_new_session=True)
        self.processes.append(process)
        return process

    def line(self, process):
        ready, _, _ = select.select([process.stdout], [], [], 5)
        self.assertTrue(ready, "fixture did not reach its synchronization point")
        return process.stdout.readline().decode().strip()

    def shell(self, body, *, success=True, **env):
        process = self.start(["/bin/bash", "--noprofile", "--norc", "-c",
                              COMMON + body], **env)
        stdout, stderr = process.communicate(timeout=15)
        output = (stdout + stderr).decode()
        if success:
            self.assertEqual(process.returncode, 0, output)
        else:
            self.assertNotEqual(process.returncode, 0, output)
        return output

    def sync(self, setup="", *, success=True, **env):
        return self.shell(setup + SYNC, success=success, **env)

    def invoke(self, function, setup="", *, success=True, **env):
        return self.shell(setup + f'\nif {function}; then exit 0; else exit "$?"; fi\n',
                          success=success, **env)

    def assert_runtime_files(self, *expected):
        self.assertEqual(sorted(str(p.relative_to(self.acfs)) for p in self.acfs.rglob("*")
                                if not p.is_dir()), sorted(expected))
        self.assertEqual(list(self.stage.iterdir()), [], "source-ref temporary file leaked")

    def test_running_script_finishes_old_version_and_next_launch_gets_new_version(self):
        # Each line is a separate command/comment, not one function or compound
        # command Bash could parse in full before waiting. Padding keeps the final
        # command beyond read-ahead. Readiness and stdin provide the ordering;
        # there are no timing sleeps or probabilistic copy races in this test.
        old = ("#!/bin/bash\nset -euo pipefail\nprintf 'old-ready\\n'\n"
               "IFS= read -r release\n" + "# unread script body\n" * 16384
               + "printf 'old-finished\\n'\n")
        new = "#!/bin/bash\nprintf 'new-version\\n'\n"
        self.write(self.repo, "scripts/lib/nightly_update.sh", new)
        deployed = self.write(self.acfs, "scripts/nightly-update.sh", old, 0o755)
        original_inode = deployed.stat().st_ino
        running = self.start([str(deployed)])
        self.assertEqual(self.line(running), "old-ready")

        self.sync()
        self.assertIsNone(running.poll(), "original script must still be paused")
        subsequent = subprocess.run([str(deployed)], env=self.env, capture_output=True,
                                    text=True, timeout=5)
        self.assertEqual(subsequent.returncode, 0, subsequent.stderr)
        self.assertEqual(subsequent.stdout, "new-version\n")
        stdout, stderr = running.communicate(input=b"resume\n", timeout=5)
        self.assertEqual(running.returncode, 0, stderr.decode())
        self.assertEqual(stdout.decode(), "old-finished\n",
                         "deployment truncated the inode Bash was still reading")
        self.assertNotEqual(deployed.stat().st_ino, original_inode)
        self.assertEqual(deployed.read_text(), new)
        self.assert_runtime_files("scripts/lib/nightly_update.sh", "scripts/nightly-update.sh")

    def test_self_update_and_shell_preserve_running_runtime_readers(self):
        old = ("#!/bin/bash\nset -euo pipefail\nprintf 'old-ready\\n'\n"
               "IFS= read -r release\n" + "# unread script body\n" * 16384
               + "printf 'old-finished\\n'\n")
        new = "#!/bin/bash\nprintf 'new-version\\n'\n"
        cases = (("security", "scripts/lib/security.sh", "scripts/lib/security.sh", "update_acfs_self"),
                 ("zsh", "acfs/zsh/acfs.zshrc", "zsh/acfs.zshrc", "update_shell"))
        for name, source_rel, deployed_rel, phase in cases:
            with self.subTest(phase=phase):
                _, source, runtime, env = self.phase_tree(name)
                self.write(source, source_rel, new, 0o755)
                self.git(source, "init", "--quiet", "--initial-branch=main")
                self.commit_tree(source, "current source")
                self.git(source, "remote", "add", "origin", str(source))
                deployed = self.write(runtime, deployed_rel, old, 0o755)
                original_inode = deployed.stat().st_ino
                running = self.start(["/bin/bash", str(deployed)], **env)
                self.assertEqual(self.line(running), "old-ready")
                process = self.start(["/bin/bash", "-c", COMMON + PHASE_SETUP + phase], **env)
                stdout, stderr = process.communicate(timeout=15)
                self.assertEqual(process.returncode, 0, (stdout + stderr).decode())
                self.assertIsNone(running.poll(), "reader must remain paused during deployment")
                subsequent = subprocess.run(["/bin/bash", str(deployed)], env=self.env | env,
                                            capture_output=True, text=True, timeout=5)
                self.assertEqual(subsequent.returncode, 0, subsequent.stderr)
                self.assertEqual(subsequent.stdout, "new-version\n")
                stdout, stderr = running.communicate(input=b"resume\n", timeout=5)
                self.assertEqual(running.returncode, 0, stderr.decode())
                self.assertEqual(stdout.decode(), "old-finished\n",
                                 f"{phase} truncated the running {name} inode")
                self.assertNotEqual(deployed.stat().st_ino, original_inode)
                self.assertEqual(list(runtime.rglob(".acfs-deploy.*")), [])
                self.assertEqual(list(self.stage.iterdir()), [])

    def test_phase_failure_and_dry_run_preserve_existing_runtime(self):
        cases = (("security", "scripts/lib/security.sh", "scripts/lib/security.sh", "update_acfs_self"),
                 ("zsh", "acfs/zsh/acfs.zshrc", "zsh/acfs.zshrc", "update_shell"))
        for name, source_rel, deployed_rel, phase in cases:
            for dry_run in (False, True):
                with self.subTest(phase=phase, dry_run=dry_run):
                    root, source, runtime, env = self.phase_tree(f"{name}-{dry_run}")
                    self.write(source, source_rel, "new complete script\n", 0o755)
                    self.git(source, "init", "--quiet", "--initial-branch=main")
                    self.commit_tree(source, "current source")
                    self.git(source, "remote", "add", "origin", str(source))
                    deployed = self.write(runtime, deployed_rel, "old complete script\n", 0o755)
                    original = deployed.stat()
                    setup = '' if dry_run else 'cp() { printf "partial" > "${@: -1}"; return 73; }\n'
                    body = COMMON + PHASE_SETUP + setup + f"if {phase}; then exit 0; else exit \"$?\"; fi\n"
                    process = self.start(["/bin/bash", "-c", body], **env,
                                         TEST_DRY_RUN=str(dry_run).lower())
                    stdout, stderr = process.communicate(timeout=15)
                    if dry_run:
                        self.assertEqual(process.returncode, 0, (stdout + stderr).decode())
                    else:
                        self.assertNotEqual(process.returncode, 0, (stdout + stderr).decode())
                    self.assertEqual(deployed.read_text(), "old complete script\n")
                    after = deployed.stat()
                    self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns),
                                     (original.st_ino, original.st_mode, original.st_mtime_ns))
                    self.assertEqual(list(runtime.rglob(".acfs-deploy.*")), [])
                    self.assertEqual(list(self.stage.iterdir()), [])
                    log = root / "update.log"
                    if not dry_run:
                        self.assertNotIn("Synced ", log.read_text() if log.exists() else "")

    def test_fetched_runtime_remains_pinned_through_shell_update(self):
        files = (("stack", "scripts/lib/stack.sh", "scripts/lib/stack.sh"),
                 ("security", "scripts/lib/security.sh", "scripts/lib/security.sh"),
                 ("zsh", "acfs/zsh/acfs.zshrc", "zsh/acfs.zshrc"),
                 ("global", "scripts/acfs-global", None))
        for scenario in ("dirty", "wrong-branch", "divergent"):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory(
                    prefix=f"{scenario}-", dir=self.base) as phase_root:
                root, source, runtime, env = self.phase_tree(phase_root)
                for name, relative, _ in files:
                    self.write(source, relative, f"#!/bin/bash\nprintf 'base-{name}\\n'\n", 0o755)
                self.write(source, "VERSION", "fixture\n")
                self.git(source, "init", "--quiet", "--initial-branch=main")
                self.commit_tree(source, "base")
                remote = root / "remote"
                self.git(root, "clone", "--quiet", str(source), str(remote))
                for name, relative, _ in files:
                    self.write(remote, relative, f"#!/bin/bash\nprintf 'fresh-{name}\\n'\n", 0o755)
                self.commit_tree(remote, "fresh runtime")
                self.git(remote, "checkout", "--quiet", "-b", "future")
                for name, relative, _ in files:
                    self.write(remote, relative, f"#!/bin/bash\nprintf 'future-{name}\\n'\n", 0o755)
                self.commit_tree(remote, "later runtime")
                future = self.git(remote, "rev-parse", "HEAD")
                self.git(remote, "checkout", "--quiet", "main")
                self.git(source, "remote", "add", "origin", str(remote))
                if scenario == "dirty":
                    self.write(source, "VERSION", "local-dirty-version\n")
                elif scenario == "wrong-branch":
                    self.git(source, "branch", "-m", "local-work")
                else:
                    self.write(source, "local.txt", "local committed work\n")
                    self.commit_tree(source, "local divergence")
                before = {str(p.relative_to(source)): (p.read_bytes(), p.stat().st_mode)
                          for p in source.rglob("*") if p.is_file() and ".git" not in p.parts}
                before_head = self.git(source, "rev-parse", "HEAD")
                before_status = self.git(source, "status", "--porcelain")
                body = r'''
report_runtime() {
    for pair in stack:scripts/lib/stack.sh security:scripts/lib/security.sh zsh:zsh/acfs.zshrc; do
        printf '%s-%s=%s\n' "$1" "${pair%%:*}" "$(bash "$TEST_DEPLOYED/${pair#*:}")"
    done
    printf '%s-global=%s\n' "$1" "$(bash "$TEST_ROOT/global-acfs")"
}
update_acfs_self
report_runtime after-self
update_shell
report_runtime after-shell
# Another fetch may move the symbolic tracking ref while this invocation runs.
# Its runtime source must remain the exact revision selected by self-update.
git -C "$TEST_SOURCE" fetch --quiet origin future
git -C "$TEST_SOURCE" update-ref refs/remotes/origin/main "$TEST_FUTURE_REF"
update_shell
report_runtime after-ref-moved
'''
                process = self.start(["/bin/bash", "-c", COMMON + PHASE_SETUP + body],
                                     **env, TEST_FUTURE_REF=future)
                stdout, stderr = process.communicate(timeout=25)
                output = (stdout + stderr).decode()
                log = root / "update.log"
                self.assertEqual(process.returncode, 0,
                                 output + (log.read_text() if log.exists() else ""))
                for phase in ("after-self", "after-shell", "after-ref-moved"):
                    for name, _, _ in files:
                        self.assertIn(f"{phase}-{name}=fresh-{name}\n", output)
                after = {str(p.relative_to(source)): (p.read_bytes(), p.stat().st_mode)
                         for p in source.rglob("*") if p.is_file() and ".git" not in p.parts}
                self.assertEqual(after, before)
                self.assertEqual(self.git(source, "rev-parse", "HEAD"), before_head)
                self.assertEqual(self.git(source, "status", "--porcelain"), before_status)
                self.assertEqual(list(runtime.rglob(".acfs-deploy.*")), [])
                self.assertEqual(list(self.stage.iterdir()), [])

    def test_modes_are_ready_at_publication_and_unchanged_files_are_idempotent(self):
        self.write(self.repo, "scripts/lib/stack.sh", "new script\n", 0o644)
        self.write(self.repo, "acfs/tmux/tmux.conf", "new config\n", 0o640)
        self.sync(r'''
mv() {
    local -a args=("$@")
    local staged="${args[${#args[@]}-2]}" destination="${args[${#args[@]}-1]}"
    case "$destination" in
        */stack.sh) [[ "$(stat -c '%a' "$staged")" == 755 ]] || return 91 ;;
        */tmux.conf) [[ "$(stat -c '%a' "$staged")" == 640 ]] || return 92 ;;
    esac
    [[ "$(dirname "$staged")" == "$(dirname "$destination")" ]] || return 93
    printf '%s\n' "$destination" >> "$TEST_ROOT/published"
    command mv "$@"
}
''')
        script = self.acfs / "scripts/lib/stack.sh"
        config = self.acfs / "tmux/tmux.conf"
        self.assertEqual(sorted((self.base / "published").read_text().splitlines()),
                         sorted((str(script), str(config))))
        self.assertEqual(script.stat().st_mode & 0o777, 0o755)
        self.assertEqual(config.stat().st_mode & 0o777, 0o640)
        before = [(p.stat().st_ino, p.stat().st_mtime_ns) for p in (script, config)]
        previous_log = self.log.read_text()
        self.sync()
        self.assertEqual([(p.stat().st_ino, p.stat().st_mtime_ns) for p in (script, config)], before)
        self.assertEqual(self.log.read_text(), previous_log)
        self.assert_runtime_files("scripts/lib/stack.sh", "tmux/tmux.conf")

    def test_identical_script_with_missing_execute_bit_is_repaired(self):
        content = "#!/bin/bash\nprintf 'repaired\\n'\n"
        self.write(self.repo, "scripts/lib/stack.sh", content)
        deployed = self.write(self.acfs, "scripts/lib/stack.sh", content)
        self.sync()
        self.assertEqual(deployed.read_text(), content)
        self.assertEqual(deployed.stat().st_mode & 0o777, 0o755)
        self.assert_runtime_files("scripts/lib/stack.sh")

    def test_dry_run_reports_changes_without_touching_runtime(self):
        self.write(self.repo, "scripts/lib/stack.sh", "new\n")
        self.write(self.repo, "acfs/tmux/tmux.conf", "new config\n")
        deployed = self.write(self.acfs, "scripts/lib/stack.sh", "old\n", 0o755)
        before = deployed.stat()
        self.sync(TEST_DRY_RUN="true")
        self.assertEqual(deployed.read_text(), "old\n")
        after = deployed.stat()
        self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns),
                         (before.st_ino, before.st_mode, before.st_mtime_ns))
        self.assertIn("Would sync scripts/lib/stack.sh ->", self.log.read_text())
        self.assertIn("Would sync acfs/tmux/tmux.conf ->", self.log.read_text())
        self.assert_runtime_files("scripts/lib/stack.sh")

    def test_git_ref_uses_committed_content_and_modes_instead_of_dirty_checkout(self):
        executable = self.write(self.repo, "scripts/lib/agy_locked.py", "committed executable\n", 0o755)
        config = self.write(self.repo, "acfs/tmux/tmux.conf", "committed config\n", 0o644)
        self.commit_source()
        executable.write_text("dirty executable\n")
        executable.chmod(0o644)
        config.write_text("dirty config\n")
        config.chmod(0o600)
        self.sync(TEST_SOURCE_REF="HEAD")
        for relative in ("scripts/lib/agy_locked.py", "bin/agy-locked"):
            deployed = self.acfs / relative
            self.assertEqual(deployed.read_text(), "committed executable\n")
            self.assertEqual(deployed.stat().st_mode & 0o777, 0o755)
        deployed = self.acfs / "tmux/tmux.conf"
        self.assertEqual(deployed.read_text(), "committed config\n")
        self.assertEqual(deployed.stat().st_mode & 0o777, 0o644)
        self.assertEqual(executable.read_text(), "dirty executable\n")
        self.assertEqual(config.read_text(), "dirty config\n")
        self.assertIn("Synced HEAD:scripts/lib/agy_locked.py ->", self.log.read_text())
        self.assert_runtime_files("scripts/lib/agy_locked.py", "bin/agy-locked", "tmux/tmux.conf")

    def test_prepublication_failures_preserve_previous_script_and_remove_temporaries(self):
        self.write(self.repo, "scripts/lib/stack.sh", "new complete script\n")
        deployed = self.write(self.acfs, "scripts/lib/stack.sh", "old complete script\n", 0o755)
        original = deployed.stat()
        failures = {
            "directory": "mkdir() { return 71; }\n",
            "temporary": "mktemp() { return 72; }\n",
            "partial copy": 'cp() { printf "partial" > "${@: -1}"; return 73; }\n',
            "permissions": "chmod() { return 74; }\n",
            "replacement": "mv() { return 75; }\n",
        }
        for step, setup in failures.items():
            with self.subTest(step=step):
                self.sync(setup, success=False)
                self.assertEqual(deployed.read_text(), "old complete script\n")
                self.assertEqual(deployed.stat().st_ino, original.st_ino)
                self.assertEqual(deployed.stat().st_mode, original.st_mode)
                self.assertEqual(deployed.stat().st_mtime_ns, original.st_mtime_ns)
                self.assertNotIn("Synced ", self.log.read_text() if self.log.exists() else "")
                self.assert_runtime_files("scripts/lib/stack.sh")

    def test_source_ref_failures_clean_extraction_and_staging_files(self):
        self.write(self.repo, "scripts/lib/stack.sh", "committed script\n", 0o755)
        self.commit_source()
        deployed = self.write(self.acfs, "scripts/lib/stack.sh", "old complete script\n", 0o755)
        original_inode = deployed.stat().st_ino
        failures = {
            "source temporary": "mktemp() { return 72; }\n",
            "partial copy": 'cp() { printf "partial" > "${@: -1}"; return 73; }\n',
            "permissions": "chmod() { return 74; }\n",
            "replacement": "mv() { return 75; }\n",
        }
        for step, setup in failures.items():
            with self.subTest(step=step):
                self.sync(setup, success=False, TEST_SOURCE_REF="HEAD")
                self.assertEqual(deployed.read_text(), "old complete script\n")
                self.assertEqual(deployed.stat().st_ino, original_inode)
                self.assert_runtime_files("scripts/lib/stack.sh")

    def test_failed_first_copy_does_not_publish_a_partial_script(self):
        self.write(self.repo, "scripts/lib/stack.sh", "new complete script\n")
        self.sync('cp() { printf "partial" > "${@: -1}"; return 73; }\n', success=False)
        self.assert_runtime_files()

    def test_early_deployers_preserve_running_script_inodes(self):
        old = ("#!/bin/bash\nset -euo pipefail\nprintf 'old-ready\\n'\n"
               "IFS= read -r release\n" + "# unread script body\n" * 16384
               + "printf 'old-finished\\n'\n")
        new = "#!/bin/bash\nprintf 'new-version\\n'\n"
        cases = (
            ("update_refresh_installed_security", "scripts/lib/security.sh", "scripts/lib/security.sh"),
            ("sync_acfs_zshrc", "acfs/zsh/acfs.zshrc", "zsh/acfs.zshrc"),
        )
        deployed_paths = []
        for helper, source_relative, deployed_relative in cases:
            with self.subTest(helper=helper):
                self.write(self.repo, source_relative, new)
                deployed = self.write(self.acfs, deployed_relative, old, 0o755)
                deployed_paths.append(deployed_relative)
                original_inode = deployed.stat().st_ino
                running = self.start([str(deployed)])
                self.assertEqual(self.line(running), "old-ready")
                self.invoke(helper)
                self.assertIsNone(running.poll(), "original script must still be paused")
                subsequent = subprocess.run([str(deployed)], env=self.env, capture_output=True,
                                            text=True, timeout=5)
                self.assertEqual(subsequent.returncode, 0, subsequent.stderr)
                self.assertEqual(subsequent.stdout, "new-version\n")
                stdout, stderr = running.communicate(input=b"resume\n", timeout=5)
                self.assertEqual(running.returncode, 0, stderr.decode())
                self.assertEqual(stdout.decode(), "old-finished\n",
                                 f"{helper} truncated the inode Bash was still reading")
                self.assertNotEqual(deployed.stat().st_ino, original_inode)
                self.assertEqual(deployed.read_text(), new)
                self.assert_runtime_files(*deployed_paths)

    def test_early_deployers_preserve_existing_modes_and_skip_identical_content(self):
        cases = (
            ("update_refresh_installed_security", "scripts/lib/security.sh", "scripts/lib/security.sh"),
            ("sync_acfs_zshrc", "acfs/zsh/acfs.zshrc", "zsh/acfs.zshrc"),
        )
        for helper, source_relative, deployed_relative in cases:
            with self.subTest(helper=helper):
                self.write(self.repo, source_relative, "new content\n", 0o644)
                deployed = self.write(self.acfs, deployed_relative, "old content\n", 0o750)
                self.invoke(helper, "umask 0077\n")
                self.assertEqual(deployed.read_text(), "new content\n")
                self.assertEqual(deployed.stat().st_mode & 0o777, 0o750)
                before = deployed.stat()
                previous_log = self.log.read_text()
                self.invoke(helper, "mv() { return 91; }\n")
                after = deployed.stat()
                self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns),
                                 (before.st_ino, before.st_mode, before.st_mtime_ns))
                self.assertEqual(self.log.read_text(), previous_log)
        self.assert_runtime_files("scripts/lib/security.sh", "zsh/acfs.zshrc")

    def test_new_zshrc_uses_source_permissions_filtered_by_umask(self):
        self.write(self.repo, "acfs/zsh/acfs.zshrc", "new shell configuration\n", 0o777)
        self.invoke("sync_acfs_zshrc", "umask 0027\n")
        deployed = self.acfs / "zsh/acfs.zshrc"
        self.assertEqual(deployed.read_text(), "new shell configuration\n")
        self.assertEqual(deployed.stat().st_mode & 0o777, 0o750)
        self.assert_runtime_files("zsh/acfs.zshrc")

    def test_early_deployers_dry_run_does_not_publish(self):
        cases = (
            ("update_refresh_installed_security", "scripts/lib/security.sh", "scripts/lib/security.sh"),
            ("sync_acfs_zshrc", "acfs/zsh/acfs.zshrc", "zsh/acfs.zshrc"),
        )
        for helper, source_relative, deployed_relative in cases:
            with self.subTest(helper=helper):
                self.write(self.repo, source_relative, "new content\n")
                deployed = self.write(self.acfs, deployed_relative, "old content\n", 0o750)
                before = deployed.stat()
                output = self.invoke(helper, TEST_DRY_RUN="true")
                self.assertEqual(deployed.read_text(), "old content\n")
                after = deployed.stat()
                self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns),
                                 (before.st_ino, before.st_mode, before.st_mtime_ns))
                log = self.log.read_text() if self.log.exists() else ""
                self.assertRegex(output + log, r"(?i)(dry-run|would)")
        self.assert_runtime_files("scripts/lib/security.sh", "zsh/acfs.zshrc")

    def test_early_deployers_fail_before_publication_and_do_not_log_success(self):
        cases = (
            ("update_refresh_installed_security", "scripts/lib/security.sh", "scripts/lib/security.sh"),
            ("sync_acfs_zshrc", "acfs/zsh/acfs.zshrc", "zsh/acfs.zshrc"),
        )
        failures = {
            "temporary": "mktemp() { return 72; }\n",
            "partial copy": 'cp() { printf "partial" > "${@: -1}"; return 73; }\n',
            "permissions": "chmod() { return 74; }\n",
            "replacement": "mv() { return 75; }\n",
        }
        deployed_paths = []
        for helper, source_relative, deployed_relative in cases:
            self.write(self.repo, source_relative, "new complete script\n")
            deployed_paths.append(deployed_relative)
            for step, setup in failures.items():
                with self.subTest(helper=helper, step=step):
                    deployed = self.write(self.acfs, deployed_relative, "old complete script\n", 0o750)
                    before = deployed.stat()
                    output = self.invoke(helper, setup, success=False)
                    self.assertEqual(deployed.read_text(), "old complete script\n")
                    after = deployed.stat()
                    self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns),
                                     (before.st_ino, before.st_mode, before.st_mtime_ns))
                    log = self.log.read_text() if self.log.exists() else ""
                    self.assertNotIn("Refreshed installed security.sh", output + log)
                    self.assertNotIn("Deployed ", output + log)
                    self.assert_runtime_files(*deployed_paths)

    def test_early_security_refresh_preserves_missing_and_same_file_skips(self):
        self.write(self.repo, "scripts/lib/security.sh", "source security\n")
        self.invoke("update_refresh_installed_security", "cp() { return 91; }\n")
        self.assert_runtime_files()
        deployed = self.write(self.acfs, "scripts/lib/security.sh", "shared source\n", 0o750)
        before = deployed.stat()
        self.invoke("update_refresh_installed_security", 'ACFS_REPO_ROOT="$TEST_DEPLOYED"\n')
        after = deployed.stat()
        self.assertEqual(deployed.read_text(), "shared source\n")
        self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns),
                         (before.st_ino, before.st_mode, before.st_mtime_ns))
        self.assert_runtime_files("scripts/lib/security.sh")

    def test_shell_update_stops_after_managed_zshrc_failure(self):
        body = r'''
UPDATE_SHELL=true
update_omz() { :; }
update_p10k() { :; }
update_zsh_plugins() { :; }
update_atuin() { :; }
update_zoxide() { :; }
sync_acfs_profile_paths() { :; }
sync_acfs_zprofile_paths() { :; }
sync_acfs_zsh_loader() { :; }
sync_acfs_zshrc() { return "$TEST_FAILURE"; }
cleanup_unmanaged_atuin_init() { printf 'unexpected cleanup\n'; }
sync_acfs_deployed() { printf 'unexpected deployment\n'; }
sync_acfs_global_wrapper() { printf 'unexpected wrapper\n'; }
sync_acfs_global_command_links() { printf 'unexpected links\n'; }
if update_shell; then exit 0; else exit "$?"; fi
'''
        for failure in (73, 143):
            with self.subTest(status=failure):
                process = self.start(["/bin/bash", "-c", COMMON + body], TEST_FAILURE=str(failure))
                stdout, stderr = process.communicate(timeout=15)
                self.assertEqual(process.returncode, failure, (stdout + stderr).decode())
                self.assertNotIn(b"unexpected", stdout + stderr)

    def test_self_update_stops_when_early_security_refresh_fails(self):
        self.write(self.repo, "VERSION", "fixture one\n")
        self.commit_source()
        checkout = self.base / "checkout"
        subprocess.run(["git", "clone", "--quiet", str(self.repo), str(checkout)], env=self.env,
                       check=True, capture_output=True, timeout=5)
        body = r'''
UPDATE_SELF=true
BOOTSTRAP_SELF_UPDATE=false
ACFS_SELF_UPDATE_DONE=false
SCRIPT_DIR="$TEST_ROOT/no-updater"
is_expected_acfs_origin_url() { return 0; }
update_refresh_installed_security() { printf 'refresh attempted\n'; return 73; }
sync_acfs_deployed() { printf 'unexpected deployment\n'; }
sync_acfs_global_wrapper() { printf 'unexpected wrapper\n'; }
sync_acfs_global_command_links() { printf 'unexpected links\n'; }
if update_acfs_self; then exit 0; else exit "$?"; fi
'''
        for state in ("current", "fast-forward"):
            with self.subTest(checkout=state):
                if state == "fast-forward":
                    self.write(self.repo, "VERSION", "fixture two\n")
                    self.commit_source()
                process = self.start(["/bin/bash", "-c", COMMON + body], TEST_SOURCE=str(checkout))
                stdout, stderr = process.communicate(timeout=15)
                self.assertEqual(process.returncode, 73, (stdout + stderr).decode())
                self.assertIn(b"refresh attempted", stdout)
                self.assertNotIn(b"unexpected", stdout + stderr)

    def test_source_ref_extraction_failure_is_not_an_optional_skip(self):
        self.write(self.repo, "scripts/lib/stack.sh", "committed script\n", 0o755)
        self.commit_source()
        deployed = self.write(self.acfs, "scripts/lib/stack.sh", "old script\n", 0o755)
        original = deployed.stat()
        self.sync(r'''
git() {
    if [[ "$3" == show && "$4" == HEAD:scripts/lib/stack.sh ]]; then
        printf 'partial source\n'
        return 73
    fi
    command git "$@"
}
''', success=False, TEST_SOURCE_REF="HEAD")
        self.assertEqual(deployed.read_text(), "old script\n")
        self.assertEqual(deployed.stat().st_ino, original.st_ino)
        self.assertEqual(deployed.stat().st_mode, original.st_mode)
        self.assertNotIn("Synced ", self.log.read_text() if self.log.exists() else "")
        self.assert_runtime_files("scripts/lib/stack.sh")

    def test_executable_override_does_not_hide_source_mode_failure(self):
        self.write(self.repo, "scripts/lib/stack.sh", "committed script\n", 0o755)
        self.commit_source()
        deployed = self.write(self.acfs, "scripts/lib/stack.sh", "old script\n", 0o755)
        original_inode = deployed.stat().st_ino
        self.sync(r'''
git() {
    if [[ "$3" == ls-tree && "${@: -1}" == scripts/lib/stack.sh ]]; then return 77; fi
    command git "$@"
}
''', success=False, TEST_SOURCE_REF="HEAD")
        self.assertEqual(deployed.read_text(), "old script\n")
        self.assertEqual(deployed.stat().st_ino, original_inode)
        self.assertNotIn("Synced ", self.log.read_text() if self.log.exists() else "")
        self.assert_runtime_files("scripts/lib/stack.sh")

    def test_fetched_refresh_propagates_failure_without_later_actions(self):
        self.write(self.repo, "VERSION", "fixture\n")
        self.commit_source()
        subprocess.run(["git", "-C", str(self.repo), "update-ref", "refs/remotes/origin/main", "HEAD"],
                       env=self.env, check=True, capture_output=True, timeout=5)
        body = r'''
sync_acfs_deployed() { return "$TEST_FAILURE"; }
sync_acfs_global_wrapper() { printf 'unexpected wrapper\n'; }
sync_acfs_global_command_links() { printf 'unexpected links\n'; }
log_item() { if [[ "$1" == ok ]]; then printf 'unexpected success log\n'; fi; }
if _acfs_refresh_security_from_fetched_remote; then exit 0; else exit "$?"; fi
'''
        for failure in (73, 143):
            with self.subTest(status=failure):
                process = self.start(["/bin/bash", "-c", COMMON + body], TEST_FAILURE=str(failure))
                stdout, stderr = process.communicate(timeout=15)
                self.assertEqual(process.returncode, failure, (stdout + stderr).decode())
                self.assertEqual(stdout, b"")
                self.assertNotIn("Refreshed deployed ACFS runtime",
                                 self.log.read_text() if self.log.exists() else "")

    def test_fetched_refresh_cannot_continue_without_resolving_a_commit(self):
        self.write(self.repo, "VERSION", "fixture\n")
        self.commit_source()
        body = r'''
sync_acfs_deployed() { printf 'unexpected deployment\n'; }
sync_acfs_global_wrapper() { printf 'unexpected wrapper\n'; }
sync_acfs_global_command_links() { printf 'unexpected links\n'; }
log_item() { if [[ "$1" == ok ]]; then printf 'unexpected success log\n'; fi; }
if _acfs_refresh_security_from_fetched_remote; then exit 0; else exit "$?"; fi
'''
        output = self.shell(body, success=False)
        self.assertNotIn("unexpected", output)

    def test_runtime_source_selection_does_not_trust_inherited_environment(self):
        output = self.shell('printf "selected:%s\\n" "${_ACFS_RUNTIME_SOURCE_REF:-}"',
                            _ACFS_RUNTIME_SOURCE_REF="untrusted-inherited-ref")
        self.assertEqual(output, "selected:\n")

    def assert_dirty_fallback_stays_pinned_through_shell_update(self, checkout_is_runtime):
        source_paths = (
            "VERSION", "scripts/lib/doctor.sh", "scripts/lib/security.sh", "scripts/lib/stack.sh",
            "scripts/acfs-global", "checksums.yaml", "acfs/zsh/acfs.zshrc",
            "acfs/onboard/lessons/00_welcome.md",
        )

        def publish(version):
            for relative in source_paths:
                self.write(self.repo, relative, f"{version}: {relative}\n")
            self.commit_source()
            return subprocess.check_output(["git", "-C", str(self.repo), "rev-parse", "HEAD"],
                                           env=self.env, text=True, timeout=5).strip()

        publish("base")
        checkout = self.acfs if checkout_is_runtime else self.base / "checkout"
        subprocess.run(["git", "clone", "--quiet", str(self.repo), str(checkout)], env=self.env,
                       check=True, capture_output=True, timeout=5)
        original_head = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"],
                                                env=self.env, text=True, timeout=5).strip()
        for relative in ("scripts/lib/stack.sh", "scripts/lib/security.sh", "acfs/zsh/acfs.zshrc"):
            self.write(checkout, relative, f"operator edits: {relative}\n")
        original_files = {relative: (checkout / relative).read_bytes() for relative in source_paths}
        original_diff = subprocess.check_output(["git", "-C", str(checkout), "diff", "--binary"],
                                                env=self.env, timeout=5)
        selected_commit = publish("selected")
        deployed_sources = {
            "bin/acfs": "scripts/lib/doctor.sh",
            "zsh/acfs.zshrc": "acfs/zsh/acfs.zshrc",
            "onboard/lessons/00_welcome.md": "acfs/onboard/lessons/00_welcome.md",
        }
        if not checkout_is_runtime:
            deployed_sources.update({relative: relative for relative in
                                     ("scripts/lib/security.sh", "scripts/lib/stack.sh", "checksums.yaml")})

        body = r'''
UPDATE_SELF=true
UPDATE_SHELL=true
BOOTSTRAP_SELF_UPDATE=false
ACFS_SELF_UPDATE_DONE=false
SCRIPT_DIR="$TEST_ROOT/no-updater"
is_expected_acfs_origin_url() { return 0; }
log_section() { :; }
log_item() { :; }
update_omz() { :; }
update_p10k() { :; }
update_zsh_plugins() { :; }
update_atuin() { :; }
update_zoxide() { :; }
sync_acfs_profile_paths() { :; }
sync_acfs_zprofile_paths() { :; }
sync_acfs_zsh_loader() { :; }
cleanup_unmanaged_atuin_init() { :; }
sync_acfs_global_wrapper() { printf '%s\n' "${1:-}" >> "$TEST_ROOT/global-wrapper-refs"; }
sync_acfs_global_command_links() { :; }
update_acfs_self
printf 'fallback-complete\n'
IFS= read -r release
# A second fetch can move origin/main between updater phases. The already
# selected runtime must stay on the original immutable commit nonetheless.
git -C "$ACFS_REPO_ROOT" fetch origin main --quiet
update_shell
'''
        process = self.start(["/bin/bash", "-c", COMMON + body], TEST_SOURCE=str(checkout))
        self.assertEqual(self.line(process), "fallback-complete")
        for target, source in deployed_sources.items():
            self.assertEqual((self.acfs / target).read_text(), f"selected: {source}\n")

        later_commit = publish("later")
        self.assertNotEqual(selected_commit, later_commit)
        stdout, stderr = process.communicate(input=b"continue\n", timeout=20)
        self.assertEqual(process.returncode, 0, (stdout + stderr).decode())
        for target, source in deployed_sources.items():
            self.assertEqual((self.acfs / target).read_text(), f"selected: {source}\n",
                             f"shell update replaced selected runtime asset {target}")
        self.assertEqual((self.base / "global-wrapper-refs").read_text().splitlines(),
                         [selected_commit, selected_commit])
        self.assertEqual(subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "origin/main"],
                                                 env=self.env, text=True, timeout=5).strip(), later_commit)
        self.assertEqual(subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"],
                                                 env=self.env, text=True, timeout=5).strip(), original_head)
        self.assertEqual({relative: (checkout / relative).read_bytes() for relative in source_paths},
                         original_files)
        self.assertEqual(subprocess.check_output(["git", "-C", str(checkout), "diff", "--binary"],
                                                 env=self.env, timeout=5), original_diff)
        self.assertEqual(list(self.stage.iterdir()), [])
        self.assertEqual(list(self.acfs.rglob(".acfs-deploy.*")), [])

    def test_dirty_fallback_stays_pinned_through_shell_update(self):
        self.assert_dirty_fallback_stays_pinned_through_shell_update(checkout_is_runtime=False)

    def test_dirty_checkout_runtime_preserves_remapped_assets_and_tracked_edits(self):
        self.assert_dirty_fallback_stays_pinned_through_shell_update(checkout_is_runtime=True)

    def test_self_update_propagates_failure_in_completed_and_current_checkouts(self):
        self.write(self.repo, "VERSION", "fixture\n")
        self.commit_source()
        subprocess.run(["git", "-C", str(self.repo), "remote", "add", "origin", str(self.repo)],
                       env=self.env, check=True, capture_output=True, timeout=5)
        body = r'''
UPDATE_SELF=true
BOOTSTRAP_SELF_UPDATE=false
ACFS_SELF_UPDATE_DONE="$TEST_ALREADY_DONE"
is_expected_acfs_origin_url() { return 0; }
update_refresh_installed_security() { :; }
sync_acfs_deployed() { return "$TEST_FAILURE"; }
if update_acfs_self; then exit 0; else exit "$?"; fi
'''
        for already_done in ("true", "false"):
            for failure in (73, 143):
                with self.subTest(already_done=already_done, status=failure):
                    process = self.start(["/bin/bash", "-c", COMMON + body],
                                         TEST_ALREADY_DONE=already_done, TEST_FAILURE=str(failure))
                    stdout, stderr = process.communicate(timeout=15)
                    self.assertEqual(process.returncode, failure, (stdout + stderr).decode())

    def test_source_ref_mode_lookup_failure_does_not_publish_private_staging_mode(self):
        self.write(self.repo, "acfs/tmux/tmux.conf", "new config\n")
        deployed = self.write(self.acfs, "tmux/tmux.conf", "old config\n", 0o644)
        original = deployed.stat()
        for args in (("init", "--quiet", "--initial-branch=main"), ("add", "."),
                     ("-c", "user.name=ACFS Test", "-c", "user.email=acfs-test@example.invalid",
                      "commit", "--quiet", "-m", "fixture")):
            subprocess.run(["git", "-C", str(self.repo), *args], env=self.env, check=True,
                           capture_output=True, timeout=5)
        self.sync(r'''
git() {
    if [[ "$3" == ls-tree ]]; then return 77; fi
    command git "$@"
}
''', success=False, TEST_SOURCE_REF="HEAD")
        self.assertEqual(deployed.read_text(), "old config\n")
        self.assertEqual(deployed.stat().st_ino, original.st_ino)
        self.assertEqual(deployed.stat().st_mode, original.st_mode)
        self.assertNotIn("Synced ", self.log.read_text())
        self.assert_runtime_files("tmux/tmux.conf")

    def test_directory_target_is_rejected_without_moving_staging_file_inside(self):
        self.write(self.repo, "scripts/lib/stack.sh", "new complete script\n")
        marker = self.write(self.acfs, "scripts/lib/stack.sh/existing", "keep directory contents\n")
        self.sync(success=False)
        self.assertEqual(marker.read_text(), "keep directory contents\n")
        self.assert_runtime_files("scripts/lib/stack.sh/existing")

    def test_callers_traps_survive_success_skip_and_failure(self):
        self.write(self.repo, "scripts/lib/stack.sh", "original source\n")
        body = r'''
trap 'printf "caller-exit\n" >> "$TEST_ROOT/trap-events"' EXIT
trap 'printf "caller-hup\n" >> "$TEST_ROOT/trap-events"' HUP
trap 'printf "caller-int\n" >> "$TEST_ROOT/trap-events"' INT
trap 'printf "caller-term\n" >> "$TEST_ROOT/trap-events"' TERM
original_traps="$(trap -p EXIT HUP INT TERM)"
assert_traps() {
    [[ "$(trap -p EXIT HUP INT TERM)" == "$original_traps" ]] || exit 91
}
sync_acfs_deployed
assert_traps
sync_acfs_deployed
assert_traps
printf 'changed source\n' > "$TEST_SOURCE/scripts/lib/stack.sh"
mv() { return 75; }
if sync_acfs_deployed; then exit 92; fi
assert_traps
'''
        process = self.start(["/bin/bash", "--noprofile", "--norc", "-c", COMMON + body])
        stdout, stderr = process.communicate(timeout=15)
        self.assertEqual(process.returncode, 0, (stdout + stderr).decode())
        self.assertEqual((self.base / "trap-events").read_text(), "caller-exit\n")
        self.assertEqual((self.acfs / "scripts/lib/stack.sh").read_text(), "original source\n")
        self.assert_runtime_files("scripts/lib/stack.sh")

    def test_interrupted_copy_preserves_previous_script_and_cleans_temporary(self):
        self.write(self.repo, "scripts/lib/stack.sh", "new complete script\n")
        deployed = self.write(self.acfs, "scripts/lib/stack.sh", "old complete script\n", 0o755)
        original_inode = deployed.stat().st_ino
        setup = r'''
cp() {
    printf 'partial' > "${@: -1}"
    printf 'copy-ready:%s\n' "$BASHPID"
    IFS= read -r release
    return 76
}
'''
        process = self.start(["/bin/bash", "--noprofile", "--norc", "-c", COMMON + setup + SYNC])
        line = self.line(process)
        self.assertTrue(line.startswith("copy-ready:"), line)
        os.kill(int(line.partition(":")[2]), signal.SIGTERM)
        # Keep stdin open until the signal has ended the worker: EOF must not
        # accidentally release the blocked copy and masquerade as cancellation.
        process.wait(timeout=5)
        stdout, stderr = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 128 + signal.SIGTERM, (stdout + stderr).decode())
        self.assertEqual(deployed.read_text(), "old complete script\n")
        self.assertEqual(deployed.stat().st_ino, original_inode)
        self.assert_runtime_files("scripts/lib/stack.sh")


if __name__ == "__main__":
    unittest.main()
