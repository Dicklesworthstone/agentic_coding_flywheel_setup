#!/usr/bin/env bash
# ============================================================
# E2E Test: Real Cross-Agent Session Resume Matrix
#
# Non-mock integration test that:
#   1. Creates fresh sessions in codex/claude/gemini
#   2. Verifies cross-agent resume paths with strict session-id continuity
#
# Optional baseline diagnostics:
#   - Self-resume checks for each CLI can be enabled with:
#       ACFS_INCLUDE_SELF_RESUME_BASELINE=true
#
# Artifacts:
#   tests/e2e/logs/cross_agent_resume_<timestamp>.log
#   tests/e2e/logs/cross_agent_resume_<timestamp>.json
#   tests/e2e/logs/cross_agent_resume_<timestamp>/*.log
# ============================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$REPO_ROOT/tests/e2e/logs"
ARTIFACT_DIR="$LOG_DIR/cross_agent_resume_${TIMESTAMP}"
LOG_FILE="$LOG_DIR/cross_agent_resume_${TIMESTAMP}.log"
JSON_FILE="$LOG_DIR/cross_agent_resume_${TIMESTAMP}.json"

mkdir -p "$LOG_DIR" "$ARTIFACT_DIR"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

declare -a RESULTS_JSON=()

INCLUDE_SELF_RESUME_BASELINE="${ACFS_INCLUDE_SELF_RESUME_BASELINE:-false}"

# Cross-CLI session reuse is not currently interoperable.
# Default expectation is isolation; set ACFS_E2E_EXPECT_CROSS_RESUME=true to
# enforce strict cross-resume continuity checks.
EXPECT_CROSS_RESUME="${ACFS_E2E_EXPECT_CROSS_RESUME:-false}"

log() {
    local level="${1:-INFO}"
    local test_name="${2:-general}"
    shift 2 || true
    local message="$*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] [$test_name] $message" | tee -a "$LOG_FILE"
}

json_escape() {
    local s="${1:-}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

record_result() {
    local status="$1"
    local test_name="$2"
    local message="$3"
    local exit_code="${4:-}"
    local expected_session_id="${5:-}"
    local observed_session_id="${6:-}"
    local artifact_path="${7:-}"

    local escaped_message escaped_expected escaped_observed escaped_artifact
    escaped_message="$(json_escape "$message")"
    escaped_expected="$(json_escape "$expected_session_id")"
    escaped_observed="$(json_escape "$observed_session_id")"
    escaped_artifact="$(json_escape "$artifact_path")"

    RESULTS_JSON+=("{\"test\":\"$test_name\",\"status\":\"$(echo "$status" | tr '[:upper:]' '[:lower:]')\",\"message\":\"$escaped_message\",\"exit_code\":\"$exit_code\",\"expected_session_id\":\"$escaped_expected\",\"observed_session_id\":\"$escaped_observed\",\"artifact\":\"$escaped_artifact\"}")

    case "$status" in
        PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
        FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
        SKIP) SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
        *) ;;
    esac

    log "$status" "$test_name" "$message"
    if [[ -n "$expected_session_id" || -n "$observed_session_id" ]]; then
        log "INFO" "$test_name" "expected_session_id=${expected_session_id:-<none>} observed_session_id=${observed_session_id:-<none>}"
    fi
    if [[ -n "$artifact_path" ]]; then
        log "INFO" "$test_name" "artifact=$artifact_path"
    fi
}

run_cmd() {
    local key="$1"
    local command="$2"
    local outfile="$ARTIFACT_DIR/${key}.log"

    log "INFO" "$key" "CMD: $command" >&2
    bash -lc "$command" > "$outfile" 2>&1
    local code=$?
    log "INFO" "$key" "exit=$code" >&2
    echo "$code"
}

extract_codex_session_id() {
    local file="$1"
    grep -E '^session id:' "$file" | awk '{print $3}' | tail -n 1
}

extract_json_blob() {
    local file="$1"
    awk '
        BEGIN { capture = 0 }
        {
            if (capture == 0) {
                brace_pos = index($0, "{")
                if (brace_pos > 0) {
                    capture = 1
                    print substr($0, brace_pos)
                }
            } else {
                print $0
            }
        }
    ' "$file"
}

extract_json_field() {
    local file="$1"
    local field="$2"
    extract_json_blob "$file" | jq -r "$field // empty" 2>/dev/null | head -n 1
}

assert_tool_available() {
    local tool="$1"
    if command -v "$tool" >/dev/null 2>&1; then
        record_result "PASS" "tool_${tool}" "Tool available at $(command -v "$tool")" "0"
        return 0
    fi
    record_result "FAIL" "tool_${tool}" "Required tool not available: $tool" "127"
    return 1
}

