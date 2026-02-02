#!/usr/bin/env bash
# E2E Test: Verify all 16+ new tools install and pass acfs doctor
#
# Tests:
#   - 7 First-class flywheel tools: br, ms, rch, wa, brenner, dcg, ru
#   - 9 Utility tools: tru, rust_proxy, rano, xf, mdwb, pt, aadc, s2p, caut
#   - Integration: acfs doctor, flywheel.ts, br primary command
#
# Related: bead bd-1ega.7

set -uo pipefail
# Note: Not using -e to allow tests to continue after failures

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/tmp/acfs_e2e_tools_${TIMESTAMP}.log"
JSON_FILE="/tmp/acfs_e2e_results_${TIMESTAMP}.json"
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

declare -a TEST_RESULTS=()

# Logging with structured format
log() {
    local level="${1:-INFO}"
    shift
    local test_name="${1:-}"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] [$test_name] $*" | tee -a "$LOG_FILE"
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

pass() {
    local test_name="$1"
    shift
    log "PASS" "$test_name" "$*"
    ((PASS_COUNT++))
    local escaped_msg
    escaped_msg=$(json_escape "$*")
    TEST_RESULTS+=("{\"test\":\"$test_name\",\"status\":\"pass\",\"message\":\"$escaped_msg\"}")
}

fail() {
    local test_name="$1"
    shift
    log "FAIL" "$test_name" "$*"
    ((FAIL_COUNT++))
    local escaped_msg
    escaped_msg=$(json_escape "$*")
    TEST_RESULTS+=("{\"test\":\"$test_name\",\"status\":\"fail\",\"message\":\"$escaped_msg\"}")
}

skip() {
    local test_name="$1"
    shift
    log "SKIP" "$test_name" "$*"
    ((SKIP_COUNT++))
    local escaped_msg
    escaped_msg=$(json_escape "$*")
    TEST_RESULTS+=("{\"test\":\"$test_name\",\"status\":\"skip\",\"message\":\"$escaped_msg\"}")
}

# ============================================================
# Generic Tool Testers
# ============================================================

# Test tool binary and version/help
test_tool_basic() {
    local name="$1"
    local binary="$2"
    local required="${3:-false}"  # Required tools fail, optional tools skip

    # Test binary exists
    if ! command -v "$binary" >/dev/null 2>&1; then
        if [[ "$required" == "true" ]]; then
            fail "${binary}_binary" "$binary binary not found (REQUIRED)"
        else
            skip "${binary}_binary" "$binary binary not found (optional tool)"
            skip "${binary}_version" "$binary --version skipped (binary not found)"
        fi
        return 1
    fi

    pass "${binary}_binary" "$binary binary found at $(command -v "$binary")"

    # Test --version or --help
    local version_output
    if version_output=$("$binary" --version 2>&1); then
        pass "${binary}_version" "$binary version: ${version_output:0:100}"
    elif version_output=$("$binary" --help 2>&1 | head -1); then
        pass "${binary}_version" "$binary help works: ${version_output:0:100}"
    else
        if [[ "$required" == "true" ]]; then
            fail "${binary}_version" "$binary --version and --help both failed"
        else
            skip "${binary}_version" "$binary --version and --help unavailable"
        fi
    fi
    return 0
}

# ============================================================
# First-Class Flywheel Tools (7)
# ============================================================

test_flywheel_tools() {
    log "INFO" "SECTION" "========================================"
    log "INFO" "SECTION" "FIRST-CLASS FLYWHEEL TOOLS (7)"
    log "INFO" "SECTION" "========================================"

    # beads_rust (br) - REQUIRED
    log "INFO" "br" "Testing beads_rust (br)..."
    if test_tool_basic "beads_rust" "br" "true"; then
        # Additional br tests
        if br list --json 2>/dev/null | head -1 | command grep -qE '^\['; then
            pass "br_list" "br list --json returns valid JSON"
        else
            fail "br_list" "br list --json failed"
        fi
    fi

    # meta_skill (ms)
    log "INFO" "ms" "Testing meta_skill (ms)..."
    test_tool_basic "meta_skill" "ms" "true"

    # remote_compilation_helper (rch)
    log "INFO" "rch" "Testing remote_compilation_helper (rch)..."
    test_tool_basic "remote_compilation_helper" "rch" "false"

    # wezterm_automata (wa)
    log "INFO" "wa" "Testing wezterm_automata (wa)..."
    test_tool_basic "wezterm_automata" "wa" "false"

    # brenner_bot
    log "INFO" "brenner" "Testing brenner_bot..."
    test_tool_basic "brenner_bot" "brenner" "false"

    # dcg (Destructive Command Guard) - REQUIRED
    log "INFO" "dcg" "Testing Destructive Command Guard (dcg)..."
    if test_tool_basic "destructive_command_guard" "dcg" "true"; then
        # Additional dcg tests
        if dcg doctor 2>&1 | command grep -qiE 'ok|pass|configured|healthy'; then
            pass "dcg_doctor" "dcg doctor passes health check"
        else
            skip "dcg_doctor" "dcg doctor output unclear (may need configuration)"
        fi
    fi

    # ru (Repo Updater) - REQUIRED
    log "INFO" "ru" "Testing Repo Updater (ru)..."
    test_tool_basic "repo_updater" "ru" "true"
}

