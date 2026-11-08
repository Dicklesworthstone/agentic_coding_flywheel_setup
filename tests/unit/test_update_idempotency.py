"""Exercise integrity-aware updater no-ops with isolated, retained fixtures.

Receipt tests invoke the real Bash entrypoint, target runner and filesystem
validation. Agent Mail orchestration tests substitute release discovery and
service operations: they prove installation/reconciliation decisions, not
cryptographic authenticity. Signed-manifest verification is tested separately.
No package manager, external network, real tool installation or service runs.
"""
import hashlib
import json
import os
from pathlib import Path
import pwd
import shlex
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(os.environ.get("ACFS_UPDATE_TEST_LIBRARY", ROOT / "scripts/lib/update.sh"))

COMMON = r'''
source "$UPDATE_TEST_LIBRARY"
HOME="$TEST_HOME"
TARGET_HOME="$TEST_HOME"
TARGET_USER="$TEST_USER"
UPDATE_LOG_FILE="$TEST_ROOT/update.log"
DRY_RUN=false FORCE_MODE=false QUIET=true VERBOSE=false ABORT_ON_FAILURE=false
RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' NC=''
SUCCESS_COUNT=0 SKIP_COUNT=0 FAIL_COUNT=0
# The fixture home belongs to the actual caller. Keep the real target runner,
# but isolate passwd-home resolution from this machine's real installation.
update_target_home() { printf '%s\n' "$TEST_HOME"; }
'''

AGENT_MAIL_FIXTURE = r'''
source "$REPO_ROOT/scripts/lib/security.sh"
UPDATE_SECURITY_READY=true
ACFS_HOLDS_FILE="$TEST_ROOT/holds.yaml"
FORCE_MODE="${TEST_FORCE:-false}"
DRY_RUN="${TEST_DRY_RUN:-false}"
UPDATE_CMD_TIMEOUT=10
PIN="$TEST_PIN"
KNOWN_INSTALLERS[mcp_agent_mail]="https://fixture.invalid/reviewed/install.sh"
get_checksum() { printf '%s\n' "$PIN"; }
update_require_security() { return 0; }
acfs_refresh_loaded_checksums_from_remote() {
    [[ "${TEST_REFRESH_PIN:-false}" == true ]] || return 1
    PIN="$TEST_ACTUAL_PIN"
}
acfs_download_to_file() {
    [[ "$1" == "${KNOWN_INSTALLERS[mcp_agent_mail]}" ]] || return 1
    printf 'installer-download\n' >> "$TEST_ROOT/events"
    cat "$TEST_ROOT/installer.sh" > "$2"
}
update_create_target_readable_temp_file() { mktemp "$TEST_ROOT/stage.XXXXXX"; }
update_private_installer_tmpdir() { printf '%s\n' "$TEST_ROOT/private-tmp"; }
update_remove_target_installer_tmpdir() { :; }
# Preserve all shell-created staging files as diagnostic fixtures.
rm() { :; }

# This is the deliberate trust-fixture boundary. It supplies an already
# authenticated contract; these orchestration tests do not claim to test a
# Minisign signature. Script pin verification and receipt validation are real.
update_agent_mail_release_contract() {
    local -n fixture_release="$1"
    fixture_release=()
    printf 'resolve-release\n' >> "$TEST_ROOT/events"
    [[ "${TEST_CONTRACT_UNAVAILABLE:-false}" != true ]] || return 1
    local contract
    contract="$(/usr/bin/jq -c --arg url "$2" --arg pin "$3" \
        '.installer={url:$url,sha256:$pin}' "$TEST_ROOT/release-contract.json")" || return 1
    fixture_release=("$contract" "$TEST_RELEASE_TAG" "$TEST_ARTIFACT_URL" "$TEST_ARCHIVE_SHA")
}

update_source_stack_lib() { return 0; }
_stack_repair_agent_mail_cli_symlink() {
    printf 'repair-alias\n' >> "$TEST_ROOT/events"
    mkdir -p "$TEST_HOME/.local/bin"
    ln -sf "$TEST_HOME/mcp_agent_mail/am" "$TEST_HOME/.local/bin/am"
}
_stack_configure_agent_mail_service() {
    printf 'reconcile-service\n' >> "$TEST_ROOT/events"
    [[ "${TEST_SERVICE_HOLD:-false}" != true ]] || return 75
    [[ -x "$TEST_HOME/mcp_agent_mail/am" && -x "$TEST_HOME/mcp_agent_mail/mcp-agent-mail" ]] || return 1
    [[ "${TEST_SERVICE_FAILURE:-false}" != true ]] || return 1
    if [[ ! -f "$TEST_ROOT/healthy" || -f "$TEST_ROOT/unit-change" ]] \
        || ! cmp -s "$TEST_ROOT/running-image" "$TEST_HOME/mcp_agent_mail/mcp-agent-mail"; then
        printf 'restart-service\n' >> "$TEST_ROOT/events"
        cp "$TEST_HOME/mcp_agent_mail/mcp-agent-mail" "$TEST_ROOT/running-image"
        touch "$TEST_ROOT/healthy"
        if [[ -f "$TEST_ROOT/unit-change" ]]; then
            mv "$TEST_ROOT/unit-change" "$TEST_ROOT/unit-applied"
        fi
    fi
}
_stack_wait_for_agent_mail_health() {
    printf 'check-health\n' >> "$TEST_ROOT/events"
    [[ -f "$TEST_ROOT/healthy" ]]
}
'''

