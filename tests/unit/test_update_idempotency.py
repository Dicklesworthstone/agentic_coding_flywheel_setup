"""Exercise integrity-aware updater no-ops with isolated, retained fixtures.

Receipt tests invoke the real Bash entrypoint, target runner and filesystem
validation. Agent Mail orchestration tests substitute release discovery and
service operations: they prove installation/reconciliation decisions, not
cryptographic authenticity. Signed-manifest verification is tested separately.
No package manager, external network, real tool installation or service runs.
"""
from contextlib import contextmanager
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import pwd
import shlex
import stat
import subprocess
import tarfile
import tempfile
import time
import unittest
from urllib.parse import unquote, urlsplit


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
# Substitute transport only: production staging, signed-metadata hash binding,
# archive parsing, installed-file comparisons, and kernel locking remain real.
update_download_release_file() {
    local kind='' source=''
    case "$1" in
        "$TEST_ARTIFACT_URL") kind=archive; source="$TEST_ROOT/release.tar.xz" ;;
        "${TEST_ARTIFACT_URL%/*}/SHA256SUMS") kind=manifest; source="$TEST_ROOT/SHA256SUMS" ;;
        "${TEST_ARTIFACT_URL%/*}/SHA256SUMS.minisig") kind=signature; source="$TEST_ROOT/SHA256SUMS.minisig" ;;
        *) return 22 ;;
    esac
    printf '%s-download\n' "$kind" >> "$TEST_ROOT/events"
    [[ "${TEST_RELEASE_FILE_UNAVAILABLE:-}" != "$kind" ]] || return 22
    cat "$source" > "$2"
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
        --yes|--no-service|--offline) shift ;;
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
lock="$dest/.mcp-agent-mail-install.lock.$(id -u).d"
if [[ ! -e "$lock" && ! -L "$lock" ]]; then
    mkdir -m 700 "$lock"
fi
[[ -d "$lock" && ! -L "$lock" && "$(stat -c %a "$lock")" == 700 ]] || exit 19
exec 8< "$lock"
flock -n -x 8 || exit 18
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


