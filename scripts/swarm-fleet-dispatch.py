#!/usr/bin/env python3
"""Dispatch reviewed remote work batches to the original agents of an ACFS fleet.

Run from a complete trusted checkout. Batches and packets must already exist on
their selected hosts. Preview opens SSH connections but sends no work. --send
requires the preview digest and can start paid model work; it never starts agents.
"""
import argparse
from contextlib import contextmanager
import fcntl
import importlib.util
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys

# Use the fleet controller's strict input, journal, transport and process rules.
# No import through PATH, no downloaded helper, and no writes during import.
sys.dont_write_bytecode = True
_helper = Path(__file__).absolute().with_name("swarm-fleet-launch.py")
if _helper.is_symlink() or not _helper.is_file():
    raise SystemExit("Required trusted sibling swarm-fleet-launch.py is unavailable")
_spec = importlib.util.spec_from_file_location("acfs_fleet_launch", _helper)
fleet = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fleet)
require, encoded, decode, digest = fleet.require, fleet.encoded, fleet.decode, fleet.digest
SCHEMA = "acfs.swarm-fleet-dispatch.v1"
SPEC_SCHEMA = "acfs.swarm-fleet-batches.v1"
STATE_SCHEMA = "acfs.swarm-fleet-dispatch-state.v1"
NATIVE_SCHEMA = "acfs.swarm-dispatch.v1"
POLICY = "original-fleet-reviewed-native-batches-v1"
SEND_ATTEMPTED = False

# Fixed read-only remote program, not code supplied by a batch/spec. It snapshots
# an original private native delivery intent without depending on a live pane,
# packet file, or remote batch. JSON and request binding are validated locally.
READ_RECEIPT = r'''import os, stat, sys
try:
    path = sys.argv[1]
    uid = os.geteuid()
    if uid == 0 or not path.startswith('/') or any(p in ('', '.', '..') for p in path.split('/')[1:]):
        raise ValueError()
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.split('/')[1:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
            info = os.fstat(fd)
            sticky = info.st_uid == 0 and info.st_mode & stat.S_ISVTX
            if info.st_uid not in (0, uid) or (info.st_mode & 0o022 and not sticky):
                raise ValueError()
        handle = os.open(path.rsplit('/', 1)[1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
        with os.fdopen(handle, 'rb') as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != uid or info.st_nlink != 1 or info.st_mode & 0o077:
                raise ValueError()
            raw = stream.read(1048577)
            if len(raw) > 1048576:
                raise ValueError()
    finally:
        os.close(fd)
    sys.stdout.buffer.write(raw)
except (OSError, ValueError):
    sys.exit(2)
'''


def lock(fd):
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise fleet.Refused("fleet_operation_in_progress") from None


@contextmanager
def launch_context(path, known, identity):
    path = str(Path(os.path.abspath(path)))
    with fleet.directory_fd(path, private=True) as fd:
        lock(fd)
        intent = decode(fleet.read_at(fd, "intent.json"))
        require(type(intent) is dict and set(intent) == {"schema", "plan"}
                and intent["schema"] == fleet.STATE_SCHEMA, "invalid_launch_intent")
        plan = intent["plan"]
        fleet.validate_plan(plan)
        require(plan["state_directory"] == path, "launch_state_path_mismatch")
        require(plan["known_hosts_sha256"] == digest(known)
                and plan["identity_sha256"] == digest(identity), "launch_transport_trust_mismatch")
        history, records = fleet.read_history(fd, plan)
        def guard():
            fleet.state_unchanged(fd, plan, records)
        guard()
        yield plan, history, records, guard
        guard()


def select_batches(spec, launch, history):
    require(type(spec) is dict and set(spec) == {"schema", "hosts"}
            and spec["schema"] == SPEC_SCHEMA and type(spec["hosts"]) is list
            and 1 <= len(spec["hosts"]) <= 16, "invalid_batch_selection")
    requested = {}
    for item in spec["hosts"]:
        require(type(item) is dict and set(item) == {"id", "batch"}
                and fleet.matches(r"[a-z][a-z0-9_-]{0,63}", item["id"])
                and item["id"] not in requested, "invalid_or_duplicate_batch_host")
        requested[item["id"]] = fleet.absolute_path(item["batch"])
    selected = []
    for host, (attempted, targets) in zip(launch["spec"]["hosts"], history):
        if host["id"] in requested:
            require(attempted and targets is not None, "selected_launch_not_confirmed")
            selected.append({"host": host, "targets": targets, "batch": requested.pop(host["id"])})
    require(not requested, "unknown_batch_host")
    return selected