write_json_report() {
    local overall
    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        overall="FAILED"
    else
        overall="PASSED"
    fi

    cat > "$JSON_FILE" <<EOF
{
  "test_suite": "ACFS Cross-Agent Resume E2E",
  "timestamp": "$(date -Iseconds)",
  "cross_resume_expectation": "$( [[ "$EXPECT_CROSS_RESUME" == "true" ]] && echo "strict" || echo "isolated" )",
  "log_file": "$LOG_FILE",
  "artifact_dir": "$ARTIFACT_DIR",
  "summary": {
    "total": $((PASS_COUNT + FAIL_COUNT + SKIP_COUNT)),
    "passed": $PASS_COUNT,
    "failed": $FAIL_COUNT,
    "skipped": $SKIP_COUNT,
    "result": "$overall"
  },
  "results": [
$(IFS=,; echo "${RESULTS_JSON[*]}" | sed 's/},{/},\
    {/g' | sed 's/^/    /')
  ]
}
EOF
    log "INFO" "report" "JSON report written to $JSON_FILE"
}

evaluate_cross_resume() {
    local test_name="$1"
    local tool_name="$2"
    local source_tool="$3"
    local exit_code="$4"
    local expected_session_id="$5"
    local observed_session_id="$6"
    local artifact_path="$7"

    if [[ "$EXPECT_CROSS_RESUME" == "true" ]]; then
        if [[ "$exit_code" -eq 0 && "$observed_session_id" == "$expected_session_id" ]]; then
            record_result "PASS" "$test_name" "$tool_name resumed ${source_tool} session id (strict mode)" "$exit_code" "$expected_session_id" "$observed_session_id" "$artifact_path"
        else
            record_result "FAIL" "$test_name" "$tool_name could not truly resume ${source_tool} session id (strict mode)" "$exit_code" "$expected_session_id" "$observed_session_id" "$artifact_path"
        fi
        return
    fi

    # Isolation mode (default): cross-CLI resume should NOT reuse the exact foreign session id.
    if [[ "$exit_code" -ne 0 ]]; then
        record_result "PASS" "$test_name" "$tool_name rejected ${source_tool} session id (expected CLI isolation)" "$exit_code" "$expected_session_id" "$observed_session_id" "$artifact_path"
    elif [[ "$observed_session_id" != "$expected_session_id" ]]; then
        record_result "PASS" "$test_name" "$tool_name isolated ${source_tool} session id (did not reuse foreign id)" "$exit_code" "$expected_session_id" "$observed_session_id" "$artifact_path"
    else
        record_result "FAIL" "$test_name" "$tool_name unexpectedly resumed ${source_tool} session id (cross-CLI interop changed)" "$exit_code" "$expected_session_id" "$observed_session_id" "$artifact_path"
    fi
}

