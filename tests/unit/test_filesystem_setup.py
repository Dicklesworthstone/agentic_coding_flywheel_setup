"""Filesystem-phase workspace guide deployment, including fresh-install #506.

Run the authored phase and manifest commands against real temporary files.
Only the fixed /data prefix and identity/privilege adapters are redirected;
asset authentication, publication, and the manifest's required checks are real.
No network, installer execution, or writes to the host workspace are needed.
"""
import hashlib
import json
import os
import pwd
import re
import shlex
import stat
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HELPERS = ROOT / "scripts/lib/install_helpers.sh"
MANIFEST = (ROOT / "acfs.manifest.yaml").read_text()
MODULE = MANIFEST.split("\n  - id: base.filesystem\n", 1)[1].split("\n  - id: ", 1)[0]


def function(name):
    source = (ROOT / "install.sh").read_text()
    found = re.search(r"^" + re.escape(name) + r"\(\) \{\n.*?^\}$", source,
                      re.MULTILINE | re.DOTALL)
    if found is None:
        raise AssertionError(f"installer function missing: {name}")
    return found[0]


def manifest_install():
    source = MODULE.split("    install:\n", 1)[1].split("    verify:\n", 1)[0]
    commands = source.split("      - |\n")
    if commands.pop(0).strip() or len(commands) != 2:
        raise AssertionError("filesystem manifest install shape changed")
    return "\n".join(textwrap.dedent(command) for command in commands)


def manifest_verify():
    source = MODULE.split("    verify:\n", 1)[1].split("    notes:\n", 1)[0]
    first, rest = source.split("      - |\n", 1)
    if first.strip() != "- test -d /data/projects":
        raise AssertionError("filesystem manifest verification shape changed")
    return "test -d /data/projects\n" + textwrap.dedent(rest)


IDENTITY = r'''
acfs_generated_getent_passwd_entry() {
    printf '%s:x:%s:%s::%s:/bin/bash\n' "$TARGET_USER" "$FIXTURE_UID" "$FIXTURE_GID" "$TARGET_HOME"
}
acfs_generated_passwd_home_from_entry() { printf '%s\n' "$TARGET_HOME"; }
acfs_generated_resolve_current_user() { printf '%s\n' "$TARGET_USER"; }
'''


