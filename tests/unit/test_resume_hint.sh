#!/usr/bin/env bash
# shellcheck disable=SC2317,SC2034
# ============================================================
# Unit tests for resume hint generation (bd-31ps.9.2)
#
# Tests that generate_resume_hint() produces correct commands
# with various flag combinations.
#
# Run with: bash tests/unit/test_resume_hint.sh
# ============================================================

set -uo pipefail

# Get the absolute path to the repo root
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

# Log file
LOG_FILE="/tmp/acfs_resume_hint_test_$(date +%Y%m%d_%H%M%S).log"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================
# Test Helpers
# ============================================================

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

test_pass() {
    ((TESTS_PASSED++))
    log "PASS: $1"
}

test_fail() {
    ((TESTS_FAILED++))
    log "FAIL: $1"
    [[ -n "${2:-}" ]] && log "  Reason: $2"
}

run_test() {
    local test_name="$1"
    ((TESTS_RUN++))
    log ""
    log "Running: $test_name..."
    if "$test_name"; then
        test_pass "$test_name"
    else
        test_fail "$test_name"
    fi
}

# ============================================================
# Mock functions and setup
# ============================================================

# Stub log functions so sourcing install.sh doesn't fail
log_info() { :; }
log_warn() { :; }
log_error() { :; }
log_detail() { :; }
log_fatal() {
    printf 'fatal: %s\n' "$*" >&2
    exit 1
}

# Source just the generate_resume_hint function from install.sh
# We extract it rather than sourcing the full install.sh to avoid side effects
extract_resume_hint_function() {
    # Extract the generate_resume_hint function from install.sh
    sed -n '/^generate_resume_hint()/,/^}$/p' "$REPO_ROOT/install.sh"
}

extract_print_resume_hint_function() {
    sed -n '/^print_resume_hint()/,/^}$/p' "$REPO_ROOT/install.sh"
}

extract_normalize_read_only_modes_function() {
    sed -n '/^normalize_read_only_modes()/,/^}$/p' "$REPO_ROOT/install.sh"
}

extract_parse_args_function() {
    sed -n '/^parse_args()/,/^}$/p' "$REPO_ROOT/install.sh"
}

extract_ref_arg_value_helper() {
    sed -n '/^acfs_require_ref_arg_value()/,/^}$/p' "$REPO_ROOT/install.sh"
}

extract_verified_installer_cache_dir_helper() {
    sed -n '/^acfs_resolve_verified_installer_cache_dir()/,/^}$/p' "$REPO_ROOT/install.sh"
}

extract_verified_installer_cache_normalizer() {
    sed -n '/^acfs_normalize_verified_installer_cache_configuration()/,/^}$/p' "$REPO_ROOT/install.sh"
}

# Actually, let's just define our test environment and source install.sh functions
setup_test_env() {
    # Reset all variables to defaults
    SCRIPT_DIR=""
    ACFS_COMMIT_SHA_FULL=""
    ACFS_REF_INPUT=""
    ACFS_CHECKSUMS_REF=""
    ACFS_CHECKSUMS_REF_EXPLICIT=false
    MODE="vibe"
    SKIP_POSTGRES=false
    SKIP_VAULT=false
    SKIP_CLOUD=false
    SKIP_PREFLIGHT=false
    SKIP_UBUNTU_UPGRADE=false
    YES_MODE=false
    STRICT_MODE=false
    ACFS_STRICT_MODE=false
    DRY_RUN=false
    PRINT_MODE=false
    AUTO_FIX_MODE="prompt"
    ACFS_VERIFIED_INSTALLER_CACHE=""
}

setup_parse_args_env() {
    setup_test_env
    ACFS_REPO_OWNER="Dicklesworthstone"
    ACFS_REPO_NAME="agentic_coding_flywheel_setup"
    ACFS_REF="main"
    ACFS_REF_INPUT="$ACFS_REF"
    ACFS_RAW="https://raw.githubusercontent.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/${ACFS_REF}"
    ACFS_CHECKSUMS_REF="main"
    ACFS_CHECKSUMS_RAW="https://raw.githubusercontent.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/${ACFS_CHECKSUMS_REF}"
    PIN_REF_MODE=false
    RESET_STATE_ONLY=false
    TARGET_UBUNTU_VERSION="25.10"
    TARGET_UBUNTU_VERSION_EXPLICIT=false
    LIST_MODULES=false
    PRINT_PLAN_MODE=false
    ONLY_MODULES=()
    ONLY_PHASES=()
    SKIP_MODULES=()
    NO_DEPS=false
}

