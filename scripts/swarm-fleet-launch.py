#!/usr/bin/env python3
"""Preview and explicitly launch dedicated native-agent sessions on a reviewed fleet.

The installed single-host launcher remains the admission and lifecycle authority.
No inventory target total, remote command string, or saved positive capacity is
accepted as permission to spawn. Requires Linux, OpenSSH, and existing ACFS hosts.
"""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import ipaddress
import json
import math
import os
from pathlib import Path
import re
import selectors
import shlex
import signal
import stat
import subprocess
import sys
import tempfile
import time

SCHEMA = "acfs.swarm-fleet-launch.v1"
SPEC_SCHEMA = "acfs.swarm-fleet-launch-spec.v1"
STATE_SCHEMA = "acfs.swarm-fleet-launch-state.v1"
NATIVE_SCHEMA = "acfs.swarm-launch.v1"
LIMIT = 1024 * 1024
POLICY = "explicit-new-sessions-strict-ssh-native-admission-v1"
PROFILES = ("balanced", "codex-heavy", "review-heavy", "docs-heavy")
WORKLOADS = ("light", "standard", "heavy")


class Refused(Exception):
    """Only fixed, non-sensitive error codes cross the reporting boundary."""


class Interrupted(Exception):
    def __init__(self, signum):
        self.signum = signum


def require(condition, code):
    if not condition:
        raise Refused(code)


def encoded(value):
    return (json.dumps(value, sort_keys=True, ensure_ascii=True, indent=2,
                       allow_nan=False) + "\n").encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def decode(data):
    require(len(data) <= LIMIT, "json_size_limit")
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "duplicate_json_field")
            result[key] = value
        return result
    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=pairs,
                           parse_constant=lambda _: (_ for _ in ()).throw(Refused("invalid_json_number")))
        pending, count = [(value, 0)], 0
        while pending:
            item, depth = pending.pop()
            count += 1
            require(depth <= 32 and count <= 50000, "json_complexity_limit")
            if type(item) is dict:
                pending.extend((v, depth + 1) for v in item.values())
                pending.extend((k, depth + 1) for k in item)
            elif type(item) is list:
                pending.extend((v, depth + 1) for v in item)
            elif type(item) is float:
                require(math.isfinite(item), "invalid_json_number")
            elif type(item) is str:
                item.encode("utf-8", "strict")
        return value
    except (ValueError, UnicodeError, RecursionError):
        raise Refused("invalid_json") from None


def matches(pattern, value):
    return type(value) is str and re.fullmatch(pattern, value) is not None


def absolute_path(value):
    require(type(value) is str and value.startswith("/") and value != "/"
            and len(value) <= 4096 and not re.search(r"[\x00-\x1f\x7f]", value)
            and all(part not in ("", ".", "..") for part in value.split("/")[1:]),
            "invalid_absolute_path")
    return value


