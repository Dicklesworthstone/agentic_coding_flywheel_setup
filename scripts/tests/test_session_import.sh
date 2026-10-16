#!/usr/bin/env bash
# Exercise the real import, sanitization and native-conversion pipeline offline.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
export ACFS_SESSION_TEST_LIB="${ACFS_SESSION_TEST_LIB:-$ROOT/scripts/lib/session.sh}"
command -v jq >/dev/null || { printf 'jq is required\n' >&2; exit 1; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/acfs-session-import-test.XXXXXX")
export WORK
printf 'Session import test artifacts: %s\n' "$WORK" >&2
mkdir -p "$WORK/home" "$WORK/tmp" "$WORK/store"
export HOME="$WORK/home" CLAUDE_HOME="$WORK/home/.claude" CODEX_HOME="$WORK/home/.codex" GEMINI_HOME="$WORK/home/.gemini"
export TMPDIR="$WORK/tmp" ACFS_SESSIONS_DIR="$WORK/store"

cat > "$WORK/codex.json" <<'JSON'
[
 {"type":"session_meta","payload":{"id":"recover-codex","cwd":"/project","originator":"codex_cli_rs"}},
 {"type":"turn_context","payload":{"model":"fixture-model"}},
 {"type":"event_msg","timestamp":"2026-10-15T10:00:00Z","payload":{"type":"user_message","message":"Question: password=supersecret123"}},
 {"type":"response_item","timestamp":"2026-10-15T10:00:00Z","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Question: password=supersecret123"}]}},
 {"type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"NOT_DIALOGUE"}]}},
 {"type":"event_msg","payload":{"type":"agent_reasoning","text":"NOT_DIALOGUE"}},
 {"type":"response_item","payload":{"type":"function_call_output","output":"NOT_DIALOGUE"}},
 {"type":"response_item","timestamp":"2026-10-15T10:00:01Z","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Recovered answer\n"},{"type":"output_text","text":"with Unicode: café 世界"}]}},
 {"type":"event_msg","timestamp":"2026-10-15T10:00:01Z","payload":{"type":"agent_message","message":"Recovered answer\nwith Unicode: café 世界"}}
]
JSON
jq -c '.[]' "$WORK/codex.json" > "$WORK/codex.jsonl"
cat > "$WORK/claude.json" <<'JSON'
[
 {"type":"file-history-snapshot","snapshot":{}},
 {"type":"user","sessionId":"recover-claude","timestamp":"2026-10-15T11:00:00Z","message":{"role":"user","content":"Question"}},
 {"type":"assistant","sessionId":"recover-claude","timestamp":"2026-10-15T11:00:01Z","message":{"role":"assistant","model":"fixture-model","content":[{"type":"thinking","thinking":"NOT_DIALOGUE"},{"type":"text","text":"Recovered Claude answer"},{"type":"tool_use","input":{"private":"NOT_DIALOGUE"}}]}},
 {"type":"user","sessionId":"recover-claude","message":{"role":"user","content":[{"type":"tool_result","content":"NOT_DIALOGUE"}]}}
]
JSON
cat > "$WORK/acfs.json" <<'JSON'
{"schema_version":1,"session_id":"existing-acfs","agent":"codex","stats":{"turns":2},"sanitized_transcript":[{"role":"user","content":"password=supersecret123","timestamp":"2026-10-15T10:00:00Z"},{"role":"assistant","content":"Recovered ACFS answer","timestamp":"2026-10-15T10:00:01Z"}]}
JSON

