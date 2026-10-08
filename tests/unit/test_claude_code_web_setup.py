"""Real entrypoint tests with controlled downloads, not live-cloud evidence.

Each case retains its scratch directory; there is no automatic deletion.
"""
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time
import unittest
from unittest import mock
import warnings
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/claude-code-web-setup.sh"
MANIFEST_URL = "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/cloud-mirror.json"
publisher_spec = importlib.util.spec_from_file_location("cloud_publisher", ROOT / "scripts/cloud-mirror-publish.py")
publisher = importlib.util.module_from_spec(publisher_spec)
publisher_spec.loader.exec_module(publisher)


class MirrorPublisher(unittest.TestCase):
    def setUp(self):
        self.stage = Path(tempfile.mkdtemp(prefix="acfs-publisher-test-"))

    def tar(self, names):
        out = io.BytesIO()
        with tarfile.open(fileobj=out, mode="w:gz") as archive:
            for name in names:
                info = tarfile.TarInfo(name)
                info.size = 3
                archive.addfile(info, io.BytesIO(b"bin"))
        return out.getvalue()

    def release(self, tool="bv", checksums=True, signature=False):
        _, pattern, bins, _ = publisher.TOOLS[tool]
        name = pattern.format(v="1.2.3")
        data = self.tar(bins)
        work = self.stage / tool / "v1.2.3"
        work.mkdir(parents=True)
        payloads = {name: data}
        if checksums:
            payloads[name + ".sha256"] = (publisher.digest(data) + "  " + name + "\n").encode()
        if signature:
            payloads[name + ".minisig"] = b"invalid signature"
        for filename, content in payloads.items():
            (work / filename).write_bytes(content)
        return {"tag_name": "v1.2.3", "assets": [
            {"name": filename, "digest": "sha256:" + publisher.digest(content),
             "browser_download_url": "https://upstream.invalid/" + filename}
            for filename, content in payloads.items()]}

    def prepare(self, release, tool="bv", signature_error=False):
        def run(*args):
            if args[0] == "gh":
                return json.dumps(release)
            if args[0] == "minisign" and signature_error:
                raise subprocess.CalledProcessError(1, args)
            self.fail("Unexpected external command: " + repr(args))
        with mock.patch.object(publisher, "run", side_effect=run), mock.patch.object(publisher, "fetch", side_effect=AssertionError("Unexpected network")):
            return publisher.prepare(tool, self.stage)

    def test_normalized_bundle_is_reproducible(self):
        files = {"bin/br": b"executable", "share/ubs/modules/data.json": b"{}"}
        first = publisher.bundle(files)
        self.assertEqual(first, publisher.bundle(dict(reversed(list(files.items())))))
        with tarfile.open(fileobj=io.BytesIO(first), mode="r:gz") as archive:
            self.assertEqual(archive.getmember("bin/br").mode, 0o755)
            self.assertEqual(archive.getmember("share/ubs/modules/data.json").mode, 0o644)

    def test_duplicate_tar_and_zip_members_rejected(self):
        with self.assertRaisesRegex(ValueError, "Duplicate upstream"):
            publisher.archive_files(self.tar(["bin/br", "bin/br"]), "br.tar.gz")
        out = io.BytesIO()
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(out, "w") as archive:
                archive.writestr("br", b"one")
                archive.writestr("br", b"two")
        with self.assertRaisesRegex(ValueError, "Duplicate upstream"):
            publisher.archive_files(out.getvalue(), "br.zip")

    def test_oversized_archive_rejected_before_reading_body(self):
        info = tarfile.TarInfo("large")
        info.size = 1024 * 1024 * 1024 + 1
        with self.assertRaisesRegex(ValueError, "beyond 1 GiB"):
            publisher.archive_files(info.tobuf(), "large.tar.gz")

    def test_valid_release_packages_expected_binary(self):
        tool, entry = self.prepare(self.release())
        self.assertEqual(tool, "bv")
        packed = (self.stage / entry["file"]).read_bytes()
        self.assertEqual(publisher.digest(packed), entry["sha256"])
        self.assertEqual(publisher.archive_files(packed, entry["file"]), {"bin/bv": b"bin"})

    def test_asset_digest_mismatch_blocks_packaging(self):
        release = self.release()
        release["assets"][0]["digest"] = "sha256:" + "0" * 64
        with self.assertRaisesRegex(ValueError, "digest mismatch"):
            self.prepare(release)

    def test_release_checksum_mismatch_blocks_packaging(self):
        release = self.release()
        checksum = release["assets"][1]
        wrong = ("0" * 64 + "  " + release["assets"][0]["name"] + "\n").encode()
        (self.stage / "bv/v1.2.3" / checksum["name"]).write_bytes(wrong)
        checksum["digest"] = "sha256:" + publisher.digest(wrong)
        with self.assertRaisesRegex(ValueError, "upstream checksum mismatch"):
            self.prepare(release)

    def test_missing_checksum_and_required_signature_fail_closed(self):
        with self.assertRaisesRegex(ValueError, "missing upstream checksum"):
            self.prepare(self.release(checksums=False))
        with self.assertRaisesRegex(ValueError, "expected release signature"):
            self.prepare(self.release(tool="br"), tool="br")

    def test_bad_signature_blocks_packaging(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.prepare(self.release(tool="br", signature=True), tool="br", signature_error=True)

    def test_unsafe_tag_fails_before_download(self):
        for tag in ("../../escape", ".", ".."):
            with self.subTest(tag=tag), self.assertRaisesRegex(ValueError, "Unsafe release tag"):
                self.prepare({"tag_name": tag, "assets": []})

    def test_unsafe_jsm_relay_tag_never_fetches_checksums(self):
        with mock.patch.object(publisher, "fetch", return_value=b"../../escape") as fetch:
            with self.assertRaisesRegex(ValueError, "Unsafe release tag"):
                publisher.prepare("jsm", self.stage)
        fetch.assert_called_once_with("https://jeffreys-skills.md/api/v1/downloads/jsm/latest.txt")

    def test_jsm_relay_checksum_requires_one_matching_row(self):
        for checksums in (b'\n', b'bad  jsm-x86_64-unknown-linux-musl.tar.gz\n',
                          (('a' * 64 + '  jsm-x86_64-unknown-linux-musl.tar.gz\n') * 2).encode()):
            with self.subTest(checksums=checksums), mock.patch.object(publisher, 'fetch', side_effect=[b'v1.2.3', checksums]):
                with self.assertRaisesRegex(ValueError, 'JSM relay checksum'):
                    publisher.prepare('jsm', self.stage)

    def test_partial_refresh_keeps_all_unselected_tools(self):
        current = json.loads((ROOT / 'cloud-mirror.json').read_text())
        replacement = {'version': 'updated', 'sha256': 'a' * 64}
        output = self.stage / 'candidate.json'
        argv = ['publisher', '--stage', str(self.stage), '--output', str(output), '--tools', 'bv']
        with mock.patch('sys.argv', argv), mock.patch.object(publisher, 'prepare', return_value=('bv', replacement)):
            publisher.main()
        candidate = json.loads(output.read_text())
        self.assertEqual(set(candidate['tools']), set(current['tools']))
        self.assertEqual(candidate['tools']['bv'], replacement)
        self.assertEqual(candidate['tools']['br'], current['tools']['br'])

    def test_duplicate_selection_and_unsafe_base_fail_before_preparing(self):
        for extra in (['--tools', 'bv', 'bv'], ['--base-url', 'http://mirror.invalid'],
                      ['--base-url', 'https://mirror.invalid/../escape']):
            argv = ['publisher', '--stage', str(self.stage), '--output', str(self.stage / 'unused.json'), *extra]
            with self.subTest(extra=extra), mock.patch('sys.argv', argv), mock.patch.object(publisher, 'prepare') as prepare:
                with self.assertRaises(SystemExit):
                    publisher.main()
                prepare.assert_not_called()

    def test_publish_uses_configured_url_path_as_object_prefix(self):
        packed = b'verified archive'
        entry = {'file': 'bv/v1/bundle.tar.gz', 'sha256': publisher.digest(packed)}
        argv = ['publisher', '--stage', str(self.stage), '--output', str(self.stage / 'published.json'),
                '--base-url', 'https://mirror.invalid/custom/prefix', '--publish']
        missing = publisher.urllib.error.HTTPError('https://mirror.invalid', 404, 'missing', {}, io.BytesIO())
        with mock.patch('sys.argv', argv), mock.patch.object(publisher, 'prepare', side_effect=lambda tool, stage: (tool, entry)), \
                mock.patch.object(publisher, 'fetch', side_effect=[value for _ in publisher.TOOLS for value in (missing, packed)]), \
                mock.patch.object(publisher, 'run') as run:
            publisher.main()
        self.assertEqual(run.call_count, len(publisher.TOOLS))
        self.assertEqual(run.call_args_list[0].args[4], 'acfs-cloud-tools/custom/prefix/bv/v1/bundle.tar.gz')

    def test_ubs_requires_complete_nonempty_checksum_tables(self):
        valid = "declare -A MODULE_CHECKSUMS=(\n['js']='" + "a" * 64 + "'\n)\ndeclare -A HELPER_CHECKSUMS=(\n['helper.py']='" + "b" * 64 + "'\n)"
        self.assertEqual(publisher.ubs_helpers(valid), [("ubs-js.sh", "a" * 64), ("helper.py", "b" * 64)])
        for invalid in ("", "declare -A MODULE_CHECKSUMS=(\n)", valid.replace("b" * 64, "wrong"), valid.replace("helper.py", "../escape")):
            with self.subTest(source=invalid), self.assertRaises(ValueError):
                publisher.ubs_helpers(invalid)


class CloudSetup(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="acfs-cloud-test-")).resolve()
        self.home = self.root / "home"
        self.bin = self.root / "bin"
        for path in (self.home, self.bin, self.root / "tmp"):
            path.mkdir()
        self.urls = {}
        self.manifest = {"schema": 1, "platform": "linux-x86_64", "base_url": "https://mirror.invalid/v1", "tools": {}}
        self.command("uname", '#!/bin/sh\ncase "$1" in -s) echo Linux;; -m) echo x86_64;; esac\n')
        self.command("curl", f'''#!{shutil.which('python3')}
import json, pathlib, sys, time
root=pathlib.Path({str(self.root)!r})
args=sys.argv[1:]; url=args[-1]
with (root/'requests').open('a') as log: log.write(url+'\\n')
mapping=json.loads((root/'urls.json').read_text())
if url not in mapping:
    if (root/'deny-connect').exists(): print('403', end='')
    sys.exit(22)
if url.endswith('/hang'): time.sleep(60)
pathlib.Path(args[args.index('-o')+1]).write_bytes(pathlib.Path(mapping[url]).read_bytes())
''')
        timeout = shutil.which("timeout") or shutil.which("gtimeout")
        if not timeout:
            self.fail("GNU timeout is required to test the actual process deadline")
        (self.bin / "timeout").symlink_to(timeout)
        for name in ("cargo", "go", "git", "npm", "bun"):
            self.command(name, f'#!/bin/sh\necho {name} >> "{self.root}/forbidden"\nexit 99\n')
        self.env = {"HOME": str(self.home), "TMPDIR": str(self.root / "tmp"),
                    "PATH": str(self.bin) + ":/usr/bin:/bin", "ACFS_CLOUD_TIMEOUT": "10"}
        (self.bin / "python3").symlink_to(shutil.which("python3"))

    def command(self, name, code):
        dest = self.bin / name
        dest.write_text(code)
        dest.chmod(0o755)

    def serve(self, url, data):
        path = self.root / ("response-" + hashlib.sha256(url.encode()).hexdigest())
        path.write_bytes(data)
        self.urls[url] = str(path)

    def bundle(self, tool="br", content=None, extra=None):
        bins = ["am", "mcp-agent-mail"] if tool == "am" else [tool]
        out = io.BytesIO()
        with tarfile.open(fileobj=out, mode="w:gz") as tar:
            for binary in bins:
                code = content if content is not None else f"#!/bin/sh\necho '{binary} 1.2.3'\n".encode()
                info = tarfile.TarInfo("bin/" + binary)
                info.size, info.mode = len(code), 0o755
                tar.addfile(info, io.BytesIO(code))
            if extra:
                info, data = extra
                tar.addfile(info, io.BytesIO(data))
        data = out.getvalue()
        file = tool + "/v1/bundle.tar.gz"
        self.manifest["tools"][tool] = {"version": "v1", "file": file, "sha256": hashlib.sha256(data).hexdigest(), "bins": bins}
        self.serve("https://mirror.invalid/v1/" + file, data)

    def run_setup(self, tools="br", **options):
        self.serve(MANIFEST_URL, json.dumps(self.manifest).encode())
        (self.root / "urls.json").write_text(json.dumps(self.urls))
        result = subprocess.run(["bash", str(SCRIPT)], env={**self.env, "ACFS_CLOUD_TOOLS": tools, **options},
                                capture_output=True, text=True, timeout=30, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "forbidden").exists(), "Attempted source build or clone")
        return result.stderr

    def test_installs_verified_bundle_and_never_calls_github(self):
        self.bundle()
        output = self.run_setup()
        self.assertIn("br 1.2.3", output)
        self.assertTrue((self.home / ".local/bin/br").is_file())
        self.assertNotIn("github.com/", (self.root / "requests").read_text())

    def test_codex_preserves_instructions_and_never_registers_claude_mcp(self):
        self.bundle('am')
        codex_home = self.home / 'custom-codex'
        codex_home.mkdir()
        guide = codex_home / 'AGENTS.md'
        guide.write_text('Keep my existing instructions.\n')
        override = codex_home / 'AGENTS.override.md'
        override.write_text('Existing override.\n')
        self.command('claude', f'#!/bin/sh\ntouch "{self.root}/claude-called"\n')
        for _ in range(2):
            output = self.run_setup('am', ACFS_CLOUD_AGENT='codex', CODEX_HOME=str(codex_home))
        self.assertIn('AGENTS.override.md takes precedence', output)
        self.assertEqual(override.read_text(), 'Existing override.\n')
        self.assertTrue(guide.read_text().startswith('Keep my existing instructions.\n'))
        self.assertEqual(guide.read_text().count('<!-- BEGIN ACFS CLOUD TOOLS'), 1)
        self.assertIn('ACFS_CLOUD_AGENT=codex bash', guide.read_text())
        self.assertIn('Hosted Codex MCP registration is not configured', guide.read_text())
        self.assertFalse((self.root / 'claude-called').exists())
        self.assertFalse((self.home / '.claude').exists())

    def test_codex_default_guide_and_invalid_agent(self):
        self.bundle()
        self.run_setup(ACFS_CLOUD_AGENT='codex')
        self.assertTrue((self.home / '.codex/AGENTS.md').is_file())
        output = self.run_setup(ACFS_CLOUD_AGENT='unknown')
        self.assertIn('ACFS_CLOUD_AGENT must be claude or codex', output)

    def test_checksum_mismatch_never_extracts_or_executes(self):
        self.bundle(content=f'#!/bin/sh\ntouch "{self.root}/executed"\n'.encode())
        self.manifest["tools"]["br"]["sha256"] = "0" * 64
        self.run_setup()
        self.assertFalse((self.root / "executed").exists())
        self.assertFalse((self.home / ".local/bin/br").exists())
        self.assertIn("checksum mismatch", (self.home / ".acfs/cloud/logs/br.log").read_text())

    def test_pinned_public_fallback_installs_without_source_build(self):
        self.bundle()
        entry = self.manifest['tools']['br']
        mirrored = self.urls.pop('https://mirror.invalid/v1/' + entry['file'])
        source_url = 'https://github.com/public/releases/download/v1/br.tar.gz'
        self.urls[source_url] = mirrored
        entry['source'] = {'url': source_url, 'asset': 'br.tar.gz', 'sha256': entry['sha256']}
        output = self.run_setup()
        self.assertIn('br 1.2.3', output)
        self.assertTrue((self.home / '.local/bin/br').is_file())
        self.assertIn('Trying pinned public release', (self.home / '.acfs/cloud/logs/br.log').read_text())

    def test_wrong_fallback_hash_never_installs(self):
        self.bundle()
        entry = self.manifest['tools']['br']
        upstream = self.urls.pop('https://mirror.invalid/v1/' + entry['file'])
        self.urls['https://upstream.invalid/br'] = upstream
        entry['source'] = {'url': 'https://upstream.invalid/br', 'asset': 'br.tar.gz', 'sha256': '0' * 64}
        self.run_setup()
        self.assertFalse((self.home / '.local/bin/br').exists())

    def test_invalid_manifest_platform_never_downloads_payload(self):
        self.bundle()
        self.manifest['platform'] = 'darwin-arm64'
        self.run_setup()
        self.assertEqual((self.root / 'requests').read_text().splitlines(), [MANIFEST_URL])

    def test_traversal_member_rejected_before_any_execution(self):
        info = tarfile.TarInfo("../../escape")
        info.size = 1
        self.bundle(extra=(info, b"x"))
        self.run_setup()
        self.assertIn("unsafe archive member", (self.home / ".acfs/cloud/logs/br.log").read_text())
        self.assertFalse((self.home / ".local/bin/br").exists())

    def test_symlink_member_rejected(self):
        info = tarfile.TarInfo("share/ubs/modules/linked")
        info.type, info.linkname = tarfile.SYMTYPE, "/tmp"
        self.bundle("ubs", extra=(info, b""))
        self.run_setup("ubs")
        self.assertFalse((self.home / ".local/bin/ubs").exists())

    def test_existing_destination_symlink_is_preserved(self):
        self.bundle()
        target = self.root / "untouched"
        target.write_text("keep")
        (self.home / ".local/bin").mkdir(parents=True)
        (self.home / ".local/bin/br").symlink_to(target)
        self.run_setup(ACFS_CLOUD_REINSTALL="1")
        self.assertEqual(target.read_text(), "keep")
        self.assertTrue((self.home / ".local/bin/br").is_symlink())

    def test_nonworking_binary_is_not_reported_installed(self):
        self.bundle(content=b"#!/bin/sh\necho broken\nexit 1\n")
        self.run_setup()
        self.assertFalse((self.home / ".local/bin/br").exists())
        self.assertIn("Not installed", (self.home / ".claude/CLAUDE.md").read_text())

    def test_binary_that_fails_at_installed_path_is_not_reported_working(self):
        self.bundle(content=b'#!/bin/sh\ncase "$0" in *-stage/bin/br) echo br-staged;; *) exit 1;; esac\n')
        output = self.run_setup()
        self.assertNotIn('(verified prebuilt)', output)
        self.assertIn('installed binary verification failed', output)
        self.assertIn('Not installed', (self.home / '.claude/CLAUDE.md').read_text())

    def test_existing_binary_probe_obeys_whole_job_deadline(self):
        self.command('br', '#!/bin/sh\ntrap "" TERM\nsleep 9\necho br-late\n')
        start = time.monotonic()
        output = self.run_setup(ACFS_CLOUD_TIMEOUT='1')
        self.assertLess(time.monotonic() - start, 5)
        self.assertIn('timed out', output)

    def test_blocked_network_keeps_existing_tools_and_reports_missing(self):
        self.command("br", "#!/bin/sh\necho br-existing\n")
        output = self.run_setup("br bv")
        self.assertIn("br-existing (already installed)", output)
        self.assertIn("no source build attempted", output)
        self.assertFalse((self.home / ".local/bin/bv").exists())

    def test_proxy_connect_denial_names_network_setting(self):
        self.bundle()
        self.urls.pop('https://mirror.invalid/v1/' + self.manifest['tools']['br']['file'])
        output = self.run_setup()
        self.assertNotIn('is blocked by this environment', output)
        (self.root / 'deny-connect').write_text('403')
        output = self.run_setup()
        log = (self.home / '.acfs/cloud/logs/br.log').read_text()
        self.assertIn('mirror.invalid is blocked by this environment', log)
        self.assertIn('set Full or allow it in Custom', log)
        self.assertIn('mirror.invalid is blocked by this environment', output)
        guide = (self.home / '.claude/CLAUDE.md').read_text()
        self.assertIn('mirror.invalid is blocked by this environment', guide)
        self.assertIn('set Full or allow it in Custom', guide)

    def test_partial_rerun_preserves_guide_and_previous_tools(self):
        self.bundle()
        (self.home / ".claude").mkdir()
        guide = self.home / ".claude/CLAUDE.md"
        guide.write_text("Keep this preference.\n")
        self.run_setup()
        self.bundle("bv")
        self.run_setup("bv")
        self.run_setup("bv")
        text = guide.read_text()
        self.assertTrue(text.startswith("Keep this preference.\n\n<!-- BEGIN"))
        self.assertEqual(text.count("<!-- BEGIN"), 1)
        self.assertIn("`br`", text)
        self.assertIn("`bv`", text)

    def test_malformed_managed_markers_preserve_all_user_instructions(self):
        self.bundle()
        (self.home / '.claude').mkdir()
        guide = self.home / '.claude/CLAUDE.md'
        begin = '<!-- BEGIN ACFS CLOUD TOOLS (managed by claude-code-web-setup.sh) -->'
        end = '<!-- END ACFS CLOUD TOOLS -->'
        for markers in (begin, end, begin + '\n' + begin + '\n' + end):
            original = 'My instructions.\n' + markers + '\nKeep these too.\n'
            guide.write_text(original)
            with self.subTest(markers=markers):
                output = self.run_setup()
                self.assertEqual(guide.read_text(), original)
                self.assertIn('Unbalanced ACFS guide markers', output)

    def test_partial_rerun_does_not_claim_incomplete_agent_mail(self):
        self.command('am', '#!/bin/sh\necho am-existing\n')
        self.bundle()
        self.run_setup()
        self.assertNotIn('`am` / `mcp-agent-mail`', (self.home / '.claude/CLAUDE.md').read_text())

    def test_download_job_deadline_is_real(self):
        self.bundle()
        entry = self.manifest["tools"]["br"]
        self.urls["https://mirror.invalid/v1/hang"] = self.urls["https://mirror.invalid/v1/" + entry["file"]]
        entry["file"] = "hang"
        start = time.monotonic()
        output = self.run_setup(ACFS_CLOUD_TIMEOUT="1")
        self.assertLess(time.monotonic() - start, 8)
        self.assertIn("timed out", output)

    def test_agent_mail_registration_failure_is_truthful(self):
        self.bundle("am")
        self.command("claude", "#!/bin/sh\nexit 1\n")
        output = self.run_setup("am")
        self.assertIn("Could not register Agent Mail", output)
        self.assertNotIn("Registered as the stdio", (self.home / ".claude/CLAUDE.md").read_text())
        self.assertTrue((self.home / ".local/bin/mcp-agent-mail").is_file())

    def test_registers_agent_mail_without_removing_user_configuration(self):
        self.bundle('am')
        self.command('claude', f'#!/bin/sh\nprintf "%s\\n" "$*" >> "{self.root}/mcp-calls"\n[ "$2" = add ]\n')
        output = self.run_setup('am')
        calls = (self.root / 'mcp-calls').read_text()
        self.assertIn('mcp add --scope user mcp-agent-mail -- ', calls)
        self.assertIn('/am serve-stdio', calls)
        self.assertNotIn('remove', calls)
        self.assertIn('Registered Agent Mail', output)

    def test_migrates_only_old_acfs_registration_and_retains_backup(self):
        self.bundle('am')
        self.command('claude', '#!/bin/sh\n[ "$2" = get ]\n')
        config = self.home / '.claude.json'
        original = {'preferences': {'theme': 'dark'}, 'mcpServers': {
            'mcp-agent-mail': {'type': 'stdio', 'command': str(self.home / '.local/bin/mcp-agent-mail'), 'args': [], 'env': {'KEEP': 'value'}},
            'another-server': {'command': 'keep', 'args': ['original']}}}
        config.write_text(json.dumps(original))
        before = config.read_bytes()
        self.run_setup('am')
        migrated = json.loads(config.read_text())
        self.assertEqual(migrated['preferences'], original['preferences'])
        self.assertEqual(migrated['mcpServers']['another-server'], original['mcpServers']['another-server'])
        self.assertEqual(migrated['mcpServers']['mcp-agent-mail']['env'], {'KEEP': 'value'})
        self.assertEqual(migrated['mcpServers']['mcp-agent-mail']['args'], ['serve-stdio'])
        backups = list((self.root / 'tmp').glob('acfs-cloud.*/claude.json.before-stdio-fix'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), before)
        self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)
        self.run_setup('am')
        self.assertEqual(len(list((self.root / 'tmp').glob('acfs-cloud.*/claude.json.before-stdio-fix'))), 1)

    def test_retains_custom_existing_mcp_registration(self):
        self.bundle('am')
        self.command('claude', '#!/bin/sh\n[ "$2" = get ]\n')
        config = self.home / '.claude.json'
        original = b'{"mcpServers":{"mcp-agent-mail":{"type":"http","url":"https://my-server.invalid/mcp"}}}\n'
        config.write_bytes(original)
        self.run_setup('am')
        self.assertEqual(config.read_bytes(), original)

    def test_missing_second_agent_mail_binary_rejected(self):
        self.bundle("am")
        self.manifest["tools"]["am"]["bins"] = ["am"]
        self.run_setup("am")
        self.assertFalse((self.home / ".local/bin/am").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
