#!/usr/bin/env bash
# ============================================================
# Unit tests for doctor generated checks and fix suggestions
#
# Tests that doctor.sh properly integrates generated manifest
# checks and provides actionable fix suggestions.
#
# Run with: bash tests/unit/test_doctor_generated.sh
#
# Related beads:
#   - bd-31ps.5.1: Doctor: integrate generated checks
#   - bd-31ps.5.2: Doctor: per-module fix suggestions
#   - bd-31ps.5.3: Tests: doctor generated checks + hints
# ============================================================

set -uo pipefail

# Get the absolute path to the scripts directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the test harness
source "$REPO_ROOT/tests/vm/lib/test_harness.sh"

# Log file
LOG_FILE="/tmp/acfs_doctor_generated_test_$(date +%Y%m%d_%H%M%S).log"

# Redirect all output to log file as well
exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================================
# Test Cases
# ============================================================

test_generated_checks_file_exists() {
    harness_section "Test: Generated doctor_checks.sh exists"

    local checks_file="$REPO_ROOT/scripts/generated/doctor_checks.sh"
    if [[ -f "$checks_file" ]]; then
        harness_pass "doctor_checks.sh exists"
    else
        harness_fail "doctor_checks.sh not found at $checks_file"
        return 1
    fi

    # Check that it has MANIFEST_CHECKS array
    if grep -q 'declare -a MANIFEST_CHECKS=' "$checks_file"; then
        harness_pass "MANIFEST_CHECKS array is defined"
    else
        harness_fail "MANIFEST_CHECKS array not found"
        return 1
    fi

    # Count number of checks
    local check_count
    check_count=$(grep -c '^\s*"' "$checks_file" 2>/dev/null || echo "0")
    if [[ "$check_count" -gt 50 ]]; then
        harness_pass "MANIFEST_CHECKS has $check_count entries"
    else
        harness_fail "MANIFEST_CHECKS has too few entries ($check_count)"
    fi
}

test_doctor_sources_generated_checks() {
    harness_section "Test: doctor.sh sources generated checks"

    local doctor_file="$REPO_ROOT/scripts/lib/doctor.sh"

    # Check that doctor.sh loads the generated checks
    if grep -q 'doctor_checks.sh' "$doctor_file"; then
        harness_pass "doctor.sh references doctor_checks.sh"
    else
        harness_fail "doctor.sh does not reference doctor_checks.sh"
        return 1
    fi

    # Check for MANIFEST_CHECKS_LOADED variable
    if grep -q 'MANIFEST_CHECKS_LOADED' "$doctor_file"; then
        harness_pass "MANIFEST_CHECKS_LOADED tracking exists"
    else
        harness_fail "MANIFEST_CHECKS_LOADED tracking missing"
    fi
}

test_fix_suggestion_builder_exists() {
    harness_section "Test: Fix suggestion builder exists"

    local doctor_file="$REPO_ROOT/scripts/lib/doctor.sh"

    # Check for build_fix_suggestion function
    if grep -q 'build_fix_suggestion()' "$doctor_file"; then
        harness_pass "build_fix_suggestion function exists"
    else
        harness_fail "build_fix_suggestion function missing"
        return 1
    fi

    # Check for fix_for_module helper
    if grep -q 'fix_for_module()' "$doctor_file"; then
        harness_pass "fix_for_module helper exists"
    else
        harness_fail "fix_for_module helper missing"
    fi
}

test_fix_suggestion_format() {
    harness_section "Test: Fix suggestions have correct format"

    # Get fix suggestions from actual doctor JSON output (more realistic test)
    local output
    output=$(bash "$REPO_ROOT/scripts/lib/doctor.sh" --json 2>&1)

    # Extract a sample fix suggestion from the output
    local fix_output
    fix_output=$(echo "$output" | jq -r '[.checks[] | select(.fix)] | .[0].fix // empty' 2>/dev/null)

    if [[ -z "$fix_output" ]]; then
        harness_fail "No fix suggestions found in doctor output"
        harness_capture_output "doctor_output" "$output"
        return 1
    fi

    # Check fix output has expected components
    if echo "$fix_output" | grep -q 'curl -fsSL'; then
        harness_pass "Fix suggestion uses curl"
    else
        harness_fail "Fix suggestion missing curl"
        harness_capture_output "fix_output" "$fix_output"
        return 1
    fi

    if echo "$fix_output" | grep -q 'agent-flywheel.com/install'; then
        harness_pass "Fix suggestion uses correct URL"
    else
        harness_fail "Fix suggestion missing correct URL"
    fi

    if echo "$fix_output" | grep -q '\-\-yes'; then
        harness_pass "Fix suggestion has --yes flag"
    else
        harness_fail "Fix suggestion missing --yes flag"
    fi

    if echo "$fix_output" | grep -q '\-\-mode'; then
        harness_pass "Fix suggestion has --mode flag"
    else
        harness_fail "Fix suggestion missing --mode flag"
    fi

    # Check that fix suggestions include --only with a module ID pattern
    if echo "$fix_output" | grep -qE '\-\-only [a-z]+\.[a-z]+'; then
        harness_pass "Fix suggestion has --only with module ID"
    else
        harness_fail "Fix suggestion missing --only with module ID"
        harness_capture_output "fix_output" "$fix_output"
    fi
}

