#!/usr/bin/env python3
"""Real offline Git collections and review-ref imports; all fixtures are retained."""
import copy
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/swarm-fleet-collect.py"
spec = importlib.util.spec_from_file_location("collection_import_tests", SCRIPT)
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)
fleet = c.fleet
ENV = {"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C", "HOME": "/nonexistent",
       "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
       "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
       "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "fixture@example.invalid"}


def git(repo, *args, data=None, allowed=(0,)):
    result = subprocess.run(["/usr/bin/git", "-C", str(repo), *args], input=data,
                            capture_output=True, env=ENV, timeout=15)
    if result.returncode not in allowed:
        raise AssertionError((args, result.returncode, result.stderr.decode()))
    return result.stdout


def members(root):
    return {str(p.relative_to(root)): ("link", os.readlink(p)) if p.is_symlink()
            else ("dir", p.stat().st_mode & 0o777) if p.is_dir()
            else ("file", p.stat().st_mode & 0o777, p.read_bytes()) for p in root.rglob("*")}


class ImportFixture:
    def __init__(self, fmt="sha1", unchanged=False):
        self.root = Path(tempfile.mkdtemp(prefix="acfs-fleet-import-test-"))
        self.source, self.dest = self.root / "source", self.root / "destination"
        self.source.mkdir()
        git(self.source, "init", "-b", "main", "--object-format=" + fmt)
        (self.source / "original").write_bytes(b"base\n")
        (self.source / "obsolete").write_bytes(b"retained fixture, deleted only from the Git tree\n")
        git(self.source, "add", ".")
        git(self.source, "commit", "-m", "base")
        self.base = git(self.source, "rev-parse", "HEAD").decode().strip()
        git(self.root, "clone", "--no-local", str(self.source), str(self.dest))
        self.heads, hosts = {}, []
        for index, host_id in enumerate(("builder", "reviewer"), 1):
            repo = self.root / host_id
            git(self.root, "clone", "--no-local", str(self.source), str(repo))
            if not unchanged:
                (repo / (host_id + ".bin")).write_bytes(bytes(range(256)) * 10)
                executable = repo / (host_id + ".sh")
                executable.write_text("#!/bin/sh\nprintf '%s\\n' reviewed\n")
                executable.chmod(0o755)
                git(repo, "add", ".")
                git(repo, "update-index", "--force-remove", "obsolete")
                git(repo, "commit", "-m", "result " + host_id)
            self.heads[host_id] = git(repo, "rev-parse", "HEAD").decode().strip()
            hosts.append({"id": host_id, "host": "node" + str(index) + ".example", "user": "worker", "port": 22,
                          "request": {"repo": str(repo), "session": "wave" + str(index),
                                      "receipt": str(self.root / (host_id + "-launch.json")),
                                      "agents": [{"agent_name": host_id.title(), "agent_type": "codex"}],
                                      "profile": "balanced", "workload": "standard", "accept_warnings": False}})
        launch_path = self.root / "launch"
        plan = fleet.build_plan({"schema": fleet.SPEC_SCHEMA, "hosts": hosts}, b"known", b"key", str(launch_path), 90)
        def launch(host, mode):
            req = host["request"]
            value = {"schema": fleet.NATIVE_SCHEMA, "request": req, "review_sha256": fleet.native_hash(req),
                     "work_dispatched": False, "authentication_verified": False, "agent_mail_registered": False}
            if mode == "preview":
                value.update(status="preview", starts_agents=False,
                             admission={"status": "pass", "recommendation": "launch", "safe_agents": 2, "recommended_agents": 2})
            else:
                value.update(status="ready", starts_agents=True, targets=[{
                    "slot": 1, **req["agents"][0], "pane": "%1", "pane_pid": "100", "server_pid": "99",
                    "session_id": "$1", "session_created": "1700000000"}])
            return 0, fleet.encoded(value)
        report, code = fleet.execute(plan, "launch", fleet.digest(fleet.encoded(plan)), launch)
        if code: raise AssertionError(report)
        self.collection = self.root / "collection"
        self.selection = {"schema": c.SPEC_SCHEMA, "hosts": [{"id": h["id"], "base_commit": self.base} for h in hosts]}
        def invoke(host, base, mode, snapshot=None):
            command = c.remote_command(host, base, mode, snapshot, 90)
            result = subprocess.run(["/bin/sh", "-c", command], env={**ENV, "PATH": os.path.dirname(sys.executable) + ":/usr/bin:/bin"},
                                    capture_output=True, timeout=20)
            return result.returncode, result.stdout
        args = (str(launch_path), self.selection, b"known", b"key", str(self.collection), 90)
        preview, code = c.execute(*args, None, invoke)
        if code: raise AssertionError(preview)
        report, code = c.execute(*args, preview["plan_sha256"], invoke)
        if code: raise AssertionError(report)

    def preview(self, **options):
        return c.import_collection(self.collection, options.pop("repository", self.dest),
                                   options.pop("name", "wave1"), options.pop("hosts", []), 90, **options)

    def apply(self, **options):
        preview = self.preview(**options)
        return self.preview(approval=preview["plan_sha256"], **options)

    def cli(self, *args):
        return subprocess.run([sys.executable, "-I", str(SCRIPT), "--import", str(self.collection),
                               "--repository", str(self.dest), "--name", "wave1", *args],
                              capture_output=True, text=True, env=ENV, timeout=20)


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.fx = ImportFixture()

    def test_preview_checks_all_bundles_without_destination_or_collection_writes(self):
        fx = self.fx
        before, source = members(fx.dest), members(fx.collection)
        first, second = fx.preview(), fx.preview()
        self.assertEqual(first, second)
        self.assertEqual(first["status"], "preview")
        self.assertFalse(first["import_started"])
        self.assertEqual([r["ref"] for r in first["plan"]["refs"]],
                         ["refs/acfs/fleet/wave1/builder", "refs/acfs/fleet/wave1/reviewer"])
        self.assertEqual(members(fx.dest), before)
        self.assertEqual(members(fx.collection), source)

    def test_import_preserves_dirty_worktree_index_head_and_existing_refs(self):
        fx = self.fx
        (fx.dest / "original").write_text("staged change\n")
        git(fx.dest, "add", "original")
        (fx.dest / "original").write_text("unstaged change\n")
        (fx.dest / "untracked").write_text("retain me")
        before = {p: (fx.dest / p).read_bytes() for p in ("original", "untracked", "obsolete", ".git/index", ".git/HEAD")}
        source = members(fx.collection)
        result = fx.apply()
        self.assertEqual(result["status"], "imported")
        self.assertEqual(git(fx.dest, "rev-parse", "HEAD").decode().strip(), fx.base)
        for p, raw in before.items(): self.assertEqual((fx.dest / p).read_bytes(), raw)
        for host, head in fx.heads.items():
            ref = "refs/acfs/fleet/wave1/" + host
            self.assertEqual(git(fx.dest, "rev-parse", ref).decode().strip(), head)
            self.assertEqual(git(fx.dest, "show", ref + ":" + host + ".bin"), bytes(range(256)) * 10)
            self.assertTrue(git(fx.dest, "ls-tree", ref, host + ".sh").startswith(b"100755"))
            self.assertEqual(git(fx.dest, "ls-tree", ref, "obsolete"), b"")
        self.assertEqual(members(fx.collection), source)
        self.assertTrue(list((fx.dest / ".git/objects/pack").glob("*.keep")))

    def test_changed_approval_is_refused_before_writes(self):
        fx = self.fx
        before = members(fx.dest)
        with self.assertRaisesRegex(fleet.Refused, "import_approval_mismatch"):
            fx.preview(approval="0" * 64)
        self.assertEqual(members(fx.dest), before)

    def test_existing_ref_never_overwritten_even_with_same_head(self):
        fx = self.fx
        fx.apply()
        before = members(fx.dest)
        with self.assertRaisesRegex(fleet.Refused, "review_ref_already_exists"):
            fx.preview()
        self.assertEqual(members(fx.dest), before)

    def test_dangling_symbolic_ref_is_occupied_and_not_followed(self):
        fx = self.fx
        git(fx.dest, "symbolic-ref", "refs/acfs/fleet/wave1/builder", "refs/heads/unborn")
        before = members(fx.dest)
        with self.assertRaisesRegex(fleet.Refused, "review_ref_already_exists"):
            fx.preview()
        self.assertEqual(members(fx.dest), before)

    def test_selected_hosts_keep_collection_order_and_do_not_import_others(self):
        fx = self.fx
        preview = fx.preview(hosts=["reviewer", "builder"])
        self.assertEqual([e["id"] for e in preview["plan"]["hosts"]], ["builder", "reviewer"])
        fx.apply(hosts=["reviewer"])
        refs = git(fx.dest, "for-each-ref", "--format=%(refname)", "refs/acfs/").decode().splitlines()
        self.assertEqual(refs, ["refs/acfs/fleet/wave1/reviewer"])
        for hosts in (["missing"], ["builder", "builder"]):
            with self.assertRaises(fleet.Refused): fx.preview(hosts=hosts)

    def test_missing_destination_prerequisites_fail_without_any_import(self):
        fx = self.fx
        other = fx.root / "empty"
        other.mkdir()
        git(other, "init", "-b", "main")
        before = members(other)
        with self.assertRaises(fleet.Refused): fx.preview(repository=other)
        self.assertEqual(members(other), before)

    def test_corrupt_bundle_fails_before_destination_writes(self):
        fx = self.fx
        path = fx.collection / "reviewer.bundle"
        with path.open("ab") as f: f.write(b"broken")
        before = members(fx.dest)
        with self.assertRaises(fleet.Refused): fx.preview()
        self.assertEqual(members(fx.dest), before)

    def rewrite_bundle(self, host, raw):
        path = self.fx.collection / (host + ".bundle")
        path.write_bytes(raw)
        manifest = json.loads((self.fx.collection / "manifest.json").read_bytes())
        artifact = next(a for a in manifest["artifacts"] if a["id"] == host)
        artifact.update(bytes=len(raw), sha256=c.digest(raw))
        (self.fx.collection / "manifest.json").write_bytes(c.encoded(manifest))

    def test_last_bundle_missing_prerequisite_prevents_any_pack_write(self):
        fx = self.fx
        raw = (fx.collection / "reviewer.bundle").read_bytes()
        header, _, pack = raw.partition(b"\n\n")
        lines = header.split(b"\n")
        lines.insert(2, b"-" + b"f" * 40 + b" deliberately absent prerequisite")
        self.rewrite_bundle("reviewer", b"\n".join(lines) + b"\n\n" + pack)
        before = members(fx.dest)
        with self.assertRaises(fleet.Refused): fx.preview()
        self.assertEqual(members(fx.dest), before)

    def test_valid_transport_checksums_do_not_allow_malformed_git_objects(self):
        fx = self.fx
        raw = (fx.collection / "reviewer.bundle").read_bytes()
        header, _, pack = raw.partition(b"\n\n")
        broken = bytearray(pack[:-20])
        broken[15] ^= 255
        altered = bytes(broken) + hashlib.sha1(broken).digest()
        self.rewrite_bundle("reviewer", header + b"\n\n" + altered)
        # Framing and both transport checksums pass; Git must still refuse it.
        self.assertEqual(c.verify(fx.collection)["status"], "verified")
        preview = fx.preview()
        with self.assertRaisesRegex(fleet.Refused, "local_git_refused"):
            fx.preview(approval=preview["plan_sha256"])
        self.assertEqual(git(fx.dest, "for-each-ref", "refs/acfs/"), b"")
        self.assertEqual(git(fx.dest, "rev-parse", "HEAD").decode().strip(), fx.base)

    def test_wrong_recorded_commit_count_never_publishes_refs(self):
        fx = self.fx
        intent = json.loads((fx.collection / "intent.json").read_bytes())
        intent["plan"]["hosts"][1]["snapshot"]["commit_count"] += 1
        (fx.collection / "intent.json").write_bytes(c.encoded(intent))
        manifest = json.loads((fx.collection / "manifest.json").read_bytes())
        manifest["plan_sha256"] = c.digest(c.encoded(intent["plan"]))
        (fx.collection / "manifest.json").write_bytes(c.encoded(manifest))
        preview = fx.preview()
        with self.assertRaisesRegex(fleet.Refused, "imported_commit_count_mismatch"):
            fx.preview(approval=preview["plan_sha256"])
        self.assertTrue(c.IMPORT_STARTED)
        self.assertEqual(git(fx.dest, "for-each-ref", "refs/acfs/"), b"")
        self.assertEqual(git(fx.dest, "rev-parse", "HEAD").decode().strip(), fx.base)

    def test_ref_conflict_on_last_host_blocks_entire_transaction(self):
        fx = self.fx
        preview = fx.preview()
        git(fx.dest, "update-ref", "refs/acfs/fleet/wave1/reviewer", fx.base)
        before = members(fx.dest)
        with self.assertRaisesRegex(fleet.Refused, "review_ref_already_exists"):
            fx.preview(approval=preview["plan_sha256"])
        self.assertEqual(members(fx.dest), before)
        self.assertEqual(git(fx.dest, "show-ref", "--verify", "--quiet", "refs/acfs/fleet/wave1/builder", allowed=(1,)), b"")

    def test_new_destination_identity_invalidates_old_approval(self):
        fx = self.fx
        preview = fx.preview()
        fx.dest.rename(fx.root / "retained-destination")
        git(fx.root, "clone", "--no-local", str(fx.source), str(fx.dest))
        before = members(fx.dest)
        with self.assertRaisesRegex(fleet.Refused, "import_approval_mismatch"):
            fx.preview(approval=preview["plan_sha256"])
        self.assertEqual(members(fx.dest), before)

    def test_linked_worktree_import_changes_neither_checkout(self):
        fx = self.fx
        worktree = fx.root / "linked"
        git(fx.dest, "worktree", "add", "--detach", str(worktree), fx.base)
        index = git(worktree, "rev-parse", "--git-path", "index").decode().strip()
        before = Path(index).read_bytes()
        result = fx.apply(repository=worktree)
        self.assertEqual(result["status"], "imported")
        self.assertEqual(Path(index).read_bytes(), before)
        self.assertEqual(git(worktree, "rev-parse", "HEAD").decode().strip(), fx.base)
        self.assertEqual(git(fx.dest, "rev-parse", "HEAD").decode().strip(), fx.base)

    def test_shared_directory_lock_prevents_competing_import(self):
        fx = self.fx
        preview = fx.preview()
        fd = os.open(fx.dest / ".git", os.O_RDONLY | os.O_DIRECTORY)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = fx.cli("--apply", "--accept-plan", preview["plan_sha256"])
            self.assertEqual(result.returncode, 2)
            self.assertIn("fleet_operation_in_progress", result.stdout)
        finally:
            os.close(fd)

    def test_hooks_and_inherited_git_settings_cannot_execute(self):
        fx = self.fx
        marker = fx.root / "hook-ran"
        hook = fx.dest / ".git/hooks/reference-transaction"
        hook.write_text("#!/bin/sh\nprintf bad > '" + str(marker) + "'\nexit 1\n")
        hook.chmod(0o755)
        custom = fx.root / "gitconfig"
        custom.write_text("[core]\n hooksPath = " + str(hook.parent) + "\n")
        original = os.environ.copy()
        try:
            os.environ.update(GIT_DIR=str(fx.source / ".git"), GIT_CONFIG_GLOBAL=str(custom), GIT_TRACE="1")
            self.assertEqual(fx.apply()["status"], "imported")
        finally:
            os.environ.clear(); os.environ.update(original)
        self.assertFalse(marker.exists())
        self.assertEqual(git(fx.source, "for-each-ref", "refs/acfs/"), b"")

    def test_configuration_and_unsafe_path_refusals_do_not_write(self):
        fx = self.fx
        for key in ("remote.origin.promisor", "extensions.partialclone", "fsck.missingEmail"):
            git(fx.dest, "config", key, "true")
            with self.assertRaisesRegex(fleet.Refused, "destination_configuration_not_supported"): fx.preview()
            git(fx.dest, "config", "--unset", key)
        link = fx.root / "destination-link"
        link.symlink_to(fx.dest)
        with self.assertRaises((OSError, fleet.Refused)): fx.preview(repository=link)
        for name in ("../main", "HEAD", "bad/name", "--force", "space name", ""):
            with self.assertRaises(fleet.Refused): fx.preview(name=name)

    def test_cli_preview_apply_and_invalid_combinations(self):
        fx = self.fx
        result = fx.cli()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        preview = json.loads(result.stdout)
        for args in (("--apply",), ("--accept-plan", "a" * 64), ("--send",), ("--collect",), ("--verify", str(fx.collection))):
            result = fx.cli(*args)
            self.assertEqual(result.returncode, 2, result.stdout)
        result = fx.cli("--apply", "--accept-plan", preview["plan_sha256"])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "imported")


class FormatTests(unittest.TestCase):
    def test_sha256_round_trip(self):
        fx = ImportFixture(fmt="sha256")
        self.assertEqual(fx.apply()["status"], "imported")
        for host, head in fx.heads.items():
            self.assertEqual(len(head), 64)
            self.assertEqual(git(fx.dest, "rev-parse", "refs/acfs/fleet/wave1/" + host).decode().strip(), head)

    def test_unchanged_collection_is_noop(self):
        fx = ImportFixture(unchanged=True)
        before = members(fx.dest)
        self.assertEqual(fx.apply()["status"], "noop")
        self.assertEqual(members(fx.dest), before)


if __name__ == "__main__":
    if os.geteuid() == 0:
        # Exercise production nonroot boundaries, not patched os.geteuid calls.
        result = subprocess.run([sys.executable, "-B", str(Path(__file__).resolve()), *sys.argv[1:]],
                                user=65534, group=65534, env=ENV)
        sys.exit(result.returncode)
    unittest.main()
