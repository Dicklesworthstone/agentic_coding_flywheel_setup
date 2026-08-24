#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2317
# ============================================================
# Test script for autofix_version_managers.sh
# Run: bash scripts/lib/test_autofix_version_managers.sh
#
# Related beads:
#   - bd-19y9.3.2: Implement auto-fix for nvm/pyenv conflicts
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the module
source "$SCRIPT_DIR/autofix_version_managers.sh"

TESTS_PASSED=0
TESTS_FAILED=0

install_test_runtime_home_override() {
    # These standalone tests isolate each case by assigning HOME to a scratch
    # directory. The production runtime resolver intentionally prefers the real
    # passwd home when TARGET_HOME is unset, so override that final fallback here
    # to keep the harness from inspecting the developer's installed ACFS home.
    autofix_resolve_current_home() {
        autofix_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null
    }
}

install_test_runtime_home_override

setup_autofix_state_dir() {
    local state_dir="$1"
    unset -f record_change 2>/dev/null || true
    unset _ACFS_AUTOFIX_SOURCED
    unset _ACFS_AUTOFIX_VERSION_MANAGERS_SH_LOADED
    # shellcheck source=autofix_version_managers.sh
    source "$SCRIPT_DIR/autofix_version_managers.sh"
    install_test_runtime_home_override

    export ACFS_STATE_DIR="$state_dir"
    export ACFS_CHANGES_FILE="$ACFS_STATE_DIR/changes.jsonl"
    export ACFS_UNDOS_FILE="$ACFS_STATE_DIR/undos.jsonl"
    export ACFS_BACKUPS_DIR="$ACFS_STATE_DIR/backups"
    export ACFS_LOCK_FILE="$ACFS_STATE_DIR/.lock"
    export ACFS_INTEGRITY_FILE="$ACFS_STATE_DIR/.integrity"

    ACFS_CHANGE_RECORDS=()
    ACFS_CHANGE_ORDER=()
    ACFS_SESSION_ID=""
    ACFS_AUTOFIX_INITIALIZED=false
    ACFS_AUTOFIX_LOCK_FD=""

    rm -rf "$ACFS_STATE_DIR"
    mkdir -p "$ACFS_BACKUPS_DIR"
    : > "$ACFS_CHANGES_FILE"
    : > "$ACFS_UNDOS_FILE"
}

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

# Safe cleanup function
cleanup_test_dir() {
    local test_dir="$1"
    if [[ -d "$test_dir" ]]; then
        rm -rf "$test_dir"
    fi
}

# ============================================================
# NVM Tests
# ============================================================

# Test: NVM check when no NVM exists
test_nvm_check_no_installation() {
    local test_id="nvm_check_none"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    mkdir -p "$test_dir"

    # Override HOME to isolated test directory
    local old_home="$HOME"
    HOME="$test_dir"
    unset NVM_DIR

    local result
    result=$(autofix_nvm_check)

    HOME="$old_home"
    cleanup_test_dir "$test_dir"

    local status
    status=$(echo "$result" | jq -r '.status')

    if [[ "$status" != "none" ]]; then
        test_fail "nvm_check_no_installation" "Expected status 'none', got '$status'"
        return
    fi

    test_pass "nvm_check_no_installation"
}

# Test: NVM check when NVM_DIR is set
test_nvm_check_env_set() {
    local test_id="nvm_check_env"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    mkdir -p "$test_dir/.nvm"

    local old_home="$HOME"
    local old_nvm_dir="${NVM_DIR:-}"
    HOME="$test_dir"
    NVM_DIR="$test_dir/.nvm"

    local result
    result=$(autofix_nvm_check)

    HOME="$old_home"
    [[ -n "$old_nvm_dir" ]] && NVM_DIR="$old_nvm_dir" || unset NVM_DIR
    cleanup_test_dir "$test_dir"

    local status
    status=$(echo "$result" | jq -r '.status')

    # Should detect as installed (directory exists)
    if [[ "$status" != "installed" ]]; then
        test_fail "nvm_check_env_set" "Expected status 'installed', got '$status'"
        return
    fi

    test_pass "nvm_check_env_set"
}

