#!/usr/bin/env python3
"""Prepare scoped work on original fleet agents; never launch or send prompts.

Preview is local and read-only. --prepare transfers explicitly selected task
briefs and invokes the existing launch-aware preparer after an all-host check.
Run from a complete trusted checkout with the original private launch journal.
"""
import argparse
from contextlib import contextmanager
import fcntl
import os
from pathlib import Path
import re
import selectors
import shlex
import signal
import subprocess
import sys
import tempfile
import time
import types

sys.dont_write_bytecode = True
_helper = Path(__file__).absolute().with_name("swarm-fleet-launch.py")
if _helper.is_symlink() or not _helper.is_file():
    raise SystemExit("Required trusted sibling swarm-fleet-launch.py is unavailable")
FLEET_SOURCE = _helper.read_bytes()
fleet = types.ModuleType("acfs_fleet_launch")
exec(compile(FLEET_SOURCE, str(_helper), "exec"), fleet.__dict__)
require, encoded, decode, digest = fleet.require, fleet.encoded, fleet.decode, fleet.digest
SCHEMA = "acfs.swarm-fleet-preparation.v1"
WORK_SCHEMA = "acfs.swarm-fleet-work.v1"
PEER_SCHEMA = "acfs.swarm-fleet-preparation-peer.v1"
PREPARATION_ATTEMPTED = False

