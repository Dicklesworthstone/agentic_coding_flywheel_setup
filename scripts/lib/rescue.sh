#!/usr/bin/env bash
# ============================================================
# ACFS Rescue Advisor - read-only first-run recovery guidance
# Usage: acfs rescue [--json]
# ============================================================

set -euo pipefail

RESCUE_JSON=false
RESCUE_STATE_FILE="${ACFS_RESCUE_STATE_FILE:-${ACFS_STATE_FILE:-}}"
RESCUE_SUMMARY_FILE="${ACFS_RESCUE_SUMMARY_FILE:-}"
RESCUE_DOCTOR_FILE="${ACFS_RESCUE_DOCTOR_FILE:-}"
RESCUE_SUPPORT_DIR="${ACFS_RESCUE_SUPPORT_DIR:-}"
RESCUE_ACFS_HOME="${ACFS_RESCUE_ACFS_HOME:-${ACFS_HOME:-}}"
RESCUE_NOW_EPOCH="${ACFS_RESCUE_NOW_EPOCH:-}"
RESCUE_STALE_SECONDS="${ACFS_RESCUE_STALE_SECONDS:-3600}"

RESCUE_STATUS="warn"
RESCUE_SEVERITY="needs_evidence"
RESCUE_REASON="ACFS state has not been evaluated yet."
RESCUE_NEXT_COMMAND="acfs status --json"
RESCUE_STATE_STATUS="missing"
RESCUE_STATE_PATH=""
RESCUE_SUMMARY_STATUS="missing"
RESCUE_SUMMARY_PATH=""
RESCUE_DOCTOR_STATUS="missing"
RESCUE_DOCTOR_PATH=""
RESCUE_INSTALL_STATUS="unknown"
RESCUE_SUPPORT_AVAILABLE=false
RESCUE_SUPPORT_LATEST=""
RESCUE_SUPPORT_REPORT=""
RESCUE_EXIT_CODE=1
RESCUE_SUPPORTED_STATE_SCHEMA_VERSION=3
RESCUE_CHECKPOINT_SCHEMA_VERSION=""
RESCUE_CHECKPOINT_SUPPORTED_SCHEMA_VERSION="$RESCUE_SUPPORTED_STATE_SCHEMA_VERSION"
RESCUE_CHECKPOINT_COMPLETED_COUNT=""
RESCUE_CHECKPOINT_LAST_COMPLETED_PHASE=""
RESCUE_CHECKPOINT_NEXT_PHASE=""
RESCUE_CHECKPOINT_CURRENT_PHASE=""
RESCUE_CHECKPOINT_FAILED_PHASE=""
RESCUE_CHECKPOINT_AGE_SECONDS=""
RESCUE_EVIDENCE=()
RESCUE_NON_ACTIONS=(
    "Leave state files in place."
    "Keep logs and support bundles intact."
    "Use only the next command listed here before changing installer flags."
)