# Source the generate_resume_hint function
# shellcheck disable=SC1090
eval "$(extract_resume_hint_function)"
# shellcheck disable=SC1090
eval "$(extract_print_resume_hint_function)"
# shellcheck disable=SC1090
eval "$(extract_normalize_read_only_modes_function)"
# shellcheck disable=SC1090
eval "$(extract_ref_arg_value_helper)"
# shellcheck disable=SC1090
eval "$(extract_verified_installer_cache_dir_helper)"
# shellcheck disable=SC1090
eval "$(extract_verified_installer_cache_normalizer)"
# shellcheck disable=SC1090
eval "$(extract_parse_args_function)"

STATE_SET_RESUME_HINT_CALLS=0
STATE_SET_RESUME_HINT_VALUE=""

state_set_resume_hint() {
    ((STATE_SET_RESUME_HINT_CALLS++))
    STATE_SET_RESUME_HINT_VALUE="$1"
    return 0
}

# ============================================================
# Tests
# ============================================================

# Test: Basic curl|bash invocation with defaults
test_basic_curl_invocation() {
    setup_test_env

    local result
    result=$(generate_resume_hint "" "")

    # Should contain curl and --resume
    if [[ "$result" != *"curl"* ]]; then
        log "  Expected curl in output, got: $result"
        return 1
    fi

    if [[ "$result" != curl\ -fsSL* ]]; then
        log "  Expected curl resume hint to fail closed with -f, got: $result"
        return 1
    fi

    if [[ "$result" != *"--resume"* ]]; then
        log "  Expected --resume in output, got: $result"
        return 1
    fi

    # Should NOT contain mode flag (default is vibe)
    if [[ "$result" == *"--mode"* ]]; then
        log "  Should not contain --mode (default vibe), got: $result"
        return 1
    fi

    return 0
}

# Test: Local script invocation
test_local_script_invocation() {
    setup_test_env
    SCRIPT_DIR="/some/local/path"

    local result
    result=$(generate_resume_hint "" "")

    # Should use the original local script path, not a cwd-relative fallback
    if [[ "$result" != "bash /some/local/path/install.sh --resume"* ]]; then
        log "  Expected 'bash /some/local/path/install.sh --resume', got: $result"
        return 1
    fi

    return 0
}

# Test: Local script invocation shell-escapes spaces in the path
test_local_script_invocation_with_spaces() {
    setup_test_env
    SCRIPT_DIR="/tmp/acfs local path"

    local result
    result=$(generate_resume_hint "" "")

    if [[ "$result" != "bash /tmp/acfs\\ local\\ path/install.sh --resume"* ]]; then
        log "  Expected shell-escaped install path, got: $result"
        return 1
    fi

    return 0
}

# Test: Pinned to specific commit SHA
test_pinned_commit_sha() {
    setup_test_env
    ACFS_COMMIT_SHA_FULL="abc123def456abc123def456abc123def456abc1"

    local result
    result=$(generate_resume_hint "" "")

    # Should include the full commit SHA in URL
    if [[ "$result" != *"$ACFS_COMMIT_SHA_FULL"* ]]; then
        log "  Expected commit SHA in output, got: $result"
        return 1
    fi
    if [[ "$result" != *"--ref $ACFS_COMMIT_SHA_FULL"* ]]; then
        log "  Expected --ref to pin the same commit SHA, got: $result"
        return 1
    fi

    return 0
}

test_pinned_commit_sha_takes_precedence_over_symbolic_ref() {
    setup_test_env
    ACFS_REF_INPUT="feature-branch"
    ACFS_COMMIT_SHA_FULL="abc123def456abc123def456abc123def456abc1"

    local result
    result=$(generate_resume_hint "" "")

    if [[ "$result" != *"--ref $ACFS_COMMIT_SHA_FULL"* ]]; then
        log "  Expected --ref to use exact commit SHA, got: $result"
        return 1
    fi
    if [[ "$result" == *"--ref feature-branch"* ]]; then
        log "  Expected resume hint not to re-resolve symbolic ref, got: $result"
        return 1
    fi

    return 0
}

