#!/usr/bin/env python3
"""Run explicitly reviewed tests against an exact commit in a fresh tree snapshot.

Preview never executes tests or writes files. --run executes trusted project code
as the current user: the separate snapshot and clean environment are NOT a sandbox.
No commands, dependencies, credentials or permissions are inferred from the project.
"""
import argparse
from contextlib import contextmanager
import hashlib
import importlib.util
import os
from pathlib import Path
import selectors
import signal
import stat
import subprocess
import sys
import time
import zlib

sys.dont_write_bytecode = True
_helper = Path(__file__).absolute().with_name("swarm-fleet-collect.py")
if _helper.is_symlink() or not _helper.is_file():
    raise SystemExit("Required trusted sibling swarm-fleet-collect.py is unavailable")
_spec = importlib.util.spec_from_file_location("acfs_test_collect", _helper)
collect = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(collect)
fleet = collect.fleet
require, encoded, decode, digest = fleet.require, fleet.encoded, fleet.decode, fleet.digest
SCHEMA = "acfs.swarm-fleet-test.v1"
SPEC_SCHEMA = "acfs.swarm-fleet-test-spec.v1"
EVIDENCE_SCHEMA = "acfs.swarm-fleet-test-evidence.v1"
PROMOTION_SCHEMA = "acfs.swarm-fleet-promotion.v1"
MAX_TREE_BYTES = 256 * 1024 * 1024
MAX_BLOB_BYTES = 8 * 1024 * 1024
MAX_LOG_BYTES = 8 * 1024 * 1024
GIT_SNAPSHOT_POLICY = "exact-tree-explicit-unsandboxed-tests-v2"
GIT_SNAPSHOT_MODE = "shallow-single-commit-v1"
RUN_STARTED = False
OUTPUT_DIRECTORY = None
PROMOTION_STARTED = False


def specification(value):
    require(type(value) is dict and set(value) == {"schema", "commands", "environment"}
            and value["schema"] == SPEC_SCHEMA, "invalid_test_specification")
    commands, env = value["commands"], value["environment"]
    require(type(commands) is list and 1 <= len(commands) <= 32, "select_one_to_thirty_two_tests")
    ids = set()
    for command in commands:
        require(type(command) is dict and set(command) == {"id", "argv", "timeout_seconds"}
                and fleet.matches(r"[a-z][a-z0-9_-]{0,63}", command["id"])
                and command["id"] not in ids, "invalid_or_duplicate_test_id")
        ids.add(command["id"])
        argv = command["argv"]
        require(type(argv) is list and 1 <= len(argv) <= 128 and all(type(a) is str
                and len(a) <= 8192 and "\0" not in a for a in argv), "invalid_test_argv")
        fleet.absolute_path(argv[0])
        require(type(command["timeout_seconds"]) is int and 1 <= command["timeout_seconds"] <= 3600,
                "invalid_test_timeout")
    require(type(env) is dict and len(env) <= 64, "invalid_test_environment")
    for key, value in env.items():
        require(fleet.matches(r"[A-Z_][A-Z0-9_]{0,127}", key) and type(value) is str
                and len(value) <= 8192 and "\0" not in value, "invalid_test_environment")
        require(key not in {"HOME", "TMPDIR", "TMP", "TEMP", "BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS",
                            "PYTHONPATH", "PYTHONHOME", "PYTHONSTARTUP"}
                and not key.startswith(("GIT_", "XDG_", "LD_", "DYLD_", "BASH_FUNC_")),
                "test_environment_override_refused")
    # The specification is data, never a shell fragment or environment expansion.
    return decode(encoded({"schema": SPEC_SCHEMA, "commands": commands, "environment": env}))


def executable(path):
    resolved = Path(path).resolve(strict=True)
    # Unlike private journals, system executable directories may be root-owned.
    for parent in (*reversed(resolved.parents), resolved):
        info = parent.lstat()
        sticky = info.st_uid == 0 and stat.S_ISDIR(info.st_mode) and info.st_mode & stat.S_ISVTX
        require(not stat.S_ISLNK(info.st_mode) and info.st_uid in (0, os.geteuid())
                and (not info.st_mode & 0o022 or sticky), "unsafe_test_executable")
    fd = os.open(resolved, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and not info.st_mode & 0o022
                and info.st_uid in (0, os.geteuid()) and os.access(resolved, os.X_OK),
                "unsafe_test_executable")
        require(0 < info.st_size <= MAX_TREE_BYTES, "test_executable_size_limit")
        sha = hashlib.sha256()
        total = 0
        while chunk := stream.read(1024 * 1024):
            total += len(chunk)
            require(total <= MAX_TREE_BYTES, "test_executable_size_limit")
            sha.update(chunk)
        after = os.fstat(stream.fileno())
        require((info.st_size, info.st_mtime_ns, info.st_ctime_ns) ==
                (after.st_size, after.st_mtime_ns, after.st_ctime_ns), "test_executable_changed")
    return {"path": path, "resolved_path": str(resolved), "sha256": sha.hexdigest(),
            "bytes": total, "identity": [info.st_dev, info.st_ino]}


def object_matches(raw, kind, oid, fmt):
    return hashlib.new(fmt, kind.encode() + b" " + str(len(raw)).encode() + b"\0" + raw).hexdigest() == oid


def tree_snapshot(git, commit, fmt):
    require(collect.oid(commit) and len(commit) == (40 if fmt == "sha1" else 64), "exact_test_commit_required")
    raw = git.run(["cat-file", "commit", commit])[1]
    require(object_matches(raw, "commit", commit, fmt), "test_commit_object_mismatch")
    tree = git.text(["rev-parse", "--verify", commit + "^{tree}"])
    raw_tree = git.run(["cat-file", "tree", tree])[1]
    require(object_matches(raw_tree, "tree", tree, fmt), "test_tree_object_mismatch")
    raw = git.run(["ls-tree", "-r", "-l", "-z", "--full-tree", tree])[1]
    require(not raw or raw.endswith(b"\0"), "invalid_test_tree")
    entries, total = [], 0
    for line in raw[:-1].split(b"\0") if raw else []:
        metadata, separator, name = line.partition(b"\t")
        fields = metadata.split()
        require(separator and len(fields) == 4, "invalid_test_tree")
        mode, kind, oid, size = (f.decode("ascii", "strict") for f in fields)
        require(kind == "blob" and mode in ("100644", "100755", "120000"), "submodule_or_special_tree_entry")
        require(collect.oid(oid) and size.isdecimal(), "invalid_test_tree")
        path = name.decode("utf-8", "strict")
        require(path and not path.startswith("/") and len(path) <= 4096
                and all(p not in ("", ".", "..", ".git") for p in path.split("/")), "unsafe_test_tree_path")
        size = int(size)
        require(size <= MAX_BLOB_BYTES, "test_blob_size_limit")
        total += size
        entries.append({"path": path, "mode": mode, "oid": oid, "bytes": size})
    require(entries and len(entries) <= 10000 and total <= MAX_TREE_BYTES, "test_tree_size_limit")
    return tree, entries, total


