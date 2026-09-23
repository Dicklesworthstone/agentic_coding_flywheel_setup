"""Launch-receipt handoff through the actual Bash/Python CLI."""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
LAUNCH = ROOT / "scripts/lib/swarm_launch.sh"
PACKET = ROOT / "scripts/lib/swarm_packet.sh"
ASSIGN = ROOT / "scripts/lib/swarm_assign.sh"

PROBE = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ["HANDOFF_ROOT"])
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
mode = os.environ.get("HANDOFF_MODE", "ok")
assert pathlib.Path.cwd() == root / "repo"
with (root / "calls").open("a") as f:
    f.write(json.dumps([name, args]) + "\n")
def flag(key):
    return args[args.index(key) + 1]
if name == "plan":
    n = int(flag("--agents"))
    print(json.dumps({"schema_version":1,"status":"pass","exit_code":0,
        "requested_agents":n,"workload":flag("--workload"),"safe_agents":32,"recommended_agents":32,
        "quiesce_advisory":{"recommendation":"proceed"},"recommendation":"launch",
        "checks":[{"id":"capacity","status":"pass"}]}))
elif name == "ntm":
    def opt(key): return next(a.split("=",1)[1] for a in args if a.startswith(key + "="))
    assert "--spawn-safety" in args and "--spawn-no-user" in args
    assert not any("robot-send" in a for a in args)
    types = ["claude"] * int(opt("--spawn-cc")) + ["codex"] * int(opt("--spawn-cod"))
    agents = [{"pane":"0."+str(i),"type":t,"ready":True} for i,t in enumerate(types)]
    dry = "--dry-run" in args
    if not dry:
        assert (root / "launch.json").is_file()
        (root / "spawned").write_text(json.dumps(agents))
    print(json.dumps({"success":True,"session":"project","working_dir":str(root / "repo"),
        "admission":{"decision":"admit"},"dry_run":dry,
        "would_create":agents if dry else [],"agents":[] if dry else agents}))
elif name == "tmux":
    assert args[:3] == ["display-message","-p","-t"]
    if mode == "missing-pane": sys.exit(1)
    target = args[3]
    i = int(target.rsplit(".",1)[1]) if target.startswith("=") else int(target[1:])-42
    agents = json.loads((root / "spawned").read_text())
    server = "901" if mode == "server-changed" or (mode == "change-during" and (root / "prepared-called").exists()) else "900"
    pid = str(2000+i) if mode == "pane-replaced" else str(1000+i)
    kind = "bash" if mode == "shell" else agents[i]["type"]
    cwd = root if mode == "wrong-repo" else root / "repo"
    print("\t".join(["project","$1","12345","%"+str(42+i),pid,server,str(cwd),"0",kind]))
elif name == "packet":
    assert args[0] == "--prepare-batch" and "--send" not in args
    output = pathlib.Path(args[1])
    assert flag("--repo") == str(root / "repo") and flag("--session") == "project"
    assert "--no-live-context" in args
    received = {key: json.loads(pathlib.Path(flag(key)).read_text()) for key in
        ("--scopes-file","--assignments","--ready-file","--triage-file","--beads-file") if key in args}
    targets = [args[i+1] for i,a in enumerate(args) if a == "--target"]
    (root / "preparation-inputs").write_text(json.dumps({"targets":targets,"sources":received}))
    (root / "prepared-called").write_text("yes")
    if mode == "preparation-failed":
        print("private failure",file=sys.stderr); print('{"schema":"acfs.packet-delivery.v1","status":"error"}'); sys.exit(2)
    if mode == "no-work":
        print(json.dumps({"schema":"acfs.packet-preparation.v1","status":"no_work","delivery_count":0,
            "sends_prompt":False,"directory_created":False,"idle_targets":targets})); sys.exit(1)
    output.mkdir(mode=0o700)
    (output / "batch.json").write_text("{}")
    print(json.dumps({"schema":"acfs.packet-preparation.v1","status":"prepared","directory":str(output),
        "delivery_count":len(targets),"sends_prompt":False,
        "preview_command":"acfs swarm packet --deliver-batch " + str(output / "batch.json")}))
else:
    raise AssertionError(name)
