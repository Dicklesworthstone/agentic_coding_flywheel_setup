#!/usr/bin/env bash
# ============================================================
# Unit tests for install.sh --pin-ref functionality
#
# Tests ref resolution to SHA and copy-pasteable command output.
#
# Run with: bash tests/unit/test_pin_ref.sh
#
# Related beads:
#   - bd-31ps.8.1: Installer pin-ref flag
#   - bd-31ps.8.3: Tests for pin-ref
# ============================================================

set -uo pipefail

# Get the absolute path to the scripts directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the test harness
source "$REPO_ROOT/tests/vm/lib/test_harness.sh"

# Log file
LOG_FILE="/tmp/acfs_pin_ref_test_$(date +%Y%m%d_%H%M%S).log"

# Redirect all output to log file as well
exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================================
# Test Cases
# ============================================================

test_pin_ref_flag_exists() {
    harness_section "Test: --pin-ref flag is recognized"

    # Check that the flag is parsed in install.sh source code
    if grep -qE '\-\-pin-ref|\-\-confirm-ref' "$REPO_ROOT/install.sh"; then
        harness_pass "--pin-ref flag is implemented in install.sh"
    else
        harness_fail "--pin-ref flag not found in install.sh"
    fi

    # Check that PIN_REF_MODE variable exists
    if grep -q 'PIN_REF_MODE' "$REPO_ROOT/install.sh"; then
        harness_pass "PIN_REF_MODE variable is defined"
    else
        harness_fail "PIN_REF_MODE variable not found"
    fi
}

test_pin_ref_resolves_main() {
    harness_section "Test: --pin-ref resolves main branch to SHA"

    local output
    output=$(ACFS_REF="main" bash "$REPO_ROOT/install.sh" --pin-ref 2>&1)
    local exit_code=$?

    harness_assert_eq "0" "$exit_code" "Exit code should be 0 for valid ref"

    # Check for SHA in output (should be 40 hex chars or 12-char short SHA)
    if echo "$output" | grep -qE '[a-f0-9]{12,40}'; then
        harness_pass "Output contains resolved SHA"
    else
        harness_fail "Output does not contain a resolved SHA"
        harness_capture_output "pin_ref_main_output" "$output"
        return 1
    fi

    # Check for copy-pasteable command
    if echo "$output" | grep -qE 'curl -fsSL.*--ref "[a-f0-9]{40}"'; then
        harness_pass "Output contains copy-pasteable pinned command"
    else
        harness_fail "Output missing copy-pasteable command"
        harness_capture_output "pin_ref_main_output" "$output"
        return 1
    fi

    harness_capture_output "pin_ref_main_output" "$output"
}

test_pin_ref_output_structure() {
    harness_section "Test: --pin-ref output has expected structure"

    local output
    output=$(bash "$REPO_ROOT/install.sh" --pin-ref 2>&1)

    # Check for expected sections
    local checks_passed=0
    local checks_total=5

    if echo "$output" | grep -q "ACFS Pinned Reference"; then
        harness_pass "Output has header"
        ((checks_passed++))
    else
        harness_fail "Missing header"
    fi

    if echo "$output" | grep -q "Requested ref:"; then
        harness_pass "Output shows requested ref"
        ((checks_passed++))
    else
        harness_fail "Missing requested ref"
    fi

    if echo "$output" | grep -q "Resolved SHA:"; then
        harness_pass "Output shows resolved SHA"
        ((checks_passed++))
    else
        harness_fail "Missing resolved SHA"
    fi

    if echo "$output" | grep -q "curl -fsSL"; then
        harness_pass "Output has curl command"
        ((checks_passed++))
    else
        harness_fail "Missing curl command"
    fi

    if echo "$output" | grep -q "Tip:"; then
        harness_pass "Output has tips section"
        ((checks_passed++))
    else
        harness_fail "Missing tips section"
    fi

    harness_capture_output "pin_ref_structure_output" "$output"

    if [[ $checks_passed -eq $checks_total ]]; then
        harness_pass "All $checks_total structure checks passed"
    else
        harness_fail "Only $checks_passed/$checks_total structure checks passed"
    fi
}

test_pin_ref_with_custom_ref() {
    harness_section "Test: --pin-ref works with custom ACFS_REF"

    # Use 'main' as a custom ref - it should always resolve
    local test_ref="main"

    local output
    output=$(ACFS_REF="$test_ref" bash "$REPO_ROOT/install.sh" --pin-ref 2>&1)
    local exit_code=$?

    harness_assert_eq "0" "$exit_code" "Exit code should be 0"

    # The output should show the ref we requested
    if echo "$output" | grep -qi "Requested ref:.*$test_ref"; then
        harness_pass "Output shows the requested ref"
    else
        harness_fail "Output does not show the requested ref"
        harness_capture_output "pin_ref_custom_output" "$output"
    fi

    # The resolved SHA should be different from the ref (it gets resolved)
    if echo "$output" | grep -qE 'Resolved SHA:.*[a-f0-9]{12}'; then
        harness_pass "Output shows resolved SHA"
    else
        harness_fail "Output does not show resolved SHA"
        harness_capture_output "pin_ref_custom_output" "$output"
    fi
}