def read_blobs(git, entries, fmt):
    """Use bounded cat-file batches, preserving raw bytes without filters/attributes."""
    blobs, pending, size = {}, [], 0
    unique = {e["oid"]: e for e in entries}
    def flush():
        if not pending:
            return
        raw = git.run(["cat-file", "--batch"], b"".join(e["oid"].encode() + b"\n" for e in pending),
                      limit=collect.MAX_BUNDLE)[1]
        offset = 0
        for entry in pending:
            end = raw.find(b"\n", offset)
            expected = (entry["oid"] + " blob " + str(entry["bytes"])).encode()
            require(end >= offset and raw[offset:end] == expected, "invalid_test_blob_response")
            content = raw[end + 1:end + 1 + entry["bytes"]]
            offset = end + 2 + entry["bytes"]
            require(len(content) == entry["bytes"] and raw[offset - 1:offset] == b"\n"
                    and object_matches(content, "blob", entry["oid"], fmt), "test_blob_object_mismatch")
            require(not content.startswith(b"version https://git-lfs.github.com/spec/v1\n"),
                    "lfs_materialization_required")
            blobs[entry["oid"]] = content
        require(offset == len(raw), "invalid_test_blob_response")
        pending.clear()
    for entry in unique.values():
        if size + entry["bytes"] + 100 > 12 * 1024 * 1024:
            flush()
            size = 0
        pending.append(entry)
        size += entry["bytes"] + 100
    flush()
    return blobs


def materialize(workspace, entries, blobs):
    # Create directories and regular files before links, so no link can redirect
    # a write performed by the runner. The workspace is new and private.
    for entry in entries:
        path = workspace / entry["path"]
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        if entry["mode"] != "120000":
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                         0o700 if entry["mode"] == "100755" else 0o600)
            with os.fdopen(fd, "wb") as stream:
                os.fchmod(stream.fileno(), 0o700 if entry["mode"] == "100755" else 0o600)
                stream.write(blobs[entry["oid"]])
    for entry in entries:
        if entry["mode"] == "120000":
            target = blobs[entry["oid"]].decode("utf-8", "strict")
            require(target and not os.path.isabs(target) and "\0" not in target and len(target) <= 4096,
                    "unsafe_test_symlink")
            os.symlink(target, workspace / entry["path"])
    for entry in entries:
        if entry["mode"] == "120000":
            try:
                target = (workspace / entry["path"]).resolve(strict=True)
                require(target.is_relative_to(workspace), "test_symlink_escapes_workspace")
            except (OSError, RuntimeError):
                raise fleet.Refused("unsafe_test_symlink") from None


def workspace_matches(workspace, entries, fmt):
    try:
        for entry in entries:
            path = workspace / entry["path"]
            with fleet.directory_fd(path.parent) as fd:
                info = os.stat(path.name, dir_fd=fd, follow_symlinks=False)
                if entry["mode"] == "120000":
                    require(stat.S_ISLNK(info.st_mode), "test_sources_changed")
                    raw = os.fsencode(os.readlink(path.name, dir_fd=fd))
                else:
                    require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
                            and bool(info.st_mode & 0o111) == (entry["mode"] == "100755"), "test_sources_changed")
                    raw = collect.read_bundle(fd, path.name)
                require(len(raw) == entry["bytes"] and object_matches(raw, "blob", entry["oid"], fmt),
                        "test_sources_changed")
        return True
    except (fleet.Refused, OSError, ValueError):
        return False


