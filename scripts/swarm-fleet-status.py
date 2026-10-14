#!/usr/bin/env python3
"""Observe original fleet agents, delivery receipts, and assigned Beads exports.

This command does not launch, send, resume, repair journals, or run br. A closed
Bead in an exported snapshot is not proof of task execution or accepted results.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from contextlib import contextmanager
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import secrets
import shlex
import signal
import subprocess
import sys
import threading
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


def transport(known, identity, timeout, deadline, *, runner=None, ssh="/usr/bin/ssh", cancel_event=None, stop_at=None):
    """Keep strict fleet SSH and bound the entire sample, not just each call."""
    end = time.monotonic() + deadline
    if stop_at is not None:
        end = min(end, stop_at)
    def invoke(entry, mode):
        require(cancel_event is None or not cancel_event.is_set(), "operation_cancelled")
        require(time.monotonic() < end, "status_deadline_exceeded")
        command = remote_command(entry, mode)
        def status_runner(argv, _timeout, env):
            remaining = end - time.monotonic()
            require(remaining > 0, "status_deadline_exceeded")
            args = ([*argv[:-1], command], min(timeout, remaining), env)
            if runner is None:
                return fleet.capture(*args, cancel_event=cancel_event)
            return runner(*args)
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


def observe_host(host, attempted, saved_targets, selected, checked, max_age):
    """Keep each host's dependent receipt reads sequential and independently reported."""
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
    return row


def journal_identity(path):
    """Private watch binding, never copied into a status report."""
    if path is None:
        return None
    with fleet.directory_fd(path, private=True) as fd:
        info = os.fstat(fd)
        return {"device": info.st_dev, "inode": info.st_ino,
                "intent_sha256": digest(fleet.read_at(fd, "intent.json"))}


def collect(launch_path, dispatch_path, known, identity, invoke, max_age=300, *, workers=1,
            cancel_event=None, watch_binding=None):
    require(type(max_age) is int and 1 <= max_age <= 86400, "invalid_export_max_age")
    # Library callers with custom transports opt into concurrency explicitly.
    # The CLI's transport is thread-safe and uses four host workers by default.
    require(type(workers) is int and 1 <= workers <= 16, "invalid_status_workers")
    require(watch_binding is None or type(watch_binding) is dict, "invalid_watch_binding")
    cancelled = cancel_event if cancel_event is not None else threading.Event()
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
            guard_lock, invalidated = threading.Lock(), []
            def guard():
                # Directory iteration shares descriptors. Serialize validation,
                # not SSH. A detected mutation stays fatal even if bytes are
                # restored before the last worker finishes or a host catches it.
                with guard_lock:
                    if invalidated:
                        raise invalidated[0]
                    try:
                        launch_guard()
                        work_guard()
                    except BaseException as exc:
                        invalidated.append(exc)
                        cancelled.set()
                        raise
            if watch_binding is not None:
                guard()
                binding = {"launch": journal_identity(launch_path), "dispatch": journal_identity(dispatch_path),
                           "launch_plan_sha256": report["launch_plan_sha256"],
                           "dispatch_plan_sha256": report["dispatch_plan_sha256"]}
                guard()
                require(not watch_binding or watch_binding == binding, "watch_source_changed")
                watch_binding.update(binding)
            def checked(entry, action):
                guard()
                require(not cancelled.is_set(), "operation_cancelled")
                try:
                    return invoke(entry, action)
                finally:
                    guard()
            def observe(index):
                guard()
                require(not cancelled.is_set(), "operation_cancelled")
                attempted, saved_targets = history[index]
                row = observe_host(launch["spec"]["hosts"][index], attempted, saved_targets,
                                   selected, checked, max_age)
                guard()
                return row
            count = len(history)
            report["observation_workers"] = min(workers, count)
            if workers == 1:
                report["hosts"] = [observe(i) for i in range(count)]
            else:
                pool = ThreadPoolExecutor(max_workers=min(workers, count), thread_name_prefix="acfs-status")
                try:
                    pending = {pool.submit(observe, i): i for i in range(count)}
                    rows = [None] * count
                    for future in as_completed(pending):
                        rows[pending[future]] = future.result()
                        guard()
                    report["hosts"] = rows
                except BaseException:
                    cancelled.set()
                    raise
                finally:
                    # Keep both journal locks until every local probe is gone.
                    pool.shutdown(wait=True, cancel_futures=True)
            guard()
            require(not cancelled.is_set(), "operation_cancelled")
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


def observation_states(report):
    """Compare evidence states, not ticking ages, changing nonces, or cached work."""
    states = {}
    for row in report["hosts"]:
        host = row["id"]
        states[(host, "agents", "")] = {k: row["agents"].get(k) for k in
                                         ("status", "code", "verified_live_agents")}
        for delivery in row["deliveries"]:
            states[(host, "delivery", delivery["operation_id"])] = {
                k: delivery.get(k) for k in ("status", "code")}
        work = row["work"]
        states[(host, "export", "")] = {k: work.get(k) for k in ("status", "code")}
        # Stale/unavailable exports cannot carry a last-known closed state into
        # the current sample. The full report retains stale evidence separately.
        items = {i["bead_id"]: i["status"] for i in work["items"]} if work["status"] == "recent" else {}
        for delivery in row["deliveries"]:
            bead = delivery["bead_id"]
            states[(host, "bead", bead)] = items.get(bead, "unobserved")
    return states


