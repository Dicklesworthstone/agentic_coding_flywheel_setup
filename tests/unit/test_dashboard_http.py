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

    def test_dashboard_directory_symlink_is_not_followed(self):
        retained = self.base / "retained-dashboard"
        self.directory.rename(retained)
        private = self.base / "private-dashboard"
        private.mkdir()
        (private / "index.html").write_bytes(b"private-parent-artifact")
        self.directory.symlink_to(private, target_is_directory=True)
        with self.server() as (port, _):
            for method in ("GET", "HEAD"):
                status, _, body = self.request(port, "/index.html?refresh=1", method)
                self.assertNotIn(b"private-parent-artifact", body)
                self.assertEqual(status, 403)
        self.assertEqual((retained / "index.html").read_bytes(), PAGE)
        self.assertEqual((private / "index.html").read_bytes(), b"private-parent-artifact")
        self.assertTrue(self.directory.is_symlink())

    def test_acfs_ancestor_symlink_is_not_followed(self):
        retained = self.base / "retained-acfs"
        self.acfs.rename(retained)
        self.acfs.symlink_to(retained, target_is_directory=True)
        (retained / "dashboard/index.html").write_bytes(b"private-ancestor-artifact")
        with self.server() as (port, _):
            for method in ("GET", "HEAD"):
                status, _, body = self.request(port, "/", method)
                self.assertNotIn(b"private-ancestor-artifact", body)
                self.assertEqual(status, 403)
        self.assertTrue(self.acfs.is_symlink())
        self.assertEqual((retained / "dashboard/index.html").read_bytes(), b"private-ancestor-artifact")

    def test_ancestor_replacement_after_start_is_not_followed(self):
        with self.server() as (port, _):
            retained = self.base / "retained-running-acfs"
            self.acfs.rename(retained)
            private = self.base / "private-running-acfs"
            (private / "dashboard").mkdir(parents=True)
            (private / "dashboard/index.html").write_bytes(b"private-replacement-artifact")
            self.acfs.symlink_to(private, target_is_directory=True)
            for method in ("GET", "HEAD"):
                status, _, body = self.request(port, "/", method)
                self.assertNotIn(b"private-replacement-artifact", body)
                self.assertEqual(status, 403)
            self.assertEqual((retained / "dashboard/index.html").read_bytes(), PAGE)

    def test_symlink_before_dotdot_is_not_normalized_away(self):
        self.directory.rename(self.base / "retained-dotdot-dashboard")
        outside = self.base / "outside-dotdot"
        outside.mkdir()
        self.directory.symlink_to(outside, target_is_directory=True)
        private = self.base / "dashboard"
        private.mkdir()
        (private / "index.html").write_bytes(b"private-dotdot-artifact")
        # A checkout invocation permits an explicit ACFS_HOME. Keep the link
        # followed by .. in that actual CLI argument, rather than resolving it.
        self.script = self.base / "checkout/scripts/lib/dashboard.sh"
        self.script.parent.mkdir(parents=True)
        shutil.copyfile(SOURCE, self.script)
        self.env["ACFS_HOME"] = str(self.acfs / "dashboard" / "..")
        with self.server() as (port, _):
            for method in ("GET", "HEAD"):
                status, _, body = self.request(port, "/", method)
                self.assertNotIn(b"private-dotdot-artifact", body)
                self.assertEqual(status, 403)

    def test_caller_python_path_cannot_replace_http_modules(self):
        poison = self.base / "python-path"
        poison.mkdir()
        (poison / "http.py").write_text(
            'raise RuntimeError("fixture module must never replace the standard HTTP server")\n')
        self.env["PYTHONPATH"] = str(poison)
        with self.server() as (port, _):
            self.assertEqual(self.request(port)[2], PAGE)

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