def git_snapshot_objects(git, commit, tree, entries, fmt):
    """Reconstruct canonical trees, checking their root against the real commit.

    Only the selected commit and its tree are copied. Parents, tags, other refs,
    configuration, hooks, credentials and source object-store links never enter
    the workspace. Reconstruction is iterative and bounded, including depth.
    """
    directories = {"": {}}
    for entry in entries:
        parts = entry["path"].split("/")
        parent = ""
        for name in parts[:-1]:
            path = parent + "/" + name if parent else name
            existing = directories[parent].setdefault(name, ("40000", path))
            require(existing == ("40000", path), "invalid_git_snapshot_tree")
            directories.setdefault(path, {})
            require(len(directories) <= 10000, "git_snapshot_directory_limit")
            parent = path
        require(parts[-1] not in directories[parent], "invalid_git_snapshot_tree")
        directories[parent][parts[-1]] = (entry["mode"], entry["oid"])
    objects, tree_ids, total = {}, {}, 0
    for path in sorted(directories, key=lambda p: (p.count("/"), len(p)), reverse=True):
        children = directories[path]
        raw = bytearray()
        for name in sorted(children, key=lambda n: n.encode() + (b"/" if children[n][0] == "40000" else b"")):
            mode, oid = children[name]
            if mode == "40000":
                oid = tree_ids[oid]
            raw.extend(mode.encode() + b" " + name.encode() + b"\0" + bytes.fromhex(oid))
        raw = bytes(raw)
        total += len(raw)
        require(total <= MAX_BLOB_BYTES, "git_snapshot_metadata_limit")
        oid = hashlib.new(fmt, b"tree " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
        tree_ids[path] = oid
        objects[oid] = ("tree", raw)
    require(tree_ids[""] == tree, "git_snapshot_tree_mismatch")
    raw = git.run(["cat-file", "commit", commit], limit=MAX_BLOB_BYTES)[1]
    require(total + len(raw) <= MAX_BLOB_BYTES and raw.startswith(b"tree " + tree.encode() + b"\n")
            and object_matches(raw, "commit", commit, fmt), "git_snapshot_commit_mismatch")
    objects[commit] = ("commit", raw)
    return objects


def git_snapshot_layout(commit, objects, entries, fmt):
    config = ("[core]\n\trepositoryformatversion = " + ("1" if fmt == "sha256" else "0")
              + "\n\tbare = false\n\tfilemode = true\n\tlogAllRefUpdates = false\n"
                "\thooksPath = /dev/null\n\tfsmonitor = false\n[gc]\n\tauto = 0\n"
                "[maintenance]\n\tauto = false\n")
    if fmt == "sha256":
        config += "[extensions]\n\tobjectformat = sha256\n"
    files = {"HEAD": (commit + "\n").encode(), "shallow": (commit + "\n").encode(), "config": config.encode()}
    for oid, (kind, raw) in objects.items():
        files["objects/" + oid[:2] + "/" + oid[2:]] = (kind, len(raw), oid)
    for entry in entries:
        oid = entry["oid"]
        files["objects/" + oid[:2] + "/" + oid[2:]] = ("blob", entry["bytes"], oid)
    directories = {"", "objects", "refs", "refs/heads", "refs/tags"}
    for name in files:
        if name.startswith("objects/"):
            directories.add(name.rsplit("/", 1)[0])
    return files, directories


def materialize_git_snapshot(workspace, commit, tree, objects, entries, blobs, fmt):
    files, directories = git_snapshot_layout(commit, objects, entries, fmt)
    root = workspace / ".git"
    for name in sorted(directories, key=lambda p: (p.count("/"), len(p), p)):
        (root / name).mkdir(mode=0o700)
    for name, value in files.items():
        if isinstance(value, tuple):
            kind, size, oid = value
            raw = blobs[oid] if kind == "blob" else objects[oid][1]
            value = zlib.compress(kind.encode() + b" " + str(size).encode() + b"\0" + raw)
        fd = os.open(root / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "wb") as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(value)
            stream.flush()
            os.fsync(stream.fileno())
    # read-tree populates only the new index; no checkout, filters or hooks run.
    collect.LocalGit(workspace, 10).run(["read-tree", "--no-sparse-checkout", tree])
    os.chmod(root / "index", 0o600)
    return files, directories


def git_snapshot_read(fd, name, limit):
    handle = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    with os.fdopen(handle, "rb") as stream:
        info = os.fstat(stream.fileno())
        # Git may refresh index stat data with mode 0644. Its parent is private;
        # permit that normal refresh, never a different owner/link/shared write.
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and info.st_uid == os.geteuid()
                and not info.st_mode & 0o022 and info.st_size <= limit, "unsafe_git_snapshot_file")
        raw = stream.read(limit + 1)
        require(len(raw) <= limit, "git_snapshot_file_limit")
        return raw


def git_snapshot_matches(workspace, layout, entries, fmt):
    if layout is None:
        return True
    files, directories = layout
    root = workspace / ".git"
    try:
        members = {name: set() for name in directories}
        for name in (set(files) | directories | {"index"}) - {""}:
            parent, _, child = name.rpartition("/")
            members[parent].add(child)
        for directory, expected in members.items():
            with fleet.directory_fd(root / directory, private=True) as fd:
                require(set(os.listdir(fd)) == expected, "git_snapshot_members_changed")
                for child in expected:
                    name = directory + "/" + child if directory else child
                    if name in directories:
                        continue
                    if name == "index":
                        git_snapshot_read(fd, child, MAX_BLOB_BYTES)
                        continue
                    wanted = files[name]
                    limit = len(wanted) if isinstance(wanted, bytes) else MAX_BLOB_BYTES + 65536
                    raw = git_snapshot_read(fd, child, limit)
                    if isinstance(wanted, bytes):
                        require(raw == wanted, "git_snapshot_control_changed")
                    else:
                        kind, size, oid = wanted
                        header = kind.encode() + b" " + str(size).encode() + b"\0"
                        inflater = zlib.decompressobj()
                        content = inflater.decompress(raw, len(header) + size + 1)
                        require(inflater.eof and not inflater.unused_data and not inflater.unconsumed_tail
                                and content.startswith(header) and len(content) == len(header) + size
                                and object_matches(content[len(header):], kind, oid, fmt), "git_snapshot_object_changed")
        # Only after rejecting config, links and extra members may Git parse its
        # index. Read-only plumbing accepts harmless stat-cache refreshes, not
        # added/deleted/staged entries, conflict stages or a different commit.
        raw = collect.LocalGit(workspace, 10).run(["ls-files", "--stage", "-z"], limit=MAX_BLOB_BYTES)[1]
        expected = b"".join((e["mode"] + " " + e["oid"] + " 0\t" + e["path"]).encode() + b"\0"
                            for e in sorted(entries, key=lambda e: e["path"].encode()))
        return raw == expected
    except (fleet.Refused, OSError, ValueError, zlib.error, subprocess.SubprocessError):
        return False


def run_command(command, program, workspace, env, logs, deadline):
    """Capture bounded private logs; failure and timeout are never successful tests."""
    row = {"id": command["id"], "status": "unconfirmed", "exit_code": None, "logs": {}}
    start = time.monotonic()
    deadline = min(deadline, start + command["timeout_seconds"])
    streams = {}
    for name in ("stdout", "stderr"):
        path = logs / (command["id"] + "." + name)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        streams[name] = (os.fdopen(fd, "wb"), hashlib.sha256(), 0, path.name)
    process = None
    total = 0
    try:
        process = subprocess.Popen([program["resolved_path"], *command["argv"][1:]], cwd=workspace,
                                   env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, start_new_session=True)
        with selectors.DefaultSelector() as poll:
            for name in streams:
                pipe = getattr(process, name)
                os.set_blocking(pipe.fileno(), False)
                poll.register(pipe, selectors.EVENT_READ, name)
            while poll.get_map() or process.poll() is None:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    row["status"] = "timed_out"
                    break
                exceeded = False
                for key, _ in poll.select(min(remaining, 0.05)):
                    chunk = os.read(key.fd, 65536)
                    if not chunk:
                        poll.unregister(key.fileobj)
                        continue
                    kept = chunk[:max(0, MAX_LOG_BYTES - total)]
                    stream, sha, size, filename = streams[key.data]
                    stream.write(kept)
                    sha.update(kept)
                    streams[key.data] = stream, sha, size + len(kept), filename
                    total += len(kept)
                    if len(kept) != len(chunk):
                        row["status"], exceeded = "output_limit", True
                        break
                if exceeded:
                    break
                if not poll.get_map() and process.poll() is None:
                    time.sleep(0.01)
            else:
                row["status"] = "passed" if process.returncode == 0 else "failed"
    except OSError:
        row["status"] = "process_error"
    finally:
        if process is not None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)
            row["exit_code"] = process.returncode
            process.stdout.close()
            process.stderr.close()
        for name, (stream, sha, size, filename) in streams.items():
            stream.flush()
            os.fsync(stream.fileno())
            stream.close()
            row["logs"][name] = {"file": "logs/" + filename, "bytes": size, "sha256": sha.hexdigest()}
        row["duration_ms"] = int((time.monotonic() - start) * 1000)
    return row