REAL_AGENT_MAIL_COMMAND_LINKS = r'''
# Link-specific cases use the real stack helper and account runner while keeping
# the service fixture. Isolate only passwd-home resolution from the real host.
fixture_service_helpers="$(declare -f _stack_configure_agent_mail_service _stack_wait_for_agent_mail_health)"
ACFS_BLUE=fixture
source "$REPO_ROOT/scripts/lib/stack.sh"
eval "$fixture_service_helpers"
_stack_target_home() { printf '%s\n' "$TEST_HOME"; }
log_warn() { printf '%s\n' "$*" >&2; }
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
        arguments = ["update_release_receipt", mode, tool, serialized]
        if mode == "write":
            # These low-level filesystem tests explicitly supply fixture
            # expectations, including deliberately unsafe types/modes. They
            # test path validation, not independent release authenticity.
            # Updater tests below obtain expectations from archive members.
            arguments[1] = "write-verified"
            arguments.append(json.dumps(self.fixture_inventory(files)))
        command = shlex.join([*arguments, *(str(path) for path in files)])
        return self.shell(command, code=code)

    def fixture_inventory(self, files):
        expected = []
        for path in files:
            try:
                digest = hashlib.sha256(Path(path).read_bytes()).hexdigest()
                mode = stat.S_IMODE(Path(path).stat().st_mode)
            except OSError:
                # Keep nonexistent/invalid paths as inputs to the production
                # validator so the shell helper must refuse them itself.
                digest, mode = "0" * 64, 0o755
            expected.append({"path": str(path), "mode": mode, "sha256": digest})
        return expected

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
                command = shlex.join(["update_release_receipt", "write-verified", "mcp_agent_mail",
                                      json.dumps(contract),
                                      json.dumps(self.fixture_inventory([self.server, self.cli])),
                                      str(self.server), str(self.cli)])
                result = self.shell(command, code=None)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.receipt.exists())


class VerifiedReleaseReceiptTests(IdempotencyFixture):
    """Receipt publication must compare against independent release evidence."""

    def expected_inventory(self):
        return [{"path": str(path), "mode": 0o755,
                 "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                for path in (self.server, self.cli)]

    def write_verified(self, expected, *, files=None, code=0):
        files = [self.server, self.cli] if files is None else files
        command = shlex.join([
            "update_release_receipt", "write-verified", "mcp_agent_mail",
            json.dumps(self.contract), json.dumps(expected),
            *(str(path) for path in files),
        ])
        return self.shell(command, code=code)

    def test_archive_bound_inventory_can_be_published_and_reused(self):
        expected = self.expected_inventory()
        self.write_verified(expected)
        self.receipt_call("match")
        self.assertEqual(json.loads(self.receipt.read_text())["files"], expected)

    def test_unchecked_write_mode_is_not_an_available_receipt_api(self):
        command = shlex.join(["update_release_receipt", "write", "mcp_agent_mail",
                              json.dumps(self.contract), str(self.server), str(self.cli)])
        result = self.shell(command, code=None)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.receipt.exists())

    def test_check_verified_requires_no_prior_receipt_and_does_not_publish_one(self):
        expected = self.expected_inventory()
        command = shlex.join([
            "update_release_receipt", "check-verified", "mcp_agent_mail",
            json.dumps(self.contract), json.dumps(expected), str(self.server), str(self.cli),
        ])
        self.shell(command)
        self.assertFalse(self.receipt_dir.exists())
        with self.cli.open("a") as stream:
            stream.write("# changed before service reconciliation\n")
        result = self.shell(command, code=None)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.receipt_dir.exists())

    def test_same_version_replacement_after_evidence_capture_cannot_be_blessed(self):
        expected = self.expected_inventory()
        with self.cli.open("a") as stream:
            stream.write("# independently built binary with identical version output\n")
        result = self.write_verified(expected, code=None)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.receipt.exists())

    def test_verified_inventory_requires_exact_digest_and_mode_for_every_path(self):
        expected = self.expected_inventory()
        variants = (
            [expected[0] | {"sha256": "f" * 64}, expected[1]],
            [expected[0] | {"mode": 0o700}, expected[1]],
            [expected[0]],
            [expected[0], expected[0]],
            [expected[0], expected[1], expected[1]],
            [expected[0] | {"path": str(self.install / "other")}, expected[1]],
        )
        for inventory in variants:
            with self.subTest(inventory=inventory):
                result = self.write_verified(inventory, code=None)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse(self.receipt.exists())

    def test_invalid_expected_inventory_never_falls_back_to_observed_bytes(self):
        expected = self.expected_inventory()
        invalid = (
            None, {}, [], "not an inventory", [None],
            [expected[0] | {"mode": True}, expected[1]],
            [expected[0] | {"mode": "755"}, expected[1]],
            [expected[0] | {"sha256": "invalid"}, expected[1]],
        )
        for inventory in invalid:
            with self.subTest(inventory=inventory):
                result = self.write_verified(inventory, code=None)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse(self.receipt.exists())

    def test_failed_verified_write_does_not_replace_existing_receipt(self):
        expected = self.expected_inventory()
        self.write_verified(expected)
        previous = self.receipt.read_bytes()
        with self.server.open("a") as stream:
            stream.write("# changed after verified release inventory was calculated\n")
        result = self.write_verified(expected, code=None)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.receipt.read_bytes(), previous)
        self.assert_receipt_refused()


class AgentMailLockTests(IdempotencyFixture):
    """Coordinate with upstream's native lock without mocks or real services."""

    def setUp(self):
        super().setUp()
        self.lock = self.install / f".mcp-agent-mail-install.lock.{os.geteuid()}.d"
        self.env["TEST_LOCK_AUTHORITY"] = str(self.lock)

    def test_acquisition_blocks_independent_flock_until_confirmed_release(self):
        self.shell(r'''
update_agent_mail_lock_acquire "$TEST_HOME" || exit 90
update_agent_mail_lock_check || exit 91
exec 7< "$TEST_LOCK_AUTHORITY"
if flock -n -x 7; then exit 92; fi
exec 7<&-
update_agent_mail_lock_release || exit 93
flock -n -x "$TEST_LOCK_AUTHORITY" /bin/true || exit 94
[[ -z "${UPDATE_AGENT_MAIL_LOCK_PID:-}" && -z "${UPDATE_AGENT_MAIL_LOCK_READ_FD:-}" \
   && -z "${UPDATE_AGENT_MAIL_LOCK_WRITE_FD:-}" && -z "${UPDATE_AGENT_MAIL_LOCK_HOME:-}" ]] || exit 95