# Test: NVM check detects shell configs
test_nvm_check_shell_configs() {
    local test_id="nvm_check_configs"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    mkdir -p "$test_dir/.nvm"

    # Create bashrc with NVM references
    cat > "$test_dir/.bashrc" << 'EOF'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
EOF

    local old_home="$HOME"
    HOME="$test_dir"
    unset NVM_DIR

    local result
    result=$(autofix_nvm_check)

    HOME="$old_home"
    cleanup_test_dir "$test_dir"

    local config_count
    config_count=$(echo "$result" | jq -r '.shell_configs | length')

    if [[ "$config_count" -lt 1 ]]; then
        test_fail "nvm_check_shell_configs" "Expected at least 1 shell config, got $config_count"
        return
    fi

    test_pass "nvm_check_shell_configs"
}

# Test: TARGET_HOME beats poisoned caller HOME/NVM_DIR

test_nvm_check_prefers_target_home_over_poisoned_home() {
    local test_id="nvm_target_home"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    local current_home="$test_dir/current-home"
    local target_home="$test_dir/target-home"
    mkdir -p "$current_home/.nvm" "$target_home/.nvm"

    cat > "$current_home/.bashrc" << 'EOF'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
EOF

    cat > "$target_home/.bashrc" << 'EOF'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
EOF

    local old_home="$HOME"
    local old_target_home="${TARGET_HOME:-}"
    local old_nvm_dir="${NVM_DIR:-}"
    HOME="$current_home"
    TARGET_HOME="$target_home"
    NVM_DIR="$current_home/.nvm"

    local result
    result=$(autofix_nvm_check)

    HOME="$old_home"
    [[ -n "$old_target_home" ]] && TARGET_HOME="$old_target_home" || unset TARGET_HOME
    [[ -n "$old_nvm_dir" ]] && NVM_DIR="$old_nvm_dir" || unset NVM_DIR

    local first_dir=""
    local first_config=""
    first_dir=$(echo "$result" | jq -r '.nvm_dirs[0] // empty')
    first_config=$(echo "$result" | jq -r '.shell_configs[0] // empty')

    cleanup_test_dir "$test_dir"

    if [[ "$first_dir" != "$target_home/.nvm" ]]; then
        test_fail "nvm_check_prefers_target_home_over_poisoned_home" "Expected target-home nvm dir, got '$first_dir'"
        return
    fi

    if [[ "$first_config" != "$target_home/.bashrc" ]]; then
        test_fail "nvm_check_prefers_target_home_over_poisoned_home" "Expected target-home bashrc, got '$first_config'"
        return
    fi

    test_pass "nvm_check_prefers_target_home_over_poisoned_home"
}

test_nvm_check_ignores_poisoned_xdg_config_home() {
    local test_id="nvm_xdg_config_home"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    local current_home="$test_dir/current-home"
    local target_home="$test_dir/target-home"
    mkdir -p "$current_home/.config/nvm" "$target_home/.config/nvm"

    local old_home="$HOME"
    local old_target_home="${TARGET_HOME:-}"
    local old_xdg_config_home="${XDG_CONFIG_HOME:-}"
    local old_nvm_dir="${NVM_DIR:-}"
    HOME="$current_home"
    TARGET_HOME="$target_home"
    XDG_CONFIG_HOME="$current_home/.config"
    unset NVM_DIR

    local result
    result=$(autofix_nvm_check)

    HOME="$old_home"
    [[ -n "$old_target_home" ]] && TARGET_HOME="$old_target_home" || unset TARGET_HOME
    [[ -n "$old_xdg_config_home" ]] && XDG_CONFIG_HOME="$old_xdg_config_home" || unset XDG_CONFIG_HOME
    [[ -n "$old_nvm_dir" ]] && NVM_DIR="$old_nvm_dir" || unset NVM_DIR

    local first_dir=""
    first_dir=$(echo "$result" | jq -r '.nvm_dirs[0] // empty')

    cleanup_test_dir "$test_dir"

    if [[ "$first_dir" != "$target_home/.config/nvm" ]]; then
        test_fail "nvm_check_ignores_poisoned_xdg_config_home" "Expected target-home XDG nvm dir, got '$first_dir'"
        return
    fi

    test_pass "nvm_check_ignores_poisoned_xdg_config_home"
}

# Test: NVM dry-run mode
test_nvm_fix_dry_run() {
    local test_id="nvm_fix_dry"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    mkdir -p "$test_dir/.nvm"

    cat > "$test_dir/.bashrc" << 'EOF'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
EOF

    local old_home="$HOME"
    HOME="$test_dir"
    unset NVM_DIR

    # Run dry-run
    local output
    output=$(autofix_nvm_fix "dry-run" 2>&1)

    # Directory should still exist
    if [[ ! -d "$test_dir/.nvm" ]]; then
        HOME="$old_home"
        cleanup_test_dir "$test_dir"
        test_fail "nvm_fix_dry_run" "Directory was removed in dry-run mode"
        return
    fi

    # Config should be unchanged
    if ! grep -q "NVM_DIR" "$test_dir/.bashrc"; then
        HOME="$old_home"
        cleanup_test_dir "$test_dir"
        test_fail "nvm_fix_dry_run" "Config was modified in dry-run mode"
        return
    fi

    HOME="$old_home"
    cleanup_test_dir "$test_dir"

    test_pass "nvm_fix_dry_run"
}