def execute(repository, commit, spec, output, timeout=600, approval=None, *, git_snapshot=False):
    global RUN_STARTED, OUTPUT_DIRECTORY
    RUN_STARTED, OUTPUT_DIRECTORY = False, None
    require(sys.platform == "linux" and os.getuid() == os.geteuid() and os.geteuid() != 0
            and not os.environ.get("SUDO_USER"), "test_as_repository_owner_without_sudo")
    require(type(timeout) is int and 1 <= timeout <= 3600, "invalid_test_deadline")
    require(approval is None or fleet.matches(r"[0-9a-f]{64}", approval), "invalid_test_approval")
    require(type(git_snapshot) is bool, "invalid_git_snapshot_option")
    spec = specification(spec)
    repository, output = (Path(fleet.absolute_path(str(Path(os.path.abspath(p))))) for p in (repository, output))
    fleet.state_preflight({"state_directory": str(output)})
    git = collect.LocalGit(repository, timeout)
    destination = collect.destination_state(git)
    require(output != repository and repository not in output.parents
            and all(Path(destination[k]["path"]) not in (output, *output.parents)
                    for k in ("common_directory", "git_directory", "object_directory")), "test_output_inside_repository")
    with fleet.directory_fd(destination["common_directory"]["path"]) as source:
        collect.lock(source)
        tree, entries, total = tree_snapshot(git, commit, destination["object_format"])
        objects = git_snapshot_objects(git, commit, tree, entries, destination["object_format"]) if git_snapshot else None
        programs = {c["argv"][0]: executable(c["argv"][0]) for c in spec["commands"]}
        with fleet.directory_fd(output.parent) as parent:
            info = os.fstat(parent)
            parent_identity = [info.st_dev, info.st_ino]
        plan = {"schema": SCHEMA, "policy": "exact-tree-explicit-unsandboxed-tests-v1",
                "source_sha256": {name: digest(Path(__file__).with_name(name).read_bytes()) for name in
                                  ("swarm-fleet-test.py", "swarm-fleet-collect.py", "swarm-fleet-launch.py")},
                "destination": destination,
                "commit": commit, "tree": tree, "tree_entries_sha256": digest(encoded(entries)),
                "files": len(entries), "tree_bytes": total, "specification": spec, "executables": programs,
                "output_directory": str(output), "output_parent_identity": parent_identity,
                "deadline_seconds": timeout, "runs_project_code": True, "sandboxed": False,
                "network_isolated": False, "inherits_environment": False, "git_history_included": False}
        if git_snapshot:
            plan.update(policy=GIT_SNAPSHOT_POLICY, git_snapshot=GIT_SNAPSHOT_MODE)
        require(len(encoded(plan)) <= fleet.LIMIT, "test_plan_size_limit")
        plan_sha = digest(encoded(plan))
        report = {"schema": SCHEMA, "status": "preview", "plan": plan, "plan_sha256": plan_sha,
                  "run_started": False, "task_completion_verified": False}
        if approval is None:
            return report
        require(approval == plan_sha, "test_approval_mismatch")
        blobs = read_blobs(git, entries, destination["object_format"])
        require(collect.destination_state(git) == destination, "test_source_changed")
        with fleet.directory_fd(output.parent) as parent:
            info = os.fstat(parent)
            require([info.st_dev, info.st_ino] == parent_identity, "test_output_parent_changed")
            os.mkdir(output.name, 0o700, dir_fd=parent)
            os.fsync(parent)
        OUTPUT_DIRECTORY = str(output)
        with fleet.directory_fd(output, private=True) as dest:
            collect.lock(dest)
            fleet.publish(dest, "intent.json", {"schema": SCHEMA, "plan": plan})
            workspace, logs = output / "workspace", output / "logs"
            for path in (workspace, logs, output / "home", output / "tmp"):
                path.mkdir(mode=0o700)
            materialize(workspace, entries, blobs)
            layout = materialize_git_snapshot(workspace, commit, tree, objects, entries, blobs,
                                               destination["object_format"]) if git_snapshot else None
            def sources_match():
                return (workspace_matches(workspace, entries, destination["object_format"])
                        and git_snapshot_matches(workspace, layout, entries, destination["object_format"]))
            require(sources_match(), "test_snapshot_mismatch")
            env = {"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8", "CI": "true",
                   **spec["environment"], "HOME": str(output / "home"), "TMPDIR": str(output / "tmp"),
                   "XDG_CONFIG_HOME": str(output / "home/config"), "XDG_CACHE_HOME": str(output / "home/cache"),
                   "XDG_DATA_HOME": str(output / "home/data")}
            if git_snapshot:
                env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null",
                           GIT_NO_REPLACE_OBJECTS="1", GIT_NO_LAZY_FETCH="1", GIT_TERMINAL_PROMPT="0")
            rows = [{"id": c["id"], "status": "not_attempted"} for c in spec["commands"]]
            deadline = time.monotonic() + timeout
            for index, command in enumerate(spec["commands"]):
                if time.monotonic() >= deadline:
                    break
                require(executable(command["argv"][0]) == programs[command["argv"][0]], "test_executable_changed")
                if time.monotonic() >= deadline:
                    break
                fleet.publish(dest, command["id"] + ".attempt.json", {"schema": SCHEMA,
                              "plan_sha256": plan_sha, "command": command})
                RUN_STARTED = report["run_started"] = True
                rows[index] = run_command(command, programs[command["argv"][0]], workspace, env, logs, deadline)
                unchanged = sources_match()
                rows[index]["tracked_sources_unchanged"] = unchanged
                if not unchanged:
                    rows[index]["status"] = "sources_changed"
                fleet.publish(dest, command["id"] + ".result.json", rows[index])
                if rows[index]["status"] != "passed":
                    break
            report.update(status="passed" if all(r["status"] == "passed" for r in rows) else "failed", tests=rows)
            with fleet.directory_fd(output, private=True) as fresh:
                require(os.path.samestat(os.fstat(dest), os.fstat(fresh)), "test_output_directory_changed")
            fleet.publish(dest, "result.json", report)
            return report


