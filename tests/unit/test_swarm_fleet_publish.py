#!/usr/bin/env python3
"""Real Git publication/evidence tests. No network or paid provider is used."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/swarm-fleet-publish.py"

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

publish = load("fleet_publish", SCRIPT)
integration = load("fleet_publication_git_fixture", Path(__file__).with_name("test_swarm_fleet_integrate.py"))
runner = publish.tests


class Fixture:
    def __init__(self, fmt="sha1", program=None, integrate=False):
        program = program or "import unittest\nclass T(unittest.TestCase):\n def test_value(self): self.assertEqual(2+2,4)\nunittest.main()\n"
        self.fx = integration.Fixture(fmt=fmt, files={"test.py": ("100644", program.encode())})
        self.root, self.repo, self.base = self.fx.root, self.fx.repo, self.fx.base
        self.remote, self.state, self.run = (self.root / name for name in ("remote.git", "publication", "test-run"))
        if integrate:
            for name in ("left", "right"):
                head = self.fx.commit(name, [self.base], {name: ("100644", name.encode())})
                self.fx.add_host(name, head)
            self.fx.seal()
            plan = self.fx.preview()
            merged = self.fx.preview(approval=plan["plan_sha256"])
            self.candidate = merged["plan"]["result"]["candidate_commit"]
        else:
            self.candidate = self.fx.commit("candidate", [self.base], {"feature.txt": ("100755", b"feature\n")})
            self.transfer(self.fx.source, self.repo, self.candidate)
        self.fx.git(self.repo, "update-ref", "refs/heads/release", self.base)
        spec = {"schema": runner.SPEC_SCHEMA, "environment": {}, "commands": [{
            "id": "unit", "argv": ["/usr/bin/python3", "-B", "test.py"], "timeout_seconds": 10}]}
        options = dict(repository=self.repo, commit=self.candidate, spec=spec, output=self.run, timeout=30)
        plan = runner.execute(**options)
        self.tested = runner.execute(**options, approval=plan["plan_sha256"])
        self.test_plan = self.tested["plan_sha256"]
        self.remote.mkdir(mode=0o700)
        self.fx.git(self.remote, "init", "--bare", "--template=", "--initial-branch=main", "--object-format=" + fmt)
        self.transfer(self.repo, self.remote, self.base)
        self.fx.git(self.remote, "update-ref", "refs/heads/main", self.base)
        self.fx.git(self.remote, "update-ref", "refs/heads/other", self.base)
        if self.tested["status"] == "passed":
            options = dict(path=self.run, repository=self.repo, expected=self.test_plan,
                           branch="release", old=self.base, timeout=30)
            promotion = runner.promote_candidate(**options)
            runner.promote_candidate(**options, approval=promotion["plan_sha256"])
        self.endpoint = publish.local_endpoint(self.remote, 30)

    def transfer(self, source, dest, commit):
        pack = self.fx.git(source, "pack-objects", "--stdout", "--revs", data=(commit + "\n").encode())
        self.fx.git(dest, "index-pack", "--stdin", data=pack)

    def args(self):
        return dict(run=self.run, repository=self.repo, test_plan=self.test_plan, local_branch="release",
                    remote_branch="main", old=self.base, endpoint=self.endpoint, known=b"", identity=b"",
                    state=self.state, timeout=30)

    def preview(self, **kw):
        return publish.publish_candidate(**{**self.args(), **kw})

    def apply(self, **kw):
        plan = self.preview(**kw)
        return self.preview(approval=plan["plan_sha256"], **kw)

    def check(self, plan, **kw):
        return self.preview(approval=plan["plan_sha256"], check=True, **kw)

    def value(self, branch="main"):
        result = self.fx.git(self.remote, "show-ref", "--verify", "refs/heads/" + branch, allowed=(0, 128))
        return result.decode().split()[0] if result else None

    def cli_args(self, *args):
        return [sys.executable, "-I", str(SCRIPT), "--test-run", str(self.run), "--repository", str(self.repo),
                "--expect-test-plan", self.test_plan, "--branch", "release", "--remote-branch", "main",
                "--expect-old", self.base, "--local-remote", str(self.remote), "--state-dir", str(self.state),
                "--timeout", "30", *args]

    def cli(self, *args, env=None):
        return subprocess.run(self.cli_args(*args), capture_output=True, text=True,
                              env=env or self.fx.env, timeout=30)

    @staticmethod
    def contents(root):
        return integration.Fixture.contents(root)


class PublicationTests(unittest.TestCase):
    def setUp(self):
        # Fixtures inherit the umask; a login user's 0002 makes them group-writable.
        self.addCleanup(os.umask, os.umask(0o022))
        self.assertNotEqual(os.geteuid(), 0, "Run unprivileged")

    def test_preview_uses_real_remote_and_changes_nothing(self):
        fx = Fixture()
        before = fx.contents(fx.root)
        one, two = fx.preview(), fx.preview()
        self.assertEqual(one, two)
        self.assertEqual(one["status"], "preview")
        self.assertEqual(one["plan"]["candidate_commit"], fx.candidate)
        self.assertEqual(fx.contents(fx.root), before)

    def test_real_push_publishes_exact_tested_commit_not_head_and_preserves_source(self):
        fx = Fixture()
        before, evidence = fx.contents(fx.repo), fx.contents(fx.run)
        result = fx.apply()
        self.assertEqual((result["status"], fx.value()), ("published", fx.candidate))
        self.assertEqual(fx.value("other"), fx.base)
        self.assertEqual(fx.fx.text(fx.repo, "rev-parse", "HEAD"), fx.base)
        self.assertEqual(fx.contents(fx.repo), before)
        self.assertEqual(fx.contents(fx.run), evidence)
        self.assertEqual((fx.state.stat().st_mode & 0o777), 0o700)
        self.assertTrue((fx.state / "attempt.json").exists())
        self.assertEqual(json.loads((fx.state / "result.json").read_text()), result)

    def test_sha256_publication(self):
        fx = Fixture(fmt="sha256")
        result = fx.apply()
        self.assertEqual(fx.value(), fx.candidate)
        self.assertEqual(len(fx.value()), 64)
        self.assertEqual(result["status"], "published")

    def test_full_production_merge_test_promotion_publication(self):
        program = ("import unittest\nfrom pathlib import Path\nclass T(unittest.TestCase):\n"
                   " def test_combined(self): self.assertEqual(Path('left').read_text()+Path('right').read_text(),'leftright')\n"
                   "unittest.main()\n")
        fx = Fixture(program=program, integrate=True)
        self.assertEqual(len(fx.fx.text(fx.repo, "show", "-s", "--format=%P", fx.candidate).split()), 2)
        result = fx.apply()
        self.assertEqual(result["status"], "published")
        self.assertEqual(fx.fx.git(fx.remote, "show", fx.candidate + ":left"), b"left")
        self.assertEqual(fx.fx.git(fx.remote, "show", fx.candidate + ":right"), b"right")
        self.assertEqual(fx.check(result)["status"], "matched")

    def test_failed_tests_never_query_or_push(self):
        fx = Fixture(program="raise SystemExit(23)\n")
        calls = []
        with self.assertRaisesRegex(publish.fleet.Refused, "passing_test_evidence_required"):
            fx.preview(invoke=lambda *a: calls.append(a))
        self.assertEqual(calls, [])
        self.assertFalse(fx.state.exists())

    def test_tampered_logs_refuse_before_remote(self):
        fx = Fixture()
        (fx.run / "logs/unit.stdout").write_text("fabricated")
        calls = []
        with self.assertRaisesRegex(publish.fleet.Refused, "log_mismatch"):
            fx.preview(invoke=lambda *a: calls.append(a))
        self.assertEqual(calls, [])

    def test_local_branch_must_equal_tested_candidate(self):
        fx = Fixture()
        fx.fx.git(fx.repo, "update-ref", "refs/heads/release", fx.base)
        with self.assertRaisesRegex(publish.fleet.Refused, "local_branch_not_exact"):
            fx.preview()
        self.assertFalse(fx.state.exists())

    def test_missing_and_moved_remote_require_new_review(self):
        fx = Fixture()
        with self.assertRaisesRegex(publish.fleet.Refused, "remote_branch_changed_or_missing"):
            fx.preview(remote_branch="missing")
        plan = fx.preview()
        fx.transfer(fx.repo, fx.remote, fx.candidate)
        fx.fx.git(fx.remote, "update-ref", "refs/heads/main", fx.candidate)
        with self.assertRaisesRegex(publish.fleet.Refused, "remote_branch_changed_or_missing"):
            fx.preview(approval=plan["plan_sha256"])
        self.assertFalse(fx.state.exists())

    def test_non_fast_forward_is_refused_before_network(self):
        fx = Fixture()
        other = fx.fx.commit("divergent", [fx.base], {"other.txt": ("100644", b"keep this")})
        fx.transfer(fx.fx.source, fx.repo, other)
        calls = []
        with self.assertRaisesRegex(publish.fleet.Refused, "publication_not_fast_forward"):
            fx.preview(old=other, invoke=lambda *a: calls.append(a))
        self.assertEqual(calls, [])
        self.assertFalse(fx.state.exists())

    def test_lease_rejects_competing_remote_update(self):
        fx = Fixture()
        other = fx.fx.commit("racing", [fx.base], {"racing": ("100644", b"racing")})
        fx.transfer(fx.fx.source, fx.remote, other)
        plan = fx.preview()
        with publish.remote_transport(fx.endpoint, b"", b"", 30) as real:
            def racing(mode, *args):
                if mode == "push":
                    fx.fx.git(fx.remote, "update-ref", "refs/heads/main", other, fx.base)
                return real(mode, *args)
            with self.assertRaisesRegex(publish.fleet.Refused, "push_result_unconfirmed"):
                fx.preview(approval=plan["plan_sha256"], invoke=racing)
        self.assertEqual(fx.value(), other)
        self.assertTrue((fx.state / "attempt.json").exists())
        self.assertFalse((fx.state / "result.json").exists())
        self.assertEqual(fx.check(plan)["remote_status"], "different")

    def test_server_receive_hook_policy_is_not_bypassed(self):
        fx = Fixture()
        hook = fx.remote / "hooks/pre-receive"
        hook.parent.mkdir(mode=0o700)
        marker = fx.root / "server-hook-ran"
        hook.write_text("#!/bin/sh\nprintf 'yes' > " + str(marker) + "\nexit 1\n")
        hook.chmod(0o700)
        plan = fx.preview()
        with self.assertRaisesRegex(publish.fleet.Refused, "push_result_unconfirmed"):
            fx.preview(approval=plan["plan_sha256"])
        self.assertEqual(marker.read_text(), "yes")
        self.assertEqual(fx.value(), fx.base)
        self.assertEqual(fx.check(plan)["remote_status"], "not_published")

    def test_local_hooks_and_remote_url_rewrites_are_not_executed(self):
        fx = Fixture()
        trap = fx.root / "trap"
        trap.mkdir(mode=0o700)
        marker = fx.root / "LOCAL-HOOK-RAN"
        hook = trap / "pre-push"
        hook.write_text("#!/bin/sh\nprintf bad > " + str(marker) + "\nexit 1\n")
        hook.chmod(0o700)
        fx.fx.git(fx.repo, "config", "core.hooksPath", str(trap))
        fx.fx.git(fx.repo, "config", "url./not/the/remote.insteadOf", str(fx.remote))
        fx.fx.git(fx.repo, "config", "push.followTags", "true")
        fx.fx.git(fx.repo, "config", "remote.origin.mirror", "true")
        before = fx.contents(fx.repo)
        self.assertEqual(fx.apply()["status"], "published")
        self.assertFalse(marker.exists())
        self.assertEqual(fx.contents(fx.repo), before)

    def test_symbolic_local_remote_ref_is_refused(self):
        fx = Fixture()
        fx.fx.git(fx.remote, "symbolic-ref", "refs/heads/alias", "refs/heads/main")
        with self.assertRaisesRegex(publish.fleet.Refused, "symbolic_local_remote_branch"):
            fx.preview(remote_branch="alias")
        self.assertEqual(fx.value(), fx.base)

    def test_noop_never_starts_push_or_creates_state(self):
        fx = Fixture()
        fx.transfer(fx.repo, fx.remote, fx.candidate)
        fx.fx.git(fx.remote, "update-ref", "refs/heads/main", fx.candidate)
        result = fx.apply(old=fx.candidate)
        self.assertEqual(result["status"], "noop")
        self.assertFalse(fx.state.exists())
        self.assertFalse(result["push_started"])

    def test_existing_state_is_never_replayed_or_overwritten(self):
        fx = Fixture()
        result = fx.apply()
        before = fx.contents(fx.state)
        with self.assertRaisesRegex(publish.fleet.Refused, "state_already_exists"):
            fx.preview(approval=result["plan_sha256"])
        self.assertEqual(fx.contents(fx.state), before)

    def test_stale_approval_and_overlapping_destinations_refuse(self):
        fx = Fixture()
        plan = fx.preview()
        for kw in ({"remote_branch": "other"}, {"local_branch": "main"}, {"timeout": 31}):
            with self.subTest(kw=kw), self.assertRaisesRegex(publish.fleet.Refused, "approval_mismatch"):
                fx.preview(approval=plan["plan_sha256"], **kw)
        for path in (fx.repo, fx.repo / "publish", fx.run / "publish", fx.remote / "publish", fx.root):
            with self.subTest(path=path), self.assertRaises(publish.fleet.Refused):
                fx.preview(state=path)
        self.assertFalse(fx.state.exists())

    def test_cli_is_separate_authority_and_preserves_json_status(self):
        fx = Fixture()
        for flags in (("--push",), ("--accept-plan", "a"*64), ("--force",), ("--apply",),
                      ("--check",), ("--push", "--check"), ("--pu",)):
            with self.subTest(flags=flags):
                result = fx.cli(*flags)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        plan = json.loads(fx.cli().stdout)
        result = fx.cli("--push", "--accept-plan", plan["plan_sha256"],
                       env={**fx.fx.env, "GIT_SSH_COMMAND": "echo BAD", "GIT_CONFIG_COUNT": "1",
                            "GIT_CONFIG_KEY_0": "push.default", "GIT_CONFIG_VALUE_0": "matching"})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "published")

    def test_ssh_target_validation_and_strict_protocol_command(self):
        endpoint = publish.ssh_endpoint("ssh://git@github.com/owner/repo.git")
        self.assertEqual(endpoint["url"], "ssh://git@github.com:22/owner/repo.git")
        for url in ("origin", "git@github.com:owner/repo.git", "https://github.com/a/b",
                    "ssh://root@host/a/b", "ssh://git:secret@host/a/b", "ssh://git@host:0/a",
                    "ssh://git@host/a/../b", "ssh://git@host/a?x=1", "ssh://git@host/%2fetc",
                    "ssh://git@host/a\nb", "ssh://git@host/a$(touch-x)", "ssh://git@0.0.0.0/a"):
            with self.subTest(url=url), self.assertRaises(publish.fleet.Refused):
                publish.ssh_endpoint(url)
        calls = []
        def inspect(argv, timeout, env):
            calls.append((argv, env.copy()))
            command = env["GIT_SSH_COMMAND"]
            self.assertIn("StrictHostKeyChecking=yes", command)
            self.assertIn("ForwardAgent=no", command)
            self.assertIn("ProxyCommand=none", command)
            self.assertNotIn(" -n", command)
            self.assertEqual(env["GIT_ALLOW_PROTOCOL"], "ssh")
            return 0, b""
        # Test the exact production argv/environment builder without an SSH
        # connection. /bin/true is only a dependency injection in this unit test.
        with publish.remote_transport(endpoint, b"reviewed-host-key", b"selected-identity", 30,
                                      runner=inspect, ssh="/bin/true") as remote:
            remote("query", "refs/heads/main")
            remote("push", "refs/heads/main", "a"*40, "b"*40, Path("/tmp"))
        self.assertEqual(len(calls), 2)
        self.assertIn("--force-with-lease=refs/heads/main:" + "a"*40, calls[1][0])
        self.assertEqual(calls[1][0][-1], "b"*40 + ":refs/heads/main")
        self.assertNotIn("--force", calls[1][0])

    def test_unexpected_remote_response_cannot_pass(self):
        fx = Fixture()
        cases = [(0,b""), (0, (fx.base+"\trefs/heads/other\n").encode()),
                 (0, (fx.base+"\trefs/heads/main\n") .encode()*2),
                 (0,b"ref: refs/heads/elsewhere\trefs/heads/main\n"), (23,b"private server output")]
        for response in cases:
            with self.subTest(response=response), self.assertRaises(publish.fleet.Refused):
                fx.preview(invoke=lambda *a: response)
        self.assertFalse(fx.state.exists())


    def test_even_an_included_competing_remote_commit_requires_new_approval(self):
        fx = Fixture()
        # Candidate includes intermediate, so a normal push would still be a
        # fast-forward after that update. The exact reviewed lease must refuse.
        middle = fx.fx.commit("middle", [fx.base], {"middle": ("100644", b"middle")})
        last = fx.fx.commit("last", [middle], {"feature": ("100644", b"last")})
        fx.transfer(fx.fx.source, fx.repo, last)
        spec = fx.tested["plan"]["specification"]
        fx.run = fx.root / "replacement-tests"
        kw = dict(repository=fx.repo, commit=last, spec=spec, output=fx.run, timeout=30)
        preview = runner.execute(**kw)
        fx.tested = runner.execute(**kw, approval=preview["plan_sha256"])
        fx.candidate, fx.test_plan = last, preview["plan_sha256"]
        fx.fx.git(fx.repo, "update-ref", "refs/heads/release", last)
        fx.transfer(fx.repo, fx.remote, middle)
        plan = fx.preview()
        with publish.remote_transport(fx.endpoint,b"",b"",30) as real:
            def raced(mode,*args):
                if mode=="push":
                    fx.fx.git(fx.remote,"update-ref","refs/heads/main",middle,fx.base)
                return real(mode,*args)
            with self.assertRaisesRegex(publish.fleet.Refused,"push_result_unconfirmed"):
                fx.preview(approval=plan["plan_sha256"],invoke=raced)
        self.assertEqual(fx.value(),middle)

    def test_local_branch_change_during_last_remote_probe_stops_push(self):
        fx=Fixture()
        plan=fx.preview()
        calls=[]
        with publish.remote_transport(fx.endpoint,b"",b"",30) as real:
            def raced(mode,*args):
                calls.append(mode)
                if calls==["query","query"]:
                    fx.fx.git(fx.repo,"update-ref","refs/heads/release",fx.base)
                return real(mode,*args)
            with self.assertRaisesRegex(publish.fleet.Refused,"local_branch_not_exact"):
                fx.preview(approval=plan["plan_sha256"],invoke=raced)
        self.assertEqual(calls,["query","query"])
        self.assertEqual(fx.value(),fx.base)
        self.assertFalse((fx.state/"attempt.json").exists())

    def test_push_reply_is_exact_and_never_accepts_forced_new_or_extra_refs(self):
        ref, head="refs/heads/main","a"*40
        good=(head+":"+ref).encode()
        for raw in (b"", b"+\t"+good+b"\tforced\n", b"*\t"+good+b"\tnew\n",
                    b" \t"+good+b"\tOK\n \t"+good+b"\tOK\n",
                    b" \t"+head.encode()+b":refs/heads/other\tOK\n"):
            with self.subTest(raw=raw),self.assertRaises(publish.fleet.Refused):
                publish.push_accepted(0,raw,ref,head)

    def test_local_remote_and_ssh_key_inputs_cannot_be_mixed(self):
        fx=Fixture()
        result=fx.cli("--known-hosts","/nonexistent","--identity-file","/nonexistent")
        self.assertEqual(result.returncode,2)
        self.assertIn("ssh_inputs_not_used",result.stdout)
        self.assertFalse(fx.state.exists())

    def test_unrelated_environment_is_not_passed_to_remote_git(self):
        endpoint=publish.ssh_endpoint("ssh://git@host/repo.git")
        original=os.environ.get("PUBLISH_PRIVATE_SECRET")
        os.environ["PUBLISH_PRIVATE_SECRET"]="never-inherit"
        try:
            def inspect(argv,timeout,env):
                self.assertNotIn("PUBLISH_PRIVATE_SECRET",env)
                self.assertNotIn("GIT_CONFIG_PARAMETERS",env)
                self.assertNotIn("GIT_CONFIG_COUNT",env)
                self.assertEqual(env["GIT_CONFIG_GLOBAL"],"/dev/null")
                self.assertEqual(argv[argv.index("-C")+1],"/")
                return 0,b""
            with publish.remote_transport(endpoint,b"key",b"identity",30,runner=inspect,ssh="/bin/true") as call:
                call("query","refs/heads/main")
        finally:
            if original is None: os.environ.pop("PUBLISH_PRIVATE_SECRET",None)
            else: os.environ["PUBLISH_PRIVATE_SECRET"]=original


class PublicationRecoveryTests(unittest.TestCase):
    def test_check_queries_remote_without_replaying_or_writing(self):
        fx = Fixture()
        result = fx.apply()
        before = fx.contents(fx.root)
        checked = fx.check(result)
        self.assertEqual(checked["status"], "matched")
        self.assertFalse(checked["push_started"])
        self.assertFalse(checked["publication_provenance_verified"])
        self.assertEqual(fx.contents(fx.root), before)

    def test_check_does_not_trust_saved_success(self):
        fx = Fixture()
        result = fx.apply()
        fx.fx.git(fx.remote, "update-ref", "refs/heads/main", fx.base)
        before = fx.contents(fx.root)
        checked = fx.check(result)
        self.assertEqual(checked["remote_status"], "not_published")
        self.assertEqual(checked["status"], "attention")
        self.assertEqual(fx.contents(fx.root), before)

    def test_check_survives_local_branch_movement(self):
        fx = Fixture()
        result = fx.apply()
        fx.fx.git(fx.repo, "update-ref", "refs/heads/release", fx.base)
        self.assertEqual(fx.check(result)["status"], "matched")

    def test_changed_ref_during_observation_is_unconfirmed(self):
        fx = Fixture()
        result = fx.apply()
        with publish.remote_transport(fx.endpoint,b"",b"",30) as real:
            count = 0
            def moving(*args):
                nonlocal count
                count += 1
                if count == 2:
                    fx.fx.git(fx.remote,"update-ref","refs/heads/main",fx.base)
                return real(*args)
            self.assertEqual(fx.check(result,invoke=moving)["remote_status"], "unconfirmed")

    def test_changed_journal_or_evidence_is_refused_without_push(self):
        fx = Fixture()
        result = fx.apply()
        (fx.state/"attempt.json").write_bytes(publish.encoded({"schema":publish.SCHEMA,"plan_sha256":"a"*64}))
        with self.assertRaisesRegex(publish.fleet.Refused,"attempt_mismatch"):
            fx.check(result)
        self.assertEqual(fx.value(),fx.candidate)

    def test_sigkill_before_and_after_real_push_is_queryable_not_retried(self):
        for after in (False, True):
            with self.subTest(after=after):
                fx=Fixture()
                plan=fx.preview()
                marker=fx.root/"boundary"
                driver=fx.root/"driver.py"
                driver.write_text(f"""import importlib.util,time
