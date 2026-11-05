#!/usr/bin/env python3
"""Exercise installer attachment and early apt under a real controlling terminal.

Only the shipped function bodies are loaded. Package, key and repository writes
are inert fixtures; flock, tail, the PTY and GNU timeout run for real. Fixtures
are retained, and every test-owned process is reaped.
"""
from __future__ import annotations

import errno
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import shlex
import shutil
import signal
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(os.environ.get("ACFS_INSTALLER_TEST_SOURCE", ROOT / "install.sh"))


def definition(name: str) -> str:
    match = re.search(r"^" + re.escape(name) + r"\(\) \{\n.*?^\}",
                      SOURCE.read_text(), re.M | re.S)
    if not match:
        raise ValueError(f"Missing production function: {name}")
    return match[0]


class InstallerTerminalTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="acfs-terminal-test-"))
        self.child = None
        self.terminal = None
        self.output = b""
        self.addCleanup(self.stop_child)

    def start(self, body: str):
        pid, terminal = pty.fork()
        if pid == 0:
            os.chdir(self.root)
            os.execv("/bin/bash", ["bash", "--noprofile", "--norc", "-c",
                                   "set -euo pipefail\n" + body])
        self.child, self.terminal = pid, terminal

    def drain(self, duration=0.1):
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.terminal], [], [],
                                         max(0, deadline - time.monotonic()))
            if not ready:
                break
            try:
                chunk = os.read(self.terminal, 65536)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                break
            if not chunk:
                break
            self.output += chunk

    def finish(self, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.drain()
            pid, status = os.waitpid(self.child, os.WNOHANG)
            if pid:
                self.child = None
                self.drain()
                return os.waitstatus_to_exitcode(status), self.output.decode(errors="replace")
        self.fail("Installer terminal function did not finish:\n" + self.output.decode(errors="replace"))

    def stop_child(self):
        if self.child is not None:
            try:
                os.killpg(self.child, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(self.child, 0)
            self.child = None
        if self.terminal is not None:
            os.close(self.terminal)
            self.terminal = None

    def attach(self, lock_path, *, parent_descriptor=True):
        log_dir = self.root / "logs"
        log_dir.mkdir()
        (log_dir / "install-current.log").write_text("installer progress\n")
        parent_fd = self.root / "parent-fd"
        self.start("\n".join([
            definition("acfs_latest_install_log"),
            definition("acfs_attach_to_running_install"),
            'log_info() { printf "%s\\n" "$*"; }',
            f"exec 197>{shlex.quote(str(parent_fd))}" if parent_descriptor else "exec 197>&-",
            f"acfs_attach_to_running_install {shlex.quote(str(lock_path))} {shlex.quote(str(log_dir))}",
            'printf "parent descriptor preserved\\n" >&197' if parent_descriptor else ":",
            'printf "WATCHER_RETURNED\\n"',
        ]))
        return parent_fd

    def test_attach_finishes_after_real_lock_release_without_taking_parent_fd(self):
        lock_path = self.root / "install.lock"
        lock_path.write_text("lock evidence\n")
        with lock_path.open("r+") as held:
            fcntl.flock(held, fcntl.LOCK_EX)
            parent_fd = self.attach(lock_path)
            self.drain(0.3)
            self.assertIn(b"Following live install output", self.output)
            self.assertNotIn(b"WATCHER_RETURNED", self.output)
            observed = os.waitpid(self.child, os.WNOHANG)
            if observed[0]:
                self.child = None
            self.assertEqual(observed, (0, 0))
            fcntl.flock(held, fcntl.LOCK_UN)
            status, output = self.finish()
        self.assertEqual(status, 0, output)
        self.assertIn("The running installer has finished", output)
        self.assertIn("WATCHER_RETURNED", output)
        self.assertEqual(lock_path.read_text(), "lock evidence\n")
        self.assertEqual(parent_fd.read_text(), "parent descriptor preserved\n")

    def test_attach_detects_lock_already_released_before_first_poll(self):
        lock_path = self.root / "install.lock"
        lock_path.touch()
        self.attach(lock_path, parent_descriptor=False)
        status, output = self.finish(timeout=3)
        self.assertEqual(status, 0, output)
        self.assertIn("The running installer has finished", output)

    def gum(self, *, failure="", dry_run=False, sudo_identity_fixture=False, setsid_available=True):
        function_source = definition("install_gum_early")
        if sudo_identity_fixture and os.geteuid() == 0:
            # Root-only user namespaces cannot switch to another UID. Exercise
            # sudo command ordering with a test-only identity substitution; this
            # fixture does not establish a real privilege transition.
            guard = "if [[ $EUID -ne 0 ]]; then"
            self.assertEqual(function_source.count(guard), 1)
            function_source = function_source.replace(guard, "if [[ 1000 -ne 0 ]]; then")
        timeout_bin = shutil.which("timeout")
        self.assertIsNotNone(timeout_bin, "GNU timeout is required")
        setsid_bin = shutil.which("setsid")
        self.assertIsNotNone(setsid_bin, "setsid is required")
        env_bin = shutil.which("env")
        self.assertIsNotNone(env_bin, "env is required")
        apt = self.root / "apt-fixture"
        events = self.root / "apt-events"
        timeouts = self.root / "timeout-args"
        timeout_wrapper = self.root / "timeout-fixture"
        timeout_wrapper.write_text("#!/usr/bin/env bash\n" + r'''
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_TIMEOUT_ARGS"
options=()
if [[ "$1" == --foreground ]]; then
    options+=("$1")
    shift
fi
[[ "$1" == 300 ]] || exit 98
shift
# Real timeout and process groups, with a bounded test-only duration.
exec "$TEST_REAL_TIMEOUT_BIN" "${options[@]}" --kill-after=0.2 0.4 "$@"
''')
        timeout_wrapper.chmod(0o755)
        apt.write_text("#!/usr/bin/python3\n" + r'''
import errno, os, signal, subprocess, sys, termios, time
from pathlib import Path
events = Path(os.environ["TEST_APT_EVENTS"])
operation = "install" if "install" in sys.argv else "update"
with events.open("a") as stream:
    stream.write(operation + ":started\n")
signal.signal(signal.SIGTTOU, signal.SIG_DFL)
try:
    fd = os.open("/dev/tty", os.O_RDWR)
except OSError as error:
    if error.errno != errno.ENXIO:
        raise
    terminal = "detached"
else:
    # This stops background process groups even when TOSTOP is disabled.
    termios.tcsetattr(fd, termios.TCSANOW, termios.tcgetattr(fd))
    os.close(fd)
    terminal = "terminal-ok"
with events.open("a") as stream:
    stream.write(operation + ":" + terminal + "\n")
if os.environ.get("DEBIAN_FRONTEND") != "noninteractive":
    sys.exit(43)
if os.fstat(0).st_rdev != os.stat("/dev/null").st_rdev:
    sys.exit(44)
if os.environ["TEST_APT_FAILURE"] == operation:
    sys.exit(42)
if os.environ["TEST_APT_FAILURE"] == "timeout":
    time.sleep(10)
if os.environ["TEST_APT_FAILURE"] == "descendant" and operation == "install":
    # A helper keeps apt's captured stdout open. Foreground-only timeout kills
    # apt but leaves this child running until it exits two seconds later.
    child = """
import signal, sys, time
from pathlib import Path
events = Path(sys.argv[1])
def terminated(signum, frame):
    with events.open('a') as stream:
        stream.write('terminated\\n')
    sys.exit(0)
signal.signal(signal.SIGTERM, terminated)
events.write_text('started\\n')
time.sleep(2)
with events.open('a') as stream:
    stream.write('completed\\n')
"""
    subprocess.run([sys.executable, "-c", child, os.environ["TEST_APT_CHILD_EVENTS"]], check=False)
''')
        apt.chmod(0o755)
        self.start("\n".join([
            function_source,
            f"export TEST_APT_EVENTS={shlex.quote(str(events))}",
            f"export TEST_APT_CHILD_EVENTS={shlex.quote(str(self.root / 'apt-child-events'))}",
            f"export TEST_APT_FAILURE={shlex.quote(failure)}",
            f"export TEST_TIMEOUT_ARGS={shlex.quote(str(timeouts))}",
            f"export TEST_REAL_TIMEOUT_BIN={shlex.quote(timeout_bin)}",
            f"TEST_TIMEOUT_WRAPPER={shlex.quote(str(timeout_wrapper))}",
            f"TEST_APT_BIN={shlex.quote(str(apt))}",
            f"TEST_SETSID_BIN={shlex.quote(setsid_bin)}",
            f"TEST_ENV_BIN={shlex.quote(env_bin)}",
            f"TEST_SUDO_EVENTS={shlex.quote(str(self.root / 'sudo-events'))}",
            f"TEST_SETSID_AVAILABLE={'true' if setsid_available else 'false'}",
            f"DRY_RUN={'true' if dry_run else 'false'}",
            r'''
ACFS_DISTRO_FAMILY=ubuntu
HAS_GUM=false
ACFS_EARLY_CURL_ARGS=()
_acfs_os_release_field() { printf '24.04\n'; }
fixture_curl() { printf 'fixture-key\n'; }
fixture_gpg() { cat >/dev/null; }
fixture_mkdir() { :; }
fixture_tee() { cat >/dev/null; }
fixture_sudo() {
    # Authentication happens before detaching, including when stdin is null.
    /usr/bin/python3 -c 'import os, sys; fd = os.open("/dev/tty", os.O_RDWR); sys.exit(os.tcgetpgrp(fd) != os.getpgrp())' || return 97
    printf 'foreground-terminal\n' >> "$TEST_SUDO_EVENTS"
    # Model sudo's environment reset. The trusted env invocation must restore
    # DEBIAN_FRONTEND for apt after elevation.
    local DEBIAN_FRONTEND
    unset DEBIAN_FRONTEND
    "$@"
}
acfs_early_sudo_binary_path() { printf 'fixture_sudo\n'; }
acfs_early_system_binary_path() {
    case "$1" in
        gum) return 1 ;;
        apt-get) printf '%s\n' "$TEST_APT_BIN" ;;
        timeout) printf '%s\n' "$TEST_TIMEOUT_WRAPPER" ;;
        setsid)
            [[ "$TEST_SETSID_AVAILABLE" == true ]] || return 1
            printf '%s\n' "$TEST_SETSID_BIN"
            ;;
        env) printf '%s\n' "$TEST_ENV_BIN" ;;
        *) printf 'fixture_%s\n' "$1" ;;
    esac
}
install_gum_early
printf 'HAS_GUM=%s\n' "$HAS_GUM"
''',
        ]))
        status, output = self.finish()
        self.assertEqual(status, 0, output)
        return output, events.read_text() if events.exists() else "", timeouts

    def test_early_gum_apt_detaches_from_controlling_terminal(self):
        output, events, timeouts = self.gum()
        self.assertIn("HAS_GUM=true", output)
        self.assertEqual(events, "update:started\nupdate:detached\ninstall:started\ninstall:detached\n")
        calls = timeouts.read_text().splitlines()
        self.assertEqual(len(calls), 2)
        self.assertTrue(all(call.startswith("300 ") for call in calls), calls)

    def test_early_gum_simulated_nonroot_sudo_keeps_terminal_and_restores_environment(self):
        output, events, _ = self.gum(sudo_identity_fixture=True)
        self.assertIn("HAS_GUM=true", output)
        self.assertIn("install:detached", events)
        sudo_events = (self.root / "sudo-events").read_text().splitlines()
        self.assertEqual(sudo_events, ["foreground-terminal"] * 5)

    def test_early_gum_update_failure_stops_before_install(self):
        output, events, _ = self.gum(failure="update")
        self.assertIn("HAS_GUM=false", output)
        self.assertNotIn("install:started", events)

    def test_early_gum_install_failure_keeps_optional_fallback(self):
        output, events, _ = self.gum(failure="install")
        self.assertIn("HAS_GUM=false", output)
        self.assertIn("install:detached", events)

    def test_early_gum_timeout_still_bounds_hanging_package_manager(self):
        output, events, _ = self.gum(failure="timeout")
        self.assertIn("HAS_GUM=false", output)
        self.assertIn("update:detached", events)
        self.assertNotIn("install:started", events)

    def test_early_gum_timeout_reaches_child_retaining_captured_output(self):
        output, events, _ = self.gum(failure="descendant")
        self.assertIn("HAS_GUM=false", output)
        self.assertIn("install:detached", events)
        self.assertEqual((self.root / "apt-child-events").read_text(), "started\nterminated\n")

    def test_early_gum_missing_session_tool_keeps_optional_fallback(self):
        output, events, timeouts = self.gum(setsid_available=False)
        self.assertIn("HAS_GUM=false", output)
        self.assertEqual(events, "")
        self.assertFalse(timeouts.exists())

    def test_early_gum_dry_run_never_calls_package_manager(self):
        output, events, timeouts = self.gum(dry_run=True)
        self.assertIn("HAS_GUM=false", output)
        self.assertEqual(events, "")
        self.assertFalse(timeouts.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
