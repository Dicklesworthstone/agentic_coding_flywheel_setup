#!/usr/bin/env bats

load '../test_helper'

setup() {
    common_setup
    source_lib "logging"
    source_lib "install_helpers"
    
    # Mock manifest data
    export ACFS_MANIFEST_INDEX_LOADED=true
    
    # We must unset arrays first to avoid "cannot assign to element of array" if re-declaring types?
    unset ACFS_MODULES_IN_ORDER ACFS_MODULE_PHASE ACFS_MODULE_DEFAULT ACFS_MODULE_CATEGORY ACFS_MODULE_DEPS ACFS_MODULE_TAGS
    
    ACFS_MODULES_IN_ORDER=("mod1" "mod2" "mod3")
    declare -gA ACFS_MODULE_PHASE=( ["mod1"]="1" ["mod2"]="2" ["mod3"]="3" )
    declare -gA ACFS_MODULE_DEFAULT=( ["mod1"]="1" ["mod2"]="1" ["mod3"]="0" )
    declare -gA ACFS_MODULE_CATEGORY=( ["mod1"]="base" ["mod2"]="lang" ["mod3"]="tools" )
    declare -gA ACFS_MODULE_DEPS=()
    declare -gA ACFS_MODULE_TAGS=()
    
    # Selection globals (reset)
    ONLY_MODULES=()
    ONLY_PHASES=()
    SKIP_MODULES=()
    SKIP_TAGS=()
    SKIP_CATEGORIES=()
    
    # Stub sudo for run_as_target
    stub_command "sudo" "" 0
}

teardown() {
    common_teardown
}

@test "acfs_flag_bool: parses boolean values" {
    export TEST_VAR="true"
    run acfs_flag_bool "TEST_VAR"
    assert_output "1"
    
    export TEST_VAR="False"
    run acfs_flag_bool "TEST_VAR"
    assert_output "0"
    
    export TEST_VAR="1"
    run acfs_flag_bool "TEST_VAR"
    assert_output "1"
    
    export TEST_VAR="invalid"
    run acfs_flag_bool "TEST_VAR"
    # Output contains warning
    assert_output --partial "Ignoring invalid"
}

@test "acfs_resolve_selection: default selection" {
    acfs_resolve_selection
    
    # mod1 (default=1) should be selected
    if [[ -z "${ACFS_EFFECTIVE_RUN[mod1]}" ]]; then fail "mod1 not selected"; fi
    # mod3 (default=0) should NOT be selected
    if [[ -n "${ACFS_EFFECTIVE_RUN[mod3]}" ]]; then fail "mod3 selected"; fi
}

@test "acfs_resolve_selection: --only module" {
    ONLY_MODULES=("mod3")
    acfs_resolve_selection
    
    if [[ -z "${ACFS_EFFECTIVE_RUN[mod3]}" ]]; then fail "mod3 not selected"; fi
    if [[ -n "${ACFS_EFFECTIVE_RUN[mod1]}" ]]; then fail "mod1 selected"; fi
}

@test "acfs_resolve_selection: --skip module" {
    SKIP_MODULES=("mod1")
    acfs_resolve_selection
    
    if [[ -n "${ACFS_EFFECTIVE_RUN[mod1]}" ]]; then fail "mod1 selected"; fi
    if [[ -z "${ACFS_EFFECTIVE_RUN[mod2]}" ]]; then fail "mod2 not selected"; fi
}

@test "run_as_current_shell: executes command" {
    run run_as_current_shell "echo 'hello world'"
    assert_success
    assert_output "hello world"
}

@test "run_as_target_shell: calls run_as_target" {
    # Override function
    run_as_target() {
        echo "run_as_target called with: $*"
    }
    
    local out
    out=$(run_as_target_shell "echo test")
    
    # Check key parts instead of exact string to avoid expansion hell
    # We want to ensure it calls run_as_target with bash -c and sets PATH
    if [[ "$out" != *"run_as_target called with: bash -c"* ]]; then
        fail "Did not call run_as_target bash -c"
    fi
    if [[ "$out" != *"export PATH="* ]]; then
        fail "Did not export PATH"
    fi
    if [[ "$out" != *"\$HOME/.local/bin"* ]]; then
        fail "Did not include user paths (literal \$HOME)"
    fi
    if [[ "$out" != *"echo test"* ]]; then
        fail "Did not include command"
    fi
}

