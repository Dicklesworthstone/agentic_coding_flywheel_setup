#!/usr/bin/env bash
# Deterministic regressions for ACFS #456; no CASS installation or live index.
# Usage: bash tests/unit/test_session_list.sh [path/to/session.sh]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIBRARY="${1:-$ROOT/scripts/lib/session.sh}"
command -v jq >/dev/null || { printf 'jq is required\n' >&2; exit 1; }

# Isolate the listing contract from terminal colors and the caller logging setup.
_ACFS_LOGGING_SH_LOADED=1
log_error() { printf 'ERROR: %s\n' "$*" >&2; }
log_info() { printf '%s\n' "$*" >&2; }
# shellcheck source=../../scripts/lib/session.sh
source "$LIBRARY"

# Retain diagnostics in an isolated temporary directory (no repository cleanup).
WORK="$(mktemp -d "${TMPDIR:-/tmp}/acfs-session-list-tests.XXXXXX")"
CALL_FILE="$WORK/cass.argv"
STDOUT_FILE="$WORK/stdout"
STDERR_FILE="$WORK/stderr"
CLOCK_MS="$(jq -n '"2026-10-15T12:00:00Z" | fromdateiso8601 * 1000')"
FIXTURE="$(jq -n --argjson clock "$CLOCK_MS" '[
    {source_path:"/sessions/recent-a.jsonl", source_id:"local", agent:"claude_code", workspace:"/work/alpha project", title:"Recent A", created_at:($clock-1000)},
    {source_path:"/sessions/recent-b.jsonl", source_id:"local", agent:"codex", workspace:"/work/beta", title:"Recent B", created_at:($clock-2000)},
    {source_path:"/sessions/recent-c.jsonl", source_id:"local", agent:"codex", workspace:"/work/alpha project", title:"Recent C", created_at:($clock-3000)},
    {source_path:"/sessions/recent-d.jsonl", source_id:"local", agent:"gemini", workspace:"/work/gamma", title:"Beyond limit", created_at:($clock-4000)},
    {source_path:"/sessions/historical.jsonl", source_id:"local", agent:"codex", workspace:"/work/historical", title:"October 13", created_at:($clock-172800000)},
    {source_path:"/sessions/boundary.jsonl", source_id:"local", agent:"codex", workspace:"/work/boundary", title:"Just outside one day", created_at:($clock-86400001)}
]')"
MODE=fixture
REPLY=''

# This mock really applies filters to a fixed historical/recent corpus. The old
# stats path returns the reported all-time poison, rather than a helpful failure.
cass() {
    printf '%s\n' "$@" > "$CALL_FILE"
    if [[ "$MODE" == forbidden ]]; then
        printf 'unexpected CASS invocation\n' >&2
        return 99
    fi
    if [[ "${1:-}" == stats ]]; then
        printf '%s\n' '{"conversations":14274,"messages":50000,"by_agent":[{"agent":"historical-agent","count":14274}],"top_workspaces":[{"workspace":"/work/historical","count":14274}],"date_range":{"oldest":"2025-01-01","newest":"2026-10-13"}}'
        return 0
    fi
    [[ "${1:-}" == search && "${2:-}" == '*' ]] || return 65
    shift 2
    local days='' limit='' agent='' json=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --days) days="${2:-}"; shift 2 ;;
            --limit) limit="${2:-}"; shift 2 ;;
            --agent) agent="${2:-}"; shift 2 ;;
            --json) json=true; shift ;;
            *) printf 'unsupported mock CASS flag: %s\n' "$1" >&2; return 65 ;;
        esac
    done
    [[ -n "$days" && -n "$limit" && "$json" == true ]] || return 65
    case "$MODE" in
        reply) printf '%s' "$REPLY"; return 0 ;;
        failure) printf '%s\n' '{"hits":[]}'; printf 'index unavailable\n' >&2; return 7 ;;
        warning) printf 'CASS index is stale\n' >&2 ;;
    esac
    jq -c --argjson clock "$CLOCK_MS" --argjson days "$days" --argjson limit "$limit" --arg agent "$agent" '
        map(select(.created_at >= ($clock - $days * 86400000)))
        | map(select($agent == "" or .agent == $agent))
        | {hits: .[:$limit], count: (.[:$limit] | length), total_matches: length, limit: $limit, offset: 0,
           aggregations: {agent: [{value:"all-time-poison", count:14274}]}}
    ' <<<"$FIXTURE"
}

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
check() { "$@" || fail "$*"; }
contains() { [[ "$1" == *"$2"* ]] || fail "missing [$2] in [$1]"; }
excludes() { [[ "$1" != *"$2"* ]] || fail "unexpected [$2] in [$1]"; }
json_is() { jq -e "$1" <<<"$OUTPUT" >/dev/null || fail "JSON assertion: $1; output: $OUTPUT"; }
run_list() {
    STATUS=0
    list_sessions "$@" > "$STDOUT_FILE" 2> "$STDERR_FILE" || STATUS=$?
    OUTPUT="$(<"$STDOUT_FILE")"
    ERROR="$(<"$STDERR_FILE")"
}
expect_success() { check test "$STATUS" -eq 0; }
expect_failure() {
    check test "$STATUS" -ne 0
    check test -z "$OUTPUT"
    check test -n "$ERROR"
}

