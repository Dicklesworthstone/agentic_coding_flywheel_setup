#!/usr/bin/env bash
# Explicit remote measurement; never an agent launcher or inventory auto-updater.
set -euo pipefail
if [[ $EUID -eq 0 ]]; then
    export PATH=/usr/sbin:/usr/bin:/sbin:/bin
fi
exec python3 -I - "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" "$@" <<'PY'
import argparse
import concurrent.futures
import copy
import datetime as dt
import fcntl
import hashlib
import ipaddress
import json
import os
import pathlib
import re
import selectors
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time

LIMIT = 1048576
MAX_HOSTS = 32
ID = re.compile(r"[a-z0-9][a-z0-9._-]{0,62}\Z")
USER = re.compile(r"[a-z_][a-z0-9_-]{0,31}\Z")
STOP = threading.Event()


class Refused(Exception):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


def refuse(code):
    raise Refused(code)


def encoded(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":"),
                       ensure_ascii=True, allow_nan=False) + "\n").encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def unique(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            refuse("duplicate_json_key")
        value[key] = item
    return value


def decode(data):
    if not data or len(data) > LIMIT:
        refuse("input_size_invalid")
    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=unique,
                           parse_constant=lambda _: refuse("invalid_json"))
        pending, nodes = [(value, 0)], 0
        while pending:
            item, depth = pending.pop()
            nodes += 1
            if depth > 24 or nodes > 30000:
                refuse("input_complexity_exceeded")
            if isinstance(item, dict):
                pending.extend((key, depth + 1) for key in item)
                pending.extend((child, depth + 1) for child in item.values())
            elif isinstance(item, list):
                pending.extend((child, depth + 1) for child in item)
            elif isinstance(item, str) and any(0xD800 <= ord(c) <= 0xDFFF for c in item):
                refuse("invalid_json")
        encoded(value)  # Also reject overflowed floating-point JSON numbers.
        return value
    except (ValueError, UnicodeError, RecursionError, OverflowError):
        refuse("invalid_json")


def read_snapshot(path, private=False):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        if (not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or
                before.st_size > LIMIT or before.st_mode & 0o022 or
                (private and (before.st_uid != os.getuid() or before.st_mode & 0o077))):
            refuse("unsafe_input_file")
        data = bytearray()
        while len(data) <= LIMIT:
            part = os.read(fd, min(65536, LIMIT + 1 - len(data)))
            if not part:
                break
            data.extend(part)
        after = os.fstat(fd)
        if (len(data) != before.st_size or before.st_size != after.st_size or
                before.st_mtime_ns != after.st_mtime_ns or before.st_ctime_ns != after.st_ctime_ns):
            refuse("input_changed")
        return bytes(data)
    finally:
        os.close(fd)


def count(value, maximum=1000000, minimum=0):
    if type(value) is not int or not minimum <= value <= maximum:
        refuse("invalid_probe_counter")
    return value


def targets_from(value, inventory):
    if (type(value) is not dict or set(value) != {"schema", "targets"} or
            value["schema"] != "acfs.swarm-probe-targets.v1" or
            type(value["targets"]) is not list or not 1 <= len(value["targets"]) <= MAX_HOSTS):
        refuse("invalid_targets")
    known = {h["id"]: h for h in inventory["hosts"]}
    found, endpoints, result = set(), set(), []
    for target in value["targets"]:
        if type(target) is not dict or set(target) != {"id", "host", "user", "port"}:
            refuse("invalid_target")
        ident, host, user, port = (target[k] for k in ("id", "host", "user", "port"))
        if (type(ident) is not str or not ID.fullmatch(ident) or ident in found or ident not in known or
                type(user) is not str or not USER.fullmatch(user) or type(host) is not str):
            refuse("invalid_target")
        count(port, 65535, 1)
        try:
            canonical = ipaddress.ip_address(host).compressed
        except ValueError:
            if (len(host) > 253 or not host or host.endswith(".") or
                    any(not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label)
                        for label in host.split("."))):
                refuse("invalid_target")
            if re.fullmatch(r"[0-9.]+", host):
                refuse("invalid_target")
            canonical = host
        if canonical != host or host in endpoints:
            refuse("duplicate_or_noncanonical_endpoint")
        workload = known[ident]["capacity"].get("workload") or (inventory.get("defaults") or {}).get("workload", "standard")
        if workload not in ("light", "standard", "heavy"):
            refuse("invalid_workload")
        found.add(ident)
        endpoints.add(host)
        result.append({**target, "workload": workload})
    return sorted(result, key=lambda t: t["id"])