test_doctor_json_includes_fix_hints() {
    harness_section "Test: Doctor JSON output includes fix hints"

    local output
    output=$(bash "$REPO_ROOT/scripts/lib/doctor.sh" --json 2>&1)
    local exit_code=$?

    # Check JSON is valid
    if echo "$output" | jq -e '.' >/dev/null 2>&1; then
        harness_pass "Doctor JSON output is valid"
    else
        harness_fail "Doctor JSON output is invalid"
        harness_capture_output "doctor_json_output" "$output"
        return 1
    fi

    # Check that checks array exists
    local check_count
    check_count=$(echo "$output" | jq '.checks | length' 2>/dev/null)
    if [[ "$check_count" -gt 30 ]]; then
        harness_pass "Doctor reports $check_count checks"
    else
        harness_fail "Doctor reports too few checks ($check_count)"
    fi

    # Check that at least some checks have fix hints
    local fix_count
    fix_count=$(echo "$output" | jq '[.checks[] | select(.fix)] | length' 2>/dev/null)
    if [[ "$fix_count" -gt 0 ]]; then
        harness_pass "Doctor includes $fix_count fix hints"
    else
        harness_fail "Doctor includes no fix hints"
    fi
}

test_failed_checks_have_fix_hints() {
    harness_section "Test: Failed checks have fix hints"

    local output
    output=$(bash "$REPO_ROOT/scripts/lib/doctor.sh" --json 2>&1)

    # Get failed checks
    local failed_checks
    failed_checks=$(echo "$output" | jq '[.checks[] | select(.status == "fail")]' 2>/dev/null)

    local failed_count
    failed_count=$(echo "$failed_checks" | jq 'length' 2>/dev/null || echo "0")

    if [[ "$failed_count" -eq 0 ]]; then
        harness_pass "No failed checks (all passing) - cannot test fix hints"
        return 0
    fi

    # Check that failed checks have fix hints
    local failed_with_fix
    failed_with_fix=$(echo "$failed_checks" | jq '[.[] | select(.fix)] | length' 2>/dev/null || echo "0")

    if [[ "$failed_with_fix" -eq "$failed_count" ]]; then
        harness_pass "All $failed_count failed checks have fix hints"
    else
        harness_fail "$failed_with_fix of $failed_count failed checks have fix hints"
        harness_capture_output "failed_checks" "$failed_checks"
    fi
}

test_warn_checks_have_fix_hints() {
    harness_section "Test: Warning checks have fix hints"

    local output
    output=$(bash "$REPO_ROOT/scripts/lib/doctor.sh" --json 2>&1)

    # Get warning checks
    local warn_checks
    warn_checks=$(echo "$output" | jq '[.checks[] | select(.status == "warn")]' 2>/dev/null)

    local warn_count
    warn_count=$(echo "$warn_checks" | jq 'length' 2>/dev/null || echo "0")

    if [[ "$warn_count" -eq 0 ]]; then
        harness_pass "No warning checks - cannot test fix hints"
        return 0
    fi

    # Check that warning checks have fix hints
    local warn_with_fix
    warn_with_fix=$(echo "$warn_checks" | jq '[.[] | select(.fix)] | length' 2>/dev/null || echo "0")

    if [[ "$warn_with_fix" -ge "$((warn_count / 2))" ]]; then
        harness_pass "$warn_with_fix of $warn_count warning checks have fix hints"
    else
        harness_fail "Only $warn_with_fix of $warn_count warning checks have fix hints"
        harness_capture_output "warn_checks" "$warn_checks"
    fi
}

test_fix_hint_uses_module_id() {
    harness_section "Test: Fix hints use correct module IDs"

    local output
    output=$(bash "$REPO_ROOT/scripts/lib/doctor.sh" --json 2>&1)

    # Sample a few checks and verify fix hints reference their module
    local samples
    samples=$(echo "$output" | jq -r '.checks[] | select(.fix and .id) | "\(.id)|\(.fix)"' 2>/dev/null | head -5)

    local checks_passed=0
    local checks_total=0

    while IFS='|' read -r check_id fix_hint; do
        [[ -z "$check_id" ]] && continue
        ((checks_total++))

        # Extract module ID from check ID (strip trailing .N suffix)
        local module_id
        module_id=$(echo "$check_id" | sed 's/\.[0-9]*$//')

        if echo "$fix_hint" | grep -q "\-\-only $module_id"; then
            ((checks_passed++))
        fi
    done <<< "$samples"

    if [[ "$checks_total" -eq 0 ]]; then
        harness_pass "No checks with fix hints to verify"
    elif [[ "$checks_passed" -eq "$checks_total" ]]; then
        harness_pass "All $checks_total sampled fix hints use correct module IDs"
    else
        harness_fail "Only $checks_passed of $checks_total fix hints use correct module IDs"
    fi
}

