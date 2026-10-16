#!/usr/bin/env python3
"""Read-only fixtures execute the doctor's embedded production source auditor."""
import hashlib
from pathlib import Path
import tempfile
import subprocess
import types
import unittest

DOCTOR = Path(__file__).resolve().parents[2] / 'scripts/lib/doctor.sh'
CODE = DOCTOR.read_text().split("<<'ACFS_APT_AUDIT_PY'\n", 1)[1].split('\nACFS_APT_AUDIT_PY\n', 1)[0]
audit_module = types.ModuleType('audit')
exec(compile(CODE, str(DOCTOR), 'exec'), audit_module.__dict__)
URI = 'http://archive.ubuntu.com/ubuntu'
STANZA = f'Types: deb\nURIs: {URI}\nSuites: resolute resolute-updates\nComponents: main universe\n'


class SourceAuditTests(unittest.TestCase):
    def run_fixture(self, files, release='ID=ubuntu\nVERSION_CODENAME=resolute\n'):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            os_release = root / 'os-release'
            os_release.write_text(release)
            apt = root / 'apt'
            (apt / 'sources.list.d').mkdir(parents=True)
            for name, content in files.items():
                (apt / name).write_text(content)
            def snapshot():
                return {str(p): (hashlib.sha256(p.read_bytes()).hexdigest(), p.stat().st_mtime_ns)
                        for p in root.rglob('*') if p.is_file()}
            before = snapshot()
            messages, status = audit_module.audit(os_release, apt)
            self.assertEqual(before, snapshot(), 'audit must not modify any file')
            return '\n'.join(messages), status

    def test_reported_legacy_layout_and_unique_temp_options(self):
        output, status = self.run_fixture({
            'sources.list.d/ubuntu.sources': STANZA.replace('resolute', 'noble') + 'Signed-By: /keyring\n',
            'sources.list.d/ubuntu-acfs-temp.sources': STANZA + 'Architectures: amd64 arm64\n' +
                '\n' + STANZA.replace('main universe', 'restricted multiverse')})
        self.assertEqual(status, 1)
        self.assertIn('ubuntu.sources:1', output)
        self.assertIn('noble, noble-updates', output)
        self.assertIn('Legacy ACFS upgrade layout', output)

    def test_healthy_mixed_formats_and_multiline_fields(self):
        output, status = self.run_fixture({
            'sources.list': f'deb-src [arch=amd64 signed-by=/key] {URI} resolute-security main\n',
            'sources.list.d/ubuntu.sources': STANZA.replace('resolute resolute-updates', 'resolute\n resolute-updates')})
        self.assertEqual(status, 0, output)

    def test_disabled_old_sources_and_vendors(self):
        output, status = self.run_fixture({
            'sources.list': f'# deb {URI} noble main\ndeb https://vendor.example/ubuntu noble main\n',
            'sources.list.d/old.sources': 'Enabled: no\n' + STANZA.replace('resolute', 'noble'),
            'sources.list.d/ubuntu.sources.disabled': STANZA.replace('resolute', 'noble'),
            'sources.list.d/vendor.sources': STANZA.replace(URI, 'https://ppa.launchpadcontent.net/test/ubuntu').replace('resolute', 'noble')})
        self.assertEqual(status, 0, output)

    def test_malformed_files_warn_without_masking_other_mismatches(self):
        for malformed in ('URIs broken\n', STANZA + 'Suites: noble\n', ' orphan\n'):
            output, status = self.run_fixture({
                'sources.list.d/broken.sources': malformed,
                'sources.list': f'deb {URI} noble main\n'})
            self.assertEqual(status, 1)
            self.assertIn('broken.sources', output)
            self.assertIn('sources.list:1', output)
            self.assertIn('manual review', output)

    def test_malformed_legacy_and_missing_components(self):
        for text in (f'deb [arch=amd64 {URI} resolute main\n',
                     f'deb {URI} resolute\n', 'not a source\n'):
            output, status = self.run_fixture({'sources.list': text})
            self.assertEqual(status, 1, output)
            self.assertIn('manual review required', output)

    def test_architecture_and_component_differences_are_not_trust_conflicts(self):
        output, status = self.run_fixture({
            'sources.list.d/a.sources': STANZA + 'Architectures: amd64\n',
            'sources.list.d/b.sources': STANZA.replace('main universe', 'multiverse') + 'Architectures: arm64\n'})
        self.assertEqual(status, 0, output)

    def test_conflicting_trust_is_reported_without_exposing_key(self):
        output, status = self.run_fixture({
            'sources.list.d/a.sources': STANZA + 'Signed-By: /secret-key-path\n',
            'sources.list.d/b.sources': STANZA})
        self.assertEqual(status, 1)
        self.assertIn('conflicting trust settings', output)
        self.assertIn('a.sources:1', output)
        self.assertIn('b.sources:1', output)
        self.assertNotIn('/secret-key-path', output)

    def test_no_layout_inference_from_names_alone(self):
        output, status = self.run_fixture({
            'sources.list.d/ubuntu.sources': STANZA.replace('resolute', 'noble'),
            'sources.list.d/ubuntu-acfs-temp.sources': STANZA.replace(URI, 'https://vendor.example/ubuntu')})
        self.assertEqual(status, 1)
        self.assertNotIn('Legacy ACFS upgrade layout', output)

    def test_release_metadata_is_never_executed(self):
        for metadata in ('ID=ubuntu\n', 'ID=ubuntu\nVERSION_CODENAME=resolute\nUBUNTU_CODENAME=noble\n',
                         'ID=ubuntu\nVERSION_CODENAME=$(false)\n'):
            output, status = self.run_fixture({}, metadata)
            self.assertEqual(status, 1, output)
        self.assertEqual(self.run_fixture({}, 'ID=arch\n')[1], 3)

    def test_official_endpoints_and_vendor_lookalikes(self):
        for host, path in [('us.archive.ubuntu.com', 'ubuntu'), ('ports.ubuntu.com', 'ubuntu-ports'),
                           ('security.ubuntu.com', 'ubuntu'), ('old-releases.ubuntu.com', 'ubuntu')]:
            output, status = self.run_fixture({'sources.list': f'deb https://{host}/{path} noble main\n'})
            self.assertEqual(status, 1, output)
        output, status = self.run_fixture({'sources.list': 'deb https://archive.ubuntu.com.evil.test/ubuntu noble main\n'})
        self.assertEqual(status, 0, output)

    def test_shell_wrapper_emits_doctor_status_and_is_wired_into_main(self):
        source = DOCTOR.read_text()
        function = source.split('check_ubuntu_archive_suites() {', 1)[1].split('\ncheck_identity() {', 1)[0]
        function = 'check_ubuntu_archive_suites() {' + function
        self.assertIn('    check_identity\n    check_ubuntu_archive_suites\n', source)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            release = root / 'os-release'
            release.write_text('ID=ubuntu\nVERSION_CODENAME=resolute\n')
            apt = root / 'apt'
            apt.mkdir()
            for suite, expected in [('resolute', 'pass'), ('noble', 'warn')]:
                (apt / 'sources.list').write_text(f'deb {URI} {suite} main\n')
                result = subprocess.run(['bash', '-c',
                    'set -euo pipefail\ncheck() { printf "%s\\n" "$1" "$3" "$4"; }\n' +
                    function + '\ncheck_ubuntu_archive_suites "$1" "$2"',
                    'fixture', str(release), str(apt)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('system.ubuntu_archive_suites\n' + expected, result.stdout)


if __name__ == '__main__':
    unittest.main()