test_pinned_commit_sha_preserves_symbolic_checksum_ref() {
    setup_test_env
    ACFS_REF_INPUT="feature-branch"
    ACFS_CHECKSUMS_REF="feature-branch"
    ACFS_COMMIT_SHA_FULL="abc123def456abc123def456abc123def456abc1"

    local result
    result=$(generate_resume_hint "" "")

    if [[ "$result" != *"--ref $ACFS_COMMIT_SHA_FULL"* ]]; then
        log "  Expected --ref to use exact commit SHA, got: $result"
        return 1
    fi
    if [[ "$result" != *"--checksums-ref feature-branch"* ]]; then
        log "  Expected resume hint to preserve branch checksum metadata, got: $result"
        return 1
    fi

    return 0
}

# Test: Custom ACFS_REF (branch/tag)
test_custom_ref() {
    setup_test_env
    ACFS_REF_INPUT="v1.2.3"

    local result
    result=$(generate_resume_hint "" "")

    # Should include the ref in URL
    if [[ "$result" != *"v1.2.3"* ]]; then
        log "  Expected ref v1.2.3 in output, got: $result"
        return 1
    fi

    return 0
}

# Test: Custom ACFS_REF is shell-escaped in copy-paste resume hints
test_custom_ref_shell_escaped() {
    setup_test_env
    ACFS_REF_INPUT='bad;touch /tmp/acfs-pwned #'

    local result
    result=$(generate_resume_hint "" "")

    if [[ "$result" == *"bad;touch"* ]]; then
        log "  Expected escaped ref in output, got raw shell metacharacters: $result"
        return 1
    fi

    if [[ "$result" != *"bad\\;touch"* ]]; then
        log "  Expected shell-escaped semicolon in output, got: $result"
        return 1
    fi

    if [[ "$result" != *"--ref bad\\;touch"* ]]; then
        log "  Expected --ref value to be escaped, got: $result"
        return 1
    fi

    return 0
}

test_checksums_ref_survives_ref_parse_order() {
    setup_parse_args_env
    parse_args --checksums-ref explicit-checksums --ref feature-branch --print-plan

    if [[ "$ACFS_CHECKSUMS_REF" != "explicit-checksums" ]]; then
        log "  Expected explicit checksums ref to survive later --ref, got: $ACFS_CHECKSUMS_REF"
        return 1
    fi
    if [[ "$ACFS_CHECKSUMS_REF_EXPLICIT" != "true" ]]; then
        log "  Expected ACFS_CHECKSUMS_REF_EXPLICIT=true, got: $ACFS_CHECKSUMS_REF_EXPLICIT"
        return 1
    fi

    setup_parse_args_env
    parse_args --ref feature-branch --checksums-ref explicit-checksums --print-plan

    if [[ "$ACFS_CHECKSUMS_REF" != "explicit-checksums" ]]; then
        log "  Expected explicit checksums ref to apply after --ref, got: $ACFS_CHECKSUMS_REF"
        return 1
    fi

    return 0
}

test_verified_installer_cache_parse_forms() {
    setup_parse_args_env
    parse_args --verified-installer-cache "cache parent" --print-plan
    if [[ "$ACFS_VERIFIED_INSTALLER_CACHE" != "cache parent" ]]; then
        log "  Expected split cache flag value, got: $ACFS_VERIFIED_INSTALLER_CACHE"
        return 1
    fi

    setup_parse_args_env
    parse_args --verified-installer-cache="cache root" --print-plan
    if [[ "$ACFS_VERIFIED_INSTALLER_CACHE" != "cache root" ]]; then
        log "  Expected equals cache flag value, got: $ACFS_VERIFIED_INSTALLER_CACHE"
        return 1
    fi

    return 0
}

test_obsolete_offline_pack_flag_is_rejected() {
    if (setup_parse_args_env; parse_args --offline-pack /tmp/obsolete); then
        log "  Expected obsolete --offline-pack to fail closed"
        return 1
    fi

    return 0
}

test_custom_checksums_ref_resume_hint() {
    setup_test_env
    SCRIPT_DIR="/some/local/path"
    ACFS_REF_INPUT="feature-branch"
    ACFS_CHECKSUMS_REF='checksums;touch /tmp/acfs-pwned #'
    ACFS_CHECKSUMS_REF_EXPLICIT=true

    local result
    result=$(generate_resume_hint "" "")

    if [[ "$result" != *"--checksums-ref checksums\\;touch"* ]]; then
        log "  Expected shell-escaped --checksums-ref in resume hint, got: $result"
        return 1
    fi

    if [[ "$result" == *"checksums;touch"* ]]; then
        log "  Expected checksum ref metacharacters to be escaped, got: $result"
        return 1
    fi

    return 0
}