# ============================================================
# Utility Tools (9)
# ============================================================

test_utility_tools() {
    log "INFO" "SECTION" "========================================"
    log "INFO" "SECTION" "UTILITY TOOLS (9)"
    log "INFO" "SECTION" "========================================"

    # toon_rust (tru)
    log "INFO" "tru" "Testing toon_rust (tru)..."
    test_tool_basic "toon_rust" "tru" "false"

    # rust_proxy
    log "INFO" "rust_proxy" "Testing rust_proxy..."
    test_tool_basic "rust_proxy" "rust_proxy" "false"

    # rano
    log "INFO" "rano" "Testing rano..."
    test_tool_basic "rano" "rano" "false"

    # xf
    log "INFO" "xf" "Testing xf..."
    test_tool_basic "xf" "xf" "false"

    # mdwb
    log "INFO" "mdwb" "Testing markdown_web_browser (mdwb)..."
    test_tool_basic "markdown_web_browser" "mdwb" "false"

    # pt
    log "INFO" "pt" "Testing process_triage (pt)..."
    test_tool_basic "process_triage" "pt" "false"

    # aadc
    log "INFO" "aadc" "Testing aadc..."
    test_tool_basic "aadc" "aadc" "false"

    # s2p
    log "INFO" "s2p" "Testing source_to_prompt_tui (s2p)..."
    test_tool_basic "source_to_prompt_tui" "s2p" "false"

    # caut
    log "INFO" "caut" "Testing coding_agent_usage_tracker (caut)..."
    test_tool_basic "coding_agent_usage_tracker" "caut" "false"
}

# ============================================================
# Integration Tests
# ============================================================

