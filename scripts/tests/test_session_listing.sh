#!/usr/bin/env bash
# Deterministic CASS discovery regressions; no live archive or network required.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
command -v jq >/dev/null || { printf 'jq is required\n' >&2; exit 1; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/acfs-session-list-test.XXXXXX")
# Retain diagnostics, including failed command output, for reproducibility.
printf 'Session listing test artifacts: %s\n' "$WORK" >&2
_ACFS_LOGGING_SH_LOADED=1
log_error() { printf 'ERROR: %s\n' "$*" >&2; }
log_info() { printf '%s\n' "$*" >&2; }
# shellcheck source=../lib/session.sh
source "${ACFS_SESSION_TEST_LIB:-$ROOT/scripts/lib/session.sh}"
session_now_iso() { printf '%s\n' '2026-10-15T12:00:00Z'; }
MODE=normal
check_cass_installed() { [[ "$MODE" != missing_cass ]]; }
# Keep fixture time independent of the system clock.
cat > "$WORK/hits.json" <<'JSON'
[
 {"source_path":"/recent/a","agent":"codex","workspace":"/project/a","created_at":1792065599000},
 {"source_path":"/recent/a","agent":"codex","workspace":"/project/a","created_at":1792065598000},
 {"source_path":"/recent/a","agent":"codex","workspace":"/project/a","created_at":1792065597000},
 {"source_path":"/recent/b","agent":"claude_code","workspace":"/project/b","created_at":1792065596000},
 {"source_path":"/recent/b","agent":"claude_code","workspace":"/project/b","created_at":1792065595000},
 {"source_path":"/recent/c","agent":"codex","workspace":"/project/a","created_at":1792065594000},
 {"source_path":"/recent/d","agent":"codex","workspace":"/project/d","created_at":1792065593000},
 {"source_path":"/historical","agent":"codex","workspace":"/old","created_at":1791892800000},
 {"source_path":"/future","agent":"codex","workspace":"/future","created_at":1792152000000}
]
JSON
cass() {
    { printf '%q ' "$@"; printf '\n'; } >> "$WORK/calls"
    [[ "${1:-}" == search && "${2:-}" == '*' ]] || return 91
    shift 2
    local days=30 limit=20 agent='' since='' until='' cursor='' fields='' meta=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --days) days=$2; shift 2 ;;
            --limit) limit=$2; shift 2 ;;
            --agent) agent=$2; shift 2 ;;
            --since) since=$2; shift 2 ;;
            --until) until=$2; shift 2 ;;
            --cursor) cursor=$2; shift 2 ;;
            --fields) fields=$2; shift 2 ;;
            --robot-meta) meta=true; shift ;;
            --json) shift ;;
            *) printf 'Unexpected CASS option: %s\n' "$1" >&2; return 92 ;;
        esac
    done
    local offset=0
    if [[ -n "$cursor" ]]; then
        [[ "$cursor" =~ ^page:([0-9]+):opaque[[:space:]]token\*$ ]] || return 93
        offset=${BASH_REMATCH[1]}
    fi
    # These assertions exercise argv forwarding rather than trusting headings.
    if [[ "$MODE" == check_contract ]]; then
        [[ "$meta" == true && "$fields" == source_path,source_id,conversation_id,agent,workspace,created_at,title && "$since" == '2026-10-14T12:00:00Z' && "$until" == '2026-10-15T12:00:00Z' ]] || return 94
        [[ "$agent" == codex ]] || return 95
    fi
    case "$MODE:$offset" in
        failed:*) printf '{"hits":[]}\n'; return 42 ;;
        late_failed:3) printf '{"hits":[]}\n'; return 42 ;;
        malformed:*) printf '%s' "$BAD_RESPONSE"; return 0 ;;
        late_malformed:3) printf '%s' "$BAD_RESPONSE"; return 0 ;;
        canonical_conflict:0)
            printf '%s\n' '{"hits":[{"source_path":"/recent/a","source_id":"local","conversation_id":41,"agent":"codex","workspace":"/p"}],"_meta":{"next_cursor":"page:3:opaque token*"}}'
            return 0 ;;
        canonical_conflict:3) printf '%s' "$BAD_RESPONSE"; return 0 ;;
        unending:*) printf '{"hits":[],"_meta":{"next_cursor":"page:%s:opaque token*"}}\n' "$((offset + 3))"; return 0 ;;
        canonical:*)
            # Two conversations share a provider store. Repeated message hits,
            # including across pages, must not consume the session limit.
            jq -cn --argjson offset "$offset" '
                [{source_path:"/shared/store.db",source_id:"local",conversation_id:41,agent:"codex",workspace:"/p"},
                 {source_path:"/shared/store.db",source_id:"local",conversation_id:41,agent:"codex",workspace:"/p"},
                 {source_path:"/shared/store.db",source_id:"local",conversation_id:42,agent:"codex",workspace:"/p"},
                 {source_path:"/shared/store.db",source_id:"local",conversation_id:42,agent:"codex",workspace:"/p"},
                 {source_path:"/shared/store.db",source_id:"remote",conversation_id:41,agent:"codex",workspace:"/remote"},
                 {source_path:"/unselected",source_id:"local",conversation_id:99,agent:"codex",workspace:"/other"}] |
                {hits:.[$offset:($offset+3)],_meta:{next_cursor:(if $offset == 0 then "page:3:opaque token*" else null end)}}'
            return 0 ;;
    esac
    local response
    response=$(jq -c --argjson limit "$limit" --argjson offset "$offset" \
        --arg days "$days" --arg since "$since" --arg until "$until" --arg agent "$agent" '
        ("2026-10-15T12:00:00Z" | fromdateiso8601) as $clock |
        ((if $since == "" then $clock - ($days|tonumber)*86400 else ($since|fromdateiso8601) end)*1000) as $start |
        ((if $until == "" then $clock else ($until|fromdateiso8601) end)*1000) as $end |
        map(select(.created_at >= $start and .created_at <= $end and ($agent == "" or .agent == $agent))) as $all |
        ($all[$offset:($offset + ([3, $limit] | min))]) as $hits |
        ($offset + ($hits|length)) as $next |
        {hits:$hits, count:($hits|length), total_matches:($all|length),
         _meta:{next_cursor:(if $next < ($all|length) then "page:\($next):opaque token*" else null end)}}
    ' "$WORK/hits.json") || return 96
    if [[ "$MODE" == cycle && "$offset" -gt 0 ]]; then
        response=$(jq -c '._meta.next_cursor = "page:3:opaque token*"' <<< "$response")
    elif [[ "$MODE" == empty_page && "$offset" == 3 ]]; then
        response=$(jq -c '.hits=[] | .count=0' <<< "$response")
    elif [[ "$MODE" == provenance ]]; then
        response='{"hits":[{"source_path":"/same","agent":"codex","workspace":"/p"},{"source_path":"/same","source_id":"remote","agent":"codex","workspace":"/p"}],"_meta":{"next_cursor":null}}'
    fi
    printf '%s\n' "$response"
}
passed=0
failed=0
assert() {
    local label=$1
    shift
    if "$@"; then
        passed=$((passed + 1))
    else
        printf 'FAIL: %s\n' "$label" >&2
        failed=$((failed + 1))
    fi
}
run_list() {
    : > "$WORK/calls"
    STATUS=0
    list_sessions "$@" > "$WORK/stdout" 2> "$WORK/stderr" || STATUS=$?
}
json_is() { jq -e "$1" "$WORK/stdout" >/dev/null; }
no_success() { [[ "$STATUS" -ne 0 && ! -s "$WORK/stdout" ]]; }

