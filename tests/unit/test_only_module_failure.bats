#!/usr/bin/env bats
#
# Issue #373: the stack phase reported success even when every module
# explicitly requested with --only failed. The generator now emits an
# explicit-selection gate into optional-module failure handlers, and
# install.sh grades a failed stack phase (all requested failed vs partial)
# via acfs_stack_phase_selection_verdict(). These tests exercise the shipped
# helper functions extracted from the real files, plus the generated output.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    INSTALL_SH="$PROJECT_ROOT/install.sh"
    HELPERS_SH="$PROJECT_ROOT/scripts/lib/install_helpers.sh"

    # Logging stubs capture messages for assertions.
    LOGGED_ERRORS=""
    LOGGED_WARNS=""
    log_error() { LOGGED_ERRORS+="$*"$'\n'; }
    log_warn() { LOGGED_WARNS+="$*"$'\n'; }

    # Load the exact shipped function bodies (top-level definitions, one per
    # file, closed by a bare `}` at column 0).
    eval "$(sed -n '/^acfs_module_explicitly_selected() {$/,/^}$/p' "$HELPERS_SH")"
    eval "$(sed -n '/^acfs_stack_phase_selection_verdict() {$/,/^}$/p' "$INSTALL_SH")"
    [[ "$(type -t acfs_module_explicitly_selected)" == "function" ]]
    [[ "$(type -t acfs_stack_phase_selection_verdict)" == "function" ]]

    ACFS_INSTALL_PARTIAL_FAILURE=0
}

_plan_three_requested() {
    declare -gA ACFS_PLAN_REASON=(
        [utils.rust_proxy]="explicitly requested"
        [utils.aadc]="explicitly requested"
        [utils.caut]="explicitly requested"
        [lang.rust]="dependency of utils.caut"
    )
    declare -gA ACFS_MODULE_CATEGORY=(
        [utils.rust_proxy]="tools"
        [utils.aadc]="tools"
        [utils.caut]="tools"
        [lang.rust]="lang"
    )
    declare -gA ACFS_MODULE_PHASE=(
        [utils.rust_proxy]="9"
        [utils.aadc]="9"
        [utils.caut]="9"
        [lang.rust]="6"
    )
    ACFS_EFFECTIVE_PLAN=(lang.rust utils.rust_proxy utils.aadc utils.caut)
    ONLY_MODULES=(utils.rust_proxy utils.aadc utils.caut)
}

@test "explicitly selected module is detected" {
    _plan_three_requested
    acfs_module_explicitly_selected "utils.caut"
}

@test "dependency-selected module is not explicitly selected" {
    _plan_three_requested
    ! acfs_module_explicitly_selected "lang.rust"
}

@test "unknown module and missing plan map are not explicitly selected" {
    _plan_three_requested
    ! acfs_module_explicitly_selected "utils.nonexistent"
    unset ACFS_PLAN_REASON
    ! acfs_module_explicitly_selected "utils.caut"
}

@test "verdict: all requested modules failed is reported as total failure" {
    _plan_three_requested
    ACFS_MODULE_FAILURES=(
        "utils.rust_proxy (installation failed)"
        "utils.aadc (installation failed)"
        "utils.caut (installation failed)"
    )
    acfs_stack_phase_selection_verdict 0
    [[ "$LOGGED_ERRORS" == *"all 3 explicitly requested module(s) failed"* ]]
    [[ "$ACFS_INSTALL_PARTIAL_FAILURE" == "0" ]]
}

@test "verdict: partial failure warns and arms the partial exit flag" {
    _plan_three_requested
    ACFS_MODULE_FAILURES=(
        "utils.aadc (installation failed)"
    )
    acfs_stack_phase_selection_verdict 0
    [[ "$LOGGED_WARNS" == *"1 of 3 explicitly requested module(s) failed"* ]]
    [[ "$LOGGED_WARNS" == *"utils.aadc"* ]]
    [[ "$ACFS_INSTALL_PARTIAL_FAILURE" == "1" ]]
}

@test "verdict: partial flag stays down when a non-requested failure also occurred" {
    _plan_three_requested
    ACFS_MODULE_FAILURES=(
        "utils.aadc (installation failed)"
        "stack.ntm (installer execution)"
    )
    acfs_stack_phase_selection_verdict 0
    [[ "$LOGGED_WARNS" == *"1 of 3"* ]]
    [[ "$ACFS_INSTALL_PARTIAL_FAILURE" == "0" ]]
}

@test "verdict: failures recorded before this phase are ignored" {
    _plan_three_requested
    ACFS_MODULE_FAILURES=(
        "utils.aadc (earlier-phase record)"
    )
    # Baseline of 1 means no NEW failures in this phase: stay silent.
    acfs_stack_phase_selection_verdict 1
    [[ -z "$LOGGED_ERRORS" ]]
    [[ -z "$LOGGED_WARNS" ]]
    [[ "$ACFS_INSTALL_PARTIAL_FAILURE" == "0" ]]
}

@test "verdict: silent without --only selection" {
    _plan_three_requested
    ONLY_MODULES=()
    ACFS_MODULE_FAILURES=("utils.aadc (installation failed)")
    acfs_stack_phase_selection_verdict 0
    [[ -z "$LOGGED_ERRORS" ]]
    [[ -z "$LOGGED_WARNS" ]]
    [[ "$ACFS_INSTALL_PARTIAL_FAILURE" == "0" ]]
}

@test "generated optional-failure handlers carry the explicit-selection gate" {
    # Every generated installer that warn-and-skips an optional module must
    # first check acfs_module_explicitly_selected and return 1 when the
    # module was named with --only.
    local f
    for f in "$PROJECT_ROOT/scripts/generated/install_tools.sh" \
        "$PROJECT_ROOT/scripts/generated/install_stack.sh"; do
        grep -q 'acfs_module_explicitly_selected' "$f"
    done
    # The gate precedes the skip-and-succeed path for a known optional module.
    grep -A6 'acfs_module_explicitly_selected "utils.caut"' \
        "$PROJECT_ROOT/scripts/generated/install_tools.sh" | grep -q 'return 1'
}
