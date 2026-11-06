#!/usr/bin/env python3
"""Adversarial tests of the actual offline evidence CLI; run through DSR.

Synthetic installer bodies are never executed. All fixtures and CLI receipts
are retained under TMPDIR so a failed check cannot erase its own evidence.
"""

import copy
import errno
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]
SECURITY = REPO / "scripts/lib/security.sh"
BODY_SECRET = "ACFS_TEST_PRIVATE_BODY_65e1d218"
HEADER_SECRET = "ACFS_TEST_PRIVATE_COOKIE_976caa14"
REDIRECT_SECRET = "ACFS_TEST_PRIVATE_REDIRECT_84e520ab"
DIAGNOSTIC_SECRET = "ACFS_TEST_PRIVATE_DIAGNOSTIC_2ab6373f"
SECRETS = (BODY_SECRET, HEADER_SECRET, REDIRECT_SECRET, DIAGNOSTIC_SECRET)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def private_file(path, data, mode=0o600):
    path.write_bytes(data)
    path.chmod(mode)


def encoded(value):
    # Independent encoding with the same compact single-document boundary as
    # the producer. Do not call production validators to construct expectations.
    return (json.dumps(value, separators=(",", ":"), ensure_ascii=False) + "\n").encode()


def document(path):
    return json.loads(path.read_bytes())


def rewrite(path, change):
    value = document(path)
    change(value)
    private_file(path, encoded(value))


def tree_state(root):
    """Snapshot identities, modes and contents without following unsafe files."""
    result = {}

    def visit(path):
        info = path.lstat()
        kind = stat.S_IFMT(info.st_mode)
        identity = (kind, stat.S_IMODE(info.st_mode), info.st_uid, info.st_gid,
                    info.st_ino, info.st_nlink, info.st_size, info.st_mtime_ns)
        if stat.S_ISREG(info.st_mode):
            contents = file_sha(path)
        elif stat.S_ISLNK(info.st_mode):
            contents = os.readlink(path)
        else:
            contents = None
        result[str(path.relative_to(root))] = (identity, contents)
        if stat.S_ISDIR(info.st_mode):
            for child in sorted(path.iterdir()):
                visit(child)

    visit(root)
    return result