'''


class HandoffTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="acfs-receipt-handoff-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.lib = self.root / "lib"
        self.lib.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        if Path("/usr/bin/python3").is_file():
            (self.bin / "python3").symlink_to("/usr/bin/python3")
        self.script = self.lib / "swarm_launch.sh"
        shutil.copyfile(LAUNCH, self.script)
        for name in ("ntm","tmux","plan","packet"):
            path = self.bin / name
            path.write_text(PROBE)
            path.chmod(0o755)
        for kind, name in (("plan","swarm_plan.sh"),("packet","swarm_packet.sh")):
            (self.lib / name).write_text('#!/bin/bash\nexec ' + shlex.quote(str(self.bin / kind)) + ' "$@"\n')
        self.env = dict(os.environ, PATH=str(self.bin)+os.pathsep+os.environ["PATH"], HANDOFF_ROOT=str(self.root))
        self.receipt = self.root / "launch.json"
        self.output = self.root / "work bundle"
        self.scopes = self.root / "scopes.json"
        self.scopes.write_text('{"schema_version":1,"scopes":{"bd-api":["src/api/**"],"bd-doc":["docs/**"]}}')
        self.assignments = self.root / "assignments.json"
        self.assignments.write_text(json.dumps({"assignments":[{"slot":2}]}))
        self.launch_args = ["--repo",str(self.repo),"--session","project","--receipt",str(self.receipt),
                            "--agent","CodeSlot:codex","--agent","ReviewSlot:claude"]

    def invoke(self, args, mode="ok"):
        result = subprocess.run(["bash",str(self.script),*args], cwd=self.root,
            env=dict(self.env,HANDOFF_MODE=mode), capture_output=True,text=True,timeout=25)
        self.assertEqual(result.stderr,"",result.stderr)
        return result.returncode, json.loads(result.stdout)

    def launch(self):
        code, preview = self.invoke(self.launch_args)
        self.assertEqual(code,0,preview)
        code, result = self.invoke([*self.launch_args,"--expect-sha256",preview["review_sha256"],"--launch"])
        self.assertEqual((code,result["status"]),(0,"ready"),result)
        return result

    def handoff(self, mode="ok", identities=None, saved=False, extra=()):
        args = ["--prepare-batch",str(self.output),"--receipt",str(self.receipt),"--no-live-context"]
        args += ["--assignments",str(self.assignments)] if saved else ["--scopes-file",str(self.scopes)]
        for value in identities or ("2:RedFox","1:BlueLake"):
            args += ["--identity",value]
        return self.invoke([*args,*extra],mode)

    def calls(self):
        path = self.root / "calls"
        return [json.loads(s) for s in path.read_text().splitlines()] if path.exists() else []

    def test_existing_launch_to_preparation_preserves_slots_and_providers(self):
        self.launch()
        before = len(self.calls())
        saved = self.receipt.read_bytes()
        code, result = self.handoff()
        self.assertEqual((code,result["status"]),(0,"prepared"),result)
        received = json.loads((self.root / "preparation-inputs").read_text())
        self.assertEqual(received["targets"],["1:BlueLake:codex:%43","2:RedFox:claude:%42"])
        self.assertEqual(received["sources"]["--scopes-file"],json.loads(self.scopes.read_text()))
        self.assertEqual([name for name,_ in self.calls()[before:]],["tmux","tmux","packet","tmux","tmux"])
        self.assertEqual(self.receipt.read_bytes(),saved)
        self.assertFalse(result["launch"]["starts_agents"])
        self.assertFalse(result["launch"]["work_dispatched"])
        self.assertFalse(result["launch"]["agent_mail_registration_verified"])

    def test_missing_intent_never_launches_or_prepares(self):
        code, _ = self.handoff()
        self.assertEqual(code,2)
        self.assertEqual(self.calls(),[])
        self.assertFalse(self.output.exists())

    def test_unconfirmed_intent_never_adopts_existing_panes(self):
        self.launch()
        result = self.root / "launch.json.result.json"
        result.rename(self.root / "retained-result.json")
        before = len(self.calls())
        code, report = self.handoff()
        self.assertEqual(code,2,report)
        self.assertEqual(len(self.calls()),before)
        self.assertFalse(self.output.exists())

    def test_changed_native_targets_block_before_preparation(self):
        self.launch()
        for mode in ("server-changed","pane-replaced","missing-pane","shell","wrong-repo"):
            with self.subTest(mode=mode):
                code, _ = self.handoff(mode=mode)
                self.assertEqual(code,2)
                self.assertFalse(self.output.exists())
        self.assertNotIn("packet",[name for name,_ in self.calls()])

    def test_identity_mapping_is_explicit_complete_and_unique(self):
        self.launch()
        before = len(self.calls())
        for identities in (("1:BlueLake",),("1:BlueLake","1:RedFox"),("1:BlueLake","2:bluelake"),
                           ("1:BlueLake","3:RedFox"),("1:$(touch x)","2:RedFox")):
            with self.subTest(identities=identities):
                self.assertEqual(self.handoff(identities=identities)[0],2)
        self.assertEqual(len(self.calls()),before)
        self.assertFalse(self.output.exists())

    def test_saved_assignments_keep_idle_slot_holes(self):
        self.launch()
        code, result = self.handoff(saved=True)
        self.assertEqual(code,0,result)
        received = json.loads((self.root / "preparation-inputs").read_text())
        self.assertEqual(received["targets"],["2:RedFox:claude:%42"])

    def test_unknown_saved_assignment_slots_block_preparation(self):
        self.launch()
        for slots in ([3],[2,2],[True],[]):
            self.assignments.write_text(json.dumps({"assignments":[{"slot":s} for s in slots]}))
            self.assertEqual(self.handoff(saved=True)[0],2)
            self.assertFalse(self.output.exists())

    def test_saved_assignment_selection_overrides_are_rejected(self):
        self.launch()
        before = len(self.calls())
        self.assertEqual(self.handoff(saved=True,extra=("--roles","testing:2"))[0],2)
        self.assertEqual(len(self.calls()),before)

    def test_no_work_does_not_publish_or_offer_dispatch(self):
        self.launch()
        code, report = self.handoff(mode="no-work")
        self.assertEqual((code,report["status"]),(1,"no_work"))
        self.assertFalse(self.output.exists())
        self.assertNotIn("preview_command",report)

    def test_preparation_failure_preserves_launch_receipts(self):
        self.launch()
        saved = self.receipt.read_bytes()
        code, result = self.handoff(mode="preparation-failed")
        self.assertEqual(code,2,result)
        self.assertNotIn("private failure",json.dumps(result))
        self.assertEqual(self.receipt.read_bytes(),saved)

    def test_agent_changes_during_preparation_retains_bundle_without_success(self):
        self.launch()
        code, report = self.handoff(mode="change-during")
        self.assertEqual(code,2,report)
        self.assertTrue((self.output / "batch.json").exists())
        self.assertNotIn("preview_command",report)

    def test_private_result_required_and_never_overwritten(self):
        self.launch()
        path = self.root / "launch.json.result.json"
        data = path.read_bytes()
        path.chmod(0o644)
        code, _ = self.handoff()
        self.assertEqual(code,2)
        self.assertEqual(path.read_bytes(),data)
        self.assertFalse(self.output.exists())

    def test_duplicate_saved_panes_and_misordered_slots_are_rejected(self):
        self.launch()
        path = self.root / "launch.json.result.json"
        original = json.loads(path.read_text())
        for key,value in (("pane",original["targets"][0]["pane"]),("slot",1)):
            broken = json.loads(json.dumps(original))
            broken["targets"][1][key] = value
            path.write_text(json.dumps(broken))
            self.assertEqual(self.handoff()[0],2)
        self.assertFalse(self.output.exists())

    def test_existing_output_and_symlink_inputs_are_preserved(self):
        self.output.mkdir()
        keep = self.output / "keep"
        keep.write_text("user work")
        self.assertEqual(self.handoff()[0],2)
        self.assertEqual(keep.read_text(),"user work")
        self.output = self.root / "new-output"
        self.scopes.rename(self.root / "original-scopes.json")
        self.scopes.symlink_to(self.root / "original-scopes.json")
        self.assertEqual(self.handoff()[0],2)
        self.assertEqual(self.calls(),[])

    def test_relative_input_paths_refer_to_invocation_directory(self):
        self.launch()
        code, result = self.handoff(extra=("--scopes-file","scopes.json"))
        self.assertEqual(code,0,result)

    @unittest.skipUnless(PACKET.is_file() and ASSIGN.is_file(), "requires the complete checkout's packet preparer and allocator")
    def test_real_preparer_and_allocator_consume_verified_launch(self):
        self.launch()
        shutil.copyfile(PACKET,self.lib / PACKET.name)
        shutil.copyfile(ASSIGN,self.lib / ASSIGN.name)
        (self.repo / "AGENTS.md").write_text("Follow current project instructions.\n")
        (self.repo / "README.md").write_text("Test project.\n")
        beads = [dict(id="bd-api",title="Implement API",status="open",issue_type="feature",priority=1,
                      description="Implement the endpoint",acceptance_criteria="Return 200",labels=["api"]),
                 dict(id="bd-doc",title="Document API",status="open",issue_type="task",priority=2,
                      description="Document the endpoint",acceptance_criteria="Example works",labels=["docs"])]
        path = self.root / "beads.json"
        path.write_text(json.dumps(beads))
        triage = self.root / "triage.json"
        triage.write_text("{}")
        code, result = self.handoff(extra=("--roles","implementation,documentation","--ready-file",str(path),
            "--beads-file",str(path),"--triage-file",str(triage)))
        self.assertEqual((code,result["status"]),(0,"prepared"),result)
        batch = json.loads((self.output / "batch.json").read_text())
        self.assertEqual([d["pane"] for d in batch["deliveries"]],["%43","%42"])
        self.assertEqual([d["agent_type"] for d in batch["deliveries"]],["codex","claude"])
        first = json.loads((self.output / "packet-01.json").read_text())
        self.assertEqual(first["agent"]["name"],"BlueLake")
        self.assertIn("Return 200",first["packet_markdown"])
        self.assertFalse(list(self.output.glob("*.receipt.json")))


if __name__ == "__main__":
    unittest.main()
