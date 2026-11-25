#!/usr/bin/env bash
# Test session sanitization patterns

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARTIFACT_DIR="${ACFS_SESSION_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-session-sanitization-$(date +%Y%m%d-%H%M%S)-$$}"
mkdir -p "$ARTIFACT_DIR"
export TMPDIR="$ARTIFACT_DIR"
source "$REPO_ROOT/scripts/lib/logging.sh"
source "$REPO_ROOT/scripts/lib/session.sh"

# Keep every synthetic export and temporary file for inspection.
acfs_session_remove_temp_files() { :; }

# Test Data
# Construct keys dynamically to avoid secret scanning detection
# These must match the patterns in session.sh:
# Stripe: [rs]k_(live|test)_[a-zA-Z0-9]{24,}
# HuggingFace: hf_[a-zA-Z0-9]{34}

STRIPE_LIVE="sk_live_""123456789012345678901234"
STRIPE_TEST="sk_test_""123456789012345678901234"
HF_TOKEN="hf_""1234567890123456789012345678901234"

RAW_TEXT="
My OpenAI key is sk-12345678901234567890
My Anthropic key is sk-ant-12345678901234567890
My AWS key is AKIAIOSFODNN7EXAMPLE
My HuggingFace token is ${HF_TOKEN}
My Stripe live key is ${STRIPE_LIVE}
My Stripe test key is ${STRIPE_TEST}
Normal text should remain.
"

echo "Testing sanitize_content..."
SANITIZED=$(sanitize_content "$RAW_TEXT")

echo "$SANITIZED"

# verification
if echo "$SANITIZED" | grep -q "sk-12345"; then echo "FAIL: OpenAI leaked"; exit 1; fi
if echo "$SANITIZED" | grep -q "sk-ant-12345"; then echo "FAIL: Anthropic leaked"; exit 1; fi
if echo "$SANITIZED" | grep -q "AKIA"; then echo "FAIL: AWS leaked"; exit 1; fi
if echo "$SANITIZED" | grep -q "hf_"; then echo "FAIL: HuggingFace leaked"; exit 1; fi
if echo "$SANITIZED" | grep -q "sk_live_"; then echo "FAIL: Stripe live leaked"; exit 1; fi
if echo "$SANITIZED" | grep -q "sk_test_"; then echo "FAIL: Stripe test leaked"; exit 1; fi

echo "PASS: sanitize_content"

# Test JSON sanitization
echo "Testing sanitize_session_export (jq)..."
JSON_FILE="$ARTIFACT_DIR/provider.json"
cat > "$JSON_FILE" <<EOF
{
  "schema_version": 1,
  "session_id": "test",
  "agent": "claude-code",
  "sanitized_transcript": [
    {
      "role": "user",
      "content": "My secret is ${HF_TOKEN}"
    },
    {
        "role": "assistant",
        "content": "I see your stripe key ${STRIPE_LIVE}"
    }
  ]
}
EOF

sanitize_session_export "$JSON_FILE"
SANITIZED_JSON=$(cat "$JSON_FILE")

if echo "$SANITIZED_JSON" | grep -q "hf_"; then echo "FAIL: JSON HuggingFace leaked"; exit 1; fi
if echo "$SANITIZED_JSON" | grep -q "sk_live_"; then echo "FAIL: JSON Stripe leaked"; exit 1; fi

echo "PASS: sanitize_session_export"

TESTS_PASSED=2
TESTS_FAILED=0
SOURCE_SESSION="$ARTIFACT_DIR/source-session.jsonl"
printf '%s\n' '{"fixture":"source session remains unchanged"}' > "$SOURCE_SESSION"
cp "$SOURCE_SESSION" "$SOURCE_SESSION.before"

# Exercise the real export_session entry point with deterministic CASS output.
# Redaction, JSON validation, publication, and postconditions remain real.
cass() {
    [[ "$#" -eq 4 && "$1" == export && "$2" == "$SOURCE_SESSION" &&
       "$3" == --format && "$4" == "$EXPECTED_FORMAT" ]] || return 64
    cat "$EXPORT_FIXTURE"
}

run_export() {
    local name="$1"
    EXPECTED_FORMAT="$2"
    EXPORT_FIXTURE="$3"
    shift 3
    local status=0
    export_session "$SOURCE_SESSION" --format "$EXPECTED_FORMAT" "$@" \
        > "$ARTIFACT_DIR/$name.output" 2> "$ARTIFACT_DIR/$name.stderr" || status=$?
    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    return "$status"
}