class Bundle:
    def __init__(self, parent, names, *, compressed=False, mismatches=("atuin", "grok"), diagnostic=False):
        self.root = Path(tempfile.mkdtemp(prefix="case-", dir=parent))
        self.root.chmod(0o700)
        for name in ("inputs", "home", "tmp", "receipts", "retained"):
            (self.root / name).mkdir(mode=0o700)
        self.inputs = self.root / "inputs"
        self.home = self.root / "home"
        self.tmp = self.root / "tmp"
        self.receipts = self.root / "receipts"
        self.retained = self.root / "retained"
        self.executed = self.root / "installer-executed"
        self.observations = self.inputs / "acfs-observations.fixture"
        self.observations.mkdir(mode=0o700)
        self.policy = self.inputs / "checksums.yaml"
        self.report = self.inputs / "verification-report.json"
        self.index = self.inputs / "evidence-index.json"
        self.names = names
        self.first = names[0]
        self.calls = 0
        rows, matches, changed, entries = [], [], [], []
        for name in names:
            url = f"https://example.invalid/acfs/{name}/install.sh"
            body = ("#!/bin/sh\n# " + BODY_SECRET + "\n"
                    + "printf '%s\\n' " + shlex.quote(name)
                    + " > " + shlex.quote(str(self.executed)) + "\nexit 91\n").encode()
            wire = gzip.compress(body, mtime=0) if compressed and name == "grok" else body
            coding = "gzip" if wire != body else "identity"
            headers = ("HTTP/2 302\r\nLocation: https://cdn.example.invalid/installer?token="
                       + REDIRECT_SECRET + "\r\nSet-Cookie: fixture=" + HEADER_SECRET
                       + "\r\n\r\nHTTP/2 200\r\nContent-Type: text/plain\r\nContent-Encoding: "
                       + coding + "\r\nContent-Length: " + str(len(wire)) + "\r\n\r\n").encode()
            actual = sha(body)
            expected = sha(("previously trusted fixture: " + name).encode()) if name in mismatches else actual
            entries.append(f'  {name}:\n    url: "{url}"\n    sha256: "{expected}"')
            if actual == expected:
                matches.append({"name": name, "url": url, "checksum": expected})
            else:
                changed.append({"name": name, "url": url, "expected": expected, "actual": actual})
            metadata = {"schema": "acfs.installer-download-evidence.v1", "name": name, "url": url,
                        "expected": expected, "actual": actual, "status": "observed",
                        "bodySha256": actual, "wireSha256": sha(wire), "headersSha256": sha(headers)}
            target = self.observations / name
            target.mkdir(mode=0o700)
            for filename, data in (("body", body), ("body.wire", wire), ("body.headers", headers),
                                   ("metadata.json", encoded(metadata))):
                private_file(target / filename, data)
            rows.append(metadata)
        policy = ("# checksums.yaml - Auto-generated 2026-11-05T19:46:29Z\n"
                  "# Run: ./scripts/lib/security.sh --update-checksums\n\ninstallers:\n"
                  + "\n\n".join(entries) + "\n")
        private_file(self.policy, policy.encode(), 0o644)
        report = {"schema": "acfs.installer-checksum-verification.v1", "schemaVersion": 1,
                  "timestamp": "2026-11-05T19:46:29Z", "checksumsYamlSha256": file_sha(self.policy),
                  "total": len(names), "matches": matches, "mismatches": changed, "errors": [], "skipped": []}
        private_file(self.report, encoded(report))
        self.report_anchor = file_sha(self.report)
        index = {"schema": "acfs.installer-download-evidence-index.v1",
                 "verificationReportSha256": self.report_anchor,
                 "checksumsYamlSha256": file_sha(self.policy), "observations": rows}
        private_file(self.index, encoded(index))
        self.index_anchor = file_sha(self.index)
        if diagnostic:
            private_file(self.tool_dir / "fetch-stderr.abcdef", (DIAGNOSTIC_SECRET + "\n").encode())

    @property
    def tool_dir(self):
        return self.observations / self.first

    def files(self):
        return {"policy": self.policy, "report": self.report, "index": self.index,
                "metadata": self.tool_dir / "metadata.json", "body": self.tool_dir / "body",
                "wire": self.tool_dir / "body.wire", "headers": self.tool_dir / "body.headers"}

    def args(self):
        return [str(self.policy), str(self.report), str(self.index), str(self.observations),
                self.report_anchor, self.index_anchor]

    def reanchor_index(self):
        self.index_anchor = file_sha(self.index)

    def reanchor_report(self):
        self.report_anchor = file_sha(self.report)
        rewrite(self.index, lambda data: data.update(verificationReportSha256=self.report_anchor))
        self.reanchor_index()

    def reanchor_metadata(self, name=None):
        name = name or self.first
        metadata = document(self.observations / name / "metadata.json")
        index = document(self.index)
        index["observations"] = [metadata if row["name"] == name else row for row in index["observations"]]
        private_file(self.index, encoded(index))
        self.reanchor_index()

    def rebind_payload(self, name=None):
        """Update hash bindings so decoding/size cases test more than stale anchors."""
        name = name or self.first
        folder = self.observations / name
        metadata = document(folder / "metadata.json")
        actual = file_sha(folder / "body")
        metadata.update(actual=actual, bodySha256=actual,
                        wireSha256=file_sha(folder / "body.wire"), headersSha256=file_sha(folder / "body.headers"))
        private_file(folder / "metadata.json", encoded(metadata))
        report = document(self.report)
        report["matches"] = [row for row in report["matches"] if row["name"] != name]
        report["mismatches"] = [row for row in report["mismatches"] if row["name"] != name]
        if actual == metadata["expected"]:
            report["matches"].append({"name": name, "url": metadata["url"], "checksum": actual})
        else:
            report["mismatches"].append({key: metadata[key] for key in ("name", "url", "expected", "actual")})
        for partition in ("matches", "mismatches"):
            report[partition].sort(key=lambda row: row["name"])
        private_file(self.report, encoded(report))
        self.reanchor_metadata(name)
        self.reanchor_report()


class EvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(tempfile.mkdtemp(prefix="acfs-checksum-evidence-tests-"))
        cls.root.chmod(0o700)
        cls.names = sorted(re.findall(r"^  ([a-z][a-z0-9_]*):$", (REPO / "checksums.yaml").read_text(), re.M))
        if len(cls.names) != len(set(cls.names)) or not {"atuin", "grok"}.issubset(cls.names):
            raise AssertionError("fixture requires the complete current installer-name policy")
        cls.cli_cases = 0
        print(f"Retaining checksum evidence fixtures: {cls.root}", file=sys.stderr)

    @classmethod
    def tearDownClass(cls):
        print(f"Actual evidence CLI invocations: {cls.cli_cases}; retained at {cls.root}", file=sys.stderr)

    def fixture(self, **kwargs):
        return Bundle(self.root, self.names, **kwargs)

    def invoke(self, fx, args=None, *, trace=False, cwd=None, operation="--verify-checksum-evidence"):
        before = tree_state(fx.inputs)
        home_before = tree_state(fx.home)
        command = ["/bin/bash", str(SECURITY), operation, *(args if args is not None else fx.args())]
        trace_path = fx.receipts / "syscalls.log"
        if trace:
            tracer = shutil.which("strace")
            self.assertIsNotNone(tracer, "strace is required for the native no-network/no-execution proof")
            command = [tracer, "-f", "-qq", "-s", "4096", "-e", "trace=network,process", "-o", str(trace_path), *command]
        environment = {key: value for key, value in os.environ.items()
                       if key not in {"BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS", "CDPATH", "PYTHONPATH", "PYTHONHOME"}}
        environment.update(HOME=str(fx.home), TMPDIR=str(fx.tmp), NO_COLOR="1", LC_ALL="C", LANG="C", TZ="UTC",
                           PYTHONDONTWRITEBYTECODE="1", ACFS_SECURITY_RETAIN_TEMP_FILES="true",
                           ACFS_MONITOR_STATE=str(fx.home / ".local/state/acfs-monitor"))
        fx.calls += 1
        type(self).cli_cases += 1
        process = subprocess.Popen(command, cwd=cwd or fx.root, env=environment,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        timed_out = False
        try:
            stdout, stderr = process.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            timed_out = True
            # Only the new session created for this test invocation is killed.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            stdout, stderr = process.communicate()
        private_file(fx.receipts / f"cli-{fx.calls}.stdout", stdout)
        private_file(fx.receipts / f"cli-{fx.calls}.stderr", stderr)
        self.assertFalse(timed_out, "offline validation blocked; inspect retained CLI receipts")
        self.assertEqual(tree_state(fx.inputs), before, "validation mutated original evidence")
        self.assertEqual(tree_state(fx.home), home_before, "validation wrote owner state or an authorization record")
        self.assertFalse(fx.executed.exists(), "an installer body was executed")
        for secret in SECRETS:
            self.assertNotIn(secret.encode(), stdout + stderr, "private evidence leaked into CLI output")
        return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)

    def accepted(self, fx, **kwargs):
        result = self.invoke(fx, **kwargs)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace")[-2000:])
        self.assertTrue(result.stdout.endswith(b"\n"))
        self.assertEqual(len(result.stdout.splitlines()), 1, "success must be a single JSON document")
        data = json.loads(result.stdout)
        self.assertEqual(data["schema"], "acfs.checksum-evidence-review.v1")
        self.assertIs(data["integrity_verified"], True)
        self.assertEqual(data["trust_decision"], "not_assessed")
        self.assertIs(data["authorization_granted"], False)
        self.assertEqual(data["verification_report_sha256"], fx.report_anchor)
        self.assertEqual(data["download_evidence_index_sha256"], fx.index_anchor)
        self.assertEqual(data["checksums_yaml_sha256"], file_sha(fx.policy))
        self.assertEqual(data["total"], len(self.names))
        report = document(fx.report)
        self.assertEqual(data["matches"], len(report["matches"]))
        self.assertEqual(data["mismatches"], len(report["mismatches"]))
        self.assertEqual(data["observations"], document(fx.index)["observations"])
        self.assertNotIn("authorization_line", data)
        self.assertNotIn(b"authorize:", result.stdout)
        self.assertNotIn(b"authorize-subset:", result.stdout)
        return data

    def refused(self, fx, args=None):
        result = self.invoke(fx, args)
        self.assertNotEqual(result.returncode, 0, "unsafe evidence was accepted")
        self.assertEqual(result.stdout, b"", "failure emitted partial trusted output")

    def test_complete_mixed_bundle_is_integrity_only(self):
        data = self.accepted(self.fixture())
        self.assertEqual(data["mismatches"], 2)

    def test_all_matches_still_grants_no_authority(self):
        self.assertEqual(self.accepted(self.fixture(mismatches=()))["mismatches"], 0)

    def test_gzip_retains_distinct_wire_and_decoded_bindings(self):
        fx = self.fixture(compressed=True)
        data = self.accepted(fx)
        grok = next(row for row in data["observations"] if row["name"] == "grok")
        self.assertNotEqual(grok["wireSha256"], grok["bodySha256"])
        self.assertIs(data["content_encoding_verified"], True)
        self.assertEqual(data["content_encodings"]["grok"], "gzip")

    def test_private_diagnostic_sidecar_is_not_disclosed(self):
        self.accepted(self.fixture(diagnostic=True))

    def test_two_exact_external_anchors_are_mandatory(self):
        for case in ("report", "index", "swapped", "uppercase", "short", "not_hex", "missing", "extra"):
            with self.subTest(case=case):
                fx = self.fixture()
                args = fx.args()
                if case == "report": args[4] = "0" * 64
                elif case == "index": args[5] = "0" * 64
                elif case == "swapped": args[4], args[5] = args[5], args[4]
                elif case == "uppercase": args[4] = args[4].upper()
                elif case == "short": args[4] = args[4][:-1]
                elif case == "not_hex": args[5] = "z" * 64
                elif case == "missing": args.pop()
                else: args.append("unexpected")
                self.refused(fx, args)

    def test_any_recorded_byte_change_is_rejected(self):
        for role in ("policy", "report", "index", "metadata", "body", "wire", "headers"):
            with self.subTest(role=role):
                fx = self.fixture()
                path = fx.files()[role]
                private_file(path, path.read_bytes() + b"\nchanged\n", stat.S_IMODE(path.stat().st_mode))
                self.refused(fx)

    def test_missing_bound_file_or_tool_is_rejected(self):
        for role in ("policy", "report", "index", "metadata", "body", "wire", "headers", "tool", "root"):
            with self.subTest(role=role):
                fx = self.fixture()
                path = fx.tool_dir if role == "tool" else fx.observations if role == "root" else fx.files()[role]
                path.rename(fx.retained / role)
                self.refused(fx)

    def test_unknown_hidden_and_duplicate_diagnostics_are_rejected(self):
        for role in ("root_extra", "root_hidden", "tool_extra", "tool_hidden", "diagnostic_extra", "diagnostic_name"):
            with self.subTest(role=role):
                fx = self.fixture(diagnostic=True)
                if role == "root_extra": (fx.observations / "unexpected").mkdir(mode=0o700)
                elif role == "root_hidden": private_file(fx.observations / ".hidden", b"private\n")
                elif role == "tool_extra": private_file(fx.tool_dir / "unexpected", b"private\n")
                elif role == "tool_hidden": private_file(fx.tool_dir / ".hidden", b"private\n")
                elif role == "diagnostic_extra": private_file(fx.tool_dir / "fetch-stderr.123456", b"private\n")
                else: private_file(fx.tool_dir / "fetch-stderr.bad", b"private\n")
                self.refused(fx)

    def test_symlinks_to_even_correct_bytes_are_rejected(self):
        for role in ("policy", "report", "index", "metadata", "body", "wire", "headers", "tool", "root", "diagnostic"):
            with self.subTest(role=role):
                fx = self.fixture(diagnostic=True)
                if role == "tool": path = fx.tool_dir
                elif role == "root": path = fx.observations
                elif role == "diagnostic": path = fx.tool_dir / "fetch-stderr.abcdef"
                else: path = fx.files()[role]
                retained = fx.retained / role
                path.rename(retained)
                path.symlink_to(retained, target_is_directory=role in {"tool", "root"})
                self.refused(fx)

    def test_multiple_hardlinks_to_private_evidence_are_rejected(self):
        for role in ("report", "index", "metadata", "body", "wire", "headers", "diagnostic"):
            with self.subTest(role=role):
                fx = self.fixture(diagnostic=True)
                path = fx.tool_dir / "fetch-stderr.abcdef" if role == "diagnostic" else fx.files()[role]
                os.link(path, fx.retained / role)
                self.refused(fx)

    def test_special_files_fail_without_waiting_for_a_writer(self):
        for role in ("policy", "report", "index", "metadata", "body", "wire", "headers", "diagnostic"):
            with self.subTest(role=role):
                fx = self.fixture(diagnostic=True)
                path = fx.tool_dir / "fetch-stderr.abcdef" if role == "diagnostic" else fx.files()[role]
                path.rename(fx.retained / role)
                os.mkfifo(path, 0o600)
                self.refused(fx)

    def test_private_file_and_directory_modes_are_enforced(self):
        for role in ("report", "index", "metadata", "body", "wire", "headers", "diagnostic", "tool", "root"):
            with self.subTest(role=role):
                fx = self.fixture(diagnostic=True)
                if role == "tool": path = fx.tool_dir
                elif role == "root": path = fx.observations
                elif role == "diagnostic": path = fx.tool_dir / "fetch-stderr.abcdef"
                else: path = fx.files()[role]
                path.chmod(0o750 if role in {"tool", "root"} else 0o640)
                self.refused(fx)

    def test_foreign_owner_is_rejected_when_constructible(self):
        fx = self.fixture()
        if os.geteuid() != 0:
            self.skipTest("foreign-owner fixture requires permission to change ownership")
        try:
            os.chown(fx.tool_dir / "body", 65534, -1)
        except PermissionError:
            self.skipTest("host denies the ownership change required for this fixture")
        except OSError as exc:
            if exc.errno == errno.EINVAL:
                mappings = [tuple(map(int, line.split()))
                            for line in Path("/proc/self/uid_map").read_text().splitlines()]
                if not any(start <= 65534 < start + count for start, _, count in mappings):
                    self.skipTest("UID 65534 is unmapped in this user namespace; foreign-owner rejection was not exercised")
            raise
        self.refused(fx)

    def test_duplicate_keys_noncanonical_json_and_multiple_documents_refuse(self):
        for role in ("report", "index", "metadata"):
            for form in ("duplicate_key", "pretty", "missing_lf", "second_document"):
                with self.subTest(role=role, form=form):
                    fx = self.fixture()
                    path = fx.files()[role]
                    raw = path.read_bytes()
                    if form == "duplicate_key":
                        key = {"report": "matches", "index": "observations", "metadata": "schema"}[role]
                        # The empty-container duplicate is intentionally first;
                        # ordinary JSON parsers would silently keep the last.
                        raw = ('{"' + key + '":{},').encode() + raw[1:]
                    elif form == "pretty": raw = (json.dumps(document(path), indent=2) + "\n").encode()
                    elif form == "missing_lf": raw = raw[:-1]
                    else: raw += b"{}\n"
                    private_file(path, raw)
                    if role == "report": fx.reanchor_report()
                    elif role == "index": fx.reanchor_index()
                    self.refused(fx)

    def test_reanchored_report_schema_coverage_and_policy_forgery_refuse(self):
        def error_partition(data, skipped=False):
            old = data["matches"].pop(0)
            row = {"name": old["name"], "url": old["url"]}
            row["reason" if skipped else "error"] = DIAGNOSTIC_SECRET
            data["skipped" if skipped else "errors"].append(row)

        changes = (
            ("schema", lambda data: data.update(schema="unexpected.schema")),
            ("boolean_version", lambda data: data.update(schemaVersion=True)),
            ("unknown_field", lambda data: data.update(extra=[])),
            ("total", lambda data: data.update(total=data["total"] + 1)),
            ("policy_digest", lambda data: data.update(checksumsYamlSha256="0" * 64)),
            ("missing", lambda data: (data["matches"].pop(0), data.update(total=data["total"] - 1))),
            ("duplicate", lambda data: (data["matches"].append(copy.deepcopy(data["matches"][0])), data.update(total=data["total"] + 1))),
            ("unknown_tool", lambda data: data["matches"][0].update(name="unexpected")),
            ("wrong_url", lambda data: data["matches"][0].update(url="https://elsewhere.invalid/install.sh")),
            ("wrong_expected", lambda data: data["mismatches"][0].update(expected="0" * 64)),
            ("mislabeled_match", lambda data: data["mismatches"][0].update(actual=data["mismatches"][0]["expected"])),
            ("errors", error_partition),
            ("skips", lambda data: error_partition(data, True)),
        )
        for label, change in changes:
            with self.subTest(case=label):
                fx = self.fixture()
                rewrite(fx.report, change)
                fx.reanchor_report()
                self.refused(fx)

    def test_reanchored_index_schema_and_exact_observation_set_refuse(self):
        changes = (
            ("schema", lambda data: data.update(schema="unexpected.schema")),
            ("unknown_field", lambda data: data.update(extra=[])),
            ("report_binding", lambda data: data.update(verificationReportSha256="0" * 64)),
            ("policy_binding", lambda data: data.update(checksumsYamlSha256="0" * 64)),
            ("missing", lambda data: data["observations"].pop()),
            ("duplicate", lambda data: data["observations"].append(copy.deepcopy(data["observations"][0]))),
            ("order", lambda data: data["observations"].reverse()),
            ("unknown_tool", lambda data: data["observations"][0].update(name="unexpected")),
        )
        for label, change in changes:
            with self.subTest(case=label):
                fx = self.fixture()
                rewrite(fx.index, change)
                fx.reanchor_index()
                self.refused(fx)

    def test_metadata_forgery_refuses_even_when_the_index_agrees(self):
        changes = (
            ("schema", lambda data: data.update(schema="unexpected.schema")),
            ("unknown_field", lambda data: data.update(extra=[])),
            ("status", lambda data: data.update(status="error")),
            ("path_name", lambda data: data.update(name="../outside")),
            ("url", lambda data: data.update(url="https://elsewhere.invalid/install.sh")),
            ("expected", lambda data: data.update(expected="0" * 64)),
            ("actual", lambda data: data.update(actual="0" * 64)),
            ("body_digest", lambda data: data.update(bodySha256="0" * 64)),
            ("wire_digest", lambda data: data.update(wireSha256="0" * 64)),
            ("header_digest", lambda data: data.update(headersSha256="0" * 64)),
        )
        for label, change in changes:
            with self.subTest(case=label):
                fx = self.fixture()
                rewrite(fx.tool_dir / "metadata.json", change)
                fx.reanchor_metadata()
                self.refused(fx)

    def test_hashes_alone_cannot_hide_inconsistent_or_undecodable_wire(self):
        for case in ("identity_mismatch", "corrupt_gzip", "unsupported_coding"):
            with self.subTest(case=case):
                fx = self.fixture()
                if case == "identity_mismatch":
                    private_file(fx.tool_dir / "body.wire", b"different wire response\n")
                elif case == "corrupt_gzip":
                    private_file(fx.tool_dir / "body.wire", b"not a gzip stream\n")
                    private_file(fx.tool_dir / "body.headers", b"HTTP/2 200\r\nContent-Encoding: gzip\r\n\r\n")
                else:
                    private_file(fx.tool_dir / "body.headers", b"HTTP/2 200\r\nContent-Encoding: br\r\n\r\n")
                fx.rebind_payload()
                self.refused(fx)

    def test_oversize_members_and_decompression_expansion_refuse(self):
        limits = {"policy": 1048576, "report": 4194304, "index": 1048576,
                  "metadata": 16384, "headers": 1048576, "diagnostic": 1048576}
        for role, limit in limits.items():
            with self.subTest(role=role):
                fx = self.fixture(diagnostic=True)
                path = fx.tool_dir / "fetch-stderr.abcdef" if role == "diagnostic" else fx.files()[role]
                with path.open("r+b") as stream:
                    stream.truncate(limit + 1)
                if role == "report": fx.reanchor_report()
                elif role == "index": fx.reanchor_index()
                self.refused(fx)
        for kind, length in (("wire", 1048577), ("decoded", 16777217)):
            with self.subTest(role=kind):
                fx = self.fixture()
                body = b"x" * length
                wire = gzip.compress(body, mtime=0) if kind == "decoded" else body
                coding = "gzip" if kind == "decoded" else "identity"
                private_file(fx.tool_dir / "body", body)
                private_file(fx.tool_dir / "body.wire", wire)
                private_file(fx.tool_dir / "body.headers", ("HTTP/2 200\r\nContent-Encoding: " + coding + "\r\n\r\n").encode())
                fx.rebind_payload()
                self.refused(fx)

    def test_native_trace_contains_no_network_or_installer_execution(self):
        fx = self.fixture(compressed=True, diagnostic=True)
        tracer = shutil.which("strace")
        self.assertIsNotNone(tracer, "strace is required for the native no-network/no-execution proof")
        probe = subprocess.run([tracer, "-f", "-qq", "-e", "trace=none", "/bin/true"],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10,
                               env={**os.environ, "LC_ALL": "C", "LANG": "C"})
        private_file(fx.receipts / "trace-probe.stderr", probe.stderr)
        denied_operations = ("PTRACE_TRACEME", "PTRACE_GET_SYSCALL_INFO", "PTRACE_SETOPTIONS")
        denied = any(line.startswith((str(tracer) + ":", "strace:")) and "Operation not permitted" in line
                     and any(operation in line for operation in denied_operations)
                     for line in probe.stderr.decode(errors="replace").splitlines())
        if probe.returncode != 0 and denied:
            self.skipTest("host denies ptrace for the standalone probe; no native tracing proof obtained")
        self.assertEqual(probe.returncode, 0, probe.stderr.decode(errors="replace"))
        self.accepted(fx, trace=True)
        trace = (fx.receipts / "syscalls.log").read_text(errors="replace")
        self.assertNotRegex(trace, r"\bsocket\(AF_INET6?\b")
        self.assertNotRegex(trace, r"\b(connect|sendto|sendmsg)\([^\n]*AF_INET6?\b")
        self.assertNotRegex(trace, r'execve\("[^"\n]*/(?:curl|wget|git|gh|ssh|scp|sftp|nc|ncat)"')
        self.assertNotIn(BODY_SECRET, trace)
        self.assertNotRegex(trace, r'execve\("' + re.escape(str(fx.observations)) + r'/')
        self.assertNotIn("checksum-monitor-local.sh", trace)

    def export_bundle(self, fx):
        destination = fx.root / "portable-evidence"
        result = self.accepted(fx, args=[*fx.args(), str(destination)], operation="--export-checksum-evidence")
        self.assertIs(result["exported"], True)
        self.assertEqual(result["export_path"], str(destination))
        return destination

    def exported_view(self, fx, destination):
        exported = copy.copy(fx)
        exported.inputs = destination
        exported.policy = destination / "checksums.yaml"
        exported.report = destination / "verification-report.json"
        exported.index = destination / "evidence-index.json"
        exported.observations = destination / "observations"
        return exported

    def test_export_preserves_exact_evidence_with_private_portable_modes(self):
        fx = self.fixture(compressed=True, diagnostic=True)
        destination = self.export_bundle(fx)
        expected_files = {"checksums.yaml", "verification-report.json", "evidence-index.json", "bundle.json"}
        for source, relative in ((fx.policy, "checksums.yaml"), (fx.report, "verification-report.json"), (fx.index, "evidence-index.json")):
            self.assertEqual((destination / relative).read_bytes(), source.read_bytes())
        for name in self.names:
            for filename in ("metadata.json", "body", "body.wire", "body.headers"):
                relative = f"observations/{name}/{filename}"
                expected_files.add(relative)
                self.assertEqual((destination / relative).read_bytes(), (fx.observations / name / filename).read_bytes())
        actual_files = set()
        for path in (destination, *destination.rglob("*")):
            info = path.lstat()
            self.assertEqual(info.st_uid, os.geteuid())
            self.assertFalse(stat.S_ISLNK(info.st_mode))
            if stat.S_ISDIR(info.st_mode):
                self.assertEqual(stat.S_IMODE(info.st_mode), 0o700)
            else:
                self.assertTrue(stat.S_ISREG(info.st_mode))
                self.assertEqual(stat.S_IMODE(info.st_mode), 0o600)
                self.assertEqual(info.st_nlink, 1)
                actual_files.add(str(path.relative_to(destination)))
        self.assertEqual(actual_files, expected_files, "export must omit unbound diagnostic sidecars")
        self.assertEqual(document(destination / "bundle.json")["schema"], "acfs.checksum-evidence-bundle.v1")
        self.accepted(self.exported_view(fx, destination))

    def test_export_refuses_existing_destinations_without_clobbering(self):
        for kind in ("directory", "file", "symlink"):
            with self.subTest(kind=kind):
                fx = self.fixture()
                destination = fx.root / "existing"
                if kind == "directory": destination.mkdir(mode=0o700)
                elif kind == "file": private_file(destination, b"owner data must survive\n")
                else: destination.symlink_to(fx.root / "not-created")
                before = tree_state(destination)
                result = self.invoke(fx, [*fx.args(), str(destination)], operation="--export-checksum-evidence")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, b"")
                self.assertEqual(tree_state(destination), before)
                self.assertFalse((fx.root / "not-created").exists())

    def test_export_refuses_linked_parent_and_invalid_evidence(self):
        for kind in ("linked_parent", "body_change", "wrong_anchor"):
            with self.subTest(kind=kind):
                fx = self.fixture()
                parent = fx.root / "foreign"
                parent.mkdir(mode=0o700)
                before = tree_state(parent)
                destination = parent / "exported"
                args = fx.args()
                if kind == "linked_parent":
                    link = fx.root / "parent-link"
                    link.symlink_to(parent, target_is_directory=True)
                    destination = link / "exported"
                elif kind == "body_change": private_file(fx.tool_dir / "body", b"unreviewed replacement\n")
                else: args[4] = "0" * 64
                result = self.invoke(fx, [*args, str(destination)], operation="--export-checksum-evidence")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, b"")
                self.assertEqual(tree_state(parent), before, "refused export changed destination parent")

    def test_export_descriptor_cannot_replace_independent_anchors(self):
        fx = self.fixture()
        destination = self.export_bundle(fx)
        exported = self.exported_view(fx, destination)
        private_file(destination / "bundle.json", encoded({"schema": "untrusted.descriptor", "verification_report_sha256": "0" * 64}))
        self.accepted(exported)
        args = exported.args()
        args[4] = "0" * 64
        self.refused(exported, args)
        private_file(exported.tool_dir / "body", b"changed after export\n")
        self.refused(exported)

    def test_validation_leaves_repository_and_owner_state_unchanged(self):
        # Include untracked product work in this check; do not mutate Git or
        # mistake an empty worktree diff for proof that source bytes survived.
        inventory_command = ["git", "-c", "core.fsmonitor=false", "ls-files", "--cached", "--others", "--exclude-standard", "-z"]
        inventory_env = {**os.environ, "GIT_OPTIONAL_LOCKS": "0"}
        listed = subprocess.run(inventory_command, cwd=REPO, env=inventory_env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=30).stdout
        paths = [REPO / os.fsdecode(name) for name in listed.split(b"\0") if name]

        def source_state():
            result = {}
            for path in paths:
                info = path.lstat()
                result[str(path)] = (stat.S_IMODE(info.st_mode), info.st_ino, info.st_nlink, info.st_mtime_ns,
                                     os.readlink(path) if path.is_symlink() else file_sha(path))
            return result

        before = source_state()
        fx = self.fixture(diagnostic=True)
        self.accepted(fx, cwd=REPO)
        self.assertEqual(source_state(), before)
        listed_after = subprocess.run(inventory_command, cwd=REPO, env=inventory_env,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=30).stdout
        self.assertEqual(listed_after, listed, "validation changed the repository file inventory")


if __name__ == "__main__":
    unittest.main(verbosity=2)
