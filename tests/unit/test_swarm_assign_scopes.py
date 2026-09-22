"""Exercise the actual Bash/jq allocator; no services or agents are launched."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/lib/swarm_assign.sh"


def issue(bead, **values):
    return {"id": bead, "title": bead, "status": "open", "priority": 2,
            "issue_type": "task", **values}


class ScopeAssignmentTests(unittest.TestCase):
    def setUp(self):
        # Retain artifacts for inspection; never clean a project directory.
        self.work = Path(tempfile.mkdtemp(prefix="acfs-assign-scopes-"))
        self.ready = self.save("ready", [issue("bd-a"), issue("bd-b"), issue("bd-c")])
        self.triage = self.save("triage", {})
        self.scopes = self.save("scopes", {"schema_version": 1, "scopes": {
            "bd-a": ["src/**"], "bd-b": ["src/a.py"], "bd-c": ["tests/**"]}})
        self.env = dict(os.environ)
        self.env["PYTHONDONTWRITEBYTECODE"] = "1"

    def save(self, name, value):
        path = self.work / (name + ".json")
        path.write_text(json.dumps(value))
        return path

    def run_cli(self, *args, ok=True, scoped=True, live=False):
        command = ["bash", str(SCRIPT), "--json"]
        if not live:
            command += ["--ready-file", str(self.ready), "--triage-file", str(self.triage)]
        if scoped:
            command += ["--scopes-file", str(self.scopes)]
        if "--agents" not in args and "--roles" not in args:
            command += ["--agents", "3"]
        result = subprocess.run(command + list(args), capture_output=True, text=True,
                                env=self.env, cwd=self.work, timeout=25)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(result.stdout, "", "failed input must not publish assignments")
        return result

    def ids(self, report):
        return [a["bead_id"] for a in report["assignments"]]

    def test_conflicting_high_ranked_work_is_replaced_by_independent_work(self):
        report = self.run_cli()
        self.assertEqual(self.ids(report), ["bd-a", "bd-c"])
        self.assertEqual(report["idle_agents"][0]["reason"], "no-independent-ready-bead")
        self.assertEqual(report["unassigned_ready_beads"][0]["admission"], {
            "reason": "scope-conflict", "blocking_beads": ["bd-a"]})
        self.assertEqual(report["scope_admission"]["status"], "warn")
        self.assertFalse(any(report["mutations"].values()))
        self.assertFalse(report["scope_admission"]["launch_authorized"])

    def test_explicit_scopes_are_not_augmented_with_shared_inferred_paths(self):
        self.save("ready", [issue("bd-a", labels=["swarm"]), issue("bd-b", labels=["swarm"])])
        self.save("scopes", {"schema_version": 1, "scopes": {"bd-a": ["src/a"], "bd-b": ["src/b"]}})
        report = self.run_cli()
        self.assertEqual(self.ids(report), ["bd-a", "bd-b"])
        self.assertEqual(report["assignments"][0]["reservation_surfaces"], ["src/a"])
        self.assertEqual(report["assignments"][0]["scope_source"], "explicit")

    def test_role_matching_retained(self):
        self.save("ready", [issue("bd-impl", issue_type="feature", labels=["swarm"]),
                            issue("bd-review", issue_type="bug", labels=["review"]),
                            issue("bd-test", labels=["tests"]), issue("bd-docs", labels=["docs"])])
        self.save("scopes", {"schema_version": 1, "scopes": {
            b: [b + "/**"] for b in ("bd-impl", "bd-review", "bd-test", "bd-docs")}})
        self.save("triage", {"recommendations": [{"id": "bd-impl", "score": 0.3},
                                                {"id": "bd-docs", "score": 0.1}]})
        report = self.run_cli("--roles", "implementation,review,testing,docs")
        self.assertEqual(self.ids(report), ["bd-impl", "bd-review", "bd-test", "bd-docs"])
        self.assertEqual([x["role"] for x in report["assignments"]],
                         ["implementation", "review", "testing", "documentation"])

    def test_missing_scopes_do_not_fall_back_to_guesses(self):
        self.save("scopes", {"schema_version": 1, "scopes": {"bd-b": ["src/b"]}})
        report = self.run_cli()
        self.assertEqual(self.ids(report), ["bd-b"])
        self.assertTrue(all(x["admission"]["reason"] == "missing-scope" for x in report["unassigned_ready_beads"]))

    def test_epics_are_deferred_even_with_declared_scopes(self):
        self.save("ready", [issue("bd-a", issue_type="epic", priority=0), issue("bd-c")])
        report = self.run_cli()
        self.assertEqual(self.ids(report), ["bd-c"])
        self.assertEqual(report["unassigned_ready_beads"][0]["admission"]["reason"], "decompose-first")

    def test_all_conflict_partners_reported(self):
        self.save("scopes", {"schema_version": 1, "scopes": {
            "bd-a": ["src/a"], "bd-b": ["src/b"], "bd-c": ["src/*"]}})
        report = self.run_cli()
        self.assertEqual(self.ids(report), ["bd-a", "bd-b"])
        self.assertEqual(report["unassigned_ready_beads"][0]["admission"]["blocking_beads"], ["bd-a", "bd-b"])

    def test_intersection_cases_and_directory_boundaries(self):
        pairs = [("src/**", "src/a.py", True), ("src/a.py", "src/**", True),
                 ("src/a", "src/ab", False), ("src/**", "src2/**", False),
                 ("src/*.py", "src/*.ts", True), ("src/a*", "src/b*", False),
                 ("*", "docs/file.md", True), ("src/?.py", "src/a.py", True),
                 (".beads/issues.jsonl", ".beads/issues.jsonl", True),
                 ("src/a", "src/b", False)]
        self.save("ready", [issue("bd-a"), issue("bd-b")])
        for a, b, conflict in pairs:
            with self.subTest(a=a, b=b):
                self.save("scopes", {"schema_version": 1, "scopes": {"bd-a": [a], "bd-b": [b]}})
                self.assertEqual(len(self.ids(self.run_cli())), 1 if conflict else 2)

    def test_ready_order_does_not_change_allocation(self):
        first = self.run_cli()
        self.save("ready", [issue("bd-c"), issue("bd-b"), issue("bd-a")])
        self.assertEqual(self.ids(first), self.ids(self.run_cli()))

    def test_legacy_heuristics_are_explicitly_unchecked(self):
        self.save("ready", [issue("bd-a", labels=["swarm"]), issue("bd-b")])
        report = self.run_cli(scoped=False)
        self.assertEqual(len(report["assignments"]), 2)
        self.assertEqual(report["scope_admission"]["status"], "unchecked")
        self.assertIn("scripts/lib/swarm_*.sh", report["assignments"][0]["reservation_surfaces"])
        self.assertEqual(report["assignments"][0]["agent_mail_thread_id"], "bd-a")

    def test_empty_ready(self):
        self.save("ready", [])
        report = self.run_cli()
        self.assertEqual(report["summary"]["assigned_count"], 0)
        self.assertEqual(report["summary"]["idle_count"], 3)

    def test_blocked_and_in_progress_are_excluded(self):
        self.save("ready", [issue("bd-a"), issue("bd-b", blocked=True),
                            issue("bd-c", blocked_by=["bd-x"]), issue("bd-d", status="in_progress")])
        report = self.run_cli()
        self.assertEqual(self.ids(report), ["bd-a"])
        self.assertEqual(report["summary"]["excluded_count"], 3)

    def test_triage_cannot_hide_a_dependency_block(self):
        self.save("triage", {"recommendations": [{"id": "bd-a", "blocked_by": ["bd-x"]}]})
        report = self.run_cli()
        self.assertNotIn("bd-a", self.ids(report))
        self.assertEqual(report["excluded_beads"][0]["reason"], "blocked")

    def test_triage_enrichment_and_ranking(self):
        self.save("ready", [issue("bd-a"), issue("bd-b")])
        self.save("triage", {"triage": {"recommendations": [
            {"id": "bd-b", "score": 0.9, "unblocks": 3, "labels": ["capacity"]}]}})
        report = self.run_cli("--agents", "1", scoped=False)
        self.assertEqual(self.ids(report), ["bd-b"])
        self.assertEqual(report["assignments"][0]["labels"], ["capacity"])
        self.assertEqual(report["assignments"][0]["dependency_position"]["unblocks"], 3)
        self.assertIn("scripts/lib/capacity.sh", report["assignments"][0]["reservation_surfaces"])

    def test_duplicate_scope_keys_rejected_before_any_live_probe(self):
        self.scopes.write_text('{"schema_version":1,"scopes":{"bd-a":["src/**"],"bd-a":["docs/**"]}}')
        self.run_cli(ok=False, live=True)

    def test_malformed_scope_shapes_and_paths(self):
        invalid = [None, [], {}, {"schema_version": True, "scopes": {}},
                   {"schema_version": 2, "scopes": {}}, {"schema_version": 1, "scopes": {}, "extra": 1}]
        invalid += [{"schema_version": 1, "scopes": {"bd-a": v}} for v in
                    ([], "src/**", [1], [None], ["src/a", "src/a"], ["a"] * 33,
                     ["../src"], ["/tmp/src"], ["src//a"], ["src/./a"], ["src/"],
                     ["src/[ab].py"], ["src\\a"], ["src\nsecret"], ["a" * 257])]
        for value in invalid:
            with self.subTest(value=value):
                self.save("scopes", value)
                self.run_cli(ok=False)

    def test_duplicate_ready_ids_and_malformed_flags(self):
        for values in ([issue("bd-a"), issue("bd-a")], {}, [issue("bd-a", blocked="true")],
                       [issue("bd-a", blocked_by="bd-x")], [issue("bd-a", labels=[1])],
                       [issue("bd-a", score=float("nan"))]):
            with self.subTest(values=values):
                self.save("ready", values)
                self.run_cli(ok=False)

    def test_duplicate_json_fields_nul_and_oversized_inputs(self):
        for payload in (b'[{"id":"bd-a","blocked":true,"blocked":false}]',
                        b'[{"id":"bd-a"}]\x00', b'[]' + b' ' * 1048576,
                        b'[{"id":"bd-a","score":1e999}]'):
            self.ready.write_bytes(payload)
            self.run_cli(ok=False)

    def test_symlink_and_fifo_scope_sources_are_rejected_without_hanging(self):
        link = self.work / "link.json"
        link.symlink_to(self.scopes)
        self.scopes = link
        self.run_cli(ok=False)
        fifo = self.work / "fifo"
        os.mkfifo(fifo)
        self.scopes = fifo
        self.run_cli(ok=False)

    def test_errors_do_not_echo_secrets(self):
        self.scopes.write_text('{"private-token": "do-not-disclose", broken}')
        result = self.run_cli(ok=False)
        self.assertNotIn("do-not-disclose", result.stderr)
        self.assertNotIn("private-token", result.stderr)

    def test_large_valid_report_does_not_use_argv(self):
        self.save("ready", [issue("bd-a", description="private-note" * 24000)])
        report = self.run_cli()
        self.assertEqual(self.ids(report), ["bd-a"])
        self.assertNotIn("private-note", json.dumps(report))

    def test_decimal_counts_and_resource_bounds(self):
        self.assertEqual(self.run_cli("--agents", "008")["inputs"]["requested_agents"], 8)
        self.assertEqual(self.run_cli("--roles", "impl:008")["inputs"]["requested_agents"], 8)
        for args in (("--agents", "0"), ("--agents", "101"), ("--agents", "9" * 40),
                     ("--roles", "impl:101"), ("--roles", "impl:60,docs:60"),
                     ("--roles", ",impl"), ("--roles", "impl,"), ("--roles", "impl,,docs")):
            self.run_cli(*args, ok=False)

    def test_markdown_explains_deferred_work(self):
        result = subprocess.run(["bash", str(SCRIPT), "--agents", "3", "--ready-file", str(self.ready),
                                 "--triage-file", str(self.triage), "--scopes-file", str(self.scopes)],
                                text=True, capture_output=True, timeout=25)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("scope-conflict; blocking Beads: bd-a", result.stdout)
        self.assertIn("not checked", result.stdout)

    def test_live_reads_use_only_br_ready_and_bv_triage(self):
        tools = self.work / "bin"
        tools.mkdir()
        marker = self.work / "calls"
        for name, args, payload in (("br", "ready --json", self.ready),
                                    ("bv", "--robot-triage", self.triage)):
            tool = tools / name
            tool.write_text('#!/bin/sh\n[ "$*" = "' + args + '" ] || exit 91\n'
                            + 'echo ' + name + ' >> "' + str(marker) + '"\n'
                            + '/bin/cat "' + str(payload) + '"\n')
            tool.chmod(0o755)
        for name in ("am", "ntm", "tmux", "rch", "ru"):
            tool = tools / name
            tool.write_text('#!/bin/sh\necho mutation >> "' + str(marker) + '"\nexit 92\n')
            tool.chmod(0o755)
        self.env["PATH"] = str(tools) + os.pathsep + self.env["PATH"]
        report = self.run_cli(live=True)
        self.assertEqual(self.ids(report), ["bd-a", "bd-c"])
        self.assertEqual(marker.read_text().splitlines(), ["br", "bv"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
