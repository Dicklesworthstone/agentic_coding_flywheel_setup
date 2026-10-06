#!/usr/bin/env python3
"""Collect reviewed commit ranges and explicitly import them into local review refs.

Preview contacts the selected hosts but writes nothing. --collect saves private
incremental Git bundles; it never commits, fetches, checks out, merges or pushes
in a project. A separate offline --import preview/apply flow creates new review
refs without changing existing refs, HEAD, the index or the working tree.
Uncommitted files are deliberately not included.
"""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import importlib.util
import os
from pathlib import Path
import selectors
import shlex
import signal
import stat
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
_helper = Path(__file__).absolute().with_name("swarm-fleet-launch.py")
if _helper.is_symlink() or not _helper.is_file():
    raise SystemExit("Required trusted sibling swarm-fleet-launch.py is unavailable")
_spec = importlib.util.spec_from_file_location("acfs_collection_fleet", _helper)
fleet = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fleet)
require, encoded, decode, digest = fleet.require, fleet.encoded, fleet.decode, fleet.digest
SCHEMA = "acfs.swarm-fleet-collection.v1"
SPEC_SCHEMA = "acfs.swarm-fleet-collection-spec.v1"
MAX_BUNDLE = 16 * 1024 * 1024
IMPORT_SCHEMA = "acfs.swarm-fleet-import.v1"
IMPORT_STARTED = False

