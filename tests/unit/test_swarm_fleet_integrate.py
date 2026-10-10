#!/usr/bin/env python3
"""Real Git collection/merge tests. Fixtures and scratch repositories are retained."""
import importlib.util
import os
from pathlib import Path
import signal
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
        # Fixtures inherit the umask; a login user's 0002 makes them group-writable.
        self.addCleanup(os.umask, os.umask(0o022))
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


class CandidatePublicationTests(unittest.TestCase):
    def setUp(self):
        # Fixtures inherit the umask; a login user's 0002 makes them group-writable.
        self.addCleanup(os.umask, os.umask(0o022))

    def branches(self, **options):
        return IntegrationTests().branches(**options)

    def apply(self, fx, **options):
        preview = fx.preview(**options)
        return fx.preview(approval=preview["plan_sha256"], **options)

    def test_publishes_exact_candidate_and_preserves_dirty_checkout_and_existing_refs(self):
        fx = self.branches()
        (fx.repo / "file.txt").write_text("staged\n")
        fx.git(fx.repo, "add", "file.txt")
        (fx.repo / "file.txt").write_text("unstaged\n")
        (fx.repo / "untracked").write_text("keep private\n")
        before = fx.contents(fx.repo)
        refs = fx.text(fx.repo, "show-ref").splitlines()
        preview = fx.preview()
        result = fx.preview(approval=preview["plan_sha256"])
        self.assertEqual(result["status"], "integrated")
        self.assertTrue(result["candidate_published"])
        self.assertTrue(result["destination_writes_started"])
        ref = preview["plan"]["ref"]
        candidate = fx.text(fx.repo, "rev-parse", ref)
        self.assertEqual(candidate, preview["plan"]["result"]["candidate_commit"])
        self.assertEqual(fx.text(fx.repo, "rev-parse", ref + "^{tree}"),
                         preview["plan"]["result"]["candidate_tree"])
        self.assertEqual(fx.git(fx.repo, "show", ref + ":left"), b"left\n")
        self.assertIn("100755", fx.text(fx.repo, "ls-tree", ref, "right"))
        self.assertEqual(len(fx.text(fx.repo, "show", "-s", "--format=%P", ref).split()), 2)
        self.assertTrue(set(refs) <= set(fx.text(fx.repo, "show-ref").splitlines()))
        after = fx.contents(fx.repo)
        for name, value in before.items():
            self.assertEqual(after[name], value, name)
        self.assertFalse((fx.repo / ".git/FETCH_HEAD").exists())
        self.assertTrue(list((fx.repo / ".git/objects/pack").glob("*.keep")))

    def test_applies_without_prior_import_refs(self):
        fx = self.branches()
        self.assertEqual(fx.text(fx.repo, "for-each-ref", "--format=%(refname)"), "refs/heads/main")
        self.assertEqual(self.apply(fx)["status"], "integrated")
        refs = fx.text(fx.repo, "for-each-ref", "--format=%(refname)").splitlines()
        self.assertEqual(set(refs), {"refs/heads/main", "refs/acfs/integrations/wave1"})

    def test_fast_forward_publishes_collected_tip_without_synthetic_commit(self):
        fx = self.branches(changes=[{"new": ("100644", b"one\n")}])
        result = self.apply(fx)
        self.assertEqual(result["status"], "integrated")
        self.assertEqual(fx.text(fx.repo, "rev-parse", result["plan"]["ref"]),
                         fx.entries[0][0]["snapshot"]["head_commit"])
        self.assertEqual(result["plan"]["result"]["steps"][0]["status"], "fast_forward")

    def test_unchanged_collection_creates_no_ref_or_destination_object(self):
        fx = Fixture()
        fx.add_host("empty", fx.base)
        fx.seal()
        before = fx.contents(fx.repo)
        result = self.apply(fx)
        self.assertEqual(result["status"], "noop")
        self.assertFalse(result["candidate_published"])
        self.assertFalse(result["destination_writes_started"])
        self.assertEqual(fx.contents(fx.repo), before)

    def test_wrong_approval_or_changed_selection_never_writes_destination(self):
        fx = self.branches()
        preview = fx.preview()
        before = fx.contents(fx.repo)
        for approval, options in (("0" * 64, {}), (preview["plan_sha256"], {"hosts": ["host0"]}),
                                  (preview["plan_sha256"], {"name": "other"})):
            with self.assertRaisesRegex(collect.fleet.Refused, "integration_approval_mismatch"):
                fx.preview(approval=approval, **options)
        self.assertFalse(collect.INTEGRATION_WRITES_STARTED)
        self.assertEqual(fx.contents(fx.repo), before)

    def test_conflicting_history_cannot_be_approved(self):
        fx = self.branches(changes=[{"file.txt": ("100644", b"left\n")},
                                   {"file.txt": ("100644", b"right\n")}])
        before = fx.contents(fx.repo)
        with self.assertRaisesRegex(collect.fleet.Refused, "integration_approval_mismatch"):
            fx.preview(approval="0" * 64)
        self.assertFalse(collect.INTEGRATION_WRITES_STARTED)
        self.assertEqual(fx.contents(fx.repo), before)

    def test_existing_identical_candidate_is_not_adopted_or_overwritten(self):
        fx = self.branches()
        result = self.apply(fx)
        before = fx.contents(fx.repo)
        with self.assertRaisesRegex(collect.fleet.Refused, "review_ref_already_exists"):
            fx.preview(approval=result["plan_sha256"])
        self.assertEqual(fx.contents(fx.repo), before)

    def test_real_competing_candidate_creation_is_preserved(self):
        self.race(False)

    def test_real_symbolic_candidate_race_cannot_redirect_main(self):
        self.race(True)

    def race(self, symbolic):
        fx = self.branches()
        preview = fx.preview()
        ref = preview["plan"]["ref"]
        original = collect.LocalGit.run
        def racing(instance, args, *rest, **options):
            if instance.repository == fx.repo and args[:1] == ["update-ref"]:
                if symbolic:
                    fx.git(fx.repo, "symbolic-ref", ref, "refs/heads/main")
                else:
                    fx.git(fx.repo, "update-ref", ref, fx.base)
            return original(instance, args, *rest, **options)
        collect.LocalGit.run = racing
        try:
            with self.assertRaises(collect.fleet.Refused):
                fx.preview(approval=preview["plan_sha256"])
        finally:
            collect.LocalGit.run = original
        self.assertEqual(fx.text(fx.repo, "rev-parse", "HEAD"), fx.base)
        self.assertEqual(fx.text(fx.repo, "rev-parse", ref), fx.base)
        if symbolic:
            self.assertEqual(fx.text(fx.repo, "symbolic-ref", ref), "refs/heads/main")

    def test_source_change_after_object_indexing_does_not_publish_candidate(self):
        fx = self.branches()
        preview = fx.preview()
        original = collect.LocalGit.run
        def changing(instance, args, *rest, **options):
            result = original(instance, args, *rest, **options)
            if instance.repository == fx.repo and args[:1] == ["index-pack"]:
                with (fx.collection / "manifest.json").open("ab") as out:
                    out.write(b" ")
            return result
        collect.LocalGit.run = changing
        try:
            with self.assertRaisesRegex(collect.fleet.Refused, "collection_changed"):
                fx.preview(approval=preview["plan_sha256"])
        finally:
            collect.LocalGit.run = original
        self.assertTrue(collect.INTEGRATION_WRITES_STARTED)
        self.assertIsNone(collect.review_ref_value(collect.LocalGit(fx.repo, 10), preview["plan"]["ref"]))

    def test_project_hooks_are_not_executed(self):
        fx = self.branches()
        hooks = fx.repo / ".git/hooks"
        hooks.mkdir()
        marker = fx.root / "HOOK_RAN"
        hook = hooks / "reference-transaction"
        hook.write_text("#!/bin/sh\nprintf bad > " + str(marker) + "\n")
        hook.chmod(0o755)
        result = self.apply(fx)
        self.assertEqual(result["status"], "integrated")
        self.assertFalse(marker.exists())

    def test_sha256_candidate_is_published_with_full_topology(self):
        fx = self.branches(fmt="sha256")
        result = self.apply(fx)
        candidate = fx.text(fx.repo, "rev-parse", result["plan"]["ref"])
        self.assertEqual(len(candidate), 64)
        for entry, _ in fx.entries:
            fx.git(fx.repo, "merge-base", "--is-ancestor", entry["snapshot"]["head_commit"], candidate)
        self.assertEqual(fx.text(fx.repo, "rev-parse", "HEAD"), fx.base)

    def test_linked_worktree_index_and_files_are_preserved_on_apply(self):
        fx = self.branches()
        linked = fx.root / "linked"
        fx.git(fx.repo, "worktree", "add", "--detach", str(linked), fx.base)
        (linked / "file.txt").write_text("staged\n")
        fx.git(linked, "add", "file.txt")
        (linked / "file.txt").write_text("unstaged\n")
        before = fx.contents(linked)
        index = fx.repo / ".git/worktrees/linked/index"
        index_before = index.read_bytes()
        self.assertEqual(self.apply(fx, repository=linked)["status"], "integrated")
        self.assertEqual(fx.contents(linked), before)
        self.assertEqual(index.read_bytes(), index_before)
        self.assertEqual(fx.text(fx.repo, "rev-parse", "HEAD"), fx.base)

    def test_cli_requires_separate_integration_approval(self):
        fx = self.branches()
        result = fx.cli("--apply", "--accept-plan", "0" * 64)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse(collect.decode(result.stdout.encode())["integration_writes_started"])
        preview = collect.decode(fx.cli().stdout.encode())
        result = fx.cli("--apply", "--accept-plan", preview["plan_sha256"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(collect.decode(result.stdout.encode())["status"], "integrated")


class IntegrationRecoveryTests(unittest.TestCase):
    def fixture(self, **options):
        return IntegrationTests().branches(**options)

    def check(self, fx, preview, **options):
        return fx.preview(check=True, approval=preview["plan_sha256"], **options)

    def test_corrupt_loose_candidate_bytes_cannot_match_by_pathname(self):
        import zlib
        fx = self.fixture()
        preview = fx.preview()
        fx.preview(approval=preview["plan_sha256"])
        candidate = preview["plan"]["result"]["candidate_commit"]
        original = fx.git(fx.repo, "cat-file", "commit", candidate)
        # Git may prefer indexed packs to a same-OID loose file. Preserve the
        # fixture's packs elsewhere and unpack every object before corruption.
        pack_dir = fx.repo / ".git/objects/pack"
        packs = [p.read_bytes() for p in pack_dir.glob("*.pack")]
        retained = fx.root / "retained-packs"
        retained.mkdir(mode=0o700)
        for item in pack_dir.iterdir():
            item.rename(retained / item.name)
        for pack in packs:
            fx.git(fx.repo, "unpack-objects", data=pack)
        self.assertEqual(fx.git(fx.repo, "cat-file", "commit", candidate), original)
        # Keep tree and parents intact but change the actual commit bytes.
        changed = original + b"\ncorrupted candidate message\n"
        raw = b"commit " + str(len(changed)).encode() + b"\0" + changed
        self.assertNotEqual(collect.hashlib.new(fx.fmt, raw).hexdigest(), candidate)
        path = fx.repo / ".git/objects" / candidate[:2] / candidate[2:]
        path.chmod(0o600)
        with path.open("wb") as stream:
            stream.write(zlib.compress(raw))
        self.assertEqual(fx.git(fx.repo, "cat-file", "commit", candidate), changed)
        before = fx.contents(fx.repo)
        result = collect.inspect_integration(collect.LocalGit(fx.repo, 30), preview["plan"])
        self.assertEqual(result["status"], "unconfirmed")
        self.assertEqual(result["code"], "integration_candidate_object_mismatch")
        # Full reconstruction can refuse the corrupt alternate before reaching
        # inspection; either refusal path must remain unsuccessful and read-only.
        checked = fx.cli("--check", "--accept-plan", preview["plan_sha256"])
        self.assertIn(checked.returncode, (1, 2), checked.stdout + checked.stderr)
        self.assertEqual(fx.contents(fx.repo), before)

    def test_missing_before_apply_and_matched_after_apply_without_destination_writes(self):
        fx = self.fixture()
        preview = fx.preview()
        before = fx.contents(fx.repo)
        missing = self.check(fx, preview)
        self.assertEqual(missing["status"], "attention")
        self.assertEqual(missing["candidate"]["status"], "missing")
        self.assertEqual(fx.contents(fx.repo), before)
        fx.preview(approval=preview["plan_sha256"])
        before = fx.contents(fx.repo)
        matched = self.check(fx, preview)
        self.assertEqual(matched["status"], "matched")
        self.assertEqual(matched["candidate"]["status"], "matched")
        self.assertTrue(matched["destination_read_only"])
        self.assertFalse(matched["destination_writes_started"])
        self.assertFalse(matched["candidate_published"])
        self.assertFalse(matched["integration_provenance_verified"])
        self.assertFalse(matched["task_completion_verified"])
        self.assertEqual(matched["plan_sha256"], preview["plan_sha256"])
        self.assertEqual(fx.contents(fx.repo), before)

    def test_different_and_symbolic_candidates_are_not_repaired(self):
        fx = self.fixture()
        preview = fx.preview()
        ref = preview["plan"]["ref"]
        fx.git(fx.repo, "update-ref", ref, fx.base)
        before = fx.contents(fx.repo)
        result = self.check(fx, preview)
        self.assertEqual(result["candidate"]["status"], "different")
        self.assertEqual(result["status"], "attention")
        self.assertEqual(fx.contents(fx.repo), before)
        fx.git(fx.repo, "symbolic-ref", ref, "refs/heads/main")
        before = fx.contents(fx.repo)
        self.assertEqual(self.check(fx, preview)["candidate"]["status"], "symbolic")
        self.assertEqual(fx.contents(fx.repo), before)

    def test_unchanged_selection_checks_absence_and_rejects_unexpected_ref(self):
        fx = Fixture()
        fx.add_host("empty", fx.base)
        fx.seal()
        preview = fx.preview()
        result = self.check(fx, preview)
        self.assertEqual((result["status"], result["candidate"]["status"]), ("matched", "unchanged"))
        self.assertIsNone(result["candidate"]["expected_commit"])
        fx.git(fx.repo, "update-ref", preview["plan"]["ref"], fx.base)
        before = fx.contents(fx.repo)
        self.assertEqual(self.check(fx, preview)["candidate"]["status"], "different")
        self.assertEqual(fx.contents(fx.repo), before)

    def test_real_ref_change_during_check_is_unconfirmed(self):
        fx = self.fixture()
        preview = fx.preview()
        fx.preview(approval=preview["plan_sha256"])
        original = collect.LocalGit.run
        candidate = preview["plan"]["result"]["candidate_commit"]
        def changing(instance, args, *rest, **options):
            result = original(instance, args, *rest, **options)
            if instance.repository == fx.repo and args == ["cat-file", "-t", candidate]:
                fx.git(fx.repo, "update-ref", preview["plan"]["ref"], fx.base)
            return result
        collect.LocalGit.run = changing
        try:
            result = self.check(fx, preview)
        finally:
            collect.LocalGit.run = original
        self.assertEqual(result["status"], "attention")
        self.assertEqual(result["candidate"]["status"], "unconfirmed")
        self.assertEqual(fx.text(fx.repo, "rev-parse", preview["plan"]["ref"]), fx.base)

    def test_check_requires_exact_original_digest_and_selection(self):
        fx = self.fixture()
        preview = fx.preview()
        before = fx.contents(fx.repo)
        for options in ({"check": True}, {"check": True, "approval": "0" * 64},
                        {"check": True, "approval": preview["plan_sha256"], "name": "changed"},
                        {"check": True, "approval": preview["plan_sha256"], "hosts": ["host0"]}):
            with self.subTest(options=options), self.assertRaises(collect.fleet.Refused):
                fx.preview(**options)
        self.assertEqual(fx.contents(fx.repo), before)

    def test_corrupt_collection_prevents_successful_check(self):
        fx = self.fixture()
        preview = fx.preview()
        fx.preview(approval=preview["plan_sha256"])
        (fx.collection / "host1.bundle").write_bytes(b"corrupt retained evidence")
        before = fx.contents(fx.repo)
        with self.assertRaises(collect.fleet.Refused):
            self.check(fx, preview)
        self.assertEqual(fx.contents(fx.repo), before)

    def test_sha256_publication_and_check(self):
        fx = self.fixture(fmt="sha256")
        preview = fx.preview()
        fx.preview(approval=preview["plan_sha256"])
        before = fx.contents(fx.repo)
        result = self.check(fx, preview)
        self.assertEqual(result["status"], "matched")
        self.assertEqual(len(result["candidate"]["expected_commit"]), 64)
        self.assertEqual(fx.contents(fx.repo), before)

    def test_common_directory_lock_excludes_cooperating_check(self):
        fx = self.fixture()
        preview = fx.preview()
        before = fx.contents(fx.repo)
        with collect.fleet.directory_fd(fx.repo / ".git") as fd:
            collect.lock(fd)
            with self.assertRaisesRegex(collect.fleet.Refused, "fleet_operation_in_progress"):
                self.check(fx, preview)
        self.assertEqual(fx.contents(fx.repo), before)

    def test_sigkill_after_real_pack_indexing_leaves_missing_candidate_and_retained_objects(self):
        self.crash_after("index-pack", "missing")

    def test_sigkill_after_real_ref_publication_is_matched_without_retry(self):
        self.crash_after("update-ref", "matched")

    def crash_after(self, operation, expected):
        fx = self.fixture()
        preview = fx.preview()
        program = f"""
import importlib.util, os, signal
from pathlib import Path
spec = importlib.util.spec_from_file_location("actual_collector", {str(SCRIPT)!r})
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)
original = c.LocalGit.run
def interrupt(instance, args, *rest, **options):
    result = original(instance, args, *rest, **options)
    if str(instance.repository) == {str(fx.repo)!r} and args[:1] == [{operation!r}]:
        os.kill(os.getpid(), signal.SIGKILL)
    return result
c.LocalGit.run = interrupt
c.integrate_collection(Path({str(fx.collection)!r}), Path({str(fx.repo)!r}), {fx.base!r},
                       "wave1", [], 90, {preview['plan_sha256']!r})
"""
        killed = subprocess.run([sys.executable, "-I", "-B", "-c", program], capture_output=True,
                                text=True, env=fx.env, timeout=30)
        self.assertEqual(killed.returncode, -signal.SIGKILL, killed.stderr)
        self.assertTrue(list((fx.repo / ".git/objects/pack").glob("*.keep")))
        before = fx.contents(fx.repo)
        result = self.check(fx, preview)
        self.assertEqual(result["candidate"]["status"], expected)
        self.assertEqual(result["status"], "matched" if expected == "matched" else "attention")
        self.assertFalse(result["destination_writes_started"])
        self.assertEqual(fx.contents(fx.repo), before)

    def test_cli_check_is_exclusive_read_only_and_has_distinct_exit_codes(self):
        fx = self.fixture()
        preview = fx.preview()
        before = fx.contents(fx.repo)
        for args in (("--check",), ("--check", "--apply", "--accept-plan", preview["plan_sha256"])):
            self.assertEqual(fx.cli(*args).returncode, 2)
        missing = fx.cli("--check", "--accept-plan", preview["plan_sha256"])
        self.assertEqual(missing.returncode, 1, missing.stderr)
        self.assertEqual(collect.decode(missing.stdout.encode())["candidate"]["status"], "missing")
        self.assertEqual(fx.contents(fx.repo), before)
        fx.preview(approval=preview["plan_sha256"])
        before = fx.contents(fx.repo)
        matched = fx.cli("--check", "--accept-plan", preview["plan_sha256"])
        self.assertEqual(matched.returncode, 0, matched.stderr)
        self.assertEqual(collect.decode(matched.stdout.encode())["candidate"]["status"], "matched")
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
