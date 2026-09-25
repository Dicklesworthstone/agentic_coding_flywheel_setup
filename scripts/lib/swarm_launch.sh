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
DISPATCH_SCHEMA = "acfs.swarm-dispatch.v1"
PACKET_SCHEMA = "acfs.packet-delivery.v1"
BATCH_SCHEMA = "acfs.packet-delivery-batch.v1"
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


def check_target(target, request):
    live = observe(binary("tmux"), target["pane"], request)
    require(all(target.get(key) == value for key, value in live.items()),
            "Recorded native agent identity changed; no replacement agent was started.")


def reconcile(fd, receipt, request, verify_live=True):
    result = read_receipt(fd, receipt.name + ".result.json")
    require(isinstance(result, dict) and result.get("schema") == SCHEMA and result.get("request") == request
            and isinstance(result.get("targets"), list) and len(result["targets"]) == len(request["agents"]),
            "Launch has no complete confirmation. Inspect the session manually; this receipt will never relaunch it.")
    require(all(isinstance(t, dict) and type(t.get("slot")) is int and t["slot"] == i
                and isinstance(t.get("pane"), str) for i, t in enumerate(result["targets"], 1))
            and len({t["pane"] for t in result["targets"]}) == len(result["targets"]),
            "Saved launch slots or panes are not distinct and ordered.")
    for index, target in enumerate(result["targets"]):
        require(isinstance(target, dict) and isinstance(target.get("pane"), str)
                and re.fullmatch(r"%[0-9]+", target["pane"])
                and target.get("agent_name") == request["agents"][index]["agent_name"]
                and target.get("agent_type") == request["agents"][index]["agent_type"]
                and isinstance(target.get("session_id"), str) and re.fullmatch(r"\$[0-9]+", target["session_id"])
                and all(isinstance(target.get(key), str) and re.fullmatch(r"[0-9]+", target[key])
                        for key in ("session_created", "pane_pid", "server_pid")), "Invalid saved launch target.")
        if verify_live:
            check_target(target, request)
    require(len({(t["session_id"], t["session_created"], t["server_pid"]) for t in result["targets"]}) == 1,
            "Saved targets do not belong to one launch session.")
    return result["targets"]


def saved_request(fd, receipt):
    """Recover only an existing launch, never reconstruct authority from pane names."""
    saved = read_receipt(fd, receipt.name)
    require(isinstance(saved, dict) and saved.get("schema") == SCHEMA,
            "A private launch intent and complete result are required; launch will not be retried.")
    request = saved.get("request")
    require(isinstance(request, dict) and set(request) == {
        "repo", "session", "agents", "receipt", "profile", "workload", "accept_warnings"},
        "Invalid saved launch request.")
    require(isinstance(request["repo"], str) and os.path.isabs(request["repo"])
            and request["receipt"] == str(receipt)
            and isinstance(request["session"], str)
            and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", request["session"])
            and "--" not in request["session"]
            and request["profile"] in ("balanced", "codex-heavy", "review-heavy", "docs-heavy")
            and request["workload"] in ("light", "standard", "heavy")
            and type(request["accept_warnings"]) is bool,
            "Saved launch repository, receipt or options are invalid.")
    require(str(directory(request["repo"])) == request["repo"], "Saved repository path is not canonical.")
    agents = request["agents"]
    require(isinstance(agents, list) and 1 <= len(agents) <= 32
            and all(isinstance(a, dict) and set(a) == {"agent_name", "agent_type"}
                    and isinstance(a["agent_name"], str)
                    and re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{0,63}", a["agent_name"])
                    and a["agent_type"] in ("claude", "codex") for a in agents)
            and len({a["agent_name"].lower() for a in agents}) == len(agents),
            "Saved launch agent identities are invalid.")
    return request


def read_input(path):
    path = Path(os.path.abspath(path))
    directory(path.parent)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1, "Input must be a single-link regular file.")
        data = stream.read(LIMIT + 1)
    require(len(data) <= LIMIT, "Input exceeds 1 MiB.")
    return data


