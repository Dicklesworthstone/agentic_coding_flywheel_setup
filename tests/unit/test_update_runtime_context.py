"""Exercise runtime updates with real account transitions and inert executables.

The complete updater, binary lookup, target runner, timeout, logging and failure
accounting are real. Only passwd home metadata points at isolated fixture homes;
no account, package, toolchain or network service is changed. A transport fixture
can hide sudo to exercise the real runuser fallback. All artifacts are retained.
"""
import json
import os
from pathlib import Path
import pwd
import select
import shlex
import shutil
import signal
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(os.environ.get("ACFS_UPDATE_TEST_LIBRARY", ROOT / "scripts/lib/update.sh"))


def snapshot_update_runtime(directory, update_source):
    """Keep the actual updater and its bootstrap dependencies together."""
    for relative in ("scripts", "scripts/lib", "scripts/generated"):
        path = directory / relative
        path.mkdir()
        path.chmod(0o755)
    sources = {
        "scripts/lib/update.sh": update_source,
        "scripts/lib/state.sh": (ROOT / "scripts/lib/state.sh").read_text(),
        "scripts/lib/progress.sh": (ROOT / "scripts/lib/progress.sh").read_text(),
        "scripts/lib/security.sh": (ROOT / "scripts/lib/security.sh").read_text(),
        "scripts/lib/holds.sh": (ROOT / "scripts/lib/holds.sh").read_text(),
        "scripts/generated/manifest_index.sh":
            (ROOT / "scripts/generated/manifest_index.sh").read_text(),
    }
    for relative, content in sources.items():
        path = directory / relative
        path.write_text(content)
        path.chmod(0o444)
    return directory / "scripts/lib/update.sh"


MAINTENANCE_ENV_NAMES = (
    "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_RUNTIME_DIR",
    "GH_CONFIG_DIR", "GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN", "GH_HOST",
    "CLOUDSDK_CONFIG", "CLOUDSDK_ACTIVE_CONFIG_NAME", "CLOUDSDK_CORE_ACCOUNT", "CLOUDSDK_AUTH_ACCESS_TOKEN",
    "CLOUDSDK_AUTH_ACCESS_TOKEN_FILE", "CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE",
    "CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT", "CLOUDSDK_PYTHON",
    "ZSH", "ZSH_CUSTOM", "ZDOTDIR", "ZSH_CACHE_DIR", "ZSH_COMPDUMP", "DISABLE_UPDATE_PROMPT",
    "ACFS_TARGET_USER", "ACFS_TARGET_HOME", "CLAUDE_CONFIG_DIR",
    "GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_CONFIG", "GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM",
    "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT", "GIT_ASKPASS", "GIT_SSH", "GIT_SSH_COMMAND",
)

UPDATE_ACCOUNT_ENV_NAMES = (
    "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_RUNTIME_DIR",
    "BUN_INSTALL_GLOBAL_DIR", "BUN_INSTALL_BIN", "BUN_INSTALL_CACHE_DIR",
    "CLAUDE_CONFIG_DIR", "CODEX_HOME", "DATABASE_URL", "STORAGE_ROOT",
)

COMMON = r'''
set -euo pipefail
source "$UPDATE_TEST_LIBRARY"
UPDATE_RUNTIME=true
QUIET=true VERBOSE=false DRY_RUN="$TEST_DRY_RUN"
ABORT_ON_FAILURE="$TEST_ABORT"
UPDATE_LOG_FILE="$TEST_ROOT/update.log"
UPDATE_CMD_TIMEOUT="$TEST_TIMEOUT"
ACFS_UPDATE_RETRY_SLEEP_SECONDS=0
ACFS_UPDATE_RETRY_MAX_ATTEMPTS=3
update_getent_passwd_entry() {
    [[ "$1" == "$TEST_USER" ]] || return 1
    printf '%s:x:%s:%s:Runtime fixture:%s:/bin/bash\n' \
        "$TEST_USER" "$TEST_UID" "$TEST_GID" "$TEST_HOME"
}
# Keep run_cmd's captures; never remove a fixture or source artifact.
rm() { :; }
if [[ "$TEST_TRANSPORT" == runuser || "$TEST_TRANSPORT" == none || "$TEST_TRANSPORT" == usage ]]; then
    # Select the real runuser fallback, or model unavailable account transport.
    # env, timeout and every remaining executable still use trusted paths.
    update_system_binary_path() {
        if [[ "$1" == sudo || "$1" == runuser ]]; then
            if [[ "$TEST_TRANSPORT" == usage ]]; then
                printf '%s\n' "$TEST_ROOT/transport-usage"
                return 0
            fi
            [[ "$1" != sudo && "$TEST_TRANSPORT" != none ]] || return 1
        fi
        local candidate
        for candidate in "/usr/bin/$1" "/bin/$1" "/usr/sbin/$1" "/sbin/$1"; do
            [[ -x "$candidate" ]] || continue
            printf '%s\n' "$candidate"
            return 0
        done
        return 1
    }
fi
'''


class RustRuntimeContextTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.name != "posix" or not Path("/proc/self").is_dir():
            raise unittest.SkipTest("requires Linux and Bash")
        if os.geteuid() == 0:
            try:
                cls.account = pwd.getpwnam("nobody")
            except KeyError:
                raise unittest.SkipTest("root fixture requires an existing nobody account")
        else:
            cls.account = pwd.getpwuid(os.geteuid())
        cls.source = SOURCE.read_text()
        cls.artifacts = Path(tempfile.mkdtemp(prefix="acfs-runtime-context-",
                                             dir=os.environ.get("ACFS_RUNTIME_TEST_ARTIFACTS_DIR")))
        cls.artifacts.chmod(0o755)
        # One immutable source snapshot per run keeps the real-account suite
        # practical on small/full disks without changing individual controls.
        cls.library = snapshot_update_runtime(cls.artifacts, cls.source)
        print("Runtime context artifacts:", cls.artifacts, flush=True)

    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="case-", dir=self.artifacts))
        self.base.chmod(0o755)
        self.home = self.base / "target-home"
        self.caller = self.base / "caller-home"
        self.work = self.base / "working directory"
        self.tmp = self.base / "tmp"
        for path in (self.home, self.caller, self.work, self.tmp):
            self.owned_dir(path)
        self.events_file = self.base / "events.tsv"
        self.events_file.write_text("")
        (self.base / "update.log").write_text("")
        self.own(self.events_file)
        self.own(self.base / "update.log")
        self.rust_home = self.home / ".rustup"
        self.cargo_home = self.home / ".cargo"
        self.prepare_rust_homes(self.rust_home, self.cargo_home)
        self.write_tools(self.cargo_home / "bin", "default")

    def own(self, path):
        if os.geteuid() == 0:
            os.chown(path, self.account.pw_uid, self.account.pw_gid)

    def owned_dir(self, path):
        # Root's umask must not make intermediate fixture directories
        # inaccessible to the account that actually executes the tools.
        created = []
        ancestor = path
        while not ancestor.exists():
            created.append(ancestor)
            ancestor = ancestor.parent
        path.mkdir(parents=True, exist_ok=True)
        for directory in created:
            directory.chmod(0o755)
            self.own(directory)
        path.chmod(0o755)
        self.own(path)

    def write_input(self, path, content):
        path.write_text(content)
        self.own(path)

    def prepare_rust_homes(self, rust_home, cargo_home, *, nightly=True):
        self.owned_dir(rust_home)
        self.owned_dir(cargo_home)
        listing = "stable-x86_64-unknown-linux-gnu (default)\n"
        if nightly:
            listing += "nightly-x86_64-unknown-linux-gnu\n"
        self.write_input(rust_home / "toolchains.txt", listing)

    def write_tools(self, directory, origin):
        self.owned_dir(directory)
        for tool in ("rustup", "rustc", "cargo"):
            script = "#!/bin/bash\nset -euo pipefail\n"
            script += "fixture=" + shlex.quote(str(self.base)) + "\n"
            script += "tool=" + shlex.quote(tool) + "\norigin=" + shlex.quote(origin) + "\n"
            script += r'''
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$tool" "$EUID" "$HOME" "$PWD" "${RUSTUP_HOME-<unset>}" \
    "${CARGO_HOME-<unset>}" "${RUSTUP_TOOLCHAIN-<unset>}" \
    "${RUSTUP_AUTO_INSTALL-<unset>}" "$origin" "$*" >> "$fixture/events.tsv"
rust_home="${RUSTUP_HOME:-$HOME/.rustup}"
cargo_home="${CARGO_HOME:-$HOME/.cargo}"
case "$tool:$*" in
    'rustup:toolchain list')
        [[ ! -f "$rust_home/toolchains.txt" ]] || cat "$rust_home/toolchains.txt"
        ;;
    'rustup:update stable'|'rustup:update nightly')
        if [[ "$2" == stable && -f "$fixture/hang-stable" ]]; then /bin/sleep 5; fi
        mkdir -p "$rust_home"
        printf '%s\n' "$EUID" > "$rust_home/updated-$2"
        if [[ "$2" == stable && -f "$fixture/fail-stable" ]]; then exit 17; fi
        ;;
    'rustup:self update')
        mkdir -p "$cargo_home"
        printf '%s\n' "$EUID" > "$cargo_home/self-update"
        ;;
    'rustc:--version')
        if [[ "${RUSTUP_AUTO_INSTALL:-1}" != 0 ]]; then
            mkdir -p "$rust_home"
            printf 'an unguarded version probe could auto-install\n' > "$rust_home/probe-auto-install"
        fi
        printf 'rustc 1.95.0-fixture\n'
        ;;
    cargo:install*)
        mkdir -p "$cargo_home"
        printf '%s\n' "$EUID" > "$cargo_home/cargo-install"
        ;;
    *) exit 64 ;;
esac
'''
            path = directory / tool
            path.write_text(script)
            path.chmod(0o755)
            self.own(path)

    def run_update(self, *, cross=False, overrides=None, command="update_rust",
                   transport="default", dry_run=False, abort=False, timeout="5", expected=0):
        if cross:
            if os.geteuid() != 0:
                self.skipTest("cross-account execution requires root")
            if not shutil.which("runuser") and not shutil.which("sudo"):
                self.skipTest("cross-account execution requires sudo or runuser")
        env = {
            "HOME": str(self.caller if cross else self.home), "PATH": "/usr/bin:/bin",
            "TARGET_USER": self.account.pw_name, "TARGET_HOME": str(self.home),
            "UPDATE_TEST_LIBRARY": str(self.library), "TEST_ROOT": str(self.base),
            "TEST_USER": self.account.pw_name, "TEST_UID": str(self.account.pw_uid),
            "TEST_GID": str(self.account.pw_gid), "TEST_HOME": str(self.home),
            "TEST_DRY_RUN": str(dry_run).lower(), "TEST_ABORT": str(abort).lower(),
            "TEST_TIMEOUT": timeout, "TEST_TRANSPORT": transport,
            "TMPDIR": str(self.tmp), "NO_COLOR": "1", "ACFS_INTERACTIVE": "false",
        }
        env.update(overrides or {})
        body = COMMON + "\n" + command + r'''
printf 'COUNTS=%s,%s,%s\n' "$SUCCESS_COUNT" "$SKIP_COUNT" "$FAIL_COUNT"
'''
        kwargs = {}
        if not cross and os.geteuid() == 0:
            kwargs.update(user=self.account.pw_uid, group=self.account.pw_gid, extra_groups=[])
        result = subprocess.run(["/bin/bash", "--noprofile", "--norc", "-c", body],
                                env=env, cwd=self.work, text=True, capture_output=True,
                                timeout=20, **kwargs)
        (self.base / "stdout").write_text(result.stdout)
        (self.base / "stderr").write_text(result.stderr)
        (self.base / "exit").write_text(str(result.returncode) + "\n")
        self.assertEqual(result.returncode, expected,
                         result.stdout + result.stderr + "\nArtifacts: " + str(self.base))
        return result.stdout + result.stderr

    def events(self):
        return [line.split("\t") for line in self.events_file.read_text().splitlines()]

    def assert_target_events(self, events):
        self.assertTrue(events, "no runtime fixture executed: " + str(self.base))
        for event in events:
            self.assertEqual(event[1:4], [str(self.account.pw_uid), str(self.home), str(self.home)], event)

    def test_cross_account_probes_and_mutations_use_target_home(self):
        output = self.run_update(cross=True)
        events = self.events()
        self.assert_target_events(events)
        self.assertEqual([e[-1] for e in events], ["--version", "update stable", "toolchain list",
                                                 "update nightly", "self update", "--version", "toolchain list"])
        self.assertIn("COUNTS=3,0,0", output)
        for path in (self.rust_home / "updated-stable", self.rust_home / "updated-nightly",
                     self.cargo_home / "self-update"):
            self.assertEqual(path.stat().st_uid, self.account.pw_uid)
        self.assertEqual(list(self.caller.iterdir()), [])

    def root_transport_fixture(self):
        if os.geteuid() != 0:
            self.skipTest("root transport selection requires root")
        sentinel = self.base / "unexpected-sudo"
        sentinel.write_text('#!/bin/sh\nprintf invoked > "$TEST_ROOT/sudo-invoked"\nexit 97\n')
        sentinel.chmod(0o755)
        return r'''
update_system_binary_path() {
    if [[ "$1" == sudo ]]; then
        printf '%s\n' "$TEST_ROOT/unexpected-sudo"
        return 0
    fi
    local candidate
    for candidate in "/usr/bin/$1" "/bin/$1" "/usr/sbin/$1" "/sbin/$1"; do
        if [[ -x "$candidate" ]]; then printf '%s\n' "$candidate"; return 0; fi
    done
    return 1
}
update_rust
'''

    def test_root_prefers_runuser_even_when_sudo_is_available(self):
        self.run_update(cross=True, command=self.root_transport_fixture())
        self.assert_target_events(self.events())
        self.assertFalse((self.base / "sudo-invoked").exists())
        self.assertTrue((self.rust_home / "updated-stable").is_file())

    def test_failed_root_command_is_not_replayed_through_sudo(self):
        (self.base / "fail-stable").write_text("fail once\n")
        self.run_update(cross=True, command=self.root_transport_fixture(), abort=True, expected=1)
        self.assert_target_events(self.events())
        self.assertEqual(sum(e[-1] == "update stable" for e in self.events()), 1)
        self.assertFalse((self.base / "sudo-invoked").exists())

    def test_cross_account_discards_caller_rust_homes_and_toolchain(self):
        foreign_rust = self.caller / "foreign-rust"
        foreign_cargo = self.caller / "foreign-cargo"
        self.prepare_rust_homes(foreign_rust, foreign_cargo, nightly=False)
        self.write_tools(foreign_cargo / "bin", "foreign")
        output = self.run_update(cross=True, transport="runuser", overrides={
            "RUSTUP_HOME": str(foreign_rust), "CARGO_HOME": str(foreign_cargo),
            "RUSTUP_TOOLCHAIN": "foreign-override", "RUSTUP_AUTO_INSTALL": "1",
        })
        events = self.events()
        self.assert_target_events(events)
        for event in events:
            self.assertEqual(event[4:7], ["<unset>"] * 3, event)
            self.assertEqual(event[8], "default", event)
        self.assertIn("COUNTS=3,0,0", output)
        self.assertEqual(sorted(p.name for p in foreign_rust.iterdir()), ["toolchains.txt"])
        self.assertEqual(sorted(p.name for p in foreign_cargo.iterdir()), ["bin"])

    def test_same_account_preserves_absolute_custom_homes_and_binary_selection(self):
        rust_home, cargo_home = self.work / "custom rust", self.work / "custom cargo"
        self.prepare_rust_homes(rust_home, cargo_home)
        self.write_tools(cargo_home / "bin", "custom")
        self.run_update(overrides={"RUSTUP_HOME": str(rust_home), "CARGO_HOME": str(cargo_home),
                                   "RUSTUP_TOOLCHAIN": "owner-override"})
        self.assert_target_events(self.events())
        for event in self.events():
            self.assertEqual(event[4:7], [str(rust_home), str(cargo_home), "owner-override"], event)
            self.assertEqual(event[8], "custom", event)
        self.assertTrue((rust_home / "updated-nightly").is_file())
        self.assertTrue((cargo_home / "self-update").is_file())
        self.assertFalse((self.rust_home / "updated-stable").exists())

    def test_same_account_relative_homes_keep_original_working_directory_meaning(self):
        rust_home, cargo_home = self.work / "relative rust", self.work / "relative cargo"
        self.prepare_rust_homes(rust_home, cargo_home)
        self.write_tools(cargo_home / "bin", "relative")
        self.run_update(overrides={"RUSTUP_HOME": "relative rust", "CARGO_HOME": "relative cargo",
                                   "RUSTUP_TOOLCHAIN": "owner-override"})
        for event in self.events():
            self.assertEqual(event[4:7], [str(rust_home), str(cargo_home), "owner-override"], event)
            self.assertEqual(event[8], "relative", event)
        self.assertTrue((cargo_home / "self-update").is_file())
        self.assertFalse((self.home / "relative rust").exists())
        self.assertFalse((self.home / "relative cargo").exists())

    def run_wrapper_rust_update(self, *, cross=False, overrides=None):
        if cross:
            if os.geteuid() != 0 or not shutil.which("runuser"):
                self.skipTest("public wrapper cross-account regression requires root and runuser")
        acfs_home = self.home / ".acfs"
        self.owned_dir(acfs_home / "bin")
        self.owned_dir(acfs_home / "scripts/lib")
        self.write_input(acfs_home / "state.json", json.dumps({
            "schema_version": 3, "target_user": self.account.pw_name,
            "target_home": str(self.home),
            "module_selection": {"schema_version": 1, "selected_modules": ["lang.rust"]},
        }))
        # The complete public wrapper performs owner detection and the real
        # account handoff. Its deployed entrypoint invokes the actual Rust
        # updater against inert tools; no self-update or other category runs.
        bindings = {
            "UPDATE_TEST_LIBRARY": str(self.library), "TEST_ROOT": str(self.base),
            "TEST_USER": self.account.pw_name, "TEST_UID": str(self.account.pw_uid),
            "TEST_GID": str(self.account.pw_gid), "TEST_HOME": str(self.home),
            "TARGET_USER": self.account.pw_name, "TARGET_HOME": str(self.home),
            "TEST_DRY_RUN": "false", "TEST_ABORT": "false",
            "TEST_TIMEOUT": "5", "TEST_TRANSPORT": "default",
        }
        entrypoint = acfs_home / "scripts/lib/update.sh"
        prefix = "#!/bin/bash\n" + "\n".join(
            f"export {name}={shlex.quote(value)}" for name, value in bindings.items()) + "\n"
        self.write_input(entrypoint, prefix + COMMON + r'''
update_rust
printf 'COUNTS=%s,%s,%s\n' "$SUCCESS_COUNT" "$SKIP_COUNT" "$FAIL_COUNT"
''')
        entrypoint.chmod(0o755)
        wrapper = acfs_home / "bin/acfs-update"
        self.write_input(wrapper, Path(os.environ.get(
            "ACFS_UPDATE_TEST_WRAPPER", ROOT / "scripts/acfs-update")).read_text())
        wrapper.chmod(0o755)
        env = {
            "PATH": "/usr/bin:/bin", "HOME": str(self.caller if cross else self.home),
            "TARGET_USER": self.account.pw_name, "TARGET_HOME": str(self.home),
            "ACFS_SYSTEM_STATE_FILE": str(self.base / "absent-system-state.json"),
            "TMPDIR": str(self.tmp), "NO_COLOR": "1", "ACFS_INTERACTIVE": "false",
        }
        env.update(overrides or {})
        kwargs = {}
        if not cross and os.geteuid() == 0:
            kwargs.update(user=self.account.pw_uid, group=self.account.pw_gid, extra_groups=[])
        result = subprocess.run(
            ["/bin/bash", "--noprofile", "--norc", str(wrapper)],
            env=env, cwd=self.work, text=True, capture_output=True, timeout=25, **kwargs,
        )
        (self.base / "wrapper-stdout").write_text(result.stdout)
        (self.base / "wrapper-stderr").write_text(result.stderr)
        self.assertEqual(result.returncode, 0,
                         result.stdout + result.stderr + "\nArtifacts: " + str(self.base))
        return result.stdout + result.stderr

    def test_public_wrapper_discards_foreign_rust_homes_before_account_handoff(self):
        foreign_rust = self.caller / "foreign-rust"
        foreign_cargo = self.caller / "foreign-cargo"
        self.prepare_rust_homes(foreign_rust, foreign_cargo, nightly=False)
        self.write_tools(foreign_cargo / "bin", "foreign")
        output = self.run_wrapper_rust_update(cross=True, overrides={
            "RUSTUP_HOME": str(foreign_rust), "CARGO_HOME": str(foreign_cargo),
            "RUSTUP_TOOLCHAIN": "foreign-override",
        })
        self.assertIn("COUNTS=3,0,0", output)
        self.assert_target_events(self.events())
        for event in self.events():
            self.assertEqual(event[4:7], ["<unset>"] * 3, event)
            self.assertEqual(event[8], "default", event)
        self.assertEqual(sorted(p.name for p in foreign_rust.iterdir()), ["toolchains.txt"])
        self.assertEqual(sorted(p.name for p in foreign_cargo.iterdir()), ["bin"])
        self.assertTrue((self.rust_home / "updated-nightly").is_file())

    def test_public_wrapper_preserves_same_account_rust_overrides(self):
        rust_home, cargo_home = self.work / "owner rust", self.work / "owner cargo"
        self.prepare_rust_homes(rust_home, cargo_home)
        self.write_tools(cargo_home / "bin", "owner")
        output = self.run_wrapper_rust_update(overrides={
            "RUSTUP_HOME": str(rust_home), "CARGO_HOME": str(cargo_home),
            "RUSTUP_TOOLCHAIN": "owner-override",
        })
        self.assertIn("COUNTS=3,0,0", output)
        self.assert_target_events(self.events())
        for event in self.events():
            self.assertEqual(event[4:7], [str(rust_home), str(cargo_home), "owner-override"], event)
            self.assertEqual(event[8], "owner", event)
        self.assertTrue((cargo_home / "self-update").is_file())
        self.assertFalse((self.cargo_home / "self-update").exists())

    def test_version_probe_is_targeted_and_cannot_auto_install(self):
        output = self.run_update(cross=True, command="get_version rust",
                                 overrides={"RUSTUP_AUTO_INSTALL": "1"})
        self.assertIn("1.95.0-fixture", output)
        self.assert_target_events(self.events())
        self.assertEqual(len(self.events()), 1)
        self.assertEqual(self.events()[0][7], "0")
        self.assertFalse((self.rust_home / "probe-auto-install").exists())
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_missing_account_transport_never_falls_back_to_caller_for_rust(self):
        self.run_update(cross=True, transport="none", expected=1)
        self.assertEqual(self.events(), [])
        self.assertEqual(list(self.caller.iterdir()), [])
        self.assertFalse((self.rust_home / "updated-stable").exists())
        self.assertFalse((self.cargo_home / "self-update").exists())
        log = (self.base / "update.log").read_text()
        self.assertIn("Cannot switch to target user", log)
        self.assertIn("Failed: Rust stable (exit code: 1)", log)
        self.assertIn("Failed: rustup self-update (exit code: 1)", log)

    def test_missing_account_transport_never_falls_back_to_caller_for_cargo(self):
        output = self.run_update(cross=True, transport="none",
                                 command='update_binary_exists() { [[ "$1" == sg ]]; }; update_cargo_tools')
        self.assertIn("COUNTS=0,0,1", output)
        self.assertEqual(self.events(), [])
        self.assertEqual(list(self.caller.iterdir()), [])
        self.assertFalse((self.cargo_home / "cargo-install").exists())

    def test_unresolvable_target_home_is_unknown_and_skipped_without_execution(self):
        output = self.run_update(cross=True, overrides={"TEST_HOME": str(self.base / "absent-home")},
                                 command="get_version rust; update_rust; update_cargo_tools")
        self.assertTrue(output.startswith("unknown\n"), output)
        self.assertIn("COUNTS=0,2,0", output)
        self.assertEqual(self.events(), [])
        self.assertEqual(list(self.caller.iterdir()), [])
        self.assertFalse((self.base / "absent-home").exists())

    def test_dry_run_only_probes_and_does_not_auto_install(self):
        output = self.run_update(dry_run=True, overrides={"RUSTUP_AUTO_INSTALL": "1"})
        self.assertIn("COUNTS=0,3,0", output)
        self.assertEqual([e[-1] for e in self.events()], ["--version", "toolchain list", "--version", "toolchain list"])
        self.assertFalse((self.rust_home / "probe-auto-install").exists())
        self.assertFalse((self.rust_home / "updated-stable").exists())
        self.assertFalse((self.cargo_home / "self-update").exists())

    def test_nightly_is_updated_only_when_target_has_it(self):
        self.write_input(self.rust_home / "toolchains.txt", "stable-x86_64-unknown-linux-gnu (default)\n")
        output = self.run_update()
        self.assertIn("COUNTS=2,0,0", output)
        self.assertNotIn("update nightly", [e[-1] for e in self.events()])

    def test_native_failure_is_counted_and_other_updates_continue(self):
        (self.base / "fail-stable").write_text("fixture\n")
        output = self.run_update()
        self.assertIn("COUNTS=2,0,1", output)
        self.assertIn("exit code: 17", (self.base / "update.log").read_text())
        self.assertTrue((self.cargo_home / "self-update").is_file())

    def test_abort_on_native_failure_stops_before_nightly_or_self_update(self):
        (self.base / "fail-stable").write_text("fixture\n")
        output = self.run_update(abort=True, expected=1)
        self.assertIn("Aborting due to failure", output)
        self.assertEqual([e[-1] for e in self.events()], ["--version", "update stable"])

    def test_wrapped_native_update_keeps_command_timeout(self):
        (self.base / "hang-stable").write_text("fixture\n")
        output = self.run_update(timeout="0.5")
        self.assertIn("COUNTS=2,0,1", output)
        self.assertIn("exit code: 124", (self.base / "update.log").read_text())
        self.assertFalse((self.rust_home / "updated-stable").exists())

    def test_cargo_update_uses_target_stores_despite_caller_overrides(self):
        foreign_rust, foreign_cargo = self.caller / "foreign-rust", self.caller / "foreign-cargo"
        self.prepare_rust_homes(foreign_rust, foreign_cargo)
        sg = self.cargo_home / "bin/sg"
        sg.write_text("#!/bin/sh\nprintf 'ast-grep 0.0.0-fixture\\n'\n")
        sg.chmod(0o755)
        output = self.run_update(cross=True, transport="runuser",
                                 command='update_binary_exists() { [[ "$1" == sg ]]; }; update_cargo_tools',
                                 overrides={"RUSTUP_HOME": str(foreign_rust), "CARGO_HOME": str(foreign_cargo),
                                            "RUSTUP_TOOLCHAIN": "foreign-override"})
        self.assertIn("COUNTS=1,0,0", output)
        self.assert_target_events(self.events())
        self.assertEqual(len(self.events()), 1)
        self.assertEqual(self.events()[0][4:7], ["<unset>"] * 3)
        self.assertEqual(self.events()[0][-1], "install ast-grep --locked --force")
        self.assertTrue((self.cargo_home / "cargo-install").is_file())
        self.assertFalse((foreign_cargo / "cargo-install").exists())

    def write_native_tool(self, tool, *, directory=None, origin="native"):
        directory = directory or self.home / ".local/bin"
        self.owned_dir(directory)
        script = "#!/bin/bash\nset -euo pipefail\n"
        script += "fixture=" + shlex.quote(str(self.base)) + "\n"
        script += "tool=" + shlex.quote(tool) + "\norigin=" + shlex.quote(origin) + "\n"
        script += r'''
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$tool" "$EUID" "$HOME" "$PWD" "${RUSTUP_HOME-<unset>}" \
    "${CARGO_HOME-<unset>}" "${RUSTUP_TOOLCHAIN-<unset>}" \
    "${RUSTUP_AUTO_INSTALL-<unset>}" "$origin" "$*" >> "$fixture/events.tsv"
if [[ -f "$fixture/unsupported-probe-$tool" ]]; then
    printf 'Usage: %s OTHER (unknown option)\n' "$tool" >&2
    exit 2
fi
case "$*" in
    --version|version)
        if [[ -f "$fixture/hang-probe-$tool" ]]; then /bin/sleep 5; fi
        if [[ -f "$fixture/read-stdin-$tool" ]] && IFS= read -r line; then
            printf '%s\n' "$line" > "$HOME/probe-read-stdin"
            exit 65
        fi
        if [[ "$tool" == bun ]]; then printf '1.2.3-fixture\nbun metadata\n'
        else printf '%s 1.2.3-fixture\nextra metadata\n' "$tool"; fi
        [[ ! -f "$fixture/version-tail-$tool" ]] || cat "$fixture/version-tail-$tool"
        exit 0
        ;;
    --help)
        if [[ -f "$fixture/no-atuin-self-update" ]]; then printf 'ordinary commands\n'
        else printf 'self-update\n'; fi
        [[ ! -f "$fixture/help-tail-$tool" ]] || cat "$fixture/help-tail-$tool"
        exit 0
        ;;
esac
case "$tool:$*" in
    bun:upgrade|bun:'install -g --trust '*|uv:'self update'|atuin:self-update|atuin-update:|agy:update|agy-real:update|omp:update|opencode:upgrade)
        attempt_file="$HOME/$tool-native-attempts"
        attempt=0
        [[ ! -f "$attempt_file" ]] || read -r attempt < "$attempt_file"
        attempt=$((attempt + 1))
        printf '%s\n' "$attempt" > "$attempt_file"
        mode=success
        [[ ! -f "$fixture/mode-$tool" ]] || read -r mode < "$fixture/mode-$tool"
        case "$mode" in
            failure) printf 'permanent fixture failure\n' >&2; exit 17 ;;
            transient)
                if [[ "$attempt" -eq 1 ]]; then printf 'curl: (7) Connection refused\n' >&2; exit 7; fi
                ;;
            hang) /bin/sleep 5 ;;
            broken-payload)
                cp -- "$0" "$0.fixture-before-update"
                printf '#!/bin/bash\nprintf "broken native replacement\\n" >&2\nexit 42\n' > "$0"
                ;;
            empty-payload)
                cp -- "$0" "$0.fixture-before-update"
                printf '#!/bin/bash\nexit 0\n' > "$0"
                ;;
            missing-payload) mv -- "$0" "$0.fixture-before-update" ;;
            unexecutable-payload) chmod 0644 "$0" ;;
            hung-payload)
                cp -- "$0" "$0.fixture-before-update"
                printf '#!/bin/bash\n/bin/sleep 5\n' > "$0"
                ;;
        esac
        printf '%s\n' "$EUID" > "$HOME/$tool-native-installed"
        ;;
    *) exit 64 ;;
esac
'''
        path = directory / tool
        path.write_text(script)
        path.chmod(0o755)
        self.own(path)
        return path

    def test_all_executable_version_branches_use_target_account_and_keep_arguments(self):
        if os.geteuid() != 0:
            self.skipTest("cross-account execution requires root")
        generic_tools = (
            "claude", "codex", "agy", "gemini", "opencode", "omp", "grok", "wrangler", "supabase", "vercel",
            "ubs", "bv", "cass", "cm", "caam", "slb", "ru", "dcg", "apr", "pt", "xf", "jfp", "ms", "br",
            "rch", "giil", "csctf", "srps", "tru", "rano", "mdwb", "s2p", "brenner", "fsfs", "sbh", "casr",
            "dsr", "asb", "aadc", "rust_proxy", "ee", "fmd", "pi", "sg", "lsd", "dust", "tldr",
        )
        special = {"bun": "bun", "uv": "uv", "atuin": "atuin", "zoxide": "zoxide",
                   "ntm": "ntm", "pcr": "claude-post-compact-reminder", "pfr": "pfr"}
        for tool in (*generic_tools, *special.values()):
            self.write_native_tool(tool)
        self.write_input(self.base / "version-tail-claude", "version metadata\n" * 8192)
        names = (*generic_tools, *special)
        outputs = []
        # Each executable keeps the same 20-second subprocess deadline. A
        # batch of independent probes must not consume one probe's budget.
        for name in names:
            with self.subTest(tool=name):
                command = "printf 'VERSION %s=[%s]\\n' " + shlex.quote(name) + \
                          ' "$(get_version ' + shlex.quote(name) + ')"'
                try:
                    outputs.append(self.run_update(cross=True, command=command))
                finally:
                    for channel in ("stdout", "stderr", "exit"):
                        artifact = self.base / channel
                        if artifact.exists():
                            artifact.rename(self.base / f"{name}.{channel}")
        output = "\n".join(outputs)
        self.assert_target_events(self.events())
        expected = [(name, "--version") for name in generic_tools]
        expected += [(binary, "version" if name == "ntm" else "--version")
                     for name, binary in special.items() if name != "pfr"]
        self.assertEqual([(e[0], e[-1]) for e in self.events()], expected)
        for tool in generic_tools:
            self.assertIn(f"VERSION {tool}=[{tool} 1.2.3-fixture]", output)
        self.assertIn("VERSION bun=[1.2.3-fixture\nbun metadata]", output)
        for tool in ("uv", "atuin", "zoxide"):
            self.assertIn(f"VERSION {tool}=[1.2.3-fixture\nmetadata]", output)
        self.assertIn("VERSION pcr=[claude-post-compact-reminder 1.2.3-fixture]", output)
        self.assertIn("VERSION ntm=[ntm 1.2.3-fixture]", output)
        self.assertIn("VERSION pfr=[installed]", output)

    def test_version_from_explicit_path_uses_target_account(self):
        binary = self.write_native_tool("fixture-native")
        output = self.run_update(cross=True, command="update_tool_version_from_path fixture " + shlex.quote(str(binary)))
        self.assert_target_events(self.events())
        self.assertIn("fixture-native 1.2.3-fixture", output)
        self.assertEqual([e[-1] for e in self.events()], ["--version"])

    def test_version_probe_keeps_its_native_command_deadline(self):
        self.write_native_tool("bun")
        (self.base / "hang-probe-bun").write_text("fixture\n")
        output = self.run_update(cross=True, command="get_version bun", timeout="0.1")
        self.assert_target_events(self.events())
        self.assertEqual(len(self.events()), 1)
        self.assertIn("unknown", output)
        self.assertEqual([e[-1] for e in self.events()], ["--version"])

    def test_native_bun_upgrade_runs_as_target_and_preserves_failure_accounting(self):
        self.write_native_tool("bun")
        self.write_input(self.base / "mode-bun", "failure\n")
        output = self.run_update(cross=True, command="update_bun")
        self.assert_target_events(self.events())
        self.assertEqual([e[-1] for e in self.events()], ["--version", "upgrade", "--version"])
        self.assertIn("COUNTS=0,0,1", output)
        self.assertIn("exit code: 17", (self.base / "update.log").read_text())
        self.assertEqual(list(self.caller.iterdir()), [])

    def write_go_fixture(self, *, installed=True, package="golang-1.23-go:amd64"):
        """Replace package tools, retaining the real updater and account runner.

        The sudo fixture never elevates and only accepts the inert apt path.
        All mutable files belong to the target, including when Python is root.
        """
        self.go_state = self.home / "go-fixture"
        self.owned_dir(self.go_state / "package/bin")
        self.owned_dir(self.go_state / "tools")
        self.go_path = self.go_state / "go"
        self.go_resolved = self.go_state / "package/bin/go"
        for name, value in {
            "owner": package, "status": "install ok installed" if installed else "unknown",
            "meta-status": "unknown", "depends": "", "mode": "normal", "go-mode": "normal",
            "package-events.tsv": "",
        }.items():
            self.write_input(self.go_state / name, value + "\n" if value else "")
        prefix = "#!/bin/bash\nset -euo pipefail\nstate=" + shlex.quote(str(self.go_state)) + "\n"
        go_script = prefix + "events=" + shlex.quote(str(self.events_file)) + "\n" + r'''
printf 'go\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$EUID" "$HOME" "$PWD" "${GOTOOLCHAIN-<unset>}" "${GOENV-<unset>}" \
    "${GOWORK-<unset>}" "${GOROOT-<unset>}" "${GOPATH-<unset>}" "$*" >> "$events"
[[ "$*" == version ]] || exit 64
case "$(<"$state/go-mode")" in
    failure) printf 'fixture Go failure\n' >&2; exit 17 ;;
    timeout) /bin/sleep 5 ;;
    invalid) printf 'not a Go version\n'; exit 0 ;;
esac
printf 'go version go1.23.4 linux/amd64\n'
'''
        self.write_input(self.go_state / "go-payload", go_script)
        if installed:
            self.write_input(self.go_resolved, go_script)
            self.go_resolved.chmod(0o755)
            self.go_path.symlink_to(self.go_resolved)
        scripts = {
            "dpkg-query": r'''
printf 'dpkg-query' >> "$state/package-events.tsv"
printf '\t%s' "$@" >> "$state/package-events.tsv"
printf '\n' >> "$state/package-events.tsv"
owner="$(<"$state/owner")"
case "${1:-}" in
    -S)
        [[ $# == 2 && "$2" == "$state/package/bin/go" && -n "$owner" ]] || exit 1
        owned_path="$2"
        [[ "$(<"$state/mode")" != wrong-owner-path ]] || owned_path="$state/unrelated-go"
        printf '%s: %s\n' "$owner" "$owned_path"
        ;;
    -W)
        [[ $# == 3 ]] || exit 97
        case "$2:$3" in
            '-f=${Status}:golang-go') cat "$state/meta-status" ;;
            '-f=${Depends}:golang-go') cat "$state/depends" ;;
            *)
                [[ "$2" == '-f=${Status}' && ( "$3" == "$owner" || "$3" == "${owner%%:*}" ) ]] || exit 1
                cat "$state/status"
                ;;
        esac
        ;;
    *) exit 97 ;;
esac
''',
            "apt-get": r'''
printf 'apt-get\t%s\t%s\t%s\t%s' "$EUID" "${DEBIAN_FRONTEND-<unset>}" \
    "${NEEDRESTART_MODE-<unset>}" "${NEEDRESTART_SUSPEND-<unset>}" >> "$state/package-events.tsv"
printf '\t%s' "$@" >> "$state/package-events.tsv"
printf '\n' >> "$state/package-events.tsv"
operation=""
for argument in "$@"; do
    case "$argument" in update|install) operation="$argument" ;; esac
done
mode="$(<"$state/mode")"
case "$operation" in
    update)
        [[ "$mode" != update-failure ]] || { printf 'fixture metadata failure\n' >&2; exit 17; }
        ;;
    install)
        [[ "$mode" != install-failure ]] || { printf 'fixture package failure\n' >&2; exit 18; }
        [[ "$mode" != install-timeout ]] || /bin/sleep 5
        if [[ "$mode" == transient-install && ! -f "$state/retried-install" ]]; then
            printf 'attempted\n' > "$state/retried-install"
            printf 'Temporary failure resolving fixture.invalid\n' >&2
            exit 100
        fi
        [[ "$mode" != no-payload ]] || exit 0
        cp "$state/go-payload" "$state/package/bin/go"
        chmod 755 "$state/package/bin/go"
        [[ -L "$state/go" ]] || ln -s "$state/package/bin/go" "$state/go"
        printf 'install ok installed\n' > "$state/status"
        [[ "$mode" != broken-payload ]] || printf 'failure\n' > "$state/go-mode"
        ;;
    *) printf 'unexpected package operation\n' >&2; exit 97 ;;
esac
''',
            "sudo": r'''
printf 'sudo' >> "$state/package-events.tsv"
printf '\t%s' "$@" >> "$state/package-events.tsv"
printf '\n' >> "$state/package-events.tsv"
[[ "${1:-}" == -n ]] || exit 97
allowed=false
for argument in "$@"; do
    [[ "$argument" != "$state/tools/apt-get" ]] || allowed=true
done
[[ "$allowed" == true ]] || { printf 'refusing non-fixture sudo command\n' >&2; exit 97; }
shift
exec "$@"
''',
        }
        for name, script in scripts.items():
            path = self.go_state / "tools" / name
            self.write_input(path, prefix + script)
            path.chmod(0o755)

    def go_command(self, setup="", *, action="update_go"):
        return r'''
source "${UPDATE_TEST_LIBRARY%/*}/holds.sh"
ACFS_HOLDS_FILE="$TEST_HOME/.acfs/holds.yaml"
ACFS_DISTRO_FAMILY=ubuntu
update_binary_path() {
    [[ "$1" == go && -x "$TEST_HOME/go-fixture/go" ]] || return 1
    printf '%s\n' "$TEST_HOME/go-fixture/go"
}
update_system_binary_path() {
    case "$1" in
        apt-get|dpkg-query) printf '%s\n' "$TEST_HOME/go-fixture/tools/$1"; return 0 ;;
        sudo)
            [[ "$TEST_TRANSPORT" != runuser && "$(<"$TEST_HOME/go-fixture/mode")" != no-sudo ]] || return 1
            printf '%s\n' "$TEST_HOME/go-fixture/tools/sudo"; return 0 ;;
    esac
    local candidate
    for candidate in "/usr/bin/$1" "/bin/$1" "/usr/sbin/$1" "/sbin/$1"; do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done
    return 1
}
# Host needrestart configuration is outside this isolated package fixture.
update_disable_needrestart_apt_hook() { :; }
''' + setup + "\n" + action + "\n"

    def go_package_events(self):
        return [line.split("\t") for line in (self.go_state / "package-events.tsv").read_text().splitlines()]

    def go_apt_calls(self):
        return [event[5:] for event in self.go_package_events() if event[0] == "apt-get"]

    def assert_go_verified(self, output, *, count=1):
        self.assertIn(f"COUNTS={count},0,0", output)
        events = self.events()
        self.assertEqual(len(events), count)
        self.assert_target_events(events)
        for event in events:
            self.assertEqual(event[4:], ["local", "off", "off", "<unset>", "<unset>", "version"])

    def test_go_missing_force_installs_and_verifies_package(self):
        self.write_go_fixture(installed=False)
        output = self.run_update(command=self.go_command("FORCE_MODE=true UPDATE_APT=false"))
        self.assert_go_verified(output)
        calls = self.go_apt_calls()
        self.assertEqual(len(calls), 2)
        self.assertIn("update", calls[0])
        self.assertIn("APT::Update::Error-Mode=any", calls[0])
        self.assertEqual(calls[1][-4:], ["install", "-y", "--reinstall", "golang-go"])
        self.assertEqual(self.go_resolved.stat().st_uid, self.account.pw_uid)

    def test_go_absence_and_explicit_package_opt_out_do_not_install(self):
        self.write_go_fixture(installed=False)
        for setup in ("", "FORCE_MODE=true UPDATE_GO_PACKAGES=false"):
            with self.subTest(setup=setup):
                output = self.run_update(command=self.go_command(setup))
                self.assertIn("COUNTS=0,1,0", output)
                self.assertFalse(self.go_path.exists())
        self.assertEqual(self.go_apt_calls(), [])
        self.assertEqual(self.events(), [])
        self.write_input(self.go_resolved, (self.go_state / "go-payload").read_text())
        self.go_resolved.chmod(0o755)
        self.go_path.symlink_to(self.go_resolved)
        output = self.run_update(command=self.go_command("FORCE_MODE=true UPDATE_GO_PACKAGES=false"))
        self.assert_go_verified(output)
        self.assertEqual(self.go_apt_calls(), [])

    def test_go_owned_package_updates_exact_owner_and_reuses_fresh_index(self):
        self.write_go_fixture()
        output = self.run_update(command=self.go_command("UPDATE_APT=false", action="update_go\nupdate_go"))
        self.assert_go_verified(output, count=2)
        calls = self.go_apt_calls()
        self.assertEqual(sum("update" in call for call in calls), 1)
        installs = [call for call in calls if "install" in call]
        self.assertEqual(len(installs), 2)
        for call in installs:
            self.assertIn("DPkg::Lock::Timeout=120", call)
            self.assertEqual(call[-4:], ["install", "-y", "--only-upgrade", "golang-1.23-go:amd64"])
        events = self.go_package_events()
        self.assertIn(["dpkg-query", "-S", str(self.go_resolved)], events)
        for event in events:
            if event[0] == "apt-get":
                self.assertEqual(event[2:5], ["noninteractive", "a", "1"])
            elif event[0] == "sudo":
                self.assertEqual(event[1], "-n")
                self.assertIn(str(self.go_state / "tools/apt-get"), event)

    def test_go_canonical_command_tracks_meta_and_actual_compiler_packages(self):
        self.write_go_fixture(package="golang-1.23-go")
        self.write_input(self.go_state / "meta-status", "install ok installed\n")
        # Only the ownership query sees /usr/bin/go. The real host command is
        # never selected or executed; readlink maps it to our inert compiler.
        readlink = self.go_state / "tools/readlink"
        self.write_input(readlink, "#!/bin/bash\n"
                         '[[ "$*" == "-f -- /usr/bin/go" ]] || exit 97\n'
                         "printf '%s\\n' " + shlex.quote(str(self.go_resolved)) + "\n")
        readlink.chmod(0o755)
        setup = r'''
fixture_system_lookup="$(declare -f update_system_binary_path)"
eval "${fixture_system_lookup/update_system_binary_path/fixture_system_binary_path}"
update_system_binary_path() {
    if [[ "$1" == readlink ]]; then printf '%s\n' "$TEST_HOME/go-fixture/tools/readlink"
    else fixture_system_binary_path "$@"; fi
}
'''
        output = self.run_update(command=self.go_command(setup, action="update_go_apt_packages /usr/bin/go"))
        self.assertEqual(output.splitlines()[:2], ["golang-go", "golang-1.23-go"])
        self.assertEqual(self.go_apt_calls(), [])
        self.assertEqual(self.events(), [])

    def test_go_force_repairs_installed_compiler_dependency(self):
        self.write_go_fixture(installed=False, package="golang-1.23-go")
        self.write_input(self.go_state / "status", "install ok installed\n")
        self.write_input(self.go_state / "meta-status", "install ok installed\n")
        self.write_input(self.go_state / "depends", "golang-1.23-go (>= 1.23.0), golang-src\n")
        output = self.run_update(command=self.go_command("FORCE_MODE=true"))
        self.assert_go_verified(output)
        install = [call for call in self.go_apt_calls() if "install" in call]
        self.assertEqual(len(install), 1)
        self.assertEqual(install[0][-5:], ["install", "-y", "--reinstall", "golang-go", "golang-1.23-go"])
        self.assertNotIn("--only-upgrade", install[0])

    def test_go_manual_install_uses_bounded_target_verification(self):
        self.write_go_fixture(package="")
        output = self.run_update(command=self.go_command(), overrides={
            "GOTOOLCHAIN": "go1.99.0+auto", "GOENV": str(self.caller / "go-env"),
            "GOWORK": str(self.work / "go.work"), "GOROOT": str(self.caller / "go"),
            "GOPATH": str(self.caller / "go-path"),
        })
        self.assert_go_verified(output)
        self.assertEqual(self.go_apt_calls(), [])
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_go_verification_failure_invalid_output_and_timeout_count_failures(self):
        self.write_go_fixture(package="")
        for mode in ("failure", "invalid", "timeout"):
            with self.subTest(mode=mode):
                self.write_input(self.go_state / "go-mode", mode + "\n")
                output = self.run_update(command=self.go_command(), timeout="0.1")
                self.assertIn("COUNTS=0,0,1", output)
        self.assertEqual(self.go_apt_calls(), [])
        self.assert_target_events(self.events())
        self.assertRegex((self.base / "update.log").read_text(), r"exit code: (124|137)")

    def test_go_package_failures_stop_before_readiness_and_transient_errors_retry(self):
        self.write_go_fixture(installed=False)
        for mode in ("update-failure", "install-failure", "install-timeout", "no-sudo"):
            with self.subTest(mode=mode):
                self.write_input(self.go_state / "mode", mode + "\n")
                start = len(self.go_apt_calls())
                output = self.run_update(command=self.go_command("FORCE_MODE=true"), timeout="0.1")
                self.assertIn("COUNTS=0,0,1", output)
                if mode in ("update-failure", "no-sudo"):
                    self.assertFalse(any("install" in call for call in self.go_apt_calls()[start:]))
                self.assertFalse(self.go_path.exists())
                self.assertEqual(self.events(), [])
        self.write_input(self.go_state / "mode", "transient-install\n")
        start = len(self.go_apt_calls())
        output = self.run_update(command=self.go_command("FORCE_MODE=true"))
        self.assert_go_verified(output)
        self.assertEqual(sum("install" in call for call in self.go_apt_calls()[start:]), 2)

    def test_go_package_success_requires_a_working_compiler(self):
        self.write_go_fixture(installed=False)
        for mode in ("no-payload", "broken-payload"):
            with self.subTest(mode=mode):
                self.write_input(self.go_state / "mode", mode + "\n")
                output = self.run_update(command=self.go_command("FORCE_MODE=true"))
                self.assertIn("COUNTS=0,0,1", output)
        self.assertEqual(len(self.events()), 1)
        self.assert_target_events(self.events())

    def test_go_dry_run_hold_and_saved_selection_block_execution(self):
        self.write_go_fixture(installed=False)
        output = self.run_update(dry_run=True, command=self.go_command("FORCE_MODE=true"))
        self.assertIn("COUNTS=0,1,0", output)
        self.run_update(command=self.go_command("UPDATE_RUNTIME=false FORCE_MODE=true"))
        self.owned_dir(self.home / ".acfs")
        self.write_input(self.home / ".acfs/holds.yaml", 'holds:\n  go:\n'
                         '    held_version: "current"\n    owner: "fixture"\n'
                         '    reason: "keep compiler"\n    expiry: ""\n')
        output = self.run_update(command=self.go_command("FORCE_MODE=true"))
        self.assertIn("COUNTS=0,1,0", output)
        self.assertIn("keep compiler", (self.base / "update.log").read_text())
        self.write_input(self.home / ".acfs/holds.yaml", "holds: {}\n")
        checkpoint = self.home / ".acfs/state.json"
        self.write_input(checkpoint, json.dumps({"target_home": str(self.home),
            "target_user": self.account.pw_name,
            "module_selection": {"schema_version": 1, "selected_modules": ["lang.bun"]}}))
        saved = checkpoint.read_bytes()
        self.run_update(command=self.go_command("FORCE_MODE=true"))
        self.assertEqual(checkpoint.read_bytes(), saved)
        self.write_input(checkpoint, json.dumps({"target_home": str(self.home),
            "target_user": self.account.pw_name,
            "module_selection": {"schema_version": 1, "selected_modules": ["lang.go"]}}))
        self.write_input(self.base / "go-platform-index.sh", 'ACFS_MODULES_IN_ORDER=(\n  "lang.go"\n)\n'
                         'declare -gA ACFS_MODULE_FAMILIES=(\n  [\'lang.go\']="ubuntu"\n)\n')
        saved = checkpoint.read_bytes()
        self.run_update(command=self.go_command('FORCE_MODE=true ACFS_DISTRO_FAMILY=arch\n'
                         '_UPDATE_MANIFEST_INDEX="$TEST_ROOT/go-platform-index.sh"'))
        self.assertEqual(checkpoint.read_bytes(), saved)
        self.assertEqual(self.go_apt_calls(), [])
        self.assertEqual(self.events(), [])
        self.assertFalse(self.go_path.exists())

    def test_go_unsupported_forced_repair_never_calls_apt(self):
        self.write_go_fixture(installed=False)
        output = self.run_update(command=self.go_command("ACFS_DISTRO_FAMILY=arch FORCE_MODE=true"))
        self.assertIn("COUNTS=0,0,1", output)
        self.assertIn("system package manager", (self.base / "update.log").read_text())
        self.assertEqual(self.go_apt_calls(), [])
        self.assertEqual(self.events(), [])

    def test_go_unproven_package_ownership_does_not_replace_existing_tool(self):
        self.write_go_fixture()
        for mode, owner, status in (
            ("wrong-owner-path", "golang-1.23-go:amd64", "install ok installed"),
            ("normal", "golang-1.23-go:amd64", "deinstall ok config-files"),
            ("normal", "unrelated-package", "install ok installed"),
        ):
            with self.subTest(mode=mode, owner=owner, status=status):
                self.write_input(self.go_state / "mode", mode + "\n")
                self.write_input(self.go_state / "owner", owner + "\n")
                self.write_input(self.go_state / "status", status + "\n")
                output = self.run_update(command=self.go_command("FORCE_MODE=true"))
                self.assertIn("COUNTS=1,0,0", output)
        self.assertEqual(self.go_apt_calls(), [])
        self.assertEqual(len(self.events()), 3)
        self.assert_target_events(self.events())

    def test_go_cross_account_verification_uses_target_without_caller_selectors(self):
        self.write_go_fixture(package="")
        output = self.run_update(cross=True, transport="runuser", command=self.go_command(), overrides={
            "GOTOOLCHAIN": "go1.99.0+auto", "GOENV": str(self.caller / "go-env"),
            "GOWORK": str(self.work / "go.work"), "GOROOT": str(self.caller / "go"),
            "GOPATH": str(self.caller / "go-path"),
        })
        self.assert_go_verified(output)
        self.assertEqual(self.go_apt_calls(), [])
        self.assertEqual(list(self.caller.iterdir()), [])

    def write_nvm_fixture(self, directory=None, *, default="node", version="0.39.7",
                          installed=True, npm=False):
        directory = directory or self.home / ".nvm"
        prefix = "fixture=" + shlex.quote(str(self.base)) + "\n"
        event = r'''
fixture_nvm_event() {
    local operation="$1"; shift
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$operation" "$EUID" "$HOME" "$PWD" "${NVM_DIR-<unset>}" \
        "${XDG_CONFIG_HOME-<unset>}" "${PROFILE-<unset>}" "$*" >> "$fixture/events.tsv"
}
'''
        library = prefix + event + r'''
fixture_nvm_event nvm-source "$@"
[[ ! -f "$NVM_DIR/hang-source" ]] || /bin/sleep 5
nvm_alias() {
    fixture_nvm_event nvm_alias "$@"
    [[ -f "$NVM_DIR/alias/$1" ]] || return 2
    cat "$NVM_DIR/alias/$1"
}
nvm() {
    fixture_nvm_event nvm "$@"
    case "$1" in
        --version)
            if [[ -f "$NVM_DIR/fail-nvm-version" && "$(cat "$NVM_DIR/fixture-version")" != 0.40.1 ]]; then
                return 17
            fi
            cat "$NVM_DIR/fixture-version"
            ;;
        version)
            [[ "$2" == default && -x "$NVM_DIR/versions/node/v20.19.0/bin/node" ]] || return 3
            printf 'v20.19.0\n'
            ;;
        version-remote)
            if [[ "$2" == v[0-9]* ]]; then printf '%s\n' "$2"
            else printf 'v22.20.0\n'; fi
            ;;
        which)
            if [[ "$2" == default ]]; then
                local default_version=v20.19.0
                [[ ! -f "$NVM_DIR/default-installed-version" ]] || read -r default_version < "$NVM_DIR/default-installed-version"
                printf '%s\n' "$NVM_DIR/versions/node/$default_version/bin/node"
            elif [[ "$2" == current ]]; then
                printf '%s\n' "$NVM_DIR/versions/node/${NVM_FIXTURE_CURRENT:?}/bin/node"
            else return 64; fi
            ;;
        install)
            [[ ! -f "$NVM_DIR/hang-install" ]] || /bin/sleep 5
            [[ ! -f "$NVM_DIR/fail-install" ]] || return 17
            shift
            local migrate=false
            if [[ "${1:-}" == --reinstall-packages-from=* ]]; then
                printf '%s\n' "${1#*=}" > "$NVM_DIR/migrated-packages"
                migrate=true
                shift
            fi
            [[ $# == 1 ]] || return 64
            printf '%s\n' "$1" > "$NVM_DIR/installed-selector"
            local installed_version=v22.20.0
            [[ "$1" != v[0-9]* ]] || installed_version="$1"
            mkdir -p "$NVM_DIR/versions/node/$installed_version/bin"
            cp "$fixture/node-payload" "$NVM_DIR/versions/node/$installed_version/bin/node"
            chmod 0755 "$NVM_DIR/versions/node/$installed_version/bin/node"
            if [[ "$migrate" == true ]]; then
                cp "$fixture/node-payload" "$NVM_DIR/versions/node/$installed_version/bin/npm"
                chmod 0755 "$NVM_DIR/versions/node/$installed_version/bin/npm"
            fi
            ;;
        use)
            [[ "${2:-}" != --silent ]] || shift
            NVM_FIXTURE_CURRENT=v22.20.0
            [[ "$2" != v[0-9]* ]] || NVM_FIXTURE_CURRENT="$2"
            export NVM_FIXTURE_CURRENT
            printf '%s\n' "$NVM_FIXTURE_CURRENT" > "$NVM_DIR/default-installed-version"
            ;;
        alias)
            [[ "$2" == default && $# == 3 ]] || return 64
            mkdir -p "$NVM_DIR/alias"
            printf '%s\n' "$3" > "$NVM_DIR/alias/default"
            ;;
        *) return 64 ;;
    esac
}
'''
        node = "#!/bin/bash\nset -euo pipefail\n" + prefix + event + r'''
fixture_nvm_event node "$@"
[[ "$*" == --version ]] || exit 64
[[ ! -f "$NVM_DIR/fail-node-version" ]] || exit 18
installed_version="${0%/bin/*}"
printf '%s\n' "${installed_version##*/}"
'''
        installer = "#!/bin/bash\nset -euo pipefail\n" + prefix + event + r'''
fixture_nvm_event nvm-installer "$@"
[[ ! -f "$fixture/hang-nvm-installer" ]] || /bin/sleep 5
[[ ! -f "$fixture/fail-nvm-installer" ]] || exit 19
[[ "${PROFILE:-}" == /dev/null && "${NVM_DIR:-}" == /* ]] || exit 65
for selector in NODE_VERSION NVM_SOURCE NVM_INSTALL_VERSION NVM_INSTALL_GITHUB_REPO METHOD NVM_INSTALL_THIRD_PARTY_HOOK; do
    [[ ! -v "$selector" ]] || exit 66
done
mkdir -p "$NVM_DIR"
cp "$fixture/nvm-payload" "$NVM_DIR/nvm.sh"
printf '0.40.1\n' > "$NVM_DIR/fixture-version"
'''
        for name, content in (("nvm-payload", library), ("node-payload", node),
                              ("nvm-installer", installer)):
            self.write_input(self.base / name, content)
        if installed:
            self.owned_dir(directory)
            self.write_input(directory / "nvm.sh", library)
            self.write_input(directory / "fixture-version", version + "\n")
            if default is not None:
                self.owned_dir(directory / "alias")
                self.write_input(directory / "alias/default", default + "\n")
            if npm:
                binaries = directory / "versions/node/v20.19.0/bin"
                self.owned_dir(binaries)
                for name in ("node", "npm"):
                    self.write_input(binaries / name, node)
                    (binaries / name).chmod(0o755)
        return directory

    def nvm_command(self, setup=""):
        # Only acquisition is replaced: the verified-installer dispatcher,
        # private staging, account transport, deadlines and nvm/Node phase run
        # normally against local inert payloads. No URL is contacted.
        return r'''
source "${UPDATE_TEST_LIBRARY%/*}/security.sh"
source "${UPDATE_TEST_LIBRARY%/*}/holds.sh"
ACFS_HOLDS_FILE="$TEST_HOME/.acfs/holds.yaml"
KNOWN_INSTALLERS=([nvm]="https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh")
update_require_security() { return 0; }
get_checksum() { [[ "$1" == nvm ]] && sha256sum "$TEST_ROOT/nvm-installer" | awk '{print $1}'; }
verify_checksum() {
    [[ "$1" == "${KNOWN_INSTALLERS[nvm]}" && "$3" == nvm ]] || return 95
    [[ "$2" == "$(get_checksum nvm)" ]] || return 95
    printf 'download\n' >> "$TEST_HOME/nvm-downloads"
    cat "$TEST_ROOT/nvm-installer"
}
# Retain the real private staging directory for fixture inspection.
update_remove_target_installer_tmpdir() { :; }
''' + setup + "\nupdate_nvm\n"

    def assert_nvm_success(self, output, directory, selector):
        self.assertIn("COUNTS=1,0,0", output)
        events = self.events()
        self.assert_target_events(events)
        self.assertTrue(all(event[4] == str(directory) for event in events), events)
        self.assertTrue(all(event[-1] == "--no-use" for event in events if event[0] == "nvm-source"))
        self.assertTrue(any(event[0] == "nvm" and event[-1] == "--version" for event in events))
        self.assertTrue(any(event[0] == "node" and event[-1] == "--version" for event in events))
        self.assertTrue(any(event[0] == "nvm" and event[-1] == "version-remote " + selector
                            for event in events))
        installed = selector if selector.startswith("v") else "v22.20.0"
        self.assertEqual((directory / "installed-selector").read_text(), installed + "\n")
        self.assertEqual((directory / "installed-selector").stat().st_uid, self.account.pw_uid)

    def test_nvm_updates_manager_and_preserves_default_channel(self):
        directory = self.write_nvm_fixture(default="lts/*", npm=True)
        output = self.run_update(command=self.nvm_command())
        self.assert_nvm_success(output, directory, "lts/*")
        self.assertEqual((directory / "alias/default").read_text(), "lts/*\n")
        self.assertEqual((directory / "fixture-version").read_text(), "0.40.1\n")
        self.assertEqual((directory / "migrated-packages").read_text(), "v20.19.0\n")
        self.assertIn("install --reinstall-packages-from=v20.19.0 v22.20.0",
                      [event[-1] for event in self.events() if event[0] == "nvm"])
        self.assertEqual((self.home / "nvm-downloads").read_text().splitlines(), ["download"])
        original_count = len(self.events())
        output = self.run_update(command=self.nvm_command())
        self.assert_nvm_success(output, directory, "lts/*")
        repeated = self.events()[original_count:]
        self.assertEqual([event[-1] for event in repeated
                          if event[0] == "nvm" and event[-1].startswith("install ")],
                         ["install v22.20.0"])
        self.assertEqual((directory / "alias/default").read_text(), "lts/*\n")
        self.assertEqual((self.home / "nvm-downloads").read_text().splitlines(), ["download"])

    def test_nvm_same_account_preserves_absolute_override_and_pinned_alias(self):
        directory = self.write_nvm_fixture(self.home / "custom nvm", default="v20.19.0")
        output = self.run_update(command=self.nvm_command(), overrides={"NVM_DIR": str(directory)})
        self.assert_nvm_success(output, directory, "v20.19.0")
        self.assertEqual((directory / "alias/default").read_text(), "v20.19.0\n")
        self.assertFalse((self.home / ".nvm").exists())

    def test_nvm_same_account_relative_override_keeps_original_working_directory(self):
        directory = self.write_nvm_fixture(self.work / "relative nvm", default="node")
        output = self.run_update(command=self.nvm_command(), overrides={"NVM_DIR": "relative nvm"})
        self.assert_nvm_success(output, directory, "node")
        self.assertFalse((self.home / "relative nvm").exists())

    def assert_cross_account_nvm_home(self, relative):
        directory = self.write_nvm_fixture(self.home / relative)
        output = self.run_update(cross=True, transport="runuser", command=self.nvm_command(),
                                 overrides={"NVM_DIR": str(self.caller / "foreign-nvm"),
                                            "XDG_CONFIG_HOME": str(self.caller / "foreign-xdg"),
                                            "NODE_VERSION": "v0.0.1", "NVM_NODEJS_ORG_MIRROR": "https://invalid.example"})
        self.assert_nvm_success(output, directory, "node")
        self.assertTrue(all(event[5] != str(self.caller / "foreign-xdg") for event in self.events()))
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_nvm_cross_account_ignores_callers_nvm_and_xdg_selectors(self):
        self.assert_cross_account_nvm_home(".nvm")

    def test_nvm_cross_account_finds_targets_xdg_installation(self):
        self.assert_cross_account_nvm_home(".config/nvm")

    def test_nvm_newer_manager_is_not_downgraded_but_node_updates(self):
        directory = self.write_nvm_fixture(version="0.40.2")
        output = self.run_update(command=self.nvm_command())
        self.assert_nvm_success(output, directory, "node")
        self.assertFalse((self.home / "nvm-downloads").exists())
        self.assertFalse(any(event[0] == "nvm-installer" for event in self.events()))
        self.assertEqual((directory / "fixture-version").read_text(), "0.40.2\n")

    def test_nvm_absent_skips_unless_force_repairs_it(self):
        directory = self.write_nvm_fixture(installed=False)
        output = self.run_update(command=self.nvm_command())
        self.assertIn("COUNTS=0,1,0", output)
        self.assertEqual(self.events(), [])
        self.assertFalse((self.home / "nvm-downloads").exists())
        output = self.run_update(command=self.nvm_command("FORCE_MODE=true"))
        self.assert_nvm_success(output, directory, "node")
        self.assertEqual((directory / "alias/default").read_text(), "node\n")
        actions = [(event[0], event[-1]) for event in self.events()]
        self.assertLess(actions.index(("node", "--version")), actions.index(("nvm", "alias default node")))

    def test_nvm_dry_run_never_sources_downloads_or_creates_installation(self):
        directory = self.write_nvm_fixture(installed=False)
        output = self.run_update(dry_run=True, command=self.nvm_command("FORCE_MODE=true"))
        self.assertIn("COUNTS=0,1,0", output)
        self.assertFalse(directory.exists())
        self.write_nvm_fixture(default="lts/*")
        self.run_update(dry_run=True, command=self.nvm_command())
        self.assertEqual(self.events(), [])
        self.assertFalse((self.home / "nvm-downloads").exists())
        self.assertEqual((directory / "alias/default").read_text(), "lts/*\n")

    def test_nvm_hold_precedes_source_download_and_force(self):
        directory = self.write_nvm_fixture()
        self.owned_dir(self.home / ".acfs")
        self.write_input(self.home / ".acfs/holds.yaml", 'holds:\n  nvm:\n'
                         '    held_version: "current"\n    owner: "fixture"\n'
                         '    reason: "keep manager and Node"\n    expiry: ""\n')
        output = self.run_update(command=self.nvm_command("FORCE_MODE=true"))
        self.assertIn("COUNTS=0,1,0", output)
        self.assertEqual(self.events(), [])
        self.assertFalse((self.home / "nvm-downloads").exists())
        self.assertFalse((directory / "installed-selector").exists())
        self.assertIn("keep manager and Node", (self.base / "update.log").read_text())

    def test_nvm_runtime_selection_and_platform_gate_all_execution(self):
        self.write_nvm_fixture()
        self.run_update(command=self.nvm_command("UPDATE_RUNTIME=false"))
        self.owned_dir(self.home / ".acfs")
        checkpoint = self.home / ".acfs/state.json"
        self.write_input(checkpoint, json.dumps({"target_home": str(self.home),
            "target_user": self.account.pw_name,
            "module_selection": {"schema_version": 1, "selected_modules": ["lang.bun"]}}))
        self.run_update(command=self.nvm_command("FORCE_MODE=true"))
        self.write_input(checkpoint, json.dumps({"target_home": str(self.home),
            "target_user": self.account.pw_name,
            "module_selection": {"schema_version": 1, "selected_modules": ["lang.nvm"]}}))
        self.write_input(self.base / "nvm-platform-index.sh", 'ACFS_MODULES_IN_ORDER=(\n  "lang.nvm"\n)\n'
                         'declare -gA ACFS_MODULE_FAMILIES=(\n  [\'lang.nvm\']="ubuntu"\n)\n')
        saved = checkpoint.read_bytes()
        self.run_update(command=self.nvm_command('FORCE_MODE=true ACFS_DISTRO_FAMILY=arch\n'
                         '_UPDATE_MANIFEST_INDEX="$TEST_ROOT/nvm-platform-index.sh"'))
        self.assertEqual(self.events(), [])
        self.assertFalse((self.home / "nvm-downloads").exists())
        self.assertEqual(checkpoint.read_bytes(), saved)

    def test_nvm_dangling_default_alias_is_preserved_and_refused(self):
        directory = self.write_nvm_fixture(default=None)
        self.owned_dir(directory / "alias")
        alias = directory / "alias/default"
        alias.symlink_to("missing-default")
        output = self.run_update(command=self.nvm_command())
        self.assertIn("COUNTS=0,0,1", output)
        self.assertTrue(alias.is_symlink())
        self.assertEqual(os.readlink(alias), "missing-default")
        self.assertFalse((directory / "alias/missing-default").exists())
        self.assertFalse((directory / "installed-selector").exists())

    def test_nvm_installer_failure_stops_before_node_stage(self):
        directory = self.write_nvm_fixture()
        self.write_input(self.base / "fail-nvm-installer", "fixture\n")
        output = self.run_update(command=self.nvm_command())
        self.assertIn("COUNTS=0,0,1", output)
        self.assertTrue(any(event[0] == "nvm-installer" for event in self.events()))
        self.assertFalse(any(event[0] == "nvm" and event[-1].startswith("install ") for event in self.events()))
        self.assertFalse((directory / "installed-selector").exists())
        self.assertIn("exit code: 19", (self.base / "update.log").read_text())

    def test_nvm_installer_timeout_stops_before_node_stage(self):
        directory = self.write_nvm_fixture()
        self.write_input(self.base / "hang-nvm-installer", "fixture\n")
        output = self.run_update(command=self.nvm_command(), timeout="0.1")
        self.assertIn("COUNTS=0,0,1", output)
        self.assertFalse((directory / "installed-selector").exists())
        self.assertRegex((self.base / "update.log").read_text(), r"exit code: (124|137)")

    def test_nvm_node_install_timeout_is_counted_and_does_not_set_default(self):
        directory = self.write_nvm_fixture(default=None)
        self.write_input(directory / "hang-install", "fixture\n")
        output = self.run_update(command=self.nvm_command(), timeout="0.1")
        self.assertIn("COUNTS=0,0,1", output)
        self.assertFalse((directory / "alias/default").exists())
        self.assertFalse((directory / "installed-selector").exists())
        self.assertRegex((self.base / "update.log").read_text(), r"exit code: (124|137)")

    def test_nvm_source_probe_is_bounded_before_installer_download(self):
        directory = self.write_nvm_fixture()
        self.write_input(directory / "hang-source", "fixture\n")
        output = self.run_update(command=self.nvm_command(), timeout="0.1")
        self.assertIn("COUNTS=0,0,1", output)
        self.assertFalse((self.home / "nvm-downloads").exists())
        self.assertFalse((directory / "installed-selector").exists())

    def test_nvm_node_readiness_failure_is_not_reported_as_success(self):
        directory = self.write_nvm_fixture(default=None)
        self.write_input(directory / "fail-node-version", "fixture\n")
        output = self.run_update(command=self.nvm_command())
        self.assertIn("COUNTS=0,0,1", output)
        self.assertTrue(any(event[0] == "node" and event[-1] == "--version" for event in self.events()))
        self.assertFalse((directory / "alias/default").exists())

    def test_nvm_probe_failure_requires_explicit_force_repair(self):
        directory = self.write_nvm_fixture()
        self.write_input(directory / "fail-nvm-version", "fixture\n")
        output = self.run_update(command=self.nvm_command())
        self.assertIn("COUNTS=0,0,1", output)
        self.assertFalse((self.home / "nvm-downloads").exists())
        self.assertFalse((directory / "installed-selector").exists())
        output = self.run_update(command=self.nvm_command("FORCE_MODE=true"))
        self.assert_nvm_success(output, directory, "node")

    def test_native_uv_retries_as_target_and_succeeds_without_fallback(self):
        self.write_native_tool("uv")
        self.write_input(self.base / "mode-uv", "transient\n")
        command = 'update_require_security() { printf unexpected-fallback; return 1; }; update_uv'
        output = self.run_update(cross=True, command=command)
        self.assert_target_events(self.events())
        self.assertEqual([e[-1] for e in self.events()], ["--version", "self update", "self update", "--version"])
        self.assertIn("COUNTS=1,0,0", output)
        self.assertNotIn("unexpected-fallback", output)
        self.assertEqual((self.home / "uv-native-installed").stat().st_uid, self.account.pw_uid)
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_uv_failure_keeps_verified_installer_fallback_dispatch(self):
        self.write_native_tool("uv")
        self.write_input(self.base / "mode-uv", "failure\n")
        command = r'''
update_require_security() { printf 'security-check\n'; return 0; }
update_run_verified_installer_with_shell_repair() {
    printf 'VERIFIED-FALLBACK:%s|%s|%s\n' "$1" "$2" "$3"
    return 1
}
update_uv
'''
        output = self.run_update(cross=True, command=command)
        self.assert_target_events(self.events())
        self.assertIn("security-check", output)
        self.assertIn("VERIFIED-FALLBACK:uv verified installer fallback|uv|update_repair_uv_install", output)
        self.assertEqual([e[-1] for e in self.events()].count("self update"), 1)

    def test_atuin_dedicated_updater_is_targeted_and_retains_native_success(self):
        self.write_native_tool("atuin")
        self.write_native_tool("atuin-update", directory=self.home / ".atuin/bin")
        output = self.run_update(cross=True, command="update_atuin")
        self.assert_target_events(self.events())
        self.assertIn(("atuin-update", ""), [(e[0], e[-1]) for e in self.events()])
        self.assertNotIn("--help", [e[-1] for e in self.events()])
        self.assertIn("COUNTS=1,0,0", output)
        self.assertEqual((self.home / "atuin-update-native-installed").stat().st_uid, self.account.pw_uid)
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_atuin_compatibility_probe_and_self_update_retry_as_target(self):
        self.write_native_tool("atuin")
        self.write_input(self.base / "mode-atuin", "transient\n")
        output = self.run_update(cross=True, command="update_atuin")
        self.assert_target_events(self.events())
        args = [e[-1] for e in self.events()]
        self.assertEqual(args.count("--help"), 1)
        self.assertEqual(args.count("self-update"), 2)
        self.assertIn("COUNTS=1,0,0", output)
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_atuin_compatibility_match_drains_trailing_help_output(self):
        self.write_native_tool("atuin")
        self.write_input(self.base / "help-tail-atuin", "additional help text\n" * 8192)
        output = self.run_update(cross=True, command="update_atuin")
        self.assert_target_events(self.events())
        self.assertIn("self-update", [e[-1] for e in self.events()])
        self.assertIn("COUNTS=1,0,0", output)

    def test_nightly_selection_drains_trailing_toolchain_list_output(self):
        self.write_input(self.rust_home / "toolchains.txt",
            "nightly-x86_64-unknown-linux-gnu\n" + "stable-fixture-toolchain\n" * 8192)
        output = self.run_update(cross=True)
        self.assert_target_events(self.events())
        self.assertIn("update nightly", [e[-1] for e in self.events()])
        self.assertIn("COUNTS=3,0,0", output)

    def test_failed_dedicated_atuin_updater_does_not_invoke_setup(self):
        self.write_native_tool("atuin")
        self.write_native_tool("atuin-update", directory=self.home / ".atuin/bin")
        self.write_input(self.base / "mode-atuin-update", "failure\n")
        output = self.run_update(cross=True, command='update_require_security() { printf unexpected-setup; }; update_atuin')
        self.assert_target_events(self.events())
        self.assertIn("COUNTS=0,1,0", output)
        self.assertNotIn("unexpected-setup", output)
        self.assertFalse((self.home / "atuin-update-native-installed").exists())

    def test_atuin_agent_aware_setup_refusal_remains_enforced(self):
        self.write_native_tool("atuin")
        (self.base / "no-atuin-self-update").write_text("fixture\n")
        command = r'''
update_require_security() { return 0; }
declare -A KNOWN_INSTALLERS=([atuin]=https://setup.atuin.sh)
update_run_verified_installer_with_shell_repair() { printf unexpected-setup; return 1; }
update_atuin
'''
        output = self.run_update(cross=True, command=command)
        self.assert_target_events(self.events())
        self.assertIn("COUNTS=0,1,0", output)
        self.assertIn("refusing agent-aware setup installer", (self.base / "update.log").read_text())
        self.assertNotIn("unexpected-setup", output)

    def test_native_updates_keep_deadlines_inside_target_account(self):
        self.write_native_tool("bun")
        self.write_native_tool("uv")
        self.write_native_tool("atuin")
        self.write_native_tool("atuin-update", directory=self.home / ".atuin/bin")
        for tool in ("bun", "uv", "atuin-update"):
            self.write_input(self.base / f"mode-{tool}", "hang\n")
        output = self.run_update(cross=True, timeout="0.1",
                                 command='update_require_security() { return 1; }; update_bun; update_uv; update_atuin')
        self.assert_target_events(self.events())
        self.assertIn("COUNTS=0,1,2", output)
        log = (self.base / "update.log").read_text()
        self.assertIn("Failed: Bun self-upgrade (exit code: 124)", log)
        self.assertIn("Failed: uv self-update (exit code: 124", log)
        self.assertIn("Failed: Atuin updater (exit code: 124", log)
        for tool in ("bun", "uv", "atuin-update"):
            self.assertFalse((self.home / f"{tool}-native-installed").exists())

    def test_native_dry_run_probes_target_but_never_self_updates(self):
        self.write_native_tool("bun")
        self.write_native_tool("uv")
        self.write_native_tool("atuin")
        self.write_native_tool("atuin-update", directory=self.home / ".atuin/bin")
        output = self.run_update(cross=True, dry_run=True, command="update_bun; update_uv; update_atuin")
        self.assert_target_events(self.events())
        self.assertEqual(set(e[-1] for e in self.events()), {"--version"})
        self.assertIn("COUNTS=0,3,0", output)
        for tool in ("bun", "uv", "atuin-update"):
            self.assertFalse((self.home / f"{tool}-native-attempts").exists())

    def test_native_versions_and_updates_refuse_missing_account_transport(self):
        self.write_native_tool("bun")
        self.write_native_tool("uv")
        self.write_native_tool("atuin")
        self.write_native_tool("atuin-update", directory=self.home / ".atuin/bin")
        output = self.run_update(cross=True, transport="none",
                                 command='update_require_security() { return 1; }; update_bun; update_uv; update_atuin')
        self.assertEqual(self.events(), [])
        self.assertIn("COUNTS=0,1,2", output)
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_custom_only_cargo_packages_are_discovered_probed_and_updated(self):
        cargo_home = self.work / "custom packages"
        self.owned_dir(cargo_home)
        self.write_tools(cargo_home / "bin", "custom-cargo")
        for tool in ("sg", "lsd", "dust", "tldr"):
            self.write_native_tool(tool, directory=cargo_home / "bin", origin="custom-package")
        output = self.run_update(overrides={"CARGO_HOME": "custom packages"}, command="update_cargo_tools")
        self.assert_target_events(self.events())
        self.assertIn("COUNTS=4,0,0", output)
        self.assertEqual([e[-1] for e in self.events() if e[0] == "cargo"],
                         [f"install {name} --locked --force" for name in ("ast-grep", "lsd", "du-dust", "tealdeer")])
        self.assertEqual([e[0] for e in self.events() if e[0] != "cargo"],
                         [name for name in ("sg", "lsd", "dust", "tldr") for _ in range(2)])
        for event in self.events():
            self.assertEqual(event[5], str(cargo_home), event)

    def test_cross_account_cargo_package_discovery_ignores_callers_custom_home(self):
        foreign_cargo = self.caller / "foreign-cargo"
        self.owned_dir(foreign_cargo)
        for tool in ("sg", "lsd", "dust", "tldr"):
            self.write_native_tool(tool, directory=self.cargo_home / "bin", origin="target-package")
            self.write_native_tool(tool, directory=foreign_cargo / "bin", origin="foreign-package")
        output = self.run_update(cross=True, transport="runuser", command="update_cargo_tools",
                                 overrides={"CARGO_HOME": str(foreign_cargo)})
        self.assert_target_events(self.events())
        self.assertIn("COUNTS=4,0,0", output)
        for event in self.events():
            self.assertEqual(event[5], "<unset>", event)
            self.assertNotEqual(event[8], "foreign-package", event)

    def test_all_repair_version_probes_execute_as_target(self):
        for tool in ("atuin", "zoxide", "uv"):
            self.write_native_tool(tool)
        self.run_update(cross=True, command="update_repair_atuin_install; update_repair_zoxide_install; update_repair_uv_install")
        self.assert_target_events(self.events())
        self.assertEqual([(e[0], e[-1]) for e in self.events()],
                         [(tool, "--version") for tool in ("atuin", "zoxide", "uv")])

    def test_rollback_smoke_probe_uses_target_account_and_detaches_stdin(self):
        binary = self.write_native_tool("claude")
        (self.base / "read-stdin-claude").write_text("fixture\n")
        command = "printf 'do-not-read\\n' | update_run_smoke_probe " + shlex.quote(str(binary)) + " --version"
        output = self.run_update(cross=True, command=command)
        self.assert_target_events(self.events())
        self.assertFalse((self.home / "probe-read-stdin").exists())
        # Real sudo may precede the payload with a host audit diagnostic; it
        # belongs in combined output, while internal receipts must never leak.
        self.assertTrue(output.endswith("claude 1.2.3-fixture\nextra metadata\nCOUNTS=0,0,0\n"), output)
        self.assertNotIn("ACFS_SMOKE_STARTED_", output)

    def test_rollback_smoke_deadline_and_status_are_preserved(self):
        binary = self.write_native_tool("claude")
        (self.base / "hang-probe-claude").write_text("fixture\n")
        command = "UPDATE_SMOKE_TIMEOUT=0.1 update_run_smoke_probe " + shlex.quote(str(binary)) + " --version"
        self.run_update(cross=True, command=command, expected=124)
        self.assert_target_events(self.events())

    def test_rollback_smoke_never_falls_back_to_caller_when_transport_is_missing(self):
        binary = self.write_native_tool("claude")
        command = "rc=0; update_tool_smoke_check claude " + shlex.quote(str(binary)) + \
            ' || rc=$?; printf "SMOKE=%s\\n" "$UPDATE_LAST_SMOKE_VERDICT"; exit "$rc"'
        output = self.run_update(cross=True, transport="none", command=command, expected=1)
        self.assertIn("SMOKE=broken", output)
        self.assertEqual(self.events(), [])

    def test_rollback_smoke_reports_unresolvable_target_home_as_broken(self):
        binary = self.write_native_tool("claude")
        command = "rc=0; update_tool_smoke_check claude " + shlex.quote(str(binary)) + \
            ' || rc=$?; printf "SMOKE=%s\\n" "$UPDATE_LAST_SMOKE_VERDICT"; exit "$rc"'
        output = self.run_update(cross=True, command=command, expected=1,
                                 overrides={"TEST_HOME": str(self.base / "absent-home")})
        self.assertIn("SMOKE=broken", output)
        self.assertEqual(self.events(), [])

    def test_transport_usage_error_cannot_impersonate_an_executed_probe(self):
        binary = self.write_native_tool("claude")
        transport = self.base / "transport-usage"
        transport.write_text("#!/bin/sh\nprintf 'usage: transport (unknown option)\\n' >&2\nexit 1\n")
        transport.chmod(0o755)
        command = "rc=0; update_tool_smoke_check claude " + shlex.quote(str(binary)) + \
            ' || rc=$?; printf "SMOKE=%s\\n" "$UPDATE_LAST_SMOKE_VERDICT"; exit "$rc"'
        output = self.run_update(cross=True, transport="usage", command=command, expected=1)
        self.assertIn("SMOKE=broken", output)
        self.assertEqual(self.events(), [])

    def test_timeout_setup_failure_cannot_impersonate_an_executed_probe(self):
        binary = self.write_native_tool("claude")
        command = "rc=0; UPDATE_SMOKE_TIMEOUT=invalid update_tool_smoke_check claude " + \
            shlex.quote(str(binary)) + \
            ' || rc=$?; printf "SMOKE=%s\\n" "$UPDATE_LAST_SMOKE_VERDICT"; exit "$rc"'
        output = self.run_update(cross=True, command=command, expected=1)
        self.assertIn("SMOKE=broken", output)
        self.assertEqual(self.events(), [])

    def test_genuine_unsupported_probe_keeps_its_distinct_verdict(self):
        binary = self.write_native_tool("claude")
        (self.base / "unsupported-probe-claude").write_text("fixture\n")
        command = "rc=0; update_tool_smoke_check claude " + shlex.quote(str(binary)) + \
            ' || rc=$?; printf "SMOKE=%s\\n" "$UPDATE_LAST_SMOKE_VERDICT"; exit "$rc"'
        output = self.run_update(cross=True, command=command, expected=1)
        self.assertIn("SMOKE=unsupported", output)
        self.assert_target_events(self.events())
        self.assertEqual([e[-1] for e in self.events()], ["--version", "--help", "version"])

    def write_maintenance_tool(self, tool, *, path=None, executable=True):
        path = path or self.home / ".local/bin" / tool
        self.owned_dir(path.parent)
        env_file = self.base / "maintenance-env.tsv"
        if not env_file.exists():
            env_file.write_text("")
            self.own(env_file)
        script = "#!/bin/bash\nset -euo pipefail\n"
        script += "fixture=" + shlex.quote(str(self.base)) + "\ntool=" + shlex.quote(tool) + "\n"
        script += "names=(" + " ".join(MAINTENANCE_ENV_NAMES) + ")\n"
        script += r'''
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tmaintenance\t%s\n' \
    "$tool" "$EUID" "$HOME" "$PWD" "${RUSTUP_HOME-<unset>}" "${CARGO_HOME-<unset>}" \
    "${RUSTUP_TOOLCHAIN-<unset>}" "${RUSTUP_AUTO_INSTALL-<unset>}" "$*" >> "$fixture/events.tsv"
{
    printf '%s' "$tool"
    for name in "${names[@]}"; do printf '\t%s' "${!name-<unset>}"; done
    printf '\n'
} >> "$fixture/maintenance-env.tsv"
if [[ "$tool:$*" == 'gh:extension list' ]]; then
    if [[ -f "$fixture/inventory-failure" ]]; then printf 'fixture inventory denied\n' >&2; exit 19; fi
    if [[ -f "$fixture/inventory-empty" ]]; then printf 'fixture transport warning\n' >&2; exit 0; fi
    printf 'gh fixture-extension org/fixture-extension\n'
    exit 0
fi
if [[ -f "$fixture/fail-$tool" ]]; then printf 'fixture maintenance failure\n' >&2; exit 17; fi
if [[ -f "$fixture/hang-$tool" ]]; then /bin/sleep 5; fi
case "$tool:$*" in
    gh:'extension upgrade --all') destination="${XDG_DATA_HOME:-$HOME/.local/share}/gh/extensions" ;;
    gcloud:'components update --quiet') destination="${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}" ;;
    flywheel-update-agents-md:|fallback-guide:) destination="${ACFS_TARGET_HOME:-$HOME}/.acfs/docs" ;;
    dcg:'install --force')
        destination="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
        case "$destination" in '~') destination="$HOME" ;; '~/'*) destination="$HOME/${destination#\~/}" ;; esac
        ;;
    omz-upgrade:|foreign-omz:) destination="$ZSH" ;;
    *) printf 'Unexpected fixture argv: %s %s\n' "$tool" "$*" >&2; exit 64 ;;
esac
mkdir -p "$destination"
printf '%s\n' "$EUID" > "$destination/maintenance-$tool"
'''
        path.write_text(script)
        path.chmod(0o755 if executable else 0o644)
        self.own(path)
        return path

    def maintenance_env(self):
        path = self.base / "maintenance-env.tsv"
        if not path.exists():
            return []
        return [dict(zip(("tool", *MAINTENANCE_ENV_NAMES), line.split("\t")))
                for line in path.read_text().splitlines()]

    def cloud_command(self):
        # Only package-manager metadata is a fixture; no apt operation is run.
        return 'UPDATE_CLOUD=true; FORCE_MODE=false; dpkg() { return 1; }; update_cloud'

    def hook_command(self):
        # Run the real update_stack dispatch and the real run_cmd for its hook.
        # Every unrelated upstream installer is a no-op, so this cannot contact
        # a provider or install a package on the test host.
        return r'''
UPDATE_STACK=true
declare -A KNOWN_INSTALLERS=()
update_require_security() { return 0; }
get_checksum() { :; }
update_ensure_minisign() { return 0; }
capture_version_before() { :; }
capture_version_after() { return 1; }
update_binary_exists() { [[ "$1" == dcg || "$1" == claude ]]; }
update_run_verified_installer_or_existing_on_transient() { :; }
update_run_verified_installer_with_target_tmpdir_or_existing_on_transient() { :; }
fixture_run_cmd_definition=$(declare -f run_cmd)
eval "${fixture_run_cmd_definition/run_cmd ()/fixture_real_run_cmd ()}"
run_cmd() { if [[ "$1" == 'DCG Hook' ]]; then fixture_real_run_cmd "$@"; fi; }
update_stack
'''

    def test_cloud_updates_use_target_account_storage_and_native_arguments(self):
        self.write_maintenance_tool("gh")
        self.write_maintenance_tool("gcloud")
        output = self.run_update(cross=True, transport="runuser", command=self.cloud_command())
        self.assert_target_events(self.events())
        self.assertEqual([(e[0], e[-1]) for e in self.events()],
                         [("gh", "extension list"), ("gh", "extension upgrade --all"),
                          ("gcloud", "components update --quiet")])
        self.assertIn("COUNTS=2,3,0", output)
        for marker in (self.home / ".local/share/gh/extensions/maintenance-gh",
                       self.home / ".config/gcloud/maintenance-gcloud"):
            self.assertEqual(marker.stat().st_uid, self.account.pw_uid)
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_cross_account_cloud_discards_caller_roots_credentials_and_git_redirects(self):
        self.write_maintenance_tool("gh")
        self.write_maintenance_tool("gcloud")
        overrides = {name: str(self.caller / name) for name in MAINTENANCE_ENV_NAMES
                     if name.startswith(("XDG_", "GH_", "GITHUB_", "CLOUDSDK_", "GIT_"))}
        overrides.update(GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.sshCommand", GIT_CONFIG_VALUE_0="caller-command")
        self.run_update(cross=True, transport="runuser", command=self.cloud_command(), overrides=overrides)
        self.assert_target_events(self.events())
        for event in self.maintenance_env():
            self.assertEqual(event["GH_CONFIG_DIR"], str(self.home / ".config/gh"))
            self.assertEqual(event["CLOUDSDK_CONFIG"], str(self.home / ".config/gcloud"))
            for name, suffix in (("XDG_CONFIG_HOME", ".config"), ("XDG_CACHE_HOME", ".cache"),
                                 ("XDG_DATA_HOME", ".local/share"), ("XDG_STATE_HOME", ".local/state")):
                self.assertEqual(event[name], str(self.home / suffix), event)
            for name in overrides:
                if name not in ("GH_CONFIG_DIR", "CLOUDSDK_CONFIG", "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
                                "XDG_DATA_HOME", "XDG_STATE_HOME", "GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0"):
                    self.assertEqual(event[name], "<unset>", (name, event))
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_same_account_cloud_preserves_custom_paths_and_credentials(self):
        self.write_maintenance_tool("gh")
        self.write_maintenance_tool("gcloud")
        absolute_config = self.work / "absolute gh"
        owner_markers = {name: f"fixture-{self.base.name}-{name}"
                         for name in ("GH_TOKEN", "CLOUDSDK_AUTH_ACCESS_TOKEN")}
        credential_file = str(Path("credentials") / f"{self.base.name}.json")
        overrides = {"GH_CONFIG_DIR": str(absolute_config), "CLOUDSDK_CONFIG": "custom gcloud",
                     "XDG_CONFIG_HOME": "custom config", "XDG_CACHE_HOME": str(self.work / "absolute cache"),
                     "XDG_DATA_HOME": "custom data", "XDG_STATE_HOME": "custom state",
                     **owner_markers,
                     "CLOUDSDK_AUTH_ACCESS_TOKEN_FILE": "credentials/access-token",
                     "CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE": credential_file,
                     "CLOUDSDK_PYTHON": "runtime/bin/python", "GIT_CONFIG_GLOBAL": ".git/owner-config"}
        self.run_update(command=self.cloud_command(), overrides=overrides)
        self.assert_target_events(self.events())
        for event in self.maintenance_env():
            for name, value in overrides.items():
                if name in ("GH_TOKEN", "CLOUDSDK_AUTH_ACCESS_TOKEN", "GIT_CONFIG_GLOBAL"):
                    expected = value
                else:
                    expected = value if value.startswith("/") else str(self.work / value)
                self.assertEqual(event[name], expected, (name, event))
        self.assertTrue((self.work / "custom data/gh/extensions/maintenance-gh").is_file())
        self.assertTrue((self.work / "custom gcloud/maintenance-gcloud").is_file())

    def test_same_account_cloud_keeps_bare_interpreter_name(self):
        self.write_maintenance_tool("gcloud")
        self.run_update(command=self.cloud_command(), overrides={"CLOUDSDK_PYTHON": "python3"})
        self.assert_target_events(self.events())
        self.assertEqual(self.maintenance_env()[0]["CLOUDSDK_PYTHON"], "python3")

    def test_failed_github_inventory_is_not_an_empty_success(self):
        self.write_maintenance_tool("gh")
        (self.base / "inventory-failure").write_text("fixture\n")
        output = self.run_update(cross=True, command=self.cloud_command())
        self.assert_target_events(self.events())
        self.assertEqual([e[-1] for e in self.events()], ["extension list"])
        self.assertIn("COUNTS=0,4,1", output)
        self.assertIn("fixture inventory denied", output)
        self.assertIn("extension inventory failed (exit 19)", (self.base / "update.log").read_text())
        self.assertNotIn("no extensions to update", (self.base / "update.log").read_text())

    def test_github_inventory_stderr_does_not_create_an_extension(self):
        self.write_maintenance_tool("gh")
        (self.base / "inventory-empty").write_text("fixture\n")
        output = self.run_update(cross=True, command=self.cloud_command())
        self.assert_target_events(self.events())
        self.assertEqual([e[-1] for e in self.events()], ["extension list"])
        self.assertIn("fixture transport warning", output)
        self.assertIn("COUNTS=1,4,0", output)

    def test_cloud_dry_run_lists_extensions_without_mutating(self):
        self.write_maintenance_tool("gh")
        self.write_maintenance_tool("gcloud")
        self.run_update(cross=True, dry_run=True, command=self.cloud_command())
        self.assert_target_events(self.events())
        self.assertEqual([(e[0], e[-1]) for e in self.events()], [("gh", "extension list")])
        self.assertFalse((self.home / ".local/share/gh").exists())
        self.assertFalse((self.home / ".config/gcloud").exists())

    def test_cloud_transport_refusal_never_runs_provider_as_caller(self):
        self.write_maintenance_tool("gh")
        self.write_maintenance_tool("gcloud")
        output = self.run_update(cross=True, transport="none", command=self.cloud_command())
        self.assertEqual(self.events(), [])
        self.assertIn("COUNTS=0,3,2", output)
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_cloud_native_timeout_and_failure_are_counted(self):
        self.write_maintenance_tool("gh")
        self.write_maintenance_tool("gcloud")
        (self.base / "fail-gh").write_text("fixture\n")
        (self.base / "hang-gcloud").write_text("fixture\n")
        output = self.run_update(cross=True, timeout="0.1", command=self.cloud_command())
        self.assert_target_events(self.events())
        self.assertIn("COUNTS=0,3,2", output)
        log = (self.base / "update.log").read_text()
        self.assertIn("Failed: GitHub CLI extensions (exit code: 17)", log)
        self.assertIn("Failed: Google Cloud SDK (exit code: 124)", log)

    def test_guide_overrides_caller_target_hints_and_uses_selected_account(self):
        self.write_maintenance_tool("flywheel-update-agents-md")
        self.run_update(cross=True, transport="runuser", command="update_root_agents_md",
                        overrides={"ACFS_TARGET_USER": "root", "ACFS_TARGET_HOME": str(self.caller), "SUDO_USER": "root"})
        self.assert_target_events(self.events())
        event = self.maintenance_env()[0]
        self.assertEqual(event["ACFS_TARGET_USER"], self.account.pw_name)
        self.assertEqual(event["ACFS_TARGET_HOME"], str(self.home))
        self.assertEqual((self.home / ".acfs/docs/maintenance-flywheel-update-agents-md").stat().st_uid,
                         self.account.pw_uid)
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_guide_nonexecutable_fallback_needs_no_global_link_repair(self):
        self.write_maintenance_tool("fallback-guide", path=self.home / ".acfs/bin/flywheel-update-agents-md", executable=False)
        # Exercise fallback selection even on a host with a legitimate
        # system-wide guide command. Installed-command precedence is covered
        # independently below; the real fallback resolver/runner stays active.
        command = 'update_binary_path() { return 1; }; run_cmd_sudo() { printf "UNEXPECTED-GLOBAL-LINK\\n"; return 97; }; update_root_agents_md'
        output = self.run_update(cross=True, command=command)
        self.assert_target_events(self.events())
        self.assertEqual([e[0] for e in self.events()], ["fallback-guide"])
        self.assertNotIn("UNEXPECTED-GLOBAL-LINK", output)
        self.assertTrue((self.home / ".acfs/docs/maintenance-fallback-guide").is_file())

    def test_guide_installed_command_precedes_repository_fallback(self):
        self.write_maintenance_tool("flywheel-update-agents-md")
        repo = self.base / "repo"
        self.write_maintenance_tool("fallback-guide", path=repo / "scripts/generate-root-agents-md.sh")
        self.run_update(cross=True, command="update_root_agents_md", overrides={"ACFS_REPO_ROOT": str(repo)})
        self.assert_target_events(self.events())
        self.assertEqual([e[0] for e in self.events()], ["flywheel-update-agents-md"])

    def test_guide_and_hook_dry_run_never_execute_payloads(self):
        self.write_maintenance_tool("flywheel-update-agents-md")
        self.write_maintenance_tool("dcg")
        self.run_update(cross=True, dry_run=True, command="update_root_agents_md; " + self.hook_command())
        self.assertEqual(self.events(), [])
        self.assertFalse((self.home / ".acfs/docs").exists())
        self.assertFalse((self.home / ".claude").exists())

    def test_hook_registration_discards_cross_account_claude_override(self):
        self.write_maintenance_tool("dcg")
        self.run_update(cross=True, transport="runuser", command=self.hook_command(),
                        overrides={"CLAUDE_CONFIG_DIR": str(self.caller / "claude")})
        self.assert_target_events(self.events())
        self.assertEqual([e[-1] for e in self.events()], ["install --force"])
        self.assertEqual(self.maintenance_env()[0]["CLAUDE_CONFIG_DIR"], "<unset>")
        self.assertEqual((self.home / ".claude/maintenance-dcg").stat().st_uid, self.account.pw_uid)
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_hook_registration_preserves_same_account_relative_directory(self):
        self.write_maintenance_tool("dcg")
        self.run_update(command=self.hook_command(), overrides={"CLAUDE_CONFIG_DIR": "custom claude"})
        self.assert_target_events(self.events())
        self.assertEqual(self.maintenance_env()[0]["CLAUDE_CONFIG_DIR"], str(self.work / "custom claude"))
        self.assertTrue((self.work / "custom claude/maintenance-dcg").is_file())

    def test_hook_registration_preserves_same_account_tilde_directory(self):
        self.write_maintenance_tool("dcg")
        self.run_update(command=self.hook_command(), overrides={"CLAUDE_CONFIG_DIR": "~/custom claude"})
        self.assert_target_events(self.events())
        self.assertEqual(self.maintenance_env()[0]["CLAUDE_CONFIG_DIR"], str(self.home / "custom claude"))
        self.assertTrue((self.home / "custom claude/maintenance-dcg").is_file())

    def write_service_fixture(self):
        path = self.home / ".acfs/scripts/lib/acfs-services.sh"
        self.owned_dir(path.parent)
        environment = self.base / "service-env.tsv"
        self.write_input(environment, "")
        script = "#!/bin/bash\nset -euo pipefail\nfixture=" + shlex.quote(str(self.base)) + "\n"
        script += r'''
printf 'services\t%s\t%s\t%s\t%s\n' "$EUID" "$HOME" "$PWD" "$*" >> "$fixture/events.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${XDG_RUNTIME_DIR-<unset>}" \
    "${DBUS_SESSION_BUS_ADDRESS-<unset>}" "${TMUX-<unset>}" "${TMUX_PANE-<unset>}" \
    "${TMUX_TMPDIR-<unset>}" "${BASH_ENV-<unset>}" "$PATH" "${ACFS_BIN_DIR-<unset>}" >> "$fixture/service-env.tsv"
case "$1" in
    drift)
        if [[ -f "$fixture/service-drift-hang" ]]; then /bin/sleep 10; fi
        if [[ -f "$HOME/.service-restarted-cm" ]]; then
            printf 'cm|ok|installed executable\n'
        else
            printf 'cm|stale|previous executable\n'
        fi
        printf 'cass|stale|previous executable\n'
        exit 1
        ;;
    restart)
        [[ "$2" == cm ]] || exit 64
        [[ ! -f "$fixture/service-restart-failure" ]] || exit 19
        printf '%s\n' "$EUID" > "$HOME/.service-restarted-cm"
        ;;
    *) exit 64 ;;
esac
'''
        self.write_input(path, script)
        path.chmod(0o755)
        return path

    def service_environment_overrides(self):
        return {
            "XDG_RUNTIME_DIR": str(self.caller / "runtime"),
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(self.caller / "runtime/bus"),
            "TMUX": str(self.caller / "tmux-socket") + ",123,0",
            "TMUX_PANE": "%7",
            "TMUX_TMPDIR": str(self.caller / "tmux"),
            "ACFS_BIN_DIR": str(self.caller / ".local/bin"),
        }

    def assert_service_environment(self):
        runtime = Path(f"/run/user/{self.account.pw_uid}")
        runtime_safe = runtime.is_dir() and not runtime.is_symlink() and runtime.stat().st_uid == self.account.pw_uid
        bus = runtime / "bus"
        bus_safe = runtime_safe and bus.is_socket() and not bus.is_symlink() and bus.stat().st_uid == self.account.pw_uid
        expected = [str(runtime) if runtime_safe else "<unset>",
                    f"unix:path={bus}" if bus_safe else "<unset>",
                    "<unset>", "<unset>", "<unset>", "<unset>"]
        rows = (self.base / "service-env.tsv").read_text().splitlines()
        self.assertTrue(rows)
        for row in rows:
            values = row.split("\t")
            self.assertEqual(values[:6], expected)
            self.assertTrue(values[6].startswith(str(self.home / ".local/bin") + ":"))
            self.assertNotIn(str(self.caller), values[6])
            self.assertNotIn(str(self.work), values[6])
            self.assertEqual(values[7], str(self.home / ".local/bin"))

    def test_service_drift_report_uses_target_context_without_automatic_restart(self):
        self.write_service_fixture()
        output = self.run_update(command="update_report_service_binary_drift",
                                 overrides=self.service_environment_overrides())
        self.assert_target_events(self.events())
        self.assert_service_environment()
        self.assertEqual([event[-1] for event in self.events()], ["drift --robot"])
        self.assertIn("cm: previous executable", output)
        self.assertFalse((self.home / ".service-restarted-cm").exists())
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_service_drift_ignores_caller_bash_and_shell_startup(self):
        self.write_service_fixture()
        caller_bin = self.work / "caller-bin"
        self.owned_dir(caller_bin)
        self.write_input(caller_bin / "bash",
                         '#!/bin/sh\nprintf called > "$TEST_ROOT/caller-bash-executed"\nexit 97\n')
        (caller_bin / "bash").chmod(0o755)
        self.write_input(self.base / "caller-bash-env",
                         'printf called > "$TEST_ROOT/caller-startup-executed"\n')
        command = r'''
export BASH_ENV="$TEST_ROOT/caller-bash-env"
export PATH="$TEST_ROOT/working directory/caller-bin:$PATH"
update_report_service_binary_drift
'''
        self.run_update(command=command, overrides=self.service_environment_overrides())
        self.assert_target_events(self.events())
        self.assert_service_environment()
        self.assertFalse((self.base / "caller-bash-executed").exists())
        self.assertFalse((self.base / "caller-startup-executed").exists())

    def test_service_command_enforces_deadline_in_target_account(self):
        self.write_service_fixture()
        self.write_input(self.base / "service-drift-hang", "fixture\n")
        self.run_update(command='update_run_service_command 0.2 "$TEST_HOME/.acfs/scripts/lib/acfs-services.sh" drift --robot',
                        expected=124)
        self.assert_target_events(self.events())
        self.assert_service_environment()
        self.assertEqual([event[-1] for event in self.events()], ["drift --robot"])

    def test_service_drift_opt_in_restart_and_confirmation_share_target_context(self):
        self.write_service_fixture()
        output = self.run_update(command="update_report_service_binary_drift",
                                 overrides=self.service_environment_overrides() | {
                                     "ACFS_UPDATE_RESTART_SERVICES": "cm,cm",
                                 })
        self.assert_target_events(self.events())
        self.assert_service_environment()
        self.assertEqual([event[-1] for event in self.events()],
                         ["drift --robot", "restart cm", "drift --robot"])
        self.assertIn("Restarted cm; it now runs the installed binary", output)
        self.assertEqual((self.home / ".service-restarted-cm").stat().st_uid, self.account.pw_uid)
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_cross_account_service_drift_never_executes_as_privileged_caller(self):
        self.write_service_fixture()
        output = self.run_update(cross=True, transport="runuser", command="update_report_service_binary_drift",
                                 overrides=self.service_environment_overrides() | {
                                     "ACFS_UPDATE_RESTART_SERVICES": "cm",
                                 })
        self.assert_target_events(self.events())
        self.assert_service_environment()
        self.assertEqual([event[-1] for event in self.events()],
                         ["drift --robot", "restart cm", "drift --robot"])
        self.assertIn("Restarted cm; it now runs the installed binary", output)
        self.assertEqual((self.home / ".service-restarted-cm").stat().st_uid, self.account.pw_uid)
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_service_drift_transport_refusal_never_falls_back_to_caller(self):
        self.write_service_fixture()
        self.run_update(cross=True, transport="none", command="update_report_service_binary_drift",
                        overrides={"ACFS_UPDATE_RESTART_SERVICES": "cm"})
        self.assertEqual(self.events(), [])
        self.assertFalse((self.home / ".service-restarted-cm").exists())
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_service_drift_dry_run_never_executes_service_script(self):
        self.write_service_fixture()
        self.run_update(dry_run=True, command="update_report_service_binary_drift",
                        overrides={"ACFS_UPDATE_RESTART_SERVICES": "cm"})
        self.assertEqual(self.events(), [])
        self.assertFalse((self.home / ".service-restarted-cm").exists())

    def test_service_drift_restart_failure_is_reported_without_confirmation(self):
        self.write_service_fixture()
        self.write_input(self.base / "service-restart-failure", "fixture\n")
        output = self.run_update(command="update_report_service_binary_drift",
                                 overrides={"ACFS_UPDATE_RESTART_SERVICES": "cm"})
        self.assert_target_events(self.events())
        self.assertEqual([event[-1] for event in self.events()], ["drift --robot", "restart cm"])
        self.assertIn("Restart of cm failed (exit 19)", output)
        self.assertNotIn("Restarted cm;", output)
        self.assertFalse((self.home / ".service-restarted-cm").exists())

    def test_guide_and_hook_refuse_missing_account_transport(self):
        self.write_maintenance_tool("flywheel-update-agents-md")
        self.write_maintenance_tool("dcg")
        self.run_update(cross=True, transport="none", command="update_root_agents_md; " + self.hook_command())
        self.assertEqual(self.events(), [])
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_unresolvable_home_refuses_selected_cloud_and_guide_payloads(self):
        self.write_maintenance_tool("gh")
        self.write_maintenance_tool("flywheel-update-agents-md")
        # Keep discovery positive while passwd/explicit home validation fails.
        # The execution boundary must refuse even an already-selected payload.
        command = r'''
update_binary_path() {
    case "$1" in
        gh|flywheel-update-agents-md) printf '%s\n' "$TEST_ROOT/target-home/.local/bin/$1" ;;
        *) return 1 ;;
    esac
}
''' + self.cloud_command() + '; update_root_agents_md; update_omz'
        output = self.run_update(cross=True, command=command,
                                 overrides={"TEST_HOME": str(self.base / "absent-home"),
                                            "TARGET_HOME": str(self.base / "absent-home")})
        self.assertEqual(self.events(), [])
        self.assertIn("COUNTS=0,5,2", output)
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_shell_upgrade_uses_target_installation_not_callers_zsh(self):
        omz = self.home / ".oh-my-zsh"
        self.write_maintenance_tool("omz-upgrade", path=omz / "tools/upgrade.sh")
        foreign = self.caller / "foreign-shell"
        self.write_maintenance_tool("foreign-omz", path=foreign / "tools/upgrade.sh")
        caller_markers = {name: f"fixture-{self.base.name}-{name}" for name in
                          ("GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN")}
        self.run_update(cross=True, transport="runuser", command="update_omz",
                        overrides={"ZSH": str(foreign), "ZSH_CUSTOM": str(foreign / "custom"),
                                   "ZSH_CACHE_DIR": str(self.caller / "cache"), "ZDOTDIR": str(self.caller),
                                   "GH_CONFIG_DIR": str(self.caller / "gh"), "GH_HOST": "caller-host.invalid",
                                   **caller_markers})
        self.assert_target_events(self.events())
        self.assertEqual([e[0] for e in self.events()], ["omz-upgrade"])
        event = self.maintenance_env()[0]
        self.assertEqual(event["ZSH"], str(omz))
        self.assertEqual(event["ZSH_CUSTOM"], str(omz / "custom"))
        self.assertEqual(event["DISABLE_UPDATE_PROMPT"], "true")
        self.assertEqual(event["ZDOTDIR"], "<unset>")
        self.assertEqual(event["ZSH_CACHE_DIR"], "<unset>")
        self.assertEqual(event["GH_CONFIG_DIR"], str(self.home / ".config/gh"))
        for name in ("GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN", "GH_HOST"):
            self.assertEqual(event[name], "<unset>", (name, event))
        self.assertFalse((foreign / "maintenance-foreign-omz").exists())

    def test_same_account_shell_preserves_relative_omz_and_custom_paths(self):
        omz = self.work / "custom omz"
        self.write_maintenance_tool("omz-upgrade", path=omz / "tools/upgrade.sh", executable=False)
        self.run_update(command="update_omz", overrides={"ZSH": "custom omz", "ZSH_CUSTOM": "custom plugins"})
        self.assert_target_events(self.events())
        event = self.maintenance_env()[0]
        self.assertEqual(event["ZSH"], str(omz))
        self.assertEqual(event["ZSH_CUSTOM"], str(self.work / "custom plugins"))
        self.assertTrue((omz / "maintenance-omz-upgrade").is_file())

    def test_same_account_shell_preserves_absolute_omz_and_custom_paths(self):
        omz, custom = self.work / "absolute omz", self.work / "absolute custom"
        self.write_maintenance_tool("omz-upgrade", path=omz / "tools/upgrade.sh")
        owner_marker = f"fixture-{self.base.name}-owner-gh"
        self.run_update(command="update_omz", overrides={"ZSH": str(omz), "ZSH_CUSTOM": str(custom),
                        "GH_CONFIG_DIR": ".git/owner-gh-config", "GH_TOKEN": owner_marker})
        self.assert_target_events(self.events())
        event = self.maintenance_env()[0]
        self.assertEqual(event["ZSH"], str(omz))
        self.assertEqual(event["ZSH_CUSTOM"], str(custom))
        self.assertEqual(event["GH_CONFIG_DIR"], ".git/owner-gh-config")
        self.assertEqual(event["GH_TOKEN"], owner_marker)

    def test_shell_upgrade_keeps_native_deadline_and_failure_status(self):
        self.write_maintenance_tool("omz-upgrade", path=self.home / ".oh-my-zsh/tools/upgrade.sh")
        (self.base / "hang-omz-upgrade").write_text("fixture\n")
        output = self.run_update(cross=True, timeout="0.1", command="update_omz")
        self.assert_target_events(self.events())
        self.assertIn("COUNTS=0,0,1", output)
        self.assertIn("Failed: Oh-My-Zsh upgrade (exit code: 124)", (self.base / "update.log").read_text())
        self.assertFalse((self.home / ".oh-my-zsh/maintenance-omz-upgrade").exists())

    def test_shell_upgrade_dry_run_and_missing_transport_do_not_execute(self):
        self.write_maintenance_tool("omz-upgrade", path=self.home / ".oh-my-zsh/tools/upgrade.sh")
        self.run_update(cross=True, dry_run=True, command="update_omz")
        self.assertEqual(self.events(), [])
        output = self.run_update(cross=True, transport="none", command="update_omz")
        self.assertEqual(self.events(), [])
        self.assertIn("COUNTS=0,0,1", output)

    def fixture_git(self, *args, cwd=None):
        template = self.artifacts / "empty-git-template"
        self.owned_dir(template)
        env = {"PATH": "/usr/bin:/bin", "HOME": str(self.home), "GIT_CONFIG_NOSYSTEM": "1",
               "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TEMPLATE_DIR": str(template),
               "GIT_AUTHOR_NAME": "ACFS fixture", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
               "GIT_COMMITTER_NAME": "ACFS fixture", "GIT_COMMITTER_EMAIL": "fixture@example.invalid"}
        kwargs = {}
        if os.geteuid() == 0:
            kwargs.update(user=self.account.pw_uid, group=self.account.pw_gid, extra_groups=[])
        result = subprocess.run(["/usr/bin/git", *args], cwd=cwd or self.home,
                                env=env, text=True, capture_output=True, timeout=10, **kwargs)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.strip()

    def prepare_shell_git_repos(self, *, custom=False, with_omz=True, with_plugin=True):
        publisher = self.base / "local-upstream"
        self.owned_dir(publisher)
        self.fixture_git("init", "-q", "-b", "main", str(publisher))
        payload = publisher / "fixture.txt"
        payload.write_text("first fixture revision\n")
        self.own(payload)
        self.fixture_git("add", "fixture.txt", cwd=publisher)
        self.fixture_git("commit", "-qm", "first fixture revision", cwd=publisher)
        self.fixture_git("tag", "fixture-v1", cwd=publisher)
        omz = (self.work / "custom omz") if custom else (self.home / ".oh-my-zsh")
        custom_dir = (self.work / "custom plugins") if custom else (omz / "custom")
        repos = [custom_dir / "themes/powerlevel10k"]
        if with_omz:
            repos.insert(0, omz)
        if with_plugin:
            repos.append(custom_dir / "plugins/zsh-autosuggestions")
        git_events = self.base / "git-events.tsv"
        git_events.write_text("")
        self.own(git_events)
        for path in repos:
            self.owned_dir(path)
            self.fixture_git("clone", "-q", "--no-hardlinks", str(publisher), str(path))
            hook = path / ".git/hooks/post-merge"
            self.owned_dir(hook.parent)
            hook.write_text("#!/bin/bash\nprintf '%s\\t%s\\t%s\\n' \"$EUID\" \"$HOME\" \"$PWD\" >> " +
                            shlex.quote(str(git_events)) + "\n")
            hook.chmod(0o755)
            self.own(hook)
        payload.write_text("second fixture revision\n")
        self.fixture_git("commit", "-qam", "second fixture revision", cwd=publisher)
        self.fixture_git("tag", "fixture-v2", cwd=publisher)
        return publisher, omz, custom_dir, repos

    def git_events(self):
        return [line.split("\t") for line in (self.base / "git-events.tsv").read_text().splitlines()]

    def test_cross_account_shell_git_updates_and_metadata_use_target_repositories(self):
        publisher, omz, custom, repos = self.prepare_shell_git_repos()
        overrides = {"ZSH": str(self.caller / "foreign omz"), "ZSH_CUSTOM": str(self.caller / "foreign custom"),
                     "GIT_DIR": str(publisher / ".git"), "GIT_WORK_TREE": str(publisher),
                     "GIT_CONFIG_GLOBAL": str(self.caller / "wrong-git-config"), "GIT_SSH_COMMAND": "wrong-caller-command"}
        command = 'printf "BEFORE=%s,%s\\n" "$(get_version omz)" "$(get_version p10k)"; ' \
                  'update_omz; update_p10k; update_zsh_plugins; ' \
                  'printf "AFTER=%s,%s\\n" "$(get_version omz)" "$(get_version p10k)"'
        output = self.run_update(cross=True, transport="runuser", command=command, overrides=overrides)
        self.assertIn("BEFORE=fixture-v1,fixture-v1", output)
        self.assertIn("AFTER=fixture-v2,fixture-v2", output)
        self.assertIn("COUNTS=3,0,0", output)
        self.assertEqual(self.git_events(), [[str(self.account.pw_uid), str(self.home), str(path)] for path in repos])
        expected = self.fixture_git("rev-parse", "HEAD", cwd=publisher)
        for path in repos:
            self.assertEqual(self.fixture_git("rev-parse", "HEAD", cwd=path), expected)
            self.assertEqual((path / "fixture.txt").stat().st_uid, self.account.pw_uid)
        # Neither dry-run nor a failed account transition may replay a pull.
        self.run_update(cross=True, dry_run=True, command="update_omz; update_p10k; update_zsh_plugins")
        self.run_update(cross=True, transport="none", command="update_omz; update_p10k; update_zsh_plugins")
        self.assertEqual(len(self.git_events()), len(repos))

    def test_same_account_custom_git_paths_ignore_ambient_repository_redirects(self):
        publisher, omz, custom, repos = self.prepare_shell_git_repos(custom=True, with_plugin=False)
        overrides = {"ZSH": "custom omz", "ZSH_CUSTOM": "custom plugins",
                     "GIT_DIR": str(publisher / ".git"), "GIT_WORK_TREE": str(publisher),
                     "GIT_INDEX_FILE": str(self.caller / "unrelated-index"),
                     "GIT_OBJECT_DIRECTORY": str(self.caller / "unrelated-objects"),
                     "GIT_CONFIG_GLOBAL": ".git/config"}
        command = 'printf "BEFORE=%s,%s\\n" "$(get_version omz)" "$(get_version p10k)"; update_omz; update_p10k'
        output = self.run_update(command=command, overrides=overrides)
        self.assertIn("BEFORE=fixture-v1,fixture-v1", output)
        self.assertIn("COUNTS=2,0,0", output)
        self.assertEqual(self.git_events(), [[str(self.account.pw_uid), str(self.home), str(path)] for path in repos])
        self.assertFalse((self.caller / "unrelated-index").exists())
        self.assertFalse((self.caller / "unrelated-objects").exists())

    def test_shell_git_fast_forward_refusal_is_skip_and_other_failure_is_failure(self):
        _, _, _, repos = self.prepare_shell_git_repos(with_omz=False, with_plugin=False)
        path = repos[0]
        local_file = path / "local.txt"
        local_file.write_text("local user work\n")
        self.own(local_file)
        self.fixture_git("add", "local.txt", cwd=path)
        self.fixture_git("commit", "-qm", "local user work", cwd=path)
        before = self.fixture_git("rev-parse", "HEAD", cwd=path)
        output = self.run_update(command="update_p10k")
        self.assertIn("COUNTS=0,1,0", output)
        self.assertEqual(self.fixture_git("rev-parse", "HEAD", cwd=path), before)
        self.assertEqual(local_file.read_text(), "local user work\n")
        self.assertEqual(self.git_events(), [])
        self.fixture_git("remote", "set-url", "origin", str(self.base / "missing-local-origin"), cwd=path)
        output = self.run_update(command="update_p10k")
        self.assertIn("COUNTS=0,0,1", output)
        self.assertEqual(self.fixture_git("rev-parse", "HEAD", cwd=path), before)

    def test_shell_explicit_deadline_argv_runs_inside_target_account(self):
        self.write_maintenance_tool("omz-upgrade", path=self.home / ".oh-my-zsh/tools/upgrade.sh")
        theme = self.home / ".oh-my-zsh/custom/themes/powerlevel10k"
        self.owned_dir(theme / ".git")
        records = self.base / "timeouts.tsv"
        records.write_text("")
        self.own(records)
        wrapper = self.base / "record-timeout"
        wrapper.write_text("#!/bin/bash\nprintf '%s\\t%s\\t%s\\n' \"$EUID\" \"$HOME\" \"$*\" >> " +
                           shlex.quote(str(records)) + '\nexec /usr/bin/timeout "$@"\n')
        wrapper.chmod(0o755)
        command = r'''
fixture_system_path_definition=$(declare -f update_system_binary_path)
eval "${fixture_system_path_definition/update_system_binary_path ()/fixture_system_path ()}"
update_system_binary_path() {
    if [[ "$1" == timeout ]]; then printf '%s\n' "$TEST_ROOT/record-timeout";
    else fixture_system_path "$@"; fi
}
update_omz
update_p10k
'''
        self.run_update(cross=True, command=command)
        rows = [line.split("\t") for line in records.read_text().splitlines()]
        self.assertTrue(rows)
        for row in rows:
            self.assertEqual(row[:2], [str(self.account.pw_uid), str(self.home)])
        self.assertTrue(any(row[2].startswith("120 ") for row in rows), rows)
        self.assertTrue(any(row[2].startswith("60 ") for row in rows), rows)
        self.assertTrue(any(row[2].startswith("--kill-after=30s 5 ") for row in rows), rows)

    def nvm_wrapper_handoff(self, *, foreign_caller, extra_selectors=()):
        wrapper = Path(os.environ.get("ACFS_UPDATE_TEST_WRAPPER", ROOT / "scripts/acfs-update")).read_text()
        entrypoint = 'main "$@"\n'
        self.assertTrue(wrapper.endswith(entrypoint))
        # Load the complete real wrapper without its final main call so this
        # unit case can invoke the account-handoff boundary directly. Account
        # identity and privileged transport are fixtures, not real UID changes;
        # env construction and execution remain the production implementation.
        module = self.base / "wrapper-functions.sh"
        self.write_input(module, wrapper[:-len(entrypoint)])
        transport = self.base / "fixture-account-transport"
        self.write_input(transport, r'''#!/bin/bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|-H|--) shift ;;
        -u) [[ "$2" == "$TEST_USER" ]] || exit 64; shift 2 ;;
        *) break ;;
    esac
done
exec "$@"
''')
        transport.chmod(0o755)
        selectors = (
            "NVM_DIR", "NVM_BIN", "NVM_INC", "NVM_CD_FLAGS",
            "NVM_NODEJS_ORG_MIRROR", "NVM_IOJS_ORG_MIRROR", "NVM_AUTH_HEADER",
            "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_RUNTIME_DIR",
            "NPM_CONFIG_USERCONFIG", "npm_config_userconfig", "NPM_CONFIG_GLOBALCONFIG", "npm_config_globalconfig",
            "NPM_CONFIG_CACHE", "npm_config_cache", "NPM_CONFIG_PREFIX", "npm_config_prefix",
            "PREFIX", "NODE_OPTIONS", "NODE_PATH", "BASH_ENV", "ENV",
        )
        configured = {name: str(self.caller / name) for name in (*selectors, *extra_selectors)}
        env = configured | {
            "PATH": "/usr/bin:/bin", "HOME": str(self.home), "TARGET_HOME": str(self.home),
            "TEST_ROOT": str(self.base), "TEST_USER": self.account.pw_name,
            "TEST_CALLER": "foreign-caller" if foreign_caller else self.account.pw_name,
            "ACFS_STATE_FILE": "", "ACFS_SYSTEM_STATE_FILE": str(self.base / "no-system-state"),
            "ACFS_HOME": "", "ACFS_BIN_DIR": "", "ACFS_KEEP_FIXTURE": "preserved",
        }
        body = r'''
source "$TEST_ROOT/wrapper-functions.sh"
resolve_current_user() { printf '%s\n' "$TEST_CALLER"; }
system_binary_path() {
    if [[ "$1" == sudo || "$1" == runuser ]]; then
        printf '%s\n' "$TEST_ROOT/fixture-account-transport"
        return 0
    fi
    local candidate
    for candidate in "/usr/bin/$1" "/bin/$1" "/usr/sbin/$1" "/sbin/$1"; do
        if [[ -x "$candidate" ]]; then printf '%s\n' "$candidate"; return 0; fi
    done
    return 1
}
exec_as_target_user "$TEST_USER" /usr/bin/env
'''
        result = subprocess.run(["/bin/bash", "--noprofile", "--norc", "-p", "-c", body],
                                env=env, cwd=self.work, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        observed = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
        self.assertEqual(observed["HOME"], str(self.home))
        self.assertEqual(observed["ACFS_KEEP_FIXTURE"], "preserved")
        return configured, observed

    def test_nvm_public_handoff_discards_foreign_selectors_before_identity_changes(self):
        configured, observed = self.nvm_wrapper_handoff(foreign_caller=True)
        for name in configured:
            self.assertNotIn(name, observed, name)

    def test_nvm_public_handoff_preserves_same_account_selectors(self):
        configured, observed = self.nvm_wrapper_handoff(foreign_caller=False)
        for name, value in configured.items():
            self.assertEqual(observed.get(name), value, name)

    def test_public_handoff_discards_caller_agent_mail_and_bun_stores(self):
        configured, observed = self.nvm_wrapper_handoff(
            foreign_caller=True, extra_selectors=UPDATE_ACCOUNT_ENV_NAMES)
        for name in configured:
            self.assertNotIn(name, observed, name + " crossed the account boundary")

    def test_public_handoff_preserves_own_agent_mail_and_bun_stores(self):
        configured, observed = self.nvm_wrapper_handoff(
            foreign_caller=False, extra_selectors=UPDATE_ACCOUNT_ENV_NAMES)
        for name, value in configured.items():
            self.assertEqual(observed.get(name), value, name)

    def test_direct_target_runner_discards_caller_agent_mail_and_bun_stores(self):
        # Exercise the production runner even on unprivileged CI hosts. Only
        # account identity and runuser transport are fixtures; real env applies
        # the handoff policy before an inert account-owned writer runs. This
        # proves routing, not the OS's ability to change UID.
        transport = self.base / "fixture-account-transport"
        transport.write_text(r'''#!/bin/bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|-H|--) shift ;;
        -u) [[ "$2" == "$TEST_USER" ]] || exit 64; shift 2 ;;
        *) break ;;
    esac
done
exec "$@"
''')
        transport.chmod(0o755)
        probe = self.base / "account-store-probe.py"
        probe.write_text(
            "import json, os\nfrom pathlib import Path\n"
            "home = Path(os.environ['HOME'])\n"
            "defaults = {'BUN_INSTALL_GLOBAL_DIR': '.bun/install/global', "
            "'CLAUDE_CONFIG_DIR': '.claude', 'CODEX_HOME': '.codex', "
            "'STORAGE_ROOT': 'mcp_agent_mail/storage'}\n"
            "for name, relative in defaults.items():\n"
            "    destination = Path(os.environ.get(name, home / relative))\n"
            "    destination.mkdir(parents=True, exist_ok=True)\n"
            "    (destination / 'updated').write_text('target update\\n')\n"
            "print(json.dumps(dict(os.environ)))\n")
        overrides = {name: str(self.caller / name) for name in UPDATE_ACCOUNT_ENV_NAMES}
        output = self.run_update(overrides=overrides, command=r'''
update_current_user() { printf 'foreign-caller\n'; }
update_system_binary_path() {
    if [[ "$1" == sudo || "$1" == runuser ]]; then
        printf '%s\n' "$TEST_ROOT/fixture-account-transport"
        return 0
    fi
    local candidate
    for candidate in "/usr/bin/$1" "/bin/$1" "/usr/sbin/$1" "/sbin/$1"; do
        if [[ -x "$candidate" ]]; then printf '%s\n' "$candidate"; return 0; fi
    done
    return 1
}
update_run_in_target_context "" /usr/bin/python3 "$TEST_ROOT/account-store-probe.py"
''')
        observed = json.loads(output.splitlines()[0])
        for name in UPDATE_ACCOUNT_ENV_NAMES:
            self.assertNotIn(name, observed, name + " crossed the account boundary")
        self.assertEqual(observed["BUN_INSTALL"], str(self.home / ".bun"))
        self.assertEqual(list(self.caller.iterdir()), [])
        for relative in (".bun/install/global", ".claude", ".codex", "mcp_agent_mail/storage"):
            self.assertEqual((self.home / relative / "updated").read_text(), "target update\n")

    def test_direct_target_runner_preserves_same_account_agent_mail_and_bun_stores(self):
        overrides = {name: str(self.work / ("custom " + name)) for name in UPDATE_ACCOUNT_ENV_NAMES}
        output = self.run_update(overrides=overrides, command=r'''
update_run_in_target_context "" /usr/bin/python3 -c 'import json, os; print(json.dumps(dict(os.environ)))'
''')
        observed = json.loads(output.splitlines()[0])
        for name, value in overrides.items():
            self.assertEqual(observed.get(name), value, name)

class AgentPackageDeadlineTests(unittest.TestCase):
    """Exercise agent/package deadlines without requiring account privileges.

    The existing RustRuntimeContextTests retain their real account-transition
    coverage. These dispatch tests use the current account and a fixture home,
    keeping the production target runner, timeouts and failure accounting real.
    """

    owned_dir = RustRuntimeContextTests.owned_dir
    write_input = RustRuntimeContextTests.write_input
    write_native_tool = RustRuntimeContextTests.write_native_tool
    write_tools = RustRuntimeContextTests.write_tools
    write_maintenance_tool = RustRuntimeContextTests.write_maintenance_tool
    cloud_command = RustRuntimeContextTests.cloud_command
    events = RustRuntimeContextTests.events
    assert_target_events = RustRuntimeContextTests.assert_target_events

    @classmethod
    def setUpClass(cls):
        cls.account = pwd.getpwuid(os.geteuid())
        cls.artifacts = Path(tempfile.mkdtemp(prefix="acfs-agent-deadlines-"))
        cls.library = snapshot_update_runtime(cls.artifacts, SOURCE.read_text())
        print("Agent deadline artifacts:", cls.artifacts, flush=True)

    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="case-", dir=self.artifacts))
        self.home = self.base / "target-home"
        self.caller = self.base / "caller-home"
        self.work = self.base / "working directory"
        self.tmp = self.base / "tmp"
        for path in (self.home, self.caller, self.work, self.tmp):
            self.owned_dir(path)
        self.events_file = self.base / "events.tsv"
        self.events_file.write_text("")
        (self.base / "update.log").write_text("")

    def own(self, path):
        # These fixtures already belong to the account that executes them.
        pass

    def run_update(self, *, command, timeout="5", dry_run=False, abort=False, expected=0):
        env = {
            "HOME": str(self.home), "PATH": "/usr/bin:/bin",
            "TARGET_USER": self.account.pw_name, "TARGET_HOME": str(self.home),
            "ACFS_HOLDS_FILE": str(self.home / ".acfs/holds.yaml"),
            "UPDATE_TEST_LIBRARY": str(self.library), "TEST_ROOT": str(self.base),
            "TEST_USER": self.account.pw_name, "TEST_UID": str(self.account.pw_uid),
            "TEST_GID": str(self.account.pw_gid), "TEST_HOME": str(self.home),
            "TEST_DRY_RUN": str(dry_run).lower(), "TEST_ABORT": str(abort).lower(),
            "TEST_TIMEOUT": timeout, "TEST_TRANSPORT": "default",
            "TMPDIR": str(self.tmp), "NO_COLOR": "1", "ACFS_INTERACTIVE": "false",
        }
        # Root's real home is /root even with TARGET_HOME. Redirect only home
        # metadata to the isolated fixture; account identity/transport stay real.
        body = COMMON + r'''
update_target_home() { printf '%s\n' "$TEST_HOME"; }
''' + command + r'''
printf 'COUNTS=%s,%s,%s\n' "$SUCCESS_COUNT" "$SKIP_COUNT" "$FAIL_COUNT"
'''
        result = subprocess.run(["/bin/bash", "--noprofile", "--norc", "-c", body],
                                env=env, cwd=self.work, text=True, capture_output=True,
                                timeout=20)
        (self.base / "stdout").write_text(result.stdout)
        (self.base / "stderr").write_text(result.stderr)
        (self.base / "exit").write_text(str(result.returncode) + "\n")
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def write_selection(self, modules):
        directory = self.home / ".acfs"
        self.owned_dir(directory)
        self.write_input(directory / "state.json", json.dumps({
            "target_home": str(self.home), "target_user": self.account.pw_name,
            "module_selection": {"schema_version": 1, "selected_modules": modules},
        }))

    def write_holds(self, tools, *, expiry="2999-12-31"):
        directory = self.home / ".acfs"
        self.owned_dir(directory)
        self.write_input(directory / "holds.yaml", "holds:\n" + "".join(
            f'  {tool}:\n    held_version: "current"\n    owner: "operator"\n'
            f'    reason: "retain working version"\n    expiry: "{expiry}"\n'
            for tool in tools))

    def test_held_native_runtimes_skip_probes_updates_and_forced_repair(self):
        self.write_selection(["lang.bun", "lang.uv", "tools.atuin"])
        self.write_holds(["bun", "uv", "atuin"])
        for tool in ("bun", "uv", "atuin"):
            self.write_native_tool(tool)
        self.write_native_tool("atuin-update", directory=self.home / ".atuin/bin")
        output = self.run_update(command=r'''
FORCE_MODE=true
update_bun
update_uv
update_run_selected_module tools.atuin update_atuin
printf 'HELD=%s:%s\n' "$HELD_COUNT" "${UPDATE_HELD_TOOLS[*]}"
''')
        self.assertEqual(self.events(), [])
        self.assertIn("COUNTS=0,3,0", output)
        self.assertIn("HELD=3:bun uv atuin", output)
        log = (self.base / "update.log").read_text()
        self.assertIn("by operator: retain working version (expires 2999-12-31)", log)

    def test_held_signature_verified_tools_never_provision_prerequisites(self):
        for modules, tools in ((["stack.caam"], ["caam"]),
                               (["stack.mcp_agent_mail"], ["mcp_agent_mail"]),
                               (["stack.mcp_agent_mail", "stack.caam"], ["mcp_agent_mail", "caam"])):
            with self.subTest(modules=modules):
                self.write_selection(modules)
                self.write_holds(tools)
                checkpoint = (self.home / ".acfs/state.json").read_bytes()
                output = self.run_update(command=r'''
FORCE_MODE=true
declare -gA KNOWN_INSTALLERS=([mcp_agent_mail]="https://fixture.invalid/agent-mail.sh")
update_require_security() { return 0; }
get_checksum() { printf '%064d\n' 1; }
update_ensure_minisign() { printf 'unexpected-package-install\n' >> "$TEST_ROOT/events.tsv"; return 1; }
update_stack
printf 'HELD=%s:%s\n' "$HELD_COUNT" "${UPDATE_HELD_TOOLS[*]}"
''')
                self.assertEqual(self.events(), [])
                self.assertIn(f"HELD={len(tools)}:", output)
                self.assertIn(",0\n", output.split("COUNTS=")[1])
                self.assertEqual((self.home / ".acfs/state.json").read_bytes(), checkpoint)

    def test_unheld_signature_verified_tool_still_requires_minisign_beside_a_hold(self):
        self.write_selection(["stack.mcp_agent_mail", "stack.caam"])
        for held in ("mcp_agent_mail", "caam"):
            with self.subTest(held=held):
                self.write_holds([held])
                self.events_file.write_text("")
                output = self.run_update(command=r'''
QUIET=false
declare -gA KNOWN_INSTALLERS=([mcp_agent_mail]="https://fixture.invalid/agent-mail.sh")
update_require_security() { return 0; }
get_checksum() { printf '%064d\n' 1; }
update_ensure_minisign() { printf 'prerequisite-required\n' >> "$TEST_ROOT/events.tsv"; return 1; }
update_stack
printf 'HELD=%s:%s\n' "$HELD_COUNT" "${UPDATE_HELD_TOOLS[*]}"
''')
                self.assertEqual(self.events(), [["prerequisite-required"]])
                self.assertIn("minisign is required to verify release signatures", output)
                self.assertIn(f"HELD=1:{held}", output)
                self.assertTrue(output.split("COUNTS=")[1].strip().endswith(",1"), output)

    def test_expired_signature_verified_tool_hold_does_not_bypass_prerequisites(self):
        self.write_selection(["stack.caam"])
        self.write_holds(["caam"], expiry="2000-01-01")
        output = self.run_update(command=r'''
update_require_security() { return 0; }
update_ensure_minisign() { printf 'prerequisite-required\n' >> "$TEST_ROOT/events.tsv"; return 1; }
update_stack
printf 'HELD=%s\n' "$HELD_COUNT"
''')
        self.assertEqual(self.events(), [["prerequisite-required"]])
        self.assertIn("HELD=0", output)
        self.assertTrue(output.split("COUNTS=")[1].strip().endswith(",1"), output)

    def test_held_agents_skip_native_and_package_updates_even_with_force(self):
        self.write_selection(["agents.codex", "agents.antigravity", "agents.omp", "agents.opencode"])
        self.write_holds(["codex", "antigravity", "omp", "opencode"])
        for tool in ("bun", "codex", "agy", "agy-real", "omp", "opencode"):
            self.write_native_tool(tool)
        output = self.run_update(command=r'''
FORCE_MODE=true
update_agents
printf 'HELD=%s:%s\n' "$HELD_COUNT" "${UPDATE_HELD_TOOLS[*]}"
''')
        self.assertEqual(self.events(), [])
        self.assertIn("COUNTS=0,6,0", output)
        self.assertIn("HELD=4:codex antigravity omp opencode", output)
        self.assertFalse((self.home / ".local/bin/agy-locked").exists())

    def test_held_cloud_tools_skip_packages_release_downloads_and_extensions(self):
        self.write_selection(["cloud.wrangler", "cloud.supabase", "cloud.vercel", "cli.modern"])
        self.write_holds(["wrangler", "supabase", "vercel", "gh"])
        for tool in ("bun", "wrangler", "supabase", "vercel"):
            self.write_native_tool(tool)
        self.write_maintenance_tool("gh")
        # Replace only the release payload with an inert marker; the real
        # dispatcher/account runner still decides whether it may execute.
        output = self.run_update(command=r'''
FORCE_MODE=true
supabase_release_update_script() { printf 'printf "release-download\\n" >> %q\n' "$TEST_ROOT/events.tsv"; }
update_cloud
printf 'HELD=%s:%s\n' "$HELD_COUNT" "${UPDATE_HELD_TOOLS[*]}"
''')
        self.assertEqual(self.events(), [])
        self.assertIn("COUNTS=0,5,0", output)
        self.assertIn("HELD=4:wrangler supabase vercel gh", output)

    def test_holding_bun_keeps_other_selected_package_updates_available(self):
        self.write_selection(["lang.bun", "agents.codex", "agents.omp"])
        self.write_holds(["bun", "omp"])
        for tool in ("bun", "codex", "omp"):
            self.write_native_tool(tool)
        output = self.run_update(command="update_bun; update_agents")
        self.assert_target_events(self.events())
        self.assertNotIn("omp", [event[0] for event in self.events()])
        self.assertEqual([event[-1] for event in self.events() if event[0] == "bun"],
                         ["install -g --trust @openai/codex@latest"])
        self.assertIn("COUNTS=1,6,0", output)

    def test_expired_native_hold_warns_and_update_still_runs(self):
        self.write_selection(["lang.bun"])
        self.write_holds(["bun"], expiry="2000-01-01")
        self.write_native_tool("bun")
        output = self.run_update(command="update_bun; printf 'HELD=%s\\n' \"$HELD_COUNT\"")
        self.assertEqual([event[-1] for event in self.events()], ["--version", "upgrade", "--version"])
        self.assertIn("COUNTS=1,0,0", output)
        self.assertIn("HELD=0", output)
        self.assertIn("hold ignored, updating normally", (self.base / "update.log").read_text())

    def test_dry_run_reports_holds_once_without_probing_held_tools(self):
        self.write_selection(["lang.bun"])
        self.write_holds(["bun"])
        self.write_native_tool("bun")
        checkpoint = self.home / ".acfs/state.json"
        original_checkpoint = checkpoint.read_bytes()
        output = self.run_update(dry_run=True, command=r'''
update_bun
update_bun
printf 'HELD=%s:%s\n' "$HELD_COUNT" "${UPDATE_HELD_TOOLS[*]}"
''')
        self.assertEqual(self.events(), [])
        self.assertIn("COUNTS=0,2,0", output)
        self.assertIn("HELD=1:bun", output)
        self.assertEqual(checkpoint.read_bytes(), original_checkpoint)

    def test_held_cargo_tool_skips_reinstall_and_missing_cargo_repair(self):
        self.write_selection(["tools.ast_grep"])
        self.write_holds(["ast-grep"])
        self.write_tools(self.home / ".cargo/bin", "target-cargo")
        self.write_native_tool("sg")
        output = self.run_update(command=r'''
FORCE_MODE=true
update_cargo_tools
update_rust_binary_path() { return 1; }
update_cargo_tools
printf 'HELD=%s:%s\n' "$HELD_COUNT" "${UPDATE_HELD_TOOLS[*]}"
''')
        self.assertEqual(self.events(), [])
        self.assertIn("COUNTS=0,2,0", output)
        self.assertIn("HELD=1:ast-grep", output)

    def test_legacy_cargo_hold_keeps_other_packages_updating(self):
        self.write_holds(["ast-grep", "du-dust"])
        self.write_tools(self.home / ".cargo/bin", "target-cargo")
        for tool in ("sg", "lsd", "dust", "tldr"):
            self.write_native_tool(tool)
        output = self.run_update(command="update_cargo_tools")
        self.assertEqual([event[-1] for event in self.events() if event[0] == "cargo"],
                         ["install lsd --locked --force", "install tealdeer --locked --force"])
        self.assertFalse(any(event[0] in ("sg", "dust") for event in self.events()))
        self.assertIn("COUNTS=2,2,0", output)

    def test_held_shell_components_do_not_block_unheld_plugin(self):
        self.write_selection(["shell.omz"])
        self.write_holds(["omz", "p10k", "zsh-autosuggestions"])
        custom = self.home / ".oh-my-zsh/custom"
        self.write_maintenance_tool("omz-upgrade", path=self.home / ".oh-my-zsh/tools/upgrade.sh")
        self.owned_dir(custom / "themes/powerlevel10k/.git")
        for plugin in ("zsh-autosuggestions", "zsh-syntax-highlighting"):
            self.owned_dir(custom / "plugins" / plugin / ".git")
        output = self.run_update(command=r'''
# Network acquisition is inert; normal selection, shell path resolution and
# hold lookup decide whether each repository reaches the git boundary.
update_run_shell_git() { printf '%s\n' "$*" >> "$TEST_ROOT/events.tsv"; printf 'updated\n'; }
update_run_selected_module shell.omz update_omz
update_run_selected_module shell.omz update_p10k
update_run_selected_module shell.omz update_zsh_plugins
printf 'HELD=%s:%s\n' "$HELD_COUNT" "${UPDATE_HELD_TOOLS[*]}"
''')
        self.assertEqual(self.events(), [[str(custom / "plugins/zsh-syntax-highlighting") + " pull --ff-only"]])
        self.assertIn("COUNTS=1,3,0", output)
        self.assertIn("HELD=3:omz p10k zsh-autosuggestions", output)

    def test_unselected_hold_does_not_count_as_held_and_missing_held_tool_stays_absent(self):
        self.write_selection(["lang.bun"])
        self.write_holds(["bun", "uv"])
        output = self.run_update(command=r'''
FORCE_MODE=true
update_require_security() { printf 'unexpected-download\n' >> "$TEST_ROOT/events.tsv"; return 1; }
update_bun
update_uv
printf 'HELD=%s:%s\n' "$HELD_COUNT" "${UPDATE_HELD_TOOLS[*]}"
''')
        self.assertEqual(self.events(), [])
        self.assertIn("COUNTS=0,1,0", output)
        self.assertIn("HELD=1:bun", output)

    def test_stack_update_skips_selected_ubuntu_only_module_on_arch(self):
        self.write_selection(["stack.srps"])
        self.write_maintenance_tool("flywheel-update-agents-md")
        checkpoint = self.home / ".acfs/state.json"
        saved_selection = checkpoint.read_bytes()
        output = self.run_update(command=r'''
ACFS_DISTRO_FAMILY=arch FORCE_MODE=true
update_require_security() { printf 'unexpected-security\n' >> "$TEST_ROOT/events.tsv"; return 1; }
update_run_verified_installer() { printf '%s\n' "$*" >> "$TEST_ROOT/events.tsv"; }
update_stack
update_root_agents_md
update_run_selected_module stack.srps printf 'UNSUPPORTED-INSTALL\n'
''')
        self.assertEqual(self.events(), [])
        self.assertEqual(checkpoint.read_bytes(), saved_selection)
        self.assertNotIn("UNSUPPORTED-INSTALL", output)
        self.assertIn("not applicable on arch", (self.base / "update.log").read_text())
        self.assertIn("COUNTS=0,", output)

    def test_stack_update_keeps_selected_module_on_supported_family(self):
        self.write_selection(["stack.srps"])
        self.run_update(command=r'''
ACFS_DISTRO_FAMILY=ubuntu
update_require_security() { return 0; }
update_run_verified_installer() { printf '%s\n' "$*" >> "$TEST_ROOT/events.tsv"; }
update_stack
''')
        self.assertEqual(self.events(), [["srps"]])

    def test_caut_selected_install_reaches_source_maintenance(self):
        self.write_selection(["utils.caut"])
        self.write_native_tool("caut", directory=self.home / ".cargo/bin")
        output = self.run_update(command=r'''
update_require_security() { return 0; }
update_run_cargo_git_source_install() {
    printf '%s\n' "$*" > "$TEST_ROOT/source-install"
}
update_stack
''')
        self.assertTrue((self.base / "source-install").exists(), output)
        self.assertEqual((self.base / "source-install").read_text(),
                         "https://github.com/Dicklesworthstone/coding_agent_usage_tracker.git caut\n")
        self.assertEqual([(event[0], event[-1]) for event in self.events()],
                         [("caut", "--version"), ("caut", "--version")])
        self.assertIn("Version before [caut]: caut 1.2.3-fixture",
                      (self.base / "update.log").read_text())
        self.assertIn("COUNTS=1,", output)

    def test_caut_maintenance_finds_custom_cargo_home_and_reports_build_failure(self):
        self.write_selection(["utils.caut"])
        self.write_native_tool("caut", directory=self.home / "custom cargo/bin")
        output = self.run_update(command=r'''
export CARGO_HOME="$TEST_HOME/custom cargo"
update_require_security() { return 0; }
update_run_cargo_git_source_install() {
    printf '%s\n' "$*" > "$TEST_ROOT/source-install"
    return 17
}
update_stack
''')
        self.assertTrue((self.base / "source-install").exists(), output)
        self.assertEqual([(event[0], event[-1]) for event in self.events()],
                         [("caut", "--version"), ("caut", "--version")])
        log = (self.base / "update.log").read_text()
        self.assertIn("Failed: CAUT (exit code: 17)", log)
        self.assertNotIn("Success: CAUT", log)
        self.assertIn("COUNTS=0,", output)
        self.assertTrue(output.rstrip().endswith(",1"), output)

    def test_caut_forced_repair_respects_selection_and_hold(self):
        self.write_selection(["utils.caut"])
        command = r'''
update_require_security() { return 0; }
update_run_cargo_git_source_install() {
    printf '%s\n' "$*" >> "$TEST_ROOT/source-install"
}
update_stack
printf 'HELD=%s:%s\n' "$HELD_COUNT" "${UPDATE_HELD_TOOLS[*]}"
'''
        self.run_update(command=command)
        self.assertFalse((self.base / "source-install").exists())
        self.run_update(command="FORCE_MODE=true\n" + command, dry_run=True)
        self.assertFalse((self.base / "source-install").exists())
        output = self.run_update(command="FORCE_MODE=true\n" + command)
        self.assertTrue((self.base / "source-install").exists(), output)
        self.assertEqual((self.base / "source-install").read_text().count("caut\n"), 1)
        self.write_native_tool("caut", directory=self.home / ".cargo/bin")
        self.write_holds(["caut"])
        output = self.run_update(command="FORCE_MODE=true\n" + command)
        self.assertIn("HELD=1:caut", output)
        self.assertEqual((self.base / "source-install").read_text().count("caut\n"), 1)
        self.assertEqual(self.events(), [])
        self.write_selection(["utils.aadc"])
        self.run_update(command="FORCE_MODE=true\n" + command)
        self.assertEqual((self.base / "source-install").read_text().count("caut\n"), 1)

    def test_legacy_scope_also_honors_manifest_platforms(self):
        output = self.run_update(command=r'''
ACFS_DISTRO_FAMILY=arch FORCE_MODE=true
update_run_selected_module stack.srps printf 'UNSUPPORTED-INSTALL\n'
update_run_selected_module stack.ntm printf 'PORTABLE-INSTALL\n'
''')
        self.assertNotIn("UNSUPPORTED-INSTALL", output)
        self.assertIn("PORTABLE-INSTALL", output)

    def test_manifest_platforms_gate_runtime_agents_cloud_and_shell(self):
        modules = ["lang.bun", "agents.omp", "cloud.vercel", "shell.omz"]
        self.write_selection(modules)
        for tool in ("bun", "omp", "vercel"):
            self.write_native_tool(tool)
        # The same generated data format supports every category; this fixture
        # adds restrictions without changing any production manifest policy.
        index = self.base / "restricted-index.sh"
        index.write_text("ACFS_MODULES_IN_ORDER=(\n" + "".join(
            f'  "{module}"\n' for module in modules) + ")\n"
            "declare -gA ACFS_MODULE_FAMILIES=(\n" + "".join(
            f"  ['{module}']=\"ubuntu\"\n" for module in modules) + ")\n")
        output = self.run_update(command=r'''
ACFS_DISTRO_FAMILY=arch FORCE_MODE=true
_UPDATE_MANIFEST_INDEX="$TEST_ROOT/restricted-index.sh"
update_omz() { printf 'unexpected-omz\n' >> "$TEST_ROOT/events.tsv"; }
update_p10k() { printf 'unexpected-p10k\n' >> "$TEST_ROOT/events.tsv"; }
update_zsh_plugins() { printf 'unexpected-plugins\n' >> "$TEST_ROOT/events.tsv"; }
# Runtime publication has its own tests; keep this dispatch test confined to
# the fixture's account-owned modules and shell configuration.
sync_acfs_deployed() { :; }
sync_acfs_global_wrapper() { :; }
sync_acfs_global_command_links() { :; }
update_bun
update_agents
update_cloud
update_shell
''')
        self.assertEqual(self.events(), [])
        self.assertFalse((self.home / ".profile").exists())
        self.assertFalse((self.home / ".zprofile").exists())
        self.assertFalse((self.home / ".zshrc").exists())
        self.assertIn("COUNTS=0,", output)

    def test_malformed_manifest_platform_data_stops_before_update(self):
        self.write_selection(["lang.bun"])
        self.write_native_tool("bun")
        index = self.base / "malformed-index.sh"
        index.write_text('ACFS_MODULES_IN_ORDER=(\n  "lang.bun"\n)\n'
                         'declare -gA ACFS_MODULE_FAMILIES=(\n'
                         '  [\'lang.bun\']="$(touch SHOULD-NOT-EXECUTE)"\n)\n')
        output = self.run_update(command=r'''
ACFS_DISTRO_FAMILY=arch FORCE_MODE=true
_UPDATE_MANIFEST_INDEX="$TEST_ROOT/malformed-index.sh"
if update_bun; then printf 'UNEXPECTED-ACCEPT\n'; else printf 'PLATFORM-REFUSED\n'; fi
''')
        self.assertEqual(self.events(), [])
        self.assertIn("PLATFORM-REFUSED", output)
        self.assertNotIn("UNEXPECTED-ACCEPT", output)
        self.assertFalse((self.work / "SHOULD-NOT-EXECUTE").exists())

    def test_agy_launcher_priming_transports_validated_mode_and_custom_checkpoint(self):
        source_dir = self.home / ".acfs/scripts/lib"
        self.owned_dir(source_dir)
        self.write_input(source_dir / "agy_locked.py",
                         (ROOT / "scripts/lib/agy_locked.py").read_text())
        self.write_native_tool("agy-real")
        settings = self.home / ".gemini/antigravity-cli/settings.json"
        # MODE is deliberately not exported and there is no default state.
        self.run_update(command=r'''
MODE=safe
export -n MODE
update_install_agy_locked_launchers
''')
        self.assertEqual(json.loads(settings.read_text())["toolPermission"], "request-review")
        custom = self.home / "custom checkpoint.json"
        self.write_input(custom, json.dumps({"mode": "safe", "target_home": str(self.home),
                                            "target_user": self.account.pw_name}))
        self.write_input(self.home / ".acfs/state.json", json.dumps({"mode": "vibe"}))
        # An unexported explicit checkpoint must survive the target runner.
        self.run_update(command=r'''
unset MODE
ACFS_STATE_FILE="$TEST_HOME/custom checkpoint.json"
export -n ACFS_STATE_FILE
update_install_agy_locked_launchers
''')
        self.assertEqual(json.loads(settings.read_text())["toolPermission"], "request-review")
        self.assertTrue((self.home / ".gemini/config/hooks/dcg-antigravity-hook.py").is_file())
        self.assertEqual(self.events(), [])  # Priming never starts an agent session.

    def test_agy_launcher_priming_rejects_invalid_context_before_installing(self):
        for assignment in ("MODE=unsupported", "MODE=safe ACFS_STATE_FILE=relative.json"):
            with self.subTest(assignment=assignment):
                output = self.run_update(command=assignment + r'''
if update_install_agy_locked_launchers; then
    printf 'UNEXPECTED-PRIME\n'
else
    printf 'PRIME-REFUSED\n'
fi
''')
                self.assertIn("PRIME-REFUSED", output)
                self.assertNotIn("UNEXPECTED-PRIME", output)
                self.assertFalse((self.home / ".local/bin/agy-locked").exists())
                self.assertFalse((self.home / ".gemini").exists())

    def test_agent_native_updates_keep_deadlines_and_continue(self):
        for tool in ("agy", "agy-real", "omp", "opencode"):
            self.write_native_tool(tool)
        for tool in ("agy-real", "omp"):
            self.write_input(self.base / f"mode-{tool}", "hang\n")
        output = self.run_update(timeout="0.2", command="update_agents")
        self.assert_target_events(self.events())
        # This minimal runtime snapshot omits agy_locked.py. Its independent
        # launcher failure must be counted in addition to the native timeouts.
        self.assertIn("COUNTS=1,3,3", output)
        log = (self.base / "update.log").read_text()
        self.assertIn("Failed: Antigravity CLI (exit code: 124)", log)
        self.assertIn("Failed: Antigravity locked launchers (exit code: 1)", log)
        self.assertIn("Failed: oh-my-pi (omp) (exit code: 124)", log)
        for tool in ("agy-real", "omp"):
            self.assertFalse((self.home / f"{tool}-native-installed").exists())
        self.assertTrue((self.home / "opencode-native-installed").exists())
        mutations = [(e[0], e[-1]) for e in self.events() if e[-1] != "--version"]
        self.assertEqual(mutations, [("agy-real", "update"), ("omp", "update"),
                                     ("opencode", "upgrade")])
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_agent_native_updates_keep_success_and_account_context(self):
        for tool in ("agy", "agy-real", "omp", "opencode"):
            self.write_native_tool(tool)
        output = self.run_update(command="update_agents")
        self.assert_target_events(self.events())
        # All three native updaters succeeded, but the fixture has no launcher
        # source. Native success cannot hide that incomplete Antigravity setup.
        self.assertIn("COUNTS=3,3,1", output)
        self.assertIn("Failed: Antigravity locked launchers (exit code: 1)",
                      (self.base / "update.log").read_text())
        for tool in ("agy-real", "omp", "opencode"):
            self.assertEqual((self.home / f"{tool}-native-installed").stat().st_uid,
                             self.account.pw_uid)
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_agent_native_dry_run_never_self_updates(self):
        for tool in ("agy", "agy-real", "omp", "opencode"):
            self.write_native_tool(tool)
        output = self.run_update(dry_run=True, command="update_agents")
        self.assert_target_events(self.events())
        self.assertIn("COUNTS=0,7,0", output)
        self.assertIn("Running: update_install_agy_locked_launchers",
                      (self.base / "update.log").read_text())
        self.assertEqual(set(e[-1] for e in self.events()), {"--version"})
        for tool in ("agy-real", "omp", "opencode"):
            self.assertFalse((self.home / f"{tool}-native-attempts").exists())

    def assert_native_replacement_failure(self, mode, *, timeout="5", verification_status=None):
        """A real successful updater leaves a broken final command on disk."""
        labels = {"agy-real": "Antigravity CLI", "omp": "oh-my-pi (omp)", "opencode": "OpenCode"}
        for failed_tool, label in labels.items():
            with self.subTest(mode=mode, tool=failed_tool):
                self.setUp()
                self.write_selection(["agents.antigravity", "agents.omp", "agents.opencode"])
                for tool in ("agy", *labels):
                    self.write_native_tool(tool)
                self.write_input(self.base / f"mode-{failed_tool}", mode + "\n")
                checkpoint = self.home / ".acfs/state.json"
                original_checkpoint = checkpoint.read_bytes()
                output = self.run_update(timeout=timeout, command=r'''
UPDATE_SMOKE_TIMEOUT=0.2
UPDATE_OPENCODE_TIMEOUT=0.2
update_agents
printf 'CONTINUED-AFTER-AGENTS\n'
''')
                self.assert_target_events(self.events())
                # The fixture omits the Antigravity launcher source, so that
                # existing failure remains separate from the native payload.
                self.assertIn("COUNTS=2,3,2", output)
                self.assertIn("CONTINUED-AFTER-AGENTS", output)
                log = (self.base / "update.log").read_text()
                self.assertIn(f"Failed: {label} (exit code:", log)
                self.assertNotIn(f"Success: {label}\n", log)
                if verification_status is not None:
                    self.assertIn(f"verification failed (exit {verification_status})", log)
                for tool in labels:
                    self.assertTrue((self.home / f"{tool}-native-installed").is_file())
                    self.assertEqual((self.home / f"{tool}-native-attempts").read_text(), "1\n")
                self.assertEqual(checkpoint.read_bytes(), original_checkpoint)
                self.assertEqual(list(self.caller.iterdir()), [])

    def test_native_agent_update_rejects_broken_replacement(self):
        self.assert_native_replacement_failure("broken-payload", verification_status=42)

    def test_native_agent_update_rejects_empty_version_output(self):
        self.assert_native_replacement_failure("empty-payload")

    def test_native_agent_update_rejects_missing_replacement(self):
        self.assert_native_replacement_failure("missing-payload")

    def test_native_agent_update_rejects_unexecutable_replacement(self):
        self.assert_native_replacement_failure("unexecutable-payload")

    def test_native_agent_replacement_verification_has_a_deadline(self):
        self.assert_native_replacement_failure("hung-payload", timeout="0.2", verification_status=124)

    def test_native_agent_verification_failure_honors_abort_before_later_agents(self):
        self.write_selection(["agents.omp", "agents.opencode"])
        self.write_native_tool("omp")
        later_binary = self.write_native_tool("opencode")
        original_later_binary = later_binary.read_bytes()
        self.write_input(self.base / "mode-omp", "broken-payload\n")
        output = self.run_update(command="update_agents", abort=True, expected=1)
        self.assertIn("Aborting due to failure", output)
        self.assertNotIn("COUNTS=", output)
        self.assert_target_events(self.events())
        self.assertFalse((self.home / "opencode-native-attempts").exists())
        self.assertEqual(later_binary.read_bytes(), original_later_binary)
        self.assertIn("verification failed (exit 42)", (self.base / "update.log").read_text())

    def test_codex_package_timeout_preserves_retries_and_later_agents(self):
        for tool in ("bun", "codex", "omp"):
            self.write_native_tool(tool)
        self.write_input(self.base / "mode-bun", "hang\n")
        output = self.run_update(timeout="0.2", command="update_agents")
        self.assert_target_events(self.events())
        self.assertIn("COUNTS=1,4,1", output)
        install_args = [e[-1] for e in self.events() if e[0] == "bun"]
        self.assertEqual(install_args,
                         ["install -g --trust @openai/codex@latest"] * 3 +
                         ["install -g --trust @openai/codex"] * 3)
        self.assertFalse((self.home / "bun-native-installed").exists())
        self.assertTrue((self.home / "omp-native-installed").exists())
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_codex_package_dry_run_never_installs(self):
        for tool in ("bun", "codex", "omp"):
            self.write_native_tool(tool)
        output = self.run_update(dry_run=True, command="update_agents")
        self.assert_target_events(self.events())
        self.assertIn("COUNTS=0,6,0", output)
        self.assertEqual(set(e[-1] for e in self.events()), {"--version"})
        self.assertFalse((self.home / "bun-native-attempts").exists())
        self.assertFalse((self.home / "omp-native-attempts").exists())

    def write_codex_package_fixture(self, *, package_mode="success"):
        """Model Bun's global-bin query and Node-shebang package, without Node."""
        self.write_selection(["agents.codex", "lang.bun"])
        bun_dir = self.home / ".bun/bin"
        self.owned_dir(bun_dir)
        bun = bun_dir / "bun"
        bun.write_text("#!/bin/bash\nset -euo pipefail\nfixture=" + shlex.quote(str(self.base)) + r'''
printf '%s\t%s\t%s\t%s\t%s\n' "$EUID" "$HOME" "$PWD" "${BUN_INSTALL-}" "$*" >> "$fixture/package-events.tsv"
global_bin="${BUN_INSTALL_BIN:-$HOME/.bun/bin}"
if [[ -f "$fixture/reported-global-bin" ]]; then
    IFS= read -r global_bin < "$fixture/reported-global-bin"
fi
case "$*" in
    'install -g --trust @openai/codex'*|'install -g --trust wrangler@latest'|'install -g --trust vercel@latest')
        name="${4%@*}"
        [[ "$name" == wrangler || "$name" == vercel ]] || name=codex
        [[ ! -f "$fixture/missing-package" ]] || exit 0
        mkdir -p -- "$global_bin"
        printf '%s\n' "$global_bin" > "$fixture/installed-global-bin"
        printf '#!/usr/bin/env node\nconsole.log("%s-cli 1.2.3-fixture");\n' "$name" > "$global_bin/$name"
        chmod 0755 "$global_bin/$name"
        ;;
    'pm bin -g')
        [[ ! -f "$fixture/failed-bin-query" ]] || exit 42
        [[ ! -f "$fixture/hung-bin-query" ]] || /bin/sleep 5
        if [[ -f "$fixture/global-bin-output" ]]; then
            cat "$fixture/global-bin-output"
        else
            printf '%s\n' "$global_bin"
        fi
        ;;
    *)
        [[ -f "$fixture/installed-global-bin" ]] || exit 64
        IFS= read -r global_bin < "$fixture/installed-global-bin"
        name="${1##*/}"
        [[ $# == 2 && "$1" == "$global_bin/$name" && "$2" == --version ]] || exit 64
        [[ -f "$1" ]] || exit 127
        [[ ! -f "$fixture/failed-package" ]] || { printf 'broken package fixture\n' >&2; exit 42; }
        [[ ! -f "$fixture/hung-package" ]] || /bin/sleep 5
        printf '%s-cli 1.2.3-fixture\n' "$name"
        ;;
esac
''')
        bun.chmod(0o755)
        node = self.home / ".local/bin/node"
        self.owned_dir(node.parent)
        node.write_text("#!/bin/bash\nexit 127\n")
        node.chmod(0o755)
        if package_mode != "success":
            self.write_input(self.base / f"{package_mode}-package", "fixture\n")

    def assert_codex_launcher_works(self, launcher):
        self.assertTrue(launcher.is_file(), f"Codex launcher missing: {launcher}")
        result = subprocess.run([str(launcher), "--version"],
                                env={"HOME": str(self.home), "PATH": "/usr/bin:/bin"},
                                text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "codex-cli 1.2.3-fixture")
        self.assertEqual(launcher.stat().st_uid, self.account.pw_uid)

    def test_codex_forced_repair_restores_bun_launcher_without_node(self):
        self.write_codex_package_fixture()
        output = self.run_update(command="FORCE_MODE=true; update_agents")
        self.assertIn("COUNTS=1,5,0", output)
        self.assert_codex_launcher_works(self.home / ".local/bin/codex")
        events = [line.split("\t") for line in (self.base / "package-events.tsv").read_text().splitlines()]
        for event in events[:2]:
            self.assertEqual(event[:4], [str(self.account.pw_uid), str(self.home),
                                        str(self.home), str(self.home / ".bun")])
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_codex_update_repairs_broken_launcher_in_custom_primary_bin(self):
        self.write_codex_package_fixture()
        primary = self.home / "custom bin"
        self.owned_dir(primary)
        launcher = primary / "codex"
        launcher.write_text("#!/bin/bash\nexit 127\n")
        launcher.chmod(0o755)
        output = self.run_update(command='ACFS_BIN_DIR="$TEST_HOME/custom bin"; update_agents')
        self.assertIn("COUNTS=1,5,0", output)
        self.assert_codex_launcher_works(launcher)
        self.assertFalse((self.home / ".local/bin/codex").exists())

    def test_codex_forced_repair_uses_bun_environment_global_bin(self):
        self.write_codex_package_fixture()
        global_bin = self.home / "Bun's global bin"
        output = self.run_update(command=(
            "export BUN_INSTALL_BIN=" + shlex.quote(str(global_bin)) +
            "; FORCE_MODE=true; update_agents"))
        self.assertIn("COUNTS=1,5,0", output)
        self.assertTrue((global_bin / "codex").is_file())
        self.assertFalse((self.home / ".bun/bin/codex").exists())
        self.assert_codex_launcher_works(self.home / ".local/bin/codex")

    def test_codex_forced_repair_uses_bun_reported_global_bin(self):
        self.write_codex_package_fixture()
        global_bin = self.home / "configured global bin"
        # Configuration can select a directory without BUN_INSTALL_BIN. Let
        # the package manager resolve it; the updater must consume its query.
        self.write_input(self.base / "reported-global-bin", str(global_bin) + "\n")
        output = self.run_update(command="FORCE_MODE=true; update_agents")
        self.assertIn("COUNTS=1,5,0", output)
        self.assertTrue((global_bin / "codex").is_file())
        self.assertFalse((self.home / ".bun/bin/codex").exists())
        self.assert_codex_launcher_works(self.home / ".local/bin/codex")
        events = (self.base / "package-events.tsv").read_text().splitlines()
        self.assertTrue(any(row.endswith("\tpm bin -g") for row in events), events)

    def test_codex_global_bin_query_failure_or_timeout_keeps_existing_launcher(self):
        for mode, status in (("failed", 42), ("hung", 124)):
            with self.subTest(mode=mode):
                self.setUp()
                self.write_codex_package_fixture()
                launcher = self.write_native_tool("codex")
                original = launcher.read_bytes()
                self.write_input(self.base / f"{mode}-bin-query", "fixture\n")
                output = self.run_update(command="FORCE_MODE=true; UPDATE_SMOKE_TIMEOUT=0.2; update_agents")
                self.assertIn("COUNTS=0,5,1", output)
                self.assertEqual(launcher.read_bytes(), original)
                self.assertEqual(list(launcher.parent.glob(".acfs-codex.*")), [])
                self.assertIn(f"launcher verification failed (exit {status})",
                              (self.base / "update.log").read_text())

    def test_codex_global_bin_query_invalid_output_keeps_existing_launcher(self):
        for value in ("", "relative/bin\n", "/\n", "/missing/acfs-bin\n", "/tmp\n/another/bin\n"):
            with self.subTest(value=value):
                self.setUp()
                self.write_codex_package_fixture()
                launcher = self.write_native_tool("codex")
                original = launcher.read_bytes()
                self.write_input(self.base / "global-bin-output", value)
                output = self.run_update(command="FORCE_MODE=true; update_agents")
                self.assertIn("COUNTS=0,5,1", output)
                self.assertEqual(launcher.read_bytes(), original)
                self.assertEqual(list(launcher.parent.glob(".acfs-codex.*")), [])
                self.assertIn("invalid global bin directory", (self.base / "update.log").read_text())

    def test_codex_global_bin_collision_and_directory_alias_preserve_package(self):
        for alias in (False, True):
            with self.subTest(alias=alias):
                self.setUp()
                self.write_codex_package_fixture()
                global_bin = self.home / "configured global bin"
                self.owned_dir(global_bin)
                primary = global_bin
                if alias:
                    primary = self.home / "primary bin alias"
                    primary.symlink_to(global_bin, target_is_directory=True)
                self.write_input(self.base / "reported-global-bin", str(global_bin) + "\n")
                output = self.run_update(command=(
                    "ACFS_BIN_DIR=" + shlex.quote(str(primary)) +
                    "; FORCE_MODE=true; update_agents"))
                self.assertIn("COUNTS=0,5,1", output)
                self.assertEqual((global_bin / "codex").read_text(),
                                 '#!/usr/bin/env node\nconsole.log("codex-cli 1.2.3-fixture");\n')
                self.assertEqual(list(global_bin.glob(".acfs-codex.*")), [])
                self.assertIn("Cannot replace the Codex package with its launcher",
                              (self.base / "update.log").read_text())

    def test_codex_launcher_uses_native_bun_global_configuration(self):
        native_bun = shutil.which("bun")
        if native_bun is None:
            self.skipTest("Bun is required for the offline native configuration check")
        global_bin = self.home / "native configured bin"
        self.owned_dir(global_bin)
        global_store = self.home / ".bun/install/global"
        self.owned_dir(global_store)
        self.write_input(global_store / "package.json", '{"private":true}\n')
        self.write_input(self.home / ".bunfig.toml",
                         "[install]\nglobalBinDir = " + json.dumps(str(global_bin)) + "\n")
        self.write_input(global_bin / "codex", 'console.log("codex-cli 1.2.3-fixture");\n')
        # No registry/package installation: real Bun resolves its own account
        # config and executes the local JavaScript package through the launcher.
        self.run_update(command=(
            "FORCE_MODE=true; update_reconcile_bun_launcher " + shlex.quote(native_bun) + " codex"))
        self.assert_codex_launcher_works(self.home / ".local/bin/codex")
        self.assertFalse((self.home / ".bun/bin/codex").exists())

    def test_codex_update_preserves_healthy_custom_launcher(self):
        self.write_codex_package_fixture()
        launcher = self.write_native_tool("codex")
        original = launcher.read_bytes()
        output = self.run_update(command="update_agents")
        self.assertIn("COUNTS=1,5,0", output)
        self.assertEqual(launcher.read_bytes(), original)

    def test_codex_repair_failure_or_timeout_preserves_previous_launcher(self):
        for mode in ("failed", "hung"):
            with self.subTest(mode=mode):
                self.setUp()
                self.write_codex_package_fixture(package_mode=mode)
                launcher = self.write_native_tool("codex")
                original = launcher.read_bytes()
                output = self.run_update(command="FORCE_MODE=true; UPDATE_SMOKE_TIMEOUT=0.2; update_agents")
                self.assertIn("COUNTS=0,5,1", output)
                self.assertEqual(launcher.read_bytes(), original)
                self.assertEqual(list(launcher.parent.glob(".acfs-codex.*")), [])
                self.assertIn("launcher verification failed", (self.base / "update.log").read_text())

    def test_codex_repair_rejects_successful_install_without_package(self):
        self.write_codex_package_fixture(package_mode="missing")
        output = self.run_update(command="FORCE_MODE=true; update_agents")
        self.assertIn("COUNTS=0,5,1", output)
        self.assertFalse((self.home / ".local/bin/codex").exists())

    def test_codex_launcher_repair_obeys_selection_hold_and_dry_run(self):
        for mode in ("unselected", "held", "dry-run"):
            with self.subTest(mode=mode):
                self.setUp()
                self.write_codex_package_fixture()
                if mode == "unselected":
                    self.write_selection(["lang.bun"])
                elif mode == "held":
                    self.write_holds(["codex"])
                self.run_update(command="FORCE_MODE=true; update_agents", dry_run=mode == "dry-run")
                self.assertFalse((self.base / "package-events.tsv").exists())
                self.assertFalse((self.home / ".local/bin/codex").exists())
                self.assertFalse((self.home / ".bun/bin/codex").exists())

    def test_cloud_package_timeouts_continue_to_other_tools(self):
        for tool in ("bun", "wrangler", "vercel"):
            self.write_native_tool(tool)
        self.write_maintenance_tool("gh")
        self.write_input(self.base / "mode-bun", "hang\n")
        output = self.run_update(timeout="0.2", command=self.cloud_command())
        self.assert_target_events(self.events())
        self.assertIn("COUNTS=1,2,2", output)
        self.assertEqual([e[-1] for e in self.events() if e[0] == "bun"],
                         ["install -g --trust wrangler@latest",
                          "install -g --trust vercel@latest"])
        self.assertFalse((self.home / "bun-native-installed").exists())
        self.assertIn(("gh", "extension upgrade --all"),
                      [(e[0], e[-1]) for e in self.events()])
        log = (self.base / "update.log").read_text()
        self.assertIn("Failed: Wrangler (Cloudflare) (exit code: 124 after 1 attempts)", log)
        self.assertIn("Failed: Vercel CLI (exit code: 124 after 1 attempts)", log)
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_cloud_force_makes_custom_bun_global_packages_runnable_without_node(self):
        self.write_codex_package_fixture()
        self.write_selection(["lang.bun", "cloud.wrangler", "cloud.vercel"])
        global_bin = self.home / "Bun's global bin"
        self.write_input(self.base / "reported-global-bin", str(global_bin) + "\n")
        output = self.run_update(command="UPDATE_CLOUD=true; FORCE_MODE=true; update_cloud")
        self.assertIn("COUNTS=2,3,0", output)
        for tool in ("wrangler", "vercel"):
            launcher = self.home / ".local/bin" / tool
            result = subprocess.run([str(launcher), "--version"], text=True,
                                    capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), f"{tool}-cli 1.2.3-fixture")
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_cloud_package_install_success_requires_working_command(self):
        for mode in ("missing", "failed", "hung"):
            with self.subTest(mode=mode):
                self.setUp()
                self.write_codex_package_fixture(package_mode=mode)
                self.write_selection(["lang.bun", "cloud.wrangler"])
                launcher = self.write_native_tool("wrangler")
                original = launcher.read_bytes()
                output = self.run_update(command=(
                    "UPDATE_CLOUD=true; FORCE_MODE=true; UPDATE_SMOKE_TIMEOUT=0.3; update_cloud"))
                self.assertIn("COUNTS=0,4,1", output)
                self.assertEqual(launcher.read_bytes(), original)
                self.assertEqual(list(launcher.parent.glob(".acfs-wrangler.*")), [])
                self.assertFalse((self.home / ".local/bin/vercel").exists())

    def test_cloud_force_keeps_working_package_when_bin_directories_coincide(self):
        self.write_codex_package_fixture()
        self.write_selection(["lang.bun", "cloud.vercel"])
        primary = self.home / ".local/bin"
        self.write_input(self.base / "reported-global-bin", str(primary) + "\n")
        node = primary / "node"
        node.write_text('#!/bin/bash\n[[ -f "$1" && "$2" == --version ]] || exit 42\nprintf "1.2.3\\n"\n')
        output = self.run_update(command="UPDATE_CLOUD=true; FORCE_MODE=true; update_cloud")
        self.assertIn("COUNTS=1,4,0", output)
        self.assertTrue((primary / "vercel").read_text().startswith("#!/usr/bin/env node\n"))
        self.assertEqual(list(primary.glob(".acfs-vercel.*")), [])

    def test_cloud_package_dry_run_never_installs(self):
        for tool in ("bun", "wrangler", "vercel"):
            self.write_native_tool(tool)
        self.write_maintenance_tool("gh")
        output = self.run_update(dry_run=True, command=self.cloud_command())
        self.assert_target_events(self.events())
        self.assertIn("COUNTS=0,5,0", output)
        self.assertEqual([(e[0], e[-1]) for e in self.events()],
                         [("gh", "extension list")])
        self.assertFalse((self.home / "bun-native-attempts").exists())
        self.assertEqual(list(self.caller.iterdir()), [])