# Fixed first-party program, never supplied by a work file or remote response.
# The same existing fleet utility bytes provide bounded JSON, no-follow private
# file reads, durable create-only writes and process supervision on both ends.
# Task briefs travel through stdin, not command arguments or generated shell.
PEER_CODE = r'''
import fcntl
import os
from pathlib import Path
import sys


def peer_live(entry, timeout):
    home = os.environ.get("HOME", "")
    fleet.absolute_path(home)
    with fleet.directory_fd(home):
        pass
    launcher = Path(home) / ".acfs/scripts/lib/swarm_launch.sh"
    with fleet.directory_fd(launcher.parent) as directory:
        fleet.read_at(directory, launcher.name, private=False)
        fleet.read_at(directory, "swarm_packet.sh", private=False)
    # Bash and Python startup hooks, proxy variables, credentials and test
    # overrides do not enter the native preparer. Its normal managed bins do.
    env = {"HOME": home, "PATH": ":".join([home + "/.local/bin", home + "/.bun/bin",
        home + "/.cargo/bin", "/usr/local/bin", "/usr/bin", "/bin"]),
        "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"}
    argv = ["/bin/bash", "--noprofile", "--norc", "-p", str(launcher)]
    result = fleet.remote_result(entry["host"], "reconcile", lambda _host, _mode:
        fleet.capture(argv + ["--reconcile", "--receipt", entry["host"]["request"]["receipt"]], timeout, env))
    fleet.require(result["status"] == "ready" and result["targets"] == entry["targets"], "original_agents_not_live")
    return argv, env


def bundle_snapshot(entry):
    root = str(Path(entry["output"]) / "bundle")
    expected_names = {"assignments.json", "batch.json"}
    receipt_names = set()
    items = entry["assignments"]["assignments"]
    for item in items:
        name = "packet-" + str(item["slot"]).zfill(2)
        expected_names.update((name + ".json", name + ".md"))
        receipt_names.add(name + ".receipt.json")
    with fleet.directory_fd(root, private=True) as fd:
        members = set(os.listdir(fd))
        fleet.require(expected_names <= members <= expected_names | receipt_names, "unexpected_bundle_members")
        files = {name: fleet.read_at(fd, name) for name in sorted(expected_names)}
    fleet.require(sum(len(raw) for raw in files.values()) <= 16 * fleet.LIMIT, "bundle_size_limit")
    fleet.require(files["assignments.json"] == fleet.encoded(entry["assignments"]), "assignment_bytes_changed")
    batch = fleet.decode(files["batch.json"])
    fleet.require(type(batch) is dict and set(batch) == {"schema", "deliveries"}
        and batch["schema"] == "acfs.packet-delivery-batch.v1" and type(batch["deliveries"]) is list
        and len(batch["deliveries"]) == len(items), "prepared_batch_invalid")
    targets = {t["slot"]: t for t in entry["targets"]}
    operations = set()
    packets = []
    for item, delivery in zip(items, batch["deliveries"]):
        slot = item["slot"]
        name = "packet-" + str(slot).zfill(2)
        target, request = targets[slot], entry["host"]["request"]
        fleet.require(type(delivery) is dict and set(delivery) == {
            "packet", "repo", "session", "pane", "agent_type", "operation_id", "receipt"}
            and delivery["packet"] == name + ".json" and delivery["receipt"] == name + ".receipt.json"
            and delivery["repo"] == request["repo"] and delivery["session"] == request["session"]
            and delivery["pane"] == target["pane"] and delivery["agent_type"] == target["agent_type"]
            and fleet.matches(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", delivery["operation_id"])
            and delivery["operation_id"] not in operations, "prepared_target_invalid")
        operations.add(delivery["operation_id"])
        packet = fleet.decode(files[name + ".json"])
        fleet.require(type(packet) is dict and type(packet.get("schema_version")) is int
            and packet["schema_version"] == 1 and packet.get("status") in ("pass", "warn")
            and type(packet.get("repository")) is dict and packet["repository"].get("path") == request["repo"]
            and type(packet.get("bead")) is dict and packet["bead"].get("id") == item["bead_id"]
            and type(packet.get("output")) is dict and packet["output"].get("truncated") is False,
            "prepared_packet_invalid")
        scope = packet.get("preparation")
        fleet.require(type(scope) is dict and type(scope.get("slot")) is int and scope["slot"] == slot
            and scope.get("assignment_sha256") == fleet.digest(files["assignments.json"])
            and scope.get("declared_write_scopes") == item["reservation_surfaces"]
            and scope.get("reservations_acquired") is False and scope.get("bead_source") == "file",
            "prepared_scope_invalid")
        text = packet.get("packet_markdown")
        fleet.require(type(text) is str and text.startswith("# ACFS Swarm Startup Packet\n")
            and not any(ord(c) < 32 and c not in "\n\t" for c in text)
            and 1 <= len(text.encode()) <= 65536 and files[name + ".md"] == text.encode(),
            "prepared_markdown_invalid")
        packets.append({"slot": slot, "bead_id": item["bead_id"], "operation_id": delivery["operation_id"]})
    return {"schema": "acfs.swarm-fleet-preparation-peer.v1", "status": "prepared",
        "entry_sha256": fleet.digest(fleet.encoded(entry)), "batch": root + "/batch.json",
        "files": {name: {"sha256": fleet.digest(raw), "bytes": len(raw)} for name, raw in files.items()},
        "packets": packets, "starts_agents": False, "sends_prompt": False}


def inspect_preparation(entry):
    # A complete, unchanged bundle can be observed after response loss. No
    # preparer, live agent, or remote command is invoked on this path.
    path = entry["output"]
    with fleet.directory_fd(path, private=True) as fd:
        fcntl.flock(fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
        names = {"request.json", "assignments.json", "beads.json", "complete.json"}
        fleet.require(set(os.listdir(fd)) == names | {"bundle"}, "remote_preparation_incomplete")
        records = {name: fleet.read_at(fd, name) for name in names}
        fleet.require(records["request.json"] == fleet.encoded(entry)
            and records["assignments.json"] == fleet.encoded(entry["assignments"])
            and records["beads.json"] == fleet.encoded(entry["beads"]), "remote_preparation_input_mismatch")
        result = bundle_snapshot(entry)
        fleet.require(records["complete.json"] == fleet.encoded(result), "prepared_bundle_changed")
        with fleet.directory_fd(path, private=True) as current:
            fleet.require(os.path.samestat(os.fstat(fd), os.fstat(current)), "remote_output_changed")
        fleet.require(set(os.listdir(fd)) == names | {"bundle"}
            and all(fleet.read_at(fd, name) == raw for name, raw in records.items()), "remote_output_changed")
        return result


def peer_main(message):
    fleet.require(os.geteuid() != 0, "nonroot_remote_user_required")
    fleet.require(type(message) is dict and set(message) == {"mode", "entry", "timeout_seconds"}, "invalid_peer_request")
    mode, entry, timeout = message["mode"], message["entry"], message["timeout_seconds"]
    fleet.require(mode in ("check", "prepare", "inspect") and type(timeout) is int and 1 <= timeout <= 600, "invalid_peer_operation")
    fleet.require(type(entry) is dict and set(entry) == {"host", "targets", "output", "identities", "assignments", "beads"},
        "invalid_peer_entry")
    fleet.validate_spec({"schema": fleet.SPEC_SCHEMA, "hosts": [entry["host"]]})
    fleet.require(fleet.valid_targets(entry["targets"], entry["host"]["request"]) == entry["targets"], "invalid_peer_targets")
    path = Path(fleet.absolute_path(entry["output"]))
    if mode == "inspect":
        return inspect_preparation(entry)
    deadline = fleet.time.monotonic() + timeout
    def remaining():
        budget = deadline - fleet.time.monotonic()
        fleet.require(budget > 0, "preparation_deadline_exceeded")
        return budget
    with fleet.directory_fd(path.parent) as parent:
        fleet.require(not os.path.lexists(path), "remote_output_already_exists")
        argv, env = peer_live(entry, remaining())
        if mode == "check":
            return {"schema": "acfs.swarm-fleet-preparation-peer.v1", "status": "available",
                "entry_sha256": fleet.digest(fleet.encoded(entry)), "starts_agents": False, "sends_prompt": False}
        # Reserve the output exactly once, before the native preparer can run.
        os.mkdir(path.name, 0o700, dir_fd=parent)
        os.fsync(parent)
    with fleet.directory_fd(path, private=True) as fd:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fleet.publish(fd, "request.json", entry)
        fleet.publish(fd, "assignments.json", entry["assignments"])
        fleet.publish(fd, "beads.json", entry["beads"])
        records = {name: fleet.read_at(fd, name) for name in os.listdir(fd)}
        fleet.state_unchanged(fd, {"state_directory": str(path)}, records)
        args = ["--prepare-batch", str(path / "bundle"), "--receipt", entry["host"]["request"]["receipt"],
            "--assignments", str(path / "assignments.json"), "--beads-file", str(path / "beads.json"), "--no-live-context"]
        for identity in entry["identities"]:
            args += ["--identity", str(identity["slot"]) + ":" + identity["name"]]
        code, raw = fleet.capture(argv + args, remaining(), env)
        result = fleet.decode(raw)
        fleet.require(code == 0 and type(result) is dict and result.get("schema") == "acfs.packet-preparation.v1"
            and result.get("status") == "prepared" and result.get("directory") == str(path / "bundle")
            and result.get("sends_prompt") is False, "native_preparation_unconfirmed")
        handoff = result.get("launch")
        names = {v["slot"]: v["name"] for v in entry["identities"]}
        mapping = [{"slot": t["slot"], "launch_name": t["agent_name"],
            "agent_mail_name": names[t["slot"]], "agent_type": t["agent_type"], "pane": t["pane"]}
            for t in entry["targets"]]
        fleet.require(type(handoff) is dict and handoff.get("receipt") == entry["host"]["request"]["receipt"]
            and handoff.get("session") == entry["host"]["request"]["session"]
            and handoff.get("request_sha256") == fleet.digest(fleet.encoded(entry["host"]["request"]))
            and handoff.get("identities_rechecked") is True and handoff.get("starts_agents") is False
            and handoff.get("work_dispatched") is False and handoff.get("agent_mail_registration_verified") is False
            and handoff.get("identity_mapping") == mapping, "native_handoff_invalid")
        peer_live(entry, remaining())
        with fleet.directory_fd(path, private=True) as current:
            fleet.require(os.path.samestat(os.fstat(fd), os.fstat(current)), "remote_output_changed")
        fleet.require(set(os.listdir(fd)) == set(records) | {"bundle"}, "remote_output_changed")
        for name, data in records.items():
            fleet.require(fleet.read_at(fd, name) == data, "remote_input_changed")
        summary = bundle_snapshot(entry)
        # Completion is last. A lost reply can be inspected without regenerating
        # the native preparer's random operation namespace or overwriting work.
        fleet.publish(fd, "complete.json", summary)
        return summary
'''