def preparation_main(arguments):
    parser = argparse.ArgumentParser(prog="acfs swarm launch --prepare-batch", allow_abbrev=False,
        description="Prepare scoped work for an already-confirmed launch. Rechecks saved native panes; "
                    "never launches agents or sends work. Review and delivery remain separate.")
    parser.add_argument("output", help="New private handoff directory")
    parser.add_argument("--receipt", required=True, help="Existing acfs swarm launch intent (not its result file)")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--scopes-file", help="Select work using the installed scoped allocator")
    source.add_argument("--assignments", help="Prepare an existing explicit-scopes assignment report")
    parser.add_argument("--identity", action="append", required=True,
                        help="SLOT:AGENT_MAIL_NAME; supply every launched slot, including potentially idle ones")
    roles = parser.add_mutually_exclusive_group()
    roles.add_argument("--roles")
    roles.add_argument("--profile", choices=("balanced", "codex-heavy", "review-heavy", "docs-heavy"))
    parser.add_argument("--ready-file")
    parser.add_argument("--triage-file")
    parser.add_argument("--beads-file")
    parser.add_argument("--no-live-context", action="store_true")
    args = parser.parse_args(arguments)
    require(args.scopes_file is not None or all(value is None for value in
            (args.roles, args.profile, args.ready_file, args.triage_file)),
            "Selection options require --scopes-file, not saved --assignments.")
    receipt = Path(os.path.abspath(args.receipt))
    output = Path(os.path.abspath(args.output))
    directory(output.parent)
    require(not os.path.lexists(output), "Output directory already exists; no files were changed.")
    preparer = RUNTIME.with_name("swarm_packet.sh")
    require(preparer.is_file() and not preparer.is_symlink(), "The installed work-packet preparer is unavailable.")
    identities = {}
    for value in args.identity:
        match = re.fullmatch(r"([0-9]{1,2}):([A-Za-z][A-Za-z0-9_-]{0,63})", value)
        require(match is not None and 1 <= int(match[1]) <= 32, "Use --identity SLOT:AGENT_MAIL_NAME.")
        slot, name = int(match[1]), match[2]
        require(slot not in identities and name.lower() not in {n.lower() for n in identities.values()},
                "Identity slots and Agent Mail names must be distinct.")
        identities[slot] = name
    # Snapshot each input before checking the session. Saved assignments can
    # contain idle holes; their selected slot IDs, not list positions, bind panes.
    inputs = {}
    for option in ("scopes_file", "assignments", "ready_file", "triage_file", "beads_file"):
        value = getattr(args, option)
        if value is not None:
            inputs[option] = read_input(value)
    with receipt_directory(receipt, lock=True) as fd:
        request = saved_request(fd, receipt)
        require(set(identities) == set(range(1, len(request["agents"]) + 1)),
                "Supply exactly one --identity for every recorded launch slot.")
        targets = reconcile(fd, receipt, request)
        selected = {t["slot"] for t in targets}
        if args.assignments is not None:
            assignments = parse(inputs["assignments"])
            require(isinstance(assignments, dict) and isinstance(assignments.get("assignments"), list),
                    "Invalid assignment report.")
            slots = [a.get("slot") if isinstance(a, dict) else None for a in assignments["assignments"]]
            require(slots and all(type(s) is int and s in selected for s in slots)
                    and len(set(slots)) == len(slots), "Assignments reference unknown or duplicate launch slots.")
            selected = set(slots)
        with tempfile.TemporaryDirectory(prefix="acfs-launch-handoff-") as scratch:
            argv = [binary("bash"), str(preparer), "--prepare-batch", str(output),
                    "--repo", request["repo"], "--session", request["session"]]
            for option, data in inputs.items():
                path = Path(scratch) / (option + ".json")
                path.write_bytes(data)
                argv.extend(("--" + option.replace("_", "-"), str(path)))
            for target in targets:
                if target["slot"] in selected:
                    argv.extend(("--target", f'{target["slot"]}:{identities[target["slot"]]}:{target["agent_type"]}:{target["pane"]}'))
            for option in ("roles", "profile"):
                value = getattr(args, option)
                if value is not None:
                    argv.extend(("--" + option, value))
            if args.no_live_context:
                argv.append("--no-live-context")
            code, data = run(argv, request["repo"], timeout=60 + 65 * len(selected))
        result = parse(data)
        require(isinstance(result, dict) and result.get("schema") == "acfs.packet-preparation.v1"
                and (code, result.get("status")) in ((0, "prepared"), (1, "no_work"))
                and result.get("sends_prompt") is False, "Work preparation failed; inspect any retained output directory.")
        if code == 0:
            require(result.get("directory") == str(output), "Preparer returned an unexpected output directory.")
        # If an agent disappeared while collecting context, do not advertise a
        # usable handoff. No prompts have been sent, and existing files stay intact.
        reconcile(fd, receipt, request)
        result["launch"] = {"receipt": str(receipt), "session": request["session"],
            "request_sha256": hashlib.sha256(encode(request)).hexdigest(), "identities_rechecked": True,
            "starts_agents": False, "work_dispatched": False, "agent_mail_registration_verified": False,
            "identity_mapping": [{"slot": t["slot"], "launch_name": t["agent_name"],
                "agent_mail_name": identities[t["slot"]], "agent_type": t["agent_type"], "pane": t["pane"]} for t in targets]}
        if code == 0:
            result["preview_command"] = shlex.join(["acfs", "swarm", "launch", "--dispatch-batch",
                str(output / "batch.json"), "--receipt", str(receipt)])
        print(encode(result).decode(), end="")
        return code


