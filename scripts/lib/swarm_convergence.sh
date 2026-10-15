#!/usr/bin/env bash
# ============================================================
# ACFS Swarm Convergence - epic success criteria audit
#
# Builds a read-only report that maps an epic's success criteria to child
# Beads and commit evidence. It suggests follow-up Bead titles but never
# creates, updates, closes, reserves, mails, launches, or mutates anything.
# ============================================================

set -euo pipefail

SWARM_CONVERGENCE_JSON=false
SWARM_CONVERGENCE_EPIC_ID=""
SWARM_CONVERGENCE_EPIC_FILE=""
SWARM_CONVERGENCE_ISSUES_FILE=""
SWARM_CONVERGENCE_COMMITS_FILE=""

swarm_convergence_usage() {
    cat <<'EOF'
Usage: acfs swarm convergence --epic ID [OPTIONS]

Options:
  --json               Emit machine-readable JSON
  --markdown           Emit Markdown output (default)
  --epic ID            Epic Bead ID to audit
  --epic-file FILE     Read br show <epic> --json output from a file
  --issues-file FILE   Read Beads issue JSON/JSONL from a file
  --commits-file FILE  Read commit evidence JSON from a file
  --help, -h           Show this help

The command is advisory-only. It reports satisfied, weakly verified, and
missing criteria, then suggests follow-up Bead titles without mutating Beads.
EOF
}

swarm_convergence_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                SWARM_CONVERGENCE_JSON=true
                shift
                ;;
            --markdown)
                SWARM_CONVERGENCE_JSON=false
                shift
                ;;
            --epic)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --epic requires a Bead ID" >&2
                    return 2
                fi
                SWARM_CONVERGENCE_EPIC_ID="$2"
                shift 2
                ;;
            --epic-file)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --epic-file requires a path" >&2
                    return 2
                fi
                SWARM_CONVERGENCE_EPIC_FILE="$2"
                shift 2
                ;;
            --issues-file)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --issues-file requires a path" >&2
                    return 2
                fi
                SWARM_CONVERGENCE_ISSUES_FILE="$2"
                shift 2
                ;;
            --commits-file)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --commits-file requires a path" >&2
                    return 2
                fi
                SWARM_CONVERGENCE_COMMITS_FILE="$2"
                shift 2
                ;;
            --help|-h)
                swarm_convergence_usage
                return 100
                ;;
            *)
                echo "Error: unknown option: $1" >&2
                echo "Run 'acfs swarm convergence --help' for usage." >&2
                return 2
                ;;
        esac
    done

    if [[ -z "$SWARM_CONVERGENCE_EPIC_ID" && -z "$SWARM_CONVERGENCE_EPIC_FILE" ]]; then
        echo "Error: provide --epic or --epic-file" >&2
        return 2
    fi
}

