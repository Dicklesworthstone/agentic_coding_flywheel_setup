"""Lost startup response -> approved recovery -> receipt status -> scoped handoff."""
import json
import os
import pwd
from pathlib import Path
import shlex
import shutil
import subprocess
import unittest

import test_swarm_launch_handoff as handoff

ROOT, PACKET, ASSIGN, PROBE = handoff.ROOT, handoff.PACKET, handoff.ASSIGN, handoff.PROBE

LIST_PANES = r'''elif name == "tmux":
    if args[0] == "list-panes":
        assert args[:5] == ["list-panes", "-s", "-t", "=project", "-F"]
        assert len(args) == 6
        agents = json.loads((root / "spawned").read_text())
        for i, agent in enumerate(agents):
            fields = ["project", "$1", "12345", "%" + str(42+i), str(1000+i),
                      "900", str(root / "repo"), "0", agent["type"], "0", str(i)]
            if mode == "pane-replaced": fields[4] = str(2000+i)
            print("\t".join(fields))
        sys.exit(0)
'''


class RecoveryIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.case = handoff.HandoffTests("test_missing_intent_never_launches_or_prepares")
        self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.root = self.case.root
        self.helper = self.case.lib / "swarm_launch_recovery.py"
        shutil.copyfile(ROOT / "scripts/lib/swarm_launch_recovery.py", self.helper)
        fixture = PROBE.replace('elif name == "tmux":\n', LIST_PANES)
        original = '        (root / "spawned").write_text(json.dumps(agents))\n'
        assert original in fixture
        fixture = fixture.replace(original, original + '        if mode == "lost-spawn-reply": sys.exit(1)\n')
        mutation = r'''    if mode == "reconcile-result-race":
        result = root / "launch.json.result.json"
        content = json.loads(result.read_text())
        content["recovery"]["review_sha256"] = "0" * 64
        result.write_text(json.dumps(content))
    if mode == "reconcile-intent-race":
        result = root / "launch.json"
        content = json.loads(result.read_text())
        content["request"]["workload"] = "heavy"
        result.write_text(json.dumps(content))
'''
        fixture = fixture.replace('    assert args[:3] == ["display-message","-p","-t"]\n',
            mutation + '    assert args[:3] == ["display-message","-p","-t"]\n')
        for name in ("tmux", "ntm"):
            (self.case.bin / name).write_text(fixture)

    def unconfirmed(self):
        code, preview = self.case.invoke(self.case.launch_args)
        self.assertEqual(code, 0, preview)
        code, report = self.case.invoke([*self.case.launch_args, "--launch", "--expect-sha256",
                                        preview["review_sha256"]], "lost-spawn-reply")
        self.assertEqual((code, report["status"]), (1, "unconfirmed"), report)
        self.assertTrue((self.root / "spawned").exists())
        self.assertTrue(self.case.receipt.exists())
        self.assertFalse(Path(str(self.case.receipt) + ".result.json").exists())
        return preview["review_sha256"]

    def recover(self, *extra, mode="ok"):
        return self.case.invoke(["--recover", "--receipt", str(self.case.receipt), *extra], mode)

    def adopt(self):
        code, preview = self.recover()
        self.assertEqual((code, preview["status"]), (0, "preview"), preview)
        code, result = self.recover("--adopt", "--expect-sha256", preview["review_sha256"])
        self.assertEqual((code, result["status"]), (0, "ready"), result)
        return result

    def reconcile(self, mode="ok"):
        return self.case.invoke(["--reconcile", "--receipt", str(self.case.receipt)], mode)

    def assert_one_spawn_and_no_sends(self):
        calls = self.case.calls()
        spawns = [args for name, args in calls if name == "ntm" and "--robot-spawn=project" in args
                  and "--dry-run" not in args]
        self.assertEqual(len(spawns), 1)
        self.assertFalse(any(name == "ntm" and any("robot-send" in arg for arg in args) for name, args in calls))

    def test_lost_response_recovers_and_ordinary_launch_only_reconciles(self):
        original_review = self.unconfirmed()
        before = self.case.receipt.read_bytes()
        code, report = self.reconcile()
        self.assertEqual((code, report["status"]), (1, "unconfirmed"), report)
        self.assertEqual(shlex.split(report["recovery_preview_command"])[3], "--recover")
        self.adopt()
        code, report = self.case.invoke([*self.case.launch_args, "--launch", "--expect-sha256", original_review])
        self.assertEqual((code, report["status"]), (0, "ready"), report)
        self.assertTrue(report["reconciled_only"])
        self.assertFalse(report["starts_agents"])
        self.assertEqual(self.case.receipt.read_bytes(), before)
        self.assert_one_spawn_and_no_sends()

    def test_receipt_only_reconciliation_retains_adoption_provenance(self):
        self.unconfirmed()
        self.adopt()
        before = len(self.case.calls())
        code, report = self.reconcile()
        self.assertEqual((code, report["status"]), (0, "ready"), report)
        self.assertFalse(report["original_launch_verified"])
        self.assertFalse(report["recovery_provenance"]["original_launch_verified"])
        self.assertEqual(report["preparation_targets"], ["1:CodeSlot:codex:%43", "2:ReviewSlot:claude:%42"])
        self.assertEqual([name for name, _ in self.case.calls()[before:]], ["tmux", "tmux"])
        self.assert_one_spawn_and_no_sends()

    def test_recovered_launch_handoff_keeps_native_slot_bindings(self):
        self.unconfirmed()
        self.adopt()
        code, report = self.case.handoff()
        self.assertEqual((code, report["status"]), (0, "prepared"), report)
        received = json.loads((self.root / "preparation-inputs").read_text())
        self.assertEqual(received["targets"], ["1:BlueLake:codex:%43", "2:RedFox:claude:%42"])
        self.assertFalse(report["launch"]["starts_agents"])
        self.assert_one_spawn_and_no_sends()

    def test_recovered_session_produces_real_scoped_packets(self):
        self.unconfirmed()
        self.adopt()
        shutil.copyfile(PACKET, self.case.lib / "swarm_packet.sh")
        shutil.copyfile(ASSIGN, self.case.lib / "swarm_assign.sh")
        beads = self.root / "beads.json"
        beads.write_text(json.dumps([
            {"id":"bd-api","title":"Implement endpoint","description":"Return 200","status":"open","priority":1,
             "issue_type":"task","labels":["implementation"]},
            {"id":"bd-doc","title":"Document endpoint","description":"Explain usage","status":"open","priority":2,
             "issue_type":"task","labels":["documentation"]}]))
        triage = self.root / "triage.json"
        triage.write_text("{}")
        code, report = self.case.handoff(extra=("--roles", "implementation,documentation",
            "--ready-file", str(beads), "--beads-file", str(beads), "--triage-file", str(triage)))
        self.assertEqual((code, report["status"]), (0, "prepared"), report)
        batch = json.loads((self.case.output / "batch.json").read_text())
        self.assertEqual([d["pane"] for d in batch["deliveries"]], ["%43", "%42"])
        self.assertEqual([d["agent_type"] for d in batch["deliveries"]], ["codex", "claude"])
        self.assertIn("Return 200", json.loads((self.case.output / "packet-01.json").read_text())["packet_markdown"])
        self.assertFalse(list(self.case.output.glob("*.receipt.json")))
        self.assert_one_spawn_and_no_sends()

    def test_recovery_rejects_changed_panes_and_old_launch_approval(self):
        old_review = self.unconfirmed()
        code, _ = self.recover("--adopt", "--expect-sha256", old_review)
        self.assertEqual(code, 2)
        code, preview = self.recover()
        self.assertEqual(code, 0)
        code, _ = self.recover("--adopt", "--expect-sha256", preview["review_sha256"], mode="pane-replaced")
        self.assertEqual(code, 2)
        self.assertFalse(Path(str(self.case.receipt) + ".result.json").exists())
        self.assert_one_spawn_and_no_sends()

    def test_missing_helper_fails_closed_without_searching_path(self):
        self.helper.rename(self.root / "retained-helper.py")
        path_helper = self.case.bin / "swarm_launch_recovery.py"
        path_helper.write_text('raise AssertionError("must not run")')
        code, report = self.recover("--help")
        self.assertEqual(code, 2, report)
        self.assertEqual(self.case.calls(), [])

    def test_symlinked_helper_fails_closed(self):
        retained = self.root / "retained-helper.py"
        self.helper.rename(retained)
        self.helper.symlink_to(retained)
        code, report = self.recover("--help")
        self.assertEqual(code, 2, report)
        self.assertEqual(self.case.calls(), [])

    def test_reconciliation_without_intent_is_inert(self):
        code, report = self.reconcile()
        self.assertEqual(code, 2, report)
        self.assertEqual(self.case.calls(), [])
        self.assertFalse(self.case.receipt.exists())

    def test_completed_original_launch_reconciles_without_recovery(self):
        self.case.launch()
        code, report = self.reconcile()
        self.assertEqual((code, report["status"]), (0, "ready"), report)
        self.assertNotIn("recovery_provenance", report)
        self.assertFalse(report["starts_agents"])
        self.assert_one_spawn_and_no_sends()

    def test_reconciliation_never_adopts_replacement_processes(self):
        self.unconfirmed()
        self.adopt()
        before = Path(str(self.case.receipt) + ".result.json").read_bytes()
        code, report = self.reconcile(mode="pane-replaced")
        self.assertEqual((code, report["status"]), (1, "unconfirmed"), report)
        self.assertNotIn("recovery_preview_command", report)
        self.assertEqual(Path(str(self.case.receipt) + ".result.json").read_bytes(), before)
        self.assert_one_spawn_and_no_sends()

    def test_reconciliation_rejects_launch_flags_without_mutation(self):
        self.unconfirmed()
        before = self.case.calls()
        result = subprocess.run(["bash", str(self.case.script), "--reconcile", "--receipt", str(self.case.receipt),
                                 "--launch"], env=self.case.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.case.calls(), before)
        self.assert_one_spawn_and_no_sends()

    def test_reconciliation_projects_only_known_recovery_fields(self):
        self.unconfirmed()
        self.adopt()
        path = Path(str(self.case.receipt) + ".result.json")
        content = json.loads(path.read_text())
        content["recovery"]["private_note"] = "DO_NOT_REPORT_PRIVATE_NOTE"
        path.write_text(json.dumps(content))
        code, report = self.reconcile()
        self.assertEqual((code, report["status"]), (0, "ready"), report)
        self.assertNotIn("DO_NOT_REPORT", json.dumps(report))
        self.assert_one_spawn_and_no_sends()

    def test_invalid_recovery_provenance_is_not_reported_as_ready(self):
        self.unconfirmed()
        self.adopt()
        path = Path(str(self.case.receipt) + ".result.json")
        content = json.loads(path.read_text())
        content["recovery"]["original_launch_verified"] = True
        path.write_text(json.dumps(content))
        code, report = self.reconcile()
        self.assertEqual((code, report["status"]), (1, "unconfirmed"), report)
        self.assertNotIn("targets", report)
        self.assert_one_spawn_and_no_sends()

    def test_changing_saved_result_is_not_reported_as_ready(self):
        self.unconfirmed()
        self.adopt()
        code, report = self.reconcile(mode="reconcile-result-race")
        self.assertEqual((code, report["status"]), (1, "unconfirmed"), report)
        self.assertNotIn("targets", report)
        self.assert_one_spawn_and_no_sends()

    def test_changing_saved_intent_is_not_reported_as_ready(self):
        self.unconfirmed()
        self.adopt()
        code, report = self.reconcile(mode="reconcile-intent-race")
        self.assertEqual((code, report["status"]), (1, "unconfirmed"), report)
        self.assertNotIn("targets", report)
        self.assert_one_spawn_and_no_sends()

    def install_launcher(self):
        home = self.root / "installed-acfs"
        home.mkdir(mode=0o700)
        lines = (ROOT / "install.sh").read_text().splitlines()
        copies = []
        for name in ("swarm_launch.sh", "swarm_launch_recovery.py"):
            found = [line for line in lines if line.strip().startswith('try_step "Installing ' + name + '" install_asset ')]
            self.assertEqual(len(found), 1)
            copies.extend(found)
        script = 'set -euo pipefail\nACFS_HOME="$1"\nmkdir -p "$ACFS_HOME/scripts/lib"\n'
        script += 'try_step() { shift; "$@"; }\ninstall_asset() { cp -- "$1" "$2"; }\n'
        script += "\n".join(copies)
        subprocess.run(["bash", "-c", script, "installed-recovery", str(home)], cwd=ROOT,
            capture_output=True, check=True, timeout=10)
        for name in ("swarm_launch.sh", "swarm_launch_recovery.py"):
            self.assertEqual((home / "scripts/lib" / name).read_bytes(), (ROOT / "scripts/lib" / name).read_bytes())
        return home

    def test_fresh_install_copy_recovers_and_reconciles_saved_session(self):
        self.unconfirmed()
        home = self.install_launcher()
        self.case.script = home / "scripts/lib/swarm_launch.sh"
        self.adopt()
        code, report = self.reconcile()
        self.assertEqual((code, report["status"]), (0, "ready"), report)
        self.assert_one_spawn_and_no_sends()

    def test_installed_doctor_cli_routes_to_recovery_and_reconciliation(self):
        home = self.install_launcher()
        doctor = home / "scripts/lib/doctor.sh"
        shutil.copyfile(ROOT / "scripts/lib/doctor.sh", doctor)
        env = dict(self.case.env, ACFS_HOME=str(home), TARGET_USER=pwd.getpwuid(os.geteuid()).pw_name)
        for flag, expected in (("--recover", "--adopt"), ("--reconcile", "--receipt")):
            process = subprocess.run(["bash", str(doctor), "swarm", "launch", flag, "--help"],
                env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
            self.assertIn(expected, process.stdout)
        self.assertEqual(self.case.calls(), [])

    def test_cli_exposes_recovery_and_reconciliation_help(self):
        for mode, flag in (("--recover", "--adopt"), ("--reconcile", "--receipt")):
            result = subprocess.run(["bash", str(self.case.script), mode, "--help"], env=self.case.env,
                capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(flag, result.stdout)
        self.assertEqual(self.case.calls(), [])


if __name__ == "__main__":
    unittest.main()