def remote_program():
    return ("import types\nfleet = types.ModuleType('acfs_fleet')\nexec("
            + repr(FLEET_SOURCE.decode("utf-8")) + ", fleet.__dict__)\n" + PEER_CODE + "\n"
            + "try:\n    result = peer_main(fleet.decode(sys.stdin.buffer.read(fleet.LIMIT + 1)))\n"
              "    sys.stdout.buffer.write(fleet.encoded(result))\n"
              "except (fleet.Refused, OSError, ValueError, KeyError, TypeError):\n    sys.exit(2)\n")


def scopes_overlap(left, right):
    # Extra fleet-wide admission, not a second scheduler. Conservatively include
    # literal directory ancestors as well as the native preparer's glob prefixes.
    a, b = (re.split(r"[*?]", value, maxsplit=1)[0] for value in (left, right))
    if any(c in left + right for c in "*?"):
        return a.startswith(b) or b.startswith(a)
    return left == right or left.startswith(right + "/") or right.startswith(left + "/")


def select_work(spec, launch, history):
    require(type(spec) is dict and set(spec) == {"schema", "hosts", "assignments", "beads"}
            and spec["schema"] == WORK_SCHEMA, "invalid_work_spec")
    require(type(spec["hosts"]) is list and 1 <= len(spec["hosts"]) <= 16
            and type(spec["assignments"]) is list and 1 <= len(spec["assignments"]) <= 256
            and type(spec["beads"]) is list and 1 <= len(spec["beads"]) <= 2048, "invalid_work_counts")
    selected, names = {}, set()
    originals = {h["id"]: (h, state) for h, state in zip(launch["spec"]["hosts"], history)}
    for host in spec["hosts"]:
        require(type(host) is dict and set(host) == {"id", "output", "identities"}
                and type(host["id"]) is str and host["id"] in originals and host["id"] not in selected,
                "unknown_or_duplicate_work_host")
        original, (attempted, targets) = originals[host["id"]]
        require(attempted and targets is not None, "selected_launch_not_confirmed")
        output = fleet.absolute_path(host["output"])
        require(output not in (original["request"]["receipt"], original["request"]["repo"])
                and not original["request"]["receipt"].startswith(output + "/"), "output_overlaps_launch")
        identities = host["identities"]
        require(type(identities) is list and len(identities) == len(targets), "identity_map_incomplete")
        slots = set()
        for identity in identities:
            require(type(identity) is dict and set(identity) == {"slot", "name"}
                    and type(identity["slot"]) is int and 1 <= identity["slot"] <= len(targets)
                    and identity["slot"] not in slots
                    and fleet.matches(r"[A-Za-z][A-Za-z0-9_-]{0,63}", identity["name"])
                    and identity["name"].lower() not in names, "invalid_or_duplicate_work_identity")
            names.add(identity["name"].lower())
            slots.add(identity["slot"])
        selected[host["id"]] = {"host": original, "targets": targets, "output": output,
            "identities": sorted(identities, key=lambda v: v["slot"]), "beads": [],
            "assignments": {"schema_version": 1, "status": "pass", "advisory_only": True,
                "scope_admission": {"mode": "explicit-scopes"}, "assignments": []}}
    beads = {}
    for bead in spec["beads"]:
        require(type(bead) is dict and fleet.matches(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", bead.get("id"))
                and bead["id"] not in beads, "invalid_or_duplicate_bead")
        beads[bead["id"]] = bead
    tasks, occupied, surfaces = set(), set(), []
    for item in spec["assignments"]:
        require(type(item) is dict and set(item) == {"host_id", "slot", "bead_id", "role", "write_scopes"}
                and type(item["host_id"]) is str and item["host_id"] in selected
                and type(item["slot"]) is int and 1 <= item["slot"] <= len(selected[item["host_id"]]["targets"])
                and (item["host_id"], item["slot"]) not in occupied
                and type(item["bead_id"]) is str and item["bead_id"] in beads and item["bead_id"] not in tasks
                and item["role"] in ("implementation", "testing", "review", "documentation"), "invalid_or_duplicate_assignment")
        bead = beads[item["bead_id"]]
        require(bead.get("status") == "open" and bead.get("blocked", False) is False
                and bead.get("blocked_by", []) == [] and bead.get("issue_type") != "epic"
                and type(bead.get("title")) is str and bead["title"].strip()
                and all(bead.get(k) is None or type(bead[k]) is str for k in ("description", "design", "acceptance_criteria"))
                and type(bead.get("labels", [])) is list and all(type(v) is str for v in bead.get("labels", []))
                and len(encoded(bead)) <= 65536, "assigned_bead_not_usable")
        paths = item["write_scopes"]
        require(type(paths) is list and 1 <= len(paths) <= 32 and all(
            fleet.matches(r"[A-Za-z0-9_.*?/ -]{1,256}", p)
            and all(part not in ("", ".", "..") for part in p.split("/")) for p in paths)
            and len(set(paths)) == len(paths), "invalid_write_scopes")
        require(not any(scopes_overlap(a, b) for a in paths for b in surfaces), "cross_task_write_scope_overlap")
        surfaces.extend(paths)
        tasks.add(item["bead_id"])
        occupied.add((item["host_id"], item["slot"]))
        entry = selected[item["host_id"]]
        entry["assignments"]["assignments"].append({"slot": item["slot"], "bead_id": item["bead_id"],
            "role": item["role"], "issue_type": bead.get("issue_type", "task"), "scope_source": "explicit",
            "reservation_surfaces": paths, "dependency_position": {"blocked_by": []}})
        entry["beads"].append(bead)
    result = []
    for host in launch["spec"]["hosts"]:
        if host["id"] not in selected:
            continue
        entry = selected[host["id"]]
        require(entry["beads"], "selected_host_has_no_work")
        entry["assignments"]["assignments"].sort(key=lambda a: a["slot"])
        entry["beads"].sort(key=lambda b: b["id"])
        require(len(encoded(entry)) <= fleet.LIMIT - 1024, "host_work_size_limit")
        result.append(entry)
    return result


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
        require(plan["state_directory"] == path and plan["known_hosts_sha256"] == digest(known)
                and plan["identity_sha256"] == digest(identity), "launch_context_mismatch")
        history, records = fleet.read_history(fd, plan)
        def guard():
            fleet.state_unchanged(fd, plan, records)
        guard()
        yield plan, history, records, guard
        guard()


def build_plan(work, launch, history, records, state_dir, timeout):
    require(type(timeout) is int and 1 <= timeout <= 600, "timeout_must_be_1_to_600")
    state_dir = fleet.absolute_path(str(Path(os.path.abspath(state_dir))))
    source = Path(launch["state_directory"])
    destination = Path(state_dir)
    require(source != destination and source not in destination.parents and destination not in source.parents,
            "preparation_state_overlaps_launch")
    plan = {"schema": SCHEMA, "state_directory": state_dir, "launch_state": str(source),
        "source_sha256": digest(encoded({k: digest(v) for k, v in records.items() if v is not None})),
        "known_hosts_sha256": launch["known_hosts_sha256"], "identity_sha256": launch["identity_sha256"],
        "peer_policy_sha256": digest(remote_program().encode()), "timeout_seconds": timeout,
        "hosts": select_work(work, launch, history)}
    require(len(encoded(plan)) <= fleet.LIMIT, "preparation_plan_size_limit")
    return plan


def capture_input(argv, timeout, env, data):
    require(len(data) <= fleet.LIMIT, "host_work_size_limit")
    with tempfile.TemporaryFile() as inp:
        inp.write(data)
        inp.seek(0)
        process = subprocess.Popen(argv, env=env, stdin=inp, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, start_new_session=True)
        deadline, size, output = time.monotonic() + timeout, 0, bytearray()
        try:
            with selectors.DefaultSelector() as poll:
                for stream in (process.stdout, process.stderr):
                    os.set_blocking(stream.fileno(), False)
                    poll.register(stream, selectors.EVENT_READ)
                while poll.get_map() or process.poll() is None:
                    require(time.monotonic() < deadline, "preparation_transport_timeout")
                    for key, _ in poll.select(0.05):
                        part = os.read(key.fd, 65536)
                        if not part:
                            poll.unregister(key.fileobj)
                        size += len(part)
                        require(size <= fleet.LIMIT, "preparation_transport_output_limit")
                        if key.fileobj is process.stdout:
                            output.extend(part)
                    if not poll.get_map() and process.poll() is None:
                        time.sleep(0.01)
            return process.returncode, bytes(output)
        finally:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)
            process.stdout.close()
            process.stderr.close()