def evidence_plan(plan, expected):
    """Validate a historical plan, without invoking its recorded executables."""
    fields = {"schema", "policy", "source_sha256", "destination", "commit", "tree",
              "tree_entries_sha256", "files", "tree_bytes", "specification", "executables",
              "output_directory", "output_parent_identity", "deadline_seconds", "runs_project_code",
              "sandboxed", "network_isolated", "inherits_environment", "git_history_included"}
    require(type(plan) is dict, "invalid_saved_test_plan")
    if plan.get("policy") == GIT_SNAPSHOT_POLICY:
        fields.add("git_snapshot")
        require(plan.get("git_snapshot") == GIT_SNAPSHOT_MODE, "invalid_saved_git_snapshot")
    require(set(plan) == fields and plan["schema"] == SCHEMA
            and plan["policy"] in ("exact-tree-explicit-unsandboxed-tests-v1", GIT_SNAPSHOT_POLICY), "invalid_saved_test_plan")
    require(fleet.matches(r"[0-9a-f]{64}", expected) and digest(encoded(plan)) == expected,
            "test_evidence_plan_mismatch")
    specification(plan["specification"])
    require(all(plan[k] is False for k in ("sandboxed", "network_isolated", "inherits_environment", "git_history_included"))
            and plan["runs_project_code"] is True, "invalid_saved_test_policy")
    hashes = plan["source_sha256"]
    require(type(hashes) is dict and set(hashes) == {"swarm-fleet-test.py", "swarm-fleet-collect.py", "swarm-fleet-launch.py"}
            and all(fleet.matches(r"[0-9a-f]{64}", h) for h in hashes.values()), "invalid_saved_test_sources")
    require(collect.oid(plan["commit"]) and collect.oid(plan["tree"])
            and fleet.matches(r"[0-9a-f]{64}", plan["tree_entries_sha256"])
            and type(plan["files"]) is int and 1 <= plan["files"] <= 10000
            and type(plan["tree_bytes"]) is int and 0 <= plan["tree_bytes"] <= MAX_TREE_BYTES
            and type(plan["deadline_seconds"]) is int and 1 <= plan["deadline_seconds"] <= 3600,
            "invalid_saved_test_snapshot")
    fleet.absolute_path(plan["output_directory"])
    parent = plan["output_parent_identity"]
    require(type(parent) is list and len(parent) == 2 and all(type(n) is int and n >= 0 for n in parent),
            "invalid_saved_test_parent")
    programs = plan["executables"]
    paths = {c["argv"][0] for c in plan["specification"]["commands"]}
    require(type(programs) is dict and set(programs) == paths, "invalid_saved_test_executables")
    for path, program in programs.items():
        require(type(program) is dict and set(program) == {"path", "resolved_path", "sha256", "bytes", "identity"}
                and program["path"] == path and fleet.matches(r"[0-9a-f]{64}", program["sha256"])
                and type(program["bytes"]) is int and 0 < program["bytes"] <= MAX_TREE_BYTES,
                "invalid_saved_test_executable")
        fleet.absolute_path(program["resolved_path"])
        identity = program["identity"]
        require(type(identity) is list and len(identity) == 2 and all(type(n) is int and n >= 0 for n in identity),
                "invalid_saved_test_executable")


def log_fingerprint(fd, name):
    raw = collect.read_bundle(fd, name)
    require(len(raw) <= MAX_LOG_BYTES, "test_evidence_log_limit")
    return {"file": "logs/" + name, "bytes": len(raw), "sha256": digest(raw)}


def evidence_records(fd, plan, expected):
    """A final summary must agree with every command intent, result and log."""
    metadata = {"intent.json": fleet.read_at(fd, "intent.json"),
                "result.json": fleet.read_at(fd, "result.json", optional=True)}
    if metadata["result.json"] is None:
        # Incomplete runs may have live children or partially written files.
        # Do not guess a successful outcome from their prefix or try to repair it.
        return None, metadata, {}
    result = decode(metadata["result.json"])
    fields = {"schema", "status", "plan", "plan_sha256", "run_started", "task_completion_verified", "tests"}
    require(type(result) is dict and set(result) == fields and result["schema"] == SCHEMA
            and result["status"] in ("passed", "failed") and result["plan_sha256"] == expected
            and encoded(result["plan"]) == encoded(plan) and result["task_completion_verified"] is False
            and type(result["run_started"]) is bool, "invalid_test_evidence_result")
    commands, rows = plan["specification"]["commands"], result["tests"]
    require(type(rows) is list and len(rows) == len(commands), "test_evidence_command_count")
    logs, stopped, attempted = {}, False, False
    for command, row in zip(commands, rows):
        name = command["id"]
        require(type(row) is dict and row.get("id") == name, "test_evidence_command_order")
        for suffix in (".attempt.json", ".result.json"):
            metadata[name + suffix] = fleet.read_at(fd, name + suffix, optional=True)
        attempt, saved = metadata[name + ".attempt.json"], metadata[name + ".result.json"]
        if row.get("status") == "not_attempted":
            require(set(row) == {"id", "status"} and attempt is None and saved is None,
                    "test_evidence_unattempted_mismatch")
            stopped = True
            continue
        require(not stopped and attempt is not None and saved is not None, "test_evidence_nonprefix_history")
        attempted = True
        require(encoded(decode(attempt)) == encoded({"schema": SCHEMA, "plan_sha256": expected, "command": command})
                and encoded(decode(saved)) == encoded(row), "test_evidence_record_mismatch")
        require(set(row) == {"id", "status", "exit_code", "logs", "duration_ms", "tracked_sources_unchanged"}
                and type(row["status"]) is str
                and row["status"] in {"passed", "failed", "timed_out", "output_limit", "process_error", "sources_changed"}
                and (row["exit_code"] is None or type(row["exit_code"]) is int)
                and type(row["duration_ms"]) is int and row["duration_ms"] >= 0
                and type(row["tracked_sources_unchanged"]) is bool, "invalid_test_evidence_command")
        require((row["status"] == "sources_changed") == (not row["tracked_sources_unchanged"]),
                "test_evidence_source_state_mismatch")
        if row["status"] == "passed":
            require(row["exit_code"] == 0, "test_evidence_false_pass")
        elif row["status"] == "failed":
            require(type(row["exit_code"]) is int and row["exit_code"] != 0, "test_evidence_false_failure")
        stopped = row["status"] != "passed"
        require(type(row["logs"]) is dict and set(row["logs"]) == {"stdout", "stderr"}, "invalid_test_evidence_logs")
        for stream in ("stdout", "stderr"):
            filename = name + "." + stream
            with fleet.directory_fd(Path(plan["output_directory"]) / "logs", private=True) as log_fd:
                actual = log_fingerprint(log_fd, filename)
            require(encoded(row["logs"][stream]) == encoded(actual), "test_evidence_log_mismatch")
            logs[filename] = actual
        require(sum(row["logs"][s]["bytes"] for s in ("stdout", "stderr")) <= MAX_LOG_BYTES,
                "test_evidence_log_limit")
    passed = all(row["status"] == "passed" for row in rows)
    require(result["run_started"] == attempted and (result["status"] == "passed") == passed,
            "test_evidence_summary_mismatch")
    return result, metadata, logs


