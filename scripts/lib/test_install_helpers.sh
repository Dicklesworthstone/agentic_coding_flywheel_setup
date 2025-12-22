#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
# ============================================================
# Test script for install_helpers.sh selection logic
# Run: bash scripts/lib/test_install_helpers.sh
#
# Tests the acfs_resolve_selection function from install_helpers.sh
# which is the version actually used by install.sh.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source required files
source "$SCRIPT_DIR/logging.sh"
source "$PROJECT_ROOT/scripts/generated/manifest_index.sh"
source "$SCRIPT_DIR/install_helpers.sh"

TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    local name="$1"
    echo -e "\033[32m[PASS]\033[0m $name"
    ((++TESTS_PASSED))
}

test_fail() {
    local name="$1"
    local reason="${2:-}"
    echo -e "\033[31m[FAIL]\033[0m $name"
    [[ -n "$reason" ]] && echo "       Reason: $reason"
    ((++TESTS_FAILED))
}

# Reset selection state for each test
reset_selection() {
    ONLY_MODULES=()
    ONLY_PHASES=()
    SKIP_MODULES=()
    SKIP_TAGS=()
    SKIP_CATEGORIES=()
    NO_DEPS=false
    PRINT_PLAN=false

    # Clear effective arrays
    ACFS_EFFECTIVE_PLAN=()
    declare -gA ACFS_EFFECTIVE_RUN=()
    declare -gA ACFS_PLAN_REASON=()
    declare -gA ACFS_PLAN_EXCLUDE_REASON=()
}

reset_generated_flags() {
    unset ACFS_USE_GENERATED \
        ACFS_USE_GENERATED_BASE \
        ACFS_USE_GENERATED_USERS \
        ACFS_USE_GENERATED_SHELL \
        ACFS_USE_GENERATED_CLI \
        ACFS_USE_GENERATED_LANG \
        ACFS_USE_GENERATED_TOOLS \
        ACFS_USE_GENERATED_AGENTS \
        ACFS_USE_GENERATED_DB \
        ACFS_USE_GENERATED_CLOUD \
        ACFS_USE_GENERATED_STACK \
        ACFS_USE_GENERATED_ACFS
    ACFS_GENERATED_DEFAULT_CATEGORIES=()
}

# ============================================================
# Test Cases: Default Selection
# ============================================================

test_default_includes_enabled_modules() {
    local name="Default selection includes enabled_by_default modules"
    reset_selection

    if acfs_resolve_selection 2>/dev/null; then
        # Check that common default modules are included
        if should_run_module "lang.bun" && should_run_module "base.system"; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name"
}

test_default_excludes_disabled_modules() {
    local name="Default selection excludes disabled modules"
    reset_selection

    if acfs_resolve_selection 2>/dev/null; then
        # db.postgres18 and tools.vault are disabled by default
        if ! should_run_module "db.postgres18" && ! should_run_module "tools.vault"; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name"
}

# ============================================================
# Test Cases: --only Module Selection
# ============================================================

test_only_single_module() {
    local name="--only selects single module"
    reset_selection
    ONLY_MODULES=("agents.claude")

    if acfs_resolve_selection 2>/dev/null; then
        if should_run_module "agents.claude"; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name"
}

test_only_module_includes_deps() {
    local name="--only includes module dependencies"
    reset_selection
    ONLY_MODULES=("agents.claude")

    if acfs_resolve_selection 2>/dev/null; then
        # agents.claude depends on lang.bun which depends on base.system
        if should_run_module "lang.bun" && should_run_module "base.system"; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name"
}

test_only_excludes_unrelated() {
    local name="--only excludes unrelated modules"
    reset_selection
    ONLY_MODULES=("agents.claude")

    if acfs_resolve_selection 2>/dev/null; then
        # lang.rust and tools.atuin should not be included
        if ! should_run_module "lang.rust" && ! should_run_module "tools.atuin"; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name"
}

test_only_unknown_module_fails() {
    local name="--only with unknown module fails"
    reset_selection
    ONLY_MODULES=("nonexistent.module")

    if ! acfs_resolve_selection 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail for unknown module"
    fi
}

# ============================================================
# Test Cases: --only-phase Selection
# ============================================================

