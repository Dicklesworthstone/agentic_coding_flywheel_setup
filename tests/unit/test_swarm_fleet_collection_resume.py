#!/usr/bin/env python3
"""Resume real interrupted Git collections; retain fixtures and original evidence."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
_spec = importlib.util.spec_from_file_location("integration_fixture", Path(__file__).with_name("test_swarm_fleet_integrate.py"))
support = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(support)
collect, fleet = support.collect, support.collect.fleet


class Fixture:
    """Real repositories/remote program; native-agent admission is a fixture."""

    def __init__(self, fmt="sha1", unchanged=()):
        self.git = support.Fixture(fmt)
        self.root, self.out = self.git.root, self.git.collection
        self.launch = self.root / "launch"
        self.known, self.key = b"fixture-host-key\n", b"fixture-private-key\n"
        self.hosts, self.repos, self.heads = [], {}, {}
        for name in ("alpha", "beta"):
            head = self.git.commit(name, [self.git.base], {name + ".txt": ("100644", name.encode() + b"\n")})
            repo = self.root / ("remote-" + name)
            self.git.git(self.git.source, "worktree", "add", "--detach", str(repo), head)
            self.repos[name], self.heads[name] = repo, head
            self.hosts.append({"id": name, "host": name + ".invalid", "user": "worker", "port": 22,
                "request": {"repo": str(repo), "session": name, "receipt": "/home/worker/" + name + ".json",
                            "agents": [{"agent_name": name.title(), "agent_type": "codex"}],
                            "profile": "balanced", "workload": "standard", "accept_warnings": False}})
        launch = fleet.build_plan({"schema": fleet.SPEC_SCHEMA, "hosts": self.hosts}, self.known, self.key, self.launch, 90)
        result, code = fleet.execute(launch, "launch", collect.digest(collect.encoded(launch)), self.native)
        if code:
            raise AssertionError(result)
        self.selection = {"schema": collect.SPEC_SCHEMA,
                          "hosts": [{"id": h["id"], "base_commit": self.heads[h["id"]] if h["id"] in unchanged else self.git.base}
                                    for h in self.hosts]}
        self.calls = []
        self.original, code = self.collect()
        if code:
            raise AssertionError(self.original)
        self.approval = self.original["plan_sha256"]
        self.calls.clear()

    @staticmethod
    def native(host, mode):
        request = host["request"]
        value = {"schema": fleet.NATIVE_SCHEMA, "request": request, "work_dispatched": False,
                 "authentication_verified": False, "agent_mail_registered": False,
                 "review_sha256": fleet.native_hash(request), "starts_agents": mode == "launch"}
        if mode == "preview":
            value.update(status="preview", admission={"status": "pass", "recommendation": "launch",
                         "safe_agents": 2, "recommended_agents": 2})
        else:
            value.update(status="ready", targets=[{"slot": 1, **request["agents"][0], "pane": "%3", "pane_pid": "301",
                         "server_pid": "300", "session_id": "$2", "session_created": "1780000000"}])
        return 0, collect.encoded(value)

    def invoke(self, host, base, mode, snapshot=None):
        self.calls.append((host["id"], mode))
        result = subprocess.run(["/bin/bash", "--noprofile", "--norc", "-p", "-c",
                                 collect.remote_command(host, base, mode, snapshot, 10)],
                                env=self.git.env, capture_output=True, timeout=20)
        return result.returncode, result.stdout

    def options(self, **kwargs):
        return {"launch_path": self.launch, "selection": self.selection, "known": self.known, "identity": self.key,
                "output_dir": self.out, "timeout": 90, "invoke": self.invoke, **kwargs}

    def collect(self, approval=None, **kwargs):
        return collect.execute(**self.options(approval=approval, **kwargs))

    def resume(self, accepted=None, **kwargs):
        return collect.resume_collection(**self.options(approval=self.approval, resume_approval=accepted, **kwargs))

    def partial(self, fail="beta"):
        def interrupt(host, base, mode, snapshot=None):
            if host["id"] == fail and mode == "collect":
                return 255, b""
            return self.invoke(host, base, mode, snapshot)
        result, code = self.collect(self.approval, invoke=interrupt)
        if code != 1 or result["status"] != "partial":
            raise AssertionError(result)
        self.calls.clear()
        return result

    def cli(self, *args):
        paths = {}
        for name, raw in (("known", self.known), ("key", self.key), ("selection", collect.encoded(self.selection))):
            path = self.root / (name + ".input")
            if not path.exists():
                path.write_bytes(raw)
                path.chmod(0o600)
            paths[name] = str(path)
        return subprocess.run([sys.executable, "-I", "-B", collect.__file__,
                               "--launch-state", str(self.launch), "--bases", paths["selection"],
                               "--known-hosts", paths["known"], "--identity-file", paths["key"],
                               "--output-dir", str(self.out), *args],
                              env=self.git.env, capture_output=True, text=True, timeout=20)


class ResumeTests(unittest.TestCase):
    def setUp(self):
        self.assertNotEqual(os.geteuid(), 0, "Exercise actual unprivileged production behavior")

    def test_partial_preview_is_offline_repeatable_and_read_only(self):
        fx = Fixture()
        fx.partial()
        before = fx.git.contents(fx.root)
        with patch.object(collect, "observe", side_effect=AssertionError("preview opened transport")):
            first, code = fx.resume()
            second, code2 = fx.resume()
        self.assertEqual((code, code2), (0, 0))
        self.assertEqual(first, second)
        self.assertEqual(first["status"], "resume_preview")
        self.assertEqual(first["resume_plan"]["pending_hosts"], ["beta"])
        self.assertEqual([a["id"] for a in first["resume_plan"]["artifacts"]], ["alpha"])
        self.assertFalse(first["network_access"])
        self.assertFalse(first["collection_resume_writes_started"])
        self.assertFalse(first["collection_provenance_verified"])
        self.assertEqual(fx.git.contents(fx.root), before)

    def test_resume_contacts_only_missing_host_and_preserves_exact_saved_bytes(self):
        fx = Fixture()
        fx.partial()
        saved = fx.out / "alpha.bundle"
        before, inode = saved.read_bytes(), saved.stat().st_ino
        repo_before = fx.git.contents(fx.git.source)
        preview, _ = fx.resume()
        result, code = fx.resume(preview["resume_plan_sha256"])
        self.assertEqual(code, 0, result)
        self.assertEqual(result["status"], "collected")
        self.assertEqual(fx.calls, [("beta", "collect")])
        self.assertEqual(saved.read_bytes(), before)
        self.assertEqual(saved.stat().st_ino, inode)
        self.assertEqual(fx.git.contents(fx.git.source), repo_before)
        self.assertEqual(collect.verify(fx.out)["status"], "verified")
        self.assertEqual([a["id"] for a in result["artifacts"]], ["alpha", "beta"])

    def test_recovered_collection_supports_strict_import_and_combined_candidate(self):
        for fmt in ("sha1", "sha256"):
            with self.subTest(fmt=fmt):
                fx = Fixture(fmt)
                fx.partial()
                preview, _ = fx.resume()
                self.assertEqual(fx.resume(preview["resume_plan_sha256"])[1], 0)
                before = fx.git.contents(fx.git.repo)
                imported = collect.import_collection(fx.out, fx.git.repo, "recovered", [], 90)
                imported = collect.import_collection(fx.out, fx.git.repo, "recovered", [], 90, imported["plan_sha256"])
                self.assertEqual(imported["status"], "imported")
                merged = collect.integrate_collection(fx.out, fx.git.repo, fx.git.base, "recovered", [], 90)
                applied = collect.integrate_collection(fx.out, fx.git.repo, fx.git.base, "recovered", [], 90,
                                                       merged["plan_sha256"])
                self.assertEqual(applied["status"], "integrated")
                head = applied["plan"]["result"]["candidate_commit"]
                for name in ("alpha", "beta"):
                    self.assertEqual(fx.git.git(fx.git.repo, "show", head + ":" + name + ".txt"), name.encode() + b"\n")
                for path, raw in before.items():
                    self.assertEqual(fx.git.contents(fx.git.repo)[path], raw)

    def test_completed_host_can_advance_without_changing_collected_range(self):
        fx = Fixture()
        fx.partial()
        new = fx.git.commit("later", [fx.heads["alpha"]], {"later.txt": ("100644", b"not approved\n")})
        fx.git.git(fx.repos["alpha"], "update-ref", "HEAD", new)
        preview, _ = fx.resume()
        result, code = fx.resume(preview["resume_plan_sha256"])
        self.assertEqual(code, 0, result)
        self.assertEqual(fx.calls, [("beta", "collect")])
        self.assertEqual(result["plan"]["hosts"][0]["snapshot"]["head_commit"], fx.heads["alpha"])

    def test_changed_pending_head_refuses_without_writing_or_replacing_artifacts(self):
        fx = Fixture()
        fx.partial()
        preview, _ = fx.resume()
        new = fx.git.commit("later", [fx.heads["beta"]], {"later.txt": ("100644", b"not approved\n")})
        fx.git.git(fx.repos["beta"], "update-ref", "HEAD", new)
        before = fx.git.contents(fx.out)
        result, code = fx.resume(preview["resume_plan_sha256"])
        self.assertEqual((code, result["status"]), (1, "partial"))
        self.assertEqual(fx.git.contents(fx.out), before)
        self.assertFalse(result["collection_resume_writes_started"])
        self.assertFalse((fx.out / "manifest.json").exists())

    def test_both_approvals_are_required_and_not_interchangeable(self):
        fx = Fixture()
        fx.partial()
        before = fx.git.contents(fx.out)
        preview, _ = fx.resume()
        for original in (None, "f" * 64, preview["resume_plan_sha256"]):
            with self.subTest(original=original), self.assertRaises(fleet.Refused):
                collect.resume_collection(**fx.options(approval=original))
        with self.assertRaisesRegex(fleet.Refused, "collection_resume_approval_mismatch"):
            fx.resume(fx.approval)
        self.assertEqual(fx.calls, [])
        self.assertEqual(fx.git.contents(fx.out), before)

    def test_changed_selection_trust_timeout_and_launch_evidence_refuse_offline(self):
        fx = Fixture()
        fx.partial()
        for options in ({"selection": {"schema": collect.SPEC_SCHEMA, "hosts": fx.selection["hosts"][:1]}},
                        {"timeout": 91}, {"known": b"other host key"}, {"identity": b"other key"}):
            with self.subTest(options=options), self.assertRaises(fleet.Refused):
                fx.resume(**options)
        result = next(p for p in fx.launch.iterdir() if p.name != "intent.json")
        raw = result.read_bytes()
        result.write_bytes(raw + b"\n")  # Parsed meaning unchanged, exact evidence changed.
        with self.assertRaises(fleet.Refused):
            fx.resume()
        self.assertEqual(fx.calls, [])

    def test_complete_collection_is_a_verified_offline_noop(self):
        fx = Fixture()
        result, code = fx.collect(fx.approval)
        self.assertEqual(code, 0, result)
        fx.calls.clear()
        before = fx.git.contents(fx.out)
        with patch.object(collect, "observe", side_effect=AssertionError("completed collection contacted host")):
            preview, _ = fx.resume()
            report, code = fx.resume(preview["resume_plan_sha256"])
        self.assertEqual((code, report["status"]), (0, "verified"))
        self.assertFalse(report["collection_resume_writes_started"])
        self.assertEqual(fx.git.contents(fx.out), before)

    def test_absent_bundle_for_approved_unchanged_range_requires_no_remote_read(self):
        fx = Fixture(unchanged=("alpha", "beta"))
        fx.partial(fail="alpha")
        before = fx.git.contents(fx.out)
        with patch.object(collect, "observe", side_effect=AssertionError("empty history requested")):
            preview, _ = fx.resume()
            self.assertEqual(preview["resume_plan"]["pending_hosts"], [])
            result, code = fx.resume(preview["resume_plan_sha256"])
        self.assertEqual((code, result["status"]), (0, "collected"))
        self.assertFalse(result["network_access"])
        self.assertEqual(collect.verify(fx.out)["artifacts"], result["artifacts"])
        self.assertEqual(set(fx.git.contents(fx.out)), set(before) | {"manifest.json"})
        self.assertTrue(all(a["file"] is None for a in result["artifacts"]))

    def test_torn_bundle_and_corrupt_final_manifest_are_not_overwritten(self):
        fx = Fixture()
        fx.partial()
        path = fx.out / "alpha.bundle"
        path.write_bytes(path.read_bytes()[:-1])
        before = fx.git.contents(fx.out)
        with self.assertRaises(fleet.Refused):
            fx.resume()
        self.assertEqual(fx.git.contents(fx.out), before)
        fx = Fixture()
        fx.collect(fx.approval)
        (fx.out / "manifest.json").write_bytes(b"{incomplete")
        before = fx.git.contents(fx.out)
        with self.assertRaises(fleet.Refused):
            fx.resume()
        self.assertEqual(fx.git.contents(fx.out), before)

    def test_nonprefix_files_and_unexpected_members_fail_closed(self):
        fx = Fixture()
        fx.partial(fail="alpha")
        snap = fx.original["plan"]["hosts"][1]["snapshot"]
        _, bundle = collect.observe(fx.hosts[1], fx.git.base, "collect", fx.invoke, snap)
        with fleet.directory_fd(fx.out, private=True) as fd:
            collect.publish_bundle(fd, "beta.bundle", bundle)
        with self.assertRaisesRegex(fleet.Refused, "nonprefix_collection_artifacts"):
            fx.resume()
        fx = Fixture()
        fx.partial()
        extra = fx.out / "unexpected"
        extra.write_bytes(b"retain this")
        extra.chmod(0o600)
        with self.assertRaisesRegex(fleet.Refused, "unexpected_collection_member"):
            fx.resume()
        self.assertEqual(extra.read_bytes(), b"retain this")

    def test_saved_bundle_changes_during_remote_read_stop_before_new_publication(self):
        fx = Fixture()
        fx.partial()
        preview, _ = fx.resume()
        def changed(host, base, mode, snapshot=None):
            response = fx.invoke(host, base, mode, snapshot)
            path = fx.out / "alpha.bundle"
            path.write_bytes(path.read_bytes() + b"changed")
            return response
        with self.assertRaisesRegex(fleet.Refused, "collection_changed_during_recovery"):
            fx.resume(preview["resume_plan_sha256"], invoke=changed)
        self.assertFalse((fx.out / "beta.bundle").exists())
        self.assertFalse((fx.out / "manifest.json").exists())

    def test_cli_resume_preview_and_noop_are_offline_and_require_explicit_flags(self):
        fx = Fixture(unchanged=("alpha", "beta"))
        fx.partial(fail="alpha")
        preview = fx.cli("--resume", "--accept-plan", fx.approval)
        self.assertEqual(preview.returncode, 0, preview.stdout + preview.stderr)
        report = collect.decode(preview.stdout.encode())
        before = fx.git.contents(fx.out)
        for args in (("--resume",), ("--accept-resume", report["resume_plan_sha256"]),
                     ("--resume", "--collect", "--accept-plan", fx.approval)):
            refused = fx.cli(*args)
            self.assertEqual(refused.returncode, 2, refused.stdout + refused.stderr)
            self.assertEqual(fx.git.contents(fx.out), before)
        applied = fx.cli("--resume", "--accept-plan", fx.approval, "--accept-resume", report["resume_plan_sha256"])
        self.assertEqual(applied.returncode, 0, applied.stdout + applied.stderr)
        self.assertEqual(collect.decode(applied.stdout.encode())["status"], "collected")
        check = fx.cli("--resume", "--accept-plan", fx.approval)
        self.assertEqual(check.returncode, 0, check.stdout + check.stderr)
        self.assertEqual(collect.decode(check.stdout.encode())["status"], "verified")


if __name__ == "__main__":
    if os.geteuid() == 0:
        os.setgroups([])
        os.setgid(65534)
        os.setuid(65534)
        os.execv(sys.executable, [sys.executable, "-B", __file__, *sys.argv[1:]])
    unittest.main()