def validate_spec(value):
    require(type(value) is dict and set(value) == {"schema", "hosts"}
            and value["schema"] == SPEC_SCHEMA, "invalid_fleet_spec")
    hosts = value["hosts"]
    require(type(hosts) is list and 1 <= len(hosts) <= 16, "select_one_to_sixteen_hosts")
    ids, endpoints, names = set(), set(), set()
    result, total = [], 0
    for host in hosts:
        require(type(host) is dict and set(host) == {"id", "host", "user", "port", "request"},
                "invalid_fleet_host")
        require(matches(r"[a-z][a-z0-9_-]{0,63}", host["id"]) and host["id"] not in ids,
                "invalid_or_duplicate_host_id")
        address = host["host"]
        require(type(address) is str and len(address) <= 253, "invalid_host_address")
        endpoint = address
        try:
            ip = ipaddress.ip_address(address)
            require(str(ip) == address and "%" not in address and not ip.is_unspecified
                    and not ip.is_multicast, "invalid_host_address")
            endpoint = str(getattr(ip, "ipv4_mapped", None) or ip)
        except ValueError:
            require(all(matches(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", p)
                        for p in address.split(".")) and not matches(r"[0-9.]+", address),
                    "invalid_host_address")
        require(endpoint not in endpoints, "duplicate_endpoint_host")
        require(matches(r"[a-z_][a-z0-9_-]{0,31}", host["user"]) and host["user"] != "root",
                "nonroot_remote_user_required")
        require(type(host["port"]) is int and 1 <= host["port"] <= 65535, "invalid_ssh_port")
        req = host["request"]
        require(type(req) is dict and set(req) == {"repo", "session", "receipt", "agents", "profile", "workload", "accept_warnings"},
                "invalid_native_request")
        absolute_path(req["repo"])
        absolute_path(req["receipt"])
        require(matches(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", req["session"])
                and "--" not in req["session"], "invalid_session_name")
        require(req["profile"] in PROFILES and req["workload"] in WORKLOADS
                and type(req["accept_warnings"]) is bool, "invalid_admission_options")
        require(type(req["agents"]) is list and 1 <= len(req["agents"]) <= 32,
                "select_one_to_thirty_two_agents_per_host")
        for agent in req["agents"]:
            require(type(agent) is dict and set(agent) == {"agent_name", "agent_type"}
                    and matches(r"[A-Za-z][A-Za-z0-9_-]{0,63}", agent["agent_name"])
                    and agent["agent_type"] in ("claude", "codex"), "invalid_agent")
            name = agent["agent_name"].lower()
            require(name not in names, "duplicate_fleet_agent_name")
            names.add(name)
        total += len(req["agents"])
        ids.add(host["id"])
        endpoints.add(endpoint)
        result.append(host)
    require(total <= 256, "fleet_agent_limit")
    # Copy to detach the canonical plan from mutable caller data.
    return decode(encoded({"schema": SPEC_SCHEMA, "hosts": result}))


@contextmanager
def directory_fd(path, private=False):
    """Walk by descriptor; reject links and other users' writable directories."""
    path = Path(os.path.abspath(path))
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parts[1:]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
            info = os.fstat(fd)
            sticky_root = info.st_uid == 0 and info.st_mode & stat.S_ISVTX
            require(info.st_uid in (0, os.geteuid()) and (not info.st_mode & 0o022 or sticky_root),
                    "unsafe_directory")
        info = os.fstat(fd)
        require(info.st_uid == os.geteuid() and not info.st_mode & (0o077 if private else 0o022),
                "directory_ownership_or_permissions")
        yield fd
    finally:
        os.close(fd)


def read_at(fd, name, private=True, optional=False):
    try:
        handle = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    except FileNotFoundError:
        if optional:
            return None
        raise Refused("required_file_missing") from None
    with os.fdopen(handle, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
                and info.st_uid == os.geteuid() and not info.st_mode & (0o077 if private else 0o022),
                "unsafe_input_file")
        raw = stream.read(LIMIT + 1)
        require(len(raw) <= LIMIT, "input_size_limit")
        return raw


def read_input(path, private=True):
    path = Path(os.path.abspath(path))
    with directory_fd(path.parent) as fd:
        return read_at(fd, path.name, private=private)


def publish(fd, name, value):
    raw = encoded(value)
    require(len(raw) <= LIMIT, "state_size_limit")
    handle = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
    with os.fdopen(handle, "wb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    os.fsync(fd)


def native_hash(request):
    return digest(encoded({"schema": NATIVE_SCHEMA, "request": request}))


def build_plan(spec, known_hosts, identity, state_dir, timeout):
    require(type(timeout) is int and 1 <= timeout <= 600, "timeout_must_be_1_to_600")
    require(known_hosts and identity, "empty_ssh_trust_input")
    return {"schema": SCHEMA, "policy": POLICY, "spec": validate_spec(spec),
            "known_hosts_sha256": digest(known_hosts), "identity_sha256": digest(identity),
            "state_directory": str(Path(os.path.abspath(state_dir))), "timeout_seconds": timeout}


def native_argv(request, mode):
    if mode == "reconcile":
        return ["--reconcile", "--receipt", request["receipt"]]
    argv = ["--repo", request["repo"], "--session", request["session"], "--receipt", request["receipt"],
            "--profile", request["profile"], "--workload", request["workload"]]
    for agent in request["agents"]:
        argv += ["--agent", agent["agent_name"] + ":" + agent["agent_type"]]
    if request["accept_warnings"]:
        argv.append("--accept-warnings")
    if mode == "launch":
        argv += ["--expect-sha256", native_hash(request), "--launch"]
    return argv


def ssh_argv(host, mode, known_fd, identity_fd, ssh="/usr/bin/ssh"):
    launcher = '"$HOME/.acfs/scripts/lib/swarm_launch.sh"'
    # The remote installed launcher is fixed. Never execute a command returned
    # by a preview or permit a spec to supply an executable/SSH option.
    command = ('test "$(/usr/bin/id -u)" != 0 && test -f ' + launcher +
               ' && test ! -L ' + launcher + ' && exec /bin/bash --noprofile --norc -p ' +
               launcher + " " + shlex.join(native_argv(host["request"], mode)))
    options = ["BatchMode=yes", "StrictHostKeyChecking=yes", "GlobalKnownHostsFile=/dev/null",
               "UpdateHostKeys=no", "VerifyHostKeyDNS=no", "ConnectionAttempts=1", "ConnectTimeout=10",
               "ServerAliveInterval=5", "ServerAliveCountMax=2", "ForwardAgent=no", "ForwardX11=no",
               "ClearAllForwardings=yes", "ControlMaster=no", "ControlPath=none", "PermitLocalCommand=no",
               "ProxyCommand=none", "ProxyJump=none", "RemoteCommand=none", "SendEnv=-*", "IdentitiesOnly=yes",
               f"UserKnownHostsFile=/proc/{os.getpid()}/fd/{known_fd}"]
    argv = [ssh, "-F", "/dev/null", "-T", "-n"]
    for option in options:
        argv += ["-o", option]
    return argv + ["-i", f"/proc/{os.getpid()}/fd/{identity_fd}", "-p", str(host["port"]),
                   "-l", host["user"], "--", host["host"], command]


def capture(argv, timeout, env):
    """Bound both pipes in memory and terminate only our own SSH process group."""
    process = subprocess.Popen(argv, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=True)
    output, size = bytearray(), 0
    deadline = time.monotonic() + timeout
    try:
        with selectors.DefaultSelector() as selector:
            for stream in (process.stdout, process.stderr):
                os.set_blocking(stream.fileno(), False)
                selector.register(stream, selectors.EVENT_READ)
            while selector.get_map() or process.poll() is None:
                remaining = deadline - time.monotonic()
                require(remaining > 0, "ssh_timeout")
                for key, _ in selector.select(min(remaining, 0.05)):
                    chunk = os.read(key.fd, 65536)
                    if not chunk:
                        selector.unregister(key.fileobj)
                    size += len(chunk)
                    require(size <= LIMIT, "ssh_output_limit")
                    if key.fileobj is process.stdout:
                        output.extend(chunk)
                if not selector.get_map() and process.poll() is None:
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


@contextmanager
def transport(known_hosts, identity, timeout, *, runner=capture, ssh="/usr/bin/ssh"):
    require(sys.platform == "linux" and Path("/proc/self/fd").is_dir(), "linux_controller_required")
    require(Path(ssh).is_file() and os.access(ssh, os.X_OK), "system_openssh_required")
    env = {"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"}
    # An existing local agent may unlock the explicitly selected identity. No
    # agent is forwarded, and IdentitiesOnly excludes unrelated agent keys.
    sock = os.environ.get("SSH_AUTH_SOCK")
    if sock and os.path.isabs(sock) and not re.search(r"[\x00-\x1f\x7f]", sock):
        env["SSH_AUTH_SOCK"] = sock
    with tempfile.TemporaryFile() as known, tempfile.TemporaryFile() as key:
        known.write(known_hosts)
        key.write(identity)
        known.flush()
        key.flush()
        yield lambda host, mode: runner(ssh_argv(host, mode, known.fileno(), key.fileno(), ssh), timeout, env)


def valid_targets(value, request):
    require(type(value) is list and len(value) == len(request["agents"]), "native_targets_invalid")
    targets, panes, session = [], set(), None
    fields = {"slot", "agent_name", "agent_type", "pane", "pane_pid", "server_pid", "session_id", "session_created"}
    for slot, (target, agent) in enumerate(zip(value, request["agents"]), 1):
        require(type(target) is dict and fields <= set(target) and type(target["slot"]) is int
                and target["slot"] == slot and target["agent_name"] == agent["agent_name"]
                and target["agent_type"] == agent["agent_type"] and matches(r"%[0-9]+", target["pane"])
                and matches(r"\$[0-9]+", target["session_id"])
                and all(matches(r"[0-9]+", target[k]) for k in ("pane_pid", "server_pid", "session_created")),
                "native_targets_invalid")
        require(target["pane"] not in panes, "native_targets_invalid")
        identity = (target["session_id"], target["session_created"], target["server_pid"])
        require(session is None or session == identity, "native_targets_invalid")
        session = identity
        panes.add(target["pane"])
        targets.append({k: target[k] for k in sorted(fields)})
    return targets


def remote_result(host, mode, invoke):
    """Project only validated evidence; never copy raw remote diagnostics."""
    row = {"id": host["id"], "status": "unconfirmed", "code": "remote_unconfirmed"}
    try:
        code, raw = invoke(host, mode)
        require(type(code) is int and type(raw) is bytes, "invalid_transport_result")
        value = decode(raw)
        req = host["request"]
        require(type(value) is dict and value.get("schema") == NATIVE_SCHEMA and value.get("request") == req
                and value.get("work_dispatched") is False and value.get("authentication_verified") is False
                and value.get("agent_mail_registered") is False, "native_response_invalid")
        if mode == "preview":
            require(code == 0 and value.get("status") == "preview" and value.get("starts_agents") is False
                    and value.get("review_sha256") == native_hash(req)
                    and value.get("reconciled_only", False) is False, "native_preview_refused_or_existing")
            admission = value.get("admission")
            require(type(admission) is dict and admission.get("status") in ("pass", "warn")
                    and admission.get("recommendation") in ("launch", "launch_with_review")
                    and all(type(admission.get(k)) is int and admission[k] >= len(req["agents"])
                            for k in ("safe_agents", "recommended_agents"))
                    and (admission["status"] == "pass" or req["accept_warnings"]), "native_admission_invalid")
            row.update(status="admitted", code="live_admission_passed", admission={
                k: admission[k] for k in ("status", "recommendation", "safe_agents", "recommended_agents")})
        else:
            require(code == 0 and value.get("status") == "ready" and type(value.get("starts_agents")) is bool,
                    "native_launch_unconfirmed")
            require(value.get("original_launch_verified", True) is True and "recovery_provenance" not in value,
                    "adopted_session_requires_manual_review")
            if mode == "reconcile":
                require(value.get("starts_agents") is False and value.get("reconciled_only") is True,
                        "native_reconciliation_invalid")
            else:
                require(value.get("review_sha256") == native_hash(req), "native_request_digest_mismatch")
            row.update(status="ready", code="native_targets_verified", targets=valid_targets(value.get("targets"), req))
    except Refused as exc:
        row["code"] = str(exc)
    except (OSError, subprocess.SubprocessError):
        row["code"] = "ssh_unavailable"
    return row


def state_preflight(plan):
    path = Path(plan["state_directory"])
    require(path.name not in ("", ".", ".."), "invalid_state_directory")
    with directory_fd(path.parent) as parent:
        try:
            os.stat(path.name, dir_fd=parent, follow_symlinks=False)
        except FileNotFoundError:
            return
        raise Refused("state_already_exists_preserve_for_recovery")


@contextmanager
def new_state(plan):
    path = Path(plan["state_directory"])
    with directory_fd(path.parent) as parent:
        os.mkdir(path.name, 0o700, dir_fd=parent)
        os.fsync(parent)
    with directory_fd(path, private=True) as fd:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        publish(fd, "intent.json", {"schema": STATE_SCHEMA, "plan": plan})
        yield fd


def host_intent(plan, host):
    return {"schema": STATE_SCHEMA, "plan_sha256": digest(encoded(plan)), "host_id": host["id"],
            "request_sha256": native_hash(host["request"])}


def execute(plan, mode, approval, invoke):
    require(mode in ("preview", "launch"), "invalid_fleet_operation")
    plan_sha = digest(encoded(plan))
    require(mode != "launch" or approval == plan_sha, "approval_mismatch_preview_again")
    state_preflight(plan)
    hosts = plan["spec"]["hosts"]
    report = {"schema": SCHEMA, "operation": mode, "plan_sha256": plan_sha, "status": "blocked",
              "starts_agents": False, "work_dispatched": False, "authentication_verified": False,
              "allocation_semantics": "explicit_new_dedicated_sessions",
              "requested_new_agents": sum(len(h["request"]["agents"]) for h in hosts),
              "hosts": [remote_result(h, "preview", invoke) for h in hosts]}
    if any(row["status"] != "admitted" for row in report["hosts"]):
        return report, 1
    if mode == "preview":
        report["status"] = "preview"
        return report, 0
    with new_state(plan) as fd:
        report["hosts"] = [{"id": h["id"], "status": "not_attempted", "code": "prior_host_not_confirmed"} for h in hosts]
        for index, host in enumerate(hosts):
            # Both local and remote durable intents precede their respective
            # lifecycle boundary. A transport loss is never proof of no spawn.
            publish(fd, host["id"] + ".attempt.json", host_intent(plan, host))
            report["starts_agents"] = True
            result = remote_result(host, "launch", invoke)
            report["hosts"][index] = result
            if result["status"] != "ready":
                report["status"] = "unconfirmed"
                return report, 1
            publish(fd, host["id"] + ".result.json", {**host_intent(plan, host), "targets": result["targets"]})
    report["status"] = "ready"
    return report, 0


def main(arguments=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--spec", required=True, help="Private explicit fleet launch spec; never an inventory placement report")
    parser.add_argument("--known-hosts", required=True, help="Existing independently verified SSH host keys")
    parser.add_argument("--identity-file", required=True, help="Private SSH identity; may use its matching key in the local agent")
    parser.add_argument("--state-dir", required=True, help="New private directory under an existing user-owned parent")
    parser.add_argument("--timeout", type=int, default=360, help="Per SSH operation deadline, 1..600 seconds (default 360)")
    parser.add_argument("--launch", action="store_true", help="Start agents; default is live remote admission preview")
    parser.add_argument("--accept-plan", help="Exact digest from preview; required for --launch")
    args = parser.parse_args(arguments)
    mode = "launch" if args.launch else "preview"
    require((args.accept_plan is not None) == args.launch, "launch_requires_exact_approval")
    known = read_input(args.known_hosts, private=False)
    identity = read_input(args.identity_file)
    plan = build_plan(decode(read_input(args.spec)), known, identity, args.state_dir, args.timeout)
    with transport(known, identity, args.timeout) as invoke:
        report, code = execute(plan, mode, args.accept_plan, invoke)
    print(encoded(report).decode(), end="")
    return code


def cli():
    def stop(signum, _frame):
        raise Interrupted(signum)
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, stop)
    try:
        return main()
    except Interrupted as exc:
        print(encoded({"schema": SCHEMA, "status": "interrupted", "code": "preserve_state_and_remote_receipts",
                       "launch_may_have_occurred": True}).decode(), end="")
        return 128 + exc.signum
    except (Refused, OSError, subprocess.SubprocessError) as exc:
        print(encoded({"schema": SCHEMA, "status": "error", "code": str(exc) if isinstance(exc, Refused)
                       else "local_io_or_process_failure", "launch_may_have_occurred": True}).decode(), end="")
        return 2


if __name__ == "__main__":
    sys.exit(cli())
