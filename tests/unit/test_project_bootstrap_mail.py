"""Real loopback HTTP coverage for the reviewed Agent Mail bootstrap boundary."""
import contextlib
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import threading
import unittest

import test_project_bootstrap as bootstrap


class MailBootstrapTests(unittest.TestCase):
    setUp = bootstrap.BootstrapTests.setUp
    run_cli = bootstrap.BootstrapTests.run_cli
    plan = bootstrap.BootstrapTests.plan
    save = bootstrap.BootstrapTests.save

    @contextlib.contextmanager
    def service(self, response=None, status=200, content_type="application/json"):
        calls = []
        test = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                calls.append({"request": request, "authorization": self.headers.get("Authorization"),
                              "path": self.path, "config_exists": (test.target / ".mcp.json").exists()})
                output = response(request) if callable(response) else response
                if output is None:
                    output = {"jsonrpc": "2.0", "id": request["id"], "result": {"content": [
                        {"type": "text", "text": json.dumps({"id": 1, "human_key": request["params"]["arguments"]["human_key"]})}]}}
                payload = output if isinstance(output, bytes) else json.dumps(output).encode()
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(payload)))
                if status == 307:
                    self.send_header("Location", "/redirected/")
                self.end_headers()
                self.wfile.write(payload)

            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True)
        thread.start()
        try:
            yield "http://127.0.0.1:%s/api/" % server.server_port, calls
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def test_plan_discloses_network_but_makes_no_requests_or_secret_reads(self):
        with self.service() as (url, calls):
            self.env["ACFS_MAIL_TEST_TOKEN"] = "never-copy-this-secret"
            plan = self.plan("--preset", "first-project", "--agent-mail", url,
                             "--agent-mail-token-env", "ACFS_MAIL_TEST_TOKEN")
            self.assertEqual(calls, [])
            self.assertFalse(self.target.exists())
            self.assertTrue(plan["effects"]["network"])
            self.assertFalse(plan["effects"]["model_calls"])
            self.assertNotIn("never-copy-this-secret", json.dumps(plan))
            files = {f["path"]: f["content"] for f in plan["files"]}
            config = json.loads(files[".mcp.json"])["mcpServers"]["mcp-agent-mail"]
            self.assertEqual(config["headers"]["Authorization"], "Bearer ${ACFS_MAIL_TEST_TOKEN}")
            self.assertEqual(config["url"], url)
            self.assertIn("/.mcp.json\n", files[".gitignore"])
            self.assertIn("register_agent", files["AGENT_MAIL.md"])
            self.assertIn("exception to the network restriction", files["FIRST_AGENT_PROMPT.md"])
            self.assertEqual(plan["commands"][-1]["arguments"], {"human_key": str(self.target)})

    def test_apply_registers_exact_project_with_private_auth_then_checkpoints(self):
        with self.service() as (url, calls):
            self.env["ACFS_MAIL_TEST_TOKEN"] = "private-test-token"
            plan = self.plan("--with", "readme", "--agent-mail", url,
                             "--agent-mail-token-env", "ACFS_MAIL_TEST_TOKEN")
            path = self.save(plan)
            result = self.run_cli("--apply", path, "--yes")
            self.assertEqual(len(calls), 1)
            self.assertEqual(calls[0]["authorization"], "Bearer private-test-token")
            self.assertTrue(calls[0]["config_exists"])
            self.assertEqual(calls[0]["request"]["params"], {"name": "ensure_project", "arguments": {"human_key": str(self.target)}})
            self.assertNotIn("private-test-token", result.stdout + result.stderr)
            for file in self.target.rglob("*"):
                if file.is_file():
                    self.assertNotIn(b"private-test-token", file.read_bytes())
            state = json.loads((self.target / ".acfs/bootstrap-state.json").read_text())
            self.assertEqual(state["completed_commands"], ["agent-mail-project"])
            self.assertEqual(state["status"], "complete")
            self.env.pop("ACFS_MAIL_TEST_TOKEN")
            self.run_cli("--apply", path, "--yes", "--resume")
            self.assertEqual(len(calls), 1, "completed resume must not repeat network calls or require old credentials")

    def test_missing_or_invalid_token_fails_before_any_local_mutation(self):
        with self.service() as (url, calls):
            path = self.save(self.plan("--with", "readme", "--agent-mail", url,
                                       "--agent-mail-token-env", "ACFS_MAIL_TEST_TOKEN"))
            for token in (None, "", "value\ninjection", "has space", "x" * 8193):
                if token is None:
                    self.env.pop("ACFS_MAIL_TEST_TOKEN", None)
                else:
                    self.env["ACFS_MAIL_TEST_TOKEN"] = token
                self.run_cli("--apply", path, "--yes", ok=False)
                self.assertFalse(self.target.exists())
                self.assertEqual(calls, [])

    def test_unauthenticated_loopback_does_not_use_ambient_credentials_or_proxies(self):
        with self.service() as (url, calls):
            self.env.update({"HTTP_BEARER_TOKEN": "ambient-secret", "AGENT_MAIL_TOKEN": "ambient-secret",
                             "http_proxy": "http://127.0.0.1:1", "HTTP_PROXY": "http://127.0.0.1:1",
                             "ALL_PROXY": "http://127.0.0.1:1", "NO_PROXY": ""})
            path = self.save(self.plan("--with", "readme", "--agent-mail", url))
            self.run_cli("--apply", path, "--yes")
            self.assertIsNone(calls[0]["authorization"])

    def test_failed_registration_resumes_same_plan_without_recreating_files(self):
        attempts = []

        def respond(request):
            attempts.append(request)
            if len(attempts) == 1:
                return {"jsonrpc": "2.0", "id": request["id"], "error": {"message": "do not echo credentials"}}
            return {"jsonrpc": "2.0", "id": request["id"], "result": {
                "structuredContent": {"human_key": str(self.target)}}}

        with self.service(respond) as (url, calls):
            path = self.save(self.plan("--preset", "first-project", "--agent-mail", url))
            failed = self.run_cli("--apply", path, "--yes", ok=False)
            self.assertNotIn("do not echo credentials", failed.stderr)
            original = (self.target / "src/app.py").stat().st_ino
            state_path = self.target / ".acfs/bootstrap-state.json"
            state = json.loads(state_path.read_text())
            self.assertEqual(state["status"], "failed")
            self.assertNotIn("agent-mail-project", state["completed_commands"])
            self.run_cli("--apply", path, "--yes", "--resume")
            self.assertEqual(original, (self.target / "src/app.py").stat().st_ino)
            self.assertEqual(len(calls), 2)
            self.assertEqual(json.loads(state_path.read_text())["status"], "complete")

    def test_redirects_are_not_followed_and_response_body_is_not_logged(self):
        with self.service(b"SECRET-IN-ERROR", status=307) as (url, calls):
            path = self.save(self.plan("--with", "readme", "--agent-mail", url))
            result = self.run_cli("--apply", path, "--yes", ok=False)
            self.assertEqual(len(calls), 1)
            self.assertIn("307", result.stderr)
            self.assertNotIn("SECRET-IN-ERROR", result.stderr)
            self.assertEqual(calls[0]["path"], "/api/")

    def test_wrong_project_and_error_envelopes_never_complete(self):
        cases = [
            {"jsonrpc": "2.0", "id": "wrong", "result": {}},
            {"jsonrpc": "2.0", "id": "acfs-project", "error": {"message": "SECRET"}},
            {"jsonrpc": "2.0", "id": "acfs-project", "result": {"isError": True, "content": []}},
            {"jsonrpc": "2.0", "id": "acfs-project", "result": {"structuredContent": {"human_key": "/wrong"}}},
            b'{"jsonrpc":"2.0","jsonrpc":"2.0"}', b"not-json", b"x" * 65537,
        ]
        for index, payload in enumerate(cases):
            with self.subTest(index=index), self.service(payload) as (url, calls):
                self.target = self.base / ("project" + str(index))
                path = self.save(self.plan("--with", "readme", "--agent-mail", url))
                result = self.run_cli("--apply", path, "--yes", ok=False)
                self.assertNotIn("SECRET", result.stderr)
                self.assertEqual(len(calls), 1)
                state = json.loads((self.target / ".acfs/bootstrap-state.json").read_text())
                self.assertEqual(state["status"], "failed")
                self.assertEqual(state["completed_commands"], [])

    def test_non_json_service_cannot_be_mistaken_for_success(self):
        with self.service(b"data: {}\n\n", content_type="text/event-stream") as (url, calls):
            path = self.save(self.plan("--with", "readme", "--agent-mail", url))
            result = self.run_cli("--apply", path, "--yes", ok=False)
            self.assertIn("stateless JSON API", result.stderr)

    def test_unsafe_or_credential_bearing_endpoints_are_rejected(self):
        urls = ["http://example.com/api/", "http://localhost:8765/api/", "ftp://127.0.0.1/api/",
                "http://user:secret@127.0.0.1/api/", "http://127.0.0.1/api/?token=secret",
                "http://127.0.0.1/api/#secret", "http://127.0.0.1/api/\n", "http://127.0.0.1:0/api/",
                "http://127.0.0.1:99999/api/", "http://127.0.0.1/api/${SECRET}/", "http://127.0.0.1/api"]
        for url in urls:
            with self.subTest(url=url):
                self.run_cli("--plan", "demo", self.target, "--with", "readme", "--agent-mail", url, ok=False)
        self.assertFalse(self.target.exists())

    def test_remote_service_requires_https_and_explicit_credential_source(self):
        self.run_cli("--plan", "demo", self.target, "--with", "readme", "--agent-mail", "https://mail.example/api/", ok=False)
        plan = self.plan("--with", "readme", "--agent-mail", "https://mail.example/api/",
                         "--agent-mail-token-env", "ACFS_MAIL_TEST_TOKEN")
        self.assertEqual(plan["agent_mail"]["token_env"], "ACFS_MAIL_TEST_TOKEN")
        self.assertFalse(self.target.exists())

    def test_plan_modifications_and_apply_overrides_cannot_change_network_action(self):
        with self.service() as (url, calls):
            plan = self.plan("--with", "readme", "--agent-mail", url)
            plan["commands"][-1]["arguments"]["human_key"] = "/another/project"
            plan.pop("plan_id")
            plan["plan_id"] = hashlib.sha256(json.dumps(plan, sort_keys=True, ensure_ascii=True, separators=(",", ":")).encode()).hexdigest()
            self.run_cli("--apply", self.save(plan), "--yes", ok=False)
            good = self.save(self.plan("--with", "readme", "--agent-mail", url))
            self.run_cli("--apply", good, "--yes", "--agent-mail", url, ok=False)
            self.assertFalse(self.target.exists())
            self.assertEqual(calls, [])

    def test_edited_mcp_config_blocks_resume_before_another_request(self):
        with self.service({"error": "failure"}) as (url, calls):
            path = self.save(self.plan("--with", "readme", "--agent-mail", url))
            self.run_cli("--apply", path, "--yes", ok=False)
            (self.target / ".mcp.json").write_text("human edits")
            self.run_cli("--apply", path, "--yes", "--resume", ok=False)
            self.assertEqual(len(calls), 1)
            self.assertEqual((self.target / ".mcp.json").read_text(), "human edits")

    def test_connection_options_are_not_accepted_without_explicit_selection(self):
        self.run_cli("--plan", "demo", self.target, "--with", "readme", "--agent-mail-token-env", "TOKEN", ok=False)
        self.run_cli("--plan", "demo", self.target, "--with", "agent-mail", ok=False)
        self.run_cli("--plan", "demo", self.target, "--with", "readme", "--agent-mail", "http://127.0.0.1:8765/api/",
                     "--agent-mail-token-env", "token;print-secret", ok=False)
        self.assertFalse(self.target.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
