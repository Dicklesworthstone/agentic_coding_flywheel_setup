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
        [[ "$meta" == true && "$fields" == source_path,source_id,agent,workspace,created_at,title && "$since" == '2026-10-14T12:00:00Z' && "$until" == '2026-10-15T12:00:00Z' ]] || return 94
        [[ "$agent" == codex ]] || return 95
    fi
    case "$MODE:$offset" in
        failed:*) printf '{"hits":[]}\n'; return 42 ;;
        late_failed:3) printf '{"hits":[]}\n'; return 42 ;;
        malformed:*) printf '%s' "$BAD_RESPONSE"; return 0 ;;
        late_malformed:3) printf '%s' "$BAD_RESPONSE"; return 0 ;;
        unending:*) printf '{"hits":[],"_meta":{"next_cursor":"page:%s:opaque token*"}}\n' "$((offset + 3))"; return 0 ;;
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
printf 'Session listing: %s assertions passed; %s failed\n' "$passed" "$failed"
[[ "$failed" == 0 ]]