def packet_intent(path, request=None):
    with receipt_directory(path) as fd:
        saved = read_receipt(fd, path.name)
    require(saved is None or (isinstance(saved, dict) and saved.get("schema") == PACKET_SCHEMA
            and isinstance(saved.get("request"), dict) and (request is None or saved["request"] == request)
            and isinstance(saved.get("target"), str)
            and saved["target"]), "Delivery receipt belongs to another packet; it was not changed.")
    return saved


def query_delivery(entry, saved):
    """A known intent NEVER goes back through a send-capable execution path."""
    request, target = entry["request"], saved["target"]
    report = {"schema": PACKET_SCHEMA, "request": request, "receipt": str(entry["receipt"]),
              "status": "unconfirmed", "sends_prompt": False, "reconciled_only": True,
              "agent_execution_verified": False}
    try:
        code, data = run([binary("ntm"), "--robot-send-receipt=" + request["operation_id"],
                          "--robot-format=json"], request["repo"])
        response = parse(data)
        operation = response.get("operation") if isinstance(response, dict) else None
        outcome = response.get("outcome") if isinstance(response, dict) else None
        if (code == 0 and isinstance(response, dict) and response.get("success") is True and response.get("session") == request["session"]
                and isinstance(operation, dict) and operation.get("operation_id") == request["operation_id"]
                and operation.get("payload_sha256") == request["payload_sha256"]
                and type(operation.get("payload_bytes")) is int and operation["payload_bytes"] == request["payload_bytes"]
                and operation.get("status") == "completed" and isinstance(outcome, dict)
                and outcome.get("success") is True and outcome.get("targets") == [target]
                and outcome.get("successful") == [target] and outcome.get("failed") == []
                and operation.get("admissions") == [{"target": target, "state": "submitted"}]):
            report["status"] = "submitted"
    except (LaunchError, OSError, UnicodeError):
        pass
    return report, 0 if report["status"] == "submitted" else 1