def transport(known, identity, timeout, *, runner=capture_input, ssh="/usr/bin/ssh"):
    command = "exec python3 -I -c " + shlex.quote(remote_program())
    require(len(command.encode()) <= 100000, "remote_program_size_limit")
    def invoke(entry, mode):
        require(mode in ("check", "prepare", "inspect"), "invalid_preparation_mode")
        data = encoded({"mode": mode, "entry": entry, "timeout_seconds": timeout})
        def wrapped(argv, deadline, env):
            # Only drop SSH's stdin-discard switch; retain every trust/forwarding
            # restriction. No task bytes or operator command enter the shell.
            require(argv[1:5] == ["-F", "/dev/null", "-T", "-n"], "ssh_policy_changed")
            return runner([argv[0], *argv[1:4], *argv[5:-1], command], deadline, env, data)
        with fleet.transport(known, identity, timeout, runner=wrapped, ssh=ssh) as call:
            return call(entry["host"], "reconcile")
    return invoke


def accept_result(entry, value, mode):
    require(type(value) is dict and value.get("schema") == PEER_SCHEMA
            and value.get("entry_sha256") == digest(encoded(entry))
            and value.get("starts_agents") is False and value.get("sends_prompt") is False,
            "preparation_response_mismatch")
    if mode == "check":
        require(set(value) == {"schema", "status", "entry_sha256", "starts_agents", "sends_prompt"}
                and value["status"] == "available", "remote_preflight_refused")
        return value
    require(set(value) == {"schema", "status", "entry_sha256", "batch", "files", "packets", "starts_agents", "sends_prompt"}
            and value["status"] == "prepared" and value["batch"] == entry["output"] + "/bundle/batch.json",
            "remote_preparation_unconfirmed")
    expected = {"assignments.json", "batch.json"}
    items = entry["assignments"]["assignments"]
    for item in items:
        name = "packet-" + str(item["slot"]).zfill(2)
        expected.update((name + ".json", name + ".md"))
    files = value["files"]
    require(type(files) is dict and set(files) == expected and all(
        type(v) is dict and set(v) == {"sha256", "bytes"} and fleet.matches(r"[a-f0-9]{64}", v["sha256"])
        and type(v["bytes"]) is int and 1 <= v["bytes"] <= fleet.LIMIT for v in files.values()), "prepared_file_inventory_invalid")
    require(sum(v["bytes"] for v in files.values()) <= 16 * fleet.LIMIT
            and files["assignments.json"] == {"sha256": digest(encoded(entry["assignments"])),
                                               "bytes": len(encoded(entry["assignments"]))}, "prepared_assignment_mismatch")
    packets = value["packets"]
    require(type(packets) is list and len(packets) == len(items), "prepared_packet_count_mismatch")
    operations = set()
    for packet, item in zip(packets, items):
        require(type(packet) is dict and set(packet) == {"slot", "bead_id", "operation_id"}
                and type(packet["slot"]) is int and packet["slot"] == item["slot"] and packet["bead_id"] == item["bead_id"]
                and fleet.matches(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", packet["operation_id"])
                and packet["operation_id"] not in operations, "prepared_packet_identity_mismatch")
        operations.add(packet["operation_id"])
    return value


def probe(entry, mode, invoke):
    code, raw = invoke(entry, mode)
    require(type(code) is int and code == 0 and type(raw) is bytes, "remote_preparation_failed")
    value = decode(raw)
    return accept_result(entry, value, mode)


def report_for(plan):
    return {"schema": SCHEMA, "status": "preview", "plan_sha256": digest(encoded(plan)),
        "starts_agents": False, "sends_prompt": False, "preparation_attempted": False,
        "scope_policy": "one-logical-project-conservative-cross-host-write-scopes",
        "task_status_source": "supplied_beads_snapshot",
        "live_reservations_checked": False, "agent_mail_registration_verified": False,
        "hosts": [{"id": e["host"]["id"], "status": "not_attempted", "output": e["output"],
            "identities": e["identities"], "assignments": e["assignments"]["assignments"]} for e in plan["hosts"]]}


def attempt(plan, entry):
    return {"schema": SCHEMA, "plan_sha256": digest(encoded(plan)), "entry_sha256": digest(encoded(entry))}


def prepare(plan, approval, invoke, guard):
    global PREPARATION_ATTEMPTED
    PREPARATION_ATTEMPTED = False
    require(approval == digest(encoded(plan)), "approval_mismatch_preview_again")
    fleet.state_preflight(plan)
    report = report_for(plan)
    # Check every host before creating any state or uploading any persistent
    # input. Each actual native preparation subsequently rechecks its launch.
    blocked = False
    for index, entry in enumerate(plan["hosts"]):
        guard()
        try:
            probe(entry, "check", invoke)
        except (fleet.Refused, OSError, subprocess.SubprocessError):
            report["hosts"][index].update(status="blocked", code="remote_preflight_failed")
            blocked = True
        guard()
    if blocked:
        report["status"] = "blocked"
        return report, 1
    path = Path(plan["state_directory"])
    with fleet.directory_fd(path.parent) as parent:
        os.mkdir(path.name, 0o700, dir_fd=parent)
        os.fsync(parent)
    with fleet.directory_fd(path, private=True) as fd:
        lock(fd)
        intent = {"schema": SCHEMA, "plan": plan}
        fleet.publish(fd, "intent.json", intent)
        records = {"intent.json": encoded(intent)}
        for index, entry in enumerate(plan["hosts"]):
            guard()
            fleet.state_unchanged(fd, plan, records)
            name = entry["host"]["id"] + ".attempt.json"
            value = attempt(plan, entry)
            fleet.publish(fd, name, value)
            records[name] = encoded(value)
            PREPARATION_ATTEMPTED = report["preparation_attempted"] = True
            try:
                result = probe(entry, "prepare", invoke)
            except (fleet.Refused, OSError, subprocess.SubprocessError):
                report["status"] = "unconfirmed"
                report["hosts"][index].update(status="unconfirmed", code="preserve_remote_output")
                return report, 1
            guard()
            fleet.state_unchanged(fd, plan, records)
            name = entry["host"]["id"] + ".result.json"
            fleet.publish(fd, name, result)
            records[name] = encoded(result)
            report["hosts"][index].update(status="prepared", files=result["files"], packets=result["packets"])
        mapping = {"schema": "acfs.swarm-fleet-batches.v1", "hosts": [
            {"id": e["host"]["id"], "batch": e["output"] + "/bundle/batch.json"} for e in plan["hosts"]]}
        guard()
        fleet.state_unchanged(fd, plan, records)
        fleet.publish(fd, "batches.json", mapping)
        records["batches.json"] = encoded(mapping)
        fleet.state_unchanged(fd, plan, records)
    report.update(status="prepared", batches_file=str(path / "batches.json"))
    return report, 0


def main(arguments=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--launch-state", required=True)
    parser.add_argument("--work", required=True, help="Private explicit fleet work spec, including selected task briefs")
    parser.add_argument("--known-hosts", required=True)
    parser.add_argument("--identity-file", required=True)
    parser.add_argument("--state-dir", required=True, help="New private preparation journal; separate from launch state")
    parser.add_argument("--timeout", type=int, default=360, help="Per SSH operation timeout, 1..600 seconds")
    parser.add_argument("--prepare", action="store_true", help="Upload briefs and prepare remote bundles; never sends prompts")
    parser.add_argument("--accept-plan")
    args = parser.parse_args(arguments)
    require(args.prepare == (args.accept_plan is not None), "prepare_requires_exact_approval")
    known = fleet.read_input(args.known_hosts, private=False)
    identity = fleet.read_input(args.identity_file)
    work = decode(fleet.read_input(args.work))
    with launch_context(args.launch_state, known, identity) as (launch, history, records, guard):
        plan = build_plan(work, launch, history, records, args.state_dir, args.timeout)
        fleet.state_preflight(plan)
        if args.prepare:
            report, code = prepare(plan, args.accept_plan, transport(known, identity, args.timeout), guard)
        else:
            report, code = report_for(plan), 0
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
        code = str(exc) if isinstance(exc, fleet.Refused) else "preserve_preparation_state_and_remote_outputs"
        print(encoded({"schema": SCHEMA, "status": "error", "code": code,
            "starts_agents": False, "sends_prompt": False, "preparation_attempted": PREPARATION_ATTEMPTED}).decode(), end="")
        return 128 + exc.signum if isinstance(exc, fleet.Interrupted) else 2


if __name__ == "__main__":
    sys.exit(cli())
