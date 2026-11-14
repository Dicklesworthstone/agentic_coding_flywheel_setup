#!/usr/bin/env python3
"""Offline regressions for atomic deployment and saved installation scope.

Run: python3 -B -m unittest discover -s tests/unit -p test_update_deployment.py -v
Real runtime, early security, and managed-shell deployment paths run against
disposable source/runtime trees. Selection cases also exercise main() and real
failure accounting with external installers, package commands, service checks,
and the watchdog replaced by fixture endpoints. No network or real install runs.
"""
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import select
import shlex
import shutil
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
GLOBAL_SYNC = 'sync_acfs_global_wrapper "${TEST_SOURCE_REF:-}" "$TEST_ROOT/global-acfs"'


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

    def test_security_refresh_and_shell_preserve_running_runtime_readers(self):
        old = ("#!/bin/bash\nset -euo pipefail\nprintf 'old-ready\\n'\n"
               "IFS= read -r release\n" + "# unread script body\n" * 16384
               + "printf 'old-finished\\n'\n")
        new = "#!/bin/bash\nprintf 'new-version\\n'\n"
        cases = (("security", "scripts/lib/security.sh", "scripts/lib/security.sh", "update_refresh_installed_security"),
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
        cases = (("security", "scripts/lib/security.sh", "scripts/lib/security.sh", "update_refresh_installed_security"),
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

    def test_fetched_runtime_refresh_remains_pinned_through_shell_update(self):
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
git -C "$TEST_SOURCE" fetch --quiet origin main
_ACFS_RUNTIME_SOURCE_REF="$(git -C "$TEST_SOURCE" rev-parse --verify 'FETCH_HEAD^{commit}')"
sync_acfs_deployed "$_ACFS_RUNTIME_SOURCE_REF" || exit $?
sync_acfs_global_wrapper "$_ACFS_RUNTIME_SOURCE_REF" || exit $?
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

    def test_global_wrapper_failed_real_copy_preserves_working_command(self):
        # A real file-size limit makes coreutils fail after writing part of the
        # source. No mocked publisher is needed to reproduce a broken wrapper.
        self.write(self.repo, "scripts/acfs-global", "#!/bin/bash\n# " + "x" * 4096 + "\n")
        deployed = self.write(self.base, "global-acfs", "#!/bin/bash\nexit 0\n", 0o755)
        before = deployed.stat()
        setup = r'''
update_system_binary_path() {
    [[ "$1" != sudo ]] || return 1
    command -v "$1"
}
ulimit -f 1
'''
        process = self.start(["/bin/bash", "-c", COMMON + setup + GLOBAL_SYNC])
        stdout, stderr = process.communicate(timeout=15)
        self.assertEqual(deployed.read_text(), "#!/bin/bash\nexit 0\n",
                         "failed installation replaced the working command with a partial file")
        self.assertNotEqual(process.returncode, 0, (stdout + stderr).decode())
        after = deployed.stat()
        self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns),
                         (before.st_ino, before.st_mode, before.st_mtime_ns))
        self.assertEqual(list(self.base.rglob(".acfs-deploy.*")), [])
        self.assertEqual(list(self.stage.iterdir()), [])

    def test_global_wrapper_readers_see_complete_versions_during_staging(self):
        old = ("#!/bin/bash\nset -euo pipefail\nprintf 'old-ready\\n'\n"
               "IFS= read -r release\n" + "# unread script body\n" * 16384
               + "printf 'old-finished\\n'\n")
        new = "#!/bin/bash\nprintf 'new-version\\n'\n"
        setup = r'''
pause_copy() {
    printf '#!/bin/bash\n' > "${@: -1}"
    printf 'copy-ready\n'
    IFS= read -r release
}
cp() { pause_copy "$@"; command cp "$@"; }
install() {
    # GNU install removes the previous destination before writing its copy.
    command install -m 0755 /dev/null "${@: -1}" || return $?
    pause_copy "$@"
    command install "$@"
}
mv() {
    local staged="${@: -2:1}" destination="${@: -1}"
    [[ "${staged%/*}" == "${destination%/*}" ]] || return 91
    [[ "$(stat -c '%a' "$staged")" == 755 ]] || return 92
    command mv "$@"
}
'''
        for source_ref in ("", "HEAD"):
            with self.subTest(source_ref=source_ref):
                root, source, _, env = self.phase_tree(source_ref or "checkout")
                source_file = self.write(source, "scripts/acfs-global", new, 0o644)
                if source_ref:
                    self.git(source, "init", "--quiet", "--initial-branch=main")
                    self.commit_tree(source, "selected wrapper")
                    source_file.write_text("dirty checkout must not deploy\n")
                deployed = self.write(root, "global-acfs", old, 0o755)
                before_inode = deployed.stat().st_ino
                reader = self.start(["/bin/bash", str(deployed)], **env)
                self.assertEqual(self.line(reader), "old-ready")
                publisher = self.start(["/bin/bash", "-c", COMMON + setup + GLOBAL_SYNC],
                                       **env, TEST_SOURCE_REF=source_ref)
                self.assertEqual(self.line(publisher), "copy-ready")
                self.assertEqual(deployed.read_text(), old,
                                 "new invocations can observe an incomplete wrapper")
                self.assertEqual(deployed.stat().st_ino, before_inode)
                during = subprocess.run(["/bin/bash", str(deployed)], env=self.env | env,
                                        input="resume\n", text=True, capture_output=True, timeout=5)
                self.assertEqual(during.returncode, 0, during.stderr)
                self.assertEqual(during.stdout, "old-ready\nold-finished\n")
                stdout, stderr = publisher.communicate(input=b"publish\n", timeout=15)
                self.assertEqual(publisher.returncode, 0, (stdout + stderr).decode())
                subsequent = subprocess.run(["/bin/bash", str(deployed)], env=self.env | env,
                                            text=True, capture_output=True, timeout=5)
                self.assertEqual(subsequent.returncode, 0, subsequent.stderr)
                self.assertEqual(subsequent.stdout, "new-version\n")
                stdout, stderr = reader.communicate(input=b"resume\n", timeout=5)
                self.assertEqual(reader.returncode, 0, stderr.decode())
                self.assertEqual(stdout.decode(), "old-finished\n")
                self.assertNotEqual(deployed.stat().st_ino, before_inode)
                self.assertEqual(deployed.stat().st_mode & 0o777, 0o755)
                self.assertEqual(list(root.rglob(".acfs-deploy.*")), [])
                self.assertEqual(list(self.stage.iterdir()), [])

    def test_global_wrapper_staging_failures_preserve_metadata_and_cleanup(self):
        self.write(self.repo, "scripts/acfs-global", "new complete wrapper\n")
        self.commit_source()
        failures = {
            "temporary": "mktemp() { return 72; }\n",
            "partial copy": 'cp() { printf "partial" > "${@: -1}"; return 73; }\n',
            "permissions": "chmod() { return 74; }\n",
            "replacement": "mv() { return 75; }\n",
        }
        for source_ref in ("", "HEAD"):
            for operation, setup in failures.items():
                with self.subTest(source_ref=source_ref, operation=operation):
                    deployed = self.write(self.base, "global-acfs", "old complete wrapper\n", 0o750)
                    before = deployed.stat()
                    self.invoke(GLOBAL_SYNC, setup, success=False, TEST_SOURCE_REF=source_ref)
                    self.assertEqual(deployed.read_text(), "old complete wrapper\n")
                    after = deployed.stat()
                    self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns),
                                     (before.st_ino, before.st_mode, before.st_mtime_ns))
                    self.assertNotIn("Synced ", self.log.read_text() if self.log.exists() else "")
                    self.assertEqual(list(self.base.rglob(".acfs-deploy.*")), [])
                    self.assertEqual(list(self.stage.iterdir()), [])

    def test_global_wrapper_dry_run_idempotence_and_mode_repair(self):
        self.write(self.repo, "scripts/acfs-global", "new wrapper\n")
        deployed = self.write(self.base, "global-acfs", "old wrapper\n", 0o750)
        before = deployed.stat()
        self.invoke(GLOBAL_SYNC, TEST_DRY_RUN="true")
        self.assertEqual(deployed.read_text(), "old wrapper\n")
        after = deployed.stat()
        self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns),
                         (before.st_ino, before.st_mode, before.st_mtime_ns))
        self.invoke(GLOBAL_SYNC)
        self.assertEqual(deployed.read_text(), "new wrapper\n")
        self.assertEqual(deployed.stat().st_mode & 0o777, 0o755)
        before = deployed.stat()
        self.invoke(GLOBAL_SYNC, "cp() { return 73; }\nmv() { return 75; }\n")
        after = deployed.stat()
        self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns),
                         (before.st_ino, before.st_mode, before.st_mtime_ns))
        deployed.chmod(0o644)
        self.invoke(GLOBAL_SYNC)
        self.assertEqual(deployed.stat().st_mode & 0o777, 0o755)
        self.assertEqual(list(self.base.rglob(".acfs-deploy.*")), [])

    def test_global_wrapper_ref_errors_are_not_optional_missing_assets(self):
        self.write(self.repo, "scripts/acfs-global", "committed wrapper\n")
        self.commit_source()
        deployed = self.write(self.base, "global-acfs", "old wrapper\n", 0o755)
        before = deployed.stat()
        for operation in ("ls-tree", "show"):
            with self.subTest(operation=operation):
                setup = r'''
update_bootstrap_git() {
    # Inject failure at the authenticated Git boundary; the updater must not
    # consult an arbitrary shell function named git.
    if [[ "$1" == "$TEST_GIT_FAILURE" ]]; then printf 'partial\n'; return 73; fi
    update_git_at "$ACFS_REPO_ROOT" "$@"
}
'''
                self.invoke(GLOBAL_SYNC, setup, success=False,
                            TEST_SOURCE_REF="HEAD", TEST_GIT_FAILURE=operation)
                self.assertEqual(deployed.read_text(), "old wrapper\n")
                after = deployed.stat()
                self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns),
                                 (before.st_ino, before.st_mode, before.st_mtime_ns))
                self.assertEqual(list(self.stage.iterdir()), [])
        self.invoke(GLOBAL_SYNC, success=False, TEST_SOURCE_REF="missing-ref")
        self.git(self.repo, "mv", "scripts/acfs-global", "scripts/optional-wrapper")
        self.commit_tree(self.repo, "older source without wrapper")
        self.invoke(GLOBAL_SYNC, TEST_SOURCE_REF="HEAD")
        self.invoke(GLOBAL_SYNC)
        self.assertEqual(deployed.read_text(), "old wrapper\n")
        after = deployed.stat()
        self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns),
                         (before.st_ino, before.st_mode, before.st_mtime_ns))
        self.assertEqual(list(self.stage.iterdir()), [])

        # A committed symlink is an existing Git asset, but its blob contains
        # a link target rather than a deployable shell wrapper.
        (self.repo / "scripts/acfs-global").symlink_to("optional-wrapper")
        self.commit_tree(self.repo, "unsupported symlink wrapper")
        self.invoke(GLOBAL_SYNC, success=False, TEST_SOURCE_REF="HEAD")
        self.assertEqual(deployed.read_text(), "old wrapper\n")
        after = deployed.stat()
        self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns),
                         (before.st_ino, before.st_mode, before.st_mtime_ns))
        self.assertEqual(list(self.stage.iterdir()), [])

    def test_global_wrapper_privileged_staging_and_cleanup_use_same_prefix(self):
        # /proc/sys is not writable even under root. The explicit command-prefix
        # double redirects every operation into the fixture before executing it;
        # no operation writes /proc, invokes sudo, or changes process credentials.
        prefix_script = r'''#!/bin/bash
set -euo pipefail
operation="$1"
shift
printf '%s\n' "$operation" >> "$TEST_ROOT/prefix-calls"
[[ "$operation" != true ]] || exit 0
case "$operation" in mkdir|mktemp|cp|chmod|mv|rm) ;; *) exit 91 ;; esac
args=()
for arg in "$@"; do
    case "$arg" in
        /proc/sys/acfs-wrapper-regression*)
            arg="$TEST_ROOT/protected${arg#/proc/sys/acfs-wrapper-regression}"
            ;;
    esac
    args+=("$arg")
done
if [[ "$operation" == "$TEST_PREFIX_FAILURE" ]]; then
    if [[ "$operation" == cp ]]; then printf 'partial' > "${args[${#args[@]}-1]}"; fi
    exit 73
fi
exec "/usr/bin/$operation" "${args[@]}"
'''
        setup = r'''
install() { return 77; }
update_system_binary_path() {
    [[ "$1" != sudo ]] || return 1
    command -v "$1"
}
update_sudo_prefix() {
    [[ "$TEST_PREFIX_FAILURE" != deny ]] || return 1
    local -n result="$1"
    result=(/bin/bash "$TEST_ROOT/privileged-command")
}
'''
        invocation = 'sync_acfs_global_wrapper "" /proc/sys/acfs-wrapper-regression/global-acfs'
        for failure in ("deny", "cp", "chmod", "mv", "none"):
            with self.subTest(failure=failure):
                root, source, _, env = self.phase_tree(f"prefix-{failure}")
                self.write(source, "scripts/acfs-global", "new complete wrapper\n")
                self.write(root, "privileged-command", prefix_script)
                deployed = self.write(root, "protected/global-acfs", "old complete wrapper\n", 0o750)
                before = deployed.stat()
                self.invoke(invocation, setup, success=failure in ("deny", "none"),
                            **env, TEST_PREFIX_FAILURE=failure)
                calls = root / "prefix-calls"
                if failure == "deny":
                    self.assertFalse(calls.exists(), "unavailable privilege must remain an explicit skip")
                else:
                    self.assertTrue(calls.exists(), "protected publication never used its admitted prefix")
                    operations = calls.read_text().splitlines()
                    self.assertEqual(operations[:4], ["true", "mkdir", "mktemp", "cp"])
                    self.assertIn("rm" if failure != "none" else "mv", operations)
                if failure == "none":
                    self.assertEqual(deployed.read_text(), "new complete wrapper\n")
                    self.assertEqual(deployed.stat().st_mode & 0o777, 0o755)
                    self.assertNotEqual(deployed.stat().st_ino, before.st_ino)
                else:
                    self.assertEqual(deployed.read_text(), "old complete wrapper\n")
                    after = deployed.stat()
                    self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns),
                                     (before.st_ino, before.st_mode, before.st_mtime_ns))
                    log = root / "update.log"
                    self.assertNotIn("Synced ", log.read_text() if log.exists() else "")
                self.assertEqual(list(root.rglob(".acfs-deploy.*")), [])
                self.assertEqual(list(self.stage.iterdir()), [])

    def test_global_wrapper_retry_after_checkout_fast_forward(self):
        self.write(self.repo, "VERSION", "base\n")
        self.write(self.repo, "scripts/acfs-global", "old wrapper\n")
        self.commit_source()
        checkout = self.base / "checkout"
        self.git(self.base, "clone", "--quiet", str(self.repo), str(checkout))
        self.write(self.repo, "VERSION", "fresh\n")
        self.write(self.repo, "scripts/acfs-global", "new wrapper\n")
        self.commit_source()
        self.git(checkout, "fetch", "--quiet", "origin", "main")
        self.git(checkout, "merge", "--quiet", "--ff-only", "origin/main")
        deployed = self.write(self.base, "global-acfs", "old wrapper\n", 0o755)
        before = deployed.stat()
        setup = PHASE_SETUP + r'''
SCRIPT_DIR="$TEST_ROOT/no-updater"
cp() {
    if [[ "$1" == -- ]]; then shift; fi
    if [[ "$1" == "$ACFS_REPO_ROOT/scripts/acfs-global" ]]; then
        printf 'partial' > "${@: -1}"
        return 73
    fi
    command cp "$@"
}
'''
        self.invoke("sync_acfs_global_wrapper", setup, success=False, TEST_SOURCE=str(checkout))
        self.assertEqual(self.git(checkout, "rev-parse", "HEAD"), self.git(self.repo, "rev-parse", "HEAD"))
        self.assertEqual(deployed.read_text(), "old wrapper\n")
        after = deployed.stat()
        self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns),
                         (before.st_ino, before.st_mode, before.st_mtime_ns))
        # A failed publication must remain repairable from the same immutable
        # checkout, without another source change or the shell-update phase.
        self.invoke("sync_acfs_global_wrapper", PHASE_SETUP, TEST_SOURCE=str(checkout))
        self.assertEqual(deployed.read_text(), "new wrapper\n")
        self.assertEqual(deployed.stat().st_mode & 0o777, 0o755)
        self.assertEqual(list(self.base.rglob(".acfs-deploy.*")), [])
        self.assertEqual(list(self.stage.iterdir()), [])

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

    def assert_atomic_updater_publication(self, fetched_revision):
        # These deliberately tiny scripts cover only immutable per-file
        # publication. BootstrapHandoffTests covers complete current/fetched
        # generation activation, PID, lock and exact argument preservation.
        replacement = "#!/bin/bash\nprintf 'replacement-activated\\n'\n"
        old = "#!/bin/bash\nprintf 'old-updater-file\\n'\n"
        self.write(self.repo, "scripts/lib/update.sh", old if fetched_revision else replacement, 0o755)
        self.commit_source()
        checkout = self.base / "checkout"
        self.git(self.base, "clone", "--quiet", str(self.repo), str(checkout))
        checkout_head = self.git(checkout, "rev-parse", "HEAD")
        if fetched_revision:
            self.write(self.repo, "scripts/lib/update.sh", replacement, 0o755)
            self.commit_source()
            self.git(checkout, "fetch", "--quiet", "origin", "main")
        revision = self.git(self.repo, "rev-parse", "HEAD")
        deployed = self.write(self.acfs, "scripts/lib/update.sh", old, 0o755)
        original_inode = deployed.stat().st_ino
        self.sync(TEST_SOURCE=str(checkout), TEST_SOURCE_REF=revision)
        launched = subprocess.run([str(deployed)], env=self.env, capture_output=True,
                                  text=True, timeout=5)
        self.assertEqual(launched.returncode, 0, launched.stdout + launched.stderr)
        self.assertEqual(launched.stdout, "replacement-activated\n")
        self.assertEqual(deployed.read_text(), replacement)
        self.assertNotEqual(deployed.stat().st_ino, original_inode)
        self.assertEqual(deployed.stat().st_mode & 0o777, 0o755)
        self.assertEqual(self.git(checkout, "rev-parse", "HEAD"), checkout_head,
                         "publishing an immutable blob must not change the source checkout")
        self.assertEqual(self.git(checkout, "status", "--porcelain"), "")
        self.assert_runtime_files("scripts/lib/update.sh")

    def test_atomic_updater_publication_from_current_revision(self):
        self.assert_atomic_updater_publication(fetched_revision=False)

    def test_atomic_updater_publication_from_fetched_revision(self):
        self.assert_atomic_updater_publication(fetched_revision=True)

    def test_atomic_updater_publication_skips_unchanged_or_missing_source(self):
        replacement = "#!/bin/bash\nprintf 'unexpected-activation\\n'\nexit 83\n"
        for state in ("unchanged", "missing"):
            with self.subTest(state=state):
                root, source, runtime, env = self.phase_tree(state)
                self.write(source, "VERSION", "fixture\n")
                if state == "unchanged":
                    self.write(source, "scripts/lib/update.sh", replacement, 0o755)
                self.git(source, "init", "--quiet", "--initial-branch=main")
                self.commit_tree(source, "fixture")
                self.git(source, "remote", "add", "origin", str(source))
                deployed = self.write(runtime, "scripts/lib/update.sh", replacement, 0o755)
                before = deployed.stat()
                output = self.sync(**env)
                self.assertNotIn("unexpected-activation", output)
                self.assertEqual(deployed.read_text(), replacement)
                after = deployed.stat()
                self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns),
                                 (before.st_ino, before.st_mode, before.st_mtime_ns))
                self.assertFalse((root / "activation-receipt").exists())
                self.assertEqual(list(runtime.rglob(".acfs-deploy.*")), [])
                self.assertEqual(self.git(source, "status", "--porcelain"), "")

    def test_atomic_updater_and_wrapper_copy_failures_preserve_previous_files(self):
        replacement = "#!/bin/bash\nprintf 'unexpected-activation\\n'\nexit 83\n"
        old = "#!/bin/bash\nprintf 'old-updater-file\\n'\n"
        for step in ("copy", "wrapper"):
            with self.subTest(step=step):
                root, source, runtime, env = self.phase_tree(step)
                self.write(source, "scripts/lib/update.sh", replacement, 0o755)
                self.write(source, "scripts/acfs-global", replacement, 0o755)
                self.git(source, "init", "--quiet", "--initial-branch=main")
                self.commit_tree(source, "fixture")
                self.git(source, "remote", "add", "origin", str(source))
                deployed = self.write(runtime, "scripts/lib/update.sh", old, 0o755)
                wrapper = self.write(root, "global-acfs", old, 0o755)
                before = deployed.stat()
                wrapper_before = wrapper.stat()
                setup = 'cp() { printf "partial" > "${@: -1}"; return 73; }\n'
                operation = "sync_acfs_deployed" if step == "copy" else "sync_acfs_global_wrapper"
                body = COMMON + PHASE_SETUP + setup + (
                    f'if {operation}; then printf "unexpected-continuation\\n"; else exit "$?"; fi\n')
                process = self.start(["/bin/bash", "-c", body], **env, TEST_ORIGIN=str(source))
                stdout, stderr = process.communicate(timeout=15)
                output = (stdout + stderr).decode()
                self.assertEqual(process.returncode, 1, output)
                self.assertNotIn("unexpected-", output)
                self.assertEqual(deployed.read_text(), old)
                self.assertEqual(wrapper.read_text(), old)
                after = deployed.stat()
                wrapper_after = wrapper.stat()
                self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns),
                                 (before.st_ino, before.st_mode, before.st_mtime_ns))
                self.assertEqual((wrapper_after.st_ino, wrapper_after.st_mode, wrapper_after.st_mtime_ns),
                                 (wrapper_before.st_ino, wrapper_before.st_mode, wrapper_before.st_mtime_ns))
                self.assertFalse((root / "activation-receipt").exists())
                self.assertEqual(list(runtime.rglob(".acfs-deploy.*")), [])
                self.assertEqual(list(self.stage.iterdir()), [])

    def test_bootstrap_preparation_failure_stops_before_publication_or_execution(self):
        self.write(self.repo, "VERSION", "fixture one\n")
        self.commit_source()
        checkout = self.base / "checkout"
        subprocess.run(["git", "clone", "--quiet", str(self.repo), str(checkout)], env=self.env,
                       check=True, capture_output=True, timeout=5)
        deployed = self.write(self.acfs, "scripts/lib/update.sh", "previous working updater\n", 0o755)
        before = deployed.read_bytes(), deployed.stat()
        body = r'''
UPDATE_SELF=true
BOOTSTRAP_SELF_UPDATE=false
ACFS_SELF_UPDATE_DONE=false
SCRIPT_DIR="$TEST_ROOT/no-updater"
is_expected_acfs_origin_url() { return 0; }
update_bootstrap_files() {
    if [[ "$1" == prepare ]]; then printf 'preparation attempted\n' >&2; return 73; fi
    printf 'unexpected publication\n' >&2
    return 91
}
update_bootstrap_exec() { printf 'unexpected execution\n'; return 92; }
sync_acfs_deployed() { printf 'unexpected deployment\n'; }
sync_acfs_global_wrapper() { printf 'unexpected wrapper\n'; }
sync_acfs_global_command_links() { printf 'unexpected links\n'; }
if update_bootstrap_handoff "$TEST_REVISION"; then exit 0; else exit "$?"; fi
'''
        for state in ("current", "fast-forward"):
            with self.subTest(checkout=state):
                if state == "fast-forward":
                    self.write(self.repo, "VERSION", "fixture two\n")
                    self.commit_source()
                self.git(checkout, "fetch", "--quiet", "origin", "main")
                original_head = self.git(checkout, "rev-parse", "HEAD")
                process = self.start(["/bin/bash", "-c", COMMON + body], TEST_SOURCE=str(checkout),
                                     TEST_REVISION=self.git(self.repo, "rev-parse", "HEAD"))
                stdout, stderr = process.communicate(timeout=15)
                self.assertEqual(process.returncode, 1, (stdout + stderr).decode())
                self.assertIn(b"preparation attempted", stderr)
                self.assertNotIn(b"unexpected", stdout + stderr)
                self.assertEqual(self.git(checkout, "rev-parse", "HEAD"), original_head)
                self.assertEqual(deployed.read_bytes(), before[0])
                after = deployed.stat()
                self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns),
                                 (before[1].st_ino, before[1].st_mode, before[1].st_mtime_ns))

    def test_source_ref_extraction_failure_is_not_an_optional_skip(self):
        self.write(self.repo, "scripts/lib/stack.sh", "committed script\n", 0o755)
        self.commit_source()
        deployed = self.write(self.acfs, "scripts/lib/stack.sh", "old script\n", 0o755)
        original = deployed.stat()
        self.sync(r'''
update_bootstrap_git() {
    if [[ "$1" == show && "$2" == HEAD:scripts/lib/stack.sh ]]; then
        printf 'partial source\n'
        return 73
    fi
    update_git_at "$ACFS_REPO_ROOT" "$@"
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
update_bootstrap_git() {
    if [[ "$1" == ls-tree && "${@: -1}" == scripts/lib/stack.sh ]]; then return 77; fi
    update_git_at "$ACFS_REPO_ROOT" "$@"
}
''', success=False, TEST_SOURCE_REF="HEAD")
        self.assertEqual(deployed.read_text(), "old script\n")
        self.assertEqual(deployed.stat().st_ino, original_inode)
        self.assertNotIn("Synced ", self.log.read_text() if self.log.exists() else "")
        self.assert_runtime_files("scripts/lib/stack.sh")

    def test_fetched_refresh_propagates_failure_without_later_actions(self):
        self.write(self.repo, "VERSION", "fixture\n")
        self.commit_source()
        self.git(self.repo, "remote", "add", "origin", str(self.repo))
        self.git(self.repo, "fetch", "--quiet", "origin", "main")
        revision = self.git(self.repo, "rev-parse", "HEAD")
        body = r'''
update_bootstrap_handoff() {
    [[ "$1" == "$TEST_REVISION" ]] || return 91
    return "$TEST_FAILURE"
}
log_item() { if [[ "$1" == ok ]]; then printf 'unexpected success log\n'; fi; }
if _acfs_refresh_security_from_fetched_remote; then exit 0; else exit "$?"; fi
'''
        for failure in (73, 143):
            with self.subTest(status=failure):
                process = self.start(["/bin/bash", "-c", COMMON + body], TEST_FAILURE=str(failure),
                                     TEST_REVISION=revision)
                stdout, stderr = process.communicate(timeout=15)
                self.assertEqual(process.returncode, failure, (stdout + stderr).decode())
                self.assertEqual(stdout, b"")
                self.assertNotIn("Refreshed deployed ACFS runtime",
                                 self.log.read_text() if self.log.exists() else "")

    def test_fetched_refresh_cannot_continue_without_resolving_a_commit(self):
        self.write(self.repo, "VERSION", "fixture\n")
        self.commit_source()
        body = r'''
update_bootstrap_handoff() { printf 'unexpected handoff\n'; }
log_item() { if [[ "$1" == ok ]]; then printf 'unexpected success log\n'; fi; }
if _acfs_refresh_security_from_fetched_remote; then exit 0; else exit "$?"; fi
'''
        output = self.shell(body, success=False)
        self.assertNotIn("unexpected", output)

    def test_runtime_source_selection_does_not_trust_inherited_environment(self):
        output = self.shell('printf "selected:%s\\n" "${_ACFS_RUNTIME_SOURCE_REF:-}"',
                            _ACFS_RUNTIME_SOURCE_REF="untrusted-inherited-ref")
        self.assertEqual(output, "selected:\n")

    def assert_fetched_refresh_stays_pinned_through_shell_update(self, checkout_is_runtime):
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
git -C "$ACFS_REPO_ROOT" fetch origin main --quiet
_ACFS_RUNTIME_SOURCE_REF="$(git -C "$ACFS_REPO_ROOT" rev-parse --verify 'FETCH_HEAD^{commit}')"
sync_acfs_deployed "$_ACFS_RUNTIME_SOURCE_REF" || exit $?
sync_acfs_global_wrapper "$_ACFS_RUNTIME_SOURCE_REF" || exit $?
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

    def test_fetched_refresh_stays_pinned_through_shell_update_with_dirty_checkout(self):
        self.assert_fetched_refresh_stays_pinned_through_shell_update(checkout_is_runtime=False)

    def test_dirty_checkout_runtime_preserves_remapped_assets_and_tracked_edits(self):
        self.assert_fetched_refresh_stays_pinned_through_shell_update(checkout_is_runtime=True)

    def test_admitted_self_update_propagates_sync_failure(self):
        self.write(self.repo, "VERSION", "fixture\n")
        self.commit_source()
        subprocess.run(["git", "-C", str(self.repo), "remote", "add", "origin", str(self.repo)],
                       env=self.env, check=True, capture_output=True, timeout=5)
        body = r'''
UPDATE_SELF=true
BOOTSTRAP_SELF_UPDATE=false
ACFS_SELF_UPDATE_DONE=true
# This unit starts at the admitted child boundary; complete admission and
# current/fast-forward source selection are covered by BootstrapHandoffTests.
_ACFS_BOOTSTRAP_REF="$(git -C "$ACFS_REPO_ROOT" rev-parse HEAD)"
is_expected_acfs_origin_url() { return 0; }
update_refresh_installed_security() { :; }
sync_acfs_deployed() { return "$TEST_FAILURE"; }
if update_acfs_self; then exit 0; else exit "$?"; fi
'''
        for failure in (73, 143):
            with self.subTest(status=failure):
                process = self.start(["/bin/bash", "-c", COMMON + body], TEST_FAILURE=str(failure))
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
update_bootstrap_git() {
    if [[ "$1" == ls-tree ]]; then return 77; fi
    update_git_at "$ACFS_REPO_ROOT" "$@"
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


SELECTION_SETUP = r'''
source "$UPDATE_TEST_LIBRARY"
ACFS_REPO_ROOT="$TEST_SOURCE"
UPDATE_LOG_DIR="$TEST_ROOT/logs"
UPDATE_LOG_FILE="$TEST_ROOT/update.log"
DRY_RUN="$TEST_DRY_RUN" FORCE_MODE="$TEST_FORCE"
ABORT_ON_FAILURE="$TEST_ABORT" QUIET=true YES_MODE=true
UPDATE_CMD_TIMEOUT=3
# Keep the real target-home and runtime resolution. Only the account database
# is a fixture, so these cases also run safely when the test caller is root.
update_current_user() { printf '%s\n' "$TEST_CURRENT_USER"; }
update_getent_passwd_entry() {
    [[ "$1" == fixture ]] || return 1
    printf 'fixture:x:2001:2001:Fixture:%s:/bin/bash\n' "$TEST_HOME"
}
# Retain shell-created output/staging files with the diagnostic fixture.
rm() { :; }
'''

SELECTION_DISPATCH = r'''
# These are the external mutation boundaries. Real category dispatch,
# selection loading, run_cmd, failure counters, and runtime deployment remain.
fixture_record() { printf '%s\n' "$*" >> "$TEST_EVENTS"; }
update_require_security() { return 0; }
capture_version_before() { VERSION_BEFORE["$1"]="fixture"; }
capture_version_after() { return 1; }
update_binary_path() {
    case ",$TEST_PRESENT," in
        *,"$1",*) printf '%s/%s\n' "$TEST_BIN" "$1" ;;
        *) return 1 ;;
    esac
}
update_binary_exists() { update_binary_path "$1" >/dev/null; }
update_tool_binary_path() { update_binary_path "$1"; }
update_rust_binary_path() { update_binary_path "$1"; }
update_run_verified_installer() {
    fixture_record "installer:$*"
    [[ "$TEST_FAILURE" != "$1" ]] || return 47
}
update_run_verified_installer_with_env() { update_run_verified_installer "$@"; }
update_run_verified_installer_or_existing_on_transient() {
    local label="$1" tool="$2"
    shift 4
    run_cmd "$label" update_run_verified_installer "$tool" "$@"
}
update_run_verified_installer_with_target_tmpdir_or_existing_on_transient() {
    update_run_verified_installer_or_existing_on_transient "$@"
}
update_ensure_minisign() { fixture_record "provision:minisign"; }
update_agent_mail() { run_cmd "MCP Agent Mail" update_run_verified_installer mcp_agent_mail; }
update_run_slb_verified_install() { update_run_verified_installer slb; }
update_run_fsfs_installer() { update_run_verified_installer fsfs "$@"; }
update_run_asb_installer() { update_run_verified_installer asb; }
update_run_pcr_installer_and_verify() { update_run_verified_installer pcr; }
update_run_cargo_git_source_install() { fixture_record "cargo-install:$*"; }
run_cmd_claude_update() { run_cmd "Claude Code" update_run_verified_installer claude; }
update_run_bounded_in_target_context() { fixture_record "native:$*"; }
update_run_in_target_context() { fixture_record "target:$*"; }
update_run_rust_in_target_context() {
    fixture_record "rust:$*"
    if [[ "$*" == *"toolchain list" ]]; then printf 'stable-fixture\n'; fi
}
update_run_maintenance_in_target_context() { fixture_record "maintenance:$*"; }
update_install_agy_locked_launchers() { fixture_record "launchers:agy"; }
update_omz() { fixture_record "shell:omz"; }
update_p10k() { fixture_record "shell:p10k"; }
update_zsh_plugins() { fixture_record "shell:plugins"; }
update_atuin() { fixture_record "shell:atuin"; }
update_zoxide() { fixture_record "shell:zoxide"; }
update_ensure_jq_available() { :; }
update_procwatch_start() { :; }
update_procwatch_stop() { :; }
update_record_nightly_outcome() { :; }
update_report_service_binary_drift() { :; }
'''


class ModuleSelectionUpdateTests(unittest.TestCase):
    """Saved module scope survives actual updater dispatch and publication."""

    @classmethod
    def setUpClass(cls):
        cls.artifacts = Path(tempfile.mkdtemp(prefix="acfs-update-selection-"))
        print("Updater selection artifacts:", cls.artifacts, flush=True)

    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="case-", dir=self.artifacts))
        self.home = self.base / "target home"
        self.acfs = self.home / ".acfs"
        self.repo = self.base / "source"
        self.stage = self.base / "temporary"
        self.bin = self.home / ".local/bin"
        for path in (self.acfs, self.repo, self.stage, self.bin):
            path.mkdir(parents=True)
        self.events_file = self.base / "events"
        self.state = self.acfs / "state.json"
        self.env = {
            "PATH": "/usr/bin:/bin", "HOME": str(self.home),
            "TARGET_USER": "fixture", "TARGET_HOME": str(self.home),
            "TMPDIR": str(self.stage), "TEST_ROOT": str(self.base),
            "TEST_HOME": str(self.home), "TEST_SOURCE": str(self.repo),
            "TEST_EVENTS": str(self.events_file), "TEST_BIN": str(self.bin),
            "TEST_CURRENT_USER": "fixture", "TEST_DRY_RUN": "false",
            "TEST_FORCE": "false", "TEST_ABORT": "false",
            "TEST_PRESENT": "", "TEST_FAILURE": "",
            "UPDATE_TEST_LIBRARY": os.environ.get(
                "ACFS_UPDATE_TEST_LIBRARY", str(ROOT / "scripts/lib/update.sh")),
            "ACFS_GLOBAL_BIN_DIR": str(self.base / "global-bin"),
            "NO_COLOR": "1", "ACFS_INTERACTIVE": "false",
        }

    def selection(self, *modules, path=None):
        (path or self.state).write_text(json.dumps({
            "schema_version": 3, "target_user": "fixture",
            "target_home": str(self.home),
            "module_selection": {"schema_version": 1, "selected_modules": list(modules)},
        }))

    def write(self, root, path, content, mode=0o644):
        result = root / path
        result.parent.mkdir(parents=True, exist_ok=True)
        result.write_text(content)
        result.chmod(mode)
        return result

    def source_assets(self):
        assets = {
            "scripts/lib/update.sh": "#!/bin/bash\nprintf 'updated runtime\\n'\n",
            "scripts/lib/state.sh": (ROOT / "scripts/lib/state.sh").read_text(),
            "scripts/lib/doctor.sh": "#!/bin/bash\nprintf 'doctor\\n'\n",
            "scripts/lib/agy_locked.py": "print('agy fixture')\n",
            "scripts/acfs-update": "#!/bin/bash\nprintf 'update\\n'\n",
            "scripts/acfs-global": "#!/bin/bash\nprintf 'global acfs\\n'\n",
            "packages/onboard/onboard.sh": "#!/bin/bash\nprintf 'onboard\\n'\n",
            "acfs/onboard/lessons/fixture.md": "# Fixture lesson\n",
            "acfs/tmux/tmux.conf": "set -g mouse on\n",
            "acfs/zsh/acfs.zshrc": "export ACFS_FIXTURE=1\n",
            "acfs/zsh/p10k.zsh": "# Managed theme fixture\n",
            "scripts/completions/_acfs": "# Managed completion fixture\n",
        }
        for path, content in assets.items():
            self.write(self.repo, path, content, 0o755 if path.endswith(".sh") else 0o644)

    def shell(self, body, *, code=0, dispatch=True, **env):
        script = SELECTION_SETUP + (SELECTION_DISPATCH if dispatch else "") + body
        result = subprocess.run(
            ["/bin/bash", "--noprofile", "--norc", "-c", script],
            env=self.env | env, text=True, capture_output=True, timeout=20,
        )
        if code is not None:
            self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result

    def events(self):
        return self.events_file.read_text().splitlines() if self.events_file.exists() else []

    def wrapper(self, checkpoint, *, code=0):
        wrapper_path = self.write(
            self.acfs, "bin/acfs-update",
            Path(os.environ.get("ACFS_UPDATE_TEST_WRAPPER", ROOT / "scripts/acfs-update")).read_text(),
            0o755,
        )
        self.write(self.acfs, "scripts/lib/update.sh", r'''#!/bin/bash
source "$UPDATE_TEST_LIBRARY"
# Root's production home is intentionally fixed to /root. Keep this read-only
# checkpoint probe inside its fixture while exercising the complete wrapper.
if [[ "$EUID" -eq 0 ]]; then
    update_target_home() { printf '%s\n' "$TEST_HOME"; }
fi
update_load_module_selection || exit $?
if state_module_is_selected stack.ntm; then printf 'NTM:selected\n'; else printf 'NTM:omitted\n'; fi
if state_module_is_selected stack.caam; then printf 'CAAM:selected\n'; else printf 'CAAM:omitted\n'; fi
printf 'checkpoint-accepted\n' >> "$TEST_EVENTS"
''', 0o755)
        env = self.env | {
            "ACFS_HOME": str(self.acfs), "ACFS_STATE_FILE": str(checkpoint),
            "ACFS_SYSTEM_STATE_FILE": str(self.base / "missing system checkpoint.json"),
        }
        env.pop("TARGET_USER")
        # ubs:ignore[python.taint.command] - the trusted test harness chooses the wrapper under test, not external user input.
        result = subprocess.run(
            ["/bin/bash", str(wrapper_path), "--stack-only"], env=env,
            text=True, capture_output=True, timeout=20,
        )
        if code is not None:
            self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result

    def wrapper_selection(self, path, *modules):
        self.selection(*modules, path=path)
        document = json.loads(path.read_text())
        document["target_user"] = pwd.getpwuid(os.geteuid()).pw_name
        path.write_text(json.dumps(document))

    def installers(self):
        return [event.partition(":")[2].split()[0] for event in self.events()
                if event.startswith("installer:")]

    def test_stack_subset_updates_only_selected_tool_and_required_prerequisite(self):
        for module, tool, needs_minisign in (
            ("stack.ntm", "ntm", False), ("stack.caam", "caam", True),
            ("stack.mcp_agent_mail", "mcp_agent_mail", True),
            ("utils.giil", "giil", False),
        ):
            with self.subTest(module=module):
                self.selection(module)
                self.events_file.write_text("")
                self.shell("update_stack\n")
                self.assertEqual(self.installers(), [tool])
                self.assertEqual("provision:minisign" in self.events(), needs_minisign)

    def test_force_installs_selected_missing_agents_without_expanding_scope(self):
        self.selection("agents.omp", "cloud.vercel", "lang.uv")
        self.shell(
            "update_agents\nupdate_cloud\nupdate_stack\nupdate_bun\n"
            "update_rust\nupdate_cargo_tools\nupdate_uv\nupdate_go\n",
            TEST_FORCE="true", TEST_PRESENT="bun,uv",
        )
        self.assertEqual(self.installers(), ["omp"])
        native = [event for event in self.events() if event.startswith("native:")]
        self.assertEqual(native, [
            f"native:{self.bin}/bun install -g --trust vercel@latest",
            f"native:{self.bin}/uv self update",
        ])
        self.assertNotIn("launchers:agy", self.events())

    def test_present_but_unselected_tools_and_shell_settings_remain_untouched(self):
        self.selection("acfs.update")
        self.source_assets()
        self.shell(
            "update_agents\nupdate_cloud\nupdate_stack\nupdate_bun\n"
            "update_rust\nupdate_cargo_tools\nupdate_uv\nupdate_go\nupdate_shell\n",
            TEST_FORCE="true",
            TEST_PRESENT="claude,codex,agy-real,omp,opencode,grok,bun,uv,rustup,cargo,"
                         "go,sg,lsd,dust,tldr,wrangler,vercel,supabase,gh,gcloud,atuin,zoxide",
        )
        self.assertEqual(self.events(), [])
        self.assertTrue((self.acfs / "bin/acfs-update").is_file())
        for path in ("bin/acfs", "bin/agy-locked", "onboard/onboard.sh",
                     "tmux/tmux.conf", "zsh/acfs.zshrc", "completions/_acfs"):
            self.assertFalse((self.acfs / path).exists(), path)
        self.assertFalse((self.home / ".profile").exists())
        self.assertFalse((self.home / ".zprofile").exists())

    def test_scoped_cloud_update_does_not_manage_external_google_cloud_sdk(self):
        self.selection("cloud.vercel")
        self.shell("update_cloud\n", TEST_PRESENT="bun,vercel,gcloud")
        self.assertEqual(self.events(), [
            f"native:{self.bin}/bun install -g --trust vercel@latest",
        ])

    def test_legacy_cloud_update_keeps_external_google_cloud_sdk_maintenance(self):
        self.shell("dpkg() { return 1; }; update_cloud\n", TEST_PRESENT="gcloud")
        self.assertEqual(self.events(), [
            f"maintenance:cloud {self.bin}/gcloud components update --quiet",
        ])

    def test_force_repairs_missing_selected_cargo_tools_without_expanding_scope(self):
        for modules, packages in (
            (("tools.ast_grep",), ("ast-grep",)),
            (("cli.modern",), ()),
            (("tools.ast_grep", "cli.modern"), ("ast-grep",)),
            (("lang.rust",), ()),
        ):
            with self.subTest(modules=modules):
                self.selection(*modules)
                self.events_file.write_text("")
                self.shell("update_cargo_tools\n", TEST_FORCE="true", TEST_PRESENT="cargo")
                self.assertEqual(self.events(), [
                    f"rust:{self.bin}/cargo install {package} --locked --force"
                    for package in packages
                ])

    def test_scoped_cli_packages_do_not_gain_cargo_installs(self):
        self.selection("cli.modern")
        self.shell("update_cargo_tools\n", TEST_FORCE="true",
                   TEST_PRESENT="cargo,lsd,dust,tldr")
        self.assertEqual(self.events(), [])

    def test_legacy_cargo_update_keeps_maintenance_of_present_extras(self):
        self.shell("update_cargo_tools\n", TEST_PRESENT="cargo,lsd,dust,tldr")
        self.assertEqual(self.events(), [
            f"rust:{self.bin}/cargo install {package} --locked --force"
            for package in ("lsd", "du-dust", "tealdeer")
        ])

    def test_missing_selected_cargo_tool_is_not_provisioned_without_force(self):
        self.selection("tools.ast_grep", "cli.modern")
        self.shell("update_cargo_tools\n", TEST_PRESENT="cargo")
        self.assertEqual(self.events(), [])

    def test_force_cargo_repair_dry_run_does_not_execute_installs(self):
        self.selection("tools.ast_grep", "cli.modern")
        result = self.shell("QUIET=false\nupdate_cargo_tools\n", TEST_PRESENT="cargo",
                            TEST_FORCE="true", TEST_DRY_RUN="true")
        self.assertEqual(self.events(), [])
        self.assertIn("Update ast-grep", result.stdout)

    def test_force_cargo_repair_reports_missing_prerequisite_as_failure(self):
        self.selection("tools.ast_grep")
        result = self.shell(
            'update_cargo_tools\nprintf "FAILURES:%s\\n" "$FAIL_COUNT"\n',
            TEST_FORCE="true",
        )
        self.assertIn("FAILURES:1", result.stdout)
        self.assertEqual(self.events(), [])

    def test_force_dry_run_previews_missing_rust_and_ast_grep_without_false_failure(self):
        self.selection("lang.rust", "tools.ast_grep")
        result = self.shell(
            'QUIET=false\nupdate_rust\nupdate_cargo_tools\nprintf "FAILURES:%s\\n" "$FAIL_COUNT"\n',
            TEST_FORCE="true", TEST_DRY_RUN="true",
        )
        self.assertIn("Rust (install)", result.stdout)
        self.assertIn("Update ast-grep (after Rust installation)", result.stdout)
        self.assertIn("FAILURES:0", result.stdout)
        self.assertEqual(self.events(), [])

    def test_force_without_selected_cargo_tools_does_not_require_cargo(self):
        for module in ("acfs.update", "cli.modern", "lang.rust"):
            with self.subTest(module=module):
                self.selection(module)
                result = self.shell(
                    'update_cargo_tools\nprintf "FAILURES:%s\\n" "$FAIL_COUNT"\n',
                    TEST_FORCE="true",
                )
                self.assertIn("FAILURES:0", result.stdout)
                self.assertEqual(self.events(), [])

    def test_selected_failure_still_counts_and_later_selected_tools_continue(self):
        self.selection("stack.beads_viewer", "stack.beads_rust")
        result = self.shell(
            'update_stack\nprintf "COUNTS:%s:%s\\n" "$SUCCESS_COUNT" "$FAIL_COUNT"\n',
            TEST_FAILURE="bv",
        )
        self.assertEqual(self.installers(), ["bv", "br"])
        self.assertIn("COUNTS:1:1", result.stdout)

    def test_abort_on_selected_failure_still_stops_later_tools(self):
        self.selection("stack.beads_viewer", "stack.beads_rust")
        result = self.shell("update_stack\n", code=None, TEST_FAILURE="bv", TEST_ABORT="true")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.installers(), ["bv"])

    def test_legacy_installation_without_scope_keeps_full_stack_dispatch(self):
        self.shell("update_stack\n")
        self.assertEqual(set(self.installers()), {
            "brenner_bot", "ntm", "mcp_agent_mail", "ms", "apr", "pt", "xf",
            "ubs", "bv", "br", "cass", "cm", "caam", "slb", "ru", "dcg",
            "rch", "giil", "csctf", "srps", "tru", "rano", "mdwb", "s2p",
            "fsfs", "sbh", "casr", "dsr", "ee", "fmd", "pi", "pfr",
        })
        self.assertIn("provision:minisign", self.events())

    def test_category_flags_narrow_the_saved_scope(self):
        self.selection("agents.omp", "stack.ntm", "lang.bun", "cloud.vercel")
        self.shell("main --yes --agents-only --no-self-update --force\n", TEST_PRESENT="bun")
        self.assertEqual(self.installers(), ["omp"])
        self.assertFalse(any(event.startswith("native:") for event in self.events()))

    def maintenance_files(self):
        contents = {
            ".claude/settings.json": json.dumps({
                "hooks": {"PreToolUse": [{"hooks": [
                    {"type": "command", "command": "python3 ~/.claude/hooks/git_safety_guard.py"},
                    {"type": "command", "command": "keep-review-marker"},
                ]}]},
            }) + "\n",
            ".acfs/zsh/acfs.zshrc": "alias br='bun run dev'\n# atuin init zsh\n",
            ".zshrc.local": "# preserved setting\nalias bv='beads_viewer'\n",
            ".zshrc": 'eval "$(atuin init zsh)"\n',
        }
        for path, content in contents.items():
            self.write(self.home, path, content)
        self.write(self.bin, "flywheel-update-agents-md", "#!/bin/sh\nexit 0\n", 0o755)
        return contents

    def test_category_flags_also_limit_real_config_cleanup_and_guide_generation(self):
        self.selection("agents.claude", "shell.omz", "tools.atuin", "stack.beads_rust",
                       "stack.beads_viewer", "cloud.vercel", "lang.uv")
        all_paths = {".claude/settings.json", ".acfs/zsh/acfs.zshrc", ".zshrc.local", ".zshrc"}
        for flags, changed_paths, guide in (
            ("--cloud-only", set(), False),
            ("--runtime-only", set(), False),
            ("--apt-only", set(), False),
            ("--agents-only", {".claude/settings.json"}, True),
            ("--stack-only", {".acfs/zsh/acfs.zshrc", ".zshrc.local"}, True),
            ("--shell-only", {".zshrc"}, False),
            ("--no-agents --no-stack --no-shell", set(), False),
            ("", all_paths, True),
        ):
            with self.subTest(flags=flags):
                before = self.maintenance_files()
                self.events_file.write_text("")
                self.shell(f"main --yes --no-self-update {flags}\n",
                           TEST_PRESENT="bun,uv,vercel,flywheel-update-agents-md")
                changed = {path for path, content in before.items()
                           if (self.home / path).read_text() != content}
                self.assertEqual(changed, changed_paths)
                self.assertEqual(any(event.startswith("maintenance:guide ")
                                     for event in self.events()), guide)
                settings = json.loads((self.home / ".claude/settings.json").read_text())
                commands = [hook["command"]
                            for entry in settings["hooks"]["PreToolUse"] for hook in entry["hooks"]]
                self.assertIn("keep-review-marker", commands)
                self.assertIn("# preserved setting", (self.home / ".zshrc.local").read_text())

    def test_enabled_categories_do_not_clean_config_for_omitted_modules(self):
        self.selection("acfs.update")
        before = self.maintenance_files()
        self.shell("main --yes --no-self-update --force\n",
                   TEST_PRESENT="flywheel-update-agents-md")
        self.assertEqual({path: (self.home / path).read_text() for path in before}, before)
        self.assertFalse(any(event.startswith("maintenance:guide ") for event in self.events()))

    def test_agent_guide_requires_matching_category_and_selected_modules(self):
        self.maintenance_files()
        for module, flags, expected in (
            ("agents.claude", "--stack-only", False),
            ("stack.ntm", "--agents-only", False),
            ("agents.claude", "--agents-only", True),
            ("stack.ntm", "--stack-only", True),
        ):
            with self.subTest(module=module, flags=flags):
                self.selection(module)
                self.events_file.write_text("")
                self.shell(f"main --yes --no-self-update {flags}\n",
                           TEST_PRESENT="flywheel-update-agents-md")
                self.assertEqual(any(event.startswith("maintenance:guide ")
                                     for event in self.events()), expected)

    def drift_service(self):
        # The production drift dispatcher and saved-scope reader run unchanged.
        # Only actual service observation/restart is an inert executable.
        self.write(self.acfs, "scripts/lib/acfs-services.sh", r'''#!/bin/bash
set -eu
case "$1" in
    drift)
        for service in agent-mail cm cass; do
            if [[ -f "$TEST_ROOT/restarted-$service" ]]; then
                printf '%s|ok|pid 7 runs the installed executable\n' "$service"
            else
                printf '%s|stale|pid 7 runs the old executable\n' "$service"
            fi
        done
        ;;
    restart)
        printf 'restart:%s\n' "$2" >> "$TEST_EVENTS"
        printf 'restarted\n' > "$TEST_ROOT/restarted-$2"
        ;;
    *) exit 64 ;;
esac
''', 0o755)

    def test_category_only_main_does_not_restart_excluded_stack_services(self):
        self.selection("stack.cm")
        self.drift_service()
        for flags in ("--cloud-only", "--agents-only", "--runtime-only", "--apt-only", "--shell-only"):
            with self.subTest(flags=flags):
                self.events_file.write_text("")
                result = self.shell(
                    "update_procwatch_start() { :; }\nupdate_procwatch_stop() { :; }\n"
                    f"main --yes --no-self-update {flags}\n",
                    dispatch=False, ACFS_UPDATE_RESTART_SERVICES="agent-mail,cm,cass",
                )
                self.assertIn("cm: pid 7 runs the old executable", result.stdout)
                self.assertEqual(self.events(), [])
                self.assertFalse((self.base / "restarted-cm").exists())

    def test_service_restart_opt_in_is_intersected_with_saved_module_scope(self):
        self.selection("stack.cm")
        self.drift_service()
        result = self.shell("update_report_service_binary_drift\n", dispatch=False,
                            ACFS_UPDATE_RESTART_SERVICES="agent-mail,cm,cass,cm")
        self.assertEqual(self.events(), ["restart:cm"])
        self.assertIn("Restarted cm; it now runs the installed binary", result.stdout)
        self.assertFalse((self.base / "restarted-agent-mail").exists())
        self.assertFalse((self.base / "restarted-cass").exists())

    def test_legacy_service_restart_opt_in_still_restarts_all_requested_stale_services(self):
        self.drift_service()
        result = self.shell("update_report_service_binary_drift\n", dispatch=False,
                            ACFS_UPDATE_RESTART_SERVICES="agent-mail,cm,cass")
        self.assertEqual(self.events(), ["restart:agent-mail", "restart:cm", "restart:cass"])
        for service in ("agent-mail", "cm", "cass"):
            self.assertIn(f"Restarted {service}; it now runs the installed binary", result.stdout)

    def test_invalid_scope_stops_main_before_self_update_or_component_mutation(self):
        for invalid in (
            {"schema_version": 2, "selected_modules": ["stack.ntm"]},
            {"schema_version": 1, "selected_modules": []},
            {"schema_version": 1, "selected_modules": ["stack.ntm", "stack.ntm"]},
            {"schema_version": 1, "selected_modules": ["stack.does_not_exist"]},
            False,
        ):
            with self.subTest(invalid=invalid):
                self.state.write_text(json.dumps({"module_selection": invalid}))
                self.events_file.write_text("")
                result = self.shell(
                    'update_acfs_self() { fixture_record "self-update"; }\nmain --yes\n',
                    code=None,
                )
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.events(), [])
                self.assertFalse((self.base / "update.log").exists())

    def test_malformed_json_does_not_fall_back_to_full_updates(self):
        self.state.write_text('{"module_selection":')
        result = self.shell("update_stack\n", code=None)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.events(), [])

    def test_selection_uses_resolved_target_home_and_ignores_inherited_policy(self):
        self.selection("stack.ntm")
        caller = self.base / "caller"
        self.write(caller, ".acfs/state.json", '{"module_selection":false}\n')
        self.shell(
            "update_stack\n",
            HOME=str(caller), TARGET_HOME=str(caller), ACFS_HOME=str(caller / ".acfs"),
            TEST_CURRENT_USER="caller",
            UPDATE_MODULE_SELECTION_READY="true", ACFS_STATE_SELECTION_MODE="legacy",
        )
        self.assertEqual(self.installers(), ["ntm"])

    def test_custom_checkpoint_scope_is_used_without_a_default_checkpoint(self):
        custom = self.home / "custom checkpoint.json"
        self.selection("stack.ntm", path=custom)
        self.assertFalse(self.state.exists())
        self.shell("update_stack\n", ACFS_STATE_FILE=str(custom), TEST_FORCE="true")
        self.assertEqual(self.installers(), ["ntm"])

    def test_explicit_checkpoint_takes_precedence_over_default_scope(self):
        self.selection("stack.caam")
        custom = self.home / "custom checkpoint.json"
        self.selection("stack.ntm", path=custom)
        self.shell("update_stack\n", ACFS_STATE_FILE=str(custom))
        self.assertEqual(self.installers(), ["ntm"])
        self.assertNotIn("provision:minisign", self.events())

    def test_invalid_custom_checkpoint_never_falls_back_to_default_scope(self):
        self.selection("stack.ntm")
        for name, content in (
            ("missing", None),
            ("malformed", '{"module_selection":'),
            ("wrong-home", {"target_user": "fixture", "target_home": str(self.base / "caller")}),
            ("wrong-user", {"target_user": "another", "target_home": str(self.home)}),
            ("no-identity", {}),
        ):
            with self.subTest(name=name):
                custom = self.home / (name + ".json")
                if isinstance(content, dict):
                    content["module_selection"] = {
                        "schema_version": 1, "selected_modules": ["stack.caam"],
                    }
                    custom.write_text(json.dumps(content))
                elif content is not None:
                    custom.write_text(content)
                self.events_file.write_text("")
                result = self.shell("update_stack\n", code=None, ACFS_STATE_FILE=str(custom))
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.events(), [])
        for path in ("relative.json", "/", str(self.home)):
            with self.subTest(path=path):
                result = self.shell("update_stack\n", code=None, ACFS_STATE_FILE=path)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.events(), [])

    def test_explicit_default_path_preserves_legacy_missing_state_behavior(self):
        self.assertFalse(self.state.exists())
        result = self.shell(
            'update_load_module_selection\nprintf "MODE:%s\\n" "$ACFS_STATE_SELECTION_MODE"\n',
            dispatch=False, ACFS_STATE_FILE=str(self.state),
        )
        self.assertIn("MODE:legacy", result.stdout)

    def test_public_update_wrapper_preserves_custom_checkpoint_without_default(self):
        custom = self.home / "custom checkpoint.json"
        self.wrapper_selection(custom, "stack.ntm")
        self.assertFalse(self.state.exists())
        result = self.wrapper(custom)
        self.assertIn("NTM:selected", result.stdout)
        self.assertIn("CAAM:omitted", result.stdout)
        self.assertEqual(self.events(), ["checkpoint-accepted"])

    def test_public_update_wrapper_preserves_custom_checkpoint_after_context_repair(self):
        self.wrapper_selection(self.state, "stack.caam")
        custom = self.home / "custom checkpoint.json"
        self.wrapper_selection(custom, "stack.ntm")
        result = self.wrapper(custom)
        self.assertIn("NTM:selected", result.stdout)
        self.assertIn("CAAM:omitted", result.stdout)
        self.assertEqual(self.events(), ["checkpoint-accepted"])

    def test_public_update_wrapper_rejects_invalid_explicit_checkpoint(self):
        self.wrapper_selection(self.state, "stack.caam")
        custom = self.home / "wrong identity checkpoint.json"
        self.wrapper_selection(custom, "stack.ntm")
        document = json.loads(custom.read_text())
        document["target_home"] = str(self.base / "another home")
        custom.write_text(json.dumps(document))
        malformed = self.home / "malformed checkpoint.json"
        malformed.write_text('{"module_selection":')
        for checkpoint in (custom, malformed, self.home / "missing checkpoint.json", "relative.json", "/"):
            with self.subTest(checkpoint=str(checkpoint)):
                result = self.wrapper(checkpoint, code=None)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.events(), [])

    def test_catalog_is_parsed_as_data_without_executing_shell_content(self):
        self.selection("stack.ntm")
        self.write(
            self.base, "catalog.sh",
            'printf injected > "$TEST_ROOT/catalog-executed"\n'
            'ACFS_MODULES_IN_ORDER=(\n  "stack.ntm"\n)\n',
        )
        self.shell('_UPDATE_MANIFEST_INDEX="$TEST_ROOT/catalog.sh"\nupdate_stack\n')
        self.assertEqual(self.installers(), ["ntm"])
        self.assertFalse((self.base / "catalog-executed").exists())

    def test_scoped_updates_require_a_valid_catalog_but_legacy_does_not(self):
        self.selection("stack.ntm")
        result = self.shell(
            '_UPDATE_MANIFEST_INDEX="$TEST_ROOT/missing"\nupdate_stack\n', code=None,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.events(), [])
        self.state.write_text('{"schema_version":3}\n')
        self.shell('_UPDATE_MANIFEST_INDEX="$TEST_ROOT/missing"\nupdate_stack\n')
        self.assertIn("ntm", self.installers())

    def test_public_assets_follow_scope_while_shared_runtime_stays_current(self):
        self.selection("acfs.update")
        self.source_assets()
        before = self.state.read_bytes()
        self.shell("sync_acfs_deployed\n", dispatch=False)
        self.assertFalse((self.acfs / "bin/acfs").exists())
        self.assertFalse((self.acfs / "onboard").exists())
        self.assertTrue((self.acfs / "scripts/lib/state.sh").is_file())
        self.assertTrue((self.acfs / "scripts/lib/update.sh").is_file())
        self.assertTrue((self.acfs / "scripts/lib/doctor.sh").is_file())
        self.assertTrue((self.acfs / "bin/acfs-update").is_file())
        self.assertEqual(self.state.read_bytes(), before)
        inode = (self.acfs / "scripts/lib/update.sh").stat().st_ino
        self.shell("sync_acfs_deployed\n", dispatch=False)
        self.assertEqual((self.acfs / "scripts/lib/update.sh").stat().st_ino, inode)
        self.selection("acfs.update", "acfs.onboard")
        self.shell("sync_acfs_deployed\n", dispatch=False)
        self.assertTrue((self.acfs / "onboard/lessons/fixture.md").is_file())
        self.assertFalse((self.acfs / "bin/acfs").exists())

    def test_existing_unselected_commands_configuration_and_profiles_are_preserved(self):
        self.selection("acfs.update")
        self.source_assets()
        kept = [
            self.write(self.acfs, path, "existing user content\n")
            for path in ("bin/acfs", "bin/agy-locked", "onboard/onboard.sh",
                         "tmux/tmux.conf", "zsh/acfs.zshrc", "completions/_acfs")
        ]
        kept += [self.write(self.home, path, "existing user profile\n")
                 for path in (".profile", ".zprofile", ".zshrc")]
        kept.append(self.write(self.base, "global-acfs", "existing command\n", 0o755))
        original = {path: (path.read_bytes(), path.stat().st_ino) for path in kept}
        self.shell(
            'sync_acfs_profile_paths\nsync_acfs_zprofile_paths\nsync_acfs_zsh_loader\n'
            'sync_acfs_zshrc\nsync_acfs_deployed\n'
            'sync_acfs_global_wrapper "" "$TEST_ROOT/global-acfs"\n'
            'sync_acfs_global_command_links\n',
            dispatch=False,
        )
        for path, expected in original.items():
            self.assertEqual((path.read_bytes(), path.stat().st_ino), expected, path)
        self.assertFalse((self.base / "global-bin/onboard").exists())

    def test_selected_public_commands_deploy_link_and_remain_idempotent(self):
        self.selection("acfs.doctor", "acfs.update", "acfs.onboard",
                       "shell.omz", "cli.modern", "agents.antigravity")
        self.source_assets()
        body = ('sync_acfs_deployed\n'
                'sync_acfs_global_wrapper "" "$TEST_ROOT/global-acfs"\n'
                'sync_acfs_global_command_links\n')
        self.shell(body, dispatch=False)
        expected = ("bin/acfs", "bin/acfs-update", "bin/agy-locked", "onboard/onboard.sh",
                    "onboard/lessons/fixture.md", "tmux/tmux.conf", "zsh/acfs.zshrc")
        for path in expected:
            self.assertTrue((self.acfs / path).is_file(), path)
        self.assertEqual((self.base / "global-bin/onboard").resolve(),
                         self.acfs / "onboard/onboard.sh")
        self.assertEqual((self.base / "global-bin/acfs-update").resolve(),
                         self.acfs / "bin/acfs-update")
        self.assertTrue(os.access(self.base / "global-acfs", os.X_OK))
        inodes = {path: (self.acfs / path).stat().st_ino for path in expected}
        self.shell(body, dispatch=False)
        self.assertEqual({path: (self.acfs / path).stat().st_ino for path in expected}, inodes)

    def test_dry_run_publishes_no_runtime_or_public_files(self):
        self.selection("acfs.doctor", "acfs.update", "acfs.onboard")
        self.source_assets()
        self.shell(
            'sync_acfs_deployed\nsync_acfs_global_wrapper "" "$TEST_ROOT/global-acfs"\n'
            'sync_acfs_global_command_links\n',
            dispatch=False, TEST_DRY_RUN="true",
        )
        self.assertEqual(list(self.acfs.iterdir()), [self.state])
        self.assertFalse((self.base / "global-acfs").exists())
        self.assertFalse((self.base / "global-bin").exists())

    def test_selected_deployment_error_is_not_hidden_as_an_exclusion(self):
        self.selection("cli.modern")
        self.source_assets()
        marker = self.write(self.acfs, "tmux/tmux.conf/marker", "keep directory content\n")
        result = self.shell("sync_acfs_deployed\n", code=None, dispatch=False)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(marker.read_text(), "keep directory content\n")
        self.assertFalse((self.acfs / "scripts/lib/update.sh").exists())


