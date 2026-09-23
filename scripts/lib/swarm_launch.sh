#!/usr/bin/env bash
# Explicit native-agent startup. The swarm planner remains read-only.
set -euo pipefail
command -v python3 >/dev/null 2>&1 || { echo 'Error: python3 is required' >&2; exit 2; }
exec python3 - "${BASH_SOURCE[0]}" "$@" <<'PY'
"""Admission-checked NTM startup with a create-only, never-relaunch receipt."""
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

RUNTIME = Path(sys.argv.pop(1)).resolve(strict=True)
SCHEMA = "acfs.swarm-launch.v1"
LIMIT = 1024 * 1024
FORMAT = "\t".join(("#{session_name}", "#{session_id}", "#{session_created}",
    "#{pane_id}", "#{pane_pid}", "#{pid}", "#{pane_current_path}",
    "#{pane_dead}", "#{pane_current_command}"))


class LaunchError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise LaunchError(message)


def encode(value):
    return (json.dumps(value, sort_keys=True, ensure_ascii=True, indent=2, allow_nan=False) + "\n").encode()


def parse(data):
    def pairs(values):
        result = {}
        for key, value in values:
            require(key not in result, "Duplicate JSON field.")
            result[key] = value
        return result
    try:
        require(len(data) <= LIMIT, "Command output exceeds 1 MiB.")
        value = json.loads(data, object_pairs_hook=pairs,
            parse_constant=lambda _: (_ for _ in ()).throw(LaunchError("Invalid JSON number.")))
        pending, count = [(value, 0)], 0
        while pending:
            item, depth = pending.pop()
            count += 1
            require(depth <= 32 and count <= 50000, "JSON input is too complex.")
            if isinstance(item, dict):
                pending.extend((v, depth + 1) for v in item.values())
            elif isinstance(item, list):
                pending.extend((v, depth + 1) for v in item)
            elif isinstance(item, float):
                require(math.isfinite(item), "Invalid JSON number.")
        return value
    except (ValueError, UnicodeError, RecursionError):
        raise LaunchError("Invalid JSON response.") from None


def directory(value):
    path = Path(os.path.abspath(value))
    for part in [*reversed(path.parents), path]:
        require(stat.S_ISDIR(part.lstat().st_mode), "Directory contains a symlink or non-directory.")
    require(not any(ord(c) < 32 for c in str(path)), "Control characters in directory path.")
    return path


def binary(name):
    path = shutil.which(name)
    require(path is not None, "Required command is unavailable: " + name)
    return os.path.abspath(path)


def run(argv, repo, timeout=30):
    # No shell, inherited stdin, pane capture, or raw error output in reports.
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        process = subprocess.Popen(argv, cwd=repo, stdin=subprocess.DEVNULL,
            stdout=out, stderr=err, start_new_session=True)
        deadline = time.monotonic() + timeout
        try:
            while process.poll() is None:
                require(time.monotonic() < deadline, "Command timed out; preserve any launch receipt.")
                require(os.fstat(out.fileno()).st_size + os.fstat(err.fileno()).st_size <= LIMIT,
                        "Command output limit exceeded; preserve any launch receipt.")
                time.sleep(0.02)
            require(os.fstat(out.fileno()).st_size + os.fstat(err.fileno()).st_size <= LIMIT,
                    "Command output limit exceeded.")
            out.seek(0)
            return process.returncode, out.read(LIMIT + 1)
        finally:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()


@contextmanager
def receipt_directory(path, lock=False):
    parent = directory(path.parent)
    fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        info = os.fstat(fd)
        require(info.st_uid == os.geteuid() and info.st_mode & 0o022 == 0,
                "Receipt parent must be owned by this user and not group/world writable.")
        if lock:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise LaunchError("Another launch is using this receipt directory; retry after it finishes.") from None
        require(os.path.samestat(parent.stat(), info), "Receipt parent changed.")
        yield fd
    finally:
        os.close(fd)


def read_receipt(fd, name):
    try:
        handle = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    except FileNotFoundError:
        return None
    with os.fdopen(handle, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and info.st_uid == os.geteuid()
                and info.st_mode & 0o077 == 0, "Receipt must be an owned, private, single-link regular file.")
        return parse(stream.read(LIMIT + 1))


def publish(fd, name, value):
    handle = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
    with os.fdopen(handle, "wb") as stream:
        stream.write(encode(value))
        stream.flush()
        os.fsync(stream.fileno())
    os.fsync(fd)


