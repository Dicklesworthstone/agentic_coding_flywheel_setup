#!/usr/bin/env python3
"""Explicitly adopt observed native panes after an unconfirmed ACFS launch.

This is not evidence that the original spawn succeeded. The operator approves
one exact observed topology. This command never invokes NTM or starts, stops,
interrupts, or sends input to an agent. Existing results are never replaced.
"""
import argparse
from collections import Counter
from contextlib import contextmanager
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time

SCHEMA = "acfs.swarm-launch.v1"
RECOVERY_SCHEMA = "acfs.swarm-launch-recovery.v1"
LIMIT = 1024 * 1024
FORMAT = "\t".join(("#{session_name}", "#{session_id}", "#{session_created}",
    "#{pane_id}", "#{pane_pid}", "#{pid}", "#{pane_current_path}",
    "#{pane_dead}", "#{pane_current_command}", "#{window_index}", "#{pane_index}"))
PROFILES = ("balanced", "codex-heavy", "review-heavy", "docs-heavy")
WORKLOADS = ("light", "standard", "heavy")


class RecoveryError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise RecoveryError(message)


def encode(value):
    return (json.dumps(value, sort_keys=True, ensure_ascii=True, indent=2,
                       allow_nan=False) + "\n").encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def parse(data):
    def pairs(values):
        result = {}
        for key, value in values:
            require(key not in result, "Duplicate JSON field.")
            result[key] = value
        return result
    try:
        require(len(data) <= LIMIT, "Input exceeds 1 MiB.")
        value = json.loads(data.decode("utf-8"), object_pairs_hook=pairs,
            parse_constant=lambda _: (_ for _ in ()).throw(RecoveryError("Invalid JSON number.")))
        pending, count = [(value, 0)], 0
        while pending:
            item, depth = pending.pop()
            count += 1
            require(depth <= 32 and count <= 50000, "JSON input is too complex.")
            if isinstance(item, dict):
                pending.extend((v, depth + 1) for v in item.values())
                pending.extend((k, depth + 1) for k in item)
            elif isinstance(item, list):
                pending.extend((v, depth + 1) for v in item)
            elif isinstance(item, float):
                require(math.isfinite(item), "Invalid JSON number.")
            elif isinstance(item, str):
                require(not any(0xD800 <= ord(c) <= 0xDFFF for c in item), "Invalid JSON Unicode.")
        return value
    except (ValueError, UnicodeError, RecursionError):
        raise RecoveryError("Invalid JSON input.") from None


def clean_path(value):
    require(isinstance(value, str) and os.path.isabs(value)
            and not any(ord(c) < 32 or ord(c) == 127 for c in value), "Invalid absolute path.")
    path = Path(os.path.abspath(value))
    require(str(path) == value, "Path must be canonical and absolute.")
    return path


def directory(path):
    for part in [*reversed(path.parents), path]:
        require(stat.S_ISDIR(part.lstat().st_mode), "Directory contains a symlink or non-directory.")
    return path


@contextmanager
def locked_parent(receipt):
    parent = directory(receipt.parent)
    fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        info = os.fstat(fd)
        require(info.st_uid == os.geteuid() and info.st_mode & 0o022 == 0,
                "Receipt parent must be owned by this user and not writable by others.")
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RecoveryError("Another launch or recovery holds this receipt directory.") from None
        require(os.path.samestat(parent.stat(), info), "Receipt parent changed.")
        yield fd, info
    finally:
        os.close(fd)


def read_private(fd, name):
    handle = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    with os.fdopen(handle, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
                and info.st_uid == os.geteuid() and info.st_mode & 0o077 == 0,
                "Intent must be an owned, private, single-link regular file.")
        data = stream.read(LIMIT + 1)
    require(len(data) <= LIMIT, "Intent exceeds 1 MiB.")
    return data, info


def no_result(fd, name):
    try:
        os.stat(name, dir_fd=fd, follow_symlinks=False)
    except FileNotFoundError:
        return
    raise RecoveryError("A result path already exists. Preserve it and use ordinary launch reconciliation; recovery will not replace it.")