test_nvm_fix_manages_session_and_records_changes() {
    local test_id="nvm_fix_live"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    local state_dir="$test_dir/state"
    mkdir -p "$test_dir/.nvm"

    cat > "$test_dir/.bashrc" << 'EOF'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
EOF

    local old_home="$HOME"
    local old_nvm_dir="${NVM_DIR:-}"
    HOME="$test_dir"
    unset NVM_DIR
    setup_autofix_state_dir "$state_dir"

    if ! autofix_nvm_fix "fix" >/dev/null 2>&1; then
        HOME="$old_home"
        [[ -n "$old_nvm_dir" ]] && NVM_DIR="$old_nvm_dir" || unset NVM_DIR
        cleanup_test_dir "$test_dir"
        test_fail "nvm_fix_manages_session_and_records_changes" "standalone nvm fix failed"
        return
    fi

    if [[ -d "$test_dir/.nvm" ]]; then
        HOME="$old_home"
        [[ -n "$old_nvm_dir" ]] && NVM_DIR="$old_nvm_dir" || unset NVM_DIR
        cleanup_test_dir "$test_dir"
        test_fail "nvm_fix_manages_session_and_records_changes" "nvm directory was not removed"
        return
    fi

    if grep -q "NVM_DIR\\|nvm\\.sh" "$test_dir/.bashrc"; then
        HOME="$old_home"
        [[ -n "$old_nvm_dir" ]] && NVM_DIR="$old_nvm_dir" || unset NVM_DIR
        cleanup_test_dir "$test_dir"
        test_fail "nvm_fix_manages_session_and_records_changes" "nvm shell config entries were not removed"
        return
    fi

    if [[ -f "$ACFS_STATE_DIR/.session" ]]; then
        HOME="$old_home"
        [[ -n "$old_nvm_dir" ]] && NVM_DIR="$old_nvm_dir" || unset NVM_DIR
        cleanup_test_dir "$test_dir"
        test_fail "nvm_fix_manages_session_and_records_changes" "session marker was left behind after standalone nvm fix"
        return
    fi

    if [[ "$(jq -r 'select(.category == "nvm") | .category' "$ACFS_CHANGES_FILE" | wc -l | tr -d ' ')" -lt 2 ]]; then
        HOME="$old_home"
        [[ -n "$old_nvm_dir" ]] && NVM_DIR="$old_nvm_dir" || unset NVM_DIR
        cleanup_test_dir "$test_dir"
        test_fail "nvm_fix_manages_session_and_records_changes" "expected nvm changes were not recorded"
        return
    fi

    HOME="$old_home"
    [[ -n "$old_nvm_dir" ]] && NVM_DIR="$old_nvm_dir" || unset NVM_DIR
    cleanup_test_dir "$test_dir"
    test_pass "nvm_fix_manages_session_and_records_changes"
}