# Keep each invocation in a fresh shell, including failures under set -e/-u.
cat > "$WORK/runner.sh" <<'RUN'
#!/usr/bin/env bash
set -euo pipefail
_ACFS_LOGGING_SH_LOADED=1
log_error() { printf 'ERROR: %s\n' "$*" >&2; }
log_warn() { printf 'WARN: %s\n' "$*" >&2; }
log_info() { printf '%s\n' "$*" >&2; }
log_success() { printf '%s\n' "$*" >&2; }
# shellcheck disable=SC1090
source "$ACFS_SESSION_TEST_LIB"
generate_session_id() { printf '%s\n' "${CASE_ID:-imported}"; }
case "${TEST_MODE:-normal}" in
    sanitizer_failure) sanitize_session_export() { return 71; } ;;
    publish_failure) acfs_session_publish_new_file() { return 72; } ;;
    copy_failure) cp() { return 73; } ;;
    jq_missing) acfs_session_system_binary_path() { return 1; } ;;
    no_pipefail) set +o pipefail ;;
    changing_source)
        original_defs=$(acfs_session_transcript_jq_defs)
        acfs_session_transcript_jq_defs() {
            printf '%s\n' "$original_defs"
            printf '{}' > "$WORK/changing.json"
        }
        ;;
esac
roundtrip() {
    cass() { cat -- "$WORK/codex.json"; }
    export_session "$WORK/codex.jsonl" --output "$WORK/exported.json" >/dev/null
    import_session "$WORK/exported.json"
}
check_caller_state() {
    trap 'printf "%s\n" caller-exit-preserved >&2' EXIT
    caller() {
        trap 'printf "%s\n" caller-return-preserved >&2' RETURN
        local before
        before=$(umask)
        import_session "$WORK/codex.json" --dry-run >/dev/null
        [[ $(umask) == "$before" ]]
        trap -p RETURN
    }
    caller
    trap -p EXIT
}
"$@"
RUN

passed=0 failed=0
assert() {
    local label=$1
    shift
    if "$@"; then passed=$((passed + 1)); else
        printf 'FAIL: %s\n' "$label" >&2
        failed=$((failed + 1))
    fi
}
export TEST_MODE=normal CASE_ID=imported
run_helper() {
    STATUS=0
    bash "$WORK/runner.sh" "$@" > "$WORK/stdout" 2> "$WORK/stderr" || STATUS=$?
}
json_is() { jq -e "$1" "$2" >/dev/null; }
no_success() { [[ "$STATUS" -ne 0 && ! -s "$WORK/stdout" ]]; }
no_temp_files() { [[ -z $(find "$WORK/tmp" "$WORK/store" -type f -name '*.tmp' -o -type f -name 'acfs_session_*') ]]; }

for kind in codex claude acfs; do
    CASE_ID="$kind"
    run_helper import_session "$WORK/$kind.json" --dry-run
    assert "$kind dry run succeeds" test "$STATUS" -eq 0
    assert "$kind dry run shows actual message count" grep -q 'Messages: 2' "$WORK/stdout"
    assert "$kind dry run never publishes" test ! -e "$WORK/store/$kind.json"
    run_helper import_session "$WORK/$kind.json"
    assert "$kind import succeeds" test "$STATUS" -eq 0
    assert "$kind persists both conversational roles" json_is '[.sanitized_transcript[].role] == ["user","assistant"]' "$WORK/store/$kind.json"
    assert "$kind retains assistant response" json_is '.sanitized_transcript[1].content | startswith("Recovered")' "$WORK/store/$kind.json"
    assert "$kind computes turns from the normalized conversation" json_is '.stats.turns == 2 and (.sanitized_transcript|length) == 2' "$WORK/store/$kind.json"
    assert "$kind sanitizes before publication" bash -c '! grep -Eq "supersecret123|NOT_DIALOGUE" "$1"' _ "$WORK/store/$kind.json"
    assert "$kind input was not modified" grep -q 'Question\|supersecret123' "$WORK/$kind.json"
    assert "$kind private staging is cleaned" no_temp_files
    assert "$kind destination is private" test "$(stat -c %a "$WORK/store/$kind.json")" = 600
    run_helper show_session "$kind" --format json
    assert "$kind imported session is viewable" test "$STATUS" -eq 0
    assert "$kind view preserves both roles" json_is '.sanitized_transcript | length == 2' "$WORK/stdout"
