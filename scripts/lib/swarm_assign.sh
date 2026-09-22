#!/usr/bin/env bash
# ============================================================
# ACFS Swarm Assign - role-aware Beads allocation planner
#
# Reads ready Beads plus optional bv triage JSON, then emits advisory-only
# per-agent assignment suggestions. This script never marks Beads, sends
# Agent Mail, claims reservations, launches agents, or mutates RCH/NTM state.
# ============================================================

set -euo pipefail

SWARM_ASSIGN_JSON=false
SWARM_ASSIGN_AGENTS=""
SWARM_ASSIGN_ROLES=""
SWARM_ASSIGN_PROFILE="balanced"
SWARM_ASSIGN_READY_FILE=""
SWARM_ASSIGN_TRIAGE_FILE=""
SWARM_ASSIGN_SCOPES_FILE=""

swarm_assign_usage() {
    cat <<'EOF'
Usage: acfs swarm assign [OPTIONS]

Options:
  --json              Emit machine-readable JSON
  --markdown          Emit Markdown output (default)
  --agents N          Requested agent count when --roles is omitted
  --roles SPEC        Role mix, e.g. implementation:2,review:1,testing,docs
  --profile NAME      balanced, codex-heavy, review-heavy, or docs-heavy
                      (default: balanced)
  --ready-file FILE   Read br ready --json output from a fixture/file
  --triage-file FILE  Read bv --robot-triage output from a fixture/file
  --scopes-file FILE  Allocate non-overlapping, explicitly declared write scopes
  --help, -h          Show this help

The command is advisory-only. It prints Bead IDs, suggested roles, reservation
surfaces, and Agent Mail thread IDs, but it does not claim work or send mail.
Without --scopes-file, inferred reservation surfaces are NOT parallel admission.
Inputs require Python 3 for bounded, duplicate-key-rejecting JSON validation.
EOF
}