def remote_command(entry, mode):
    require(mode in ("launch-status", "preview", "send", "read-receipt", "query-receipt"), "invalid_dispatch_operation")
    if mode == "read-receipt":
        path = fleet.absolute_path(entry["delivery"]["receipt"])
        return "exec python3 -I -c " + shlex.quote(READ_RECEIPT) + " " + shlex.quote(path)
    if mode == "query-receipt":
        operation = entry["delivery"]["request"]["operation_id"]
        require(fleet.matches(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", operation), "invalid_operation_id")
        # This branch has no --robot-send, batch, packet payload or fallback.
        return "exec /bin/bash --noprofile --norc -p -c " + shlex.quote('exec ntm "$@"') + " " + shlex.join([
            "acfs-fleet-receipt", "--robot-send-receipt=" + operation, "--robot-format=json"])
    request = entry["host"]["request"]
    args = ["--reconcile", "--receipt", request["receipt"]] if mode == "launch-status" else [
        "--dispatch-batch", entry["batch"], "--receipt", request["receipt"]]
    if mode == "send":
        args += ["--expect-sha256", entry["review_sha256"], "--send"]
    launcher = '"$HOME/.acfs/scripts/lib/swarm_launch.sh"'
    return ('test "$(/usr/bin/id -u)" -gt 0 && test -f ' + launcher + ' && test ! -L ' + launcher
            + ' && exec /bin/bash --noprofile --norc -p ' + launcher + " " + shlex.join(args))


def transport(known, identity, timeout, *, runner=fleet.capture, ssh="/usr/bin/ssh"):
    """Retain every SSH restriction and anonymous trust snapshot of fleet launch."""
    def invoke(entry, mode):
        command = remote_command(entry, mode)
        def dispatch_runner(argv, deadline, env):
            return runner([*argv[:-1], command], deadline, env)
        with fleet.transport(known, identity, timeout, runner=dispatch_runner, ssh=ssh) as call:
            return call(entry["host"], "reconcile")
    return invoke


def response(entry, mode, invoke):
    code, raw = invoke(entry, mode)
    require(type(code) is int and type(raw) is bytes, "invalid_transport_result")
    value = decode(raw)
    validate_binding(entry, value)
    return code, value


def validate_binding(entry, value):
    require(type(value) is dict and value.get("schema") == NATIVE_SCHEMA
            and value.get("launch_receipt") == entry["host"]["request"]["receipt"]
            and value.get("batch") == entry["batch"] and value.get("starts_agents") is False
            and value.get("agent_execution_verified") is False, "native_dispatch_identity_mismatch")
    require(fleet.matches(r"[0-9a-f]{64}", value.get("batch_review_sha256")), "invalid_batch_digest")
    expected = digest(encoded({"schema": NATIVE_SCHEMA, "request": entry["host"]["request"],
                              "targets": entry["targets"], "batch_sha256": value["batch_review_sha256"]}))
    require(value.get("review_sha256") == expected, "original_launch_or_batch_mismatch")


def preview(entry, invoke):
    # Native dispatch checks pending panes; reconciliation also rejects adoption
    # provenance and checks the complete original launch against our local result.
    live = fleet.remote_result(entry["host"], "reconcile", lambda _host, _mode: invoke(entry, "launch-status"))
    require(live["status"] == "ready" and live["targets"] == entry["targets"], "original_agents_not_live")
    code, value = response(entry, "preview", invoke)
    require(code == 0 and value.get("status") == "preview" and value.get("sends_prompt") is False,
            "native_dispatch_preview_refused")
    deliveries = validate_deliveries(entry, value.get("deliveries"))
    return {**entry, "review_sha256": value["review_sha256"],
            "batch_review_sha256": value["batch_review_sha256"], "deliveries": deliveries}


def validate_deliveries(entry, details):
    require(type(details) is list and 1 <= len(details) <= len(entry["targets"]), "invalid_delivery_count")
    by_slot = {target["slot"]: target for target in entry["targets"]}
    slots, operations, receipts, deliveries = set(), set(), set(), []
    keys = {"repo", "session", "pane", "agent_type", "operation_id", "bead_id", "packet_sha256", "payload_sha256", "payload_bytes"}
    for detail in details:
        require(type(detail) is dict and set(detail) == {"request", "receipt", "slot", "action"}
                and detail["action"] == "submit" and type(detail["slot"]) is int
                and detail["slot"] in by_slot and detail["slot"] not in slots, "delivery_not_new_or_wrong_slot")
        request, target = detail["request"], by_slot[detail["slot"]]
        require(type(request) is dict and set(request) == keys
                and request["repo"] == entry["host"]["request"]["repo"]
                and request["session"] == entry["host"]["request"]["session"]
                and request["pane"] == target["pane"] and request["agent_type"] == target["agent_type"]
                and all(fleet.matches(r"[0-9a-f]{64}", request[k]) for k in ("packet_sha256", "payload_sha256"))
                and all(fleet.matches(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", request[k]) for k in ("operation_id", "bead_id"))
                and type(request["payload_bytes"]) is int and 1 <= request["payload_bytes"] <= 65536,
                "invalid_delivery_request")
        receipt = fleet.absolute_path(detail["receipt"])
        require(receipt not in receipts and request["operation_id"] not in operations
                and receipt not in (entry["batch"], entry["host"]["request"]["receipt"],
                                    entry["host"]["request"]["receipt"] + ".result.json"), "duplicate_or_unsafe_delivery_receipt")
        slots.add(detail["slot"])
        operations.add(request["operation_id"])
        receipts.add(receipt)
        deliveries.append({"slot": detail["slot"], "request": request, "receipt": receipt})
    return deliveries


def submission(entry, invoke):
    code, value = response(entry, "send", invoke)
    require(code == 0 and value.get("status") == "submitted"
            and value["review_sha256"] == entry["review_sha256"]
            and value["batch_review_sha256"] == entry["batch_review_sha256"]
            and type(value.get("sends_prompt")) is bool, "batch_submission_unconfirmed")
    details = value.get("deliveries")
    require(type(details) is list and len(details) == len(entry["deliveries"]), "batch_submission_incomplete")
    for actual, expected in zip(details, entry["deliveries"]):
        require(type(actual) is dict and all(encoded(actual.get(k)) == encoded(v) for k, v in expected.items())
                and actual.get("status") == "submitted" and type(actual.get("sends_prompt")) is bool
                and actual.get("agent_execution_verified") is False, "delivery_submission_unconfirmed")


def attempted(plan, entry):
    return {"schema": STATE_SCHEMA, "plan_sha256": digest(encoded(plan)), "host_id": entry["host"]["id"]}


@contextmanager
def new_state(plan):
    path = Path(plan["state_directory"])
    with fleet.directory_fd(path.parent) as parent:
        os.mkdir(path.name, 0o700, dir_fd=parent)
        os.fsync(parent)
    with fleet.directory_fd(path, private=True) as fd:
        lock(fd)
        value = {"schema": STATE_SCHEMA, "plan": plan}
        fleet.publish(fd, "intent.json", value)
        records = {"intent.json": encoded(value)}
        fleet.state_unchanged(fd, plan, records)
        yield fd, records


def report_for(plan, operation):
    return {"schema": SCHEMA, "operation": operation, "status": "preview", "plan_sha256": digest(encoded(plan)),
            "starts_agents": False, "send_attempted": False, "agent_execution_verified": False,
            "hosts": [{"id": e["host"]["id"], "status": "not_attempted", "deliveries": [
                {"slot": d["slot"], "bead_id": d["request"]["bead_id"], "operation_id": d["request"]["operation_id"],
                 "packet_sha256": d["request"]["packet_sha256"], "payload_sha256": d["request"]["payload_sha256"]}
                for d in e["deliveries"]]} for e in plan["hosts"]]}


def send_pending(plan, pending, fd, records, report, invoke, source_guard):
    global SEND_ATTEMPTED
    for index in pending:
        source_guard()
        fleet.state_unchanged(fd, plan, records)
        entry = plan["hosts"][index]
        name = entry["host"]["id"] + ".attempt.json"
        value = attempted(plan, entry)
        fleet.publish(fd, name, value)
        records[name] = encoded(value)
        source_guard()
        fleet.state_unchanged(fd, plan, records)
        SEND_ATTEMPTED = report["send_attempted"] = True
        try:
            submission(entry, invoke)
        except (fleet.Refused, OSError, subprocess.SubprocessError) as exc:
            report["hosts"][index].update(status="unconfirmed", code=str(exc) if isinstance(exc, fleet.Refused) else "remote_unavailable")
            report["status"] = "unconfirmed"
            return report, 1
        source_guard()
        fleet.state_unchanged(fd, plan, records)
        name = entry["host"]["id"] + ".result.json"
        value = {**attempted(plan, entry), "submitted": True}
        fleet.publish(fd, name, value)
        records[name] = encoded(value)
        report["hosts"][index]["status"] = "submitted"
    source_guard()
    fleet.state_unchanged(fd, plan, records)
    report["status"] = "submitted"
    return report, 0


def plan_context(launch_path, launch, records, known, identity, state_dir, timeout):
    return {"schema": SCHEMA, "policy": POLICY, "launch_state": launch_path,
            "launch_plan_sha256": digest(encoded(launch)),
            "launch_evidence_sha256": digest(encoded({k: digest(v) if v is not None else None for k, v in records.items()})),
            "known_hosts_sha256": digest(known), "identity_sha256": digest(identity),
            "state_directory": state_dir, "timeout_seconds": timeout}


def read_dispatch_history(fd, context, selected):
    raw = fleet.read_at(fd, "intent.json")
    intent = decode(raw)
    require(type(intent) is dict and set(intent) == {"schema", "plan"}
            and intent["schema"] == STATE_SCHEMA, "invalid_dispatch_intent")
    plan = intent["plan"]
    require(type(plan) is dict and set(plan) == set(context) | {"hosts"}
            and all(encoded(plan[k]) == encoded(v) for k, v in context.items())
            and type(plan["hosts"]) is list and len(plan["hosts"]) == len(selected), "dispatch_context_changed")
    records, history, pending, incomplete = {"intent.json": raw}, [], False, False
    beads = set()
    for entry, original in zip(plan["hosts"], selected):
        require(type(entry) is dict and set(entry) == set(original) | {"review_sha256", "batch_review_sha256", "deliveries"}
                and all(encoded(entry[k]) == encoded(v) for k, v in original.items()), "dispatch_host_changed")
        validate_binding(entry, {"schema": NATIVE_SCHEMA, "launch_receipt": entry["host"]["request"]["receipt"],
            "batch": entry["batch"], "starts_agents": False, "agent_execution_verified": False,
            "batch_review_sha256": entry["batch_review_sha256"], "review_sha256": entry["review_sha256"]})
        require(type(entry["deliveries"]) is list and all(type(d) is dict
                and set(d) == {"slot", "request", "receipt"} for d in entry["deliveries"]), "invalid_saved_deliveries")
        validated = validate_deliveries(entry, [{**d, "action": "submit"} for d in entry["deliveries"]])
        for delivery in validated:
            bead = delivery["request"]["bead_id"]
            require(bead not in beads, "duplicate_fleet_bead_assignment")
            beads.add(bead)
        name = entry["host"]["id"]
        attempt = fleet.read_at(fd, name + ".attempt.json", optional=True)
        result = fleet.read_at(fd, name + ".result.json", optional=True)
        records[name + ".attempt.json"], records[name + ".result.json"] = attempt, result
        require(attempt is not None or result is None, "result_without_attempt")
        if attempt is None:
            pending = True
        else:
            require(not pending and not incomplete, "nonprefix_dispatch_history")
            expected = attempted(plan, entry)
            require(encoded(decode(attempt)) == encoded(expected), "dispatch_attempt_mismatch")
            if result is not None:
                require(encoded(decode(result)) == encoded({**expected, "submitted": True}), "dispatch_result_mismatch")
            else:
                incomplete = True
        history.append((attempt is not None, result is not None))
    fleet.state_unchanged(fd, plan, records)
    return plan, history, records


def query_submission(entry, delivery, invoke):
    """Snapshot the native intent, then query NTM's exact operation; never send."""
    query = {**entry, "delivery": delivery}
    code, raw = invoke(query, "read-receipt")
    require(type(code) is int and code == 0 and type(raw) is bytes, "native_receipt_unavailable")
    saved = decode(raw)
    require(type(saved) is dict and set(saved) == {"schema", "request", "target"}
            and saved["schema"] == "acfs.packet-delivery.v1"
            and encoded(saved["request"]) == encoded(delivery["request"])
            and type(saved["target"]) is str and 1 <= len(saved["target"]) <= 128
            and all(32 <= ord(c) < 127 for c in saved["target"]), "native_receipt_mismatch")
    code, raw = invoke(query, "query-receipt")
    require(type(code) is int and code == 0 and type(raw) is bytes, "ntm_receipt_unavailable")
    value = decode(raw)
    require(type(value) is dict, "ntm_receipt_invalid")
    operation, outcome = value.get("operation"), value.get("outcome")
    request, target = delivery["request"], saved["target"]
    require(value.get("success") is True and value.get("session") == request["session"]
            and type(operation) is dict and operation.get("operation_id") == request["operation_id"]
            and operation.get("payload_sha256") == request["payload_sha256"]
            and type(operation.get("payload_bytes")) is int and operation["payload_bytes"] == request["payload_bytes"]
            and operation.get("status") == "completed" and type(outcome) is dict
            and outcome.get("success") is True and outcome.get("targets") == [target]
            and outcome.get("successful") == [target] and outcome.get("failed") == []
            and operation.get("admissions") == [{"target": target, "state": "submitted"}],
            "submission_not_confirmed")


def recover(context, selected, mode, approval, invoke, source_guard):
    with fleet.directory_fd(context["state_directory"], private=True) as fd:
        lock(fd)
        plan, history, records = read_dispatch_history(fd, context, selected)
        require(mode != "resume" or approval == digest(encoded(plan)), "approval_mismatch_preview_again")
        report = report_for(plan, mode)
        def checked_invoke(entry, action):
            source_guard()
            fleet.state_unchanged(fd, plan, records)
            try:
                return invoke(entry, action)
            finally:
                source_guard()
                fleet.state_unchanged(fd, plan, records)
        confirmed = True
        for index, (was_attempted, _) in enumerate(history):
            if not was_attempted:
                continue
            entry, row = plan["hosts"][index], report["hosts"][index]
            row.update(status="submitted", reconciled_only=True)
            for delivery, detail in zip(entry["deliveries"], row["deliveries"]):
                try:
                    query_submission(entry, delivery, checked_invoke)
                    detail["status"] = "submitted"
                except (fleet.Refused, OSError, subprocess.SubprocessError) as exc:
                    detail.update(status="unconfirmed", code=str(exc) if isinstance(exc, fleet.Refused) else "remote_unavailable")
                    row["status"], confirmed = "unconfirmed", False
        source_guard()
        fleet.state_unchanged(fd, plan, records)
        if not confirmed:
            report["status"] = "unconfirmed"
            return report, 1
        pending = [i for i, (was_attempted, _) in enumerate(history) if not was_attempted]
        if mode == "reconcile":
            report["status"] = "partial" if pending else "submitted"
            return report, 1 if pending else 0
        for index, (was_attempted, result_exists) in enumerate(history):
            if was_attempted and not result_exists:
                entry = plan["hosts"][index]
                name = entry["host"]["id"] + ".result.json"
                value = {**attempted(plan, entry), "submitted": True}
                fleet.publish(fd, name, value)
                records[name] = encoded(value)
        blocked = False
        for index in pending:
            entry = plan["hosts"][index]
            try:
                require(encoded(preview(entry, checked_invoke)) == encoded(entry), "pending_batch_changed")
            except (fleet.Refused, OSError, subprocess.SubprocessError) as exc:
                report["hosts"][index]["code"] = str(exc) if isinstance(exc, fleet.Refused) else "remote_unavailable"
                blocked = True
        source_guard()
        fleet.state_unchanged(fd, plan, records)
        if blocked:
            report["status"] = "blocked"
            return report, 1
        return send_pending(plan, pending, fd, records, report, checked_invoke, source_guard)


def execute(launch_path, batches, known, identity, state_dir, timeout, mode, approval, invoke):
    global SEND_ATTEMPTED
    SEND_ATTEMPTED = False
    require(mode in ("preview", "send", "reconcile", "resume"), "invalid_dispatch_operation")
    require((approval is not None) == (mode in ("send", "resume"))
            and (approval is None or fleet.matches(r"[0-9a-f]{64}", approval)), "send_requires_exact_approval")
    require(type(timeout) is int and 1 <= timeout <= 600, "invalid_timeout")
    state_dir = str(Path(os.path.abspath(state_dir)))
    launch_path = str(Path(os.path.abspath(launch_path)))
    require(state_dir != launch_path and Path(launch_path) not in Path(state_dir).parents,
            "dispatch_state_must_be_outside_launch_journal")
    if mode in ("preview", "send"):
        fleet.state_preflight({"state_directory": state_dir})
    with launch_context(launch_path, known, identity) as (launch, history, records, guard):
        selected = select_batches(batches, launch, history)
        context = plan_context(launch_path, launch, records, known, identity, state_dir, timeout)
        if mode in ("reconcile", "resume"):
            return recover(context, selected, mode, approval, invoke, guard)
        prepared, errors = [], []
        for entry in selected:
            guard()
            try:
                prepared.append(preview(entry, invoke))
            except (fleet.Refused, OSError, subprocess.SubprocessError) as exc:
                errors.append({"id": entry["host"]["id"], "code": str(exc) if isinstance(exc, fleet.Refused) else "remote_unavailable"})
            guard()
        if errors:
            return {"schema": SCHEMA, "status": "blocked", "starts_agents": False, "send_attempted": False,
                    "agent_execution_verified": False, "errors": errors}, 1
        beads = [d["request"]["bead_id"] for e in prepared for d in e["deliveries"]]
        require(len(set(beads)) == len(beads), "duplicate_fleet_bead_assignment")
        plan = {**context, "hosts": prepared}
        report = report_for(plan, mode)
        if mode == "preview":
            for row in report["hosts"]:
                row["status"] = "reviewed"
            return report, 0
        require(approval == report["plan_sha256"], "approval_mismatch_preview_again")
        guard()
        with new_state(plan) as (fd, state_records):
            return send_pending(plan, range(len(prepared)), fd, state_records, report, invoke, guard)


def main(arguments=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--launch-state", required=True, help="Existing private fleet launch journal")
    parser.add_argument("--batches", required=True, help="Private explicit host-ID to remote batch-path selection")
    parser.add_argument("--known-hosts", required=True)
    parser.add_argument("--identity-file", required=True)
    parser.add_argument("--state-dir", required=True, help="New dispatch journal, outside the launch journal")
    parser.add_argument("--timeout", type=int, default=360, help="Per SSH call, 1..600 seconds")
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--send", action="store_true", help="Send approved work; may consume paid model quota")
    action.add_argument("--reconcile", action="store_true", help="Query attempted submissions only; no writes or sends")
    action.add_argument("--resume", action="store_true", help="Confirm attempted hosts, then send only to untouched hosts")
    parser.add_argument("--accept-plan", help="Exact dispatch preview digest; not the fleet launch digest")
    args = parser.parse_args(arguments)
    mode = "resume" if args.resume else "reconcile" if args.reconcile else "send" if args.send else "preview"
    known, identity = fleet.read_input(args.known_hosts, private=False), fleet.read_input(args.identity_file)
    result, code = execute(args.launch_state, decode(fleet.read_input(args.batches)), known, identity,
                           args.state_dir, args.timeout, mode, args.accept_plan,
                           transport(known, identity, args.timeout))
    print(encoded(result).decode(), end="")
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
                       "code": str(exc) if isinstance(exc, fleet.Refused) else "preserve_dispatch_and_launch_receipts",
                       "send_attempted": SEND_ATTEMPTED, "starts_agents": False,
                       "agent_execution_verified": False}).decode(), end="")
        return 128 + exc.signum if interrupted else 2


if __name__ == "__main__":
    sys.exit(cli())
