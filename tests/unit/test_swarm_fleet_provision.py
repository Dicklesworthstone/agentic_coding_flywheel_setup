#!/usr/bin/env python3
"""Real Git and unprivileged receiver tests; no hosted SSH or coding agents.

Repositories and journals are intentionally retained for inspection.
"""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/swarm-fleet-provision.py"
spec = importlib.util.spec_from_file_location("provision", SCRIPT)
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
fleet = p.load_fleet()


class Fixture:
    def __init__(self, fmt="sha1"):
        self.root = Path(tempfile.mkdtemp(prefix="acfs-provision-test-"))
        self.repo = self.root / "source"
        self.repo.mkdir(mode=0o700)
        self.home = self.root / "home"
        self.home.mkdir(mode=0o700)
        self.env = {**p.ENV, "HOME": str(self.home), "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "fixture@localhost",
                    "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "fixture@localhost"}
        self.git(self.repo, "init", "-q", "--initial-branch=main", "--object-format=" + fmt)
        (self.repo / "old.txt").write_text("original\n")
        (self.repo / "data.bin").write_bytes(bytes(range(256)) * 50)
        self.git(self.repo, "add", ".")
        self.git(self.repo, "commit", "-qm", "base")
        self.base = self.text(self.repo, "rev-parse", "HEAD")
        (self.repo / "old.txt").write_text("selected commit\n")
        (self.repo / "run.sh").write_text("#!/bin/sh\nexit 0\n")
        (self.repo / "run.sh").chmod(0o700)
        (self.repo / "relative-link").symlink_to("old.txt")
        self.git(self.repo, "add", ".")
        self.git(self.repo, "commit", "-qm", "candidate")
        self.commit = self.text(self.repo, "rev-parse", "HEAD")
        self.tree = self.text(self.repo, "rev-parse", "HEAD^{tree}")
        self.known, self.key = b"fixed-host-keys\n", b"fixed-private-key\n"
        self.state = self.root / "state"
        self.spec = {"schema": fleet.SPEC_SCHEMA, "hosts": []}
        for name in ("alpha", "beta"):
            self.spec["hosts"].append({"id": name, "host": name + ".invalid", "user": "worker", "port": 22,
                "request": {"repo": str(self.root / ("remote-" + name)), "session": name,
                            "receipt": str(self.root / (name + "-launch.json")),
                            "agents": [{"agent_name": name.title(), "agent_type": "codex"}],
                            "profile": "balanced", "workload": "standard", "accept_warnings": False}})
        self.calls = []

    def git(self, repo, *args, data=None, allowed=(0,)):
        result = subprocess.run(["/usr/bin/git", "-C", str(repo), *args], input=data,
                                env=self.env, capture_output=True, timeout=20)
        if result.returncode not in allowed:
            raise AssertionError((args, result.returncode, result.stderr))
        return result.stdout

    def text(self, repo, *args):
        return self.git(repo, *args).decode().strip()

    def invoke(self, host, request, pack=b""):
        self.calls.append((host["id"], request["mode"]))
        data = json.dumps(request, sort_keys=True, separators=(",", ":")).encode() + b"\n" + pack
        code = "RECEIVER_POLICY=" + repr(p.policy()) + "\n" + SCRIPT.read_text()
        result = subprocess.run(["/usr/bin/python3", "-I", "-c", code, "--receiver", "20"], input=data,
                                env=self.env, capture_output=True, timeout=25)
        value = p.decode(result.stdout)
        if result.returncode:
            raise p.Refused(value["code"])
        return value

    def run(self, approval=None, **options):
        args = {"fleet": fleet, "spec": self.spec, "repository": self.repo, "commit": self.commit,
                "known": self.known, "key": self.key, "state": self.state, "timeout": 90,
                "approval": approval, "invoke": self.invoke, **options}
        return p.execute(**args)

    def preview(self):
        report, code = self.run()
        if code != 0 or report["status"] != "preview":
            raise AssertionError(report)
        return report

    def apply(self):
        preview = self.preview()
        report, code = self.run(preview["plan_sha256"])
        if code != 0 or report["status"] != "provisioned":
            raise AssertionError(report)
        return report

    def files(self, root):
        return {str(path.relative_to(root)): ("link", os.readlink(path)) if path.is_symlink()
                else ("dir", path.stat().st_mode) if path.is_dir()
                else ("file", path.stat().st_mode, path.read_bytes()) for path in root.rglob("*")}


class ProvisionTests(unittest.TestCase):
    def setUp(self):
        self.assertNotEqual(os.geteuid(), 0)

    def test_preview_is_repeatable_and_never_creates_state_or_projects(self):
        fx = Fixture()
        before = fx.files(fx.root)
        first, second = fx.preview(), fx.preview()
        self.assertEqual(first, second)
        self.assertEqual(fx.calls, [("alpha", "preview"), ("beta", "preview")] * 2)
        self.assertEqual(fx.files(fx.root), before)
        self.assertFalse(first["writes_attempted"])

    def test_two_hosts_get_exact_full_history_modes_links_without_source_changes(self):
        for fmt in ("sha1", "sha256"):
            with self.subTest(fmt=fmt):
                fx = Fixture(fmt)
                fx.git(fx.repo, "remote", "add", "origin", "ssh://private.invalid/secret")
                fx.git(fx.repo, "tag", "not-copied")
                (fx.repo / "old.txt").write_text("uncommitted changes\n")
                (fx.repo / "secret").write_text("not tracked")
                before = fx.files(fx.repo)
                result = fx.apply()
                self.assertEqual(fx.files(fx.repo), before)
                self.assertEqual(fx.calls[-4:], [("alpha", "preview"), ("beta", "preview"),
                                                ("alpha", "create"), ("beta", "create")])
                for host in fx.spec["hosts"]:
                    repo = Path(host["request"]["repo"])
                    self.assertEqual(fx.text(repo, "rev-parse", "HEAD"), fx.commit)
                    self.assertEqual(fx.text(repo, "rev-parse", "HEAD^{tree}"), fx.tree)
                    self.assertEqual(fx.text(repo, "rev-list", "--count", "HEAD"), "2")
                    self.assertEqual(fx.text(repo, "rev-parse", "--is-shallow-repository"), "false")
                    self.assertEqual(fx.git(repo, "show", fx.base + ":old.txt"), b"original\n")
                    self.assertEqual((repo / "old.txt").read_text(), "selected commit\n")
                    self.assertEqual((repo / "data.bin").read_bytes(), bytes(range(256)) * 50)
                    self.assertTrue((repo / "run.sh").stat().st_mode & 0o111)
                    self.assertTrue((repo / "relative-link").is_symlink())
                    self.assertFalse((repo / "secret").exists())
                    self.assertFalse((repo / ".git/hooks").exists())
                    self.assertEqual(fx.git(repo, "remote"), b"")
                    self.assertEqual(fx.git(repo, "tag", "--list"), b"")
                    fx.git(repo, "fsck", "--strict")
                    request = p.request_for(result["plan"], host, "check", result["plan"]["contexts"][host["id"]])
                    before_check = fx.files(repo)
                    self.assertEqual(p.response_receipt(fx.invoke(host, request), request)["binding"]["artifact"]["commit"], fx.commit)
                    self.assertEqual(fx.files(repo), before_check)

    def test_existing_destination_blocks_all_hosts_before_state_or_remote_writes(self):
        fx = Fixture()
        occupied = Path(fx.spec["hosts"][1]["request"]["repo"])
        occupied.mkdir(mode=0o700)
        (occupied / "precious").write_bytes(b"never overwrite")
        before = fx.files(fx.root)
        report, code = fx.run("f" * 64)
        self.assertEqual((code, report["status"]), (1, "blocked"))
        self.assertEqual(report["errors"][0]["code"], "destination_already_exists")
        self.assertEqual(fx.files(fx.root), before)
        self.assertFalse(fx.state.exists())

    def test_head_can_advance_but_approval_cannot_change_selected_commit_or_trust(self):
        fx = Fixture()
        preview = fx.preview()
        (fx.repo / "future").write_text("do not transfer")
        fx.git(fx.repo, "add", "future")
        fx.git(fx.repo, "commit", "-qm", "future")
        newer = fx.text(fx.repo, "rev-parse", "HEAD")
        self.assertEqual(fx.preview()["plan_sha256"], preview["plan_sha256"])
        for changes in ({"commit": newer}, {"known": b"different keys"}, {"key": b"different identity"},
                        {"state": fx.root / "different-state"}):
            with self.subTest(changes=changes), self.assertRaisesRegex(p.Refused, "approval_mismatch"):
                fx.run(preview["plan_sha256"], **changes)
        self.assertFalse(fx.state.exists())
        result, code = fx.run(preview["plan_sha256"])
        self.assertEqual(code, 0, result)
        self.assertFalse((Path(fx.spec["hosts"][0]["request"]["repo"]) / "future").exists())

    def test_failed_transfer_stops_later_hosts_and_keeps_durable_attempt(self):
        fx = Fixture()
        preview = fx.preview()
        def failing(host, request, pack=b""):
            if request["mode"] == "create":
                raise OSError("simulated lost connection")
            return fx.invoke(host, request, pack)
        result, code = fx.run(preview["plan_sha256"], invoke=failing)
        self.assertEqual((code, result["status"]), (1, "partial"))
        self.assertEqual([h["status"] for h in result["hosts"]], ["unconfirmed", "not_attempted"])
        self.assertTrue((fx.state / "alpha.attempt.json").exists())
        self.assertFalse((fx.state / "alpha.result.json").exists())
        self.assertFalse((fx.state / "beta.attempt.json").exists())
        with self.assertRaises(fleet.Refused):
            fx.run(preview["plan_sha256"])

    def test_corrupt_pack_is_refused_before_destination_creation(self):
        fx = Fixture()
        preview = fx.preview()
        def corrupted(host, request, pack=b""):
            return fx.invoke(host, request, pack[:-1] + b"!" if pack else pack)
        result, code = fx.run(preview["plan_sha256"], invoke=corrupted)
        self.assertEqual((code, result["status"]), (1, "partial"))
        self.assertEqual(result["hosts"][0]["code"], "pack_transfer_mismatch")
        self.assertFalse(Path(fx.spec["hosts"][0]["request"]["repo"]).exists())

    def test_changed_parent_after_approval_is_refused_without_adoption(self):
        fx = Fixture()
        target_parent = fx.root / "target-parent"
        target_parent.mkdir(mode=0o700)
        for host in fx.spec["hosts"]:
            host["request"]["repo"] = str(target_parent / host["id"])
        preview = fx.preview()
        target_parent.rename(fx.root / "retained-parent")
        target_parent.mkdir(mode=0o700)
        with self.assertRaisesRegex(p.Refused, "approval_mismatch"):
            fx.run(preview["plan_sha256"])
        self.assertFalse(fx.state.exists())

    def test_source_instructions_and_hooks_are_not_executed_or_copied(self):
        fx = Fixture()
        marker = fx.root / "HOOK_RAN"
        hook = fx.repo / ".git/hooks/post-checkout"
        hook.write_text("#!/bin/sh\ntouch " + str(marker) + "\n")
        hook.chmod(0o700)
        fx.git(fx.repo, "config", "core.hooksPath", str(hook.parent))
        fx.git(fx.repo, "config", "filter.evil.smudge", "touch " + str(marker))
        (fx.repo / ".gitattributes").write_text("old.txt filter=evil export-subst\nrun.sh export-ignore\n")
        fx.git(fx.repo, "add", ".gitattributes")
        fx.git(fx.repo, "commit", "-qm", "attributes")
        fx.commit = fx.text(fx.repo, "rev-parse", "HEAD")
        fx.apply()
        self.assertFalse(marker.exists())
        for host in fx.spec["hosts"]:
            repo = Path(host["request"]["repo"])
            self.assertTrue((repo / "run.sh").exists())
            self.assertEqual((repo / "old.txt").read_text(), "selected commit\n")
            self.assertNotIn(b"evil", (repo / ".git/config").read_bytes())

    def test_noncommit_shallow_partial_or_borrowed_sources_refuse_before_transport(self):
        fx = Fixture()
        with self.assertRaises(p.Refused):
            fx.run(commit="HEAD")
        with self.assertRaises(p.Refused):
            fx.run(commit=fx.tree)
        fx.git(fx.repo, "config", "remote.origin.promisor", "true")
        with self.assertRaisesRegex(p.Refused, "partial_repository_refused"):
            fx.run()
        self.assertEqual(fx.calls, [])
        fx = Fixture()
        (fx.repo / ".git/shallow").write_text(fx.base + "\n")
        with self.assertRaisesRegex(p.Refused, "shallow_repository_refused"):
            fx.run()
        self.assertEqual(fx.calls, [])
        fx = Fixture()
        (fx.repo / ".git/objects/info/alternates").write_text("/nonexistent\n")
        with self.assertRaisesRegex(p.Refused, "borrowed_objects_refused"):
            fx.run()
        self.assertEqual(fx.calls, [])

    def test_transport_keeps_strict_options_and_sends_data_only_over_stdin(self):
        fx = Fixture()
        captured = []
        def fake_capture(argv, deadline, data=b"", env=None, limit=p.LIMIT):
            captured.append((argv, data, env))
            return p.encoded({"test": True})
        source, artifact, pack = p.source_artifact(fx.repo, fx.commit, 90)
        plan = {"artifact": artifact, "policy": p.policy()}
        request = p.request_for(plan, fx.spec["hosts"][0], "preview")
        with patch.object(p, "capture", fake_capture):
            # Only the injected capture runs; the shared SSH argv/trust builder
            # uses an existing sentinel because OpenSSH is absent in this lab.
            result = p.transport(fleet, fx.known, fx.key, 90, ssh="/usr/bin/true")(fx.spec["hosts"][0], request, pack)
        self.assertEqual(result, {"test": True})
        argv, raw, env = captured[0]
        self.assertNotIn("-n", argv[:5])
        self.assertIn("StrictHostKeyChecking=yes", argv)
        self.assertIn("ForwardAgent=no", argv)
        self.assertIn("ProxyCommand=none", argv)
        self.assertIn("IdentitiesOnly=yes", argv)
        self.assertEqual(raw.partition(b"\n")[2], pack)
        self.assertEqual(p.decode(raw.partition(b"\n")[0]), request)
        self.assertNotIn(fx.commit, argv[-1])
        self.assertNotIn("HOME", env)

    def test_capture_deadline_output_limits_and_receiver_regular_file_input(self):
        deadline = time.monotonic() + 1
        with self.assertRaisesRegex(p.Refused, "operation_timed_out"):
            p.capture(["/usr/bin/python3", "-c", "import time;time.sleep(10)"], deadline)
        with self.assertRaisesRegex(p.Refused, "process_output_limit"):
            p.capture(["/usr/bin/python3", "-c", "print('x'*10000)"], time.monotonic() + 10, limit=100)
        fx = Fixture()
        _, artifact, _ = p.source_artifact(fx.repo, fx.commit, 90)
        request = p.request_for({"artifact": artifact, "policy": p.policy()}, fx.spec["hosts"][0], "preview")
        raw = json.dumps(request).encode() + b"\n"
        result = p.capture([sys.executable, "-I", str(SCRIPT), "--receiver", "10"], time.monotonic() + 10, raw)
        self.assertEqual(p.decode(result)["status"], "available")

    def test_merge_history_is_independent_after_source_is_no_longer_available(self):
        fx = Fixture()
        first = fx.commit
        fx.git(fx.repo, "checkout", "-qb", "side", fx.base)
        (fx.repo / "side.txt").write_text("side contribution\n")
        fx.git(fx.repo, "add", "side.txt")
        fx.git(fx.repo, "commit", "-qm", "side")
        second = fx.text(fx.repo, "rev-parse", "HEAD")
        fx.git(fx.repo, "checkout", "main")
        fx.git(fx.repo, "merge", "--no-ff", "-m", "combined", "side")
        fx.commit = fx.text(fx.repo, "rev-parse", "HEAD")
        fx.apply()
        fx.repo.rename(fx.root / "retained-source")
        for host in fx.spec["hosts"]:
            repo = Path(host["request"]["repo"])
            self.assertEqual(fx.text(repo, "show", "-s", "--format=%P", "HEAD").split(), [first, second])
            self.assertEqual((repo / "side.txt").read_text(), "side contribution\n")
            fx.git(repo, "fsck", "--strict")
            self.assertFalse((repo / ".git/objects/info/alternates").exists())

    def test_submodule_source_is_refused_before_any_host_contact(self):
        fx = Fixture()
        fx.git(fx.repo, "update-index", "--add", "--cacheinfo", "160000," + fx.commit + ",sub")
        fx.git(fx.repo, "commit", "-qm", "submodule")
        fx.commit = fx.text(fx.repo, "rev-parse", "HEAD")
        with self.assertRaisesRegex(p.Refused, "submodule_or_special_entry_refused"):
            fx.run()
        self.assertEqual(fx.calls, [])
        self.assertFalse(fx.state.exists())

    def test_journal_change_during_remote_create_prevents_success_record_and_later_hosts(self):
        fx = Fixture()
        preview = fx.preview()
        def changed(host, request, pack=b""):
            value = fx.invoke(host, request, pack)
            if request["mode"] == "create":
                intent = fx.state / "intent.json"
                intent.write_bytes(intent.read_bytes() + b"\n")
            return value
        with self.assertRaisesRegex(p.Refused, "state_changed"):
            fx.run(preview["plan_sha256"], invoke=changed)
        self.assertTrue((Path(fx.spec["hosts"][0]["request"]["repo"]) / ".git/acfs-provision.json").exists())
        self.assertFalse((fx.state / "alpha.result.json").exists())
        self.assertFalse(Path(fx.spec["hosts"][1]["request"]["repo"]).exists())


if __name__ == "__main__":
    if os.geteuid() == 0:
        os.setgroups([])
        os.setgid(65534)
        os.setuid(65534)
        os.execv(sys.executable, [sys.executable, "-B", __file__, *sys.argv[1:]])
    unittest.main()