def dispatch_preview(batch, request, targets, packet_script):
    raw = read_input(batch)
    spec = parse(raw)
    require(isinstance(spec, dict) and set(spec) == {"schema", "deliveries"}
            and spec["schema"] == BATCH_SCHEMA and isinstance(spec["deliveries"], list)
            and 1 <= len(spec["deliveries"]) <= len(targets), "Expected a nonempty batch for this recorded launch.")
    keys = {"packet", "repo", "session", "pane", "agent_type", "operation_id", "receipt"}
    known_intents = {}
    for item in spec["deliveries"]:
        require(isinstance(item, dict) and set(item) == keys
                and all(isinstance(v, str) and v and "\0" not in v for v in item.values()), "Invalid batch entry.")
        path = Path(os.path.abspath(batch.parent / item["receipt"]))
        known_intents[path] = packet_intent(path)
    code, data = run([binary("bash"), str(packet_script), "--deliver-batch", str(batch)], request["repo"])
    preview = parse(data)
    require(code == 0 and isinstance(preview, dict) and preview.get("schema") == BATCH_SCHEMA
            and preview.get("status") == "preview" and preview.get("sends_prompt") is False
            and isinstance(preview.get("deliveries"), list)
            and len(preview["deliveries"]) == len(spec["deliveries"])
            and preview.get("manifest_sha256") == hashlib.sha256(raw).hexdigest()
            and read_input(batch) == raw, "Batch validation failed or inputs changed; no work was sent.")
    by_pane = {t["pane"]: t for t in targets}
    entries, reviewed, panes = [], [], set()
    for item, detail in zip(spec["deliveries"], preview["deliveries"]):
        require(isinstance(item, dict) and set(item) == keys
                and all(isinstance(v, str) and v and "\0" not in v for v in item.values())
                and isinstance(detail, dict) and isinstance(detail.get("request"), dict), "Invalid batch entry.")
        packet, receipt, repo = (Path(os.path.abspath(batch.parent / item[k])) for k in ("packet", "receipt", "repo"))
        r = detail["request"]
        require(r.get("repo") == str(repo) == request["repo"] and r.get("session") == item["session"] == request["session"]
                and r.get("pane") == item["pane"] and r["pane"] in by_pane and r["pane"] not in panes
                and r.get("agent_type") == item["agent_type"] == by_pane[r["pane"]]["agent_type"]
                and r.get("operation_id") == item["operation_id"] and detail.get("receipt") == str(receipt)
                and all(isinstance(r.get(k), str) and re.fullmatch(r"[a-f0-9]{64}", r[k])
                        for k in ("packet_sha256", "payload_sha256"))
                and type(r.get("payload_bytes")) is int and 1 <= r["payload_bytes"] <= 65536,
                "Batch target does not match the original launch; no work was sent.")
        panes.add(r["pane"])
        entry = {"packet": packet, "receipt": receipt, "request": r, "target": by_pane[r["pane"]]}
        prior, current = known_intents[receipt], packet_intent(receipt, r)
        require(prior is None or (prior["request"] == r and (current is None or current == prior)),
                "Delivery intent changed during validation; preserve it and inspect the recorded submission.")
        entry["saved"] = prior or current
        entries.append(entry)
        reviewed.append({"request": r, "receipt": str(receipt), "packet": str(packet)})
    digest = hashlib.sha256(encode({"schema": BATCH_SCHEMA, "manifest_sha256": hashlib.sha256(raw).hexdigest(),
                                    "deliveries": reviewed})).hexdigest()
    require(preview.get("review_sha256") == digest, "Batch review identity mismatch; no work was sent.")
    return entries, digest