main() {
    log "INFO" "start" "Cross-agent resume E2E started"
    log "INFO" "start" "Log file: $LOG_FILE"
    log "INFO" "start" "Artifact dir: $ARTIFACT_DIR"
    log "INFO" "start" "Self-resume baseline enabled: $INCLUDE_SELF_RESUME_BASELINE"
    if [[ "$EXPECT_CROSS_RESUME" == "true" ]]; then
        log "INFO" "start" "Cross-resume expectation: strict (foreign session ids must be reusable)"
    else
        log "INFO" "start" "Cross-resume expectation: isolated (foreign session ids should be rejected or remapped)"
    fi

    local has_preconditions=true
    for tool in timeout jq codex claude gemini; do
        if ! assert_tool_available "$tool"; then
            has_preconditions=false
        fi
    done

    if [[ "$has_preconditions" != "true" ]]; then
        write_json_report
        exit 1
    fi

    local COD_CREATE_LOG="$ARTIFACT_DIR/create_codex_session.log"
    local CLAUDE_CREATE_LOG="$ARTIFACT_DIR/create_claude_session.log"
    local GEMINI_CREATE_LOG="$ARTIFACT_DIR/create_gemini_session.log"

    local codex_id=""
    local claude_id=""
    local gemini_id=""

    local code

    code="$(run_cmd "create_codex_session" "timeout 120 codex exec --sandbox danger-full-access 'Respond with exactly READY-CODEX.'")"
    codex_id="$(extract_codex_session_id "$COD_CREATE_LOG")"
    if [[ "$code" -eq 0 && -n "$codex_id" ]] && grep -q 'READY-CODEX' "$COD_CREATE_LOG"; then
        record_result "PASS" "create_codex_session" "Created codex session successfully" "$code" "" "$codex_id" "$COD_CREATE_LOG"
    else
        record_result "FAIL" "create_codex_session" "Failed to create codex session" "$code" "" "$codex_id" "$COD_CREATE_LOG"
    fi

    code="$(run_cmd "create_claude_session" "timeout 120 claude -p --output-format json 'Respond with exactly READY-CLAUDE.'")"
    claude_id="$(extract_json_field "$CLAUDE_CREATE_LOG" '.session_id')"
    local claude_reply
    claude_reply="$(extract_json_field "$CLAUDE_CREATE_LOG" '.result')"
    if [[ "$code" -eq 0 && -n "$claude_id" && "$claude_reply" == READY-CLAUDE* ]]; then
        record_result "PASS" "create_claude_session" "Created claude session successfully" "$code" "" "$claude_id" "$CLAUDE_CREATE_LOG"
    else
        record_result "FAIL" "create_claude_session" "Failed to create claude session" "$code" "" "$claude_id" "$CLAUDE_CREATE_LOG"
    fi

    code="$(run_cmd "create_gemini_session" "timeout 120 gemini -p 'Respond with exactly READY-GEMINI.' --output-format json")"
    gemini_id="$(extract_json_field "$GEMINI_CREATE_LOG" '.session_id')"
    local gemini_reply
    gemini_reply="$(extract_json_field "$GEMINI_CREATE_LOG" '.response')"
    if [[ "$code" -eq 0 && -n "$gemini_id" && "$gemini_reply" == "READY-GEMINI" ]]; then
        record_result "PASS" "create_gemini_session" "Created gemini session successfully" "$code" "" "$gemini_id" "$GEMINI_CREATE_LOG"
    else
        record_result "FAIL" "create_gemini_session" "Failed to create gemini session" "$code" "" "$gemini_id" "$GEMINI_CREATE_LOG"
    fi

    local COD_SELF_LOG="$ARTIFACT_DIR/self_resume_codex.log"
    local CLAUDE_SELF_LOG="$ARTIFACT_DIR/self_resume_claude.log"
    local GEMINI_SELF_LOG="$ARTIFACT_DIR/self_resume_gemini.log"

    if [[ "$INCLUDE_SELF_RESUME_BASELINE" == "true" ]]; then
        if [[ -n "$codex_id" ]]; then
            code="$(run_cmd "self_resume_codex" "timeout 120 codex exec resume '$codex_id' 'Respond with exactly SELF-CODEX.'")"
            local codex_self_observed
            codex_self_observed="$(extract_codex_session_id "$COD_SELF_LOG")"
            if [[ "$code" -eq 0 && "$codex_self_observed" == "$codex_id" ]] && grep -q 'SELF-CODEX' "$COD_SELF_LOG"; then
                record_result "PASS" "self_resume_codex" "Codex resumed its own session" "$code" "$codex_id" "$codex_self_observed" "$COD_SELF_LOG"
            else
                record_result "FAIL" "self_resume_codex" "Codex did not resume its own session" "$code" "$codex_id" "$codex_self_observed" "$COD_SELF_LOG"
            fi
        else
            record_result "SKIP" "self_resume_codex" "Skipped because codex session creation failed" ""
        fi

        if [[ -n "$claude_id" ]]; then
            code="$(run_cmd "self_resume_claude" "timeout 120 claude -r '$claude_id' -p --output-format json 'Respond with exactly SELF-CLAUDE.'")"
            local claude_self_observed claude_self_reply
            claude_self_observed="$(extract_json_field "$CLAUDE_SELF_LOG" '.session_id')"
            claude_self_reply="$(extract_json_field "$CLAUDE_SELF_LOG" '.result')"
            if [[ "$code" -eq 0 && "$claude_self_observed" == "$claude_id" && "$claude_self_reply" == SELF-CLAUDE* ]]; then
                record_result "PASS" "self_resume_claude" "Claude resumed its own session" "$code" "$claude_id" "$claude_self_observed" "$CLAUDE_SELF_LOG"
            else
                record_result "FAIL" "self_resume_claude" "Claude did not resume its own session" "$code" "$claude_id" "$claude_self_observed" "$CLAUDE_SELF_LOG"
            fi
        else
            record_result "SKIP" "self_resume_claude" "Skipped because claude session creation failed" ""
        fi

        if [[ -n "$gemini_id" ]]; then
            code="$(run_cmd "self_resume_gemini" "timeout 120 gemini --resume '$gemini_id' -p 'Respond with exactly SELF-GEMINI.' --output-format json")"
            local gemini_self_observed gemini_self_reply
            gemini_self_observed="$(extract_json_field "$GEMINI_SELF_LOG" '.session_id')"
            gemini_self_reply="$(extract_json_field "$GEMINI_SELF_LOG" '.response')"
            if [[ "$code" -eq 0 && "$gemini_self_observed" == "$gemini_id" && "$gemini_self_reply" == "SELF-GEMINI" ]]; then
                record_result "PASS" "self_resume_gemini" "Gemini resumed its own session" "$code" "$gemini_id" "$gemini_self_observed" "$GEMINI_SELF_LOG"
            else
                record_result "FAIL" "self_resume_gemini" "Gemini did not resume its own session" "$code" "$gemini_id" "$gemini_self_observed" "$GEMINI_SELF_LOG"
            fi
        else
            record_result "SKIP" "self_resume_gemini" "Skipped because gemini session creation failed" ""
        fi
    else
        record_result "SKIP" "self_resume_codex" "Self-resume baseline disabled (set ACFS_INCLUDE_SELF_RESUME_BASELINE=true to enable)" ""
        record_result "SKIP" "self_resume_claude" "Self-resume baseline disabled (set ACFS_INCLUDE_SELF_RESUME_BASELINE=true to enable)" ""
        record_result "SKIP" "self_resume_gemini" "Self-resume baseline disabled (set ACFS_INCLUDE_SELF_RESUME_BASELINE=true to enable)" ""
    fi

    local CLAUDE_FROM_CODEX_LOG="$ARTIFACT_DIR/cross_resume_claude_from_codex.log"
    local CODEX_FROM_CLAUDE_LOG="$ARTIFACT_DIR/cross_resume_codex_from_claude.log"
    local CODEX_FROM_GEMINI_LOG="$ARTIFACT_DIR/cross_resume_codex_from_gemini.log"
    local GEMINI_FROM_CODEX_LOG="$ARTIFACT_DIR/cross_resume_gemini_from_codex.log"

    if [[ -n "$codex_id" ]]; then
        code="$(run_cmd "cross_resume_claude_from_codex" "timeout 120 claude -r '$codex_id' -p --output-format json 'Respond with exactly CROSS-CLAUDE-CODEX.'")"
        local claude_from_codex_observed
        claude_from_codex_observed="$(extract_json_field "$CLAUDE_FROM_CODEX_LOG" '.session_id')"
        evaluate_cross_resume "cross_resume_claude_from_codex" "Claude" "codex" "$code" "$codex_id" "$claude_from_codex_observed" "$CLAUDE_FROM_CODEX_LOG"
    else
        record_result "SKIP" "cross_resume_claude_from_codex" "Skipped because codex session creation failed" ""
    fi

    if [[ -n "$claude_id" ]]; then
        code="$(run_cmd "cross_resume_codex_from_claude" "timeout 120 codex exec resume '$claude_id' 'Respond with exactly CROSS-CODEX-CLAUDE.'")"
        local codex_from_claude_observed
        codex_from_claude_observed="$(extract_codex_session_id "$CODEX_FROM_CLAUDE_LOG")"
        evaluate_cross_resume "cross_resume_codex_from_claude" "Codex" "claude" "$code" "$claude_id" "$codex_from_claude_observed" "$CODEX_FROM_CLAUDE_LOG"
    else
        record_result "SKIP" "cross_resume_codex_from_claude" "Skipped because claude session creation failed" ""
    fi

    if [[ -n "$gemini_id" ]]; then
        code="$(run_cmd "cross_resume_codex_from_gemini" "timeout 120 codex exec resume '$gemini_id' 'Respond with exactly CROSS-CODEX-GEMINI.'")"
        local codex_from_gemini_observed
        codex_from_gemini_observed="$(extract_codex_session_id "$CODEX_FROM_GEMINI_LOG")"
        evaluate_cross_resume "cross_resume_codex_from_gemini" "Codex" "gemini" "$code" "$gemini_id" "$codex_from_gemini_observed" "$CODEX_FROM_GEMINI_LOG"
    else
        record_result "SKIP" "cross_resume_codex_from_gemini" "Skipped because gemini session creation failed" ""
    fi

    if [[ -n "$codex_id" ]]; then
        code="$(run_cmd "cross_resume_gemini_from_codex" "timeout 120 gemini --resume '$codex_id' -p 'Respond with exactly CROSS-GEMINI-CODEX.' --output-format json")"
        local gemini_from_codex_observed
        gemini_from_codex_observed="$(extract_json_field "$GEMINI_FROM_CODEX_LOG" '.session_id')"
        evaluate_cross_resume "cross_resume_gemini_from_codex" "Gemini" "codex" "$code" "$codex_id" "$gemini_from_codex_observed" "$GEMINI_FROM_CODEX_LOG"
    else
        record_result "SKIP" "cross_resume_gemini_from_codex" "Skipped because codex session creation failed" ""
    fi

    write_json_report

    log "INFO" "summary" "Passed=$PASS_COUNT Failed=$FAIL_COUNT Skipped=$SKIP_COUNT"
    log "INFO" "summary" "Text log: $LOG_FILE"
    log "INFO" "summary" "JSON report: $JSON_FILE"
    log "INFO" "summary" "Artifacts: $ARTIFACT_DIR"

    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
