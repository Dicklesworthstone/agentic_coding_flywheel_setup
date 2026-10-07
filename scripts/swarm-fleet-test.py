#!/usr/bin/env python3
"""Run explicitly reviewed tests against an exact commit in a fresh tree snapshot.

Preview never executes tests or writes files. --run executes trusted project code
as the current user: the separate snapshot and clean environment are NOT a sandbox.
No commands, dependencies, credentials or permissions are inferred from the project.
"""
import argparse
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
MAX_TREE_BYTES = 256 * 1024 * 1024
MAX_BLOB_BYTES = 8 * 1024 * 1024
MAX_LOG_BYTES = 8 * 1024 * 1024
RUN_STARTED = False
OUTPUT_DIRECTORY = None


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


def execute(repository, commit, spec, output, timeout=600, approval=None):
    global RUN_STARTED, OUTPUT_DIRECTORY
    RUN_STARTED, OUTPUT_DIRECTORY = False, None
    require(sys.platform == "linux" and os.getuid() == os.geteuid() and os.geteuid() != 0
            and not os.environ.get("SUDO_USER"), "test_as_repository_owner_without_sudo")
    require(type(timeout) is int and 1 <= timeout <= 3600, "invalid_test_deadline")
    require(approval is None or fleet.matches(r"[0-9a-f]{64}", approval), "invalid_test_approval")
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
            require(workspace_matches(workspace, entries, destination["object_format"]), "test_snapshot_mismatch")
            env = {"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8", "CI": "true",
                   **spec["environment"], "HOME": str(output / "home"), "TMPDIR": str(output / "tmp"),
                   "XDG_CONFIG_HOME": str(output / "home/config"), "XDG_CACHE_HOME": str(output / "home/cache"),
                   "XDG_DATA_HOME": str(output / "home/data")}
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
                unchanged = workspace_matches(workspace, entries, destination["object_format"])
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


def main(args=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--commit", required=True, help="Exact full commit ID, never a branch or revision expression")
    parser.add_argument("--spec", required=True, help="Private reviewed JSON test commands; no automatic project discovery")
    parser.add_argument("--output-dir", required=True, help="New private directory outside the repository; retained on failure")
    parser.add_argument("--deadline", type=int, default=600, help="Test phase deadline, 1..3600 seconds; Git staging has its own same-size budget")
    parser.add_argument("--run", action="store_true", help="Run trusted project code as you; NOT sandboxed and may access network")
    parser.add_argument("--accept-plan")
    options = parser.parse_args(args)
    require(options.run == (options.accept_plan is not None), "test_run_requires_exact_approval")
    result = execute(options.repository, options.commit, decode(fleet.read_input(options.spec)),
                     options.output_dir, options.deadline, options.accept_plan)
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
                       "task_completion_verified": False}).decode(), end="")
        return 128 + exc.signum if isinstance(exc, fleet.Interrupted) else 2


if __name__ == "__main__":
    sys.exit(cli())