class DashboardGenerationTests(unittest.TestCase):
    """Run the real generator with a controlled, local info renderer."""

    NEW_PAGE = b"<!doctype html><p>New generated status</p>\n"

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="acfs-dashboard-generate-")
        self.addCleanup(self.scratch.cleanup)
        self.base = Path(self.scratch.name)
        self.script = self.base / "checkout/scripts/lib/dashboard.sh"
        self.script.parent.mkdir(parents=True)
        shutil.copyfile(SOURCE, self.script)
        self.acfs = self.base / ".acfs"
        self.directory = self.acfs / "dashboard"
        self.directory.mkdir(parents=True)
        (self.acfs / "VERSION").write_text("0.0.0\n")
        self.index = self.directory / "index.html"
        self.index.write_bytes(PAGE)
        self.stamp = self.directory / ".last_generated"
        self.stamp.write_bytes(b"0\n")
        self.called = self.base / "renderer-called"
        self.started = self.base / "renderer-started"
        self.release = self.base / "renderer-release"
        (self.script.parent / "info.sh").write_text(
            '#!/usr/bin/env bash\n'
            '[[ $1 == --html && $2 == --live ]] || exit 77\n'
            'printf "called\\n" >> "$ACFS_TEST_RENDER_CALLED"\n'
            'if [[ $ACFS_TEST_RENDER_MODE == wait ]]; then\n'
            '  : > "$ACFS_TEST_RENDER_STARTED"\n'
            '  while [[ ! -f $ACFS_TEST_RENDER_RELEASE ]]; do sleep 0.01; done\n'
            'fi\n'
            'if [[ $ACFS_TEST_RENDER_MODE == fail ]]; then printf "partial\\n"; exit 9; fi\n'
            'printf "%s" "$ACFS_TEST_RENDER_PAGE"\n')
        self.env = dict(os.environ, HOME=str(self.base), ACFS_HOME=str(self.acfs),
                        ACFS_SYSTEM_STATE_FILE=str(self.base / "absent-state.json"),
                        ACFS_TEST_RENDER_CALLED=str(self.called),
                        ACFS_TEST_RENDER_STARTED=str(self.started),
                        ACFS_TEST_RENDER_RELEASE=str(self.release),
                        ACFS_TEST_RENDER_PAGE=self.NEW_PAGE.decode())

    @contextlib.contextmanager
    def generation(self, *, mode="normal", force=True, limit=None):
        command = ["bash", str(self.script), "generate", *(["--force"] if force else [])]
        env = dict(self.env, ACFS_TEST_RENDER_MODE=mode)
        with subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              start_new_session=True, preexec_fn=limit) as process:
            try:
                yield process
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                process.communicate(timeout=5)

    def generate(self, **options):
        with self.generation(**options) as process:
            stdout, stderr = process.communicate(timeout=5)
            return subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)

    def while_rendering(self, change):
        with self.generation(mode="wait") as process:
            deadline = time.monotonic() + 5
            while not self.started.exists():
                if process.poll() is not None:
                    self.fail(process.communicate())
                if time.monotonic() >= deadline:
                    self.fail("Renderer did not start")
                time.sleep(0.01)
            change()
            self.release.touch()
            stdout, stderr = process.communicate(timeout=5)
            return subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)

    def test_success_publishes_complete_page_and_freshness(self):
        before = int(time.time())
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.index.read_bytes(), self.NEW_PAGE)
        self.assertTrue(before <= int(self.stamp.read_bytes()) <= int(time.time()))

    def test_recent_page_is_reused_without_rendering_or_writes(self):
        self.stamp.write_text(str(int(time.time())) + "\n")
        before = [(path.stat().st_ino, path.stat().st_mtime_ns) for path in (self.index, self.stamp)]
        entries = set(self.directory.iterdir())
        result = self.generate(force=False, mode="fail")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.called.exists())
        self.assertEqual(self.index.read_bytes(), PAGE)
        self.assertEqual(before, [(path.stat().st_ino, path.stat().st_mtime_ns) for path in (self.index, self.stamp)])
        self.assertEqual(entries, set(self.directory.iterdir()))

    def test_timestamp_symlink_preserves_its_target_and_page(self):
        self.stamp.rename(self.directory / "retained-timestamp")
        private = self.base / "private-timestamp"
        private.write_bytes(b"private timestamp data\n")
        self.stamp.symlink_to(private)
        result = self.generate()
        self.assertEqual(private.read_bytes(), b"private timestamp data\n")
        self.assertEqual(self.index.read_bytes(), PAGE)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.stamp.is_symlink())
        self.assertFalse(self.called.exists())

    def test_timestamp_hardlink_preserves_its_target_and_page(self):
        self.stamp.rename(self.directory / "retained-timestamp")
        private = self.base / "hardlinked-timestamp"
        private.write_bytes(b"private hardlink data\n")
        os.link(private, self.stamp)
        result = self.generate()
        self.assertEqual(private.read_bytes(), b"private hardlink data\n")
        self.assertEqual(self.index.read_bytes(), PAGE)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(private.stat().st_ino, self.stamp.stat().st_ino)
        self.assertFalse(self.called.exists())

    def test_linked_dashboard_directory_does_not_redirect_writes(self):
        retained = self.base / "retained-dashboard"
        self.directory.rename(retained)
        private = self.base / "private-dashboard"
        private.mkdir()
        (private / "index.html").write_bytes(b"private page\n")
        (private / ".last_generated").write_bytes(b"private stamp\n")
        self.directory.symlink_to(private, target_is_directory=True)
        result = self.generate()
        self.assertEqual((private / "index.html").read_bytes(), b"private page\n")
        self.assertEqual((private / ".last_generated").read_bytes(), b"private stamp\n")
        self.assertEqual((retained / "index.html").read_bytes(), PAGE)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.called.exists())

    def test_linked_acfs_ancestor_does_not_redirect_writes(self):
        retained = self.base / "retained-acfs"
        self.acfs.rename(retained)
        self.acfs.symlink_to(retained, target_is_directory=True)
        result = self.generate()
        self.assertEqual((retained / "dashboard/index.html").read_bytes(), PAGE)
        self.assertEqual((retained / "dashboard/.last_generated").read_bytes(), b"0\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.called.exists())

    def test_directory_at_page_target_is_not_treated_as_publication(self):
        self.index.rename(self.directory / "retained-page")
        self.index.mkdir()
        (self.index / "keep.txt").write_bytes(b"keep\n")
        result = self.generate()
        self.assertEqual({path.name for path in self.index.iterdir()}, {"keep.txt"})
        self.assertEqual(self.stamp.read_bytes(), b"0\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.called.exists())

    def test_linked_staging_directory_is_refused(self):
        private = self.base / "private-staging"
        private.mkdir()
        (self.directory / ".staging").symlink_to(private, target_is_directory=True)
        result = self.generate()
        self.assertEqual(list(private.iterdir()), [])
        self.assertEqual(self.index.read_bytes(), PAGE)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.called.exists())

    def test_failed_renderer_preserves_publication_and_retains_partial_output(self):
        result = self.generate(mode="fail")
        self.assertEqual(self.index.read_bytes(), PAGE)
        self.assertEqual(self.stamp.read_bytes(), b"0\n")
        self.assertNotEqual(result.returncode, 0)
        staging = self.directory / ".staging"
        self.assertTrue(staging.is_dir())
        partial = [path for path in staging.iterdir() if path.is_file() and path.read_bytes() == b"partial\n"]
        self.assertEqual(len(partial), 1)
        self.assertEqual(partial[0].stat().st_mode & 0o777, 0o600)
        self.assertIn(b".staging", result.stderr)
        self.assertFalse(any(self.directory.glob("index.html.tmp.*")))

    def test_invalid_or_future_freshness_is_rebuilt(self):
        values = [b"opaque\n", b"9" * 128 + b"\n", str(int(time.time()) + 600).encode() + b"\n"]
        for value in values:
            with self.subTest(value=value):
                self.index.write_bytes(PAGE)
                self.stamp.write_bytes(value)
                result = self.generate(force=False)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.index.read_bytes(), self.NEW_PAGE)
                self.assertLess(abs(int(self.stamp.read_bytes()) - int(time.time())), 5)

    def test_leading_zero_decimal_timestamp_reuses_recent_page(self):
        self.stamp.write_bytes(b"0" + str(int(time.time())).encode() + b"\n")
        before = self.stamp.read_bytes()
        result = self.generate(force=False, mode="fail")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.index.read_bytes(), PAGE)
        self.assertEqual(self.stamp.read_bytes(), before)
        self.assertFalse(self.called.exists())

    def test_recent_page_is_reused_without_an_installed_renderer(self):
        renderer = self.script.parent / "info.sh"
        renderer.rename(renderer.with_name("retained-info.sh"))
        self.stamp.write_text(str(int(time.time())) + "\n")
        result = self.generate(force=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.index.read_bytes(), PAGE)
        self.assertFalse(self.called.exists())

    def test_timestamp_fifo_is_refused_without_running_renderer(self):
        self.stamp.rename(self.directory / "retained-timestamp")
        os.mkfifo(self.stamp)
        result = self.generate()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.index.read_bytes(), PAGE)
        self.assertFalse(self.called.exists())

    def test_timestamp_changed_during_render_does_not_redirect_writes(self):
        private = self.base / "concurrent-private-stamp"
        private.write_bytes(b"private concurrent stamp\n")
        def change():
            self.stamp.rename(self.directory / "retained-timestamp")
            self.stamp.symlink_to(private)
        result = self.while_rendering(change)
        self.assertEqual(private.read_bytes(), b"private concurrent stamp\n")
        self.assertEqual(self.index.read_bytes(), PAGE)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.stamp.is_symlink())

    def test_parent_changed_during_render_does_not_redirect_writes(self):
        private = self.base / "concurrent-private-dashboard"
        private.mkdir()
        (private / "index.html").write_bytes(b"private concurrent page\n")
        (private / ".last_generated").write_bytes(b"private concurrent stamp\n")
        retained = self.base / "retained-running-dashboard"
        def change():
            staged = list(self.directory.rglob("index.html.tmp.*"))
            self.assertEqual(len(staged), 1)
            relative = staged[0].relative_to(self.directory)
            self.directory.rename(retained)
            self.directory.symlink_to(private, target_is_directory=True)
            forged = private / relative
            forged.parent.mkdir(parents=True, exist_ok=True)
            forged.write_bytes(b"forged concurrent page\n")
        result = self.while_rendering(change)
        self.assertEqual((private / "index.html").read_bytes(), b"private concurrent page\n")
        self.assertEqual((private / ".last_generated").read_bytes(), b"private concurrent stamp\n")
        self.assertEqual((retained / "index.html").read_bytes(), PAGE)
        self.assertNotEqual(result.returncode, 0)

    def test_staged_page_replaced_during_render_is_not_published(self):
        private = self.base / "private-stage-target"
        private.write_bytes(b"private stage data\n")
        def change():
            staged = list(self.directory.rglob("index.html.tmp.*"))
            self.assertEqual(len(staged), 1)
            staged[0].rename(staged[0].with_name("retained-render-output"))
            staged[0].symlink_to(private)
        result = self.while_rendering(change)
        self.assertEqual(private.read_bytes(), b"private stage data\n")
        self.assertEqual(self.index.read_bytes(), PAGE)
        self.assertEqual(self.stamp.read_bytes(), b"0\n")
        self.assertNotEqual(result.returncode, 0)

    def test_interrupted_timestamp_write_preserves_both_previous_files(self):
        import resource
        def limit():
            resource.setrlimit(resource.RLIMIT_FSIZE, (8, 8))
        self.env["ACFS_TEST_RENDER_PAGE"] = "x\n"
        result = self.generate(limit=limit)
        self.assertEqual(self.stamp.read_bytes(), b"0\n")
        self.assertEqual(self.index.read_bytes(), PAGE)
        self.assertNotEqual(result.returncode, 0)

    def test_missing_dashboard_directory_is_created_safely(self):
        self.directory.rename(self.base / "retained-initial-dashboard")
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.index.read_bytes(), self.NEW_PAGE)
        self.assertTrue(self.stamp.read_bytes().strip().isdigit())


if __name__ == "__main__":
    unittest.main()
