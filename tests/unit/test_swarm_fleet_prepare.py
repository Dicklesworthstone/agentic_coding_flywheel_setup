#!/usr/bin/env python3
"""Central preparation: real journals and an unprivileged native-protocol peer.

Fixtures model only the existing preparer's public protocol, never an SSH/VPS or
real agent. Keep fixture directories after failure for inspection.
"""
import ast
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shlex
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/swarm-fleet-prepare.py"
spec = importlib.util.spec_from_file_location("acfs_prepare_test", SCRIPT)
prep = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prep)
fleet = prep.fleet


def write(path, value, mode=0o600):
    path.write_bytes(value if isinstance(value, bytes) else fleet.encoded(value))
    path.chmod(mode)


def sample(directory, count=2):
    hosts, work_hosts, assignments, beads, targets = [], [], [], [], []
    for i in range(count):
        ident = "worker-" + chr(97 + i)
        agents = [{"agent_name": "Original" + str(i), "agent_type": "claude"},
                  {"agent_name": "Idle" + str(i), "agent_type": "codex"}]
        request = {"repo": "/home/ubuntu/project", "session": "wave", "receipt": "/home/ubuntu/receipts/wave.json",
                   "agents": agents, "profile": "balanced", "workload": "standard", "accept_warnings": False}
        host = {"id": ident, "host": ident + ".example.com", "user": "ubuntu", "port": 22, "request": request}
        target = [{"slot": j, **agent, "pane": "%" + str(40 + j), "pane_pid": str(200 + j),
                   "server_pid": "100", "session_id": "$1", "session_created": "1750000000"}
                  for j, agent in enumerate(agents, 1)]
        hosts.append(host)
        targets.append(target)
        work_hosts.append({"id": ident, "output": "/home/ubuntu/work-" + ident,
                           "identities": [{"slot": 1, "name": "Mail" + str(i)}, {"slot": 2, "name": "Rest" + str(i)}]})
        assignments.append({"host_id": ident, "slot": 1, "bead_id": "bd-task-" + str(i),
                            "role": "implementation", "write_scopes": ["src/feature" + str(i) + "/**"]})
        beads.append({"id": "bd-task-" + str(i), "title": "Implement a feature", "status": "open", "issue_type": "task",
                      "description": "Private task: $(touch NEVER); preserve this as data", "labels": []})
    launch = fleet.build_plan({"schema": fleet.SPEC_SCHEMA, "hosts": hosts}, b"known", b"identity", directory / "launch", 360)
    Path(launch["state_directory"]).mkdir(mode=0o700)
    with fleet.directory_fd(launch["state_directory"], private=True) as fd:
        fleet.publish(fd, "intent.json", {"schema": fleet.STATE_SCHEMA, "plan": launch})
        for host, target in zip(hosts, targets):
            intent = fleet.host_intent(launch, host)
            fleet.publish(fd, host["id"] + ".attempt.json", intent)
            fleet.publish(fd, host["id"] + ".result.json", {**intent, "targets": target})
        history, records = fleet.read_history(fd, launch)
    work = {"schema": prep.WORK_SCHEMA, "hosts": work_hosts, "assignments": assignments, "beads": beads}
    return launch, history, records, work