test_only_phase_selects_modules() {
    local name="--only-phase selects all modules in phase"
    reset_selection
    ONLY_PHASES=("6")  # Phase 6 has lang.* modules

    if acfs_resolve_selection 2>/dev/null; then
        if should_run_module "lang.bun" && should_run_module "lang.rust"; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name"
}

test_only_phase_includes_deps() {
    local name="--only-phase includes dependencies from other phases"
    reset_selection
    ONLY_PHASES=("6")  # Phase 6 modules depend on phase 1 (base.system)

    if acfs_resolve_selection 2>/dev/null; then
        if should_run_module "base.system"; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name"
}

test_only_phase_unknown_fails() {
    local name="--only-phase with unknown phase fails"
    reset_selection
    ONLY_PHASES=("99")

    if ! acfs_resolve_selection 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail for unknown phase"
    fi
}

# ============================================================
# Test Cases: --skip Module Exclusion
# ============================================================

test_skip_removes_module() {
    local name="--skip removes modules from plan"
    reset_selection
    SKIP_MODULES=("tools.atuin")

    if acfs_resolve_selection 2>/dev/null; then
        if ! should_run_module "tools.atuin"; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name"
}

test_skip_leaves_others() {
    local name="--skip leaves other modules"
    reset_selection
    SKIP_MODULES=("tools.atuin")

    if acfs_resolve_selection 2>/dev/null; then
        if should_run_module "lang.bun"; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name"
}

test_skip_dependency_fails() {
    local name="--skip on required dependency fails"
    reset_selection
    ONLY_MODULES=("agents.claude")
    SKIP_MODULES=("lang.bun")  # agents.claude requires lang.bun

    if ! acfs_resolve_selection 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail when skipping a required dependency"
    fi
}

test_skip_unknown_module_fails() {
    local name="--skip with unknown module fails"
    reset_selection
    SKIP_MODULES=("nonexistent.module")

    if ! acfs_resolve_selection 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail for unknown module"
    fi
}

# ============================================================
# Test Cases: --no-deps Flag
# ============================================================

test_no_deps_excludes_dependencies() {
    local name="--no-deps excludes dependencies"
    reset_selection
    ONLY_MODULES=("agents.claude")
    NO_DEPS=true

    if acfs_resolve_selection 2>/dev/null; then
        # With no-deps, should only have agents.claude, not its deps
        if should_run_module "agents.claude" && ! should_run_module "lang.bun"; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name"
}