def admission(request):
    planner = RUNTIME.with_name("swarm_plan.sh")
    require(planner.is_file() and not planner.is_symlink(), "The installed swarm planner is unavailable.")
    code, data = run([binary("bash"), str(planner), "--json", "--agents", str(len(request["agents"])),
        "--profile", request["profile"], "--workload", request["workload"]], request["repo"], timeout=90)
    plan = parse(data)
    require(isinstance(plan, dict) and type(plan.get("schema_version")) is int and plan["schema_version"] == 1
            and plan.get("status") in ("pass", "warn", "fail") and type(plan.get("exit_code")) is int
            and plan["exit_code"] == code == {"pass": 0, "warn": 1, "fail": 2}[plan["status"]],
            "Planner did not return a recognized admission decision.")
    count = len(request["agents"])
    require(type(plan.get("requested_agents")) is int and plan["requested_agents"] == count
            and plan.get("workload") == request["workload"], "Planner request identity mismatch.")
    quiesce = plan.get("quiesce_advisory")
    bounds = (plan.get("safe_agents"), plan.get("recommended_agents"))
    require(plan["status"] != "fail" and plan.get("recommendation") in ("launch", "launch_with_review")
            and isinstance(quiesce, dict) and quiesce.get("recommendation") == "proceed"
            and all(type(bound) is int and count <= bound for bound in bounds),
            "Launch admission blocked: reduce the count or resolve pressure; inspect acfs swarm plan.")
    require(plan["status"] == "pass" or request["accept_warnings"],
            "Admission has warnings; inspect acfs swarm plan and explicitly use --accept-warnings to proceed.")
    checks = plan.get("checks")
    require(isinstance(checks, list) and checks and all(isinstance(c, dict)
            and c.get("status") in ("pass", "warn") for c in checks), "Planner checks are incomplete or blocked.")
    return {"status": plan["status"], "recommendation": plan["recommendation"],
            "recommended_agents": bounds[1], "safe_agents": bounds[0],
            "warning_checks": [c.get("id") for c in checks if c["status"] == "warn"]}


def spawn_argv(request):
    counts = Counter(a["agent_type"] for a in request["agents"])
    return ["ntm", "--robot-spawn=" + request["session"], "--spawn-dir=" + request["repo"],
            "--spawn-cc=" + str(counts["claude"]), "--spawn-cod=" + str(counts["codex"]),
            "--spawn-no-user", "--spawn-safety", "--spawn-wait", "--timeout=60s", "--robot-format=json"]


def spawn_response(data, request, dry_run):
    result = parse(data)
    require(isinstance(result, dict) and result.get("success") is True
            and result.get("session") == request["session"] and result.get("working_dir") == request["repo"]
            and result.get("effective_project_key", request["repo"]) == request["repo"]
            and result.get("dry_run", False) is dry_run and not result.get("assignments")
            and not result.get("error"), "NTM did not confirm the exact requested native-agent launch.")
    pressure = result.get("admission")
    require(isinstance(pressure, dict) and pressure.get("decision") == "admit",
            "NTM resource admission is unavailable or does not admit this launch.")
    agents = result.get("would_create" if dry_run else "agents")
    require(isinstance(agents, list) and len(agents) == len(request["agents"])
            and all(isinstance(a, dict) and a.get("type") in ("claude", "codex")
                    and isinstance(a.get("pane"), str) and re.fullmatch(r"[0-9]+\.[0-9]+", a["pane"])
                    and not a.get("error") for a in agents), "NTM returned unexpected agent topology.")
    require(len({a["pane"] for a in agents}) == len(agents)
            and Counter(a["type"] for a in agents) == Counter(a["agent_type"] for a in request["agents"]),
            "NTM returned duplicate panes or the wrong agent mix.")
    require(dry_run or all(a.get("ready") is True for a in agents),
            "Some native agents are not ready; inspect the retained session, do not relaunch.")
    return agents