def dispatch_main(arguments):
    parser = argparse.ArgumentParser(prog="acfs swarm launch --dispatch-batch", allow_abbrev=False,
        description="Review and dispatch a batch only to its original launched agents. "
                    "Each new send rechecks launch identity. Existing delivery intents are queried, never resent.")
    parser.add_argument("batch")
    parser.add_argument("--receipt", required=True, help="Original launch intent; never a delivery receipt")
    parser.add_argument("--expect-sha256", help="Combined launch-and-batch hash from this command's preview")
    parser.add_argument("--send", action="store_true", help="May start paid model work; otherwise preview only")
    args = parser.parse_args(arguments)
    receipt, batch = Path(os.path.abspath(args.receipt)), Path(os.path.abspath(args.batch))
    packet_script = RUNTIME.with_name("swarm_packet.sh")
    require(packet_script.is_file() and not packet_script.is_symlink(), "Installed packet delivery is unavailable.")
    with receipt_directory(receipt, lock=args.send) as fd:
        request = saved_request(fd, receipt)
        targets = reconcile(fd, receipt, request, verify_live=False)
        entries, batch_hash = dispatch_preview(batch, request, targets, packet_script)
        review = {"schema": DISPATCH_SCHEMA, "request": request, "targets": targets, "batch_sha256": batch_hash}
        review_hash = hashlib.sha256(encode(review)).hexdigest()
        require(args.expect_sha256 is None or args.expect_sha256 == review_hash,
                "Launch evidence, batch or packet changed since review; preview again.")
        require(not args.send or args.expect_sha256 == review_hash,
                "Preview receipt-checked dispatch first and pass its --expect-sha256 with --send.")
        report = {"schema": DISPATCH_SCHEMA, "status": "preview", "review_sha256": review_hash,
                  "batch_review_sha256": batch_hash, "launch_receipt": str(receipt), "batch": str(batch),
                  "starts_agents": False, "sends_prompt": False, "agent_execution_verified": False,
                  "note": "New submissions can start paid work. Checks are not atomic with NTM; "
                          "do not restart agents during dispatch. No sessions, claims or reservations are created."}
        if not args.send:
            for entry in entries:
                if entry["saved"] is None:
                    check_target(entry["target"], request)
            report["deliveries"] = [{"request": e["request"], "receipt": str(e["receipt"]),
                "slot": e["target"]["slot"], "action": "reconcile_only" if e["saved"] else "submit"} for e in entries]
            report["send_command"] = shlex.join(["acfs", "swarm", "launch", "--dispatch-batch", str(batch),
                "--receipt", str(receipt), "--expect-sha256", review_hash, "--send"])
            print(encode(report).decode(), end="")
            return 0
        results, exit_code = [], 0
        for entry in entries:
            r, target = entry["request"], entry["target"]
            result = {"request": r, "receipt": str(entry["receipt"]), "slot": target["slot"],
                      "status": "not_attempted", "sends_prompt": False, "agent_execution_verified": False}
            if not exit_code:
                send_invoked = False
                try:
                    # A known intent is never sent again even if another process
                    # removes its file after preview. Keep and query the snapshot.
                    saved = entry["saved"] or packet_intent(entry["receipt"], r)
                    if saved is not None:
                        outcome, code = query_delivery(entry, saved)
                    else:
                        check_target(target, request)
                        argv = [binary("bash"), str(packet_script), "--deliver", str(entry["packet"])]
                        for key in ("repo", "session", "pane", "agent_type", "operation_id"):
                            argv.extend(("--" + key.replace("_", "-"), r[key]))
                        argv.extend(("--receipt", str(entry["receipt"]), "--expect-sha256", r["packet_sha256"], "--send"))
                        send_invoked = True
                        code, data = run(argv, request["repo"], timeout=150)
                        outcome = parse(data)
                        require(isinstance(outcome, dict) and outcome.get("schema") == PACKET_SCHEMA
                                and outcome.get("request") == r and outcome.get("receipt") == str(entry["receipt"])
                                and (code, outcome.get("status")) in ((0, "submitted"), (1, "unconfirmed"))
                                and type(outcome.get("sends_prompt")) is bool,
                                "Delivery did not return matching submission evidence; retain its receipt.")
                    result.update(outcome)
                    exit_code = code
                except (LaunchError, OSError, UnicodeError, KeyboardInterrupt) as exc:
                    result.update(status="error", error=str(exc) if isinstance(exc, LaunchError) else "Dispatch interrupted or unavailable.",
                                  submission_may_have_occurred=send_invoked or os.path.lexists(entry["receipt"]))
                    exit_code = 2
            results.append(result)
        report.update(status="stopped" if exit_code else "submitted", deliveries=results,
            sends_prompt=any(r.get("sends_prompt") for r in results),
            submission_may_have_occurred=any(r.get("sends_prompt") or r.get("submission_may_have_occurred") for r in results))
        report["summary"] = {s: sum(r["status"] == s for r in results)
                             for s in ("submitted", "unconfirmed", "error", "not_attempted")}
        report["summary"]["reconciled"] = sum(r.get("reconciled_only") is True for r in results)
        report["recovery"] = "Keep launch and delivery receipts plus unchanged packets and manifest. Repeat this command to " \
                             "query known intents and continue pending entries; never delete receipts to force a resend."
        print(encode(report).decode(), end="")
        return exit_code