from pathlib import Path
s=importlib.util.spec_from_file_location('publish',{str(SCRIPT)!r})
p=importlib.util.module_from_spec(s);s.loader.exec_module(p)
endpoint=p.local_endpoint({str(fx.remote)!r},30)
with p.remote_transport(endpoint,b'',b'',30) as real:
 def invoke(mode,*args):
  if mode=='push':
   result=real(mode,*args) if {after!r} else None
   Path({str(marker)!r}).write_text('reached')
   time.sleep(30)
   return result if {after!r} else real(mode,*args)
  return real(mode,*args)
 p.publish_candidate({str(fx.run)!r},{str(fx.repo)!r},{fx.test_plan!r},'release','main',
 {fx.base!r},endpoint,b'',b'',{str(fx.state)!r},30,{plan['plan_sha256']!r},invoke=invoke)
""")
                process=subprocess.Popen([sys.executable,"-I",str(driver)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=fx.fx.env)
                try:
                    deadline=time.monotonic()+15
                    while not marker.exists() and process.poll() is None and time.monotonic()<deadline:
                        time.sleep(0.01)
                    self.assertTrue(marker.exists())
                    self.assertTrue((fx.state/"attempt.json").exists())
                    os.kill(process.pid,signal.SIGKILL)
                    process.wait(timeout=5)
                finally:
                    if process.poll() is None: process.kill()
                    process.communicate(timeout=5)
                self.assertFalse((fx.state/"result.json").exists())
                before=fx.contents(fx.state)
                checked=fx.check(plan)
                self.assertEqual(checked["remote_status"],"matched" if after else "not_published")
                self.assertEqual(fx.contents(fx.state),before)
                self.assertEqual(fx.value(),fx.candidate if after else fx.base)


    def test_check_refuses_forged_result_and_unexpected_state_members(self):
        fx=Fixture(); result=fx.apply()
        original=(fx.state/"result.json").read_bytes()
        changed=json.loads(original); changed["plan_sha256"]="e"*64
        (fx.state/"result.json").write_bytes(publish.encoded(changed))
        with self.assertRaisesRegex(publish.fleet.Refused,"publication_result_mismatch"):
            fx.check(result)
        (fx.state/"result.json").write_bytes(original)
        (fx.state/"unexpected").write_text("not a journal member")
        with self.assertRaisesRegex(publish.fleet.Refused,"unexpected_publication_state"):
            fx.check(result)

    def test_check_detects_state_replacement_and_lock_contention(self):
        import fcntl
        fx=Fixture(); result=fx.apply()
        with publish.fleet.directory_fd(fx.state,private=True) as fd:
            fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
            proc=fx.cli("--check","--accept-plan",result["plan_sha256"])
            self.assertEqual(proc.returncode,2)
            self.assertIn("fleet_operation_in_progress",proc.stdout)
        before=fx.contents(fx.state)
        checked=fx.check(result)
        self.assertEqual(checked["status"],"matched")
        self.assertEqual(fx.contents(fx.state),before)

    def test_remote_unavailable_is_not_reported_as_missing_or_retryable(self):
        fx=Fixture(); result=fx.apply()
        before=fx.contents(fx.root)
        calls=[]
        def offline(*args):
            calls.append(args)
            return 128,b""
        with self.assertRaisesRegex(publish.fleet.Refused,"remote_ref_query_failed"):
            fx.check(result,invoke=offline)
        self.assertEqual(len(calls),1)
        self.assertEqual(calls[0][0],"query")
        self.assertEqual(fx.contents(fx.root),before)


if __name__ == "__main__":
    if os.geteuid() == 0:
        os.setgroups([]); os.setgid(65534); os.setuid(65534)
        os.execv(sys.executable,[sys.executable,"-B",__file__,*sys.argv[1:]])
    unittest.main()
