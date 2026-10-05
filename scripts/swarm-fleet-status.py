#!/usr/bin/env python3
"""Observe original fleet agents, delivery receipts, and assigned Beads exports.

This command does not launch, send, resume, repair journals, or run br. A closed
Bead in an exported snapshot is not proof of task execution or accepted results.
"""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import importlib.util
import os
from pathlib import Path
import secrets
import shlex
import signal
import subprocess
import sys
import time

sys.dont_write_bytecode = True
_helper = Path(__file__).absolute().with_name("swarm-fleet-dispatch.py")
if _helper.is_symlink() or not _helper.is_file():
    raise SystemExit("Required trusted sibling swarm-fleet-dispatch.py is unavailable")
_spec = importlib.util.spec_from_file_location("acfs_fleet_dispatch", _helper)
dispatch = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dispatch)
fleet = dispatch.fleet
require, encoded, decode, digest = fleet.require, fleet.encoded, fleet.decode, fleet.digest
SCHEMA = "acfs.swarm-fleet-status.v1"
SNAPSHOT_SCHEMA = "acfs.swarm-fleet-work-snapshot.v1"
WORK_STATES = ("open", "in_progress", "blocked", "deferred", "closed", "tombstone", "pinned", "unknown", "missing")

# Fixed remote observer. No repository code, br database, shell configuration,
# provider, installer, or prompt is executed. Only requested IDs leave the host.
# Retain the whole directory chain to detect replacement as well as in-place
# changes while reading the bounded export. mtime is evidence age, not DB sync.
READ_WORK = r'''import hashlib, json, os, re, stat, sys, time
SCHEMA = "acfs.swarm-fleet-work-snapshot.v1"
def check(ok):
    if not ok:
        raise ValueError()
def unique(pairs):
    result = {}
    for key, value in pairs:
        check(key not in result)
        result[key] = value
    return result
def parse(raw):
    value = json.loads(raw.decode('utf-8'), object_pairs_hook=unique,
                       parse_constant=lambda _: check(False))
    pending, count = [(value, 0)], 0
    while pending:
        item, depth = pending.pop()
        count += 1
        check(depth <= 32 and count <= 50000)
        if type(item) is dict:
            pending.extend((v, depth + 1) for v in item.values())
        elif type(item) is list:
            pending.extend((v, depth + 1) for v in item)
        elif type(item) is str:
            item.encode('utf-8', 'strict')
        elif type(item) is float:
            import math
            check(math.isfinite(item))
    return value
def stamp(info):
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)
fds = []
try:
    check(os.geteuid() != 0 and len(sys.argv) == 2)
    request = parse(sys.argv[1].encode('utf-8'))
    check(type(request) is dict and set(request) == {'repo', 'bead_ids', 'nonce'})
    repo, ids = request['repo'], request['bead_ids']
    check(type(repo) is str and repo.startswith('/') and len(repo) <= 4096
          and re.search(r'[\x00-\x1f\x7f]', repo) is None)
    parts = repo.split('/')[1:]
    check(1 <= len(parts) <= 64 and all(p not in ('', '.', '..') for p in parts))
    check(type(ids) is list and 1 <= len(ids) <= 32
          and all(type(i) is str and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', i) for i in ids)
          and len(set(ids)) == len(ids))
    check(type(request['nonce']) is str and re.fullmatch(r'[a-f0-9]{32}', request['nonce']))
    uid, chain = os.geteuid(), []
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    fds.append(fd)
    for part in parts + ['.beads']:
        child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
        fds.append(child)
        info = os.fstat(child)
        sticky = info.st_uid == 0 and info.st_mode & stat.S_ISVTX
        check(info.st_uid in (0, uid) and (not info.st_mode & 0o022 or sticky))
        chain.append((fd, part, info))
        fd = child
    check(os.fstat(fd).st_uid == uid and not os.fstat(fd).st_mode & 0o022)
    handle = os.open('issues.jsonl', os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    with os.fdopen(handle, 'rb') as stream:
        before = os.fstat(stream.fileno())
        check(stat.S_ISREG(before.st_mode) and before.st_uid == uid
              and before.st_nlink == 1 and not before.st_mode & 0o022
              and before.st_size <= 16777216)
        wanted, found, seen = set(ids), {}, set()
        total, lines, checksum = 0, 0, hashlib.sha256()
        while True:
            raw = stream.readline(1048577)
            if not raw:
                break
            total += len(raw)
            lines += 1
            check(total <= 16777216 and len(raw) <= 1048576 and lines <= 100000)
            checksum.update(raw)
            if not raw.strip():
                continue
            item = parse(raw)
            check(type(item) is dict and type(item.get('id')) is str
                  and 1 <= len(item['id']) <= 128 and item['id'] not in seen)
            seen.add(item['id'])
            if item['id'] in wanted:
                state = item.get('status')
                found[item['id']] = state if type(state) is str and state in (
                    'open', 'in_progress', 'blocked', 'deferred', 'closed', 'tombstone', 'pinned') else 'unknown'
        check(stamp(before) == stamp(os.fstat(stream.fileno())))
        check(stamp(before) == stamp(os.stat('issues.jsonl', dir_fd=fd, follow_symlinks=False)))
        for parent, part, info in chain:
            current = os.stat(part, dir_fd=parent, follow_symlinks=False)
            check(stat.S_ISDIR(current.st_mode) and os.path.samestat(info, current))
    age_ns = time.time_ns() - before.st_mtime_ns
    check(age_ns >= -5000000000)
    result = {'schema': SCHEMA, 'request': request, 'sha256': checksum.hexdigest(),
              'bytes': total, 'records': len(seen), 'age_seconds': max(0, age_ns // 1000000000),
              'items': [{'bead_id': i, 'status': found.get(i, 'missing')} for i in ids]}
    print(json.dumps(result, sort_keys=True, ensure_ascii=True, allow_nan=False))
except (OSError, ValueError, UnicodeError, RecursionError, TypeError):
    sys.exit(2)
finally:
    for fd in reversed(fds):
        os.close(fd)
'''


