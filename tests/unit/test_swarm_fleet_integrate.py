#!/usr/bin/env python3
"""Real Git collection/merge tests. Fixtures and scratch repositories are retained."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/swarm-fleet-collect.py"
spec = importlib.util.spec_from_file_location("fleet_collect", SCRIPT)
collect = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collect)


class Fixture:
    def __init__(self, fmt="sha1", files=None):
        self.root = Path(tempfile.mkdtemp(prefix="acfs-integration-test-"))
        self.source = self.root / "source"
        self.repo = self.root / "destination"
        self.collection = self.root / "collection"
        self.env = {"PATH": "/usr/bin:/bin", "HOME": "/nonexistent", "LANG": "C", "LC_ALL": "C",
                    "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
                    "GIT_AUTHOR_NAME": "Fixture", "GIT_COMMITTER_NAME": "Fixture",
                    "GIT_AUTHOR_EMAIL": "fixture@example.invalid", "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
                    "GIT_AUTHOR_DATE": "1700000000 +0000", "GIT_COMMITTER_DATE": "1700000000 +0000"}
        self.fmt = fmt
        for repo in (self.source, self.repo):
            repo.mkdir(mode=0o700)
            self.git(repo, "init", "--template=", "--initial-branch=main", "--object-format=" + fmt)
        self.base = self.commit("base", [], files or {"file.txt": ("100644", b"base\n")})
        self.git(self.source, "update-ref", "refs/heads/main", self.base)
        pack = self.git(self.source, "pack-objects", "--stdout", "--revs", data=(self.base + "\n").encode())
        self.git(self.repo, "index-pack", "--stdin", data=pack)
        self.git(self.repo, "update-ref", "refs/heads/main", self.base)
        self.git(self.repo, "read-tree", self.base)
        self.git(self.repo, "checkout-index", "--all")
        self.entries = []

    def git(self, repo, *args, data=b"", env=None, allowed=(0,)):
        result = subprocess.run(["/usr/bin/git", "-C", str(repo), *args], input=data, capture_output=True,
                                env=env or self.env, timeout=15)
        if result.returncode not in allowed:
            raise AssertionError((args, result.returncode, result.stderr.decode(errors="replace")))
        return result.stdout

    def text(self, repo, *args):
        return self.git(repo, *args).decode().strip()

    def commit(self, name, parents, changes):
        # A private alternate index constructs deletion/rename fixtures without
        # removing any filesystem files or checking out another user's work.
        env = {**self.env, "GIT_INDEX_FILE": str(self.root / ("index-" + name))}
        self.git(self.source, "read-tree", parents[0] if parents else "--empty", env=env)
        for path, value in changes.items():
            if value is None:
                self.git(self.source, "update-index", "--force-remove", "--", path, env=env)
            else:
                mode, content = value
                blob = self.git(self.source, "hash-object", "-w", "--stdin", data=content).decode().strip()
                self.git(self.source, "update-index", "--add", "--cacheinfo", mode + "," + blob + "," + path, env=env)
        tree = self.git(self.source, "write-tree", env=env).decode().strip()
        args = ["commit-tree", tree]
        for parent in parents:
            args += ["-p", parent]
        oid = self.git(self.source, *args, data=(name + "\n").encode()).decode().strip()
        self.git(self.source, "update-ref", "refs/heads/" + name, oid)
        return oid

    def add_host(self, host, head, base=None):
        base = base or self.base
        self.git(self.source, "update-ref", "refs/heads/bundle-source", head)
        self.git(self.source, "symbolic-ref", "HEAD", "refs/heads/bundle-source")
        count = int(self.text(self.source, "rev-list", "--count", base + ".." + head))
        bundle = self.git(self.source, "bundle", "create", "--version=3", "-", "HEAD", "^" + base) if count else b""
        paths = self.git(self.source, "diff", "--no-renames", "--name-only", "-z", base, head)
        self.entries.append(({"id": host, "snapshot": {"base_commit": base, "head_commit": head,
            "object_format": self.fmt, "commit_count": count, "net_changed_paths": collect.integration_paths(paths),
            "repository_identity": [self.source.stat().st_dev, self.source.stat().st_ino]}}, bundle))

    def seal(self):
        self.collection.mkdir(mode=0o700)
        plan = {"schema": collect.SCHEMA, "policy": collect.POLICY,
                "launch_plan_sha256": "a" * 64, "launch_evidence_sha256": "b" * 64,
                "known_hosts_sha256": "c" * 64, "identity_sha256": "d" * 64,
                "output_directory": str(self.collection),
                "output_parent_identity": [self.root.stat().st_dev, self.root.stat().st_ino],
                "timeout_seconds": 90, "hosts": [e for e, _ in self.entries]}
        artifacts = []
        with collect.fleet.directory_fd(self.collection, private=True) as fd:
            collect.fleet.publish(fd, "intent.json", {"schema": collect.SCHEMA, "plan": plan})
            for entry, bundle in self.entries:
                name = entry["id"] + ".bundle" if bundle else None
                if name:
                    collect.publish_bundle(fd, name, bundle)
                artifacts.append({"id": entry["id"], "file": name, "bytes": len(bundle), "sha256": collect.digest(bundle)})
            collect.fleet.publish(fd, "manifest.json", {"schema": collect.SCHEMA,
                                  "plan_sha256": collect.digest(collect.encoded(plan)), "artifacts": artifacts})
        collect.verify(self.collection)

    def preview(self, **kwargs):
        options = dict(path=self.collection, repository=self.repo, onto=self.base,
                       name="wave1", hosts=[], timeout=90)
        options.update(kwargs)
        return collect.integrate_collection(**options)

    def cli(self, *extra):
        return subprocess.run([sys.executable, "-I", str(SCRIPT), "--integrate", str(self.collection),
            "--repository", str(self.repo), "--onto", self.base, "--name", "wave1", *extra],
            env=self.env, capture_output=True, text=True, timeout=30)

    @staticmethod
    def contents(root):
        return {str(p.relative_to(root)): ("link", os.readlink(p)) if p.is_symlink()
                else ("file", p.stat().st_mode & 0o777, p.read_bytes())
                for p in root.rglob("*") if not p.is_dir()}


class IntegrationTests(unittest.TestCase):
    def setUp(self):
        self.assertNotEqual(os.geteuid(), 0, "Run this test script as an unprivileged user")

    def branches(self, fmt="sha1", files=None, changes=None):
        fx = Fixture(fmt, files)
        changes = changes or [{"left": ("100644", b"left\n")}, {"right": ("100755", b"#!/bin/sh\nexit 0\n")}]
        for i, change in enumerate(changes):
            head = fx.commit("branch" + str(i), [fx.base], change)
            fx.add_host("host" + str(i), head)
        fx.seal()
        return fx

    def test_combines_real_histories_without_modifying_destination_or_collection(self):
        fx = self.branches()
        before, artifacts = fx.contents(fx.repo), fx.contents(fx.collection)
        result = fx.preview()
        self.assertEqual(result["status"], "preview")
        merged = result["plan"]["result"]
        self.assertEqual([r["status"] for r in merged["steps"]], ["fast_forward", "merged"])
        scratch = Path(result["scratch_directory"])
        candidate = merged["candidate_commit"]
        self.assertEqual(fx.text(scratch, "rev-parse", candidate + "^1"), fx.entries[0][0]["snapshot"]["head_commit"])
        self.assertEqual(fx.text(scratch, "rev-parse", candidate + "^2"), fx.entries[1][0]["snapshot"]["head_commit"])
        self.assertEqual(fx.git(scratch, "show", candidate + ":left"), b"left\n")
        self.assertEqual(fx.git(scratch, "show", candidate + ":right"), b"#!/bin/sh\nexit 0\n")
        self.assertIn("100755", fx.text(scratch, "ls-tree", candidate, "right"))
        self.assertEqual(fx.contents(fx.repo), before)
        self.assertEqual(fx.contents(fx.collection), artifacts)
        self.assertFalse(result["destination_writes_started"])
        self.assertEqual(scratch.stat().st_mode & 0o777, 0o700)

    def test_repeated_preview_has_identical_candidate_and_approval(self):
        fx = self.branches()
        first, second = fx.preview(), fx.preview()
        self.assertEqual(first["plan"], second["plan"])
        self.assertEqual(first["plan_sha256"], second["plan_sha256"])
        self.assertNotEqual(first["scratch_directory"], second["scratch_directory"])

    def test_conflict_stops_later_hosts_without_exposing_marker_tree_as_candidate(self):
        fx = self.branches(changes=[{"file.txt": ("100644", b"left\n")},
                                   {"file.txt": ("100644", b"right\n")},
                                   {"other": ("100644", b"not attempted\n")}])
        before = fx.contents(fx.repo)
        result = fx.preview()
        self.assertEqual(result["status"], "conflict")
        self.assertIsNone(result["plan_sha256"])
        merged = result["plan"]["result"]
        self.assertIsNone(merged["candidate_commit"])
        self.assertIsNone(merged["candidate_tree"])
        self.assertEqual(merged["steps"][1]["conflicted_paths"], ["file.txt"])
        self.assertEqual(merged["steps"][2]["status"], "not_attempted")
        self.assertEqual(fx.contents(fx.repo), before)
        self.assertEqual(fx.cli().returncode, 1)

    def test_binary_conflicts_are_not_treated_as_clean(self):
        fx = self.branches(files={"file.txt": ("100644", b"base\0binary")}, changes=[
            {"file.txt": ("100644", b"left\0binary")}, {"file.txt": ("100644", b"right\0binary")}])
        result = fx.preview()
        self.assertEqual(result["status"], "conflict")
        self.assertEqual(result["plan"]["result"]["steps"][1]["conflicted_paths"], ["file.txt"])

    def test_modify_delete_conflict_uses_git_not_overlapping_path_heuristic(self):
        fx = self.branches(changes=[{"file.txt": None}, {"file.txt": ("100644", b"modified\n")}])
        self.assertEqual(fx.preview()["status"], "conflict")

    def test_same_file_nonoverlapping_hunks_merge(self):
        lines = [str(i) + "\n" for i in range(30)]
        a, b, expected = lines.copy(), lines.copy(), lines.copy()
        a[2], b[25] = "left\n", "right\n"
        expected[2], expected[25] = a[2], b[25]
        fx = self.branches(files={"file.txt": ("100644", "".join(lines).encode())}, changes=[
            {"file.txt": ("100644", "".join(a).encode())}, {"file.txt": ("100644", "".join(b).encode())}])
        result = fx.preview()
        self.assertEqual(result["status"], "preview")
        self.assertEqual(fx.git(Path(result["scratch_directory"]), "show",
            result["plan"]["result"]["candidate_commit"] + ":file.txt"), "".join(expected).encode())

    def test_rename_and_edit_are_combined_by_git(self):
        original = b"".join((str(i) + "\n").encode() for i in range(40))
        edited = original.replace(b"15\n", b"EDITED\n")
        fx = self.branches(files={"file.txt": ("100644", original)}, changes=[
            {"file.txt": None, "renamed.txt": ("100644", original)}, {"file.txt": ("100644", edited)}])
        result = fx.preview()
        self.assertEqual(result["status"], "preview")
        self.assertEqual(fx.git(Path(result["scratch_directory"]), "show",
            result["plan"]["result"]["candidate_commit"] + ":renamed.txt"), edited)

    def test_unchanged_and_duplicate_histories_are_not_merged_again(self):
        fx = Fixture()
        head = fx.commit("one", [fx.base], {"new": ("100644", b"new")})
        fx.add_host("empty", fx.base)
        fx.add_host("first", head)
        fx.add_host("duplicate", head)
        fx.seal()
        result = fx.preview()
        self.assertEqual([r["status"] for r in result["plan"]["result"]["steps"]],
                         ["unchanged", "fast_forward", "already_contained"])
        self.assertEqual(result["plan"]["result"]["candidate_commit"], head)

    def test_sha256_history_and_synthetic_parents(self):
        fx = self.branches(fmt="sha256")
        result = fx.preview()
        candidate = result["plan"]["result"]["candidate_commit"]
        self.assertEqual(len(candidate), 64)
        self.assertEqual(len(fx.text(Path(result["scratch_directory"]), "show", "-s", "--format=%P", candidate).split()), 2)
        self.assertEqual(fx.text(fx.repo, "rev-parse", "HEAD"), fx.base)

    def test_linked_worktree_and_dirty_index_are_preserved(self):
        fx = self.branches()
        linked = fx.root / "linked"
        fx.git(fx.repo, "worktree", "add", "--detach", "--no-checkout", str(linked), fx.base)
        fx.git(linked, "read-tree", fx.base)
        fx.git(linked, "checkout-index", "--all")
        (linked / "file.txt").write_text("staged\n")
        fx.git(linked, "add", "file.txt")
        (linked / "file.txt").write_text("unstaged\n")
        (linked / "untracked").write_text("keep me\n")
        before, common = fx.contents(linked), fx.contents(fx.repo / ".git")
        self.assertEqual(fx.preview(repository=linked)["status"], "preview")
        self.assertEqual(fx.contents(linked), before)
        self.assertEqual(fx.contents(fx.repo / ".git"), common)

    def test_custom_merge_attributes_are_refused_without_running_driver(self):
        fx = self.branches(files={"file.txt": ("100644", b"base\n"),
                                  ".gitattributes": ("100644", b"[attr]special merge=evil\n*.txt special\n")})
        sentinel = fx.root / "driver-ran"
        fx.git(fx.repo, "config", "merge.evil.driver", "touch " + str(sentinel))
        before = fx.contents(fx.repo)
        with self.assertRaisesRegex(collect.fleet.Refused, "external_merge_driver_not_supported"):
            fx.preview()
        self.assertFalse(sentinel.exists())
        self.assertEqual(fx.contents(fx.repo), before)

    def test_host_selection_keeps_original_order_and_rejects_unknown_or_duplicate(self):
        fx = self.branches()
        a, b = fx.preview(hosts=["host1", "host0"]), fx.preview()
        self.assertEqual(a["plan_sha256"], b["plan_sha256"])
        self.assertEqual(len(fx.preview(hosts=["host1"])["plan"]["result"]["steps"]), 1)
        for hosts in (["host0", "host0"], ["unknown"]):
            with self.subTest(hosts=hosts), self.assertRaises(collect.fleet.Refused):
                fx.preview(hosts=hosts)

    def test_existing_direct_and_dangling_symbolic_candidates_are_never_adopted(self):
        fx = self.branches()
        ref = "refs/acfs/integrations/wave1"
        fx.git(fx.repo, "update-ref", ref, fx.base)
        before = fx.contents(fx.repo)
        with self.assertRaisesRegex(collect.fleet.Refused, "review_ref_already_exists"):
            fx.preview()
        self.assertEqual(fx.contents(fx.repo), before)
        fx.git(fx.repo, "symbolic-ref", "refs/acfs/integrations/symbolic", "refs/heads/nonexistent")
        with self.assertRaisesRegex(collect.fleet.Refused, "review_ref_already_exists"):
            fx.preview(name="symbolic")

    def test_full_target_commit_is_required_and_unrelated_base_is_refused(self):
        fx = self.branches()
        for onto in ("HEAD", "main", fx.base[:12], "--help"):
            with self.subTest(onto=onto), self.assertRaisesRegex(collect.fleet.Refused, "full_onto_commit"):
                fx.preview(onto=onto)
        other = fx.commit("unrelated", [], {"unrelated": ("100644", b"unrelated")})
        pack = fx.git(fx.source, "pack-objects", "--stdout", "--revs", data=(other + "\n").encode())
        fx.git(fx.repo, "index-pack", "--stdin", data=pack)
        with self.assertRaises(collect.fleet.Refused):
            fx.preview(onto=other)
        self.assertIsNone(collect.INTEGRATION_SCRATCH)

    def test_corrupt_collection_is_refused_before_scratch_and_destination_writes(self):
        fx = self.branches()
        (fx.collection / "host1.bundle").write_bytes(b"corrupted")
        before = fx.contents(fx.repo)
        with self.assertRaises(collect.fleet.Refused):
            fx.preview()
        self.assertIsNone(collect.INTEGRATION_SCRATCH)
        self.assertEqual(fx.contents(fx.repo), before)

    def test_cli_rejects_execution_and_ambiguous_modes_before_work(self):
        fx = self.branches()
        before = fx.contents(fx.repo)
        for args in (("--send",), ("--apply",), ("--import", str(fx.collection)), ("--resume",)):
            with self.subTest(args=args):
                result = fx.cli(*args)
                self.assertEqual(result.returncode, 2)
        self.assertEqual(fx.contents(fx.repo), before)


if __name__ == "__main__":
    if os.geteuid() == 0:
        os.setgroups([])
        os.setgid(65534)
        os.setuid(65534)
        # Re-exec after dropping privilege: Linux otherwise marks this process
        # nondumpable, so same-user Git cannot read its /proc/PID/fd snapshots.
        os.execv(sys.executable, [sys.executable, "-B", __file__, *sys.argv[1:]])
    unittest.main()