test_manifest_checks_have_required_fields() {
    harness_section "Test: Manifest checks have required fields"

    local checks_file="$REPO_ROOT/scripts/generated/doctor_checks.sh"

    # Extract first 5 checks and verify format
    local sample_checks
    sample_checks=$(grep -E '^\s+"[a-z]' "$checks_file" | head -5)

    local valid=0
    local total=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ((total++))

        # Expected format: "id<TAB>description<TAB>command<TAB>required/optional"
        # Check for at least 3 tabs (4 fields)
        local tab_count
        tab_count=$(echo "$line" | tr -cd '\t' | wc -c)
        if [[ "$tab_count" -ge 3 ]]; then
            ((valid++))
        fi
    done <<< "$sample_checks"

    if [[ "$valid" -eq "$total" ]]; then
        harness_pass "All $total sampled manifest checks have correct format"
    else
        harness_fail "Only $valid of $total manifest checks have correct format"
    fi
}

test_doctor_summary_counts() {
    harness_section "Test: Doctor summary has correct counts"

    local output
    output=$(bash "$REPO_ROOT/scripts/lib/doctor.sh" --json 2>&1)

    # Get summary counts
    local pass_count warn_count fail_count
    pass_count=$(echo "$output" | jq '.summary.pass // 0' 2>/dev/null)
    warn_count=$(echo "$output" | jq '.summary.warn // 0' 2>/dev/null)
    fail_count=$(echo "$output" | jq '.summary.fail // 0' 2>/dev/null)

    # Calculate expected totals from checks array
    local calc_pass calc_warn calc_fail
    calc_pass=$(echo "$output" | jq '[.checks[] | select(.status == "pass")] | length' 2>/dev/null)
    calc_warn=$(echo "$output" | jq '[.checks[] | select(.status == "warn")] | length' 2>/dev/null)
    calc_fail=$(echo "$output" | jq '[.checks[] | select(.status == "fail")] | length' 2>/dev/null)

    if [[ "$pass_count" -eq "$calc_pass" ]]; then
        harness_pass "Pass count matches: $pass_count"
    else
        harness_fail "Pass count mismatch: summary=$pass_count calculated=$calc_pass"
    fi

    if [[ "$warn_count" -eq "$calc_warn" ]]; then
        harness_pass "Warn count matches: $warn_count"
    else
        harness_fail "Warn count mismatch: summary=$warn_count calculated=$calc_warn"
    fi

    if [[ "$fail_count" -eq "$calc_fail" ]]; then
        harness_pass "Fail count matches: $fail_count"
    else
        harness_fail "Fail count mismatch: summary=$fail_count calculated=$calc_fail"
    fi
}

test_meta_skill_arm64_linux_guidance() {
    harness_section "Test: meta_skill ARM64 Linux guidance is specific"

    local doctor_file arm64_branch
    doctor_file="$REPO_ROOT/scripts/lib/doctor.sh"
    arm64_branch="$(sed -n '/aarch64-Linux|arm64-Linux)/,/;;/p' "$doctor_file")"

    if [[ -z "$arm64_branch" ]]; then
        harness_fail "meta_skill ARM64 Linux branch is missing from doctor.sh"
        return 1
    fi

    if echo "$arm64_branch" | grep -q 'ARM64 Linux binary not yet available (see https://github.com/Dicklesworthstone/meta_skill/issues/1)'; then
        harness_pass "meta_skill ARM64 Linux warning includes the upstream issue link"
    else
        harness_fail "meta_skill ARM64 Linux warning is missing the specific upstream guidance"
        harness_capture_output "meta_skill_arm64_branch" "$arm64_branch"
    fi

    if echo "$arm64_branch" | grep -q 'Build from source: cargo install --git https://github.com/Dicklesworthstone/meta_skill --force'; then
        harness_pass "meta_skill ARM64 Linux fix uses the source-build fallback"
    else
        harness_fail "meta_skill ARM64 Linux fix hint is incorrect"
        harness_capture_output "meta_skill_arm64_branch" "$arm64_branch"
    fi

    if echo "$arm64_branch" | grep -q 'curl -fsSL'; then
        harness_fail "meta_skill ARM64 Linux branch still suggests the raw installer path"
        harness_capture_output "meta_skill_arm64_branch" "$arm64_branch"
    else
        harness_pass "meta_skill ARM64 Linux branch avoids the raw installer path"
    fi
}

# ============================================================
# Main
# ============================================================

main() {
    harness_init "Doctor Generated Checks Tests"

    harness_info "Log file: $LOG_FILE"

    # Run tests
    test_generated_checks_file_exists
    test_doctor_sources_generated_checks
    test_fix_suggestion_builder_exists
    test_fix_suggestion_format
    test_doctor_json_includes_fix_hints
    test_failed_checks_have_fix_hints
    test_warn_checks_have_fix_hints
    test_fix_hint_uses_module_id
    test_manifest_checks_have_required_fields
    test_doctor_summary_counts
    test_meta_skill_arm64_linux_guidance

    # Summary
    harness_section "Test Summary"
    harness_info "Log written to: $LOG_FILE"

    harness_summary
}

main "$@"