@contextmanager
def test_evidence(path, repository, expected, timeout=90):
    """Hold evidence/repository locks and expose a guard for downstream consumers.

    This checks local integrity, not provenance against the same user who owns
    both test code and records. No recorded executable is invoked or rehashed.
    """
    require(sys.platform == "linux" and os.getuid() == os.geteuid() and os.geteuid() != 0
            and not os.environ.get("SUDO_USER"), "verify_as_repository_owner_without_sudo")
    require(type(timeout) is int and 1 <= timeout <= 3600, "invalid_evidence_timeout")
    path, repository = (Path(fleet.absolute_path(str(Path(os.path.abspath(p))))) for p in (path, repository))
    with fleet.directory_fd(path, private=True) as fd:
        collect.lock(fd)
        intent_raw = fleet.read_at(fd, "intent.json")
        intent = decode(intent_raw)
        require(type(intent) is dict and set(intent) == {"schema", "plan"} and intent["schema"] == SCHEMA,
                "invalid_test_evidence_intent")
        plan = intent["plan"]
        evidence_plan(plan, expected)
        require(plan["output_directory"] == str(path), "test_evidence_directory_mismatch")
        with fleet.directory_fd(path.parent) as parent:
            info = os.fstat(parent)
            require([info.st_dev, info.st_ino] == plan["output_parent_identity"], "test_evidence_parent_mismatch")
        git = collect.LocalGit(repository, timeout)
        destination = collect.destination_state(git)
        require(encoded(destination) == encoded(plan["destination"]), "test_evidence_repository_mismatch")
        with fleet.directory_fd(destination["common_directory"]["path"]) as source:
            collect.lock(source)
            tree, entries, total = tree_snapshot(git, plan["commit"], destination["object_format"])
            require(tree == plan["tree"] and digest(encoded(entries)) == plan["tree_entries_sha256"]
                    and len(entries) == plan["files"] and total == plan["tree_bytes"], "test_evidence_tree_mismatch")
            # Hash all selected Git blobs, not merely their size or pathname.
            read_blobs(git, entries, destination["object_format"])
            result, metadata, logs = evidence_records(fd, plan, expected)
            require(metadata["intent.json"] == intent_raw, "test_evidence_changed")
            workspace = path / "workspace"
            layout = None
            if plan["policy"] == GIT_SNAPSHOT_POLICY:
                objects = git_snapshot_objects(git, plan["commit"], tree, entries, destination["object_format"])
                layout = git_snapshot_layout(plan["commit"], objects, entries, destination["object_format"])
            def sources_match():
                return (workspace_matches(workspace, entries, destination["object_format"])
                        and git_snapshot_matches(workspace, layout, entries, destination["object_format"]))
            unchanged = sources_match()
            directories = {"workspace", "logs", "home", "tmp"}
            def guard():
                with fleet.directory_fd(path, private=True) as current:
                    require(os.path.samestat(os.fstat(fd), os.fstat(current)), "test_evidence_directory_changed")
                for filename, raw in metadata.items():
                    require(fleet.read_at(fd, filename, optional=True) == raw, "test_evidence_changed")
                require(collect.destination_state(git) == destination, "test_evidence_repository_changed")
                if result is not None:
                    require(set(os.listdir(fd)) == directories | {k for k, v in metadata.items() if v is not None},
                            "unexpected_test_evidence_member")
                    for name in directories:
                        with fleet.directory_fd(path / name, private=True):
                            pass
                    with fleet.directory_fd(path / "logs", private=True) as log_fd:
                        require(set(os.listdir(log_fd)) == set(logs), "unexpected_test_evidence_log")
                        for name, expected_log in logs.items():
                            require(log_fingerprint(log_fd, name) == expected_log, "test_evidence_changed")
                    require(sources_match() == unchanged, "test_evidence_workspace_changed")
            guard()
            status = "incomplete" if result is None else result["status"] if unchanged else "sources_changed"
            evidence_hash = digest(encoded({"records": {k: digest(v) if v is not None else None for k, v in metadata.items()},
                                           "logs": logs})) if result is not None else None
            report = {"schema": EVIDENCE_SCHEMA, "status": status, "test_plan_sha256": expected,
                      "evidence_sha256": evidence_hash, "commit": plan["commit"], "tree": tree,
                      "read_only": True, "runs_project_code": False, "tests_rerun": False,
                      "complete": result is not None, "tracked_sources_unchanged": unchanged,
                      "test_provenance_verified": False, "task_completion_verified": False,
                      "tests": [{"id": r["id"], "status": r["status"], "exit_code": r.get("exit_code")}
                                for r in result["tests"]] if result else []}
            yield report, plan, git, guard
            guard()


