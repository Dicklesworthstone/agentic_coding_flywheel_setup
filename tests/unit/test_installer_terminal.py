#!/usr/bin/env python3
"""Exercise installer attachment and early apt under a real controlling terminal.

Only the shipped function bodies are loaded. Package, key and repository writes
are inert fixtures; flock, tail, the PTY and GNU timeout run for real. Fixtures
are retained, and every test-owned process is reaped.
"""
from __future__ import annotations

import errno
import fcntl
import json
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


def initializer(name: str) -> str:
    match = re.search(r"^" + re.escape(name) + r"=.*$", SOURCE.read_text(), re.M)
    if not match:
        raise ValueError(f"Missing production initializer: {name}")
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
            # Wait for actual startup before measuring contention. A loaded
            # runner may take longer than a fixed 300 ms just to start Bash.
            deadline = time.monotonic() + 3
            while b"Following live install output" not in self.output and time.monotonic() < deadline:
                self.drain()
            self.assertIn(b"Following live install output", self.output)
            self.drain(0.3)
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

    def hold_install_lock(self, lock_path):
        import subprocess

        holder = subprocess.Popen([
            "/bin/bash", "-c",
            'exec 199>>"$1"; flock -x 199; printf "locked\\n"; exec sleep 30',
            "lock-holder", str(lock_path),
        ], stdout=subprocess.PIPE, start_new_session=True)

        def stop_holder():
            if holder.poll() is None:
                holder.terminate()
            holder.wait(timeout=3)
            holder.stdout.close()

        self.addCleanup(stop_holder)
        self.assertTrue(select.select([holder.stdout], [], [], 3)[0], "lock holder did not start")
        self.assertEqual(holder.stdout.readline(), b"locked\n")
        return holder

    def test_attach_finishes_after_interrupted_installer_releases_lock(self):
        lock_path = self.root / "install.lock"
        lock_path.write_text("lock evidence\n")
        holder = self.hold_install_lock(lock_path)
        self.attach(lock_path)
        self.drain(0.3)
        self.assertNotIn(b"WATCHER_RETURNED", self.output)
        with lock_path.open("r+") as contender:
            with self.assertRaises(BlockingIOError):
                fcntl.flock(contender, fcntl.LOCK_EX | fcntl.LOCK_NB)
        holder.terminate()
        self.assertEqual(holder.wait(timeout=3), -signal.SIGTERM)
        status, output = self.finish()
        self.assertEqual(status, 0, output)
        self.assertIn("The running installer has finished", output)
        self.assertEqual(lock_path.read_text(), "lock evidence\n")
        with lock_path.open("r+") as contender:
            fcntl.flock(contender, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_attach_noninteractive_prints_recovery_command_without_following(self):
        import subprocess

        lock_path = self.root / "install.lock"
        holder = self.hold_install_lock(lock_path)
        log_dir = self.root / "logs"
        log_dir.mkdir()
        (log_dir / "install-current.log").write_text("installer progress\n")
        script = "\n".join([
            definition("acfs_latest_install_log"),
            definition("acfs_attach_to_running_install"),
            'log_info() { printf "%s\\n" "$*"; }',
            'tail() { printf "UNEXPECTED_TAIL\\n"; return 97; }',
            f"acfs_attach_to_running_install {shlex.quote(str(lock_path))} {shlex.quote(str(log_dir))}",
        ])
        result = subprocess.run(["/bin/bash", "-c", script], capture_output=True, text=True, timeout=3)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(f"tail -f {log_dir}/install-current.log", result.stdout)
        self.assertNotIn("UNEXPECTED_TAIL", result.stdout)
        self.assertIsNone(holder.poll())

    def attach_signal_probe(self, watched_signal):
        import subprocess

        lock_path = self.root / "install.lock"
        holder = self.hold_install_lock(lock_path)
        log_dir = self.root / "logs"
        log_dir.mkdir()
        (log_dir / "install-current.log").write_text("installer progress\n")
        tail_pid_path = self.root / "tail-pid"
        script = "\n".join([
            definition("acfs_latest_install_log"),
            definition("acfs_attach_to_running_install"),
            definition("_acfs_signal_handler"),
            definition("_acfs_bootstrap_signal_exit"),
            'log_info() { printf "%s\\n" "$*"; }',
            f'tail() {{ printf "%s\\n" "$BASHPID" > {shlex.quote(str(tail_pid_path))}; exec /usr/bin/tail "$@"; }}',
            "trap '_acfs_signal_handler INT' INT",
            "trap '_acfs_signal_handler TERM' TERM",
            "trap '_acfs_signal_handler HUP' HUP",
            f"acfs_attach_to_running_install {shlex.quote(str(lock_path))} {shlex.quote(str(log_dir))}",
        ])
        pid, terminal = pty.fork()
        if pid == 0:
            # A shell in SSH/tmux normally outlives its installer. Keep this
            # PTY session leader alive after the watcher exits so its SIGHUP
            # cannot conceal an orphan tail. Become a subreaper to collect
            # that tail even when exercising the unfixed implementation.
            import ctypes
            ctypes.CDLL(None).prctl(36, 1, 0, 0, 0)
            worker = subprocess.Popen(["/bin/bash", "-c", script])
            tail_pid = None
            exit_code = 1
            try:
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    if tail_pid_path.exists() and tail_pid_path.read_text().strip():
                        tail_pid = int(tail_pid_path.read_text())
                        break
                    time.sleep(0.02)
                if tail_pid is None:
                    raise RuntimeError("tail did not start")
                worker.send_signal(watched_signal)
                status = worker.wait(timeout=4)
                # GNU tail --pid checks at its ordinary one-second interval.
                deadline = time.monotonic() + 2
                tail_exited = False
                while time.monotonic() < deadline:
                    try:
                        reaped, _ = os.waitpid(tail_pid, os.WNOHANG)
                    except ChildProcessError:
                        # A watcher that reaps its own tail is also correct.
                        try:
                            os.kill(tail_pid, 0)
                        except ProcessLookupError:
                            tail_exited = True
                            break
                    else:
                        if reaped:
                            tail_exited = True
                            break
                    time.sleep(0.02)
                print(f"WATCHER_SIGNAL_STATUS={status}", flush=True)
                print(f"TAIL_EXITED={tail_exited}", flush=True)
                exit_code = 0
            finally:
                if worker.poll() is None:
                    worker.kill()
                    worker.wait()
                if tail_pid is not None:
                    try:
                        os.kill(tail_pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    try:
                        os.waitpid(tail_pid, 0)
                    except ChildProcessError:
                        pass
                os._exit(exit_code)
        self.child, self.terminal = pid, terminal
        status, output = self.finish(timeout=10)
        self.assertEqual(status, 0, output)
        self.assertIn(f"WATCHER_SIGNAL_STATUS={128 + watched_signal}", output)
        self.assertIn("TAIL_EXITED=True", output)
        self.assertIsNone(holder.poll(), "stopping the watcher must not stop the installer")
        with lock_path.open("r+") as contender:
            with self.assertRaises(BlockingIOError):
                fcntl.flock(contender, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_attach_interrupt_cleans_up_tail_without_stopping_installer(self):
        self.attach_signal_probe(signal.SIGINT)

    def test_attach_termination_cleans_up_tail_without_stopping_installer(self):
        self.attach_signal_probe(signal.SIGTERM)

    def test_attach_hangup_cleans_up_tail_without_stopping_installer(self):
        self.attach_signal_probe(signal.SIGHUP)

    def gum(self, *, failure="", dry_run=False, sudo_identity_fixture=False,
            setsid_available=True, sleep_available=True, mktemp_available=True,
            detached=False, interrupt_signal=None, pid_only=False, monitor_mode=False,
            parent_kill_fails=False):
        function_source = definition("install_gum_early")
        helpers = []
        for helper in ("acfs_run_early_apt", "acfs_wait_early_apt"):
            if re.search(r"^" + helper + r"\(\) \{", SOURCE.read_text(), re.M):
                helpers.append(definition(helper))
                if helper == "acfs_wait_early_apt":
                    helpers.append(initializer("ACFS_EARLY_APT_ACTIVE"))
        if pid_only:
            helpers.extend(definition(helper) for helper in (
                "cleanup", "acfs_bootstrap_dir_is_owned_temp", "acfs_file_is_owned_temp",
                "acfs_remember_install_lock", "acfs_release_install_lock",
            ))
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
/usr/bin/python3 -c 'import json, sys
with open(sys.argv[1], "a") as stream:
    stream.write(json.dumps(sys.argv[2:]) + "\n")
' "$TEST_TIMEOUT_ARGS" "$@"
options=()
while [[ "$1" == -* ]]; do
    case "$1" in
        --foreground) options+=("$1") ;;
        --kill-after=10) options+=(--kill-after=0.2) ;;
        *) exit 98 ;;
    esac
    shift
