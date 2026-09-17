#!/usr/bin/env python3
"""Exercise the embedded production EOL transformer, not a copied substitute."""
import contextlib
import hashlib
import io
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import types
import unittest
from unittest import mock

LIB = Path(__file__).resolve().parents[2] / "scripts/lib/ubuntu_upgrade.sh"
CODE = LIB.read_text().split("<<'ACFS_EOL_APT_PY'\n", 1)[1].split("\nACFS_EOL_APT_PY\n", 1)[0]
recovery = types.ModuleType("acfs_eol_recovery")
exec(compile(CODE, str(LIB) + ":eol-recovery", "exec"), recovery.__dict__)
OLD = "http://archive.ubuntu.com/ubuntu"
NEW = "https://old-releases.ubuntu.com/ubuntu"
KEY = "/usr/share/keyrings/ubuntu-archive-keyring.gpg"
STANZA = f"Types: deb deb-src\nURIs: {OLD}\nSuites: questing questing-updates questing-security\nComponents: main universe\nSigned-By: {KEY}\nArchitectures: amd64 arm64\n"


class TransformTests(unittest.TestCase):
    def test_legacy_preserves_everything_except_uri(self):
        text = f"# header\r\n\tdeb  [arch=arm64 signed-by={KEY}] {OLD}/\tquesting-security   main restricted # keep me\r\n"
        updated, count = recovery.transform_list(text)
        self.assertEqual(updated, text.replace(OLD, NEW))
        self.assertEqual(count, 1)

    def test_deb822_preserves_everything_except_uri(self):
        updated, count = recovery.transform_sources(STANZA)
        self.assertEqual(updated, STANZA.replace(OLD, NEW))
        self.assertEqual(count, 1)

    def test_inline_signing_key_is_unchanged(self):
        text = STANZA.replace(f"Signed-By: {KEY}", "Signed-By:\n -----BEGIN PGP PUBLIC KEY BLOCK-----\n .\n FixturePublicKey+/=\n -----END PGP PUBLIC KEY BLOCK-----")
        self.assertEqual(recovery.transform_sources(text)[0], text.replace(OLD, NEW))

    def test_multiline_multiple_uris_and_suites(self):
        text = STANZA.replace(f"URIs: {OLD}", f"uris: {OLD}/\n # keep comment\n https://security.ubuntu.com/ubuntu").replace("Suites: questing questing-updates questing-security", "suites: questing\n questing-updates\n questing-security")
        expected = text.replace(OLD, NEW).replace("https://security.ubuntu.com/ubuntu", NEW)
        self.assertEqual(recovery.transform_sources(text)[0], expected)

    def test_newline_and_eof_preserved(self):
        for ending in ("\n", "\r\n", ""):
            with self.subTest(ending=repr(ending)):
                text = STANZA.replace("\n", "\r\n") if ending == "\r\n" else STANZA
                if ending == "":
                    text = text.rstrip("\n")
                self.assertEqual(recovery.transform_sources(text)[0], text.replace(OLD, NEW))

    def test_disabled_comments_and_third_parties_are_preserved(self):
        disabled = "Enabled: no\n" + STANZA.replace("questing", "noble")
        third_party = STANZA.replace(OLD, "https://user:fixture-password@packages.example.test/ubuntu")
        text = disabled + "\n# separator\n\n" + third_party + "\n" + STANZA
        updated, count = recovery.transform_sources(text)
        self.assertEqual(updated, disabled + "\n# separator\n\n" + third_party + "\n" + STANZA.replace(OLD, NEW))
        self.assertEqual(count, 1)

    def test_legacy_disabled_third_party_and_comments(self):
        text = f"# deb {OLD} noble main\ndeb https://ppa.example.test/ubuntu noble main\ndeb {OLD} questing main\n"
        self.assertEqual(recovery.transform_list(text), (text.replace(f"deb {OLD} questing", f"deb {NEW} questing"), 1))

    def test_archive_mirrors_and_ports(self):
        for host, path in [("archive.ubuntu.com", "ubuntu"), ("us.archive.ubuntu.com", "ubuntu"), ("us-east-1.ec2.archive.ubuntu.com", "ubuntu"), ("security.ubuntu.com", "ubuntu"), ("ports.ubuntu.com", "ubuntu-ports"), ("old-releases.ubuntu.com", "ubuntu")]:
            with self.subTest(host=host):
                self.assertEqual(recovery.archive_uri(f"http://{host}/{path}/"), NEW + "/")

    def test_no_hostname_prefix_confusion(self):
        for uri in ["https://archive.ubuntu.com.evil.test/ubuntu", "https://notarchive.ubuntu.com/ubuntu", "https://ubuntu.example.test/ubuntu", "file:/srv/mirror/ubuntu"]:
            with self.subTest(uri=uri):
                self.assertIsNone(recovery.archive_uri(uri))

    def test_official_credentials_custom_paths_and_ports_refused(self):
        for uri in [OLD + "/snapshot", OLD + "?fixture=secret", "http://user:fixture-secret@archive.ubuntu.com/ubuntu", "http://archive.ubuntu.com:80/ubuntu", "ftp://archive.ubuntu.com/ubuntu", OLD + "#fragment"]:
            with self.subTest(uri=uri):
                with self.assertRaises(recovery.RecoveryError) as error:
                    recovery.archive_uri(uri)
                self.assertNotIn("fixture-secret", str(error.exception))

    def test_wrong_and_mixed_releases_refused(self):
        for suite in ["noble", "resolute", "plucky", "questing resolute", "questing-invalid"]:
            with self.subTest(suite=suite), self.assertRaises(recovery.RecoveryError):
                recovery.transform_sources(STANZA.replace("questing questing-updates questing-security", suite))
        with self.assertRaises(recovery.RecoveryError):
            recovery.transform_list(f"deb {OLD} noble main\n")

    def test_mixed_uri_ownership_refused(self):
        with self.assertRaises(recovery.RecoveryError):
            recovery.transform_sources(STANZA.replace(OLD, OLD + " https://packages.example.test/ubuntu"))

    def test_insecure_existing_settings_refused(self):
        for key, value in [("Trusted", "yes"), ("Allow-Insecure", "true"), ("Allow-Weak", "1"), ("Allow-Downgrade-To-Insecure", "yes"), ("Check-Date", "no"), ("Check-Valid-Until", "false")]:
            with self.subTest(key=key):
                with self.assertRaises(recovery.RecoveryError):
                    recovery.transform_sources(STANZA + f"{key}: {value}\n")
                with self.assertRaises(recovery.RecoveryError):
                    recovery.transform_list(f"deb [{key.lower()}={value}] {OLD} questing main\n")

    def test_secure_existing_settings_preserved(self):
        text = STANZA + "Trusted: no\nAllow-Insecure: no\nCheck-Date: yes\nCheck-Valid-Until: yes\n"
        self.assertEqual(recovery.transform_sources(text)[0], text.replace(OLD, NEW))

    def test_invalid_and_duplicate_fields_refused(self):
        for text in [" URIs: " + OLD + "\n", STANZA + "uris: " + OLD + "\n", STANZA.replace("Types: deb deb-src\n", ""), STANZA.replace("Components: main universe\n", ""), STANZA + "Enabled: maybe\n", STANZA + "invalid field\n"]:
            with self.subTest(text=text), self.assertRaises(recovery.RecoveryError):
                recovery.transform_sources(text)

    def test_legacy_bad_syntax_and_duplicate_options_refused(self):
        for text in [f"deb {OLD}\n", f"deb [trusted=no trusted=yes] {OLD} questing main\n", f"deb [bad] {OLD} questing main\n", f"deb {OLD} questing\n", "some invalid source"]:
            with self.subTest(text=text), self.assertRaises(recovery.RecoveryError):
                recovery.transform_list(text)

    def test_already_recovered_is_byte_identical(self):
        text = STANZA.replace(OLD, NEW)
        self.assertEqual(recovery.transform_sources(text), (text, 1))


class FilesystemTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="acfs-eol-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.parts = self.root / "sources.list.d"
        self.parts.mkdir()
        self.source = self.parts / "ubuntu.sources"
        self.source.write_text(STANZA)
        self.source.chmod(0o640)

    def backups(self):
        return list(self.parts.glob("*.bak"))

    def test_dry_run_is_read_only(self):
        before = self.source.stat()
        self.assertEqual(recovery.prepare_sources(str(self.root)), 1)
        self.assertEqual(self.source.read_text(), STANZA)
        self.assertEqual(self.source.stat().st_ino, before.st_ino)
        self.assertEqual(self.backups(), [])

    def test_apply_preserves_mode_owner_and_backup(self):
        before = self.source.stat()
        self.assertEqual(recovery.prepare_sources(str(self.root), True), 1)
        self.assertEqual(self.source.read_text(), STANZA.replace(OLD, NEW))
        after = self.source.stat()
        self.assertEqual((stat.S_IMODE(after.st_mode), after.st_uid, after.st_gid), (0o640, before.st_uid, before.st_gid))
        self.assertEqual(len(self.backups()), 1)
        self.assertEqual(self.backups()[0].read_text(), STANZA)
        self.assertEqual(stat.S_IMODE(self.backups()[0].stat().st_mode), 0o600)
        self.assertFalse(list(self.parts.glob("*.tmp")))

    def test_rerun_is_idempotent(self):
        recovery.prepare_sources(str(self.root), True)
        before = self.source.stat()
        self.assertEqual(recovery.prepare_sources(str(self.root), True), 0)
        self.assertEqual(self.source.stat().st_ino, before.st_ino)
        self.assertEqual(len(self.backups()), 1)

    def test_real_xattrs_preserved(self):
        os.setxattr(self.source, "user.acfs-fixture", b"preserve-me")
        recovery.prepare_sources(str(self.root), True)
        self.assertEqual(os.getxattr(self.source, "user.acfs-fixture"), b"preserve-me")

    def test_bad_second_file_refused_before_first_write(self):
        (self.parts / "zz-bad.sources").write_text(STANZA.replace("questing", "resolute"))
        with self.assertRaises(recovery.RecoveryError):
            recovery.prepare_sources(str(self.root), True)
        self.assertEqual(self.source.read_text(), STANZA)
        self.assertEqual(self.backups(), [])

    def test_cross_file_signing_conflict_is_refused_by_apt(self):
        other = STANZA.replace(OLD, "http://security.ubuntu.com/ubuntu").replace(KEY, "/custom/other-key.gpg")
        (self.parts / "other.sources").write_text(other)
        with self.assertRaises(recovery.RecoveryError) as error:
            recovery.prepare_sources(str(self.root), True)
        self.assertIn("APT rejected", str(error.exception))
        self.assertEqual(self.source.read_text(), STANZA)
        self.assertEqual(self.backups(), [])

    def test_apt_parser_failure_never_reaches_source_writes(self):
        with mock.patch.object(recovery.subprocess, "run", side_effect=OSError("fixture failure")):
            with self.assertRaises(recovery.RecoveryError):
                recovery.prepare_sources(str(self.root), True)
        self.assertEqual(self.source.read_text(), STANZA)
        self.assertEqual(self.backups(), [])

    def test_apt_parser_timeout_never_reaches_source_writes(self):
        with mock.patch.object(recovery.subprocess, "run", side_effect=subprocess.TimeoutExpired("apt-get", 15)):
            with self.assertRaises(recovery.RecoveryError):
                recovery.prepare_sources(str(self.root), True)
        self.assertEqual(self.source.read_text(), STANZA)
        self.assertEqual(self.backups(), [])

    def test_legacy_and_deb822_are_both_processed(self):
        legacy = self.root / "sources.list"
        legacy.write_text(f"deb {OLD} questing main\n")
        self.assertEqual(recovery.prepare_sources(str(self.root), True), 2)
        self.assertIn(NEW, legacy.read_text())
        self.assertIn(NEW, self.source.read_text())

    def test_source_symlink_refused(self):
        self.source.rename(self.parts / "original")
        self.source.symlink_to(self.parts / "original")
        with self.assertRaises((OSError, recovery.RecoveryError)):
            recovery.prepare_sources(str(self.root), True)
        self.assertEqual((self.parts / "original").read_text(), STANZA)
        self.assertEqual(self.backups(), [])

    def test_parent_symlink_refused(self):
        real = self.root / "real"
        self.parts.rename(real)
        self.parts.symlink_to(real, target_is_directory=True)
        with self.assertRaises((OSError, recovery.RecoveryError)):
            recovery.prepare_sources(str(self.root), True)
        self.assertEqual((real / "ubuntu.sources").read_text(), STANZA)

    def test_hardlink_and_writable_files_refused(self):
        os.link(self.source, self.parts / "alias")
        with self.assertRaises(recovery.RecoveryError):
            recovery.prepare_sources(str(self.root), True)
        (self.parts / "alias").unlink()
        self.source.chmod(0o666)
        with self.assertRaises(recovery.RecoveryError):
            recovery.prepare_sources(str(self.root), True)
        self.assertEqual(self.source.read_text(), STANZA)

    def test_special_source_is_not_opened_as_a_stream(self):
        os.mkfifo(self.parts / "zz-pipe.list")
        with self.assertRaises(recovery.RecoveryError):
            recovery.prepare_sources(str(self.root), True)
        self.assertEqual(self.source.read_text(), STANZA)

    def test_existing_backup_must_not_be_overwritten(self):
        name = ".ubuntu.sources.acfs-eol-" + hashlib.sha256(STANZA.encode()).hexdigest()[:16] + ".bak"
        backup = self.parts / name
        backup.write_text("unrelated backup")
        backup.chmod(0o600)
        with self.assertRaises(recovery.RecoveryError):
            recovery.prepare_sources(str(self.root), True)
        self.assertEqual(backup.read_text(), "unrelated backup")
        self.assertEqual(self.source.read_text(), STANZA)

    def test_temp_collision_does_not_unlink_existing_file(self):
        existing = self.parts / ".acfs-eol-stage-fixture.tmp"
        existing.write_text("keep existing file")
        fake = types.SimpleNamespace(hex="fixture")
        with mock.patch.object(recovery.uuid, "uuid4", return_value=fake):
            with self.assertRaises(FileExistsError):
                recovery.prepare_sources(str(self.root), True)
        self.assertEqual(existing.read_text(), "keep existing file")
        self.assertEqual(self.source.read_text(), STANZA)

    def test_failed_staging_leaves_sources_unchanged(self):
        real = recovery.write_new
        def fail_staging(directory, name, *args, **kwargs):
            if name.endswith(".tmp"):
                raise OSError("injected staging failure")
            return real(directory, name, *args, **kwargs)
        with mock.patch.object(recovery, "write_new", side_effect=fail_staging):
            with self.assertRaises(OSError):
                recovery.prepare_sources(str(self.root), True)
        self.assertEqual(self.source.read_text(), STANZA)

    def test_concurrent_edits_are_not_overwritten(self):
        real = recovery.write_new
        def edit_source(*args, **kwargs):
            real(*args, **kwargs)
            if args[1].endswith(".tmp"):
                self.source.write_text(STANZA + "# concurrent change\n")
        with mock.patch.object(recovery, "write_new", side_effect=edit_source):
            with self.assertRaises(recovery.RecoveryError):
                recovery.prepare_sources(str(self.root), True)
        self.assertTrue(self.source.read_text().endswith("# concurrent change\n"))

    def test_partial_replace_failure_is_recoverable(self):
        other = self.parts / "zz-security.sources"
        other.write_text(STANZA.replace(OLD, "http://security.ubuntu.com/ubuntu"))
        real = os.replace
        calls = []
        def fail_second(*args, **kwargs):
            calls.append(args)
            if len(calls) == 2:
                raise OSError("injected rename failure")
            return real(*args, **kwargs)
        with mock.patch.object(recovery.os, "replace", side_effect=fail_second), contextlib.redirect_stderr(io.StringIO()) as output:
            with self.assertRaises(OSError):
                recovery.prepare_sources(str(self.root), True)
        self.assertIn("stopped after 1 replacement", output.getvalue())
        self.assertEqual(len(self.backups()), 2)
        self.assertEqual(recovery.prepare_sources(str(self.root), True), 1)
        self.assertEqual(recovery.prepare_sources(str(self.root), True), 0)

    def test_no_official_enabled_binary_source_refused(self):
        for text in ["Enabled: no\n" + STANZA, STANZA.replace(OLD, "https://mirror.example.test/ubuntu"), STANZA.replace("Types: deb deb-src", "Types: deb-src")]:
            with self.subTest(text=text):
                self.source.write_text(text)
                with self.assertRaises(recovery.RecoveryError):
                    recovery.prepare_sources(str(self.root), True)
                self.assertEqual(self.source.read_text(), text)

    def test_control_characters_and_size_limit(self):
        for text in [STANZA + "\0", STANZA + "#" * (1024 * 1024)]:
            with self.subTest(size=len(text)):
                self.source.write_text(text)
                with self.assertRaises(recovery.RecoveryError):
                    recovery.prepare_sources(str(self.root), True)

    def check_apt_parser(self, suffix, text):
        sources = self.root / ("parser." + suffix)
        sources.write_text(text)
        lists = self.root / "apt-lists"
        lists.mkdir()
        (lists / "partial").mkdir()
        # indextargets only reads local source/index metadata: no update,
        # downloads, dpkg changes, or host source files are involved.
        result = subprocess.run([
            "/usr/bin/apt-get",
            "-o", "Dir::Etc::sourcelist=" + str(sources),
            "-o", "Dir::Etc::sourceparts=-",
            "-o", "Dir::State::lists=" + str(lists),
            "-o", "Dir::State::status=/dev/null",
            "indextargets",
        ], env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"}, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_deb822_is_accepted_by_real_apt_parser(self):
        updated, _ = recovery.transform_sources(STANZA)
        self.check_apt_parser("sources", updated)

    def test_legacy_is_accepted_by_real_apt_parser(self):
        text = f"deb [arch=amd64 signed-by={KEY}] {OLD} questing main\n"
        updated, _ = recovery.transform_list(text)
        self.check_apt_parser("list", updated)

    def test_shell_wrapper_apply_and_dry_run(self):
        script = 'source "$1"; ubuntu_get_version_number() { echo 2510; }; ubuntu_prepare_eol_repositories "$2" "$3"'
        for mode in ["--dry-run", "apply"]:
            result = subprocess.run(["bash", "-c", script, "_", str(LIB), str(self.root), mode], env={"PATH": "/usr/bin:/bin", "UBUNTU_TARGET_VERSION": "26.04"}, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "")
            self.assertIn("preserved", result.stderr)
            self.assertEqual(self.source.read_text(), STANZA if mode == "--dry-run" else STANZA.replace(OLD, NEW))

    def test_shell_refuses_custom_apt_config(self):
        script = 'source "$1"; ubuntu_get_version_number() { echo 2510; }; ubuntu_prepare_eol_repositories "$2"'
        result = subprocess.run(["bash", "-c", script, "_", str(LIB), str(self.root)], env={"PATH": "/usr/bin:/bin", "UBUNTU_TARGET_VERSION": "26.04", "APT_CONFIG": "/custom/config"}, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.source.read_text(), STANZA)

    def test_supported_host_does_not_touch_repository_files(self):
        script = 'source "$1"; ubuntu_get_version_number() { echo 2404; }; ubuntu_prepare_eol_repositories "$2"'
        result = subprocess.run(["bash", "-c", script, "_", str(LIB), str(self.root)], env={"PATH": "/usr/bin:/bin", "UBUNTU_TARGET_VERSION": "26.04"}, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.source.read_text(), STANZA)
        self.assertEqual(self.backups(), [])


class UpgradeIntegrationTests(unittest.TestCase):
    def check_gate(self, phase, failure):
        # Run the real Bash call sites, replacing only external effects and
        # the recovery result. Verify ordering, fail-closed behavior, and the
        # strict APT update option before any package upgrade can proceed.
        with tempfile.TemporaryDirectory(prefix="acfs-eol-gate-") as directory:
            log = Path(directory) / "calls"
            script = r'''set -euo pipefail
source "$1"
CALLS="$2"; PHASE="$3"; FAILURE="$4"
record() { printf '%s\n' "$*" >> "$CALLS"; }
log_step() { :; }; log_detail() { :; }; log_success() { :; }; log_error() { :; }
ubuntu_check_apt_state() { record audit; }
ubuntu_prepare_eol_repositories() { record recovery; [[ "$FAILURE" != recovery ]]; }
ubuntu_configure_release_prompt() { record prompt; }
apt-get() {
    record "apt $*"
    if [[ "$*" == *'update'* ]]; then
        [[ "$*" == *'APT::Update::Error-Mode=any'* ]] || return 99
        [[ "$FAILURE" != update ]] || return 1
    fi
}
do-release-upgrade() { record "release $*"; printf "New release '26.04 LTS' available.\n"; }
command() {
    if [[ "$*" == '-v do-release-upgrade' && "$FAILURE" == missing-upgrader ]]; then return 1; fi
    builtin command "$@"
}
if [[ "$PHASE" == preparation ]]; then ubuntu_prepare_upgrade; else ubuntu_get_next_upgrade; fi
'''
            result = subprocess.run(["bash", "-c", script, "_", str(LIB), str(log), phase, failure], env={"PATH": "/usr/bin:/bin", "UBUNTU_TARGET_VERSION": "26.04"}, capture_output=True, text=True, timeout=10)
            calls = log.read_text().splitlines()
            if failure in {"recovery", "update"}:
                self.assertNotEqual(result.returncode, 0, result.stderr)
                self.assertFalse(any("dist-upgrade" in call or call.startswith("release ") for call in calls), calls)
            else:
                self.assertEqual(result.returncode, 0, result.stderr)
            if phase == "preparation":
                self.assertEqual(calls[:2], ["audit", "recovery"])
            else:
                self.assertEqual(calls[0], "recovery")
            if failure == "recovery":
                self.assertFalse(any(call.startswith("apt ") or call == "prompt" for call in calls), calls)
            if failure == "missing-upgrader":
                self.assertIn("update", calls[1])
                self.assertIn("install -y ubuntu-release-upgrader-core", calls[2])
                self.assertEqual(calls[-2:], ["prompt", "release -c"])
            if failure == "none" and phase == "preparation":
                self.assertIn("update", calls[2])
                self.assertIn("dist-upgrade", calls[3])

    def test_discovery_stops_before_package_or_release_calls_on_recovery_failure(self):
        self.check_gate("discovery", "recovery")

    def test_preparation_stops_before_apt_on_recovery_failure(self):
        self.check_gate("preparation", "recovery")

    def test_prepare_uses_strict_update_before_package_upgrade(self):
        self.check_gate("preparation", "none")

    def test_failed_update_never_reaches_dist_upgrade(self):
        self.check_gate("preparation", "update")

    def test_missing_upgrader_bootstraps_after_repository_recovery(self):
        self.check_gate("discovery", "missing-upgrader")


if __name__ == "__main__":
    unittest.main(verbosity=2)