test_verified_installer_cache_parent_is_normalized_for_resume_hint() {
    setup_test_env

    local temp_root=""
    local old_pwd=""
    local result=""
    local expected_cache=""
    local expected_cache_q=""

    temp_root="$(mktemp -d "${TMPDIR:-/tmp}/acfs-resume-cache.XXXXXX")" || return 1
    mkdir -p "$temp_root/work/cache with spaces/acfs-installer-cache" || return 1
    printf '{}\n' > "$temp_root/work/cache with spaces/acfs-installer-cache/manifest.json" || return 1

    old_pwd="$PWD"
    cd "$temp_root/work" || return 1
    ACFS_VERIFIED_INSTALLER_CACHE="cache with spaces"
    acfs_normalize_verified_installer_cache_configuration || {
        cd "$old_pwd" || true
        return 1
    }
    cd "$old_pwd" || return 1

    expected_cache="$temp_root/work/cache with spaces/acfs-installer-cache"
    if [[ "$ACFS_VERIFIED_INSTALLER_CACHE" != "$expected_cache" ]]; then
        log "  Expected ACFS_VERIFIED_INSTALLER_CACHE=$expected_cache, got: $ACFS_VERIFIED_INSTALLER_CACHE"
        return 1
    fi

    result="$(generate_resume_hint "" "")"
    printf -v expected_cache_q '%q' "$expected_cache"
    if [[ "$result" != *"--verified-installer-cache $expected_cache_q"* ]]; then
        log "  Expected canonical --verified-installer-cache in resume hint, got: $result"
        return 1
    fi

    return 0
}

# Test: Safe mode
test_safe_mode() {
    setup_test_env
    MODE="safe"

    local result
    result=$(generate_resume_hint "" "")

    if [[ "$result" != *"--mode safe"* ]]; then
        log "  Expected --mode safe in output, got: $result"
        return 1
    fi

    return 0
}

# Test: Skip flags
test_skip_flags() {
    setup_test_env
    SKIP_POSTGRES=true
    SKIP_VAULT=true

    local result
    result=$(generate_resume_hint "" "")

    if [[ "$result" != *"--skip-postgres"* ]]; then
        log "  Expected --skip-postgres in output, got: $result"
        return 1
    fi

    if [[ "$result" != *"--skip-vault"* ]]; then
        log "  Expected --skip-vault in output, got: $result"
        return 1
    fi

    return 0
}

# Test: All skip flags
test_all_skip_flags() {
    setup_test_env
    SKIP_POSTGRES=true
    SKIP_VAULT=true
    SKIP_CLOUD=true
    SKIP_PREFLIGHT=true
    SKIP_UBUNTU_UPGRADE=true

    local result
    result=$(generate_resume_hint "" "")

    for flag in --skip-postgres --skip-vault --skip-cloud --skip-preflight --skip-ubuntu-upgrade; do
        if [[ "$result" != *"$flag"* ]]; then
            log "  Expected $flag in output, got: $result"
            return 1
        fi
    done

    return 0
}

# Test: YES_MODE flag
test_yes_mode() {
    setup_test_env
    YES_MODE=true

    local result
    result=$(generate_resume_hint "" "")

    if [[ "$result" != *"--yes"* ]]; then
        log "  Expected --yes in output, got: $result"
        return 1
    fi

    return 0
}

# Test: STRICT_MODE flag
test_strict_mode() {
    setup_test_env
    STRICT_MODE=true

    local result
    result=$(generate_resume_hint "" "")

    if [[ "$result" != *"--strict"* ]]; then
        log "  Expected --strict in output, got: $result"
        return 1
    fi

    return 0
}

# Test: strict mode set by parse_args runtime flag
test_acfs_strict_mode() {
    setup_test_env
    ACFS_STRICT_MODE=true

    local result
    result=$(generate_resume_hint "" "")

    if [[ "$result" != *"--strict"* ]]; then
        log "  Expected --strict from ACFS_STRICT_MODE in output, got: $result"
        return 1
    fi

    return 0
}