def environment():
    # SSH's configuration, forwarding and remote environment are disabled below.
    # A caller's existing local authentication agent may authenticate SSH itself.
    env = {k: os.environ[k] for k in ("HOME", "USER", "LOGNAME", "SSH_AUTH_SOCK") if k in os.environ}
    env.update(PATH="/usr/local/bin:/usr/bin:/bin", LANG="C.UTF-8", LC_ALL="C.UTF-8")
    return env


def capture(argv, timeout, input_bytes=None, pass_fds=(), stop=None):
    """Bound bytes, wall time and the entire producing process group."""
    stop = STOP if stop is None else stop
    if stop.is_set():
        refuse("cancelled")
    process = subprocess.Popen(argv, stdin=subprocess.PIPE if input_bytes is not None else subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=environment(),
                               pass_fds=pass_fds, start_new_session=True)
    data = bytearray()
    deadline = time.monotonic() + timeout
    offset = 0
    try:
        with selectors.DefaultSelector() as selector:
            os.set_blocking(process.stdout.fileno(), False)
            selector.register(process.stdout, selectors.EVENT_READ)
            if input_bytes is not None:
                os.set_blocking(process.stdin.fileno(), False)
                selector.register(process.stdin, selectors.EVENT_WRITE)
            while selector.get_map():
                if stop.is_set():
                    refuse("cancelled")
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    refuse("probe_timeout")
                for key, _ in selector.select(min(remaining, 0.1)):
                    if key.fileobj is process.stdin:
                        try:
                            offset += os.write(key.fd, input_bytes[offset:offset + 65536])
                        except BrokenPipeError:
                            offset = len(input_bytes)
                        if offset == len(input_bytes):
                            selector.unregister(key.fileobj)
                            process.stdin.close()
                    else:
                        chunk = os.read(key.fd, min(65536, LIMIT + 1 - len(data)))
                        if not chunk:
                            selector.unregister(key.fileobj)
                        data.extend(chunk)
                        if len(data) > LIMIT:
                            refuse("probe_output_too_large")
            while process.poll() is None:
                if stop.is_set():
                    refuse("cancelled")
                if time.monotonic() >= deadline:
                    refuse("probe_timeout")
                time.sleep(0.01)
        if process.returncode != 0:
            refuse("probe_command_failed")
        return bytes(data)
    finally:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=5)
        process.stdout.close()
        if process.stdin is not None:
            process.stdin.close()


def validate_inventory(value, library):
    # The normal inventory validator remains the redaction/schema authority.
    # Sourcing with --help terminates its dispatcher without loading an inventory.
    bridge = ('source "$1" --help >/dev/null; '
              'data=$(cat); swarm_inventory_validation_json "$(command -v jq)" "$data" "snapshot"')
    result = decode(capture(["/bin/bash", "--noprofile", "--norc", "-c", bridge,
                             "acfs-fleet-validator", str(library / "swarm_inventory.sh")], 15, encoded(value)))
    if result.get("status") != "pass":
        refuse("inventory_validation_failed")


def ssh_argv(target, known_fd, identity=None, ssh="/usr/bin/ssh"):
    command = ('exec /bin/bash "$HOME/.acfs/scripts/lib/swarm_inventory.sh" '
               'probe-local --json --host-id {} --workload {}').format(
        target["id"], target["workload"])
    argv = [ssh, "-F", "/dev/null", "-T", "-n", "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=yes", "-o", f"UserKnownHostsFile=/proc/{os.getpid()}/fd/{known_fd}",
            "-o", "GlobalKnownHostsFile=/dev/null", "-o", "UpdateHostKeys=no",
            "-o", "ConnectionAttempts=1", "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2",
            "-o", "ForwardAgent=no", "-o", "ForwardX11=no", "-o", "ClearAllForwardings=yes",
            "-o", "ControlMaster=no", "-o", "ControlPath=none", "-o", "PermitLocalCommand=no",
            "-o", "ProxyCommand=none", "-o", "ProxyJump=none", "-o", "RemoteCommand=none",
            "-o", "SendEnv=-*", "-p", str(target["port"]), "-l", target["user"]]
    if identity is not None:
        argv += ["-o", "IdentitiesOnly=yes", "-i", identity]
    return argv + ["--", target["host"], command]


def timestamp(value):
    if type(value) is not str:
        refuse("probe_timestamp_invalid")
    try:
        moment = dt.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
    except ValueError:
        refuse("probe_timestamp_invalid")
    if moment.strftime("%Y-%m-%dT%H:%M:%SZ") != value:
        refuse("probe_timestamp_invalid")
    return moment.timestamp()


