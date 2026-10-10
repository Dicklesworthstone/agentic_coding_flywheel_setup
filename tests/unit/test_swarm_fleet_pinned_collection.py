#!/usr/bin/env python3
"""Collect exact historical commits with real Git while agent HEADs keep moving."""
import copy
from contextlib import redirect_stdout
import importlib.util
import io
import json
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
    def __init__(self, fmt="sha1", *, pinned=True):
        self.git = support.Fixture(fmt)
        self.root, self.out = self.git.root, self.git.collection
        self.launch = self.root / "launch"
        self.known, self.key = b"fixture-host-key\n", b"fixture-private-key\n"
        self.hosts, self.repos, self.heads = [], {}, {}
        self.calls = []
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
        self.selection = {"schema": collect.PINNED_SPEC_SCHEMA if pinned else collect.SPEC_SCHEMA,
                          "hosts": [{"id": h["id"], "base_commit": self.git.base,
                                     **({"head_commit": self.heads[h["id"]]} if pinned else {})} for h in self.hosts]}

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
                                 collect.remote_command(host, base, mode, snapshot, 15)],
                                env=self.git.env, capture_output=True, timeout=20)
        return result.returncode, result.stdout

    def options(self, **kwargs):
        return {"launch_path": self.launch, "selection": self.selection, "known": self.known, "identity": self.key,
                "output_dir": self.out, "timeout": 90, "invoke": self.invoke, **kwargs}

    def run(self, approval=None, **kwargs):
        return collect.execute(**self.options(approval=approval, **kwargs))

    def resume(self, original, accepted=None, **kwargs):
        return collect.resume_collection(**self.options(approval=original, resume_approval=accepted, **kwargs))

    def advance(self, name):
        head = self.git.commit("later-" + name, [self.heads[name]], {"future-" + name: ("100644", b"NOT_APPROVED\n")})
        self.git.git(self.repos[name], "update-ref", "HEAD", head)
        return head