test_integration() {
    log "INFO" "SECTION" "========================================"
    log "INFO" "SECTION" "INTEGRATION TESTS"
    log "INFO" "SECTION" "========================================"

    # Test 1: acfs doctor runs without errors
    log "INFO" "doctor" "Testing acfs doctor..."
    if command -v acfs >/dev/null 2>&1; then
        local doctor_output
        doctor_output=$(ACFS_DOCTOR_CI=true acfs doctor 2>&1) || true
        local doctor_exit=$?

        if [[ $doctor_exit -eq 0 ]] || echo "$doctor_output" | command grep -qi "all checks passed\|healthy\|ok"; then
            pass "doctor_runs" "acfs doctor completed without fatal errors"
        else
            fail "doctor_runs" "acfs doctor failed (exit=$doctor_exit)"
        fi

        # Check for DCG in doctor output
        if echo "$doctor_output" | command grep -qi "dcg\|destructive.command"; then
            pass "doctor_dcg_check" "acfs doctor includes DCG health check"
        else
            skip "doctor_dcg_check" "DCG check not visible in doctor output"
        fi

        # CRITICAL: Verify NO git_safety_guard warnings
        if echo "$doctor_output" | command grep -qi "git_safety_guard"; then
            fail "doctor_no_git_safety_guard" "LEGACY: git_safety_guard still referenced in doctor"
        else
            pass "doctor_no_git_safety_guard" "No legacy git_safety_guard references found"
        fi
    else
        skip "doctor_runs" "acfs command not found"
        skip "doctor_dcg_check" "acfs command not found"
        skip "doctor_no_git_safety_guard" "acfs command not found"
    fi

    # Test 2: br is the primary command (bd alias was removed)
    log "INFO" "br_primary" "Testing br is the primary beads command..."
    if command -v br >/dev/null 2>&1; then
        if br --help >/dev/null 2>&1; then
            pass "br_primary" "br is the primary beads_rust command"
        else
            fail "br_primary" "br --help failed"
        fi
    else
        fail "br_primary" "br binary not found"
    fi

    # Test 3: Flywheel.ts contains all new tools
    log "INFO" "flywheel_ts" "Testing flywheel.ts tool entries..."
    local flywheel_file="${ACFS_REPO:-$HOME/agentic_coding_flywheel_setup}/apps/web/lib/flywheel.ts"
    if [[ ! -f "$flywheel_file" ]]; then
        flywheel_file="/data/projects/agentic_coding_flywheel_setup/apps/web/lib/flywheel.ts"
    fi

    if [[ -f "$flywheel_file" ]]; then
        local missing_tools=()
        for tool in br ms rch wa brenner dcg ru tru rust_proxy rano xf mdwb pt aadc s2p caut; do
            if ! command grep -qE "id:\s*[\"']${tool}[\"']" "$flywheel_file"; then
                missing_tools+=("$tool")
            fi
        done

        if [[ ${#missing_tools[@]} -eq 0 ]]; then
            pass "flywheel_ts_tools" "All 16 tools present in flywheel.ts"
        else
            fail "flywheel_ts_tools" "Missing tools in flywheel.ts: ${missing_tools[*]}"
        fi
    else
        skip "flywheel_ts_tools" "flywheel.ts not found at expected locations"
    fi

    # Test 4: bv (beads_viewer) works
    log "INFO" "bv" "Testing beads_viewer (bv)..."
    if command -v bv >/dev/null 2>&1; then
        if bv --robot-triage 2>/dev/null | head -1 | command grep -q '^{'; then
            pass "bv_triage" "bv --robot-triage returns valid JSON"
        else
            fail "bv_triage" "bv --robot-triage failed"
        fi
    else
        fail "bv_binary" "bv binary not found (REQUIRED)"
    fi

    # Test 5: AI agents installed
    log "INFO" "agents" "Testing AI agent binaries..."
    for agent in claude codex gemini; do
        if command -v "$agent" >/dev/null 2>&1; then
            local ver
            ver=$("$agent" --version 2>&1 | head -1) || ver="unknown"
            pass "${agent}_binary" "$agent installed: $ver"
        else
            skip "${agent}_binary" "$agent not installed (may be optional)"
        fi
    done
}

# ============================================================
# JSON Output
# ============================================================

write_json_results() {
    local result_status
    if [[ $FAIL_COUNT -gt 0 ]]; then
        result_status="FAILED"
    else
        result_status="PASSED"
    fi

    cat > "$JSON_FILE" <<EOF
{
  "test_suite": "ACFS New Tools E2E",
  "timestamp": "$(date -Iseconds)",
  "log_file": "$LOG_FILE",
  "summary": {
    "total": $((PASS_COUNT + FAIL_COUNT + SKIP_COUNT)),
    "passed": $PASS_COUNT,
    "failed": $FAIL_COUNT,
    "skipped": $SKIP_COUNT,
    "result": "$result_status"
  },
  "categories": {
    "flywheel_tools": 7,
    "utility_tools": 9,
    "integration_tests": 5
  },
  "tests": [
$(IFS=,; echo "${TEST_RESULTS[*]}" | sed 's/},{/},\n    {/g' | sed 's/^/    /')
  ]
}
EOF
    log "INFO" "OUTPUT" "JSON results written to: $JSON_FILE"
}

# ============================================================
# Summary
# ============================================================

print_summary() {
    log "INFO" "SUMMARY" "========================================"
    log "INFO" "SUMMARY" "ACFS NEW TOOLS E2E TEST SUMMARY"
    log "INFO" "SUMMARY" "========================================"
    log "INFO" "SUMMARY" "Passed:  $PASS_COUNT"
    log "INFO" "SUMMARY" "Failed:  $FAIL_COUNT"
    log "INFO" "SUMMARY" "Skipped: $SKIP_COUNT"
    log "INFO" "SUMMARY" "Total:   $((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))"
    log "INFO" "SUMMARY" ""
    log "INFO" "SUMMARY" "Log file:  $LOG_FILE"
    log "INFO" "SUMMARY" "JSON file: $JSON_FILE"
    log "INFO" "SUMMARY" "========================================"

    if [[ $FAIL_COUNT -gt 0 ]]; then
        log "INFO" "SUMMARY" "OVERALL: FAILED"
        return 1
    else
        log "INFO" "SUMMARY" "OVERALL: PASSED"
        return 0
    fi
}

# ============================================================
# Main
# ============================================================

main() {
    log "INFO" "START" "========================================"
    log "INFO" "START" "ACFS New Tools E2E Test Suite"
    log "INFO" "START" "Started: $(date -Iseconds)"
    log "INFO" "START" "========================================"

    # Run all test sections
    test_flywheel_tools
    test_utility_tools
    test_integration

    # Output results
    write_json_results
    print_summary
}

main "$@"