def observe(tmux, target, request):
    code, data = run([tmux, "display-message", "-p", "-t", target, FORMAT], request["repo"])
    fields = data.decode("utf-8").rstrip("\n").split("\t")
    require(code == 0 and len(fields) == 9, "Unable to verify native agent pane.")
    session, session_id, created, pane, pane_pid, server_pid, cwd, dead, command = fields
    require(session == request["session"] and re.fullmatch(r"\$[0-9]+", session_id)
            and re.fullmatch(r"%[0-9]+", pane) and all(re.fullmatch(r"[0-9]+", v) for v in (created, pane_pid, server_pid))
            and dead == "0" and command in ("claude", "codex"), "Pane is not a live native agent in the requested session.")
    current, repo = Path(cwd).resolve(strict=True), Path(request["repo"])
    require(current == repo or repo in current.parents, "Native agent is in a different repository.")
    return {"session_id": session_id, "session_created": created, "pane": pane,
            "pane_pid": pane_pid, "server_pid": server_pid, "agent_type": command}


def verify_targets(agents, request):
    tmux = binary("tmux")
    by_type = {kind: iter([a for a in agents if a["type"] == kind]) for kind in ("claude", "codex")}
    targets = []
    for slot, assigned in enumerate(request["agents"], 1):
        agent = next(by_type[assigned["agent_type"]])
        identity = observe(tmux, "=" + request["session"] + ":" + agent["pane"], request)
        require(identity["agent_type"] == assigned["agent_type"], "Agent pane type changed during startup.")
        targets.append({**identity, "slot": slot, "agent_name": assigned["agent_name"]})
    require(len({a["pane"] for a in targets}) == len(targets), "Stable agent panes are not distinct.")
    require(len({(a["session_id"], a["session_created"], a["server_pid"]) for a in targets}) == 1,
            "Session changed during native-agent verification.")
    return targets


def reconcile(fd, receipt, request):
    result = read_receipt(fd, receipt.name + ".result.json")
    require(isinstance(result, dict) and result.get("schema") == SCHEMA and result.get("request") == request
            and isinstance(result.get("targets"), list) and len(result["targets"]) == len(request["agents"]),
            "Launch has no complete confirmation. Inspect the session manually; this receipt will never relaunch it.")
    tmux = binary("tmux")
    for index, target in enumerate(result["targets"]):
        require(isinstance(target, dict) and isinstance(target.get("pane"), str)
                and re.fullmatch(r"%[0-9]+", target["pane"])
                and target.get("agent_name") == request["agents"][index]["agent_name"]
                and target.get("agent_type") == request["agents"][index]["agent_type"], "Invalid saved launch target.")
        live = observe(tmux, target["pane"], request)
        require(all(target.get(key) == value for key, value in live.items()),
                "Recorded native agent identity changed; no replacement agent was started.")
    return result["targets"]