test_no_deps_prints_warning() {
    local name="--no-deps prints prominent warning"
    reset_selection
    ONLY_MODULES=("agents.claude")
    NO_DEPS=true

    # Capture stderr to check for warning
    local output
    output=$(acfs_resolve_selection 2>&1)
    if [[ "$output" == *"WARNING"* ]] && [[ "$output" == *"no-deps"* || "$output" == *"dependency"* ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected warning about --no-deps"
    fi
}

# ============================================================
# Test Cases: Effective Plan Arrays
# ============================================================

test_effective_plan_populated() {
    local name="ACFS_EFFECTIVE_PLAN is populated"
    reset_selection
    ONLY_MODULES=("lang.bun")

    if acfs_resolve_selection 2>/dev/null; then
        if [[ ${#ACFS_EFFECTIVE_PLAN[@]} -gt 0 ]]; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name"
}

test_effective_run_membership() {
    local name="ACFS_EFFECTIVE_RUN provides O(1) membership check"
    reset_selection
    ONLY_MODULES=("lang.bun")

    if acfs_resolve_selection 2>/dev/null; then
        # Direct associative array access
        if [[ -n "${ACFS_EFFECTIVE_RUN[lang.bun]:-}" ]]; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name"
}

test_plan_reason_tracked() {
    local name="ACFS_PLAN_REASON tracks inclusion reasons"
    reset_selection
    ONLY_MODULES=("agents.claude")

    if acfs_resolve_selection 2>/dev/null; then
        local reason="${ACFS_PLAN_REASON[agents.claude]:-}"
        if [[ "$reason" == *"explicitly requested"* ]]; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name" "Expected 'explicitly requested' in reason"
}

test_exclude_reason_tracked() {
    local name="ACFS_PLAN_EXCLUDE_REASON tracks exclusion reasons"
    reset_selection
    ONLY_MODULES=("lang.bun")  # Only select lang.bun

    if acfs_resolve_selection 2>/dev/null; then
        # lang.rust should be excluded as "not selected"
        local reason="${ACFS_PLAN_EXCLUDE_REASON[lang.rust]:-}"
        if [[ -n "$reason" ]]; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name"
}

# ============================================================
# Test Cases: Plan Order
# ============================================================

test_plan_respects_dependency_order() {
    local name="Plan respects dependency order"
    reset_selection
    ONLY_MODULES=("stack.ultimate_bug_scanner")

    if acfs_resolve_selection 2>/dev/null; then
        # Find positions in plan
        local base_pos=-1 bun_pos=-1 ubs_pos=-1
        local i=0
        for module_id in "${ACFS_EFFECTIVE_PLAN[@]}"; do
            case "$module_id" in
                "base.system") base_pos=$i ;;
                "lang.bun") bun_pos=$i ;;
                "stack.ultimate_bug_scanner") ubs_pos=$i ;;
            esac
            ((++i))
        done

        # base < bun < ubs (dependencies before dependents)
        if [[ $base_pos -lt $bun_pos && $bun_pos -lt $ubs_pos ]]; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name"
}

# ============================================================
# Test Cases: Plan Determinism (--print-plan stability)
# ============================================================

test_plan_is_deterministic() {
    local name="Plan output is deterministic (stable across calls)"
    reset_selection
    ONLY_MODULES=("stack.mcp_agent_mail")

    # Run selection twice
    local plan1 plan2
    if acfs_resolve_selection 2>/dev/null; then
        plan1="${ACFS_EFFECTIVE_PLAN[*]}"
    else
        test_fail "$name" "First selection failed"
        return
    fi

    reset_selection
    ONLY_MODULES=("stack.mcp_agent_mail")
    if acfs_resolve_selection 2>/dev/null; then
        plan2="${ACFS_EFFECTIVE_PLAN[*]}"
    else
        test_fail "$name" "Second selection failed"
        return
    fi

    if [[ "$plan1" == "$plan2" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Plans differ: '$plan1' vs '$plan2'"
    fi
}

test_plan_does_not_mutate_state() {
    local name="Selection does not mutate global state (idempotent)"
    reset_selection
    ONLY_MODULES=("lang.bun")

    # Run once
    acfs_resolve_selection 2>/dev/null || true
    local count1="${#ACFS_EFFECTIVE_PLAN[@]}"

    # Run again without reset - should produce same result
    acfs_resolve_selection 2>/dev/null || true
    local count2="${#ACFS_EFFECTIVE_PLAN[@]}"

    if [[ "$count1" == "$count2" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Plan counts differ: $count1 vs $count2"
    fi
}

# ============================================================
# Test Cases: Legacy Flag Mapping (mjt.5.5)
# ============================================================

test_legacy_skip_postgres() {
    local name="--skip-postgres maps to SKIP_MODULES"
    reset_selection
    SKIP_POSTGRES=true

    acfs_apply_legacy_skips

    local found=false
    for module in "${SKIP_MODULES[@]}"; do
        if [[ "$module" == "db.postgres18" ]]; then
            found=true
            break
        fi
    done

    if [[ "$found" == "true" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "db.postgres18 not in SKIP_MODULES"
    fi
}

test_legacy_skip_vault() {
    local name="--skip-vault maps to SKIP_MODULES"
    reset_selection
    SKIP_VAULT=true

    acfs_apply_legacy_skips

    local found=false
    for module in "${SKIP_MODULES[@]}"; do
        if [[ "$module" == "tools.vault" ]]; then
            found=true
            break
        fi
    done

    if [[ "$found" == "true" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "tools.vault not in SKIP_MODULES"
    fi
}

test_legacy_skip_cloud() {
    local name="--skip-cloud maps to multiple cloud modules"
    reset_selection
    SKIP_CLOUD=true

    acfs_apply_legacy_skips

    local found_wrangler=false found_supabase=false found_vercel=false
    for module in "${SKIP_MODULES[@]}"; do
        case "$module" in
            "cloud.wrangler") found_wrangler=true ;;
            "cloud.supabase") found_supabase=true ;;
            "cloud.vercel") found_vercel=true ;;
        esac
    done

    if [[ "$found_wrangler" == "true" && "$found_supabase" == "true" && "$found_vercel" == "true" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Missing cloud modules in SKIP_MODULES"
    fi
}

test_legacy_flags_affect_selection() {
    local name="Legacy flags integrate with selection engine"
    reset_selection
    SKIP_VAULT=true

    acfs_apply_legacy_skips

    if acfs_resolve_selection 2>/dev/null; then
        # tools.vault should be excluded
        if ! should_run_module "tools.vault"; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name" "tools.vault should be excluded by legacy flag"
}

# ============================================================
# Test Cases: should_run_module Helper
# ============================================================

test_should_run_module_true() {
    local name="should_run_module returns true for included modules"
    reset_selection

    if acfs_resolve_selection 2>/dev/null; then
        if should_run_module "lang.bun"; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name"
}

test_should_run_module_false() {
    local name="should_run_module returns false for excluded modules"
    reset_selection

    if acfs_resolve_selection 2>/dev/null; then
        if ! should_run_module "db.postgres18"; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name"
}

# ============================================================
# Test Cases: Generated Category Flags (mjt.5.6)
# ============================================================

test_generated_defaults() {
    local name="Generated defaults honor ACFS_GENERATED_DEFAULT_CATEGORIES"
    reset_generated_flags
    ACFS_GENERATED_DEFAULT_CATEGORIES=("shell" "lang")

    if acfs_use_generated_category "shell" 2>/dev/null && ! acfs_use_generated_category "cloud" 2>/dev/null; then
        test_pass "$name"
        return
    fi
    test_fail "$name"
}

test_generated_global_override() {
    local name="Global ACFS_USE_GENERATED=0 forces legacy for all categories"
    reset_generated_flags
    ACFS_GENERATED_DEFAULT_CATEGORIES=("shell")
    ACFS_USE_GENERATED=0

    # Global=0 should disable even default categories
    if ! acfs_use_generated_category "shell" 2>/dev/null; then
        if ! acfs_use_generated_category "cloud" 2>/dev/null; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name"
}

test_generated_per_category_override() {
    local name="Per-category ACFS_USE_GENERATED_* overrides global"
    reset_generated_flags
    ACFS_USE_GENERATED=0
    ACFS_USE_GENERATED_SHELL=1

    if acfs_use_generated_category "shell" 2>/dev/null && ! acfs_use_generated_category "lang" 2>/dev/null; then
        test_pass "$name"
        return
    fi
    test_fail "$name"
}

# ============================================================
# Run Tests
# ============================================================

echo ""
echo "ACFS Install Helpers Selection Tests"
echo "====================================="
echo ""

# Default selection tests
test_default_includes_enabled_modules
test_default_excludes_disabled_modules

# --only module tests
test_only_single_module
test_only_module_includes_deps
test_only_excludes_unrelated
test_only_unknown_module_fails

# --only-phase tests
test_only_phase_selects_modules
test_only_phase_includes_deps
test_only_phase_unknown_fails

# --skip tests
test_skip_removes_module
test_skip_leaves_others
test_skip_dependency_fails
test_skip_unknown_module_fails

# --no-deps tests
test_no_deps_excludes_dependencies
test_no_deps_prints_warning

# Effective plan tests
test_effective_plan_populated
test_effective_run_membership
test_plan_reason_tracked
test_exclude_reason_tracked

# Plan order tests
test_plan_respects_dependency_order

# Plan determinism tests (--print-plan stability)
test_plan_is_deterministic
test_plan_does_not_mutate_state

# Legacy flag mapping tests (mjt.5.5)
test_legacy_skip_postgres
test_legacy_skip_vault
test_legacy_skip_cloud
test_legacy_flags_affect_selection

# should_run_module tests
test_should_run_module_true
test_should_run_module_false

# Generated category flag tests (mjt.5.6)
test_generated_defaults
test_generated_global_override
test_generated_per_category_override

echo ""
echo "====================================="
echo "Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"
echo ""

[[ $TESTS_FAILED -eq 0 ]]
