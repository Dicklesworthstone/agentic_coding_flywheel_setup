#!/usr/bin/env python3
"""Publish an exactly tested, locally promoted commit to one explicit Git branch.

Preview queries the destination but never pushes. Publication requires its own
approval, an existing expected-old remote branch, and complete passing local test
evidence. A push can activate server hooks/CI/deployments. No automatic retry.
"""
import argparse
from contextlib import contextmanager
import importlib.util
import ipaddress
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit

sys.dont_write_bytecode = True
_helper = Path(__file__).absolute().with_name("swarm-fleet-test.py")
if _helper.is_symlink() or not _helper.is_file():
    raise SystemExit("Required trusted sibling swarm-fleet-test.py is unavailable")
_spec = importlib.util.spec_from_file_location("acfs_publish_tests", _helper)
tests = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tests)
collect, fleet = tests.collect, tests.fleet
require, encoded, decode, digest = fleet.require, fleet.encoded, fleet.decode, fleet.digest
SCHEMA = "acfs.swarm-fleet-publication.v1"
POLICY = "tested-commit-explicit-remote-fast-forward-exact-lease-v1"
PUSH_STARTED = False
STATE_DIRECTORY = None


def branch_ref(branch):
    require(fleet.matches(r"[A-Za-z0-9][A-Za-z0-9_./-]{0,191}", branch), "invalid_publication_branch")
    return "refs/heads/" + branch