# Fixed read-only program. No executable, ref expression, command or environment
# is supplied by the selection. Git configuration that could start network or
# external diff/filter/fsmonitor helpers is disabled. No worktree is extracted.
REMOTE = r'''import hashlib, json, os, re, selectors, signal, stat, subprocess, sys, time
LIMIT = 1048576
MAX_BUNDLE = 16777216
class Refused(Exception): pass
def need(value, code):
    if not value: raise Refused(code)
def stop(signum, frame): raise Refused("remote_interrupted")
for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP): signal.signal(sig, stop)
def directory(path):
    need(isinstance(path, str) and path.startswith('/') and
         all(p not in ('', '.', '..') for p in path.split('/')[1:]), "unsafe_repository")
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.split('/')[1:]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd); fd = child
            info = os.fstat(fd)
            sticky = info.st_uid == 0 and info.st_mode & stat.S_ISVTX
            need(info.st_uid in (0, os.geteuid()) and (not info.st_mode & 0o022 or sticky), "unsafe_repository")
        need(info.st_uid == os.geteuid() and not info.st_mode & 0o022, "unsafe_repository")
        return fd
    except BaseException:
        os.close(fd)
        raise
ENV = {"PATH":"/usr/bin:/bin", "LANG":"C", "LC_ALL":"C", "HOME":"/nonexistent",
       "GIT_CONFIG_NOSYSTEM":"1", "GIT_CONFIG_GLOBAL":"/dev/null", "GIT_TERMINAL_PROMPT":"0",
       "GIT_OPTIONAL_LOCKS":"0", "GIT_NO_REPLACE_OBJECTS":"1", "GIT_GRAFT_FILE":"/dev/null",
       "GIT_NO_LAZY_FETCH":"1", "GIT_ALLOW_PROTOCOL":""}
OPTIONS = ["-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false",
           "-c", "core.attributesFile=/dev/null", "-c", "diff.external=",
           "-c", "maintenance.auto=false", "-c", "gc.auto=0", "-c", "pack.threads=1"]
def git(args, limit=LIMIT, allowed=(0,)):
    process = subprocess.Popen(['/usr/bin/git', *OPTIONS, *args], env=ENV,
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True)
    output = bytearray()
    try:
        with selectors.DefaultSelector() as poll:
            os.set_blocking(process.stdout.fileno(), False)
            poll.register(process.stdout, selectors.EVENT_READ)
            while poll.get_map() or process.poll() is None:
                remaining = deadline - time.monotonic()
                need(remaining > 0, "remote_timeout")
                for key, _ in poll.select(min(remaining, 0.05)):
                    data = os.read(key.fd, 65536)
                    if not data: poll.unregister(key.fileobj)
                    need(len(output) + len(data) <= limit, "remote_size_limit")
                    output.extend(data)
                if not poll.get_map() and process.poll() is None: time.sleep(0.01)
        need(process.returncode in allowed, "git_refused")
        return process.returncode, bytes(output)
    finally:
        try: os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError: pass
        process.wait(timeout=5)
        process.stdout.close()
def text(args): return git(args)[1].decode('utf-8', 'strict').rstrip('\n')
def snapshot(repo, base, fd):
    need(text(['rev-parse', '--show-toplevel']) == repo, "repository_root_mismatch")
    need(text(['rev-parse', '--is-shallow-repository']) == 'false', "incomplete_history")
    # Refuse partial clones before any command that needs commit/tree objects.
    for key in ('extensions.partialclone', r'^remote\..*\.promisor$'):
        code, raw = git(['config', '--get-regexp', key], allowed=(0, 1))
        need(code == 1 and not raw, "incomplete_history")
    fmt = text(['rev-parse', '--show-object-format'])
    need(fmt in ('sha1', 'sha256'), "unsupported_object_format")
    width = 40 if fmt == 'sha1' else 64
    need(re.fullmatch('[0-9a-f]{%d}' % width, base), "invalid_base_commit")
    need(text(['rev-parse', '--verify', '--end-of-options', base + '^{commit}']) == base, "invalid_base_commit")
    head = text(['rev-parse', '--verify', 'HEAD^{commit}'])
    need(re.fullmatch('[0-9a-f]{%d}' % width, head), "invalid_head_commit")
    need(git(['merge-base', '--is-ancestor', base, head], allowed=(0, 1))[0] == 0, "base_not_ancestor")
    count = int(text(['rev-list', '--count', base + '..' + head, '--']))
    need(0 <= count <= 10000, "commit_count_limit")
    raw = git(['diff', '--no-ext-diff', '--no-textconv', '--no-renames', '--name-only', '-z', base, head, '--'])[1]
    need(not raw or raw.endswith(b'\0'), "invalid_path_list")
    paths = [p.decode('utf-8', 'strict') for p in raw[:-1].split(b'\0')] if raw else []
    need(len(paths) <= 4096, "changed_path_limit")
    info = os.fstat(fd)
    return {"base_commit":base, "head_commit":head, "object_format":fmt, "commit_count":count,
            "net_changed_paths":paths, "repository_identity":[info.st_dev, info.st_ino]}
try:
    need(os.geteuid() != 0 and os.getuid() == os.geteuid(), "nonroot_user_required")
    request = json.loads(sys.argv[1])
    need(request['mode'] in ('preview', 'collect'), "invalid_operation")
    deadline = time.monotonic() + request['timeout']
    repo, base = request['repo'], request['base_commit']
    fd = directory(repo)
    try:
        os.fchdir(fd)
        observed = snapshot(repo, base, fd)
        bundle = b''
        if request['mode'] == 'collect':
            observed_bytes = (json.dumps(observed, sort_keys=True, ensure_ascii=True, indent=2) + '\n').encode()
            need(hashlib.sha256(observed_bytes).hexdigest() == request['snapshot_sha256'], "reviewed_snapshot_changed")
            if observed['commit_count']:
                # HEAD must be a named ref for git bundle. The collector checks
                # the advertised OID as well as before/after HEAD snapshots.
                bundle = git(['bundle', 'create', '--version=3', '-', 'HEAD', '^' + base], MAX_BUNDLE)[1]
        need(snapshot(repo, base, fd) == observed, "repository_changed_during_read")
        fresh = directory(repo)
        try: need(os.path.samestat(os.fstat(fd), os.fstat(fresh)), "repository_replaced")
        finally: os.close(fresh)
        report = {"schema":"acfs.swarm-fleet-collection.v1", "snapshot":observed,
                  "bundle_bytes":len(bundle), "bundle_sha256":hashlib.sha256(bundle).hexdigest()}
    finally: os.close(fd)
    header = json.dumps(report, sort_keys=True, ensure_ascii=True, separators=(',', ':')).encode()
    need(len(header) <= LIMIT, "remote_size_limit")
    sys.stdout.buffer.write(header + b'\n' + bundle)
except (Refused, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
    # No paths, source, commit messages or Git stderr cross the failure boundary.
    sys.stderr.write('Fleet Git collection refused; inspect the repository and reviewed range locally.\n')
    sys.exit(2)
'''
POLICY = digest(REMOTE.encode())