def remote_command(entry, mode):
    require(mode in ("launch-status", "read-receipt", "query-receipt", "work-snapshot"),
            "status_operation_is_read_only")
    if mode != "work-snapshot":
        return dispatch.remote_command(entry, mode)
    request = entry["snapshot_request"]
    return "exec /usr/bin/python3 -I -c " + shlex.quote(READ_WORK) + " " + shlex.quote(encoded(request).decode())


def transport(known, identity, timeout, deadline, *, runner=fleet.capture, ssh="/usr/bin/ssh"):
    """Keep strict fleet SSH and bound the entire sample, not just each call."""
    end = time.monotonic() + deadline
    def invoke(entry, mode):
        require(time.monotonic() < end, "status_deadline_exceeded")
        command = remote_command(entry, mode)
        def status_runner(argv, _timeout, env):
            remaining = end - time.monotonic()
            require(remaining > 0, "status_deadline_exceeded")
            return runner([*argv[:-1], command], min(timeout, remaining), env)
        with fleet.transport(known, identity, timeout, runner=status_runner, ssh=ssh) as call:
            return call(entry["host"], "reconcile")
    return invoke


@contextmanager
def dispatch_context(path, launch_path, launch, launch_history, launch_records, known, identity):
    if path is None:
        yield None, [], lambda: None
        return
    path = str(Path(os.path.abspath(path)))
    require(path != launch_path and Path(launch_path) not in Path(path).parents,
            "dispatch_state_must_be_outside_launch_journal")
    with fleet.directory_fd(path, private=True) as fd:
        dispatch.lock(fd)
        intent = decode(fleet.read_at(fd, "intent.json"))
        require(type(intent) is dict and set(intent) == {"schema", "plan"}
                and intent["schema"] == dispatch.STATE_SCHEMA and type(intent["plan"]) is dict,
                "invalid_dispatch_intent")
        saved = intent["plan"]
        require(type(saved.get("hosts")) is list and 1 <= len(saved["hosts"]) <= 16
                and type(saved.get("timeout_seconds")) is int and 1 <= saved["timeout_seconds"] <= 600,
                "invalid_dispatch_plan")
        selection = []
        for entry in saved["hosts"]:
            require(type(entry) is dict and type(entry.get("host")) is dict
                    and "id" in entry["host"] and "batch" in entry, "invalid_dispatch_host")
            selection.append({"id": entry["host"]["id"], "batch": entry["batch"]})
        selected = dispatch.select_batches({"schema": dispatch.SPEC_SCHEMA, "hosts": selection}, launch, launch_history)
        context = dispatch.plan_context(launch_path, launch, launch_records, known, identity,
                                        path, saved["timeout_seconds"])
        plan, history, records = dispatch.read_dispatch_history(fd, context, selected)
        def guard():
            fleet.state_unchanged(fd, plan, records)
        guard()
        yield plan, history, guard
        guard()


