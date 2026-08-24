#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Selection E2E Checks
#
# Validates that install.sh CLI flags properly interact with
# the selection engine and produce correct execution plans.
#
# These tests run without Docker - they validate the selection
# logic in isolation by using --print-plan and --list-modules.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test harness
source "$SCRIPT_DIR/lib/test_harness.sh"

harness_init "ACFS Selection E2E Checks"

# ============================================================
# Helper Functions
# ============================================================

run_install() {
    # Run install.sh with given args and capture output
    local output
    if output=$(bash "$REPO_ROOT/install.sh" "$@" 2>&1); then
        echo "$output"
        return 0
    else
        echo "$output"
        return 1
    fi
}

plan_contains() {
    local output="$1"
    local module="$2"
    echo "$output" | grep -qE "^  - $module$|^$module$|\[$module\]" 2>/dev/null
}

plan_not_contains() {
    local output="$1"
    local module="$2"
    ! plan_contains "$output" "$module"
}

# ============================================================
# Test: --list-modules
# ============================================================

harness_section "Test: --list-modules"

output=$(run_install --list-modules) || {
    harness_fail "--list-modules execution failed"
    harness_capture_output "list-modules-output" "$output"
}

if echo "$output" | grep -q "Available ACFS Modules"; then
    harness_pass "--list-modules shows header"
else
    harness_fail "--list-modules missing header" "Expected 'Available ACFS Modules'"
fi

if echo "$output" | grep -q "base.system"; then
    harness_pass "--list-modules includes base.system"
else
    harness_fail "--list-modules missing base.system"
fi

if echo "$output" | grep -q "agents.claude"; then
    harness_pass "--list-modules includes agents.claude"
else
    harness_fail "--list-modules missing agents.claude"
fi

# ============================================================
# Test: --print-plan (default selection)
# ============================================================

harness_section "Test: --print-plan (default selection)"

output=$(run_install --print-plan) || {
    harness_fail "--print-plan execution failed"
    harness_capture_output "print-plan-output" "$output"
}

if echo "$output" | grep -qE "ACFS Installation Plan|Execution Plan|Plan:"; then
    harness_pass "--print-plan shows plan header"
else
    harness_fail "--print-plan missing plan header"
fi

# Default selection should include enabled_by_default modules
if echo "$output" | grep -q "lang.bun"; then
    harness_pass "--print-plan includes lang.bun (default)"
else
    harness_fail "--print-plan missing lang.bun" "lang.bun should be enabled by default"
fi

if echo "$output" | grep -q "agents.claude"; then
    harness_pass "--print-plan includes agents.claude (default)"
else
    harness_fail "--print-plan missing agents.claude" "agents.claude should be enabled by default"
fi

# Default selection should NOT include disabled modules
if echo "$output" | grep -q "db.postgres18"; then
    harness_fail "--print-plan includes db.postgres18" "db.postgres18 should be disabled by default"
else
    harness_pass "--print-plan excludes db.postgres18 (not default)"
fi

# ============================================================
# Test: --print-plan determinism
# ============================================================

harness_section "Test: --print-plan determinism"

output1=$(run_install --print-plan) || true
output2=$(run_install --print-plan) || true

if [[ "$output1" == "$output2" ]]; then
    harness_pass "--print-plan produces deterministic output"
else
    harness_fail "--print-plan output differs between runs"
    harness_capture_output "print-plan-run1" "$output1"
    harness_capture_output "print-plan-run2" "$output2"
fi

# ============================================================
# Test: --only module
# ============================================================

harness_section "Test: --only module"

output=$(run_install --print-plan --only agents.codex) || {
    harness_fail "--only agents.codex execution failed"
    harness_capture_output "only-codex-output" "$output"
}

if echo "$output" | grep -q "agents.codex"; then
    harness_pass "--only agents.codex includes agents.codex"
else
    harness_fail "--only agents.codex missing agents.codex"
fi

# Should include dependencies
if echo "$output" | grep -q "lang.bun"; then
    harness_pass "--only agents.codex includes lang.bun (dependency)"
else
    harness_fail "--only agents.codex missing lang.bun" "lang.bun is a dependency"
fi

if echo "$output" | grep -q "base.system"; then
    harness_pass "--only agents.codex includes base.system (transitive dep)"
else
    harness_fail "--only agents.codex missing base.system" "base.system is a transitive dependency"
fi

# Should NOT include unrelated modules
if echo "$output" | grep -q "lang.rust"; then
    harness_fail "--only agents.codex includes lang.rust" "lang.rust should not be included"
else
    harness_pass "--only agents.codex excludes lang.rust"
fi

# ============================================================
# Test: --only with --no-deps
# ============================================================

harness_section "Test: --only with --no-deps"

output=$(run_install --print-plan --only agents.codex --no-deps 2>&1) || true

if echo "$output" | grep -q "agents.codex"; then
    harness_pass "--only --no-deps includes agents.codex"
else
    harness_fail "--only --no-deps missing agents.codex"
fi

# --no-deps should exclude dependencies
# Note: The plan may still work but without deps, or it might warn
if echo "$output" | grep -qiE "warning|no.deps"; then
    harness_pass "--no-deps produces warning"
else
    harness_info "--no-deps did not produce warning (may be expected)"
fi

# ============================================================
# Test: --skip module
# ============================================================

harness_section "Test: --skip module"

output=$(run_install --print-plan --skip tools.atuin) || {
    harness_fail "--skip tools.atuin execution failed"
    harness_capture_output "skip-atuin-output" "$output"
}