def prepared(entry):
    """Independent response fixture for the controller boundary, not the remote bridge."""
    files = {"assignments.json": {"sha256": fleet.digest(fleet.encoded(entry["assignments"])),
                                  "bytes": len(fleet.encoded(entry["assignments"]))},
             "batch.json": {"sha256": "1" * 64, "bytes": 120}}
    packets = []
    for item in entry["assignments"]["assignments"]:
        name = "packet-" + str(item["slot"]).zfill(2)
        files[name + ".json"] = {"sha256": "2" * 64, "bytes": 500}
        files[name + ".md"] = {"sha256": "3" * 64, "bytes": 200}
        packets.append({"slot": item["slot"], "bead_id": item["bead_id"], "operation_id": "operation-" + str(item["slot"])})
    return {"schema": prep.PEER_SCHEMA, "status": "prepared", "entry_sha256": fleet.digest(fleet.encoded(entry)),
            "batch": entry["output"] + "/bundle/batch.json", "files": files, "packets": packets,
            "starts_agents": False, "sends_prompt": False}


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp(prefix="acfs-fleet-prepare-test-"))
        self.launch, self.history, self.records, self.work = sample(self.directory)

    def plan(self, work=None):
        return prep.build_plan(self.work if work is None else work, self.launch, self.history,
                               self.records, self.directory / "prepared", 360)

    def peer(self, hook=None):
        calls = []
        def invoke(entry, mode):
            calls.append((entry["host"]["id"], mode))
            if hook:
                hook(entry, mode)
            value = ({"schema": prep.PEER_SCHEMA, "status": "available", "entry_sha256": fleet.digest(fleet.encoded(entry)),
                      "starts_agents": False, "sends_prompt": False} if mode == "check" else prepared(entry))
            return 0, fleet.encoded(value)
        return calls, invoke

    def test_original_slot_and_host_order_survive_explicit_reordering(self):
        self.work["hosts"].reverse()
        self.work["assignments"].reverse()
        self.work["hosts"][0]["identities"].reverse()
        plan = self.plan()
        self.assertEqual([e["host"]["id"] for e in plan["hosts"]], ["worker-a", "worker-b"])
        self.assertEqual(plan["hosts"][1]["identities"][0]["slot"], 1)
        self.assertEqual(plan["hosts"][0]["targets"], self.history[0][1])
        self.assertEqual(plan["hosts"][0]["beads"], [self.work["beads"][0]])
        self.assertFalse((self.directory / "prepared").exists())

    def test_idle_holes_are_preserved_without_inventing_tasks(self):
        self.work["assignments"][0]["slot"] = 2
        plan = self.plan()
        self.assertEqual(plan["hosts"][0]["assignments"]["assignments"][0]["slot"], 2)
        self.assertEqual(len(plan["hosts"][0]["identities"]), 2)
        self.assertEqual(len(plan["hosts"][0]["beads"]), 1)

    def test_duplicate_bead_across_hosts_is_refused(self):
        self.work["assignments"][1]["bead_id"] = self.work["assignments"][0]["bead_id"]
        with self.assertRaisesRegex(fleet.Refused, "duplicate_assignment"):
            self.plan()

    def test_cross_host_scope_overlap_includes_literals_ancestors_and_globs(self):
        for left, right in [("src/a.rs", "src/a.rs"), ("src", "src/a.rs"), ("src/a.rs", "src"),
                            ("src/**", "src/a.rs"), ("src/a*.rs", "src/a?/x"), ("*", "README.md")]:
            work = copy.deepcopy(self.work)
            work["assignments"][0]["write_scopes"] = [left]
            work["assignments"][1]["write_scopes"] = [right]
            with self.subTest(left=left, right=right), self.assertRaisesRegex(fleet.Refused, "write_scope_overlap"):
                self.plan(work)
        self.assertFalse(prep.scopes_overlap("src/api", "src/apikey"))
        self.assertFalse(prep.scopes_overlap("src/a/**", "src/b/**"))

    def test_scopes_cannot_escape_or_become_executable_arguments(self):
        for path in ("../private", "/root", "src//file", "src/./file", "src\\file", "src\nfile", "src/[ab]", "$(touch bad)"):
            work = copy.deepcopy(self.work)
            work["assignments"][0]["write_scopes"] = [path]
            with self.subTest(path=path), self.assertRaisesRegex(fleet.Refused, "invalid_write_scopes"):
                self.plan(work)

    def test_missing_closed_blocked_epic_or_invalid_bead_fails_before_transport(self):
        for patch in ({"status": "closed"}, {"blocked": True}, {"blocked_by": ["bd-blocker"]},
                      {"issue_type": "epic"}, {"title": " "}, {"description": 7}, {"labels": [False]}):
            work = copy.deepcopy(self.work)
            work["beads"][0].update(patch)
            with self.subTest(patch=patch), self.assertRaises(fleet.Refused):
                self.plan(work)
        self.work["beads"].pop(0)
        with self.assertRaises(fleet.Refused):
            self.plan()

    def test_unknown_hosts_incomplete_launch_and_duplicate_identities_fail(self):
        work = copy.deepcopy(self.work)
        work["hosts"][0]["id"] = "other"
        with self.assertRaises(fleet.Refused):
            self.plan(work)
        self.history[0] = (True, None)
        with self.assertRaisesRegex(fleet.Refused, "launch_not_confirmed"):
            self.plan()
        self.history[0] = (True, self.history[1][1])
        work = copy.deepcopy(self.work)
        work["hosts"][1]["identities"][0]["name"] = "mail0"
        with self.assertRaisesRegex(fleet.Refused, "duplicate_work_identity"):
            self.plan(work)

    def test_host_without_work_and_duplicate_slot_refused(self):
        self.work["assignments"].pop()
        with self.assertRaisesRegex(fleet.Refused, "host_has_no_work"):
            self.plan()
        self.work["assignments"].append({**self.work["assignments"][0], "bead_id": "bd-task-1"})
        with self.assertRaisesRegex(fleet.Refused, "duplicate_assignment"):
            self.plan()

    def test_approval_changes_with_brief_scope_roster_policy_and_paths(self):
        original = fleet.digest(fleet.encoded(self.plan()))
        for change in (lambda w: w["beads"][0].update(description="different"),
                       lambda w: w["assignments"][0].update(write_scopes=["elsewhere/**"]),
                       lambda w: w["hosts"][0].update(output="/home/ubuntu/other"),
                       lambda w: w["hosts"][0]["identities"][0].update(name="Different")):
            work = copy.deepcopy(self.work)
            change(work)
            self.assertNotEqual(original, fleet.digest(fleet.encoded(self.plan(work))))
        self.assertEqual(self.plan()["peer_policy_sha256"], fleet.digest(prep.remote_program().encode()))

    def test_prepare_uses_all_host_barrier_and_publishes_dispatch_input(self):
        plan = self.plan()
        checked = []
        def hook(entry, mode):
            if mode == "check":
                self.assertFalse((self.directory / "prepared").exists())
                checked.append(entry["host"]["id"])
            else:
                self.assertEqual(checked, ["worker-a", "worker-b"])
                path = self.directory / "prepared" / (entry["host"]["id"] + ".attempt.json")
                self.assertEqual(json.loads(path.read_text()), prep.attempt(plan, entry))
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        calls, invoke = self.peer(hook)
        report, code = prep.prepare(plan, fleet.digest(fleet.encoded(plan)), invoke, lambda: None)
        self.assertEqual(code, 0)
        self.assertEqual(calls, [("worker-a", "check"), ("worker-b", "check"), ("worker-a", "prepare"), ("worker-b", "prepare")])
        self.assertEqual(report["status"], "prepared")
        self.assertFalse(report["sends_prompt"])
        mapping = json.loads(Path(report["batches_file"]).read_text())
        self.assertEqual(mapping, {"schema": "acfs.swarm-fleet-batches.v1", "hosts": [
            {"id": "worker-a", "batch": "/home/ubuntu/work-worker-a/bundle/batch.json"},
            {"id": "worker-b", "batch": "/home/ubuntu/work-worker-b/bundle/batch.json"}]})
        self.assertNotIn("Private task", json.dumps(report))

    def test_failed_later_preflight_creates_nothing(self):
        def hook(entry, mode):
            if entry["host"]["id"] == "worker-b":
                raise fleet.Refused("private-token-must-not-escape")
        calls, invoke = self.peer(hook)
        plan = self.plan()
        result, code = prep.prepare(plan, fleet.digest(fleet.encoded(plan)), invoke, lambda: None)
        self.assertEqual(code, 1)
        self.assertFalse((self.directory / "prepared").exists())
        self.assertEqual(calls, [("worker-a", "check"), ("worker-b", "check")])
        self.assertNotIn("private-token", json.dumps(result))

    def test_lost_prepare_response_retains_attempt_and_stops_later_hosts(self):
        def hook(_entry, mode):
            if mode == "prepare":
                raise OSError("connection lost")
        calls, invoke = self.peer(hook)
        plan = self.plan()
        result, code = prep.prepare(plan, fleet.digest(fleet.encoded(plan)), invoke, lambda: None)
        self.assertEqual(code, 1)
        self.assertEqual(result["hosts"][1]["status"], "not_attempted")
        self.assertTrue((self.directory / "prepared/worker-a.attempt.json").exists())
        self.assertFalse((self.directory / "prepared/batches.json").exists())
        self.assertNotIn(("worker-b", "prepare"), calls)
        calls.clear()
        with self.assertRaisesRegex(fleet.Refused, "state_already_exists"):
            prep.prepare(plan, fleet.digest(fleet.encoded(plan)), invoke, lambda: None)
        self.assertEqual(calls, [])

    def test_wrong_approval_refused_without_transport(self):
        calls, invoke = self.peer()
        with self.assertRaisesRegex(fleet.Refused, "approval_mismatch"):
            prep.prepare(self.plan(), "0" * 64, invoke, lambda: None)
        self.assertEqual(calls, [])

    def test_binding_and_inventory_mutations_cannot_publish_success(self):
        entry = self.plan()["hosts"][0]
        for change in (lambda r: r.update(entry_sha256="0" * 64), lambda r: r.update(sends_prompt=True),
                       lambda r: r.update(batch="/other/batch.json"), lambda r: r["files"].pop("packet-01.md"),
                       lambda r: r["files"]["assignments.json"].update(sha256="0" * 64),
                       lambda r: r["files"]["packet-01.md"].update(bytes=True),
                       lambda r: r["packets"][0].update(bead_id="other"), lambda r: r["packets"][0].update(slot=True)):
            result = prepared(entry)
            change(result)
            with self.assertRaises(fleet.Refused):
                prep.accept_result(entry, result, "prepare")

    def test_source_journal_is_locked_and_changes_are_detected(self):
        with self.assertRaisesRegex(fleet.Refused, "state_changed_during_operation"):
            with prep.launch_context(self.launch["state_directory"], b"known", b"identity") as (_, _, _, guard):
                with self.assertRaisesRegex(fleet.Refused, "in_progress"):
                    with prep.launch_context(self.launch["state_directory"], b"known", b"identity"):
                        self.fail("acquired duplicate lock")
                # Both the explicit guard and context exit reject new members.
                path = Path(self.launch["state_directory"]) / "unexpected"
                path.write_text("inspection evidence")
                with self.assertRaises(fleet.Refused):
                    guard()

    def test_actual_cli_preview_needs_neither_ssh_nor_remote_files(self):
        known, key, work = (self.directory / name for name in ("known", "key", "work.json"))
        write(known, b"known")
        write(key, b"identity")
        write(work, self.work)
        result = subprocess.run([sys.executable, "-I", str(SCRIPT), "--launch-state", self.launch["state_directory"],
            "--work", str(work), "--known-hosts", str(known), "--identity-file", str(key),
            "--state-dir", str(self.directory / "prepared")], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["status"], "preview")
        self.assertFalse(report["preparation_attempted"])
        self.assertFalse((self.directory / "prepared").exists())

    def test_remote_program_has_valid_syntax_and_no_input_in_argv(self):
        ast.parse(prep.remote_program())
        entry = self.plan()["hosts"][0]
        def runner(argv, timeout, env, data):
            self.assertNotIn("-n", argv)
            self.assertIn("StrictHostKeyChecking=yes", argv)
            self.assertIn("ForwardAgent=no", argv)
            self.assertIn("IdentitiesOnly=yes", argv)
            self.assertNotIn("Private task", " ".join(argv))
            self.assertIn("Private task", data.decode())
            self.assertEqual(json.loads(data)["mode"], "prepare")
            self.assertNotIn("BASH_ENV", env)
            self.assertEqual(timeout, 30)
            return 0, b"{}"
        self.assertEqual(prep.transport(b"known", b"identity", 30, runner=runner, ssh="/bin/true")(entry, "prepare"), (0, b"{}"))

    def test_real_input_transport_preserves_large_stdin_and_bounds_both_streams(self):
        data = b"literal $(bad) ' \n" * 20000
        code, raw = prep.capture_input([sys.executable, "-c", "import sys,hashlib;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())"],
                                      5, {"PATH": "/usr/bin:/bin"}, data)
        self.assertEqual(code, 0)
        self.assertEqual(raw.strip().decode(), hashlib.sha256(data).hexdigest())
        for stream in ("stdout", "stderr"):
            with self.assertRaisesRegex(fleet.Refused, "output_limit"):
                prep.capture_input([sys.executable, "-c", f"import sys;sys.{stream}.write('x'*2000000)"],
                                   5, {"PATH": "/usr/bin:/bin"}, b"input")

    def test_real_timeout_kills_pipe_holding_descendant(self):
        code = "import subprocess,sys;subprocess.Popen([sys.executable,'-c','import time;time.sleep(10)']);sys.exit(0)"
        start = time.monotonic()
        with self.assertRaisesRegex(fleet.Refused, "timeout"):
            prep.capture_input([sys.executable, "-c", code], 0.15, {"PATH": "/usr/bin:/bin"}, b"")
        self.assertLess(time.monotonic() - start, 3)


