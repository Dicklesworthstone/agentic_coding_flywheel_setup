#!/usr/bin/env python3
"""Offline integration regressions for atomic runtime deployment (issue #488).

Run: python3 -B -m unittest discover -s tests/unit -p test_update_deployment.py -v
The real sync_acfs_deployed() runs against disposable source/runtime trees. No
updater main(), package manager, network request, or service is invoked.
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


class AtomicDeploymentTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="acfs-deploy-test-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.repo = self.base / "source"
        self.acfs = self.base / "runtime"
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

    def sync(self, setup="", *, success=True, **env):
        process = self.start(["/bin/bash", "--noprofile", "--norc", "-c",
                              COMMON + setup + SYNC], **env)
        stdout, stderr = process.communicate(timeout=15)
        output = (stdout + stderr).decode()
        if success:
            self.assertEqual(process.returncode, 0, output)
        else:
            self.assertNotEqual(process.returncode, 0, output)
        return output

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