''')
        self.assertEqual(stat.S_IMODE(self.lock.stat().st_mode), 0o700)

    def test_competing_upstream_flock_returns_busy_without_stealing_authority(self):
        self.lock.mkdir(mode=0o700)
        identity = self.lock.stat().st_ino
        fd = os.open(self.lock, os.O_RDONLY | os.O_DIRECTORY)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.shell('update_agent_mail_lock_acquire "$TEST_HOME"', code=75)
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)
        self.assertEqual(self.lock.stat().st_ino, identity)
        self.assertEqual(stat.S_IMODE(self.lock.stat().st_mode), 0o700)

    def test_missing_destination_is_distinct_from_current_or_unsafe_installation(self):
        self.install.rename(self.home / "preserved-installation")
        self.shell('update_agent_mail_lock_acquire "$TEST_HOME"', code=3)
        self.assertFalse(self.install.exists())
        self.assertFalse(self.receipt.exists())

    def test_nonprivate_symlinked_or_non_directory_authority_is_refused(self):
        target = self.install / "outside-authority"
        target.mkdir(mode=0o700)
        for kind in ("nonprivate", "writable", "symlink", "regular", "fifo"):
            with self.subTest(authority=kind):
                if kind in ("nonprivate", "writable"):
                    self.lock.mkdir(mode=0o700)
                    self.lock.chmod(0o755 if kind == "nonprivate" else 0o777)
                elif kind == "symlink":
                    self.lock.symlink_to(target, target_is_directory=True)
                elif kind == "regular":
                    self.lock.write_text("not a lock directory\n")
                else:
                    os.mkfifo(self.lock, 0o600)
                self.shell('update_agent_mail_lock_acquire "$TEST_HOME"', code=1)
                self.lock.rename(self.install / ("preserved-" + kind))
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o700)
        self.assertEqual(list(target.iterdir()), [])

    def test_pending_regular_and_dangling_transaction_markers_are_reported_under_lock(self):
        self.shell(r'''
update_agent_mail_lock_acquire "$TEST_HOME" || exit 90
transaction="$TEST_HOME/mcp_agent_mail/.mcp-agent-mail-install-transaction.active"
printf 'pending\n' > "$transaction"
status=0
update_agent_mail_lock_check || status=$?
[[ "$status" == 2 ]] || exit 91
mv "$transaction" "$TEST_ROOT/preserved-transaction"
update_agent_mail_lock_check || exit 92
ln -s "$TEST_ROOT/missing-transaction" "$transaction"
status=0
update_agent_mail_lock_check || status=$?
[[ "$status" == 2 ]] || exit 93
update_agent_mail_lock_release || exit 94
''')

    def test_replaced_lock_inode_is_rejected_and_old_inode_is_unlocked(self):
        self.shell(r'''
update_agent_mail_lock_acquire "$TEST_HOME" || exit 90
mv "$TEST_LOCK_AUTHORITY" "$TEST_ROOT/preserved-held-authority"
mkdir -m 700 "$TEST_LOCK_AUTHORITY"
status=0
update_agent_mail_lock_check || status=$?
[[ "$status" == 1 ]] || exit 91
update_agent_mail_lock_release || true
flock -n -x "$TEST_ROOT/preserved-held-authority" /bin/true || exit 92
[[ -z "${UPDATE_AGENT_MAIL_LOCK_PID:-}" ]] || exit 93
''')

    def test_replaced_destination_is_rejected_without_locking_new_destination(self):
        self.shell(r'''
update_agent_mail_lock_acquire "$TEST_HOME" || exit 90
mv "$TEST_HOME/mcp_agent_mail" "$TEST_HOME/preserved-held-installation"
mkdir -m 755 "$TEST_HOME/mcp_agent_mail"
status=0
update_agent_mail_lock_check || status=$?
[[ "$status" == 1 ]] || exit 91
update_agent_mail_lock_release || true
[[ ! -e "$TEST_LOCK_AUTHORITY" ]] || exit 92
''')

    def test_parent_exit_unlocks_even_while_a_spawned_child_remains_alive(self):
        release = self.base / "background-child-release"
        os.mkfifo(release, 0o600)
        fd = None
        try:
            self.shell(r'''