done
[[ "$1" == 300 ]] || exit 98
shift
# Match the apt operation as an argv element. The guardian's multiline shell
# source is one argument and must not be mistaken for an operation name.
operation=""
for argument in "$@"; do
    case "$argument" in
        update|install)
            [[ -z "$operation" ]] || exit 98
            operation="$argument"
            ;;
    esac
done
case "$operation" in
    update) test_duration="$TEST_TIMEOUT_UPDATE_DURATION" ;;
    install) test_duration="$TEST_TIMEOUT_INSTALL_DURATION" ;;
    *) exit 98 ;;
esac
# Scale only durations supplied by production. In particular, do not invent a
# kill-after grace period that would conceal a missing production escalation.
exec "$TEST_REAL_TIMEOUT_BIN" "${options[@]}" "$test_duration" "$@"
''')
        timeout_wrapper.chmod(0o755)
        apt.write_text("#!/usr/bin/python3\n" + r'''
import errno, os, signal, subprocess, sys, termios, time
from pathlib import Path
events = Path(os.environ["TEST_APT_EVENTS"])
operation = "install" if "install" in sys.argv else "update"
if operation == "install":
    Path(os.environ["TEST_APT_PGID"]).write_text(str(os.getpgrp()))
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
if os.environ["TEST_APT_FAILURE"] == "install-output" and operation == "install":
    print("Unable to locate package fixture-gum", file=sys.stderr, flush=True)
    sys.exit(42)