FIXTURE_INSTALLER = r'''#!/bin/bash
set -euo pipefail
printf 'install\n' >> "$TEST_ROOT/events"
printf '%s\n' "$@" > "$TEST_ROOT/installer-arguments"
dest=''
force=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dest) dest="$2"; shift 2 ;;
        --version|--artifact-url|--checksum) shift 2 ;;
        --force) force=true; shift ;;
        --yes|--no-service) shift ;;
        *) printf 'unexpected fixture installer argument: %s\n' "$1" >&2; exit 90 ;;
    esac
done
[[ "$dest" == "$TEST_HOME/mcp_agent_mail" ]] || exit 91
# The reviewed upstream installer probes existing executables for information
# unless --force is supplied. Model that behavior so a receipt-drift repair
# would actually execute a corrupted binary if ACFS omitted this argument.
if [[ "$force" != true ]]; then
    for existing in "$dest/mcp-agent-mail" "$dest/am"; do
        if [[ -x "$existing" ]]; then
            "$existing" --version >/dev/null 2>&1 || true
        fi
    done
fi
[[ "${TEST_INSTALLER_FAIL:-}" != before ]] || exit 17
mkdir -p "$dest"
transaction="$dest/.mcp-agent-mail-install-transaction.active"
if [[ -e "$transaction" || -L "$transaction" ]]; then
    mv "$transaction" "$dest/fixture-recovered-transaction"
fi
cp "$TEST_ROOT/release/mcp-agent-mail" "$dest/mcp-agent-mail"
chmod 755 "$dest/mcp-agent-mail"
if [[ "${TEST_INSTALLER_MISSING_CLI:-false}" == true ]]; then
    if [[ -e "$dest/am" ]]; then mv "$dest/am" "$dest/am.not-installed"; fi
else
    cp "$TEST_ROOT/release/am" "$dest/am"
    chmod 755 "$dest/am"
fi
[[ "${TEST_INSTALLER_FAIL:-}" != after ]] || exit 23
'''