def main():
    parser = argparse.ArgumentParser(prog="acfs swarm launch", allow_abbrev=False,
        description="Preview and explicitly start a new NTM native-agent session. May use paid providers. "
                    "Existing receipts only verify saved panes; they NEVER spawn again.")
    parser.add_argument("--repo", required=True)
    parser.add_argument("--session", required=True)
    parser.add_argument("--agent", action="append", required=True, help="Unique NAME:claude or NAME:codex; repeat for each slot")
    parser.add_argument("--receipt", required=True, help="New private intent file in an owned non-writable-by-others directory")
    parser.add_argument("--profile", choices=("balanced", "codex-heavy", "review-heavy", "docs-heavy"), default="balanced")
    parser.add_argument("--workload", choices=("light", "standard", "heavy"), default="standard")
    parser.add_argument("--accept-warnings", action="store_true", help="Allow warning admission only; never wait, scale-down or fail")
    parser.add_argument("--expect-sha256", help="Request hash from preview; required with --launch")
    parser.add_argument("--launch", action="store_true", help="Actually start agents; otherwise preview with live admission checks")
    args = parser.parse_args()
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", args.session) and "--" not in args.session, "Invalid new session name.")
    require(1 <= len(args.agent) <= 32, "Request 1 through 32 native agents.")
    agents = []
    for value in args.agent:
        match = re.fullmatch(r"([A-Za-z][A-Za-z0-9_-]{0,63}):(claude|codex)", value)
        require(match is not None, "Use --agent NAME:claude or NAME:codex.")
        agents.append({"agent_name": match[1], "agent_type": match[2]})
    require(len({a["agent_name"].lower() for a in agents}) == len(agents), "Agent names must be distinct.")
    repo = directory(args.repo)
    receipt = Path(os.path.abspath(args.receipt))
    require(not any(ord(c) < 32 for c in str(receipt)), "Invalid receipt path.")
    request = {"repo": str(repo), "session": args.session, "agents": agents, "receipt": str(receipt),
               "profile": args.profile, "workload": args.workload, "accept_warnings": args.accept_warnings}
    review_hash = hashlib.sha256(encode({"schema": SCHEMA, "request": request})).hexdigest()
    require(args.expect_sha256 is None or args.expect_sha256 == review_hash, "Launch request changed; preview again.")
    require(not args.launch or args.expect_sha256 == review_hash, "Preview first and supply --expect-sha256 with --launch.")
    report = {"schema": SCHEMA, "status": "preview", "request": request, "review_sha256": review_hash,
              "starts_agents": False, "work_dispatched": False, "authentication_verified": False,
              "agent_mail_registered": False,
              "note": "Agent names are intended packet identities, not proof of Agent Mail registration. "
                      "NTM uses its configured agent commands/models and may start its normal session monitor. "
                      "No work prompts, Beads claims, file reservations, interrupts or cleanup are requested."}
    with receipt_directory(receipt, lock=args.launch) as fd:
        saved = read_receipt(fd, receipt.name)
        if saved is not None:
            require(isinstance(saved, dict) and saved.get("schema") == SCHEMA and saved.get("request") == request,
                    "Receipt belongs to another launch; it was not changed.")
            report["reconciled_only"] = True
            try:
                report["targets"] = reconcile(fd, receipt, request)
                report["status"] = "ready"
            except (LaunchError, OSError, UnicodeError) as exc:
                report.update(status="unconfirmed", error=str(exc) if isinstance(exc, LaunchError) else "Unable to verify saved agents.")
        else:
            require(read_receipt(fd, receipt.name + ".result.json") is None, "Result path already exists; it was not changed.")
            report["admission"] = admission(request)
            argv = spawn_argv(request)
            ntm = binary("ntm")
            binary("tmux")
            code, data = run([ntm, *argv[1:], "--dry-run"], repo, timeout=90)
            require(code == 0, "NTM launch preview failed; no launch receipt was created.")
            spawn_response(data, request, True)
            report["ntm_argv"] = argv
            if not args.launch:
                command = ["acfs", "swarm", "launch", "--repo", str(repo), "--session", args.session,
                           "--receipt", str(receipt), "--profile", args.profile, "--workload", args.workload]
                for agent in args.agent:
                    command.extend(("--agent", agent))
                if args.accept_warnings:
                    command.append("--accept-warnings")
                report["launch_command"] = shlex.join([*command, "--expect-sha256", review_hash, "--launch"])
            else:
                # Durable create-only intent precedes the FIRST lifecycle mutation.
                # A lost response, interruption or malformed result never permits retrying spawn.
                publish(fd, receipt.name, {"schema": SCHEMA, "request": request})
                report.update(status="unconfirmed", starts_agents=True, reconciled_only=False)
                try:
                    code, data = run([ntm, *argv[1:]], repo, timeout=120)
                    require(code == 0, "NTM launch did not complete; inspect the retained session.")
                    targets = verify_targets(spawn_response(data, request, False), request)
                    publish(fd, receipt.name + ".result.json", {"schema": SCHEMA, "request": request, "targets": targets})
                    report.update(status="ready", targets=targets)
                except (LaunchError, OSError, UnicodeError, KeyboardInterrupt) as exc:
                    report["error"] = str(exc) if isinstance(exc, LaunchError) else "Launch interrupted; inspect the retained session."
    if report.get("targets"):
        report["preparation_targets"] = [str(t["slot"]) + ":" + t["agent_name"] + ":" + t["agent_type"] + ":" + t["pane"]
                                         for t in report["targets"]]
    report["recovery"] = "Keep this receipt and its result file. Repeat the identical command only to verify saved agents. " \
                         "Do not delete receipts or change the receipt path to retry an uncertain launch."
    print(encode(report).decode(), end="")
    return 1 if report["status"] == "unconfirmed" else 0


def cancelled(signum, frame):
    raise KeyboardInterrupt


for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
    signal.signal(sig, cancelled)
try:
    sys.exit(main())
except (LaunchError, OSError, UnicodeError, KeyboardInterrupt) as exc:
    print(encode({"schema": SCHEMA, "status": "error", "error": str(exc) if isinstance(exc, LaunchError)
                  else "Launch unavailable or interrupted; retain any receipt and inspect the session before retrying."}).decode(), end="")
    sys.exit(2)
PY