class UpdaterCommandHarness(unittest.TestCase):
    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="acfs-update-retry-"))

    def execute(self, wrapper, body, *, verbose=False, quiet=True, setup="", stdin="",
                invocation='"$TEST_ROOT/command"', observe=None, expected_returncode=0):
        case = Path(tempfile.mkdtemp(prefix="case-", dir=self.base))
        command = case / "command"
        command.write_text("#!/bin/bash\nset -euo pipefail\n" + body + "\n")
        command.chmod(0o700)
        env = {
            "PATH": "/usr/bin:/bin", "HOME": str(case), "TARGET_HOME": str(case),
            "TMPDIR": str(case), "TEST_ROOT": str(case), "NO_COLOR": "1",
            "UPDATE_TEST_LIBRARY": str(SOURCE),
            "TEST_VERBOSE": str(verbose).lower(), "TEST_QUIET": str(quiet).lower(),
        }
        script = r'''
source "$UPDATE_TEST_LIBRARY"
QUIET="$TEST_QUIET" VERBOSE="$TEST_VERBOSE" DRY_RUN=false ABORT_ON_FAILURE=false
UPDATE_LOG_FILE="$TEST_ROOT/update.log"
UPDATE_CMD_TIMEOUT=0.2
ACFS_UPDATE_RETRY_MAX_ATTEMPTS=2
ACFS_UPDATE_RETRY_SLEEP_SECONDS=0
# Retain captures and all fixture files for failure diagnosis.
rm() { :; }
''' + setup + "\nrc=0\n" + wrapper + (" " if wrapper == "update_run_logged_passthrough" else ' "fixture" ') + invocation + r''' || rc=$?
printf 'RESULT=%s COUNTS=%s,%s,%s\n' "$rc" "$SUCCESS_COUNT" "$SKIP_COUNT" "$FAIL_COUNT"
printf 'CAPTURE=%s\n' "$UPDATE_LAST_COMMAND_OUTPUT"
printf 'STATE=%s\n' "$UPDATE_LAST_HOLD_DETAILS"
'''
        process = subprocess.Popen(["/bin/bash", "--noprofile", "--norc", "-c", script],
                                   env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True)
        try:
            observed = observe(process, case) if observe is not None else ""
            stdout, stderr = process.communicate(stdin, timeout=3)
            stdout = observed + stdout
            self.assertEqual(process.returncode, expected_returncode, stdout + stderr)
            return case, stdout, stderr
        finally:
            # Terminate only the fixture processes created by this invocation.
            # GNU timeout may put the command in its own process group.
            background = case / "background-pid"
            if background.exists():
                try:
                    os.kill(int(background.read_text()), signal.SIGKILL)
                except ProcessLookupError:
                    pass
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate(timeout=3)