test_nvm_fix_restores_state_when_record_change_fails() {
    local test_id="nvm_fix_restore_on_journal_failure"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    local state_dir="$test_dir/state"
    mkdir -p "$test_dir/.nvm"

    cat > "$test_dir/.bashrc" << 'EOF'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
EOF

    local old_home="$HOME"
    local old_nvm_dir="${NVM_DIR:-}"
    HOME="$test_dir"
    unset NVM_DIR
    setup_autofix_state_dir "$state_dir"

    record_change() {
        return 1
    }

    if autofix_nvm_fix "fix" >/dev/null 2>&1; then
        HOME="$old_home"
        [[ -n "$old_nvm_dir" ]] && NVM_DIR="$old_nvm_dir" || unset NVM_DIR
        cleanup_test_dir "$test_dir"
        test_fail "nvm_fix_restores_state_when_record_change_fails" "nvm fix unexpectedly succeeded when journaling failed"
        return
    fi

    if [[ ! -d "$test_dir/.nvm" ]]; then
        HOME="$old_home"
        [[ -n "$old_nvm_dir" ]] && NVM_DIR="$old_nvm_dir" || unset NVM_DIR
        cleanup_test_dir "$test_dir"
        test_fail "nvm_fix_restores_state_when_record_change_fails" "nvm directory was not restored after journaling failure"
        return
    fi

    if ! grep -q "NVM_DIR\\|nvm\\.sh" "$test_dir/.bashrc"; then
        HOME="$old_home"
        [[ -n "$old_nvm_dir" ]] && NVM_DIR="$old_nvm_dir" || unset NVM_DIR
        cleanup_test_dir "$test_dir"
        test_fail "nvm_fix_restores_state_when_record_change_fails" "nvm shell config was not restored after journaling failure"
        return
    fi

    if [[ -s "$ACFS_CHANGES_FILE" ]]; then
        HOME="$old_home"
        [[ -n "$old_nvm_dir" ]] && NVM_DIR="$old_nvm_dir" || unset NVM_DIR
        cleanup_test_dir "$test_dir"
        test_fail "nvm_fix_restores_state_when_record_change_fails" "nvm journaling failure still left change records behind"
        return
    fi

    HOME="$old_home"
    [[ -n "$old_nvm_dir" ]] && NVM_DIR="$old_nvm_dir" || unset NVM_DIR
    cleanup_test_dir "$test_dir"
    test_pass "nvm_fix_restores_state_when_record_change_fails"
}

# ============================================================
# Pyenv Tests
# ============================================================

# Test: Pyenv check when no pyenv exists
test_pyenv_check_no_installation() {
    local test_id="pyenv_check_none"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    mkdir -p "$test_dir"

    local old_home="$HOME"
    HOME="$test_dir"
    unset PYENV_ROOT

    local result
    result=$(autofix_pyenv_check)

    HOME="$old_home"
    cleanup_test_dir "$test_dir"

    local status
    status=$(echo "$result" | jq -r '.status')

    if [[ "$status" != "none" ]]; then
        test_fail "pyenv_check_no_installation" "Expected status 'none', got '$status'"
        return
    fi

    test_pass "pyenv_check_no_installation"
}

# Test: Pyenv check when PYENV_ROOT is set
test_pyenv_check_env_set() {
    local test_id="pyenv_check_env"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    mkdir -p "$test_dir/.pyenv/bin"

    local old_home="$HOME"
    local old_pyenv_root="${PYENV_ROOT:-}"
    HOME="$test_dir"
    PYENV_ROOT="$test_dir/.pyenv"

    local result
    result=$(autofix_pyenv_check)

    HOME="$old_home"
    [[ -n "$old_pyenv_root" ]] && PYENV_ROOT="$old_pyenv_root" || unset PYENV_ROOT
    cleanup_test_dir "$test_dir"

    local status
    status=$(echo "$result" | jq -r '.status')

    if [[ "$status" != "installed" ]]; then
        test_fail "pyenv_check_env_set" "Expected status 'installed', got '$status'"
        return
    fi

    test_pass "pyenv_check_env_set"
}

# Test: Pyenv check detects shell configs
test_pyenv_check_shell_configs() {
    local test_id="pyenv_check_configs"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    mkdir -p "$test_dir/.pyenv"

    cat > "$test_dir/.bashrc" << 'EOF'
export PYENV_ROOT="$HOME/.pyenv"
eval "$(pyenv init -)"
EOF

    local old_home="$HOME"
    HOME="$test_dir"
    unset PYENV_ROOT

    local result
    result=$(autofix_pyenv_check)

    HOME="$old_home"
    cleanup_test_dir "$test_dir"

    local config_count
    config_count=$(echo "$result" | jq -r '.shell_configs | length')

    if [[ "$config_count" -lt 1 ]]; then
        test_fail "pyenv_check_shell_configs" "Expected at least 1 shell config, got $config_count"
        return
    fi

    test_pass "pyenv_check_shell_configs"
}

# Test: TARGET_HOME beats poisoned caller HOME/PYENV_ROOT

