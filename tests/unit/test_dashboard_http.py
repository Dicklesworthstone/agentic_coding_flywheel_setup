"""Exercise the dashboard's real HTTP server against private on-disk pages."""
import contextlib
import http.client
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import tempfile
import time
import unittest


SOURCE = Path(os.environ.get("ACFS_DASHBOARD_TEST_SOURCE", str(
    Path(__file__).resolve().parents[2] / "scripts/lib/dashboard.sh")))
PAGE = b"<!doctype html><title>ACFS dashboard</title><p>Published status</p>\n"


class DashboardHTTPTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="acfs-dashboard-http-")
        self.addCleanup(self.scratch.cleanup)
        self.base = Path(self.scratch.name)
        self.acfs = self.base / ".acfs"
        self.script = self.acfs / "scripts/lib/dashboard.sh"
        self.script.parent.mkdir(parents=True)
        shutil.copyfile(SOURCE, self.script)
        self.directory = self.acfs / "dashboard"
        self.directory.mkdir()
        self.index = self.directory / "index.html"
        self.index.write_bytes(PAGE)
        self.env = dict(os.environ, HOME=str(self.base), ACFS_HOME=str(self.acfs),
                        ACFS_SYSTEM_STATE_FILE=str(self.base / "absent-state.json"))

    def request(self, port, path="/", method="GET", host="127.0.0.1"):
        connection = http.client.HTTPConnection(host, port, timeout=2)
        try:
            connection.request(method, path)
            response = connection.getresponse()
            headers = {name.lower(): value for name, value in response.getheaders()}
            return response.status, headers, response.read()
        finally:
            connection.close()

    @contextlib.contextmanager
    def server(self, *options, host="127.0.0.1"):
        family = socket.AF_INET6 if ":" in host else socket.AF_INET
        with socket.socket(family) as probe:
            probe.bind((host, 0))
            port = probe.getsockname()[1]
        log_path = self.base / "server.log"
        with log_path.open("wb") as log:
            process = subprocess.Popen(
                ["bash", str(self.script), "serve", "--port", str(port), *options],
                env=self.env, stdout=log, stderr=log, start_new_session=True)
            try:
                deadline = time.monotonic() + 5
                while True:
                    if process.poll() is not None:
                        self.fail(log_path.read_text())
                    try:
                        self.request(port, host=host)
                        break
                    except (OSError, http.client.HTTPException):
                        if time.monotonic() >= deadline:
                            self.fail("Server did not become ready: " + log_path.read_text())
                        time.sleep(0.02)
                yield port, log_path
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=5)

    def test_published_page_get_head_and_query(self):
        with self.server() as (port, _):
            for path in ("/", "/index.html", "/?refresh=1", "/index.html?refresh=1"):
                with self.subTest(path=path):
                    status, headers, body = self.request(port, path)
                    self.assertEqual(status, 200)
                    self.assertEqual(body, PAGE)
                    self.assertEqual(int(headers["content-length"]), len(PAGE))
                    self.assertIn("text/html", headers["content-type"])
                    status, headers, body = self.request(port, path, "HEAD")
                    self.assertEqual(status, 200)
                    self.assertEqual(body, b"")
                    self.assertEqual(int(headers["content-length"]), len(PAGE))

    def test_only_published_page_is_served(self):
        for name in ("index.html.tmp.interrupted", ".last_generated", "notes.txt"):
            (self.directory / name).write_text("private-artifact")
        (self.directory / "nested").mkdir()
        (self.directory / "nested/private.txt").write_text("private-artifact")
        (self.acfs / "secret.txt").write_text("private-artifact")
        (self.directory / "linked.txt").symlink_to(self.acfs / "secret.txt")
        with self.server() as (port, _):
            for path in ("/index.html.tmp.interrupted", "/.last_generated", "/notes.txt",
                         "/nested/", "/nested/private.txt", "/linked.txt", "/../secret.txt",
                         "/%2e%2e/secret.txt", "/%69ndex.html", "/index.html/", "//outside/"):
                with self.subTest(path=path):
                    for method in ("GET", "HEAD"):
                        status, _, body = self.request(port, path, method)
                        self.assertEqual(status, 404)
                        self.assertNotIn(b"private-artifact", body)

    def test_missing_page_does_not_enable_directory_listing(self):
        (self.directory / "index.html.tmp.private").write_text("private-artifact")
        with self.server() as (port, _):
            self.index.rename(self.directory / "retained-page.html")
            status, _, body = self.request(port)
            self.assertEqual(status, 404)
            self.assertNotIn(b"index.html.tmp.private", body)
            self.assertNotIn(b"retained-page.html", body)

    def test_index_symlink_is_not_followed(self):
        self.index.rename(self.directory / "retained-page.html")
        private = self.base / "secret.txt"
        private.write_text("private-artifact")
        self.index.symlink_to(private)
        with self.server() as (port, _):
            status, _, body = self.request(port)
            self.assertEqual(status, 403)
            self.assertNotIn(b"private-artifact", body)

    def test_index_directory_is_not_listed(self):
        with self.server() as (port, _):
            self.index.rename(self.directory / "retained-page.html")
            self.index.mkdir()
            (self.index / "private.txt").write_text("private-artifact")
            status, _, body = self.request(port)
            self.assertEqual(status, 403)
            self.assertNotIn(b"private.txt", body)

    def test_atomic_page_replacement_remains_visible(self):
        with self.server() as (port, _):
            self.index.rename(self.directory / "retained-page.html")
            replacement = self.directory / "index.html.tmp.next"
            replacement.write_bytes(PAGE.replace(b"Published", b"Updated"))
            replacement.rename(self.index)
            self.assertEqual(self.request(port)[2], PAGE.replace(b"Published", b"Updated"))

    def test_index_fifo_is_rejected_without_blocking(self):
        with self.server() as (port, _):
            self.index.rename(self.directory / "retained-page.html")
            os.mkfifo(self.index)
            self.assertEqual(self.request(port)[0], 403)

    def test_sourced_server_preserves_working_directory(self):
        result = subprocess.run(
            ["bash", "-c", 'source "$1"; '
             'dashboard_system_binary_path() { [[ $1 == python3 ]] && printf /usr/bin/true; }; '
             'dashboard_serve --port 19099; pwd', "_", str(self.script)],
            env=self.env, cwd=self.base, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.decode().splitlines()[-1], str(self.base))

    def test_occupied_port_still_fails(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            port = listener.getsockname()[1]
            result = subprocess.run(
                ["bash", str(self.script), "serve", "--port", str(port)], env=self.env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(str(port).encode(), result.stdout + result.stderr)

    def test_missing_page_is_generated_before_serving(self):
        self.index.rename(self.directory / "retained-page.html")
        (self.script.parent / "info.sh").write_text(
            "#!/usr/bin/env bash\n"
            "[[ $1 == --html && $2 == --live ]] || exit 2\n"
            "printf '%s\\n' '<!doctype html><p>Fresh status</p>'\n")
        with self.server() as (port, _):
            self.assertEqual(self.request(port)[2], b"<!doctype html><p>Fresh status</p>\n")

    def test_generation_failure_is_propagated_when_sourced(self):
        self.index.rename(self.directory / "retained-page.html")
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        with subprocess.Popen(
            ["bash", "-c", 'source "$1"; dashboard_generate() { return 7; }; '
             'if dashboard_serve --port "$2"; then exit 9; else exit 0; fi',
             "_", str(self.script), str(port)], env=self.env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True) as process:
            try:
                stdout, stderr = process.communicate(timeout=5)
                self.assertEqual(process.returncode, 0, stdout + stderr)
                self.assertNotIn(b"http://", stdout)
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=5)

    def test_public_bind_explains_unauthenticated_access(self):
        with self.server("--public") as (port, log):
            self.assertEqual(self.request(port)[2], PAGE)
            self.assertIn("NO authentication", log.read_text())
            self.assertIn("SSH tunnel", log.read_text())

    def test_ipv6_loopback_is_local_and_works(self):
        try:
            with socket.socket(socket.AF_INET6) as probe:
                probe.bind(("::1", 0))
        except OSError as error:
            self.skipTest("IPv6 loopback unavailable: " + str(error))
        with self.server("--host", "::1", host="::1") as (port, log):
            self.assertEqual(self.request(port, host="::1")[2], PAGE)
            self.assertIn(f"http://[::1]:{port}", log.read_text())
            self.assertNotIn("Network URL:", log.read_text())


if __name__ == "__main__":
    unittest.main()