# Keep transcript analysis out of the checkpoint collectors: an explicit log
# must not trigger home-directory discovery, subprocess probes, or file writes.
rescue_explain_log() (
    local python_bin="" source_dir="${BASH_SOURCE[0]%/*}"
    [[ "$source_dir" != "${BASH_SOURCE[0]}" ]] || source_dir=.
    python_bin="$(rescue_system_binary_path python3 2>/dev/null || true)"
    if [[ -z "$python_bin" || ! -f "$source_dir/errors.sh" || -L "$source_dir/errors.sh" ]]; then
        printf '%s\n' '{"schema":"acfs.installer-transcript.v1","status":"error","error_code":"analyzer_unavailable","raw_log_included":false}'
        return 2
    fi
    # Reuse the installer's matching vocabulary, NOT its mutating fix commands.
    unset ACFS_ERRORS_LOADED
    # shellcheck source=errors.sh
    source "$source_dir/errors.sh"
    "$python_bin" -I - "$source_dir" "${#ERROR_PATTERNS[@]}" "${!ERROR_PATTERNS[@]}" "$@" <<'ACFS_TRANSCRIPT_PY'
import argparse
import json
import os
from pathlib import Path
import re
import stat
import sys

SCHEMA = "acfs.installer-transcript.v1"
library = Path(sys.argv[1]).absolute()
pattern_count = int(sys.argv[2])
patterns = sorted(sys.argv[3:3 + pattern_count], key=lambda p: (-len(p), p))
arguments = sys.argv[3 + pattern_count:]


class InputError(Exception):
    pass


class Parser(argparse.ArgumentParser):
    def error(self, message):
        # argparse normally echoes unknown arguments (possibly secrets/paths).
        raise InputError("invalid_arguments")


def read_regular(value, maximum, tail=False):
    path = Path(os.path.abspath(value))
    if ".." in Path(value).parts or any(ord(c) < 32 or ord(c) == 127 for c in str(path)):
        raise InputError("unsafe_input")
    fd = os.open(path.anchor, os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parts[1:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
        handle = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    finally:
        os.close(fd)
    with os.fdopen(handle, "rb") as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise InputError("unsafe_input")
        if not tail and before.st_size > maximum:
            raise InputError("input_too_large")
        offset = max(0, before.st_size - maximum)
        stream.seek(offset)
        data = stream.read(maximum)
        after = os.fstat(stream.fileno())
        if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_size, after.st_mtime_ns, after.st_ctime_ns):
            raise InputError("input_changed")
    if offset:
        # Never diagnose a fragment whose prefix was outside the bounded tail.
        data = data.partition(b"\n")[2]
    return data, before.st_size, bool(offset)


def module_ids():
    # Read the generated data as inert text. Never source it or execute a log.
    try:
        raw, _, _ = read_regular(str(library.parent / "generated/manifest_index.sh"), 1024 * 1024)
        block = re.search(rb"(?m)^ACFS_MODULES_IN_ORDER=\(\n(.*?)^\)", raw, re.S)
        if block:
            return {m.decode("ascii") for m in re.findall(rb'^  "([a-z][a-z0-9_.]*)"$', block[1], re.M)}
    except (InputError, OSError, ValueError):
        pass
    return set()


# Confidence describes a match in a transcript, never a verified host diagnosis.
CAUSES = {
    "checksum": ("high", "Downloaded content did not match trusted checksums or signatures.", "Stop and review the trusted source and checksum pin. Do not bypass verification.", ["acfs", "doctor", "--json"]),
    "host_key": ("high", "SSH could not verify the host identity.", "Verify the host key independently. Do not remove known-host entries just to suppress this error.", ["acfs", "status", "--json"]),
    "disk": ("high", "The log reports exhausted disk space or a quota.", "Inspect storage and preserve logs and databases. Choose any cleanup separately.", ["df", "-h"]),
    "memory": ("high", "The log reports memory allocation failure.", "Inspect memory pressure before retrying; do not automatically kill processes.", ["free", "-h"]),
    "package_lock": ("high", "Another package manager may own the APT or dpkg lock.", "Wait for the owner to finish. Never remove lock files or kill live package-manager processes.", ["ps", "-eo", "pid,comm"]),
    "package_state": ("medium", "Package configuration or dependency resolution failed.", "Inspect package state and the supported Ubuntu release before choosing a repair.", ["dpkg", "--audit"]),
    "network": ("medium", "A download, DNS lookup, or network connection failed.", "Check connectivity, provider availability, and firewall policy before retrying.", ["acfs", "status", "--json"]),
    "tls": ("medium", "TLS or repository-key validation could not complete.", "Check the clock and trusted repository configuration. Do not disable TLS or signature checks.", ["date", "-u"]),
    "permission": ("medium", "The log reports an access or permission failure.", "Check the intended account and ownership. Do not apply recursive ownership changes or retry every command as root.", ["id"]),
    "rate_limit": ("medium", "An upstream service reports rate limiting.", "Wait for its documented reset and review authentication separately; do not retry in a tight loop.", ["acfs", "status", "--json"]),
    "authentication": ("medium", "A service reports missing or rejected authentication.", "Use that service's explicit login or token-rotation flow. Never paste credentials into logs or support reports.", ["acfs", "services", "status"]),
    "interrupted_upgrade": ("medium", "The transcript reports an interrupted upgrade or a required reboot.", "Inspect the saved upgrade checkpoint and package state before any reboot or resume.", ["acfs", "rescue", "--json"]),
    "process_killed": ("low", "A process was killed; this alone does not prove an out-of-memory event.", "Inspect memory and system evidence before choosing a retry.", ["free", "-h"]),
    "tool_failure": ("low", "A tool failed or a required dependency was unavailable.", "Inspect the saved installer summary for the exact failed module and original selection.", ["acfs", "rescue", "--json"]),
}


def category(pattern):
    p = pattern.lower()
    if any(s in p for s in ("checksum", "hash sum", "signature verification")): return "checksum"
    if "host key" in p: return "host_key"
    if "space left" in p or "quota" in p: return "disk"
    if "allocate memory" in p: return "memory"
    if "get lock" in p: return "package_lock"
    if any(s in p for s in ("dpkg", "dependencies", "locate package")): return "package_state"
    if any(s in p for s in ("ssl", "gpg", "pubkey")): return "tls"
    if "permission" in p or "permitted" in p: return "permission"
    if "rate limit" in p or "too many requests" in p: return "rate_limit"
    if p == "killed": return "process_killed"
    if any(s in p for s in ("curl:", "connection", "timed out")): return "network"
    return "tool_failure"


def explain(args):
    raw, total, truncated = read_regular(args.log_file, args.max_bytes, tail=True)
    # Drop ANSI/OSC payloads, including hyperlink URLs, before matching.
    text = raw.decode("utf-8", errors="replace")
    text = re.sub(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)", "", text)
    text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
    text = re.sub(r"[\x00-\x08\x0b-\x1f\x7f]", "", text)
    lines = text.splitlines()
    # Concatenated runs must not attribute an older run's failure to this one.
    start = max((i for i, line in enumerate(lines) if line.strip() == "=== ACFS Install Log ==="), default=0)
    known_modules = module_ids()
    phase_names = {"User Normalization": "user_setup", "Filesystem Setup": "filesystem",
        "Shell Setup": "shell_setup", "CLI Tools": "cli_tools", "Language Runtimes": "languages",
        "Coding Agents": "agents", "Cloud & Database Tools": "cloud_db", "Agent Flywheel Stack": "stack",
        "Final Wiring": "finalize", "Ubuntu Auto-Upgrade": "ubuntu_upgrade"}
    phase = module = None
    findings = {}
    long_lines = 0
    completion_seen = False
    for index, line in enumerate(lines[start:], start + 1):
        if len(line) > 65536:
            long_lines += 1
            continue
        stripped = line.strip()
        if stripped.startswith("Phase: "):
            value = stripped[7:].split(" ", 1)[0]
            phase = value if value in set(phase_names.values()) | {"bootstrap", "preflight"} else None
        match = re.fullmatch(r"Phase [0-9]+/[0-9]+: (.+)", stripped)
        if match:
            phase = phase_names.get(match[1])
        match = re.search(r"(?:Generated module failed:|Module:) ([a-z][a-z0-9_.]*)\b", line)
        if match:
            module = match[1] if match[1] in known_modules else None
        lowered = line.lower()
        cause = next((category(p) for p in patterns if p.lower() in lowered), None)
        if re.search(r"(?:\b(?:401|403)\b.*(?:unauthorized|forbidden)|authentication failed|invalid api key|token (?:has )?expired)", lowered):
            cause = "authentication"
        if "dpkg was interrupted" in lowered:
            cause = "package_state"
        if any(p in lowered for p in ("upgrade interrupted", "reboot required", "system restart required")):
            cause = "interrupted_upgrade"
        if cause is None and ("generated module failed:" in lowered or stripped == "INSTALLATION FAILED" or "ACFS Installation Finished With Failures" in line):
            cause = "tool_failure"
        completion_seen |= "ACFS Installation Complete!" in line
        if cause:
            entry = findings.setdefault(cause, {"pattern_id": cause, "occurrences": 0})
            entry.update(occurrences=entry["occurrences"] + 1, last_line=index)
    ranked = sorted(findings.values(), key=lambda f: (f["pattern_id"] not in ("checksum", "host_key"),
                    f["pattern_id"] in ("tool_failure", "process_killed"), -f["last_line"], f["pattern_id"]))
    for finding in ranked:
        confidence, reason, action, command = CAUSES[finding["pattern_id"]]
        finding.update(confidence=confidence, explanation=reason, remediation=action, diagnostic_argv=command)
    return {"schema": SCHEMA, "status": "needs_attention" if ranked else "inconclusive",
        "installation_verified": False, "raw_log_included": False, "paths_included": False,
        "redaction_policy": "omit_all_raw_input_except_allowlisted_phase_and_module_ids",
        "source": {"bytes_analyzed": len(raw), "total_bytes": total, "tail_truncated": truncated,
                   "line_numbers": "analyzed_tail" if truncated else "original_file",
                   "analyzed_from_line": start + 1, "oversized_lines_omitted": long_lines},
        "phase": phase, "module": module, "completion_marker_seen": completion_seen,
        "primary_cause": ranked[0]["pattern_id"] if ranked else None, "findings": ranked,
        "retry": {"command": None, "inspection_argv": ["acfs", "rescue", "--json"],
                  "reason": "Logs do not establish the original ref, flags, live package locks, or checkpoint validity. Inspect saved state before resuming; never execute a command copied from a transcript."},
        "support_argv": ["acfs", "support-bundle"], "commands_executed": False,
        "note": "Pattern matches are advisory, not proof of the root cause. No match or a success footer is not evidence of a healthy installation."}


def main():
    parser = Parser(prog="acfs rescue --log-file", allow_abbrev=False,
        description="Explain a bounded local installer transcript without commands, uploads, or raw excerpts.")
    parser.add_argument("--log-file", required=True)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--max-bytes", type=int, default=1048576)
    args = parser.parse_args(arguments)
    if not 1024 <= args.max_bytes <= 8 * 1024 * 1024:
        raise InputError("invalid_arguments")
    report = explain(args)
    if args.json:
        print(json.dumps(report, sort_keys=True, indent=2))
    else:
        print("ACFS Installer Transcript\nStatus: " + report["status"])
        print("Recorded phase: " + (report["phase"] or "unknown"))
        print("Recorded module: " + (report["module"] or "unknown"))
        for f in report["findings"]:
            print("\n" + f["pattern_id"] + " (" + f["confidence"] + " confidence): " + f["explanation"])
            print(f["remediation"] + "\nInspect: " + " ".join(f["diagnostic_argv"]))
        if report["source"]["tail_truncated"] or report["source"]["oversized_lines_omitted"]:
            print("\nOnly a bounded portion of the transcript was analyzed; earlier evidence may be missing.")
        print("\n" + report["note"])
        print("Before retrying: acfs rescue --json\nSupport: acfs support-bundle")
    return 1 if report["findings"] else 0


try:
    sys.exit(main())
except (InputError, OSError, ValueError):
    # Neither exception text nor an offending input path belongs in evidence.
    exc = sys.exc_info()[1]
    print(json.dumps({"schema": SCHEMA, "status": "error", "raw_log_included": False,
                      "commands_executed": False,
                      "error_code": str(exc) if isinstance(exc, InputError) else "input_unavailable"}))
    sys.exit(2)
ACFS_TRANSCRIPT_PY
)

rescue_usage() {
    cat <<'EOF'
Usage: acfs rescue [options]

Read-only recovery advisor for first-run ACFS installer problems.

Options:
  --json                     Output machine-readable JSON
  --log-file PATH             Explain a local installer transcript instead of probing checkpoints
  --max-bytes N               Transcript tail limit, 1024..8388608 (default: 1048576)
  --state-file PATH          Read installer state from PATH
  --summary-file PATH        Read install_summary JSON from PATH
  --doctor-file PATH         Read acfs doctor --json output from PATH
  --support-dir PATH         Look for support bundles under PATH
  --acfs-home PATH           Resolve default state/log/support paths from PATH
  --now-epoch SECONDS        Override current time for stale checkpoint checks
  --stale-seconds SECONDS    Running checkpoint age before warning (default: 3600)
  -h, --help                 Show this help
EOF
}

rescue_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..|*[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    for candidate in \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

rescue_jq() {
    rescue_system_binary_path jq
}

rescue_json_escape() {
    local jq_bin=""
    jq_bin="$(rescue_jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        "$jq_bin" -Rn --arg value "${1:-}" '$value'
    else
        printf '"%s"' "${1//\"/\\\"}"
    fi
}

rescue_array_json() {
    local jq_bin=""
    jq_bin="$(rescue_jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        "$jq_bin" -n '$ARGS.positional' --args "$@"
    else
        printf '[]'
    fi
}

rescue_bool_json() {
    if [[ "${1:-false}" == "true" ]]; then
        printf 'true'
    else
        printf 'false'
    fi
}

rescue_add_evidence() {
    RESCUE_EVIDENCE+=("$1")
}

rescue_resolve_acfs_home() {
    local home_candidate=""

    if [[ -n "$RESCUE_ACFS_HOME" ]]; then
        printf '%s\n' "${RESCUE_ACFS_HOME%/}"
        return 0
    fi

    if [[ -n "${TARGET_HOME:-}" && "${TARGET_HOME:-}" == /* && "${TARGET_HOME:-}" != "/" ]]; then
        printf '%s/.acfs\n' "${TARGET_HOME%/}"
        return 0
    fi

    home_candidate="${HOME:-}"
    if [[ -n "$home_candidate" && "$home_candidate" == /* && "$home_candidate" != "/" ]]; then
        printf '%s/.acfs\n' "${home_candidate%/}"
        return 0
    fi

    printf '%s\n' "$PWD/.acfs"
}

rescue_resolve_defaults() {
    local acfs_home=""
    acfs_home="$(rescue_resolve_acfs_home)"
    RESCUE_ACFS_HOME="$acfs_home"

    if [[ -z "$RESCUE_STATE_FILE" ]]; then
        RESCUE_STATE_FILE="$RESCUE_ACFS_HOME/state.json"
    fi
    RESCUE_STATE_PATH="$RESCUE_STATE_FILE"

    if [[ -z "$RESCUE_SUMMARY_FILE" ]]; then
        RESCUE_SUMMARY_FILE="$(rescue_latest_summary_file "$RESCUE_ACFS_HOME/logs" 2>/dev/null || true)"
    fi
    RESCUE_SUMMARY_PATH="$RESCUE_SUMMARY_FILE"

    if [[ -z "$RESCUE_SUPPORT_DIR" ]]; then
        RESCUE_SUPPORT_DIR="$RESCUE_ACFS_HOME/support"
    fi
}

rescue_latest_summary_file() {
    local logs_dir="${1:-}"
    local latest=""

    [[ -n "$logs_dir" && -d "$logs_dir" ]] || return 1
    latest="$(find "$logs_dir" -maxdepth 1 -type f -name 'install_summary_*.json' 2>/dev/null | sort | tail -n 1)"
    [[ -n "$latest" ]] || return 1
    printf '%s\n' "$latest"
}

rescue_latest_support_path() {
    local support_dir="${1:-}"
    local latest=""

    [[ -n "$support_dir" && -d "$support_dir" ]] || return 1
    latest="$(find "$support_dir" -maxdepth 1 \( -type d -o -type f \) \( -name 'acfs-support-*' -o -name 'support-*' -o -name '*.tar.gz' \) 2>/dev/null | sort | tail -n 1)"
    [[ -n "$latest" ]] || return 1
    printf '%s\n' "$latest"
}

rescue_support_report_for_path() {
    local bundle_path="${1:-}"
    local bundle_dir=""

    [[ -n "$bundle_path" ]] || return 1
    if [[ -d "$bundle_path" ]]; then
        bundle_dir="$bundle_path"
    elif [[ "$bundle_path" == *.tar.gz ]]; then
        bundle_dir="${bundle_path%.tar.gz}"
    fi

    [[ -n "$bundle_dir" && -f "$bundle_dir/support-report.md" ]] || return 1
    printf '%s\n' "$bundle_dir/support-report.md"
}

rescue_probe_support() {
    RESCUE_SUPPORT_LATEST="$(rescue_latest_support_path "$RESCUE_SUPPORT_DIR" 2>/dev/null || true)"
    if [[ -n "$RESCUE_SUPPORT_LATEST" ]]; then
        RESCUE_SUPPORT_AVAILABLE=true
        RESCUE_SUPPORT_REPORT="$(rescue_support_report_for_path "$RESCUE_SUPPORT_LATEST" 2>/dev/null || true)"
        rescue_add_evidence "Latest support bundle found: $RESCUE_SUPPORT_LATEST"
        if [[ -n "$RESCUE_SUPPORT_REPORT" ]]; then
            rescue_add_evidence "Support report available: $RESCUE_SUPPORT_REPORT"
        fi
    else
        RESCUE_SUPPORT_AVAILABLE=false
        rescue_add_evidence "No prior support bundle found under: $RESCUE_SUPPORT_DIR"
    fi
}

rescue_json_file_valid() {
    local path="${1:-}"
    local jq_bin=""

    [[ -n "$path" && -f "$path" && -r "$path" ]] || return 1
    jq_bin="$(rescue_jq 2>/dev/null || true)"
    [[ -n "$jq_bin" ]] || return 1
    "$jq_bin" -e . "$path" >/dev/null 2>&1
}

rescue_json_get() {
    local path="$1"
    local query="$2"
    local jq_bin=""

    jq_bin="$(rescue_jq 2>/dev/null || true)"
    [[ -n "$jq_bin" ]] || return 0
    "$jq_bin" -r "$query" "$path" 2>/dev/null || true
}

rescue_timestamp_epoch() {
    local value="${1:-}"
    local date_bin=""

    [[ -n "$value" && "$value" != "null" ]] || return 1
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$value"
        return 0
    fi

    date_bin="$(rescue_system_binary_path date 2>/dev/null || true)"
    [[ -n "$date_bin" ]] || return 1
    "$date_bin" -u -d "$value" +%s 2>/dev/null
}

rescue_file_mtime_epoch() {
    local path="${1:-}"
    local stat_bin=""

    [[ -n "$path" && -e "$path" ]] || return 1
    stat_bin="$(rescue_system_binary_path stat 2>/dev/null || true)"
    [[ -n "$stat_bin" ]] || return 1
    "$stat_bin" -c %Y "$path" 2>/dev/null
}

rescue_now_epoch() {
    local date_bin=""

    if [[ -n "$RESCUE_NOW_EPOCH" ]]; then
        printf '%s\n' "$RESCUE_NOW_EPOCH"
        return 0
    fi

    date_bin="$(rescue_system_binary_path date 2>/dev/null || true)"
    [[ -n "$date_bin" ]] || return 1
    "$date_bin" -u +%s
}

rescue_is_safe_next_command() {
    local command_value="${1:-}"

    [[ -n "$command_value" ]] || return 1
    case "$command_value" in
        *"rm -rf"*|*"git reset"*|*"git clean"*|*"mkfs"*|*"shred "*|*"dd if="*|*" > /var/lib/acfs/state.json"*|*" > ~/.acfs/state.json"*)
            return 1
            ;;
    esac

    return 0
}

rescue_set_decision() {
    RESCUE_STATUS="$1"
    RESCUE_SEVERITY="$2"
    RESCUE_REASON="$3"
    RESCUE_NEXT_COMMAND="$4"

    case "$RESCUE_STATUS" in
        pass) RESCUE_EXIT_CODE=0 ;;
        warn) RESCUE_EXIT_CODE=1 ;;
        fail) RESCUE_EXIT_CODE=2 ;;
        *) RESCUE_EXIT_CODE=1 ;;
    esac
}

rescue_next_phase_after() {
    local phase_id="${1:-}"

    case "$phase_id" in
        "") printf 'user_setup\n' ;;
        user_setup) printf 'filesystem\n' ;;
        filesystem) printf 'shell_setup\n' ;;
        shell_setup) printf 'cli_tools\n' ;;
        cli_tools) printf 'languages\n' ;;
        languages) printf 'agents\n' ;;
        agents) printf 'cloud_db\n' ;;
        cloud_db) printf 'stack\n' ;;
        stack) printf 'finalize\n' ;;
        finalize) printf '\n' ;;
        *) printf '\n' ;;
    esac
}

rescue_analyze_state() {
    local state_file="$RESCUE_STATE_FILE"
    local schema_version=""
    local failed_phase=""
    local failed_step=""
    local failed_error=""
    local resume_hint=""
    local current_phase=""
    local current_step=""
    local completed_finalize=""
    local completed_count=""
    local last_completed_phase=""
    local next_phase=""
    local last_updated=""
    local updated_epoch=""
    local now_epoch=""
    local age_seconds=""

    if [[ ! -e "$state_file" ]]; then
        RESCUE_STATE_STATUS="missing"
        rescue_add_evidence "State file not found: $state_file"
        return 0
    fi

    if [[ ! -r "$state_file" ]]; then
        RESCUE_STATE_STATUS="unreadable"
        rescue_add_evidence "State file exists but is not readable: $state_file"
        rescue_set_decision "fail" "blocked" "The ACFS state file cannot be read, so the safe next step is to capture diagnostics." "acfs support-bundle"
        return 0
    fi

    if ! rescue_json_file_valid "$state_file"; then
        RESCUE_STATE_STATUS="malformed"
        rescue_add_evidence "State file is not valid JSON: $state_file"
        rescue_set_decision "fail" "blocked" "The ACFS state file is malformed, so the safe next step is to capture diagnostics before changing anything." "acfs support-bundle"
        return 0
    fi

    RESCUE_STATE_STATUS="valid"
    schema_version="$(rescue_json_get "$state_file" '.schema_version // empty')"
    failed_phase="$(rescue_json_get "$state_file" '.failed_phase // empty')"
    failed_step="$(rescue_json_get "$state_file" '.failed_step // empty')"
    failed_error="$(rescue_json_get "$state_file" '.failed_error // empty')"
    resume_hint="$(rescue_json_get "$state_file" '.resume_hint // empty')"
    current_phase="$(rescue_json_get "$state_file" '.current_phase.id? // .current_phase // empty')"
    current_step="$(rescue_json_get "$state_file" '.current_step // empty')"
    completed_finalize="$(rescue_json_get "$state_file" '(.completed_phases // []) | index("finalize") != null')"
    completed_count="$(rescue_json_get "$state_file" '(.completed_phases // []) | length')"
    last_completed_phase="$(rescue_json_get "$state_file" '(.completed_phases // [] | map(select(type == "string")) | .[-1]) // empty')"
    next_phase="$(rescue_next_phase_after "$last_completed_phase")"
    last_updated="$(rescue_json_get "$state_file" '.last_updated // .updated_at // .last_update // empty')"

    RESCUE_CHECKPOINT_SCHEMA_VERSION="$schema_version"
    RESCUE_CHECKPOINT_COMPLETED_COUNT="$completed_count"
    RESCUE_CHECKPOINT_LAST_COMPLETED_PHASE="$last_completed_phase"
    RESCUE_CHECKPOINT_NEXT_PHASE="$next_phase"
    RESCUE_CHECKPOINT_CURRENT_PHASE="$current_phase"
    RESCUE_CHECKPOINT_FAILED_PHASE="$failed_phase"

    rescue_add_evidence "State file is valid JSON: $state_file"
    if [[ -n "$schema_version" && "$schema_version" != "null" ]]; then
        rescue_add_evidence "State schema version recorded: $schema_version"
    fi
    if [[ -n "$completed_count" && "$completed_count" != "null" ]]; then
        rescue_add_evidence "Completed phases recorded: $completed_count"
    fi
    if [[ -n "$last_completed_phase" && "$last_completed_phase" != "null" ]]; then
        rescue_add_evidence "Last completed phase recorded: $last_completed_phase"
    fi
    if [[ -n "$next_phase" && "$next_phase" != "null" ]]; then
        rescue_add_evidence "Next phase to attempt: $next_phase"
    fi

    if [[ "$schema_version" =~ ^[0-9]+$ ]] && (( schema_version > RESCUE_SUPPORTED_STATE_SCHEMA_VERSION )); then
        RESCUE_STATE_STATUS="future_version"
        RESCUE_INSTALL_STATUS="unknown"
        rescue_set_decision "fail" "future_state" "The ACFS state file was written by a newer schema; capture diagnostics before rerunning this older installer." "acfs support-bundle"
        return 0
    fi

    if [[ -n "$failed_phase" && "$failed_phase" != "null" ]]; then
        RESCUE_INSTALL_STATUS="failed"
        rescue_add_evidence "Failed phase recorded: $failed_phase"
        if [[ -n "$failed_step" && "$failed_step" != "null" ]]; then
            rescue_add_evidence "Failed step recorded: $failed_step"
        fi
        if [[ -n "$failed_error" && "$failed_error" != "null" ]]; then
            rescue_add_evidence "Failure message recorded in state."
        fi
        if rescue_is_safe_next_command "$resume_hint"; then
            rescue_set_decision "fail" "blocked" "The installer recorded a failed phase; resume with the persisted installer command after reviewing the evidence." "$resume_hint"
        else
            rescue_set_decision "fail" "blocked" "The installer recorded a failed phase, but no safe resume command is available in state." "acfs support-bundle"
        fi
        return 0
    fi

    if [[ "$completed_finalize" == "true" ]]; then
        RESCUE_INSTALL_STATUS="healthy"
        rescue_add_evidence "Finalize phase is marked complete."
        rescue_set_decision "pass" "healthy" "ACFS appears installed; continue with onboarding." "onboard"
        return 0
    fi

    if [[ -n "$current_phase" && "$current_phase" != "null" ]]; then
        RESCUE_INSTALL_STATUS="running"
        rescue_add_evidence "Current phase recorded: $current_phase"
        if [[ -n "$current_step" && "$current_step" != "null" ]]; then
            rescue_add_evidence "Current step recorded: $current_step"
        fi

        updated_epoch="$(rescue_timestamp_epoch "$last_updated" 2>/dev/null || true)"
        if [[ -z "$updated_epoch" ]]; then
            updated_epoch="$(rescue_file_mtime_epoch "$state_file" 2>/dev/null || true)"
        fi
        now_epoch="$(rescue_now_epoch 2>/dev/null || true)"

        if [[ -n "$updated_epoch" && -n "$now_epoch" && "$now_epoch" =~ ^[0-9]+$ && "$updated_epoch" =~ ^[0-9]+$ ]]; then
            age_seconds=$((now_epoch - updated_epoch))
            RESCUE_CHECKPOINT_AGE_SECONDS="$age_seconds"
            rescue_add_evidence "Checkpoint age seconds: $age_seconds"
            if (( age_seconds > RESCUE_STALE_SECONDS )); then
                rescue_set_decision "warn" "stale_checkpoint" "The installer has a running checkpoint that has not changed recently." "acfs continue --status"
                return 0
            fi
        fi

        rescue_set_decision "warn" "install_running" "The installer appears to be in progress; watch progress before taking other action." "acfs continue"
        return 0
    fi
}

rescue_analyze_summary() {
    local summary_file="$RESCUE_SUMMARY_FILE"
    local summary_status=""
    local summary_failure_phase=""
    local summary_failure_step=""
    local summary_resume_hint=""

    if [[ "$RESCUE_STATUS" == "fail" || "$RESCUE_STATE_STATUS" == "malformed" || "$RESCUE_STATE_STATUS" == "unreadable" ]]; then
        return 0
    fi

    if [[ -z "$summary_file" ]]; then
        RESCUE_SUMMARY_STATUS="missing"
        rescue_add_evidence "No install summary JSON found."
        return 0
    fi

    RESCUE_SUMMARY_PATH="$summary_file"
    if [[ ! -e "$summary_file" ]]; then
        RESCUE_SUMMARY_STATUS="missing"
        rescue_add_evidence "Install summary not found: $summary_file"
        return 0
    fi

    if [[ ! -r "$summary_file" ]]; then
        RESCUE_SUMMARY_STATUS="unreadable"
        rescue_add_evidence "Install summary exists but is not readable: $summary_file"
        return 0
    fi

    if ! rescue_json_file_valid "$summary_file"; then
        RESCUE_SUMMARY_STATUS="malformed"
        rescue_add_evidence "Install summary is not valid JSON: $summary_file"
        return 0
    fi

    RESCUE_SUMMARY_STATUS="valid"
    summary_status="$(rescue_json_get "$summary_file" '.status // empty')"
    summary_failure_phase="$(rescue_json_get "$summary_file" '.failure.phase // empty')"
    summary_failure_step="$(rescue_json_get "$summary_file" '.failure.step // empty')"
    summary_resume_hint="$(rescue_json_get "$summary_file" '.failure.resume_hint // empty')"

    rescue_add_evidence "Install summary is valid JSON: $summary_file"
    if [[ -n "$summary_status" && "$summary_status" != "null" ]]; then
        rescue_add_evidence "Latest install summary status: $summary_status"
    fi

    if [[ "$RESCUE_STATE_STATUS" == "valid" && "$RESCUE_INSTALL_STATUS" != "unknown" ]]; then
        return 0
    fi

    case "$summary_status" in
        success)
            RESCUE_INSTALL_STATUS="healthy"
            rescue_set_decision "pass" "healthy" "The latest install summary reports success; continue with onboarding." "onboard"
            ;;
        failure|failed)
            RESCUE_INSTALL_STATUS="failed"
            if [[ -n "$summary_failure_phase" && "$summary_failure_phase" != "null" ]]; then
                rescue_add_evidence "Failed phase in summary: $summary_failure_phase"
            fi
            if [[ -n "$summary_failure_step" && "$summary_failure_step" != "null" ]]; then
                rescue_add_evidence "Failed step in summary: $summary_failure_step"
            fi
            if rescue_is_safe_next_command "$summary_resume_hint"; then
                rescue_set_decision "fail" "blocked" "The latest install summary reports failure; resume with the recorded command after reviewing the evidence." "$summary_resume_hint"
            else
                rescue_set_decision "fail" "blocked" "The latest install summary reports failure, but no safe resume command is available." "acfs support-bundle"
            fi
            ;;
    esac
}

rescue_analyze_doctor() {
    local doctor_file="$RESCUE_DOCTOR_FILE"
    local doctor_status=""
    local fail_count=""
    local warn_count=""

    if [[ -z "$doctor_file" ]]; then
        RESCUE_DOCTOR_STATUS="missing"
        return 0
    fi

    RESCUE_DOCTOR_PATH="$doctor_file"
    if [[ ! -e "$doctor_file" ]]; then
        RESCUE_DOCTOR_STATUS="missing"
        rescue_add_evidence "Doctor JSON not found: $doctor_file"
        return 0
    fi

    if [[ ! -r "$doctor_file" ]]; then
        RESCUE_DOCTOR_STATUS="unreadable"
        rescue_add_evidence "Doctor JSON exists but is not readable: $doctor_file"
        return 0
    fi

    if ! rescue_json_file_valid "$doctor_file"; then
        RESCUE_DOCTOR_STATUS="malformed"
        rescue_add_evidence "Doctor JSON is not valid JSON: $doctor_file"
        return 0
    fi

    RESCUE_DOCTOR_STATUS="valid"
    doctor_status="$(rescue_json_get "$doctor_file" '.status // empty')"
    fail_count="$(rescue_json_get "$doctor_file" '.summary.fail // .summary.failed // 0')"
    warn_count="$(rescue_json_get "$doctor_file" '.summary.warn // .summary.warnings // 0')"
    [[ "$fail_count" =~ ^[0-9]+$ ]] || fail_count=0
    [[ "$warn_count" =~ ^[0-9]+$ ]] || warn_count=0
    rescue_add_evidence "Doctor JSON is valid: $doctor_file"
    rescue_add_evidence "Doctor status: ${doctor_status:-unknown}"

    if [[ "$RESCUE_INSTALL_STATUS" == "failed" || "$RESCUE_STATUS" == "fail" ]]; then
        return 0
    fi

    if [[ "$doctor_status" == "fail" || "${fail_count:-0}" -gt 0 ]]; then
        rescue_set_decision "fail" "doctor_failed" "Doctor checks are failing; collect a support bundle before changing installer state." "acfs support-bundle"
    elif [[ "$doctor_status" == "warn" || "${warn_count:-0}" -gt 0 ]]; then
        rescue_set_decision "warn" "doctor_warned" "Doctor checks have warnings; inspect doctor output before rerunning the installer." "acfs doctor --json"
    fi
}

rescue_finalize_missing_state_decision() {
    if [[ "$RESCUE_STATE_STATUS" != "missing" || "$RESCUE_INSTALL_STATUS" != "unknown" || "$RESCUE_STATUS" == "fail" ]]; then
        return 0
    fi

    rescue_set_decision "warn" "needs_state" "No ACFS state file was found; verify whether ACFS was installed on this VPS before rerunning anything." "acfs status --json"
}

rescue_render_json() {
    local jq_bin=""
    local evidence_json=""
    local non_actions_json=""
    local support_available_json=""

    jq_bin="$(rescue_jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        printf '{"schema_version":1,"status":"fail","severity":"blocked","reason":"jq is required for acfs rescue JSON output","next_command":"acfs support-bundle"}\n'
        return 0
    fi

    evidence_json="$(rescue_array_json "${RESCUE_EVIDENCE[@]}")"
    non_actions_json="$(rescue_array_json "${RESCUE_NON_ACTIONS[@]}")"
    support_available_json="$(rescue_bool_json "$RESCUE_SUPPORT_AVAILABLE")"

    "$jq_bin" -n \
        --argjson schema_version 1 \
        --arg status "$RESCUE_STATUS" \
        --arg severity "$RESCUE_SEVERITY" \
        --arg reason "$RESCUE_REASON" \
        --arg next_command "$RESCUE_NEXT_COMMAND" \
        --arg state_status "$RESCUE_STATE_STATUS" \
        --arg state_path "$RESCUE_STATE_PATH" \
        --arg summary_status "$RESCUE_SUMMARY_STATUS" \
        --arg summary_path "$RESCUE_SUMMARY_PATH" \
        --arg doctor_status "$RESCUE_DOCTOR_STATUS" \
        --arg doctor_path "$RESCUE_DOCTOR_PATH" \
        --arg install_status "$RESCUE_INSTALL_STATUS" \
        --arg checkpoint_schema_version "$RESCUE_CHECKPOINT_SCHEMA_VERSION" \
        --argjson checkpoint_supported_schema_version "$RESCUE_CHECKPOINT_SUPPORTED_SCHEMA_VERSION" \
        --arg checkpoint_completed_count "$RESCUE_CHECKPOINT_COMPLETED_COUNT" \
        --arg checkpoint_last_completed_phase "$RESCUE_CHECKPOINT_LAST_COMPLETED_PHASE" \
        --arg checkpoint_next_phase "$RESCUE_CHECKPOINT_NEXT_PHASE" \
        --arg checkpoint_current_phase "$RESCUE_CHECKPOINT_CURRENT_PHASE" \
        --arg checkpoint_failed_phase "$RESCUE_CHECKPOINT_FAILED_PHASE" \
        --arg checkpoint_age_seconds "$RESCUE_CHECKPOINT_AGE_SECONDS" \
        --arg support_command "acfs support-bundle" \
        --argjson support_available "$support_available_json" \
        --arg support_latest "$RESCUE_SUPPORT_LATEST" \
        --arg support_report "$RESCUE_SUPPORT_REPORT" \
        --argjson evidence "$evidence_json" \
        --argjson non_actions "$non_actions_json" \
        '{
            schema_version: $schema_version,
            status: $status,
            severity: $severity,
            reason: $reason,
            next_command: $next_command,
            install_status: $install_status,
            sources: {
                state: {status: $state_status, path: (if $state_path == "" then null else $state_path end)},
                summary: {status: $summary_status, path: (if $summary_path == "" then null else $summary_path end)},
                doctor: {status: $doctor_status, path: (if $doctor_path == "" then null else $doctor_path end)}
            },
            checkpoint: {
                state_schema_version: (if $checkpoint_schema_version == "" then null else ($checkpoint_schema_version | tonumber? // $checkpoint_schema_version) end),
                supported_state_schema_version: $checkpoint_supported_schema_version,
                completed_phase_count: (if $checkpoint_completed_count == "" then null else ($checkpoint_completed_count | tonumber? // null) end),
                last_completed_phase: (if $checkpoint_last_completed_phase == "" then null else $checkpoint_last_completed_phase end),
                next_phase: (if $checkpoint_next_phase == "" then null else $checkpoint_next_phase end),
                current_phase: (if $checkpoint_current_phase == "" then null else $checkpoint_current_phase end),
                failed_phase: (if $checkpoint_failed_phase == "" then null else $checkpoint_failed_phase end),
                age_seconds: (if $checkpoint_age_seconds == "" then null else ($checkpoint_age_seconds | tonumber? // null) end)
            },
            evidence: $evidence,
            non_actions: $non_actions,
            support_bundle: {
                command: $support_command,
                available: $support_available,
                latest: (if $support_latest == "" then null else $support_latest end),
                report: (if $support_report == "" then null else $support_report end)
            }
        }'
}

rescue_render_human() {
    local evidence=""
    local action=""

    printf 'ACFS Rescue Advisor\n'
    printf 'Status: %s\n' "$RESCUE_STATUS"
    printf 'Severity: %s\n' "$RESCUE_SEVERITY"
    printf 'Reason: %s\n' "$RESCUE_REASON"
    printf 'Next command: %s\n' "$RESCUE_NEXT_COMMAND"
    printf '\n'
    printf 'Evidence:\n'
    if [[ ${#RESCUE_EVIDENCE[@]} -eq 0 ]]; then
        printf '  - No evidence collected.\n'
    else
        for evidence in "${RESCUE_EVIDENCE[@]}"; do
            printf '  - %s\n' "$evidence"
        done
    fi
    printf '\n'
    printf 'Non-actions:\n'
    for action in "${RESCUE_NON_ACTIONS[@]}"; do
        printf '  - %s\n' "$action"
    done
    printf '\n'
    printf 'Support bundle command: acfs support-bundle\n'
    if [[ "$RESCUE_SUPPORT_AVAILABLE" == "true" ]]; then
        printf 'Latest support bundle: %s\n' "$RESCUE_SUPPORT_LATEST"
        if [[ -n "$RESCUE_SUPPORT_REPORT" ]]; then
            printf 'Support report: %s\n' "$RESCUE_SUPPORT_REPORT"
        fi
    else
        printf 'Support bundle: none found yet\n'
    fi
}

rescue_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                RESCUE_JSON=true
                shift
                ;;
            --state-file)
                shift
                [[ -n "${1:-}" ]] || { echo "Error: --state-file requires a path" >&2; return 2; }
                RESCUE_STATE_FILE="$1"
                shift
                ;;
            --summary-file)
                shift
                [[ -n "${1:-}" ]] || { echo "Error: --summary-file requires a path" >&2; return 2; }
                RESCUE_SUMMARY_FILE="$1"
                shift
                ;;
            --doctor-file)
                shift
                [[ -n "${1:-}" ]] || { echo "Error: --doctor-file requires a path" >&2; return 2; }
                RESCUE_DOCTOR_FILE="$1"
                shift
                ;;
            --support-dir)
                shift
                [[ -n "${1:-}" ]] || { echo "Error: --support-dir requires a path" >&2; return 2; }
                RESCUE_SUPPORT_DIR="$1"
                shift
                ;;
            --acfs-home)
                shift
                [[ -n "${1:-}" ]] || { echo "Error: --acfs-home requires a path" >&2; return 2; }
                RESCUE_ACFS_HOME="$1"
                shift
                ;;
            --now-epoch)
                shift
                [[ -n "${1:-}" ]] || { echo "Error: --now-epoch requires seconds" >&2; return 2; }
                RESCUE_NOW_EPOCH="$1"
                shift
                ;;
            --stale-seconds)
                shift
                [[ -n "${1:-}" ]] || { echo "Error: --stale-seconds requires seconds" >&2; return 2; }
                RESCUE_STALE_SECONDS="$1"
                shift
                ;;
            -h|--help|help)
                rescue_usage
                exit 0
                ;;
            *)
                echo "Error: unknown rescue option: $1" >&2
                echo "Try 'acfs rescue --help' for usage." >&2
                return 2
                ;;
        esac
    done
}

rescue_main() {
    local argument
    for argument in "$@"; do
        case "$argument" in
            --log-file|--log-file=*)
                rescue_explain_log "$@"
                return $?
                ;;
        esac
    done
    rescue_parse_args "$@"
    rescue_resolve_defaults
    rescue_probe_support
    rescue_analyze_state
    rescue_analyze_summary
    rescue_analyze_doctor
    rescue_finalize_missing_state_decision

    if [[ "$RESCUE_JSON" == "true" ]]; then
        rescue_render_json
    else
        rescue_render_human
    fi

    return "$RESCUE_EXIT_CODE"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    rescue_main "$@"
fi