test_pyenv_check_prefers_target_home_over_poisoned_home() {
    local test_id="pyenv_target_home"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    local current_home="$test_dir/current-home"
    local target_home="$test_dir/target-home"
    mkdir -p "$current_home/.pyenv" "$target_home/.pyenv"

    cat > "$current_home/.bashrc" << 'EOF'
export PYENV_ROOT="$HOME/.pyenv"
eval "$(pyenv init -)"
EOF

    cat > "$target_home/.bashrc" << 'EOF'
export PYENV_ROOT="$HOME/.pyenv"
eval "$(pyenv init -)"
EOF

    local old_home="$HOME"
    local old_target_home="${TARGET_HOME:-}"
    local old_pyenv_root="${PYENV_ROOT:-}"
    HOME="$current_home"
    TARGET_HOME="$target_home"
    PYENV_ROOT="$current_home/.pyenv"

    local result
    result=$(autofix_pyenv_check)

    HOME="$old_home"
    [[ -n "$old_target_home" ]] && TARGET_HOME="$old_target_home" || unset TARGET_HOME
    [[ -n "$old_pyenv_root" ]] && PYENV_ROOT="$old_pyenv_root" || unset PYENV_ROOT

    local first_root=""
    local first_config=""
    first_root=$(echo "$result" | jq -r '.pyenv_roots[0] // empty')
    first_config=$(echo "$result" | jq -r '.shell_configs[0] // empty')

    cleanup_test_dir "$test_dir"

    if [[ "$first_root" != "$target_home/.pyenv" ]]; then
        test_fail "pyenv_check_prefers_target_home_over_poisoned_home" "Expected target-home pyenv root, got '$first_root'"
        return
    fi

    if [[ "$first_config" != "$target_home/.bashrc" ]]; then
        test_fail "pyenv_check_prefers_target_home_over_poisoned_home" "Expected target-home bashrc, got '$first_config'"
        return
    fi

    test_pass "pyenv_check_prefers_target_home_over_poisoned_home"
}

test_pyenv_check_ignores_poisoned_xdg_data_home() {
    local test_id="pyenv_xdg_data_home"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    local current_home="$test_dir/current-home"
    local target_home="$test_dir/target-home"
    mkdir -p "$current_home/.local/share/pyenv" "$target_home/.local/share/pyenv"

    local old_home="$HOME"
    local old_target_home="${TARGET_HOME:-}"
    local old_xdg_data_home="${XDG_DATA_HOME:-}"
    local old_pyenv_root="${PYENV_ROOT:-}"
    HOME="$current_home"
    TARGET_HOME="$target_home"
    XDG_DATA_HOME="$current_home/.local/share"
    unset PYENV_ROOT

    local result
    result=$(autofix_pyenv_check)

    HOME="$old_home"
    [[ -n "$old_target_home" ]] && TARGET_HOME="$old_target_home" || unset TARGET_HOME
    [[ -n "$old_xdg_data_home" ]] && XDG_DATA_HOME="$old_xdg_data_home" || unset XDG_DATA_HOME
    [[ -n "$old_pyenv_root" ]] && PYENV_ROOT="$old_pyenv_root" || unset PYENV_ROOT

    local first_root=""
    first_root=$(echo "$result" | jq -r '.pyenv_roots[0] // empty')

    cleanup_test_dir "$test_dir"

    if [[ "$first_root" != "$target_home/.local/share/pyenv" ]]; then
        test_fail "pyenv_check_ignores_poisoned_xdg_data_home" "Expected target-home XDG pyenv root, got '$first_root'"
        return
    fi

    test_pass "pyenv_check_ignores_poisoned_xdg_data_home"
}

# Test: Pyenv dry-run mode
test_pyenv_fix_dry_run() {
    local test_id="pyenv_fix_dry"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    mkdir -p "$test_dir/.pyenv"

    cat > "$test_dir/.bashrc" << 'EOF'
export PYENV_ROOT="$HOME/.pyenv"
eval "$(pyenv init -)"
EOF

    local old_home="$HOME"
    HOME="$test_dir"
    unset PYENV_ROOT

    # Run dry-run
    local output
    output=$(autofix_pyenv_fix "dry-run" 2>&1)

    # Directory should still exist
    if [[ ! -d "$test_dir/.pyenv" ]]; then
        HOME="$old_home"
        cleanup_test_dir "$test_dir"
        test_fail "pyenv_fix_dry_run" "Directory was removed in dry-run mode"
        return
    fi

    # Config should be unchanged
    if ! grep -q "PYENV_ROOT" "$test_dir/.bashrc"; then
        HOME="$old_home"
        cleanup_test_dir "$test_dir"
        test_fail "pyenv_fix_dry_run" "Config was modified in dry-run mode"
        return
    fi

    HOME="$old_home"
    cleanup_test_dir "$test_dir"

    test_pass "pyenv_fix_dry_run"
}

