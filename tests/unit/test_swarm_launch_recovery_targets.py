#!/usr/bin/env python3
"""Explicit recovery bindings through the real CLI, with no live agents."""
import json
import shlex
import unittest

import test_swarm_launch_recovery as fixtures


class ExplicitTargetTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.RecoveryTests(methodName="runTest")
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.targets = ["--target", "1:%7", "--target", "2:%3", "--target", "3:%2"]

    def preview(self, targets=None):
        return self.fixture.invoke(*(self.targets if targets is None else targets))

    def adopt(self, preview, *, targets=None, **kwargs):
        return self.fixture.invoke(*(self.targets if targets is None else targets),
            "--adopt", "--expect-sha256", preview["review_sha256"], **kwargs)

    def helper(self, kind="bash"):
        f = self.fixture
        row = f.pane("%20", "1020", kind, "9", "1")
        row[6] = str(f.root)
        return row

    def test_explicit_slots_override_same_provider_layout_order(self):
        f = self.fixture
        before = f.intent.read_bytes()
        report = self.preview()
        self.assertEqual(report["selection"], "explicit")
        self.assertEqual([(t["slot"], t["agent_name"], t["pane"]) for t in report["targets"]],
            [(1, "Reviewer", "%7"), (2, "Builder", "%3"), (3, "Tester", "%2")])
        self.assertEqual(self.adopt(report)["status"], "ready")
        saved = json.loads(f.result.read_text())
        self.assertEqual(saved["request"], f.request)
        self.assertEqual(saved["targets"], report["targets"])
        self.assertEqual(saved["recovery"]["selection"], "explicit")
        self.assertFalse(saved["recovery"]["original_launch_verified"])
        self.assertEqual(f.intent.read_bytes(), before)
        self.assertEqual(f.result.stat().st_mode & 0o777, 0o600)

    def test_helper_shell_outside_repo_can_remain_unselected(self):
        f = self.fixture
        f.panes.append(self.helper())
        f.save_panes()
        f.invoke(code=2)  # Default mode remains strict, with no implicit filtering.
        report = self.preview()
        self.assertEqual(len(report["targets"]), 3)
        self.assertEqual(self.adopt(report)["status"], "ready")

    def test_unselected_native_agent_is_not_adopted(self):
        f = self.fixture
        f.panes.append(self.helper("codex"))
        f.save_panes()
        report = self.preview()
        self.assertNotIn("%20", [t["pane"] for t in report["targets"]])
        self.adopt(report)

    def test_bad_bindings_fail_before_observation(self):
        cases = [[], ["1:%7"], ["1:%7", "2:%3", "2:%2"],
            ["1:%7", "2:%3", "3:%7"], ["1:%7", "2:%3", "4:%2"],
            ["0:%7", "2:%3", "3:%2"], ["01:%7", "2:%3", "3:%2"],
            ["1:0.0", "2:%3", "3:%2"], ["1:%7;true", "2:%3", "3:%2"],
            ["1:%7", "2:%3", "3:%2", "4:%9"]]
        # An empty option value is invalid, whereas omitting the option is layout mode.
        cases[0] = [""]
        for values in cases:
            with self.subTest(values=values):
                args = [part for value in values for part in ("--target", value)]
                self.fixture.invoke(*args, code=2)
                self.assertEqual((self.fixture.root / "commands.jsonl").read_text(), "")
                self.assertFalse(self.fixture.result.exists())

    def test_each_slot_requires_its_own_provider_not_just_the_right_mix(self):
        self.fixture.invoke("--target", "1:%3", "--target", "2:%7", "--target", "3:%2", code=2)
        self.assertFalse(self.fixture.result.exists())

    def test_missing_selected_pane_is_not_replaced_by_another_agent(self):
        self.fixture.invoke("--target", "1:%99", "--target", "2:%3", "--target", "3:%2", code=2)
        self.assertFalse(self.fixture.result.exists())

    def test_selected_dead_shell_and_wrong_repo_panes_are_refused(self):
        f = self.fixture
        for column, value in ((7, "1"), (8, "bash"), (6, str(f.root))):
            with self.subTest(column=column):
                original = f.panes[0][column]
                f.panes[0][column] = value
                f.save_panes()
                f.invoke(*self.targets, code=2)
                self.assertFalse(f.result.exists())
                f.panes[0][column] = original

    def test_ignored_rows_cannot_hide_duplicate_or_mixed_session_identity(self):
        f = self.fixture
        for column, value in ((3, "%7"), (4, "1007"), (1, "$99"), (5, "999")):
            with self.subTest(column=column):
                row = self.helper()
                row[column] = value
                f.panes.append(row)
                f.save_panes()
                f.invoke(*self.targets, code=2)
                self.assertFalse(f.result.exists())
                f.panes.pop()

    def test_mapping_changes_invalidate_review(self):
        report = self.preview()
        other = ["--target", "1:%2", "--target", "2:%3", "--target", "3:%7"]
        self.assertNotEqual(report["review_sha256"], self.preview(other)["review_sha256"])
        self.adopt(report, targets=other, code=2)
        self.assertFalse(self.fixture.result.exists())

    def test_approval_cannot_switch_between_explicit_and_layout_selection(self):
        f = self.fixture
        normal = f.invoke()
        same = ["--target", "1:%2", "--target", "2:%3", "--target", "3:%7"]
        explicit = self.preview(same)
        self.assertEqual(normal["targets"], explicit["targets"])
        self.assertNotEqual(normal["review_sha256"], explicit["review_sha256"])
        self.adopt(normal, targets=same, code=2)
        f.invoke("--adopt", "--expect-sha256", explicit["review_sha256"], code=2)
        self.assertFalse(f.result.exists())

    def test_argument_order_is_canonical_and_copyable_command_retains_bindings(self):
        report = self.preview()
        reordered = self.targets[4:6] + self.targets[0:2] + self.targets[2:4]
        self.assertEqual(report["review_sha256"], self.preview(reordered)["review_sha256"])
        command = shlex.split(report["adopt_command"])
        self.assertEqual(command[:4], ["acfs", "swarm", "launch", "--recover"])
        self.assertEqual(self.fixture.invoke(*command[4:])["status"], "ready")

    def test_explicit_approval_survives_layout_reordering(self):
        report = self.preview()
        f = self.fixture
        f.panes[0][9], f.panes[2][9] = "0", "2"
        f.panes.reverse()
        f.save_panes()
        self.assertEqual(report["review_sha256"], self.preview()["review_sha256"])
        self.adopt(report)

    def test_selected_process_drift_prevents_publication(self):
        self.adopt(self.preview(), mode="drift", code=2)
        self.assertFalse(self.fixture.result.exists())

    def test_unselected_helper_process_drift_does_not_rebind_slots(self):
        f = self.fixture
        f.panes.insert(0, self.helper())
        f.save_panes()
        self.assertEqual(self.adopt(self.preview(), mode="drift")["status"], "ready")


if __name__ == "__main__":
    unittest.main()
