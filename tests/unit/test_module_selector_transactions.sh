#!/usr/bin/env bash
# Dependency-aware custom selection against the real resolver and fixture metadata.
# No installers, network access, or host configuration changes are performed.
# shellcheck disable=SC2034
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/logging.sh
source "$REPO_ROOT/scripts/lib/logging.sh"
# shellcheck source=scripts/lib/install_helpers.sh
source "$REPO_ROOT/scripts/lib/install_helpers.sh"
# shellcheck source=scripts/lib/module_selector.sh
source "$REPO_ROOT/scripts/lib/module_selector.sh"

fixture() {
    ACFS_MANIFEST_INDEX_LOADED=true
    ACFS_GENERATED_SELECTION_READY=false
    ACFS_SELECTED_PROFILE=""
    ACFS_CLI_PROFILE=""
    ACFS_EXPLICIT_TARGETED_SELECTION=false
    ACFS_INTERACTIVE=false
    YES_MODE=false
    NO_DEPS=false
    MODE=vibe
    ONLY_MODULES=()
    ONLY_PHASES=()
    SKIP_MODULES=()
    SKIP_TAGS=()
    SKIP_CATEGORIES=()
    declare -ga ACFS_MODULES_IN_ORDER=(
        base.core tools.one tools.two tools.three tools.four tools.five tools.six
        lang.runtime agents.alpha cloud.deploy stack.workflow acfs.locked
    )
    declare -gA ACFS_MODULE_DEPS=(
        [lang.runtime]=base.core [agents.alpha]=lang.runtime
        [stack.workflow]=agents.alpha [cloud.deploy]=base.core
        [acfs.locked]=stack.workflow
    )
    declare -gA ACFS_MODULE_PHASE=() ACFS_MODULE_DESC=() ACFS_MODULE_OPTIONAL=()
    declare -gA ACFS_MODULE_DEFAULT=() ACFS_MODULE_TAGS=() ACFS_MODULE_CATEGORY=()
    local mod=""
    for mod in "${ACFS_MODULES_IN_ORDER[@]}"; do
        ACFS_MODULE_PHASE["$mod"]=5
        ACFS_MODULE_DESC["$mod"]="Fixture $mod"
        ACFS_MODULE_OPTIONAL["$mod"]=1
        ACFS_MODULE_DEFAULT["$mod"]=0
        ACFS_MODULE_TAGS["$mod"]=extra
        ACFS_MODULE_CATEGORY["$mod"]=tools
    done
    ACFS_MODULE_PHASE[base.core]=1
    ACFS_MODULE_PHASE[lang.runtime]=6
    ACFS_MODULE_PHASE[agents.alpha]=7
    ACFS_MODULE_PHASE[cloud.deploy]=8
    ACFS_MODULE_PHASE[stack.workflow]=9
    ACFS_MODULE_PHASE[acfs.locked]=10
    ACFS_MODULE_OPTIONAL[base.core]=0
    ACFS_MODULE_OPTIONAL[acfs.locked]=0
    for mod in base.core lang.runtime agents.alpha stack.workflow; do
        ACFS_MODULE_DEFAULT["$mod"]=1
        ACFS_MODULE_TAGS["$mod"]=essential
    done
    ACFS_MODULE_CATEGORY[cloud.deploy]=cloud
    declare -ga ACFS_PROFILES_IN_ORDER=(vibe safe minimal agents-only cloud-only stack-only)
    declare -gA ACFS_PROFILE_MODE=([vibe]=vibe [safe]=safe)
    declare -gA ACFS_PROFILE_ONLY_MODULES=(
        [minimal]=agents.alpha,stack.workflow [cloud-only]=cloud.deploy
    )
    declare -gA ACFS_PROFILE_ONLY_PHASES=([agents-only]=7 [stack-only]=9)
    acfs_resolve_selection
}

snapshot() {
    declare -p ONLY_MODULES ONLY_PHASES SKIP_MODULES SKIP_TAGS SKIP_CATEGORIES \
        ACFS_EFFECTIVE_PLAN ACFS_EFFECTIVE_RUN ACFS_PLAN_REASON \
        ACFS_PLAN_EXCLUDE_REASON ACFS_GENERATED_SELECTION_READY
}