test_pyenv_fix_manages_session_and_records_changes() {
    local test_id="pyenv_fix_live"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    local state_dir="$test_dir/state"
    mkdir -p "$test_dir/.pyenv"

    cat > "$test_dir/.bashrc" << 'EOF'
export PYENV_ROOT="$HOME/.pyenv"
eval "$(pyenv init -)"
EOF

    local old_home="$HOME"
    local old_pyenv_root="${PYENV_ROOT:-}"
    HOME="$test_dir"
    unset PYENV_ROOT
    setup_autofix_state_dir "$state_dir"

    if ! autofix_pyenv_fix "fix" >/dev/null 2>&1; then
        HOME="$old_home"
        [[ -n "$old_pyenv_root" ]] && PYENV_ROOT="$old_pyenv_root" || unset PYENV_ROOT
        cleanup_test_dir "$test_dir"
        test_fail "pyenv_fix_manages_session_and_records_changes" "standalone pyenv fix failed"
        return
    fi

    if [[ -d "$test_dir/.pyenv" ]]; then
        HOME="$old_home"
        [[ -n "$old_pyenv_root" ]] && PYENV_ROOT="$old_pyenv_root" || unset PYENV_ROOT
        cleanup_test_dir "$test_dir"
        test_fail "pyenv_fix_manages_session_and_records_changes" "pyenv directory was not removed"
        return
    fi

    if grep -q "PYENV_ROOT\\|pyenv init" "$test_dir/.bashrc"; then
        HOME="$old_home"
        [[ -n "$old_pyenv_root" ]] && PYENV_ROOT="$old_pyenv_root" || unset PYENV_ROOT
        cleanup_test_dir "$test_dir"
        test_fail "pyenv_fix_manages_session_and_records_changes" "pyenv shell config entries were not removed"
        return
    fi

    if [[ -f "$ACFS_STATE_DIR/.session" ]]; then
        HOME="$old_home"
        [[ -n "$old_pyenv_root" ]] && PYENV_ROOT="$old_pyenv_root" || unset PYENV_ROOT
        cleanup_test_dir "$test_dir"
        test_fail "pyenv_fix_manages_session_and_records_changes" "session marker was left behind after standalone pyenv fix"
        return
    fi

    if [[ "$(jq -r 'select(.category == "pyenv") | .category' "$ACFS_CHANGES_FILE" | wc -l | tr -d ' ')" -lt 2 ]]; then
        HOME="$old_home"
        [[ -n "$old_pyenv_root" ]] && PYENV_ROOT="$old_pyenv_root" || unset PYENV_ROOT
        cleanup_test_dir "$test_dir"
        test_fail "pyenv_fix_manages_session_and_records_changes" "expected pyenv changes were not recorded"
        return
    fi

    HOME="$old_home"
    [[ -n "$old_pyenv_root" ]] && PYENV_ROOT="$old_pyenv_root" || unset PYENV_ROOT
    cleanup_test_dir "$test_dir"
    test_pass "pyenv_fix_manages_session_and_records_changes"
}

test_pyenv_fix_restores_state_when_record_change_fails() {
    local test_id="pyenv_fix_restore_on_journal_failure"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    local state_dir="$test_dir/state"
    mkdir -p "$test_dir/.pyenv"

    cat > "$test_dir/.bashrc" << 'EOF'
export PYENV_ROOT="$HOME/.pyenv"
eval "$(pyenv init -)"
EOF

    local old_home="$HOME"
    local old_pyenv_root="${PYENV_ROOT:-}"
    HOME="$test_dir"
    unset PYENV_ROOT
    setup_autofix_state_dir "$state_dir"

    record_change() {
        return 1
    }

    if autofix_pyenv_fix "fix" >/dev/null 2>&1; then
        HOME="$old_home"
        [[ -n "$old_pyenv_root" ]] && PYENV_ROOT="$old_pyenv_root" || unset PYENV_ROOT
        cleanup_test_dir "$test_dir"
        test_fail "pyenv_fix_restores_state_when_record_change_fails" "pyenv fix unexpectedly succeeded when journaling failed"
        return
    fi

    if [[ ! -d "$test_dir/.pyenv" ]]; then
        HOME="$old_home"
        [[ -n "$old_pyenv_root" ]] && PYENV_ROOT="$old_pyenv_root" || unset PYENV_ROOT
        cleanup_test_dir "$test_dir"
        test_fail "pyenv_fix_restores_state_when_record_change_fails" "pyenv directory was not restored after journaling failure"
        return
    fi

    if ! grep -q "PYENV_ROOT\\|pyenv init" "$test_dir/.bashrc"; then
        HOME="$old_home"
        [[ -n "$old_pyenv_root" ]] && PYENV_ROOT="$old_pyenv_root" || unset PYENV_ROOT
        cleanup_test_dir "$test_dir"
        test_fail "pyenv_fix_restores_state_when_record_change_fails" "pyenv shell config was not restored after journaling failure"
        return
    fi

    if [[ -s "$ACFS_CHANGES_FILE" ]]; then
        HOME="$old_home"
        [[ -n "$old_pyenv_root" ]] && PYENV_ROOT="$old_pyenv_root" || unset PYENV_ROOT
        cleanup_test_dir "$test_dir"
        test_fail "pyenv_fix_restores_state_when_record_change_fails" "pyenv journaling failure still left change records behind"
        return
    fi

    HOME="$old_home"
    [[ -n "$old_pyenv_root" ]] && PYENV_ROOT="$old_pyenv_root" || unset PYENV_ROOT
    cleanup_test_dir "$test_dir"
    test_pass "pyenv_fix_restores_state_when_record_change_fails"
}

