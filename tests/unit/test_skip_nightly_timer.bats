#!/usr/bin/env bats
#
# Issue #476: `--skip acfs.nightly` removed the module from the plan, but the
# legacy finalize phase still installed and enabled the nightly update timer
# through its own hardcoded path. finalize now asks the same selection verdict
# as module dispatch (acfs_finalize_nightly_timer) and records an explicit
# opt-out for doctor. These tests exercise the shipped function bodies
# extracted from install.sh, in the style of test_only_module_failure.bats.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    INSTALL_SH="$PROJECT_ROOT/install.sh"

    eval "$(sed -n '/^acfs_legacy_module_selected() {$/,/^}$/p' "$INSTALL_SH")"
    eval "$(sed -n '/^acfs_finalize_nightly_timer() {$/,/^}$/p' "$INSTALL_SH")"
    [[ "$(type -t acfs_legacy_module_selected)" == "function" ]]
    [[ "$(type -t acfs_finalize_nightly_timer)" == "function" ]]

    # Selection state as install_helpers.sh leaves it after planning.
    ONLY_MODULES=()
    SKIP_MODULES=()
    declare -gA ACFS_EFFECTIVE_RUN=()
    declare -gA ACFS_PLAN_EXCLUDE_REASON=()
    acfs_selection_filters_active() {
        [[ ${#ONLY_MODULES[@]} -gt 0 || ${#SKIP_MODULES[@]} -gt 0 ]]
    }
    should_run_module() { [[ -n "${ACFS_EFFECTIVE_RUN[$1]:-}" ]]; }

    TIMER_CONFIGURED=0
    STATE_SKIPS=()
    DETAILS=""
    try_step() { shift; "$@"; }
    configure_acfs_nightly_timer() { TIMER_CONFIGURED=$((TIMER_CONFIGURED + 1)); }
    state_tool_skip() { STATE_SKIPS+=("$1"); }
    log_detail() { DETAILS+="$*"$'\n'; }
}

@test "default install (no selection filters) configures the nightly timer" {
    acfs_finalize_nightly_timer

    [ "$TIMER_CONFIGURED" -eq 1 ]
    [ "${#STATE_SKIPS[@]}" -eq 0 ]
}

@test "--skip acfs.nightly does not configure the timer and records the opt-out (#476)" {
    SKIP_MODULES=(acfs.nightly)
    ACFS_EFFECTIVE_RUN=([acfs.update]=1 [acfs.doctor]=1)
    ACFS_PLAN_EXCLUDE_REASON=([acfs.nightly]="explicitly skipped")

    acfs_finalize_nightly_timer

    [ "$TIMER_CONFIGURED" -eq 0 ]
    [ "${#STATE_SKIPS[@]}" -eq 1 ]
    [ "${STATE_SKIPS[0]}" = "acfs.nightly" ]
    [[ "$DETAILS" == *"Skipping ACFS nightly update timer (acfs.nightly: explicitly skipped)"* ]]
}

@test "a skipped tag or category that covers acfs.nightly is also an opt-out (#476)" {
    local reason=""
    for reason in "skipped tag maintenance" "skipped category acfs"; do
        TIMER_CONFIGURED=0
        STATE_SKIPS=()
        SKIP_MODULES=(placeholder)
        ACFS_PLAN_EXCLUDE_REASON=([acfs.nightly]="$reason")

        acfs_finalize_nightly_timer

        [ "$TIMER_CONFIGURED" -eq 0 ]
        [ "${STATE_SKIPS[*]}" = "acfs.nightly" ]
    done
}

@test "--only without acfs.nightly leaves the timer and the skip record alone" {
    ONLY_MODULES=(lang.go)
    ACFS_EFFECTIVE_RUN=([lang.go]=1)
    ACFS_PLAN_EXCLUDE_REASON=([acfs.nightly]="not selected")

    acfs_finalize_nightly_timer

    [ "$TIMER_CONFIGURED" -eq 0 ]
    [ "${#STATE_SKIPS[@]}" -eq 0 ]
    [[ "$DETAILS" == *"(acfs.nightly: not selected)"* ]]
}

@test "--only acfs.nightly configures the timer" {
    ONLY_MODULES=(acfs.nightly)
    ACFS_EFFECTIVE_RUN=([acfs.update]=1 [acfs.nightly]=1)

    acfs_finalize_nightly_timer

    [ "$TIMER_CONFIGURED" -eq 1 ]
    [ "${#STATE_SKIPS[@]}" -eq 0 ]
}

@test "a timer configuration failure still fails finalize" {
    configure_acfs_nightly_timer() { return 7; }

    run acfs_finalize_nightly_timer
    [ "$status" -eq 1 ]
}

@test "finalize reaches the timer only through the selection-aware helper" {
    local finalize_body=""
    finalize_body="$(sed -n '/^finalize() {$/,/^}$/p' "$INSTALL_SH")"
    [[ "$finalize_body" == *"acfs_finalize_nightly_timer || return 1"* ]]
    [[ "$finalize_body" != *"configure_acfs_nightly_timer"* ]]
}