class SmokeCommandExecutionTests(UpdaterCommandHarness):
    SETUP = r'''
update_target_home() { printf '%s\n' "$TEST_ROOT"; }
UPDATE_SMOKE_TIMEOUT=0.2
'''
    INVOCATION = 'update_run_smoke_probe "$TEST_ROOT/command" --version'

    def test_smoke_does_not_wait_for_successful_probe_background_writer(self):
        case, stdout, stderr = self.execute("update_run_logged_passthrough", r'''
/bin/sleep 30 &
printf '%s\n' "$!" > "$TEST_ROOT/background-pid"
printf 'omp 1.2.3\n\n'
''', setup=self.SETUP, invocation=self.INVOCATION)
        self.assertIn("RESULT=0 COUNTS=0,0,0", stdout)
        log = (case / "update.log").read_text()
        payload = log.split("\n----- COMMAND: ", 1)[1].split("\n", 1)[1]
        self.assertEqual(payload, "omp 1.2.3\n\n")
        self.assertNotIn("ACFS_SMOKE_STARTED_", stdout + stderr)
        self.assertEqual(stderr, "")

    def test_smoke_preserves_native_failure_and_trailing_diagnostics(self):
        case, stdout, stderr = self.execute("update_run_logged_passthrough", r'''
printf 'native failure diagnostic\n\n' >&2
exit 42
''', setup=self.SETUP, invocation=self.INVOCATION)
        self.assertIn("RESULT=42 COUNTS=0,0,0", stdout)
        log = (case / "update.log").read_text()
        payload = log.split("\n----- COMMAND: ", 1)[1].split("\n", 1)[1]
        self.assertEqual(payload, "native failure diagnostic\n\n")
        self.assertEqual(stderr, "")

    def test_smoke_capture_allocation_failure_never_executes_probe(self):
        case, stdout, _ = self.execute("update_run_logged_passthrough", r'''
printf 'executed\n' > "$TEST_ROOT/probe-executed"
printf 'omp 1.2.3\n'
''', setup=self.SETUP + '\nmktemp() { return 73; }\n', invocation=self.INVOCATION)
        self.assertIn("RESULT=126 COUNTS=0,0,0", stdout)
        self.assertFalse((case / "probe-executed").exists())
        self.assertIn("Unable to allocate update command capture", (case / "update.log").read_text())

    def test_smoke_capture_read_failure_cannot_report_success(self):
        case, stdout, _ = self.execute("update_run_logged_passthrough", r'''
printf 'executed\n' > "$TEST_ROOT/probe-executed"
printf 'omp 1.2.3\n'
''', setup=self.SETUP + '\ncat() { return 74; }\n', invocation=self.INVOCATION)
        self.assertIn("RESULT=126 COUNTS=0,0,0", stdout)
        self.assertTrue((case / "probe-executed").is_file())
        self.assertIn("Unable to read update command output", (case / "update.log").read_text())