# ============================================================
# Combined Tests
# ============================================================

# Test: Combined check returns expected structure
test_combined_check_structure() {
    local test_id="combined_check"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    mkdir -p "$test_dir"

    local old_home="$HOME"
    HOME="$test_dir"
    unset NVM_DIR PYENV_ROOT

    local result
    result=$(autofix_version_managers_check)

    HOME="$old_home"
    cleanup_test_dir "$test_dir"

    # Verify structure
    if ! echo "$result" | jq -e '.nvm' >/dev/null 2>&1; then
        test_fail "combined_check_structure" "Missing nvm key"
        return
    fi

    if ! echo "$result" | jq -e '.pyenv' >/dev/null 2>&1; then
        test_fail "combined_check_structure" "Missing pyenv key"
        return
    fi

    # Use 'has' to check for key presence since has_conflicts may be false
    if ! echo "$result" | jq -e 'has("has_conflicts")' >/dev/null 2>&1; then
        test_fail "combined_check_structure" "Missing has_conflicts key"
        return
    fi

    test_pass "combined_check_structure"
}

test_combined_fix_reuses_single_session() {
    local test_id="combined_fix_live"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    local state_dir="$test_dir/state"
    mkdir -p "$test_dir/.nvm" "$test_dir/.pyenv"

    cat > "$test_dir/.bashrc" << 'EOF'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
export PYENV_ROOT="$HOME/.pyenv"
eval "$(pyenv init -)"
EOF

    local old_home="$HOME"
    local old_nvm_dir="${NVM_DIR:-}"
    local old_pyenv_root="${PYENV_ROOT:-}"
    HOME="$test_dir"
    unset NVM_DIR PYENV_ROOT
    setup_autofix_state_dir "$state_dir"

    if ! autofix_version_managers_fix "fix" >/dev/null 2>&1; then
        HOME="$old_home"
        [[ -n "$old_nvm_dir" ]] && NVM_DIR="$old_nvm_dir" || unset NVM_DIR
        [[ -n "$old_pyenv_root" ]] && PYENV_ROOT="$old_pyenv_root" || unset PYENV_ROOT
        cleanup_test_dir "$test_dir"
        test_fail "combined_fix_reuses_single_session" "combined fix failed"
        return
    fi

    local session_count
    session_count=$(jq -r '.session_id' "$ACFS_CHANGES_FILE" | sort -u | sed '/^null$/d;/^$/d' | wc -l | tr -d ' ')
    if [[ "$session_count" != "1" ]]; then
        HOME="$old_home"
        [[ -n "$old_nvm_dir" ]] && NVM_DIR="$old_nvm_dir" || unset NVM_DIR
        [[ -n "$old_pyenv_root" ]] && PYENV_ROOT="$old_pyenv_root" || unset PYENV_ROOT
        cleanup_test_dir "$test_dir"
        test_fail "combined_fix_reuses_single_session" "expected one shared session id, got $session_count"
        return
    fi

    if [[ -f "$ACFS_STATE_DIR/.session" ]]; then
        HOME="$old_home"
        [[ -n "$old_nvm_dir" ]] && NVM_DIR="$old_nvm_dir" || unset NVM_DIR
        [[ -n "$old_pyenv_root" ]] && PYENV_ROOT="$old_pyenv_root" || unset PYENV_ROOT
        cleanup_test_dir "$test_dir"
        test_fail "combined_fix_reuses_single_session" "session marker was left behind after combined fix"
        return
    fi

    HOME="$old_home"
    [[ -n "$old_nvm_dir" ]] && NVM_DIR="$old_nvm_dir" || unset NVM_DIR
    [[ -n "$old_pyenv_root" ]] && PYENV_ROOT="$old_pyenv_root" || unset PYENV_ROOT
    cleanup_test_dir "$test_dir"
    test_pass "combined_fix_reuses_single_session"
}