def observation(data, target, started, finished):
    value = decode(data)
    if (type(value) is not dict or type(value.get("schema_version")) is not int or value["schema_version"] != 1 or
            type(value.get("hosts")) is not list or len(value["hosts"]) != 1):
        refuse("probe_schema_invalid")
    host = value["hosts"][0]
    try:
        if type(host) is not dict or host["id"] != target["id"] or host["probe_source"] != "acfs swarm inventory probe-local":
            refuse("probe_identity_mismatch")
        observed = timestamp(host["last_probe_at"])
        # Stale, future-dated and replayed observations cannot refresh inventory.
        if not started - 60 <= observed <= finished:
            refuse("probe_timestamp_invalid")
        resource = {k: count(host["resources"][k], 2**40, 0 if k == "disk_available_mib" else 1)
                    for k in ("cpu_count", "mem_total_mib", "disk_available_mib")}
        cap = host["capacity"]
        recommended, safe = count(cap["recommended_agents"]), count(cap["safe_agents"])
        local = host["local_observation"]
        if (cap["workload"] != target["workload"] or recommended > safe or
                local["capacity_status"] not in ("pass", "warn", "fail") or
                (local["capacity_status"] == "fail" and safe != 0) or
                type(local["ntm_available"]) is not bool or type(local["rch_available"]) is not bool or
                local["live_admission_checked"] is not False):
            refuse("probe_evidence_invalid")
        # Copy only reviewed scalar fields. Remote policy, notes, names and any
        # extra output never become local inventory authority or persisted logs.
        return {"resources": resource, "capacity": {"workload": target["workload"],
                "recommended_agents": recommended, "safe_agents": safe, "source": "acfs capacity --json"},
                "last_probe_at": host["last_probe_at"],
                "local_observation": {k: local[k] for k in
                    ("capacity_status", "ntm_available", "rch_available", "live_admission_checked")}}
    except (KeyError, TypeError):
        refuse("probe_evidence_invalid")


def probe_one(target, known_fd, timeout, identity=None, ssh="/usr/bin/ssh"):
    started = time.time()
    try:
        data = capture(ssh_argv(target, known_fd, identity, ssh), timeout)
        return {"id": target["id"], "status": "measured",
                "observation": observation(data, target, started, time.time())}
    except Refused as exc:
        return {"id": target["id"], "status": "failed", "code": exc.code}
    except (OSError, subprocess.SubprocessError):
        return {"id": target["id"], "status": "failed", "code": "probe_unavailable"}


def merge(inventory, results):
    candidate = copy.deepcopy(inventory)
    hosts = {host["id"]: host for host in candidate["hosts"]}
    for result in results:
        host = hosts[result["id"]]
        host["probe_source"] = "acfs swarm inventory probe-fleet"
        if result["status"] == "measured":
            fresh = result["observation"]
            host["resources"].update(fresh["resources"])
            host["capacity"].update(fresh["capacity"])
            host["last_probe_at"] = fresh["last_probe_at"]
            host["local_observation"] = fresh["local_observation"]
            host["ntm"]["can_launch"] = host["ntm"].get("can_launch") is True and fresh["local_observation"]["ntm_available"]
        else:
            # A failed refresh must not leave yesterday's positive recommendation.
            # Preserve operator status/role and launch permission for later review.
            host["last_probe_at"] = None
            host["capacity"].update(recommended_agents=0, safe_agents=0)
            host["local_observation"] = {"capacity_status": "fail", "live_admission_checked": False,
                                          "probe_error": result["code"]}
    candidate["updated_at"] = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return candidate