update_agent_mail_lock_acquire "$TEST_HOME" || exit 90
/bin/bash --noprofile --norc -c 'read -r < "$1"' acfs-lock-child "$TEST_CHILD_RELEASE" \
    >/dev/null 2>&1 &
printf '%s\n' "$!" > "$TEST_ROOT/background-child-pid"
# Deliberately exit without calling release. Only caller EOF can unlock.
''', TEST_CHILD_RELEASE=str(release))
            child_pid = int((self.base / "background-child-pid").read_text())
            os.kill(child_pid, 0)
            fd = os.open(self.lock, os.O_RDONLY | os.O_DIRECTORY)
            deadline = time.monotonic() + 3
            acquired = False
            while time.monotonic() < deadline:
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    acquired = True
                    break
                except BlockingIOError:
                    time.sleep(0.02)
            self.assertTrue(acquired, "a background child retained the installer lock after updater exit")
            os.kill(child_pid, 0)
        finally:
            if fd is not None:
                os.close(fd)
            # The intentionally long-lived fixture exits only after the test
            # releases it. No timing assumption determines whether it is alive.
            writer = os.open(release, os.O_RDWR | os.O_NONBLOCK)
            try:
                os.write(writer, b"release\n")
            finally:
                os.close(writer)


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
        self.archive = self.base / "release.tar.xz"
        self.write_release("0.3.40")
        (self.base / "running-image").write_bytes(self.server.read_bytes())
        (self.base / "healthy").touch()

    def write_release(self, version):
        self.release_tag = "v" + version
        for name in ("am", "mcp-agent-mail"):
            path = self.release / name
            path.write_text(f'#!/bin/bash\nprintf "{name} {version}\\n"\n')
            path.chmod(0o755)
        self.artifact_url = ("https://github.com/Dicklesworthstone/mcp_agent_mail_rust/releases/download/" + self.release_tag
                             + "/mcp-agent-mail-x86_64-unknown-linux-musl.tar.xz")
        # The resolver stub supplies an authenticated contract. The updater
        # still verifies these actual archive bytes and their member inventory.
        self.write_archive()
        self.archive_sha = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.manifest = self.base / "SHA256SUMS"
        self.signature = self.base / "SHA256SUMS.minisig"
        self.manifest.write_text(f"{self.archive_sha}  {self.artifact_url.rsplit('/', 1)[-1]}\n")
        # This is not a cryptographic acceptance test: release resolution is
        # stubbed above. Exact metadata transport/hash binding remains real.
        self.signature.write_text(f"fixture signature bound to {self.release_tag}\n")
        self.release_contract = {
            "adapter": "agent-mail-minisign-v2",
            "installer": {},
            "release": {"tag": self.release_tag, "artifact": self.artifact_url,
                        "sha256": self.archive_sha,
                        "manifest": hashlib.sha256(self.manifest.read_bytes()).hexdigest(),
                        "signature": hashlib.sha256(self.signature.read_bytes()).hexdigest(),
                        "key": "fixture-only-key"},
            "platform": "Linux/x86_64",
            "options": ["--yes", "--no-service", "--force", "--offline", "AM_INSTALL_SKIP_MCP_SETUP=1", "AM_INSTALL_SKIP_REMOTE_HTTP_READINESS=1"],
        }
        self.save_release_contract()

    def write_archive(self, members=None):
        if members is None:
            members = []
            for name in ("am", "mcp-agent-mail"):
                payload = (self.release / name).read_bytes()
                member = tarfile.TarInfo(name)
                member.mode = 0o755
                member.size = len(payload)
                members.append((member, payload))
        with tarfile.open(self.archive, "w:xz") as archive:
            for member, payload in members:
                archive.addfile(member, io.BytesIO(payload) if member.isfile() else None)

    @property
    def lock_authority(self):
        return self.install / f".mcp-agent-mail-install.lock.{os.geteuid()}.d"

    @contextmanager
    def hold_upstream_lock(self):
        """Use the same inode and native flock as the reviewed installer."""
        fd = os.open(self.lock_authority, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            yield
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)

    def save_release_contract(self):
        (self.base / "release-contract.json").write_text(json.dumps(self.release_contract))

    def bind_archive_to_fixture_contract(self):
        self.archive_sha = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.manifest.write_text(f"{self.archive_sha}  {self.artifact_url.rsplit('/', 1)[-1]}\n")
        self.release_contract["release"]["sha256"] = self.archive_sha
        self.release_contract["release"]["manifest"] = hashlib.sha256(
            self.manifest.read_bytes()
        ).hexdigest()
        self.save_release_contract()

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
        self.assertEqual(events.count("archive-download"), 1)
        self.assertEqual(events.count("install"), 1)
        self.assertEqual(events.count("reconcile-service"), 4)
        self.assertEqual(events.count("check-health"), 4)
        self.assertNotIn("restart-service", events)

    def test_first_install_is_bound_to_exact_resolved_release_and_artifact(self):
        self.agent_mail()
        arguments = (self.base / "installer-arguments").read_text().splitlines()
        artifact = arguments[arguments.index("--artifact-url") + 1]
        self.assertEqual(urlsplit(artifact).scheme, "file")
        self.assertEqual(Path(unquote(urlsplit(artifact).path)).name,
                         self.artifact_url.rsplit("/", 1)[-1])
        self.assertEqual(arguments, ["--dest", str(self.install), "--yes", "--no-service", "--force",
                                     "--version", self.release_tag,
                                     "--artifact-url", artifact,
                                     "--checksum", self.archive_sha, "--offline"])
        self.assertTrue(self.receipt.is_file())

    def test_changed_signed_manifest_reinstalls_same_reported_version(self):
        self.agent_mail()
        # The authenticated manifest changes while the selected artifact stays
        # identical. Its newly staged bytes must agree with the new contract.
        self.manifest.write_bytes(self.manifest.read_bytes() + b"\n")
        self.release_contract["release"]["manifest"] = hashlib.sha256(
            self.manifest.read_bytes()
        ).hexdigest()
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

    def test_old_receipt_without_archive_member_proof_cannot_authorize_no_op(self):
        self.agent_mail()
        previous = json.loads(self.receipt.read_text())
        previous["contract"]["adapter"] = "agent-mail-minisign-v1"
        self.receipt.write_text(json.dumps(previous))
        self.agent_mail()
        self.agent_mail()
        self.assertEqual(self.events().count("install"), 2)
        self.assertEqual(self.events().count("archive-download"), 2)
        current = json.loads(self.receipt.read_text())
        self.assertEqual(current["contract"]["adapter"], "agent-mail-minisign-v2")

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

    def test_post_installer_same_version_replacement_is_not_receipted_or_executed(self):
        result = self.agent_mail(before=r'''