if os.environ["TEST_APT_FAILURE"] == "timeout":
    time.sleep(10)
if os.environ["TEST_APT_FAILURE"] == "ignore-term" and operation == "install":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    time.sleep(2)
    with events.open("a") as stream:
        stream.write("install:survived-timeout\n")
if os.environ["TEST_APT_FAILURE"] in (
    "descendant", "interrupt", "resistant-descendant", "interrupt-resistant"
) and operation == "install":
    # A helper keeps apt's captured stdout open. Some helpers also ignore TERM;
    # timeout must retain its KILL escalation even after apt itself exits.
    child = """
import fcntl, os, signal, sys, time
from pathlib import Path
events = Path(sys.argv[1])
resistant = os.environ["TEST_APT_FAILURE"] in ("resistant-descendant", "interrupt-resistant")
def terminated(signum, frame):
    with events.open('a') as stream:
        stream.write('terminated\\n')
    sys.exit(0)
signal.signal(signal.SIGTERM, signal.SIG_IGN if resistant else terminated)
Path(os.environ["TEST_APT_CHILD_PID"]).write_text(str(os.getpid()))
events.write_text('started\\n')
lock_path = os.environ.get("TEST_INSTALL_LOCK")
lock_reported = False
deadline = time.monotonic() + (6 if resistant or os.environ["TEST_APT_FAILURE"] == "interrupt" else 2)
while time.monotonic() < deadline:
    if lock_path:
        # Probe from the live helper itself: zombie-only process groups must
        # not be mistaken for work that still needs the installer lock.
        with open(lock_path, "r+") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                if not lock_reported:
                    Path(os.environ["TEST_LOCK_EVENTS"]).write_text('contended\\n')
                    lock_reported = True
            else:
                with open(os.environ["TEST_LOCK_EVENTS"], "a") as stream:
                    stream.write('released-while-child-live\\n')
                fcntl.flock(lock, fcntl.LOCK_UN)
    time.sleep(0.01)
with events.open('a') as stream:
    stream.write('completed\\n')
"""
    if os.environ["TEST_APT_FAILURE"] in ("resistant-descendant", "interrupt-resistant"):
        def terminated(signum, frame):
            with events.open("a") as stream:
                stream.write("install:terminated\n")
            # Abrupt apt exit must leave the resistant helper to production
            # supervision, not subprocess.run's exception cleanup in this fixture.
            os._exit(128 + signum)
        signal.signal(signal.SIGTERM, terminated)
    subprocess.run([sys.executable, "-c", child, os.environ["TEST_APT_CHILD_EVENTS"]], check=False)