test_quoted_markdown_export() {
    local fixture="$ARTIFACT_DIR/quoted-markdown.txt" output
    cat > "$fixture" <<'TEXT'
# Session transcript
PASSWORD="fixtureQuotedFirst fixtureQuotedTail"
password="correct horse battery staple"
secret='fixtureQuotedSingleFirst fixtureQuotedSingleTail'
auth_token="fixtureQuotedEscapedFirst \"fixtureQuotedEscapedTail"
access_token=\"fixtureQuotedEncodedFirst fixtureQuotedEncodedTail\"
{"password":"fixtureQuotedJsonFirst\"fixtureQuotedJsonTail","public":"public nested guidance"}
Public guidance remains readable.
secret="fixtureQuotedIncompleteFirst fixtureQuotedIncompleteTail
TEXT
    run_export quoted-markdown markdown "$fixture" || return 1
    output="$(cat "$ARTIFACT_DIR/quoted-markdown.output")"
    [[ "$output" != *fixtureQuoted* && "$output" != *'correct horse battery staple'* ]] || return 1
    [[ "$output" == *'Public guidance remains readable.'* &&
       "$output" == *'public nested guidance'* ]] || return 1
}

test_json_export_preserves_public_values() {
    local fixture="$ARTIFACT_DIR/quoted-json.json" output
    cat > "$fixture" <<'JSON'
{"schema_version":1,"session_id":"fixture-session","agent":"claude-code","requestId":9007199254740993,"public":{"enabled":false,"nothing":null,"count":12,"text":"public deployment guidance","items":[1,"public item",true]},"password":12345,"api_key":null,"auth_token":false,"private_key":{"inner":"fixtureJsonStructuredSecret"},"secret_key":[1,{"inner":"fixtureJsonArraySecret"}],"passwordCount":4,"sanitized_transcript":[{"role":"user","content":"PASSWORD=\"fixtureJsonFirst fixtureJsonTail\""},{"role":"assistant","content":"password=\"correct horse battery staple\""}],"document":"{\"pass\\u0077ord\":\"fixtureJsonNestedFirst\\\"fixtureJsonNestedTail\",\"public\":\"public nested guidance\",\"requestId\":9007199254740993}","unconfigured":{"password":""}}
JSON
    run_export quoted-json json "$fixture" || return 1
    output="$(cat "$ARTIFACT_DIR/quoted-json.output")"
    [[ "$output" != *fixtureJson* && "$output" != *'correct horse battery staple'* ]] || return 1
    jq -e '.schema_version == 1 and .session_id == "fixture-session" and
      .public == {"enabled":false,"nothing":null,"count":12,"text":"public deployment guidance","items":[1,"public item",true]} and
      [.password,.api_key,.auth_token,.private_key,.secret_key,.passwordCount,.unconfigured.password] ==
        ["[REDACTED]","[REDACTED]","[REDACTED]","[REDACTED]","[REDACTED]","[REDACTED]","[REDACTED]"] and
      (.document | fromjson | .password == "[REDACTED]" and .public == "public nested guidance") and
      (.document | contains("\"requestId\":9007199254740993"))' <<< "$output" >/dev/null || return 1
    [[ "$output" == *'"requestId":9007199254740993'* ]] || return 1
}

test_export_optional_redaction_and_opt_out() {
    local fixture="$ARTIFACT_DIR/optional.json" format output
    for format in json markdown; do
        printf '%s\n' '{"content":"fixture@example.invalid 192.0.2.14 password=fixtureOptionalCredential"}' > "$fixture"
        ACFS_SANITIZE_OPTIONAL=0 run_export "default-$format" "$format" "$fixture" || return 1
        output="$(cat "$ARTIFACT_DIR/default-$format.output")"
        [[ "$output" == *fixture@example.invalid* && "$output" == *192.0.2.14* &&
           "$output" != *fixtureOptionalCredential* ]] || return 1
        ACFS_SANITIZE_OPTIONAL=1 run_export "optional-$format" "$format" "$fixture" || return 1
        output="$(cat "$ARTIFACT_DIR/optional-$format.output")"
        [[ "$output" != *fixture@example.invalid* && "$output" != *192.0.2.14* &&
           "$output" != *fixtureOptionalCredential* ]] || return 1
        ACFS_SANITIZE_OPTIONAL=1 run_export "raw-$format" "$format" "$fixture" --no-sanitize || return 1
        cmp -s "$fixture" "$ARTIFACT_DIR/raw-$format.output" || return 1
    done
}

