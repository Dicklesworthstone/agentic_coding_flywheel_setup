"""End-to-end publication tests with real Git objects and isolated external services.

The command entrypoint and its generated project are real. GitHub and repo_updater
are strict executable fixtures, while Git's transport alone is redirected to a
temporary bare repository. No test can publish to a real account or change the
developer's updater configuration.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import unittest

import test_project_bootstrap as bootstrap
import test_project_bootstrap_guided as guided
import test_project_bootstrap_mail as mail


REPOSITORY = "acfs-test/demo"
REMOTE_URL = "https://github.com/" + REPOSITORY + ".git"
REPO_URL = "https://github.com/" + REPOSITORY
REAL_GIT = shutil.which("git")


GITHUB_FIXTURE = r'''
import json
import os
from pathlib import Path
import subprocess
import sys

arguments = sys.argv[1:]
with open(os.environ["ACFS_TEST_TOOL_LOG"], "a") as stream:
    stream.write(json.dumps({"tool": "gh", "argv": arguments, "cwd": os.getcwd()}) + "\n")
failure = os.environ.get("ACFS_TEST_FAIL")
server_file = Path(os.environ["ACFS_TEST_SERVER"])
server = json.loads(server_file.read_text())
repository = os.environ["ACFS_TEST_REPOSITORY"]
owner, name = repository.split("/")

def error(code):
    print("HTTP/2.0 " + str(code) + " Error\nContent-Type: application/json\n")
    print(json.dumps({"message": "SECRET_FROM_GITHUB_ERROR", "status": str(code)}))
    print("gh: SECRET_FROM_GITHUB_ERROR (HTTP " + str(code) + ")", file=sys.stderr)
    sys.exit(1)

if arguments == ["auth", "status", "--active", "--hostname", "github.com"]:
    if failure == "auth":
        print("SECRET_FROM_AUTH_FAILURE", file=sys.stderr)
        sys.exit(4)
    sys.exit(0)
if arguments[:3] != ["api", "--hostname", "github.com"]:
    print("Unexpected GitHub command", file=sys.stderr)
    sys.exit(99)
arguments = arguments[3:]
if arguments == ["user"]:
    if failure == "user":
        error(401)
    print(json.dumps({"login": "acfs-test", "id": 4242, "type": "User"}))
elif arguments == ["users/" + owner] and owner != "acfs-test":
    print(json.dumps({"login": owner, "id": 5454, "type": os.environ.get("ACFS_TEST_OWNER_TYPE", "Organization")}))
elif arguments == ["--include", "repos/" + repository]:
    if failure in ("lookup-403", "lookup-429", "lookup-500"):
        error(int(failure.split("-")[1]))
    entry = server["repositories"].get(repository)
    if entry is None:
        error(404)
    print("HTTP/2.0 200 OK\nContent-Type: application/json\n")
    print(json.dumps(entry))
elif arguments[:4] == ["--include", "user/repos" if owner == "acfs-test" else "orgs/" + owner + "/repos", "--method", "POST"]:
    fields = arguments[4:]
    expected_private = ["--raw-field", "name=" + name, "--field", "private=true", "--field", "auto_init=false"]
    expected_public = ["--raw-field", "name=" + name, "--field", "private=false", "--field", "auto_init=false"]
    if fields not in (expected_private, expected_public):
        print("Unexpected creation fields: " + repr(fields), file=sys.stderr)
        sys.exit(98)
    if failure == "create-before":
        error(503)
    if failure == "create-rejected":
        error(422)
    if repository in server["repositories"]:
        error(422)
    private = fields == expected_private
    if failure == "create-wrong-visibility":
        private = not private
    entry = {"id": 61001, "full_name": repository, "private": private,
             "visibility": "private" if private else "public",
             "html_url": "https://github.com/" + repository,
             "clone_url": "https://github.com/" + repository + ".git",
             "default_branch": "main", "permissions": {"push": True}}
    server["repositories"][repository] = entry
    server_file.write_text(json.dumps(server))
    subprocess.run([os.environ["ACFS_TEST_REAL_GIT"], "init", "--bare", "--template=",
                    "--initial-branch=main", os.environ["ACFS_TEST_BARE_REPO"]],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if failure == "create-after":
        # An accepted request whose response was lost must never trigger a second creation.
        sys.exit(23)
    print("HTTP/2.0 201 Created\nContent-Type: application/json\n")
    print(json.dumps(entry))
else:
    print("Unexpected GitHub API request: " + repr(arguments), file=sys.stderr)
    sys.exit(97)
'''


RU_FIXTURE = r'''
import json
import os
from pathlib import Path
import sys

arguments = sys.argv[1:]
with open(os.environ["ACFS_TEST_TOOL_LOG"], "a") as stream:
    stream.write(json.dumps({"tool": "ru", "argv": arguments, "cwd": os.getcwd()}) + "\n")
repository = os.environ["ACFS_TEST_REPOSITORY"]
config = Path(os.environ["RU_CONFIG_DIR"])
failure = os.environ.get("ACFS_TEST_FAIL")
if arguments in (["add", "--non-interactive", "--private", repository],
                 ["add", "--non-interactive", repository]):
    if failure == "ru-before":
        print("SECRET_FROM_RU_FAILURE", file=sys.stderr)
        sys.exit(24)
    if failure == "ru-unconfirmed":
        # Upstream ru may report success after a failed append; verification
        # must read the selected list instead of trusting this zero exit.
        sys.exit(0)
    private = "--private" in arguments
    (config / "repos.d").mkdir(parents=True, exist_ok=True)
    Path(os.environ["RU_STATE_DIR"]).mkdir(parents=True, exist_ok=True)
    listing = config / "repos.d" / ("private.txt" if private else "public.txt")
    listed = []
    for path in (config / "repos.d/private.txt", config / "repos.d/public.txt"):
        if path.exists():
            listed.extend(path.read_text().splitlines())
    if repository not in listed:
        with listing.open("a") as stream:
            stream.write(repository + "\n")
    if failure == "ru-after":
        sys.exit(25)
elif arguments in (["list", "--private", "--json"], ["list", "--public", "--json"]):
    listing = config / "repos.d" / ("private.txt" if "--private" in arguments else "public.txt")
    lines = listing.read_text().splitlines() if listing.exists() else []
    print(json.dumps({"version": "test-fixture", "output_format": "json", "command": "list",
                      "data": {"total": len(lines), "repos": [{"repo": name, "url": "https://github.com/" + name,
                                                              "path": "/configured/projects/" + name.split("/")[-1]}
                                                             for name in lines]}, "_meta": {"exit_code": 0}}))
else:
    print("Unexpected updater command: " + repr(arguments), file=sys.stderr)
    sys.exit(99)
'''


GIT_FIXTURE = r'''
import json
import os
from pathlib import Path
import subprocess
import sys

arguments = sys.argv[1:]
with open(os.environ["ACFS_TEST_TOOL_LOG"], "a") as stream:
    stream.write(json.dumps({"tool": "git", "argv": arguments, "cwd": os.getcwd()}) + "\n")

index = 0
while index < len(arguments):
    if arguments[index] in ("-c", "-C", "--git-dir", "--work-tree"):
        index += 2
    elif arguments[index].startswith("-"):
        index += 1
    else:
        break
if index == len(arguments):
    sys.exit(97)
command = arguments[index]
local_commands = {
    "init", "config", "add", "commit", "commit-tree", "rev-parse", "write-tree",
    "read-tree", "ls-files", "ls-tree", "diff", "diff-index", "show-ref", "symbolic-ref",
    "cat-file", "log", "show", "status", "remote", "hash-object", "update-index",
    "update-ref", "check-ignore", "check-ref-format", "for-each-ref", "mktree", "rev-list",
}
if command not in local_commands | {"push", "ls-remote"}:
    print("Unexpected Git command in isolated fixture: " + command, file=sys.stderr)
    sys.exit(98)

if command == "commit-tree" and os.environ.get("ACFS_TEST_FAIL") == "commit-before":
    sys.exit(26)

if command in ("push", "ls-remote"):
    rewritten = False
    for position in range(index + 1, len(arguments)):
        if arguments[position] in ("origin", "https://github.com/" + os.environ["ACFS_TEST_REPOSITORY"] + ".git"):
            arguments[position] = os.environ["ACFS_TEST_BARE_REPO"]
            rewritten = True
    if not rewritten:
        print("Refusing an unrecognized transport destination", file=sys.stderr)
        sys.exit(99)
    if command == "push" and os.environ.get("ACFS_TEST_FAIL") == "push-before":
        print("SECRET_FROM_PUSH_FAILURE", file=sys.stderr)
        sys.exit(19)

env = os.environ.copy()
env["GIT_ALLOW_PROTOCOL"] = "file"
result = subprocess.run([os.environ["ACFS_TEST_REAL_GIT"], *arguments], env=env)
if result.returncode == 0 and command == "push" and os.environ.get("ACFS_TEST_FAIL") == "push-after":
    # The server accepted the commit, but the caller did not receive success.
    sys.exit(20)
sys.exit(result.returncode)
'''


class GitHubBootstrapTests(unittest.TestCase):
    run_cli = bootstrap.BootstrapTests.run_cli
    plan = bootstrap.BootstrapTests.plan
    save = bootstrap.BootstrapTests.save

    def setUp(self):
        bootstrap.BootstrapTests.setUp(self)
        self.bin = self.base / "tools"
        self.bin.mkdir()
        self.home = self.base / "home"
        self.home.mkdir()
        self.config = self.base / "config"
        self.remote = self.base / "remote.git"
        self.log = self.base / "commands.jsonl"
        self.server = self.base / "github.json"
        self.server.write_text(json.dumps({"repositories": {}}))
        self.env.update({
            "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.config),
            "RU_CONFIG_DIR": str(self.config / "repo_updater"),
            "RU_STATE_DIR": str(self.base / "updater-state"),
            "ACFS_TEST_TOOL_LOG": str(self.log),
            "ACFS_TEST_SERVER": str(self.server),
            "ACFS_TEST_REPOSITORY": REPOSITORY,
            "ACFS_TEST_BARE_REPO": str(self.remote),
            "ACFS_TEST_REAL_GIT": REAL_GIT,
            "ACFS_TEST_FAIL": "",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_TERMINAL_PROMPT": "0",
            "PATH": str(self.bin),
        })
        (self.bin / "python3").symlink_to(sys.executable)
        (self.bin / "bash").symlink_to(bootstrap.BASH)
        self.executable("git", GIT_FIXTURE)
        self.executable("gh", GITHUB_FIXTURE)
        self.executable("ru", RU_FIXTURE)

    def executable(self, name, source):
        path = self.bin / name
        path.write_text("#!" + sys.executable + "\n" + source)
        path.chmod(0o755)

    def calls(self, tool=None, command=None):
        rows = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return [row for row in rows if (tool is None or row["tool"] == tool)
                and (command is None or command in row["argv"])]

    def git(self, *arguments, cwd=None, ok=True):
        # Fixture inspection uses the real executable, never the transport shim.
        result = subprocess.run([REAL_GIT, *map(str, arguments)], cwd=cwd, env=self.env,
                                capture_output=True, text=True, timeout=10)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def remote_head(self):
        return self.git("--git-dir", self.remote, "rev-parse", "refs/heads/main").stdout.strip()

    def publication_plan(self, *arguments, visibility="private", ru=False):
        return self.plan("--preset", "first-project", "--github", visibility,
                         "--github-repo", REPOSITORY, *(["--ru"] if ru else []), *arguments)

    def checkpoint(self):
        return json.loads((self.target / ".acfs/bootstrap-state.json").read_text())

    def repositories(self):
        return json.loads(self.server.read_text())["repositories"]

    def set_repository(self, **fields):
        repositories = self.repositories()
        entry = repositories.setdefault(REPOSITORY, {"id": 61001, "full_name": REPOSITORY,
                                                       "private": True, "visibility": "private",
                                                       "permissions": {"push": True}})
        entry.update(fields)
        self.server.write_text(json.dumps({"repositories": repositories}))

    def creations(self):
        return self.calls("gh", "POST")

    def registrations(self):
        return self.calls("ru", "add")

    def listing(self, visibility="private"):
        return self.config / "repo_updater/repos.d" / (visibility + ".txt")

    def guide_to_review(self, *, visibility="public", ru="yes"):
        terminal = guided.Terminal(self.env)
        self.addCleanup(terminal.close)
        guided.GuidedBootstrapTests.select(self, terminal, github=visibility, ru=ru)
        terminal.expect("Action: details / create / save / cancel [cancel]: ")
        return terminal

    def test_local_creation_ignores_ambient_remote_defaults(self):
        self.env.update({"ACFS_NEWPROJ_GITHUB": "public", "ACFS_NEWPROJ_RU": "1",
                         "GH_HOST": "unreviewed.example", "GH_REPO": "unreviewed/other"})
        plan = self.plan("--preset", "first-project")
        self.assertTrue(all(effect is False for effect in plan["effects"].values()))
        self.run_cli("--apply", self.save(plan), "--yes")
        self.assertEqual(self.calls("gh"), [])
        self.assertEqual(self.calls("ru"), [])
        self.assertEqual(self.calls("git", "push"), [])
        self.assertEqual(self.git("remote", cwd=self.target).stdout, "")
        self.assertNotEqual(self.git("rev-parse", "--verify", "HEAD", cwd=self.target, ok=False).returncode, 0)
        self.assertFalse(self.config.exists())

    def test_publication_plan_is_offline_deterministic_and_discloses_effects(self):
        self.env["GH_TOKEN"] = "secret-never-in-plan"
        first = self.publication_plan(ru=True)
        self.assertEqual(first, self.publication_plan(ru=True))
        self.assertEqual(self.calls(), [])
        self.assertFalse(self.target.exists())
        self.assertFalse(self.config.exists())
        text = json.dumps(first)
        self.assertIn(REPOSITORY, text)
        self.assertIn(REPO_URL, text)
        self.assertIn("private", text)
        self.assertIn(str(self.config), text, "review must name the updater configuration destination")
        self.assertNotIn("secret-never-in-plan", text)
        for effect in ("network", "commit", "push", "global_settings"):
            self.assertTrue(first["effects"][effect], effect)
        self.assertFalse(first["effects"]["model_calls"])

    def test_public_visibility_requires_an_explicit_plan_selection(self):
        private = self.publication_plan()
        public = self.publication_plan(visibility="public")
        self.assertNotEqual(private["plan_id"], public["plan_id"])
        self.assertEqual(private["github"]["visibility"], "private")
        self.assertEqual(public["github"]["visibility"], "public")
        self.assertEqual(next(c for c in private["commands"] if c["id"] == "github-create")["visibility"], "private")
        self.assertEqual(next(c for c in public["commands"] if c["id"] == "github-create")["visibility"], "public")
        self.assertFalse(private["effects"]["global_settings"])
        self.assertEqual(self.calls(), [])

    def test_incomplete_or_invalid_remote_choices_are_rejected(self):
        invalid = (
            ("--github",),
            ("--github", "private"),
            ("--github", "internal", "--github-repo", REPOSITORY),
            ("--github-repo", REPOSITORY),
            ("--ru",),
            ("--github", "private", "--github-repo", "acfs-test/demo/extra"),
            ("--github", "private", "--github-repo", "https://github.com/" + REPOSITORY),
            ("--github", "private", "--github-repo", "acfs-test/$(touch marker)"),
            ("--github", "private", "--github-repo", "acfs-test/.."),
        )
        for options in invalid:
            with self.subTest(options=options):
                self.run_cli("--plan", "demo", self.target, "--preset", "first-project", *options, ok=False)
        self.assertFalse(self.target.exists())
        self.assertEqual(self.calls(), [])

    def test_publication_requires_explicit_git_feature(self):
        self.run_cli("--plan", "demo", self.target, "--with", "readme",
                     "--github", "private", "--github-repo", REPOSITORY, ok=False)
        self.assertFalse(self.target.exists())
        self.assertEqual(self.calls(), [])

    def test_apply_without_consent_or_with_remote_overrides_does_nothing(self):
        path = self.save(self.publication_plan())
        self.run_cli("--apply", path, ok=False)
        for options in (("--github", "public"), ("--github-repo", "another/repo"), ("--ru",)):
            with self.subTest(options=options):
                self.run_cli("--apply", path, "--yes", *options, ok=False)
        self.assertFalse(self.target.exists())
        self.assertEqual(self.calls(), [])

    def test_legacy_cli_does_not_bypass_remote_review(self):
        env = {**self.env, "PATH": str(self.bin) + os.pathsep + os.defpath}
        result = self.run_cli("demo", self.target, "--github=private", "--ru", ok=False, env=env)
        self.assertIn("Unknown option: --github=private", result.stderr)
        self.assertFalse(self.target.exists())
        self.assertEqual(self.calls(), [])

    def test_authentication_and_lookup_errors_stop_before_any_project_write(self):
        path = self.save(self.publication_plan(ru=True))
        for failure in ("auth", "user", "lookup-403", "lookup-429", "lookup-500"):
            with self.subTest(failure=failure):
                self.env["ACFS_TEST_FAIL"] = failure
                result = self.run_cli("--apply", path, "--yes", ok=False)
                self.assertFalse(self.target.exists())
                self.assertEqual(self.creations(), [])
                self.assertEqual(self.calls("git", "push"), [])
                self.assertEqual(self.registrations(), [])
                self.assertNotIn("SECRET_FROM_", result.stdout + result.stderr)

    def test_name_conflict_is_not_adopted_or_pushed(self):
        self.set_repository(id=4444)
        path = self.save(self.publication_plan())
        result = self.run_cli("--apply", path, "--yes", ok=False)
        self.assertIn("exist", result.stderr.lower())
        self.assertFalse(self.target.exists())
        self.assertEqual(self.repositories()[REPOSITORY]["id"], 4444)
        self.assertEqual(self.creations(), [])
        self.assertEqual(self.calls("git", "push"), [])

    def test_preflight_also_protects_an_existing_empty_directory(self):
        self.target.mkdir()
        inode = self.target.stat().st_ino
        path = self.save(self.publication_plan(ru=True))
        self.env["ACFS_TEST_FAIL"] = "auth"
        self.run_cli("--apply", path, "--yes", ok=False)
        self.assertEqual(self.target.stat().st_ino, inode)
        self.assertEqual(list(self.target.iterdir()), [])
        self.assertEqual(self.creations(), [])
        self.assertFalse(self.config.exists())

    def test_missing_selected_executable_blocks_before_local_or_remote_creation(self):
        path = self.save(self.publication_plan(ru=True))
        for tool in ("gh", "ru", "git"):
            with self.subTest(tool=tool):
                executable = self.bin / tool
                saved = self.bin / (tool + ".unavailable")
                executable.rename(saved)
                try:
                    result = self.run_cli("--apply", path, "--yes", ok=False)
                finally:
                    saved.rename(executable)
                self.assertIn(tool, result.stderr)
                self.assertFalse(self.target.exists())
                self.assertEqual(self.creations(), [])
                self.assertEqual(self.registrations(), [])

    def test_private_publication_pushes_real_reviewed_tree_and_registers_once(self):
        plan = self.publication_plan(ru=True)
        path = self.save(plan)
        result = self.run_cli("--apply", path, "--yes")
        self.assertEqual(json.loads(result.stdout)["status"], "created")
        self.assertEqual(self.repositories()[REPOSITORY]["private"], True)
        self.assertEqual(len(self.creations()), 1)
        self.assertEqual(len(self.calls("git", "push")), 1)
        self.assertEqual(len(self.registrations()), 1)
        self.assertEqual(self.git("remote", "get-url", "origin", cwd=self.target).stdout.strip(), REMOTE_URL)
        self.assertEqual(self.git("rev-parse", "HEAD", cwd=self.target).stdout.strip(), self.remote_head())
        paths = self.git("--git-dir", self.remote, "ls-tree", "--name-only", "-r", "refs/heads/main").stdout.splitlines()
        self.assertEqual(set(paths), {entry["path"] for entry in plan["files"]})
        self.assertNotIn(".acfs/bootstrap-state.json", paths)
        for entry in plan["files"]:
            committed = self.git("--git-dir", self.remote, "show", "refs/heads/main:" + entry["path"]).stdout
            self.assertEqual(committed, entry["content"])
        self.assertEqual(self.listing().read_text().splitlines(), [REPOSITORY])
        self.assertFalse(self.listing("public").exists())
        self.assertEqual(self.checkpoint()["status"], "complete")
        self.assertIn("without explicit permission", (self.target / "AGENTS.md").read_text())
        head = self.remote_head()
        calls = self.calls()
        self.env["ACFS_TEST_FAIL"] = "auth"
        self.run_cli("--apply", path, "--yes", "--resume")
        self.assertEqual(self.remote_head(), head)
        self.assertEqual(self.calls("gh"), [c for c in calls if c["tool"] == "gh"])
        self.assertEqual(self.calls("ru"), [c for c in calls if c["tool"] == "ru"])
        self.assertEqual(len(self.calls("git", "push")), 1)

    def test_agent_mail_clients_exist_locally_but_are_excluded_from_actual_publication(self):
        self.env["ACFS_MAIL_TEST_TOKEN"] = "private-runtime-token-never-publish"
        with mail.MailBootstrapTests.service(self) as (url, requests):
            plan = self.publication_plan("--agent-mail", url,
                                         "--agent-mail-token-env", "ACFS_MAIL_TEST_TOKEN",
                                         "--agent-mail-clients", "claude,codex,gemini")
            self.run_cli("--apply", self.save(plan), "--yes")
            self.assertEqual(len(requests), 1)
            self.assertEqual(requests[0]["authorization"], "Bearer private-runtime-token-never-publish")
            private_paths = {".mcp.json", ".codex/config.toml", ".gemini/settings.json"}
            self.assertTrue(private_paths.issubset(set(plan["publication"]["excluded_files"])))
            for path in private_paths:
                self.assertTrue((self.target / path).is_file(), path)
                self.assertIn(url, (self.target / path).read_text())
            published = self.git("--git-dir", self.remote, "ls-tree", "--name-only", "-r", "refs/heads/main").stdout.splitlines()
            self.assertEqual(set(published), set(plan["publication"]["files"]))
            self.assertTrue(private_paths.isdisjoint(published))
            self.assertNotIn(".acfs/bootstrap-state.json", published)
            self.assertIn("AGENT_MAIL.md", published)
            for path in published:
                content = self.git("--git-dir", self.remote, "show", "refs/heads/main:" + path).stdout
                self.assertNotIn("private-runtime-token-never-publish", content)
                self.assertNotIn(url, content)

    def test_explicit_public_publication_uses_public_updater_list(self):
        path = self.save(self.publication_plan(visibility="public", ru=True))
        self.run_cli("--apply", path, "--yes")
        self.assertEqual(self.repositories()[REPOSITORY]["private"], False)
        self.assertIn("private=false", self.creations()[0]["argv"])
        self.assertNotIn("--private", self.registrations()[0]["argv"])
        self.assertEqual(self.listing("public").read_text().splitlines(), [REPOSITORY])
        self.assertFalse(self.listing().exists())

    def test_publication_does_not_register_without_ru_selection(self):
        path = self.save(self.publication_plan())
        self.run_cli("--apply", path, "--yes")
        self.assertEqual(len(self.creations()), 1)
        self.assertEqual(self.calls("ru"), [])
        self.assertFalse(self.config.exists())

    def test_failed_push_reports_created_repository_and_resumes_without_recreating(self):
        path = self.save(self.publication_plan(ru=True))
        self.env["ACFS_TEST_FAIL"] = "push-before"
        result = self.run_cli("--apply", path, "--yes", ok=False)
        self.assertIn(REPO_URL, result.stderr)
        self.assertIn("--resume", result.stderr)
        self.assertNotIn("SECRET_FROM_PUSH_FAILURE", result.stdout + result.stderr)
        self.assertEqual(len(self.creations()), 1)
        self.assertEqual(self.registrations(), [])
        self.assertEqual(self.checkpoint()["github"]["repository_id"], 61001)
        self.assertEqual(self.checkpoint()["status"], "failed")
        commit = self.git("rev-parse", "HEAD", cwd=self.target).stdout.strip()
        inode = (self.target / "src/app.py").stat().st_ino
        self.env["ACFS_TEST_FAIL"] = ""
        self.run_cli("--apply", path, "--yes", "--resume")
        self.assertEqual(self.remote_head(), commit)
        self.assertEqual(len(self.creations()), 1)
        self.assertEqual(len(self.registrations()), 1)
        self.assertEqual((self.target / "src/app.py").stat().st_ino, inode)

    def test_failed_registration_keeps_published_commit_and_resume_only_registers(self):
        path = self.save(self.publication_plan(ru=True))
        self.env["ACFS_TEST_FAIL"] = "ru-before"
        result = self.run_cli("--apply", path, "--yes", ok=False)
        self.assertIn(REPO_URL, result.stderr)
        self.assertIn("--resume", result.stderr)
        self.assertNotIn("SECRET_FROM_RU_FAILURE", result.stdout + result.stderr)
        published = self.remote_head()
        self.assertEqual(self.checkpoint()["status"], "failed")
        self.assertEqual(len(self.creations()), 1)
        self.assertEqual(len(self.calls("git", "push")), 1)
        self.env["ACFS_TEST_FAIL"] = ""
        self.run_cli("--apply", path, "--yes", "--resume")
        self.assertEqual(len(self.creations()), 1)
        self.assertEqual(len(self.calls("git", "push")), 1)
        self.assertEqual(self.remote_head(), published)
        self.assertEqual(self.listing().read_text().splitlines(), [REPOSITORY])
        self.assertEqual(self.checkpoint()["status"], "complete")

    def test_resume_recognizes_a_push_that_succeeded_before_response_was_lost(self):
        path = self.save(self.publication_plan(ru=True))
        self.env["ACFS_TEST_FAIL"] = "push-after"
        self.run_cli("--apply", path, "--yes", ok=False)
        head = self.remote_head()
        self.assertEqual(head, self.git("rev-parse", "HEAD", cwd=self.target).stdout.strip())
        self.env["ACFS_TEST_FAIL"] = ""
        self.run_cli("--apply", path, "--yes", "--resume")
        self.assertEqual(self.remote_head(), head)
        self.assertEqual(len(self.calls("git", "push")), 1)
        self.assertEqual(len(self.creations()), 1)
        self.assertEqual(self.checkpoint()["status"], "complete")

    def test_successful_ru_command_without_registration_readback_is_not_complete(self):
        path = self.save(self.publication_plan(ru=True))
        self.env["ACFS_TEST_FAIL"] = "ru-unconfirmed"
        self.run_cli("--apply", path, "--yes", ok=False)
        self.assertNotEqual(self.checkpoint()["status"], "complete")
        self.assertNotIn("ru-register", self.checkpoint()["completed_commands"])

    def test_existing_registration_in_wrong_visibility_list_is_reported(self):
        self.listing("public").parent.mkdir(parents=True)
        self.listing("public").write_text(REPOSITORY + "\n")
        path = self.save(self.publication_plan(ru=True))
        self.run_cli("--apply", path, "--yes", ok=False)
        self.assertEqual(self.remote_head(), self.checkpoint()["github"]["commit"])
        self.assertFalse(self.listing().exists())
        self.assertEqual(self.listing("public").read_text(), REPOSITORY + "\n")
        self.assertNotIn("ru-register", self.checkpoint()["completed_commands"])

    def test_interrupted_registration_can_be_retried_without_duplicate_entries(self):
        path = self.save(self.publication_plan(ru=True))
        self.env["ACFS_TEST_FAIL"] = "ru-after"
        self.run_cli("--apply", path, "--yes", ok=False)
        self.assertEqual(self.listing().read_text().splitlines(), [REPOSITORY])
        self.env["ACFS_TEST_FAIL"] = ""
        self.run_cli("--apply", path, "--yes", "--resume")
        self.assertEqual(self.listing().read_text().splitlines(), [REPOSITORY])
        self.assertEqual(len(self.creations()), 1)
        self.assertEqual(len(self.calls("git", "push")), 1)

    def test_lost_create_response_never_adopts_repository_or_retries_creation_blindly(self):
        path = self.save(self.publication_plan(ru=True))
        self.env["ACFS_TEST_FAIL"] = "create-after"
        result = self.run_cli("--apply", path, "--yes", ok=False)
        self.assertIn(REPO_URL, result.stderr)
        self.assertEqual(len(self.creations()), 1)
        self.assertIn(REPOSITORY, self.repositories())
        self.assertEqual(self.calls("git", "push"), [])
        self.env["ACFS_TEST_FAIL"] = ""
        self.run_cli("--apply", path, "--yes", "--resume", ok=False)
        self.assertEqual(len(self.creations()), 1)
        self.assertEqual(self.calls("git", "push"), [])
        self.assertEqual(self.registrations(), [])

    def test_definite_creation_rejection_can_resume_after_the_problem_is_fixed(self):
        path = self.save(self.publication_plan())
        self.env["ACFS_TEST_FAIL"] = "create-rejected"
        self.run_cli("--apply", path, "--yes", ok=False)
        self.assertFalse(self.checkpoint()["github"]["create_attempted"])
        self.assertIsNone(self.checkpoint()["github"]["repository_id"])
        self.assertEqual(self.repositories(), {})
        self.assertEqual(self.calls("git", "push"), [])
        self.env["ACFS_TEST_FAIL"] = ""
        self.run_cli("--apply", path, "--yes", "--resume")
        self.assertEqual(len(self.creations()), 2)
        self.assertEqual(self.repositories()[REPOSITORY]["id"], 61001)
        self.assertEqual(self.remote_head(), self.checkpoint()["github"]["commit"])

    def test_created_repository_id_survives_interruption_before_step_checkpoint(self):
        path = self.save(self.publication_plan())
        self.env["ACFS_TEST_FAIL"] = "push-before"
        self.run_cli("--apply", path, "--yes", ok=False)
        checkpoint = self.checkpoint()
        self.assertEqual(checkpoint["github"]["repository_id"], 61001)
        # Simulate death between saving the immutable repository identity and
        # marking github-create complete. The accepted repo must not be recreated.
        completed = checkpoint["completed_commands"]
        checkpoint["completed_commands"] = completed[:completed.index("github-create")]
        (self.target / ".acfs/bootstrap-state.json").write_text(json.dumps(checkpoint))
        self.env["ACFS_TEST_FAIL"] = ""
        self.run_cli("--apply", path, "--yes", "--resume")
        self.assertEqual(len(self.creations()), 1)
        self.assertEqual(self.checkpoint()["status"], "complete")
        self.assertEqual(self.remote_head(), checkpoint["github"]["commit"])

    def test_wrong_visibility_returned_from_creation_never_pushes(self):
        path = self.save(self.publication_plan())
        self.env["ACFS_TEST_FAIL"] = "create-wrong-visibility"
        self.run_cli("--apply", path, "--yes", ok=False)
        self.assertEqual(self.repositories()[REPOSITORY]["private"], False)
        self.assertEqual(self.calls("git", "push"), [])

    def test_resume_refuses_remote_identity_or_visibility_changes(self):
        path = self.save(self.publication_plan(ru=True))
        self.env["ACFS_TEST_FAIL"] = "push-before"
        self.run_cli("--apply", path, "--yes", ok=False)
        push_count = len(self.calls("git", "push"))
        self.env["ACFS_TEST_FAIL"] = ""
        for fields in ({"id": 99999}, {"id": 61001, "private": False, "visibility": "public"},
                       {"private": True, "visibility": "internal"},
                       {"visibility": "private", "full_name": "another/repo"}):
            with self.subTest(fields=fields):
                self.set_repository(**fields)
                self.run_cli("--apply", path, "--yes", "--resume", ok=False)
                self.assertEqual(len(self.calls("git", "push")), push_count)
                self.assertEqual(self.registrations(), [])

    def test_resume_refuses_changed_origin_and_pushurl_before_transport(self):
        path = self.save(self.publication_plan())
        self.env["ACFS_TEST_FAIL"] = "push-before"
        self.run_cli("--apply", path, "--yes", ok=False)
        push_count = len(self.calls("git", "push"))
        self.env["ACFS_TEST_FAIL"] = ""
        self.git("remote", "set-url", "origin", "https://github.com/unreviewed/repo.git", cwd=self.target)
        self.run_cli("--apply", path, "--yes", "--resume", ok=False)
        self.assertEqual(len(self.calls("git", "push")), push_count)
        self.git("remote", "set-url", "origin", REMOTE_URL, cwd=self.target)
        self.git("config", "remote.origin.pushurl", "https://github.com/unreviewed/repo.git", cwd=self.target)
        self.run_cli("--apply", path, "--yes", "--resume", ok=False)
        self.assertEqual(len(self.calls("git", "push")), push_count)

    def test_resume_does_not_push_an_unreviewed_commit(self):
        path = self.save(self.publication_plan())
        self.env["ACFS_TEST_FAIL"] = "push-before"
        self.run_cli("--apply", path, "--yes", ok=False)
        push_count = len(self.calls("git", "push"))
        self.git("-c", "user.name=Human", "-c", "user.email=human@example.test", "commit",
                 "--allow-empty", "-m", "Unreviewed later work", cwd=self.target)
        later = self.git("rev-parse", "HEAD", cwd=self.target).stdout.strip()
        self.env["ACFS_TEST_FAIL"] = ""
        self.run_cli("--apply", path, "--yes", "--resume", ok=False)
        self.assertEqual(self.git("rev-parse", "HEAD", cwd=self.target).stdout.strip(), later)
        self.assertEqual(len(self.calls("git", "push")), push_count)

    def test_resume_never_commits_previously_staged_unreviewed_secrets(self):
        plan = self.publication_plan()
        path = self.save(plan)
        self.env["ACFS_TEST_FAIL"] = "commit-before"
        self.run_cli("--apply", path, "--yes", ok=False)
        self.assertEqual(self.creations(), [])
        secret = self.target / ".env"
        secret.write_text("PRIVATE_CREDENTIAL=must-remain-local\n")
        self.git("add", "--force", ".env", cwd=self.target)
        self.env["ACFS_TEST_FAIL"] = ""
        result = subprocess.run([bootstrap.BASH, str(bootstrap.SCRIPT), "--apply", str(path), "--yes", "--resume"],
                                env=self.env, text=True, capture_output=True, timeout=10)
        self.assertEqual(secret.read_text(), "PRIVATE_CREDENTIAL=must-remain-local\n")
        if result.returncode == 0:
            paths = self.git("--git-dir", self.remote, "ls-tree", "--name-only", "-r", "refs/heads/main").stdout.splitlines()
            self.assertEqual(set(paths), set(plan["publication"]["files"]))
            self.assertNotIn(".env", paths)
        else:
            self.assertIn("unreviewed", result.stderr.lower())
            self.assertEqual(self.calls("git", "push"), [])
        self.assertNotIn("must-remain-local", result.stdout + result.stderr)

    def test_resume_blocks_local_url_rewrites_before_any_push_attempt(self):
        path = self.save(self.publication_plan())
        self.env["ACFS_TEST_FAIL"] = "push-before"
        self.run_cli("--apply", path, "--yes", ok=False)
        count = len(self.calls("git", "push"))
        self.git("config", "url.https://unreviewed.example/.insteadOf", "https://github.com/", cwd=self.target)
        self.env["ACFS_TEST_FAIL"] = ""
        self.run_cli("--apply", path, "--yes", "--resume", ok=False)
        self.assertEqual(len(self.calls("git", "push")), count)

    def test_updater_destinations_remain_bound_to_the_reviewed_plan(self):
        path = self.save(self.publication_plan(ru=True))
        self.env["ACFS_TEST_FAIL"] = "ru-before"
        self.run_cli("--apply", path, "--yes", ok=False)
        elsewhere = self.base / "unreviewed-updater-config"
        other_state = self.base / "unreviewed-updater-state"
        self.env.update({"RU_CONFIG_DIR": str(elsewhere), "RU_STATE_DIR": str(other_state),
                         "ACFS_TEST_FAIL": ""})
        self.run_cli("--apply", path, "--yes", "--resume")
        self.assertFalse(elsewhere.exists())
        self.assertFalse(other_state.exists())
        self.assertEqual(self.listing().read_text().splitlines(), [REPOSITORY])

    def test_changed_updater_directory_symlink_blocks_all_apply_side_effects(self):
        path = self.save(self.publication_plan(ru=True))
        outside = self.base / "unreviewed-config"
        outside.mkdir()
        self.config.mkdir()
        (self.config / "repo_updater").symlink_to(outside, target_is_directory=True)
        self.run_cli("--apply", path, "--yes", ok=False)
        self.assertFalse(self.target.exists())
        self.assertEqual(list(outside.iterdir()), [])
        self.assertEqual(self.creations(), [])
        self.assertEqual(self.calls("ru"), [])

    def test_changed_updater_list_symlink_blocks_resume_without_altering_other_files(self):
        path = self.save(self.publication_plan(ru=True))
        self.env["ACFS_TEST_FAIL"] = "ru-before"
        self.run_cli("--apply", path, "--yes", ok=False)
        head = self.remote_head()
        outside = self.base / "unrelated-list.txt"
        outside.write_text("human-owned-content\n")
        self.listing().parent.mkdir(parents=True, exist_ok=True)
        self.listing().symlink_to(outside)
        registration_count = len(self.registrations())
        self.env["ACFS_TEST_FAIL"] = ""
        self.run_cli("--apply", path, "--yes", "--resume", ok=False)
        self.assertEqual(outside.read_text(), "human-owned-content\n")
        self.assertEqual(self.remote_head(), head)
        self.assertEqual(len(self.registrations()), registration_count)
        self.assertEqual(len(self.calls("git", "push")), 1)

    def test_guided_public_save_discloses_publication_and_calls_no_external_tools(self):
        terminal = self.guide_to_review()
        plan_path = self.base / ".demo-acfs-plan.json"
        self.assertFalse(plan_path.exists())
        self.assertFalse(self.target.exists())
        self.assertEqual(self.calls(), [])
        self.assertIn("PUBLIC: anyone", terminal.transcript)
        self.assertIn("GitHub: PUBLIC https://github.com/test-owner/demo", terminal.transcript)
        self.assertIn("Initial commit and push: YES", terminal.transcript)
        self.assertIn(str(self.config), terminal.transcript)
        code, output = guided.GuidedBootstrapTests.decide(self, terminal, "save")
        self.assertEqual(code, 0, terminal.transcript)
        self.assertEqual(json.loads(output)["status"], "planned")
        self.assertFalse(self.target.exists())
        self.assertFalse(self.config.exists())
        self.assertEqual(self.calls(), [])
        plan = json.loads(plan_path.read_text())
        self.assertEqual(plan["github"], {"repository": "test-owner/demo", "visibility": "public"})
        self.assertEqual(plan_path.stat().st_mode & 0o777, 0o600)

    def test_guided_public_selection_still_defaults_to_cancel(self):
        terminal = self.guide_to_review()
        code, output = guided.GuidedBootstrapTests.decide(self, terminal, "")
        self.assertEqual(code, 0, terminal.transcript)
        self.assertEqual(json.loads(output)["status"], "cancelled")
        self.assertFalse((self.base / ".demo-acfs-plan.json").exists())
        self.assertFalse(self.target.exists())
        self.assertFalse(self.config.exists())
        self.assertEqual(self.calls(), [])

    def test_guided_private_create_uses_the_same_publication_and_registration_workflow(self):
        # The existing guided harness selects an organization destination.
        self.env["ACFS_TEST_REPOSITORY"] = "test-owner/demo"
        terminal = self.guide_to_review(visibility="private")
        self.assertEqual(self.calls(), [])
        code, output = guided.GuidedBootstrapTests.decide(self, terminal, "create")
        self.assertEqual(code, 0, terminal.transcript)
        result = json.loads(output)
        self.assertEqual(result["status"], "created")
        self.assertTrue(self.repositories()["test-owner/demo"]["private"])
        self.assertEqual(result["github"]["initial_commit"], self.remote_head())
        self.assertEqual(self.listing().read_text().splitlines(), ["test-owner/demo"])
        self.assertEqual(len(self.creations()), 1)
        self.assertIn("orgs/test-owner/repos", self.creations()[0]["argv"])
        self.assertEqual(self.checkpoint()["status"], "complete")


if __name__ == "__main__":
    unittest.main(verbosity=2)