expect_plan() {
    local actual="${ACFS_EFFECTIVE_PLAN[*]}"
    [[ "$actual" == "$1" ]] || {
        printf 'Expected plan: %s\nActual plan:   %s\n' "$1" "$actual" >&2
        return 1
    }
}

test_disable_prerequisite_cascades() {
    fixture || return 1
    acfs_prepare_custom_selection || return 1
    acfs_interactive_custom_module_toggles <<< $'lang.runtime\ndone' >/dev/null || return 1
    acfs_resolve_selection || return 1
    expect_plan base.core
}

test_enable_restores_transitive_prerequisites() {
    fixture || return 1
    acfs_prepare_custom_selection || return 1
    acfs_toggle_custom_module lang.runtime >/dev/null || return 1
    acfs_toggle_custom_module stack.workflow >/dev/null || return 1
    expect_plan 'base.core lang.runtime agents.alpha stack.workflow' || return 1
    [[ "${ACFS_PLAN_REASON[lang.runtime]}" == 'dependency of agents.alpha' ]]
}

test_repeated_edits_use_resolved_state() {
    fixture || return 1
    acfs_prepare_custom_selection || return 1
    acfs_interactive_custom_module_toggles <<< $'lang.runtime\nstack.workflow\nlang.runtime\ndone' >/dev/null || return 1
    expect_plan base.core
}

test_locked_dependents_prevent_cascade() {
    fixture || return 1
    ONLY_MODULES=(acfs.locked)
    acfs_prepare_custom_selection || return 1
    local before
    before="$(snapshot)"
    if acfs_toggle_custom_module lang.runtime >/dev/null 2>&1; then return 1; fi
    [[ "$(snapshot)" == "$before" ]]
}

test_locked_core_cannot_be_toggled() {
    fixture || return 1
    acfs_prepare_custom_selection || return 1
    local before
    before="$(snapshot)"
    if acfs_toggle_custom_module base.core >/dev/null 2>&1; then return 1; fi
    [[ "$(snapshot)" == "$before" ]]
}

test_rejected_candidate_preserves_plan() {
    fixture || return 1
    acfs_prepare_custom_selection || return 1
    ACFS_MODULE_DEPS[cloud.deploy]=missing.module
    local before
    before="$(snapshot)"
    if acfs_toggle_custom_module cloud.deploy >/dev/null 2>&1; then return 1; fi
    [[ "$(snapshot)" == "$before" ]]
}

test_invalid_target_preserves_plan() {
    fixture || return 1
    acfs_prepare_custom_selection || return 1
    local before
    before="$(snapshot)"
    if acfs_toggle_custom_module 'not.a.module' >/dev/null 2>&1; then return 1; fi
    if acfs_toggle_custom_module '' >/dev/null 2>&1; then return 1; fi
    [[ "$(snapshot)" == "$before" ]]
}

test_last_module_never_expands_to_defaults() {
    fixture || return 1
    NO_DEPS=true
    ONLY_MODULES=(tools.one)
    acfs_prepare_custom_selection 2>/dev/null || return 1
    local before
    before="$(snapshot)"
    if acfs_toggle_custom_module tools.one >/dev/null 2>&1; then return 1; fi
    [[ "$(snapshot)" == "$before" ]] || return 1
    expect_plan tools.one
}

test_broad_filters_are_materialized() {
    fixture || return 1
    ACFS_MODULE_DEFAULT[cloud.deploy]=1
    SKIP_TAGS=(extra)
    SKIP_CATEGORIES=(cloud)
    acfs_prepare_custom_selection || return 1
    [[ "${#SKIP_TAGS[@]}" -eq 0 && "${#SKIP_CATEGORIES[@]}" -eq 0 ]] || return 1
    expect_plan 'base.core lang.runtime agents.alpha stack.workflow' || return 1
    acfs_toggle_custom_module cloud.deploy >/dev/null || return 1
    expect_plan 'base.core lang.runtime agents.alpha cloud.deploy stack.workflow'
}

test_disabled_by_default_module_can_be_enabled() {
    fixture || return 1
    acfs_prepare_custom_selection || return 1
    acfs_toggle_custom_module tools.one >/dev/null || return 1
    expect_plan 'base.core tools.one lang.runtime agents.alpha stack.workflow'
}