def oid(value):
    return fleet.matches(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", value)


def selected_hosts(spec, launch, history):
    require(type(spec) is dict and set(spec) == {"schema", "hosts"}
            and spec["schema"] == SPEC_SCHEMA and type(spec["hosts"]) is list
            and 1 <= len(spec["hosts"]) <= 16, "invalid_collection_selection")
    bases = {}
    for item in spec["hosts"]:
        require(type(item) is dict and set(item) == {"id", "base_commit"}
                and fleet.matches(r"[a-z][a-z0-9_-]{0,63}", item["id"])
                and item["id"] not in bases and oid(item["base_commit"]), "invalid_or_duplicate_collection_host")
        bases[item["id"]] = item["base_commit"]
    selected = []
    for host, (attempted, targets) in zip(launch["spec"]["hosts"], history):
        if host["id"] in bases:
            require(attempted and targets is not None, "selected_launch_not_confirmed")
            selected.append((host, bases.pop(host["id"])))
    require(not bases, "unknown_collection_host")
    return selected


def validate_snapshot(value, base):
    fields = {"base_commit", "head_commit", "object_format", "commit_count", "net_changed_paths", "repository_identity"}
    require(type(value) is dict and set(value) == fields and value["base_commit"] == base
            and oid(base) and oid(value["head_commit"]), "invalid_git_snapshot")
    fmt = value["object_format"]
    require(fmt in ("sha1", "sha256") and len(base) == len(value["head_commit"]) == (40 if fmt == "sha1" else 64),
            "invalid_git_object_format")
    count, paths, identity = value["commit_count"], value["net_changed_paths"], value["repository_identity"]
    require(type(count) is int and 0 <= count <= 10000 and (count == 0) == (base == value["head_commit"]),
            "invalid_commit_count")
    require(type(paths) is list and len(paths) <= 4096 and all(type(p) is str and 0 < len(p) <= 4096
            and "\x00" not in p and not p.startswith("/")
            and all(c not in ("", ".", "..") for c in p.split("/")) for p in paths)
            and len(set(paths)) == len(paths) and (count > 0 or not paths), "invalid_git_paths")
    require(type(identity) is list and len(identity) == 2
            and all(type(n) is int and n >= 0 for n in identity), "invalid_repository_identity")
    return value


def validate_bundle(raw, snapshot):
    """Check framing, advertised commit and pack checksum, not Git object semantics."""
    require(0 < len(raw) <= MAX_BUNDLE, "bundle_size_limit")
    header, separator, pack = raw.partition(b"\n\n")
    require(separator and len(header) <= fleet.LIMIT and raw.startswith(b"# v3 git bundle\n"), "invalid_bundle_header")
    lines = header.split(b"\n")
    fmt, width = snapshot["object_format"], len(snapshot["head_commit"])
    require(lines[1:2] == [("@object-format=" + fmt).encode()], "bundle_object_format_mismatch")
    refs, prerequisites = [], set()
    for line in lines[2:]:
        if line.startswith(b"-"):
            commit = line[1:].split(b" ", 1)[0]
            require(len(commit) == width and all(c in b"0123456789abcdef" for c in commit)
                    and commit not in prerequisites, "invalid_bundle_prerequisite")
            prerequisites.add(commit)
        else:
            refs.append(line)
    require(refs == [(snapshot["head_commit"] + " HEAD").encode()] and prerequisites,
            "bundle_head_or_prerequisites_mismatch")
    # Merge ranges can have several prerequisite boundary commits, not just base.
    size = width // 2
    require(len(pack) > 12 + size and pack[:4] == b"PACK" and int.from_bytes(pack[4:8], "big") in (2, 3)
            and int.from_bytes(pack[8:12], "big") > 0, "invalid_bundle_pack")
    require(hashlib.new(fmt, pack[:-size]).digest() == pack[-size:], "bundle_pack_checksum_mismatch")


def remote_command(host, base, mode, snapshot, timeout):
    require(mode in ("preview", "collect") and oid(base), "invalid_collection_operation")
    request = {"repo": host["request"]["repo"], "base_commit": base, "mode": mode,
               "snapshot_sha256": digest(encoded(snapshot)) if snapshot is not None else None, "timeout": timeout}
    # Program and JSON are separate literal arguments, never interpolated code.
    return "exec python3 -I -c " + shlex.quote(REMOTE) + " " + shlex.quote(encoded(request).decode())


def transport(known, identity, timeout, *, runner=fleet.capture, ssh="/usr/bin/ssh"):
    def invoke(host, base, mode, snapshot=None):
        command = remote_command(host, base, mode, snapshot, timeout)
        def collect_runner(argv, deadline, env):
            return runner([*argv[:-1], command], deadline, env, limit=MAX_BUNDLE + fleet.LIMIT)
        with fleet.transport(known, identity, timeout, runner=collect_runner, ssh=ssh) as call:
            return call(host, "reconcile")
    return invoke


def observe(host, base, mode, invoke, expected=None):
    code, raw = invoke(host, base, mode, expected)
    require(type(code) is int and code == 0 and type(raw) is bytes, "remote_collection_refused")
    require(len(raw) <= MAX_BUNDLE + fleet.LIMIT, "collection_output_limit")
    header, separator, bundle = raw.partition(b"\n")
    require(separator, "invalid_collection_response")
    value = decode(header)
    require(type(value) is dict and set(value) == {"schema", "snapshot", "bundle_bytes", "bundle_sha256"}
            and value["schema"] == SCHEMA, "invalid_collection_response")
    snapshot = validate_snapshot(value["snapshot"], base)
    require(type(value["bundle_bytes"]) is int and value["bundle_bytes"] == len(bundle)
            and value["bundle_sha256"] == digest(bundle), "bundle_transfer_mismatch")
    if mode == "preview":
        require(not bundle, "preview_returned_bundle")
    else:
        require(encoded(snapshot) == encoded(expected), "reviewed_snapshot_changed")
        if snapshot["commit_count"]:
            validate_bundle(bundle, snapshot)
        else:
            require(not bundle, "unchanged_repository_returned_bundle")
    return snapshot, bundle


def lock(fd):
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise fleet.Refused("fleet_operation_in_progress") from None


def read_bundle(fd, name):
    handle = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    with os.fdopen(handle, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and info.st_uid == os.geteuid()
                and not info.st_mode & 0o077, "unsafe_bundle_file")
        raw = stream.read(MAX_BUNDLE + 1)
        require(len(raw) <= MAX_BUNDLE, "bundle_size_limit")
        return raw


def publish_bundle(fd, name, raw):
    handle = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
    with os.fdopen(handle, "wb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    os.fsync(fd)


def validate_plan(plan):
    require(type(plan) is dict and set(plan) == {"schema", "policy", "launch_plan_sha256", "launch_evidence_sha256",
            "known_hosts_sha256", "identity_sha256", "output_directory", "output_parent_identity", "timeout_seconds", "hosts"}
            and plan["schema"] == SCHEMA and plan["policy"] == POLICY, "invalid_collection_plan")
    for name in ("launch_plan_sha256", "launch_evidence_sha256", "known_hosts_sha256", "identity_sha256"):
        require(fleet.matches(r"[0-9a-f]{64}", plan[name]), "invalid_collection_plan_digest")
    fleet.absolute_path(plan["output_directory"])
    parent = plan["output_parent_identity"]
    require(type(parent) is list and len(parent) == 2 and all(type(n) is int and n >= 0 for n in parent),
            "invalid_output_parent_identity")
    require(type(plan["timeout_seconds"]) is int and 1 <= plan["timeout_seconds"] <= 600, "invalid_timeout")
    require(type(plan["hosts"]) is list and 1 <= len(plan["hosts"]) <= 16, "invalid_collection_hosts")
    ids = set()
    for entry in plan["hosts"]:
        require(type(entry) is dict and set(entry) == {"id", "snapshot"}
                and fleet.matches(r"[a-z][a-z0-9_-]{0,63}", entry["id"]) and entry["id"] not in ids,
                "invalid_collection_host")
        ids.add(entry["id"])
        require(type(entry["snapshot"]) is dict, "invalid_git_snapshot")
        validate_snapshot(entry["snapshot"], entry["snapshot"].get("base_commit"))


def verify_at(fd):
    intent = decode(fleet.read_at(fd, "intent.json"))
    require(type(intent) is dict and set(intent) == {"schema", "plan"} and intent["schema"] == SCHEMA,
            "invalid_collection_intent")
    plan = intent["plan"]
    validate_plan(plan)
    manifest = decode(fleet.read_at(fd, "manifest.json"))
    require(type(manifest) is dict and set(manifest) == {"schema", "plan_sha256", "artifacts"}
            and manifest["schema"] == SCHEMA and manifest["plan_sha256"] == digest(encoded(plan))
            and type(manifest["artifacts"]) is list and len(manifest["artifacts"]) == len(plan["hosts"]),
            "invalid_collection_manifest")
    names = {"intent.json", "manifest.json"}
    for entry, artifact in zip(plan["hosts"], manifest["artifacts"]):
        require(type(artifact) is dict and set(artifact) == {"id", "file", "bytes", "sha256"}
                and artifact["id"] == entry["id"] and type(artifact["bytes"]) is int, "invalid_collection_artifact")
        expected = entry["id"] + ".bundle" if entry["snapshot"]["commit_count"] else None
        require(artifact["file"] == expected, "unexpected_collection_filename")
        raw = read_bundle(fd, expected) if expected else b""
        require(artifact["bytes"] == len(raw) and artifact["sha256"] == digest(raw), "artifact_integrity_mismatch")
        if expected:
            names.add(expected)
            validate_bundle(raw, entry["snapshot"])
    require(set(os.listdir(fd)) == names, "unexpected_collection_member")
    return {"schema": SCHEMA, "status": "verified", "plan_sha256": manifest["plan_sha256"],
            "hosts": plan["hosts"], "artifacts": manifest["artifacts"], "task_completion_verified": False}


def verify(path):
    with fleet.directory_fd(path, private=True) as fd:
        lock(fd)
        report = verify_at(fd)
        with fleet.directory_fd(path, private=True) as fresh:
            require(os.path.samestat(os.fstat(fd), os.fstat(fresh)), "collection_directory_changed")
        return report


def execute(launch_path, selection, known, identity, output_dir, timeout, approval, invoke):
    require(type(timeout) is int and 1 <= timeout <= 600, "invalid_timeout")
    require(approval is None or fleet.matches(r"[0-9a-f]{64}", approval), "invalid_collection_approval")
    launch_path, output_dir = (Path(os.path.abspath(p)) for p in (launch_path, output_dir))
    require(launch_path != output_dir and launch_path not in output_dir.parents, "output_inside_launch_journal")
    fleet.state_preflight({"state_directory": str(output_dir)})
    with fleet.directory_fd(output_dir.parent) as parent:
        info = os.fstat(parent)
        output_parent = [info.st_dev, info.st_ino]
    with fleet.directory_fd(launch_path, private=True) as source:
        lock(source)
        intent = decode(fleet.read_at(source, "intent.json"))
        require(type(intent) is dict and set(intent) == {"schema", "plan"} and intent["schema"] == fleet.STATE_SCHEMA,
                "invalid_launch_intent")
        launch = intent["plan"]
        fleet.validate_plan(launch)
        require(launch["state_directory"] == str(launch_path) and launch["known_hosts_sha256"] == digest(known)
                and launch["identity_sha256"] == digest(identity), "launch_context_mismatch")
        history, records = fleet.read_history(source, launch)
        def guard():
            fleet.state_unchanged(source, launch, records)
        selected = selected_hosts(selection, launch, history)
        entries, errors = [], []
        for host, base in selected:
            guard()
            try:
                snapshot, _ = observe(host, base, "preview", invoke)
                entries.append({"id": host["id"], "snapshot": snapshot})
            except (fleet.Refused, OSError, subprocess.SubprocessError) as exc:
                errors.append({"id": host["id"], "code": str(exc) if isinstance(exc, fleet.Refused) else "remote_unavailable"})
            guard()
        report = {"schema": SCHEMA, "status": "blocked", "remote_read_only": True, "starts_agents": False,
                  "sends_prompts": False, "worktree_included": False, "task_completion_verified": False}
        if errors:
            return {**report, "errors": errors}, 1
        plan = {"schema": SCHEMA, "policy": POLICY, "launch_plan_sha256": digest(encoded(launch)),
                "launch_evidence_sha256": digest(encoded({k: digest(v) if v is not None else None for k, v in records.items()})),
                "known_hosts_sha256": digest(known), "identity_sha256": digest(identity),
                "output_directory": str(output_dir), "output_parent_identity": output_parent,
                "timeout_seconds": timeout, "hosts": entries}
        validate_plan(plan)
        require(len(encoded(plan)) <= fleet.LIMIT, "collection_plan_size_limit")
        report.update(status="preview", plan=plan, plan_sha256=digest(encoded(plan)))
        if approval is None:
            return report, 0
        require(approval == report["plan_sha256"], "collection_approval_mismatch")
        guard()
        with fleet.directory_fd(output_dir.parent) as parent:
            info = os.fstat(parent)
            require([info.st_dev, info.st_ino] == output_parent, "output_parent_changed")
            os.mkdir(output_dir.name, 0o700, dir_fd=parent)
            os.fsync(parent)
        with fleet.directory_fd(output_dir, private=True) as dest:
            lock(dest)
            fleet.publish(dest, "intent.json", {"schema": SCHEMA, "plan": plan})
            artifacts = []
            for (host, base), entry in zip(selected, entries):
                guard()
                try:
                    _, bundle = observe(host, base, "collect", invoke, entry["snapshot"])
                except (fleet.Refused, OSError, subprocess.SubprocessError) as exc:
                    report.update(status="partial", artifacts=artifacts,
                                  error={"id": host["id"], "code": str(exc) if isinstance(exc, fleet.Refused) else "remote_unavailable"})
                    return report, 1
                guard()
                with fleet.directory_fd(output_dir, private=True) as fresh:
                    require(os.path.samestat(os.fstat(dest), os.fstat(fresh)), "collection_directory_changed")
                filename = host["id"] + ".bundle" if bundle else None
                if filename:
                    publish_bundle(dest, filename, bundle)
                artifacts.append({"id": host["id"], "file": filename, "bytes": len(bundle), "sha256": digest(bundle)})
            guard()
            fleet.publish(dest, "manifest.json", {"schema": SCHEMA, "plan_sha256": report["plan_sha256"], "artifacts": artifacts})
            verify_at(dest)
            report.update(status="collected", artifacts=artifacts)
            return report, 0


class LocalGit:
    """Bounded local plumbing, with no inherited Git environment or project hooks."""

    def __init__(self, repository, timeout):
        self.repository = repository
        self.deadline = time.monotonic() + timeout
        self.env = {"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C", "HOME": "/nonexistent",
                    "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
                    "GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0",
                    "GIT_NO_REPLACE_OBJECTS": "1", "GIT_GRAFT_FILE": "/dev/null",
                    "GIT_NO_LAZY_FETCH": "1", "GIT_ALLOW_PROTOCOL": ""}

    def run(self, args, data=b"", allowed=(0,)):
        require(time.monotonic() < self.deadline, "import_git_deadline")
        options = ["core.hooksPath=/dev/null", "core.fsmonitor=false", "core.attributesFile=/dev/null",
                   "diff.external=", "maintenance.auto=false", "gc.auto=0", "pack.threads=1",
                   "core.logAllRefUpdates=false"]
        argv = ["/usr/bin/git", "--no-pager", "-C", str(self.repository)]
        for option in options:
            argv += ["-c", option]
        # Anonymous input avoids shell interpolation, pipe deadlocks, and a
        # second pathname read of a bundle after its integrity was checked.
        with tempfile.TemporaryFile() as source:
            source.write(data)
            source.seek(0)
            process = subprocess.Popen([*argv, *args], env=self.env, stdin=source,
                                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                       start_new_session=True)
            output = bytearray()
            try:
                with selectors.DefaultSelector() as poll:
                    os.set_blocking(process.stdout.fileno(), False)
                    poll.register(process.stdout, selectors.EVENT_READ)
                    while poll.get_map() or process.poll() is None:
                        remaining = self.deadline - time.monotonic()
                        require(remaining > 0, "import_git_deadline")
                        for key, _ in poll.select(min(remaining, 0.05)):
                            chunk = os.read(key.fd, 65536)
                            if not chunk:
                                poll.unregister(key.fileobj)
                            require(len(output) + len(chunk) <= fleet.LIMIT, "import_git_output_limit")
                            output.extend(chunk)
                        if not poll.get_map() and process.poll() is None:
                            time.sleep(0.01)
                require(process.returncode in allowed, "local_git_refused")
                return process.returncode, bytes(output)
            finally:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=5)
                process.stdout.close()

    def text(self, args):
        return self.run(args)[1].decode("utf-8", "strict").rstrip("\n")

    def verify_bundle(self, raw):
        # Give Git a seekable snapshot with independent stdin. Some Git versions
        # feed the remainder of a stdin bundle into their prerequisite walk.
        with tempfile.TemporaryFile() as snapshot:
            snapshot.write(raw)
            snapshot.flush()
            self.run(["bundle", "verify", f"/proc/{os.getpid()}/fd/{snapshot.fileno()}"])


@contextmanager
def import_source(path):
    """Keep the verified artifact bytes and recheck the complete collection."""
    with fleet.directory_fd(path, private=True) as fd:
        lock(fd)
        metadata = {name: fleet.read_at(fd, name) for name in ("intent.json", "manifest.json")}
        verified = verify_at(fd)
        bundles = {}
        for artifact in verified["artifacts"]:
            if artifact["file"] is not None:
                raw = read_bundle(fd, artifact["file"])
                require(len(raw) == artifact["bytes"] and digest(raw) == artifact["sha256"],
                        "collection_changed_during_import")
                bundles[artifact["file"]] = raw
        def guard():
            with fleet.directory_fd(path, private=True) as current:
                require(os.path.samestat(os.fstat(fd), os.fstat(current)), "collection_directory_changed")
            require(set(os.listdir(fd)) == set(metadata) | set(bundles), "collection_changed_during_import")
            for name, raw in metadata.items():
                require(fleet.read_at(fd, name) == raw, "collection_changed_during_import")
            for name, raw in bundles.items():
                require(read_bundle(fd, name) == raw, "collection_changed_during_import")
        guard()
        yield verified, bundles, digest(encoded({k: digest(v) for k, v in metadata.items()})), guard
        guard()


def destination_state(git):
    require(git.text(["rev-parse", "--show-toplevel"]) == str(git.repository), "destination_root_mismatch")
    require(git.text(["rev-parse", "--is-shallow-repository"]) == "false", "destination_history_incomplete")
    # No network-on-demand objects or configured relaxations of object checks.
    for key in ("extensions.partialclone", r"^remote\..*\.promisor$", r"^fsck\."):
        code, raw = git.run(["config", "--get-regexp", key], allowed=(0, 1))
        require(code == 1 and not raw, "destination_configuration_not_supported")
    paths = {"repository": str(git.repository),
             "git_directory": git.text(["rev-parse", "--absolute-git-dir"]),
             "common_directory": git.text(["rev-parse", "--path-format=absolute", "--git-common-dir"]),
             "object_directory": git.text(["rev-parse", "--path-format=absolute", "--git-path", "objects"])}
    result = {}
    for name, path in paths.items():
        fleet.absolute_path(path)
        with fleet.directory_fd(path) as fd:
            info = os.fstat(fd)
            result[name] = {"path": path, "identity": [info.st_dev, info.st_ino]}
    require(not os.path.lexists(Path(paths["object_directory"]) / "info/alternates"),
            "borrowed_destination_objects_not_supported")
    result["object_format"] = git.text(["rev-parse", "--show-object-format"])
    require(result["object_format"] in ("sha1", "sha256"), "unsupported_destination_object_format")
    return result


def require_new_ref(git, ref):
    # A dangling symbolic ref is occupied too. Never follow it to a user ref.
    code, _ = git.run(["symbolic-ref", "--quiet", ref], allowed=(0, 1))
    require(code == 1, "review_ref_already_exists")
    code, _ = git.run(["show-ref", "--verify", "--quiet", ref], allowed=(0, 1))
    require(code == 1, "review_ref_already_exists")
    _, head = git.run(["symbolic-ref", "--quiet", "HEAD"], allowed=(0, 1))
    require(head.rstrip(b"\n") != ref.encode(), "review_ref_is_current_head")


def check_imported_history(git, entry):
    snap = entry["snapshot"]
    base, head = snap["base_commit"], snap["head_commit"]
    require(git.text(["cat-file", "-t", head]) == "commit", "imported_head_not_commit")
    git.run(["merge-base", "--is-ancestor", base, head])
    require(git.text(["rev-list", "--count", base + ".." + head, "--"]) == str(snap["commit_count"]),
            "imported_commit_count_mismatch")
    raw = git.run(["diff", "--no-ext-diff", "--no-textconv", "--no-renames", "--name-only", "-z",
                   base, head, "--"])[1]
    expected = b"".join(p.encode() + b"\0" for p in snap["net_changed_paths"])
    require(raw == expected, "imported_changed_paths_mismatch")
    # Walk all reachable objects, not just commits/trees appearing in a net diff.
    git.run(["rev-list", "--objects", "--quiet", "--missing=error", head, "--"])


def import_collection(path, repository, name, hosts, timeout, approval=None):
    global IMPORT_STARTED
    IMPORT_STARTED = False
    require(sys.platform == "linux" and os.geteuid() != 0 and os.getuid() == os.geteuid()
            and not os.environ.get("SUDO_USER"), "import_as_repository_owner_without_sudo")
    require(type(timeout) is int and 1 <= timeout <= 600, "invalid_import_timeout")
    require(fleet.matches(r"[a-z][a-z0-9_-]{0,63}", name), "invalid_review_name")
    require(approval is None or fleet.matches(r"[0-9a-f]{64}", approval), "invalid_import_approval")
    require(type(hosts) is list and len(set(hosts)) == len(hosts)
            and all(fleet.matches(r"[a-z][a-z0-9_-]{0,63}", h) for h in hosts), "invalid_import_hosts")
    path, repository = (Path(fleet.absolute_path(str(Path(os.path.abspath(p))))) for p in (path, repository))
    with import_source(path) as (source, bundles, evidence, guard), fleet.directory_fd(repository):
        git = LocalGit(repository, timeout)
        destination = destination_state(git)
        entries = [e for e in source["hosts"] if not hosts or e["id"] in hosts]
        require(entries and (not hosts or len(entries) == len(hosts)), "unknown_import_host")
        artifacts = {a["id"]: a for a in source["artifacts"]}
        refs = [{"id": e["id"], "ref": "refs/acfs/fleet/" + name + "/" + e["id"],
                 "head_commit": e["snapshot"]["head_commit"]}
                for e in entries if e["snapshot"]["commit_count"]]
        plan = {"schema": IMPORT_SCHEMA, "policy": "new-review-refs-strict-git-v1",
                "collection_directory": str(path), "collection_evidence_sha256": evidence,
                "collection_plan_sha256": source["plan_sha256"], "destination": destination,
                "name": name, "hosts": entries, "artifacts": [artifacts[e["id"]] for e in entries],
                "refs": refs, "timeout_seconds": timeout}
        plan_sha = digest(encoded(plan))
        require(approval is None or approval == plan_sha, "import_approval_mismatch")
        # Lock the shared Git directory, so linked worktrees cooperate too.
        with fleet.directory_fd(destination["common_directory"]["path"]) as dest:
            lock(dest)
            require(destination_state(git) == destination, "destination_changed")
            for row in refs:
                require_new_ref(git, row["ref"])
            for entry in entries:
                snap, artifact = entry["snapshot"], artifacts[entry["id"]]
                require(snap["object_format"] == destination["object_format"], "import_object_format_mismatch")
                require(git.text(["cat-file", "-t", snap["base_commit"]]) == "commit", "destination_base_missing")
                if artifact["file"]:
                    # Verify every bundle prerequisite before writing any pack.
                    git.verify_bundle(bundles[artifact["file"]])
            guard()
            report = {"schema": IMPORT_SCHEMA, "status": "preview", "plan": plan, "plan_sha256": plan_sha,
                      "network_access": False, "changes_checkout": False, "runs_project_code": False,
                      "task_completion_verified": False, "import_started": False}
            if approval is None:
                return report
            for entry in entries:
                guard()
                require(destination_state(git) == destination, "destination_changed")
                artifact = artifacts[entry["id"]]
                if artifact["file"]:
                    IMPORT_STARTED = report["import_started"] = True
                    pack = bundles[artifact["file"]].partition(b"\n\n")[2]
                    git.run(["index-pack", "--stdin", "--fix-thin", "--strict", "--threads=1",
                             "--max-input-size=" + str(MAX_BUNDLE), "--keep=acfs-fleet-import:" + plan_sha], pack)
                check_imported_history(git, entry)
            guard()
            require(destination_state(git) == destination, "destination_changed")
            for row in refs:
                require_new_ref(git, row["ref"])
            if refs:
                # No existing refs are updated, and symbolic refs cannot redirect
                # a creation. The transaction prepares the whole set together.
                transaction = "start\n" + "".join("create " + r["ref"] + " " + r["head_commit"] + "\n" for r in refs)
                git.run(["update-ref", "--no-deref", "--stdin"], (transaction + "prepare\ncommit\n").encode())
            report["status"] = "imported" if refs else "noop"
            return report


def import_main(args):
    parser = argparse.ArgumentParser(description="Import an offline collection into new review refs; never checkout or merge",
                                     allow_abbrev=False)
    parser.add_argument("--import", dest="collection", required=True)
    parser.add_argument("--repository", required=True, help="Trusted existing local worktree containing the base history")
    parser.add_argument("--name", required=True, help="New review namespace: refs/acfs/fleet/NAME/HOST")
    parser.add_argument("--host", action="append", default=[], help="Select host IDs; default all, original order retained")
    parser.add_argument("--timeout", type=int, default=90, help="Combined Git subprocess budget, 1..600 seconds")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--accept-plan")
    options = parser.parse_args(args)
    require(options.apply == (options.accept_plan is not None), "import_requires_exact_approval")
    report = import_collection(options.collection, options.repository, options.name, options.host,
                               options.timeout, options.accept_plan)
    print(encoded(report).decode(), end="")
    return 0


def main(arguments=None):
    args = list(sys.argv[1:] if arguments is None else arguments)
    if "--import" in args:
        return import_main(args)
    if args[:1] == ["--verify"]:
        require(len(args) == 2, "verify_requires_only_collection_directory")
        print(encoded(verify(args[1])).decode(), end="")
        return 0
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False,
                                     epilog="Offline review import: --import COLLECTION --repository DIR --name NAME [--apply --accept-plan SHA256]")
    parser.add_argument("--launch-state", required=True)
    parser.add_argument("--bases", required=True, help="Private host-ID to full base-commit selection")
    parser.add_argument("--known-hosts", required=True)
    parser.add_argument("--identity-file", required=True)
    parser.add_argument("--output-dir", required=True, help="New private artifact directory; never an existing project")
    parser.add_argument("--timeout", type=int, default=90, help="Per-host operation deadline, 1..600 seconds")
    parser.add_argument("--collect", action="store_true", help="Save reviewed committed changes; no local import or merge")
    parser.add_argument("--accept-plan", help="Exact collection preview digest")
    options = parser.parse_args(args)
    require(options.collect == (options.accept_plan is not None), "collection_requires_exact_approval")
    known = fleet.read_input(options.known_hosts, private=False)
    identity = fleet.read_input(options.identity_file)
    result, code = execute(options.launch_state, decode(fleet.read_input(options.bases)), known, identity,
                           options.output_dir, options.timeout, options.accept_plan,
                           transport(known, identity, options.timeout))
    print(encoded(result).decode(), end="")
    return code


def cli():
    def stop(signum, _frame):
        raise fleet.Interrupted(signum)
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, stop)
    try:
        return main()
    except (fleet.Refused, OSError, ValueError, subprocess.SubprocessError, fleet.Interrupted) as exc:
        print(encoded({"schema": SCHEMA, "status": "error", "remote_read_only": True,
                       "import_started": IMPORT_STARTED,
                       "code": str(exc) if isinstance(exc, fleet.Refused) else "collection_io_or_process_failure"}).decode(), end="")
        return 128 + exc.signum if isinstance(exc, fleet.Interrupted) else 2


if __name__ == "__main__":
    sys.exit(cli())
