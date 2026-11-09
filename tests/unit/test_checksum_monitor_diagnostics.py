#!/usr/bin/env python3
"""Exercise the real offline monitor diagnostics CLI without changing evidence.

All inputs are synthetic. Fixtures and command receipts are retained for
inspection; no installer body or retained shell fragment is ever executed.
"""

import copy
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]
MONITOR = REPO / "scripts/checksum-monitor-local.sh"
RUN = "20261108T110101Z"
OTHER_RUN = "20261108T111601Z"
ERROR_SECRET = "ACFS_TEST_PRIVATE_FETCH_ERROR_17a6c9"
LOG_SECRET = "ACFS_TEST_PRIVATE_LOG_REASON_34acb1"
URL_SECRET = "ACFS_TEST_PRIVATE_URL_TOKEN_b49f06"
BODY_SECRET = "ACFS_TEST_PRIVATE_BODY_7a8051"
HEADER_SECRET = "ACFS_TEST_PRIVATE_COOKIE_ace91f"
AUTH_SECRET = "ACFS_TEST_PRIVATE_AUTHORIZATION_f2f41d"
SECRETS = (ERROR_SECRET, LOG_SECRET, URL_SECRET, BODY_SECRET, HEADER_SECRET, AUTH_SECRET)


def private_file(path, value, mode=0o600):
    path.write_bytes(value.encode() if isinstance(value, str) else value)
    path.chmod(mode)


def encoded(value):
    return (json.dumps(value, separators=(",", ":"), ensure_ascii=False) + "\n").encode()


def sha(value):
    return hashlib.sha256(value).hexdigest()


def tree_state(root):
    """Fingerprint evidence identities and contents without following links."""
    result = {}

    def visit(path):
        info = path.lstat()
        kind = stat.S_IFMT(info.st_mode)
        identity = (kind, stat.S_IMODE(info.st_mode), info.st_uid, info.st_gid,
                    info.st_ino, info.st_nlink, info.st_size, info.st_mtime_ns)
        if stat.S_ISREG(info.st_mode):
            content = sha(path.read_bytes())
        elif stat.S_ISLNK(info.st_mode):
            content = os.readlink(path)
        else:
            content = None
        result[str(path.relative_to(root))] = (identity, content)
        if stat.S_ISDIR(info.st_mode):
            for child in sorted(path.iterdir()):
                visit(child)

    if root.exists() or root.is_symlink():
        visit(root)
    return result


class RunFixture:
    def __init__(self, parent, *, state=True, log=True, report=True, downloads=True):
        self.root = Path(tempfile.mkdtemp(prefix="run-", dir=parent))
        self.root.chmod(0o700)
        self.home = self.root / "home"
        self.state = self.home / "monitor-state"
        self.repo = self.root / "repo"
        self.tmp = self.root / "tmp"
        self.receipts = self.root / "receipts"
        self.unsafe = self.root / "unsafe-fixtures"
        for directory in (self.home, self.repo, self.tmp, self.receipts, self.unsafe):
            directory.mkdir(mode=0o700)
        self.executed = self.root / "unexpected-execution"
        self.calls = 0
        self.log = self.state / "logs" / f"run-{RUN}.log"
        self.report = self.state / f"verify-{RUN}.Abc123.json"
        self.downloads = self.state / f"downloads-{RUN}.Def456"
        self.observations = self.downloads / "acfs-observations.Ghi789"
        self.policy_digest = "1" * 64
        self.match_digest = "2" * 64
        self.expected_digest = "3" * 64
        self.actual_digest = "4" * 64
        self.url = "https://example.invalid/install.sh?token=" + URL_SECRET
        self.error = "curl: (22) private response: " + ERROR_SECRET
        self.document = {
            "schema": "acfs.installer-checksum-verification.v1", "schemaVersion": 1,
            "timestamp": "2026-11-08T11:01:01Z", "checksumsYamlSha256": self.policy_digest,
            "total": 3,
            "matches": [{"name": "alpha", "url": "https://example.invalid/alpha.sh",
                         "checksum": self.match_digest}],
            "mismatches": [{"name": "beta", "url": "https://example.invalid/beta.sh",
                            "expected": self.expected_digest, "actual": self.actual_digest}],
            "errors": [{"name": "gamma", "url": self.url, "error": self.error}],
            "skipped": [],
        }
        private_file(self.repo / "checksums.yaml", "installers: {}\n", 0o644)
        private_file(self.repo / "tracked-sentinel", "repository must remain unchanged\n")
        if not state:
            return
        self.state.mkdir(mode=0o700)
        private_file(self.state / "authorized-checksum-change", AUTH_SECRET + "\n")
        private_file(self.state / "fail_closed_streak", "3\n")
        private_file(self.state / "fail_closed_alert", "opaque existing alert\n")
        private_file(self.state / "fail_closed_recovery_pending", "7\n")
        if report:
            self.write_report()
        if log:
            self.log.parent.mkdir(mode=0o755)
            self.write_log()
        if downloads:
            self.observations.mkdir(mode=0o700, parents=True)
            self.downloads.chmod(0o700)
            tool = self.observations / "gamma"
            tool.mkdir(mode=0o700)
            private_file(tool / "fetch-stderr.Jkl012", self.error + "\n")
            private_file(tool / "body.headers", "HTTP/2 403\r\nSet-Cookie: " + HEADER_SECRET + "\r\n\r\n")
            private_file(tool / "body", "#!/bin/sh\n# " + BODY_SECRET + "\nexit 87\n")

    def write_report(self):
        private_file(self.report, encoded(self.document))

    def write_log(self, reason=None):
        report_sha = sha(encoded(self.document))
        reason = reason or "verification returned 1 error(s) / 0 skip(s); refusing to auto-update checksums.yaml"
        text = ("[11:01:01] state=LOCKED\n"
                "[11:01:01] ACFS checksum monitor starting (repo: " + str(self.repo) + ")\n"
                "[11:01:02] state=CLEAN_BASE\n"
                "[11:01:02] clean base pinned to " + "a" * 40 + "\n"
                "[11:02:00] verification evidence: run=" + RUN + " exit=1 report="
                + str(self.report) + " downloads=" + str(self.downloads) + "\n"
                "[11:02:00] verification binding: policy_sha256=" + self.policy_digest
                + " report_sha256=" + report_sha + "\n"
                "  error: gamma -> " + self.error + "\n"
                "[11:02:01] FAIL-CLOSED: " + reason + "\n"
                "[11:02:01] summary: result=fail_closed state=CLEAN_BASE streak=3 repo="
                + str(self.repo) + "\n")
        private_file(self.log, text, 0o644)


class DiagnosticsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(tempfile.mkdtemp(prefix="acfs-monitor-diagnostics-tests-"))
        cls.root.chmod(0o700)
        cls.cli_cases = 0
        print(f"Retaining monitor diagnostic fixtures: {cls.root}", file=sys.stderr)

    @classmethod
    def tearDownClass(cls):
        print(f"Actual monitor diagnostic CLI invocations: {cls.cli_cases}; retained at {cls.root}", file=sys.stderr)

    def fixture(self, **kwargs):
        return RunFixture(self.root, **kwargs)

    def invoke(self, fx, args=None, *, private=False, environment=None, state=None, trace=False):
        observed = (fx.home, fx.repo, fx.tmp, fx.unsafe)
        before = [tree_state(path) for path in observed]
        arguments = ["--diagnose", RUN] if args is None else args
        if private:
            arguments = [*arguments, "--include-private-details"]
        command = ["/bin/bash", str(MONITOR), *arguments]
        fx.calls += 1
        trace_path = fx.receipts / f"cli-{fx.calls}.trace"
        if trace:
            tracer = shutil.which("strace")
            self.assertIsNotNone(tracer, "strace is required for the native no-network proof")
            command = [tracer, "-f", "-qq", "-s", "4096", "-e", "trace=network,process",
                       "-o", str(trace_path), *command]
        env = {"HOME": str(fx.home), "USER": "diagnostic-test", "LOGNAME": "diagnostic-test",
               "PATH": "/usr/bin:/bin", "TMPDIR": str(fx.tmp), "LANG": "C", "LC_ALL": "C", "TZ": "UTC",
               "ACFS_MONITOR_STATE": str(state or fx.state), "ACFS_MONITOR_REPO": str(fx.repo)}
        if environment:
            env.update(environment)
        type(self).cli_cases += 1
        process = subprocess.Popen(command, cwd=fx.root, env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        timed_out = False
        try:
            stdout, stderr = process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            timed_out = True
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            stdout, stderr = process.communicate()
        private_file(fx.receipts / f"cli-{fx.calls}.stdout", stdout)
        private_file(fx.receipts / f"cli-{fx.calls}.stderr", stderr)
        self.assertFalse(timed_out, "read-only diagnosis blocked; inspect retained receipts")
        for path, snapshot in zip(observed, before):
            self.assertEqual(tree_state(path), snapshot, f"diagnosis mutated {path.name}")
        self.assertFalse(fx.executed.exists(), "diagnosis executed retained content or an ambient hook")
        if not private:
            for secret in SECRETS:
                self.assertNotIn(secret.encode(), stdout + stderr, "default diagnostic output disclosed private content")
            self.assertNotIn(str(fx.home).encode(), stdout + stderr, "default diagnostic output disclosed the home path")
        return subprocess.CompletedProcess(command, process.returncode, stdout, stderr), trace_path

    def inspected(self, fx, **kwargs):
        result, trace = self.invoke(fx, **kwargs)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace")[-2000:])
        self.assertEqual(len(result.stdout.splitlines()), 1, "diagnostics must emit one JSON document")
        document = json.loads(result.stdout)
        self.assertEqual(document["schema"], "acfs.checksum-monitor-diagnostics.v1")
        self.assertEqual(document["run_id"], RUN)
        self.assertIs(document["diagnostic_only"], True)
        self.assertIs(document["publication_authorized"], False)
        self.assertEqual(document["current_health"], "unknown")
        self.assertIs(document["private_details_included"], kwargs.get("private", False))
        self.assertNotIn("authorization_line", document)
        self.assertNotIn(b"authorize:", result.stdout)
        self.assertNotIn(b"authorize-subset:", result.stdout)
        return document, trace

    def refused(self, fx, *, code=None, **kwargs):
        result, _ = self.invoke(fx, **kwargs)
        self.assertEqual(result.returncode, 2, result.stderr.decode(errors="replace")[-2000:])
        document = json.loads(result.stdout)
        self.assertIs(document["diagnostic_only"], True)
        self.assertIs(document["publication_authorized"], False)
        if code:
            self.assertEqual(document["error"]["code"], code)
        self.assertNotIn("counts", document.get("verification", {}))
        return document

    def test_partial_failure_keeps_errors_distinct_from_checksum_changes(self):
        fx = self.fixture()
        data, _ = self.inspected(fx)
        self.assertEqual(data["log"]["recorded_result"], "fail_closed")
        self.assertEqual(data["log"]["recorded_state"], "CLEAN_BASE")
        self.assertEqual(data["log"]["recorded_base_commit"], "a" * 40)
        self.assertEqual(data["log"]["failure_category"], "verification_items")
        self.assertEqual(data["verification"]["status"], "inspected")
        self.assertEqual(data["verification"]["counts"],
                         {"matches": 1, "mismatches": 1, "errors": 1, "skipped": 0, "total": 3})
        self.assertEqual(data["verification"]["errors"], [{"name": "gamma"}])
        self.assertEqual(data["verification"]["mismatches"],
                         [{"name": "beta", "expected": fx.expected_digest, "actual": fx.actual_digest}])
        self.assertEqual(data["verification"]["sha256"], sha(fx.report.read_bytes()))
        self.assertEqual(data["verification"]["bytes"], len(fx.report.read_bytes()))
        self.assertEqual(data["verification"]["logged_report_binding"], "matches")
        self.assertEqual(data["verification"]["logged_policy_binding"], "matches")
        self.assertEqual(data["downloads"]["status"], "present")
        self.assertNotIn("failure_reason", data["log"])
        self.assertFalse(list(fx.downloads.glob("evidence-index.*")), "fixture accidentally supplied a completed index")

    def test_private_details_opt_in_returns_exact_report_errors_only(self):
        fx = self.fixture()
        fx.document["errors"][0]["error"] += "\n\t\"quoted\" \u001b[31m $(not-a-command)"
        fx.write_report()
        fx.write_log("verification returned 1 error(s) / 0 skip(s); " + LOG_SECRET)
        data, _ = self.inspected(fx, private=True)
        self.assertEqual(data["verification"]["errors"],
                         [{"name": "gamma", "description": fx.document["errors"][0]["error"]}])
        self.assertIn(LOG_SECRET, data["log"]["failure_reason"])
        serialized = json.dumps(data)
        for secret in (URL_SECRET, HEADER_SECRET, BODY_SECRET, AUTH_SECRET):
            self.assertNotIn(secret, serialized, "private details included unrelated secrets")

    def test_skipped_items_remain_explicit_and_non_authorizing(self):
        fx = self.fixture()
        fx.document["skipped"].append({"name": "delta", "url": "", "reason": ERROR_SECRET})
        fx.document["total"] = 4
        fx.write_report()
        fx.write_log()
        data, _ = self.inspected(fx)
        self.assertEqual(data["verification"]["counts"]["skipped"], 1)
        self.assertEqual(data["verification"]["skipped"], [{"name": "delta"}])
        data, _ = self.inspected(fx, private=True)
        self.assertEqual(data["verification"]["skipped"], [{"name": "delta", "description": ERROR_SECRET}])

    def test_early_failures_need_neither_report_nor_download_index(self):
        reasons = {
            "remote main and legacy mirror differ before observation": "configuration",
            "pinned base already contains generated drift; repair it independently before checksum publication": "generated_artifact_drift",
            "checksum verification returned data outside its strict bound report contract": "verification_contract",
        }
        for reason, category in reasons.items():
            with self.subTest(category=category):
                fx = self.fixture(report=False, downloads=False)
                private_file(fx.log,
                             "[11:01:01] ACFS checksum monitor starting (repo: " + str(fx.repo) + ")\n"
                             "[11:01:02] state=LOCKED\n"
                             "[11:01:03] FAIL-CLOSED: " + reason + "\n"
                             "[11:01:03] summary: result=fail_closed state=LOCKED streak=3 repo="
                             + str(fx.repo) + "\n", 0o644)
                data, _ = self.inspected(fx)
                self.assertEqual(data["log"]["recorded_result"], "fail_closed")
                self.assertEqual(data["log"]["failure_category"], category)
                self.assertEqual(data["verification"]["status"], "missing")
                self.assertEqual(data["downloads"]["status"], "missing")

    def test_state_storage_failures_keep_legacy_incident_classification(self):
        reasons = (
            "could not open monitor lock file",
            "could not open a safe monitor lock file",
            "could not open a safe monitor log file",
            "monitor lock path changed or became unsafe while acquiring it",
            "remote publication is verified but failure-count state could not be safely read",
            "remote publication is verified but the healthy-state marker could not be written",
        )
        for reason in reasons:
            with self.subTest(reason=reason):
                fx = self.fixture(report=False, downloads=False)
                state = "REMOTE_VERIFIED" if reason.startswith("remote publication") else "INIT"
                private_file(fx.log,
                             "[11:01:01] FAIL-CLOSED: " + reason + "\n"
                             "[11:01:01] summary: result=fail_closed state=" + state + " streak=unknown\n",
                             0o644)
                data, _ = self.inspected(fx)
                self.assertEqual(data["log"]["failure_category"], "state_storage")
                self.assertEqual(data["log"]["recorded_result"], "fail_closed")
                self.assertEqual(data["log"]["recorded_state"], state)
                self.assertNotIn("state_refusal", data["log"])

    def test_typed_primary_state_refusal_survives_secondary_failures(self):
        fx = self.fixture(report=False, downloads=False)
        reason = ("could not open a safe monitor lock file " + LOG_SECRET
                  + " [state_refusal=lock_file.symlink]")
        private_file(fx.log,
                     "[11:01:01] WARNING: failure count could not be persisted "
                     "[count_refusal=failure_counter.multiple_links]\n"
                     "[11:01:01] WARNING: log unavailable [state_refusal=log_file.wrong_type]\n"
                     "[11:01:01] FAIL-CLOSED: " + reason + "\n"
                     "[11:01:01] summary: result=fail_closed state=INIT streak=unknown\n",
                     0o644)
        for private in (False, True):
            with self.subTest(private=private):
                data, _ = self.inspected(fx, private=private)
                self.assertEqual(data["log"]["state_refusal"],
                                 {"component": "lock_file", "reason": "symlink"})
                self.assertEqual(data["log"]["failure_category"], "state_storage")
                self.assertNotIn("invalid_state_refusal", data["warnings"])
                if private:
                    self.assertEqual(data["log"]["failure_reason"], reason)
                else:
                    self.assertNotIn("failure_reason", data["log"])

    def test_unknown_or_ambiguous_state_refusal_does_not_invent_a_cause(self):
        markers = (
            "[state_refusal=untrusted.symlink]",
            "[state_refusal=lock_file." + LOG_SECRET + "]",
            "[state_refusal=LOCK_FILE.symlink]",
            "[state_refusal=lock_file.symlink",
            "[state_refusal=state_record.unclassified]",
            "[state_refusal=lock_file.symlink] [state_refusal=log_file.wrong_type]",
            "[state_refusal=lock_file.symlink] [state_refusal=lock_file.symlink]",
        )
        for marker in markers:
            with self.subTest(marker=marker):
                fx = self.fixture(report=False, downloads=False)
                private_file(fx.log,
                             "[11:01:01] FAIL-CLOSED: could not open a safe monitor lock file "
                             + marker + "\n"
                             "[11:01:01] summary: result=fail_closed state=INIT streak=unknown\n",
                             0o644)
                data, _ = self.inspected(fx)
                self.assertEqual(data["log"]["failure_category"], "state_storage")
                self.assertNotIn("state_refusal", data["log"])
                self.assertIn("invalid_state_refusal", data["warnings"])

    def test_state_refusal_markers_do_not_override_outcome_consistency(self):
        for inconsistent in (False, True):
            with self.subTest(inconsistent=inconsistent):
                fx = self.fixture(report=False, downloads=False)
                prefix = "FAIL-CLOSED: " if inconsistent else "WARNING: "
                private_file(fx.log,
                             "[11:01:01] " + prefix + "could not open a safe monitor log file "
                             "[state_refusal=log_file.wrong_type]\n"
                             "[11:01:02] state=HEALTHY\n"
                             "[11:01:02] summary: result=ok state=HEALTHY\n",
                             0o644)
                data, _ = self.inspected(fx)
                if inconsistent:
                    self.assertEqual(data["log"]["recorded_result"], "unknown")
                    self.assertIn("incomplete_log", data["warnings"])
                    self.assertEqual(data["log"]["state_refusal"],
                                     {"component": "log_file", "reason": "wrong_type"})
                else:
                    self.assertEqual(data["log"]["recorded_result"], "ok")
                    self.assertNotIn("state_refusal", data["log"])

    def test_historical_accepted_results_do_not_establish_current_health(self):
        for state, outcome in (("HEALTHY", "ok"), ("DEFERRED", "deferred")):
            with self.subTest(state=state):
                fx = self.fixture()
                private_file(fx.log,
                             "[11:01:01] ACFS checksum monitor starting (repo: " + str(fx.repo) + ")\n"
                             "[11:02:01] state=" + state + "\n"
                             "[11:02:01] summary: result=" + outcome + " state=" + state
                             + " base=" + "a" * 40 + " published=" + "a" * 40 + "\n", 0o644)
                data, _ = self.inspected(fx)
                self.assertEqual(data["log"]["recorded_state"], state)
                self.assertEqual(data["log"]["recorded_result"], outcome)
                self.assertEqual(data["current_health"], "unknown")

    def test_missing_state_is_reported_without_creating_it(self):
        fx = self.fixture(state=False)
        self.refused(fx, code="unavailable")
        self.assertFalse(fx.state.exists())

    def test_missing_run_artifacts_are_not_replaced_with_latest_run(self):
        fx = self.fixture(log=False, report=False, downloads=False)
        (fx.state / "logs").mkdir(mode=0o755)
        private_file(fx.state / "logs" / f"run-{OTHER_RUN}.log", LOG_SECRET + "\n", 0o644)
        private_file(fx.state / f"verify-{OTHER_RUN}.Abc123.json", encoded(fx.document))
        data, _ = self.inspected(fx)
        self.assertEqual(data["log"]["status"], "missing")
        self.assertEqual(data["verification"]["status"], "missing")
        self.assertEqual(data["downloads"]["status"], "missing")

    def test_cli_rejects_wrong_arguments_before_any_state_changes(self):
        cases = [
            ["--diagnose"], ["--diagnose", "latest"], ["--diagnose", "../outside"],
            ["--diagnose", "20260230T110101Z"], ["--diagnose", "20261108T250101Z"],
            ["--diagnose", RUN, "--unknown"], ["--diagnose", RUN, "--include-private-details", "extra"],
            ["--include-private-details"], ["--dry-run"], ["--diagnose", RUN, "--diagnose", RUN],
        ]
        for arguments in cases:
            with self.subTest(arguments=arguments):
                fx = self.fixture(state=False)
                self.refused(fx, args=arguments, code="invalid_arguments")
                self.assertFalse(fx.state.exists())

    def test_help_does_not_initialize_monitor_state(self):
        fx = self.fixture(state=False)
        result, _ = self.invoke(fx, ["--help"])
        self.assertEqual(result.returncode, 0)
        self.assertIn(b"--diagnose", result.stdout)
        self.assertFalse(fx.state.exists())

    def test_multiple_reports_are_ambiguous_instead_of_selected_by_timestamp(self):
        fx = self.fixture()
        second = fx.state / f"verify-{RUN}.Zyx987.json"
        forged = copy.deepcopy(fx.document)
        forged["errors"][0]["name"] = "different_tool"
        private_file(second, encoded(forged))
        data, _ = self.inspected(fx)
        self.assertEqual(data["verification"]["status"], "ambiguous")
        self.assertEqual(set(data["verification"]["candidates"]), {fx.report.name, second.name})
        self.assertNotIn("counts", data["verification"])
        self.assertNotIn("errors", data["verification"])

    def test_multiple_downloads_and_repeated_log_runs_are_ambiguous(self):
        fx = self.fixture()
        second = fx.state / f"downloads-{RUN}.Zyx987"
        second.mkdir(mode=0o700)
        private_file(fx.log, fx.log.read_bytes() * 2, 0o644)
        data, _ = self.inspected(fx, private=True)
        self.assertEqual(data["downloads"]["status"], "ambiguous")
        self.assertEqual(data["log"]["status"], "ambiguous")
        self.assertEqual(data["log"]["recorded_result"], "unknown")
        self.assertIsNone(data["log"]["recorded_state"])
        self.assertNotIn("failure_reason", data["log"])

    def test_diagnostic_binding_mismatch_does_not_hide_report(self):
        fx = self.fixture()
        fx.document["errors"][0]["error"] = "a different captured fetch error"
        fx.write_report()
        data, _ = self.inspected(fx)
        self.assertEqual(data["verification"]["status"], "inspected")
        self.assertEqual(data["verification"]["logged_report_binding"], "differs")
        self.assertEqual(data["verification"]["logged_policy_binding"], "matches")
        fx.document["checksumsYamlSha256"] = "9" * 64
        fx.write_report()
        data, _ = self.inspected(fx)
        self.assertEqual(data["verification"]["logged_policy_binding"], "differs")

    def test_conflicting_or_duplicated_base_records_remain_ambiguous(self):
        for digest in ("a" * 40, "b" * 40):
            with self.subTest(digest=digest):
                fx = self.fixture()
                private_file(fx.log, fx.log.read_text() + "[11:02:02] clean base pinned to " + digest + "\n", 0o644)
                data, _ = self.inspected(fx)
                self.assertIsNone(data["log"]["recorded_base_commit"])
                self.assertIn("ambiguous_base_commit_records", data["warnings"])

    def test_inconsistent_log_cannot_claim_an_accepted_run(self):
        for kind in ("state-after-summary", "failure-before-accepted-summary"):
            with self.subTest(kind=kind):
                fx = self.fixture()
                if kind == "state-after-summary":
                    text = fx.log.read_text() + "[11:02:02] state=OBSERVED\n"
                else:
                    text = ("[11:01:01] ACFS checksum monitor starting (repo: " + str(fx.repo) + ")\n"
                            "[11:01:01] state=LOCKED\n"
                            "[11:01:02] FAIL-CLOSED: checksum verification returned data outside its strict bound report contract\n"
                            "[11:01:03] state=HEALTHY\n"
                            "[11:01:03] summary: result=ok state=HEALTHY\n")
                private_file(fx.log, text, 0o644)
                data, _ = self.inspected(fx)
                self.assertEqual(data["log"]["recorded_result"], "unknown")
                self.assertIn("incomplete_log", data["warnings"])

    def test_retained_policy_locator_does_not_parse_or_disclose_policy_bytes(self):
        fx = self.fixture()
        snapshot = fx.downloads / "acfs-checksums-policy.Mno345"
        private_file(snapshot, "opaque retained bytes\n" + BODY_SECRET + "\n")
        data, _ = self.inspected(fx)
        self.assertEqual(data["downloads"]["policy_snapshots"], [fx.downloads.name + "/" + snapshot.name])
        self.assertEqual(data["downloads"]["observation_roots"],
                         [fx.downloads.name + "/" + fx.observations.name])
        self.assertEqual(data["verification"]["counts"]["errors"], 1)

    def test_nested_evidence_locators_require_safe_metadata(self):
        cases = (("snapshot", "symlink"), ("snapshot", "hardlink"), ("snapshot", "fifo"),
                 ("snapshot", "mode"), ("observation", "symlink"), ("observation", "file"))
        for role, kind in cases:
            with self.subTest(role=role, kind=kind):
                fx = self.fixture()
                if role == "snapshot":
                    path = fx.downloads / "acfs-checksums-policy.Mno345"
                    private_file(path, "opaque retained policy\n")
                else:
                    path = fx.observations
                if kind == "mode":
                    path.chmod(0o644)
                elif kind == "hardlink":
                    os.link(path, fx.unsafe / "linked-policy")
                else:
                    original = fx.unsafe / "original-locator"
                    path.rename(original)
                    if kind == "symlink":
                        path.symlink_to(original, target_is_directory=role == "observation")
                    elif kind == "fifo":
                        os.mkfifo(path, 0o600)
                    else:
                        private_file(path, "not a directory\n")
                self.refused(fx, code="unsafe_input")

    def test_log_locators_never_redirect_reads_outside_selected_state(self):
        fx = self.fixture()
        outside = fx.unsafe / "stolen.json"
        forged = copy.deepcopy(fx.document)
        forged["errors"][0]["error"] = "outside file must not be inspected"
        private_file(outside, encoded(forged))
        text = fx.log.read_text().replace(str(fx.report), str(outside))
        text = text.replace(str(fx.downloads), str(fx.unsafe))
        private_file(fx.log, text, 0o644)
        data, _ = self.inspected(fx, private=True)
        self.assertEqual(data["verification"]["errors"][0]["description"], fx.error)
        self.assertNotIn("stolen.json", json.dumps(data))

    def test_invalid_json_and_partition_contracts_are_explicit(self):
        bad_documents = [
            b"", b"{", b"[]\n", b"\xff\n", b'{"schema":NaN}\n',
            encoded(self.fixture().document) + b"{}\n",
            b'{"schema":"one","schema":"two"}\n', b"[" * 2000 + b"]" * 2000,
        ]
        for mutation in (
            lambda doc: doc.update(total=True),
            lambda doc: doc.update(total=2),
            lambda doc: doc.update(total="3"),
            lambda doc: doc.update(schemaVersion=True),
            lambda doc: doc.update(schema="other.schema"),
            lambda doc: doc.update(errors="not-an-array"),
            lambda doc: doc["errors"][0].update(name="../outside"),
            lambda doc: doc["errors"][0].update(name="alpha"),
            lambda doc: doc["errors"][0].update(error={"not": "text"}),
            lambda doc: doc["mismatches"][0].update(actual="3" * 64),
            lambda doc: doc["matches"][0].update(checksum="Z" * 64),
            lambda doc: doc.update(timestamp="2026-02-30T11:01:01Z"),
            lambda doc: doc.update(unreviewedField="opaque"),
        ):
            fx = self.fixture()
            changed = copy.deepcopy(fx.document)
            mutation(changed)
            bad_documents.append(encoded(changed))
        for index, value in enumerate(bad_documents):
            with self.subTest(index=index):
                fx = self.fixture()
                private_file(fx.report, value)
                data, _ = self.inspected(fx)
                self.assertEqual(data["verification"]["status"], "invalid")
                self.assertEqual(data["verification"]["sha256"], sha(value))
                self.assertNotIn("counts", data["verification"])
                self.assertNotIn("errors", data["verification"])

    def test_valid_clock_skew_is_visible_without_fabricating_integrity(self):
        fx = self.fixture()
        fx.document["timestamp"] = "2026-11-07T11:01:01Z"
        fx.write_report()
        data, _ = self.inspected(fx)
        self.assertEqual(data["verification"]["status"], "inspected")
        self.assertIn("report_timestamp_outside_run_window", data["warnings"])

    def test_byte_and_candidate_limits_fail_promptly(self):
        for kind in ("report", "log", "candidates"):
            with self.subTest(kind=kind):
                fx = self.fixture()
                if kind == "report":
                    private_file(fx.report, b" " * (1048576 + 1))
                elif kind == "log":
                    private_file(fx.log, b" " * (8 * 1048576 + 1), 0o644)
                else:
                    for number in range(32):
                        private_file(fx.state / f"verify-{RUN}.{number:06d}.json", encoded(fx.document))
                self.refused(fx, code="limit_exceeded")

    def test_linked_and_special_report_files_are_not_followed(self):
        for kind in ("symlink", "hardlink", "fifo", "directory"):
            with self.subTest(kind=kind):
                fx = self.fixture()
                if kind == "hardlink":
                    os.link(fx.report, fx.unsafe / "linked-report")
                else:
                    original = fx.unsafe / "original-report"
                    fx.report.rename(original)
                    if kind == "symlink":
                        fx.report.symlink_to(original)
                    elif kind == "fifo":
                        os.mkfifo(fx.report, 0o600)
                    else:
                        fx.report.mkdir(mode=0o700)
                self.refused(fx, code="unsafe_input")

    def test_unsafe_log_and_report_permissions_are_rejected(self):
        for kind, mode in (("report", 0o644), ("report", 0o660), ("report", 0o400),
                           ("log", 0o666), ("log", 0o4644)):
            with self.subTest(kind=kind, mode=oct(mode)):
                fx = self.fixture()
                getattr(fx, kind).chmod(mode)
                self.refused(fx, code="unsafe_input")

    def test_unsafe_directories_are_rejected_without_following_links(self):
        for kind in ("state", "logs", "downloads", "observation", "ancestor-link"):
            with self.subTest(kind=kind):
                fx = self.fixture()
                state = None
                if kind == "ancestor-link":
                    link = fx.unsafe / "home-link"
                    link.symlink_to(fx.home, target_is_directory=True)
                    state = link / fx.state.name
                else:
                    path = {"state": fx.state, "logs": fx.log.parent,
                            "downloads": fx.downloads, "observation": fx.observations}[kind]
                    path.chmod(0o777)
                self.refused(fx, state=state, code="unsafe_input")

    def test_foreign_owned_files_are_rejected_when_constructible(self):
        if os.geteuid() != 0:
            self.skipTest("foreign-owner fixture requires root")
        for kind in ("report", "log", "state"):
            with self.subTest(kind=kind):
                fx = self.fixture()
                try:
                    os.chown(getattr(fx, kind), 1, -1)
                except OSError as error:
                    if error.errno in (errno.EPERM, errno.EACCES, errno.EINVAL):
                        self.skipTest("host UID mapping or permissions forbid a foreign-owner fixture")
                    raise
                self.refused(fx, code="unsafe_input")

    def test_authorization_and_unrelated_state_are_never_read(self):
        fx = self.fixture()
        authorization = fx.state / "authorized-checksum-change"
        authorization.rename(fx.unsafe / "original-authorization")
        os.mkfifo(authorization, 0o600)
        private_file(fx.state / f"verify-{OTHER_RUN}.Abc123.json", b"not-json")
        (fx.state / "unrelated-link").symlink_to(fx.unsafe)
        data, _ = self.inspected(fx)
        self.assertEqual(data["verification"]["counts"]["errors"], 1)

    def test_python_environment_and_path_cannot_load_ambient_code(self):
        fx = self.fixture()
        private_file(fx.unsafe / "sitecustomize.py", "from pathlib import Path\nPath("
                     + repr(str(fx.executed)) + ").write_text('unexpected Python hook')\n")
        private_file(fx.unsafe / "json.py", "raise RuntimeError('ambient module loaded')\n")
        for executable in ("python3", "git", "gh", "curl", "bun"):
            private_file(fx.unsafe / executable,
                         "#!/bin/sh\nprintf 'unexpected command' > '" + str(fx.executed) + "'\nexit 90\n", 0o700)
        data, _ = self.inspected(fx, environment={"PYTHONPATH": str(fx.unsafe), "PYTHONHOME": str(fx.unsafe),
                                                "PYTHONSTARTUP": str(fx.unsafe / "sitecustomize.py"),
                                                "PATH": str(fx.unsafe) + ":/usr/bin:/bin"})
        self.assertEqual(data["verification"]["counts"]["errors"], 1)

    def test_native_trace_contains_no_network_or_publisher_commands(self):
        fx = self.fixture()
        tracer = shutil.which("strace")
        if tracer is None:
            self.skipTest("strace is unavailable; no native tracing proof obtained")
        probe = subprocess.run([tracer, "-f", "-qq", "-e", "trace=none", "/bin/true"],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        private_file(fx.receipts / "trace-probe.stderr", probe.stderr)
        denied_operations = ("PTRACE_TRACEME", "PTRACE_GET_SYSCALL_INFO", "PTRACE_SETOPTIONS")
        denied = any(line.startswith((str(tracer) + ":", "strace:")) and "Operation not permitted" in line
                     and any(operation in line for operation in denied_operations)
                     for line in probe.stderr.decode(errors="replace").splitlines())
        if probe.returncode != 0 and denied:
            self.skipTest("host denies ptrace; no native tracing proof obtained")
        self.assertEqual(probe.returncode, 0, probe.stderr.decode(errors="replace"))
        _, path = self.inspected(fx, trace=True)
        trace = path.read_text(errors="replace")
        self.assertNotRegex(trace, r"\bsocket\(AF_INET6?\b")
        self.assertNotRegex(trace, r"\b(connect|sendto|sendmsg)\([^\n]*AF_INET6?\b")
        self.assertNotRegex(trace, r'execve\("[^"\n]*/(?:curl|wget|git|gh|bun|ssh|scp|sftp|nc|ncat)"')
        self.assertNotRegex(trace, r'execve\("' + re.escape(str(fx.state)) + r'/')
        self.assertNotIn(BODY_SECRET, trace)
        self.assertNotIn(AUTH_SECRET, trace)


if __name__ == "__main__":
    unittest.main(verbosity=2)