def work_snapshot(entry, invoke, max_age):
    ids = [d["request"]["bead_id"] for d in entry["deliveries"]]
    request = {"repo": entry["host"]["request"]["repo"], "bead_ids": ids, "nonce": secrets.token_hex(16)}
    code, raw = invoke({**entry, "snapshot_request": request}, "work-snapshot")
    require(type(code) is int and code == 0 and type(raw) is bytes, "work_export_unavailable")
    value = decode(raw)
    require(type(value) is dict and set(value) == {"schema", "request", "sha256", "bytes", "records", "age_seconds", "items"}
            and value["schema"] == SNAPSHOT_SCHEMA and encoded(value["request"]) == encoded(request)
            and fleet.matches(r"[a-f0-9]{64}", value["sha256"])
            and type(value["bytes"]) is int and 0 <= value["bytes"] <= 16777216
            and type(value["records"]) is int and 0 <= value["records"] <= 100000
            and type(value["age_seconds"]) is int and 0 <= value["age_seconds"] <= 2**63
            and type(value["items"]) is list and len(value["items"]) == len(ids), "work_export_invalid")
    for item, bead_id in zip(value["items"], ids):
        require(type(item) is dict and set(item) == {"bead_id", "status"}
                and item["bead_id"] == bead_id and type(item["status"]) is str
                and item["status"] in WORK_STATES, "work_export_items_invalid")
    return {"status": "recent" if value["age_seconds"] <= max_age else "stale",
            "source": "beads_export_not_live_database", "sha256": value["sha256"],
            "bytes": value["bytes"], "records": value["records"], "age_seconds": value["age_seconds"],
            "items": value["items"]}


def collect(launch_path, dispatch_path, known, identity, invoke, max_age=300):
    require(type(max_age) is int and 1 <= max_age <= 86400, "invalid_export_max_age")
    launch_path = str(Path(os.path.abspath(launch_path)))
    report = {"schema": SCHEMA, "status": "observed", "read_only": True, "starts_agents": False,
              "sends_prompts": False, "modifies_beads": False, "task_completion_verified": False,
              "started_at": datetime.now(timezone.utc).isoformat(), "export_max_age_seconds": max_age,
              "hosts": []}
    # Reuse both journal validators. A missing result is not fabricated or
    # repaired, and a different fleet/target cannot be substituted by a journal.
    with dispatch.launch_context(launch_path, known, identity) as (launch, history, records, launch_guard):
        with dispatch_context(dispatch_path, launch_path, launch, history, records, known, identity) as (work, work_history, work_guard):
            report["launch_plan_sha256"] = digest(encoded(launch))
            report["dispatch_plan_sha256"] = digest(encoded(work)) if work else None
            selected = {e["host"]["id"]: (e, h) for e, h in zip(work["hosts"], work_history)} if work else {}
            def guard():
                launch_guard()
                work_guard()
            def checked(entry, action):
                guard()
                try:
                    return invoke(entry, action)
                finally:
                    guard()
            for host, (attempted, saved_targets) in zip(launch["spec"]["hosts"], history):
                guard()
                row = {"id": host["id"], "requested_agents": len(host["request"]["agents"]),
                       "agents": {"status": "not_attempted", "verified_live_agents": 0},
                       "deliveries": [], "work": {"status": "not_selected"}}
                if attempted:
                    live = fleet.remote_result(host, "reconcile", lambda _host, _mode: checked({"host": host}, "launch-status"))
                    if live["status"] == "ready" and saved_targets is not None and live["targets"] != saved_targets:
                        live = {"status": "unconfirmed", "code": "original_targets_changed"}
                    row["agents"] = {"status": "live" if live["status"] == "ready" else "unconfirmed",
                                     "code": live["code"], "verified_live_agents": len(host["request"]["agents"]) if live["status"] == "ready" else 0,
                                     "local_result_present": saved_targets is not None}
                if host["id"] in selected:
                    entry, (sent, result_present) = selected[host["id"]]
                    row["local_dispatch_result_present"] = result_present
                    for delivery in entry["deliveries"]:
                        detail = {"slot": delivery["slot"], "bead_id": delivery["request"]["bead_id"],
                                  "operation_id": delivery["request"]["operation_id"], "status": "not_attempted"}
                        if sent:
                            try:
                                dispatch.query_submission(entry, delivery, checked)
                                detail["status"] = "submitted"
                            except (fleet.Refused, OSError, subprocess.SubprocessError) as exc:
                                detail.update(status="unconfirmed", code=str(exc) if isinstance(exc, fleet.Refused) else "remote_unavailable")
                        row["deliveries"].append(detail)
                    row["work"] = {"status": "not_attempted"}
                    if sent:
                        try:
                            row["work"] = work_snapshot(entry, checked, max_age)
                        except (fleet.Refused, OSError, subprocess.SubprocessError) as exc:
                            row["work"] = {"status": "unavailable", "code": str(exc) if isinstance(exc, fleet.Refused) else "remote_unavailable"}
                guard()
                report["hosts"].append(row)
            guard()
    summarize(report)
    report["finished_at"] = datetime.now(timezone.utc).isoformat()
    return report, 0 if report["status"] == "observed" else 1


