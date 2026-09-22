"""Exercise the real newproj entrypoint and generated projects without third-party dependencies."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/lib/newproj.sh"
BASH = shutil.which("bash")


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="acfs-bootstrap-test-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.target = self.base / "project with spaces"
        self.env = os.environ.copy()
        self.env.update({"ACFS_PROJECTS_DIR": str(self.base), "PYTHONDONTWRITEBYTECODE": "1"})

    def run_cli(self, *args, ok=True, env=None):
        result = subprocess.run([BASH, str(SCRIPT), *map(str, args)], env=env or self.env, text=True, capture_output=True, timeout=10)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def plan(self, *args):
        return json.loads(self.run_cli("--plan", "demo", self.target, *args).stdout)

    def save(self, plan):
        path = self.base / "reviewed.json"
        path.write_text(json.dumps(plan))
        return path

    def test_plan_is_deterministic_and_creates_nothing(self):
        first = self.plan("--preset", "first-project")
        self.assertEqual(first, self.plan("--preset", "first-project"))
        self.assertFalse(self.target.exists())
        self.assertEqual(list(self.base.iterdir()), [])
        self.assertTrue(all(value is False for value in first["effects"].values()))
        for entry in first["files"]:
            self.assertEqual(entry["sha256"], hashlib.sha256(entry["content"].encode()).hexdigest())

    def test_python_project_is_runnable_without_installing_dependencies(self):
        plan = self.plan("--preset", "first-project")
        result = json.loads(self.run_cli("--apply", self.save(plan), "--yes").stdout)
        self.assertEqual(result["status"], "created")
        check = subprocess.run(["sh", str(self.target / "scripts/check.sh")], text=True, capture_output=True)
        self.assertEqual(check.returncode, 0, check.stderr)
        self.assertIn("Ran 3 tests", check.stderr)
        branch = subprocess.check_output(["git", "-C", str(self.target), "symbolic-ref", "HEAD"], text=True)
        self.assertEqual(branch.strip(), "refs/heads/main")
        self.assertEqual(subprocess.check_output(["git", "-C", str(self.target), "diff", "--cached", "--name-only"]), b"")
        self.assertEqual(subprocess.check_output(["git", "-C", str(self.target), "remote"]), b"")
        state = self.target / plan["state_file"]
        self.assertEqual(state.stat().st_mode & 0o777, 0o600)
        self.assertEqual(json.loads(state.read_text())["status"], "complete")
        self.assertFalse((self.target / ".claude").exists())

    def test_only_explicitly_requested_files_are_created(self):
        plan = self.plan("--with", "readme")
        self.run_cli("--apply", self.save(plan), "--yes")
        files = sorted(str(p.relative_to(self.target)) for p in self.target.rglob("*") if p.is_file())
        self.assertEqual(files, [".acfs/bootstrap-state.json", "README.md"])
        self.assertEqual(plan["commands"], [])

    def test_typescript_starter_source_executes_and_uses_bun_tests(self):
        plan = self.plan("--preset", "first-project", "--stack", "typescript")
        self.run_cli("--apply", self.save(plan), "--yes")
        package = json.loads((self.target / "package.json").read_text())
        self.assertEqual(package["scripts"]["test"], "bun test")
        node = shutil.which("node")
        if not node:
            self.skipTest("Node required to execute generated TypeScript source; Bun is not emulated")
        program = 'import assert from "node:assert/strict"; import {stripTypeScriptTypes} from "node:module"; import {readFileSync} from "node:fs"; const source=stripTypeScriptTypes(readFileSync(process.argv[1],"utf8")); const {greet}=await import("data:text/javascript,"+encodeURIComponent(source)); assert.equal(greet("world"),"Hello, world!"); assert.equal(greet(" Ada "),"Hello, Ada!"); assert.throws(()=>greet(" "));'
        result = subprocess.run([node, "--input-type=module", "-e", program, str(self.target / "src/app.ts")], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.target / "package-lock.json").exists())

    def test_apply_requires_explicit_confirmation(self):
        path = self.save(self.plan("--with", "readme"))
        self.run_cli("--apply", path, ok=False)
        self.assertFalse(self.target.exists())

    def test_apply_does_not_accept_unreviewed_overrides(self):
        path = self.save(self.plan("--with", "readme"))
        self.run_cli("--apply", path, "--yes", "--stack", "typescript", ok=False)
        self.assertFalse(self.target.exists())

    def test_tampered_content_or_commands_never_execute(self):
        for field in ("content", "command", "path", "extra"):
            with self.subTest(field=field):
                plan = self.plan("--with", "readme")
                if field == "content":
                    plan["files"][0]["content"] = "unreviewed code"
                elif field == "command":
                    plan["commands"] = [{"id": "git-init", "argv": ["sh", "-c", "touch marker"]}]
                elif field == "path":
                    plan["files"][0]["path"] = "../outside"
                else:
                    plan["unreviewed"] = True
                # Even recomputing a digest must not turn a plan into arbitrary code execution.
                unsigned = {k: v for k, v in plan.items() if k != "plan_id"}
                plan["plan_id"] = hashlib.sha256(json.dumps(unsigned, sort_keys=True, ensure_ascii=True, separators=(",", ":")).encode()).hexdigest()
                self.run_cli("--apply", self.save(plan), "--yes", ok=False)
                self.assertFalse(self.target.exists())

    def test_existing_contents_are_never_overwritten(self):
        plan = self.plan("--with", "readme")
        self.target.mkdir()
        valuable = self.target / "README.md"
        valuable.write_text("user work")
        self.run_cli("--apply", self.save(plan), "--yes", ok=False)
        self.assertEqual(valuable.read_text(), "user work")
        self.assertFalse((self.target / ".acfs").exists())

    def test_empty_existing_directory_is_bound_to_its_identity(self):
        self.target.mkdir()
        plan = self.plan("--with", "readme")
        self.target.rename(self.base / "moved")
        self.target.mkdir()
        self.run_cli("--apply", self.save(plan), "--yes", ok=False)
        self.assertEqual(list(self.target.iterdir()), [])

    def test_existing_empty_directory_can_be_populated(self):
        self.target.mkdir()
        path = self.save(self.plan("--with", "readme"))
        self.run_cli("--apply", path, "--yes")
        self.assertTrue((self.target / "README.md").exists())

    def test_target_symlink_is_rejected(self):
        outside = self.base / "outside"
        outside.mkdir()
        self.target.symlink_to(outside, target_is_directory=True)
        self.run_cli("--plan", "demo", self.target, "--with", "readme", ok=False)
        self.assertEqual(list(outside.iterdir()), [])

    def test_git_environment_cannot_redirect_initialization(self):
        path = self.save(self.plan("--with", "git,readme"))
        env = self.env.copy()
        env.update({"GIT_DIR": str(self.base / "outside.git"), "GIT_WORK_TREE": str(self.base), "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "init.defaultBranch", "GIT_CONFIG_VALUE_0": "wrong"})
        self.run_cli("--apply", path, "--yes", env=env)
        self.assertFalse((self.base / "outside.git").exists())
        self.assertTrue((self.target / ".git").is_dir())

    def test_missing_selected_tool_fails_before_creating_project(self):
        path = self.save(self.plan("--with", "git,readme"))
        bin_dir = self.base / "bin"
        bin_dir.mkdir()
        (bin_dir / "python3").symlink_to(shutil.which("python3"))
        env = {**self.env, "PATH": str(bin_dir)}
        result = self.run_cli("--apply", path, "--yes", ok=False, env=env)
        self.assertIn("required executable is missing: git", result.stderr)
        self.assertFalse(self.target.exists())

    def test_explicit_selection_and_feature_dependencies_are_required(self):
        for options in ([], ["--with", "unknown"], ["--with", "readme,readme"], ["--with", "ci"]):
            self.run_cli("--plan", "demo", self.target, *options, ok=False)
            self.assertFalse(self.target.exists())

    def test_duplicate_json_keys_and_non_regular_plans_are_rejected(self):
        path = self.base / "bad.json"
        path.write_text('{"project":{},"project":{}}')
        self.run_cli("--apply", path, "--yes", ok=False)
        fifo = self.base / "pipe"
        os.mkfifo(fifo)
        self.run_cli("--apply", fifo, "--yes", ok=False)
        self.assertFalse(self.target.exists())

    def test_invalid_project_names_are_rejected_without_writes(self):
        for name in ("../escape", "-option", "has space", "$(touch marker)", "x" * 65):
            self.run_cli("--plan", name, self.target, "--with", "readme", ok=False)
        self.assertEqual(list(self.base.iterdir()), [])

    def br_fixture(self, failure=""):
        bin_dir = self.base / "tools"
        bin_dir.mkdir()
        script = bin_dir / "br"
        script.write_text("#!" + shutil.which("python3") + "\n" + '''import json, os, pathlib, sys
log = pathlib.Path(os.environ["BOOTSTRAP_TEST_LOG"])
with log.open("a") as stream:
    stream.write(json.dumps(sys.argv[1:]) + "\\n")
beads = pathlib.Path(".beads")
if sys.argv[1:] == ["init"]:
    failure = os.environ.get("BOOTSTRAP_TEST_FAILURE", "")
    if failure == "before":
        sys.exit(19)
    beads.mkdir(exist_ok=True)
    (beads / "beads.db").write_text("fixture, not a real Beads database")
    if failure == "after":
        sys.exit(20)
elif sys.argv[1:] == ["ready", "--json"]:
    if not (beads / "beads.db").is_file():
        sys.exit(21)
    print("[]")
else:
    sys.exit(22)
''')
        script.chmod(0o755)
        self.env.update({"PATH": str(bin_dir) + os.pathsep + self.env["PATH"], "BOOTSTRAP_TEST_LOG": str(self.base / "tool.log"), "BOOTSTRAP_TEST_FAILURE": failure})
        return self.base / "tool.log"

    def test_beads_is_opt_in_and_all_tool_effects_are_reviewable(self):
        log = self.br_fixture()
        plan = self.plan("--preset", "first-project", "--beads")
        self.assertFalse(log.exists(), "planning must not execute br")
        self.assertEqual([c["argv"] for c in plan["commands"]], [["git", "init", "--template=", "--initial-branch=main", "."], ["br", "init"]])
        self.assertEqual(plan["commands"][1]["writes"], [".beads/"])
        self.run_cli("--apply", self.save(plan), "--yes")
        self.assertEqual([json.loads(s) for s in log.read_text().splitlines()], [["init"], ["ready", "--json"]])
        self.assertIn("br ready --json", (self.target / "AGENTS.md").read_text())
        self.assertIn("until I approve", (self.target / "FIRST_AGENT_PROMPT.md").read_text())

    def test_resume_completes_failed_tool_without_reinitializing_git_or_overwriting_files(self):
        log = self.br_fixture("before")
        plan = self.plan("--preset", "first-project", "--beads")
        path = self.save(plan)
        failure = self.run_cli("--apply", path, "--yes", ok=False)
        self.assertIn("nothing was removed", failure.stderr)
        state = json.loads((self.target / plan["state_file"]).read_text())
        self.assertEqual(state["completed_commands"], ["git-init"])
        self.assertEqual(state["status"], "failed")
        files = {entry["path"]: (self.target / entry["path"]).stat().st_ino for entry in plan["files"]}
        git_head = (self.target / ".git/HEAD").stat().st_ino
        self.env["BOOTSTRAP_TEST_FAILURE"] = ""
        result = json.loads(self.run_cli("--apply", path, "--yes", "--resume").stdout)
        self.assertEqual(result["status"], "resumed")
        self.assertEqual(result["completed_commands"], ["git-init", "beads-init"])
        self.assertEqual((self.target / ".git/HEAD").stat().st_ino, git_head)
        self.assertEqual(files, {p: (self.target / p).stat().st_ino for p in files})
        self.assertEqual(len(log.read_text().splitlines()), 3)

    def test_resume_recovers_tool_completion_before_checkpoint(self):
        log = self.br_fixture("after")
        path = self.save(self.plan("--with", "git,beads,readme"))
        self.run_cli("--apply", path, "--yes", ok=False)
        self.env["BOOTSTRAP_TEST_FAILURE"] = ""
        self.run_cli("--apply", path, "--yes", "--resume")
        calls = [json.loads(s) for s in log.read_text().splitlines()]
        self.assertEqual(calls.count(["init"]), 1, "do not reinitialize an already-created database")
        self.assertIn(["ready", "--json"], calls)

    def test_resume_checks_all_existing_files_before_creating_missing_ones(self):
        self.br_fixture("before")
        plan = self.plan("--preset", "first-project", "--beads")
        path = self.save(plan)
        self.run_cli("--apply", path, "--yes", ok=False)
        missing = self.target / "README.md"
        missing.rename(self.base / "saved-readme")
        changed = self.target / "src/app.py"
        changed.write_text("user work")
        self.env["BOOTSTRAP_TEST_FAILURE"] = ""
        self.run_cli("--apply", path, "--yes", "--resume", ok=False)
        self.assertFalse(missing.exists())
        self.assertEqual(changed.read_text(), "user work")

    def test_resume_can_finish_missing_files_with_matching_checkpoint(self):
        self.br_fixture("before")
        path = self.save(self.plan("--preset", "first-project", "--beads"))
        self.run_cli("--apply", path, "--yes", ok=False)
        missing = self.target / "src/app.py"
        expected = missing.read_bytes()
        missing.rename(self.base / "saved-app")
        self.env["BOOTSTRAP_TEST_FAILURE"] = ""
        self.run_cli("--apply", path, "--yes", "--resume")
        self.assertEqual(missing.read_bytes(), expected)

    def test_completed_resume_does_not_repeat_tool_commands(self):
        log = self.br_fixture()
        path = self.save(self.plan("--with", "git,beads,readme"))
        self.run_cli("--apply", path, "--yes")
        before = log.read_bytes()
        self.run_cli("--apply", path, "--yes", "--resume")
        self.assertEqual(log.read_bytes(), before)

    def test_resume_rejects_foreign_or_forged_checkpoint(self):
        path = self.save(self.plan("--with", "readme"))
        self.run_cli("--apply", path, "--yes")
        checkpoint = self.target / ".acfs/bootstrap-state.json"
        original = json.loads(checkpoint.read_text())
        for change in ({"plan_id": "wrong"}, {"completed_commands": ["unreviewed-command"]}, {"directory_identity": {"device": 0, "inode": 0}}):
            checkpoint.write_text(json.dumps({**original, **change}))
            self.run_cli("--apply", path, "--yes", "--resume", ok=False)
        self.assertEqual((self.target / "README.md").read_text().splitlines()[0], "# demo")

    def test_resume_rejects_symlinked_sources_and_tool_metadata(self):
        self.br_fixture("before")
        path = self.save(self.plan("--preset", "first-project", "--beads"))
        self.run_cli("--apply", path, "--yes", ok=False)
        source = self.target / "src"
        moved = self.base / "moved-src"
        source.rename(moved)
        source.symlink_to(moved, target_is_directory=True)
        self.run_cli("--apply", path, "--yes", "--resume", ok=False)
        source.unlink()
        moved.rename(source)
        config = self.target / ".git/config"
        config.rename(self.base / "saved-config")
        config.symlink_to(self.base / "saved-config")
        self.run_cli("--apply", path, "--yes", "--resume", ok=False)

    def test_beads_requires_an_explicit_git_selection(self):
        self.run_cli("--plan", "demo", self.target, "--with", "readme", "--beads", ok=False)
        self.assertFalse(self.target.exists())

    def test_resume_without_checkpoint_does_not_claim_an_existing_project(self):
        self.target.mkdir()
        path = self.save(self.plan("--with", "readme"))
        (self.target / "important.txt").write_text("existing work")
        self.run_cli("--apply", path, "--yes", "--resume", ok=False)
        self.assertEqual(sorted(p.name for p in self.target.iterdir()), ["important.txt"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
