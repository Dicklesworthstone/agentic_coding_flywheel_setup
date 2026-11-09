#!/usr/bin/env bash
# ============================================================
# ACFS Checksum Monitor (local) — replaces the GitHub Actions
# checksum-monitor workflow with a host-local systemd timer.
#
# This monitor is an explicit fail-closed publication state machine:
#   CLEAN_BASE -> OBSERVED -> CANDIDATE_VALIDATED -> AUTHORIZED ->
#   GENERATED -> STAGED -> COMMITTED -> ATOMIC_PUBLISHED ->
#   REMOTE_VERIFIED -> HEALTHY (or DEFERRED when external review is pending).
#
# A run starts only from a clean main checkout whose HEAD and both remote refs
# are identical. Verification is bound to the exact checksums.yaml bytes it
# observed. Candidates are built offline from that report and security.sh
# proves they apply exactly the selected observations. External-owner changes
# additionally require a human authorization digest before repository bytes
# are mutated; until then they stay at their current pins (deferred) while
# trusted-owner changes still publish. Publication is a closed-path commit
# pushed to both refs in one atomic transaction and re-read from the remote
# before health is recorded.
# Every observation retains its decoded body, original content-coded response
# entity, headers and digest bindings under an owner-only downloads-* state
# directory. Evidence is never automatically expired: the monitor owner must
# provision and archive its state directory as part of host maintenance.
#
# Deployment (maintainer host):
#   git clone https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup ~/acfs-monitor
#   cp ~/acfs-monitor/scripts/templates/acfs-checksum-monitor.{service,timer} \
#      ~/.config/systemd/user/
#   systemctl --user daemon-reload
#   systemctl --user enable --now acfs-checksum-monitor.timer
#   loginctl enable-linger "$USER"   # so the timer runs without a login session
#
# Requirements on the host: git (push access via gh credential helper),
# gh (authenticated), bun, jq, curl, flock.
#
# Environment overrides:
#   ACFS_MONITOR_REPO   clone to operate on   (default: ~/acfs-monitor)
#   ACFS_MONITOR_STATE  state/log directory   (default: ~/.local/state/acfs-monitor)
# ============================================================

set -euo pipefail

# Diagnostics deliberately run before normal monitor initialization. In
# particular, inspecting an old failure must not create state, acquire the
# publication lock, fetch a repository, or execute its current verifier.
diagnose_monitor_run() {
    if [[ ! -x /usr/bin/python3 ]]; then
        printf '%s\n' 'Monitor diagnostics require /usr/bin/python3.' >&2
        return 2
    fi
    command /usr/bin/python3 -I -S -B - "${ACFS_MONITOR_STATE:-$HOME/.local/state/acfs-monitor}" "$@" <<'ACFS_MONITOR_DIAGNOSTICS_PY'
import datetime
import errno
import hashlib
import json
import os
import re
import stat
import sys
import time

SCHEMA = "acfs.checksum-monitor-diagnostics.v1"
LOG_LIMIT = 8 * 1024 * 1024
REPORT_LIMIT = 1024 * 1024
MATCH_LIMIT = 32
DEADLINE = time.monotonic() + 30
STATES = {"INIT", "LOCKED", "CLEAN_BASE", "OBSERVED", "CANDIDATE_VALIDATED",
          "AUTHORIZED", "GENERATED", "STAGED", "COMMITTED", "ATOMIC_PUBLISHED",
          "REMOTE_VERIFIED", "HEALTHY", "DEFERRED"}
HASH = re.compile(r"[0-9a-f]{64}\Z")
NAME = re.compile(r"[a-z][a-z0-9_]{0,127}\Z")
REFUSAL_COMPONENTS = {"state_directory", "log_directory", "log_file", "lock_file",
                      "failure_counter", "github_cooldown", "private_cooldown",
                      "recovery_pending", "state_record"}
REFUSAL_REASONS = {"missing", "symlink", "wrong_type", "owner_mismatch",
                  "group_or_world_writable", "owner_permissions", "multiple_links",
                  "metadata_unavailable", "identity_changed", "io_failure",
                  "invalid_input", "private_mode_required"}
REFUSAL_MARKER = re.compile(r"\[state_refusal=([a-z_]+)\.([a-z_]+)\]")


class DiagnosticError(Exception):
    def __init__(self, code):
        self.code = code


def require(condition, code="unsafe_input"):
    if not condition:
        raise DiagnosticError(code)


def check_deadline():
    require(time.monotonic() < DEADLINE, "limit_exceeded")


def identity(info):
    return info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_gid


def file_identity(info):
    return identity(info) + (info.st_nlink, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


class Reader:
    """Read held descriptors; never trust a path supplied by an artifact."""
    def __init__(self):
        require(all(hasattr(os, key) for key in
                    ("O_DIRECTORY", "O_NOFOLLOW", "O_NONBLOCK", "O_CLOEXEC")), "unavailable")
        self.directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
        self.file_flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC
        self.directories = {}
        self.files = []
        self.selections = []

    def directory(self, path, owned=False, private=False):
        check_deadline()
        if path not in self.directories:
            parent = None if path == "/" else self.directory(os.path.dirname(path))
            fd = os.open(path if parent is None else os.path.basename(path), self.directory_flags,
                         **({} if parent is None else {"dir_fd": parent["fd"]}))
            self.directories[path] = {"fd": fd, "path": path, "parent": parent,
                                      "initial": os.fstat(fd)}
        value = self.directories[path]
        info = os.fstat(value["fd"])
        if owned or private:
            require(info.st_uid == os.geteuid() and not stat.S_IMODE(info.st_mode) & 0o7022)
        if private:
            require(stat.S_IMODE(info.st_mode) == 0o700)
        return value

    def matching(self, directory, pattern):
        matches = []
        # Retention is unlimited. Bound selected artifacts and elapsed time,
        # not the number of unrelated historical runs in the state directory.
        with os.scandir(directory["fd"]) as entries:
            for entry in entries:
                check_deadline()
                if pattern.fullmatch(entry.name):
                    matches.append(entry.name)
                    require(len(matches) <= MATCH_LIMIT, "limit_exceeded")
        return sorted(matches)

    def select(self, directory, pattern):
        names = self.matching(directory, pattern)
        self.selections.append((directory, pattern, names))
        return names

    def hold(self, directory, name, limit, private=False):
        check_deadline()
        fd = os.open(name, self.file_flags, dir_fd=directory["fd"])
        info = os.fstat(fd)
        self.files.append((directory, name, fd, info))
        mode = stat.S_IMODE(info.st_mode)
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
                and info.st_uid == os.geteuid() and not mode & 0o7022)
        require(not private or mode == 0o600)
        require(info.st_size <= limit, "limit_exceeded")
        return fd, info

    def take(self, directory, name, limit, private=False):
        fd, info = self.hold(directory, name, limit, private)
        chunks, size = [], 0
        while True:
            check_deadline()
            chunk = os.read(fd, min(65536, limit + 1 - size))
            if not chunk:
                break
            chunks.append(chunk)
            size += len(chunk)
            require(size <= limit, "limit_exceeded")
        require(file_identity(os.fstat(fd)) == file_identity(info), "changed_input")
        data = b"".join(chunks)
        return data, {"bytes": size, "sha256": hashlib.sha256(data).hexdigest()}

    def fence(self):
        for directory, pattern, names in self.selections:
            require(self.matching(directory, pattern) == names, "changed_input")
        for directory, name, fd, initial in self.files:
            require(file_identity(os.fstat(fd)) == file_identity(initial), "changed_input")
            reopened = os.open(name, self.file_flags, dir_fd=directory["fd"])
            try:
                require(file_identity(os.fstat(reopened)) == file_identity(initial), "changed_input")
            finally:
                os.close(reopened)
        for directory in self.directories.values():
            require(identity(os.fstat(directory["fd"])) == identity(directory["initial"]), "changed_input")
            parent = directory["parent"]
            reopened = os.open(directory["path"] if parent is None else os.path.basename(directory["path"]),
                               self.directory_flags, **({} if parent is None else {"dir_fd": parent["fd"]}))
            try:
                require(identity(os.fstat(reopened)) == identity(directory["initial"]), "changed_input")
            finally:
                os.close(reopened)

    def close(self):
        for _, _, fd, _ in self.files:
            os.close(fd)
        for directory in reversed(list(self.directories.values())):
            os.close(directory["fd"])


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "invalid_report")
        result[key] = value
    return result


def parse_report(data):
    def reject_constant(_):
        raise DiagnosticError("invalid_report")
    report = json.loads(data, object_pairs_hook=unique_object, parse_constant=reject_constant)
    require(isinstance(report, dict) and set(report) == {
        "schema", "schemaVersion", "timestamp", "checksumsYamlSha256", "total",
        "matches", "mismatches", "errors", "skipped"}, "invalid_report")
    require(report["schema"] == "acfs.installer-checksum-verification.v1"
            and type(report["schemaVersion"]) is int and report["schemaVersion"] == 1
            and type(report["total"]) is int and report["total"] >= 0
            and isinstance(report["checksumsYamlSha256"], str)
            and HASH.fullmatch(report["checksumsYamlSha256"]), "invalid_report")
    require(isinstance(report["timestamp"], str)
            and re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", report["timestamp"]), "invalid_report")
    datetime.datetime.strptime(report["timestamp"], "%Y-%m-%dT%H:%M:%SZ")
    shapes = {"matches": {"name", "url", "checksum"},
              "mismatches": {"name", "url", "expected", "actual"},
              "errors": {"name", "url", "error"}, "skipped": {"name", "url", "reason"}}
    seen = set()
    for category, keys in shapes.items():
        require(isinstance(report[category], list), "invalid_report")
        for item in report[category]:
            require(isinstance(item, dict) and set(item) == keys
                    and all(isinstance(value, str) for value in item.values()), "invalid_report")
            # The lower-level producer can record an incomplete policy entry
            # as skipped with no URL. It remains diagnostic-only here; the
            # publication validator continues to reject that contract breach.
            good_url = re.fullmatch(r"https://[^\s\x00-\x1f\x7f]+", item["url"])
            require(NAME.fullmatch(item["name"]) and item["name"] not in seen
                    and (good_url or (category == "skipped" and item["url"] == "")), "invalid_report")
            seen.add(item["name"])
            for key in keys & {"checksum", "expected", "actual"}:
                require(HASH.fullmatch(item[key]), "invalid_report")
            if category == "mismatches":
                require(item["expected"] != item["actual"], "invalid_report")
            if category in ("errors", "skipped"):
                text_key = "error" if category == "errors" else "reason"
                require(bool(item[text_key]) and len(item[text_key]) <= 8192, "invalid_report")
    require(report["total"] == len(seen), "invalid_report")
    return report


def state_refusal(reason, warnings):
    if "[state_refusal=" not in reason:
        return None
    markers = list(REFUSAL_MARKER.finditer(reason))
    if (reason.count("[state_refusal=") != 1 or len(markers) != 1
            or markers[0].end() != len(reason)
            or markers[0][1] not in REFUSAL_COMPONENTS
            or markers[0][2] not in REFUSAL_REASONS):
        warnings.append("invalid_state_refusal")
        return None
    return {"component": markers[0][1], "reason": markers[0][2]}


def failure_category(reason, refusal=None):
    if refusal is not None or any(reason.startswith(prefix) for prefix in (
            "could not open monitor lock file", "could not open a safe monitor lock file",
            "could not open a safe monitor log file",
            "monitor lock path changed or became unsafe while acquiring it",
            "remote publication is verified but failure-count state could not be safely read",
            "remote publication is verified but the healthy-state marker could not be written")):
        return "state_storage"
    if reason.startswith("verification returned ") and "error(s)" in reason:
        return "verification_items"
    if "strict bound report contract" in reason or reason.startswith("verification reported "):
        return "verification_contract"
    if reason.startswith("pinned base already contains generated drift"):
        return "generated_artifact_drift"
    if any(reason.startswith(prefix) for prefix in (
            "missing dependency:", "dependency ", "trusted system prefix ", "pinned Bun ",
            "Bun version unacceptable:", "monitor clone ", "origin does not ", "remote main ",
            "fetch of main ", "could not resolve exactly one remote ", "local main ",
            "local HEAD ", "clone is not clean ", "frozen, lifecycle-disabled Bun install ")):
        return "configuration"
    if any(word in reason for word in ("publication", "authorization", "atomic push", "published")):
        return "publication"
    return "unknown"


def inspect_log(data, result, run_id, private, warnings):
    states, summaries, failures, bindings, producer_exits, starts, bases = [], [], [], [], [], [], []
    for number, line in enumerate(data.decode("utf-8", errors="strict").splitlines()):
        match = re.fullmatch(r"\[[0-9]{2}:[0-9]{2}:[0-9]{2}\] (.*)", line)
        if not match:
            continue
        message = match[1]
        if message.startswith("ACFS checksum monitor starting (") or message == "state=LOCKED":
            starts.append((number, message.startswith("ACFS checksum")))
        if message.startswith("state=") and message[6:] in STATES:
            states.append((number, message[6:]))
        summary = re.match(r"summary: result=(ok|deferred|fail_closed) state=([A-Z_]+)(?: |$)", message)
        if summary and summary[2] in STATES:
            summaries.append((number, summary[1], summary[2]))
        if message.startswith("FAIL-CLOSED: "):
            failures.append((number, message[13:]))
        base = re.fullmatch(r"clean base pinned to ([0-9a-f]{40})", message)
        if base:
            bases.append(base[1])
        binding = re.fullmatch(r"verification binding: policy_sha256=([0-9a-f]{64}) report_sha256=([0-9a-f]{64})", message)
        if binding:
            bindings.append((binding[1], binding[2]))
        producer = re.match(r"verification evidence: run=" + re.escape(run_id) + r" exit=([0-9]{1,3})(?: |$)", message)
        if producer:
            producer_exits.append(int(producer[1]))
    ambiguous = len(summaries) > 1 or any(sum(kind == target for _, kind in starts) > 1 for target in (True, False))
    if ambiguous:
        result["status"] = "ambiguous"
        warnings.append("ambiguous_run_log")
        return [], []
    if states:
        result["recorded_state"] = states[-1][1]
    if len(bases) == 1:
        result["recorded_base_commit"] = bases[0]
    elif len(bases) > 1:
        warnings.append("ambiguous_base_commit_records")
    if summaries:
        position, outcome, state = summaries[-1]
        later = any(item[0] > position for item in states + failures + starts)
        consistent = ((outcome == "ok" and state == "HEALTHY") or (outcome == "deferred" and state == "DEFERRED")) and not failures
        consistent = consistent or (outcome == "fail_closed" and state not in {"HEALTHY", "DEFERRED"})
        if not later and consistent:
            result["recorded_result"], result["recorded_state"] = outcome, state
        else:
            warnings.append("incomplete_log")
    else:
        warnings.append("incomplete_log")
    if failures and result["recorded_result"] not in ("ok", "deferred"):
        reason = failures[-1][1]
        refusal = state_refusal(reason, warnings)
        result["failure_category"] = failure_category(reason, refusal)
        if refusal is not None:
            result["state_refusal"] = refusal
        if private:
            result["failure_reason"] = reason
    return bindings, producer_exits


def inspect(state_path, run_id, private):
    run_time = datetime.datetime.strptime(run_id, "%Y%m%dT%H%M%SZ")
    warnings = ["local_diagnostics_are_not_publication_evidence", "current_monitor_health_not_established"]
    output = {"schema": SCHEMA, "run_id": run_id, "diagnostic_only": True,
              "publication_authorized": False, "current_health": "unknown",
              "private_details_included": private, "warnings": warnings}
    log = {"status": "missing", "path": "logs/run-" + run_id + ".log",
           "recorded_state": None, "recorded_result": "unknown", "failure_category": "unknown",
           "recorded_base_commit": None}
    verification = {"status": "missing", "candidates": [],
                    "logged_report_binding": "absent", "logged_policy_binding": "absent"}
    downloads = {"status": "missing", "candidates": [], "observation_roots": [], "policy_snapshots": []}
    output.update(log=log, verification=verification, downloads=downloads)
    reader = Reader()
    try:
        state_dir = reader.directory(state_path, owned=True)
        bindings, producer_exits = [], []
        try:
            log_dir = reader.directory(os.path.join(state_path, "logs"), owned=True)
        except FileNotFoundError:
            log_dir = None
        if log_dir is not None:
            logs = reader.select(log_dir, re.compile(re.escape("run-" + run_id + ".log")))
            if logs:
                data, metadata = reader.take(log_dir, logs[0], LOG_LIMIT)
                log.update(status="inspected", **metadata)
                try:
                    bindings, producer_exits = inspect_log(data, log, run_id, private, warnings)
                except UnicodeError:
                    log["status"] = "invalid"
                    warnings.append("invalid_log_encoding")
        suffix = r"[A-Za-z0-9]{6}"
        verification["candidates"] = reader.select(state_dir, re.compile("verify-" + re.escape(run_id) + r"\." + suffix + r"\.json"))
        if len(verification["candidates"]) > 1:
            verification["status"] = "ambiguous"
            warnings.append("ambiguous_verification_reports")
        elif verification["candidates"]:
            data, metadata = reader.take(state_dir, verification["candidates"][0], REPORT_LIMIT, private=True)
            verification.update(metadata)
            try:
                report = parse_report(data)
            except (DiagnosticError, ValueError, TypeError, RecursionError, UnicodeError):
                report = None
                verification["status"] = "invalid"
                warnings.append("invalid_verification_report")
            if report is not None:
                verification.update(status="inspected", policy_sha256=report["checksumsYamlSha256"],
                                    timestamp=report["timestamp"],
                                    counts={key: len(report[key]) for key in ("matches", "mismatches", "errors", "skipped")})
                verification["counts"]["total"] = report["total"]
                verification["errors"] = [{"name": item["name"], **({"description": item["error"]} if private else {})} for item in report["errors"]]
                verification["skipped"] = [{"name": item["name"], **({"description": item["reason"]} if private else {})} for item in report["skipped"]]
                verification["mismatches"] = [{key: item[key] for key in ("name", "expected", "actual")} for item in report["mismatches"]]
                elapsed = (datetime.datetime.strptime(report["timestamp"], "%Y-%m-%dT%H:%M:%SZ") - run_time).total_seconds()
                if not 0 <= elapsed <= 1200:
                    warnings.append("report_timestamp_outside_run_window")
                if len(bindings) == 1:
                    verification["logged_report_binding"] = "matches" if bindings[0][1] == metadata["sha256"] else "differs"
                    verification["logged_policy_binding"] = "matches" if bindings[0][0] == report["checksumsYamlSha256"] else "differs"
                elif len(bindings) > 1:
                    verification["logged_report_binding"] = verification["logged_policy_binding"] = "ambiguous"
                if "differs" in (verification["logged_report_binding"], verification["logged_policy_binding"]):
                    warnings.append("local_report_binding_differs")
        if len(producer_exits) == 1:
            verification["recorded_producer_exit"] = producer_exits[0]
        elif len(producer_exits) > 1:
            warnings.append("ambiguous_verifier_exit_records")
        downloads["candidates"] = reader.select(state_dir, re.compile("downloads-" + re.escape(run_id) + r"\." + suffix))
        if len(downloads["candidates"]) > 1:
            downloads["status"] = "ambiguous"
            warnings.append("ambiguous_download_directories")
        elif downloads["candidates"]:
            name = downloads["candidates"][0]
            directory = reader.directory(os.path.join(state_path, name), private=True)
            downloads["status"] = "present"
            for key, prefix in (("observation_roots", "acfs-observations."), ("policy_snapshots", "acfs-checksums-policy.")):
                names = reader.select(directory, re.compile(re.escape(prefix) + suffix))
                for item in names:
                    if key == "observation_roots":
                        reader.directory(os.path.join(state_path, name, item), private=True)
                    else:
                        reader.hold(directory, item, REPORT_LIMIT, private=True)
                # Locators only: installer bodies, headers, stderr, authorization
                # records and repository files are never read by diagnostics.
                downloads[key] = [name + "/" + item for item in names]
        reader.fence()
        return output
    finally:
        reader.close()


try:
    require(len(sys.argv) in (3, 4), "invalid_arguments")
    state_path, run_id = sys.argv[1:3]
    require(re.fullmatch(r"[0-9]{8}T[0-9]{6}Z", run_id), "invalid_arguments")
    try:
        datetime.datetime.strptime(run_id, "%Y%m%dT%H%M%SZ")
    except ValueError:
        raise DiagnosticError("invalid_arguments") from None
    require(len(sys.argv) == 3 or sys.argv[3] == "--include-private-details", "invalid_arguments")
    require(state_path and ".." not in state_path.split("/")
            and not any(ord(char) < 32 for char in state_path), "invalid_arguments")
    output = inspect(os.path.abspath(state_path), run_id, len(sys.argv) == 4)
    print(json.dumps(output, ensure_ascii=True, separators=(",", ":")))
except (DiagnosticError, OSError, ValueError, TypeError, RecursionError) as error:
    code = error.code if isinstance(error, DiagnosticError) else "unsafe_input"
    if isinstance(error, OSError) and error.errno in (errno.ENOENT, errno.EACCES, errno.EPERM):
        code = "unavailable"
    messages = {"invalid_arguments": "Expected a valid UTC run ID and optional --include-private-details.",
                "unsafe_input": "A diagnostic input is unsafe or unsupported.",
                "changed_input": "Diagnostic inputs changed during inspection; retry after the run finishes.",
                "limit_exceeded": "A diagnostic input exceeded its bounded inspection limit.",
                "unavailable": "The requested run state or a required input is unavailable."}
    print(json.dumps({"schema": SCHEMA, "diagnostic_only": True, "publication_authorized": False,
                      "error": {"code": code, "message": messages.get(code, messages["unsafe_input"])}},
                     ensure_ascii=True, separators=(",", ":")))
    sys.exit(2)
ACFS_MONITOR_DIAGNOSTICS_PY
}