class PinnedCollectionTests(unittest.TestCase):
    def setUp(self):
        # Fixtures inherit the umask; a login user's 0002 makes them group-writable.
        self.addCleanup(os.umask, os.umask(0o022))
        self.assertNotEqual(os.geteuid(), 0, "Exercise actual unprivileged production behavior")

    def preview(self, fx):
        report, code = fx.run()
        self.assertEqual(code, 0, report)
        self.assertEqual(report["revision_mode"], "pinned")
        return report

    def collect(self, fx):
        preview = self.preview(fx)
        report, code = fx.run(preview["plan_sha256"])
        self.assertEqual((code, report["status"]), (0, "collected"), report)
        return report

    def test_pinned_preview_stays_identical_after_both_heads_advance(self):
        fx = Fixture()
        first = self.preview(fx)
        for name in fx.heads:
            fx.advance(name)
        before = fx.git.contents(fx.root)
        second = self.preview(fx)
        self.assertEqual(first, second)
        self.assertEqual(fx.git.contents(fx.root), before)
        self.assertFalse(fx.out.exists())

    def test_live_head_approval_still_refuses_moving_head_before_writes(self):
        fx = Fixture(pinned=False)
        preview, code = fx.run()
        self.assertEqual(code, 0, preview)
        fx.advance("beta")
        with self.assertRaisesRegex(fleet.Refused, "collection_approval_mismatch"):
            fx.run(preview["plan_sha256"])
        self.assertFalse(fx.out.exists())

    def test_sha1_and_sha256_round_trip_only_reviewed_history_while_heads_move(self):
        for fmt in ("sha1", "sha256"):
            with self.subTest(fmt=fmt):
                fx = Fixture(fmt)
                preview = self.preview(fx)
                future = [fx.advance(name) for name in fx.heads]
                # Committed, staged, unstaged and untracked future work is not
                # part of the explicitly approved historical range.
                dirty = fx.repos["alpha"] / "alpha.txt"
                dirty.write_bytes(b"staged secret\n")
                fx.git.git(fx.repos["alpha"], "add", "alpha.txt")
                dirty.write_bytes(b"unstaged secret\n")
                (fx.repos["alpha"] / "untracked").write_bytes(b"untracked secret\n")
                source_before = fx.git.contents(fx.git.source)
                work_before = {name: fx.git.contents(repo) for name, repo in fx.repos.items()}
                report, code = fx.run(preview["plan_sha256"])
                self.assertEqual((code, report["status"]), (0, "collected"), report)
                self.assertEqual(fx.git.contents(fx.git.source), source_before)
                for name, repo in fx.repos.items():
                    self.assertEqual(fx.git.contents(repo), work_before[name])
                    raw = (fx.out / (name + ".bundle")).read_bytes()
                    header = raw.partition(b"\n\n")[0]
                    self.assertIn((fx.heads[name] + " HEAD").encode(), header)
                    self.assertIn(("-" + fx.git.base + " reviewed base").encode(), header)
                    fx.git.git(fx.git.repo, "bundle", "verify", str(fx.out / (name + ".bundle")))
                self.assertEqual(collect.verify(fx.out)["status"], "verified")
                imported = collect.import_collection(fx.out, fx.git.repo, "pinned", [], 90)
                self.assertEqual(collect.import_collection(fx.out, fx.git.repo, "pinned", [], 90,
                                 imported["plan_sha256"])["status"], "imported")
                merged = collect.integrate_collection(fx.out, fx.git.repo, fx.git.base, "pinned", [], 90)
                applied = collect.integrate_collection(fx.out, fx.git.repo, fx.git.base, "pinned", [], 90,
                                                       merged["plan_sha256"])
                self.assertEqual(applied["status"], "integrated")
                candidate = applied["plan"]["result"]["candidate_commit"]
                for name, head in fx.heads.items():
                    self.assertEqual(fx.git.git(fx.git.repo, "show", candidate + ":" + name + ".txt"), name.encode() + b"\n")
                    fx.git.git(fx.git.repo, "merge-base", "--is-ancestor", head, candidate)
                for head in future:
                    fx.git.git(fx.git.repo, "cat-file", "-e", head, allowed=(1, 128))

    def test_collection_ignores_a_head_change_between_preview_and_pack(self):
        fx = Fixture()
        preview = self.preview(fx)
        changed = set()
        def advancing(host, base, mode, snapshot=None):
            if mode == "collect_pinned":
                fx.advance(host["id"])
                changed.add(host["id"])
            return fx.invoke(host, base, mode, snapshot)
        report, code = fx.run(preview["plan_sha256"], invoke=advancing)
        self.assertEqual((code, report["status"]), (0, "collected"), report)
        self.assertEqual(changed, set(fx.heads))
        self.assertEqual([e["snapshot"]["head_commit"] for e in report["plan"]["hosts"]], list(fx.heads.values()))

    def test_explicit_commit_does_not_need_any_current_head_commit(self):
        fx = Fixture()
        for repo in fx.repos.values():
            fx.git.git(repo, "symbolic-ref", "HEAD", "refs/heads/unborn-agent-work")
        before = fx.git.contents(fx.git.source)
        report = self.collect(fx)
        self.assertEqual(report["revision_mode"], "pinned")
        self.assertEqual(fx.git.contents(fx.git.source), before)

    def test_merge_with_several_boundary_ancestors_verifies_from_only_base_history(self):
        for fmt in ("sha1", "sha256"):
            with self.subTest(fmt=fmt):
                fx = Fixture(fmt)
                left = fx.git.commit("left", [fx.git.base], {"left": ("100644", b"left\n")})
                base = fx.git.commit("advanced-base", [left], {"base-only": ("100644", b"base\n")})
                side = fx.git.commit("side", [fx.git.base], {"side": ("100644", b"side\n")})
                head = fx.git.commit("merged", [base, side], {"side": ("100644", b"side\n")})
                fx.selection["hosts"][0].update(base_commit=base, head_commit=head)
                boundaries = fx.git.text(fx.git.source, "rev-list", "--boundary", head, "^" + base)
                self.assertGreaterEqual(sum(s.startswith("-") for s in boundaries.splitlines()), 2)
                pack = fx.git.git(fx.git.source, "pack-objects", "--stdout", "--revs", data=(base + "\n").encode())
                fx.git.git(fx.git.repo, "index-pack", "--stdin", data=pack)
                self.collect(fx)
                fx.git.git(fx.git.repo, "bundle", "verify", str(fx.out / "alpha.bundle"))
                preview = collect.import_collection(fx.out, fx.git.repo, "merge", [], 90)
                collect.import_collection(fx.out, fx.git.repo, "merge", [], 90, preview["plan_sha256"])
                self.assertEqual(fx.git.text(fx.git.repo, "rev-list", "--parents", "-n", "1", head), head + " " + base + " " + side)
                fx.git.git(fx.git.repo, "fsck", "--strict", "--no-reflogs", head)

    def test_binary_modes_symlink_deletion_and_thin_pack_materialize_exactly(self):
        fx = Fixture()
        binary = bytes(range(256)) * 2048
        base = fx.git.commit("binary-base", [fx.git.base], {"payload": ("100644", binary), "obsolete": ("100644", b"old")})
        changed = binary[:90000] + b"edited payload\x00" + binary[90015:]
        head = fx.git.commit("binary-tip", [base], {"payload": ("100644", changed), "run": ("100755", b"#!/bin/sh\nexit 0\n"),
                                                    "link": ("120000", b"payload"), "obsolete": None})
        fx.selection["hosts"][0].update(base_commit=base, head_commit=head)
        pack = fx.git.git(fx.git.source, "pack-objects", "--stdout", "--revs", data=(base + "\n").encode())
        fx.git.git(fx.git.repo, "index-pack", "--stdin", data=pack)
        self.collect(fx)
        imported = collect.import_collection(fx.out, fx.git.repo, "binary", ["alpha"], 90)
        collect.import_collection(fx.out, fx.git.repo, "binary", ["alpha"], 90, imported["plan_sha256"])
        self.assertEqual(fx.git.git(fx.git.repo, "show", head + ":payload"), changed)
        self.assertIn(b"100755", fx.git.git(fx.git.repo, "ls-tree", head, "run"))
        self.assertIn(b"120000", fx.git.git(fx.git.repo, "ls-tree", head, "link"))
        self.assertEqual(fx.git.git(fx.git.repo, "ls-tree", head, "obsolete"), b"")

    def test_empty_pinned_range_is_explicit_even_after_remote_head_advances(self):
        fx = Fixture()
        for item in fx.selection["hosts"]:
            item["base_commit"] = item["head_commit"]
        for name in fx.heads:
            fx.advance(name)
        report = self.collect(fx)
        self.assertTrue(all(a["file"] is None and a["bytes"] == 0 for a in report["artifacts"]))
        self.assertEqual(set(os.listdir(fx.out)), {"intent.json", "manifest.json"})

    def test_live_and_pinned_approvals_are_not_interchangeable(self):
        fx = Fixture(pinned=False)
        live, code = fx.run()
        self.assertEqual(code, 0, live)
        fx.selection = {"schema": collect.PINNED_SPEC_SCHEMA,
                        "hosts": [{**item, "head_commit": fx.heads[item["id"]]} for item in fx.selection["hosts"]]}
        pinned = self.preview(fx)
        self.assertEqual(live["plan"]["hosts"], pinned["plan"]["hosts"])
        self.assertNotEqual(live["plan_sha256"], pinned["plan_sha256"])
        with self.assertRaisesRegex(fleet.Refused, "collection_approval_mismatch"):
            fx.run(live["plan_sha256"])
        self.assertFalse(fx.out.exists())

    def test_invalid_selection_ref_expressions_and_partial_pins_refuse_before_transport(self):
        fx = Fixture()
        original = copy.deepcopy(fx.selection)
        selections = []
        for value in ("HEAD", fx.heads["alpha"][:12], fx.heads["alpha"].upper(), "f" * 64, None, True):
            selection = copy.deepcopy(original)
            selection["hosts"][0]["head_commit"] = value
            selections.append(selection)
        selections += [{"schema": collect.PINNED_SPEC_SCHEMA, "hosts": [{"id": "alpha", "base_commit": fx.git.base}]},
                       {"schema": collect.SPEC_SCHEMA, "hosts": original["hosts"]}]
        for selection in selections:
            with self.subTest(selection=selection), self.assertRaises(fleet.Refused):
                fx.run(selection=selection)
        self.assertEqual(fx.calls, [])
        self.assertFalse(fx.out.exists())

    def test_missing_noncommit_and_nonancestor_pins_are_remote_refusals(self):
        fx = Fixture()
        tree = fx.git.text(fx.git.source, "rev-parse", fx.heads["alpha"] + "^{tree}")
        unrelated = fx.git.commit("unrelated", [], {"other": ("100644", b"other")})
        fx.git.git(fx.git.source, "tag", "-a", "reviewed-tag", fx.heads["alpha"], "-m", "a tag is not a commit pin")
        tag = fx.git.text(fx.git.source, "rev-parse", "reviewed-tag")
        for head in ("f" * 40, tree, tag, unrelated):
            with self.subTest(head=head):
                selection = copy.deepcopy(fx.selection)
                selection["hosts"][0]["head_commit"] = head
                report, code = fx.run(selection=selection)
                self.assertEqual((code, report["status"]), (1, "blocked"), report)
                self.assertFalse(fx.out.exists())

    def test_pinned_preview_rejects_a_different_tip_from_transport(self):
        fx = Fixture()
        def wrong_tip(host, base, mode, snapshot=None):
            if mode == "preview_pinned":
                snapshot = {"head_commit": fx.git.base}
            return fx.invoke(host, base, mode, snapshot)
        report, code = fx.run(invoke=wrong_tip)
        self.assertEqual((code, report["status"]), (1, "blocked"), report)
        self.assertTrue(all(e["code"] == "reviewed_snapshot_changed" for e in report["errors"]))
        self.assertFalse(fx.out.exists())

    def test_resume_downloads_old_pending_tip_after_that_host_advances(self):
        fx = Fixture()
        preview = self.preview(fx)
        def partial(host, base, mode, snapshot=None):
            return (255, b"") if host["id"] == "beta" and mode == "collect_pinned" else fx.invoke(host, base, mode, snapshot)
        result, code = fx.run(preview["plan_sha256"], invoke=partial)
        self.assertEqual((code, result["status"]), (1, "partial"), result)
        saved = fx.out / "alpha.bundle"
        before, inode = saved.read_bytes(), saved.stat().st_ino
        future = fx.advance("beta")
        fx.calls.clear()
        recovery, code = fx.resume(preview["plan_sha256"])
        self.assertEqual(code, 0, recovery)
        self.assertEqual(fx.calls, [])
        result, code = fx.resume(preview["plan_sha256"], recovery["resume_plan_sha256"])
        self.assertEqual((code, result["status"]), (0, "collected"), result)
        self.assertEqual(fx.calls, [("beta", "collect_pinned")])
        self.assertEqual((saved.read_bytes(), saved.stat().st_ino), (before, inode))
        self.assertEqual(result["plan"]["hosts"][1]["snapshot"]["head_commit"], fx.heads["beta"])
        self.assertNotEqual(future, fx.heads["beta"])
        self.assertEqual(collect.verify(fx.out)["status"], "verified")

    def test_resume_cannot_change_pinned_tip_or_upgrade_live_authority_offline(self):
        for pinned in (False, True):
            with self.subTest(pinned=pinned):
                fx = Fixture(pinned=pinned)
                preview, code = fx.run()
                self.assertEqual(code, 0, preview)
                def fail(host, base, mode, snapshot=None):
                    return (255, b"") if mode in ("collect", "collect_pinned") else fx.invoke(host, base, mode, snapshot)
                self.assertEqual(fx.run(preview["plan_sha256"], invoke=fail)[1], 1)
                selection = {"schema": collect.PINNED_SPEC_SCHEMA,
                             "hosts": [{"id": h["id"], "base_commit": fx.git.base,
                                        "head_commit": fx.git.base if pinned else fx.heads[h["id"]]} for h in fx.hosts]}
                fx.calls.clear()
                before = fx.git.contents(fx.out)
                with self.assertRaisesRegex(fleet.Refused, "collection_resume_selection_mismatch"):
                    fx.resume(preview["plan_sha256"], selection=selection)
                self.assertEqual(fx.calls, [])
                self.assertEqual(fx.git.contents(fx.out), before)

    def test_old_live_policy_artifacts_remain_readable_without_pinned_authority(self):
        fx = Fixture(pinned=False)
        # Generate actual previous-policy data through the unchanged live path.
        with patch.object(collect, "POLICY", collect.LIVE_HEAD_POLICY_V1):
            preview, code = fx.run()
            self.assertEqual(code, 0, preview)
            self.assertEqual(fx.run(preview["plan_sha256"])[1], 0)
        self.assertEqual(collect.verify(fx.out)["status"], "verified")
        report, code = fx.resume(preview["plan_sha256"])
        self.assertEqual((code, report["status"]), (0, "verified"))
        self.assertEqual(report["revision_mode"], "live_head")
        self.assertEqual(report["resume_plan"]["execution_policy"], collect.POLICY)