class IdempotencyFixture(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.name != "posix" or not Path("/bin/bash").is_file():
            raise unittest.SkipTest("requires Bash and a POSIX filesystem")
        cls.artifacts = Path(tempfile.mkdtemp(prefix="acfs-update-idempotency-"))
        print("Updater idempotency artifacts:", cls.artifacts, flush=True)

    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="case-", dir=self.artifacts))
        self.home = self.base / "target home"
        self.home.mkdir(mode=0o700)
        self.install = self.home / "mcp_agent_mail"
        self.install.mkdir(mode=0o755)
        self.server = self.install / "mcp-agent-mail"
        self.cli = self.install / "am"
        self.server.write_text('#!/bin/bash\nprintf "mcp-agent-mail 0.3.40\\n"\n')
        self.cli.write_text('#!/bin/bash\nprintf "am 0.3.40\\n"\n')
        for binary in (self.server, self.cli):
            binary.chmod(0o755)
        self.receipt_dir = self.home / ".local/state/acfs/verified-installs"
        self.receipt = self.receipt_dir / "mcp_agent_mail.json"
        self.contract = {
            "tool": "mcp_agent_mail",
            "installer_url": "https://fixture.invalid/reviewed/install.sh",
            "installer_sha256": "1" * 64,
            "release_tag": "v0.3.40",
            "target": "x86_64-unknown-linux-gnu",
            "manifest_sha256": "2" * 64,
            "signature_sha256": "3" * 64,
            "archive_sha256": "4" * 64,
        }
        self.env = {
            "PATH": "/usr/bin:/bin", "HOME": str(self.home),
            "TARGET_HOME": str(self.home), "TEST_HOME": str(self.home),
            "TEST_ROOT": str(self.base), "TEST_USER": pwd.getpwuid(os.geteuid()).pw_name,
            "UPDATE_TEST_LIBRARY": str(SOURCE), "REPO_ROOT": str(ROOT),
            "TMPDIR": str(self.base), "NO_COLOR": "1", "ACFS_INTERACTIVE": "false",
        }

    def shell(self, body, *, code=0, **env):
        result = subprocess.run(
            ["/bin/bash", "--noprofile", "--norc", "-c", COMMON + body],
            env=self.env | env, text=True, capture_output=True, timeout=30,
        )
        if code is not None:
            self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result

    def receipt_call(self, mode, *, contract=None, files=None, tool="mcp_agent_mail", code=0):
        contract = self.contract if contract is None else contract
        serialized = json.dumps(contract, sort_keys=True, separators=(",", ":"))
        files = [self.server, self.cli] if files is None else files
        command = shlex.join(["update_release_receipt", mode, tool, serialized,
                              *(str(path) for path in files)])
        return self.shell(command, code=code)

    def assert_receipt_refused(self, *, mode="match", **kwargs):
        result = self.receipt_call(mode, code=None, **kwargs)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)