NATIVE_FIXTURE = r'''import hashlib,json,os,pathlib,sys
home = pathlib.Path(os.environ['HOME'])
entry = json.loads((home/'fixture.json').read_text())
args = sys.argv[1:]
with (home/'calls.jsonl').open('a') as trace: trace.write(json.dumps(args)+'\n')
def enc(x): return (json.dumps(x,sort_keys=True,ensure_ascii=True,indent=2)+'\n').encode()
def sha(x): return hashlib.sha256(x).hexdigest()
request = entry['host']['request']
if args == ['--reconcile','--receipt',request['receipt']]:
    print(json.dumps(dict(schema='acfs.swarm-launch.v1',status='ready',request=request,
        targets=entry['targets'],starts_agents=False,work_dispatched=False,
        authentication_verified=False,agent_mail_registered=False,reconciled_only=True)))
    sys.exit(0)
assert args[:2] == ['--prepare-batch',entry['output']+'/bundle']
assert args[2:4] == ['--receipt',request['receipt']]
assert args[4:8] == ['--assignments',entry['output']+'/assignments.json','--beads-file',entry['output']+'/beads.json']
assert args[8] == '--no-live-context'
expected = []
for identity in entry['identities']: expected += ['--identity',str(identity['slot'])+':'+identity['name']]
assert args[9:] == expected
assert not any(k in os.environ for k in ('BASH_ENV','ENV','OPENAI_API_KEY','PYTHONPATH','HTTP_PROXY'))
assignment_bytes = pathlib.Path(args[5]).read_bytes()
assert assignment_bytes == enc(entry['assignments'])
assert pathlib.Path(args[7]).read_bytes() == enc(entry['beads'])
out = pathlib.Path(args[1]); out.mkdir(mode=0o700)
def write(name,data):
    p=out/name; p.write_bytes(data); p.chmod(0o600)
write('assignments.json',assignment_bytes)
deliveries=[]
for item in entry['assignments']['assignments']:
    slot=item['slot']; name='packet-'+str(slot).zfill(2); t=entry['targets'][slot-1]
    text='# ACFS Swarm Startup Packet\n\nA bounded test brief.\n'
    packet={'schema_version':1,'status':'pass','repository':{'path':request['repo']},
        'bead':{'id':item['bead_id']},'output':{'truncated':False},'packet_markdown':text,
        'preparation':{'slot':slot,'assignment_sha256':sha(assignment_bytes),
            'declared_write_scopes':item['reservation_surfaces'],'reservations_acquired':False,'bead_source':'file'}}
    write(name+'.json',enc(packet)); write(name+'.md',text.encode())
    deliveries.append({'packet':name+'.json','receipt':name+'.receipt.json','repo':request['repo'],
        'session':request['session'],'pane':t['pane'],'agent_type':t['agent_type'],'operation_id':'test-operation-'+str(slot)})
write('batch.json',enc({'schema':'acfs.packet-delivery-batch.v1','deliveries':deliveries}))
names={v['slot']:v['name'] for v in entry['identities']}
print(json.dumps({'schema':'acfs.packet-preparation.v1','status':'prepared','directory':str(out),'sends_prompt':False,
    'launch':{'receipt':request['receipt'],'session':request['session'],'request_sha256':sha(enc(request)),
        'identities_rechecked':True,'starts_agents':False,'work_dispatched':False,'agent_mail_registration_verified':False,
        'identity_mapping':[{'slot':t['slot'],'launch_name':t['agent_name'],'agent_mail_name':names[t['slot']],
            'agent_type':t['agent_type'],'pane':t['pane']} for t in entry['targets']]}}))
'''