reported_text() {
    run_list --days 1 --limit 3
    expect_success
    contains "$OUTPUT" 'Listed Sessions: 3'
    contains "$OUTPUT" '/sessions/recent-a.jsonl'
    contains "$OUTPUT" '/sessions/recent-b.jsonl'
    contains "$OUTPUT" '/sessions/recent-c.jsonl'
    contains "$OUTPUT" '/work/alpha project'
    contains "$OUTPUT" 'codex: 2 sessions'
    excludes "$OUTPUT" 'historical'
    excludes "$OUTPUT" 'recent-d'
    excludes "$OUTPUT" '14274'
    excludes "$OUTPUT" 'Total Messages'
    check test "$(head -n 1 "$CALL_FILE")" = search
}
reported_json() {
    run_list --json --days 1 --limit 3
    expect_success
    json_is '.total == 3 and (.sessions | length) == 3 and .query_info.days == 1 and .query_info.limit == 3'
    json_is '[.sessions[].source_path] == ["/sessions/recent-a.jsonl","/sessions/recent-b.jsonl","/sessions/recent-c.jsonl"]'
    json_is '.by_agent == [{agent:"claude_code",count:1},{agent:"codex",count:2}]'
    json_is '.by_workspace == [{workspace:"/work/alpha project",count:2},{workspace:"/work/beta",count:1}]'
    excludes "$OUTPUT" '14274'
    excludes "$OUTPUT" 'historical'
}
equivalent_modes() {
    run_list --days 1 --agent codex --limit 3 --json
    expect_success
    json_is '.total == 2 and all(.sessions[]; .agent == "codex") and .query_info.agent == "codex"'
    local json="$OUTPUT" json_args
    json_args="$(<"$CALL_FILE")"
    run_list --days 1 --agent codex --limit 3
    expect_success
    check test "$json_args" = "$(<"$CALL_FILE")"
    local path text_paths=''
    while IFS= read -r path; do contains "$OUTPUT" " | $path"; done < <(jq -r '.sessions[].source_path' <<<"$json")
    while IFS= read -r path; do
        case "$path" in '  codex | '*) text_paths+="${path##*' | '}"$'\n' ;; esac
    done <<<"$OUTPUT"
    check test "${text_paths%$'\n'}" = "$(jq -r '.sessions[].source_path' <<<"$json")"
    contains "$OUTPUT" "Listed Sessions: $(jq -r '.total' <<<"$json")"
    contains "$OUTPUT" 'codex: 2 sessions'
    excludes "$OUTPUT" 'recent-a'
    excludes "$OUTPUT" 'historical'
}
window_and_defaults() {
    run_list --json --days 3 --limit 20
    expect_success
    json_is '.total == 6'
    contains "$OUTPUT" 'historical.jsonl'
    run_list --json
    expect_success
    json_is '.query_info.days == 30 and .query_info.limit == 20 and .total == 6'
    run_list --json --days 001 --limit 003
    expect_success
    json_is '.query_info.days == 1 and .query_info.limit == 3 and .total == 3'
}
empty_results() {
    run_list --agent nonexistent --days 1 --limit 3 --json
    expect_success
    json_is '.sessions == [] and .total == 0 and .by_agent == [] and .by_workspace == []'
    run_list --agent nonexistent --days 1 --limit 3
    expect_success
    contains "$OUTPUT" 'No matching sessions found.'
    contains "$OUTPUT" 'Listed Sessions: 0'
    excludes "$OUTPUT" ' | '
}
historical_only() {
    FIXTURE="$(jq '[.[] | select(.title == "October 13")]' <<<"$FIXTURE")"
    run_list --days 1 --limit 3 --json
    expect_success
    json_is '.total == 0 and .sessions == []'
    run_list --days 1 --limit 3
    expect_success
    contains "$OUTPUT" 'Listed Sessions: 0'
    excludes "$OUTPUT" 'historical'
    excludes "$OUTPUT" '2026-10-13'
}
duplicates_and_sources() {
    MODE=reply
    REPLY="$(jq '{hits:[.[0], .[0], .[1]]}' <<<"$FIXTURE")"
    run_list --days 1 --limit 3 --json
    expect_success
    json_is '.total == 2 and [.by_agent[].count] == [1,1]'
    REPLY="$(jq '{hits:[.[0], (.[0] | .source_id="remote")]}' <<<"$FIXTURE")"
    run_list --json
    expect_success
    json_is '.total == 2 and [.sessions[].source_id] == ["local","remote"]'
}
metadata_and_cap() {
    MODE=reply
    REPLY="$(jq '{hits: map(.content="PRIVATE TRANSCRIPT" | .snippet="PRIVATE SNIPPET")}' <<<"$FIXTURE")"
    run_list --json --limit 2
    expect_success
    json_is '.total == 2'
    excludes "$OUTPUT" 'PRIVATE'
    REPLY='{"hits":[{"agent":"codex","workspace":"/work/minimal","source_path":"/sessions/minimal.jsonl"}]}'
    run_list --json
    expect_success
    json_is '.total == 1 and .sessions[0].workspace == "/work/minimal" and .sessions[0].created_at == null'
    run_list
    expect_success
    contains "$OUTPUT" '/work/minimal'
    contains "$OUTPUT" '/sessions/minimal.jsonl'
}
invalid_args() {
    MODE=forbidden
    local flag value
    for flag in --days --limit; do
        for value in '' nope -1 0 00 000 1.5 +1 '1 2' '$((1+1))'; do
            run_list --json "$flag" "$value"
            expect_failure
            check test "$STATUS" -eq 1
            excludes "$ERROR" 'unexpected CASS invocation'
        done
        run_list "$flag"
        expect_failure
        excludes "$ERROR" 'unbound variable'
        excludes "$ERROR" 'unexpected CASS invocation'
        run_list "$flag" --json
        expect_failure
    done
    for value in '' '--json' '-1'; do
        run_list --agent "$value"
        expect_failure
        excludes "$ERROR" 'unexpected CASS invocation'
    done
    run_list --agent
    expect_failure
    run_list --limti 3
    expect_failure
    run_list unexpected
    expect_failure
}
invalid_responses() {
    MODE=reply
    local flag
    for REPLY in '' ' ' '{' '{}' '[]' 'null' 'false' '"text"' \
        '{"hits":[]} {"hits":[]}' '{"hits":[]} trailing' \
        '{"hits":null}' '{"hits":{}}' '{"hits":[null]}' '{"hits":[{}]}' \
        '{"hits":[{"source_path":"a"}]}' '{"hits":[{"source_path":"","agent":"codex"}]}' \
        '{"hits":[{"source_path":"a","agent":false}]}' \
        '{"hits":[{"source_path":"a","agent":"codex","workspace":{}}]}' \
        '{"hits":[],"error":"broken"}' '{"err":{"kind":"broken"}}' \
        '{"hits":[],"budget":{"timed_out":true}}'; do
        for flag in text json; do
            if [[ "$flag" == json ]]; then run_list --json; else run_list; fi
            expect_failure
            contains "$ERROR" 'Invalid JSON search results from CASS'
        done
    done
}
backend_failure() {
    MODE=failure
    set +o pipefail
    run_list --json
    expect_failure
    contains "$ERROR" 'index unavailable'
    run_list
    expect_failure
    contains "$ERROR" 'Failed to query CASS'
}
missing_cass() {
    unset -f cass
    PATH="$WORK/empty-path"
    run_list --json
    check test "$STATUS" -ne 0
    contains "$OUTPUT" '"error": "CASS not installed"'
    excludes "$OUTPUT" '"sessions"'
    run_list
    expect_failure
    contains "$ERROR" 'CASS (Coding Agent Session Search) is not installed'
}
missing_jq() {
    acfs_session_system_binary_path() { return 1; }
    MODE=forbidden
    run_list --json
    expect_failure
    contains "$ERROR" 'jq is required'
    excludes "$ERROR" 'unexpected CASS invocation'
}
backend_warning() {
    MODE=warning
    run_list --json --days 1 --limit 3
    expect_success
    json_is '.total == 3'
    contains "$ERROR" 'CASS index is stale'
    excludes "$OUTPUT" 'CASS index is stale'
}

passed=0
failed=0
for name in reported_text reported_json equivalent_modes window_and_defaults \
    empty_results historical_only duplicates_and_sources metadata_and_cap \
    invalid_args invalid_responses backend_failure missing_cass missing_jq \
    backend_warning; do
    if ( "$name" ) > "$WORK/$name.log" 2>&1; then
        printf 'PASS %s\n' "$name"
        passed=$((passed + 1))
    else
        printf 'FAIL %s\n' "$name"
        cat "$WORK/$name.log"
        failed=$((failed + 1))
    fi
done
printf '\n%d passed; %d failed\n' "$passed" "$failed"
if [[ "$failed" -ne 0 ]]; then
    printf 'Diagnostics: %s\n' "$WORK"
    exit 1
fi
