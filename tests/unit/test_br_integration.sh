#!/usr/bin/env bash
# Unit tests for beads_rust (br) integration
# Tests that br binary works and basic operations succeed

set -uo pipefail
# Note: Not using -e to allow tests to continue after failures

LOG_FILE="/tmp/br_integration_tests_$(date +%Y%m%d_%H%M%S).log"
PASS_COUNT=0
FAIL_COUNT=0

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }
pass() {
    log "PASS: $*"
    ((PASS_COUNT++))
}
fail() {
    log "FAIL: $*"
    ((FAIL_COUNT++))
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
    if br list --json 2>/dev/null | head -1 | grep -q '^\['; then
        pass "br list --json returns valid JSON array"
    else
        # Empty list is also valid
        if br list --json 2>/dev/null | head -1 | grep -q '^\[\]$'; then
            pass "br list --json returns empty array (no issues yet)"
        else
            fail "br list --json failed or returned invalid JSON"
        fi
    fi
}

# Test 5: br ready works
test_br_ready() {
    log "Test 5: br ready..."
    if br ready --json 2>/dev/null | head -1 | grep -qE '^\[|^$'; then
        pass "br ready --json works"
    else
        fail "br ready --json failed"
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
    if bv --robot-triage 2>/dev/null | head -1 | grep -q '^{'; then
        pass "bv --robot-triage returns valid JSON"
    else
        fail "bv --robot-triage failed or returned invalid JSON"
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