test_decimal_menu_input() {
    fixture || return 1
    acfs_prepare_custom_selection || return 1
    acfs_interactive_custom_module_toggles <<< $'08\ndone' >/dev/null || return 1
    expect_plan 'base.core lang.runtime'
}

test_oversized_menu_input_is_inert() {
    fixture || return 1
    acfs_prepare_custom_selection || return 1
    local before
    before="$(snapshot)"
    acfs_interactive_custom_module_toggles <<< $'999999999999999999999999999999\n0\ndone' >/dev/null 2>&1 || return 1
    [[ "$(snapshot)" == "$before" ]]
}

test_eof_cancels_instead_of_proceeding() {
    fixture || return 1
    if _acfs_interactive_module_selector_on_tty <<< $'1\n3\nlang.runtime' >/dev/null 2>&1; then
        return 1
    fi
}

test_failed_profile_does_not_authorize_previous_plan() {
    fixture || return 1
    ACFS_PROFILES_IN_ORDER=(vibe safe)
    # A missing minimal profile must return to profile selection, not interpret
    # the following 1 as authorization to install the old default plan.
    if _acfs_interactive_module_selector_on_tty <<< $'3\n1' >/dev/null 2>&1; then
        return 1
    fi
}

test_profile_reselection_clears_all_filters() {
    fixture || return 1
    SKIP_TAGS=(extra)
    SKIP_CATEGORIES=(cloud)
    _acfs_interactive_module_selector_on_tty <<< $'2\n2\n5\n1' >/dev/null || return 1
    [[ "$MODE" == vibe && "$ACFS_SELECTED_PROFILE" == cloud-only ]] || return 1
    [[ "${#SKIP_TAGS[@]}" -eq 0 && "${#SKIP_CATEGORIES[@]}" -eq 0 ]] || return 1
    expect_plan 'base.core cloud.deploy'
}

test_invalid_plan_clears_readiness() {
    fixture || return 1
    ONLY_MODULES=(missing.module)
    if acfs_validate_interactive_plan >/dev/null 2>&1; then return 1; fi
    [[ "$ACFS_GENERATED_SELECTION_READY" == false ]]
}

test_empty_plan_cannot_be_customized() {
    fixture || return 1
    SKIP_MODULES=("${ACFS_MODULES_IN_ORDER[@]}")
    if acfs_prepare_custom_selection >/dev/null 2>&1; then return 1; fi
    [[ "$ACFS_GENERATED_SELECTION_READY" == false ]]
}

test_no_deps_preserves_explicit_expert_behavior() {
    fixture || return 1
    NO_DEPS=true
    acfs_prepare_custom_selection 2>/dev/null || return 1
    acfs_toggle_custom_module lang.runtime >/dev/null 2>&1 || return 1
    expect_plan 'base.core agents.alpha stack.workflow'
}

passed=0
failed=0
for test in \
    test_disable_prerequisite_cascades \
    test_enable_restores_transitive_prerequisites \
    test_repeated_edits_use_resolved_state \
    test_locked_dependents_prevent_cascade \
    test_locked_core_cannot_be_toggled \
    test_rejected_candidate_preserves_plan \
    test_invalid_target_preserves_plan \
    test_last_module_never_expands_to_defaults \
    test_broad_filters_are_materialized \
    test_disabled_by_default_module_can_be_enabled \
    test_decimal_menu_input \
    test_oversized_menu_input_is_inert \
    test_eof_cancels_instead_of_proceeding \
    test_failed_profile_does_not_authorize_previous_plan \
    test_profile_reselection_clears_all_filters \
    test_invalid_plan_clears_readiness \
    test_empty_plan_cannot_be_customized \
    test_no_deps_preserves_explicit_expert_behavior; do
    if ("$test"); then
        printf 'PASS: %s\n' "$test"
        passed=$((passed + 1))
    else
        printf 'FAIL: %s\n' "$test" >&2
        failed=$((failed + 1))
    fi
done
printf '\nPassed: %s; failed: %s\n' "$passed" "$failed"
[[ "$failed" -eq 0 ]]