test_combined_fix_completes_recovery_path_under_errexit() {
    local test_id="combined_fix_errexit"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    local marker="$test_dir/calls"
    local status=0
    mkdir -p "$test_dir"

    TEST_AUTOFIX_MARKER="$marker" /bin/bash -c '
        source "$1"
        autofix_ensure_session() {
            printf -v "$1" "%s" true
        }
        autofix_nvm_fix() {
            printf "nvm\n" >> "$TEST_AUTOFIX_MARKER"
            return 1
        }
        autofix_pyenv_fix() {
            printf "pyenv\n" >> "$TEST_AUTOFIX_MARKER"
            return 0
        }
        autofix_finalize_managed_session() {
            printf "finalize:%s\n" "$1" >> "$TEST_AUTOFIX_MARKER"
            return 0
        }
        set -e
        autofix_version_managers_fix fix
    ' _ "$SCRIPT_DIR/autofix_version_managers.sh" >/dev/null 2>&1 || status=$?

    if [[ "$status" != "1" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "combined_fix_completes_recovery_path_under_errexit" "Expected partial-failure status 1, got $status"
        return
    fi

    if [[ "$(cat "$marker" 2>/dev/null || true)" != $'nvm\npyenv\nfinalize:true' ]]; then
        local calls
        calls="$(cat "$marker" 2>/dev/null || true)"
        cleanup_test_dir "$test_dir"
        test_fail "combined_fix_completes_recovery_path_under_errexit" "Recovery path stopped early: ${calls:-<empty>}"
        return
    fi

    cleanup_test_dir "$test_dir"
    test_pass "combined_fix_completes_recovery_path_under_errexit"
}

test_restore_ignores_poisoned_path_bash() {
    local test_id="restore_trusted_bash"
    local test_dir="/tmp/test_autofix_${test_id}_$$"
    local fake_bin="$test_dir/fake-bin"
    local restored_marker="$test_dir/restored"
    local poisoned_marker="$test_dir/poisoned"
    local touch_bin=""
    local restore_command=""
    mkdir -p "$fake_bin"

    cat > "$fake_bin/bash" <<EOF
#!/bin/bash
printf 'poisoned\n' > "$poisoned_marker"
exit 97
EOF
    chmod +x "$fake_bin/bash"

    touch_bin="$(autofix_system_binary_path touch 2>/dev/null || true)"
    printf -v restore_command '%q %q' "$touch_bin" "$restored_marker"

    if ! PATH="$fake_bin:$PATH" autofix_version_managers_restore "$restore_command"; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_ignores_poisoned_path_bash" "Trusted restore command failed"
        return
    fi

    if [[ ! -f "$restored_marker" || -e "$poisoned_marker" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_ignores_poisoned_path_bash" "Restore selected the caller-controlled bash"
        return
    fi

    cleanup_test_dir "$test_dir"
    test_pass "restore_ignores_poisoned_path_bash"
}

# ============================================================
# Main Test Runner
# ============================================================

main() {
    unset TARGET_HOME TARGET_USER SUDO_USER

    echo "============================================="
    echo "Running autofix_version_managers.sh unit tests"
    echo "============================================="

    # NVM tests
    test_nvm_check_no_installation
    test_nvm_check_env_set
    test_nvm_check_shell_configs
    test_nvm_check_prefers_target_home_over_poisoned_home
    test_nvm_check_ignores_poisoned_xdg_config_home
    test_nvm_fix_dry_run
    test_nvm_fix_manages_session_and_records_changes
    test_nvm_fix_restores_state_when_record_change_fails

    # Pyenv tests
    test_pyenv_check_no_installation
    test_pyenv_check_env_set
    test_pyenv_check_shell_configs
    test_pyenv_check_prefers_target_home_over_poisoned_home
    test_pyenv_check_ignores_poisoned_xdg_data_home
    test_pyenv_fix_dry_run
    test_pyenv_fix_manages_session_and_records_changes
    test_pyenv_fix_restores_state_when_record_change_fails

    # Combined tests
    test_combined_check_structure
    test_combined_fix_reuses_single_session
    test_combined_fix_completes_recovery_path_under_errexit
    test_restore_ignores_poisoned_path_bash

    echo "============================================="
    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi

    echo "All tests passed!"
    exit 0
}

main "$@"
