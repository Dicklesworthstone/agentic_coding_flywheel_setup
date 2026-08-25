#!/usr/bin/env bash
# ============================================================
# ACFS - Unit Tests for Interactive Module Selector (bd-l56ty)
# ============================================================

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$REPO_ROOT/scripts/lib"

# shellcheck source=scripts/lib/logging.sh
source "$SCRIPT_DIR/logging.sh"
# shellcheck source=scripts/lib/install_helpers.sh
source "$SCRIPT_DIR/install_helpers.sh"
# shellcheck source=scripts/lib/module_selector.sh
source "$SCRIPT_DIR/module_selector.sh"

TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo "PASS: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo "FAIL: $1"
    echo "  Reason: $2"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

reset_selection_env() {
    ONLY_MODULES=()
    ONLY_PHASES=()
    SKIP_MODULES=()
    SKIP_TAGS=()
    SKIP_CATEGORIES=()
    NO_DEPS=false
    MODE="vibe"
    YES_MODE=false
    ACFS_SELECTED_PROFILE=""
    ACFS_CLI_PROFILE=""
    ACFS_INTERACTIVE=false
    ACFS_EXPLICIT_TARGETED_SELECTION=false
    export ONLY_MODULES ONLY_PHASES SKIP_MODULES SKIP_TAGS SKIP_CATEGORIES NO_DEPS MODE YES_MODE ACFS_SELECTED_PROFILE ACFS_CLI_PROFILE ACFS_INTERACTIVE ACFS_EXPLICIT_TARGETED_SELECTION
}

test_profile_application_replaces_derived_selectors() {
    source_manifest_index
    reset_selection_env

    acfs_apply_profile "minimal" || { fail "profile_state_transition" "minimal profile failed"; return 1; }
    acfs_apply_profile "cloud-only" || { fail "profile_state_transition" "cloud-only profile failed"; return 1; }

    [[ " ${ONLY_MODULES[*]} " == *" cloud.wrangler "* ]] \
        || { fail "profile_state_transition" "cloud selector missing after transition"; return 1; }
    [[ " ${ONLY_MODULES[*]} " != *" agents.claude "* ]] \
        || { fail "profile_state_transition" "minimal selector leaked into cloud-only"; return 1; }

    pass "profile_application_replaces_derived_selectors"
}

test_selector_profile_rejects_explicit_only() {
    source_manifest_index
    reset_selection_env
    ONLY_MODULES=("agents.codex")
    ACFS_EXPLICIT_TARGETED_SELECTION=true

    local output status=0
    output="$(acfs_apply_profile "minimal" 2>&1)" || status=$?
    [[ "$status" -ne 0 ]] \
        || { fail "selector_profile_rejects_explicit_only" "conflicting profile was accepted"; return 1; }
    [[ "$output" == *"cannot be combined"* ]] \
        || { fail "selector_profile_rejects_explicit_only" "missing conflict explanation"; return 1; }

    pass "selector_profile_rejects_explicit_only"
}

test_all_canonical_profiles_apply_successfully() {
    source_manifest_index

    local profile=""
    for profile in "${ACFS_PROFILES_IN_ORDER[@]}"; do
        reset_selection_env
        if ! acfs_apply_profile "$profile"; then
            fail "all_canonical_profiles_apply_successfully" "Failed to apply profile: $profile"
            return 1
        fi
        if ! acfs_resolve_selection; then
            fail "all_canonical_profiles_apply_successfully" "Failed to resolve selection for profile: $profile"
            return 1
        fi
        if [[ "${#ACFS_EFFECTIVE_PLAN[@]}" -eq 0 ]]; then
            fail "all_canonical_profiles_apply_successfully" "Effective plan is empty for profile: $profile"
            return 1
        fi
    done

    pass "all_canonical_profiles_apply_successfully"
}

test_unknown_profile_fails_cleanly() {
    source_manifest_index
    reset_selection_env

    local output status=0
    output="$(acfs_apply_profile "invalid-profile-xyz" 2>&1)" || status=$?

    if [[ "$status" -eq 0 ]]; then
        fail "unknown_profile_fails_cleanly" "Expected failure for unknown profile, got status 0"
        return 1
    fi

    if [[ "$output" != *"Unknown profile id: invalid-profile-xyz"* ]]; then
        fail "unknown_profile_fails_cleanly" "Expected unknown profile error message, got: $output"
        return 1
    fi

    pass "unknown_profile_fails_cleanly"
}