done

CASE_ID=roundtrip
run_helper roundtrip
assert 'CASS export to import roundtrip succeeds' test "$STATUS" -eq 0
assert 'roundtrip preserves the answer and removes secret' json_is '.sanitized_transcript[1].content == "Recovered answer\nwith Unicode: café 世界" and (.sanitized_transcript[0].content | contains("supersecret123") | not)' "$WORK/store/roundtrip.json"
run_helper parse_native_codex_to_canonical "$WORK/codex.jsonl" /project
assert 'native Codex parser succeeds' test "$STATUS" -eq 0
assert 'native and imported dialogue share the same projection' json_is '[.messages[].role] == ["user","assistant"] and .messages[1].content == "Recovered answer\nwith Unicode: café 世界"' "$WORK/stdout"
run_helper convert_session_native "$WORK/codex.jsonl" --from codex --to claude-code --session-id recovered-native --json
assert 'native Codex to Claude conversion succeeds' test "$STATUS" -eq 0
if [[ "$STATUS" == 0 ]]; then
    native=$(jq -r .written_path "$WORK/stdout")
    assert 'native writer receives two complete conversational messages' test "$(jq -s length "$native")" -eq 2
    assert 'native target preserves Unicode answer' bash -c 'jq -es '\''.[1].message.content[0].text == "Recovered answer\nwith Unicode: café 世界"'\'' "$1" >/dev/null' _ "$native"
fi

# Legacy event-only answers and response-only conversations both occur in
# archives. Repeated same-encoding text and repeated turns are not duplicates.
jq '[.[0], {type:"event_msg",payload:{type:"user_message",message:"Again"}}, {type:"event_msg",payload:{type:"agent_message",message:"Legacy answer"}}]' "$WORK/codex.json" > "$WORK/legacy.json"
run_helper convert_to_acfs_schema "$WORK/legacy.json"
assert 'legacy event-only assistant messages are retained' json_is '.sanitized_transcript[1].content == "Legacy answer"' "$WORK/stdout"
jq 'map(select(.type != "event_msg"))' "$WORK/codex.json" > "$WORK/responses.json"
run_helper convert_to_acfs_schema "$WORK/responses.json"
assert 'response-only user and assistant messages are retained' json_is '[.sanitized_transcript[].role] == ["user","assistant"]' "$WORK/stdout"
jq '[.[0], {type:"event_msg",payload:{type:"user_message",message:"Again"}}, {type:"event_msg",payload:{type:"user_message",message:"Again"}}, {type:"event_msg",payload:{type:"task_started"}}, {type:"response_item",payload:{type:"message",role:"user",content:[{type:"input_text",text:"Again"}]}}]' "$WORK/codex.json" > "$WORK/repeated.json"
run_helper convert_to_acfs_schema "$WORK/repeated.json"
assert 'repeated real messages and separate turns are not globally deduplicated' json_is '.sanitized_transcript|length == 3' "$WORK/stdout"
run_helper convert_to_acfs_schema "$WORK/codex.json" claude-code
assert 'conflicting agent hint fails rather than relabels dialogue' no_success

# Unknown, mixed and malformed documents must never create an imported file.
CASE_ID=invalid
for bad in '' broken null '{}' '[]' '[false]' '{"schema_version":1}' \
    '{"schema_version":1,"session_id":"bad","agent":"codex","sanitized_transcript":{}}' \
    '{"schema_version":1,"session_id":"bad","agent":"codex","sanitized_transcript":[{"role":"tool","content":"bad"}]}' \
    '{"schema_version":1,"session_id":"../bad","agent":"codex","sanitized_transcript":[]}' \
    '{"schema_version":1,"session_id":"bad","agent":"codex","sanitized_transcript":[]} {}'; do
    printf '%s' "$bad" > "$WORK/invalid.json"
    for TEST_MODE in normal no_pipefail; do
        run_helper import_session "$WORK/invalid.json"
        assert "$TEST_MODE rejects malformed import: $bad" no_success
        assert 'invalid import never publishes' test ! -e "$WORK/store/invalid.json"
        assert 'failed import cleans staging' no_temp_files
    done
