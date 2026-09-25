#!/usr/bin/env python3
"""Module migration tests: real files/processes, inert installer boundary."""
import importlib.util
import json
import os
import shlex
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "import-config.py"
spec = importlib.util.spec_from_file_location("acfs_import_config", SCRIPT)
import_config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(import_config)


class ExportTests(unittest.TestCase):
    def test_json_export_and_duplicate_modules(self):
        parsed = import_config.parse_export(json.dumps({
            "settings": {"mode": "vibe", "shell": "zsh"},
            "modules": ["agents.claude", "lang.bun", "agents.claude"],
            "tools": {"bun": {"installed": True, "version": "1.2.3"}},
        }))
        self.assertEqual(parsed["modules"], ["agents.claude", "lang.bun"])
        self.assertEqual(parsed["source_mode"], "vibe")

    def test_minimal_with_comments_and_crlf(self):
        parsed = import_config.parse_export("# exported modules\r\n\r\nlang.bun\r\nagents.codex\r\n")
        self.assertEqual(parsed["modules"], ["lang.bun", "agents.codex"])
        self.assertEqual(parsed["source_format"], "minimal")

    def test_invalid_exports_fail_closed(self):
        cases = ["", "# empty", "{}", "[]", '{"modules": []}',
                 '{"modules": "lang.bun"}', '{"modules": [null]}',
                 '{"modules": [42]}', '{"modules": [true]}',
                 '{"modules": ["lang.bun"], "modules": ["agents.codex"]}',
                 '{"modules": ["lang.bun"], "settings": {"mode": "safe", "mode": "vibe"}}',
                 '{"modules": ["lang.bun"], "x": NaN}',
                 '{"modules": ["lang.bun"]} {}', "--skip-preflight", "lang.bun,agents.codex",
                 "lang.bun $(touch /tmp/sentinel)", "LANG.BUN", "lang.bun\x00", "../lang.bun",
                 json.dumps({"modules": ["lang.bun"] * 1025}),
                 json.dumps({"modules": ["x" * 129]})]
        for text in cases:
            with self.subTest(text=text[:100]):
                with self.assertRaises(import_config.ImportConfigError):
                    import_config.parse_export(text)

    def test_read_limits_utf8_bom_and_nonregular_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "export"
            path.write_bytes(b"\xef\xbb\xbflang.bun\n")
            self.assertEqual(import_config.read_export(str(path)), "lang.bun\n")
            for data in (b"x" * (import_config.LIMIT + 1), b"\xff"):
                path.write_bytes(data)
                with self.assertRaises(import_config.ImportConfigError):
                    import_config.read_export(str(path))
            fifo = Path(directory) / "fifo"
            os.mkfifo(fifo)
            with self.assertRaises(import_config.ImportConfigError):
                import_config.read_export(str(fifo))