''')
        apt.chmod(0o755)
        fixture_commands = {
            "curl": "printf 'fixture-key\\n'\n",
            "gpg": "cat >/dev/null\n",
            "mkdir": ":\n",
            "tee": "cat >/dev/null\n",
            "mktemp": r'''
# Production must pin its private capture to a trusted root, not inherit TMPDIR.
[[ $# -eq 1 && "$1" == /tmp/acfs-early-apt.* ]] || exit 96
exec /usr/bin/python3 -c 'import os, tempfile
fd, path = tempfile.mkstemp(prefix="early-apt-output-", dir=os.environ["TEST_FIXTURE_DIR"])
os.close(fd)
print(path)
'
''',
            "rm": r'''
# Retain test artifacts while recording the production cleanup request.
printf '%s\n' "$*" >> "$TEST_CAPTURE_CLEANUP"
''',
            "sudo": r'''
# This is a signal-transparent exec fixture, not a real privilege transition.
# Authentication happens before detaching, including when stdin is null.
/usr/bin/python3 -c 'import os, sys; fd = os.open("/dev/tty", os.O_RDWR); sys.exit(os.tcgetpgrp(fd) != os.getpgrp())' || exit 97
printf 'foreground-terminal\n' >> "$TEST_SUDO_EVENTS"
unset DEBIAN_FRONTEND
exec "$@"
''',
        }
        for name, content in fixture_commands.items():
            fixture = self.root / ("fixture-" + name)
            fixture.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + content)
            fixture.chmod(0o755)
        # A setup update must not hit the shortened deadline intended for a
        # later install fault, especially when the test host is under load.
        install_duration = "0.4" if failure in ("descendant", "resistant-descendant", "ignore-term") else "2"
        if interrupt_signal is not None:
            install_duration = "4"
        body = "\n".join([
            *helpers,
            function_source,
            definition("_acfs_signal_handler"),
            definition("_acfs_bootstrap_signal_exit"),
            "trap '_acfs_signal_handler INT' INT",
            "trap '_acfs_signal_handler TERM' TERM",
            "trap '_acfs_signal_handler HUP' HUP",
            f"export TEST_APT_EVENTS={shlex.quote(str(events))}",
            f"export TEST_APT_PGID={shlex.quote(str(self.root / 'apt-pgid'))}",
            f"export TEST_APT_CHILD_EVENTS={shlex.quote(str(self.root / 'apt-child-events'))}",
            f"export TEST_APT_CHILD_PID={shlex.quote(str(self.root / 'apt-child-pid'))}",
            f"export TEST_INSTALL_LOCK={shlex.quote(str(self.root / 'install.lock') if pid_only else '')}",
            f"export TEST_LOCK_EVENTS={shlex.quote(str(self.root / 'apt-lock-events'))}",
            f"export TEST_INTERRUPT_EVENTS={shlex.quote(str(self.root / 'interruption-events'))}",
            f"export TEST_CAPTURE_CLEANUP={shlex.quote(str(self.root / 'capture-cleanup-events'))}",
            f"export TEST_APT_FAILURE={shlex.quote(failure)}",
            f"export TEST_TIMEOUT_ARGS={shlex.quote(str(timeouts))}",
            f"export TEST_REAL_TIMEOUT_BIN={shlex.quote(timeout_bin)}",
            f"export TEST_TIMEOUT_UPDATE_DURATION={'0.4' if failure == 'timeout' else '2'}",
            f"export TEST_TIMEOUT_INSTALL_DURATION={install_duration}",
            f"TEST_TIMEOUT_WRAPPER={shlex.quote(str(timeout_wrapper))}",
            f"TEST_APT_BIN={shlex.quote(str(apt))}",
            f"TEST_SETSID_BIN={shlex.quote(setsid_bin)}",
            f"TEST_ENV_BIN={shlex.quote(env_bin)}",
            f"export TEST_SUDO_EVENTS={shlex.quote(str(self.root / 'sudo-events'))}",
            f"export TEST_FIXTURE_DIR={shlex.quote(str(self.root))}",
            f"TEST_SETSID_AVAILABLE={'true' if setsid_available else 'false'}",
            f"TEST_SLEEP_AVAILABLE={'true' if sleep_available else 'false'}",
            f"TEST_MKTEMP_AVAILABLE={'true' if mktemp_available else 'false'}",
            f"TEST_MONITOR_MODE={'true' if monitor_mode else 'false'}",
            f"DRY_RUN={'true' if dry_run else 'false'}",
            r'''
# Exercise the shipped EXIT cleanup against a real install-wide lock. Only
# its state-storage callback and unrelated logging are controlled fixtures.
BOOTSTRAP_ARCHIVE_FD=""
ACFS_BOOTSTRAP_SUPERVISOR=true
ACFS_INSTALL_RUN_CONFIRMED=0
ACFS_CLEANUP_ACTIVE=false
_ACFS_SIGNAL_RECEIVED=""
log_error() { :; }
log_warn() { :; }
acfs_log_close() { :; }
state_mark_interrupted() { printf '%s\n' "$_ACFS_SIGNAL_RECEIVED" >> "$TEST_INTERRUPT_EVENTS"; }
exec 199>>"$TEST_INSTALL_LOCK"
flock -n 199
acfs_remember_install_lock 199 "$TEST_INSTALL_LOCK"
trap cleanup EXIT
''' if pid_only else ":",
            # A sudo exec can make the privileged helper unsignalable by the
            # caller. The child Bash ignores this function; EOF must cancel it.
            "kill() { return 1; }" if parent_kill_fails else ":",
            r'''
ACFS_DISTRO_FAMILY=ubuntu
HAS_GUM=false
ACFS_EARLY_CURL_ARGS=()
_acfs_os_release_field() { printf '24.04\n'; }
acfs_early_sudo_binary_path() { printf '%s/fixture-sudo\n' "$TEST_FIXTURE_DIR"; }
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
        bash) printf '/bin/bash\n' ;;
        sleep)
            [[ "$TEST_SLEEP_AVAILABLE" == true ]] || return 1
            printf '/bin/sleep\n'
            ;;
        mktemp)
            [[ "$TEST_MKTEMP_AVAILABLE" == true ]] || return 1
            printf '%s/fixture-mktemp\n' "$TEST_FIXTURE_DIR"
            ;;
        *) printf '%s/fixture-%s\n' "$TEST_FIXTURE_DIR" "$1" ;;
    esac
}
if [[ "$TEST_MONITOR_MODE" == true ]]; then
    set -m
