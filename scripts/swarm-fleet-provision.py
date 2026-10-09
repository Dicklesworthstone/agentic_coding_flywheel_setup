#!/usr/bin/env python3
"""Seed new fleet repositories from an explicitly reviewed local commit.

Preview performs read-only SSH probes. --provision requires its exact digest.
Existing destinations are never adopted or overwritten. No agents are started,
no project code runs, and no credentials or remote configuration are cloned.
"""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import selectors
import shlex
import signal
import stat
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
SCHEMA = "acfs.swarm-fleet-provision.v1"
LIMIT = 1024 * 1024
PACK_LIMIT = 16 * LIMIT
TREE_LIMIT = 256 * LIMIT
WRITES_ATTEMPTED = False
ENV = {"PATH": "/usr/bin:/bin", "HOME": "/nonexistent", "LANG": "C", "LC_ALL": "C",
       "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0",
       "GIT_OPTIONAL_LOCKS": "0", "GIT_NO_REPLACE_OBJECTS": "1", "GIT_GRAFT_FILE": "/dev/null",
       "GIT_NO_LAZY_FETCH": "1", "GIT_ALLOW_PROTOCOL": "", "GIT_ATTR_NOSYSTEM": "1"}


class Refused(Exception):
    """Fixed error codes only; project output and SSH diagnostics stay private."""


def require(condition, code):
    if not condition:
        raise Refused(code)


def encoded(value):
    return (json.dumps(value, ensure_ascii=True, sort_keys=True, indent=2, allow_nan=False) + "\n").encode()


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def oid(value):
    return type(value) is str and re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", value) is not None


def sha256(value):
    return type(value) is str and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def decode(raw):
    require(len(raw) <= LIMIT, "json_size_limit")
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "duplicate_json_field")
            result[key] = value
        return result
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=pairs,
                           parse_constant=lambda _: (_ for _ in ()).throw(Refused("invalid_json_number")))
        pending, count = [(value, 0)], 0
        while pending:
            item, depth = pending.pop()
            count += 1
            require(depth <= 32 and count <= 50000, "json_complexity_limit")
            if type(item) is dict:
                pending.extend((v, depth + 1) for v in item.values())
                pending.extend((k, depth + 1) for k in item)
            elif type(item) is list:
                pending.extend((v, depth + 1) for v in item)
            elif type(item) is str:
                item.encode("utf-8", "strict")
        return value
    except (ValueError, UnicodeError, RecursionError):
        raise Refused("invalid_json") from None


def absolute(value):
    require(type(value) is str and value.startswith("/") and value != "/" and len(value) <= 4096
            and not re.search(r"[\x00-\x1f\x7f]", value)
            and all(p not in ("", ".", "..") for p in value.split("/")[1:]), "invalid_absolute_path")
    return Path(value)


@contextmanager
def directory(path):
    path = absolute(str(path))
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parts[1:]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
            info = os.fstat(fd)
            sticky = info.st_uid == 0 and info.st_mode & stat.S_ISVTX
            require(info.st_uid in (0, os.geteuid()) and (not info.st_mode & 0o022 or sticky), "unsafe_directory")
        info = os.fstat(fd)
        require(info.st_uid == os.geteuid() and not info.st_mode & 0o022, "directory_ownership_or_permissions")
        yield fd
    finally:
        os.close(fd)


def identity(fd):
    info = os.fstat(fd)
    return [info.st_dev, info.st_ino]


def read_at(fd, name):
    handle = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    with os.fdopen(handle, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_uid == os.geteuid() and info.st_nlink == 1
                and not info.st_mode & 0o077, "unsafe_receipt")
        raw = stream.read(LIMIT + 1)
        require(len(raw) <= LIMIT, "receipt_size_limit")
        return raw