def summarize(report):
    rows = report["hosts"]
    deliveries = [d for row in rows for d in row["deliveries"]]
    # Zero verified agents means zero confirmed, not proof that no agents exist.
    report["summary"] = {"hosts": len(rows), "requested_agents": sum(r["requested_agents"] for r in rows),
                         "verified_live_agents": sum(r["agents"]["verified_live_agents"] for r in rows),
                         "selected_deliveries": len(deliveries),
                         "confirmed_submissions": sum(d["status"] == "submitted" for d in deliveries),
                         "recent_export_states": {state: 0 for state in WORK_STATES}, "unobserved_work_items": 0}
    counts = report["summary"]["recent_export_states"]
    attention = any(r["agents"]["status"] != "live" for r in rows)
    attention |= any(d["status"] != "submitted" for d in deliveries)
    for row in rows:
        work = row["work"]
        if work["status"] == "recent":
            for item in work["items"]:
                counts[item["status"]] += 1
                attention |= item["status"] in ("blocked", "deferred", "tombstone", "unknown", "missing")
        elif row["deliveries"]:
            report["summary"]["unobserved_work_items"] += len(row["deliveries"])
            attention = True
    report["status"] = "attention" if attention else "observed"


def main(arguments=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--launch-state", required=True, help="Original private fleet launch journal")
    parser.add_argument("--dispatch-state", help="Optional original dispatch journal; binds exactly which Beads to observe")
    parser.add_argument("--known-hosts", required=True)
    parser.add_argument("--identity-file", required=True)
    parser.add_argument("--timeout", type=int, default=10, help="Per SSH call deadline, 1..600 seconds")
    parser.add_argument("--deadline", type=int, default=120, help="Total remote observation budget, 1..3600 seconds")
    parser.add_argument("--export-max-age", type=int, default=300, help="Recent export threshold, 1..86400 seconds; never proves live DB sync")
    args = parser.parse_args(arguments)
    require(1 <= args.timeout <= 600 and 1 <= args.deadline <= 3600, "invalid_status_timeout")
    known = fleet.read_input(args.known_hosts, private=False)
    identity = fleet.read_input(args.identity_file)
    require(known and identity, "empty_ssh_trust_input")
    report, code = collect(args.launch_state, args.dispatch_state, known, identity,
                           transport(known, identity, args.timeout, args.deadline), args.export_max_age)
    print(encoded(report).decode(), end="")
    return code


def cli():
    def stop(signum, _frame):
        raise fleet.Interrupted(signum)
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, stop)
    try:
        return main()
    except (fleet.Refused, OSError, subprocess.SubprocessError, fleet.Interrupted) as exc:
        interrupted = isinstance(exc, fleet.Interrupted)
        print(encoded({"schema": SCHEMA, "status": "interrupted" if interrupted else "error",
                       "code": str(exc) if isinstance(exc, fleet.Refused) else "status_observation_failed",
                       "read_only": True, "starts_agents": False, "sends_prompts": False,
                       "modifies_beads": False, "task_completion_verified": False}).decode(), end="")
        return 128 + exc.signum if interrupted else 2


if __name__ == "__main__":
    sys.exit(cli())