# Check that tools.atuin is NOT in the execution order (it may appear in "Skipped:" line)
if echo "$output" | grep -E "^\s+[0-9]+\.\s+.*tools\.atuin" >/dev/null; then
    harness_fail "--skip tools.atuin still in execution order"
else
    harness_pass "--skip tools.atuin excluded from execution order"
fi

# Verify the skip was acknowledged
if echo "$output" | grep -qiE "skip.*tools.atuin|tools.atuin.*skip"; then
    harness_pass "--skip tools.atuin acknowledged in output"
else
    harness_info "--skip tools.atuin not explicitly shown (may be expected)"
fi

# ============================================================
# Test: --only-phase
# ============================================================

harness_section "Test: --only-phase"

output=$(run_install --print-plan --only-phase 1) || {
    harness_fail "--only-phase 1 execution failed"
    harness_capture_output "only-phase-1-output" "$output"
}

if echo "$output" | grep -q "base.system"; then
    harness_pass "--only-phase 1 includes base.system"
else
    harness_fail "--only-phase 1 missing base.system" "base.system is phase 1"
fi

# Phase 1 should not include later-phase modules like agents
if echo "$output" | grep -q "agents.claude"; then
    harness_fail "--only-phase 1 includes agents.claude" "agents are not phase 1"
else
    harness_pass "--only-phase 1 excludes agents.claude"
fi

# ============================================================
# Test: Unknown module error
# ============================================================

harness_section "Test: Unknown module error"

output=$(run_install --print-plan --only nonexistent.module 2>&1) || true

if echo "$output" | grep -qiE "unknown|not found|invalid"; then
    harness_pass "--only unknown module produces error"
else
    harness_fail "--only unknown module should fail" "Expected error message"
    harness_capture_output "unknown-module-output" "$output"
fi

# ============================================================
# Test: Unknown phase error
# ============================================================

harness_section "Test: Unknown phase error"

output=$(run_install --print-plan --only-phase 99 2>&1) || true

if echo "$output" | grep -qiE "unknown|not found|invalid"; then
    harness_pass "--only-phase unknown produces error"
else
    harness_fail "--only-phase unknown should fail" "Expected error message"
    harness_capture_output "unknown-phase-output" "$output"
fi

# ============================================================
# Test: Skip dependency violation
# ============================================================

harness_section "Test: Skip dependency violation"

# Skipping a required dependency should fail
output=$(run_install --print-plan --only agents.codex --skip lang.bun 2>&1) || true

if echo "$output" | grep -qiE "error|dependency|required|violation|cannot skip"; then
    harness_pass "--skip required dependency produces error"
else
    harness_fail "--skip required dependency should fail" "Expected dependency error"
    harness_capture_output "skip-dep-violation-output" "$output"
fi

# ============================================================
# Test: Manifest index integrity
# ============================================================

harness_section "Test: Manifest index integrity"

MANIFEST_INDEX="$REPO_ROOT/scripts/generated/manifest_index.sh"

if [[ -f "$MANIFEST_INDEX" ]]; then
    harness_pass "manifest_index.sh exists"
else
    harness_fail "manifest_index.sh missing"
fi

# Check that it can be sourced without error
if bash -n "$MANIFEST_INDEX" 2>/dev/null; then
    harness_pass "manifest_index.sh syntax is valid"
else
    harness_fail "manifest_index.sh has syntax errors"
fi

# Check for expected content
if grep -q "ACFS_MANIFEST_SHA256" "$MANIFEST_INDEX"; then
    harness_pass "manifest_index.sh has ACFS_MANIFEST_SHA256"
else
    harness_fail "manifest_index.sh missing ACFS_MANIFEST_SHA256"
fi

if grep -q "ACFS_MODULES_IN_ORDER" "$MANIFEST_INDEX"; then
    harness_pass "manifest_index.sh has ACFS_MODULES_IN_ORDER"
else
    harness_fail "manifest_index.sh missing ACFS_MODULES_IN_ORDER"
fi

# ============================================================
# Test: Plan ordering respects dependencies
# ============================================================

harness_section "Test: Plan ordering"

output=$(run_install --print-plan --only stack.ultimate_bug_scanner) || {
    harness_fail "--only stack.ultimate_bug_scanner execution failed"
}

# Extract execution order numbers from the plan
# Format: "   1. [Phase 1] base.system -> acfs_generated_install_base_system()"
# Use more specific pattern to match module name after phase bracket
base_order=$(echo "$output" | grep -E "^\s+[0-9]+\.\s+\[Phase [0-9]+\] base\.system " | head -1 | awk '{print $1}' | tr -d '.')
bun_order=$(echo "$output" | grep -E "^\s+[0-9]+\.\s+\[Phase [0-9]+\] lang\.bun " | head -1 | awk '{print $1}' | tr -d '.')
ubs_order=$(echo "$output" | grep -E "^\s+[0-9]+\.\s+\[Phase [0-9]+\] stack\.ultimate_bug_scanner " | head -1 | awk '{print $1}' | tr -d '.')

if [[ -n "$base_order" && -n "$bun_order" && -n "$ubs_order" ]]; then
    if [[ $base_order -lt $bun_order && $bun_order -lt $ubs_order ]]; then
        harness_pass "Plan respects dependency order (base #$base_order < bun #$bun_order < ubs #$ubs_order)"
    else
        harness_fail "Plan order incorrect" "Expected base < bun < ubs, got #$base_order < #$bun_order < #$ubs_order"
    fi
else
    harness_warn "Could not verify plan order" "Missing modules: base=$base_order bun=$bun_order ubs=$ubs_order"
fi

# ============================================================
# Summary
# ============================================================

harness_summary