def publish(fd, name, value):
    raw = encoded(value)
    require(len(raw) <= LIMIT, "receipt_size_limit")
    handle = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
    with os.fdopen(handle, "wb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    os.fsync(fd)


def capture(argv, deadline, data=b"", env=None, limit=LIMIT):
    """Bound input and both outputs without a pipe-writer deadlock."""
    require(type(data) is bytes and len(data) <= PACK_LIMIT + LIMIT, "input_size_limit")
    require(time.monotonic() < deadline, "operation_timed_out")
    with tempfile.TemporaryFile() as source:
        source.write(data)
        source.seek(0)
        process = subprocess.Popen(argv, env=ENV if env is None else env, stdin=source,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        result, total = bytearray(), 0
        try:
            with selectors.DefaultSelector() as poll:
                for stream in (process.stdout, process.stderr):
                    os.set_blocking(stream.fileno(), False)
                    poll.register(stream, selectors.EVENT_READ)
                while poll.get_map() or process.poll() is None:
                    remaining = deadline - time.monotonic()
                    require(remaining > 0, "operation_timed_out")
                    for key, _ in poll.select(min(remaining, 0.05)):
                        chunk = os.read(key.fd, 65536)
                        if not chunk:
                            poll.unregister(key.fileobj)
                        total += len(chunk)
                        require(total <= limit, "process_output_limit")
                        if key.fileobj is process.stdout:
                            result.extend(chunk)
                    if not poll.get_map() and process.poll() is None:
                        time.sleep(0.01)
            require(process.returncode == 0, "process_refused")
            return bytes(result)
        finally:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)
            process.stdout.close()
            process.stderr.close()


def git(repo, args, deadline, data=b"", limit=LIMIT):
    options = ["core.hooksPath=/dev/null", "core.fsmonitor=false", "core.attributesFile=/dev/null",
               "diff.external=", "maintenance.auto=false", "gc.auto=0", "pack.threads=1",
               "core.logAllRefUpdates=false", "core.fsync=all"]
    argv = ["/usr/bin/git", "--no-pager", "-C", str(repo)]
    for option in options:
        argv += ["-c", option]
    return capture([*argv, *args], deadline, data, limit=limit)


def snapshot(repo, commit, deadline):
    """Read complete history and tracked-tree metadata, never the dirty index."""
    require(oid(commit), "full_commit_required")
    require(git(repo, ["rev-parse", "--show-toplevel"], deadline).rstrip(b"\n") == os.fsencode(repo), "repository_root_mismatch")
    require(git(repo, ["rev-parse", "--is-shallow-repository"], deadline).strip() == b"false", "shallow_repository_refused")
    fmt = git(repo, ["rev-parse", "--show-object-format"], deadline).strip().decode()
    require(fmt in ("sha1", "sha256") and len(commit) == (40 if fmt == "sha1" else 64), "object_format_mismatch")
    raw = git(repo, ["cat-file", "commit", commit], deadline)
    require(hashlib.new(fmt, b"commit " + str(len(raw)).encode() + b"\0" + raw).hexdigest() == commit,
            "commit_object_mismatch")
    tree = git(repo, ["rev-parse", "--verify", commit + "^{tree}"], deadline).strip().decode()
    count = int(git(repo, ["rev-list", "--count", commit, "--"], deadline))
    require(1 <= count <= 10000, "history_limit")
    raw = git(repo, ["ls-tree", "-r", "-l", "-z", "--full-tree", tree], deadline)
    require(not raw or raw.endswith(b"\0"), "invalid_tree")
    size, files = 0, 0
    for row in raw[:-1].split(b"\0") if raw else []:
        meta, sep, path = row.partition(b"\t")
        fields = meta.split()
        require(sep and len(fields) == 4 and fields[0] in (b"100644", b"100755", b"120000")
                and fields[1] == b"blob" and fields[3].isdigit(), "submodule_or_special_entry_refused")
        require(path and not path.startswith(b"/") and len(path) <= 4096
                and all(p.lower() not in (b"", b".", b"..", b".git") for p in path.split(b"/")), "unsafe_tree_path")
        files += 1
        size += int(fields[3])
        require(int(fields[3]) <= 8 * LIMIT and files <= 10000 and size <= TREE_LIMIT, "tree_size_limit")
    git(repo, ["rev-list", "--objects", "--quiet", "--missing=error", commit, "--"], deadline)
    return {"commit": commit, "tree": tree, "object_format": fmt, "commits": count, "files": files, "tree_bytes": size}


def validate_artifact(value):
    require(type(value) is dict and set(value) == {"commit", "tree", "object_format", "commits", "files", "tree_bytes",
                                                   "pack_bytes", "pack_sha256"}, "invalid_artifact")
    require(value["object_format"] in ("sha1", "sha256") and oid(value["commit"]) and oid(value["tree"])
            and len(value["commit"]) == len(value["tree"]) == (40 if value["object_format"] == "sha1" else 64), "invalid_artifact")
    for name, lower, upper in (("commits", 1, 10000), ("files", 0, 10000), ("tree_bytes", 0, TREE_LIMIT),
                               ("pack_bytes", 1, PACK_LIMIT)):
        require(type(value[name]) is int and lower <= value[name] <= upper, "invalid_artifact")
    require(sha256(value["pack_sha256"]), "invalid_artifact")


def source_artifact(repo, commit, timeout):
    repo = absolute(str(Path(os.path.abspath(repo))))
    deadline = time.monotonic() + timeout
    with directory(repo) as fd:
        keys = git(repo, ["config", "--includes", "--name-only", "--list"], deadline).decode().lower().splitlines()
        require(not any(k == "extensions.partialclone" or re.fullmatch(r"remote\..*\.promisor", k)
                        for k in keys), "partial_repository_refused")
        objects = absolute(os.fsdecode(git(repo, ["rev-parse", "--path-format=absolute", "--git-path", "objects"],
                                          deadline).rstrip(b"\n")))
        with directory(objects):
            require(not os.path.lexists(objects / "info/alternates"), "borrowed_objects_refused")
        common = absolute(os.fsdecode(git(repo, ["rev-parse", "--path-format=absolute", "--git-common-dir"], deadline).rstrip(b"\n")))
        with directory(common) as common_fd:
            source = {"repository": str(repo), "repository_identity": identity(fd), "common_directory": str(common),
                      "common_identity": identity(common_fd)}
        meta = snapshot(repo, commit, deadline)
        pack = git(repo, ["pack-objects", "--stdout", "--revs", "--delta-base-offset"], deadline,
                   (commit + "\n").encode(), limit=PACK_LIMIT)
        meta.update(pack_bytes=len(pack), pack_sha256=sha(pack))
        validate_artifact(meta)
        with directory(repo) as current, directory(common) as current_common:
            require(identity(current) == source["repository_identity"] and identity(current_common) == source["common_identity"],
                    "source_directory_changed")
    return source, meta, pack


def policy():
    return globals().get("RECEIVER_POLICY") or sha(Path(__file__).read_bytes())


def receive_input(deadline):
    if stat.S_ISREG(os.fstat(sys.stdin.fileno()).st_mode):
        raw = sys.stdin.buffer.read(PACK_LIMIT + LIMIT + 1)
        require(len(raw) <= PACK_LIMIT + LIMIT, "input_size_limit")
        header, sep, pack = raw.partition(b"\n")
        require(sep, "invalid_frame")
        return decode(header), pack
    raw = bytearray()
    with selectors.DefaultSelector() as poll:
        poll.register(sys.stdin.buffer, selectors.EVENT_READ)
        while True:
            remaining = deadline - time.monotonic()
            require(remaining > 0, "input_timed_out")
            if not poll.select(min(remaining, 0.05)):
                continue
            chunk = os.read(sys.stdin.fileno(), 65536)
            if not chunk:
                break
            raw.extend(chunk)
            require(len(raw) <= PACK_LIMIT + LIMIT, "input_size_limit")
    header, sep, pack = bytes(raw).partition(b"\n")
    require(sep, "invalid_frame")
    return decode(header), pack


def parent_observation(repo, deadline, absent):
    with directory(repo.parent) as parent:
        if absent:
            try:
                os.stat(repo.name, dir_fd=parent, follow_symlinks=False)
            except FileNotFoundError:
                pass
            else:
                raise Refused("destination_already_exists")
        return {"parent_identity": identity(parent), "uid": os.geteuid(),
                "git_version": git(repo.parent, ["--version"], deadline).strip().decode()}


def receiver(request, pack, deadline):
    global WRITES_ATTEMPTED
    WRITES_ATTEMPTED = False
    require(os.geteuid() != 0 and os.getuid() == os.geteuid(), "nonroot_receiver_required")
    require(type(request) is dict and set(request) == {"schema", "mode", "repo", "artifact", "context", "plan_sha256", "host_id", "policy"}
            and request["schema"] == SCHEMA and request["mode"] in ("preview", "create", "check")
            and request["policy"] == policy() and type(request["host_id"]) is str
            and re.fullmatch(r"[a-z][a-z0-9_-]{0,63}", request["host_id"]), "invalid_receiver_request")
    repo = absolute(request["repo"])
    artifact = request["artifact"]
    validate_artifact(artifact)
    mode = request["mode"]
    context = parent_observation(repo, deadline, absent=mode != "check")
    if mode == "preview":
        require(not pack and request["context"] is None and request["plan_sha256"] is None, "invalid_preview")
        return {"schema": SCHEMA, "status": "available", "context": context}
    require(context == request["context"] and sha256(request["plan_sha256"]), "receiver_context_changed")
    binding = {k: request[k] for k in ("repo", "artifact", "context", "plan_sha256", "host_id", "policy")}
    if mode == "create":
        require(len(pack) == artifact["pack_bytes"] and sha(pack) == artifact["pack_sha256"], "pack_transfer_mismatch")
        with directory(repo.parent) as parent:
            require(identity(parent) == context["parent_identity"], "receiver_parent_changed")
            WRITES_ATTEMPTED = True
            os.mkdir(repo.name, 0o700, dir_fd=parent)
            os.fsync(parent)
        with directory(repo) as target:
            repo_identity = identity(target)
            git(repo, ["init", "--template=", "--initial-branch=main", "--object-format=" + artifact["object_format"]], deadline)
            git(repo, ["index-pack", "--stdin", "--strict", "--threads=1", "--max-input-size=" + str(PACK_LIMIT)], deadline, pack)
            require(snapshot(repo, artifact["commit"], deadline) == {k: v for k, v in artifact.items() if not k.startswith("pack_")},
                    "received_history_mismatch")
            git(repo, ["update-ref", "refs/heads/main", artifact["commit"], "0" * len(artifact["commit"])], deadline)
            git(repo, ["read-tree", artifact["commit"]], deadline)
            # Unlike checkout/reset --force, checkout-index without --force
            # refuses an existing working file. This directory was created here.
            git(repo, ["checkout-index", "--all"], deadline)
            require(not git(repo, ["status", "--porcelain", "--untracked-files=all"], deadline), "checkout_not_clean")
            with directory(repo) as current:
                require(identity(current) == repo_identity, "receiver_directory_changed")
            receipt = {"schema": SCHEMA, "binding": binding, "repository_identity": repo_identity}
            with directory(repo / ".git") as git_dir:
                publish(git_dir, "acfs-provision.json", receipt)
            return {"schema": SCHEMA, "status": "provisioned", "receipt": receipt}
    require(not pack, "check_does_not_accept_pack")
    with directory(repo) as target, directory(repo / ".git") as git_dir:
        raw = read_at(git_dir, "acfs-provision.json")
        receipt = decode(raw)
        require(receipt == {"schema": SCHEMA, "binding": binding, "repository_identity": identity(target)}, "receipt_mismatch")
        require(git(repo, ["rev-parse", "--show-toplevel"], deadline).rstrip(b"\n") == os.fsencode(repo), "repository_root_mismatch")
        require(git(repo, ["symbolic-ref", "HEAD"], deadline).strip() == b"refs/heads/main"
                and git(repo, ["rev-parse", "HEAD"], deadline).strip() == artifact["commit"].encode(), "provisioned_head_changed")
        require(snapshot(repo, artifact["commit"], deadline) == {k: v for k, v in artifact.items() if not k.startswith("pack_")},
                "received_history_mismatch")
        require(not git(repo, ["status", "--porcelain", "--untracked-files=all"], deadline), "checkout_not_clean")
        require(read_at(git_dir, "acfs-provision.json") == raw, "receipt_changed")
        with directory(repo) as current:
            require(identity(current) == identity(target), "receiver_directory_changed")
        return {"schema": SCHEMA, "status": "provisioned", "receipt": receipt}


def load_fleet():
    path = Path(__file__).absolute().with_name("swarm-fleet-launch.py")
    require(path.is_file() and not path.is_symlink(), "trusted_fleet_helper_required")
    spec = importlib.util.spec_from_file_location("acfs_provision_fleet", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def transport(fleet, known, key, timeout, *, ssh="/usr/bin/ssh"):
    source = Path(__file__).read_text()
    command = "exec /usr/bin/python3 -I -c " + shlex.quote("RECEIVER_POLICY=" + repr(policy()) + "\n" + source)
    command += " --receiver " + str(timeout)
    def invoke(host, request, pack=b""):
        data = json.dumps(request, ensure_ascii=True, sort_keys=True, separators=(",", ":")).encode() + b"\n" + pack
        def runner(argv, seconds, env):
            # -n closes stdin in the shared read-only SSH transport. Remove that
            # exact option, not arbitrary arguments; retain all trust settings.
            require(argv[0:5] == [ssh, "-F", "/dev/null", "-T", "-n"], "unexpected_ssh_argv")
            raw = capture([*argv[:4], *argv[5:-1], command], time.monotonic() + seconds, data, env)
            return 0, raw
        with fleet.transport(known, key, timeout, runner=runner, ssh=ssh) as call:
            _, raw = call(host, "reconcile")
        return decode(raw)
    return invoke


def request_for(plan, host, mode, context=None):
    return {"schema": SCHEMA, "mode": mode, "repo": host["request"]["repo"], "artifact": plan["artifact"],
            "context": context, "plan_sha256": None if mode == "preview" else sha(encoded(plan)),
            "host_id": host["id"], "policy": plan["policy"]}


def response_receipt(value, request):
    require(type(value) is dict and set(value) == {"schema", "status", "receipt"}
            and value["schema"] == SCHEMA and value["status"] == "provisioned", "remote_provision_unconfirmed")
    receipt = value["receipt"]
    binding = {k: request[k] for k in ("repo", "artifact", "context", "plan_sha256", "host_id", "policy")}
    require(type(receipt) is dict and set(receipt) == {"schema", "binding", "repository_identity"}
            and receipt["schema"] == SCHEMA and receipt["binding"] == binding
            and type(receipt["repository_identity"]) is list and len(receipt["repository_identity"]) == 2
            and all(type(n) is int and n >= 0 for n in receipt["repository_identity"]), "invalid_remote_receipt")
    return receipt


def execute(fleet, spec, repository, commit, known, key, state, timeout, approval, invoke):
    global WRITES_ATTEMPTED
    WRITES_ATTEMPTED = False
    require(sys.platform == "linux" and os.geteuid() != 0 and os.getuid() == os.geteuid()
            and not os.environ.get("SUDO_USER"), "provision_as_owner_without_sudo")
    require(known and key and type(timeout) is int and 1 <= timeout <= 600, "invalid_trust_or_timeout")
    require(approval is None or sha256(approval), "invalid_approval")
    spec = fleet.validate_spec(spec)
    state = absolute(str(Path(os.path.abspath(state))))
    fleet.state_preflight({"state_directory": str(state)})
    source, artifact, pack = source_artifact(repository, commit, timeout)
    require(Path(source["repository"]) not in (state, *state.parents)
            and Path(source["common_directory"]) not in (state, *state.parents), "state_inside_source_repository")
    with directory(state.parent) as parent:
        parent_id = identity(parent)
    plan = {"schema": SCHEMA, "policy": policy(), "spec": spec, "source": source, "artifact": artifact,
            "known_hosts_sha256": sha(known), "identity_sha256": sha(key), "state_directory": str(state),
            "state_parent_identity": parent_id, "timeout_seconds": timeout, "contexts": {}}
    errors = []
    for host in spec["hosts"]:
        try:
            reply = invoke(host, request_for(plan, host, "preview"))
            require(type(reply) is dict and set(reply) == {"schema", "status", "context"}
                    and reply["schema"] == SCHEMA and reply["status"] == "available", "remote_preflight_refused")
            context = reply["context"]
            require(type(context) is dict and set(context) == {"parent_identity", "uid", "git_version"}
                    and type(context["uid"]) is int and context["uid"] > 0
                    and type(context["parent_identity"]) is list and len(context["parent_identity"]) == 2
                    and all(type(n) is int and n >= 0 for n in context["parent_identity"])
                    and type(context["git_version"]) is str and len(context["git_version"]) <= 128, "invalid_remote_context")
            plan["contexts"][host["id"]] = context
        except (Refused, fleet.Refused, OSError, subprocess.SubprocessError) as exc:
            errors.append({"id": host["id"], "code": str(exc) if isinstance(exc, (Refused, fleet.Refused)) else "remote_io_failure"})
    report = {"schema": SCHEMA, "status": "blocked" if errors else "preview", "starts_agents": False,
              "runs_project_code": False, "writes_attempted": False, "task_completion_verified": False}
    if errors:
        return {**report, "errors": errors}, 1
    require(len(encoded(plan)) <= LIMIT, "plan_size_limit")
    report.update(plan=plan, plan_sha256=sha(encoded(plan)))
    if approval is None:
        return report, 0
    require(approval == report["plan_sha256"], "approval_mismatch")
    with directory(state.parent) as parent:
        require(identity(parent) == parent_id, "state_parent_changed")
        os.mkdir(state.name, 0o700, dir_fd=parent)
        os.fsync(parent)
    with directory(state) as dest:
        fcntl.flock(dest, fcntl.LOCK_EX | fcntl.LOCK_NB)
        intent = {"schema": SCHEMA, "plan": plan}
        publish(dest, "intent.json", intent)
        records = {"intent.json": encoded(intent)}
        def guard():
            with directory(state) as current, directory(state.parent) as parent:
                require(identity(current) == identity(dest) and identity(parent) == parent_id, "state_directory_changed")
            require(set(os.listdir(dest)) == set(records), "state_changed")
            for filename, raw in records.items():
                require(read_at(dest, filename) == raw, "state_changed")
        rows = [{"id": h["id"], "status": "not_attempted"} for h in spec["hosts"]]
        for index, host in enumerate(spec["hosts"]):
            guard()
            request = request_for(plan, host, "create", plan["contexts"][host["id"]])
            attempt = {"schema": SCHEMA, "request": request}
            publish(dest, host["id"] + ".attempt.json", attempt)
            records[host["id"] + ".attempt.json"] = encoded(attempt)
            guard()
            WRITES_ATTEMPTED = report["writes_attempted"] = True
            try:
                receipt = response_receipt(invoke(host, request, pack), request)
            except (Refused, fleet.Refused, OSError, subprocess.SubprocessError) as exc:
                guard()
                rows[index].update(status="unconfirmed", code=str(exc) if isinstance(exc, (Refused, fleet.Refused)) else "remote_io_failure")
                return {**report, "status": "partial", "hosts": rows}, 1
            guard()
            publish(dest, host["id"] + ".result.json", receipt)
            records[host["id"] + ".result.json"] = encoded(receipt)
            guard()
            rows[index]["status"] = "provisioned"
        return {**report, "status": "provisioned", "hosts": rows}, 0


def main(args=None):
    args = list(sys.argv[1:] if args is None else args)
    if args[:1] == ["--receiver"]:
        require(len(args) == 2 and args[1].isdigit() and 1 <= int(args[1]) <= 600, "invalid_receiver_timeout")
        deadline = time.monotonic() + int(args[1])
        request, pack = receive_input(deadline)
        print(encoded(receiver(request, pack, deadline)).decode(), end="")
        return 0
    fleet = load_fleet()
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--spec", required=True, help="Existing fleet launch spec; destinations must not exist")
    parser.add_argument("--repository", required=True)
    parser.add_argument("--commit", required=True, help="Full exact source commit; no branch expressions")
    parser.add_argument("--known-hosts", required=True)
    parser.add_argument("--identity-file", required=True)
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--timeout", type=int, default=90)
    parser.add_argument("--provision", action="store_true")
    parser.add_argument("--accept-plan")
    options = parser.parse_args(args)
    require(options.provision == (options.accept_plan is not None), "provision_requires_exact_approval")
    known = fleet.read_input(options.known_hosts, private=False)
    key = fleet.read_input(options.identity_file)
    try:
        report, code = execute(fleet, decode(fleet.read_input(options.spec)), options.repository, options.commit,
                               known, key, options.state_dir, options.timeout, options.accept_plan,
                               transport(fleet, known, key, options.timeout))
    except fleet.Refused as exc:
        raise Refused(str(exc)) from None
    print(encoded(report).decode(), end="")
    return code


def cli():
    def stop(signum, _frame):
        raise InterruptedError(signum)
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, stop)
    try:
        return main()
    except (Refused, OSError, ValueError, subprocess.SubprocessError) as exc:
        print(encoded({"schema": SCHEMA, "status": "error", "writes_attempted": WRITES_ATTEMPTED,
                       "code": str(exc) if isinstance(exc, Refused) else "provision_io_or_process_failure"}).decode(), end="")
        return 2


if __name__ == "__main__":
    sys.exit(cli())
