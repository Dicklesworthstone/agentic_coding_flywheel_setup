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
SWARM_CONVERGENCE_EXPORT_FILE=""

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
  --export-file FILE   Audit --epic ID from one complete Beads JSON/JSONL export
  --help, -h           Show this help

The command is advisory-only. It reports satisfied, weakly verified, and
missing criteria, then suggests follow-up Bead titles without mutating Beads.
Criteria come from success_criteria, a Success criteria description section,
or Beads acceptance_criteria (in that order). Checkboxes are not evidence.
Native parent-child dependents supplement legacy dependency-based children.
With --export-file, no br database is needed or consulted. It replaces both
--epic-file and --issues-file. Git evidence still comes from the current
repository unless --commits-file is supplied (use an empty array for none).
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
            --export-file)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --export-file requires a path" >&2
                    return 2
                fi
                SWARM_CONVERGENCE_EXPORT_FILE="$2"
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
    if [[ -n "$SWARM_CONVERGENCE_EXPORT_FILE" ]] &&
       [[ -z "$SWARM_CONVERGENCE_EPIC_ID" || -n "$SWARM_CONVERGENCE_EPIC_FILE" || -n "$SWARM_CONVERGENCE_ISSUES_FILE" ]]; then
        echo "Error: --export-file requires --epic and cannot be combined with --epic-file or --issues-file" >&2
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
    local child_ids_json="${3:-}"
    local export_epic_id="${4:-}"

    # Consume the entire stream before emitting anything, but retain only the
    # selected records for JSONL. A malformed suffix or incomplete envelope
    # must fail even when it contains no children relevant to this epic.
    "$jq_bin" -n --arg kind "$kind" --arg export_epic_id "$export_epic_id" \
        --slurpfile child_ids <(printf '%s\n' "$child_ids_json") '
        def invalid($message): error($kind + " input: " + $message);
        def objects: type == "array" and all(.[]; type == "object");
        def relation_id: .id // .issue_id // .depends_on_id // "";
        def native_children:
            . as $epic
            | (reduce ($epic.dependencies // [])[] as $dep ({};
                ($dep | relation_id) as $id
                | if ($id | type) == "string" then .[$id] = true else . end)) as $known
            | reduce ($epic.dependents // [])[] as $dep
                ({out:($epic.dependencies // []), seen:$known};
                # Incoming blockers and related issues are not epic children.
                # Preserve legacy dependency order/overrides, including its
                # duplicate semantics; only newly discovered children dedupe.
                if $dep.dependency_type == "parent-child" then
                    ($dep | relation_id) as $id
                    | if ($id | type) != "string" or $id == "" then
                        invalid("parent-child dependent must have a non-empty string ID")
                      elif $id == $epic.id then
                        invalid("epic cannot be its own parent-child dependent")
                      elif .seen[$id] == true then .
                      else .out += [$dep] | .seen[$id] = true end
                else . end)
            | $epic + {dependencies:.out};
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
        def jsonl_record:
            if type == "object" and (.id | type) == "string" then [.]
            else invalid("expected an issue array, issues wrapper, or JSONL issue objects") end;
        (reduce $child_ids[0][]? as $id ({};
            if ($id | type) == "string" then .[$id] = true else . end)) as $wanted
        | def selected:
            if ($child_ids | length) == 0 then .
            else map(select(.id as $id |
                if ($id | type) == "string" then $wanted[$id] == true
                else ($child_ids[0] | index($id)) != null end)) end;
        # Raw Beads exports carry outgoing edges with issue_id as the source,
        # not the target. br show expands those edges and adds dependents.
        # Reconstruct that view only for the explicit export mode; do not
        # reinterpret the existing --epic-file dependency aliases.
        def export_record:
            if (.id | type) != "string" or .id == "" then
                invalid("export records must have non-empty string IDs")
            elif .dependencies != null and (.dependencies | objects | not) then
                invalid("export dependencies must be an array of objects")
            else . end
            | . as $issue
            | .dependencies = [(.dependencies // [])[] |
                if any([.type, .dependency_type][];
                       . != null and (type != "string" or . == "")) then
                    invalid("export dependency type must be a non-empty string")
                else . end
                |
                if has("depends_on_id") then
                    if (.depends_on_id | type) != "string" or .depends_on_id == "" or
                       (.issue_id != null and .issue_id != $issue.id) then
                        invalid("export dependency has an invalid target or mismatched source")
                    else . + {id:.depends_on_id, dependency_type:(.type // .dependency_type)} end
                else . end];
        def accumulate($records):
            if $kind != "export" then .out += ($records | selected)
            else reduce $records[] as $record (.;
                ($record | export_record) as $issue
                | if .seen[$issue.id] then
                    if $issue.id == $export_epic_id then invalid("duplicate epic ID in export") else . end
                  else
                    .seen[$issue.id] = true
                    | if $issue.id == $export_epic_id then .epic = $issue else . end
                    | if any($issue.dependencies[];
                             .id == $export_epic_id and .dependency_type == "parent-child") then
                        if $issue.id == $export_epic_id then invalid("epic cannot be its own child")
                        else .out += [{id:$issue.id, title:$issue.title, status:$issue.status,
                                       priority:$issue.priority, dependency_type:"parent-child"}] end
                      else . end
                  end)
            end;
        if $kind == "issues" or $kind == "export" then
            # Defer the first value until the next value or EOF distinguishes
            # a single array/wrapper from JSONL. JSONL issue records may have
            # an unrelated field called "issues"; preserve that distinction.
            reduce inputs as $value ({count:0, first:null, out:[], seen:{}, epic:null};
                if .count == 0 then .first = $value
                else
                    (if .count == 1 then
                        (.first | jsonl_record) as $first
                        | accumulate($first) | .first = null
                     else . end)
                    | ($value | jsonl_record) as $next
                    | accumulate($next)
                end
                | .count += 1)
            | if .count == 1 then
                (.first
                | (if type == "array" or (type == "object" and has("issues")) then object_list
                   else jsonl_record end)) as $records
                | accumulate($records) | .first = null
              else . end
            | if $kind == "export" then
                if .epic == null then invalid("epic ID not found in export: " + $export_epic_id)
                elif .epic.dependents != null and (.epic.dependents | objects | not) then
                    invalid("dependents must be an array of objects")
                else .epic + {dependents:((.epic.dependents // []) + .out)} end
              else .out end
        else [inputs]
        | if $kind == "epic" then
            if length != 1 then invalid("expected exactly one JSON value")
            else .[0]
                | (if type == "array" then .[0] else . end) as $epic
                | if ($epic | type) != "object" then
                    invalid("expected an epic object or a non-empty array of epic objects")
                  elif ($epic.dependencies != null and ($epic.dependencies | objects | not)) then
                    invalid("dependencies must be an array of objects")
                  elif ($epic.dependents != null and ($epic.dependents | objects | not)) then
                    invalid("dependents must be an array of objects")
                  elif ($epic.acceptance_criteria != null and ($epic.acceptance_criteria | type) != "string") then
                    invalid("acceptance_criteria must be a string")
                  elif ($epic.success_criteria != null and
                        ($epic.success_criteria | (type == "array" and all(.[]; type == "string")) | not)) then
                    invalid("success_criteria must be an array of strings")
                  else
                    # Normalize once so issue selection, commit collection and
                    # scoring all use the same augmented graph. Keep the first
                    # epic selection convention for array-form br show output.
                    ($epic | native_children) as $normalized
                    | if type == "array" then .[0] = $normalized else $normalized end
                  end
            end
        else
            if length != 1 then invalid("expected exactly one JSON value")
            else .[0] | object_list end
        end
        end
    '
}

swarm_convergence_read_json_or_jsonl() {
    local jq_bin="$1"
    local path="$2"
    local child_ids_json="${3:-}"

    [[ -f "$path" ]] || {
        echo "Error: file not found: $path" >&2
        return 2
    }

    swarm_convergence_normalize_json "$jq_bin" issues "$child_ids_json" < "$path"
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

swarm_convergence_collect_detail_batch() {
    local jq_bin="$1" br_bin="$2"
    shift 2

    # Only a byte/count-bounded set of IDs goes in argv, never issue payloads.
    # The end-of-options marker prevents an ID from becoming a br option.
    "$br_bin" show --json --no-auto-import --no-auto-flush -- "$@" \
        | swarm_convergence_normalize_json "$jq_bin" issues \
        | "$jq_bin" -c --rawfile requested <(printf '%s\n' "$@") '
            ($requested | split("\n")[:-1] | sort) as $ids
            | if (map(.id) | sort) != $ids then
                error("live child details: missing, duplicate, or unexpected issue IDs")
              elif any(.[]; .comments != null and
                   (.comments | (type == "array" and all(.[];
                       type == "object" and (.text | type) == "string")) | not)) then
                error("live child details: comments must be objects with string text")
              else .[] end
        '
}

swarm_convergence_collect_live_details() {
    local jq_bin="$1" br_bin="$2" issues_json="$3"
    local ids_text="" id="" bytes=0
    local -a batch=()
    # Bash length must measure bytes, including under UTF-8 user locales.
    local LC_ALL=C

    # Validate the complete selected ID set before executing any detail read.
    # Reject line/NUL delimiters and individually oversized IDs explicitly.
    ids_text="$("$jq_bin" -r '
        def valid_id:
            if type == "string" then
                length > 0 and utf8bytelength <= 16384 and
                (test("[\u0000-\u001f\u007f]") | not)
            else false end;
        if all(.[]; .id | valid_id) then map(.id) | unique[]
        else error("live child details: IDs must be non-empty strings without control characters, at most 16384 bytes") end
    ' <<< "$issues_json")" || return $?
    [[ -n "$ids_text" ]] || return 0

    while IFS= read -r id; do
        if (( ${#batch[@]} >= 128 || bytes + ${#id} + 1 > 32768 )); then
            swarm_convergence_collect_detail_batch "$jq_bin" "$br_bin" "${batch[@]}" || return $?
            batch=()
            bytes=0
        fi
        batch+=("$id")
        bytes=$((bytes + ${#id} + 1))
    done <<< "$ids_text"
    if (( ${#batch[@]} > 0 )); then
        swarm_convergence_collect_detail_batch "$jq_bin" "$br_bin" "${batch[@]}" || return $?
    fi
    return 0
}

swarm_convergence_collect_issues_json() {
    local jq_bin="$1"
    local epic_json="$2"
    local br_bin=""
    local child_ids_json=""
    local listed_json=""

    child_ids_json="$(swarm_convergence_child_ids_json "$jq_bin" "$epic_json")" || return $?
    if [[ -n "$SWARM_CONVERGENCE_ISSUES_FILE" ]]; then
        swarm_convergence_read_json_or_jsonl "$jq_bin" "$SWARM_CONVERGENCE_ISSUES_FILE" "$child_ids_json"
        return $?
    fi

    if [[ -f ".beads/issues.jsonl" ]]; then
        swarm_convergence_read_json_or_jsonl "$jq_bin" .beads/issues.jsonl "$child_ids_json"
        return $?
    fi

    br_bin="$(swarm_convergence_binary_path br 2>/dev/null || true)"
    [[ -n "$br_bin" ]] || {
        printf '[]\n'
        return 0
    }
    # The default work queue hides closed/deferred issues. Auditing an epic
    # needs their evidence too, without any version-dependent result limit.
    listed_json="$("$br_bin" list --json --all --deferred --limit 0 --no-auto-import --no-auto-flush \
        | swarm_convergence_normalize_json "$jq_bin" issues "$child_ids_json")" || return $?

    # br list supplies labels and counts, but does not hydrate comments. A
    # child whose only verification is a comment must audit exactly as it does
    # from a full export. Keep list order/duplicates/fields; enrich comments
    # only, without silently accepting missing or stale detail responses.
    swarm_convergence_collect_live_details "$jq_bin" "$br_bin" "$listed_json" \
        | "$jq_bin" -s --slurpfile listed <(printf '%s\n' "$listed_json") '
            (reduce .[] as $detail ({}; .[$detail.id] = $detail)) as $details
            | $listed[0] | map(
                $details[.id] as $detail
                | if $detail == null then
                    error("live child details: missing issue " + .id)
                  elif .updated_at != null and $detail.updated_at != null and
                       .updated_at != $detail.updated_at then
                    error("live child details: issue changed during collection: " + .id + "; retry the audit")
                  else . + {comments: ($detail.comments // [])} end)
        '
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
    # %s is a single line, whereas arbitrary control-character delimiters may
    # occur inside the subject itself. Split only after the full object ID.
    # Suppress config-dependent extra output (notably notes and signatures).
    # Consume history one line at a time and retain only matching evidence;
    # unrelated history must not be slurped into a second in-memory copy.
    "$git_bin" log --format='%H %s' --all --no-show-signature --no-notes \
        --no-patch --color=never --no-decorate --encoding=UTF-8 \
        | "$jq_bin" -R -n --slurpfile child_ids <(printf '%s\n' "$child_ids_json") '
            def bead_id_in_subject($id; $subject):
                ($id | tostring) as $needle
                | ($subject | tostring) as $body
                | ($needle | length) as $width
                | any($body | indices($needle)[]?;
                    . as $offset
                    | ($body[$offset - 1:$offset] // "") as $before
                    | ($body[$offset + $width:$offset + $width + 1] // "") as $after
                    | (($offset == 0) or ($before | test("[A-Za-z0-9._-]") | not))
                      and (($offset + $width == ($body | length)) or
                           ($after | test("[A-Za-z0-9._-]") | not)));
            [inputs
             | index(" ") as $end
             | if (($end == 40 or $end == 64) and
                   (.[:$end] | test("^[0-9a-f]+$"))) then
                 {hash: .[:$end], subject: .[$end + 1:]}
               else error("commits input: malformed git log record") end
             | select(.subject as $subject |
                 any($child_ids[0][]; . as $id | bead_id_in_subject($id; $subject)))]
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
def child_ids:
  [arr(epic_doc.dependencies)[]?
   | (.id // .issue_id // .depends_on_id // "") | select(. != "")];
def issue_index:
  (reduce child_ids[] as $id ({};
    if ($id | type) == "string" then .[$id] = true else . end)) as $wanted
  | reduce issue_list[]? as $issue ({};
      if ($issue.id | type) == "string" then
        if $wanted[$issue.id] == true and (has($issue.id) | not) then
          .[$issue.id] = $issue
        else . end
      else . end);
def issue_for($id; $index):
  # Preserve first-record-wins for duplicate IDs, and the existing equality
  # behavior for non-string legacy IDs without putting them in object keys.
  if ($id | type) == "string" then $index[$id] // {}
  else first(issue_list[]? | select(.id == $id)) // {} end;
def bead_id_in_subject($id; $subject):
  ($id | tostring) as $needle
  | ($subject | tostring) as $body
  | ($needle | length) as $width
  | any($body | indices($needle)[]?;
      . as $offset
      | ($body[$offset - 1:$offset] // "") as $before
      | ($body[$offset + $width:$offset + $width + 1] // "") as $after
      | (($offset == 0) or ($before | test("[A-Za-z0-9._-]") | not))
        and (($offset + $width == ($body | length)) or
             ($after | test("[A-Za-z0-9._-]") | not)));
def commits_for($id): [commit_list[]? | select(bead_id_in_subject($id; (.subject // "")))];

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

def criteria_from_acceptance($body):
  # Beads stores free-form Markdown, not a success_criteria array. Extract
  # lists/checklists without interpreting a checked box as verification.
  # Fenced examples are not requirements; preserve marker/length rules so
  # a shorter fence or one with trailing text cannot end an example early.
  (text($body) | gsub("\r\n"; "\n") | split("\n")) as $lines
  | reduce $lines[] as $line
      ({fence:"", width:0, items:[], prose:[], continuation:false};
      ($line | capture("^[ \\t]*(?<marker>`{3,}|~{3,})(?<tail>.*)$")? // null) as $f
      | if .fence != "" then
          if $f != null and ($f.marker[:1] == .fence) and
             ($f.marker | length) >= .width and ($f.tail | test("^[ \\t]*$")) then
            .fence = "" | .width = 0
          else . end
        elif $f != null and ($f.marker[:1] != "`" or ($f.tail | contains("`") | not)) then
          .fence = $f.marker[:1] | .width = ($f.marker | length)
        elif ($line | test("^[ \\t]*#{1,6}[ \\t]+")) then .continuation = false
        elif ($line | test("^[ \\t]*([-*+][ \\t]+|[0-9]+[.)][ \\t]+)")) then
          ($line | sub("^[ \\t]*([-*+][ \\t]+|[0-9]+[.)][ \\t]+)"; "")
                 | sub("^\\[[ xX]\\][ \\t]*"; "")
                 | sub("[ \\t\\r]+$"; "")) as $item
          | if $item != "" then .items += [$item] | .continuation = true
            else .continuation = false end
        elif ($line | test("^[[:space:]]*$")) then .continuation = false
        elif .continuation and ($line | test("^[ \\t]+")) then
          .items[-1] += (" " + ($line | sub("^[ \\t]+"; "") | sub("[ \\t\\r]+$"; "")))
        else .prose += [$line] | .continuation = false end)
  | if (.items | length) > 0 then .items
    else (.prose | join("\n") | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "")) as $prose
         | if $prose == "" then [] else [$prose] end
    end;

def criteria:
  if (epic_doc.success_criteria | type) == "array" then epic_doc.success_criteria
  else criteria_from_description(epic_doc.description) as $legacy
       | if ($legacy | length) > 0 then $legacy
         else criteria_from_acceptance(epic_doc.acceptance_criteria) end
  end;

def child_issues($index):
  [arr(epic_doc.dependencies)[]?
   | (.id // .issue_id // .depends_on_id // "") as $id
   | select($id != "")
   | (issue_for($id; $index)) as $issue
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

def proofy($body):
  ($body | test("test|tests|artifact|artifacts|commit|evidence|passed|coverage|logs|fixture|support-bundle|dashboard|report|verified|verification"));

def match_score($terms; $body):
  [$terms[] | . as $term | select($body | contains($term))] | unique | length;

def criterion_report($criterion; $position; $children):
  [$children[] | . as $c | ._scores[$position] as $score | select($score > 0) | $c + {match_score: $score}] as $matches
  | [$matches[] | select(.status == "closed")] as $closed
  | [$matches[] | select(.status != "closed")] as $open
  | [$closed[] | select(._proofy)] as $strong
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

# Build the graph/evidence once, not once per criterion plus every summary.
# Cache each criterion-child score for both evidence and over-broad accounting.
# Only the explicit report projections below are emitted; caches stay internal.
(criteria | map({criterion: ., terms: tokens(.)})) as $criteria
| issue_index as $index
| [child_issues($index)[] | . as $child | child_text($child) as $body
   | $child + {
       _proofy: proofy($body),
       _scores: [$criteria[] | match_score(.terms; $body)]
     }] as $children
| ($criteria | to_entries | map(criterion_report(.value.criterion; .key; $children))) as $criteria_reports
| [$children[] as $child | select($child._scores | max <= 0) | {
    bead_id: $child.id,
    title: safe_title($child.title),
    status: $child.status
  }] as $over_broad
| {
    schema_version: 1,
    status: (if ($criteria_reports | length) == 0 or any($criteria_reports[]; .status == "missing") then "warn" else "pass" end),
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
      child_beads: ($children | length),
      over_broad_children: ($over_broad | length)
    },
    criteria: $criteria_reports,
    over_broad_children: $over_broad,
    suggested_bead_titles: (if ($criteria_reports | length) == 0 then
      ["Define acceptance criteria for epic: " + safe_title(epic_doc.id // $epic_id)]
      else [$criteria_reports[] | .suggested_bead_title // empty] end)
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
      (if .summary.criteria_total == 0 then
        "No auditable criteria found. Add success_criteria, a Success criteria description section, or acceptance_criteria.",
        ("Suggested follow-up: `" + .suggested_bead_titles[0] + "`")
       else empty end),
      (.criteria[] | "### \(.status | ascii_upcase)\n\(.criterion)\n\nEvidence:\n" + (if (.evidence | length) == 0 then "- None" else (.evidence | map("- `\(.bead_id)` \(.status): \(.title)") | join("\n")) end) + (if .suggested_bead_title then "\n\nSuggested follow-up: `" + .suggested_bead_title + "`" else "" end)),
      "",
      "## Over-Broad Children",
      (if (.over_broad_children | length) == 0 then "- None" else (.over_broad_children[] | "- `\(.bead_id)` \(.status): \(.title)") end)
    ' <<< "$report"
}

swarm_convergence_main() (
    local parse_status=0
    local jq_bin=""
    local epic_json=""
    local issues_json=""
    local commits_json=""
    local report=""
    local export_dir=""

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

    if [[ -n "$SWARM_CONVERGENCE_EXPORT_FILE" ]]; then
        [[ -f "$SWARM_CONVERGENCE_EXPORT_FILE" ]] || {
            echo "Error: export file not found: $SWARM_CONVERGENCE_EXPORT_FILE" >&2
            return 2
        }
        # Both passes must read the same captured bytes, not a changing file or
        # different databases. Keep bulk data on disk, in a private directory.
        # The subshell scopes cleanup without replacing a callers EXIT trap.
        export_dir="$(mktemp -d "${TMPDIR:-/tmp}/acfs-convergence-export.XXXXXXXX")" || {
            echo "Error: cannot create private export workspace" >&2
            return 2
        }
        trap 'rm -f -- "$export_dir/issues.json"; rmdir -- "$export_dir"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        umask 077
        cat -- "$SWARM_CONVERGENCE_EXPORT_FILE" > "$export_dir/issues.json" || {
            echo "Error: failed to capture export input" >&2
            return 2
        }
        SWARM_CONVERGENCE_ISSUES_FILE="$export_dir/issues.json"
        epic_json="$(swarm_convergence_normalize_json "$jq_bin" export "" "$SWARM_CONVERGENCE_EPIC_ID" \
            < "$SWARM_CONVERGENCE_ISSUES_FILE" | swarm_convergence_normalize_json "$jq_bin" epic)" || {
            echo "Error: failed to resolve epic from export" >&2
            return 2
        }
    else
        epic_json="$(swarm_convergence_collect_epic_json | swarm_convergence_normalize_json "$jq_bin" epic)" || {
            echo "Error: failed to read epic input" >&2
            return 2
        }
    fi
    issues_json="$(swarm_convergence_collect_issues_json "$jq_bin" "$epic_json")" || {
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
)

swarm_convergence_main "$@"