class RetryCommandExecutionTests(UpdaterCommandHarness):
    """Real retry execution must finish without waiting for orphaned writers."""

    wrappers = (
        "run_cmd_with_retry_status",
        "run_cmd_attempt_with_retry",
        "run_cmd_bun_with_retry",
        "update_run_command_capture_with_retry",
    )

    def test_retry_external_commands_obey_existing_deadline_in_all_output_modes(self):
        for wrapper in self.wrappers:
            for verbose, quiet in ((False, True), (False, False), (True, True), (True, False)):
                with self.subTest(wrapper=wrapper, verbose=verbose, quiet=quiet):
                    case, stdout, _ = self.execute(wrapper,
                        'printf "attempt\\n" >> "$TEST_ROOT/attempts"\n'
                        'printf "before deadline\\n"\nprintf "diagnostic\\n" >&2\n'
                        'sleep 30\nprintf "must not finish\\n"', verbose=verbose, quiet=quiet)
                    expected_status = 0 if wrapper == "run_cmd_bun_with_retry" else 124
                    expected_failures = int(wrapper in ("run_cmd_with_retry_status", "run_cmd_bun_with_retry"))
                    self.assertIn(f"RESULT={expected_status} COUNTS=0,0,{expected_failures}", stdout)
                    self.assertEqual((case / "attempts").read_text(), "attempt\n")
                    log = (case / "update.log").read_text()
                    self.assertIn("before deadline\ndiagnostic", log)
                    self.assertNotIn("must not finish", log)

    def test_background_writer_does_not_delay_completed_retry_command(self):
        for wrapper in self.wrappers:
            for verbose, quiet in ((False, True), (False, False), (True, True), (True, False)):
                with self.subTest(wrapper=wrapper, verbose=verbose, quiet=quiet):
                    case, stdout, _ = self.execute(wrapper,
                        'sleep 30 &\nprintf "%s\\n" "$!" > "$TEST_ROOT/background-pid"\n'
                        'printf "foreground stdout\\n"\nprintf "foreground stderr\\n" >&2',
                        verbose=verbose, quiet=quiet)
                    expected_successes = int(wrapper != "update_run_command_capture_with_retry")
                    self.assertIn(f"RESULT=0 COUNTS={expected_successes},0,0", stdout)
                    log = (case / "update.log").read_text()
                    self.assertIn("foreground stdout\nforeground stderr", log)
                    self.assertIn("CAPTURE=foreground stdout\nforeground stderr", stdout)
                    if verbose and not quiet:
                        self.assertEqual(stdout.count("foreground stdout"), 2)

    def test_stdin_is_detached_and_permanent_failure_is_not_retried(self):
        for wrapper in self.wrappers:
            with self.subTest(wrapper=wrapper):
                case, stdout, _ = self.execute(wrapper,
                    'printf "attempt\\n" >> "$TEST_ROOT/attempts"\n'
                    'if IFS= read -r line; then printf "unexpected stdin\\n"; exit 70; fi\n'
                    'printf "ordinary failure\\n" >&2\nexit 7', stdin="sensitive caller input\n")
                expected_status = 0 if wrapper == "run_cmd_bun_with_retry" else 7
                self.assertIn(f"RESULT={expected_status} ", stdout)
                self.assertEqual((case / "attempts").read_text(), "attempt\n")
                self.assertIn("CAPTURE=ordinary failure", stdout)
                self.assertNotIn("sensitive caller input", stdout + (case / "update.log").read_text())

    def test_transient_retry_keeps_both_attempt_logs_and_final_status(self):
        for wrapper in self.wrappers:
            with self.subTest(wrapper=wrapper):
                case, stdout, _ = self.execute(wrapper,
                    'if [[ ! -f "$TEST_ROOT/attempted" ]]; then\n'
                    '  printf "first\\n" > "$TEST_ROOT/attempted"\n'
                    '  printf "connection reset by peer\\n" >&2\n  exit 7\nfi\n'
                    'printf "second\\n" >> "$TEST_ROOT/attempted"\nprintf "recovered\\n"')
                self.assertIn("RESULT=0 ", stdout)
                self.assertEqual((case / "attempted").read_text(), "first\nsecond\n")
                log = (case / "update.log").read_text()
                self.assertIn("connection reset by peer", log)
                self.assertIn("recovered", log)
                self.assertIn("CAPTURE=recovered", stdout)

    def test_capture_allocation_failure_never_runs_the_command(self):
        for wrapper in self.wrappers:
            with self.subTest(wrapper=wrapper):
                case, stdout, stderr = self.execute(wrapper,
                    'printf "executed\\n" > "$TEST_ROOT/unexpected"',
                    setup='mktemp() { return 1; }')
                self.assertFalse((case / "unexpected").exists())
                self.assertIn("command was not run", stderr)
                expected_status = 0 if wrapper == "run_cmd_bun_with_retry" else 1
                self.assertIn(f"RESULT={expected_status} COUNTS=0,0,", stdout)

    def test_capture_read_failure_does_not_report_success_or_retry_the_command(self):
        for wrapper in self.wrappers:
            for command_status in (0, 7):
                with self.subTest(wrapper=wrapper, command_status=command_status):
                    case, stdout, stderr = self.execute(wrapper,
                        'printf "attempt\\n" >> "$TEST_ROOT/attempts"\n'
                        f'exit {command_status}',
                        setup="cat() { printf 'connection reset partial capture\\n'; return 1; }")
                    self.assertEqual((case / "attempts").read_text(), "attempt\n")
                    self.assertIn("Unable to read update command output", stderr)
                    expected_status = 0 if wrapper == "run_cmd_bun_with_retry" else command_status or 1
                    self.assertIn(f"RESULT={expected_status} COUNTS=0,0,", stdout)
                    self.assertIn("CAPTURE=\n", stdout)
                    self.assertNotIn("Success:", (case / "update.log").read_text())

    def test_captured_function_state_and_exact_failure_survive(self):
        for wrapper in self.wrappers:
            with self.subTest(wrapper=wrapper):
                _, stdout, _ = self.execute(wrapper, "exit 0", setup=r'''
fixture_function() {
    UPDATE_LAST_HOLD_DETAILS="held fixture"
    printf 'function output\n'
    return 93
}
''', invocation="fixture_function")
                expected_status = 0 if wrapper == "run_cmd_bun_with_retry" else 93
                self.assertIn(f"RESULT={expected_status} ", stdout)
                self.assertIn("STATE=held fixture", stdout)
                self.assertIn("CAPTURE=function output", stdout)