# Test: Complex combination
test_complex_combination() {
    setup_test_env
    MODE="safe"
    SKIP_POSTGRES=true
    SKIP_CLOUD=true
    YES_MODE=true
    ACFS_REF_INPUT="develop"

    local result
    result=$(generate_resume_hint "languages" "install_rust")

    # Check all expected flags
    if [[ "$result" != *"--resume"* ]]; then
        log "  Expected --resume, got: $result"
        return 1
    fi

    if [[ "$result" != *"--mode safe"* ]]; then
        log "  Expected --mode safe, got: $result"
        return 1
    fi

    if [[ "$result" != *"--skip-postgres"* ]]; then
        log "  Expected --skip-postgres, got: $result"
        return 1
    fi

    if [[ "$result" != *"--skip-cloud"* ]]; then
        log "  Expected --skip-cloud, got: $result"
        return 1
    fi

    if [[ "$result" != *"--yes"* ]]; then
        log "  Expected --yes, got: $result"
        return 1
    fi

    if [[ "$result" != *"develop"* ]]; then
        log "  Expected 'develop' ref, got: $result"
        return 1
    fi

    return 0
}

# Test: Main branch uses acfs.sh shorthand
test_main_branch_shorthand() {
    setup_test_env
    ACFS_REF_INPUT="main"

    local result
    result=$(generate_resume_hint "" "")

    # Should use acfs.sh shorthand for main branch
    if [[ "$result" != *"acfs.sh"* ]]; then
        log "  Expected acfs.sh shorthand for main branch, got: $result"
        return 1
    fi

    return 0
}

# Test: Empty ACFS_REF uses acfs.sh shorthand
test_empty_ref_shorthand() {
    setup_test_env
    ACFS_REF_INPUT=""

    local result
    result=$(generate_resume_hint "" "")

    # Should use acfs.sh shorthand
    if [[ "$result" != *"acfs.sh"* ]]; then
        log "  Expected acfs.sh shorthand, got: $result"
        return 1
    fi

    return 0
}

# Test: print_resume_hint uses the state helper instead of rewriting state directly
test_print_resume_hint_uses_state_helper() {
    setup_test_env
    YES_MODE=true
    ACFS_STATE_FILE="$(mktemp)"
    printf '{}\n' > "$ACFS_STATE_FILE"
    STATE_SET_RESUME_HINT_CALLS=0
    STATE_SET_RESUME_HINT_VALUE=""

    print_resume_hint "languages" "install_rust"

    if [[ "$STATE_SET_RESUME_HINT_CALLS" -ne 1 ]]; then
        log "  Expected state_set_resume_hint to be called once, got: $STATE_SET_RESUME_HINT_CALLS"
        rm -f "$ACFS_STATE_FILE"
        return 1
    fi

    if [[ "$STATE_SET_RESUME_HINT_VALUE" != *"--resume"* ]]; then
        log "  Expected generated resume hint to include --resume, got: $STATE_SET_RESUME_HINT_VALUE"
        rm -f "$ACFS_STATE_FILE"
        return 1
    fi

    if [[ "$STATE_SET_RESUME_HINT_VALUE" != *"--yes"* ]]; then
        log "  Expected generated resume hint to include --yes, got: $STATE_SET_RESUME_HINT_VALUE"
        rm -f "$ACFS_STATE_FILE"
        return 1
    fi

    rm -f "$ACFS_STATE_FILE"
    return 0
}

# Test: print_resume_hint fallback preserves the absolute local installer path
test_print_resume_hint_fallback_uses_absolute_local_path() {
    setup_test_env
    SCRIPT_DIR="/tmp/acfs fallback"
    ACFS_STATE_FILE="$(mktemp)"
    printf '{}\n' > "$ACFS_STATE_FILE"
    STATE_SET_RESUME_HINT_CALLS=0
    STATE_SET_RESUME_HINT_VALUE=""

    generate_resume_hint() { return 1; }
    print_resume_hint "languages" "install_rust"

    if [[ "$STATE_SET_RESUME_HINT_VALUE" != "bash /tmp/acfs\\ fallback/install.sh --resume --yes" ]]; then
        log "  Expected absolute fallback resume hint, got: $STATE_SET_RESUME_HINT_VALUE"
        rm -f "$ACFS_STATE_FILE"
        unset -f generate_resume_hint
        eval "$(extract_resume_hint_function)"
        return 1
    fi

    rm -f "$ACFS_STATE_FILE"
    unset -f generate_resume_hint
    eval "$(extract_resume_hint_function)"
    return 0
}