update_run_logged_passthrough() {
    local status=0
    "$@" || status=$?
    if [[ "$status" == 0 ]]; then
        for payload in am mcp-agent-mail; do
            printf '\n# independently built same-version replacement\ntouch "$TEST_ROOT/untrusted-payload-executed"\n' \
                >> "$TEST_HOME/mcp_agent_mail/$payload"
        done
    fi
    return "$status"
}
''')
        self.assertIn("COUNTS=0,0,1,0", result.stdout)
        self.assertFalse(self.receipt.exists())
        self.assertFalse((self.base / "untrusted-payload-executed").exists())
        self.assertNotIn("repair-alias", self.events())
        self.assertNotIn("reconcile-service", self.events())
        self.assertNotIn("check-health", self.events())
        self.agent_mail()
        self.agent_mail()
        self.assertEqual(self.events().count("install"), 2)
        self.assertEqual(self.events().count("reconcile-service"), 2)
        self.assertEqual(self.server.read_bytes(), (self.release / "mcp-agent-mail").read_bytes())

    def test_upstream_directory_lock_blocks_no_op_and_service_actions(self):
        self.agent_mail()
        previous_events = self.events()
        previous_receipt = self.receipt.read_bytes()
        with self.hold_upstream_lock():
            result = self.agent_mail()
        self.assertIn("COUNTS=0,0,1,0", result.stdout)
        during = self.events()[len(previous_events):]
        for event in ("installer-download", "archive-download", "install", "repair-alias",
                      "reconcile-service", "check-health"):
            self.assertNotIn(event, during)
        self.assertEqual(self.receipt.read_bytes(), previous_receipt)
        recovered = self.agent_mail()
        self.assertIn("COUNTS=0,1,0,0", recovered.stdout)
        self.assertEqual(self.events().count("install"), 1)

    def test_reconciliation_and_health_checks_hold_the_real_upstream_lock(self):
        hook = r'''