@test "_acfs_force_reinstall_enabled: returns 0 when true" {
    export ACFS_FORCE_REINSTALL="true"
    run _acfs_force_reinstall_enabled
    assert_success
}

@test "_acfs_force_reinstall_enabled: returns 1 when false" {
    export ACFS_FORCE_REINSTALL="false"
    run _acfs_force_reinstall_enabled
    assert_failure
}

# -------------------------------------------------
# Skip-if-installed tests (bd-1eop)
# -------------------------------------------------

@test "acfs_module_is_installed: returns false when no check defined" {
    # Clear installed_check arrays
    unset ACFS_MODULE_INSTALLED_CHECK ACFS_MODULE_INSTALLED_CHECK_RUN_AS
    declare -gA ACFS_MODULE_INSTALLED_CHECK=()
    declare -gA ACFS_MODULE_INSTALLED_CHECK_RUN_AS=()

    run acfs_module_is_installed "mod1"
    assert_failure
}

@test "acfs_module_is_installed: returns true when check succeeds" {
    unset ACFS_MODULE_INSTALLED_CHECK ACFS_MODULE_INSTALLED_CHECK_RUN_AS
    declare -gA ACFS_MODULE_INSTALLED_CHECK=( ["mod1"]="true" )
    declare -gA ACFS_MODULE_INSTALLED_CHECK_RUN_AS=( ["mod1"]="current" )

    run acfs_module_is_installed "mod1"
    assert_success
}

@test "acfs_module_is_installed: returns false when check fails" {
    unset ACFS_MODULE_INSTALLED_CHECK ACFS_MODULE_INSTALLED_CHECK_RUN_AS
    declare -gA ACFS_MODULE_INSTALLED_CHECK=( ["mod1"]="false" )
    declare -gA ACFS_MODULE_INSTALLED_CHECK_RUN_AS=( ["mod1"]="current" )

    run acfs_module_is_installed "mod1"
    assert_failure
}

@test "acfs_should_skip_module: skips installed modules" {
    unset ACFS_MODULE_INSTALLED_CHECK ACFS_MODULE_INSTALLED_CHECK_RUN_AS
    declare -gA ACFS_MODULE_INSTALLED_CHECK=( ["mod1"]="true" )
    declare -gA ACFS_MODULE_INSTALLED_CHECK_RUN_AS=( ["mod1"]="current" )
    export ACFS_FORCE_REINSTALL=false

    run acfs_should_skip_module "mod1"
    assert_success  # 0 means should skip
}

@test "acfs_should_skip_module: does not skip when force reinstall" {
    unset ACFS_MODULE_INSTALLED_CHECK ACFS_MODULE_INSTALLED_CHECK_RUN_AS
    declare -gA ACFS_MODULE_INSTALLED_CHECK=( ["mod1"]="true" )
    declare -gA ACFS_MODULE_INSTALLED_CHECK_RUN_AS=( ["mod1"]="current" )
    export ACFS_FORCE_REINSTALL=true

    run acfs_should_skip_module "mod1"
    assert_failure  # 1 means do not skip (install)
}

@test "acfs_module_is_installed: respects run_as target_user" {
    unset ACFS_MODULE_INSTALLED_CHECK ACFS_MODULE_INSTALLED_CHECK_RUN_AS
    declare -gA ACFS_MODULE_INSTALLED_CHECK=( ["mod1"]="true" )
    declare -gA ACFS_MODULE_INSTALLED_CHECK_RUN_AS=( ["mod1"]="target_user" )

    # Mock run_as_target to just pass through to bash
    # Note: We need to export the function for subshells
    run_as_target() {
        "$@"
    }
    export -f run_as_target

    run acfs_module_is_installed "mod1"
    assert_success
}