test_private_key_postcondition_with_opt_out() {
    local fixture="$ARTIFACT_DIR/private-key.json" format
    printf '%s\n' '{"content":"-----BEGIN PRIVATE KEY-----fixturePrivateKeyBody-----END PRIVATE KEY-----"}' > "$fixture"
    for format in json markdown; do
        run_export "sanitized-private-key-$format" "$format" "$fixture" || return 1
        [[ "$(cat "$ARTIFACT_DIR/sanitized-private-key-$format.output")" != *fixturePrivateKeyBody* ]] || return 1
        if run_export "private-key-$format" "$format" "$fixture" --no-sanitize; then
            return 1
        fi
        [[ ! -s "$ARTIFACT_DIR/private-key-$format.output" ]] || return 1
    done
}

test_failed_redactor_never_publishes() (
    local fixture="$ARTIFACT_DIR/redactor-failure.json" format invalid_output=false
    printf '%s\n' '{"content":"password=fixtureFailedRedactor"}' > "$fixture"
    # export_session invokes this injected failure indirectly.
    # shellcheck disable=SC2329
    acfs_session_sanitize_stream() {
        printf '%s\n' 'fixturePartialRedactorOutput'
        [[ "$invalid_output" != true ]] || return 0
        return 71
    }
    for format in json markdown; do
        if run_export "redactor-failure-$format" "$format" "$fixture"; then
            return 1
        fi
        [[ ! -s "$ARTIFACT_DIR/redactor-failure-$format.output" ]] || return 1
    done
    invalid_output=true
    if run_export redactor-invalid-json json "$fixture"; then
        return 1
    fi
    [[ ! -s "$ARTIFACT_DIR/redactor-invalid-json.output" ]]
)

test_json_export_rejects_multiple_documents() {
    local fixture="$ARTIFACT_DIR/multiple-documents.json"
    printf '%s\n' '{"public":"first document"}' \
        '{"private_key":{"inner":"fixtureMultipleDocumentSecret"}}' > "$fixture"
    if run_export multiple-documents json "$fixture"; then
        return 1
    fi
    [[ ! -s "$ARTIFACT_DIR/multiple-documents.output" ]]
}

test_export_preserves_source_history_and_aliases() (
    local fixture="$ARTIFACT_DIR/publication-source.json" destination index=0
    local SOURCE_SESSION="$ARTIFACT_DIR/publication-source.jsonl"
    printf '%s\n' 'original conversation history' > "$SOURCE_SESSION"
    printf '%s\n' '{"content":"exported projection"}' > "$fixture"
    ln -- "$SOURCE_SESSION" "$SOURCE_SESSION.hardlink" || return 1
    ln -s -- "$SOURCE_SESSION" "$SOURCE_SESSION.link" || return 1
    cass() { printf 'called\n' >> "$ARTIFACT_DIR/source-refusal-cass-called"; cat "$EXPORT_FIXTURE"; }
    for destination in "$SOURCE_SESSION" "$ARTIFACT_DIR/./publication-source.jsonl" \
        "$SOURCE_SESSION.hardlink" "$SOURCE_SESSION.link"; do
        index=$((index + 1))
        if run_export "source-refusal-$index" json "$fixture" --output "$destination"; then
            return 1
        fi
        [[ ! -s "$ARTIFACT_DIR/source-refusal-$index.output" ]] || return 1
        [[ "$(cat "$SOURCE_SESSION")" == 'original conversation history' ]] || return 1
    done
    [[ -L "$SOURCE_SESSION.link" && ! -e "$ARTIFACT_DIR/source-refusal-cass-called" ]]
)

test_export_refuses_directories_and_links() (
    local fixture="$ARTIFACT_DIR/publication-links.json" destination index=0
    local target="$ARTIFACT_DIR/publication-target" directory="$ARTIFACT_DIR/publication-directory"
    printf '%s\n' 'user file sentinel' > "$target"
    printf '%s\n' '{"content":"exported projection"}' > "$fixture"
    mkdir -- "$directory" || return 1
    ln -s -- "$directory" "$directory.link" || return 1
    ln -s -- "$target" "$target.link" || return 1
    ln -s -- "$target.absent" "$target.dangling" || return 1
    for destination in "$directory" "$directory/" "$directory.link" "$target.link" "$target.dangling"; do
        index=$((index + 1))
        if run_export "unsafe-output-$index" json "$fixture" --output "$destination"; then
            return 1
        fi
    done
    [[ "$(cat "$target")" == 'user file sentinel' && ! -e "$target.absent" ]] || return 1
    [[ -L "$target.link" && -L "$target.dangling" && -L "$directory.link" ]] || return 1
    [[ -z "$(find "$directory" -mindepth 1 -print -quit)" ]]
)

