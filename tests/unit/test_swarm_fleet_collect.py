#!/usr/bin/env python3
"""Real Git histories and unprivileged remote programs; no SSH hosts or agents."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "scripts/swarm-fleet-collect.py"
spec = importlib.util.spec_from_file_location("collection", SOURCE)
collection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collection)
fleet = collection.fleet


class CollectionTests(unittest.TestCase):
    def setUp(self):
        # Retain all disposable fixtures; never clean up a user's repository.
        self.root = Path(tempfile.mkdtemp(prefix="acfs-collection-test-"))
        self.root.chmod(0o755)
        self.uid = 65534 if os.geteuid() == 0 else os.geteuid()
        self.gid = 65534 if os.geteuid() == 0 else os.getegid()
        self.credentials = {"user": self.uid, "group": self.gid, "extra_groups": []} if os.geteuid() == 0 else {}
        self.env = {"PATH": "/usr/bin:/bin", "HOME": str(self.root), "LANG": "C.UTF-8"}
        self.local = self.root / "local"
        self.local.mkdir(mode=0o700)
        self.known, self.key = b"independently-verified-host-key\n", b"test-only-identity\n"
        self.repos, self.bases, self.heads = {}, {}, {}
        self.hosts = []
        for name in ("alpha", "beta"):
            repo, base = self.repository(name)
            self.write(repo / "app.txt", "committed " + name + "\n")
            self.git(repo, "add", "app.txt")
            self.git(repo, "commit", "-qm", "Implement " + name)
            self.repos[name], self.bases[name], self.heads[name] = repo, base, self.git(repo, "rev-parse", "HEAD").strip()
            self.hosts.append({"id": name, "host": name + ".invalid", "user": "worker", "port": 22,
                "request": {"repo": str(repo), "session": name, "receipt": "/home/worker/" + name + ".json",
                    "agents": [{"agent_name": name.title(), "agent_type": "codex"}],
                    "profile": "balanced", "workload": "standard", "accept_warnings": False}})
        self.launch = self.local / "launch"
        self.launch_plan = fleet.build_plan({"schema": fleet.SPEC_SCHEMA, "hosts": self.hosts},
                                             self.known, self.key, self.launch, 90)
        result, code = fleet.execute(self.launch_plan, "launch", fleet.digest(fleet.encoded(self.launch_plan)), self.native)
        self.assertEqual(code, 0, result)
        self.selection = {"schema": collection.SPEC_SCHEMA,
                          "hosts": [{"id": h["id"], "base_commit": self.bases[h["id"]]} for h in self.hosts]}
        self.out = self.local / "artifacts"
        self.calls = []

    def own(self, path):
        if os.geteuid() == 0:
            os.chown(path, self.uid, self.gid)

    def write(self, path, data):
        path.write_bytes(data if isinstance(data, bytes) else data.encode())
        self.own(path)

    def git(self, repo, *args, allowed=(0,)):
        result = subprocess.run(["/usr/bin/git", "-C", str(repo), *args], env=self.env,
                                 capture_output=True, timeout=10, **self.credentials)
        self.assertIn(result.returncode, allowed, result.stderr.decode(errors="replace"))
        return result.stdout.decode()

    def repository(self, name, fmt="sha1"):
        repo = self.root / name
        repo.mkdir(mode=0o700)
        self.own(repo)
        self.git(repo, "init", "-q", "-b", "main", "--object-format=" + fmt)
        self.git(repo, "config", "user.name", "ACFS Test")
        self.git(repo, "config", "user.email", "test@example.invalid")
        self.write(repo / "app.txt", "base\n")
        self.git(repo, "add", "app.txt")
        self.git(repo, "commit", "-qm", "Baseline")
        return repo, self.git(repo, "rev-parse", "HEAD").strip()

    def native(self, host, mode):
        request = host["request"]
        value = {"schema": fleet.NATIVE_SCHEMA, "request": request, "work_dispatched": False,
                 "authentication_verified": False, "agent_mail_registered": False,
                 "review_sha256": fleet.native_hash(request), "starts_agents": mode == "launch"}
        if mode == "preview":
            value.update(status="preview", admission={"status": "pass", "recommendation": "launch",
                         "safe_agents": 2, "recommended_agents": 2})
        else:
            agent = request["agents"][0]
            value.update(status="ready", targets=[{"slot": 1, **agent, "pane": "%3", "pane_pid": "301",
                         "server_pid": "300", "session_id": "$2", "session_created": "1780000000"}])
        return 0, fleet.encoded(value)

    def invoke(self, host, base, mode, snapshot=None):
        self.calls.append((host["id"], mode))
        # Actual production remote command, passed literally through a real shell.
        result = subprocess.run(["/bin/bash", "--noprofile", "--norc", "-p", "-c",
                                 collection.remote_command(host, base, mode, snapshot, 10)],
                                 env=self.env, capture_output=True, timeout=15, **self.credentials)
        return result.returncode, result.stdout

    def run_collection(self, approval=None, invoke=None):
        return collection.execute(self.launch, self.selection, self.known, self.key, self.out, 90,
                                  approval, invoke or self.invoke)

    def collect(self):
        preview, code = self.run_collection()
        self.assertEqual(code, 0, preview)
        result, code = self.run_collection(preview["plan_sha256"])
        self.assertEqual(code, 0, result)
        return result

    def members(self, directory):
        return {str(p.relative_to(directory)): (p.stat().st_mode, p.read_bytes())
                for p in directory.rglob("*") if p.is_file()}

    def test_preview_is_repeatable_read_only_and_in_original_order(self):
        self.selection["hosts"].reverse()
        before = self.members(self.root)
        first, code = self.run_collection()
        second, code2 = self.run_collection()
        self.assertEqual((code, code2), (0, 0), first)
        self.assertEqual(first, second)
        self.assertEqual([r["id"] for r in first["plan"]["hosts"]], ["alpha", "beta"])
        self.assertEqual(self.members(self.root), before)
        self.assertFalse(self.out.exists())
        self.assertFalse(first["task_completion_verified"])

    def test_bundles_verify_and_import_exact_commits_without_source_writes(self):
        before = {name: self.members(repo) for name, repo in self.repos.items()}
        result = self.collect()
        self.assertEqual(result["status"], "collected")
        self.assertEqual(self.out.stat().st_mode & 0o777, 0o700)
        self.assertEqual(collection.verify(self.out)["status"], "verified")
        for name, repo in self.repos.items():
            self.assertEqual(self.members(repo), before[name])
            self.assertEqual((self.out / (name + ".bundle")).stat().st_mode & 0o777, 0o600)
            recipient, _ = self.repository("recipient-" + name)
            self.git(recipient, "fetch", str(repo), self.bases[name])
            artifact = recipient / "input.bundle"
            self.write(artifact, (self.out / (name + ".bundle")).read_bytes())
            self.git(recipient, "bundle", "verify", str(artifact))
            self.git(recipient, "fetch", str(artifact), "HEAD:refs/heads/review")
            self.assertEqual(self.git(recipient, "rev-parse", "review").strip(), self.heads[name])
            self.assertEqual(self.git(recipient, "show", "review:app.txt"), "committed " + name + "\n")

    def test_binary_deleted_and_executable_files_survive_import(self):
        repo = self.repos["alpha"]
        binary = bytes(range(256)) * 300
        self.write(repo / "binary.dat", binary)
        self.write(repo / "run.sh", "#!/bin/sh\nexit 0\n")
        (repo / "run.sh").chmod(0o755)
        # Stage a deletion without deleting the fixture file from the filesystem.
        self.git(repo, "update-index", "--force-remove", "app.txt")
        self.git(repo, "add", "binary.dat", "run.sh")
        self.git(repo, "commit", "-qm", "Binary and executable change")
        result = self.collect()
        head = result["plan"]["hosts"][0]["snapshot"]["head_commit"]
        recipient, _ = self.repository("binary-recipient")
        self.git(recipient, "fetch", str(repo), self.bases["alpha"])
        artifact = recipient / "input.bundle"
        self.write(artifact, (self.out / "alpha.bundle").read_bytes())
        self.git(recipient, "fetch", str(artifact), "HEAD:refs/heads/review")
        self.assertEqual(self.git(recipient, "rev-parse", "review").strip(), head)
        raw = subprocess.run(["git", "-C", str(recipient), "show", "review:binary.dat"],
                              capture_output=True, env=self.env, **self.credentials)
        self.assertEqual(raw.stdout, binary)
        self.assertIn("100755", self.git(recipient, "ls-tree", "review", "run.sh"))
        self.assertEqual(self.git(recipient, "ls-tree", "review", "app.txt"), "")

    def test_sha256_repository_bundle(self):
        repo, base = self.repository("sha256", fmt="sha256")
        self.git(repo, "commit", "--allow-empty", "-qm", "Empty but real commit")
        host = copy.deepcopy(self.hosts[0]); host["request"]["repo"] = str(repo)
        snapshot, _ = collection.observe(host, base, "preview", self.invoke)
        self.assertEqual(snapshot["object_format"], "sha256")
        self.assertEqual(snapshot["net_changed_paths"], [])
        _, raw = collection.observe(host, base, "collect", self.invoke, snapshot)
        artifact = repo / "sha256.bundle"
        self.write(artifact, raw)
        self.git(repo, "bundle", "verify", str(artifact))

    def test_merge_history_keeps_original_topology(self):
        repo = self.repos["alpha"]
        self.git(repo, "branch", "side", self.bases["alpha"])
        self.git(repo, "checkout", "-q", "side")
        self.write(repo / "side.txt", "side branch\n")
        self.git(repo, "add", "side.txt"); self.git(repo, "commit", "-qm", "Side implementation")
        self.git(repo, "checkout", "-q", "main")
        self.git(repo, "merge", "--no-ff", "-qm", "Reviewed merge", "side")
        snapshot, _ = collection.observe(self.hosts[0], self.bases["alpha"], "preview", self.invoke)
        _, raw = collection.observe(self.hosts[0], self.bases["alpha"], "collect", self.invoke, snapshot)
        artifact = repo / "merge.bundle"; self.write(artifact, raw)
        self.git(repo, "bundle", "verify", str(artifact))
        self.assertEqual(snapshot["commit_count"], 3)

    def test_unchanged_range_is_explicit_without_empty_bundle(self):
        self.selection["hosts"][0]["base_commit"] = self.heads["alpha"]
        result = self.collect()
        self.assertIsNone(result["artifacts"][0]["file"])
        self.assertEqual(result["artifacts"][0]["bytes"], 0)
        self.assertFalse((self.out / "alpha.bundle").exists())
        self.assertEqual(collection.verify(self.out)["status"], "verified")

    def test_uncommitted_and_untracked_secrets_are_not_collected(self):
        repo = self.repos["alpha"]
        self.write(repo / "app.txt", "UNCOMMITTED_SECRET_12345")
        self.git(repo, "add", "app.txt")
        self.write(repo / ".env", "UNTRACKED_SECRET_67890")
        before = self.members(repo)
        result = self.collect()
        self.assertFalse(result["worktree_included"])
        self.assertEqual(self.members(repo), before)
        recipient, _ = self.repository("dirty-recipient")
        self.git(recipient, "fetch", str(repo), self.bases["alpha"])
        artifact = recipient / "input.bundle"; self.write(artifact, (self.out / "alpha.bundle").read_bytes())
        self.git(recipient, "fetch", str(artifact), "HEAD:refs/heads/review")
        self.assertEqual(self.git(recipient, "show", "review:app.txt"), "committed alpha\n")
        self.assertEqual(self.git(recipient, "ls-tree", "review", ".env"), "")

    def test_helpers_hooks_and_proxy_environment_are_not_executed(self):
        repo = self.repos["alpha"]
        hook = repo / "bad-hook"
        self.write(hook, "#!/bin/sh\nprintf bad > '" + str(repo / "HOOK_RAN") + "'\n")
        hook.chmod(0o755)
        self.git(repo, "config", "core.fsmonitor", str(hook))
        self.git(repo, "config", "diff.external", str(hook))
        self.git(repo, "config", "diff.poison.textconv", str(hook))
        self.write(repo / ".gitattributes", "* diff=poison\n")
        self.env.update(GIT_EXTERNAL_DIFF=str(hook), GIT_DIR="/nonexistent", GIT_CONFIG_COUNT="1",
                        GIT_CONFIG_KEY_0="core.fsmonitor", GIT_CONFIG_VALUE_0=str(hook))
        result = self.collect()
        self.assertEqual(result["status"], "collected")
        self.assertFalse((repo / "HOOK_RAN").exists())

    def test_partial_clone_is_refused_without_lazy_fetch(self):
        repo = self.repos["beta"]
        self.git(repo, "config", "remote.origin.url", "https://must-not-contact.invalid/repo")
        self.git(repo, "config", "remote.origin.promisor", "true")
        result, code = self.run_collection()
        self.assertEqual(code, 1)
        self.assertEqual(result["errors"][0]["id"], "beta")
        self.assertFalse(self.out.exists())
        self.assertTrue(all(mode == "preview" for _, mode in self.calls))

    def test_unrelated_base_is_refused(self):
        repo, base = self.repository("unrelated")
        self.git(repo, "commit", "--allow-empty", "-qm", "Unique unrelated commit")
        base = self.git(repo, "rev-parse", "HEAD").strip()
        self.selection["hosts"][0]["base_commit"] = base
        result, code = self.run_collection()
        self.assertEqual(code, 1)
        self.assertFalse(self.out.exists())

    def test_changed_head_invalidates_approval_before_any_writes(self):
        preview, code = self.run_collection()
        self.git(self.repos["alpha"], "commit", "--allow-empty", "-qm", "New work")
        with self.assertRaisesRegex(fleet.Refused, "collection_approval_mismatch"):
            self.run_collection(preview["plan_sha256"])
        self.assertFalse(self.out.exists())
        self.assertTrue(all(mode == "preview" for _, mode in self.calls))

    def test_changed_head_during_download_retains_partial_without_completion_marker(self):
        preview, _ = self.run_collection()
        def changed(host, base, mode, snapshot=None):
            if host["id"] == "beta" and mode == "collect":
                self.git(self.repos["beta"], "commit", "--allow-empty", "-qm", "Concurrent commit")
            return self.invoke(host, base, mode, snapshot)
        result, code = self.run_collection(preview["plan_sha256"], changed)
        self.assertEqual(code, 1)
        self.assertEqual(result["status"], "partial")
        self.assertTrue((self.out / "alpha.bundle").exists())
        self.assertFalse((self.out / "manifest.json").exists())
        with self.assertRaises(fleet.Refused): collection.verify(self.out)
        before = self.members(self.out)
        with self.assertRaisesRegex(fleet.Refused, "state_already_exists"):
            self.run_collection()
        self.assertEqual(self.members(self.out), before)

    def test_corrupt_pack_is_rejected_even_with_recomputed_transport_hash(self):
        preview, _ = self.run_collection()
        def corrupt(host, base, mode, snapshot=None):
            code, raw = self.invoke(host, base, mode, snapshot)
            if mode == "collect":
                header, _, bundle = raw.partition(b"\n")
                value = json.loads(header)
                bundle = bundle[:-1] + bytes([bundle[-1] ^ 1])
                value["bundle_sha256"] = hashlib.sha256(bundle).hexdigest()
                raw = json.dumps(value).encode() + b"\n" + bundle
            return code, raw
        result, code = self.run_collection(preview["plan_sha256"], corrupt)
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "bundle_pack_checksum_mismatch")
        self.assertFalse((self.out / "alpha.bundle").exists())

    def test_offline_verification_detects_modified_artifact(self):
        self.collect()
        path = self.out / "alpha.bundle"
        path.write_bytes(path.read_bytes() + b"changed")
        with self.assertRaisesRegex(fleet.Refused, "artifact_integrity_mismatch"):
            collection.verify(self.out)

    def test_symlink_repository_is_refused(self):
        repo = self.repos["alpha"]
        repo.rename(self.root / "retained-alpha")
        repo.symlink_to(self.root / "retained-alpha", target_is_directory=True)
        result, code = self.run_collection()
        self.assertEqual(code, 1)
        self.assertFalse(self.out.exists())

    def test_linked_worktree_is_supported(self):
        repo = self.repos["alpha"]
        worktree = self.root / "worktree-parent"
        worktree.mkdir(mode=0o700); self.own(worktree)
        target = worktree / "linked"
        self.git(repo, "worktree", "add", "-q", "--detach", str(target), "HEAD")
        host = copy.deepcopy(self.hosts[0]); host["request"]["repo"] = str(target)
        snapshot, _ = collection.observe(host, self.bases["alpha"], "preview", self.invoke)
        _, bundle = collection.observe(host, self.bases["alpha"], "collect", self.invoke, snapshot)
        collection.validate_bundle(bundle, snapshot)

    def test_invalid_selections_fail_before_remote_calls(self):
        for bad in ({"schema": collection.SPEC_SCHEMA, "hosts": []},
                    {"schema": collection.SPEC_SCHEMA, "hosts": [{"id": "alpha", "base_commit": "HEAD~2"}]},
                    {"schema": collection.SPEC_SCHEMA, "hosts": [{"id": "other", "base_commit": "a" * 40}]},
                    {"schema": collection.SPEC_SCHEMA, "hosts": [self.selection["hosts"][0]] * 2}):
            with self.subTest(bad=bad):
                self.selection = bad
                with self.assertRaises(fleet.Refused): self.run_collection()
        self.assertEqual(self.calls, [])

    def test_wrong_trust_and_output_in_journal_fail_before_remote_calls(self):
        self.key = b"different"
        with self.assertRaisesRegex(fleet.Refused, "launch_context_mismatch"): self.run_collection()
        self.key = b"test-only-identity\n"
        self.out = self.launch / "nested"
        with self.assertRaisesRegex(fleet.Refused, "output_inside_launch_journal"): self.run_collection()
        self.assertEqual(self.calls, [])

    def test_source_mutation_invalidates_preview(self):
        def mutate(host, base, mode, snapshot=None):
            result = self.invoke(host, base, mode, snapshot)
            (self.launch / "extra.json").write_text("{}")
            return result
        with self.assertRaisesRegex(fleet.Refused, "state_changed_during_operation"):
            self.run_collection(invoke=mutate)
        self.assertFalse(self.out.exists())

    def test_local_journal_lock_is_respected(self):
        import fcntl
        fd = os.open(self.launch, os.O_RDONLY | os.O_DIRECTORY)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(fleet.Refused, "fleet_operation_in_progress"): self.run_collection()
        finally:
            os.close(fd)
        self.assertEqual(self.calls, [])

    def test_offline_cli_verify_needs_no_ssh_inputs_and_leaves_files_unchanged(self):
        self.collect()
        before = self.members(self.out)
        result = subprocess.run([sys.executable, "-I", str(SOURCE), "--verify", str(self.out)],
                                 capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "verified")
        self.assertEqual(self.members(self.out), before)

    def test_capture_default_and_explicit_binary_limits(self):
        argv = [sys.executable, "-I", "-c", "import sys; sys.stdout.buffer.write(b'x' * 2097152)"]
        with self.assertRaisesRegex(fleet.Refused, "ssh_output_limit"):
            fleet.capture(argv, 5, self.env)
        code, raw = fleet.capture(argv, 5, self.env, limit=collection.MAX_BUNDLE)
        self.assertEqual((code, len(raw)), (0, 2097152))
        with self.assertRaisesRegex(fleet.Refused, "invalid_capture_limit"):
            fleet.capture(argv, 5, self.env, limit=True)

    def test_capture_timeout_remains_bounded(self):
        import time
        before = time.monotonic()
        with self.assertRaisesRegex(fleet.Refused, "ssh_timeout"):
            fleet.capture([sys.executable, "-I", "-c", "import time; time.sleep(10)"], 0.15,
                           self.env, limit=collection.MAX_BUNDLE)
        self.assertLess(time.monotonic() - before, 2)


if __name__ == "__main__":
    unittest.main()