class ReleaseReceiptTests(IdempotencyFixture):
    def test_no_receipt_does_not_adopt_matching_version_strings(self):
        self.assert_receipt_refused()
        self.assertFalse(self.receipt.exists())

    def test_verified_receipt_matches_across_repeated_processes_without_rewriting(self):
        self.receipt_call("write")
        original = self.receipt.read_bytes()
        before = self.receipt.stat()
        for _ in range(3):
            self.receipt_call("match")
        after = self.receipt.stat()
        self.assertEqual(self.receipt.read_bytes(), original)
        self.assertEqual((after.st_ino, after.st_mtime_ns), (before.st_ino, before.st_mtime_ns))
        self.assertEqual(stat.S_IMODE(after.st_mode), 0o600)
        self.assertEqual(after.st_uid, os.geteuid())
        self.assertEqual(stat.S_IMODE(self.receipt_dir.stat().st_mode), 0o700)

    def test_changed_release_metadata_invalidates_same_version(self):
        self.receipt_call("write")
        changes = {
            "manifest_sha256": "5" * 64,
            "signature_sha256": "6" * 64,
            "installer_sha256": "7" * 64,
            "installer_url": "https://fixture.invalid/new-reviewed/install.sh",
            "archive_sha256": "8" * 64,
            "target": "aarch64-unknown-linux-gnu",
            "release_tag": "v0.3.41",
        }
        for field, value in changes.items():
            with self.subTest(field=field):
                self.assert_receipt_refused(contract=self.contract | {field: value})

    def test_modified_server_is_rejected_despite_identical_reported_version(self):
        self.receipt_call("write")
        with self.server.open("a") as stream:
            stream.write("# modified bytes, same --version response\n")
        self.assertEqual(subprocess.check_output([self.server, "--version"], text=True),
                         "mcp-agent-mail 0.3.40\n")
        self.assert_receipt_refused()

    def test_modified_cli_is_rejected(self):
        self.receipt_call("write")
        with self.cli.open("a") as stream:
            stream.write("# changed launcher\n")
        self.assert_receipt_refused()

    def test_missing_server_or_cli_is_rejected(self):
        self.receipt_call("write")
        for path in (self.server, self.cli):
            with self.subTest(file=path.name):
                saved = path.with_suffix(".missing")
                path.rename(saved)
                try:
                    self.assert_receipt_refused()
                finally:
                    saved.rename(path)

    def test_missing_or_extra_required_inventory_is_rejected(self):
        self.receipt_call("write")
        self.assert_receipt_refused(files=[self.server])
        self.assert_receipt_refused(files=[])
        extra = self.install / "extra-helper"
        extra.write_bytes(self.cli.read_bytes())
        extra.chmod(0o755)
        self.assert_receipt_refused(files=[self.server, self.cli, extra])

    def test_replacement_with_identical_bytes_and_modes_is_current(self):
        self.receipt_call("write")
        replacement = self.install / "replacement"
        replacement.write_bytes(self.server.read_bytes())
        replacement.chmod(0o755)
        replacement.replace(self.server)
        self.receipt_call("match")

    def test_changed_file_permissions_are_rejected(self):
        self.receipt_call("write")
        for mode in (0o644, 0o700, 0o775, 0o777):
            with self.subTest(mode=oct(mode)):
                self.server.chmod(mode)
                try:
                    self.assert_receipt_refused()
                finally:
                    self.server.chmod(0o755)

    def test_group_or_world_writable_installed_files_cannot_be_recorded(self):
        for mode in (0o775, 0o777):
            with self.subTest(mode=oct(mode)):
                self.server.chmod(mode)
                self.assert_receipt_refused(mode="write")
                self.assertFalse(self.receipt.exists())

    def test_writable_install_directory_invalidates_receipt(self):
        self.receipt_call("write")
        self.install.chmod(0o777)
        self.assert_receipt_refused()
        self.assert_receipt_refused(mode="write")

    def test_symlinked_installed_payload_is_not_receipted(self):
        self.receipt_call("write")
        saved = self.install / "server-original"
        self.server.rename(saved)
        self.server.symlink_to(saved)
        self.assert_receipt_refused()
        self.assert_receipt_refused(mode="write")
        self.assertEqual(saved.read_bytes(), b'#!/bin/bash\nprintf "mcp-agent-mail 0.3.40\\n"\n')

    def test_symlinked_install_parent_is_not_receipted(self):
        self.receipt_call("write")
        relocated = self.home / "relocated-install"
        self.install.rename(relocated)
        self.install.symlink_to(relocated, target_is_directory=True)
        self.assert_receipt_refused()
        self.assert_receipt_refused(mode="write")

    def test_invalid_receipt_is_data_never_executed(self):
        self.receipt_call("write")
        marker = self.base / "receipt-executed"
        invalid = (
            "{}", "[]", "null", '{"schema":999}',
            '{"schema":1,"files":[]}',
            f"touch {shlex.quote(str(marker))}\n",
        )
        for text in invalid:
            with self.subTest(receipt=text):
                self.receipt.write_text(text)
                self.assert_receipt_refused()
                self.assertFalse(marker.exists())

    def test_insecure_receipt_permissions_fail_closed(self):
        self.receipt_call("write")
        for mode in (0o666, 0o664):
            with self.subTest(mode=oct(mode)):
                self.receipt.chmod(mode)
                self.assert_receipt_refused()
        self.receipt.chmod(0o600)
        self.receipt_call("match")

    def test_receipt_schema_must_be_integer_and_json_fields_unique(self):
        self.receipt_call("write")
        original = json.loads(self.receipt.read_text())
        for schema in (True, 1.0, 2, "1"):
            with self.subTest(schema=schema):
                self.receipt.write_text(json.dumps(original | {"schema": schema}))
                self.assert_receipt_refused()
        raw = json.dumps(original)
        self.receipt.write_text('{"schema":1,' + raw[1:])
        self.assert_receipt_refused()

    def test_hard_linked_receipt_or_payload_cannot_be_trusted(self):
        self.receipt_call("write")
        os.link(self.receipt, self.base / "linked-receipt")
        self.assert_receipt_refused()
        self.assert_receipt_refused(mode="write")

    def test_hard_linked_payload_cannot_be_recorded(self):
        os.link(self.server, self.base / "linked-server")
        self.assert_receipt_refused(mode="write")
        self.assertFalse(self.receipt.exists())

    def test_noncanonical_duplicate_or_external_inventory_is_rejected(self):
        self.receipt_call("write")
        outside = self.base / "outside-binary"
        outside.write_bytes(self.server.read_bytes())
        outside.chmod(0o755)
        inventories = (
            [self.server, self.server],
            [str(self.install) + "/../mcp_agent_mail/am", self.server],
            [outside, self.cli],
            ["mcp_agent_mail/am", self.server],
        )
        for paths in inventories:
            with self.subTest(paths=paths):
                self.assert_receipt_refused(mode="write", files=paths)
                self.assert_receipt_refused(files=paths)

    def test_symlinked_receipt_never_reads_or_overwrites_target(self):
        self.receipt_call("write")
        victim = self.base / "outside-receipt"
        self.receipt.rename(victim)
        original = victim.read_bytes()
        self.receipt.symlink_to(victim)
        self.assert_receipt_refused()
        self.assert_receipt_refused(mode="write")
        self.assertEqual(victim.read_bytes(), original)
        self.assertTrue(self.receipt.is_symlink())

    def test_symlinked_state_parent_never_writes_outside_home(self):
        local = self.home / ".local"
        local.mkdir(mode=0o755)
        outside = self.base / "outside-state"
        outside.mkdir(mode=0o700)
        (local / "state").symlink_to(outside, target_is_directory=True)
        self.assert_receipt_refused(mode="write")
        self.assertEqual(list(outside.iterdir()), [])

    def test_writable_receipt_directory_rejects_existing_receipt(self):
        self.receipt_call("write")
        self.receipt_dir.chmod(0o777)
        self.assert_receipt_refused()
        self.assert_receipt_refused(mode="write")

    def test_tool_name_cannot_escape_receipt_directory(self):
        for tool in ("", ".", "..", "../victim", "a/b", "a\nb", "/tmp/victim"):
            with self.subTest(tool=tool):
                self.assert_receipt_refused(mode="write", tool=tool)
        self.assertFalse(self.receipt.exists())

    def test_invalidation_disables_reuse_until_new_successful_write(self):
        self.receipt_call("write")
        self.receipt_call("invalidate")
        self.assert_receipt_refused()
        self.receipt_call("write")
        self.receipt_call("match")

    def test_failed_write_cannot_certify_missing_files(self):
        self.server.rename(self.install / "server-not-installed")
        self.assert_receipt_refused(mode="write")
        self.assertFalse(self.receipt.exists())

    def test_empty_or_invalid_contract_cannot_create_receipt(self):
        for contract in ({}, [], None, "not a release", 17):
            with self.subTest(contract=contract):
                # Pass JSON literally so None can mean JSON null here.
                command = shlex.join(["update_release_receipt", "write", "mcp_agent_mail",
                                      json.dumps(contract), str(self.server), str(self.cli)])
                result = self.shell(command, code=None)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.receipt.exists())