swarm_assign_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                SWARM_ASSIGN_JSON=true
                shift
                ;;
            --markdown)
                SWARM_ASSIGN_JSON=false
                shift
                ;;
            --agents)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --agents requires a positive integer" >&2
                    return 2
                fi
                SWARM_ASSIGN_AGENTS="$2"
                shift 2
                ;;
            --roles)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --roles requires a role specification" >&2
                    return 2
                fi
                SWARM_ASSIGN_ROLES="$2"
                shift 2
                ;;
            --profile)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --profile requires a value" >&2
                    return 2
                fi
                SWARM_ASSIGN_PROFILE="$2"
                shift 2
                ;;
            --ready-file)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --ready-file requires a path" >&2
                    return 2
                fi
                SWARM_ASSIGN_READY_FILE="$2"
                shift 2
                ;;
            --triage-file)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --triage-file requires a path" >&2
                    return 2
                fi
                SWARM_ASSIGN_TRIAGE_FILE="$2"
                shift 2
                ;;
            --scopes-file)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --scopes-file requires a path" >&2
                    return 2
                fi
                SWARM_ASSIGN_SCOPES_FILE="$2"
                shift 2
                ;;
            --help|-h)
                swarm_assign_usage
                return 100
                ;;
            *)
                echo "Error: unknown option: $1" >&2
                echo "Run 'acfs swarm assign --help' for usage." >&2
                return 2
                ;;
        esac
    done

    case "$SWARM_ASSIGN_PROFILE" in
        balanced|codex-heavy|review-heavy|docs-heavy) ;;
        *)
            echo "Error: unsupported profile: $SWARM_ASSIGN_PROFILE" >&2
            return 2
            ;;
    esac

    if [[ -n "$SWARM_ASSIGN_AGENTS" ]]; then
        if [[ ! "$SWARM_ASSIGN_AGENTS" =~ ^[0-9]{1,3}$ ]] || (( 10#$SWARM_ASSIGN_AGENTS < 1 || 10#$SWARM_ASSIGN_AGENTS > 100 )); then
            echo "Error: --agents must be between 1 and 100" >&2
            return 2
        fi
        SWARM_ASSIGN_AGENTS=$((10#$SWARM_ASSIGN_AGENTS))
    fi

    if [[ -z "$SWARM_ASSIGN_ROLES" && -z "$SWARM_ASSIGN_AGENTS" ]]; then
        echo "Error: provide --agents or --roles" >&2
        return 2
    fi
}

swarm_assign_binary_path() {
    local name="${1:-}"
    local path_value=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..|*/*) return 1 ;;
    esac

    path_value="$(command -v "$name" 2>/dev/null || true)"
    [[ -n "$path_value" && -x "$path_value" ]] || return 1
    printf '%s\n' "$path_value"
}

swarm_assign_normalize_role() {
    local role="$1"

    role="${role,,}"
    role="${role//_/-}"
    case "$role" in
        impl|implement|implementation|code|coding|feature)
            printf 'implementation\n'
            ;;
        review|reviewer|audit|qa)
            printf 'review\n'
            ;;
        test|tests|testing|tester)
            printf 'testing\n'
            ;;
        doc|docs|documentation|writer)
            printf 'documentation\n'
            ;;
        *)
            echo "Error: unsupported role: $role" >&2
            return 2
            ;;
    esac
}

swarm_assign_roles_from_spec() {
    local spec="$1"
    local part=""
    local role=""
    local count=""
    local normalized=""
    local i=0
    local total=0

    [[ "$spec" != ,* && "$spec" != *, && "$spec" != *,,* ]] || {
        echo "Error: empty role in specification" >&2
        return 2
    }
    IFS=',' read -r -a parts <<< "$spec"
    for part in "${parts[@]}"; do
        part="${part//[[:space:]]/}"
        [[ -n "$part" ]] || return 2
        if [[ "$part" =~ ^([A-Za-z_-]+):([0-9]+)$ ]]; then
            role="${BASH_REMATCH[1]}"
            count="${BASH_REMATCH[2]}"
        else
            role="$part"
            count=1
        fi
        normalized="$(swarm_assign_normalize_role "$role")" || return $?
        if [[ ! "$count" =~ ^[0-9]{1,3}$ ]] || (( 10#$count < 1 || 10#$count > 100 )); then
            echo "Error: each role count must be between 1 and 100" >&2
            return 2
        fi
        count=$((10#$count))
        total=$((total + count))
        (( total <= 100 )) || { echo "Error: at most 100 agents may be assigned" >&2; return 2; }
        for ((i = 0; i < count; i++)); do
            printf '%s\n' "$normalized"
        done
    done
}

swarm_assign_roles_from_profile() {
    local agents="$1"
    local profile="$2"
    local i=0
    local role=""

    for ((i = 1; i <= agents; i++)); do
        case "$profile" in
            review-heavy)
                case $(( (i - 1) % 4 )) in
                    0|1) role="review" ;;
                    2) role="implementation" ;;
                    *) role="testing" ;;
                esac
                ;;
            docs-heavy)
                case $(( (i - 1) % 4 )) in
                    0|1) role="documentation" ;;
                    2) role="implementation" ;;
                    *) role="testing" ;;
                esac
                ;;
            codex-heavy)
                case $(( (i - 1) % 5 )) in
                    0|1|2) role="implementation" ;;
                    3) role="testing" ;;
                    *) role="review" ;;
                esac
                ;;
            *)
                case $(( (i - 1) % 5 )) in
                    0|1) role="implementation" ;;
                    2) role="review" ;;
                    3) role="testing" ;;
                    *) role="documentation" ;;
                esac
                ;;
        esac
        printf '%s\n' "$role"
    done
}

swarm_assign_roles_json() {
    local jq_bin="$1"
    local roles_text=""

    if [[ -n "$SWARM_ASSIGN_ROLES" ]]; then
        roles_text="$(swarm_assign_roles_from_spec "$SWARM_ASSIGN_ROLES")" || return $?
    else
        roles_text="$(swarm_assign_roles_from_profile "$SWARM_ASSIGN_AGENTS" "$SWARM_ASSIGN_PROFILE")"
    fi

    printf '%s\n' "$roles_text" \
        | "$jq_bin" -R -s '
            split("\n")
            | map(select(length > 0))
            | to_entries
            | map({slot: (.key + 1), agent: ("agent-" + ((.key + 1) | tostring)), role: .value})
        '
}

# Validate original bytes before Bash or jq can discard NULs/duplicate keys.
# Live probes have bounded output and deadlines and never execute a shell.
swarm_assign_read_input() {
    python3 - "$1" "$2" <<'PY'
import json
import math
import os
import re
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import time

LIMIT = 1048576
kind, path = sys.argv[1:]

def reject(message="invalid input"):
    raise ValueError(message)

def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            reject("duplicate JSON field")
        result[key] = value
    return result

def probe():
    argv = ["br", "ready", "--json"] if kind == "ready" else ["bv", "--robot-triage"]
    executable = shutil.which(argv[0])
    if not executable:
        if kind == "triage":
            return b"{}"
        reject("br is required unless --ready-file is supplied")
    process = subprocess.Popen([executable, *argv[1:]], stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               start_new_session=True)
    data = bytearray()
    deadline = time.monotonic() + 20
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not selector.select(remaining):
                    reject("tool probe timed out")
                chunk = os.read(process.stdout.fileno(), 16384)
                if not chunk:
                    break
                data.extend(chunk)
                if len(data) > LIMIT:
                    reject("tool output exceeds 1 MiB")
        if process.wait(timeout=max(0.001, deadline - time.monotonic())) != 0:
            reject("tool probe failed")
        return data
    finally:
        # A descendant retaining stdout must not outlive a failed probe.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        process.stdout.close()

def valid_id(value):
    return type(value) is str and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", value)

def records(value):
    if type(value) is not list or len(value) > 2048:
        reject("expected at most 2048 issue records")
    seen = set()
    for item in value:
        if type(item) is not dict or not valid_id(item.get("id")) or item["id"] in seen:
            reject("issue IDs must be present, valid and unique")
        seen.add(item["id"])
        for key in ("title", "status", "issue_type", "type", "action"):
            if key in item and item[key] is not None and type(item[key]) is not str:
                reject("invalid issue text field")
        for key in ("labels", "blocked_by"):
            if key in item and (type(item[key]) is not list or any(type(v) is not str for v in item[key])):
                reject("invalid issue array field")
        if "blocked" in item and type(item["blocked"]) is not bool:
            reject("invalid blocked flag")
        for key in ("priority", "estimated_minutes", "score", "unblocks"):
            v = item.get(key)
            if v is not None and not (type(v) in (int, float) and 0 <= v <= 1000000
                                      or type(v) is str and re.fullmatch(r"[0-9]{1,6}", v)):
                reject("invalid issue numeric field")

try:
    if path:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, "rb") as stream:
            if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                reject("input must be a regular file")
            data = stream.read(LIMIT + 1)
    else:
        data = probe()
    if len(data) > LIMIT:
        reject("input exceeds 1 MiB")
    value = json.loads(data, object_pairs_hook=unique, parse_constant=reject)
    pending, nodes = [(value, 0)], 0
    while pending:
        item, depth = pending.pop()
        nodes += 1
        if depth > 32 or nodes > 50000:
            reject("input is too complex")
        if type(item) is dict:
            pending.extend((v, depth + 1) for v in item.values())
        elif type(item) is list:
            pending.extend((v, depth + 1) for v in item)
        elif type(item) is float and not math.isfinite(item):
            reject("non-finite number")
    if kind == "scopes":
        if (type(value) is not dict or set(value) != {"schema_version", "scopes"}
                or type(value["schema_version"]) is not int or value["schema_version"] != 1
                or type(value["scopes"]) is not dict or len(value["scopes"]) > 2048):
            reject("expected schema_version 1 and a scopes object")
        for bead, paths in value["scopes"].items():
            if (not valid_id(bead) or type(paths) is not list or not 1 <= len(paths) <= 32
                    or any(type(p) is not str for p in paths) or len(set(paths)) != len(paths)):
                reject("each scope must have 1 to 32 unique paths")
            for p in paths:
                if (len(p) > 256 or not re.fullmatch(r"[A-Za-z0-9_.*?/ -]+", p)
                        or any(part in ("", ".", "..") for part in p.split("/"))):
                    reject("scopes require relative paths with only literal text, * or ? globs")
    elif kind == "ready":
        records(value)
    else:
        if type(value) is not dict or ("triage" in value and type(value["triage"]) is not dict):
            reject("triage must be an object")
        records(value.get("triage", value).get("recommendations", []))
    print(json.dumps(value, separators=(",", ":"), allow_nan=False))
except (OSError, ValueError, TypeError, RecursionError, subprocess.SubprocessError):
    # Never include parser text or probe output: it can contain credentials.
    print("Error: " + kind + " input invalid, unavailable, or over its size/time limit", file=sys.stderr)
    sys.exit(2)
PY
}

swarm_assign_jq_filter() {
    cat <<'JQ'
def arr($v): if $v == null then [] elif ($v | type) == "array" then $v else [] end;
def text($v): ($v // "" | tostring | ascii_downcase);
def n($v): if ($v | type) == "number" then $v elif (($v | type) == "string" and ($v | test("^[0-9]+$"))) then ($v | tonumber) else 0 end;
def triage_recommendations:
  arr($triage.triage.recommendations // $triage.recommendations);

def triage_for($id):
  first(triage_recommendations[]? | select(.id == $id)) // {};

def display_labels($i):
  if (arr($i.labels) | length) > 0 then arr($i.labels) else arr((triage_for($i.id)).labels) end;
def labels($i): display_labels($i) | map(tostring | ascii_downcase);
def issue_title($i): ($i.title // (triage_for($i.id)).title // "");
def issue_type($i): ($i.issue_type // (triage_for($i.id)).type // (triage_for($i.id)).issue_type // null);
def priority($i): n($i.priority // (triage_for($i.id)).priority // 9);
def estimate($i): if ($i.estimated_minutes // null) == null then 999999 else n($i.estimated_minutes) end;
def has_label($ls; $re): any($ls[]?; test($re));
def has_text($i; $re): (text(issue_title($i)) | test($re));

def is_ready_issue($i):
  (($i.status // "open") == "open")
  and (($i.blocked // false) != true)
  and ((arr($i.blocked_by) | length) == 0)
  and ((arr((triage_for($i.id)).blocked_by) | length) == 0);

def role_fit($i; $role):
  (labels($i)) as $ls
  | (text(issue_type($i))) as $type
  | if $role == "documentation" then
      (if has_label($ls; "docs|documentation|content|lesson|onboard|readme|website") or has_text($i; "doc|readme|lesson|copy|content") then 80 else 5 end)
    elif $role == "testing" then
      (if has_label($ls; "test|tests|qa|coverage|harness") or has_text($i; "test|fixture|harness|coverage|repro") then 80 else 10 end)
    elif $role == "review" then
      (if has_label($ls; "review|audit|quality|security|performance|bug") or has_text($i; "audit|review|bug|regression|security|perf") or $type == "bug" then 80 else 20 end)
    else
      (if $type == "feature" or $type == "task" or has_label($ls; "backend|cli|swarm|capacity|inventory|support|coordination") then 70 else 25 end)
    end;

def rank($i):
  (triage_for($i.id)) as $t
  | ((10 - priority($i)) * 10)
    + (n($t.score) * 1000)
    + (n($t.unblocks) * 5)
    - (estimate($i) / 10000);

def dependency_position($i):
  (triage_for($i.id)) as $t
  | {
      score: ($t.score // null),
      blocked_by: arr($t.blocked_by),
      unblocks: n($t.unblocks),
      action: ($t.action // "Start work on this issue")
    };

def reservation_surfaces($i):
  if $scopes != null then ($scopes.scopes[$i.id] // []) else
  (labels($i)) as $ls
  | ([ ".beads/issues.jsonl" ]
     + (if has_label($ls; "swarm|coordination|bv|beads|capacity|inventory|support") then ["scripts/lib/swarm_*.sh", "tests/unit/test_swarm_*.sh"] else [] end)
     + (if has_label($ls; "capacity") then ["scripts/lib/capacity.sh", "tests/unit/test_capacity.sh"] else [] end)
     + (if has_label($ls; "support") then ["scripts/lib/support.sh", "tests/**/test_support*.sh"] else [] end)
     + (if has_label($ls; "inventory") then ["scripts/lib/swarm_inventory.sh", "tests/unit/test_swarm_inventory.sh"] else [] end)
     + (if has_label($ls; "docs|documentation|content|lesson|onboard|readme") then ["README.md", "docs/**", "acfs/onboard/**"] else [] end)
     + (if has_label($ls; "test|tests|qa|harness") or has_text($i; "test|fixture|harness") then ["tests/**"] else [] end))
    | unique
    | .[:8] end;

# Conservative glob intersection: every matching path begins with the literal
# prefix before the first wildcard. Different prefixes prove disjointness;
# compatible prefixes are treated as conflicts, even if suffixes could differ.
# This deliberately prefers an idle slot over a false claim of independence.
def paths_overlap($a; $b):
  if (($a | test("[*?]") | not) and ($b | test("[*?]") | not)) then $a == $b
  else
    ($a | sub("[*?].*$"; "")) as $ap
    | ($b | sub("[*?].*$"; "")) as $bp
    | ($ap | startswith($bp)) or ($bp | startswith($ap))
  end;
def scope_conflicts($i; $assigned):
  reservation_surfaces($i) as $paths
  | [$assigned[] | select(any(.reservation_surfaces[]; . as $p
      | any($paths[]; paths_overlap(.; $p)))) | .bead_id];
def scope_admission($i; $assigned):
  if $scopes == null then {reason: "scope-unchecked", blocking_beads: []}
  elif ($scopes.scopes | has($i.id) | not) then {reason: "missing-scope", blocking_beads: []}
  elif issue_type($i) == "epic" then {reason: "decompose-first", blocking_beads: []}
  else scope_conflicts($i; $assigned) as $conflicts
    | {reason: (if ($conflicts | length) > 0 then "scope-conflict" else "eligible" end),
       blocking_beads: $conflicts}
  end;

def rationale($i; $role):
  (labels($i)) as $ls
  | if $role == "documentation" and (has_label($ls; "docs|documentation|content|lesson|onboard|readme") or has_text($i; "doc|readme|lesson|copy|content")) then
      "documentation role matches docs/content signals"
    elif $role == "testing" and (has_label($ls; "test|tests|qa|coverage|harness") or has_text($i; "test|fixture|harness|coverage|repro")) then
      "testing role matches test/fixture signals"
    elif $role == "review" and (has_label($ls; "review|audit|quality|security|performance|bug") or has_text($i; "audit|review|bug|regression|security|perf") or text($i.issue_type) == "bug") then
      "review role matches audit/bug/quality signals"
    elif $role == "implementation" then
      "implementation role takes the highest-ranked ready implementation slice"
    else
      "fallback assignment from ready queue ranking"
    end;

def assignment($slot; $i):
  {
    slot: $slot.slot,
    agent: $slot.agent,
    role: $slot.role,
    bead_id: $i.id,
    title: issue_title($i),
    issue_type: issue_type($i),
    priority: (if priority($i) == 9 and (($i.priority // (triage_for($i.id)).priority // null) == null) then null else priority($i) end),
    estimated_minutes: ($i.estimated_minutes // null),
    labels: display_labels($i),
    dependency_position: dependency_position($i),
    reservation_surfaces: reservation_surfaces($i),
    scope_source: (if $scopes == null then "inferred" else "explicit" end),
    agent_mail_thread_id: $i.id,
    suggested_subject: ("[" + $i.id + "] Start: " + ($i.title // "")),
    rationale: rationale($i; $slot.role)
  };

($ready | if type == "array" then . else [] end) as $raw_ready
| ($raw_ready | map(select(is_ready_issue(.)))) as $ready_issues
| (reduce $roles[] as $slot
    ({assignments: [], remaining: ($ready_issues | sort_by(priority(.), estimate(.), .id)), idle: []};
      .assignments as $assigned
      |
      ([
        .remaining[]
        | select($scopes == null or scope_admission(.; $assigned).reason == "eligible")
        | . as $issue
        | {
            issue: $issue,
            fit: role_fit($issue; $slot.role),
            rank: rank($issue)
          }
        ] | sort_by(-.fit, -.rank, priority(.issue), estimate(.issue), .issue.id) | .[0]? ) as $choice
      | if $choice == null then
          .idle += [$slot + {reason: (if $scopes != null and (.remaining | length) > 0
                                     then "no-independent-ready-bead" else "no-ready-bead" end)}]
        else
          .assignments += [assignment($slot; $choice.issue)]
          | .remaining = [.remaining[] | select(.id != $choice.issue.id)]
        end
    )) as $planned
| {
    schema_version: 1,
    status: "pass",
    advisory_only: true,
    scope_admission: {
      mode: (if $scopes == null then "inferred-unchecked" else "explicit-scopes" end),
      status: (if $scopes == null then "unchecked"
               elif ($planned.remaining | any(scope_admission(.; $planned.assignments).reason != "eligible"))
               then "warn" else "pass" end),
      live_reservations_checked: false,
      launch_authorized: false,
      note: "Declared scopes are advisory. Check current Beads and acquire Agent Mail reservations before editing."
    },
    mutations: {
      marks_beads: false,
      sends_agent_mail: false,
      claims_reservations: false,
      launches_agents: false
    },
    inputs: {
      ready_source: $ready_source,
      triage_source: $triage_source,
      scopes_source: (if $scopes == null then "unavailable" else "file" end),
      profile: $profile,
      requested_agents: ($roles | length),
      requested_roles: $roles
    },
    summary: {
      ready_count: ($ready_issues | length),
      assigned_count: ($planned.assignments | length),
      idle_count: ($planned.idle | length),
      unassigned_ready_count: ($planned.remaining | length),
      excluded_count: ($raw_ready | map(select(is_ready_issue(.) | not)) | length)
    },
    assignments: $planned.assignments,
    idle_agents: $planned.idle,
    unassigned_ready_beads: ($planned.remaining | map({
      bead_id: .id,
      title: issue_title(.),
      priority: (if priority(.) == 9 and ((.priority // (triage_for(.id)).priority // null) == null) then null else priority(.) end),
      issue_type: issue_type(.),
      labels: display_labels(.),
      admission: scope_admission(.; $planned.assignments),
      agent_mail_thread_id: .id
    })),
    excluded_beads: ($raw_ready | map(select(is_ready_issue(.) | not) | {
      bead_id: .id,
      title: issue_title(.),
      status: (.status // null),
      reason: (if (.blocked // false) == true or ((arr(.blocked_by) | length) > 0)
               or ((arr((triage_for(.id)).blocked_by) | length) > 0) then "blocked" else "not-ready-status" end)
    }))
  }
JQ
}

swarm_assign_build_report() {
    local jq_bin="$1"
    local ready_json="$2"
    local triage_json="$3"
    local roles_json="$4"
    local scopes_json="$5"
    local ready_source="live-br-ready"
    local triage_source="live-bv-triage"

    [[ -n "$SWARM_ASSIGN_READY_FILE" ]] && ready_source="file"
    [[ -n "$SWARM_ASSIGN_TRIAGE_FILE" ]] && triage_source="file"
    [[ "$triage_json" == "{}" ]] && triage_source="unavailable"

    # Validated JSON travels through stdin, not OS-size-limited argv strings.
    printf '%s\n' "$ready_json" "$triage_json" "$roles_json" "$scopes_json" | "$jq_bin" -s \
        --arg ready_source "$ready_source" \
        --arg triage_source "$triage_source" \
        --arg profile "$SWARM_ASSIGN_PROFILE" \
        '.[0] as $ready | .[1] as $triage | .[2] as $roles | .[3] as $scopes | '"$(swarm_assign_jq_filter)"
}

swarm_assign_emit_markdown() {
    local report="$1"
    local jq_bin="$2"

    printf '# ACFS Swarm Assignment Plan\n\n'
    printf 'Advisory only: this command did not mark Beads, send Agent Mail, claim reservations, launch agents, or change RCH/NTM state.\n\n'

    "$jq_bin" -r '
        "## Summary\n",
        "- Ready Beads considered: `\(.summary.ready_count)`",
        "- Assignments: `\(.summary.assigned_count)`",
        "- Idle agents: `\(.summary.idle_count)`",
        "- Unassigned ready Beads: `\(.summary.unassigned_ready_count)`",
        "- Excluded non-ready/blocked Beads: `\(.summary.excluded_count)`",
        "- Scope admission: `\(.scope_admission.mode)` / `\(.scope_admission.status)`",
        "- Live reservations: not checked; acquire them before editing.",
        "",
        "## Assignments\n",
        "| Agent | Role | Bead | Priority | Reservation Surfaces | Thread |",
        "| --- | --- | --- | --- | --- | --- |",
        (if (.assignments | length) == 0 then
          "| - | - | No ready Beads | - | - | - |"
        else
          (.assignments[] | "| \(.agent) | \(.role) | `\(.bead_id)` \(.title) | P\(.priority // "-") | \((.reservation_surfaces | join("<br>"))) | `\(.agent_mail_thread_id)` |")
        end),
        "",
        "## Idle Agents\n",
        (if (.idle_agents | length) == 0 then
          "- None"
        else
          (.idle_agents[] | "- `\(.agent)` (`\(.role)`): \(.reason)")
        end),
        "",
        "## Unassigned Ready Beads\n",
        (if (.unassigned_ready_beads | length) == 0 then
          "- None"
        else
          (.unassigned_ready_beads[] | "- `\(.bead_id)` P\(.priority // "-") \(.title) — \(.admission.reason); blocking Beads: \(.admission.blocking_beads | join(", "))")
        end)
    ' <<< "$report"
}

swarm_assign_main() {
    local parse_status=0
    local jq_bin=""
    local ready_json=""
    local triage_json=""
    local roles_json=""
    local report=""
    local scopes_json="null"

    swarm_assign_parse_args "$@" || parse_status=$?
    case "$parse_status" in
        0) ;;
        100) return 0 ;;
        *) return "$parse_status" ;;
    esac

    command -v python3 >/dev/null 2>&1 || {
        echo "Error: Python 3 is required to validate assignment inputs" >&2
        return 2
    }
    jq_bin="$(swarm_assign_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        echo "Error: jq is required for swarm assignment planning" >&2
        return 2
    fi

    roles_json="$(swarm_assign_roles_json "$jq_bin")" || return $?
    if [[ -n "$SWARM_ASSIGN_SCOPES_FILE" ]]; then
        scopes_json="$(swarm_assign_read_input scopes "$SWARM_ASSIGN_SCOPES_FILE")" || return $?
    fi
    ready_json="$(swarm_assign_read_input ready "$SWARM_ASSIGN_READY_FILE")" || return $?
    triage_json="$(swarm_assign_read_input triage "$SWARM_ASSIGN_TRIAGE_FILE")" || return $?

    report="$(swarm_assign_build_report "$jq_bin" "$ready_json" "$triage_json" "$roles_json" "$scopes_json")" || return 2
    if [[ "$SWARM_ASSIGN_JSON" == "true" ]]; then
        printf '%s\n' "$report"
    else
        swarm_assign_emit_markdown "$report" "$jq_bin"
    fi
}

swarm_assign_main "$@"
