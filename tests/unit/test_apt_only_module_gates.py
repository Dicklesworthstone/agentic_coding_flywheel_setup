#!/usr/bin/env python3
"""Generated apt-only modules refuse non-apt systems before changing anything (#477).

An install filtered with --only/--skip dispatches every category to the
generated module functions, including on Arch. Those modules install with
apt-get, and network.tailscale wrote an Ubuntu apt source and keyring as root
before its first apt call failed. Each now runs a pre-install gate first, and
stack.srps honors its manifest `families` declaration.

These tests run the real generated function bodies with the real
run_as_current_shell, and stub only the root/target runners (which record what
they were asked to run instead of running it), logging, and selection.

Run: python3 -m unittest discover -s tests/unit -p test_apt_only_module_gates.py -v
Nothing is installed and no system file is touched.
"""
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
GENERATED = ROOT / "scripts/generated"
HELPERS = ROOT / "scripts/lib/install_helpers.sh"

# module id -> (category script, optional, package-manager hint in the refusal)
GATED = {
    "base.system": ("install_base.sh", False, "sudo pacman -S --needed curl git"),
    "shell.zsh": ("install_shell.sh", False, "sudo pacman -S --needed zsh"),
    "cli.modern": ("install_cli.sh", False, "sudo pacman -S --needed ripgrep tmux fzf"),
    "network.tailscale": ("install_network.sh", False, "sudo pacman -S --needed tailscale"),
    "lang.go": ("install_lang.sh", False, "sudo pacman -S --needed go"),
    "tools.vault": ("install_tools.sh", True, "sudo pacman -S --needed vault"),
    "db.postgres18": ("install_db.sh", True, "sudo pacman -S --needed postgresql"),
}

STUBS = r'''
log_step() { printf 'STEP %s\n' "$*" >&2; }
log_info() { printf 'INFO %s\n' "$*" >&2; }
log_warn() { printf 'WARN %s\n' "$*" >&2; }
log_error() { printf 'ERROR %s\n' "$*" >&2; }
log_success() { printf 'OK %s\n' "$*" >&2; }
acfs_require_contract() { return 0; }
acfs_generated_ensure_selection() { return 0; }
should_run_module() { return 0; }
acfs_module_explicitly_selected() { [[ "${FIXTURE_EXPLICIT:-0}" == 1 ]]; }
record_skipped_tool() { printf 'SKIPPED %s\n' "$1" >> "$FIXTURE_CALLS"; }
run_as_root_shell() { printf 'ROOT\n' >> "$FIXTURE_CALLS"; cat >> "$FIXTURE_CALLS"; }
run_as_target_shell() { printf 'TARGET\n' >> "$FIXTURE_CALLS"; cat >> "$FIXTURE_CALLS"; }
'''


def function_name(module_id):
    return "acfs_generated_install_" + module_id.replace(".", "_")


def generated_function(script, module_id):
    text = (GENERATED / script).read_text()
    match = re.search(r"^%s\(\) \{\n.*?^\}$" % re.escape(function_name(module_id)), text, re.M | re.S)
    if not match:
        raise AssertionError(f"{function_name(module_id)} not found in {script}; regenerate")
    return match[0]


class AptOnlyModuleGateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="acfs-apt-gate-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.calls = self.root / "calls"
        self.calls.write_text("")
        # A PATH with the one external command the shell runner needs and no
        # apt-get, as on Arch or Fedora.
        self.no_apt_bin = self.root / "no-apt-bin"
        self.no_apt_bin.mkdir()
        for tool in ("cat",):
            (self.no_apt_bin / tool).symlink_to(self.which(tool))
        # The same plus an apt-get that must never actually run.
        self.apt_bin = self.root / "apt-bin"
        self.apt_bin.mkdir()
        (self.apt_bin / "cat").symlink_to(self.which("cat"))
        fake_apt = self.apt_bin / "apt-get"
        fake_apt.write_text("#!/bin/sh\necho 'fixture apt-get must not run' >&2\nexit 97\n")
        fake_apt.chmod(0o755)

    @staticmethod
    def which(tool):
        for directory in ("/usr/bin", "/bin"):
            candidate = Path(directory) / tool
            if candidate.exists():
                return candidate
        raise unittest.SkipTest(f"{tool} not found")

    def run_module(self, module_id, script, *, path, family=None, explicit=False, dry_run=False):
        program = "\n".join([
            "source " + shlex.quote(str(HELPERS)),
            STUBS,
            generated_function(script, module_id),
            # Switch PATH only for the module run: the gate must decide from it.
            "PATH=" + shlex.quote(str(path)),
            function_name(module_id),
        ])
        env = {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": str(self.home),
            "LC_ALL": "C",
            "FIXTURE_CALLS": str(self.calls),
            "FIXTURE_EXPLICIT": "1" if explicit else "0",
            "DRY_RUN": "true" if dry_run else "false",
        }
        if family is not None:
            env["ACFS_DISTRO_FAMILY"] = family
        return subprocess.run(["bash", "-c", program], env=env, capture_output=True,
                              text=True, timeout=60)

    def calls_made(self):
        return self.calls.read_text()

    def test_arch_refuses_every_apt_only_module_before_any_root_command(self):
        for module_id, (script, optional, hint) in GATED.items():
            with self.subTest(module=module_id):
                self.calls.write_text("")
                # apt-get is present here, so only the family decides.
                result = self.run_module(module_id, script, path=self.apt_bin, family="arch")
                level = "WARN" if optional else "ERROR"
                self.assertIn(f"{level} {module_id}: ", result.stderr)
                self.assertIn(hint, result.stderr)
                self.assertNotIn("ROOT", self.calls_made())
                self.assertNotIn("TARGET", self.calls_made())
                self.assertNotIn("fixture apt-get must not run", result.stderr)
                if optional:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(self.calls_made(), f"SKIPPED {module_id}\n")
                else:
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertEqual(self.calls_made(), "")

    def test_a_system_without_apt_get_is_refused_whatever_the_family(self):
        # Root commands search only the system directories, never PATH.
        if os.geteuid() == 0 and any(Path(d, "apt-get").exists() for d in ("/usr/sbin", "/usr/bin", "/sbin", "/bin")):
            self.skipTest("as root the gate sees the system apt-get; run as a regular user")
        for family in (None, "ubuntu"):
            with self.subTest(family=family):
                self.calls.write_text("")
                result = self.run_module("network.tailscale", "install_network.sh",
                                         path=self.no_apt_bin, family=family)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn("ERROR network.tailscale: installs from the Tailscale Ubuntu apt "
                              "repository on Debian/Ubuntu only", result.stderr)
                # No keyring, no sources list, no apt call: nothing ran as root.
                self.assertEqual(self.calls_made(), "")

    def test_an_explicitly_requested_optional_module_fails_instead_of_skipping(self):
        result = self.run_module("tools.vault", "install_tools.sh", path=self.apt_bin,
                                 family="arch", explicit=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("explicitly requested via --only", result.stderr)
        self.assertEqual(self.calls_made(), "")

    def test_apt_systems_still_install(self):
        if os.geteuid() == 0 and not any(Path(d, "apt-get").exists() for d in ("/usr/sbin", "/usr/bin", "/sbin", "/bin")):
            self.skipTest("as root the gate looks for apt-get in the system directories only")
        result = self.run_module("shell.zsh", "install_shell.sh", path=self.apt_bin, family="ubuntu")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls_made().splitlines(), [
            "ROOT", "apt-get -o DPkg::Lock::Timeout=120 install -y zsh",
            "ROOT", "zsh --version",
        ])
        self.assertIn("OK shell.zsh installed", result.stderr)

    def test_stack_srps_skips_outside_its_declared_family(self):
        result = self.run_module("stack.srps", "install_stack.sh", path=self.apt_bin,
                                 family="arch", dry_run=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("INFO Skipping stack.srps (not supported on the arch distro family; "
                      "supported: ubuntu)", result.stderr)
        self.assertNotIn("STEP", result.stderr)
        self.assertEqual(self.calls_made(), "")

        result = self.run_module("stack.srps", "install_stack.sh", path=self.apt_bin,
                                 family="ubuntu", dry_run=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("STEP Installing stack.srps", result.stderr)
        self.assertNotIn("Skipping stack.srps", result.stderr)


if __name__ == "__main__":
    unittest.main()