class StreamedCommandExecutionTests(UpdaterCommandHarness):
    """Live updater output is independent of background installer writers."""

    wrappers = ("run_cmd", "update_run_logged_passthrough")

    def test_completed_stream_does_not_wait_for_background_writer(self):
        for wrapper in self.wrappers:
            for status in (0, 7):
                with self.subTest(wrapper=wrapper, status=status):
                    case, stdout, _ = self.execute(wrapper,
                        'sleep 30 &\nprintf "%s\\n" "$!" > "$TEST_ROOT/background-pid"\n'
                        'printf "foreground stdout\\n"\nprintf "foreground stderr\\n" >&2\n'
                        f'exit {status}', verbose=True, quiet=False)
                    expected_status = status if wrapper == "update_run_logged_passthrough" else 0
                    self.assertIn(f"RESULT={expected_status} ", stdout)
                    self.assertEqual(stdout.count("foreground stdout\nforeground stderr"), 1)
                    self.assertIn("foreground stdout\nforeground stderr", (case / "update.log").read_text())
                    if wrapper == "run_cmd":
                        self.assertIn(f"COUNTS={int(status == 0)},0,{int(status != 0)}", stdout)

    def test_live_stream_preserves_final_partial_line_and_function_state(self):
        def observe(process, case):
            # The command waits for this test to observe its actual output.
            # Buffering until completion would deadlock and fail this check.
            output = b""
            deadline = time.monotonic() + 3
            while b"live foreground\n" not in output:
                remaining = deadline - time.monotonic()
                self.assertGreater(remaining, 0, "foreground output was not streamed live")
                ready, _, _ = select.select([process.stdout], [], [], remaining)
                self.assertTrue(ready, "foreground output was not streamed live")
                chunk = os.read(process.stdout.fileno(), 65536)
                self.assertTrue(chunk, output.decode(errors="replace"))
                output += chunk
            self.assertIsNone(process.poll(), "command ended before the live-output handshake")
            (case / "continue").write_text("continue\n")
            return output.decode()

        for wrapper in self.wrappers:
            with self.subTest(wrapper=wrapper):
                case, stdout, _ = self.execute(wrapper,
                    'printf "live foreground\\n"\n'
                    'while [[ ! -f "$TEST_ROOT/continue" ]]; do sleep .02; done\n'
                    'printf "final partial: café"\nexit 7', verbose=True, quiet=False,
                    setup='fixture_function() { UPDATE_LAST_HOLD_DETAILS="native state"; "$TEST_ROOT/command"; }',
                    invocation="fixture_function", observe=observe)
                self.assertEqual(stdout.count("live foreground\n"), 1)
                self.assertEqual(stdout.count("final partial: café"), 1)
                self.assertIn("STATE=native state", stdout)
                self.assertIn("live foreground\nfinal partial: café", (case / "update.log").read_text())
                self.assertIn(f"RESULT={7 if wrapper == 'update_run_logged_passthrough' else 0} ", stdout)

    def test_stream_shutdown_survives_ignored_term_and_keeps_existing_command_deadlines(self):
        for wrapper in self.wrappers:
            with self.subTest(wrapper=wrapper):
                _, stdout, _ = self.execute(wrapper,
                    'sleep .35\nprintf "allowed foreground completed\\n"',
                    verbose=True, quiet=False, setup=r'''
trap '' TERM
fixture_function() { "$TEST_ROOT/command"; }
''', invocation="fixture_function")
                # The existing 0.2s external-command deadline does not cap a
                # function whose own runner intentionally allows this job.
                self.assertIn("RESULT=0 ", stdout)
                self.assertIn("allowed foreground completed", stdout)

        case, stdout, _ = self.execute("run_cmd", 'printf "before deadline\\n"\nsleep 30',
                                        verbose=True, quiet=False)
        self.assertIn("RESULT=0 COUNTS=0,0,1", stdout)
        self.assertIn("exit code: 124", (case / "update.log").read_text())

    def test_stream_allocation_failure_never_executes_the_command(self):
        for wrapper in self.wrappers:
            with self.subTest(wrapper=wrapper):
                case, stdout, stderr = self.execute(wrapper,
                    'printf "executed\\n" > "$TEST_ROOT/unexpected"', verbose=True, quiet=False,
                    setup='mktemp() { return 1; }')
                self.assertFalse((case / "unexpected").exists())
                self.assertIn("command was not run", stderr)
                self.assertIn(f"RESULT={int(wrapper != 'run_cmd')} ", stdout)
                self.assertNotIn("Success:", (case / "update.log").read_text())

    def test_stream_failure_is_reported_without_replacing_native_command_failure(self):
        for status in (0, 7):
            with self.subTest(status=status):
                _, stdout, stderr = self.execute("update_run_logged_passthrough",
                    f'printf "foreground output\\n"\nexit {status}', verbose=True, quiet=False,
                    setup=r'''
printf '#!/bin/sh\nexit 23\n' > "$TEST_ROOT/failed-tee"
chmod 700 "$TEST_ROOT/failed-tee"
update_system_binary_path() {
    if [[ "$1" == tee ]]; then printf '%s\n' "$TEST_ROOT/failed-tee"; else command -v "$1"; fi
}
''')
                self.assertIn(f"RESULT={status or 1} ", stdout)
                self.assertIn("Unable to finish streaming update output", stderr)

    def test_updater_death_does_not_leave_output_helpers_waiting_on_installer(self):
        def terminate_after_output(process, case):
            output = b""
            deadline = time.monotonic() + 3
            while b"installer started\n" not in output:
                remaining = deadline - time.monotonic()
                self.assertGreater(remaining, 0)
                ready, _, _ = select.select([process.stdout], [], [], remaining)
                self.assertTrue(ready)
                chunk = os.read(process.stdout.fileno(), 65536)
                self.assertTrue(chunk, output.decode(errors="replace"))
                output += chunk
            process.kill()
            process.wait(timeout=3)
            return output.decode()

        # Tail/tee own the output pipe. The harness must reach EOF without
        # waiting for the still-running fixture installer after this signal.
        _, stdout, stderr = self.execute("update_run_logged_passthrough",
            'printf "%s\\n" "$$" > "$TEST_ROOT/background-pid"\n'
            'printf "installer started\\n"\nsleep 30\nprintf "installer finished\\n"',
            verbose=True, quiet=False, observe=terminate_after_output, expected_returncode=-9)
        self.assertEqual(stderr, "")
        self.assertNotIn("installer finished", stdout)