class BootstrapHandoffTests(unittest.TestCase):
    """Complete immutable runtime preparation and stranded-install recovery.

    Candidates are real local Git commits containing the production runtime
    and its complete checksum inventory. Fixture ledgers bind those exact test
    inputs; corruption cases change bytes after constructing their ledger.
    No public network endpoint or real tool installer is used. Keep artifacts.
    """

    origin = "https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup.git"
    ledger_path = "scripts/generated/internal_checksums.sh"

    @classmethod
    def setUpClass(cls):
        if os.name != "posix" or not Path("/proc/self/fd").is_dir():
            raise unittest.SkipTest("requires Linux, Bash, Git and flock")
        cls.user = pwd.getpwuid(os.geteuid()).pw_name
        cls.artifacts = Path(tempfile.mkdtemp(prefix="acfs-bootstrap-handoff-"))
        cls.artifacts.chmod(0o700)
        print("Bootstrap handoff artifacts:", cls.artifacts, flush=True)
        cls.snapshot = cls.artifacts / "source-snapshot"
        cls.snapshot.mkdir(mode=0o700)
        cls.source = Path(os.environ.get("ACFS_UPDATE_TEST_LIBRARY", ROOT / "scripts/lib/update.sh"))
        cls.ledger_template = (ROOT / cls.ledger_path).read_text()
        cls.inventory = re.findall(r'^  \[([^\]]+)\]="[0-9a-f]{64}"$',
                                   cls.ledger_template, re.MULTILINE)
        if len(cls.inventory) < 100 or len(set(cls.inventory)) != len(cls.inventory):
            raise AssertionError("review the bootstrap fixture's canonical ledger inventory")
        for relative in cls.inventory:
            original = cls.source if relative == "scripts/lib/update.sh" else ROOT / relative
            destination = cls.snapshot / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(original.read_bytes())
            destination.chmod(original.stat().st_mode & 0o777)
        cls.render_fixture_ledger(cls.snapshot)
        cls.git_env = {
            "PATH": "/usr/bin:/bin", "HOME": str(cls.artifacts),
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C",
        }
        cls.git(cls.snapshot, "init", "--quiet", "--initial-branch=main")
        cls.commit(cls.snapshot, "Complete production bootstrap fixture")
        cls.revision = cls.git(cls.snapshot, "rev-parse", "HEAD")

    @classmethod
    def git(cls, directory, *arguments):
        result = subprocess.run(
            ["/usr/bin/git", "-c", "core.hooksPath=/dev/null", "-C", str(directory),
             *arguments], env=cls.git_env, capture_output=True, text=True, timeout=15,
        )
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        return result.stdout.strip()

    @classmethod
    def commit(cls, directory, message):
        # Commits exist only in disposable fixture repositories, never in ROOT.
        cls.git(directory, "add", "--all")
        cls.git(directory, "-c", "user.name=ACFS Bootstrap Test", "-c",
                "user.email=bootstrap-test@example.invalid", "commit", "--quiet", "-m", message)

    @classmethod
    def render_fixture_ledger(cls, directory):
        """Bind test-input bytes; never regenerate repository outputs here."""
        def record(match):
            relative = match.group(1)
            content = (directory / relative).read_bytes()
            return f'  [{relative}]="{hashlib.sha256(content).hexdigest()}"'
        ledger = re.sub(r'^  \[([^\]]+)\]="[0-9a-f]{64}"$', record,
                        cls.ledger_template, flags=re.MULTILINE)
        (directory / cls.ledger_path).write_text(ledger)

    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="case-", dir=self.artifacts))
        self.home = self.base / "target home"
        self.home.mkdir(mode=0o700)
        self.acfs = self.home / ".acfs"
        self.acfs.mkdir(mode=0o700)
        self.repo = self.base / "checkout"
        self.git(self.base, "clone", "--quiet", "--no-hardlinks",
                 str(self.snapshot), str(self.repo))
        self.git(self.repo, "remote", "set-url", "origin", self.origin)
        self.state = self.acfs / "state.json"
        self.checkpoint()
        self.events = self.base / "installer-events"
        self.env = self.git_env | {
            "HOME": str(self.home), "TARGET_HOME": str(self.home),
            "ACFS_HOME": str(self.acfs), "ACFS_REPO_ROOT": str(self.repo),
            "ACFS_STATE_FILE": str(self.state), "UPDATE_TEST_LIBRARY": str(self.source),
            "NO_COLOR": "1", "ACFS_INTERACTIVE": "false",
            "ACFS_GLOBAL_BIN_DIR": str(self.base / "global-bin"),
            "TEST_EVENTS": str(self.events),
        }
        self.processes = []
        self.addCleanup(self.stop_processes)

    def stop_processes(self):
        for process in self.processes:
            if process.poll() is None:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGKILL)
            process.communicate(timeout=5)

    def nested_case(self):
        case = BootstrapHandoffTests("runTest")
        case.setUp()
        self.addCleanup(case.stop_processes)
        return case

    def checkpoint(self, *, mode="safe", path=None, legacy=False):
        document = {
            "schema_version": 3, "target_user": self.user, "target_home": str(self.home),
            "mode": mode, "completed_phases": ["base", "finalize"],
            "module_selection": {
                "schema_version": 1, "selected_modules": ["acfs.update", "stack.ntm"],
                "requested_modules": ["stack.ntm"],
            },
            "fixture_identity": "must remain byte-for-byte intact",
        }
        if legacy:
            for key in ("module_selection", "target_user", "target_home"):
                document.pop(key)
        target = path or self.state
        target.write_text(json.dumps(document, indent=2) + "\n")
        target.chmod(0o600)
        return target

    def old_runtime(self, state_library="missing", *, self_managed=False):
        if self_managed:
            saved = self.home / "initial-runtime"
            self.acfs.rename(saved)
            self.git(self.base, "clone", "--quiet", "--no-hardlinks",
                     str(self.snapshot), str(self.acfs))
            self.acfs.chmod(0o700)
            self.repo = self.acfs
            self.git(self.repo, "remote", "set-url", "origin", self.origin)
            exclude = self.repo / ".git/info/exclude"
            exclude.write_text(exclude.read_text() + "\n/state.json\n/.update-runtime/\n/logs/\n")
            self.state.write_bytes((saved / "state.json").read_bytes())
            self.state.chmod(0o600)
            self.env["ACFS_REPO_ROOT"] = str(self.repo)
        destination = self.acfs / "scripts/lib/update.sh"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text("#!/bin/bash\nprintf 'previous updater is usable\\n'\n")
        destination.chmod(0o755)
        reader = destination.with_name("state.sh")
        if reader.exists():
            reader.rename(self.base / "retained-original-state.sh")
        if state_library == "outdated":
            reader.write_text("# Legacy deployed state library, before saved module scope.\n"
                              "_ACFS_STATE_SH_LOADED=1\n_state_acquire_lock() { :; }\n")
            reader.chmod(0o644)
        return destination

    @staticmethod
    def file_identity(path):
        stat = path.stat()
        return path.read_bytes(), stat.st_ino, stat.st_mode, stat.st_mtime_ns, stat.st_uid, stat.st_gid

    def call(self, *arguments, code=0, timeout=30, **overrides):
        result = subprocess.run(
            ["/bin/bash", "--noprofile", "--norc", "-c",
             'source "$UPDATE_TEST_LIBRARY"\nupdate_bootstrap_files "$@"\n',
             "bootstrap-fixture", *map(str, arguments)],
            env=self.env | overrides, capture_output=True, text=True, timeout=timeout,
        )
        if code is not None:
            self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result

    def prepare(self, *, revision=None, state=None, code=0):
        result = self.call("prepare", self.repo, revision or self.revision,
                           self.home, self.user, state or self.state, code=code)
        return Path(result.stdout.strip()) if result.returncode == 0 else result

    def activate(self, generation, *, state=None, code=0):
        return self.call("activate", generation, self.home, self.user,
                         state or self.state, code=code)

    def current(self, *, code=0):
        result = self.call("current", self.home, self.user, code=code)
        return Path(result.stdout.strip()) if result.returncode == 0 else result

    def assert_no_installer(self):
        self.assertFalse(self.events.exists(), "bootstrap crossed the tool-installation boundary")

    def test_effective_origin_rewrite_is_rejected_before_fetch_or_runtime_mutation(self):
        previous = self.old_runtime("outdated")
        before = self.file_identity(previous)
        checkpoint = self.file_identity(self.state)
        self.git(self.repo, "config", f"url.{self.snapshot}.insteadOf", self.origin)
        self.assertEqual(self.git(self.repo, "config", "--get", "remote.origin.url"), self.origin)
        self.assertEqual(self.git(self.repo, "remote", "get-url", "origin"), str(self.snapshot))
        fetch_head = self.repo / ".git/FETCH_HEAD"
        self.assertFalse(fetch_head.exists())
        result = subprocess.run(
            ["/bin/bash", "--noprofile", "--norc", "-c",
             'source "$UPDATE_TEST_LIBRARY"\nACFS_REPO_ROOT="$TEST_CHECKOUT"\n'
             'update_bootstrap_fetch_revision\n'],
            env=self.env | {"TEST_CHECKOUT": str(self.repo)},
            capture_output=True, text=True, timeout=30,
        )
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("origin", (result.stdout + result.stderr).lower())
        self.assertFalse(fetch_head.exists(), "rejected transport was nevertheless fetched")
        self.assertFalse((self.acfs / ".update-runtime").exists())
        self.assertEqual(self.file_identity(previous), before)
        self.assertEqual(self.file_identity(self.state), checkpoint)
        self.assert_no_installer()

    def stranded_entry(self, library="missing", *, self_managed=False):
        """New entrypoint published by an old deployer with stale dependencies."""
        entry = self.old_runtime(library, self_managed=self_managed)
        updater = self.source.read_text()
        boundary = '\nif [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then\n    main "$@"\nfi'
        self.assertEqual(updater.count(boundary), 1, "review the public-main fixture boundary")
        # Actual main/admission/selection/deployment; only external tool work,
        # global links and reporting are fixture boundaries. These committed
        # candidate bytes are verified by the real bootstrap before exec.
        hooks = SELECTION_DISPATCH + r'''
sync_acfs_global_wrapper() { :; }
sync_acfs_global_command_links() { :; }
update_root_agents_md() { :; }
print_summary() {
    local lock_status=0
    /usr/bin/flock -n -E 75 "$TARGET_HOME" true || lock_status=$?
    printf '%s\0' "$BASHPID" "${_ACFS_UPDATE_LOCK_PID:-}" "$lock_status" \
        "$HOME" "$(update_target_user)" "$(update_target_home "$(update_target_user)")" \
        "$ACFS_STATE_FILE" "$ACFS_STATE_SELECTION_MODE" "$ACFS_STATE_INSTALL_MODE" \
        "${ACFS_STATE_SELECTED_MODULES[*]}" "$_ACFS_BOOTSTRAP_REF" \
        "${ACFS_UPDATE_ARGS[@]}" > "$TEST_ROOT/handoff-receipt"
}
'''
        candidate = updater.replace(boundary, "\n" + hooks + boundary)
        source_entry = self.repo / "scripts/lib/update.sh"
        source_entry.write_text(candidate)
        source_entry.chmod(0o755)
        source_reader = self.repo / "scripts/lib/state.sh"
        source_reader.write_bytes((self.snapshot / "scripts/lib/state.sh").read_bytes())
        source_reader.chmod(0o644)
        self.render_fixture_ledger(self.repo)
        self.commit(self.repo, "Actual-main bootstrap integration candidate")
        revision = self.git(self.repo, "rev-parse", "HEAD")
        # The initial actual-main process accepts exactly this fixture origin.
        # No exported authorization bypass or production trust rule is added.
        self.git(self.repo, "remote", "set-url", "origin", str(self.repo))
        if self_managed:
            source_reader.rename(self.base / "retained-candidate-state.sh")
            if library == "outdated":
                source_reader.write_text("_ACFS_STATE_SH_LOADED=1\n_state_acquire_lock() { :; }\n")
                source_reader.chmod(0o644)
        else:
            entry.write_text(candidate)
            entry.chmod(0o755)
        self.env.update({
            "TEST_ROOT": str(self.base), "TEST_BIN": str(self.home / ".local/bin"),
            "TEST_SOURCE": str(self.repo), "TEST_PRESENT": "", "TEST_FAILURE": "",
        })
        return entry, revision

    def main_process(self, entry, *arguments):
        body = r'''
source "$1"
shift
is_expected_acfs_origin_url() { [[ "$1" == "${TEST_ORIGIN:-$TEST_SOURCE}" ]]; }
_acfs_update_acquire_lock "$TARGET_HOME"
main "$@"
'''
        process = subprocess.Popen(
            ["/bin/bash", "--noprofile", "--norc", "-c", body,
             "bootstrap-main-fixture", str(entry), *arguments],
            env=self.env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, start_new_session=True,
        )
        self.processes.append(process)
        return process

    def complete_adjacent_scope_libraries(self):
        for relative in ("scripts/lib/state.sh", "scripts/lib/progress.sh",
                         "scripts/generated/manifest_index.sh"):
            destination = self.acfs / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((self.snapshot / relative).read_bytes())
            destination.chmod(0o644)

    def test_prepare_validates_full_revision_without_publishing_or_rewriting_checkpoint(self):
        previous = self.old_runtime("outdated")
        before = self.file_identity(previous)
        checkpoint = self.file_identity(self.state)
        generation = self.prepare()
        self.assertTrue(generation.is_dir())
        self.assertEqual(self.file_identity(previous), before)
        self.assertEqual(self.file_identity(self.state), checkpoint)
        self.current(code=3)
        for relative in self.inventory:
            self.assertEqual((generation / relative).read_bytes(),
                             (self.snapshot / relative).read_bytes(), relative)
        self.assertEqual(self.call("inspect", generation, self.home, self.user).stdout.splitlines(),
                         [str(self.repo), self.revision])
        self.assert_no_installer()

    def test_missing_and_outdated_legacy_libraries_recover_in_both_layouts(self):
        for layout in ("separate", "self-managed"):
            for library in ("missing", "outdated"):
                for mode in ("safe", "vibe"):
                    with self.subTest(layout=layout, library=library, mode=mode):
                        case = self.nested_case()
                        case.checkpoint(mode=mode)
                        previous = case.old_runtime(library, self_managed=layout == "self-managed")
                        before = case.file_identity(previous)
                        checkpoint = case.file_identity(case.state)
                        tracked_before = case.git(case.repo, "diff", "--binary")
                        generation = case.prepare()
                        case.activate(generation)
                        self.assertEqual(case.current(), generation)
                        self.assertEqual(case.file_identity(previous), before)
                        self.assertEqual(case.file_identity(case.state), checkpoint)
                        self.assertEqual(case.git(case.repo, "diff", "--binary"), tracked_before)
                        self.assertEqual((generation / "scripts/lib/state.sh").read_bytes(),
                                         (self.snapshot / "scripts/lib/state.sh").read_bytes())
                        result = subprocess.run(["/bin/bash", str(previous)], env=case.env,
                                                capture_output=True, text=True, timeout=5)
                        self.assertEqual((result.returncode, result.stdout),
                                         (0, "previous updater is usable\n"))
                        case.assert_no_installer()

    def test_default_legacy_checkpoint_without_identity_remains_legacy(self):
        self.old_runtime()
        self.checkpoint(legacy=True, mode="safe")
        before = self.file_identity(self.state)
        generation = self.prepare()
        self.activate(generation)
        self.assertEqual(self.current(), generation)
        self.assertEqual(self.file_identity(self.state), before)

    def test_custom_checkpoint_is_bound_without_touching_default_checkpoint(self):
        self.old_runtime()
        custom = self.checkpoint(path=self.home / "saved scope.json", mode="vibe")
        default_before, custom_before = self.file_identity(self.state), self.file_identity(custom)
        generation = self.prepare(state=custom)
        self.activate(generation, state=custom)
        self.assertEqual(self.file_identity(self.state), default_before)
        self.assertEqual(self.file_identity(custom), custom_before)
        self.assertEqual(self.current(), generation)

    def test_dirty_source_files_cannot_replace_immutable_candidate_bytes(self):
        self.old_runtime()
        untrusted = self.repo / "scripts/lib/state.sh"
        untrusted.write_text("printf 'dirty source executed' > \"$TEST_EVENTS\"\nexit 87\n")
        generation = self.prepare()
        self.assertEqual((generation / "scripts/lib/state.sh").read_bytes(),
                         (self.snapshot / "scripts/lib/state.sh").read_bytes())
        self.assertIn("dirty source executed", untrusted.read_text())
        self.assert_no_installer()

    def test_nonimmutable_or_ambiguous_revisions_are_refused(self):
        previous = self.old_runtime()
        before = self.file_identity(previous)
        for revision in ("HEAD", "main", "origin/main", self.revision[:12],
                         "--help", self.revision + ":scripts/lib/state.sh", "0" * 40):
            with self.subTest(revision=revision):
                result = self.prepare(revision=revision, code=None)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.file_identity(previous), before)
                self.current(code=3)
        self.assert_no_installer()

    def test_invalid_checkpoints_fail_before_activation(self):
        previous = self.old_runtime("outdated")
        before = self.file_identity(previous)
        valid = json.loads(self.state.read_text())
        cases = {
            "malformed": '{"module_selection":',
            "not-object": "[]\n",
            "duplicate-field": '{"schema_version":3,"schema_version":1}',
            "unsupported-checkpoint-schema": {**valid, "schema_version": 99},
            "boolean-checkpoint-schema": {**valid, "schema_version": True},
            "unsupported-selection": {**valid, "module_selection": {
                "schema_version": 2, "selected_modules": ["stack.ntm"]}},
            "empty": {**valid, "module_selection": {"schema_version": 1, "selected_modules": []}},
            "unknown": {**valid, "module_selection": {"schema_version": 1,
                                                    "selected_modules": ["stack.unknown"]}},
            "foreign-user": {**valid, "target_user": "another-user"},
            "foreign-home": {**valid, "target_home": str(self.base / "other-home")},
            "invalid-mode": {**valid, "mode": "unsafe"},
        }
        for name, document in cases.items():
            with self.subTest(checkpoint=name):
                self.state.write_text(document if isinstance(document, str) else json.dumps(document))
                state_before = self.file_identity(self.state)
                result = self.prepare(code=None)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.file_identity(self.state), state_before)
                self.assertEqual(self.file_identity(previous), before)
                self.current(code=3)
        self.assert_no_installer()

    def test_checkpoint_changes_between_prepare_and_activate_do_not_replace_previous_runtime(self):
        self.old_runtime()
        accepted = self.prepare()
        self.activate(accepted)
        candidate = self.prepare()
        pointer = self.acfs / ".update-runtime/current"
        before = self.file_identity(pointer)
        self.checkpoint(mode="vibe")
        state_before = self.file_identity(self.state)
        result = self.activate(candidate, code=None)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.file_identity(pointer), before)
        self.assertEqual(self.file_identity(self.state), state_before)
        self.assertEqual(self.current(), accepted)
        self.assert_no_installer()

    def test_activation_rejects_replaced_home_while_lock_still_holds_old_inode(self):
        self.old_runtime("outdated")
        previous = self.prepare()
        self.activate(previous)
        candidate = self.prepare()
        body = r'''
source "$UPDATE_TEST_LIBRARY"
_acfs_update_acquire_lock "$TARGET_HOME" || exit $?
printf 'home-locked\n'
IFS= read -r release
if update_bootstrap_files activate "$@"; then
    printf 'unexpected-activation\n'
else
    exit "$?"
fi
'''
        process = subprocess.Popen(
            ["/bin/bash", "--noprofile", "--norc", "-c", body,
             "bootstrap-home-swap-fixture", str(candidate), str(self.home),
             self.user, str(self.state)],
            env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, start_new_session=True,
        )
        self.processes.append(process)
        ready, _, _ = select.select([process.stdout], [], [], 5)
        self.assertTrue(ready, "fixture did not acquire the installation lock")
        self.assertEqual(process.stdout.readline(), b"home-locked\n")
        retained = self.base / "retained-locked-home"
        self.home.rename(retained)
        shutil.copytree(retained, self.home)
        self.assertNotEqual(retained.stat().st_ino, self.home.stat().st_ino)
        pointer = self.acfs / ".update-runtime/current"
        pointer_before = self.file_identity(pointer)
        checkpoint = self.file_identity(self.state)
        stdout, stderr = process.communicate(input=b"resume\n", timeout=15)
        self.assertNotEqual(process.returncode, 0, (stdout + stderr).decode())
        self.assertIn(b"held update lock", stderr)
        self.assertNotIn(b"unexpected-activation", stdout + stderr)
        self.assertEqual(self.file_identity(pointer), pointer_before)
        self.assertEqual(self.file_identity(self.state), checkpoint)
        self.assertEqual(self.current(), previous)
        self.assert_no_installer()

    def test_active_generation_refresh_uses_cache_without_rewriting_runtime(self):
        self.old_runtime()
        deployed_ledger = self.acfs / "checksums.yaml"
        deployed_ledger.write_bytes((self.snapshot / "checksums.yaml").read_bytes()
                                    + b"\n# separate deployed ledger\n")
        deployed_before = self.file_identity(deployed_ledger)
        generation = self.prepare()
        self.activate(generation)
        before = {path: self.file_identity(path) for path in generation.rglob("*") if path.is_file()}
        downloaded = self.base / "refreshed-checksums.yaml"
        downloaded.write_bytes((self.snapshot / "checksums.yaml").read_bytes()
                               + b"\n# authenticated refresh fixture\n")
        body = r'''
source "$UPDATE_TEST_LIBRARY"
update_bootstrap_use "$TEST_GENERATION" "$TARGET_HOME" "$TEST_USER" || exit $?
update_curl() {
    local output="" url="${*: -1}"
    while (( $# )); do
        if [[ "$1" == -o ]]; then output="$2"; break; fi
        shift
    done
    [[ "$url" == "https://api.github.com/repos/Dicklesworthstone/agentic_coding_flywheel_setup/contents/checksums.yaml?ref=main" ]] || return 91
    [[ -n "$output" ]] || return 92
    /bin/cp "$TEST_DOWNLOAD" "$output"
}
refresh_checksums true || exit $?
update_resolve_checksums_file
'''
        result = subprocess.run(
            ["/bin/bash", "--noprofile", "--norc", "-c", body],
            env=self.env | {"TEST_GENERATION": str(generation), "TEST_USER": self.user,
                            "TEST_DOWNLOAD": str(downloaded)},
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        cache = self.home / ".local/state/acfs/checksums.remote.yaml"
        self.assertEqual(result.stdout.strip(), str(cache))
        self.assertEqual(cache.read_bytes(), downloaded.read_bytes())
        self.assertEqual(self.file_identity(deployed_ledger), deployed_before)
        self.assertEqual({path: self.file_identity(path) for path in before}, before)
        self.assertEqual(self.git(self.repo, "status", "--porcelain"), "")
        self.assertEqual(self.current(), generation)
        self.assert_no_installer()

    def test_missing_custom_checkpoint_does_not_fall_back_to_default(self):
        self.old_runtime()
        before = self.file_identity(self.state)
        result = self.prepare(state=self.home / "absent custom.json", code=None)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.file_identity(self.state), before)
        self.current(code=3)

    def test_double_slash_checkpoint_cannot_hide_invalid_state_as_absent(self):
        previous = self.old_runtime("outdated")
        before = self.file_identity(previous)
        ambiguous = "//" + str(self.state).lstrip("/")
        for document in ('{"schema_version":99}',
                         '{"schema_version":3,"schema_version":1}'):
            with self.subTest(checkpoint=document):
                self.state.write_text(document)
                checkpoint = self.file_identity(self.state)
                result = self.prepare(state=ambiguous, code=None)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("unsafe absolute path", result.stderr)
                self.assertEqual(self.file_identity(self.state), checkpoint)
                self.assertEqual(self.file_identity(previous), before)
                self.current(code=3)
        self.assert_no_installer()

    def test_changed_generation_is_rejected_before_activation(self):
        self.old_runtime()
        previous = self.prepare()
        self.activate(previous)
        pointer = self.acfs / ".update-runtime/current"
        pointer_before = self.file_identity(pointer)
        for corruption in ("bytes", "symlink", "fifo", "writable", "writable-parent"):
            with self.subTest(corruption=corruption):
                generation = self.prepare()
                library = generation / "scripts/lib/state.sh"
                if corruption == "bytes":
                    library.write_text("printf 'unauthenticated execution' > \"$TEST_EVENTS\"\n")
                elif corruption in ("symlink", "fifo"):
                    library.rename(generation / "retained-state.sh")
                    if corruption == "symlink":
                        target = self.base / "untrusted-state.sh"
                        target.write_text("printf 'symlink executed' > \"$TEST_EVENTS\"\n")
                        library.symlink_to(target)
                    else:
                        os.mkfifo(library, 0o600)
                elif corruption == "writable-parent":
                    # ubs:ignore[py.security.file-permissions] - deliberately unsafe private fixture; activation must reject it.
                    library.parent.chmod(0o777)
                else:
                    # ubs:ignore[py.security.file-permissions] - deliberately unsafe private fixture; activation must reject it.
                    library.chmod(0o666)
                result = self.activate(generation, code=None)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.file_identity(pointer), pointer_before)
                self.assertEqual(self.current(), previous)
        self.assert_no_installer()

    def test_source_ledger_mismatch_is_not_repaired_or_published(self):
        previous = self.old_runtime()
        before = self.file_identity(previous)
        source = self.repo / "scripts/lib/state.sh"
        source.write_bytes(source.read_bytes() + b"\n# changed without a new ledger\n")
        self.commit(self.repo, "Invalid fixture with unchanged checksum ledger")
        result = self.prepare(revision=self.git(self.repo, "rev-parse", "HEAD"), code=None)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.file_identity(previous), before)
        self.current(code=3)
        self.assert_no_installer()

    def test_required_missing_library_is_not_an_optional_asset(self):
        previous = self.old_runtime()
        before = self.file_identity(previous)
        (self.repo / "scripts/lib/state.sh").rename(self.repo / "retained-state.sh")
        self.commit(self.repo, "Invalid fixture missing a required library")
        result = self.prepare(revision=self.git(self.repo, "rev-parse", "HEAD"), code=None)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.file_identity(previous), before)
        self.current(code=3)

    def test_bash_syntax_failure_preserves_previous_runtime(self):
        previous = self.old_runtime()
        before = self.file_identity(previous)
        (self.repo / "scripts/lib/state.sh").write_text("if broken syntax\n")
        self.render_fixture_ledger(self.repo)
        self.commit(self.repo, "Authenticated fixture with invalid Bash syntax")
        result = self.prepare(revision=self.git(self.repo, "rev-parse", "HEAD"), code=None)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.file_identity(previous), before)
        self.current(code=3)

    def test_pointer_cannot_escape_generation_directory(self):
        self.old_runtime()
        generation = self.prepare()
        pointer = self.acfs / ".update-runtime/current"
        for name in ("../outside", str(generation), ".", "generation-../../outside"):
            with self.subTest(generation=name):
                pointer.write_text(json.dumps({"schema": 1, "generation": name}))
                pointer.chmod(0o600)
                result = self.call("current", self.home, self.user, code=None)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_no_installer()

    def test_generation_is_bound_to_target_identity(self):
        self.old_runtime()
        generation = self.prepare()
        other_home = self.base / "other-home"
        other_home.mkdir(mode=0o700)
        for home, user in ((other_home, self.user), (self.home, "root" if self.user != "root" else "nobody")):
            with self.subTest(home=str(home), user=user):
                result = self.call("inspect", generation, home, user, code=None)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.current(code=3)

    def test_interrupted_candidate_probe_keeps_previous_generation_and_checkpoint(self):
        previous = self.old_runtime("outdated")
        before = self.file_identity(previous)
        state_before = self.file_identity(self.state)
        previous_generation = self.prepare()
        self.activate(previous_generation)
        pointer = self.acfs / ".update-runtime/current"
        pointer_before = self.file_identity(pointer)
        ready, hold = self.base / "probe-ready", self.base / "probe-hold"
        os.mkfifo(ready, 0o600)
        os.mkfifo(hold, 0o600)
        reader = self.repo / "scripts/lib/state.sh"
        # An authenticated fixture blocks during the actual fresh-shell scope
        # probe. No production hook, timing race or mock preparation is used.
        reader.write_text(reader.read_text() +
                          f"\nprintf '%s\\n' \"$BASHPID\" > {shlex.quote(str(ready))}\n"
                          f"IFS= read -r fixture_release < {shlex.quote(str(hold))}\n")
        self.render_fixture_ledger(self.repo)
        self.commit(self.repo, "Candidate with synchronized dependency probe")
        descriptor = os.open(ready, os.O_RDONLY | os.O_NONBLOCK)
        self.addCleanup(os.close, descriptor)
        process = subprocess.Popen(
            ["/bin/bash", "--noprofile", "--norc", "-c",
             'source "$UPDATE_TEST_LIBRARY"\nupdate_bootstrap_files "$@"\n',
             "bootstrap-interrupt-fixture", "prepare", str(self.repo),
             self.git(self.repo, "rev-parse", "HEAD"), str(self.home), self.user, str(self.state)],
            env=self.env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, start_new_session=True,
        )
        self.processes.append(process)
        readable, _, _ = select.select([descriptor], [], [], 20)
        self.assertTrue(readable, "candidate did not reach its dependency probe")
        self.assertTrue(os.read(descriptor, 128).strip().isdigit())
        os.killpg(process.pid, signal.SIGTERM)
        stdout, stderr = process.communicate(timeout=10)
        self.assertNotEqual(process.returncode, 0, (stdout + stderr).decode())
        self.assertEqual(self.file_identity(previous), before)
        self.assertEqual(self.file_identity(self.state), state_before)
        self.assertEqual(self.file_identity(pointer), pointer_before)
        self.assertEqual(self.current(), previous_generation)
        self.assert_no_installer()

    def test_killed_preparation_parent_releases_lock_while_probe_is_still_alive(self):
        self.old_runtime("outdated")
        previous = self.prepare()
        self.activate(previous)
        pointer = self.acfs / ".update-runtime/current"
        pointer_before = self.file_identity(pointer)
        checkpoint = self.file_identity(self.state)
        ready, hold = self.base / "parent-kill-ready", self.base / "parent-kill-hold"
        os.mkfifo(ready, 0o600)
        os.mkfifo(hold, 0o600)
        reader = self.repo / "scripts/lib/state.sh"
        reader.write_text(reader.read_text() +
                          f"\nprintf '%s\\n' \"$BASHPID\" > {shlex.quote(str(ready))}\n"
                          f"IFS= read -r fixture_release < {shlex.quote(str(hold))}\n")
        self.render_fixture_ledger(self.repo)
        self.commit(self.repo, "Candidate with a live orphanable scope probe")
        descriptor = os.open(ready, os.O_RDONLY | os.O_NONBLOCK)
        self.addCleanup(os.close, descriptor)
        body = ('source "$UPDATE_TEST_LIBRARY"\n'
                'ACFS_REPO_ROOT="$TEST_SOURCE"\n'
                'update_bootstrap_handoff "$TEST_REVISION"\n')
        process = subprocess.Popen(
            ["/bin/bash", "--noprofile", "--norc", "-c", body],
            env=self.env | {"TEST_SOURCE": str(self.repo),
                            "TEST_REVISION": self.git(self.repo, "rev-parse", "HEAD")},
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            start_new_session=True,
        )
        self.processes.append(process)
        try:
            readable, _, _ = select.select([descriptor], [], [], 20)
            self.assertTrue(readable, "candidate did not reach its dependency probe")
            probe_pid = int(os.read(descriptor, 128).strip())
            os.kill(process.pid, signal.SIGKILL)
            self.assertEqual(process.wait(timeout=5), -signal.SIGKILL)
            os.kill(probe_pid, 0)  # Keep the orphan alive until after the lock assertion.
            contender = subprocess.run(
                ["/usr/bin/flock", "-n", "-E", "75", str(self.home), "/bin/true"],
                env=self.env, capture_output=True, text=True, timeout=5,
            )
            self.assertEqual(contender.returncode, 0, contender.stdout + contender.stderr)
            os.kill(probe_pid, 0)
            self.assertEqual(self.file_identity(pointer), pointer_before)
            self.assertEqual(self.file_identity(self.state), checkpoint)
            self.assertEqual(self.current(), previous)
            self.assert_no_installer()
        finally:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
            process.communicate(timeout=5)


    @unittest.skipIf(os.geteuid() == 0, "actual entrypoint uses root's fixed /root home")
    def test_actual_main_core_repair_handles_stranded_layouts_without_installers(self):
        for layout in ("separate", "self-managed"):
            for library in ("missing", "outdated"):
                with self.subTest(layout=layout, library=library):
                    case = self.nested_case()
                    entry, revision = case.stranded_entry(
                        library, self_managed=layout == "self-managed")
                    checkpoint = case.file_identity(case.state)
                    tracked_before = case.git(case.repo, "diff", "--binary")
                    process = case.main_process(entry, "--yes", "--repair-runtime")
                    stdout, stderr = process.communicate(timeout=45)
                    self.assertEqual(process.returncode, 0, (stdout + stderr).decode())
                    self.assertIn(revision.encode(), stdout + stderr)
                    self.assertEqual(case.file_identity(case.state), checkpoint)
                    self.assertEqual(case.git(case.repo, "diff", "--binary"), tracked_before)
                    generation = case.current()
                    self.assertEqual((generation / "scripts/lib/state.sh").read_bytes(),
                                     (self.snapshot / "scripts/lib/state.sh").read_bytes())
                    case.assert_no_installer()
                    # Later canonical invocation, without the parent's origin
                    # fixture, must recognize the complete active generation.
                    check = subprocess.run(
                        ["/bin/bash", str(entry), "--check-runtime"], env=case.env,
                        capture_output=True, text=True, timeout=15,
                    )
                    self.assertEqual(check.returncode, 0, check.stdout + check.stderr)
                    self.assertIn(revision, check.stdout)
                    self.assertEqual(case.file_identity(case.state), checkpoint)

    @unittest.skipIf(os.geteuid() == 0, "actual entrypoint uses root's fixed /root home")
    def test_automatic_recovery_reexec_preserves_pid_lock_scope_mode_identity_and_arguments(self):
        arguments = ["--yes", "--quiet", "--stack-only", "--force", "--abort-on-failure"]
        for self_managed, mode in ((False, "safe"), (True, "vibe")):
            with self.subTest(self_managed=self_managed, mode=mode):
                case = self.nested_case()
                case.checkpoint(mode=mode)
                entry, revision = case.stranded_entry("outdated", self_managed=self_managed)
                checkpoint = case.file_identity(case.state)
                process = case.main_process(entry, *arguments)
                stdout, stderr = process.communicate(timeout=45)
                self.assertEqual(process.returncode, 0, (stdout + stderr).decode())
                receipt = (case.base / "handoff-receipt").read_bytes().split(b"\0")
                expected = [str(process.pid), str(process.pid), "75", str(case.home), self.user,
                            str(case.home), str(case.state), "scoped", mode,
                            "acfs.update stack.ntm", revision, *arguments]
                self.assertEqual(receipt, [value.encode() for value in expected] + [b""])
                self.assertEqual(case.file_identity(case.state), checkpoint)
                installer_events = [line for line in case.events.read_text().splitlines()
                                    if line.startswith("installer:")]
                self.assertEqual(len(installer_events), 1, installer_events)
                self.assertEqual(installer_events[0].split()[0], "installer:ntm", installer_events)

    @unittest.skipIf(os.geteuid() == 0, "actual entrypoint uses root's fixed /root home")
    def test_public_coherence_check_is_read_only_without_reader_and_while_locked(self):
        entry, _ = self.stranded_entry()
        checkpoint = self.file_identity(self.state)
        for command in (entry, self.repo / "scripts/lib/update.sh"):
            with self.subTest(entry=str(command)):
                absent = subprocess.run(["/bin/bash", str(command), "--check-runtime"], env=self.env,
                                        capture_output=True, text=True, timeout=15)
                self.assertNotEqual(absent.returncode, 0, absent.stdout + absent.stderr)
                self.assertIn("state.sh", absent.stderr)
                self.assertFalse((self.acfs / ".update-runtime").exists())
                self.assertEqual(self.file_identity(self.state), checkpoint)
        process = self.main_process(entry, "--yes", "--repair-runtime")
        stdout, stderr = process.communicate(timeout=45)
        self.assertEqual(process.returncode, 0, (stdout + stderr).decode())
        pointer = self.acfs / ".update-runtime/current"
        pointer_before = self.file_identity(pointer)
        home_fd = os.open(self.home, os.O_RDONLY | os.O_DIRECTORY)
        try:
            fcntl.flock(home_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            checked = subprocess.run(["/bin/bash", str(entry), "--check-runtime"], env=self.env,
                                     capture_output=True, text=True, timeout=15)
            self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
            self.assertIn("runtime verified", checked.stdout)
        finally:
            os.close(home_fd)
        self.assertEqual(self.file_identity(pointer), pointer_before)
        self.assertEqual(self.file_identity(self.state), checkpoint)
        self.assert_no_installer()

    @unittest.skipIf(os.geteuid() == 0, "actual entrypoint uses root's fixed /root home")
    def test_unsafe_installed_library_is_never_sourced_by_diagnostics(self):
        entry, _ = self.stranded_entry()
        library = entry.with_name("state.sh")
        malicious = self.base / "untrusted-state.sh"
        malicious.write_text("printf 'untrusted library executed\\n' > \"$TEST_EVENTS\"\n")
        library.symlink_to(malicious)
        result = subprocess.run(["/bin/bash", str(entry), "--check-runtime"], env=self.env,
                                capture_output=True, text=True, timeout=15)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.acfs / ".update-runtime").exists())
        self.assert_no_installer()


    def test_entry_publication_replaces_only_updater_after_complete_activation(self):
        entry = self.old_runtime("outdated")
        reader = entry.with_name("state.sh")
        before = self.file_identity(entry)
        reader_before = self.file_identity(reader)
        checkpoint = self.file_identity(self.state)
        generation = self.prepare()
        self.call("entry-check", generation, self.home, self.user)
        self.assertEqual(self.file_identity(entry), before)
        premature = self.call("entry", generation, self.home, self.user, code=None)
        self.assertNotEqual(premature.returncode, 0, premature.stdout + premature.stderr)
        self.assertEqual(self.file_identity(entry), before)
        self.activate(generation)
        self.call("entry", generation, self.home, self.user)
        self.assertEqual(entry.read_bytes(), (generation / "scripts/lib/update.sh").read_bytes())
        self.assertEqual(entry.stat().st_mode & 0o777, 0o755)
        self.assertNotEqual(entry.stat().st_ino, before[1])
        self.assertEqual(self.file_identity(reader), reader_before)
        self.assertEqual(self.file_identity(self.state), checkpoint)
        self.assert_no_installer()

    def test_unsafe_entrypoint_preflight_preserves_previous_generation(self):
        entry = self.old_runtime()
        previous = self.prepare()
        self.activate(previous)
        candidate = self.prepare()
        pointer = self.acfs / ".update-runtime/current"
        before = self.file_identity(pointer)
        retained = self.base / "retained-updater.sh"
        entry.rename(retained)
        entry.symlink_to(retained)
        result = self.call("entry-check", candidate, self.home, self.user, code=None)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(entry.is_symlink())
        self.assertEqual(self.file_identity(pointer), before)
        self.assertEqual(self.current(), previous)
        self.assert_no_installer()

    @unittest.skipIf(os.geteuid() == 0, "actual entrypoint uses root's fixed /root home")
    def test_bootstrap_exec_reports_failed_launch_and_preserves_prepared_runtime(self):
        # The old per-file exec helper trusted the installed shebang. The
        # generation handoff resolves system Bash instead; exercise failure at
        # that actual launch boundary without bypassing preparation or admission.
        entry = self.old_runtime("outdated")
        entry_before = self.file_identity(entry)
        checkpoint = self.file_identity(self.state)
        generation = self.prepare()
        self.activate(generation)
        pointer = self.acfs / ".update-runtime/current"
        pointer_before = self.file_identity(pointer)
        body = r'''
source "$UPDATE_TEST_LIBRARY"
shopt -s execfail
update_system_binary_path() {
    if [[ "$1" == bash ]]; then
        printf '%s\n' "$TEST_MISSING_BASH"
    else
        command -v "$1"
    fi
}
if update_bootstrap_exec "$@"; then
    printf 'unexpected-continuation\n'
else
    exit "$?"
fi
'''
        result = subprocess.run(
            ["/bin/bash", "--noprofile", "--norc", "-c", body,
             "bootstrap-failed-exec-fixture", str(generation), str(self.home), self.user],
            env=self.env | {"TEST_MISSING_BASH": str(self.base / "missing-system-bash")},
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 127, result.stdout + result.stderr)
        self.assertNotIn("unexpected-continuation", result.stdout + result.stderr)
        self.assertIn("missing-system-bash", result.stderr)
        self.assertEqual(self.file_identity(entry), entry_before)
        self.assertEqual(self.file_identity(self.state), checkpoint)
        self.assertEqual(self.file_identity(pointer), pointer_before)
        self.assertEqual(self.current(), generation)
        launch = subprocess.run(["/bin/bash", str(generation / "scripts/lib/update.sh"), "--help"],
                                env=self.env, capture_output=True, text=True, timeout=15)
        self.assertEqual(launch.returncode, 0, launch.stdout + launch.stderr)
        self.assert_no_installer()

    def test_new_bootstrap_exec_preserves_arbitrary_arguments_and_lock(self):
        self.old_runtime()
        updater = self.source.read_text()
        boundary = '\nif [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then\n    main "$@"\nfi'
        self.assertEqual(updater.count(boundary), 1)
        # An authenticated fixture operation accepts arbitrary argv before
        # main's option parser. Production exec/admission/state loading remain
        # real; unsupported strings are not invented public updater options.
        dispatch = r'''
if [[ "${BASH_SOURCE[0]}" == "${0}" && "${1:-}" == --fixture-handoff ]]; then
    update_bootstrap_admit "$@" || exit $?
    update_load_module_selection || exit $?
    lock_status=0
    /usr/bin/flock -n -E 75 "$TARGET_HOME" true || lock_status=$?
    printf '%s\0' "$BASHPID" "$_ACFS_UPDATE_LOCK_PID" "$lock_status" \
        "$ACFS_SELF_UPDATE_DONE" "$ACFS_STATE_SELECTION_MODE" "$ACFS_STATE_INSTALL_MODE" \
        "${ACFS_STATE_SELECTED_MODULES[*]}" "$@" > "$HOME/raw-handoff-receipt"
    exit 0
fi
'''
        (self.repo / "scripts/lib/update.sh").write_text(updater.replace(boundary, dispatch + boundary))
        self.render_fixture_ledger(self.repo)
        self.commit(self.repo, "Candidate for exact argv and lock handoff")
        generation = self.prepare(revision=self.git(self.repo, "rev-parse", "HEAD"))
        self.activate(generation)
        arguments = ["--fixture-handoff", "argument with spaces", "", "line\nbreak",
                     "--literal=$(unused)", "'quoted'", "--no-self-update"]
        body = 'source "$UPDATE_TEST_LIBRARY"\nupdate_bootstrap_exec "$@"\n'
        process = subprocess.Popen(
            ["/bin/bash", "--noprofile", "--norc", "-c", body, "bootstrap-exec-fixture",
             str(generation), str(self.home), self.user, *arguments],
            env=self.env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, start_new_session=True,
        )
        self.processes.append(process)
        stdout, stderr = process.communicate(timeout=30)
        self.assertEqual(process.returncode, 0, (stdout + stderr).decode())
        expected = [str(process.pid), str(process.pid), "75", "true", "scoped", "safe",
                    "acfs.update stack.ntm", *arguments]
        self.assertEqual((self.home / "raw-handoff-receipt").read_bytes().split(b"\0"),
                         [value.encode() for value in expected] + [b""])
        self.assert_no_installer()

    @unittest.skipIf(os.geteuid() == 0, "actual entrypoint uses root's fixed /root home")
    def test_healthy_current_and_fast_forward_handoff_uses_complete_candidate(self):
        arguments = ["--yes", "--quiet", "--stack-only", "--force"]
        for fast_forward in (False, True):
            with self.subTest(fast_forward=fast_forward):
                case = self.nested_case()
                entry, revision = case.stranded_entry()
                case.complete_adjacent_scope_libraries()
                upstream = case.repo
                if fast_forward:
                    checkout = case.base / "previous-checkout"
                    case.git(case.base, "clone", "--quiet", "--no-hardlinks",
                             str(self.snapshot), str(checkout))
                    case.git(checkout, "remote", "set-url", "origin", str(upstream))
                    case.repo = checkout
                    case.env.update(ACFS_REPO_ROOT=str(checkout), TEST_SOURCE=str(checkout),
                                    TEST_ORIGIN=str(upstream))
                    self.assertEqual(case.git(checkout, "rev-parse", "HEAD"), self.revision)
                checkpoint = case.file_identity(case.state)
                process = case.main_process(entry, *arguments)
                stdout, stderr = process.communicate(timeout=45)
                self.assertEqual(process.returncode, 0, (stdout + stderr).decode())
                self.assertEqual(case.git(case.repo, "rev-parse", "HEAD"), revision)
                self.assertEqual(case.git(case.repo, "status", "--porcelain"), "")
                receipt = (case.base / "handoff-receipt").read_bytes().split(b"\0")
                self.assertEqual(receipt[:3], [str(process.pid).encode(), str(process.pid).encode(), b"75"])
                self.assertEqual(receipt[10], revision.encode())
                self.assertEqual(receipt[11:], [argument.encode() for argument in arguments] + [b""])
                self.assertEqual(case.file_identity(case.state), checkpoint)
                generation = case.current()
                self.assertEqual((generation / "scripts/lib/state.sh").read_bytes(),
                                 (self.snapshot / "scripts/lib/state.sh").read_bytes())
                # A later --no-self-update invocation uses the active runtime
                # without preparing another generation or entering an exec loop.
                pointer = case.acfs / ".update-runtime/current"
                pointer_before = case.file_identity(pointer)
                generations = sorted(pointer.parent.glob("generation-*"))
                later = subprocess.run(
                    ["/bin/bash", str(entry), *arguments, "--no-self-update"],
                    env=case.env, capture_output=True, text=True, timeout=20,
                )
                self.assertEqual(later.returncode, 0, later.stdout + later.stderr)
                self.assertEqual(case.file_identity(pointer), pointer_before)
                self.assertEqual(sorted(pointer.parent.glob("generation-*")), generations)

    @unittest.skipIf(os.geteuid() == 0, "actual entrypoint uses root's fixed /root home")
    def test_repair_dry_run_preserves_runtime_checkout_and_checkpoint(self):
        entry, _ = self.stranded_entry("outdated")
        entry_before = self.file_identity(entry)
        checkpoint = self.file_identity(self.state)
        head = self.git(self.repo, "rev-parse", "HEAD")
        process = self.main_process(entry, "--yes", "--repair-runtime", "--dry-run")
        stdout, stderr = process.communicate(timeout=15)
        self.assertEqual(process.returncode, 0, (stdout + stderr).decode())
        self.assertEqual(self.file_identity(entry), entry_before)
        self.assertEqual(self.file_identity(self.state), checkpoint)
        self.assertEqual(self.git(self.repo, "rev-parse", "HEAD"), head)
        self.assertFalse((self.acfs / ".update-runtime").exists())
        self.assert_no_installer()

    @unittest.skipIf(os.geteuid() == 0, "actual entrypoint uses root's fixed /root home")
    def test_ordinary_startup_rejects_unsupported_checkpoint_before_tool_work(self):
        entry, _ = self.stranded_entry()
        self.complete_adjacent_scope_libraries()
        state = json.loads(self.state.read_text())
        state["schema_version"] = 99
        self.state.write_text(json.dumps(state))
        checkpoint = self.file_identity(self.state)
        process = self.main_process(entry, "--yes", "--no-self-update", "--stack-only", "--force")
        stdout, stderr = process.communicate(timeout=15)
        self.assertNotEqual(process.returncode, 0, (stdout + stderr).decode())
        self.assertEqual(self.file_identity(self.state), checkpoint)
        self.assertFalse((self.acfs / ".update-runtime").exists())
        self.assert_no_installer()


if __name__ == "__main__":
    unittest.main()
