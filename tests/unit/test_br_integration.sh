#!/usr/bin/env bash
# Unit tests for beads_rust (br) integration
# Tests that br binary works and basic operations succeed

set -uo pipefail
# Note: Not using -e to allow tests to continue after failures

LOG_FILE="/tmp/br_integration_tests_$(date +%Y%m%d_%H%M%S).log"
PASS_COUNT=0
FAIL_COUNT=0
TEST_TIMEOUT_SECONDS="${TEST_TIMEOUT_SECONDS:-10}"
PROBE_DIR=""

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }
pass() {
    log "PASS: $*"
    ((PASS_COUNT++))
}
fail() {
    log "FAIL: $*"
    ((FAIL_COUNT++))
}

run_probe_command() {
    (cd "$PROBE_DIR" && timeout "$TEST_TIMEOUT_SECONDS" "$@")
}

ensure_probe_workspace() {
    if [[ -n "$PROBE_DIR" && -d "$PROBE_DIR" ]]; then
        return 0
    fi

    PROBE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/acfs_br_integration.XXXXXX")
    if [[ -z "$PROBE_DIR" || ! -d "$PROBE_DIR" ]]; then
        log "Probe workspace setup failed: mktemp did not create a directory"
        return 1
    fi

    if ! run_probe_command br init >/dev/null 2>>"$LOG_FILE"; then
        log "Probe workspace setup failed: br init timed out or exited non-zero"
        return 1
    fi

    if ! run_probe_command br create "Integration test probe issue" --type task --priority 4 >/dev/null 2>>"$LOG_FILE"; then
        log "Probe workspace setup failed: br create timed out or exited non-zero"
        return 1
    fi

    return 0
}

report_probe_failure() {
    local label="$1"
    local rc="$2"
    local output="$3"

    if [[ "$rc" -eq 124 ]]; then
        fail "$label timed out after ${TEST_TIMEOUT_SECONDS}s"
    else
        fail "$label failed in isolated workspace ${PROBE_DIR}: ${output:-<no stdout>}"
    fi
}

# Test 1: br binary exists
test_br_binary() {
    log "Test 1: br binary availability..."
    if command -v br >/dev/null 2>&1; then
        pass "br binary found at $(which br)"
    else
        fail "br binary not found in PATH"
    fi
}

# Test 2: br --version works
test_br_version() {
    log "Test 2: br --version..."
    local version
    if version=$(br --version 2>&1); then
        if [[ "$version" =~ beads_rust|br ]]; then
            pass "br version: $version"
        else
            fail "Unexpected version format: $version"
        fi
    else
        fail "br --version failed"
    fi
}

# Test 3: br is the primary command (bd alias removed)
test_br_primary() {
    log "Test 3: br is the primary beads command..."
    # Confirm br works as primary command
    if br --help >/dev/null 2>&1; then
        pass "br is the primary beads_rust command"
    else
        fail "br --help failed"
    fi
}

# Test 4: br list works
test_br_list() {
    log "Test 4: br list..."
    local output rc
    if ! ensure_probe_workspace; then
        fail "br list probe workspace setup failed"
        return
    fi

    output=$(run_probe_command br list --json 2>>"$LOG_FILE")
    rc=$?
    if [[ "$rc" -eq 0 ]] && jq -e '
        if type == "array" then
            any(.[]?; .title == "Integration test probe issue")
        elif type == "object" then
            (.issues | type == "array") and any(.issues[]?; .title == "Integration test probe issue")
        else
            false
        end
    ' <<<"$output" >/dev/null 2>&1; then
        pass "br list --json returns the probe issue in isolated workspace"
    else
        report_probe_failure "br list --json" "$rc" "$output"
    fi
}

# Test 5: br ready works
test_br_ready() {
    log "Test 5: br ready..."
    local output rc
    if ! ensure_probe_workspace; then
        fail "br ready probe workspace setup failed"
        return
    fi

    output=$(run_probe_command br ready --json 2>>"$LOG_FILE")
    rc=$?
    if [[ "$rc" -eq 0 ]] && jq -e 'type == "array"' <<<"$output" >/dev/null 2>&1; then
        pass "br ready --json returns valid JSON array in isolated workspace"
    else
        report_probe_failure "br ready --json" "$rc" "$output"
    fi
}

# Test 6: bv binary exists
test_bv_binary() {
    log "Test 6: bv binary availability..."
    if command -v bv >/dev/null 2>&1; then
        pass "bv (beads_viewer) binary found at $(which bv)"
    else
        fail "bv binary not found in PATH"
    fi
}

# Test 7: bv --robot-triage works
test_bv_robot_triage() {
    log "Test 7: bv --robot-triage..."
    local output rc
    if ! ensure_probe_workspace; then
        fail "bv probe workspace setup failed"
        return
    fi

    output=$(run_probe_command bv --robot-triage 2>>"$LOG_FILE")
    rc=$?
    if [[ "$rc" -eq 0 ]] && jq -e 'type == "object"' <<<"$output" >/dev/null 2>&1; then
        pass "bv --robot-triage returns valid JSON in isolated workspace"
    else
        report_probe_failure "bv --robot-triage" "$rc" "$output"
    fi
}

# Summary
print_summary() {
    log ""
    log "========================================"
    log "TEST SUMMARY"
    log "========================================"
    log "Passed: $PASS_COUNT"
    log "Failed: $FAIL_COUNT"
    log "Total:  $((PASS_COUNT + FAIL_COUNT))"
    log "Log file: $LOG_FILE"
    log "========================================"

    if [[ $FAIL_COUNT -gt 0 ]]; then
        log "OVERALL: FAILED"
        return 1
    else
        log "OVERALL: PASSED"
        return 0
    fi
}

# Run all tests
main() {
    log "========================================"
    log "beads_rust (br) Integration Tests"
    log "========================================"
    log ""

    test_br_binary
    test_br_version
    test_br_primary
    test_br_list
    test_br_ready
    test_bv_binary
    test_bv_robot_triage

    print_summary
}

main "$@"