test_pin_ref_invalid_ref() {
    harness_section "Test: --pin-ref handles invalid ref gracefully"

    local output
    output=$(ACFS_REF="invalid-nonexistent-ref-12345" bash "$REPO_ROOT/install.sh" --pin-ref 2>&1)
    local exit_code=$?

    # Should fail with non-zero exit code
    if [[ $exit_code -ne 0 ]]; then
        harness_pass "Exit code is non-zero for invalid ref"
    else
        harness_fail "Exit code should be non-zero for invalid ref"
    fi

    # Should show error message
    if echo "$output" | grep -qiE "error|could not resolve|invalid"; then
        harness_pass "Output contains error message"
    else
        harness_fail "Missing error message for invalid ref"
    fi

    harness_capture_output "pin_ref_invalid_output" "$output"
}

test_pin_ref_does_not_install() {
    harness_section "Test: --pin-ref exits without installing"

    # The --pin-ref flag should exit early without downloading/installing anything
    local start_time
    start_time=$(date +%s)

    local output
    output=$(timeout 30 bash "$REPO_ROOT/install.sh" --pin-ref 2>&1 || true)

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Should complete quickly (under 10 seconds, excluding network latency for SHA resolution)
    if [[ $duration -lt 15 ]]; then
        harness_pass "Completed quickly ($duration seconds)"
    else
        harness_fail "Took too long ($duration seconds) - might be doing installation"
    fi

    # Should not contain installation progress messages
    if echo "$output" | grep -qE 'Installing|Phase|downloading|Setting up'; then
        harness_fail "Output suggests installation was attempted"
        harness_capture_output "pin_ref_install_check" "$output"
    else
        harness_pass "No installation progress messages in output"
    fi
}

test_pin_ref_confirms_ref_alias() {
    harness_section "Test: --confirm-ref works as alias for --pin-ref"

    local output1 output2
    output1=$(bash "$REPO_ROOT/install.sh" --pin-ref 2>&1)
    output2=$(bash "$REPO_ROOT/install.sh" --confirm-ref 2>&1)

    # Both should have similar structure (same SHA may differ if repo updated between calls)
    if echo "$output1" | grep -q "ACFS Pinned Reference" && \
       echo "$output2" | grep -q "ACFS Pinned Reference"; then
        harness_pass "--confirm-ref produces same format as --pin-ref"
    else
        harness_fail "--confirm-ref output differs from --pin-ref"
        harness_capture_output "pin_ref_output" "$output1"
        harness_capture_output "confirm_ref_output" "$output2"
    fi
}

test_pinned_command_is_valid() {
    harness_section "Test: Generated pinned command has valid syntax"

    local output
    output=$(bash "$REPO_ROOT/install.sh" --pin-ref 2>&1)

    # Extract the curl command from output
    local curl_cmd
    curl_cmd=$(echo "$output" | grep 'curl -fsSL.*--ref' | head -1 | sed 's/^[[:space:]]*//')

    if [[ -z "$curl_cmd" ]]; then
        harness_fail "Could not extract curl command from output"
        harness_capture_output "pin_ref_full_output" "$output"
        return 1
    fi

    harness_pass "Extracted curl command: ${curl_cmd:0:80}..."

    # Verify command has required components
    if echo "$curl_cmd" | grep -qE 'curl -fsSL "https://'; then
        harness_pass "Command has proper curl flags"
    else
        harness_fail "Command missing proper curl flags"
    fi

    if echo "$curl_cmd" | grep -qE -- '--ref "[a-f0-9]{40}"'; then
        harness_pass "Command has full SHA in --ref"
    else
        harness_fail "Command missing full SHA in --ref"
    fi

    if echo "$curl_cmd" | grep -q 'bash -s -- --yes --mode vibe'; then
        harness_pass "Command has standard install flags"
    else
        harness_fail "Command missing standard install flags"
    fi
}

# ============================================================
# Main
# ============================================================

main() {
    harness_init "Pin Ref Unit Tests"

    harness_info "Log file: $LOG_FILE"

    # Run tests
    test_pin_ref_flag_exists
    test_pin_ref_resolves_main
    test_pin_ref_output_structure
    test_pin_ref_with_custom_ref
    test_pin_ref_invalid_ref
    test_pin_ref_does_not_install
    test_pin_ref_confirms_ref_alias
    test_pinned_command_is_valid

    # Summary
    harness_section "Test Summary"
    harness_info "Log written to: $LOG_FILE"

    harness_summary
}

main "$@"