test_minimal_profile_selects_expected_essentials() {
    source_manifest_index
    reset_selection_env

    acfs_apply_profile "minimal"
    acfs_resolve_selection

    # Minimal profile should include essentials like ntm, ubs, beads_rust, claude, codex, agy
    should_run_module "stack.ntm" || { fail "minimal_profile_selects_expected_essentials" "Missing stack.ntm"; return 1; }
    should_run_module "stack.ultimate_bug_scanner" || { fail "minimal_profile_selects_expected_essentials" "Missing stack.ultimate_bug_scanner"; return 1; }
    should_run_module "stack.beads_rust" || { fail "minimal_profile_selects_expected_essentials" "Missing stack.beads_rust"; return 1; }
    should_run_module "agents.antigravity" || { fail "minimal_profile_selects_expected_essentials" "Missing agents.antigravity"; return 1; }

    # Core locked modules should be automatically resolved as dependencies
    should_run_module "base.system" || { fail "minimal_profile_selects_expected_essentials" "Missing base.system dependency"; return 1; }
    should_run_module "shell.omz" || { fail "minimal_profile_selects_expected_essentials" "Missing shell.omz dependency"; return 1; }

    # Optional cloud modules should not be in minimal profile
    if should_run_module "cloud.supabase"; then
        fail "minimal_profile_selects_expected_essentials" "cloud.supabase should not be in minimal profile"
        return 1
    fi

    pass "minimal_profile_selects_expected_essentials"
}

test_agents_only_profile_expands_dependencies_correctly() {
    source_manifest_index
    reset_selection_env

    acfs_apply_profile "agents-only"
    acfs_resolve_selection

    # All default agents should be included
    should_run_module "agents.claude" || { fail "agents_only_profile" "Missing agents.claude"; return 1; }
    should_run_module "agents.codex" || { fail "agents_only_profile" "Missing agents.codex"; return 1; }
    should_run_module "agents.antigravity" || { fail "agents_only_profile" "Missing agents.antigravity"; return 1; }

    # Dependencies of agents (like lang.bun, base.system) must be satisfied
    should_run_module "lang.bun" || { fail "agents_only_profile" "Missing dependency lang.bun"; return 1; }
    should_run_module "base.system" || { fail "agents_only_profile" "Missing dependency base.system"; return 1; }

    pass "agents_only_profile_expands_dependencies_correctly"
}

test_locked_core_modules_metadata_is_consistent() {
    source_manifest_index

    # Core base modules must have optional == 0 (locked)
    [[ "${ACFS_MODULE_OPTIONAL["base.system"]}" == "0" ]] || { fail "locked_core_modules" "base.system should not be optional"; return 1; }
    [[ "${ACFS_MODULE_OPTIONAL["users.ubuntu"]}" == "0" ]] || { fail "locked_core_modules" "users.ubuntu should not be optional"; return 1; }
    [[ "${ACFS_MODULE_OPTIONAL["base.filesystem"]}" == "0" ]] || { fail "locked_core_modules" "base.filesystem should not be optional"; return 1; }

    # Optional auxiliary tools must have optional == 1
    [[ "${ACFS_MODULE_OPTIONAL["db.postgres18"]}" == "1" ]] || { fail "locked_core_modules" "db.postgres18 should be optional"; return 1; }
    [[ "${ACFS_MODULE_OPTIONAL["cloud.supabase"]}" == "1" ]] || { fail "locked_core_modules" "cloud.supabase should be optional"; return 1; }
    [[ "${ACFS_MODULE_OPTIONAL["tools.vault"]}" == "1" ]] || { fail "locked_core_modules" "tools.vault should be optional"; return 1; }

    pass "locked_core_modules_metadata_is_consistent"
}

