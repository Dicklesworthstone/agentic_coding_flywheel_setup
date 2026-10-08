"""Real entrypoint tests with controlled downloads, not live-cloud evidence.

Each case retains its scratch directory; there is no automatic deletion.
"""
import hashlib
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

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/claude-code-web-setup.sh"
MANIFEST_URL = "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/cloud-mirror.json"


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

    def test_blocked_network_keeps_existing_tools_and_reports_missing(self):
        self.command("br", "#!/bin/sh\necho br-existing\n")
        output = self.run_setup("br bv")
        self.assertIn("br-existing (already installed)", output)
        self.assertIn("no source build attempted", output)
        self.assertFalse((self.home / ".local/bin/bv").exists())

    def test_proxy_connect_denial_names_network_setting(self):
        self.bundle()
        self.urls.pop('https://mirror.invalid/v1/' + self.manifest['tools']['br']['file'])
        (self.root / 'deny-connect').write_text('403')
        self.run_setup()
        log = (self.home / '.acfs/cloud/logs/br.log').read_text()
        self.assertIn('mirror.invalid is blocked by this environment', log)
        self.assertIn('set Full or allow it in Custom', log)

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
        self.assertNotIn('remove', calls)
        self.assertIn('Registered Agent Mail', output)

    def test_missing_second_agent_mail_binary_rejected(self):
        self.bundle("am")
        self.manifest["tools"]["am"]["bins"] = ["am"]
        self.run_setup("am")
        self.assertFalse((self.home / ".local/bin/am").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