class AgentMailUpdaterTests(IdempotencyFixture):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        if not Path("/usr/bin/jq").is_file():
            raise unittest.SkipTest("requires jq, as does the release-contract resolver")

    def setUp(self):
        super().setUp()
        self.release = self.base / "release"
        self.release.mkdir()
        (self.base / "private-tmp").mkdir(mode=0o700)
        self.installer = self.base / "installer.sh"
        self.installer.write_text(FIXTURE_INSTALLER)
        self.installer.chmod(0o700)
        self.write_release("0.3.40")
        (self.base / "running-image").write_bytes(self.server.read_bytes())
        (self.base / "healthy").touch()

    def write_release(self, version):
        self.release_tag = "v" + version
        for name in ("am", "mcp-agent-mail"):
            path = self.release / name
            path.write_text(f'#!/bin/bash\nprintf "{name} {version}\\n"\n')
            path.chmod(0o755)
        self.artifact_url = ("https://fixture.invalid/releases/" + self.release_tag
                             + "/mcp-agent-mail-x86_64-unknown-linux-musl.tar.xz")
        # A fixture identifier, not a claim that an artifact was downloaded or
        # signature-verified. The resolver stub supplies this trusted contract.
        self.archive_sha = hashlib.sha256(
            (self.release / "am").read_bytes() + (self.release / "mcp-agent-mail").read_bytes()
        ).hexdigest()
        self.release_contract = {
            "adapter": "agent-mail-minisign-v1",
            "installer": {},
            "release": {"tag": self.release_tag, "artifact": self.artifact_url,
                        "sha256": self.archive_sha, "manifest": "2" * 64,
                        "signature": "3" * 64, "key": "fixture-only-key"},
            "platform": "Linux/x86_64",
            "options": ["--yes", "--no-service", "--force", "AM_INSTALL_SKIP_MCP_SETUP=1", "AM_INSTALL_SKIP_REMOTE_HTTP_READINESS=1"],
        }
        self.save_release_contract()

    def save_release_contract(self):
        (self.base / "release-contract.json").write_text(json.dumps(self.release_contract))

    def agent_mail(self, *, before="", **env):
        pin = hashlib.sha256(self.installer.read_bytes()).hexdigest()
        fixture_env = {
            "TEST_PIN": pin, "TEST_ACTUAL_PIN": pin,
            "TEST_RELEASE_TAG": self.release_tag,
            "TEST_ARTIFACT_URL": self.artifact_url,
            "TEST_ARCHIVE_SHA": self.archive_sha,
        } | env
        body = AGENT_MAIL_FIXTURE + before + r'''
update_agent_mail "${TEST_MINISIGN_READY:-true}"
printf 'COUNTS=%s,%s,%s,%s\n' "$SUCCESS_COUNT" "$SKIP_COUNT" "$FAIL_COUNT" "$HELD_COUNT"
'''
        return self.shell(body, **fixture_env)

    def events(self):
        path = self.base / "events"
        return path.read_text().splitlines() if path.exists() else []

    def test_repeated_identical_updates_download_and_install_only_once(self):
        self.assertFalse(self.receipt.exists())
        first = self.agent_mail()
        self.assertIn("COUNTS=1,0,0,0", first.stdout)
        for _ in range(3):
            result = self.agent_mail()
            self.assertIn("COUNTS=0,1,0,0", result.stdout)
        events = self.events()
        self.assertEqual(events.count("resolve-release"), 4)
        self.assertEqual(events.count("installer-download"), 1)
        self.assertEqual(events.count("install"), 1)
        self.assertEqual(events.count("reconcile-service"), 4)
        self.assertEqual(events.count("check-health"), 4)
        self.assertNotIn("restart-service", events)

    def test_first_install_is_bound_to_exact_resolved_release_and_artifact(self):
        self.agent_mail()
        arguments = (self.base / "installer-arguments").read_text().splitlines()
        self.assertEqual(arguments, ["--dest", str(self.install), "--yes", "--no-service", "--force",
                                     "--version", self.release_tag,
                                     "--artifact-url", self.artifact_url,
                                     "--checksum", self.archive_sha])
        self.assertTrue(self.receipt.is_file())

    def test_changed_signed_manifest_reinstalls_same_reported_version(self):
        self.agent_mail()
        self.release_contract["release"]["manifest"] = "5" * 64
        self.save_release_contract()
        self.agent_mail()
        self.agent_mail()
        self.assertEqual(self.events().count("installer-download"), 2)
        self.assertEqual(self.events().count("install"), 2)
        self.assertNotIn("restart-service", self.events())

    def test_changed_installer_pin_reinstalls_before_reuse(self):
        self.agent_mail()
        with self.installer.open("a") as stream:
            stream.write("# newly reviewed installer bytes\n")
        self.agent_mail()
        self.agent_mail()
        self.assertEqual(self.events().count("install"), 2)

    def test_changed_pin_during_verification_does_not_mint_old_contract_receipt(self):
        self.agent_mail()
        old_pin = hashlib.sha256(self.installer.read_bytes()).hexdigest()
        with self.installer.open("a") as stream:
            stream.write("# approved pin refreshed during verification\n")
        self.agent_mail(TEST_FORCE="true", TEST_PIN=old_pin, TEST_REFRESH_PIN="true")
        receipt = json.loads(self.receipt.read_text())
        self.assertTrue(receipt.get("invalidated"), receipt)
        self.agent_mail()
        self.agent_mail()
        self.assertEqual(self.events().count("install"), 3)

    def test_changed_server_is_repaired_before_any_untrusted_version_probe(self):
        self.agent_mail()
        marker = self.base / "untrusted-server-executed"
        self.server.write_text('#!/bin/bash\ntouch ' + shlex.quote(str(marker))
                               + '\nprintf "mcp-agent-mail 0.3.40\\n"\n')
        self.agent_mail()
        self.assertEqual(self.server.read_bytes(), (self.release / "mcp-agent-mail").read_bytes())
        self.assertFalse(marker.exists())
        self.assertEqual(self.events().count("install"), 2)
        self.assertNotIn("restart-service", self.events())

    def test_changed_cli_is_repaired_before_any_untrusted_version_probe(self):
        self.agent_mail()
        marker = self.base / "untrusted-cli-executed"
        self.cli.write_text('#!/bin/bash\ntouch ' + shlex.quote(str(marker))
                            + '\nprintf "am 0.3.40\\n"\n')
        self.agent_mail()
        self.assertEqual(self.cli.read_bytes(), (self.release / "am").read_bytes())
        self.assertFalse(marker.exists())
        self.assertEqual(self.events().count("install"), 2)

    def test_missing_server_and_cli_each_trigger_repair(self):
        self.agent_mail()
        for path in (self.server, self.cli):
            with self.subTest(file=path.name):
                path.rename(path.with_suffix(".missing"))
                self.agent_mail()
                self.assertEqual(path.read_bytes(), (self.release / path.name).read_bytes())
        self.assertEqual(self.events().count("install"), 3)
        self.agent_mail()
        self.assertEqual(self.events().count("install"), 3)

    def test_force_reinstalls_but_does_not_restart_identical_healthy_service(self):
        self.agent_mail()
        result = self.agent_mail(TEST_FORCE="true")
        self.assertIn("COUNTS=1,0,0,0", result.stdout)
        self.assertEqual(self.events().count("install"), 2)
        self.assertNotIn("restart-service", self.events())
        self.assertIn("--force", (self.base / "installer-arguments").read_text().splitlines())

    def test_real_operator_hold_blocks_release_download_install_and_service_even_with_force(self):
        self.agent_mail()
        before = self.events()
        (self.base / "holds.yaml").write_text(
            'holds:\n  mcp_agent_mail:\n    held_version: "0.3.40"\n'
            '    owner: "operator"\n    reason: "reservation repair in progress"\n'
            '    expiry: ""\n'
        )
        result = self.agent_mail(TEST_FORCE="true")
        self.assertIn("COUNTS=0,1,0,1", result.stdout)
        self.assertEqual(self.events(), before)
        self.assertIn("reservation repair in progress", (self.base / "update.log").read_text())

    def test_failed_first_install_does_not_create_reusable_receipt(self):
        result = self.agent_mail(TEST_INSTALLER_FAIL="after")
        self.assertIn("COUNTS=0,0,1,0", result.stdout)
        self.assertFalse(self.receipt.exists())
        self.assertNotIn("reconcile-service", self.events())
        self.agent_mail()
        self.agent_mail()
        self.assertEqual(self.events().count("install"), 2)

    def test_failed_reinstall_invalidates_previous_receipt_even_when_bytes_still_match(self):
        self.agent_mail()
        result = self.agent_mail(TEST_FORCE="true", TEST_INSTALLER_FAIL="before")
        self.assertIn("COUNTS=0,0,1,0", result.stdout)
        receipt = json.loads(self.receipt.read_text())
        self.assertTrue(receipt.get("invalidated"), receipt)
        self.assertEqual(self.events().count("reconcile-service"), 1)
        self.agent_mail()
        self.agent_mail()
        self.assertEqual(self.events().count("install"), 3)

    def test_pending_transaction_is_recovered_before_no_op_is_allowed(self):
        self.agent_mail()
        transaction = self.install / ".mcp-agent-mail-install-transaction.active"
        transaction.write_text("interrupted verified installation\n")
        self.agent_mail()
        self.agent_mail()
        self.assertEqual(self.events().count("install"), 2)
        self.assertTrue((self.install / "fixture-recovered-transaction").is_file())

    def test_dangling_transaction_marker_also_disables_no_op(self):
        self.agent_mail()
        transaction = self.install / ".mcp-agent-mail-install-transaction.active"
        transaction.symlink_to(self.install / "missing-transaction")
        self.agent_mail()
        self.agent_mail()
        self.assertEqual(self.events().count("install"), 2)
        self.assertTrue((self.install / "fixture-recovered-transaction").is_symlink())

    def test_success_exit_with_missing_payload_does_not_create_receipt(self):
        result = self.agent_mail(TEST_INSTALLER_MISSING_CLI="true")
        self.assertIn("COUNTS=0,0,1,0", result.stdout)
        self.assertFalse(self.receipt.exists())
        self.agent_mail()
        self.agent_mail()
        self.assertEqual(self.events().count("install"), 2)

    def test_unhealthy_service_is_reconciled_on_installation_no_op(self):
        self.agent_mail()
        (self.base / "healthy").rename(self.base / "health-lost")
        result = self.agent_mail()
        self.assertIn("COUNTS=0,1,0,0", result.stdout)
        self.assertEqual(self.events().count("install"), 1)
        self.assertEqual(self.events().count("reconcile-service"), 2)
        self.assertEqual(self.events().count("restart-service"), 1)
        self.assertTrue((self.base / "healthy").exists())

    def test_changed_unit_is_reconciled_on_installation_no_op(self):
        self.agent_mail()
        (self.base / "unit-change").touch()
        self.agent_mail()
        self.agent_mail()
        self.assertEqual(self.events().count("install"), 1)
        self.assertEqual(self.events().count("restart-service"), 1)
        self.assertTrue((self.base / "unit-applied").exists())

    def test_actual_upgrade_installs_and_restarts_once_then_becomes_no_op(self):
        self.agent_mail()
        self.write_release("0.3.41")
        self.agent_mail()
        result = self.agent_mail()
        self.assertIn("COUNTS=0,1,0,0", result.stdout)
        self.assertEqual(self.events().count("installer-download"), 2)
        self.assertEqual(self.events().count("install"), 2)
        self.assertEqual(self.events().count("restart-service"), 1)
        self.assertEqual(self.server.read_bytes(), (self.release / "mcp-agent-mail").read_bytes())

    def test_unavailable_release_contract_falls_back_to_verified_installer(self):
        for _ in range(2):
            self.agent_mail(TEST_CONTRACT_UNAVAILABLE="true")
        self.assertEqual(self.events().count("install"), 2)
        self.assertEqual(self.events().count("installer-download"), 2)
        self.assertFalse(self.receipt.exists())
        arguments = (self.base / "installer-arguments").read_text().splitlines()
        self.assertEqual(arguments, ["--dest", str(self.install), "--yes", "--no-service", "--force"])

    def test_force_cannot_bypass_installer_checksum_failure(self):
        self.agent_mail()
        result = self.agent_mail(TEST_FORCE="true", TEST_PIN="0" * 64)
        self.assertIn("COUNTS=0,0,1,0", result.stdout)
        self.assertEqual(self.events().count("installer-download"), 2)
        self.assertEqual(self.events().count("install"), 1)
        self.assertEqual(self.events().count("reconcile-service"), 1)

    def test_service_opt_out_is_preserved_on_verified_installation_no_op(self):
        self.agent_mail()
        result = self.agent_mail(TEST_SERVICE_HOLD="true")
        self.assertIn("COUNTS=1,0,0,0", result.stdout)
        self.assertEqual(self.events().count("install"), 1)
        self.assertNotIn("restart-service", self.events())
        self.assertIn("local opt-out", (self.base / "update.log").read_text())

    def test_service_failure_is_reported_even_when_installation_is_current(self):
        self.agent_mail()
        result = self.agent_mail(TEST_SERVICE_FAILURE="true")
        self.assertIn("COUNTS=0,0,1,0", result.stdout)
        self.assertEqual(self.events().count("install"), 1)
        self.assertIn("service setup/readiness failed", result.stdout)

    def test_dry_run_and_missing_minisign_never_download_or_touch_service(self):
        dry = self.agent_mail(TEST_DRY_RUN="true")
        self.assertIn("COUNTS=0,1,0,0", dry.stdout)
        missing = self.agent_mail(TEST_MINISIGN_READY="false")
        self.assertIn("COUNTS=0,0,1,0", missing.stdout)
        self.assertEqual(self.events(), [])
        self.assertFalse(self.receipt.exists())


if __name__ == "__main__":
    unittest.main()