def reconcile_main(arguments):
    parser = argparse.ArgumentParser(prog="acfs swarm launch --reconcile", allow_abbrev=False,
        description="Verify an existing launch from its saved receipt only. Never starts agents or sends work.")
    parser.add_argument("--receipt", required=True, help="Existing private launch intent, not its result")
    args = parser.parse_args(arguments)
    receipt = Path(os.path.abspath(args.receipt))
    with receipt_directory(receipt, lock=True) as fd:
        request = saved_request(fd, receipt)
        report = {"schema": SCHEMA, "status": "unconfirmed", "request": request,
            "starts_agents": False, "work_dispatched": False, "reconciled_only": True,
            "authentication_verified": False, "agent_mail_registered": False}
        try:
            saved = read_receipt(fd, receipt.name + ".result.json")
            targets = reconcile(fd, receipt, request)
            require(saved_request(fd, receipt) == request
                    and read_receipt(fd, receipt.name + ".result.json") == saved,
                    "Saved launch evidence changed during reconciliation; inspect the retained files.")
            if "recovery" in saved:
                provenance = saved["recovery"]
                require(isinstance(provenance, dict)
                        and provenance.get("schema") == "acfs.swarm-launch-recovery.v1"
                        and provenance.get("original_launch_verified") is False
                        and all(isinstance(provenance.get(key), str)
                                and re.fullmatch(r"[0-9a-f]{64}", provenance[key])
                                for key in ("review_sha256", "intent_sha256"))
                        and isinstance(provenance.get("adopted_at"), str)
                        and re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z",
                                         provenance["adopted_at"]), "Invalid recovery provenance; retain the result.")
                report["original_launch_verified"] = False
                report["recovery_provenance"] = {key: provenance[key] for key in (
                    "schema", "review_sha256", "intent_sha256", "original_launch_verified", "adopted_at")}
            report.update(status="ready", targets=targets)
        except (LaunchError, OSError, UnicodeError) as exc:
            report["error"] = str(exc) if isinstance(exc, LaunchError) else "Unable to verify saved native agents."
        if report.get("targets"):
            report["preparation_targets"] = [str(t["slot"]) + ":" + t["agent_name"] + ":" + t["agent_type"] + ":" + t["pane"]
                                             for t in report["targets"]]
        if report["status"] == "unconfirmed" and not os.path.lexists(str(receipt) + ".result.json"):
            report["recovery_preview_command"] = shlex.join(["acfs", "swarm", "launch", "--recover", "--receipt", str(receipt)])
        report["recovery"] = "Preserve the intent and any result. Reconciliation never relaunches. " \
                             "A missing result requires a separate, explicitly approved recovery before work handoff."
    print(encode(report).decode(), end="")
    return 0 if report["status"] == "ready" else 1


def main():
    parser = argparse.ArgumentParser(prog="acfs swarm launch", allow_abbrev=False,
        description="Preview and explicitly start a new NTM native-agent session. May use paid providers. "
                    "Existing receipts only verify saved panes; they NEVER spawn again.",
        epilog="Work handoff: acfs swarm launch --prepare-batch DIRECTORY --help; "
               "reviewed dispatch: acfs swarm launch --dispatch-batch BATCH.json --help; "
               "receipt-only status: acfs swarm launch --reconcile --help; "
               "incomplete launch recovery: acfs swarm launch --recover --help")
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
    if sys.argv[1:2] == ["--recover"]:
        helper = RUNTIME.with_name("swarm_launch_recovery.py")
        require(helper.is_file() and not helper.is_symlink(), "The installed launch recovery helper is unavailable.")
        os.execv(sys.executable, [sys.executable, "-B", str(helper), *sys.argv[2:]])
    if sys.argv[1:2] == ["--reconcile"]:
        sys.exit(reconcile_main(sys.argv[2:]))
    if sys.argv[1:2] == ["--dispatch-batch"]:
        sys.exit(dispatch_main(sys.argv[2:]))
    sys.exit(preparation_main(sys.argv[2:]) if sys.argv[1:2] == ["--prepare-batch"] else main())
except (LaunchError, OSError, UnicodeError, KeyboardInterrupt) as exc:
    print(encode({"schema": SCHEMA, "status": "error", "error": str(exc) if isinstance(exc, LaunchError)
                  else "Launch unavailable or interrupted; retain any receipt and inspect the session before retrying."}).decode(), end="")
    sys.exit(2)
PY