swarm_convergence_binary_path() {
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

swarm_convergence_normalize_json() {
    local jq_bin="$1"
    local kind="$2"

    # Slurp before emitting anything: a malformed trailing record must not turn
    # a valid prefix into a successful (but incomplete) audit.
    "$jq_bin" -s --arg kind "$kind" '
        def invalid($message): error($kind + " input: " + $message);
        def objects: type == "array" and all(.[]; type == "object");
        def object_list:
            (if type == "object" and (.issues | type) == "array" then
                # A page is valid JSON, but not a complete evidence source.
                # Check metadata before unwrapping so it cannot be lost during
                # normalization or local child filtering. Legacy wrappers with
                # no pagination metadata remain valid.
                if has("has_more") and .has_more != false then
                    invalid("incomplete export: has_more must be false; provide all pages or use br list --all --deferred --limit 0 --json")
                elif has("offset") and .offset != 0 then
                    invalid("incomplete export: offset must be 0")
                elif has("total") and .total != (.issues | length) then
                    invalid("incomplete export: total must equal the number of supplied records")
                else .issues end
             else . end)
            | if objects then . else invalid("expected an array of objects or an issues wrapper") end;
        if $kind == "epic" then
            if length != 1 then invalid("expected exactly one JSON value")
            else .[0]
                | (if type == "array" then .[0] else . end) as $epic
                | if ($epic | type) != "object" then
                    invalid("expected an epic object or a non-empty array of epic objects")
                  elif ($epic.dependencies != null and ($epic.dependencies | objects | not)) then
                    invalid("dependencies must be an array of objects")
                  elif ($epic.success_criteria != null and
                        ($epic.success_criteria | (type == "array" and all(.[]; type == "string")) | not)) then
                    invalid("success_criteria must be an array of strings")
                  else . end
            end
        elif $kind == "issues" then
            if length == 1 and (.[0] | type) == "array" then .[0] | object_list
            elif length == 1 and (.[0] | type) == "object" and (.[0] | has("issues")) then
                .[0] | object_list
            elif all(.[]; type == "object" and (.id | type) == "string") then .
            else invalid("expected an issue array, issues wrapper, or JSONL issue objects") end
        else
            if length != 1 then invalid("expected exactly one JSON value")
            else .[0] | object_list end
        end
    '
}

swarm_convergence_read_json_or_jsonl() {
    local jq_bin="$1"
    local path="$2"

    [[ -f "$path" ]] || {
        echo "Error: file not found: $path" >&2
        return 2
    }

    swarm_convergence_normalize_json "$jq_bin" issues < "$path"
}

swarm_convergence_child_ids_json() {
    local jq_bin="$1"
    local epic_json="$2"

    "$jq_bin" -c '
        def arr($v): if ($v | type) == "array" then $v else [] end;
        (if type == "array" then (.[0] // {}) else . end) as $epic
        | [arr($epic.dependencies)[]? | (.id // .issue_id // .depends_on_id // "") | select(. != "")]
    ' <<< "$epic_json"
}

swarm_convergence_collect_epic_json() {
    local br_bin=""

    if [[ -n "$SWARM_CONVERGENCE_EPIC_FILE" ]]; then
        cat -- "$SWARM_CONVERGENCE_EPIC_FILE"
        return $?
    fi

    br_bin="$(swarm_convergence_binary_path br 2>/dev/null || true)"
    [[ -n "$br_bin" ]] || {
        echo "Error: br is required unless --epic-file is provided" >&2
        return 2
    }
    # Disable implicit import/export even for reads: an advisory audit must not
    # synchronize or otherwise change the users Beads store.
    "$br_bin" show "$SWARM_CONVERGENCE_EPIC_ID" --json --no-auto-import --no-auto-flush
}

swarm_convergence_collect_issues_json() {
    local jq_bin="$1"
    local epic_json="$2"
    local br_bin=""
    local child_ids_json=""

    if [[ -n "$SWARM_CONVERGENCE_ISSUES_FILE" ]]; then
        swarm_convergence_read_json_or_jsonl "$jq_bin" "$SWARM_CONVERGENCE_ISSUES_FILE"
        return $?
    fi

    if [[ -f ".beads/issues.jsonl" ]]; then
        child_ids_json="$(swarm_convergence_child_ids_json "$jq_bin" "$epic_json")" || return $?
        swarm_convergence_read_json_or_jsonl "$jq_bin" .beads/issues.jsonl \
            | "$jq_bin" --slurpfile child_ids <(printf '%s\n' "$child_ids_json") '
                map(select(.id as $id | $child_ids[0] | index($id)))
            '
        return $?
    fi

    br_bin="$(swarm_convergence_binary_path br 2>/dev/null || true)"
    [[ -n "$br_bin" ]] || {
        printf '[]\n'
        return 0
    }
    # The default work queue hides closed/deferred issues. Auditing an epic
    # needs their evidence too, without any version-dependent result limit.
    "$br_bin" list --json --all --deferred --limit 0 --no-auto-import --no-auto-flush
}

swarm_convergence_collect_commits_json() {
    local jq_bin="$1"
    local epic_json="$2"
    local git_bin=""
    local child_ids_json=""

    if [[ -n "$SWARM_CONVERGENCE_COMMITS_FILE" ]]; then
        cat -- "$SWARM_CONVERGENCE_COMMITS_FILE"
        return $?
    fi

    git_bin="$(swarm_convergence_binary_path git 2>/dev/null || true)"
    [[ -n "$git_bin" ]] || {
        printf '[]\n'
        return 0
    }
    child_ids_json="$(swarm_convergence_child_ids_json "$jq_bin" "$epic_json")" || return $?
    "$git_bin" log --format='%H%x1f%s%x1e' --all 2>/dev/null \
        | "$jq_bin" -R -s --slurpfile child_ids <(printf '%s\n' "$child_ids_json") '
            split("\u001e")[:-1]
            | map(split("\u001f") | {hash: .[0], subject: (.[1] // "")})
            | map(select(.subject as $subject | any($child_ids[0][]; . as $id | $subject | contains($id))))
        '
}

swarm_convergence_jq_filter() {
    cat <<'JQ'
def arr($v):
  if $v == null then []
  elif ($v | type) == "array" then $v
  elif (($v | type) == "object") and ($v.issues | type) == "array" then $v.issues
  else [] end;
def text($v): ($v // "" | tostring);
def lower($v): text($v) | ascii_downcase;
def stopwords: ["able","about","action","agent","agents","and","backend","beads","command","concrete","criteria","detailed","every","from","host","into","local","maintainer","receive","report","resource","should","status","swarm","that","the","this","through","with","without","workflows"];
def tokens($s):
  lower($s)
  | gsub("[^a-z0-9]+"; " ")
  | split(" ")
  | map(select(length > 3))
  | map(. as $token | select((stopwords | index($token)) | not))
  | unique;
def safe_title($s): text($s) | gsub("`"; "'");

def epic_doc:
  if ($epic_input | type) == "array" then ($epic_input[0] // {}) else $epic_input end;
def issue_list: arr($issues_input);
def commit_list: arr($commits_input);
def issue_for($id): first(issue_list[]? | select(.id == $id)) // {};
def commits_for($id): [commit_list[]? | select((.subject // "") | contains($id))];

def criteria_from_description($description):
  (text($description) | split("\n")) as $lines
  | reduce $lines[] as $line ({inside:false, out:[]};
      if ($line | test("^##[[:space:]]+Success criteria"; "i")) then
        .inside = true
      elif .inside and ($line | test("^##[[:space:]]+")) then
        .inside = false
      elif .inside and ($line | test("^[[:space:]]*[-*][[:space:]]+")) then
        .out += [($line | sub("^[[:space:]]*[-*][[:space:]]+"; ""))]
      else . end
    )
  | .out;

def criteria:
  if (epic_doc.success_criteria | type) == "array" then epic_doc.success_criteria
  else criteria_from_description(epic_doc.description) end;

def child_issues:
  [arr(epic_doc.dependencies)[]?
   | (.id // .issue_id // .depends_on_id // "") as $id
   | select($id != "")
   | (issue_for($id)) as $issue
   | (commits_for($id)) as $commits
   | {
       id: $id,
       title: (.title // $issue.title // ""),
       status: (.status // $issue.status // "unknown"),
       priority: (.priority // $issue.priority // null),
       issue_type: ($issue.issue_type // .issue_type // null),
       labels: arr($issue.labels // .labels),
       close_reason: ($issue.close_reason // ""),
       comments: arr($issue.comments),
       commits: $commits,
       dependency_type: (.dependency_type // null)
     }];

def child_text($c):
  ([
    $c.id,
    $c.title,
    ($c.labels | join(" ")),
    $c.close_reason,
    ($c.comments[]?.text // ""),
    ($c.commits[]?.subject // "")
  ] | join(" ") | ascii_downcase);

def proofy($c):
  (child_text($c) | test("test|tests|artifact|artifacts|commit|evidence|passed|coverage|logs|fixture|support-bundle|dashboard|report|verified|verification"));

def match_score($criterion; $c):
  (tokens($criterion)) as $terms
  | (child_text($c)) as $body
  | [$terms[] | . as $term | select($body | contains($term))] | unique | length;

def criterion_report($criterion):
  [child_issues[] | . as $c | (match_score($criterion; $c)) as $score | select($score > 0) | $c + {match_score: $score}] as $matches
  | [$matches[] | select(.status == "closed")] as $closed
  | [$matches[] | select(.status != "closed")] as $open
  | [$closed[] | select(proofy(.))] as $strong
  | {
      criterion: $criterion,
      status: (if ($strong | length) > 0 then "satisfied" elif (($closed | length) > 0 or ($open | length) > 0) then "weakly_verified" else "missing" end),
      evidence: (($strong + $closed + $open)
        | unique_by(.id)
        | sort_by(-.match_score, .status, .id)
        | map({
            bead_id: .id,
            title: safe_title(.title),
            status: .status,
            match_score: .match_score,
            commit_subjects: ([.commits[]?.subject] | map(safe_title(.)) | .[:3])
          }) | .[:6]),
      suggested_bead_title: (if (($matches | length) == 0) then ("Add evidence for epic criterion: " + ($criterion | sub("[.]$"; ""))) else null end)
    };

(criteria | map(criterion_report(.))) as $criteria_reports
| [child_issues[] as $child | select([criteria[] | match_score(.; $child)] | max <= 0) | {
    bead_id: $child.id,
    title: safe_title($child.title),
    status: $child.status
  }] as $over_broad
| {
    schema_version: 1,
    status: (if any($criteria_reports[]; .status == "missing") then "warn" else "pass" end),
    advisory_only: true,
    mutations: {
      creates_beads: false,
      updates_beads: false,
      closes_beads: false,
      sends_agent_mail: false
    },
    epic: {
      id: (epic_doc.id // $epic_id),
      title: safe_title(epic_doc.title),
      status: (epic_doc.status // null)
    },
    summary: {
      criteria_total: ($criteria_reports | length),
      satisfied: ([$criteria_reports[] | select(.status == "satisfied")] | length),
      weakly_verified: ([$criteria_reports[] | select(.status == "weakly_verified")] | length),
      missing: ([$criteria_reports[] | select(.status == "missing")] | length),
      child_beads: (child_issues | length),
      over_broad_children: ($over_broad | length)
    },
    criteria: $criteria_reports,
    over_broad_children: $over_broad,
    suggested_bead_titles: ([$criteria_reports[] | .suggested_bead_title // empty])
  }
JQ
}

swarm_convergence_build_report() {
    local jq_bin="$1"
    local epic_json="$2"
    local issues_json="$3"
    local commits_json="$4"

    # Only bounded metadata and descriptor paths belong in argv. Bash's printf
    # builtin streams each normalized document independently, without temporary
    # files or execve's per-argument/total argument-size limits (#454).
    "$jq_bin" -n \
        --arg epic_id "$SWARM_CONVERGENCE_EPIC_ID" \
        --slurpfile epic_documents <(printf '%s\n' "$epic_json") \
        --slurpfile issues_documents <(printf '%s\n' "$issues_json") \
        --slurpfile commits_documents <(printf '%s\n' "$commits_json") \
        '$epic_documents[0] as $epic_input |
         $issues_documents[0] as $issues_input |
         $commits_documents[0] as $commits_input |
        '"$(swarm_convergence_jq_filter)"
}

swarm_convergence_emit_markdown() {
    local report="$1"
    local jq_bin="$2"

    printf '# ACFS Swarm Convergence Audit\n\n'
    printf 'Advisory only: this command did not create, update, or close Beads; send Agent Mail; claim reservations; or launch agents.\n\n'
    "$jq_bin" -r '
      "Epic: `\(.epic.id)` \(.epic.title)",
      "",
      "## Summary",
      "- Criteria: `\(.summary.criteria_total)`",
      "- Satisfied: `\(.summary.satisfied)`",
      "- Weakly verified: `\(.summary.weakly_verified)`",
      "- Missing: `\(.summary.missing)`",
      "- Child Beads: `\(.summary.child_beads)`",
      "- Over-broad children: `\(.summary.over_broad_children)`",
      "",
      "## Criteria",
      (.criteria[] | "### \(.status | ascii_upcase)\n\(.criterion)\n\nEvidence:\n" + (if (.evidence | length) == 0 then "- None" else (.evidence | map("- `\(.bead_id)` \(.status): \(.title)") | join("\n")) end) + (if .suggested_bead_title then "\n\nSuggested follow-up: `" + .suggested_bead_title + "`" else "" end)),
      "",
      "## Over-Broad Children",
      (if (.over_broad_children | length) == 0 then "- None" else (.over_broad_children[] | "- `\(.bead_id)` \(.status): \(.title)") end)
    ' <<< "$report"
}

swarm_convergence_main() {
    local parse_status=0
    local jq_bin=""
    local epic_json=""
    local issues_json=""
    local commits_json=""
    local report=""

    swarm_convergence_parse_args "$@" || parse_status=$?
    case "$parse_status" in
        0) ;;
        100) return 0 ;;
        *) return "$parse_status" ;;
    esac

    jq_bin="$(swarm_convergence_binary_path jq 2>/dev/null || true)"
    [[ -n "$jq_bin" ]] || {
        echo "Error: jq is required for swarm convergence audit" >&2
        return 2
    }

    epic_json="$(swarm_convergence_collect_epic_json | swarm_convergence_normalize_json "$jq_bin" epic)" || {
        echo "Error: failed to read epic input" >&2
        return 2
    }
    issues_json="$(swarm_convergence_collect_issues_json "$jq_bin" "$epic_json" | swarm_convergence_normalize_json "$jq_bin" issues)" || {
        echo "Error: failed to read issues input" >&2
        return 2
    }
    commits_json="$(swarm_convergence_collect_commits_json "$jq_bin" "$epic_json" | swarm_convergence_normalize_json "$jq_bin" commits)" || {
        echo "Error: failed to read commits input" >&2
        return 2
    }

    report="$(swarm_convergence_build_report "$jq_bin" "$epic_json" "$issues_json" "$commits_json")" || {
        echo "Error: failed to build convergence report" >&2
        return 2
    }
    if [[ "$SWARM_CONVERGENCE_JSON" == "true" ]]; then
        printf '%s\n' "$report"
    else
        swarm_convergence_emit_markdown "$report" "$jq_bin"
    fi
}

swarm_convergence_main "$@"