def validate_request(intent, receipt):
    require(isinstance(intent, dict) and intent.get("schema") == SCHEMA,
            "A saved launch intent is required. Recovery never invents a launch request.")
    request = intent.get("request")
    require(isinstance(request, dict) and set(request) == {
        "repo", "session", "agents", "receipt", "profile", "workload", "accept_warnings"},
        "Invalid saved launch request.")
    require(request["receipt"] == str(receipt), "Intent belongs to a different receipt path.")
    directory(clean_path(request["repo"]))
    require(isinstance(request["session"], str)
            and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", request["session"])
            and "--" not in request["session"]
            and request["profile"] in PROFILES and request["workload"] in WORKLOADS
            and type(request["accept_warnings"]) is bool, "Invalid saved launch options.")
    agents = request["agents"]
    require(isinstance(agents, list) and 1 <= len(agents) <= 32
            and all(isinstance(a, dict) and set(a) == {"agent_name", "agent_type"}
                and isinstance(a["agent_name"], str)
                and re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{0,63}", a["agent_name"])
                and a["agent_type"] in ("claude", "codex") for a in agents)
            and len({a["agent_name"].lower() for a in agents}) == len(agents),
            "Invalid saved native-agent identities.")
    return request


def run(argv, repo, timeout):
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        process = subprocess.Popen(argv, cwd=repo, stdin=subprocess.DEVNULL,
            stdout=out, stderr=err, start_new_session=True)
        deadline = time.monotonic() + timeout
        try:
            while process.poll() is None:
                require(time.monotonic() < deadline, "Pane observation timed out.")
                require(os.fstat(out.fileno()).st_size + os.fstat(err.fileno()).st_size <= LIMIT,
                        "Pane observation exceeds 1 MiB.")
                time.sleep(0.02)
            require(os.fstat(out.fileno()).st_size + os.fstat(err.fileno()).st_size <= LIMIT,
                    "Pane observation exceeds 1 MiB.")
            out.seek(0)
            require(process.returncode == 0, "Unable to observe the exact saved session.")
            return out.read(LIMIT + 1)
        finally:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()


def observe(request, timeout):
    tmux = shutil.which("tmux")
    require(tmux is not None, "tmux is unavailable.")
    data = run([os.path.abspath(tmux), "list-panes", "-s", "-t",
                "=" + request["session"], "-F", FORMAT], request["repo"], timeout)
    rows = data.decode("utf-8").splitlines()
    require(len(rows) == len(request["agents"]), "Observed pane count does not match the saved launch.")
    panes = []
    for row in rows:
        fields = row.split("\t")
        require(len(fields) == 11, "Unrecognized pane observation.")
        session, sid, created, pane, pid, server, cwd, dead, kind, window, index = fields
        require(session == request["session"] and re.fullmatch(r"\$[0-9]+", sid)
                and re.fullmatch(r"%[0-9]+", pane)
                and all(re.fullmatch(r"[0-9]{1,20}", v) for v in (created, pid, server, window, index))
                and int(pid) > 0 and int(server) > 0 and int(created) > 0
                and dead == "0" and kind in ("claude", "codex"),
                "Every observed pane must be a live native agent in the saved session.")
        current, repo = clean_path(cwd).resolve(strict=True), Path(request["repo"])
        require(current == repo or repo in current.parents, "A native pane is outside the saved repository.")
        panes.append({"session_id": sid, "session_created": created, "pane": pane,
            "pane_pid": pid, "server_pid": server, "agent_type": kind,
            "position": (int(window), int(index))})
    require(len({p["pane"] for p in panes}) == len(panes)
            and len({p["position"] for p in panes}) == len(panes)
            and len({p["pane_pid"] for p in panes}) == len(panes), "Observed panes are not distinct.")
    require(len({(p["session_id"], p["session_created"], p["server_pid"]) for p in panes}) == 1,
            "Observed panes do not belong to one stable session.")
    require(Counter(p["agent_type"] for p in panes)
            == Counter(a["agent_type"] for a in request["agents"]), "Observed native-agent mix changed.")
    ordered = sorted(panes, key=lambda p: p["position"])
    by_type = {kind: iter([p for p in ordered if p["agent_type"] == kind]) for kind in ("claude", "codex")}
    targets = []
    for slot, agent in enumerate(request["agents"], 1):
        pane = next(by_type[agent["agent_type"]]).copy()
        pane.pop("position")
        targets.append({**pane, "slot": slot, "agent_name": agent["agent_name"]})
    return targets


def publish(fd, name, value):
    # O_EXCL is intentional. Even a partial result from an interrupted writer
    # remains evidence; no recovery path truncates, replaces, or deletes it.
    handle = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                     0o600, dir_fd=fd)
    with os.fdopen(handle, "wb") as stream:
        stream.write(encode(value))
        stream.flush()
        os.fsync(stream.fileno())
    os.fsync(fd)