test_reproducible_cli_command_formatting() {
    source_manifest_index
    reset_selection_env

    MODE="safe"
    ACFS_SELECTED_PROFILE="minimal"
    SKIP_MODULES=("stack.rch")
    NO_DEPS=false

    local cmd
    cmd="$(acfs_format_reproducible_cli_command)"

    [[ "$cmd" == *"bash install.sh"* ]] || { fail "reproducible_cli_command" "Missing base command"; return 1; }
    [[ "$cmd" == *"--mode safe"* ]] || { fail "reproducible_cli_command" "Missing mode flag"; return 1; }
    [[ "$cmd" == *"--profile minimal"* ]] || { fail "reproducible_cli_command" "Missing profile flag"; return 1; }
    [[ "$cmd" == *"--skip stack.rch"* ]] || { fail "reproducible_cli_command" "Missing skip flag"; return 1; }

    pass "reproducible_cli_command_formatting"
}

test_selection_review_rendering_contains_expected_sections() {
    source_manifest_index
    reset_selection_env

    acfs_apply_profile "minimal"
    acfs_resolve_selection

    local output
    output="$(acfs_render_selection_review)"

    [[ "$output" == *"ACFS Installation Plan Review"* ]] || { fail "review_rendering" "Missing review header"; return 1; }
    [[ "$output" == *"Selected Profile: minimal"* ]] || { fail "review_rendering" "Missing profile name"; return 1; }
    [[ "$output" == *"[Locked Core]"* ]] || { fail "review_rendering" "Missing locked core marker"; return 1; }
    [[ "$output" == *"Reproducible CLI Command:"* ]] || { fail "review_rendering" "Missing reproducible command section"; return 1; }

    pass "selection_review_rendering_contains_expected_sections"
}

test_no_tty_fallback_behavior() {
    source_manifest_index
    reset_selection_env

    # 1. When non-interactive without TTY, acfs_interactive_module_selector resolves selection with defaults
    YES_MODE=true
    local status=0
    acfs_interactive_module_selector >/dev/null 2>&1 || status=$?
    if [[ "$status" -ne 0 ]]; then
        fail "no_tty_fallback" "Expected success in non-interactive mode, got $status"
        return 1
    fi

    # 2. When --interactive is explicitly requested in a non-TTY environment, it fails with a clear explanation
    reset_selection_env
    ACFS_INTERACTIVE=true
    DEBIAN_FRONTEND=noninteractive
    status=0
    local output
    output="$(acfs_interactive_module_selector 2>&1)" || status=$?
    if [[ "$status" -eq 0 ]]; then
        fail "no_tty_fallback" "Expected failure when --interactive used without TTY"
        return 1
    fi
    if [[ "$output" != *"no interactive TTY is attached"* ]]; then
        fail "no_tty_fallback" "Expected no-TTY error message, got: $output"
        return 1
    fi

    pass "no_tty_fallback_behavior"
}

test_interactive_profile_reselection_clears_stale_mode() {
    source_manifest_index
    reset_selection_env

    # Choose safe, go back, choose minimal, then proceed. Minimal has no mode of
    # its own, so the abandoned safe choice must not leak into the final plan.
    if ! _acfs_interactive_module_selector_on_tty <<< $'2\n2\n3\n1' >/dev/null; then
        fail "interactive_profile_reselection_clears_stale_mode" "Interactive selector did not complete"
        return 1
    fi
    [[ "$ACFS_SELECTED_PROFILE" == "minimal" ]] \
        || { fail "interactive_profile_reselection_clears_stale_mode" "Minimal profile was not selected"; return 1; }
    [[ "$MODE" == "vibe" ]] \
        || { fail "interactive_profile_reselection_clears_stale_mode" "Abandoned safe mode leaked into minimal profile"; return 1; }

    pass "interactive_profile_reselection_clears_stale_mode"
}

run_all_tests() {
    test_all_canonical_profiles_apply_successfully
    test_unknown_profile_fails_cleanly
    test_minimal_profile_selects_expected_essentials
    test_agents_only_profile_expands_dependencies_correctly
    test_locked_core_modules_metadata_is_consistent
    test_reproducible_cli_command_formatting
    test_profile_application_replaces_derived_selectors
    test_selector_profile_rejects_explicit_only
    test_selection_review_rendering_contains_expected_sections
    test_no_tty_fallback_behavior
    test_interactive_profile_reselection_clears_stale_mode

    echo ""
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"

    if [[ "$TESTS_FAILED" -gt 0 ]]; then
        return 1
    fi
    return 0
}

run_all_tests
