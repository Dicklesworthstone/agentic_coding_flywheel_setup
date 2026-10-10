#!/usr/bin/env python3
"""Reviewed resolutions through real Git merges, packs and create-only publication.

Fixtures and failed scratch repositories are retained. No remote/provider calls.
"""
import base64
import copy
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("integration_fixtures", Path(__file__).with_name("test_swarm_fleet_integrate.py"))
support = importlib.util.module_from_spec(spec)
spec.loader.exec_module(support)
collect, Fixture = support.collect, support.Fixture


def change(path, raw=None, mode="100644"):
    if raw is None:
        return {"path": path, "mode": "delete"}
    return {"path": path, "mode": mode, "content_base64": base64.b64encode(raw).decode()}


def step(report, changes):
    row = next(r for r in report["plan"]["result"]["steps"] if r["status"] == "conflict")
    return {k: row[k] for k in ("id", "previous_commit", "head_commit", "conflict_tree")} | {"changes": changes}


def resolution(report, changes):
    return {"schema": collect.RESOLUTIONS_SCHEMA,
            "collection_evidence_sha256": report["plan"]["collection_evidence_sha256"],
            "steps": [step(report, changes)]}


class ResolutionTests(unittest.TestCase):
    def setUp(self):
        # Fixtures inherit the umask; a login user's 0002 makes them group-writable.
        self.addCleanup(os.umask, os.umask(0o022))
        self.assertNotEqual(os.geteuid(), 0, "Exercise actual unprivileged production behavior")

    def fixture(self, fmt="sha1", later=False):
        fx = Fixture(fmt, {"file.txt": ("100644", b"base\n"), "keep.txt": ("100644", b"preserve\n")})
        for host, edits in (("left", {"file.txt": ("100644", b"left\n")}),
                            ("right", {"file.txt": ("100644", b"right\n")})):
            fx.add_host(host, fx.commit(host, [fx.base], edits))
        if later:
            fx.add_host("later", fx.commit("later", [fx.base], {"extra.txt": ("100644", b"extra\n")}))
        fx.seal()
        return fx

    def resolved(self, fx, changes=None):
        conflict = fx.preview()
        self.assertEqual(conflict["status"], "conflict")
        spec = resolution(conflict, changes if changes is not None else [change("file.txt", b"left and right\n")])
        preview = fx.preview(resolutions=spec)
        self.assertEqual(preview["status"], "preview")
        return spec, preview

    def test_conflict_report_supplies_exact_binding_without_approving_marker_tree(self):
        fx = self.fixture(later=True)
        report = fx.preview()
        row = report["plan"]["result"]["steps"][1]
        self.assertEqual(row["status"], "conflict")
        self.assertEqual(fx.text(Path(report["scratch_directory"]), "cat-file", "-t", row["conflict_tree"]), "tree")
        self.assertIsNone(report["plan_sha256"])
        self.assertIsNone(report["plan"]["result"]["candidate_commit"])
        self.assertEqual(report["plan"]["result"]["steps"][2]["status"], "not_attempted")

    def test_resolves_and_continues_later_hosts_without_changing_checkout_or_collection(self):
        fx = self.fixture(later=True)
        (fx.repo / "file.txt").write_bytes(b"dirty uncommitted bytes\n")
        (fx.repo / "private-untracked").write_text("do not include")
        before, source = fx.contents(fx.repo), fx.contents(fx.collection)
        spec, preview = self.resolved(fx)
        result, scratch = preview["plan"]["result"], Path(preview["scratch_directory"])
        self.assertEqual([r["status"] for r in result["steps"]], ["fast_forward", "resolved", "merged"])
        candidate = result["candidate_commit"]
        self.assertEqual(fx.git(scratch, "show", candidate + ":file.txt"), b"left and right\n")
        self.assertEqual(fx.git(scratch, "show", candidate + ":keep.txt"), b"preserve\n")
        self.assertEqual(fx.git(scratch, "show", candidate + ":extra.txt"), b"extra\n")
        for entry, _ in fx.entries:
            fx.git(scratch, "merge-base", "--is-ancestor", entry["snapshot"]["head_commit"], candidate)
        row = result["steps"][1]
        self.assertEqual(fx.text(scratch, "show", "-s", "--format=%P", row["result_commit"]).split(),
                         [row["previous_commit"], row["head_commit"]])
        self.assertIn("Reviewed resolution: " + row["resolution_sha256"],
                      fx.text(scratch, "show", "-s", "--format=%B", row["result_commit"]))
        self.assertEqual(fx.preview(resolutions=spec)["plan"], preview["plan"])
        self.assertEqual(fx.contents(fx.repo), before)
        self.assertEqual(fx.contents(fx.collection), source)
        self.assertFalse(preview["task_completion_verified"])

    def test_resolved_objects_publish_and_read_only_check_matches_for_both_object_formats(self):
        for fmt in ("sha1", "sha256"):
            with self.subTest(fmt=fmt):
                fx = self.fixture(fmt)
                spec, preview = self.resolved(fx)
                original = fx.contents(fx.repo)
                result = fx.preview(resolutions=spec, approval=preview["plan_sha256"])
                candidate = result["plan"]["result"]["candidate_commit"]
                self.assertEqual(result["status"], "integrated")
                self.assertEqual(fx.text(fx.repo, "rev-parse", "refs/acfs/integrations/wave1"), candidate)
                self.assertEqual(fx.git(fx.repo, "show", candidate + ":file.txt"), b"left and right\n")
                for name, value in original.items():
                    self.assertEqual(fx.contents(fx.repo)[name], value)
                before = fx.contents(fx.repo)
                checked = fx.preview(resolutions=spec, approval=preview["plan_sha256"], check=True)
                self.assertEqual(checked["status"], "matched")
                self.assertFalse(checked["destination_writes_started"])
                self.assertEqual(fx.contents(fx.repo), before)
                with self.assertRaisesRegex(collect.fleet.Refused, "review_ref_already_exists"):
                    fx.preview(resolutions=spec, approval=preview["plan_sha256"])

    def test_changed_resolution_bytes_cannot_reuse_approval(self):
        fx = self.fixture()
        spec, preview = self.resolved(fx)
        before = fx.contents(fx.repo)
        spec["steps"][0]["changes"][0] = change("file.txt", b"different decision\n")
        with self.assertRaisesRegex(collect.fleet.Refused, "integration_approval_mismatch"):
            fx.preview(resolutions=spec, approval=preview["plan_sha256"])
        self.assertEqual(fx.contents(fx.repo), before)

    def test_missing_explicit_conflicted_path_is_not_assumed_resolved(self):
        fx = self.fixture()
        report = fx.preview()
        spec = resolution(report, [change("unrelated.txt", b"not a resolution\n")])
        with self.assertRaisesRegex(collect.fleet.Refused, "resolution_missing_conflicted_path"):
            fx.preview(resolutions=spec)

    def test_collection_parent_head_and_conflict_tree_are_exactly_bound(self):
        fx = self.fixture()
        spec, _ = self.resolved(fx)
        before = fx.contents(fx.repo)
        for field in ("previous_commit", "head_commit", "conflict_tree", "collection_evidence_sha256"):
            with self.subTest(field=field):
                invalid = copy.deepcopy(spec)
                if field == "collection_evidence_sha256":
                    invalid[field] = "f" * 64
                else:
                    invalid["steps"][0][field] = fx.base
                with self.assertRaises(collect.fleet.Refused):
                    fx.preview(resolutions=invalid)
        self.assertEqual(fx.contents(fx.repo), before)

    def test_multiple_conflicts_can_be_resolved_incrementally_without_digest_cycle(self):
        fx = self.fixture()
        # Add a later diverging host to a new collection, without editing the
        # existing immutable collection or deleting its original artifacts.
        fx.add_host("third", fx.commit("third", [fx.base], {"file.txt": ("100644", b"third\n")}))
        fx.collection = fx.root / "three-host-collection"
        fx.seal()
        first = fx.preview()
        spec = resolution(first, [change("file.txt", b"left and right\n")])
        second = fx.preview(resolutions=spec)
        self.assertEqual(second["status"], "conflict")
        self.assertIsNone(second["plan_sha256"])
        first_resolved = second["plan"]["result"]["steps"][1]["result_commit"]
        spec["steps"].append(step(second, [change("file.txt", b"left, right and third\n")]))
        final = fx.preview(resolutions=spec)
        self.assertEqual(final["status"], "preview")
        self.assertEqual(final["plan"]["result"]["steps"][1]["result_commit"], first_resolved)
        self.assertEqual([s["status"] for s in final["plan"]["result"]["steps"]],
                         ["fast_forward", "resolved", "resolved"])
        reordered = copy.deepcopy(spec)
        reordered["steps"].reverse()
        self.assertEqual(fx.preview(resolutions=reordered)["plan_sha256"], final["plan_sha256"])

    def test_binary_contents_modes_and_symlink_are_raw_git_objects(self):
        fx = self.fixture()
        raw = b"binary\0\xff\xfe\r\n"
        spec, report = self.resolved(fx, [change("file.txt", raw, "100755"),
                                       change("pointer", b"file.txt", "120000")])
        scratch, candidate = Path(report["scratch_directory"]), report["plan"]["result"]["candidate_commit"]
        self.assertEqual(fx.git(scratch, "show", candidate + ":file.txt"), raw)
        self.assertIn("100755 blob", fx.text(scratch, "ls-tree", candidate, "file.txt"))
        self.assertIn("120000 blob", fx.text(scratch, "ls-tree", candidate, "pointer"))
        self.assertEqual(fx.git(scratch, "show", candidate + ":pointer"), b"file.txt")
        spec["steps"][0]["changes"].reverse()
        self.assertEqual(fx.preview(resolutions=spec)["plan_sha256"], report["plan_sha256"])

    def test_modify_delete_conflict_can_choose_deletion_without_losing_other_work(self):
        fx = Fixture()
        fx.add_host("edit", fx.commit("edit", [fx.base], {"file.txt": ("100644", b"edited\n")}))
        fx.add_host("delete", fx.commit("delete", [fx.base], {"file.txt": None, "other": ("100644", b"keep\n")}))
        fx.seal()
        spec, report = self.resolved(fx, [change("file.txt")])
        scratch, candidate = Path(report["scratch_directory"]), report["plan"]["result"]["candidate_commit"]
        self.assertEqual(fx.git(scratch, "ls-tree", candidate, "file.txt"), b"")
        self.assertEqual(fx.git(scratch, "show", candidate + ":other"), b"keep\n")
        self.assertEqual(fx.preview(resolutions=spec, approval=report["plan_sha256"])["status"], "integrated")

    def test_nonconflicting_host_cannot_silently_apply_or_ignore_a_resolution(self):
        fx = self.fixture()
        spec, _ = self.resolved(fx)
        spec["steps"][0].update(id="left", head_commit=fx.entries[0][0]["snapshot"]["head_commit"])
        with self.assertRaisesRegex(collect.fleet.Refused, "resolution_for_nonconflicting_host"):
            fx.preview(resolutions=spec)

    def test_external_merge_driver_in_resolution_attributes_is_refused(self):
        fx = self.fixture(later=True)
        report = fx.preview()
        spec = resolution(report, [change("file.txt", b"resolved\n"), change(".gitattributes", b"* merge=external\n")])
        before = fx.contents(fx.repo)
        with self.assertRaisesRegex(collect.fleet.Refused, "external_merge_driver_not_supported"):
            fx.preview(resolutions=spec)
        self.assertEqual(fx.contents(fx.repo), before)

    def test_schema_rejects_duplicates_invalid_paths_modes_and_noncanonical_bytes(self):
        fx = self.fixture()
        spec, _ = self.resolved(fx)
        variants = []
        for path in ("../outside", "/absolute", "x//y", ".git/config", "nul\0path"):
            bad = copy.deepcopy(spec)
            bad["steps"][0]["changes"][0]["path"] = path
            variants.append(bad)
        for text in ("!", "AB==", "aGVsbG8=\n", 7):
            bad = copy.deepcopy(spec)
            bad["steps"][0]["changes"][0]["content_base64"] = text
            variants.append(bad)
        bad = copy.deepcopy(spec)
        bad["steps"][0]["changes"][0]["mode"] = "160000"
        variants.append(bad)
        bad = copy.deepcopy(spec)
        bad["steps"].append(copy.deepcopy(bad["steps"][0]))
        variants.append(bad)
        bad = copy.deepcopy(spec)
        bad["steps"][0]["changes"].append(copy.deepcopy(bad["steps"][0]["changes"][0]))
        variants.append(bad)
        before = fx.contents(fx.repo)
        for index, bad in enumerate(variants):
            with self.subTest(index=index), self.assertRaises(collect.fleet.Refused):
                fx.preview(resolutions=bad)
        self.assertEqual(fx.contents(fx.repo), before)

    def test_cli_preview_apply_and_check_require_original_private_resolution_content(self):
        fx = self.fixture()
        spec, preview = self.resolved(fx)
        path = fx.root / "resolutions.json"
        path.write_bytes(collect.encoded(spec))
        path.chmod(0o600)
        args = ("--resolutions", str(path))
        result = fx.cli(*args)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(collect.decode(result.stdout.encode())["plan_sha256"], preview["plan_sha256"])
        applied = fx.cli(*args, "--apply", "--accept-plan", preview["plan_sha256"])
        self.assertEqual(applied.returncode, 0, applied.stdout + applied.stderr)
        checked = fx.cli(*args, "--check", "--accept-plan", preview["plan_sha256"])
        self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
        path.chmod(0o644)
        refused = fx.cli(*args, "--check", "--accept-plan", preview["plan_sha256"])
        self.assertEqual(refused.returncode, 2)
        self.assertEqual(collect.decode(refused.stdout.encode())["code"], "unsafe_input_file")


if __name__ == "__main__":
    if os.geteuid() == 0:
        os.setgroups([])
        os.setgid(65534)
        os.setuid(65534)
        os.execv(sys.executable, [sys.executable, "-B", __file__, *sys.argv[1:]])
    unittest.main()