test_print_resume_hint_fallback_uses_fail_closed_curl() {
    setup_test_env
    ACFS_STATE_FILE="$(mktemp)"
    printf '{}\n' > "$ACFS_STATE_FILE"
    STATE_SET_RESUME_HINT_CALLS=0
    STATE_SET_RESUME_HINT_VALUE=""

    generate_resume_hint() { return 1; }
    print_resume_hint "languages" "install_rust"

    if [[ "$STATE_SET_RESUME_HINT_VALUE" != "curl -q -fsSL https://acfs.sh | bash -s -- --resume --yes" ]]; then
        log "  Expected fail-closed curl fallback resume hint, got: $STATE_SET_RESUME_HINT_VALUE"
        rm -f "$ACFS_STATE_FILE"
        unset -f generate_resume_hint
        eval "$(extract_resume_hint_function)"
        return 1
    fi

    rm -f "$ACFS_STATE_FILE"
    unset -f generate_resume_hint
    eval "$(extract_resume_hint_function)"
    return 0
}

# Test: --dry-run forces auto-fix preview mode instead of mutating mode
test_dry_run_forces_autofix_preview() {
    setup_test_env
    DRY_RUN=true
    AUTO_FIX_MODE="prompt"

    normalize_read_only_modes

    if [[ "$AUTO_FIX_MODE" != "dry-run" ]]; then
        log "  Expected AUTO_FIX_MODE=dry-run for --dry-run, got: $AUTO_FIX_MODE"
        return 1
    fi

    return 0
}

# Test: --print also forces auto-fix preview mode
test_print_mode_forces_autofix_preview() {
    setup_test_env
    PRINT_MODE=true
    AUTO_FIX_MODE="yes"

    normalize_read_only_modes

    if [[ "$AUTO_FIX_MODE" != "dry-run" ]]; then
        log "  Expected AUTO_FIX_MODE=dry-run for --print, got: $AUTO_FIX_MODE"
        return 1
    fi

    return 0
}

# Test: explicit --no-auto-fix is preserved in read-only modes
test_read_only_mode_preserves_no_autofix() {
    setup_test_env
    DRY_RUN=true
    AUTO_FIX_MODE="no"

    normalize_read_only_modes

    if [[ "$AUTO_FIX_MODE" != "no" ]]; then
        log "  Expected AUTO_FIX_MODE=no to be preserved, got: $AUTO_FIX_MODE"
        return 1
    fi

    return 0
}

# ============================================================
# Main
# ============================================================

main() {
    log "============================================================"
    log "ACFS Resume Hint Unit Tests"
    log "============================================================"
    log "Log file: $LOG_FILE"
    log ""

    # Run all tests
    run_test test_basic_curl_invocation
    run_test test_local_script_invocation
    run_test test_local_script_invocation_with_spaces
    run_test test_pinned_commit_sha
    run_test test_pinned_commit_sha_takes_precedence_over_symbolic_ref
    run_test test_pinned_commit_sha_preserves_symbolic_checksum_ref
    run_test test_custom_ref
    run_test test_custom_ref_shell_escaped
    run_test test_checksums_ref_survives_ref_parse_order
    run_test test_verified_installer_cache_parse_forms
    run_test test_obsolete_offline_pack_flag_is_rejected
    run_test test_custom_checksums_ref_resume_hint
    run_test test_verified_installer_cache_parent_is_normalized_for_resume_hint
    run_test test_safe_mode
    run_test test_skip_flags
    run_test test_all_skip_flags
    run_test test_yes_mode
    run_test test_strict_mode
    run_test test_acfs_strict_mode
    run_test test_complex_combination
    run_test test_main_branch_shorthand
    run_test test_empty_ref_shorthand
    run_test test_print_resume_hint_uses_state_helper
    run_test test_print_resume_hint_fallback_uses_absolute_local_path
    run_test test_print_resume_hint_fallback_uses_fail_closed_curl
    run_test test_dry_run_forces_autofix_preview
    run_test test_print_mode_forces_autofix_preview
    run_test test_read_only_mode_preserves_no_autofix

    # Summary
    log ""
    log "============================================================"
    log "Results: $TESTS_PASSED passed, $TESTS_FAILED failed (of $TESTS_RUN)"
    log "Log file: $LOG_FILE"
    log "============================================================"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi

    exit 0
}

main "$@"
