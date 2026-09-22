#!/usr/bin/env python3
"""Exercise the real Bash success screen with fixture NTM/provider executables.

No agents, tmux server, network, or login flows are started. Fixtures are retained
in a named temporary directory to make failures inspectable.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
SCREEN = REPO / "scripts/lib/newproj_screens/screen_success.sh"
BASH = shutil.which("bash")
JQ = shutil.which("jq")

NTM = r'''
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ["CALLS"], "a") as log:
    log.write(json.dumps({"argv": args, "cwd": os.getcwd()}) + "\n")
if os.environ.get("SCOPE_LOG") and args and args[0] != "attach":
    with open(os.environ["SCOPE_LOG"], "a") as log:
        log.write(json.dumps({key: os.environ.get(key) for key in ("BEADS_DIR", "BEADS_DB", "BD_DB", "BD_DATABASE", "BEADS_JSONL")}) + "\n")
if args and args[0] == "attach":
    print("ATTACHED")
    sys.exit(0)
mode = os.environ.get("FAKE_NTM_MODE", "ok")
if mode == "exit":
    print("existing session or launch failure", file=sys.stderr)
    sys.exit(2)
if mode == "invalid":
    print("not JSON")
    sys.exit(0)
values = dict(arg[2:].split("=", 1) for arg in args if "=" in arg)
count = sum(int(values.get("spawn-" + agent, "0")) for agent in ("cc", "cod", "agy"))
response = {
    "success": True, "session": values["robot-spawn"],
    "working_dir": values["spawn-dir"], "agents": [{} for _ in range(count)]
}
if mode == "false": response["success"] = False
if mode == "string_success": response["success"] = "true"
if mode == "wrong_session": response["session"] = "another-project"
if mode == "wrong_dir": response["working_dir"] = "/another-project"
if mode == "partial": response["agents"].pop()
if mode == "error": response["error"] = "provider failed"
if mode == "dry_run": response["dry_run"] = True
if mode == "agent_error": response["agents"][0]["error"] = "agent failed"
if mode == "multiple": print(json.dumps({"success": False}))
if "--spawn-assign-work" in args:
    assignment = os.environ.get("ASSIGN_MODE", "ok")
    response["assignments"] = [{"claimed": True, "prompt_sent": True}]
    if assignment == "none": response["assignments"] = []
    if assignment == "partial": response["assignments"].append({"claimed": True, "prompt_sent": False})
    if assignment == "invalid": response["assignments"] = [{"claimed": "true", "prompt_sent": True}]
    if assignment == "null": response["assignments"] = None
    if assignment == "missing": del response["assignments"]
print(json.dumps(response))
'''

BR = r'''
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ["BR_CALLS"], "a") as log:
    log.write(json.dumps({"argv": args, "cwd": os.getcwd()}) + "\n")
if os.environ.get("SCOPE_LOG"):
    with open(os.environ["SCOPE_LOG"], "a") as log:
        log.write(json.dumps({key: os.environ.get(key) for key in ("BEADS_DIR", "BEADS_DB", "BD_DB", "BD_DATABASE", "BEADS_JSONL")}) + "\n")
queue = Path(os.environ["BR_QUEUE"])
mode = os.environ.get("BR_MODE", "ok")
if args == ["ready", "--json"]:
    if mode == "read_error": sys.exit(2)
    print(queue.read_text())
elif args and args[0] == "create":
    if mode == "create_error": sys.exit(2)
    title = next(arg.split("=", 1)[1] for arg in args if arg.startswith("--title="))
    queue.write_text(json.dumps([{"id": "bd-first", "title": title}]))
    print("invalid id" if mode == "create_invalid" else "bd-first")
else:
    sys.exit(95)
'''

PRELUDE = r'''
set -euo pipefail
source "$SCREEN"
state_get() {
    case "$1" in
        project_name) printf '%s\n' "$PROJECT_NAME" ;;
        project_dir) printf '%s\n' "$PROJECT" ;;
        *) printf 'false\n' ;;
    esac
}
tui_cleanup() { printf 'cleanup\n' >> "$EVENTS"; }
finalize_logging() { printf 'finalize\n' >> "$EVENTS"; }
log_input() { :; }
render_success_screen() { :; }
'''

@unittest.skipUnless(BASH and JQ, "Bash and jq are required")
class LaunchTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="acfs-ntm-launch-"))
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.project = self.root / "project spaces ' $(literal); [brackets]"
        self.project.mkdir()
        self.calls = self.root / "calls.jsonl"
        self.events = self.root / "events"
        self.executable("ntm", "#!" + sys.executable + "\n" + NTM)
        self.executable("tmux", "#!" + BASH + "\nexit 0\n")
        self.bin.joinpath("jq").symlink_to(JQ)
        for agent in ("claude", "codex", "agy"):
            self.executable(agent, "#!" + BASH + "\nprintf 'UNEXPECTED PROVIDER EXECUTION' >&2\nexit 91\n")
        self.env = {
            **os.environ, "PATH": str(self.bin), "SCREEN": str(SCREEN),
            "PROJECT": str(self.project), "PROJECT_NAME": "my-app",
            "CALLS": str(self.calls), "EVENTS": str(self.events),
            "FAKE_NTM_MODE": "ok", "LC_ALL": "C",
        }

    def enable_work(self, ready=None):
        self.project.joinpath(".beads").mkdir()
        self.queue = self.root / "queue.json"
        self.queue.write_text(json.dumps(ready if ready is not None else [{"id": "bd-ready", "title": "Implement the feature"}]))
        self.br_calls = self.root / "br-calls.jsonl"
        self.env.update(BR_CALLS=str(self.br_calls), BR_QUEUE=str(self.queue), BR_MODE="ok", ASSIGN_MODE="ok")
        self.executable("br", "#!" + sys.executable + "\n" + BR)
        self.executable("bv", "#!" + BASH + "\nexit 0\n")

    def bead_invocations(self):
        return [json.loads(line) for line in self.br_calls.read_text().splitlines()] if self.br_calls.exists() else []

    def executable(self, name, text):
        path = self.bin / name
        path.write_text(text)
        path.chmod(0o755)

    def run_bash(self, body, data="", **env):
        return subprocess.run(
            [BASH, "-c", PRELUDE + body], input=data, text=True,
            capture_output=True, env={**self.env, **env}, cwd=self.root,
            timeout=10, check=False,
        )

    def invocations(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def start(self, **env):
        return self.run_bash('newproj_start_ntm "$PROJECT" acfs-my-app 1 1 1', **env)

    def test_exact_workspace_and_explicit_counts(self):
        result = self.start()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "acfs-my-app\n")
        self.assertEqual(self.invocations(), [{
            "cwd": str(self.project),
            "argv": ["--robot-spawn=acfs-my-app", "--spawn-dir=" + str(self.project),
                     "--spawn-safety", "--robot-format=json", "--spawn-cc=1", "--spawn-cod=1", "--spawn-agy=1"],
        }])
        self.assertFalse(self.events.exists())

    def test_failure_preserves_diagnostic_and_never_retries(self):
        result = self.start(FAKE_NTM_MODE="exit")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("existing session or launch failure", result.stderr)
        self.assertEqual(len(self.invocations()), 1)
        self.assertFalse(self.events.exists())

    def test_unconfirmed_or_partial_receipts_never_authorize_attach(self):
        for mode in ("invalid", "false", "string_success", "wrong_session", "wrong_dir", "partial", "error", "dry_run", "agent_error", "multiple"):
            with self.subTest(mode=mode):
                result = self.run_bash('open_in_ntm', "\n\n\n\nyes\n", FAKE_NTM_MODE=mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("ATTACHED", result.stdout)
                self.assertFalse(self.events.exists())
        self.assertTrue(all(call["argv"][0].startswith("--robot-spawn=") for call in self.invocations()))

    def test_invalid_mix_never_executes_ntm(self):
        for mix in ("0 0 0", "4 4 4", "5 0 0", "-1 1 0", "08 1 0", "x 1 0", "1 1.0 0"):
            with self.subTest(mix=mix):
                result = self.run_bash('newproj_start_ntm "$PROJECT" acfs-my-app ' + mix)
                self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.invocations(), [])

    def test_arithmetic_injection_is_data(self):
        result = self.run_bash('newproj_start_ntm "$PROJECT" acfs-my-app "$BAD_COUNT" 1 0', BAD_COUNT='1+$(touch injected)')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.invocations(), [])
        self.assertFalse((self.root / "injected").exists())

    def test_session_validation_precedes_execution(self):
        for name in ("", "-option", "bad.name", "bad:name", "a" * 65, "a\nline", "$(touch injected)"):
            with self.subTest(name=name):
                result = self.run_bash('newproj_start_ntm "$PROJECT" "$NAME" 1 1 0', NAME=name)
                self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.invocations(), [])

    def test_missing_provider_refuses_before_spawn(self):
        self.bin.joinpath("codex").rename(self.bin / "codex.disabled")
        result = self.start()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.invocations(), [])

    def test_each_infrastructure_dependency_is_required(self):
        for tool in ("ntm", "tmux", "jq"):
            with self.subTest(tool=tool):
                path = self.bin / tool
                saved = self.bin / (tool + ".saved")
                path.rename(saved)
                try:
                    result = self.start()
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("Missing " + tool, result.stderr)
                finally:
                    saved.rename(path)
        self.assertEqual(self.invocations(), [])

    def test_missing_or_unsafe_project_refuses(self):
        for project in ("/", "relative", str(self.root / "missing"), str(self.project) + "\n"):
            with self.subTest(project=project):
                result = self.start(PROJECT=project)
                self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.invocations(), [])

    def test_canonical_project_ignores_cdpath(self):
        alias = self.root / "alias"
        alias.symlink_to(self.project, target_is_directory=True)
        result = self.run_bash('newproj_ntm_project', PROJECT=str(alias), CDPATH=str(self.root))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, str(self.project) + "\n")

    def test_spawn_leaves_caller_directory_and_streams_intact(self):
        result = self.run_bash('newproj_start_ntm "$PROJECT" acfs-my-app 1 1 0; pwd; echo diagnostic >&2')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.endswith(str(self.root) + "\n"))
        self.assertIn("diagnostic", result.stderr)

    def test_default_mix_needs_explicit_yes(self):
        for answer in ("", "y", "no"):
            with self.subTest(answer=answer):
                result = self.run_bash('open_in_ntm', "\n\n\n\n" + answer + "\n")
                self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.invocations(), [])

    def test_eof_during_each_prompt_never_launches(self):
        for input_data in ("", "\n", "\n\n", "\n\n\n", "\n\n\n\n"):
            with self.subTest(input_data=input_data):
                result = self.run_bash('open_in_ntm', input_data)
                self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.invocations(), [])

    def test_confirmed_workspace_attaches_after_cleanup(self):
        result = self.run_bash('open_in_ntm', "\n\n\n\nyes\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ATTACHED", result.stdout)
        self.assertEqual(self.events.read_text(), "cleanup\nfinalize\n")
        self.assertEqual(self.invocations()[-1], {"argv": ["attach", "acfs-my-app"], "cwd": str(self.project)})

    def test_single_provider_defaults_to_two_agents(self):
        for agent in ("codex", "agy"):
            self.bin.joinpath(agent).rename(self.bin / (agent + ".disabled"))
        result = self.run_bash('open_in_ntm', "\n\nyes\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.invocations()[0]["argv"]
        self.assertIn("--spawn-cc=2", args)
        self.assertIn("--spawn-cod=0", args)
        self.assertIn("--spawn-agy=0", args)

    def test_operator_can_choose_counts_and_session(self):
        result = self.run_bash('open_in_ntm', "review-team\n2\n0\n1\nyes\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.invocations()[0]["argv"]
        self.assertIn("--robot-spawn=review-team", args)
        self.assertIn("--spawn-cc=2", args)
        self.assertIn("--spawn-cod=0", args)
        self.assertEqual(self.invocations()[-1]["argv"], ["attach", "review-team"])

    def test_no_agents_gives_actionable_failure(self):
        for agent in ("claude", "codex", "agy"):
            self.bin.joinpath(agent).rename(self.bin / (agent + ".disabled"))
        result = self.run_bash('open_in_ntm')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Install Claude Code", result.stderr)
        self.assertEqual(self.invocations(), [])

    def test_success_screen_eof_does_not_open_shell(self):
        result = self.run_bash('open_in_shell() { echo UNEXPECTED; }; handle_success_input')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("UNEXPECTED", result.stdout)
        self.assertEqual(self.invocations(), [])

    def test_menu_routes_ntm_and_preserves_cancel(self):
        result = self.run_bash('handle_success_input', "n\n\n\n\nno\nxq")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("cancelled", result.stdout)
        self.assertEqual(self.invocations(), [])

    def test_work_handoff_uses_canonical_ntm_assignment(self):
        self.enable_work()
        result = self.run_bash('open_in_ntm true', "\n\n\n\nyes\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--spawn-assign-work", self.invocations()[0]["argv"])
        self.assertIn("1 delivered task(s)", result.stderr)
        self.assertIn("Implement the feature", result.stdout)
        self.assertTrue(all(call["argv"] == ["ready", "--json"] for call in self.bead_invocations()))
        self.assertTrue(all(call["cwd"] == str(self.project) for call in self.bead_invocations()))

    def test_empty_queue_creates_first_task_only_after_consent(self):
        self.enable_work([])
        title = 'Implement "search"; $(do-not-execute)'
        result = self.run_bash('open_in_ntm true', "\n\n\n\n" + title + "\nyes\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        creates = [call for call in self.bead_invocations() if call["argv"][0] == "create"]
        self.assertEqual(creates, [{"cwd": str(self.project), "argv": ["create", "--title=" + title, "--type=task", "--priority=2", "--silent"]}])
        self.assertEqual(json.loads(self.queue.read_text())[0]["title"], title)
        self.assertIn("Created task bd-first", result.stdout)
        self.assertIn("--spawn-assign-work", self.invocations()[0]["argv"])

    def test_declined_first_task_is_not_created(self):
        self.enable_work([])
        result = self.run_bash('open_in_ntm true', "\n\n\n\nFirst feature\nno\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads(self.queue.read_text()), [])
        self.assertEqual(self.invocations(), [])
        self.assertTrue(all(call["argv"][0] == "ready" for call in self.bead_invocations()))

    def test_work_mode_eof_never_creates_or_launches(self):
        self.enable_work([])
        for data in ("\n\n\n\n", "\n\n\n\nFirst feature\n"):
            with self.subTest(data=data):
                result = self.run_bash('open_in_ntm true', data)
                self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads(self.queue.read_text()), [])
        self.assertEqual(self.invocations(), [])

    def test_invalid_goal_never_creates_a_task(self):
        self.enable_work([])
        for title in ("", "   ", "x" * 513, "escape\x1bsequence", "tab\tvalue"):
            with self.subTest(title=title):
                result = self.run_bash('open_in_ntm true', "\n\n\n\n" + title + "\nyes\n")
                self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads(self.queue.read_text()), [])
        self.assertEqual(self.invocations(), [])

    def test_invalid_mix_prevents_even_task_creation(self):
        self.enable_work([])
        result = self.run_bash('open_in_ntm true', "\n9\n1\n1\nFirst feature\nyes\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.bead_invocations(), [])
        self.assertEqual(self.invocations(), [])

    def test_missing_beads_project_does_not_assign_work(self):
        self.enable_work()
        self.project.joinpath(".beads").rename(self.project / ".beads.saved")
        result = self.run_bash('open_in_ntm true', "\n\n\n\nyes\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("br init", result.stderr)
        self.assertEqual(self.bead_invocations(), [])
        self.assertEqual(self.invocations(), [])

    def test_symlinked_beads_project_is_not_used(self):
        self.enable_work()
        original = self.project / ".beads"
        original.rename(self.project / ".beads.saved")
        original.symlink_to(self.project / ".beads.saved", target_is_directory=True)
        result = self.run_bash('open_in_ntm true', "\n\n\n\nyes\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.bead_invocations(), [])

    def test_missing_beads_tools_prevents_launch(self):
        self.enable_work()
        for tool in ("br", "bv"):
            path = self.bin / tool
            saved = self.bin / (tool + ".saved")
            path.rename(saved)
            try:
                result = self.run_bash('open_in_ntm true', "\n\n\n\nyes\n")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.invocations(), [])
            finally:
                saved.rename(path)

    def test_malformed_ready_queue_is_not_permission_to_create(self):
        self.enable_work()
        for ready in ('{}', 'null', 'bad JSON', '[{}]', '[]\n[]', '[{"id":"bad id","title":"x"}]'):
            with self.subTest(ready=ready):
                self.queue.write_text(ready)
                result = self.run_bash('open_in_ntm true', "\n\n\n\nFirst task\nyes\n")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.queue.read_text(), ready)
        self.assertEqual(self.invocations(), [])
        self.assertTrue(all(call["argv"][0] == "ready" for call in self.bead_invocations()))

    def test_task_read_failure_is_not_an_empty_queue(self):
        self.enable_work([])
        result = self.run_bash('open_in_ntm true', "\n\n\n\nFirst task\nyes\n", BR_MODE="read_error")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not read", result.stderr)
        self.assertEqual(self.invocations(), [])

    def test_creation_failure_never_launches(self):
        self.enable_work([])
        result = self.run_bash('open_in_ntm true', "\n\n\n\nFirst task\nyes\n", BR_MODE="create_error")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.invocations(), [])

    def test_ambiguous_creation_preserves_task_without_retry(self):
        self.enable_work([])
        result = self.run_bash('open_in_ntm true', "\n\n\n\nFirst task\nyes\n", BR_MODE="create_invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(json.loads(self.queue.read_text())), 1)
        self.assertEqual(self.invocations(), [])
        self.assertEqual(sum(call["argv"][0] == "create" for call in self.bead_invocations()), 1)

    def test_spawn_failure_preserves_created_task(self):
        self.enable_work([])
        result = self.run_bash('open_in_ntm true', "\n\n\n\nFirst task\nyes\n", FAKE_NTM_MODE="exit")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads(self.queue.read_text())[0]["id"], "bd-first")
        self.assertEqual(len(self.invocations()), 1)

    def test_partial_assignment_is_reported_without_redispatch(self):
        self.enable_work()
        result = self.run_bash('open_in_ntm true', "\n\n\n\nyes\n", ASSIGN_MODE="partial")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1 delivered task(s) from 2 assignment(s)", result.stderr)
        self.assertIn("before retrying", result.stderr)
        self.assertEqual(len(self.invocations()), 2)  # one spawn, one attach

    def test_no_assignment_is_not_reported_as_work_started(self):
        self.enable_work()
        for mode in ("none", "missing"):
            with self.subTest(mode=mode):
                result = self.run_bash('open_in_ntm true', "\n\n\n\nyes\n", ASSIGN_MODE=mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("0 delivered task(s)", result.stderr)
                self.assertIn("Check agent sign-in", result.stderr)

    def test_invalid_assignment_receipt_blocks_attach(self):
        self.enable_work()
        for mode in ("invalid", "null"):
            with self.subTest(mode=mode):
                result = self.run_bash('open_in_ntm true', "\n\n\n\nyes\n", ASSIGN_MODE=mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("ATTACHED", result.stdout)
        self.assertTrue(all(call["argv"][0].startswith("--robot-spawn=") for call in self.invocations()))

    def test_inherited_database_overrides_cannot_redirect_task_handoff(self):
        self.enable_work([])
        scope_log = self.root / "scope.jsonl"
        overrides = {key: "/another-project/" + key for key in ("BEADS_DIR", "BEADS_DB", "BD_DB", "BD_DATABASE", "BEADS_JSONL")}
        result = self.run_bash('open_in_ntm true', "\n\n\n\nFirst task\nyes\n", SCOPE_LOG=str(scope_log), **overrides)
        self.assertEqual(result.returncode, 0, result.stderr)
        scopes = [json.loads(line) for line in scope_log.read_text().splitlines()]
        self.assertEqual(len(scopes), 4)  # ready, create, ready, spawn
        for scope in scopes:
            self.assertEqual(scope.pop("BEADS_DIR"), str(self.project / ".beads"))
            self.assertTrue(all(value is None for value in scope.values()))

    def test_project_scope_preserves_callers_environment(self):
        self.enable_work()
        overrides = {key: "/another-project/" + key for key in ("BEADS_DIR", "BEADS_DB", "BD_DB", "BD_DATABASE", "BEADS_JSONL")}
        body = r'''
        newproj_ntm_ready_work "$PROJECT" >/dev/null
        for key in BEADS_DIR BEADS_DB BD_DB BD_DATABASE BEADS_JSONL; do
            [[ "${!key}" == "/another-project/$key" ]] || exit 92
        done
        pwd
        '''
        result = self.run_bash(body, **overrides)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, str(self.root) + "\n")

    def test_plain_workspace_does_not_read_or_mutate_beads(self):
        self.enable_work([])
        result = self.run_bash('open_in_ntm', "\n\n\n\nyes\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.bead_invocations(), [])
        self.assertNotIn("--spawn-assign-work", self.invocations()[0]["argv"])

    def test_work_mode_must_be_explicit_boolean(self):
        result = self.run_bash('newproj_start_ntm "$PROJECT" acfs-my-app 1 1 0 maybe')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.invocations(), [])

    def test_work_menu_routes_to_explicit_assignment(self):
        self.enable_work()
        result = self.run_bash('handle_success_input', "w\n\n\n\nyes\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--spawn-assign-work", self.invocations()[0]["argv"])

if __name__ == "__main__":
    unittest.main(verbosity=2)