class YamlExportTests(unittest.TestCase):
    def test_default_export_schema(self):
        exported = """# ACFS Configuration Export
# Generated: 2026-09-25T12:30:00-04:00
# Hostname: source-host
# ACFS Version: 0.9.0

settings:
  mode: 'vibe'
  shell: 'zsh'

modules:
  - 'lang.bun'
  - 'agents.claude'
  - 'lang.bun'

tools:
  bun:
    version: '1.2.3'
    installed: true

agents:
  claude:
    version: '2.0.0'
    installed: true

flywheel_stack:
"""
        parsed = import_config.parse_export(exported)
        self.assertEqual(parsed["source_format"], "yaml")
        self.assertEqual(parsed["source_mode"], "vibe")
        self.assertEqual(parsed["modules"], ["lang.bun", "agents.claude"])

    def test_quotes_comments_and_inert_metadata(self):
        text = r"""settings:
  mode: "safe" # explicit mode
modules:
  - 'lang.bun' # runtime
  - "agents.codex"
  - stack.beads_rust
tools:
  bun:
    version: 'vendor''s $(touch NEVER) \n literal'
    installed: true
"""
        parsed = import_config.parse_export(text)
        self.assertEqual(parsed["modules"], ["lang.bun", "agents.codex", "stack.beads_rust"])
        self.assertEqual(import_config.yaml_scalar("'vendor''s version'"), "vendor's version")

    def test_reject_ambiguous_and_executable_yaml_constructs(self):
        cases = [
            "modules: [lang.bun]", "modules: &modules\n  - lang.bun",
            "modules:\n  - *alias", "modules:\n  - !!str lang.bun",
            "modules:\n  - 'lang.bun'\nmodules:\n  - 'agents.codex'",
            "modules:\n  - lang.bun\nsettings:\n  mode: safe\n  mode: vibe",
            "modules:\n  - lang.bun\ntools:\n  bun:\n    version: '1'\n    version: '2'",
            "modules:\n  - lang.bun\n---\nmodules:\n  - agents.codex",
            "modules:\n  - lang.bun\nsettings:\n  mode: |\n    vibe",
            "modules:\n\t- lang.bun", "modules:\n    - lang.bun",
            "modules:\n  mode: safe", "modules:\n  - 'lang.bun' garbage",
            "modules:\n  - \"lang.bun'", "modules:\n  - lang.bun\n  <<: *defaults",
            "modules:\n  - lang.bun\nsettings:\n    mode: safe",
            "modules:\n  - lang.bun\nsettings:\n  mode: !!python/object/apply:os.system 'false'",
        ]
        for text in cases:
            with self.subTest(text=text):
                with self.assertRaises(import_config.ImportConfigError):
                    import_config.parse_export(text)

    def test_empty_destination_is_valid_but_empty_source_is_not(self):
        for text in ("", "# empty destination", '{"modules": []}', "modules:\n\ntools:\n"):
            with self.subTest(text=text):
                self.assertEqual(import_config.parse_export(text, allow_empty=True)["modules"], [])
                with self.assertRaises(import_config.ImportConfigError):
                    import_config.parse_export(text)
        for text in ("{}", "[]", "settings:\n  mode: safe"):
            with self.assertRaises(import_config.ImportConfigError):
                import_config.parse_export(text, allow_empty=True)


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.export = self.directory / "source export.json"
        self.export.write_text(json.dumps({"settings": {"mode": "vibe"},
            "modules": ["agents.claude", "lang.bun", "agents.claude"],
            "tools": {"bun": {"version": "$(touch NEVER)", "installed": True}}}))
        self.trace = self.directory / "trace.jsonl"
        self.installer = self.directory / "trusted checkout" / "install.sh"
        self.installer.parent.mkdir()
        # Use the current interpreter by absolute path: the helper must not
        # depend on shell command lookup or invoke anything from the export.
        self.installer.write_text("#!/bin/bash\n" +
            "exec " + shlex.quote(sys.executable) + " - \"$@\" <<'PYCODE'\n" +
            "import json, os, signal, sys, time\n"
            "args = sys.argv[1:]\n"
            "with open(os.environ['TRACE'], 'a') as f: f.write(json.dumps(args) + '\\n')\n"
            "if '--print-plan' in args:\n"
            "    if 'invalid.module' in args: print('Unknown module', file=sys.stderr); sys.exit(7)\n"
            "    if os.environ.get('PLAN_SLEEP'): time.sleep(10)\n"
            "    if os.environ.get('PLAN_LARGE'): print('x' * (2 * 1024 * 1024))\n"
            "    print('users.ubuntu -> lang.bun -> agents.claude')\n"
            "else:\n"
            "    print('INSTALLER EXECUTED')\n"
            "    if os.environ.get('INSTALL_SIGNAL'): os.kill(os.getpid(), signal.SIGTERM)\n"
            "    sys.exit(int(os.environ.get('INSTALL_EXIT', '0')))\n"
            "PYCODE\n")
        self.env = {**os.environ, "TRACE": str(self.trace)}

    def run_cli(self, *options, data=None, **environment):
        return subprocess.run([sys.executable, str(SCRIPT), str(self.export),
            "--installer", str(self.installer), *options], input=data, text=True,
            capture_output=True, env={**self.env, **environment}, timeout=10)

    def calls(self):
        return [json.loads(line) for line in self.trace.read_text().splitlines()] if self.trace.exists() else []

    def test_default_preview_uses_resolver_and_safe_destination(self):
        result = self.run_cli("--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["mode"], "safe")
        self.assertEqual(report["source_mode"], "vibe")
        self.assertFalse(report["pins_tool_versions"])
        self.assertFalse(report["restores_credentials"])
        self.assertIn("users.ubuntu", report["installer_plan"])
        self.assertEqual(len(self.calls()), 1)
        self.assertEqual(self.calls()[0], ["--mode", "safe", "--skip-ubuntu-upgrade", "--only",
                                         "agents.claude", "--only", "lang.bun", "--print-plan"])
        self.assertNotIn("INSTALLER EXECUTED", result.stdout)

    def test_apply_validates_first_then_preserves_arguments_and_exit_status(self):
        result = self.run_cli("--apply", "--yes", "--resume", "--mode", "vibe", INSTALL_EXIT="23")
        self.assertEqual(result.returncode, 23, result.stderr)
        calls = self.calls()
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0], calls[1] + ["--print-plan"])
        self.assertIn("--resume", calls[1])
        self.assertIn("--yes", calls[1])
        self.assertIn("vibe", calls[1])
        self.assertIn("INSTALLER EXECUTED", result.stdout)

    def test_rejected_selection_never_installs(self):
        self.export.write_text('{"modules": ["invalid.module"]}')
        result = self.run_cli("--apply")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Unknown module", result.stderr)
        self.assertEqual(len(self.calls()), 1)

    def test_empty_export_never_invokes_installer(self):
        self.export.write_text('{"modules": []}')
        result = self.run_cli("--apply")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_shell_startup_hooks_cannot_run(self):
        hook = self.directory / "hook.sh"
        marker = self.directory / "hook-ran"
        hook.write_text("touch " + str(marker) + "\n")
        result = self.run_cli("--apply", BASH_ENV=str(hook), ENV=str(hook))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(marker.exists())

    def test_plan_timeout_never_installs(self):
        result = self.run_cli("--apply", "--plan-timeout", "1", PLAN_SLEEP="1")
        self.assertEqual(result.returncode, 2)
        self.assertIn("timed out", result.stderr)
        self.assertEqual(len(self.calls()), 1)

    def test_json_apply_and_unknown_options_are_rejected_before_planning(self):
        for options in (("--apply", "--json"), ("--apply", "--no-deps"), ("--ap",)):
            with self.subTest(options=options):
                result = self.run_cli(*options)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(self.calls(), [])

    def test_stdin_export_preview(self):
        self.export = "-"
        result = self.run_cli("--json", data="lang.bun\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["modules"], ["lang.bun"])

    def test_stdin_apply_requires_explicit_noninteractive_mode(self):
        self.export = "-"
        result = self.run_cli("--apply", data="lang.bun\n")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.calls(), [])
        result = self.run_cli("--apply", "--yes", data="lang.bun\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls()), 2)

    def test_default_yaml_can_be_applied(self):
        self.export.write_text("settings:\n  mode: 'vibe'\nmodules:\n  - 'agents.claude'\n  - 'lang.bun'\n")
        result = self.run_cli("--apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls()), 2)
        self.assertEqual(self.calls()[1][:2], ["--mode", "safe"])

    def test_comparison_only_installs_missing_and_never_removes_extras(self):
        current = self.directory / "destination.yaml"
        current.write_text("modules:\n  - 'lang.bun'\n  - 'agents.codex'\n")
        result = self.run_cli("--against", str(current), "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["modules"], ["agents.claude", "lang.bun"])
        self.assertEqual(report["install_modules"], ["agents.claude"])
        self.assertEqual(report["comparison"]["basis"], "supplied_export")
        self.assertEqual(report["comparison"]["already_present"], ["lang.bun"])
        self.assertEqual(report["comparison"]["extra"], ["agents.codex"])
        self.assertEqual(self.calls()[0].count("--only"), 1)
        self.assertIn("agents.claude", self.calls()[0])
        self.assertNotIn("agents.codex", self.calls()[0])
        self.assertNotIn("lang.bun", self.calls()[0])
        result = self.run_cli("--against", str(current), "--apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[-1].count("--only"), 1)

    def test_comparison_noop_never_falls_through_to_default_install(self):
        current = self.directory / "destination.json"
        current.write_text('{"modules": ["lang.bun", "agents.claude", "agents.codex"]}')
        self.installer = self.directory / "does-not-exist.sh"
        result = self.run_cli("--against", str(current), "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["status"], "noop")
        self.assertEqual(report["install_modules"], [])
        self.assertEqual(report["installer_argv"], [])
        self.assertIsNone(report["installer_command"])
        result = self.run_cli("--against", str(current), "--apply", "--yes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("No installer was invoked", result.stdout)
        self.assertEqual(self.calls(), [])

    def test_empty_comparison_installs_the_entire_nonempty_source_selection(self):
        current = self.directory / "empty.modules"
        current.write_text("")
        result = self.run_cli("--against", str(current), "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["install_modules"], ["agents.claude", "lang.bun"])
        self.assertEqual(self.calls()[0].count("--only"), 2)

    def test_invalid_comparison_never_invokes_installer(self):
        current = self.directory / "invalid.json"
        current.write_text("{}")
        result = self.run_cli("--against", str(current), "--apply")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_comparison_stdin_and_duplicate_stdin_are_guarded(self):
        result = self.run_cli("--against", "-", "--json", data="lang.bun\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["install_modules"], ["agents.claude"])
        count = len(self.calls())
        result = self.run_cli("--against", "-", "--apply", data="lang.bun\n")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(len(self.calls()), count)
        self.export = "-"
        result = self.run_cli("--against", "-", "--json", data="lang.bun\n")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(len(self.calls()), count)

    def test_oversized_plan_refuses_apply(self):
        result = self.run_cli("--apply", PLAN_LARGE="1")
        self.assertEqual(result.returncode, 2)
        self.assertIn("exceeds 1 MiB", result.stderr)
        self.assertEqual(len(self.calls()), 1)

    def test_installer_signal_is_not_reported_as_success(self):
        result = self.run_cli("--apply", INSTALL_SIGNAL="1")
        self.assertEqual(result.returncode, -15)
        self.assertEqual(len(self.calls()), 2)

    def test_export_cannot_select_executable_paths_or_commands(self):
        marker = self.directory / "must-not-exist"
        self.export.write_text(json.dumps({
            "modules": ["lang.bun"], "installer": str(marker),
            "settings": {"mode": "vibe", "target_home": "/untrusted/source/path"},
            "commands": ["touch " + str(marker)],
            "tools": {"bun": {"version": "$(touch " + str(marker) + ")"}},
        }))
        result = self.run_cli("--apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(marker.exists())
        self.assertEqual(self.calls()[1], ["--mode", "safe", "--skip-ubuntu-upgrade", "--only", "lang.bun"])


if __name__ == "__main__":
    unittest.main()