test_export_replaces_regular_output_privately() (
    local fixture="$ARTIFACT_DIR/publication-success.json" output="$ARTIFACT_DIR/replaced-export.json"
    printf '%s\n' '{"content":"public projection","api_key":"fixturePublishCredential"}' > "$fixture"
    printf '%s\n' 'previous export' > "$output"
    umask 000
    run_export publication-success json "$fixture" --output "$output" || return 1
    jq -e '.content == "public projection" and .api_key == "[REDACTED]"' "$output" >/dev/null || return 1
    [[ "$(stat -c %a -- "$output")" == 600 && ! -s "$ARTIFACT_DIR/publication-success.output" ]] || return 1
    [[ "$(cat "$ARTIFACT_DIR/publication-success.stderr")" == *'Exported to:'* ]]
)

test_export_rechecks_destination_after_cass() (
    local fixture="$ARTIFACT_DIR/publication-race.json" mode destination
    printf '%s\n' '{"content":"exported projection"}' > "$fixture"
    # Called indirectly by export_session in the sourced library.
    # shellcheck disable=SC2329
    cass() {
        if [[ "$mode" == directory ]]; then
            mkdir -- "$destination" || return 1
        else
            ln -s -- "$SOURCE_SESSION" "$destination" || return 1
        fi
        cat "$EXPORT_FIXTURE"
    }
    for mode in directory symlink; do
        destination="$ARTIFACT_DIR/publication-race-$mode"
        if run_export "publication-race-$mode" json "$fixture" --output "$destination"; then
            return 1
        fi
        [[ ! -s "$ARTIFACT_DIR/publication-race-$mode.output" ]] || return 1
    done
    [[ -L "$ARTIFACT_DIR/publication-race-symlink" ]] || return 1
    [[ -z "$(find "$ARTIFACT_DIR/publication-race-directory" -mindepth 1 -print -quit)" ]]
)

test_failed_export_publication_preserves_previous_output() (
    local fixture="$ARTIFACT_DIR/publication-failure.json" output="$ARTIFACT_DIR/preserved-export.json"
    local failed_mv="$ARTIFACT_DIR/publication-failing-mv"
    printf '%s\n' '{"content":"exported projection"}' > "$fixture"
    printf '%s\n' 'previous export sentinel' > "$output"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 73' > "$failed_mv"
    chmod +x "$failed_mv" || return 1
    # Fail the external rename, including the old PATH-based route. The export
    # must not turn a publication error into a destructive streaming fallback.
    # Both overrides are invoked indirectly by the sourced export library.
    # shellcheck disable=SC2329
    mv() { return 73; }
    # shellcheck disable=SC2329
    acfs_session_system_binary_path() {
        if [[ "$1" == mv ]]; then printf '%s\n' "$failed_mv";
        else printf '/usr/bin/%s\n' "$1"; fi
    }
    if run_export publication-failure json "$fixture" --no-sanitize --output "$output"; then
        return 1
    fi
    [[ "$(cat "$output")" == 'previous export sentinel' ]] || return 1
    [[ ! -s "$ARTIFACT_DIR/publication-failure.output" ]] || return 1
    [[ "$(cat "$ARTIFACT_DIR/publication-failure.stderr")" != *'Exported to:'* ]]
)

for test_case in test_quoted_markdown_export test_json_export_preserves_public_values \
    test_export_optional_redaction_and_opt_out test_private_key_postcondition_with_opt_out \
    test_failed_redactor_never_publishes test_json_export_rejects_multiple_documents \
    test_export_preserves_source_history_and_aliases test_export_refuses_directories_and_links \
    test_export_replaces_regular_output_privately test_export_rechecks_destination_after_cass \
    test_failed_export_publication_preserves_previous_output; do
    if "$test_case"; then
        printf 'PASS: %s\n' "$test_case"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        printf 'FAIL: %s\n' "$test_case"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

cmp -s "$SOURCE_SESSION" "$SOURCE_SESSION.before" || TESTS_FAILED=$((TESTS_FAILED + 1))
printf 'Results: %s passed, %s failed\nArtifacts: %s\n' "$TESTS_PASSED" "$TESTS_FAILED" "$ARTIFACT_DIR"
[[ "$TESTS_FAILED" -eq 0 ]]