def observation_changes(previous, current):
    if previous is None:
        return []
    before, after = observation_states(previous), observation_states(current)
    changes = []
    for key in dict.fromkeys([*after, *before]):
        if before.get(key) != after.get(key):
            host, kind, identity = key
            change = {"host": host, "kind": kind, "before": before.get(key), "after": after.get(key)}
            if identity:
                change["id"] = identity
            changes.append(change)
    return changes


def emit(report, *, jsonl=False):
    if jsonl:
        print(json.dumps(report, sort_keys=True, ensure_ascii=True, separators=(",", ":"), allow_nan=False), flush=True)
    else:
        print(encoded(report).decode(), end="")


def close_output():
    try:
        sys.stdout.close()
    except OSError:
        pass


def watch(args, known, identity, cancelled):
    """Finite, non-overlapping observations; no journal locks are held in delays."""
    stop_at = time.monotonic() + args.watch
    previous, binding, sample, attention_seen = None, {}, 0, False
    interval = args.interval if args.interval is not None else 5
    while time.monotonic() < stop_at:
        invoke = transport(known, identity, args.timeout, args.deadline,
                           cancel_event=cancelled, stop_at=stop_at)
        report, code = collect(args.launch_state, args.dispatch_state, known, identity, invoke,
                               args.export_max_age, workers=args.workers,
                               cancel_event=cancelled, watch_binding=binding)
        sample += 1
        attention_seen |= code != 0
        report["watch"] = {"sample": sample, "duration_seconds": args.watch,
                           "interval_seconds": interval, "attention_seen": attention_seen,
                           "changes": observation_changes(previous, report)}
        emit(report, jsonl=True)
        previous = report
        remaining = stop_at - time.monotonic()
        if remaining <= 0:
            break
        require(not cancelled.wait(min(interval, remaining)), "operation_cancelled")
    require(sample > 0, "watch_no_sample")
    return 1 if attention_seen else 0


def main(arguments=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--launch-state", required=True, help="Original private fleet launch journal")
    parser.add_argument("--dispatch-state", help="Optional original dispatch journal; binds exactly which Beads to observe")
    parser.add_argument("--known-hosts", required=True)
    parser.add_argument("--identity-file", required=True)
    parser.add_argument("--timeout", type=int, default=10, help="Per SSH call deadline, 1..600 seconds")
    parser.add_argument("--deadline", type=int, default=120, help="Total remote observation budget, 1..3600 seconds")
    parser.add_argument("--workers", type=int, default=4, help="Concurrent hosts, 1..16 (default 4); one shared deadline")
    parser.add_argument("--export-max-age", type=int, default=300, help="Recent export threshold, 1..86400 seconds; never proves live DB sync")
    parser.add_argument("--watch", type=int, metavar="SECONDS", help="Observe repeatedly for 1..86400 seconds; flushed JSON Lines")
    parser.add_argument("--interval", type=int, metavar="SECONDS", help="Delay between completed watch samples, 1..3600 (default 5)")
    args = parser.parse_args(arguments)
    require(1 <= args.timeout <= 600 and 1 <= args.deadline <= 3600, "invalid_status_timeout")
    require(1 <= args.workers <= 16, "invalid_status_workers")
    require(args.watch is None or 1 <= args.watch <= 86400, "invalid_watch_duration")
    require(args.interval is None or args.watch is not None and 1 <= args.interval <= 3600,
            "interval_requires_watch_and_1_to_3600_seconds")
    known = fleet.read_input(args.known_hosts, private=False)
    identity = fleet.read_input(args.identity_file)
    require(known and identity, "empty_ssh_trust_input")
    cancelled = threading.Event()
    if args.watch is not None:
        return watch(args, known, identity, cancelled)
    report, code = collect(args.launch_state, args.dispatch_state, known, identity,
                           transport(known, identity, args.timeout, args.deadline, cancel_event=cancelled),
                           args.export_max_age, workers=args.workers, cancel_event=cancelled)
    emit(report)
    return code


def cli():
    def stop(signum, _frame):
        raise fleet.Interrupted(signum)
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, stop)
    try:
        return main()
    except BrokenPipeError:
        # A downstream reader can stop a watch without another write or a
        # traceback. All probes have already been joined before emit().
        close_output()
        return 1
    except (fleet.Refused, OSError, subprocess.SubprocessError, fleet.Interrupted) as exc:
        interrupted = isinstance(exc, fleet.Interrupted)
        report = {"schema": SCHEMA, "status": "interrupted" if interrupted else "error",
                       "code": str(exc) if isinstance(exc, fleet.Refused) else "status_observation_failed",
                       "read_only": True, "starts_agents": False, "sends_prompts": False,
                       "modifies_beads": False, "task_completion_verified": False}
        jsonl = any(arg == "--watch" or arg.startswith("--watch=") for arg in sys.argv[1:])
        try:
            emit(report, jsonl=jsonl)
        except BrokenPipeError:
            close_output()
        return 128 + exc.signum if interrupted else 2


if __name__ == "__main__":
    sys.exit(cli())