def verify_test_run(path, repository, expected, timeout=90):
    with test_evidence(path, repository, expected, timeout) as (report, _, _, _guard):
        return report


def evidence_main(args):
    parser = argparse.ArgumentParser(description="Verify saved exact-candidate test evidence without rerunning tests",
                                     allow_abbrev=False)
    parser.add_argument("--verify", required=True, help="Original private test output directory")
    parser.add_argument("--repository", required=True)
    parser.add_argument("--expect-plan", required=True, help="Original test approval digest retained outside the run directory")
    parser.add_argument("--timeout", type=int, default=90)
    options = parser.parse_args(args)
    report = verify_test_run(options.verify, options.repository, options.expect_plan, options.timeout)
    print(encoded(report).decode(), end="")
    return 0 if report["status"] == "passed" else 1


def idle_branch(git, reference):
    """Include all registered worktrees, even locked/prunable ones; never prune."""
    raw = git.run(["worktree", "list", "--porcelain", "-z"])[1]
    require(raw.endswith(b"\0\0"), "invalid_promotion_worktree_list")
    records = raw[:-2].split(b"\0\0")
    require(1 <= len(records) <= 1024, "promotion_worktree_limit")
    for record in records:
        fields = {}
        for field in record.split(b"\0"):
            key, _, value = field.partition(b" ")
            require(key in {b"worktree", b"HEAD", b"branch", b"detached", b"bare", b"locked", b"prunable"}
                    and key not in fields, "invalid_promotion_worktree_list")
            fields[key] = value
        require(b"worktree" in fields and sum(k in fields for k in (b"branch", b"detached", b"bare")) == 1,
                "ambiguous_promotion_worktree_state")
        branch = fields.get(b"branch")
        if branch is not None:
            require(branch.startswith(b"refs/heads/"), "invalid_promotion_worktree_branch")
            # Account for a checked-out symbolic branch that ultimately targets
            # this branch, as well as the usual direct branch reported by Git.
            code, target = git.run(["symbolic-ref", "--quiet", branch.decode("utf-8", "strict")], allowed=(0, 1))
            require(branch != reference.encode() and (code != 0 or target.rstrip(b"\n") != reference.encode()),
                    "promotion_branch_is_checked_out")


def promote_ref(git, reference, old, candidate, guard):
    """Recheck while Git holds the ref lock, then perform exactly one CAS update.

    --no-deref alone still permits overwriting a symbolic ref whose target has
    the expected OID. Inspect it AFTER prepare, while cooperating Git writers
    cannot replace it. Closing an uncommitted transaction aborts it.
    """
    global PROMOTION_STARTED
    options = ["core.hooksPath=/dev/null", "core.fsmonitor=false", "maintenance.auto=false", "gc.auto=0",
               "core.logAllRefUpdates=false"]
    argv = ["/usr/bin/git", "--no-pager", "-C", str(git.repository)]
    for option in options:
        argv += ["-c", option]
    argv += ["update-ref", "--no-deref", "--stdin", "-m", "acfs-fleet tested candidate promotion"]
    PROMOTION_STARTED = True  # even a prepared transaction may leave locks after SIGKILL
    env = {**git.env, "GIT_COMMITTER_NAME": "ACFS Fleet Promotion", "GIT_COMMITTER_EMAIL": "acfs-fleet@localhost"}
    process = subprocess.Popen(argv, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, start_new_session=True)
    commit_sent = False
    try:
        with selectors.DefaultSelector() as poll:
            os.set_blocking(process.stdout.fileno(), False)
            poll.register(process.stdout, selectors.EVENT_READ)
            def exchange(data, expected):
                require(time.monotonic() < git.deadline, "promotion_git_deadline")
                process.stdin.write(data)
                process.stdin.flush()
                received = bytearray()
                while len(received) < len(expected):
                    remaining = git.deadline - time.monotonic()
                    require(remaining > 0, "promotion_git_deadline")
                    for key, _ in poll.select(min(remaining, 0.05)):
                        chunk = os.read(key.fd, 4096)
                        require(chunk and len(received) + len(chunk) <= 4096, "promotion_transaction_refused")
                        received.extend(chunk)
                    require(process.poll() is None or len(received) == len(expected), "promotion_transaction_refused")
                require(bytes(received) == expected, "promotion_transaction_refused")
            exchange(("start\nupdate " + reference + " " + candidate + " " + old + "\nprepare\n").encode(),
                     b"start: ok\nprepare: ok\n")
            guard()
            require(collect.review_ref_value(git, reference) == old, "promotion_branch_changed_or_symbolic")
            idle_branch(git, reference)
            commit_sent = True
            exchange(b"commit\n", b"commit: ok\n")
            process.stdin.close()
            require(process.wait(timeout=5) == 0, "promotion_transaction_refused")
    finally:
        if process.poll() is None:
            try:
                if not commit_sent and not process.stdin.closed:
                    process.stdin.write(b"abort\n")
                    process.stdin.flush()
                if not process.stdin.closed:
                    process.stdin.close()
                process.wait(timeout=1)
            except (OSError, subprocess.TimeoutExpired):
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=5)
        if not process.stdin.closed:
            process.stdin.close()
        process.stdout.close()


