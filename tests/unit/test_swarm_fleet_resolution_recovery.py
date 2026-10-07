#!/usr/bin/env python3
"""Structural conflicts and real process-death recovery for reviewed resolutions."""
import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("resolution_support", Path(__file__).with_name("test_swarm_fleet_resolutions.py"))
support = importlib.util.module_from_spec(spec)
spec.loader.exec_module(support)
collect, Fixture = support.collect, support.Fixture
change, resolution = support.change, support.resolution


class ResolutionBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.assertNotEqual(os.geteuid(), 0)
        self.helper = support.ResolutionTests()

    def tree_entries(self, fx, report):
        scratch = Path(report["scratch_directory"])
        candidate = report["plan"]["result"]["candidate_commit"]
        raw = fx.git(scratch, "ls-tree", "-r", "-z", "--full-tree", candidate)
        entries = {}
        for item in raw[:-1].split(b"\0") if raw else []:
            meta, _, path = item.partition(b"\t")
            mode, kind, oid = meta.split()
            self.assertEqual(kind, b"blob")
            entries[path.decode()] = (mode.decode(), fx.git(scratch, "cat-file", "blob", oid.decode()))
        return entries

    def test_rename_rename_conflict_preserves_explicit_new_path_and_both_histories(self):
        fx = Fixture(files={"original": ("100644", b"same content\n"), "keep": ("100644", b"keep\n")})
        for name in ("left", "right"):
            fx.add_host(name, fx.commit(name, [fx.base], {"original": None, name: ("100644", b"same content\n")}))
        fx.seal()
        conflict = fx.preview()
        self.assertEqual(conflict["status"], "conflict")
        paths = conflict["plan"]["result"]["steps"][1]["conflicted_paths"]
        spec = resolution(conflict, [*(change(p) for p in paths), change("chosen", b"same content\n")])
        preview = fx.preview(resolutions=spec)
        self.assertEqual(self.tree_entries(fx, preview), {"chosen": ("100644", b"same content\n"),
                                                        "keep": ("100644", b"keep\n")})
        self.assertEqual(fx.preview(resolutions=spec, approval=preview["plan_sha256"])["status"], "integrated")

    def test_directory_file_conflict_can_choose_either_shape_without_dropping_unlisted_paths(self):
        for choose_file in (True, False):
            with self.subTest(choose_file=choose_file):
                fx = Fixture(files={"keep": ("100644", b"keep\n")})
                fx.add_host("file", fx.commit("file", [fx.base], {"item": ("100644", b"file\n")}))
                fx.add_host("directory", fx.commit("directory", [fx.base], {"item/child": ("100644", b"child\n")}))
                fx.seal()
                conflict = fx.preview()
                self.assertEqual(conflict["status"], "conflict")
                paths = conflict["plan"]["result"]["steps"][1]["conflicted_paths"]
                changes = {p: change(p) for p in paths}
                if choose_file:
                    changes.update({"item/child": change("item/child"), "item": change("item", b"file\n")})
                else:
                    changes["item/child"] = change("item/child", b"child\n")
                spec = resolution(conflict, list(changes.values()))
                preview = fx.preview(resolutions=spec)
                expected = {"keep": ("100644", b"keep\n")}
                expected["item" if choose_file else "item/child"] = ("100644", b"file\n" if choose_file else b"child\n")
                self.assertEqual(self.tree_entries(fx, preview), expected)

    def test_replacing_directory_must_explicitly_account_for_clean_descendants(self):
        fx = Fixture(files={"file.txt": ("100644", b"base\n"), "folder/keep": ("100644", b"keep\n")})
        for name in ("left", "right"):
            fx.add_host(name, fx.commit(name, [fx.base], {"file.txt": ("100644", name.encode() + b"\n")}))
        fx.seal()
        report = fx.preview()
        spec = resolution(report, [change("file.txt", b"resolved\n"), change("folder", b"new shape\n")])
        before = fx.contents(fx.repo)
        with self.assertRaises(collect.fleet.Refused):
            fx.preview(resolutions=spec)
        self.assertEqual(fx.contents(fx.repo), before)
        spec["steps"][0]["changes"].append(change("folder/keep"))
        preview = fx.preview(resolutions=spec)
        self.assertEqual(self.tree_entries(fx, preview), {"file.txt": ("100644", b"resolved\n"),
                                                        "folder": ("100644", b"new shape\n")})

    def test_contradictory_file_and_descendant_decisions_cannot_silently_succeed(self):
        fx = self.helper.fixture()
        spec = resolution(fx.preview(), [change("file.txt", b"resolved\n"), change("both", b"file\n"),
                                        change("both/child", b"child\n")])
        before = fx.contents(fx.repo)
        with self.assertRaises(collect.fleet.Refused):
            fx.preview(resolutions=spec)
        self.assertEqual(fx.contents(fx.repo), before)

    def test_unusual_paths_are_literal_and_do_not_act_as_shell_or_pathspec(self):
        fx = self.helper.fixture()
        names = ["spaces and 'quotes'", "line\nbreak\ttab", "unicode-é-λ", ":(glob)**", "-option", "$(touch NEVER)"]
        spec = resolution(fx.preview(), [change("file.txt", b"resolved\n"), *(change(p, p.encode()) for p in names)])
        preview = fx.preview(resolutions=spec)
        entries = self.tree_entries(fx, preview)
        for name in names:
            self.assertEqual(entries[name], ("100644", name.encode()))
        self.assertFalse((fx.root / "NEVER").exists())
        self.assertEqual(fx.preview(resolutions=spec, approval=preview["plan_sha256"])["status"], "integrated")

    def test_resolved_apply_preserves_dirty_linked_worktree_and_its_private_index(self):
        fx = self.helper.fixture(later=True)
        linked = fx.root / "linked"
        fx.git(fx.repo, "worktree", "add", "--detach", str(linked), fx.base)
        (linked / "file.txt").write_bytes(b"staged\n")
        fx.git(linked, "add", "file.txt")
        (linked / "file.txt").write_bytes(b"unstaged\n")
        (linked / "untracked").write_bytes(b"untracked\n")
        conflict = fx.preview(repository=linked)
        spec = resolution(conflict, [change("file.txt", b"resolved\n")])
        preview = fx.preview(repository=linked, resolutions=spec)
        before = fx.contents(linked)
        index = fx.repo / ".git/worktrees/linked/index"
        index_before = index.read_bytes()
        result = fx.preview(repository=linked, resolutions=spec, approval=preview["plan_sha256"])
        self.assertEqual(result["status"], "integrated")
        self.assertEqual(fx.contents(linked), before)
        self.assertEqual(index.read_bytes(), index_before)
        self.assertEqual(fx.preview(repository=linked, resolutions=spec, approval=preview["plan_sha256"], check=True)["status"], "matched")

    def test_real_competing_symbolic_ref_cannot_redirect_resolved_publication(self):
        fx = self.helper.fixture()
        spec, preview = self.helper.resolved(fx)
        reference = preview["plan"]["ref"]
        original = collect.LocalGit.run
        def race(instance, args, *rest, **options):
            if instance.repository == fx.repo and args[:1] == ["update-ref"]:
                fx.git(fx.repo, "symbolic-ref", reference, "refs/heads/main")
            return original(instance, args, *rest, **options)
        with patch.object(collect.LocalGit, "run", race), self.assertRaises(collect.fleet.Refused):
            fx.preview(resolutions=spec, approval=preview["plan_sha256"])
        self.assertEqual(fx.text(fx.repo, "rev-parse", "HEAD"), fx.base)
        self.assertEqual(fx.text(fx.repo, "symbolic-ref", reference), "refs/heads/main")
        before = fx.contents(fx.repo)
        checked = fx.preview(resolutions=spec, approval=preview["plan_sha256"], check=True)
        self.assertEqual(checked["candidate"]["status"], "symbolic")
        self.assertEqual(fx.contents(fx.repo), before)

    def crash_after(self, operation, threshold, expected):
        fx = self.helper.fixture()
        spec, preview = self.helper.resolved(fx)
        script = Path(collect.__file__).resolve()
        program = f'''
import importlib.util, os, signal
from pathlib import Path
spec = importlib.util.spec_from_file_location("actual_controller", {str(script)!r})
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)
original = c.LocalGit.run
count = 0
def interrupt(instance, args, *rest, **options):
    global count
    result = original(instance, args, *rest, **options)
    if str(instance.repository) == {str(fx.repo)!r} and args[:1] == [{operation!r}]:
        count += 1
        if count == {threshold!r}:
            os.kill(os.getpid(), signal.SIGKILL)
    return result
c.LocalGit.run = interrupt
c.integrate_collection({str(fx.collection)!r}, {str(fx.repo)!r}, {fx.base!r}, "wave1", [], 90,
                       {preview["plan_sha256"]!r}, resolutions={spec!r})
'''
        killed = subprocess.run([sys.executable, "-I", "-B", "-c", program], capture_output=True,
                                text=True, env=fx.env, timeout=30)
        self.assertEqual(killed.returncode, -signal.SIGKILL, killed.stdout + killed.stderr)
        candidate = preview["plan"]["result"]["candidate_commit"]
        # Crash only after the synthesized resolution objects really exist.
        self.assertEqual(fx.git(fx.repo, "show", candidate + ":file.txt"), b"left and right\n")
        before = fx.contents(fx.repo)
        checked = fx.preview(resolutions=spec, approval=preview["plan_sha256"], check=True)
        self.assertEqual(checked["candidate"]["status"], expected)
        self.assertFalse(checked["destination_writes_started"])
        self.assertEqual(fx.contents(fx.repo), before)

    def test_sigkill_after_resolved_object_transfer_is_missing_without_retry(self):
        self.crash_after("index-pack", 3, "missing")

    def test_sigkill_after_resolved_ref_publication_is_matched_without_retry(self):
        self.crash_after("update-ref", 1, "matched")


if __name__ == "__main__":
    if os.geteuid() == 0:
        os.setgroups([])
        os.setgid(65534)
        os.setuid(65534)
        os.execv(sys.executable, [sys.executable, "-B", __file__, *sys.argv[1:]])
    unittest.main()