done
TEST_MODE=normal
jq '. + [{type:"session_meta",payload:{id:"different-session"}}]' "$WORK/codex.json" > "$WORK/mixed-ids.json"
run_helper import_session "$WORK/mixed-ids.json"
assert 'multiple session IDs fail instead of blending conversations' no_success
jq --slurpfile claude "$WORK/claude.json" '. + $claude[0]' "$WORK/codex.json" > "$WORK/mixed-agents.json"
run_helper import_session "$WORK/mixed-agents.json"
assert 'mixed provider formats are rejected' no_success
jq '.[7].payload.content[0].text = {}' "$WORK/codex.json" > "$WORK/invalid-text.json"
run_helper import_session "$WORK/invalid-text.json"
assert 'malformed text cannot become stringified object content' no_success

CASE_ID=failure
for TEST_MODE in sanitizer_failure publish_failure copy_failure jq_missing; do
    run_helper import_session "$WORK/codex.json"
    assert "$TEST_MODE returns failure without successful output" no_success
    assert "$TEST_MODE never publishes" test ! -e "$WORK/store/failure.json"
    assert "$TEST_MODE cleans private stages" no_temp_files
done
TEST_MODE=sanitizer_failure
run_helper import_session "$WORK/codex.json" --dry-run
assert 'dry run performs real sanitization checks' no_success
TEST_MODE=normal
CASE_ID=collision
printf '%s\n' 'existing-import-sentinel' > "$WORK/store/collision.json"
before=$(sha256sum "$WORK/store/collision.json")
run_helper import_session "$WORK/acfs.json"
assert 'an ID collision cannot replace a previously imported session' no_success
assert 'existing imported bytes survive collision' test "$before" = "$(sha256sum "$WORK/store/collision.json")"
CASE_ID=snapshot
cp -- "$WORK/codex.json" "$WORK/changing.json"
TEST_MODE=changing_source
run_helper import_session "$WORK/changing.json"
assert 'source changes after parsing do not replace the validated snapshot' test "$STATUS" -eq 0
assert 'snapshot keeps original dialogue' json_is '.sanitized_transcript|length == 2' "$WORK/store/snapshot.json"
assert 'snapshot test actually changed the caller input' json_is '. == {}' "$WORK/changing.json"
TEST_MODE=normal
run_helper check_caller_state
assert 'import preserves caller umask and traps' test "$STATUS" -eq 0
assert 'caller RETURN trap survives' grep -q caller-return-preserved "$WORK/stderr"
assert 'caller EXIT trap survives' grep -q caller-exit-preserved "$WORK/stderr"
for option in --bogus --dry-run-extra; do
    run_helper import_session "$WORK/codex.json" "$option"
    assert 'unknown import arguments are errors' no_success
done
run_helper import_session "$WORK/codex.json" "$WORK/claude.json"
assert 'multiple input files are not silently ignored' no_success

CASE_ID=large
jq -n '[{type:"session_meta",payload:{id:"large-session"}}, {type:"response_item",payload:{type:"message",role:"assistant",content:[{type:"output_text",text:("x" * 262144)}]}}]' > "$WORK/large.json"
run_helper import_session "$WORK/large.json"
assert 'large transcripts stay off argv' test "$STATUS" -eq 0
assert 'large assistant content is not truncated' json_is '.sanitized_transcript[0].content|length == 262144' "$WORK/store/large.json"
assert 'all private staging files are cleaned' no_temp_files
printf 'Session import: %s assertions passed; %s failed\n' "$passed" "$failed"
[[ "$failed" == 0 ]]