def main(arguments=None):
    parser = argparse.ArgumentParser(prog="acfs swarm launch --recover", allow_abbrev=False,
        description="Recover an unconfirmed launch by explicitly adopting its observed native panes. "
                    "Preview first. Never launches agents, sends work, or replaces an existing result.")
    parser.add_argument("--receipt", required=True, help="Existing private launch intent, not its result")
    parser.add_argument("--adopt", action="store_true", help="Create the missing result for the exact reviewed topology")
    parser.add_argument("--expect-sha256", help="Recovery digest from this command's preview, not the original launch digest")
    parser.add_argument("--timeout", type=int, choices=range(1, 31), default=10, metavar="1..30")
    args = parser.parse_args(arguments)
    require(not args.adopt or args.expect_sha256 is not None, "Preview recovery first, then use --adopt --expect-sha256.")
    receipt = clean_path(os.path.abspath(args.receipt))
    result_name = receipt.name + ".result.json"
    with locked_parent(receipt) as (fd, parent_info):
        raw, intent_info = read_private(fd, receipt.name)
        request = validate_request(parse(raw), receipt)
        no_result(fd, result_name)
        targets = observe(request, args.timeout)
        approval = {"schema": RECOVERY_SCHEMA, "intent_sha256": digest(raw),
            "request": request, "targets": targets,
            "policy_sha256": digest(Path(__file__).read_bytes())}
        review_hash = digest(encode(approval))
        require(args.expect_sha256 is None or args.expect_sha256 == review_hash,
                "Recovery request or native pane identities changed; preview recovery again.")
        report = {"schema": RECOVERY_SCHEMA, "status": "preview", "receipt": str(receipt),
            "review_sha256": review_hash, "targets": targets, "starts_agents": False,
            "work_dispatched": False, "agent_mail_registered": False,
            "original_launch_verified": False, "result_created": False,
            "note": "Approval adopts these current native panes, not proof of the original spawn. "
                    "Names are intended packet identities, not verified Agent Mail registrations."}
        if not args.adopt:
            report["adopt_command"] = shlex.join(["acfs", "swarm", "launch", "--recover",
                "--receipt", str(receipt), "--timeout", str(args.timeout),
                "--adopt", "--expect-sha256", review_hash])
        else:
            require(observe(request, args.timeout) == targets, "Native pane identities changed during recovery.")
            current, current_info = read_private(fd, receipt.name)
            require(current == raw and os.path.samestat(current_info, intent_info), "Launch intent changed during recovery.")
            directory(receipt.parent)
            require(os.path.samestat(receipt.parent.stat(), parent_info), "Receipt parent changed during recovery.")
            no_result(fd, result_name)
            publish(fd, result_name, {"schema": SCHEMA, "request": request, "targets": targets,
                "recovery": {"schema": RECOVERY_SCHEMA, "review_sha256": review_hash,
                    "intent_sha256": digest(raw), "original_launch_verified": False,
                    "adopted_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}})
            report.update(status="ready", result_created=True)
            try:
                require(observe(request, args.timeout) == targets, "Native panes changed after result publication.")
            except (RecoveryError, OSError, UnicodeError) as exc:
                report.update(status="unconfirmed", error=str(exc) if isinstance(exc, RecoveryError)
                              else "Unable to recheck native panes. Preserve the published result.")
        report["recovery"] = "Preserve the launch intent and result. Use ordinary launch reconciliation " \
                             "before preparing work. Never remove receipts to force a duplicate launch."
    print(encode(report).decode(), end="")
    return 1 if report["status"] == "unconfirmed" else 0


def cli(arguments=None):
    try:
        return main(arguments)
    except (RecoveryError, OSError, UnicodeError) as exc:
        print(encode({"schema": RECOVERY_SCHEMA, "status": "error", "starts_agents": False,
            "work_dispatched": False, "error": str(exc) if isinstance(exc, RecoveryError)
            else "Recovery unavailable. Preserve the intent and any result; no agent was started."}).decode(), end="")
        return 2
    except KeyboardInterrupt:
        print(encode({"schema": RECOVERY_SCHEMA, "status": "interrupted", "starts_agents": False,
            "work_dispatched": False, "error": "Recovery interrupted. Preserve the intent and any result."}).decode(), end="")
        return 130


if __name__ == "__main__":
    def cancelled(signum, frame):
        raise KeyboardInterrupt
    for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, cancelled)
    sys.exit(cli())
