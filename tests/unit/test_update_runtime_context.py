"""Exercise runtime updates with real account transitions and inert executables.

The complete updater, binary lookup, target runner, timeout, logging and failure
accounting are real. Only passwd home metadata points at isolated fixture homes;
no account, package, toolchain or network service is changed. A transport fixture
can hide sudo to exercise the real runuser fallback. All artifacts are retained.
"""
import os
from pathlib import Path
import pwd
import shlex
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(os.environ.get("ACFS_UPDATE_TEST_LIBRARY", ROOT / "scripts/lib/update.sh"))

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
        cls.library = cls.artifacts / "update.sh"
        cls.library.write_text(cls.source)
        cls.library.chmod(0o444)
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
    bun:upgrade|uv:'self update'|atuin:self-update|atuin-update:)
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