class RemotePeerTests(unittest.TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp(prefix="acfs-real-preparation-peer-"))
        launch, history, records, work = sample(self.directory, 1)
        self.home = self.directory / "home"
        self.home.mkdir(mode=0o700)
        work["hosts"][0]["output"] = str(self.home / "wave ' literal $(NEVER)")
        self.entry = prep.build_plan(work, launch, history, records, self.directory / "state", 20)["hosts"][0]
        self.uid = 65534 if os.geteuid() == 0 else os.geteuid()
        self.gid = 65534 if os.geteuid() == 0 else os.getegid()
        native = self.home / ".acfs/scripts/lib/swarm_launch.sh"
        native.parent.mkdir(parents=True, mode=0o700)
        native.write_text("#!/bin/bash\nexec /usr/bin/python3 - \"$@\" <<'PY_NATIVE'\n" + NATIVE_FIXTURE + "\nPY_NATIVE\n")
        native.chmod(0o700)
        write(native.with_name("swarm_packet.sh"), b"# Companion availability fixture\n", 0o700)
        write(self.home / "fixture.json", self.entry)
        self.directory.chmod(0o755)
        if os.geteuid() == 0:
            for path in [self.home, *self.home.rglob("*")]:
                os.chown(path, self.uid, self.gid)

    def peer(self, mode):
        return subprocess.run(["/usr/bin/python3", "-I", "-c", prep.remote_program()],
            input=fleet.encoded({"mode": mode, "entry": self.entry, "timeout_seconds": 20}),
            capture_output=True, timeout=30, user=self.uid, group=self.gid,
            env={"HOME": str(self.home), "PATH": "/usr/bin:/bin", "OPENAI_API_KEY": "never-forward-this"})

    def test_real_peer_checks_without_writes_then_prepares_exact_literal_inputs(self):
        check = self.peer("check")
        self.assertEqual(check.returncode, 0, check.stderr)
        self.assertEqual(json.loads(check.stdout)["status"], "available")
        self.assertFalse(Path(self.entry["output"]).exists())
        result = self.peer("prepare")
        self.assertEqual(result.returncode, 0, result.stderr)
        report = prep.accept_result(self.entry, json.loads(result.stdout), "prepare")
        stage = Path(self.entry["output"])
        self.assertEqual(stage.stat().st_mode & 0o777, 0o700)
        self.assertEqual(json.loads((stage / "complete.json").read_text()), report)
        self.assertEqual((stage / "beads.json").read_bytes(), fleet.encoded(self.entry["beads"]))
        self.assertFalse((self.home / "NEVER").exists())
        calls = [json.loads(line) for line in (self.home / "calls.jsonl").read_text().splitlines()]
        self.assertEqual([c[0] for c in calls], ["--reconcile", "--reconcile", "--prepare-batch", "--reconcile"])
        self.assertFalse(any("--send" in c or "--launch" in c for c in calls))
        prior = {str(p): p.read_bytes() for p in stage.rglob("*") if p.is_file()}
        again = self.peer("prepare")
        self.assertNotEqual(again.returncode, 0)
        self.assertEqual(prior, {str(p): p.read_bytes() for p in stage.rglob("*") if p.is_file()})

    def test_existing_output_symlink_and_unsafe_parent_are_refused(self):
        destination = Path(self.entry["output"])
        destination.symlink_to(self.home, target_is_directory=True)
        self.assertNotEqual(self.peer("prepare").returncode, 0)
        self.assertFalse((self.home / "calls.jsonl").exists())

    def test_wrong_original_targets_never_reach_generation(self):
        self.entry["targets"][0]["pane_pid"] = "999"
        result = self.peer("prepare")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(Path(self.entry["output"]).exists())
        calls = [json.loads(line) for line in (self.home / "calls.jsonl").read_text().splitlines()]
        self.assertEqual([c[0] for c in calls], ["--reconcile"])

    def test_complete_remote_output_is_inspectable_without_reinvoking_native_tools(self):
        result = self.peer("prepare")
        self.assertEqual(result.returncode, 0, result.stderr)
        trace = (self.home / "calls.jsonl").read_bytes()
        inspected = self.peer("inspect")
        self.assertEqual(inspected.returncode, 0, inspected.stderr)
        self.assertEqual(inspected.stdout, result.stdout)
        self.assertEqual((self.home / "calls.jsonl").read_bytes(), trace)

    def test_changed_remote_bundle_is_not_adopted_or_rebuilt(self):
        self.assertEqual(self.peer("prepare").returncode, 0)
        trace = (self.home / "calls.jsonl").read_bytes()
        path = Path(self.entry["output"]) / "bundle/packet-01.md"
        path.write_text("changed work")
        self.assertNotEqual(self.peer("inspect").returncode, 0)
        self.assertEqual(path.read_text(), "changed work")
        self.assertEqual((self.home / "calls.jsonl").read_bytes(), trace)

    def test_incomplete_remote_stage_never_enters_generation_during_inspection(self):
        path = Path(self.entry["output"])
        path.mkdir(mode=0o700)
        if os.geteuid() == 0:
            os.chown(path, self.uid, self.gid)
        result = self.peer("inspect")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / "calls.jsonl").exists())
        self.assertEqual(list(path.iterdir()), [])

    def test_task_brief_argv_is_not_interpreted_by_a_remote_shell(self):
        # Exercise the exact shell quoting used in SSH's final command, not just
        # direct Python invocation. Task bytes stay on stdin through the shell.
        command = "exec python3 -I -c " + shlex.quote(prep.remote_program())
        result = subprocess.run(["/bin/sh", "-c", command],
            input=fleet.encoded({"mode": "prepare", "entry": self.entry, "timeout_seconds": 20}),
            capture_output=True, timeout=30, user=self.uid, group=self.gid,
            env={"HOME": str(self.home), "PATH": "/usr/bin:/bin"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "prepared")

    def test_root_remote_execution_is_refused(self):
        if os.geteuid() != 0:
            self.skipTest("Root identity unavailable")
        result = subprocess.run(["/usr/bin/python3", "-I", "-c", prep.remote_program()],
            input=fleet.encoded({"mode": "prepare", "entry": self.entry, "timeout_seconds": 20}), capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b"")
        self.assertFalse(Path(self.entry["output"]).exists())


if __name__ == "__main__":
    unittest.main()