def output_parent(path):
    target = pathlib.Path(os.path.abspath(path))
    if target.name in ("", ".", ".."):
        refuse("output_invalid")
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in target.parts[1:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
        info = os.fstat(fd)
        if info.st_uid != os.getuid() or info.st_mode & 0o022:
            refuse("output_directory_unsafe")
        try:
            os.stat(target.name, dir_fd=fd, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            refuse("output_exists")
        return fd, target.name
    except BaseException:
        os.close(fd)
        raise


def publish(fd, name, data):
    # Reserve once; interruption leaves evidence, never a silently replaced file.
    out = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
    with os.fdopen(out, "wb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    os.fsync(fd)


def parser():
    p = argparse.ArgumentParser(description="Preview or explicitly collect capacity from named, host-key-verified SSH targets. No agents are started.")
    p.add_argument("--inventory", required=True)
    p.add_argument("--targets", required=True, help="Private acfs.swarm-probe-targets.v1 JSON; never merged into inventory")
    p.add_argument("--known-hosts", required=True, help="Existing trusted OpenSSH known_hosts file; unknown hosts are refused")
    p.add_argument("--identity-file", help="Optional existing SSH identity; no login or credential collection")
    p.add_argument("--parallel", type=int, default=4, choices=range(1, 9), metavar="1-8")
    p.add_argument("--timeout", type=int, default=45, choices=range(1, 121), metavar="1-120")
    p.add_argument("--probe", action="store_true", help="Perform the reviewed SSH measurements")
    p.add_argument("--accept-plan", help="Exact plan digest printed by preview")
    p.add_argument("--output", help="Create a NEW inventory snapshot; never update the input")
    p.add_argument("--json", action="store_true")
    return p


def main(args, library):
    options = parser().parse_args(args)
    if options.probe != bool(options.accept_plan) or (options.probe and not options.output):
        refuse("probe_requires_approval_and_new_output")
    inventory_bytes = read_snapshot(options.inventory)
    inventory = decode(inventory_bytes)
    validate_inventory(inventory, library)
    targets = targets_from(decode(read_snapshot(options.targets, private=True)), inventory)
    known = read_snapshot(options.known_hosts)
    if not known.strip():
        refuse("known_hosts_empty")
    # Never serialize an identity path or key. Approved bytes are held in an
    # anonymous private snapshot during execution, not reopened through a path.
    identity_bytes = read_snapshot(options.identity_file, private=True) if options.identity_file else None
    identity_hash = digest(identity_bytes) if identity_bytes is not None else None
    plan = {"schema": "acfs.swarm-fleet-probe-plan.v1", "inventory_sha256": digest(inventory_bytes),
            "targets_sha256": digest(encoded(targets)), "known_hosts_sha256": digest(known),
            "identity_sha256": identity_hash, "parallel": options.parallel, "timeout_seconds": options.timeout,
            "hosts": [{"id": t["id"], "workload": t["workload"]} for t in targets],
            "protocol": "ssh-strict-probe-local-v1", "advisory_only": True,
            "runtime_sha256": digest(read_snapshot(library / "swarm_fleet_probe.sh")),
            "inventory_policy_sha256": digest(read_snapshot(library / "swarm_inventory.sh"))}
    plan_hash = digest(encoded(plan))
    if not options.probe:
        return {"status": "planned", "plan_sha256": plan_hash, "plan": plan,
                "next": "Review the inventory and target file, then repeat with --probe --accept-plan DIGEST --output NEW_FILE"}, 0
    if options.accept_plan != plan_hash:
        refuse("plan_changed")
    if sys.platform != "linux":
        refuse("linux_required")
    parent, name = output_parent(options.output)
    try:
        fcntl.flock(parent, fcntl.LOCK_EX | fcntl.LOCK_NB)
        # Pin reviewed host keys to one inherited anonymous file for ALL SSH calls.
        with tempfile.TemporaryFile() as trust, tempfile.TemporaryFile() as identity:
            trust.write(known)
            trust.flush()
            identity_path = None
            if identity_bytes is not None:
                identity.write(identity_bytes)
                identity.flush()
                identity_path = f"/proc/{os.getpid()}/fd/{identity.fileno()}"
            results = []
            with concurrent.futures.ThreadPoolExecutor(max_workers=options.parallel) as pool:
                pending = [pool.submit(probe_one, target, trust.fileno(), options.timeout, identity_path)
                           for target in targets]
                for future in pending:
                    results.append(future.result())
        if STOP.is_set():
            refuse("cancelled")
        candidate = merge(inventory, results)
        validate_inventory(candidate, library)
        if STOP.is_set():
            refuse("cancelled")
        publish(parent, name, encoded(candidate))
        successes = sum(result["status"] == "measured" for result in results)
        return {"status": "measured" if successes == len(results) else "partial" if successes else "failed",
                "plan_sha256": plan_hash, "inventory_sha256": digest(encoded(candidate)),
                "advisory_only": True, "live_admission_checked": False,
                "results": [{k: v for k, v in result.items() if k != "observation"} for result in results],
                "snapshot_created": True, "agents_started": False}, 0 if successes == len(results) else 1
    finally:
        os.close(parent)


if __name__ == "__main__":
    library = pathlib.Path(sys.argv[1])
    cancelled = [0]
    def stop(signum, _frame):
        cancelled[0] = 128 + signum
        STOP.set()
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    try:
        report, code = main(sys.argv[2:], library)
    except (Refused, OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError) as exc:
        report, code = {"status": "failed", "code": exc.code if isinstance(exc, Refused) else "probe_inputs_or_output_unavailable",
                        "agents_started": False}, cancelled[0] or 2
    if "--json" in sys.argv[2:]:
        print(encoded(report).decode(), end="")
    else:
        print("Fleet probe: " + report["status"])
        if "plan_sha256" in report:
            print("Plan digest: " + report["plan_sha256"])
        for item in report.get("results", report.get("plan", {}).get("hosts", [])):
            print(item["id"] + ": " + item.get("status", item.get("workload", "unknown")) +
                  (" (" + item["code"] + ")" if "code" in item else ""))
        if "next" in report:
            print(report["next"])
        if "code" in report:
            print("Reason: " + report["code"])
        print("No agents started. Re-run live admission on each host before launch.")
    sys.exit(cancelled[0] or code)
PY
