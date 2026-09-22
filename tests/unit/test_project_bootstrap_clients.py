"""Native client config and real HTTP/apply coverage; no provider/model calls."""
import contextlib
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import subprocess
import threading
import tomllib
import unittest

import test_project_bootstrap as bootstrap


class ClientBootstrapTests(unittest.TestCase):
    setUp = bootstrap.BootstrapTests.setUp
    run_cli = bootstrap.BootstrapTests.run_cli
    plan = bootstrap.BootstrapTests.plan
    save = bootstrap.BootstrapTests.save

    @contextlib.contextmanager
    def service(self, fail_first=False):
        calls = []

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                calls.append((request, self.headers.get("Authorization")))
                response = {"jsonrpc": "2.0", "id": request["id"]}
                if fail_first and len(calls) == 1:
                    response["error"] = {"message": "fixture failure"}
                else:
                    response["result"] = {"structuredContent": {
                        "human_key": request["params"]["arguments"]["human_key"]}}
                body = json.dumps(response).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)
        thread.start()
        try:
            yield "http://127.0.0.1:%s/api/" % server.server_port, calls
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def client_plan(self, clients, *extra):
        return self.plan("--with", "readme,agents,prompt", "--agent-mail",
                         "http://127.0.0.1:8765/api/", "--agent-mail-clients", clients, *extra)

    @staticmethod
    def files(plan):
        return {entry["path"]: entry["content"] for entry in plan["files"]}

    def test_selection_is_explicit_canonical_and_side_effect_free(self):
        first = self.client_plan("gemini,codex,claude")
        self.assertEqual(first, self.client_plan("claude,codex,gemini"))
        self.assertEqual(first["agent_mail_clients"], ["claude", "codex", "gemini"])
        self.assertFalse(self.target.exists())
        self.assertEqual(list(self.base.iterdir()), [])
        self.assertEqual(len(first["commands"]), 1)
        self.assertFalse(first["effects"]["model_calls"])
        self.assertFalse(first["effects"]["global_settings"])
        for entry in first["files"]:
            self.assertEqual(entry["sha256"], hashlib.sha256(entry["content"].encode()).hexdigest())

    def test_codex_uses_native_toml_and_env_name_not_interpolation(self):
        self.env["MAIL_TEST_TOKEN"] = "credential-must-not-appear"
        plan = self.client_plan("codex", "--agent-mail-token-env", "MAIL_TEST_TOKEN")
        files = self.files(plan)
        config = tomllib.loads(files[".codex/config.toml"])
        self.assertEqual(config, {"mcp_servers": {"mcp-agent-mail": {
            "url": "http://127.0.0.1:8765/api/", "bearer_token_env_var": "MAIL_TEST_TOKEN"}}})
        self.assertNotIn("credential-must-not-appear", json.dumps(plan))
        self.assertNotIn(".mcp.json", files)
        self.assertNotIn(".gemini/settings.json", files)
        self.assertIn("trusted projects", files["AGENT_MAIL.md"])
        self.assertNotIn("Other clients need their own", files["AGENT_MAIL.md"])

    def test_gemini_uses_http_transport_and_shared_policy_without_auto_approval(self):
        files = self.files(self.client_plan("gemini", "--agent-mail-token-env", "MAIL_TEST_TOKEN"))
        config = json.loads(files[".gemini/settings.json"])
        self.assertEqual(config, {"mcpServers": {"mcp-agent-mail": {
            "httpUrl": "http://127.0.0.1:8765/api/", "trust": False,
            "headers": {"Authorization": "Bearer ${MAIL_TEST_TOKEN}"}}},
            "context": {"fileName": ["AGENTS.md", "GEMINI.md"]}})
        self.assertNotIn(".mcp.json", files)
        self.assertNotIn(".codex/config.toml", files)
        self.assertIn("/memory show", files["AGENT_MAIL.md"])

    def test_claude_imports_shared_policy_without_copying_it(self):
        files = self.files(self.client_plan("claude"))
        self.assertEqual(files["CLAUDE.md"], "@AGENTS.md\n")
        self.assertEqual(json.loads(files[".mcp.json"]), {"mcpServers": {"mcp-agent-mail": {
            "type": "http", "url": "http://127.0.0.1:8765/api/"}}})
        self.assertIn("AGENT_MAIL.md", files["AGENTS.md"])
        self.assertIn("/context", files["AGENT_MAIL.md"])

    def test_no_dangling_policy_import_when_policy_feature_is_not_selected(self):
        files = self.files(self.plan("--with", "readme", "--agent-mail", "http://127.0.0.1:8765/api/",
                                     "--agent-mail-clients", "claude,codex,gemini"))
        self.assertNotIn("AGENTS.md", files)
        self.assertNotIn("CLAUDE.md", files)
        self.assertNotIn("context", json.loads(files[".gemini/settings.json"]))

    def test_unauthenticated_configs_do_not_import_ambient_tokens(self):
        self.env["AGENT_MAIL_TOKEN"] = "ambient-secret"
        files = self.files(self.client_plan("claude,codex,gemini"))
        for name in (".mcp.json", ".gemini/settings.json"):
            self.assertNotIn("Authorization", files[name])
        self.assertNotIn("bearer_token_env_var", files[".codex/config.toml"])
        self.assertNotIn("ambient-secret", json.dumps(files))

    def test_invalid_clients_and_orphan_option_fail_without_mutation(self):
        for clients in ("", "claude,claude", "codex,", "unknown", "CODEX", "codex, gemini", "../other", "$(touch marker)"):
            with self.subTest(clients=clients):
                self.run_cli("--plan", "demo", self.target, "--with", "readme", "--agent-mail",
                             "http://127.0.0.1:8765/api/", "--agent-mail-clients", clients, ok=False)
        self.run_cli("--plan", "demo", self.target, "--with", "readme", "--agent-mail-clients", "codex", ok=False)
        self.assertEqual(list(self.base.iterdir()), [])

    def test_apply_cannot_override_or_rehash_arbitrary_client_configuration(self):
        plan = self.client_plan("codex")
        path = self.save(plan)
        for value in ("gemini", ""):
            self.run_cli("--apply", path, "--yes", "--agent-mail-clients", value, ok=False)
        config = next(f for f in plan["files"] if f["path"] == ".codex/config.toml")
        config["content"] += 'approval_policy = "never"\n'
        config["sha256"] = hashlib.sha256(config["content"].encode()).hexdigest()
        plan.pop("plan_id")
        plan["plan_id"] = hashlib.sha256(json.dumps(plan, sort_keys=True, ensure_ascii=True, separators=(",", ":")).encode()).hexdigest()
        self.run_cli("--apply", self.save(plan), "--yes", ok=False)
        self.assertFalse(self.target.exists())

    def test_all_clients_apply_once_with_private_token_and_resume_without_it(self):
        with self.service() as (url, calls):
            home = self.base / "home"
            home.mkdir()
            self.env.update({"HOME": str(home), "MAIL_TEST_TOKEN": "private-test-token"})
            plan = self.plan("--preset", "first-project", "--agent-mail", url,
                             "--agent-mail-clients", "claude,codex,gemini",
                             "--agent-mail-token-env", "MAIL_TEST_TOKEN")
            self.assertEqual(calls, [])
            path = self.save(plan)
            result = self.run_cli("--apply", path, "--yes")
            self.assertEqual(len(calls), 1)
            self.assertEqual(calls[0][1], "Bearer private-test-token")
            self.assertEqual(calls[0][0]["params"], {"name": "ensure_project", "arguments": {"human_key": str(self.target)}})
            self.assertEqual(list(home.iterdir()), [])
            self.assertNotIn("private-test-token", result.stdout + result.stderr)
            for entry in plan["files"]:
                self.assertEqual((self.target / entry["path"]).read_text(), entry["content"])
                self.assertNotIn("private-test-token", entry["content"])
            for name in (".mcp.json", ".codex/config.toml", ".gemini/settings.json"):
                check = subprocess.run(["git", "-C", str(self.target), "check-ignore", "--", name], capture_output=True)
                self.assertEqual(check.returncode, 0, name)
            self.env.pop("MAIL_TEST_TOKEN")
            before = (self.target / ".codex/config.toml").stat().st_ino
            self.run_cli("--apply", path, "--yes", "--resume")
            self.assertEqual((self.target / ".codex/config.toml").stat().st_ino, before)
            self.assertEqual(len(calls), 1)

    def test_failed_registration_resumes_without_rewriting_selected_configs(self):
        with self.service(fail_first=True) as (url, calls):
            plan = self.plan("--with", "readme", "--agent-mail", url, "--agent-mail-clients", "codex,gemini")
            path = self.save(plan)
            self.run_cli("--apply", path, "--yes", ok=False)
            before = (self.target / ".gemini/settings.json").stat().st_ino
            self.run_cli("--apply", path, "--yes", "--resume")
            self.assertEqual((self.target / ".gemini/settings.json").stat().st_ino, before)
            self.assertEqual(len(calls), 2)
            self.assertEqual(json.loads((self.target / ".acfs/bootstrap-state.json").read_text())["status"], "complete")

    def test_edited_config_blocks_resume_before_network_or_missing_file_writes(self):
        with self.service(fail_first=True) as (url, calls):
            path = self.save(self.plan("--with", "readme", "--agent-mail", url, "--agent-mail-clients", "codex,gemini"))
            self.run_cli("--apply", path, "--yes", ok=False)
            (self.target / ".codex/config.toml").write_text("human edits")
            (self.target / "README.md").rename(self.target / "README.saved")
            self.run_cli("--apply", path, "--yes", "--resume", ok=False)
            self.assertEqual(len(calls), 1)
            self.assertFalse((self.target / "README.md").exists())
            self.assertEqual((self.target / ".codex/config.toml").read_text(), "human edits")

    def test_nested_config_symlink_cannot_redirect_resume(self):
        with self.service(fail_first=True) as (url, calls):
            path = self.save(self.plan("--with", "readme", "--agent-mail", url, "--agent-mail-clients", "codex"))
            self.run_cli("--apply", path, "--yes", ok=False)
            original = self.target / ".codex"
            moved = self.base / "outside"
            original.rename(moved)
            original.symlink_to(moved, target_is_directory=True)
            before = (moved / "config.toml").read_bytes()
            self.run_cli("--apply", path, "--yes", "--resume", ok=False)
            self.assertEqual(len(calls), 1)
            self.assertEqual((moved / "config.toml").read_bytes(), before)

    def test_default_remains_claude_only_and_does_not_change_plan_shape(self):
        plan = self.plan("--with", "readme", "--agent-mail", "http://127.0.0.1:8765/api/")
        self.assertNotIn("agent_mail_clients", plan)
        files = self.files(plan)
        self.assertEqual(set(files), {".gitignore", ".mcp.json", "README.md", "AGENT_MAIL.md"})
        self.assertIn("Other clients need their own reviewed connection configuration", files["AGENT_MAIL.md"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