fi
install_gum_early
printf 'HAS_GUM=%s\n' "$HAS_GUM"
if [[ "$TEST_MONITOR_MODE" == true ]]; then
    [[ $- == *m* ]]
    printf 'JOB_CONTROL_RESTORED=true\n'
fi
''',
        ])
        if interrupt_signal is not None or failure == "resistant-descendant":
            return self.gum_process_probe(
                body, interrupt_signal,
                resistant_child=failure in ("resistant-descendant", "interrupt-resistant"),
                pid_only=pid_only,
            )
        if detached:
            import subprocess

            result = subprocess.run(
                ["/bin/bash", "-c", "set -euo pipefail\n" + body],
                stdin=subprocess.DEVNULL, capture_output=True, text=True,
                start_new_session=True, timeout=5,
            )
            status, output = result.returncode, result.stdout + result.stderr
        else:
            self.start(body)
            status, output = self.finish()
        self.assertEqual(status, 0, output)
        return output, events.read_text() if events.exists() else "", timeouts

    def gum_process_probe(self, body, watched_signal, *, resistant_child=False, pid_only=False):
        pid, terminal = pty.fork()
        if pid == 0:
            import ctypes

            # Keep the terminal's session leader alive after cancellation, as
            # SSH/tmux would, and reap any orphaned fixture descendants. Closing
            # the PTY must not mask missing installer cleanup.
            ctypes.CDLL(None).prctl(36, 1, 0, 0, 0)
            ready_read, ready_write = os.pipe()
            worker = os.fork()
            if worker == 0:
                os.close(ready_write)
                os.setpgid(0, 0)
                os.read(ready_read, 1)
                os.close(ready_read)
                os.execv("/bin/bash", ["bash", "-c", "set -euo pipefail\n" + body])
            os.close(ready_read)
            os.setpgid(worker, worker)
            signal.signal(signal.SIGTTOU, signal.SIG_IGN)
            os.tcsetpgrp(0, worker)
            os.write(ready_write, b"1")
            os.close(ready_write)
            apt_group = None
            apt_child = None
            child_status = None
            worker_status = None
            group_exited = False
            result = 1
            try:
                pgid_file = self.root / "apt-pgid"
                child_events = self.root / "apt-child-events"
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    if child_events.exists() and "started\n" in child_events.read_text():
                        apt_group = int(pgid_file.read_text())
                        apt_child = int((self.root / "apt-child-pid").read_text())
                        break
                    time.sleep(0.02)
                if apt_group is None or apt_group in (os.getpgrp(), worker):
                    raise RuntimeError("detached apt helper did not become ready")
                if watched_signal is not None:
                    if pid_only:
                        # A service manager/operator may target the installer
                        # PID alone. Its children must be cancelled by production.
                        os.kill(worker, watched_signal)
                    else:
                        # Deliver exactly the foreground-group signal a terminal
                        # would send, without signalling detached apt ourselves.
                        os.killpg(worker, watched_signal)
                deadline = time.monotonic() + 2
                while time.monotonic() < deadline:
                    while True:
                        try:
                            reaped, status = os.waitpid(-1, os.WNOHANG)
                        except ChildProcessError:
                            break
                        if not reaped:
                            break
                        if reaped == worker:
                            worker_status = os.waitstatus_to_exitcode(status)
                        if reaped == apt_child:
                            child_status = os.waitstatus_to_exitcode(status)
                    try:
                        os.killpg(apt_group, 0)
                    except ProcessLookupError:
                        group_exited = True
                    if worker_status is not None and group_exited:
                        break
                    time.sleep(0.02)
                print(f"INSTALLER_SIGNAL_STATUS={worker_status}", flush=True)
                print(f"APT_GROUP_EXITED={group_exited}", flush=True)
                print(f"APT_CHILD_STATUS={child_status}", flush=True)
                result = 0
            finally:
                # Readiness can fail after apt starts but before its helper
                # publishes its marker. Still clean up that owned detached group.
                if apt_group is None and (self.root / "apt-pgid").exists():
                    recorded_group = int((self.root / "apt-pgid").read_text())
                    if recorded_group > 1 and recorded_group not in (os.getpgrp(), worker):
                        apt_group = recorded_group
                for group in (worker, apt_group):
                    if group is not None:
                        try:
                            os.killpg(group, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                # Reap test-owned children even when the baseline fails the
                # assertions, so a negative control cannot leak package fixtures.
                while True:
                    try:
                        os.waitpid(-1, 0)
                    except ChildProcessError:
                        break
                os._exit(result)
        self.child, self.terminal = pid, terminal
        status, output = self.finish(timeout=8)
        self.assertEqual(status, 0, output)
        expected_status = 128 + watched_signal if watched_signal is not None else 0
        self.assertIn(f"INSTALLER_SIGNAL_STATUS={expected_status}", output)
        self.assertIn("APT_GROUP_EXITED=True", output)
        self.assertNotIn("HAS_GUM=true", output)
        if resistant_child:
            self.assertIn(f"APT_CHILD_STATUS={-signal.SIGKILL}", output)
            self.assertEqual((self.root / "apt-child-events").read_text(), "started\n")
            self.assertIn("install:terminated\n", (self.root / "apt-events").read_text())
        else:
            self.assertEqual((self.root / "apt-child-events").read_text(), "started\nterminated\n")
        if pid_only:
            self.assertEqual((self.root / "apt-lock-events").read_text(), "contended\n")
            expected_signal = signal.Signals(watched_signal).name.removeprefix("SIG")
            self.assertEqual((self.root / "interruption-events").read_text(), expected_signal + "\n")
            with (self.root / "install.lock").open("r+") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                fcntl.flock(lock, fcntl.LOCK_UN)
        return output, (self.root / "apt-events").read_text(), self.root / "timeout-args"

    def test_early_apt_fd_allocation_failure_reaps_spawned_child_before_returning(self):
        finished = self.root / "allocation-child-finished"
        released_early = self.root / "allocation-lock-released-early"
        lock_path = self.root / "allocation.lock"
        child = r'''