assert_destination_lock_held() {
    local lock="$TEST_HOME/mcp_agent_mail/.mcp-agent-mail-install.lock.$(id -u).d"
    exec 7< "$lock" || return 1
    if flock -n -x 7; then
        printf 'unlocked-service-action\n' >> "$TEST_ROOT/events"
        exec 7<&-
        return 1
    fi
    exec 7<&-
}
_stack_configure_agent_mail_service() {
    assert_destination_lock_held || return 1
    printf 'reconcile-service\n' >> "$TEST_ROOT/events"
}
_stack_wait_for_agent_mail_health() {
    assert_destination_lock_held || return 1
    printf 'check-health\n' >> "$TEST_ROOT/events"
}
'''
        first = self.agent_mail(before=hook)
        second = self.agent_mail(before=hook)
        self.assertIn("COUNTS=1,0,0,0", first.stdout)
        self.assertIn("COUNTS=0,1,0,0", second.stdout)
        self.assertEqual(self.events().count("reconcile-service"), 2)
        self.assertEqual(self.events().count("check-health"), 2)
        self.assertNotIn("unlocked-service-action", self.events())

    def test_writable_or_symlinked_lock_authority_stops_before_service(self):
        self.agent_mail()
        previous_events = self.events()
        self.lock_authority.chmod(0o755)
        bad_mode = self.agent_mail()
        self.assertIn("COUNTS=0,0,1,0", bad_mode.stdout)
        preserved = self.install / "preserved-lock-authority"
        self.lock_authority.rename(preserved)
        self.lock_authority.symlink_to(preserved, target_is_directory=True)
        bad_link = self.agent_mail()
        self.assertIn("COUNTS=0,0,1,0", bad_link.stdout)
        during = self.events()[len(previous_events):]
        for event in ("installer-download", "archive-download", "install", "repair-alias",
                      "reconcile-service", "check-health"):
            self.assertNotIn(event, during)
        self.assertEqual(stat.S_IMODE(preserved.stat().st_mode), 0o755)
        self.assertTrue(self.lock_authority.is_symlink())

    def test_missing_kernel_lock_capability_cannot_turn_receipt_into_no_op(self):
        self.agent_mail()
        previous_events = self.events()
        result = self.agent_mail(before=r'''
eval "$(declare -f update_system_binary_path | sed '1s/update_system_binary_path/fixture_system_binary_path/')"
update_system_binary_path() {
    case "$1" in flock|python3) return 1 ;; esac
    fixture_system_binary_path "$@"
}
''')
        self.assertIn("COUNTS=0,0,1,0", result.stdout)
        for event in ("install", "repair-alias", "reconcile-service", "check-health"):
            self.assertNotIn(event, self.events()[len(previous_events):])

    def test_transaction_appearing_after_installer_exit_blocks_receipt_and_service(self):
        result = self.agent_mail(before=r'''
update_run_logged_passthrough() {
    local status=0
    "$@" || status=$?
    if [[ "$status" == 0 ]]; then
        printf 'competing installation started a transaction\n' \
            > "$TEST_HOME/mcp_agent_mail/.mcp-agent-mail-install-transaction.active"
    fi
    return "$status"
}
''')
        self.assertIn("COUNTS=0,0,1,0", result.stdout)
        self.assertFalse(self.receipt.exists())
        self.assertNotIn("repair-alias", self.events())
        self.assertNotIn("reconcile-service", self.events())
        self.agent_mail()
        self.agent_mail()
        self.assertEqual(self.events().count("install"), 2)
        self.assertTrue((self.install / "fixture-recovered-transaction").is_file())

    def test_transaction_appearing_after_receipt_match_is_rechecked_before_service(self):
        self.agent_mail()
        before = self.events()
        result = self.agent_mail(before=r'''