if [[ "${BASH_SOURCE[0]}" == "$0" && "$#" -gt 0 ]]; then
    case "$1" in
        --diagnose)
            shift
            diagnose_monitor_run "$@"
            exit "$?"
            ;;
        --help|-h)
            if [[ "$#" -ne 1 ]]; then
                printf '%s\n' '{"schema":"acfs.checksum-monitor-diagnostics.v1","diagnostic_only":true,"publication_authorized":false,"error":{"code":"invalid_arguments","message":"Expected --diagnose RUN_ID [--include-private-details] or --help."}}'
                exit 2
            fi
            printf '%s\n' \
                'Usage: checksum-monitor-local.sh [--diagnose RUN_ID [--include-private-details]]' \
                'RUN_ID is an explicit UTC timestamp such as 20261108T110101Z.' \
                'Diagnostics read existing state and emit JSON without running the monitor.' \
                'Private details may contain credentials or host information; keep that output private.'
            exit 0
            ;;
        *)
            printf '%s\n' '{"schema":"acfs.checksum-monitor-diagnostics.v1","diagnostic_only":true,"publication_authorized":false,"error":{"code":"invalid_arguments","message":"Expected --diagnose RUN_ID [--include-private-details] or --help."}}'
            exit 2
            ;;
    esac
fi

MONITOR_REPO="${ACFS_MONITOR_REPO:-$HOME/acfs-monitor}"
STATE_DIR="${ACFS_MONITOR_STATE:-$HOME/.local/state/acfs-monitor}"

# The generated-artifact contract asserts exact 755/644 modes on outputs, and
# git materializes checkout/merge files through the process umask. A distro
# default of 002 therefore yields 775/664 trees whose bytes are identical to
# HEAD yet fail the mode comparison -- every file "drifts" on a perfectly
# clean clone (issue #344). Pin the umask so everything this monitor creates
# or merges lands group/world read-only.
umask 022
# System utilities are resolved only from root-owned system prefixes. Bun is
# bound separately below because it intentionally lives under the monitor
# owner's home directory.
MONITOR_EXEC_PATH="/usr/local/bin:/usr/bin:/bin"
BUN_BIN="$HOME/.bun/bin/bun"
export PATH="$MONITOR_EXEC_PATH"
LOG_DIR="$STATE_DIR/logs"
LOCK_FILE="$STATE_DIR/monitor.lock"
RUN_TS="$(/usr/bin/date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="$LOG_DIR/run-$RUN_TS.log"
AUTHORIZATION_FILE="$STATE_DIR/authorized-checksum-change"
# Bun floor. The monitor used to require this exact version, and bun's own
# auto-upgrade (1.4.0 -> 1.4.1 -> 1.4.2) then failed the monitor closed on
# every run for days (#355). A newer release of the same major is accepted;
# a downgrade, a different major, or a pre-release/garbage string still
# fails closed. Raise the floor deliberately when the lockfile or generator
# starts depending on a newer Bun.
MINIMUM_BUN_VERSION="1.4.0"
MONITOR_RUN_BUDGET_SECONDS=1050
MONITOR_FAILURE_RESERVE_SECONDS=60
MONITOR_STARTED_AT_SECONDS=$SECONDS
STATE="INIT"
DOWNLOAD_EVIDENCE_RUN_DIR=""
DOWNLOAD_EVIDENCE_ROOT=""
DOWNLOAD_EVIDENCE_INDEX_FILE=""
DOWNLOAD_EVIDENCE_INDEX_SHA256=""
MONITOR_LOG_FD=2
MONITOR_LOG_PATH=""
MONITOR_LOCK_IDENTITY=""

# Exact files the monitor may publish. Directory pathspecs and extension
# globs are intentionally absent: a newly generated filename must first be
# reviewed and added to this contract.
PUBLICATION_PATHS=(
    checksums.yaml
    scripts/generated/doctor_checks.sh
    scripts/generated/install_acfs.sh
    scripts/generated/install_agents.sh
    scripts/generated/install_all.sh
    scripts/generated/install_base.sh
    scripts/generated/install_cli.sh
    scripts/generated/install_cloud.sh
    scripts/generated/install_db.sh
    scripts/generated/install_filesystem.sh
    scripts/generated/install_lang.sh
    scripts/generated/install_network.sh
    scripts/generated/install_shell.sh
    scripts/generated/install_stack.sh
    scripts/generated/install_tools.sh
    scripts/generated/install_users.sh
    scripts/generated/internal_checksums.sh
    scripts/generated/manifest_index.sh
    apps/web/lib/generated/manifest-agents.ts
    apps/web/lib/generated/manifest-commands.ts
    apps/web/lib/generated/manifest-lessons-index.ts
    apps/web/lib/generated/manifest-modules.ts
    apps/web/lib/generated/manifest-tldr.ts
    apps/web/lib/generated/manifest-tools.ts
    apps/web/lib/generated/manifest-web-index.ts
)

declare -A PUBLICATION_PATH_SET=()
for publication_path in "${PUBLICATION_PATHS[@]}"; do
    PUBLICATION_PATH_SET["$publication_path"]=1
done

# Only these internally produced statuses carry a public refusal label. Keep
# them below 128: a killed child must never look like a specific metadata fault.
# Every external utility failure is translated at its call site, not decoded.
_monitor_refusal_code() {
    local component="$1" reason="$2" component_id=0 reason_id=0
    case "$component" in
        state_directory) component_id=0 ;; log_directory) component_id=1 ;;
        log_file) component_id=2 ;; lock_file) component_id=3 ;;
        failure_counter) component_id=4 ;; github_cooldown) component_id=5 ;;
        private_cooldown) component_id=6 ;; recovery_pending) component_id=7 ;;
        state_record) component_id=8 ;;
        *) printf '1\n'; return 0 ;;
    esac
    case "$reason" in
        missing) reason_id=0 ;; symlink) reason_id=1 ;;
        wrong_type) reason_id=2 ;; owner_mismatch) reason_id=3 ;;
        group_or_world_writable) reason_id=4 ;; owner_permissions) reason_id=5 ;;
        multiple_links) reason_id=6 ;; metadata_unavailable) reason_id=7 ;;
        identity_changed) reason_id=8 ;; io_failure) reason_id=9 ;;
        invalid_input) reason_id=10 ;; private_mode_required) reason_id=11 ;;
        *) printf '1\n'; return 0 ;;
    esac
    printf '%s\n' "$((16 + component_id * 12 + reason_id))"
}

_monitor_refusal_label() {
    local status="${1:-}" component="" reason="" value=0
    if [[ ! "$status" =~ ^[0-9]{1,3}$ ]]; then
        printf 'state_record.unclassified\n'
        return 0
    fi
    value=$((10#$status))
    if (( value < 16 || value > 123 )); then
        printf 'state_record.unclassified\n'
        return 0
    fi
    case "$(((value - 16) / 12))" in
        0) component=state_directory ;; 1) component=log_directory ;;
        2) component=log_file ;; 3) component=lock_file ;;
        4) component=failure_counter ;; 5) component=github_cooldown ;;
        6) component=private_cooldown ;; 7) component=recovery_pending ;;
        8) component=state_record ;;
    esac
    case "$(((value - 16) % 12))" in
        0) reason=missing ;; 1) reason=symlink ;; 2) reason=wrong_type ;;
        3) reason=owner_mismatch ;; 4) reason=group_or_world_writable ;;
        5) reason=owner_permissions ;; 6) reason=multiple_links ;;
        7) reason=metadata_unavailable ;; 8) reason=identity_changed ;;
        9) reason=io_failure ;; 10) reason=invalid_input ;;
        11) reason=private_mode_required ;;
    esac
    printf '%s.%s\n' "$component" "$reason"
}