run_list --days 1 --limit 3 --json
assert 'reported request succeeds' test "$STATUS" -eq 0
assert 'limit counts distinct sessions across pages' json_is '.total == 3 and [.sessions[].source_path] == ["/recent/a","/recent/b","/recent/c"]'
assert 'counts describe listed sessions only' json_is '.by_agent == [{agent:"claude_code",count:1},{agent:"codex",count:2}] and .by_workspace == [{workspace:"/project/a",count:2},{workspace:"/project/b",count:1}]'
assert 'traversal actually requests a later page' grep -q -- '--cursor' "$WORK/calls"
cp "$WORK/stdout" "$WORK/listing.json"
run_list --days 1 --limit 3
assert 'text request succeeds' test "$STATUS" -eq 0
for path in /recent/a /recent/b /recent/c; do
    assert "text includes JSON session $path" grep -Fq "$path" "$WORK/stdout"
done
assert 'text has no historical or future sessions' bash -c '! grep -Eq "/historical|/future|/recent/d" "$1"' _ "$WORK/stdout"
assert 'text count matches JSON' grep -q 'Listed Sessions: 3' "$WORK/stdout"

MODE=check_contract
run_list --days 1 --limit 3 --agent codex --json
assert 'every page keeps the same time window and agent' test "$STATUS" -eq 0
assert 'agent filtering precedes unique session limit' json_is '[.sessions[].source_path] == ["/recent/a","/recent/c","/recent/d"]'
MODE=normal
run_list --days 3 --limit 10 --json
assert 'wider date window includes history but not future' json_is '.total == 5 and any(.sessions[]; .source_path == "/historical") and all(.sessions[]; .source_path != "/future")'
run_list --days 1 --limit 10 --agent claude_code --json
assert 'exhaustion returns fewer sessions honestly' json_is '.total == 1 and .query_info.exhausted == true'
run_list --days 1 --limit 3 --agent absent --json
assert 'empty JSON is a successful empty listing' json_is '.total == 0 and .sessions == [] and .by_agent == [] and .by_workspace == []'
run_list --days 1 --limit 3 --agent absent
assert 'empty text is explicit' grep -q 'No matching sessions' "$WORK/stdout"
MODE=provenance
run_list --json
assert 'identical paths on different sources stay distinct' json_is '.total == 2'
assert 'missing canonical IDs remain explicit, not invented' json_is 'all(.sessions[]; .conversation_id == null and .identity_kind == "source_path")'
MODE=canonical
run_list --days 1 --limit 3 --json
assert 'canonical discovery succeeds' test "$STATUS" -eq 0
assert 'same-path canonical conversations remain distinct across pages' json_is '.total == 3 and [.sessions[] | [.source_id,.conversation_id]] == [["local",41],["local",42],["remote",41]]'
assert 'canonical coordinates survive discovery without path rewriting' json_is 'all(.sessions[]; .source_path == "/shared/store.db" and .identity_kind == "canonical")'
assert 'canonical identity determines aggregate counts' json_is '.by_agent == [{agent:"codex",count:3}] and .by_workspace == [{workspace:"/p",count:2},{workspace:"/remote",count:1}]'
assert 'canonical discovery continues past duplicate-heavy first page' test "$(wc -l < "$WORK/calls")" -eq 2
run_list --days 1 --limit 3
assert 'text distinguishes first local conversation' grep -Fq 'source="local" | conversation=41' "$WORK/stdout"
assert 'text distinguishes second local conversation' grep -Fq 'source="local" | conversation=42' "$WORK/stdout"
assert 'text distinguishes remote conversation with same path and ID' grep -Fq 'source="remote" | conversation=41' "$WORK/stdout"
assert 'canonical text and JSON agree on total' grep -q 'Listed Sessions: 3' "$WORK/stdout"
run_list --days 1 --limit 1 --json
assert 'session limit still caps canonical discovery' json_is '.total == 1 and .sessions[0].conversation_id == 41'
assert 'satisfied canonical limit does not fetch another page' test "$(wc -l < "$WORK/calls")" -eq 1