class PinPreviewTests(unittest.TestCase):
    def setUp(self):
        # Fixtures inherit the umask; a login user's 0002 makes them group-writable.
        self.addCleanup(os.umask, os.umask(0o022))
        self.assertNotEqual(os.geteuid(), 0, "Exercise actual unprivileged production behavior")
        self.fx = Fixture(pinned=False)
        self.preview, code = self.fx.run()
        self.assertEqual(code, 0, self.preview)
        self.approval = self.preview["plan_sha256"]

    def input_file(self):
        path = self.fx.root / "saved-preview.json"
        path.write_bytes(collect.encoded(self.preview))
        path.chmod(0o600)
        return path

    def cli(self, path, *args):
        return subprocess.run([sys.executable, "-I", "-B", collect.__file__, "--pin-preview", str(path),
                               "--accept-plan", self.approval, *args],
                              env={**self.fx.git.env, "PATH": "/nonexistent"},
                              capture_output=True, text=True, timeout=10)

    def test_live_preview_freezes_then_collects_after_both_heads_advance(self):
        fx = self.fx
        before = fx.git.contents(fx.root)
        with patch.object(collect, "transport", side_effect=AssertionError("opened transport")), \
             patch.object(subprocess, "Popen", side_effect=AssertionError("started process")):
            selection = collect.pin_preview(self.preview, self.approval)
        self.assertEqual(fx.git.contents(fx.root), before)
        self.assertEqual(set(selection), {"schema", "hosts"})
        self.assertEqual(selection["schema"], collect.PINNED_SPEC_SCHEMA)
        self.assertEqual([h["id"] for h in selection["hosts"]], ["alpha", "beta"])
        self.assertTrue(all(set(h) == {"id", "base_commit", "head_commit"} for h in selection["hosts"]))
        fx.selection = selection
        for name in fx.heads:
            fx.advance(name)
        pinned, code = fx.run()
        self.assertEqual(code, 0, pinned)
        self.assertNotEqual(pinned["plan_sha256"], self.approval)
        with self.assertRaisesRegex(fleet.Refused, "collection_approval_mismatch"):
            fx.run(self.approval)
        result, code = fx.run(pinned["plan_sha256"])
        self.assertEqual((code, result["status"]), (0, "collected"))
        self.assertEqual(collect.verify(fx.out)["status"], "verified")
        imported = collect.import_collection(fx.out, fx.git.repo, "frozen", [], 90)
        self.assertEqual(collect.import_collection(fx.out, fx.git.repo, "frozen", [], 90,
                         imported["plan_sha256"])["status"], "imported")

    def test_pin_is_repeatable_and_preserves_sha256_empty_ranges(self):
        fx = Fixture("sha256")
        for item in fx.selection["hosts"]:
            item["base_commit"] = item["head_commit"]
        report, code = fx.run()
        self.assertEqual(code, 0, report)
        first = collect.pin_preview(report, report["plan_sha256"])
        second = collect.pin_preview(json.loads(json.dumps(report)), report["plan_sha256"])
        self.assertEqual(first, second)
        self.assertEqual(first, fx.selection)
        self.assertTrue(all(len(h["head_commit"]) == 64 for h in first["hosts"]))

    def test_bad_digest_or_changed_plan_cannot_freeze_different_work(self):
        for approval in (None, "f" * 64, self.approval[:20], True):
            with self.subTest(approval=approval), self.assertRaisesRegex(fleet.Refused, "pin_preview_approval_mismatch"):
                collect.pin_preview(self.preview, approval)
        changed = copy.deepcopy(self.preview)
        changed["plan"]["hosts"][0]["snapshot"]["head_commit"] = "f" * 40
        with self.assertRaisesRegex(fleet.Refused, "pin_preview_approval_mismatch"):
            collect.pin_preview(changed, self.approval)

    def test_nonpreview_and_malformed_or_unknown_policy_evidence_refused(self):
        for status in ("blocked", "partial", "collected", "verified", "resume_preview"):
            with self.subTest(status=status), self.assertRaisesRegex(fleet.Refused, "pin_requires_collection_preview"):
                collect.pin_preview({**self.preview, "status": status}, self.approval)
        for key, value in (("hosts", []), ("policy", "f" * 64), ("timeout_seconds", True)):
            changed = copy.deepcopy(self.preview)
            changed["plan"][key] = value
            changed["plan_sha256"] = collect.digest(collect.encoded(changed["plan"]))
            with self.subTest(key=key), self.assertRaises(fleet.Refused):
                collect.pin_preview(changed, changed["plan_sha256"])
        for key, value in (("starts_agents", True), ("worktree_included", 0), ("unexpected", "ignored?")):
            with self.subTest(key=key), self.assertRaises(fleet.Refused):
                collect.pin_preview({**self.preview, key: value}, self.approval)
        with self.assertRaisesRegex(fleet.Refused, "pin_preview_mode_mismatch"):
            collect.pin_preview({**self.preview, "revision_mode": "pinned"}, self.approval)

    def test_main_conversion_needs_only_private_preview_and_never_starts_a_process(self):
        path = self.input_file()
        before = self.fx.git.contents(self.fx.root)
        output = io.StringIO()
        with patch.object(subprocess, "Popen", side_effect=AssertionError("started process")), \
             patch.object(collect, "transport", side_effect=AssertionError("opened transport")), redirect_stdout(output):
            code = collect.main(["--pin-preview", str(path), "--accept-plan", self.approval])
        self.assertEqual(code, 0)
        self.assertEqual(collect.decode(output.getvalue().encode()), collect.pin_preview(self.preview, self.approval))
        self.assertEqual(self.fx.git.contents(self.fx.root), before)
        # Actual isolated CLI with no Git/SSH available via PATH.
        cli = self.cli(path)
        self.assertEqual(cli.returncode, 0, cli.stdout + cli.stderr)
        self.assertEqual(cli.stderr, "")
        self.assertEqual(cli.stdout, output.getvalue())
        self.assertEqual(self.fx.git.contents(self.fx.root), before)

    def test_cli_rejects_mutating_or_other_modes_instead_of_dispatching_them(self):
        path = self.input_file()
        before = self.fx.git.contents(self.fx.root)
        for args in (("--collect",), ("--resume",), ("--import", str(self.fx.out)),
                     ("--integrate", str(self.fx.out)), ("--verify", str(self.fx.out)),
                     ("--accept-resume", self.approval), ("--launch-state", str(self.fx.launch))):
            with self.subTest(args=args):
                refused = self.cli(path, *args)
                self.assertEqual(refused.returncode, 2, refused.stdout + refused.stderr)
                self.assertEqual(self.fx.git.contents(self.fx.root), before)

    def test_cli_refuses_unsafe_or_corrupt_saved_previews(self):
        path = self.input_file()
        public = self.fx.root / "public-preview.json"
        public.write_bytes(path.read_bytes())
        public.chmod(0o644)
        link = self.fx.root / "linked-preview.json"
        link.symlink_to(path)
        fifo = self.fx.root / "pipe-preview"
        os.mkfifo(fifo, 0o600)
        malformed = self.fx.root / "malformed-preview.json"
        malformed.write_bytes(b'{"schema":')
        malformed.chmod(0o600)
        duplicate = self.fx.root / "duplicate-preview.json"
        duplicate.write_bytes(b'{"schema":"a","schema":"b"}')
        duplicate.chmod(0o600)
        for source in (public, link, fifo, malformed, duplicate):
            with self.subTest(source=source):
                refused = self.cli(source)
                self.assertEqual(refused.returncode, 2, refused.stdout + refused.stderr)
        self.assertFalse(self.fx.out.exists())
        self.assertEqual(collect.decode(path.read_bytes()), self.preview)


if __name__ == "__main__":
    if os.geteuid() == 0:
        os.setgroups([])
        os.setgid(65534)
        os.setuid(65534)
        os.execv(sys.executable, [sys.executable, "-B", __file__, *sys.argv[1:]])
    unittest.main()