eval "$(declare -f update_release_receipt | sed '1s/update_release_receipt/fixture_release_receipt/')"
update_release_receipt() {
    local status=0
    fixture_release_receipt "$@" || status=$?
    if [[ "$1" == match && "$status" == 0 ]]; then
        printf 'transaction appeared before reconciliation\n' \
            > "$TEST_HOME/mcp_agent_mail/.mcp-agent-mail-install-transaction.active"
    fi
    return "$status"
}
''')
        self.assertIn("COUNTS=0,0,1,0", result.stdout)
        for event in ("install", "repair-alias", "reconcile-service", "check-health"):
            self.assertNotIn(event, self.events()[len(before):])
        self.agent_mail()
        self.agent_mail()
        self.assertEqual(self.events().count("install"), 2)
        self.assertTrue((self.install / "fixture-recovered-transaction").is_file())

    def test_archive_bytes_must_match_authenticated_release_checksum(self):
        self.archive.write_bytes(b"untrusted archive with a forged same-version payload\n")
        result = self.agent_mail()
        self.assertIn("COUNTS=0,0,1,0", result.stdout)
        self.assertNotIn("install", self.events())
        self.assertNotIn("reconcile-service", self.events())
        self.assertFalse(self.receipt.exists())

    def test_staged_archive_url_must_match_the_authenticated_release_contract(self):
        self.release_contract["release"]["artifact"] = self.artifact_url.replace(
            "/v0.3.40/", "/v0.3.39/"
        )
        self.save_release_contract()
        result = self.agent_mail()
        self.assertIn("COUNTS=0,0,1,0", result.stdout)
        self.assertNotIn("install", self.events())
        self.assertNotIn("reconcile-service", self.events())
        self.assertFalse(self.receipt.exists())

    def test_staged_manifest_and_signature_must_match_resolved_authentic_metadata(self):
        for path in (self.manifest, self.signature):
            with self.subTest(file=path.name):
                original = path.read_bytes()
                path.write_bytes(original + b"replacement between discovery and staging\n")
                try:
                    result = self.agent_mail()
                    self.assertIn("COUNTS=0,0,1,0", result.stdout)
                    self.assertNotIn("install", self.events())
                    self.assertNotIn("reconcile-service", self.events())
                    self.assertFalse(self.receipt.exists())
                finally:
                    path.write_bytes(original)

    def test_archive_and_metadata_transport_failure_cannot_bless_installed_files(self):
        for kind in ("archive", "manifest", "signature"):
            with self.subTest(file=kind):
                result = self.agent_mail(TEST_RELEASE_FILE_UNAVAILABLE=kind)
                self.assertIn("COUNTS=0,0,1,0", result.stdout)
                self.assertNotIn("install", self.events())
                self.assertNotIn("reconcile-service", self.events())
                self.assertFalse(self.receipt.exists())

    def test_installed_payload_must_match_archive_members_not_only_version(self):
        members = []
        for name in ("am", "mcp-agent-mail"):
            payload = (self.release / name).read_bytes() + b"# different legitimate archive build\n"
            member = tarfile.TarInfo(name)
            member.mode = 0o755
            member.size = len(payload)
            members.append((member, payload))
        self.write_archive(members)
        self.bind_archive_to_fixture_contract()
        # The inert installer deliberately publishes the different release/
        # bytes. Matching versions and successful exit cannot authorize them.
        result = self.agent_mail()
        self.assertIn("COUNTS=0,0,1,0", result.stdout)
        self.assertEqual(self.events().count("install"), 1)
        self.assertNotIn("repair-alias", self.events())
        self.assertNotIn("reconcile-service", self.events())
        self.assertFalse(self.receipt.exists())

    def test_ambiguous_missing_or_unsafe_archive_members_are_rejected(self):
        payloads = {name: (self.release / name).read_bytes() for name in ("am", "mcp-agent-mail")}

        def member(name, payload=b"", kind=tarfile.REGTYPE, target=""):
            info = tarfile.TarInfo(name)
            info.mode = 0o755
            info.type = kind
            info.linkname = target
            info.size = len(payload) if kind == tarfile.REGTYPE else 0
            return info, payload

        normal = [member(name, payload) for name, payload in payloads.items()]
        variants = {
            "duplicate": normal + [member("am", payloads["am"])],
            "alias_duplicate": normal + [member("./am", payloads["am"])],
            "missing_server": [normal[0]],
            "traversal": normal + [member("../unexpected", b"outside installation\n")],
            "symlink": [member("am", kind=tarfile.SYMTYPE, target="mcp-agent-mail"), normal[1]],
            "hardlink": [member("am", kind=tarfile.LNKTYPE, target="mcp-agent-mail"), normal[1]],
        }
        for kind, entries in variants.items():
            with self.subTest(archive=kind):
                self.write_archive(entries)
                self.bind_archive_to_fixture_contract()
                result = self.agent_mail()
                self.assertIn("COUNTS=0,0,1,0", result.stdout)
                self.assertNotIn("install", self.events())
                self.assertNotIn("reconcile-service", self.events())
                self.assertFalse(self.receipt.exists())

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

    def test_missing_server_command_link_is_repaired_on_payload_no_op_without_restart(self):
        self.agent_mail(before=REAL_AGENT_MAIL_COMMAND_LINKS)
        server_link = self.home / ".local/bin/mcp-agent-mail"
        self.assertTrue(server_link.is_symlink())
        server_link.rename(self.base / "server-command-link-before-repair")
        result = self.agent_mail(before=REAL_AGENT_MAIL_COMMAND_LINKS)
        self.assertIn("COUNTS=0,1,0,0", result.stdout)
        self.assertEqual(server_link.readlink(), self.server)
        self.assertEqual(self.events().count("installer-download"), 1)
        self.assertEqual(self.events().count("install"), 1)
        self.assertEqual(self.events().count("reconcile-service"), 2)
        self.assertNotIn("restart-service", self.events())

    def test_changed_command_links_are_repaired_in_both_bin_directories_on_no_op(self):
        configured = self.home / "operator command bin"
        self.agent_mail(before=REAL_AGENT_MAIL_COMMAND_LINKS, ACFS_BIN_DIR=str(configured))
        for index, directory in enumerate((configured, self.home / ".local/bin")):
            for name in ("am", "mcp-agent-mail"):
                link = directory / name
                link.rename(self.base / f"previous-link-{index}-{name}")
                # Cover an existing wrong target and a dangling target.
                link.symlink_to(self.server if name == "am" else self.base / "absent-command")
        result = self.agent_mail(before=REAL_AGENT_MAIL_COMMAND_LINKS, ACFS_BIN_DIR=str(configured))
        self.assertIn("COUNTS=0,1,0,0", result.stdout)
        for directory in (configured, self.home / ".local/bin"):
            for name in ("am", "mcp-agent-mail"):
                self.assertEqual((directory / name).readlink(), self.install / name)
        self.assertEqual(self.events().count("installer-download"), 1)
        self.assertEqual(self.events().count("install"), 1)
        self.assertNotIn("restart-service", self.events())

    def test_blocked_server_command_link_reports_failure_before_service_reconciliation(self):
        self.agent_mail(before=REAL_AGENT_MAIL_COMMAND_LINKS)
        server_link = self.home / ".local/bin/mcp-agent-mail"
        server_link.rename(self.base / "server-command-link-before-obstruction")
        server_link.mkdir()
        sentinel = server_link / "operator-data"
        sentinel.write_text("preserve this directory\n")
        result = self.agent_mail(before=REAL_AGENT_MAIL_COMMAND_LINKS)
        self.assertIn("COUNTS=0,0,1,0", result.stdout)
        self.assertIn("command link repair failed", result.stdout)
        self.assertIn("Unable to repair Agent Mail command link", result.stderr)
        self.assertEqual(sentinel.read_text(), "preserve this directory\n")
        self.assertFalse((server_link / "mcp-agent-mail").exists())
        self.assertEqual(self.events().count("installer-download"), 1)
        self.assertEqual(self.events().count("install"), 1)
        self.assertEqual(self.events().count("reconcile-service"), 1)
        self.assertNotIn("restart-service", self.events())
        # Once the obstruction is removed, the same verified payload can be
        # reconciled successfully without another archive or installer fetch.
        server_link.rename(self.base / "preserved-obstructing-directory")
        recovered = self.agent_mail(before=REAL_AGENT_MAIL_COMMAND_LINKS)
        self.assertIn("COUNTS=0,1,0,0", recovered.stdout)
        self.assertEqual(server_link.readlink(), self.server)
        self.assertEqual(self.events().count("install"), 1)
        self.assertEqual(self.events().count("reconcile-service"), 2)


if __name__ == "__main__":
    unittest.main()