class FilesystemSetupTests(unittest.TestCase):
    def setUp(self):
        # Retain fixture files and failure evidence; no destructive cleanup.
        self.root = Path(tempfile.mkdtemp(prefix="acfs-filesystem-test-"))
        self.home = self.root / "home with spaces"
        self.home.mkdir()
        self.workspace = self.root / "data/projects"
        self.workspace.mkdir(parents=True)
        self.source = self.root / "verified source"
        (self.source / "acfs").mkdir(parents=True)
        (self.source / "scripts/generated").mkdir(parents=True)
        self.template = self.source / "acfs/AGENTS.md"
        self.template.write_bytes((ROOT / "acfs/AGENTS.md").read_bytes())
        self.ledger = self.source / "scripts/generated/internal_checksums.sh"
        self.ledger.write_bytes((ROOT / "scripts/generated/internal_checksums.sh").read_bytes())
        self.digest = hashlib.sha256(self.ledger.read_bytes()).hexdigest()
        self.canonical = self.home / ".acfs/docs/AGENTS.workspace.md"
        self.instructions = self.workspace / "AGENTS.md"
        account = pwd.getpwuid(os.geteuid())
        self.user = account.pw_name
        self.env = {
            "PATH": "/usr/bin:/bin", "HOME": str(self.home), "LC_ALL": "C",
            "TARGET_USER": self.user, "TARGET_HOME": str(self.home),
            "FIXTURE_UID": str(account.pw_uid), "FIXTURE_GID": str(account.pw_gid),
            "ACFS_HOME": str(self.home / ".acfs"),
            "ACFS_LOG_DIR": str(self.home / ".acfs/logs"),
            "ACFS_BIN_DIR": str(self.home / ".local/bin"),
            "ACFS_LIB_DIR": str(HELPERS.parent),
            "ACFS_TRUSTED_INTERNAL_SOURCE_ROOT": str(self.source),
            "ACFS_TRUSTED_INTERNAL_LEDGER_SHA256": self.digest,
            "SUDO": "", "MODE": "vibe", "NO_COLOR": "1",
        }

    def invoke(self, body=None, *, phase=False, manifest=False, generated_phase=False,
               early_runtime=False, selected_modules=None, finalize_cli=False, **environment):
        program = "set -euo pipefail\nsource " + shlex.quote(str(HELPERS)) + "\n"
        program += IDENTITY
        if phase:
            program += r'''
set_phase() { :; }
log_step() { :; }
log_detail() { :; }
log_success() { printf '%s\n' "$*"; }
acfs_use_generated_category() { return 1; }
try_step() { shift; "$@"; }
try_step_optional() { shift; "$@"; }
run_as_target() { "$@"; }
acfs_chown_target_home() { chown -h "$@"; }
acfs_chown_tree() { chown -hR "$@"; }
acfs_ensure_primary_bin_dir() { mkdir -p "$ACFS_BIN_DIR"; }
acfs_link_primary_bin_command() {
    acfs_ensure_primary_bin_dir && ln -sf "$1" "$ACFS_BIN_DIR/$2"
}
# Early doctor script copies are outside this guide-deployment test. Retain
# any attempted guide copy as an error: it must use the real shared helper.
install_asset() {
    [[ "$1" != acfs/AGENTS.md ]] || return 91
    mkdir -p "${2%/*}"
    printf '# fixture early doctor\n' > "$2"
}
'''
            if early_runtime:
                # Exercise authentication and publication with the real asset
                # installer. Only privilege/account and fixed host paths are
                # redirected; runtime bytes come from the verified source.
                for name in ("acfs_early_system_binary_path", "acfs_calculate_file_sha256",
                             "_acfs_install_asset_has_symlink_component_under_prefix",
                             "_acfs_internal_asset_is_rendered_data",
                             "_acfs_internal_asset_expected_sha256", "install_asset"):
                    program += function(name) + "\n"
                program += 'acfs_early_sudo_binary_path() { return 1; }\n'
                program += 'SCRIPT_DIR="$ACFS_TRUSTED_INTERNAL_SOURCE_ROOT"\n'
                program += 'declare -gA ACFS_INTERNAL_CHECKSUMS=(\n'
                for path, digest in re.findall(r'^  \[([^\]]+)\]="([a-f0-9]{64})"$',
                                               self.ledger.read_text(), re.MULTILINE):
                    program += f"  [{shlex.quote(path)}]={shlex.quote(digest)}\n"
                program += ')\n'
            source = (ROOT / "install.sh").read_text()
            if "\nacfs_install_early_doctor() {\n" in source:
                program += function("acfs_install_early_doctor").replace(
                    "/usr/local/bin", str(self.home / "global-bin")) + "\n"
            if generated_phase:
                program += 'acfs_use_generated_category() { return 0; }\n'
                program += 'acfs_run_generated_category_phase() {\n'
                program += manifest_install().replace("/data", str(self.root / "data")).replace(
                    'target_home="/root"', 'target_home="$TARGET_HOME"')
                program += '\n}\n'
            program += function("acfs_legacy_module_selected") + "\n"
            if selected_modules is not None:
                program += 'declare -gA ACFS_EFFECTIVE_RUN=(\n'
                for module in selected_modules:
                    program += f"  [{shlex.quote(module)}]=1\n"
                program += ')\nACFS_GENERATED_SELECTION_READY=true\n'
            # These are the same fixed-path substitutions used by the existing
            # PostgreSQL installer tests, not product test-only configuration.
            program += function("setup_filesystem").replace("/data", str(self.root / "data"))
            program += "\nsetup_filesystem\n"
            if finalize_cli:
                # Exercise the actual finalization publication block after
                # early deployment, without unrelated finalization installs.
                start = '    if acfs_legacy_module_selected "acfs.doctor"; then\n'
                block = start + function("finalize").split(start, 1)[1].split(
                    "\n    # Install DCG", 1)[0]
                program += block.replace("/usr/local/bin", str(self.home / "global-bin")) + "\n"
        elif manifest:
            program += manifest_install().replace("/data", str(self.root / "data")).replace(
                'target_home="/root"', 'target_home="$TARGET_HOME"')
        else:
            program += body or ('acfs_install_workspace_template "$TARGET_HOME" '
                               + shlex.quote(str(self.workspace)) + "\n")
        result = subprocess.run(["/bin/bash", "-p", "-c", program], env={**self.env, **environment},
                                capture_output=True, text=True,
                                timeout=60 if early_runtime else 10, check=False)
        (self.root / "last.stdout").write_text(result.stdout)
        (self.root / "last.stderr").write_text(result.stderr)
        return result

    def prepare_early_runtime(self):
        # Keep each source's real bytes and the canonical ledger. No fetching,
        # fixture-success executables, or checkout fallback can hide omissions.
        for name in ("logging", "output", "progress", "gum_ui", "state", "user", "doctor", "install_helpers"):
            path = self.source / f"scripts/lib/{name}.sh"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((ROOT / f"scripts/lib/{name}.sh").read_bytes())
        for relative in ("VERSION", "scripts/generated/doctor_checks.sh",
                         "scripts/generated/manifest_index.sh", "scripts/acfs-global"):
            path = self.source / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((ROOT / relative).read_bytes())

    def run_early_doctor(self, *, entrypoint=False, selection=None):
        checkpoint = self.home / ".acfs/state.json"
        checkpoint.write_text(json.dumps({
            "schema_version": 3, "target_user": self.user, "target_home": str(self.home),
            "mode": "safe", "completed_phases": ["filesystem"], "failed_phase": "agents",
            "module_selection": selection or {
                "schema_version": 1, "selected_modules": ["acfs.doctor", "agents.grok"],
                "requested_modules": ["agents.grok"],
            },
        }))
        doctor = self.home / (".acfs/bin/acfs" if entrypoint else ".acfs/scripts/lib/doctor.sh")
        # Load the exact deployed runtime via its non-mutating help command.
        # Redirect only the resolved account home after startup, so the real
        # state parser, generated catalogue, diagnostic dispatch and JSON
        # reporting operate on this incomplete installation, not this machine.
        program = 'source ' + shlex.quote(str(doctor)) + ' help >/dev/null\n'
        program += 'TARGET_HOME="$FIXTURE_HOME"\nACFS_HOME="$FIXTURE_HOME/.acfs"\n'
        program += 'ACFS_STATE_FILE="$ACFS_HOME/state.json"\n'
        program += 'main doctor --json\n' if entrypoint else 'main --json\n'
        result = subprocess.run(["/bin/bash", "-p", "-c", program],
                                env={**self.env, "FIXTURE_HOME": str(self.home),
                                     "ACFS_LIB_DIR": str(self.home / ".acfs/scripts/lib"),
                                     "ACFS_LOCAL_PROGRESS": "0"},
                                cwd=self.root, capture_output=True, text=True,
                                timeout=30, check=False)
        (self.root / "doctor.stdout").write_text(result.stdout)
        (self.root / "doctor.stderr").write_text(result.stderr)
        return result

    def test_early_runtime_diagnoses_selected_failure_without_finalization(self):
        for generated in (False, True):
            with self.subTest(generated=generated):
                self.setUp()
                self.prepare_early_runtime()
                self.assert_installed(self.invoke(phase=True, early_runtime=True,
                                                 generated_phase=generated))
                result = self.run_early_doctor()
                report = json.loads(result.stdout)
                checks = {check["id"]: check for check in report["checks"]}
                self.assertNotIn("config.module_selection", checks, result.stdout)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertEqual(checks["agents.grok"]["status"], "fail", result.stdout)
                self.assertEqual(checks["agent.claude"]["status"], "skip", result.stdout)
                self.assertEqual(report["mode"], "safe")

    def test_selected_early_cli_is_callable_before_shell_and_finalization(self):
        self.prepare_early_runtime()
        self.assert_installed(self.invoke(phase=True, early_runtime=True))
        self.assertTrue((self.home / ".local/bin/acfs").is_symlink())
        self.assertTrue(os.access(self.home / ".local/bin/acfs", os.X_OK))
        self.assertEqual((self.home / "global-bin/acfs").read_bytes(),
                         (ROOT / "scripts/acfs-global").read_bytes())
        result = self.run_early_doctor(entrypoint=True)
        checks = {check["id"]: check for check in json.loads(result.stdout)["checks"]}
        self.assertEqual(checks["agents.grok"]["status"], "fail", result.stdout)
        self.assertNotIn("config.module_selection", checks, result.stdout)

    def test_early_runtime_does_not_relax_invalid_selection(self):
        self.prepare_early_runtime()
        self.assert_installed(self.invoke(phase=True, early_runtime=True))
        result = self.run_early_doctor(selection={
            "schema_version": 1, "selected_modules": ["agents.unknown"],
        })
        report = json.loads(result.stdout)
        self.assertEqual(result.returncode, 1)
        self.assertEqual([check["id"] for check in report["checks"]], ["config.module_selection"])

    def test_early_runtime_respects_omitted_doctor_command(self):
        for generated in (False, True):
            with self.subTest(generated=generated):
                self.setUp()
                self.prepare_early_runtime()
                self.assert_installed(self.invoke(
                    phase=True, early_runtime=True, generated_phase=generated,
                    selected_modules=["base.filesystem"]))
                self.assertTrue((self.home / ".acfs/scripts/lib/doctor.sh").is_file())
                self.assertFalse((self.home / ".acfs/bin/acfs").exists())
                self.assertFalse((self.home / ".local/bin/acfs").is_symlink())
                self.assertFalse((self.home / "global-bin/acfs").exists())

    def test_missing_early_runtime_dependency_fails_before_public_command(self):
        self.prepare_early_runtime()
        source = self.source / "scripts/lib/state.sh"
        source.rename(source.with_suffix(".retained"))
        result = self.invoke(phase=True, early_runtime=True)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("Filesystem setup complete", result.stdout)
        self.assertFalse((self.home / ".acfs/bin/acfs").exists())
        self.assertFalse((self.home / "global-bin/acfs").exists())

    def test_early_runtime_and_finalization_preserve_custom_primary_bins(self):
        for generated in (False, True):
            for destination in (".acfs/bin", "global-bin"):
                with self.subTest(generated=generated, destination=destination):
                    self.setUp()
                    self.prepare_early_runtime()
                    self.assert_installed(self.invoke(
                        phase=True, early_runtime=True, generated_phase=generated,
                        finalize_cli=True, ACFS_BIN_DIR=str(self.home / destination)))
                    cli = self.home / ".acfs/bin/acfs"
                    wrapper = self.home / "global-bin/acfs"
                    self.assertFalse(cli.is_symlink())
                    self.assertFalse(wrapper.is_symlink())
                    self.assertEqual(cli.read_bytes(), (ROOT / "scripts/lib/doctor.sh").read_bytes())
                    self.assertEqual(wrapper.read_bytes(), (ROOT / "scripts/acfs-global").read_bytes())

    def assert_installed(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.canonical.read_bytes(), self.template.read_bytes())
        self.assertEqual(self.canonical.stat().st_uid, os.geteuid())
        self.assertEqual(stat.S_IMODE(self.canonical.stat().st_mode), 0o644)
        self.assertEqual(self.canonical.stat().st_nlink, 1)

    def verify(self):
        program = "set -euo pipefail\n" + IDENTITY
        program += manifest_verify().replace("/data", str(self.root / "data")).replace(
            'target_home="/root"', 'target_home="$TARGET_HOME"')
        result = subprocess.run(["/bin/bash", "-p", "-c", program], env=self.env,
                                capture_output=True, text=True, timeout=5, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_fresh_authored_phase_passes_its_real_required_checks_in_both_modes(self):
        for mode in ("vibe", "safe"):
            with self.subTest(mode=mode):
                self.setUp()
                self.assert_installed(self.invoke(phase=True, MODE=mode))
                self.assertEqual(self.instructions.read_bytes(), self.template.read_bytes())
                self.assertNotEqual(self.instructions.stat().st_ino, self.canonical.stat().st_ino)
                self.verify()

    def test_manifest_install_uses_the_same_verified_template_and_passes_checks(self):
        self.assert_installed(self.invoke(manifest=True))
        self.assertEqual(self.instructions.read_bytes(), self.template.read_bytes())
        self.verify()

    def test_authored_root_shell_preserves_unexported_verified_source_identity(self):
        if os.geteuid() != 0:
            self.skipTest("run as root or in an unshare -Ur namespace for the direct-root shell")
        command = ('source "$ACFS_LIB_DIR/install_helpers.sh"; '
                   'acfs_install_workspace_template "$TARGET_HOME" ' + shlex.quote(str(self.workspace)))
        self.assert_installed(self.invoke(
            "export -n ACFS_TRUSTED_INTERNAL_SOURCE_ROOT ACFS_TRUSTED_INTERNAL_LEDGER_SHA256\n"
            "run_as_root_shell " + shlex.quote(command) + "\n"))

    def test_generated_module_deploys_and_verifies_through_real_root_child_shells(self):
        if os.geteuid() != 0:
            self.skipTest("run as root or in an unshare -Ur namespace for generated root commands")
        generated = (ROOT / "scripts/generated/install_filesystem.sh").read_text()
        body = "acfs_generated_install_base_filesystem() {\n" + generated.split(
            "acfs_generated_install_base_filesystem() {\n", 1)[1].split(
            "\n# Category scripts are source-only libraries.", 1)[0]
        self.assertIn('acfs_install_workspace_template "$target_home" /data/projects', body)
        # Root's passwd home and /data are the only real-host paths redirected.
        body = body.replace("/data", str(self.root / "data")).replace(
            'target_home="/root"', 'target_home="$TARGET_HOME"')
        program = r'''
acfs_require_contract() { return 0; }
acfs_generated_ensure_selection() { return 0; }
should_run_module() { return 0; }
export -n ACFS_TRUSTED_INTERNAL_SOURCE_ROOT ACFS_TRUSTED_INTERNAL_LEDGER_SHA256
''' + body + "\nacfs_generated_install_base_filesystem\n"
        self.assert_installed(self.invoke(program))
        self.assertEqual(self.instructions.read_bytes(), self.template.read_bytes())
        before = self.canonical.read_bytes()
        self.template.write_bytes(before + b"changed after verification\n")
        result = self.invoke(program)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("changed after source verification", result.stderr)
        self.assertEqual(self.canonical.read_bytes(), before)

    def test_rerun_refreshes_managed_copy_and_preserves_operator_instructions(self):
        self.assert_installed(self.invoke(phase=True))
        self.canonical.write_text("old managed guide\n")
        self.instructions.write_text("Operator rules must survive reinstall\n")
        before = self.instructions.stat()
        self.assert_installed(self.invoke(phase=True))
        self.assertEqual(self.instructions.read_text(), "Operator rules must survive reinstall\n")
        after = self.instructions.stat()
        self.assertEqual((before.st_ino, before.st_mtime_ns, before.st_mode),
                         (after.st_ino, after.st_mtime_ns, after.st_mode))
        self.verify()

    def test_existing_workspace_entries_are_preserved_by_both_install_paths(self):
        for manifest in (False, True):
            for kind in ("symlink", "dangling_symlink", "directory", "fifo"):
                with self.subTest(manifest=manifest, kind=kind):
                    self.setUp()
                    outside = self.root / "operator rules"
                    if kind == "symlink":
                        outside.write_text("preserve this target\n")
                        self.instructions.symlink_to(outside)
                    elif kind == "dangling_symlink":
                        self.instructions.symlink_to(outside)
                    elif kind == "directory":
                        self.instructions.mkdir()
                    else:
                        os.mkfifo(self.instructions)
                    before = self.instructions.lstat()
                    self.assert_installed(self.invoke(phase=not manifest, manifest=manifest))
                    after = self.instructions.lstat()
                    self.assertEqual((before.st_ino, before.st_mode, before.st_mtime_ns),
                                     (after.st_ino, after.st_mode, after.st_mtime_ns))
                    if kind == "symlink":
                        self.assertEqual(outside.read_text(), "preserve this target\n")
                    elif kind == "dangling_symlink":
                        self.assertFalse(outside.exists())

    def test_missing_source_fails_the_phase_without_publishing_success(self):
        self.template.rename(self.source / "acfs/retained-template.md")
        result = self.invoke(phase=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Filesystem setup complete", result.stdout)
        self.assertFalse(self.canonical.exists())
        self.assertFalse(self.instructions.exists())

    def test_changed_source_or_ledger_fails_before_replacing_existing_data(self):
        for changed in ("template", "ledger"):
            with self.subTest(changed=changed):
                self.setUp()
                self.assert_installed(self.invoke())
                before = self.canonical.read_bytes()
                source = self.template if changed == "template" else self.ledger
                source.write_bytes(source.read_bytes() + b"changed after verification\n")
                result = self.invoke()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("changed after source verification", result.stderr)
                self.assertEqual(self.canonical.read_bytes(), before)
                self.assertEqual(self.instructions.read_bytes(), before)

    def test_managed_destination_symlinks_are_refused_without_touching_their_targets(self):
        for suffix in (".acfs", ".acfs/docs", ".acfs/docs/AGENTS.workspace.md"):
            with self.subTest(suffix=suffix):
                self.setUp()
                destination = self.home / suffix
                destination.parent.mkdir(parents=True, exist_ok=True)
                outside = self.root / "outside"
                outside.mkdir()
                saved = outside / "saved"
                saved.write_text("must remain untouched")
                destination.symlink_to(outside)
                result = self.invoke()
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(destination.is_symlink())
                self.assertEqual(saved.read_text(), "must remain untouched")
                self.assertEqual(sorted(p.name for p in outside.iterdir()), ["saved"])
                self.assertFalse(self.instructions.exists())

    def test_source_symlink_and_fifo_are_rejected_without_hanging(self):
        for kind in ("symlink", "fifo"):
            with self.subTest(kind=kind):
                self.setUp()
                saved = self.template.with_name("saved.md")
                self.template.rename(saved)
                if kind == "symlink":
                    self.template.symlink_to(saved)
                else:
                    os.mkfifo(self.template)
                result = self.invoke()
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.canonical.exists())
                self.assertFalse(self.instructions.exists())

    def test_missing_trusted_identity_is_not_satisfied_by_an_ambient_raw_url(self):
        result = self.invoke(ACFS_TRUSTED_INTERNAL_SOURCE_ROOT="",
                             ACFS_RAW="https://example.invalid/untrusted")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires the verified ACFS source identity", result.stderr)
        self.assertFalse(self.canonical.exists())

    def test_unwritable_workspace_is_a_required_failure_after_safe_canonical_deployment(self):
        if os.geteuid() == 0:
            self.skipTest("permission denial is meaningful for a non-root target")
        self.workspace.chmod(0o500)
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.canonical.read_bytes(), self.template.read_bytes())
        self.assertFalse(self.instructions.exists())

    def test_no_network_or_python_startup_hooks_are_used(self):
        poisoned = self.root / "poisoned"
        poisoned.mkdir()
        marker = self.root / "executed"
        for name in ("curl", "wget", "python3"):
            binary = poisoned / name
            binary.write_text("#!/bin/sh\ntouch " + shlex.quote(str(marker)) + "\nexit 91\n")
            binary.chmod(0o755)
        (poisoned / "sitecustomize.py").write_text("raise RuntimeError('untrusted startup hook')\n")
        result = self.invoke(PATH=f"{poisoned}:/usr/bin:/bin", PYTHONPATH=str(poisoned),
                             PYTHONHOME=str(poisoned), ACFS_RAW="https://example.invalid/untrusted")
        self.assert_installed(result)
        self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
