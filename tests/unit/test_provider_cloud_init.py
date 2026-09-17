#!/usr/bin/env python3
"""Execute the template's Bash driver through cloud-init's sh/argv boundary.

No network, package manager, user modification, or reboot is performed. Only
OS/root identity, paths, network commands, account lookup, package audit and
user switching are replaced in a temporary copy; optional write/sync failures
are injected at external-command boundaries. Bash, sh, jq, filesystem writes,
flock, timeout and exit-status handling run for real. The test runner itself needs only Python's standard library.
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
                   installer_status=0, payload=None, driver_args=(),
                   doctor_status=0, doctor_document=None, doctor_missing=False,
                   getent_status=0, getent_entry=None, fail_write=None,
                   git_status=1, git_body="", fail_sync=None,
                   doctor_sleep=0, doctor_deadline="300s", runuser_status=0,
                   audit_status=0, audit_output=""):
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
                f"printf 'ran\\n' >> {shlex.quote(str(work / 'executed'))}\n"
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
        git = work / "git"
        git.write_text(
            "#!/usr/bin/python3\nimport json, os, sys\nfrom pathlib import Path\n"
            f"work=Path({str(work)!r})\n"
            "with (work/'git.jsonl').open('a') as f: f.write(json.dumps({'argv':sys.argv[1:],'env':dict(os.environ)})+'\\n')\n"
            f"sys.stdout.write({git_body!r})\nsys.exit({git_status})\n"
        )
        git.chmod(0o700)
        home = work / "home with spaces"
        home.mkdir(exist_ok=True)
        (home / ".acfs/bin").mkdir(parents=True, exist_ok=True)
        doctor = home / ".acfs/bin/acfs"
        if doctor_document is None:
            doctor_document = json.dumps({
                "acfs_version": "0.9.0", "user": "ubuntu", "mode": "vibe",
                "os": {"id": "ubuntu", "version": version},
                "checks": [{"id": "fixture.installed", "status": "pass"}],
                "summary": {"pass": 1, "warn": 0, "skip": 0, "fail": 0},
            })
        doctor.write_text(
            "#!/bin/bash\n"
            f"sleep {float(doctor_sleep)}\n"
            f"printf 'checked\\n' >> {shlex.quote(str(work / 'doctor-runs'))}\n"
            f"printf '%s' {shlex.quote(doctor_document)}\nexit {doctor_status}\n"
        )
        doctor.chmod(0o600 if doctor_missing else 0o700)
        getent = work / "getent"
        if getent_entry is None:
            getent_entry = f"ubuntu:x:1000:1000:Ubuntu:{home}:/bin/bash"
        getent.write_text("#!/bin/bash\n" + f"printf '%s\\n' {shlex.quote(getent_entry)}\nexit {getent_status}\n")
        getent.chmod(0o700)
        runuser = work / "runuser"
        runuser.write_text(
            "#!/usr/bin/python3\nimport json, os, sys\nfrom pathlib import Path\n"
            f"work=Path({str(work)!r})\n"
            "args=sys.argv[1:]\n"
            "with (work/'runuser.jsonl').open('a') as f: f.write(json.dumps(args)+'\\n')\n"
            "assert args[:3] == ['-u', 'ubuntu', '--']\n"
            f"if {runuser_status}: sys.exit({runuser_status})\n"
            "os.execvp(args[3], args[3:])\n"
        )
        runuser.chmod(0o700)
        dpkg = work / "dpkg"
        dpkg.write_text(
            "#!/bin/bash\n"
            f"printf '%s\\n' \"$*\" >> {shlex.quote(str(work / 'dpkg-calls'))}\n"
            f"printf '%s' {shlex.quote(audit_output)}\nexit {audit_status}\n"
        )
        dpkg.chmod(0o700)
        driver = self.original
        edits = {
            'if [[ "$EUID" != 0 ]]; then': f'if [[ "{uid}" != 0 ]]; then',
            "log_dir=/var/log/acfs": f"log_dir={shlex.quote(str(work / 'logs'))}",
            "run_dir=/run/acfs-cloud-init": f"run_dir={shlex.quote(str(work / 'run'))}",
            "state_dir=/var/lib/acfs/cloud-init": f"state_dir={shlex.quote(str(work / 'state'))}",
            "upgrade_lock=/run/acfs-upgrade.lock": f"upgrade_lock={shlex.quote(str(work / 'upgrade.lock'))}",
            "upgrade_state=/var/lib/acfs/state.json": f"upgrade_state={shlex.quote(str(work / 'upgrade.json'))}",
            "reboot_required=/run/reboot-required": f"reboot_required={shlex.quote(str(work / 'reboot-required'))}",
            "dpkg --audit 2>&1": f"{shlex.quote(str(dpkg))} --audit 2>&1",
            ". /etc/os-release": f". {shlex.quote(str(release))}",
            'curl "${curl_args[@]}"': f'{shlex.quote(str(curl))} "${{curl_args[@]}}"',
            'getent passwd ubuntu': f'{shlex.quote(str(getent))} passwd ubuntu',
            '300s runuser -u ubuntu': f'{doctor_deadline} {shlex.quote(str(runuser))} -u ubuntu',
            'git -C / ls-remote': f'{shlex.quote(str(git))} -C / ls-remote',
        }
        for old, new in edits.items():
            self.assertIn(old, driver)
            driver = driver.replace(old, new)
        if fail_write is not None:
            mv = work / "mv"
            mv.write_text(
                "#!/usr/bin/python3\nimport os, sys\n"
                f"reject={fail_write!r}\n"
                "if sys.argv[-1].endswith('/'+reject): sys.exit(9)\n"
                "os.execv('/usr/bin/mv', ['/usr/bin/mv', *sys.argv[1:]])\n"
            )
            mv.chmod(0o700)
            driver = driver.replace('mv -fT --', f'{shlex.quote(str(mv))} -fT --')
        if fail_sync is not None:
            sync = work / "sync"
            sync.write_text(
                "#!/usr/bin/python3\nimport os, sys\n"
                f"reject={fail_sync!r}\n"
                "if sys.argv[1].endswith('/'+reject): sys.exit(9)\n"
                "os.execv('/usr/bin/sync', ['/usr/bin/sync', *sys.argv[1:]])\n"
            )
            sync.chmod(0o700)
            driver = driver.replace('sync "$state_dir/', f'{shlex.quote(str(sync))} "$state_dir/')
        script = work / "driver.sh"
        script.write_text(driver)
        subprocess.run(["/bin/bash", "-n", str(script)], check=True, capture_output=True)
        argv = [*self.command[:-1], str(script), *driver_args]
        runcmd = work / "runcmd"
        runcmd.write_text("#!/bin/sh\n" + shlex.join(argv) + "\n")
        subprocess.run(["/bin/sh", "-n", str(runcmd)], check=True, capture_output=True)
        env = os.environ.copy()
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


    def state(self):
        return json.loads((self.work / "state/status.json").read_text())

    def seed_status(self, status="running", **changes):
        state = self.work / "state"
        state.mkdir(mode=0o700, exist_ok=True)
        document = {"schema_version": 1, "status": status, "phase": "installing",
                    "target_user": "ubuntu", "source_commit": SHA,
                    "updated_at": "2026-09-17T00:00:00Z", "exit_code": 0}
        document.update(changes)
        (state / "status.json").write_text(json.dumps(document))
        return state / "status.json"

    def healthy_report(self, **changes):
        report = {"acfs_version": "0.9.0", "mode": "vibe", "user": "ubuntu",
                  "os": {"id": "ubuntu", "version": "26.04"},
                  "checks": [{"id": "fixture", "status": "pass"}],
                  "summary": {"pass": 1, "warn": 0, "skip": 0, "fail": 0}}
        report.update(changes)
        return json.dumps(report)

    def test_ready_state_requires_doctor_and_is_private(self):
        result, log = self.run_driver()
        self.assertEqual(result.returncode, 0, log)
        self.assertIn("ACFS READY", log)
        self.assertEqual(self.state()["status"], "succeeded")
        self.assertEqual(self.state()["phase"], "complete")
        self.assertEqual(self.state()["source_commit"], SHA)
        self.assertEqual(self.state()["exit_code"], 0)
        for name in ("source.json", "status.json", "doctor.json"):
            self.assertEqual((self.work / "state" / name).stat().st_mode & 0o777, 0o600)
        launch = json.loads((self.work / "runuser.jsonl").read_text().splitlines()[0])
        self.assertEqual(launch[:5], ["-u", "ubuntu", "--", "env", "-i"])
        self.assertIn(f"HOME={self.work / 'home with spaces'}", launch)
        self.assertEqual(launch[-4:], ["/bin/bash", str(self.work / 'home with spaces/.acfs/bin/acfs'), "doctor", "--json"])

    def test_help_is_inert_and_does_not_require_root(self):
        result, _ = self.run_driver(uid="1000", driver_args=("--help",))
        self.assertEqual(result.returncode, 0)
        self.assertIn("Usage:", result.stdout)
        self.assertFalse((self.work / "state").exists())
        self.assertFalse((self.work / "curl.jsonl").exists())

    def test_status_before_install_is_read_only(self):
        result, _ = self.run_driver(driver_args=("--status",))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stdout)["status"], "not_started")
        for path in ("state", "logs", "run", "curl.jsonl", "doctor-runs"):
            self.assertFalse((self.work / path).exists(), path)

    def test_status_preserves_running_state_without_taking_lock(self):
        import fcntl
        status = self.seed_status()
        original = status.read_bytes()
        with (self.work / "state/lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result, _ = self.run_driver(driver_args=("--status",))
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "running")
        self.assertEqual(status.read_bytes(), original)
        self.assertFalse((self.work / "logs").exists())
        self.assertFalse((self.work / "curl.jsonl").exists())

    def test_status_after_failure_retains_original_exit_code(self):
        result, log = self.run_driver(api_status=22)
        self.assertEqual(result.returncode, 22, log)
        saved = (self.work / "state/status.json").read_bytes()
        result, _ = self.run_driver(driver_args=("--status",))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(json.loads(result.stdout)["exit_code"], 22)
        self.assertEqual((self.work / "state/status.json").read_bytes(), saved)

    def test_status_after_success_performs_no_new_work(self):
        result, log = self.run_driver()
        self.assertEqual(result.returncode, 0, log)
        tracked = [self.work / p for p in ("state/status.json", "state/source.json",
                   "state/doctor.json", "logs/cloud-init.log", "logs/install.log", "curl.jsonl")]
        before = {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in tracked}
        result, _ = self.run_driver(driver_args=("--status",))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "succeeded")
        self.assertEqual(before, {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in tracked})
        self.assertEqual((self.work / "doctor-runs").read_text().splitlines(), ["checked"])

    def test_successful_retry_rechecks_health_without_reinstalling(self):
        first, log = self.run_driver()
        self.assertEqual(first.returncode, 0, log)
        requests = (self.work / "curl.jsonl").read_bytes()
        second, log = self.run_driver(api_status=22)
        self.assertEqual(second.returncode, 0, log)
        self.assertEqual((self.work / "curl.jsonl").read_bytes(), requests)
        self.assertEqual((self.work / "executed").read_text().splitlines(), ["ran"])
        self.assertEqual((self.work / "doctor-runs").read_text().splitlines(), ["checked", "checked"])

    def test_stale_success_cannot_mask_a_broken_installed_environment(self):
        first, log = self.run_driver()
        self.assertEqual(first.returncode, 0, log)
        second, log = self.run_driver(doctor_status=1)
        self.assertEqual(second.returncode, 1, log)
        self.assertEqual(self.state()["status"], "failed")
        self.assertEqual(self.state()["phase"], "verifying")
        self.assertEqual(log.count("ACFS READY"), 1)
        self.assertEqual((self.work / "executed").read_text().splitlines(), ["ran"])

    def test_failed_retry_keeps_pin_even_when_main_moves_and_api_fails(self):
        first, log = self.run_driver(installer_status=17)
        self.assertEqual(first.returncode, 17, log)
        second, log = self.run_driver(api_body="b" * 40, api_status=22)
        self.assertEqual(second.returncode, 0, log)
        requests = [json.loads(x) for x in (self.work / "curl.jsonl").read_text().splitlines()]
        self.assertEqual(len(requests), 3)
        self.assertTrue(requests[1][-1].endswith(f"/{SHA}/install.sh"))
        self.assertTrue(requests[2][-1].endswith(f"/{SHA}/install.sh"))
        self.assertEqual(self.state()["source_commit"], SHA)

    def test_real_flock_contention_preserves_running_workers_state(self):
        import fcntl
        status = self.seed_status()
        original = status.read_bytes()
        with (self.work / "state/lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result, log = self.run_driver()
        self.assertEqual(result.returncode, 75, log)
        self.assertEqual(status.read_bytes(), original)
        self.assertFalse((self.work / "curl.jsonl").exists())
        self.assertFalse((self.work / "executed").exists())

    def test_cannot_install_without_persisting_status(self):
        result, log = self.run_driver(fail_write="status.json")
        self.assertNotEqual(result.returncode, 0, log)
        self.assertFalse((self.work / "curl.jsonl").exists())
        self.assertFalse((self.work / "executed").exists())

    def test_cannot_install_without_persisting_source(self):
        result, log = self.run_driver(fail_write="source.json")
        self.assertEqual(result.returncode, 9, log)
        self.assertFalse((self.work / "executed").exists())
        self.assertEqual(self.state()["status"], "failed")
        self.assertEqual(len((self.work / "curl.jsonl").read_text().splitlines()), 1)

    def test_missing_doctor_does_not_report_ready(self):
        result, log = self.run_driver(doctor_missing=True)
        self.assertEqual(result.returncode, 1, log)
        self.assertTrue((self.work / "executed").exists())
        self.assertFalse((self.work / "runuser.jsonl").exists())
        self.assertNotIn("ACFS READY", log)
        self.assertEqual(self.state()["status"], "failed")

    def test_unresolved_target_account_does_not_launch_doctor(self):
        result, log = self.run_driver(getent_status=2)
        self.assertEqual(result.returncode, 2, log)
        self.assertFalse((self.work / "runuser.jsonl").exists())
        self.assertEqual(self.state()["status"], "failed")

    def test_warnings_are_not_fatal(self):
        report = self.healthy_report(checks=[{"id": "base", "status": "pass"},
            {"id": "auth", "status": "warn"}, {"id": "optional", "status": "skip"}],
            summary={"pass": 1, "warn": 1, "skip": 1, "fail": 0})
        result, log = self.run_driver(doctor_document=report)
        self.assertEqual(result.returncode, 0, log)
        self.assertEqual(self.state()["status"], "succeeded")

    def test_world_writable_state_directory_is_refused(self):
        state = self.work / "state"
        state.mkdir()
        state.chmod(0o777)
        result, _ = self.run_driver()
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.work / "curl.jsonl").exists())

    def test_symlinked_state_directory_is_refused(self):
        target = self.work / "elsewhere"
        target.mkdir()
        (self.work / "state").symlink_to(target, target_is_directory=True)
        result, _ = self.run_driver()
        self.assertEqual(result.returncode, 2)
        self.assertEqual(list(target.iterdir()), [])

    def test_symlinked_status_is_not_followed_or_overwritten(self):
        state = self.work / "state"
        state.mkdir()
        target = self.work / "unrelated"
        target.write_text("unchanged")
        (state / "status.json").symlink_to(target)
        result, _ = self.run_driver()
        self.assertEqual(result.returncode, 2)
        self.assertEqual(target.read_text(), "unchanged")
        self.assertTrue((state / "status.json").is_symlink())

    def test_hardlinked_pin_is_not_overwritten(self):
        state = self.work / "state"
        state.mkdir()
        target = self.work / "unrelated"
        target.write_text("unchanged")
        os.link(target, state / "source.json")
        result, _ = self.run_driver()
        self.assertEqual(result.returncode, 2)
        self.assertEqual(target.read_text(), "unchanged")
        self.assertFalse((self.work / "curl.jsonl").exists())

    def test_fifo_pin_is_refused_without_blocking(self):
        state = self.work / "state"
        state.mkdir()
        os.mkfifo(state / "source.json")
        result, _ = self.run_driver()
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.work / "curl.jsonl").exists())

    def test_success_status_requires_matching_saved_source(self):
        self.seed_status("succeeded", phase="complete")
        source = self.work / "state/source.json"
        source.write_text(json.dumps({"schema_version": 1,
            "repository": "Dicklesworthstone/agentic_coding_flywheel_setup", "commit": "b" * 40}))
        result, _ = self.run_driver(driver_args=("--status",))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertFalse((self.work / "curl.jsonl").exists())


    def test_git_resolution_works_when_rest_api_is_unavailable(self):
        result, log = self.run_driver(git_status=0, git_body=SHA + "\trefs/heads/main\n", api_status=22)
        self.assertEqual(result.returncode, 0, log)
        requests = [json.loads(x) for x in (self.work / "curl.jsonl").read_text().splitlines()]
        self.assertEqual(len(requests), 1)
        self.assertTrue(requests[0][-1].endswith(f"/{SHA}/install.sh"))
        lookup = json.loads((self.work / "git.jsonl").read_text().splitlines()[0])
        self.assertEqual(lookup["argv"], ["-C", "/", "ls-remote", "--exit-code", "--refs",
            "https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup.git", "refs/heads/main"])
        self.assertEqual(lookup["env"]["HOME"], "/")
        self.assertEqual(lookup["env"]["GIT_CONFIG_NOSYSTEM"], "1")
        self.assertEqual(lookup["env"]["GIT_CONFIG_GLOBAL"], "/dev/null")
        self.assertEqual(lookup["env"]["GIT_TERMINAL_PROMPT"], "0")
        self.assertNotIn("ACFS_REF", lookup["env"])

    def test_source_must_be_synced_before_execution(self):
        result, log = self.run_driver(fail_sync="source.json")
        self.assertEqual(result.returncode, 9, log)
        self.assertFalse((self.work / "executed").exists())
        self.assertEqual(self.state()["status"], "failed")

    def test_status_sync_failure_stops_work(self):
        result, log = self.run_driver(fail_sync="status.json")
        self.assertEqual(result.returncode, 9, log)
        self.assertFalse((self.work / "executed").exists())
        self.assertFalse((self.work / "curl.jsonl").exists())

    def test_actual_doctor_timeout_cannot_report_ready(self):
        import time
        start = time.monotonic()
        result, log = self.run_driver(doctor_sleep=5, doctor_deadline="0.1s")
        self.assertEqual(result.returncode, 124, log)
        self.assertLess(time.monotonic() - start, 3)
        self.assertEqual(self.state()["exit_code"], 124)
        self.assertNotIn("ACFS READY", log)

    def test_failed_privilege_drop_cannot_report_ready(self):
        result, log = self.run_driver(runuser_status=125)
        self.assertEqual(result.returncode, 125, log)
        self.assertEqual(self.state()["status"], "failed")
        self.assertFalse((self.work / "doctor-runs").exists())
        self.assertNotIn("ACFS READY", log)

    def test_success_marker_without_pin_is_unavailable(self):
        self.seed_status("succeeded", phase="complete")
        result, _ = self.run_driver(driver_args=("--status",))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")

    def test_multiple_status_documents_are_refused_without_rewriting(self):
        path = self.seed_status()
        path.write_text(path.read_text() + path.read_text())
        original = path.read_bytes()
        result, _ = self.run_driver(driver_args=("--status",))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(path.read_bytes(), original)


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


# Validate the actual doctor's documented JSON shape, not merely exit zero.
for index, changes in enumerate([
    {"summary": {"pass": 1, "fail": 1}},
    {"checks": [{"status": "fail"}]},
    {"checks": [{"status": "unknown"}]},
    {"checks": []},
    {"checks": [{"status": "skip"}]},
    {"checks": [{"status": "warn"}]},
    {"user": "root"},
    {"mode": "safe"},
    {"os": {"id": "debian", "version": "26.04"}},
    {"os": {"id": "ubuntu", "version": "25.10"}},
    {"os": {"id": "ubuntu", "version": "26.04 unexpected"}},
]):
    def check(self, changes=changes):
        result, log = self.run_driver(doctor_document=self.healthy_report(**changes))
        self.assertEqual(result.returncode, 1, log)
        self.assertEqual(self.state()["phase"], "verifying")
        self.assertEqual(self.state()["status"], "failed")
        self.assertNotIn("ACFS READY", log)
    setattr(CloudInitTest, f"test_contradictory_health_report_{index}", check)

for index, report in enumerate(["", "null", "{}", "[]", "not JSON", '{} {}']):
    def check(self, report=report):
        result, log = self.run_driver(doctor_document=report)
        self.assertNotEqual(result.returncode, 0, log)
        self.assertEqual(self.state()["status"], "failed")
        self.assertNotIn("ACFS READY", log)
    setattr(CloudInitTest, f"test_invalid_health_json_{index}", check)

for code in (1, 2, 124, 137):
    def check(self, code=code):
        result, log = self.run_driver(doctor_status=code)
        self.assertEqual(result.returncode, code, log)
        self.assertEqual(self.state()["exit_code"], code)
        self.assertEqual(self.state()["phase"], "verifying")
        self.assertNotIn("ACFS READY", log)
    setattr(CloudInitTest, f"test_doctor_failure_{code}_propagates", check)

for index, entry in enumerate(["", "ubuntu:x:0:0::/:/bin/bash", "ubuntu:x:00:0::/:/bin/bash",
    "root:x:1000:1000::/:/bin/bash", "ubuntu:x:a:1000::/:/bin/bash", "ubuntu:x:1000:1000::/:/bin/bash",
    "ubuntu:x:1000:1000::/nonexistent-acfs-test-user-home:/bin/bash", "ubuntu:x:1000:1000::/:/bin/bash\nsecond line"]):
    def check(self, entry=entry):
        result, log = self.run_driver(getent_entry=entry)
        self.assertEqual(result.returncode, 1, log)
        self.assertFalse((self.work / "runuser.jsonl").exists())
        self.assertNotIn("ACFS READY", log)
    setattr(CloudInitTest, f"test_invalid_target_identity_{index}", check)

for index, body in enumerate(["", "null", "{}", "{} {}", "not JSON",
    json.dumps({"schema_version": 1, "repository": "unrelated/repo", "commit": SHA}),
    json.dumps({"schema_version": 1, "repository": "Dicklesworthstone/agentic_coding_flywheel_setup", "commit": "main"})]):
    def check(self, body=body):
        state = self.work / "state"
        state.mkdir()
        (state / "source.json").write_text(body)
        result, log = self.run_driver()
        self.assertNotEqual(result.returncode, 0, log)
        self.assertFalse((self.work / "curl.jsonl").exists())
        self.assertFalse((self.work / "executed").exists())
        self.assertEqual((state / "source.json").read_text(), body)
    setattr(CloudInitTest, f"test_corrupt_pin_never_falls_back_to_main_{index}", check)

for index, changes in enumerate([{"exit_code": -1}, {"exit_code": "0"}, {"exit_code": 1.5},
    {"source_commit": "main"}, {"target_user": "root"}, {"schema_version": 99},
    {"status": "succeeded", "phase": "complete", "source_commit": None}, {"status": "unknown"}]):
    def check(self, changes=changes):
        path = self.seed_status(**changes)
        original = path.read_bytes()
        result, _ = self.run_driver(driver_args=("--status",))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(path.read_bytes(), original)
        self.assertFalse((self.work / "curl.jsonl").exists())
    setattr(CloudInitTest, f"test_status_schema_refusal_{index}", check)

for index, arguments in enumerate([("--unknown",), ("--status", "extra")]):
    def check(self, arguments=arguments):
        result, _ = self.run_driver(driver_args=arguments)
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.work / "state").exists())
        self.assertFalse((self.work / "curl.jsonl").exists())
    setattr(CloudInitTest, f"test_invalid_cli_is_inert_{index}", check)


for index, (code, body) in enumerate([
    (1, "b" * 40 + "\trefs/heads/main"),
    (0, "b" * 40 + "\trefs/heads/unrelated"),
    (0, "b" * 40 + " refs/heads/main"),
    (0, SHA + "\trefs/heads/main\n" + "b" * 40 + "\trefs/heads/main"),
    (0, "not a ref"),
]):
    def check(self, code=code, body=body):
        result, log = self.run_driver(git_status=code, git_body=body)
        self.assertEqual(result.returncode, 0, log)
        requests = [json.loads(x) for x in (self.work / "curl.jsonl").read_text().splitlines()]
        self.assertEqual(len(requests), 2)
        self.assertTrue(requests[0][-1].endswith("/commits/main"))
        self.assertTrue(requests[1][-1].endswith(f"/{SHA}/install.sh"))
    setattr(CloudInitTest, f"test_bad_git_lookup_uses_verified_api_result_{index}", check)


# The cloud-init lock is not a substitute for the OS-upgrader's shared lock.
def check_upgrade_lock_contention(self):
    import fcntl
    lock = self.work / "upgrade.lock"
    with lock.open("w") as holder:
        holder.write("live-upgrade\n")
        holder.flush()
        fcntl.flock(holder, fcntl.LOCK_EX | fcntl.LOCK_NB)
        result, log = self.run_driver()
        self.assertEqual(result.returncode, 75, log)
        self.assertFalse((self.work / "state/status.json").exists())
        self.assertFalse((self.work / "executed").exists())
        self.assertFalse((self.work / "dpkg-calls").exists())
        self.assertEqual(lock.read_text(), "live-upgrade\n")
CloudInitTest.test_upgrade_lock_contention_preserves_other_worker = check_upgrade_lock_contention


def check_upgrade_lock_during_installer(self):
    import fcntl
    lock = self.work / "upgrade.lock"
    payload = "#!/bin/bash\nset -eu\n" + (
        f"exec 7>>{shlex.quote(str(lock))}\n"
        "if flock -n 7; then echo 'unexpected free upgrade lock'; exit 80; fi\n"
        f"printf 'held\\n' > {shlex.quote(str(self.work / 'held-during-installer'))}\n"
    )
    result, log = self.run_driver(payload=payload)
    self.assertEqual(result.returncode, 0, log)
    self.assertEqual((self.work / "held-during-installer").read_text(), "held\n")
    with lock.open("a") as holder:
        fcntl.flock(holder, fcntl.LOCK_EX | fcntl.LOCK_NB)
CloudInitTest.test_upgrade_lock_spans_installer_and_is_released = check_upgrade_lock_during_installer


def check_upgrade_lock_symlink(self):
    victim = self.work / "victim"
    victim.write_text("do not modify")
    (self.work / "upgrade.lock").symlink_to(victim)
    result, log = self.run_driver()
    self.assertEqual(result.returncode, 2, log)
    self.assertEqual(victim.read_text(), "do not modify")
    self.assertFalse((self.work / "executed").exists())
CloudInitTest.test_symlinked_upgrade_lock_refused = check_upgrade_lock_symlink


def check_pending_reboot(self):
    (self.work / "reboot-required").touch()
    result, log = self.run_driver()
    self.assertEqual(result.returncode, 1, log)
    self.assertFalse((self.work / "curl.jsonl").exists())
    self.assertFalse((self.work / "executed").exists())
    self.assertEqual(self.state()["status"], "failed")
CloudInitTest.test_pending_reboot_stops_before_download = check_pending_reboot


for index, (status, output) in enumerate([(1, ""), (0, "unconfigured package"), (2, "audit failed")]):
    def check(self, status=status, output=output):
        result, log = self.run_driver(audit_status=status, audit_output=output)
        self.assertEqual(result.returncode, 1, log)
        self.assertEqual((self.work / "dpkg-calls").read_text(), "--audit\n")
        self.assertFalse((self.work / "curl.jsonl").exists())
        self.assertFalse((self.work / "executed").exists())
        self.assertEqual(self.state()["status"], "failed")
    setattr(CloudInitTest, f"test_unhealthy_package_state_{index}", check)


for index, state in enumerate([
    {"ubuntu_upgrade": {"current_stage": "upgrading", "target_version": "26.04"}},
    {"ubuntu_upgrade": {"current_stage": "error", "target_version": "26.04"}},
    {"ubuntu_upgrade": {"current_stage": "pre_upgrade_reboot", "target_version": "26.04"}},
    {"ubuntu_upgrade": {"current_stage": "completed", "target_version": "25.10"}},
    {"ubuntu_upgrade": {"current_stage": "completed", "target_version": "26.04", "needs_reboot": True}},
    {"ubuntu_upgrade": {"current_stage": "completed", "target_version": "26.04", "resume_after_reboot": True}},
    {"ubuntu_upgrade": {"current_stage": "completed", "target_version": "26.04", "current_upgrade": {"to": "26.04"}}},
    {"ubuntu_upgrade": {}},
    [],
]):
    def check(self, state=state):
        path = self.work / "upgrade.json"
        original = json.dumps(state)
        path.write_text(original)
        result, log = self.run_driver()
        self.assertEqual(result.returncode, 1, log)
        self.assertFalse((self.work / "executed").exists())
        self.assertFalse((self.work / "curl.jsonl").exists())
        self.assertEqual(path.read_text(), original)
    setattr(CloudInitTest, f"test_unfinished_upgrade_checkpoint_{index}_preserved", check)


for index, state in enumerate([{}, {"ubuntu_upgrade": None},
    {"ubuntu_upgrade": {"current_stage": "completed", "target_version": "26.04"}},
    {"ubuntu_upgrade": {"current_stage": "completed", "target_version": "24.04", "needs_reboot": False}},
]):
    def check(self, state=state):
        path = self.work / "upgrade.json"
        original = json.dumps(state)
        path.write_text(original)
        result, log = self.run_driver()
        self.assertEqual(result.returncode, 0, log)
        self.assertEqual(path.read_text(), original)
    setattr(CloudInitTest, f"test_quiescent_checkpoint_{index}_preserved", check)


for index, content in enumerate(["not JSON", "{} {}"]):
    def check(self, content=content):
        path = self.work / "upgrade.json"
        path.write_text(content)
        result, log = self.run_driver()
        self.assertEqual(result.returncode, 1, log)
        self.assertFalse((self.work / "executed").exists())
        self.assertEqual(path.read_text(), content)
    setattr(CloudInitTest, f"test_invalid_upgrade_checkpoint_{index}_preserved", check)


def check_upgrade_checkpoint_symlink(self):
    victim = self.work / "victim"
    victim.write_text("{}")
    (self.work / "upgrade.json").symlink_to(victim)
    result, log = self.run_driver()
    self.assertEqual(result.returncode, 1, log)
    self.assertEqual(victim.read_text(), "{}")
    self.assertFalse((self.work / "executed").exists())
CloudInitTest.test_symlinked_upgrade_checkpoint_refused = check_upgrade_checkpoint_symlink


if __name__ == "__main__":
    unittest.main(verbosity=2)