def promote_candidate(path, repository, expected, branch, old, timeout=90, approval=None, *, check=False):
    global PROMOTION_STARTED
    PROMOTION_STARTED = False
    require(fleet.matches(r"[A-Za-z0-9][A-Za-z0-9_./-]{0,191}", branch), "invalid_promotion_branch")
    require(collect.oid(old), "promotion_requires_exact_old_commit")
    require(approval is None or fleet.matches(r"[0-9a-f]{64}", approval), "invalid_promotion_approval")
    require(type(check) is bool and (not check or approval is not None), "promotion_check_requires_original_approval")
    with test_evidence(path, repository, expected, timeout) as (evidence, saved, git, guard):
        require(evidence["status"] == "passed", "passing_test_evidence_required")
        reference = "refs/heads/" + branch
        git.run(["check-ref-format", reference])
        candidate = evidence["commit"]
        fmt = saved["destination"]["object_format"]
        require(len(old) == len(candidate), "promotion_object_format_mismatch")
        raw = git.run(["cat-file", "commit", old])[1]
        require(object_matches(raw, "commit", old, fmt), "promotion_old_commit_mismatch")
        code, _ = git.run(["merge-base", "--is-ancestor", old, candidate], allowed=(0, 1))
        require(code == 0, "promotion_not_fast_forward")
        git.run(["rev-list", "--objects", "--quiet", "--missing=error", candidate, "--"])
        plan = {"schema": PROMOTION_SCHEMA, "policy": "verified-tests-unchecked-out-fast-forward-v1",
                "test_directory": saved["output_directory"], "test_plan_sha256": expected,
                "evidence_sha256": evidence["evidence_sha256"], "destination": saved["destination"],
                "ref": reference, "expected_old_commit": old, "candidate_commit": candidate,
                "candidate_tree": evidence["tree"], "timeout_seconds": timeout,
                "git_version": git.text(["--version"]),
                "source_sha256": {name: digest(Path(__file__).with_name(name).read_bytes()) for name in
                                  ("swarm-fleet-test.py", "swarm-fleet-collect.py", "swarm-fleet-launch.py")}}
        plan_sha = digest(encoded(plan))
        require(approval is None or approval == plan_sha, "promotion_approval_mismatch")
        report = {"schema": PROMOTION_SCHEMA, "status": "preview", "plan": plan, "plan_sha256": plan_sha,
                  "promotion_started": False, "changes_checkout": False, "network_access": False,
                  "runs_project_code": False, "test_provenance_verified": False, "task_completion_verified": False}
        current = collect.review_ref_value(git, reference)
        if check:
            status = ("missing" if current is None else "symbolic" if current == "symbolic" else
                      "matched" if current == candidate else "not_promoted" if current == old else "different")
            guard()
            if collect.review_ref_value(git, reference) != current:
                status = "unconfirmed"
            return {**report, "status": "matched" if status == "matched" else "attention",
                    "read_only": True, "branch_status": status, "promotion_provenance_verified": False}
        require(current == old, "promotion_branch_changed_missing_or_symbolic")
        if old != candidate:
            idle_branch(git, reference)
        guard()
        if approval is None:
            return report
        if old == candidate:
            return {**report, "status": "noop"}
        promote_ref(git, reference, old, candidate, guard)
        guard()
        require(collect.review_ref_value(git, reference) == candidate, "promotion_result_unconfirmed")
        return {**report, "status": "promoted", "promotion_started": True}


def promotion_main(args):
    parser = argparse.ArgumentParser(description="Fast-forward an unoccupied local branch to an exactly tested commit",
                                     allow_abbrev=False)
    parser.add_argument("--promote", required=True, help="Original private test run directory")
    parser.add_argument("--repository", required=True)
    parser.add_argument("--expect-plan", required=True, help="Original test-plan digest; not promotion approval")
    parser.add_argument("--branch", required=True, help="Existing local branch name, never a revision expression")
    parser.add_argument("--expect-old", required=True, help="Exact old branch commit; only fast-forwards are allowed")
    parser.add_argument("--timeout", type=int, default=90)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--apply", action="store_true")
    action.add_argument("--check", action="store_true", help="Inspect original promotion without changing refs")
    parser.add_argument("--accept-plan")
    options = parser.parse_args(args)
    require((options.apply or options.check) == (options.accept_plan is not None), "promotion_requires_exact_approval")
    report = promote_candidate(options.promote, options.repository, options.expect_plan, options.branch,
                               options.expect_old, options.timeout, options.accept_plan, check=options.check)
    print(encoded(report).decode(), end="")
    return 1 if report["status"] == "attention" else 0


def main(args=None):
    args = list(sys.argv[1:] if args is None else args)
    if any(a == "--promote" or a.startswith("--promote=") for a in args):
        return promotion_main(args)
    if any(a == "--verify" or a.startswith("--verify=") for a in args):
        return evidence_main(args)
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False,
        epilog="Saved evidence: --verify RUN --repository DIR --expect-plan SHA256. "
               "Promotion: --promote RUN --repository DIR --expect-plan SHA256 --branch NAME --expect-old OID.")
    parser.add_argument("--repository", required=True)
    parser.add_argument("--commit", required=True, help="Exact full commit ID, never a branch or revision expression")
    parser.add_argument("--spec", required=True, help="Private reviewed JSON test commands; no automatic project discovery")
    parser.add_argument("--output-dir", required=True, help="New private directory outside the repository; retained on failure")
    parser.add_argument("--deadline", type=int, default=600, help="Test phase deadline, 1..3600 seconds; Git staging has its own same-size budget")
    parser.add_argument("--git-snapshot", action="store_true",
                        help="Include independent shallow Git metadata for this commit; no parents, tags, remotes or source configuration")
    parser.add_argument("--run", action="store_true", help="Run trusted project code as you; NOT sandboxed and may access network")
    parser.add_argument("--accept-plan")
    options = parser.parse_args(args)
    require(options.run == (options.accept_plan is not None), "test_run_requires_exact_approval")
    result = execute(options.repository, options.commit, decode(fleet.read_input(options.spec)),
                     options.output_dir, options.deadline, options.accept_plan, git_snapshot=options.git_snapshot)
    print(encoded(result).decode(), end="")
    return 1 if result["status"] == "failed" else 0


def cli():
    def stop(signum, _frame):
        raise fleet.Interrupted(signum)
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, stop)
    try:
        return main()
    except (fleet.Refused, OSError, ValueError, subprocess.SubprocessError, fleet.Interrupted) as exc:
        print(encoded({"schema": SCHEMA, "status": "interrupted" if isinstance(exc, fleet.Interrupted) else "error",
                       "code": str(exc) if isinstance(exc, fleet.Refused) else "test_io_or_process_failure",
                       "run_started": RUN_STARTED, "output_directory": OUTPUT_DIRECTORY,
                       "promotion_started": PROMOTION_STARTED,
                       "task_completion_verified": False}).decode(), end="")
        return 128 + exc.signum if isinstance(exc, fleet.Interrupted) else 2


if __name__ == "__main__":
    sys.exit(cli())