def ssh_endpoint(url):
    """No ambient remote name, scp shorthand, proxy, URL rewrite or credential URL."""
    require(type(url) is str and len(url) <= 4096 and url.isascii()
            and not re.search(r"[\x00-\x20\x7f\\%?#]", url), "explicit_canonical_ssh_url_required")
    try:
        parsed = urlsplit(url)
        host, user = parsed.hostname, parsed.username
        port = parsed.port if parsed.port is not None else 22
        require(parsed.scheme == "ssh" and parsed.password is None and host is not None
                and fleet.matches(r"[a-z_][a-z0-9_-]{0,31}", user) and user != "root"
                and 1 <= port <= 65535 and not parsed.query and not parsed.fragment,
                "invalid_publication_ssh_endpoint")
        try:
            address = ipaddress.ip_address(host)
            require(not address.is_unspecified and not address.is_multicast and str(address) == host,
                    "invalid_publication_host")
        except ValueError:
            require(len(host) <= 253 and not re.fullmatch(r"[0-9.]+", host)
                    and all(fleet.matches(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", p)
                            for p in host.split(".")), "invalid_publication_host")
        require(parsed.path.startswith("/") and all(
            fleet.matches(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,254}", p)
            and p not in (".", "..") for p in parsed.path[1:].split("/")),
            "invalid_publication_repository_path")
        authority = "[" + host + "]" if ":" in host else host
        canonical = "ssh://" + user + "@" + authority + ":" + str(port) + parsed.path
        return {"transport": "ssh", "url": canonical, "host": host, "user": user, "port": port}
    except ValueError:
        raise fleet.Refused("invalid_publication_ssh_endpoint") from None


def local_endpoint(path, timeout):
    """Explicit local bare remotes are useful offline and use real receive-pack."""
    path = Path(fleet.absolute_path(str(Path(os.path.abspath(path)))))
    with fleet.directory_fd(path) as fd:
        info = os.fstat(fd)
        git = collect.LocalGit(path, timeout)
        require(git.text(["rev-parse", "--is-bare-repository"]) == "true", "local_remote_must_be_bare")
        require(git.text(["rev-parse", "--absolute-git-dir"]) == str(path), "local_remote_root_mismatch")
        fmt = git.text(["rev-parse", "--show-object-format"])
        require(fmt in ("sha1", "sha256"), "unsupported_remote_object_format")
        return {"transport": "local", "path": str(path), "identity": [info.st_dev, info.st_ino],
                "object_format": fmt}


@contextmanager
def remote_transport(endpoint, known, identity, timeout, *, runner=fleet.capture, ssh="/usr/bin/ssh"):
    """Git never reads the source repository's remote/push/hook configuration."""
    env = dict(collect.LocalGit(Path("/"), timeout).env)
    env["GIT_ATTR_NOSYSTEM"] = "1"
    env["GIT_CONFIG_SYSTEM"] = "/dev/null"
    env["GIT_CONFIG_GLOBAL"] = "/dev/null"
    with tempfile.TemporaryFile() as hosts, tempfile.TemporaryFile() as key:
        if endpoint["transport"] == "ssh":
            require(known and identity, "explicit_ssh_trust_and_identity_required")
            require(Path(ssh).is_file() and os.access(ssh, os.X_OK), "system_openssh_required")
            hosts.write(known); hosts.flush()
            key.write(identity); key.flush()
            # Reuse the fleet's strict SSH policy. Git needs stdin for its wire
            # protocol, unlike command-only fleet calls, so remove only -n.
            host = {**endpoint, "request": {"receipt": "/unused"}}
            base = fleet.ssh_argv(host, "reconcile", hosts.fileno(), key.fileno(), ssh)
            prefix = [arg for arg in base[:base.index("-i")] if arg != "-n"]
            prefix += ["-i", f"/proc/{os.getpid()}/fd/{key.fileno()}"]
            env.update(GIT_ALLOW_PROTOCOL="ssh", GIT_SSH_VARIANT="ssh", GIT_SSH_COMMAND=shlex.join(prefix))
            sock = os.environ.get("SSH_AUTH_SOCK")
            if sock and os.path.isabs(sock) and not re.search(r"[\x00-\x1f\x7f]", sock):
                env["SSH_AUTH_SOCK"] = sock
            url = endpoint["url"]
        else:
            require(not known and not identity, "ssh_inputs_not_used_for_local_remote")
            env["GIT_ALLOW_PROTOCOL"] = "file"
            url = endpoint["path"]

        deadline = time.monotonic() + timeout
        def invoke(mode, reference, old=None, candidate=None, staging=None):
            remaining = deadline - time.monotonic()
            require(remaining > 0, "publication_remote_deadline")
            if endpoint["transport"] == "local":
                require(local_endpoint(endpoint["path"], max(1, int(remaining))) == endpoint,
                        "local_remote_changed")
                local = collect.LocalGit(Path(endpoint["path"]), max(1, int(remaining)))
                require(collect.review_ref_value(local, reference) != "symbolic", "symbolic_local_remote_branch")
            options = ["core.hooksPath=/dev/null", "core.fsmonitor=false", "maintenance.auto=false",
                       "gc.auto=0", "push.followTags=false", "push.recurseSubmodules=no",
                       "push.gpgSign=false", "push.useForceIfIncludes=false", "pack.threads=1"]
            argv = ["/usr/bin/git", "--no-pager", "-C", str(staging if staging is not None else "/")]
            for option in options:
                argv += ["-c", option]
            if mode == "query":
                argv += ["ls-remote", "--exit-code", "--refs", "--", url, reference]
            else:
                require(mode == "push" and staging is not None and collect.oid(old) and collect.oid(candidate),
                        "invalid_publication_operation")
                # The caller proves old is an ancestor of candidate. This exact
                # lease is a compare-and-swap guard, NEVER permission to rebase
                # or discard an old commit. No tracking-ref heuristic is used.
                argv += ["push", "--porcelain", "--no-verify", "--no-follow-tags", "--no-signed",
                         "--recurse-submodules=no", "--force-with-lease=" + reference + ":" + old]
                if endpoint["transport"] == "local":
                    # A local receive-pack otherwise inherits the client's -c
                    # hook suppression through GIT_CONFIG_PARAMETERS. Preserve
                    # receiver-owned hooks and policy, just as SSH transport does.
                    argv += ["--receive-pack=/usr/bin/env -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT /usr/bin/git-receive-pack"]
                argv += ["--", url, candidate + ":" + reference]
            return runner(argv, remaining, env)
        yield invoke


def remote_ref(invoke, reference, width):
    code, raw = invoke("query", reference)
    require(type(code) is int and type(raw) is bytes and len(raw) <= fleet.LIMIT, "invalid_remote_ref_response")
    if code == 2 and not raw:
        return None
    require(code == 0, "remote_ref_query_failed")
    lines = raw.splitlines()
    require(len(lines) == 1, "ambiguous_remote_ref_response")
    value, separator, name = lines[0].partition(b"\t")
    require(separator and name == reference.encode() and len(value) == width
            and re.fullmatch(b"[0-9a-f]+", value), "invalid_remote_ref_response")
    return value.decode("ascii")


def push_accepted(code, raw, reference, candidate):
    require(type(code) is int and code == 0 and type(raw) is bytes and len(raw) <= fleet.LIMIT,
            "push_result_unconfirmed")
    rows = [line.split(b"\t") for line in raw.splitlines() if b"\t" in line]
    require(len(rows) == 1 and len(rows[0]) == 3 and rows[0][0] in (b" ", b"=")
            and rows[0][1] == (candidate + ":" + reference).encode(), "push_result_unconfirmed")
    return rows[0][0] == b" "


def state_parent(path, forbidden):
    path = Path(fleet.absolute_path(str(Path(os.path.abspath(path)))))
    require(all(path != p and p not in path.parents and path not in p.parents for p in forbidden),
            "publication_state_overlaps_input")
    with fleet.directory_fd(path.parent) as fd:
        info = os.fstat(fd)
        return path, [info.st_dev, info.st_ino]


def publish_candidate(run, repository, test_plan, local_branch, remote_branch, old, endpoint,
                      known, identity, state, timeout=90, approval=None, *, check=False, invoke=None):
    global PUSH_STARTED, STATE_DIRECTORY
    PUSH_STARTED, STATE_DIRECTORY = False, None
    local_ref, reference = branch_ref(local_branch), branch_ref(remote_branch)
    require(collect.oid(old), "publication_requires_exact_old_commit")
    require(type(timeout) is int and 1 <= timeout <= 600, "invalid_publication_timeout")
    require(approval is None or fleet.matches(r"[0-9a-f]{64}", approval), "invalid_publication_approval")
    require(type(check) is bool and (not check or approval is not None), "check_requires_original_publication_digest")
    require(type(endpoint) is dict and endpoint.get("transport") in ("ssh", "local"), "invalid_publication_endpoint")
    if endpoint["transport"] == "ssh":
        require(endpoint == ssh_endpoint(endpoint.get("url")) and known and identity, "invalid_publication_endpoint")
    else:
        require(endpoint == local_endpoint(endpoint.get("path"), timeout) and not known and not identity,
                "invalid_publication_endpoint")
    with tests.test_evidence(run, repository, test_plan, timeout) as (evidence, saved, git, guard):
        require(evidence["status"] == "passed", "passing_test_evidence_required")
        git.run(["check-ref-format", local_ref]); git.run(["check-ref-format", reference])
        candidate, fmt = evidence["commit"], saved["destination"]["object_format"]
        require(len(old) == len(candidate), "publication_object_format_mismatch")
        raw = git.run(["cat-file", "commit", old])[1]
        require(tests.object_matches(raw, "commit", old, fmt), "publication_old_commit_mismatch")
        require(git.run(["merge-base", "--is-ancestor", old, candidate], allowed=(0, 1))[0] == 0,
                "publication_not_fast_forward")
        git.run(["rev-list", "--objects", "--quiet", "--missing=error", candidate, "--"])
        forbidden = [Path(saved["output_directory"])] + [
            Path(saved["destination"][k]["path"]) for k in
            ("repository", "common_directory", "git_directory", "object_directory")]
        if endpoint["transport"] == "local":
            remote_path = Path(endpoint["path"])
            require(endpoint["object_format"] == fmt, "publication_object_format_mismatch")
            require(all(remote_path != p and p not in remote_path.parents and remote_path not in p.parents
                        for p in forbidden), "local_remote_overlaps_source")
            forbidden.append(remote_path)
        state, parent = state_parent(state, forbidden)
        plan = {"schema": SCHEMA, "policy": POLICY, "test_directory": saved["output_directory"],
                "test_plan_sha256": test_plan, "evidence_sha256": evidence["evidence_sha256"],
                "destination": saved["destination"], "local_ref": local_ref, "remote": endpoint,
                "remote_ref": reference, "expected_old_commit": old, "candidate_commit": candidate,
                "candidate_tree": evidence["tree"], "state_directory": str(state),
                "state_parent_identity": parent, "timeout_seconds": timeout, "git_version": git.text(["--version"]),
                "known_hosts_sha256": digest(known) if known else None, "identity_sha256": digest(identity) if identity else None,
                "source_sha256": {name: digest(Path(__file__).with_name(name).read_bytes()) for name in
                    ("swarm-fleet-publish.py", "swarm-fleet-test.py", "swarm-fleet-collect.py", "swarm-fleet-launch.py")},
                "may_activate_remote_hooks_ci_or_deployments": True,
                "remote_reference_kind_verified": False}
        require(len(encoded(plan)) <= fleet.LIMIT, "publication_plan_size_limit")
        sha = digest(encoded(plan))
        require(approval is None or approval == sha, "publication_approval_mismatch")
        report = {"schema": SCHEMA, "status": "preview", "plan": plan, "plan_sha256": sha,
                  "push_started": False, "changes_local_refs": False, "changes_checkout": False,
                  "tests_rerun": False, "test_provenance_verified": False, "publication_provenance_verified": False,
                  "task_completion_verified": False}
        if invoke is None:
            with remote_transport(endpoint, known, identity, timeout) as call:
                return execute_publication(plan, report, git, guard, approval, check, call)
        return execute_publication(plan, report, git, guard, approval, check, invoke)


def execute_publication(plan, report, git, guard, approval, check, invoke):
    global PUSH_STARTED, STATE_DIRECTORY
    state, candidate, old = Path(plan["state_directory"]), plan["candidate_commit"], plan["expected_old_commit"]
    reference, local_ref, sha = plan["remote_ref"], plan["local_ref"], report["plan_sha256"]
    intent = {"schema": SCHEMA, "plan": plan}
    if check:
        with fleet.directory_fd(state, private=True) as fd:
            collect.lock(fd)
            original = {name: fleet.read_at(fd, name, optional=name != "intent.json")
                        for name in ("intent.json", "attempt.json", "result.json")}
            require(encoded(decode(original["intent.json"])) == encoded(intent), "publication_intent_mismatch")
            attempt = {"schema": SCHEMA, "plan_sha256": sha}
            require(original["attempt.json"] is None or encoded(decode(original["attempt.json"])) == encoded(attempt),
                    "publication_attempt_mismatch")
            require(original["result.json"] is None or original["attempt.json"] is not None,
                    "publication_result_without_attempt")
            if original["result.json"] is not None:
                result = decode(original["result.json"])
                require(type(result) is dict and type(result.get("push_acknowledged")) is bool,
                        "invalid_publication_result")
                acknowledged = result["push_acknowledged"]
                require(encoded(result) == encoded({**report,
                        "status": "published" if acknowledged else "matched", "push_started": True,
                        "push_acknowledged": acknowledged, "remote_status": "matched"}),
                        "publication_result_mismatch")
            members = {name for name, raw in original.items() if raw is not None}
            if os.path.lexists(state / "transport.git"):
                with fleet.directory_fd(state / "transport.git", private=True):
                    pass
                members.add("transport.git")
            require(set(os.listdir(fd)) == members, "unexpected_publication_state_member")
            # Saved success is not authority: query the remote again, never push.
            current = remote_ref(invoke, reference, len(candidate))
            guard()
            status = ("matched" if current == candidate else "not_published" if current == old
                      else "missing" if current is None else "different")
            if remote_ref(invoke, reference, len(candidate)) != current:
                status = "unconfirmed"
            with fleet.directory_fd(state, private=True) as fresh:
                require(os.path.samestat(os.fstat(fd), os.fstat(fresh)), "publication_state_changed")
            require(set(os.listdir(fd)) == members, "publication_state_changed")
            for name, raw in original.items():
                require(fleet.read_at(fd, name, optional=True) == raw, "publication_state_changed")
            return {**report, "status": "matched" if status == "matched" else "attention",
                    "read_only": True, "remote_status": status,
                    "recorded_attempt": original["attempt.json"] is not None}
    fleet.state_preflight({"state_directory": str(state)})
    require(collect.review_ref_value(git, local_ref) == candidate, "local_branch_not_exact_tested_candidate")
    current = remote_ref(invoke, reference, len(candidate))
    require(current == old, "remote_branch_changed_or_missing")
    guard()
    if approval is None:
        return report
    if candidate == old:
        return {**report, "status": "noop"}
    with fleet.directory_fd(state.parent) as parent:
        info = os.fstat(parent)
        require([info.st_dev, info.st_ino] == plan["state_parent_identity"], "publication_parent_changed")
        os.mkdir(state.name, 0o700, dir_fd=parent); os.fsync(parent)
    STATE_DIRECTORY = str(state)
    with fleet.directory_fd(state, private=True) as fd:
        collect.lock(fd)
        fleet.publish(fd, "intent.json", intent)
        staging = state / "transport.git"
        staging.mkdir(mode=0o700)
        scratch = collect.LocalGit(staging, plan["timeout_seconds"])
        scratch.deadline = git.deadline
        scratch.run(["init", "--bare", "--template=", "--initial-branch=acfs-publication",
                     "--object-format=" + plan["destination"]["object_format"]])
        with fleet.directory_fd(staging / "objects/info") as info:
            collect.publish_bundle(info, "alternates", (plan["destination"]["object_directory"]["path"] + "\n").encode())
        guard()
        require(collect.review_ref_value(git, local_ref) == candidate, "local_branch_not_exact_tested_candidate")
        require(remote_ref(invoke, reference, len(candidate)) == old, "remote_branch_changed_or_missing")
        guard()
        with fleet.directory_fd(state, private=True) as fresh:
            require(os.path.samestat(os.fstat(fd), os.fstat(fresh)), "publication_state_changed")
        require(fleet.read_at(fd, "intent.json") == encoded(intent), "publication_intent_changed")
        require(collect.review_ref_value(git, local_ref) == candidate, "local_branch_not_exact_tested_candidate")
        fleet.publish(fd, "attempt.json", {"schema": SCHEMA, "plan_sha256": sha})
        PUSH_STARTED = report["push_started"] = True
        code, raw = invoke("push", reference, old, candidate, staging)
        accepted = push_accepted(code, raw, reference, candidate)
        guard()
        require(remote_ref(invoke, reference, len(candidate)) == candidate, "remote_publication_unconfirmed")
        report.update(status="published" if accepted else "matched", push_acknowledged=accepted, remote_status="matched")
        with fleet.directory_fd(state, private=True) as fresh:
            require(os.path.samestat(os.fstat(fd), os.fstat(fresh)), "publication_state_changed")
        fleet.publish(fd, "result.json", report)
    return report


def main(args=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--test-run", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--expect-test-plan", required=True)
    parser.add_argument("--branch", required=True, help="Local direct branch already at the exact tested commit")
    parser.add_argument("--remote-branch", required=True, help="Existing destination branch; never inferred")
    parser.add_argument("--expect-old", required=True, help="Full old remote commit, which must be an ancestor")
    remote = parser.add_mutually_exclusive_group(required=True)
    remote.add_argument("--remote-url", help="Explicit ssh://USER@HOST[:PORT]/REPO; no ambient remote names")
    remote.add_argument("--local-remote", help="Explicit local bare repository (no network)")
    parser.add_argument("--known-hosts")
    parser.add_argument("--identity-file")
    parser.add_argument("--state-dir", required=True, help="New private publication journal outside all inputs")
    parser.add_argument("--timeout", type=int, default=90)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--push", action="store_true", help="Upload committed history and update the approved remote branch")
    action.add_argument("--check", action="store_true", help="Observe an original operation; never retry the push")
    parser.add_argument("--accept-plan")
    options = parser.parse_args(args)
    require((options.push or options.check) == (options.accept_plan is not None), "publication_requires_exact_approval")
    if options.remote_url is not None:
        require(options.known_hosts and options.identity_file, "explicit_ssh_trust_and_identity_required")
        endpoint = ssh_endpoint(options.remote_url)
        known = fleet.read_input(options.known_hosts, private=False)
        identity = fleet.read_input(options.identity_file)
    else:
        require(options.known_hosts is None and options.identity_file is None, "ssh_inputs_not_used_for_local_remote")
        endpoint = local_endpoint(options.local_remote, options.timeout)
        known = identity = b""
    report = publish_candidate(options.test_run, options.repository, options.expect_test_plan, options.branch,
        options.remote_branch, options.expect_old, endpoint, known, identity, options.state_dir,
        options.timeout, options.accept_plan, check=options.check)
    print(encoded(report).decode(), end="")
    return 1 if report["status"] == "attention" else 0


def cli():
    def stop(signum, _frame):
        raise fleet.Interrupted(signum)
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, stop)
    try:
        return main()
    except (fleet.Refused, OSError, ValueError, subprocess.SubprocessError, fleet.Interrupted) as exc:
        print(encoded({"schema": SCHEMA, "status": "error", "push_started": PUSH_STARTED,
            "state_directory": STATE_DIRECTORY, "code": str(exc) if isinstance(exc, fleet.Refused)
            else "publication_io_or_process_failure", "publication_provenance_verified": False}).decode(), end="")
        return 128 + exc.signum if isinstance(exc, fleet.Interrupted) else 2


if __name__ == "__main__":
    sys.exit(cli())
