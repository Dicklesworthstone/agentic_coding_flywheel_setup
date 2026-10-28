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

COMMON = r'''
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
        if [[ "$1" == sudo ]]; then
            [[ "$TEST_TRANSPORT" == usage ]] || return 1
            printf '%s\n' "$TEST_ROOT/transport-usage"
            return 0
        fi
        [[ "$TEST_TRANSPORT" != none || "$1" != runuser ]] || return 1
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
        self.library = self.base / "update.sh"
        self.library.write_text(self.source)
        self.library.chmod(0o644)
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
        path.mkdir(parents=True, exist_ok=True)
        path.chmod(0o755)
        self.own(path)

    def prepare_rust_homes(self, rust_home, cargo_home, *, nightly=True):
        self.owned_dir(rust_home)
        self.owned_dir(cargo_home)
        listing = "stable-x86_64-unknown-linux-gnu (default)\n"
        if nightly:
            listing += "nightly-x86_64-unknown-linux-gnu\n"
        (rust_home / "toolchains.txt").write_text(listing)

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
        (self.rust_home / "toolchains.txt").write_text("stable-x86_64-unknown-linux-gnu (default)\n")
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
        (self.base / "version-tail-claude").write_text("version metadata\n" * 8192)
        names = (*generic_tools, *special)
        command = "\n".join("printf 'VERSION %s=[%s]\\n' " + shlex.quote(name) +
                            ' "$(get_version ' + shlex.quote(name) + ')"' for name in names)
        output = self.run_update(cross=True, command=command)
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

    def test_native_bun_upgrade_runs_as_target_and_preserves_failure_accounting(self):
        self.write_native_tool("bun")
        (self.base / "mode-bun").write_text("failure\n")
        output = self.run_update(cross=True, command="update_bun")
        self.assert_target_events(self.events())
        self.assertEqual([e[-1] for e in self.events()], ["--version", "upgrade", "--version"])
        self.assertIn("COUNTS=0,0,1", output)
        self.assertIn("exit code: 17", (self.base / "update.log").read_text())
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_native_uv_retries_as_target_and_succeeds_without_fallback(self):
        self.write_native_tool("uv")
        (self.base / "mode-uv").write_text("transient\n")
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
        (self.base / "mode-uv").write_text("failure\n")
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
        (self.base / "mode-atuin").write_text("transient\n")
        output = self.run_update(cross=True, command="update_atuin")
        self.assert_target_events(self.events())
        args = [e[-1] for e in self.events()]
        self.assertEqual(args.count("--help"), 1)
        self.assertEqual(args.count("self-update"), 2)
        self.assertIn("COUNTS=1,0,0", output)
        self.assertEqual(list(self.caller.iterdir()), [])

    def test_atuin_compatibility_match_drains_trailing_help_output(self):
        self.write_native_tool("atuin")
        (self.base / "help-tail-atuin").write_text("additional help text\n" * 8192)
        output = self.run_update(cross=True, command="update_atuin")
        self.assert_target_events(self.events())
        self.assertIn("self-update", [e[-1] for e in self.events()])
        self.assertIn("COUNTS=1,0,0", output)

    def test_nightly_selection_drains_trailing_toolchain_list_output(self):
        (self.rust_home / "toolchains.txt").write_text(
            "nightly-x86_64-unknown-linux-gnu\n" + "stable-fixture-toolchain\n" * 8192)
        output = self.run_update(cross=True)
        self.assert_target_events(self.events())
        self.assertIn("update nightly", [e[-1] for e in self.events()])
        self.assertIn("COUNTS=3,0,0", output)

    def test_failed_dedicated_atuin_updater_does_not_invoke_setup(self):
        self.write_native_tool("atuin")
        self.write_native_tool("atuin-update", directory=self.home / ".atuin/bin")
        (self.base / "mode-atuin-update").write_text("failure\n")
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
            (self.base / f"mode-{tool}").write_text("hang\n")
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