class PublicMaintenanceHandoffTests(unittest.TestCase):
    """Exercise complete public dispatchers without changing host accounts.

    Root dispatch runs in a private user/mount namespace. Only passwd metadata
    and runuser are fixtures: the latter records the command's environment
    through the real env executable instead of claiming a real account switch.
    Same-account dispatch uses the real current identity. No repair executes.
    """

    SELECTORS = ("CLAUDE_CONFIG_DIR", "DATABASE_URL", "STORAGE_ROOT",
                 "XDG_CONFIG_HOME", "XDG_DATA_HOME")
    UPDATE_SELECTORS = UPDATE_ACCOUNT_ENV_NAMES + (
        "CARGO_HOME", "RUSTUP_HOME", "RUSTUP_TOOLCHAIN",
        "NVM_DIR", "NVM_BIN", "NVM_INC", "NVM_CD_FLAGS",
        "NVM_NODEJS_ORG_MIRROR", "NVM_IOJS_ORG_MIRROR", "NVM_AUTH_HEADER",
        "NPM_CONFIG_USERCONFIG", "npm_config_userconfig",
        "NPM_CONFIG_GLOBALCONFIG", "npm_config_globalconfig",
        "NPM_CONFIG_CACHE", "npm_config_cache", "NPM_CONFIG_PREFIX", "npm_config_prefix",
        "PREFIX", "NODE_OPTIONS", "NODE_PATH", "BASH_ENV", "ENV",
    )

    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="acfs-public-handoff-"))
        self.home = self.base / "target-home"
        self.caller = self.base / "caller-home"
        self.acfs_home = self.home / ".acfs"
        self.library = self.acfs_home / "scripts/lib"
        self.library.mkdir(parents=True)
        (self.acfs_home / "bin").mkdir()
        (self.home / ".local/bin").mkdir(parents=True)
        self.caller.mkdir()
        self.capture = self.base / "capture.py"
        self.capture.write_text(
            "import json, os, pathlib, sys\n"
            "pathlib.Path(os.environ['TEST_ROOT'], 'captured.json').write_text(\n"
            "    json.dumps({'env': dict(os.environ), 'args': sys.argv[1:]}))\n")
        capture_shell = "#!/bin/bash\nexec /usr/bin/python3 " + shlex.quote(str(self.capture)) + ' "$@"\n'
        # Stop at the first repair-helper load, after the actual Doctor
        # bootstrap and public wrapper have resolved the runtime context.
        (self.library / "doctor_fix.sh").write_text(capture_shell)
        self.doctor = self.library / "doctor.sh"
        self.doctor.write_text((ROOT / "scripts/lib/doctor.sh").read_text())
        (self.library / "update.sh").write_text(capture_shell)
        self.updater = self.acfs_home / "bin/acfs-update"
        self.updater.write_text((ROOT / "scripts/acfs-update").read_text())
        entry = self.acfs_home / "bin/acfs"
        # Capture each public boundary independently. The global wrapper has
        # already changed identity before the separate updater wrapper starts;
        # the latter cannot recover the original caller's ownership from UID.
        entry.write_text("#!/bin/bash\n"
                         'if [[ "${1:-}" == update ]]; then\n    shift\n    exec /usr/bin/python3 ' +
                         shlex.quote(str(self.capture)) + ' "$@"\nfi\nexec /bin/bash ' +
                         shlex.quote(str(self.doctor)) + ' "$@"\n')
        entry.chmod(0o755)
        self.wrapper = self.base / "acfs-global"
        self.wrapper.write_text((ROOT / "scripts/acfs-global").read_text())
        self.transport = self.base / "runuser"
        self.transport.write_text(r'''#!/bin/bash
set -euo pipefail
[[ "$1" == -u && "$2" == handoffowner && "$3" == -- ]]
printf '%s\n' "$2" > "$TEST_ROOT/transport-user"
shift 3
env_binary="$1"
shift
env_arguments=()
while (( $# > 0 )); do
    case "$1" in /bin/bash|/usr/bin/bash) break ;; esac
    env_arguments+=("$1")
    shift
done
(( $# >= 2 ))
exec "$env_binary" "${env_arguments[@]}" /usr/bin/python3 "$TEST_ROOT/capture.py" "$@"
''')
        self.transport.chmod(0o755)

    def run_public(self, entrypoint, *, cross):
        updating = entrypoint in ("update", "global-update")
        selector_names = self.UPDATE_SELECTORS if updating else self.SELECTORS
        account = "handoffowner" if cross else pwd.getpwuid(os.geteuid()).pw_name
        state_file = self.acfs_home / "state.json"
        state_file.write_text(json.dumps({
            "schema_version": 3, "target_user": account, "target_home": str(self.home),
            "bin_dir": str(self.home / ".local/bin"), "mode": "safe",
        }))
        selected_home = self.caller if cross else self.home
        selectors = {name: str(selected_home / ("custom " + name.lower())) for name in selector_names}
        selectors["DATABASE_URL"] = "sqlite:///" + str(selected_home / "mail.sqlite3").lstrip("/")
        env = {
            "PATH": "/usr/bin:/bin", "HOME": str(selected_home), "TEST_ROOT": str(self.base),
            "ACFS_STATE_FILE": str(state_file), "ACFS_SYSTEM_STATE_FILE": str(state_file),
            "ACFS_HOME": str(self.acfs_home), "ACFS_MODE": "safe", "ACFS_REF": "fixture-ref",
            "ACFS_RAW": "https://example.invalid/acfs", "ACFS_OFFLINE": "1",
            "NO_COLOR": "1", **selectors,
        }
        if entrypoint in ("global", "global-update"):
            script = self.wrapper
            args = ["update" if updating else "doctor"]
        else:
            script = self.updater if updating else self.doctor
            args = []
        args.extend(["--stack-only", "--yes"] if updating else ["--fix", "--yes"])
        command = ["/bin/bash", str(script), *args]
        if cross:
            unshare = shutil.which("unshare")
            runuser = shutil.which("runuser")
            if not unshare or not runuser:
                self.skipTest("public root handoff fixture requires unshare and runuser")
            namespace = [unshare, "--user", "--map-root-user", "--mount"]
            probe = subprocess.run([*namespace, "/usr/bin/true"], capture_output=True, timeout=5)
            if probe.returncode:
                self.skipTest("private user/mount namespaces unavailable: " + probe.stderr.decode().strip())
            passwd = self.base / "passwd"
            passwd.write_text(f"root:x:0:0::/root:/bin/bash\nhandoffowner:x:1000:1000::{self.home}:/bin/bash\n")
            command = [*namespace, "/bin/bash", "-c", r'''
set -euo pipefail
mount --bind "$TEST_ROOT/passwd" /etc/passwd
mount --bind "$TEST_ROOT/runuser" "$1"
shift
exec "$@"
''', "_", runuser, *command]
        result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=15)
        (self.base / "stdout").write_text(result.stdout)
        (self.base / "stderr").write_text(result.stderr)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr + "\nArtifacts: " + str(self.base))
        capture = json.loads((self.base / "captured.json").read_text())
        for name in ("ACFS_STATE_FILE", "ACFS_SYSTEM_STATE_FILE", "ACFS_HOME", "ACFS_MODE",
                     "ACFS_REF", "ACFS_RAW", "ACFS_OFFLINE"):
            self.assertEqual(capture["env"].get(name), env[name], name)
        if cross:
            self.assertEqual((self.base / "transport-user").read_text(), "handoffowner\n")
            self.assertEqual(capture["env"]["HOME"], str(self.home))
            self.assertEqual(capture["env"]["TARGET_HOME"], str(self.home))
            self.assertEqual(capture["env"]["ACFS_BIN_DIR"], str(self.home / ".local/bin"))
            for name in selector_names:
                self.assertNotIn(name, capture["env"], name + " crossed the account boundary")
        else:
            self.assertFalse((self.base / "transport-user").exists())
            for name, value in selectors.items():
                self.assertEqual(capture["env"].get(name), value, name)

    def test_global_wrapper_clears_foreign_repair_selectors(self):
        self.run_public("global", cross=True)

    def test_direct_doctor_clears_foreign_repair_selectors(self):
        self.run_public("doctor", cross=True)

    def test_global_wrapper_preserves_same_account_repair_selectors(self):
        self.run_public("global", cross=False)

    def test_direct_doctor_preserves_same_account_repair_selectors(self):
        self.run_public("doctor", cross=False)

    def test_global_update_clears_foreign_agent_and_runtime_stores(self):
        self.run_public("global-update", cross=True)

    def test_update_wrapper_clears_foreign_agent_and_runtime_stores(self):
        self.run_public("update", cross=True)

    def test_global_update_preserves_same_account_agent_and_runtime_stores(self):
        self.run_public("global-update", cross=False)

    def test_update_wrapper_preserves_same_account_agent_and_runtime_stores(self):
        self.run_public("update", cross=False)


if __name__ == "__main__":
    unittest.main(verbosity=2)
