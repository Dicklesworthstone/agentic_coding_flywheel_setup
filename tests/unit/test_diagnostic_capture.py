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
import unittest


ROOT = Path(__file__).resolve().parents[2]


def definition(path: Path, name: str) -> str:
    match = re.search(r"^" + re.escape(name) + r"\(\) \{\n.*?^\}",
                      path.read_text(), re.M | re.S)
    if match is None:
        raise AssertionError(f"Missing production function: {name}")
    return match[0]


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
        probe = definition(ROOT / "scripts/lib/doctor.sh", "doctor_version_probe")
        for mode, expected in (("merge", "fixture version"), ("discard", "")):
            with self.subTest(mode=mode):
                code = probe + "\ndoctor_version_probe /usr/bin/timeout 1 " + mode + \
                    " /bin/bash -c 'printf \"fixture version\\nsecond line\\n\" >&2'"
                result = subprocess.run(["/bin/bash", "-c", code], capture_output=True,
                                        text=True, timeout=3)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)

    def test_version_probe_kills_term_ignoring_process(self):
        probe = definition(ROOT / "scripts/lib/doctor.sh", "doctor_version_probe")
        fixture = self.root / "stubborn.py"
        group = self.root / "process-group"
        fixture.write_text("import os,signal,time\nfrom pathlib import Path\n"
                           "signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
                           f"Path({str(group)!r}).write_text(str(os.getpgrp()))\n"
                           "time.sleep(30)\n")
        code = "set -o pipefail\n" + probe + \
            "\ndoctor_version_probe /usr/bin/timeout 0.1 discard /usr/bin/python3 " + shlex.quote(str(fixture))
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