_monitor_owned_directory() {
    local directory="$1" component="${2:-state_record}" metadata="" owner="" mode="" mode_value=0
    [[ ! -L "$directory" ]] || return "$(_monitor_refusal_code "$component" symlink)"
    [[ -e "$directory" ]] || return "$(_monitor_refusal_code "$component" missing)"
    [[ -d "$directory" ]] || return "$(_monitor_refusal_code "$component" wrong_type)"
    metadata="$(stat -c '%u:%a' -- "$directory" 2>/dev/null)" \
        || return "$(_monitor_refusal_code "$component" metadata_unavailable)"
    IFS=: read -r owner mode <<< "$metadata"
    [[ "$owner" =~ ^[0-9]+$ && "$mode" =~ ^[0-7]{3,4}$ ]] \
        || return "$(_monitor_refusal_code "$component" metadata_unavailable)"
    [[ "$owner" == "$EUID" ]] || return "$(_monitor_refusal_code "$component" owner_mismatch)"
    mode_value=$((8#$mode))
    (( (mode_value & 022) == 0 )) || return "$(_monitor_refusal_code "$component" group_or_world_writable)"
    (( (mode_value & 0700) == 0700 )) || return "$(_monitor_refusal_code "$component" owner_permissions)"
    return 0
}

_monitor_file_metadata_identity() {
    local metadata="$1" component="${2:-state_record}" device="" inode="" owner="" mode="" links="" mode_value=0
    IFS=: read -r device inode owner mode links <<< "$metadata"
    [[ "$device" =~ ^[0-9]+$ && "$inode" =~ ^[0-9]+$ && "$owner" =~ ^[0-9]+$ \
        && "$links" =~ ^[0-9]+$ && "$mode" =~ ^[0-7]{3,4}$ ]] \
        || return "$(_monitor_refusal_code "$component" metadata_unavailable)"
    [[ "$owner" == "$EUID" ]] || return "$(_monitor_refusal_code "$component" owner_mismatch)"
    if [[ "$links" != 1 ]]; then
        [[ "$links" != 0 ]] || return "$(_monitor_refusal_code "$component" identity_changed)"
        return "$(_monitor_refusal_code "$component" multiple_links)"
    fi
    mode_value=$((8#$mode))
    (( (mode_value & 022) == 0 )) || return "$(_monitor_refusal_code "$component" group_or_world_writable)"
    (( (mode_value & 0600) == 0600 )) || return "$(_monitor_refusal_code "$component" owner_permissions)"
    printf '%s:%s\n' "$device" "$inode"
}

_monitor_named_file_identity() {
    local path="$1" component="${2:-state_record}" metadata=""
    [[ ! -L "$path" ]] || return "$(_monitor_refusal_code "$component" symlink)"
    [[ -e "$path" ]] || return "$(_monitor_refusal_code "$component" missing)"
    [[ -f "$path" ]] || return "$(_monitor_refusal_code "$component" wrong_type)"
    metadata="$(stat -c '%d:%i:%u:%a:%h' -- "$path" 2>/dev/null)" \
        || return "$(_monitor_refusal_code "$component" metadata_unavailable)"
    _monitor_file_metadata_identity "$metadata" "$component"
}

_monitor_descriptor_identity() {
    local descriptor="$1" component="${2:-state_record}" descriptor_path="" metadata=""
    [[ "$descriptor" =~ ^[0-9]{1,9}$ ]] || return "$(_monitor_refusal_code "$component" invalid_input)"
    descriptor_path="/proc/self/fd/$descriptor"
    [[ -f "$descriptor_path" ]] || return "$(_monitor_refusal_code "$component" io_failure)"
    metadata="$(stat -Lc '%d:%i:%u:%a:%h' -- "$descriptor_path" 2>/dev/null)" \
        || return "$(_monitor_refusal_code "$component" metadata_unavailable)"
    _monitor_file_metadata_identity "$metadata" "$component"
}

_initialize_monitor_log_directories() {
    if [[ ! -e "$STATE_DIR" && ! -L "$STATE_DIR" ]]; then
        ( umask 077; /usr/bin/mkdir -p -- "$STATE_DIR" ) \
            || return "$(_monitor_refusal_code state_directory io_failure)"
    fi
    _monitor_owned_directory "$STATE_DIR" state_directory || return "$?"
    if [[ ! -e "$LOG_DIR" && ! -L "$LOG_DIR" ]]; then
        ( umask 077; /usr/bin/mkdir -- "$LOG_DIR" ) \
            || return "$(_monitor_refusal_code log_directory io_failure)"
    fi
    _monitor_owned_directory "$LOG_DIR" log_directory
}

# Sourcing retains its directory setup, but never follows an unsafe directory
# to create children and never opens a lock or log descriptor. Main reports a
# rejected layout through the ordinary fail-closed path and service journal.
_initialize_monitor_log_directories || true

_close_monitor_log() {
    local previous_fd="$MONITOR_LOG_FD"
    MONITOR_LOG_FD=2
    MONITOR_LOG_PATH=""
    if [[ "$previous_fd" =~ ^[0-9]{1,9}$ && "$previous_fd" != 2 ]]; then
        { exec {previous_fd}>&-; } 2>/dev/null || true
    fi
}

_monitor_open_log_identity() {
    local descriptor="$1" before="${2:-}" current="" opened=""
    _monitor_owned_directory "$STATE_DIR" state_directory || return "$?"
    _monitor_owned_directory "$LOG_DIR" log_directory || return "$?"
    [[ "${LOG_FILE%/*}" == "$LOG_DIR" ]] || return "$(_monitor_refusal_code log_file invalid_input)"
    current="$(_monitor_named_file_identity "$LOG_FILE" log_file)" || return "$?"
    opened="$(_monitor_descriptor_identity "$descriptor" log_file)" || return "$?"
    [[ "$current" == "$opened" && ( -z "$before" || "$current" == "$before" ) ]] \
        || return "$(_monitor_refusal_code log_file identity_changed)"
    printf '%s\n' "$opened"
}

_prepare_monitor_log() {
    local before="" opened="" opened_fd="" previous_umask="" open_status=0 validation_status=0
    if [[ "$MONITOR_LOG_FD" != 2 ]]; then
        if [[ "$MONITOR_LOG_PATH" == "$LOG_FILE" ]] \
            && opened="$(_monitor_open_log_identity "$MONITOR_LOG_FD")"; then
            return 0
        fi
        # A changed or unsafe name must not silently keep writing the old log.
        _close_monitor_log
    fi
    _monitor_owned_directory "$STATE_DIR" state_directory || return "$?"
    _monitor_owned_directory "$LOG_DIR" log_directory || return "$?"
    [[ "${LOG_FILE%/*}" == "$LOG_DIR" ]] || return "$(_monitor_refusal_code log_file invalid_input)"
    if [[ -e "$LOG_FILE" || -L "$LOG_FILE" ]]; then
        before="$(_monitor_named_file_identity "$LOG_FILE" log_file)" || return "$?"
    fi
    previous_umask="$(umask)"
    umask 077
    { exec {opened_fd}>>"$LOG_FILE"; } 2>/dev/null || open_status=$?
    umask "$previous_umask"
    (( open_status == 0 )) || return "$(_monitor_refusal_code log_file io_failure)"
    opened="$(_monitor_open_log_identity "$opened_fd" "$before")" || validation_status=$?
    if (( validation_status != 0 )); then
        { exec {opened_fd}>&-; } 2>/dev/null || true
        return "$validation_status"
    fi
    MONITOR_LOG_FD="$opened_fd"
    MONITOR_LOG_PATH="$LOG_FILE"
}

_monitor_open_lock_identity() {
    local before="${1:-}" current="" opened=""
    [[ "$LOCK_FILE" == "$STATE_DIR/monitor.lock" ]] || return "$(_monitor_refusal_code lock_file invalid_input)"
    _monitor_owned_directory "$STATE_DIR" state_directory || return "$?"
    current="$(_monitor_named_file_identity "$LOCK_FILE" lock_file)" || return "$?"
    opened="$(_monitor_descriptor_identity 9 lock_file)" || return "$?"
    [[ "$current" == "$opened" && ( -z "$before" || "$current" == "$before" ) ]] \
        || return "$(_monitor_refusal_code lock_file identity_changed)"
    printf '%s\n' "$opened"
}

_open_monitor_lock() {
    local before="" opened="" previous_umask="" open_status=0 validation_status=0
    [[ "$LOCK_FILE" == "$STATE_DIR/monitor.lock" ]] || return "$(_monitor_refusal_code lock_file invalid_input)"
    _monitor_owned_directory "$STATE_DIR" state_directory || return "$?"
    if [[ -e "$LOCK_FILE" || -L "$LOCK_FILE" ]]; then
        before="$(_monitor_named_file_identity "$LOCK_FILE" lock_file)" || return "$?"
    fi
    previous_umask="$(umask)"
    umask 077
    # Read/write opening creates an absent lock without truncating an existing
    # inode. Replacing or unlinking a live lock would break mutual exclusion.
    { exec 9<>"$LOCK_FILE"; } 2>/dev/null || open_status=$?
    umask "$previous_umask"
    (( open_status == 0 )) || return "$(_monitor_refusal_code lock_file io_failure)"
    opened="$(_monitor_open_lock_identity "$before")" || validation_status=$?
    if (( validation_status != 0 )); then
        exec 9>&-
        return "$validation_status"
    fi
    MONITOR_LOCK_IDENTITY="$opened"
}

_monitor_lock_is_current() {
    local opened=""
    [[ -n "$MONITOR_LOCK_IDENTITY" ]] || return "$(_monitor_refusal_code lock_file invalid_input)"
    opened="$(_monitor_open_lock_identity "$MONITOR_LOCK_IDENTITY")" || return "$?"
    return 0
}

log() {
    local message="" status=0 refusal_status=0
    printf -v message '[%s] %s\n' "$(/usr/bin/date -u +%H:%M:%S)" "$*"
    if _prepare_monitor_log; then
        printf '%s' "$message" >&"$MONITOR_LOG_FD" || status=1
    else
        refusal_status=$?
        printf 'ACFS monitor log unavailable [state_refusal=%s]\n' \
            "$(_monitor_refusal_label "$refusal_status")" >&2 || true
        status=1
    fi
    printf '%s' "$message" >&2 || status=1
    return "$status"
}

monitor_log_stream() {
    if ! _prepare_monitor_log; then
        /usr/bin/cat >&2
        return 1
    fi
    # This names the already validated descriptor, never the mutable log path.
    /usr/bin/tee -a "/proc/self/fd/$MONITOR_LOG_FD" >&2
}

advance_state() {
    local expected="$1" next="$2"
    if [[ "$STATE" != "$expected" ]]; then
        fail_closed "invalid monitor transition: expected $expected, found $STATE, requested $next"
    fi
    STATE="$next"
    log "state=$STATE"
}

# Do not allow CHECKSUMS_FILE, ACFS_PLUGIN_PATHS, ACFS_PLUGINS_DIR, curl-bin
# overrides, manifest roots, or other ambient inputs to redirect verification
# or generation. Only the stable process essentials below cross this boundary.
run_clean() {
    env -i \
        HOME="$HOME" \
        USER="${USER:-}" \
        LOGNAME="${LOGNAME:-${USER:-}}" \
        PATH="$MONITOR_EXEC_PATH" \
        LANG=C \
        LC_ALL=C \
        TZ=UTC \
        CI=1 \
        NO_COLOR=1 \
        "$@"
}

# Bun re-execs itself via PATH when running package.json scripts, so the
# pinned Bun's own directory must be on the clean PATH here too (appended,
# never prepended).
run_bun_clean() {
    env -i \
        HOME="$HOME" \
        USER="${USER:-}" \
        LOGNAME="${LOGNAME:-${USER:-}}" \
        PATH="$MONITOR_EXEC_PATH:${BUN_BIN%/*}" \
        LANG=C \
        LC_ALL=C \
        TZ=UTC \
        CI=1 \
        NO_COLOR=1 \
        "$BUN_BIN" "$@"
}

run_bounded() {
    local requested_seconds="$1"
    shift
    local elapsed=$((SECONDS - MONITOR_STARTED_AT_SECONDS))
    local remaining=$((MONITOR_RUN_BUDGET_SECONDS - elapsed - MONITOR_FAILURE_RESERVE_SECONDS))
    local limit="$requested_seconds"
    (( remaining > 0 )) || return 124
    if (( limit > remaining )); then
        limit="$remaining"
    fi
    timeout --signal=TERM --kill-after=10 "${limit}s" "$@"
}

run_clean_bounded() {
    local requested_seconds="$1"
    shift
    # The pinned Bun's directory is appended (never prepended, so system tools
    # always win) because child scripts such as check-manifest-drift.sh resolve
    # `bun` via PATH. $BUN_BIN and its directory are metadata-verified before
    # any run_clean_bounded call that executes repository code.
    run_bounded "$requested_seconds" env -i \
        HOME="$HOME" \
        USER="${USER:-}" \
        LOGNAME="${LOGNAME:-${USER:-}}" \
        PATH="$MONITOR_EXEC_PATH:${BUN_BIN%/*}" \
        LANG=C \
        LC_ALL=C \
        TZ=UTC \
        CI=1 \
        NO_COLOR=1 \
        "$@"
}

run_bun_clean_bounded() {
    local requested_seconds="$1"
    shift
    run_bounded "$requested_seconds" env -i \
        HOME="$HOME" \
        USER="${USER:-}" \
        LOGNAME="${LOGNAME:-${USER:-}}" \
        PATH="$MONITOR_EXEC_PATH:${BUN_BIN%/*}" \
        LANG=C \
        LC_ALL=C \
        TZ=UTC \
        CI=1 \
        NO_COLOR=1 \
        "$BUN_BIN" "$@"
}

run_failure_bounded() {
    timeout --signal=TERM --kill-after=5 20 "$@"
}

sha256_file() {
    local file="$1" digest="" links=""
    [[ -f "$file" && ! -L "$file" && -r "$file" ]] || return 1
    links="$(stat -c '%h' -- "$file" 2>/dev/null)" || return 1
    [[ "$links" == "1" ]] || return 1
    digest="$(sha256sum -- "$file" 2>/dev/null)" || return 1
    digest="${digest%% *}"
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s\n' "$digest"
}

REMOTE_MAIN_HEAD=""
REMOTE_MASTER_HEAD=""
read_remote_heads() {
    local refs="" main_count="" mirror_count=""
    refs="$(run_bounded 45 git ls-remote --heads origin refs/heads/main refs/heads/master 2>&"$MONITOR_LOG_FD")" \
        || return 1
    main_count="$(awk '$2 == "refs/heads/main" { count += 1 } END { print count + 0 }' <<< "$refs")"
    mirror_count="$(awk '$2 == "refs/heads/master" { count += 1 } END { print count + 0 }' <<< "$refs")"
    [[ "$main_count" -eq 1 && "$mirror_count" -eq 1 ]] || return 1
    REMOTE_MAIN_HEAD="$(awk '$2 == "refs/heads/main" { print $1 }' <<< "$refs")"
    REMOTE_MASTER_HEAD="$(awk '$2 == "refs/heads/master" { print $1 }' <<< "$refs")"
    [[ "$REMOTE_MAIN_HEAD" =~ ^[0-9a-f]{40}$ ]] \
        && [[ "$REMOTE_MASTER_HEAD" =~ ^[0-9a-f]{40}$ ]]
}

require_clean_tree() {
    local status_output=""
    status_output="$(git status --porcelain=v1 --untracked-files=all 2>&"$MONITOR_LOG_FD")" \
        || return 1
    [[ -z "$status_output" ]] || return 1
    git diff --quiet --exit-code -- \
        && git diff --cached --quiet --exit-code --
}

canonical_compact_json_is_exact() {
    local file="$1" canonical="" canonical_digest="" source_digest=""
    canonical="$(jq -c . "$file" 2>/dev/null)" || return 1
    [[ "$canonical" != *$'\n'* ]] || return 1
    canonical_digest="$(printf '%s\n' "$canonical" | sha256sum | awk '{print $1}')" \
        || return 1
    source_digest="$(sha256_file "$file")" || return 1
    [[ "$canonical_digest" =~ ^[0-9a-f]{64}$ ]] \
        && [[ "$canonical_digest" == "$source_digest" ]]
}

validate_drift_report() {
    local file="$1"
    # The drift producer emits one compact jq object. Requiring byte-canonical
    # compact JSON rejects duplicate keys, alternate encodings, trailing data,
    # and empty-container duplicate-key cases before the field schema runs.
    canonical_compact_json_is_exact "$file" || return 1
    jq -e '
        def exact_keys($wanted): type == "object" and keys == ($wanted | sort);
        def count: type == "number" and floor == . and . >= 0;
        def strings: type == "array" and all(.[]; type == "string");
        type == "object" and
        exact_keys([
          "drift_detected", "generated_artifacts", "internal_scripts",
          "manifest", "manifest_contract", "reasons", "repo_mcp_configs"
        ]) and
        (.drift_detected | type == "boolean") and
        (.reasons | strings) and
        (.manifest | exact_keys(["actual_sha256", "index_modules", "manifest_modules", "recorded_sha256", "sha256_line_count"])) and
        (.manifest.actual_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
        (.manifest.recorded_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
        (.manifest.sha256_line_count | count) and
        (.manifest.manifest_modules | count) and
        (.manifest.index_modules | count) and
        (.internal_scripts | exact_keys(["checked", "drift_files", "drifted"])) and
        (.internal_scripts.checked | count) and
        (.internal_scripts.drifted | count) and
        (.internal_scripts.drift_files | strings) and
        (.repo_mcp_configs | exact_keys(["checked", "drift_files", "drifted", "expected_url"])) and
        (.repo_mcp_configs.expected_url == "http://127.0.0.1:8765/mcp/") and
        (.repo_mcp_configs.checked | count) and
        (.repo_mcp_configs.drifted | count) and
        (.repo_mcp_configs.drift_files | strings) and
        (.generated_artifacts | exact_keys(["drift_files", "drifted", "status"])) and
        (.generated_artifacts.status == "clean" or .generated_artifacts.status == "drift") and
        (.generated_artifacts.drifted | count) and
        (.generated_artifacts.drift_files | strings) and
        (.manifest_contract | exact_keys(["checked", "drift_files", "drifted", "mismatch_codes", "status"])) and
        (.manifest_contract.status == "clean" or .manifest_contract.status == "drift") and
        (.manifest_contract.checked | count) and
        (.manifest_contract.drifted | count) and
        (.manifest_contract.drift_files | strings) and
        (.manifest_contract.mismatch_codes | strings)
    ' "$file" >/dev/null 2>&1
}

validate_verification_report() {
    local file="$1" expected_digest="$2"
    canonical_compact_json_is_exact "$file" || return 1
    [[ "$(sha256_file checksums.yaml)" == "$expected_digest" ]] || return 1
    # Delegate exact schema, duplicate-key detection, installer membership,
    # URL/hash bindings, and report-to-policy digest binding to security.sh's
    # authoritative offline report validator. This accepts complete match and
    # mismatch partitions without pretending the current policy is already
    # the later candidate.
    run_clean_bounded 30 bash -c '
        set -euo pipefail
        source "$1"
        declare -A urls=() checksums=() matches=() mismatch_expected=()
        declare -A mismatch_actual=() errors=() skipped=()
        acfs_load_checksums_strict "$2" urls checksums
        digest="$(calculate_file_sha256 "$2")"
        [[ "$digest" == "$3" ]]
        acfs_validate_installer_checksum_report \
            "$4" urls checksums "$digest" \
            matches mismatch_expected mismatch_actual errors skipped
    ' bash \
        "$PWD/scripts/lib/security.sh" \
        "$PWD/checksums.yaml" \
        "$expected_digest" \
        "$file" >/dev/null 2>&1
}

# Download evidence is kept outside Git, in a fresh owner-only directory.
# No paths from sidecars are followed: the strict policy name determines each
# directory, and all filenames below are fixed. Headers may contain cookies
# or signed redirects, so neither their contents nor bodies go into issues.
private_download_evidence_path() {
    local path="$1" kind="$2" limit="${3:-0}" owner="" mode="" links="" size=""
    [[ ! -L "$path" ]] || return 1
    owner="$(stat -c '%u' -- "$path" 2>/dev/null)" || return 1
    mode="$(stat -c '%a' -- "$path" 2>/dev/null)" || return 1
    [[ "$owner" == "$(id -u)" ]] || return 1
    if [[ "$kind" == directory ]]; then
        [[ -d "$path" && "$mode" == 700 ]]
    else
        [[ -f "$path" && "$mode" == 600 ]] || return 1
        links="$(stat -c '%h' -- "$path" 2>/dev/null)" || return 1
        size="$(stat -c '%s' -- "$path" 2>/dev/null)" || return 1
        [[ "$links" == 1 && "$size" =~ ^[0-9]+$ ]] || return 1
        (( size <= limit ))
    fi
}

validate_download_evidence() {
    local report="$1" run_dir="$2" expected_index="${3:-}"
    local root="" rows="" name="" url="" expected="" actual="" dir="" metadata=""
    local body_digest="" wire_digest="" headers_digest="" report_digest="" row_file="" index_file="" index_digest=""
    local -a roots=("$run_dir"/acfs-observations.*) entries=()
    local -A seen=()
    if [[ -n "$expected_index" ]]; then
        private_download_evidence_path "$DOWNLOAD_EVIDENCE_INDEX_FILE" file 1048576 \
            && [[ "$(sha256_file "$DOWNLOAD_EVIDENCE_INDEX_FILE")" == "$expected_index" ]] || return 1
    fi
    private_download_evidence_path "$run_dir" directory || return 1
    (( ${#roots[@]} == 1 )) || return 1
    root="${roots[0]}"
    private_download_evidence_path "$root" directory || return 1
    rows="$(jq -er '
      ([.matches[] | {name,url,expected:.checksum,actual:.checksum}] + .mismatches)
      | sort_by(.name) | .[] | [.name,.url,.expected,.actual] | @tsv
    ' "$report")" || return 1
    report_digest="$(sha256_file "$report")" || return 1
    [[ "$report_digest" == "$VERIFICATION_REPORT_SHA256" ]] || return 1
    row_file="$(mktemp "$run_dir/evidence-rows.XXXXXX.jsonl")" || return 1
    while IFS=$'\t' read -r name url expected actual; do
        [[ "$name" =~ ^[a-z][a-z0-9_]*$ && -z "${seen[$name]+present}" ]] || return 1
        seen["$name"]=1
        dir="$root/$name"
        metadata="$dir/metadata.json"
        private_download_evidence_path "$dir" directory \
            && private_download_evidence_path "$metadata" file 16384 \
            && private_download_evidence_path "$dir/body" file 16777216 \
            && private_download_evidence_path "$dir/body.wire" file 1048576 \
            && private_download_evidence_path "$dir/body.headers" file 1048576 || return 1
        [[ -s "$dir/body.headers" ]] || return 1
        canonical_compact_json_is_exact "$metadata" || return 1
        body_digest="$(sha256_file "$dir/body")" || return 1
        wire_digest="$(sha256_file "$dir/body.wire")" || return 1
        headers_digest="$(sha256_file "$dir/body.headers")" || return 1
        jq -e --arg name "$name" --arg url "$url" --arg expected "$expected" --arg actual "$actual" \
            --arg body "$body_digest" --arg wire "$wire_digest" --arg headers "$headers_digest" '
          (keys | sort) == (["schema","name","url","expected","actual","status","bodySha256","wireSha256","headersSha256"] | sort) and
          .schema == "acfs.installer-download-evidence.v1" and .status == "observed" and
          .name == $name and .url == $url and .expected == $expected and .actual == $actual and
          .bodySha256 == $actual and .bodySha256 == $body and
          .wireSha256 == $wire and .headersSha256 == $headers
        ' "$metadata" >/dev/null 2>&1 || return 1
        cat -- "$metadata" >> "$row_file" || return 1
    done <<< "$rows"
    entries=("$root"/*)
    (( ${#entries[@]} == ${#seen[@]} )) || return 1
    index_file="$(mktemp "$run_dir/evidence-index.XXXXXX.json")" || return 1
    jq -cs --arg report "$report_digest" --arg policy "$CURRENT_CHECKSUMS_SHA256" \
        '{schema:"acfs.installer-download-evidence-index.v1",verificationReportSha256:$report,checksumsYamlSha256:$policy,observations:.}' \
        "$row_file" > "$index_file" || return 1
    index_digest="$(sha256_file "$index_file")" || return 1
    [[ -z "$expected_index" || "$index_digest" == "$expected_index" ]] || return 1
    DOWNLOAD_EVIDENCE_ROOT="$root"
    if [[ -z "$DOWNLOAD_EVIDENCE_INDEX_FILE" ]]; then
        DOWNLOAD_EVIDENCE_INDEX_FILE="$index_file"
    fi
    DOWNLOAD_EVIDENCE_INDEX_SHA256="$index_digest"
}

require_download_evidence_current() {
    validate_download_evidence "$verify_json" "$DOWNLOAD_EVIDENCE_RUN_DIR" "$DOWNLOAD_EVIDENCE_INDEX_SHA256" \
        || fail_closed "first-observation download evidence is missing, unsafe, or changed"
}

is_trusted_installer_url() {
    case "$1" in
        https://raw.githubusercontent.com/Dicklesworthstone/*) return 0 ;;
        *) return 1 ;;
    esac
}

# sha256 of the external mismatch evidence (name, url, expected, actual) only.
# Trusted repins and unrelated commits leave a pending authorization valid;
# changes to the external bytes themselves yield a new digest.
external_authorization_digest() {
    local report="$1" names_json=""
    shift
    names_json="$(printf '%s\n' "$@" | jq -R . | jq -s .)" || return 1
    jq -cS --argjson names "$names_json" '
      [.mismatches[] | select(.name as $name | $names | index($name)) | {actual, expected, name, url}]
      | sort_by(.name)
    ' "$report" | sha256sum | awk '{print $1}'
}

# Constrain an independently obtained raw policy to a reviewed apply set.
# This is data projection only; the strict validator must still authorize it.
restrict_checksum_candidate() {
    local current="$1" raw="$2" apply_csv=""
    shift 2
    apply_csv="$(IFS=,; printf '%s' "$*")"
    awk -v apply_csv="$apply_csv" '
        BEGIN { n = split(apply_csv, names, ","); for (i = 1; i <= n; i++) apply[names[i]] = 1 }
        /^  [A-Za-z0-9_.-]+:$/ { name = substr($0, 3, length($0) - 3) }
        FNR == NR {
            if ($0 ~ /^    sha256: "[0-9a-f]+"$/ && name != "") pin[name] = $0
            next
        }
        /^    sha256: / && name != "" && !(name in apply) && (name in pin) { print pin[name]; next }
        { print }
    ' "$current" "$raw"
}

authorization_file_is_private() {
    local limit="$1" owner="" links="" mode="" size="" mode_value=""
    [[ -f "$AUTHORIZATION_FILE" && ! -L "$AUTHORIZATION_FILE" ]] || return 1
    owner="$(stat -c '%u' -- "$AUTHORIZATION_FILE" 2>/dev/null)" || return 1
    links="$(stat -c '%h' -- "$AUTHORIZATION_FILE" 2>/dev/null)" || return 1
    mode="$(stat -c '%a' -- "$AUTHORIZATION_FILE" 2>/dev/null)" || return 1
    size="$(stat -c '%s' -- "$AUTHORIZATION_FILE" 2>/dev/null)" || return 1
    [[ "$owner" == "$(id -u)" && "$links" == "1" ]] || return 1
    [[ "$mode" =~ ^[0-7]{3,4}$ && "$size" =~ ^[0-9]+$ ]] || return 1
    (( size > 0 && size <= limit )) || return 1
    mode_value=$((8#$mode))
    (( (mode_value & 077) == 0 )) || return 1
}

authorization_is_valid() {
    local digest="$1"
    local -a lines=()
    # Preserve the legacy aggregate record and its original size/line rules.
    authorization_file_is_private 256 || return 1
    mapfile -t lines < "$AUTHORIZATION_FILE" || return 1
    [[ ${#lines[@]} -eq 1 && "${lines[0]}" == "authorize:$digest" ]]
}

read_subset_authorization_record() {
    local record="" names="" sorted_names="" record_digest="" file_digest=""
    authorization_file_is_private 4096 || return 1
    # read requires the terminating LF; the byte hash also rejects NUL bytes
    # discarded by Bash, additional records, CRLF, and trailing data.
    IFS= read -r record < "$AUTHORIZATION_FILE" || return 1
    [[ "$record" =~ ^authorize-subset:([0-9a-f]{64}):([a-z][a-z0-9_]*(,[a-z][a-z0-9_]*)*)$ ]] || return 1
    names="${record##*:}"
    sorted_names="$(jq -nr --arg names "$names" '$names | split(",") | sort | unique | join(",")')" || return 1
    [[ "$names" == "$sorted_names" ]] || return 1
    record_digest="$(printf '%s\n' "$record" | sha256sum | awk '{print $1}')" || return 1
    file_digest="$(sha256_file "$AUTHORIZATION_FILE")" || return 1
    [[ "$record_digest" == "$file_digest" ]] || return 1
    printf '%s\n' "$record"
}

subset_authorization_is_valid() {
    local expected_record="$1" expected_mode="$2" record="" mode=""
    record="$(read_subset_authorization_record)" || return 1
    mode="$(stat -c '%a' -- "$AUTHORIZATION_FILE" 2>/dev/null)" || return 1
    [[ "$record" == "$expected_record" && "$mode" == "$expected_mode" ]]
}

# The security library owns complete report validation and the v2 digest.
# This selects no authority unless its exact offline proposal matches the
# private human record. Never prune stale names or reinterpret a subset as
# an aggregate grant. No production authorization file is created here.
select_external_subset_authorization() {
    local report="$1" record="" mode="" names="" proposal="" proposed_record="" digest="" requested_json=""
    local -a requested=()
    record="$(read_subset_authorization_record)" || return 1
    mode="$(stat -c '%a' -- "$AUTHORIZATION_FILE" 2>/dev/null)" || return 1
    names="${record##*:}"
    IFS=, read -r -a requested <<< "$names"
    digest="${record#authorize-subset:}"
    digest="${digest%%:*}"
    requested_json="$(printf '%s\n' "${requested[@]}" | jq -R . | jq -s .)" || return 1
    proposal="$(run_clean_bounded 30 bash scripts/lib/security.sh \
        --review-checksum-subset checksums.yaml "$report" "${requested[@]}" 2>&"$MONITOR_LOG_FD")" || return 1
    proposed_record="$(printf '%s\n' "$proposal" | jq -er \
        --arg policy "$CURRENT_CHECKSUMS_SHA256" --arg report "$VERIFICATION_REPORT_SHA256" \
        --arg digest "$digest" --argjson requested "$requested_json" '
        select(.schema == "acfs.external-checksum-review.v1" and .scope == "subset" and
               .checksums_yaml_sha256 == $policy and .verification_report_sha256 == $report and
               .authorization_digest == $digest and .selected == $requested) |
        .authorization_line | select(type == "string")
    ')" || return 1
    [[ "$record" == "$proposed_record" ]] || return 1
    subset_authorization_is_valid "$record" "$mode" || return 1
    authorization_mode="subset"
    selected_authorization_record="$record"
    selected_authorization_file_mode="$mode"
    authorization_digest="$digest"
    SELECTED_EXTERNAL_CHANGED=("${requested[@]}")
    authorized_external_changed="$names"
}

require_selected_external_authorization() {
    if [[ -n "$DOWNLOAD_EVIDENCE_INDEX_SHA256" ]]; then
        require_download_evidence_current
    fi
    if [[ "$authorization_consumed" == "true" ]]; then
        case "${authorization_mode:-aggregate}" in
            aggregate)
                authorization_is_valid "$authorization_digest" \
                    || fail_closed "selected external authorization changed before acceptance"
                ;;
            subset)
                subset_authorization_is_valid "$selected_authorization_record" "$selected_authorization_file_mode" \
                    || fail_closed "selected external subset authorization changed before acceptance"
                ;;
            *) fail_closed "unknown selected external authorization mode" ;;
        esac
    fi
}

record_external_review() {
    local report="$1" digest="$2" authorization_status="$3"
    local body_file="" existing="" external_names_json="[]" external_evidence="" repo_slug=""
    local review_scope="aggregate" issue_candidates=""
    if [[ "${authorization_mode:-aggregate}" == subset ]]; then
        review_scope="subset"
    fi
    repo_slug="Dicklesworthstone/agentic_coding_flywheel_setup"
    body_file="$(mktemp "$STATE_DIR/external-review-$RUN_TS.XXXXXX.md")" || return 1
    external_names_json="$(printf '%s\n' "${EXTERNAL_CHANGED[@]}" | jq -R . | jq -s .)" \
        || return 1
    external_evidence="$(jq -r --argjson names "$external_names_json" '
      .mismatches[] | select(.name as $name | $names | index($name)) |
      "- `\(.name)`\n  - URL: `\(.url)`\n  - expected: `\(.expected)`\n  - observed: `\(.actual)`"
    ' "$report")" || return 1
    {
        printf '## External installer checksum authorization\n\n'
        printf 'This monitor observed installer bytes outside the exact trusted owner boundary.\n\n'
        printf -- '- Authorization digest: `%s`\n' "$digest"
        printf -- '- Authorization status: `%s`\n' "$authorization_status"
        printf -- '- Authorization scope: `%s`\n' "$review_scope"
        printf -- '- Pinned base: `%s`\n' "$BASE_HEAD"
        printf -- '- Verification report SHA256: `%s`\n' "$VERIFICATION_REPORT_SHA256"
        printf -- '- Download evidence index SHA256: `%s`\n\n' "$DOWNLOAD_EVIDENCE_INDEX_SHA256"
        if [[ "${authorization_mode:-aggregate}" == subset ]]; then
            printf -- '- Authorized external tools: `%s`\n' "$authorized_external_changed"
            printf -- '- Deferred external tools: `%s`\n' "${deferred_changed:-none}"
            printf -- '- Aggregate observation digest (separate review): `%s`\n\n' "$aggregate_authorization_digest"
        fi
        printf 'Exact first-observation bodies, raw responses and redirect headers are retained privately on the monitor host.\n\n'
        printf '### First-observation evidence\n\n'
        printf '%s\n' "$external_evidence"
        printf '\n### Human authorization\n\n'
        printf 'After reviewing the upstream bytes, place exactly this line in `%s` as an owner-only, non-symlink file:\n\n' "$(public_text "$AUTHORIZATION_FILE")"
        if [[ "${authorization_mode:-aggregate}" == subset ]]; then
            printf 'This record authorizes only the selected external tools listed above. Deferred tools remain pinned.\n\n'
            printf '```text\n%s\n```\n' "$selected_authorization_record"
        else
            printf '```text\nauthorize:%s\n```\n' "$digest"
        fi
    } > "$body_file" || return 1

    # Search only discovers candidates. Incidental digest references in a
    # different review scope cannot identify the approval being recorded.
    issue_candidates="$(run_bounded 45 gh issue list --repo "$repo_slug" --state all \
        --label security --label checksum-update \
        --search "$digest" --json number,body \
        2>&"$MONITOR_LOG_FD")" || return 1
    existing="$(printf '%s\n' "$issue_candidates" | jq -ers \
        --arg digest "$digest" --arg scope "$review_scope" '
        if length != 1 or (.[0] | type) != "array" then
            error("expected one issue array")
        else
            .[0]
        end
        | [
            .[]
            | select((.number | type) == "number" and (.body | type) == "string")
            | select(.number > 0 and .number == (.number | floor))
            | (.body | split("\n")) as $lines
            | ($lines | map(select(startswith("- Authorization digest:")))) as $digests
            | ($lines | map(select(startswith("- Authorization scope:")))) as $scopes
            | select($digests == ["- Authorization digest: `\($digest)`"])
            | select($scopes == ["- Authorization scope: `\($scope)`"]
                     or ($scope == "aggregate" and $scopes == []))
            | .number
          ]
        | .[0] // ""
    ')" || return 1
    # Identical pending evidence is already recorded. Only an authorized use
    # warrants another comment on the matching review.
    if [[ -n "$existing" && "$existing" != "null" ]]; then
        if [[ "$authorization_status" != "authorized" ]]; then
            log "external authorization still pending on #$existing"
            return 0
        fi
        run_bounded 45 gh issue comment "$existing" --repo "$repo_slug" \
            --body-file "$body_file" >&"$MONITOR_LOG_FD" 2>&1
        return
    fi
    if run_bounded 45 gh issue create --repo "$repo_slug" \
        --title "External installer checksum authorization ${digest:0:12}" \
        --label security --label checksum-update \
        --body-file "$body_file" >&"$MONITOR_LOG_FD" 2>&1; then
        return 0
    fi
    run_bounded 45 gh issue create --repo "$repo_slug" \
        --title "External installer checksum authorization ${digest:0:12}" \
        --body-file "$body_file" >&"$MONITOR_LOG_FD" 2>&1
}

# Called only after the complete report is validated against the clean base.
# Keep its original mismatch partition intact while selecting what may publish.
prepare_checksum_candidate() {
    local report="$1" mismatch_rows="" name="" url=""
    local -a deferred_names=()
    local -A selected_names=()
    TRUSTED_CHANGED=()
    EXTERNAL_CHANGED=()
    SELECTED_EXTERNAL_CHANGED=()
    mismatch_rows="$(jq -r '.mismatches[] | [.name, .url] | @tsv' "$report")" \
        || fail_closed "could not classify validated checksum mismatches"
    while IFS=$'\t' read -r name url; do
        [[ -n "$name" ]] || continue
        if is_trusted_installer_url "$url"; then
            TRUSTED_CHANGED+=("$name")
        else
            EXTERNAL_CHANGED+=("$name")
        fi
    done <<< "$mismatch_rows"
    (( ${#TRUSTED_CHANGED[@]} + ${#EXTERNAL_CHANGED[@]} == mismatches )) \
        || fail_closed "mismatch classification did not cover the full validated report"
    changed_tools="$(jq -r '.mismatches[].name' "$report" | paste -sd, -)" \
        || fail_closed "could not summarize validated checksum mismatches"
    trusted_changed="$(printf '%s\n' "${TRUSTED_CHANGED[@]:-}" | sed '/^$/d' | paste -sd, -)"
    external_changed="$(printf '%s\n' "${EXTERNAL_CHANGED[@]:-}" | sed '/^$/d' | paste -sd, -)"
    applicable_changed="$trusted_changed"
    deferred_changed=""
    external_deferred=false
    authorization_digest=""
    aggregate_authorization_digest=""
    authorization_mode="none"
    selected_authorization_record=""
    selected_authorization_file_mode=""
    authorized_external_changed=""
    authorization_status="not-required"
    authorization_consumed=false
    [[ "$(sha256_file "$report")" == "$VERIFICATION_REPORT_SHA256" ]] \
        || fail_closed "verification report changed before authorization selection"
    if (( ${#EXTERNAL_CHANGED[@]} > 0 )); then
        authorization_digest="$(external_authorization_digest "$report" "${EXTERNAL_CHANGED[@]}")" \
            || fail_closed "could not hash external-change authorization evidence"
        [[ "$authorization_digest" =~ ^[0-9a-f]{64}$ ]] \
            || fail_closed "could not derive external-change authorization digest"
        aggregate_authorization_digest="$authorization_digest"
        if authorization_is_valid "$authorization_digest"; then
            authorization_mode="aggregate"
            authorization_status="authorized"
            applicable_changed="$changed_tools"
            authorization_consumed=true
            authorized_external_changed="$external_changed"
            SELECTED_EXTERNAL_CHANGED=("${EXTERNAL_CHANGED[@]}")
        elif select_external_subset_authorization "$report"; then
            authorization_status="authorized"
            authorization_consumed=true
            for name in "${SELECTED_EXTERNAL_CHANGED[@]}"; do
                selected_names["$name"]=1
                applicable_changed+="${applicable_changed:+,}$name"
            done
            for name in "${EXTERNAL_CHANGED[@]}"; do
                if [[ -z "${selected_names[$name]+present}" ]]; then
                    deferred_names+=("$name")
                fi
            done
            if (( ${#deferred_names[@]} > 0 )); then
                external_deferred=true
                deferred_changed="$(IFS=,; printf '%s' "${deferred_names[*]}")"
            fi
        else
            authorization_status="required"
            external_deferred=true
            deferred_changed="$external_changed"
            deferred_names=("${EXTERNAL_CHANGED[@]}")
            log "external pins deferred: ${external_changed}; review authorize:$authorization_digest"
        fi
        if ! record_external_review "$report" "$authorization_digest" "$authorization_status"; then
            if [[ "$authorization_status" == "authorized" ]]; then
                fail_closed "could not record authorized external checksum evidence before mutation"
            fi
            # The bound local report is retained even when GitHub is unavailable.
            # No external pin is allowed to change; trusted publication can proceed.
            log "WARNING: external review issue could not be recorded; evidence retained at $report"
        fi
    fi
    log "changed tools: ${changed_tools:-none} (selected: ${applicable_changed:-none}; deferred external: $external_deferred)"

    raw_candidate=""
    validated_candidate=""
    CANDIDATE_SHA256="$CURRENT_CHECKSUMS_SHA256"
    if [[ -n "$applicable_changed" ]]; then
        raw_candidate="$(mktemp "$STATE_DIR/checksums-raw-$RUN_TS.XXXXXX.yaml")" \
            || fail_closed "could not allocate raw candidate evidence file"
        validated_candidate="$(mktemp "$STATE_DIR/checksums-validated-$RUN_TS.XXXXXX.yaml")" \
            || fail_closed "could not allocate validated candidate evidence file"
        run_clean_bounded 60 bash scripts/lib/security.sh \
            --build-checksum-candidate checksums.yaml "$report" "${deferred_names[@]}" \
            >"$raw_candidate" 2>&"$MONITOR_LOG_FD" \
            || fail_closed "offline checksum candidate generation failed"
        run_clean_bounded 60 bash scripts/lib/security.sh \
            --validate-checksum-candidate checksums.yaml "$raw_candidate" "$report" "${deferred_names[@]}" \
            >"$validated_candidate" 2>&"$MONITOR_LOG_FD" \
            || fail_closed "candidate is not exactly implied by the selected first observations"
        cmp -s -- "$raw_candidate" "$validated_candidate" \
            || fail_closed "candidate validator did not reproduce the exact reviewed candidate bytes"
        CANDIDATE_SHA256="$(sha256_file "$validated_candidate")" \
            || fail_closed "validated checksum candidate is empty or unsafe"
        [[ "$CANDIDATE_SHA256" != "$CURRENT_CHECKSUMS_SHA256" ]] \
            || fail_closed "selected mismatch produced a byte-identical candidate"
    else
        log "no authorized checksum changes to publish"
    fi
    [[ "$(sha256_file "$report")" == "$VERIFICATION_REPORT_SHA256" ]] \
        || fail_closed "verification report changed during candidate preparation"
    [[ "$(sha256_file checksums.yaml)" == "$CURRENT_CHECKSUMS_SHA256" ]] \
        || fail_closed "checksums.yaml changed while validating the candidate"
    require_clean_tree || fail_closed "repository changed while validating the candidate"
    advance_state OBSERVED CANDIDATE_VALIDATED
    advance_state CANDIDATE_VALIDATED AUTHORIZED
}

assert_closed_publication_worktree() {
    local path="" tracked_paths="" untracked_paths="" deleted_paths=""
    # Capture each producer's status before inspecting output. Git's default
    # C quoting keeps pathnames containing newlines on one line; force it so a
    # hostile filename cannot be split into an apparently allowed suffix.
    tracked_paths="$(git -c core.quotePath=true diff --name-only -- 2>&"$MONITOR_LOG_FD")" \
        || return 1
    untracked_paths="$(git -c core.quotePath=true ls-files --others --exclude-standard -- 2>&"$MONITOR_LOG_FD")" \
        || return 1
    deleted_paths="$(git -c core.quotePath=true diff --name-only --diff-filter=D -- 2>&"$MONITOR_LOG_FD")" \
        || return 1
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        [[ -n "${PUBLICATION_PATH_SET[$path]+present}" ]] || {
            log "unexpected tracked mutation: $path"
            return 1
        }
    done <<< "$tracked_paths"
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        [[ -n "${PUBLICATION_PATH_SET[$path]+present}" ]] || {
            log "unexpected untracked path: $path"
            return 1
        }
    done <<< "$untracked_paths"
    if [[ -n "$deleted_paths" ]]; then
        log "publication would contain a deletion"
        return 1
    fi
}

# bun_version_is_acceptable ACTUAL MINIMUM
# True when ACTUAL is a plain X.Y.Z release with the same major as MINIMUM
# and ACTUAL >= MINIMUM. Pre-release/build suffixes and anything that is not
# three dotted integers are rejected (fail closed on the unknown).
bun_version_is_acceptable() {
    local actual="$1" minimum="$2"
    local -a a=() m=()
    [[ "$actual" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
    a=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")
    [[ "$minimum" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
    m=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")
    (( 10#${a[0]} == 10#${m[0]} )) || return 1
    if (( 10#${a[1]} > 10#${m[1]} )); then
        return 0
    elif (( 10#${a[1]} < 10#${m[1]} )); then
        return 1
    fi
    (( 10#${a[2]} >= 10#${m[2]} ))
}

# bun_binary_unsafe_reason BUN_BIN
# Prints why the pinned Bun binary cannot be trusted and returns 1, or prints
# nothing and returns 0. Each condition has its own reason so a fail-closed
# alert says what to fix (#433 only reported "metadata is unsafe").
bun_binary_unsafe_reason() {
    local bin="$1" dir="" uid="" owner="" mode="" links="" inode="" bunx_inode=""
    uid="$(id -u)"
    if [[ ! -f "$bin" || -L "$bin" || ! -x "$bin" ]]; then
        printf 'pinned Bun binary is missing or unsafe: %s\n' "$bin"
        return 1
    fi

    dir="${bin%/*}"
    owner="$(stat -c '%u' -- "$dir" 2>/dev/null || true)"
    mode="$(stat -c '%a' -- "$dir" 2>/dev/null || true)"
    if [[ "$owner" != "$uid" ]]; then
        printf 'pinned Bun directory is owned by uid %s, not %s: %s\n' "${owner:-unknown}" "$uid" "$dir"
        return 1
    fi
    if [[ ! "$mode" =~ ^[0-7]{3,4}$ ]]; then
        printf 'pinned Bun directory mode is unreadable: %s\n' "$dir"
        return 1
    fi
    if (( (8#$mode & 022) != 0 )); then
        printf 'pinned Bun directory is group/world writable (mode %s): %s\n' "$mode" "$dir"
        return 1
    fi

    owner="$(stat -c '%u' -- "$bin" 2>/dev/null || true)"
    mode="$(stat -c '%a' -- "$bin" 2>/dev/null || true)"
    links="$(stat -c '%h' -- "$bin" 2>/dev/null || true)"
    if [[ "$owner" != "$uid" ]]; then
        printf 'pinned Bun binary is owned by uid %s, not %s: %s\n' "${owner:-unknown}" "$uid" "$bin"
        return 1
    fi
    if [[ ! "$mode" =~ ^[0-7]{3,4}$ ]]; then
        printf 'pinned Bun binary mode is unreadable: %s\n' "$bin"
        return 1
    fi
    # nlink==1 is the plain case. Bun's own installer hardlinks bunx to bun in
    # the same directory, so nlink==2 is also legitimate when the extra link is
    # exactly that sibling bunx (same inode). Anything else stays fail-closed (#355).
    if [[ "$links" != "1" ]]; then
        if [[ "$links" != "2" ]]; then
            printf 'pinned Bun binary has %s hard links (trusted: 1, or 2 with the sibling bunx): %s\n' \
                "${links:-unknown}" "$bin"
            return 1
        fi
        if [[ -f "$dir/bunx" && ! -L "$dir/bunx" ]]; then
            inode="$(stat -c '%i' -- "$bin" 2>/dev/null || true)"
            bunx_inode="$(stat -c '%i' -- "$dir/bunx" 2>/dev/null || true)"
        fi
        if [[ -z "$inode" || "$inode" != "$bunx_inode" ]]; then
            # Say where to look and how to recover; on the maintainer host the
            # stray link was perf's root-owned build-id cache, and the bare
            # reason sat in 351 consecutive fail-closed runs.
            inode="$(stat -c '%i' -- "$bin" 2>/dev/null || true)"
            printf 'pinned Bun binary has a second hard link that is not the sibling bunx: %s (inode %s; locate it with: sudo find / -xdev -inum %s; perf build-id caches under /root/.debug are a common source; once it is explained, break the link with a byte-identical copy: cp -p %s %s.new && mv %s.new %s)\n' \
                "$bin" "${inode:-unknown}" "${inode:-INODE}" "$bin" "$bin" "$bin" "$bin"
            return 1
        fi
    fi
    if (( (8#$mode & 022) != 0 )); then
        printf 'pinned Bun binary is group/world writable (mode %s): %s\n' "$mode" "$bin"
        return 1
    fi
    return 0
}

# Consecutive fail-closed runs are tracked so a persistently broken monitor
# (expired gh auth, dead network, wedged clone) alerts a human instead of
# silently leaving checksums unmonitored. Alerting is strictly best-effort:
# it must never mask the fail-closed exit or itself abort the trap path.
FAIL_STREAK_FILE="$STATE_DIR/fail_closed_streak"
# Last alert actually posted: "<epoch>\t<reason>". Alerts are deduplicated on
# it so an unchanged failure produces one issue comment per day, not one
# every 24 runs (the old cadence posted the identical text every ~6h for
# two weeks on #355).
FAIL_ALERT_FILE="$STATE_DIR/fail_closed_alert"
FAIL_PUSH_ALERT_FILE="$STATE_DIR/fail_closed_push_alert"
RECOVERY_PENDING_FILE="$STATE_DIR/fail_closed_recovery_pending"
FAIL_ALERT_REPEAT_SECONDS=86400
FAIL_ALERT_MIN_STREAK=3
FAIL_STREAK_MAX=2147483647
FAIL_ALERT_RECORD_MAX_BYTES=4096

# Only the lock-owning shell may account for a run. Library sourcing and
# diagnostics leave these unarmed; inherited subshells cannot record a second
# failure for the parent's run. STATE is deliberately not an outcome receipt.
MONITOR_RUN_PID=""
MONITOR_TERMINAL_OUTCOME=""

# Bash otherwise interprets leading zeroes as octal and wraps large integers.
# Eighteen decimal digits fit in its signed 64-bit arithmetic on our Linux host.
_monitor_decimal() {
    local value="${1:-}"
    [[ "$value" =~ ^[0-9]{1,18}$ ]] || return 1
    printf '%s\n' "$((10#$value))"
}

# These bookkeeping paths carry no publication authority. Validate the parent
# and each existing leaf before reading or replacing it, including hard links.
# Legacy owner-readable 0644 records remain usable; replacements are private.
_monitor_notice_component() {
    case "$1" in
        "$FAIL_STREAK_FILE") printf 'failure_counter\n' ;;
        "$FAIL_ALERT_FILE") printf 'github_cooldown\n' ;;
        "$FAIL_PUSH_ALERT_FILE") printf 'private_cooldown\n' ;;
        "$RECOVERY_PENDING_FILE") printf 'recovery_pending\n' ;;
        *) printf 'state_record\n' ;;
    esac
}

_monitor_notice_record_path() {
    local record_file="$1" component="" metadata="" owner="" mode="" links="" mode_value=0 monitor_uid=""
    component="$(_monitor_notice_component "$record_file")"
    case "$record_file" in
        "$FAIL_STREAK_FILE"|"$FAIL_ALERT_FILE"|"$FAIL_PUSH_ALERT_FILE"|"$RECOVERY_PENDING_FILE") ;;
        *) return "$(_monitor_refusal_code state_record invalid_input)" ;;
    esac
    monitor_uid="$(id -u)" || return "$(_monitor_refusal_code state_directory metadata_unavailable)"
    [[ "$monitor_uid" =~ ^[0-9]+$ ]] || return "$(_monitor_refusal_code state_directory metadata_unavailable)"
    [[ ! -L "$STATE_DIR" ]] || return "$(_monitor_refusal_code state_directory symlink)"
    [[ -e "$STATE_DIR" ]] || return "$(_monitor_refusal_code state_directory missing)"
    [[ -d "$STATE_DIR" ]] || return "$(_monitor_refusal_code state_directory wrong_type)"
    metadata="$(stat -c '%u:%a' -- "$STATE_DIR" 2>/dev/null)" \
        || return "$(_monitor_refusal_code state_directory metadata_unavailable)"
    IFS=: read -r owner mode <<< "$metadata"
    [[ "$owner" =~ ^[0-9]+$ && "$mode" =~ ^[0-7]{3,4}$ ]] \
        || return "$(_monitor_refusal_code state_directory metadata_unavailable)"
    [[ "$owner" == "$monitor_uid" ]] || return "$(_monitor_refusal_code state_directory owner_mismatch)"
    mode_value=$((8#$mode))
    (( (mode_value & 022) == 0 )) || return "$(_monitor_refusal_code state_directory group_or_world_writable)"
    if [[ -e "$record_file" || -L "$record_file" ]]; then
        [[ ! -L "$record_file" ]] || return "$(_monitor_refusal_code "$component" symlink)"
        [[ -f "$record_file" ]] || return "$(_monitor_refusal_code "$component" wrong_type)"
        metadata="$(stat -c '%u:%a:%h' -- "$record_file" 2>/dev/null)" \
            || return "$(_monitor_refusal_code "$component" metadata_unavailable)"
        IFS=: read -r owner mode links <<< "$metadata"
        [[ "$owner" =~ ^[0-9]+$ && "$links" =~ ^[0-9]+$ && "$mode" =~ ^[0-7]{3,4}$ ]] \
            || return "$(_monitor_refusal_code "$component" metadata_unavailable)"
        [[ "$owner" == "$monitor_uid" ]] || return "$(_monitor_refusal_code "$component" owner_mismatch)"
        if [[ "$links" != 1 ]]; then
            [[ "$links" != 0 ]] || return "$(_monitor_refusal_code "$component" identity_changed)"
            return "$(_monitor_refusal_code "$component" multiple_links)"
        fi
        mode_value=$((8#$mode))
        (( (mode_value & 022) == 0 )) || return "$(_monitor_refusal_code "$component" group_or_world_writable)"
        (( (mode_value & 0400) != 0 )) || return "$(_monitor_refusal_code "$component" owner_permissions)"
        [[ "$record_file" != "$RECOVERY_PENDING_FILE" || "$mode" == 600 ]] \
            || return "$(_monitor_refusal_code "$component" private_mode_required)"
    fi
}

# The existing cooldown format is one complete epoch<TAB>reason<LF> record.
# Do not truncate reasons: distinct failures must not share an accidental key.
_monitor_cooldown_content_valid() {
    local content="$1" payload="" epoch="" reason="" LC_ALL=C
    (( ${#content} <= FAIL_ALERT_RECORD_MAX_BYTES )) || return 1
    [[ "$content" == *$'\n' ]] || return 1
    payload="${content%$'\n'}"
    [[ "$payload" == *$'\t'* ]] || return 1
    epoch="${payload%%$'\t'*}"
    reason="${payload#*$'\t'}"
    [[ ! "$reason" =~ [[:cntrl:]] ]] || return 1
    epoch="$(_monitor_decimal "$epoch")" || return 1
    (( epoch > 0 ))
}

_read_monitor_cooldown_record() {
    local record_file="$1" content="" size="" reader_pid=""
    case "$record_file" in
        "$FAIL_ALERT_FILE"|"$FAIL_PUSH_ALERT_FILE") ;;
        *) return 1 ;;
    esac
    _monitor_notice_record_path "$record_file" || return 1
    [[ -f "$record_file" ]] || return 1
    size="$(stat -c '%s' -- "$record_file" 2>/dev/null)" || return 1
    [[ "$size" =~ ^[0-9]{1,10}$ ]] || return 1
    (( size > 0 && size <= FAIL_ALERT_RECORD_MAX_BYTES )) || return 1
    # read -d '' preserves the final LF and stops at a NUL. The exact bounded
    # comparison below rejects NULs, extra lines and a valid-looking prefix.
    IFS= read -r -d '' content < <(/usr/bin/head -c "$((FAIL_ALERT_RECORD_MAX_BYTES + 1))" -- "$record_file" 2>/dev/null) || true
    reader_pid=$!
    wait "$reader_pid" || return 1
    _monitor_cooldown_content_valid "$content" || return 1
    printf '%s' "$content" | cmp -s -- "$record_file" - || return 1
    printf '%s' "$content"
}

_read_failure_streak() {
    local value="" reader_pid=""
    _monitor_notice_record_path "$FAIL_STREAK_FILE" || return "$?"
    if [[ -f "$FAIL_STREAK_FILE" ]]; then
        # Bound malformed state reads. A long numeric record saturates rather
        # than wrapping negative and disabling the alert threshold.
        IFS= read -r value < <(/usr/bin/head -c 64 -- "$FAIL_STREAK_FILE" 2>/dev/null) || true
        reader_pid=$!
        wait "$reader_pid" || return "$(_monitor_refusal_code failure_counter io_failure)"
    fi
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        printf '0\n'
        return 0
    fi
    if [[ ${#value} -eq 64 ]]; then
        printf '%s\n' "$FAIL_STREAK_MAX"
        return 0
    fi
    while [[ ${#value} -gt 1 && "$value" == 0* ]]; do
        value="${value#0}"
    done
    if [[ ${#value} -gt 10 ]]; then
        printf '%s\n' "$FAIL_STREAK_MAX"
    else
        value="$(_monitor_decimal "$value")"
        if (( value > FAIL_STREAK_MAX )); then
            value="$FAIL_STREAK_MAX"
        fi
        printf '%s\n' "$value"
    fi
}

# _fail_alert_due STREAK REASON [NOW_EPOCH [RECORD_FILE [MODE]]]
# True when an alert should be posted for this failure: the streak has just
# reached the alert threshold, the reason differs from the last posted alert,
# or the last alert is older than FAIL_ALERT_REPEAT_SECONDS. count-unavailable
# bypasses the threshold without inventing a count. REASON is the exact stored
# comparison key. Pure: reads the selected channel record, never writes it.
_fail_alert_due() {
    local streak="$1" reason="$2" now="${3:-}"
    local record_file="${4:-$FAIL_ALERT_FILE}" count_mode="${5:-normal}"
    local last_epoch="" last_reason="" record=""
    case "$count_mode" in
        normal)
            streak="$(_monitor_decimal "$streak")" || return 1
            (( streak >= FAIL_ALERT_MIN_STREAK )) || return 1
            ;;
        count-unavailable) ;;
        *) return 1 ;;
    esac
    [[ -n "$now" ]] || now="$(date -u +%s 2>/dev/null || echo 0)"
    now="$(_monitor_decimal "$now")" || return 0
    (( now > 0 )) || return 0
    record="$(_read_monitor_cooldown_record "$record_file")" || return 0
    last_epoch="${record%%$'\t'*}"
    last_reason="${record#*$'\t'}"
    last_epoch="$(_monitor_decimal "$last_epoch")" || return 0
    [[ "$last_reason" == "$reason" ]] || return 0    # the failure changed: say so
    # Clock rollback or corrupt future state must not silence alerts forever.
    (( last_epoch <= now )) || return 0
    (( now - last_epoch >= FAIL_ALERT_REPEAT_SECONDS ))
}

_fail_alert_record() {
    local reason="$1" now="${2:-}"
    local record_file="${3:-$FAIL_ALERT_FILE}" refusal_status=0
    [[ -n "$now" ]] || now="$(date -u +%s 2>/dev/null || echo 0)"
    now="$(_monitor_decimal "$now")" || return 0
    (( now > 0 )) || return 0
    if _write_monitor_notice_record "$record_file" "$now"$'\t'"$reason"$'\n'; then
        :
    else
        refusal_status=$?
        _monitor_failure_log "WARNING: failure notification was delivered but its cooldown could not be persisted [state_refusal=$(_monitor_refusal_label "$refusal_status")]"
    fi
    return 0
}

# public_text TEXT: TEXT with the monitor user's home directory written as ~.
# Anything posted to GitHub goes through it: issues are public, and the
# home path names the account (fail-closed reasons often carry paths).
public_text() {
    # shellcheck disable=SC2088  # a literal ~ is the point
    local text="$1" home_prefix="${HOME:-}/" tilde_prefix='~/'
    [[ "$home_prefix" == / || "$home_prefix" == // ]] || text="${text//"$home_prefix"/$tilde_prefix}"
    printf '%s' "$text"
}

_alert_fail_closed_streak() {
    local streak="$1" reason="$2" count_mode="${3:-normal}" count_refusal="${4:-}" failure_text=""
    case "$count_mode" in
        normal)
            failure_text="ACFS checksum monitor has failed closed $streak times in a row."
            ;;
        count-unavailable)
            reason="$reason. Failure count could not be persisted; consecutive count unavailable."
            if [[ -n "$count_refusal" ]]; then
                count_refusal="$(_monitor_refusal_label "$(_monitor_refusal_code "${count_refusal%%.*}" "${count_refusal#*.}")")"
                reason="$reason [count_refusal=$count_refusal]"
            fi
            failure_text="ACFS checksum monitor has failed closed. The consecutive failure count is unavailable because monitoring state could not be persisted."
            ;;
        *) return 0 ;;
    esac
    local github_due=false push_due=false
    if _fail_alert_due "$streak" "$reason" "" "$FAIL_ALERT_FILE" "$count_mode"; then
        github_due=true
    fi
    if [[ -n "${ACFS_NTFY_TOPIC:-}" ]] && _fail_alert_due "$streak" "$reason" "" "$FAIL_PUSH_ALERT_FILE" "$count_mode"; then
        push_due=true
    fi
    [[ "$github_due" == true || "$push_due" == true ]] || return 0
    # A log failure may be the incident itself. Hold a usable output sink so
    # failed redirection cannot prevent an otherwise deliverable notification.
    # Keep diagnostics in the ordinary log when possible, otherwise stderr is
    # retained by the service journal. Never open a known link or special file.
    local notification_fd=""
    if _prepare_monitor_log \
        && { exec {notification_fd}>&"$MONITOR_LOG_FD"; } 2>/dev/null; then
        :
    else
        exec {notification_fd}>&2 || return 0
    fi
    # The GitHub issue is public, so it names neither the host nor the home
    # directory; the private push does, so the operator knows where to look.
    local alert_msg=""
    alert_msg="$(public_text "$failure_text Latest reason: $reason. Checksum drift is NOT being monitored until this is fixed. Run: $RUN_TS. See $LOG_DIR on the monitor host. (Repeated at most once per 24h while the reason is unchanged and delivery state can be persisted.)")"
    local push_msg="$failure_text Monitor host: $(hostname 2>/dev/null || echo unknown-host). Latest reason: $reason. Checksum drift is NOT being monitored until this is fixed. Run: $RUN_TS. See $LOG_DIR. (Repeated at most once per 24h while the reason is unchanged and delivery state can be persisted.)"
    # Optional push notification
    if [[ "$push_due" == true ]]; then
        if curl -fsS -m 10 -A "acfs (+https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup)" \
            -d "$push_msg" "https://ntfy.sh/${ACFS_NTFY_TOPIC}" \
            >&"$notification_fd" 2>&1; then
            _fail_alert_record "$reason" "" "$FAIL_PUSH_ALERT_FILE"
        fi
    fi
    # A delivered push has its own cooldown. Failed GitHub posts still retry,
    # and a delivered GitHub post must not silence retries of a failed push.
    if [[ "$github_due" != true ]]; then
        exec {notification_fd}>&- || true
        return 0
    fi
    # GitHub issue (deduped by label + search, same pattern as the
    # external-change review issue below)
    local repo_slug="Dicklesworthstone/agentic_coding_flywheel_setup"
    local existing=""
    existing="$(run_failure_bounded gh issue list --repo "$repo_slug" --state open \
        --label monitoring \
        --search "Checksum monitor failing closed" \
        --json number -q '.[0].number' 2>&"$notification_fd" || true)"
    local posted=false
    if [[ -n "$existing" && "$existing" != "null" ]]; then
        if run_failure_bounded gh issue comment "$existing" --repo "$repo_slug" \
            --body "$alert_msg" >&"$notification_fd" 2>&1; then
            _monitor_failure_log "commented on existing monitoring issue #$existing"
            posted=true
        fi
    else
        if run_failure_bounded gh issue create --repo "$repo_slug" \
            --title "🚨 Checksum monitor failing closed - checksums unmonitored" \
            --label monitoring \
            --body "$alert_msg" >&"$notification_fd" 2>&1; then
            _monitor_failure_log "created monitoring alert issue"
            posted=true
        elif run_failure_bounded gh issue create --repo "$repo_slug" \
            --title "🚨 Checksum monitor failing closed - checksums unmonitored" \
            --body "$alert_msg" >&"$notification_fd" 2>&1; then
            # The label exists in the canonical repo; if it is ever missing,
            # an unlabeled alert (dedupe degraded) beats no alert at all.
            _monitor_failure_log "created monitoring alert issue (unlabeled fallback)"
            posted=true
        fi
    fi
    # Only a delivered alert starts the repeat window; a failed post (gh
    # auth, network) is retried on the next run instead of going quiet.
    if [[ "$posted" == "true" ]]; then
        _fail_alert_record "$reason"
    fi
    exec {notification_fd}>&- || true
}

# Monitoring state carries no publication authority. Keep it bounded and
# private nevertheless: never follow a linked record or write through one.
# Atomic replacement preserves the previous record when a write fails. Failed
# temporary writes are retained; none of the observation evidence is touched.
_write_monitor_notice_record() {
    local record_file="$1" content="$2" component="" temporary="" streak=""
    component="$(_monitor_notice_component "$record_file")"
    case "$record_file" in
        "$FAIL_STREAK_FILE")
            streak="${content%$'\n'}"
            [[ "$content" == "$streak"$'\n' && "$streak" =~ ^(0|[1-9][0-9]{0,9})$ ]] \
                || return "$(_monitor_refusal_code "$component" invalid_input)"
            (( streak <= FAIL_STREAK_MAX )) || return "$(_monitor_refusal_code "$component" invalid_input)"
            ;;
        "$RECOVERY_PENDING_FILE")
            if [[ -n "$content" ]]; then
                streak="${content%$'\n'}"
                [[ "$content" == "$streak"$'\n' && "$streak" =~ ^(0|[1-9][0-9]{0,9})$ ]] \
                    || return "$(_monitor_refusal_code "$component" invalid_input)"
                (( streak == 0 || (streak >= FAIL_ALERT_MIN_STREAK && streak <= FAIL_STREAK_MAX) )) \
                    || return "$(_monitor_refusal_code "$component" invalid_input)"
            fi
            ;;
        "$FAIL_ALERT_FILE"|"$FAIL_PUSH_ALERT_FILE")
            [[ -z "$content" ]] || _monitor_cooldown_content_valid "$content" \
                || return "$(_monitor_refusal_code "$component" invalid_input)"
            ;;
        *) return "$(_monitor_refusal_code state_record invalid_input)" ;;
    esac
    _monitor_notice_record_path "$record_file" || return "$?"
    temporary="$(mktemp "$STATE_DIR/notice-state.XXXXXX")" \
        || return "$(_monitor_refusal_code "$component" io_failure)"
    ( umask 077; printf '%s' "$content" > "$temporary" ) \
        || return "$(_monitor_refusal_code "$component" io_failure)"
    mv -fT -- "$temporary" "$record_file" \
        || return "$(_monitor_refusal_code "$component" io_failure)"
    return 0
}

_read_recovery_pending_streak() {
    local value=""
    if [[ ! -e "$RECOVERY_PENDING_FILE" && ! -L "$RECOVERY_PENDING_FILE" ]]; then
        printf '0\n'
        return 0
    fi
    private_download_evidence_path "$RECOVERY_PENDING_FILE" file 64 || return 1
    if [[ ! -s "$RECOVERY_PENDING_FILE" ]]; then
        printf '0\n'
        return 0
    fi
    value="$(head -c 64 -- "$RECOVERY_PENDING_FILE" 2>/dev/null)" || return 1
    value="$(_monitor_decimal "$value")" || return 1
    (( value == 0 || (value >= FAIL_ALERT_MIN_STREAK && value <= FAIL_STREAK_MAX) )) || return 1
    # A bounded Bash read alone would lose NULs and trailing newlines. Exact
    # comparison also rejects extra lines, control bytes and noncanonical counts.
    printf '%s\n' "$value" | cmp -s -- "$RECOVERY_PENDING_FILE" - || return 1
    printf '%s\n' "$value"
}

_queue_recovery_notice() {
    local previous_streak="$1" pending=0 recorded=0
    previous_streak="$(_monitor_decimal "$previous_streak")" || return 1
    (( previous_streak <= FAIL_STREAK_MAX )) || return 1
    if ! pending="$(_read_recovery_pending_streak)"; then
        log "WARNING: ignoring unsafe or malformed pending recovery state"
        pending=0
    fi
    recorded="$pending"
    if (( previous_streak >= FAIL_ALERT_MIN_STREAK )); then
        recorded="$previous_streak"
    fi
    if (( recorded > 0 && recorded != pending )); then
        _write_monitor_notice_record "$RECOVERY_PENDING_FILE" "$recorded"$'\n' \
            || log "WARNING: recovery notification could not be persisted; a failed delivery may not survive this run"
    fi
    printf '%s\n' "$recorded"
}

# Deliver only after a fresh accepted run. A queued notice can outlive a short
# intervening failure, so its streak is explicitly historical; the current
# result and run identifier always describe the newly accepted observation.
_announce_recovery() {
    local recorded_streak="$1" outcome="$2" status_text=""
    case "$outcome:$STATE" in
        ok:HEALTHY) status_text="Verification and publication checks passed; current state: HEALTHY." ;;
        deferred:DEFERRED)
            status_text="Verification and publication checks passed; current state: DEFERRED. Unapproved external checksum changes remain pinned pending human authorization."
            ;;
        *) return 1 ;;
    esac
    recorded_streak="$(_monitor_decimal "$recorded_streak")" || return 1
    (( recorded_streak >= FAIL_ALERT_MIN_STREAK && recorded_streak <= FAIL_STREAK_MAX )) || return 0
    # Library callers may not have prepared a run log. Refresh a changed name
    # before any delivery diagnostics; rejected logs leave the safe stderr sink.
    _prepare_monitor_log || true
    local repo_slug="Dicklesworthstone/agentic_coding_flywheel_setup"
    local existing=""
    local msg="ACFS checksum monitor completed an accepted run. Previously recorded fail-closed streak: $recorded_streak. Run: $RUN_TS. $status_text"
    if ! existing="$(run_failure_bounded gh issue list --repo "$repo_slug" --state open \
        --label monitoring \
        --search "Checksum monitor failing closed" \
        --json number -q '.[0].number' 2>&"$MONITOR_LOG_FD")"; then
        log "WARNING: recovery issue lookup failed; notification remains pending"
        return 1
    fi
    if [[ -n "$existing" && "$existing" != "null" ]]; then
        [[ "$existing" =~ ^[1-9][0-9]{0,17}$ ]] || {
            log "WARNING: recovery issue lookup returned an invalid issue number; notification remains pending"
            return 1
        }
        if ! run_failure_bounded gh issue comment "$existing" --repo "$repo_slug" \
            --body "$msg" >&"$MONITOR_LOG_FD" 2>&1; then
            log "WARNING: recovery notification delivery failed; notification remains pending"
            return 1
        fi
        log "posted recovery note on monitoring issue #$existing"
    fi
    # A successful empty lookup needs no new issue. Failed lookups/posts retain
    # the pending record. An ambiguous delivery or failed acknowledgement may
    # repeat the notice; never claim exactly-once delivery from a CLI exit code.
    _write_monitor_notice_record "$RECOVERY_PENDING_FILE" '' || {
        log "WARNING: recovery notification acknowledgement could not be persisted; delivery may be retried"
        return 1
    }
}

# Called only after evidence, authorization consumption and remote acceptance.
# Notification failures cannot invalidate a verified publication. Persist the
# retry obligation first, then reset cooldowns before clearing the streak: a
# crash can repeat an alert, but must not suppress the next outage's alert.
record_accepted_monitor_outcome() {
    local outcome="$1" previous_streak=0 recorded_streak=0 next_state="" refusal_status=0
    [[ "$STATE" == REMOTE_VERIFIED ]] || return 1
    case "$outcome" in
        ok) next_state=HEALTHY ;;
        deferred) next_state=DEFERRED ;;
        *) return 1 ;;
    esac
    if previous_streak="$(_read_failure_streak)"; then
        :
    else
        refusal_status=$?
        fail_closed "remote publication is verified but failure-count state could not be safely read [state_refusal=$(_monitor_refusal_label "$refusal_status")]"
    fi
    recorded_streak="$(_queue_recovery_notice "$previous_streak")" || {
        log "WARNING: could not prepare recovery notification state"
        recorded_streak=0
    }
    _write_monitor_notice_record "$FAIL_ALERT_FILE" '' \
        || log "WARNING: could not reset GitHub failure alert cooldown"
    _write_monitor_notice_record "$FAIL_PUSH_ALERT_FILE" '' \
        || log "WARNING: could not reset private failure alert cooldown"
    if _write_monitor_notice_record "$FAIL_STREAK_FILE" $'0\n'; then
        :
    else
        refusal_status=$?
        fail_closed "remote publication is verified but the healthy-state marker could not be written [state_refusal=$(_monitor_refusal_label "$refusal_status")]"
    fi
    advance_state REMOTE_VERIFIED "$next_state" || return 1
    # Required acceptance is complete. A later notification interruption must
    # preserve its pending notice without inventing another verification outage.
    MONITOR_TERMINAL_OUTCOME="accepted"
    _announce_recovery "$recorded_streak" "$outcome" || true
}

_record_monitor_failure() {
    local reason="$*"
    if [[ -n "$MONITOR_RUN_PID" && "$BASHPID" != "$MONITOR_RUN_PID" ]]; then
        # Preserve the child's explanation locally without claiming a
        # terminal parent failure: the caller may deliberately handle it.
        _monitor_failure_log "subprocess failed closed: $reason"
        return 0
    fi
    if [[ -n "$MONITOR_RUN_PID" ]]; then
        case "$MONITOR_TERMINAL_OUTCOME" in
            accepted|failed) return 0 ;;
        esac
    fi
    # Claim the terminal outcome before any best-effort operation. In the
    # armed owner, ignore repeated termination signals while bounded failure
    # notification runs; EXIT still preserves the caller's final status.
    if [[ -n "$MONITOR_RUN_PID" ]]; then
        trap ':' HUP INT TERM
    fi
    MONITOR_TERMINAL_OUTCOME="failed"
    local streak=0 count_mode=normal summary_streak="" count_refusal="" refusal_status=0
    if streak="$(_read_failure_streak)"; then
        if (( streak < FAIL_STREAK_MAX )); then
            streak=$((streak + 1))
        fi
        if _write_monitor_notice_record "$FAIL_STREAK_FILE" "$streak"$'\n'; then
            :
        else
            refusal_status=$?
            count_mode=count-unavailable
            count_refusal="$(_monitor_refusal_label "$refusal_status")"
        fi
    else
        refusal_status=$?
        streak=0
        count_mode=count-unavailable
        count_refusal="$(_monitor_refusal_label "$refusal_status")"
    fi
    summary_streak="$streak"
    if [[ "$count_mode" == count-unavailable ]]; then
        summary_streak=unknown
        _monitor_failure_log "WARNING: failure count could not be persisted; consecutive count unavailable [count_refusal=$count_refusal]"
    fi
    # A broken log must not prevent streak accounting or notification. The
    # existing logger also emits to stderr, retained by the service journal.
    _monitor_failure_log "FAIL-CLOSED: $reason"
    _alert_fail_closed_streak "$streak" "$reason" "$count_mode" "$count_refusal" || true
    _monitor_failure_log "summary: result=fail_closed state=$STATE streak=$summary_streak repo=$MONITOR_REPO"
    return 0
}

_monitor_failure_log() {
    # log always mirrors to stderr, including when a named log is rejected.
    # Do not emit a second terminal summary to the journal on that failure.
    log "$*" || true
}

fail_closed() {
    _record_monitor_failure "$*" || true
    exit 1
}

_monitor_exit_handler() {
    local exit_status="$1" original_status="$1"
    [[ "$BASHPID" == "$MONITOR_RUN_PID" ]] || return "$exit_status"
    trap - EXIT
    trap ':' HUP INT TERM
    case "$MONITOR_TERMINAL_OUTCOME" in
        accepted|failed) ;;
        *)
            # An early `exit 0` is not proof that verification and remote
            # acceptance happened. Never turn an interrupted run green.
            (( exit_status != 0 )) || exit_status=1
            _record_monitor_failure "monitor exited unexpectedly before acceptance (exit=$original_status)" || true
            ;;
    esac
    exit "$exit_status"
}

_monitor_signal_handler() {
    local signal_name="$1" exit_status="$2"
    if [[ "$BASHPID" == "$MONITOR_RUN_PID" ]]; then
        trap ':' HUP INT TERM
        _record_monitor_failure "monitor interrupted by $signal_name before acceptance" || true
    fi
    exit "$exit_status"
}

arm_monitor_exit_handlers() {
    MONITOR_RUN_PID="$BASHPID"
    MONITOR_TERMINAL_OUTCOME="running"
    trap '_monitor_exit_handler "$?"' EXIT
    trap '_monitor_signal_handler HUP 129' HUP
    trap '_monitor_signal_handler INT 130' INT
    trap '_monitor_signal_handler TERM 143' TERM
}

checksum_monitor_main() {
# ---- single-instance lock (timer overlap is a silent no-op) ----
local state_refusal_status=0
if _open_monitor_lock; then
    :
else
    state_refusal_status=$?
    fail_closed "could not open a safe monitor lock file [state_refusal=$(_monitor_refusal_label "$state_refusal_status")]"
fi
local lock_status=0
if flock -n -E 200 9; then
    :
else
    lock_status=$?
    # Another run is active; skipping is the correct behavior for a
    # 15-minute timer. An explicit contention code distinguishes that normal
    # condition from a broken lock utility or descriptor (which must alert).
    if [[ "$lock_status" -eq 200 ]]; then
        exit 0
    fi
    fail_closed "could not acquire monitor lock (flock exit=$lock_status)"
fi
if _monitor_lock_is_current; then
    :
else
    state_refusal_status=$?
    fail_closed "monitor lock path changed or became unsafe while acquiring it [state_refusal=$(_monitor_refusal_label "$state_refusal_status")]"
fi
arm_monitor_exit_handlers

if _prepare_monitor_log; then
    :
else
    state_refusal_status=$?
    fail_closed "could not open a safe monitor log file [state_refusal=$(_monitor_refusal_label "$state_refusal_status")]"
fi

advance_state INIT LOCKED

log "ACFS checksum monitor starting (repo: $MONITOR_REPO)"

# Monitor location/notification overrides were captured above. Everything
# capable of redirecting Git, checksum, manifest, plugin, or package-manager
# behavior is removed before the first repository observation.
unset CHECKSUMS_FILE ACFS_REPO_ROOT ACFS_MANIFEST_YAML ACFS_CHECKSUMS_YAML
unset ACFS_VERIFIED_INSTALLER_CACHE ACFS_REPO_OWNER ACFS_REPO_NAME ACFS_CHECKSUMS_REF
unset ACFS_CURL_BIN ACFS_PLUGIN_PATHS ACFS_PLUGINS_DIR
unset BUN_INSTALL BUN_CONFIG_REGISTRY npm_config_registry NPM_CONFIG_REGISTRY
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG_SYSTEM GIT_CONFIG_GLOBAL
unset GIT_CONFIG_NOSYSTEM GIT_CONFIG_COUNT GIT_CEILING_DIRECTORIES GIT_NAMESPACE
unset GIT_QUARANTINE_PATH GIT_REPLACE_REF_BASE GIT_SSH_COMMAND GIT_SSH_VARIANT
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE
unset GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_DATE
unset GIT_ASKPASS SSH_ASKPASS GH_HOST GH_REPO
for system_prefix in /usr/local/bin /usr/bin /bin; do
    [[ -d "$system_prefix" ]] || continue
    prefix_real="$(/usr/bin/readlink -f -- "$system_prefix" 2>/dev/null || true)"
    prefix_owner="$(/usr/bin/stat -c '%u' -- "$prefix_real" 2>/dev/null || true)"
    prefix_mode="$(/usr/bin/stat -c '%a' -- "$prefix_real" 2>/dev/null || true)"
    [[ "$prefix_real" == /* && "$prefix_owner" == "0" && "$prefix_mode" =~ ^[0-7]{3,4}$ ]] \
        || fail_closed "trusted system prefix metadata is unsafe: $system_prefix"
    prefix_mode_value=$((8#$prefix_mode))
    (( (prefix_mode_value & 022) == 0 )) \
        || fail_closed "trusted system prefix is group/world writable: $system_prefix -> $prefix_real"
done
# Each dependency must be REACHED through one of the trusted prefixes checked
# above (so a user-writable PATH entry can never shadow it), and must RESOLVE
# to a root-owned, non-writable regular file inside a root-owned, non-writable
# directory of the distro-managed tree. The resolved target is deliberately
# not confined to the bin prefixes: Ubuntu 25.10+ ships uutils coreutils, so
# /usr/bin/env, sha256sum, stat, ... are symlinks into
# /usr/lib/cargo/bin/coreutils/, which is exactly as distro-managed as
# /usr/bin. Confining the target to /usr/bin failed closed on every such host
# (issue #344); the directory and file metadata checks below carry the actual
# trust decision.
for dep in bash env git gh jq curl flock sha256sum stat sort uniq awk sed tr cmp mktemp paste head id cp mv timeout readlink date tee mkdir hostname cat; do
    dep_path="$(command -v "$dep" 2>/dev/null || true)"
    [[ "$dep_path" == /* ]] || fail_closed "missing dependency: $dep"
    case "$dep_path" in
        /usr/local/bin/*|/usr/bin/*|/bin/*) ;;
        *) fail_closed "dependency is not reached through a trusted system prefix: $dep -> $dep_path" ;;
    esac
    dep_real="$(/usr/bin/readlink -f -- "$dep_path" 2>/dev/null || true)"
    case "$dep_real" in
        /usr/bin/*|/usr/local/bin/*|/usr/lib/*|/usr/libexec/*) ;;
        *) fail_closed "dependency resolves outside the distro-managed tree: $dep -> ${dep_real:-unresolved}" ;;
    esac
    [[ -f "$dep_real" && -x "$dep_real" ]] \
        || fail_closed "dependency is not a regular executable: $dep -> $dep_real"
    dep_dir="${dep_real%/*}"
    dep_dir_owner="$(/usr/bin/stat -c '%u' -- "$dep_dir" 2>/dev/null || true)"
    dep_dir_mode="$(/usr/bin/stat -c '%a' -- "$dep_dir" 2>/dev/null || true)"
    [[ "$dep_dir_owner" == "0" && "$dep_dir_mode" =~ ^[0-7]{3,4}$ ]] \
        || fail_closed "dependency directory metadata is unsafe: $dep -> $dep_dir"
    dep_dir_mode_value=$((8#$dep_dir_mode))
    (( (dep_dir_mode_value & 022) == 0 )) \
        || fail_closed "dependency directory is group/world writable: $dep -> $dep_dir"
    dep_owner="$(/usr/bin/stat -c '%u' -- "$dep_real" 2>/dev/null || true)"
    dep_mode="$(/usr/bin/stat -c '%a' -- "$dep_real" 2>/dev/null || true)"
    [[ "$dep_owner" == "0" && "$dep_mode" =~ ^[0-7]{3,4}$ ]] \
        || fail_closed "dependency metadata is unsafe: $dep -> $dep_real"
    dep_mode_value=$((8#$dep_mode))
    (( (dep_mode_value & 022) == 0 )) \
        || fail_closed "dependency is group/world writable: $dep -> $dep_real"
done

bun_unsafe_reason="$(bun_binary_unsafe_reason "$BUN_BIN")" \
    || fail_closed "$bun_unsafe_reason"

[[ -d "$MONITOR_REPO/.git" ]] || fail_closed "monitor clone not found at $MONITOR_REPO"
cd "$MONITOR_REPO" || fail_closed "could not enter monitor clone at $MONITOR_REPO"
origin_url="$(git remote get-url origin 2>/dev/null || true)"
case "$origin_url" in
    https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup|\
    https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup.git|\
    git@github.com:Dicklesworthstone/agentic_coding_flywheel_setup.git) ;;
    *) fail_closed "origin does not name the canonical ACFS repository: ${origin_url:-missing}" ;;
esac

# ---- CLEAN_BASE: clean main, then one ff-only synchronization ----
[[ "$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)" == "main" ]] \
    || fail_closed "monitor clone must already be on main"
require_clean_tree \
    || fail_closed "monitor clone has local tracked, staged, or untracked changes"
run_bounded 60 git fetch --quiet origin main master 2>&"$MONITOR_LOG_FD" \
    || fail_closed "fetch of main and legacy mirror failed"
read_remote_heads || fail_closed "could not resolve exactly one remote main and mirror ref"
[[ "$REMOTE_MAIN_HEAD" == "$REMOTE_MASTER_HEAD" ]] \
    || fail_closed "remote main and legacy mirror differ before observation"
if ! git -c core.hooksPath=/dev/null merge --ff-only --quiet \
    refs/remotes/origin/main 2>&"$MONITOR_LOG_FD"; then
    fail_closed "local main is not an exact fast-forward of origin/main"
fi
BASE_HEAD="$(git rev-parse HEAD 2>/dev/null || true)"
[[ "$BASE_HEAD" =~ ^[0-9a-f]{40}$ && "$BASE_HEAD" == "$REMOTE_MAIN_HEAD" ]] \
    || fail_closed "local HEAD is not the fetched remote base"
require_clean_tree || fail_closed "clone is not clean after synchronization"

actual_bun_version="$(run_bun_clean --version 2>&"$MONITOR_LOG_FD" || true)"
bun_version_is_acceptable "$actual_bun_version" "$MINIMUM_BUN_VERSION" \
    || fail_closed "Bun version unacceptable: need $MINIMUM_BUN_VERSION or a newer ${MINIMUM_BUN_VERSION%%.*}.x release, found ${actual_bun_version:-unavailable}"
log "bun $actual_bun_version accepted (floor $MINIMUM_BUN_VERSION)"
( cd packages/manifest \
    && run_bun_clean_bounded 90 install --frozen-lockfile --ignore-scripts --silent >&"$MONITOR_LOG_FD" 2>&1 ) \
    || fail_closed "frozen, lifecycle-disabled Bun install failed in packages/manifest"
require_clean_tree || fail_closed "dependency preparation changed tracked or untracked repository state"
advance_state LOCKED CLEAN_BASE
log "clean base pinned to $BASE_HEAD"

# ---- OBSERVED: drift plus the first and only authoritative network report ----
drift_json="$(mktemp "$STATE_DIR/drift-$RUN_TS.XXXXXX.json")" \
    || fail_closed "could not allocate drift evidence file"
set +e
run_clean_bounded 120 bash scripts/check-manifest-drift.sh --json >"$drift_json" 2>&"$MONITOR_LOG_FD"
drift_exit=$?
set -e
validate_drift_report "$drift_json" \
    || fail_closed "drift checker returned data outside its strict JSON contract"

drift_detected="$(jq -r '.drift_detected' "$drift_json")"
if [[ "$drift_exit" -eq 0 && "$drift_detected" == "false" ]]; then
    log "generated artifacts are clean"
elif [[ "$drift_exit" -eq 1 && "$drift_detected" == "true" ]]; then
    log "generated artifact drift detected:"
    jq -r '.reasons[] | "  - \(.)"' "$drift_json" | monitor_log_stream
    fail_closed "pinned base already contains generated drift; repair it independently before checksum publication"
else
    fail_closed "drift checker exit/result mismatch (exit $drift_exit, drift=$drift_detected)"
fi

CURRENT_CHECKSUMS_SHA256="$(sha256_file checksums.yaml)" \
    || fail_closed "canonical checksums.yaml is missing, unsafe, or unreadable"
verify_json="$(mktemp "$STATE_DIR/verify-$RUN_TS.XXXXXX.json")" \
    || fail_closed "could not allocate verification evidence file"
DOWNLOAD_EVIDENCE_RUN_DIR="$(mktemp -d "$STATE_DIR/downloads-$RUN_TS.XXXXXX")" \
    || fail_closed "could not allocate private first-observation download evidence"
set +e
run_clean_bounded 300 env TMPDIR="$DOWNLOAD_EVIDENCE_RUN_DIR" \
    bash scripts/lib/security.sh --verify --json --retain-temp-files >"$verify_json" 2>&"$MONITOR_LOG_FD"
verify_exit=$?
set -e
# Keep locators and the producer exit even when the report contract fails.
# Raw errors and HTTP evidence remain local; only the run locator is added to public alerts.
log "verification evidence: run=$RUN_TS exit=$verify_exit report=$verify_json downloads=$DOWNLOAD_EVIDENCE_RUN_DIR"
validate_verification_report "$verify_json" "$CURRENT_CHECKSUMS_SHA256" \
    || fail_closed "checksum verification returned data outside its strict bound report contract"
VERIFICATION_REPORT_SHA256="$(sha256_file "$verify_json")" \
    || fail_closed "could not bind the validated verification report bytes"
log "verification binding: policy_sha256=$CURRENT_CHECKSUMS_SHA256 report_sha256=$VERIFICATION_REPORT_SHA256"

mismatches="$(jq '.mismatches | length' "$verify_json")"
errors="$(jq '.errors | length' "$verify_json")"
skipped="$(jq '.skipped | length' "$verify_json")"

if [[ "$errors" -gt 0 || "$skipped" -gt 0 ]]; then
    jq -r '.errors[]?  | "  error: \(.name) -> \(.error)"'    "$verify_json" | monitor_log_stream
    jq -r '.skipped[]? | "  skipped: \(.name) -> \(.reason)"' "$verify_json" | monitor_log_stream
    fail_closed "verification returned $errors error(s) / $skipped skip(s); refusing to auto-update checksums.yaml"
fi
if [[ "$mismatches" -eq 0 && "$verify_exit" -ne 0 ]]; then
    fail_closed "verification reported no mismatch but exited $verify_exit"
fi
if [[ "$mismatches" -gt 0 && "$verify_exit" -ne 1 ]]; then
    fail_closed "verification reported $mismatches mismatch(es) but exited $verify_exit"
fi
validate_download_evidence "$verify_json" "$DOWNLOAD_EVIDENCE_RUN_DIR" \
    || fail_closed "verification did not retain complete private first-observation evidence"
log "download evidence: $DOWNLOAD_EVIDENCE_INDEX_FILE (sha256=$DOWNLOAD_EVIDENCE_INDEX_SHA256)"
[[ "$(sha256_file checksums.yaml)" == "$CURRENT_CHECKSUMS_SHA256" ]] \
    || fail_closed "checksums.yaml changed during first observation"
[[ "$(git rev-parse HEAD 2>/dev/null || true)" == "$BASE_HEAD" ]] \
    || fail_closed "HEAD changed during observation"
require_clean_tree || fail_closed "repository changed during observation"
advance_state CLEAN_BASE OBSERVED

prepare_checksum_candidate "$verify_json"

publication_required=false
if [[ -n "$applicable_changed" ]]; then
    require_selected_external_authorization
    command cp -- "$validated_candidate" checksums.yaml \
        || fail_closed "could not place the validated checksum candidate"
    [[ "$(sha256_file checksums.yaml)" == "$CANDIDATE_SHA256" ]] \
        || fail_closed "placed checksums.yaml does not match the validated candidate"
    ( cd packages/manifest \
        && run_bun_clean_bounded 120 run generate >&"$MONITOR_LOG_FD" 2>&1 ) \
        || fail_closed "generation from the validated checksum candidate failed"
    assert_closed_publication_worktree \
        || fail_closed "generation escaped the closed publication path set"

    post_drift_json="$(mktemp "$STATE_DIR/post-generate-drift-$RUN_TS.XXXXXX.json")" \
        || fail_closed "could not allocate post-generation evidence file"
    set +e
    run_clean_bounded 120 bash scripts/check-manifest-drift.sh --json \
        >"$post_drift_json" 2>&"$MONITOR_LOG_FD"
    post_drift_exit=$?
    set -e
    validate_drift_report "$post_drift_json" \
        || fail_closed "post-generation drift report violated its strict JSON contract"
    [[ "$post_drift_exit" -eq 0 ]] \
        && [[ "$(jq -r '.drift_detected' "$post_drift_json")" == "false" ]] \
        || fail_closed "validated candidate did not produce a clean generated-artifact contract"
    [[ "$(sha256_file checksums.yaml)" == "$CANDIDATE_SHA256" ]] \
        || fail_closed "checksums.yaml changed during generation"
    publication_required=true
fi
advance_state AUTHORIZED GENERATED

for publication_path in "${PUBLICATION_PATHS[@]}"; do
    [[ -f "$publication_path" && ! -L "$publication_path" ]] \
        && [[ "$(stat -c '%h' -- "$publication_path" 2>/dev/null || true)" == "1" ]] \
        || fail_closed "closed publication member is missing or unsafe: $publication_path"
done

if [[ "$publication_required" == "true" ]]; then
    require_selected_external_authorization
    assert_closed_publication_worktree \
        || fail_closed "worktree contains bytes outside the closed publication set"
    git add -- "${PUBLICATION_PATHS[@]}" \
        || fail_closed "could not stage the closed publication set"
    staged_paths="$(git -c core.quotePath=true diff --cached --name-only -- 2>&"$MONITOR_LOG_FD")" \
        || fail_closed "could not enumerate the staged publication"
    while IFS= read -r staged_path; do
        [[ -n "$staged_path" ]] || continue
        [[ -n "${PUBLICATION_PATH_SET[$staged_path]+present}" ]] \
            || fail_closed "unexpected staged publication path: $staged_path"
    done <<< "$staged_paths"
    staged_deletions="$(git -c core.quotePath=true diff --cached --name-only --diff-filter=D -- 2>&"$MONITOR_LOG_FD")" \
        || fail_closed "could not enumerate staged deletions"
    [[ -z "$staged_deletions" ]] \
        || fail_closed "refusing to stage a file deletion"
    git diff --quiet --exit-code -- \
        || fail_closed "worktree bytes changed after staging"
    git diff --cached --check \
        || fail_closed "staged publication failed whitespace/error checks"
    git diff --cached --quiet --exit-code -- \
        && fail_closed "validated mismatch produced no staged publication"
else
    require_clean_tree || fail_closed "no-op run acquired repository mutations"
fi
advance_state GENERATED STAGED

read_remote_heads || fail_closed "could not re-read remote refs before commit"
[[ "$REMOTE_MAIN_HEAD" == "$BASE_HEAD" && "$REMOTE_MASTER_HEAD" == "$BASE_HEAD" ]] \
    || fail_closed "remote base moved after observation; refusing to commit stale evidence"

committed=false
PUBLISH_HEAD="$BASE_HEAD"
if [[ "$publication_required" == "true" ]]; then
    # The remote-base probe above may block. Approval and retained evidence
    # live outside Git, so a clean index cannot prove they survived that wait.
    require_selected_external_authorization
    # The author name is public history: no host name in it.
    git -c "user.name=acfs-checksum-monitor" \
        -c user.email=jeff141421@gmail.com \
        -c core.hooksPath=/dev/null \
        -c commit.gpgsign=false \
        commit --quiet \
        -m "chore(security): publish validated checksums for ${applicable_changed}" \
        -m "Observed checksums policy: ${CURRENT_CHECKSUMS_SHA256}" \
        -m "Verification evidence: ${VERIFICATION_REPORT_SHA256}" \
        -m "Download evidence index: ${DOWNLOAD_EVIDENCE_INDEX_SHA256}" \
        -m "Validated candidate: ${CANDIDATE_SHA256}" \
        -m "Changed tools: ${changed_tools}" \
        -m "Trusted: ${trusted_changed:-none}" \
        -m "External: ${external_changed:-none}" \
        -m "Deferred (awaiting authorization): ${deferred_changed:-none}" \
        -m "Authorization scope: ${authorization_mode}; selected external: ${authorized_external_changed:-none}" \
        -m "Authorization: ${authorization_digest:-not-required} (${authorization_status})" \
        || fail_closed "closed checksum publication commit failed"
    PUBLISH_HEAD="$(git rev-parse HEAD 2>/dev/null || true)"
    [[ "$PUBLISH_HEAD" =~ ^[0-9a-f]{40}$ ]] \
        && [[ "$(git rev-parse "${PUBLISH_HEAD}^" 2>/dev/null || true)" == "$BASE_HEAD" ]] \
        || fail_closed "publication commit is not the direct child of the observed base"
    committed_paths="$(git -c core.quotePath=true diff-tree --no-commit-id --name-only -r "$PUBLISH_HEAD" 2>&"$MONITOR_LOG_FD")" \
        || fail_closed "could not enumerate the publication commit"
    while IFS= read -r committed_path; do
        [[ -n "$committed_path" ]] || continue
        [[ -n "${PUBLICATION_PATH_SET[$committed_path]+present}" ]] \
            || fail_closed "publication commit contains unexpected path: $committed_path"
    done <<< "$committed_paths"
    require_clean_tree || fail_closed "repository is not clean after publication commit"
    committed=true
fi
advance_state STAGED COMMITTED

read_remote_heads || fail_closed "could not read remote refs immediately before publication"
[[ "$REMOTE_MAIN_HEAD" == "$BASE_HEAD" && "$REMOTE_MASTER_HEAD" == "$BASE_HEAD" ]] \
    || fail_closed "remote refs moved before atomic publication"

push_result="not-required"
if [[ "$publication_required" == "true" ]]; then
    publication_journal="$(mktemp "$STATE_DIR/publication-$RUN_TS.XXXXXX.journal")" \
        || fail_closed "could not allocate publication journal"
    printf 'prepared\t%s\t%s\n' "$BASE_HEAD" "$PUBLISH_HEAD" >> "$publication_journal" \
        || fail_closed "could not record prepared publication"
    # This is the last local authority check before the remote side effect.
    # In particular, do not defer revocation/evidence checks until readback:
    # failing after a successful push cannot undo an unauthorized publication.
    require_selected_external_authorization
    set +e
    run_bounded 90 git -c core.hooksPath=/dev/null push --atomic --quiet origin \
        "$PUBLISH_HEAD:refs/heads/main" \
        "$PUBLISH_HEAD:refs/heads/master" >&"$MONITOR_LOG_FD" 2>&1
    push_exit=$?
    set -e
    printf 'push-exit\t%s\n' "$push_exit" >> "$publication_journal" \
        || fail_closed "could not journal the publication result"
    read_remote_heads \
        || fail_closed "atomic push result is ambiguous because remote refs cannot be read"
    if [[ "$REMOTE_MAIN_HEAD" == "$PUBLISH_HEAD" && "$REMOTE_MASTER_HEAD" == "$PUBLISH_HEAD" ]]; then
        if [[ "$push_exit" -eq 0 ]]; then
            push_result="accepted"
        else
            push_result="reconciled-after-ambiguous-exit"
        fi
    elif [[ "$REMOTE_MAIN_HEAD" == "$BASE_HEAD" && "$REMOTE_MASTER_HEAD" == "$BASE_HEAD" ]]; then
        fail_closed "atomic publication was not accepted (push exit $push_exit)"
    else
        fail_closed "remote refs are mixed or unexpected after atomic publication attempt"
    fi
    printf 'remote-observed\t%s\t%s\t%s\n' \
        "$REMOTE_MAIN_HEAD" "$REMOTE_MASTER_HEAD" "$push_result" \
        >> "$publication_journal" \
        || fail_closed "could not journal reconciled remote publication"
fi
advance_state COMMITTED ATOMIC_PUBLISHED

# A second independent remote read is the acceptance boundary. Local source,
# a successful git exit, or one remote-tracking ref is not publication proof.
read_remote_heads || fail_closed "remote verification after publication failed"
[[ "$REMOTE_MAIN_HEAD" == "$PUBLISH_HEAD" && "$REMOTE_MASTER_HEAD" == "$PUBLISH_HEAD" ]] \
    || fail_closed "remote verification does not match the intended publication commit"
[[ "$(git rev-parse HEAD 2>/dev/null || true)" == "$PUBLISH_HEAD" ]] \
    || fail_closed "local HEAD changed before remote acceptance"
require_clean_tree || fail_closed "repository is not clean at remote acceptance"
# Retained observations remain part of acceptance even when only trusted
# changes published, or the run had no candidate. Do not gate their recheck
# on whether an external authorization happens to need consumption.
require_selected_external_authorization
advance_state ATOMIC_PUBLISHED REMOTE_VERIFIED

if [[ "$authorization_consumed" == "true" ]]; then
    require_selected_external_authorization
    if [[ "$authorization_mode" == subset ]]; then
        printf 'used-subset:%s:%s:%s\n' "$authorization_digest" "$authorized_external_changed" "$PUBLISH_HEAD" \
            > "$AUTHORIZATION_FILE" \
            || fail_closed "remote publication succeeded but subset authorization consumption could not be recorded"
    else
        printf 'used:%s:%s\n' "$authorization_digest" "$PUBLISH_HEAD" \
            > "$AUTHORIZATION_FILE" \
            || fail_closed "remote publication succeeded but authorization consumption could not be recorded"
    fi
fi

if [[ "$external_deferred" == "true" ]]; then
    result="deferred"
else
    result="ok"
fi
record_accepted_monitor_outcome "$result" \
    || fail_closed "could not record the accepted monitor outcome"

log "summary: result=$result state=$STATE base=$BASE_HEAD published=$PUBLISH_HEAD push=$push_result mismatches=$mismatches errors=$errors skipped=$skipped trusted=${trusted_changed:-none} external=${external_changed:-none} deferred=${deferred_changed:-none} selected=${applicable_changed:-none} committed=$committed"
}

# Source the real helpers and state machine without taking the lock in tests.
if [[ "${ACFS_MONITOR_LIBRARY_ONLY:-0}" != "1" ]]; then
    checksum_monitor_main
fi