import fcntl, os, select, sys, time
from pathlib import Path
# Keep a failing negative control bounded even if no EOF arrives.
if not select.select([0], [], [], 2)[0] or os.read(0, 1) != b"":
    sys.exit(97)
time.sleep(0.2)
with open(sys.argv[2], "r+") as lock:
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        pass
    else:
        Path(sys.argv[3]).write_text("released before child finished\n")
        fcntl.flock(lock, fcntl.LOCK_UN)
Path(sys.argv[1]).write_text("finished\n")
'''
        child_command = shlex.join([
            "/usr/bin/python3", "-c", child, str(finished), str(lock_path), str(released_early),
        ])
        self.start("\n".join([
            initializer("ACFS_EARLY_APT_ACTIVE"),
            definition("acfs_wait_early_apt"),
            f"exec 9>{shlex.quote(str(lock_path))}",
            "flock -n 9",
            # Bash can spawn process substitution before discovering that a
            # dynamically allocated descriptor (>=10) exceeds this limit.
            "ulimit -n 10",
            "wrapper_status=0",
            f"acfs_wait_early_apt '' /bin/false /bin/false {child_command} || wrapper_status=$?",
            'printf "WRAPPER_STATUS=%s\\n" "$wrapper_status"',
            f"if [[ -f {shlex.quote(str(finished))} ]]; then",
            "    printf 'CHILD_FINISHED_AT_RETURN=true\\n'",
            "else",
            "    printf 'CHILD_FINISHED_AT_RETURN=false\\n'",
            "fi",
            "flock -u 9",
            # A broken implementation may return early. Retain observations
            # above, then reap its fixture so the negative control cannot leak.
            "wait",
        ]))
        status, output = self.finish()
        self.assertEqual(status, 0, output)
        wrapper_status = re.search(r"WRAPPER_STATUS=(\d+)", output)
        self.assertIsNotNone(wrapper_status, output)
        self.assertNotEqual(int(wrapper_status[1]), 0, output)
        self.assertIn("CHILD_FINISHED_AT_RETURN=true", output)
        self.assertEqual(finished.read_text(), "finished\n")
        self.assertFalse(released_early.exists(), output)

    def test_signal_handler_rejects_inherited_early_apt_ownership(self):
        attempted_signals = self.root / "forged-signal-attempts"
        unrelated_fd = self.root / "unrelated-descriptor"
        self.start("\n".join([
            "export ACFS_EARLY_APT_ACTIVE=true ACFS_EARLY_APT_PID=2147483647",
            "export ACFS_EARLY_APT_CONTROL_FD=197 ACFS_EARLY_APT_SIGNAL=TERM ACFS_EARLY_APT_SIGNAL_COUNT=0",
            initializer("ACFS_EARLY_APT_ACTIVE"),
            definition("_acfs_signal_handler"),
            definition("_acfs_bootstrap_signal_exit"),
            f"TEST_SIGNAL_ATTEMPTS={shlex.quote(str(attempted_signals))}",
            'kill() { printf "%s\\n" "$*" >> "$TEST_SIGNAL_ATTEMPTS"; }',
            "ACFS_CLEANUP_ACTIVE=false; ACFS_BOOTSTRAP_CHILD_STATE=QUIESCENT",
            f"exec 197>{shlex.quote(str(unrelated_fd))}",
            "trap 'printf \"descriptor preserved\\n\" >&197' EXIT",
            "_acfs_signal_handler TERM",
            "printf 'SIGNAL_HANDLER_RETURNED\\n'",
        ]))
        status, output = self.finish()
        self.assertEqual(status, 143, output)
        self.assertNotIn("SIGNAL_HANDLER_RETURNED", output)
        self.assertFalse(attempted_signals.exists())
        self.assertEqual(unrelated_fd.read_text(), "descriptor preserved\n")

    def test_early_gum_apt_detaches_from_controlling_terminal(self):
        output, events, timeouts = self.gum()
        self.assertIn("HAS_GUM=true", output)
        self.assertEqual(events, "update:started\nupdate:detached\ninstall:started\ninstall:detached\n")
        calls = [json.loads(call) for call in timeouts.read_text().splitlines()]
        self.assertEqual(len(calls), 2)
        self.assertTrue(all(call[:2] == ["--kill-after=10", "300"] for call in calls), calls)

    def test_early_gum_detached_noninteractive_bootstrap_succeeds(self):
        output, events, _ = self.gum(detached=True)
        self.assertIn("HAS_GUM=true", output)
        self.assertEqual(events, "update:started\nupdate:detached\ninstall:started\ninstall:detached\n")

    def test_early_gum_simulated_nonroot_sudo_keeps_terminal_and_restores_environment(self):
        output, events, _ = self.gum(sudo_identity_fixture=True)
        self.assertIn("HAS_GUM=true", output)
        self.assertIn("install:detached", events)
        sudo_events = (self.root / "sudo-events").read_text().splitlines()
        self.assertEqual(sudo_events, ["foreground-terminal"] * 5)

    def test_early_gum_restores_monitor_mode_and_keeps_sudo_in_foreground(self):
        output, _, _ = self.gum(sudo_identity_fixture=True, monitor_mode=True)
        self.assertIn("HAS_GUM=true", output)
        self.assertIn("JOB_CONTROL_RESTORED=true", output)
        self.assertEqual((self.root / "sudo-events").read_text().splitlines(), ["foreground-terminal"] * 5)

    def test_early_gum_update_failure_stops_before_install(self):
        output, events, _ = self.gum(failure="update")
        self.assertIn("HAS_GUM=false", output)
        self.assertNotIn("install:started", events)

    def test_early_gum_install_failure_keeps_optional_fallback(self):
        output, events, _ = self.gum(failure="install")
        self.assertIn("HAS_GUM=false", output)
        self.assertIn("install:detached", events)

    def test_early_gum_install_failure_preserves_captured_diagnostics(self):
        output, events, _ = self.gum(failure="install-output")
        self.assertIn("HAS_GUM=false", output)
        self.assertIn("install:detached", events)
        self.assertIn("Charm repository may be unavailable or package not found", output)

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

    def test_early_gum_timeout_kills_package_manager_that_ignores_term(self):
        output, events, _ = self.gum(failure="ignore-term")
        self.assertIn("HAS_GUM=false", output)
        self.assertIn("install:detached", events)
        self.assertNotIn("install:survived-timeout", events)

    def test_early_gum_timeout_kills_resistant_child_after_apt_exits(self):
        output, events, _ = self.gum(failure="resistant-descendant")
        self.assertIn("HAS_GUM=false", output)
        self.assertIn("install:detached", events)

    def test_early_gum_terminal_interrupt_kills_resistant_child_after_apt_exits(self):
        self.gum(failure="interrupt-resistant", interrupt_signal=signal.SIGINT)

    def test_early_gum_terminal_interrupt_cleans_up_detached_apt_group(self):
        self.gum(failure="interrupt", interrupt_signal=signal.SIGINT)

    def test_early_gum_terminal_hangup_cleans_up_detached_apt_group(self):
        self.gum(failure="interrupt", interrupt_signal=signal.SIGHUP)

    def test_early_gum_sudo_terminal_interrupt_cleans_up_detached_apt_group(self):
        self.gum(failure="interrupt", sudo_identity_fixture=True, interrupt_signal=signal.SIGINT)

    def test_early_gum_pid_interrupt_reaps_children_before_unlocking(self):
        self.gum(failure="interrupt-resistant", interrupt_signal=signal.SIGINT, pid_only=True)

    def test_early_gum_pid_termination_reaps_children_before_unlocking(self):
        self.gum(failure="interrupt-resistant", interrupt_signal=signal.SIGTERM, pid_only=True)

    def test_early_gum_pid_hangup_reaps_children_before_unlocking(self):
        self.gum(failure="interrupt-resistant", interrupt_signal=signal.SIGHUP, pid_only=True)

    def test_early_gum_sudo_pid_termination_reaps_children_before_unlocking(self):
        self.gum(failure="interrupt-resistant", interrupt_signal=signal.SIGTERM,
                 sudo_identity_fixture=True, pid_only=True, parent_kill_fails=True)
        self.assertEqual((self.root / "sudo-events").read_text().splitlines(), ["foreground-terminal"] * 5)

    def test_early_gum_missing_session_tool_keeps_optional_fallback(self):
        output, events, timeouts = self.gum(setsid_available=False)
        self.assertIn("HAS_GUM=false", output)
        self.assertEqual(events, "")
        self.assertFalse(timeouts.exists())

    def test_early_gum_missing_guardian_sleep_keeps_optional_fallback(self):
        output, events, timeouts = self.gum(sleep_available=False)
        self.assertIn("HAS_GUM=false", output)
        self.assertEqual(events, "")
        self.assertFalse(timeouts.exists())

    def test_early_gum_missing_capture_mktemp_keeps_optional_fallback(self):
        output, events, timeouts = self.gum(mktemp_available=False)
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