# Identity changes within or between pages cannot silently relabel a session.
# Include an id-less hit mixed with a canonical one for the same source/path;
# there is no sound basis to call those one session or two.
for conflict in '{"workspace":"/changed"}' '{"agent":"other"}' '{"source_path":"/changed"}' '{"conversation_id":null}'; do
    BAD_RESPONSE=$(jq -cn --argjson conflict "$conflict" '
        {source_path:"/recent/a",source_id:"local",conversation_id:41,agent:"codex",workspace:"/p"} as $hit |
        {hits:[$hit,($hit + $conflict)],_meta:{next_cursor:null}}')
    for MODE in malformed canonical_conflict; do
        if [[ "$MODE" == canonical_conflict ]]; then
            BAD_RESPONSE=$(jq -c '.hits = [.hits[1]]' <<< "$BAD_RESPONSE")
        fi
        for format in text json; do
            args=(--days 1 --limit 10)
            [[ "$format" == text ]] || args+=(--json)
            run_list "${args[@]}"
            assert "$MODE/$format rejects conflicting canonical identity $conflict" no_success
            if [[ "$conflict" == *conversation_id* ]]; then
                assert 'ambiguous identity has an explicit diagnostic' grep -q 'ambiguous CASS session identity' "$WORK/stderr"
            else
                assert 'identity drift has an explicit diagnostic' grep -q 'conflicting CASS session identity' "$WORK/stderr"
            fi
        done
    done
done
for bad_id in 'false' '0' '-1' '1.5' '"41"' '[]' '{}' '9007199254740992' '9007199254740993'; do
    BAD_RESPONSE='{"hits":[{"source_path":"/a","source_id":"local","conversation_id":'"$bad_id"',"agent":"codex","workspace":"/p"}],"_meta":{"next_cursor":null}}'
    MODE=malformed
    run_list --json
    assert "invalid or imprecise canonical ID $bad_id fails without output" no_success
done
MODE=malformed
BAD_RESPONSE='{"hits":[{"source_path":"/a","conversation_id":9007199254740991,"agent":"codex","workspace":"/p"}],"_meta":{"next_cursor":null}}'
run_list --json
assert 'largest exactly supported canonical ID is preserved' json_is '.sessions[0].conversation_id == 9007199254740991'
BAD_RESPONSE='{"hits":[{"source_path":"/shared","agent":"codex","workspace":"/p"},{"source_path":"/shared","agent":"claude_code","workspace":"/p"}],"_meta":{"next_cursor":null}}'
run_list --json
assert 'path-only identity cannot merge different agent stores' json_is '.total == 2 and all(.sessions[]; .identity_kind == "source_path")'
BAD_RESPONSE='{"hits":[{"source_path":"/shared","agent":"codex","workspace":"/p"},{"source_path":"/shared","conversation_id":41,"agent":"codex","workspace":"/p"}],"_meta":{"next_cursor":null}}'
run_list --json
assert 'path-only followed by canonical identity is also refused' no_success
BAD_RESPONSE=$(jq -cn '{hits:[{source_path:"/p\nforged row",source_id:"remote\u001b[2J",conversation_id:41,agent:"code\tx",workspace:"/p\nforged summary"}],_meta:{next_cursor:null}}')
run_list --json
assert 'JSON preserves the exact canonical path and source' json_is '.sessions[0].source_path == "/p\nforged row" and .sessions[0].source_id == "remote\u001b[2J"'
run_list
assert 'text safely quotes multiline paths without inventing rows' grep -Fq '/p\nforged row' "$WORK/stdout"
assert 'text safely quotes control characters in source names' grep -Fq 'source="remote\u001b[2J"' "$WORK/stdout"
assert 'text never emits raw escape or tab bytes from metadata' bash -c '! LC_ALL=C grep -qE "$2" "$1"' _ "$WORK/stdout" $'\033|\t'
# Accumulated identities exceed Linux single-argument limits. Keep the actual
# library and real jq in this check, not a reimplementation of the reducer.
BAD_RESPONSE=$(jq -cn '{hits:[range(1;1201) | {source_path:("/shared/" + ("x" * 180)),source_id:"local",conversation_id:.,agent:"codex",workspace:"/p"}],_meta:{next_cursor:null}}')
run_list --limit 1200 --json
assert 'large canonical metadata stays off argv and retains every ID' json_is '.total == 1200 and [.sessions[].conversation_id] == [range(1;1201)]'
MODE=empty_page
run_list --days 1 --limit 10 --json
assert 'an empty page with a fresh cursor does not imply exhaustion' json_is '.total == 2 and [.sessions[].source_path] == ["/recent/a","/recent/d"]'
MODE=cycle
run_list --days 1 --limit 10 --json
assert 'cursor cycles fail without partial success' no_success
MODE=unending
run_list --days 1 --limit 10 --json
assert 'ever-changing cursors cannot cause an unbounded scan' no_success
assert 'scan bound produces an actionable diagnostic' grep -q 'exceeded 1000 CASS pages' "$WORK/stderr"
assert 'scan stops at the documented page bound' test "$(wc -l < "$WORK/calls")" -eq 1000

for MODE in failed late_failed; do
    for format in text json; do
        args=(--days 1 --limit 10)
        [[ "$format" == text ]] || args+=(--json)
        run_list "${args[@]}"
        assert "$MODE ($format) cannot publish partial success" no_success
    done
done
for BAD_RESPONSE in '' broken null '{}' '{"hits":{}}' \
    '{"hits":[],"_meta":{}}' '{"hits":[],"_meta":{"next_cursor":false}}' \
    '{"hits":[],"_meta":{"next_cursor":""}}' \
    '{"hits":[],"_meta":{"next_cursor":null},"error":"failed"}' \
    '{"hits":[],"_meta":{"next_cursor":null},"budget":{"timed_out":true}}' \
    '{"hits":[],"_meta":{"next_cursor":null,"timed_out":true}}' \
    '{"hits":[],"_meta":{"next_cursor":null,"partial_results":true}}' \
    '{"hits":[],"_meta":{"next_cursor":null},"budget":{"timed_out":"true"}}' \
    '{"hits":[{}],"_meta":{"next_cursor":null}}' \
    '{"hits":[{"source_path":"/a","agent":"codex","workspace":"/p","source_id":5}],"_meta":{"next_cursor":null}}' \
    '{"hits":[],"_meta":{"next_cursor":null}} {"hits":[]}'; do
    for MODE in malformed late_malformed; do
        for format in text json; do
            args=(--days 1 --limit 10)
            [[ "$format" == text ]] || args+=(--json)
            run_list "${args[@]}"
            assert "$MODE/$format rejects $BAD_RESPONSE" no_success
        done
    done
done
MODE=missing_cass
for format in text json; do
    args=()
    [[ "$format" == text ]] || args+=(--json)
    run_list "${args[@]}"
    assert 'unavailable CASS returns nonzero' test "$STATUS" -ne 0
done
MODE=normal
for option in --days --limit --agent; do
    run_list "$option"
    assert "missing $option is rejected before CASS" bash -c '[[ $1 != 0 && ! -s $2 ]]' _ "$STATUS" "$WORK/calls"
done
for option in --days --limit; do
    for value in 0 00 -1 1.5 nope; do
        run_list "$option" "$value"
        assert "invalid $option=$value fails before CASS" bash -c '[[ $1 != 0 && ! -s $2 ]]' _ "$STATUS" "$WORK/calls"
    done
done
run_list --bogus
assert 'unknown argument is rejected' no_success
run_list --limit 10001 --json
assert 'oversized limit is rejected before querying CASS' bash -c '[[ $1 != 0 && ! -s $2 ]]' _ "$STATUS" "$WORK/calls"
: > "$WORK/calls"
STATUS=0
(
    acfs_session_system_binary_path() { return 1; }
    list_sessions --json
) > "$WORK/stdout" 2> "$WORK/stderr" || STATUS=$?
assert 'missing trusted jq cannot produce a successful listing' no_success
assert 'missing jq prevents querying CASS' test ! -s "$WORK/calls"
# Failure handling must not rely on callers enabling pipefail.
set +o pipefail
MODE=late_failed
run_list --days 1 --limit 10 --json
assert 'later failure survives pipefail off' no_success
set -o pipefail
MODE=normal
if [[ -e /dev/full ]]; then
    STATUS=0
    list_sessions --json > /dev/full 2> "$WORK/stderr" || STATUS=$?
    assert 'output write failures propagate' test "$STATUS" -ne 0
fi
# Workspace/recent helpers must use CASS's first-class session enumeration.
cass() {
    { printf '%q ' "$@"; printf '\n'; } >> "$WORK/calls"
    [[ "${1:-}" == sessions && "${2:-}" == --workspace && "${4:-}" == --limit && "${6:-}" == --json ]] || return 97
    printf '%s\n' '{"sessions":[{"path":"/tmp/acfs-recent-session.jsonl","agent":"codex","workspace":"/project/a","source_id":"local","message_count":4},{"path":"/tmp/older.jsonl","agent":"codex","workspace":"/project/a","source_id":"local","message_count":2}]}'
}
: > "$WORK/calls"
STATUS=0
get_workspace_sessions "/project/a" 2 > "$WORK/stdout" 2> "$WORK/stderr" || STATUS=$?
assert 'workspace helper succeeds through native CASS sessions' test "$STATUS" -eq 0
assert 'workspace helper preserves native session payload' bash -c 'jq -e '\''(.sessions|length)==2 and .sessions[0].path=="/tmp/acfs-recent-session.jsonl"'\'' "$1" >/dev/null' _ "$WORK/stdout"
assert 'workspace helper never uses wildcard search' bash -c '! grep -q '\''search '\'' "$1"' _ "$WORK/calls"
assert 'workspace helper forwards workspace and session limit' grep -Fq 'sessions --workspace /project/a --limit 2 --json' "$WORK/calls"

cass() { printf '%s\n' '{"sessions":"not-an-array"}'; }
STATUS=0
get_workspace_sessions "/project/a" 2 > "$WORK/stdout" 2> "$WORK/stderr" || STATUS=$?
assert 'malformed native session JSON is rejected without stdout' no_success
cass() { printf '%s\n' '{"sessions":[]}'; }
STATUS=0
export_recent_session "/project/a" json > "$WORK/stdout" 2> "$WORK/stderr" || STATUS=$?
assert 'empty recent-session result fails without fabricated export' no_success

for value in 0 00 -1 1.5 nope 10001; do
    : > "$WORK/calls"
    STATUS=0
    get_workspace_sessions "/project/a" "$value" > "$WORK/stdout" 2> "$WORK/stderr" || STATUS=$?
    assert "invalid workspace limit $value is rejected before CASS" bash -c '[[ $1 != 0 && ! -s "$2" ]]' _ "$STATUS" "$WORK/calls"
done

recent_file="$WORK/recent export.jsonl"
printf '%s\n' '{"dummy":true}' > "$recent_file"
cass() {
    { printf '%q ' "$@"; printf '\n'; } >> "$WORK/calls"
    if [[ "${1:-}" == sessions ]]; then
        jq -cn --arg path "$recent_file" '{sessions:[{path:$path,agent:"codex",workspace:"/project/a",source_id:"local"}]}'
    elif [[ "${1:-}" == export ]]; then
        printf '%s\n' '[{"timestamp":"2026-10-15T12:00:00Z","type":"session_meta","payload":{"id":"native-recent","cwd":"/project/a","originator":"codex"}},{"timestamp":"2026-10-15T12:00:01Z","type":"event_msg","payload":{"type":"user_message","message":"hello"}},{"timestamp":"2026-10-15T12:00:02Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"reply"}]}}]'
    else
        return 98
    fi
}
: > "$WORK/calls"
STATUS=0
export_recent_session "/project/a" json > "$WORK/stdout" 2> "$WORK/stderr" || STATUS=$?
assert 'recent-session export succeeds from native session result' test "$STATUS" -eq 0
assert 'recent-session export called native sessions first' bash -c 'head -n1 "$1" | grep -Fq "sessions --workspace /project/a --limit 1 --json"' _ "$WORK/calls"
assert 'recent-session export uses the returned path verbatim' grep -Fq 'export '"$(printf '%q' "$recent_file")"' --format json' "$WORK/calls"

printf 'Session listing: %s assertions passed; %s failed\n' "$passed" "$failed"
[[ "$failed" == 0 ]]
