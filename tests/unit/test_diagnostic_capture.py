#!/usr/bin/env python3
"""Exercise shipped diagnostic functions with real subprocesses and GNU timeout.

Only the diagnostic commands are fixtures; capture, JSON parsing, process-group
signals and timeout escalation run for real. Test-owned files are retained.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]


def definition(path: Path, name: str) -> str:
    match = re.search(r"^" + re.escape(name) + r"\(\) \{\n.*?^\}",
                      path.read_text(), re.M | re.S)
    if match is None:
        raise AssertionError(f"Missing production function: {name}")
    return match[0]


def doctor_definitions(name: str) -> str:
    source = ROOT / "scripts/lib/doctor.sh"
    helpers = [definition(source, "_acfs_doctor_system_binary_path")]
    # Load the shipped dependencies, including when these behavior tests are
    # run against a pre-guardian revision to reproduce the original failure.
    if re.search(r"^_acfs_doctor_run_bounded\(\)", source.read_text(), re.M):
        helpers.append(definition(source, "_acfs_doctor_run_bounded"))
    return "\n".join([*helpers, definition(source, name)])


class DiagnosticCaptureTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="acfs-diagnostic-test-"))
        self.bundle = self.root / "bundle"
        self.bundle.mkdir()
        self.acfs = self.root / "acfs"
        (self.acfs / "scripts/lib").mkdir(parents=True)

    def capture(self, body: str, *, deadline="2"):
        (self.acfs / "scripts/lib/doctor.sh").write_text(body)
        source = ROOT / "scripts/lib/support.sh"
        code = "\n".join([
            "set -euo pipefail",
            definition(source, "support_system_binary_path"),
            definition(source, "support_run_with_timeout"),
            definition(source, "record_bundle_file"),
            definition(source, "capture_doctor_json"),
            "log_detail() { :; }; log_warn() { :; }",
            f"_SUPPORT_ACFS_HOME={shlex.quote(str(self.acfs))}",
            f"_SUPPORT_SCRIPT_DIR={shlex.quote(str(self.root / 'missing'))}",
            f"DOCTOR_TIMEOUT={shlex.quote(deadline)}",
            "BUNDLE_FILES=()",
            "capture_rc=0",
            f"capture_doctor_json {shlex.quote(str(self.bundle))} || capture_rc=$?",
            "printf '%s\\n' \"$capture_rc\" \"${BUNDLE_FILES[@]}\"",
        ])
        result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                text=True, timeout=9)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(lines[1:], ["doctor.json"])
        return int(lines[0]), (self.bundle / "doctor.json").read_text()

    def report(self, *, failures=0):
        return {"acfs_version": "fixture", "checks": [{
            "id": "tool.fixture", "label": "Fixture tool",
            "status": "fail" if failures else "pass",
            "details": "missing" if failures else "installed",
            "fix": "install the missing tool" if failures else None,
        }], "summary": {"pass": int(not failures), "warn": 0, "fail": failures}}

    def test_unhealthy_doctor_keeps_checks_and_repair_hints(self):
        report = self.report(failures=1)
        body = "printf '%s\\n' " + shlex.quote(json.dumps(report)) + "\nexit 1\n"
        rc, output = self.capture(body)
        self.assertEqual(rc, 0, output)
        self.assertEqual(json.loads(output), report)

    def test_healthy_doctor_keeps_complete_report(self):
        report = self.report()
        rc, output = self.capture("printf '%s\\n' " + shlex.quote(json.dumps(report)))
        self.assertEqual(rc, 0, output)
        self.assertEqual(json.loads(output), report)

    def test_success_exit_does_not_accept_malformed_or_unrelated_json(self):
        for output in ('{"checks":', '[]', '{"message":"not a report"}',
                       '{"checks":[]}\n{"checks":[]}'):
            with self.subTest(output=output):
                rc, captured = self.capture("printf '%s\\n' " + shlex.quote(output))
                self.assertEqual(rc, 1, captured)
                self.assertIn("error", json.loads(captured))

    def test_doctor_crash_does_not_present_partial_report_as_complete(self):
        body = "printf '%s\\n' " + shlex.quote(json.dumps(self.report())) + "\nexit 2\n"
        rc, output = self.capture(body)
        self.assertEqual(rc, 1, output)
        self.assertIn("error", json.loads(output))

    def test_timeout_does_not_present_early_json_as_complete(self):
        body = "printf '%s\\n' " + shlex.quote(json.dumps(self.report())) + "\nsleep 10\n"
        rc, output = self.capture(body, deadline="0.1")
        self.assertEqual(rc, 1, output)
        self.assertIn("error", json.loads(output))

    def test_version_probe_preserves_first_line_and_stderr_policy(self):
        probe = doctor_definitions("doctor_version_probe")
        for mode, expected in (("merge", "fixture version"), ("discard", "")):
            with self.subTest(mode=mode):
                code = probe + "\ndoctor_version_probe /usr/bin/timeout 1 " + mode + \
                    " /bin/bash -c 'printf \"fixture version\\nsecond line\\n\" >&2'"
                # Repository helper and literal fixture, no external input. ubs:ignore[py.security.command-injection]
                result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                        text=True, timeout=3)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)

    def test_version_probe_preserves_failure_without_caller_pipefail(self):
        code = doctor_definitions("doctor_version_probe") + \
            "\ndoctor_version_probe /usr/bin/timeout 1 merge /bin/bash -c " + \
            shlex.quote("printf 'credible version 1.0\\n'; exit 42")
        result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                text=True, timeout=3)
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertEqual(result.stdout, "credible version 1.0\n")

    def version_check_code(self, body: str, *, name="codex", optional=False,
                           interpreter="/bin/bash", deadline="0.5",
                           missing_timeout=False, missing_system_binary=None):
        """Keep the shipped version/check pipeline; fixture discovery/output only."""
        tool = self.root / name
        tool.write_text(f"#!{interpreter}\n" + body + "\n")
        tool.chmod(0o755)
        source = ROOT / "scripts/lib/doctor.sh"
        definitions = [doctor_definitions("doctor_version_probe")]
        for function in ("get_version_line", "doctor_report_version_failure",
                         "check_command", "check_optional_command"):
            # This also runs against the pre-fix production source to prove the
            # regressions; the reporting helper did not exist there.
            if re.search(r"^" + function + r"\(\)", source.read_text(), re.M):
                definitions.append(definition(source, function))
        command = "check_optional_command" if optional else "check_command"
        missing_system_binary = "timeout" if missing_timeout else missing_system_binary
        system_lookup = ":"
        if missing_system_binary:
            system_lookup = (
                "_acfs_doctor_system_binary_path() { "
                '[[ "$1" != ' + shlex.quote(missing_system_binary) + " ]] || return 1; "
                'local candidate; for candidate in "/usr/bin/$1" "/bin/$1" '
                '"/usr/sbin/$1" "/sbin/$1"; do '
                '[[ -x "$candidate" ]] || continue; printf \'%s\\n\' "$candidate"; '
                "return 0; done; return 1; }"
            )
        return "\n".join([
            *definitions,
            "doctor_skip_unselected_check() { return 1; }",
            "doctor_optional_failure_status() { printf '%s\\n' warn; }",
            "doctor_binary_path() { printf '%s\\n' " + shlex.quote(str(tool)) + "; }",
            "check() { printf '%s|%s|%s|%s|%s\\n' \"$1\" \"$2\" \"$3\" \"${4:-}\" \"${5:-}\"; }",
            'check_with_timeout_status() { check "$@"; }',
            "DOCTOR_VERSION_TIMEOUT=" + shlex.quote(deadline),
            system_lookup,
            f"{command} agent.codex Codex {shlex.quote(name)} repair-codex",
        ])

    def test_command_check_rejects_failed_or_empty_launchers(self):
        cases = (
            ("exit 127", "/bin/bash"),
            ("printf 'credible version 99.0\\n'; exit 42", "/bin/bash"),
            ("exit 0", "/bin/bash"),
            ("printf '  \\n\\t\\n'", "/bin/bash"),
            ("printf 'unreachable\\n'", "/nonexistent-acfs-fixture-interpreter"),
        )
        for body, interpreter in cases:
            with self.subTest(body=body, interpreter=interpreter):
                code = self.version_check_code(body, interpreter=interpreter)
                result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                        text=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                row = result.stdout.strip().split("|")
                self.assertEqual(row[2], "fail", result.stdout)
                self.assertIn("verification failed", row[3])
                self.assertEqual(row[4], "repair-codex")

    def test_command_check_preserves_tool_specific_version_conventions(self):
        cases = (("lsof", "-v"), ("minisign", "-v"), ("dig", "-v"),
                 ("tmux", "-V"), ("go", "version"), ("nc", "-h"),
                 ("codex", "--help"), ("bun", "--version"),
                 ("legacy", "-V"), ("subcommand", "version"))
        for name, argument in cases:
            with self.subTest(name=name, argument=argument):
                body = '[[ "$1" == ' + shlex.quote(argument) + " ]] || exit 2\n" + \
                    "printf '%s\\n' " + shlex.quote(name + " fixture 1.0") + " >&2"
                code = self.version_check_code(body, name=name)
                result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                        text=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(),
                                 f"agent.codex|Codex ({name} fixture 1.0)|pass|installed|")

    def test_command_check_drains_large_help_without_sigpipe(self):
        producer = "import sys; print('Usage: fixture'); sys.stdout.write('detail\\n' * 300000)"
        body = '[[ "$1" == --help ]] || exit 2\nexec /usr/bin/python3 -c ' + shlex.quote(producer)
        code = self.version_check_code(body, deadline="2")
        result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "agent.codex|Codex (Usage: fixture)|pass|installed|\n")

    def test_command_check_timeout_stops_fallbacks_and_rejects_early_banner(self):
        calls = self.root / "version-arguments"
        body = "printf '%s\\n' \"$1\" >> " + shlex.quote(str(calls)) + \
            "\nprintf 'credible version 1.0\\n'\nsleep 30"
        code = self.version_check_code(body, deadline="0.1")
        result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                text=True, timeout=8)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip().split("|")[2], "timeout", result.stdout)
        self.assertEqual(calls.read_text().splitlines(), ["--version"])

    def test_interrupted_version_probe_never_falls_back_or_queues_repair(self):
        source = ROOT / "scripts/lib/doctor.sh"
        for status in (124, 137, 143):
            for fallback_succeeds in (False, True):
                with self.subTest(status=status, fallback_succeeds=fallback_succeeds):
                    calls = self.root / f"interrupted-version-{status}-{fallback_succeeds}"
                    body = "printf '%s\\n' \"$1\" >> " + shlex.quote(str(calls)) + "\n"
                    if fallback_succeeds:
                        body += 'if [[ "$1" != --version ]]; then printf "fallback version 1.0\\n"; exit 0; fi\n'
                    body += f"printf 'unverified version 99.0\\n'; exit {status}"
                    before, call = self.version_check_code(body).rsplit("\n", 1)
                    # Use the real JSON/counter/repair path, including when a
                    # fallback would otherwise hide the interrupted command.
                    code = "\n".join([
                        before,
                        *(definition(source, name) for name in
                          ("json_escape", "check", "check_with_timeout_status")),
                        "JSON_MODE=true; HAS_GUM=false; FIX_MODE=true; DOCTOR_FIX_SCOPED=true",
                        "PASS_COUNT=0; WARN_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0",
                        "JSON_CHECKS=(); DOCTOR_FIX_OBSERVED_IDS=(); DOCTOR_FIX_PENDING_IDS=()",
                        "DOCTOR_FIX_PENDING_STATUSES=(); DOCTOR_FIX_PENDING_HINTS=()",
                        call,
                        'printf \'[%s]\\n\' "$(IFS=,; echo "${JSON_CHECKS[*]}")"',
                        'printf \'%s\\n\' "${#DOCTOR_FIX_PENDING_IDS[@]}"',
                    ])
                    result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                            text=True, timeout=3)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    lines = result.stdout.splitlines()
                    self.assertEqual(len(lines), 2, result.stdout)
                    checks = json.loads(lines[0])
                    self.assertEqual(len(checks), 1, checks)
                    self.assertEqual(checks[0]["status"], "timeout", checks)
                    self.assertEqual(int(lines[1]), 0)
                    self.assertEqual(calls.read_text().splitlines(), ["--version"])

    def test_command_check_missing_timeout_never_executes_unbounded_launcher(self):
        marker = self.root / "unbounded-version-ran"
        body = "touch " + shlex.quote(str(marker)) + "; printf 'version 1.0\\n'"
        code = self.version_check_code(body, missing_timeout=True)
        result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                text=True, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        row = result.stdout.strip().split("|")
        self.assertEqual(row[2], "warn", result.stdout)
        self.assertIn("verification unavailable", row[3])
        self.assertEqual(row[4], "")
        self.assertFalse(marker.exists())

    def test_command_check_invalid_timeout_never_executes_launcher(self):
        for index, deadline in enumerate(("0", "0.00", "-1", "--help", "NaN", "1h")):
            with self.subTest(deadline=deadline):
                marker = self.root / f"invalid-version-deadline-{index}"
                body = "touch " + shlex.quote(str(marker)) + "; printf 'version 1.0\\n'"
                code = self.version_check_code(body, deadline=deadline)
                result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                        text=True, timeout=3)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip().split("|")[2], "warn", result.stdout)
                self.assertFalse(marker.exists())

    def test_command_check_missing_probe_dependency_is_not_a_broken_launcher(self):
        for dependency in ("bash", "head", "cat", "sleep"):
            with self.subTest(dependency=dependency):
                marker = self.root / f"missing-{dependency}-launcher-ran"
                body = "touch " + shlex.quote(str(marker)) + "; printf 'version 1.0\\n'"
                code = self.version_check_code(body, missing_system_binary=dependency)
                result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                        text=True, timeout=3)
                self.assertEqual(result.returncode, 0, result.stderr)
                row = result.stdout.strip().split("|")
                self.assertEqual(row[2], "warn", result.stdout)
                self.assertIn("verification unavailable", row[3])
                self.assertEqual(row[4], "")
                self.assertFalse(marker.exists())

    def test_optional_command_check_warns_for_broken_installed_launcher(self):
        code = self.version_check_code("printf 'version 1.0\\n'; exit 42", optional=True)
        result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                text=True, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip().split("|")[2], "warn", result.stdout)
        self.assertEqual(result.stdout.strip().split("|")[4], "repair-codex")

    def command_check_code(self, kind: str, body: str, *, dpkg_body="exit 1\n",
                           missing_timeout=False, stranded=""):
        """Run the real quick check; fixture only tool discovery and rendering."""
        tool = self.root / f"{kind} fixture"
        tool.write_text("#!/bin/bash\n" + body)
        tool.chmod(0o755)
        dpkg = self.root / "dpkg-query fixture"
        dpkg.write_text("#!/bin/bash\n" + dpkg_body)
        dpkg.chmod(0o755)
        check_name = "check_bun_global_bin_dir" if kind == "bun" else "check_cosign_version"
        return "\n".join([
            "set -uo pipefail",
            doctor_definitions(check_name),
            "doctor_skip_unselected_check() { return 1; }",
            "check() { printf '%s|%s|%s\\n' \"$1\" \"$3\" \"${4:-}\"; }",
            'check_with_timeout_status() { check "$@"; }',
            "doctor_binary_path() { case \"$1\" in " + kind + ") printf '%s\\n' " +
            shlex.quote(str(tool)) + ";; dpkg-query) printf '%s\\n' " +
            shlex.quote(str(dpkg)) + ";; *) return 1;; esac; }",
            "doctor_runtime_home() { printf '%s\\n' " + shlex.quote(str(self.root)) + "; }",
            "doctor_bun_stranded_global_binaries() { printf '%s' " + shlex.quote(stranded) + "; }",
            "_acfs_doctor_current_home=" + shlex.quote(str(self.root)),
            "DOCTOR_VERSION_TIMEOUT=0.5",
            "_acfs_doctor_system_binary_path() { return 1; }" if missing_timeout else ":",
            check_name,
        ])

    def test_bun_global_bin_check_accepts_only_successful_absolute_path(self):
        expected = str(self.root / ".bun/bin")
        cases = [
            ("printf '%s\\n' " + shlex.quote(expected), "pass"),
            ("printf '%s\\n' " + shlex.quote(expected) + "; exit 42", "warn"),
            ("printf 'not-a-path\\n'", "warn"),
            ("exit 0", "warn"),
        ]
        for body, status in cases:
            with self.subTest(body=body):
                result = subprocess.run(["/bin/bash", "-c", self.command_check_code("bun", body)],
                                        capture_output=True, text=True, timeout=3)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f"bun.global_bin_dir|{status}|", result.stdout)

    def test_bun_global_bin_check_reports_stranded_packages_without_running_bun(self):
        marker = self.root / "stranded-probe-ran"
        code = self.command_check_code(
            "bun", "touch " + shlex.quote(str(marker)),
            stranded=f"{self.root}/.cache/.bun/bin/codex\t@openai/codex\n")
        result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                text=True, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("bun.global_bin_dir|warn|", result.stdout)
        self.assertIn("codex", result.stdout)
        self.assertFalse(marker.exists(), "Known stranded packages need no external probe")

    def test_cosign_version_keeps_release_and_distro_versions(self):
        for body, dpkg_body, expected in [
            ("printf 'GitVersion: v3.0.2\\n'", "exit 1", "cosign (v3.0.2)"),
            ("printf 'GitVersion: devel\\n'", "printf '2:2.6.2-0ubuntu1'", "cosign (v2.6.2)"),
        ]:
            with self.subTest(body=body):
                code = self.command_check_code("cosign", body, dpkg_body=dpkg_body)
                # Include the label to distinguish the exact discovered version.
                code = code.rsplit("\n", 1)[0] + \
                    '\ncheck() { printf "%s|%s|%s|%s\\n" "$1" "$2" "$3" "${4:-}"; }\ncheck_cosign_version'
                result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                        text=True, timeout=3)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(expected, result.stdout)
                self.assertIn("|pass|", result.stdout)

    def test_quick_checks_do_not_execute_without_timeout(self):
        for kind in ("bun", "cosign"):
            with self.subTest(kind=kind):
                marker = self.root / f"{kind}-unbounded"
                code = self.command_check_code(kind, "touch " + shlex.quote(str(marker)),
                                               missing_timeout=True)
                result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                        text=True, timeout=3)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(marker.exists(), "Missing timeout must not run a probe")
                self.assertIn("|warn|", result.stdout)

    def test_quick_checks_bound_wrappers_with_resistant_descendants(self):
        for kind in ("bun", "cosign"):
            with self.subTest(kind=kind):
                self.root = Path(tempfile.mkdtemp(prefix="acfs-diagnostic-check-"))
                fixture, stop, identity = self.wrapper_with_resistant_grandchild()
                code = self.command_check_code(kind, "exec /usr/bin/python3 " + shlex.quote(str(fixture)))
                process = subprocess.Popen(["/bin/bash", "-c", code], stdout=subprocess.PIPE,
                                           stderr=subprocess.PIPE, text=True)
                try:
                    try:
                        stdout, stderr = process.communicate(timeout=9)
                    except subprocess.TimeoutExpired:
                        self.fail(f"{kind} quick check exceeded its deadline and termination grace")
                    self.assertEqual(process.returncode, 0, (stdout, stderr))
                    self.assertIn("|timeout|", stdout)
                    self.assert_child_stopped(identity)
                finally:
                    stop.touch()
                    process.communicate(timeout=3)

    def test_version_probe_kills_term_ignoring_process(self):
        probe = doctor_definitions("doctor_version_probe")
        fixture = self.root / "stubborn.py"
        group = self.root / "process-group"
        fixture.write_text("import os,signal,time\nfrom pathlib import Path\n"
                           "signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
                           f"Path({str(group)!r}).write_text(str(os.getpgrp()))\n"
                           "time.sleep(30)\n")
        code = "set -o pipefail\n" + probe + \
            "\ndoctor_version_probe /usr/bin/timeout 0.1 discard /usr/bin/python3 " + shlex.quote(str(fixture))
        # Repository helper and shell-quoted fixture path. ubs:ignore[py.security.command-injection]
        process = subprocess.Popen(["/bin/bash", "-c", code], stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True)
        try:
            try:
                stdout, stderr = process.communicate(timeout=9)
            except subprocess.TimeoutExpired:
                self.fail("Version probe exceeded its deadline and termination grace")
            self.assertIn(process.returncode, (124, 137), (stdout, stderr))
        finally:
            if process.poll() is None:
                # Kill only this test's timeout group and outer shell, retaining
                # the fixture files. GNU timeout creates its own process group.
                if group.exists():
                    try:
                        os.killpg(int(group.read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.communicate(timeout=3)

    def wrapper_with_resistant_grandchild(self, *, parent_waits=True):
        fixture = self.root / "wrapper with child.py"
        stop = self.root / "stop-child"
        identity = self.root / "child-identity.json"
        fixture.write_text(
            "import json,os,signal,subprocess,sys,time\n"
            "from pathlib import Path\n"
            f"stop=Path({str(stop)!r})\n"
            f"identity=Path({str(identity)!r})\n"
            "if len(sys.argv) > 1:\n"
            "    signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
            "    stat=Path('/proc/self/stat').read_text().split()\n"
            "    identity.write_text(json.dumps({'pid':stat[0], 'start':stat[21]}))\n"
            "    deadline=time.monotonic()+15\n"
            "    while time.monotonic()<deadline and not stop.exists():\n"
            "        time.sleep(0.02)\n"
            "else:\n"
            "    child=subprocess.Popen([sys.executable, __file__, 'child'])\n"
            + ("    child.wait()\n" if parent_waits else
               "    deadline=time.monotonic()+3\n"
               "    while not identity.exists() and time.monotonic()<deadline:\n"
               "        time.sleep(0.01)\n"
               "    print('wrapper version 1.0', flush=True)\n")
        )
        return fixture, stop, identity

    def assert_child_stopped(self, identity: Path):
        self.assertTrue(identity.is_file(), "Resistant grandchild never became ready")
        child = json.loads(identity.read_text())
        # /proc exposes host PIDs in this executor. They are used only for
        # liveness reads, never as targets for signals from another namespace.
        stat_path = Path("/proc") / child["pid"] / "stat"
        for _ in range(20):
            try:
                stat = stat_path.read_text().split()
            except FileNotFoundError:
                return
            if stat[2] == "Z" or stat[21] != child["start"]:
                return
            time.sleep(0.025)
        self.fail("Probe returned with its TERM-resistant grandchild still running")

    def bounded_probe(self, kind: str, command: list[str], *, deadline="0.5"):
        argv = shlex.join(command)
        if kind == "swarm":
            source = ROOT / "scripts/lib/swarm_status.sh"
            return "\n".join([
                definition(source, "swarm_status_binary_path"),
                definition(source, "swarm_status_run_with_timeout"),
                f"swarm_status_run_with_timeout {deadline} {argv}",
            ])
        if kind == "version":
            return "set -o pipefail\n" + doctor_definitions("doctor_version_probe") + \
                f"\ndoctor_version_probe /usr/bin/timeout {deadline} discard {argv}"
        if kind == "deep":
            return "\n".join([
                doctor_definitions("run_with_timeout"),
                "JSON_MODE=true; HAS_GUM=false",
                f"run_with_timeout {deadline} fixture {argv}",
            ])
        if kind == "onboard":
            source = ROOT / "packages/onboard/onboard.sh"
            return "\n".join([
                definition(source, "onboard_system_binary_path"),
                definition(source, "onboard_run_auth_probe"),
                f"onboard_run_auth_probe {deadline} {argv}",
            ])
        source = ROOT / "scripts/lib/support.sh"
        return "\n".join([
            definition(source, "support_system_binary_path"),
            definition(source, "support_run_with_timeout"),
            f"support_run_with_timeout {deadline} {argv}",
        ])

    def check_wrapper_timeout(self, kind: str):
        fixture, stop, identity = self.wrapper_with_resistant_grandchild()
        code = self.bounded_probe(kind, ["/usr/bin/python3", str(fixture)])
        process = subprocess.Popen(["/bin/bash", "-c", code], stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True)
        try:
            try:
                stdout, stderr = process.communicate(timeout=9)
            except subprocess.TimeoutExpired:
                self.fail("Wrapper exited on TERM but its child kept the diagnostic probe open")
            self.assertIn(process.returncode, (124, 137), (stdout, stderr))
            if kind == "deep" and process.returncode == 124:
                self.assertEqual(stdout, "TIMEOUT\n")
            self.assert_child_stopped(identity)
        finally:
            # Cooperatively stop this test's fixture on an assertion failure;
            # it also has its own lifetime bound. Keep every fixture file.
            stop.touch()
            process.communicate(timeout=3)

    def test_version_probe_bounds_wrapper_exit_with_live_grandchild(self):
        self.check_wrapper_timeout("version")

    def test_version_probe_bounds_capture_after_wrapper_exits_successfully(self):
        fixture, stop, identity = self.wrapper_with_resistant_grandchild(parent_waits=False)
        code = self.bounded_probe("version", ["/usr/bin/python3", str(fixture)])
        process = subprocess.Popen(["/bin/bash", "-c", code], stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True)
        try:
            stdout, stderr = process.communicate(timeout=9)
            self.assertIn(process.returncode, (124, 137), (stdout, stderr))
            self.assertEqual(stdout, "wrapper version 1.0\n")
            self.assert_child_stopped(identity)
        finally:
            stop.touch()
            process.communicate(timeout=3)

    def test_deep_probe_bounds_wrapper_exit_with_live_grandchild(self):
        self.check_wrapper_timeout("deep")

    def test_support_helper_bounds_wrapper_exit_with_live_grandchild(self):
        self.check_wrapper_timeout("support")

    def test_swarm_probe_bounds_wrapper_exit_with_live_grandchild(self):
        self.check_wrapper_timeout("swarm")

    def test_onboard_probe_bounds_wrapper_exit_with_live_grandchild(self):
        self.check_wrapper_timeout("onboard")

    def test_live_info_bounds_wrapper_exit_with_live_grandchild(self):
        fixture, stop, identity = self.wrapper_with_resistant_grandchild()
        collector = self.root / "collector.sh"
        collector.write_text("exec /usr/bin/python3 " + shlex.quote(str(fixture)) + "\n")
        source = ROOT / "scripts/lib/info.sh"
        code = "\n".join([
            definition(source, "info_system_binary_path"),
            definition(source, "info_collect_swarm_status_json"),
            f"ACFS_INFO_SWARM_STATUS_SCRIPT={shlex.quote(str(collector))}",
            "ACFS_INFO_SWARM_STATUS_DEADLINE=0.5",
            "info_collect_swarm_status_json",
        ])
        process = subprocess.Popen(["/bin/bash", "-c", code], stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True)
        try:
            try:
                stdout, stderr = process.communicate(timeout=4)
            except subprocess.TimeoutExpired:
                self.fail("Live info waited for a descendant after its collector timed out")
            self.assertEqual(process.returncode, 1, (stdout, stderr))
            self.assertEqual(stdout, "")
            self.assert_child_stopped(identity)
        finally:
            stop.touch()
            process.communicate(timeout=3)

    def test_swarm_missing_timeout_does_not_execute_unbounded_probe(self):
        marker = self.root / "unbounded-probe-ran"
        code = self.bounded_probe("swarm", ["/usr/bin/touch", str(marker)], deadline="1")
        # Only dependency discovery is replaced; run the actual probe helper.
        before, call = code.rsplit("\n", 1)
        code = before + '\nswarm_status_binary_path() { return 1; }\n' + call
        # Repository helper, literal override, and quoted argv. ubs:ignore[py.security.command-injection]
        result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                text=True, timeout=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(marker.exists(), "Missing timeout ran an unbounded probe")

    def test_swarm_rejects_deadlines_that_disable_or_reinterpret_timeout(self):
        for index, deadline in enumerate(("0", "0.000", "-1", "--help", "NaN", "1h")):
            with self.subTest(deadline=deadline):
                marker = self.root / f"invalid-deadline-probe-ran-{index}"
                code = self.bounded_probe("swarm", ["/usr/bin/touch", str(marker)],
                                          deadline=shlex.quote(deadline))
                result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                        text=True, timeout=3)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(marker.exists())

    def test_onboard_missing_timeout_does_not_execute_unbounded_probe(self):
        marker = self.root / "onboard-unbounded-probe-ran"
        code = self.bounded_probe("onboard", ["/usr/bin/touch", str(marker)], deadline="1")
        before, call = code.rsplit("\n", 1)
        code = before + '\nonboard_system_binary_path() { return 1; }\n' + call
        # Repository helper, literal override, and quoted argv. ubs:ignore[py.security.command-injection]
        result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                text=True, timeout=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(marker.exists(), "Missing timeout ran an unbounded auth probe")

    def test_onboard_rejects_deadlines_that_disable_or_reinterpret_timeout(self):
        for index, deadline in enumerate(("0", "0.000", "-1", "--help", "NaN", "1h")):
            with self.subTest(deadline=deadline):
                marker = self.root / f"onboard-invalid-deadline-probe-ran-{index}"
                code = self.bounded_probe("onboard", ["/usr/bin/touch", str(marker)],
                                          deadline=shlex.quote(deadline))
                result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                        text=True, timeout=3)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(marker.exists())

    def test_doctor_capture_bounds_wrapper_exit_with_live_grandchild(self):
        fixture, stop, identity = self.wrapper_with_resistant_grandchild()
        try:
            body = "exec /usr/bin/python3 " + shlex.quote(str(fixture))
            rc, output = self.capture(body, deadline="0.5")
            self.assertEqual(rc, 1, output)
            self.assertIn(json.loads(output)["exit_code"], (124, 137))
            self.assert_child_stopped(identity)
        finally:
            stop.touch()

    def test_helpers_preserve_failure_arguments_streams_and_null_stdin(self):
        argument = "literal 'quotes' $(not-a-command); spaces"
        probe = (
            "import json,sys; "
            "print(json.dumps(sys.argv[1:]), flush=True); "
            "print('stdin='+sys.stdin.read(), flush=True); "
            "print('diagnostic stderr', file=sys.stderr, flush=True); "
            "sys.exit(41)"
        )
        first_line = json.dumps([argument]) + "\n"
        for kind in ("version", "deep", "support", "swarm", "onboard"):
            with self.subTest(kind=kind):
                code = self.bounded_probe(kind, ["/usr/bin/python3", "-c", probe, argument], deadline="2")
                result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                        text=True, input="remaining installer input\n", timeout=5)
                self.assertEqual(result.returncode, 41, result.stderr)
                expected = first_line if kind == "version" else first_line + "stdin=\n"
                if kind in ("deep", "swarm"):
                    expected += "diagnostic stderr\n"
                self.assertEqual(result.stdout, expected)
                self.assertEqual(result.stderr, "")

    def test_native_probe_guardian_ignores_shell_startup_hooks(self):
        hook = self.root / "bash-env"
        marker = self.root / "hook-ran"
        hook.write_text("printf 'unexpected startup' > " + shlex.quote(str(marker)))
        for kind in ("version", "deep", "support", "swarm", "onboard"):
            with self.subTest(kind=kind):
                code = "export BASH_ENV=" + shlex.quote(str(hook)) + "\n" + \
                    self.bounded_probe(kind, ["/usr/bin/printf", "%s\\n", "version 1"], deadline="2")
                # Repository helper and quoted startup-hook fixture. ubs:ignore[py.security.command-injection]
                result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                        text=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "version 1\n")
                self.assertFalse(marker.exists(), "Guardian executed a user shell startup hook")

    def test_native_137_is_preserved_as_failure_not_relabelled_timeout(self):
        for kind in ("version", "deep", "support", "swarm", "onboard"):
            with self.subTest(kind=kind):
                code = self.bounded_probe(kind, ["/bin/bash", "-c", "printf 'native failure\\n'; exit 137"], deadline="2")
                result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                        text=True, timeout=5)
                self.assertEqual(result.returncode, 137, result.stderr)
                self.assertEqual(result.stdout, "native failure\n")
                self.assertEqual(result.stderr, "")

    def doctor_live_check_code(self, check_name: str, body: str, *, missing_timeout=False, args=()):
        """Exercise live verdicts and repair collection, with inert provider binaries."""
        source = ROOT / "scripts/lib/doctor.sh"
        provider = self.root / "provider fixture"
        provider.write_text("#!/bin/bash\n" + body + "\n")
        provider.chmod(0o755)
        auth = self.root / ".config/vercel"
        auth.mkdir(parents=True, exist_ok=True)
        (auth / "auth.json").write_text('{"token":"fixture-saved-token"}')
        self.cache_marker = self.root / "cached-verdicts"
        helpers = ["json_escape", "check", "check_with_timeout_status",
                   "normalize_config_value", "is_placeholder_secret", "has_usable_secret",
                   "json_file_has_usable_jq_value", "json_file_has_usable_string_key"]
        return "\n".join([
            "set -euo pipefail",
            doctor_definitions("run_with_timeout"),
            *(definition(source, name) for name in helpers),
            definition(source, check_name),
            'doctor_skip_unselected_check() { return 1; }',
            "doctor_binary_path() { printf '%s\\n' " + shlex.quote(str(provider)) + "; }",
            "doctor_runtime_home() { printf '%s\\n' " + shlex.quote(str(self.root)) + "; }",
            "doctor_runtime_path() { printf '%s\\n' /usr/bin:/bin; }",
            'get_cached_result() { return 1; }',
            "cache_result() { printf '%s|%s\\n' \"$1\" \"$2\" >> " +
                shlex.quote(str(self.cache_marker)) + "; }",
            'default_auth_config_files() { :; }',
            'get_configured_secret() { return 1; }',
            'JSON_MODE=true; HAS_GUM=false; FIX_MODE=true; DOCTOR_FIX_SCOPED=true',
            'PASS_COUNT=0; WARN_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0',
            'JSON_CHECKS=(); DOCTOR_FIX_OBSERVED_IDS=(); DOCTOR_FIX_PENDING_IDS=()',
            'DOCTOR_FIX_PENDING_STATUSES=(); DOCTOR_FIX_PENDING_HINTS=()',
            'TARGET_USER=fixture; VAULT_ADDR=https://vault.invalid; DEEP_CHECK_TIMEOUT=0.5',
            '_acfs_doctor_system_binary_path() { return 1; }' if missing_timeout else ':',
            shlex.join([check_name, *args]),
            'printf \'[%s]\\n\' "$(IFS=,; echo "${JSON_CHECKS[*]}")"',
            'printf \'%s\\n\' "${#DOCTOR_FIX_PENDING_IDS[@]}"',
        ])

    def run_doctor_live_check(self, check_name: str, body: str, *, timeout=9, missing_timeout=False, args=()):
        code = self.doctor_live_check_code(check_name, body, missing_timeout=missing_timeout, args=args)
        result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                text=True, timeout=timeout)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(len(lines), 2, result.stdout)
        return json.loads(lines[0]), int(lines[1])

    def test_interrupted_live_cloud_auth_never_passes_caches_or_queues_repair(self):
        for check_name in ("check_gh_auth", "check_wrangler_auth", "check_vercel_auth"):
            for status in (124, 137, 143):
                with self.subTest(check=check_name, status=status):
                    checks, repairs = self.run_doctor_live_check(
                        check_name, f"printf 'unverified provider output\\n'; exit {status}")
                    self.assertEqual(len(checks), 1, checks)
                    self.assertEqual(checks[0]["status"], "timeout", checks)
                    self.assertEqual(repairs, 0)
                    self.assertFalse(self.cache_marker.exists(), "Interrupted auth was cached")

    def test_vercel_live_probe_kills_grandchild_without_using_saved_auth_as_pass(self):
        fixture, stop, identity = self.wrapper_with_resistant_grandchild()
        try:
            checks, repairs = self.run_doctor_live_check(
                "check_vercel_auth", "exec /usr/bin/python3 " + shlex.quote(str(fixture)))
            self.assertEqual(checks[0]["status"], "timeout", checks)
            self.assertEqual(repairs, 0)
            self.assertFalse(self.cache_marker.exists())
            self.assert_child_stopped(identity)
        finally:
            stop.touch()

    def test_live_cloud_auth_success_still_caches_verified_identity(self):
        for check_name in ("check_gh_auth", "check_wrangler_auth", "check_vercel_auth"):
            with self.subTest(check=check_name):
                checks, repairs = self.run_doctor_live_check(check_name, "printf 'fixture-user\\n'")
                self.assertEqual(checks[0]["status"], "pass", checks)
                self.assertEqual(repairs, 0)
                self.assertIn("fixture-user" if check_name != "check_wrangler_auth" else "authenticated",
                              self.cache_marker.read_text())

    def test_optional_operational_timeout_cannot_be_hidden_by_a_version_fallback(self):
        marker = self.root / "version-fallback-ran"
        for status in (124, 137, 143):
            with self.subTest(status=status):
                checks, repairs = self.run_doctor_live_check(
                    "deep_check_optional_probe", "exit 0", args=(
                        "deep.stack.rch", "RCH readiness", "rch", "Review RCH configuration",
                        f"exit {status}", "printf 'version' > " + shlex.quote(str(marker))))
                self.assertEqual(checks[0]["status"], "timeout", checks)
                self.assertEqual(repairs, 0)
                self.assertFalse(marker.exists())
                self.assertFalse(self.cache_marker.exists())

    def test_optional_unsupported_probe_still_uses_a_successful_fallback(self):
        checks, repairs = self.run_doctor_live_check(
            "deep_check_optional_probe", "exit 0", args=(
                "deep.stack.rch", "RCH readiness", "rch", "Review RCH configuration",
                "exit 2", "printf 'fixture-ready\\n'"))
        self.assertEqual(checks[0]["status"], "pass", checks)
        self.assertEqual(repairs, 0)
        self.assertIn("fixture-ready", self.cache_marker.read_text())

    def test_doctor_version_missing_timeout_never_executes_unbounded_command(self):
        marker = self.root / "unbounded-version"
        code = doctor_definitions("doctor_version_probe") + \
            "\ndoctor_version_probe '' 1 discard /usr/bin/touch " + shlex.quote(str(marker))
        result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                text=True, timeout=3)
        self.assertEqual(result.stdout, "")
        self.assertFalse(marker.exists(), "Version probe ran without a timeout guardian")

    def test_doctor_rejects_deadlines_that_disable_or_reinterpret_timeout(self):
        for kind in ("version", "deep"):
            for index, deadline in enumerate(("0", "0.000", "-1", "--help", "NaN", "1h")):
                with self.subTest(kind=kind, deadline=deadline):
                    marker = self.root / f"doctor-invalid-deadline-{kind}-{index}"
                    code = self.bounded_probe(kind, ["/usr/bin/touch", str(marker)],
                                              deadline=shlex.quote(deadline))
                    result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                            text=True, timeout=3)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(marker.exists())

    def onboard_auth_check(self, service: str, body: str, *, stdin=""):
        home = self.root / "onboard-home"
        home.mkdir(exist_ok=True)
        fixture = self.root / "provider probe"
        fixture.write_text("#!/bin/bash\n" + body + "\n")
        fixture.chmod(0o755)
        # Provider discovery is the fixture boundary; the shipped auth checks,
        # credential parsing, timeout process group and stdin isolation are real.
        code = "\n".join([
            "source " + shlex.quote(str(ROOT / "packages/onboard/onboard.sh")),
            "onboard_effective_runtime_home() { printf '%s\\n' " + shlex.quote(str(home)) + "; }",
            "onboard_runtime_binary_path() { printf '%s\\n' " + shlex.quote(str(fixture)) + "; }",
            "check_auth_status " + shlex.quote(service),
        ])
        env = dict(os.environ)
        for name in ("VERCEL_TOKEN", "SUPABASE_ACCESS_TOKEN", "CLOUDFLARE_API_TOKEN"):
            env.pop(name, None)
        env.update(TARGET_HOME=str(home), ACFS_HOME=str(self.acfs),
                   ACFS_SYSTEM_STATE_FILE=str(self.root / "absent-state.json"))
        # Trusted test fixture; source path and service are quoted. ubs:ignore[py.security.command-injection]
        return subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                              text=True, input=stdin, timeout=9, env=env)

    def test_onboard_live_auth_rejects_failed_commands_with_success_shaped_output(self):
        for service, output in (("tailscale", '{"BackendState":"Running"}'),
                                ("github", "Logged in to github.com"),
                                ("vercel", "fixture-user"),
                                ("cloudflare", "You are logged in with an OAuth Token")):
            with self.subTest(service=service):
                result = self.onboard_auth_check(service, "printf '%s\\n' " + shlex.quote(output) + "\nexit 1")
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(result.stdout, "", "Raw provider output must stay private")

    def test_onboard_cloudflare_rejects_success_exit_when_not_authenticated(self):
        result = self.onboard_auth_check("cloudflare", "printf '%s\\n' 'You are not authenticated. Please run wrangler login.'")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_onboard_live_auth_requires_nonblank_identity_output(self):
        for service in ("vercel", "cloudflare"):
            with self.subTest(service=service):
                result = self.onboard_auth_check(service, "printf '  \\n\\t\\n'")
                self.assertEqual(result.returncode, 1, result.stderr)

    def test_onboard_live_auth_deadline_never_accepts_early_identity_output(self):
        # Exercise the shipped five-second deadline, including escalation when
        # the actual provider process ignores TERM after printing an identity.
        started = time.monotonic()
        result = self.onboard_auth_check("vercel", "trap '' TERM\nprintf 'fixture-user\\n'\nsleep 30")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertLess(time.monotonic() - started, 8)
        self.assertEqual(result.stdout, "")

    def test_onboard_probe_bounds_descendants_after_provider_exits_normally(self):
        # A successful parent can leave an inherited output pipe open. The
        # complete capture still needs a deadline, not just the parent's wait.
        fixture = self.root / "early-exit-provider.py"
        fixture.write_text("import subprocess,sys\n"
                           "subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(10)'])\n"
                           "print('fixture-user')\n")
        code = self.bounded_probe("onboard", ["/usr/bin/python3", str(fixture)], deadline="0.1")
        started = time.monotonic()
        # Repository helper and shell-quoted fixture path. ubs:ignore[py.security.command-injection]
        result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                text=True, timeout=4)
        self.assertIn(result.returncode, (124, 137), result.stderr)
        self.assertLess(time.monotonic() - started, 3)
        self.assertEqual(result.stdout, "fixture-user\n")

    def test_onboard_live_auth_probes_once_without_consuming_menu_input(self):
        for service, output in (("tailscale", '{"BackendState":"Running"}'),
                                ("github", "Logged in to github.com"),
                                ("vercel", "fixture-user"),
                                ("cloudflare", "You are logged in with an OAuth Token")):
            with self.subTest(service=service):
                captured = self.root / (service + "-stdin")
                calls = self.root / (service + "-calls")
                body = "\n".join([
                    "IFS= read -r answer || true",
                    "printf '%s' \"$answer\" > " + shlex.quote(str(captured)),
                    "printf 'called\\n' >> " + shlex.quote(str(calls)),
                    "printf '%s\\n' " + shlex.quote(output),
                ])
                result = self.onboard_auth_check(service, body, stdin="m\n")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(captured.read_text(), "", "Provider consumed the user's menu choice")
                self.assertEqual(calls.read_text(), "called\n")
                self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
