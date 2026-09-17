#!/usr/bin/env python3
"""Execute the template's Bash driver through cloud-init's sh/argv boundary.

No network, package manager, user modification, or reboot is performed. Only
OS identity, root identity, paths, and curl are replaced in a temporary copy;
the script's branching, Bash interpreters, argument handling and exit status
run for real. The test runner itself needs only Python's standard library.
"""
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = ROOT / "scripts/providers/hetzner-cloud-init.yml"
SHA = "a" * 40


def template_parts():
    text = TEMPLATE.read_text()
    header, rest = text.split("    content: |\n", 1)
    lines = []
    for line in rest.splitlines():
        if line and not line.startswith("      "):
            break
        lines.append(line[6:] if line else "")
    driver = "\n".join(lines).rstrip() + "\n"
    command_line = text.split("runcmd:\n", 1)[1].splitlines()[0]
    command = json.loads(command_line.strip().removeprefix("- "))
    return text, header, driver, command


class CloudInitTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="acfs-provider-test-")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.text, self.header, self.original, self.command = template_parts()

    def run_driver(self, *, version="26.04", distro="ubuntu", uid="0",
                   api_body=SHA, api_status=0, download_status=0,
                   installer_status=0, payload=None):
        work = self.work
        release = work / "os-release"
        release.write_text(f"ID={shlex.quote(distro)}\nVERSION_ID={shlex.quote(version)}\n")
        curl = work / "curl"
        if payload is None:
            payload = (
                "#!/bin/bash\nset -eu\n"
                f"printf '%s\\0' \"$@\" > {shlex.quote(str(work / 'argv'))}\n"
                f"printf '%s' \"${{TARGET_USER:-}}\" > {shlex.quote(str(work / 'user'))}\n"
                f"printf '%s' \"${{BASH_SOURCE[0]:-}}\" > {shlex.quote(str(work / 'source'))}\n"
                f"printf 'ran' > {shlex.quote(str(work / 'executed'))}\n"
                "printf 'fixture installer output\\n'\n"
                f"exit {installer_status}\n"
            )
        curl.write_text(
            "#!/usr/bin/python3\nimport json, sys\nfrom pathlib import Path\n"
            f"work=Path({str(work)!r})\n"
            "args=sys.argv[1:]\n"
            "with (work/'curl.jsonl').open('a') as f: f.write(json.dumps(args)+'\\n')\n"
            "if '-o' not in args:\n"
            f"    sys.stdout.write({api_body!r})\n    sys.exit({api_status})\n"
            f"Path(args[args.index('-o')+1]).write_text({payload!r})\n"
            f"sys.exit({download_status})\n"
        )
        curl.chmod(0o700)
        driver = self.original
        edits = {
            '"$EUID"': f'"{uid}"',  # Fixture identity, not an environment seam in production.
            "log_dir=/var/log/acfs": f"log_dir={shlex.quote(str(work / 'logs'))}",
            "run_dir=/run/acfs-cloud-init": f"run_dir={shlex.quote(str(work / 'run'))}",
            ". /etc/os-release": f". {shlex.quote(str(release))}",
            'curl "${curl_args[@]}"': f'{shlex.quote(str(curl))} "${{curl_args[@]}}"',
        }
        for old, new in edits.items():
            self.assertIn(old, driver)
            driver = driver.replace(old, new)
        script = work / "driver.sh"
        script.write_text(driver)
        subprocess.run(["/bin/bash", "-n", str(script)], check=True, capture_output=True)
        argv = [*self.command[:-1], str(script)]
        runcmd = work / "runcmd"
        runcmd.write_text("#!/bin/sh\n" + shlex.join(argv) + "\n")
        subprocess.run(["/bin/sh", "-n", str(runcmd)], check=True, capture_output=True)
        env = os.environ.copy()
        # These must not override the selected source or target user.
        env.update({"ACFS_REF": "attacker-ref", "TARGET_USER": "root"})
        for key in ("BASH_ENV", "ENV", "LD_PRELOAD", "LD_LIBRARY_PATH"):
            env.pop(key, None)
        result = subprocess.run(["/bin/sh", str(runcmd)], env=env,
                                text=True, capture_output=True, timeout=15)
        log = work / "logs/cloud-init.log"
        return result, log.read_text() if log.exists() else ""

    def test_template_uses_explicit_privileged_bash(self):
        self.assertEqual(self.command, ["/bin/bash", "-p", "/var/lib/acfs/cloud-init-install.sh"])
        self.assertTrue(self.original.startswith("#!/bin/bash\nset -euo pipefail\n"))
        self.assertNotIn(">(tee", self.text)
        self.assertIn("permissions: '0700'", self.header)
        self.assertIn("owner: root:root", self.header)

    def test_preserves_provider_ssh_keys_and_image_user(self):
        self.assertIn("users:\n  - default\n", self.text)
        self.assertNotIn("ssh_authorized_keys:", self.text)
        self.assertNotIn("ssh-ed25519 AAAA", self.text)
        self.assertNotIn("ssh_pwauth:", self.text)
        self.assertIn("package_upgrade: false", self.text)

    def test_final_message_does_not_claim_installation_success(self):
        final = self.text.split("final_message:", 1)[1]
        self.assertNotIn("ACFS cloud-init complete", final)
        self.assertIn("cloud-init status --long", final)

    def test_success_streams_complete_installer_with_pinned_arguments(self):
        result, log = self.run_driver()
        self.assertEqual(result.returncode, 0, result.stderr + log)
        self.assertIn("installer succeeded", log)
        args = (self.work / "argv").read_bytes().decode().split("\0")[:-1]
        self.assertEqual(args, ["--yes", "--mode", "vibe", "--target-ubuntu=26.04",
                                "--skip-ubuntu-upgrade", "--ref", SHA])
        self.assertEqual((self.work / "user").read_text(), "ubuntu")
        self.assertEqual((self.work / "source").read_text(), "")
        self.assertIn("fixture installer output", (self.work / "logs/install.log").read_text())
        requests = [json.loads(x) for x in (self.work / "curl.jsonl").read_text().splitlines()]
        self.assertEqual(len(requests), 2)
        self.assertTrue(requests[0][-1].endswith("/commits/main"))
        self.assertTrue(requests[1][-1].endswith(f"/{SHA}/install.sh"))
        for request in requests:
            self.assertEqual(request[0], "-q")
            self.assertEqual(request[request.index("--proto") + 1], "=https")
            self.assertEqual(request[request.index("--proto-redir") + 1], "=https")

    def test_point_release_is_accepted(self):
        result, log = self.run_driver(version="26.04.1")
        self.assertEqual(result.returncode, 0, log)

    def test_root_is_required_before_any_download(self):
        result, _ = self.run_driver(uid="1000")
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.work / "curl.jsonl").exists())

    def test_non_ubuntu_is_refused_before_download(self):
        result, log = self.run_driver(distro="debian")
        self.assertEqual(result.returncode, 1, log)
        self.assertFalse((self.work / "curl.jsonl").exists())

    def test_release_resolution_error_does_not_execute_even_with_valid_body(self):
        result, log = self.run_driver(api_status=22)
        self.assertEqual(result.returncode, 22, log)
        self.assertFalse((self.work / "executed").exists())
        self.assertNotIn("installer succeeded", log)

    def test_partial_download_never_executes(self):
        result, log = self.run_driver(download_status=18)
        self.assertEqual(result.returncode, 18, log)
        self.assertFalse((self.work / "executed").exists())
        self.assertNotIn("installer succeeded", log)

    def test_empty_installer_is_refused(self):
        result, log = self.run_driver(payload="")
        self.assertEqual(result.returncode, 1, log)
        self.assertFalse((self.work / "executed").exists())

    def test_syntax_error_in_installer_is_refused(self):
        result, log = self.run_driver(payload="#!/bin/bash\nif then\n")
        self.assertNotEqual(result.returncode, 0, log)
        self.assertFalse((self.work / "executed").exists())


# Each case is reported independently, not hidden behind one passing loop.
def failure_case(**kwargs):
    def check(self):
        result, log = self.run_driver(**kwargs)
        self.assertNotEqual(result.returncode, 0, log)
        self.assertFalse((self.work / "executed").exists())
        self.assertNotIn("installer succeeded", log)
    return check


for index, version in enumerate(["", "22.04", "24.04", "25.10", "26.10", "28.04", "26.04 trailing"]):
    setattr(CloudInitTest, f"test_unsupported_image_{index}", failure_case(version=version))
for index, body in enumerate(["", "main", SHA[:12], SHA + "\n" + SHA, " " + SHA, '{"sha":"' + SHA + '"}']):
    setattr(CloudInitTest, f"test_ambiguous_resolution_{index}", failure_case(api_body=body))
for status in (1, 2, 17, 137):
    def check(self, status=status):
        result, log = self.run_driver(installer_status=status)
        self.assertEqual(result.returncode, status, log)
        self.assertTrue((self.work / "executed").exists())
        self.assertIn("FAILED", log)
        self.assertNotIn("installer succeeded", log)
    setattr(CloudInitTest, f"test_installer_status_{status}_propagates", check)


if __name__ == "__main__":
    unittest.main(verbosity=2)
